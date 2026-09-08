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
  const MemoryDiagnosticReport(
      {required this.memoryRoot,
      required this.currentTruthRoot,
      required this.sourceEvidenceRoot,
      required this.messages,
      required this.truths,
      required this.currentTruths,
      required this.conflicts,
      required this.evidenceBlocks,
      required this.strictBlockedAtoms});
  String get summary =>
      'Truth root ${currentTruthRoot.substring(0, 12)}… · Evidence root ${sourceEvidenceRoot.substring(0, 12)}… · $currentTruths current · $conflicts conflicts · $evidenceBlocks evidence blocks · $strictBlockedAtoms strict-blocked atoms';
}

class MobileMemoryDiagnostics {
  final Brain2Database db;
  const MobileMemoryDiagnostics(this.db);
  Future<MemoryDiagnosticReport> verify() async {
    final root = await db.memoryRoot();
    final messages = await db.records('messages', orderBy: 'updated_at ASC');
    final truths = await db.records('truths', orderBy: 'updated_at ASC');
    final atoms = await db.records('atoms', orderBy: 'updated_at ASC');
    final current = truths.where((t) => '${t['status']}' == 'CURRENT').toList();
    final conflicts =
        truths.where((t) => '${t['status']}' == 'CONFLICTING').length;
    final strictBlocked =
        atoms.where((a) => a['strictTruthBlocked'] == true).length;
    return MemoryDiagnosticReport(
      memoryRoot: root,
      currentTruthRoot: buildCurrentTruthRoot(current),
      sourceEvidenceRoot: buildSourceEvidenceRoot(messages),
      messages: messages.length,
      truths: truths.length,
      currentTruths: current.length,
      conflicts: conflicts,
      evidenceBlocks: await db.total('evidenceBlocks'),
      strictBlockedAtoms: strictBlocked,
    );
  }
}
