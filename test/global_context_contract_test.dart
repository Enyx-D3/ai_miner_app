import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/core/contracts.dart';
import 'package:brain2_ai_miner_mobile/core/identity.dart';
import 'package:brain2_ai_miner_mobile/sync/sync_contract.dart';

void main() {
  test('GC-CP001 shared schema and state families', () {
    expect(brain2SchemaVersion, 10);
    expect(brain2SyncProtocolVersion, 2);
    for (final table in [
      'mrsRuns',
      'intelligenceSnapshots',
      'wikiSnapshots',
      'notebookSnapshots',
    ]) {
      expect(brain2SupportsWireTable(table), isTrue);
    }
  });

  test('GC-CP001 NFKC identity fixture matches Web', () {
    expect(canonicalId('x', ['Ａ', ' Å  ']), 'x_d1a8a5e267653ff721231d09');
    expect(canonicalId('x', ['ChatGPT', ' Project  Foo ']),
        'x_672c665657ed937a93a9eb87');
    expect(
      canonicalId('msg',
          ['chatgpt', 'conv_1', 'structural', null, null, 1, 'user', 'Cafe\u0301']),
      'msg_fc15f3790e150f38c303abc7',
    );
  });
}
