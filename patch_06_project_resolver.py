#!/usr/bin/env python3
from pathlib import Path
import shutil, sys, time
ROOT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd().resolve()
RES=ROOT/'lib/intelligence/project_resolver.dart'
IMP=ROOT/'lib/services/import_service.dart'
for p in (RES,IMP):
    if not p.exists(): raise SystemExit(f'ERROR: expected mobile project file not found: {p}')
stamp=str(int(time.time()))
def backup(p): shutil.copy2(p,p.with_name(p.name+f'.pre_project_resolver_{stamp}'))

resolver=r'''import '../core/identity.dart';

final RegExp _genericTitles = RegExp(
  r'^(new chat|chat|conversation|untitled(?: conversation| project)?|claude conversation \d+|gemini conversation \d+|conversation \d+)$',
  caseSensitive: false,
);

class ProjectFingerprint {
  final List<String> titleTerms;
  final List<String> contentTerms;
  final List<String> entityTerms;
  final List<String> allTerms;
  final bool genericTitle;
  const ProjectFingerprint({
    required this.titleTerms,
    required this.contentTerms,
    required this.entityTerms,
    required this.allTerms,
    required this.genericTitle,
  });
}

class ProjectResolution {
  final String projectId;
  final String name;
  final String slug;
  final List<String> aliases;
  final List<String> entityTerms;
  final double confidence;
  const ProjectResolution({
    required this.projectId,
    required this.name,
    required this.slug,
    required this.aliases,
    required this.entityTerms,
    required this.confidence,
  });
}

List<String> _keywords(String value, int limit) {
  const stop = <String>{
    'the','and','for','with','that','this','from','have','will','would','should','could','what','when','where','which','about','into','your','you','our','are','was','were','has','had','not','but','can','how','why','use','using','need','want'
  };
  final counts=<String,int>{};
  for(final token in normalizeText(value).toLowerCase().split(RegExp(r'[^a-z0-9.+#-]+'))){
    if(token.length<3||stop.contains(token)) continue;
    counts[token]=(counts[token]??0)+1;
  }
  final ranked=counts.entries.toList()..sort((a,b)=>b.value.compareTo(a.value)!=0?b.value.compareTo(a.value):a.key.compareTo(b.key));
  return ranked.take(limit).map((e)=>e.key).toList(growable:false);
}

bool _titleIsGeneric(String title){
  final value=normalizeText(title).replaceAll(RegExp(r'\s*\(\d{4}-\d{2}-\d{2}\)$'),'');
  return value.isEmpty||_genericTitles.hasMatch(value);
}

List<String> _extractEntities(String text){
  final matches=RegExp(r'\b(?:[A-Z][A-Za-z0-9.+#-]{2,})(?:\s+[A-Z][A-Za-z0-9.+#-]{2,}){0,3}\b').allMatches(text);
  final counts=<String,int>{};
  for(final match in matches){
    final value=normalizeText(match.group(0)??'').toLowerCase();
    if(value.length<4) continue;
    counts[value]=(counts[value]??0)+1;
  }
  final ranked=counts.entries.toList()..sort((a,b)=>b.value.compareTo(a.value)!=0?b.value.compareTo(a.value):a.key.compareTo(b.key));
  return ranked.take(16).map((e)=>e.key).toList(growable:false);
}

ProjectFingerprint fingerprintConversation({required String title, required List<Map<String,Object?>> messages}){
  final generic=_titleIsGeneric(title);
  final titleTerms=generic?<String>[]:_keywords(title,12);
  final userText=messages.where((m)=>'${m['role']}'=='user').map((m)=>'${m['text']??''}').join('\n');
  final allText=messages.map((m)=>'${m['text']??''}').join('\n');
  final contentTerms=_keywords('$userText\n$allText',28);
  final entityTerms=_extractEntities('$title\n$allText');
  final all=<String>{...titleTerms,...contentTerms};
  for(final entity in entityTerms) all.addAll(_keywords(entity,4));
  return ProjectFingerprint(titleTerms:titleTerms,contentTerms:contentTerms,entityTerms:entityTerms,allTerms:all.toList(),genericTitle:generic);
}

double _jaccard(Iterable<String> a,Iterable<String> b){
  final aa=a.map((e)=>normalizeText(e).toLowerCase()).where((e)=>e.isNotEmpty).toSet();
  final bb=b.map((e)=>normalizeText(e).toLowerCase()).where((e)=>e.isNotEmpty).toSet();
  if(aa.isEmpty||bb.isEmpty)return 0;
  return aa.intersection(bb).length/aa.union(bb).length;
}

double _tokenOverlap(Iterable<String> a,Iterable<String> b){
  final aa=a.map((e)=>normalizeText(e).toLowerCase()).where((e)=>e.isNotEmpty).toSet();
  final bb=b.map((e)=>normalizeText(e).toLowerCase()).where((e)=>e.isNotEmpty).toSet();
  if(aa.isEmpty||bb.isEmpty)return 0;
  return aa.intersection(bb).length/aa.length;
}

List<String> _projectTerms(Map<String,Object?> project){
  final aliases=((project['aliases'] as List?)??const[]).map((e)=>'$e').expand((e)=>_keywords(e,8));
  final entities=((project['entityTerms'] as List?)??const[]).map((e)=>'$e');
  final entityKeywords=entities.expand((e)=>_keywords(e,4));
  final tags=((project['tags'] as List?)??const[]).map((e)=>'$e');
  return <String>{...tags,...entityKeywords,...aliases,..._keywords('${project['summary']??''}',12),..._keywords('${project['name']??''}',8)}.toList();
}

double scoreProject(ProjectFingerprint fingerprint,Map<String,Object?> project){
  final terms=_projectTerms(project);
  final aliases=((project['aliases'] as List?)??const[]).map((e)=>'$e').toList();
  final entities=((project['entityTerms'] as List?)??const[]).map((e)=>'$e').toList();
  final normalized=fingerprint.allTerms.map((e)=>normalizeText(e).toLowerCase()).toSet();
  final exact=[...aliases,...entities].any((e)=>normalized.contains(normalizeText(e).toLowerCase()))?1.0:0.0;
  final titleScore=fingerprint.genericTitle?0:_tokenOverlap(fingerprint.titleTerms,terms);
  final contentScore=_jaccard(fingerprint.contentTerms.take(20),terms);
  final entityScore=_jaccard(fingerprint.entityTerms,entities);
  var aliasScore=0.0;
  for(final alias in aliases){
    final score=_tokenOverlap(fingerprint.contentTerms.take(12),_keywords(alias,8));
    if(score>aliasScore) aliasScore=score;
  }
  final evidence=[contentScore,_tokenOverlap(fingerprint.contentTerms.take(12),terms)].reduce((a,b)=>a>b?a:b);
  final score=(fingerprint.genericTitle?0:titleScore*.2)+evidence*.46+entityScore*.18+aliasScore*.08+exact*.12;
  return score.clamp(0,1).toDouble();
}

String _deriveProjectName(String title,ProjectFingerprint fingerprint){
  if(!fingerprint.genericTitle)return normalizeText(title).isEmpty?'Untitled project':normalizeText(title);
  final terms=fingerprint.contentTerms.take(4).toList();
  if(terms.isEmpty)return 'Unresolved conversation';
  return terms.map((term)=>term[0].toUpperCase()+term.substring(1)).join(' · ');
}

ProjectResolution resolveProject({
  required String title,
  required List<Map<String,Object?>> messages,
  List<Map<String,Object?>> existingProjects=const[],
}){
  final fingerprint=fingerprintConversation(title:title,messages:messages);
  final ranked=existingProjects.map((project)=>(project:project,score:scoreProject(fingerprint,project))).toList()
    ..sort((a,b)=>b.score.compareTo(a.score)!=0?b.score.compareTo(a.score):'${b.project['updatedAt']??''}'.compareTo('${a.project['updatedAt']??''}'));
  if(ranked.isNotEmpty){
    final best=ranked.first;
    final runner=ranked.length>1?ranked[1]:null;
    final overlap=fingerprint.contentTerms.where(_projectTerms(best.project).toSet().contains).length;
    final accepted=fingerprint.genericTitle
      ? best.score>=.14&&overlap>=3&&(runner==null||best.score>=runner.score+.08)
      : best.score>=.34;
    if(accepted){
      return ProjectResolution(
        projectId:'${best.project['id']}',
        name:'${best.project['name']}',
        slug:'${best.project['slug']??_slug('${best.project['name']}')}',
        aliases:<String>{...((best.project['aliases'] as List?)??const[]).map((e)=>'$e'),normalizeText(title)}.where((e)=>e.isNotEmpty).toList(),
        entityTerms:<String>{...((best.project['entityTerms'] as List?)??const[]).map((e)=>'$e'),...fingerprint.entityTerms}.toList(),
        confidence:best.score,
      );
    }
  }
  final name=_deriveProjectName(title,fingerprint);
  final key=<String>[...fingerprint.titleTerms,...fingerprint.contentTerms.take(12),...fingerprint.entityTerms.take(8)]..sort();
  final id=canonicalId('proj',['brain2-project',key.isEmpty?name.toLowerCase():key.join('|')]);
  return ProjectResolution(
    projectId:id,
    name:name,
    slug:_slug(name),
    aliases:<String>{normalizeText(title),name}.where((e)=>e.isNotEmpty).toList(),
    entityTerms:fingerprint.entityTerms,
    confidence:fingerprint.allTerms.length>=4?.82:.62,
  );
}

String _slug(String s){
  final x=normalizeText(s).toLowerCase().replaceAll(RegExp('[^a-z0-9]+'),'-').replaceAll(RegExp('^-+|-+\$'),'');
  return x.isEmpty?'untitled':x.substring(0,x.length>72?72:x.length);
}
'''
backup(RES); RES.write_text(resolver)
s=IMP.read_text()
if 'final knownProjects = await db.records(' not in s:
    anchor='    var conversationCount = 0;\n'
    if anchor not in s: raise SystemExit('ERROR: import project-cache anchor not found')
    s=s.replace(anchor,"    final knownProjects = await db.records('projects', orderBy: 'updated_at DESC');\n\n"+anchor,1)
