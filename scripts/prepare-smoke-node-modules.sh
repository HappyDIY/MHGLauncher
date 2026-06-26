#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
hash="$(
  shasum -a 256 "$root/backend/package.json" "$root/backend/package-lock.json" |
    shasum -a 256 | awk '{print $1}'
)"
cache="$root/build/smoke-node-modules/$hash/node_modules"

if [[ ! -d "$cache" ]]; then
  stage="$(mktemp -d)"
  cleanup() { rm -rf "$stage"; }
  trap cleanup EXIT
  mkdir -p "$stage/app"
  cp "$root/backend/package.json" "$root/backend/package-lock.json" "$stage/app/"
  (
    cd "$stage/app"
    PATH="$node_root/bin:$PATH" npm ci --omit=dev --no-audit --no-fund
  )
  find "$stage/app/node_modules" \
    \( -name '*.md' -o -name '*.map' -o -name '*.tsbuildinfo' \) -type f -delete
  find "$stage/app/node_modules" \
    \( -type d -name test -o -type d -name tests -o -type d -name docs -o -type d -name examples \) \
    -prune -exec rm -rf {} +
  mkdir -p "$(dirname "$cache")"
  mv "$stage/app/node_modules" "$cache"
fi

printf '%s\n' "$cache"
