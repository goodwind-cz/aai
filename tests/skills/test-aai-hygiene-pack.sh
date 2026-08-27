#!/usr/bin/env bash
#
# Test: CHANGE-0007 / SPEC-0013 workflow hygiene pack — grep-wiring suite
# (TEST-010..018, TEST-022). Asserts the H2–H8 prompt/wrapper edits are present and the
# SPEC-0012 migration markers were preserved. RED-proof: run against the
# PRE-CHANGE prompt/wrapper text — every test must FAIL before the edits land.
# test_030 per CHANGE-0008 / SPEC-0014 TEST-008 (auto-trigger deprecation, F3).
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

# Set by test_113 while a disposable detached worktree is live, so the EXIT
# trap below removes it with a targeted `git worktree remove` (HAZ-WORKTREE)
# even if a mid-arm log_fail exits the whole process before test_113's own
# happy-path cleanup runs.
HSK_ACTIVE_WORKTREE=""

cleanup() {
  if [[ -n "${HSK_ACTIVE_WORKTREE:-}" ]]; then
    git -C "$PROJECT_ROOT" worktree remove --force "$HSK_ACTIVE_WORKTREE" >/dev/null 2>&1 || true
    HSK_ACTIVE_WORKTREE=""
  fi
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
# tree that carries the wrapper — SPEC-0013 D8). `.agents` added by
# harness-surfaces-drift-unguarded D4/D1: it is the fourth tracked skill tree
# (Cursor's FIRST documented project-skills path) and every arm below that
# iterates skill_trees() now covers it too — that is deliberate, not scope
# creep (see the spec's "Adding .agents ... retro-applies eight existing arms"
# edge case note).
skill_trees() {
  local t
  for t in .claude .agents .gemini .codex; do
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

test_030_auto_trigger_deprecation() {  # SPEC-0014 TEST-008 / Spec-AC-06 (CHANGE-0008 F3)
  log_info "Test: aai-auto-trigger deprecated per SPEC-0014 D4 — notice, wrappers, USER_GUIDE, AGENTS.md, catalog, repo grep (SPEC-0014 TEST-008)..."
  local f="$PROJECT_ROOT/.aai/SKILL_AUTO_TRIGGER.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_AUTO_TRIGGER.prompt.md (the deprecation notice must stay present)"

  # (a) the notice: DEPRECATED marker + no-runtime-consumer evidence + real
  # channel + out-of-scope note; the 500-line pattern-matching manual is GONE.
  grep -qF "DEPRECATED" "$f" || log_fail "notice must carry the DEPRECATED marker"
  grep -qiF "no runtime consumer" "$f" || log_fail "notice must carry the no-runtime-consumer evidence"
  grep -qF "SPEC-0013" "$f" || log_fail "notice must point at the SPEC-0013 D8 grep evidence"
  grep -qiF "trigger phrases" "$f" || log_fail "notice must name the real channel (wrapper-description trigger phrases)"
  grep -qF "aai-wrap-up" "$f" || log_fail "notice must cite the aai-wrap-up precedent"
  grep -qiF "out of scope" "$f" || log_fail "notice must state that building a real consumer is out of scope (CHANGE-0008)"
  grep -qF '"triggers":' "$f" && log_fail "notice must drop the triggers.json config-structure manual"
  grep -qF "/aai-auto-trigger add" "$f" && log_fail "notice must drop the CRUD operations manual"
  local n
  n="$(wc -l < "$f" | tr -d ' ')"
  [[ "$n" -le 60 ]] || log_fail "notice must be a SHORT deprecation notice (~40 lines target, got $n)"

  # (b) wrappers stay PRESENT in every tree (muscle memory) but say deprecated
  # and no longer claim a working mechanism.
  local t w
  for t in $(skill_trees); do
    w="$PROJECT_ROOT/$t/skills/aai-auto-trigger/SKILL.md"
    [[ -f "$w" ]] || log_fail "wrapper must STAY present: $w (removing it breaks muscle memory/mirrors)"
    grep -qE '^description: DEPRECATED' "$w" \
      || log_fail "$w description must lead with DEPRECATED"
    grep -qF ".aai/SKILL_AUTO_TRIGGER.prompt.md" "$w" || log_fail "$w must still point at the notice"
    grep -qiE 'manages pattern' "$w" \
      && log_fail "$w must no longer claim to manage a working pattern-matching mechanism"
  done

  # (c) USER_GUIDE: section-7 entry + quick-list line relabeled deprecated;
  # the working-mechanism claims are gone.
  local ug="$PROJECT_ROOT/docs/USER_GUIDE.md"
  grep -A3 '#### `/aai-auto-trigger`' "$ug" | grep -qi "deprecated" \
    || log_fail "USER_GUIDE Automation & Integration entry must be relabeled deprecated"
  grep -qE '^\- `/aai-auto-trigger` - Deprecated' "$ug" \
    || log_fail "USER_GUIDE quick skills list must relabel /aai-auto-trigger as Deprecated"
  grep -qE '\| `/aai-auto-trigger` \| Deprecated \|' "$ug" \
    || log_fail "USER_GUIDE Advanced Skills table must relabel /aai-auto-trigger as Deprecated"
  grep -qF '`.claude/triggers.json` config' "$ug" \
    && log_fail "USER_GUIDE must no longer claim /aai-auto-trigger manages a .claude/triggers.json config"
  grep -qF "Setup auto-triggers" "$ug" \
    && log_fail "USER_GUIDE must no longer instruct setting up auto-triggers as a working workflow"

  # (d) AGENTS.md skill-index line relabeled.
  grep -E 'SKILL_AUTO_TRIGGER' "$PROJECT_ROOT/.aai/AGENTS.md" | grep -qi "deprecated" \
    || log_fail ".aai/AGENTS.md SKILL_AUTO_TRIGGER line must be relabeled deprecated"

  # (e) generated catalog entry updated (CHANGE-0078: docs/SKILL_CATALOG.html
  # is now emitted by generate-docs-hub.mjs as `<h3>aai-auto-trigger</h3>`
  # followed by a `<p class="desc">` carrying the SKILL.md description
  # verbatim, not the old hand-authored `name: "aai-auto-trigger"` JS
  # literal shape).
  grep -A2 '<h3>aai-auto-trigger</h3>' "$PROJECT_ROOT/docs/SKILL_CATALOG.html" | grep -qi "deprecated" \
    || log_fail "docs/SKILL_CATALOG.html aai-auto-trigger description must say deprecated"

  # (f) discriminating repo grep: every non-historical file that mentions
  # triggers.json must carry a deprecation marker (historical records and the
  # already-reality-aligned SUPERPOWERS_INTEGRATION are out of scope per D4).
  local hits h
  hits="$(cd "$PROJECT_ROOT" && grep -rl "triggers.json" .aai docs .claude .codex .gemini 2>/dev/null || true)"
  for h in $hits; do
    case "$h" in
      docs/releases/*|docs/specs/*|docs/issues/*|docs/ai/*|.aai/system/SUPERPOWERS_INTEGRATION.md) continue ;;
    esac
    grep -qi "deprecat" "$PROJECT_ROOT/$h" \
      || log_fail "$h mentions triggers.json without a deprecation marker (presents a consumer-less mechanism as working)"
  done
  log_pass "Auto-trigger deprecation wired: notice + 3 wrappers + USER_GUIDE + AGENTS.md + catalog; repo grep reality-aligned (SPEC-0014 TEST-008)"
}

test_031_guard_config_conformance() {  # CHANGE-0009 TEST-018 / Spec-AC-09
  log_info "Test: shared guard-config reader agrees with the pre-commit shell greps on fixture configs (CHANGE-0009 TEST-018)..."
  local lib="$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs"
  local sh_hook="$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh"
  local ps_hook="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1"
  [[ -f "$lib" ]] || log_fail "missing shared reader $lib (RED until CHANGE-0009 lands)"
  command -v node >/dev/null 2>&1 || log_skip "node not found"

  # The deliberate thin greps must name the shared reader as canonical so the
  # coupling is documented at the fork site (SPEC-0018 W2 / CHANGE-0009 D8).
  grep -qF "lib/guard-config.mjs" "$sh_hook" \
    || log_fail "pre-commit-checks.sh must name lib/guard-config.mjs as the canonical reader"
  grep -qF "lib/guard-config.mjs" "$ps_hook" \
    || log_fail "install-pre-commit-hook.ps1 must name lib/guard-config.mjs as the canonical reader"

  # Extract the ACTUAL grep -Eq patterns from the hooks (drift in either side
  # now fails this test instead of diverging silently).
  local dn_pat cg_pat
  dn_pat="$(awk -F"'" '/grep -Eq/ && /doc_number_guard:/ { print $(NF-1); exit }' "$sh_hook")"
  cg_pat="$(awk -F"'" '/grep -Eq/ && /close_gate:/ { print $(NF-1); exit }' "$ps_hook")"
  [[ -n "$dn_pat" ]] || log_fail "could not extract the doc_number_guard grep pattern from pre-commit-checks.sh"
  [[ -n "$cg_pat" ]] || log_fail "could not extract the close_gate grep pattern from install-pre-commit-hook.ps1"

  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  local d="$TEST_DIR/t31"
  mkdir -p "$d"

  reader_verdict() {  # $1 dir, $2 key -> enforce|report-only
    (cd "$PROJECT_ROOT" && node --input-type=module -e '
      import { readGuardConfig } from "./.aai/scripts/lib/guard-config.mjs";
      const g = readGuardConfig(process.argv[1], { warn: () => {} });
      console.log(g[process.argv[2]]);
    ' "$1" "$2")
  }

  check_variant() {  # $1 label, $2 key, $3 pattern, $4 config-content ('' = absent file)
    local label="$1" key="$2" pat="$3" content="$4"
    rm -f "$d/docs-audit.yaml"
    [[ -n "$content" ]] && printf '%s\n' "$content" > "$d/docs-audit.yaml"
    local want="report-only"
    if [[ -f "$d/docs-audit.yaml" ]] && grep -Eq "$pat" "$d/docs-audit.yaml" 2>/dev/null; then
      want="enforce"
    fi
    local got
    got="$(reader_verdict "$d" "$key")"
    [[ "$got" == "$want" ]] \
      || log_fail "conformance drift on '$label' ($key): shell grep says $want, reader says $got"
  }

  local key pat
  for key in close_gate doc_number_guard; do
    pat="$cg_pat"
    [[ "$key" == "doc_number_guard" ]] && pat="$dn_pat"
    check_variant "absent file" "$key" "$pat" ""
    check_variant "absent key" "$key" "$pat" "legacy_until_date: 2026-06-12"
    check_variant "enforce" "$key" "$pat" "$key: enforce"
    check_variant "report-only" "$key" "$pat" "$key: report-only"
    check_variant "trailing comment" "$key" "$pat" "$key: enforce  # note"
    check_variant "commented out" "$key" "$pat" "# $key: enforce"
    check_variant "invalid value" "$key" "$pat" "$key: enforced"
    # Review CHANGE-0009 W2 variants: these four used to diverge (or were
    # untested) between the hooks' greps and the shared reader.
    check_variant "indented key" "$key" "$pat" "  $key: enforce"
    check_variant "glued comment" "$key" "$pat" "$key: enforce# note"
    check_variant "quoted value" "$key" "$pat" "$key: \"enforce\""
    check_variant "CRLF line" "$key" "$pat" "$key: enforce"$'\r'
  done
  log_pass "Shared reader and shell grep patterns agree on all fixture variants (CHANGE-0009 TEST-018)"
}

test_040_dual_verdict_prompt() {  # spec-single-dual-verdict-review TEST-001..004 / Spec-AC-01..02
  log_info "Test: SKILL_CODE_REVIEW is a single dual-verdict pass, diet + preserved contracts (spec-single-dual-verdict-review TEST-001..004)..."
  local f="$PROJECT_ROOT/.aai/SKILL_CODE_REVIEW.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_CODE_REVIEW.prompt.md"

  # TEST-001 — prompt diet: the single pass fits in 250 lines (was 766, RES-0001 F3).
  local n
  n="$(wc -l < "$f" | tr -d ' ')"
  [[ "$n" -le 250 ]] || log_fail "SKILL_CODE_REVIEW must be <=250 lines (got $n)"

  # TEST-002 — dual-verdict block anchors (RFC single-dual-verdict-review Option B).
  grep -qF "spec_compliance" "$f" || log_fail "prompt must carry the spec_compliance verdict"
  grep -qF "code_quality" "$f" || log_fail "prompt must carry the code_quality verdict"
  grep -qF "cannot_verify" "$f" || log_fail "prompt must carry the cannot_verify verdict class"
  grep -qE "cannot_verify.*MANDATORY|MANDATORY.*cannot_verify" "$f" \
    || log_fail "the cannot_verify section must be MANDATORY (empty list allowed, but the section is not optional)"
  grep -qF "BLOCKING" "$f" || log_fail "code_quality findings must be rankable BLOCKING"
  grep -qF "NON-BLOCKING" "$f" || log_fail "code_quality findings must be rankable NON-BLOCKING"
  grep -qF "AC table walk" "$f" || log_fail "spec_compliance evidence must be the AC table walk"
  grep -qF "per-AC citation" "$f" || log_fail "the AC table walk must demand a per-AC citation"
  grep -qF "failure scenario" "$f" || log_fail "every quality finding must carry a concrete failure scenario"
  grep -qiF "both verdicts pass" "$f" || log_fail "overall review pass must require BOTH verdicts to pass"

  # TEST-003 — the two-stage scaffolding and the RES-0001 F3 fiction are gone.
  grep -qF "TWO-STAGE REVIEW" "$f" && log_fail "the TWO-STAGE REVIEW mandatory-order block must be gone"
  grep -qF "Stage 1" "$f" && log_fail "no Stage 1 scaffolding may remain"
  grep -qF "Stage 2" "$f" && log_fail "no Stage 2 scaffolding may remain"
  grep -qF "parseDiff" "$f" && log_fail "the inline JS diff-parser fiction must be gone"
  grep -qF "jsChecks" "$f" && log_fail "the inline JS regex-checker arrays must be gone"
  grep -qF "code-review-config.json" "$f" && log_fail "the consumer-less config JSON manual must be gone"
  grep -qF ".github/workflows/code-review.yml" "$f" && log_fail "the CI workflow YAML must be gone"
  grep -qF "## Troubleshooting" "$f" && log_fail "the troubleshooting table must be gone"

  # TEST-004 — preserved verbatim-or-equivalent contracts.
  grep -qF "DIFF SCOPE PREFLIGHT" "$f" || log_fail "the diff-scope preflight must be preserved"
  grep -qF "SPEC-0013 H6" "$f" || log_fail "the H6 warnings policy must be preserved"
  grep -qF "## External Review Response" "$f" || log_fail "the H3 external-review-response flow must be preserved"
  grep -qF "docs/ai/reviews/" "$f" || log_fail "reports must stay under docs/ai/reviews/"
  grep -qF "set-code-review" "$f" || log_fail "the set-code-review STATE contract must be preserved"
  grep -qF "docs/validation/" "$f" || log_fail "the never-docs/validation lesson must be preserved"
  log_pass "SKILL_CODE_REVIEW dual-verdict single pass wired: $n lines, anchors present, scaffolding gone (spec-single-dual-verdict-review TEST-001..004)"
}

test_041_anti_gaming_protocol() {  # spec-single-dual-verdict-review TEST-005 / Spec-AC-03
  log_info "Test: SUBAGENT_PROTOCOL carries the review anti-gaming contract (spec-single-dual-verdict-review TEST-005)..."
  local f="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SUBAGENT_PROTOCOL.md"
  grep -qF "MUST NOT characterize expected findings" "$f" \
    || log_fail "protocol must ban the orchestrator from characterizing expected findings"
  grep -qF "pre-rate severity" "$f" \
    || log_fail "protocol must ban the orchestrator from pre-rating severity"
  grep -qF "scope-exclude" "$f" \
    || log_fail "protocol must ban the orchestrator from scope-excluding areas for the reviewer"
  grep -qF "read-only on implementation files" "$f" \
    || log_fail "protocol must make the reviewer context read-only on implementation files"
  grep -qF "ref/path list" "$f" \
    || log_fail "protocol must hand the diff off by ref/path list"
  grep -qF "never pasted inline" "$f" \
    || log_fail "protocol must forbid pasting the diff inline into the dispatch prompt"
  log_pass "Review anti-gaming contract present in SUBAGENT_PROTOCOL (spec-single-dual-verdict-review TEST-005)"
}

test_042_dual_verdict_surfaces() {  # spec-single-dual-verdict-review TEST-006 / Spec-AC-04
  log_info "Test: wrapper descriptions + ROLES.md + AGENTS.md match the dual-verdict shape (spec-single-dual-verdict-review TEST-006)..."
  local t w
  for t in $(skill_trees); do
    w="$PROJECT_ROOT/$t/skills/aai-code-review/SKILL.md"
    [[ -f "$w" ]] || log_fail "missing $t/skills/aai-code-review/SKILL.md"
    grep -qiF "dual-verdict" "$w" || log_fail "$w description must name the dual-verdict single pass"
    grep -qF "cannot_verify" "$w" || log_fail "$w description must name the cannot_verify verdict"
  done
  local r="$PROJECT_ROOT/.aai/roles/ROLES.md"
  grep -qF "Stage 1" "$r" && log_fail "ROLES.md must no longer define a stage-ordered code review"
  grep -qF "Stage 2" "$r" && log_fail "ROLES.md must no longer define a stage-ordered code review"
  grep -qiF "dual verdict" "$r" || log_fail "ROLES.md Code Review role must own the dual-verdict pass"
  grep -qF "cannot_verify" "$r" || log_fail "ROLES.md Code Review role must own the cannot_verify verdict"
  local a="$PROJECT_ROOT/.aai/AGENTS.md"
  grep -qiF "two-stage review" "$a" && log_fail "AGENTS.md must no longer describe the review as two-stage"
  grep -qiF "dual-verdict" "$a" || log_fail "AGENTS.md skill index must describe the dual-verdict review"
  log_pass "Dual-verdict surfaces aligned: wrappers x$(skill_trees | wc -l | tr -d ' '), ROLES.md, AGENTS.md (spec-single-dual-verdict-review TEST-006)"
}

test_043_review_taxonomy_alignment() {  # spec-review-taxonomy-alignment TEST-001..002 / Spec-AC-01..02 (CHANGE-0014)
  log_info "Test: orchestration-facing surfaces speak the dual-verdict taxonomy (spec-review-taxonomy-alignment TEST-001..002)..."

  # TEST-001 — repo-wide negative grep: the retired Stage-1/Stage-2 +
  # ERROR/WARNING review taxonomy is gone from every orchestration-facing
  # tree (.aai + skill wrappers). Whitelist: .aai/SKILL_CODE_REVIEW.prompt.md
  # only — its "replaces the former two-stage flow" note is a historical
  # self-reference and the review prompt is out of CHANGE-0014 scope
  # (test_040 already bans Stage 1/2 scaffolding inside it). Immutable
  # history (docs/**, CHANGELOG) and this suite (tests/**) are outside the
  # swept trees by construction.
  local trees=("$PROJECT_ROOT/.aai") t hits
  for t in $(skill_trees); do trees+=("$PROJECT_ROOT/$t"); done
  # Review CHANGE-0014 NB-1: anchor the whitelist to the HIT PATH PREFIX —
  # an unanchored substring filter would silently whitelist any OTHER swept
  # file whose line merely mentions the reviewed prompt's path.
  hits="$(grep -rniE 'Stage 1|Stage 2|stage-1|stage-2|two-stage|mandatory stage|ERROR finding|WARNING finding|ERROR/WARNING|ERROR blocks|WARNING requires' \
    "${trees[@]}" 2>/dev/null | grep -vE "^${PROJECT_ROOT}/\.aai/SKILL_CODE_REVIEW\.prompt\.md:" || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" >&2
    log_fail "old review taxonomy still present on orchestration-facing surfaces (see hits above)"
  fi

  # TEST-002 — positive anchors (non-vacuous): the finding-intake wording in
  # REMEDIATION matches the dual-verdict report schema FIELD NAMES so a
  # review-FAIL dispatch buckets correctly.
  local r="$PROJECT_ROOT/.aai/REMEDIATION.prompt.md"
  grep -qF "spec_compliance" "$r" || log_fail "REMEDIATION must bucket by the spec_compliance verdict"
  grep -qF "code_quality" "$r" || log_fail "REMEDIATION must bucket by the code_quality verdict"
  grep -qF "ac_walk" "$r" || log_fail "REMEDIATION must point at the report's ac_walk rows"
  grep -qF "BLOCKING" "$r" || log_fail "REMEDIATION must key code-quality fixes on BLOCKING findings"
  grep -qF "NON-BLOCKING" "$r" || log_fail "REMEDIATION must carry the NON-BLOCKING (H6) disposition duty"
  grep -qF "failure_scenario" "$r" || log_fail "REMEDIATION must name the findings' failure_scenario field"
  grep -qF "cannot_verify" "$r" || log_fail "REMEDIATION must name cannot_verify as evidence gaps, not defects"

  # The reworded surfaces carry the new vocabulary.
  grep -qF "BLOCKING findings block readiness" "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" \
    || log_fail "dispatch Code Review stop_condition must speak BLOCKING findings"
  grep -qF "Code Review BLOCKING findings" "$PROJECT_ROOT/.aai/workflow/WORKFLOW.md" \
    || log_fail "WORKFLOW stop condition must speak BLOCKING findings"
  grep -qF "Code Review BLOCKING findings" "$PROJECT_ROOT/.aai/ORCHESTRATION_HITL.prompt.md" \
    || log_fail "HITL trigger 9 must speak BLOCKING findings"
  grep -qF "BLOCKING findings" "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md" \
    || log_fail "SKILL_TDD code-review gate must speak BLOCKING findings"
  grep -qiF "dual-verdict" "$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md" \
    || log_fail "AUTONOMOUS_LOOP Code reviewer must be described as dual-verdict"
  grep -qiF "dual-verdict" "$PROJECT_ROOT/.aai/system/SUPERPOWERS_INTEGRATION.md" \
    || log_fail "SUPERPOWERS_INTEGRATION must describe the dual-verdict review"

  log_pass "Dual-verdict taxonomy aligned on orchestration-facing surfaces (spec-review-taxonomy-alignment TEST-001..002)"
}

test_050_pr_merge_conflict() {  # spec-learned-to-layer-promotion TEST-001 / Spec-AC-01
  log_info "Test: SKILL_PR merge-conflict resolution + verify-merge + cleanup-after-MERGED (spec-learned-to-layer-promotion TEST-001)..."
  local f="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_PR.prompt.md"
  grep -qF "MERGE-CONFLICT RESOLUTION" "$f" \
    || log_fail "SKILL_PR must carry a MERGE-CONFLICT RESOLUTION section"
  grep -qF "generate-docs-index.mjs" "$f" \
    || log_fail "SKILL_PR must resolve docs/INDEX.md conflicts by regenerating via generate-docs-index.mjs"
  grep -qi "hand-merge" "$f" \
    || log_fail "SKILL_PR must forbid hand-merging docs/INDEX.md"
  grep -qF "[unreleased]" "$f" && grep -qiE "stack(s|ing)? both|both \[unreleased\]" "$f" \
    || log_fail "SKILL_PR must stack BOTH [unreleased] CHANGELOG entries on conflict"
  grep -qi "union merge" "$f" && grep -qF "EVENTS.jsonl" "$f" \
    || log_fail "SKILL_PR must union-merge docs/ai/EVENTS.jsonl conflicts (RFC-0001 append-only)"
  grep -qF "^<<<<<<<" "$f" \
    || log_fail "SKILL_PR must grep '^<<<<<<<' for surviving conflict markers before git add"
  grep -qF "MERGE_HEAD" "$f" \
    || log_fail "SKILL_PR must verify a merge actually happened (MERGE_HEAD / 2 parents) — dirty tree silently aborts git merge"
  grep -qiE "silently abort" "$f" \
    || log_fail "SKILL_PR must name the silent-abort failure mode of git merge on a dirty tree"
  grep -qF "gh pr view" "$f" && grep -qiE "only after .* MERGED|MERGED.*(before|then).*clean" "$f" \
    || log_fail "SKILL_PR must gate branch/worktree cleanup on gh pr view reporting MERGED"
  log_pass "SKILL_PR merge-conflict + verify-merge + cleanup-after-MERGED anchors present (spec-learned-to-layer-promotion TEST-001)"
}

test_051_no_number_prediction() {  # spec-learned-to-layer-promotion TEST-002 / Spec-AC-02
  log_info "Test: no-number-prediction rule in INTAKE_COMMON + SKILL_PR (spec-learned-to-layer-promotion TEST-002)..."
  local c="$PROJECT_ROOT/.aai/INTAKE_COMMON.md"
  local p="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  [[ -f "$c" ]] || log_fail "missing .aai/INTAKE_COMMON.md"
  [[ -f "$p" ]] || log_fail "missing .aai/SKILL_PR.prompt.md"
  grep -qiE "never predict" "$c" \
    || log_fail "INTAKE_COMMON.md must carry the never-predict-a-number rule"
  grep -qiE "never predict" "$p" \
    || log_fail "SKILL_PR must carry the never-predict-a-number rule"
  grep -qiE "after allocation" "$p" \
    || log_fail "SKILL_PR must state that commit messages / changelog entries / PR titles are written AFTER allocation"
  log_pass "no-number-prediction rule present in INTAKE_COMMON + SKILL_PR (spec-learned-to-layer-promotion TEST-002)"
}

test_052_loop_drift_preflight() {  # spec-learned-to-layer-promotion TEST-004 / Spec-AC-04
  log_info "Test: SKILL_LOOP layer-drift preflight + silent degrade (spec-learned-to-layer-promotion TEST-004)..."
  local f="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SKILL_LOOP.prompt.md"
  grep -qF "layer-drift.mjs" "$f" \
    || log_fail "SKILL_LOOP must run layer-drift.mjs at loop start (drift preflight)"
  # degrade + informational clauses must be co-located with the drift line
  grep -B3 -A5 "layer-drift.mjs" "$f" | grep -qiE "skip silently|silently skip" \
    || log_fail "SKILL_LOOP drift preflight must degrade silently when layer-drift.mjs is absent (older vendored layers)"
  grep -B3 -A5 "layer-drift.mjs" "$f" | grep -qi "informational" \
    || log_fail "SKILL_LOOP drift preflight must be informational (never block or branch on exit code)"
  log_pass "SKILL_LOOP drift preflight named with silent degrade (spec-learned-to-layer-promotion TEST-004)"
}

test_060_work_item_brief() {  # spec-work-item-brief TEST-001..006 / Spec-AC-01..02 (CHANGE work-item-brief)
  log_info "Test: work-item brief — template + PLANNING emit step + protocol handoff + gitignore (spec-work-item-brief TEST-001..006)..."
  local tpl="$PROJECT_ROOT/.aai/templates/BRIEF_TEMPLATE.md"
  local pl="$PROJECT_ROOT/.aai/PLANNING.prompt.md"
  local sp="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
  local cd="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
  local gi="$PROJECT_ROOT/.gitignore"

  # TEST-001 — template exists, <=60 lines, 5 section anchors, pointers-not-copies rule.
  [[ -f "$tpl" ]] || log_fail "missing .aai/templates/BRIEF_TEMPLATE.md"
  local n
  n="$(wc -l < "$tpl" | tr -d ' ')"
  [[ "$n" -le 60 ]] || log_fail "BRIEF_TEMPLATE.md must be <=60 lines (got $n)"
  local sec
  for sec in "## Scope & Why" "## AC ↔ Task Map" "## Constraints & Canon Pointers" "## Evidence Contract" "## Return Record"; do
    grep -qF "$sec" "$tpl" || log_fail "BRIEF_TEMPLATE.md must carry the section anchor '$sec'"
  done
  grep -qiF "never paste full copies" "$tpl" \
    || log_fail "BRIEF_TEMPLATE.md must carry the pointers-not-copies rule (canon paths only, never paste full copies)"

  # TEST-002 — Return Record skeleton is byte-identical to the SUBAGENT_CONTRACT
  # result block (single source; S1 seam crossed mechanically, not by prose).
  # Retargeted from SUBAGENT_PROTOCOL.md to SUBAGENT_CONTRACT.md
  # (spec-subagent-protocol-slim TEST-004: section 7 relocated to CONTRACT).
  [[ -f "$cd" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"
  grep -qF ".aai/SUBAGENT_CONTRACT.md" "$tpl" \
    || log_fail "BRIEF_TEMPLATE.md must cite the SUBAGENT_CONTRACT section 'Result block (mandatory subagent output)' as single source"
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  awk 'f&&/^```$/{exit} f{print} /^```yaml$/{f=1}' "$cd" > "$TEST_DIR/t60-proto.yaml"
  awk 'f&&/^```$/{exit} f{print} /^```yaml$/{f=1}' "$tpl" > "$TEST_DIR/t60-brief.yaml"
  grep -qF "subagent_result:" "$TEST_DIR/t60-proto.yaml" \
    || log_fail "could not extract the subagent_result skeleton from SUBAGENT_CONTRACT.md"
  grep -qF "subagent_result:" "$TEST_DIR/t60-brief.yaml" \
    || log_fail "BRIEF_TEMPLATE.md Return Record must embed the fenced subagent_result YAML skeleton"
  diff -u "$TEST_DIR/t60-proto.yaml" "$TEST_DIR/t60-brief.yaml" > "$TEST_DIR/t60.diff" \
    || log_fail "Return Record skeleton must be BYTE-IDENTICAL to the SUBAGENT_CONTRACT result block: $(cat "$TEST_DIR/t60.diff")"

  # TEST-003 — PLANNING emits the brief as a numbered step between freeze and STATE update.
  grep -qF "docs/ai/briefs/" "$pl" || log_fail "PLANNING must emit the brief under docs/ai/briefs/"
  grep -qF ".aai/templates/BRIEF_TEMPLATE.md" "$pl" || log_fail "PLANNING emit step must name the template path"
  grep -qiF "SPEC-FROZEN is false" "$pl" || log_fail "PLANNING emit step must skip while SPEC-FROZEN is false"
  grep -qiF "gitignored runtime artifact" "$pl" || log_fail "PLANNING emit step must state briefs are gitignored runtime artifacts"
  local l_freeze l_emit l_state
  l_freeze="$(grep -n "Set SPEC-FROZEN: true" "$pl" | head -1 | cut -d: -f1)"
  l_emit="$(grep -n "docs/ai/briefs/" "$pl" | head -1 | cut -d: -f1)"
  l_state="$(grep -n "Update docs/ai/STATE.yaml — PRIMARY PATH" "$pl" | head -1 | cut -d: -f1)"
  [[ -n "$l_freeze" && -n "$l_emit" && -n "$l_state" ]] \
    || log_fail "PLANNING must keep the freeze step, the emit step, and the STATE-update step greppable"
  [[ "$l_emit" -gt "$l_freeze" && "$l_emit" -lt "$l_state" ]] \
    || log_fail "PLANNING emit step must sit AFTER the SPEC-FROZEN step (line $l_freeze) and BEFORE the STATE-update step (line $l_state); got line $l_emit"

  # TEST-004 — gitignore block + behavioral check (S4: ask git, not just the text).
  grep -qF "docs/ai/briefs/**" "$gi" || log_fail ".gitignore must ignore docs/ai/briefs/**"
  grep -qF '!docs/ai/briefs/.gitkeep' "$gi" || log_fail ".gitignore must un-ignore docs/ai/briefs/.gitkeep (reports-style pattern)"
  [[ -f "$PROJECT_ROOT/docs/ai/briefs/.gitkeep" ]] || log_fail "docs/ai/briefs/.gitkeep placeholder must exist"
  git -C "$PROJECT_ROOT" check-ignore -q docs/ai/briefs/some-ref.md \
    || log_fail "git must ignore docs/ai/briefs/some-ref.md (runtime artifact class)"
  git -C "$PROJECT_ROOT" check-ignore -q docs/ai/briefs/.gitkeep \
    && log_fail "git must NOT ignore docs/ai/briefs/.gitkeep (directory placeholder stays committed)"

  # TEST-005 — protocol handoff: default-when-present + explicit degrade + single-source Return Record.
  grep -qF "docs/ai/briefs/" "$sp" || log_fail "SUBAGENT_PROTOCOL must name the brief path docs/ai/briefs/<ref>.md"
  grep -qiF "DEFAULTS to the brief" "$sp" || log_fail "SUBAGENT_PROTOCOL must make the brief the DEFAULT dispatch INPUT when present"
  grep -qiF "fall back to the spec path" "$sp" || log_fail "SUBAGENT_PROTOCOL must carry the degrade-to-spec-path clause"
  grep -qiF "never block a dispatch on a missing brief" "$sp" || log_fail "the degrade clause must state a missing brief never blocks a dispatch"
  grep -qF "Return Record" "$sp" && grep -qiF "verbatim" "$sp" \
    || log_fail "SUBAGENT_PROTOCOL must state the brief's Return Record is the result block, verbatim"
  grep -qF "CHANGE-0010 D1" "$sp" || log_fail "the MODEL contract row (CHANGE-0010 D1) must stay intact"
  grep -qF "MUST NOT characterize expected findings" "$sp" || log_fail "the review anti-gaming rules must stay intact"

  # TEST-006 — ORCHESTRATION wrapper untouched in behavior: the brief mention
  # stays out of it (SUBAGENT_PROTOCOL route intact) and it stays inside the
  # thin-wrapper ceiling. That ceiling is TEST-011's, not a private one: it was
  # raised 40->45 repo-wide by DEBT-0002 (2026-07-17), and
  # single-writer-canon-contradiction grew this file to 42/45 for the ENV row +
  # state_update_commands wiring — this line follows that ceiling rather than
  # re-pinning the pre-DEBT-0002 value.
  local orch="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
  n="$(wc -l < "$orch" | tr -d ' ')"
  [[ "$n" -le 45 ]] || log_fail "ORCHESTRATION.prompt.md must stay <=45 lines (TEST-011 thin-wrapper ceiling; got $n) — the brief mention belongs in SUBAGENT_PROTOCOL (spec D5)"
  grep -qF ".aai/SUBAGENT_PROTOCOL.md" "$orch" \
    || log_fail "ORCHESTRATION must keep routing dispatches through .aai/SUBAGENT_PROTOCOL.md (the brief mention's reachability path)"
  log_pass "Work-item brief wired: template ($(wc -l < "$tpl" | tr -d ' ') lines) + verbatim Return Record + PLANNING step + protocol default/degrade + gitignore (spec-work-item-brief TEST-001..006)"
}

test_080_subagent_contract_exists() {  # spec-subagent-protocol-slim TEST-001 / Spec-AC-01
  # Cap re-based 60 -> 90 by spec-the-subagent-contract-omits-the-hazards D1.
  # The cap's purpose is per-spawn payload cost, and the Standing hazards
  # section it makes room for LOWERS that cost: those ~40 lines were already
  # retyped into every dispatch as variable suffix bytes; in the CONTRACT they
  # are stable-prefix bytes the SPEC-0110/SPEC-0096 dispatch hash caches. The
  # cap is re-based, never removed — the sibling headroom guard
  # (test-aai-role-output.sh TEST-020) re-bases with it, to 84.
  log_info "Test: .aai/SUBAGENT_CONTRACT.md exists, <=90 lines, carries the required tokens (spec-subagent-protocol-slim TEST-001)..."
  local f="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"
  local n
  n="$(wc -l < "$f" | tr -d ' ')"
  [[ "$n" -le 90 ]] || log_fail "SUBAGENT_CONTRACT.md must be <=90 lines (got $n)"
  grep -qF "subagent_result:" "$f" \
    || log_fail "CONTRACT must carry the fenced subagent_result: result block"
  grep -qF "duration_seconds" "$f" \
    || log_fail "CONTRACT must carry the duration_seconds timing rule"
  grep -qiE "MUST NOT write.*STATE\.yaml" "$f" \
    || log_fail "CONTRACT must carry the MUST NOT write STATE.yaml rule"
  grep -qiE "sole.*(STATE )?writer|only .*STATE.* writer|sole writer" "$f" \
    || log_fail "CONTRACT must name the orchestrator as the sole STATE writer"
  grep -qF "docs/ai/tdd/" "$f" \
    || log_fail "CONTRACT must carry the allowed-write list entry docs/ai/tdd/"
  grep -qF "append-event.mjs" "$f" \
    || log_fail "CONTRACT must carry the allowed-write list entry append-event.mjs"
  grep -qiF "rationalization" "$f" \
    || log_fail "CONTRACT must carry the subagent-binding rationalization table"
  grep -qiF "self-report" "$f" \
    || log_fail "CONTRACT must carry the do-NOT-self-report-usage prohibition line"
  log_pass "SUBAGENT_CONTRACT.md present, $n lines, required tokens present (spec-subagent-protocol-slim TEST-001)"
}

test_081_no_rule_duplication() {  # spec-subagent-protocol-slim TEST-002 / Spec-AC-02
  log_info "Test: no rule sentence duplicated between CONTRACT and PROTOCOL — 5-phrase spot-grep (spec-subagent-protocol-slim TEST-002)..."
  local contract="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
  local protocol="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
  [[ -f "$contract" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"
  [[ -f "$protocol" ]] || log_fail "missing .aai/SUBAGENT_PROTOCOL.md"

  # (a) subagent_result: fence -> CONTRACT only
  grep -qF "subagent_result:" "$contract" \
    || log_fail "'subagent_result:' must be present in SUBAGENT_CONTRACT.md"
  grep -qF "subagent_result:" "$protocol" \
    && log_fail "'subagent_result:' must NOT remain in SUBAGENT_PROTOCOL.md (moved to CONTRACT)"

  # (b) MUST NOT write ... STATE.yaml -> CONTRACT only
  grep -qF 'MUST NOT write `docs/ai/STATE.yaml`' "$contract" \
    || log_fail "'MUST NOT write STATE.yaml' must be present in SUBAGENT_CONTRACT.md"
  grep -qF 'MUST NOT write `docs/ai/STATE.yaml`' "$protocol" \
    && log_fail "'MUST NOT write STATE.yaml' must NOT remain in SUBAGENT_PROTOCOL.md (moved to CONTRACT)"

  # (c) duration_seconds ... match -> CONTRACT only
  grep -qF 'duration_seconds` MUST match' "$contract" \
    || log_fail "'duration_seconds MUST match' must be present in SUBAGENT_CONTRACT.md"
  grep -qF 'duration_seconds` MUST match' "$protocol" \
    && log_fail "'duration_seconds MUST match' must NOT remain in SUBAGENT_PROTOCOL.md (moved to CONTRACT)"

  # (d) never from a subagent's own self-report -> PROTOCOL only
  grep -qF "never from a subagent's own self-report" "$protocol" \
    || log_fail "'never from a subagent's own self-report' must be present in SUBAGENT_PROTOCOL.md"
  grep -qF "never from a subagent's own self-report" "$contract" \
    && log_fail "'never from a subagent's own self-report' must NOT appear in SUBAGENT_CONTRACT.md (orchestrator-only)"

  # (e) MUST NOT characterize expected findings -> PROTOCOL only
  grep -qF "MUST NOT characterize expected findings" "$protocol" \
    || log_fail "'MUST NOT characterize expected findings' must be present in SUBAGENT_PROTOCOL.md"
  grep -qF "MUST NOT characterize expected findings" "$contract" \
    && log_fail "'MUST NOT characterize expected findings' must NOT appear in SUBAGENT_CONTRACT.md (orchestrator-only)"

  log_pass "5-phrase spot-grep: each phrase lives in exactly one file (spec-subagent-protocol-slim TEST-002)"
}

test_082_dispatch_refs_name_contract() {  # spec-subagent-protocol-slim TEST-003 / Spec-AC-03
  log_info "Test: dispatch payload refs name SUBAGENT_CONTRACT.md; orchestrator-only refs stay on SUBAGENT_PROTOCOL.md (spec-subagent-protocol-slim TEST-003)..."
  local orch_p="$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md"
  local loop="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
  local val="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  local tpl="$PROJECT_ROOT/.aai/templates/BRIEF_TEMPLATE.md"
  [[ -f "$orch_p" ]] || log_fail "missing .aai/ORCHESTRATION_PARALLEL.prompt.md"
  [[ -f "$loop" ]] || log_fail "missing .aai/SKILL_LOOP.prompt.md"
  [[ -f "$val" ]] || log_fail "missing .aai/VALIDATION.prompt.md"
  [[ -f "$tpl" ]] || log_fail "missing .aai/templates/BRIEF_TEMPLATE.md"

  # ORCHESTRATION_PARALLEL: payload refs -> CONTRACT
  grep -qF '`.aai/SUBAGENT_CONTRACT.md`, Single-writer rule' "$orch_p" \
    || log_fail "ORCHESTRATION_PARALLEL single-writer pointer must name SUBAGENT_CONTRACT.md"
  grep -qF 'a copy of .aai/SUBAGENT_CONTRACT.md' "$orch_p" \
    || log_fail "ORCHESTRATION_PARALLEL subagent context must pass a copy of SUBAGENT_CONTRACT.md"
  grep -qF 'result block as defined in .aai/SUBAGENT_CONTRACT.md' "$orch_p" \
    || log_fail "ORCHESTRATION_PARALLEL result-block reference must name SUBAGENT_CONTRACT.md"
  # ORCHESTRATION_PARALLEL: orchestrator-only refs stay on PROTOCOL
  grep -qF 'See .aai/SUBAGENT_PROTOCOL.md' "$orch_p" \
    || log_fail "ORCHESTRATION_PARALLEL validator-spawning pointer must stay on SUBAGENT_PROTOCOL.md"
  grep -qF 'merge protocol from .aai/SUBAGENT_PROTOCOL.md' "$orch_p" \
    || log_fail "ORCHESTRATION_PARALLEL merge-protocol reference must stay on SUBAGENT_PROTOCOL.md"

  # SKILL_LOOP: validator-payload ref -> CONTRACT; harness-usage refs stay PROTOCOL
  grep -qF '.aai/SUBAGENT_CONTRACT.md) — never the implementer'"'"'s accumulated working' "$loop" \
    || log_fail "SKILL_LOOP validator-payload context must name SUBAGENT_CONTRACT.md"
  grep -qF "SUBAGENT_PROTOCOL.md" "$loop" \
    || log_fail "SKILL_LOOP must retain at least one SUBAGENT_PROTOCOL.md mention (harness-usage refs, token-capture TEST-001)"

  # VALIDATION: per-subagent payload ref -> CONTRACT; merge-protocol ref stays PROTOCOL
  grep -qF 'linked spec items, and .aai/SUBAGENT_CONTRACT.md' "$val" \
    || log_fail "VALIDATION per-subagent payload reference must name SUBAGENT_CONTRACT.md"
  grep -qF 'merged per .aai/SUBAGENT_PROTOCOL.md' "$val" \
    || log_fail "VALIDATION merge-protocol reference must stay on SUBAGENT_PROTOCOL.md"

  # BRIEF_TEMPLATE single-source citation
  grep -qF '.aai/SUBAGENT_CONTRACT.md section' "$tpl" \
    || log_fail "BRIEF_TEMPLATE single-source citation must name SUBAGENT_CONTRACT.md"

  # IMPLEMENTATION + SKILL_TDD: unit payload + expert result-block refs -> CONTRACT
  # (validation FAIL 20260726T184217Z caught IMPLEMENTATION:121 leaking the
  # full protocol into every parallel Implementation unit payload; the merge
  # and spawn-criteria refs legitimately stay on PROTOCOL.)
  local impl="$PROJECT_ROOT/.aai/IMPLEMENTATION.prompt.md"
  local tdd="$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"
  grep -qF 'Spec-AC items, and .aai/SUBAGENT_CONTRACT.md' "$impl" \
    || log_fail "IMPLEMENTATION unit payload must name SUBAGENT_CONTRACT.md (never the full protocol)"
  grep -qF 'result block per `.aai/SUBAGENT_CONTRACT.md`' "$impl" \
    || log_fail "IMPLEMENTATION expert result-block reference must name SUBAGENT_CONTRACT.md"
  grep -qF 'merged per .aai/SUBAGENT_PROTOCOL.md' "$impl" \
    || log_fail "IMPLEMENTATION merge-protocol reference must stay on SUBAGENT_PROTOCOL.md"
  grep -qF 'result block per `.aai/SUBAGENT_CONTRACT.md`' "$tdd" \
    || log_fail "SKILL_TDD expert result-block reference must name SUBAGENT_CONTRACT.md"

  log_pass "Dispatch payload refs resolve to SUBAGENT_CONTRACT.md; orchestrator-only refs stay on SUBAGENT_PROTOCOL.md (spec-subagent-protocol-slim TEST-003)"
}

# --- spec-the-subagent-contract-omits-the-hazards TEST-001..003 --------------
# The Standing hazards section IS the change: those rules were written verbatim
# into every dispatch, read, and still failed twice (fu-subagent-probe-hits-
# real-repo P1 2026-08-15; commit 485a315 2026-08-22), so they moved into the
# payload every subagent receives.
#
# An arm that only asserted "the heading exists" would stay green on a section
# someone quietly emptied while tidying up, which is exactly how the rules got
# lost the first time. So the check is a REPORTER (hazards_findings) plus a bite
# proof: the shipped file must report nothing, and a COPY with any one hazard —
# or any one incident citation — removed must report that specific loss.
#
# The mutation only ever touches a copy under TEST_DIR; the tracked CONTRACT is
# read and then proved byte-unchanged. This arm is bound by the HAZ-RESTORE rule
# it pins.

# The five hazard anchors and the five incident citations they must carry. Ids,
# not prose fragments: prose gets reworded by the next editor, anchors do not.
HAZ_IDS=(HAZ-RESTORE HAZ-SCRATCH HAZ-CD HAZ-LEDGER HAZ-WORKTREE)
# EVERY scar below is a registry id, resolvable by anyone with the repository:
# `node .aai/scripts/follow-ups.mjs list --status all`. An earlier version cited
# commit 485a315 for HAZ-CD. Codex caught that it resolves ONLY in the author's
# reflog — `git cat-file -t 485a315` fails in every clone, including CI and
# every reviewer's. A citation that only its writer can check is not evidence,
# which is the defect class this whole section exists to name. It also cited
# follow-ups.mjs, a script header rather than an incident; that one was replaced
# during validation for the same reason.
HAZ_SCARS=(
  fu-orchestrator-mutated-real-file
  fu-subagent-probe-hits-real-repo
  fu-empty-path-cd-stays-in-shipping-repo
  # HAZ-LEDGER's scar was `follow-ups.mjs` (a script header describing a
  # rollback that would truncate). Validation judged that weaker than its four
  # neighbours — a design note, not an incident — and it was wrong besides:
  # fu-append-only-merge-needs-prefix-order records ledger bytes ACTUALLY
  # rewritten, caught in CI as DIVERGES at byte offset 248943.
  fu-append-only-merge-needs-prefix-order
  fu-prune-repair-error-string-misquoted
)

# hazards_section <file> — the body of '## Standing hazards' up to the next
# level-2 heading. Prints nothing when the section is absent.
hazards_section() {
  awk '/^## Standing hazards/{f=1;next} f&&/^## /{exit} f' "$1"
}

# hazards_findings <file> — one MISSING-* token per absent requirement, nothing
# when complete. It REPORTS and never judges: it must not call log_fail, because
# the bite half of the arm runs it against a deliberately broken copy and
# log_fail exits the whole suite.
hazards_findings() {
  local _hf_file="$1" _hf_body _hf_tok
  # CARDINALITY FIRST. Validation broke this arm by emptying HAZ_IDS/HAZ_SCARS:
  # on bash >= 4.4 (ubuntu CI) an empty array under `set -u` expands to nothing,
  # both loops below run zero times, and the arm printed "all 0 anchors + 0
  # incident citations; bite proved on 0 mutations" at rc 0. A guard reporting
  # success over an empty corpus is the exact defect this programme has spent
  # three days removing — reproduced inside the arm that enforces the rules
  # against it. Never a pass on an unmeasured zero.
  if [[ "${#HAZ_IDS[@]}" -lt 5 || "${#HAZ_SCARS[@]}" -lt 5 ]]; then
    printf 'UNCOVERED-EMPTY-CORPUS ids=%s scars=%s (want >=5 each; with fewer, this arm asserts nothing)\n' \
      "${#HAZ_IDS[@]}" "${#HAZ_SCARS[@]}"
    return 0
  fi
  _hf_body="$(hazards_section "$_hf_file")"
  if [[ -z "${_hf_body//[[:space:]]/}" ]]; then
    printf 'MISSING-SECTION\n'
    return 0
  fi
  for _hf_tok in "${HAZ_IDS[@]}"; do
    case "$_hf_body" in
      *"$_hf_tok"*) ;;
      *) printf 'MISSING-%s\n' "$_hf_tok" ;;
    esac
  done
  for _hf_tok in "${HAZ_SCARS[@]}"; do
    case "$_hf_body" in
      *"$_hf_tok"*) ;;
      *) printf 'MISSING-SCAR-%s\n' "$_hf_tok" ;;
    esac
  done
  return 0
}

test_083_subagent_contract_hazards() {  # spec-the-subagent-contract-omits-the-hazards TEST-001..003
  log_info "Test: SUBAGENT_CONTRACT carries the Standing hazards section with all five hazards + their incidents, and the check BITES when one is removed (spec-the-subagent-contract-omits-the-hazards TEST-001..003)..."
  local f="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
  [[ -f "$f" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"

  # (a) CONTROL — the shipped, unmutated CONTRACT reports nothing missing.
  local found
  found="$(hazards_findings "$f")"
  [[ -z "$found" ]] \
    || log_fail "SUBAGENT_CONTRACT.md '## Standing hazards' is incomplete: ${found//$'\n'/ } — every hazard needs its anchor AND the measured incident that produced it (a rule without its scar gets deleted by the next tidy-up)"

  # (b) The lever. No writable scratch dir means the bite proof cannot run, and
  # an unrun bite proof is UNCOVERED, never a pass.
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" && -w "$TEST_DIR" ]] \
    || log_fail "test_083 UNCOVERED — no writable scratch directory, so the per-hazard mutation bite proof did not run; this arm reports UNCOVERED rather than passing on an unexercised check"
  local pristine="$TEST_DIR/t83-contract-pristine.md"
  cp "$f" "$pristine"

  # (c) BITE — drop ONE token at a time from a COPY and require the reporter to
  # name exactly that loss. A mutation that removed nothing proves nothing, so
  # it is UNCOVERED, not a pass.
  #
  # Both UNCOVERED branches were driven and observed exiting 1, not passing
  # (2026-08-23, in a disposable worktree): (b) with TEST_DIR pointed at a path
  # under a chmod-500 directory, and (c) with a token the reporter sees but the
  # file does not carry. Neither can fire on a healthy tree — which is the
  # point; they exist so a future edit that decouples the reporter's corpus
  # from the mutation's corpus turns red instead of quietly green.
  local tok mutated
  for tok in "${HAZ_IDS[@]}" "${HAZ_SCARS[@]}"; do
    mutated="$TEST_DIR/t83-without-$tok.md"
    grep -vF -- "$tok" "$pristine" > "$mutated" || true
    if cmp -s "$pristine" "$mutated"; then
      log_fail "test_083 UNCOVERED — removing '$tok' changed nothing, so the assertion below would have 'bitten' on an unmutated file; the token is not where this arm thinks it is"
    fi
    found="$(hazards_findings "$mutated")"
    case "$found" in
      *"MISSING-$tok"*|*"MISSING-SCAR-$tok"*) ;;
      *) log_fail "test_083: the hazards check did NOT bite when '$tok' was removed (reported: '${found:-<nothing>}'). A check that stays green on a deleted hazard is the exact failure this change exists to prevent" ;;
    esac
  done

  # (d) SELF-BINDING — prove the arm mutated only copies. It pins HAZ-RESTORE;
  # it does not get to be the thing that breaks it.
  cmp -s "$f" "$pristine" \
    || log_fail "test_083: the tracked .aai/SUBAGENT_CONTRACT.md changed while this arm ran — the mutation proof must only ever write copies under TEST_DIR (HAZ-RESTORE)"

  log_pass "Standing hazards present with all ${#HAZ_IDS[@]} anchors + ${#HAZ_SCARS[@]} incident citations; bite proved on $(( ${#HAZ_IDS[@]} + ${#HAZ_SCARS[@]} )) mutations with the tracked file byte-unchanged (spec-the-subagent-contract-omits-the-hazards TEST-001..003)"
}

test_093_test_registration() {  # CHANGE test-registration-guard
  log_info "test_093: every defined test_* function in every suite is referenced beyond its definition (registered)..."
  local out rc=0
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$PROJECT_ROOT/tests/skills" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '%s\n' "$out" | head -10
    log_fail "test_093: orphan (defined-but-unreferenced) test function(s) — a green suite with an unwired pin is not coverage (the #229 class)"
    return 1
  fi
  log_pass "test_093: no orphan test functions"
}

test_092_no_phantom_node_apis() {  # CHANGE phantom-api-pin: APIs that LOOK real but do not exist
  log_info "test_092: no .mjs script calls a known-phantom Node API (bit us live: process.getpgrp)..."
  # Each entry is an API that plausibly exists (POSIX cousin, docs folklore)
  # but is NOT in Node's runtime — a call site compiles, reviews clean, and
  # only fails (or silently misbehaves inside try/catch) in production.
  # process.getpgrp: shipped in orphan-sweep's self-guard, caught by a PR bot,
  # not by author or internal review (CHANGE-0108 sweep, 2026-08-02).
  local phantoms='process\.getpgrp|process\.getpgid|process\.setpgrp|fs\.exists\(|require\.main\.filename'
  # exit-code contract: 0=hits, 1=clean, 2=scan error. A scan error must FAIL
  # loudly (bot review: masking it makes the denylist silently ineffective).
  # set -e safe: capture rc via && / || (a bare rc=$? after the substitution
  # aborts the whole suite on grep's exit 1 = clean tree — bit us on CI).
  local hits rc
  hits="$(grep -rnE "$phantoms" "$PROJECT_ROOT/.aai/scripts" --include='*.mjs' 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ge 2 ]]; then
    log_fail "test_092: phantom-API scan itself failed (grep exit $rc): $hits"
    return 1
  fi
  if [[ "$rc" -eq 0 && -n "$hits" ]]; then
    log_info "test_092: phantom/deprecated API call site(s):"
    printf '%s\n' "$hits" | head -5
    log_fail "test_092: phantom Node API in .aai/scripts (verify against the runtime: node -e 'console.log(typeof <api>)')"
    return 1
  fi
  log_pass "test_092: no phantom Node APIs in .aai/scripts"
}
test_091_session_journal_index_complete() {  # CHANGE-0080: every journal has an INDEX row
  log_info "test_091: every docs/project-sessions/*.md (except INDEX.md) has a row in INDEX.md..."
  local idx="$PROJECT_ROOT/docs/project-sessions/INDEX.md"
  [[ -f "$idx" ]] || { log_fail "test_091: $idx missing"; return 1; }
  local f base missing=0
  for f in "$PROJECT_ROOT"/docs/project-sessions/*.md; do
    base="$(basename "$f")"
    [[ "$base" == "INDEX.md" ]] && continue
    if ! grep -qF "($base)" "$idx"; then
      log_info "test_091: journal $base has NO row in $idx"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || { log_fail "test_091: session-journal INDEX is incomplete (CHANGE-0080 contract)"; return 1; }
  log_pass "test_091: session-journal INDEX complete"
}

test_090_suite_map_pin() {  # spec-ci-test-impact-selection TEST-014 / Spec-AC-03
  log_info "Test: every tests/skills/test-aai-*.sh has a tests/skills/suite-map.yaml row (spec-ci-test-impact-selection AC-003)..."
  local map="$PROJECT_ROOT/tests/skills/suite-map.yaml"
  [[ -f "$map" ]] || log_fail "missing tests/skills/suite-map.yaml"
  local f name missing=0
  for f in "$PROJECT_ROOT"/tests/skills/test-aai-*.sh; do
    name="$(basename "$f" .sh)"
    name="${name#test-}"
    grep -qE "^  ${name}:\$" "$map" \
      || { log_info "MISSING suite-map row for: $name"; missing=1; }
  done
  [[ "$missing" -eq 0 ]] \
    || log_fail "one or more test-aai-*.sh suites have no tests/skills/suite-map.yaml row (see MISSING lines above) — a new suite must be mapped or it silently escapes selection accounting"
  log_pass "Every test-aai-*.sh suite has a suite-map.yaml row (spec-ci-test-impact-selection AC-003)"
}

test_070_companion_obligations() {  # spec-planning-companion-obligations TEST-001..003 / Spec-AC-01..03
  log_info "Test: PLANNING companion-obligations checklist — both triggers + companions + files, closed to 2 (spec-planning-companion-obligations TEST-001..003)..."
  local pl="$PROJECT_ROOT/.aai/PLANNING.prompt.md"
  [[ -f "$pl" ]] || log_fail "missing .aai/PLANNING.prompt.md"

  # Heading present (RED-proof: grep -c "COMPANION OBLIGATIONS" = 0 today).
  grep -qF "COMPANION OBLIGATIONS" "$pl" \
    || log_fail "PLANNING must carry a COMPANION OBLIGATIONS checklist step"

  # TEST-001 — positioned BEFORE the existing '4) Create or update docs/specs' step.
  local l_check l_spec
  l_check="$(grep -n "COMPANION OBLIGATIONS" "$pl" | head -1 | cut -d: -f1)"
  l_spec="$(grep -n "Create or update docs/specs" "$pl" | head -1 | cut -d: -f1)"
  [[ -n "$l_check" && -n "$l_spec" ]] \
    || log_fail "PLANNING must keep both the COMPANION OBLIGATIONS step and the 'Create or update docs/specs' step greppable"
  [[ "$l_check" -lt "$l_spec" ]] \
    || log_fail "COMPANION OBLIGATIONS step (line $l_check) must sit BEFORE the spec-creation step (line $l_spec)"

  # Extract the checklist block: from the heading line to the next numbered step.
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  local blk="$TEST_DIR/t70-block.txt"
  awk '/COMPANION OBLIGATIONS/{f=1} f&&/^[0-9]+\)/{exit} f{print}' "$pl" > "$blk"
  [[ -s "$blk" ]] || log_fail "could not extract the COMPANION OBLIGATIONS block from PLANNING"

  # TEST-001 — trigger 1 (prompt-corpus byte growth) -> ledger true-up companion + file.
  grep -qF "prompt corpus" "$blk" \
    || log_fail "block must name trigger 1: prompt-corpus byte growth"
  grep -qF "JUSTIFIED_ADDITIONS" "$blk" \
    || log_fail "block must name the prompt-diet ledger true-up companion (JUSTIFIED_ADDITIONS entry)"
  grep -qF "tests/skills/lib/prompt-diet-ledger.sh" "$blk" \
    || log_fail "block must point trigger 1 at tests/skills/lib/prompt-diet-ledger.sh"

  # TEST-002 — trigger 2 (a new .aai/** file) -> PROFILES.yaml classification companion + file.
  grep -qF ".aai/**" "$blk" \
    || log_fail "block must name trigger 2: a new .aai/** file"
  grep -qiF "classif" "$blk" \
    || log_fail "block must name the PROFILES classification companion"
  grep -qF ".aai/system/PROFILES.yaml" "$blk" \
    || log_fail "block must point trigger 2 at .aai/system/PROFILES.yaml"

  # TEST-003 — CLOSED to exactly two trigger bullets (no third obligation, no
  # auto-detection guard added). Counts bullet lines that carry a '->' mapping;
  # the trailing 'Neither applies -> skip' line is not a bullet and is excluded.
  local bullets
  bullets="$(grep -cE '^[[:space:]]*-[[:space:]].*->' "$blk" || true)"
  [[ "$bullets" -eq 2 ]] \
    || log_fail "COMPANION OBLIGATIONS block must contain EXACTLY 2 trigger bullets (closed list), got $bullets"

  log_pass "PLANNING companion-obligations checklist: both triggers + companions + files, closed to 2 bullets (spec-planning-companion-obligations TEST-001..003)"
}

# --- spec-assertions-must-not-die-on-their-own-payload ----------------------
# TEST-001..006. An assertion that pipes its payload into `grep -q` reports
# FAILURE on a payload that MATCHED, once the payload passes the 64 KiB pipe
# buffer: `grep -q` exits at the first match, the writer takes SIGPIPE (141),
# and `set -o pipefail` promotes that to the pipeline's status. These arms own
# the pipe-free helper (tests/skills/lib/assert-payload.sh) and the corpus
# ratchet that stops new occurrences of the shape being added silently.
AP_LIB_REL="tests/skills/lib/assert-payload.sh"
PGQ_LIB_REL="tests/skills/lib/pipe-grep-q-ratchet.sh"
PGQ_BASELINE_REL="tests/skills/lib/pipe-grep-q-baseline.tsv"

# THE PIPE CHARACTER IS PARAMETERISED THROUGHOUT THESE ARMS, ON PURPOSE.
# The ratchet scans tests/skills/*.sh — including THIS FILE — for the literal
# shape: an echo or printf of a variable, piped into a quiet grep. (Even THIS
# COMMENT matched it in an earlier draft and put this suite in the baseline at
# 2 — the scanner does not care that the occurrence is prose.) The fixtures
# below must CONTAIN that shape to prove the ratchet bites and to reproduce the
# 141 that justifies all of this, but writing it literally
# here would make this suite the corpus's newest offender and would ratchet the
# ratchet's own demonstrations. Substituting the bar keeps this file at zero
# real occurrences. Do not "tidy" it back to a literal `|`.
PGQ_BAR='|'

# Absolute path: `grep` resolves to a ugrep shell function in this repo's
# environment even non-interactively, and a measurement must not depend on
# whose shell ran it.
PGQ_GREP_BIN=/usr/bin/grep
[[ -x "$PGQ_GREP_BIN" ]] || PGQ_GREP_BIN=grep

ap_tmpdir() {
  TEST_DIR="${TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/aai-hygiene.XXXXXX")}"
  printf '%s' "$TEST_DIR"
}

# ap_payload <lines> <needle> — a payload built with NO pipe anywhere. `yes |
# head` is itself a pipefail SIGPIPE trap and would kill the fixture before it
# reached the assertion under test (measured while writing these arms).
ap_payload() {
  awk -v n="$1" -v needle="$2" 'BEGIN{
    print needle
    for (i = 0; i < n; i++) print "filler line padding the payload past the pipe buffer"
  }'
}

# ap_grep_lines <count> <file> — append <count> occurrences of the UNSAFE shape.
ap_grep_lines() {
  local _n="$1" _f="$2" _i=0
  while [[ "$_i" -lt "$_n" ]]; do
    printf 'echo "$out%s" %s grep -qF needle%s\n' "$_i" "$PGQ_BAR" "$_i" >> "$_f"
    _i=$(( _i + 1 ))
  done
}

test_100_assert_payload_contract() {  # TEST-001 / Spec-AC-02
  log_info "test_100: pipe-free payload assertions — needle named, preview bounded, vacuous needle refused (TEST-001)..."
  local lib="$PROJECT_ROOT/$AP_LIB_REL" d
  [[ -f "$lib" ]] || log_fail "test_100: missing $AP_LIB_REL"
  d="$(ap_tmpdir)"

  # Every probe runs in a CHILD bash that sources the library WITHOUT a
  # log_fail of its own, so what is measured is the helper's own stderr +
  # return-1 fallback, and a deliberately failing probe cannot take this suite
  # down with it.
  # `--payload-file <f>` reads the payload from a FILE instead of argv. Not a
  # convenience: Linux caps a SINGLE argument at MAX_ARG_STRLEN (32 pages =
  # 131072 B) even though ARG_MAX is far larger, so passing the ~220 KB
  # oversize fixture as an argument makes execve fail with E2BIG and bash
  # reports 126. darwin has no such per-argument cap, so case (c) passed
  # locally and turned CI red — a platform threshold in the FIXTURE, not in
  # the code under test. The `printf x` / `%x` pair preserves trailing
  # newlines that `$(cat)` would strip, so the byte count the probe sees is
  # the byte count this suite computed.
  local probe="$d/ap-probe.sh"
  cat > "$probe" <<PROBE
. '$lib'
fn="\$1"; shift
if [ "\${1:-}" = "--payload-file" ]; then
  shift
  ap_arg="\$(cat "\$1"; printf x)"; ap_arg="\${ap_arg%x}"
  shift
  "\$fn" "\$ap_arg" "\$@"
else
  "\$fn" "\$@"
fi
PROBE

  local out rc
  # (a) present -> exit 0, silent.
  out="$(bash "$probe" assert_payload_contains "alpha beta gamma" "beta" "must find beta" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_100(a): a present needle must pass, got exit $rc: $out"
  [[ -z "$out" ]] || log_fail "test_100(a): a passing assertion must print nothing, got: $out"

  # (b) absent -> exit 1, message names BOTH the needle and the caller's text.
  out="$(bash "$probe" assert_payload_contains "alpha beta gamma" "delta" "must find delta" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "test_100(b): an absent needle must exit 1, got $rc"
  [[ "$out" == *"delta"* ]] || log_fail "test_100(b): the failure must NAME the needle, got: $out"
  [[ "$out" == *"must find delta"* ]] || log_fail "test_100(b): the failure must carry the caller's message, got: $out"

  # (c) BOUNDED PREVIEW. The incident behind this spec printed a FAIL line with
  # 46 KB of findings after `got:`. A ~220 KB payload must produce a message
  # small enough to read, and must state the TRUE total so the truncation can
  # never be mistaken for the whole payload.
  local big
  big="$(ap_payload 4000 'needle-here')"
  local biglen
  biglen="$(LC_ALL=C; printf '%s' "${#big}")"
  [[ "$biglen" -gt 65536 ]] \
    || log_fail "test_100(c): the fixture payload must exceed the 64 KiB pipe buffer to be meaningful, got $biglen B"
  printf '%s' "$big" > "$d/big-arg.txt"
  out="$(bash "$probe" assert_payload_contains --payload-file "$d/big-arg.txt" "absent-zzz" "big payload miss" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] \
    || log_fail "test_100(c): expected exit 1, got $rc (126 means the payload went through argv and hit Linux MAX_ARG_STRLEN)"
  local outlen
  outlen="$(LC_ALL=C; printf '%s' "${#out}")"
  [[ "$outlen" -lt 1200 ]] \
    || log_fail "test_100(c): the failure message must stay bounded, got $outlen B for a $biglen B payload"
  [[ "$out" == *"$biglen bytes total, truncated to 512"* ]] \
    || log_fail "test_100(c): the message must state the TRUE total ($biglen) and the bound, got: $out"

  # (d) CONTROL for (c): a payload UNDER the bound is printed WHOLE and is not
  # labelled truncated. Without this, (c) would also pass a helper that simply
  # printed a fixed string and never showed the payload at all.
  out="$(bash "$probe" assert_payload_contains "short-payload-marker" "absent-zzz" "small payload miss" 2>&1)" && rc=0 || rc=$?
  [[ "$out" == *"short-payload-marker"* ]] \
    || log_fail "test_100(d): a small payload must be shown in full, got: $out"
  [[ "$out" != *"truncated"* ]] \
    || log_fail "test_100(d): a small payload must NOT be labelled truncated, got: $out"

  # (e) the not-contains direction, both ways.
  out="$(bash "$probe" assert_payload_not_contains "alpha beta" "zeta" "must not find zeta" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_100(e): an absent needle must pass not_contains, got $rc: $out"
  out="$(bash "$probe" assert_payload_not_contains "alpha beta" "beta" "must not find beta" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "test_100(e): a present needle must FAIL not_contains, got $rc"
  [[ "$out" == *"beta"* ]] || log_fail "test_100(e): not_contains failure must name the needle, got: $out"

  # (f) VACUITY GUARD on the guard. An empty needle matches every payload, so
  # an assertion whose needle expanded to nothing would pass forever while
  # testing nothing. Both directions must REFUSE it, not answer it.
  out="$(bash "$probe" assert_payload_contains "anything at all" "" "empty needle" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] \
    || log_fail "test_100(f): assert_payload_contains must REFUSE an empty needle (it matches everything), got exit $rc"
  [[ "$out" == *"vacuous"* ]] || log_fail "test_100(f): the refusal must say why, got: $out"
  out="$(bash "$probe" assert_payload_not_contains "anything at all" "" "empty needle" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] \
    || log_fail "test_100(f): assert_payload_not_contains must REFUSE an empty needle, got exit $rc"

  # (g) DELEGATION: when the sourcing suite has its own log_fail, the helper
  # uses it, so a suite's existing failure convention and exit code survive.
  local dprobe="$d/ap-probe-delegating.sh"
  cat > "$dprobe" <<PROBE
log_fail() { echo "SUITE-LOG-FAIL: \$*" >&2; exit 7; }
. '$lib'
assert_payload_contains "alpha" "omega" "delegated message"
echo "UNREACHABLE"
PROBE
  out="$(bash "$dprobe" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 7 ]] \
    || log_fail "test_100(g): the helper must delegate to the suite's log_fail (expected exit 7), got $rc: $out"
  [[ "$out" == *"SUITE-LOG-FAIL: delegated message"* ]] \
    || log_fail "test_100(g): the suite's log_fail must receive the message, got: $out"
  [[ "$out" != *"UNREACHABLE"* ]] \
    || log_fail "test_100(g): delegation must not fall through past the suite's exiting log_fail"

  log_pass "test_100: helper names the needle, bounds the preview at 512 B, refuses a vacuous needle, delegates to log_fail (TEST-001)"
}

test_101_helper_survives_the_pipe_buffer() {  # TEST-002 / Spec-AC-02
  log_info "test_101: a >64 KiB MATCHING payload makes the old idiom FAIL under pipefail and passes the helper (TEST-002)..."
  local lib="$PROJECT_ROOT/$AP_LIB_REL" d
  d="$(ap_tmpdir)"

  # One payload, three runs. It MATCHES in all three — every failure below is
  # the mechanism, never a missing needle.
  local big biglen
  big="$(ap_payload 4000 'needle-here')"
  biglen="$(LC_ALL=C; printf '%s' "${#big}")"
  [[ "$biglen" -gt 65536 ]] || log_fail "test_101: fixture payload $biglen B does not clear the 64 KiB buffer"

  # CONTROL A — the hazard is REAL on this machine right now. Without this, a
  # green subject below would prove nothing: the helper could be passing
  # because the platform never had the defect.
  #
  # The ABSOLUTE grep path is load-bearing. Measured: run under a `grep` shim
  # that slurps stdin to EOF (this repo's ugrep wrapper does, and so does the
  # census shim used to size this very change), the bare-name form exits 0 and
  # this control fires — correctly, but for the wrong reason. Pinning the
  # binary makes the control measure the POSIX grep the corpus's 390 sites
  # actually resolve to in CI, instead of whatever the operator's shell put in
  # front of it.
  local old="$d/old-idiom.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n' 'big="$(cat "$1")"'
    printf 'printf "%%s\\n" "$big" %s %s -qF "needle-here"\n' "$PGQ_BAR" "$PGQ_GREP_BIN"
  } > "$old"
  printf '%s\n' "$big" > "$d/big.txt"
  local rc

  # CONTROL B RUNS FIRST, and the order is the whole argument. B establishes
  # that this idiom, this needle and this generator produce exit 0 at a small
  # size. Only then can A's non-zero mean "the pipe killed it" rather than
  # "the needle was not there" — those are otherwise indistinguishable, both
  # being exit 1 on Linux. The original arm ran A first, so when A failed on
  # CI the discriminator never executed and the log could not say which had
  # happened.
  local small
  small="$(ap_payload 40 'needle-here')"
  printf '%s\n' "$small" > "$d/small.txt"
  bash "$old" "$d/small.txt" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "test_101 CONTROL B: the same idiom on a SMALL matching payload must pass, got $rc — the needle, the generator or the grep binary is wrong and nothing below this line would mean anything"

  # CONTROL A — the hazard is REAL on this machine right now. The EXIT CODE is
  # platform-dependent and the arm must not pin one of them:
  #   141 — the writer dies by SIGPIPE (macOS, bash 3.2.57)
  #     1 — bash reports EPIPE from its printf BUILTIN as a write error and
  #         returns 1 instead of dying by the signal (Linux CI, bash 5.x)
  # Pinning 141 turned CI red on a machine where the defect reproduced
  # perfectly well, just with a different number. What both share, and what
  # actually matters, is that the pipeline reports FAILURE under pipefail on a
  # payload that MATCHED — which CONTROL B above has just proved it does.
  bash "$old" "$d/big.txt" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] \
    || log_fail "test_101 CONTROL A: the old idiom on a $biglen B MATCHING payload must FAIL under pipefail, got 0 — the buffer hazard did not reproduce here and the rest of this arm is vacuous"
  [[ "$rc" -eq 141 || "$rc" -eq 1 ]] \
    || log_fail "test_101 CONTROL A: expected 141 (SIGPIPE) or 1 (bash builtin EPIPE), got $rc — an unrecognised failure mode, do not assume it is the same defect"
  local rc_a="$rc"
  log_info "  CONTROL A: old idiom on ${biglen} B matching payload -> exit $rc_a (141=SIGPIPE, 1=bash builtin EPIPE)"

  # SUBJECT — the helper, same payload, under the same set -euo pipefail.
  local new="$d/new-helper.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf '. %s\n' "'$lib'"
    printf '%s\n' 'big="$(cat "$1")"'
    printf '%s\n' 'assert_payload_contains "$big" "needle-here" "the payload must carry the needle"'
    printf '%s\n' 'echo HELPER-OK'
  } > "$new"
  local out
  out="$(bash "$new" "$d/big.txt" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "test_101 SUBJECT: the helper must pass the same $biglen B matching payload, got $rc: $out"
  [[ "$out" == *"HELPER-OK"* ]] \
    || log_fail "test_101 SUBJECT: execution must continue past the assertion, got: $out"

  log_pass "test_101: small 0 / old idiom $rc_a (141 SIGPIPE or 1 builtin EPIPE) / helper 0 on a ${biglen}B matching payload (TEST-002)"
}

test_102_pgq_ratchet_gate_and_bite() {  # TEST-003 / Spec-AC-03
  log_info "test_102: unsafe-shape ratchet — live gate over tests/skills, plus a bite proof with an unmutated control (TEST-003)..."
  local ratchet="$PROJECT_ROOT/$PGQ_LIB_REL" baseline="$PROJECT_ROOT/$PGQ_BASELINE_REL" d
  [[ -f "$ratchet" ]] || log_fail "test_102: missing $PGQ_LIB_REL"
  [[ -f "$baseline" ]] || log_fail "test_102: missing $PGQ_BASELINE_REL"
  d="$(ap_tmpdir)"
  # shellcheck source=lib/pipe-grep-q-ratchet.sh
  . "$ratchet"

  # ---- LIVE GATE ----------------------------------------------------------
  local scan base total files
  scan="$(pgq_scan "$PROJECT_ROOT/tests/skills")"
  base="$(pgq_read_baseline "$baseline")"
  total="$(pgq_total "$scan")"
  files="$(printf '%s\n' "$scan" | "$PGQ_GREP_BIN" -c '[^[:space:]]')" || files=0

  # VACUITY GUARD. A broken pattern scans to nothing, and an empty scan
  # contradicts no baseline: the gate would pass by measuring the empty set.
  # The corpus is known to carry hundreds of occurrences, so a zero here is a
  # broken scanner, never a clean corpus.
  [[ "$total" -gt 0 && "$files" -gt 0 ]] \
    || log_fail "test_102: the live scan found $total occurrence(s) in $files file(s) — the scanner is broken, not the corpus (an empty scan can never contradict a baseline)"
  [[ -n "$base" ]] \
    || log_fail "test_102: $PGQ_BASELINE_REL has no data rows — re-record it: bash $PGQ_LIB_REL --record"

  local verdicts risen shrunk
  verdicts="$(pgq_compare "$base" "$scan")"
  risen="$(printf '%s\n' "$verdicts" | "$PGQ_GREP_BIN" -E '^(RISE|NEW) ' 2>/dev/null)" || risen=""
  if [[ -n "$risen" ]]; then
    printf '%s\n' "$risen"
    log_fail "test_102: the unsafe \`grep -q\` pipe count ROSE (see the RISE/NEW lines above, each naming its file). Use assert_payload_contains from $AP_LIB_REL instead; an echo or printf of a variable piped into a quiet grep reports FAILURE on a payload that MATCHED, once it passes 64 KiB"
  fi
  shrunk="$(printf '%s\n' "$verdicts" | "$PGQ_GREP_BIN" -E '^(SHRINK|GONE) ' 2>/dev/null)" || shrunk=""
  if [[ -n "$shrunk" ]]; then
    log_info "test_102: NOTE — the corpus SHRANK below the recorded bar. The bar is not lowered automatically; re-record deliberately: bash $PGQ_LIB_REL --record"
    printf '%s\n' "$shrunk" | while IFS= read -r l; do [[ -z "$l" ]] || log_info "  $l"; done
  fi
  log_info "test_102: live corpus $total occurrence(s) of the ratcheted shape across $files file(s); wider surface (any pipe into grep -q) $(pgq_superset_count "$PROJECT_ROOT/tests/skills") — reported, not gated"

  # ---- BITE PROOF, on a fixture tree --------------------------------------
  local fx="$d/pgq-fixture" fb="$d/pgq-fixture-baseline.tsv"
  rm -rf "$fx"; mkdir -p "$fx"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-fix-a.sh"; ap_grep_lines 2 "$fx/test-aai-fix-a.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-fix-b.sh"; ap_grep_lines 1 "$fx/test-aai-fix-b.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-fix-clean.sh"
  printf '%s\n' 'grep -qF needle "$file" || true' >> "$fx/test-aai-fix-clean.sh"

  bash "$ratchet" --record "$fb" "$fx" > /dev/null \
    || log_fail "test_102: --record failed on the fixture tree"
  local fbase fscan
  fbase="$(pgq_read_baseline "$fb")"
  fscan="$(pgq_scan "$fx")"

  # Fixture vacuity: the planted occurrences must actually be seen, or the
  # control's silence below means nothing.
  [[ "$(pgq_total "$fscan")" -eq 3 ]] \
    || log_fail "test_102: the fixture plants 3 occurrences but the scanner counted $(pgq_total "$fscan") — the bite proof would be vacuous"
  [[ "$(pgq_lookup "$fscan" test-aai-fix-clean.sh)" -eq 0 ]] \
    || log_fail "test_102: a file-target \`grep -qF needle FILE\` has no pipe and must NOT be counted"

  # CONTROL — unmutated: no verdict at all.
  local fv
  fv="$(pgq_compare "$fbase" "$fscan")"
  [[ -z "$fv" ]] || log_fail "test_102 CONTROL: an unmutated fixture must produce no verdict, got: $fv"

  # BITE 1 — one more occurrence in an EXISTING file.
  ap_grep_lines 1 "$fx/test-aai-fix-a.sh"
  fv="$(pgq_compare "$fbase" "$(pgq_scan "$fx")")"
  [[ "$fv" == *"RISE test-aai-fix-a.sh 2 3"* ]] \
    || log_fail "test_102 BITE 1: adding one occurrence must RISE and NAME the file, got: $fv"
  [[ "$fv" != *"test-aai-fix-b.sh"* ]] \
    || log_fail "test_102 BITE 1: an untouched file must not be named, got: $fv"

  # BITE 2 — a BRAND-NEW file carrying the shape. Per-file counts alone would
  # miss this; the file set is what catches it.
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-fix-new.sh"; ap_grep_lines 1 "$fx/test-aai-fix-new.sh"
  fv="$(pgq_compare "$fbase" "$(pgq_scan "$fx")")"
  [[ "$fv" == *"NEW test-aai-fix-new.sh 0 1"* ]] \
    || log_fail "test_102 BITE 2: a new file carrying the shape must be reported NEW and named, got: $fv"

  log_pass "test_102: live gate clean at $total occurrence(s); ratchet bites on a rise and on a new file, control silent (TEST-003)"
}

test_103_pgq_baseline_is_measured_not_typed() {  # TEST-004 / Spec-AC-04
  log_info "test_103: the recorded number is produced by the scanner the arm runs, and TRACKS the tree (TEST-004)..."
  local ratchet="$PROJECT_ROOT/$PGQ_LIB_REL" baseline="$PROJECT_ROOT/$PGQ_BASELINE_REL" d
  d="$(ap_tmpdir)"
  # shellcheck source=lib/pipe-grep-q-ratchet.sh
  . "$ratchet"

  # The plants are chosen HERE, by this arm. A recorder with a number typed
  # into it (from the change document or anywhere else) cannot follow them.
  local fx="$d/pgq-provenance" out="$d/pgq-provenance.tsv"
  rm -rf "$fx"; mkdir -p "$fx"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-p1.sh"; ap_grep_lines 5 "$fx/test-aai-p1.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-p2.sh"; ap_grep_lines 2 "$fx/test-aai-p2.sh"

  bash "$ratchet" --record "$out" "$fx" > /dev/null || log_fail "test_103: --record failed"
  local rows
  rows="$(pgq_read_baseline "$out")"
  [[ "$(pgq_lookup "$rows" test-aai-p1.sh)" -eq 5 ]] \
    || log_fail "test_103: --record wrote $(pgq_lookup "$rows" test-aai-p1.sh) for a tree with 5 planted occurrences"
  [[ "$(pgq_lookup "$rows" test-aai-p2.sh)" -eq 2 ]] \
    || log_fail "test_103: --record wrote $(pgq_lookup "$rows" test-aai-p2.sh) for a tree with 2 planted occurrences"

  # CHANGE THE TREE, RE-RECORD: the number must move with it. This is what
  # separates "measured" from "written down once and blessed".
  ap_grep_lines 3 "$fx/test-aai-p1.sh"
  bash "$ratchet" --record "$out" "$fx" > /dev/null || log_fail "test_103: re-record failed"
  rows="$(pgq_read_baseline "$out")"
  [[ "$(pgq_lookup "$rows" test-aai-p1.sh)" -eq 8 ]] \
    || log_fail "test_103: after planting 3 more the recorder must write 8, wrote $(pgq_lookup "$rows" test-aai-p1.sh) — the number is not being measured"

  # The COMMITTED baseline must name the generator, so nobody hand-edits it.
  "$PGQ_GREP_BIN" -qF -- '--record' "$baseline" \
    || log_fail "test_103: $PGQ_BASELINE_REL must name its generator command in the header"
  "$PGQ_GREP_BIN" -qiF 'generated' "$baseline" \
    || log_fail "test_103: $PGQ_BASELINE_REL must mark itself GENERATED"

  # And it must be a scan of the REAL tree, not of nothing: every committed row
  # names a file that exists and still carries the shape.
  local brow bfile bcount live missing=0
  live="$(pgq_scan "$PROJECT_ROOT/tests/skills")"
  while IFS=$'\t' read -r bcount bfile; do
    [[ -n "$bfile" ]] || continue
    [[ -f "$PROJECT_ROOT/tests/skills/$bfile" ]] \
      || { log_info "test_103: baseline row names a missing file: $bfile"; missing=1; }
    [[ "$bcount" -gt 0 ]] || { log_info "test_103: baseline row with a zero count: $bfile"; missing=1; }
  done <<< "$(pgq_read_baseline "$baseline")"
  [[ "$missing" -eq 0 ]] \
    || log_fail "test_103: the committed baseline carries rows that no scan could have produced (see above)"
  [[ "$(pgq_total "$live")" -gt 0 ]] \
    || log_fail "test_103: the live scan is empty — a zero-total scan must never validate a baseline"

  log_pass "test_103: --record tracks a planted tree (5/2 then 8), header names the generator, every committed row is real (TEST-004)"
}

test_104_pgq_shrink_never_lowers_the_bar() {  # TEST-005 / Spec-AC-03
  log_info "test_104: a file that SHRINKS produces a NOTE, not a pass-by-lowering and not a failure (TEST-005)..."
  local ratchet="$PROJECT_ROOT/$PGQ_LIB_REL" baseline="$PROJECT_ROOT/$PGQ_BASELINE_REL" d
  d="$(ap_tmpdir)"
  # shellcheck source=lib/pipe-grep-q-ratchet.sh
  . "$ratchet"

  local fx="$d/pgq-shrink" fb="$d/pgq-shrink.tsv"
  rm -rf "$fx"; mkdir -p "$fx"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s1.sh"; ap_grep_lines 4 "$fx/test-aai-s1.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s2.sh"; ap_grep_lines 1 "$fx/test-aai-s2.sh"
  bash "$ratchet" --record "$fb" "$fx" > /dev/null || log_fail "test_104: --record failed"
  local fbase before after
  fbase="$(pgq_read_baseline "$fb")"
  before="$(cat "$fb")"

  # Convert two sites away, and remove one file's last one entirely.
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s1.sh"; ap_grep_lines 2 "$fx/test-aai-s1.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s2.sh"

  local fv
  fv="$(pgq_compare "$fbase" "$(pgq_scan "$fx")")"
  [[ "$fv" == *"SHRINK test-aai-s1.sh 4 2"* ]] \
    || log_fail "test_104: a shrunk file must report SHRINK with BOTH numbers, got: $fv"
  [[ "$fv" == *"GONE test-aai-s2.sh 1 0"* ]] \
    || log_fail "test_104: a file with none left must report GONE, got: $fv"
  [[ "$fv" != *"RISE"* && "$fv" != *"NEW"* ]] \
    || log_fail "test_104: a shrink must never be reported as a rise, got: $fv"

  # THE BAR ITSELF MUST NOT HAVE MOVED. A ratchet that re-records on read
  # re-arms one occurrence lower every time a file is edited for an unrelated
  # reason, and the bar walks to zero with nobody ever seeing it move.
  after="$(cat "$fb")"
  [[ "$before" == "$after" ]] \
    || log_fail "test_104: comparing must not rewrite the recorded numbers — the baseline file changed underneath the comparison"

  # CONTROL: the same fixture, unshrunk, produces nothing at all.
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s1.sh"; ap_grep_lines 4 "$fx/test-aai-s1.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "$fx/test-aai-s2.sh"; ap_grep_lines 1 "$fx/test-aai-s2.sh"
  fv="$(pgq_compare "$fbase" "$(pgq_scan "$fx")")"
  [[ -z "$fv" ]] || log_fail "test_104 CONTROL: the restored fixture must produce no verdict, got: $fv"

  # And the committed baseline is likewise untouched by a live gate run.
  local live_before live_after
  live_before="$(cat "$baseline")"
  pgq_compare "$(pgq_read_baseline "$baseline")" "$(pgq_scan "$PROJECT_ROOT/tests/skills")" > /dev/null
  live_after="$(cat "$baseline")"
  [[ "$live_before" == "$live_after" ]] \
    || log_fail "test_104: running the live gate rewrote $PGQ_BASELINE_REL"

  log_pass "test_104: SHRINK and GONE are NOTEs, never a rise, and the recorded number is never rewritten by a comparison (TEST-005)"
}

# Converted sites, as `<suite file>|<needle it must still assert>`. The needle
# is the CONTRACT: a conversion that quietly changed what an assertion looks for
# would be a silent loss of coverage, and the suites themselves could not tell
# you (they would just keep passing on a weaker claim).
#
# THREE of the four converted assertions are pinned here. The fourth asserts
# `"$victim"` — a needle computed at run time from whichever tracked spec the
# fixture picked — and a literal pin cannot express it. Code review found the
# arm claiming "every converted site" while pinning three of four; the claim is
# narrowed rather than the gap papered over.
PGQ_CONVERTED=(
  "test-aai-docs-audit.sh|not POSIX"
  "test-aai-docs-audit.sh|STALE"
  "test-aai-docs-audit.sh|no longer exists on disk"
)

test_105_converted_sites_keep_their_needles() {  # TEST-006 / Spec-AC-01, Spec-AC-05
  log_info "test_105: the pinned converted needles survive, the helper is sourced, and no failure message dumps an unbounded payload (TEST-006)..."
  local entry f needle suite seen=0

  # VACUITY GUARD: an empty list would make every loop below pass by never
  # running. The conversion set is not allowed to be silently empty.
  [[ "${#PGQ_CONVERTED[@]}" -gt 0 ]] \
    || log_fail "test_105: the converted-site list is EMPTY — this arm would pass without checking anything"

  for entry in "${PGQ_CONVERTED[@]}"; do
    f="${entry%%|*}"
    needle="${entry#*|}"
    suite="$PROJECT_ROOT/tests/skills/$f"
    [[ -n "$needle" ]] || log_fail "test_105: empty needle in the converted-site list entry '$entry'"
    [[ -f "$suite" ]] || log_fail "test_105: converted site names a missing suite: $f"

    # The suite must SOURCE the helper, or its assert_payload_contains calls are
    # `command not found` — which bash reports as a failure, but only when the
    # arm holding them actually runs.
    #
    # Anchored on a real `.`/`source` COMMAND, not on the path anywhere in the
    # file. Measured: a plain `grep -qF lib/assert-payload.sh` passed a mutant
    # with the source line deleted, because the `# shellcheck source=` directive
    # one line above still carried the path.
    "$PGQ_GREP_BIN" -qE '^[[:space:]]*(\.|source)[[:space:]]+.*lib/assert-payload\.sh' "$suite" \
      || log_fail "test_105: $f uses the pipe-free helper but never sources tests/skills/lib/assert-payload.sh"

    # The needle survived, and it survived INSIDE a helper call — not merely
    # somewhere in the file.
    "$PGQ_GREP_BIN" -qF -- "assert_payload_contains \"\$out\" \"$needle\"" "$suite" \
      || log_fail "test_105: $f no longer asserts the needle '$needle' through assert_payload_contains — a conversion must not change what a site asserts"
    seen=$(( seen + 1 ))
  done

  # No converted suite may still dump a whole findings payload into a FAIL line.
  # This is the exact line the incident produced: 46 KB of findings after `got:`.
  local unbounded
  for entry in "${PGQ_CONVERTED[@]}"; do
    f="${entry%%|*}"
    suite="$PROJECT_ROOT/tests/skills/$f"
    # Anchored on the SHAPE, not on one spelling. The first version of this
    # sweep looked for the single literal `got: $out"`, found zero, and logged
    # "no unbounded payload dump" over a file that had TWELVE — every one of
    # them spelled `: $out"` with a different word before the colon. Code review
    # caught it. That is the ride's own defect class inside the ride's own
    # guard: a claim broader than what it checks.
    unbounded="$("$PGQ_GREP_BIN" -nE '(log_fail|log_info)[[:space:]]+".*\$out"[[:space:]]*$' "$suite")" || unbounded=""
    if [[ -n "$unbounded" ]]; then
      printf '%s\n' "$unbounded"
      log_fail "test_105: $f still prints an UNBOUNDED payload in a failure message (see the lines above) — use payload_preview from $AP_LIB_REL"
    fi
  done

  log_pass "test_105: $seen pinned needle(s) of 4 converted sites intact (the 4th asserts a run-time variable and cannot be pinned), helper sourced, no unbounded payload dump (TEST-006)"
}

# --- harness-surfaces-drift-unguarded arms (test_110..113) ------------------
# CHANGE harness-surfaces-drift-unguarded /
# docs/specs/SPEC-0154-spec-harness-surfaces-drift-unguarded.md.
#
# .agents/skills, .codex/skills and .gemini/skills are GENERATED from
# .claude/skills by .aai/scripts/sync-harness-skills.mjs under the transform
# declared in .aai/system/HARNESS_SKILLS.yaml (D1). test_110 is a bash-native,
# node-independent spot check of the same set-equality invariant the
# generator's --check also proves — defense in depth per D4 (this suite IS
# the guard; the generator is generation machinery it drives). test_111..113
# drive the generator itself.
HSK_GENERATOR_REL=".aai/scripts/sync-harness-skills.mjs"
HSK_MANIFEST_REL=".aai/system/HARNESS_SKILLS.yaml"
HSK_MIRROR_TREES=".agents/skills .codex/skills .gemini/skills"

# hsk_skill_dirs <skills-dir> — one skill name per line, sorted. A "skill" is
# any directory directly under <skills-dir> that itself contains a SKILL.md
# (excludes README.md and the gitignored skills.local/ index — neither carries
# a SKILL.md, so no special-case is needed for them).
hsk_skill_dirs() {
  local dir="$1" n
  [[ -d "$dir" ]] || return 0
  for n in "$dir"/*/; do
    [[ -f "${n}SKILL.md" ]] && basename "$n"
  done | LC_ALL=C sort
}

# hsk_exclusions_for <manifest> <tree> — one excluded skill name per line for
# <tree>, read from the manifest's `exclusions:` block (tree|skill|reason rows).
# Prints nothing when the manifest is absent or carries no matching row.
hsk_exclusions_for() {
  local manifest="$1" tree="$2" insec=0 line rest etree eskill
  [[ -f "$manifest" ]] || return 0
  while IFS= read -r line; do
    case "$line" in
      'exclusions:') insec=1; continue ;;
      [a-zA-Z_]*:*) insec=0; continue ;;
    esac
    [[ "$insec" -eq 1 ]] || continue
    case "$line" in
      '  - '*) ;;
      *) continue ;;
    esac
    rest="${line#  - }"
    etree="${rest%%|*}"
    etree="${etree#"${etree%%[![:space:]]*}"}"
    etree="${etree%"${etree##*[![:space:]]}"}"
    [[ "$etree" == "$tree" ]] || continue
    rest="${rest#*|}"
    eskill="${rest%%|*}"
    eskill="${eskill#"${eskill%%[![:space:]]*}"}"
    eskill="${eskill%"${eskill##*[![:space:]]}"}"
    [[ -n "$eskill" ]] && printf '%s\n' "$eskill"
  done < "$manifest"
}

# hsk_check_parity <root> [<manifest>] — prints one "PARITY <missing|extra>
# <tree>/<skill>" line per divergence, honoring the manifest's exclusions;
# returns 0 clean / 1 dirty. Side-effect-free (no log_fail), so it can be run
# against a mutated fixture or worktree without killing the whole suite.
hsk_check_parity() {
  local root="$1" manifest="${2:-}"
  [[ -n "$manifest" ]] || manifest="$root/$HSK_MANIFEST_REL"
  local src="$root/.claude/skills"
  local expected_all
  expected_all="$(hsk_skill_dirs "$src")"
  local rc=0 tree tdir excluded want actual missing extra s
  for tree in $HSK_MIRROR_TREES; do
    tdir="$root/$tree"
    excluded="$(hsk_exclusions_for "$manifest" "$tree")"
    if [[ -n "$excluded" ]]; then
      want="$(comm -23 <(printf '%s\n' "$expected_all") <(printf '%s\n' "$excluded" | LC_ALL=C sort))"
    else
      want="$expected_all"
    fi
    if [[ ! -d "$tdir" ]]; then
      # A declared mirror tree that is absent ENTIRELY is the largest
      # possible drift, not a skip: report every skill this tree should
      # carry as missing. Fixtures may legitimately ship only a subset of
      # the mirror trees, so this hard-fail applies only at the real root.
      [[ "$root" == "$PROJECT_ROOT" ]] || continue
      while IFS= read -r s; do [[ -n "$s" ]] && printf 'PARITY missing %s/%s\n' "$tree" "$s"; done <<< "$want"
      rc=1
      continue
    fi
    actual="$(hsk_skill_dirs "$tdir")"
    missing="$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$actual"))"
    extra="$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$actual"))"
    if [[ -n "$missing" ]]; then
      while IFS= read -r s; do [[ -n "$s" ]] && printf 'PARITY missing %s/%s\n' "$tree" "$s"; done <<< "$missing"
      rc=1
    fi
    if [[ -n "$extra" ]]; then
      while IFS= read -r s; do [[ -n "$s" ]] && printf 'PARITY extra %s/%s\n' "$tree" "$s"; done <<< "$extra"
      rc=1
    fi
  done
  return "$rc"
}

