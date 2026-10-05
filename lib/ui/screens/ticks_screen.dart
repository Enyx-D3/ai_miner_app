import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../core/identity.dart';
import '../theme.dart';
import '../widgets.dart';

class TicksScreen extends StatefulWidget {
  final Brain2Controller c;
  const TicksScreen(this.c, {super.key});

  @override
  State<TicksScreen> createState() => _TicksScreenState();
}

class _TicksScreenState extends State<TicksScreen> {
  final title = TextEditingController();
  final detail = TextEditingController();
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    title.dispose();
    detail.dispose();
    super.dispose();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('ticks');
    if (mounted) setState(() {});
  }

  Future<void> create() async {
    if (title.text.trim().isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final r = <String, Object?>{
      'id': canonicalId('tick', [title.text, now]),
      'title': title.text.trim(),
      'detail': detail.text.trim(),
      'status': 'OPEN',
      'priority': 'MEDIUM',
      'createdAt': now,
      'updatedAt': now,
      'evidenceAtomIds': <String>[],
    };
    await widget.c.mutations.upsert('ticks', r, type: 'CREATE_TICK');
    title.clear();
    detail.clear();
    await load();
    await widget.c.refresh();
  }

  Future<void> resolve(Map<String, Object?> r) async {
    final next = Map<String, Object?>.from(r)
      ..['status'] = 'RESOLVED'
      ..['resolution'] = 'Resolved by owner'
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await widget.c.mutations.upsert('ticks', next, type: 'RESOLVE_TICK');
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final openTicks = rows.where((r) => '${r['status']}' == 'OPEN').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const GlobalContextPageHeader(
          tag: 'GLOBAL / TICKS',
          title: 'Things That Need You',
          description:
              'Explicit human-control points. A Tick blocks only dependent work.',
        ),
        GlobalContextSectionCard(
          title: 'Create new Tick',
          badgeLabel: 'Human-in-loop',
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(
                hintText: 'Decision or input needed…',
                labelText: 'Decision or input needed',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: detail,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'What depends on this?…',
                labelText: 'What depends on this?',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: create,
                child: const Text('Create Tick →'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GlobalContextSectionCard(
          title: 'Pending actions ($openTicks)',
          children: [
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No ticks recorded yet.',
                    style: TextStyle(
                      color: Brain2Theme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...rows.reversed.map((r) {
                final isOpen = '${r['status']}' == 'OPEN';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOpen
                          ? const Color(0xFFCCE4F7)
                          : Brain2Theme.borderLight,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isOpen
                              ? Brain2Theme.primaryBlueLight
                              : Brain2Theme.greenLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isOpen
                              ? Icons.pending_actions
                              : Icons.check_circle_outline,
                          color: isOpen
                              ? Brain2Theme.primaryBlue
                              : Brain2Theme.greenDark,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bestTitle(r),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: Brain2Theme.textDark,
                              ),
                            ),
                            if ('${r['detail'] ?? ''}'.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${r['detail']}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Brain2Theme.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isOpen)
                        FilledButton(
                          onPressed: () => resolve(r),
                          style: FilledButton.styleFrom(
                            backgroundColor: Brain2Theme.primaryBlue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: const Text('Resolve'),
                        )
                      else
                        const GlobalContextPillBadge(
                          label: 'Resolved',
                          color: Brain2Theme.greenLight,
                          textColor: Brain2Theme.greenDark,
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}
