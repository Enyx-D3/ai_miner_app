import 'dart:convert';
import 'dart:typed_data';

import 'contextvault_native.dart';

class ContextVaultDigest {
  final bool nativeUsed;
  final Map<String, Object?> summary;
  const ContextVaultDigest({required this.nativeUsed, required this.summary});
}

/// Product-facing ContextVault boundary.
///
/// Android production prefers libcontextvault.so. A deterministic Dart
/// validation fallback keeps development/test builds usable when the NDK-built
/// library is not installed yet.
class ContextVaultService {
  final ContextVaultNative native;
  ContextVaultService({ContextVaultNative? native})
      : native = native ?? ContextVaultNative();

  bool initialize() => native.load();
  bool get nativeAvailable => native.available;

  ContextVaultDigest digestChatGptJson(Uint8List bytes, String sourceName) {
    if (native.available) {
      final r = native.digestSummary(bytes, sourceName);
      if (!r.ok) throw FormatException(r.error!);
      final decoded = r.jsonText.isEmpty
          ? const <String, Object?>{}
          : jsonDecode(r.jsonText);
      return ContextVaultDigest(
        nativeUsed: true,
        summary: decoded is Map
            ? decoded.cast<String, Object?>()
            : {'result': decoded},
      );
    }
    return ContextVaultDigest(
        nativeUsed: false, summary: _dartSummary(bytes, sourceName));
  }

  Map<String, Object?> _dartSummary(Uint8List bytes, String sourceName) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List)
      throw const FormatException('Expected ChatGPT conversations JSON array.');
    var conversations = 0;
    var messages = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      conversations++;
      final mapping = item['mapping'];
      if (mapping is Map) {
        for (final node in mapping.values) {
          if (node is Map && node['message'] is Map) messages++;
        }
      } else if (item['messages'] is List) {
        messages += (item['messages'] as List).length;
      }
    }
    return {
      'source_name': sourceName,
      'conversation_count': conversations,
      'message_count': messages,
      'engine': 'DART_VALIDATION_FALLBACK',
    };
  }
}
