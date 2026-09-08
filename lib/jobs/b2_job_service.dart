import 'dart:convert';

import '../asif/asif_reader_core.dart';
import '../core/contracts.dart';
import '../core/identity.dart';
import '../intelligence/atomization_stack.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class B2JobVerification {
  final String status;
  final bool jobExists;
  final bool memoryRootMatches;
  final bool databoxMatches;
  final int citedEvidenceCount;
  final List<String> missingEvidenceIds;
  final List<String> outsideJobEvidenceIds;
  final String detail;

  const B2JobVerification({
    required this.status,
    required this.jobExists,
    required this.memoryRootMatches,
    required this.databoxMatches,
    required this.citedEvidenceCount,
    required this.missingEvidenceIds,
    required this.outsideJobEvidenceIds,
    required this.detail,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status,
        'jobExists': jobExists,
        'memoryRootMatches': memoryRootMatches,
        'databoxMatches': databoxMatches,
        'citedEvidenceCount': citedEvidenceCount,
        'missingEvidenceIds': missingEvidenceIds,
        'outsideJobEvidenceIds': outsideJobEvidenceIds,
        'detail': detail,
      };
}

class B2JobService {
  final Brain2Database db;
  final MutationService mutations;
  final AsifReaderCore reader;

  const B2JobService(this.db, this.mutations, this.reader);

  Future<Map<String, Object?>> compile(
    String question, {
    String? projectId,
    int limit = 24,
  }) async {
    final q = normalizeText(question);
    if (q.isEmpty) throw ArgumentError('Enter a question or task first.');
    final plan = reader.planQuery(q, limit: limit);
    final evidence = await reader.query(
      q,
      candidateLimit: plan.candidateCap,
      evidenceLimit: limit,
      projectId: projectId,
      tables: const {'truths', 'atoms', 'messages'},
    );
    final evidenceJson =
        evidence.map((e) => e.toJson()).toList(growable: false);
    final sufficiency = assessAtomContextSufficiency(q, evidenceJson);
    final box = await reader.buildDatabox(
      q,
      evidenceLimit: limit,
      projectId: projectId,
      tables: const {'truths', 'atoms', 'messages'},
    );
    final boxJson = box.toJson();
    final now = DateTime.now().toUtc().toIso8601String();
    final root = await db.memoryRoot();
    final id = canonicalId('b2job-v2', [root, q, projectId, box.hash, now]);
    final job = <String, Object?>{
      'format': 'B2JOB',
      'version': 2,
      'id': id,
      'createdAt': now,
      'question': q,
      'task': q,
      'projectId': projectId,
      'memoryRoot': root,
      'evidenceHash': box.evidenceHash,
      'databox': boxJson,
      'evidencePolicy': <String, Object?>{
        'limit': evidenceJson.length,
        'method': 'asif-reader-rapidretrieve-v9',
        'route': plan.route,
        'fallback':
            sufficiency.state == 'SUFFICIENT' ? plan.fallback : 'B_250_CHUNK',
        'boundedContext': true,
        'candidateCap': plan.candidateCap,
        'atomizationStack': atomizationStackVersion,
        'sufficiencyScore': sufficiency.score,
        'sufficiencyState': sufficiency.state,
        'usedB250Fallback': sufficiency.state != 'SUFFICIENT',
      },
      'instructions': <String>[
        'Use the attached B2DATABOX as the authoritative minimum sufficient context.',
        'Preserve uncertainty and conflicts; do not silently choose one side of CONFLICTING evidence.',
        'Return only evidence IDs actually supplied by this B2JOB.',
        'If the Databox is insufficient, state the evidence gap instead of inventing facts.',
        'Memory writes are proposals only; no reasoning result directly mutates Current Truth.',
      ],
      'acceptance': <String, Object?>{
        'routing': 'DETERMINISTIC_THEN_COMPILED_THEN_MRS_RESIDUAL',
        'verification': 'INDEPENDENT_AFTER_EACH_SOLVE_PATH',
        'memoryWrite': 'PROPOSE_THEN_VERIFY',
        'forbidDirectDataboxToModel': true,
      },
      'evidence': evidenceJson,
      'schemaVersion': brain2SchemaVersion,
    };
    await mutations.upsert('databoxes', boxJson, type: 'CREATE_DATABOX');
    await mutations.upsert(
      'transactions',
      <String, Object?>{
        'id': id,
        'type': 'B2JOB',
        'payload': jsonEncode(job),
        'createdAt': now,
        'hash': sha256Hex(canonicalJson(job)),
      },
      type: 'CREATE_B2JOB',
    );
    return job;
  }

