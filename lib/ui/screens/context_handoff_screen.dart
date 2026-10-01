import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/brain2_controller.dart';
import '../../services/global_context_service.dart';
import '../theme.dart';
import '../widgets.dart';

class ContextHandoffScreen extends StatefulWidget {
  final Brain2Controller controller;
  final Map<String, Object?>? initialProject;
  final String? initialTask;
  final VoidCallback? onConsumed;

  const ContextHandoffScreen(
    this.controller, {
    super.key,
    this.initialProject,
    this.initialTask,
    this.onConsumed,
  });

  @override
  State<ContextHandoffScreen> createState() => _ContextHandoffScreenState();
}

class _ContextHandoffScreenState extends State<ContextHandoffScreen> {
  final task = TextEditingController();
  List<Map<String, Object?>> projects = [];
  Map<String, Object?>? selectedProject;
  Map<String, Object?>? package;
  List<Map<String, Object?>> anti = [];
  String outbound = '';
  String destination = 'chatgpt';
  bool busy = false;
  int evidenceLimit = 24;

  @override
  void initState() {
    super.initState();
    task.text = widget.initialTask ?? '';
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    evidenceLimit = prefs.getInt('gc_autocontext_evidence_limit') ?? 24;
    projects = await widget.controller.db.records(
      'projects',
      orderBy: 'updated_at DESC',
    );
    selectedProject = widget.initialProject ??
        (projects.isNotEmpty ? projects.first : null);
    if (mounted) setState(() {});
  }

  GlobalContextService get service => GlobalContextService(
        widget.controller.db,
        widget.controller.mutations,
        widget.controller.reader,
      );

  Future<void> compile() async {
    final project = selectedProject;
    if (project == null || task.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final next = await service.compileContextPackage(
        project: project,
        task: task.text,
        evidenceLimit: evidenceLimit,
      );
      final hits = await service.antiReinvention(
        task.text,
        projectId: '${project['id']}',
      );
      setState(() {
        package = next;
        outbound = service.renderOutbound(next);
        anti = hits;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> approveAndCopy() async {
    final p = package;
    if (p == null || outbound.isEmpty) return;
    await service.recordHandoff(
      package: p,
      outbound: outbound,
      destination: destination,
    );
    await Clipboard.setData(ClipboardData(text: outbound));
    widget.onConsumed?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approved bounded context copied for $destination')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Context handoff')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const GlobalContextPageHeader(
            tag: 'ANDROID · AN16',
            title: 'Use saved context',
            description:
                'Build a bounded continuation capsule, inspect exactly what leaves the device, then approve it for one AI destination.',
          ),
          DropdownButtonFormField<String>(
            value: selectedProject == null ? null : '${selectedProject!['id']}',
            decoration: const InputDecoration(labelText: 'Project'),
            items: projects
                .map(
                  (p) => DropdownMenuItem(
                    value: '${p['id']}',
                    child: Text(bestTitle(p)),
                  ),
                )
                .toList(),
            onChanged: (id) => setState(() {
              selectedProject = null;
              for (final p in projects) {
                if ('${p['id']}' == id) {
                  selectedProject = p;
                  break;
                }
              }
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: task,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What are you continuing?',
              hintText: 'Continue from the last verified checkpoint…',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: destination,
            decoration: const InputDecoration(labelText: 'Destination'),
            items: const [
              DropdownMenuItem(value: 'chatgpt', child: Text('ChatGPT')),
              DropdownMenuItem(value: 'claude', child: Text('Claude')),
              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
              DropdownMenuItem(value: 'manual', child: Text('Manual / other AI')),
            ],
            onChanged: (value) => setState(() => destination = value ?? 'manual'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : compile,
            icon: const Icon(Icons.auto_awesome),
            label: Text(busy ? 'Compiling…' : 'Build bounded context'),
          ),
          if (anti.isNotEmpty) ...[
            const SizedBox(height: 18),
            GlobalContextSectionCard(
              title: 'You may have solved this before',
              badgeLabel: 'Anti-Reinvention',
              children: anti
                  .map(
                    (hit) => GlobalContextActionTile(
                      icon: hit['kind'] == 'FAILURE'
                          ? Icons.route_outlined
                          : Icons.history_rounded,
                      title: '${hit['title']}',
                      subtitle: '${hit['detail']}',
                      actionLabel: '${hit['action']}',
                      onTap: null,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (package != null) ...[
            const SizedBox(height: 18),
            GlobalContextSectionCard(
              title: 'Inspect before send',
              badgeLabel: 'Private by default',
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Brain2Theme.heroCardBgOf(context),
                    border: Border.all(color: Brain2Theme.heroBorderOf(context)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      outbound,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: approveAndCopy,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Approve & copy selected context'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Full archive excluded · returned output remains a proposal until verified.',
                  style: TextStyle(
                    color: Brain2Theme.textSecondaryOf(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
