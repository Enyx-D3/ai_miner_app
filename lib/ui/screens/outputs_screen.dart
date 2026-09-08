import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class OutputsScreen extends StatefulWidget {
  final Brain2Controller c;
  const OutputsScreen(this.c, {super.key});
  @override
  State<OutputsScreen> createState() => _OutputsScreenState();
}

class _OutputsScreenState extends State<OutputsScreen> {
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('transactions');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('Outputs',
            'B2 transactions, results, verifications and portable artifacts.'),
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
