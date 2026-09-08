import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../../jobs/b2_job_service.dart';
import '../widgets.dart';

class AskScreen extends StatefulWidget {
  final Brain2Controller c;
  const AskScreen(this.c, {super.key});
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final q = TextEditingController();
  Map<String, Object?>? job;
  Map<String, Object?>? result;
  bool busy = false;

  Future<void> run() async {
    if (q.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final service = B2JobService(
        widget.c.db,
        widget.c.mutations,
        widget.c.reader,
      );
      final j = await service.compile(q.text);
      final boxJson = (j['databox'] as Map).cast<String, Object?>();
      final run = await widget.c.mrs.run(task: q.text, databox: boxJson);
      setState(() {
        job = j;
        result = run.toJson();
      });
      await widget.c.refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PageTitle('Ask Brain2',
              'Verified Databox → deterministic/compiled solve first → canonical MRS only for unresolved residuals.'),
          TextField(
              controller: q,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText:
                      'What do you want Brain2 to find, verify, compare, or reason about?')),
          const SizedBox(height: 10),
          FilledButton.icon(
              onPressed: busy ? null : run,
              icon: const Icon(Icons.auto_awesome),
              label:
                  Text(busy ? 'Running Brain2…' : 'Run verified Brain2 job')),
          if (result != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MRS / routing result',
                              style: Theme.of(c).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          SelectableText(const JsonEncoder.withIndent('  ')
                              .convert(result)),
                        ]))),
          if (job != null)
            ExpansionTile(
                title: const Text('B2JOB / Verified Databox'),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(job)))
                ]),
        ],
      );
}
