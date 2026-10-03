import 'dart:convert';

import '../core/identity.dart';
import '../core/r1_authority.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

const String continuityVersion = 'B2_CONTINUITY_INTELLIGENCE_V1';
const String continuityPlannerVersion = 'B2_QUERY_PLANNER_V1';

const Set<String> _stop = {
  'the',
  'and',
  'for',
  'with',
  'that',
  'this',
  'from',
  'have',
  'will',
  'would',
  'should',
  'could',
  'what',
  'when',
  'where',
  'which',
  'about',
  'into',
  'your',
  'you',
  'our',
  'are',
  'was',
  'were',
  'has',
  'had',
  'not',
  'but',
  'can',
  'how',
  'why',
  'use',
  'using',
  'need',
  'want',
  'project',
  'brain2',
  'global',
  'context'
};
final RegExp _dependencyCue = RegExp(
    r'\b(depends? on|dependency|after|before|requires?|prerequisite|blocked by|waiting for)\b',
    caseSensitive: false);
final RegExp _blockCue = RegExp(
    r"\b(blocked|cannot|can't|waiting|missing|failed|failure|stuck)\b",
    caseSensitive: false);
const Set<String> _gateActions = {
  'APPROVE',
  'DECIDE',
  'CONFLICT',
  'UNCERTAIN',
  'VERIFY'
};

String _norm(Object? value) => normalizeText('${value ?? ''}');
List<String> _tokens(Object? value) => _norm(value)
    .toLowerCase()
    .split(RegExp(r"[^a-z0-9'-]+"))
    .where((x) => x.length >= 3 && !_stop.contains(x))
    .toSet()
    .toList();
double _overlap(Object? a, Object? b) {
  final aa = _tokens(a).toSet(), bb = _tokens(b).toSet();
  if (aa.isEmpty || bb.isEmpty) return 0;
  return aa.intersection(bb).length / aa.union(bb).length;
}

List<String> _unique(Iterable<Object?> values) =>
    values.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toSet().toList()
      ..sort();
String continuityStableId(String prefix, List<Object?> parts) {
  final stable = [continuityVersion, ...parts.map(_norm)].join('\u241f');
  return '${prefix}_${sha256Hex(stable).substring(0, 24)}';
}

String _hashJson(Object? value) => sha256Hex(canonicalJson(value));

String hashContinuitySourceState(
    {required String projectId,
    required String goalText,
    required List<Map<String, Object?>> atoms,
    required List<Map<String, Object?>> truths,
    required List<Map<String, Object?>> ticks,
    required List<Map<String, Object?>> failures}) {
  List<List<Object?>> stableRows(Iterable<List<Object?>> rows) {
    final out = rows.toList();
    out.sort((a, b) => '${a.first}'.compareTo('${b.first}'));
    return out;
  }

  final material = {
    'projectId': projectId,
    'goalText': _norm(goalText),
    'atoms': stableRows(atoms.map(
        (a) => [a['id'], a['kind'], _norm(a['text']), a['createdAt'] ?? ''])),
    'truths': stableRows(truths.map((t) => [
          t['id'],
          t['status'],
          t['kind'],
          _norm(t['text']),
          t['updatedAt'] ?? ''
        ])),
    'ticks': stableRows(ticks.map((t) => [
          t['id'],
          t['status'],
          t['actionType'] ?? '',
          _norm(t['title']),
          _norm(t['detail'])
        ])),
    'failures': stableRows(failures.map((f) => [
          f['id'],
          f['lastSeenAt'] ?? '',
          _norm(f['title']),
          _norm(f['cause'])
        ])),
  };
  return _hashJson(material);
}

Map<String, Object?> _continuityStateMaterial(Map<String, Object?> input) {
  final checklist =
      ((input['checklist'] as List?) ?? const []).whereType<Map>().map((raw) {
    final row = raw.cast<String, Object?>();
    return <String, Object?>{
      for (final entry in row.entries)
        if (entry.key != 'updatedAt') entry.key: entry.value
    };
  }).toList();
  return <String, Object?>{
    'format': input['format'],
    'version': input['version'],
    'kind': input['kind'],
    'projectId': input['projectId'],
    'sourceHash': input['sourceHash'],
    'goal': input['goal'],
    'checklist': checklist,
    'avoidedWorkLedger': input['avoidedWorkLedger'] ?? const [],
    'recap': input['recap'],
    'prescription': input['prescription'] ?? const [],
    'plannerVersion': input['plannerVersion'],
  };
}

