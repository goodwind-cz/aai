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

  # (e) generated catalog entry updated.
  grep -A1 'name: "aai-auto-trigger"' "$PROJECT_ROOT/docs/SKILL_CATALOG.html" | grep -qi "deprecated" \
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
  test_050_pr_merge_conflict
  test_051_no_number_prediction
  test_052_loop_drift_preflight
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (RED-proof evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
