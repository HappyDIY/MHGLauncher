#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:?缺少 GitHub Release tag}"
version="${2:?缺少历史卡池资源版本}"
manifest="$root/build/gacha-history-assets/$version/gacha-history-manifest.json"
test -f "$manifest" || manifest="$("$root/scripts/build-gacha-history-resource.sh" "$version")"
"$root/scripts/verify-gacha-history-resource.sh" "$manifest"
command -v gh >/dev/null || { printf '未找到 GitHub CLI。\n' >&2; exit 1; }
gh release view "$tag" >/dev/null
gh release upload "$tag" "$(dirname "$manifest")/gacha-history.zip" "$manifest" --clobber
printf '历史卡池资源已上传到 Release：%s\n' "$tag"
