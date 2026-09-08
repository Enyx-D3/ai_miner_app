import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_history_repository.dart';
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
