#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

manifest="$("$root/scripts/create-smoke-runtime-assets.sh" "$stage/assets" v0.1.0)"
jq -e '.schemaVersion == 1 and .tag == "v0.1.0"' "$manifest" >/dev/null

jq -c '.components[]' "$manifest" | while IFS= read -r component; do
  file="$(jq -r '.file' <<<"$component")"
  path="$stage/assets/$file"
  test -f "$path"
  test "$(stat -f %z "$path")" = "$(jq -r '.size' <<<"$component")"
  test "$(shasum -a 256 "$path" | awk '{print $1}')" = "$(jq -r '.sha256' <<<"$component")"
done

app="$root/dist/MHGLauncher.app"
if [[ -d "$app" ]]; then
  test ! -e "$app/Contents/Resources/Backend/node"
  test ! -e "$app/Contents/Resources/Backend/MHGLauncherBackend/node"
  test ! -e "$app/Contents/Resources/GameRuntime"
fi

printf '运行时资产清单测试通过。\n'