old='      final resolution = resolveProject(title: title, messages: messages);'
if old in s:
    s=s.replace(old,"      final resolution = resolveProject(\n        title: title,\n        messages: messages,\n        existingProjects: knownProjects,\n      );",1)
# entityTerms field in project record.
anchor="        'aliases': aliases,\n        'resolverConfidence': resolution.confidence,"
if anchor in s and "'entityTerms':" not in s[s.find("final project =", s.find('final resolution')):s.find('// Web-parity performance rule', s.find('final resolution'))]:
    s=s.replace(anchor,"        'aliases': aliases,\n        'entityTerms': <String>{\n          ..._stringList(existingProject?['entityTerms']),\n          ...resolution.entityTerms,\n        }.toList(),\n        'resolverConfidence': resolution.confidence,",1)
# Keep cache updated so later conversations can resolve into projects created earlier in same import.
marker='      // Web-parity performance rule: one conversation is one durable atomic\n'
if marker in s and 'knownProjects.indexWhere' not in s:
    cache="""      final knownProjectIndex =\n          knownProjects.indexWhere((item) => '${item['id']}' == '${project['id']}');\n      if (knownProjectIndex >= 0) {\n        knownProjects[knownProjectIndex] = project;\n      } else {\n        knownProjects.add(project);\n      }\n\n"""
    s=s.replace(marker,cache+marker,1)
backup(IMP); IMP.write_text(s)
print('PASS patch_06_project_resolver')
print('  upgraded resolver to Web-style title/content/entity fingerprinting + existing-project scoring')
print('  importer now maintains an in-session project cache and persists entityTerms')
print('  current Projects UI is unchanged')
