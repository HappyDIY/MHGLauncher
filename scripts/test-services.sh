#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

"$root/scripts/check-toolchain.sh"
"$root/scripts/check-test-policy.sh"
"$root/scripts/test-cloud.sh"
"$root/scripts/test-admin.sh"