test_110_skill_set_parity() {  # TEST-001 / Spec-AC-01, TEST-005 / Spec-AC-06 (exclusion half)
  log_info "test_110: every mirror tree offers exactly .claude/skills' skill set, honoring manifest exclusions (TEST-001, TEST-005 exclusion half)..."
  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"

  # (a) LIVE PARITY — the real, measured drift (6/8/8 missing pre-normalization).
  local out rc
  out="$(hsk_check_parity "$PROJECT_ROOT")" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "test_110: mirror trees diverge from .claude/skills (Spec-AC-01):"$'\n'"$out"

  # (b) EXCLUSION SEMANTICS (Spec-AC-06, the "good exclusion" half) — a
  # self-contained fixture, independent of the shipped (empty) manifest.
  # Skill "b" is present in .claude/skills but absent from BOTH .codex/skills
  # and .gemini/skills; only .codex/skills excludes it. The SAME missing skill
  # must be forgiven for .codex/skills and still reported for .gemini/skills.
  local fx="$TEST_DIR/t110-fixture"
  rm -rf "$fx"
  mkdir -p "$fx/.claude/skills/a" "$fx/.claude/skills/b" "$fx/.codex/skills/a" "$fx/.gemini/skills/a"
  printf -- '---\nname: a\ndescription: fixture a\n---\nbody\n' > "$fx/.claude/skills/a/SKILL.md"
  printf -- '---\nname: b\ndescription: fixture b\n---\nbody\n' > "$fx/.claude/skills/b/SKILL.md"
  cp "$fx/.claude/skills/a/SKILL.md" "$fx/.codex/skills/a/SKILL.md"
  cp "$fx/.claude/skills/a/SKILL.md" "$fx/.gemini/skills/a/SKILL.md"
  local fm="$fx/manifest.yaml"
  {
    printf '%s\n' 'trees:'
    printf '%s\n' '  - .agents/skills|carry|no'
    printf '%s\n' '  - .codex/skills|drop|yes'
    printf '%s\n' '  - .gemini/skills|drop|yes'
    printf '%s\n' 'exclusions:'
    printf '%s\n' '  - .codex/skills | b | fixture: b is intentionally not offered to codex'
  } > "$fm"

  out="$(hsk_check_parity "$fx" "$fm")" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] \
    || log_fail "test_110: fixture expected to still redden on .gemini/skills/b (not excluded there), got clean"
  case "$out" in
    *"PARITY missing .codex/skills/b"*)
      log_fail "test_110: the manifest exclusion (.codex/skills, b, reason) must forgive that ONE pair, but it was still reported missing: $out" ;;
  esac
  case "$out" in
    *"PARITY missing .gemini/skills/b"*) ;;
    *) log_fail "test_110: the SAME skill 'b', missing from .gemini/skills (NOT excluded there), must still be reported: $out" ;;
  esac

  log_pass "test_110: mirror trees carry exactly .claude/skills' skill set; an exclusion forgives exactly the one declared (tree, skill) pair (TEST-001, TEST-005 exclusion half)"
}

