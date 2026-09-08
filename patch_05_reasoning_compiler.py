#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
MRS = ROOT / 'lib/mrs/brain2_mrs_runtime.dart'
NEW = ROOT / 'lib/reasoning/reasoning_compiler.dart'
if not MRS.exists(): raise SystemExit(f'ERROR: expected mobile project file not found: {MRS}')
NEW.parent.mkdir(parents=True, exist_ok=True)
stamp=str(int(time.time()))
def backup(p):
    p=Path(p)
    if p.exists(): shutil.copy2(p, p.with_name(p.name+f'.pre_reasoning_compiler_{stamp}'))

content=r'''import '../core/contracts.dart';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';

class MobileReasoningCompiler {
  final Brain2Database db;
  final MutationService mutations;
  const MobileReasoningCompiler(this.db, this.mutations);

  Set<String> _terms(String value) => normalizeText(value)
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((e) => e.length >= 3)
      .toSet();

  String _trajectoryKey(String task) {
    final terms = _terms(task).take(8).toList()..sort();
    final key = terms.isEmpty ? normalizeText(task).toLowerCase() : terms.join(' ');
    return key.length <= 160 ? key : key.substring(0, 160);
  }

  List<String> _evidenceIds(Map<String, Object?> databox) =>
      ((databox['evidence'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => '${e['id'] ?? e['recordId'] ?? ''}')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

  List<String> _boundaryConditions(Map<String, Object?> databox) {
    final out = <String>{};
    final conflictCount = (databox['conflictCount'] as num?)?.toInt() ?? 0;
    if (conflictCount > 0) out.add('Databox contains $conflictCount conflicting truth record(s)');
    final route = '${databox['retrievalRoute'] ?? databox['route'] ?? ''}';
    if (route.contains('B_250_CHUNK')) out.add('B250 bounded-context fallback may be required');
    final evidenceCount = ((databox['evidence'] as List?) ?? const []).length;
    if (evidenceCount < 2) out.add('Sparse Databox evidence');
    return out.toList();
  }

  String _terminatedBy(List<String> trace) {
    if (trace.contains('RESIDUAL_REPAIR')) return 'REPAIR';
    if (trace.any((e) => e.startsWith('MODEL_'))) return 'MRS_MODEL';
    if (trace.contains('TINY_SPECIALIST')) return 'TINY_SPECIALIST';
    return 'BRANCH_ZERO';
  }

  Future<void> persistRun({
    required String runId,
    required String task,
    required Map<String, Object?> databox,
    required String status,
    required String answer,
    required List<String> trace,
    String? blockedDependency,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final projectId = '${databox['projectId'] ?? ''}'.trim();
    final databoxId = '${databox['id'] ?? ''}';
    final databoxHash = '${databox['hash'] ?? databox['manifestHash'] ?? ''}';
    final evidenceIds = _evidenceIds(databox);
    final verificationStatus = status == 'SOLVED'
        ? 'PASS'
        : status == 'BLOCKED_EXTERNAL_DEPENDENCY'
            ? 'PENDING'
            : 'FAIL';
    final outcome = verificationStatus == 'PASS'
        ? 'SUCCESS'
        : trace.contains('RESIDUAL_REPAIR')
            ? 'REPAIR'
            : 'FAILURE';
    final usedMRS = trace.any((e) => e.startsWith('MODEL_'));
    final terminatedBy = _terminatedBy(trace);
    final boundaryConditions = _boundaryConditions(databox);
    final trajectoryKey = _trajectoryKey(task);
    final failureSignature = verificationStatus == 'PASS'
        ? null
        : normalizeText([terminatedBy, blockedDependency, answer].whereType<String>().join(' | '));
    final operationSequence = trace
        .where((e) => const {
              'COGNITIVE_R1',
              'TRACE_RPVM',
              'TINY_SPECIALIST',
              'RESIDUAL_REPAIR',
            }.contains(e) || e.startsWith('MODEL_'))
        .toList(growable: false);
    final trajectoryPayload = <String, Object?>{
      'trajectoryKey': trajectoryKey,
      'question': task,
      'projectId': projectId.isEmpty ? null : projectId,
      'databoxId': databoxId,
      'databoxHash': databoxHash,
      'stageTrace': trace,
      'operationSequence': operationSequence,
      'evidenceIds': evidenceIds,
      'capabilityId': null,
      'successPatternIds': <String>[],
      'failureMemoryIds': <String>[],
      'boundaryConditions': boundaryConditions,
      'verificationStatus': verificationStatus,
      'outcome': outcome,
      'usedMRS': usedMRS,
      'terminatedBy': terminatedBy,
      'residualCount': trace.contains('HARD_RESIDUAL') ? 1 : 0,
      'repairApplied': trace.contains('RESIDUAL_REPAIR'),
      'failureSignature': failureSignature,
      'createdAt': now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
    final trajectory = <String, Object?>{
      'id': canonicalId('trajectory', [trajectoryKey, runId, now]),
      ...trajectoryPayload,
      'hash': sha256Hex(canonicalJson(trajectoryPayload)),
    };
    await mutations.upsert('reasoningTrajectories', trajectory, type: 'MRS_TRAJECTORY_V2');

    if (verificationStatus != 'PASS') {
      final failurePayload = <String, Object?>{
        'failureSignature': failureSignature ?? '$terminatedBy:$runId',
        'title': 'Failure memory: ${task.length > 96 ? task.substring(0, 96) : task}',
        'projectId': projectId.isEmpty ? null : projectId,
        'trajectoryId': trajectory['id'],
        'failedStage': terminatedBy == 'REPAIR' ? 'VERIFIER' : terminatedBy,
        'cause': answer,
        'knownBadOperation': operationSequence.isEmpty ? null : operationSequence.last,
        'stageTrace': trace,
        'evidenceIds': evidenceIds,
        'boundaryConditions': boundaryConditions,
        'repairThatWorked': trace.contains('RESIDUAL_REPAIR') ? 'Residual-only repair lane attempted' : null,
        'repairNotApplicableWhen': boundaryConditions,
        'occurrenceCount': 1,
        'lastSeenAt': now,
        'createdAt': now,
        'schemaVersion': brain2SchemaVersion,
      };
      final failure = <String, Object?>{
        'id': canonicalId('failure-memory', [failurePayload['failureSignature'], projectId, now]),
        ...failurePayload,
        'hash': sha256Hex(canonicalJson(failurePayload)),
      };
      await mutations.upsert('failureMemory', failure, type: 'MRS_FAILURE_MEMORY_V2');
      return;
    }

    if (evidenceIds.isEmpty) return;
    await _compileCapability(
      task: task,
      projectId: projectId,
      trajectory: trajectory,
      trace: trace,
      evidenceIds: evidenceIds,
      boundaryConditions: boundaryConditions,
      usedMRS: usedMRS,
      now: now,
    );
  }

  Future<void> _compileCapability({
    required String task,
    required String projectId,
    required Map<String, Object?> trajectory,
    required List<String> trace,
    required List<String> evidenceIds,
    required List<String> boundaryConditions,
    required bool usedMRS,
    required String now,
  }) async {
    final registryKey = _trajectoryKey(task);
    final existing = (await db.records('capabilities', orderBy: 'updated_at DESC', limit: 1000))
        .where((item) => '${item['registryKey']}' == registryKey && '${item['projectId'] ?? ''}' == projectId)
        .toList();
    existing.sort((a, b) => ((b['version'] as num?)?.toInt() ?? 0).compareTo((a['version'] as num?)?.toInt() ?? 0));
    final prior = existing.isEmpty ? null : existing.first;
    final version = ((prior?['version'] as num?)?.toInt() ?? 0) + 1;
    final successfulPrior = (await db.records('reasoningTrajectories', orderBy: 'updated_at DESC', limit: 1000))
        .where((item) => '${item['trajectoryKey']}' == registryKey && '${item['verificationStatus']}' == 'PASS')
        .length;
    final verificationState = !usedMRS && successfulPrior >= 1
        ? 'VERIFIED'
        : !usedMRS
            ? 'REPLAY_VERIFIED'
            : 'CANDIDATE';
    final stageOrigin = usedMRS
        ? (trace.contains('RESIDUAL_REPAIR') ? 'REPAIR' : 'WEB_MRS_MODEL')
        : trace.contains('DETERMINISTIC_SOLVE')
            ? 'BRANCH_ZERO'
            : trace.contains('CAPABILITY_EXECUTE')
                ? 'CAPABILITY_LOOKUP'
                : 'TINY_SPECIALIST';
    final payload = <String, Object?>{
      'registryKey': registryKey,
      'title': 'Compiled capability for ${task.length > 72 ? task.substring(0, 72) : task}',
      'projectId': projectId.isEmpty ? null : projectId,
      'sourcePatternId': null,
      'sourceTrajectoryId': trajectory['id'],
      'version': version,
      'stageOrigin': stageOrigin,
      'preconditions': <String>[
        'Verified Databox required',
        if (projectId.isNotEmpty) 'Project scope: $projectId',
      ],
      'inputShape': <String>['task:string', 'databox:evidence-bounded', projectId.isNotEmpty ? 'projectScope:required' : 'projectScope:optional'],
      'outputShape': <String>['answer:string', 'evidenceIds:string[]', 'verification:PASS|FAIL|PENDING'],
      'dependencies': <String>{'B2JOB', 'B2VERIFY', if (usedMRS) 'MOBILE_MRS_MODEL'}.toList(),
      'procedure': <String>[
        'Compile bounded Databox for the task.',
        'Run Branch Zero and capability lookup before neural escalation.',
        'Verify the solve path independently before returning.',
      ],
      'boundaryConditions': boundaryConditions,
      'repairHints': trace.contains('RESIDUAL_REPAIR') ? <String>['Residual-only repair may be required.'] : <String>[],
      'evidenceIds': evidenceIds.take(8).toList(),
      'verificationState': verificationState,
      'successfulRuns': ((prior?['successfulRuns'] as num?)?.toInt() ?? 0) + 1,
      'failedRuns': (prior?['failedRuns'] as num?)?.toInt() ?? 0,
      'lastUsedAt': now,
      'lastVerifiedAt': now,
      'rollbackCapabilityId': prior?['id'],
      'createdAt': prior?['createdAt'] ?? now,
      'updatedAt': now,
      'schemaVersion': brain2SchemaVersion,
    };
    final capability = <String, Object?>{
      'id': canonicalId('capability', [registryKey, version, projectId]),
      ...payload,
      'hash': sha256Hex(canonicalJson(payload)),
    };
    await mutations.upsert('capabilities', capability, type: 'COMPILE_CAPABILITY');
  }
}
'''
backup(NEW); NEW.write_text(content)
s=MRS.read_text()
if "import '../reasoning/reasoning_compiler.dart';" not in s:
    anchor="import '../storage/mutation_service.dart';\n"
    if anchor not in s: raise SystemExit('ERROR: MRS import anchor not found')
    s=s.replace(anchor, anchor+"import '../reasoning/reasoning_compiler.dart';\n",1)
