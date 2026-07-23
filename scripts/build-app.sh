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

icon_src="$root/frontend/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$icon_src/light.png" ]; then
  build_icon "$icon_src/light.png" "$contents/Resources/AppIcon.icns"
  export MHG_APP_PATH="$app"
  swift - <<'SWIFTEOF'
import Cocoa
let appPath = ProcessInfo.processInfo.environment["MHG_APP_PATH"] ?? ""
guard !appPath.isEmpty,
      let icon = NSImage(contentsOf: URL(fileURLWithPath: "\(appPath)/Contents/Resources/AppIcon.icns"))
else { exit(1) }
NSWorkspace.shared.setIcon(icon, forFile: appPath, options: [])
SWIFTEOF
fi

chmod +x "$contents/MacOS/MHGLauncher"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
test ! -e "$contents/Resources/Backend/node"
test ! -e "$contents/Resources/GameRuntime"
