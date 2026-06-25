#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$root/build/backend"
dist="$build_root/dist/MHGLauncherBackend"

rm -rf "$build_root"
mkdir -p "$dist/app"
cd "$root/backend"
npm ci
npm run build

cp -R .next app build next.config.ts package.json package-lock.json "$dist/app/"
mkdir -p "$dist/app/src/mhglauncher/data"
cp src/mhglauncher/data/gacha_items.json "$dist/app/src/mhglauncher/data/"
