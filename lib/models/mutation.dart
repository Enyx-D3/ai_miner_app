import '../core/contracts.dart';
import '../core/identity.dart';

typedef JsonMap = Map<String, Object?>;

class MutationDeltaPayload {
  final String operation;
  final Map<String, List<JsonMap>> writes;
  final Map<String, List<String>> deletes;
  final String? primaryTable;
  const MutationDeltaPayload(
      {this.operation = 'UPSERT',
      required this.writes,
      this.deletes = const {},
      this.primaryTable});
  JsonMap toJson() => {
        'version': 1,
        'operation': operation,
        'writes': writes,
        'deletes': deletes.isEmpty ? null : deletes,
        'primaryTable': primaryTable
      }..removeWhere((k, v) => v == null);
}

class MutationRecord {
  final String id,
      type,
      entityType,
      entityId,
      createdAt,
      deviceId,
      hash,
      memoryRoot,
      originDeviceId,
      payloadHash;
  final int originSequence;
  final List<String> parentMutationIds;
  final MutationDeltaPayload payload;
  final String? beforeHash, afterHash;
  MutationRecord(
      {required this.id,
      required this.type,
      required this.entityType,
      required this.entityId,
      required this.createdAt,
      required this.deviceId,
      required this.hash,
      required this.memoryRoot,
      required this.originDeviceId,
      required this.originSequence,
      required this.payloadHash,
      required this.payload,
      required this.parentMutationIds,
      this.beforeHash,
      this.afterHash});
  JsonMap toJson() => {
        'id': id,
        'type': type,
        'entityType': entityType,
        'entityId': entityId,
        'createdAt': createdAt,
        'deviceId': deviceId,
        'hash': hash,
        'schemaVersion': brain2SchemaVersion,
        'protocolVersion': brain2SyncProtocolVersion,
        'memoryRoot': memoryRoot,
        'originDeviceId': originDeviceId,
        'originSequence': originSequence,
        'parentMutationIds': parentMutationIds,
        'payload': payload.toJson(),
        'payloadHash': payloadHash,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
        'replicationStatus': 'LOCAL_COMMITTED',
        'sourceTransport': 'LOCAL'
      }..removeWhere((k, v) => v == null);
  static String envelopeHash(
          {required String memoryRoot,
          required String originDeviceId,
          required int originSequence,
          required String type,
          required String entityType,
          required String entityId,
          required String payloadHash,
          required List<String> parents}) =>
      sha256Hex([
        brain2SyncProtocolVersion,
        memoryRoot,
        originDeviceId,
        originSequence,
        type,
        entityType,
        entityId,
        payloadHash,
        ...parents
      ].join('|'));
}
