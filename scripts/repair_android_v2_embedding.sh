#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo 'Brain2 AI Miner: rebuilding Android host shell with Flutter v2 embedding...'
bash scripts/bootstrap_android.sh
