import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../widgets.dart';

class OperationsScreen extends StatelessWidget {
  final Brain2Controller c;

  const OperationsScreen(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final counts = c.counts;
    final nativeContextVault = c.contextVault.native.markdownFileAvailable;
    final qwenConfigured = c.mrs.model.runtimeName != 'UNCONFIGURED';
    final p2pConnected = c.p2p != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageTitle(
          'Operations Floor',
          'Technical truth surface. External integrations are shown as blocked until they are actually configured.',
        ),
        _IntegrationStatus(
          label: 'ContextVault native ARM64',
          ready: nativeContextVault,
          detail: nativeContextVault
              ? 'Native ContextVault library loaded.'
              : 'libcontextvault.so is not loaded. Build/install the Android ARM64 library.',
        ),
        _IntegrationStatus(
          label: 'Local Qwen hard-residual runtime',
          ready: qwenConfigured,
          detail: qwenConfigured
              ? '${c.mrs.model.runtimeName} · ${c.mrs.model.modelName}'
              : 'Not configured. MRS fails closed when a hard residual reaches the neural lane.',
        ),
        _IntegrationStatus(
          label: 'P2P live connection',
          ready: p2pConnected,
          detail: p2pConnected
              ? 'A mobile peer session is active.'
              : 'No active peer. Configure signaling/STUN/TURN and join a web-created QR invite.',
        ),
        _IntegrationStatus(
          label: '.ASIF / RapidRetrieve Reader',
          ready: c.readerState == 'READY' || c.readerState == 'EMPTY',
          detail: 'Reader index state: ${c.readerState}',
        ),
        const SizedBox(height: 8),
        for (final key in const [
          'mutations',
          'missions',
          'verifications',
          'transactions',
          'databoxes',
          'patternTests',
          'portableExpertise',
          'mrsRuns',
          'failureMemory',
        ])
          MetricCard(
            key,
            '${counts[key] ?? 0}',
            Icons.monitor_heart_outlined,
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device ID: ${c.deviceId}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Storage: local SQLite canonical replica + rebuildable Reader projection',
                ),
                const Text(
                    'Pairing role: web creates QR → mobile scans / joins'),
                const Text(
                  'Neural policy: deterministic and compiled lanes run first; local model is only a hard-residual fallback.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IntegrationStatus extends StatelessWidget {
  final String label;
  final bool ready;
  final String detail;

  const _IntegrationStatus({
    required this.label,
    required this.ready,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(
            ready ? Icons.check_circle : Icons.pause_circle_outline,
            color: ready ? const Color(0xff31d6a1) : Colors.orange,
          ),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(detail),
          trailing: Text(
            ready ? 'READY' : 'BLOCKED',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: ready ? const Color(0xff31d6a1) : Colors.orange,
            ),
          ),
        ),
      );
}
