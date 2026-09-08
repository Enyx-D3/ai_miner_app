import '../core/identity.dart';

const String canonicalTruthVersion = 'B2_CANONICAL_TRUTH_MOBILE_V1';

enum StrictTruthTier { d0, d1, d2, residual }

class StrictTruthDecision {
  final bool eligible;
  final bool blocked;
  final StrictTruthTier tier;
  final String ruleFamily;
  final String reason;

  const StrictTruthDecision({
    required this.eligible,
    required this.blocked,
    required this.tier,
    required this.ruleFamily,
    required this.reason,
  });
}

final RegExp _questionRe = RegExp(
  r'^\s*(what|why|how|when|where|who|which|can|could|would|should|is|are|do|does|did)\b|[?]\s*$',
  caseSensitive: false,
);
final RegExp _speculativeRe = RegExp(
  r'\b(maybe|might|could be|possibly|probably|i think|i guess|not sure|seems like|wonder if)\b',
  caseSensitive: false,
);
final RegExp _chatTaskRe = RegExp(
  r'\b(give me|write|find|search|show me|explain|summari[sz]e|review|audit|analy[sz]e|create|generate|make a|make me|tell me|help me)\b',
  caseSensitive: false,
);
final RegExp _codeOrLogRe = RegExp(
  r'(```|^\s*(import|export|const|let|var|function|class|def|from)\b|npm\s+run|GET\s+/|POST\s+/|stack trace|console\.log|error:|warning:)',
  caseSensitive: false,
  multiLine: true,
);
final RegExp _transientUiRe = RegExp(
  r'\b(freeze|frozen|unresponsive|loading|downloading|pending|console error|not seeing|showing same|reload|refresh|tab|popup|window|missing|not showing|never sends|not sending)\b',
  caseSensitive: false,
);
final RegExp _firstPersonRequirementRe = RegExp(
  r'\b(i|we)\s+(want|need|prefer|must|should|will|am going to|are going to)\b',
  caseSensitive: false,
);
final RegExp _negativeConstraintRe = RegExp(
  r"\b(do not|don't|dont|never|must not|should not|cannot|can't|no\s+manual|without\s+manual|avoid)\b",
  caseSensitive: false,
);
final RegExp _explicitConfigRe = RegExp(
  r'\b(runtime|model|backend|provider|architecture|schema|adapter|engine|cache|worker|mrs|dvi|brain2|gemini|claude|chatgpt)\b.{0,80}\b(is|are|uses|use|must use|should use|equals|=|:)\b',
  caseSensitive: false,
);
final RegExp _shortDirectiveRe = RegExp(
  r'^(keep|use|switch|replace|remove|add|make|move|stick to|preserve|disable|enable)\b',
  caseSensitive: false,
);
final RegExp _projectRequirementRe = RegExp(
  r'\b(model|backend|provider|schema|adapter|engine|cache|worker|mrs|dvi|brain2|life wiki|import|export|truth|deterministic)\b.{0,120}\b(should|must|needs?\s+to|has\s+to|have\s+to|will)\b|\b(should|must|needs?\s+to|has\s+to|have\s+to|will)\b.{0,120}\b(model|backend|provider|schema|adapter|engine|cache|worker|mrs|dvi|brain2|life wiki|import|export|truth|deterministic)\b',
  caseSensitive: false,
);

