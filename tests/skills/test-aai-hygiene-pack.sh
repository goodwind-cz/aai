#!/usr/bin/env bash
#
# Test: CHANGE-0007 / SPEC-0013 workflow hygiene pack — grep-wiring suite
# (TEST-010..018, TEST-022). Asserts the H2–H8 prompt/wrapper edits are present and the
# SPEC-0012 migration markers were preserved. RED-proof: run against the
# PRE-CHANGE prompt/wrapper text — every test must FAIL before the edits land.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-hygiene-pack"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# Skill trees that exist in this checkout (wrapper edits are mirrored to every
# tree that carries the wrapper — SPEC-0013 D8).
skill_trees() {
  local t
  for t in .claude .gemini .codex; do
    [[ -d "$PROJECT_ROOT/$t/skills" ]] && echo "$t"
  done
  return 0
}

check_deps() {
  log_info "Checking dependencies..."
  command -v grep >/dev/null 2>&1 || log_skip "grep not found"
  [[ -d "$PROJECT_ROOT/.aai" ]] || log_skip "not an AAI checkout"
  log_pass "Dependencies checked"
}

test_010_skill_pr() {  # TEST-010 / Spec-AC-02
  log_info "Test: SKILL_PR anchors + aai-pr wrapper in every skill tree (TEST-010)..."
  local f="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_PR.prompt.md"
  grep -qF "derive the scope file-list" "$f" \
    || log_fail "SKILL_PR must derive the scope file-list from STATE/spec"
  grep -qF "stage ONLY in-scope paths" "$f" \
    || log_fail "SKILL_PR must instruct scope-only staging"
  grep -qF "staged-vs-scope audit" "$f" \
    || log_fail "SKILL_PR must carry the staged-vs-scope audit step"
  grep -qF -- "git diff --cached --name-only" "$f" \
    || log_fail "SKILL_PR audit must compare git diff --cached --name-only against the scope list"
  grep -qE 'git add -A|git add \.' "$f" \
    || log_fail "SKILL_PR must explicitly forbid git add -A / git add . (named as forbidden)"
  grep -qF "gh pr create" "$f" \
    || log_fail "SKILL_PR must create the PR via gh pr create"
  grep -qiF "never merge" "$f" \
    || log_fail "SKILL_PR must state it NEVER merges"
  grep -qiF "gh pr merge" "$f" \
    || log_fail "SKILL_PR must name gh pr merge as forbidden"
  grep -qiF "operator" "$f" \
    || log_fail "SKILL_PR must reserve merging for the operator"
  grep -qF "Spec-AC" "$f" \
    || log_fail "SKILL_PR body template must carry a Spec-AC/TEST evidence table"
  local t w
  for t in $(skill_trees); do
    w="$PROJECT_ROOT/$t/skills/aai-pr/SKILL.md"
    [[ -f "$w" ]] || log_fail "missing $t/skills/aai-pr/SKILL.md"
    grep -qF ".aai/SKILL_PR.prompt.md" "$w" || log_fail "$w must read .aai/SKILL_PR.prompt.md"
    grep -qF "<SUBAGENT-STOP>" "$w" || log_fail "$w must carry the SUBAGENT-STOP block"
    grep -qF 'Invoke this as `/aai-pr`' "$w" || log_fail "$w must carry the invoke line"
    grep -qF "SKILL_PR not found" "$w" || log_fail "$w must carry the not-found fallback"
  done
  log_pass "SKILL_PR prompt anchors + aai-pr wrappers present in all trees (TEST-010)"
}

test_011_external_review_response() {  # TEST-011 / Spec-AC-03
  log_info "Test: SKILL_CODE_REVIEW External Review Response section (TEST-011)..."
  local f="$PROJECT_ROOT/.aai/SKILL_CODE_REVIEW.prompt.md"
  grep -qF "## External Review Response" "$f" \
    || log_fail "SKILL_CODE_REVIEW must carry the External Review Response section"
  grep -qF "gh api repos/{owner}/{repo}/pulls/" "$f" \
    || log_fail "section must fetch review threads via gh api repos/{owner}/{repo}/pulls/.../comments"
  grep -qF "gh pr view" "$f" && grep -qF -- "--json reviews" "$f" \
    || log_fail "section must also fetch reviews via gh pr view --json reviews"
  grep -qF "real / stale / duplicate / disputed" "$f" \
    || log_fail "section must triage findings as real / stale / duplicate / disputed"
  grep -qF "RED-proofed regression test" "$f" \
    || log_fail "section must require a RED-proofed regression test per real finding"
  grep -qF "commit SHA and TEST id" "$f" \
    || log_fail "inline replies must cite the fixing commit SHA and TEST id"
  grep -qiF "push" "$f" || log_fail "section must end with a push"
  grep -qiF "never resolve a thread without a reply" "$f" \
    || log_fail "section must forbid resolving a thread without a reply"
  log_pass "External Review Response flow codified (TEST-011)"
}

