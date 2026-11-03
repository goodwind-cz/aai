#!/usr/bin/env bash
#
# Test: aai-hygiene-corpus - the whole-checkout half of the hygiene pack (spec
# reuse-split-corpus-cases D2). It sources the definition file
# tests/skills/test-aai-hygiene-pack.sh (every function and helper lives there)
# and runs HYGIENE_CORPUS_CASES: the cases whose subject is the git index, a
# whole tree or the run ledgers, so any tracked-file change can turn it red.
# tests/skills/test-aai-hygiene-pack.sh itself runs the fixture cases only.
#
# Single-function dispatch: bash tests/skills/test-aai-hygiene-corpus.sh <function>
#
# Exit codes: 0 passed, 1 failed, 42 skipped.

set -euo pipefail

CORPUS_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$CORPUS_SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || CORPUS_SCRIPT_DIR=.
# shellcheck source=test-aai-hygiene-pack.sh
. "$CORPUS_SCRIPT_DIR/test-aai-hygiene-pack.sh"
TEST_NAME="aai-hygiene-corpus"

main_corpus() {
  local fn
  if [[ $# -gt 0 ]]; then
    declare -F "$1" >/dev/null || { printf 'FAIL: unknown or invalid test function: %s\n' "$1" >&2; exit 2; }
    check_deps
    "$1"
    return
  fi
  echo "Testing $TEST_NAME (whole-checkout cases of the hygiene pack)"
  check_deps
  for fn in $HYGIENE_CORPUS_CASES; do
    "$fn"
  done
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_corpus "$@"
fi
