# Brain2 AI Miner Mobile V9.6.0 — Full Integrated Build

This full source tree integrates the accumulated mobile work into one project:

- multi-provider AI export import (ChatGPT, Claude, Gemini + generic adapters)
- native ContextVault C++ processing through Android FFI
- bounded-memory streaming canonical import
- conversation-sized atomic SQLite/mutation commits + WAL/NORMAL mode
- G+F+I+B250, Current Truth, Projects, Reader/RapidRetrieve, LifeWiki, Live Notebooks, MRS persistence
- `.B2M` persistence
- web↔mobile QR pairing, WebRTC bootstrap, delta sync, ACK/cursor and reconnect handling
- fixed navigation drawer context and Discover/Search state separation

Android host files are generated from the Flutter SDK installed on the build Mac/PC. Run `scripts/bootstrap_android.sh`, then build/install ContextVault before `flutter run`.

---

# Brain2 AI Miner Mobile V9.5.3 — bounded-memory canonical import

V9.5.3 fixes the Android process death/hang observed at **86% — Canonical ingestion + Global Memory** after ContextVault and `digest.zip` had already succeeded.

## Root cause fixed

The previous mobile importer did all of the following on the prepared ChatGPT history:

1. `File(jsonPath).readAsBytes()` — full JSON copy in Dart heap.
2. `utf8.decode(bytes)` — second full-size String copy.
3. `jsonDecode(...)` — a third, much larger object graph containing the complete export.
4. ran the ContextVault summary path again even though the Mine pipeline had already completed native ContextVault.
5. for every generated truth/atom, repeatedly loaded large/full JSON-backed SQLite tables into Dart.
6. rebuilt the complete Reader index even though each mutation already updates it incrementally.

On a large export this can exceed Android's process memory budget. Android may kill the process directly, which appears in Flutter as a silent console/device disconnect rather than a catchable Dart exception.

## V9.5.3 changes

- Added `lib/services/json_array_stream.dart`: streaming top-level ChatGPT JSON-array parser; only one conversation is materialized at a time.
- Canonical import no longer calls `readAsBytes()` or whole-file `jsonDecode()`.
- Mine passes the already-completed ContextVault stats/native state into canonical import; ContextVault is not run a second time.
- Canonical storage and G+F+I+B250 intelligence are now separate real progress phases.
- Mining UI reports conversation/message counts while importing instead of appearing frozen at 86%.
- Intelligence lookups use SQLite-side `json_extract(...)` filters instead of loading entire message/truth/atom tables into Dart.
- Added JSON-expression indexes for conversation/project/kind lookups when the platform SQLite supports them.
- Project snapshots refresh after conversation intelligence instead of once after every conversation.
- Removed the redundant full Reader-index rebuild at the end of import; incremental Reader writes are retained.
- ContextVault C++ source is unchanged from V9.5.2.

## Run on the existing Android project

If your local V9.5.2 already has its generated Android v2 shell and `libcontextvault.so`, copy the changed `lib/` files from this release over it, then:

```bash
flutter clean
flutter pub get
flutter run -d emulator-5554
```

There is no need to rebuild ContextVault for the V9.5.3 memory fix because the native C++ source was not changed.

## If Android still kills the process

Capture the OS-level reason in a second Terminal while reproducing:

```bash
adb logcat -c
adb logcat | grep -E "lowmemorykiller|lmkd|OutOfMemory|FATAL EXCEPTION|brain2|AndroidRuntime|libc"
```

If Android reports a native crash or OOM after V9.5.3, send that log together with the stage/percentage shown by the app.
