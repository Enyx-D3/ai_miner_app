import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

class PreparedAiExport {
  final String jsonPath;
  final int jsonFileCount;
  final int jsonBytes;
  final List<String> providers;

  const PreparedAiExport({
    required this.jsonPath,
    required this.jsonFileCount,
    required this.jsonBytes,
    required this.providers,
  });
}

class _JsonBounds {
  final int start;
  final int end;

  const _JsonBounds(this.start, this.end);
}

/// Normalizes supported AI conversation exports into the ChatGPT-shaped JSON
/// array consumed by ContextVault, while preserving the original provider in
/// `_brain2_provider` so the canonical Brain2 layer never loses provenance.
///
/// Supported directly:
/// - ChatGPT/OpenAI `mapping` exports and `messages` arrays
/// - Claude `chat_messages` exports
/// - Gemini-style `messages`/`turns` with `role` + `parts`
/// - B2_SOURCE_ENVELOPE v2
/// - Generic OpenAI/Anthropic/Copilot/Poe-style JSON message arrays
///
/// ZIPs may contain more than one supported provider. Irrelevant JSON files
/// are skipped rather than causing the whole import to fail.
class MultiProviderExportExtractor {
  Future<PreparedAiExport> prepare({
    required String inputPath,
    required String inputName,
    required String outputPath,
  }) async {
    final lower = inputName.toLowerCase();
    if (lower.endsWith('.json')) {
      return _prepareJsonFile(
        inputPath: inputPath,
        inputName: inputName,
        outputPath: outputPath,
      );
    }
    if (!lower.endsWith('.zip')) {
      throw StateError('Choose an AI conversation export as .zip or .json.');
    }
    return _prepareZip(
      zipPath: inputPath,
      outputPath: outputPath,
    );
  }

  Future<PreparedAiExport> _prepareJsonFile({
    required String inputPath,
    required String inputName,
    required String outputPath,
  }) async {
    final source = File(inputPath);
    final bytes = await source.readAsBytes();
    final providerHint = _providerHintFromName(inputName);

    // Preserve raw ChatGPT arrays byte-for-byte where possible. This keeps the
    // large-export path as close as possible to the web/browser-digest flow.
    if (_isJsonArrayBytes(bytes) &&
        _looksLikeChatGptBytes(bytes, providerHint)) {
      await source.copy(outputPath);
      return PreparedAiExport(
        jsonPath: outputPath,
        jsonFileCount: 1,
        jsonBytes: bytes.length,
        providers: const ['chatgpt'],
      );
    }

    final out = File(outputPath).openWrite();
    final providers = <String>{};
    var conversations = 0;
    out.add(const [0x5B]);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      for (final conversation in _normalizeRoot(
        decoded,
        providerHint: providerHint,
        sourceName: inputName,
      )) {
        if (conversations > 0) out.add(const [0x2C]);
        out.add(utf8.encode(jsonEncode(conversation)));
        providers.add('${conversation['_brain2_provider'] ?? 'generic'}');
        conversations++;
      }
      out.add(const [0x5D]);
    } finally {
      await out.close();
    }

    if (conversations == 0) {
      throw StateError(
        'No supported AI conversation messages were found. '
        'Supported formats include ChatGPT, Claude, Gemini, B2 SourceEnvelope, '
        'and generic role/content message JSON.',
      );
    }

    return PreparedAiExport(
      jsonPath: outputPath,
      jsonFileCount: 1,
      jsonBytes: await File(outputPath).length(),
      providers: providers.toList()..sort(),
    );
  }

  Future<PreparedAiExport> _prepareZip({
    required String zipPath,
    required String outputPath,
  }) async {
    final input = InputFileStream(zipPath);
    final providers = <String>{};
    var jsonFilesUsed = 0;
    var conversations = 0;
    final out = File(outputPath).openWrite();
    out.add(const [0x5B]);

    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries = archive.files.where((entry) {
        if (!entry.isFile) return false;
        return entry.name.replaceAll('\\', '/').toLowerCase().endsWith('.json');
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      for (final entry in entries) {
        final bytes = _readArchiveEntryBytes(entry);
        final sourceName = entry.name.replaceAll('\\', '/');
        final hint = _providerHintFromName(sourceName);

        if (_isJsonArrayBytes(bytes) && _looksLikeChatGptBytes(bytes, hint)) {
          final bounds = _jsonArrayInnerBounds(bytes, sourceName);
          if (bounds.end > bounds.start) {
            if (conversations > 0) out.add(const [0x2C]);
            out.add(Uint8List.sublistView(bytes, bounds.start, bounds.end));
            final count = _estimateTopLevelArrayObjects(bytes, bounds);
            conversations += math.max(1, count);
            jsonFilesUsed++;
            providers.add('chatgpt');
          }
          entry.clear();
          continue;
        }

        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          var usedThisFile = false;
          for (final conversation in _normalizeRoot(
            decoded,
            providerHint: hint,
            sourceName: sourceName,
          )) {
            if (conversations > 0) out.add(const [0x2C]);
            out.add(utf8.encode(jsonEncode(conversation)));
            providers.add('${conversation['_brain2_provider'] ?? 'generic'}');
            conversations++;
            usedThisFile = true;
          }
          if (usedThisFile) jsonFilesUsed++;
        } catch (_) {
          // A provider export ZIP often contains unrelated JSON files. Ignore
          // those and continue looking for actual conversation data.
        } finally {
          entry.clear();
        }
      }
      out.add(const [0x5D]);
    } finally {
      await out.close();
      input.closeSync();
    }

    if (conversations == 0) {
      try {
        await File(outputPath).delete();
      } catch (_) {}
      throw StateError(
        'No supported AI conversations were found in this export ZIP. '
        'Brain2 AI Miner currently recognizes ChatGPT, Claude, Gemini, '
        'B2 SourceEnvelope, and generic role/content JSON conversations.',
      );
    }

    return PreparedAiExport(
      jsonPath: outputPath,
      jsonFileCount: jsonFilesUsed,
      jsonBytes: await File(outputPath).length(),
      providers: providers.toList()..sort(),
    );
  }
}

