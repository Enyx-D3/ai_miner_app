import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/g11_sync_proof.dart';

Map<String, Object?> _map(Object? value) =>
    (value as Map).map((key, entry) => MapEntry('$key', entry));

List<Map<String, Object?>> _maps(Object? value) =>
    (value as List).map(_map).toList();

void main() {
  test('G11.1 rejects initial mutation gaps but accepts duplicates and contiguous deltas', () {
    expect(brain2MutationGapExpected(0, 1), isNull);
    expect(brain2MutationGapExpected(0, 3), 1);
    expect(brain2MutationGapExpected(2, 2), isNull);
    expect(brain2MutationGapExpected(2, 3), isNull);
    expect(brain2MutationGapExpected(2, 4), 3);
  });

  test('G11.1 proof roots match frozen cross-platform fixture', () {
    final fixture = _map(jsonDecode(
      File('spec/v1/g11-sync-proof-fixture.json').readAsStringSync(),
    ));
    final expected = _map(fixture['expected']);
    final truths = _maps(fixture['truths']);
    final mutations = _maps(fixture['mutations']);

    expect(brain2TruthStateRoot(truths), expected['truthStateRoot']);
    expect(brain2MutationFrontierRoot(mutations), expected['mutationFrontierRoot']);
    expect(brain2MutationFrontier(mutations), expected['frontier']);
  });
}
