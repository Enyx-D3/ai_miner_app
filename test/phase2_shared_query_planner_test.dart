import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/intelligence/shared_query_planner.dart';
import 'package:brain2_ai_miner_mobile/intelligence/continuity_intelligence.dart';

void main() {
  test('Phase 2 shared query planner vectors and hashes', () {
    final vectors = <(String, int, String, String, String, String)>[
      (
        'receipt: abcdef123456',
        1,
        'EXACT',
        'FAST',
        'B_250_CHUNK',
        '154fbc413bc7bd12c4351896f40cfc36486ccab540b71791e09aa1903c6a1121'
      ),
      (
        'what is the current status now?',
        1,
        'TEMPORAL',
        'STANDARD',
        'F_TEMPORAL_TRUTH',
        'cfb2de2193f81ac958e3806a7470a2728211fb338a2ed724d2b8d0cdf7f72fea'
      ),
      (
        'what are we using now?',
        1,
        'TEMPORAL',
        'STANDARD',
        'F_TEMPORAL_TRUTH',
        'a5997b2f2b082ac539b4fa0fc5e730e44013ac01164bec5aaced0c2d355dbd97'
      ),
      (
        'find the contradiction between these decisions',
        1,
        'CONTRADICTION',
        'STANDARD',
        'F_TEMPORAL_TRUTH',
        '7e21f30073eb278ca6ff10300df9c307113b5798992634c640cdca4ca5d5eb58'
      ),
      (
        'why did this fail and what repair worked?',
        1,
        'FAILURE',
        'STANDARD',
        'G_ADAPTIVE_HETEROGENEOUS',
        '89c50b84de943790cd83bd6edd9423e354201b533b7809e974f5fa01442f93f4'
      ),
      (
        'why does this module depend on the router?',
        1,
        'SEMANTIC',
        'STANDARD',
        'G_ADAPTIVE_HETEROGENEOUS',
        'b97189fc0cce6ae6ea572d0d3ea7ca6ebc381b36e80e28b9a4f87e814ab591a2'
      ),
      (
        'explain the memory architecture',
        1,
        'SEMANTIC',
        'FAST',
        'B_250_CHUNK',
        '45114cd9bdb1e9323cde219ec377cbfc8a8dfb1393c0b34209ba54aefe7a6bf3'
      ),
      (
        'deep archaeology trace back the full lineage',
        1,
        'GENEALOGY_ARCHAEOLOGY',
        'DEEP',
        'G_ADAPTIVE_HETEROGENEOUS',
        'a88347173c462dc65276ab5b51a96d877af81f4028ccd8e1cb1e0323cebd5e13'
      ),
      (
        'deep search implementation history',
        1,
        'GENEALOGY_ARCHAEOLOGY',
        'DEEP',
        'G_ADAPTIVE_HETEROGENEOUS',
        '10f1c10c5917280ec5704b7b203d5fb8033978371ef02f991412ecf536fc08ce'
      ),
      (
        'compare across projects',
        2,
        'MULTI_PROJECT',
        'STANDARD',
        'G_ADAPTIVE_HETEROGENEOUS',
        '058b52514817e5c07f5faa44e8529308ce15bade697dc0d4a35b7797400ed59d'
      ),
    ];
    for (final v in vectors) {
      final p = planSharedQuery(v.$1, projectCount: v.$2);
      expect(p.queryClassWire, v.$3);
      expect(p.modeWire, v.$4);
      expect(p.route, v.$5);
      expect(hashSharedQueryPlan(p), v.$6);
    }
  });
  test('Phase 2 continuity source hash parity vector', () {
    final hash = hashContinuitySourceState(
      projectId: 'p',
      goalText: 'Ship continuity',
      atoms: [
        {
          'id': 'a',
          'projectId': 'p',
          'kind': 'task',
          'text': 'Ship continuity',
          'createdAt': '2026-10-03'
        }
      ],
      truths: [
        {
          'id': 't',
          'projectId': 'p',
          'kind': 'task',
          'text': 'Ship continuity',
          'status': 'CURRENT',
          'updatedAt': '2026-10-03'
        }
      ],
      ticks: [
        {
          'id': 'k',
          'projectId': 'p',
          'title': 'Approve',
          'detail': 'Human approval',
          'status': 'OPEN',
          'actionType': 'APPROVE'
        }
      ],
      failures: [
        {
          'id': 'f',
          'projectId': 'p',
          'title': 'Old failure',
          'cause': 'Bad route',
          'lastSeenAt': '2026-10-02'
        }
      ],
    );
    expect(hash,
        '802148b176c8e2496bd1a17e329eb4875d4293634cb5c37a89e83ab199d7d865');
    expect(continuityStableId('goal', ['p', 'Ship continuity']),
        'goal_2f0bd589d83e0c366a21fa65');
    expect(continuityStableId('check', ['p', 'TICK', 'k']),
        'check_2b155c9e94d40cdb160c6e67');
    final stateHash = hashContinuityStateMaterial({
      'format': 'B2_CONTINUITY',
      'version': 1,
      'kind': 'CONTINUITY_INTELLIGENCE',
      'projectId': 'p',
      'sourceHash': hash,
      'goal': {
        'id': 'goal_2f0bd589d83e0c366a21fa65',
        'text': 'Ship continuity',
        'evidenceAtomIds': ['a']
      },
      'checklist': [
        {
          'id': 'check_2b155c9e94d40cdb160c6e67',
          'projectId': 'p',
          'goalId': 'goal_2f0bd589d83e0c366a21fa65',
          'sourceType': 'TICK',
          'sourceRefId': 'k',
          'title': 'Approve: Human approval',
          'status': 'GATE',
          'evidenceAtomIds': ['a'],
          'verificationIds': [],
          'authorizationRefs': [],
          'blockedByIds': [],
          'updatedAt': 'IGNORED'
        },
        {
          'id': 'check_504956e09d241db1f358a685',
          'projectId': 'p',
          'goalId': 'goal_2f0bd589d83e0c366a21fa65',
          'sourceType': 'ATOM',
          'sourceRefId': 'a',
          'title': 'Ship continuity',
          'status': 'OPEN',
          'evidenceAtomIds': ['m'],
          'verificationIds': [],
          'authorizationRefs': [],
          'blockedByIds': [],
          'updatedAt': 'IGNORED'
        },
      ],
      'avoidedWorkLedger': [],
      'recap': {
        'currentTruthCount': 1,
        'open': 1,
        'blocked': 0,
        'gates': 1,
        'done': 0,
        'unknown': 0,
        'knownFailureCount': 1,
        'recentChangeCount': 0
      },
      'prescription': [
        'Resolve human gate: Approve: Human approval',
        'Continue: Ship continuity'
      ],
      'plannerVersion': 'B2_QUERY_PLANNER_V1',
    });
    expect(stateHash,
        'f1b3f45e8f99c489032ce8a89caae5cc1f3a964593230da9f2435e0215141bf3');
  });
}
