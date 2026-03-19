#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/src/runner.ts"
assert_contains "apps/control-plane/src/runner.ts" "worktree_path"
assert_file "apps/control-plane/src/runner.ts"
assert_contains "apps/control-plane/src/runner.ts" "mounts"
echo "PASS"
