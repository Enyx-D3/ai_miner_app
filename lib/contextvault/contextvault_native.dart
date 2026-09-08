import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _CvBrowserDigestResult extends Struct {
  external Pointer<Uint8> json;

  @UintPtr()
  external int jsonSize;

  external Pointer<Uint8> error;

  @UintPtr()
  external int errorSize;
}

typedef _DigestNative = Int32 Function(
  Pointer<Uint8>,
  UintPtr,
  Pointer<Utf8>,
  Pointer<_CvBrowserDigestResult>,
);
typedef _DigestDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Utf8>,
  Pointer<_CvBrowserDigestResult>,
);
typedef _FreeNative = Void Function(Pointer<_CvBrowserDigestResult>);
typedef _FreeDart = void Function(Pointer<_CvBrowserDigestResult>);

typedef _DigestFileNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _DigestFileDart = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

class ContextVaultNativeResult {
  final String jsonText;
  final String? error;

  const ContextVaultNativeResult(this.jsonText, this.error);

  bool get ok => error == null;
}

/// Native Android adapter over the same ContextVault C++ digest core used by
/// the web/WASM build. Mobile compiles the source directly into
/// libcontextvault.so and calls it through Dart FFI.
class ContextVaultNative {
  DynamicLibrary? _lib;
  _DigestDart? _summary;
  _DigestDart? _markdown;
  _FreeDart? _free;
  _DigestFileDart? _markdownFile;
  _LastErrorDart? _lastError;
  _FreeStringDart? _freeString;

  bool get available => _lib != null && _summary != null && _free != null;
  bool get markdownFileAvailable =>
      available &&
      _markdownFile != null &&
      _lastError != null &&
      _freeString != null;

  bool load() {
    if (_lib != null) return available;
    if (!Platform.isAndroid) return false;

    try {
      final lib = DynamicLibrary.open('libcontextvault.so');
      _summary = lib.lookupFunction<_DigestNative, _DigestDart>(
        'cv_digest_chatgpt_json_summary_out',
      );
      _markdown = lib.lookupFunction<_DigestNative, _DigestDart>(
        'cv_digest_chatgpt_json_to_markdown_out',
      );
      _free = lib.lookupFunction<_FreeNative, _FreeDart>(
        'cv_free_browser_digest_result_ptr',
      );
      _markdownFile = lib.lookupFunction<_DigestFileNative, _DigestFileDart>(
        'cv_mobile_digest_markdown_file',
      );
      _lastError = lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'cv_mobile_last_error',
      );
      _freeString = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'cv_mobile_free_string',
      );
      _lib = lib;
      return true;
    } catch (_) {
      _lib = null;
      _summary = null;
      _markdown = null;
      _free = null;
      _markdownFile = null;
      _lastError = null;
      _freeString = null;
      return false;
    }
  }

  ContextVaultNativeResult digestSummary(Uint8List bytes, String sourceName) {
    if (!available) {
      throw StateError('libcontextvault.so is not loaded');
    }
    return _invoke(_summary!, bytes, sourceName);
  }

  ContextVaultNativeResult digestMarkdown(
    Uint8List bytes,
    String optionsJson,
  ) {
    if (_markdown == null || _free == null) {
      throw StateError('ContextVault markdown ABI unavailable');
    }
    return _invoke(_markdown!, bytes, optionsJson);
  }

  /// Processes a prepared ChatGPT conversations JSON file directly from its
  /// filesystem path, avoiding a second Dart-side copy of the full JSON.
  String digestMarkdownFile(
    String jsonPath, {
    String optionsJson = '{"max_messages_per_file":100,"include_system":false}',
  }) {
    if (!markdownFileAvailable) {
      throw StateError('ContextVault file digest ABI unavailable');
    }

    final pathPtr = jsonPath.toNativeUtf8();
    final optionsPtr = optionsJson.toNativeUtf8();
    try {
      final result = _markdownFile!(pathPtr, optionsPtr);
      if (result == nullptr) {
        final errorPtr = _lastError!();
        final message = errorPtr == nullptr
            ? 'ContextVault native processing failed.'
            : errorPtr.toDartString();
        throw StateError(message);
      }

      try {
        return result.toDartString();
      } finally {
        _freeString!(result);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(optionsPtr);
    }
  }

  ContextVaultNativeResult _invoke(
    _DigestDart fn,
    Uint8List bytes,
    String arg,
  ) {
    final input = calloc<Uint8>(bytes.length);
    final out = calloc<_CvBrowserDigestResult>();
    final argPtr = arg.toNativeUtf8();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final rc = fn(input, bytes.length, argPtr, out);
      final jsonText = out.ref.json == nullptr || out.ref.jsonSize == 0
          ? ''
          : utf8.decode(out.ref.json.asTypedList(out.ref.jsonSize));
      final errorText = out.ref.error == nullptr || out.ref.errorSize == 0
          ? null
          : utf8.decode(out.ref.error.asTypedList(out.ref.errorSize));
      // ContextVault's *_out ABI returns 1 on success and 0 on failure.
      // The web wrapper intentionally ignores the numeric return code and uses
      // the populated error pointer as the authoritative failure signal.
      if (errorText != null) {
        return ContextVaultNativeResult(jsonText, errorText);
      }
      if (rc != 1) {
        return ContextVaultNativeResult(
          jsonText,
          'ContextVault ABI call failed with status $rc',
        );
      }
      return ContextVaultNativeResult(jsonText, null);
    } finally {
      _free?.call(out);
      calloc.free(argPtr);
      calloc.free(input);
      calloc.free(out);
    }
  }
}
