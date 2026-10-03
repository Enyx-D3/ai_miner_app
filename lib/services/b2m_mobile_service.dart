import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/contracts.dart';
import '../core/identity.dart';
import '../core/current_truth_firewall.dart';
import '../core/r1_authority.dart';
import '../intelligence/canonical_truth.dart';
import '../storage/brain2_database.dart';
import '../sync/sync_contract.dart';

class B2MImportResult {
  final String memoryRoot;
  final int records;
  final int tables;
  final bool hashVerified;

  const B2MImportResult({
    required this.memoryRoot,
    required this.records,
    required this.tables,
    required this.hashVerified,
  });
}

class B2MMobileService {
  final Brain2Database db;

  B2MMobileService(this.db);

  static const tables = <String>[
    'sources',
    'conversations',
    'messages',
    'atoms',
    'truths',
    'projects',
    'ticks',
    'decisions',
    'patterns',
    'experiments',
    'missions',
    'checkpoints',
    'verifications',
    'transactions',
    'patternTests',
    'portableExpertise',
    'databoxes',
    'evidenceBlocks',
    'capabilities',
    'reasoningTrajectories',
    'failureMemory',
    'mrsRuns',
    'intelligenceSnapshots',
    'wikiSnapshots',
    'notebookSnapshots',
  ];

  Future<File> exportSnapshot() async {
    final root = await db.memoryRoot();
    final payload = <String, Object?>{
      'format': 'B2M',
      'version': 10,
      'schemaVersion': brain2SchemaVersion,
      'identityVersion': brain2IdentityVersion,
      'memoryRoot': root,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': <String, Object?>{},
    };
    final map = payload['tables'] as Map<String, Object?>;
    for (final table in tables) {
      map[brain2WireTableForLocal(table)] = await db.records(table);
    }
    final hash = sha256Hex(canonicalJson(payload));
    payload['hash'] = hash;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/brain2-$root.b2m.json');
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }

  Future<void> shareSnapshot() async {
    final file = await exportSnapshot();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Brain2 AI Miner .B2M',
      ),
    );
  }

  Future<B2MImportResult?> pickAndImportSnapshot() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'b2m'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) {
      throw StateError(
          'The selected .B2M snapshot is not available as a local file.');
    }
    return importSnapshot(File(path), explicitUserAction: true);
  }

  Future<B2MImportResult> importSnapshot(File file,
      {Brain2R1Receipt? r1Authority, bool explicitUserAction = false}) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('Invalid .B2M JSON root.');
    final payload = decoded.cast<String, Object?>();
    if ('${payload['format']}' != 'B2M') {
      throw const FormatException('This file is not a Brain2 .B2M snapshot.');
    }

    var hashVerified = false;
    final suppliedHash = '${payload['hash'] ?? ''}'.trim();
    if (suppliedHash.isNotEmpty) {
      final unsigned = <String, Object?>{...payload}..remove('hash');
      final expected = sha256Hex(canonicalJson(unsigned));
      if (expected != suppliedHash) {
        throw const FormatException('.B2M integrity hash mismatch.');
      }
      hashVerified = true;
    }

    final snapshotRoot = '${payload['memoryRoot'] ?? ''}'.trim();
    if (snapshotRoot.isEmpty) {
      throw const FormatException('.B2M snapshot has no memoryRoot.');
    }

    final localMessages = await db.total('messages');
    final localRoot = await db.memoryRoot();
    if (localMessages > 0 && localRoot != snapshotRoot) {
      throw StateError(
        'B2M memory-root mismatch. Reset local memory before importing a different Brain2 replica.',
      );
    }
    final nested = payload['tables'];
    final tableMap = nested is Map
        ? nested.cast<String, Object?>()
        : <String, Object?>{
            for (final table in tables) table: payload[table],
          };
    final rawTruths = tableMap['truths'];
    final truths = rawTruths is List
        ? rawTruths
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
        : const <Map<String, Object?>>[];
    final currentTruths = truths
        .where((truth) => '${truth['status'] ?? ''}' == 'CURRENT')
        .toList(growable: false);
    final unsignedForScope = <String, Object?>{...payload}..remove('hash');
    final stateHash = sha256Hex(canonicalJson(unsignedForScope));
    final currentTruthRoot = buildCurrentTruthRoot(truths);
    if (currentTruths.isNotEmpty) {
      final context = currentTruthB2MImportContext(
          memoryRoot: snapshotRoot,
          stateHash: stateHash,
          currentTruthRoot: currentTruthRoot);
      var receipt = r1Authority;
      if (receipt == null && explicitUserAction) {
        receipt = issueUserR1Allow(
          action: brain2CurrentTruthR1Action,
          scope: context.scope,
          reason:
              'User explicitly selected a .B2M snapshot for canonical restore.',
          evidenceRefs: currentTruths.map((truth) => '${truth['id'] ?? ''}'),
        );
      }
      requireCurrentTruthAuthority(
          truths: currentTruths,
          receipt: receipt,
          context: context,
          authoritySource: 'EXPLICIT_USER_ACTION');
    }
    if (localMessages == 0 && localRoot != snapshotRoot) {
      await db.setMeta('memory_root', snapshotRoot);
    }

    var recordCount = 0;
    var tableCount = 0;
    for (final table in tables) {
      final raw = tableMap[brain2WireTableForLocal(table)] ?? tableMap[table];
      if (raw is! List || raw.isEmpty) continue;
      final records = <Map<String, Object?>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final record = item.cast<String, Object?>();
        final id = '${record['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        records.add(record);
      }
      if (records.isEmpty) continue;
      await db.putRecords(table, records);
      recordCount += records.length;
      tableCount++;
    }

    await db.rebuildReaderIndex();
    return B2MImportResult(
      memoryRoot: snapshotRoot,
      records: recordCount,
      tables: tableCount,
      hashVerified: hashVerified,
    );
  }
}
