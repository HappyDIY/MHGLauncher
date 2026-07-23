#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0

reject() {
  local pattern="$1"
  shift
  if rg -n "$pattern" "$@"; then
    status=1
  fi
}

reject '\b(describe|it|test)\.(skip|skipIf|runIf|only|todo)\b|\b(xdescribe|xit|xtest)\b' \
  "$root/backend/tests" "$root/cloud/tests" "$root/admin"
reject 'XCTSkip|@Test\([^)]*\.disabled|@Suite\([^)]*\.disabled' "$root/frontend/Tests"

if (( status != 0 )); then
  printf '测试门禁禁止 skip、only、todo 或 disabled。\n' >&2
  exit "$status"
fi

printf '测试策略检查通过。\n'
