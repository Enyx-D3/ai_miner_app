import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import '../../miner/miner_models.dart';

class MiningCompleteScreen extends StatelessWidget {
  final Brain2Controller controller;
  final MinerRunRecord run;
  final bool fromHistory;

  const MiningCompleteScreen({
    super.key,
    required this.controller,
    required this.run,
    this.fromHistory = false,
  });

  Future<void> _share(BuildContext context) async {
    final file = File(run.outputZipPath);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('digest.zip is no longer available.')),
        );
      }
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Brain2 AI Miner digest.zip',
    );
  }

  Future<void> _save(BuildContext context) async {
    try {
      final file = File(run.outputZipPath);
      if (!await file.exists()) {
        throw StateError('digest.zip is no longer available.');
      }
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save digest.zip',
        fileName: 'digest.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: await file.readAsBytes(),
      );
      if (context.mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('digest.zip saved.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save digest.zip: $error')),
        );
      }
    }
  }

  void _showFiles(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xff405164),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Generated Files',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text('${run.generatedFiles.length}'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: run.generatedFiles.length,
                itemBuilder: (_, index) => ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: Color(0xffa970ff),
                  ),
                  title: Text(
                    run.generatedFiles[index],
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fromHistory ? 'Saved Mining Run' : 'Complete'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xffa970ff), Color(0xff7c4dff)],
                ),
              ),
              child: const Icon(Icons.check_rounded, size: 50),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your Brain2 archive is ready',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Completed ${formatDateTime(run.completedAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff9aa8b7)),
          ),
          const SizedBox(height: 20),
          _SummaryGrid(run: run),
          const SizedBox(height: 14),
          _Section(
            title: 'Brain2 Memory',
            rows: [
              _Pair('Canonical conversations',
                  formatCount(run.conversationsImported)),
              _Pair('Canonical messages', formatCount(run.messagesImported)),
              _Pair('ContextVault',
                  run.nativeContextVaultUsed ? 'Native C++' : 'Fallback'),
              const _Pair('Atomization', 'G + F + I + B250'),
              const _Pair('Current Truth', 'Reconciled'),
              const _Pair('Reader', '.ASIF / RapidRetrieve'),
              const _Pair('Intelligence', 'LifeWiki + Live Notebooks'),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'File Information',
            rows: [
              _Pair('Input file', run.inputFileName),
              _Pair('Input ZIP', formatBytes(run.inputZipBytes)),
              _Pair('Conversation JSON', formatBytes(run.jsonBytes)),
              _Pair(
                'Providers',
                run.providers.isEmpty ? 'Unknown' : run.providers.join(' + '),
              ),
              _Pair('JSON files', '${run.jsonFileCount}'),
              _Pair('Output file', 'digest.zip'),
              _Pair('Output ZIP', formatBytes(run.outputZipBytes)),
              _Pair(
                'Size reduction',
                '${run.compressionPercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Performance',
            rows: [
              _Pair('ZIP + JSON extraction',
                  formatDurationMs(run.extractionTimeMs)),
              _Pair('ContextVault C++',
                  formatDurationMs(run.nativeProcessingTimeMs)),
              _Pair('Markdown + output ZIP',
                  formatDurationMs(run.outputZipTimeMs)),
              _Pair('Brain2 intelligence import',
                  formatDurationMs(run.intelligenceImportTimeMs)),
              _Pair('Total', formatDurationMs(run.totalTimeMs)),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share digest.zip'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _save(context),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Save digest.zip'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showFiles(context),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('View Generated Files'),
          ),
          const SizedBox(height: 14),
          const Text(
            'This completed run persists locally and can be reopened from Mining History.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff9aa8b7), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final MinerRunRecord run;

  const _SummaryGrid({required this.run});

  @override
  Widget build(BuildContext context) {
    final items = <_Pair>[
      _Pair('Paragraphs', formatCount(run.paragraphs)),
      _Pair('Atoms', formatCount(run.atoms)),
      _Pair('Threads', formatCount(run.threads)),
      _Pair('Topic files', formatCount(run.topicFiles)),
      _Pair('Messages', formatCount(run.messagesImported)),
      _Pair('Output', formatBytes(run.outputZipBytes)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xff9aa8b7),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.value,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Pair> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(color: Color(0xff9aa8b7)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        row.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pair {
  final String label;
  final String value;

  const _Pair(this.label, this.value);
}
