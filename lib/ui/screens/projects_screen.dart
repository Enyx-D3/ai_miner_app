import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'resume_screen.dart';

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
  Widget build(BuildContext context) {
    final activeProject = rows.isNotEmpty ? rows.first : null;

    return RefreshIndicator(
      onRefresh: load,
      color: Brain2Theme.primaryBlue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Header: ANDROID · AN05
          const GlobalContextPageHeader(
            tag: 'ANDROID · AN05',
            title: 'Projects',
            description: 'One current state across your AI services',
          ),

          // Hero Card: Pick up where you left off
          GlobalContextHeroCard(
            overline: 'PICK UP WHERE YOU LEFT OFF',
            title:
                activeProject != null ? bestTitle(activeProject) : 'Projects',
            subtitle:
                '${rows.length} linked projects · recent context available offline',
            buttonText: 'Continue project ↗',
            onButtonPressed: activeProject != null
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ResumeProjectScreen(widget.c, activeProject),
                      ),
                    );
                  }
                : null,
          ),

          const SizedBox(height: 18),

          // Relevant Work Container
          GlobalContextSectionCard(
            title: 'Relevant work',
            badgeLabel: 'Concept',
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 40,
                          color: Brain2Theme.textLight,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No projects yet. Mine an AI history export first.',
                          style: TextStyle(
                            color: Brain2Theme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...rows.map((record) {
                  final title = bestTitle(record);
                  final subtitleText = subline(record).isEmpty
                      ? 'Design + architecture\nVerified unified workspace'
                      : subline(record);

                  return GlobalContextActionTile(
                    icon: Icons.folder_outlined,
                    title: title,
                    subtitle: subtitleText,
                    actionLabel: 'Continue >',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ResumeProjectScreen(widget.c, record),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}
