import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../widgets.dart';

class ConversationDetailScreen extends StatefulWidget {
  final Brain2Controller c;
  final Map<String, Object?> conversation;

  const ConversationDetailScreen(this.c, this.conversation, {super.key});

  @override
  State<ConversationDetailScreen> createState() =>
      _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  List<Map<String, Object?>> rows = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final id = '${widget.conversation['id']}';
    rows = await widget.c.db.recordsWhere(
      'messages',
      test: (record) => '${record['conversationId']}' == id,
    );
    rows.sort(
      (a, b) => ((a['sequence'] as int?) ?? 0)
          .compareTo((b['sequence'] as int?) ?? 0),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PageTitle(
                bestTitle(widget.conversation),
                'Canonical conversation and exact local source messages.',
              ),
              ...rows.map(
                (record) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${record['role'] ?? 'unknown'}'.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xffa970ff),
                          ),
                        ),
                        const SizedBox(height: 5),
                        SelectableText('${record['text'] ?? ''}'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
