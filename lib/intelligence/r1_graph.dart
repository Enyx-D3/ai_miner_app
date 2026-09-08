import '../core/identity.dart';

const String brain2R1GraphVersion = 'B2_R1_GRAPH_V1';

enum R1VerificationState { verified, partial, conflicting, unverified, invalid, needsReverify }

class R1GraphNode {
  final String id;
  final String kind;
  final String? projectId;
  final String label;
  final String? sourceRecordId;
  final String? truthStatus;
  final R1VerificationState verificationState;
  final List<String> evidenceIds;
  final Map<String, Object?> metadata;
  const R1GraphNode({required this.id, required this.kind, this.projectId, required this.label, this.sourceRecordId, this.truthStatus, required this.verificationState, required this.evidenceIds, this.metadata = const {}});
  Map<String,Object?> toJson()=>{'id':id,'kind':kind,'projectId':projectId,'label':label,'sourceRecordId':sourceRecordId,'truthStatus':truthStatus,'verificationState':verificationState.name.toUpperCase(),'evidenceIds':evidenceIds,'metadata':metadata};
}

class R1GraphEdge {
  final String id, from, to, type;
  const R1GraphEdge({required this.id, required this.from, required this.to, required this.type});
  Map<String,Object?> toJson()=>{'id':id,'from':from,'to':to,'type':type};
}

class R1Graph {
  final List<R1GraphNode> nodes;
  final List<R1GraphEdge> edges;
  final String rootHash;
  const R1Graph({required this.nodes, required this.edges, required this.rootHash});
  Map<String,Object?> toJson()=>{'format':'B2_R1_GRAPH','version':1,'graphVersion':brain2R1GraphVersion,'nodes':nodes.map((e)=>e.toJson()).toList(),'edges':edges.map((e)=>e.toJson()).toList(),'rootHash':rootHash};
}

R1VerificationState _verification(Object? status) {
  switch ('$status') {
    case 'CURRENT': case 'HISTORICAL': case 'SUPERSEDED': return R1VerificationState.verified;
    case 'CONFLICTING': return R1VerificationState.conflicting;
    default: return R1VerificationState.unverified;
  }
}
String _atomKind(Object? kind) { final k='$kind'; if(k=='decision')return 'DECISION'; if(k=='constraint')return 'CONSTRAINT'; if(k=='task')return 'TASK'; if(k=='question')return 'OPEN_QUESTION'; return 'ATOM'; }
List<String> _unique(Iterable<Object?> values)=>(values.where((e)=>e!=null).map((e)=>'$e').where((e)=>e.isNotEmpty).toSet().toList()..sort());
R1GraphEdge _edge(String from,String to,String type)=>R1GraphEdge(id:canonicalId('r1e',[brain2R1GraphVersion,from,type,to]),from:from,to:to,type:type);

