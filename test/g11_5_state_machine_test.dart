import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/p2p_sync.dart';

void main() {
  test('G11.5 keeps memoryConflict as a first-class sync state', () {
    expect(Brain2P2PStage.values, contains(Brain2P2PStage.memoryConflict));
    expect(Brain2P2PStage.values, contains(Brain2P2PStage.disconnected));
  });
}
