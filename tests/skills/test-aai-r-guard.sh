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

# --- run ------------------------------------------------------------------------

check_deps
setup_fixture

test_pin_subagent_protocol
test_pin_orchestration_parallel
test_seam_marker_refuses

if [[ "$FAILED" == 0 ]]; then
  echo "PASS: all aai-r-guard tests (TEST-RG-PIN-01..03)"
  exit 0
else
  echo "FAIL: aai-r-guard suite had failures" >&2
  exit 1
fi
