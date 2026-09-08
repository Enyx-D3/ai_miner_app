import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../storage/brain2_database.dart';
import 'network_client.dart';
import 'p2p_sync.dart';

class Brain2PairingInvite {
  final Uri url;
  final String joinToken;
  final String inviterDeviceId;
  final DateTime? expiresAt;
  final String signalingOrigin;
  final int protocolVersion;

  const Brain2PairingInvite({
    required this.url,
    required this.joinToken,
    required this.inviterDeviceId,
    required this.expiresAt,
    required this.signalingOrigin,
    required this.protocolVersion,
  });
}

class Brain2MobilePairing {
  static const _originKey = 'brain2_network_origin';
  static const _tokenKey = 'brain2_network_token';
  static const _deviceKey = 'brain2_network_device_id';
  static const _peerKey = 'brain2_network_peer_device_id';
  static const _rootKey = 'brain2_network_memory_root';
  static const _iceKey = 'brain2_network_ice_servers';

  final Brain2Database db;
  final String deviceId;
  final Brain2P2PStatusCallback? onStatus;
  Brain2P2PSync? sync;

  Brain2MobilePairing(
    this.db,
    this.deviceId, {
    this.onStatus,
  });

  void _status(Brain2P2PStage stage, String message, {String? peer}) {
    onStatus?.call(
      Brain2P2PStatus(stage, message, peerDeviceId: peer),
    );
  }

  Brain2PairingInvite parse(String raw) {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException(
          'Brain2 pairing QR must contain an http/https URL.');
    }
    final token = uri.queryParameters['pair']?.trim();
    final peer = uri.queryParameters['peer']?.trim();
    if (token == null || token.isEmpty || peer == null || peer.isEmpty) {
      throw const FormatException('Not a Brain2 pairing QR.');
    }
    final expiresAt = DateTime.tryParse(uri.queryParameters['expires'] ?? '');
    if (expiresAt != null && expiresAt.isBefore(DateTime.now().toUtc())) {
      throw StateError('Brain2 pairing invitation expired.');
    }
    final protocolVersion = int.tryParse(uri.queryParameters['v'] ?? '') ?? 1;
    if (protocolVersion > 2) {
      throw StateError(
        'This Brain2 pairing QR uses sync protocol $protocolVersion, '
        'but this app supports protocol 2.',
      );
    }

    final explicitSignal = uri.queryParameters['signal']?.trim();
    String signalingOrigin;
    if (explicitSignal != null && explicitSignal.isNotEmpty) {
      final signalUri = Uri.parse(explicitSignal);
      if (signalUri.scheme != 'http' && signalUri.scheme != 'https') {
        throw const FormatException(
            'Brain2 signaling origin in QR is invalid.');
      }
      signalingOrigin = Uri(
        scheme: signalUri.scheme,
        host: signalUri.host,
        port: signalUri.hasPort ? signalUri.port : null,
      ).toString();
    } else {
      signalingOrigin = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ).toString();
    }

    return Brain2PairingInvite(
      url: uri,
      joinToken: token,
      inviterDeviceId: peer,
      expiresAt: expiresAt,
      signalingOrigin: signalingOrigin,
      protocolVersion: protocolVersion,
    );
  }

  Future<Brain2P2PSync> join(Brain2PairingInvite invite) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('brain2_mobile_device_id', deviceId);

    _status(
      Brain2P2PStage.signaling,
      'QR valid. Registering this phone as an authorized replica…',
      peer: invite.inviterDeviceId,
    );

    final api = Brain2NetworkClient(invite.signalingOrigin);
    final joined = await api.register(
      deviceId: deviceId,
      name: 'Brain2 AI Miner Mobile',
      kind: 'mobile',
      joinToken: invite.joinToken,
    );
    final token = '${joined['deviceToken'] ?? ''}';
    final root = '${joined['spaceId'] ?? ''}';
    if (token.isEmpty || root.isEmpty) {
      api.close();
      throw StateError(
          'Brain2 signaling server returned an incomplete pairing response.');
    }
    final protocol = joined['syncProtocolVersion'] is num
        ? (joined['syncProtocolVersion'] as num).toInt()
        : int.tryParse('${joined['syncProtocolVersion']}') ?? 2;
    if (protocol != 2) {
      api.close();
      throw StateError(
          'Brain2 sync protocol mismatch: server=$protocol, mobile=2.');
    }

    final localMessages = await db.total('messages');
    final localRoot = await db.memoryRoot();
    if (localMessages == 0) {
      await db.setMeta('memory_root', root);
    } else if (localRoot != root) {
      _status(
        Brain2P2PStage.memoryConflict,
        'Different Brain2 memories detected. Choose Merge both memories to preserve both replicas.',
        peer: invite.inviterDeviceId,
      );
    }

    final iceServers = _parseIceServers(joined['iceServers']);

    await prefs.setString(_originKey, invite.signalingOrigin);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_deviceKey, deviceId);
    await prefs.setString(_peerKey, invite.inviterDeviceId);
    await prefs.setString(_rootKey, await db.memoryRoot());
    await prefs.setString(_iceKey, jsonEncode(iceServers));

    await sync?.dispose();
    final peerSync = Brain2P2PSync(
      db: db,
      api: api,
      deviceId: deviceId,
      deviceToken: token,
      iceServers: iceServers,
      onStatus: onStatus,
      onMemoryRootChanged: (newRoot) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_rootKey, newRoot);
      },
    );
    await peerSync.start();
    await peerSync.connect(invite.inviterDeviceId);
    sync = peerSync;
    return peerSync;
  }

  Future<Brain2P2PSync?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final origin = prefs.getString(_originKey)?.trim() ?? '';
    final token = prefs.getString(_tokenKey)?.trim() ?? '';
    final storedDeviceId = prefs.getString(_deviceKey)?.trim() ?? '';
    final peer = prefs.getString(_peerKey)?.trim() ?? '';
    final storedRoot = prefs.getString(_rootKey)?.trim() ?? '';
    if (origin.isEmpty || token.isEmpty || peer.isEmpty) return null;
    if (storedDeviceId.isNotEmpty && storedDeviceId != deviceId) {
      throw StateError(
          'Stored Brain2 P2P credential belongs to another device identity.');
    }
    if (storedRoot.isNotEmpty && await db.memoryRoot() != storedRoot) {
      throw StateError(
          'Stored Brain2 P2P credential belongs to another memory root.');
    }

    final iceServers = _decodeStoredIce(prefs.getString(_iceKey));
    _status(
      Brain2P2PStage.signaling,
      'Restoring paired Brain2 session…',
      peer: peer,
    );
    final api = Brain2NetworkClient(origin);
    final peerSync = Brain2P2PSync(
      db: db,
      api: api,
      deviceId: deviceId,
      deviceToken: token,
      iceServers: iceServers,
      onStatus: onStatus,
      onMemoryRootChanged: (newRoot) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_rootKey, newRoot);
      },
    );
    await peerSync.start();
    await peerSync.connect(peer);
    sync = peerSync;
    return peerSync;
  }

  Future<void> forget() async {
    await sync?.dispose();
    sync = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _originKey,
      _tokenKey,
      _deviceKey,
      _peerKey,
      _rootKey,
      _iceKey,
    ]) {
      await prefs.remove(key);
    }
    _status(Brain2P2PStage.idle, 'Not paired');
  }

  List<Map<String, Object?>> _parseIceServers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  List<Map<String, Object?>> _decodeStoredIce(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return _parseIceServers(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }
}
