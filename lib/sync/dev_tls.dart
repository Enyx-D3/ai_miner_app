import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const String brain2DevHost =
    String.fromEnvironment('BRAIN2_DEV_HOST', defaultValue: '');
const String brain2DevCertSha256 =
    String.fromEnvironment('BRAIN2_DEV_CERT_SHA256', defaultValue: '');

String normalizeCertificateSha256(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-f0-9]'), '');

bool brain2AllowsDevCertificate({
  required bool debugBuild,
  required String configuredHost,
  required String configuredSha256,
  required String requestHost,
  required String certificateSha256,
}) {
  final expected = normalizeCertificateSha256(configuredSha256);
  final actual = normalizeCertificateSha256(certificateSha256);
  return debugBuild &&
      configuredHost.isNotEmpty &&
      expected.length == 64 &&
      requestHost == configuredHost &&
      actual == expected;
}

http.Client brain2HttpClientFor(Uri base) {
  final expected = normalizeCertificateSha256(brain2DevCertSha256);
  if (!kDebugMode || brain2DevHost.isEmpty || expected.length != 64) {
    return http.Client();
  }

  final io = HttpClient();
  io.badCertificateCallback = (certificate, host, port) {
    final now = DateTime.now();
    final fingerprint = sha256.convert(certificate.der).toString();
    if (host != base.host ||
        now.isBefore(certificate.startValidity) ||
        now.isAfter(certificate.endValidity)) {
      return false;
    }
    return brain2AllowsDevCertificate(
      debugBuild: kDebugMode,
      configuredHost: brain2DevHost,
      configuredSha256: expected,
      requestHost: host,
      certificateSha256: fingerprint,
    );
  };
  return IOClient(io);
}
