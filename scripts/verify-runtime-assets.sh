#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
asset_dir="${1:?缺少运行时资产目录}"
scope="${2:-all}"
manifest="$asset_dir/runtime-manifest.json"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/packaging/Info.plist")"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
size() { stat -f %z "$1"; }
fail() { printf '%s\n' "$1" >&2; exit 1; }

test -f "$manifest" || fail "缺少 runtime-manifest.json。"
jq -e --arg version "$app_version" '
  .schemaVersion == 2 and .tag == ("v" + $version) and .appVersion == $version and
  .platform == "darwin" and .hostArchitecture == "arm64" and .guestArchitecture == "x86_64" and
  (.requiredPaths | type == "array" and length > 0 and all(type == "string" and length > 0)) and
  (.components | type == "array" and length > 0) and
  ([.components[].id] | length == (unique | length)) and
  all(.components[]; (.id | test("^[a-z0-9_-]+$")) and (.kind == "core" or .kind == "game") and
    ((.version | type) == "string" and (.version | length) > 0) and (.file | test("^[A-Za-z0-9._+-]+$")) and
    (.installRoot | test("^[A-Za-z0-9._()/-]+$") and (contains("..") | not)) and
    ((.size | type) == "number" and .size > 0) and (.sha256 | test("^[0-9a-f]{64}$")))' "$manifest" >/dev/null \
  || fail "运行时 manifest v2 契约无效。"

expected_core='{"node":"node","node_modules":"backend/app/node_modules","hpatchz":"backend"}'
expected_all='{"node":"node","node_modules":"backend/app/node_modules","hpatchz":"backend","host":"game-runtime","wine":"game-runtime/wine","msync":"game-runtime/wine","dxmt":"game-runtime/wine/lib/wine","mhypbase":"game-runtime/assets"}'
expected="$expected_all"; [[ "$scope" == "core" ]] && expected="$expected_core"
jq -e --argjson expected "$expected" '(.components | map({key:.id,value:.installRoot}) | from_entries) as $actual |
  all($expected | to_entries[]; $actual[.key] == .value) and
  (if ($expected | length) == 3 then ([.components[] | select(.kind == "core") | .id] | sort) == (["hpatchz","node","node_modules"] | sort) else ($actual | length) == ($expected | length) end)' \
  "$manifest" >/dev/null || fail "运行时组件集合或安装根目录无效。"

: >"$stage/referenced"
while IFS= read -r component; do
  file="$(jq -r '.file' <<<"$component")"; expected_size="$(jq -r '.size' <<<"$component")"; expected_sha="$(jq -r '.sha256' <<<"$component")"
  parts="$(jq -r '.parts // [] | length' <<<"$component")"
  if (( parts > 0 )); then
    combined="$stage/$file"; : >"$combined"
    while IFS= read -r part; do
      name="$(jq -r '.file' <<<"$part")"; path="$asset_dir/$name"; echo "$name" >>"$stage/referenced"
      test -f "$path" || fail "缺少运行时分片：$name"
      test "$(size "$path")" = "$(jq -r '.size' <<<"$part")" || fail "运行时分片大小不匹配：$name"
      test "$(sha256 "$path")" = "$(jq -r '.sha256' <<<"$part")" || fail "运行时分片摘要不匹配：$name"
      cat "$path" >>"$combined"
    done < <(jq -c '.parts[]' <<<"$component")
    path="$combined"
  else
    path="$asset_dir/$file"; echo "$file" >>"$stage/referenced"; test -f "$path" || fail "缺少运行时资产：$file"
  fi
  test "$(size "$path")" = "$expected_size" || fail "运行时资产大小不匹配：$file"
  test "$(sha256 "$path")" = "$expected_sha" || fail "运行时资产摘要不匹配：$file"
done < <(jq -c '.components[]' "$manifest")

while IFS= read -r path; do
  name="$(basename "$path")"
  [[ "$name" == "runtime-manifest.json" || "$name" == "runtime-manifest.json.sig" ]] && continue
  grep -Fxq "$name" "$stage/referenced" || fail "发现 manifest 未引用的资产：$name"
done < <(find "$asset_dir" -maxdepth 1 -type f)

if [[ "${MHG_REQUIRE_RUNTIME_SIGNATURE:-0}" == 1 ]]; then
  key="${MHG_RUNTIME_MANIFEST_SIGNING_KEY:-$HOME/.config/MHGLauncher/runtime-manifest-ed25519.pem}"
  test -f "$key" || fail "缺少运行时 manifest 签名密钥。"
  test -f "$manifest.sig" || fail "缺少运行时 manifest 签名。"
  openssl pkey -in "$key" -pubout -out "$stage/public.pem"
  openssl pkeyutl -verify -rawin -pubin -inkey "$stage/public.pem" -in "$manifest" -sigfile "$manifest.sig" >/dev/null \
    || fail "运行时 manifest 签名无效。"
fi

printf '运行时资产摘要与组件契约验证通过：%s\n' "$asset_dir"
