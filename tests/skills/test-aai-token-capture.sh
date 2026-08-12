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
#   - TEST-005 (Spec-AC-02, seam / SPEC-0085-spec-token-capture-canary spec
#     TEST-004): append-run --note "usage_total_tokens=..." (no token flags)
#     round-trips verbatim through STATE.yaml into a flushed METRICS.jsonl
#     line, tokens stay null, and the run now gets an INFO line (reclassified
#     from the old generic WARNING, token-capture-canary Spec-AC-01); a
#     sibling run with no note/no tokens at all still gets the capture-missing
#     WARNING (never silenced, never conflated with the honest undecomposed
#     case).
#
# token-capture-canary (SPEC-0085-spec-token-capture-canary.md) adds:
#   - test_006_log_tick_duration_warning (spec TEST-005, Spec-AC-02):
#     state.mjs log-tick with started==ended (duration 0) emits a stderr
#     WARNING containing "duration"; exit 0; tick line still appended.
#   - test_007_log_tick_harness_warning (spec TEST-006, Spec-AC-02):
#     state.mjs log-tick with --harness omitted emits a stderr WARNING
#     containing "harness"; exit 0; harness_version stays "unknown".
#   - test_008_log_tick_negative_control (spec TEST-007, Spec-AC-02):
#     a healthy tick (nonzero duration AND --harness present) emits NO
#     warning (non-tautology guard).
#   - test_009_mandatory_usage_note_wording (spec TEST-008, Spec-AC-03):
#     SUBAGENT_PROTOCOL.md "Merge protocol" + SKILL_LOOP.prompt.md step 4
#     carry MANDATORY/non-optional usage_total_tokens=<N> wording.
#   - test_010_d3_prose_reclassified (spec TEST-009, Spec-AC-03):
#     SUBAGENT_PROTOCOL.md D3 prose no longer claims the flush WARNING fires
#     for an undecomposed total (reflects the INFO reclassification).
#
# ALL fixtures for TEST-005..010 are scratch temp-dir files (--state/
# --metrics/--ticks/--pricing/--events overrides); the real gitignored
# runtime files are NEVER touched. bash 3.2 compatible (no ${var^^}, no
# declare -A).
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
ROLE_COMMON="$PROJECT_ROOT/.aai/ROLE_COMMON.md"

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
  [[ -f "$ROLE_COMMON" ]] || log_fail "ROLE_COMMON.md not found: $ROLE_COMMON"
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

# --- TEST-003 (Spec-AC-03): subagent-mode append carve-out, single-sourced ---
# (prompt-dedup-canonical-includes TEST-005/Spec-AC-03: the D5 carve-out BODY
# lives in exactly ONE file, .aai/ROLE_COMMON.md; each of the five role
# prompts carries a pointer naming it + its own --role value, never the
# literal "Subagent-mode carve-out" phrase itself.)