test_111_generator_check_clean_and_idempotent() {  # TEST-002, TEST-003 / Spec-AC-02
  log_info "test_111: sync-harness-skills.mjs --check is clean post-normalization, --write is then a no-op, and both generated READMEs list the full set (TEST-002, TEST-003)..."
  local gen="$PROJECT_ROOT/$HSK_GENERATOR_REL"
  [[ -f "$gen" ]] || log_fail "test_111: missing $HSK_GENERATOR_REL"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"

  local out rc
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "test_111: --check must exit 0 on the normalized tree, got $rc:"$'\n'"$out"

  local mirrors_before="$TEST_DIR/t111-mirrors-before.diff"
  local mirrors_after="$TEST_DIR/t111-mirrors-after.diff"
  git -C "$PROJECT_ROOT" diff --binary HEAD -- \
    .agents/skills .codex/skills .gemini/skills > "$mirrors_before" \
    || log_fail "test_111: could not snapshot the pre-write mirror state"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must exit 0, got $rc: $out"
  git -C "$PROJECT_ROOT" diff --binary HEAD -- \
    .agents/skills .codex/skills .gemini/skills > "$mirrors_after" \
    || log_fail "test_111: could not snapshot the post-write mirror state"
  cmp -s "$mirrors_before" "$mirrors_after" \
    || log_fail "test_111: --write after a clean --check must change no bytes from the pre-write mirror state (idempotence)"

  # TEST-003 — the README indexes list the FULL live set, not the old 22-of-39.
  local n_skills n t
  n_skills="$(hsk_skill_dirs "$PROJECT_ROOT/.claude/skills" | "$PGQ_GREP_BIN" -c .)" || n_skills=0
  for t in .codex .gemini; do
    n="$("$PGQ_GREP_BIN" -cE '^- `/aai-' "$PROJECT_ROOT/$t/skills/README.md")" || n=0
    [[ "$n" -eq "$n_skills" ]] \
      || log_fail "test_111: $t/skills/README.md lists $n skills, want the full live set of $n_skills"
  done

  # PR review — a readme=yes tree still needs its directory and README when
  # every source skill is excluded and the mirror tree starts absent.
  local empty_fx="$TEST_DIR/t111-all-excluded"
  rm -rf "$empty_fx"
  mkdir -p "$empty_fx/.claude/skills/a"
  printf -- '---\nname: a\ndescription: fixture a\n---\nbody\n' > "$empty_fx/.claude/skills/a/SKILL.md"
  {
    printf '%s\n' 'trees:'
    printf '%s\n' '  - .agents/skills|carry|no'
    printf '%s\n' '  - .codex/skills|drop|yes'
    printf '%s\n' '  - .gemini/skills|drop|yes'
    printf '%s\n' 'exclusions:'
    printf '%s\n' '  - .agents/skills|a|fixture excludes the only skill'
    printf '%s\n' '  - .codex/skills|a|fixture excludes the only skill'
    printf '%s\n' '  - .gemini/skills|a|fixture excludes the only skill'
  } > "$empty_fx/manifest.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$empty_fx" --manifest "$empty_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must create empty readme=yes trees, got $rc: $out"
  [[ -f "$empty_fx/.codex/skills/README.md" && -f "$empty_fx/.gemini/skills/README.md" ]] \
    || log_fail "test_111: all-excluded readme=yes trees must still receive README.md"
  local excluded_line
  for excluded_line in \
    'EXCLUDED .agents/skills/a: fixture excludes the only skill' \
    'EXCLUDED .codex/skills/a: fixture excludes the only skill' \
    'EXCLUDED .gemini/skills/a: fixture excludes the only skill'; do
    case "$out" in
      *"$excluded_line"*) ;;
      *) log_fail "test_111: --write must report every applied exclusion; missing '$excluded_line' in: $out" ;;
    esac
  done

  # PR review — write mode repairs a non-file SKILL.md target instead of
  # detecting it in check mode and then crashing with EISDIR while writing.
  local corrupt_fx="$TEST_DIR/t111-non-file-target"
  rm -rf "$corrupt_fx"
  mkdir -p "$corrupt_fx/.claude/skills/a" \
    "$corrupt_fx/.agents/skills/a" "$corrupt_fx/.codex/skills/a" "$corrupt_fx/.gemini/skills/a"
  printf -- '---\nname: a\ndescription: fixture a\n---\nbody\n' > "$corrupt_fx/.claude/skills/a/SKILL.md"
  cp "$corrupt_fx/.claude/skills/a/SKILL.md" "$corrupt_fx/.agents/skills/a/SKILL.md"
  cp "$corrupt_fx/.claude/skills/a/SKILL.md" "$corrupt_fx/.codex/skills/a/SKILL.md"
  cp "$corrupt_fx/.claude/skills/a/SKILL.md" "$corrupt_fx/.gemini/skills/a/SKILL.md"
  rm "$corrupt_fx/.codex/skills/a/SKILL.md"
  mkdir "$corrupt_fx/.codex/skills/a/SKILL.md"
  {
    printf '%s\n' 'trees:'
    printf '%s\n' '  - .agents/skills|carry|no'
    printf '%s\n' '  - .codex/skills|drop|yes'
    printf '%s\n' '  - .gemini/skills|drop|yes'
    printf '%s\n' 'exclusions:'
  } > "$corrupt_fx/manifest.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$corrupt_fx" --manifest "$corrupt_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must replace a directory at SKILL.md, got $rc: $out"
  [[ -f "$corrupt_fx/.codex/skills/a/SKILL.md" ]] \
    || log_fail "test_111: repaired .codex/skills/a/SKILL.md must be a regular file"
  rm "$corrupt_fx/.codex/skills/README.md"
  mkdir "$corrupt_fx/.codex/skills/README.md"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$corrupt_fx" --manifest "$corrupt_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must replace a directory at README.md, got $rc: $out"
  [[ -f "$corrupt_fx/.codex/skills/README.md" ]] \
    || log_fail "test_111: repaired .codex/skills/README.md must be a regular file"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$corrupt_fx" --manifest "$corrupt_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: repaired non-file target must pass --check, got $rc: $out"

  # PR review — readable symlinks must never redirect generator writes outside
  # a declared mirror, whether the link is the file or its skill directory.
  local symlink_fx="$TEST_DIR/t111-symlink-targets"
  local external_fx="$TEST_DIR/t111-external-sentinels"
  rm -rf "$symlink_fx" "$external_fx"
  cp -R "$corrupt_fx" "$symlink_fx"
  mkdir -p "$external_fx/skill-dir"
  printf '%s\n' 'external skill sentinel' > "$external_fx/skill.md"
  printf '%s\n' 'external readme sentinel' > "$external_fx/readme.md"
  printf '%s\n' 'external directory sentinel' > "$external_fx/skill-dir/SKILL.md"
  rm "$symlink_fx/.codex/skills/a/SKILL.md" "$symlink_fx/.codex/skills/README.md"
  rm -rf "$symlink_fx/.gemini/skills/a"
  ln -s "$external_fx/skill.md" "$symlink_fx/.codex/skills/a/SKILL.md"
  ln -s "$external_fx/readme.md" "$symlink_fx/.codex/skills/README.md"
  ln -s "$external_fx/skill-dir" "$symlink_fx/.gemini/skills/a"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must safely replace readable symlinks, got $rc: $out"
  [[ "$(cat "$external_fx/skill.md")" == 'external skill sentinel' ]] \
    || log_fail "test_111: symlinked SKILL.md redirected the write into the external sentinel"
  [[ "$(cat "$external_fx/readme.md")" == 'external readme sentinel' ]] \
    || log_fail "test_111: symlinked README.md redirected the write into the external sentinel"
  [[ "$(cat "$external_fx/skill-dir/SKILL.md")" == 'external directory sentinel' ]] \
    || log_fail "test_111: symlinked skill directory redirected the write outside the mirror"
  [[ ! -L "$symlink_fx/.codex/skills/a/SKILL.md" && -f "$symlink_fx/.codex/skills/a/SKILL.md" ]] \
    || log_fail "test_111: repaired SKILL.md symlink must become a regular file"
  [[ ! -L "$symlink_fx/.codex/skills/README.md" && -f "$symlink_fx/.codex/skills/README.md" ]] \
    || log_fail "test_111: repaired README.md symlink must become a regular file"
  [[ ! -L "$symlink_fx/.gemini/skills/a" && -f "$symlink_fx/.gemini/skills/a/SKILL.md" ]] \
    || log_fail "test_111: repaired skill-directory symlink must become a real directory with SKILL.md"

  # A symlink with an unexpected skill name must not disappear from parity
  # enumeration merely because Dirent.isDirectory() is false. Check mode names
  # it; write mode removes only the owned link and preserves its external tree.
  mkdir -p "$external_fx/extra-skill"
  printf '%s\n' 'external extra sentinel' > "$external_fx/extra-skill/SKILL.md"
  ln -s "$external_fx/extra-skill" "$symlink_fx/.codex/skills/evil"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "test_111: unexpected symlinked skill must fail --check, got $rc: $out"
  case "$out" in
    *"extra .codex/skills/evil"*) ;;
    *) log_fail "test_111: unexpected symlinked skill must be named as extra, got: $out" ;;
  esac
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: --write must remove unexpected symlinked skill, got $rc: $out"
  [[ ! -e "$symlink_fx/.codex/skills/evil" && ! -L "$symlink_fx/.codex/skills/evil" ]] \
    || log_fail "test_111: unexpected symlinked skill remained after --write"
  [[ "$(cat "$external_fx/extra-skill/SKILL.md")" == 'external extra sentinel' ]] \
    || log_fail "test_111: removing unexpected symlinked skill mutated its external target"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_111: repaired unexpected symlink must pass --check, got $rc: $out"

  mkdir -p "$symlink_fx/.codex/skills/empty-skill"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "test_111: mirror directory without SKILL.md must fail --check, got $rc: $out"
  case "$out" in
    *"extra .codex/skills/empty-skill"*) ;;
    *) log_fail "test_111: malformed mirror directory must be named as extra, got: $out" ;;
  esac
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$symlink_fx" --manifest "$symlink_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 && ! -e "$symlink_fx/.codex/skills/empty-skill" ]] \
    || log_fail "test_111: --write must remove an extra mirror directory without SKILL.md, got $rc: $out"

  log_pass "test_111: generator --check clean, --write idempotent, both READMEs list the full $n_skills-skill set (TEST-002, TEST-003)"
}

