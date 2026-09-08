#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from datetime import datetime
import re
import shutil
import sys

ROOT = Path.cwd()
P2P = ROOT / "lib/sync/p2p_sync.dart"
CTRL = ROOT / "lib/app/brain2_controller.dart"

TARGET_METHODS = {
    'start': "Future<void> start() async {\n    if (_disposed) throw StateError('Brain2 P2P sync has been disposed.');\n    _signalPoll ??= Timer.periodic(\n      const Duration(seconds: 2),\n      (_) => unawaited(_consumeSignalsSafe()),\n    );\n    _mutationSubscription ??= db.mutationEvents\n        .where(\n          (e) =>\n              !e.remote && e.mutation.originDeviceId == deviceId,\n        )\n        .listen((_) {\n      for (final peer in _channels.keys) {\n        unawaited(_hello(peer));\n      }\n    });\n    _reconcileTimer ??= Timer.periodic(\n      const Duration(seconds: 5),\n      (_) {\n        for (final peer in _channels.keys) {\n          unawaited(_hello(peer));\n        }\n      },\n    );\n    await _consumeSignalsSafe();\n  }",
    'dispose': 'Future<void> dispose() async {\n    _disposed = true;\n    _signalPoll?.cancel();\n    _signalPoll = null;\n    _reconcileTimer?.cancel();\n    _reconcileTimer = null;\n    await _mutationSubscription?.cancel();\n    _mutationSubscription = null;\n    for (final c in _channels.values) {\n      await c.close();\n    }\n    for (final p in _pcs.values) {\n      await p.close();\n    }\n    _channels.clear();\n    _pcs.clear();\n    _pendingIce.clear();\n    _remoteDescriptionReady.clear();\n    api.close();\n  }',
    'message': "Future<void> _message(String peer, Map<String, Object?> message) async {\n    switch ('${message['type']}') {\n      case 'hello':\n        final remote = (message['summary'] as Map).cast<String, Object?>();\n        final localRoot = await db.memoryRoot();\n        if ('${remote['memoryRoot']}' != localRoot) {\n          throw StateError('P2P peer memory-root mismatch');\n        }\n        final localMessages = await db.total('messages');\n        final remoteMessages = remote['totalMessages'] is num\n            ? (remote['totalMessages'] as num).toInt()\n            : int.tryParse('${remote['totalMessages']}') ?? 0;\n        final remoteLatest = remote['latestLocalSequence'] is num\n            ? (remote['latestLocalSequence'] as num).toInt()\n            : int.tryParse('${remote['latestLocalSequence']}') ?? 0;\n        _remoteMessageCount[peer] = remoteMessages;\n        _remoteAtomCount[peer] = remote['totalAtoms'] is num\n            ? (remote['totalAtoms'] as num).toInt()\n            : int.tryParse('${remote['totalAtoms']}') ?? 0;\n        _remoteTruthCount[peer] = remote['totalTruths'] is num\n            ? (remote['totalTruths'] as num).toInt()\n            : int.tryParse('${remote['totalTruths']}') ?? 0;\n        _remoteLatestSequence[peer] = remoteLatest;\n        final inboundApplied = await db.peerCursor(peer, peer);\n        if (localMessages == 0 && remoteMessages > 0) {\n          _status(\n            Brain2P2PStage.bootstrapping,\n            'Memory verified. Requesting initial bootstrap…',\n            peer: peer,\n          );\n          await _send(peer, {'type': 'bootstrap_request'});\n        } else if (remoteMessages == 0 && localMessages > 0) {\n          // The empty peer will request the bootstrap. Waiting avoids sending\n          // the complete mutation history at the same time as the snapshot.\n          _status(\n            Brain2P2PStage.bootstrapping,\n            'Memory verified. Waiting for peer bootstrap request…',\n            peer: peer,\n          );\n        } else {\n          _status(\n            Brain2P2PStage.syncingDeltas,\n            'Memory verified. Synchronizing missing deltas…',\n            peer: peer,\n          );\n          if (remoteLatest > inboundApplied) {\n            await _send(peer, {\n              'type': 'sync_request',\n              'fromSequence': inboundApplied + 1,\n            });\n          }\n          _scheduleFlush(peer, immediate: true);\n        }\n        break;\n\n      case 'sync_request':\n        _scheduleFlush(peer, immediate: true);\n        break;\n\n      case 'bootstrap_request':\n        _status(\n          Brain2P2PStage.bootstrapping,\n          'Sending initial Brain2 bootstrap…',\n          peer: peer,\n        );\n        await _sendBootstrap(peer);\n        break;\n\n      case 'bootstrap_chunk':\n        final memoryRoot = '${message['memoryRoot']}';\n        final wireTable = '${message['table']}';\n        final ordinal = message['ordinal'] is num\n            ? (message['ordinal'] as num).toInt()\n            : int.parse('${message['ordinal']}');\n        final records = (message['records'] as List)\n            .map((e) => (e as Map).cast<String, Object?>())\n            .toList(growable: false);\n        final expected = '${message['chunkHash']}';\n        final actual = sha256Hex(\n          canonicalJson({\n            'memoryRoot': memoryRoot,\n            'table': wireTable,\n            'ordinal': ordinal,\n            'records': records,\n          }),\n        );\n        if (actual != expected) {\n          throw StateError('Brain2 bootstrap chunk hash mismatch');\n        }\n        if (wireTable == 'mutations') {\n          var maxSequence = _bootstrapPeerMaxSequence[peer] ?? 0;\n          for (final record in records) {\n            final origin = '${record['originDeviceId'] ?? record['deviceId'] ?? ''}';\n            if (origin != peer) continue;\n            final raw = record['originSequence'] ?? record['sequence'];\n            final sequence = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;\n            if (sequence > maxSequence) maxSequence = sequence;\n          }\n          _bootstrapPeerMaxSequence[peer] = maxSequence;\n        }\n        await db.applyBootstrapChunk(memoryRoot, wireTable, records);\n        _status(\n          Brain2P2PStage.bootstrapping,\n          'Receiving Brain2 bootstrap · $wireTable',\n          peer: peer,\n          processed: ordinal + 1,\n        );\n        break;\n\n      case 'bootstrap_complete':\n        if ('${message['memoryRoot']}' != await db.memoryRoot()) {\n          throw StateError('bootstrap memory-root mismatch');\n        }\n        await db.finalizeBootstrap();\n        final bootstrappedPeerSequence = _bootstrapPeerMaxSequence.remove(peer) ?? 0;\n        if (bootstrappedPeerSequence > 0) {\n          await db.setPeerCursor(peer, peer, bootstrappedPeerSequence);\n          await _send(peer, {\n            'type': 'ack',\n            'originDeviceId': peer,\n            'sequence': bootstrappedPeerSequence,\n          });\n        }\n        _status(\n          Brain2P2PStage.syncingDeltas,\n          'Bootstrap complete. Checking for newer deltas…',\n          peer: peer,\n        );\n        await _hello(peer);\n        break;\n\n      case 'mutations':\n        final list = (message['mutations'] as List)\n            .map(\n              (e) => _mutationFromJson(\n                (e as Map).cast<String, Object?>(),\n              ),\n            )\n            .toList()\n          ..sort((a, b) => a.originSequence.compareTo(b.originSequence));\n        final manifestHash = sha256Hex(\n          list\n              .map(\n                (x) => '${x.originSequence}:${x.id}:${x.payloadHash}',\n              )\n              .join('|'),\n        );\n        if (manifestHash != '${message['manifestHash']}') {\n          throw StateError('mutation batch manifest mismatch');\n        }\n\n        var lastApplied = await db.peerCursor(peer, peer);\n        for (final mutation in list) {\n          if (mutation.originDeviceId != peer) {\n            throw StateError('mutation origin device mismatch');\n          }\n          if (lastApplied > 0 &&\n              mutation.originSequence > lastApplied + 1) {\n            throw StateError(\n              'mutation gap: expected ${lastApplied + 1}, '\n              'got ${mutation.originSequence}',\n            );\n          }\n          await db.applyMutation(mutation);\n          if (mutation.originSequence > lastApplied) {\n            lastApplied = mutation.originSequence;\n          }\n        }\n        await db.setPeerCursor(peer, peer, lastApplied);\n        await _send(peer, {\n          'type': 'ack',\n          'originDeviceId': peer,\n          'sequence': lastApplied,\n          'manifestHash': manifestHash,\n        });\n        await _markConvergedIfPossible(peer);\n        break;\n\n      case 'ack':\n        final origin = '${message['originDeviceId'] ?? deviceId}';\n        final sequence = message['sequence'] is num\n            ? (message['sequence'] as num).toInt()\n            : int.tryParse('${message['sequence']}') ?? 0;\n        await db.setPeerCursor(peer, origin, sequence);\n        _awaitingAck.remove(peer);\n        _scheduleFlush(peer);\n        await _markConvergedIfPossible(peer);\n        break;\n\n      case 'ping':\n        break;\n    }\n  }",
    'sendPending': "Future<void> _sendPending(String peer) async {\n    final cursor = await db.peerCursor(peer, deviceId);\n    final mutations = await db.pendingLocalAfter(\n      deviceId,\n      cursor,\n      limit: brain2SyncBatchLimit,\n    );\n    if (mutations.isEmpty) {\n      await _markConvergedIfPossible(peer);\n      return;\n    }\n\n    final manifestHash = sha256Hex(\n      mutations\n          .map(\n            (x) => '${x.originSequence}:${x.id}:${x.payloadHash}',\n          )\n          .join('|'),\n    );\n    _awaitingAck.add(peer);\n    try {\n      await _send(peer, {\n        'type': 'mutations',\n        'mutations': mutations.map((e) => e.toJson()).toList(),\n        'manifestHash': manifestHash,\n        'originDeviceId': deviceId,\n        'fromSequence': mutations.first.originSequence,\n        'toSequence': mutations.last.originSequence,\n      });\n      _status(\n        Brain2P2PStage.syncingDeltas,\n        'Sent deltas ${mutations.first.originSequence}–'\n        '${mutations.last.originSequence}; waiting for ACK…',\n        peer: peer,\n      );\n    } catch (_) {\n      _awaitingAck.remove(peer);\n      rethrow;\n    }\n  }",
    'mark': "Future<void> _markConvergedIfPossible(String peer) async {\n    final localLatest = int.tryParse(await db.meta('origin_sequence')) ?? 0;\n    final outboundAcked = await db.peerCursor(peer, deviceId);\n    final inboundApplied = await db.peerCursor(peer, peer);\n    final remoteLatest = _remoteLatestSequence[peer] ?? 0;\n    final remoteMessages = _remoteMessageCount[peer] ?? 0;\n    final remoteAtoms = _remoteAtomCount[peer] ?? 0;\n    final remoteTruths = _remoteTruthCount[peer] ?? 0;\n    final localMessages = await db.total('messages');\n    final localAtoms = await db.total('atoms');\n    final localTruths = await db.total('truths');\n    final inboundOk = inboundApplied >= remoteLatest;\n    final outboundOk = outboundAcked >= localLatest;\n    final countsMatch =\n        localMessages == remoteMessages &&\n        localAtoms == remoteAtoms &&\n        localTruths == remoteTruths;\n\n    if (inboundOk && outboundOk && countsMatch) {\n      _status(\n        Brain2P2PStage.synced,\n        'Brain2 replicas are synchronized · local $localMessages messages · peer $remoteMessages messages.',\n        peer: peer,\n      );\n    } else {\n      _status(\n        Brain2P2PStage.syncingDeltas,\n        'Connected · waiting for missing Brain2 deltas…',\n        peer: peer,\n      );\n    }\n  }"
}

