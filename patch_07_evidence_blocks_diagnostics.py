#!/usr/bin/env python3
from pathlib import Path
import shutil, sys, time
ROOT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd().resolve()
PIPE=ROOT/'lib/intelligence/mobile_intelligence_pipeline.dart'
MEM=ROOT/'lib/ui/screens/memory_screen.dart'
EVID=ROOT/'lib/intelligence/evidence_block_engine.dart'
DIAG=ROOT/'lib/intelligence/memory_diagnostics.dart'
for p in (PIPE,MEM):
    if not p.exists(): raise SystemExit(f'ERROR: expected mobile project file not found: {p}')
stamp=str(int(time.time()))
def backup(p):
    p=Path(p)
    if p.exists(): shutil.copy2(p,p.with_name(p.name+f'.pre_evidence_diag_{stamp}'))

evidence=r'''import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class MobileEvidenceBlockEngine {
  final Brain2Database db;
  final MutationService mutations;
  const MobileEvidenceBlockEngine(this.db,this.mutations);

  int _blockNumber(Object? sequence){
    final n=(sequence as num?)?.toInt()??int.tryParse('${sequence??0}')??0;
    return n<0?0:n~/250;
  }

  Future<List<Map<String,Object?>>> buildProject(String projectId) async{
    final conversations=await db.recordsByJsonFields('conversations',{'projectId':projectId},newestFirst:false,limit:10000);
    final out=<Map<String,Object?>>[];
    for(final conversation in conversations){
      final conversationId='${conversation['id']}';
      final sourceId='${conversation['sourceId']??''}';
      final messages=await db.recordsByJsonFields('messages',{'conversationId':conversationId},newestFirst:false,limit:100000);
      messages.sort((a,b)=>((a['sequence'] as num?)?.toInt()??0).compareTo((b['sequence'] as num?)?.toInt()??0));
      final atoms=await db.recordsByJsonFields('atoms',{'conversationId':conversationId},newestFirst:false,limit:100000);
      final atomsByMessage=<String,List<Map<String,Object?>>>{};
      for(final atom in atoms){atomsByMessage.putIfAbsent('${atom['messageId']}',()=>[]).add(atom);}
      final grouped=<int,List<Map<String,Object?>>>{};
      for(final message in messages){grouped.putIfAbsent(_blockNumber(message['sequence']),()=>[]).add(message);}
      for(final entry in grouped.entries){
        final blockNumber=entry.key; final blockMessages=entry.value;
        final messageIds=blockMessages.map((m)=>'${m['id']}').where((e)=>e.isNotEmpty).toList();
        final atomIds=<String>[];
        for(final id in messageIds){atomIds.addAll((atomsByMessage[id]??const[]).map((a)=>'${a['id']}').where((e)=>e.isNotEmpty));}
        final seqs=blockMessages.map((m)=>(m['sequence'] as num?)?.toInt()??0).toList();
        final firstSequence=seqs.isEmpty?0:seqs.reduce((a,b)=>a<b?a:b);
        final lastSequence=seqs.isEmpty?0:seqs.reduce((a,b)=>a>b?a:b);
        final byteEstimate=blockMessages.fold<int>(0,(sum,m)=>sum+'${m['text']??''}'.codeUnits.length);
        final payload=<String,Object?>{
          'conversationId':conversationId,'projectId':projectId,'sourceId':sourceId,'blockNumber':blockNumber,
          'firstSequence':firstSequence,'lastSequence':lastSequence,'messageIds':messageIds,'atomIds':atomIds,
          'byteEstimate':byteEstimate,'updatedAt':DateTime.now().toUtc().toIso8601String(),'schemaVersion':brain2SchemaVersion,
        };
        out.add(<String,Object?>{
          'id':canonicalId('evidence-block',[conversationId,blockNumber]),...payload,
          'hash':sha256Hex(canonicalJson(<String,Object?>{'conversationId':conversationId,'blockNumber':blockNumber,'messageIds':messageIds,'atomIds':atomIds,'firstSequence':firstSequence,'lastSequence':lastSequence})),
        });
      }
    }
    return out;
  }

  Future<List<Map<String,Object?>>> refreshProject(String projectId) async{
    if(projectId.isEmpty)return const[];
    final blocks=await buildProject(projectId);
    const batchSize=128;
    for(var i=0;i<blocks.length;i+=batchSize){
      final end=(i+batchSize).clamp(0,blocks.length).toInt();
      await mutations.upsertBatch({'evidenceBlocks':blocks.sublist(i,end)},type:'EVIDENCE_BLOCK_REFRESH',primaryTable:'evidenceBlocks',entityType:'projects',entityId:'$projectId:$i');
      if((i~/batchSize)%4==3)await Future<void>.delayed(Duration.zero);
    }
    return blocks;
  }
}
'''

