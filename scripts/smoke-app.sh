#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
executable="$app/Contents/MacOS/MHGLauncher"
log="$(mktemp)"
data="$(mktemp -d)"

cleanup() {
  [[ -n "${backend_pid:-}" ]] && kill "$backend_pid" 2>/dev/null || true
  [[ -n "${app_pid:-}" ]] && kill "$app_pid" 2>/dev/null || true
  [[ -n "${launcher_pid:-}" ]] && kill "$launcher_pid" 2>/dev/null || true
  rm -f "$log"
  rm -rf "$data"
}
trap cleanup EXIT

MHG_DATA_DIR="$data" \
MHG_PROVIDER_MODE=fixture \
MHG_FIXTURE_DIR="$root/backend/fixtures" \
MHG_SMOKE_MODE=1 \
"$executable" >"$log" 2>&1 &
launcher_pid=$!

for _ in {1..100}; do
  app_pid="$(pgrep -f "^$executable$" | tail -n 1 || true)"
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    backend_pid="$(pgrep -P "$app_pid" -f 'MHGLauncherBackend|/node .*build/server.js' | head -n 1 || true)"
    [[ -n "$backend_pid" ]] && break
  fi
  sleep 0.1
done
if [[ -z "$app_pid" || -z "$backend_pid" ]]; then
  cat "$log" >&2
  printf '未观察到 App 与后端的父子进程关系\n' >&2
  exit 1
fi
kill "$app_pid"

for _ in {1..50}; do
  if ! kill -0 "$app_pid" 2>/dev/null && ! kill -0 "$backend_pid" 2>/dev/null; then
    app_pid=""
    backend_pid=""
    exit 0
  fi
  sleep 0.1
done

printf 'App 或后端进程未正常退出：%s %s\n' "$app_pid" "$backend_pid" >&2
exit 1
