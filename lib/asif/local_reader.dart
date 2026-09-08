import 'asif_reader_core.dart';
import '../storage/brain2_database.dart';

/// Compatibility adapter. New product code should use [AsifReaderCore].
class LocalAsifReader {
  final AsifReaderCore core;
  LocalAsifReader(Brain2Database db) : core = AsifReaderCore(db);

  Future<List<Map<String, Object?>>> search(String table, String query,
      {int limit = 64}) async {
    final hits = await core.query(query, evidenceLimit: limit, tables: {table});
    return hits.map((e) => e.record).toList(growable: false);
  }
}
