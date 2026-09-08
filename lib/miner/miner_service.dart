import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import '../contextvault/contextvault_native.dart';
import 'multi_provider_export_extractor.dart';
import 'miner_history_repository.dart';
import 'miner_models.dart';

class MinerDigestResult {
  final MinerRunRecord run;
  final String preparedJsonPath;

  const MinerDigestResult({
    required this.run,
    required this.preparedJsonPath,
  });
}

class MinerService {
  final MinerHistoryRepository history;

  MinerService({MinerHistoryRepository? history})
      : history = history ?? MinerHistoryRepository();

  Future<MinerDigestResult> createDigest({
    required String inputPath,
    required String inputName,
    required int inputSize,
    required void Function(MinerProgress progress) onProgress,
  }) async {
    final totalWatch = Stopwatch()..start();
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    final root = await history.rootDirectory();
    final runDir = Directory(
      '${root.path}${Platform.pathSeparator}$id',
    );
    await runDir.create(recursive: true);

    final combinedJson = File(
      '${runDir.path}${Platform.pathSeparator}combined_conversations.json',
    );

    try {
      onProgress(
        const MinerProgress(
          stage: MinerStage.preparing,
          percent: 4,
          message: 'Preparing local processing workspace',
        ),
      );

      final extractionWatch = Stopwatch()..start();
      onProgress(
        const MinerProgress(
          stage: MinerStage.extracting,
          percent: 12,
          message: 'Reading AI conversation export',
        ),
      );
      final prepared = await MultiProviderExportExtractor().prepare(
        inputPath: inputPath,
        inputName: inputName,
        outputPath: combinedJson.path,
      );
      extractionWatch.stop();

      onProgress(
        MinerProgress(
          stage: MinerStage.extracting,
          percent: 28,
          message:
              'Detected ${prepared.providers.join(' + ')} · prepared ${prepared.jsonFileCount} conversation JSON file${prepared.jsonFileCount == 1 ? '' : 's'}',
        ),
      );

      final native = ContextVaultNative();
      if (!native.load() || !native.markdownFileAvailable) {
        throw StateError(
          'Native ContextVault is not installed in this Android build. '
          'Build and package arm64-v8a/libcontextvault.so first.',
        );
      }

      onProgress(
        const MinerProgress(
          stage: MinerStage.contextVault,
          percent: 38,
          message: 'ContextVault C++ is atomizing and generating Markdown',
        ),
      );
      final nativeWatch = Stopwatch()..start();
      final digestJson = await Isolate.run(
        () => _digestMarkdownFileNative(prepared.jsonPath),
      );
      nativeWatch.stop();

      final decodedRaw = jsonDecode(digestJson);
      if (decodedRaw is! Map) {
        throw StateError('ContextVault returned an unexpected digest payload.');
      }
      final decoded = decodedRaw.cast<String, Object?>();
      final statsRaw = decoded['stats'];
      final filesRaw = decoded['files'];
      if (statsRaw is! Map || filesRaw is! List) {
        throw StateError('ContextVault digest payload is missing stats/files.');
      }
      final stats = statsRaw.cast<String, Object?>();
      final files = filesRaw
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList(growable: false);

      onProgress(
        const MinerProgress(
          stage: MinerStage.packaging,
          percent: 76,
          message: 'Packaging Markdown as digest.zip',
        ),
      );
      final zipWatch = Stopwatch()..start();
      final generatedTemp = Directory(
        '${runDir.path}${Platform.pathSeparator}generated_tmp',
      );
      await generatedTemp.create(recursive: true);
      final outputZipPath = '${runDir.path}${Platform.pathSeparator}digest.zip';
      final encoder = ZipFileEncoder();
      encoder.create(outputZipPath);
      final generatedPaths = <String>[];

      try {
        for (final entry in files) {
          final path = _safeRelativePath('${entry['path'] ?? ''}');
          final content = '${entry['content'] ?? ''}';
          final local = File(_joinRelative(generatedTemp.path, path));
          await local.parent.create(recursive: true);
          await local.writeAsString(content, flush: false);
          encoder.addFileSync(local, path);
          generatedPaths.add(path);
        }
      } finally {
        encoder.closeSync();
        if (await generatedTemp.exists()) {
          await generatedTemp.delete(recursive: true);
        }
      }
      zipWatch.stop();

      final outputZipBytes = await File(outputZipPath).length();
      totalWatch.stop();
      final now = DateTime.now().toUtc();
      final run = MinerRunRecord(
        id: id,
        inputFileName: inputName,
        inputZipBytes: inputSize,
        jsonBytes: prepared.jsonBytes,
        jsonFileCount: prepared.jsonFileCount,
        paragraphs: _intStat(stats, 'paragraphs'),
        atoms: _intStat(stats, 'atoms'),
        threads: _intStat(stats, 'threads'),
        topicFiles: _intStat(stats, 'topic_files'),
        conversationsImported: 0,
        messagesImported: 0,
        extractionTimeMs: extractionWatch.elapsedMilliseconds,
        nativeProcessingTimeMs: nativeWatch.elapsedMilliseconds,
        outputZipTimeMs: zipWatch.elapsedMilliseconds,
        intelligenceImportTimeMs: 0,
        totalTimeMs: totalWatch.elapsedMilliseconds,
        outputZipBytes: outputZipBytes,
        nativeContextVaultUsed: true,
        completedAt: now,
        outputZipPath: outputZipPath,
        generatedFiles: generatedPaths,
        providers: prepared.providers,
      );

      onProgress(
        const MinerProgress(
          stage: MinerStage.packaging,
          percent: 82,
          message: 'Local digest is ready; importing Brain2 memory',
        ),
      );
      return MinerDigestResult(
        run: run,
        preparedJsonPath: prepared.jsonPath,
      );
    } catch (_) {
      if (await runDir.exists()) {
        try {
          await runDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }
}

int _intStat(Map<String, Object?> stats, String key) =>
    (stats[key] as num?)?.toInt() ?? 0;

String _safeRelativePath(String raw) {
  final path = raw.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  final parts = path.split('/');
  if (path.isEmpty ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw StateError('Unsafe digest file path: $raw');
  }
  return path;
}

String _joinRelative(String root, String relative) =>
    '$root${Platform.pathSeparator}${relative.split('/').join(Platform.pathSeparator)}';

String _digestMarkdownFileNative(String jsonPath) {
  final native = ContextVaultNative();
  if (!native.load() || !native.markdownFileAvailable) {
    throw StateError('ContextVault native file ABI is unavailable.');
  }
  return native.digestMarkdownFile(jsonPath);
}