METHOD_PATTERNS = {
    "start": r"Future<void>\s+start\(\)\s+async\s*\{",
    "dispose": r"Future<void>\s+dispose\(\)\s+async\s*\{",
    "message": r"Future<void>\s+_message\(String peer, Map<String, Object\?> message\)\s+async\s*\{",
    "sendPending": r"Future<void>\s+_sendPending\(String peer\)\s+async\s*\{",
    "mark": r"Future<void>\s+_markConvergedIfPossible\(String peer\)\s+async\s*\{",
}


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(2)


def find_balanced_method(text: str, pattern: str) -> tuple[int, int]:
    m = re.search(pattern, text)
    if not m:
        fail(f"Could not find method matching: {pattern}")
    start = m.start()
    brace = text.find("{", m.start())
    if brace < 0:
        fail("Method opening brace not found")

    depth = 0
    i = brace
    quote = None
    escaped = False
    line_comment = False
    block_comment = False

    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if c == "\n":
                line_comment = False
        elif block_comment:
            if c == "*" and n == "/":
                block_comment = False
                i += 1
        elif quote is not None:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
        else:
            if c == "/" and n == "/":
                line_comment = True
                i += 1
            elif c == "/" and n == "*":
                block_comment = True
                i += 1
            elif c in ("'", '"'):
                quote = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return start, i + 1
        i += 1

    fail("Unclosed method block")


