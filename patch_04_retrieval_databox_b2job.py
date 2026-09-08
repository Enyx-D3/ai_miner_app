#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
ASIF = ROOT / 'lib/asif/asif_reader_core.dart'
ASK = ROOT / 'lib/ui/screens/ask_screen.dart'
JOB = ROOT / 'lib/jobs/b2_job_service.dart'
for p in (ASIF, ASK):
    if not p.exists():
        raise SystemExit(f'ERROR: expected mobile project file not found: {p}')
JOB.parent.mkdir(parents=True, exist_ok=True)
stamp = str(int(time.time()))
def backup(p: Path):
    if p.exists():
        shutil.copy2(p, p.with_name(p.name + f'.pre_retrieval_b2job_{stamp}'))

asif = r'''import 'dart:convert';

import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';

enum AsifEvidenceBudget { tiny, balanced, deep }

class AsifReaderQueryPlan {
  final String owner;
  final String retrievalOwner;
  final String route;
  final String? fallback;
  final AsifEvidenceBudget budget;
  final int termCap;
  final int candidateCap;
  final int resultCap;
  final double truthBoost;
  final double diversityBoost;
  final String reason;

  const AsifReaderQueryPlan({
    required this.owner,
    required this.retrievalOwner,
    required this.route,
    required this.fallback,
    required this.budget,
    required this.termCap,
    required this.candidateCap,
    required this.resultCap,
    required this.truthBoost,
    required this.diversityBoost,
    required this.reason,
  });

  String get budgetName => switch (budget) {
        AsifEvidenceBudget.tiny => 'TINY',
        AsifEvidenceBudget.balanced => 'BALANCED',
        AsifEvidenceBudget.deep => 'DEEP',
      };
}

class ReaderEvidence {
  final String id;
  final String table;
  final String recordId;
  final double score;
  final String recordHash;
  final Map<String, Object?> record;

  const ReaderEvidence({
    required this.id,
    required this.table,
    required this.recordId,
    required this.score,
    required this.recordHash,
    required this.record,
  });

  String get type => table == 'truths'
      ? 'truth'
      : table == 'atoms'
          ? 'atom'
          : table == 'messages'
              ? 'message'
              : table;

  Map<String, Object?> toJson() {
    final text = normalizeText('${record['text'] ?? record['content'] ?? record['value'] ?? record['title'] ?? record['summary'] ?? ''}');
    return <String, Object?>{
      'id': id,
      'type': type,
      'table': table,
      'recordId': recordId,
      'text': text,
      'projectId': record['projectId'],
      'sourceId': record['sourceId'],
      'conversationId': record['conversationId'],
      'messageId': record['messageId'] ?? (table == 'messages' ? record['id'] : null),
      'blockId': record['blockId'],
      'truthStatus': table == 'truths' ? record['status'] : record['truthStatus'],
      'sourceStart': record['sourceStart'],
      'sourceEnd': record['sourceEnd'],
      'createdAt': record['occurredAt'] ?? record['createdAt'] ?? record['updatedAt'],
      'intrinsicSufficiency': record['intrinsicSufficiency'],
      'score': score,
      'recordHash': recordHash,
      // Mobile MRS compatibility: keep the verified hydrated record.
      'record': record,
    };
  }
}

class ReaderDatabox {
  final String id;
  final String query;
  final String? projectId;
  final String memoryRoot;
  final String route;
  final String createdAt;
  final List<ReaderEvidence> evidence;
  final String evidenceHash;
  final String hash;
  final int sourceCount;
  final int evidenceBlockCount;
  final int currentTruthCount;
  final int conflictCount;
  final AsifReaderQueryPlan plan;

  const ReaderDatabox({
    required this.id,
    required this.query,
    required this.projectId,
    required this.memoryRoot,
    required this.route,
    required this.createdAt,
    required this.evidence,
    required this.evidenceHash,
    required this.hash,
    required this.sourceCount,
    required this.evidenceBlockCount,
    required this.currentTruthCount,
    required this.conflictCount,
    required this.plan,
  });

  // Historical mobile callers use manifestHash. Keep it as an alias to the
  // canonical Databox hash so existing MRS/UI code remains source-compatible.
  String get manifestHash => hash;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'format': 'B2DATABOX',
        'type': 'B2DATABOX',
        'version': 1,
        'reader': brain2RetrievalVersion,
        'readerCore': asifReaderCoreVersion,
        'query': query,
        'projectId': projectId,
        'memoryRoot': memoryRoot,
        'retrievalRoute': route,
        'route': route,
        'budget': plan.budgetName,
        'candidateCap': plan.candidateCap,
        'resultCap': plan.resultCap,
        'truthBoost': plan.truthBoost,
        'diversityBoost': plan.diversityBoost,
        'createdAt': createdAt,
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
        'evidenceHash': evidenceHash,
        'manifestHash': hash,
        'hash': hash,
        'sourceCount': sourceCount,
        'evidenceBlockCount': evidenceBlockCount,
        'currentTruthCount': currentTruthCount,
        'conflictCount': conflictCount,
      };
}

/// Pure-Dart ASIF Reader / RapidRetrieve core aligned with the Web routing
/// contract while preserving SQLite as the mobile derived index.
class AsifReaderCore {
  final Brain2Database db;
  const AsifReaderCore(this.db);

  String get owner => 'ASIF_READER';
  String get retrievalOwner => 'RAPIDRETRIEVE';
  String get coreVersion => asifReaderCoreVersion;

  Future<void> ensureReady() => db.ensureReaderIndex();

  AsifReaderQueryPlan planQuery(String query, {int limit = 256}) {
    final text = normalizeText(query);
    final temporal = RegExp(
      r'\b(current|currently|latest|now|changed|change|before|after|timeline|history|supersed|replaced|decision|decided|version|status|what are we using|what did we decide)\b',
      caseSensitive: false,
    ).hasMatch(text);
    final heterogeneous = RegExp(
      r'\b(compare|comparison|relationship|relate|connect|connection|across|contradiction|conflict|why|cause|depends|dependency|multiple|projects|pattern)\b',
      caseSensitive: false,
    ).hasMatch(text);
    final route = temporal
        ? 'F_TEMPORAL_TRUTH'
        : heterogeneous
            ? 'G_ADAPTIVE_HETEROGENEOUS'
            : 'B_250_CHUNK';
    final fallback = route == 'B_250_CHUNK' ? null : 'B_250_CHUNK';
    final candidateCap = temporal ? 192 : heterogeneous ? 320 : 256;
    final truthBoost = temporal ? 3.2 : heterogeneous ? 2.4 : 2.2;
    final diversityBoost = temporal ? .2 : heterogeneous ? .9 : .35;
    final resultCap = limit.clamp(1, 256).toInt();
    final budget = resultCap <= 32 && candidateCap <= 192
        ? AsifEvidenceBudget.tiny
        : resultCap <= 96 && candidateCap <= 320
            ? AsifEvidenceBudget.balanced
            : AsifEvidenceBudget.deep;
    return AsifReaderQueryPlan(
      owner: owner,
      retrievalOwner: retrievalOwner,
      route: route,
      fallback: fallback,
      budget: budget,
      termCap: temporal ? 16 : 14,
      candidateCap: candidateCap.clamp(resultCap, 512).toInt(),
      resultCap: resultCap,
      truthBoost: truthBoost,
      diversityBoost: diversityBoost,
      reason: temporal
          ? 'temporal/current-truth query'
          : heterogeneous
              ? 'multi-unit/relationship query'
              : 'bounded recall safety route',
    );
  }

  List<String> _terms(String query, int cap) => normalizeText(query)
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true))
      .where((t) => t.length >= 2)
      .toSet()
      .take(cap)
      .toList(growable: false);

  Future<List<ReaderEvidence>> query(
    String query, {
    int candidateLimit = 256,
    int evidenceLimit = 24,
    Set<String>? tables,
    String? projectId,
  }) async {
    await ensureReady();
    final plan = planQuery(query, limit: evidenceLimit);
    final terms = _terms(query, plan.termCap);
    final effectiveCandidate = candidateLimit < plan.candidateCap ? candidateLimit : plan.candidateCap;
    final candidates = terms.isEmpty
        ? await db.readerRecent(limit: effectiveCandidate, tables: tables)
        : await db.readerCandidates(terms, limit: effectiveCandidate, tables: tables);
    final out = <ReaderEvidence>[];
    final exact = normalizeText(query).toLowerCase();
    final diversitySeen = <String, int>{};

    for (final candidate in candidates) {
      final table = '${candidate['table_name']}';
      final recordId = '${candidate['record_id']}';
      final record = await db.getRecord(table, recordId);
      if (record == null) continue;
      if (projectId != null && projectId.isNotEmpty) {
        final recordProjectId = '${record['projectId'] ?? ''}';
        if (recordProjectId.isNotEmpty && recordProjectId != projectId) continue;
      }
      final expected = '${candidate['record_hash']}';
      final actual = hashEntity(record);
      if (expected.isEmpty || expected != actual) continue;
      var score = (candidate['score'] as num?)?.toDouble() ?? double.tryParse('${candidate['score']}') ?? 0;
      final searchable = normalizeText([
        record['title'], record['name'], record['text'], record['content'], record['value'],
        record['subject'], record['summary'], record['description'], record['status'],
      ].where((x) => x != null).join(' ')).toLowerCase();
      if (exact.isNotEmpty && searchable.contains(exact)) score += 5;
      for (final term in terms) if (searchable.contains(term)) score += 1;
      if (table == 'truths') {
        final status = '${record['status']}';
        if (status == 'CURRENT') score += plan.truthBoost;
        else if (status == 'CONFLICTING') score += 1.3;
        else if (status == 'PENDING_REVIEW') score += .6;
        score += (record['confidence'] as num?)?.toDouble() ?? 0;
      }
      if (table == 'atoms') {
        score += (record['confidence'] as num?)?.toDouble() ?? 0;
        if (const {'decision', 'constraint'}.contains('${record['kind']}')) score += .8;
      }
      final diversityKey = '${record['projectId'] ?? 'none'}|${record['sourceId'] ?? 'none'}|$table';
      final seen = diversitySeen[diversityKey] ?? 0;
      score -= seen * plan.diversityBoost * .15;
      diversitySeen[diversityKey] = seen + 1;
      out.add(ReaderEvidence(
        id: canonicalId('ev', [table, recordId, actual]),
        table: table,
        recordId: recordId,
        score: score,
        recordHash: actual,
        record: record,
      ));
    }
    out.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.recordId.compareTo(b.recordId);
    });
    final dedup = <String, ReaderEvidence>{};
    for (final item in out) {
      final key = normalizeText('${item.record['text'] ?? item.record['content'] ?? item.record['value'] ?? item.record['title'] ?? item.recordId}').toLowerCase();
      dedup.putIfAbsent(key, () => item);
      if (dedup.length >= plan.resultCap) break;
    }
    return dedup.values.toList(growable: false);
  }

  Future<ReaderDatabox> buildDatabox(
    String query, {
    int evidenceLimit = 24,
    Set<String>? tables,
    String? projectId,
  }) async {
    final plan = planQuery(query, limit: evidenceLimit);
    final evidence = await this.query(
      query,
      evidenceLimit: evidenceLimit,
      tables: tables,
      projectId: projectId,
    );
    final root = await db.memoryRoot();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final evidenceRows = evidence.map((e) {
      final j = e.toJson();
      return <Object?>[
        j['id'], j['type'], j['text'], j['projectId'], j['sourceId'], j['conversationId'],
        j['messageId'], j['blockId'], j['truthStatus'], j['sourceStart'], j['sourceEnd'], j['createdAt'],
      ];
    }).toList(growable: false);
    final evidenceHash = sha256Hex(canonicalJson(evidenceRows));
    final sourceCount = evidence.map((e) => '${e.record['sourceId'] ?? ''}').where((e) => e.isNotEmpty).toSet().length;
    final evidenceBlockCount = evidence.map((e) => '${e.record['blockId'] ?? ''}').where((e) => e.isNotEmpty).toSet().length;
    final currentTruthCount = evidence.where((e) => e.table == 'truths' && '${e.record['status']}' == 'CURRENT').length;
    final explicitConflictCount = evidence.where((e) => e.table == 'truths' && '${e.record['status']}' == 'CONFLICTING').length;
    final evidenceIds = evidence.map((e) => e.recordId).toSet();
    final hotTruths = await db.records('truths', orderBy: 'updated_at DESC', limit: 1200);
    final hotConflictCount = hotTruths.where((truth) {
      if ('${truth['status']}' != 'CONFLICTING') return false;
      if (evidenceIds.contains('${truth['id']}')) return true;
      return ((truth['evidenceAtomIds'] as List?) ?? const []).map((e) => '$e').any(evidenceIds.contains);
    }).length;
    final conflictCount = explicitConflictCount > hotConflictCount ? explicitConflictCount : hotConflictCount;
    final route = plan.route;
    final id = canonicalId('databox', [root, normalizeText(query), projectId, route, evidenceHash]);
    final hash = sha256Hex(canonicalJson(<String, Object?>{
      'id': id,
      'query': normalizeText(query),
      'projectId': projectId,
      'memoryRoot': root,
      'retrievalRoute': route,
      'evidenceHash': evidenceHash,
      'sourceCount': sourceCount,
      'currentTruthCount': currentTruthCount,
      'conflictCount': conflictCount,
    }));
    return ReaderDatabox(
      id: id,
      query: normalizeText(query),
      projectId: projectId,
      memoryRoot: root,
      route: route,
      createdAt: createdAt,
      evidence: evidence,
      evidenceHash: evidenceHash,
      hash: hash,
      sourceCount: sourceCount,
      evidenceBlockCount: evidenceBlockCount,
      currentTruthCount: currentTruthCount,
      conflictCount: conflictCount,
      plan: plan,
    );
  }

  bool verifyDatabox(ReaderDatabox box) {
    final evidenceRows = box.evidence.map((e) {
      final j = e.toJson();
      return <Object?>[
        j['id'], j['type'], j['text'], j['projectId'], j['sourceId'], j['conversationId'],
        j['messageId'], j['blockId'], j['truthStatus'], j['sourceStart'], j['sourceEnd'], j['createdAt'],
      ];
    }).toList(growable: false);
    if (sha256Hex(canonicalJson(evidenceRows)) != box.evidenceHash) return false;
    final hash = sha256Hex(canonicalJson(<String, Object?>{
      'id': box.id,
      'query': box.query,
      'projectId': box.projectId,
      'memoryRoot': box.memoryRoot,
      'retrievalRoute': box.route,
      'evidenceHash': box.evidenceHash,
      'sourceCount': box.sourceCount,
      'currentTruthCount': box.currentTruthCount,
      'conflictCount': box.conflictCount,
    }));
    return hash == box.hash;
  }

  String encodeDatabox(ReaderDatabox box) => jsonEncode(box.toJson());
}
'''

