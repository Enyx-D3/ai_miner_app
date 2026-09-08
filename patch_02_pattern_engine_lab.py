#!/usr/bin/env python3
from pathlib import Path
import shutil, sys, time

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
PIPE = ROOT / 'lib/intelligence/mobile_intelligence_pipeline.dart'
LAB = ROOT / 'lib/intelligence/pattern_lab.dart'
ENG = ROOT / 'lib/intelligence/pattern_engine.dart'
if not PIPE.exists():
    raise SystemExit(f'ERROR: expected mobile project file not found: {PIPE}')
stamp = str(int(time.time()))
def backup(p: Path):
    if not p.exists(): return
    shutil.copy2(p, p.with_name(p.name + f'.pre_pattern_engine_{stamp}'))

pattern_lab = r'''import '../core/contracts.dart';
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
  final relevant = tests.where((test) => '${test['patternId']}' == '${pattern['id']}').toList();
  final pass = relevant.where((test) => '${test['status']}' == 'PASS').toList();
  final fail = relevant.where((test) => '${test['status']}' == 'FAIL').toList();
  final transferPass = pass.where((test) => '${test['kind']}' == 'TRANSFER').toList();
  final domains = transferPass
      .map((test) => normalizeText('${test['domain'] ?? test['projectId'] ?? ''}'))
      .where((value) => value.isNotEmpty)
      .toSet();
  final replicationPass = pass.where((test) => '${test['kind']}' == 'REPLICATION').length;
  final falsificationPass = pass.where((test) => '${test['kind']}' == 'FALSIFICATION').length;
  final counterexampleFailures = fail.where((test) {
    final kind = '${test['kind']}';
    return kind == 'COUNTEREXAMPLE' || kind == 'FALSIFICATION';
  }).toList();
  final boundaries = <String>{
    ...((pattern['boundaryConditions'] as List?) ?? const []).map((e) => '$e'),
    ...fail
        .where((test) => normalizeText('${test['domain'] ?? ''}').isNotEmpty)
        .map((test) => 'Failed transfer/falsification in ${normalizeText('${test['domain']}')}'),
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
  } else if (domains.length >= 2 && replicationPass >= 1 && falsificationPass >= 1) {
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
    'id': canonicalId('pattern-test', [patternId, kind, projectId, domain, createdAt, hash]),
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
  if (evaluation.status != 'VERIFIED' || evaluation.maturity != 'L6_GENERALIZED') {
    throw StateError(
      'Portable Expertise requires a pattern that survived replication, falsification, and transfer in at least two domains.',
    );
  }
  final relevant = tests.where((test) => '${test['patternId']}' == '${pattern['id']}').toList();
  final domains = relevant
      .where((test) => '${test['kind']}' == 'TRANSFER' && '${test['status']}' == 'PASS')
      .map((test) => normalizeText('${test['domain'] ?? test['projectId'] ?? ''}'))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  final counterexamples = relevant
      .where((test) => '${test['status']}' == 'FAIL')
      .map((test) => '${test['result']}')
      .toList();
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final id = canonicalId('portable-expertise', ['${pattern['id']}', title ?? '${pattern['label']}']);
  final payload = <String, Object?>{
    'id': id,
    'patternId': pattern['id'],
    'title': title ?? pattern['label'],
    'triggerConditions': triggerConditions,
    'operatingBoundaries': evaluation.boundaryConditions,
    'counterexamples': counterexamples,
    'procedure': procedure,
    'verifier': verifier,
    'provenanceAtomIds': ((pattern['atomIds'] as List?) ?? const []).map((e) => '$e').toList(),
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
'''

