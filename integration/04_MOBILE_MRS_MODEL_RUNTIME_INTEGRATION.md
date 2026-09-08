# Mobile MRS Model Runtime Integration

## Locked target

Mobile uses the same model **family** and the same MRS role as web:

```text
Qwen2.5-0.5B-Instruct
```

Web artifact/runtime:

```text
Transformers.js → ONNX
```

Mobile artifact/runtime contract:

```text
llama.cpp-compatible runtime → GGUF
Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M
```

The artifact is different because ONNX is for the browser runtime and GGUF is for llama.cpp. The underlying model family remains Qwen2.5-0.5B-Instruct.

## Current mobile source boundary

```text
lib/mrs/mobile_model_adapter.dart
lib/model/mobile_qwen_spec.dart
```

The MRS router is already wired to call `MobileModelAdapter` only after:

```text
DATABOX
→ BRANCH_ZERO
→ CAPABILITY_LOOKUP
→ PATTERN_MEMORY
→ COGNITIVE_R1
→ TRACE_RPVM
→ TINY_SPECIALIST
→ HARD_RESIDUAL
→ MobileModelAdapter
→ VERIFY
```

No direct `Databox → model` path is allowed.

## fllama decision

`fllama` was **not made a mandatory production dependency** in V9.4.0.

Reason:

1. The older pub.dev `fllama` package is very old and minimally adopted.
2. The more active Telosnex `fllama` implementation is capable of Android/iOS local llama.cpp inference, but its repository states that the default GitHub code is GPL v2 / dual licensed. That can impose source-distribution obligations on a commercial integrating app unless a suitable commercial license is obtained.
3. Production Brain2 should not accidentally lock itself into a licensing obligation merely to close the runtime hook.

Therefore the adapter boundary remains production-safe and runtime-neutral.

## Recommended integration decision

Choose one llama.cpp mobile binding only after verifying:

- Android ARM64 support;
- iOS ARM64 support if iOS is in scope;
- release-mode Flutter compatibility;
- background/isolate behavior;
- token streaming;
- cancellation;
- model load/unload;
- Qwen chat-template support;
- 16 KB Android page-size compatibility where required;
- license acceptable for Brain2 distribution.

Then implement a concrete `MobileModelAdapter`.

## Required adapter

```dart
class Brain2LocalQwenAdapter implements MobileModelAdapter {
  @override String get runtimeName => 'LLAMA_CPP_<RUNTIME>';
  @override String get modelName => 'Qwen2.5-0.5B-Instruct-Q4_K_M';

  @override
  Future<bool> isAvailable() async {
    // Verify native runtime + downloaded GGUF model.
  }

  @override
  Future<String> generate({
    required String systemPrompt,
    required String userPrompt,
    int maxNewTokens = 256,
  }) async {
    // Execute local GGUF inference and return proposal text only.
  }
}
```

Then inject it in `Brain2Controller.boot()`:

```dart
mrs = Brain2MrsRuntime(
  db,
  mutations,
  model: Brain2LocalQwenAdapter(...),
);
```

## Model

Canonical mobile GGUF baseline:

```text
Repository: Qwen/Qwen2.5-0.5B-Instruct-GGUF
Quantization: Q4_K_M
Context: 4096
```

Do not bundle the ~491 MB model inside the application APK by default. Download it on first activation, store it in application support/files storage, verify size/hash if a release manifest pins one, and reuse it on subsequent runs.

## User-visible model activation behavior

Mobile should match the web UX:

```text
MODEL: CHECKING
MODEL: DOWNLOADING 0–100%
MODEL: DOWNLOADED / READY
MRS: SELF-TESTING
MRS: ACTIVE
```

If the runtime is unavailable:

```text
MODEL: RUNTIME NOT INTEGRATED
MRS: HARD RESIDUAL BLOCKED
```

Do not report `MRS ACTIVE` until a real one-token/small inference self-test succeeds.

## MRS acceptance tests

1. deterministic task → zero model calls;
2. compiled/specialist task → zero model calls;
3. hard residual → exactly one gated model call;
4. generated evidence IDs outside Databox → reject;
5. failed verification → residual-only repair;
6. model missing → `BLOCKED_EXTERNAL_DEPENDENCY`, no cloud shortcut.
