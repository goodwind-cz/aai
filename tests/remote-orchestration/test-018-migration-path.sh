#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
run_cli help > "$tmp/help.txt"
assert_contains "docs/ai/reports/MIGRATION_PATH_REMOTE.md" "Install host control-plane runtime."
assert_contains "docs/ai/reports/MIGRATION_PATH_REMOTE.md" "Register project with /aai-remote-register."
assert_contains "$tmp/help.txt" "project register"
assert_contains "$tmp/help.txt" "telegram simulate"
echo "PASS"
