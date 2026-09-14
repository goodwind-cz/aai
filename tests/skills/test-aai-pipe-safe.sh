#!/usr/bin/env bash
#
# Test: tests/skills/lib/pipe-safe.sh — the pipe-safe `qgrep`/`qhead` drop-in
# readers (remediation round 10, PR #381, docs/specs/SPEC-0179-spec-test-
# framework-sweep.md Amendment Round 10). Reproduces the early-closing-reader
# SIGPIPE class deterministically (TEST-467), proves `qhead` reads the same
# bytes correctly (TEST-468), and proves `qgrep` changes nothing about the
# exit-code contract a caller under `set -o pipefail` depends on (TEST-469).
#
# Usage:
#   bash tests/skills/test-aai-pipe-safe.sh                             # run all
#   bash tests/skills/test-aai-pipe-safe.sh test_467_qgrep_survives_early_close  # run one
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-pipe-safe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPE_SAFE_LIB="$SCRIPT_DIR/lib/pipe-safe.sh"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  [[ -f "$PIPE_SAFE_LIB" ]] || log_skip "missing $PIPE_SAFE_LIB"
  log_pass "Dependencies checked"
}

# A producer function (NOT a pipeline) that writes well past the 64 KiB pipe
# buffer AFTER a line an early match pattern hits, so a `grep -q`/`qgrep -q`
# reader that stops at the first match closes the pipe long before this
# producer is done writing — the exact shape CI hit on 1aab60bb. > 1 MB total
# (Spec-AC / brief requirement), not just past one buffer, so the
# reproduction does not depend on any one platform's exact buffer size.
pipe_safe_producer() {
  echo "first-line"
  local i=0
  while [[ "$i" -lt 20000 ]]; do
    printf 'filler line %d padding the payload well past the pipe buffer for SIGPIPE reproduction (round 10, PR #381)\n' "$i"
    i=$(( i + 1 ))
  done
}

test_467_qgrep_survives_early_close() {  # TEST-467
  log_info "TEST-467: a >1MB producer into grep -q (first-line match) SIGPIPEs under pipefail; qgrep does not (round 10)..."

  # Vacuity guard: the producer really is > 1 MB, or the reproduction below
  # proves nothing about the pipe-buffer class.
  local payload_bytes
  payload_bytes="$(pipe_safe_producer | wc -c | tr -d '[:space:]')"
  [[ "$payload_bytes" -gt 1000000 ]] \
    || log_fail "TEST-467: producer fixture is only $payload_bytes byte(s), need > 1000000 for the reproduction to mean anything"

  # ---- BASELINE: bare `grep -q` reading directly off the pipe reproduces
  # the CI-observed 141 (Broken pipe), reliably — the match is on the very
  # first line, so grep closes almost immediately while the producer is
  # still writing megabytes behind it.
  #
  # THE PIPE CHARACTER IS PASSED IN, ON PURPOSE (same technique tests/skills/
  # test-aai-hygiene-pack.sh's PGQ_BAR uses for its own pgq fixtures). This
  # arm's whole job is to prove the ratcheted shape reproduces 141, which
  # means the shape must be REAL inside the child `bash -c`. Writing it as a
  # literal pipe into `grep -q` here would make this file the pipe-safe
  # ratchet's own newest offender — so it is joined via `eval` from an
  # argument instead.
  local rc_bare
  bash -c '
    set -eo pipefail
    . "$1"
    p="$2"
    pipe_safe_producer() {
      echo "first-line"
      local i=0
      while [[ "$i" -lt 20000 ]]; do
        printf "filler line %d padding the payload well past the pipe buffer for SIGPIPE reproduction (round 10, PR #381)\n" "$i"
        i=$(( i + 1 ))
      done
    }
    eval "pipe_safe_producer ${p} grep -q first-line"
  ' _ "$PIPE_SAFE_LIB" "|" >/dev/null 2>&1
  rc_bare=$?
  # Two honest outcomes, one per SIGPIPE disposition of the environment:
  # 141 where SIGPIPE is at its default (the producer is killed), 1 where the
  # runner ignores SIGPIPE (GitHub Actions does — observed on PR #381 run
  # 34815192336, where this arm saw 0 before `set -e` propagated the
  # producer's EPIPE write error). Under `set -e` the EPIPE'd printf aborts
  # the producer with 1, so either way the pipeline is non-zero — which is
  # the class. Anything else (0 above all) means the fixture proved nothing.
  case "$rc_bare" in
    141) log_info "TEST-467: baseline reproduced SIGPIPE (rc 141; SIGPIPE at default here)" ;;
    1)   log_info "TEST-467: baseline reproduced EPIPE (rc 1; this environment ignores SIGPIPE, the producer's write failed instead)" ;;
    *)   log_fail "TEST-467: the baseline (producer piped into grep -q first-line) under pipefail must fail with 141 (SIGPIPE) or 1 (EPIPE under an ignored SIGPIPE), got $rc_bare — the reproduction fixture itself is not exercising the early-closing-reader class, so the qgrep proof below would be vacuous" ;;
  esac

  # ---- FIX: the same producer into `qgrep -q` must return 0 (match found),
  # never 141 — qgrep drains the pipe to EOF before grep ever sees it, so the
  # producer's writes never hit a closed reader.
  local rc_safe
  bash -c '
    set -eo pipefail
    . "$1"
    pipe_safe_producer() {
      echo "first-line"
      local i=0
      while [[ "$i" -lt 20000 ]]; do
        printf "filler line %d padding the payload well past the pipe buffer for SIGPIPE reproduction (round 10, PR #381)\n" "$i"
        i=$(( i + 1 ))
      done
    }
    pipe_safe_producer | qgrep -q first-line
  ' _ "$PIPE_SAFE_LIB" >/dev/null 2>&1
  rc_safe=$?
  [[ "$rc_safe" -eq 0 ]] \
    || log_fail "TEST-467: \`producer | qgrep -q first-line\` under pipefail must return 0 (match found, no SIGPIPE), got $rc_safe — qgrep did not survive the early-closing-reader class it exists to fix"

  log_pass "TEST-467: bare grep -q makes the producer fail (141, or 1 under an ignored SIGPIPE) on a >1MB early-match payload under pipefail; qgrep returns 0 with identical match semantics"
}

