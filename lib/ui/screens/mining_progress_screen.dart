import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_history_repository.dart';
import '../../miner/miner_models.dart';
import '../../miner/miner_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mining_complete_screen.dart';

class MiningProgressScreen extends StatefulWidget {
  final Brain2Controller controller;
  final String inputPath;
  final String inputName;
  final int inputSize;

  const MiningProgressScreen({
    super.key,
    required this.controller,
    required this.inputPath,
    required this.inputName,
    required this.inputSize,
  });

  @override
  State<MiningProgressScreen> createState() => _MiningProgressScreenState();
}

class _MiningProgressScreenState extends State<MiningProgressScreen> {
  MinerProgress _progress = const MinerProgress(
    stage: MinerStage.preparing,
    percent: 1,
    message: 'Starting local Brain2 pipeline',
  );
  String? _error;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final totalWatch = Stopwatch()..start();
    String? preparedJsonPath;
    try {
      final digest = await MinerService().createDigest(
        inputPath: widget.inputPath,
        inputName: widget.inputName,
        inputSize: widget.inputSize,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      preparedJsonPath = digest.preparedJsonPath;

      if (mounted) {
        setState(() {
          _progress = const MinerProgress(
            stage: MinerStage.importingMemory,
            percent: 86,
            message: 'Importing canonical conversations and messages',
          );
        });
      }

      final importWatch = Stopwatch()..start();
      final expectedConversations = digest.run.threads;
      final imported = await widget.controller.importer.importPreparedJsonFile(
        digest.preparedJsonPath,
        sourceLabel: widget.inputName,
        contextVaultAlreadyProcessed: digest.run.nativeContextVaultUsed,
        contextVaultSummary: <String, Object?>{
          'paragraphs': digest.run.paragraphs,
          'atoms': digest.run.atoms,
          'threads': digest.run.threads,
          'topic_files': digest.run.topicFiles,
        },
        onProgress: (conversations, messages) {
          if (!mounted) return;
          final ratio = expectedConversations <= 0
              ? 0.0
              : (conversations / expectedConversations).clamp(0.0, 1.0);
          final percent = 86 + (ratio * 8).floor();
          setState(() {
            _progress = MinerProgress(
              stage: MinerStage.importingMemory,
              percent: percent.clamp(86, 94).toInt(),
              message:
                  'Imported $conversations conversations / $messages messages',
            );
          });
        },
      );

      if (mounted) {
        setState(() {
          _progress = MinerProgress(
            stage: MinerStage.intelligence,
            percent: 96,
            message:
                'Building G+F+I+B250 and Current Truth from ${imported.conversations} conversations',
          );
        });
      }

      await widget.controller.importer.buildIntelligence(
        imported,
        onProgress: (completed, total) {
          if (!mounted) return;
          final ratio = total <= 0 ? 1.0 : (completed / total).clamp(0.0, 1.0);
          final percent = 96 + (ratio * 3).floor();
          setState(() {
            _progress = MinerProgress(
              stage: MinerStage.intelligence,
              percent: percent.clamp(96, 99).toInt(),
              message: 'Building Brain2 intelligence $completed / $total',
            );
          });
        },
      );
      importWatch.stop();

      await widget.controller.refresh();
      totalWatch.stop();
      final completed = digest.run.copyWith(
        conversationsImported: imported.conversations,
        messagesImported: imported.messages,
        intelligenceImportTimeMs: importWatch.elapsedMilliseconds,
        totalTimeMs: totalWatch.elapsedMilliseconds,
        nativeContextVaultUsed: digest.run.nativeContextVaultUsed &&
            imported.nativeContextVaultUsed,
        completedAt: DateTime.now().toUtc(),
      );
      await MinerHistoryRepository().save(completed);

      if (preparedJsonPath != null) {
        final file = File(preparedJsonPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _progress = const MinerProgress(
          stage: MinerStage.completed,
          percent: 100,
          message: 'Brain2 AI Miner completed',
        );
        _running = false;
      });
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MiningCompleteScreen(
            controller: widget.controller,
            run: completed,
          ),
        ),
      );
    } catch (error) {
      if (preparedJsonPath != null) {
        final file = File(preparedJsonPath);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _running = false;
          _error = '$error';
          // Preserve the last real progress percentage so a late-stage error
          // does not misleadingly reset the UI to 0% and hide completed work.
          _progress = MinerProgress(
            stage: MinerStage.failed,
            percent: _progress.percent,
            message: 'Mining failed',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _progress.percent.clamp(0, 100).toDouble() / 100.0;
    return Scaffold(
      backgroundColor: Brain2Theme.canvasLight,
      appBar: AppBar(
        title: const Text(
          'Mining progress',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        automaticallyImplyLeading: !_running,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Header: ANDROID · AN03
          const GlobalContextPageHeader(
            tag: 'ANDROID · AN03',
            title: 'Mining progress',
            description: 'See each phase; resume safely after interruption',
          ),

          // Mining checkpoint Container (AN03_mining.png)
          GlobalContextSectionCard(
            title: 'Mining checkpoint',
            badgeLabel: 'Local-first',
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFE),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFCCE4F7),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Brain2Theme.primaryBlueLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Brain2Theme.primaryBlue,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _progress.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Brain2Theme.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_progress.percent}% completed · on-device pipeline',
                      style: TextStyle(
                        fontSize: 13,
                        color: Brain2Theme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _running ? fraction : 1.0,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Brain2Theme.primaryBlue,
                        ),
                        minHeight: 7,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Coverage and next actions Container
          GlobalContextSectionCard(
            title: 'Coverage and next actions',
            children: [
              GlobalContextActionTile(
                icon: Icons.inventory_2_outlined,
                title: 'Inventory',
                subtitle: '${_progress.percent}% of pipeline stages executed\nDemonstration figures · not product benchmarks',
                actionLabel: 'View coverage >',
                onTap: () {},
              ),
              GlobalContextActionTile(
                icon: Icons.tune_rounded,
                title: 'Processing',
                subtitle: 'Structure → Link → Verify\nResumable checkpoints; exact source IDs',
                actionLabel: _running ? 'Running >' : 'Complete >',
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Stage Details Container
          GlobalContextSectionCard(
            title: 'Pipeline stages',
            children: [
              _StageRow(
                title: 'Detect provider + normalize export',
                done: _progress.percent >= 28,
                active: _progress.stage == MinerStage.extracting,
              ),
              _StageRow(
                title: 'ContextVault C++ digest',
                done: _progress.percent >= 76,
                active: _progress.stage == MinerStage.contextVault,
              ),
              _StageRow(
                title: 'Create Markdown + digest.zip',
                done: _progress.percent >= 82,
                active: _progress.stage == MinerStage.packaging,
              ),
              _StageRow(
                title: 'Canonical ingestion + Global Memory',
                done: _progress.percent >= 96,
                active: _progress.stage == MinerStage.importingMemory,
              ),
              _StageRow(
                title: 'Current Truth / LifeWiki / Notebooks',
                done: _progress.percent >= 100,
                active: _progress.stage == MinerStage.intelligence,
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: SelectableText(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Home →'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  final String title;
  final bool done;
  final bool active;

  const _StageRow({
    required this.title,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
            color: done
                ? Brain2Theme.primaryBlue
                : active
                    ? Brain2Theme.primaryBlue
                    : Brain2Theme.textLight,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: done || active
                    ? Brain2Theme.textDark
                    : Brain2Theme.textMuted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
