#!/usr/bin/env bash
#
# Test: Windows fallback wiring that lives OUTSIDE the Pester suite (SPEC-0046
# / ISSUE-0009, TEST-007, TEST-009, TEST-013).
#
#   - TEST-007 (Spec-AC-05): the MSYS-deterministic degraded branch in
#     .aai/scripts/aai-run-tests.sh. Branch SELECTION is injectable via an
#     AAI_UNAME override (used only when set), so it is unit-testable on this
#     macOS host without a real Git-Bash/MSYS environment. With AAI_UNAME
#     UNSET the chain must be byte-for-byte the current (pre-change) behavior
#     — this suite's own AAI_UNAME-unset assertions ARE that regression check.
#   - TEST-009 (Spec-AC-07): the 5-row supported-platform matrix is present,
#     with the same 5 concepts, in both wrapper headers AND docs/TECHNOLOGY.md.
#   - TEST-013 (Spec-AC-10): the Manual verification protocol section
#     (MV-1..MV-3) is documented in the frozen spec. Automated part checks
#     ONLY that the protocol is documented — MV-1..3 EXECUTION is manual,
#     off-host (real Windows), and is never claimed here.
#
# Usage:
#   bash tests/skills/test-aai-win-fallback.sh            # run all
#   bash tests/skills/test-aai-win-fallback.sh 007 009     # run only selected
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-win-fallback"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_TESTS_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
REAP_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.sh"
RUN_TESTS_PS1="$PROJECT_ROOT/.aai/scripts/aai-run-tests.ps1"
REAP_PS1="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.ps1"
TECHNOLOGY_DOC="$PROJECT_ROOT/docs/TECHNOLOGY.md"
SPEC_DOC="$PROJECT_ROOT/docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  [[ -f "$RUN_TESTS_SCRIPT" ]] || log_fail "missing $RUN_TESTS_SCRIPT"
  [[ -f "$REAP_SCRIPT" ]] || log_fail "missing $REAP_SCRIPT"
  [[ -f "$TECHNOLOGY_DOC" ]] || log_fail "missing $TECHNOLOGY_DOC"
  [[ -f "$SPEC_DOC" ]] || log_fail "missing $SPEC_DOC"
  log_pass "Dependencies checked"
}

# --- TEST-007 (Spec-AC-05): MSYS-deterministic degraded branch, injectable ---

test_007() {
  log_info "TEST-007: AAI_UNAME=MSYS_NT-10.0 -> degraded branch marker on stderr; unset -> current chain untouched..."

  local out rc

  # Baseline: AAI_UNAME unset -> no degraded marker, exit-code fidelity holds
  # exactly as before this change (regression tripwire for the untouched path).
  out="$(sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    && log_fail "degraded marker printed with AAI_UNAME unset (must be inert on macOS/Linux)"
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 7' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 7 ]] || log_fail "AAI_UNAME unset: exit-code fidelity broke (expected 7, got $rc)"

  # Forced MSYS: AAI_UNAME=MSYS_NT-10.0 -> exactly one degraded-mode marker on
  # stderr, naming the reason; exit-code fidelity still holds under the
  # degraded (bare-background) launch path.
  out="$(AAI_UNAME="MSYS_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  local marker_count
  marker_count="$(echo "$out" | grep -c "AAI-DEGRADED-MODE")"
  [[ "$marker_count" -eq 1 ]] \
    || log_fail "expected exactly one AAI-DEGRADED-MODE marker under AAI_UNAME=MSYS_NT-10.0, got $marker_count"
  echo "$out" | grep -qi "MSYS" || log_fail "degraded marker must name the detected MSYS/MINGW uname"

  AAI_UNAME="MSYS_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 5' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "AAI_UNAME=MSYS_NT-10.0: exit-code fidelity broke (expected 5, got $rc)"

  # MINGW variant also selects the degraded branch.
  out="$(AAI_UNAME="MINGW64_NT-10.0" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    || log_fail "AAI_UNAME=MINGW64_NT-10.0 must also select the degraded branch"

  # A non-Windows-shaped AAI_UNAME override (e.g. explicitly set to Linux) must
  # NOT force the degraded branch — selection is uname-value-driven, not
  # merely override-presence-driven.
  out="$(AAI_UNAME="Linux" sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' 2>&1 1>/dev/null)"
  echo "$out" | grep -q "AAI-DEGRADED-MODE" \
    && log_fail "AAI_UNAME=Linux must NOT select the degraded branch"

  log_pass "MSYS-deterministic degraded branch selects on AAI_UNAME override; inert when unset (TEST-007)"
}

# --- TEST-009 (Spec-AC-07): 5-row platform matrix, both headers + TECHNOLOGY.md

test_009() {
  log_info "TEST-009: grep asserts — 5-row platform matrix present in both wrapper headers + TECHNOLOGY.md..."

  [[ -f "$RUN_TESTS_PS1" ]] || log_fail "missing $RUN_TESTS_PS1 (new Windows dispatcher)"
  [[ -f "$REAP_PS1" ]] || log_fail "missing $REAP_PS1 (new Windows reap dispatcher)"

  local doc
  for doc in "$RUN_TESTS_SCRIPT" "$REAP_SCRIPT" "$TECHNOLOGY_DOC"; do
    grep -qiE 'macOS' "$doc" || log_fail "$doc missing the macOS platform-matrix row"
    grep -qiE 'Linux' "$doc" || log_fail "$doc missing the Linux platform-matrix row"
    grep -qiE 'WSL' "$doc" || log_fail "$doc missing the Windows+WSL platform-matrix row"
    grep -qiE 'Git.?Bash' "$doc" || log_fail "$doc missing the Windows+Git-Bash-only platform-matrix row"
    grep -qiE 'neither|AAI-ENV-ERROR' "$doc" || log_fail "$doc missing the Windows-neither-available platform-matrix row"
  done

  log_pass "5-row platform matrix present in both wrapper headers and docs/TECHNOLOGY.md (TEST-009)"
}

# --- TEST-013 (Spec-AC-10): Manual verification protocol documented ----------

test_013() {
  log_info "TEST-013: MV-1..3 manual verification protocol section documented in the frozen spec (doc-presence only; execution is manual, off-host)..."

  grep -qF "## Manual verification protocol" "$SPEC_DOC" \
    || log_fail "SPEC-0046 must carry a '## Manual verification protocol' section"
  grep -qF "MV-1" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-1"
  grep -qF "MV-2" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-2"
  grep -qF "MV-3" "$SPEC_DOC" || log_fail "SPEC-0046 must document MV-3"
  grep -qiE "residual risk" "$SPEC_DOC" \
    || log_fail "SPEC-0046 must record the residual risk (Windows-host semantics unverified in this repo)"

  log_pass "Manual verification protocol section documented; execution remains off-host (TEST-013)"
}

ALL_TESTS="007 009 013"

main() {
  echo "Testing $TEST_NAME (Windows fallback: MSYS branch, platform matrix, MV protocol doc-presence)"
  check_deps
  local selected="$*"
  [[ -n "$selected" ]] || selected="$ALL_TESTS"
  local t
  for t in $selected; do
    t="${t#TEST-}"
    "test_${t}"
  done
  echo ""
  log_pass "All selected $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
