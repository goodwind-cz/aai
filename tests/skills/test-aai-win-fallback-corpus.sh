#!/usr/bin/env bash
#
# Test: aai-win-fallback-corpus - the whole-checkout half of the Windows
# fallback suite (spec reuse-split-corpus-cases D2). It sources the definition
# file tests/skills/test-aai-win-fallback.sh (every function and helper lives
# there) and runs WIN_FALLBACK_CORPUS_TESTS: the cases that run the real test
# wrapper, which reads the git index. tests/skills/test-aai-win-fallback.sh
# itself runs the other cases.
#
# Usage:
#   bash tests/skills/test-aai-win-fallback-corpus.sh           # the five cases
#   bash tests/skills/test-aai-win-fallback-corpus.sh 029       # one case
#
# Exit codes: 0 passed, 1 failed, 42 skipped.

set -uo pipefail

CORPUS_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$CORPUS_SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || CORPUS_SCRIPT_DIR=.
# shellcheck source=test-aai-win-fallback.sh
. "$CORPUS_SCRIPT_DIR/test-aai-win-fallback.sh"
TEST_NAME="aai-win-fallback-corpus"

main_corpus() {
  if [[ $# -gt 0 ]]; then
    main "$@"
  else
    # shellcheck disable=SC2086
    main $WIN_FALLBACK_CORPUS_TESTS
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_corpus "$@"
fi
