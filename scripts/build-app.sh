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

build_icon() {
  local light="$1" out_icns="$2"
  local iconset="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    local half=$((size / 2))
    sips -z $size $size "$light" --out "$iconset/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -z $((size * 2)) $((size * 2)) "$light" --out "$iconset/icon_${half}x${half}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$iconset" -o "$out_icns"
  rm -rf "$(dirname "$iconset")"
}

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
icon_src="$root/frontend/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
if [[ -d "$composer_icon" ]] && compile_composer_icon "$composer_icon"; then
  :
elif [ -f "$icon_src/light.png" ]; then
  printf '未找到 Icon Composer 编译工具，回退到静态 AppIcon.icns。\n' >&2
  build_icon "$icon_src/light.png" "$contents/Resources/AppIcon.icns"
fi

chmod +x "$contents/MacOS/MHGLauncher"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
test ! -e "$contents/Resources/Backend/node"
test ! -e "$contents/Resources/GameRuntime"
"$root/scripts/sign-app.sh" "$app"
