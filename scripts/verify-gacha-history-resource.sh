#!/usr/bin/env bash
set -euo pipefail

manifest="${1:?缺少历史卡池资源清单}"
root="$(cd "$(dirname "$manifest")" && pwd)"
archive="$root/$(jq -r '.archive.url' "$manifest")"
jq -e '.schema_version == 1 and (.version | type) == "string"
  and (.archive.size | type) == "number"
  and (.archive.sha256 | test("^[0-9a-f]{64}$"))' "$manifest" >/dev/null
test -f "$archive"
test "$(stat -f '%z' "$archive")" = "$(jq -r '.archive.size' "$manifest")"
test "$(shasum -a 256 "$archive" | awk '{print $1}')" = "$(jq -r '.archive.sha256' "$manifest")"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
/usr/bin/unzip -q "$archive" -d "$stage"
jq -e --arg version "$(jq -r '.version' "$manifest")" \
  '.schema_version == 2 and .version == $version and (.events | length) > 200
  and (.items | length) > 300 and (.character_assets.avatars | length) > 100
  and (.character_assets.weapons | length) > 200
  and (.character_assets.reliquaries | length) > 800
  and (.character_assets.skills | length) > 300
  and (.character_assets.talents | length) > 600' \
  "$stage/catalog.json" >/dev/null
jq -r '.files | to_entries[] | [.key,.value] | @tsv' "$stage/mhg-manifest.json" |
while IFS=$'\t' read -r name expected; do
  test "$(shasum -a 256 "$stage/$name" | awk '{print $1}')" = "$expected"
done
printf '历史卡池资源校验通过：%s\n' "$(jq -r '.version' "$manifest")"
