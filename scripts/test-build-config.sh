#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for script in build-app.sh build-frontend.sh; do
  if "$root/scripts/$script" debug >/dev/null 2>&1; then
    printf '%s 仍接受 debug 构建配置。\n' "$script" >&2
    exit 1
  fi
done
test ! -e "$root/debug-app.command"
grep -q -- '--strict --verbose=2' "$root/scripts/sign-app.sh"
test ! -e "$root/scripts/build-debug-app.sh"
(cd "$root/frontend/Vendor/SwiftLibgit2Base" && shasum -a 256 -c SHA256SUMS >/dev/null)
grep -q 'exact: "7.10.0"' "$root/frontend/Package.swift"
grep -q 'exact: "1.38.1"' "$root/frontend/Package.swift"
test -f "$root/frontend/Vendor/SwiftLibgit2Base/LICENSE.txt"
test -f "$root/frontend/Vendor/SwiftLibgit2Base/Licenses/libgit2-LICENSE.txt"
bash -n "$root/scripts/sign-app.sh"
plutil -lint "$root/packaging/CodeSigning.plist" >/dev/null
grep -q 'scripts/sign-app.sh.*app' "$root/scripts/build-app.sh"
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
