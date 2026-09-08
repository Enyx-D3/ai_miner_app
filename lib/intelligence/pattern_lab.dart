import '../core/contracts.dart';
import '../core/identity.dart';

class PatternEvaluation {
  final String status;
  final String maturity;
  final String verificationStatus;
  final String falsificationStatus;
  final List<String> transferTestIds;
  final List<String> boundaryConditions;
  final double supportScore;

  const PatternEvaluation({
    required this.status,
    required this.maturity,
    required this.verificationStatus,
    required this.falsificationStatus,
    required this.transferTestIds,
    required this.boundaryConditions,
    required this.supportScore,
  });
}

PatternEvaluation evaluatePattern(
  Map<String, Object?> pattern,
  List<Map<String, Object?>> tests,
) {
  final relevant = tests
      .where((test) => '${test['patternId']}' == '${pattern['id']}')
      .toList();
  final pass = relevant.where((test) => '${test['status']}' == 'PASS').toList();
  final fail = relevant.where((test) => '${test['status']}' == 'FAIL').toList();
  final transferPass =
      pass.where((test) => '${test['kind']}' == 'TRANSFER').toList();
  final domains = transferPass
      .map((test) =>
          normalizeText('${test['domain'] ?? test['projectId'] ?? ''}'))
      .where((value) => value.isNotEmpty)
      .toSet();
  final replicationPass =
      pass.where((test) => '${test['kind']}' == 'REPLICATION').length;
  final falsificationPass =
      pass.where((test) => '${test['kind']}' == 'FALSIFICATION').length;
  final counterexampleFailures = fail.where((test) {
    final kind = '${test['kind']}';
    return kind == 'COUNTEREXAMPLE' || kind == 'FALSIFICATION';
  }).toList();
  final boundaries = <String>{
    ...((pattern['boundaryConditions'] as List?) ?? const []).map((e) => '$e'),
    ...fail
        .where((test) => normalizeText('${test['domain'] ?? ''}').isNotEmpty)
        .map((test) =>
            'Failed transfer/falsification in ${normalizeText('${test['domain']}')}'),
  };

  var status = '${pattern['status'] ?? 'OBSERVED'}';
  var maturity = '${pattern['maturity'] ?? 'L1_OBSERVATION'}';
  var verificationStatus = '${pattern['verificationStatus'] ?? 'UNTESTED'}';
  var falsificationStatus = 'UNTESTED';
  final evidenceCount = (pattern['evidenceCount'] as num?)?.toInt() ?? 0;
  final strength = (pattern['strength'] as num?)?.toDouble() ?? 0.0;

  if (evidenceCount >= 3) maturity = 'L2_CANDIDATE';
  if (evidenceCount >= 7) maturity = 'L3_HYPOTHESIS';
  if (replicationPass >= 1 && fail.isEmpty) maturity = 'L4_SUPPORTED';
  if (replicationPass >= 2 && fail.isEmpty) maturity = 'L5_REPLICATED';
  if (relevant.any((test) => '${test['kind']}' == 'FALSIFICATION')) {
    falsificationStatus = counterexampleFailures.isNotEmpty
        ? 'FAILED'
        : falsificationPass > 0
            ? 'SURVIVED'
            : 'ACTIVE';
  }
  if (counterexampleFailures.isNotEmpty) {
    status = 'TESTING';
    verificationStatus = 'COUNTEREXAMPLE_FOUND';
  } else if (domains.length >= 2 &&
      replicationPass >= 1 &&
      falsificationPass >= 1) {
    status = 'VERIFIED';
    maturity = 'L6_GENERALIZED';
    verificationStatus = 'VERIFIED_EXTERNAL';
    falsificationStatus = 'SURVIVED';
  } else if (evidenceCount >= 7 || relevant.isNotEmpty) {
    status = 'TESTING';
    verificationStatus = 'NEEDS_TRANSFER_TEST';
  }
  final supportScore = (strength * .45 +
          (pass.length / 4).clamp(0, 1) * .35 +
          (domains.length / 2).clamp(0, 1) * .2 -
          fail.length * .2)
      .clamp(0, 1)
      .toDouble();

  return PatternEvaluation(
    status: status,
    maturity: maturity,
    verificationStatus: verificationStatus,
    falsificationStatus: falsificationStatus,
    transferTestIds: transferPass.map((test) => '${test['id']}').toList(),
    boundaryConditions: boundaries.toList(),
    supportScore: supportScore,
  );
}

Map<String, Object?> createPatternTest({
  required String patternId,
  required String kind,
  String? projectId,
  String? domain,
  required String status,
  required String hypothesis,
  required String result,
  List<String> evidenceAtomIds = const [],
  String? verifier,
}) {
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final payload = <String, Object?>{
    'patternId': patternId,
    'kind': kind,
    'projectId': projectId,
    'domain': domain,
    'status': status,
    'hypothesis': hypothesis,
    'result': result,
    'evidenceAtomIds': evidenceAtomIds,
    'verifier': verifier,
    'createdAt': createdAt,
  };
  final hash = sha256Hex(canonicalJson(payload));
  return <String, Object?>{
    ...payload,
    'id': canonicalId(
        'pattern-test', [patternId, kind, projectId, domain, createdAt, hash]),
    'hash': hash,
    'schemaVersion': brain2SchemaVersion,
  };
}

Map<String, Object?> createPortableExpertise({
  required Map<String, Object?> pattern,
  required List<Map<String, Object?>> tests,
  String? title,
  required List<String> triggerConditions,
  required List<String> procedure,
  required String verifier,
}) {
  final evaluation = evaluatePattern(pattern, tests);
  if (evaluation.status != 'VERIFIED' ||
      evaluation.maturity != 'L6_GENERALIZED') {
    throw StateError(
      'Portable Expertise requires a pattern that survived replication, falsification, and transfer in at least two domains.',
    );
  }
  final relevant = tests
      .where((test) => '${test['patternId']}' == '${pattern['id']}')
      .toList();
  final domains = relevant
      .where((test) =>
          '${test['kind']}' == 'TRANSFER' && '${test['status']}' == 'PASS')
      .map((test) =>
          normalizeText('${test['domain'] ?? test['projectId'] ?? ''}'))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  final counterexamples = relevant
      .where((test) => '${test['status']}' == 'FAIL')
      .map((test) => '${test['result']}')
      .toList();
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final id = canonicalId('portable-expertise',
      ['${pattern['id']}', title ?? '${pattern['label']}']);
  final payload = <String, Object?>{
    'id': id,
    'patternId': pattern['id'],
    'title': title ?? pattern['label'],
    'triggerConditions': triggerConditions,
    'operatingBoundaries': evaluation.boundaryConditions,
    'counterexamples': counterexamples,
    'procedure': procedure,
    'verifier': verifier,
    'provenanceAtomIds':
        ((pattern['atomIds'] as List?) ?? const []).map((e) => '$e').toList(),
    'transferDomains': domains,
    'confidence': evaluation.supportScore,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'version': 1,
  };
  return <String, Object?>{
    ...payload,
    'hash': sha256Hex(canonicalJson(payload)),
  };
}
