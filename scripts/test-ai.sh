#!/usr/bin/env bash
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
base_ref="${MHG_AI_TEST_BASE:-HEAD}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch="$(date +%s)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
log_dir="$root/build/ai-tests/$run_id"
changed_jsonl="$log_dir/changed.jsonl"
results_jsonl="$log_dir/results.jsonl"
discovery_log="$log_dir/discovery.log"

mkdir -p "$log_dir"
: >"$changed_jsonl"
: >"$results_jsonl"
: >"$discovery_log"

emit_bootstrap_failure() {
  local message="$1"
  printf '{"schema_version":1,"status":"failed","phase":"bootstrap","message":"%s"}\n' "$message"
  exit 2
}

command -v jq >/dev/null 2>&1 ||
  emit_bootstrap_failure "缺少 jq"

base_commit="$(git -C "$root" rev-parse --verify "$base_ref" 2>"$discovery_log")" ||
  emit_bootstrap_failure "测试基线无效"
head_commit="$(git -C "$root" rev-parse --verify HEAD 2>>"$discovery_log")" ||
  emit_bootstrap_failure "无法读取 HEAD"

tracked_file="$log_dir/tracked.zlist"
untracked_file="$log_dir/untracked.zlist"
git -C "$root" diff --name-only --no-renames -z "$base_ref" -- \
  >"$tracked_file" 2>>"$discovery_log" ||
  emit_bootstrap_failure "无法读取 Git 变更"
git -C "$root" ls-files --others --exclude-standard -z \
  >"$untracked_file" 2>>"$discovery_log" ||
  emit_bootstrap_failure "无法读取未跟踪文件"

