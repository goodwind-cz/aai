#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/handoff.schema.json"
assert_contains "apps/control-plane/config/handoff.schema.json" "input_refs"
assert_file "apps/control-plane/config/handoff.schema.json"
assert_contains "apps/control-plane/config/handoff.schema.json" "output_targets"
echo "PASS"