pattern_engine = r'''import 'dart:math' as math;

import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';
import 'pattern_lab.dart';

const String brain2PatternVersion = 'B2_PATTERN_ENGINE_V1';

class _PatternAggregate {
  final String patternKey;
  String label;
  final String kind;
  int evidenceCount = 0;
  final Set<String> projectIds = <String>{};
  final List<String> atomIds = <String>[];
  final List<String> counterexampleAtomIds = <String>[];

  _PatternAggregate(this.patternKey, this.label, this.kind);
}

class MobilePatternEngine {
  final Brain2Database db;
  final MutationService mutations;

  const MobilePatternEngine(this.db, this.mutations);

  String patternKeyForAtom(Map<String, Object?> atom) {
    final subject = normalizeText('${atom['canonicalSubject'] ?? atom['subject'] ?? ''}').toLowerCase();
    final rawKeywords = ((atom['keywords'] as List?) ?? const []).map((e) => '$e').toList();
    final source = subject.isNotEmpty ? subject : (rawKeywords.take(3).toList()..sort()).join(' ');
    final terms = source.split(' ').where((e) => e.isNotEmpty).take(4).toList()..sort();
    return '${atom['kind']}:${terms.isEmpty ? 'unresolved' : terms.join('-')}';
  }

  String patternLabelForAtom(Map<String, Object?> atom) {
    final keywords = ((atom['keywords'] as List?) ?? const []).map((e) => '$e').take(3).join(' ');
    final subject = normalizeText('${atom['subject'] ?? atom['canonicalSubject'] ?? keywords}');
    return subject.isNotEmpty ? subject : '${atom['kind']} pattern';
  }

  Future<List<Map<String, Object?>>> build({int limit = 250}) async {
    final atoms = await db.records('atoms', orderBy: 'updated_at ASC');
    final truths = await db.records('truths', orderBy: 'updated_at ASC');
    final tests = await db.records('patternTests', orderBy: 'updated_at ASC');
    final conflicts = truths
        .where((truth) => '${truth['status']}' == 'CONFLICTING')
        .expand((truth) => ((truth['evidenceAtomIds'] as List?) ?? <Object?>[truth['atomId']]).map((e) => '$e'))
        .where((e) => e.isNotEmpty)
        .toSet();
    final aggregates = <String, _PatternAggregate>{};

    for (final atom in atoms) {
      final kind = '${atom['kind']}';
      if (!const {'decision', 'constraint', 'fact', 'task', 'idea'}.contains(kind)) continue;
      final key = patternKeyForAtom(atom);
      final group = aggregates.putIfAbsent(key, () => _PatternAggregate(key, patternLabelForAtom(atom), kind));
      group.evidenceCount++;
      final projectId = '${atom['projectId'] ?? ''}';
      if (projectId.isNotEmpty) group.projectIds.add(projectId);
      final atomId = '${atom['id'] ?? ''}';
      if (atomId.isNotEmpty) {
        group.atomIds.add(atomId);
        if (group.atomIds.length > 300) group.atomIds.removeAt(0);
        if (conflicts.contains(atomId)) {
          group.counterexampleAtomIds.add(atomId);
          if (group.counterexampleAtomIds.length > 100) group.counterexampleAtomIds.removeAt(0);
        }
      }
    }

    final patterns = <Map<String, Object?>>[];
    for (final group in aggregates.values) {
      if (group.evidenceCount < 3) continue;
      final crossProject = group.projectIds.length;
      final counterexampleRatio = group.counterexampleAtomIds.length / math.max(1, group.evidenceCount);
      final strength = (.28 +
              math.log(group.evidenceCount + 1) / math.ln2 / 9 +
              math.min(.24, crossProject * .06) -
              counterexampleRatio * .45)
          .clamp(0, 1)
          .toDouble();
      var status = 'OBSERVED';
      var verificationStatus = 'UNTESTED';
      var maturity = 'L1_OBSERVATION';
      if (group.evidenceCount >= 3) maturity = 'L2_CANDIDATE';
      if (group.evidenceCount >= 7 && crossProject >= 2) {
        status = 'CANDIDATE';
        maturity = 'L3_HYPOTHESIS';
      }
      if (group.evidenceCount >= 12 && crossProject >= 2) {
        status = 'TESTING';
        verificationStatus = group.counterexampleAtomIds.isNotEmpty
            ? 'COUNTEREXAMPLE_FOUND'
            : 'NEEDS_TRANSFER_TEST';
      }
      var pattern = <String, Object?>{
        'id': canonicalId('pat', [group.patternKey]),
        'label': group.label,
        'status': status,
        'strength': strength,
        'projectIds': group.projectIds.toList(),
        'atomIds': group.atomIds,
        'evidenceCount': group.evidenceCount,
        'counterexamples': group.counterexampleAtomIds.length,
        'counterexampleAtomIds': group.counterexampleAtomIds,
        'hypothesis': 'Repeated ${group.kind.isEmpty ? 'knowledge' : group.kind} structure around ${group.label}.',
        'boundaryConditions': crossProject < 2 ? <String>['Observed in only one project'] : <String>[],
        'verificationStatus': verificationStatus,
        'patternKey': group.patternKey,
        'patternVersion': brain2PatternVersion,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'maturity': maturity,
        'falsificationStatus': 'UNTESTED',
        'predictions': <String>[],
        'schemaVersion': brain2SchemaVersion,
      };
      final evaluation = evaluatePattern(pattern, tests);
      pattern = <String, Object?>{
        ...pattern,
        'status': evaluation.status,
        'maturity': evaluation.maturity,
        'verificationStatus': evaluation.verificationStatus,
        'falsificationStatus': evaluation.falsificationStatus,
        'transferTestIds': evaluation.transferTestIds,
        'boundaryConditions': evaluation.boundaryConditions,
        'strength': math.max(strength, evaluation.supportScore),
      };
      patterns.add(pattern);
    }
    patterns.sort((a, b) {
      final strength = ((b['strength'] as num?)?.toDouble() ?? 0).compareTo((a['strength'] as num?)?.toDouble() ?? 0);
      if (strength != 0) return strength;
      return ((b['evidenceCount'] as num?)?.toInt() ?? 0).compareTo((a['evidenceCount'] as num?)?.toInt() ?? 0);
    });
    return patterns.take(limit).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> refresh({int limit = 250}) async {
    final patterns = await build(limit: limit);
    if (patterns.isNotEmpty) {
      await mutations.upsertBatch(
        {'patterns': patterns},
        type: 'PATTERN_ENGINE_REFRESH',
        primaryTable: 'patterns',
        entityType: 'patterns',
        entityId: 'global-pattern-refresh',
      );
    }
    return patterns;
  }
}
'''
for p, content in ((LAB, pattern_lab), (ENG, pattern_engine)):
    backup(p); p.write_text(content)

