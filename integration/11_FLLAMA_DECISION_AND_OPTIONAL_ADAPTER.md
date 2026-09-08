# fllama Decision and Optional Adapter Path

## Decision in V9.4.0

`fllama` is **not compiled into the release by default**.

This is deliberate, not an oversight.

The active Telosnex implementation provides a local llama.cpp Flutter API and supports Android/iOS, but its repository states that the GitHub code is GPL v2 under a dual-license model. Brain2 should not adopt that distribution obligation accidentally.

## If Brain2 approves fllama licensing

Pin a reviewed commit rather than a floating `main` dependency.

Then use the runtime only behind:

```text
lib/mrs/mobile_model_adapter.dart
```

Pseudo-integration shape:

```dart
final request = OpenAiRequest(
  modelPath: modelPath,
  contextSize: 4096,
  maxTokens: maxNewTokens,
  temperature: 0.1,
  messages: [
    Message(Role.system, systemPrompt),
    Message(Role.user, userPrompt),
  ],
);

// Wrap fllamaChat completion/streaming into a Future<String> and expose
// cancellation/timeout semantics required by MobileModelAdapter.
```

The model should be:

```text
Qwen/Qwen2.5-0.5B-Instruct-GGUF
Q4_K_M
```

## Required reliability checks before enabling

- release Android APK builds;
- ARM64 device load;
- 4096 context load;
- 20 consecutive inference runs;
- cancellation;
- app pause/resume;
- low-memory behavior;
- no main-UI-thread stall;
- model unload/reload;
- MRS evidence isolation;
- no direct Global Memory access from runtime;
- license approval recorded.
