import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/intelligence/r1_graph.dart';
import 'package:brain2_ai_miner_mobile/intelligence/r2_graph.dart';

void main() {
  test('R1 projects Current Truth and R2 stays evidence-bounded', () {
    final r1 = projectR1Graph(atoms: [
      {'id':'a1','messageId':'m1','conversationId':'c1','projectId':'p1','sourceId':'s1','kind':'fact','text':'Runtime works','truthStatus':'CURRENT','confidence':1.0,'provenance':['m1'],'hash':'h1','truthRecordId':'t1'}
    ], truths: [
      {'id':'t1','key':'runtime','projectId':'p1','atomId':'a1','text':'Runtime works','kind':'fact','status':'CURRENT','confidence':1.0,'updatedAt':'2026-09-08','evidenceAtomIds':['a1']}
    ]);
    final source = r1.nodes.firstWhere((n) => n.sourceRecordId == 't1');
    final r2 = buildR2Graph(r1, [
      {'kind':'HYPOTHESIS','statement':'Mobile may use the same route','derivedFrom':[source.id],'confidence':0.7,'status':'TESTABLE','requiredEvidence':['android-test'],'staleWhen':[]}
    ]);
    expect(r2.nodes, hasLength(1));
    expect(() => buildR2Graph(r1,[{'kind':'HYPOTHESIS','statement':'bad','derivedFrom':['missing'],'confidence':0.5}]), throwsStateError);
    expect(() => assertR2CannotMutateR1(r1, buildR2Graph(r1,[{'kind':'HYPOTHESIS','statement':'bad promotion','derivedFrom':[source.id],'confidence':0.5,'metadata':{'currentTruth':true}}])), throwsStateError);
  });
}
