#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/build/backend/dist/MHGLauncherBackend/MHGLauncherBackend"
socket="$(mktemp -u /tmp/mhg-smoke.XXXXXX).sock"
log="$(mktemp)"
data="$(mktemp -d)"

cleanup() {
  [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
  [[ -n "${pid:-}" ]] && wait "$pid" 2>/dev/null || true
  rm -f "$log" "$socket"
  rm -rf "$data"
}
trap cleanup EXIT

MHG_SOCKET_PATH="$socket" MHG_DATA_DIR="$data" MHG_API_TOKEN=smoke-token \
MHG_PROVIDER_MODE=fixture MHG_FIXTURE_DIR="$root/backend/fixtures" "$binary" >"$log" 2>&1 &
pid=$!
for _ in {1..100}; do [[ -S "$socket" ]] && break; sleep 0.05; done
test -S "$socket"
curl --fail --silent --unix-socket "$socket" http://localhost/health | grep -q '"status":"ok"'
test "$(stat -f '%Lp' "$socket")" = "600"
if lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN | grep -q LISTEN; then
  printf '后端不应监听 TCP 端口\n' >&2
  exit 1
fi
grep -q '"socket_path"' "$log"
