import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../core/identity.dart';
import '../widgets.dart';

class MissionsScreen extends StatefulWidget {
  final Brain2Controller c;

  const MissionsScreen(this.c, {super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  final title = TextEditingController();
  final objective = TextEditingController();
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    objective.dispose();
    super.dispose();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('missions');
    if (mounted) setState(() {});
  }

  Future<void> create() async {
    if (title.text.trim().isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final record = <String, Object?>{
      'id': canonicalId('mission', [title.text, now]),
      'title': title.text.trim(),
      'objective': objective.text.trim(),
      'status': 'READY',
      'createdAt': now,
      'updatedAt': now,
      'checkpointIds': <String>[],
      'tickIds': <String>[],
      'runtimeCanon': 'BRAIN2SHOT_CANONICAL_PRODUCTION_RUNTIME_V2',
      'writerId': widget.c.deviceId,
    };
    await widget.c.mutations.upsert(
      'missions',
      record,
      type: 'CREATE_MISSION',
    );
    title.clear();
    objective.clear();
    await load();
  }

  Future<void> checkpoint(
    Map<String, Object?> record,
    String state,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final checkpointIds = (record['checkpointIds'] as List? ?? const [])
        .map((value) => '$value')
        .toList();
    final checkpoint = <String, Object?>{
      'id': canonicalId(
        'cp',
        [
          record['id'],
          checkpointIds.isEmpty ? '' : checkpointIds.last,
          state,
          now,
        ],
      ),
      'missionId': record['id'],
      'parentId': checkpointIds.isEmpty ? null : checkpointIds.last,
      'state': state,
      'note': 'Operator checkpoint',
      'createdAt': now,
      'validationStatus': 'PASS',
      'regressionStatus': 'PASS',
      'commitStatus': 'COMMITTED',
    };
    await widget.c.mutations.upsert(
      'checkpoints',
      checkpoint,
      type: 'CHECKPOINT',
    );

    final next = Map<String, Object?>.from(record)
      ..['checkpointIds'] = [...checkpointIds, checkpoint['id']]
      ..['status'] = state == 'completed'
          ? 'COMPLETED'
          : state == 'blocked'
              ? 'BLOCKED'
              : 'RUNNING'
      ..['updatedAt'] = now;
    await widget.c.mutations.upsert(
      'missions',
      next,
      type: 'UPDATE_MISSION',
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PageTitle(
            'Brain2Missions',
            'Durable long-running work with checkpoint lineage; no fake autonomous execution.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration:
                        const InputDecoration(labelText: 'Mission title'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: objective,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Objective and acceptance condition',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: create,
                      child: const Text('Create mission'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...rows.reversed.map(
            (record) {
              final checkpoints =
                  (record['checkpointIds'] as List? ?? const []).length;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bestTitle(record),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${record['objective'] ?? ''}'),
                      const SizedBox(height: 4),
                      Text(
                        '${record['status'] ?? ''} · $checkpoints checkpoints',
                        style: const TextStyle(color: Color(0xff9aa8b7)),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: () => checkpoint(record, 'running'),
                            child: const Text('Checkpoint'),
                          ),
                          OutlinedButton(
                            onPressed: () => checkpoint(record, 'blocked'),
                            child: const Text('Block'),
                          ),
                          FilledButton(
                            onPressed: () => checkpoint(record, 'completed'),
                            child: const Text('Complete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
}
