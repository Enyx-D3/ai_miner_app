import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/sync_safety.dart';

void main() {
  test('G12.3 physical P2P message has a hard byte ceiling', () {
    brain2AssertPhysicalMessageSize('x' * 100);
    expect(
      () => brain2AssertPhysicalMessageSize(
        'x' * (brain2SyncPhysicalMessageMaxBytes + 1),
      ),
      throwsStateError,
    );
  });

  test('G12.3 frame metadata and frame payload are bounded', () {
    brain2AssertFrameMetadata({
      'id': 'frame-1',
      'index': 0,
      'total': 1,
      'data': 'AA==',
    });
    expect(
      () => brain2AssertFrameMetadata({
        'id': '',
        'index': 0,
        'total': 1,
        'data': 'AA==',
      }),
      throwsStateError,
    );
    expect(
      () => brain2AssertFrameMetadata({
        'id': 'x' * (brain2SyncFrameIdMaxChars + 1),
        'index': 0,
        'total': 1,
        'data': 'AA==',
      }),
      throwsStateError,
    );
    expect(
      () => brain2AssertDecodedFrameBytes(
        brain2SyncFramePayloadMaxBytes + 1,
      ),
      throwsStateError,
    );
  });

  test('G12.3 mutation ranges must be contiguous and exact', () {
    expect(brain2SequenceRangeMatches([7, 8, 9], 7, 9), isTrue);
    expect(brain2SequenceRangeMatches([7, 9], 7, 9), isFalse);
    expect(brain2SequenceRangeMatches([7, 8], 7, 9), isFalse);
    expect(brain2SequenceRangeMatches(const [], 1, 1), isFalse);
  });

  test('G12.3 ACK must match the exact pending batch', () {
    expect(
      brain2AckMatchesPending(
        awaiting: true,
        pendingManifestHash: 'abc',
        pendingToSequence: 9,
        ackManifestHash: 'abc',
        ackSequence: 9,
        ackOriginDeviceId: 'dev_a',
        localDeviceId: 'dev_a',
      ),
      isTrue,
    );
    expect(
      brain2AckMatchesPending(
        awaiting: true,
        pendingManifestHash: 'abc',
        pendingToSequence: 9,
        ackManifestHash: 'evil',
        ackSequence: 999,
        ackOriginDeviceId: 'dev_a',
        localDeviceId: 'dev_a',
      ),
      isFalse,
    );
  });

  test('G12.3 duplicate signal IDs are suppressed in a bounded window', () {
    final replay = Brain2ReplayWindow(limit: 2);
    expect(replay.accept('sig1'), isTrue);
    expect(replay.accept('sig1'), isFalse);
    expect(replay.accept('sig2'), isTrue);
    expect(replay.accept('sig3'), isTrue);
    expect(replay.accept('sig1'), isTrue);
  });

  test('G12.3 unsupported wire message type fails closed', () {
    brain2AssertWireMessageType('hello');
    expect(
      () => brain2AssertWireMessageType('root_override'),
      throwsStateError,
    );
  });
}
