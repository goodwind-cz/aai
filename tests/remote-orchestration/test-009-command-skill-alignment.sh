#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/command-registry.json"
assert_contains "apps/control-plane/config/command-registry.json" '"/intake": "aai-intake"'
assert_file "apps/control-plane/config/command-registry.json"
assert_contains "apps/control-plane/config/command-registry.json" '"/usage": "provider-router"'
echo "PASS"
