#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?缺少版本 tag，例如 v0.1.0}"
out="$root/build/runtime-assets/$tag"
stage="$(mktemp -d)"
asset_base="https://github.com/HappyDIY/MHGLauncher/releases/download/$tag"
split_bytes="${MHG_RELEASE_ASSET_SPLIT_BYTES:-1900m}"
component_file="$stage/components.jsonl"
signing_key="${MHG_RUNTIME_MANIFEST_SIGNING_KEY:-$HOME/.config/MHGLauncher/runtime-manifest-ed25519.pem}"
signing_public_key="DvswOM/iIXbp+jB12AmqWUqU/gYv7xG7RYWu7dIa+Sk="
dxmt_url="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
dxmt_sha="8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

test -f "$signing_key" || { printf '未找到运行时清单 Ed25519 私钥。\n' >&2; exit 1; }
test "$(openssl pkey -in "$signing_key" -pubout -outform DER | tail -c 32 | base64)" = "$signing_public_key" \
  || { printf '运行时清单 Ed25519 私钥与应用内公钥不匹配。\n' >&2; exit 1; }

json_string() { jq -Rn --arg value "$1" '$value'; }

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

size() { stat -f %z "$1"; }

sign_manifest() {
  [[ -f "$signing_key" ]]
  openssl pkeyutl -sign -rawin -inkey "$signing_key" -in "$1" -out "$2"
  test "$(size "$2")" = 64
}

fetch() {
  local url="$1" sha="$2" destination="$3"
  if [[ ! -f "$destination" ]] || [[ "$(sha256 "$destination")" != "$sha" ]]; then
    rm -f "$destination.tmp"
    curl --fail --location --retry 3 --output "$destination.tmp" "$url"
    [[ "$(sha256 "$destination.tmp")" == "$sha" ]]
    mv "$destination.tmp" "$destination"
  fi
}

archive_component() {
  local id="$1" kind="$2" version="$3" install_root="$4" source="$5"
  local file="$id-$version.tar.gz"
  local archive="$out/$file"
  tar --format=pax -C "$source" -czf "$archive" .
  local total_size total_sha
  total_size="$(size "$archive")"
  total_sha="$(sha256 "$archive")"
  if (( total_size > 1900 * 1024 * 1024 )); then
    rm -f "$archive".part*
    split -b "$split_bytes" -d -a 2 "$archive" "$archive.part"
    rm -f "$archive"
    local parts="[]"
    local part
    for part in "$archive".part*; do
      parts="$(jq -c \
        --arg file "$(basename "$part")" \
        --argjson size "$(size "$part")" \
        --arg sha256 "$(sha256 "$part")" \
        '. + [{file:$file,size:$size,sha256:$sha256}]' <<<"$parts")"
    done
    jq -nc \
      --arg id "$id" --arg kind "$kind" --arg version "$version" \
      --arg file "$file" --arg installRoot "$install_root" \
      --argjson size "$total_size" --arg sha256 "$total_sha" --argjson parts "$parts" \
      '{id:$id,kind:$kind,version:$version,file:$file,size:$size,sha256:$sha256,installRoot:$installRoot,parts:$parts}' \
      >>"$component_file"
  else
    jq -nc \
      --arg id "$id" --arg kind "$kind" --arg version "$version" \
      --arg file "$file" --arg installRoot "$install_root" \
      --argjson size "$total_size" --arg sha256 "$total_sha" \
      '{id:$id,kind:$kind,version:$version,file:$file,size:$size,sha256:$sha256,installRoot:$installRoot}' \
      >>"$component_file"
  fi
}

rm -rf "$out"
mkdir -p "$out"
: >"$component_file"

"$root/scripts/build-backend.sh" release
node_root="$("$root/scripts/fetch-node.sh")"

backend_stage="$stage/backend"
mkdir -p "$backend_stage/backend/app"
cp -R "$root/build/backend/dist/MHGLauncherBackend/app/." "$backend_stage/backend/app/"
(
  cd "$backend_stage/backend/app"
  PATH="$node_root/bin:$PATH" npm ci --omit=dev
)
find "$backend_stage/backend/app/node_modules" \
  \( -name '*.md' -o -name '*.map' -o -name '*.tsbuildinfo' \) -type f -delete
find "$backend_stage/backend/app/node_modules" \
  \( -type d -name test -o -type d -name tests -o -type d -name docs -o -type d -name examples \) \
  -prune -exec rm -rf {} +

node_stage="$stage/node"
mkdir -p "$node_stage/node/bin"
cp "$node_root/bin/node" "$node_stage/node/bin/node"
chmod +x "$node_stage/node/bin/node"
archive_component node core 24.17.0 node "$node_stage"

modules_stage="$stage/node_modules"
mkdir -p "$modules_stage/backend/app"
mv "$backend_stage/backend/app/node_modules" "$modules_stage/backend/app/node_modules"
archive_component node_modules core "$(jq -r '.version' "$root/backend/package-lock.json")" \
  backend/app/node_modules "$modules_stage"

