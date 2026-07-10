#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/dist/MHGLauncher.app"
app_pid=""

source_signature() {
  (
    cd "$root"
    git log -1 --format=%H -- frontend backend packaging scripts release-app.command
    git ls-files --cached --others --exclude-standard -- frontend backend packaging scripts release-app.command |
      LC_ALL=C sort |
      while IFS= read -r file_path; do
        case "$file_path" in
          *.[mM][dD]) continue ;;
        esac
        printf '%s\0' "$file_path"
        if [[ -e "$file_path" || -L "$file_path" ]]; then
          git hash-object --no-filters -- "$file_path"
        else
          printf 'deleted\n'
        fi
      done
  ) | shasum -a 256 | awk '{print $1}'
}

source_hash="$(source_signature)"
signature_file="$app/Contents/Resources/.release-source-signature"

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

pkill -x MHGLauncher 2>/dev/null || true
pkill -x MHGLauncherBackend 2>/dev/null || true
sleep 1

printf '正在构建发布版 MHGLauncher.app...\n'
if [[ ! -d "$app" ]] || [[ "$(cat "$signature_file" 2>/dev/null || true)" != "$source_hash" ]]; then
  "$root/scripts/build-app.sh" --release
  printf '%s\n' "$source_hash" >"$signature_file"
else
  printf '源码未变化，复用发布版构建：%s\n' "$app"
fi

printf '正在启动发布版：%s\n' "$app"
"$app/Contents/MacOS/MHGLauncher" &
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

printf 'MHGLauncher 已关闭，发布版 App 已保留：%s\n' "$app"
trap - EXIT INT TERM HUP
