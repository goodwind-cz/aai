#!/usr/bin/env bash
#
# Test: systematic-debugging gate skill
# Grep-wiring suite for .aai/SKILL_DEBUG.prompt.md (root-cause-first debugging
# protocol), its wiring into REMEDIATION (before the fix step, no obligation
# lost), its three agent-tree wrappers, and the two survival invariants it
# must not break (prompt-diet byte floor, repo-wide strict docs audit).
#
# Covers TEST-001..008 from docs/specs/SPEC-DRAFT-systematic-debugging.md.
#
# Shared-baseline caveat: the prompt-diet byte baseline constants live in
# tests/skills/test-aai-prompt-diet.sh (TEST-010) and are deliberately NOT
# duplicated here — TEST-007 asserts the floor by running that suite itself;
# this suite's own stanzas are existence/content greps only.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-debug-gate"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

GATE_FILE=".aai/SKILL_DEBUG.prompt.md"
REMEDIATION_FILE=".aai/REMEDIATION.prompt.md"

FAILED=0

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -d .aai ]] || log_skip ".aai directory not found"
}

# TEST-001 — SKILL_DEBUG.prompt.md exists and wc -l <= 120
test_001_exists_and_line_budget() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-001 $GATE_FILE does not exist"
    return
  fi
  local n
  n=$(wc -l < "$GATE_FILE" | tr -d ' ')
  if [[ "$n" -le 120 ]]; then
    log_pass "TEST-001 $GATE_FILE exists, $n lines (<= 120)"
  else
    log_fail "TEST-001 $GATE_FILE is $n lines (> 120)"
  fi
}

# TEST-002 — literal ordered protocol chain present
test_002_protocol_chain() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-002 $GATE_FILE does not exist"
    return
  fi
  if grep -qF "READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE" "$GATE_FILE"; then
    log_pass "TEST-002 protocol chain literal present"
  else
    log_fail "TEST-002 protocol chain literal 'READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE' missing"
  fi
}

# TEST-003 — rationalization table has >= 5 data rows (pipe-rows minus header/separator)
test_003_rationalization_table() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-003 $GATE_FILE does not exist"
    return
  fi
  local section total data
  # Review NB-1: bound the extraction at the NEXT '## ' heading — an unbounded
  # to-EOF slice would count pipe-rows from any later table and falsely pass.
  section=$(awk '/[Rr]ationalization [Tt]able/{found=1; print; next} found && /^## /{exit} found' "$GATE_FILE")
  total=$(printf '%s\n' "$section" | grep -c '^\s*|')
  data=$((total - 2))
  if [[ "$data" -ge 5 ]]; then
    log_pass "TEST-003 rationalization table has $data data rows (>= 5)"
  else
    log_fail "TEST-003 rationalization table has $data data rows (< 5, total pipe-rows=$total)"
  fi
}

# TEST-004 — cross-link to the completion-side gate (SKILL_VERIFY) present
test_004_verify_cross_link() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-004 $GATE_FILE does not exist"
    return
  fi
  if grep -qF ".aai/SKILL_VERIFY.prompt.md" "$GATE_FILE"; then
    log_pass "TEST-004 SKILL_VERIFY cross-link present"
  else
    log_fail "TEST-004 cross-link to .aai/SKILL_VERIFY.prompt.md missing"
  fi
}

# TEST-005 — REMEDIATION wiring: 1-2 SKILL_DEBUG lines, placed BEFORE the fix
# step; existing obligations survive (S3: additive wiring, no loss)
test_005_remediation_wiring() {
  if [[ ! -f "$REMEDIATION_FILE" ]]; then
    log_fail "TEST-005 $REMEDIATION_FILE does not exist"
    return
  fi
  local ok=1 n wire_line fix_line m
  n=$(grep -c "SKILL_DEBUG" "$REMEDIATION_FILE" || true)
  if [[ "$n" -lt 1 || "$n" -gt 2 ]]; then
    log_info "TEST-005: $REMEDIATION_FILE has $n SKILL_DEBUG lines (want 1-2)"
    ok=0
  fi
  wire_line=$(grep -n "SKILL_DEBUG" "$REMEDIATION_FILE" | head -1 | cut -d: -f1)
  fix_line=$(grep -nF "Apply fixes in order" "$REMEDIATION_FILE" | head -1 | cut -d: -f1)
  if [[ -z "$fix_line" ]]; then
    log_info "TEST-005: fix-step marker 'Apply fixes in order' missing (obligation lost?)"
    ok=0
  elif [[ -z "$wire_line" || "$wire_line" -ge "$fix_line" ]]; then
    log_info "TEST-005: wiring (line ${wire_line:-none}) is not before the fix step (line $fix_line)"
    ok=0
  fi
  # Obligation-survival markers: fix ordering, both reset-block transitions,
  # and the no-loop stop rule must remain intact.
  for m in "reset-block last_validation" "reset-block code_review" "Do NOT loop"; do
    if ! grep -qF "$m" "$REMEDIATION_FILE"; then
      log_info "TEST-005: obligation marker '$m' missing from REMEDIATION"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-005 REMEDIATION wiring before fix step, obligations intact" \
    || log_fail "TEST-005 REMEDIATION wiring"
}

# TEST-006 — aai-debug/SKILL.md exists in all three agent trees with name +
# pointer to .aai/SKILL_DEBUG.prompt.md
test_006_wrappers() {
  local ok=1 dir f
  for dir in .claude .codex .gemini; do
    f="$dir/skills/aai-debug/SKILL.md"
    if [[ ! -f "$f" ]]; then
      log_info "TEST-006: $f does not exist"
      ok=0
      continue
    fi
    if ! grep -qE "^name:[[:space:]]*aai-debug[[:space:]]*$" "$f"; then
      log_info "TEST-006: $f missing 'name: aai-debug' frontmatter"
      ok=0
    fi
    if ! grep -qF ".aai/SKILL_DEBUG.prompt.md" "$f"; then
      log_info "TEST-006: $f missing pointer to .aai/SKILL_DEBUG.prompt.md"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-006 aai-debug wrappers x3 trees" || log_fail "TEST-006 aai-debug wrappers"
}

# TEST-007 — prompt-diet floor holds post-change, asserted via the owning
# suite itself (Seam S1; baseline constants not duplicated here)
test_007_prompt_diet_suite() {
  if [[ ! -f tests/skills/test-aai-prompt-diet.sh ]]; then
    log_fail "TEST-007 tests/skills/test-aai-prompt-diet.sh not found"
    return
  fi
  if bash tests/skills/test-aai-prompt-diet.sh >/dev/null 2>&1; then
    log_pass "TEST-007 prompt-diet suite green (byte floor holds)"
  else
    log_fail "TEST-007 prompt-diet suite failed (byte floor or wiring broken)"
  fi
}

# TEST-008 — repo-wide strict docs audit exits 0 (Seam S4)
test_008_strict_audit() {
  if node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1; then
    log_pass "TEST-008 repo-wide strict docs audit exits 0"
  else
    log_fail "TEST-008 repo-wide strict docs audit failed"
  fi
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_exists_and_line_budget
  test_002_protocol_chain
  test_003_rationalization_table
  test_004_verify_cross_link
  test_005_remediation_wiring
  test_006_wrappers
  test_007_prompt_diet_suite
  test_008_strict_audit

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
