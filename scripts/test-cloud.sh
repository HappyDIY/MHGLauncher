#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
cd "$root/cloud"
npm ci
npm run typecheck

if command -v docker >/dev/null 2>&1; then
  docker compose -f "$root/docker-compose.cloud.yml" up -d db
  trap 'docker compose -f "$root/docker-compose.cloud.yml" down -v' EXIT
  npm test
else
  printf 'Docker 不可用，已跳过 cloud 集成测试。\n' >&2
fi
