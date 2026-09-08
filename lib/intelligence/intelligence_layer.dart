import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';

const String brain2IntelligenceVersion = 'B2_INTELLIGENCE_V1';
const String brain2ProjectIntelligenceRuleVersion =
    'B2_PROJECT_INTELLIGENCE_SOFT_GATE_V3';

const Set<String> _mrsBlockedRules = <String>{
  'assistant_or_unknown_author',
  'question',
  'code_or_log',
  'labelled_answer',
  'quoted_text',
  'meta_task',
  'chat_task',
  'anaphora',
  'duplicate_claim',
  'transient_observation',
  'speculation',
  'invalid_source',
  'invalid_timestamp',
  'empty_candidate',
};

const Set<String> _deterministicProjectIdeaRules = <String>{
  'explicit_negative_constraint',
  'explicit_first_person_requirement',
  'explicit_preference',
  'deterministic_priority_decision',
  'explicit_architecture_decision',
  'bounded_project_requirement',
  'explicit_project_config',
  'calibrated_short_component_directive',
  'explicit_qa_selection',
  'corroborated_exact_config',
};

class _ScoringContext {
  final Map<String, Map<String, Object?>> atomById;
  final Map<String, int> keywordFrequency;
  final Map<String, double> conceptFrequencyByAtomId;
  final Map<String, double> noveltyByAtomId;

  const _ScoringContext({
    required this.atomById,
    required this.keywordFrequency,
    required this.conceptFrequencyByAtomId,
    required this.noveltyByAtomId,
  });
}

class MobileIntelligenceLayer {
  final Brain2Database db;
  const MobileIntelligenceLayer(this.db);

  double _clamp(double value) => value.clamp(0, 1).toDouble();

  double _recency(Object? value) {
    if (value == null) return .35;
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return .35;
    final days = DateTime.now().toUtc().difference(parsed.toUtc()).inHours / 24;
    return _clamp(1 - days / 730);
  }

  List<String> _terms(String value, {int? limit}) {
    final out = normalizeText(value)
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((term) => term.length >= 3)
        .toSet()
        .toList(growable: false);
    return limit == null ? out : out.take(limit).toList(growable: false);
  }

  String _normalizedValue(Map<String, Object?> record) =>
      normalizeText('${record['value'] ?? ''}').toLowerCase();

