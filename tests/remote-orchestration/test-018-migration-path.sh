#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "docs/ai/reports/MIGRATION_PATH_REMOTE.md"
assert_contains "docs/ai/reports/MIGRATION_PATH_REMOTE.md" "/aai-remote-register"
assert_file "docs/ai/reports/MIGRATION_PATH_REMOTE.md"
assert_contains "docs/ai/reports/MIGRATION_PATH_REMOTE.md" "downstream sync boundaries"
echo "PASS"
