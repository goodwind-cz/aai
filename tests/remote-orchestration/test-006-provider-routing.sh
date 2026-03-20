#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
usage="$tmp/usage.json"

write_usage_fixture "$usage"
run_cli router choose --project-config docs/ai/project-overrides/remote-control.yaml --usage-file "$usage" --phase planning --provider auto > "$tmp/auto.json"
run_cli router choose --project-config docs/ai/project-overrides/remote-control.yaml --usage-file "$usage" --phase implementation --provider codex > "$tmp/explicit.json"

json_assert_file "$tmp/auto.json" "data.decision.provider === 'claude'"
json_assert_file "$tmp/explicit.json" "data.decision.provider === 'codex'"
json_assert_file "$tmp/explicit.json" "data.decision.reason === 'project-policy-explicit'"
echo "PASS"
