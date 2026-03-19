#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/resource-defaults.json"
assert_contains "apps/control-plane/config/resource-defaults.json" '"default_concurrency": 1'
assert_file "apps/control-plane/config/resource-defaults.json"
assert_contains "apps/control-plane/config/resource-defaults.json" '"requires_redis": false'
echo "PASS"
