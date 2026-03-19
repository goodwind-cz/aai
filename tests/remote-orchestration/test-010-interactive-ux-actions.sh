#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/src/telegram.ts"
assert_contains "apps/control-plane/src/telegram.ts" "Approve implementation"
assert_file "apps/control-plane/src/telegram.ts"
assert_contains "apps/control-plane/src/telegram.ts" "Use Auto Router"
echo "PASS"
