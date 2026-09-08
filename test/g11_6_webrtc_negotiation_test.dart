import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/p2p_sync.dart';

void main() {
  test('G11.6 applies remote answer only to a live local offer', () {
    expect(
      brain2ShouldApplyRemoteAnswer(
        hasPeerConnection: true,
        awaitingRemoteAnswer: true,
      ),
      isTrue,
    );
    expect(
      brain2ShouldApplyRemoteAnswer(
        hasPeerConnection: true,
        awaitingRemoteAnswer: false,
      ),
      isFalse,
      reason: 'duplicate/stale answer must be ignored once negotiation is stable',
    );
    expect(
      brain2ShouldApplyRemoteAnswer(
        hasPeerConnection: false,
        awaitingRemoteAnswer: true,
      ),
      isFalse,
    );
  });
}
