#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

section() {
  printf '\n==> %s\n' "$1"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

section "source line limits"
run "$root/scripts/check-source-lines.sh"

section "backend TypeScript variable and API type check"
cd "$root/backend"
if [[ ! -d node_modules ]]; then
  run npm ci
fi
run npm run typecheck
run npm test -- --run tests/api.test.ts tests/game.test.ts tests/predownload.test.ts

section "frontend Swift API model and runtime boundary check"
cd "$root/frontend"
run swift test --filter "APIClientTests|APIModelTests|GameModelTests|FeatureSurfaceTests|RuntimeInstallerTests"