test_112_generator_refuses_bad_manifest() {  # TEST-004 / Spec-AC-03, TEST-005 / Spec-AC-06 (stale/reasonless halves)
  log_info "test_112: generator refuses an undeclared tree and a stale or reason-less exclusion, exit 2 naming the offender (TEST-004, TEST-005 stale/reasonless halves)..."
  local gen="$PROJECT_ROOT/$HSK_GENERATOR_REL"
  [[ -f "$gen" ]] || log_fail "test_112: missing $HSK_GENERATOR_REL"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"
  local fx="$TEST_DIR/t112-fixture"
  rm -rf "$fx"
  mkdir -p "$fx/.claude/skills/a" "$fx/.agents/skills/a" "$fx/.codex/skills/a" "$fx/.gemini/skills/a"
  printf -- '---\nname: a\ndescription: fixture a\n---\nbody\n' > "$fx/.claude/skills/a/SKILL.md"
  cp "$fx/.claude/skills/a/SKILL.md" "$fx/.agents/skills/a/SKILL.md"
  cp "$fx/.claude/skills/a/SKILL.md" "$fx/.codex/skills/a/SKILL.md"
  cp "$fx/.claude/skills/a/SKILL.md" "$fx/.gemini/skills/a/SKILL.md"

  local out rc

  # (a) Spec-AC-03 — the .codex/skills row is deleted from the manifest.
  {
    printf '%s\n' 'trees:'
    printf '%s\n' '  - .agents/skills|carry|no'
    printf '%s\n' '  - .gemini/skills|drop|yes'
    printf '%s\n' 'exclusions:'
  } > "$fx/m-no-codex.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-no-codex.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(a): undeclared tree must exit 2, got $rc: $out"
  case "$out" in
    *".codex/skills"*) ;;
    *) log_fail "test_112(a): the refusal must name the offending tree .codex/skills, got: $out" ;;
  esac

  local base_manifest="trees:
  - .agents/skills|carry|no
  - .codex/skills|drop|yes
  - .gemini/skills|drop|yes
