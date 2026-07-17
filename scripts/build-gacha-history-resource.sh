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
metadata_cache="$root/build/gacha-history-cache/Snap.Metadata"
metadata_root="${MHG_METADATA_ROOT:-}"
metadata_revision="${MHG_METADATA_REVISION:-main}"
if [[ -z "$metadata_root" ]]; then
  if [[ ! -d "$metadata_cache/.git" ]]; then
    git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/SnapHutaoRemasteringProject/Snap.Metadata.git "$metadata_cache"
    git -C "$metadata_cache" sparse-checkout set Genshin/CHS
  fi
  git -C "$metadata_cache" fetch --depth 1 origin "$metadata_revision"
  git -C "$metadata_cache" checkout --detach FETCH_HEAD
  metadata_root="$metadata_cache/Genshin/CHS"
  metadata_revision="$(git -C "$metadata_cache" rev-parse HEAD)"
fi
test -d "$metadata_root/Avatar"
test -f "$metadata_root/Weapon.json"
test -f "$metadata_root/Reliquary.json"
rm -rf "$output"
mkdir -p "$payload"
"$node_root/bin/node" "$root/scripts/build-gacha-history-resource.mjs" \
  "$root/backend/src/mhglauncher/data" "$metadata_root" "$payload" \
  "$root/build/gacha-history-cache/images" "$version" "$metadata_revision"
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
