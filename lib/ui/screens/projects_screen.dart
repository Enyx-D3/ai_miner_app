import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../widgets.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatefulWidget {
  final Brain2Controller c;

  const ProjectsScreen(this.c, {super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('projects');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PageTitle(
              'Projects',
              'Identity-resolved working contexts built from related conversations; no duplicated memory.',
            ),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child:
                      Text('No projects yet. Mine an AI history export first.'),
                ),
              ),
            ...rows.reversed.map(
              (record) => RecordTile(
                record,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailScreen(widget.c, record),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
