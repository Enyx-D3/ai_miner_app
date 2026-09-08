import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_history_repository.dart';
import '../../mrs/mobile_model_manager.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  final Brain2Controller controller;

  const SettingsScreen(this.controller, {super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  String note = '';
  MobileModelStatus? modelStatus;
  bool modelBusy = false;
  double modelProgress = 0;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  Future<void> _refreshModelStatus({bool verifyHash = false}) async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null) return;
    final next = await manager.status(verifyHash: verifyHash);
    if (mounted) setState(() => modelStatus = next);
  }

  Future<void> _downloadModel() async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null || modelBusy) return;
    setState(() {
      modelBusy = true;
      modelProgress = modelStatus?.progress ?? 0;
      note = '';
    });
    try {
      await manager.ensureDownloaded(onProgress: (progress) {
        if (mounted) setState(() => modelProgress = progress);
      });
      await _refreshModelStatus(verifyHash: true);
      if (mounted) setState(() => note = 'Local MRS model verified and ready.');
    } catch (error) {
      if (mounted) setState(() => note = 'Model download error: $error');
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _removeModel() async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null || modelBusy) return;
    setState(() => modelBusy = true);
    try {
      await widget.controller.mobileModelAdapter?.dispose();
      await manager.remove();
      await _refreshModelStatus();
      if (mounted) setState(() => note = 'Local MRS model removed.');
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _clearHistory() async {
    setState(() {
      busy = true;
      note = '';
    });
    try {
      await MinerHistoryRepository().clear();
      if (mounted) setState(() => note = 'Mining History cleared.');
    } catch (error) {
      if (mounted) setState(() => note = 'Error: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nativeReady =
        widget.controller.contextVault.native.markdownFileAvailable;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageTitle(
          'Settings',
          'Local product settings and runtime status. Brain2 memory management stays under Memory & .B2M.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Brain2 AI Miner',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text('Version 9.5.3+953'),
                Text(
                  'ContextVault: ${nativeReady ? 'Native C++ ready' : 'Android ARM64 binary required'}',
                ),
                Text('Reader: ${widget.controller.readerState}'),
                const SizedBox(height: 12),
                const Text(
                  'Privacy: mining and canonical memory processing are local-first. P2P networking is only used when you explicitly join a Brain2 pairing invite.',
                  style: TextStyle(color: Color(0xff9aa8b7), height: 1.45),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local MRS model',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(widget
                        .controller.mobileModelManager?.manifest.displayName ??
                    'Unavailable'),
                Text(
                    'Runtime: ${widget.controller.mobileModelAdapter?.runtimeName ?? 'UNCONFIGURED'}'),
                Text(
                    'State: ${modelStatus?.state.name.toUpperCase() ?? 'CHECKING'}'),
                if (modelBusy) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                      value: modelProgress > 0 ? modelProgress : null),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: modelBusy || modelStatus?.ready == true
                          ? null
                          : _downloadModel,
                      icon: const Icon(Icons.download),
                      label: const Text('Download & verify'),
                    ),
                    OutlinedButton.icon(
                      onPressed: modelBusy || modelStatus?.ready != true
                          ? null
                          : _removeModel,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove model'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'The model is only invoked for hard semantic residuals after deterministic, graph, capability, and Tiny Specialist routes fail.',
                  style: TextStyle(color: Color(0xff9aa8b7), height: 1.45),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : _clearHistory,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Clear Mining History'),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(note),
        ],
      ],
    );
  }
}
