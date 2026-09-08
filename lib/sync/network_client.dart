import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class Brain2NetworkClient {
  final Uri base;
  final http.Client client;
  final Duration requestTimeout;

  Brain2NetworkClient(
    String baseUrl, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  })  : base = Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), '')),
        client = client ?? http.Client();

  Uri _u(String path) => base.replace(path: path, query: null);

  Future<Map<String, Object?>> register({
    required String deviceId,
    String? spaceId,
    required String name,
    required String kind,
    String? joinToken,
    String? publicKey,
  }) async {
    final r = await client
        .post(
          _u('/api/brain2-sync/devices'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
            'spaceId': spaceId,
            'name': name,
            'kind': kind,
            'joinToken': joinToken,
            'publicKey': publicKey,
          }..removeWhere((k, v) => v == null)),
        )
        .timeout(requestTimeout, onTimeout: _timeoutResponse);
    return _decode(r);
  }

  Future<List<Map<String, Object?>>> listDevices(
    String deviceId,
    String token,
  ) async {
    final u = _u('/api/brain2-sync/devices').replace(
      queryParameters: {'deviceId': deviceId},
    );
    final r = await client.get(u, headers: {
      'x-brain2-device-token': token
    }).timeout(requestTimeout, onTimeout: _timeoutResponse);
    final b = _decode(r);
    return ((b['devices'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, Object?>())
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> pullSignals(
    String deviceId,
    String token,
  ) async {
    final u = _u('/api/brain2-sync/signals').replace(
      queryParameters: {'deviceId': deviceId},
    );
    final r = await client.get(u, headers: {
      'x-brain2-device-token': token
    }).timeout(requestTimeout, onTimeout: _timeoutResponse);
    final b = _decode(r);
    return ((b['signals'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, Object?>())
        .toList(growable: false);
  }

  Future<void> postSignal({
    required String fromDeviceId,
    required String token,
    required String toDeviceId,
    required String kind,
    required Object? payload,
  }) async {
    final r = await client
        .post(
          _u('/api/brain2-sync/signals'),
          headers: {
            'content-type': 'application/json',
            'x-brain2-device-token': token,
          },
          body: jsonEncode({
            'fromDeviceId': fromDeviceId,
            'toDeviceId': toDeviceId,
            'kind': kind,
            'payload': payload,
          }),
        )
        .timeout(requestTimeout, onTimeout: _timeoutResponse);
    _decode(r);
  }

  http.Response _timeoutResponse() => http.Response(
        jsonEncode({
          'error':
              'Brain2 signaling server did not respond within ${requestTimeout.inSeconds} seconds.',
        }),
        504,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object?> _decode(http.Response r) {
    Map<String, Object?> b;
    try {
      b = (jsonDecode(r.body) as Map).cast<String, Object?>();
    } catch (_) {
      b = {
        'error':
            'Brain2 signaling server returned invalid JSON (${r.statusCode}).'
      };
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError('${b['error'] ?? 'Brain2 network error'}');
    }
    return b;
  }

  void close() => client.close();
}
