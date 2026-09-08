import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class MobileEvidenceBlockEngine {
  final Brain2Database db;
  final MutationService mutations;
  const MobileEvidenceBlockEngine(this.db, this.mutations);

  int _blockNumber(Object? sequence) {
    final n =
        (sequence as num?)?.toInt() ?? int.tryParse('${sequence ?? 0}') ?? 0;
    return n < 0 ? 0 : n ~/ 250;
  }

  Future<List<Map<String, Object?>>> buildProject(String projectId) async {
    final conversations = await db.recordsByJsonFields(
        'conversations', {'projectId': projectId},
        newestFirst: false, limit: 10000);
    final out = <Map<String, Object?>>[];
    for (final conversation in conversations) {
      final conversationId = '${conversation['id']}';
      final sourceId = '${conversation['sourceId'] ?? ''}';
      final messages = await db.recordsByJsonFields(
          'messages', {'conversationId': conversationId},
          newestFirst: false, limit: 100000);
      messages.sort((a, b) => ((a['sequence'] as num?)?.toInt() ?? 0)
          .compareTo((b['sequence'] as num?)?.toInt() ?? 0));
      final atoms = await db.recordsByJsonFields(
          'atoms', {'conversationId': conversationId},
          newestFirst: false, limit: 100000);
      final atomsByMessage = <String, List<Map<String, Object?>>>{};
      for (final atom in atoms) {
        atomsByMessage.putIfAbsent('${atom['messageId']}', () => []).add(atom);
      }
      final grouped = <int, List<Map<String, Object?>>>{};
      for (final message in messages) {
        grouped
            .putIfAbsent(_blockNumber(message['sequence']), () => [])
            .add(message);
      }
      for (final entry in grouped.entries) {
        final blockNumber = entry.key;
        final blockMessages = entry.value;
        final messageIds = blockMessages
            .map((m) => '${m['id']}')
            .where((e) => e.isNotEmpty)
            .toList();
        final atomIds = <String>[];
        for (final id in messageIds) {
          atomIds.addAll((atomsByMessage[id] ?? const [])
              .map((a) => '${a['id']}')
              .where((e) => e.isNotEmpty));
        }
        final seqs = blockMessages
            .map((m) => (m['sequence'] as num?)?.toInt() ?? 0)
            .toList();
        final firstSequence =
            seqs.isEmpty ? 0 : seqs.reduce((a, b) => a < b ? a : b);
        final lastSequence =
            seqs.isEmpty ? 0 : seqs.reduce((a, b) => a > b ? a : b);
        final byteEstimate = blockMessages.fold<int>(
            0, (sum, m) => sum + '${m['text'] ?? ''}'.codeUnits.length);
        final payload = <String, Object?>{
          'conversationId': conversationId,
          'projectId': projectId,
          'sourceId': sourceId,
          'blockNumber': blockNumber,
          'firstSequence': firstSequence,
          'lastSequence': lastSequence,
          'messageIds': messageIds,
          'atomIds': atomIds,
          'byteEstimate': byteEstimate,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'schemaVersion': brain2SchemaVersion,
        };
        out.add(<String, Object?>{
          'id': canonicalId('evidence-block', [conversationId, blockNumber]),
          ...payload,
          'hash': sha256Hex(canonicalJson(<String, Object?>{
            'conversationId': conversationId,
            'blockNumber': blockNumber,
            'messageIds': messageIds,
            'atomIds': atomIds,
            'firstSequence': firstSequence,
            'lastSequence': lastSequence
          })),
        });
      }
    }
    return out;
  }

  Future<List<Map<String, Object?>>> refreshProject(String projectId) async {
    if (projectId.isEmpty) return const [];
    final blocks = await buildProject(projectId);
    const batchSize = 128;
    for (var i = 0; i < blocks.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, blocks.length).toInt();
      await mutations.upsertBatch({'evidenceBlocks': blocks.sublist(i, end)},
          type: 'EVIDENCE_BLOCK_REFRESH',
          primaryTable: 'evidenceBlocks',
          entityType: 'projects',
          entityId: '$projectId:$i');
      if ((i ~/ batchSize) % 4 == 3) await Future<void>.delayed(Duration.zero);
    }
    return blocks;
  }
}
