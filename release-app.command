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

content_signature() {
  (
    cd "$root"
    git ls-files --cached --others --exclude-standard -- "$@" |
      LC_ALL=C sort |
      while IFS= read -r file_path; do
        if is_markdown "$file_path"; then
          continue
        fi
        printf '%s\0' "$file_path"
        if [[ -e "$file_path" || -L "$file_path" ]]; then
          git hash-object --no-filters -- "$file_path"
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
      [[ "$(cat "$candidate/Contents/Resources/.release-source-signature" 2>/dev/null || true)" == "$source_hash" ]]; then
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
signature_file="$cached_app/Contents/Resources/.release-source-signature"
frontend_hash="$(content_signature \
  frontend packaging/Info.plist scripts/build-frontend.sh \
  scripts/build-app.sh scripts/configure-cloud-server.swift)"
backend_hash="$(content_signature \
  backend scripts/build-backend.sh scripts/fetch-hpatchz.sh)"
source_hash="$(printf '%s%s' "$frontend_hash" "$backend_hash" |
  shasum -a 256 | awk '{print $1}')"
frontend_test_hash="$(content_signature \
  frontend quality/coverage-baseline.json scripts/check-coverage.mjs \
  scripts/check-source-lines.sh scripts/test-frontend.sh)"
backend_test_hash="$(content_signature \
  backend quality/coverage-baseline.json scripts/check-coverage.mjs \
  scripts/check-source-lines.sh scripts/fetch-node.sh scripts/test-backend.sh)"
api_test_hash="$(content_signature \
  contracts/local-api backend/src/api backend/src/core/models.ts \
  frontend/Sources/Models frontend/Sources/Services/APIClient.swift \
  frontend/Tests/APIClientTests.swift frontend/Tests/APIContractFixture.swift \
  frontend/Tests/APIContractRequestTests.swift \
  frontend/Tests/APIContractResponseTests.swift \
  scripts/check-api-boundary.sh)"
build_test_hash="$(content_signature \
  release-app.command packaging/Info.plist scripts/build-app.sh \
  scripts/build-backend.sh scripts/build-frontend.sh \
  scripts/configure-cloud-server.swift scripts/test-build-config.sh)"
backend_cache="$root/build/backend-release-cache/$backend_hash/MHGLauncherBackend"
run_dir="$root/build/release-run/$source_hash"
run_app="$run_dir/MHGLauncher.app"
run_binary="$run_app/Contents/MacOS/MHGLauncher"
# 默认使用源码签名缓存；需要排查缓存问题时再显式强制重建。
force_rebuild="${MHG_RELEASE_FORCE_REBUILD:-0}"
force_tests="${MHG_RELEASE_FORCE_TESTS:-0}"

# 测试基线来自上一次成功写入发布 App 的板块签名。
test_baseline=""
for candidate in "$built_app" "$cached_app"; do
  resources="$candidate/Contents/Resources"
  if [[ -f "$resources/.release-test-frontend-signature" ]] &&
    [[ -f "$resources/.release-test-backend-signature" ]] &&
    [[ -f "$resources/.release-test-api-signature" ]] &&
    [[ -f "$resources/.release-test-build-signature" ]]; then
    test_baseline="$resources"
    break
  fi
done

frontend_changed=1
backend_changed=1
api_changed=1
build_changed=1
if [[ -n "$test_baseline" ]] && [[ "$force_tests" != "1" ]]; then
  [[ "$(cat "$test_baseline/.release-test-frontend-signature")" == "$frontend_test_hash" ]] &&
    frontend_changed=0
  [[ "$(cat "$test_baseline/.release-test-backend-signature")" == "$backend_test_hash" ]] &&
    backend_changed=0
  [[ "$(cat "$test_baseline/.release-test-api-signature")" == "$api_test_hash" ]] &&
    api_changed=0
  [[ "$(cat "$test_baseline/.release-test-build-signature")" == "$build_test_hash" ]] &&
    build_changed=0
fi

if (( frontend_changed == 0 && backend_changed == 0 &&
  api_changed == 0 && build_changed == 0 )); then
  printf '与上一次构建相比无测试相关变更，跳过测试。\n'
else
  (( build_changed == 1 )) &&
    printf '检测到构建配置变化，正在运行构建配置测试...\n' &&
    /bin/bash "$root/scripts/test-build-config.sh"
  (( backend_changed == 1 )) &&
    printf '检测到后端变化，正在运行后端测试...\n' &&
    /bin/bash "$root/scripts/test-backend.sh"
  (( frontend_changed == 1 )) &&
    printf '检测到前端变化，正在运行前端测试...\n' &&
    /bin/bash "$root/scripts/test-frontend.sh"
  if (( api_changed == 1 )); then
    if (( frontend_changed == 1 && backend_changed == 1 )); then
      printf 'API 边界已由前后端完整测试覆盖。\n'
    else
      printf '检测到 API 边界变化，正在运行跨端契约测试...\n'
      /bin/bash "$root/scripts/check-api-boundary.sh"
    fi
  fi
fi

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
  printf '源码已变化，正在构建最新的发布版 MHGLauncher.app...\n'
  if [[ ! -x "$backend_cache/MHGLauncherBackend" ]]; then
    printf '后端源码已变化，正在更新发布后端缓存...\n'
    /bin/bash "$root/scripts/build-backend.sh"
    mkdir -p "$(dirname "$backend_cache")"
    cp -R "$root/build/backend/dist/MHGLauncherBackend" "$backend_cache"
  else
    printf '后端源码未变化，复用发布后端缓存。\n'
  fi
  MHG_BACKEND_DIR="$backend_cache" \
    /bin/bash "$root/scripts/build-app.sh"
  rm -rf "$cached_app"
  mv "$built_app" "$cached_app"
  printf '%s\n' "$source_hash" >"$signature_file"
fi

resources="$cached_app/Contents/Resources"
# 只有测试和构建均成功后才推进基线，失败的变更会在下次继续验证。
printf '%s\n' "$frontend_test_hash" >"$resources/.release-test-frontend-signature"
printf '%s\n' "$backend_test_hash" >"$resources/.release-test-backend-signature"
printf '%s\n' "$api_test_hash" >"$resources/.release-test-api-signature"
printf '%s\n' "$build_test_hash" >"$resources/.release-test-build-signature"

# 保留一个固定入口，避免用户从 Finder 打开的 dist App 落后于运行副本。
rm -rf "$built_app"
cp -cR "$cached_app" "$built_app"

printf '正在启动发布版：%s\n' "$cached_app"
printf '关闭 MHGLauncher 后将保留此 App。\n'

rm -rf "$run_dir"
mkdir -p "$run_dir"
cp -cR "$cached_app" "$run_app"
chmod +x "$run_binary"

runtime_env=()
if [[ -n "${MHG_RUNTIME_MANIFEST_URL:-}" ]]; then
  runtime_env+=(MHG_RUNTIME_MANIFEST_URL="$MHG_RUNTIME_MANIFEST_URL")
fi

env "${runtime_env[@]}" "$run_binary" &
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

printf 'MHGLauncher 已关闭，发布版 App 已保留：%s\n' "$cached_app"
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
