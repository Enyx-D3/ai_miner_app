import 'package:brain2_ai_miner_mobile/sync/dev_tls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = '192.168.0.213';
  const fingerprint =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('debug accepts exact configured host and certificate fingerprint', () {
    expect(
      brain2AllowsDevCertificate(
        debugBuild: true,
        configuredHost: host,
        configuredSha256: fingerprint,
        requestHost: host,
        certificateSha256: fingerprint,
      ),
      isTrue,
    );
  });

  test('debug rejects wrong certificate fingerprint', () {
    expect(
      brain2AllowsDevCertificate(
        debugBuild: true,
        configuredHost: host,
        configuredSha256: fingerprint,
        requestHost: host,
        certificateSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
      isFalse,
    );
  });

  test('debug rejects matching certificate for a different host', () {
    expect(
      brain2AllowsDevCertificate(
        debugBuild: true,
        configuredHost: host,
        configuredSha256: fingerprint,
        requestHost: '192.168.0.214',
        certificateSha256: fingerprint,
      ),
      isFalse,
    );
  });

  test('debug without configured fingerprint uses normal TLS only', () {
    expect(
      brain2AllowsDevCertificate(
        debugBuild: true,
        configuredHost: host,
        configuredSha256: '',
        requestHost: host,
        certificateSha256: fingerprint,
      ),
      isFalse,
    );
  });

  test('release rejects the debug override path', () {
    expect(
      brain2AllowsDevCertificate(
        debugBuild: false,
        configuredHost: host,
        configuredSha256: fingerprint,
        requestHost: host,
        certificateSha256: fingerprint,
      ),
      isFalse,
    );
  });

  test('fingerprint normalization allows colon separated uppercase input', () {
    expect(
      normalizeCertificateSha256('AA:BB cc'),
      'aabbcc',
    );
  });
}
