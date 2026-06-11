#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
log="$(mktemp)"
data="$(mktemp -d)"

cleanup() {
  if [[ -n "${pid:-}" ]]; then
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$log"
  rm -rf "$data"
}
trap cleanup EXIT

MHG_DATA_DIR="$data" \
MHG_PROVIDER_MODE=fixture \
MHG_FIXTURE_DIR="$root/backend/fixtures" \
"$app/Contents/MacOS/MHGLauncher" >"$log" 2>&1 &
pid=$!

sleep 3
if ! kill -0 "$pid" 2>/dev/null; then
  cat "$log" >&2
  exit 1
fi

child="$(pgrep -P "$pid" -f MHGLauncherBackend | head -n 1 || true)"
kill "$pid"
wait "$pid" 2>/dev/null || true
pid=""

if [[ -n "$child" ]]; then
  for _ in {1..50}; do
    if ! kill -0 "$child" 2>/dev/null; then
      exit 0
    fi
    sleep 0.1
  done
  printf '后端进程未随 App 退出：%s\n' "$child" >&2
  exit 1
fi
