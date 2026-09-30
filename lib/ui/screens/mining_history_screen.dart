import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import '../../miner/miner_history_repository.dart';
import '../../miner/miner_models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mining_complete_screen.dart';

class MiningHistoryScreen extends StatefulWidget {
  final Brain2Controller controller;

  const MiningHistoryScreen(this.controller, {super.key});

  @override
  State<MiningHistoryScreen> createState() => _MiningHistoryScreenState();
}

class _MiningHistoryScreenState extends State<MiningHistoryScreen> {
  late Future<List<MinerRunRecord>> _runs = MinerHistoryRepository().loadRuns();

  void _reload() {
    setState(() => _runs = MinerHistoryRepository().loadRuns());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MinerRunRecord>>(
      future: _runs,
      builder: (context, snapshot) {
        final runs = snapshot.data ?? const <MinerRunRecord>[];
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _runs;
          },
          color: Brain2Theme.primaryBlue,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const GlobalContextPageHeader(
                tag: 'GLOBAL / HISTORY',
                title: 'Mining History',
                description:
                    'Completed local digest + Brain2 intelligence runs.',
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Brain2Theme.primaryBlue,
                    ),
                  ),
                )
              else if (runs.isEmpty)
                const GlobalContextSectionCard(
                  title: 'Past Archives',
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No completed mining runs yet.',
                          style: TextStyle(color: Brain2Theme.textMuted),
                        ),
                      ),
                    ),
                  ],
                )
              else
                GlobalContextSectionCard(
                  title: 'Completed exports (${runs.length})',
                  badgeLabel: 'Verified',
                  children: [
                    for (final run in runs)
                      GlobalContextActionTile(
                        icon: Icons.archive_outlined,
                        title: run.inputFileName,
                        subtitle:
                            '${formatDateTime(run.completedAt)}\n${formatCount(run.threads)} threads · ${formatCount(run.atoms)} atoms · ${formatBytes(run.outputZipBytes)}',
                        actionLabel: 'Details >',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MiningCompleteScreen(
                              controller: widget.controller,
                              run: run,
                              fromHistory: true,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
