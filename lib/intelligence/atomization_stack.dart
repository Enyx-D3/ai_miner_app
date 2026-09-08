import '../core/identity.dart';

const String atomizationStackVersion = 'B2_ATOM_STACK_G_F_I_B250_V1';
const int b250TokenCap = 250;
const double iStyleSufficiencyThreshold = 0.72;

class AtomContextSufficiency {
  final double score;
  final String state;
  final double queryCoverage;
  final int evidenceCount;
  final List<String> reasons;
  const AtomContextSufficiency(this.score, this.state, this.queryCoverage,
      this.evidenceCount, this.reasons);
}

Map<String, Object?> buildB250LocalChunk(String text,
    {int anchorStart = 0, int? anchorEnd, int cap = b250TokenCap}) {
  final cleaned = normalizeText(text);
  if (cleaned.isEmpty)
    return {'text': '', 'sourceStart': 0, 'sourceEnd': 0, 'tokenCount': 0};
  final matches = RegExp(r'\S+').allMatches(cleaned).toList();
  if (matches.length <= cap)
    return {
      'text': cleaned,
      'sourceStart': 0,
      'sourceEnd': cleaned.length,
      'tokenCount': matches.length
    };
  final end = anchorEnd ?? anchorStart;
  final anchor =
      ((anchorStart + end) / 2).floor().clamp(0, cleaned.length).toInt();
  var center = matches.indexWhere((m) => m.start <= anchor && m.end >= anchor);
  if (center < 0) {
    center = matches.indexWhere((m) => m.start >= anchor);
    if (center < 0) center = matches.length - 1;
  }
  var left = (center - (cap ~/ 2)).clamp(0, matches.length - 1).toInt();
  var right = (left + cap).clamp(1, matches.length).toInt();
  left = (right - cap).clamp(0, matches.length - 1).toInt();
  final sourceStart = matches[left].start, sourceEnd = matches[right - 1].end;
  return {
    'text': cleaned.substring(sourceStart, sourceEnd),
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'tokenCount': right - left
  };
}

double intrinsicAtomSufficiency(String text, String subject,
    {String? value, bool relationSafe = true}) {
  final words = RegExp(r'\S+').allMatches(text).length;
  var score = 0.42;
  if (normalizeText(subject).length >= 3) score += 0.16;
  if (value != null && value.trim().isNotEmpty) score += 0.12;
  if (words >= 6) score += 0.08;
  if (words >= 12) score += 0.06;
  if (relationSafe) score += 0.08;
  if (RegExp(
          r'\b(if|unless|because|therefore|due to|step|first|then|finally)\b',
          caseSensitive: false)
      .hasMatch(text)) score += 0.04;
  if (words < 4) score -= 0.2;
  return score.clamp(0, 1).toDouble();
}

AtomContextSufficiency assessAtomContextSufficiency(
    String query, List<Map<String, Object?>> evidence) {
  final qTerms = normalizeText(query)
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true))
      .where((t) => t.length >= 2)
      .toSet()
      .take(32)
      .toList();
  final covered = <String>{};
  for (final item in evidence.take(12)) {
    final text =
        normalizeText('${item['text'] ?? item['content'] ?? ''}').toLowerCase();
    for (final term in qTerms) if (text.contains(term)) covered.add(term);
  }
  final coverage = qTerms.isEmpty ? 1.0 : covered.length / qTerms.length;
  final count = evidence.length;
  final currentTruth = evidence.any(
      (e) => '${e['type']}' == 'truth' && '${e['truthStatus']}' == 'CURRENT');
  final conflict = evidence.any((e) =>
      '${e['truthStatus']}' == 'CONFLICTING' ||
      '${e['truthStatus']}' == 'PENDING_REVIEW');
  var semantic = 0.0;
  final top = evidence.take(4).toList();
  for (final e in top) {
    semantic += (e['intrinsicSufficiency'] as num?)?.toDouble() ??
        (e['confidence'] as num?)?.toDouble() ??
        (((e['score'] as num?)?.toDouble() ?? 0) / 6).clamp(0, 1);
  }
  if (top.isNotEmpty) semantic /= top.length;
  var score = (coverage * 0.46 +
          semantic * 0.28 +
          (count / 4).clamp(0, 1) * 0.14 +
          (currentTruth ? 0.08 : 0) +
          (evidence.isNotEmpty &&
                  ((evidence.first['score'] as num?)?.toDouble() ?? 0) >= 4
              ? 0.08
              : 0) -
          (conflict ? 0.08 : 0))
      .clamp(0, 1)
      .toDouble();
  final reasons = <String>[];
  if (coverage < 0.67) reasons.add('query_terms_undercovered');
  if (count < 2) reasons.add('too_few_atom_evidence_units');
  if (semantic < 0.65) reasons.add('atom_context_thin');
  if (conflict) reasons.add('conflict_requires_local_context');
  if (currentTruth) reasons.add('current_truth_present');
  final state = score >= iStyleSufficiencyThreshold
      ? 'SUFFICIENT'
      : score >= 0.5
          ? 'AMBIGUOUS'
          : 'INSUFFICIENT';
  return AtomContextSufficiency(score, state, coverage, count, reasons);
}
