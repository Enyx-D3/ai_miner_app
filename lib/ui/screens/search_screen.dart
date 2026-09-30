import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../asif/asif_reader_core.dart';
import '../theme.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  final Brain2Controller c;
  final bool discover;

  const SearchScreen(this.c, {super.key, this.discover = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final q = TextEditingController();
  List<ReaderEvidence> rows = [];
  bool busy = false;
  String mode = 'find';

  Future<void> run() async {
    setState(() => busy = true);
    Set<String>? tables;
    if (mode == 'current' || mode == 'history') tables = {'truths'};
    if (mode == 'evidence') tables = {'atoms', 'messages', 'truths'};
    if (mode == 'discover') tables = {'atoms'};

    var r = await widget.c.reader.query(
      q.text.isEmpty && mode == 'discover'
          ? 'idea decision constraint task'
          : q.text,
      evidenceLimit: 100,
      tables: tables,
    );

    if (mode == 'current') {
      r = r.where((e) => '${e.record['status']}' == 'CURRENT').toList();
    }
    if (mode == 'history') {
      r = r.where((e) => '${e.record['status']}' != 'CURRENT').toList();
    }
    rows = r;
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    if (widget.discover) {
      mode = 'discover';
      Future.microtask(run);
    }
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Page Header: ANDROID · AN04
        GlobalContextPageHeader(
          tag: 'ANDROID · AN04',
          title: widget.discover ? 'Discover · Gold' : 'Perfect Recall',
          description: widget.discover
              ? 'Resurface older ideas, decisions, constraints and tasks'
              : 'Search conversations, sources and forgotten work',
        ),

        // Main Search Container Card
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
              // Search input box matching reference
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Brain2Theme.borderLight),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(
                        Icons.search,
                        color: Brain2Theme.primaryBlue,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: q,
                        onSubmitted: (_) => run(),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Brain2Theme.textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.discover
                              ? 'Find forgotten work…'
                              : 'Global Context original plan',
                          hintStyle: TextStyle(
                            color: Brain2Theme.textMuted,
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: run,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(
                          'Search →',
                          style: TextStyle(
                            color: Brain2Theme.primaryBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Filter pills: All, Sources, Projects, Decisions
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterPill('All', 'find'),
                    const SizedBox(width: 8),
                    _filterPill('Sources', 'evidence'),
                    const SizedBox(width: 8),
                    _filterPill('Projects', 'discover'),
                    const SizedBox(width: 8),
                    _filterPill('Decisions', 'current'),
                  ],
                ),
              ),

              if (busy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Brain2Theme.primaryBlueLight,
                  color: Brain2Theme.primaryBlue,
                ),
              ],

              const SizedBox(height: 16),

              // Results List
              if (rows.isEmpty && !busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.manage_search_rounded,
                          size: 40,
                          color: Brain2Theme.textLight,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          q.text.isEmpty
                              ? 'Enter a query or select a category to recall'
                              : 'No matches found in local memory',
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
                ...rows.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  final padIdx = idx.toString().padLeft(2, '0');
                  final title = bestTitle(item.record);
                  final sourceInfo =
                      item.record['sourceLabel'] ?? item.record['provider'] ?? 'imported project notes';

                  return GlobalContextActionTile(
                    icon: idx % 2 == 1 ? Icons.auto_awesome : Icons.search,
                    title: 'Result $padIdx · $title',
                    subtitle: 'Source: $sourceInfo\nRelevance score: ${(item.score * 100).toInt()}%',
                    actionLabel: 'Open evidence >',
                    onTap: () => _showEvidenceSheet(context, item),
                  );
                }),

              const SizedBox(height: 8),

              // Footnote
              const Center(
                child: Text(
                  'Verified on-device memory · source excerpts remain private.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Brain2Theme.textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterPill(String label, String m) {
    final selected = mode == m;
    return InkWell(
      onTap: () {
        setState(() => mode = m);
        run();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Brain2Theme.primaryBlue
              : Brain2Theme.primaryBlueLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Brain2Theme.primaryBlue,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showEvidenceSheet(BuildContext context, ReaderEvidence evidence) {
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
                bestTitle(evidence.record),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Brain2Theme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subline(evidence.record),
                style: TextStyle(
                  color: Brain2Theme.textMuted,
                  fontSize: 13,
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    '${evidence.record['content'] ?? evidence.record['text'] ?? evidence.record['summary'] ?? evidence.record}',
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
