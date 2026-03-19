#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "apps/control-plane/config/approval-gates.json"
assert_contains "apps/control-plane/config/approval-gates.json" "worktree_manifest"
assert_file "docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md"
assert_contains "docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md" "Approve implementation"
echo "PASS"