exclusions:"

  # (b) Spec-AC-06 — an exclusion with an empty reason.
  printf '%s\n  - .codex/skills|a|\n' "$base_manifest" > "$fx/m-empty-reason.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-empty-reason.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(b): an exclusion with an empty reason must exit 2, got $rc: $out"

  # (c) Spec-AC-06 — an exclusion naming a skill absent from .claude/skills.
  printf '%s\n  - .codex/skills|aai-does-not-exist|some reason\n' "$base_manifest" > "$fx/m-stale.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-stale.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(c): a stale exclusion must exit 2, got $rc: $out"
  case "$out" in
    *[Ss]"tale exclusion"*) ;;
    *) log_fail "test_112(c): the refusal must say 'stale exclusion', got: $out" ;;
  esac

  # (d) Review NB-1 — path-valued flags must not silently fall back to the
  # live repository when their value is absent or is another option.
  local cli_case cli_flag
  for cli_flag in root manifest; do
    for cli_case in missing option; do
      if [[ "$cli_case" == "missing" ]]; then
        out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --check "--$cli_flag" 2>&1)" && rc=0 || rc=$?
      else
        out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" "--$cli_flag" --check 2>&1)" && rc=0 || rc=$?
      fi
      [[ "$rc" -eq 2 ]] || log_fail "test_112(d): --$cli_flag with a $cli_case value must exit 2, got $rc: $out"
      case "$out" in
        *"--$cli_flag requires a value"*) ;;
        *) log_fail "test_112(d): --$cli_flag with a $cli_case value must name its missing value, got: $out" ;;
      esac
    done
  done

  # (e) PR review — duplicate tree rows must be rejected before Map
  # construction can silently discard the first transform.
  printf '%s\n' 'trees:' \
    '  - .agents/skills|carry|no' \
    '  - .codex/skills|nonsense|no' \
    '  - .codex/skills|drop|yes' \
    '  - .gemini/skills|drop|yes' \
    'exclusions:' > "$fx/m-duplicate-tree.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-duplicate-tree.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(e): a duplicate tree row must exit 2, got $rc: $out"
  case "$out" in
    *"duplicate tree"*".codex/skills"*) ;;
    *) log_fail "test_112(e): duplicate-tree refusal must name .codex/skills, got: $out" ;;
  esac

  # (f) PR review — no nonblank manifest content may disappear merely
  # because it has unexpected indentation or a misspelled section header.
  printf '%s\n' "$base_manifest" '    - .codex/skills|a|intentionally excluded' > "$fx/m-indented-row.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-indented-row.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(f): an unexpectedly indented row must exit 2, got $rc: $out"
  case "$out" in
    *"unparsed manifest content"*) ;;
    *) log_fail "test_112(f): indented-row refusal must name unparsed content, got: $out" ;;
  esac

  printf '%s\n' 'trees:' \
    '  - .agents/skills|carry|no' \
    '  - .codex/skills|drop|yes' \
    '  - .gemini/skills|drop|yes' \
    'exclusionz:' > "$fx/m-misspelled-section.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-misspelled-section.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(f): a misspelled section header must exit 2, got $rc: $out"
  case "$out" in
    *"unparsed manifest content"*"exclusionz:"*) ;;
    *) log_fail "test_112(f): misspelled-section refusal must name the unparsed header, got: $out" ;;
  esac

  # (g) PR review — a closing frontmatter fence is a complete `---` line,
  # never a prefix such as `---oops` that gets silently discarded.
  printf '%s\n' "$base_manifest" > "$fx/m-base.yaml"
  printf -- '---\nname: a\ndescription: fixture a\n---oops\nbody\n' > "$fx/.claude/skills/a/SKILL.md"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$fx" --manifest "$fx/m-base.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(g): a prefixed closing fence must exit 2, got $rc: $out"
  case "$out" in
    *"closing frontmatter fence"*) ;;
    *) log_fail "test_112(g): malformed-fence refusal must name the closing frontmatter fence, got: $out" ;;
  esac

  # (h) Internal review — a late malformed source must be rejected before
  # --write mutates any earlier target, never leaving a partial projection.
  local late_fx="$TEST_DIR/t112-late-malformed-source"
  rm -rf "$late_fx"
  mkdir -p "$late_fx/.claude/skills/a" "$late_fx/.claude/skills/b"
  local tree
  for tree in .agents/skills .codex/skills .gemini/skills; do
    mkdir -p "$late_fx/$tree/a"
    printf -- '---\nname: a\ndescription: old mirror sentinel\n---\nold body\n' \
      > "$late_fx/$tree/a/SKILL.md"
  done
  printf -- '---\nname: a\ndescription: new source a\n---\nnew body\n' \
    > "$late_fx/.claude/skills/a/SKILL.md"
  printf -- '---\nname: b\ndescription: malformed late source\nbody without closing fence\n' \
    > "$late_fx/.claude/skills/b/SKILL.md"
  printf '%s\n' "$base_manifest" > "$late_fx/manifest.yaml"
  local before_targets after_targets
  before_targets="$(find "$late_fx/.agents/skills" "$late_fx/.codex/skills" "$late_fx/.gemini/skills" \
    -type f -exec cksum {} \; | LC_ALL=C sort)"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$late_fx" --manifest "$late_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(h): late malformed source must exit 2, got $rc: $out"
  after_targets="$(find "$late_fx/.agents/skills" "$late_fx/.codex/skills" "$late_fx/.gemini/skills" \
    -type f -exec cksum {} \; | LC_ALL=C sort)"
  [[ "$after_targets" == "$before_targets" ]] \
    || log_fail "test_112(h): failed --write partially mutated mirror targets"

  # (i) Internal final review — manifest topology diagnostics take precedence
  # over source parsing when both inputs are invalid. AC-03 requires the
  # undeclared on-disk tree to be named unconditionally.
  cp "$fx/m-no-codex.yaml" "$late_fx/m-no-codex.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$late_fx" --manifest "$late_fx/m-no-codex.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(i): combined invalid manifest/source must exit 2, got $rc: $out"
  case "$out" in
    *".codex/skills"*) ;;
    *) log_fail "test_112(i): manifest validation must name .codex/skills before parsing malformed sources, got: $out" ;;
  esac

  # (j) External review — source directories are authored inputs, so a
  # directory without SKILL.md is a structural error, never an omitted skill.
  printf -- '---\nname: b\ndescription: repaired source b\n---\nbody\n' \
    > "$late_fx/.claude/skills/b/SKILL.md"
  mkdir -p "$late_fx/.claude/skills/empty-skill"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$late_fx" --manifest "$late_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(j): source directory without SKILL.md must exit 2, got $rc: $out"
  case "$out" in
    *"missing SKILL.md"*".claude/skills/empty-skill"*) ;;
    *) log_fail "test_112(j): malformed source directory must name its missing SKILL.md, got: $out" ;;
  esac

  # (k) Final review NB-1 — source entries may not escape through directory
  # symlinks, and SKILL.md itself must be a regular authored file.
  rm -rf "$late_fx/.claude/skills/empty-skill"
  local external_source="$TEST_DIR/t112-external-source"
  mkdir -p "$external_source"
  printf -- '---\nname: evil\ndescription: external source\n---\nbody\n' > "$external_source/SKILL.md"
  ln -s "$external_source" "$late_fx/.claude/skills/evil"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$late_fx" --manifest "$late_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(k): symlinked source skill must exit 2, got $rc: $out"
  case "$out" in
    *"source skill entry must be a real directory"*".claude/skills/evil"*) ;;
    *) log_fail "test_112(k): source symlink refusal must name .claude/skills/evil, got: $out" ;;
  esac

  rm "$late_fx/.claude/skills/evil"
  rm "$late_fx/.claude/skills/a/SKILL.md"
  mkdir "$late_fx/.claude/skills/a/SKILL.md"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$late_fx" --manifest "$late_fx/manifest.yaml" --check 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(k): non-file source SKILL.md must exit 2, got $rc: $out"
  case "$out" in
    *"source SKILL.md must be a regular file"*".claude/skills/a/SKILL.md"*) ;;
    *) log_fail "test_112(k): non-file source refusal must name .claude/skills/a/SKILL.md, got: $out" ;;
  esac

  # (l) External review — README.md is the generated index path in two
  # mirrors and therefore cannot also be represented as a source skill name.
  local reserved_fx="$TEST_DIR/t112-reserved-skill-name"
  mkdir -p "$reserved_fx/.claude/skills/README.md" \
    "$reserved_fx/.agents/skills" "$reserved_fx/.codex/skills" "$reserved_fx/.gemini/skills"
  printf -- '---\nname: README.md\ndescription: collides with generated index\n---\nbody\n' \
    > "$reserved_fx/.claude/skills/README.md/SKILL.md"
  printf '%s\n' "$base_manifest" > "$reserved_fx/manifest.yaml"
  out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$reserved_fx" --manifest "$reserved_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "test_112(l): reserved README.md skill name must exit 2 before writing, got $rc: $out"
  case "$out" in
    *"reserved"*"README.md"*) ;;
    *) log_fail "test_112(l): reserved-name refusal must name README.md, got: $out" ;;
  esac

  # (m) Final review BLOCKING-1 — the collision is case-insensitive on the
  # supported macOS/Windows filesystems, so every case-fold equivalent is
  # reserved even when authored on a case-sensitive checkout.
  local reserved_name reserved_case=0
  for reserved_name in readme.md ReAdMe.md; do
    reserved_case=$((reserved_case + 1))
    reserved_fx="$TEST_DIR/t112-reserved-skill-name-$reserved_case"
    mkdir -p "$reserved_fx/.claude/skills/$reserved_name" \
      "$reserved_fx/.agents/skills" "$reserved_fx/.codex/skills" "$reserved_fx/.gemini/skills"
    printf -- '---\nname: %s\ndescription: case-fold index collision\n---\nbody\n' "$reserved_name" \
      > "$reserved_fx/.claude/skills/$reserved_name/SKILL.md"
    printf '%s\n' "$base_manifest" > "$reserved_fx/manifest.yaml"
    out="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --root "$reserved_fx" --manifest "$reserved_fx/manifest.yaml" --write 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || log_fail "test_112(m): reserved case-fold name $reserved_name must exit 2 before writing, got $rc: $out"
    case "$out" in
      *"reserved"*"$reserved_name"*) ;;
      *) log_fail "test_112(m): reserved-name refusal must name $reserved_name, got: $out" ;;
    esac
  done

  log_pass "test_112: generator refuses invalid manifests and missing CLI path values (TEST-004, TEST-005 stale/reasonless halves)"
}

