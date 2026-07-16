#!/usr/bin/env bash
#
# Test: project constitution with justified-exception tracking
# Grep-wiring suite for docs/CONSTITUTION.md (ratified principles, spec-kit
# pattern per RES-0001 P2 rec 10), the PLANNING freeze-step article check
# ("Constitution deviations" recorded in the spec — accountable deviation,
# spec-kit Complexity Tracking), the SPEC_TEMPLATE optional section, the
# AGENTS.md canonical-sources line, and the survival invariants the change
# must not break (legacy specs unflagged, prompt-diet byte floor, repo-wide
# strict docs audit).
#
# Covers TEST-001..010 from docs/specs/SPEC-DRAFT-constitution.md.
#
# Shared-baseline caveat: the prompt-diet byte baseline constants live in
# tests/skills/test-aai-prompt-diet.sh (TEST-010) and are deliberately NOT
# duplicated here — TEST-009 asserts the floor by running that suite itself;
# this suite's own stanzas are existence/content greps only.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-constitution"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

DOC_FILE="docs/CONSTITUTION.md"
PLANNING_FILE=".aai/PLANNING.prompt.md"
TEMPLATE_FILE=".aai/templates/SPEC_TEMPLATE.md"
AGENTS_FILE=".aai/AGENTS.md"

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

# TEST-001 — docs/CONSTITUTION.md exists and wc -l <= 60
test_001_exists_and_line_budget() {
  if [[ ! -f "$DOC_FILE" ]]; then
    log_fail "TEST-001 $DOC_FILE does not exist"
    return
  fi
  local n
  n=$(wc -l < "$DOC_FILE" | tr -d ' ')
  if [[ "$n" -le 60 ]]; then
    log_pass "TEST-001 $DOC_FILE exists, $n lines (<= 60)"
  else
    log_fail "TEST-001 $DOC_FILE is $n lines (> 60)"
  fi
}

# TEST-002 — >= 6 numbered articles, each carrying a source pointer "(see: ...)"
test_002_articles_with_pointers() {
  if [[ ! -f "$DOC_FILE" ]]; then
    log_fail "TEST-002 $DOC_FILE does not exist"
    return
  fi
  local articles pointered
  articles=$(grep -cE '^[0-9]+\. ' "$DOC_FILE" || true)
  pointered=$(grep -cE '^[0-9]+\. .*\(see: .+\)' "$DOC_FILE" || true)
  if [[ "$articles" -ge 6 && "$pointered" -eq "$articles" ]]; then
    log_pass "TEST-002 $articles numbered articles, all with (see: ...) pointers"
  else
    log_fail "TEST-002 need >=6 numbered articles each with a (see: ...) pointer (articles=$articles, pointered=$pointered)"
  fi
}

# TEST-003 — ratification header naming the owner, date, and version
test_003_ratification_header() {
  if [[ ! -f "$DOC_FILE" ]]; then
    log_fail "TEST-003 $DOC_FILE does not exist"
    return
  fi
  if grep -qF "Proposed for ratification by: project owner (ales@holubec.net) — ratifies by merging the introducing PR; v1, 2026-07-16" "$DOC_FILE"; then
    log_pass "TEST-003 ratification header present"
  else
    log_fail "TEST-003 ratification header 'Proposed for ratification by: project owner (ales@holubec.net) — ratifies by merging the introducing PR; v1, 2026-07-16' missing"
  fi
}

# TEST-004 — the seven mandated principles are all present (stable literals)
test_004_principle_literals() {
  if [[ ! -f "$DOC_FILE" ]]; then
    log_fail "TEST-004 $DOC_FILE does not exist"
    return
  fi
  local ok=1 lit
  local literals=(
    "executable evidence"
    "KISS"
    "YAGNI"
    "tri-platform"
    "Degrade"
    "Additive first"
    "single writer"
    "operator-only"
  )
  for lit in "${literals[@]}"; do
    if ! grep -qF "$lit" "$DOC_FILE"; then
      log_info "TEST-004: missing principle literal '$lit'"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-004 all mandated principle literals present" \
                  || log_fail "TEST-004 mandated principle literal(s) missing"
}

