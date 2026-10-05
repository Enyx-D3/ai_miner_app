import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'dev_tls.dart';

class Brain2NetworkClient {
  final Uri base;
  final http.Client client;
  final Duration requestTimeout;

  Brain2NetworkClient(
    String baseUrl, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  })  : base = _parseBase(baseUrl),
        client = client ?? brain2HttpClientFor(_parseBase(baseUrl));

  static Uri _parseBase(String baseUrl) =>
      Uri.parse(baseUrl.replaceAll(RegExp(r'/$'), ''));

  Uri _u(String path) => base.replace(path: path, query: null);

  void _log(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // ignore: avoid_print
    print('[brain2.network] $message');
    developer.log(
      message,
      name: 'brain2.network',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<Map<String, Object?>> register({
    required String deviceId,
    String? spaceId,
    required String name,
    required String kind,
    String? joinToken,
    String? publicKey,
  }) async {
    final uri = _u('/api/brain2-sync/devices');
    final watch = Stopwatch()..start();
    _log('POST ${uri.path} start host=${uri.host}:${uri.port}');
    try {
      final r = await client
          .post(
            uri,
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
          .timeout(
            requestTimeout,
            onTimeout: () => _timeoutResponse('POST', uri, watch),
          );
      _log(
          'POST ${uri.path} status=${r.statusCode} elapsedMs=${watch.elapsedMilliseconds}');
      return _decode(r);
    } catch (error, stackTrace) {
      _log(
        'POST ${uri.path} failed elapsedMs=${watch.elapsedMilliseconds} error=$error',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> listDevices(
    String deviceId,
    String token,
  ) async {
    final u = _u('/api/brain2-sync/devices').replace(
      queryParameters: {'deviceId': deviceId},
    );
    final watch = Stopwatch()..start();
    _log('GET ${u.path} start host=${u.host}:${u.port}');
    final r =
        await client.get(u, headers: {'x-brain2-device-token': token}).timeout(
      requestTimeout,
      onTimeout: () => _timeoutResponse('GET', u, watch),
    );
    _log(
        'GET ${u.path} status=${r.statusCode} elapsedMs=${watch.elapsedMilliseconds}');
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
    final watch = Stopwatch()..start();
    _log('GET ${u.path} start host=${u.host}:${u.port}');
    final r =
        await client.get(u, headers: {'x-brain2-device-token': token}).timeout(
      requestTimeout,
      onTimeout: () => _timeoutResponse('GET', u, watch),
    );
    _log(
        'GET ${u.path} status=${r.statusCode} elapsedMs=${watch.elapsedMilliseconds}');
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
    final uri = _u('/api/brain2-sync/signals');
    final watch = Stopwatch()..start();
    _log('POST ${uri.path} start host=${uri.host}:${uri.port}');
    final r = await client
        .post(
          uri,
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
        .timeout(
          requestTimeout,
          onTimeout: () => _timeoutResponse('POST', uri, watch),
        );
    _log(
        'POST ${uri.path} status=${r.statusCode} elapsedMs=${watch.elapsedMilliseconds}');
    _decode(r);
  }

  http.Response _timeoutResponse(String method, Uri uri, Stopwatch watch) {
    final message =
        'Brain2 signaling $method ${uri.path} did not respond within ${requestTimeout.inSeconds} seconds.';
    _log('$method ${uri.path} timeout elapsedMs=${watch.elapsedMilliseconds}');
    return http.Response(
      jsonEncode({'error': message}),
      504,
      headers: {'content-type': 'application/json'},
    );
  }

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
      _log(
          'HTTP ${r.statusCode} error=${b['error'] ?? 'Brain2 network error'}');
      throw StateError('${b['error'] ?? 'Brain2 network error'}');
    }
    return b;
  }

  void close() => client.close();
}
