import 'package:brain2_ai_miner_mobile/intelligence/truth_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> atom({
  String text = 'The runtime uses the Dart MRS adapter',
  String value = 'the Dart MRS adapter',
  String subject = 'runtime',
  String? scope,
  String polarity = 'NEUTRAL',
  String conversationId = 'c1',
}) =>
    <String, Object?>{
      'id': 'a1',
      'projectId': 'p1',
      'conversationId': conversationId,
      'kind': 'fact',
      'text': text,
      'subject': subject,
      'canonicalSubject': subject,
      'value': value,
      'scope': scope,
      'polarity': polarity,
      'keywords': truthTerms('$subject $value').toList(),
      'ruleTrace': <String>['strict_truth:explicit_project_config'],
    };

Map<String, Object?> truth({
  String text = 'The runtime uses the browser adapter',
  String value = 'the browser adapter',
  String subject = 'runtime',
  String? scope,
  String polarity = 'NEUTRAL',
  String status = 'CURRENT',
  String conversationId = 'c1',
}) =>
    <String, Object?>{
      'id': 't1',
      'projectId': 'p1',
      'conversationId': conversationId,
      'kind': 'fact',
      'text': text,
      'canonicalSubject': subject,
      'value': value,
      'scope': scope,
      'polarity': polarity,
      'status': status,
      'keywords': truthTerms('$subject $value').toList(),
      'strictTruthRule': 'strict_truth:explicit_project_config',
    };

void main() {
  test('conflicting values do not silently replace Current Truth', () {
    expect(relationForAtomAndTruth(atom(), truth()), 'CONTRADICTS');
  });

  test('explicit update supersedes conflicting value', () {
    expect(
      relationForAtomAndTruth(
        atom(text: 'Going forward the runtime uses the Dart MRS adapter'),
        truth(),
      ),
      'SUPERSEDES',
    );
  });

  test('same subject in different scope remains independently current', () {
    expect(
      relationForAtomAndTruth(
        atom(scope: 'mobile'),
        truth(scope: 'web'),
      ),
      'DIFFERENT_SCOPE',
    );
  });

  test('speculative atom stays uncertain unless it is an explicit update', () {
    expect(
      relationForAtomAndTruth(
        atom(text: 'Maybe the runtime uses the Dart MRS adapter'),
        truth(value: 'the Dart MRS adapter'),
      ),
      'UNCERTAIN',
    );
  });

  test('strict qa/config truth families require exact canonical subject', () {
    final qaAtom = atom(subject: 'storage choice')
      ..['ruleTrace'] = <String>['strict_truth:explicit_qa_selection'];
    final qaTruth = truth(subject: 'runtime choice')
      ..['strictTruthRule'] = 'strict_truth:explicit_qa_selection';

    expect(strictFamilyCompatible(qaAtom, qaTruth), isFalse);
  });
}
