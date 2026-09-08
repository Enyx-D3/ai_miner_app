import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';
import 'truth_reconciliation.dart';

class MobileTruthEngine {
  final Brain2Database db;
  final MutationService mutations;
  MobileTruthEngine(this.db, this.mutations);

  Future<void> reconcileAtom(Map<String, Object?> atom,
      {required String role}) async {
    final kind = '${atom['kind'] ?? ''}';
    final normalizedRole = normalizeText(role).toLowerCase();
    if (!const {'user', 'human'}.contains(normalizedRole) ||
        !const {'decision', 'constraint', 'fact', 'task'}.contains(kind)) {
      return;
    }
    final projectId = '${atom['projectId'] ?? ''}';
    final subject = normalizeText(
            '${atom['canonicalSubject'] ?? atom['subject'] ?? atom['text'] ?? ''}')
        .toLowerCase();
    final current = (await db.recordsByJsonFields(
            'truths', {'projectId': projectId, 'kind': kind},
            newestFirst: true, limit: 256))
        .where((t) => const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}
            .contains('${t['status']}'))
        .toList();
    Map<String, Object?>? match;
    double best = 0;
    final aTerms = _terms(subject);
    for (final t in current) {
      if (!strictFamilyCompatible(atom, t)) {
        continue;
      }
      final ov = _overlap(
          aTerms, _terms('${t['canonicalSubject'] ?? t['text'] ?? ''}'));
      if (ov > best) {
        best = ov;
        match = t;
      }
    }
    if (best < 0.25) match = null;
    final now = DateTime.now().toUtc().toIso8601String();
    final text = normalizeText('${atom['text'] ?? ''}');
    String relation = 'NEW', status = 'CURRENT';
    if (match != null) {
      relation = relationForAtomAndTruth(atom, match);
      if (relation == 'CONTRADICTS') {
        status = 'CONFLICTING';
        await mutations.upsert(
            'truths',
            {
              ...match,
              'status': 'CONFLICTING',
              'relation': 'CONTRADICTS',
              'updatedAt': now
            },
            type: 'TRUTH_CONFLICT');
      } else if (relation == 'SUPERSEDES' || relation == 'REFINES') {
        await mutations.upsert(
            'truths', {...match, 'status': 'SUPERSEDED', 'updatedAt': now},
            type: 'TRUTH_SUPERSEDE');
      } else if (relation == 'UNCERTAIN') {
        status = 'PENDING_REVIEW';
      } else if (relation == 'SAME') {
        status = 'HISTORICAL';
      } else if (relation == 'DIFFERENT_SCOPE') {
        status = 'CURRENT';
      }
    }
    final id =
        canonicalId('truth', [projectId, kind, subject, '${atom['id']}']);
    await mutations.upsert(
        'truths',
        {
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
          'evidenceAtomIds': ['${atom['id']}'],
          'canonicalSubject': atom['canonicalSubject'],
          'value': atom['value'],
          'polarity': atom['polarity'],
          'scope': atom['scope'],
          if (relation == 'SUPERSEDES' || relation == 'REFINES')
            'supersedes': match?['id'],
          'strictTruthRootKey': strictTruthRootKeyForAtom(atom),
          'strictTruthRule': strictRuleFromRecord(atom) == null
              ? 'strict_truth:residual'
              : 'strict_truth:${strictRuleFromRecord(atom)}',
          'reconciliationVersion': 'B2_TRUTH_V8_STRICT_MOBILE',
          'schemaVersion': 10,
        },
        type: 'TRUTH_RECONCILE');
  }

  Set<String> _terms(String s) => normalizeText(s)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((x) => x.length >= 3)
      .toSet();
  double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }
}
