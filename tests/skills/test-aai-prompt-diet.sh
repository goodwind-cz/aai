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

# Byte baseline measured before any CHANGE-0011 edit (evidence:
# docs/ai/tdd/prompt-diet-kb-before.txt). AC floor: >= 28KB net reduction.
BASELINE_PROMPT_BYTES=357457
REQUIRED_REDUCTION_BYTES=28672   # 28 KB

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
  local after extra reduction
  after=$(cat .aai/*.prompt.md | wc -c | tr -d ' ')
  extra=0
  [[ -f .aai/INTAKE_COMMON.md ]] && extra=$((extra + $(wc -c < .aai/INTAKE_COMMON.md)))
  [[ -f .aai/STATE_FALLBACK.md ]] && extra=$((extra + $(wc -c < .aai/STATE_FALLBACK.md)))
  reduction=$((BASELINE_PROMPT_BYTES - after - extra))
  if [[ "$reduction" -lt "$REQUIRED_REDUCTION_BYTES" ]]; then
    log_info "TEST-010: net reduction $reduction bytes (< $REQUIRED_REDUCTION_BYTES; after=$after, new files=$extra)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-010 strict audit clean, net reduction $reduction bytes" || log_fail "TEST-010 audit + byte reduction"
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
