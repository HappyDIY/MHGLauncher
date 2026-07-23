#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
cd "$root/backend"
npm ci
npm run typecheck
npm run lint
npm run test:coverage
"$root/scripts/check-coverage.mjs" backend \
  "$root/backend/coverage/coverage-summary.json" \
  "$root/quality/coverage-baseline.json"
npm run test:performance
"$root/scripts/check-source-lines.sh"
