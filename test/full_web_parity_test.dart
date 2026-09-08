import 'package:flutter_test/flutter_test.dart';import 'package:brain2_ai_miner_mobile/core/contracts.dart';
void main(){test('V9 web parity constants',(){expect(brain2SchemaVersion,10);expect(brain2IdentityVersion,'B2_ID_V9_ASIF_READER');expect(brain2SyncProtocolVersion,2);expect(brain2SyncChannel,'brain2-sync');});}
