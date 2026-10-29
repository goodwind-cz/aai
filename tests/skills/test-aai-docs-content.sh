#!/usr/bin/env bash
#
# Test: aai-docs-content — the always-on CONTENT half of the docs-audit suite
# (SPEC docs-audit-content-engine-split D1). It sources the definition file
# tests/skills/test-aai-docs-audit.sh (every function and helper lives there)
# and runs DOCS_AUDIT_CONTENT_CASES, the cases whose subject is the live
# repository corpus, so a document-only change can turn it red.
#
# Single-function dispatch: bash tests/skills/test-aai-docs-content.sh <function>
#
# Exit codes: 0 passed, 1 failed, 42 skipped.

set -euo pipefail

CONTENT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-aai-docs-audit.sh
. "$CONTENT_SCRIPT_DIR/test-aai-docs-audit.sh"
TEST_NAME="aai-docs-content"

main_content() {
  local fn
  if [[ $# -gt 0 ]]; then
    "$1"
    return
  fi
  echo "Testing $TEST_NAME suite (live-corpus content cases)"
  for fn in $DOCS_AUDIT_CONTENT_CASES; do
    "$fn"
  done
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_content "$@"
fi
