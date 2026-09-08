import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../core/identity.dart';
import '../widgets.dart';

class ExperimentsScreen extends StatefulWidget {
  final Brain2Controller c;

  const ExperimentsScreen(this.c, {super.key});

  @override
  State<ExperimentsScreen> createState() => _ExperimentsScreenState();
}

class _ExperimentsScreenState extends State<ExperimentsScreen> {
  final title = TextEditingController();
  final hypothesis = TextEditingController();
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    hypothesis.dispose();
    super.dispose();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('experiments');
    if (mounted) setState(() {});
  }

  Future<void> create() async {
    if (title.text.trim().isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final record = <String, Object?>{
      'id': canonicalId('exp', [title.text, now]),
      'title': title.text.trim(),
      'hypothesis': hypothesis.text.trim(),
      'status': 'READY',
      'createdAt': now,
      'updatedAt': now,
      'evidenceAtomIds': <String>[],
    };
    await widget.c.mutations.upsert(
      'experiments',
      record,
      type: 'CREATE_EXPERIMENT',
    );
    title.clear();
    hypothesis.clear();
    await load();
  }

  Future<void> status(Map<String, Object?> record, String value) async {
    final next = Map<String, Object?>.from(record)
      ..['status'] = value
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    if (value == 'COMPLETED') {
      next['result'] =
          'Completed by operator; evidence remains attached separately.';
    } else if (value == 'FAILED') {
      next['result'] = 'Marked failed by operator.';
    }
    await widget.c.mutations.upsert(
      'experiments',
      next,
      type: 'UPDATE_EXPERIMENT',
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PageTitle(
            'Experiments',
            'Durable READY → RUNNING → COMPLETED / FAILED experiment registry.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'Experiment title'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hypothesis,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Hypothesis and measurable result',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: create,
                      child: const Text('Create experiment'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...rows.reversed.map(
            (record) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bestTitle(record),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text('${record['hypothesis'] ?? ''}'),
                    const SizedBox(height: 4),
                    Text(
                      '${record['status'] ?? ''}',
                      style: const TextStyle(
                        color: Color(0xffa970ff),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        if ('${record['status']}' == 'READY')
                          OutlinedButton(
                            onPressed: () => status(record, 'RUNNING'),
                            child: const Text('Start'),
                          ),
                        if ('${record['status']}' == 'RUNNING') ...[
                          OutlinedButton(
                            onPressed: () => status(record, 'COMPLETED'),
                            child: const Text('Complete'),
                          ),
                          OutlinedButton(
                            onPressed: () => status(record, 'FAILED'),
                            child: const Text('Fail'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}
