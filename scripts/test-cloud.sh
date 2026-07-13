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
  export DATABASE_URL="postgres://mhglauncher:mhglauncher@127.0.0.1:54329/mhglauncher"
  for _ in {1..30}; do
    docker compose -f "$root/docker-compose.cloud.yml" exec -T db pg_isready -U mhglauncher >/dev/null 2>&1 && break
    sleep 1
  done
  npm test
else
  printf 'Docker 不可用，已跳过 cloud 集成测试。\n' >&2
fi
