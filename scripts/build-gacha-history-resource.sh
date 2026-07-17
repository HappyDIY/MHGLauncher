#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?缺少历史卡池资源版本，例如 2026.07.18}"
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || {
  printf '历史卡池资源版本格式无效。\n' >&2
  exit 2
}
node_root="$("$root/scripts/fetch-node.sh")"
output="$root/build/gacha-history-assets/$version"
payload="$output/payload"
archive="$output/gacha-history.zip"
rm -rf "$output"
mkdir -p "$payload"
"$node_root/bin/node" "$root/scripts/build-gacha-history-resource.mjs" \
  "$root/backend/src/mhglauncher/data" "$payload" \
  "$root/build/gacha-history-cache/images" "$version"
find "$payload" -exec touch -t 198001010000 {} +
(
  cd "$payload"
  find . -type f -print | LC_ALL=C sort | /usr/bin/zip -X -q "$archive" -@
)
size="$(stat -f '%z' "$archive")"
sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
"$node_root/bin/node" -e 'const fs=require("fs"); const [path,version,size,sha]=process.argv.slice(1); fs.writeFileSync(path, JSON.stringify({schema_version:1,version,archive:{url:"gacha-history.zip",size:Number(size),sha256:sha}})+"\n")' \
  "$output/gacha-history-manifest.json" "$version" "$size" "$sha256"
printf '%s\n' "$output/gacha-history-manifest.json"
