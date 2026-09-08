import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';
import 'atomization_stack.dart';
import 'truth_engine.dart';

class MobileIntelligencePipeline {
  final Brain2Database db;
  final MutationService mutations;
  late final MobileTruthEngine truths = MobileTruthEngine(db, mutations);

  MobileIntelligencePipeline(this.db, this.mutations);

  Future<void> processConversation(
    String conversationId, {
    bool refreshSnapshots = true,
  }) async {
    final conversation = await db.getRecord('conversations', conversationId);
    if (conversation == null) return;
    final messages = await db.recordsByJsonFields(
      'messages',
      {'conversationId': conversationId},
    );
    messages.sort(
      (a, b) => ((a['sequence'] as num?)?.toInt() ?? 0)
          .compareTo((b['sequence'] as num?)?.toInt() ?? 0),
    );
    await processConversationData(
      conversation,
      messages,
      refreshSnapshots: refreshSnapshots,
    );
  }

  /// Import-time fast path. The importer already owns the conversation and its
  /// messages, so it can avoid rescanning the entire message table per thread.
  Future<void> processConversationData(
    Map<String, Object?> conversation,
    List<Map<String, Object?>> messages, {
    bool refreshSnapshots = true,
  }) async {
    for (final message in messages) {
      final atoms = _atomize(message, conversation);
      for (final atom in atoms) {
        await mutations.upsert('atoms', atom, type: 'ATOMIZE_GFIB250');
        await truths.reconcileAtom(
          atom,
          role: '${message['role'] ?? ''}',
        );
      }
    }
    if (refreshSnapshots) {
      await refreshProjectSnapshots('${conversation['projectId'] ?? ''}');
    }
  }

  List<Map<String, Object?>> _atomize(
    Map<String, Object?> message,
    Map<String, Object?> conversation,
  ) {
    final text = normalizeText('${message['text'] ?? ''}');
    if (text.isEmpty) return const [];

    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map(normalizeText)
        .where((sentence) => sentence.length >= 4)
        .toList();
    final chunks = sentences.isEmpty ? <String>[text] : sentences;
    final out = <Map<String, Object?>>[];
    var cursor = 0;

    for (var i = 0; i < chunks.length; i++) {
      final sentence = chunks[i];
      final start = text.indexOf(sentence, cursor);
      final safeStart = start < 0 ? cursor : start;
      final end = (safeStart + sentence.length).clamp(0, text.length).toInt();
      cursor = end;
      final kind = _kind(sentence);
      final subject = _subject(sentence);
      final value = _value(sentence, kind);
      final intrinsic = intrinsicAtomSufficiency(
        sentence,
        subject,
        value: value,
      );

      out.add({
        'id': canonicalId('atom', ['${message['id']}', i, sentence]),
        'projectId': conversation['projectId'],
        'conversationId': message['conversationId'],
        'messageId': message['id'],
        'sourceId': message['sourceId'],
        'text': sentence,
        'kind': kind,
        'subject': subject,
        'canonicalSubject': subject.toLowerCase(),
        'value': value,
        'scope': null,
        'polarity': _polarity(sentence),
        'confidence': intrinsic,
        'keywords': _terms(sentence).take(12).toList(),
        'sourceStart': safeStart,
        'sourceEnd': end,
        'intrinsicSufficiency': intrinsic,
        'atomizationStack': atomizationStackVersion,
        'createdAt': message['occurredAt'] ??
            message['createdAt'] ??
            DateTime.now().toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'schemaVersion': brain2SchemaVersion,
      });
    }
    return out;
  }

  String _kind(String value) {
    final text = value.toLowerCase();
    if (RegExp(
      r"\b(decide|decided|we will|we'll|use .* instead|canonical|final)\b",
    ).hasMatch(text)) {
      return 'decision';
    }
    if (RegExp(
      r"\b(must|never|cannot|can't|required|constraint|only)\b",
    ).hasMatch(text)) {
      return 'constraint';
    }
    if (RegExp(r'\b(todo|need to|next|should|implement|fix|build)\b')
        .hasMatch(text)) {
      return 'task';
    }
    if (RegExp(r'\b(hypothesis|maybe|perhaps|could|might)\b')
        .hasMatch(text)) {
      return 'hypothesis';
    }
    return 'fact';
  }

  String _subject(String value) {
    final words = _terms(value).take(8).toList();
    return words.isEmpty ? normalizeText(value) : words.join(' ');
  }

  String? _value(String text, String kind) {
    if (!const {'decision', 'constraint', 'fact', 'task'}.contains(kind)) {
      return null;
    }
    final parts = text.split(
      RegExp(r'\b(is|are|use|be|to)\b', caseSensitive: false),
    );
    return parts.length > 1 ? normalizeText(parts.last) : null;
  }

  String _polarity(String text) => RegExp(
        r"\b(no|not|never|cannot|can't|without)\b",
        caseSensitive: false,
      ).hasMatch(text)
          ? 'NEGATIVE'
          : 'NEUTRAL';

  Iterable<String> _terms(String text) => normalizeText(text)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length >= 3);

  Future<void> refreshProjectSnapshots(String projectId) async {
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

    await mutations.upsert(
      'intelligenceSnapshots',
      {
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
      },
      type: 'INTELLIGENCE_REFRESH',
    );

    await mutations.upsert(
      'wikiSnapshots',
      {
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
      },
      type: 'LIFEWIKI_REFRESH',
    );

    await mutations.upsert(
      'notebookSnapshots',
      {
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
      },
      type: 'LIVE_NOTEBOOK_REFRESH',
    );
  }
}