# TEST-005 — PLANNING freeze step carries the article check INSIDE step 10;
# steps 11 (brief emit) and 12 (STATE update) survive unrenumbered; no step 13.
test_005_planning_freeze_step() {
  local section
  # Bound the extraction at the NEXT top-level numbered step — an unbounded
  # slice would find the literal anywhere and falsely pass.
  section=$(sed -n '/^10) /,/^11) /p' "$PLANNING_FILE")
  local ok=1
  if ! printf '%s\n' "$section" | grep -qF "Constitution deviations"; then
    log_info "TEST-005: 'Constitution deviations' check not inside PLANNING step 10"
    ok=0
  fi
  if ! printf '%s\n' "$section" | grep -qF "docs/CONSTITUTION.md"; then
    log_info "TEST-005: step 10 does not point at docs/CONSTITUTION.md"
    ok=0
  fi
  grep -qE '^11\) Emit the work-item brief' "$PLANNING_FILE" \
    || { log_info "TEST-005: step 11 (brief emit) missing or renumbered"; ok=0; }
  grep -qE '^12\) Update docs/ai/STATE\.yaml' "$PLANNING_FILE" \
    || { log_info "TEST-005: step 12 (STATE update) missing or renumbered"; ok=0; }
  if grep -qE '^13\) ' "$PLANNING_FILE"; then
    log_info "TEST-005: unexpected step 13 — the article check must not add a numbered step"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-005 article check inside freeze step 10, no renumber (11/12 intact, no 13)" \
                  || log_fail "TEST-005 PLANNING freeze-step wiring"
}

# TEST-006 — SPEC_TEMPLATE carries the section, marked required-for-new /
# optional-for-pre-existing.
test_006_spec_template_section() {
  local ok=1
  grep -qE '^## Constitution deviations' "$TEMPLATE_FILE" \
    || { log_info "TEST-006: '## Constitution deviations' section missing from SPEC_TEMPLATE"; ok=0; }
  grep -qF "optional for pre-existing specs" "$TEMPLATE_FILE" \
    || { log_info "TEST-006: optional-for-pre-existing note missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006 SPEC_TEMPLATE section present with legacy-optional note" \
                  || log_fail "TEST-006 SPEC_TEMPLATE wiring"
}

# TEST-007 — AGENTS.md canonical-sources line points at the constitution
test_007_agents_canonical_line() {
  if grep -qE '^- Project constitution.*docs/CONSTITUTION\.md' "$AGENTS_FILE"; then
    log_pass "TEST-007 AGENTS.md canonical-sources line present"
  else
    log_fail "TEST-007 AGENTS.md canonical-sources line for docs/CONSTITUTION.md missing"
  fi
}

# TEST-008 — legacy specs WITHOUT the section stay unflagged: strict audit
# scoped to all pre-existing docs/specs must be CLEAN and non-vacuous.
test_008_legacy_specs_unflagged() {
  local out
  if ! out=$(node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs 2>&1); then
    log_info "TEST-008: strict audit over docs/specs failed:"
    printf '%s\n' "$out" | tail -5 >&2
    log_fail "TEST-008 legacy specs flagged by strict audit"
    return
  fi
  # Non-vacuity: the scoped run must actually have scanned legacy specs.
  local scanned
  scanned=$(printf '%s\n' "$out" | grep -oE 'Scanned: [0-9]+' | grep -oE '[0-9]+' || echo 0)
  if [[ "${scanned:-0}" -ge 10 ]]; then
    log_pass "TEST-008 strict audit over docs/specs CLEAN ($scanned docs scanned, none flagged for missing section)"
  else
    log_fail "TEST-008 scoped audit vacuous (scanned=$scanned < 10)"
  fi
}

# TEST-009 — prompt-diet byte floor survives the PLANNING addition (shared
# baseline lives in the prompt-diet suite; run it rather than duplicate it).
test_009_prompt_diet_floor() {
  if bash tests/skills/test-aai-prompt-diet.sh >/dev/null 2>&1; then
    log_pass "TEST-009 prompt-diet suite green (byte floor holds)"
  else
    log_fail "TEST-009 prompt-diet suite failed after PLANNING addition"
  fi
}

# TEST-010 — repo-wide strict docs audit stays CLEAN with the new docs
test_010_strict_audit() {
  if node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1; then
    log_pass "TEST-010 repo-wide strict docs audit clean"
  else
    log_fail "TEST-010 repo-wide strict docs audit failed"
  fi
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_exists_and_line_budget
  test_002_articles_with_pointers
  test_003_ratification_header
  test_004_principle_literals
  test_005_planning_freeze_step
  test_006_spec_template_section
  test_007_agents_canonical_line
  test_008_legacy_specs_unflagged
  test_009_prompt_diet_floor
  test_010_strict_audit

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
