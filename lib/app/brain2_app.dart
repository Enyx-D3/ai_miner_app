import 'package:flutter/material.dart';

import '../ui/screens/ask_screen.dart';
import '../ui/screens/conversations_screen.dart';
import '../ui/screens/dashboard_screen.dart';
import '../ui/screens/decisions_screen.dart';
import '../ui/screens/devices_screen.dart';
import '../ui/screens/experiments_screen.dart';
import '../ui/screens/memory_screen.dart';
import '../ui/screens/mine_screen.dart';
import '../ui/screens/mining_history_screen.dart';
import '../ui/screens/missions_screen.dart';
import '../ui/screens/notebooks_screen.dart';
import '../ui/screens/operations_screen.dart';
import '../ui/screens/outputs_screen.dart';
import '../ui/screens/patterns_screen.dart';
import '../ui/screens/projects_screen.dart';
import '../ui/screens/search_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/ticks_screen.dart';
import '../ui/screens/timeline_screen.dart';
import '../ui/screens/wiki_screen.dart';
import '../ui/theme.dart';
import 'brain2_controller.dart';

class Brain2App extends StatefulWidget {
  const Brain2App({super.key});

  @override
  State<Brain2App> createState() => _Brain2AppState();
}

class _Brain2AppState extends State<Brain2App> {
  final Brain2Controller controller = Brain2Controller();
  String page = 'mine';

  @override
  void initState() {
    super.initState();
    controller.addListener(_controllerChanged);
    controller.boot();
  }

  @override
  void dispose() {
    controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  Widget _screen() {
    switch (page) {
      case 'mine':
        return MineScreen(controller);
      case 'miningHistory':
        return MiningHistoryScreen(controller);
      case 'dashboard':
        return DashboardScreen(controller);
      case 'projects':
        return ProjectsScreen(controller);
      case 'conversations':
        return ConversationsScreen(controller);
      case 'discover':
        return SearchScreen(
          controller,
          key: const ValueKey('discover'),
          discover: true,
        );
      case 'search':
        return SearchScreen(
          controller,
          key: const ValueKey('search'),
        );
      case 'ask':
        return AskScreen(controller);
      case 'memory':
        return MemoryScreen(controller);
      case 'wiki':
        return WikiScreen(controller);
      case 'notebooks':
        return NotebooksScreen(controller);
      case 'patterns':
        return PatternsScreen(controller);
      case 'experiments':
        return ExperimentsScreen(controller);
      case 'missions':
        return MissionsScreen(controller);
      case 'ticks':
        return TicksScreen(controller);
      case 'decisions':
        return DecisionsScreen(controller);
      case 'timeline':
        return TimelineScreen(controller);
      case 'outputs':
        return OutputsScreen(controller);
      case 'devices':
        return DevicesScreen(controller);
      case 'operations':
        return OperationsScreen(controller);
      case 'settings':
        return SettingsScreen(controller);
      default:
        return MineScreen(controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Brain2 AI Miner',
      theme: Brain2Theme.dark(),
      home: !controller.loaded
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.error == null)
                        const CircularProgressIndicator()
                      else
                        const Icon(
                          Icons.error_outline,
                          size: 42,
                          color: Colors.redAccent,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        controller.error ?? 'Opening local Brain2 memory…',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: controller.boot,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Brain2 AI Miner',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        'V9.6',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              drawer: Drawer(
                child: Builder(
                  builder: (drawerContext) => SafeArea(
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
                          child: Text(
                            'BRAIN2 AI MINER\nMOBILE INTELLIGENCE',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 0, 18, 14),
                          child: Text(
                            'Local-first · ContextVault · Brain2 Memory',
                            style: TextStyle(
                              color: Color(0xff9aa8b7),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        for (final item in _items) ...[
                          if (item.$1 == 'dashboard' ||
                              item.$1 == 'memory' ||
                              item.$1 == 'experiments' ||
                              item.$1 == 'devices')
                            const Divider(height: 12),
                          ListTile(
                            selected: page == item.$1,
                            leading: Icon(item.$3),
                            title: Text(item.$2),
                            onTap: () {
                              setState(() => page = item.$1);
                              Navigator.of(drawerContext).pop();
                            },
                          ),
                        ],
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Pairing: web creates QR · mobile scans and joins. Hard neural residuals remain fail-closed until a licensed local Qwen runtime is configured.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xff9aa8b7),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              body: KeyedSubtree(
                key: ValueKey(page),
                child: _screen(),
              ),
            ),
    );
  }
}

final _items = <(String, String, IconData)>[
  ('mine', 'Mine AI History', Icons.auto_awesome),
  ('miningHistory', 'Mining History', Icons.history_rounded),
  ('dashboard', 'Dashboard', Icons.dashboard_outlined),
  ('projects', 'Projects', Icons.folder_copy_outlined),
  ('conversations', 'Conversations', Icons.forum_outlined),
  ('discover', 'Discover', Icons.explore_outlined),
  ('search', 'Search', Icons.search),
  ('ask', 'Ask Brain2', Icons.auto_awesome_outlined),
  ('memory', 'Memory & .B2M', Icons.storage_outlined),
  ('wiki', 'LifeWiki', Icons.menu_book_outlined),
  ('notebooks', 'Live Notebooks', Icons.note_alt_outlined),
  ('patterns', 'Pattern Lab', Icons.hub_outlined),
  ('experiments', 'Experiments', Icons.science_outlined),
  ('missions', 'Missions', Icons.flag_outlined),
  ('ticks', 'Needs You · Ticks', Icons.task_alt_outlined),
  ('decisions', 'Decisions', Icons.gavel_outlined),
  ('timeline', 'Timeline', Icons.timeline_outlined),
  ('outputs', 'Outputs', Icons.inventory_2_outlined),
  ('devices', 'Devices & Sync', Icons.devices_outlined),
  ('operations', 'Operations', Icons.monitor_heart_outlined),
  ('settings', 'Settings', Icons.settings_outlined),
];
