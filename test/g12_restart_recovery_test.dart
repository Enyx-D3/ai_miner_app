import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/storage/brain2_database.dart';

void main() {
  test('G12.2 SQLite quick_check accepts only explicit ok rows', () {
    expect(
      brain2SqliteQuickCheckOk([
        {'quick_check': 'ok'}
      ]),
      isTrue,
    );
    expect(
      brain2SqliteQuickCheckOk([
        {'quick_check': 'database disk image is malformed'}
      ]),
      isFalse,
    );
    expect(brain2SqliteQuickCheckOk(const []), isFalse);
  });

  test('G12.2 interrupted reader-index build becomes rebuildable', () {
    expect(brain2RestartReaderIndexState('BUILDING'), 'UNKNOWN');
    expect(brain2RestartReaderIndexState('READY'), 'READY');
    expect(brain2RestartReaderIndexState('ERROR'), 'ERROR');
    expect(brain2RestartReaderIndexState('EMPTY'), 'EMPTY');
  });
}
