class NormalizedMessageInput {
  final String externalId, role, text;
  final String? providerMessageId,
      providerNodeId,
      parentProviderNodeId,
      branchId,
      occurredAt,
      capturedAt,
      timestampSource,
      captureId,
      captureUrl,
      captureConnectorId;
  final int sequence;
  const NormalizedMessageInput(
      {required this.externalId,
      required this.sequence,
      required this.role,
      required this.text,
      this.providerMessageId,
      this.providerNodeId,
      this.parentProviderNodeId,
      this.branchId,
      this.occurredAt,
      this.capturedAt,
      this.timestampSource,
      this.captureId,
      this.captureUrl,
      this.captureConnectorId});
  Map<String, Object?> toJson() => {
        'externalId': externalId,
        'providerMessageId': providerMessageId,
        'providerNodeId': providerNodeId,
        'parentProviderNodeId': parentProviderNodeId,
        'branchId': branchId,
        'sequence': sequence,
        'role': role,
        'text': text,
        'occurredAt': occurredAt,
        'capturedAt': capturedAt,
        'timestampSource': timestampSource,
        'captureId': captureId,
        'captureUrl': captureUrl,
        'captureConnectorId': captureConnectorId
      }..removeWhere((k, v) => v == null);
}

class SourceEnvelope {
  final String provider,
      sourceLabel,
      sourceType,
      conversationExternalId,
      conversationTitle;
  final String? selectedBranchId;
  final List<NormalizedMessageInput> messages;
  const SourceEnvelope(
      {required this.provider,
      required this.sourceLabel,
      required this.sourceType,
      required this.conversationExternalId,
      required this.conversationTitle,
      this.selectedBranchId,
      required this.messages});
  Map<String, Object?> toJson() => {
        'format': 'B2_SOURCE_ENVELOPE',
        'version': 2,
        'provider': provider,
        'sourceLabel': sourceLabel,
        'sourceType': sourceType,
        'conversationExternalId': conversationExternalId,
        'conversationTitle': conversationTitle,
        'selectedBranchId': selectedBranchId,
        'messages': messages.map((e) => e.toJson()).toList()
      }..removeWhere((k, v) => v == null);
}
