#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"

run_cli approve check --gate implementation --prd-ref docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md > "$tmp/check-blocked.json"
json_assert_file "$tmp/check-blocked.json" "data.enabled === false && data.missing.length > 0"

run_cli init --db "$db" > /dev/null
run_cli approve grant --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --gate implementation --approved-by operator:1 --artifact-path docs/decisions/example.md > /dev/null
run_cli approval exists --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --gate implementation > "$tmp/exists.json"
json_assert_file "$tmp/exists.json" "data.exists === true"
echo "PASS"
