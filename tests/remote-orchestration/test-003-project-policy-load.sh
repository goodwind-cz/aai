#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
run_cli policy show --project-config docs/ai/project-overrides/remote-control.yaml > "$tmp/out.json"
json_assert_file "$tmp/out.json" "data.project_id === 'aai-canonical'"
json_assert_file "$tmp/out.json" "data.default_provider_policy === 'auto'"
json_assert_file "$tmp/out.json" "data.phase_provider_preferences.implementation === 'codex'"
echo "PASS"
