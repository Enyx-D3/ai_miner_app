import '../core/identity.dart';

final RegExp _updateCue = RegExp(
  r"\b(now|going forward|from now on|replace(?:d)?|instead|switch(?:ed)?|changed? to|set to|updated? to|no longer|we(?:'ll| will) use|we decided|final(?:ly)?|canonical)\b",
  caseSensitive: false,
);

final RegExp _speculativeCue = RegExp(
  r'\b(maybe|perhaps|might|could|should|consider|possibly|in some cases?)\b',
  caseSensitive: false,
);

Set<String> truthTerms(String value) => normalizeText(value)
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((term) => term.length >= 3)
    .toSet();

double truthOverlap(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  return a.intersection(b).length / a.union(b).length;
}

double _tokenOverlap(Iterable<String> a, Iterable<String> b) {
  final aa = a
      .map((e) => normalizeText(e).toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  final bb = b
      .map((e) => normalizeText(e).toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  if (aa.isEmpty || bb.isEmpty) return 0;
  return aa.intersection(bb).length / aa.length;
}

String _normalizedValue(Map<String, Object?> record) =>
    normalizeText('${record['value'] ?? ''}').toLowerCase();

Set<String> _subjectTerms(Map<String, Object?> record) => truthTerms(
      '${record['canonicalSubject'] ?? record['subject'] ?? record['text'] ?? ''}',
    );

Set<String> _keywords(Map<String, Object?> record) =>
    ((record['keywords'] as List?) ?? const [])
        .map((e) => normalizeText('$e').toLowerCase())
        .where((e) => e.length >= 3)
        .toSet();

double _textSimilarity(String a, String b) => truthOverlap(
    truthTerms(a).take(18).toSet(), truthTerms(b).take(18).toSet());

String _valueRelationship(String a, String b) {
  if (a == b) return 'SAME';
  if (a.contains(b) || b.contains(a)) return 'REFINES';
  return 'CONFLICTS';
}

String? strictRuleFromRecord(Map<String, Object?> record) {
  final explicit = '${record['strictTruthRule'] ?? ''}';
  if (explicit.startsWith('strict_truth:')) {
    return explicit.replaceFirst('strict_truth:', '');
  }
  final trace = ((record['ruleTrace'] as List?) ?? const []).map((e) => '$e');
  for (final item in trace) {
    if (item.startsWith('strict_truth:') &&
        item != 'strict_truth:eligible' &&
        item != 'strict_truth:residual') {
      return item.replaceFirst('strict_truth:', '');
    }
  }
  final root = '${record['strictTruthRootKey'] ?? ''}';
  if (root.contains(':')) return root.split(':').first;
  return null;
}

bool strictFamilyCompatible(
  Map<String, Object?> atom,
  Map<String, Object?> truth,
) {
  final atomRule = strictRuleFromRecord(atom);
  final truthRule = strictRuleFromRecord(truth);
  final atomSubject =
      normalizeText('${atom['canonicalSubject'] ?? atom['subject'] ?? ''}')
          .toLowerCase();
  final truthSubject =
      normalizeText('${truth['canonicalSubject'] ?? ''}').toLowerCase();
  if ((atomRule == 'explicit_qa_selection' ||
          truthRule == 'explicit_qa_selection') &&
      atomSubject != truthSubject) {
    return false;
  }
  if ((atomRule == 'corroborated_exact_config' ||
          truthRule == 'corroborated_exact_config') &&
      atomSubject != truthSubject) {
    return false;
  }
  return true;
}

String strictTruthRootKeyForAtom(Map<String, Object?> atom) {
  final rule = strictRuleFromRecord(atom) ?? 'legacy';
  final subject =
      normalizeText('${atom['canonicalSubject'] ?? atom['subject'] ?? ''}')
          .toLowerCase();
  final value = _normalizedValue(atom);
  final polarity = '${atom['polarity'] ?? 'NEUTRAL'}';
  final scope = normalizeText('${atom['scope'] ?? ''}').toLowerCase();
  return '$rule:${atom['kind']}:$subject:$value:$polarity:$scope';
}

String relationForAtomAndTruth(
  Map<String, Object?> atom,
  Map<String, Object?> current,
) {
  final atomConversation = '${atom['conversationId'] ?? ''}';
  final truthConversation = '${current['conversationId'] ?? ''}';
  if (atomConversation.isNotEmpty &&
      truthConversation.isNotEmpty &&
      atomConversation != truthConversation) {
    return 'UNCERTAIN';
  }

  final atomText = normalizeText('${atom['text'] ?? ''}').toLowerCase();
  final truthText = normalizeText('${current['text'] ?? ''}').toLowerCase();
  if (atomText == truthText) return 'SAME';

  final subject = [
    truthOverlap(_subjectTerms(atom), _subjectTerms(current)),
    _tokenOverlap(_keywords(atom).take(6), truthTerms(truthText).take(10)),
  ].reduce((a, b) => a > b ? a : b);
  if (subject < .32) return 'UNCERTAIN';

  final atomScope = normalizeText('${atom['scope'] ?? ''}').toLowerCase();
  final truthScope = normalizeText('${current['scope'] ?? ''}').toLowerCase();
  if ((atomScope.isNotEmpty || truthScope.isNotEmpty) &&
      atomScope != truthScope) {
    return 'DIFFERENT_SCOPE';
  }

  final similarity = _textSimilarity(atomText, truthText);
  final atomValue = _normalizedValue(atom);
  final truthValue = _normalizedValue(current);
  final valueRelation = atomValue.isNotEmpty && truthValue.isNotEmpty
      ? _valueRelationship(atomValue, truthValue)
      : null;
  final oppositePolarity = '${atom['polarity'] ?? 'NEUTRAL'}' != 'NEUTRAL' &&
      '${current['polarity'] ?? 'NEUTRAL'}' != 'NEUTRAL' &&
      '${atom['polarity']}' != '${current['polarity']}';
  final explicitUpdate = _updateCue.hasMatch(atomText);
  final speculative = _speculativeCue.hasMatch(atomText);

  if (speculative && !explicitUpdate) return 'UNCERTAIN';
  if (oppositePolarity) return explicitUpdate ? 'SUPERSEDES' : 'CONTRADICTS';
  if (valueRelation == 'CONFLICTS') {
    return explicitUpdate ? 'SUPERSEDES' : 'CONTRADICTS';
  }
  if (valueRelation == 'REFINES' && subject >= .45) {
    return explicitUpdate ? 'SUPERSEDES' : 'REFINES';
  }
  if (explicitUpdate && subject >= .45) return 'SUPERSEDES';
  if (similarity >= .82) return 'SAME';
  if ((atomText.contains(truthText) || similarity >= .58) &&
      atomText.length > truthText.length) {
    return 'REFINES';
  }
  return 'UNCERTAIN';
}
