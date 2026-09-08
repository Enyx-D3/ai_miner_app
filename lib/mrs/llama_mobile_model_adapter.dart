import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'mobile_model_adapter.dart';
import 'mobile_model_manager.dart';

class LlamaMobileModelAdapter implements MobileModelAdapter {
  final MobileModelManager manager;
  final LlamaController _controller;
  Future<void>? _loadFuture;
  bool _loaded = false;

  LlamaMobileModelAdapter(
    this.manager, {
    LlamaController? controller,
  }) : _controller = controller ?? LlamaController();

  @override
  String get runtimeName => 'LLAMA_CPP_ANDROID';

  @override
  String get modelName => manager.manifest.id;

  Future<void> _ensureLoaded() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('The V1 GGUF runtime is Android ARM64 only.');
    }
    if (_loaded && await _controller.isModelLoaded()) return;
    final existing = _loadFuture;
    if (existing != null) return existing;

    final load = () async {
      final file = await manager.modelFile();
      if (!await manager.verifyFile(file)) {
        throw StateError(
          'The verified V1 mobile model is not installed. Download it from Settings first.',
        );
      }
      int? gpuLayers;
      try {
        final gpu = await _controller.detectGpu();
        gpuLayers = gpu.recommendedGpuLayers;
      } catch (_) {
        // CPU fallback is intentional. The model runtime remains usable when
        // Vulkan probing is unavailable or rejected by a device driver.
      }
      await _controller.loadModel(
        modelPath: file.path,
        threads: 4,
        contextSize: manager.manifest.contextSize,
        gpuLayers: gpuLayers,
      );
      _loaded = true;
    }();
    _loadFuture = load;
    try {
      await load;
    } finally {
      _loadFuture = null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      await _ensureLoaded();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _prompt({
    required String systemPrompt,
    required String userPrompt,
  }) {
    // SmolLM2 Instruct follows a ChatML-compatible message envelope.
    return '<|im_start|>system\n$systemPrompt<|im_end|>\n'
        '<|im_start|>user\n$userPrompt<|im_end|>\n'
        '<|im_start|>assistant\n';
  }

  @override
  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int maxNewTokens = 256,
  }) async {
    await _ensureLoaded();
    await _controller.clearContext();
    final output = StringBuffer();
    final stream = _controller.generate(
      prompt: _prompt(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      ),
      maxTokens: maxNewTokens.clamp(1, manager.manifest.maxNewTokens).toInt(),
      temperature: 0.2,
      topP: 0.9,
      topK: 40,
      repeatPenalty: 1.08,
    );
    await for (final token in stream) {
      output.write(token);
    }
    final text = output.toString().trim();
    if (text.isEmpty) {
      throw StateError('The local mobile model returned an empty response.');
    }
    return text;
  }

  Future<void> cancel() => _controller.stop();

  Future<void> dispose() async {
    if (_controller.isGenerating) await _controller.stop();
    await _controller.dispose();
    _loaded = false;
  }
}