Iterable<Map<String, Object?>> _normalizeRoot(
  Object? root, {
  required String? providerHint,
  required String sourceName,
}) sync* {
  if (root is List) {
    for (var i = 0; i < root.length; i++) {
      final item = root[i];
      if (item is! Map) continue;
      final normalized = _normalizeConversation(
        item.cast<String, Object?>(),
        providerHint: providerHint,
        sourceName: sourceName,
        index: i,
      );
      if (normalized != null) yield normalized;
    }
    return;
  }

  if (root is! Map) return;
  final map = root.cast<String, Object?>();

  if ('${map['format'] ?? ''}'.toUpperCase() == 'B2_SOURCE_ENVELOPE') {
    final normalized = _normalizeB2Envelope(map, sourceName: sourceName);
    if (normalized != null) yield normalized;
    return;
  }

  for (final key in const ['conversations', 'chats', 'threads', 'items']) {
    final nested = map[key];
    if (nested is! List) continue;
    for (var i = 0; i < nested.length; i++) {
      final item = nested[i];
      if (item is! Map) continue;
      final normalized = _normalizeConversation(
        item.cast<String, Object?>(),
        providerHint: providerHint ?? _providerFromRoot(map),
        sourceName: sourceName,
        index: i,
      );
      if (normalized != null) yield normalized;
    }
    return;
  }

  final normalized = _normalizeConversation(
    map,
    providerHint: providerHint ?? _providerFromRoot(map),
    sourceName: sourceName,
    index: 0,
  );
  if (normalized != null) yield normalized;
}

Map<String, Object?>? _normalizeConversation(
  Map<String, Object?> conversation, {
  required String? providerHint,
  required String sourceName,
  required int index,
}) {
  if ('${conversation['format'] ?? ''}'.toUpperCase() == 'B2_SOURCE_ENVELOPE') {
    return _normalizeB2Envelope(conversation, sourceName: sourceName);
  }

  final provider = _detectProvider(conversation, providerHint);

  // ChatGPT already has exactly the structure ContextVault expects. Preserve
  // it and add only provenance metadata used by the canonical importer.
  if (conversation['mapping'] is Map) {
    return <String, Object?>{
      ...conversation,
      '_brain2_provider': provider == 'generic' ? 'chatgpt' : provider,
      '_brain2_source_name': sourceName,
    };
  }

  final rawMessages = _conversationMessages(conversation, provider);
  if (rawMessages.isEmpty) return null;

  final title = _firstString(conversation, const [
        'title',
        'name',
        'subject',
        'conversation_title',
      ]) ??
      'Conversation ${index + 1}';
  final externalId = _firstString(conversation, const [
        'id',
        'uuid',
        'conversation_id',
        'conversationId',
        'thread_id',
        'threadId',
      ]) ??
      '$provider:$sourceName:${index + 1}:$title';

  final normalizedMessages = <Map<String, Object?>>[];
  var sequence = 0;
  for (final raw in rawMessages) {
    final normalized = _normalizeMessage(
      raw,
      provider: provider,
      conversationId: externalId,
      sequence: sequence,
    );
    if (normalized == null) continue;
    normalizedMessages.add({'message': normalized});
    sequence++;
  }
  if (normalizedMessages.isEmpty) return null;

  return <String, Object?>{
    '_brain2_provider': provider,
    '_brain2_source_name': sourceName,
    'id': externalId,
    'title': title,
    'create_time': _firstValue(conversation, const [
      'create_time',
      'created_at',
      'createdAt',
      'start_time',
      'time',
    ]),
    'update_time': _firstValue(conversation, const [
      'update_time',
      'updated_at',
      'updatedAt',
      'last_updated',
    ]),
    'messages': normalizedMessages,
  }..removeWhere((key, value) => value == null);
}

