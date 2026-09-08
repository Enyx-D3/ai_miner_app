import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/app/brain2_app.dart';

void main() {
  test('Brain2 root widget is available', () {
    const app = Brain2App();
    expect(app, isA<Brain2App>());
  });
}
