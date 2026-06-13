#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$root/build/backend"
dist_root="$build_root/dist"
mode="${1:-development}"

rm -rf "$build_root"
mkdir -p "$dist_root"
cd "$root/backend"

uv sync --frozen --all-groups

if [[ "$mode" == "--release" ]]; then
  nuitka_root="$build_root/nuitka"
  uv run python -m nuitka \
    --mode=standalone \
    --assume-yes-for-downloads \
    --disable-ccache \
    --nofollow-import-to=mypy \
    --include-package-data=mhglauncher \
    --output-dir="$nuitka_root" \
    --output-filename=MHGLauncherBackend \
    --python-flag=-m \
    src/mhglauncher

  standalone_dir="$nuitka_root/mhglauncher.dist"
  test -d "$standalone_dir"
  mv "$standalone_dir" "$dist_root/MHGLauncherBackend"
else
  uv run pyinstaller \
    --noconfirm \
    --clean \
    --onedir \
    --name MHGLauncherBackend \
    --collect-data mhglauncher \
    --paths src \
    --distpath "$dist_root" \
    --workpath "$build_root/work" \
    --specpath "$build_root" \
    src/mhglauncher/__main__.py
fi

"$root/scripts/fetch-hpatchz.sh" "$dist_root/MHGLauncherBackend"

binary="$dist_root/MHGLauncherBackend/MHGLauncherBackend"
test -x "$binary"
