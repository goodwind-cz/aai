#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"

run_cli init --db "$db" > /dev/null
run_cli queue create --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --phase implementation --branch aai/prd-01 --provider codex > /dev/null
run_cli approve grant --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --gate implementation --approved-by user:1 --artifact-path docs/decisions/example.md > /dev/null
run_cli handoff build --db "$db" --project-id aai-canonical --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 --requirement-refs docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md --spec-refs docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md --report-refs docs/ai/reports/validation-20260319T190838Z.log > "$tmp/out.json"

json_assert_file "$tmp/out.json" "data.repo_truth.requirement_refs.length === 1"
json_assert_file "$tmp/out.json" "data.runtime_state.approvals.length === 1"
json_assert_file "$tmp/out.json" "data.handoff_contract.hidden_shared_memory_required === false"
echo "PASS"
