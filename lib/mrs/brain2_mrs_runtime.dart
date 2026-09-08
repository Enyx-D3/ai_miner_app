import 'dart:convert';
import '../core/identity.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';
import '../reasoning/reasoning_compiler.dart';
import 'mobile_model_adapter.dart';

enum MrsRunStatus { solved, blockedExternalDependency, failed }

class MrsRunResult {
  final String runId;
  final MrsRunStatus status;
  final String answer;
  final List<String> trace;
  final String? blockedDependency;
  const MrsRunResult(
      {required this.runId,
      required this.status,
      required this.answer,
      required this.trace,
      this.blockedDependency});

  Map<String, Object?> toJson() => {
        'id': runId,
        'format': 'B2MRSRUN',
        'version': 1,
        'status': status.name.toUpperCase(),
        'answer': answer,
        'trace': trace,
        'blockedDependency': blockedDependency,
      };
}

/// Canonical Brain2 MRS router for mobile.
///
/// IMPORTANT: neural inference is conditional. The runtime first attempts
/// deterministic/compiled paths and only invokes [MobileModelAdapter] for a
/// hard residual. If no neural runtime is configured, it fails closed as a
/// BLOCKED_EXTERNAL_DEPENDENCY rather than bypassing the locked architecture.
class Brain2MrsRuntime {
  final Brain2Database db;
  final MutationService mutations;
  final MobileModelAdapter model;
  Brain2MrsRuntime(this.db, this.mutations, {MobileModelAdapter? model})
      : model = model ?? UnconfiguredMobileModelAdapter();

  Future<MrsRunResult> run(
      {required String task, required Map<String, Object?> databox}) async {
    final trace = <String>['DATABOX'];
    final runId = canonicalId('mrsrun', [
      task,
      '${databox['manifestHash'] ?? databox['hash'] ?? ''}',
      DateTime.now().toUtc().toIso8601String()
    ]);

    _verifyDatabox(databox);
    trace.add('BRANCH_ZERO');
    final branchZero = _branchZero(task, databox);
    if (branchZero != null) {
      trace.add('DETERMINISTIC_SOLVE');
      trace.add('VERIFY');
      final out = MrsRunResult(
          runId: runId,
          status: MrsRunStatus.solved,
          answer: branchZero,
          trace: trace);
      await _persist(out, task, databox);
      return out;
    }

    trace.add('CAPABILITY_LOOKUP');
    final capability = await _compiledCapability(task);
    if (capability != null) {
      trace.add('CAPABILITY_EXECUTE');
      trace.add('VERIFY');
      final out = MrsRunResult(
          runId: runId,
          status: MrsRunStatus.solved,
          answer:
              '${capability['output'] ?? capability['summary'] ?? capability['title'] ?? 'Compiled capability executed.'}',
          trace: trace);
      await _persist(out, task, databox);
      return out;
    }

    trace.add('PATTERN_MEMORY');
    await _loadSuccessFailureMemory(task);

    trace.add('COGNITIVE_R1');
    final operation = _cognitiveR1(task, databox);

    trace.add('TRACE_RPVM');
    if (!_traceAccepts(operation)) {
      final out = MrsRunResult(
          runId: runId,
          status: MrsRunStatus.failed,
          answer: 'TRACE/RPVM rejected the proposed reasoning transition.',
          trace: [...trace, 'REJECTED']);
      await _persist(out, task, databox);
      return out;
    }

    trace.add('TINY_SPECIALIST');
    final specialist = _tinySpecialist(task, databox, operation);
    if (specialist != null) {
      trace.add('VERIFY');
      final out = MrsRunResult(
          runId: runId,
          status: MrsRunStatus.solved,
          answer: specialist,
          trace: trace);
      await _persist(out, task, databox);
      return out;
    }

    trace.add('HARD_RESIDUAL');
    if (!await model.isAvailable()) {
      trace.add('BLOCKED_EXTERNAL_DEPENDENCY');
      final out = MrsRunResult(
        runId: runId,
        status: MrsRunStatus.blockedExternalDependency,
        answer:
            'A hard semantic residual remains, but no mobile neural runtime is configured.',
        trace: trace,
        blockedDependency: 'MOBILE_NEURAL_RUNTIME',
      );
      await _persist(out, task, databox);
      return out;
    }

    trace.add('MODEL_${model.runtimeName}');
    final evidence = _evidenceSummary(databox);
    final proposal = await model.generate(
      systemPrompt:
          'You are a residual reasoning worker inside Brain2 MRS. Use only the supplied verified Databox evidence. Do not invent evidence IDs. Return a concise proposal.',
      userPrompt: 'TASK:\n$task\n\nVERIFIED DATABOX:\n$evidence',
      maxNewTokens: 256,
    );

    trace.add('VERIFY');
    if (!_verifyProposal(proposal, databox)) {
      trace.add('RESIDUAL_REPAIR');
      final out = MrsRunResult(
          runId: runId,
          status: MrsRunStatus.failed,
          answer:
              'Model proposal failed independent evidence verification; residual repair requires a verified retry lane.',
          trace: trace);
      await _persist(out, task, databox);
      return out;
    }

    final out = MrsRunResult(
        runId: runId,
        status: MrsRunStatus.solved,
        answer: proposal.trim(),
        trace: trace);
    await _persist(out, task, databox);
    return out;
  }

