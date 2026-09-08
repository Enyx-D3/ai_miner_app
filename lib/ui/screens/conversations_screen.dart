import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../widgets.dart';
import 'conversation_detail_screen.dart';

class ConversationsScreen extends StatefulWidget {
  final Brain2Controller c;

  const ConversationsScreen(this.c, {super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await widget.c.db.records('conversations');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PageTitle(
              'Conversations',
              'Canonical source conversations across supported AI providers.',
            ),
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                      'No conversations yet. Mine an AI history export first.'),
                ),
              ),
            ...rows.reversed.map(
              (record) => RecordTile(
                record,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConversationDetailScreen(widget.c, record),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
