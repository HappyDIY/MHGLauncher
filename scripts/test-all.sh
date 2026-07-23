#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

"$root/scripts/test-launcher.sh"
"$root/scripts/test-services.sh"
