#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/build/backend/dist/MHGLauncherBackend/MHGLauncherBackend"
log="$(mktemp)"
data="$(mktemp -d)"
token="smoke-token"

cleanup() {
  if [[ -n "${pid:-}" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$log"
  rm -rf "$data"
}
trap cleanup EXIT

MHG_DATA_DIR="$data" \
MHG_API_TOKEN="$token" \
MHG_PROVIDER_MODE=fixture \
MHG_FIXTURE_DIR="$root/backend/fixtures" \
"$binary" >"$log" 2>&1 &
pid=$!

for _ in {1..100}; do
  ready="$(head -n 1 "$log" 2>/dev/null || true)"
  if [[ "$ready" == *'"event": "ready"'* ]]; then
    port="$(printf '%s' "$ready" | sed -E 's/.*"port": ([0-9]+).*/\1/')"
    curl --fail --silent "http://127.0.0.1:$port/health" | grep -q '"status":"ok"'
    exit 0
  fi
  sleep 0.05
done

cat "$log" >&2
exit 1

