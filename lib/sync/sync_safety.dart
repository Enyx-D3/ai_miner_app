import 'dart:convert';

const int brain2SyncPhysicalMessageMaxBytes = 16 * 1024;
const int brain2SyncFramePayloadMaxBytes = 8 * 1024;
const int brain2SyncReassembledMaxBytes = 64 * 1024 * 1024;
const int brain2SyncFrameMaxCount =
    brain2SyncReassembledMaxBytes ~/ brain2SyncFramePayloadMaxBytes;
const int brain2SyncFrameIdMaxChars = 192;
const int brain2SyncFrameMaxAssemblies = 16;
const int brain2SyncFrameTtlMs = 30000;
const int brain2SyncSignalReplayWindow = 2048;
const int brain2SyncMutationBatchMax = 128;

const Set<String> brain2SyncWireMessageTypes = {
  'hello',
  'sync_request',
  'mutations',
  'ack',
  'bootstrap_request',
  'bootstrap_chunk',
  'bootstrap_ack',
  'bootstrap_complete',
  'merge_request',
  'merge_accept',
  'merge_ready',
  'merge_seed_chunk',
  'merge_seed_complete',
  'merge_return_chunk',
  'merge_return_complete',
  'merge_complete',
  'ping',
};

int brain2Utf8Bytes(String value) => utf8.encode(value).length;

void brain2AssertPhysicalMessageSize(String raw) {
  if (brain2Utf8Bytes(raw) > brain2SyncPhysicalMessageMaxBytes) {
    throw StateError(
      'Brain2 physical P2P message exceeded the 16 KiB transport limit.',
    );
  }
}

void brain2AssertWireMessageType(Object? type) {
  if (type is! String || !brain2SyncWireMessageTypes.contains(type)) {
    throw StateError('Unsupported Brain2 P2P message type: $type');
  }
}

void brain2AssertFrameMetadata(Map<String, Object?> frame) {
  final id = frame['id'];
  final rawIndex = frame['index'];
  final rawTotal = frame['total'];
  final index = rawIndex is num ? rawIndex.toInt() : int.tryParse('$rawIndex');
  final total = rawTotal is num ? rawTotal.toInt() : int.tryParse('$rawTotal');

  if (id is! String ||
      id.isEmpty ||
      id.length > brain2SyncFrameIdMaxChars ||
      index == null ||
      total == null ||
      total < 1 ||
      total > brain2SyncFrameMaxCount ||
      index < 0 ||
      index >= total ||
      frame['data'] is! String) {
    throw StateError('Invalid Brain2 transport frame');
  }
}

void brain2AssertDecodedFrameBytes(int bytes) {
  if (bytes < 0 || bytes > brain2SyncFramePayloadMaxBytes) {
    throw StateError(
      'Brain2 transport frame payload exceeded the 8 KiB limit',
    );
  }
}

bool brain2SequenceRangeMatches(
  List<int> sequences,
  int fromSequence,
  int toSequence,
) {
  if (sequences.isEmpty ||
      sequences.length > brain2SyncMutationBatchMax ||
      fromSequence < 1 ||
      toSequence < fromSequence ||
      sequences.first != fromSequence ||
      sequences.last != toSequence) {
    return false;
  }
  for (var index = 0; index < sequences.length; index++) {
    if (sequences[index] < 1) return false;
    if (index > 0 && sequences[index] != sequences[index - 1] + 1) {
      return false;
    }
  }
  return true;
}

bool brain2AckMatchesPending({
  required bool awaiting,
  required String pendingManifestHash,
  required int pendingToSequence,
  required String ackManifestHash,
  required int ackSequence,
  required String ackOriginDeviceId,
  required String localDeviceId,
}) {
  if (!awaiting || pendingManifestHash.isEmpty) return false;
  if (ackManifestHash != pendingManifestHash) return false;
  if (ackSequence != pendingToSequence) return false;
  if (ackOriginDeviceId.isNotEmpty && ackOriginDeviceId != localDeviceId) {
    return false;
  }
  return true;
}

class Brain2ReplayWindow {
  final int limit;
  final Set<String> _seen = <String>{};

  Brain2ReplayWindow({this.limit = brain2SyncSignalReplayWindow});

  bool accept(String id) {
    if (id.isEmpty) return true;
    if (_seen.contains(id)) return false;
    _seen.add(id);
    while (_seen.length > limit) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  void clear() => _seen.clear();
}
