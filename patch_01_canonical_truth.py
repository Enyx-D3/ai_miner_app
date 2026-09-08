#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
PIPE = ROOT / 'lib/intelligence/mobile_intelligence_pipeline.dart'
TRUTH = ROOT / 'lib/intelligence/truth_batch_engine.dart'
NEW = ROOT / 'lib/intelligence/canonical_truth.dart'
for p in (PIPE, TRUTH):
    if not p.exists():
        raise SystemExit(f'ERROR: expected mobile project file not found: {p}')

stamp = str(int(time.time()))
def backup(p: Path):
    b = p.with_name(p.name + f'.pre_canonical_truth_{stamp}')
    shutil.copy2(p, b)
    return b

canonical_truth = r'''import '../core/identity.dart';

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
  if (_chatTaskRe.hasMatch(normalized) && !_projectRequirementRe.hasMatch(normalized)) {
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
      reason: 'Transient UI/runtime observations should not become durable truth.',
    );
  }
  if (_speculativeRe.hasMatch(normalized) || kind == 'hypothesis') {
    return const StrictTruthDecision(
      eligible: false,
      blocked: false,
      tier: StrictTruthTier.residual,
      ruleFamily: 'speculation',
      reason: 'Speculation stays outside Current Truth unless later corroborated.',
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
  if (_shortDirectiveRe.hasMatch(normalized) && normalized.split(' ').length >= 3) {
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
    reason: 'Candidate remains evidence but lacks a strict deterministic promotion rule.',
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
'''
if NEW.exists():
    backup(NEW)
NEW.write_text(canonical_truth)

s = PIPE.read_text()
if "import 'canonical_truth.dart';" not in s:
    anchor = "import 'atomization_stack.dart';\n"
    if anchor not in s:
        raise SystemExit('ERROR: pipeline import anchor not found')
    s = s.replace(anchor, anchor + "import 'canonical_truth.dart';\n", 1)

# Add strict-decision metadata inside _atomize before out.add.
needle = "      final intrinsic = intrinsicAtomSufficiency(\n        sentence,\n        subject,\n        value: value,\n      );\n\n      out.add({"
if needle in s and 'evaluateStrictCurrentTruthCandidate(' not in s:
    repl = """      final intrinsic = intrinsicAtomSufficiency(\n        sentence,\n        subject,\n        value: value,\n      );\n      final strictDecision = evaluateStrictCurrentTruthCandidate(\n        role: '${message['role'] ?? ''}',\n        text: sentence,\n        kind: kind,\n        sourceValid: '${message['sourceId'] ?? ''}'.isNotEmpty,\n        timestampValid: '${message['occurredAt'] ?? message['createdAt'] ?? ''}'.isNotEmpty,\n      );\n\n      out.add({"""
    s = s.replace(needle, repl, 1)

# Add fields before createdAt.
needle2 = "        'fallbackPolicy': 'B_250_CHUNK',\n        'createdAt':"
if needle2 not in s:
    # older source may not yet have fallbackPolicy; use atomizationStack anchor
    needle2 = "        'atomizationStack': atomizationStackVersion,\n        'createdAt':"
    replacement2 = """        'atomizationStack': atomizationStackVersion,\n        'ruleTrace': <String>[\n          strictTruthRuleTrace(strictDecision),\n          strictDecision.eligible ? 'strict_truth:eligible' : 'strict_truth:residual',\n        ],\n        'strictTruthTier': strictDecision.tier.name.toUpperCase(),\n        'strictTruthReason': strictDecision.reason,\n        'strictTruthBlocked': strictDecision.blocked,\n        'createdAt':"""
else:
    replacement2 = """        'fallbackPolicy': 'B_250_CHUNK',\n        'ruleTrace': <String>[\n          strictTruthRuleTrace(strictDecision),\n          strictDecision.eligible ? 'strict_truth:eligible' : 'strict_truth:residual',\n        ],\n        'strictTruthTier': strictDecision.tier.name.toUpperCase(),\n        'strictTruthReason': strictDecision.reason,\n        'strictTruthBlocked': strictDecision.blocked,\n        'createdAt':"""
if needle2 in s and "'strictTruthBlocked': strictDecision.blocked" not in s:
    s = s.replace(needle2, replacement2, 1)

backup(PIPE)
PIPE.write_text(s)

s = TRUTH.read_text()
# Skip explicit strict blockers while preserving residual evidence behavior.
needle = "      final atom = input.atom;\n      final kind = '${atom['kind'] ?? ''}';\n      if (input.role != 'user' ||"
if needle in s and 'strictBlocked' not in s:
    repl = """      final atom = input.atom;\n      final kind = '${atom['kind'] ?? ''}';\n      final strictBlocked = atom['strictTruthBlocked'] == true ||\n          ((atom['ruleTrace'] as List?) ?? const [])\n              .map((e) => '$e')\n              .any((e) => const {\n                    'strict_truth:assistant_or_unknown_author',\n                    'strict_truth:question',\n                    'strict_truth:code_or_log',\n                    'strict_truth:chat_task',\n                    'strict_truth:transient_observation',\n                    'strict_truth:invalid_source',\n                    'strict_truth:invalid_timestamp',\n                  }.contains(e));\n      if (strictBlocked || input.role != 'user' ||"""
    s = s.replace(needle, repl, 1)

# Add strict lineage to truth records.
needle = "        'scope': atom['scope'],\n        'reconciliationVersion': 'B2_TRUTH_V7_BATCH',"
if needle in s and "'strictTruthRootKey':" not in s:
    repl = """        'scope': atom['scope'],\n        'strictTruthRootKey': canonicalId('strict-truth-key', [\n          projectId,\n          kind,\n          subject,\n        ]),\n        'strictTruthRule': ((atom['ruleTrace'] as List?) ?? const [])\n            .map((e) => '$e')\n            .firstWhere(\n              (e) => e.startsWith('strict_truth:') &&\n                  e != 'strict_truth:eligible' &&\n                  e != 'strict_truth:residual',\n              orElse: () => 'strict_truth:residual',\n            ),\n        'reconciliationVersion': 'B2_TRUTH_V8_STRICT_MOBILE',"""
    s = s.replace(needle, repl, 1)

backup(TRUTH)
TRUTH.write_text(s)

print('PASS patch_01_canonical_truth')
print(f'  wrote: {NEW.relative_to(ROOT)}')
print('  upgraded atom strict-truth metadata + truth reconciliation blocker gate')
print('  current UI unchanged')
