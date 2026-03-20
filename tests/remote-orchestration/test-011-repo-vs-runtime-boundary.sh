#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"

run_cli init --db "$db" > /dev/null
run_cli queue create --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --phase planning --branch aai/prd-01 --provider auto > "$tmp/out.json"
assert_file "$db"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "aai/prd-01"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "queued"
json_assert_file "$tmp/out.json" "data.work_item.branch === 'aai/prd-01'"
echo "PASS"
