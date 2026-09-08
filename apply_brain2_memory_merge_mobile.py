#!/usr/bin/env python3
from pathlib import Path
import shutil, time, re, sys

ROOT = Path.cwd()
FILES = [
    ROOT/'lib/sync/qr_pairing.dart',
    ROOT/'lib/sync/p2p_sync.dart',
    ROOT/'lib/storage/brain2_database.dart',
    ROOT/'lib/app/brain2_controller.dart',
    ROOT/'lib/ui/screens/devices_screen.dart',
]
for f in FILES:
    if not f.exists():
        raise SystemExit(f'Missing expected Brain2 mobile file: {f}')

stamp=time.strftime('%Y%m%d_%H%M%S')
backup=ROOT/f'.brain2_memory_merge_backup_{stamp}'
backup.mkdir()
for f in FILES:
    shutil.copy2(f, backup/f.name)

def rw(path, fn):
    s=path.read_text()
    ns=fn(s)
    if ns==s:
        print(f'WARN: no change in {path.relative_to(ROOT)}')
    path.write_text(ns)

# 1) QR pairing: allow a non-empty different-root mobile to connect far enough
# to negotiate an explicit merge. Persist the local root until merge succeeds.
def patch_qr(s):
    if 'onMemoryRootChanged:' in s and 'Different Brain2 memories detected' in s:
        return s
    pat=re.compile(r"    final localMessages = await db\.total\('messages'\);\n    final localRoot = await db\.memoryRoot\(\);\n    if \(localMessages == 0\) \{\n      await db\.setMeta\('memory_root', root\);\n    \} else if \(localRoot != root\) \{.*?\n    \}\n", re.S)
    repl="""    final localMessages = await db.total('messages');
    final localRoot = await db.memoryRoot();
    if (localMessages == 0) {
      await db.setMeta('memory_root', root);
    } else if (localRoot != root) {
      _status(
        Brain2P2PStage.memoryConflict,
        'Different Brain2 memories detected. Choose Merge both memories to preserve both replicas.',
        peer: invite.inviterDeviceId,
      );
    }
"""
    s,n=pat.subn(repl,s,count=1)
    if n!=1:
        raise SystemExit('Could not locate the QR memory-root rejection block. Your qr_pairing.dart differs from the expected V9.6 structure.')
    # Store the root that is actually local now. A successful merge callback updates it later.
    s=s.replace("await prefs.setString(_rootKey, root);","await prefs.setString(_rootKey, await db.memoryRoot());",1)

    # Add callback to every Brain2P2PSync constructor if not present.
    marker='      onStatus: onStatus,\n    );'
    callback="""      onStatus: onStatus,
      onMemoryRootChanged: (newRoot) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_rootKey, newRoot);
      },
    );"""
    count=s.count(marker)
    if count:
        s=s.replace(marker,callback)
    return s
rw(FILES[0], patch_qr)

