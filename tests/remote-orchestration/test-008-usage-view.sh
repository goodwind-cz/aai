#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
usage="$tmp/usage.json"

write_usage_fixture "$usage"
run_cli usage show --usage-file "$usage" > "$tmp/out.json"
json_assert_file "$tmp/out.json" "data.providers.length === 2"
json_assert_file "$tmp/out.json" "data.providers.every((provider) => provider.window_label && provider.reset_at_utc)"
json_assert_file "$tmp/out.json" "data.providers.some((provider) => provider.provider === 'claude' && provider.used_percentage === 22)"
echo "PASS"
