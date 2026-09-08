import '../core/identity.dart';
import '../models/mutation.dart';
import '../sync/sync_contract.dart';
import 'brain2_database.dart';

class MutationService {
  final Brain2Database db;
  final String deviceId;
  MutationService(this.db, this.deviceId);

  Future<MutationRecord> upsert(
    String table,
    Map<String, Object?> record, {
    String type = 'ENTITY_UPSERT',
  }) {
    return upsertBatch(
      {
        table: <Map<String, Object?>>[record]
      },
      type: type,
      primaryTable: table,
      entityType: table,
      entityId: '${record['id']}',
    );
  }

  /// Commits many related records as one durable Brain2 mutation + one SQLite
  /// transaction. Import uses this at conversation granularity so project,
  /// conversation and messages become visible atomically and sync as one delta.
  Future<MutationRecord> upsertBatch(
    Map<String, List<Map<String, Object?>>> writes, {
    String type = 'ENTITY_BATCH_UPSERT',
    String? primaryTable,
    String? entityType,
    String? entityId,
  }) async {
    if (writes.isEmpty || writes.values.every((records) => records.isEmpty)) {
      throw ArgumentError('at least one record write is required');
    }
    final firstEntry = writes.entries.firstWhere((e) => e.value.isNotEmpty);
    final effectiveEntityType = entityType ?? primaryTable ?? firstEntry.key;
    final effectiveEntityId = entityId ?? '${firstEntry.value.first['id']}';
    final root = await db.memoryRoot();
    final seq = await db.nextOriginSequence();
    final wireWrites = writes.map(
      (table, records) => MapEntry(brain2WireTableForLocal(table), records),
    );
    final payload = MutationDeltaPayload(
      writes: wireWrites,
      primaryTable: brain2WireTableForLocal(primaryTable ?? firstEntry.key),
    );
    final ph = sha256Hex(canonicalJson(payload.toJson()));
    final parents = <String>[];
    final id = canonicalId(
      'mut',
      [root, deviceId, seq, type, effectiveEntityType, effectiveEntityId, ph],
    );
    final h = MutationRecord.envelopeHash(
      memoryRoot: root,
      originDeviceId: deviceId,
      originSequence: seq,
      type: type,
      entityType: effectiveEntityType,
      entityId: effectiveEntityId,
      payloadHash: ph,
      parents: parents,
    );
    final m = MutationRecord(
      id: id,
      type: type,
      entityType: effectiveEntityType,
      entityId: effectiveEntityId,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      deviceId: deviceId,
      hash: h,
      memoryRoot: root,
      originDeviceId: deviceId,
      originSequence: seq,
      payloadHash: ph,
      payload: payload,
      parentMutationIds: parents,
      afterHash: sha256Hex(canonicalJson(writes)),
    );
    await db.commitLocalMutation(m);
    return m;
  }
}
