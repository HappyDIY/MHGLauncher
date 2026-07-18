#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

configure() {
  cp "$root/packaging/Info.plist" "$work/Info.plist"
  env -u MHG_CLOUD_BASE_URL swift "$root/scripts/configure-cloud-server.swift" \
    "$work/.env" "$work/Info.plist"
}

printf 'MHG_CLOUD_BASE_URL="https://cloud.example/api/"\n' > "$work/.env"
configure
test "$(plutil -extract MHGCloudBaseURL raw "$work/Info.plist")" = "https://cloud.example/api"

printf 'MHG_CLOUD_BASE_URL=http://cloud.example\n' > "$work/.env"
if configure >/dev/null 2>&1; then
  printf '远程 HTTP 云端地址未被拒绝\n' >&2
  exit 1
fi

printf 'MHG_CLOUD_BASE_URL=http://localhost:3333\n' > "$work/.env"
configure
test "$(plutil -extract MHGCloudBaseURL raw "$work/Info.plist")" = "http://localhost:3333"
