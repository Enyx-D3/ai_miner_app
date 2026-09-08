import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

class PreparedChatGptExport {
  final String jsonPath;
  final int jsonFileCount;
  final int jsonBytes;

  const PreparedChatGptExport({
    required this.jsonPath,
    required this.jsonFileCount,
    required this.jsonBytes,
  });
}

class _JsonBounds {
  final int start;
  final int end;

  const _JsonBounds(this.start, this.end);
}

final RegExp _conversationJsonPattern = RegExp(
  r'(?:^|/)conversations(?:-[^/\\]+)?\.json$',
  caseSensitive: false,
);

class ChatGptExportExtractor {
  Future<PreparedChatGptExport> prepare({
    required String inputPath,
    required String inputName,
    required String outputPath,
  }) async {
    if (inputName.toLowerCase().endsWith('.json')) {
      final source = File(inputPath);
      await source.copy(outputPath);
      return PreparedChatGptExport(
        jsonPath: outputPath,
        jsonFileCount: 1,
        jsonBytes: await File(outputPath).length(),
      );
    }

    return _combineConversationJsonShards(inputPath, outputPath);
  }

  Future<PreparedChatGptExport> _combineConversationJsonShards(
    String zipPath,
    String outputPath,
  ) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries = archive.files.where((entry) {
        if (!entry.isFile) return false;
        final normalized = entry.name.replaceAll('\\', '/');
        return _conversationJsonPattern.hasMatch(normalized) ||
            normalized.toLowerCase().endsWith('/chat.json') ||
            normalized.toLowerCase() == 'chat.json';
      }).toList()
        ..sort((a, b) => _compareShardNames(a.name, b.name));

      if (entries.isEmpty) {
        throw StateError(
          'No conversations.json or conversations-*.json file was found in '
          'this ChatGPT export ZIP.',
        );
      }

      if (entries.length == 1) {
        final bytes = _readArchiveEntryBytes(entries.single);
        await File(outputPath).writeAsBytes(bytes, flush: false);
        entries.single.clear();
        return PreparedChatGptExport(
          jsonPath: outputPath,
          jsonFileCount: 1,
          jsonBytes: bytes.length,
        );
      }

      final out = File(outputPath).openWrite();
      var wroteAny = false;
      out.add(const [0x5B]);
      try {
        for (final entry in entries) {
          final bytes = _readArchiveEntryBytes(entry);
          final bounds = _jsonArrayInnerBounds(bytes, entry.name);
          if (bounds.end > bounds.start) {
            if (wroteAny) out.add(const [0x2C]);
            out.add(
              Uint8List.sublistView(bytes, bounds.start, bounds.end),
            );
            wroteAny = true;
          }
          entry.clear();
        }
        out.add(const [0x5D]);
      } finally {
        await out.close();
      }

      return PreparedChatGptExport(
        jsonPath: outputPath,
        jsonFileCount: entries.length,
        jsonBytes: await File(outputPath).length(),
      );
    } finally {
      input.closeSync();
    }
  }
}

Uint8List _readArchiveEntryBytes(ArchiveFile entry) {
  final bytes = entry.readBytes();
  if (bytes == null) {
    throw StateError(
      'Unable to read ${entry.name} from the ChatGPT export ZIP.',
    );
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

int _compareShardNames(String a, String b) {
  int rank(String value) {
    final name = value.replaceAll('\\', '/').split('/').last.toLowerCase();
    if (name == 'conversations.json') return 0;
    final match = RegExp(r'^conversations-(\d+)\.json$').firstMatch(name);
    if (match != null) return int.parse(match.group(1)!) + 1;
    if (name == 'chat.json') return 900000;
    return 1000000;
  }

  final left = rank(a);
  final right = rank(b);
  if (left != right) return left.compareTo(right);
  return a.compareTo(b);
}
