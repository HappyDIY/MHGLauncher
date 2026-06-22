#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/backend"
npm ci
npm run typecheck
npm run lint
npm test
"$root/scripts/check-source-lines.sh"
