#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
PIPE = ROOT / 'lib/intelligence/mobile_intelligence_pipeline.dart'
NEW = ROOT / 'lib/intelligence/intelligence_layer.dart'
if not PIPE.exists(): raise SystemExit(f'ERROR: expected mobile project file not found: {PIPE}')
stamp=str(int(time.time()))
def backup(p):
    p=Path(p)
    if p.exists(): shutil.copy2(p, p.with_name(p.name+f'.pre_intelligence_layer_{stamp}'))

content = r'''import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';

const String brain2IntelligenceVersion = 'B2_INTELLIGENCE_V1';

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

  List<String> _terms(String value) => normalizeText(value)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 3)
      .toSet()
      .toList(growable: false);

  bool _requestLike(String value) {
    final text = normalizeText(value);
    return RegExp(
      r'^(?:i need|need |please |can you|could you|would you|help me|make |write |create |generate |give me|tell me|show me|explain |summarize |draft |build )',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _uiJunk(String value) {
    final text = normalizeText(value);
    if (text.length < 10) return true;
    return RegExp(
      r'^(?:```|`{1,3}\s*$)|this block is not supported|browser cache is not available|model download progress|brain2 ai runtime|retry after checking',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _structured(String value) {
    final text = normalizeText(value);
    return RegExp(
      r'\b(?:is|are|was|were|has|have|uses|requires|means|contains|supports|blocks|fails|works|equals|current|status|version|limit|budget|runtime|backend|model)\b|[:=]\s*\S+|\b\d+(?:\.\d+)?\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _promotable(Map<String, Object?> atom) {
    final text = normalizeText('${atom['text'] ?? ''}');
    if (_uiJunk(text)) return false;
    if (_requestLike(text) && !_structured(text)) return false;
    if (text.split(' ').length < 4 && !_structured(text)) return false;
    return true;
  }

  double _importance(Map<String, Object?> atom) {
    final kind = '${atom['kind']}';
    var value = switch (kind) {
      'decision' => .88,
      'constraint' => .9,
      'task' => .7,
      'idea' => .66,
      'fact' => .58,
      'hypothesis' => .48,
      _ => .42,
    };
    if ('${atom['truthStatus']}' == 'CURRENT') value += .08;
    if (((atom['ruleTrace'] as List?) ?? const []).map((e) => '$e').contains('strict_truth:eligible')) value += .08;
    if (_structured('${atom['text']}')) value += .05;
    value = value * .78 + _recency(atom['createdAt']) * .22;
    return _clamp(value);
  }

  Map<String, int> _keywordFrequency(List<Map<String, Object?>> atoms) {
    final out = <String, int>{};
    for (final atom in atoms) {
      final terms = ((atom['keywords'] as List?) ?? _terms('${atom['text']}'))
          .map((e) => normalizeText('$e').toLowerCase())
          .where((e) => e.length >= 3)
          .toSet();
      for (final term in terms) out[term] = (out[term] ?? 0) + 1;
    }
    return out;
  }

  double _novelty(Map<String, Object?> atom, Map<String, int> frequencies, int atomCount) {
    final terms = ((atom['keywords'] as List?) ?? _terms('${atom['text']}'))
        .map((e) => normalizeText('$e').toLowerCase())
        .where((e) => e.length >= 3)
        .toSet();
    if (terms.isEmpty || atomCount <= 1) return .4;
    final commonness = terms
            .map((term) => (frequencies[term] ?? 1) / atomCount)
            .fold<double>(0, (sum, value) => sum + value) /
        terms.length;
    return _clamp(1 - commonness);
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
    required String verification,
    required String rationale,
    Object? createdAt,
  }) {
    final id = canonicalId('intel-item', [projectId, kind, statement, evidenceIds.join('|')]);
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
      'verification': verification,
      'rationale': rationale,
      'createdAt': createdAt,
    };
  }

  Future<Map<String, Object?>> buildProjectIntelligence(
    String projectId, {
    List<Map<String, Object?>>? truthRows,
    List<Map<String, Object?>>? atoms,
  }) async {
    final project = await db.getRecord('projects', projectId);
    if (project == null) throw StateError('Unknown Brain2 project: $projectId');
    final truths = truthRows ?? await db.recordsByJsonFields('truths', {'projectId': projectId}, newestFirst: true, limit: 1600);
    final atomRows = atoms ?? await db.recordsByJsonFields('atoms', {'projectId': projectId}, newestFirst: true, limit: 3000);
    final patterns = (await db.records('patterns', orderBy: 'updated_at DESC', limit: 500))
        .where((p) => ((p['projectIds'] as List?) ?? const []).map((e) => '$e').contains(projectId))
        .toList();
    final frequencies = _keywordFrequency(atomRows);
    final currentTruth = <Map<String, Object?>>[];
    final importantIdeas = <Map<String, Object?>>[];
    final changes = <Map<String, Object?>>[];
    final connections = <Map<String, Object?>>[];
    final openQuestions = <Map<String, Object?>>[];
    final unresolved = <Map<String, Object?>>[];

    for (final truth in truths.where((t) => '${t['status']}' == 'CURRENT').take(40)) {
      final statement = normalizeText('${truth['text'] ?? ''}');
      if (statement.isEmpty || _uiJunk(statement)) continue;
      currentTruth.add(_item(
        projectId: projectId,
        kind: 'TRUTH',
        title: '${truth['kind']}'.toUpperCase(),
        statement: statement,
        evidenceIds: <String>['${truth['id']}', ...((truth['evidenceAtomIds'] as List?) ?? const []).map((e) => '$e')],
        truthConfidence: (truth['confidence'] as num?)?.toDouble() ?? .7,
        importance: .92,
        novelty: .35,
        verification: 'DETERMINISTIC_VERIFIED',
        rationale: 'Current Truth promoted by deterministic truth reconciliation.',
        createdAt: truth['updatedAt'],
      ));
    }

    final scoredAtoms = atomRows
        .where(_promotable)
        .map((atom) => (
              atom: atom,
              importance: _importance(atom),
              novelty: _novelty(atom, frequencies, atomRows.length),
            ))
        .toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));

    for (final entry in scoredAtoms.take(80)) {
      final atom = entry.atom;
      final kind = '${atom['kind']}';
      final trace = ((atom['ruleTrace'] as List?) ?? const []).map((e) => '$e').toList();
      final deterministic = trace.contains('strict_truth:eligible') || const {'decision', 'constraint'}.contains(kind);
      if ((deterministic && entry.importance >= .52) || (!deterministic && entry.importance >= .7 && _structured('${atom['text']}'))) {
        final item = _item(
          projectId: projectId,
          kind: 'IMPORTANT_IDEA',
          title: kind.toUpperCase(),
          statement: normalizeText('${atom['text']}'),
          evidenceIds: <String>['${atom['id']}'],
          truthConfidence: (atom['confidence'] as num?)?.toDouble() ?? .65,
          importance: entry.importance,
          novelty: entry.novelty,
          verification: deterministic ? 'DETERMINISTIC_VERIFIED' : 'MRS_PENDING',
          rationale: deterministic
              ? 'Deterministic project intelligence from a durable human directive/decision.'
              : 'Useful project evidence that should receive MRS semantic review before promotion.',
          createdAt: atom['createdAt'],
        );
        importantIdeas.add(item);
        if (!deterministic) unresolved.add(item);
      }
      if (normalizeText('${atom['text']}').contains('?') || kind == 'question') {
        openQuestions.add(_item(
          projectId: projectId,
          kind: 'OPEN_QUESTION',
          title: 'Open question',
          statement: normalizeText('${atom['text']}'),
          evidenceIds: <String>['${atom['id']}'],
          truthConfidence: (atom['confidence'] as num?)?.toDouble() ?? .6,
          importance: _clamp(.45 + .25 * _recency(atom['createdAt'])),
          novelty: entry.novelty,
          verification: 'DETERMINISTIC_VERIFIED',
          rationale: 'Explicit unresolved question preserved from source history.',
          createdAt: atom['createdAt'],
        ));
      }
    }

    for (final truth in truths.where((t) => const {'SUPERSEDED', 'CONFLICTING', 'PENDING_REVIEW'}.contains('${t['status']}')).take(30)) {
      changes.add(_item(
        projectId: projectId,
        kind: 'CHANGE',
        title: '${truth['status']}' == 'CONFLICTING' ? 'Conflict detected' : '${truth['status']}' == 'SUPERSEDED' ? 'Superseded state' : 'Unresolved change',
        statement: normalizeText('${truth['text']}'),
        evidenceIds: <String>['${truth['id']}', ...((truth['evidenceAtomIds'] as List?) ?? const []).map((e) => '$e')],
        truthConfidence: (truth['confidence'] as num?)?.toDouble() ?? .65,
        importance: .7,
        novelty: .35,
        verification: 'DETERMINISTIC_VERIFIED',
        rationale: 'Truth engine change-state preserved separately from Current Truth.',
        createdAt: truth['updatedAt'],
      ));
    }

    for (final pattern in patterns.where((p) => '${p['status']}' == 'VERIFIED' || (((p['strength'] as num?)?.toDouble() ?? 0) >= .22 && ((p['evidenceCount'] as num?)?.toInt() ?? 0) >= 2)).take(20)) {
      final strength = (pattern['strength'] as num?)?.toDouble() ?? 0;
      connections.add(_item(
        projectId: projectId,
        kind: 'CONNECTION',
        title: '${pattern['status']}' == 'VERIFIED' ? 'Verified connection' : 'Candidate connection',
        statement: normalizeText('${pattern['label'] ?? pattern['hypothesis'] ?? ''}'),
        evidenceIds: <String>['${pattern['id']}', ...((pattern['atomIds'] as List?) ?? const []).map((e) => '$e').take(6)],
        truthConfidence: '${pattern['status']}' == 'VERIFIED' ? _clamp(strength < .75 ? .75 : strength) : _clamp(strength < .7 ? strength : .7),
        importance: _clamp(.45 + .35 * strength),
        novelty: .4,
        verification: '${pattern['status']}' == 'VERIFIED' ? 'DETERMINISTIC_VERIFIED' : 'MRS_PENDING',
        rationale: 'Pattern Lab connection backed by ${pattern['evidenceCount'] ?? 0} observations and ${pattern['counterexamples'] ?? 0} counterexamples.',
        createdAt: pattern['updatedAt'],
      ));
    }

    int byImportance(Map<String, Object?> a, Map<String, Object?> b) =>
        ((b['importance'] as num?)?.toDouble() ?? 0).compareTo((a['importance'] as num?)?.toDouble() ?? 0);
    currentTruth.sort(byImportance);
    importantIdeas.sort(byImportance);
    changes.sort(byImportance);
    connections.sort(byImportance);
    openQuestions.sort(byImportance);
    unresolved.sort(byImportance);
    final now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'id': canonicalId('intel', [projectId, brain2IntelligenceVersion]),
      'version': brain2IntelligenceVersion,
      'projectId': projectId,
      'generatedAt': now,
      'mrsRuntime': unresolved.isEmpty ? 'NOT_REQUIRED' : 'DEFERRED',
      'currentTruth': currentTruth.take(25).toList(),
      'truth': currentTruth.take(25).toList(),
      'importantIdeas': importantIdeas.where((item) => '${item['verification']}' != 'REJECTED').take(20).toList(),
      'novelty': (importantIdeas.toList()..sort((a, b) => ((b['novelty'] as num?)?.toDouble() ?? 0).compareTo((a['novelty'] as num?)?.toDouble() ?? 0))).take(12).toList(),
      'changes': changes.take(20).toList(),
      'connections': connections.take(15).toList(),
      'openQuestions': openQuestions.take(15).toList(),
      'unresolved': unresolved.take(50).toList(),
      'unresolvedTotal': unresolved.length,
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
  }
}
'''
backup(NEW); NEW.write_text(content)
s=PIPE.read_text()
if "import 'intelligence_layer.dart';" not in s:
    anchor="import 'canonical_truth.dart';\n" if "import 'canonical_truth.dart';\n" in s else "import 'atomization_stack.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: pipeline import anchor not found')
    s=s.replace(anchor, anchor+"import 'intelligence_layer.dart';\n",1)