StrictTruthDecision evaluateStrictCurrentTruthCandidate({
  required String role,
  required String text,
  required String kind,
  bool sourceValid = true,
  bool timestampValid = true,
}) {
  final normalized = normalizeText(text);
  final normalizedRole = normalizeText(role).toLowerCase();

  if (!sourceValid) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'invalid_source',
      reason: 'Source identity is not valid enough for Current Truth.',
    );
  }
  if (!timestampValid) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'invalid_timestamp',
      reason: 'Source timestamp is missing or invalid.',
    );
  }
  if (normalizedRole != 'user' && normalizedRole != 'human') {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'assistant_or_unknown_author',
      reason: 'Assistant-authored text cannot directly become Current Truth.',
    );
  }
  if (normalized.isEmpty) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'empty_candidate',
      reason: 'Empty text is not a truth candidate.',
    );
  }
  if (_codeOrLogRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'code_or_log',
      reason: 'Code/log fragments are evidence, not direct Current Truth.',
    );
  }
  if (_questionRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'question',
      reason: 'Questions remain unresolved evidence.',
    );
  }
  if (_chatTaskRe.hasMatch(normalized) &&
      !_projectRequirementRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'chat_task',
      reason: 'One-off assistant requests are not durable project truth.',
    );
  }
  if (_transientUiRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: false,
      blocked: true,
      tier: StrictTruthTier.residual,
      ruleFamily: 'transient_observation',
      reason:
          'Transient UI/runtime observations should not become durable truth.',
    );
  }
  if (_speculativeRe.hasMatch(normalized) || kind == 'hypothesis') {
    return const StrictTruthDecision(
      eligible: false,
      blocked: false,
      tier: StrictTruthTier.residual,
      ruleFamily: 'speculation',
      reason:
          'Speculation stays outside Current Truth unless later corroborated.',
    );
  }
  if (_negativeConstraintRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: true,
      blocked: false,
      tier: StrictTruthTier.d0,
      ruleFamily: 'explicit_negative_constraint',
      reason: 'Explicit human-authored negative constraint.',
    );
  }
  if (_firstPersonRequirementRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: true,
      blocked: false,
      tier: StrictTruthTier.d0,
      ruleFamily: 'explicit_first_person_requirement',
      reason: 'Explicit human-authored requirement or preference.',
    );
  }
  if (_explicitConfigRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: true,
      blocked: false,
      tier: StrictTruthTier.d1,
      ruleFamily: 'explicit_project_config',
      reason: 'Bounded project/runtime configuration assertion.',
    );
  }
  if (_projectRequirementRe.hasMatch(normalized)) {
    return const StrictTruthDecision(
      eligible: true,
      blocked: false,
      tier: StrictTruthTier.d1,
      ruleFamily: 'bounded_project_requirement',
      reason: 'Project-scoped durable requirement.',
    );
  }
  if (_shortDirectiveRe.hasMatch(normalized) &&
      normalized.split(' ').length >= 3) {
    return const StrictTruthDecision(
      eligible: true,
      blocked: false,
      tier: StrictTruthTier.d2,
      ruleFamily: 'calibrated_short_component_directive',
      reason: 'Short deterministic directive with sufficient scope.',
    );
  }

  return const StrictTruthDecision(
    eligible: false,
    blocked: false,
    tier: StrictTruthTier.residual,
    ruleFamily: 'residual',
    reason:
        'Candidate remains evidence but lacks a strict deterministic promotion rule.',
  );
}

String strictTruthRuleTrace(StrictTruthDecision decision) =>
    'strict_truth:${decision.ruleFamily}';

String buildCurrentTruthRoot(List<Map<String, Object?>> truths) {
  final rows = truths
      .where((t) => '${t['status']}' == 'CURRENT')
      .map((t) => <Object?>[
            t['id'],
            t['key'],
            t['text'],
            t['kind'],
            t['confidence'],
            t['canonicalSubject'],
            t['value'],
            t['polarity'],
            t['scope'],
          ])
      .toList()
    ..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
  return sha256Hex(canonicalJson(rows));
}

String buildSourceEvidenceRoot(List<Map<String, Object?>> messages) {
  final rows = messages
      .map((m) => <Object?>[
            m['id'],
            m['provider'],
            m['conversationId'],
            m['role'],
            m['sequence'],
            m['text'],
            m['occurredAt'],
          ])
      .toList()
    ..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
  return sha256Hex(canonicalJson(rows));
}
