#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SO="${1:-$ROOT/android/app/src/main/jniLibs/arm64-v8a/libcontextvault.so}"
[[ -f "$SO" ]] || { echo "FAIL: missing $SO"; exit 2; }
file "$SO"
SYMS=(
  cv_digest_chatgpt_json_summary_out
  cv_digest_chatgpt_json_to_markdown_out
  cv_free_browser_digest_result_ptr
  cv_mobile_digest_markdown_file
  cv_mobile_last_error
  cv_mobile_free_string
)
if command -v readelf >/dev/null 2>&1; then
  readelf -h "$SO" | grep -E 'AArch64|Machine:.*AArch64' >/dev/null || { echo 'FAIL: not AArch64'; exit 3; }
  for sym in "${SYMS[@]}"; do
    readelf -Ws "$SO" | grep -F "$sym" >/dev/null || { echo "FAIL: missing export $sym"; exit 4; }
  done
elif command -v llvm-nm >/dev/null 2>&1; then
  for sym in "${SYMS[@]}"; do
    llvm-nm -D "$SO" | grep -F "$sym" >/dev/null || { echo "FAIL: missing export $sym"; exit 4; }
  done
else
  echo 'WARN: readelf/llvm-nm unavailable; ABI exports were not independently checked.'
fi
echo 'PASS: ContextVault Android ARM64 ABI contract'
