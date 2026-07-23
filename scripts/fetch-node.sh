#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="v24.17.0"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform="darwin-arm64" ;;
  Linux-x86_64) platform="linux-x64" ;;
  Linux-aarch64|Linux-arm64) platform="linux-arm64" ;;
  *)
    printf '不支持的 Node.js 工具链平台：%s-%s\n' "$(uname -s)" "$(uname -m)" >&2
    exit 1
    ;;
esac
name="node-$version-$platform"
cache="$root/build/toolchain"
archive="$cache/$name.tar.gz"
destination="$cache/$name"

mkdir -p "$cache"
if [[ ! -x "$destination/bin/node" ]]; then
  curl --fail --location --silent --show-error \
    "https://nodejs.org/dist/$version/$name.tar.gz" --output "$archive"
  expected="$(curl --fail --location --silent --show-error \
    "https://nodejs.org/dist/$version/SHASUMS256.txt" | awk -v file="$name.tar.gz" '$2 == file {print $1}')"
  test -n "$expected"
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  else
    actual="$(sha256sum "$archive" | awk '{print $1}')"
  fi
  test "$actual" = "$expected"
  rm -rf "$destination"
  tar -xzf "$archive" -C "$cache"
fi

printf '%s\n' "$destination"
