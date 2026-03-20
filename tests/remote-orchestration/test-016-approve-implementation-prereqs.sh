#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT

run_cli approve check --gate implementation \
  --prd-ref docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --frozen-spec-ref docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --test-plan-ref docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md > "$tmp/incomplete.json"

json_assert_file "$tmp/incomplete.json" "data.enabled === false"
json_assert_file "$tmp/incomplete.json" "data.missing.includes('project_selection') && data.missing.includes('worktree_manifest')"

run_cli approve check --gate implementation \
  --prd-ref docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --frozen-spec-ref docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --test-plan-ref docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --project-selection aai-canonical \
  --provider-selection-or-policy auto \
  --worktree-manifest /tmp/run-manifest.json > "$tmp/complete.json"

json_assert_file "$tmp/complete.json" "data.enabled === true && data.missing.length === 0"
echo "PASS"
