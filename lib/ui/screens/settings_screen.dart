import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_history_repository.dart';
import '../../mrs/mobile_model_manager.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  final Brain2Controller controller;

  const SettingsScreen(this.controller, {super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  String note = '';
  MobileModelStatus? modelStatus;
  bool modelBusy = false;
  double modelProgress = 0;

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  Future<void> _refreshModelStatus({bool verifyHash = false}) async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null) return;
    final next = await manager.status(verifyHash: verifyHash);
    if (mounted) setState(() => modelStatus = next);
  }

  Future<void> _downloadModel() async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null || modelBusy) return;
    setState(() {
      modelBusy = true;
      modelProgress = modelStatus?.progress ?? 0;
      note = '';
    });
    try {
      await manager.ensureDownloaded(onProgress: (progress) {
        if (mounted) setState(() => modelProgress = progress);
      });
      await _refreshModelStatus(verifyHash: true);
      if (mounted) setState(() => note = 'Local MRS model verified and ready.');
    } catch (error) {
      if (mounted) setState(() => note = 'Model download error: $error');
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _removeModel() async {
    final manager = widget.controller.mobileModelManager;
    if (manager == null || modelBusy) return;
    setState(() => modelBusy = true);
    try {
      await widget.controller.mobileModelAdapter?.dispose();
      await manager.remove();
      await _refreshModelStatus();
      if (mounted) setState(() => note = 'Local MRS model removed.');
    } finally {
      if (mounted) setState(() => modelBusy = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brain2Theme.cardBgOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clean Mining History?',
          style: TextStyle(
            color: Brain2Theme.textPrimaryOf(ctx),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Are you sure you want to delete all local mining run history and cached logs? This action cannot be undone.',
          style: TextStyle(
            color: Brain2Theme.textSecondaryOf(ctx),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Brain2Theme.textSecondaryOf(ctx)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clean', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      busy = true;
      note = '';
    });
    try {
      await MinerHistoryRepository().clear();
      if (mounted) {
        setState(() => note = 'Mining history cleaned successfully.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mining history cleaned successfully.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => note = 'Error clearing history: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nativeReady =
        widget.controller.contextVault.native.markdownFileAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Header: ANDROID · AN10
        const GlobalContextPageHeader(
          tag: 'ANDROID · AN10',
          title: 'Privacy & settings',
          description: 'Local-first controls, retention and export',
        ),

        // Dark Mode Toggle
        GlobalContextSectionCard(
          title: 'Appearance',
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Brain2Theme.pillBadgeBgOf(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.controller.themeMode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: Brain2Theme.primaryBlueOf(context),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dark mode',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Brain2Theme.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.controller.themeMode == ThemeMode.dark
                            ? 'On'
                            : 'Off',
                        style: TextStyle(
                          fontSize: 12,
                          color: Brain2Theme.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: widget.controller.themeMode == ThemeMode.dark,
                  activeColor: Brain2Theme.primaryBlueOf(context),
                  activeTrackColor: Brain2Theme.primaryBlueOf(context).withOpacity(0.4),
                  inactiveThumbColor: Brain2Theme.textSecondaryOf(context),
                  inactiveTrackColor: Brain2Theme.borderOf(context),
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  onChanged: (val) {
                    widget.controller.setThemeMode(
                      val ? ThemeMode.dark : ThemeMode.light,
                    );
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Scope and Permission Container (AN10_settings.png)
        GlobalContextSectionCard(
          title: 'Scope and permission',
          children: [
            Row(
              children: [
                const GlobalContextPillBadge(label: 'Private by default'),
                const SizedBox(width: 8),
                GlobalContextPillBadge(
                  label: 'Inspect before send',
                  color: Brain2Theme.isDark(context)
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFFE8F0FE),
                  textColor: Brain2Theme.primaryBlueOf(context),
                ),
                const SizedBox(width: 8),
                GlobalContextPillBadge(
                  label: 'R1 required',
                  color: Brain2Theme.isDark(context)
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFFE8F0FE),
                  textColor: Brain2Theme.primaryBlueOf(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            GlobalContextActionTile(
              icon: Icons.archive_outlined,
              title: 'Local archive',
              subtitle: 'Stored on your device\nEncryption and retention controls',
              actionLabel: 'Manage >',
              onTap: () {},
            ),

            GlobalContextActionTile(
              icon: Icons.share_outlined,
              title: 'Context sharing',
              subtitle: 'Ask every time\nOnly the selected capsule leaves the device',
              actionLabel: 'Preview >',
              onTap: () {},
            ),

            GlobalContextActionTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Clean mining history',
              subtitle: 'Stored on your device\nDelete all mining runs and cached records',
              actionLabel: busy ? 'Cleaning...' : 'Clean >',
              onTap: busy ? null : _clearHistory,
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brain2Theme.heroCardBgOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Brain2Theme.heroBorderOf(context)),
              ),
              child: Text(
                'Source data is not silently promoted into global context or copied into another model.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Brain2Theme.textPrimaryOf(context),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Runtime & MRS Container
        GlobalContextSectionCard(
          title: 'Local MRS model & intelligence',
          badgeLabel: 'On-device',
          children: [
            Text(
              widget.controller.mobileModelManager?.manifest.displayName ??
                  'Local Qwen/Llama Runtime',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Brain2Theme.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Runtime: ${widget.controller.mobileModelAdapter?.runtimeName ?? 'UNCONFIGURED'}\nState: ${modelStatus?.state.name.toUpperCase() ?? 'CHECKING'} · ContextVault: ${nativeReady ? 'C++ Active' : 'ARM64 binary required'}',
              style: TextStyle(
                color: Brain2Theme.textSecondaryOf(context),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (modelBusy) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: modelProgress > 0 ? modelProgress : null,
                  backgroundColor: Brain2Theme.isDark(context)
                      ? const Color(0xFF1E3A8A)
                      : Brain2Theme.primaryBlueLight,
                  color: Brain2Theme.primaryBlueOf(context),
                  minHeight: 6,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: modelBusy || modelStatus?.ready == true
                      ? null
                      : _downloadModel,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download & verify'),
                ),
                OutlinedButton.icon(
                  onPressed: modelBusy || modelStatus?.ready != true
                      ? null
                      : _removeModel,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove model'),
                ),
              ],
            ),
          ],
        ),

        if (note.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Brain2Theme.primaryBlueOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