def replace_method(text: str, key: str) -> str:
    start, end = find_balanced_method(text, METHOD_PATTERNS[key])
    return text[:start] + TARGET_METHODS[key] + text[end:]


def insert_fields(text: str) -> str:
    if "_remoteLatestSequence" not in text:
        anchor = "  final Map<String, int> _bootstrapPeerMaxSequence = {};"
        if anchor not in text:
            fail("P2P field anchor _bootstrapPeerMaxSequence not found")
        extra = """
  final Map<String, int> _remoteLatestSequence = {};
  final Map<String, int> _remoteMessageCount = {};
  final Map<String, int> _remoteAtomCount = {};
  final Map<String, int> _remoteTruthCount = {};"""
        text = text.replace(anchor, anchor + extra, 1)

    if "Timer? _reconcileTimer;" not in text:
        anchor = "  Timer? _signalPoll;"
        if anchor not in text:
            fail("P2P timer anchor _signalPoll not found")
        text = text.replace(anchor, anchor + "\n  Timer? _reconcileTimer;", 1)
    return text


def ensure_mark_method(text: str) -> str:
    if re.search(METHOD_PATTERNS["mark"], text):
        return replace_method(text, "mark")
    m = re.search(METHOD_PATTERNS["sendPending"], text)
    if not m:
        fail("_sendPending method not found; cannot insert convergence method")
    return text[:m.start()] + TARGET_METHODS["mark"] + "\n\n  " + text[m.start():]


