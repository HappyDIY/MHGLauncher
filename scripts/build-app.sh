#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
contents="$app/Contents"
mode="${1:-development}"

"$root/scripts/build-backend.sh" "$mode"
"$root/scripts/build-frontend.sh"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources/Backend"

cp "$root/packaging/Info.plist" "$contents/Info.plist"
cp "$root/frontend/.build/arm64-apple-macosx/release/MHGLauncher" \
  "$contents/MacOS/MHGLauncher"
cp -R "$root/build/backend/dist/MHGLauncherBackend" \
  "$contents/Resources/Backend/MHGLauncherBackend"

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
chmod +x "$contents/Resources/Backend/MHGLauncherBackend/MHGLauncherBackend"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
file "$contents/Resources/Backend/MHGLauncherBackend/node" \
  | grep -q 'arm64'
