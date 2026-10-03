import 'dart:convert';

import '../asif/asif_reader_core.dart';
import '../core/contracts.dart';
import '../core/identity.dart';
import '../core/r1_authority.dart';
import '../jobs/b2_job_service.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class ResultReturnState {
  final String resultTransactionId;
  final String verificationTransactionId;
  final String? tickId;
  final String? projectId;
  final String status;
  final String detail;
  const ResultReturnState(
      {required this.resultTransactionId,
      required this.verificationTransactionId,
      required this.status,
      required this.detail,
      this.tickId,
      this.projectId});
}

class ResultReturnService {
  final Brain2Database db;
  final MutationService mutations;
  final AsifReaderCore reader;
  const ResultReturnService(this.db, this.mutations, this.reader);

  Future<Map<String, Object?>?> _job(String jobId) async {
    final txs = await db.records('transactions',
        orderBy: 'updated_at DESC', limit: 1600);
    for (final tx in txs) {
      if ('${tx['type']}' != 'B2JOB') continue;
      try {
        final decoded =
            (jsonDecode('${tx['payload']}') as Map).cast<String, Object?>();
        if ('${decoded['id']}' == jobId) return decoded;
      } catch (_) {}
    }
    return null;
  }

  Future<ResultReturnState> importAndVerify(Map<String, Object?> result) async {
    final verification =
        await B2JobService(db, mutations, reader).verifyResult(result);
    final now = DateTime.now().toUtc().toIso8601String();
    final jobId = '${result['jobId'] ?? ''}';
    final job = await _job(jobId);
    final projectId = '${job?['projectId'] ?? ''}';
    final resultHash = sha256Hex(canonicalJson(result));
    final resultTxId = canonicalId('b2result', [jobId, resultHash]);
    await mutations.upsert(
        'transactions',
        {
          'id': resultTxId,
          'type': 'B2RESULT',
          if (projectId.isNotEmpty) 'projectId': projectId,
          'payload': jsonEncode(result),
          'createdAt': now,
          'updatedAt': now,
          'hash': resultHash,
          'schemaVersion': brain2SchemaVersion
        },
        type: 'RESULT_RETURN_B2RESULT');
    final verifyPayload = <String, Object?>{
      'format': 'B2VERIFY',
      'version': 1,
      'resultTransactionId': resultTxId,
      'jobId': jobId,
      if (projectId.isNotEmpty) 'projectId': projectId,
      ...verification.toJson(),
      'verifiedAt': now,
      'writePolicy': 'PROPOSE_THEN_VERIFY'
    };
    final verifyId = canonicalId('b2verify',
        [resultTxId, verification.status, hashEntity(verifyPayload)]);
    await mutations.upsert(
        'transactions',
        {
          'id': verifyId,
          'type': 'B2VERIFY',
          if (projectId.isNotEmpty) 'projectId': projectId,
          'payload': jsonEncode(verifyPayload),
          'createdAt': now,
          'updatedAt': now,
          'hash': sha256Hex(canonicalJson(verifyPayload)),
          'schemaVersion': brain2SchemaVersion
        },
        type: 'RESULT_RETURN_VERIFY');
    final tickId =
        canonicalId('tick', [projectId, 'result-return', resultTxId]);
    final pass = verification.status == 'PASS';
    await mutations.upsert(
        'ticks',
        {
          'id': tickId,
          if (projectId.isNotEmpty) 'projectId': projectId,
          'title':
              pass ? 'Review verified AI result' : 'Repair returned AI result',
          'detail': pass
              ? 'Provenance passed. Review before adding this answer back to project memory. Approval stores an observation, not Current Truth.'
              : '${verification.detail} Repair or regenerate from the canonical B2JOB.',
          'status': 'OPEN',
          'priority': pass ? 'MEDIUM' : 'HIGH',
          'actionType': pass ? 'RESULT' : 'VERIFY',
          'createdAt': now,
          'updatedAt': now,
          'evidenceAtomIds': ((result['evidenceIds'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
          'blockingScope': ['result-return:$resultTxId'],
          'schemaVersion': brain2SchemaVersion
        },
        type: pass
            ? 'RESULT_RETURN_REQUIRE_USER'
            : 'RESULT_RETURN_REPAIR_REQUIRED');
    if (!pass) {
      final repair = <String, Object?>{
        'format': 'B2REPAIR',
        'version': 1,
        'resultTransactionId': resultTxId,
        'verificationTransactionId': verifyId,
        'detail': verification.detail,
        'missingEvidenceIds': verification.missingEvidenceIds,
        'outsideJobEvidenceIds': verification.outsideJobEvidenceIds,
        'createdAt': now
      };
      await mutations.upsert(
          'transactions',
          {
            'id': canonicalId('b2repair', [resultTxId, hashEntity(repair)]),
            'type': 'B2REPAIR',
            if (projectId.isNotEmpty) 'projectId': projectId,
            'payload': jsonEncode(repair),
            'createdAt': now,
            'updatedAt': now,
            'hash': sha256Hex(canonicalJson(repair)),
            'schemaVersion': brain2SchemaVersion
          },
          type: 'RESULT_RETURN_REPAIR');
    }
    return ResultReturnState(
        resultTransactionId: resultTxId,
        verificationTransactionId: verifyId,
        tickId: tickId,
        projectId: projectId.isEmpty ? null : projectId,
        status: verification.status,
        detail: verification.detail);
  }

  Future<String> approveVerifiedResult(String resultTransactionId) async {
    final tx = await db.getRecord('transactions', resultTransactionId);
    if (tx == null || '${tx['type']}' != 'B2RESULT') {
      throw StateError('B2RESULT transaction not found.');
    }
    final result =
        (jsonDecode('${tx['payload']}') as Map).cast<String, Object?>();
    final verification =
        await B2JobService(db, mutations, reader).verifyResult(result);
    if (verification.status != 'PASS') {
      throw StateError('Only provenance-PASS B2RESULT can be accepted.');
    }
    final job = await _job('${result['jobId'] ?? ''}');
    final projectId = '${job?['projectId'] ?? tx['projectId'] ?? ''}';
    if (projectId.isEmpty) throw StateError('Result has no canonical project.');
    final project = await db.getRecord('projects', projectId);
    if (project == null) throw StateError('Canonical project not found.');
    final answer = normalizeText('${result['answer'] ?? ''}');
    if (answer.isEmpty) throw StateError('B2RESULT answer is empty.');
    final evidence = ((result['evidenceIds'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final r1 = requireR1Allow(
        issueUserR1Allow(
            action: 'RESULT_RETURN_ACCEPT',
            scope: resultTransactionId,
            reason: 'User approved a structurally verified returned result.',
            evidenceRefs: [resultTransactionId, ...evidence]),
        action: 'RESULT_RETURN_ACCEPT',
        scope: resultTransactionId);
    final now = DateTime.now().toUtc().toIso8601String();
    final sourceId = canonicalId('src', ['global-context', 'result-return']);
    final conversationId = canonicalId('conv', ['result-return', projectId]);
    final messageId =
        canonicalId('msg', ['result-return', resultTransactionId]);
    final atomId =
        canonicalId('atom', ['result-return', resultTransactionId, answer]);
    final source = <String, Object?>{
      'id': sourceId,
      'provider': 'generic',
      'label': 'Verified Result Return',
      'sourceType': 'result-return',
      'createdAt': now,
      'lastSeenAt': now,
      'schemaVersion': brain2SchemaVersion
    };
    final oldConversation = await db.getRecord('conversations', conversationId);
    final message = <String, Object?>{
      'id': messageId,
      'conversationId': conversationId,
      'sourceId': sourceId,
      'provider': 'generic',
      'externalId': resultTransactionId,
      'role': 'tool',
      'text': answer,
      'createdAt': now,
      'occurredAt': now,
      'timestampSource': 'capture',
      'sequence':
          ((oldConversation?['messageCount'] as num?)?.toInt() ?? 0) + 1,
      'hash': sha256Hex(answer),
      'wordCount': answer.split(' ').where((e) => e.isNotEmpty).length,
      'schemaVersion': brain2SchemaVersion
    };
    final conversation = <String, Object?>{
      'id': conversationId,
      'sourceId': sourceId,
      'provider': 'generic',
      'externalId': 'result-return:$projectId',
      'title': 'Verified Result Return - ${project['name']}',
      'createdAt': oldConversation?['createdAt'] ?? now,
      'updatedAt': now,
      'projectId': projectId,
      'messageCount':
          ((oldConversation?['messageCount'] as num?)?.toInt() ?? 0) + 1,
      'wordCount': ((oldConversation?['wordCount'] as num?)?.toInt() ?? 0) +
          (message['wordCount'] as int),
      'schemaVersion': brain2SchemaVersion
    };
    final atom = <String, Object?>{
      'id': atomId,
      'messageId': messageId,
      'conversationId': conversationId,
      'projectId': projectId,
      'sourceId': sourceId,
      'kind': 'statement',
      'text': answer,
      'subject': 'Verified returned result',
      'canonicalSubject': 'result.return.$resultTransactionId',
      'confidence': 1.0,
      'provenance': [...evidence, resultTransactionId],
      'keywords': <String>[],
      'hash': sha256Hex('$resultTransactionId|$answer'),
      'strictTruthBlocked': true,
      'ruleTrace': [
        'result_return:provenance_pass',
        'result_return:r1_allow',
        'result_return:observation_only',
        'strict_truth:residual'
      ],
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion
    };
    final updatedProject = <String, Object?>{
      ...project,
      'updatedAt': now,
      'conversationIds': <String>{
        ...((project['conversationIds'] as List?) ?? const []).map((e) => '$e'),
        conversationId
      }.toList(),
      'atomIds': <String>{
        ...((project['atomIds'] as List?) ?? const []).map((e) => '$e'),
        atomId
      }.toList(),
      'recentAtomIds': [
        atomId,
        ...((project['recentAtomIds'] as List?) ?? const [])
            .map((e) => '$e')
            .where((e) => e != atomId)
            .take(119)
      ],
      'atomCount': ((project['atomCount'] as num?)?.toInt() ??
              ((project['atomIds'] as List?) ?? const []).length) +
          1
    };
    final tickId =
        canonicalId('tick', [projectId, 'result-return', resultTransactionId]);
    final tick = await db.getRecord('ticks', tickId);
    final accepted = <String, Object?>{
      'format': 'B2VERIFY',
      'version': 1,
      'resultTransactionId': resultTransactionId,
      'status': 'PASS',
      'decision': 'ACCEPTED_TO_PROJECT_MEMORY_AS_OBSERVATION',
      'currentTruthPromoted': false,
      'r1Authority': r1.toJson(),
      'acceptedAt': now
    };
    final writes = <String, List<Map<String, Object?>>>{
      'sources': [source],
      'conversations': [conversation],
      'messages': [message],
      'atoms': [atom],
      'projects': [updatedProject],
      'transactions': [
        <String, Object?>{
          'id': canonicalId(
              'b2verify', [resultTransactionId, 'accepted', r1.hash]),
          'type': 'B2VERIFY',
          'projectId': projectId,
          'payload': jsonEncode(accepted),
          'createdAt': now,
          'updatedAt': now,
          'hash': sha256Hex(canonicalJson(accepted)),
          'schemaVersion': brain2SchemaVersion,
        }
      ],
    };
    if (tick != null) {
      writes['ticks'] = [
        <String, Object?>{
          ...tick,
          'status': 'RESOLVED',
          'resolution':
              'Approved after provenance verification. Stored as project observation; Current Truth was not modified.',
          'updatedAt': now,
        }
      ];
    }
    await mutations.upsertBatch(
      writes,
      type: 'RESULT_RETURN_ACCEPTED',
      primaryTable: 'transactions',
      entityType: 'projects',
      entityId: projectId,
    );
    return atomId;
  }
}