test_012_report_staging() {  # TEST-012 / Spec-AC-04
  log_info "Test: review-report staging instruction + wrap-up orphaned-reviews call-out (TEST-012)..."
  local cr="$PROJECT_ROOT/.aai/SKILL_CODE_REVIEW.prompt.md"
  local wu="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"
  grep -qF "stage the report files" "$cr" \
    || log_fail "SKILL_CODE_REVIEW must instruct staging the report files with the scope's commit"
  grep -qiF "never orphan" "$cr" \
    || log_fail "SKILL_CODE_REVIEW staging instruction must state reports never orphan"
  grep -qF "orphaned review reports" "$wu" \
    || log_fail "SKILL_WRAP_UP uncommitted-work step must call out orphaned review reports"
  grep -qF "docs/ai/reviews/" "$wu" \
    || log_fail "SKILL_WRAP_UP orphan call-out must name docs/ai/reviews/"
  log_pass "Report staging + orphaned-reviews call-out wired (TEST-012)"
}

test_013_metrics_flush_partial() {  # TEST-013 / Spec-AC-05
  log_info "Test: METRICS_FLUSH partial-flush reset per D6 + SPEC-0012 markers preserved (TEST-013)..."
  local f="$PROJECT_ROOT/.aai/METRICS_FLUSH.prompt.md"
  grep -qF "PARTIAL-FLUSH" "$f" \
    || log_fail "METRICS_FLUSH must carry the PARTIAL-FLUSH reset branch"
  grep -qF "current_focus.ref_id" "$f" \
    || log_fail "partial-flush condition must trigger on flushed ref == current_focus.ref_id"
  grep -qF 'set-validation --status not_run --notes "reset after flush of <ref_id>"' "$f" \
    || log_fail "partial-flush must use the exact set-validation command from D6"
  grep -qF 'set-code-review --required false --status not_run --notes "reset after flush of <ref_id>"' "$f" \
    || log_fail "partial-flush must use the exact set-code-review command from D6"
  grep -qF "ledger-before-reset" "$f" \
    || log_fail "METRICS_FLUSH must state the ledger-before-reset ordering"
  grep -qF -- "reset-block --force" "$f" \
    && log_fail "METRICS_FLUSH must NOT route the flush reset through reset-block --force"
  # SPEC-0012 migration text preserved (freshness constraint).
  grep -qF "PRIMARY PATH (transactional CLI, SPEC-0012)" "$f" \
    || log_fail "SPEC-0012 primary-path marker must be preserved in METRICS_FLUSH"
  grep -qF "state.mjs is absent" "$f" \
    || log_fail "SPEC-0012 fallback marker must be preserved in METRICS_FLUSH"

  # Fixture walk-through (seam 4): the two prescribed commands run clean against
  # the live CLI and leave a check-state-valid file with both verdicts not_run.
  command -v node >/dev/null 2>&1 || { log_pass "prose wired; node absent — CLI walk-through skipped (TEST-013)"; return 0; }
  [[ -f "$PROJECT_ROOT/.aai/scripts/state.mjs" ]] || log_fail "state.mjs missing — D6 commands have no CLI target"
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  local s="$TEST_DIR/t13-state.yaml"
  cat > "$s" <<'YAML'
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md

active_work_items:
  - ref_id: CHANGE-0002
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0002-fixture.md

implementation_strategy:
  selected: hybrid
  source: null
  rationale: null

worktree:
  recommendation: not_needed
  user_decision: undecided
  base_ref: null
  branch: null
  path: null
  inline_review_scope: null
  rationale: null

code_review:
  required: true
  status: pass
  scope: fixture scope
  base_ref: main
  head_ref: null
  report_paths: []
  notes: null

last_validation:
  status: pass
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: CHANGE-0001/SPEC-0001
  evidence_paths: []
  notes: null

human_input:
  required: false
  question: null

locks:
  implementation: false

updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" set-validation --status not_run --notes "reset after flush of CHANGE-0001" > "$TEST_DIR/t13a.log" 2>&1) \
    || log_fail "D6 set-validation command must run clean: $(cat "$TEST_DIR/t13a.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" set-code-review --required false --status not_run --notes "reset after flush of CHANGE-0001" > "$TEST_DIR/t13b.log" 2>&1) \
    || log_fail "D6 set-code-review command must run clean: $(cat "$TEST_DIR/t13b.log")"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: not_run$' \
    || log_fail "walk-through: last_validation.status must be not_run after the partial-flush reset"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: not_run$' \
    || log_fail "walk-through: code_review.status must be not_run after the partial-flush reset"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$s" > "$TEST_DIR/t13c.log" 2>&1) \
    || log_fail "walk-through: check-state must pass after the resets: $(cat "$TEST_DIR/t13c.log")"
  log_pass "Partial-flush reset wired, exact D6 commands verified against the live CLI (TEST-013)"
}