test_116_metrics_correction_not_counted() {  # PR review / telemetry honesty
  log_info "test_116: the harness-surfaces metrics correction is folded into its original run, not counted as extra work..."
  node - "$PROJECT_ROOT/docs/ai/METRICS.jsonl" <<'NODE' || log_fail "test_116: correction still inflates metrics"
const fs = require('fs');
const rows = fs.readFileSync(process.argv[2], 'utf8').trim().split(/\r?\n/)
  .filter((line) => line && !line.startsWith('#')).map(JSON.parse)
  .filter((row) => row.ref_id === 'harness-surfaces-drift-unguarded');
if (rows.length !== 1) throw new Error(`want one metrics row, got ${rows.length}`);
const row = rows[0];
const runs = row.agent_runs || [];
if (runs.some((run) => /CORRECTION of/.test(run.note || ''))) throw new Error('correction is still an agent run');
const corrected = runs.find((run) => /commits 496b7a1/.test(run.note || ''));
if (!corrected || !/usage_total_tokens=128719/.test(corrected.note || '')) throw new Error('corrected token total is absent');
const duration = runs.reduce((sum, run) => sum + (run.duration_seconds || 0), 0);
if (duration !== 17319 || row.totals.agent_duration_seconds !== duration) throw new Error(`duration mismatch: runs=${duration} total=${row.totals.agent_duration_seconds}`);
const remediationRuns = runs.filter((run) => run.role === 'Remediation').length;
if (remediationRuns !== 2 || row.reliability.remediation_runs !== remediationRuns) throw new Error(`remediation mismatch: runs=${remediationRuns} total=${row.reliability.remediation_runs}`);
const validationFails = runs.filter((run) => run.role === 'Validation' && /FAIL round/.test(run.note || '')).length;
if (validationFails !== 1 || row.reliability.validation_fails !== validationFails) throw new Error(`validation-fail mismatch: runs=${validationFails} total=${row.reliability.validation_fails}`);
NODE
  log_pass "test_116: correction is non-billable and aggregate duration/remediation counts match the actual runs"
}

