#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
executable="$app/Contents/MacOS/MHGLauncher"
log="$(mktemp)"
data="$(mktemp -d)"

cleanup() {
  [[ -n "${app_pid:-}" ]] && kill "$app_pid" 2>/dev/null || true
  [[ -n "${launcher_pid:-}" ]] && kill "$launcher_pid" 2>/dev/null || true
  rm -f "$log"
  rm -rf "$data"
}
trap cleanup EXIT

MHG_DATA_DIR="$data" \
MHG_INSTANCE_LOCK_PATH="$data/app.lock" \
MHG_PROVIDER_MODE=fixture \
MHG_SMOKE_MODE=1 \
"$executable" >"$log" 2>&1 &
launcher_pid=$!

for _ in {1..100}; do
  app_pid="$(pgrep -f "^$executable$" | tail -n 1 || true)"
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if [[ -z "$app_pid" ]]; then
  cat "$log" >&2
  printf '未观察到 App 进程\n' >&2
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
  if ! kill -0 "$app_pid" 2>/dev/null; then
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

children="$(pgrep -P "$app_pid" || true)"
if [[ -n "$children" ]]; then
  ps -p "$children" -o pid,ppid,command >&2 || true
  printf 'Fixture 启动不应产生后台子进程\n' >&2
  exit 1
fi
if find "$data" -type s -print -quit | grep -q .; then
  printf '纯 Swift App 不应创建 Unix Socket\n' >&2
  exit 1
fi

kill "$app_pid"

for _ in {1..50}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    app_pid=""
    break
  fi
  sleep 0.1
done

if [[ -n "$app_pid" ]]; then
  printf 'App 进程未正常退出：%s\n' "$app_pid" >&2
  exit 1
fi
if find "$data/launches" -name dll-journal.json -print -quit 2>/dev/null | grep -q .; then
  printf '退出后仍存在未恢复的启动文件记录\n' >&2
  exit 1
fi
