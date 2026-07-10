#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
cd "$root/backend"
npm ci
npm run typecheck
npm run lint
npm test
"$root/scripts/check-source-lines.sh"
