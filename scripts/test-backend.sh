#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/backend"

uv sync --frozen --all-groups
uv run ruff check .
uv run mypy src
uv run pytest
"$root/scripts/check-source-lines.sh"

