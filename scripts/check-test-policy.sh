#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0

reject() {
  local pattern="$1"
  shift
  local result
  if command -v rg >/dev/null 2>&1; then
    if rg -n "$pattern" "$@"; then
      status=1
      return
    else
      result=$?
    fi
  elif grep -EnR \
    --exclude-dir=.build \
    --exclude-dir=.git \
    --exclude-dir=.next \
    --exclude-dir=build \
    --exclude-dir=dist \
    --exclude-dir=node_modules \
    "$pattern" "$@"; then
    status=1
    return
  else
    result=$?
  fi
  if (( result > 1 )); then
    printf '测试策略扫描失败（退出码 %s）。\n' "$result" >&2
    exit "$result"
  fi
}

reject '(^|[^[:alnum:]_])(describe|it|test)\.(skip|skipIf|runIf|only|todo)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])(xdescribe|xit|xtest)([^[:alnum:]_]|$)' \
  "$root/backend/tests"
reject 'XCTSkip|@Test\([^)]*\.disabled|@Suite\([^)]*\.disabled' "$root/frontend/Tests"

if (( status != 0 )); then
  printf '测试门禁禁止 skip、only、todo 或 disabled。\n' >&2
  exit "$status"
fi

printf '测试策略检查通过。\n'
