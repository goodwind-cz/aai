#!/usr/bin/env bash
#
# Test: aai-token-capture — harness-reported token usage capture (CHANGE-0032
# / docs/specs/SPEC-0043-spec-loop-token-usage-capture.md, TEST-001..005).
#
# Verifies the prompt-layer canon wiring that lets the dispatching PARENT
# (never a self-reporting subagent — it cannot observe its own usage) carry
# harness-reported token usage into the EXISTING state.mjs flag surface:
#   - TEST-001 (Spec-AC-01): SKILL_LOOP step 4/6 + SUBAGENT_PROTOCOL instruct
#     parent-side capture of DECOMPOSED usage into the existing --tokens-in/
#     --tokens-out flags.
#   - TEST-002 (Spec-AC-02): SUBAGENT_PROTOCOL defines the
#     `usage_total_tokens=<N>` note grammar for an UNDECOMPOSED total and
#     prohibits splitting/relabeling it.
#   - TEST-003 (Spec-AC-03): all five role prompts carry the subagent-mode
#     append carve-out referencing SUBAGENT_PROTOCOL.md; ORCHESTRATION
#     appends the completed role's run with harness usage.
#   - TEST-004 (Spec-AC-04): SKILL_LOOP stop condition f's run-budget tally
#     counts observed undecomposed totals; the never-fabricate no-op clause
#     is retained verbatim.
#   - TEST-005 (Spec-AC-02, seam): append-run --note "usage_total_tokens=..."
#     (no token flags) round-trips verbatim through STATE.yaml into a flushed
#     METRICS.jsonl line, tokens stay null, and the "cost unattributable"
#     warning still fires (never silenced for an undecomposed total).
#
# ALL fixtures for TEST-005 are scratch temp-dir files (--state/--metrics/
# --ticks/--pricing/--events overrides); the real gitignored runtime files
# are NEVER touched. bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-token-capture"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_SCRIPT="$PROJECT_ROOT/.aai/scripts/state.mjs"
FLUSH_SCRIPT="$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs"
PROTOCOL="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
LOOP="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
ORCH="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
PLANNING="$PROJECT_ROOT/.aai/PLANNING.prompt.md"
IMPLEMENTATION="$PROJECT_ROOT/.aai/IMPLEMENTATION.prompt.md"
VALIDATION="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
REMEDIATION="$PROJECT_ROOT/.aai/REMEDIATION.prompt.md"
SKILL_TDD="$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
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

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$STATE_SCRIPT" ]] || log_fail "state CLI not found: $STATE_SCRIPT"
  [[ -f "$FLUSH_SCRIPT" ]] || log_fail "flush script not found: $FLUSH_SCRIPT"
  [[ -f "$PROTOCOL" ]] || log_fail "SUBAGENT_PROTOCOL.md not found: $PROTOCOL"
  [[ -f "$LOOP" ]] || log_fail "SKILL_LOOP.prompt.md not found: $LOOP"
  [[ -f "$ORCH" ]] || log_fail "ORCHESTRATION.prompt.md not found: $ORCH"
  for f in "$PLANNING" "$IMPLEMENTATION" "$VALIDATION" "$REMEDIATION" "$SKILL_TDD"; do
    [[ -f "$f" ]] || log_fail "role prompt not found: $f"
  done
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-token-capture-test.XXXXXX")"
}

NOW_UTC=""
capture_now() { NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; }

# --- TEST-001 (Spec-AC-01): parent-side decomposed-usage capture -------------

