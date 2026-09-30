import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../theme.dart';
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
  String selectedPill = 'Briefing';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db
        .records('notebookSnapshots', orderBy: 'updated_at DESC');
    if (rows.isEmpty) {
      rows = await widget.c.db.records('projects', orderBy: 'updated_at DESC');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      color: Brain2Theme.primaryBlue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // Header: ANDROID · AN07
          const GlobalContextPageHeader(
            tag: 'ANDROID · AN07',
            title: 'Live notebooks',
            description: 'Your sources, notes and generated study outputs',
          ),

          // Container: Sources · Chat · Studio
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Brain2Theme.borderLight, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sources · Chat · Studio',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Brain2Theme.textDark,
                  ),
                ),
                const SizedBox(height: 14),

                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Brain2Theme.primaryBlue,
                      ),
                    ),
                  )
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.note_alt_outlined,
                            size: 40,
                            color: Brain2Theme.textLight,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No Live Notebook state yet. Import or sync memory first.',
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
                  ...rows.take(30).map((record) {
                    final title = bestTitle(record);
                    final sub = subline(record).isEmpty
                        ? '12 sources · 4 provider threads\nSources · Chat · Studio · Graph'
                        : subline(record);

                    return GlobalContextActionTile(
                      icon: Icons.book_outlined,
                      title: title,
                      subtitle: sub,
                      actionLabel: 'Open >',
                      onTap: () => _showNotebookDetail(context, record),
                    );
                  }),

                const SizedBox(height: 14),

                // Category chips matching reference: Briefing, Timeline, Mind map
                Row(
                  children: [
                    _categoryChip('Briefing'),
                    const SizedBox(width: 8),
                    _categoryChip('Timeline'),
                    const SizedBox(width: 8),
                    _categoryChip('Mind map'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String label) {
    final selected = selectedPill == label;
    return InkWell(
      onTap: () => setState(() => selectedPill = label),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Brain2Theme.primaryBlueLight
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Brain2Theme.primaryBlue : Brain2Theme.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _showNotebookDetail(BuildContext context, Map<String, Object?> record) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bestTitle(record),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Brain2Theme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subline(record),
                style: TextStyle(
                  color: Brain2Theme.textMuted,
                  fontSize: 13,
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    '${record['content'] ?? record['summary'] ?? record['notes'] ?? record}',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Brain2Theme.textDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
