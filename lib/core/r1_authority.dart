import 'identity.dart';

enum Brain2R1Signal { allow, deny, pause, revoke, requireTick, limitChanged }
extension Brain2R1SignalWire on Brain2R1Signal {
  String get wire => switch (this) {
    Brain2R1Signal.allow => 'ALLOW', Brain2R1Signal.deny => 'DENY', Brain2R1Signal.pause => 'PAUSE', Brain2R1Signal.revoke => 'REVOKE', Brain2R1Signal.requireTick => 'REQUIRE_TICK', Brain2R1Signal.limitChanged => 'LIMIT_CHANGED',
  };
}
class Brain2R1Receipt {
  final Brain2R1Signal signal; final String action; final String scope; final String authoritySource; final String reason; final List<String> evidenceRefs; final String issuedAt; final String hash;
  const Brain2R1Receipt({required this.signal,required this.action,required this.scope,required this.authoritySource,required this.reason,required this.evidenceRefs,required this.issuedAt,required this.hash});
  Map<String,Object?> toJson()=>{'format':'B2_R1_AUTHORITY','version':1,'signal':signal.wire,'action':action,'scope':scope,'authoritySource':authoritySource,'reason':reason,'evidenceRefs':evidenceRefs,'issuedAt':issuedAt,'hash':hash};
}
Brain2R1Signal parseR1Signal(Object? value)=>switch('${value??''}'.toUpperCase()){'ALLOW'=>Brain2R1Signal.allow,'DENY'=>Brain2R1Signal.deny,'PAUSE'=>Brain2R1Signal.pause,'REVOKE'=>Brain2R1Signal.revoke,'REQUIRE_TICK'=>Brain2R1Signal.requireTick,'LIMIT_CHANGED'=>Brain2R1Signal.limitChanged,_=>throw StateError('Invalid or missing R1 signal.')};
Brain2R1Receipt _issue({required Brain2R1Signal signal,required String action,required String scope,required String authoritySource,required String reason,Iterable<String> evidenceRefs=const []}){
  final refs=evidenceRefs.map((e)=>e.trim()).where((e)=>e.isNotEmpty).toSet().toList()..sort();
  final stable=<String,Object?>{'format':'B2_R1_AUTHORITY','version':1,'signal':signal.wire,'action':action,'scope':scope,'authoritySource':authoritySource,'reason':reason,'evidenceRefs':refs};
  return Brain2R1Receipt(signal:signal,action:action,scope:scope,authoritySource:authoritySource,reason:reason,evidenceRefs:refs,issuedAt:DateTime.now().toUtc().toIso8601String(),hash:sha256Hex(canonicalJson(stable)));
}
Brain2R1Receipt issueUserR1Allow({required String action,required String scope,String reason='Explicit user approval',Iterable<String> evidenceRefs=const []})=>_issue(signal:Brain2R1Signal.allow,action:action,scope:scope,authoritySource:'EXPLICIT_USER_ACTION',reason:reason,evidenceRefs:evidenceRefs);
Brain2R1Receipt issueVerifierR1({required Object? signal,required String action,required String scope,required String reason,Iterable<String> evidenceRefs=const []})=>_issue(signal:parseR1Signal(signal),action:action,scope:scope,authoritySource:'INDEPENDENT_VERIFIER',reason:reason,evidenceRefs:evidenceRefs);
Brain2R1Receipt requireR1Allow(Brain2R1Receipt receipt,{String? action,String? scope}){if(receipt.signal!=Brain2R1Signal.allow)throw StateError('R1 blocked action with ${receipt.signal.wire}.');if(action!=null&&receipt.action!=action)throw StateError('R1 action mismatch.');if(scope!=null&&receipt.scope!=scope)throw StateError('R1 scope mismatch.');if(receipt.hash.isEmpty)throw StateError('R1 receipt hash is required.');return receipt;}
