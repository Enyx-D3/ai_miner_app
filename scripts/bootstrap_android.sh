#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v flutter >/dev/null 2>&1 || { echo 'ERROR: flutter is not on PATH'; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo 'ERROR: python3 is not on PATH'; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Preserve only native binaries/notes. Never restore the old Android manifest,
# Gradle shell, MainActivity, or generated registrant: those are exactly the
# pieces that can carry stale Flutter embedding metadata.
if [[ -d android/app/src/main/jniLibs ]]; then
  mkdir -p "$TMP/jniLibs"
  cp -R android/app/src/main/jniLibs/. "$TMP/jniLibs/" || true
fi

rm -rf android

flutter create . \
  --platforms=android \
  --org com.brain2 \
  --project-name brain2_ai_miner_mobile

# Restore ContextVault native libs/README only.
if [[ -d "$TMP/jniLibs" ]]; then
  mkdir -p android/app/src/main/jniLibs
  cp -R "$TMP/jniLibs/." android/app/src/main/jniLibs/ || true
fi

# Patch the fresh Flutter-generated v2 manifest instead of replacing it.
python3 - <<'PY'
from pathlib import Path
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()

# Permissions go directly under <manifest>.
permissions = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.CAMERA" />',
]
insert = ''
for permission in permissions:
    if permission not in s:
        insert += '    ' + permission + '\n'
if insert:
    pos = s.find('>') + 1
    s = s[:pos] + '\n' + insert + s[pos:]

# Product label.
import re
s = re.sub(r'android:label="[^"]*"', 'android:label="Brain2 AI Miner"', s, count=1)

# Allow local/dev signaling endpoints where needed. Keep the generated
# application name (${applicationName}) and all v2 embedding metadata intact.
app_tag = re.search(r'<application\b[^>]*>', s, flags=re.S)
if app_tag:
    tag = app_tag.group(0)
    if 'android:usesCleartextTraffic=' not in tag:
        patched = tag[:-1] + '\n        android:usesCleartextTraffic="true">'
        s = s[:app_tag.start()] + patched + s[app_tag.end():]

p.write_text(s)
PY

# Hard fail if any Android-v1 embedding markers exist.
if grep -RInE 'io\.flutter\.app\.|PluginRegistry\.Registrar|FlutterApplication|SplashScreenUntilFirstFrame' android --exclude='*.so' >/tmp/brain2_v1_embedding_hits.txt 2>/dev/null; then
  echo 'ERROR: Android v1 embedding marker found after regeneration:'
  cat /tmp/brain2_v1_embedding_hits.txt
  exit 3
fi

if ! grep -q 'android:name="flutterEmbedding"' android/app/src/main/AndroidManifest.xml || \
   ! grep -q 'android:value="2"' android/app/src/main/AndroidManifest.xml; then
  echo 'ERROR: fresh manifest does not declare Flutter embedding v2.'
  exit 4
fi

if ! grep -Rqs 'io.flutter.embedding.android.FlutterActivity' android/app/src/main; then
  echo 'ERROR: modern FlutterActivity was not generated.'
  exit 5
fi

echo 'PASS: fresh Android v2 embedding shell generated from this machine\x27s Flutter SDK.'
echo 'PASS: Brain2 permissions/label and ContextVault jniLibs were preserved.'
echo
echo 'Next:'
echo '  bash scripts/build_and_install_contextvault_android.sh'
echo '  flutter pub get'
echo '  flutter analyze'
echo '  flutter test'
echo '  flutter run'
