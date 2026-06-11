#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
built_app="$root/dist/MHGLauncher.app"
temp_root=""
app_pid=""
terminal_tty="$(tty 2>/dev/null || true)"

remove_artifacts() {
  if [[ -n "$temp_root" ]]; then
    rm -rf "$temp_root"
  fi
}

cleanup() {
  status=$?
  trap - EXIT INT TERM HUP

  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi

  remove_artifacts
  exit "$status"
}
trap cleanup EXIT INT TERM HUP

pkill -x MHGLauncher 2>/dev/null || true
pkill -x MHGLauncherBackend 2>/dev/null || true
sleep 1

printf '正在构建 MHGLauncher.app...\n'
"$root/scripts/build-app.sh"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/MHGLauncher-debug.XXXXXX")"
temp_app="$temp_root/MHGLauncher.app"
cp -R "$built_app" "$temp_app"

printf '构建完成，正在临时启动：%s\n' "$temp_app"
printf '关闭 MHGLauncher 后将自动销毁临时 App。\n'

"$temp_app/Contents/MacOS/MHGLauncher" &
app_pid=$!

set +e
wait "$app_pid"
status=$?
set -e
app_pid=""

if [[ "$status" -ne 0 ]]; then
  printf 'MHGLauncher 异常退出，状态码：%s\n' "$status" >&2
  exit "$status"
fi

printf 'MHGLauncher 已关闭，正在清理临时 App...\n'
remove_artifacts
temp_root=""
trap - EXIT INT TERM HUP

if [[ "$terminal_tty" == /dev/tty* ]]; then
  nohup osascript - "$terminal_tty" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run arguments
    set targetTTY to item 1 of arguments
    delay 0.2

    tell application "Terminal"
        repeat with terminalWindow in windows
            repeat with terminalTab in tabs of terminalWindow
                if tty of terminalTab is targetTTY then
                    close terminalWindow
                    return
                end if
            end repeat
        end repeat
    end tell
end run
APPLESCRIPT
fi
