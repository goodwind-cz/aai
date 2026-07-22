#!/usr/bin/env bash
#
# Test: prompt-layer diet, phase 1 (CHANGE-0011 / spec-prompt-layer-diet-phase-1)
# Grep-wiring suite for the shared intake include, SKILL_PROFILE de-fiction,
# STATE fallback dedup, and SKILL_LOOP caching/digest fixes.
#
# Covers TEST-001..010 from docs/specs/SPEC-DRAFT-prompt-layer-diet-phase-1.md.
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
# SPEC-DRAFT-spec-prompt-diet-floor-credit-drift.md) so this suite and
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
# 19298 (true-up: metrics-flush-strands-completed-refs added a 738 B itemized
# entry for the METRICS_FLUSH.prompt.md --sweep mention + its code-review reword,
# to the prior 18560 B total) AND equals an independent re-sum of
# JUSTIFIED_ADDITIONS. This
# expected total is bumped, never recomputed silently, each time a scope
# legitimately appends a ledger entry (LEARNED.md 2026-07-17: the true-up is
# definition-of-done for prompt-touching scopes).
test_012_growth_sum_matches_ledger() {
  if ! declare -p JUSTIFIED_ADDITIONS >/dev/null 2>&1; then
    log_fail "TEST-012 (spec TEST-001) JUSTIFIED_ADDITIONS array does not exist yet"
    return
  fi
  local ok=1 independent_sum=0 _e
  for _e in "${JUSTIFIED_ADDITIONS[@]}"; do
    independent_sum=$(( independent_sum + ${_e%% *} ))
  done
  if [[ "$JUSTIFIED_GROWTH_BYTES" -ne 19298 ]]; then
    log_info "TEST-012 (spec TEST-001): JUSTIFIED_GROWTH_BYTES=$JUSTIFIED_GROWTH_BYTES (want 19298)"
    ok=0
  fi
  if [[ "$independent_sum" -ne "$JUSTIFIED_GROWTH_BYTES" ]]; then
    log_info "TEST-012 (spec TEST-001): independent re-sum=$independent_sum != JUSTIFIED_GROWTH_BYTES=$JUSTIFIED_GROWTH_BYTES"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-012 (spec TEST-001) JUSTIFIED_GROWTH_BYTES == 19298 == independent re-sum" \
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
    if ! [[ "$lead" =~ ^[0-9]+$ ]]; then
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