test_117_source_skills_are_lf_pinned() {  # PR review / Windows portability
  log_info "test_117: source and generated skill bytes are pinned to LF so core.autocrlf cannot create false divergence..."
  local path attr
  for path in \
    .claude/skills/aai-pr/SKILL.md \
    .agents/skills/aai-pr/SKILL.md \
    .codex/skills/aai-pr/SKILL.md \
    .codex/skills/README.md \
    .gemini/skills/aai-pr/SKILL.md \
    .gemini/skills/README.md; do
    attr="$(cd "$PROJECT_ROOT" && git check-attr eol -- "$path")"
    [[ "$attr" == "$path: eol: lf" ]] \
      || log_fail "test_117: expected $path to resolve to eol=lf, got: $attr"
  done
  log_pass "test_117: source and all generated skill files are pinned to LF"
}

test_113_bite_proofs_in_detached_worktree() {  # TEST-007 / Spec-AC-05
  log_info "test_113: bite proofs for the parity guard in a disposable DETACHED worktree, with unmutated controls (TEST-007)..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"

  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"
  local wt="$TEST_DIR/t113-worktree"
  local outer_before="$TEST_DIR/t113-outer-before.diff"
  local outer_after="$TEST_DIR/t113-outer-after.diff"
  git -C "$PROJECT_ROOT" diff --binary HEAD -- \
    .claude/skills .agents/skills .codex/skills .gemini/skills > "$outer_before" \
    || log_fail "test_113: could not snapshot the outer harness state"
  rm -rf "$wt"
  git -C "$PROJECT_ROOT" worktree add --detach "$wt" HEAD >/dev/null 2>&1 \
    || log_fail "test_113: could not create a disposable detached worktree at $wt from HEAD"
  HSK_ACTIVE_WORKTREE="$wt"

  # The canonical wrapper seeds staged/uncommitted bytes into PROJECT_ROOT
  # without moving HEAD. Carry the generator-owned tracked diff into this
  # nested worktree before running bite mutations, or the proof can exercise
  # the previously committed implementation and false-pass.
  local seed_patch="$TEST_DIR/t113-current-seed.diff"
  git -C "$PROJECT_ROOT" diff --binary HEAD -- \
    "$HSK_GENERATOR_REL" "$HSK_MANIFEST_REL" tests/skills/test-aai-hygiene-pack.sh \
    .claude/skills .agents/skills .codex/skills .gemini/skills > "$seed_patch" \
    || log_fail "test_113: could not capture the current seeded harness diff"
  if [[ -s "$seed_patch" ]]; then
    git -C "$wt" apply "$seed_patch" \
      || log_fail "test_113: could not apply the current seeded harness diff to the nested worktree"
  fi

  cmp -s "$PROJECT_ROOT/$HSK_GENERATOR_REL" "$wt/$HSK_GENERATOR_REL" \
    || log_fail "test_113: nested worktree did not inherit the current seeded generator bytes"
  cmp -s "$PROJECT_ROOT/tests/skills/test-aai-hygiene-pack.sh" "$wt/tests/skills/test-aai-hygiene-pack.sh" \
    || log_fail "test_113: nested worktree did not inherit the current parity-arm bytes"

  local gen="$wt/$HSK_GENERATOR_REL"
  [[ -f "$gen" ]] || log_fail "test_113: generator missing in the worktree checkout of HEAD: $gen"
  local parity_fn="test_111_generator_check_clean_and_idempotent"

  local source_snapshot="$TEST_DIR/t113-source-wrap-up.md"
  local codex_snapshot="$TEST_DIR/t113-codex-wrap-up"
  cp "$wt/.claude/skills/aai-wrap-up/SKILL.md" "$source_snapshot"
  rm -rf "$codex_snapshot"
  cp -R "$wt/.codex/skills/aai-wrap-up" "$codex_snapshot"

  local out rc

  # CONTROL — the worktree is an unmutated checkout of HEAD; --check must be
  # clean before any mutation.
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "test_113 CONTROL: --check on the unmutated worktree must exit 0, got $rc: $out"

  # MUTATION (a) — a new directory added under .claude/skills ONLY.
  mkdir -p "$wt/.claude/skills/aai-zz-mutant-fixture"
  printf -- '---\nname: aai-zz-mutant-fixture\ndescription: bite-proof fixture\n---\nbody\n' \
    > "$wt/.claude/skills/aai-zz-mutant-fixture/SKILL.md"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] \
    || log_fail "test_113(a): a new .claude/skills-only directory must redden --check, got exit 0"
  case "$out" in
    *"aai-zz-mutant-fixture"*) ;;
    *) log_fail "test_113(a): FAIL output must name the offending skill, got: $out" ;;
  esac
  rm -rf "$wt/.claude/skills/aai-zz-mutant-fixture"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_113: worktree not clean between mutations (a)->(b), got $rc: $out"

  # MUTATION (b) — a directory deleted from .codex/skills ONLY.
  rm -rf "$wt/.codex/skills/aai-wrap-up"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] \
    || log_fail "test_113(b): a directory deleted from .codex/skills only must redden --check, got exit 0"
  case "$out" in
    *".codex/skills/aai-wrap-up"*) ;;
    *) log_fail "test_113(b): FAIL output must name the offending tree and skill, got: $out" ;;
  esac
  rm -rf "$wt/.codex/skills/aai-wrap-up"
  cp -R "$codex_snapshot" "$wt/.codex/skills/aai-wrap-up"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_113: worktree not clean between mutations (b)->(c), got $rc: $out"

  # MUTATION (c) — a description line edited in .claude/skills ONLY.
  local target="$wt/.claude/skills/aai-wrap-up/SKILL.md"
  [[ -f "$target" ]] || log_fail "test_113(c): fixture skill missing: $target"
  local mutated="$TEST_DIR/t113-mutated-wrap-up.md"
  sed 's/^description: .*/description: bite-proof mutated description/' "$target" > "$mutated"
  cp "$mutated" "$target"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] \
    || log_fail "test_113(c): a description edited in .claude/skills only must redden --check, got exit 0"
  case "$out" in
    *"aai-wrap-up"*) ;;
    *) log_fail "test_113(c): FAIL output must name the offending skill, got: $out" ;;
  esac
  cp "$source_snapshot" "$wt/.claude/skills/aai-wrap-up/SKILL.md"
  out="$(cd "$wt" && env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh "$parity_fn" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_113: worktree not clean after reverting mutation (c), got $rc: $out"

  # SELF-BINDING (HAZ-RESTORE) — the real checkout is never touched; all
  # mutation happened only inside the disposable worktree.
  git -C "$PROJECT_ROOT" diff --binary HEAD -- \
    .claude/skills .agents/skills .codex/skills .gemini/skills > "$outer_after" \
    || log_fail "test_113: could not resnapshot the outer harness state"
  cmp -s "$outer_before" "$outer_after" \
    || log_fail "test_113: the tracked harness trees changed in the REAL checkout — mutation must be confined to the disposable worktree"

  git -C "$PROJECT_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  HSK_ACTIVE_WORKTREE=""

  log_pass "test_113: three independent mutations each redden the parity guard naming the offender, with clean unmutated controls before/between/after, in a disposable detached worktree; real tree untouched (TEST-007)"
}

