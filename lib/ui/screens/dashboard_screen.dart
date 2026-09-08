import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../widgets.dart';

class DashboardScreen extends StatelessWidget {
  final Brain2Controller c;
  const DashboardScreen(this.c, {super.key});
  @override
  Widget build(BuildContext x) {
    final n = c.counts;
    return RefreshIndicator(
        onRefresh: c.refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const PageTitle('Living intelligence operations',
              'The same Brain2 memory, Current Truth, missions, patterns and device state as the V9 web app.'),
          GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.45,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                MetricCard(
                    'Messages', '${n['messages'] ?? 0}', Icons.forum_outlined),
                MetricCard('Atoms', '${n['atoms'] ?? 0}', Icons.hub_outlined),
                MetricCard('Projects', '${n['projects'] ?? 0}',
                    Icons.folder_copy_outlined),
                MetricCard(
                    'Open ticks', '${n['ticks'] ?? 0}', Icons.task_alt_outlined)
              ]),
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('V9 runtime',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17)),
                        const SizedBox(height: 8),
                        Text('.ASIF Reader / RapidRetrieve: ${c.readerState}'),
                        Text('Memory root: ${c.db.db.path.split('/').last}'),
                        Text('Global Delta mutations: ${n['mutations'] ?? 0}'),
                        const SizedBox(height: 10),
                        const Text(
                            'Extension captures arrive through the web replica and propagate here through Global Delta. Mobile is a full Brain2 replica, not an extension receiver.',
                            style: TextStyle(
                                color: Color(0xff9aa8b7), height: 1.4))
                      ])))
        ]));
  }
}
