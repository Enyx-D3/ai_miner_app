import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/p2p_sync.dart';

void main() {
  test('G11.7 hello dispatch waits for a present OPEN data channel', () {
    expect(
      brain2ShouldDispatchHello(
        channelPresent: false,
        channelOpen: false,
      ),
      isFalse,
    );
    expect(
      brain2ShouldDispatchHello(
        channelPresent: true,
        channelOpen: false,
      ),
      isFalse,
      reason: 'CONNECTING channel must not receive hello',
    );
    expect(
      brain2ShouldDispatchHello(
        channelPresent: true,
        channelOpen: true,
      ),
      isTrue,
    );
  });
}
