#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
keychain="${MHG_LOCAL_SIGNING_KEYCHAIN:-}"

if (( $# != 1 )) || [[ ! -d "$1/Contents" ]]; then
  printf '用法：%s <App 路径>\n' "$0" >&2
  exit 2
fi

app="$1"
identity="${MHG_CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$("$root/scripts/ensure-local-signing-identity.sh")"
fi

sign_args=(--force --sign "$identity" --timestamp=none)
if [[ -n "$keychain" ]]; then
  sign_args+=(--keychain "$keychain")
fi

codesign "${sign_args[@]}" "$app"
codesign --verify --deep --verbose=2 "$app"
printf '已使用本地身份签名：%s\n' "$identity"
