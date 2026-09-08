import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../intelligence/memory_diagnostics.dart';
import '../widgets.dart';

class MemoryScreen extends StatefulWidget {
  final Brain2Controller c;

  const MemoryScreen(this.c, {super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool busy = false;
  String note = '';

  Future<void> _run(Future<String?> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      note = '';
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() => note = message ?? 'Done');
    } catch (error) {
      if (!mounted) return;
      setState(() => note = 'Error: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.c.counts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageTitle(
          'Memory · Import / Export .B2M',
          'Canonical source history stays in local SQLite. .B2M moves the persistent Brain2 intelligence replica; Reader projections remain rebuildable.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reader index: ${widget.c.readerState}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Messages ${counts['messages'] ?? 0} · Atoms ${counts['atoms'] ?? 0} · Truths ${counts['truths'] ?? 0} · Projects ${counts['projects'] ?? 0}',
                  style: const TextStyle(color: Color(0xff9aa8b7)),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            final result =
                                await widget.c.importer.pickAndImport();
                            if (result == null) return 'Import cancelled';
                            await widget.c.refresh();
                            return 'Imported ${result.messages} messages from ${result.sourceLabel}';
                          }),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import AI history'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            final result =
                                await widget.c.b2m.pickAndImportSnapshot();
                            if (result == null) return 'B2M import cancelled';
                            await widget.c.refresh();
                            final integrity = result.hashVerified
                                ? 'integrity verified'
                                : 'legacy snapshot (no integrity hash)';
                            return 'Imported ${result.records} records across ${result.tables} tables · $integrity';
                          }),
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: const Text('Import .B2M snapshot'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            await widget.c.b2m.shareSnapshot();
                            return '.B2M snapshot ready to share';
                          }),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export / share .B2M'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            await widget.c.repairReader();
                            return 'Reader index rebuilt';
                          }),
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('Repair search index'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                            final report =
                                await MobileMemoryDiagnostics(widget.c.db)
                                    .verify();
                            return report.summary;
                          }),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Verify truth & evidence integrity'),
                ),
                const SizedBox(height: 8),
                const Divider(height: 28),
                FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Reset local Brain2 memory?'),
                              content: const Text(
                                'This deletes the Brain2 replica on this device. Other synced devices are not deleted.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _run(() async {
                                      await widget.c.reset();
                                      return 'Local memory reset';
                                    });
                                  },
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Reset local memory'),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(note, style: const TextStyle(height: 1.4)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
