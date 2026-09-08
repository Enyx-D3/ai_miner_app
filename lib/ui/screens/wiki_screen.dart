import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class WikiScreen extends StatefulWidget {
  final Brain2Controller c;
  const WikiScreen(this.c, {super.key});
  @override
  State<WikiScreen> createState() => _WikiScreenState();
}

class _WikiScreenState extends State<WikiScreen> {
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows =
        await widget.c.db.records('wikiSnapshots', orderBy: 'updated_at DESC');
    if (rows.isEmpty)
      rows = await widget.c.db.records('truths', orderBy: 'updated_at DESC');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('LifeWiki',
            'Verified long-term intelligence: Current Truth, decisions, changes, conflicts, ideas and evidence.'),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                      'No LifeWiki state yet. Import or sync Brain2 memory first.')))
        else
          ...rows.take(300).map((r) => RecordTile(r))
      ]));
}
