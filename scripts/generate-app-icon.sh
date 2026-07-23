#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$root/frontend/Sources/Resources/AppIcon.icon-source/previews"
asset_dir="$root/frontend/Sources/Resources/Assets.xcassets/AppIcon.appiconset"
preview_dir="$root/frontend/Sources/Resources/AppIcon.icon-source/rendered"

mkdir -p "$preview_dir"

render() {
  local source="$1" destination="$2"
  sips -s format png "$source_dir/$source.svg" --out "$destination" >/dev/null
}

render default "$asset_dir/light.png"
render dark "$asset_dir/dark.png"
render mono "$asset_dir/mono.png"

for appearance in default dark clear-light clear-dark tinted-light tinted-dark; do
  render "$appearance" "$preview_dir/$appearance.png"
done

for image in "$asset_dir/light.png" "$asset_dir/dark.png" "$asset_dir/mono.png" "$preview_dir"/*.png; do
  test "$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')" = "1024"
  test "$(sips -g pixelHeight "$image" | awk '/pixelHeight/ {print $2}')" = "1024"
done