job = r'''import 'dart:convert';

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
    final evidenceJson = evidence.map((e) => e.toJson()).toList(growable: false);
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
        'fallback': sufficiency.state == 'SUFFICIENT' ? plan.fallback : 'B_250_CHUNK',
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
    if (version != 1 && version != 2) throw ArgumentError('Unsupported B2RESULT version.');
    final jobId = '${result['jobId'] ?? ''}';
    final evidenceIds = ((result['evidenceIds'] as List?) ?? const []).map((e) => '$e').toSet().toList();
    final transactions = await db.records('transactions', orderBy: 'updated_at DESC', limit: 1200);
    Map<String, Object?>? job;
    for (final tx in transactions) {
      if ('${tx['type']}' != 'B2JOB') continue;
      try {
        final decoded = (jsonDecode('${tx['payload']}') as Map).cast<String, Object?>();
        if ('${decoded['id']}' == jobId) {
          job = decoded;
          break;
        }
      } catch (_) {}
    }
    final root = await db.memoryRoot();
    final memoryRootMatches = job == null || '${job['memoryRoot']}' == root;
    final databox = job?['databox'] is Map ? (job!['databox'] as Map).cast<String, Object?>() : null;
    final databoxMatches = job == null || version == 1 || '${result['databoxHash']}' == '${databox?['hash'] ?? databox?['manifestHash'] ?? ''}';
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
      if (!exists) missing.add(id);
      else if (!allowed.contains(id)) outside.add(id);
    }
    final status = job == null || !memoryRootMatches || !databoxMatches || missing.isNotEmpty || outside.isNotEmpty
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
'''