test_003_role_carveout_canon() {
  log_info "Test: D5 carve-out body single-sourced in ROLE_COMMON.md; five role prompts carry a pointer + role value (not the inline body); ORCHESTRATION appends with usage (TEST-003)..."

  grep -qE 'Subagent-mode carve-out.*SUBAGENT_PROTOCOL\.md' "$ROLE_COMMON" \
    || log_fail "TEST-003: .aai/ROLE_COMMON.md must carry the canonical subagent-mode carve-out body referencing SUBAGENT_PROTOCOL.md (D5)"

  local names=("PLANNING" "IMPLEMENTATION" "VALIDATION" "REMEDIATION" "SKILL_TDD")
  local files=("$PLANNING" "$IMPLEMENTATION" "$VALIDATION" "$REMEDIATION" "$SKILL_TDD")
  local roles=("Planning" "Implementation" "Validation" "Remediation" "TDD Implementation")
  local i=0
  while [[ $i -lt ${#files[@]} ]]; do
    local f="${files[$i]}" n="${names[$i]}" r="${roles[$i]}"
    grep -qF "ROLE_COMMON.md" "$f" \
      || log_fail "TEST-003: $n.prompt.md must carry a pointer naming .aai/ROLE_COMMON.md"
    # The role value must sit ON the pointer line itself — a bare occurrence
    # elsewhere in the prompt must not satisfy this check (PR #159 bot review).
    # Both unquoted and quoted forms are canonical: ROLE_COMMON.md itself
    # mandates quoting when the role value contains a space (TDD Implementation).
    { grep -F "ROLE_COMMON.md" "$f" | grep -qF "(role: $r)"; } \
      || { grep -F "ROLE_COMMON.md" "$f" | grep -qF "(role: \"$r\")"; } \
      || log_fail "TEST-003: $n.prompt.md pointer line must name its own --role value as '(role: $r)'"
    grep -qF 'Subagent-mode carve-out' "$f" \
      && log_fail "TEST-003: $n.prompt.md must NOT re-inline the 'Subagent-mode carve-out' body (it must live only in ROLE_COMMON.md)"
    i=$((i + 1))
  done

  grep -qF 'harness-reported usage per SUBAGENT_PROTOCOL.md' "$ORCH" \
    || log_fail "TEST-003: ORCHESTRATION.prompt.md must instruct appending the completed role's run with harness-reported usage per SUBAGENT_PROTOCOL.md"
  grep -qF 'append-run' "$ORCH" \
    || log_fail "TEST-003: ORCHESTRATION.prompt.md must reference append-run for the merge-time write"

  log_pass "D5 carve-out single-sourced in ROLE_COMMON.md; all five role prompts point to it with their --role value; ORCHESTRATION appends with usage (TEST-003)"
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
  log_info "Test: SEAM-1 end-to-end -- append-run usage_total_tokens= note round-trips STATE -> METRICS.jsonl, tokens null, INFO fires (reclassified from WARNING); a sibling no-note/no-tokens run gets the capture-missing WARNING (TEST-005 legacy id / spec TEST-004)..."

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

  # Sibling run: nothing exposed at all (no tokens, no note) -> capture-missing.
  local ar2_log="$d/append-run2.log"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" append-run \
    --ref CHANGE-9001 --role Planning --model claude-test --started "$NOW_UTC" \
    > "$ar2_log" 2>&1) \
    || log_fail "TEST-005: append-run with no usage signal at all must exit 0: $(cat "$ar2_log")"

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
  grep -qE '^INFO CHANGE-9001 run Implementation .*undecomposed total 262134 observed; cost unattributable by design' "$flush_log" \
    || log_fail "TEST-005 (spec TEST-004): flush must emit an INFO line for the undecomposed-note run (reclassified from WARNING, never silenced): $(cat "$flush_log")"
  grep -qE '^WARNING CHANGE-9001 run Implementation' "$flush_log" \
    && log_fail "TEST-005 (spec TEST-004): the undecomposed-note run must NOT also emit the generic capture-missing WARNING: $(cat "$flush_log")"
  grep -qE '^WARNING CHANGE-9001 run Planning .*cost unattributable' "$flush_log" \
    || log_fail "TEST-005 (spec TEST-004): the sibling no-note/no-tokens run must still get the capture-missing WARNING: $(cat "$flush_log")"

  log_pass "SEAM-1: usage_total_tokens= note round-trips verbatim -> INFO (reclassified); no-signal sibling run -> capture-missing WARNING (TEST-005 legacy id / spec TEST-004)"
}

# --- log-tick duration-0 / missing-harness stderr WARNINGs (Spec-AC-02) ------

test_006_log_tick_duration_warning() {
  log_info "Test: log-tick with started==ended (duration 0) emits a stderr WARNING containing 'duration'; exit 0; tick still appended (spec TEST-005)..."
  local s="$TEST_DIR/t006-state.yaml" tk="$TEST_DIR/t006-ticks.jsonl"
  write_state_fixture_005 "$s"
  local i out err duration=""
  for i in 1 2 3 4 5; do
    out="$TEST_DIR/t006-$i.out"
    err="$TEST_DIR/t006-$i.err"
    : > "$tk"
    capture_now
    (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
        --tick 1 --role Implementation --scope CHANGE-9001 --started "$NOW_UTC" --harness 2.1.211 \
        > "$out" 2> "$err") \
      || log_fail "TEST-006 (spec TEST-005): log-tick must exit 0 even when duration collapses to 0 (attempt $i): $(cat "$err")"
    duration="$(node -e '
      const lines = require("fs").readFileSync(process.argv[1], "utf8").trim().split("\n");
      console.log(JSON.parse(lines[lines.length - 1]).duration_seconds);
    ' "$tk")"
    [[ "$duration" == "0" ]] && break
  done
  [[ "$duration" == "0" ]] || log_fail "TEST-006 (spec TEST-005): could not reproduce duration_seconds 0 in 5 attempts (env too slow?) last=$duration"
  grep -qi 'WARNING' "$err" || log_fail "TEST-006 (spec TEST-005): stderr must carry a WARNING when duration_seconds is 0: $(cat "$err")"
  grep -qi 'duration' "$err" || log_fail "TEST-006 (spec TEST-005): the WARNING must contain the substring 'duration': $(cat "$err")"
  [[ -s "$tk" ]] || log_fail "TEST-006 (spec TEST-005): tick line must still be appended (warn, not block)"
  log_pass "log-tick duration-0 WARNING fires on stderr, exit 0, tick still appended (spec TEST-005)"
}

test_007_log_tick_harness_warning() {
  log_info "Test: log-tick with --harness omitted emits a stderr WARNING containing 'harness'; harness_version stays 'unknown' (spec TEST-006)..."
  local s="$TEST_DIR/t007-state.yaml" tk="$TEST_DIR/t007-ticks.jsonl"
  write_state_fixture_005 "$s"
  : > "$tk"
  local out="$TEST_DIR/t007.out" err="$TEST_DIR/t007.err"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 2 --role Validation --scope CHANGE-9001 --started 2026-07-15T10:00:00Z \
      > "$out" 2> "$err") \
    || log_fail "TEST-007 (spec TEST-006): log-tick must exit 0 even without --harness: $(cat "$err")"
  grep -qi 'WARNING' "$err" || log_fail "TEST-007 (spec TEST-006): stderr must carry a WARNING when --harness is omitted: $(cat "$err")"
  grep -qi 'harness' "$err" || log_fail "TEST-007 (spec TEST-006): the WARNING must contain the substring 'harness': $(cat "$err")"
  grep -qF '"harness_version":"unknown"' "$tk" \
    || log_fail "TEST-007 (spec TEST-006): tick line must record harness_version unknown when --harness omitted: $(cat "$tk")"
  log_pass "log-tick missing-harness WARNING fires on stderr, exit 0, harness_version stays unknown (spec TEST-006)"
}

test_008_log_tick_negative_control() {
  log_info "Test: valid nonzero duration AND --harness present -> NO duration/harness WARNING (non-tautology negative control, spec TEST-007)..."
  local s="$TEST_DIR/t008-state.yaml" tk="$TEST_DIR/t008-ticks.jsonl"
  write_state_fixture_005 "$s"
  : > "$tk"
  local out="$TEST_DIR/t008.out" err="$TEST_DIR/t008.err"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 5 --role Implementation --scope CHANGE-9001 --started 2026-07-15T10:00:00Z --harness 2.1.211 \
      > "$out" 2> "$err") \
    || log_fail "TEST-008 (spec TEST-007): log-tick must exit 0: $(cat "$err")"
  [[ ! -s "$err" ]] || log_fail "TEST-008 (spec TEST-007): no WARNING may fire on a healthy tick (non-tautology guard): $(cat "$err")"
  log_pass "no duration/harness WARNING on a healthy tick -- non-tautology negative control holds (spec TEST-007)"
}

# --- SUBAGENT_PROTOCOL / SKILL_LOOP MANDATORY usage-note wording (Spec-AC-03) --

test_009_mandatory_usage_note_wording() {
  log_info "Test: SUBAGENT_PROTOCOL Merge protocol + SKILL_LOOP step 4 carry MANDATORY usage_total_tokens=<N> wording (spec TEST-008)..."

  sed -n '/^## Merge protocol/,/^## /p' "$PROTOCOL" | grep -qE 'usage_total_tokens=<N>.*MANDATORY|MANDATORY.*usage_total_tokens=<N>' \
    || log_fail "TEST-009 (spec TEST-008): SUBAGENT_PROTOCOL.md 'Merge protocol' section must make usage_total_tokens=<N> MANDATORY, not optional"

  sed -n '/^  4\. RUN DISPATCHED ROLE/,/^  5\. /p' "$LOOP" | grep -qE 'usage_total_tokens=<N>.*MANDATORY|MANDATORY.*usage_total_tokens=<N>' \
    || log_fail "TEST-009 (spec TEST-008): SKILL_LOOP.prompt.md step 4 must make usage_total_tokens=<N> MANDATORY, not optional"

  log_pass "MANDATORY usage_total_tokens=<N> wording present in Merge protocol + SKILL_LOOP step 4 (spec TEST-008)"
}

test_010_d3_prose_reclassified() {
  log_info "Test: SUBAGENT_PROTOCOL D3 prose no longer claims the flush WARNING fires for an undecomposed total (spec TEST-009)..."

  grep -qF 'The flush "cost unattributable" warning correctly continues to fire for such runs (D3)' "$PROTOCOL" \
    && log_fail "TEST-010 (spec TEST-009): SUBAGENT_PROTOCOL.md must no longer claim the flush WARNING fires for an undecomposed total"
  grep -qE 'undecomposed-note.*INFO|INFO line.*undecomposed' "$PROTOCOL" \
    || log_fail "TEST-010 (spec TEST-009): SUBAGENT_PROTOCOL.md must state the flush now emits an INFO line for an undecomposed total"

  log_pass "SUBAGENT_PROTOCOL D3 prose reclassified to INFO (spec TEST-009)"
}

# --- validation-cost-calibration (Spec-AC-04) -------------------------------

# --- TEST-011 (spec TEST-007/Spec-AC-04): requested/actual model extractors -

test_011_model_marker_extractors() {
  log_info "Test: extractRequestedModel/extractActualModel/modelOverrideDropped — plain id, bracketed context-window id, prefixed key, empty/malformed value, differ/equal (spec TEST-007)..."
  cat > "$TEST_DIR/t011.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const lib = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/lib/usage-note.mjs')).href);
const { extractRequestedModel, extractActualModel, modelOverrideDropped } = lib;

// Plain id.
assert.strictEqual(extractRequestedModel('requested_model=claude-sonnet-5'), 'claude-sonnet-5');
assert.strictEqual(extractActualModel('actual_model=claude-haiku-4-5'), 'claude-haiku-4-5');

// Bracketed context-window suffix (a REAL recorded model id).
assert.strictEqual(extractRequestedModel('requested_model=claude-opus-4-8[1m]'), 'claude-opus-4-8[1m]');
assert.strictEqual(extractActualModel('actual_model=claude-opus-4-8[1m]'), 'claude-opus-4-8[1m]');

// Boundary discipline: quoted / parenthesized forms still match.
assert.strictEqual(extractRequestedModel('note="requested_model=claude-sonnet-5"'), 'claude-sonnet-5');
assert.strictEqual(extractRequestedModel('(requested_model=claude-sonnet-5)'), 'claude-sonnet-5');

// Prefixed key must never match (same discipline as not_usage_total_tokens=).
assert.strictEqual(extractRequestedModel('not_requested_model=claude-sonnet-5'), null);
assert.strictEqual(extractActualModel('not_actual_model=claude-sonnet-5'), null);

// Empty value never matches.
assert.strictEqual(extractRequestedModel('requested_model='), null);
assert.strictEqual(extractRequestedModel('requested_model= trailing'), null);

// Malformed value (id cannot start with a disallowed character) never matches.
assert.strictEqual(extractRequestedModel('requested_model=!badstart'), null);

// Non-string / no marker at all -> null, never throws.
assert.strictEqual(extractRequestedModel(null), null);
assert.strictEqual(extractRequestedModel(undefined), null);
assert.strictEqual(extractRequestedModel('usage_total_tokens=123'), null);

// Sentence-final marker (review-20260812T083704Z CQ-1): a trailing `.` is a
// right-boundary delimiter, NOT part of the id, even though the note itself
// ends right there -- plain form, marker alone.
assert.strictEqual(
  extractActualModel('actual_model=claude-opus-4-8.'),
  'claude-opus-4-8',
  'sentence-final period must not be captured into the id (CQ-1 plain)'
);
// Sentence-final marker with the OTHER marker mid-note: requested_model
// sits mid-string, actual_model is the sentence-final token carrying the
// period. Pre-fix this made modelOverrideDropped() report TRUE for an
// override that took (the exact false-positive CQ-1 names) because the
// captured actual id was 'claude-opus-4-8.' != 'claude-opus-4-8'.
assert.strictEqual(
  extractActualModel('requested_model=claude-opus-4-8 actual_model=claude-opus-4-8.'),
  'claude-opus-4-8',
  'sentence-final period must not be captured when the other marker is mid-note (CQ-1)'
);
assert.strictEqual(
  modelOverrideDropped('requested_model=claude-opus-4-8 actual_model=claude-opus-4-8.'),
  false,
  'CQ-1 false positive: an EQUAL pair must not report a dropped override just because the note ends in a period'
);
// Regression guard: the bracketed context-window suffix must stay immune --
// the suffix group already ends the id before the trailing period.
assert.strictEqual(
  extractRequestedModel('requested_model=claude-opus-4-8[1m]. actual_model=claude-opus-4-8[1m]'),
  'claude-opus-4-8[1m]',
  'bracketed [1m] suffix must still parse after the CQ-1 boundary fix'
);
assert.strictEqual(
  modelOverrideDropped('requested_model=claude-opus-4-8[1m]. actual_model=claude-opus-4-8[1m]'),
  false,
  'bracketed sentence-final pair must not false-positive either'
);

// modelOverrideDropped: true ONLY when both present and DIFFER.
assert.strictEqual(
  modelOverrideDropped('requested_model=claude-opus-4-8 actual_model=claude-haiku-4-5'),
  true,
  'differing pair must report the override dropped'
);
// Equal pair is POSITIVE evidence the override took -- never "dropped".
assert.strictEqual(
  modelOverrideDropped('requested_model=claude-opus-4-8 actual_model=claude-opus-4-8'),
  false,
  'equal pair must NOT report a dropped override'
);
// Only one marker present -> false (absence must not be readable as either outcome).
assert.strictEqual(modelOverrideDropped('requested_model=claude-opus-4-8'), false);
assert.strictEqual(modelOverrideDropped('actual_model=claude-opus-4-8'), false);
assert.strictEqual(modelOverrideDropped(''), false);
assert.strictEqual(modelOverrideDropped(null), false);

console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t011.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t011.log" 2>&1 \
    || log_fail "TEST-011 (spec TEST-007): model marker extractor cases failed: $(cat "$TEST_DIR/t011.log")"
  log_pass "extractRequestedModel/extractActualModel/modelOverrideDropped: plain/bracketed/boundary/prefixed/empty/malformed/differ/equal (TEST-011/spec TEST-007)"
}

# --- TEST-012 (spec TEST-009/Spec-AC-04, SEAM-1 integration): note with all
# three markers survives append-run -> STATE -> metrics-flush -> METRICS.jsonl
# verbatim; extractUsageTotal (existing) and the new extractors both still
# resolve correctly out of the flushed line -----------------------------------

test_012_model_marker_seam_roundtrip() {
  log_info "Test: SEAM -- a note carrying requested_model, actual_model AND usage_total_tokens survives append-run + metrics-flush into METRICS.jsonl verbatim; all three extractors resolve from the flushed line (spec TEST-009)..."
  local d="$TEST_DIR/t012"
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

  local note="requested_model=claude-opus-4-8 actual_model=claude-opus-4-8[1m] usage_total_tokens=48213 (harness total; in/out not exposed)"
  local ar_log="$d/append-run.log"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" append-run \
    --ref CHANGE-9001 --role Validation --model claude-opus-4-8 --started "$NOW_UTC" \
    --note "$note" > "$ar_log" 2>&1) \
    || log_fail "TEST-012 (spec TEST-009): append-run with model+usage note must exit 0: $(cat "$ar_log")"

  grep -qF "requested_model=claude-opus-4-8" "$s" \
    || log_fail "TEST-012 (spec TEST-009): STATE agent_runs note must carry requested_model verbatim"
  grep -qF "actual_model=claude-opus-4-8[1m]" "$s" \
    || log_fail "TEST-012 (spec TEST-009): STATE agent_runs note must carry actual_model verbatim"

  local flush_log="$d/flush.log"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$s" --metrics "$m" --ticks "$tk" --pricing "$pr" --events "$ev" \
    --now "2026-07-17T12:00:00Z" > "$flush_log" 2>&1) \
    || log_fail "TEST-012 (spec TEST-009): flush must exit 0: $(cat "$flush_log")"

  grep -qF "requested_model=claude-opus-4-8" "$m" \
    || log_fail "TEST-012 (spec TEST-009): flushed METRICS.jsonl line must carry requested_model verbatim"
  grep -qF "actual_model=claude-opus-4-8[1m]" "$m" \
    || log_fail "TEST-012 (spec TEST-009): flushed METRICS.jsonl line must carry actual_model verbatim"
  grep -qF "usage_total_tokens=48213" "$m" \
    || log_fail "TEST-012 (spec TEST-009): flushed METRICS.jsonl line must still carry the usage total verbatim"

  local flushed_note
  flushed_note="$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(l => l.trim() && !l.startsWith("#"));
    const o = JSON.parse(lines[lines.length - 1]);
    process.stdout.write(o.agent_runs[0].note);
  ' "$m")"

  node -e '
    import(process.argv[1] + "/.aai/scripts/lib/usage-note.mjs").then(lib => {
      const note = process.argv[2];
      const total = lib.extractUsageTotal(note);
      const req = lib.extractRequestedModel(note);
      const act = lib.extractActualModel(note);
      if (total !== 48213) { console.error("extractUsageTotal mismatch: " + total); process.exit(1); }
      if (req !== "claude-opus-4-8") { console.error("extractRequestedModel mismatch: " + req); process.exit(1); }
      if (act !== "claude-opus-4-8[1m]") { console.error("extractActualModel mismatch: " + act); process.exit(1); }
    });
  ' "$PROJECT_ROOT" "$flushed_note" \
    || log_fail "TEST-012 (spec TEST-009): extractUsageTotal/extractRequestedModel/extractActualModel must all resolve from the flushed note"

  log_pass "SEAM-1: requested/actual model markers + usage total survive append-run -> flush -> METRICS.jsonl verbatim, all extractors resolve (TEST-012/spec TEST-009)"
}

# --- TEST-013 (spec TEST-010/Spec-AC-04): SUBAGENT_PROTOCOL usage-capture ----
# prose pin: model_id records the GRANTED model; both markers recorded
# whenever an override was requested; validator-independence claims cite
# actual_model.

test_013_subagent_protocol_model_marker_prose() {
  log_info "Test: SUBAGENT_PROTOCOL Harness-reported usage capture section states model_id==granted, both markers recorded together, independence claims cite actual_model (spec TEST-010)..."
  local block
  block="$(awk '/^## Harness-reported usage capture/{f=1} /^## /{if (f && !/^## Harness-reported usage capture/) f=0} f' "$PROTOCOL")"
  [[ -n "$block" ]] || log_fail "TEST-013 (spec TEST-010): Harness-reported usage capture section body not found"

  echo "$block" | grep -qF 'requested_model=' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must name the requested_model= marker"
  echo "$block" | grep -qF 'actual_model=' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must name the actual_model= marker"
  echo "$block" | grep -qiF 'GRANTED model' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must state model_id records the GRANTED model"
  echo "$block" | grep -qiF 'both markers' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must state both markers are recorded whenever an override was requested"
  # Sharper than a bare 'actual_model' grep (subsumed by the earlier
  # 'actual_model=' pin, review-20260812T083704Z CQ-2, mutation-proved: the
  # old pin stayed GREEN after deleting the whole "Any claim of validator
  # independence ... MUST cite actual_model" sentence). Two phrases unique to
  # that sentence -- "must cite" and "claim of validator independence" (the
  # word "independence" alone recurs elsewhere in the block, e.g.
  # "independence that never happened", so it cannot anchor alone).
  echo "$block" | grep -qiF 'must cite' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must state validator-independence claims MUST cite actual_model"
  echo "$block" | grep -qiF 'claim of validator independence' \
    || log_fail "TEST-013 (spec TEST-010): usage-capture section must name the validator-independence claim actual_model must be cited for"

  log_pass "SUBAGENT_PROTOCOL usage-capture prose: model_id==granted, both-markers-together, independence-cites-actual_model (TEST-013/spec TEST-010)"
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
  test_006_log_tick_duration_warning
  test_007_log_tick_harness_warning
  test_008_log_tick_negative_control
  test_009_mandatory_usage_note_wording
  test_010_d3_prose_reclassified
  test_011_model_marker_extractors
  test_012_model_marker_seam_roundtrip
  test_013_subagent_protocol_model_marker_prose

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
