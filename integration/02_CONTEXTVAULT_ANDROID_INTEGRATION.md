# ContextVault Android Integration — Complete Procedure

## 1. What ContextVault is in this package

The mobile application contains:

```text
native/contextvault/                 C++ source
native/contextvault/CMakeLists.txt   native build definition
native/contextvault/build_android_arm64.sh
lib/contextvault/contextvault_native.dart
lib/contextvault/contextvault_service.dart
android/app/src/main/jniLibs/arm64-v8a/
```

The production Android path is:

```text
ChatGPT/export bytes
   ↓
ContextVaultService
   ↓
ContextVaultNative (dart:ffi)
   ↓
libcontextvault.so
   ↓
ContextVault C++ digest core
```

The Dart fallback exists for development/validation, but a production acceptance build must prove `nativeUsed == true` for the native import path.

## 2. Toolchain prerequisites

Install:

- Flutter SDK compatible with Dart >= 3.4
- Android SDK
- Android NDK with CMake toolchain support
- CMake >= 3.22
- Ninja (recommended)
- JDK required by the installed Flutter/Android Gradle toolchain

Confirm:

```bash
flutter doctor -v
cmake --version
```

Set NDK path on macOS/Linux:

```bash
export ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/<installed-version>"
```

or on Windows PowerShell:

```powershell
$env:ANDROID_NDK = "$env:LOCALAPPDATA\Android\Sdk\ndk\<installed-version>"
```

## 3. Build ARM64 ContextVault

From the project root:

```bash
bash scripts/build_and_install_contextvault_android.sh
```

That must:

1. configure CMake with Android NDK;
2. build for `arm64-v8a`;
3. produce `libcontextvault.so`;
4. copy it to:

```text
android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so
```

Manual equivalent:

```bash
cd native/contextvault
./build_android_arm64.sh
cp build-android-arm64/libcontextvault.so \
  ../../android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so
```

## 4. Verify the binary before building Flutter

Run:

```bash
bash scripts/verify_contextvault_android.sh
```

Required results:

- file exists;
- ELF shared object;
- AArch64 / ARM64;
- exported ABI symbols found:
  - `cv_digest_chatgpt_json_summary_out`
  - `cv_digest_chatgpt_json_to_markdown_out`
  - `cv_free_browser_digest_result_ptr`

Do not continue to production acceptance if any of these are missing.

## 5. Build Flutter APK

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## 6. Verify the APK actually contains ContextVault

Run:

```bash
bash scripts/verify_contextvault_in_apk.sh build/app/outputs/flutter-apk/app-release.apk
```

Required APK member:

```text
lib/arm64-v8a/libcontextvault.so
```

A successful CMake build alone is insufficient; the library must be inside the distributable APK/AAB.

## 7. Runtime smoke test

Install the release APK on an ARM64 Android device and import a known ChatGPT JSON export.

The runtime must satisfy:

```text
ContextVaultService.nativeAvailable == true
ContextVaultDigest.nativeUsed == true
```

Then compare the produced canonical summary/counts against the same fixed fixture used by the web/WASM ContextVault path.

## 8. Web/native parity gate

For one frozen export fixture, compare at minimum:

- conversation count;
- message count;
- canonical source identity inputs;
- any digest/normalized fields consumed by ingestion;
- error/fail-closed behavior for malformed input.

The goal is semantic/canonical parity, not byte-for-byte equality of irrelevant metadata.

## 9. Emulator support

The shipped native build script targets ARM64. If an x86_64 emulator must exercise native ContextVault, build a second ABI and place it at:

```text
android/app/src/main/jniLibs/x86_64/libcontextvault.so
```

Do not ship an x86_64-only build as evidence for ARM64 phone acceptance.

## 10. Common failures

### `DynamicLibrary.open('libcontextvault.so')` fails

Check APK contents and ABI match. A library built for the host machine is not an Android library.

### symbol lookup fails

Run the ABI verifier. The C++ wrapper must export the exact C ABI symbol names without C++ mangling.

### native loads but digest crashes

Confirm FFI struct layout and ownership contract in `03_CONTEXTVAULT_ABI_CONTRACT.md`, then test the frozen fixture.

### app silently uses Dart fallback

This is acceptable only for development. Production acceptance must surface `nativeAvailable` and prove `nativeUsed == true` on the native test fixture.
