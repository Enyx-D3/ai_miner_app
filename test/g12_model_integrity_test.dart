import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/mrs/mobile_model_manager.dart';
import 'package:brain2_ai_miner_mobile/mrs/mobile_model_manifest.dart';

void main() {
  test('G12.1 GGUF magic preflight rejects corrupt/truncated artifacts', () {
    expect(brain2HasGgufMagic([0x47,0x47,0x55,0x46]), isTrue);
    expect(brain2HasGgufMagic([0x47,0x47,0x55]), isFalse);
    expect(brain2HasGgufMagic([0x00,0x47,0x55,0x46]), isFalse);
  });
  test('G12.1 resume Content-Range must begin at exact partial offset', () {
    expect(brain2ContentRangeStartsAt('bytes 100-199/1000',100), isTrue);
    expect(brain2ContentRangeStartsAt('bytes 0-199/1000',100), isFalse);
    expect(brain2ContentRangeStartsAt(null,100), isFalse);
    expect(brain2ContentRangeStartsAt(null,0), isTrue);
  });
  test('G12.1 model byte budget allows only metadata tolerance', () {
    expect(brain2ModelMaxAcceptedBytes(1000),1030);
    expect(brain2ModelMaxAcceptedBytes(0),0);
  });
  test('G12.1 verifyFile requires GGUF header and pinned SHA256', () async {
    final dir=await Directory.systemTemp.createTemp('brain2-g12-model-');
    addTearDown(() async {if(await dir.exists())await dir.delete(recursive:true);});
    final goodBytes=<int>[0x47,0x47,0x55,0x46,0x03,0,0,0];
    final good=File('${dir.path}/good.gguf');await good.writeAsBytes(goodBytes,flush:true);
    final manifest=MobileModelManifest(
      id:'g12-fixture',displayName:'G12 fixture',fileName:'g12.gguf',
      downloadUri:Uri.parse('https://example.invalid/g12.gguf'),
      sha256Hex:sha256.convert(goodBytes).toString(),sizeBytes:goodBytes.length,
    );
    final manager=MobileModelManager(manifest:manifest,directoryProvider:() async=>dir);
    addTearDown(manager.dispose);
    expect(await manager.verifyFile(good),isTrue);
    final corrupt=File('${dir.path}/corrupt.gguf');
    await corrupt.writeAsBytes(<int>[0x00,0x47,0x55,0x46,0x03,0,0,0],flush:true);
    expect(await manager.verifyFile(corrupt),isFalse);
  });
}
