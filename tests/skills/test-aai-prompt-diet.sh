#!/usr/bin/env bash
#
# Test: prompt-layer diet, phase 1 (CHANGE-0011 / spec-prompt-layer-diet-phase-1)
# Grep-wiring suite for the shared intake include, SKILL_PROFILE de-fiction,
# STATE fallback dedup, and SKILL_LOOP caching/digest fixes.
#
# Covers TEST-001..010 from docs/specs/SPEC-0017-spec-prompt-layer-diet-phase-1.md.
# TEST-004 is a real e2e dry-run (constructs a DRAFT artifact per the moved
# instructions and audits it). TEST-010 asserts the repo-wide strict audit and
# the measured byte reduction; the "existing suites green" half of TEST-010 is
# owned by the full tests/skills run (validation evidence), not re-run here.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-prompt-diet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# Diet-floor constants, JUSTIFIED_ADDITIONS ledger, and the two pure helpers
# are single-sourced from the shared library (prompt-diet-floor-credit-drift /
# SPEC-0060-spec-prompt-diet-floor-credit-drift.md) so this suite and
# tests/skills/test-aai-verify-gate.sh can never drift from each other again
# (DEBT-0002 "two copies of one gate" pattern). Sourced at top level (not
# inside a function) so JUSTIFIED_ADDITIONS stays a global visible to
# `declare -p` in TEST-012/013 below.
source "$SCRIPT_DIR/lib/prompt-diet-ledger.sh"

E2E_DRAFT="docs/issues/CHANGE-DRAFT-prompt-diet-e2e-dry-run.md"

FAILED=0

cleanup() {
  rm -f "$PROJECT_ROOT/$E2E_DRAFT"
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

INTAKE_FILES=(
  .aai/INTAKE_CHANGE.prompt.md
  .aai/INTAKE_HOTFIX.prompt.md
  .aai/INTAKE_ISSUE.prompt.md
  .aai/INTAKE_PRD.prompt.md
  .aai/INTAKE_RELEASE.prompt.md
  .aai/INTAKE_RESEARCH.prompt.md
  .aai/INTAKE_RFC.prompt.md
  .aai/INTAKE_TECHDEBT.prompt.md
)

# The 10 prompts whose FALLBACK/STATE-WRITE footers were single-sourced (D4).
FALLBACK_PROMPTS=(
  .aai/PLANNING.prompt.md
  .aai/IMPLEMENTATION.prompt.md
  .aai/VALIDATION.prompt.md
  .aai/REMEDIATION.prompt.md
  .aai/SKILL_TDD.prompt.md
  .aai/ORCHESTRATION.prompt.md
  .aai/ORCHESTRATION_PARALLEL.prompt.md
  .aai/METRICS_FLUSH.prompt.md
  .aai/SKILL_LOOP.prompt.md
  .aai/SKILL_INTAKE.prompt.md
)

check_deps() {
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -d .aai ]] || log_skip ".aai directory not found"
}

# TEST-001 — each of the 8 INTAKE_* files references INTAKE_COMMON.md exactly once
test_001_include_reference() {
  local ok=1 f n
  for f in "${INTAKE_FILES[@]}"; do
    n=$(grep -cF "Read .aai/INTAKE_COMMON.md" "$f" 2>/dev/null || true)
    if [[ "$n" != "1" ]]; then
      log_info "TEST-001: $f has $n INTAKE_COMMON.md reference lines (want 1)"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-001 include reference x8" || log_fail "TEST-001 include reference x8"
}

# TEST-002 — INTAKE_COMMON.md exists; each block heading exactly once there, zero in INTAKE_*
test_002_common_blocks() {
  local ok=1
  if [[ ! -f .aai/INTAKE_COMMON.md ]]; then
    log_fail "TEST-002 .aai/INTAKE_COMMON.md does not exist"
    return
  fi
  local headings=(
    "## LANGUAGE POLICY"
    "## DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)"
    "## POST-SAVE CHECK (RFC-0002)"
    "## METRICS (after saving the document)"
  )
  local h n f
  for h in "${headings[@]}"; do
    n=$(grep -cF "$h" .aai/INTAKE_COMMON.md || true)
    if [[ "$n" != "1" ]]; then
      log_info "TEST-002: heading '$h' appears $n times in INTAKE_COMMON.md (want 1)"
      ok=0
    fi
  done
  # Block bodies / headings must be gone from the 8 intake prompts
  local markers=(
    "DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)"
    "POST-SAVE CHECK (RFC-0002)"
    "METRICS (after saving the document)"
    "Output the final saved markdown in English only"
  )
  local m
  for f in "${INTAKE_FILES[@]}"; do
    for m in "${markers[@]}"; do
      if grep -qF "$m" "$f" 2>/dev/null; then
        log_info "TEST-002: block marker '$m' still present in $f"
        ok=0
      fi
    done
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-002 shared blocks single-sourced" || log_fail "TEST-002 shared blocks single-sourced"
}

# TEST-003 — combined line count of the 8 INTAKE_* files <= 240 (50% of 480 baseline)
test_003_intake_line_budget() {
  local total
  total=$(cat "${INTAKE_FILES[@]}" | wc -l | tr -d ' ')
  if [[ "$total" -le 240 ]]; then
    log_pass "TEST-003 intake line budget ($total <= 240)"
  else
    log_fail "TEST-003 intake line budget ($total > 240)"
  fi
}

