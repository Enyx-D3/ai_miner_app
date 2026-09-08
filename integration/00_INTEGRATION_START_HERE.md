# Brain2 AI Miner Mobile V9.3 — Integration Start Here

This folder is the authoritative integration pack for the mobile release.

## Required integration order

1. **Flutter/Android platform shell** — make sure the project has a valid Flutter-generated Android Gradle shell.
2. **ContextVault native runtime** — build `libcontextvault.so`, copy it to `android/app/src/main/jniLibs/<abi>/`, verify ABI + exported symbols, then verify it is packaged in the APK/AAB.
3. **Brain2 database migration** — V9.3 uses schema V10 with local storage migration 11 and adds MRS/persistent-intelligence tables.
4. **Locked MRS router** — already present in `lib/mrs/brain2_mrs_runtime.dart`. Neural inference is conditional, not mandatory.
5. **Mobile neural runtime (external integration)** — implement `MobileModelAdapter` only if hard-residual neural reasoning is required on-device. Without it, MRS fails closed as `BLOCKED_EXTERNAL_DEPENDENCY`.
6. **B2 Network signaling + ICE** — pairing needs the deployed web Brain2 signaling endpoints. TURN is required for restrictive NATs.
7. **.B2M persistence** — new persistent-intelligence tables are included in export/bootstrap.
8. **Release verification** — analyze, tests, native ABI, APK contents, import smoke, MRS trace, P2P convergence.

Read these files in order:

- `01_LOCKED_ARCHITECTURE.md`
- `02_CONTEXTVAULT_ANDROID_INTEGRATION.md`
- `03_CONTEXTVAULT_ABI_CONTRACT.md`
- `04_MOBILE_MRS_MODEL_RUNTIME_INTEGRATION.md`
- `05_B2_NETWORK_P2P_INTEGRATION.md`
- `06_B2M_PERSISTENCE_AND_MIGRATION.md`
- `07_ANDROID_FLUTTER_BUILD_INTEGRATION.md`
- `08_RELEASE_ACCEPTANCE_CHECKLIST.md`
- `09_EXTERNAL_DEPENDENCIES.md`

## Critical truth boundary

The current ZIP contains the native ContextVault **source**, FFI adapter, CMake build scripts and verification helpers. It does **not** claim that an Android ARM64 `.so` has already been built unless `android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so` physically exists and the ABI verification script passes.


## V9.4 web-parity integration order

Read these next:

1. `01_LOCKED_ARCHITECTURE.md`
2. `10_WEB_PARITY_STATUS_AND_WHATS_LEFT.md` — master remaining-work handoff
3. `02_CONTEXTVAULT_ANDROID_INTEGRATION.md`
4. `03_CONTEXTVAULT_ABI_CONTRACT.md`
5. `12_CONTEXTVAULT_AND_MODEL_RUNTIME_FINAL_CHECKLIST.md`
6. `04_MOBILE_MRS_MODEL_RUNTIME_INTEGRATION.md`
7. `11_FLLAMA_DECISION_AND_OPTIONAL_ADAPTER.md`
8. `05_B2_NETWORK_P2P_INTEGRATION.md`
9. `06_B2M_PERSISTENCE_AND_MIGRATION.md`
10. `07_ANDROID_FLUTTER_BUILD_INTEGRATION.md`
11. `08_RELEASE_ACCEPTANCE_CHECKLIST.md`

### Current V9.4 rule

The core data/reasoning architecture is intended to match the web app. The main planned platform difference is P2P role/UX (web invitation/QR creation vs mobile scan/join). The model family also matches web (`Qwen2.5-0.5B-Instruct`) but uses GGUF/llama.cpp on mobile rather than ONNX/Transformers.js.
