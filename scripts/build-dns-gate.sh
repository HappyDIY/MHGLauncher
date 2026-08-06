#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:?请提供域名门控动态库输出路径}"
rustc="${RUSTC:-$(command -v rustc || true)}"
if [[ -z "$rustc" && -x "$HOME/.cargo/bin/rustc" ]]; then
  rustc="$HOME/.cargo/bin/rustc"
fi
[[ -x "$rustc" ]] || {
  printf '缺少 Rust 编译器。\n' >&2
  exit 1
}

mkdir -p "$(dirname "$output")"
"$rustc" \
  --crate-type cdylib \
  --target x86_64-apple-darwin \
  -C opt-level=2 \
  -C panic=abort \
  -C strip=symbols \
  "$root/runtime/dns-gate.rs" \
  -o "$output"
