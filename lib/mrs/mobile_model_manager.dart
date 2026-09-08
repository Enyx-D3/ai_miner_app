import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mobile_model_manifest.dart';

const List<int> brain2GgufMagic = [0x47, 0x47, 0x55, 0x46];

bool brain2HasGgufMagic(List<int> prefix) =>
    prefix.length >= brain2GgufMagic.length &&
    List.generate(brain2GgufMagic.length, (index) => prefix[index] == brain2GgufMagic[index]).every((value) => value);

int brain2ModelMaxAcceptedBytes(int expectedBytes) {
  if (expectedBytes <= 0) return 0;
  return expectedBytes + (expectedBytes * 0.03).round();
}

bool brain2ContentRangeStartsAt(String? header, int expectedOffset) {
  if (expectedOffset <= 0) return true;
  if (header == null || header.isEmpty) return false;
  final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$', caseSensitive: false).firstMatch(header.trim());
  if (match == null) return false;
  return int.tryParse(match.group(1) ?? '') == expectedOffset;
}

enum MobileModelInstallState {
  missing,
  partial,
  ready,
  corrupt,
}

class MobileModelStatus {
  final MobileModelInstallState state;
  final String path;
  final int bytesOnDisk;
  final int expectedBytes;

  const MobileModelStatus({
    required this.state,
    required this.path,
    required this.bytesOnDisk,
    required this.expectedBytes,
  });

  bool get ready => state == MobileModelInstallState.ready;
  double get progress =>
      expectedBytes <= 0 ? 0 : (bytesOnDisk / expectedBytes).clamp(0.0, 1.0);
}

class MobileModelManager {
  final MobileModelManifest manifest;
  final http.Client _client;
  final Future<Directory> Function()? _directoryProvider;

  MobileModelManager({
    MobileModelManifest? manifest,
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
  })  : manifest = manifest ?? MobileModelManifest.v1Default,
        _client = client ?? http.Client(),
        _directoryProvider = directoryProvider;

  Future<Directory> _modelsDir() async {
    final root = _directoryProvider == null
        ? await getApplicationSupportDirectory()
        : await _directoryProvider!();
    final dir = Directory(p.join(root.path, 'brain2', 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> modelFile() async {
    final dir = await _modelsDir();
    return File(p.join(dir.path, manifest.fileName));
  }

  Future<File> partialFile() async {
    final dir = await _modelsDir();
    return File(p.join(dir.path, '${manifest.fileName}.part'));
  }

  Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<bool> verifyGgufHeader(File file) async {
    if (!await file.exists()) return false;
    if (await file.length() < brain2GgufMagic.length) return false;
    final handle = await file.open();
    try {
      final prefix = await handle.read(brain2GgufMagic.length);
      return brain2HasGgufMagic(prefix);
    } finally {
      await handle.close();
    }
  }

  Future<bool> verifyFile(File file) async {
    if (!await file.exists()) return false;
    if (!await verifyGgufHeader(file)) return false;
    if (manifest.sizeBytes > 0) {
      final length = await file.length();
      // Hugging Face reports decimal MB. Allow a small metadata tolerance while
      // still requiring the cryptographic hash below for final integrity.
      final tolerance = (manifest.sizeBytes * 0.03).round();
      if ((length - manifest.sizeBytes).abs() > tolerance) return false;
    }
    return (await sha256Of(file)).toLowerCase() ==
        manifest.sha256Hex.toLowerCase();
  }

  Future<MobileModelStatus> status({bool verifyHash = false}) async {
    final target = await modelFile();
    final partial = await partialFile();
    if (await target.exists()) {
      final length = await target.length();
      if (!verifyHash) {
        return MobileModelStatus(
          state: MobileModelInstallState.ready,
          path: target.path,
          bytesOnDisk: length,
          expectedBytes: manifest.sizeBytes,
        );
      }
      final valid = await verifyFile(target);
      return MobileModelStatus(
        state: valid
            ? MobileModelInstallState.ready
            : MobileModelInstallState.corrupt,
        path: target.path,
        bytesOnDisk: length,
        expectedBytes: manifest.sizeBytes,
      );
    }
    if (await partial.exists()) {
      return MobileModelStatus(
        state: MobileModelInstallState.partial,
        path: partial.path,
        bytesOnDisk: await partial.length(),
        expectedBytes: manifest.sizeBytes,
      );
    }
    return MobileModelStatus(
      state: MobileModelInstallState.missing,
      path: target.path,
      bytesOnDisk: 0,
      expectedBytes: manifest.sizeBytes,
    );
  }

  Future<File> ensureDownloaded({
    void Function(double progress)? onProgress,
  }) async {
    if (manifest.downloadUri.scheme.toLowerCase() != 'https') {
      throw StateError('Brain2 production model downloads require HTTPS.');
    }
    final target = await modelFile();
    if (await target.exists()) {
      if (await verifyFile(target)) return target;
      await target.delete();
    }

    final partial = await partialFile();
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset >= manifest.sizeBytes && manifest.sizeBytes > 0) {
      await partial.delete();
      offset = 0;
    }

    final request = http.Request('GET', manifest.downloadUri);
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException(
        'Model download failed with HTTP ${response.statusCode}.',
        uri: manifest.downloadUri,
      );
    }

    if (offset > 0 &&
        response.statusCode == 206 &&
        !brain2ContentRangeStartsAt(response.headers['content-range'], offset)) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Model server returned an invalid Content-Range for resume.');
    }

    // A server that ignored Range must restart the partial download from zero.
    if (offset > 0 && response.statusCode == 200) {
      await partial.writeAsBytes(const [], flush: true);
      offset = 0;
    }

    final maxAcceptedBytes = brain2ModelMaxAcceptedBytes(manifest.sizeBytes);
    final responseLength = response.contentLength;
    if (maxAcceptedBytes > 0 &&
        responseLength != null &&
        offset + responseLength > maxAcceptedBytes) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Model response exceeds the pinned V1 artifact size budget.');
    }

    final sink = partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var written = offset;
    try {
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          written += chunk.length;
          if (maxAcceptedBytes > 0 && written > maxAcceptedBytes) {
            throw StateError('Model download exceeded the pinned V1 artifact size budget.');
          }
          if (manifest.sizeBytes > 0) {
            onProgress?.call((written / manifest.sizeBytes).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }

    if (!await verifyFile(partial)) {
      final actualHash = await partial.exists() ? await sha256Of(partial) : 'missing';
      if (await partial.exists()) await partial.delete();
      throw StateError(
        'Downloaded model failed GGUF/integrity verification. '
        'Expected ${manifest.sha256Hex}, got $actualHash.',
      );
    }

    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    onProgress?.call(1.0);
    return target;
  }

  Future<void> remove() async {
    final target = await modelFile();
    final partial = await partialFile();
    if (await target.exists()) await target.delete();
    if (await partial.exists()) await partial.delete();
  }

  void dispose() => _client.close();
}
