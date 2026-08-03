#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/frontend"
MHG_PROVIDER_MODE=fixture swift test --filter CoreFixtureMatrixTests
printf '纯 Swift Fixture 功能矩阵测试通过。\n'