String hashContinuityStateMaterial(Map<String, Object?> input) =>
    _hashJson(_continuityStateMaterial(input));

class MobileContinuityIntelligence {
  final Brain2Database db;
  final MutationService mutations;
  MobileContinuityIntelligence(this.db, this.mutations);

  Future<Map<String, Object?>?> _existing(String projectId) async {
    final rows = await db.recordsByJsonFields(
        'intelligenceSnapshots',
        {
          'projectId': projectId,
          'kind': 'CONTINUITY_INTELLIGENCE',
        },
        limit: 2);
    if (rows.isEmpty) return null;
    rows.sort((a, b) =>
        '${b['updatedAt'] ?? ''}'.compareTo('${a['updatedAt'] ?? ''}'));
    return rows.first;
  }

  Future<Map<String, Object?>?> refreshProject(String projectId) async {
    final project = await db.getRecord('projects', projectId);
    if (project == null) return null;
    final atoms = await db
        .recordsByJsonFields('atoms', {'projectId': projectId}, limit: 10000);
    final truths = await db
        .recordsByJsonFields('truths', {'projectId': projectId}, limit: 10000);
    final ticks = await db
        .recordsByJsonFields('ticks', {'projectId': projectId}, limit: 1000);
    final failures = await db.recordsByJsonFields(
        'failureMemory', {'projectId': projectId},
        limit: 1000);
    final previous = await _existing(projectId);
    final built = _build(project, atoms, truths, ticks, failures, previous);
    final snapshot = built.$1;
    final atomUpdates = built.$2;
    if (previous != null &&
        '${previous['sourceHash']}' == '${snapshot['sourceHash']}' &&
        atomUpdates.isEmpty) {
      return previous;
    }
    final writes = <String, List<Map<String, Object?>>>{
      'intelligenceSnapshots': [snapshot],
      if (atomUpdates.isNotEmpty) 'atoms': atomUpdates,
    };
    await mutations.upsertBatch(
      writes,
      type: 'CONTINUITY_INTELLIGENCE_REFRESH',
      primaryTable: 'intelligenceSnapshots',
      entityType: 'projects',
      entityId: projectId,
    );
    return snapshot;
  }

