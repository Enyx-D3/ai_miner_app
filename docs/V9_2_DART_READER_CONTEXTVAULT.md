# Brain2 AI Miner Mobile V9.2 — Pure Dart Reader + Native ContextVault

## Architecture

```text
Web V9 TypeScript Reader                 Mobile V9 Dart Reader
ASIF_READER_V9_BROWSER_CORE             ASIF_READER_V9_DART_CORE
          |                                       |
          +---- same ownership law ---------------+
                 ASIF Reader / RapidRetrieve
                         |
               selective verified evidence
                         |
                     B2DATABOX
                         |
               Global Memory / .B2M
                         |
                Global Delta / B2 Network
```

The mobile product no longer probes or depends on `libasif_reader.so`. The current V9 product Reader is implemented directly in Dart, mirroring the browser TypeScript architecture.

## ContextVault

ContextVault is the only Android native library in this package. Exact current V9 C++ source is embedded at `native/contextvault/`.

Build/install:

```bash
export ANDROID_NDK=/path/to/Android/Sdk/ndk/<version>
./scripts/build_and_install_contextvault_android.sh
```

Expected output:

```text
android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so
```

At runtime `ContextVaultService` prefers the native library and uses a deterministic Dart validation fallback when a development build does not yet contain it. Production parity testing should require the native path.

## Pairing distinction

Web generates/displays the single-use QR invitation. Mobile scans it. Mobile does not generate pairing QR codes.
