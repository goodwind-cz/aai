#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/run-manifest.schema.json"
assert_contains "apps/control-plane/config/run-manifest.schema.json" "run_id"
assert_file "apps/control-plane/config/run-manifest.schema.json"
assert_contains "apps/control-plane/config/run-manifest.schema.json" "output_artifacts"
echo "PASS"
