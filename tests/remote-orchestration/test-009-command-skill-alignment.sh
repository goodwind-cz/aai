#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
run_cli telegram registry --config apps/control-plane/config/command-registry.json > "$tmp/out.json"
json_assert_file "$tmp/out.json" "data.commands['/intake'] === 'aai-intake'"
json_assert_file "$tmp/out.json" "data.commands['/approve'] === 'hitl-approvals'"
json_assert_file "$tmp/out.json" "data.aliases['/new'] === '/intake'"
echo "PASS"
