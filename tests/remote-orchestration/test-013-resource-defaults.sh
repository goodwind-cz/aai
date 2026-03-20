#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
run_cli defaults show --config apps/control-plane/config/resource-defaults.json > "$tmp/out.json"
json_assert_file "$tmp/out.json" "data.controller_mode === 'single-process'"
json_assert_file "$tmp/out.json" "data.runtime_db === 'sqlite-wal'"
json_assert_file "$tmp/out.json" "data.default_concurrency === 1"
json_assert_file "$tmp/out.json" "data.requires_redis === false && data.requires_postgres === false"
echo "PASS"
