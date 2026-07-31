#!/usr/bin/env bash
#
# Test: implementation-mode-choice (SPEC spec-implementation-mode-choice)
# Grep-contract suite for the user-facing implementation-mode choice surfaced at
# the end of intake and honored downstream: the intake choice block, the
# PLANNING respect-clause, the IMPLEMENTATION direct/untested lanes, the SKILL_TDD
# non-TDD-lane hand-off, and the VALIDATION strategy-conditional evidence prose.
# The state.mjs / orchestration-dispatch enum behavior is covered by
# test-aai-state.sh and test-aai-orchestration-dispatch.sh; here we pin the
# producer/consumer SEAM (both enums must include the new values).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-implementation-mode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

INTAKE_COMMON=".aai/INTAKE_COMMON.md"
SKILL_INTAKE=".aai/SKILL_INTAKE.prompt.md"
PLANNING=".aai/PLANNING.prompt.md"
IMPLEMENTATION=".aai/IMPLEMENTATION.prompt.md"
SKILL_TDD=".aai/SKILL_TDD.prompt.md"
VALIDATION=".aai/VALIDATION.prompt.md"
STATE_MJS=".aai/scripts/state.mjs"
DISPATCH=".aai/scripts/orchestration-dispatch.mjs"

FAILED=0
log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v grep >/dev/null 2>&1 || log_skip "grep not found"
  [[ -d .aai ]] || log_skip ".aai directory not found"
}

