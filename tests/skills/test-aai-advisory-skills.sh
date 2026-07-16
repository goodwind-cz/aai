#!/usr/bin/env bash
#
# Test: three optional advisory skills (scout / deslop / interrogate)
# Grep-wiring suite for .aai/SKILL_SCOUT.prompt.md, .aai/SKILL_DESLOP.prompt.md,
# .aai/SKILL_INTERROGATE.prompt.md (pro-workflow patterns per RES-0001 P3
# rec 15), their nine agent-tree wrappers, catalog rows, the advisory-isolation
# invariant (no gate/dispatch/workflow surface may reference them), and the two
# survival invariants (prompt-diet byte floor, repo-wide strict docs audit).
#
# Covers TEST-001..014 from docs/specs/SPEC-DRAFT-advisory-skills.md.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-advisory-skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCOUT=".aai/SKILL_SCOUT.prompt.md"
DESLOP=".aai/SKILL_DESLOP.prompt.md"
INTERROGATE=".aai/SKILL_INTERROGATE.prompt.md"
DISCLAIMER="ADVISORY ONLY — this skill never blocks, gates, or dispatches anything"

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

# Shared: file exists and wc -l <= 100
check_exists_and_budget() {
  local test_id="$1" f="$2" n
  if [[ ! -f "$f" ]]; then
    log_fail "$test_id $f does not exist"
    return 1
  fi
  n=$(wc -l < "$f" | tr -d ' ')
  if [[ "$n" -le 100 ]]; then
    log_pass "$test_id $f exists, $n lines (<= 100)"
  else
    log_fail "$test_id $f is $n lines (> 100)"
  fi
}

# TEST-001 — SKILL_SCOUT exists and <= 100 lines
test_001_scout_exists() { check_exists_and_budget "TEST-001" "$SCOUT" || true; }

