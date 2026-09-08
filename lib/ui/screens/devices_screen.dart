import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/brain2_controller.dart';
import '../../sync/p2p_sync.dart';
import '../widgets.dart';

bool _showsSyncProgress(Brain2P2PStage stage) {
  return stage == Brain2P2PStage.signaling ||
      stage == Brain2P2PStage.webRtcConnected ||
      stage == Brain2P2PStage.verifyingMemory ||
      stage == Brain2P2PStage.bootstrapping ||
      stage == Brain2P2PStage.syncingDeltas;
}

String _syncProgressLabel(Brain2P2PStatus status) {
  switch (status.stage) {
    case Brain2P2PStage.signaling:
      return 'Establishing secure peer session';
    case Brain2P2PStage.webRtcConnected:
      return 'Direct WebRTC channel connected';
    case Brain2P2PStage.verifyingMemory:
      return 'Verifying Brain2 memory';
    case Brain2P2PStage.bootstrapping:
      return status.processed == null
          ? 'Receiving Brain2 memory'
          : '${status.processed} bootstrap chunks processed';
    case Brain2P2PStage.syncingDeltas:
      return 'Applying and reconciling Global Delta';
    default:
      return status.message;
  }
}

class DevicesScreen extends StatefulWidget {
  final Brain2Controller c;
  const DevicesScreen(this.c, {super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool scanning = false;
  bool busy = false;
  bool handled = false;
  late final MobileScannerController scannerController;

  @override
  void initState() {
    super.initState();
    scannerController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      cameraResolution: const Size(1280, 720),
      autoZoom: true,
    );
    widget.c.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    widget.c.removeListener(_controllerChanged);
    scannerController.dispose();
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _accept(String raw) async {
    if (handled || busy) return;
    handled = true;
    setState(() {
      busy = true;
      scanning = false;
    });
    try {
      await widget.c.joinQr(raw);
    } catch (error) {
      handled = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.c.p2pStatus;
    final paired = widget.c.p2p != null ||
        status.stage == Brain2P2PStage.synced ||
        status.stage == Brain2P2PStage.syncingDeltas ||
        status.stage == Brain2P2PStage.bootstrapping ||
        status.stage == Brain2P2PStage.webRtcConnected ||
        status.stage == Brain2P2PStage.memoryConflict;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageTitle(
          'Devices & Sync',
          'Web creates a short-lived pairing QR. Mobile scans it, joins the same Brain2 memory root, bootstraps the full replica, then exchanges only ordered Global Delta mutations.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _StageDot(status.stage),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _stageTitle(status.stage),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status.message,
                  style: const TextStyle(
                    color: Color(0xff9aa8b7),
                    height: 1.4,
                  ),
                ),
                if (status.peerDeviceId != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Peer: ${status.peerDeviceId}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xff758398),
                    ),
                  ),
                ],
                if (_showsSyncProgress(status.stage)) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.sync,
                        size: 14,
                        color: Color(0xff758398),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _syncProgressLabel(status),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff758398),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
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
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => busy = true);
                            try {
                              await widget.c.mergeBothMemories();
                            } catch (error) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(content: Text('Merge failed: $error')),
                              );
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Merge both memories'),
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => busy = true);
                          try {
                            final proof = await widget.c.g11SyncProof();
                            final payload =
                                const JsonEncoder.withIndent('  ').convert(proof);
                            await Clipboard.setData(ClipboardData(text: payload));
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'G11 sync proof copied. Compare it with brain2_sync_proof on Web.',
                                ),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Could not build sync proof: $error'),
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Copy G11 sync proof'),
                ),
                if (!scanning)
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            handled = false;
                            setState(() => scanning = true);
                          },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(
                        paired ? 'Scan another Brain2 QR' : 'Scan Brain2 QR'),
                  )
                else
                  SizedBox(
                    height: 330,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: MobileScanner(
                        controller: scannerController,
                        fit: BoxFit.contain,
                        tapToFocus: true,
                        errorBuilder: (context, error) => Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'Camera scanner error: ${error.errorCode}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        onDetectError: (error, stackTrace) {
                          if (!mounted || handled) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Scanner error: $error')),
                          );
                        },
                        onDetect: (capture) {
                          final value = capture.barcodes
                              .map((barcode) => barcode.rawValue)
                              .whereType<String>()
                              .map((value) => value.trim())
                              .where((value) => value.isNotEmpty)
                              .firstOrNull;
                          if (value != null && value.trim().isNotEmpty) {
                            _accept(value);
                          }
                        },
                      ),
                    ),
                  ),
                if (scanning)
                  TextButton(
                    onPressed: () => setState(() => scanning = false),
                    child: const Text('Close scanner'),
                  ),
                if (paired) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              await widget.c.forgetP2P();
                              handled = false;
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.link_off),
                    label: const Text('Forget paired device'),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'There is intentionally no “Generate QR” button on mobile. Pairing authority begins from the existing web Brain2 replica. For local development, the QR must point to a LAN-reachable web/signaling origin rather than localhost.',
                  style: TextStyle(
                    color: Color(0xff9aa8b7),
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Golden flow',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 10),
                Text(
                  'QR detected → invitation authorized → WebRTC signaling → memory-root verified → full bootstrap if this phone is empty → delta-only sync → durable ACK/cursor → reconnect and converge.',
                  style: TextStyle(
                    color: Color(0xff9aa8b7),
                    height: 1.5,
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

class _StageDot extends StatelessWidget {
  final Brain2P2PStage stage;
  const _StageDot(this.stage);

  @override
  Widget build(BuildContext context) {
    final color = switch (stage) {
      Brain2P2PStage.error => Colors.redAccent,
      Brain2P2PStage.synced => Colors.greenAccent,
      Brain2P2PStage.disconnected => Colors.orangeAccent,
      Brain2P2PStage.idle => Colors.blueGrey,
      _ => Colors.cyanAccent,
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

String _stageTitle(Brain2P2PStage stage) => switch (stage) {
      Brain2P2PStage.idle => 'Not paired',
      Brain2P2PStage.signaling => 'Pairing / signaling',
      Brain2P2PStage.webRtcConnected => 'Direct channel connected',
      Brain2P2PStage.verifyingMemory => 'Verifying memory',
      Brain2P2PStage.memoryConflict => 'Different memories detected',
      Brain2P2PStage.bootstrapping => 'Bootstrapping Brain2',
      Brain2P2PStage.syncingDeltas => 'Synchronizing deltas',
      Brain2P2PStage.synced => 'Synced',
      Brain2P2PStage.disconnected => 'Disconnected',
      Brain2P2PStage.error => 'Sync needs attention',
    };
