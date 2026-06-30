#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/MHGLauncher.app"
contents="$app/Contents"
backend_dir="${MHG_DEBUG_BACKEND_DIR:-}"

if [[ -z "$backend_dir" ]]; then
  /bin/bash "$root/scripts/build-backend-debug.sh"
  backend_dir="$root/build/backend-debug/dist/MHGLauncherBackend"
fi
/bin/bash "$root/scripts/build-frontend.sh" debug

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources/Backend"

cp "$root/packaging/Info.plist" "$contents/Info.plist"
cp "$root/frontend/.build/arm64-apple-macosx/debug/MHGLauncher" \
  "$contents/MacOS/MHGLauncher"
cp -R "$backend_dir/app" "$contents/Resources/Backend/app"

chmod +x "$contents/MacOS/MHGLauncher"

plutil -lint "$contents/Info.plist"
file "$contents/MacOS/MHGLauncher" | grep -q 'arm64'
test ! -e "$contents/Resources/Backend/node"
test ! -e "$contents/Resources/GameRuntime"