  String _normalizeForPromotion(String value) =>
      normalizeText(value).replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _requestLike(String value) {
    final text = _normalizeForPromotion(value);
    return RegExp(
          r'^(?:i need|need |please |can you|could you|would you|help me|make |write |create |generate |give me|tell me|show me|explain |summarize |draft |build )',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(?:for me|more details|full information|long article|article on|document on)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }

  bool _structured(String value) {
    final text = _normalizeForPromotion(value);
    if (text.isEmpty) return false;
    return RegExp(
          r'\b(?:is|are|was|were|has|have|uses|requires|means|contains|supports|blocks|fails|works|equals)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(r'[:=]\s*\S+').hasMatch(text) ||
        RegExp(r'\b\d+(?:\.\d+)?\b').hasMatch(text) ||
        RegExp(
          r'\b(?:current|status|version|limit|budget|error|issue|problem|state|runtime|backend|model)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }

  bool _grounded(
    String text,
    Map<String, Object?> source, {
    int evidenceCount = 0,
  }) {
    if (normalizeText('${source['value'] ?? ''}').isNotEmpty) return true;
    if (normalizeText('${source['scope'] ?? ''}').isNotEmpty) return true;
    if (normalizeText('${source['semanticSubtype'] ?? ''}').isNotEmpty) {
      return true;
    }
    if (evidenceCount >= 2) return true;
    return _structured(text);
  }

  bool _uiJunk(String value) {
    final text = _normalizeForPromotion(value);
    if (text.isEmpty || text.length < 10) return true;
    if (RegExp(r'\bmust be treated as\s+\d+\b', caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    if (RegExp(
          r'\bmust be treated as\s+(?:on|between|ambiguous|true|false)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        text.split(' ').length < 12) {
      return true;
    }
    if (RegExp(r'^```|^`{1,3}\s*$').hasMatch(text)) return true;
    if (RegExp(r'<[^>]+>').hasMatch(text) &&
        RegExp(
          r'\b(?:class|meta-data|android:name|div|span|image|svg|import|export|const)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
      return true;
    }
    if (RegExp(
      r'this block is not supported|browser cache is not available|brain2 mrs could not activate|retry after checking browser network/storage/console|(?:download|restore|enable)\s+local\s+mrs|brain2 ai runtime|model download progress',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    final alpha = text.replaceAll(RegExp(r'[^a-z]', caseSensitive: false), '');
    return alpha.length < 6;
  }

  bool _weakStandalone(
    String value, {
    bool allowStructuredRequest = false,
  }) {
    final text = _normalizeForPromotion(value);
    if (_requestLike(text) && !(allowStructuredRequest && _structured(text))) {
      return true;
    }
    if (text.split(' ').length < 4) return true;
    return RegExp(r'^(?:yes|no|ok|okay|thanks|thank you|done|sure)\b',
            caseSensitive: false)
        .hasMatch(text);
  }

  String? _strictRule(Map<String, Object?> atom) {
    final trace = ((atom['ruleTrace'] as List?) ?? const []).map((e) => '$e');
    for (final item in trace) {
      if (item.startsWith('strict_truth:') &&
          item != 'strict_truth:eligible' &&
          item != 'strict_truth:residual') {
        return item.replaceFirst('strict_truth:', '');
      }
    }
    final explicit = '${atom['strictTruthRule'] ?? ''}';
    return explicit.startsWith('strict_truth:')
        ? explicit.replaceFirst('strict_truth:', '')
        : null;
  }

  bool _strictEligible(Map<String, Object?> atom) =>
      ((atom['ruleTrace'] as List?) ?? const [])
          .map((e) => '$e')
          .contains('strict_truth:eligible');

  bool _projectDirectiveShape(String value) {
    final text = _normalizeForPromotion(value);
    return RegExp(r'\b(i|we)\s+(want|need|prefer|must|should)\b',
                caseSensitive: false)
            .hasMatch(text) ||
        RegExp(
          r"\b(should|must|needs?\s+to|has\s+to|have\s+to|do not|don't|dont|never|without manual|no manual|keep|use|switch|replace|remove|make|move|stay|stick to|preserve|protect|disable|enable)\b",
          caseSensitive: false,
        ).hasMatch(text);
  }

  bool _operationallyThinFact(Map<String, Object?> atom) {
    if ('${atom['kind']}' != 'fact') return false;
    final text = _normalizeForPromotion('${atom['text'] ?? ''}');
    if (RegExp(r'\bversion\b', caseSensitive: false).hasMatch(text)) {
      return true;
    }
    if (RegExp(r'\bstatus\b', caseSensitive: false).hasMatch(text) &&
        !RegExp(r'\b(?:fails|blocks|requires|supports|changed?|updated?)\b',
                caseSensitive: false)
            .hasMatch(text)) {
      return true;
    }
    final keywords = ((atom['keywords'] as List?) ?? const []);
    return normalizeText('${atom['value'] ?? ''}').isNotEmpty &&
        keywords.length <= 3 &&
        !_grounded(text, atom,
            evidenceCount: '${atom['truthStatus']}' == 'CURRENT' ? 2 : 0);
  }

  bool _promotableAtom(Map<String, Object?> atom) {
    final text = normalizeText('${atom['text'] ?? ''}');
    final grounded = _grounded(text, atom,
        evidenceCount: '${atom['truthStatus']}' == 'CURRENT' ? 2 : 0);
    return !_uiJunk(text) &&
        !_weakStandalone(text, allowStructuredRequest: grounded);
  }

  bool _promotableTruth(
    Map<String, Object?> truth,
    _ScoringContext context,
  ) {
    final evidenceAtoms = ((truth['evidenceAtomIds'] as List?) ?? const [])
        .map((id) => context.atomById['$id'])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final sourceAtom = evidenceAtoms.isNotEmpty
        ? evidenceAtoms.first
        : context.atomById['${truth['atomId']}'];
    final text = normalizeText('${truth['text'] ?? ''}');
    final grounded = _grounded(text, sourceAtom ?? truth,
        evidenceCount: evidenceAtoms.length);
    if (_uiJunk(text) ||
        _weakStandalone(text, allowStructuredRequest: grounded)) {
      return false;
    }
    return !evidenceAtoms.any((atom) => !_promotableAtom(atom));
  }

  bool _deterministicProjectIdea(Map<String, Object?> atom) {
    if (_strictRule(atom) == 'assistant_or_unknown_author') return false;
    if (!_promotableAtom(atom)) return false;
    final kind = '${atom['kind']}';
    final rule = _strictRule(atom);
    if (rule != null && _deterministicProjectIdeaRules.contains(rule)) {
      return true;
    }
    if (_strictEligible(atom) &&
        const {'decision', 'constraint', 'fact'}.contains(kind)) {
      return true;
    }
    if (kind == 'idea' && _projectDirectiveShape('${atom['text'] ?? ''}')) {
      return true;
    }
    final residual = ((atom['ruleTrace'] as List?) ?? const [])
        .map((e) => '$e')
        .contains('strict_truth:residual');
    return residual &&
        const {'decision', 'constraint'}.contains(kind) &&
        _projectDirectiveShape('${atom['text'] ?? ''}') &&
        _grounded('${atom['text'] ?? ''}', atom);
  }

  bool _mrsReviewableProjectIdea(
    Map<String, Object?> atom,
    double importance,
  ) {
    if (!_promotableAtom(atom)) return false;
    final rule = _strictRule(atom);
    if (rule != null && _mrsBlockedRules.contains(rule)) return false;
    if (_deterministicProjectIdea(atom)) return false;
    final kind = '${atom['kind']}';
    final text = '${atom['text'] ?? ''}';
    if (const {'decision', 'constraint'}.contains(kind) &&
        _projectDirectiveShape(text)) {
      return true;
    }
    if (kind == 'idea' && importance >= .68 && _grounded(text, atom)) {
      return true;
    }
    return kind == 'fact' &&
        importance >= .72 &&
        _grounded(text, atom, evidenceCount: 1) &&
        !_operationallyThinFact(atom);
  }

  bool _duplicatesCurrentTruth(
    Map<String, Object?> atom,
    List<Map<String, Object?>> truths,
  ) {
    if ('${atom['kind']}' != 'fact' || '${atom['truthStatus']}' != 'CURRENT') {
      return false;
    }
    final atomText = _normalizeForPromotion('${atom['text'] ?? ''}');
    final atomSubject =
        normalizeText('${atom['canonicalSubject'] ?? atom['subject'] ?? ''}')
            .toLowerCase();
    final atomValue = _normalizedValue(atom);
    return truths.any((truth) {
      if ('${truth['status']}' != 'CURRENT') return false;
      final sameText =
          _normalizeForPromotion('${truth['text'] ?? ''}') == atomText;
      final sameSubjectValue = atomSubject.isNotEmpty &&
          normalizeText('${truth['canonicalSubject'] ?? ''}').toLowerCase() ==
              atomSubject &&
          atomValue.isNotEmpty &&
          _normalizedValue(truth) == atomValue;
      return sameText || sameSubjectValue;
    });
  }

  _ScoringContext _buildScoringContext(List<Map<String, Object?>> atoms) {
    final atomById = <String, Map<String, Object?>>{};
    final keywordFrequency = <String, int>{};
    final conceptFrequency = <String, double>{};
    final novelty = <String, double>{};

    for (final atom in atoms) {
      final id = '${atom['id'] ?? ''}';
      if (id.isNotEmpty) atomById[id] = atom;
      final keywords = ((atom['keywords'] as List?) ??
              _terms('${atom['text'] ?? ''}', limit: 8))
          .map((entry) => normalizeText('$entry').toLowerCase())
          .where((entry) => entry.isNotEmpty)
          .take(8)
          .toSet();
      for (final keyword in keywords) {
        keywordFrequency[keyword] = (keywordFrequency[keyword] ?? 0) + 1;
      }
    }

    final projectScale = (atoms.length - 1).clamp(1, 1 << 30).toDouble();
    for (final atom in atoms) {
      final id = '${atom['id'] ?? ''}';
      final keywords = ((atom['keywords'] as List?) ??
              _terms('${atom['text'] ?? ''}', limit: 7))
          .map((entry) => normalizeText('$entry').toLowerCase())
          .where((entry) => entry.isNotEmpty)
          .take(7)
          .toSet();
      if (id.isEmpty) continue;
      if (keywords.isEmpty) {
        conceptFrequency[id] = 0;
        novelty[id] = .25;
        continue;
      }
      final overlapMass = keywords.fold<double>(
        0,
        (sum, keyword) => sum + ((keywordFrequency[keyword] ?? 1) - 1),
      );
      final normalizedMass = overlapMass / (keywords.length * projectScale);
      conceptFrequency[id] = _clamp(normalizedMass * 8);
      novelty[id] = _clamp(1 - normalizedMass.clamp(0, 1) * 6);
    }

    return _ScoringContext(
      atomById: atomById,
      keywordFrequency: keywordFrequency,
      conceptFrequencyByAtomId: conceptFrequency,
      noveltyByAtomId: novelty,
    );
  }

  double _truthPromotionScore(
    Map<String, Object?> truth,
    _ScoringContext context,
  ) {
    final evidenceAtoms = ((truth['evidenceAtomIds'] as List?) ?? const [])
        .map((id) => context.atomById['$id'])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final sourceAtom = evidenceAtoms.isNotEmpty
        ? evidenceAtoms.first
        : context.atomById['${truth['atomId']}'];
    final text = normalizeText('${truth['text'] ?? ''}');
    final grounded = _grounded(text, sourceAtom ?? truth,
        evidenceCount: evidenceAtoms.length);
    final requestPenalty = _requestLike(text) ||
            evidenceAtoms.any((atom) => _requestLike('${atom['text'] ?? ''}'))
        ? .32
        : 0.0;
    final weakPenalty =
        _weakStandalone(text, allowStructuredRequest: grounded) ? .22 : 0.0;
    final evidenceBoost = (evidenceAtoms.length * .04).clamp(0, .18);
    final kind = '${truth['kind']}';
    final kindBoost = kind == 'decision'
        ? .14
        : kind == 'constraint'
            ? .1
            : kind == 'fact'
                ? .06
                : 0.0;
    final confidence = (truth['confidence'] as num?)?.toDouble() ?? .7;
    final requestMitigation = grounded ? .2 : 0.0;
    return _clamp(.22 +
        kindBoost +
        .22 * confidence +
        .08 * _recency(truth['updatedAt']) +
        evidenceBoost +
        (grounded ? .08 : 0) -
        (requestPenalty - requestMitigation).clamp(0, 1) -
        weakPenalty);
  }

  double _ideaImportance(
    Map<String, Object?> atom,
    _ScoringContext context,
  ) {
    final kind = '${atom['kind']}';
    final kindBoost = kind == 'idea'
        ? .2
        : kind == 'decision'
            ? .16
            : kind == 'constraint'
                ? .1
                : 0.0;
    final truthBoost = '${atom['truthStatus']}' == 'CURRENT'
        ? .1
        : '${atom['truthStatus']}' == 'CONFLICTING'
            ? .05
            : 0.0;
    final id = '${atom['id'] ?? ''}';
    final connection = context.conceptFrequencyByAtomId[id] ?? 0;
    final keywordCount = ((atom['keywords'] as List?) ?? const []).length;
    final scope = _clamp((keywordCount == 0 ? 1 : keywordCount) / 8);
    final text = normalizeText('${atom['text'] ?? ''}');
    final grounded = _grounded(text, atom,
        evidenceCount: '${atom['truthStatus']}' == 'CURRENT' ? 2 : 0);
    final requestPenalty = _requestLike(text) ? .24 : 0.0;
    final weakPenalty =
        _weakStandalone(text, allowStructuredRequest: grounded) ? .18 : 0.0;
    final thinFactPenalty = _operationallyThinFact(atom) ? .22 : 0.0;
    final confidence = (atom['confidence'] as num?)?.toDouble() ?? .65;
    return _clamp(.14 +
        kindBoost +
        truthBoost +
        .18 * confidence +
        .12 * _recency(atom['createdAt']) +
        .16 * connection +
        .06 * scope +
        (grounded ? .06 : 0) -
        (requestPenalty - (grounded ? .14 : 0)).clamp(0, 1) -
        weakPenalty -
        thinFactPenalty);
  }

  double _novelty(Map<String, Object?> atom, _ScoringContext context) =>
      context.noveltyByAtomId['${atom['id'] ?? ''}'] ?? .25;

  String _sentenceCase(String value) {
    final text = _normalizeForPromotion(value)
        .replaceAll(RegExp(r'^[\s:;,.]+|[\s:;,.]+$'), '');
    return text.isEmpty ? '' : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String _clipDisplayText(String value, {int limit = 260}) {
    final text = _normalizeForPromotion(value)
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1) ?? '')
        .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length <= limit) return text;
    final clipped = text.substring(0, limit);
    final lastSpace = clipped.lastIndexOf(' ');
    final end = lastSpace < 120 ? limit : lastSpace;
    return '${clipped.substring(0, end)}...';
  }

  String _readableScope(Object? scope) {
    final text = _normalizeForPromotion('${scope ?? ''}');
    return text.isEmpty ? '' : ' ($text)';
  }

  String _readableValue(Object? value) {
    final text = _normalizeForPromotion('${value ?? ''}')
        .replaceAll(RegExp(r'[.]+$'), '');
    return text.isNotEmpty && text.length <= 140 ? text : '';
  }

  String _readableAtomStatement(Map<String, Object?> atom) {
    final subject =
        _sentenceCase('${atom['subject'] ?? atom['canonicalSubject'] ?? ''}');
    final value = _readableValue(atom['value']);
    if (subject.isNotEmpty && value.isNotEmpty) {
      final kind = '${atom['kind']}';
      if (kind == 'decision') {
        return 'Decision: $subject is $value${_readableScope(atom['scope'])}.';
      }
      if (kind == 'constraint') {
        return 'Constraint: $subject must be treated as $value${_readableScope(atom['scope'])}.';
      }
      if (kind == 'task') {
        return 'Task: $subject needs $value${_readableScope(atom['scope'])}.';
      }
      return '$subject is $value${_readableScope(atom['scope'])}.';
    }
    return _clipDisplayText('${atom['text'] ?? ''}');
  }

  String _readableTruthStatement(Map<String, Object?> truth) {
    final subject = _sentenceCase('${truth['canonicalSubject'] ?? ''}');
    final value = _readableValue(truth['value']);
    if (subject.isNotEmpty && value.isNotEmpty) {
      final prefix = '${truth['kind']}' == 'decision'
          ? 'Decision'
          : '${truth['kind']}' == 'constraint'
              ? 'Constraint'
              : 'Current truth';
      return '$prefix: $subject is $value${_readableScope(truth['scope'])}.';
    }
    return _clipDisplayText('${truth['text'] ?? ''}');
  }

  String _readableTitle(String kind, Map<String, Object?> source) {
    final subject = _sentenceCase(
        '${source['subject'] ?? source['canonicalSubject'] ?? ''}');
    if (subject.length >= 4) {
      return subject.substring(0, subject.length > 90 ? 90 : subject.length);
    }
    final text = _clipDisplayText('${source['text'] ?? ''}', limit: 96)
        .replaceAll(RegExp(r'[.?!]+$'), '');
    return text.isNotEmpty ? text : kind.replaceAll('_', ' ').toLowerCase();
  }

  bool _evidenceExists(
    List<String> ids,
    List<Map<String, Object?>> atoms,
    List<Map<String, Object?>> truths,
    List<Map<String, Object?>> patterns,
  ) {
    final all = <String>{
      ...atoms.map((x) => '${x['id'] ?? ''}'),
      ...truths.map((x) => '${x['id'] ?? ''}'),
      ...patterns.map((x) => '${x['id'] ?? ''}'),
    }..remove('');
    return ids.isNotEmpty && ids.every(all.contains);
  }

  Map<String, Object?> _item({
    required String projectId,
    required String kind,
    required String title,
    required String statement,
    required List<String> evidenceIds,
    required double truthConfidence,
    required double importance,
    required double novelty,
    required String rationale,
    required List<Map<String, Object?>> atoms,
    required List<Map<String, Object?>> truths,
    required List<Map<String, Object?>> patterns,
    String? verification,
    Object? createdAt,
  }) {
    final sortedEvidence = evidenceIds.toList()..sort();
    final id = canonicalId(brain2IntelligenceVersion,
        [projectId, kind, normalizeText(statement), ...sortedEvidence]);
    return <String, Object?>{
      'id': id,
      'projectId': projectId,
      'kind': kind,
      'title': title,
      'statement': statement,
      'evidenceIds': evidenceIds,
      'truthConfidence': _clamp(truthConfidence),
      'importance': _clamp(importance),
      'novelty': _clamp(novelty),
      'verification': verification ??
          (_evidenceExists(evidenceIds, atoms, truths, patterns)
              ? 'DETERMINISTIC_VERIFIED'
              : 'MRS_PENDING'),
      'rationale': rationale,
      'createdAt': createdAt,
    };
  }

  String buildProjectIntelligenceSourceVersion({
    required Map<String, Object?> project,
    required List<Map<String, Object?>> atoms,
    required List<Map<String, Object?>> truths,
    required List<Map<String, Object?>> patterns,
  }) {
    return sha256Hex(canonicalJson(<String, Object?>{
      'ruleVersion': brain2ProjectIntelligenceRuleVersion,
      'projectId': project['id'],
      'projectUpdatedAt': project['updatedAt'],
      'atomCount': atoms.length,
      'truthCount': truths.length,
      'patternCount': patterns.length,
      'atomTail': atoms
          .take(40)
          .map((x) => <Object?>[
                x['id'],
                x['createdAt'],
                x['truthStatus'],
                x['confidence'],
              ])
          .toList(),
      'truthTail': truths
          .take(40)
          .map((x) => <Object?>[
                x['id'],
                x['status'],
                x['updatedAt'],
                x['confidence'],
              ])
          .toList(),
      'patternTail': patterns
          .take(20)
          .map((x) => <Object?>[
                x['id'],
                x['updatedAt'],
                x['status'],
                x['strength'],
              ])
          .toList(),
    }));
  }

  Map<String, Object?> buildProjectIntelligenceProjection({
    required Map<String, Object?> project,
    required List<Map<String, Object?>> truthRows,
    required List<Map<String, Object?>> atoms,
    required List<Map<String, Object?>> patterns,
  }) {
    final projectId = '${project['id'] ?? ''}';
    final projectAtoms = atoms
        .where((atom) => '${atom['projectId'] ?? ''}' == projectId)
        .toList(growable: false);
    final projectTruths = truthRows
        .where((truth) => '${truth['projectId'] ?? ''}' == projectId)
        .toList(growable: false);
    final projectPatterns = patterns
        .where((p) => ((p['projectIds'] as List?) ?? const [])
            .map((e) => '$e')
            .contains(projectId))
        .toList(growable: false);
    final context = _buildScoringContext(projectAtoms);
    final truthIds = projectTruths.map((truth) => '${truth['id']}').toSet();
    final atomIds = projectAtoms.map((atom) => '${atom['id']}').toSet();

    final currentTruth = <Map<String, Object?>>[];
    final importantIdeas = <Map<String, Object?>>[];
    final changes = <Map<String, Object?>>[];
    final connections = <Map<String, Object?>>[];
    final openQuestions = <Map<String, Object?>>[];
    final unresolved = <Map<String, Object?>>[];

    final scoredTruths = projectTruths
        .where((truth) =>
            '${truth['status']}' == 'CURRENT' &&
            _promotableTruth(truth, context))
        .map((truth) => (
              truth: truth,
              score: _truthPromotionScore(truth, context),
            ))
        .where((entry) => entry.score >= .58)
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        return '${b.truth['updatedAt'] ?? ''}'
            .compareTo('${a.truth['updatedAt'] ?? ''}');
      });

    for (final entry in scoredTruths.take(40)) {
      final truth = entry.truth;
      final evidenceIds = <String>[
        '${truth['id']}',
        ...((truth['evidenceAtomIds'] as List?) ?? const []).map((e) => '$e'),
      ].where((id) => truthIds.contains(id) || atomIds.contains(id)).toList();
      currentTruth.add(_item(
        projectId: projectId,
        kind: 'TRUTH',
        title: '${truth['kind']}' == 'decision'
            ? 'Current decision'
            : _readableTitle('TRUTH', {
                ...truth,
                'subject': truth['canonicalSubject'],
              }),
        statement: _readableTruthStatement(truth),
        evidenceIds: evidenceIds,
        truthConfidence: (truth['confidence'] as num?)?.toDouble() ?? .7,
        importance: entry.score,
        novelty: .2,
        rationale:
            'Deterministic Current Truth: this item has a current truth record, grounded evidence, and enough assertion structure to present before MRS review.',
        atoms: projectAtoms,
        truths: projectTruths,
        patterns: projectPatterns,
        createdAt: truth['updatedAt'],
      ));
    }

    final candidates = projectAtoms
        .where((atom) =>
            const {'idea', 'decision', 'constraint', 'fact'}
                .contains('${atom['kind']}') &&
            _promotableAtom(atom) &&
            '${atom['truthStatus']}' != 'SUPERSEDED' &&
            '${atom['truthStatus']}' != 'CONFLICTING' &&
            !_duplicatesCurrentTruth(atom, projectTruths))
        .map((atom) => (
              atom: atom,
              importance: _ideaImportance(atom, context),
              novelty: _novelty(atom, context),
            ))
        .where((entry) =>
            _deterministicProjectIdea(entry.atom) ||
            _mrsReviewableProjectIdea(entry.atom, entry.importance))
        .toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));

    for (final entry in candidates.take(60)) {
      if (entry.importance < .56) continue;
      final atom = entry.atom;
      final deterministic = _deterministicProjectIdea(atom);
      final item = _item(
        projectId: projectId,
        kind: 'IMPORTANT_IDEA',
        title: _readableTitle('IMPORTANT_IDEA', atom),
        statement: _readableAtomStatement(atom),
        evidenceIds: <String>['${atom['id']}'],
        truthConfidence: '${atom['truthStatus']}' == 'CURRENT'
            ? ((atom['confidence'] as num?)?.toDouble() ?? .65)
            : (((atom['confidence'] as num?)?.toDouble() ?? .65)
                .clamp(0, deterministic ? .82 : .72)
                .toDouble()),
        importance: entry.importance,
        novelty: entry.novelty,
        verification: deterministic ? 'DETERMINISTIC_VERIFIED' : 'MRS_PENDING',
        rationale: deterministic
            ? 'Deterministic project intelligence: ${_strictRule(atom) ?? atom['kind']} has enough project-scoped human directive structure to show without MRS.'
            : 'MRS candidate: human-authored project evidence is useful but ambiguous enough to require semantic review before verification.',
        atoms: projectAtoms,
        truths: projectTruths,
        patterns: projectPatterns,
        createdAt: atom['createdAt'],
      );
      importantIdeas.add(item);
      if (!deterministic) unresolved.add(item);
    }

    final changeTruths = projectTruths
        .where((truth) =>
            const {'SUPERSEDED', 'CONFLICTING', 'PENDING_REVIEW'}
                .contains('${truth['status']}') &&
            _promotableTruth(truth, context))
        .toList()
      ..sort((a, b) =>
          '${b['updatedAt'] ?? ''}'.compareTo('${a['updatedAt'] ?? ''}'));
    for (final truth in changeTruths.take(30)) {
      final evidenceIds = <String>[
        '${truth['id']}',
        ...((truth['evidenceAtomIds'] as List?) ?? const []).map((e) => '$e'),
      ].where((id) => truthIds.contains(id) || atomIds.contains(id)).toList();
      changes.add(_item(
        projectId: projectId,
        kind: 'CHANGE',
        title: '${truth['status']}' == 'CONFLICTING'
            ? 'Conflict detected'
            : '${truth['status']}' == 'SUPERSEDED'
                ? 'Superseded state'
                : 'Unresolved change',
        statement: _readableTruthStatement(truth),
        evidenceIds: evidenceIds,
        truthConfidence: (truth['confidence'] as num?)?.toDouble() ?? .65,
        importance: .7,
        novelty: .35,
        rationale:
            'Deterministic change signal: the truth engine marked this record ${truth['status']}, so Life Wiki keeps it separate from Current Truth.',
        atoms: projectAtoms,
        truths: projectTruths,
        patterns: projectPatterns,
        createdAt: truth['updatedAt'],
      ));
    }

    final sortedPatterns = projectPatterns
        .where((pattern) =>
            '${pattern['status']}' == 'VERIFIED' ||
            (((pattern['strength'] as num?)?.toDouble() ?? 0) >= .22 &&
                ((pattern['evidenceCount'] as num?)?.toInt() ?? 0) >= 2))
        .toList()
      ..sort((a, b) => ((b['strength'] as num?)?.toDouble() ?? 0)
          .compareTo((a['strength'] as num?)?.toDouble() ?? 0));
    for (final pattern in sortedPatterns.take(20)) {
      final strength = (pattern['strength'] as num?)?.toDouble() ?? 0;
      final evidenceIds = <String>[
        '${pattern['id']}',
        ...((pattern['atomIds'] as List?) ?? const []).map((e) => '$e').take(6),
      ]
          .where((id) => id == '${pattern['id']}' || atomIds.contains(id))
          .toList();
      connections.add(_item(
        projectId: projectId,
        kind: 'CONNECTION',
        title: '${pattern['status']}' == 'VERIFIED'
            ? 'Verified connection'
            : 'Candidate connection',
        statement:
            normalizeText('${pattern['label'] ?? pattern['hypothesis'] ?? ''}'),
        evidenceIds: evidenceIds,
        truthConfidence: '${pattern['status']}' == 'VERIFIED'
            ? _clamp(strength < .75 ? .75 : strength)
            : _clamp(strength < .7 ? strength : .7),
        importance: _clamp(.45 + .35 * strength),
        novelty: .4,
        verification: '${pattern['status']}' == 'VERIFIED'
            ? 'DETERMINISTIC_VERIFIED'
            : 'MRS_PENDING',
        rationale:
            'Pattern Lab connection with ${pattern['evidenceCount'] ?? 0} observations and ${pattern['counterexamples'] ?? 0} counterexamples.',
        atoms: projectAtoms,
        truths: projectTruths,
        patterns: projectPatterns,
        createdAt: pattern['updatedAt'],
      ));
    }

    final questions = projectAtoms
        .where(
            (atom) => '${atom['kind']}' == 'question' && _promotableAtom(atom))
        .toList()
      ..sort((a, b) =>
          '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
    for (final atom in questions.take(25)) {
      openQuestions.add(_item(
        projectId: projectId,
        kind: 'OPEN_QUESTION',
        title: _readableTitle('OPEN_QUESTION', atom),
        statement: _clipDisplayText('${atom['text'] ?? ''}'),
        evidenceIds: <String>['${atom['id']}'],
        truthConfidence: (atom['confidence'] as num?)?.toDouble() ?? .6,
        importance: _clamp(.45 + .25 * _recency(atom['createdAt'])),
        novelty: _novelty(atom, context),
        rationale:
            'Explicit unresolved question preserved from source history.',
        atoms: projectAtoms,
        truths: projectTruths,
        patterns: projectPatterns,
        createdAt: atom['createdAt'],
      ));
    }

    int byImportance(Map<String, Object?> a, Map<String, Object?> b) {
      final importance = ((b['importance'] as num?)?.toDouble() ?? 0)
          .compareTo((a['importance'] as num?)?.toDouble() ?? 0);
      if (importance != 0) return importance;
      return ((b['truthConfidence'] as num?)?.toDouble() ?? 0)
          .compareTo((a['truthConfidence'] as num?)?.toDouble() ?? 0);
    }

    currentTruth.sort(byImportance);
    importantIdeas.sort(byImportance);
    changes.sort(byImportance);
    connections.sort(byImportance);
    openQuestions.sort(byImportance);
    unresolved.sort(byImportance);

    final now = DateTime.now().toUtc().toIso8601String();
    final sourceVersion = buildProjectIntelligenceSourceVersion(
      project: project,
      atoms: projectAtoms,
      truths: projectTruths,
      patterns: projectPatterns,
    );
    return <String, Object?>{
      'id': canonicalId('intel', [projectId, sourceVersion]),
      'version': brain2IntelligenceVersion,
      'ruleVersion': brain2ProjectIntelligenceRuleVersion,
      'sourceVersion': sourceVersion,
      'projectId': projectId,
      'generatedAt': now,
      'mrsRuntime': unresolved.isEmpty ? 'NOT_REQUIRED' : 'DEFERRED',
      'currentTruth': currentTruth.take(25).toList(),
      'truth': currentTruth.take(25).toList(),
      'importantIdeas': importantIdeas
          .where((item) => '${item['verification']}' != 'REJECTED')
          .take(20)
          .toList(),
      'novelty': (importantIdeas.toList()
            ..sort((a, b) => ((b['novelty'] as num?)?.toDouble() ?? 0)
                .compareTo((a['novelty'] as num?)?.toDouble() ?? 0)))
          .take(12)
          .toList(),
      'changes': changes.take(20).toList(),
      'connections': connections.take(15).toList(),
      'openQuestions': openQuestions.take(15).toList(),
      'unresolved': unresolved.take(50).toList(),
      'unresolvedTotal': unresolved.length,
      'mrsReviewedCandidateIds': <String>[],
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
  }

  Future<Map<String, Object?>> buildProjectIntelligence(
    String projectId, {
    List<Map<String, Object?>>? truthRows,
    List<Map<String, Object?>>? atoms,
  }) async {
    final project = await db.getRecord('projects', projectId);
    if (project == null) throw StateError('Unknown Brain2 project: $projectId');
    final truths = truthRows ??
        await db.recordsByJsonFields('truths', {'projectId': projectId},
            newestFirst: true, limit: 1600);
    final atomRows = atoms ??
        await db.recordsByJsonFields('atoms', {'projectId': projectId},
            newestFirst: true, limit: 3000);
    final patterns =
        await db.records('patterns', orderBy: 'updated_at DESC', limit: 500);
    return buildProjectIntelligenceProjection(
      project: project,
      truthRows: truths,
      atoms: atomRows,
      patterns: patterns,
    );
  }
}
