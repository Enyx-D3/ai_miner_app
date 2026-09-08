import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class DecisionsScreen extends StatefulWidget {
  final Brain2Controller c;
  const DecisionsScreen(this.c, {super.key});
  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('decisions');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle(
            'Decisions', 'Decision records reconciled against Current Truth.'),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                      'No records yet. Import history or sync from another Brain2 device.')))
        else
          ...rows.reversed.take(300).map((r) => RecordTile(r))
      ]));
}