test_118_bite_proofs_preserve_seeded_state() {  # PR review / seeded-wrapper regression
  log_info "test_118: bite proofs restore a seeded source+mirror state instead of HEAD..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"

  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"
  local shipping_root="$PROJECT_ROOT"
  local seeded_root="$TEST_DIR/t118-seeded-root"
  git clone --quiet --no-hardlinks "$shipping_root" "$seeded_root" \
    || log_fail "test_118: could not create seeded fixture repository"
  cp "$shipping_root/$HSK_GENERATOR_REL" "$seeded_root/$HSK_GENERATOR_REL" \
    || log_fail "test_118: could not seed the current generator into the fixture"
  cp "$shipping_root/tests/skills/test-aai-hygiene-pack.sh" "$seeded_root/tests/skills/test-aai-hygiene-pack.sh" \
    || log_fail "test_118: could not seed the current parity arm into the fixture"

  local source_skill="$seeded_root/.claude/skills/aai-wrap-up/SKILL.md"
  local changed_skill="$TEST_DIR/t118-changed-wrap-up.md"
  sed 's/^description: .*/description: seeded wrapper regression fixture/' \
    "$source_skill" > "$changed_skill"
  cp "$changed_skill" "$source_skill"
  (cd "$seeded_root" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --write >/dev/null) \
    || log_fail "test_118: could not regenerate mirrors for seeded fixture"

  (cd "$seeded_root" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --check >/dev/null) \
    || log_fail "test_118: seeded source+mirror fixture must begin clean"
  [[ -n "$(git -C "$seeded_root" status --short -- .claude/skills .agents/skills .codex/skills .gemini/skills)" ]] \
    || log_fail "test_118: fixture must differ from HEAD before bite proofs"

  PROJECT_ROOT="$seeded_root"
  test_113_bite_proofs_in_detached_worktree
  PROJECT_ROOT="$shipping_root"

  (cd "$seeded_root" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --check >/dev/null) \
    || log_fail "test_118: seeded source+mirror state diverged after bite proofs"
  [[ -n "$(git -C "$seeded_root" status --short -- .claude/skills .agents/skills .codex/skills .gemini/skills)" ]] \
    || log_fail "test_118: bite proofs silently reset the seeded fixture to HEAD"

  log_pass "test_118: nested mutations preserve the exact seeded source+mirror state and leave the outer fixture unchanged"
}

test_119_generator_idempotence_preserves_seeded_state() {  # PR review / seeded-wrapper regression
  log_info "test_119: generator idempotence compares against a seeded pre-write mirror state..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"

  TEST_DIR="${TEST_DIR:-$(ap_tmpdir)}"
  local shipping_root="$PROJECT_ROOT"
  local seeded_root="$TEST_DIR/t119-seeded-root"
  git clone --quiet --no-hardlinks "$shipping_root" "$seeded_root" \
    || log_fail "test_119: could not create seeded fixture repository"
  cp "$shipping_root/$HSK_GENERATOR_REL" "$seeded_root/$HSK_GENERATOR_REL" \
    || log_fail "test_119: could not seed the current generator into the fixture"

  local source_skill="$seeded_root/.claude/skills/aai-wrap-up/SKILL.md"
  local changed_skill="$TEST_DIR/t119-changed-wrap-up.md"
  sed 's/^description: .*/description: seeded idempotence regression fixture/' \
    "$source_skill" > "$changed_skill"
  cp "$changed_skill" "$source_skill"
  (cd "$seeded_root" && env -u AAI_ROLE node "$HSK_GENERATOR_REL" --write >/dev/null) \
    || log_fail "test_119: could not regenerate mirrors for seeded fixture"
  [[ -n "$(git -C "$seeded_root" status --short -- .claude/skills .agents/skills .codex/skills .gemini/skills)" ]] \
    || log_fail "test_119: fixture must differ from HEAD before idempotence proof"

  PROJECT_ROOT="$seeded_root"
  test_111_generator_check_clean_and_idempotent
  PROJECT_ROOT="$shipping_root"

  log_pass "test_119: clean --write preserves a seeded pre-write mirror state"
}

test_114_cursor_rule_contract() {  # TEST-008 / Spec-AC-07 (harness-surfaces-drift-unguarded)
  log_info "test_114: .cursor/rules/aai.mdc carries valid quoted glob metadata, no stale skills-are-prompt-files claim, no enumerated .aai/SKILL_ prompt paths, exactly one alwaysApply/description line each, at most 60 lines (TEST-008)..."
  local root="${1:-$PROJECT_ROOT}"
  local rule="$root/.cursor/rules/aai.mdc"
  [[ -f "$rule" ]] || log_fail "test_114: missing $rule"

  local c
  c="$(/usr/bin/grep -c 'Skills are prompt files' "$rule" || true)"
  [[ "$c" -eq 0 ]] \
    || log_fail "test_114: $rule still claims skills are prompt files to be read by hand ($c occurrence(s))"

  c="$(/usr/bin/grep -c '\.aai/SKILL_' "$rule" || true)"
  [[ "$c" -eq 0 ]] \
    || log_fail "test_114: $rule still enumerates .aai/SKILL_ prompt paths ($c occurrence(s))"

  c="$(/usr/bin/grep -c '^alwaysApply: true$' "$rule" || true)"
  [[ "$c" -eq 1 ]] \
    || log_fail "test_114: expected exactly one '^alwaysApply: true$' line in $rule, got $c"

  c="$(/usr/bin/grep -c '^description: ' "$rule" || true)"
  [[ "$c" -eq 1 ]] \
    || log_fail "test_114: expected exactly one '^description: ' line in $rule, got $c"

  c="$(/usr/bin/grep -c '^globs: "\*\*/\*"$' "$rule" || true)"
  [[ "$c" -eq 1 ]] \
    || log_fail "test_114: expected exactly one YAML-safe quoted 'globs: \"**/*\"' line in $rule, got $c"

  local lines
  lines="$(wc -l < "$rule" | tr -d ' ')"
  [[ "$lines" -le 60 ]] \
    || log_fail "test_114: $rule is $lines lines, want at most 60"

  log_pass "test_114: Cursor rule contract holds — quoted glob, no stale prompt-file claim, no enumerated SKILL_ paths, single alwaysApply/description line, $lines lines (TEST-008)"
}

test_115_root_shim_and_manifest_header() {  # TEST-009 / Spec-AC-08 (harness-surfaces-drift-unguarded)
  log_info "test_115: root AGENTS.md (not .aai/AGENTS.md) is titled for its real audience, and HARNESS_SKILLS.yaml's header records D2 (no .cursor/skills) and D3 (three-times duplicate offering) (TEST-009)..."
  local root="${1:-$PROJECT_ROOT}"
  local shim="$root/AGENTS.md"
  local manifest="$root/$HSK_MANIFEST_REL"
  [[ -f "$shim" ]] || log_fail "test_115: missing root shim $shim"
  [[ -f "$manifest" ]] || log_fail "test_115: missing $manifest"

  local c
  c="$(/usr/bin/grep -c '^# Codex Instructions' "$shim" || true)"
  [[ "$c" -eq 0 ]] \
    || log_fail "test_115: root $shim still carries a '# Codex Instructions' heading ($c occurrence(s))"

  local first
  first="$(head -1 "$shim")"
  [[ "$first" == "# Agent Instructions (Shim)" ]] \
    || log_fail "test_115: root $shim first line must be exactly '# Agent Instructions (Shim)', got: $first"

  c="$(/usr/bin/grep -c 'cursor/skills' "$manifest" || true)"
  [[ "$c" -ge 1 ]] \
    || log_fail "test_115: $manifest header must record the no-cursor-skills decision (D2) — 'cursor/skills' occurs $c time(s)"

  c="$(/usr/bin/grep -c 'three times' "$manifest" || true)"
  [[ "$c" -ge 1 ]] \
    || log_fail "test_115: $manifest header must record the three-times duplicate offering (D3) — 'three times' occurs $c time(s)"

  c="$(/usr/bin/grep -c 'SPEC-DRAFT-harness-surfaces-drift-unguarded' "$manifest" || true)"
  [[ "$c" -eq 0 ]] \
    || log_fail "test_115: $manifest still references the pre-allocation draft spec path ($c occurrence(s))"

  c="$(/usr/bin/grep -c 'SPEC-0154-spec-harness-surfaces-drift-unguarded.md' "$manifest" || true)"
  [[ "$c" -eq 2 ]] \
    || log_fail "test_115: $manifest must reference the allocated SPEC-0154 path twice, got $c occurrence(s)"

  log_pass "test_115: root shim titled for its real audience (root AGENTS.md, not .aai/AGENTS.md) and D2/D3 recorded in the manifest header (TEST-009)"
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
  test_030_auto_trigger_deprecation
  test_031_guard_config_conformance
  test_040_dual_verdict_prompt
  test_041_anti_gaming_protocol
  test_042_dual_verdict_surfaces
  test_043_review_taxonomy_alignment
  test_050_pr_merge_conflict
  test_051_no_number_prediction
  test_052_loop_drift_preflight
  test_060_work_item_brief
  test_070_companion_obligations
  test_080_subagent_contract_exists
  test_081_no_rule_duplication
  test_082_dispatch_refs_name_contract
  test_083_subagent_contract_hazards
  test_090_suite_map_pin
  test_091_session_journal_index_complete
  test_092_no_phantom_node_apis
  test_093_test_registration
  test_100_assert_payload_contract
  test_101_helper_survives_the_pipe_buffer
  test_102_pgq_ratchet_gate_and_bite
  test_103_pgq_baseline_is_measured_not_typed
  test_104_pgq_shrink_never_lowers_the_bar
  test_105_converted_sites_keep_their_needles
  test_110_skill_set_parity
  test_111_generator_check_clean_and_idempotent
  test_112_generator_refuses_bad_manifest
  test_113_bite_proofs_in_detached_worktree
  test_114_cursor_rule_contract
  test_115_root_shim_and_manifest_header
  test_116_metrics_correction_not_counted
  test_117_source_skills_are_lf_pinned
  test_118_bite_proofs_preserve_seeded_state
  test_119_generator_idempotence_preserves_seeded_state
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (RED-proof evidence);
# run the full suite only when invoked directly.
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
