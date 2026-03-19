#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md"
assert_contains "docs/ai/reports/REMOTE_RUNTIME_BOUNDARIES.md" "Host-only runtime artifacts"
assert_file "apps/control-plane/sql/001_init.sql"
assert_contains "apps/control-plane/sql/001_init.sql" "local_repo_path"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "local_repo_path"
assert_not_contains "docs/ai/project-overrides/remote-control.yaml" "allowed_telegram_chat_ids"
echo "PASS"
