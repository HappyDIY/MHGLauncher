#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0

while IFS= read -r file; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  if (( lines > 1000 )); then
    printf '源码文件超过 1000 行：%s（%s 行）\n' "$file" "$lines" >&2
    status=1
  fi
done < <(find "$root" \
  -type f \( -name '*.swift' -o -name '*.rs' -o -name '*.ts' \) \
  -not -path '*/.build/*' \
  -not -path '*/.venv/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.next/*' \
  -not -path '*/generated/*' \
  -not -path '*/dist/*' \
  | sort)

exit "$status"
