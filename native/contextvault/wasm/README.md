# ContextVault Browser/WASM Library

This folder contains the browser-facing library boundary for a future WebAssembly build.

The goal is to expose ContextVault functionality to a browser worker without modifying the existing core `src/` files.

## Current Boundary

`contextvault_browser_lib` links against the existing `com_decom` core library and exposes a small C ABI:

```cpp
CvBrowserDigestResult cv_digest_chatgpt_json_summary(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* source_name
);

void cv_free_browser_digest_result(CvBrowserDigestResult result);
```

The current function proves the boundary by calling existing core functions:

```cpp
tp::import_chatgpt_bytes(...)
tp::build_txt_atom_index(...)
```

It returns a JSON summary with source, title, paragraph count, atom count, and thread count.

## Native Probe

Build:

```powershell
cmake --build build --target tp_browser_lib_probe --config Debug
```

Run:

```powershell
build\Debug\tp_browser_lib_probe.exe tools\fixtures\chatgpt_export_tiny.json
```

Expected shape:

```json
{"source":"...","title":"chatgpt_export_tiny","paragraphs":4,"atoms":4,"threads":3,"source_kind":"chatgpt"}
```

## Browser POC Direction

For the browser proof:

1. JavaScript reads the ChatGPT ZIP and extracts `conversations.json` / `conversations-*.json`.
2. JavaScript passes combined JSON bytes into the WASM wrapper.
3. WASM calls ContextVault core functions.
4. WASM returns JSON metadata and, later, markdown file contents.
5. JavaScript packages returned files into `digest.zip`.

## Next WASM API

The next function should return markdown files:

```cpp
CvBrowserDigestResult cv_digest_chatgpt_json_to_markdown(
    const std::uint8_t* json_bytes,
    std::size_t json_size,
    const char* options_json
);
```

Suggested JSON result:

```json
{
  "files": [
    {"path": "index.md", "content": "..."},
    {"path": "topics/001_topic.md", "content": "..."}
  ],
  "stats": {
    "paragraphs": 21282,
    "atoms": 381852,
    "topic_files": 883
  }
}
```

## Notes

- Existing core files are not modified for this wrapper.
- The wrapper is intentionally separate from `tools/tp_chatgpt_digest.cpp`.
- Avoid compiling the CLI directly to WASM; expose library-style functions instead.
- ZIP read/write should stay in JavaScript for the first browser POC.
