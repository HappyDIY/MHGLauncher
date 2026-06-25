#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root/build/backend/dist/MHGLauncherBackend/app"
node_root="$("$root/scripts/fetch-node.sh")"
socket="$(mktemp -u /tmp/mhg-features.XXXXXX).sock"
data="$(mktemp -d)"
log="$(mktemp)"
token="feature-test-token"

cleanup() {
  [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
  [[ -n "${pid:-}" ]] && wait "$pid" 2>/dev/null || true
  rm -f "$socket" "$log"
  rm -rf "$data"
}
trap cleanup EXIT

if [[ ! -d "$app_dir" ]]; then
  "$root/scripts/build-backend.sh"
fi
ln -sfn "$("$root/scripts/prepare-smoke-node-modules.sh")" "$app_dir/node_modules"

(
  cd "$app_dir"
  MHG_SOCKET_PATH="$socket" MHG_DATA_DIR="$data" MHG_API_TOKEN="$token" \
  MHG_PROVIDER_MODE=fixture MHG_FIXTURE_DIR="$root/backend/fixtures" \
  NODE_ENV=production MHG_HPATCHZ="$data/hpatchz" MHG_RUNTIME_ROOT="$data/runtime" \
  "$node_root/bin/node" build/server.js
) >"$log" 2>&1 &
pid=$!
for _ in {1..100}; do [[ -S "$socket" ]] && break; sleep 0.05; done
if [[ ! -S "$socket" ]]; then
  cat "$log" >&2
  exit 1
fi

request() {
  curl --fail --silent --unix-socket "$socket" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" "$@"
}
test "$(curl --silent --unix-socket "$socket" --output /dev/null --write-out '%{http_code}' http://localhost/v1/account)" = "401"

session="$(request -X POST http://localhost/v1/auth/qr-sessions -d '{}')"
ticket="$(jq -r '.id' <<<"$session")"
request "http://localhost/v1/auth/qr-sessions/$ticket" >/dev/null
confirmed="$(request "http://localhost/v1/auth/qr-sessions/$ticket")"
identity="$(jq -c '.identity' <<<"$confirmed")"
login="$(request -X POST http://localhost/v1/auth/complete \
  -d "$(jq -nc --argjson identity "$identity" '{identity:$identity,credential_ref:"keychain:test"}')")"
test "$(jq -r '.roles[0].uid' <<<"$login")" = "100000001"

credential="$(jq -r '.identity.credential' <<<"$confirmed")"
task="$(request -X POST http://localhost/v1/wishes/tasks/sync \
  -d "$(jq -nc --arg credential "$credential" '{credential:$credential}')")"
task_id="$(jq -r '.id' <<<"$task")"
for _ in {1..100}; do
  snapshot="$(request "http://localhost/v1/wishes/tasks/$task_id")"
  [[ "$(jq -r '.status' <<<"$snapshot")" = "completed" ]] && break
  sleep 0.02
done
test "$(jq -r '.result.inserted' <<<"$snapshot")" = "2"
test "$(request 'http://localhost/v1/wishes?uid=100000001' | jq length)" = "2"
test "$(request 'http://localhost/v1/wishes/export?uid=100000001' | jq -r '.info.version')" = "v4.2"

note="$(request -X POST http://localhost/v1/notes/refresh \
  -d "$(jq -nc --arg credential "$credential" '{credential:$credential}')")"
test "$(jq -r '.current_resin' <<<"$note")" = "120"
launch_body='{"install_path":"/tmp/mhg-missing-game"}'
test "$(request -X POST http://localhost/v1/game/launch -d "$launch_body" --output /dev/null --write-out '%{http_code}' || true)" = "409"
printf 'Unix Socket 冻结后端功能矩阵测试通过。\n'