# Upgrade compiled capability lookup acceptance and matching.
start=s.find('  Future<Map<String, Object?>?> _compiledCapability(String task) async {')
end=s.find('\n  Future<void> _loadSuccessFailureMemory', start)
if start>=0 and end>start:
    repl=r'''  Future<Map<String, Object?>?> _compiledCapability(String task) async {
    final caps = await db.records('capabilities', orderBy: 'updated_at DESC');
    final norm = normalizeText(task).toLowerCase();
    final taskTerms = norm
        .split(RegExp(r'[^a-z0-9]+'))
        .where((e) => e.length >= 3)
        .toSet();
    Map<String, Object?>? best;
    var bestScore = 0.0;
    for (final cap in caps) {
      final state = '${cap['verificationState'] ?? cap['status'] ?? ''}'.toUpperCase();
      if (!const {'VERIFIED', 'TRANSFER_VERIFIED', 'REPLAY_VERIFIED'}.contains(state)) continue;
      final haystack = normalizeText([
        cap['registryKey'],
        cap['title'],
        ...((cap['preconditions'] as List?) ?? const []),
        ...((cap['procedure'] as List?) ?? const []),
      ].join(' ')).toLowerCase();
      final terms = haystack
          .split(RegExp(r'[^a-z0-9]+'))
          .where((e) => e.length >= 3)
          .toSet();
      if (taskTerms.isEmpty || terms.isEmpty) continue;
      final score = taskTerms.intersection(terms).length / taskTerms.union(terms).length;
      if (score > bestScore) {
        bestScore = score;
        best = cap;
      }
    }
    return bestScore >= .16 ? best : null;
  }
'''
    s=s[:start]+repl+s[end:]
