#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md"
assert_contains "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md" "Repo-owned portable artifacts"
assert_file "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md"
assert_contains "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md" "Host-only runtime artifacts"
echo "PASS"
