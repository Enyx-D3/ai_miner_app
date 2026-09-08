#!/usr/bin/env bash
set -euo pipefail
APK="${1:?Usage: verify_contextvault_in_apk.sh path/to/app-release.apk}"
[[ -f "$APK" ]] || { echo "FAIL: APK not found: $APK"; exit 2; }
python3 - "$APK" <<'PY'
import sys, zipfile
apk=sys.argv[1]
needle='lib/arm64-v8a/libcontextvault.so'
with zipfile.ZipFile(apk) as z:
    names=set(z.namelist())
    if needle not in names:
        raise SystemExit(f'FAIL: {needle} not packaged in APK')
    info=z.getinfo(needle)
    if info.file_size <= 0:
        raise SystemExit('FAIL: packaged libcontextvault.so is empty')
    print(f'PASS: {needle} packaged ({info.file_size} bytes)')
PY