# TEST-004 — e2e dry-run: DRAFT artifact per the moved instructions passes strict audit
test_004_intake_dry_run() {
  if [[ ! -f .aai/INTAKE_COMMON.md ]]; then
    log_fail "TEST-004 cannot dry-run: INTAKE_COMMON.md missing"
    return
  fi
  # Construct the artifact exactly per INTAKE_COMMON.md DURABLE DOC IDENTITY:
  # docs/<type>/<TYPE>-DRAFT-<slug>.md, frontmatter id/number/status.
  cat > "$E2E_DRAFT" <<'EOF'
---
id: prompt-diet-e2e-dry-run
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# Change — Prompt diet e2e dry-run artifact (TEST-004)

## Summary
- Synthetic intake artifact produced per .aai/INTAKE_COMMON.md instructions.

## Motivation / Business Value
- Proves the relocated intake blocks still yield a template-compliant DRAFT.

## Scope
- In scope: this test artifact only.
- Out of scope: everything else.

## Affected Area
- tests/skills/test-aai-prompt-diet.sh (TEST-004 fixture).

## Desired Behavior (To-Be)
- The strict docs audit accepts this artifact.

## Acceptance Criteria
- AC-001: docs-audit --check --strict --no-event --path exits 0 on this file.

## Verification
- node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <this file>

## Constraints / Risks
- None; deleted by the test on exit.

## Notes
- Ephemeral fixture; never committed.
EOF
  if node .aai/scripts/docs-audit.mjs --check --strict --no-event --path "$E2E_DRAFT" >/dev/null 2>&1; then
    log_pass "TEST-004 intake dry-run artifact passes strict audit"
  else
    log_fail "TEST-004 intake dry-run artifact fails strict audit"
  fi
  rm -f "$E2E_DRAFT"
}

# TEST-005 — SKILL_PROFILE contains no fiction and is <= 8988 bytes
test_005_profile_defictioned() {
  local ok=1 f=.aai/SKILL_PROFILE.prompt.md
  local markers=("profiler.mjs" ".aai/lib/" "docs/ai/profiles/" "class Profiler" '```javascript')
  local m
  for m in "${markers[@]}"; do
    if grep -qF "$m" "$f"; then
      log_info "TEST-005: fictional marker '$m' present in $f"
      ok=0
    fi
  done
  local bytes
  bytes=$(wc -c < "$f" | tr -d ' ')
  if [[ "$bytes" -gt 8988 ]]; then
    log_info "TEST-005: $f is $bytes bytes (> 8988)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-005 SKILL_PROFILE de-fictioned ($bytes bytes)" || log_fail "TEST-005 SKILL_PROFILE de-fictioned"
}

