import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets.dart';

class AttentionPreferencesScreen extends StatefulWidget {
  const AttentionPreferencesScreen({super.key});

  @override
  State<AttentionPreferencesScreen> createState() =>
      _AttentionPreferencesScreenState();
}

class _AttentionPreferencesScreenState
    extends State<AttentionPreferencesScreen> {
  double contextDepth = 0.55;
  double resurfacing = 0.5;
  double interruption = 0.25;
  String detail = 'balanced';
  bool reminders = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      contextDepth = p.getDouble('gc_taste_context_depth') ?? .55;
      resurfacing = p.getDouble('gc_taste_resurfacing') ?? .5;
      interruption = p.getDouble('gc_taste_interruption') ?? .25;
      detail = p.getString('gc_taste_detail') ?? 'balanced';
      reminders = p.getBool('gc_taste_reminders') ?? true;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('gc_taste_context_depth', contextDepth);
    await p.setDouble('gc_taste_resurfacing', resurfacing);
    await p.setDouble('gc_taste_interruption', interruption);
    await p.setString('gc_taste_detail', detail);
    await p.setBool('gc_taste_reminders', reminders);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attention preferences saved locally')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Attention preferences')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const GlobalContextPageHeader(
              tag: 'ANDROID · AN17',
              title: 'Human Taste',
              description:
                  'Calibrate context depth, resurfacing and interruptions. These controls are explicit, local and editable; brain2:inContext does not infer sensitive traits.',
            ),
            _slider('Context depth', contextDepth,
                (v) => setState(() => contextDepth = v)),
            _slider('Forgotten-work resurfacing', resurfacing,
                (v) => setState(() => resurfacing = v)),
            _slider('Interruption tolerance', interruption,
                (v) => setState(() => interruption = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Helpful reminders'),
              subtitle: const Text('Allow bounded Continue / Verify reminders'),
              value: reminders,
              onChanged: (v) => setState(() => reminders = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: detail,
              decoration: const InputDecoration(labelText: 'Default detail'),
              items: const [
                DropdownMenuItem(value: 'compact', child: Text('Compact')),
                DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                DropdownMenuItem(value: 'detailed', child: Text('Detailed')),
              ],
              onChanged: (v) => setState(() => detail = v ?? 'balanced'),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('Save locally')),
          ],
        ),
      );

  Widget _slider(String label, double value, ValueChanged<double> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(value: value, onChanged: onChanged),
        ],
      );
}