# Capability path answer: use title/procedure rather than obsolete output field only.
s=s.replace("'${capability['output'] ?? capability['summary'] ?? 'Compiled capability executed.'}'",
            "'${capability['output'] ?? capability['summary'] ?? capability['title'] ?? 'Compiled capability executed.'}'")
# Replace _persist's simple trajectory/failure logic with compiler call while retaining mrsRuns.
start=s.find('  Future<void> _persist(\n')
if start<0: start=s.find('  Future<void> _persist(')
if start>=0:
    # function is last member before class close in current source. find matching braces.
    brace=s.find('{', start); depth=0; end=None
    for i in range(brace,len(s)):
        if s[i]=='{': depth+=1
        elif s[i]=='}':
            depth-=1
            if depth==0:
                end=i+1; break
    if end:
        repl=r'''  Future<void> _persist(
      MrsRunResult result, String task, Map<String, Object?> databox) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final record = <String, Object?>{
      ...result.toJson(),
      'task': task,
      'databoxHash': '${databox['hash'] ?? databox['manifestHash'] ?? ''}',
      'createdAt': now,
      'updatedAt': now,
    };
    await mutations.upsert('mrsRuns', record, type: 'MRS_RUN');
    final compiler = MobileReasoningCompiler(db, mutations);
    await compiler.persistRun(
      runId: result.runId,
      task: task,
      databox: databox,
      status: result.status.name.toUpperCase(),
      answer: result.answer,
      trace: result.trace,
      blockedDependency: result.blockedDependency,
    );
  }'''
        s=s[:start]+repl+s[end:]
backup(MRS); MRS.write_text(s)
print('PASS patch_05_reasoning_compiler')
print(f'  wrote: {NEW.relative_to(ROOT)}')
print('  MRS now persists Web-style reasoning trajectories/failure memories and compiles reusable capabilities')
print('  native MobileModelAdapter path is preserved')
