#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
executable="$app/Contents/MacOS/MHGLauncher"
log="$(mktemp)"
data="$(mktemp -d)"
assets="$(mktemp -d)"

cleanup() {
  [[ -n "${backend_pid:-}" ]] && kill "$backend_pid" 2>/dev/null || true
  [[ -n "${app_pid:-}" ]] && kill "$app_pid" 2>/dev/null || true
  [[ -n "${launcher_pid:-}" ]] && kill "$launcher_pid" 2>/dev/null || true
  rm -f "$log"
  rm -rf "$data" "$assets"
}
trap cleanup EXIT

manifest="$("$root/scripts/create-smoke-runtime-assets.sh" "$assets" v0.1.0)"

MHG_DATA_DIR="$data" \
MHG_INSTANCE_LOCK_PATH="$data/app.lock" \
MHG_PROVIDER_MODE=fixture \
MHG_FIXTURE_DIR="$root/backend/fixtures" \
MHG_RUNTIME_MANIFEST_URL="$manifest" \
MHG_SMOKE_MODE=1 \
"$executable" >"$log" 2>&1 &
launcher_pid=$!

for _ in {1..100}; do
  app_pid="$(pgrep -f "^$executable$" | tail -n 1 || true)"
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    backend_pid="$(pgrep -P "$app_pid" -f '/node .*build/server.js' | head -n 1 || true)"
    if [[ -n "$backend_pid" ]]; then
      sleep 0.5
      kill -0 "$backend_pid" 2>/dev/null && break
      backend_pid=""
    fi
  fi
  sleep 0.1
done
if [[ -z "$app_pid" || -z "$backend_pid" ]]; then
  cat "$log" >&2
  printf '未观察到 App 与后端的父子进程关系\n' >&2
  exit 1
fi

bootstrap_ready=""
for _ in {1..600}; do
  if grep -q '"event":"bootstrap_ready"' "$log"; then
    bootstrap_ready="1"
    break
  fi
  if grep -q '"event":"bootstrap_failed"' "$log"; then
    cat "$log" >&2
    printf 'App bootstrap 报告失败\n' >&2
    exit 1
  fi
  if ! kill -0 "$app_pid" 2>/dev/null || ! kill -0 "$backend_pid" 2>/dev/null; then
    cat "$log" >&2
    printf 'App bootstrap 完成前进程已退出\n' >&2
    exit 1
  fi
  sleep 0.1
done
if [[ -z "$bootstrap_ready" ]]; then
  cat "$log" >&2
  printf '等待 App bootstrap 成功超时\n' >&2
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
