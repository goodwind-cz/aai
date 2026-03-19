#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"
assert_file "docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md"
assert_contains "docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md" "direct API-key or token-based provider mode is not supported"
assert_file "docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md"
assert_contains "docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md" "must never ask for provider API keys"
echo "PASS"
