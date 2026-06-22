#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="v24.17.0"
name="node-$version-darwin-arm64"
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
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  test "$actual" = "$expected"
  rm -rf "$destination"
  tar -xzf "$archive" -C "$cache"
fi

printf '%s\n' "$destination"