Map<String, Object?>? _normalizeB2Envelope(
  Map<String, Object?> envelope, {
  required String sourceName,
}) {
  final provider = _normalizeProvider('${envelope['provider'] ?? 'generic'}');
  final rawMessages = envelope['messages'];
  if (rawMessages is! List) return null;
  final externalId =
      '${envelope['conversationExternalId'] ?? 'b2-conversation'}';
  final normalizedMessages = <Map<String, Object?>>[];
  var sequence = 0;
  for (final item in rawMessages) {
    if (item is! Map) continue;
    final normalized = _normalizeMessage(
      item.cast<String, Object?>(),
      provider: provider,
      conversationId: externalId,
      sequence: sequence,
    );
    if (normalized == null) continue;
    normalizedMessages.add({'message': normalized});
    sequence++;
  }
  if (normalizedMessages.isEmpty) return null;
  return {
    '_brain2_provider': provider,
    '_brain2_source_name': '${envelope['sourceLabel'] ?? sourceName}',
    'id': externalId,
    'title': '${envelope['conversationTitle'] ?? 'Conversation'}',
    'messages': normalizedMessages,
  };
}

List<Map<String, Object?>> _conversationMessages(
  Map<String, Object?> conversation,
  String provider,
) {
  Object? value;
  if (provider == 'claude' && conversation['chat_messages'] is List) {
    value = conversation['chat_messages'];
  } else {
    value = conversation['messages'] ??
        conversation['chat_messages'] ??
        conversation['turns'] ??
        conversation['entries'];
  }
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}

Map<String, Object?>? _normalizeMessage(
  Map<String, Object?> raw, {
  required String provider,
  required String conversationId,
  required int sequence,
}) {
  final wrapped = raw['message'];
  final message = wrapped is Map ? wrapped.cast<String, Object?>() : raw;

  final text = _extractText(message);
  if (text.trim().isEmpty) return null;

  final rawRole = _firstString(message, const [
        'role',
        'sender',
        'author',
        'speaker',
        'from',
      ]) ??
      _nestedAuthorRole(message) ??
      'unknown';
  final role = _normalizeRole(rawRole);
  final id = _firstString(message, const [
        'id',
        'uuid',
        'message_id',
        'messageId',
      ]) ??
      '$conversationId-$sequence';
  final timestamp = _firstValue(message, const [
    'create_time',
    'created_at',
    'createdAt',
    'timestamp',
    'time',
    'occurredAt',
  ]);

  return <String, Object?>{
    'id': id,
    '_brain2_provider': provider,
    'author': {'role': role},
    'content': {
      'content_type': 'text',
      'parts': [text.trim()],
    },
    'create_time': timestamp,
  }..removeWhere((key, value) => value == null);
}

String _detectProvider(Map<String, Object?> conversation, String? hint) {
  final explicit = _firstString(conversation, const [
    '_brain2_provider',
    'provider',
    'platform',
    'source',
  ]);
  if (explicit != null && explicit.isNotEmpty)
    return _normalizeProvider(explicit);
  if (conversation['mapping'] is Map) return 'chatgpt';
  if (conversation['chat_messages'] is List) return 'claude';
  final messages = conversation['messages'];
  if (messages is List && messages.isNotEmpty && messages.first is Map) {
    final first = (messages.first as Map).cast<String, Object?>();
    final wrapped = first['message'];
    if (wrapped is Map) {
      final message = wrapped.cast<Object?, Object?>();
      if (message['author'] is Map && message['content'] != null) {
        return 'chatgpt';
      }
    }
    if (first['sender'] != null &&
        '${first['sender']}'.toLowerCase() == 'human') {
      return 'claude';
    }
    final role = '${first['role'] ?? ''}'.toLowerCase();
    if (role == 'model') return 'gemini';
    if (first['parts'] is List) return 'gemini';
  }
  if (conversation['turns'] is List) return hint ?? 'gemini';
  return hint ?? 'generic';
}

String? _providerFromRoot(Map<String, Object?> root) {
  final provider = _firstString(root, const ['provider', 'platform', 'source']);
  return provider == null ? null : _normalizeProvider(provider);
}

String? _providerHintFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('claude') || lower.contains('anthropic')) return 'claude';
  if (lower.contains('gemini') || lower.contains('bard')) return 'gemini';
  if (lower.contains('copilot') || lower.contains('bing')) return 'copilot';
  if (lower.contains('poe')) return 'poe';
  if (lower.contains('perplexity')) return 'perplexity';
  if (lower.contains('chatgpt') || lower.contains('openai')) return 'chatgpt';
  return null;
}