# 2) Database merge primitives.
def patch_db(s):
    if 'Future<int> applyMergeChunk(' in s:
        return s
    insert=r'''

  static const mergeSnapshotTables = <String>[
    ...syncBootstrapTables,
  ];

  Future<void> beginMemoryMerge(
    String targetRoot, {
    required List<String> parentRoots,
  }) async {
    if (targetRoot.isEmpty) throw StateError('Missing merge target root');
    final parents = parentRoots.where((e) => e.isNotEmpty).toSet().toList()
      ..sort();
    await db.transaction((txn) async {
      await txn.insert(
        'meta',
        {'key': 'memory_root', 'value': targetRoot},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'meta',
        {'key': 'origin_sequence', 'value': '0'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'meta',
        {'key': 'merge_parent_roots', 'value': jsonEncode(parents)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'meta',
        {'key': 'reader_index_state', 'value': 'READY'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Old-root mutation envelopes cannot be replayed under the target root.
      // The merged records are checkpointed again by the web peer as valid
      // target-root mutations after convergence.
      await txn.delete('mutations');
      await txn.delete('sync_cursors');

    });
  }

  String _mergeClock(Map<String, Object?> record) {
    for (final key in const [
      'updatedAt',
      'createdAt',
      'occurredAt',
      'timestamp',
      'lastSeenAt',
      'completedAt',
    ]) {
      final value = '${record[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, Object?> _mergeWinner(
    Map<String, Object?> local,
    Map<String, Object?> incoming,
  ) {
    final localJson = canonicalJson(local);
    final incomingJson = canonicalJson(incoming);
    if (localJson == incomingJson) return local;

    final localClock = _mergeClock(local);
    final incomingClock = _mergeClock(incoming);
    if (incomingClock != localClock) {
      return incomingClock.compareTo(localClock) > 0 ? incoming : local;
    }

    // Stable hash tie-break means both replicas choose the same winner even
    // when neither record has a usable timestamp.
    final localHash = sha256Hex(localJson);
    final incomingHash = sha256Hex(incomingJson);
    return incomingHash.compareTo(localHash) > 0 ? incoming : local;
  }

  Future<int> applyMergeChunk(
    String targetRoot,
    String wireTable,
    List<Map<String, Object?>> records,
  ) async {
    if (targetRoot != await memoryRoot()) {
      throw StateError('merge target memory-root mismatch');
    }

    final canonicalWire = brain2WireTableForLocal(wireTable);
    if (!brain2SupportsWireTable(canonicalWire)) {
      throw StateError('unsupported merge table: $wireTable');
    }
    final localTable = brain2LocalTableForWire(canonicalWire);
    if (!mergeSnapshotTables.contains(localTable)) {
      throw StateError('table is not mergeable: $localTable');
    }

    var changed = 0;
    await db.transaction((txn) async {
      for (final incoming in records) {
        final id = '${incoming['id'] ?? ''}';
        if (id.isEmpty) continue;
        final rows = await txn.query(
          localTable,
          columns: ['json'],
          where: 'id=?',
          whereArgs: [id],
          limit: 1,
        );
        Map<String, Object?> winner = incoming;
        if (rows.isNotEmpty) {
          final local = (jsonDecode(rows.first['json'] as String) as Map)
              .cast<String, Object?>();
          winner = _mergeWinner(local, incoming);
          if (canonicalJson(local) == canonicalJson(winner)) continue;
        }
        await _putRecordTxn(txn, localTable, winner);
        await _upsertReaderDocTxn(txn, localTable, winner);
        changed++;
      }
    });
    return changed;
  }

  Future<void> finalizeMemoryMerge() async {
    await setMeta(
      'reader_index_state',
      (await total('messages')) == 0 ? 'EMPTY' : 'READY',
    );
  }
'''
    pos=s.rfind('\n}')
    if pos<0: raise SystemExit('Could not find Brain2Database class end.')
    return s[:pos]+insert+s[pos:]
rw(FILES[2], patch_db)