  Future<B2JobVerification> verifyResult(Map<String, Object?> result) async {
    if ('${result['format']}' != 'B2RESULT') {
      throw ArgumentError('Unsupported B2RESULT.');
    }
    final version = (result['version'] as num?)?.toInt() ?? 0;
    if (version != 1 && version != 2)
      throw ArgumentError('Unsupported B2RESULT version.');
    final jobId = '${result['jobId'] ?? ''}';
    final evidenceIds = ((result['evidenceIds'] as List?) ?? const [])
        .map((e) => '$e')
        .toSet()
        .toList();
    final transactions = await db.records('transactions',
        orderBy: 'updated_at DESC', limit: 1200);
    Map<String, Object?>? job;
    for (final tx in transactions) {
      if ('${tx['type']}' != 'B2JOB') continue;
      try {
        final decoded =
            (jsonDecode('${tx['payload']}') as Map).cast<String, Object?>();
        if ('${decoded['id']}' == jobId) {
          job = decoded;
          break;
        }
      } catch (_) {}
    }
    final root = await db.memoryRoot();
    final memoryRootMatches = job == null || '${job['memoryRoot']}' == root;
    final databox = job?['databox'] is Map
        ? (job!['databox'] as Map).cast<String, Object?>()
        : null;
    final databoxMatches = job == null ||
        version == 1 ||
        '${result['databoxHash']}' ==
            '${databox?['hash'] ?? databox?['manifestHash'] ?? ''}';
    final allowed = ((job?['evidence'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => '${e['id']}')
        .where((e) => e.isNotEmpty)
        .toSet();
    final missing = <String>[];
    final outside = <String>[];
    for (final id in evidenceIds) {
      var exists = false;
      for (final table in const ['truths', 'atoms', 'messages']) {
        if (await db.getRecord(table, id) != null) {
          exists = true;
          break;
        }
      }
      if (!exists)
        missing.add(id);
      else if (!allowed.contains(id)) outside.add(id);
    }
    final status = job == null ||
            !memoryRootMatches ||
            !databoxMatches ||
            missing.isNotEmpty ||
            outside.isNotEmpty
        ? 'FAIL'
        : evidenceIds.isNotEmpty
            ? 'PASS'
            : 'PENDING';
    final detail = job == null
        ? 'The referenced B2JOB is not present in this local memory.'
        : !memoryRootMatches
            ? 'The B2RESULT references a B2JOB from a different Brain2 memory root.'
            : !databoxMatches
                ? 'B2RESULT Databox hash does not match the canonical B2JOB context package.'
                : missing.isNotEmpty
                    ? 'Result cites ${missing.length} evidence ID(s) that do not exist in this local memory.'
                    : outside.isNotEmpty
                        ? 'Result cites ${outside.length} real evidence ID(s) that were not supplied by the referenced B2JOB.'
                        : evidenceIds.isNotEmpty
                            ? 'Structural provenance PASS: all cited evidence belongs to the referenced B2JOB.'
                            : 'No evidence IDs were cited.';
    return B2JobVerification(
      status: status,
      jobExists: job != null,
      memoryRootMatches: memoryRootMatches,
      databoxMatches: databoxMatches,
      citedEvidenceCount: evidenceIds.length,
      missingEvidenceIds: missing,
      outsideJobEvidenceIds: outside,
      detail: detail,
    );
  }
}