test_468_qhead_reads_same_bytes() {  # TEST-468
  log_info "TEST-468: qhead -n1 on the same >1MB payload returns the first line, rc 0 (round 10)..."
  local out rc
  out="$(bash -c '
    set -o pipefail
    . "$1"
    pipe_safe_producer() {
      echo "first-line"
      local i=0
      while [[ "$i" -lt 20000 ]]; do
        printf "filler line %d padding the payload well past the pipe buffer for SIGPIPE reproduction (round 10, PR #381)\n" "$i"
        i=$(( i + 1 ))
      done
    }
    pipe_safe_producer | qhead -n1
  ' _ "$PIPE_SAFE_LIB")"
  rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "TEST-468: producer | qhead -n1 under pipefail must return 0, got $rc"
  [[ "$out" == "first-line" ]] \
    || log_fail "TEST-468: qhead -n1 must read the FIRST line of the payload, got: $out"

  log_pass "TEST-468: qhead -n1 reads the payload's first line correctly, rc 0, no SIGPIPE"
}

test_469_qgrep_preserves_exit_codes() {  # TEST-469
  log_info "TEST-469: qgrep preserves grep's own exit code (no-match -> 1), and a producer's own failure is still visible under pipefail (round 10)..."

  # ---- No match: qgrep must return grep's own 1, exactly like a direct
  # `grep -q` on the same (small, no-SIGPIPE-risk) payload would.
  local rc_nomatch
  bash -c '
    set -eo pipefail
    . "$1"
    printf "needle-not-present\n" | qgrep -q "this-pattern-does-not-occur-anywhere-xyz"
  ' _ "$PIPE_SAFE_LIB" >/dev/null 2>&1
  rc_nomatch=$?
  [[ "$rc_nomatch" -eq 1 ]] \
    || log_fail "TEST-469: qgrep -q on a payload with no match must return 1 (grep's own no-match code), got $rc_nomatch"

  # ---- Producer failure: qgrep only changes how the READER consumes bytes.
  # A producer that fails on its own (unrelated to SIGPIPE) must still make
  # its failure visible through the pipeline under pipefail — qgrep must not
  # swallow it.
  local rc_producer_fail
  bash -c '
    set -eo pipefail
    . "$1"
    producer_fail() { echo "first-line"; exit 7; }
    producer_fail | qgrep -q first-line
  ' _ "$PIPE_SAFE_LIB" >/dev/null 2>&1
  rc_producer_fail=$?
  [[ "$rc_producer_fail" -eq 7 ]] \
    || log_fail "TEST-469: a producer that fails with exit 7 (unrelated to SIGPIPE) must still surface as 7 through \`producer | qgrep -q ...\` under pipefail, got $rc_producer_fail — qgrep must not mask a real producer failure"

  log_pass "TEST-469: qgrep preserves grep's no-match exit code (1), and a producer's own failure (7) still propagates through the pipeline under pipefail"
}

main() {
  echo "Testing $TEST_NAME (pipe-safe qgrep/qhead drop-in readers, round 10 PR #381)"
  check_deps
  test_467_qgrep_survives_early_close
  test_468_qhead_reads_same_bytes
  test_469_qgrep_preserves_exit_codes
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (RED-proof evidence); run
# the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "$#" -eq 0 ]]; then
    main
  elif [[ "$#" -eq 1 && "$1" == test_* ]] && declare -F "$1" >/dev/null; then
    check_deps
    "$1"
  else
    printf 'FAIL: unknown or invalid test function: %s\n' "${1:-<missing>}" >&2
    exit 2
  fi
fi
