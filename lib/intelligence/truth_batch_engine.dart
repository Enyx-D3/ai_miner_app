import '../core/identity.dart';
import '../storage/brain2_database.dart';
import 'truth_reconciliation.dart';

class TruthAtomInput {
  final Map<String, Object?> atom;
  final String role;

  const TruthAtomInput(this.atom, this.role);
}

class TruthBatchResult {
  final List<Map<String, Object?>> truthWrites;

  const TruthBatchResult(this.truthWrites);
}

/// Fast import/build-session truth reconciler.
///
/// Loads each project+kind truth group once, reconciles subsequent atoms in
/// memory, and returns one deduplicated write set to be committed together
/// with an atom batch. This removes the previous per-atom SQLite query and
/// per-truth mutation/transaction loop.
class MobileTruthBatchEngine {
  final Brain2Database db;

  final Map<String, List<Map<String, Object?>>> _activeGroups = {};
  final Set<String> _loadedGroups = {};

  MobileTruthBatchEngine(this.db);

  void reset() {
    _activeGroups.clear();
    _loadedGroups.clear();
  }

  void invalidateProject(String projectId) {
    final prefix = '$projectId\u241f';
    _activeGroups.removeWhere((key, _) => key.startsWith(prefix));
    _loadedGroups.removeWhere((key) => key.startsWith(prefix));
  }

  Future<TruthBatchResult> reconcile(List<TruthAtomInput> inputs) async {
    if (inputs.isEmpty) return const TruthBatchResult([]);
    final writes = <String, Map<String, Object?>>{};

    for (final input in inputs) {
      final atom = input.atom;
      final kind = '${atom['kind'] ?? ''}';
      final strictBlocked = atom['strictTruthBlocked'] == true ||
          ((atom['ruleTrace'] as List?) ?? const [])
              .map((e) => '$e')
              .any((e) => const {
                    'strict_truth:assistant_or_unknown_author',
                    'strict_truth:question',
                    'strict_truth:code_or_log',
                    'strict_truth:chat_task',
                    'strict_truth:transient_observation',
                    'strict_truth:invalid_source',
                    'strict_truth:invalid_timestamp',
                  }.contains(e));
      if (strictBlocked ||
          input.role != 'user' ||
          !const {'decision', 'constraint', 'fact', 'task'}.contains(kind)) {
        continue;
      }

      final projectId = '${atom['projectId'] ?? ''}';
      if (projectId.isEmpty) continue;
      final subject = normalizeText(
        '${atom['canonicalSubject'] ?? atom['subject'] ?? atom['text'] ?? ''}',
      ).toLowerCase();
      if (subject.isEmpty) continue;

      final group = await _group(projectId, kind);
      Map<String, Object?>? match;
      var best = 0.0;
      final atomTerms = _terms(subject);
      for (final truth in group) {
        if (!strictFamilyCompatible(atom, truth)) continue;
        final overlap = _overlap(
          atomTerms,
          _terms('${truth['canonicalSubject'] ?? truth['text'] ?? ''}'),
        );
        if (overlap > best) {
          best = overlap;
          match = truth;
        }
      }
      if (best < 0.25) match = null;

      final now = DateTime.now().toUtc().toIso8601String();
      final text = normalizeText('${atom['text'] ?? ''}');

      var relation = 'NEW';
      var status = 'CURRENT';
      if (match != null) {
        relation = relationForAtomAndTruth(atom, match);

        if (relation == 'CONTRADICTS') {
          status = 'CONFLICTING';
          final updated = <String, Object?>{
            ...match,
            'status': 'CONFLICTING',
            'relation': 'CONTRADICTS',
            'updatedAt': now,
          };
          writes['${updated['id']}'] = updated;
          _replaceInGroup(group, updated);
        } else if (relation == 'SUPERSEDES' || relation == 'REFINES') {
          final updated = <String, Object?>{
            ...match,
            'status': 'SUPERSEDED',
            'updatedAt': now,
          };
          writes['${updated['id']}'] = updated;
          _replaceInGroup(group, updated);
        } else if (relation == 'UNCERTAIN') {
          status = 'PENDING_REVIEW';
        } else if (relation == 'SAME') {
          status = 'HISTORICAL';
        } else if (relation == 'DIFFERENT_SCOPE') {
          status = 'CURRENT';
        }
      }

      final id = canonicalId(
        'truth',
        [projectId, kind, subject, '${atom['id']}'],
      );
      final created = <String, Object?>{
        'id': id,
        'key': '$projectId:$kind:$subject',
        'projectId': projectId,
        'conversationId': atom['conversationId'],
        'sourceId': atom['sourceId'],
        'atomId': atom['id'],
        'text': text,
        'kind': kind,
        'status': status,
        'confidence': atom['confidence'] ?? 0.7,
        'createdAt': atom['createdAt'] ?? now,
        'updatedAt': now,
        'relation': relation,
        'relatedTruthIds':
            match == null ? <String>[] : <String>['${match['id']}'],
        'evidenceAtomIds': <String>['${atom['id']}'],
        'canonicalSubject': atom['canonicalSubject'],
        'value': atom['value'],
        'polarity': atom['polarity'],
        'scope': atom['scope'],
        if (relation == 'SUPERSEDES' || relation == 'REFINES')
          'supersedes': match?['id'],
        'strictTruthRootKey': strictTruthRootKeyForAtom(atom),
        'strictTruthRule': ((atom['ruleTrace'] as List?) ?? const [])
            .map((e) => '$e')
            .firstWhere(
              (e) =>
                  e.startsWith('strict_truth:') &&
                  e != 'strict_truth:eligible' &&
                  e != 'strict_truth:residual',
              orElse: () => 'strict_truth:residual',
            ),
        'reconciliationVersion': 'B2_TRUTH_V8_STRICT_MOBILE',
        'schemaVersion': 10,
      };
      writes[id] = created;
      if (const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}.contains(status)) {
        _replaceInGroup(group, created);
      }
    }

    return TruthBatchResult(writes.values.toList(growable: false));
  }

  Future<List<Map<String, Object?>>> _group(
    String projectId,
    String kind,
  ) async {
    final key = '$projectId\u241f$kind';
    if (!_loadedGroups.contains(key)) {
      final rows = await db.recordsByJsonFields(
        'truths',
        {'projectId': projectId, 'kind': kind},
        newestFirst: true,
        limit: 512,
      );
      _activeGroups[key] = rows
          .where(
            (truth) => const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}
                .contains('${truth['status']}'),
          )
          .toList(growable: true);
      _loadedGroups.add(key);
    }
    return _activeGroups[key] ??= <Map<String, Object?>>[];
  }

  void _replaceInGroup(
    List<Map<String, Object?>> group,
    Map<String, Object?> record,
  ) {
    final id = '${record['id']}';
    final index = group.indexWhere((item) => '${item['id']}' == id);
    final active = const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}
        .contains('${record['status']}');
    if (index >= 0) {
      if (active) {
        group[index] = record;
      } else {
        group.removeAt(index);
      }
    } else if (active) {
      group.add(record);
    }
  }

  Set<String> _terms(String value) => normalizeText(value)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 3)
      .toSet();

  double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }
}
