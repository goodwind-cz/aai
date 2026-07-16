#!/usr/bin/env bash
#
# Test: verification-before-completion gate skill
# Grep-wiring suite for .aai/SKILL_VERIFY.prompt.md (new gate prompt), its
# wiring into IMPLEMENTATION/VALIDATION/SKILL_TDD, its three agent-tree
# wrappers, and the two survival invariants it must not break (prompt-diet
# byte floor, repo-wide strict docs audit).
#
# Covers TEST-001..008 from
# docs/specs/SPEC-DRAFT-verification-before-completion.md.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-verify-gate"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

GATE_FILE=".aai/SKILL_VERIFY.prompt.md"

# Byte baseline shared with tests/skills/test-aai-prompt-diet.sh TEST-010
# (same formula, re-measured here per spec D2/TEST-006 — Seam S1).
BASELINE_PROMPT_BYTES=357457
REQUIRED_REDUCTION_BYTES=28672   # 28 KB

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

# TEST-001 — SKILL_VERIFY.prompt.md exists and wc -l <= 120
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

# TEST-002 — literal ordered gate chain present
test_002_gate_chain() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-002 $GATE_FILE does not exist"
    return
  fi
  if grep -qF "IDENTIFY → RUN → READ → VERIFY → CLAIM" "$GATE_FILE"; then
    log_pass "TEST-002 gate chain literal present"
  else
    log_fail "TEST-002 gate chain literal 'IDENTIFY → RUN → READ → VERIFY → CLAIM' missing"
  fi
}

# TEST-003 — rationalization table has >= 6 data rows (pipe-rows minus header/separator)
test_003_rationalization_table() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-003 $GATE_FILE does not exist"
    return
  fi
  # Count lines that look like markdown table rows (start with |) after the
  # rationalization heading, then subtract 2 for header + separator.
  local section total data
  section=$(awk '/[Rr]ationalization [Tt]able/{found=1} found' "$GATE_FILE")
  total=$(printf '%s\n' "$section" | grep -c '^\s*|')
  data=$((total - 2))
  if [[ "$data" -ge 6 ]]; then
    log_pass "TEST-003 rationalization table has $data data rows (>= 6)"
  else
    log_fail "TEST-003 rationalization table has $data data rows (< 6, total pipe-rows=$total)"
  fi
}

# TEST-004 — verify-subagent-reports-via-diff rule present (names subagent + git diff)
test_004_subagent_diff_rule() {
  if [[ ! -f "$GATE_FILE" ]]; then
    log_fail "TEST-004 $GATE_FILE does not exist"
    return
  fi
  local ok=1
  grep -qi "subagent" "$GATE_FILE" || ok=0
  grep -qF "git diff" "$GATE_FILE" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-004 subagent-reports-via-diff rule present" \
    || log_fail "TEST-004 subagent-reports-via-diff rule missing (need both 'subagent' and 'git diff')"
}

# TEST-005 — each of IMPLEMENTATION/VALIDATION/SKILL_TDD has >=1 and <=2
# SKILL_VERIFY lines; old marker absent from IMPLEMENTATION (S3: move, not loss)
test_005_wiring_pointers() {
  local ok=1 f n
  local files=(.aai/IMPLEMENTATION.prompt.md .aai/VALIDATION.prompt.md .aai/SKILL_TDD.prompt.md)
  for f in "${files[@]}"; do
    if [[ ! -f "$f" ]]; then
      log_info "TEST-005: $f does not exist"
      ok=0
      continue
    fi
    n=$(grep -c "SKILL_VERIFY" "$f" || true)
    if [[ "$n" -lt 1 || "$n" -gt 2 ]]; then
      log_info "TEST-005: $f has $n SKILL_VERIFY lines (want 1-2)"
      ok=0
    fi
  done
  if [[ -f .aai/IMPLEMENTATION.prompt.md ]] && grep -qF "Forbidden language in completion reports" .aai/IMPLEMENTATION.prompt.md; then
    log_info "TEST-005: old marker 'Forbidden language in completion reports' still present in IMPLEMENTATION.prompt.md"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-005 IMPLEMENTATION/VALIDATION/SKILL_TDD wiring pointers" \
    || log_fail "TEST-005 wiring pointers"
}

# TEST-006 — prompt-diet byte formula re-measured post-change (Seam S1 survival invariant)
test_006_prompt_diet_floor() {
  local after extra reduction
  after=$(cat .aai/*.prompt.md 2>/dev/null | wc -c | tr -d ' ')
  extra=0
  [[ -f .aai/INTAKE_COMMON.md ]] && extra=$((extra + $(wc -c < .aai/INTAKE_COMMON.md)))
  [[ -f .aai/STATE_FALLBACK.md ]] && extra=$((extra + $(wc -c < .aai/STATE_FALLBACK.md)))
  reduction=$((BASELINE_PROMPT_BYTES - after - extra))
  if [[ "$reduction" -ge "$REQUIRED_REDUCTION_BYTES" ]]; then
    log_pass "TEST-006 prompt-diet floor holds (net reduction $reduction bytes >= $REQUIRED_REDUCTION_BYTES)"
  else
    log_fail "TEST-006 prompt-diet floor broken (net reduction $reduction bytes < $REQUIRED_REDUCTION_BYTES; after=$after, new files=$extra)"
  fi
}

# TEST-007 — aai-verify/SKILL.md exists in all three agent trees with name +
# pointer to .aai/SKILL_VERIFY.prompt.md
test_007_wrappers() {
  local ok=1 dir f
  for dir in .claude .codex .gemini; do
    f="$dir/skills/aai-verify/SKILL.md"
    if [[ ! -f "$f" ]]; then
      log_info "TEST-007: $f does not exist"
      ok=0
      continue
    fi
    if ! grep -qE "^name:[[:space:]]*aai-verify[[:space:]]*$" "$f"; then
      log_info "TEST-007: $f missing 'name: aai-verify' frontmatter"
      ok=0
    fi
    if ! grep -qF ".aai/SKILL_VERIFY.prompt.md" "$f"; then
      log_info "TEST-007: $f missing pointer to .aai/SKILL_VERIFY.prompt.md"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-007 aai-verify wrappers x3 trees" || log_fail "TEST-007 aai-verify wrappers"
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
  test_002_gate_chain
  test_003_rationalization_table
  test_004_subagent_diff_rule
  test_005_wiring_pointers
  test_006_prompt_diet_floor
  test_007_wrappers
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
