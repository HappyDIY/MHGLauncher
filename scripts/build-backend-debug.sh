#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/build-backend.sh" debug
rm -rf "$root/build/backend-debug"
mkdir -p "$root/build/backend-debug/dist"
cp -R "$root/build/backend/dist/MHGLauncherBackend" \
  "$root/build/backend-debug/dist/MHGLauncherBackend"
