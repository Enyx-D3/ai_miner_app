# Mobile Release Acceptance Checklist

## Architecture

- [ ] Locked architecture document matches implementation.
- [ ] Deterministic solve can finish without model.
- [ ] Compiled capability can finish without model.
- [ ] Direct Databox → model shortcut does not exist.
- [ ] Hard residual stops if model runtime is unavailable.
- [ ] Independent verification occurs after neural proposal.

## ContextVault

- [ ] Android NDK build succeeds.
- [ ] ARM64 ELF verified.
- [ ] required `cv_*` exports verified.
- [ ] `.so` copied to `jniLibs/arm64-v8a/`.
- [ ] release APK/AAB contains `.so`.
- [ ] real device reports native runtime available.
- [ ] frozen import fixture uses `nativeUsed == true`.
- [ ] web/native canonical parity test passes.

## Reader / memory

- [ ] `.ASIF Reader / RapidRetrieve` remains pure Dart.
- [ ] no `libasif_reader.so` dependency.
- [ ] V9.2 → V9.3 database migration preserves records.
- [ ] new persistent intelligence tables exist.
- [ ] `.B2M` export contains them.

## MRS

- [ ] deterministic trace test.
- [ ] capability trace test.
- [ ] hard-residual trace test.
- [ ] model adapter integration if neural reasoning is required.
- [ ] verifier rejects invented evidence IDs.
- [ ] failure trajectory persists.

## P2P

- [ ] web QR → mobile join.
- [ ] empty bootstrap.
- [ ] delta sync.
- [ ] offline/reconnect convergence.
- [ ] STUN/TURN production network test.

## Flutter / Android

- [ ] `flutter analyze` PASS.
- [ ] `flutter test` PASS.
- [ ] release APK build PASS.
- [ ] physical ARM64 device smoke PASS.
- [ ] long-duration/RAM/thermal/battery tests PASS.
