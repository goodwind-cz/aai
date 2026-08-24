#!/usr/bin/env bash
#
# Test: aai-r-guard (R-GUARD runtime enforcement / SPEC-0113).
#
# Pins the ORCHESTRATOR WIRING seam for R-GUARD Stage 1: the dispatch templates
# instruct setting AAI_ROLE=subagent in every spawned subagent's environment, so
# state.mjs (which refuses STATE mutations under that marker, exit 3) actually
# fires in real runs — and instruct the orchestrator to keep the marker UNSET
# for its own writes. Also a live-seam integration pin: the prompt-declared
# marker really makes state.mjs refuse (prompt claim -> real CLI behavior).
#
# The Stage-1 CLI refusal (byte-identity, allowed paths, exit-code ordering)
# lives in tests/skills/test-aai-state.sh; the Stage-2/3 flush WARNs live in
# tests/skills/test-aai-metrics.sh. This suite is the wiring/pin layer.
#
# ALL fixtures are scratch temp dirs (--state override); the real runtime
# docs/ai/STATE.yaml is NEVER read or written. bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -uo pipefail

TEST_NAME="aai-r-guard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"
SUBAGENT_PROTOCOL="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
ORCH_PARALLEL="$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md"
SUBAGENT_CONTRACT="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
ORCH_SERIAL="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
CHECK_ROLE_OUTPUT="$PROJECT_ROOT/.aai/scripts/check-role-output.mjs"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

TEST_DIR=""
FAILED=0

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
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$STATE_CLI" ]] || log_skip "state.mjs not found: $STATE_CLI"
  [[ -f "$SUBAGENT_PROTOCOL" ]] || { log_fail "SUBAGENT_PROTOCOL missing: $SUBAGENT_PROTOCOL"; return; }
  [[ -f "$ORCH_PARALLEL" ]] || { log_fail "ORCHESTRATION_PARALLEL missing: $ORCH_PARALLEL"; return; }
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-r-guard-test.XXXXXX")"
}

# --- TEST-RG-PIN-01: SUBAGENT_PROTOCOL carries the AAI_ROLE=subagent wiring ----

test_pin_subagent_protocol() {
  log_info "Test: SUBAGENT_PROTOCOL.md instructs setting AAI_ROLE=subagent + keeping it unset for the orchestrator (TEST-RG-PIN-01)..."
  grep -qF 'AAI_ROLE=subagent' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-01: no AAI_ROLE=subagent wiring in $SUBAGENT_PROTOCOL"
  grep -qF 'SPEC-0113' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-01: SUBAGENT_PROTOCOL does not cite SPEC-0113"
  grep -qiE 'unset|non-`?subagent`?|not carry|MUST NOT carry' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-01: SUBAGENT_PROTOCOL does not tell the orchestrator to keep the marker unset for its own writes"
  # Honesty posture must ride the wiring (SPEC-0113 RR-1, never softened).
  grep -qiF 'not a security boundary' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-01: SUBAGENT_PROTOCOL must keep the 'not a security boundary' honesty"
  [[ "$FAILED" == 0 ]] && log_pass "SUBAGENT_PROTOCOL carries the AAI_ROLE=subagent wiring + honesty (TEST-RG-PIN-01)" || true
}

# --- TEST-RG-PIN-02: ORCHESTRATION_PARALLEL carries the marker wiring ----------

test_pin_orchestration_parallel() {
  log_info "Test: ORCHESTRATION_PARALLEL.prompt.md sets AAI_ROLE=subagent on dispatch and keeps it unset for orchestrator writes (TEST-RG-PIN-02)..."
  grep -qF 'AAI_ROLE=subagent' "$ORCH_PARALLEL" \
    || log_fail "TEST-RG-PIN-02: no AAI_ROLE=subagent wiring in $ORCH_PARALLEL"
  grep -qiE 'UNSET|keep it unset' "$ORCH_PARALLEL" \
    || log_fail "TEST-RG-PIN-02: ORCHESTRATION_PARALLEL does not instruct keeping the marker unset for the orchestrator's own writes"
  [[ "$FAILED" == 0 ]] && log_pass "ORCHESTRATION_PARALLEL sets the marker on dispatch, unset for own writes (TEST-RG-PIN-02)" || true
}

