# Brain2 AI Miner Mobile V9.6.0

Integrated full source release.

## Included
- V9.5.3 bounded-memory import fixes
- multi-provider import normalization
- native ContextVault C++ Android FFI path
- per-conversation atomic import batching and SQLite WAL/NORMAL configuration
- P2P QR/WebRTC bootstrap + delta sync parity fixes
- navigation drawer Navigator-context fix
- Discover/Search keyed-state fix

## External production gates
- Android host shell must be generated with the installed Flutter SDK.
- `libcontextvault.so` must be built/packaged for the target ABI.
- production signaling/STUN/TURN must be configured for internet P2P.
- local Qwen hard-residual runtime remains a separate external runtime integration.