def patch_controller(text: str) -> str:
    # Idempotent.
    if "status.stage == Brain2P2PStage.synced" in text and "unawaited(refresh())" in text:
        return text

    # Target the pairing callback, not arbitrary notifyListeners() calls.
    anchor = """        onStatus: (status) {
          p2pStatus = status;
          notifyListeners();
        },"""
    replacement = """        onStatus: (status) {
          p2pStatus = status;
          if (status.stage == Brain2P2PStage.synced) {
            unawaited(refresh());
          }
          notifyListeners();
        },"""
    if anchor in text:
        return text.replace(anchor, replacement, 1)

    # Tolerate dart-format/manual whitespace changes.
    pattern = re.compile(
        r"(onStatus:\s*\(status\)\s*\{\s*"
        r"p2pStatus\s*=\s*status;)(\s*)"
        r"notifyListeners\(\);",
        re.S,
    )
    m = pattern.search(text)
    if not m:
        fail("Could not locate Brain2 pairing onStatus callback in brain2_controller.dart")
    insert = (
        m.group(1)
        + "\n          if (status.stage == Brain2P2PStage.synced) {\n"
        + "            unawaited(refresh());\n"
        + "          }"
        + m.group(2)
        + "notifyListeners();"
    )
    return text[:m.start()] + insert + text[m.end():]


def validate(p2p: str, ctrl: str) -> None:
    required = [
        "Timer? _reconcileTimer;",
        "_remoteLatestSequence",
        "Duration(seconds: 5)",
        "case 'sync_request':",
        "_markConvergedIfPossible",
        "Connected · waiting for missing Brain2 deltas…",
    ]
    missing = [x for x in required if x not in p2p]
    if missing:
        fail("Continuous-sync markers missing after patch: " + ", ".join(missing))
    if "status.stage == Brain2P2PStage.synced" not in ctrl or "unawaited(refresh())" not in ctrl:
        fail("Controller refresh-on-convergence marker missing")


def main() -> None:
    if not P2P.exists() or not CTRL.exists():
        fail("Run this script from the Brain2 AI Miner Mobile V9.6 project root")

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = ROOT / f".brain2_contsync_backup_{stamp}"
    backup.mkdir(parents=True, exist_ok=False)
    shutil.copy2(P2P, backup / "p2p_sync.dart")
    shutil.copy2(CTRL, backup / "brain2_controller.dart")

    p2p = P2P.read_text()
    ctrl = CTRL.read_text()

    p2p = insert_fields(p2p)
    for key in ("start", "dispose", "message"):
        p2p = replace_method(p2p, key)
    p2p = ensure_mark_method(p2p)
    p2p = replace_method(p2p, "sendPending")
    ctrl = patch_controller(ctrl)

    validate(p2p, ctrl)
    P2P.write_text(p2p)
    CTRL.write_text(ctrl)

    print("PASS: Brain2 continuous convergence semantic patch applied.")
    print(f"Backup: {backup}")
    print("Touched only:")
    print("  lib/sync/p2p_sync.dart")
    print("  lib/app/brain2_controller.dart")
    print("Next:")
    print("  dart format lib/sync/p2p_sync.dart lib/app/brain2_controller.dart")
    print("  flutter analyze")
    print("  flutter run -d M2101K6P")


if __name__ == "__main__":
    main()
