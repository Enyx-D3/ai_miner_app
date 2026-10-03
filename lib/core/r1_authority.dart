import 'identity.dart';

enum Brain2R1Signal { allow, deny, pause, revoke, requireTick, limitChanged }

extension Brain2R1SignalWire on Brain2R1Signal {
  String get wire => switch (this) {
        Brain2R1Signal.allow => 'ALLOW',
        Brain2R1Signal.deny => 'DENY',
        Brain2R1Signal.pause => 'PAUSE',
        Brain2R1Signal.revoke => 'REVOKE',
        Brain2R1Signal.requireTick => 'REQUIRE_TICK',
        Brain2R1Signal.limitChanged => 'LIMIT_CHANGED',
      };
}

class Brain2R1Receipt {
  final int version;
  final Brain2R1Signal signal;
  final String action;
  final String scope;
  final String authoritySource;
  final String reason;
  final List<String> evidenceRefs;
  final String issuedAt;
  final String hash;

  const Brain2R1Receipt({
    required this.version,
    required this.signal,
    required this.action,
    required this.scope,
    required this.authoritySource,
    required this.reason,
    required this.evidenceRefs,
    required this.issuedAt,
    required this.hash,
  });

  Map<String, Object?> toJson() => {
        'format': 'B2_R1_AUTHORITY',
        'version': version,
        'signal': signal.wire,
        'action': action,
        'scope': scope,
        'authoritySource': authoritySource,
        'reason': reason,
        'evidenceRefs': evidenceRefs,
        'issuedAt': issuedAt,
        'hash': hash,
      };

