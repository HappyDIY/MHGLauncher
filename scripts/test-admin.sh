#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
cd "$root/admin"
npm ci
npm run typecheck
npm run lint
npm test
npm run build
if [[ "${MHG_RUN_PLAYWRIGHT:-0}" == "1" ]]; then
  npm run test:e2e
fi
