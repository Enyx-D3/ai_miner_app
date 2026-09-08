import 'dart:math' as math;

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
    final subject =
        normalizeText('${atom['canonicalSubject'] ?? atom['subject'] ?? ''}')
            .toLowerCase();
    final rawKeywords =
        ((atom['keywords'] as List?) ?? const []).map((e) => '$e').toList();
    final source = subject.isNotEmpty
        ? subject
        : (rawKeywords.take(3).toList()..sort()).join(' ');
    final terms = source.split(' ').where((e) => e.isNotEmpty).take(4).toList()
      ..sort();
    return '${atom['kind']}:${terms.isEmpty ? 'unresolved' : terms.join('-')}';
  }

  String patternLabelForAtom(Map<String, Object?> atom) {
    final keywords = ((atom['keywords'] as List?) ?? const [])
        .map((e) => '$e')
        .take(3)
        .join(' ');
    final subject = normalizeText(
        '${atom['subject'] ?? atom['canonicalSubject'] ?? keywords}');
    return subject.isNotEmpty ? subject : '${atom['kind']} pattern';
  }

  Future<List<Map<String, Object?>>> build({int limit = 250}) async {
    final atoms = await db.records('atoms', orderBy: 'updated_at ASC');
    final truths = await db.records('truths', orderBy: 'updated_at ASC');
    final tests = await db.records('patternTests', orderBy: 'updated_at ASC');
    final conflicts = truths
        .where((truth) => '${truth['status']}' == 'CONFLICTING')
        .expand((truth) =>
            ((truth['evidenceAtomIds'] as List?) ?? <Object?>[truth['atomId']])
                .map((e) => '$e'))
        .where((e) => e.isNotEmpty)
        .toSet();
    final aggregates = <String, _PatternAggregate>{};

    for (final atom in atoms) {
      final kind = '${atom['kind']}';
      if (!const {'decision', 'constraint', 'fact', 'task', 'idea'}
          .contains(kind)) continue;
      final key = patternKeyForAtom(atom);
      final group = aggregates.putIfAbsent(
          key, () => _PatternAggregate(key, patternLabelForAtom(atom), kind));
      group.evidenceCount++;
      final projectId = '${atom['projectId'] ?? ''}';
      if (projectId.isNotEmpty) group.projectIds.add(projectId);
      final atomId = '${atom['id'] ?? ''}';
      if (atomId.isNotEmpty) {
        group.atomIds.add(atomId);
        if (group.atomIds.length > 300) group.atomIds.removeAt(0);
        if (conflicts.contains(atomId)) {
          group.counterexampleAtomIds.add(atomId);
          if (group.counterexampleAtomIds.length > 100)
            group.counterexampleAtomIds.removeAt(0);
        }
      }
    }

    final patterns = <Map<String, Object?>>[];
    for (final group in aggregates.values) {
      if (group.evidenceCount < 3) continue;
      final crossProject = group.projectIds.length;
      final counterexampleRatio =
          group.counterexampleAtomIds.length / math.max(1, group.evidenceCount);
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
        'hypothesis':
            'Repeated ${group.kind.isEmpty ? 'knowledge' : group.kind} structure around ${group.label}.',
        'boundaryConditions': crossProject < 2
            ? <String>['Observed in only one project']
            : <String>[],
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
      final strength = ((b['strength'] as num?)?.toDouble() ?? 0)
          .compareTo((a['strength'] as num?)?.toDouble() ?? 0);
      if (strength != 0) return strength;
      return ((b['evidenceCount'] as num?)?.toInt() ?? 0)
          .compareTo((a['evidenceCount'] as num?)?.toInt() ?? 0);
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
