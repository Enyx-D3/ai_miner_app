# ContextVault Native ABI Contract

Dart FFI loads:

```text
libcontextvault.so
```

Required exports:

```c
cv_digest_chatgpt_json_summary_out
cv_digest_chatgpt_json_to_markdown_out
cv_free_browser_digest_result_ptr
```

The Dart result structure is:

```text
json pointer
json byte length
error pointer
error byte length
```

Ownership rule:

1. Dart allocates the outer result struct.
2. ContextVault may allocate result buffers referenced by the struct.
3. Dart reads/copies those buffers.
4. Dart calls `cv_free_browser_digest_result_ptr` before freeing the outer struct.

Integration invariant:

```text
native call returns
   ↓
copy returned bytes into Dart-owned String/Uint8List
   ↓
call ContextVault free function
   ↓
free Dart-side temporary allocations
```

Never retain a pointer returned by the native library after the free call.

## Fail-closed rules

- nonzero status + no explicit error → synthesize an error message;
- invalid UTF-8/JSON → reject import;
- missing ABI symbol → mark ContextVault native runtime unavailable;
- production native acceptance must not silently count a Dart fallback as native success.
