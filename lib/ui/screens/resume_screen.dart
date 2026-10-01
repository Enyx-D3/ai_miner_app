import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../services/global_context_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'context_handoff_screen.dart';
import 'project_detail_screen.dart';

class ResumeProjectScreen extends StatefulWidget {
  final Brain2Controller controller;
  final Map<String, Object?> project;
  const ResumeProjectScreen(this.controller, this.project, {super.key});

  @override
  State<ResumeProjectScreen> createState() => _ResumeProjectScreenState();
}

class _ResumeProjectScreenState extends State<ResumeProjectScreen> {
  Map<String, Object?>? capsule;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = GlobalContextService(
        widget.controller.db,
        widget.controller.mutations,
        widget.controller.reader,
      );
      capsule = await service.buildResumeCapsule(widget.project);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = capsule;
    return Scaffold(
      appBar: AppBar(title: const Text('Resume project')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlobalContextPageHeader(
            tag: 'ANDROID · AN06',
            title: bestTitle(widget.project),
            description:
                'Exact re-entry point from Current Truth, open human-control points, known failures and source-backed project state.',
          ),
          if (busy)
            const Center(child: CircularProgressIndicator())
          else if (c == null)
            const Text('Could not build the resume capsule.')
          else ...[
            GlobalContextHeroCard(
              overline: 'PICK UP WHERE YOU LEFT OFF',
              title: '${c['goal']}',
              subtitle: 'Next: ${(c['nextAction'] as Map)['text']}',
              buttonText: 'Open project ↗',
              onButtonPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProjectDetailScreen(
                    widget.controller,
                    widget.project,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            GlobalContextSectionCard(
              title: 'Verified resume capsule',
              badgeLabel: 'Bounded',
              children: [
                _countTile(
                  context,
                  'Current Truth',
                  ((c['currentTruth'] as List?) ?? const []).length,
                  Icons.verified_outlined,
                ),
                _countTile(
                  context,
                  'Needs you',
                  ((c['openTicks'] as List?) ?? const []).length,
                  Icons.task_alt_outlined,
                ),
                _countTile(
                  context,
                  'Known failed routes',
                  ((c['knownFailures'] as List?) ?? const []).length,
                  Icons.route_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContextHandoffScreen(
                    widget.controller,
                    initialProject: widget.project,
                    initialTask: '${(c['nextAction'] as Map)['text']}',
                  ),
                ),
              ),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Prepare bounded AI handoff'),
            ),
            const SizedBox(height: 10),
            Text(
              'Resume capsule ${('${c['capsuleHash']}').substring(0, 16)}… · raw archive excluded',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Brain2Theme.textSecondaryOf(context),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countTile(
      BuildContext context, String label, int count, IconData icon) {
    return GlobalContextActionTile(
      icon: icon,
      title: label,
      subtitle: '$count source-backed item${count == 1 ? '' : 's'}',
      actionLabel: '',
      onTap: null,
    );
  }
}