if 'late final MobileIntelligenceLayer intelligenceLayer' not in s:
    anchor='  late final MobileTruthBatchEngine batchTruths = MobileTruthBatchEngine(db);\n'
    if anchor not in s: raise SystemExit('ERROR: pipeline field anchor not found')
    s=s.replace(anchor, anchor+'  late final MobileIntelligenceLayer intelligenceLayer = MobileIntelligenceLayer(db);\n',1)
# Replace only old intelligenceSnapshot literal, keep current wiki/notebook UI contracts.
pattern=re.compile(r"\n    final intelligenceSnapshot = <String, Object\?>\{.*?\n    \};\n    final wikiSnapshot =", re.S)
if pattern.search(s) and 'await intelligenceLayer.buildProjectIntelligence(' not in s:
    s=pattern.sub("\n    final intelligenceSnapshot = await intelligenceLayer.buildProjectIntelligence(\n      projectId,\n      truthRows: truthRows,\n      atoms: atoms,\n    );\n    final wikiSnapshot =", s, count=1)
backup(PIPE); PIPE.write_text(s)
print('PASS patch_03_intelligence_layer')
print(f'  wrote: {NEW.relative_to(ROOT)}')
print('  replaced simplistic intelligence snapshot with deterministic scored projection')
print('  existing Wiki/Notebook/UI structures remain intact')
