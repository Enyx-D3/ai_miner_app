import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/core/identity.dart';
import 'package:brain2_ai_miner_mobile/core/r1_authority.dart';

void main() {
  final fixture =
      (jsonDecode(File('spec/v1/gc-cp001-fixture.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();
  test('GC-CP001 Unicode identity and stable hash vectors', () {
    for (final raw in (fixture['unicodeIdentityVectors'] as List).cast<Map>()) {
      final v = raw.cast<String, Object?>();
      expect(
          canonicalId('${v['prefix']}', (v['parts'] as List).cast<Object?>()),
          '${v['expected']}');
    }
    expect(sha256Hex(canonicalJson(fixture['resumeStablePayload'])),
        '${fixture['resumeStableHash']}');
    expect(sha256Hex(canonicalJson(fixture['contextStablePayload'])),
        '${fixture['contextStableHash']}');
  });
  test('R1 fail-closed signals', () {
    final allow = issueUserR1Allow(action: 'TEST', scope: 'fixture');
    expect(requireR1Allow(allow, action: 'TEST', scope: 'fixture').signal,
        Brain2R1Signal.allow);
    expect(
        () => requireR1Allow(issueVerifierR1(
            signal: 'REQUIRE_TICK',
            action: 'TEST',
            scope: 'fixture',
            reason: 'conflict')),
        throwsStateError);
    expect(() => parseR1Signal(''), throwsStateError);
  });
}
