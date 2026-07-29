#!/usr/bin/env bash
set -euo pipefail

identity_name="${MHG_LOCAL_SIGNING_IDENTITY_NAME:-MHGLauncher Local Development}"
keychain="${MHG_LOCAL_SIGNING_KEYCHAIN:-}"

if (( $# != 0 )); then
  printf '本地签名身份脚本不接受参数。\n' >&2
  exit 2
fi

if [[ -z "$keychain" ]]; then
  keychain="$(security default-keychain -d user | tr -d '"[:space:]')"
fi
test -n "$keychain"

find_identity() {
  security find-identity -v -p codesigning "$keychain" 2>/dev/null |
    awk -v name="$identity_name" \
      'index($0, "\"" name "\"") { print $2; exit }'
}

identity="$(find_identity)"
if [[ -n "$identity" ]]; then
  printf '%s\n' "$identity"
  exit 0
fi

command -v openssl >/dev/null
printf '首次构建：正在钥匙串中创建本地自签名身份“%s”...\n' \
  "$identity_name" >&2
printf 'macOS 可能仅在本次创建时要求确认钥匙串访问。\n' >&2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
umask 077
password="$(openssl rand -hex 24)"

openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -subj "/CN=$identity_name/O=MHGLauncher Local Development" \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=critical,codeSigning' \
  -keyout "$work/private-key.pem" \
  -out "$work/certificate.pem" >/dev/null 2>&1
openssl pkcs12 -export -legacy \
  -inkey "$work/private-key.pem" \
  -in "$work/certificate.pem" \
  -name "$identity_name" \
  -passout "pass:$password" \
  -out "$work/identity.p12"

security import "$work/identity.p12" \
  -k "$keychain" -f pkcs12 -P "$password" \
  -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$keychain" "$work/certificate.pem"

identity="$(find_identity)"
if [[ -z "$identity" ]]; then
  printf '本地自签名身份创建后仍不可用于代码签名。\n' >&2
  exit 1
fi
printf '%s\n' "$identity"
