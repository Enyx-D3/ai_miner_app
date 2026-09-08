import 'dart:convert';

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
    final text = normalizeText(
        '${record['text'] ?? record['content'] ?? record['value'] ?? record['title'] ?? record['summary'] ?? ''}');
    return <String, Object?>{
      'id': id,
      'type': type,
      'table': table,
      'recordId': recordId,
      'text': text,
      'projectId': record['projectId'],
      'sourceId': record['sourceId'],
      'conversationId': record['conversationId'],
      'messageId':
          record['messageId'] ?? (table == 'messages' ? record['id'] : null),
      'blockId': record['blockId'],
      'truthStatus':
          table == 'truths' ? record['status'] : record['truthStatus'],
      'sourceStart': record['sourceStart'],
      'sourceEnd': record['sourceEnd'],
      'createdAt':
          record['occurredAt'] ?? record['createdAt'] ?? record['updatedAt'],
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
    final candidateCap = temporal
        ? 192
        : heterogeneous
            ? 320
            : 256;
    final truthBoost = temporal
        ? 3.2
        : heterogeneous
            ? 2.4
            : 2.2;
    final diversityBoost = temporal
        ? .2
        : heterogeneous
            ? .9
            : .35;
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
    final effectiveCandidate =
        candidateLimit < plan.candidateCap ? candidateLimit : plan.candidateCap;
    final candidates = terms.isEmpty
        ? await db.readerRecent(limit: effectiveCandidate, tables: tables)
        : await db.readerCandidates(terms,
            limit: effectiveCandidate, tables: tables);
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
        if (recordProjectId.isNotEmpty && recordProjectId != projectId)
          continue;
      }
      final expected = '${candidate['record_hash']}';
      final actual = hashEntity(record);
      if (expected.isEmpty || expected != actual) continue;
      var score = (candidate['score'] as num?)?.toDouble() ??
          double.tryParse('${candidate['score']}') ??
          0;
      final searchable = normalizeText([
        record['title'],
        record['name'],
        record['text'],
        record['content'],
        record['value'],
        record['subject'],
        record['summary'],
        record['description'],
        record['status'],
      ].where((x) => x != null).join(' '))
          .toLowerCase();
      if (exact.isNotEmpty && searchable.contains(exact)) score += 5;
      for (final term in terms) if (searchable.contains(term)) score += 1;
      if (table == 'truths') {
        final status = '${record['status']}';
        if (status == 'CURRENT')
          score += plan.truthBoost;
        else if (status == 'CONFLICTING')
          score += 1.3;
        else if (status == 'PENDING_REVIEW') score += .6;
        score += (record['confidence'] as num?)?.toDouble() ?? 0;
      }
      if (table == 'atoms') {
        score += (record['confidence'] as num?)?.toDouble() ?? 0;
        if (const {'decision', 'constraint'}.contains('${record['kind']}'))
          score += .8;
      }
      final diversityKey =
          '${record['projectId'] ?? 'none'}|${record['sourceId'] ?? 'none'}|$table';
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
      final key = normalizeText(
              '${item.record['text'] ?? item.record['content'] ?? item.record['value'] ?? item.record['title'] ?? item.recordId}')
          .toLowerCase();
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
        j['id'],
        j['type'],
        j['text'],
        j['projectId'],
        j['sourceId'],
        j['conversationId'],
        j['messageId'],
        j['blockId'],
        j['truthStatus'],
        j['sourceStart'],
        j['sourceEnd'],
        j['createdAt'],
      ];
    }).toList(growable: false);
    final evidenceHash = sha256Hex(canonicalJson(evidenceRows));
    final sourceCount = evidence
        .map((e) => '${e.record['sourceId'] ?? ''}')
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;
    final evidenceBlockCount = evidence
        .map((e) => '${e.record['blockId'] ?? ''}')
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;
    final currentTruthCount = evidence
        .where(
            (e) => e.table == 'truths' && '${e.record['status']}' == 'CURRENT')
        .length;
    final explicitConflictCount = evidence
        .where((e) =>
            e.table == 'truths' && '${e.record['status']}' == 'CONFLICTING')
        .length;
    final evidenceIds = evidence.map((e) => e.recordId).toSet();
    final hotTruths =
        await db.records('truths', orderBy: 'updated_at DESC', limit: 1200);
    final hotConflictCount = hotTruths.where((truth) {
      if ('${truth['status']}' != 'CONFLICTING') return false;
      if (evidenceIds.contains('${truth['id']}')) return true;
      return ((truth['evidenceAtomIds'] as List?) ?? const [])
          .map((e) => '$e')
          .any(evidenceIds.contains);
    }).length;
    final conflictCount = explicitConflictCount > hotConflictCount
        ? explicitConflictCount
        : hotConflictCount;
    final route = plan.route;
    final id = canonicalId('databox',
        [root, normalizeText(query), projectId, route, evidenceHash]);
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
        j['id'],
        j['type'],
        j['text'],
        j['projectId'],
        j['sourceId'],
        j['conversationId'],
        j['messageId'],
        j['blockId'],
        j['truthStatus'],
        j['sourceStart'],
        j['sourceEnd'],
        j['createdAt'],
      ];
    }).toList(growable: false);
    if (sha256Hex(canonicalJson(evidenceRows)) != box.evidenceHash)
      return false;
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
