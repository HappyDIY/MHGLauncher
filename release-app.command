#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
skip_tests=0
case "${1:-}" in
  "") ;;
  --skip-tests) skip_tests=1 ;;
  -h|--help) printf '用法：%s [--skip-tests]\n' "$0"; exit 0 ;;
  *) printf '未知参数：%s\n' "$1" >&2; exit 2 ;;
esac

if (( skip_tests == 0 )); then
  "$root/scripts/test-all.sh"
else
  "$root/scripts/build-app.sh"
fi

app="$root/dist/MHGLauncher.app"
pkill -x MHGLauncher 2>/dev/null || true
open "$app"
printf '已启动：%s\n' "$app"