hpatch_stage="$stage/hpatchz"
mkdir -p "$hpatch_stage/backend"
"$root/scripts/fetch-hpatchz.sh" "$hpatch_stage/backend"
archive_component hpatchz core 4.12.2 backend "$hpatch_stage"

runtime_stage="$stage/runtime"
"$root/scripts/fetch-game-runtime.sh" "$runtime_stage/full"
dxmt_archive="$stage/dxmt-v0.80-builtin.tar.gz"
fetch "$dxmt_url" "$dxmt_sha" "$dxmt_archive"
dxmt_source="$stage/dxmt-source"
mkdir -p "$dxmt_source"
tar -xf "$dxmt_archive" -C "$dxmt_source"

host_stage="$stage/host"
mkdir -p "$host_stage/game-runtime/bin" "$host_stage/game-runtime/lib" "$host_stage/game-runtime/licenses"
cp "$runtime_stage/full/bin/mhg-window-probe" "$host_stage/game-runtime/bin/"
cp "$runtime_stage/full/lib/libmhg_dns_gate.dylib" "$host_stage/game-runtime/lib/"
cp -R "$runtime_stage/full/licenses/." "$host_stage/game-runtime/licenses/"
archive_component host game "$tag" game-runtime "$host_stage"

wine_stage="$stage/wine"
mkdir -p "$wine_stage/game-runtime"
cp -R "$runtime_stage/full/wine" "$wine_stage/game-runtime/wine"
rm -f "$wine_stage/game-runtime/wine/bin/wineserver"
rm -f "$wine_stage/game-runtime/wine/lib/wine/x86_64-unix/ntdll.so"
for architecture in x86_64-unix x86_64-windows; do
  dxmt_dir="$(find "$dxmt_source" -type d -name "$architecture" -print -quit)"
  [[ -n "$dxmt_dir" ]]
  while IFS= read -r file; do
    relative="${file#$dxmt_dir/}"
    rm -f "$wine_stage/game-runtime/wine/lib/wine/$architecture/$relative"
  done < <(find "$dxmt_dir" -type f)
done
find "$wine_stage/game-runtime/wine" -name .DS_Store -delete
archive_component wine game wine-crossover-11.0-1 game-runtime/wine "$wine_stage"

msync_stage="$stage/msync"
mkdir -p "$msync_stage/game-runtime/wine/bin" "$msync_stage/game-runtime/wine/lib/wine/x86_64-unix"
cp "$runtime_stage/full/wine/bin/wineserver" "$msync_stage/game-runtime/wine/bin/"
cp "$runtime_stage/full/wine/lib/wine/x86_64-unix/ntdll.so" \
  "$msync_stage/game-runtime/wine/lib/wine/x86_64-unix/"
grep -R -a -q 'WINEMSYNC' "$msync_stage/game-runtime/wine"
archive_component msync game wine-crossover-11.0-1-msync game-runtime/wine "$msync_stage"

dxmt_stage="$stage/dxmt"
mkdir -p "$dxmt_stage/game-runtime/wine/lib/wine"
for architecture in x86_64-unix x86_64-windows; do
  dxmt_dir="$(find "$dxmt_source" -type d -name "$architecture" -print -quit)"
  [[ -n "$dxmt_dir" ]]
  mkdir -p "$dxmt_stage/game-runtime/wine/lib/wine/$architecture"
  cp -R "$dxmt_dir/." "$dxmt_stage/game-runtime/wine/lib/wine/$architecture/"
done
archive_component dxmt game v0.80 game-runtime/wine/lib/wine "$dxmt_stage"

mhyp_stage="$stage/mhypbase"
mkdir -p "$mhyp_stage/game-runtime/assets" "$mhyp_stage/game-runtime/licenses"
cp "$runtime_stage/full/assets/mhypbase.dll" "$mhyp_stage/game-runtime/assets/"
printf '%s\n' \
  'mhypbase.dll 已由维护者确认具备随 MHGLauncher 公开 Release 资产分发的授权。' \
  "SHA-256: $(sha256 "$runtime_stage/full/assets/mhypbase.dll")" \
  >"$mhyp_stage/game-runtime/licenses/MHYPBASE-NOTICE.txt"
archive_component mhypbase game 1 game-runtime/assets "$mhyp_stage"

jq -s \
  --arg tag "$tag" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg assetBaseURL "$asset_base" \
  '{schemaVersion:1,tag:$tag,generatedAt:$generatedAt,assetBaseURL:$assetBaseURL,components:.}' \
  "$component_file" >"$out/runtime-manifest.json"
sign_manifest "$out/runtime-manifest.json" "$out/runtime-manifest.json.sig"

printf '运行时发布资产已生成：%s\n' "$out"
