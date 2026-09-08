# ContextVault Android ARM64 source

This directory is copied from the current Brain2 AI Miner Web V9.0.2 `contextvault-core/` tree. `CMakeLists.txt` and `build_android_arm64.sh` are additive Android build files.

Expected output: `libcontextvault.so`.

Required exported browser-parity functions include:
- `cv_digest_chatgpt_json_summary_out`
- `cv_digest_chatgpt_json_to_markdown_out`
- `cv_free_browser_digest_result_ptr`

After building, copy to the Flutter app:
`android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so`
