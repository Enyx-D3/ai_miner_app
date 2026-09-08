import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../../miner/miner_formatters.dart';
import 'mining_progress_screen.dart';

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xff7c4dff).withOpacity(0.15),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xffa970ff),
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Brain2 AI Miner',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mine ChatGPT, Claude, Gemini and other supported AI exports into one local Markdown archive and living Brain2 intelligence replica.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xff9aa8b7), height: 1.5),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: nativeReady
                ? const Color(0xff31d6a1).withOpacity(0.08)
                : Colors.orange.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: nativeReady
                  ? const Color(0xff31d6a1).withOpacity(0.28)
                  : Colors.orange.withOpacity(0.32),
            ),
          ),
          child: Row(
            children: [
              Icon(
                nativeReady ? Icons.verified : Icons.warning_amber_rounded,
                color: nativeReady ? const Color(0xff31d6a1) : Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nativeReady
                      ? 'Native ContextVault C++ ready'
                      : 'ContextVault ARM64 binary not loaded. Build/install libcontextvault.so before mining.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_file == null)
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
              decoration: BoxDecoration(
                color: const Color(0xff0c1925),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xff7c4dff)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.upload_file_rounded,
                    color: Color(0xffa970ff),
                    size: 38,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Select AI Conversation Export',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _picking
                        ? 'Opening file picker…'
                        : 'Choose .zip or .json · ChatGPT / Claude / Gemini / more',
                    style: const TextStyle(color: Color(0xff9aa8b7)),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Icon(
                    Icons.folder_zip_rounded,
                    color: Color(0xffa970ff),
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _file!.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    formatBytes(_file!.size),
                    style: const TextStyle(color: Color(0xff9aa8b7)),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: nativeReady ? _start : null,
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Mine This Export'),
                    ),
                  ),
                  TextButton(
                    onPressed: _pick,
                    child: const Text('Choose another file'),
                  ),
                ],
              ),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 18),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: Color(0xffa970ff)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Local-first flow\nYour export stays on the phone. The same run creates digest.zip, canonical memory, Current Truth, Projects, LifeWiki and Live Notebooks.',
                    style: TextStyle(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
