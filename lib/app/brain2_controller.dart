import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../asif/asif_reader_core.dart';
import '../contextvault/contextvault_service.dart';
import '../core/identity.dart';
import '../intelligence/mobile_intelligence_pipeline.dart';
import '../mrs/brain2_mrs_runtime.dart';
import '../mrs/llama_mobile_model_adapter.dart';
import '../mrs/mobile_model_manager.dart';
import '../services/b2m_mobile_service.dart';
import '../services/import_service.dart';
import '../storage/brain2_database.dart';
import '../storage/mutation_service.dart';
import '../sync/p2p_sync.dart';
import '../sync/qr_pairing.dart';

class Brain2Controller extends ChangeNotifier {
  Brain2Database db = Brain2Database();
  late AsifReaderCore reader;
  late MutationService mutations;
  late ContextVaultService contextVault;
  late Brain2ImportService importer;
  late MobileIntelligencePipeline intelligence;
  late B2MMobileService b2m;
  late Brain2MrsRuntime mrs;
  MobileModelManager? mobileModelManager;
  LlamaMobileModelAdapter? mobileModelAdapter;
  late Brain2MobilePairing pairing;
  Brain2P2PSync? p2p;
  StreamSubscription<MutationCommittedEvent>? _databaseMutationSubscription;
  Timer? _refreshDebounce;

  Brain2P2PStatus p2pStatus = const Brain2P2PStatus(
    Brain2P2PStage.idle,
    'Not paired',
  );

  bool loaded = false;
  String? error;
  Map<String, int> counts = {};
  String readerState = 'UNKNOWN';
  late String deviceId;

  Future<void> boot() async {
    try {
      await _databaseMutationSubscription?.cancel();
      _databaseMutationSubscription = null;
      await db.open();
      _databaseMutationSubscription = db.mutationEvents
          .where((event) => event.remote)
          .listen((_) => _scheduleRefresh());

      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString('brain2_mobile_device_id') ??
          canonicalId(
            'dev',
            ['mobile', DateTime.now().toUtc().toIso8601String()],
          );
      await prefs.setString('brain2_mobile_device_id', deviceId);

      reader = AsifReaderCore(db);
      mutations = MutationService(db, deviceId);
      contextVault = ContextVaultService();
      contextVault.initialize();
      intelligence = MobileIntelligencePipeline(db, mutations);
      importer = Brain2ImportService(
        db,
        mutations,
        contextVault: contextVault,
        intelligence: intelligence,
      );
      b2m = B2MMobileService(db);
      await mobileModelAdapter?.dispose();
      mobileModelManager ??= MobileModelManager();
      mobileModelAdapter = LlamaMobileModelAdapter(mobileModelManager!);
      mrs = Brain2MrsRuntime(
        db,
        mutations,
        model: mobileModelAdapter,
      );
      pairing = Brain2MobilePairing(
        db,
        deviceId,
        onStatus: (status) {
          if (_isStalePairingCredential(status.message)) {
            unawaited(_forgetStalePairing(status.message));
            return;
          }
          p2pStatus = status;

          // Bootstrap chunks update only sync progress. Refresh application
          // state once bootstrap moves into delta reconciliation, and debounce
          // normal remote mutation refreshes to avoid SQLite contention.
          if (status.stage == Brain2P2PStage.syncingDeltas ||
              status.stage == Brain2P2PStage.synced) {
            _scheduleRefresh();
          }

          notifyListeners();
        },
      );

      await reader.ensureReady();
      await refresh();
      loaded = true;
      error = null;

      // Pairing credentials are durable. Restore the WebRTC session after app
      // restart without blocking the rest of Brain2 from opening.
      unawaited(_restoreP2P());
    } catch (exception) {
      error = '$exception';
      loaded = false;
    }
    notifyListeners();
  }

  Future<void> _restoreP2P() async {
    try {
      p2p = await pairing.restore();
      if (p2p == null) {
        p2pStatus = const Brain2P2PStatus(
          Brain2P2PStage.idle,
          'Not paired',
        );
      }
    } catch (exception) {
      if (_isStalePairingCredential('$exception')) {
        await _forgetStalePairing('$exception');
        notifyListeners();
        return;
      }
      p2pStatus = Brain2P2PStatus(
        Brain2P2PStage.error,
        'Could not restore device sync: $exception',
      );
    }
    notifyListeners();
  }

  void _scheduleRefresh({
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(delay, () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    counts = await db.counts();
    readerState = await db.meta('reader_index_state');
    notifyListeners();
  }

  Future<void> reset() async {
    try {
      await pairing.forget();
      p2p = null;
      await db.resetLocalMemory();
      db = Brain2Database();
      await boot();
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> repairReader() async {
    await db.rebuildReaderIndex();
    await refresh();
  }

  Future<void> joinQr(String raw) async {
    p2pStatus = const Brain2P2PStatus(
      Brain2P2PStage.signaling,
      'QR detected. Validating Brain2 invitation…',
    );
    notifyListeners();
    final invite = pairing.parse(raw);
    p2p = await pairing.join(invite);
    await refresh();
    notifyListeners();
  }

  Future<void> mergeBothMemories() async {
    final sync = p2p;
    if (sync == null) {
      throw StateError('No paired Brain2 replica is connected.');
    }
    await sync.mergeBothMemories();
    await refresh();
  }

  Future<void> forgetP2P() async {
    await pairing.forget();
    p2p = null;
    p2pStatus = const Brain2P2PStatus(
      Brain2P2PStage.idle,
      'Not paired',
    );
    notifyListeners();
  }

  bool _isStalePairingCredential(String message) {
    return message.contains('Invalid Brain2 device sync credential') ||
        message.contains('Unknown or revoked Brain2 device');
  }

  Future<void> _forgetStalePairing(String reason) async {
    await pairing.forget();
    p2p = null;
    p2pStatus = Brain2P2PStatus(
      Brain2P2PStage.error,
      'Saved pairing expired or was revoked. Scan a fresh Brain2 QR. ($reason)',
    );
    notifyListeners();
  }
}
