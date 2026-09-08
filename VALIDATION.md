# V9.5.3 validation

## Static bounded-memory checks

PASS:
- canonical prepared JSON is no longer loaded through `File(jsonPath).readAsBytes()`;
- canonical importer no longer calls whole-export `jsonDecode(utf8.decode(bytes))`;
- streaming parser materializes one top-level conversation object at a time;
- Mine does not invoke ContextVault a second time during canonical import;
- truth reconciliation no longer calls `db.records('truths')` for every atom;
- project snapshot generation no longer calls unfiltered `db.records('truths')` / `db.records('atoms')`;
- per-conversation intelligence no longer loads the entire messages table;
- redundant full `rebuildReaderIndex()` was removed from canonical import;
- ContextVault core source checksums are unchanged from V9.5.2.

## Runtime requirement

Flutter/Android runtime validation must still be performed on the user's Mac/emulator/device. Expected progression for a large import is now observable inside 86–94% (`Imported N conversations / M messages`) and then 96–99% (`Building Brain2 intelligence N / total`).

If the Android process is still terminated without a Dart exception, use `adb logcat` to distinguish LMKD/OOM from native SIGABRT/SIGSEGV.