changed_files=()
add_changed_file() {
  local path="$1" existing
  for existing in "${changed_files[@]}"; do
    [[ "$existing" == "$path" ]] && return
  done
  changed_files[${#changed_files[@]}]="$path"
  jq -nc --arg path "$path" '$path' >>"$changed_jsonl"
}

while IFS= read -r -d '' path; do
  add_changed_file "$path"
done <"$tracked_file"
while IFS= read -r -d '' path; do
  add_changed_file "$path"
done <"$untracked_file"

suite_ids=()
suite_commands=()
suite_reasons=()
select_suite() {
  local id="$1" command="$2" reason="$3" existing
  for existing in "${suite_ids[@]}"; do
    [[ "$existing" == "$id" ]] && return
  done
  suite_ids[${#suite_ids[@]}]="$id"
  suite_commands[${#suite_commands[@]}]="$command"
  suite_reasons[${#suite_reasons[@]}]="$reason"
}

for path in "${changed_files[@]}"; do
  case "$path" in
    backend/src/api/*|backend/src/core/models.ts)
      select_suite backend scripts/test-backend.sh "$path"
      select_suite api-boundary scripts/check-api-boundary.sh "$path"
      ;;
    frontend/Sources/Models/*|frontend/Sources/Services/APIClient.swift|frontend/Tests/API*)
      select_suite frontend scripts/test-frontend.sh "$path"
      select_suite api-boundary scripts/check-api-boundary.sh "$path"
      ;;
    backend/*) select_suite backend scripts/test-backend.sh "$path" ;;
    frontend/*) select_suite frontend scripts/test-frontend.sh "$path" ;;
    cloud/*) select_suite cloud scripts/test-cloud.sh "$path" ;;
    admin/*) select_suite admin scripts/test-admin.sh "$path" ;;
    contracts/local-api/*)
      select_suite api-boundary scripts/check-api-boundary.sh "$path"
      ;;
    quality/*|scripts/check-coverage.mjs)
      select_suite backend scripts/test-backend.sh "$path"
      select_suite frontend scripts/test-frontend.sh "$path"
      ;;
    release-app.command|packaging/Info.plist|scripts/build-app.sh|scripts/build-backend.sh|scripts/build-frontend.sh|scripts/configure-cloud-server.swift|scripts/test-build-config.sh)
      select_suite build-config scripts/test-build-config.sh "$path"
      ;;
    runtime/*|scripts/fetch-game-runtime.sh|scripts/test-game-runtime.sh)
      select_suite game-runtime scripts/test-game-runtime.sh "$path"
      ;;
    packaging/GAME_RUNTIME_NOTICES.md|packaging/HDiffPatch-LICENSE.txt|scripts/build-runtime-assets.sh|scripts/create-smoke-runtime-assets.sh|scripts/verify-runtime-assets.sh|scripts/publish-runtime-assets.sh|scripts/test-runtime-assets.sh)
      select_suite runtime-assets scripts/test-runtime-assets.sh "$path"
      ;;
    scripts/check-api-boundary.sh)
      select_suite api-boundary scripts/check-api-boundary.sh "$path"
      ;;
    scripts/test-backend.sh|scripts/fetch-node.sh|scripts/fetch-hpatchz.sh)
      select_suite backend scripts/test-backend.sh "$path"
      ;;
    scripts/test-frontend.sh)
      select_suite frontend scripts/test-frontend.sh "$path"
      ;;
    scripts/test-cloud.sh|docker-compose.yml)
      select_suite cloud scripts/test-cloud.sh "$path"
      ;;
    scripts/test-admin.sh)
      select_suite admin scripts/test-admin.sh "$path"
      ;;
    scripts/check-source-lines.sh)
      select_suite source-lines scripts/check-source-lines.sh "$path"
      ;;
    scripts/check-test-policy.sh)
      select_suite test-policy scripts/check-test-policy.sh "$path"
      ;;
    scripts/check-toolchain.sh)
      select_suite toolchain scripts/check-toolchain.sh "$path"
      ;;
    AGENTS.md|CLAUDE.md|*.md|.gitignore) ;;
    scripts/test-ai.sh|scripts/test-all.sh|scripts/test-launcher.sh|scripts/test-services.sh|.github/*|.codex/*|scripts/*)
      select_suite full scripts/test-all.sh "$path"
      ;;
    *) select_suite full scripts/test-all.sh "$path" ;;
  esac
done

for id in "${suite_ids[@]}"; do
  if [[ "$id" == "full" ]]; then
    suite_ids=(full)
    suite_commands=(scripts/test-all.sh)
    suite_reasons=("测试编排或未知范围发生变化")
    break
  fi
done

passed=0
failed=0
for ((index = 0; index < ${#suite_ids[@]}; index++)); do
  id="${suite_ids[$index]}"
  command="${suite_commands[$index]}"
  reason="${suite_reasons[$index]}"
  log="$log_dir/$id.log"
  suite_started="$(date +%s)"
  /bin/bash "$root/$command" >"$log" 2>&1
  exit_code=$?
  duration=$(($(date +%s) - suite_started))
  if (( exit_code == 0 )); then
    status=passed
    passed=$((passed + 1))
  else
    status=failed
    failed=$((failed + 1))
  fi
  jq -nc \
    --arg id "$id" --arg command "$command" --arg reason "$reason" \
    --arg status "$status" --arg log "${log#"$root/"}" \
    --argjson exit_code "$exit_code" --argjson duration_seconds "$duration" \
    '{id:$id,command:$command,reason:$reason,status:$status,exit_code:$exit_code,duration_seconds:$duration_seconds,log:$log}' \
    >>"$results_jsonl"
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
duration=$(($(date +%s) - started_epoch))
overall_status=passed
exit_code=0
if (( failed != 0 )); then
  overall_status=failed
  exit_code=1
fi

result_file="$log_dir/result.json"
jq -cS -n \
  --arg status "$overall_status" --arg base_ref "$base_ref" \
  --arg base_commit "$base_commit" --arg head_commit "$head_commit" \
  --arg started_at "$started_at" --arg finished_at "$finished_at" \
  --arg log_dir "${log_dir#"$root/"}" \
  --argjson duration_seconds "$duration" \
  --argjson selected "${#suite_ids[@]}" \
  --argjson passed "$passed" --argjson failed "$failed" \
  --slurpfile changed_files "$changed_jsonl" \
  --slurpfile tests "$results_jsonl" \
  '{schema_version:1,status:$status,base:{ref:$base_ref,commit:$base_commit},head_commit:$head_commit,started_at:$started_at,finished_at:$finished_at,duration_seconds:$duration_seconds,changed_files:$changed_files,summary:{selected:$selected,passed:$passed,failed:$failed},tests:$tests,log_dir:$log_dir}' \
  >"$result_file"

cat "$result_file"
printf '\n'
exit "$exit_code"