s = PIPE.read_text()
if "import 'pattern_engine.dart';" not in s:
    anchor = "import 'truth_batch_engine.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: pipeline import anchor not found')
    s = s.replace(anchor, anchor + "import 'pattern_engine.dart';\n", 1)
if 'late final MobilePatternEngine patterns' not in s:
    anchor = "  late final MobileTruthBatchEngine batchTruths = MobileTruthBatchEngine(db);\n"
    if anchor not in s: raise SystemExit('ERROR: pipeline field anchor not found')
    s = s.replace(anchor, anchor + "  late final MobilePatternEngine patterns = MobilePatternEngine(db, mutations);\n", 1)
# Refresh patterns after derived project snapshots; stable id means cross-project patterns converge as evidence grows.
anchor = "    await mutations.upsertBatch(\n      {\n        'intelligenceSnapshots': <Map<String, Object?>>[intelligenceSnapshot],"
# We insert after the whole upsert call via unique tail.
tail = "      entityId: projectId,\n    );\n  }\n}"
if tail in s and 'await patterns.refresh(limit: 250);' not in s:
    s = s.replace(tail, "      entityId: projectId,\n    );\n    await patterns.refresh(limit: 250);\n  }\n}", 1)
backup(PIPE); PIPE.write_text(s)

print('PASS patch_02_pattern_engine_lab')
print(f'  wrote: {LAB.relative_to(ROOT)}')
print(f'  wrote: {ENG.relative_to(ROOT)}')
print('  wired global pattern generation into existing derived-snapshot refresh')
print('  current PatternsScreen UI is preserved and will now receive locally-generated records')
