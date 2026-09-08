import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../../core/identity.dart';
import '../widgets.dart';

class TicksScreen extends StatefulWidget {
  final Brain2Controller c;
  const TicksScreen(this.c, {super.key});
  @override
  State<TicksScreen> createState() => _T();
}

class _T extends State<TicksScreen> {
  final title = TextEditingController(), detail = TextEditingController();
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('ticks');
    if (mounted) setState(() {});
  }

  Future<void> create() async {
    if (title.text.trim().isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final r = <String, Object?>{
      'id': canonicalId('tick', [title.text, now]),
      'title': title.text.trim(),
      'detail': detail.text.trim(),
      'status': 'OPEN',
      'priority': 'MEDIUM',
      'createdAt': now,
      'updatedAt': now,
      'evidenceAtomIds': <String>[]
    };
    await widget.c.mutations.upsert('ticks', r, type: 'CREATE_TICK');
    title.clear();
    detail.clear();
    await load();
    await widget.c.refresh();
  }

  Future<void> resolve(Map<String, Object?> r) async {
    final next = Map<String, Object?>.from(r)
      ..['status'] = 'RESOLVED'
      ..['resolution'] = 'Resolved by owner'
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await widget.c.mutations.upsert('ticks', next, type: 'RESOLVE_TICK');
    await load();
  }

  @override
  Widget build(BuildContext c) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('Ticks · Things That Need You',
            'Explicit human-control points. A Tick blocks only dependent work.'),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(
                          labelText: 'Decision or input needed')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: detail,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'What depends on this?')),
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: create, child: const Text('Create Tick')))
                ]))),
        ...rows.reversed.map((r) => Card(
            child: ListTile(
                title: Text(bestTitle(r),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${r['detail'] ?? ''}\n${r['status'] ?? ''}'),
                isThreeLine: true,
                trailing: '${r['status']}' == 'OPEN'
                    ? FilledButton.tonal(
                        onPressed: () => resolve(r),
                        child: const Text('Resolve'))
                    : const Icon(Icons.check_circle, color: Colors.green))))
      ]);
}