test_014_warnings_policy() {  # TEST-014 / Spec-AC-06
  log_info "Test: warnings policy names decisions.jsonl / follow-up ref; wrap-up advisory present (TEST-014)..."
  local cr="$PROJECT_ROOT/.aai/SKILL_CODE_REVIEW.prompt.md"
  local wu="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"
  grep -qF "docs/ai/decisions.jsonl" "$cr" \
    || log_fail "warnings policy must name a docs/ai/decisions.jsonl entry per WARNING"
  grep -qF "follow-up ref" "$cr" \
    || log_fail "warnings policy must allow promotion to a tracked follow-up ref"
  grep -qiF "conditional" "$cr" \
    || log_fail "a PASS with open WARNINGs must be stated as conditional"
  grep -qF "unrecorded WARNINGs" "$wu" \
    || log_fail "SKILL_WRAP_UP must surface unrecorded WARNINGs at closeout (advisory)"
  log_pass "Warnings policy with named artifacts + wrap-up advisory wired (TEST-014)"
}

test_015_fixture_diversity() {  # TEST-015 / Spec-AC-07
  log_info "Test: fixture-diversity checklist + happy-path question in SKILL_TDD and SKILL_TEST_CANON (TEST-015)..."
  local f
  for f in "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md" "$PROJECT_ROOT/.aai/SKILL_TEST_CANON.prompt.md"; do
    grep -qF "Fixture diversity checklist" "$f" \
      || log_fail "$f must carry the fixture-diversity checklist"
    grep -qiF "degenerate" "$f" || log_fail "$f checklist must cover degenerate/empty collections"
    grep -qF "zero-remainder" "$f" || log_fail "$f checklist must cover the fully-covered / zero-remainder case"
    grep -qF "multi-source" "$f" || log_fail "$f checklist must cover the multi-source / multi-writer case"
    grep -qF "mid-operation failure" "$f" || log_fail "$f checklist must cover mid-operation failure"
    grep -qF "negative control" "$f" || log_fail "$f checklist must cover the negative control"
    grep -qF "would this suite stay green if the happy path were the only path implemented?" "$f" \
      || log_fail "$f must carry the verbatim RED-proof extension question"
  done
  # SPEC-0012 markers intact in SKILL_TDD (freshness constraint).
  grep -qF "node .aai/scripts/state.mjs" "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md" \
    || log_fail "SKILL_TDD SPEC-0012 primary path must be preserved"
  grep -qF "state.mjs is absent" "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md" \
    || log_fail "SKILL_TDD SPEC-0012 fallback marker must be preserved"
  log_pass "Fixture-diversity checklist in both test-writing prompts, markers intact (TEST-015)"
}

