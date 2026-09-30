import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../intelligence/memory_diagnostics.dart';
import '../theme.dart';
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Brain2Theme.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brain2Theme.border),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Reader Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Brain2Theme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GlobalContextPillBadge(
                    label: widget.c.readerState,
                    backgroundColor: Brain2Theme.pillBadgeBg,
                    textColor: Brain2Theme.brandBlue,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Messages ${counts['messages'] ?? 0} · Atoms ${counts['atoms'] ?? 0} · Truths ${counts['truths'] ?? 0} · Projects ${counts['projects'] ?? 0}',
                style: const TextStyle(
                  color: Brain2Theme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          final result =
                              await widget.c.importer.pickAndImport();
                          if (result == null) return 'Import cancelled';
                          await widget.c.refresh();
                          return 'Imported ${result.messages} messages from ${result.sourceLabel}';
                        }),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import AI history'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Brain2Theme.brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
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
                icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                label: const Text('Import .B2M snapshot'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Brain2Theme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  foregroundColor: Brain2Theme.textPrimary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          await widget.c.b2m.shareSnapshot();
                          return '.B2M snapshot ready to share';
                        }),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Export / share .B2M'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Brain2Theme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  foregroundColor: Brain2Theme.textPrimary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          await widget.c.repairReader();
                          return 'Reader index rebuilt';
                        }),
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Repair search index'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Brain2Theme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  foregroundColor: Brain2Theme.textPrimary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          final report =
                              await MobileMemoryDiagnostics(widget.c.db)
                                  .verify();
                          return report.summary;
                        }),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Verify truth & evidence integrity'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: Brain2Theme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  foregroundColor: Brain2Theme.textPrimary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 20, color: Brain2Theme.borderLight),
              const SizedBox(height: 4),
              TextButton.icon(
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
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xffd93025),
                                ),
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
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xffd93025)),
                label: const Text(
                  'Reset local memory',
                  style: TextStyle(color: Color(0xffd93025), fontWeight: FontWeight.w700),
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Brain2Theme.heroCardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Brain2Theme.heroBorder),
                  ),
                  child: Text(
                    note,
                    style: const TextStyle(
                      color: Brain2Theme.brandBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
