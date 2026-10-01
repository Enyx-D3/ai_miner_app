import 'dart:convert';

import '../asif/asif_reader_core.dart';
import '../core/contracts.dart';
import '../core/identity.dart';
import '../jobs/b2_job_service.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class GlobalContextService {
  final Brain2Database db;
  final MutationService mutations;
  final AsifReaderCore reader;

  const GlobalContextService(this.db, this.mutations, this.reader);

  Future<Map<String, Object?>> buildResumeCapsule(
      Map<String, Object?> project) async {
    final projectId = '${project['id'] ?? ''}';
    if (projectId.isEmpty) {
      throw ArgumentError('Project has no canonical id.');
    }

    final truthRows = await db.recordsByJsonFields(
      'truths',
      {'projectId': projectId},
      newestFirst: true,
      limit: 200,
    );
    final current = truthRows
        .where((row) => '${row['status']}' == 'CURRENT')
        .toList(growable: true)
      ..sort((a, b) =>
          '${b['updatedAt'] ?? b['createdAt'] ?? ''}'
              .compareTo('${a['updatedAt'] ?? a['createdAt'] ?? ''}'));
    final changes = truthRows
        .where((row) => '${row['status']}' != 'CURRENT')
        .take(12)
        .toList(growable: false);
    final tickRows = await db.recordsByJsonFields(
      'ticks',
      {'projectId': projectId},
      newestFirst: true,
      limit: 100,
    );
    final ticks = tickRows
        .where((row) => '${row['status']}' == 'OPEN')
        .toList(growable: false)
      ..sort((a, b) {
        int score(Map<String, Object?> r) =>
            '${r['priority']}' == 'HIGH' ? 3 : '${r['priority']}' == 'MEDIUM' ? 2 : 1;
        final priority = score(b).compareTo(score(a));
        if (priority != 0) return priority;
        return '${b['updatedAt'] ?? b['createdAt'] ?? ''}'
            .compareTo('${a['updatedAt'] ?? a['createdAt'] ?? ''}');
      });
    final failureRows = await db.recordsByJsonFields(
      'failureMemory',
      {'projectId': projectId},
      newestFirst: true,
      limit: 100,
    );
    failureRows.sort((a, b) =>
        '${b['lastSeenAt'] ?? b['createdAt'] ?? ''}'
            .compareTo('${a['lastSeenAt'] ?? a['createdAt'] ?? ''}'));
    final failures = failureRows.take(8).toList(growable: false);

    Map<String, Object?>? currentTask;
    for (final row in current) {
      if ('${row['kind']}' == 'task') {
        currentTask = row;
        break;
      }
    }
    final goal = normalizeText(
      '${currentTask?['text'] ?? project['summary'] ?? project['name'] ?? 'Continue project'}',
    );

    final nextAction = ticks.isNotEmpty
        ? <String, Object?>{
            'kind': 'TICK',
            'text': '${ticks.first['title'] ?? ticks.first['detail'] ?? 'Review human control point'}',
            'refId': '${ticks.first['id']}',
          }
        : currentTask != null
            ? <String, Object?>{
                'kind': 'TASK',
                'text': '${currentTask['text']}',
                'refId': '${currentTask['id']}',
              }
            : <String, Object?>{
                'kind': 'CONTINUE',
                'text': 'Continue ${project['name'] ?? 'this project'} from the latest verified project state.',
              };

    final evidenceRefs = <String>{};
    for (final row in current) {
      final ids = (row['evidenceAtomIds'] as List?) ?? const [];
      evidenceRefs.addAll(ids.map((e) => '$e').where((e) => e.isNotEmpty));
      if ('${row['atomId'] ?? ''}'.isNotEmpty) evidenceRefs.add('${row['atomId']}');
    }
    for (final row in ticks) {
      final ids = (row['evidenceAtomIds'] as List?) ?? const [];
      evidenceRefs.addAll(ids.map((e) => '$e').where((e) => e.isNotEmpty));
    }
    for (final row in failures) {
      final ids = (row['evidenceIds'] as List?) ?? const [];
      evidenceRefs.addAll(ids.map((e) => '$e').where((e) => e.isNotEmpty));
    }

    Map<String, Object?> minimalTruth(Map<String, Object?> row) => {
          'id': '${row['id']}',
          'kind': '${row['kind']}',
          'text': '${row['text']}',
          'confidence': row['confidence'] ?? 0,
          'updatedAt': '${row['updatedAt'] ?? row['createdAt'] ?? ''}',
          'evidenceAtomIds': (((row['evidenceAtomIds'] as List?) ?? const [])
                .map((e) => '$e')
                .toSet()
                .toList()
              ..sort()),
        };
    Map<String, Object?> minimalTick(Map<String, Object?> row) => {
          'id': '${row['id']}',
          'title': '${row['title']}',
          'detail': '${row['detail']}',
          'priority': '${row['priority']}',
          if (row['actionType'] != null) 'actionType': '${row['actionType']}',
          'evidenceAtomIds': (((row['evidenceAtomIds'] as List?) ?? const [])
                .map((e) => '$e')
                .toSet()
                .toList()
              ..sort()),
        };
    Map<String, Object?> minimalFailure(Map<String, Object?> row) => {
          'id': '${row['id']}',
          'failureSignature': '${row['failureSignature']}',
          'title': '${row['title']}',
          'cause': '${row['cause']}',
          if (row['repairThatWorked'] != null)
            'repairThatWorked': '${row['repairThatWorked']}',
          'boundaryConditions': (((row['boundaryConditions'] as List?) ?? const [])
                .map((e) => '$e')
                .toSet()
                .toList()
              ..sort()),
          'occurrenceCount': row['occurrenceCount'] ?? 0,
        };

    final currentMinimal = current.map(minimalTruth).toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final tickMinimal = ticks.map(minimalTick).toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final failureMinimal = failures.map(minimalFailure).toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final changeMinimal = changes
        .map((row) => <String, Object?>{
              'id': '${row['id']}',
              'status': '${row['status']}',
              'kind': '${row['kind']}',
              'text': '${row['text']}',
              'updatedAt': '${row['updatedAt'] ?? row['createdAt'] ?? ''}',
            })
        .toList()
      ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final aliases = (((project['aliases'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet()
          .toList()
        ..sort());
    final evidence = evidenceRefs.toList()..sort();

    final stable = <String, Object?>{
      'format': 'GLOBAL_CONTEXT_RESUME',
      'version': 1,
      'memoryRoot': await db.memoryRoot(),
      'projectId': projectId,
      'projectName': '${project['name'] ?? projectId}',
      'projectAliases': aliases,
      'goal': goal,
      'currentTruth': currentMinimal,
      'openTicks': tickMinimal,
      'knownFailures': failureMinimal,
      'recentChanges': changeMinimal,
      'nextAction': nextAction,
      'evidenceRefs': evidence,
    };
    return {
      ...stable,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'capsuleHash': sha256Hex(canonicalJson(stable)),
    };
  }

  Future<Map<String, Object?>> compileContextPackage({
    required Map<String, Object?> project,
    required String task,
    int evidenceLimit = 24,
  }) async {
    final clean = normalizeText(task);
    if (clean.isEmpty) throw ArgumentError('A continuation task is required.');
    final projectId = '${project['id'] ?? ''}';
    final resume = await buildResumeCapsule(project);
    final job = await B2JobService(db, mutations, reader).compile(
      clean,
      projectId: projectId,
      limit: evidenceLimit,
    );
    final databox = (job['databox'] as Map).cast<String, Object?>();
    final evidence = ((job['evidence'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => '${e['id']}')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final supplementCore = <String, Object?>{
      'format': 'B2JOB',
      'version': 2,
      'jobId': '${job['id']}',
      'databoxHash': '${databox['hash'] ?? databox['manifestHash'] ?? ''}',
      'evidenceHash': '${job['evidenceHash'] ?? ''}',
      'evidenceIds': evidence,
      'sufficiencyState':
          '${(job['evidencePolicy'] as Map?)?['sufficiencyState'] ?? ''}',
      'route': '${(job['evidencePolicy'] as Map?)?['route'] ?? ''}',
    };
    final supplement = {
      ...supplementCore,
      'supplementHash': sha256Hex(canonicalJson(supplementCore)),
    };
    final policy = <String, Object?>{
      'bounded': true,
      'fullArchiveIncluded': false,
      'askEveryTime': true,
      'resultWritePolicy': 'PROPOSE_THEN_VERIFY',
      'currentTruthWritePolicy': 'R1_OR_TICK_AFTER_VERIFY',
    };
    final stable = <String, Object?>{
      'format': 'GLOBAL_CONTEXT_PACKAGE',
      'version': 1,
      'memoryRoot': await db.memoryRoot(),
      'projectId': projectId,
      'projectName': '${project['name'] ?? projectId}',
      'task': clean,
      'resumeCapsuleHash': '${resume['capsuleHash']}',
      'currentTruthIds': (((resume['currentTruth'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => '${e['id']}')
            .toList()
          ..sort()),
      'openTickIds': (((resume['openTicks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => '${e['id']}')
            .toList()
          ..sort()),
      'failureSignatures': (((resume['knownFailures'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => '${e['failureSignature']}')
            .toList()
          ..sort()),
      'compilerSupplementHash': '${supplement['supplementHash']}',
      'policy': policy,
    };
    return <String, Object?>{
      'format': 'GLOBAL_CONTEXT_PACKAGE',
      'version': 1,
      'memoryRoot': stable['memoryRoot'],
      'projectId': projectId,
      'projectName': stable['projectName'],
      'task': clean,
      'resumeCapsule': resume,
      'policy': policy,
      'compilerSupplement': supplement,
      'packageHash': sha256Hex(canonicalJson(stable)),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Set<String> _terms(String value) => RegExp(r"[a-z0-9][a-z0-9'-]{2,}")
      .allMatches(normalizeText(value).toLowerCase())
      .map((m) => m.group(0)!)
      .toSet();

  double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final i = a.intersection(b).length;
    return i / (a.length + b.length - i);
  }

  Future<List<Map<String, Object?>>> antiReinvention(
    String query, {
    String? projectId,
    int limit = 6,
  }) async {
    final q = _terms(query);
    if (q.isEmpty) return const [];
    final hits = <Map<String, Object?>>[];

    for (final row in await db.records('truths', limit: 1200)) {
      if (projectId != null && '${row['projectId']}' != projectId) continue;
      final score = _overlap(q, _terms('${row['kind']} ${row['text']} ${row['canonicalSubject'] ?? ''}'));
      if (score < .18) continue;
      final current = '${row['status']}' == 'CURRENT';
      hits.add({
        'id': '${row['id']}',
        'kind': current ? 'CURRENT_TRUTH' : 'HISTORICAL_TRUTH',
        'title': current ? 'Existing Current Truth' : 'Existing ${row['status']} work',
        'detail': '${row['text']}',
        'score': (score + (current ? .18 : .04)).clamp(0, 1),
        'action': current ? 'REUSE' : 'REVIEW',
      });
    }
    for (final row in await db.records('failureMemory', limit: 400)) {
      if (projectId != null &&
          '${row['projectId'] ?? ''}'.isNotEmpty &&
          '${row['projectId']}' != projectId) continue;
      final score = _overlap(
        q,
        _terms('${row['title']} ${row['cause']} ${row['knownBadOperation'] ?? ''} ${row['boundaryConditions'] ?? ''}'),
      );
      if (score < .16) continue;
      hits.add({
        'id': '${row['id']}',
        'kind': 'FAILURE',
        'title': 'Known failed route',
        'detail': '${row['title']}: ${row['cause']}',
        'score': (score + .22).clamp(0, 1),
        'action': 'BRAKE_CANDIDATE',
      });
    }
    hits.sort((a, b) =>
        ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));
    return hits.take(limit).toList(growable: false);
  }

  String renderOutbound(Map<String, Object?> package) {
    final resume =
        (package['resumeCapsule'] as Map).cast<String, Object?>();
    final truth = ((resume['currentTruth'] as List?) ?? const [])
        .whereType<Map>()
        .take(12);
    final ticks = ((resume['openTicks'] as List?) ?? const [])
        .whereType<Map>()
        .take(8);
    final failures = ((resume['knownFailures'] as List?) ?? const [])
        .whereType<Map>()
        .take(6);
    final supplement =
        (package['compilerSupplement'] as Map?)?.cast<String, Object?>();
    final evidence = ((supplement?['evidenceIds'] as List?) ??
            (resume['evidenceRefs'] as List?) ??
            const [])
        .map((e) => '$e')
        .take(64)
        .toList();

    return [
      'GLOBAL CONTEXT — BOUNDED CONTINUATION PACKAGE',
      'Project: ${package['projectName']}',
      'Task: ${package['task']}',
      'Current goal: ${resume['goal']}',
      '',
      'CURRENT TRUTH:',
      if (truth.isEmpty)
        '- No promoted Current Truth for this project.'
      else
        ...truth.map((e) => '- [${e['kind']}] ${e['text']}'),
      '',
      'OPEN HUMAN CONTROL POINTS:',
      if (ticks.isEmpty)
        '- None.'
      else
        ...ticks.map((e) => '- [${e['priority']}] ${e['title']}: ${e['detail']}'),
      '',
      'KNOWN FAILED ROUTES / REPAIRS:',
      if (failures.isEmpty)
        '- None recorded.'
      else
        ...failures.map((e) =>
            '- ${e['title']}: ${e['cause']}${e['repairThatWorked'] != null ? ' | repair: ${e['repairThatWorked']}' : ''}'),
      '',
      'EXACT NEXT ACTION: ${(resume['nextAction'] as Map)['text']}',
      '',
      'SELECTED EVIDENCE IDS (${evidence.length}): ${evidence.join(', ')}',
      '',
      'BOUNDARIES:',
      '- Use only this bounded package plus evidence explicitly provided with it.',
      '- Preserve uncertainty, conflict and superseded history; do not flatten them into Current Truth.',
      '- Do not treat this package as permission to read or transmit the full archive.',
      '- Returned results are proposals until source/provenance verification passes.',
      '',
      'GLOBAL_CONTEXT_PACKAGE_HASH: ${package['packageHash']}',
    ].join('\n');
  }

  Future<Map<String, Object?>> recordHandoff({
    required Map<String, Object?> package,
    required String outbound,
    required String destination,
    String sourceSurface = 'android',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final outboundHash = sha256Hex(outbound);
    final core = <String, Object?>{
      'format': 'GLOBAL_CONTEXT_HANDOFF',
      'version': 1,
      'memoryRoot': '${package['memoryRoot']}',
      'projectId': '${package['projectId']}',
      'destination': destination,
      'packageHash': '${package['packageHash']}',
      'outboundHash': outboundHash,
      'sourceSurface': sourceSurface,
      'consent': 'EXPLICIT_USER_ACTION',
    };
    final receipt = <String, Object?>{
      ...core,
      'id': canonicalId('gch', [
        package['memoryRoot'],
        package['projectId'],
        package['packageHash'],
        outboundHash,
        destination
      ]),
      'approvedAt': now,
      'hash': sha256Hex(canonicalJson(core)),
      'schemaVersion': brain2SchemaVersion,
    };
    await mutations.upsert(
      'transactions',
      {
        'id': receipt['id'],
        'type': 'B2REQUEST',
        'projectId': package['projectId'],
        'payload': jsonEncode(receipt),
        'createdAt': now,
        'updatedAt': now,
        'hash': receipt['hash'],
        'schemaVersion': brain2SchemaVersion,
      },
      type: 'GLOBAL_CONTEXT_HANDOFF_APPROVED',
    );
    return receipt;
  }
}
