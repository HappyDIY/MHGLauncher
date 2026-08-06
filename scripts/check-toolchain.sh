#!/usr/bin/env bash
set -euo pipefail

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
  rustc="${RUSTC:-$(command -v rustc || true)}"
  if [[ -z "$rustc" && -x "$HOME/.cargo/bin/rustc" ]]; then
    rustc="$HOME/.cargo/bin/rustc"
  fi
  [[ -x "$rustc" ]] || {
    printf '缺少 Rust 编译器。\n' >&2
    exit 1
  }
  "$rustc" --print target-libdir --target x86_64-apple-darwin >/dev/null 2>&1 || {
    printf '缺少 Rust x86_64-apple-darwin 目标。\n' >&2
    exit 1
  }
fi

printf 'Swift 与 Rust 工具链检查通过。\n'
