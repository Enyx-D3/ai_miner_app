import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/sync/sync_contract.dart';

void main() {
  test('G11.8 Web merge subset contains canonical shared tables', () {
    for (final table in [
      'sources',
      'conversations',
      'messages',
      'atoms',
      'truths',
      'projects',
      'compiledCapabilities',
      'failureMemories',
    ]) {
      expect(brain2WebMergeWireTables, contains(table));
    }
  });

  test('G11.8 Web merge subset excludes Mobile-only tables', () {
    for (final table in [
      'mrsRuns',
      'intelligenceSnapshots',
      'wikiSnapshots',
      'notebookSnapshots',
    ]) {
      expect(brain2WebMergeWireTables, isNot(contains(table)));
    }
  });
}
