$ErrorActionPreference = "Stop"
if (-not $env:ANDROID_NDK) { throw "Set ANDROID_NDK to your Android NDK directory" }
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Native = Join-Path $Root "native/contextvault"
$Build = Join-Path $Native "build-android-arm64"
$Toolchain = Join-Path $env:ANDROID_NDK "build/cmake/android.toolchain.cmake"
cmake -S $Native -B $Build `
  -DCMAKE_TOOLCHAIN_FILE=$Toolchain `
  -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release
cmake --build $Build --config Release --parallel
$Source = Join-Path $Build "libcontextvault.so"
$DestDir = Join-Path $Root "android/app/src/main/jniLibs/arm64-v8a"
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
Copy-Item -Force $Source (Join-Path $DestDir "libcontextvault.so")
Write-Host "Installed libcontextvault.so into $DestDir"
