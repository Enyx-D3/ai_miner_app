# Brain2 AI Miner Mobile V9.5.0 — Web Parity Status and Remaining Integration

**Scope:** Mobile app compared against the current locked Brain2 web architecture.  
**Target rule:** Core memory/reasoning architecture should match web. P2P UX/transport role is platform-specific: web creates pairing invites/QR, mobile primarily scans/joins.

---

# 1. Locked shared architecture

```text
SOURCES
  ↓
Canonical Ingestion
  ↓
ContextVault
  ↓
G + F + I + B250 Atomization
  ↓
Global Memory
  ↓
Current Truth / Semantic Delta
  ↓
Project Intelligence / Resolver
  ↓
.ASIF Reader / RapidRetrieve
  ↓
Verified Databox / B2JOB
  ↓
Brain2 Intelligence / Reasoning Router
```

Then the conditional router:

```text
Can deterministic logic solve it?
  ├── YES → deterministic result → Independent Verification
  └── NO
       ↓
    compiled capability available?
       ├── YES → execute capability → Independent Verification
       └── NO
            ↓
         success + failure patterns
            ↓
         Cognitive R1
            ↓
         TRACE / RPVM
            ↓
         tiny specialist
            ↓
         unresolved hard residual?
            ├── NO → Independent Verification
            └── YES
                 ↓
              local mobile LLM adapter
                 ↓
              Qwen2.5-0.5B-Instruct GGUF
                 ↓
              Independent Verification
                 ↓
              residual-only repair
```

Verified outputs feed:

```text
Verified Intelligence
  ├── LifeWiki
  └── Live Notebooks
          ↓
Pattern Lab / Failure Memory
          ↓
Reasoning Compiler
          ↓
Capability Registry
          ↓
.B2M Persistent Intelligence
          ↓
B2 Network / P2P / Devices
```

---

# 2. What the V9.5.0 source now matches with web

| Area | Mobile V9.4.0 state |
|---|---|
| Stable identity / hashes | Implemented |
| Canonical message storage | Implemented |
| ContextVault service boundary | Implemented |
| G+F+I+B250 ownership | Implemented in Dart pipeline |
| Atom generation on import | Implemented |
| Current Truth reconciliation | Implemented baseline |
| Project resolver | Implemented baseline fingerprint resolver |
| Global Memory | SQLite implementation |
| `.ASIF Reader / RapidRetrieve` | Pure Dart implementation |
| Verified Databox | Implemented |
| Conditional MRS router | Implemented |
| Branch Zero | Implemented baseline |
| Capability lookup | Implemented |
| Success/failure memory retrieval | Implemented storage/routing baseline |
| Cognitive R1 | Implemented typed-operation baseline |
| TRACE/RPVM | Implemented transition gate baseline |
| Tiny specialist | Implemented baseline |
| Independent evidence verification | Implemented baseline |
| MRS run trajectories | Persisted |
| Failure memory | Persisted |
| Intelligence snapshots | Generated/persisted |
| LifeWiki snapshots | Generated/persisted |
| Live Notebook snapshots | Generated/persisted |
| `.B2M` persistent intelligence | Includes new intelligence tables |
| P2P bootstrap/delta | Includes new intelligence tables |
| QR pairing | Mobile join/scan path |

---

# 3. Intentional platform differences from web

## Model artifact/runtime

Same model family, different execution format:

```text
WEB
Transformers.js
→ Qwen2.5-0.5B-Instruct ONNX

MOBILE
llama.cpp-compatible runtime
→ Qwen2.5-0.5B-Instruct GGUF Q4_K_M
```

This is not an architecture difference. It is the platform runtime representation of the same hard-residual model capability.

## P2P role

```text
WEB
create invitation / QR
host signaling-facing browser peer

MOBILE
scan invitation / QR
join peer
persist offline delta locally
reconnect and converge
```

The replicated Brain2 objects and mutation protocol should remain the same.

---

# 4. What is still external / integration work

## A. ContextVault Android binary — REQUIRED

**V9.5 source status:** the no-JavaScript mobile file-path FFI wrapper is implemented and the ContextVault digest core is restored to the same source used by `/browser-digest-test`. The Android ARM64 binary still must be built with the local NDK and proven on-device.

Source is already included:

```text
native/contextvault/
```

Build/install:

```bash
export ANDROID_NDK="$ANDROID_SDK_ROOT/ndk/<version>"
bash scripts/build_and_install_contextvault_android.sh
```

Verify:

```bash
bash scripts/verify_contextvault_android.sh
```

Required binary:

```text
android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so
```

Required exports:

```text
cv_digest_chatgpt_json_summary_out
cv_digest_chatgpt_json_to_markdown_out
cv_free_browser_digest_result_ptr
cv_mobile_digest_markdown_file
cv_mobile_last_error
cv_mobile_free_string
```

