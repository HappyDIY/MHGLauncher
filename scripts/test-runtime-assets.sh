#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

if "$root/scripts/build-runtime-assets.sh" '../../outside' >/dev/null 2>&1; then
  printf '构建脚本接受了不安全 tag。\n' >&2
  exit 1
fi
if "$root/scripts/publish-runtime-assets.sh" '../../outside' >/dev/null 2>&1; then
  printf '发布脚本接受了不安全 tag。\n' >&2
  exit 1
fi

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
