import 'dart:convert';

import '../core/identity.dart';

int? brain2MutationGapExpected(int lastApplied, int nextSequence) {
  final cursor = lastApplied < 0 ? 0 : lastApplied;
  if (nextSequence <= cursor) return null;
  final expected = cursor + 1;
  return nextSequence == expected ? null : expected;
}

String _proofString(Object? value) => value == null ? '' : '$value';

List<Object?> brain2TruthStateMaterial(List<Map<String, Object?>> truths) {
  final rows = truths.map<List<Object?>>((truth) {
    final evidence = ((truth['evidenceAtomIds'] as List?) ?? const [])
        .map(_proofString)
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    return <Object?>[
      _proofString(truth['id']),
      _proofString(truth['key']),
      _proofString(truth['projectId']),
      _proofString(truth['atomId']),
      _proofString(truth['status']),
      _proofString(truth['kind']),
      _proofString(truth['text']),
      _proofString(truth['canonicalSubject']),
      _proofString(truth['value']),
      _proofString(truth['scope']),
      _proofString(truth['supersedes']),
      evidence,
    ];
  }).toList();
  rows.sort((a, b) => '${a.first}'.compareTo('${b.first}'));
  return rows;
}

String brain2TruthStateRoot(List<Map<String, Object?>> truths) =>
    sha256Hex(jsonEncode(brain2TruthStateMaterial(truths)));

List<List<Object?>> brain2MutationFrontier(List<Map<String, Object?>> mutations) {
  final maxByOrigin = <String, int>{};
  for (final mutation in mutations) {
    final origin = _proofString(mutation['originDeviceId'] ?? mutation['deviceId']);
    final raw = mutation['originSequence'] ?? mutation['sequence'];
    final sequence = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (origin.isEmpty || sequence < 1) continue;
    final current = maxByOrigin[origin] ?? 0;
    if (sequence > current) maxByOrigin[origin] = sequence;
  }
  final rows = maxByOrigin.entries.map<List<Object?>>((entry) => [entry.key, entry.value]).toList()
    ..sort((a, b) => '${a[0]}'.compareTo('${b[0]}'));
  return rows;
}

String brain2MutationFrontierRoot(List<Map<String, Object?>> mutations) =>
    sha256Hex(jsonEncode(brain2MutationFrontier(mutations)));
