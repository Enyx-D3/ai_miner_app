#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${ANDROID_NDK:-}" ]]; then
  if [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "ERROR: Set ANDROID_SDK_ROOT or ANDROID_NDK first." >&2
    exit 2
  fi
  NDK_ROOT="$ANDROID_SDK_ROOT/ndk"
  [[ -d "$NDK_ROOT" ]] || { echo "ERROR: No NDK directory at $NDK_ROOT" >&2; exit 2; }
  ANDROID_NDK="$(find "$NDK_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
  export ANDROID_NDK
fi

[[ -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]] || {
  echo "ERROR: Invalid ANDROID_NDK: $ANDROID_NDK" >&2
  exit 2
}

NATIVE="$ROOT/native/contextvault"
BUILD="$NATIVE/build-android-arm64"
DEST="$ROOT/android/app/src/main/jniLibs/arm64-v8a"

cmake -S "$NATIVE" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --config Release --parallel

mkdir -p "$DEST"
cp "$BUILD/libcontextvault.so" "$DEST/libcontextvault.so"
echo "Installed native ContextVault: $DEST/libcontextvault.so"
"$ROOT/scripts/verify_contextvault_android.sh" "$DEST/libcontextvault.so"