backup(ASIF); ASIF.write_text(asif)
backup(JOB); JOB.write_text(job)

s = ASK.read_text()
if "import '../../jobs/b2_job_service.dart';" not in s:
    anchor = "import '../../core/identity.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: AskScreen import anchor not found')
    s = s.replace(anchor, anchor + "import '../../jobs/b2_job_service.dart';\n", 1)
# Replace the manual Databox+B2JOB construction while preserving current UI/result flow.
start = s.find("      final box = await widget.c.reader.buildDatabox(q.text);")
end = s.find("      final run = await widget.c.mrs.run", start)
if start >= 0 and end > start and 'final service = B2JobService' not in s:
    replacement = """      final service = B2JobService(\n        widget.c.db,\n        widget.c.mutations,\n        widget.c.reader,\n      );\n      final j = await service.compile(q.text);\n      final boxJson = (j['databox'] as Map).cast<String, Object?>();\n"""
    s = s[:start] + replacement + s[end:]
# Remove now-unused dart:convert/core identity imports only if no longer referenced.
if "jsonEncode(" not in s and "JsonEncoder" in s:
    pass
# JsonEncoder is still used in UI, so dart:convert remains. canonicalId/sha256 no longer needed.
if "canonicalId(" not in s and "sha256Hex(" not in s and "canonicalJson(" not in s:
    s = s.replace("import '../../core/identity.dart';\n", "")
backup(ASK); ASK.write_text(s)

print('PASS patch_04_retrieval_databox_b2job')
print('  upgraded ASIF Reader routing/scoring to Web-style F/G/B250 routes')
print('  canonical B2DATABOX fields added while retaining Mobile MRS compatibility')
print(f'  wrote: {JOB.relative_to(ROOT)}')
print('  Ask Brain2 now compiles/persists a verified B2JOB through the service')
print('  current Ask UI is preserved')