  factory Brain2R1Receipt.fromJson(Map<String, Object?> json) {
    if ('${json['format'] ?? ''}' != 'B2_R1_AUTHORITY') {
      throw StateError('Unsupported R1 authority format.');
    }
    final rawVersion = json['version'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse('$rawVersion') ?? 0;
    if (version != 1 && version != 2) {
      throw StateError('Unsupported R1 authority version.');
    }
    final refs = (json['evidenceRefs'] as List? ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Brain2R1Receipt(
      version: version,
      signal: parseR1Signal(json['signal']),
      action: '${json['action'] ?? ''}',
      scope: '${json['scope'] ?? ''}',
      authoritySource: '${json['authoritySource'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      evidenceRefs: refs,
      issuedAt: '${json['issuedAt'] ?? ''}',
      hash: '${json['hash'] ?? ''}',
    );
  }
}

Brain2R1Signal parseR1Signal(Object? value) =>
    switch ('${value ?? ''}'.toUpperCase()) {
      'ALLOW' => Brain2R1Signal.allow,
      'DENY' => Brain2R1Signal.deny,
      'PAUSE' => Brain2R1Signal.pause,
      'REVOKE' => Brain2R1Signal.revoke,
      'REQUIRE_TICK' => Brain2R1Signal.requireTick,
      'LIMIT_CHANGED' => Brain2R1Signal.limitChanged,
      _ => throw StateError('Invalid or missing R1 signal.'),
    };

List<String> _refs(Iterable<String> input) {
  final out = input
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return out;
}

Map<String, Object?> r1StableMaterial(Brain2R1Receipt receipt) {
  final stable = <String, Object?>{
    'format': 'B2_R1_AUTHORITY',
    'version': receipt.version,
    'signal': receipt.signal.wire,
    'action': receipt.action,
    'scope': receipt.scope,
    'authoritySource': receipt.authoritySource,
    'reason': receipt.reason,
    'evidenceRefs': _refs(receipt.evidenceRefs),
  };
  if (receipt.version >= 2) stable['issuedAt'] = receipt.issuedAt;
  return stable;
}

String computeR1AuthorityHash(Brain2R1Receipt receipt) =>
    sha256Hex(canonicalJson(r1StableMaterial(receipt)));

Brain2R1Receipt _issue({
  required Brain2R1Signal signal,
  required String action,
  required String scope,
  required String authoritySource,
  required String reason,
  Iterable<String> evidenceRefs = const [],
}) {
  final normalizedAction = action.trim();
  final normalizedScope = scope.trim();
  final normalizedReason = reason.trim();
  if (normalizedAction.isEmpty ||
      normalizedScope.isEmpty ||
      normalizedReason.isEmpty) {
    throw StateError('R1 action, scope and reason are required.');
  }
  final issuedAt = DateTime.now().toUtc().toIso8601String();
  final unsigned = Brain2R1Receipt(
    version: 2,
    signal: signal,
    action: normalizedAction,
    scope: normalizedScope,
    authoritySource: authoritySource,
    reason: normalizedReason,
    evidenceRefs: _refs(evidenceRefs),
    issuedAt: issuedAt,
    hash: '',
  );
  return Brain2R1Receipt(
    version: unsigned.version,
    signal: unsigned.signal,
    action: unsigned.action,
    scope: unsigned.scope,
    authoritySource: unsigned.authoritySource,
    reason: unsigned.reason,
    evidenceRefs: unsigned.evidenceRefs,
    issuedAt: unsigned.issuedAt,
    hash: computeR1AuthorityHash(unsigned),
  );
}

Brain2R1Receipt issueUserR1Allow({
  required String action,
  required String scope,
  String reason = 'Explicit user approval',
  Iterable<String> evidenceRefs = const [],
}) =>
    _issue(
      signal: Brain2R1Signal.allow,
      action: action,
      scope: scope,
      authoritySource: 'EXPLICIT_USER_ACTION',
      reason: reason,
      evidenceRefs: evidenceRefs,
    );

Brain2R1Receipt issuePolicyR1Allow({
  required String action,
  required String scope,
  required String reason,
  Iterable<String> evidenceRefs = const [],
}) =>
    _issue(
      signal: Brain2R1Signal.allow,
      action: action,
      scope: scope,
      authoritySource: 'POLICY',
      reason: reason,
      evidenceRefs: evidenceRefs,
    );

Brain2R1Receipt issueVerifierR1({
  required Object? signal,
  required String action,
  required String scope,
  required String reason,
  Iterable<String> evidenceRefs = const [],
}) =>
    _issue(
      signal: parseR1Signal(signal),
      action: action,
      scope: scope,
      authoritySource: 'INDEPENDENT_VERIFIER',
      reason: reason,
      evidenceRefs: evidenceRefs,
    );

Brain2R1Receipt verifyR1AuthorityReceipt(Brain2R1Receipt receipt) {
  if (receipt.version != 1 && receipt.version != 2) {
    throw StateError('Unsupported R1 authority version.');
  }
  if (!const {'EXPLICIT_USER_ACTION', 'INDEPENDENT_VERIFIER', 'POLICY'}
      .contains(receipt.authoritySource)) {
    throw StateError('Invalid R1 authority source.');
  }
  if (receipt.action.trim().isEmpty ||
      receipt.scope.trim().isEmpty ||
      receipt.reason.trim().isEmpty) {
    throw StateError('R1 action, scope and reason are required.');
  }
  if (DateTime.tryParse(receipt.issuedAt) == null) {
    throw StateError('R1 issuedAt is invalid.');
  }
  if (receipt.hash.isEmpty || computeR1AuthorityHash(receipt) != receipt.hash) {
    throw StateError('R1 receipt hash verification failed.');
  }
  return receipt;
}

Brain2R1Receipt requireR1Allow(Brain2R1Receipt receipt,
    {String? action, String? scope}) {
  if (receipt.signal != Brain2R1Signal.allow) {
    throw StateError('R1 blocked action with ${receipt.signal.wire}.');
  }
  if (action != null && receipt.action != action) {
    throw StateError('R1 action mismatch.');
  }
  if (scope != null && receipt.scope != scope) {
    throw StateError('R1 scope mismatch.');
  }
  if (receipt.hash.isEmpty) throw StateError('R1 receipt hash is required.');
  return receipt;
}

Brain2R1Receipt requireVerifiedR1Allow(
  Brain2R1Receipt receipt, {
  String? action,
  String? scope,
  int minVersion = 2,
  String? authoritySource,
}) {
  final verified = verifyR1AuthorityReceipt(receipt);
  if (verified.signal != Brain2R1Signal.allow) {
    throw StateError('R1 blocked action with ${verified.signal.wire}.');
  }
  if (action != null && verified.action != action) {
    throw StateError('R1 action mismatch.');
  }
  if (scope != null && verified.scope != scope) {
    throw StateError('R1 scope mismatch.');
  }
  if (verified.version < minVersion) {
    throw StateError('R1 v$minVersion+ is required for this canonical write.');
  }
  if (authoritySource != null && verified.authoritySource != authoritySource) {
    throw StateError('R1 authority source mismatch.');
  }
  return verified;
}
