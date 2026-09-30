import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class ProjectDetailScreen extends StatefulWidget {
  final Brain2Controller c;
  final Map<String, Object?> project;
  const ProjectDetailScreen(this.c, this.project, {super.key});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brain2Theme.canvasLight,
      appBar: AppBar(
        title: Text(
          bestTitle(widget.project),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          GlobalContextPageHeader(
            tag: 'PROJECT / CONTEXT',
            title: bestTitle(widget.project),
            description:
                'Identity-resolved project state, decisions, findings and evidence.',
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'now',
                'findings',
                'patterns',
                'evidence',
                'ticks',
                'experiments'
              ].map((t) {
                final selected = tab == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() => tab = t);
                      load();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? Brain2Theme.primaryBlue
                            : Brain2Theme.primaryBlueLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        t.toUpperCase(),
                        style: TextStyle(
                          color: selected ? Colors.white : Brain2Theme.primaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No items found under this tab.',
                  style: TextStyle(color: Brain2Theme.textMuted),
                ),
              ),
            )
          else
            ...rows.take(200).map((r) => RecordTile(r)),
        ],
      ),
    );
  }
}