# TEST-002 — scout core mechanism: 5 named dimensions, 0-100 scale, GO/HOLD at 70
test_002_scout_mechanism() {
  if [[ ! -f "$SCOUT" ]]; then log_fail "TEST-002 $SCOUT does not exist"; return; fi
  local ok=1 dim
  for dim in "Scope clarity" "Pattern familiarity" "Dependency awareness" \
             "Edge cases" "Test strategy"; do
    grep -qF "$dim" "$SCOUT" || { log_info "TEST-002: dimension '$dim' missing"; ok=0; }
  done
  grep -qE "0(–|-)100" "$SCOUT" || { log_info "TEST-002: 0-100 scale missing"; ok=0; }
  grep -qE "GO" "$SCOUT" && grep -qE "HOLD" "$SCOUT" \
    || { log_info "TEST-002: GO/HOLD verdicts missing"; ok=0; }
  grep -E "GO|HOLD" "$SCOUT" | grep -q "70" \
    || { log_info "TEST-002: threshold 70 not on a GO/HOLD line"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-002 scout 5 dimensions + 0-100 + GO/HOLD@70" \
    || log_fail "TEST-002 scout core mechanism"
}

# TEST-003 — scout advisory disclaimer (never blocks)
test_003_scout_advisory() {
  if [[ ! -f "$SCOUT" ]]; then log_fail "TEST-003 $SCOUT does not exist"; return; fi
  if grep -qF "$DISCLAIMER" "$SCOUT"; then
    log_pass "TEST-003 scout ADVISORY disclaimer present"
  else
    log_fail "TEST-003 scout ADVISORY disclaimer missing"
  fi
}

# TEST-004 — SKILL_DESLOP exists and <= 100 lines
test_004_deslop_exists() { check_exists_and_budget "TEST-004" "$DESLOP" || true; }

# TEST-005 — deslop slop-class table >= 5 data rows naming the five classes
test_005_deslop_table() {
  if [[ ! -f "$DESLOP" ]]; then log_fail "TEST-005 $DESLOP does not exist"; return; fi
  local ok=1 section total data cls
  # Bound extraction at the next ## heading (lesson from debug-gate review).
  section=$(awk '/[Ss]lop-class table/{found=1; next} /^## /{if(found) exit} found' "$DESLOP")
  total=$(printf '%s\n' "$section" | grep -c '^\s*|')
  data=$((total - 2))
  if [[ "$data" -lt 5 ]]; then
    log_info "TEST-005: slop-class table has $data data rows (< 5, total pipe-rows=$total)"
    ok=0
  fi
  for cls in "comment" "try/catch" "abstraction" "unrequested" "untouched"; do
    grep -qi "$cls" "$DESLOP" || { log_info "TEST-005: slop class keyword '$cls' missing"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-005 deslop slop-class table ($data rows >= 5, 5 classes named)" \
    || log_fail "TEST-005 deslop slop-class table"
}

# TEST-006 — deslop behavior-unchanged rule + SKILL_VERIFY cross-link + disclaimer
test_006_deslop_rules() {
  if [[ ! -f "$DESLOP" ]]; then log_fail "TEST-006 $DESLOP does not exist"; return; fi
  local ok=1
  grep -qi "behavior.unchanged" "$DESLOP" || { log_info "TEST-006: behavior-unchanged rule missing"; ok=0; }
  grep -qF "aai-run-tests.sh" "$DESLOP" || { log_info "TEST-006: aai-run-tests.sh runner missing"; ok=0; }
  grep -qF ".aai/SKILL_VERIFY.prompt.md" "$DESLOP" || { log_info "TEST-006: SKILL_VERIFY cross-link missing"; ok=0; }
  grep -qF "$DISCLAIMER" "$DESLOP" || { log_info "TEST-006: ADVISORY disclaimer missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006 deslop behavior-unchanged + VERIFY link + disclaimer" \
    || log_fail "TEST-006 deslop rules"
}

# TEST-007 — SKILL_INTERROGATE exists and <= 100 lines
test_007_interrogate_exists() { check_exists_and_budget "TEST-007" "$INTERROGATE" || true; }

# TEST-008 — interrogate one-question rule + recommended-answer rule
test_008_interrogate_rules() {
  if [[ ! -f "$INTERROGATE" ]]; then log_fail "TEST-008 $INTERROGATE does not exist"; return; fi
  local ok=1
  grep -qi "ONE QUESTION AT A TIME" "$INTERROGATE" || { log_info "TEST-008: one-question rule missing"; ok=0; }
  grep -qi "EVERY question" "$INTERROGATE" || { log_info "TEST-008: EVERY-question literal missing"; ok=0; }
  grep -qi "recommended answer" "$INTERROGATE" || { log_info "TEST-008: recommended-answer rule missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-008 interrogate one-question + recommended-answer rules" \
    || log_fail "TEST-008 interrogate rules"
}

# TEST-009 — interrogate codebase-first resolution + ledger output + disclaimer
test_009_interrogate_ledger() {
  if [[ ! -f "$INTERROGATE" ]]; then log_fail "TEST-009 $INTERROGATE does not exist"; return; fi
  local ok=1
  grep -qF "inferred: <path>" "$INTERROGATE" || { log_info "TEST-009: 'inferred: <path>' resolution missing"; ok=0; }
  grep -qF "docs/ai/decisions.jsonl" "$INTERROGATE" || { log_info "TEST-009: decisions.jsonl ledger target missing"; ok=0; }
  grep -qF '"type":"planning_decision"' "$INTERROGATE" || { log_info "TEST-009: ledger line format missing"; ok=0; }
  # Review NB-1: pin the ref_id key — the validation-caught ref/ref_id defect
  # must not be able to regress with the suite green.
  grep -qF '"ref_id"' "$INTERROGATE" || { log_info "TEST-009: ledger line must key the reference as ref_id (decisions.jsonl convention)"; ok=0; }
  grep -qF "$DISCLAIMER" "$INTERROGATE" || { log_info "TEST-009: ADVISORY disclaimer missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-009 interrogate inferred-path + ledger format + disclaimer" \
    || log_fail "TEST-009 interrogate ledger"
}

# TEST-010 — nine wrappers: 3 skills x .claude/.codex/.gemini, name + pointer
test_010_wrappers() {
  local ok=1 skill dir f prompt
  for skill in aai-scout aai-deslop aai-interrogate; do
    case "$skill" in
      aai-scout)       prompt=".aai/SKILL_SCOUT.prompt.md" ;;
      aai-deslop)      prompt=".aai/SKILL_DESLOP.prompt.md" ;;
      aai-interrogate) prompt=".aai/SKILL_INTERROGATE.prompt.md" ;;
    esac
    for dir in .claude .codex .gemini; do
      f="$dir/skills/$skill/SKILL.md"
      if [[ ! -f "$f" ]]; then
        log_info "TEST-010: $f does not exist"
        ok=0
        continue
      fi
      grep -qE "^name:[[:space:]]*$skill[[:space:]]*$" "$f" \
        || { log_info "TEST-010: $f missing 'name: $skill' frontmatter"; ok=0; }
      grep -qF "$prompt" "$f" \
        || { log_info "TEST-010: $f missing pointer to $prompt"; ok=0; }
    done
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-010 advisory wrappers x9 (3 skills x 3 trees)" \
    || log_fail "TEST-010 advisory wrappers"
}

# TEST-011 — catalog rows: SKILLS.md x3 + .aai/AGENTS.md Follow lines x3
test_011_catalogs() {
  local ok=1 skill prompt
  for skill in aai-scout aai-deslop aai-interrogate; do
    grep -qE "^\| $skill \|" SKILLS.md \
      || { log_info "TEST-011: SKILLS.md row for $skill missing"; ok=0; }
  done
  for prompt in SKILL_SCOUT SKILL_DESLOP SKILL_INTERROGATE; do
    grep -qE "^Follow \.aai/$prompt\.prompt\.md" .aai/AGENTS.md \
      || { log_info "TEST-011: .aai/AGENTS.md Follow line for $prompt missing"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-011 SKILLS.md rows x3 + AGENTS.md Follow lines x3" \
    || log_fail "TEST-011 catalog rows"
}

# TEST-012 — advisory isolation: prompts carry the disclaimer AND no
# gate/dispatch/workflow surface references the new skills (Seam S3 / AC-002)
test_012_advisory_isolation() {
  local ok=1 f
  for f in "$SCOUT" "$DESLOP" "$INTERROGATE"; do
    if [[ ! -f "$f" ]] || ! grep -qF "$DISCLAIMER" "$f"; then
      log_info "TEST-012: $f missing or lacks ADVISORY disclaimer"
      ok=0
    fi
  done
  local surfaces=(
    .aai/ORCHESTRATION.prompt.md
    .aai/ORCHESTRATION_PARALLEL.prompt.md
    .aai/ORCHESTRATION_HITL.prompt.md
    .aai/scripts/orchestration-dispatch.mjs
    .aai/scripts/orchestration-mode.mjs
    .aai/workflow/WORKFLOW.md
  )
  for f in "${surfaces[@]}"; do
    if [[ ! -f "$f" ]]; then
      log_info "TEST-012: expected gate/dispatch surface $f not found"
      ok=0
      continue
    fi
    if grep -qE "SKILL_SCOUT|SKILL_DESLOP|SKILL_INTERROGATE|aai-scout|aai-deslop|aai-interrogate" "$f"; then
      log_info "TEST-012: $f references an advisory skill (must stay unwired)"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-012 advisory isolation (disclaimers present, gate/dispatch surfaces unwired)" \
    || log_fail "TEST-012 advisory isolation"
}

# TEST-013 — prompt-diet byte floor holds post-change (Seam S1; runs the real suite)
test_013_prompt_diet_floor() {
  if bash tests/skills/test-aai-prompt-diet.sh >/dev/null 2>&1; then
    log_pass "TEST-013 prompt-diet suite exits 0 (byte floor holds)"
  else
    log_fail "TEST-013 prompt-diet suite failed (byte floor broken?)"
  fi
}

# TEST-014 — repo-wide strict docs audit exits 0 (Seam S4)
test_014_strict_audit() {
  if node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1; then
    log_pass "TEST-014 repo-wide strict docs audit exits 0"
  else
    log_fail "TEST-014 repo-wide strict docs audit failed"
  fi
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_scout_exists
  test_002_scout_mechanism
  test_003_scout_advisory
  test_004_deslop_exists
  test_005_deslop_table
  test_006_deslop_rules
  test_007_interrogate_exists
  test_008_interrogate_rules
  test_009_interrogate_ledger
  test_010_wrappers
  test_011_catalogs
  test_012_advisory_isolation
  test_013_prompt_diet_floor
  test_014_strict_audit

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