# 3) P2P protocol and merge state machine.
def patch_p2p(s):
    if "case 'merge_accept':" in s:
        return s
    s=s.replace('  verifyingMemory,\n  bootstrapping,','  verifyingMemory,\n  memoryConflict,\n  bootstrapping,',1)
    if 'typedef Brain2MemoryRootChangedCallback' not in s:
        s=s.replace('typedef Brain2P2PStatusCallback = void Function(Brain2P2PStatus status);',
                    'typedef Brain2P2PStatusCallback = void Function(Brain2P2PStatus status);\ntypedef Brain2MemoryRootChangedCallback = Future<void> Function(String root);',1)
    s=s.replace('  final Brain2P2PStatusCallback? onStatus;','  final Brain2P2PStatusCallback? onStatus;\n  final Brain2MemoryRootChangedCallback? onMemoryRootChanged;',1)
    # fields
    field_anchor='  final Map<String, int> _bootstrapPeerMaxSequence = {};'
    if field_anchor in s:
        s=s.replace(field_anchor,field_anchor+'\n  final Map<String, Map<String, Object?>> _memoryConflicts = {};\n  bool _merging = false;',1)
    # constructor
    ctor='    this.iceServers = const [],\n    this.onStatus,\n  });'
    if ctor in s:
        s=s.replace(ctor,'    this.iceServers = const [],\n    this.onStatus,\n    this.onMemoryRootChanged,\n  });',1)
    elif 'this.onMemoryRootChanged' not in s:
        raise SystemExit('Could not patch Brain2P2PSync constructor.')

    connect_anchor='  Future<void> connect(String peer) async {'
    if connect_anchor not in s: raise SystemExit('Could not find Brain2P2PSync.connect().')
    merge_method=r'''  bool get hasMemoryConflict => _memoryConflicts.isNotEmpty;

  Future<void> mergeBothMemories() async {
    if (_memoryConflicts.isEmpty) {
      throw StateError('No different Brain2 memory is waiting to merge.');
    }
    final peer = _memoryConflicts.keys.first;
    final remote = _memoryConflicts[peer]!;
    // The web pairing root survives as the identity/trust namespace. Data is
    // still a true union: neither web nor mobile is treated as the data master.
    final targetRoot = '${remote['memoryRoot'] ?? ''}';
    if (targetRoot.isEmpty) throw StateError('Peer did not provide a memory root.');
    _merging = true;
    _status(
      Brain2P2PStage.bootstrapping,
      'Preparing deterministic merge. No local conversation data will be deleted…',
      peer: peer,
    );
    await _send(peer, {
      'type': 'merge_request',
      'targetRoot': targetRoot,
      'localSummary': await _summary(),
    });
  }

'''
    s=s.replace(connect_anchor,merge_method+connect_anchor,1)

    # Change hello mismatch from hard failure to explicit decision state.
    pat=re.compile(r"        final localRoot = await db\.memoryRoot\(\);\n        if \('\$\{remote\['memoryRoot'\]\}' != localRoot\) \{.*?\n        \}\n",re.S)
    repl="""        final localRoot = await db.memoryRoot();
        final remoteRoot = '${remote['memoryRoot']}';
        if (remoteRoot != localRoot) {
          _memoryConflicts[peer] = remote;
          _status(
            Brain2P2PStage.memoryConflict,
            'Different Brain2 memories detected. Merge both memories to preserve data from both replicas.',
            peer: peer,
          );
          break;
        }
        _memoryConflicts.remove(peer);
"""
    s,n=pat.subn(repl,s,count=1)
    if n!=1:
        raise SystemExit('Could not locate the mobile P2P hello memory-root guard.')

    anchor="      case 'bootstrap_request':\n"
    if anchor not in s: raise SystemExit('Could not locate bootstrap_request switch case.')
    merge_cases=r'''      case 'merge_accept':
        final targetRoot = '${message['targetRoot'] ?? ''}';
        final remote = _memoryConflicts[peer];
        if (remote == null || targetRoot != '${remote['memoryRoot']}') {
          throw StateError('Unexpected Brain2 merge target.');
        }
        final oldRoot = await db.memoryRoot();
        await db.beginMemoryMerge(
          targetRoot,
          parentRoots: [oldRoot, targetRoot],
        );
        await onMemoryRootChanged?.call(targetRoot);
        _status(
          Brain2P2PStage.bootstrapping,
          'Merge accepted. Receiving the web replica into this phone…',
          peer: peer,
        );
        await _send(peer, {'type': 'merge_ready', 'targetRoot': targetRoot});
        break;

      case 'merge_seed_chunk':
        final targetRoot = '${message['targetRoot'] ?? ''}';
        final wireTable = '${message['table'] ?? ''}';
        final recordsJson = '${message['recordsJson'] ?? ''}';
        final expected = '${message['chunkHash'] ?? ''}';
        if (sha256Hex(recordsJson) != expected) {
          throw StateError('Brain2 merge chunk hash mismatch');
        }
        final decodedRecords = jsonDecode(recordsJson);
        if (decodedRecords is! List) {
          throw StateError('Brain2 merge chunk is not a record list');
        }
        final records = decodedRecords
            .map((e) => (e as Map).cast<String, Object?>())
            .toList(growable: false);
        await db.applyMergeChunk(targetRoot, wireTable, records);
        _status(
          Brain2P2PStage.bootstrapping,
          'Merging web data · $wireTable',
          peer: peer,
        );
        break;

      case 'merge_seed_complete':
        final targetRoot = '${message['targetRoot'] ?? ''}';
        if (targetRoot != await db.memoryRoot()) {
          throw StateError('Brain2 merge root changed unexpectedly');
        }
        _status(
          Brain2P2PStage.bootstrapping,
          'Web data merged. Returning the combined replica for convergence…',
          peer: peer,
        );
        await _sendMergeReturn(peer, targetRoot);
        break;

      case 'merge_complete':
        final targetRoot = '${message['targetRoot'] ?? ''}';
        if (targetRoot != await db.memoryRoot()) {
          throw StateError('Brain2 merge completion root mismatch');
        }
        await db.finalizeMemoryMerge();
        _memoryConflicts.remove(peer);
        _merging = false;
        _status(
          Brain2P2PStage.syncingDeltas,
          'Both memories merged. Rechecking ordered deltas…',
          peer: peer,
        );
        await _hello(peer);
        break;

'''
    s=s.replace(anchor,merge_cases+anchor,1)

    send_anchor='  Future<void> _sendPending(String peer) async {'
    if send_anchor not in s: raise SystemExit('Could not locate _sendPending().')
    helper=r'''  Future<void> _sendMergeReturn(String peer, String targetRoot) async {
    var ordinal = 0;
    for (final localTable in Brain2Database.mergeSnapshotTables) {
      final wireTable = brain2WireTableForLocal(localTable);
      var offset = 0;
      while (true) {
        final page = await db.bootstrapRecordsPage(
          localTable,
          offset: offset,
          limit: 128,
        );
        if (page.isEmpty) break;
        offset += page.length;
        final recordsJson = jsonEncode(page);
        await _send(peer, {
          'type': 'merge_return_chunk',
          'targetRoot': targetRoot,
          'table': wireTable,
          'ordinal': ordinal++,
          'recordsJson': recordsJson,
          'chunkHash': sha256Hex(recordsJson),
        });
        if (page.length < 128) break;
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _send(peer, {
      'type': 'merge_return_complete',
      'targetRoot': targetRoot,
    });
  }

'''
    s=s.replace(send_anchor,helper+send_anchor,1)
    s=s.replace(send_anchor,send_anchor+'\n    if (_merging) return;',1)
    return s
