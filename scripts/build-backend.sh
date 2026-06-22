#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$root/build/backend"
dist="$build_root/dist/MHGLauncherBackend"
node_root="$($root/scripts/fetch-node.sh)"

rm -rf "$build_root"
mkdir -p "$dist/app"
cd "$root/backend"
npm ci
npm run build

cp "$node_root/bin/node" "$dist/node"
cp -R .next app build next.config.ts package.json package-lock.json "$dist/app/"
mkdir -p "$dist/app/src/mhglauncher/data"
cp src/mhglauncher/data/gacha_items.json "$dist/app/src/mhglauncher/data/"
PATH="$node_root/bin:$PATH" npm ci --omit=dev --prefix "$dist/app"

cat >"$dist/MHGLauncherBackend" <<'EOF'
#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$root/app"
export NODE_ENV=production
export MHG_HPATCHZ="$root/hpatchz"
export MHG_RUNTIME_ROOT="$root/../../GameRuntime"
exec "$root/node" build/server.js
EOF
chmod +x "$dist/MHGLauncherBackend" "$dist/node"
"$root/scripts/fetch-hpatchz.sh" "$dist"
