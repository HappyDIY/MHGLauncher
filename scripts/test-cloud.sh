#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
node_root="$("$root/scripts/fetch-node.sh")"
export PATH="$node_root/bin:$PATH"
cd "$root/cloud"
npm ci
npm run typecheck

if command -v docker >/dev/null 2>&1; then
	  compose_file="$root/docker-compose.yml"
	  compose_project="mhglauncher-cloud-test-$$"
	  export MHG_CLOUD_DB_PORT_MAPPING="127.0.0.1::5432"
	  cleanup() { docker compose -p "$compose_project" -f "$compose_file" down -v; }
	  trap cleanup EXIT
	  docker compose -p "$compose_project" -f "$compose_file" up -d db
	  for _ in {1..30}; do
	    docker compose -p "$compose_project" -f "$compose_file" exec -T db pg_isready -U mhglauncher >/dev/null 2>&1 && break
	    sleep 1
	  done
	  database_port="$(docker compose -p "$compose_project" -f "$compose_file" port db 5432 | awk -F: 'END { print $NF }')"
	  export DATABASE_URL="postgres://mhglauncher:mhglauncher@127.0.0.1:$database_port/mhglauncher"
	  npm test
else
  printf 'Docker 不可用，已跳过 cloud 集成测试。\n' >&2
fi
