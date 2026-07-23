#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
node_version="$("$node_root/bin/node" --version)"

if [[ "$node_version" != "v24.17.0" ]]; then
  printf 'Node.js 版本不匹配：期望 v24.17.0，实际 %s\n' "$node_version" >&2
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  [[ "$(uname -m)" == "arm64" ]] || {
    printf 'macOS 启动器测试必须运行在 arm64。\n' >&2
    exit 1
  }
  sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
  swift_version="$(xcrun swift --version | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p')"
  [[ "${sdk_version%%.*}" -ge 26 ]] || {
    printf 'macOS SDK 版本过低：%s\n' "$sdk_version" >&2
    exit 1
  }
  swift_major="${swift_version%%.*}"
  swift_minor="${swift_version#*.}"
  swift_minor="${swift_minor%%.*}"
  if (( swift_major < 6 || (swift_major == 6 && swift_minor < 2) )); then
    printf 'Swift 版本过低：%s\n' "$swift_version" >&2
    exit 1
  fi
fi

printf '工具链检查通过：Node.js %s。\n' "$node_version"
