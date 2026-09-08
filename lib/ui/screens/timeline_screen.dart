import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class TimelineScreen extends StatefulWidget {
  final Brain2Controller c;
  const TimelineScreen(this.c, {super.key});
  @override
  State<TimelineScreen> createState() => _T();
}

class _T extends State<TimelineScreen> {
  List<Map<String, Object?>> rows = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('messages');
    rows.sort((a, b) => '${b['occurredAt'] ?? b['createdAt'] ?? ''}'
        .compareTo('${a['occurredAt'] ?? a['createdAt'] ?? ''}'));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('Timeline',
            'A source-backed chronology from the persistent message store; mutation telemetry belongs on Operations.'),
        ...rows.take(250).map((r) => Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${r['provider'] ?? ''}'.toUpperCase(),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xff1864ff))),
                        const Spacer(),
                        Text('${r['occurredAt'] ?? r['createdAt'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xff9aa8b7)))
                      ]),
                      const SizedBox(height: 6),
                      Text('${r['text'] ?? ''}',
                          maxLines: 5, overflow: TextOverflow.ellipsis)
                    ]))))
      ]));
}
