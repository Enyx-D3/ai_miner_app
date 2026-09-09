import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/contracts.dart';
import '../core/identity.dart';
import '../models/mutation.dart';
import '../storage/brain2_database.dart';
import 'g11_sync_proof.dart';
import 'network_client.dart';
import 'sync_contract.dart';
import 'sync_safety.dart';

const int _brain2TransportFramePayloadBytes = brain2SyncFramePayloadMaxBytes;
const int _brain2TransportMaxReassembledBytes = brain2SyncReassembledMaxBytes;

bool brain2ShouldDispatchHello({
  required bool channelPresent,
  required bool channelOpen,
}) =>
    channelPresent && channelOpen;

bool brain2ShouldApplyRemoteAnswer({
  required bool hasPeerConnection,
  required bool awaitingRemoteAnswer,
}) =>
    hasPeerConnection && awaitingRemoteAnswer;

String _bootstrapWireHashMaterial(
  String memoryRoot,
  String table,
  int ordinal,
  String recordsJson,
) =>
    'B2BOOTSTRAP3\u0000$memoryRoot\u0000$table\u0000$ordinal\u0000$recordsJson';

String _hashBootstrapWireChunk(
  String memoryRoot,
  String table,
  int ordinal,
  String recordsJson,
) =>
    sha256Hex(
        _bootstrapWireHashMaterial(memoryRoot, table, ordinal, recordsJson));

class _Brain2FrameAssembly {
  final int total;
  final List<Uint8List?> parts;
  int received = 0;
  int bytes = 0;
  int updatedAtMs;

  _Brain2FrameAssembly(this.total)
      : updatedAtMs = DateTime.now().millisecondsSinceEpoch,
        parts = List<Uint8List?>.filled(total, null);
}

enum Brain2P2PStage {
  idle,
  signaling,
  webRtcConnected,
  verifyingMemory,
  memoryConflict,
  bootstrapping,
  syncingDeltas,
  synced,
  disconnected,
  error,
}

class Brain2P2PStatus {
  final Brain2P2PStage stage;
  final String message;
  final String? peerDeviceId;
  final int? processed;

  const Brain2P2PStatus(
    this.stage,
    this.message, {
    this.peerDeviceId,
    this.processed,
  });
}

typedef Brain2P2PStatusCallback = void Function(Brain2P2PStatus status);
typedef Brain2MemoryRootChangedCallback = Future<void> Function(String root);

class Brain2P2PSync {
  final Brain2Database db;
  final Brain2NetworkClient api;
  final String deviceId;
  final String deviceToken;
  final List<Map<String, Object?>> iceServers;
  final Brain2P2PStatusCallback? onStatus;
  final Brain2MemoryRootChangedCallback? onMemoryRootChanged;

  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, RTCDataChannel> _channels = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Set<String> _remoteDescriptionReady = {};
  final Set<String> _awaitingRemoteAnswer = {};
  final Set<String> _flushScheduled = {};
  final Set<String> _awaitingAck = {};
  final Map<String, String> _outboundManifestHash = {};
  final Map<String, int> _outboundToSequence = {};
  final Map<String, int> _bootstrapPeerMaxSequence = {};
  final Map<String, int> _bootstrapExpectedOrdinal = {};
  final Map<String, Map<String, Object?>> _memoryConflicts = {};
  bool _merging = false;
  String _mergePhase = 'IDLE';
  int _mergeSeedOrdinal = 0;
  final Brain2ReplayWindow _signalReplay = Brain2ReplayWindow();
  final Map<String, _Brain2FrameAssembly> _incomingFrames = {};
  final Map<String, Future<void>> _incomingWork = {};
  int _frameCounter = 0;
  final Map<String, int> _remoteLatestSequence = {};
  final Map<String, int> _remoteMessageCount = {};
  final Map<String, int> _remoteAtomCount = {};
  final Map<String, int> _remoteTruthCount = {};

  Timer? _signalPoll;
  Timer? _reconcileTimer;
  StreamSubscription<MutationCommittedEvent>? _mutationSubscription;
  bool _polling = false;
  bool _disposed = false;

  Brain2P2PSync({
    required this.db,
    required this.api,
    required this.deviceId,
    required this.deviceToken,
    this.iceServers = const [],
    this.onStatus,
    this.onMemoryRootChanged,
  });

  void _status(
    Brain2P2PStage stage,
    String message, {
    String? peer,
    int? processed,
  }) {
    final preserveConflict = _memoryConflicts.isNotEmpty &&
        !_merging &&
        stage != Brain2P2PStage.memoryConflict &&
        (stage == Brain2P2PStage.signaling ||
            stage == Brain2P2PStage.webRtcConnected ||
            stage == Brain2P2PStage.verifyingMemory ||
            stage == Brain2P2PStage.disconnected);

    onStatus?.call(
      Brain2P2PStatus(
        preserveConflict ? Brain2P2PStage.memoryConflict : stage,
        preserveConflict
            ? 'Different Brain2 memories are still waiting to merge. '
                'Transport update: $message'
            : message,
        peerDeviceId: peer,
        processed: processed,
      ),
    );
  }

