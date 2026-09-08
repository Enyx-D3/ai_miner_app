import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class NotebooksScreen extends StatefulWidget {
  final Brain2Controller c;
  const NotebooksScreen(this.c, {super.key});
  @override
  State<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db
        .records('notebookSnapshots', orderBy: 'updated_at DESC');
    if (rows.isEmpty)
      rows = await widget.c.db.records('projects', orderBy: 'updated_at DESC');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('Live Notebooks',
            'Verified current working state: NOW, changes, blockers, hypotheses, experiments and next actions.'),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                      'No Live Notebook state yet. Import or sync Brain2 memory first.')))
        else
          ...rows.take(300).map((r) => RecordTile(r))
      ]));
}