R1Graph projectR1Graph({required List<Map<String,Object?>> atoms, required List<Map<String,Object?>> truths, List<Map<String,Object?>> releaseGates=const []}) {
  final nodes=<R1GraphNode>[]; final edges=<R1GraphEdge>[]; final atomIds=<String,String>{}; final truthIds=<String,String>{};
  for(final atom in atoms){ final source='${atom['id']}'; final id=canonicalId('r1n',[brain2R1GraphVersion,'atom',source]); atomIds[source]=id; nodes.add(R1GraphNode(id:id,kind:_atomKind(atom['kind']),projectId:atom['projectId']?.toString(),label:'${atom['text']??''}',sourceRecordId:source,truthStatus:atom['truthStatus']?.toString(),verificationState:_verification(atom['truthStatus']),evidenceIds:_unique([atom['messageId'],atom['sourceId'],...(atom['provenance'] is List?(atom['provenance'] as List):const [])]),metadata:{'atomKind':atom['kind'],'canonicalSubject':atom['canonicalSubject'],'scope':atom['scope'],'value':atom['value'],'confidence':atom['confidence'],'hash':atom['hash']})); }
  for(final truth in truths){ final source='${truth['id']}'; final id=canonicalId('r1n',[brain2R1GraphVersion,'truth',source]); truthIds[source]=id; final kind='${truth['kind']}'=='decision'?'DECISION':'${truth['kind']}'=='constraint'?'CONSTRAINT':'TRUTH'; nodes.add(R1GraphNode(id:id,kind:kind,projectId:truth['projectId']?.toString(),label:'${truth['text']??''}',sourceRecordId:source,truthStatus:truth['status']?.toString(),verificationState:_verification(truth['status']),evidenceIds:_unique([truth['atomId'],truth['sourceId'],...(truth['evidenceAtomIds'] is List?(truth['evidenceAtomIds'] as List):const [])]),metadata:{'key':truth['key'],'canonicalSubject':truth['canonicalSubject'],'scope':truth['scope'],'value':truth['value'],'confidence':truth['confidence'],'relation':truth['relation'],'updatedAt':truth['updatedAt']})); }
  for(final atom in atoms){ final from=atomIds['${atom['id']}']!; final parent=atomIds['${atom['parentAtomId']}']; if(parent!=null)edges.add(_edge(from,parent,'DERIVED_FROM')); final tr=truthIds['${atom['truthRecordId']}']; if(tr!=null)edges.add(_edge(from,tr,'SUPPORTS')); final sup=truthIds['${atom['supersedesTruthId']}']; if(sup!=null)edges.add(_edge(from,sup,'SUPERSEDES')); }
  for(final truth in truths){ final from=truthIds['${truth['id']}']!; final a=atomIds['${truth['atomId']}']; if(a!=null)edges.add(_edge(from,a,'DERIVED_FROM')); if(truth['evidenceAtomIds'] is List){for(final e in truth['evidenceAtomIds'] as List){final n=atomIds['$e'];if(n!=null)edges.add(_edge(n,from,'SUPPORTS'));}} final sup=truthIds['${truth['supersedes']}'];if(sup!=null)edges.add(_edge(from,sup,'SUPERSEDES')); if(truth['relatedTruthIds'] is List){for(final e in truth['relatedTruthIds'] as List){final n=truthIds['$e'];if(n!=null){final rel='${truth['relation']}'=='CONTRADICTS'?'CONTRADICTS':'${truth['relation']}'=='SUPERSEDES'?'SUPERSEDES':'RELATED_TO';edges.add(_edge(from,n,rel));}}} }
  for(final gate in releaseGates){final key='${gate['id']}';final id=canonicalId('r1n',[brain2R1GraphVersion,'release_gate',key]);nodes.add(R1GraphNode(id:id,kind:'RELEASE_GATE',projectId:gate['projectId']?.toString(),label:'${gate['label']??key}',sourceRecordId:key,verificationState:R1VerificationState.unverified,evidenceIds:_unique(gate['evidenceNodeIds'] is List?gate['evidenceNodeIds'] as List:const []),metadata:{'gateKey':key}));if(gate['requires'] is List){for(final required in gate['requires'] as List){R1GraphNode? target;for(final n in nodes){if(n.id=='$required'||n.sourceRecordId=='$required'){target=n;break;}}if(target!=null)edges.add(_edge(id,target.id,'REQUIRES'));}}}
  nodes.sort((a,b)=>a.id.compareTo(b.id)); final byId=<String,R1GraphEdge>{for(final e in edges)e.id:e};final sorted=byId.values.toList()..sort((a,b)=>a.id.compareTo(b.id));final rootMaterial=[nodes.map((n)=>[n.id,n.kind,n.projectId??'',n.label,n.sourceRecordId??'',n.truthStatus??'',n.verificationState.name.toUpperCase(),n.evidenceIds]).toList(),sorted.map((e)=>[e.id,e.from,e.to,e.type]).toList()];final root=sha256Hex(canonicalJson(rootMaterial));return R1Graph(nodes:nodes,edges:sorted,rootHash:root);
}

R1GraphNode? getR1Node(R1Graph graph,String id){for(final n in graph.nodes){if(n.id==id||n.sourceRecordId==id)return n;}return null;}
List<R1GraphNode> r1Dependencies(R1Graph graph,String id){final node=getR1Node(graph,id);if(node==null)return const[];final ids=graph.edges.where((e)=>e.from==node.id&&(e.type=='DEPENDS_ON'||e.type=='REQUIRES')).map((e)=>e.to).toSet();return graph.nodes.where((n)=>ids.contains(n.id)).toList();}
String evaluateR1ReleaseGate(R1Graph graph,String gateId){final gate=getR1Node(graph,gateId);if(gate==null||gate.kind!='RELEASE_GATE')return 'UNKNOWN';final deps=r1Dependencies(graph,gate.id);if(deps.isEmpty)return 'UNKNOWN';if(deps.any((n)=>n.verificationState==R1VerificationState.invalid||n.truthStatus=='CONFLICTING'))return 'FAIL';if(deps.any((n)=>n.verificationState==R1VerificationState.needsReverify))return 'NEEDS_REVERIFY';if(deps.any((n)=>n.verificationState!=R1VerificationState.verified))return 'BLOCKED';return 'PASS';}
