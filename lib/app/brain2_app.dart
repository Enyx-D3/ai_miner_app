import 'package:flutter/material.dart';

import '../ui/screens/ask_screen.dart';
import '../ui/screens/attention_preferences_screen.dart';
import '../ui/screens/context_handoff_screen.dart';
import '../ui/screens/onboarding_screen.dart';
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
import '../ui/widgets.dart';
import 'brain2_controller.dart';

class Brain2App extends StatefulWidget {
  const Brain2App({super.key});

  @override
  State<Brain2App> createState() => _Brain2AppState();
}

class _Brain2AppState extends State<Brain2App> {
  final Brain2Controller controller = Brain2Controller();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String page = 'mine';

  int get _currentNavIndex {
    switch (page) {
      case 'mine':
      case 'dashboard':
      case 'miningHistory':
        return 0;
      case 'search':
      case 'discover':
      case 'ask':
        return 1;
      case 'projects':
      case 'conversations':
        return 2;
      case 'notebooks':
      case 'wiki':
      case 'memory':
        return 3;
      case 'settings':
      case 'devices':
      case 'ticks':
      case 'decisions':
      case 'experiments':
      case 'missions':
      case 'operations':
      case 'timeline':
      case 'outputs':
      case 'patterns':
      default:
        return 4;
    }
  }

  void _onBottomNavTapped(int index) {
    setState(() {
      switch (index) {
        case 0:
          page = 'mine';
          break;
        case 1:
          page = 'search';
          break;
        case 2:
          page = 'projects';
          break;
        case 3:
          page = 'notebooks';
          break;
        case 4:
          page = 'settings';
          break;
      }
    });
  }

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
    if (!mounted) return;
    final shared = controller.pendingSharedText;
    if (shared != null && shared.isNotEmpty && page != 'handoff') {
      setState(() => page = 'handoff');
    } else {
      setState(() {});
    }
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
      case 'handoff':
        return ContextHandoffScreen(controller,
            initialTask: controller.pendingSharedText,
            onConsumed: controller.consumePendingShare);
      case 'attention':
        return const AttentionPreferencesScreen();
      case 'settings':
        return SettingsScreen(controller);
      default:
        return MineScreen(controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticksCount = controller.counts['ticks'] ?? 1;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Global Context',
      theme: Brain2Theme.light(),
      darkTheme: Brain2Theme.dark(),
      themeMode: controller.themeMode,
      home: Builder(
        builder: (context) {
          if (!controller.loaded) {
            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Brain2Theme.primaryBlue,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Brain2Theme.primaryBlue
                                  .withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'G',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 34,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (controller.error == null)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Brain2Theme.primaryBlue,
                          ),
                        )
                      else
                        const Icon(
                          Icons.error_outline,
                          size: 40,
                          color: Colors.redAccent,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        controller.error ??
                            'Opening local Global Context memory…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Brain2Theme.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (controller.error != null)
                        FilledButton(
                          onPressed: controller.boot,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (!controller.onboardingComplete) {
            return GlobalContextOnboardingScreen(controller);
          }
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(62),
              child: SafeArea(
                child: GlobalContextBrandHeader(
                  onSearch: () => setState(() => page = 'search'),
                  onMore: () => _scaffoldKey.currentState?.openDrawer(),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, size: 22),
                        color: Brain2Theme.textSecondaryOf(context),
                        splashRadius: 20,
                        onPressed: () => setState(() => page = 'search'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, size: 24),
                        color: Brain2Theme.textSecondaryOf(context),
                        splashRadius: 20,
                        onPressed: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            drawer: Drawer(
              backgroundColor: Brain2Theme.cardBgOf(context),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Brain2Theme.primaryBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GLOBAL CONTEXT',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: Brain2Theme.textPrimaryOf(context),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Local-first · All Intelligence Views',
                                style: TextStyle(
                                  color: Brain2Theme.textSecondaryOf(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Brain2Theme.borderOf(context)),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        children: [
                          for (final item in _items) ...[
                            if (item.$1 == 'dashboard' ||
                                item.$1 == 'memory' ||
                                item.$1 == 'experiments' ||
                                item.$1 == 'devices')
                              Divider(
                                  height: 16,
                                  color: Brain2Theme.borderOf(context)),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: page == item.$1
                                    ? (Brain2Theme.isDark(context)
                                        ? const Color(0xFF1E3A8A)
                                        : Brain2Theme.primaryBlueLight)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: Icon(
                                  item.$3,
                                  color: page == item.$1
                                      ? Brain2Theme.primaryBlueOf(context)
                                      : Brain2Theme.textSecondaryOf(context),
                                  size: 20,
                                ),
                                title: Text(
                                  item.$2,
                                  style: TextStyle(
                                    fontWeight: page == item.$1
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: page == item.$1
                                        ? Brain2Theme.primaryBlueOf(context)
                                        : Brain2Theme.textPrimaryOf(context),
                                    fontSize: 13.5,
                                  ),
                                ),
                                onTap: () {
                                  setState(() => page = item.$1);
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(page),
                    child: _screen(),
                  ),
                ),
                if (page != 'ticks')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: GlobalContextTickBanner(
                      count: ticksCount,
                      onReview: () => setState(() => page = 'ticks'),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: Brain2Theme.cardBgOf(context),
                border: Border(
                  top: BorderSide(
                      color: Brain2Theme.borderOf(context), width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(
                        context,
                        index: 0,
                        label: 'Home',
                        iconBuilder: (color, selected) => CleanHomeIcon(
                          color: color,
                          size: 22,
                          strokeWidth: selected ? 2.1 : 1.8,
                        ),
                      ),
                      _buildNavItem(
                        context,
                        index: 1,
                        label: 'Search',
                        iconBuilder: (color, selected) => CleanSearchIcon(
                          color: color,
                          size: 22,
                          strokeWidth: selected ? 2.1 : 1.8,
                        ),
                      ),
                      _buildNavItem(
                        context,
                        index: 2,
                        label: 'Projects',
                        iconBuilder: (color, selected) => CleanProjectsIcon(
                          color: color,
                          size: 22,
                          strokeWidth: selected ? 2.1 : 1.8,
                        ),
                      ),
                      _buildNavItem(
                        context,
                        index: 3,
                        label: 'Knowledge',
                        iconBuilder: (color, selected) => Icon(
                          selected
                              ? Icons.auto_stories_rounded
                              : Icons.auto_stories_outlined,
                          size: 22,
                          color: color,
                        ),
                      ),
                      _buildNavItem(
                        context,
                        index: 4,
                        label: 'More',
                        iconBuilder: (color, selected) => Icon(
                          selected
                              ? Icons.settings_rounded
                              : Icons.settings_outlined,
                          size: 22,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    IconData? icon,
    IconData? activeIcon,
    required String label,
    Widget Function(Color color, bool selected)? iconBuilder,
  }) {
    final selected = _currentNavIndex == index;
    final color = selected
        ? Brain2Theme.primaryBlueOf(context)
        : Brain2Theme.textSecondaryOf(context);
    return InkWell(
      onTap: () => _onBottomNavTapped(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconBuilder != null)
              iconBuilder(color, selected)
            else
              Icon(
                selected ? (activeIcon ?? icon) : icon,
                size: 22,
                color: color,
              ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
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
