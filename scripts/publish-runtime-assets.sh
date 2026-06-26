#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?缺少版本 tag，例如 v0.1.0}"
asset_dir="$root/build/runtime-assets/$tag"

command -v gh >/dev/null || {
  printf '未找到 GitHub CLI：请先安装 gh 并登录。\n' >&2
  exit 1
}
[[ -f "$asset_dir/runtime-manifest.json" ]] || "$root/scripts/build-runtime-assets.sh" "$tag"

if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --draft --title "$tag" --notes "MHGLauncher $tag runtime assets"
fi

gh release upload "$tag" "$asset_dir"/* --clobber
printf '运行时资产已上传到 GitHub Release：%s\n' "$tag"
