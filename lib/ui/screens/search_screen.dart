import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../../asif/asif_reader_core.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  final Brain2Controller c;
  final bool discover;
  const SearchScreen(this.c, {super.key, this.discover = false});
  @override
  State<SearchScreen> createState() => _S();
}

class _S extends State<SearchScreen> {
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
        tables: tables);
    if (mode == 'current')
      r = r.where((e) => '${e.record['status']}' == 'CURRENT').toList();
    if (mode == 'history')
      r = r.where((e) => '${e.record['status']}' != 'CURRENT').toList();
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
  Widget build(BuildContext c) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        PageTitle(
            widget.discover ? 'Discover · Forgotten Gold' : 'Search & Recall',
            widget.discover
                ? 'Resurface older ideas, decisions, constraints and tasks through the persistent Reader index.'
                : 'Search the full local Brain2 history without materializing the whole corpus.'),
        TextField(
            controller: q,
            onSubmitted: (_) => run(),
            decoration: InputDecoration(
                hintText: widget.discover
                    ? 'Find forgotten work…'
                    : 'Search your entire Brain2 memory…',
                suffixIcon: IconButton(
                    onPressed: run, icon: const Icon(Icons.search)))),
        if (!widget.discover)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      ['find', 'current', 'history', 'evidence', 'discover']
                          .map((m) => ChoiceChip(
                              label: Text(m[0].toUpperCase() + m.substring(1)),
                              selected: mode == m,
                              onSelected: (_) {
                                mode = m;
                                run();
                              }))
                          .toList())),
        if (busy) const LinearProgressIndicator(),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('${rows.length} results',
                style: const TextStyle(color: Color(0xff9aa8b7)))),
        ...rows.map((e) => RecordTile(e.record))
      ]);
}