test_001_decomposed_capture_canon() {
  log_info "Test: SKILL_LOOP + SUBAGENT_PROTOCOL instruct parent-side decomposed-usage capture into existing flags (TEST-001)..."

  grep -qF 'harness-reported usage' "$LOOP" \
    || log_fail "TEST-001: SKILL_LOOP step 4 must instruct capturing harness-reported usage from the completed role's tool result"
  grep -qF 'SUBAGENT_PROTOCOL.md' "$LOOP" \
    || log_fail "TEST-001: SKILL_LOOP must point to SUBAGENT_PROTOCOL.md for the capture contract"

  grep -qF '## Harness-reported usage capture' "$PROTOCOL" \
    || log_fail "TEST-001: SUBAGENT_PROTOCOL.md must define a 'Harness-reported usage capture' section"
  grep -qF 'harness-level result visible to the dispatching parent' "$PROTOCOL" \
    || log_fail "TEST-001: SUBAGENT_PROTOCOL.md must state the D1 source-of-truth rule (dispatching parent, never subagent self-report)"
  grep -qF 'append-run --tokens-in N --tokens-out N' "$PROTOCOL" \
    || log_fail "TEST-001: SUBAGENT_PROTOCOL.md must map decomposed usage onto the existing append-run --tokens-in/--tokens-out flags (D2)"
  grep -qE 'log-tick[^\n]*--tokens-in N --tokens-out N' "$PROTOCOL" \
    || log_fail "TEST-001: SUBAGENT_PROTOCOL.md must map decomposed usage onto the existing log-tick --tokens-in/--tokens-out flags (D2)"

  log_pass "SKILL_LOOP + SUBAGENT_PROTOCOL decomposed-usage capture wiring present (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): usage_total_tokens= grammar, never split ---------

test_002_total_grammar_canon() {
  log_info "Test: SUBAGENT_PROTOCOL defines usage_total_tokens= grammar and prohibits splitting/relabeling totals (TEST-002)..."

  grep -qF 'usage_total_tokens=<N>' "$PROTOCOL" \
    || log_fail "TEST-002: SUBAGENT_PROTOCOL.md must define the usage_total_tokens=<N> note grammar (D3)"
  grep -qF 'NEVER split a total' "$PROTOCOL" \
    || log_fail "TEST-002: SUBAGENT_PROTOCOL.md must prohibit splitting an undecomposed total into in/out components"
  grep -qF 'NEVER relabel it as' "$PROTOCOL" \
    || log_fail "TEST-002: SUBAGENT_PROTOCOL.md must prohibit relabeling a total as tokens_in/tokens_out"
  grep -qF 'omit all usage flags' "$PROTOCOL" \
    || log_fail "TEST-002: SUBAGENT_PROTOCOL.md must retain the D4 omit rule for absent usage"
  grep -qF "I'll estimate the in/out split from the total" "$PROTOCOL" \
    || log_fail "TEST-002: SUBAGENT_PROTOCOL.md must carry the 'estimate the split' rationalization row"

  log_pass "usage_total_tokens= grammar + never-split/never-relabel prohibition present (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): subagent-mode append carve-out -------------------

test_003_role_carveout_canon() {
  log_info "Test: five role prompts carry the subagent-mode append carve-out; ORCHESTRATION appends with usage (TEST-003)..."

  local names=("PLANNING" "IMPLEMENTATION" "VALIDATION" "REMEDIATION" "SKILL_TDD")
  local files=("$PLANNING" "$IMPLEMENTATION" "$VALIDATION" "$REMEDIATION" "$SKILL_TDD")
  local i=0
  while [[ $i -lt ${#files[@]} ]]; do
    local f="${files[$i]}" n="${names[$i]}"
    grep -qE 'Subagent-mode carve-out.*SUBAGENT_PROTOCOL\.md' "$f" \
      || log_fail "TEST-003: $n.prompt.md must carry a subagent-mode append carve-out referencing SUBAGENT_PROTOCOL.md (D5)"
    i=$((i + 1))
  done

  grep -qF 'harness-reported usage per SUBAGENT_PROTOCOL.md' "$ORCH" \
    || log_fail "TEST-003: ORCHESTRATION.prompt.md must instruct appending the completed role's run with harness-reported usage per SUBAGENT_PROTOCOL.md"
  grep -qF 'append-run' "$ORCH" \
    || log_fail "TEST-003: ORCHESTRATION.prompt.md must reference append-run for the merge-time write"

  log_pass "Subagent-mode append carve-out present on all five role prompts; ORCHESTRATION appends with usage (TEST-003)"
}

# --- TEST-004 (Spec-AC-04): run-budget tally counts observed totals ---------

test_004_run_budget_tally_canon() {
  log_info "Test: SKILL_LOOP condition f counts observed undecomposed totals; never-fabricate no-op clause retained (TEST-004)..."

  grep -qF 'undecomposed totals observed at subagent completions' "$LOOP" \
    || log_fail "TEST-004: SKILL_LOOP stop condition f must count harness-reported undecomposed totals observed this run (D6)"
  grep -qF 'no-op (never fabricate usage)' "$LOOP" \
    || log_fail "TEST-004: SKILL_LOOP must retain the never-fabricate no-op clause verbatim when no usage is recorded"

  log_pass "Run-budget tally counts observed undecomposed totals; no-op clause retained verbatim (TEST-004)"
}

# --- TEST-005 (Spec-AC-02, seam): note round-trips append-run -> STATE -> flush -> METRICS ----

write_state_fixture_005() {
  local f="$1"
  cat > "$f" <<'YAML'
# docs/ai/STATE.yaml - AAI runtime state (managed by orchestration; humans need not edit)
#
# CANONICAL SCHEMA / INVARIANTS (authoritative; see .aai/SKILL_CHECK_STATE.prompt.md)
#   project_status:            active | paused
#   last_validation.status:    pass | fail | not_run
#   updated_at_utc:            ISO 8601 UTC
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-9001
  primary_path: docs/issues/CHANGE-9001-fixture.md
active_work_items:
  - ref_id: CHANGE-9001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-9001-fixture.md
    spec_path: docs/specs/SPEC-9001-fixture.md
implementation_strategy:
  selected: loop
  source: docs/specs/SPEC-9001-fixture.md
  rationale: >-
    Fixture strategy rationale.
worktree:
  recommendation: not_needed
  user_decision: waived
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: false
  status: not_run
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-17T11:00:00Z
  ref_id: CHANGE-9001
  evidence_paths:
    - docs/ai/reports/validation-fixture.md
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: false
orchestration:
  mode: single
  k: 1
tdd_cycle:
  status: IDLE
  test_id: null
  spec_path: null
  test_path: null
  evidence:
    red: null
    green: null
    refactor: null
metrics:
  work_items:
    CHANGE-9001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs: []

updated_at_utc: 2026-07-17T11:00:00Z
YAML
}

write_pricing_005() {
  cat > "$1" <<'YAML'
schema_version: 2
lookup_rules:
  order:
    - exact-match
    - unknown-fallback
models:
  claude-test:
    input_usd_per_m: 3.00
    output_usd_per_m: 15.00
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
}

test_005_seam_total_note_roundtrip() {
  log_info "Test: append-run usage_total_tokens= note round-trips STATE -> METRICS.jsonl, tokens null, warning fires (TEST-005)..."

  local d="$TEST_DIR/t005"
  mkdir -p "$d/docs/ai"
  local s="$d/docs/ai/STATE.yaml"
  local m="$d/docs/ai/METRICS.jsonl"
  local tk="$d/docs/ai/LOOP_TICKS.jsonl"
  local ev="$d/docs/ai/EVENTS.jsonl"
  local pr="$d/PRICING.yaml"
  write_state_fixture_005 "$s"
  write_pricing_005 "$pr"
  printf '# ledger comment header\n' > "$m"
  : > "$tk"
  : > "$ev"
  capture_now

  local note="usage_total_tokens=262134 (harness total; in/out not exposed)"
  local ar_log="$d/append-run.log"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" append-run \
    --ref CHANGE-9001 --role Implementation --model claude-test --started "$NOW_UTC" \
    --note "$note" > "$ar_log" 2>&1) \
    || log_fail "TEST-005: append-run with note-only usage must exit 0: $(cat "$ar_log")"

  grep -qF "usage_total_tokens=262134" "$s" \
    || log_fail "TEST-005: STATE agent_runs note must carry usage_total_tokens=262134 verbatim"
  sed -n '/^    CHANGE-9001:$/,$p' "$s" | grep -qE '^ {10}tokens_in: null$' \
    || log_fail "TEST-005: tokens_in must stay null for an undecomposed-total run (never split)"
  sed -n '/^    CHANGE-9001:$/,$p' "$s" | grep -qE '^ {10}tokens_out: null$' \
    || log_fail "TEST-005: tokens_out must stay null for an undecomposed-total run (never split)"

  local flush_log="$d/flush.log"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$s" --metrics "$m" --ticks "$tk" --pricing "$pr" --events "$ev" \
    --now "2026-07-17T12:00:00Z" > "$flush_log" 2>&1) \
    || log_fail "TEST-005: flush must exit 0: $(cat "$flush_log")"

  grep -qF "usage_total_tokens=262134" "$m" \
    || log_fail "TEST-005: flushed METRICS.jsonl line must carry the note verbatim: $(cat "$m")"
  grep -q '"tokens_in":null' "$m" \
    || log_fail "TEST-005: flushed METRICS.jsonl run must keep tokens_in null"
  grep -qE 'cost unattributable' "$flush_log" \
    || log_fail "TEST-005: flush must still emit the 'cost unattributable' warning for an undecomposed total (never silenced): $(cat "$flush_log")"

  log_pass "usage_total_tokens= note round-trips verbatim, tokens stay null, warning fires (TEST-005)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  test_001_decomposed_capture_canon
  test_002_total_grammar_canon
  test_003_role_carveout_canon
  test_004_run_budget_tally_canon
  test_005_seam_total_note_roundtrip

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
