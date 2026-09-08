#!/usr/bin/env python3
from pathlib import Path
import re, shutil, datetime, sys

p=Path('lib/sync/p2p_sync.dart'); contracts=Path('lib/core/contracts.dart')
if not p.exists() or not contracts.exists(): sys.exit('Run from the Brain2 mobile project root.')
stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S'); b=Path(f'.brain2_webrtc_frame_backup_{stamp}'); b.mkdir()
shutil.copy2(p,b/p.name); shutil.copy2(contracts,b/contracts.name)
s=p.read_text()

if "import 'dart:typed_data';" not in s:
    s=s.replace("import 'dart:convert';\n", "import 'dart:convert';\nimport 'dart:typed_data';\n",1)

if '_brain2TransportFramePayloadBytes' not in s:
    anchor="enum Brain2P2PStage {\n"
    block="""const int _brain2TransportFramePayloadBytes = 8 * 1024;\nconst int _brain2TransportMaxReassembledBytes = 64 * 1024 * 1024;\n\nclass _Brain2FrameAssembly {\n  final int total;\n  final List<Uint8List?> parts;\n  int received = 0;\n  int bytes = 0;\n\n  _Brain2FrameAssembly(this.total) : parts = List<Uint8List?>.filled(total, null);\n}\n\n"""
    if anchor not in s: sys.exit('enum anchor not found')
    s=s.replace(anchor,block+anchor,1)

if 'final Map<String, _Brain2FrameAssembly> _incomingFrames = {};' not in s:
    anchor='  final Map<String, int> _bootstrapPeerMaxSequence = {};\n'
    if anchor not in s: sys.exit('bootstrapPeerMaxSequence anchor not found')
    s=s.replace(anchor,anchor+'  final Map<String, _Brain2FrameAssembly> _incomingFrames = {};\n  int _frameCounter = 0;\n',1)

# Replace handle incoming method.
pat_in=re.compile(r'''  Future<void> _handleIncomingText\(String peer, String text\) async \{\n.*?\n  \}\n\n  Future<void> connect\(''', re.S)
new_in='''  Future<void> _handleIncomingText(String peer, String text) async {\n    try {\n      final decoded = jsonDecode(text);\n      if (decoded is! Map) {\n        throw const FormatException('Brain2 P2P message is not an object.');\n      }\n      final map = decoded.cast<String, Object?>();\n      if (map['__brain2Frame'] == 1) {\n        await _acceptTransportFrame(peer, map);\n        return;\n      }\n      await _message(peer, map);\n    } catch (error) {\n      _status(\n        Brain2P2PStage.error,\n        'P2P message rejected: $error',\n        peer: peer,\n      );\n    }\n  }\n\n  Future<void> _acceptTransportFrame(\n    String peer,\n    Map<String, Object?> frame,\n  ) async {\n    final id = '${frame['id'] ?? ''}';\n    final index = frame['index'] is num\n        ? (frame['index'] as num).toInt()\n        : int.tryParse('${frame['index']}') ?? -1;\n    final total = frame['total'] is num\n        ? (frame['total'] as num).toInt()\n        : int.tryParse('${frame['total']}') ?? -1;\n    if (id.isEmpty || total < 1 || total > 16384 || index < 0 || index >= total) {\n      throw StateError('Invalid Brain2 transport frame');\n    }\n    final key = '$peer::$id';\n    final assembly = _incomingFrames.putIfAbsent(\n      key,\n      () => _Brain2FrameAssembly(total),\n    );\n    if (assembly.total != total) {\n      _incomingFrames.remove(key);\n      throw StateError('Brain2 transport frame total changed');\n    }\n    if (assembly.parts[index] != null) return;\n\n    final bytes = base64Decode('${frame['data'] ?? ''}');\n    assembly.parts[index] = bytes;\n    assembly.received += 1;\n    assembly.bytes += bytes.length;\n    if (assembly.bytes > _brain2TransportMaxReassembledBytes) {\n      _incomingFrames.remove(key);\n      throw StateError('Brain2 transport message exceeded reassembly limit');\n    }\n    if (assembly.received != assembly.total) return;\n\n    final builder = BytesBuilder(copy: false);\n    for (final part in assembly.parts) {\n      if (part == null) {\n        _incomingFrames.remove(key);\n        throw StateError('Brain2 transport frame missing during reassembly');\n      }\n      builder.add(part);\n    }\n    _incomingFrames.remove(key);\n    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));\n    if (decoded is! Map) {\n      throw const FormatException('Reassembled Brain2 message is not an object.');\n    }\n    await _message(peer, decoded.cast<String, Object?>());\n  }\n\n  Future<void> connect('''
if '_acceptTransportFrame(' not in s:
    s2,n=pat_in.subn(new_in,s,count=1)
    if n!=1: sys.exit('_handleIncomingText block not found')
    s=s2

# Replace send method until summary.
pat_send=re.compile(r'''  Future<void> _send\(String peer, Map<String, Object\?> message\) async \{\n.*?\n  \}\n\n  Future<Map<String, Object\?>> _summary\(\)''', re.S)
new_send='''  Future<void> _sendPhysicalText(String peer, String text) async {\n    final channel = _channels[peer];\n    if (channel == null ||\n        channel.state != RTCDataChannelState.RTCDataChannelOpen) {\n      throw StateError('Brain2 P2P channel not open');\n    }\n    while ((await channel.getBufferedAmount()) > 512 * 1024) {\n      await Future<void>.delayed(const Duration(milliseconds: 20));\n      if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {\n        throw StateError('Brain2 P2P channel closed while draining');\n      }\n    }\n    await channel.send(RTCDataChannelMessage(text));\n  }\n\n  Future<void> _send(String peer, Map<String, Object?> message) async {\n    final raw = jsonEncode(message);\n    final bytes = Uint8List.fromList(utf8.encode(raw));\n    if (bytes.length <= _brain2TransportFramePayloadBytes) {\n      await _sendPhysicalText(peer, raw);\n      return;\n    }\n\n    final id = '$deviceId-${DateTime.now().microsecondsSinceEpoch}-${_frameCounter++}';\n    final total =\n        (bytes.length + _brain2TransportFramePayloadBytes - 1) ~/\n            _brain2TransportFramePayloadBytes;\n    for (var index = 0; index < total; index++) {\n      final start = index * _brain2TransportFramePayloadBytes;\n      final end = (start + _brain2TransportFramePayloadBytes < bytes.length)\n          ? start + _brain2TransportFramePayloadBytes\n          : bytes.length;\n      final frame = <String, Object?>{\n        '__brain2Frame': 1,\n        'id': id,\n        'index': index,\n        'total': total,\n        'data': base64Encode(Uint8List.sublistView(bytes, start, end)),\n      };\n      await _sendPhysicalText(peer, jsonEncode(frame));\n    }\n  }\n\n  Future<Map<String, Object?>> _summary()'''
if '_sendPhysicalText(' not in s:
    s2,n=pat_send.subn(new_send,s,count=1)
    if n!=1: sys.exit('_send block not found')
    s=s2

p.write_text(s)
cs=contracts.read_text().replace('const int brain2SyncBatchLimit = 128;', 'const int brain2SyncBatchLimit = 32;').replace('const int brain2SyncBootstrapChunkBytes = 48 * 1024;', 'const int brain2SyncBootstrapChunkBytes = 32 * 1024;')
contracts.write_text(cs)
print('PASS: Brain2 mobile RTCDataChannel byte framing applied.')
print('Backup:', b)
print('Touched: lib/sync/p2p_sync.dart, lib/core/contracts.dart')
