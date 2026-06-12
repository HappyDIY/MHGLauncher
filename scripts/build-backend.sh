#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$root/build/backend"
dist_root="$build_root/dist"
nuitka_root="$build_root/nuitka"

rm -rf "$build_root"
mkdir -p "$dist_root"
cd "$root/backend"

uv sync --frozen --all-groups
uv run python -m nuitka \
  --mode=standalone \
  --assume-yes-for-downloads \
  --disable-ccache \
  --nofollow-import-to=mypy \
  --output-dir="$nuitka_root" \
  --output-filename=MHGLauncherBackend \
  --python-flag=-m \
  src/mhglauncher

standalone_dir="$nuitka_root/mhglauncher.dist"
test -d "$standalone_dir"
mv "$standalone_dir" "$dist_root/MHGLauncherBackend"
"$root/scripts/fetch-hpatchz.sh" "$dist_root/MHGLauncherBackend"

binary="$dist_root/MHGLauncherBackend/MHGLauncherBackend"
test -x "$binary"
