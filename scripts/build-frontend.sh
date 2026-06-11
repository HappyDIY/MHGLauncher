#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$root/frontend"
swift build -c release --arch arm64

binary="$root/frontend/.build/arm64-apple-macosx/release/MHGLauncher"
test -x "$binary"
file "$binary" | grep -q 'arm64'

