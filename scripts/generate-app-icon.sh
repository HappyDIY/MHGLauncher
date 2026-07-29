#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$root/frontend/Sources/Resources/AppIcon.icon-source/previews"
preview_dir="$root/frontend/Sources/Resources/AppIcon.icon-source/rendered"

mkdir -p "$preview_dir"

render() {
  local source="$1" destination="$2"
  sips -s format png "$source_dir/$source.svg" --out "$destination" >/dev/null
}

for appearance in default dark clear-light clear-dark tinted-light tinted-dark; do
  render "$appearance" "$preview_dir/$appearance.png"
  image="$preview_dir/$appearance.png"
  test "$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')" = "1024"
  test "$(sips -g pixelHeight "$image" | awk '/pixelHeight/ {print $2}')" = "1024"
done

for source in 00-background.svg 01-portal.svg 02-launch.svg 03-spark.svg; do
  cmp "$root/frontend/Sources/Resources/AppIcon.icon-source/$source" \
    "$root/frontend/Sources/Resources/AppIcon.icon/Assets/$source"
done
