#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/usage-payload.schema.json"
assert_contains "apps/control-plane/config/usage-payload.schema.json" "used_percentage"
assert_file "apps/control-plane/config/usage-payload.schema.json"
assert_contains "apps/control-plane/config/usage-payload.schema.json" "reset_at_utc"
echo "PASS"
