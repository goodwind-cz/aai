#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/approval-gates.json"
assert_contains "apps/control-plane/config/approval-gates.json" "approve_implementation_requires"
assert_file "apps/control-plane/config/approval-gates.json"
assert_contains "apps/control-plane/config/approval-gates.json" "approve_validation_requires"
echo "PASS"
