import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/intelligence/r1_graph.dart';
import 'package:brain2_ai_miner_mobile/intelligence/r2_graph.dart';

Map<String, Object?> _map(Object? value) =>
    (value as Map).map((key, entry) => MapEntry('$key', entry));

List<Map<String, Object?>> _maps(Object? value) =>
    (value as List).map(_map).toList();

void main() {
  test('G11 golden graph root and truth semantics match the frozen cross-surface contract', () {
    final raw = jsonDecode(File('spec/v1/golden-graph-fixture.json').readAsStringSync());
    final fixture = _map(raw);
    expect(fixture['format'], 'B2_V1_GOLDEN_GRAPH_FIXTURE');
    expect(fixture['version'], 1);

    final assertions = _map(fixture['assertions']);
    final expected = _map(fixture['expected']);
    final atoms = _maps(fixture['atoms']);
    final truths = _maps(fixture['truths']);

    final graph = projectR1Graph(atoms: atoms, truths: truths);

    expect(
      graph.nodes.expand((node) => node.evidenceIds),
      isNot(contains('null')),
      reason: 'Missing evidence references must be omitted, never serialized as the literal string null.',
    );
    expect(graph.rootHash, expected['r1RootHash']);
    expect(graph.nodes.length, expected['r1NodeCount']);
    expect(graph.edges.length, expected['r1EdgeCount']);

    final truthIds = truths.map((truth) => '${truth['id']}').toSet();
    final currentTruthIds = graph.nodes
        .where((node) => node.truthStatus == 'CURRENT' && truthIds.contains(node.sourceRecordId))
        .map((node) => node.sourceRecordId!)
        .toList()
      ..sort();
    final expectedCurrent = (assertions['currentTruthSourceIds'] as List).map((e) => '$e').toList()..sort();
    expect(currentTruthIds, expectedCurrent);

    final supersededTruthIds = graph.nodes
        .where((node) => node.truthStatus == 'SUPERSEDED' && truthIds.contains(node.sourceRecordId))
        .map((node) => node.sourceRecordId!)
        .toList()
      ..sort();
    final expectedSuperseded = (assertions['supersededTruthSourceIds'] as List).map((e) => '$e').toList()..sort();
    expect(supersededTruthIds, expectedSuperseded);

    final edgeTypes = graph.edges.map((edge) => edge.type).toSet();
    for (final required in assertions['mustContainEdgeTypes'] as List) {
      expect(edgeTypes.contains('$required'), isTrue, reason: 'missing edge type $required');
    }

    final source = graph.nodes.firstWhere(
      (node) => node.sourceRecordId == expectedCurrent.first,
    );
    final r2 = buildR2Graph(graph, [
      {
        'kind': 'HYPOTHESIS',
        'projectId': fixture['projectId'],
        'statement': 'Golden fixture provisional hypothesis.',
        'derivedFrom': [source.id],
        'confidence': 0.5,
        'status': 'PROVISIONAL',
        'requiredEvidence': ['independent confirmation'],
        'staleWhen': ['R1 source changes'],
        'metadata': {'currentTruth': true},
      }
    ]);

    expect(
      () => assertR2CannotMutateR1(graph, r2),
      throwsStateError,
      reason: 'R2 must never self-promote into Current Truth.',
    );
  });
}
