#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
keychain="${MHG_LOCAL_SIGNING_KEYCHAIN:-}"
allow_ad_hoc="${MHG_ALLOW_AD_HOC_SIGNING:-0}"
config="$root/packaging/CodeSigning.plist"

if (( $# != 1 )) || [[ ! -d "$1/Contents" ]]; then
  printf '用法：%s <App 路径>\n' "$0" >&2
  exit 2
fi

app="$1"
if [[ "$allow_ad_hoc" == "1" ]]; then
  ad_hoc_identity="-"
  codesign --force --sign "$ad_hoc_identity" --timestamp=none "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  printf '已使用 CI 专用 ad-hoc 签名。\n'
  exit 0
fi

certificate_name="$(plutil -extract CertificateName raw "$config")"
identity="$(plutil -extract CertificateSHA1 raw "$config")"
expected_sha256="$(plutil -extract CertificateSHA256 raw "$config")"

sign_args=(--force --sign "$identity" --timestamp=none)
if [[ -n "$keychain" ]]; then
  sign_args+=(--keychain "$keychain")
  identity_list="$(security find-identity -v -p codesigning "$keychain")"
else
  identity_list="$(security find-identity -v -p codesigning)"
fi

if ! printf '%s\n' "$identity_list" |
  awk -v hash="$identity" -v name="$certificate_name" \
    '$2 == hash && index($0, "\"" name "\"") { found = 1 }
     END { exit !found }'; then
  printf '缺少项目统一签名证书：%s（%s）。\n' \
    "$certificate_name" "$identity" >&2
  printf '请先将包含私钥的统一证书导入当前用户钥匙串。\n' >&2
  exit 1
fi

codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
codesign -d --extract-certificates="$work/certificate" "$app"
actual_sha256="$(openssl x509 -inform DER -in "$work/certificate0" \
  -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  printf 'App 签名证书指纹与项目统一证书不一致。\n' >&2
  exit 1
fi
printf '已使用项目统一证书签名：%s（%s）\n' \
  "$certificate_name" "$identity"