# --- TEST-RG-PIN-03: live seam — the marker really makes state.mjs refuse ------
#
# Ties the prompt-declared string to the real CLI: set AAI_ROLE=subagent (exactly
# as the wiring instructs) and run a STATE mutator against a scratch fixture ->
# exit 3, nothing written; then the SAME command with the marker unset succeeds.

test_seam_marker_refuses() {
  log_info "Test [SEAM]: the wired AAI_ROLE=subagent marker makes a real state.mjs mutation refuse (exit 3); unset succeeds (TEST-RG-PIN-03)..."
  local s="$TEST_DIR/seam-state.yaml"
  cat > "$s" <<'YAML'
project_status: active
current_focus:
  type: none
  ref_id: null
  primary_path: null
implementation_strategy:
  selected: undecided
  source: null
  rationale: null
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  cp "$s" "$TEST_DIR/seam-snapshot.yaml"

  local ec=0
  ( cd "$PROJECT_ROOT" && AAI_ROLE=subagent node .aai/scripts/state.mjs --state "$s" \
      set-strategy --selected tdd > "$TEST_DIR/seam-refuse.log" 2>&1 ) || ec=$?
  [[ "$ec" == 3 ]] || { log_fail "TEST-RG-PIN-03: marker set must refuse with exit 3 (got $ec): $(cat "$TEST_DIR/seam-refuse.log")"; return; }
  cmp -s "$s" "$TEST_DIR/seam-snapshot.yaml" || { log_fail "TEST-RG-PIN-03: refusal must leave STATE byte-identical"; return; }
  grep -qi 'single-writer' "$TEST_DIR/seam-refuse.log" \
    || { log_fail "TEST-RG-PIN-03: refusal message must name the single-writer rule"; return; }

  ec=0
  ( cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" \
      set-strategy --selected tdd > "$TEST_DIR/seam-ok.log" 2>&1 ) || ec=$?
  [[ "$ec" == 0 ]] || { log_fail "TEST-RG-PIN-03: marker unset must succeed (got $ec): $(cat "$TEST_DIR/seam-ok.log")"; return; }
  grep -qE '^  selected: tdd$' "$s" || { log_fail "TEST-RG-PIN-03: unset write must actually apply"; return; }
  log_pass "SEAM: wired marker -> state.mjs refuses (exit 3, no write); unset -> writes (TEST-RG-PIN-03)"
}

# --- TEST-RG-PIN-04: serial ORCHESTRATION relays the ENV row -------------------
#
# single-writer-canon-contradiction D1: being DISPATCHED decides who writes
# STATE, not which pipeline dispatched you. The serial dispatcher must relay
# the same AAI_ROLE=subagent arming line the parallel one already carries
# (TEST-RG-PIN-02), keep it unset for its own writes, and name running the
# returned state_update_commands — while staying inside the thin-wrapper
# ceiling (TEST-011, 45 lines).

test_pin_orchestration_serial() {
  log_info "Test: serial ORCHESTRATION.prompt.md arms AAI_ROLE=subagent, keeps it unset for its own writes, names state_update_commands, stays <=45 lines (TEST-RG-PIN-04)..."
  [[ -f "$ORCH_SERIAL" ]] || { log_fail "TEST-RG-PIN-04: ORCHESTRATION.prompt.md missing: $ORCH_SERIAL"; return; }
  grep -qF 'AAI_ROLE=subagent' "$ORCH_SERIAL" \
    || log_fail "TEST-RG-PIN-04: no AAI_ROLE=subagent wiring in $ORCH_SERIAL"
  grep -qiE 'unset|non-`?subagent`?|not carry|MUST NOT carry' "$ORCH_SERIAL" \
    || log_fail "TEST-RG-PIN-04: ORCHESTRATION.prompt.md does not tell the orchestrator to keep the marker unset for its own writes"
  grep -qF 'state_update_commands' "$ORCH_SERIAL" \
    || log_fail "TEST-RG-PIN-04: ORCHESTRATION.prompt.md does not name running the returned state_update_commands"
  local lines
  lines="$(wc -l < "$ORCH_SERIAL" | tr -d '[:space:]')"
  [[ "$lines" -le 45 ]] || log_fail "TEST-RG-PIN-04: ORCHESTRATION.prompt.md is $lines lines, exceeds the 45-line thin-wrapper ceiling (TEST-011)"
  [[ "$FAILED" == 0 ]] && log_pass "ORCHESTRATION.prompt.md relays the ENV row + state_update_commands, $lines/45 lines (TEST-RG-PIN-04)" || true
}

# --- TEST-RG-PIN-05: the four role prompts point at the returned-commands duty -

test_pin_role_prompts() {
  log_info "Test: PLANNING/IMPLEMENTATION/VALIDATION/REMEDIATION name state_update_commands + SUBAGENT_CONTRACT.md while keeping the state.mjs primary path and fallback marker (TEST-RG-PIN-05)..."
  local p f
  for p in PLANNING IMPLEMENTATION VALIDATION REMEDIATION; do
    f="$PROJECT_ROOT/.aai/${p}.prompt.md"
    [[ -f "$f" ]] || { log_fail "TEST-RG-PIN-05: missing prompt $f"; continue; }
    grep -qF 'state_update_commands' "$f" \
      || log_fail "TEST-RG-PIN-05: $p.prompt.md does not name state_update_commands"
    grep -qF '.aai/SUBAGENT_CONTRACT.md' "$f" \
      || log_fail "TEST-RG-PIN-05: $p.prompt.md does not point at .aai/SUBAGENT_CONTRACT.md"
    grep -qF 'node .aai/scripts/state.mjs' "$f" \
      || log_fail "TEST-RG-PIN-05: $p.prompt.md lost its node .aai/scripts/state.mjs primary path"
    grep -qF 'state.mjs is absent' "$f" \
      || log_fail "TEST-RG-PIN-05: $p.prompt.md lost its 'state.mjs is absent' fallback marker"
  done
  [[ "$FAILED" == 0 ]] && log_pass "All four role prompts name state_update_commands + SUBAGENT_CONTRACT.md, primary path and fallback marker intact (TEST-RG-PIN-05)" || true
}

# --- TEST-RG-PIN-06: CONTRACT holds the normative duty, PROTOCOL the merge input

test_pin_contract_and_protocol() {
  log_info "Test: SUBAGENT_CONTRACT.md carries the returned-commands duty + sole-agent carve; SUBAGENT_PROTOCOL.md names state_update_commands as a merge input and names the serial dispatch surface (TEST-RG-PIN-06)..."
  [[ -f "$SUBAGENT_CONTRACT" ]] || { log_fail "TEST-RG-PIN-06: SUBAGENT_CONTRACT.md missing: $SUBAGENT_CONTRACT"; return; }
  grep -qF 'state_update_commands' "$SUBAGENT_CONTRACT" \
    || log_fail "TEST-RG-PIN-06: SUBAGENT_CONTRACT.md does not name state_update_commands"
  grep -qiE 'sole agent|sole-agent|SOLE writer' "$SUBAGENT_CONTRACT" \
    || log_fail "TEST-RG-PIN-06: SUBAGENT_CONTRACT.md does not carry the sole-agent carve"
  grep -qF 'state_update_commands' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-06: SUBAGENT_PROTOCOL.md does not name state_update_commands as a merge input"
  grep -qF '.aai/ORCHESTRATION.prompt.md' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-06: SUBAGENT_PROTOCOL.md does not name the serial dispatch surface .aai/ORCHESTRATION.prompt.md"
  # The existing honesty assertion must survive unchanged.
  grep -qiF 'not a security boundary' "$SUBAGENT_PROTOCOL" \
    || log_fail "TEST-RG-PIN-06: SUBAGENT_PROTOCOL.md must keep the 'not a security boundary' honesty (TEST-RG-PIN-01 still binds)"
  [[ "$FAILED" == 0 ]] && log_pass "SUBAGENT_CONTRACT.md + SUBAGENT_PROTOCOL.md carry the D1 statement, merge input, and serial-surface name (TEST-RG-PIN-06)" || true
}

# --- TEST-RG-PIN-07: SEAM — check-role-output.mjs accepts the extension key ----

test_seam_extension_key_accepted() {
  log_info "Test [SEAM]: check-role-output.mjs accepts a block carrying state_update_commands (exit 0) and still refuses a block missing started_utc (exit 1, ROLE-OUTPUT-VIOLATION) (TEST-RG-PIN-07)..."
  if [[ ! -f "$CHECK_ROLE_OUTPUT" ]]; then
    log_info "TEST-RG-PIN-07: check-role-output.mjs absent, degrading (skip this arm only)"
    return
  fi
  local valid="$TEST_DIR/rg-pin-07-valid.md"
  cat > "$valid" <<'MD'
```yaml
subagent_result:
  scope: single-writer-canon-contradiction
  role: Implementation
  status: PASS
  started_utc: 2026-08-24T09:00:00Z
  ended_utc: 2026-08-24T09:07:00Z
  duration_seconds: 420
  evidence:
    - command: bash tests/skills/test-aai-r-guard.sh
      exit_code: 0
      output_snippet: "PASS: all aai-r-guard tests"
  files_changed:
    - .aai/SUBAGENT_CONTRACT.md
  blockers: []
  state_update_commands:
    - node .aai/scripts/state.mjs set-phase --ref single-writer-canon-contradiction --phase validation --status in_progress
```
MD
  local missing="$TEST_DIR/rg-pin-07-missing-started.md"
  cat > "$missing" <<'MD'
```yaml
subagent_result:
  scope: single-writer-canon-contradiction
  role: Implementation
  status: PASS
  ended_utc: 2026-08-24T09:07:00Z
  duration_seconds: 420
  evidence:
    - command: bash tests/skills/test-aai-r-guard.sh
      exit_code: 0
      output_snippet: "PASS: all aai-r-guard tests"
  files_changed:
    - .aai/SUBAGENT_CONTRACT.md
  blockers: []
  state_update_commands:
    - node .aai/scripts/state.mjs set-phase --ref single-writer-canon-contradiction --phase validation --status in_progress
```
MD
  local ec=0 out=""
  out="$(node "$CHECK_ROLE_OUTPUT" --file "$valid" --now 2026-08-24T09:10:00Z 2>&1)"; ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-RG-PIN-07: valid block + state_update_commands extension must exit 0 (got $ec): $out"

  ec=0
  out="$(node "$CHECK_ROLE_OUTPUT" --file "$missing" --now 2026-08-24T09:10:00Z 2>&1)"; ec=$?
  [[ "$ec" == 1 ]] || log_fail "TEST-RG-PIN-07: block missing started_utc must exit 1 (got $ec): $out"
  assert_payload_contains "$out" 'ROLE-OUTPUT-VIOLATION:' \
    "TEST-RG-PIN-07: missing-field rejection must print a ROLE-OUTPUT-VIOLATION: line"

  [[ "$FAILED" == 0 ]] && log_pass "SEAM: state_update_commands extension accepted (exit 0); missing-field block still refused (exit 1) (TEST-RG-PIN-07)" || true
}

# --- run ------------------------------------------------------------------------

check_deps
setup_fixture

test_pin_subagent_protocol
test_pin_orchestration_parallel
test_seam_marker_refuses
test_pin_orchestration_serial
test_pin_role_prompts
test_pin_contract_and_protocol
test_seam_extension_key_accepted

if [[ "$FAILED" == 0 ]]; then
  echo "PASS: all aai-r-guard tests (TEST-RG-PIN-01..07)"
  exit 0
else
  echo "FAIL: aai-r-guard suite had failures" >&2
  exit 1
fi
