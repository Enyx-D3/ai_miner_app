# External Dependencies Still Required for Full Mobile Acceptance

## Mandatory for native ContextVault production acceptance

- Android SDK/NDK/CMake toolchain.
- Real ARM64 build of `libcontextvault.so`.
- Physical Android ARM64 device or appropriate device farm.

## Required only for neural hard-residual MRS

- A selected mobile neural runtime/model implementing `MobileModelAdapter`.

The locked router is already present; the model runtime is intentionally pluggable.

## Required for production P2P across arbitrary networks

- deployed Brain2 signaling endpoints;
- STUN configuration;
- TURN service/ephemeral credentials if restrictive NAT support is required.

## Required for final release proof

- Flutter/Android build environment;
- real-device E2E;
- long-duration, RAM, thermal, battery and network tests.
