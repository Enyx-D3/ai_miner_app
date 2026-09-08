# Locked Brain2 Mobile Architecture

## Shared deterministic data pipeline

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
.ASIF Reader / RapidRetrieve  ← PURE DART ON MOBILE
  ↓
Verified Databox / B2JOB
  ↓
Brain2 Intelligence / Reasoning Router
```

## Conditional reasoning router

```text
Can deterministic logic solve the job?
  ├── YES → deterministic result → Independent Verification
  └── NO
       ↓
    compiled capability available?
       ├── YES → execute verified capability → Independent Verification
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
              MobileModelAdapter
                 ↓
              configured local/mobile model runtime
                 ↓
              Independent Verification
                 ↓
              residual-only repair if needed
```

## Verified result fan-out

```text
All verified result paths
          ↓
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

## Locked rules

- Neural inference is **conditional**.
- `Databox → model` direct is forbidden.
- Raw history is not a valid model input.
- `.ASIF Reader / RapidRetrieve` stays pure Dart on mobile. There is no `libasif_reader.so` requirement.
- ContextVault is the only required native `.so` in this mobile architecture.
- Model output is a proposal, not Current Truth.
- If the mobile neural runtime is absent, hard residuals must stop as `BLOCKED_EXTERNAL_DEPENDENCY`; do not bypass the model stage with a cloud call unless the product canon is explicitly changed.
