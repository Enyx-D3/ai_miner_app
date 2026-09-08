import 'package:brain2_ai_miner_mobile/intelligence/intelligence_layer.dart';
import 'package:brain2_ai_miner_mobile/storage/brain2_database.dart';
import 'package:flutter_test/flutter_test.dart';

const now = '2026-09-07T00:00:00.000Z';

Map<String, Object?> atom({
  required String id,
  String projectId = 'p1',
  String kind = 'fact',
  required String text,
  String? subject,
  String? value,
  String? truthStatus,
  List<String>? keywords,
  List<String>? ruleTrace,
  double confidence = .9,
}) =>
    <String, Object?>{
      'id': id,
      'projectId': projectId,
      'kind': kind,
      'text': text,
      'subject': subject ?? text.split(' ').take(3).join(' '),
      'canonicalSubject':
          (subject ?? text.split(' ').take(3).join(' ')).toLowerCase(),
      'value': value,
      'truthStatus': truthStatus,
      'keywords': keywords ?? text.toLowerCase().split(' ').take(7).toList(),
      'ruleTrace': ruleTrace ?? const <String>[],
      'confidence': confidence,
      'createdAt': now,
    };

Map<String, Object?> truth({
  required String id,
  String projectId = 'p1',
  String status = 'CURRENT',
  String kind = 'fact',
  required String text,
  String? subject,
  String? value,
  List<String>? evidenceAtomIds,
  double confidence = .92,
}) =>
    <String, Object?>{
      'id': id,
      'projectId': projectId,
      'status': status,
      'kind': kind,
      'text': text,
      'canonicalSubject': subject ?? text.split(' ').take(3).join(' '),
      'value': value,
      'evidenceAtomIds': evidenceAtomIds ?? const <String>[],
      'confidence': confidence,
      'updatedAt': now,
    };

MobileIntelligenceLayer layer() => MobileIntelligenceLayer(Brain2Database());

Map<String, Object?> projection({
  List<Map<String, Object?>> atoms = const [],
  List<Map<String, Object?>> truths = const [],
  List<Map<String, Object?>> patterns = const [],
}) =>
    layer().buildProjectIntelligenceProjection(
      project: const <String, Object?>{
        'id': 'p1',
        'name': 'Brain2 Mobile',
        'updatedAt': now,
      },
      atoms: atoms,
      truthRows: truths,
      patterns: patterns,
    );

List<Map<String, Object?>> list(Map<String, Object?> p, String key) =>
    ((p[key] as List?) ?? const []).cast<Map<String, Object?>>();

