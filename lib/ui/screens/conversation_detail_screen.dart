import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../theme.dart';
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
        backgroundColor: Brain2Theme.scaffoldBg,
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
              const SizedBox(height: 12),
              ...rows.map(
                (record) {
                  final isUser = '${record['role']}'.toLowerCase() == 'user';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isUser ? Brain2Theme.heroCardBg : Brain2Theme.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isUser ? Brain2Theme.heroBorder : Brain2Theme.border,
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? Brain2Theme.brandBlue
                                    : const Color(0xfff1f3f4),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${record['role'] ?? 'unknown'}'.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isUser
                                      ? Colors.white
                                      : Brain2Theme.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${record['text'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Brain2Theme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
}
