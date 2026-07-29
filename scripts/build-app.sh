#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
contents="$app/Contents"
backend_dir="${MHG_BACKEND_DIR:-}"
configured_plist="$(mktemp)"
trap 'rm -f "$configured_plist"' EXIT

if (( $# != 0 )); then
  printf 'App 仅保留 release 构建，不再接受构建配置参数。\n' >&2
  exit 2
fi

cp "$root/packaging/Info.plist" "$configured_plist"
swift "$root/scripts/configure-cloud-server.swift" "$root/.env" "$configured_plist"

if [[ -z "$backend_dir" ]]; then
  "$root/scripts/build-backend.sh"
  backend_dir="$root/build/backend/dist/MHGLauncherBackend"
fi
test -d "$backend_dir/app"
test "$(cat "$backend_dir/app/.build-mode")" = "release"
"$root/scripts/build-frontend.sh"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources/Backend"

cp "$configured_plist" "$contents/Info.plist"
cp "$root/frontend/.build/arm64-apple-macosx/release/MHGLauncher" \
  "$contents/MacOS/MHGLauncher"
resource_bundle="$root/frontend/.build/arm64-apple-macosx/release/MHGLauncher_MHGLauncher.bundle"
test -d "$resource_bundle"
cp -R "$resource_bundle" "$contents/Resources/"
cp -R "$backend_dir/app" "$contents/Resources/Backend/app"

compile_composer_icon() {
  local icon="$1"
  local developer_dir="${DEVELOPER_DIR:-}"
  local actool=""
  local icon_info

  if [[ -n "$developer_dir" && -x "$developer_dir/usr/bin/actool" ]]; then
    actool="$developer_dir/usr/bin/actool"
  elif [[ -x "/Applications/Xcode.app/Contents/Developer/usr/bin/actool" ]]; then
    developer_dir="/Applications/Xcode.app/Contents/Developer"
    actool="$developer_dir/usr/bin/actool"
  else
    return 1
  fi

  icon_info="$(mktemp)"
  DEVELOPER_DIR="$developer_dir" "$actool" \
    --compile "$contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --standalone-icon-behavior all \
    --output-partial-info-plist "$icon_info" \
    "$icon" >/dev/null
  rm -f "$icon_info"
  test -f "$contents/Resources/Assets.car"
  test -f "$contents/Resources/AppIcon.icns"
}

composer_icon="$root/frontend/Sources/Resources/AppIcon.icon"
if [[ ! -d "$composer_icon" ]]; then
  printf '缺少原生 Icon Composer 图标：%s\n' "$composer_icon" >&2
  exit 1
fi
if ! compile_composer_icon "$composer_icon"; then
  printf '无法编译 Icon Composer 图标，请安装与目标系统匹配的最新版 Xcode。\n' >&2
  exit 1
fi

chmod +x "$contents/MacOS/MHGLauncher"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
test ! -e "$contents/Resources/Backend/node"
test ! -e "$contents/Resources/GameRuntime"
"$root/scripts/sign-app.sh" "$app"
