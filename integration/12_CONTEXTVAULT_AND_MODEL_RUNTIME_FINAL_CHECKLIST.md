# ContextVault + Mobile Model Runtime Final Checklist

## ContextVault

- [ ] Android NDK installed.
- [ ] `libcontextvault.so` built for ARM64.
- [ ] ELF architecture verified AArch64.
- [ ] required `cv_*` symbols exported.
- [ ] copied to `android/app/src/main/jniLibs/arm64-v8a/`.
- [ ] release APK contains the `.so`.
- [ ] Dart FFI loads library on device.
- [ ] native digest call succeeds.
- [ ] allocation is freed with `cv_free_browser_digest_result_ptr`.
- [ ] native output matches browser/WASM golden fixture.
- [ ] production import reports native ContextVault, not fallback.

## Mobile Qwen runtime

- [ ] runtime/license selected.
- [ ] dependency pinned.
- [ ] Qwen2.5-0.5B-Instruct Q4_K_M GGUF downloader implemented.
- [ ] download progress visible.
- [ ] cached model detected after restart.
- [ ] model load status visible.
- [ ] real inference self-test passes.
- [ ] `MRS ACTIVE` shown only after self-test.
- [ ] deterministic route causes zero model calls.
- [ ] hard residual causes gated model call.
- [ ] verifier rejects fabricated evidence.
- [ ] cancellation and timeout implemented.
- [ ] RAM/thermal tests pass.
