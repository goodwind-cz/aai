#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"

run_cli init --db "$db" > /dev/null
run_cli project register --db "$db" --project-config docs/ai/project-overrides/remote-control.yaml --repo-path "$PWD" --chat-ids 1001,1002 --user-ids 2001 > /dev/null
run_cli project show --db "$db" --project-id aai-canonical > "$tmp/out.json"

json_assert_file "$tmp/out.json" "typeof data.project.local_repo_path === 'string' && data.project.local_repo_path.toLowerCase().includes('aai-feature-remote-orchestration')"
json_assert_file "$tmp/out.json" "Array.isArray(data.project.allowed_telegram_chat_ids) && data.project.allowed_telegram_chat_ids.length === 2"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "$PWD"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "1001"
echo "PASS"
