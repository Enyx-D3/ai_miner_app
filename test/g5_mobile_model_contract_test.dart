import 'dart:io';

import 'package:brain2_ai_miner_mobile/mrs/mobile_model_manager.dart';
import 'package:brain2_ai_miner_mobile/mrs/mobile_model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1 model manifest is pinned and production-shaped', () {
    final manifest = MobileModelManifest.v1Default;
    expect(manifest.id, isNotEmpty);
    expect(manifest.fileName.endsWith('.gguf'), isTrue);
    expect(manifest.downloadUri.isScheme('https'), isTrue);
    expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest.sha256Hex), isTrue);
    expect(manifest.sizeBytes, greaterThan(200 * 1000 * 1000));
    expect(manifest.contextSize, greaterThanOrEqualTo(1024));
  });

  test('model manager fails closed on a hash mismatch', () async {
    final temp = await Directory.systemTemp.createTemp('brain2-g5-');
    addTearDown(() => temp.delete(recursive: true));
    final manifest = MobileModelManifest(
      id: 'fixture',
      displayName: 'Fixture',
      fileName: 'fixture.gguf',
      downloadUri: Uri.parse('https://example.invalid/fixture.gguf'),
      sha256Hex:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sizeBytes: 4,
    );
    final manager = MobileModelManager(
      manifest: manifest,
      directoryProvider: () async => temp,
    );
    addTearDown(manager.dispose);
    final file = await manager.modelFile();
    await file.writeAsBytes([1, 2, 3, 4]);
    expect(await manager.verifyFile(file), isFalse);
  });
}
