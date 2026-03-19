#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/src/telegram.ts"
assert_contains "apps/control-plane/src/telegram.ts" "/intake"
assert_file "apps/control-plane/src/telegram.ts"
assert_contains "apps/control-plane/src/telegram.ts" "/approve"
assert_file "apps/control-plane/src/telegram.ts"
assert_contains "apps/control-plane/src/telegram.ts" "/stop"
echo "PASS"
