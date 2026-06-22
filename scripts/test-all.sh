#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

"$root/scripts/check-source-lines.sh"
"$root/scripts/test-game-runtime.sh"
"$root/scripts/test-backend.sh"
"$root/scripts/test-frontend.sh"
"$root/scripts/build-app.sh"
"$root/scripts/smoke-backend.sh"
"$root/scripts/test-features.sh"
"$root/scripts/smoke-app.sh"
