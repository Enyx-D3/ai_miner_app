import 'r1_authority.dart';

const String brain2CurrentTruthR1Action = 'CURRENT_TRUTH_PROMOTE';

class CurrentTruthAuthorityContext {
  final String path;
  final String? projectId;
  final String operationId;
  final String? memoryRoot;
  final String? mergeId;
  final String? sourceRoot;
  final String? targetRoot;
  final String? sourceDeviceId;
  final String? targetDeviceId;
  final int? ordinal;
  final String? chunkHash;
  final String? stateHash;
  final String? currentTruthRoot;

  const CurrentTruthAuthorityContext({
    required this.path,
    required this.operationId,
    this.projectId,
    this.memoryRoot,
    this.mergeId,
    this.sourceRoot,
    this.targetRoot,
    this.sourceDeviceId,
    this.targetDeviceId,
    this.ordinal,
    this.chunkHash,
    this.stateHash,
    this.currentTruthRoot,
  });

  String get scope {
    if (path == 'BOOTSTRAP') {
      return [
        'bootstrap',
        memoryRoot ?? '_',
        sourceDeviceId ?? '_',
        targetDeviceId ?? '_',
        '${ordinal ?? -1}',
        chunkHash ?? '_'
      ].join(':');
    }
    if (path == 'MEMORY_MERGE') {
      return [
        'merge',
        sourceRoot ?? '_',
        targetRoot ?? '_',
        sourceDeviceId ?? '_',
        targetDeviceId ?? '_',
        mergeId ?? '_'
      ].join(':');
    }
    if (path == 'B2M_IMPORT') {
      return [
        'b2m-import',
        memoryRoot ?? '_',
        stateHash ?? '_',
        currentTruthRoot ?? '_'
      ].join(':');
    }
    return [
      'current-truth',
      path,
      projectId ?? '_',
      operationId,
      memoryRoot ?? '_',
      mergeId ?? '_'
    ].join(':');
  }
}

CurrentTruthAuthorityContext currentTruthMutationContext({
  required String type,
  required String entityType,
  required String entityId,
  required String memoryRoot,
}) =>
    CurrentTruthAuthorityContext(
      path: 'MUTATION',
      operationId: '$type:$entityType:$entityId',
      memoryRoot: memoryRoot,
    );

CurrentTruthAuthorityContext currentTruthBootstrapContext({
  required String memoryRoot,
  required String sourceDeviceId,
  required String targetDeviceId,
  required int ordinal,
  required String chunkHash,
}) =>
    CurrentTruthAuthorityContext(
      path: 'BOOTSTRAP',
      operationId: '$sourceDeviceId:$targetDeviceId:$ordinal',
      memoryRoot: memoryRoot,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId,
      ordinal: ordinal,
      chunkHash: chunkHash,
    );

CurrentTruthAuthorityContext currentTruthMergeContext({
  required String sourceRoot,
  required String targetRoot,
  required String sourceDeviceId,
  required String targetDeviceId,
  required String mergeId,
}) =>
    CurrentTruthAuthorityContext(
      path: 'MEMORY_MERGE',
      operationId: mergeId,
      memoryRoot: targetRoot,
      mergeId: mergeId,
      sourceRoot: sourceRoot,
      targetRoot: targetRoot,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId,
    );

CurrentTruthAuthorityContext currentTruthB2MImportContext({
  required String memoryRoot,
  required String stateHash,
  required String currentTruthRoot,
}) =>
    CurrentTruthAuthorityContext(
      path: 'B2M_IMPORT',
      operationId: stateHash,
      memoryRoot: memoryRoot,
      stateHash: stateHash,
      currentTruthRoot: currentTruthRoot,
    );

bool containsCurrentTruthWrite(Iterable<Map<String, Object?>> records) =>
    records.any((record) => '${record['status'] ?? ''}' == 'CURRENT');

List<Map<String, Object?>> currentTruthRecordsFromWrites(
  Map<String, List<Map<String, Object?>>> writes,
) =>
    (writes['truths'] ?? const <Map<String, Object?>>[])
        .where((record) => '${record['status'] ?? ''}' == 'CURRENT')
        .toList(growable: false);

Brain2R1Receipt? requireCurrentTruthAuthority({
  required Iterable<Map<String, Object?>> truths,
  required CurrentTruthAuthorityContext context,
  Brain2R1Receipt? receipt,
  String? authoritySource,
}) {
  if (!containsCurrentTruthWrite(truths)) return null;
  if (receipt == null) {
    throw StateError(
        'R1 authority receipt is required for Current Truth writes.');
  }
  return requireVerifiedR1Allow(
    receipt,
    action: brain2CurrentTruthR1Action,
    scope: context.scope,
    minVersion: 2,
    authoritySource: authoritySource,
  );
}

Brain2R1Receipt? requireCurrentTruthAuthorityForMutation({
  required Map<String, List<Map<String, Object?>>> writes,
  required CurrentTruthAuthorityContext context,
  Brain2R1Receipt? receipt,
  String? authoritySource,
}) =>
    requireCurrentTruthAuthority(
      truths: currentTruthRecordsFromWrites(writes),
      context: context,
      receipt: receipt,
      authoritySource: authoritySource,
    );
