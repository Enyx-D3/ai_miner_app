import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mining_progress_screen.dart';
import 'projects_screen.dart';
import 'search_screen.dart';

class MineScreen extends StatefulWidget {
  final Brain2Controller controller;

  const MineScreen(this.controller, {super.key});

  @override
  State<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends State<MineScreen> {
  PlatformFile? _file;
  String? _error;
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip', 'json'],
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.path == null) {
        setState(() {
          _error = 'The selected export is not available as a local file.';
        });
        return;
      }
      const maxBytes = 2 * 1024 * 1024 * 1024;
      if (file.size > maxBytes) {
        setState(() {
          _error = 'This build supports AI export files up to 2 GB.';
        });
        return;
      }
      setState(() => _file = file);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _start() async {
    final file = _file;
    if (file == null || file.path == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiningProgressScreen(
          controller: widget.controller,
          inputPath: file.path!,
          inputName: file.name,
          inputSize: file.size,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nativeReady =
        widget.controller.contextVault.native.markdownFileAvailable;
    final projectCount = widget.controller.counts['projects'] ?? 0;
    final messagesCount = widget.controller.counts['messages'] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Page Header: ANDROID · AN01
        const GlobalContextPageHeader(
          tag: 'ANDROID · AN01',
          title: 'Today in your AI life',
          description: 'Pick up work without reopening old conversations',
        ),

        // Hero Card: PICK UP WHERE YOU LEFT OFF
        GlobalContextHeroCard(
          overline: 'PICK UP WHERE YOU LEFT OFF',
          title: 'Today in your AI life',
          subtitle:
              '$projectCount linked projects · recent context available offline',
          buttonText: 'Continue project ↗',
          onButtonPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Projects')),
                  body: ProjectsScreen(widget.controller),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 18),

        // Relevant Work Section
        GlobalContextSectionCard(
          title: 'Relevant work',
          badgeLabel: 'Concept',
          children: [
            GlobalContextActionTile(
              icon: Icons.auto_awesome,
              title: 'Continue',
              subtitle: projectCount > 0
                  ? 'Your active projects · $messagesCount verified records'
                  : 'Global Context design\nYour current project · 4 linked threads',
              actionLabel: 'Continue project >',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Projects')),
                      body: ProjectsScreen(widget.controller),
                    ),
                  ),
                );
              },
            ),
            GlobalContextActionTile(
              icon: Icons.search,
              title: 'Perfect Recall',
              subtitle: messagesCount > 0
                  ? '$messagesCount indexed messages\nIncludes earlier design decisions'
                  : '12 useful results\nIncludes earlier design decisions',
              actionLabel: 'Search >',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Perfect Recall')),
                      body: SearchScreen(widget.controller),
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Import Section (AN02_import.png)
        GlobalContextSectionCard(
          title: 'Import history',
          badgeLabel: 'Local-first',
          children: [
            // Dashed Upload Zone
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFE),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFCCE4F7),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Brain2Theme.primaryBlueLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Brain2Theme.primaryBlue,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _file == null
                          ? 'Select an archive'
                          : _file!.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Brain2Theme.textDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _file == null
                          ? (_picking
                              ? 'Opening file picker…'
                              : 'No archive is uploaded in this concept')
                          : formatBytes(_file!.size),
                      style: TextStyle(
                        fontSize: 13,
                        color: Brain2Theme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _file != null ? 1.0 : (_picking ? null : 0.4),
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Brain2Theme.primaryBlue,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Archive status tile
            GlobalContextActionTile(
              icon: Icons.archive_outlined,
              title: _file == null ? 'Archive' : _file!.name,
              subtitle: _file == null
                  ? 'ChatGPT export.zip\nIn the import queue · 342 MB'
                  : 'Selected export · ${formatBytes(_file!.size)}',
              actionLabel: _file == null ? 'Choose file >' : 'Change >',
              onTap: _pick,
            ),

            // Provider selection tile
            GlobalContextActionTile(
              icon: Icons.hub_outlined,
              title: 'Provider',
              subtitle: 'ChatGPT · Claude · Gemini\nAdd archives or connect a supported source',
              actionLabel: 'Select >',
              onTap: _pick,
            ),

            if (_file != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: nativeReady ? _start : null,
                  icon: const Icon(Icons.bolt_rounded, size: 20),
                  label: const Text('Mine This Export →'),
                ),
              ),
            ],

            if (!nativeReady) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ContextVault binary not detected. Compiling without native acceleration.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 18),

        // Local-first notice banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brain2Theme.heroCyan,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCCE4F7)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.security_rounded,
                color: Brain2Theme.primaryBlue,
                size: 20,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Source data is not silently promoted into global context or copied into another model. Processing happens locally first.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF244464),
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