diag=r'''import '../core/identity.dart';
import '../storage/brain2_database.dart';
import 'canonical_truth.dart';

class MemoryDiagnosticReport {
  final String memoryRoot;
  final String currentTruthRoot;
  final String sourceEvidenceRoot;
  final int messages;
  final int truths;
  final int currentTruths;
  final int conflicts;
  final int evidenceBlocks;
  final int strictBlockedAtoms;
  const MemoryDiagnosticReport({required this.memoryRoot,required this.currentTruthRoot,required this.sourceEvidenceRoot,required this.messages,required this.truths,required this.currentTruths,required this.conflicts,required this.evidenceBlocks,required this.strictBlockedAtoms});
  String get summary=>'Truth root ${currentTruthRoot.substring(0,12)}… · Evidence root ${sourceEvidenceRoot.substring(0,12)}… · $currentTruths current · $conflicts conflicts · $evidenceBlocks evidence blocks · $strictBlockedAtoms strict-blocked atoms';
}

class MobileMemoryDiagnostics {
  final Brain2Database db;
  const MobileMemoryDiagnostics(this.db);
  Future<MemoryDiagnosticReport> verify() async{
    final root=await db.memoryRoot();
    final messages=await db.records('messages',orderBy:'updated_at ASC');
    final truths=await db.records('truths',orderBy:'updated_at ASC');
    final atoms=await db.records('atoms',orderBy:'updated_at ASC');
    final current=truths.where((t)=>'${t['status']}'=='CURRENT').toList();
    final conflicts=truths.where((t)=>'${t['status']}'=='CONFLICTING').length;
    final strictBlocked=atoms.where((a)=>a['strictTruthBlocked']==true).length;
    return MemoryDiagnosticReport(
      memoryRoot:root,
      currentTruthRoot:buildCurrentTruthRoot(current),
      sourceEvidenceRoot:buildSourceEvidenceRoot(messages),
      messages:messages.length,
      truths:truths.length,
      currentTruths:current.length,
      conflicts:conflicts,
      evidenceBlocks:await db.total('evidenceBlocks'),
      strictBlockedAtoms:strictBlocked,
    );
  }
}
'''
for p,c in ((EVID,evidence),(DIAG,diag)): backup(p); p.write_text(c)

s=PIPE.read_text()
if "import 'evidence_block_engine.dart';" not in s:
    anchor="import 'intelligence_layer.dart';\n" if "import 'intelligence_layer.dart';\n" in s else "import 'atomization_stack.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: pipeline import anchor not found')
    s=s.replace(anchor,anchor+"import 'evidence_block_engine.dart';\n",1)
if 'late final MobileEvidenceBlockEngine evidenceBlocks' not in s:
    anchor='  late final MobileTruthBatchEngine batchTruths = MobileTruthBatchEngine(db);\n'
    if anchor not in s: raise SystemExit('ERROR: pipeline field anchor not found')
    s=s.replace(anchor,anchor+'  late final MobileEvidenceBlockEngine evidenceBlocks = MobileEvidenceBlockEngine(db, mutations);\n',1)
# Refresh evidence blocks before project intelligence snapshot so retrieval/provenance sees them.
anchor='  Future<void> refreshProjectSnapshots(String projectId) async {\n    if (projectId.isEmpty) return;\n'
if anchor in s and 'await evidenceBlocks.refreshProject(projectId);' not in s:
    s=s.replace(anchor,anchor+'    await evidenceBlocks.refreshProject(projectId);\n',1)
backup(PIPE); PIPE.write_text(s)

s=MEM.read_text()
if "import '../../intelligence/memory_diagnostics.dart';" not in s:
    anchor="import '../../app/brain2_controller.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: MemoryScreen import anchor not found')
    s=s.replace(anchor,anchor+"import '../../intelligence/memory_diagnostics.dart';\n",1)
# Add a current-style diagnostic button before destructive reset divider.
anchor='                const Divider(height: 28),\n'
if anchor in s and 'Verify truth & evidence integrity' not in s:
    block="""                OutlinedButton.icon(\n                  onPressed: busy\n                      ? null\n                      : () => _run(() async {\n                            final report =\n                                await MobileMemoryDiagnostics(widget.c.db).verify();\n                            return report.summary;\n                          }),\n                  icon: const Icon(Icons.verified_outlined),\n                  label: const Text('Verify truth & evidence integrity'),\n                ),\n                const SizedBox(height: 8),\n"""
    s=s.replace(anchor,block+anchor,1)
backup(MEM); MEM.write_text(s)
print('PASS patch_07_evidence_blocks_diagnostics')
print(f'  wrote: {EVID.relative_to(ROOT)}')
print(f'  wrote: {DIAG.relative_to(ROOT)}')
print('  project refresh now generates 250-message evidence blocks')
print('  Memory screen receives one matching-style truth/evidence integrity action')
