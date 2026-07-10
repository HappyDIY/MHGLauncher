#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
built_app="$root/dist/MHGLauncher.app"
app_pid=""
backend_pid=""
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
    git log -1 --format=%H -- "$@"
    git ls-files --cached --others --exclude-standard -- "$@" |
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

  if [[ -n "$app_pid" ]]; then
    backend_pid="$(pgrep -P "$app_pid" -f MHGLauncherBackend | head -n 1 || true)"
  fi
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ -n "$backend_pid" ]] && kill -0 "$backend_pid" 2>/dev/null; then
    kill "$backend_pid" 2>/dev/null || true
  fi

  exit "$status"
}
trap cleanup EXIT INT TERM HUP

git_hash="$(git -C "$root" rev-parse --verify HEAD)"
cached_app="$root/dist/$git_hash.app"
signature_file="$cached_app/Contents/Resources/.debug-source-signature"
frontend_hash="$(source_signature \
  frontend packaging/Info.plist scripts/build-frontend.sh \
  scripts/build-debug-app.sh)"
backend_hash="$(source_signature \
  backend scripts/build-backend.sh scripts/build-backend-debug.sh \
  scripts/fetch-hpatchz.sh)"
source_hash="$(printf '%s%s' "$frontend_hash" "$backend_hash" |
  shasum -a 256 | awk '{print $1}')"
backend_cache="$root/build/backend-debug-cache/$backend_hash/MHGLauncherBackend"
run_dir="$root/build/debug-run/$source_hash"
run_app="$run_dir/MHGLauncher.app"
run_binary="$run_app/Contents/MacOS/MHGLauncher"
# 默认使用源码签名缓存；需要排查缓存问题时再显式强制重建。
force_rebuild="${MHG_DEBUG_FORCE_REBUILD:-0}"

pkill -x MHGLauncher 2>/dev/null || true
pkill -x MHGLauncherBackend 2>/dev/null || true
sleep 1

if [[ "$force_rebuild" != "1" ]] && [[ -d "$cached_app" ]] &&
  [[ "$(cat "$signature_file" 2>/dev/null || true)" == "$source_hash" ]]; then
  printf '源码未变化，复用缓存：%s\n' "$cached_app"
elif [[ "$force_rebuild" != "1" ]] && reusable_app="$(find_cached_app)"; then
  printf '仅 Git 哈希或文档变化，复用已有构建：%s\n' "$reusable_app"
  rm -rf "$cached_app"
  cp -R "$reusable_app" "$cached_app"
else
  printf '源码已变化，正在构建最新的 MHGLauncher.app...\n'
  if [[ ! -x "$backend_cache/MHGLauncherBackend" ]]; then
    printf '后端源码已变化，正在更新冻结后端...\n'
    /bin/bash "$root/scripts/build-backend-debug.sh"
    mkdir -p "$(dirname "$backend_cache")"
    cp -R "$root/build/backend-debug/dist/MHGLauncherBackend" "$backend_cache"
  else
    printf '后端源码未变化，复用冻结后端缓存。\n'
  fi
  MHG_DEBUG_BACKEND_DIR="$backend_cache" \
    /bin/bash "$root/scripts/build-debug-app.sh"
  rm -rf "$cached_app"
  mv "$built_app" "$cached_app"
  printf '%s\n' "$source_hash" >"$signature_file"
fi

printf '正在启动：%s\n' "$cached_app"
printf '关闭 MHGLauncher 后将保留此 App。\n'

rm -rf "$run_dir"
mkdir -p "$run_dir"
cp -cR "$cached_app" "$run_app"
chmod +x "$run_binary"

runtime_env=()
if [[ -n "${MHG_RUNTIME_MANIFEST_URL:-}" ]]; then
  runtime_env+=(MHG_RUNTIME_MANIFEST_URL="$MHG_RUNTIME_MANIFEST_URL")
fi

env MHG_DEBUG_MODE=1 "${runtime_env[@]}" "$run_binary" &
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
