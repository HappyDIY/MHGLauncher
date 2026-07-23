#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$root/frontend"
swift test --enable-code-coverage
coverage="$(swift test --show-codecov-path)"
"$root/scripts/check-coverage.mjs" frontend \
  "$coverage" \
  "$root/quality/coverage-baseline.json"
"$root/scripts/check-source-lines.sh"