String _normalizeProvider(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.contains('chatgpt') || lower == 'openai') return 'chatgpt';
  if (lower.contains('claude') || lower.contains('anthropic')) return 'claude';
  if (lower.contains('gemini') || lower.contains('bard') || lower == 'google') {
    return 'gemini';
  }
  if (lower.contains('copilot') ||
      lower.contains('bing') ||
      lower == 'microsoft') {
    return 'copilot';
  }
  if (lower.contains('poe')) return 'poe';
  if (lower.contains('perplexity')) return 'perplexity';
  return lower.isEmpty
      ? 'generic'
      : lower.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
}

String _normalizeRole(String value) {
  final lower = value.trim().toLowerCase();
  if (lower == 'human' || lower == 'user' || lower == 'prompt') return 'user';
  if (lower == 'assistant' ||
      lower == 'model' ||
      lower == 'bot' ||
      lower == 'ai') {
    return 'assistant';
  }
  if (lower == 'system') return 'system';
  if (lower == 'tool' || lower == 'function') return lower;
  return lower.isEmpty ? 'unknown' : lower;
}

String? _nestedAuthorRole(Map<String, Object?> message) {
  final author = message['author'];
  if (author is Map) {
    final role = author['role'] ?? author['name'];
    if (role != null) return '$role';
  }
  return null;
}

String _extractText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  if (value is List) {
    return value
        .map(_extractText)
        .where((part) => part.trim().isNotEmpty)
        .join('\n');
  }
  if (value is! Map) return '';
  final map = value.cast<Object?, Object?>();

  // Avoid turning role/metadata fields into message text. Prefer known content
  // containers in provider order.
  for (final key in const [
    'text',
    'content',
    'parts',
    'message',
    'body',
    'value',
    'response',
    'prompt',
  ]) {
    if (!map.containsKey(key)) continue;
    final text = _extractText(map[key]);
    if (text.trim().isNotEmpty) return text;
  }
  return '';
}

String? _firstString(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null || value is Map || value is List) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

Object? _firstValue(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) return value;
  }
  return null;
}

bool _isJsonArrayBytes(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  while (start < bytes.length && _isWhitespace(bytes[start])) {
    start++;
  }
  return start < bytes.length && bytes[start] == 0x5B;
}

bool _looksLikeChatGptBytes(Uint8List bytes, String? hint) {
  final sampleLength = math.min(bytes.length, 512 * 1024);
  final sample = utf8.decode(
    Uint8List.sublistView(bytes, 0, sampleLength),
    allowMalformed: true,
  );
  if (sample.contains('"mapping"') && sample.contains('"message"')) return true;
  if (hint == 'chatgpt' &&
      sample.contains('"author"') &&
      sample.contains('"content"')) {
    return true;
  }
  return false;
}

Uint8List _readArchiveEntryBytes(ArchiveFile entry) {
  final bytes = entry.readBytes();
  if (bytes == null) {
    throw StateError('Unable to read ${entry.name} from the export ZIP.');
  }
  return bytes;
}

_JsonBounds _jsonArrayInnerBounds(Uint8List bytes, String name) {
  var start = 0;
  var end = bytes.length;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  while (start < end && _isWhitespace(bytes[start])) {
    start++;
  }
  while (end > start && _isWhitespace(bytes[end - 1])) {
    end--;
  }
  if (end - start < 2 || bytes[start] != 0x5B || bytes[end - 1] != 0x5D) {
    throw StateError('$name is not a JSON array.');
  }
  var innerStart = start + 1;
  var innerEnd = end - 1;
  while (innerStart < innerEnd && _isWhitespace(bytes[innerStart])) {
    innerStart++;
  }
  while (innerEnd > innerStart && _isWhitespace(bytes[innerEnd - 1])) {
    innerEnd--;
  }
  return _JsonBounds(innerStart, innerEnd);
}

bool _isWhitespace(int value) =>
    value == 0x20 || value == 0x09 || value == 0x0A || value == 0x0D;

/// Cheap object count for progress estimates only. The canonical importer later
/// computes the authoritative conversation count.
int _estimateTopLevelArrayObjects(Uint8List bytes, _JsonBounds bounds) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  var count = 0;
  for (var i = bounds.start; i < bounds.end; i++) {
    final b = bytes[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (b == 0x5C) {
        escaped = true;
      } else if (b == 0x22) {
        inString = false;
      }
      continue;
    }
    if (b == 0x22) {
      inString = true;
    } else if (b == 0x7B) {
      if (depth == 0) count++;
      depth++;
    } else if (b == 0x7D && depth > 0) {
      depth--;
    }
  }
  return count;
}
