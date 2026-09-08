import '../core/contracts.dart';

/// Runtime identity for the mobile V9 Reader.
///
/// Unlike the historical CP008 file-engine ABI, the current V9 product Reader
/// is implemented directly in Dart, mirroring the browser TypeScript Reader
/// architecture. No libasif_reader.so is required.
class AsifReaderRuntime {
  const AsifReaderRuntime();

  String get coreVersion => asifReaderCoreVersion;
  String get cacheVersion => asifReaderCacheVersion;
  String get owner => 'ASIF_READER';
  String get retrievalOwner => 'RAPIDRETRIEVE';
  bool get nativeLibraryRequired => false;
  String get detail => 'Pure Dart V9 Reader/RapidRetrieve core active.';
}
