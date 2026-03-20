#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
run_cli telegram interactive > "$tmp/out.json"
run_cli telegram callback --data "approve:implementation:PRD-AAI-REMOTE-ORCHESTRATION-01" > "$tmp/callback.json"
json_assert_file "$tmp/out.json" "data.inline_actions.includes('Approve implementation')"
json_assert_file "$tmp/out.json" "data.inline_actions.includes('Use Codex')"
json_assert_file "$tmp/out.json" "data.form_fields.includes('project_id') && data.form_fields.includes('summary')"
json_assert_file "$tmp/callback.json" "data.action === 'approve' && data.target === 'implementation'"

if run_cli telegram callback --data "approve:../etc/passwd:bad" > "$tmp/bad-callback.json" 2>&1; then
  echo "unsafe callback should fail"
  exit 1
fi
echo "PASS"
