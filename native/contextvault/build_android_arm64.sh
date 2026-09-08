#!/usr/bin/env bash
set -euo pipefail
: "${ANDROID_NDK:?Set ANDROID_NDK to your Android NDK directory}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${ROOT}/build-android-arm64"
cmake -S "$ROOT" -B "$BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel
printf '\nBuilt: %s\n' "$BUILD/libcontextvault.so"
