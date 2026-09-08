import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../core/contracts.dart';
import '../core/identity.dart';
import '../models/mutation.dart';
import '../sync/sync_contract.dart';

class MutationCommittedEvent {
  final MutationRecord mutation;
  final bool remote;
  const MutationCommittedEvent(this.mutation, {required this.remote});
}

class Brain2Database {
  Database? _db;
  final StreamController<MutationCommittedEvent> _mutationEvents =
      StreamController.broadcast(sync: true);
  Database get db => _db!;
  Stream<MutationCommittedEvent> get mutationEvents => _mutationEvents.stream;

  static const _searchableTables = <String>{
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
    'verifications',
    'databoxes',
    'evidenceBlocks',
    'capabilities',
    'reasoningTrajectories',
    'failureMemory',
    'mrsRuns',
    'intelligenceSnapshots',
    'wikiSnapshots',
    'notebookSnapshots'
  };

  Future<void> open() async {
    final p = join(await getDatabasesPath(), 'brain2_ai_miner_v9_0_2.db');
    _db = await openDatabase(
      p,
      version: 11, // V11 adds locked-MRS persistent intelligence tables.
      onConfigure: (d) async {
        // journal_mode returns a result row, so use rawQuery.
        final walResult = await d.rawQuery('PRAGMA journal_mode=WAL');

        // These are assignments; do NOT use rawQuery for them.
        await d.execute('PRAGMA synchronous=NORMAL');
        await d.execute('PRAGMA temp_store=MEMORY');
        await d.execute('PRAGMA cache_size=-32768');

        await d.execute('PRAGMA foreign_keys=ON');

        print('Brain2 SQLite WAL: $walResult');
      },
      onCreate: (d, v) async => _createSchema(d),
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 10) await _createReaderTables(d);
        if (oldVersion < 11) await _createLockedArchitectureTables(d);
      },
    );
    await _ensureMeta('schema_version', '$brain2SchemaVersion');
    await _ensureMeta('storage_migration', '11');
    await _ensureMeta('memory_root',
        canonicalId('b2m', [DateTime.now().toUtc().toIso8601String(), p]));
    await _ensureMeta('origin_sequence', '0');
    await _ensureMeta('reader_index_state', 'UNKNOWN');
    await _createJsonLookupIndexes();
  }

  Future<void> _createJsonLookupIndexes() async {
    // These expression indexes keep import-time intelligence lookups bounded
    // without changing the canonical JSON record schema. If an unusual SQLite
    // build lacks JSON functions, the app still works via the query fallback.
    try {
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_messages_conversation_json "
        "ON messages(json_extract(json, '\$.conversationId'))",
      );
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_truths_project_kind_json "
        "ON truths(json_extract(json, '\$.projectId'), "
        "json_extract(json, '\$.kind'), updated_at)",
      );
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_atoms_project_json "
        "ON atoms(json_extract(json, '\$.projectId'), updated_at)",
      );
    } catch (_) {
      // Compatibility fallback is handled by recordsByJsonFields().
    }
  }

  Future<void> _createSchema(DatabaseExecutor d) async {
    for (final t in [
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
      'evidenceBlocks'
    ]) {
      await d.execute(
          'CREATE TABLE IF NOT EXISTS $t (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at TEXT)');
    }
    await d.execute(
        'CREATE TABLE IF NOT EXISTS mutations (id TEXT PRIMARY KEY, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL, json TEXT NOT NULL, payload_hash TEXT NOT NULL, hash TEXT NOT NULL, applied_at TEXT, UNIQUE(origin_device_id,origin_sequence))');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS sync_peers (peer_device_id TEXT PRIMARY KEY, json TEXT NOT NULL)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createReaderTables(d);
    await _createLockedArchitectureTables(d);
  }

  Future<void> _createLockedArchitectureTables(DatabaseExecutor d) async {
    for (final t in [
      'capabilities',
      'reasoningTrajectories',
      'failureMemory',
      'mrsRuns',
      'intelligenceSnapshots',
      'wikiSnapshots',
      'notebookSnapshots'
    ]) {
      await d.execute(
          'CREATE TABLE IF NOT EXISTS $t (id TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at TEXT)');
    }
  }

  Future<void> _createReaderTables(DatabaseExecutor d) async {
    await d.execute(
        'CREATE TABLE IF NOT EXISTS reader_search_docs (doc_id TEXT PRIMARY KEY, table_name TEXT NOT NULL, record_id TEXT NOT NULL, text_norm TEXT NOT NULL, record_hash TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await d.execute(
        'CREATE INDEX IF NOT EXISTS idx_reader_table_record ON reader_search_docs(table_name, record_id)');
    await d.execute(
        'CREATE TABLE IF NOT EXISTS sync_cursors (peer_device_id TEXT NOT NULL, origin_device_id TEXT NOT NULL, sequence INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(peer_device_id,origin_device_id))');
  }

  Future<void> _ensureMeta(String k, String v) async =>
      db.insert('meta', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.ignore);
  Future<String> meta(String key) async {
    final rows =
        await db.query('meta', where: 'key=?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return '';
    return rows.first['value'] as String? ?? '';
  }

  Future<void> setMeta(String key, String value) =>
      db.insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
  Future<String> memoryRoot() => meta('memory_root');

  Future<int> nextOriginSequence() async {
    return db.transaction((txn) async {
      final rows = await txn.query('meta',
          where: 'key=?', whereArgs: ['origin_sequence'], limit: 1);
      final n = rows.isEmpty ? 0 : int.tryParse('${rows.first['value']}') ?? 0;
      final next = n + 1;
      await txn.insert('meta', {'key': 'origin_sequence', 'value': '$next'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      return next;
    });
  }

  Future<void> putRecord(String table, Map<String, Object?> record) async {
    final id = '${record['id']}';
    if (id.isEmpty) throw ArgumentError('record id required');
    await db.transaction((txn) async {
      await _putRecordTxn(txn, table, record);
      await _upsertReaderDocTxn(txn, table, record);
    });
  }

  Future<void> _putRecordTxn(
      DatabaseExecutor txn, String table, Map<String, Object?> record) async {
    await txn.insert(
        table,
        {
          'id': '${record['id']}',
          'json': jsonEncode(record),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertReaderDocTxn(
      DatabaseExecutor txn, String table, Map<String, Object?> record) async {
    if (!_searchableTables.contains(table)) return;
    final id = '${record['id']}';
    if (id.isEmpty) return;
    final text = _readerText(record);
    final docId = canonicalId('rdoc', [table, id]);
    await txn.insert(
        'reader_search_docs',
        {
          'doc_id': docId,
          'table_name': table,
          'record_id': id,
          'text_norm': normalizeText(text).toLowerCase(),
          'record_hash': hashEntity(record),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String _readerText(Map<String, Object?> record) {
    final selected = <Object?>[
      record['title'],
      record['name'],
      record['text'],
      record['content'],
      record['value'],
      record['subject'],
      record['summary'],
      record['description'],
      record['status'],
      record['provider']
    ].where((x) => x != null).join(' ');
    return selected.isNotEmpty ? selected : canonicalJson(record);
  }

  Future<void> ensureReaderIndex() async {
    final state = await meta('reader_index_state');
    if (state == 'READY' || state == 'EMPTY') return;
    await setMeta('reader_index_state', 'BUILDING');
    try {
      await db.transaction((txn) async {
        await txn.delete('reader_search_docs');
        var total = 0;
        for (final table in _searchableTables) {
          final rows = await txn.query(table);
          total += rows.length;
          for (final row in rows) {
            final record = (jsonDecode(row['json'] as String) as Map)
                .cast<String, Object?>();
            await _upsertReaderDocTxn(txn, table, record);
          }
        }
        await txn.insert(
            'meta',
            {
              'key': 'reader_index_state',
              'value': total == 0 ? 'EMPTY' : 'READY'
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } catch (_) {
      await setMeta('reader_index_state', 'ERROR');
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> readerRecent(
      {int limit = 96, Set<String>? tables}) async {
    var where = '';
    final args = <Object?>[];
    if (tables != null && tables.isNotEmpty) {
      where = 'table_name IN (${List.filled(tables.length, '?').join(',')})';
      args.addAll(tables);
    }
    final rows = await db.query(
      'reader_search_docs',
      where: where.isEmpty ? null : where,
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'updated_at DESC, record_id ASC',
      limit: limit,
    );
    return rows.map((r) => {...r, 'score': 1}).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> readerCandidates(List<String> terms,
      {int limit = 96, Set<String>? tables}) async {
    if (terms.isEmpty) return const [];
    final clauses = <String>[];
    final args = <Object?>[];
    for (final term in terms.take(8)) {
      clauses.add('text_norm LIKE ?');
      args.add('%${term.replaceAll('%', '').replaceAll('_', '')}%');
    }
    var where = '(${clauses.join(' OR ')})';
    if (tables != null && tables.isNotEmpty) {
      where +=
          ' AND table_name IN (${List.filled(tables.length, '?').join(',')})';
      args.addAll(tables);
    }
    final rows = await db.query('reader_search_docs',
        where: where, whereArgs: args, limit: limit * 2);
    final scored = rows
        .map((row) {
          final text = '${row['text_norm']}';
          var score = 0;
          for (final term in terms) {
            if (text.contains(term)) score++;
          }
          return {...row, 'score': score};
        })
        .where((r) => (r['score'] as int) > 0)
        .toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return scored.take(limit).toList(growable: false);
  }

  Future<Map<String, Object?>?> getRecord(String table, String id) async {
    final rows =
        await db.query(table, where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return (jsonDecode(rows.first['json'] as String) as Map)
        .cast<String, Object?>();
  }

  Future<List<Map<String, Object?>>> allRecords(String table) async =>
      (await db.query(table))
          .map((r) =>
              (jsonDecode(r['json'] as String) as Map).cast<String, Object?>())
          .toList();

  Future<void> deleteRecord(String table, String id) async {
    await db.transaction((txn) async {
      await txn.delete(table, where: 'id=?', whereArgs: [id]);
      await txn.delete('reader_search_docs',
          where: 'table_name=? AND record_id=?', whereArgs: [table, id]);
    });
  }

  Future<int> total(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  Future<List<MutationRecord>> pendingLocalAfter(
      String localDeviceId, int after,
      {int limit = 128}) async {
    final rows = await db.query('mutations',
        where: 'origin_device_id=? AND origin_sequence>?',
        whereArgs: [localDeviceId, after],
        orderBy: 'origin_sequence ASC',
        limit: limit);
    return rows.map(_mutationFromRow).toList();
  }

  Future<int> peerCursor(String peerDeviceId, String originDeviceId) async {
    final rows = await db.query('sync_cursors',
        where: 'peer_device_id=? AND origin_device_id=?',
        whereArgs: [peerDeviceId, originDeviceId],
        limit: 1);
    return rows.isEmpty ? 0 : (rows.first['sequence'] as int? ?? 0);
  }

  Future<void> setPeerCursor(
      String peerDeviceId, String originDeviceId, int sequence) async {
    final current = await peerCursor(peerDeviceId, originDeviceId);
    if (sequence <= current) return;
    await db.insert(
        'sync_cursors',
        {
          'peer_device_id': peerDeviceId,
          'origin_device_id': originDeviceId,
          'sequence': sequence
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  MutationRecord _mutationFromRow(Map<String, Object?> row) {
    final j =
        (jsonDecode(row['json'] as String) as Map).cast<String, Object?>();
    final p = (j['payload'] as Map).cast<String, Object?>();
    final writes = ((p['writes'] as Map?) ?? {}).map((k, v) => MapEntry('$k',
        (v as List).map((e) => (e as Map).cast<String, Object?>()).toList()));
    final deletes = ((p['deletes'] as Map?) ?? {})
        .map((k, v) => MapEntry('$k', (v as List).map((e) => '$e').toList()));
    return MutationRecord(
        id: '${j['id']}',
        type: '${j['type']}',
        entityType: '${j['entityType']}',
        entityId: '${j['entityId']}',
        createdAt: '${j['createdAt']}',
        deviceId: '${j['deviceId']}',
        hash: '${j['hash']}',
        memoryRoot: '${j['memoryRoot']}',
        originDeviceId: '${j['originDeviceId']}',
        originSequence: j['originSequence'] as int,
        payloadHash: '${j['payloadHash']}',
        payload: MutationDeltaPayload(
            operation: '${p['operation']}',
            writes: writes,
            deletes: deletes,
            primaryTable: p['primaryTable'] as String?),
        parentMutationIds:
            (j['parentMutationIds'] as List? ?? []).map((e) => '$e').toList(),
        beforeHash: j['beforeHash'] as String?,
        afterHash: j['afterHash'] as String?);
  }

  Future<void> storeMutation(MutationRecord m,
      {String? appliedAt, bool remote = false}) async {
    await db.insert(
        'mutations',
        {
          'id': m.id,
          'origin_device_id': m.originDeviceId,
          'origin_sequence': m.originSequence,
          'json': jsonEncode(m.toJson()),
          'payload_hash': m.payloadHash,
          'hash': m.hash,
          'applied_at': appliedAt
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    _mutationEvents.add(MutationCommittedEvent(m, remote: remote));
  }

  /// Atomically commits a locally-created mutation and every record it writes.
  /// This is the mobile equivalent of the web importer's conversation-sized
  /// atomic transaction and avoids thousands of one-record SQLite commits.
  Future<void> commitLocalMutation(MutationRecord m) async {
    await db.transaction((txn) async {
      for (final entry in m.payload.writes.entries) {
        for (final record in entry.value) {
          await _putRecordTxn(txn, entry.key, record);
          await _upsertReaderDocTxn(txn, entry.key, record);
        }
      }
      for (final entry in m.payload.deletes.entries) {
        for (final id in entry.value) {
          await txn.delete(entry.key, where: 'id=?', whereArgs: [id]);
          await txn.delete(
            'reader_search_docs',
            where: 'table_name=? AND record_id=?',
            whereArgs: [entry.key, id],
          );
        }
      }
      await txn.insert(
        'mutations',
        {
          'id': m.id,
          'origin_device_id': m.originDeviceId,
          'origin_sequence': m.originSequence,
          'json': jsonEncode(m.toJson()),
          'payload_hash': m.payloadHash,
          'hash': m.hash,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.insert(
        'meta',
        {'key': 'reader_index_state', 'value': 'READY'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _mutationEvents.add(MutationCommittedEvent(m, remote: false));
  }

  Future<bool> applyMutation(MutationRecord m) async {
    final duplicate = await db.query(
      'mutations',
      columns: ['id'],
      where: 'id=?',
      whereArgs: [m.id],
      limit: 1,
    );
    if (duplicate.isNotEmpty) return false;

    final root = await memoryRoot();
    if (root != m.memoryRoot) throw StateError('memory-root mismatch');
    final payloadHash = sha256Hex(canonicalJson(m.payload.toJson()));
    if (payloadHash != m.payloadHash) throw StateError('payload hash mismatch');
    final expected = MutationRecord.envelopeHash(
      memoryRoot: m.memoryRoot,
      originDeviceId: m.originDeviceId,
      originSequence: m.originSequence,
      type: m.type,
      entityType: m.entityType,
      entityId: m.entityId,
      payloadHash: m.payloadHash,
      parents: m.parentMutationIds,
    );
    if (expected != m.hash) throw StateError('mutation envelope hash mismatch');

    await db.transaction((txn) async {
      for (final entry in m.payload.writes.entries) {
        final wireTable = brain2WireTableForLocal(entry.key);
        if (!brain2SupportsWireTable(wireTable)) {
          throw StateError('unsupported replicated table: ${entry.key}');
        }
        final localTable = brain2LocalTableForWire(wireTable);
        for (final record in entry.value) {
          await _putRecordTxn(txn, localTable, record);
          await _upsertReaderDocTxn(txn, localTable, record);
        }
      }
      for (final entry in m.payload.deletes.entries) {
        final wireTable = brain2WireTableForLocal(entry.key);
        if (!brain2SupportsWireTable(wireTable)) {
          throw StateError('unsupported replicated table: ${entry.key}');
        }
        final localTable = brain2LocalTableForWire(wireTable);
        for (final id in entry.value) {
          await txn.delete(localTable, where: 'id=?', whereArgs: [id]);
          await txn.delete(
            'reader_search_docs',
            where: 'table_name=? AND record_id=?',
            whereArgs: [localTable, id],
          );
        }
      }
      await txn.insert(
        'mutations',
        {
          'id': m.id,
          'origin_device_id': m.originDeviceId,
          'origin_sequence': m.originSequence,
          'json': jsonEncode(m.toJson()),
          'payload_hash': m.payloadHash,
          'hash': m.hash,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.insert(
        'meta',
        {'key': 'reader_index_state', 'value': 'READY'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _mutationEvents.add(MutationCommittedEvent(m, remote: true));
    return true;
  }

  Future<void> close() async {
    await _mutationEvents.close();
    await _db?.close();
    _db = null;
  }

  Future<List<Map<String, Object?>>> records(
    String table, {
    String? orderBy,
    int? limit,
  }) async {
    final rows = await db.query(table, orderBy: orderBy, limit: limit);
    return rows
        .map((r) =>
            (jsonDecode(r['json'] as String) as Map).cast<String, Object?>())
        .toList();
  }

  /// Query JSON-backed records by one or more top-level fields without
  /// materializing the whole table in Dart. Modern Android SQLite includes
  /// JSON functions; a conservative Dart fallback is kept for older builds.
  Future<List<Map<String, Object?>>> recordsByJsonFields(
    String table,
    Map<String, Object?> filters, {
    bool newestFirst = false,
    int? limit,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(table)) {
      throw ArgumentError.value(table, 'table', 'Unsafe table name');
    }
    for (final field in filters.keys) {
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(field)) {
        throw ArgumentError.value(field, 'field', 'Unsafe JSON field name');
      }
    }

    if (filters.isEmpty) {
      return records(
        table,
        orderBy: newestFirst ? 'updated_at DESC' : null,
        limit: limit,
      );
    }

    final clauses = <String>[];
    final args = <Object?>[];
    for (final entry in filters.entries) {
      clauses.add("json_extract(json, '\$.${entry.key}') = ?");
      args.add(entry.value);
    }
    final limitSql = limit == null ? '' : ' LIMIT $limit';
    final orderSql = newestFirst ? ' ORDER BY updated_at DESC' : '';

    try {
      final rows = await db.rawQuery(
        'SELECT json FROM $table WHERE ${clauses.join(' AND ')}'
        '$orderSql$limitSql',
        args,
      );
      return rows
          .map(
            (row) => (jsonDecode(row['json'] as String) as Map)
                .cast<String, Object?>(),
          )
          .toList(growable: false);
    } catch (_) {
      // Safe compatibility fallback. This should only be needed on an unusual
      // SQLite build without JSON functions.
      final all = await records(
        table,
        orderBy: newestFirst ? 'updated_at DESC' : null,
      );
      final matching = all.where((record) {
        for (final entry in filters.entries) {
          if (record[entry.key] != entry.value) return false;
        }
        return true;
      });
      return (limit == null ? matching : matching.take(limit))
          .toList(growable: false);
    }
  }

  Future<List<Map<String, Object?>>> recordsWhere(
    String table, {
    required bool Function(Map<String, Object?>) test,
    String? orderBy,
    int? limit,
  }) async {
    final rows = await records(table, orderBy: orderBy);
    final filtered = rows.where(test);
    return (limit == null ? filtered : filtered.take(limit))
        .toList(growable: false);
  }

  Future<void> putRecords(
      String table, Iterable<Map<String, Object?>> records) async {
    await db.transaction((txn) async {
      for (final record in records) {
        await _putRecordTxn(txn, table, record);
        await _upsertReaderDocTxn(txn, table, record);
      }
    });
  }

  Future<Map<String, int>> counts() async {
    final out = <String, int>{};
    for (final t in [
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
      'mutations'
    ]) {
      out[t] = await total(t);
    }
    return out;
  }

  Future<void> resetLocalMemory() async {
    final path = db.path;
    await _mutationEvents.close();
    await db.close();
    _db = null;
    await deleteDatabase(path);
  }

  Future<void> rebuildReaderIndex() async {
    await setMeta('reader_index_state', 'UNKNOWN');
    await ensureReaderIndex();
  }

  static const syncBootstrapTables = <String>[
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
    'notebookSnapshots'
  ];

  Future<List<Map<String, Object?>>> bootstrapRecords(String table) async {
    return bootstrapRecordsPage(table, offset: 0, limit: 1 << 30);
  }

  Future<List<Map<String, Object?>>> bootstrapRecordsPage(
    String localTable, {
    required int offset,
    int limit = 256,
  }) async {
    if (localTable == 'mutations') {
      final rows = await db.query(
        'mutations',
        orderBy: 'origin_sequence ASC',
        limit: limit,
        offset: offset,
      );
      return rows
          .map(
            (r) => (jsonDecode(r['json'] as String) as Map)
                .cast<String, Object?>(),
          )
          .toList(growable: false);
    }
    final rows = await db.query(localTable, limit: limit, offset: offset);
    return rows
        .map(
          (r) =>
              (jsonDecode(r['json'] as String) as Map).cast<String, Object?>(),
        )
        .toList(growable: false);
  }

  Future<void> applyBootstrapChunk(
    String memoryRoot,
    String wireTable,
    List<Map<String, Object?>> records,
  ) async {
    if (memoryRoot != await this.memoryRoot()) {
      throw StateError('bootstrap memory-root mismatch');
    }
    await db.transaction((txn) async {
      if (wireTable == 'mutations') {
        for (final r in records) {
          final p = (r['payload'] as Map?)?.cast<String, Object?>();
          if (p == null) continue;
          final writes = ((p['writes'] as Map?) ?? {}).map(
            (k, v) => MapEntry(
              '$k',
              (v as List)
                  .map((e) => (e as Map).cast<String, Object?>())
                  .toList(),
            ),
          );
          final deletes = ((p['deletes'] as Map?) ?? {}).map(
            (k, v) => MapEntry('$k', (v as List).map((e) => '$e').toList()),
          );
          final rawSequence = r['originSequence'];
          final sequence = rawSequence is num
              ? rawSequence.toInt()
              : int.parse('$rawSequence');
          final m = MutationRecord(
            id: '${r['id']}',
            type: '${r['type']}',
            entityType: '${r['entityType']}',
            entityId: '${r['entityId']}',
            createdAt: '${r['createdAt']}',
            deviceId: '${r['deviceId']}',
            hash: '${r['hash']}',
            memoryRoot: '${r['memoryRoot']}',
            originDeviceId: '${r['originDeviceId']}',
            originSequence: sequence,
            payloadHash: '${r['payloadHash']}',
            payload: MutationDeltaPayload(
              operation: '${p['operation']}',
              writes: writes,
              deletes: deletes,
              primaryTable: p['primaryTable'] as String?,
            ),
            parentMutationIds: (r['parentMutationIds'] as List? ?? [])
                .map((e) => '$e')
                .toList(),
            beforeHash: r['beforeHash'] as String?,
            afterHash: r['afterHash'] as String?,
          );
          await txn.insert(
            'mutations',
            {
              'id': m.id,
              'origin_device_id': m.originDeviceId,
              'origin_sequence': m.originSequence,
              'json': jsonEncode(m.toJson()),
              'payload_hash': m.payloadHash,
              'hash': m.hash,
              'applied_at': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        return;
      }

      final canonicalWire = brain2WireTableForLocal(wireTable);
      if (!brain2SupportsWireTable(canonicalWire)) {
        throw StateError('unsupported bootstrap table: $wireTable');
      }
      final localTable = brain2LocalTableForWire(canonicalWire);
      for (final record in records) {
        await _putRecordTxn(txn, localTable, record);
        await _upsertReaderDocTxn(txn, localTable, record);
      }
    });
  }

  Future<void> finalizeBootstrap() async {
    await setMeta('reader_index_state',
        (await total('messages')) == 0 ? 'EMPTY' : 'READY');
  }
}
