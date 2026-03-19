#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/src/provider-router.ts"
assert_contains "apps/control-plane/src/provider-router.ts" "chooseProvider"
assert_file "apps/control-plane/src/provider-router.ts"
assert_contains "apps/control-plane/src/provider-router.ts" "fallback"
echo "PASS"