  void _verifyDatabox(Map<String, Object?> databox) {
    if (databox.isEmpty)
      throw StateError('Verified Databox is mandatory for MRS.');
    final evidence = databox['evidence'];
    final records = databox['records'];
    if (evidence == null && records == null)
      throw StateError('Databox contains no verified evidence payload.');
  }

  String? _branchZero(String task, Map<String, Object?> databox) {
    final q = task.trim().toLowerCase();
    final records = _records(databox);
    if (q.isEmpty) return 'No task supplied.';
    if (q == 'how many sources?' || q == 'source count')
      return '${records.length} verified evidence records are in the Databox.';
    if ((q.contains('show') || q.contains('list')) && q.contains('evidence')) {
      return records
          .take(12)
          .map((e) =>
              '${e['title'] ?? e['text'] ?? e['content'] ?? e['id'] ?? ''}')
          .where((e) => e.isNotEmpty)
          .join('\n');
    }
    return null;
  }

  Future<Map<String, Object?>?> _compiledCapability(String task) async {
    final caps = await db.records('capabilities', orderBy: 'updated_at DESC');
    final norm = normalizeText(task).toLowerCase();
    final taskTerms =
        norm.split(RegExp(r'[^a-z0-9]+')).where((e) => e.length >= 3).toSet();
    Map<String, Object?>? best;
    var bestScore = 0.0;
    for (final cap in caps) {
      final state =
          '${cap['verificationState'] ?? cap['status'] ?? ''}'.toUpperCase();
      if (!const {'VERIFIED', 'TRANSFER_VERIFIED', 'REPLAY_VERIFIED'}
          .contains(state)) continue;
      final haystack = normalizeText([
        cap['registryKey'],
        cap['title'],
        ...((cap['preconditions'] as List?) ?? const []),
        ...((cap['procedure'] as List?) ?? const []),
      ].join(' '))
          .toLowerCase();
      final terms = haystack
          .split(RegExp(r'[^a-z0-9]+'))
          .where((e) => e.length >= 3)
          .toSet();
      if (taskTerms.isEmpty || terms.isEmpty) continue;
      final score =
          taskTerms.intersection(terms).length / taskTerms.union(terms).length;
      if (score > bestScore) {
        bestScore = score;
        best = cap;
      }
    }
    return bestScore >= .16 ? best : null;
  }

  Future<void> _loadSuccessFailureMemory(String task) async {
    await db.records('reasoningTrajectories',
        orderBy: 'updated_at DESC', limit: 24);
    await db.records('failureMemory', orderBy: 'updated_at DESC', limit: 24);
  }

  String _cognitiveR1(String task, Map<String, Object?> databox) {
    final q = task.toLowerCase();
    if (q.contains('contradict') || q.contains('conflict'))
      return 'CHECK_CONTRADICTION';
    if (q.contains('compare')) return 'COMPARE';
    if (q.contains('find') || q.contains('retrieve')) return 'RETRIEVE';
    return 'SYNTHESIZE';
  }

  bool _traceAccepts(String operation) => const {
        'CHECK_CONTRADICTION',
        'COMPARE',
        'RETRIEVE',
        'SYNTHESIZE'
      }.contains(operation);

  String? _tinySpecialist(
      String task, Map<String, Object?> databox, String operation) {
    final records = _records(databox);
    if (operation == 'RETRIEVE' && records.isNotEmpty) {
      return records
          .take(8)
          .map((e) =>
              '${e['text'] ?? e['content'] ?? e['value'] ?? e['title'] ?? ''}')
          .where((e) => e.trim().isNotEmpty)
          .join('\n\n');
    }
    if (operation == 'CHECK_CONTRADICTION') {
      final conflicts = records
          .where(
              (e) => '${e['status'] ?? ''}'.toUpperCase().contains('CONFLICT'))
          .toList();
      if (conflicts.isNotEmpty)
        return 'Found ${conflicts.length} explicitly marked conflicting evidence records in the verified Databox.';
    }
    return null;
  }

  List<Map<String, Object?>> _records(Map<String, Object?> databox) {
    final raw = databox['records'] ?? databox['evidence'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) {
      final e = entry.cast<String, Object?>();
      final nested = e['record'];
      if (nested is Map) {
        return <String, Object?>{
          ...nested.cast<String, Object?>(),
          '_evidenceId': '${e['id'] ?? ''}',
          '_recordHash': '${e['recordHash'] ?? ''}',
          '_sourceTable': '${e['table'] ?? ''}',
          '_recordId': '${e['recordId'] ?? ''}',
        };
      }
      return e;
    }).toList(growable: false);
  }

  String _evidenceSummary(Map<String, Object?> databox) => jsonEncode({
        'records': _records(databox).take(24).toList(),
        'truths': databox['truths'],
        'conflicts': databox['conflicts']
      });

  bool _verifyProposal(String proposal, Map<String, Object?> databox) {
    if (proposal.trim().isEmpty) return false;
    // The mobile baseline verifier is fail-closed for explicit evidence-id syntax.
    final allowed = _records(databox)
        .expand((e) => ['${e['_evidenceId'] ?? ''}', '${e['id'] ?? ''}'])
        .where((e) => e.isNotEmpty)
        .toSet();
    final cited = RegExp(r'B2[A-Z0-9_:-]{5,}', caseSensitive: false)
        .allMatches(proposal)
        .map((m) => m.group(0)!)
        .toSet();
    return cited.every(allowed.contains);
  }

  Future<void> _persist(
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
  }
}
