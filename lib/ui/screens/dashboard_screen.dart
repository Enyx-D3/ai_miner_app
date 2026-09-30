import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../theme.dart';
import '../widgets.dart';

class DashboardScreen extends StatelessWidget {
  final Brain2Controller c;
  const DashboardScreen(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final n = c.counts;
    return RefreshIndicator(
      onRefresh: c.refresh,
      color: Brain2Theme.primaryBlue,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const GlobalContextPageHeader(
            tag: 'LIVING INTELLIGENCE',
            title: 'Operations',
            description:
                'Living Brain2 memory, Current Truth, missions, patterns and device state.',
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              MetricCard(
                  'Messages', '${n['messages'] ?? 0}', Icons.forum_outlined),
              MetricCard('Atoms', '${n['atoms'] ?? 0}', Icons.hub_outlined),
              MetricCard('Projects', '${n['projects'] ?? 0}',
                  Icons.folder_copy_outlined),
              MetricCard(
                  'Open ticks', '${n['ticks'] ?? 0}', Icons.task_alt_outlined),
            ],
          ),
          const SizedBox(height: 18),
          GlobalContextSectionCard(
            title: 'Global Context runtime',
            badgeLabel: 'Verified',
            children: [
              Text(
                'ASIF Reader / RapidRetrieve: ${c.readerState}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Brain2Theme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Memory root: ${c.db.db.path.split('/').last}',
                style: TextStyle(
                  fontSize: 13,
                  color: Brain2Theme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Global Delta mutations: ${n['mutations'] ?? 0}',
                style: TextStyle(
                  fontSize: 13,
                  color: Brain2Theme.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Brain2Theme.heroCyan,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Extension captures arrive through the web replica and propagate here through Global Delta. Mobile is a full replica, not an extension receiver.',
                  style: TextStyle(
                    color: Color(0xFF244464),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