# TEST-001 — intake choice block: single-sourced in INTAKE_COMMON.md, 3 options,
# set-strategy --source intake recording, and the back-compat no-choice path.
test_001_intake_block() {
  local ok=1
  [[ -f "$INTAKE_COMMON" ]] || { log_fail "TEST-001 $INTAKE_COMMON missing"; return; }
  local n
  n=$(grep -cF "## IMPLEMENTATION MODE CHOICE" "$INTAKE_COMMON" || true)
  [[ "$n" == "1" ]] || { log_info "TEST-001: heading appears $n times (want 1)"; ok=0; }
  grep -qiF "Full TDD loop" "$INTAKE_COMMON" || { log_info "TEST-001: missing option 1 (full TDD loop)"; ok=0; }
  grep -qiF "Direct + targeted tests" "$INTAKE_COMMON" || { log_info "TEST-001: missing option 2 (direct + targeted tests)"; ok=0; }
  grep -qiF "Direct without tests" "$INTAKE_COMMON" || { log_info "TEST-001: missing option 3 (direct without tests)"; ok=0; }
  grep -qF "set-strategy --selected <tdd|direct|untested>" "$INTAKE_COMMON" \
    || { log_info "TEST-001: missing set-strategy recording line"; ok=0; }
  grep -qF -- "--source intake" "$INTAKE_COMMON" || { log_info "TEST-001: choice must be recorded with --source intake"; ok=0; }
  grep -qiF "recommend" "$INTAKE_COMMON" || { log_info "TEST-001: block must carry a recommendation"; ok=0; }
  grep -qiF "does NOT choose" "$INTAKE_COMMON" || { log_info "TEST-001: back-compat no-choice path missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001 intake choice block single-sourced with 3 options + recommendation + back-compat" \
    || log_fail "TEST-001 intake choice block"
}

# TEST-002 — SKILL_INTAKE surfaces the choice at end of flow and points at the block.
test_002_skill_intake_wiring() {
  local ok=1
  [[ -f "$SKILL_INTAKE" ]] || { log_fail "TEST-002 $SKILL_INTAKE missing"; return; }
  grep -qF "IMPLEMENTATION MODE CHOICE" "$SKILL_INTAKE" || { log_info "TEST-002: SKILL_INTAKE does not apply the choice block"; ok=0; }
  # Bot-review ordering contract: the choice is asked BEFORE the INTAKE COMPLETE
  # output (asking after reads as done and gets skipped) — pin the step comes
  # before the confirm block in file order.
  local choice_ln confirm_ln
  choice_ln=$(grep -n "IMPLEMENTATION MODE CHOICE" "$SKILL_INTAKE" | head -1 | cut -d: -f1)
  confirm_ln=$(grep -n "INTAKE COMPLETE" "$SKILL_INTAKE" | head -1 | cut -d: -f1)
  { [[ -n "$choice_ln" && -n "$confirm_ln" && "$choice_ln" -lt "$confirm_ln" ]]; } \
    || { log_info "TEST-002: choice step must precede the INTAKE COMPLETE output (choice=$choice_ln confirm=$confirm_ln)"; ok=0; }
  grep -qF "five blocks" "$SKILL_INTAKE" || { log_info "TEST-002: SHARED POLICY must name five blocks"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-002 SKILL_INTAKE surfaces the choice before the completion output" || log_fail "TEST-002 SKILL_INTAKE wiring"
}

# TEST-003 — PLANNING respects a pre-recorded intake choice + enum extended.
test_003_planning_respect() {
  local ok=1
  [[ -f "$PLANNING" ]] || { log_fail "TEST-003 $PLANNING missing"; return; }
  grep -qF "RESPECT A PRE-RECORDED INTAKE CHOICE" "$PLANNING" || { log_info "TEST-003: missing respect-clause"; ok=0; }
  grep -qF "source: intake" "$PLANNING" || { log_info "TEST-003: respect-clause must key off source: intake"; ok=0; }
  grep -qF "loop|tdd|hybrid|direct|untested" "$PLANNING" || { log_info "TEST-003: set-strategy enum not extended"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003 PLANNING respects intake choice, enum extended" || log_fail "TEST-003 PLANNING respect-clause"
}

# TEST-004 — IMPLEMENTATION honors both cheap lanes.
test_004_implementation_lanes() {
  local ok=1
  [[ -f "$IMPLEMENTATION" ]] || { log_fail "TEST-004 $IMPLEMENTATION missing"; return; }
  # direct: implement first, targeted regression tests, no RED-first ceremony
  grep -qiF "targeted regression tests" "$IMPLEMENTATION" || { log_info "TEST-004: direct lane must add targeted regression tests"; ok=0; }
  grep -qiF "No RED-first ceremony" "$IMPLEMENTATION" || { log_info "TEST-004: direct lane must drop RED-first ceremony"; ok=0; }
  # untested: NO test files + rationale visible in hand-off
  grep -qF "write NO test files" "$IMPLEMENTATION" || { log_info "TEST-004: untested lane must write NO test files"; ok=0; }
  grep -qF "implementation_strategy.rationale" "$IMPLEMENTATION" || { log_info "TEST-004: untested lane must surface the recorded rationale"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004 IMPLEMENTATION honors direct + untested lanes" || log_fail "TEST-004 IMPLEMENTATION lanes"
}

# TEST-005 — SKILL_TDD routes non-TDD lanes away from RED.
test_005_tdd_routes_away() {
  local ok=1
  [[ -f "$SKILL_TDD" ]] || { log_fail "TEST-005 $SKILL_TDD missing"; return; }
  grep -qF "do NOT start RED" "$SKILL_TDD" || { log_info "TEST-005: non-TDD lanes must not start RED"; ok=0; }
  grep -qiF "direct" "$SKILL_TDD" && grep -qiF "untested" "$SKILL_TDD" \
    || { log_info "TEST-005: SKILL_TDD must name both direct and untested lanes"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-005 SKILL_TDD routes direct/untested to Implementation" || log_fail "TEST-005 SKILL_TDD routing"
}

# TEST-006 — VALIDATION evidence demand is strategy-conditional; tdd/hybrid never weakened.
test_006_validation_conditional() {
  local ok=1
  [[ -f "$VALIDATION" ]] || { log_fail "TEST-006 $VALIDATION missing"; return; }
  grep -qF "STRATEGY-CONDITIONAL EVIDENCE" "$VALIDATION" || { log_info "TEST-006: missing strategy-conditional block"; ok=0; }
  # L3-review hardening: pin the tdd/hybrid clause by its FULL literal line —
  # a bare "UNCHANGED" grep was rescued by an unrelated pre-existing line
  # (mutation-proven), so a targeted weakening of THIS clause escaped. The full
  # phrase can only be satisfied by the clause itself.
  grep -qF 'tdd` / `hybrid` -> UNCHANGED: step 5g applies in full (RED-proof, RED_CLASS,' "$VALIDATION" \
    || { log_info "TEST-006: tdd/hybrid clause must state UNCHANGED step 5g in full (literal pin)"; ok=0; }
  grep -qiF "TARGETED-TEST evidence" "$VALIDATION" || { log_info "TEST-006: direct lane needs targeted-test evidence"; ok=0; }
  grep -qiF "DECLARED-VERIFICATION evidence" "$VALIDATION" || { log_info "TEST-006: untested lane needs declared-verification evidence"; ok=0; }
  # The conditionality must key off the RECORDED strategy in STATE, not a claim
  # (anti-gaming anchor from the L3 review).
  grep -qF 'implementation_strategy.selected' "$VALIDATION" \
    || { log_info "TEST-006: conditionality must key off implementation_strategy.selected"; ok=0; }
  # 5g's existing tdd-evidence contract must survive verbatim (Seam with tdd-evidence suite)
  grep -qF "tdd-evidence-check.mjs" "$VALIDATION" || { log_info "TEST-006: step 5g tdd-evidence-check.mjs contract regressed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006 VALIDATION evidence is strategy-conditional, tdd/hybrid intact" || log_fail "TEST-006 VALIDATION conditionality"
}

# TEST-007 — SEAM: the strategy enum is consistent across the producer (state.mjs
# set-strategy) and the consumer (orchestration-dispatch checkEnum). A value the
# CLI writes but the dispatcher rejects would strand the loop; pin both.
test_007_enum_seam() {
  local ok=1 f
  for f in "$STATE_MJS" "$DISPATCH"; do
    [[ -f "$f" ]] || { log_info "TEST-007: $f missing"; ok=0; continue; }
    grep -qE "STRATEGIES = \[.*'direct'.*'untested'.*\]" "$f" \
      || { log_info "TEST-007: $f STRATEGIES must include 'direct' and 'untested'"; ok=0; }
  done
  # untested guard is documented in the CLI header so the requirement is discoverable
  grep -qF "untested requires a non-empty --rationale" "$STATE_MJS" \
    || { log_info "TEST-007: state.mjs must enforce untested rationale"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-007 strategy enum consistent across producer/consumer + untested guard" || log_fail "TEST-007 enum seam"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="
  check_deps
  test_001_intake_block
  test_002_skill_intake_wiring
  test_003_planning_respect
  test_004_implementation_lanes
  test_005_tdd_routes_away
  test_006_validation_conditional
  test_007_enum_seam
  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