  Future<void> start() async {
    if (_disposed) throw StateError('Brain2 P2P sync has been disposed.');
    _signalPoll ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_consumeSignalsSafe()),
    );
    _mutationSubscription ??= db.mutationEvents
        .where(
      (e) => !e.remote && e.mutation.originDeviceId == deviceId,
    )
        .listen((_) {
      for (final peer in _channels.keys) {
        _scheduleHello(peer);
      }
    });
    _reconcileTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        for (final peer in _channels.keys) {
          _scheduleHello(peer);
        }
      },
    );
    await _consumeSignalsSafe();
  }

  Future<void> dispose() async {
    _disposed = true;
    _signalPoll?.cancel();
    _signalPoll = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    await _mutationSubscription?.cancel();
    _mutationSubscription = null;
    for (final c in _channels.values) {
      await c.close();
    }
    for (final p in _pcs.values) {
      await p.close();
    }
    _channels.clear();
    _pcs.clear();
    _pendingIce.clear();
    _remoteDescriptionReady.clear();
    _awaitingRemoteAnswer.clear();
    _awaitingAck.clear();
    _outboundManifestHash.clear();
    _outboundToSequence.clear();
    _bootstrapExpectedOrdinal.clear();
    _incomingFrames.clear();
    _incomingWork.clear();
    _signalReplay.clear();
    api.close();
  }

  Future<RTCPeerConnection> _pc(String peer) async {
    final existing = _pcs[peer];
    if (existing != null) return existing;

    final pc = await createPeerConnection({'iceServers': iceServers});
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(
        api
            .postSignal(
          fromDeviceId: deviceId,
          token: deviceToken,
          toDeviceId: peer,
          kind: 'ice',
          payload: candidate.toMap(),
        )
            .catchError((Object error) {
          _status(
            Brain2P2PStage.error,
            'Could not send ICE candidate: $error',
            peer: peer,
          );
        }),
      );
    };
    pc.onDataChannel = (channel) => _attach(peer, channel);
    _pcs[peer] = pc;
    return pc;
  }

  void _attach(String peer, RTCDataChannel channel) {
    _channels[peer] = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _status(
          Brain2P2PStage.webRtcConnected,
          'Direct WebRTC channel connected.',
          peer: peer,
        );
        _scheduleHello(peer);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _channels.remove(peer);
        _awaitingAck.remove(peer);
        _outboundManifestHash.remove(peer);
        _outboundToSequence.remove(peer);
        _bootstrapExpectedOrdinal.remove(peer);
        _clearTransportFrames(peer);
        if (_memoryConflicts.containsKey(peer)) {
          _merging = false;
          _mergePhase = 'IDLE';
          _mergeSeedOrdinal = 0;
        }
        _status(
          Brain2P2PStage.disconnected,
          'Peer disconnected. Missing deltas will resume after reconnect.',
          peer: peer,
        );
      }
    };
    channel.onMessage = (message) {
      if (message.isBinary) return;

      final previous = _incomingWork[peer] ?? Future<void>.value();
      final queued = previous.then(
        (_) => _handleIncomingText(peer, message.text),
      );

      _incomingWork[peer] = queued;

      unawaited(
        queued.whenComplete(() {
          if (identical(_incomingWork[peer], queued)) {
            _incomingWork.remove(peer);
          }
        }),
      );
    };
  }

  Future<void> _handleIncomingText(String peer, String text) async {
    try {
      brain2AssertPhysicalMessageSize(text);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('Brain2 P2P message is not an object.');
      }
      final map = decoded.cast<String, Object?>();
      if (map['__brain2Frame'] == 1) {
        await _acceptTransportFrame(peer, map);
        return;
      }
      await _message(peer, map);
    } catch (error) {
      _status(
        Brain2P2PStage.error,
        'P2P message rejected: $error',
        peer: peer,
      );
      _awaitingAck.remove(peer);
      _outboundManifestHash.remove(peer);
      _outboundToSequence.remove(peer);
      _bootstrapExpectedOrdinal.remove(peer);
      _clearTransportFrames(peer);
      _merging = false;
      _mergePhase = 'IDLE';
      _mergeSeedOrdinal = 0;
      final channel = _channels.remove(peer);
      if (channel != null) await channel.close();
      final pc = _pcs.remove(peer);
      if (pc != null) await pc.close();
    }
  }

  void _clearTransportFrames(String peer) {
    final prefix = '$peer::';
    final keys = _incomingFrames.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      _incomingFrames.remove(key);
    }
  }

  void _pruneTransportFrames(String peer) {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - brain2SyncFrameTtlMs;
    final prefix = '$peer::';
    final expired = _incomingFrames.entries
        .where(
          (entry) =>
              entry.key.startsWith(prefix) &&
              entry.value.updatedAtMs < cutoff,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expired) {
      _incomingFrames.remove(key);
    }
  }

  int _incomingFrameBytesForPeer(String peer) {
    final prefix = '$peer::';
    var total = 0;
    for (final entry in _incomingFrames.entries) {
      if (entry.key.startsWith(prefix)) total += entry.value.bytes;
    }
    return total;
  }

  int _incomingFrameAssembliesForPeer(String peer) {
    final prefix = '$peer::';
    return _incomingFrames.keys.where((key) => key.startsWith(prefix)).length;
  }

  Future<void> _acceptTransportFrame(
    String peer,
    Map<String, Object?> frame,
  ) async {
    brain2AssertFrameMetadata(frame);
    _pruneTransportFrames(peer);

    final id = frame['id'] as String;
    final rawIndex = frame['index'];
    final rawTotal = frame['total'];
    final index = rawIndex is num ? rawIndex.toInt() : int.parse('$rawIndex');
    final total = rawTotal is num ? rawTotal.toInt() : int.parse('$rawTotal');
    final bytes = base64Decode(frame['data'] as String);
    brain2AssertDecodedFrameBytes(bytes.length);

    final key = '$peer::$id';
    var assembly = _incomingFrames[key];
    if (assembly == null) {
      if (_incomingFrameAssembliesForPeer(peer) >=
          brain2SyncFrameMaxAssemblies) {
        throw StateError('Too many concurrent Brain2 frame assemblies');
      }
      assembly = _Brain2FrameAssembly(total);
      _incomingFrames[key] = assembly;
    }
    if (assembly.total != total) {
      _incomingFrames.remove(key);
      throw StateError('Brain2 transport frame total changed');
    }
    if (assembly.parts[index] != null) return;

    if (_incomingFrameBytesForPeer(peer) + bytes.length >
        _brain2TransportMaxReassembledBytes) {
      _incomingFrames.remove(key);
      throw StateError('Brain2 aggregate frame reassembly budget exceeded');
    }

    assembly.parts[index] = bytes;
    assembly.received += 1;
    assembly.bytes += bytes.length;
    assembly.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (assembly.received != assembly.total) return;

    final builder = BytesBuilder(copy: false);
    for (final part in assembly.parts) {
      if (part == null) {
        _incomingFrames.remove(key);
        throw StateError('Brain2 transport frame missing during reassembly');
      }
      builder.add(part);
    }
    _incomingFrames.remove(key);

    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
    if (decoded is! Map) {
      throw const FormatException(
        'Reassembled Brain2 message is not an object.',
      );
    }
    final map = decoded.cast<String, Object?>();
    brain2AssertWireMessageType(map['type']);
    await _message(peer, map);
  }

  bool get hasMemoryConflict => _memoryConflicts.isNotEmpty;

  void rememberMemoryConflict(String peer, String remoteRoot) {
    if (peer.isEmpty || remoteRoot.isEmpty) return;
    _memoryConflicts[peer] = {'memoryRoot': remoteRoot};
    _status(
      Brain2P2PStage.memoryConflict,
      'Different Brain2 memories detected. Merge both memories to preserve data from both replicas.',
      peer: peer,
    );
  }

  bool _channelIsOpen(String peer) =>
      _channels[peer]?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> _ensureOpenChannel(
    String peer, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_channelIsOpen(peer)) return;

    await connect(peer);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_channelIsOpen(peer)) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    throw StateError(
      'Brain2 P2P channel did not open after reconnect. '
      'Keep Web AI Miner open on the same network and retry.',
    );
  }

  Future<void> mergeBothMemories() async {
    if (_memoryConflicts.isEmpty) {
      throw StateError('No different Brain2 memory is waiting to merge.');
    }
    final peer = _memoryConflicts.keys.first;
    final remote = _memoryConflicts[peer]!;
    // The web pairing root survives as the identity/trust namespace. Data is
    // still a true union: neither web nor mobile is treated as the data master.
    final targetRoot = '${remote['memoryRoot'] ?? ''}';
    if (targetRoot.isEmpty) {
      throw StateError('Peer did not provide a memory root.');
    }
    // Never enter the merge state until the direct channel is actually
    // usable. If transport dropped, reconnect first and wait for OPEN.
    await _ensureOpenChannel(peer);

    _merging = true;
    _mergePhase = 'REQUESTED';
    _mergeSeedOrdinal = 0;
    _status(
      Brain2P2PStage.bootstrapping,
      'Preparing deterministic merge. No local conversation data will be deleted…',
      peer: peer,
    );
    try {
      await _send(peer, {
        'type': 'merge_request',
        'targetRoot': targetRoot,
        'localSummary': await _summary(),
      });
    } catch (error) {
      _merging = false;
      _mergePhase = 'IDLE';
      _mergeSeedOrdinal = 0;
      _status(
        Brain2P2PStage.memoryConflict,
        'Merge transport failed before data transfer. Reconnect and retry. ($error)',
        peer: peer,
      );
      rethrow;
    }
  }

  Future<void> connect(String peer) async {
    if (peer == deviceId) {
      throw StateError('Cannot connect a Brain2 device to itself.');
    }

    final existingChannel = _channels[peer];
    if (existingChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      await _hello(peer);
      return;
    }

    final oldPc = _pcs.remove(peer);
    if (oldPc != null) await oldPc.close();
    _channels.remove(peer);
    _pendingIce.remove(peer);
    _remoteDescriptionReady.remove(peer);
    _awaitingRemoteAnswer.remove(peer);
    _awaitingAck.remove(peer);
    _outboundManifestHash.remove(peer);
    _outboundToSequence.remove(peer);
    _bootstrapExpectedOrdinal.remove(peer);
    _clearTransportFrames(peer);
    if (!_merging) {
      _mergePhase = 'IDLE';
      _mergeSeedOrdinal = 0;
    }

    _status(
      Brain2P2PStage.signaling,
      'Creating WebRTC offer…',
      peer: peer,
    );

    final pc = await _pc(peer);
    final channel = await pc.createDataChannel(
      brain2SyncChannel,
      RTCDataChannelInit()..ordered = true,
    );
    _attach(peer, channel);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _awaitingRemoteAnswer.add(peer);
    await api.postSignal(
      fromDeviceId: deviceId,
      token: deviceToken,
      toDeviceId: peer,
      kind: 'offer',
      payload: offer.toMap(),
    );
    _status(
      Brain2P2PStage.signaling,
      'Offer sent. Waiting for the web replica…',
      peer: peer,
    );
  }

  Future<void> _setRemoteDescription(
    String peer,
    RTCPeerConnection pc,
    RTCSessionDescription description,
  ) async {
    await pc.setRemoteDescription(description);
    _remoteDescriptionReady.add(peer);
    final queued = _pendingIce.remove(peer) ?? const <RTCIceCandidate>[];
    for (final candidate in queued) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {
        // A later ICE candidate can still establish the connection. The signal
        // itself has already been integrity/authorization checked server-side.
      }
    }
  }

  Future<void> _addIce(String peer, RTCIceCandidate candidate) async {
    if (!_remoteDescriptionReady.contains(peer)) {
      (_pendingIce[peer] ??= []).add(candidate);
      return;
    }
    final pc = await _pc(peer);
    await pc.addCandidate(candidate);
  }

  Future<void> _consumeSignalsSafe() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      await _consumeSignals();
    } catch (error) {
      _status(
        Brain2P2PStage.error,
        'Signaling error: $error',
      );
    } finally {
      _polling = false;
    }
  }

  Future<void> _consumeSignals() async {
    final signals = await api.pullSignals(deviceId, deviceToken);
    for (final signal in signals) {
      final signalId = '${signal['id'] ?? ''}';
      if (signalId.isNotEmpty && !_signalReplay.accept(signalId)) continue;
      final from = '${signal['fromDeviceId']}';
      final kind = '${signal['kind']}';
      final payload = (signal['payload'] as Map?)?.cast<String, dynamic>();

      if (kind == 'offer') {
        if (payload == null) throw StateError('Offer signal has no payload.');

        // In the QR golden flow the joining mobile is the deterministic
        // initiator. If a web-side manual Connect created a simultaneous offer,
        // do not apply it to the mobile initiator RTCPeerConnection: flutter_webrtc
        // can reject the subsequent SDP with an m-line ordering error. The web
        // peer will consume our mobile offer and answer it.
        if (_pcs.containsKey(from)) {
          _status(
            Brain2P2PStage.signaling,
            'Ignoring simultaneous web offer; waiting for the answer to the mobile offer…',
            peer: from,
          );
          continue;
        }

        final pc = await _pc(from);
        _status(
          Brain2P2PStage.signaling,
          'WebRTC offer received. Sending answer…',
          peer: from,
        );
        await _setRemoteDescription(
          from,
          pc,
          RTCSessionDescription('${payload['sdp']}', '${payload['type']}'),
        );
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await api.postSignal(
          fromDeviceId: deviceId,
          token: deviceToken,
          toDeviceId: from,
          kind: 'answer',
          payload: answer.toMap(),
        );
      } else if (kind == 'answer') {
        if (payload == null) throw StateError('Answer signal has no payload.');
        final pc = _pcs[from];

        // Signaling mailboxes can contain a delayed/duplicate answer from an
        // earlier offer. Applying an answer after the PeerConnection is already
        // stable throws WEBRTC_SET_REMOTE_DESCRIPTION_ERROR. Only the current
        // locally-created offer is allowed to consume one answer.
        if (!brain2ShouldApplyRemoteAnswer(
          hasPeerConnection: pc != null,
          awaitingRemoteAnswer: _awaitingRemoteAnswer.contains(from),
        )) {
          continue;
        }

        try {
          await _setRemoteDescription(
            from,
            pc!,
            RTCSessionDescription('${payload['sdp']}', '${payload['type']}'),
          );
          _awaitingRemoteAnswer.remove(from);
        } catch (error) {
          final message = '$error';
          if (message.contains('wrong state: stable') ||
              message.contains('Called in wrong state: stable')) {
            _awaitingRemoteAnswer.remove(from);
            continue;
          }
          rethrow;
        }
      } else if (kind == 'ice' && payload != null) {
        final rawIndex = payload['sdpMLineIndex'];
        final index =
            rawIndex is num ? rawIndex.toInt() : int.tryParse('$rawIndex');
        await _addIce(
          from,
          RTCIceCandidate(
            payload['candidate'] as String?,
            payload['sdpMid'] as String?,
            index,
          ),
        );
      } else if (kind == 'bye') {
        final pc = _pcs[from];
        if (pc != null) await pc.close();
        _pcs.remove(from);
        _channels.remove(from);
        _pendingIce.remove(from);
        _remoteDescriptionReady.remove(from);
        _status(
          Brain2P2PStage.disconnected,
          'Peer ended the session.',
          peer: from,
        );
      }
    }
  }

  void _scheduleHello(String peer) {
    if (_merging) return;
    // _attach() stores the channel before WebRTC reports OPEN. Mutation/reconcile
    // timers must not attempt hello while the channel is still CONNECTING.
    if (!_channelIsOpen(peer)) return;
    unawaited(_hello(peer).catchError((Object error) {
      if (!_channelIsOpen(peer)) {
        _status(
          Brain2P2PStage.disconnected,
          'Peer channel changed state before hello completed. Reconnect will resume safely.',
          peer: peer,
        );
        return;
      }
      _status(
        Brain2P2PStage.error,
        'P2P hello failed: $error',
        peer: peer,
      );
    }));
  }

  Future<void> _sendPhysicalText(String peer, String text) async {
    final channel = _channels[peer];
    if (channel == null) {
      throw StateError('Brain2 P2P channel not open');
    }
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      // CONNECTING is a valid transient state. Keep it registered so the
      // onDataChannelState OPEN callback can finish the handshake.
      if (channel.state == RTCDataChannelState.RTCDataChannelClosed) {
        _channels.remove(peer);
      }
      throw StateError('Brain2 P2P channel not open');
    }
    while ((await channel.getBufferedAmount()) > 512 * 1024) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
        _channels.remove(peer);
        throw StateError('Brain2 P2P channel closed while draining');
      }
    }
    await channel.send(RTCDataChannelMessage(text));
  }

  Future<void> _send(String peer, Map<String, Object?> message) async {
    final raw = jsonEncode(message);
    final bytes = Uint8List.fromList(utf8.encode(raw));
    if (bytes.length > _brain2TransportMaxReassembledBytes) {
      throw StateError('Brain2 logical P2P message exceeded the 64 MiB limit');
    }
    if (bytes.length <= _brain2TransportFramePayloadBytes) {
      await _sendPhysicalText(peer, raw);
      return;
    }

    final id =
        '$deviceId-${DateTime.now().microsecondsSinceEpoch}-${_frameCounter++}';
    final total = (bytes.length + _brain2TransportFramePayloadBytes - 1) ~/
        _brain2TransportFramePayloadBytes;
    for (var index = 0; index < total; index++) {
      final start = index * _brain2TransportFramePayloadBytes;
      final end = (start + _brain2TransportFramePayloadBytes < bytes.length)
          ? start + _brain2TransportFramePayloadBytes
          : bytes.length;
      final frame = <String, Object?>{
        '__brain2Frame': 1,
        'id': id,
        'index': index,
        'total': total,
        'data': base64Encode(Uint8List.sublistView(bytes, start, end)),
      };
      await _sendPhysicalText(peer, jsonEncode(frame));
    }
  }

  Future<Map<String, Object?>> _summary() async => {
        'deviceId': deviceId,
        'memoryRoot': await db.memoryRoot(),
        'latestLocalSequence':
            int.tryParse(await db.meta('origin_sequence')) ?? 0,
        'totalMessages': await db.total('messages'),
        'totalAtoms': await db.total('atoms'),
        'totalTruths': await db.total('truths'),
        'reader': brain2RetrievalVersion,
      };

  Future<void> _hello(String peer) async {
    _status(
      Brain2P2PStage.verifyingMemory,
      'Verifying Brain2 memory root…',
      peer: peer,
    );
    await _send(peer, {'type': 'hello', 'summary': await _summary()});
  }

  Future<void> _message(String peer, Map<String, Object?> message) async {
    brain2AssertWireMessageType(message['type']);
    switch ('${message['type']}') {
      case 'hello':
        if (_merging) {
          throw StateError('Brain2 hello is not allowed during an active merge');
        }
        if (message['summary'] is! Map) {
          throw StateError('Invalid Brain2 hello summary');
        }
        final remote = (message['summary'] as Map).cast<String, Object?>();
        final localRoot = await db.memoryRoot();
        final remoteRoot = '${remote['memoryRoot']}';
        if (remoteRoot != localRoot) {
          _memoryConflicts[peer] = remote;
          _status(
            Brain2P2PStage.memoryConflict,
            'Different Brain2 memories detected. Merge both memories to preserve data from both replicas.',
            peer: peer,
          );
          break;
        }
        if (_memoryConflicts.containsKey(peer) && !_merging) {
          _status(
            Brain2P2PStage.memoryConflict,
            'An interrupted Brain2 merge is waiting to resume. Merge both memories again to continue safely.',
            peer: peer,
          );
          break;
        }
        _memoryConflicts.remove(peer);
        final localMessages = await db.total('messages');
        final remoteMessages = remote['totalMessages'] is num
            ? (remote['totalMessages'] as num).toInt()
            : int.tryParse('${remote['totalMessages']}') ?? 0;
        final remoteLatest = remote['latestLocalSequence'] is num
            ? (remote['latestLocalSequence'] as num).toInt()
            : int.tryParse('${remote['latestLocalSequence']}') ?? 0;
        _remoteMessageCount[peer] = remoteMessages;
        _remoteAtomCount[peer] = remote['totalAtoms'] is num
            ? (remote['totalAtoms'] as num).toInt()
            : int.tryParse('${remote['totalAtoms']}') ?? 0;
        _remoteTruthCount[peer] = remote['totalTruths'] is num
            ? (remote['totalTruths'] as num).toInt()
            : int.tryParse('${remote['totalTruths']}') ?? 0;
        _remoteLatestSequence[peer] = remoteLatest;
        final inboundApplied = await db.peerCursor(peer, peer);
        if (localMessages == 0 && remoteMessages > 0) {
          _status(
            Brain2P2PStage.bootstrapping,
            'Memory verified. Requesting initial bootstrap…',
            peer: peer,
          );
          _bootstrapExpectedOrdinal[peer] = 0;
          await _send(peer, {'type': 'bootstrap_request'});
        } else if (remoteMessages == 0 && localMessages > 0) {
          // The empty peer will request the bootstrap. Waiting avoids sending
          // the complete mutation history at the same time as the snapshot.
          _status(
            Brain2P2PStage.bootstrapping,
            'Memory verified. Waiting for peer bootstrap request…',
            peer: peer,
          );
        } else {
          _status(
            Brain2P2PStage.syncingDeltas,
            'Memory verified. Synchronizing missing deltas…',
            peer: peer,
          );
          if (remoteLatest > inboundApplied) {
            await _send(peer, {
              'type': 'sync_request',
              'fromSequence': inboundApplied + 1,
            });
          }
          _scheduleFlush(peer, immediate: true);
        }
        break;

      case 'sync_request':
        if (_merging) {
          throw StateError('Sync request is not allowed during an active merge');
        }
        _scheduleFlush(peer, immediate: true);
        break;

      case 'merge_accept':
        final targetRoot = '${message['targetRoot'] ?? ''}';
        final remote = _memoryConflicts[peer];
        if (!_merging || _mergePhase != 'REQUESTED') {
          throw StateError('Unexpected Brain2 merge_accept');
        }
        if (remote == null || targetRoot != '${remote['memoryRoot']}') {
          throw StateError('Unexpected Brain2 merge target.');
        }
        final oldRoot = await db.memoryRoot();
        await db.beginMemoryMerge(
          targetRoot,
          parentRoots: [oldRoot, targetRoot],
        );
        await onMemoryRootChanged?.call(targetRoot);
        _mergePhase = 'RECEIVING_SEED';
        _mergeSeedOrdinal = 0;
        _status(
          Brain2P2PStage.bootstrapping,
          'Merge accepted. Receiving the web replica into this phone…',
          peer: peer,
        );
        await _send(peer, {'type': 'merge_ready', 'targetRoot': targetRoot});
        break;

      case 'merge_seed_chunk':
        if (!_merging || _mergePhase != 'RECEIVING_SEED') {
          throw StateError('Unexpected Brain2 merge seed chunk');
        }
        final targetRoot = '${message['targetRoot'] ?? ''}';
        if (targetRoot != await db.memoryRoot()) {
          throw StateError('Brain2 merge seed root mismatch');
        }
        final ordinal = message['ordinal'] is num
            ? (message['ordinal'] as num).toInt()
            : int.tryParse('${message['ordinal']}') ?? -1;
        if (ordinal != _mergeSeedOrdinal) {
          throw StateError(
            'Brain2 merge seed ordinal mismatch: '
            'expected $_mergeSeedOrdinal, got $ordinal',
          );
        }
        final wireTable = '${message['table'] ?? ''}';
        final recordsJson = '${message['recordsJson'] ?? ''}';
        final expected = '${message['chunkHash'] ?? ''}';
        if (sha256Hex(recordsJson) != expected) {
          throw StateError('Brain2 merge chunk hash mismatch');
        }
        final decodedRecords = jsonDecode(recordsJson);
        if (decodedRecords is! List) {
          throw StateError('Brain2 merge chunk is not a record list');
        }
        final records = decodedRecords
            .map((e) => (e as Map).cast<String, Object?>())
            .toList(growable: false);
        await db.applyMergeChunk(targetRoot, wireTable, records);
        _mergeSeedOrdinal += 1;
        _status(
          Brain2P2PStage.bootstrapping,
          'Merging web data · $wireTable',
          peer: peer,
        );
        break;

      case 'merge_seed_complete':
        if (!_merging || _mergePhase != 'RECEIVING_SEED') {
          throw StateError('Unexpected Brain2 merge seed completion');
        }
        final targetRoot = '${message['targetRoot'] ?? ''}';
        if (targetRoot != await db.memoryRoot()) {
          throw StateError('Brain2 merge root changed unexpectedly');
        }
        _status(
          Brain2P2PStage.bootstrapping,
          'Web data merged. Returning the combined replica for convergence…',
          peer: peer,
        );
        _mergePhase = 'RETURNING';
        await _sendMergeReturn(peer, targetRoot);
        _mergePhase = 'AWAITING_COMPLETE';
        break;

      case 'merge_complete':
        if (!_merging || _mergePhase != 'AWAITING_COMPLETE') {
          throw StateError('Unexpected Brain2 merge completion');
        }
        final targetRoot = '${message['targetRoot'] ?? ''}';
        if (targetRoot != await db.memoryRoot()) {
          throw StateError('Brain2 merge completion root mismatch');
        }
        await db.finalizeMemoryMerge();
        _memoryConflicts.remove(peer);
        _merging = false;
        _mergePhase = 'IDLE';
        _mergeSeedOrdinal = 0;
        _status(
          Brain2P2PStage.syncingDeltas,
          'Both memories merged. Rechecking ordered deltas…',
          peer: peer,
        );
        await _hello(peer);
        break;

      case 'bootstrap_request':
        _status(
          Brain2P2PStage.bootstrapping,
          'Sending initial Brain2 bootstrap…',
          peer: peer,
        );
        await _sendBootstrap(peer);
        break;

      case 'bootstrap_chunk':
        final memoryRoot = '${message['memoryRoot']}';
        final wireTable = '${message['table']}';
        final ordinal = message['ordinal'] is num
            ? (message['ordinal'] as num).toInt()
            : int.parse('${message['ordinal']}');
        final expectedOrdinal = _bootstrapExpectedOrdinal[peer];
        if (expectedOrdinal == null || ordinal != expectedOrdinal) {
          throw StateError(
            'Brain2 bootstrap ordinal mismatch: '
            'expected ${expectedOrdinal ?? 0}, got $ordinal',
          );
        }
        final expected = '${message['chunkHash']}';

        late final List<Map<String, Object?>> records;
        late final String actual;
        if (message['hashVersion'] == 3 && message['recordsJson'] is String) {
          final recordsJson = message['recordsJson'] as String;
          actual = _hashBootstrapWireChunk(
            memoryRoot,
            wireTable,
            ordinal,
            recordsJson,
          );
          final decoded = jsonDecode(recordsJson);
          if (decoded is! List) {
            throw StateError('Brain2 bootstrap recordsJson is not a list');
          }
          records = decoded
              .map((e) => (e as Map).cast<String, Object?>())
              .toList(growable: false);
        } else {
          records = (message['records'] as List)
              .map((e) => (e as Map).cast<String, Object?>())
              .toList(growable: false);
          actual = sha256Hex(
            canonicalJson({
              'memoryRoot': memoryRoot,
              'table': wireTable,
              'ordinal': ordinal,
              'records': records,
            }),
          );
        }
        if (actual != expected) {
          throw StateError('Brain2 bootstrap chunk hash mismatch');
        }
        if (wireTable == 'mutations') {
          var maxSequence = _bootstrapPeerMaxSequence[peer] ?? 0;
          for (final record in records) {
            final origin =
                '${record['originDeviceId'] ?? record['deviceId'] ?? ''}';
            if (origin != peer) continue;
            final raw = record['originSequence'] ?? record['sequence'];
            final sequence =
                raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
            if (sequence > maxSequence) maxSequence = sequence;
          }
          _bootstrapPeerMaxSequence[peer] = maxSequence;
        }
        await db.applyBootstrapChunk(memoryRoot, wireTable, records);
        _bootstrapExpectedOrdinal[peer] = ordinal + 1;

        // Receiver-side backpressure:
        // ACK only after the bootstrap chunk is durably committed to SQLite.
        await _send(peer, {
          'type': 'bootstrap_ack',
          'ordinal': ordinal,
        });

        _status(
          Brain2P2PStage.bootstrapping,
          'Receiving Brain2 bootstrap · $wireTable',
          peer: peer,
          processed: ordinal + 1,
        );
        break;

      case 'bootstrap_complete':
        if (_bootstrapExpectedOrdinal[peer] == null) {
          throw StateError('Unexpected Brain2 bootstrap completion');
        }
        if ('${message['memoryRoot']}' != await db.memoryRoot()) {
          throw StateError('bootstrap memory-root mismatch');
        }
        await db.finalizeBootstrap();
        _bootstrapExpectedOrdinal.remove(peer);
        final bootstrappedPeerSequence =
            _bootstrapPeerMaxSequence.remove(peer) ?? 0;
        if (bootstrappedPeerSequence > 0) {
          await db.setPeerCursor(peer, peer, bootstrappedPeerSequence);
          await _send(peer, {
            'type': 'ack',
            'originDeviceId': peer,
            'sequence': bootstrappedPeerSequence,
          });
        }
        _status(
          Brain2P2PStage.syncingDeltas,
          'Bootstrap complete. Checking for newer deltas…',
          peer: peer,
        );
        await _hello(peer);
        break;

      case 'mutations':
        final rawMutations = message['mutations'];
        if (rawMutations is! List ||
            rawMutations.isEmpty ||
            rawMutations.length > brain2SyncMutationBatchMax) {
          throw StateError('Invalid Brain2 mutation batch size');
        }
        final list = rawMutations
            .map(
              (e) => _mutationFromJson(
                (e as Map).cast<String, Object?>(),
              ),
            )
            .toList()
          ..sort((a, b) => a.originSequence.compareTo(b.originSequence));

        final fromSequence = message['fromSequence'] is num
            ? (message['fromSequence'] as num).toInt()
            : int.tryParse('${message['fromSequence']}') ?? -1;
        final toSequence = message['toSequence'] is num
            ? (message['toSequence'] as num).toInt()
            : int.tryParse('${message['toSequence']}') ?? -1;
        if (!brain2SequenceRangeMatches(
          list.map((mutation) => mutation.originSequence).toList(),
          fromSequence,
          toSequence,
        )) {
          throw StateError('Brain2 mutation batch sequence range mismatch');
        }

        final manifestHash = sha256Hex(
          list
              .map(
                (x) => '${x.originSequence}:${x.id}:${x.payloadHash}',
              )
              .join('|'),
        );
        if (manifestHash != '${message['manifestHash']}') {
          throw StateError('mutation batch manifest mismatch');
        }

        final localRoot = await db.memoryRoot();
        for (final mutation in list) {
          if (mutation.originDeviceId != peer) {
            throw StateError('mutation origin device mismatch');
          }
          if (mutation.memoryRoot != localRoot) {
            throw StateError('mutation memory-root mismatch');
          }
          final payloadHash =
              sha256Hex(canonicalJson(mutation.payload.toJson()));
          if (payloadHash != mutation.payloadHash) {
            throw StateError('mutation payload hash mismatch');
          }
          final expectedEnvelope = MutationRecord.envelopeHash(
            memoryRoot: mutation.memoryRoot,
            originDeviceId: mutation.originDeviceId,
            originSequence: mutation.originSequence,
            type: mutation.type,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            payloadHash: mutation.payloadHash,
            parents: mutation.parentMutationIds,
          );
          if (expectedEnvelope != mutation.hash) {
            throw StateError('mutation envelope hash mismatch');
          }
        }

        var lastApplied = await db.peerCursor(peer, peer);
        for (final mutation in list) {
          final gapExpected = brain2MutationGapExpected(
            lastApplied,
            mutation.originSequence,
          );
          if (gapExpected != null) {
            throw StateError(
              'mutation gap: expected $gapExpected, '
              'got ${mutation.originSequence}',
            );
          }
          await db.applyMutation(mutation);
          if (mutation.originSequence > lastApplied) {
            lastApplied = mutation.originSequence;
          }
        }
        await db.setPeerCursor(peer, peer, lastApplied);
        await _send(peer, {
          'type': 'ack',
          'originDeviceId': peer,
          'sequence': lastApplied,
          'manifestHash': manifestHash,
        });
        await _markConvergedIfPossible(peer);
        break;

      case 'ack':
        if (!_awaitingAck.contains(peer)) break;
        final origin = '${message['originDeviceId'] ?? deviceId}';
        final sequence = message['sequence'] is num
            ? (message['sequence'] as num).toInt()
            : int.tryParse('${message['sequence']}') ?? 0;
        final manifestHash = '${message['manifestHash'] ?? ''}';
        if (!brain2AckMatchesPending(
          awaiting: _awaitingAck.contains(peer),
          pendingManifestHash: _outboundManifestHash[peer] ?? '',
          pendingToSequence: _outboundToSequence[peer] ?? 0,
          ackManifestHash: manifestHash,
          ackSequence: sequence,
          ackOriginDeviceId: origin,
          localDeviceId: deviceId,
        )) {
          throw StateError(
            'Brain2 ACK does not match the pending mutation batch',
          );
        }
        await db.setPeerCursor(peer, origin, sequence);
        _awaitingAck.remove(peer);
        _outboundManifestHash.remove(peer);
        _outboundToSequence.remove(peer);
        _scheduleFlush(peer);
        await _markConvergedIfPossible(peer);
        break;

      case 'bootstrap_ack':
        break;

      case 'ping':
        break;

      default:
        throw StateError(
          'Unsupported Brain2 P2P message type: ${message['type']}',
        );
    }
  }

  void _scheduleFlush(String peer, {bool immediate = false}) {
    if (_flushScheduled.contains(peer)) return;
    _flushScheduled.add(peer);
    Future<void>.delayed(
      immediate ? Duration.zero : const Duration(milliseconds: 80),
      () async {
        _flushScheduled.remove(peer);
        if (_awaitingAck.contains(peer)) return;
        try {
          await _sendPending(peer);
        } catch (_) {
          // The durable mutation cursor is unchanged. Signaling/reconnect will
          // safely retry the exact missing range later.
        }
      },
    );
  }

  Future<void> _sendBootstrap(String peer) async {
    final root = await db.memoryRoot();
    var ordinal = 0;
    for (final localTable in [
      ...Brain2Database.syncBootstrapTables,
      'mutations',
    ]) {
      final wireTable = localTable == 'mutations'
          ? 'mutations'
          : brain2WireTableForLocal(localTable);
      var offset = 0;
      while (true) {
        final page = await db.bootstrapRecordsPage(
          localTable,
          offset: offset,
          limit: 256,
        );
        if (page.isEmpty) break;
        offset += page.length;

        var chunk = <Map<String, Object?>>[];
        var bytes = 2;

        Future<void> flush() async {
          if (chunk.isEmpty) return;
          final current = List<Map<String, Object?>>.from(chunk);
          // Serialize once and hash the exact JSON text that crosses the wire.
          // This avoids Dart↔JavaScript canonicalization differences.
          final recordsJson = jsonEncode(current);
          final hash = _hashBootstrapWireChunk(
            root,
            wireTable,
            ordinal,
            recordsJson,
          );
          await _send(peer, {
            'type': 'bootstrap_chunk',
            'memoryRoot': root,
            'table': wireTable,
            'recordsJson': recordsJson,
            'hashVersion': 3,
            'ordinal': ordinal,
            'chunkHash': hash,
          });
          ordinal++;
          chunk = <Map<String, Object?>>[];
          bytes = 2;
          _status(
            Brain2P2PStage.bootstrapping,
            'Sending Brain2 bootstrap · $wireTable',
            peer: peer,
            processed: ordinal,
          );
        }

        for (final record in page) {
          final size = utf8.encode(canonicalJson(record)).length + 1;
          if (chunk.isNotEmpty &&
              bytes + size > brain2SyncBootstrapChunkBytes) {
            await flush();
          }
          chunk.add(record);
          bytes += size;
        }
        await flush();

        if (page.length < 256) break;
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _send(peer, {
      'type': 'bootstrap_complete',
      'memoryRoot': root,
    });
  }

  Future<void> _markConvergedIfPossible(String peer) async {
    final localLatest = int.tryParse(await db.meta('origin_sequence')) ?? 0;
    final outboundAcked = await db.peerCursor(peer, deviceId);
    final inboundApplied = await db.peerCursor(peer, peer);
    final remoteLatest = _remoteLatestSequence[peer] ?? 0;
    final remoteMessages = _remoteMessageCount[peer] ?? 0;
    final remoteAtoms = _remoteAtomCount[peer] ?? 0;
    final remoteTruths = _remoteTruthCount[peer] ?? 0;
    final localMessages = await db.total('messages');
    final localAtoms = await db.total('atoms');
    final localTruths = await db.total('truths');
    final inboundOk = inboundApplied >= remoteLatest;
    final outboundOk = outboundAcked >= localLatest;
    final countsMatch = localMessages == remoteMessages &&
        localAtoms == remoteAtoms &&
        localTruths == remoteTruths;

    if (inboundOk && outboundOk && countsMatch) {
      _status(
        Brain2P2PStage.synced,
        'Brain2 replicas are synchronized · local $localMessages messages · peer $remoteMessages messages.',
        peer: peer,
      );
    } else {
      _status(
        Brain2P2PStage.syncingDeltas,
        'Connected · waiting for missing Brain2 deltas…',
        peer: peer,
      );
    }
  }

  Future<void> _sendMergeReturn(String peer, String targetRoot) async {
    var ordinal = 0;
    for (final localTable in Brain2Database.mergeSnapshotTables) {
      final wireTable = brain2WireTableForLocal(localTable);
      if (!brain2WebMergeWireTables.contains(wireTable)) continue;

      var offset = 0;
      while (true) {
        final page = await db.bootstrapRecordsPage(
          localTable,
          offset: offset,
          limit: 128,
        );
        if (page.isEmpty) break;
        offset += page.length;

        var chunk = <Map<String, Object?>>[];
        var bytes = 2;

        Future<void> flush() async {
          if (chunk.isEmpty) return;
          final current = List<Map<String, Object?>>.from(chunk);
          final recordsJson = jsonEncode(current);
          await _send(peer, {
            'type': 'merge_return_chunk',
            'targetRoot': targetRoot,
            'table': wireTable,
            'ordinal': ordinal++,
            'recordsJson': recordsJson,
            'chunkHash': sha256Hex(recordsJson),
          });
          chunk = <Map<String, Object?>>[];
          bytes = 2;
          _status(
            Brain2P2PStage.bootstrapping,
            'Returning merged Brain2 data · $wireTable',
            peer: peer,
            processed: ordinal,
          );
        }

        for (final record in page) {
          final size = utf8.encode(canonicalJson(record)).length + 1;
          if (chunk.isNotEmpty &&
              bytes + size > brain2SyncBootstrapChunkBytes) {
            await flush();
          }
          chunk.add(record);
          bytes += size;
        }
        await flush();

        if (page.length < 128) break;
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _send(peer, {
      'type': 'merge_return_complete',
      'targetRoot': targetRoot,
    });
  }

  Future<void> _sendPending(String peer) async {
    if (_merging) return;
    final cursor = await db.peerCursor(peer, deviceId);
    final mutations = await db.pendingLocalAfter(
      deviceId,
      cursor,
      limit: brain2SyncBatchLimit,
    );
    if (mutations.isEmpty) {
      await _markConvergedIfPossible(peer);
      return;
    }

    final manifestHash = sha256Hex(
      mutations
          .map(
            (x) => '${x.originSequence}:${x.id}:${x.payloadHash}',
          )
          .join('|'),
    );
    _awaitingAck.add(peer);
    _outboundManifestHash[peer] = manifestHash;
    _outboundToSequence[peer] = mutations.last.originSequence;
    try {
      await _send(peer, {
        'type': 'mutations',
        'mutations': mutations.map((e) => e.toJson()).toList(),
        'manifestHash': manifestHash,
        'originDeviceId': deviceId,
        'fromSequence': mutations.first.originSequence,
        'toSequence': mutations.last.originSequence,
      });
      _status(
        Brain2P2PStage.syncingDeltas,
        'Sent deltas ${mutations.first.originSequence}–'
        '${mutations.last.originSequence}; waiting for ACK…',
        peer: peer,
      );
    } catch (_) {
      _awaitingAck.remove(peer);
      _outboundManifestHash.remove(peer);
      _outboundToSequence.remove(peer);
      rethrow;
    }
  }

  MutationRecord _mutationFromJson(Map<String, Object?> json) {
    final payload = (json['payload'] as Map).cast<String, Object?>();
    final writes = ((payload['writes'] as Map?) ?? {}).map(
      (k, v) => MapEntry(
        '$k',
        (v as List).map((e) => (e as Map).cast<String, Object?>()).toList(),
      ),
    );
    final deletes = ((payload['deletes'] as Map?) ?? {}).map(
      (k, v) => MapEntry('$k', (v as List).map((e) => '$e').toList()),
    );
    final rawSequence = json['originSequence'];
    final sequence =
        rawSequence is num ? rawSequence.toInt() : int.parse('$rawSequence');
    return MutationRecord(
      id: '${json['id']}',
      type: '${json['type']}',
      entityType: '${json['entityType']}',
      entityId: '${json['entityId']}',
      createdAt: '${json['createdAt']}',
      deviceId: '${json['deviceId']}',
      hash: '${json['hash']}',
      memoryRoot: '${json['memoryRoot']}',
      originDeviceId: '${json['originDeviceId']}',
      originSequence: sequence,
      payloadHash: '${json['payloadHash']}',
      payload: MutationDeltaPayload(
        operation: '${payload['operation']}',
        writes: writes,
        deletes: deletes,
        primaryTable: payload['primaryTable'] as String?,
      ),
      parentMutationIds:
          (json['parentMutationIds'] as List? ?? []).map((e) => '$e').toList(),
      beforeHash: json['beforeHash'] as String?,
      afterHash: json['afterHash'] as String?,
    );
  }
}
