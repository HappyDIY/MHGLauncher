#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if (( $# != 0 )); then
  printf '后端仅保留 release 构建，不再接受构建配置参数。\n' >&2
  exit 2
fi

node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
build_root="$root/build/backend"
dist="$build_root/dist/MHGLauncherBackend"

rm -rf "$build_root"
mkdir -p "$dist/app"
cd "$root/backend"
export MHG_BUILD_MODE=release
export NEXT_TELEMETRY_DISABLED=1
npm ci
npm run build

cp -R .next app build next.config.ts package.json package-lock.json "$dist/app/"
mkdir -p "$dist/app/src/mhglauncher/data"
cp src/mhglauncher/data/Snap.Metadata.LICENSE \
  "$dist/app/src/mhglauncher/data/"
test ! -e "$dist/app/src/mhglauncher/data/achievement.json"
test ! -e "$dist/app/src/mhglauncher/data/achievement_goals.json"
test ! -e "$dist/app/src/mhglauncher/data/gacha_events.json"
test ! -e "$dist/app/src/mhglauncher/data/gacha_items.json"
printf 'release\n' >"$dist/app/.build-mode"
