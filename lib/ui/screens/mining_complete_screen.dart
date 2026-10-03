import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import '../../miner/miner_models.dart';
import '../theme.dart';
import '../widgets.dart';

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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Brain2 AI Miner digest.zip',
      ),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Brain2Theme.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Generated Files',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Brain2Theme.textPrimary,
                      ),
                    ),
                  ),
                  GlobalContextPillBadge(
                    label: '${run.generatedFiles.length} files',
                    backgroundColor: Brain2Theme.pillBadgeBg,
                    textColor: Brain2Theme.brandBlue,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Brain2Theme.border),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: run.generatedFiles.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, indent: 56, color: Brain2Theme.borderLight),
                itemBuilder: (_, index) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Brain2Theme.heroCardBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: Brain2Theme.brandBlue,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    run.generatedFiles[index],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Brain2Theme.textPrimary,
                    ),
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
      backgroundColor: Brain2Theme.scaffoldBg,
      appBar: AppBar(
        title: Text(fromHistory ? 'Saved Mining Run' : 'Mining Complete'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xffe6f4ea),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 50,
                color: Color(0xff137333),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your Brain2 archive is ready',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Brain2Theme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Completed ${formatDateTime(run.completedAt)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Brain2Theme.textSecondary,
            ),
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
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _share(context),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Share digest.zip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Brain2Theme.brandBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _save(context),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Save digest.zip'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Brain2Theme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              foregroundColor: Brain2Theme.textPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showFiles(context),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('View Generated Files'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Brain2Theme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              foregroundColor: Brain2Theme.textPrimary,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This completed run persists locally and can be reopened from Mining History.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brain2Theme.textSecondary, fontSize: 12),
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: Brain2Theme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Brain2Theme.border),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label.toUpperCase(),
                          style: TextStyle(
                            color: Brain2Theme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.value,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Brain2Theme.textPrimary,
                          ),
                        ),
                      ],
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
    return Container(
      decoration: BoxDecoration(
        color: Brain2Theme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brain2Theme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Brain2Theme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        color: Brain2Theme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Brain2Theme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Pair {
  final String label;
  final String value;

  const _Pair(this.label, this.value);
}
