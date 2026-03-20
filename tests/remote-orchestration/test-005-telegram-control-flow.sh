#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"

run_cli init --db "$db" > /dev/null
run_cli telegram simulate --db "$db" --command /intake --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --summary "Start remote orchestration" > "$tmp/intake.json"
run_cli telegram simulate --db "$db" --command /status --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 > "$tmp/status.json"
run_cli telegram simulate --db "$db" --command /resume --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 > "$tmp/resume.json"
run_cli telegram simulate --db "$db" --command /stop --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 > "$tmp/stop.json"

json_assert_file "$tmp/intake.json" "data.command === '/intake'"
json_assert_file "$tmp/status.json" "data.work_item.status === 'queued'"
json_assert_file "$tmp/resume.json" "data.work_item.status === 'running'"
json_assert_file "$tmp/stop.json" "data.work_item.status === 'stopped'"
echo "PASS"
