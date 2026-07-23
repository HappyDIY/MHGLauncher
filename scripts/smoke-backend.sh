#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root/build/backend/dist/MHGLauncherBackend/app"
node_root="$("$root/scripts/fetch-node.sh")"
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

if [[ ! -d "$app_dir" ]]; then
  "$root/scripts/build-backend.sh"
fi
ln -sfn "$("$root/scripts/prepare-smoke-node-modules.sh")" "$app_dir/node_modules"

(
  cd "$app_dir"
  MHG_SOCKET_PATH="$socket" MHG_DATA_DIR="$data" MHG_API_TOKEN=smoke-token \
  MHG_PROVIDER_MODE=fixture MHG_FIXTURE_DIR="$root/backend/fixtures" \
  NODE_ENV=production MHG_HPATCHZ="$data/hpatchz" MHG_RUNTIME_ROOT="$data/runtime" \
  "$node_root/bin/node" build/server.js
) >"$log" 2>&1 &
pid=$!
for _ in {1..100}; do [[ -S "$socket" ]] && break; sleep 0.05; done
test -S "$socket"
curl --fail --silent --unix-socket "$socket" -H "Authorization: Bearer smoke-token" \
  http://localhost/health | grep -q '"status":"ok"'
test "$(stat -f '%Lp' "$socket")" = "600"
if lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN | grep -q LISTEN; then
  printf '后端不应监听 TCP 端口\n' >&2
  exit 1
fi
for _ in {1..100}; do grep -q '"socket_path"' "$log" && break; sleep 0.01; done
grep -q '"socket_path"' "$log"
