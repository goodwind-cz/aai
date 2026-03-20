#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT

run_cli approve check --gate validation --implementation-summary done > "$tmp/incomplete.json"
json_assert_file "$tmp/incomplete.json" "data.enabled === false && data.missing.includes('changed_file_summary')"

run_cli approve check --gate validation \
  --implementation-summary done \
  --changed-file-summary apps/control-plane/src/cli.ts \
  --validation-command-set "bash tests/remote-orchestration/run-all.sh" \
  --report-target-path docs/ai/reports/validation-current.md \
  --evidence-target-path docs/ai/reports/validation-current.log > "$tmp/complete.json"

json_assert_file "$tmp/complete.json" "data.enabled === true && data.missing.length === 0"
echo "PASS"
