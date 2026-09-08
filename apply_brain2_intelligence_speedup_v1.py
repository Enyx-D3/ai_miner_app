#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
import shutil, sys

ROOT = Path.cwd()
PIPE = ROOT / 'lib/intelligence/mobile_intelligence_pipeline.dart'
IMPORT = ROOT / 'lib/services/import_service.dart'
NEW = ROOT / 'lib/intelligence/truth_batch_engine.dart'

for p in (PIPE, IMPORT):
    if not p.exists():
        raise SystemExit(f'ERROR: expected Brain2 mobile project root; missing {p}')

stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup = ROOT / f'.brain2_intelligence_speed_backup_{stamp}'
backup.mkdir(exist_ok=True)
for p in (PIPE, IMPORT):
    dst = backup / p.relative_to(ROOT)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, dst)
if NEW.exists():
    dst = backup / NEW.relative_to(ROOT)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(NEW, dst)


def replace_method(text: str, signature: str, replacement: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise RuntimeError(f'Could not find method signature: {signature}')
    async_pos = text.find('async {', start)
    if async_pos < 0:
        raise RuntimeError(f'Could not find async body for: {signature}')
    brace = text.find('{', async_pos)
    if brace < 0:
        raise RuntimeError(f'Could not find opening brace for: {signature}')
    depth = 0
    quote = None
    escape = False
    i = brace
    while i < len(text):
        ch = text[i]
        if quote:
            if escape:
                escape = False
            elif ch == '\\':
                escape = True
            elif ch == quote:
                quote = None
        else:
            if ch in ('"', "'"):
                quote = ch
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    return text[:start] + replacement.rstrip() + text[end:]
        i += 1
    raise RuntimeError(f'Unbalanced method: {signature}')

truth_batch = r'''import '../core/identity.dart';
import '../storage/brain2_database.dart';

class TruthAtomInput {
  final Map<String, Object?> atom;
  final String role;

  const TruthAtomInput(this.atom, this.role);
}

class TruthBatchResult {
  final List<Map<String, Object?>> truthWrites;

  const TruthBatchResult(this.truthWrites);
}

/// Fast import/build-session truth reconciler.
///
/// Loads each project+kind truth group once, reconciles subsequent atoms in
/// memory, and returns one deduplicated write set to be committed together
/// with an atom batch. This removes the previous per-atom SQLite query and
/// per-truth mutation/transaction loop.
class MobileTruthBatchEngine {
  final Brain2Database db;

  final Map<String, List<Map<String, Object?>>> _activeGroups = {};
  final Set<String> _loadedGroups = {};

  MobileTruthBatchEngine(this.db);

  void reset() {
    _activeGroups.clear();
    _loadedGroups.clear();
  }

  void invalidateProject(String projectId) {
    final prefix = '$projectId\u241f';
    _activeGroups.removeWhere((key, _) => key.startsWith(prefix));
    _loadedGroups.removeWhere((key) => key.startsWith(prefix));
  }

  Future<TruthBatchResult> reconcile(List<TruthAtomInput> inputs) async {
    if (inputs.isEmpty) return const TruthBatchResult([]);
    final writes = <String, Map<String, Object?>>{};

    for (final input in inputs) {
      final atom = input.atom;
      final kind = '${atom['kind'] ?? ''}';
      if (input.role != 'user' ||
          !const {'decision', 'constraint', 'fact', 'task'}.contains(kind)) {
        continue;
      }

      final projectId = '${atom['projectId'] ?? ''}';
      if (projectId.isEmpty) continue;
      final subject = normalizeText(
        '${atom['canonicalSubject'] ?? atom['subject'] ?? atom['text'] ?? ''}',
      ).toLowerCase();
      if (subject.isEmpty) continue;

      final group = await _group(projectId, kind);
      Map<String, Object?>? match;
      var best = 0.0;
      final atomTerms = _terms(subject);
      for (final truth in group) {
        final overlap = _overlap(
          atomTerms,
          _terms('${truth['canonicalSubject'] ?? truth['text'] ?? ''}'),
        );
        if (overlap > best) {
          best = overlap;
          match = truth;
        }
      }
      if (best < 0.25) match = null;

      final now = DateTime.now().toUtc().toIso8601String();
      final value = normalizeText('${atom['value'] ?? ''}').toLowerCase();
      final text = normalizeText('${atom['text'] ?? ''}');
      final explicitUpdate = RegExp(
        r"\b(now|going forward|from now on|replace(?:d)?|instead|switch(?:ed)?|changed? to|set to|updated? to|no longer|we(?:'ll| will) use|we decided|final(?:ly)?|canonical)\b",
        caseSensitive: false,
      ).hasMatch(text);

      var relation = 'NEW';
      var status = 'CURRENT';
      if (match != null) {
        final oldText = normalizeText('${match['text'] ?? ''}').toLowerCase();
        final oldValue = normalizeText('${match['value'] ?? ''}').toLowerCase();
        if (oldText == text.toLowerCase()) {
          relation = 'SAME';
        } else if (value.isNotEmpty && oldValue.isNotEmpty && value != oldValue) {
          relation = explicitUpdate ? 'SUPERSEDES' : 'CONTRADICTS';
        } else if (explicitUpdate && best >= 0.45) {
          relation = 'SUPERSEDES';
        } else if (best >= 0.72) {
          relation = 'REFINES';
        } else {
          relation = 'UNCERTAIN';
        }

        if (relation == 'CONTRADICTS') {
          status = 'CONFLICTING';
          final updated = <String, Object?>{
            ...match,
            'status': 'CONFLICTING',
            'relation': 'CONTRADICTS',
            'updatedAt': now,
          };
          writes['${updated['id']}'] = updated;
          _replaceInGroup(group, updated);
        } else if (relation == 'SUPERSEDES' || relation == 'REFINES') {
          final updated = <String, Object?>{
            ...match,
            'status': 'SUPERSEDED',
            'updatedAt': now,
          };
          writes['${updated['id']}'] = updated;
          _replaceInGroup(group, updated);
        } else if (relation == 'UNCERTAIN') {
          status = 'PENDING_REVIEW';
        } else if (relation == 'SAME') {
          status = 'HISTORICAL';
        }
      }

      final id = canonicalId(
        'truth',
        [projectId, kind, subject, '${atom['id']}'],
      );
      final created = <String, Object?>{
        'id': id,
        'key': '$projectId:$kind:$subject',
        'projectId': projectId,
        'atomId': atom['id'],
        'text': text,
        'kind': kind,
        'status': status,
        'confidence': atom['confidence'] ?? 0.7,
        'createdAt': atom['createdAt'] ?? now,
        'updatedAt': now,
        'relation': relation,
        'relatedTruthIds': match == null ? <String>[] : <String>['${match['id']}'],
        'evidenceAtomIds': <String>['${atom['id']}'],
        'canonicalSubject': atom['canonicalSubject'],
        'value': atom['value'],
        'polarity': atom['polarity'],
        'scope': atom['scope'],
        'reconciliationVersion': 'B2_TRUTH_V7_BATCH',
        'schemaVersion': 10,
      };
      writes[id] = created;
      if (const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}.contains(status)) {
        _replaceInGroup(group, created);
      }
    }

    return TruthBatchResult(writes.values.toList(growable: false));
  }

  Future<List<Map<String, Object?>>> _group(
    String projectId,
    String kind,
  ) async {
    final key = '$projectId\u241f$kind';
    if (!_loadedGroups.contains(key)) {
      final rows = await db.recordsByJsonFields(
        'truths',
        {'projectId': projectId, 'kind': kind},
        newestFirst: true,
        limit: 512,
      );
      _activeGroups[key] = rows
          .where(
            (truth) => const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}
                .contains('${truth['status']}'),
          )
          .toList(growable: true);
      _loadedGroups.add(key);
    }
    return _activeGroups[key] ??= <Map<String, Object?>>[];
  }

  void _replaceInGroup(
    List<Map<String, Object?>> group,
    Map<String, Object?> record,
  ) {
    final id = '${record['id']}';
    final index = group.indexWhere((item) => '${item['id']}' == id);
    final active = const {'CURRENT', 'CONFLICTING', 'PENDING_REVIEW'}
        .contains('${record['status']}');
    if (index >= 0) {
      if (active) {
        group[index] = record;
      } else {
        group.removeAt(index);
      }
    } else if (active) {
      group.add(record);
    }
  }

  Set<String> _terms(String value) => normalizeText(value)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 3)
      .toSet();

  double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }
}
'''
NEW.write_text(truth_batch)

pipe = PIPE.read_text()
if "import 'truth_batch_engine.dart';" not in pipe:
    pipe = pipe.replace("import 'truth_engine.dart';", "import 'truth_engine.dart';\nimport 'truth_batch_engine.dart';")
if 'MobileTruthBatchEngine batchTruths' not in pipe:
    needle = '  late final MobileTruthEngine truths = MobileTruthEngine(db, mutations);'
    if needle not in pipe:
        raise RuntimeError('Could not locate MobileTruthEngine field')
    pipe = pipe.replace(
        needle,
        needle + "\n  late final MobileTruthBatchEngine batchTruths = MobileTruthBatchEngine(db);\n\n  void beginBuildSession() => batchTruths.reset();\n  void endBuildSession() => batchTruths.reset();",
    )

process_method = r'''  Future<void> processConversationData(
    Map<String, Object?> conversation,
    List<Map<String, Object?>> messages, {
    bool refreshSnapshots = true,
  }) async {
    final atoms = <Map<String, Object?>>[];
    final truthInputs = <TruthAtomInput>[];

    for (final message in messages) {
      final messageAtoms = _atomize(message, conversation);
      final role = '${message['role'] ?? ''}';
      atoms.addAll(messageAtoms);
      for (final atom in messageAtoms) {
        truthInputs.add(TruthAtomInput(atom, role));
      }
    }

    // Performance-critical web-parity rule: never commit one mutation per atom.
    // Normal conversations become one batch; very large conversations are
    // bounded so mutation JSON/P2P payloads do not grow without limit.
    const atomBatchSize = 192;
    final projectId = '${conversation['projectId'] ?? ''}';
    final conversationId = '${conversation['id'] ?? ''}';

    for (var offset = 0; offset < atoms.length; offset += atomBatchSize) {
      final end = (offset + atomBatchSize).clamp(0, atoms.length).toInt();
      final atomChunk = atoms.sublist(offset, end);
      final truthChunk = truthInputs.sublist(offset, end);
      final truthResult = await batchTruths.reconcile(truthChunk);
      final writes = <String, List<Map<String, Object?>>>{
        'atoms': atomChunk,
      };
      if (truthResult.truthWrites.isNotEmpty) {
        writes['truths'] = truthResult.truthWrites;
      }

      try {
        await mutations.upsertBatch(
          writes,
          type: 'INTELLIGENCE_ATOM_TRUTH_BATCH',
          primaryTable: 'atoms',
          entityType: 'conversations',
          entityId: '$conversationId:$offset',
        );
      } catch (_) {
        if (projectId.isNotEmpty) batchTruths.invalidateProject(projectId);
        rethrow;
      }

      if ((offset ~/ atomBatchSize) % 4 == 3) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (refreshSnapshots) {
      await refreshProjectSnapshots(projectId);
    }
  }'''
pipe = replace_method(pipe, '  Future<void> processConversationData(', process_method)

snapshot_method = r'''  Future<void> refreshProjectSnapshots(String projectId) async {
    if (projectId.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final truthRows = await db.recordsByJsonFields(
      'truths',
      {'projectId': projectId},
      newestFirst: true,
      limit: 1200,
    );
    final atoms = await db.recordsByJsonFields(
      'atoms',
      {'projectId': projectId},
      newestFirst: true,
      limit: 2000,
    );
    final current = truthRows
        .where((truth) => '${truth['status']}' == 'CURRENT')
        .take(40)
        .toList();
    final conflicts = truthRows
        .where(
          (truth) =>
              '${truth['status']}' == 'CONFLICTING' ||
              '${truth['status']}' == 'PENDING_REVIEW',
        )
        .take(20)
        .toList();
    final important = atoms
        .where(
          (atom) => const {'decision', 'constraint', 'hypothesis'}
              .contains('${atom['kind']}'),
        )
        .take(30)
        .toList();
    final openQuestions = atoms
        .where((atom) => '${atom['text']}'.contains('?'))
        .take(20)
        .toList();
    final changes = truthRows
        .where(
          (truth) => const {'SUPERSEDES', 'REFINES', 'CONTRADICTS'}
              .contains('${truth['relation']}'),
        )
        .take(30)
        .toList();

    final intelligenceSnapshot = <String, Object?>{
      'id': canonicalId('intel', [projectId, now]),
      'projectId': projectId,
      'truth': current,
      'importantIdeas': important,
      'novelty': important.take(12).toList(),
      'connections': <Object?>[],
      'changes': changes,
      'openQuestions': openQuestions,
      'conflicts': conflicts,
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
    final wikiSnapshot = <String, Object?>{
      'id': canonicalId('wiki', [projectId]),
      'projectId': projectId,
      'currentTruth': current,
      'importantIdeas': important,
      'decisions': truthRows
          .where((truth) => '${truth['kind']}' == 'decision')
          .take(40)
          .toList(),
      'changes': changes,
      'conflicts': conflicts,
      'openQuestions': openQuestions,
      'evidenceAtomIds': atoms.take(80).map((atom) => '${atom['id']}').toList(),
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
    final notebookSnapshot = <String, Object?>{
      'id': canonicalId('notebook', [projectId]),
      'projectId': projectId,
      'now': current.take(8).toList(),
      'whatChanged': changes.take(12).toList(),
      'currentTruth': current.take(20).toList(),
      'importantIdeas': important.take(12).toList(),
      'activeHypotheses': atoms
          .where((atom) => '${atom['kind']}' == 'hypothesis')
          .take(12)
          .toList(),
      'blockers': conflicts.take(10).toList(),
      'openQuestions': openQuestions.take(12).toList(),
      'nextActions': atoms
          .where((atom) => '${atom['kind']}' == 'task')
          .take(12)
          .toList(),
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };

    // LifeWiki + Notebook + intelligence snapshot are one durable commit.
    await mutations.upsertBatch(
      {
        'intelligenceSnapshots': <Map<String, Object?>>[intelligenceSnapshot],
        'wikiSnapshots': <Map<String, Object?>>[wikiSnapshot],
        'notebookSnapshots': <Map<String, Object?>>[notebookSnapshot],
      },
      type: 'PROJECT_DERIVED_SNAPSHOT_BATCH',
      primaryTable: 'intelligenceSnapshots',
      entityType: 'projects',
      entityId: projectId,
    );
  }'''
pipe = replace_method(pipe, '  Future<void> refreshProjectSnapshots(', snapshot_method)
PIPE.write_text(pipe)

imp = IMPORT.read_text()
build_method = r'''  Future<void> buildIntelligence(
    ImportSummary imported, {
    IntelligenceBuildProgress? onProgress,
  }) async {
    final total = imported.conversationIds.length;
    intelligence.beginBuildSession();
    try {
      for (var i = 0; i < total; i++) {
        await intelligence.processConversation(
          imported.conversationIds[i],
          refreshSnapshots: false,
        );
        onProgress?.call(i + 1, total);
        if ((i + 1) % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      for (final projectId in imported.projectIds) {
        await intelligence.refreshProjectSnapshots(projectId);
      }
    } finally {
      intelligence.endBuildSession();
    }
  }'''
imp = replace_method(imp, '  Future<void> buildIntelligence(', build_method)
IMPORT.write_text(imp)

# Lightweight sanity checks.
for p in (PIPE, IMPORT, NEW):
    s = p.read_text()
    if s.count('{') != s.count('}'):
        raise RuntimeError(f'Brace count mismatch after patch: {p}')
if 'INTELLIGENCE_ATOM_TRUTH_BATCH' not in PIPE.read_text():
    raise RuntimeError('atom/truth batch marker missing')
if 'B2_TRUTH_V7_BATCH' not in NEW.read_text():
    raise RuntimeError('truth batch marker missing')

print('PASS: Brain2 mobile intelligence performance patch applied.')
print(f'Backup: {backup.name}')
print('Changed:')
print('  lib/intelligence/mobile_intelligence_pipeline.dart')
print('  lib/services/import_service.dart')
print('Added:')
print('  lib/intelligence/truth_batch_engine.dart')
print('\nNext:')
print('  dart format lib/intelligence/mobile_intelligence_pipeline.dart lib/intelligence/truth_batch_engine.dart lib/services/import_service.dart')
print('  flutter analyze')
print('  flutter run -d <device>')
