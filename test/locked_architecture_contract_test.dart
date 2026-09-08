import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/core/contracts.dart';

void main() {
  test('mobile release declares locked architecture and MRS contract', () {
    expect(brain2SchemaVersion, 10);
    expect(brain2LockedArchitectureVersion, 'B2_LOCKED_ARCHITECTURE_V1');
    expect(brain2MrsVersion, 'B2_MRS_MOBILE_CANONICAL_V1');
    expect(asifReaderCoreVersion.contains('DART'), isTrue);
  });
}
