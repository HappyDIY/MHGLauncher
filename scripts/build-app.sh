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

icon_source="$root/frontend/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$icon_source/light.png" ]; then
  iconset="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    half=$((size / 2))
    twosize=$((size * 2))
    sips -z $size $size "$icon_source/light.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $size $size "$icon_source/dark.png" --out "$iconset/icon_${size}x${size}~dark.png" >/dev/null
    sips -z $twosize $twosize "$icon_source/light.png" --out "$iconset/icon_${half}x${half}@2x.png" >/dev/null
    sips -z $twosize $twosize "$icon_source/dark.png" --out "$iconset/icon_${half}x${half}@2x~dark.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$iconset")"
fi

chmod +x "$contents/MacOS/MHGLauncher"
chmod +x "$contents/Resources/Backend/MHGLauncherBackend/MHGLauncherBackend"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
file "$contents/Resources/Backend/MHGLauncherBackend/MHGLauncherBackend" \
  | grep -q 'arm64'
