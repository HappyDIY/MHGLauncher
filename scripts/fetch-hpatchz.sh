#!/usr/bin/env bash
set -euo pipefail

target="${1:?缺少 hpatchz 输出目录}"
version="4.12.2"
archive="hdiffpatch_v${version}_bin_macos.zip"
checksum="9b17de4ad88dd214e45943cb7fff76208f015e81d23f52cba083f9fde3de12d1"
cache="${TMPDIR:-/tmp}/mhglauncher-$archive"

if [[ ! -f "$cache" ]]; then
  curl -fsSL \
    "https://github.com/sisong/HDiffPatch/releases/download/v${version}/$archive" \
    -o "$cache"
fi

actual="$(shasum -a 256 "$cache" | awk '{print $1}')"
if [[ "$actual" != "$checksum" ]]; then
  rm -f "$cache"
  echo "hpatchz 校验失败" >&2
  exit 1
fi

mkdir -p "$target"
unzip -p "$cache" macos/hpatchz > "$target/hpatchz"
cp "$(cd "$(dirname "$0")/.." && pwd)/packaging/HDiffPatch-LICENSE.txt" "$target/"
chmod +x "$target/hpatchz"
file "$target/hpatchz" | grep -q 'arm64'