void main() {
  test('empty project produces no-evidence deterministic snapshot', () {
    final p = projection();

    expect(p['version'], brain2IntelligenceVersion);
    expect(p['ruleVersion'], brain2ProjectIntelligenceRuleVersion);
    expect(p['mrsRuntime'], 'NOT_REQUIRED');
    expect(list(p, 'currentTruth'), isEmpty);
    expect(list(p, 'importantIdeas'), isEmpty);
    expect(list(p, 'openQuestions'), isEmpty);
  });

  test('current grounded truth and obvious decision become important findings',
      () {
    final p = projection(
      atoms: [
        atom(
          id: 'a_truth',
          text: 'Runtime uses mobile MRS.',
          subject: 'Runtime',
          value: 'mobile MRS',
          truthStatus: 'CURRENT',
        ),
        atom(
          id: 'a_decision',
          kind: 'decision',
          text: 'We decided mobile import must preserve SQLite storage.',
          subject: 'mobile import',
          value: 'preserve SQLite storage',
          ruleTrace: const [
            'strict_truth:explicit_first_person_requirement',
            'strict_truth:eligible',
          ],
        ),
      ],
      truths: [
        truth(
          id: 't_runtime',
          text: 'Runtime uses mobile MRS.',
          subject: 'Runtime',
          value: 'mobile MRS',
          evidenceAtomIds: const ['a_truth'],
        ),
      ],
    );

    expect(list(p, 'currentTruth').single['statement'],
        'Current truth: Runtime is mobile MRS.');
    expect(list(p, 'importantIdeas').single['statement'],
        'Decision: Mobile import is preserve SQLite storage.');
    expect(list(p, 'importantIdeas').single['verification'],
        'DETERMINISTIC_VERIFIED');
  });

  test('duplicates current truth and request-like/user junk are rejected', () {
    final p = projection(
      atoms: [
        atom(
          id: 'a_current_duplicate',
          text: 'Runtime uses mobile MRS.',
          subject: 'Runtime',
          value: 'mobile MRS',
          truthStatus: 'CURRENT',
        ),
        atom(
          id: 'a_request',
          text: 'Please write a long article on mobile mining.',
          kind: 'idea',
          confidence: .99,
        ),
        atom(
          id: 'a_junk',
          text: 'Brain2 AI runtime model download progress',
          kind: 'idea',
          confidence: .99,
        ),
      ],
      truths: [
        truth(
          id: 't_runtime',
          text: 'Runtime uses mobile MRS.',
          subject: 'Runtime',
          value: 'mobile MRS',
          evidenceAtomIds: const ['a_current_duplicate'],
        ),
      ],
    );

    final statements =
        list(p, 'importantIdeas').map((item) => '${item['statement']}');
    expect(statements, isNot(contains('Runtime uses mobile MRS.')));
    expect(statements,
        isNot(contains('Please write a long article on mobile mining.')));
    expect(statements,
        isNot(contains('Brain2 AI runtime model download progress')));
  });

  test('novel grounded MRS candidate is exposed as unresolved novelty', () {
    final p = projection(
      atoms: [
        atom(
          id: 'a_novel',
          kind: 'idea',
          text: 'Vector lane failure budget is 42.',
          subject: 'Vector lane failure budget',
          value: '42',
          keywords: const ['vector', 'lane', 'failure', 'budget', 'forty'],
          confidence: .96,
        ),
      ],
    );

    expect(list(p, 'importantIdeas').single['verification'], 'MRS_PENDING');
    expect(list(p, 'unresolved').single['id'],
        list(p, 'importantIdeas').single['id']);
    expect(list(p, 'novelty').single['statement'],
        'Vector lane failure budget is 42.');
    expect(p['mrsRuntime'], 'DEFERRED');
  });

  test('changed, conflicting, and uncertain truths become change artifacts',
      () {
    final p = projection(
      atoms: [
        atom(id: 'a_old', text: 'Backend uses browser WASM.'),
        atom(id: 'a_conflict', text: 'Backend uses native MRS.'),
        atom(id: 'a_uncertain', text: 'Backend could use both paths.'),
      ],
      truths: [
        truth(
          id: 't_old',
          status: 'SUPERSEDED',
          text: 'Backend uses browser WASM.',
          subject: 'Backend',
          value: 'browser WASM',
          evidenceAtomIds: const ['a_old'],
        ),
        truth(
          id: 't_conflict',
          status: 'CONFLICTING',
          text: 'Backend uses native MRS.',
          subject: 'Backend',
          value: 'native MRS',
          evidenceAtomIds: const ['a_conflict'],
        ),
        truth(
          id: 't_uncertain',
          status: 'PENDING_REVIEW',
          text: 'Backend could use both paths.',
          subject: 'Backend',
          value: 'both paths',
          evidenceAtomIds: const ['a_uncertain'],
        ),
      ],
    );

    expect(
      list(p, 'changes').map((item) => '${item['title']}').toSet(),
      containsAll(
          const ['Superseded state', 'Conflict detected', 'Unresolved change']),
    );
  });

  test('open questions and pattern connections are project scoped', () {
    final p = projection(
      atoms: [
        atom(
          id: 'a_question',
          kind: 'question',
          text: 'Which evidence block should seed project resolver tests?',
        ),
        atom(
          id: 'a_p2',
          projectId: 'p2',
          kind: 'decision',
          text: 'We decided another project uses another engine.',
          ruleTrace: const [
            'strict_truth:explicit_first_person_requirement',
            'strict_truth:eligible',
          ],
        ),
      ],
      truths: [
        truth(
          id: 't_p2',
          projectId: 'p2',
          text: 'Another project uses another engine.',
          value: 'another engine',
        ),
      ],
      patterns: const [
        <String, Object?>{
          'id': 'pat1',
          'projectIds': ['p1'],
          'status': 'VERIFIED',
          'strength': .8,
          'evidenceCount': 5,
          'counterexamples': 0,
          'label': 'Resolver evidence blocks',
          'atomIds': ['a_question'],
          'updatedAt': now,
        },
        <String, Object?>{
          'id': 'pat2',
          'projectIds': ['p2'],
          'status': 'VERIFIED',
          'strength': .99,
          'evidenceCount': 5,
          'counterexamples': 0,
          'label': 'Wrong project',
          'atomIds': ['a_p2'],
          'updatedAt': now,
        },
      ],
    );

    expect(list(p, 'openQuestions').single['statement'],
        'Which evidence block should seed project resolver tests?');
    expect(
        list(p, 'connections').single['statement'], 'Resolver evidence blocks');
    expect('${p['sourceVersion']}', isNotEmpty);
  });
}
