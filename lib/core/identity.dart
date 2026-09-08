import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'contracts.dart';

String normalizeText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();
String normalizeIdentityPart(Object? value) =>
    normalizeText('${value ?? ''}').toLowerCase();
String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

String canonicalId(String prefix, List<Object?> parts) {
  final stable = [brain2IdentityVersion, ...parts]
      .map(normalizeIdentityPart)
      .join('\u241f');
  return '${prefix}_${sha256Hex(stable).substring(0, 24)}';
}

String canonicalMessageId(
    {required String provider,
    required String conversationId,
    String? providerMessageId,
    String? providerNodeId,
    String? parentProviderNodeId,
    String? branchId,
    int? sequence,
    required String role,
    required String text}) {
  final nativeIdentity =
      normalizeIdentityPart(providerMessageId ?? providerNodeId);
  if (nativeIdentity.isNotEmpty)
    return canonicalId(
        'msg', [provider, conversationId, 'native', nativeIdentity]);
  return canonicalId('msg', [
    provider,
    conversationId,
    'structural',
    branchId,
    parentProviderNodeId,
    sequence ?? -1,
    role,
    normalizeText(text)
  ]);
}

Object? _sortJson(Object? value) {
  if (value is List) return value.map(_sortJson).toList();
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return {for (final key in keys) key: _sortJson(value[key])};
  }
  return value;
}

String canonicalJson(Object? value) => jsonEncode(_sortJson(value));
String hashEntity(Object? value) => sha256Hex(canonicalJson(value));

String canonicalMessageIdSync(
    {required String provider,
    required String conversationId,
    String? providerMessageId,
    String? providerNodeId,
    String? parentProviderNodeId,
    String? branchId,
    int? sequence,
    required String role,
    required String text}) {
  final nativeIdentity =
      normalizeIdentityPart(providerMessageId ?? providerNodeId ?? '');
  if (nativeIdentity.isNotEmpty)
    return canonicalId(
        'msg', [provider, conversationId, 'native', nativeIdentity]);
  return canonicalId('msg', [
    provider,
    conversationId,
    'structural',
    branchId,
    parentProviderNodeId,
    sequence ?? -1,
    role,
    normalizeText(text)
  ]);
}
