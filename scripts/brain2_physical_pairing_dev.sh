#!/usr/bin/env bash
set -euo pipefail

ANDROID_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_ROOT="${BRAIN2_WEB_ROOT:-"$ANDROID_ROOT/../ai-miner-web"}"
WEB_PORT="${BRAIN2_WEB_PORT:-3001}"
HTTPS_PORT="${BRAIN2_HTTPS_PORT:-3000}"
LOG_DIR="${TMPDIR:-/tmp}/brain2-physical-pairing"

need() {
  command -v "$1" >/dev/null || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need adb
need flutter
need mkcert
need node
need npm
need openssl

if [[ ! -d "$WEB_ROOT" ]]; then
  echo "web repo not found: $WEB_ROOT" >&2
  exit 1
fi

LAN_IP="${BRAIN2_LAN_IP:-}"
if [[ -z "$LAN_IP" ]]; then
  IFACE="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  LAN_IP="$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)"
fi
if [[ -z "$LAN_IP" ]]; then
  echo "could not detect LAN IP; set BRAIN2_LAN_IP=..." >&2
  exit 1
fi

CERT_DIR="$WEB_ROOT/.certs"
CERT="$CERT_DIR/brain2-lan-cert.pem"
KEY="$CERT_DIR/brain2-lan-key.pem"
mkdir -p "$CERT_DIR" "$LOG_DIR"

if [[ ! -f "$CERT" || ! -f "$KEY" ]]; then
  mkcert -cert-file "$CERT" -key-file "$KEY" "$LAN_IP" localhost 127.0.0.1
fi

FINGERPRINT="$(
  openssl x509 -in "$CERT" -noout -fingerprint -sha256 |
    sed 's/^.*=//' |
    tr -d ':[:space:]' |
    tr '[:upper:]' '[:lower:]'
)"

(cd "$WEB_ROOT" && npm run build)

(cd "$WEB_ROOT" && npm run start -- -p "$WEB_PORT" -H 127.0.0.1) \
  >"$LOG_DIR/web.log" 2>&1 &
WEB_PID=$!

node - "$CERT" "$KEY" "$WEB_PORT" "$HTTPS_PORT" >"$LOG_DIR/https-proxy.log" 2>&1 <<'NODE' &
const https = require("https");
const http = require("http");
const fs = require("fs");
const [cert, key, webPort, httpsPort] = process.argv.slice(2);
https.createServer({ cert: fs.readFileSync(cert), key: fs.readFileSync(key) }, (req, res) => {
  const proxy = http.request({
    hostname: "127.0.0.1",
    port: Number(webPort),
    method: req.method,
    path: req.url,
    headers: {
      ...req.headers,
      host: req.headers.host,
      "x-forwarded-proto": "https",
      "x-forwarded-host": req.headers.host,
    },
  }, (upstream) => {
    res.writeHead(upstream.statusCode || 502, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on("error", (error) => {
    res.writeHead(502, { "content-type": "text/plain" });
    res.end(String(error));
  });
  req.pipe(proxy);
}).listen(Number(httpsPort), "0.0.0.0");
NODE
PROXY_PID=$!

cleanup() {
  kill "$WEB_PID" "$PROXY_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 2

cd "$ANDROID_ROOT"
flutter build apk --debug \
  --dart-define="BRAIN2_DEV_HOST=$LAN_IP" \
  --dart-define="BRAIN2_DEV_CERT_SHA256=$FINGERPRINT"
adb install -r build/app/outputs/flutter-apk/app-debug.apk

cat <<EOF
READY FOR QR SCAN

Open: https://$LAN_IP:$HTTPS_PORT/devices
Android dart-defines:
  BRAIN2_DEV_HOST=$LAN_IP
  BRAIN2_DEV_CERT_SHA256=$FINGERPRINT

Logs:
  $LOG_DIR/web.log
  $LOG_DIR/https-proxy.log

Keep this process running while testing. Press Ctrl-C to stop Web/proxy.
EOF

wait