Build APK:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Verify `.so` packaged inside APK:

```bash
bash scripts/verify_contextvault_in_apk.sh \
  build/app/outputs/flutter-apk/app-release.apk
```

Production acceptance requires a real-device import reporting native ContextVault use, not Dart fallback.

## B. Local mobile LLM runtime — REQUIRED for hard residual parity

The architecture hook is complete:

```text
lib/mrs/mobile_model_adapter.dart
```

The model family is frozen:

```text
Qwen2.5-0.5B-Instruct
```

Mobile GGUF baseline:

```text
Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M
```

A production llama.cpp Flutter binding still needs to be selected and licensed.

`fllama` is not enabled by default in this release because the reliable/active Telosnex implementation declares GPL v2 / dual licensing for the GitHub code. Integrate it only after deliberately accepting its license terms or obtaining an appropriate license.

After choosing the runtime:

1. add/pin dependency;
2. implement `Brain2LocalQwenAdapter`;
3. create model download/cache manager;
4. show download progress;
5. load GGUF;
6. run real inference self-test;
7. inject adapter into `Brain2MrsRuntime`;
8. prove deterministic jobs do not invoke model;
9. prove hard residual does invoke model;
10. prove generated evidence stays inside Databox.

## C. Flutter/Android build shell — REQUIRED

V9.5 includes `scripts/bootstrap_android.sh`, which replaces the partial checked-in shell with a fresh Android shell generated by the user's installed Flutter SDK while preserving Brain2 manifest/jniLibs overlays.

If `android/` is incomplete for the local Flutter version, generate the platform shell with the installed Flutter toolchain, then preserve Brain2 files:

```bash
flutter create . --platforms=android --org com.brain2 --project-name brain2_ai_miner_mobile
```

Re-apply/preserve:

```text
AndroidManifest permissions
ContextVault jniLibs
proguard/R8 rules required by chosen LLM runtime
Brain2 Dart source
```

Then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## D. Real P2P environment — REQUIRED for production sync proof

Configure:

```text
Brain2 web signaling endpoint
STUN servers
TURN if restrictive NAT support is required
```

Golden flow:

```text
web creates QR
→ mobile scans
→ memory-root check
→ bootstrap
→ same canonical objects
→ disconnect
→ web changes
→ mobile reconnects
→ deltas converge
```

Test duplicate replay, ordering, expiry, revocation, offline queue and long reconnect.

## E. Real semantic parity verification — REQUIRED

The mobile ports are source-level baselines. Run the same frozen corpus against web/mobile and compare:

```text
canonical IDs
atom boundaries
truth status
Databox evidence membership
MRS route trace
LifeWiki Current Truth
Live Notebook What Changed
.B2M restored objects
```

Differences must be classified as:

```text
EXPECTED PLATFORM DIFFERENCE
or
PARITY BUG
```

---

# 5. What does NOT need a native integration

```text
.ASIF Reader / RapidRetrieve = PURE DART
```

Do not add `libasif_reader.so`.

ContextVault is the native data-processing acceleration boundary.

---

# 6. Final integration order

```text
1. Generate/confirm Flutter Android shell
2. Build + install libcontextvault.so
3. flutter analyze/test/build
4. Real-device ContextVault import test
5. Select/license mobile llama.cpp runtime
6. Integrate Qwen2.5-0.5B-Instruct GGUF Q4_K_M
7. Add model auto-download/cache/progress/self-test
8. Run canonical MRS trace tests
9. Configure real signaling/STUN/TURN
10. Run web↔mobile P2P golden flow
11. Run web/mobile semantic parity corpus
12. Run .B2M export/import parity
13. Security + long-duration + performance tests
14. Release gate
```

---

# 7. Mobile production-complete gate

Only mark mobile complete when:

```text
LOCKED_ARCHITECTURE = PASS
CONTEXTVAULT_ARM64 = PASS
CONTEXTVAULT_REAL_DEVICE = PASS
G_F_I_B250 = PASS
CURRENT_TRUTH = PASS
READER_RAPIDRETRIEVE = PASS
DATABOX = PASS
MRS_CONDITIONAL_ROUTER = PASS
LOCAL_QWEN_RUNTIME = PASS
MRS_SELF_TEST = PASS
INDEPENDENT_VERIFIER = PASS
LIFEWIKI = PASS
LIVE_NOTEBOOKS = PASS
B2M = PASS
P2P_WEB_MOBILE_GOLDEN_FLOW = PASS
WEB_MOBILE_SEMANTIC_PARITY = PASS
FLUTTER_RELEASE_BUILD = PASS
SECURITY = PASS
PERFORMANCE = PASS
LONG_DURATION = PASS
```
