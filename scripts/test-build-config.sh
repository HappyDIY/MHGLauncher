#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for script in build-app.sh build-backend.sh build-frontend.sh; do
  if "$root/scripts/$script" debug >/dev/null 2>&1; then
    printf '%s 仍接受 debug 构建配置。\n' "$script" >&2
    exit 1
  fi
done
test ! -e "$root/debug-app.command"
test ! -e "$root/scripts/build-backend-debug.sh"
test ! -e "$root/scripts/build-debug-app.sh"
bash -n "$root/scripts/sign-app.sh"
plutil -lint "$root/packaging/CodeSigning.plist" >/dev/null
grep -q 'scripts/sign-app.sh.*app' "$root/scripts/build-app.sh"
grep -q 'scripts/sign-app.sh.*cached_app' "$root/release-app.command"
grep -q -- '--timestamp=none' "$root/scripts/sign-app.sh"
grep -q 'CertificateSHA256' "$root/scripts/sign-app.sh"
grep -q 'MHG_ALLOW_AD_HOC_SIGNING' "$root/scripts/sign-app.sh"
grep -q 'MHG_ALLOW_AD_HOC_SIGNING.*"1"' \
  "$root/.github/workflows/quality-gate.yml"
if grep -q -- '--sign -' "$root/scripts/sign-app.sh"; then
  printf 'App 签名脚本不允许降级为 ad-hoc 签名。\n' >&2
  exit 1
fi

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
