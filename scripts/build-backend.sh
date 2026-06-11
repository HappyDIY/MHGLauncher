#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$root/build/backend"
dist_root="$build_root/dist"

rm -rf "$build_root"
mkdir -p "$build_root"
cd "$root/backend"

uv sync --frozen --all-groups
uv run pyinstaller \
  --noconfirm \
  --clean \
  --onedir \
  --name MHGLauncherBackend \
  --paths src \
  --distpath "$dist_root" \
  --workpath "$build_root/work" \
  --specpath "$build_root" \
  src/mhglauncher/__main__.py

binary="$dist_root/MHGLauncherBackend/MHGLauncherBackend"
test -x "$binary"

