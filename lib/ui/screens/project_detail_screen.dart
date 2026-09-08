import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Brain2Controller c;
  final Map<String, Object?> project;
  const ProjectDetailScreen(this.c, this.project, {super.key});
  @override
  State<ProjectDetailScreen> createState() => _P();
}

class _P extends State<ProjectDetailScreen> {
  String tab = 'now';
  List<Map<String, Object?>> rows = [];
  Future<void> load() async {
    final id = '${widget.project['id']}';
    final table = tab == 'findings'
        ? 'atoms'
        : tab == 'patterns'
            ? 'patterns'
            : tab == 'evidence'
                ? 'databoxes'
                : tab == 'ticks'
                    ? 'ticks'
                    : tab == 'experiments'
                        ? 'experiments'
                        : 'truths';
    rows = await widget.c.db.recordsWhere(table,
        test: (r) => '${r['projectId'] ?? ''}' == id || tab == 'patterns');
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext c) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        PageTitle(bestTitle(widget.project),
            'Project / Live Notebook · same working context as web V9.'),
        Wrap(
            spacing: 6,
            children: [
              'now',
              'findings',
              'patterns',
              'evidence',
              'ticks',
              'experiments'
            ]
                .map((t) => ChoiceChip(
                    label: Text(t),
                    selected: tab == t,
                    onSelected: (_) {
                      tab = t;
                      load();
                    }))
                .toList()),
        const SizedBox(height: 12),
        ...rows.take(200).map((r) => RecordTile(r))
      ]);
}
