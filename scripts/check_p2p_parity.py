from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text()
contract=read('lib/sync/sync_contract.dart')
p2p=read('lib/sync/p2p_sync.dart')
qr=read('lib/sync/qr_pairing.dart')
db=read('lib/storage/brain2_database.dart')
controller=read('lib/app/brain2_controller.dart')
ui=read('lib/ui/screens/devices_screen.dart')
checks={
 'wire aliases': all(x in contract for x in ["'capabilities': 'compiledCapabilities'","'failureMemory': 'failureMemories'",'mrsRuns','intelligenceSnapshots','wikiSnapshots','notebookSnapshots']),
 'qr protocol/signaling': all(x in qr for x in ["queryParameters['v']","queryParameters['signal']",'syncProtocolVersion','Future<Brain2P2PSync?> restore()']),
 'ice queue': all(x in p2p for x in ['_pendingIce','_remoteDescriptionReady','_setRemoteDescription','_addIce']),
 'bootstrap/delta': all(x in p2p for x in ['bootstrap_request','bootstrap_chunk','bootstrap_complete','manifestHash','originDeviceId','getBufferedAmount']),
 'bounded bootstrap': 'bootstrapRecordsPage' in db and 'limit: 256' in p2p,
 'idempotent mutation': "if (duplicate.isNotEmpty) return false;" in db,
 'session restore': '_restoreP2P' in controller and 'pairing.restore()' in controller,
 'diagnostic UI': all(x in ui for x in ['QR detected','Golden flow','Scan Brain2 QR']),
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL: '+', '.join(failed))
print('PASS: mobile QR/signaling/WebRTC/bootstrap/delta parity invariants are present.')
