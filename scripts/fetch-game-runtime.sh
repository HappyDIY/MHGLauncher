#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$root/build/game-runtime}"
cache="${MHG_SOURCE_CACHE:-$HOME/Library/Caches/MHGLauncher/sources}"
source_lock="$root/packaging/game-runtime-source-lock.json"
wine_url="$(jq -er '.wineArtifact.url' "$source_lock")"
wine_sha="$(jq -er '.wineArtifact.sha256' "$source_lock")"
dxmt_url="https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
dxmt_sha="8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
dxmt_license_url="https://raw.githubusercontent.com/3Shain/dxmt/v0.80/LICENSE"
dxmt_license_sha="6b928413c6308c106f3e0080bd94b6427b56d587d400fd40e6cbfbab7d9c4ae1"

fetch() {
  local url="$1" sha="$2" destination="$3"
  if [[ ! -f "$destination" ]] || [[ "$(shasum -a 256 "$destination" | awk '{print $1}')" != "$sha" ]]; then
    rm -f "$destination.tmp"
    curl --fail --location --retry 3 --output "$destination.tmp" "$url"
    [[ "$(shasum -a 256 "$destination.tmp" | awk '{print $1}')" == "$sha" ]]
    mv "$destination.tmp" "$destination"
  fi
}

mkdir -p "$cache"
wine_archive="$cache/wine-crossover-11.0-1-osx64-signed.tar.xz"
dxmt_archive="$cache/dxmt-v0.80-builtin.tar.gz"
fetch "$wine_url" "$wine_sha" "$wine_archive"
fetch "$dxmt_url" "$dxmt_sha" "$dxmt_archive"
fetch "$dxmt_license_url" "$dxmt_license_sha" "$cache/DXMT-LICENSE.txt"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/wine" "$stage/dxmt"
while IFS= read -r source; do
  source_id="$(jq -r '.id' <<<"$source")"
  source_url="$(jq -r '.url' <<<"$source")"
  source_sha="$(jq -r '.sha256' <<<"$source")"
  source_archive="$cache/$(jq -r '.cacheFile' <<<"$source")"
  source_listing="$stage/$source_id.list"
  fetch "$source_url" "$source_sha" "$source_archive"
  tar -tf "$source_archive" >"$source_listing"
  while IFS= read -r required; do
    grep -Fxq "$required" "$source_listing"
  done < <(jq -r '.requiredPaths[]' <<<"$source")
done < <(jq -c '.correspondingSources[]' "$source_lock")
wine_source="$cache/$(jq -r '.correspondingSources[] | select(.id == "codeweavers-wine") | .cacheFile' "$source_lock")"
[[ "$(tar -xOf "$wine_source" sources/wine/VERSION)" == "Wine version 11.0" ]]
tar -xf "$wine_archive" -C "$stage/wine"
tar -xf "$dxmt_archive" -C "$stage/dxmt"
wine_binary="$(find "$stage/wine" -type f -path '*/bin/wine' -print -quit)"
[[ -n "$wine_binary" ]]
wine_root="$(dirname "$(dirname "$wine_binary")")"

rm -rf "$output"
mkdir -p "$output/bin" "$output/lib" "$output/assets" "$output/licenses"
cp -R "$wine_root" "$output/wine"
for architecture in x86_64-unix x86_64-windows; do
  source_dir="$(find "$stage/dxmt" -type d -name "$architecture" -print -quit)"
  [[ -n "$source_dir" ]]
  mkdir -p "$output/wine/lib/wine/$architecture"
  cp -R "$source_dir/." "$output/wine/lib/wine/$architecture/"
done

xcrun clang -dynamiclib -arch x86_64 -O2 "$root/runtime/dns-gate.c" -lresolv -o "$output/lib/libmhg_dns_gate.dylib"
xcrun swiftc -O "$root/runtime/window-probe.swift" -o "$output/bin/mhg-window-probe"

dll_source="${MHG_MHYPBASE_SOURCE:-$HOME/Downloads/mhypbase.dll}"
[[ -f "$dll_source" ]]
[[ "$(stat -f %z "$dll_source")" == "24056296" ]]
[[ "$(md5 -q "$dll_source")" == "dcb1b134e0e8bc3bb292eb41d17f5788" ]]
[[ "$(shasum -a 256 "$dll_source" | awk '{print $1}')" == "941558c9761eadecfebe13f5aeef131e35abf11370e0eb798cbc2d1e356f04f1" ]]
install -m 0644 "$dll_source" "$output/assets/mhypbase.dll"

cp "$cache/DXMT-LICENSE.txt" "$output/licenses/DXMT-LICENSE.txt"
cp "$root/packaging/GAME_RUNTIME_NOTICES.md" "$output/licenses/THIRD_PARTY_NOTICES.md"
cp "$source_lock" "$output/licenses/GAME_RUNTIME_SOURCE_LOCK.json"
chmod +x "$output/wine/bin/"* "$output/bin/mhg-window-probe"
tar -xOf "$wine_source" sources/wine/COPYING.LIB >"$output/licenses/Wine-LGPL-2.1.txt"
[[ "$("$output/wine/bin/wine" --version)" == "wine-11.0" ]]
grep -R -a -q 'WINEMSYNC' "$output/wine/lib/wine"
printf '%s\n' "游戏运行时已生成：$output"
