import 'dart:convert';
import 'dart:io';

/// Streams a top-level JSON array of objects from disk without materializing
/// the whole file in Dart memory.
///
/// ChatGPT exports are a JSON array whose elements are conversation objects.
/// This parser keeps only one conversation object in memory at a time, while
/// correctly ignoring braces/brackets that appear inside JSON strings.
Stream<Map<String, Object?>> streamJsonObjectArrayFile(
  String path, {
  void Function(int parsedObjects)? onObject,
}) async* {
  var sawArrayStart = false;
  var finished = false;
  var inElement = false;
  var inString = false;
  var escaping = false;
  var depth = 0;
  var parsed = 0;
  StringBuffer? buffer;

  await for (final chunk in File(path).openRead().transform(utf8.decoder)) {
    for (var i = 0; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);

      if (finished) {
        if (!_isWhitespace(code)) {
          throw const FormatException(
            'Unexpected data after the top-level JSON array.',
          );
        }
        continue;
      }

      if (!sawArrayStart) {
        if (_isWhitespace(code) || code == 0xfeff) continue;
        if (code != 0x5b) {
          throw const FormatException(
            'Expected ChatGPT conversations JSON to start with an array.',
          );
        }
        sawArrayStart = true;
        continue;
      }

      if (!inElement) {
        if (_isWhitespace(code) || code == 0x2c) continue;
        if (code == 0x5d) {
          finished = true;
          continue;
        }
        if (code != 0x7b) {
          throw const FormatException(
            'Expected each ChatGPT conversation entry to be a JSON object.',
          );
        }
        buffer = StringBuffer()..writeCharCode(code);
        inElement = true;
        inString = false;
        escaping = false;
        depth = 1;
        continue;
      }

      buffer!.writeCharCode(code);

      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (code == 0x5c) {
          escaping = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }

      if (code == 0x22) {
        inString = true;
        continue;
      }
      if (code == 0x7b || code == 0x5b) {
        depth++;
        continue;
      }
      if (code == 0x7d || code == 0x5d) {
        depth--;
        if (depth < 0) {
          throw const FormatException('Malformed JSON nesting.');
        }
        if (depth == 0) {
          final text = buffer.toString();
          buffer = null;
          inElement = false;
          final decoded = jsonDecode(text);
          if (decoded is! Map) {
            throw const FormatException(
              'Expected ChatGPT conversation entry to decode as an object.',
            );
          }
          parsed++;
          onObject?.call(parsed);
          yield decoded.cast<String, Object?>();
        }
      }
    }
  }

  if (!sawArrayStart) {
    throw const FormatException('ChatGPT conversations JSON is empty.');
  }
  if (inElement || depth != 0 || inString) {
    throw const FormatException('Truncated ChatGPT conversations JSON.');
  }
  if (!finished) {
    throw const FormatException('Top-level ChatGPT JSON array was not closed.');
  }
}

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
