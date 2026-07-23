#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if (( $# != 0 )); then
  printf '前端仅保留 release 构建，不再接受构建配置参数。\n' >&2
  exit 2
fi

cd "$root/frontend"
swift build -c release --arch arm64

binary="$root/frontend/.build/arm64-apple-macosx/release/MHGLauncher"
test -x "$binary"
file "$binary" | grep -q 'arm64'
