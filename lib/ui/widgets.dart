import 'package:flutter/material.dart';

class PageTitle extends StatelessWidget {
  final String title;
  final String description;

  const PageTitle(this.title, this.description, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(color: Color(0xff9aa8b7), height: 1.45),
            ),
          ],
        ),
      );
}

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const MetricCard(this.label, this.value, this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xff9b6cff).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xffa970ff)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff9aa8b7),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, color: const Color(0xff9b6cff), size: 20),
            ],
          ),
        ),
      );
}

String bestTitle(Map<String, Object?> record) =>
    '${record['title'] ?? record['name'] ?? record['label'] ?? record['text'] ?? record['id'] ?? 'Item'}';

String subline(Map<String, Object?> record) => [
      '${record['status'] ?? ''}',
      '${record['provider'] ?? ''}',
      '${record['updatedAt'] ?? record['createdAt'] ?? ''}',
    ].where((value) => value.isNotEmpty).join(' · ');

class RecordTile extends StatelessWidget {
  final Map<String, Object?> record;
  final VoidCallback? onTap;

  const RecordTile(this.record, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          title: Text(
            bestTitle(record),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(subline(record), maxLines: 2),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
