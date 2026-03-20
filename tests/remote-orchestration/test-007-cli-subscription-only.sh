#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT

run_cli auth validate --mode cli-subscription > "$tmp/ok.json"
json_assert_file "$tmp/ok.json" "data.ok === true && data.mode === 'cli-subscription'"

if run_cli auth validate --mode api-key > "$tmp/fail.log" 2>&1; then
  echo "api-key mode should fail"
  exit 1
fi

assert_contains "$tmp/fail.log" "Only cli-subscription is allowed"
echo "PASS"