  (Map<String, Object?>, List<Map<String, Object?>>) _build(
    Map<String, Object?> project,
    List<Map<String, Object?>> atoms,
    List<Map<String, Object?>> truths,
    List<Map<String, Object?>> ticks,
    List<Map<String, Object?>> failures,
    Map<String, Object?>? previous,
  ) {
    final projectId = '${project['id']}';
    final current = truths.where((t) => '${t['status']}' == 'CURRENT').toList();
    final tasks = current.where((t) => '${t['kind']}' == 'task').toList()
      ..sort((a, b) =>
          '${b['updatedAt'] ?? ''}'.compareTo('${a['updatedAt'] ?? ''}'));
    final taskTruth = tasks.isEmpty ? null : tasks.first;
    final goalText =
        _norm(taskTruth?['text'] ?? project['summary'] ?? project['name']);
    final goalId = continuityStableId('goal', [projectId, goalText]);
    final goalEvidence = _unique(((taskTruth?['evidenceAtomIds'] as List?) ??
            [if (taskTruth?['atomId'] != null) taskTruth!['atomId']])
        .cast<Object?>());
    final openTicks = ticks.where((t) => '${t['status']}' == 'OPEN').toList();
    final sortedAtoms = [...atoms]..sort((a, b) =>
        '${a['createdAt'] ?? a['id']}'
            .compareTo('${b['createdAt'] ?? b['id']}'));
    final linkedTasks = <Map<String, Object?>>[];
    final atomUpdates = <Map<String, Object?>>[];

    for (final atom in sortedAtoms) {
      final kind = '${atom['kind']}';
      final score = _overlap(atom['text'], goalText);
      final eligible = kind == 'task' ||
          ({'decision', 'constraint', 'fact'}.contains(kind) && score >= .16);
      if (!eligible) continue;
      final deps = <String>[];
      if (_dependencyCue.hasMatch('${atom['text']}') &&
          linkedTasks.isNotEmpty) {
        final ranked = linkedTasks
            .map((x) => (row: x, score: _overlap(atom['text'], x['text'])))
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score) != 0
              ? b.score.compareTo(a.score)
              : '${a.row['id']}'.compareTo('${b.row['id']}'));
        if (ranked.first.score >= .10) deps.add('${ranked.first.row['id']}');
      }
      final tickRanked = openTicks
          .map((t) => (
                row: t,
                score: _overlap(atom['text'], '${t['title']} ${t['detail']}')
              ))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score) != 0
            ? b.score.compareTo(a.score)
            : '${a.row['id']}'.compareTo('${b.row['id']}'));
      final bestTick = tickRanked.isNotEmpty && tickRanked.first.score >= .12
          ? tickRanked.first.row
          : null;
      final blocker = bestTick != null &&
              ('${bestTick['actionType']}' == 'BLOCKER' ||
                  _blockCue.hasMatch('${atom['text']}'))
          ? '${bestTick['id']}'
          : null;
      final gate =
          bestTick != null && _gateActions.contains('${bestTick['actionType']}')
              ? '${bestTick['id']}'
              : null;
      final next = <String, Object?>{...atom};
      for (final key in const [
        'goalId',
        'dependencyIds',
        'gateId',
        'blockerId',
        'nextAction'
      ]) {
        next.remove(key);
      }
      next['goalId'] = goalId;
      if (deps.isNotEmpty) next['dependencyIds'] = deps;
      if (gate != null) next['gateId'] = gate;
      if (blocker != null) next['blockerId'] = blocker;
      if (kind == 'task') next['nextAction'] = _norm(atom['text']);
      if (canonicalJson(next) != canonicalJson(atom)) atomUpdates.add(next);
      if (kind == 'task') linkedTasks.add(next);
    }

    final previousChecklist = ((previous?['checklist'] as List?) ?? const [])
        .whereType<Map>()
        .map((x) => x.cast<String, Object?>())
        .toList();
    final previousBySource = {
      for (final x in previousChecklist)
        '${x['sourceType']}:${x['sourceRefId']}': x
    };
    final checklist = <Map<String, Object?>>[];
    void addItem(String sourceType, String sourceRefId, String title,
        String derivedStatus, List<String> evidence,
        {List<String> blockedBy = const []}) {
      final old = previousBySource['$sourceType:$sourceRefId'];
      final e = _unique([
        ...evidence,
        ...(((old?['evidenceAtomIds'] as List?) ?? const []).cast<Object?>())
      ]);
      final ver = _unique(
          (((old?['verificationIds'] as List?) ?? const []).cast<Object?>()));
      final auth = _unique(
          (((old?['authorizationRefs'] as List?) ?? const []).cast<Object?>()));
      var status = derivedStatus;
      if ('${old?['status']}' == 'DONE' &&
          e.isNotEmpty &&
          ver.isNotEmpty &&
          auth.isNotEmpty) {
        status = 'DONE';
      }
      checklist.add({
        'id': old?['id'] ??
            continuityStableId('check', [projectId, sourceType, sourceRefId]),
        'projectId': projectId,
        'goalId': goalId,
        'sourceType': sourceType,
        'sourceRefId': sourceRefId,
        'title': _norm(title),
        'status': status,
        'evidenceAtomIds': e,
        'verificationIds': ver,
        'authorizationRefs': auth,
        'blockedByIds': _unique(blockedBy),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }

    final linkedById = <String, Map<String, Object?>>{
      for (final a in sortedAtoms) '${a['id']}': a,
      for (final a in atomUpdates) '${a['id']}': a
    };
    for (final atom in linkedById.values
        .where((a) => '${a['goalId']}' == goalId && '${a['kind']}' == 'task')) {
      final blocker = '${atom['blockerId'] ?? ''}';
      final gate = '${atom['gateId'] ?? ''}';
      addItem(
          'ATOM',
          '${atom['id']}',
          '${atom['nextAction'] ?? atom['text']}',
          blocker.isNotEmpty
              ? 'BLOCKED'
              : gate.isNotEmpty
                  ? 'GATE'
                  : 'OPEN',
          _unique(((atom['evidenceAtomIds'] as List?) ??
                  (atom['provenance'] as List?) ??
                  const [])
              .cast<Object?>()),
          blockedBy: _unique([
            ...(atom['dependencyIds'] as List? ?? const []),
            if (blocker.isNotEmpty) blocker
          ]));
    }
    for (final tick in openTicks) {
      final action = '${tick['actionType'] ?? ''}';
      final status = action == 'BLOCKER'
          ? 'BLOCKED'
          : _gateActions.contains(action)
              ? 'GATE'
              : 'OPEN';
      addItem(
          'TICK',
          '${tick['id']}',
          '${tick['title']}: ${tick['detail']}',
          status,
          _unique(((tick['evidenceAtomIds'] as List?) ?? const [])
              .cast<Object?>()));
    }
    for (final truth in truths.where(
        (t) => {'CONFLICTING', 'PENDING_REVIEW'}.contains('${t['status']}'))) {
      final evidence = _unique(((truth['evidenceAtomIds'] as List?) ??
              [if (truth['atomId'] != null) truth['atomId']])
          .cast<Object?>());
      addItem(
          'TRUTH',
          '${truth['id']}',
          '${truth['text']}',
          '${truth['status']}' == 'CONFLICTING' ? 'BLOCKED' : 'UNKNOWN',
          evidence);
    }
    const rank = {'GATE': 0, 'BLOCKED': 1, 'UNKNOWN': 2, 'OPEN': 3, 'DONE': 4};
    checklist.sort((a, b) {
      final d = (rank['${a['status']}'] ?? 9) - (rank['${b['status']}'] ?? 9);
      return d != 0 ? d : '${a['id']}'.compareTo('${b['id']}');
    });

    final ledger = ((previous?['avoidedWorkLedger'] as List?) ?? const [])
        .whereType<Map>()
        .map((x) => x.cast<String, Object?>())
        .toList()
      ..sort((a, b) => '${a['kind']}'.compareTo('${b['kind']}'));
    int c(String s) => checklist.where((x) => '${x['status']}' == s).length;
    final recap = {
      'currentTruthCount': current.length,
      'open': c('OPEN'),
      'blocked': c('BLOCKED'),
      'gates': c('GATE'),
      'done': c('DONE'),
      'unknown': c('UNKNOWN'),
      'knownFailureCount': failures.length,
      'recentChangeCount':
          truths.where((x) => '${x['status']}' != 'CURRENT').length,
    };
    final prescription = <String>[
      ...checklist
          .where((x) => '${x['status']}' == 'GATE')
          .take(2)
          .map((x) => 'Resolve human gate: ${x['title']}'),
      ...checklist
          .where((x) => '${x['status']}' == 'BLOCKED')
          .take(2)
          .map((x) => 'Unblock: ${x['title']}'),
      ...checklist
          .where((x) => '${x['status']}' == 'UNKNOWN')
          .take(1)
          .map((x) => 'Verify: ${x['title']}'),
      ...checklist
          .where((x) => '${x['status']}' == 'OPEN')
          .take(3)
          .map((x) => 'Continue: ${x['title']}'),
    ].take(5).toList();
    if (prescription.isEmpty) {
      prescription
          .add('Continue ${project['name']} from the latest verified state.');
    }
    final sourceHash = hashContinuitySourceState(
        projectId: projectId,
        goalText: goalText,
        atoms: sortedAtoms,
        truths: truths,
        ticks: openTicks,
        failures: failures);
    final stateInput = <String, Object?>{
      'format': 'B2_CONTINUITY',
      'version': 1,
      'kind': 'CONTINUITY_INTELLIGENCE',
      'projectId': projectId,
      'sourceHash': sourceHash,
      'goal': {'id': goalId, 'text': goalText, 'evidenceAtomIds': goalEvidence},
      'checklist': checklist,
      'avoidedWorkLedger': ledger,
      'recap': recap,
      'prescription': prescription,
      'plannerVersion': continuityPlannerVersion,
    };
    final snapshot = <String, Object?>{
      'id': continuityStableId('continuity', [projectId]),
      ...stateInput,
      'stateHash': hashContinuityStateMaterial(stateInput),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    return (snapshot, atomUpdates);
  }

  Future<Map<String, Object?>> completeChecklistItem(
      String projectId, String itemId,
      {required List<String> evidenceAtomIds,
      required List<String> verificationIds,
      required List<String> authorizationRefs}) async {
    final snapshot = await _existing(projectId);
    if (snapshot == null) throw StateError('Continuity snapshot not found.');
    if (evidenceAtomIds.isEmpty ||
        verificationIds.isEmpty ||
        authorizationRefs.isEmpty) {
      throw StateError(
          'DONE requires evidence + PASS verification + explicit authorization reference.');
    }
    for (final evidenceId in _unique(evidenceAtomIds)) {
      var exists = false;
      for (final table in const ['messages', 'atoms', 'truths']) {
        if (await db.getRecord(table, evidenceId) != null) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        throw StateError(
            'Checklist DONE evidence is missing from canonical storage: $evidenceId');
      }
    }
    for (final verificationId in _unique(verificationIds)) {
      final verification = await db.getRecord('verifications', verificationId);
      if (verification == null || '${verification['status']}' != 'PASS') {
        throw StateError('Checklist DONE requires PASS verification IDs.');
      }
    }
    final checklist = ((snapshot['checklist'] as List?) ?? const [])
        .whereType<Map>()
        .map((x) => x.cast<String, Object?>())
        .toList();
    final index = checklist.indexWhere((x) => '${x['id']}' == itemId);
    if (index < 0) throw StateError('Continuity checklist item not found.');
    final target = checklist[index];
    final proofEvidence = _unique(evidenceAtomIds).toSet();
    final allowed = <String, Brain2R1Receipt>{};
    for (final mutation in await db.records('mutations')) {
      final payload = (mutation['payload'] as Map?)?.cast<String, Object?>();
      final receiptMap =
          (payload?['r1Authority'] as Map?)?.cast<String, Object?>();
      if (receiptMap == null) continue;
      try {
        final receipt =
            verifyR1AuthorityReceipt(Brain2R1Receipt.fromJson(receiptMap));
        if (receipt.signal != Brain2R1Signal.allow || receipt.version < 2) {
          continue;
        }
        allowed['${mutation['id']}'] = receipt;
        allowed[receipt.hash] = receipt;
      } catch (_) {}
    }
    for (final ref in _unique(authorizationRefs)) {
      final receipt = allowed[ref];
      if (receipt == null) {
        throw StateError(
            'Checklist DONE authorization reference is not a verified R1 v2 ALLOW.');
      }
      final evidenceBound = receipt.evidenceRefs.any(proofEvidence.contains);
      final sourceRefId = '${target['sourceRefId'] ?? ''}';
      final scopeBound = receipt.scope.contains(itemId) ||
          (sourceRefId.isNotEmpty &&
              (receipt.scope.contains(sourceRefId) ||
                  receipt.evidenceRefs.contains(sourceRefId)));
      if (!evidenceBound && !scopeBound) {
        throw StateError(
            'Checklist DONE authorization is not bound to this checklist item or its evidence.');
      }
    }
    checklist[index] = {
      ...checklist[index],
      'status': 'DONE',
      'evidenceAtomIds': _unique(evidenceAtomIds),
      'verificationIds': _unique(verificationIds),
      'authorizationRefs': _unique(authorizationRefs),
      'updatedAt': DateTime.now().toUtc().toIso8601String()
    };
    int count(String status) =>
        checklist.where((x) => '${x['status']}' == status).length;
    final oldRecap = (snapshot['recap'] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final recap = {
      ...oldRecap,
      'open': count('OPEN'),
      'blocked': count('BLOCKED'),
      'gates': count('GATE'),
      'done': count('DONE'),
      'unknown': count('UNKNOWN')
    };
    final next = {
      ...snapshot,
      'checklist': checklist,
      'recap': recap,
      'updatedAt': DateTime.now().toUtc().toIso8601String()
    };
    next['stateHash'] = hashContinuityStateMaterial(next);
    await mutations.upsert('intelligenceSnapshots', next,
        type: 'CONTINUITY_CHECKLIST_COMPLETE');
    return next;
  }

  Future<Map<String, Object?>> recordAvoidedWork(String projectId,
      {required String kind, int count = 1, int? estimatedMs}) async {
    final snapshot =
        await _existing(projectId) ?? await refreshProject(projectId);
    if (snapshot == null) throw StateError('Continuity snapshot not found.');
    final ledger = ((snapshot['avoidedWorkLedger'] as List?) ?? const [])
        .whereType<Map>()
        .map((x) => x.cast<String, Object?>())
        .toList();
    Map<String, Object?>? row;
    for (final item in ledger) {
      if ('${item['kind']}' == kind) {
        row = item;
        break;
      }
    }
    if (row == null) {
      row = {'kind': kind, 'measuredCount': 0};
      ledger.add(row);
    }
    row['measuredCount'] = ((row['measuredCount'] as num?)?.toInt() ?? 0) +
        (count < 1 ? 1 : count);
    if (estimatedMs != null && estimatedMs > 0) {
      row['estimatedMs'] =
          ((row['estimatedMs'] as num?)?.toInt() ?? 0) + estimatedMs;
      row['estimateLabel'] = 'ESTIMATE';
    }
    ledger.sort((a, b) => '${a['kind']}'.compareTo('${b['kind']}'));
    final next = {
      ...snapshot,
      'avoidedWorkLedger': ledger,
      'updatedAt': DateTime.now().toUtc().toIso8601String()
    };
    next['stateHash'] = hashContinuityStateMaterial(next);
    await mutations.upsert('intelligenceSnapshots', next,
        type: 'CONTINUITY_AVOIDED_WORK');
    return next;
  }

  Future<void> recordFriction(String projectId, String type,
      {Map<String, Object?> detail = const {}}) async {
    final raw = await db.meta('continuity_friction_v1');
    List<dynamic> rows = [];
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) rows = decoded;
      } catch (_) {}
    }
    rows.add({
      'continuityVersion': continuityVersion,
      'frictionType': type,
      'projectId': projectId,
      'detail': detail,
      'createdAt': DateTime.now().toUtc().toIso8601String()
    });
    if (rows.length > 200) rows = rows.sublist(rows.length - 200);
    await db.setMeta('continuity_friction_v1', jsonEncode(rows));
  }

  Future<Map<String, Object?>> replayAnswer(String projectId,
      String previousAnswer, List<String> previousEvidenceIds) async {
    final truths = await db
        .recordsByJsonFields('truths', {'projectId': projectId}, limit: 10000);
    final known = <String>{};
    for (final table in ['messages', 'atoms', 'truths']) {
      for (final row in await db.records(table)) {
        known.add('${row['id']}');
      }
    }
    final missing =
        _unique(previousEvidenceIds.where((id) => !known.contains(id)));
    final sentences = RegExp(r'[^.!?]+[.!?]?')
        .allMatches(_norm(previousAnswer))
        .map((m) => _norm(m.group(0)))
        .where((x) => x.isNotEmpty)
        .toList();
    final out = <Map<String, Object?>>[];
    for (final sentence in sentences) {
      final ranked = truths
          .map((t) => (
                row: t,
                score: _overlap(
                    sentence, '${t['canonicalSubject'] ?? ''} ${t['text']}')
              ))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score) != 0
            ? b.score.compareTo(a.score)
            : '${a.row['id']}'.compareTo('${b.row['id']}'));
      final current = ranked
          .where((x) => '${x.row['status']}' == 'CURRENT' && x.score >= .18)
          .firstOrNull;
      final conflict = ranked
          .where((x) => '${x.row['status']}' == 'CONFLICTING' && x.score >= .18)
          .firstOrNull;
      final stale = ranked
          .where((x) =>
              {'SUPERSEDED', 'HISTORICAL'}.contains('${x.row['status']}') &&
              x.score >= .18)
          .firstOrNull;
      final match = current ?? conflict ?? stale;
      String status = current != null
          ? 'VALID'
          : conflict != null
              ? 'CONTRADICTED'
              : stale != null
                  ? 'STALE'
                  : missing.isNotEmpty
                      ? 'MISSING'
                      : 'UNVERIFIED';
      final replacement = status == 'VALID'
          ? null
          : ranked
              .where((x) => '${x.row['status']}' == 'CURRENT' && x.score >= .10)
              .map((x) => '${x.row['text']}')
              .firstOrNull;
      out.add({
        'text': sentence,
        'status': status,
        if (match != null) 'matchedTruthId': match.row['id'],
        'score': double.parse((match?.score ?? 0).toStringAsFixed(4)),
        if (replacement != null) 'replacement': replacement
      });
    }
    final core = {
      'format': 'B2_ANSWER_REPLAY',
      'version': 1,
      'projectId': projectId,
      'previousAnswerHash': sha256Hex(_norm(previousAnswer)),
      'missingEvidenceIds': missing,
      'sentences': out,
      'retained': out
          .where((x) => x['status'] == 'VALID')
          .map((x) => x['text'])
          .toList(),
      'repairDelta': out
          .where((x) => x['status'] != 'VALID')
          .map((x) => x['replacement'] != null
              ? '${x['status']}: ${x['text']} -> ${x['replacement']}'
              : '${x['status']}: ${x['text']}')
          .toList()
    };
    return {...core, 'replayHash': _hashJson(core)};
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
