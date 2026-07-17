#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?缺少版本 tag，例如 v0.1.0}"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || {
  printf '运行时版本 tag 必须是 v 开头的语义版本。\n' >&2
  exit 2
}
asset_dir="$root/build/runtime-assets/$tag"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/packaging/Info.plist")"
[[ "$tag" == "v$app_version" ]] || { printf '发布 tag 必须与 App 版本 v%s 一致。\n' "$app_version" >&2; exit 2; }

command -v gh >/dev/null || {
  printf '未找到 GitHub CLI：请先安装 gh 并登录。\n' >&2
  exit 1
}
if draft="$(gh release view "$tag" --json isDraft --jq '.isDraft' 2>/dev/null)"; then
  [[ "$draft" == "true" ]] || { printf '拒绝修改已公开的不可变 Release：%s\n' "$tag" >&2; exit 1; }
  count="$(gh release view "$tag" --json assets --jq '.assets | length')"
  [[ "$count" == 0 ]] || { printf 'Draft Release 已包含资产，拒绝覆盖：%s\n' "$tag" >&2; exit 1; }
else
  [[ -f "$asset_dir/runtime-manifest.json" ]] || "$root/scripts/build-runtime-assets.sh" "$tag"
  MHG_REQUIRE_RUNTIME_SIGNATURE=1 "$root/scripts/verify-runtime-assets.sh" "$asset_dir" all
  gh release create "$tag" --draft --title "$tag" --notes "MHGLauncher $tag runtime assets"
fi

MHG_REQUIRE_RUNTIME_SIGNATURE=1 "$root/scripts/verify-runtime-assets.sh" "$asset_dir" all
gh release upload "$tag" "$asset_dir"/*
"$root/scripts/publish-gacha-history-resource.sh" "$tag" "${tag#v}"
printf '运行时资产已上传到 GitHub Release：%s\n' "$tag"
