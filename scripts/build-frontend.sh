#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mode="${1:-release}"

case "$mode" in
  --debug|debug|development) configuration="debug" ;;
  --release|release|production) configuration="release" ;;
  *)
    printf '未知前端构建配置：%s\n' "$mode" >&2
    exit 2
    ;;
esac

cd "$root/frontend"
swift build -c "$configuration" --arch arm64

binary="$root/frontend/.build/arm64-apple-macosx/$configuration/MHGLauncher"
test -x "$binary"
file "$binary" | grep -q 'arm64'
