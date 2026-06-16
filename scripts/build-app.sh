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
  local light="$1" dark="$2" out_dir="$3"
  local work="$(mktemp -d)"
  local xcassets="$work/Assets.xcassets"
  local iconset="$xcassets/AppIcon.appiconset"
  mkdir -p "$iconset"

  for size in 16 32 128 256 512; do
    local half=$((size / 2))
    local twosize=$((size * 2))
    sips -z $size $size "$light" --out "$iconset/icon_${size}x${size}.png" >/dev/null 2>&1
    sips -z $size $size "$dark" --out "$iconset/icon_${size}x${size}~dark.png" >/dev/null 2>&1
    sips -z $twosize $twosize "$light" --out "$iconset/icon_${half}x${half}@2x.png" >/dev/null 2>&1
    sips -z $twosize $twosize "$dark" --out "$iconset/icon_${half}x${half}@2x~dark.png" >/dev/null 2>&1
  done

  cat > "$xcassets/Contents.json" << 'XCEOF'
{"info":{"author":"xcode","version":1}}
XCEOF

  cat > "$iconset/Contents.json" << 'ICEOF'
{
  "images" : [
    {"filename":"icon_16x16.png","idiom":"mac","scale":"1x","size":"16x16"},
    {"filename":"icon_8x8@2x.png","idiom":"mac","scale":"2x","size":"16x16"},
    {"filename":"icon_32x32.png","idiom":"mac","scale":"1x","size":"32x32"},
    {"filename":"icon_16x16@2x.png","idiom":"mac","scale":"2x","size":"32x32"},
    {"filename":"icon_128x128.png","idiom":"mac","scale":"1x","size":"128x128"},
    {"filename":"icon_64x64@2x.png","idiom":"mac","scale":"2x","size":"128x128"},
    {"filename":"icon_256x256.png","idiom":"mac","scale":"1x","size":"256x256"},
    {"filename":"icon_128x128@2x.png","idiom":"mac","scale":"2x","size":"256x256"},
    {"filename":"icon_512x512.png","idiom":"mac","scale":"1x","size":"512x512"},
    {"filename":"icon_256x256@2x.png","idiom":"mac","scale":"2x","size":"512x512"},
    {"filename":"icon_16x16~dark.png","idiom":"mac","scale":"1x","size":"16x16",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_8x8@2x~dark.png","idiom":"mac","scale":"2x","size":"16x16",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_32x32~dark.png","idiom":"mac","scale":"1x","size":"32x32",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_16x16@2x~dark.png","idiom":"mac","scale":"2x","size":"32x32",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_128x128~dark.png","idiom":"mac","scale":"1x","size":"128x128",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_64x64@2x~dark.png","idiom":"mac","scale":"2x","size":"128x128",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_256x256~dark.png","idiom":"mac","scale":"1x","size":"256x256",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_128x128@2x~dark.png","idiom":"mac","scale":"2x","size":"256x256",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_512x512~dark.png","idiom":"mac","scale":"1x","size":"512x512",
     "appearances":[{"appearance":"luminosity","value":"dark"}]},
    {"filename":"icon_256x256@2x~dark.png","idiom":"mac","scale":"2x","size":"512x512",
     "appearances":[{"appearance":"luminosity","value":"dark"}]}
  ],
  "info" : {"author" : "xcode", "version" : 1}
}
ICEOF

  local compile_dir="$(mktemp -d)"
  /Applications/Xcode.app/Contents/Developer/usr/bin/actool "$xcassets" \
    --compile "$compile_dir" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$compile_dir/partial.plist" >/dev/null 2>&1

  if [ -f "$compile_dir/AppIcon.icns" ]; then
    cp "$compile_dir/AppIcon.icns" "$out_dir/AppIcon.icns"
  fi
  if [ -f "$compile_dir/Assets.car" ]; then
    cp "$compile_dir/Assets.car" "$out_dir/Assets.car"
  fi

  rm -rf "$work" "$compile_dir"
}

icon_src="$root/frontend/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -f "$icon_src/light.png" ] && [ -f "$icon_src/dark.png" ]; then
  build_icon "$icon_src/light.png" "$icon_src/dark.png" "$contents/Resources"
fi

chmod +x "$contents/MacOS/MHGLauncher"
chmod +x "$contents/Resources/Backend/MHGLauncherBackend/MHGLauncherBackend"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
file "$contents/Resources/Backend/MHGLauncherBackend/MHGLauncherBackend" \
  | grep -q 'arm64'