rw(FILES[1], patch_p2p)

# 4) Controller exposes one explicit user action.
def patch_controller(s):
    if 'Future<void> mergeBothMemories()' in s: return s
    anchor='  Future<void> forgetP2P() async {'
    if anchor not in s: raise SystemExit('Could not locate Brain2Controller.forgetP2P().')
    method="""  Future<void> mergeBothMemories() async {
    final sync = p2p;
    if (sync == null) throw StateError('No paired Brain2 replica is connected.');
    await sync.mergeBothMemories();
    await refresh();
  }

"""
    return s.replace(anchor,method+anchor,1)
rw(FILES[3], patch_controller)

# 5) Devices UI exposes Merge both memories only when the guard fires.
def patch_devices(s):
    if "label: const Text('Merge both memories')" in s: return s
    s=s.replace(
        '        status.stage == Brain2P2PStage.webRtcConnected;',
        '        status.stage == Brain2P2PStage.webRtcConnected ||\n        status.stage == Brain2P2PStage.memoryConflict;',
        1,
    )
    anchor='                const SizedBox(height: 16),\n                if (!scanning)'
    if anchor not in s: raise SystemExit('Could not locate Devices screen action area.')
    block=r'''                const SizedBox(height: 16),
                if (status.stage == Brain2P2PStage.memoryConflict) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xff171224),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xff8f5cff)),
                    ),
                    child: const Text(
                      'Both devices contain Brain2 data. Merge preserves both datasets, deduplicates canonical IDs, and rebuilds root-bound intelligence on the shared pairing root.',
                      style: TextStyle(color: Color(0xffc7b7ef), height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await widget.c.mergeBothMemories();
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Merge failed: $error')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Merge both memories'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (!scanning)'''
    s=s.replace(anchor,block,1)
    s=s.replace(
        "      Brain2P2PStage.verifyingMemory => 'Verifying memory',",
        "      Brain2P2PStage.verifyingMemory => 'Verifying memory',\n      Brain2P2PStage.memoryConflict => 'Different memories detected',",
        1,
    )
    return s
rw(FILES[4], patch_devices)

print('PASS: Brain2 mobile Merge Both Memories V1 applied.')
print(f'Backup: {backup.name}')
print('Next: dart format lib/sync lib/storage lib/app lib/ui/screens/devices_screen.dart && flutter analyze')