# TEST-006 — STATE_FALLBACK.md holds the body markers; markers absent from all prompts
test_006_fallback_single_source() {
  local ok=1
  if [[ ! -f .aai/STATE_FALLBACK.md ]]; then
    log_fail "TEST-006 .aai/STATE_FALLBACK.md does not exist"
    return
  fi
  local markers=("Legacy field list" "never emit a second top-level" "STATE-WRITE SAFETY")
  local m
  for m in "${markers[@]}"; do
    if ! grep -qF "$m" .aai/STATE_FALLBACK.md; then
      log_info "TEST-006: body marker '$m' missing from STATE_FALLBACK.md"
      ok=0
    fi
    if grep -lF "$m" .aai/*.prompt.md >/dev/null 2>&1; then
      log_info "TEST-006: body marker '$m' still present in: $(grep -lF "$m" .aai/*.prompt.md | tr '\n' ' ')"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-006 fallback/safety single-sourced" || log_fail "TEST-006 fallback/safety single-sourced"
}

# TEST-007 — every 'state.mjs is absent' occurrence in the 10 prompts is the
# <=2-line pointer form naming .aai/STATE_FALLBACK.md
test_007_pointer_form() {
  local ok=1 f bad
  for f in "${FALLBACK_PROMPTS[@]}"; do
    bad=$(awk '
      /state\.mjs is absent/ { pending = NR; line = $0; next }
      pending && NR == pending + 1 {
        if (line !~ /STATE_FALLBACK\.md/ && $0 !~ /STATE_FALLBACK\.md/) print pending ": " line
        pending = 0
      }
      END { if (pending && line !~ /STATE_FALLBACK\.md/) print pending ": " line }
    ' "$f")
    if [[ -n "$bad" ]]; then
      log_info "TEST-007: $f has non-pointer fallback occurrence(s):"
      log_info "$bad"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-007 fallback occurrences are pointers" || log_fail "TEST-007 fallback occurrences are pointers"
}

# TEST-008 — SKILL_LOOP caching order + digest payload wiring
test_008_loop_caching_and_payload() {
  local ok=1 f=.aai/SKILL_LOOP.prompt.md
  # (a) the stable-prefix sentence must not place STATE.yaml in the prefix
  if grep -i "stable prefix" "$f" | grep -q "STATE.yaml"; then
    log_info "TEST-008: a 'stable prefix' line still names STATE.yaml"
    ok=0
  fi
  if ! grep -qi "stable prefix" "$f"; then
    log_info "TEST-008: no 'stable prefix' sentence found"
    ok=0
  fi
  # (b) a volatile-last sentence must place STATE.yaml last
  if ! grep -i "volatile" "$f" | grep -q "STATE.yaml"; then
    log_info "TEST-008: no volatile-last sentence naming STATE.yaml"
    ok=0
  fi
  # (c) step-3 payload names the digest script + JSON mode
  if ! grep -qF "loop-digest.mjs --json" "$f"; then
    log_info "TEST-008: step-3 payload does not name loop-digest.mjs --json"
    ok=0
  fi
  # (d) documented degradation clause
  if ! grep -qi "DEGRADATION" "$f"; then
    log_info "TEST-008: no degradation clause found"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-008 SKILL_LOOP caching + digest payload" || log_fail "TEST-008 SKILL_LOOP caching + digest payload"
}

# TEST-009 — loop-digest.mjs --json runs and emits exactly the documented keys
test_009_digest_contract() {
  local out
  if ! out=$(node .aai/scripts/loop-digest.mjs --json 2>/dev/null); then
    log_fail "TEST-009 loop-digest.mjs --json exited non-zero"
    return
  fi
  local keys expected
  keys=$(printf '%s' "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      console.log(Object.keys(JSON.parse(d)).sort().join(","));
    });
  ')
  expected="cost,durationSeconds,endedUtc,finalValidation,git,harnessVersion,recoveries,recoveryOutcomes,scopes,startedUtc,stopReason,ticks"
  if [[ "$keys" == "$expected" ]]; then
    log_pass "TEST-009 digest emits exactly the documented keys"
  else
    log_info "TEST-009: got keys: $keys"
    log_info "TEST-009: expected:  $expected"
    log_fail "TEST-009 digest key contract"
  fi
}

# TEST-010 — repo-wide strict audit clean + measured byte reduction >= 28KB
test_010_audit_and_reduction() {
  local ok=1
  if ! node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1; then
    log_info "TEST-010: repo-wide docs-audit --check --strict failed"
    ok=0
  fi
  local after extra reduction headroom
  after=$(cat .aai/*.prompt.md | wc -c | tr -d ' ')
  extra=0
  [[ -f .aai/INTAKE_COMMON.md ]] && extra=$((extra + $(wc -c < .aai/INTAKE_COMMON.md)))
  [[ -f .aai/STATE_FALLBACK.md ]] && extra=$((extra + $(wc -c < .aai/STATE_FALLBACK.md)))
  [[ -f .aai/ROLE_COMMON.md ]] && extra=$((extra + $(wc -c < .aai/ROLE_COMMON.md)))
  read -r reduction headroom <<<"$(compute_reduction_headroom "$BASELINE_PROMPT_BYTES" "$after" "$extra" "$JUSTIFIED_GROWTH_BYTES" "$REQUIRED_REDUCTION_BYTES")"
  if [[ "$headroom" -lt 0 ]]; then
    log_info "TEST-010: net reduction $reduction bytes (< $REQUIRED_REDUCTION_BYTES; after=$after, new files=$extra, credit=$JUSTIFIED_GROWTH_BYTES)"
    log_info "  $(justified_growth_breach_suggestion "$reduction" "$REQUIRED_REDUCTION_BYTES")"
    ok=0
  elif [[ "$headroom" -gt "$HEADROOM_CAP" ]]; then
    log_info "TEST-010: headroom $headroom bytes exceeds cap $HEADROOM_CAP (reduction=$reduction, required=$REQUIRED_REDUCTION_BYTES, credit=$JUSTIFIED_GROWTH_BYTES) -- either the credit is padded above what the ledger justifies, OR the corpus legitimately shrank below the credit: LOWER JUSTIFIED_GROWTH_BYTES to match the real deficit (a shrink means you no longer need the old credit), or add an itemized ledger line for genuine new growth"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-010 strict audit clean, net reduction $reduction bytes (headroom $headroom/$HEADROOM_CAP)" || log_fail "TEST-010 audit + byte reduction"
}

# TEST-011 (CHANGE-0009 spec-local TEST-015) — the three deterministic-tick
# prompts are thin wrappers: <=WRAPPER_LINE_CEILING lines each, each names
# its script path and carries a degrade instruction for the script-absent
# vendored layer.
#
# Ceiling raised 40->45 (DEBT-0002/SPEC-0048 Spec-AC-03): the original
# SPEC-0017 40-line cap left .aai/ORCHESTRATION.prompt.md at exactly 40/40
# (zero headroom) and broke live on a single canon-mandated line addition
# (LEARNED 2026-07-17). +5 gives deterministic-tick wrappers headroom for
# one more small addition while still rejecting anything that stops being
# "thin" (>45 lines) -- see the synthetic over-ceiling fixture below.
WRAPPER_LINE_CEILING=45

test_011_tick_wrappers() {
  local ok=1 pair f s n
  local pairs=(
    ".aai/ORCHESTRATION.prompt.md|.aai/scripts/orchestration-dispatch.mjs"
    ".aai/METRICS_FLUSH.prompt.md|.aai/scripts/metrics-flush.mjs"
    ".aai/METRICS_REPORT.prompt.md|.aai/scripts/metrics-report.mjs"
  )
  for pair in "${pairs[@]}"; do
    f="${pair%%|*}"
    s="${pair##*|}"
    if [[ ! -f "$f" ]]; then
      log_info "TEST-011: missing prompt $f"
      ok=0
      continue
    fi
    n=$(wc -l < "$f" | tr -d ' ')
    if [[ "$n" -gt "$WRAPPER_LINE_CEILING" ]]; then
      log_info "TEST-011: $f is $n lines (> $WRAPPER_LINE_CEILING — not a thin wrapper)"
      ok=0
    fi
    if ! grep -qF "$s" "$f"; then
      log_info "TEST-011: $f does not name its script $s"
      ok=0
    fi
    if ! grep -qiE "degrade|DEGRADED" "$f"; then
      log_info "TEST-011: $f carries no degrade instruction (script-absent path)"
      ok=0
    fi
  done

  # Anti-bloat proof (DEBT-0002 Spec-AC-03 / spec TEST-003): the ceiling must
  # actually bite, not just document a number. Build a synthetic fixture at
  # ceiling+1 (46) lines that otherwise satisfies the script-path + degrade
  # markers, and confirm the SAME comparison the real wrappers are checked
  # against correctly rejects it on line count alone.
  local fixture i
  fixture="$(mktemp "${TMPDIR:-/tmp}/aai-wrapper-ceiling-fixture.XXXXXX")"
  {
    echo "# synthetic oversize wrapper fixture (DEBT-0002 TEST-011 proof)"
    echo "Run .aai/scripts/orchestration-dispatch.mjs"
    echo "DEGRADED: script absent"
    for i in $(seq 1 43); do echo "# padding line $i"; done
  } > "$fixture"
  n=$(wc -l < "$fixture" | tr -d ' ')
  if [[ "$n" -le "$WRAPPER_LINE_CEILING" ]]; then
    log_info "TEST-011: synthetic fixture is $n lines (want > $WRAPPER_LINE_CEILING to prove the ceiling bites)"
    ok=0
  fi
  if ! grep -qF ".aai/scripts/orchestration-dispatch.mjs" "$fixture" || ! grep -qiE "degrade|DEGRADED" "$fixture"; then
    log_info "TEST-011: synthetic fixture missing required markers (test bug, not a real finding)"
    ok=0
  fi
  rm -f "$fixture"

  [[ $ok -eq 1 ]] && log_pass "TEST-011 deterministic-tick wrappers <=$WRAPPER_LINE_CEILING lines + script path + degrade, ceiling guard proven to bite (CHANGE-0009 TEST-015 / DEBT-0002 Spec-AC-03)" \
    || log_fail "TEST-011 deterministic-tick wrappers (CHANGE-0009 TEST-015 / DEBT-0002 Spec-AC-03)"
}

# TEST-012 (spec TEST-001, SPEC-0059 Spec-AC-01) — JUSTIFIED_GROWTH_BYTES ==
# -10463 (true-up: CHANGE-0120-cheap-ticks added an +889 B itemized entry for
# the three deterministic-tick wirings — ORCHESTRATION --confirm + the rule-9x
# advance exception (+186, file held at 40 lines), PLANNING step 10 routed
# through spec-freeze.mjs (+237), ORCHESTRATION_PARALLEL's spec-scope-edit.mjs
# pointer (+466); the rule-9x engine, both new scripts, the docs-model content-
# hash helpers and the spec-lint half-frozen rule all live in .aai/scripts/,
# outside the live glob, so they carry no ledger cost; credited 1:1 so headroom
# stays 1150/2048, over the prior
# -11352 (true-up: CHANGE-0122-strategy-scaled-evidence added a +216 B itemized
# entry for the PLANNING step 7 evidence-by-strategy pointer, 11073 -> 11289;
# the per-strategy evidence TABLE lives in .aai/templates/SPEC_TEMPLATE.md,
# outside the live glob and the extra accounting, so it carries no ledger cost;
# credited 1:1 so headroom stays 1150/2048, over the prior
# -11568 (true-up: prompt-diet-2-safe-wins appended a -12873 B NEGATIVE
# RECLAIMED entry executing the zero-pin "safe immediate wins" rows of
# docs/analysis/unhobbling-audit.md — SKILL_WORKTREE -6019, VALIDATION -2098,
# SKILL_TDD -1860, PLANNING -1699, SKILL_LOOP -1197, no new .aai/** file and no
# extra-accounting growth — dropping the total from 1305; headroom stays
# 1530/2048. Prior lineage: 1305 after lane-intake-ceremony +189 over
# 1116; before that
# 878 (true-up: runtime-state-consolidation added a +196 B itemized entry for
# the SKILL_CODE_REVIEW.prompt.md Verdict 2 SIDECAR LIFECYCLE convention pin —
# the CONVENTION half of the shared runtime-file.mjs sidecar-lib change; the lib
# + its negative-control suite + the hitl-channel.mjs migration are script/test
# only, no ledger cost — over the prior 682 B total).
# NOTE: this branch (feat/async-hitl-platform-comments) carries THREE
# async-HITL ledger true-ups — async-hitl-platform-comments +1281, async-hitl-
# resolve-lifecycle +262, and the PR #205 5d bot-sweep async-hitl-botfix +551
# (--ref token-reuse trust guard + bracket/bare token-form clarifier); the
# earlier -2835 figure was a transplant artifact from before the resolve-
# lifecycle/botfix true-ups landed on this branch.
# Prior lineage (true-up: async-hitl-platform-comments added a +1281 B itemized entry
# for the ORCHESTRATION_HITL ASYNC CHANNEL post bullet + SKILL_HITL STEP 0
# RESUME FROM PLATFORM poll block, credited 1:1 so headroom stays 0/2048, over
# the prior -4378 total after implementation-mode-choice +854/+4774; before
# that -10006 (true-up: github-no-bots-hardening +1147 B, then +282 B bot-sweep P1 reword; itemized entries for
# the SKILL_PR.prompt.md step 5/5d reviewer_bots-gated bot sweep + bounded-wait
# rule, 16740 -> 17887 B, credited 1:1 so headroom stays 106/2048, over the
# prior -11435 total; before that core-prompt-diet retired -3247 B via a NEGATIVE RECLAIMED
# entry — folding 4 cross-prompt duplications (FRICTION HOOK, PYTHON MONTY
# SCRATCHPAD, PRE-HANDOFF AC-TABLE RECONCILIATION, WORKTREE GATE) into
# .aai/ROLE_COMMON.md as canonical blocks (the 4 FRICTION HOOK sites also
# keep their own literal FRICTION_PROTOCOL.md + best-effort wording per
# test-aai-friction-wiring.sh's hostile-mutation pins), deleting SKILL_TDD's
# 3 dead prose sections, trimming SKILL_LOOP's VALIDATOR INDEPENDENCE
# rationale tail to a SUBAGENT_PROTOCOL.md pointer (the CONTRACT-naming
# dispatch-payload sentence stayed verbatim per hygiene-pack TEST-082), and
# pointing 4 more script-restating sections (SKILL_LOOP POST-TICK REAP,
# SKILL_CHECK_STATE INV-14, SKILL_PR RECONCILE WORKTREE TELEMETRY, VALIDATION
# LEAK-SAFE EXECUTION, ORCHESTRATION_PARALLEL SCOPE LOCKING) at their
# scripts' headers while keeping every operative recipe/gate/exit-code line
# verbatim — shrank the live .aai/*.prompt.md glob by a measured 6442 B while
# .aai/ROLE_COMMON.md (already inside TEST-010's extra accounting) grew
# 3195 B, a net 3247 B reduction, dropping the total from -8188; before that
# (true-up: issues-skill new .aai/SKILL_ISSUES.prompt.md thin wrapper
# (3810 B) documenting the on-demand /aai-issues fetch+triage skill, credited
# at its exact size, headroom back to 815/2048 (CHANGE-0087-issues-skill);
# before that, platform-portable-pr SKILL_PR.prompt.md step 5 PLATFORM
# GATE (pr-platform.mjs) + az command set + step 5d REVIEWER-FALLBACK
# CONTRACT + GENERIC MODE loud line added +3277 B (13767 -> 17044), credited
# 1:1, headroom unchanged at 605/2048 (operator direction 2026-07-28); before
# that, journal-report-contracts retired -2132 B net (journal relax -2715, report scope-note +583; operator decisions 2026-07-28); before that, docs-hub-generator retired -6099 B via a NEGATIVE RECLAIMED
# entry — rewriting .aai/SKILL_DOCS_HUB.prompt.md (9513 B, a ~70-file LLM
# fan-out prompt that hand-authored docs/SKILL_CATALOG.html per run, drifted
# to 27/35 skills stale) down to a 3409 B script-first thin wrapper around
# the new deterministic .aai/scripts/generate-docs-hub.mjs — dropping the
# total -7254 -> -13353; before that, dashboard-refit retired -21517 B (21565 initial minus 48 B review remediation) via a NEGATIVE RECLAIMED
# entry — rewriting .aai/SKILL_DASHBOARD.prompt.md (19173 B, ~330 of 652 lines
# a stale duplicate implementation dump of generate-dashboard.mjs, plus an
# unimplemented --publish flag) down to a 4152 B script-first thin wrapper,
# and .aai/SKILL_TEST_SKILLS.prompt.md (9218 B, stale hardcoded 11-skill
# Example Output + a pytest/cargo CI snippet) down to a 2674 B wrapper around
# the real tests/skills/test-framework.sh — dropping the total from 14263 (a
# negative total is expected: the corpus has shrunk enough that no positive
# credit is owed); before that, doctor-determinize retired -7534 B via a
# NEGATIVE RECLAIMED entry — rewriting .aai/SKILL_DOCTOR.prompt.md from a
# 10697 B prose file (11 of 13 health-check categories were hand-computed
# file-existence/line-count/git-status prose) to a 3163 B thin wrapper around
# the new deterministic .aai/scripts/aai-doctor.mjs — dropping the total from
# 21738; before that, decapod-prune retired -9573 B via a NEGATIVE RECLAIMED
# entry — the deleted SKILL_DECAPOD.prompt.md's 9571 B plus 2 B residual
# reword slack — dropping the total from 31311; before that,
# state-bootstrap-template added a +286 B itemized entry for
# the SKILL_CHECK_STATE.prompt.md AUTHORITATIVE SCHEMA reword naming the new
# .aai/templates/STATE_TEMPLATE.yaml as the canonical schema source, over the
# prior 31025 B total after prompt-hash-runtime-wiring added a +131 B itemized
# entry for the SKILL_LOOP.prompt.md step 4 --prompt-hash pass-through pointer, over the
# prior 30894 B total after learned-append-gate added a +755 B itemized entry
# for the SKILL_WRAP_UP.prompt.md step 3 critic-then-gate rewrite + step 6
# cross-reference, over the prior 30139 B total after friction-capture-
# default-on added a +1881 B itemized entry for the thin FRICTION HOOK
# pointers wired into VALIDATION/REMEDIATION/SKILL_PR/SKILL_WRAP_UP naming
# FRICTION_PROTOCOL.md's new "Deterministic hook points" subsection, over the
# prior 27805 B total after pr-post-open-review-sweep added a +992 B itemized
# entry for SKILL_PR step 5d POST-OPEN REVIEW SWEEP, over the prior 26781 B
# total after prompt-dedup-canonical-includes appended a -3021 B NEGATIVE
# entry that reclaims credit no longer needed once the D5/ceremony/AC-gate
# dedup genuinely shrank the corpus, over the prior 29802 B total from
# token-capture-canary) AND equals an independent re-sum of
# JUSTIFIED_ADDITIONS. This expected total is bumped, never recomputed
# silently, each time a scope legitimately appends a ledger entry
# (LEARNED.md 2026-07-17: the true-up is definition-of-done for
# prompt-touching scopes).
test_012_growth_sum_matches_ledger() {
  if ! declare -p JUSTIFIED_ADDITIONS >/dev/null 2>&1; then
    log_fail "TEST-012 (spec TEST-001) JUSTIFIED_ADDITIONS array does not exist yet"
    return
  fi
  local ok=1 independent_sum=0 _e
  for _e in "${JUSTIFIED_ADDITIONS[@]}"; do
    independent_sum=$(( independent_sum + ${_e%% *} ))
  done
  if [[ "$JUSTIFIED_GROWTH_BYTES" -ne -10463 ]]; then
    log_info "TEST-012 (spec TEST-001): JUSTIFIED_GROWTH_BYTES=$JUSTIFIED_GROWTH_BYTES (want -10463)"
    ok=0
  fi
  if [[ "$independent_sum" -ne "$JUSTIFIED_GROWTH_BYTES" ]]; then
    log_info "TEST-012 (spec TEST-001): independent re-sum=$independent_sum != JUSTIFIED_GROWTH_BYTES=$JUSTIFIED_GROWTH_BYTES"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-012 (spec TEST-001) JUSTIFIED_GROWTH_BYTES == -10463 == independent re-sum" \
    || log_fail "TEST-012 (spec TEST-001) growth sum mismatch"
}

# TEST-013 (spec TEST-002, SPEC-0059 Spec-AC-01) — array has >=3 entries;
# each entry's leading field is numeric bytes.
test_013_ledger_entry_shape() {
  if ! declare -p JUSTIFIED_ADDITIONS >/dev/null 2>&1; then
    log_fail "TEST-013 (spec TEST-002) JUSTIFIED_ADDITIONS array does not exist yet"
    return
  fi
  local ok=1 _e lead
  if [[ "${#JUSTIFIED_ADDITIONS[@]}" -lt 3 ]]; then
    log_info "TEST-013 (spec TEST-002): JUSTIFIED_ADDITIONS has ${#JUSTIFIED_ADDITIONS[@]} entries (want >=3)"
    ok=0
  fi
  for _e in "${JUSTIFIED_ADDITIONS[@]}"; do
    lead="${_e%% *}"
    # A leading '-' is allowed (prompt-dedup-canonical-includes): a NEGATIVE
    # entry reclaims credit when the corpus genuinely shrank below what the
    # ledger justified (see TEST-010's own remediation message).
    if ! [[ "$lead" =~ ^-?[0-9]+$ ]]; then
      log_info "TEST-013 (spec TEST-002): entry '$_e' has non-numeric leading bytes field '$lead'"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-013 (spec TEST-002) ledger entries >=3, numeric leading bytes field" \
    || log_fail "TEST-013 (spec TEST-002) ledger entry shape"
}

# TEST-014 (spec TEST-003, SPEC-0059 Spec-AC-02) — synthetic breach input
# prints a paste-ready JUSTIFIED_ADDITIONS+=( "..." ) line with the correct
# computed deficit, WITHOUT touching the real ledger.
test_014_breach_suggestion_deficit() {
  if ! declare -f justified_growth_breach_suggestion >/dev/null 2>&1; then
    log_fail "TEST-014 (spec TEST-003) justified_growth_breach_suggestion() does not exist yet"
    return
  fi
  local out expected_deficit=1234
  local synth_required=$REQUIRED_REDUCTION_BYTES
  local synth_reduction=$(( synth_required - expected_deficit ))
  out=$(justified_growth_breach_suggestion "$synth_reduction" "$synth_required")
  case "$out" in
    *'JUSTIFIED_ADDITIONS+=( "'"$expected_deficit"' '*)
      log_pass "TEST-014 (spec TEST-003) synthetic breach -> deficit=$expected_deficit paste-ready entry" ;;
    *)
      log_info "TEST-014 (spec TEST-003): got '$out' (want deficit=$expected_deficit paste-ready entry)"
      log_fail "TEST-014 (spec TEST-003) breach suggestion deficit" ;;
  esac
}

# TEST-015 (spec TEST-004, SPEC-0059 Spec-AC-02) — synthetic over-padded
# credit is still detected as headroom > HEADROOM_CAP (cap guard still
# bites), driven through the SAME formula TEST-010 uses, without touching
# the real corpus or ledger.
test_015_headroom_cap_still_bites() {
  if ! declare -f compute_reduction_headroom >/dev/null 2>&1; then
    log_fail "TEST-015 (spec TEST-004) compute_reduction_headroom() does not exist yet"
    return
  fi
  local reduction headroom
  local synth_baseline=$REQUIRED_REDUCTION_BYTES
  local synth_credit=$(( HEADROOM_CAP + 1 ))
  read -r reduction headroom <<<"$(compute_reduction_headroom "$synth_baseline" 0 0 "$synth_credit" "$REQUIRED_REDUCTION_BYTES")"
  if [[ "$headroom" -gt "$HEADROOM_CAP" ]]; then
    log_pass "TEST-015 (spec TEST-004) over-padded synthetic credit ($synth_credit) -> headroom($headroom) > CAP($HEADROOM_CAP), cap guard still bites"
  else
    log_info "TEST-015 (spec TEST-004): synthetic headroom=$headroom not > cap=$HEADROOM_CAP (credit=$synth_credit)"
    log_fail "TEST-015 (spec TEST-004) cap-bite guard"
  fi
}

# TEST-016 (prompt-hash-runtime-wiring, Spec-AC-01) — SKILL_LOOP.prompt.md
# names a --prompt-hash pass-through from the dispatch `Prompt hash:` line so
# an orchestrator following the loop verbatim records prompt_hash on the
# dispatched role's append-run (the producer side, PR #170, was otherwise
# never consumed).
test_016_skill_loop_prompt_hash_pointer() {
  local ok=1 f=.aai/SKILL_LOOP.prompt.md
  if ! grep -qF "Prompt hash:" "$f"; then
    log_info "TEST-016: $f does not reference the dispatch 'Prompt hash:' line"
    ok=0
  fi
  if ! grep -qF -- "--prompt-hash" "$f"; then
    log_info "TEST-016: $f does not name the --prompt-hash append-run flag"
    ok=0
  fi
  # Both layers must carry the pass-through: SKILL_LOOP for the parent-loop
  # path AND SUBAGENT_PROTOCOL for the single-mode orchestration agent that
  # actually executes append-run at merge time (PR #172 Codex P1 — the
  # parent-loop pointer alone never reaches the appending component).
  local p=.aai/SUBAGENT_PROTOCOL.md
  if ! grep -qF -- "--prompt-hash" "$p"; then
    log_info "TEST-016: $p does not name the --prompt-hash append-run pass-through"
    ok=0
  fi
  if ! grep -qF "prompt_hash" "$p"; then
    log_info "TEST-016: $p does not reference the dispatch JSON prompt_hash field"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-016 prompt-hash pass-through pointer (SKILL_LOOP + SUBAGENT_PROTOCOL)" \
    || log_fail "TEST-016 prompt-hash pass-through pointer (SKILL_LOOP + SUBAGENT_PROTOCOL)"
}

# TEST-017 (dashboard-refit, CHANGE-0076 AC-001/AC-002) — the two rewritten
# thin-wrapper prompts pin their script-first / stale-content-dropped shape
# so a future edit cannot silently regress back to a source dump or reinstate
# unimplemented/unused examples:
#   - SKILL_DASHBOARD.prompt.md names the real engine (generate-dashboard.mjs)
#     and never mentions the documented-but-unimplemented --publish flag
#     (publishing is /aai-share's job, per CHANGE-0076 decision).
#   - SKILL_TEST_SKILLS.prompt.md never mentions pytest or cargo (the stale
#     CI snippet this project does not use).
test_017_dashboard_test_skills_pins() {
  local ok=1 d=.aai/SKILL_DASHBOARD.prompt.md t=.aai/SKILL_TEST_SKILLS.prompt.md
  if [[ ! -f "$d" ]]; then
    log_info "TEST-017: $d does not exist"
    ok=0
  else
    if ! grep -qF "generate-dashboard.mjs" "$d"; then
      log_info "TEST-017: $d does not name generate-dashboard.mjs"
      ok=0
    fi
    if grep -qF -- "--publish" "$d"; then
      log_info "TEST-017: $d still mentions --publish (unimplemented; publishing is /aai-share's job)"
      ok=0
    fi
  fi
  if [[ ! -f "$t" ]]; then
    log_info "TEST-017: $t does not exist"
    ok=0
  else
    if grep -qi "pytest" "$t"; then
      log_info "TEST-017: $t still mentions pytest (stale CI snippet)"
      ok=0
    fi
    if grep -qi "cargo" "$t"; then
      log_info "TEST-017: $t still mentions cargo (stale CI snippet)"
      ok=0
    fi
  fi
  if [[ -f "$t" ]] && grep -qE "attempts common repairs|auto-fix common issues" "$t"; then
    log_info "TEST-017: $t claims --fix performs repairs (AUTO_FIX is a no-op in test-framework.sh)"
    ok=0
  fi
  if [[ $ok -eq 1 ]]; then
    log_pass "TEST-017 SKILL_DASHBOARD/SKILL_TEST_SKILLS content pins (CHANGE-0076)"
  else
    log_fail "TEST-017 SKILL_DASHBOARD/SKILL_TEST_SKILLS content pins (CHANGE-0076)"
  fi
}

test_018_journal_report_contract_pins() {  # CHANGE-0080/0082 content pins
  local ok=1 j=.aai/SKILL_SESSION_JOURNAL.prompt.md v=.aai/SKILL_VALIDATE_REPORT.prompt.md
  grep -qF "<YYYY-MM-DD>-<slug>.md" "$j" || { log_info "TEST-018: $j lacks the date-slug naming contract"; ok=0; }
  grep -qF "| Date | Session | Focus |" "$j" || { log_info "TEST-018: $j lacks the 3-column INDEX contract"; ok=0; }
  grep -qF "SESSION-<slug>" "$j" && { log_info "TEST-018: $j still mandates the retired SESSION-<slug> naming"; ok=0; }
  grep -qF "PROJECT_SESSION_TEMPLATE" "$j" && { log_info "TEST-018: $j still references the pruned template"; ok=0; }
  grep -qF "STANDALONE, ON-DEMAND" "$v" || { log_info "TEST-018: $v lacks the opt-in scope note"; ok=0; }
  grep -qF "VALIDATION-<YYYYMMDD-HHMMSSZ>-<slug>.md" "$v" || { log_info "TEST-018: $v lacks the unified report naming"; ok=0; }
  grep -qE "reports/validation-<" "$v" && { log_info "TEST-018: $v still carries the retired lowercase naming"; ok=0; }
  if [[ $ok -eq 1 ]]; then
    log_pass "TEST-018 journal/report contract pins (CHANGE-0080/0082)"
  else
    log_fail "TEST-018 journal/report contract pins (CHANGE-0080/0082)"
  fi
}

# TEST-019 (core-prompt-diet) — the 4 dedup targets now have exactly ONE
# canonical copy each (in .aai/ROLE_COMMON.md) and every former site is a
# pointer, not a restatement; and the surviving MEDIUM-RISK recipes/gates
# survive verbatim (leak-safe exec, scope-lock acquire/exit-code lines,
# INV-14 pointer + WRITER RULE, RECONCILE WORKTREE TELEMETRY exit codes).
test_019_core_prompt_diet_dedup() {
  local ok=1

  # (a) each moved block's distinctive body text appears in ROLE_COMMON.md
  # exactly once, and NOWHERE else across the live .aai/*.prompt.md glob.
  local markers=(
    'Skill wiring (shadow capture)'
    'Do not use it for project imports, third-party libraries'
    '--event ac_status --ref <SPEC-ID>/<Spec-AC-ID> --from planned --to done'
    'Action: dispatch `.aai/SKILL_WORKTREE.prompt.md` operation `recommendation gate`'
  )
  local m n_common n_glob
  for m in "${markers[@]}"; do
    n_common=$(grep -cF -- "$m" .aai/ROLE_COMMON.md || true)
    if [[ "$n_common" != "1" ]]; then
      log_info "TEST-019: marker '$m' appears $n_common times in ROLE_COMMON.md (want 1)"
      ok=0
    fi
    n_glob=$(grep -lF -- "$m" .aai/*.prompt.md 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$n_glob" != "0" ]]; then
      log_info "TEST-019: marker '$m' still present in $(grep -lF -- "$m" .aai/*.prompt.md | tr '\n' ' ') (want 0 — should be a pointer)"
      ok=0
    fi
  done

  # (b) each former site now carries a pointer to its ROLE_COMMON.md block
  local pointer_sites=(
    ".aai/IMPLEMENTATION.prompt.md|FRICTION HOOK"
    ".aai/VALIDATION.prompt.md|FRICTION HOOK"
    ".aai/REMEDIATION.prompt.md|FRICTION HOOK"
    ".aai/IMPLEMENTATION.prompt.md|PYTHON MONTY SCRATCHPAD"
    ".aai/SKILL_TDD.prompt.md|PYTHON MONTY SCRATCHPAD"
    ".aai/IMPLEMENTATION.prompt.md|PRE-HANDOFF AC-TABLE RECONCILIATION"
    ".aai/SKILL_TDD.prompt.md|PRE-HANDOFF AC-TABLE RECONCILIATION"
    ".aai/ORCHESTRATION_PARALLEL.prompt.md|WORKTREE GATE"
    ".aai/IMPLEMENTATION.prompt.md|WORKTREE GATE"
    ".aai/SKILL_TDD.prompt.md|WORKTREE GATE"
  )
  local pair f label squashed
  for pair in "${pointer_sites[@]}"; do
    f="${pair%%|*}"
    label="${pair##*|}"
    # Squash newlines so a pointer phrase wrapped across a line break (prose
    # word-wrap) still matches a single-line substring check.
    squashed=$(tr '\n' ' ' < "$f" | tr -s ' ')
    case "$squashed" in
      *"ROLE_COMMON.md $label"*) : ;;
      *)
        log_info "TEST-019: $f has no pointer to ROLE_COMMON.md $label"
        ok=0
        ;;
    esac
  done

  # (b2) VALIDATION has TWO FRICTION HOOK sites (discovery-gate + FAIL-verdict);
  # the at-least-one check above would miss a regression that drops one of them.
  # Pin both explicitly.
  local val_friction_n
  val_friction_n=$(grep -cF "ROLE_COMMON.md FRICTION HOOK" .aai/VALIDATION.prompt.md)
  if [[ "$val_friction_n" -lt 2 ]]; then
    log_info "TEST-019: VALIDATION.prompt.md must carry the FRICTION HOOK pointer at BOTH sites (found $val_friction_n, want >=2)"
    ok=0
  fi

  # (c) SKILL_TDD dead sections gone; troubleshooting pointer present
  if grep -qF '## Token Optimization' .aai/SKILL_TDD.prompt.md || \
     grep -qF '## Example Complete Cycle' .aai/SKILL_TDD.prompt.md; then
    log_info "TEST-019: SKILL_TDD.prompt.md still carries a dead prose section"
    ok=0
  fi
  if ! grep -qF 'SKILL_DEBUG.prompt.md' .aai/SKILL_TDD.prompt.md; then
    log_info "TEST-019: SKILL_TDD.prompt.md Troubleshooting has no pointer to SKILL_DEBUG.prompt.md"
    ok=0
  fi

  # (d) SKILL_LOOP VALIDATOR INDEPENDENCE points at SUBAGENT_PROTOCOL.md
  if ! grep -qF 'SUBAGENT_PROTOCOL.md' .aai/SKILL_LOOP.prompt.md; then
    log_info "TEST-019: SKILL_LOOP.prompt.md VALIDATOR INDEPENDENCE has no SUBAGENT_PROTOCOL.md pointer"
    ok=0
  fi
  if grep -qF 'Prefer a different model_id than the implementer when the platform' .aai/SKILL_LOOP.prompt.md; then
    log_info "TEST-019: SKILL_LOOP.prompt.md still restates VALIDATOR INDEPENDENCE prose"
    ok=0
  fi

  # (e) leak-safe exec recipe (VALIDATION) survives verbatim
  if ! grep -qF 'AAI_REAP_STEP_START_EPOCH=$(date +%s)' .aai/VALIDATION.prompt.md || \
     ! grep -qF '.aai/scripts/aai-run-tests.sh <cmd>' .aai/VALIDATION.prompt.md || \
     ! grep -qF '.aai/scripts/aai-reap-tests.sh' .aai/VALIDATION.prompt.md; then
    log_info "TEST-019: VALIDATION.prompt.md LEAK-SAFE EXECUTION recipe regressed"
    ok=0
  fi

  # (f) scope-lock acquire/exit-code lines (ORCHESTRATION_PARALLEL) survive
  if ! grep -qF 'docs-lock.mjs acquire <scope> <owner>' .aai/ORCHESTRATION_PARALLEL.prompt.md || \
     ! grep -qF 'exit 3 => scope is held by a live lock' .aai/ORCHESTRATION_PARALLEL.prompt.md || \
     ! grep -qF 'docs-lock.mjs release <scope> <owner>' .aai/ORCHESTRATION_PARALLEL.prompt.md || \
     ! grep -qF 'exit 4 => lock is owned by someone else' .aai/ORCHESTRATION_PARALLEL.prompt.md; then
    log_info "TEST-019: ORCHESTRATION_PARALLEL.prompt.md SCOPE LOCKING acquire/exit-code lines regressed"
    ok=0
  fi

  # (g) INV-14 pointer + WRITER RULE both present (SKILL_CHECK_STATE)
  if ! grep -qF 'check-state.mjs` header' .aai/SKILL_CHECK_STATE.prompt.md || \
     ! grep -qF 'WRITER RULE: always append into the EXISTING metrics.work_items.<ref>.agent_runs' .aai/SKILL_CHECK_STATE.prompt.md; then
    log_info "TEST-019: SKILL_CHECK_STATE.prompt.md INV-14 pointer + WRITER RULE regressed"
    ok=0
  fi

  # (h) RECONCILE WORKTREE TELEMETRY exit-code branching + FALLBACK survive
  if ! grep -qF 'node .aai/scripts/reconcile-telemetry.mjs --ref <ref>' .aai/SKILL_PR.prompt.md || \
     ! grep -qF 'Exit 0 (carried or no-op)' .aai/SKILL_PR.prompt.md || \
     ! grep -qF 'Exit 1 (write happened, post-write verify failed)' .aai/SKILL_PR.prompt.md; then
    log_info "TEST-019: SKILL_PR.prompt.md RECONCILE WORKTREE TELEMETRY recipe regressed"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-019 core-prompt-diet dedup + surviving recipes intact" \
    || log_fail "TEST-019 core-prompt-diet dedup + surviving recipes"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_include_reference
  test_002_common_blocks
  test_003_intake_line_budget
  test_004_intake_dry_run
  test_005_profile_defictioned
  test_006_fallback_single_source
  test_007_pointer_form
  test_008_loop_caching_and_payload
  test_009_digest_contract
  test_010_audit_and_reduction
  test_011_tick_wrappers
  test_012_growth_sum_matches_ledger
  test_013_ledger_entry_shape
  test_014_breach_suggestion_deficit
  test_015_headroom_cap_still_bites
  test_016_skill_loop_prompt_hash_pointer
  test_017_dashboard_test_skills_pins
  test_018_journal_report_contract_pins
  test_019_core_prompt_diet_dedup

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
