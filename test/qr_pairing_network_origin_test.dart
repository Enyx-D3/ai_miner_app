import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/storage/brain2_database.dart';
import 'package:brain2_ai_miner_mobile/sync/qr_pairing.dart';

void main() {
  final pairing = Brain2MobilePairing(Brain2Database(), 'dev_mobile_test');

  test('physical-device pairing accepts LAN signaling origin', () {
    final invite = pairing.parse(
      'http://192.168.1.20:3000/devices'
      '?pair=token123&peer=dev_web&v=2'
      '&signal=http%3A%2F%2F192.168.1.20%3A3000',
    );
    expect(invite.signalingOrigin, 'http://192.168.1.20:3000');
    expect(invite.protocolVersion, 2);
  });

  test('physical-device pairing rejects localhost QR', () {
    expect(
      () => pairing.parse(
        'http://localhost:3000/devices?pair=token123&peer=dev_web&v=2',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('physical-device pairing rejects explicit loopback signal origin', () {
    expect(
      () => pairing.parse(
        'http://192.168.1.20:3000/devices'
        '?pair=token123&peer=dev_web&v=2'
        '&signal=http%3A%2F%2F127.0.0.1%3A3000',
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('G11 sync proof JSON is rejected with pairing-link guidance', () {
    expect(
      () => pairing.parse(
        '{"format":"B2_G11_SYNC_PROOF","version":1,"surface":"MOBILE"}',
      ),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains('Copy link'),
      )),
    );
  });

}
