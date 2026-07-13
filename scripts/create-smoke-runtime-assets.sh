#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?缺少输出目录}"
tag="${2:-v0.1.0}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/packaging/Info.plist")"
[[ "$tag" == "v$app_version" ]] || { printf 'Smoke runtime tag 与 App 版本不一致。\n' >&2; exit 2; }
stage="$(mktemp -d)"
component_file="$stage/components.jsonl"

cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
size() { stat -f %z "$1"; }

archive_component() {
  local id="$1" version="$2" install_root="$3" source="$4"
  local file="$id-$version.tar.gz"
  tar --format=pax --dereference -C "$source" -czf "$out/$file" .
  jq -nc \
    --arg id "$id" --arg version "$version" --arg file "$file" \
    --arg installRoot "$install_root" --argjson size "$(size "$out/$file")" \
    --arg sha256 "$(sha256 "$out/$file")" \
    '{id:$id,kind:"core",version:$version,file:$file,size:$size,sha256:$sha256,installRoot:$installRoot}' \
    >>"$component_file"
}

rm -rf "$out"
mkdir -p "$out"
: >"$component_file"

node_root="$("$root/scripts/fetch-node.sh")"
node_stage="$stage/node"
mkdir -p "$node_stage/node/bin"
cp "$node_root/bin/node" "$node_stage/node/bin/node"
chmod +x "$node_stage/node/bin/node"
archive_component node 24.17.0 node "$node_stage"

modules_stage="$stage/modules"
mkdir -p "$modules_stage/backend/app"
ln -s "$("$root/scripts/prepare-smoke-node-modules.sh")" "$modules_stage/backend/app/node_modules"
archive_component node_modules smoke backend/app/node_modules "$modules_stage"

hpatch_stage="$stage/hpatchz"
mkdir -p "$hpatch_stage/backend"
printf '#!/bin/sh\nexit 0\n' >"$hpatch_stage/backend/hpatchz"
chmod +x "$hpatch_stage/backend/hpatchz"
archive_component hpatchz smoke backend "$hpatch_stage"

jq -s \
  --arg tag "$tag" \
  --arg appVersion "$app_version" \
  --arg generatedAt "1970-01-01T00:00:00Z" \
  --arg assetBaseURL "file://$out" \
  '{schemaVersion:2,tag:$tag,appVersion:$appVersion,platform:"darwin",hostArchitecture:"arm64",
    guestArchitecture:"x86_64",generatedAt:$generatedAt,assetBaseURL:$assetBaseURL,
    requiredPaths:["node/bin/node","backend/app/node_modules","backend/hpatchz"],components:.}' \
  "$component_file" >"$out/runtime-manifest.json"

printf '%s\n' "$out/runtime-manifest.json"
