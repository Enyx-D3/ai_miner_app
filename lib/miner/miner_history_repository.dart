import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'miner_models.dart';

class MinerHistoryRepository {
  Future<Directory> rootDirectory() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(
      '${base.path}${Platform.pathSeparator}brain2_ai_miner_runs',
    );
    await root.create(recursive: true);
    return root;
  }

  Future<List<MinerRunRecord>> loadRuns() async {
    final root = await rootDirectory();
    final runs = <MinerRunRecord>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(
        '${entity.path}${Platform.pathSeparator}run.json',
      );
      if (!await meta.exists()) continue;
      try {
        final raw = jsonDecode(await meta.readAsString());
        if (raw is! Map) continue;
        final run = MinerRunRecord.fromJson(raw.cast<String, Object?>());
        if (await File(run.outputZipPath).exists()) runs.add(run);
      } catch (_) {
        // Ignore incomplete run metadata instead of breaking History.
      }
    }
    runs.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return runs;
  }

  Future<void> save(MinerRunRecord run) async {
    final root = await rootDirectory();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}${run.id}',
    );
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}run.json')
        .writeAsString(run.encode(), flush: true);
  }

  Future<void> clear() async {
    final root = await rootDirectory();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
  }
}