test_016_wrapup_promise_and_guards() {  # TEST-016 / Spec-AC-08
  log_info "Test: triggers.json promise removed; wrapper description phrases; SUBAGENT-STOP guards (TEST-016)..."
  local wu="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"
  grep -qF ".claude/triggers.json" "$wu" \
    && log_fail "SKILL_WRAP_UP must no longer promise .claude/triggers.json auto-triggering (no runtime consumer exists)"
  grep -qF "AUTO-TRIGGER PATTERNS" "$wu" \
    && log_fail "SKILL_WRAP_UP must no longer carry the AUTO-TRIGGER PATTERNS block"
  local t w p
  for t in $(skill_trees); do
    w="$PROJECT_ROOT/$t/skills/aai-wrap-up/SKILL.md"
    [[ -f "$w" ]] || continue
    for p in "wrap up" "end session" "done for today" "hotovo" "konec" "bye"; do
      grep -qF "$p" "$w" \
        || log_fail "$w description must carry the trigger phrase '$p' (native skill-matching compensation)"
    done
    grep -qF "<SUBAGENT-STOP>" "$w" || log_fail "$w must carry the SUBAGENT-STOP block"
    w="$PROJECT_ROOT/$t/skills/aai-flush/SKILL.md"
    [[ -f "$w" ]] || continue
    grep -qF "<SUBAGENT-STOP>" "$w" || log_fail "$w must carry the SUBAGENT-STOP block"
  done
  log_pass "Promise removed, trigger phrases moved to the native channel, guards added (TEST-016)"
}

test_017_invoke_lines() {  # TEST-017 / Spec-AC-08
  log_info "Test: the 6 wrappers carry the invoke line in every tree that has them (TEST-017)..."
  local s t w
  for s in aai-docs-hub aai-flush aai-share aai-tdd aai-test-skills aai-worktree; do
    for t in $(skill_trees); do
      w="$PROJECT_ROOT/$t/skills/$s/SKILL.md"
      [[ -f "$w" ]] || continue
      grep -qF "Invoke this as \`/$s\`" "$w" \
        || log_fail "$w must carry the line: Invoke this as \`/$s\`."
    done
  done
  log_pass "Invoke lines uniform across the wrapper set (TEST-017)"
}

test_018_skill_meta_loader() {  # TEST-018 / Spec-AC-08
  log_info "Test: SKILL_META self-documents its loader; hooks wiring intact (TEST-018)..."
  local f="$PROJECT_ROOT/.aai/SKILL_META.prompt.md"
  grep -qF "hooks/session-start.sh" "$f" \
    || log_fail "SKILL_META must name its loader (hooks/session-start.sh/.ps1)"
  grep -qF "not a slash skill" "$f" \
    || log_fail "SKILL_META loader note must state it is not a slash skill (no wrapper)"
  grep -qF "SKILL_META" "$PROJECT_ROOT/hooks/session-start.sh" \
    || log_fail "hooks/session-start.sh must still reference SKILL_META"
  grep -qF "SKILL_META" "$PROJECT_ROOT/hooks/session-start.ps1" \
    || log_fail "hooks/session-start.ps1 must still reference SKILL_META"
  grep -qF "SessionStart" "$PROJECT_ROOT/hooks/hooks.json" \
    || log_fail "hooks/hooks.json must still wire SessionStart"
  log_pass "SKILL_META kept, loader self-documented, hooks wiring intact (TEST-018)"
}

test_022_pr_review_companions() {  # TEST-022 / Spec-AC-04 (review-20260704T110648Z W4: H2/H4 seam)
  log_info "Test: SKILL_PR staged-vs-scope audit whitelists docs/ai/reviews/ report artifacts as expected companions (TEST-022)..."
  local f="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_PR.prompt.md"
  grep -qF "docs/ai/reviews/" "$f" \
    || log_fail "SKILL_PR must whitelist docs/ai/reviews/ — H4 mandates staging review reports with the scope's commit, so the audit must not unstage them"
  grep -qiF "companion" "$f" \
    || log_fail "the docs/ai/reviews/ allowance must be phrased as an expected companion, not a violation"
  grep -qF "H4" "$f" \
    || log_fail "the allowance must cite H4 (SKILL_CODE_REVIEW report-staging mandate) so the seam stays traceable"
  log_pass "SKILL_PR treats scope-cited review reports as expected companions (TEST-022)"
}

main() {
  echo "Testing $TEST_NAME (CHANGE-0007 / SPEC-0013 grep wiring)"
  check_deps
  test_010_skill_pr
  test_011_external_review_response
  test_012_report_staging
  test_013_metrics_flush_partial
  test_014_warnings_policy
  test_015_fixture_diversity
  test_016_wrapup_promise_and_guards
  test_017_invoke_lines
  test_018_skill_meta_loader
  test_022_pr_review_companions
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (RED-proof evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
