import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets.dart';

class AutoContextSettingsScreen extends StatefulWidget {
  const AutoContextSettingsScreen({super.key});

  @override
  State<AutoContextSettingsScreen> createState() =>
      _AutoContextSettingsScreenState();
}

class _AutoContextSettingsScreenState extends State<AutoContextSettingsScreen> {
  bool enabled = true;
  int evidenceLimit = 24;
  String scope = 'project';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      enabled = p.getBool('gc_autocontext_enabled') ?? true;
      evidenceLimit = p.getInt('gc_autocontext_evidence_limit') ?? 24;
      scope = p.getString('gc_autocontext_scope') ?? 'project';
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('gc_autocontext_enabled', enabled);
    await p.setInt('gc_autocontext_evidence_limit', evidenceLimit);
    await p.setString('gc_autocontext_scope', scope);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AutoContext preferences saved locally')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AutoContext')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const GlobalContextPageHeader(
              tag: 'ANDROID · AN08',
              title: 'AutoContext',
              description:
                  'Automatically suggest the smallest relevant context package. AutoContext never sends context by itself; Inspect before send remains mandatory.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suggest context automatically'),
              subtitle: const Text(
                  'Use Current Truth, recent deltas, open Ticks and verified evidence to prepare a bounded suggestion.'),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: scope,
              decoration: const InputDecoration(labelText: 'Default scope'),
              items: const [
                DropdownMenuItem(
                    value: 'project', child: Text('Current project')),
                DropdownMenuItem(value: 'all', child: Text('All local memory')),
              ],
              onChanged: enabled
                  ? (v) => setState(() => scope = v ?? 'project')
                  : null,
            ),
            const SizedBox(height: 18),
            Text('Evidence budget: $evidenceLimit',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              min: 4,
              max: 64,
              divisions: 15,
              value: evidenceLimit.toDouble(),
              onChanged: enabled
                  ? (v) => setState(() => evidenceLimit = v.round())
                  : null,
            ),
            const SizedBox(height: 12),
            const GlobalContextSectionCard(
              title: 'Hard boundaries',
              badgeLabel: 'Always on',
              children: [
                GlobalContextActionTile(
                  icon: Icons.visibility_outlined,
                  title: 'Inspect before send',
                  subtitle:
                      'The exact outbound capsule is always shown before approval.',
                  actionLabel: '',
                ),
                GlobalContextActionTile(
                  icon: Icons.lock_outline,
                  title: 'No full-archive injection',
                  subtitle:
                      'Only the selected bounded context package can leave the device.',
                  actionLabel: '',
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _save, child: const Text('Save locally')),
          ],
        ),
      );
}
