#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
build_root="$root/build/backend"
dist="$build_root/dist/MHGLauncherBackend"
mode="${1:-release}"

case "$mode" in
  --debug|debug|development) build_mode="debug" ;;
  --release|release|production) build_mode="release" ;;
  *)
    printf '未知后端构建配置：%s\n' "$mode" >&2
    exit 2
    ;;
esac

rm -rf "$build_root"
mkdir -p "$dist/app"
cd "$root/backend"
export MHG_BUILD_MODE="$build_mode"
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
printf '%s\n' "$build_mode" >"$dist/app/.build-mode"
