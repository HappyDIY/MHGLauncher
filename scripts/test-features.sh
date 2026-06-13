#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/build/backend/dist/MHGLauncherBackend/MHGLauncherBackend"
log="$(mktemp)"
data="$(mktemp -d)"
token="feature-test-token"

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
    break
  fi
  sleep 0.05
done
test -n "${port:-}"

base="http://127.0.0.1:$port"
auth=(-H "Authorization: Bearer $token" -H "Content-Type: application/json")

request() {
  curl --fail --silent "${auth[@]}" "$@"
}

test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$base/v1/account")" = "401"

session="$(request -X POST "$base/v1/auth/qr-sessions" -d '{}')"
ticket="$(jq -r '.id' <<<"$session")"
test -n "$ticket"
test "$(jq -r '.status' <<<"$session")" = "created"

scanned="$(request "$base/v1/auth/qr-sessions/$ticket")"
test "$(jq -r '.session.status' <<<"$scanned")" = "scanned"
confirmed="$(request "$base/v1/auth/qr-sessions/$ticket")"
test "$(jq -r '.session.status' <<<"$confirmed")" = "confirmed"

identity="$(jq -c '.identity' <<<"$confirmed")"
login_body="$(jq -nc \
  --argjson identity "$identity" \
  '{identity:$identity, credential_ref:"keychain:feature-test"}')"
login="$(request -X POST "$base/v1/auth/complete" -d "$login_body")"
test "$(jq -r '.account.nickname' <<<"$login")" = "测试旅行者"
test "$(jq -r '.roles[0].uid' <<<"$login")" = "100000001"

credential="$(jq -r '.identity.credential' <<<"$confirmed")"
credential_body="$(jq -nc --arg credential "$credential" '{credential:$credential}')"
roles="$(request -X POST "$base/v1/roles/sync" -d "$credential_body")"
test "$(jq 'length' <<<"$roles")" = "1"
test "$(jq -r '.[0].selected' <<<"$roles")" = "true"

account="$(request "$base/v1/account")"
test "$(jq -r '.credential_ref' <<<"$account")" = "keychain:feature-test"
listed_roles="$(request "$base/v1/roles")"
test "$(jq -r '.[0].nickname' <<<"$listed_roles")" = "旅行者"

game="$(request "$base/v1/game/status")"
test "$(jq -r '.status' <<<"$game")" = "not_installed"
test "$(jq -r '.available_version' <<<"$game")" = "5.8.0"

launch_file="$(mktemp)"
launch_status="$(curl --silent --output "$launch_file" --write-out '%{http_code}' \
  "${auth[@]}" -X POST "$base/v1/game/launch" -d '{}')"
test "$launch_status" = "501"
test "$(jq -r '.code' "$launch_file")" = "launch_not_implemented"
rm -f "$launch_file"

first_sync="$(request -X POST "$base/v1/wishes/sync" -d "$credential_body")"
second_sync="$(request -X POST "$base/v1/wishes/sync" -d "$credential_body")"
test "$(jq -r '.inserted' <<<"$first_sync")" = "2"
test "$(jq -r '.inserted' <<<"$second_sync")" = "0"

wishes="$(request "$base/v1/wishes?uid=100000001")"
test "$(jq 'length' <<<"$wishes")" = "2"
stats="$(request "$base/v1/wishes/statistics?uid=100000001")"
test "$(jq -r '.[0].five_star_count' <<<"$stats")" = "1"

uigf="$(request "$base/v1/wishes/export?uid=100000001")"
test "$(jq -r '.info.version' <<<"$uigf")" = "v4.2"
test "$(jq -r '.info | has("uigf_version")' <<<"$uigf")" = "false"
imported="$(request -X POST "$base/v1/wishes/import" -d "$uigf")"
test "$(jq -r '.imported' <<<"$imported")" = "2"

note="$(request -X POST "$base/v1/notes/refresh" -d "$credential_body")"
test "$(jq -r '.current_resin' <<<"$note")" = "120"
cached="$(request "$base/v1/notes?uid=100000001")"
test "$(jq -r '.finished_tasks' <<<"$cached")" = "3"

request -X DELETE "$base/v1/account" >/dev/null
test "$(request "$base/v1/account")" = "null"
test "$(request "$base/v1/roles")" = "[]"

missing_role_file="$(mktemp)"
missing_role_status="$(curl --silent --output "$missing_role_file" \
  --write-out '%{http_code}' "${auth[@]}" -X POST \
  "$base/v1/notes/refresh" -d "$credential_body")"
test "$missing_role_status" = "409"
test "$(jq -r '.code' "$missing_role_file")" = "role_missing"
rm -f "$missing_role_file"

printf '冻结后端功能矩阵测试通过（未触发大型游戏下载）。\n'
