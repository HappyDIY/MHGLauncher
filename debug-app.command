#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
built_app="$root/dist/MHGLauncher.app"
app_pid=""
terminal_tty="$(tty 2>/dev/null || true)"

is_markdown() {
  case "$1" in
    *.[mM][dD]) return 0 ;;
    *) return 1 ;;
  esac
}

source_signature() {
  (
    cd "$root"
    git log -1 --format=%H -- . \
      ':(exclude,glob)**/*.md' \
      ':(exclude,glob)*.md'
    git ls-files --cached --others --exclude-standard |
      LC_ALL=C sort |
      while IFS= read -r path; do
        if is_markdown "$path"; then
          continue
        fi
        printf '%s\0' "$path"
        if [[ -e "$path" || -L "$path" ]]; then
          git hash-object --no-filters -- "$path"
        else
          printf 'deleted\n'
        fi
      done
  ) | shasum -a 256 | awk '{print $1}'
}

find_cached_app() {
  local candidate
  for candidate in "$root"/dist/*.app; do
    if [[ -d "$candidate" ]] &&
      [[ "$(cat "$candidate/Contents/Resources/.debug-source-signature" 2>/dev/null || true)" == "$source_hash" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

cleanup() {
  status=$?
  trap - EXIT INT TERM HUP

  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi

  exit "$status"
}
trap cleanup EXIT INT TERM HUP

git_hash="$(git -C "$root" rev-parse --verify HEAD)"
cached_app="$root/dist/$git_hash.app"
signature_file="$cached_app/Contents/Resources/.debug-source-signature"
source_hash="$(source_signature)"

pkill -x MHGLauncher 2>/dev/null || true
pkill -x MHGLauncherBackend 2>/dev/null || true
sleep 1

if [[ -d "$cached_app" ]] &&
  [[ "$(cat "$signature_file" 2>/dev/null || true)" == "$source_hash" ]]; then
  printf '源码未变化，复用缓存：%s\n' "$cached_app"
elif reusable_app="$(find_cached_app)"; then
  printf '仅 Git 哈希或文档变化，复用已有构建：%s\n' "$reusable_app"
  rm -rf "$cached_app"
  cp -R "$reusable_app" "$cached_app"
else
  printf '检测到非 Markdown 文件变化，正在构建 MHGLauncher.app...\n'
  "$root/scripts/build-app.sh"
  rm -rf "$cached_app"
  mv "$built_app" "$cached_app"
  printf '%s\n' "$source_hash" >"$signature_file"
fi

printf '正在启动：%s\n' "$cached_app"
printf '关闭 MHGLauncher 后将保留此 App。\n'

"$cached_app/Contents/MacOS/MHGLauncher" &
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

printf 'MHGLauncher 已关闭，App 已保留：%s\n' "$cached_app"
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
