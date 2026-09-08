import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import '../../miner/miner_history_repository.dart';
import '../../miner/miner_models.dart';
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Mining History',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              const Text(
                'Completed local digest + Brain2 intelligence runs.',
                style: TextStyle(color: Color(0xff9aa8b7)),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (runs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No completed mining runs yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final run in runs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MiningCompleteScreen(
                              controller: widget.controller,
                              run: run,
                              fromHistory: true,
                            ),
                          ),
                        ),
                        leading: const Icon(
                          Icons.folder_zip_rounded,
                          color: Color(0xffa970ff),
                        ),
                        title: Text(
                          run.inputFileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${formatDateTime(run.completedAt)}\n'
                          '${formatCount(run.threads)} threads · '
                          '${formatCount(run.atoms)} atoms · '
                          '${formatBytes(run.outputZipBytes)}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
