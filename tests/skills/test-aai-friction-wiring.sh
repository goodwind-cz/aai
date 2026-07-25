#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 1 — local shadow-mode friction capture WIRING
# (docs/specs/SPEC-DRAFT-spec-friction-shadow-capture-wiring.md, TEST-001..007).
#
# Phase 0 shipped the protocol + offline CLI. Phase 1 wires them into the skill
# surface as ONE canonical seam, inherited by every universal skill via the
# shared guide, enforced here with a negative control.
#
#   .aai/system/FRICTION_PROTOCOL.md  — gains a "## Skill wiring (shadow capture)"
#                                       section naming the record command + the
#                                       shadow best-effort/never-mask contract.
#   .aai/AGENTS.md                    — gains ONE thin inheriting pointer.
#   .aai/scripts/aai-friction.mjs     — the Phase-0 CLI the seam invokes.
#
# Test map:
#   TEST-001 (Spec-AC-01) protocol has the "Skill wiring" seam naming the exact
#                         record command, exactly once.
#   TEST-002 (Spec-AC-02) AGENTS.md carries a thin pointer to the seam (shadow
#                         capture + FRICTION_PROTOCOL.md), not a duplicated body.
#   TEST-003 (Spec-AC-03) negative control: deleting the seam section OR the
#                         AGENTS pointer makes the guard FAIL (has teeth).
#   TEST-004 (Spec-AC-04) seam states the shadow contract: best-effort, never
#                         masks the skill result, capture failure swallowed.
#   TEST-005 (Spec-AC-05) the seam introduces NO Phase-2 surface (no triage,
#                         feedback.yaml, upsert, review/auto mode).
#   TEST-006 (Spec-AC-06) companion: prompt-diet + layer-profiles suites green.
#   TEST-007 (Spec-AC-01) integration: the documented record command runs
#                         end-to-end -> exactly one spool line, exit 0.

set -u

TEST_NAME="test-aai-friction-wiring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-friction.mjs"
PROTOCOL="$PROJECT_ROOT/.aai/system/FRICTION_PROTOCOL.md"
AGENTS="$PROJECT_ROOT/.aai/AGENTS.md"
PROMPT_DIET_TEST="$SCRIPT_DIR/test-aai-prompt-diet.sh"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

# The canonical seam markers Phase 1 introduces.
SEAM_HEADING="## Skill wiring (shadow capture)"
RECORD_CMD="node .aai/scripts/aai-friction.mjs record --input"

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
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
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  [ -f "$PROMPT_DIET_TEST" ]    || log_fail "test-aai-prompt-diet.sh not found"
  [ -f "$LAYER_PROFILES_TEST" ] || log_fail "test-aai-layer-profiles.sh not found"
  # PROTOCOL / AGENTS / SCRIPT are intentionally NOT required here so the RED
  # phase fails on each TEST-xxx's own assertion (product_red), not a skip.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-friction-wiring-test.XXXXXX")"
}

# Extract the "Skill wiring" seam section body (heading -> next "## " heading)
# from a protocol file. Prints nothing if the heading is absent.
extract_seam() {
  local file="$1"
  awk -v h="$SEAM_HEADING" '
    $0 == h { cap = 1; print; next }
    cap && /^## / { cap = 0 }
    cap { print }
  ' "$file"
}

# The guard predicate under test: exit 0 iff the seam is fully wired across the
# protocol file ($1) and the shared guide ($2). Used both on the live tree and,
# by TEST-003, on mutated copies to prove the guard has teeth.
seam_wired() {
  local protocol="$1" agents="$2"
  [ -f "$protocol" ] || return 1
  [ -f "$agents" ]   || return 1
  grep -qF "$SEAM_HEADING" "$protocol" || return 1
  grep -qF "$RECORD_CMD"   "$protocol" || return 1
  # AGENTS thin pointer: names the protocol seam + the shadow-capture concept.
  grep -qF "FRICTION_PROTOCOL.md" "$agents" || return 1
  grep -qi "shadow" "$agents"              || return 1
  grep -qi "friction" "$agents"            || return 1
  return 0
}

# --- TEST-001 (Spec-AC-01): protocol seam names the record command ----------

test_001_protocol_seam() {
  log_info "Test: FRICTION_PROTOCOL.md has the Skill wiring seam naming the record command (TEST-001)..."
  [ -f "$PROTOCOL" ] || log_fail "TEST-001: protocol file missing: $PROTOCOL"
  local n; n="$(grep -cF "$SEAM_HEADING" "$PROTOCOL" || true)"
  [ "$n" = "1" ] || log_fail "TEST-001: seam heading '$SEAM_HEADING' must appear exactly once (got $n)"
  grep -qF "$RECORD_CMD" "$PROTOCOL" \
    || log_fail "TEST-001: seam must name the exact record command '$RECORD_CMD'"
  log_pass "Protocol seam present and names the record command (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): AGENTS.md thin inheriting pointer ---------------

test_002_agents_pointer() {
  log_info "Test: AGENTS.md carries a thin pointer to the shadow-capture seam (TEST-002)..."
  [ -f "$AGENTS" ] || log_fail "TEST-002: AGENTS.md missing: $AGENTS"
  grep -qF "FRICTION_PROTOCOL.md" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md must reference FRICTION_PROTOCOL.md"
  grep -qi "shadow" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md pointer must mention shadow capture"
  grep -qi "friction" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md pointer must mention friction"
  # DRY: the pointer must NOT duplicate the protocol body. The taxonomy table
  # header lives only in the protocol; assert it is absent from AGENTS.md.
  if grep -qF "failure_class" "$AGENTS"; then
    log_fail "TEST-002: AGENTS.md must POINT at the seam, not duplicate the protocol body (found 'failure_class')"
  fi
  log_pass "AGENTS.md thin inheriting pointer present, body not duplicated (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): negative control (guard has teeth) --------------

test_003_negative_control() {
  log_info "Test: negative control — removing the seam or the pointer fails the guard (TEST-003)..."
  # Positive: the live tree is wired.
  seam_wired "$PROTOCOL" "$AGENTS" \
    || log_fail "TEST-003: live tree must be wired (positive control failed)"

  local p_mut="$TEST_DIR/protocol-no-seam.md"
  local a_mut="$TEST_DIR/agents-no-pointer.md"

  # Mutation 1: protocol with the whole seam section stripped.
  awk -v h="$SEAM_HEADING" '
    $0 == h { drop = 1; next }
    drop && /^## / { drop = 0 }
    drop { next }
    { print }
  ' "$PROTOCOL" > "$p_mut"
  if seam_wired "$p_mut" "$AGENTS"; then
    log_fail "TEST-003: guard passed with the protocol seam removed (no teeth)"
  fi

  # Mutation 2: AGENTS.md with every FRICTION_PROTOCOL.md reference removed.
  grep -v "FRICTION_PROTOCOL.md" "$AGENTS" > "$a_mut"
  if seam_wired "$PROTOCOL" "$a_mut"; then
    log_fail "TEST-003: guard passed with the AGENTS pointer removed (no teeth)"
  fi

  log_pass "Negative control: guard fails when either side of the seam is removed (TEST-003)"
}

# --- TEST-004 (Spec-AC-04): shadow best-effort / never-mask contract --------

test_004_shadow_contract() {
  log_info "Test: seam documents the shadow best-effort / never-mask / swallow contract (TEST-004)..."
  local seam; seam="$(extract_seam "$PROTOCOL")"
  [ -n "$seam" ] || log_fail "TEST-004: seam section is empty or missing"
  printf '%s' "$seam" | grep -qi "best-effort" \
    || log_fail "TEST-004: seam must state capture is best-effort"
  printf '%s' "$seam" | grep -qiE "never (mask|change)|must not (mask|change|replace)" \
    || log_fail "TEST-004: seam must state capture never masks/changes the skill result"
  printf '%s' "$seam" | grep -qi "swallow" \
    || log_fail "TEST-004: seam must state a capture failure is swallowed"
  log_pass "Seam documents the shadow best-effort / never-mask / swallow contract (TEST-004)"
}

# --- TEST-005 (Spec-AC-05): no Phase-2 surface introduced -------------------

test_005_no_phase2_surface() {
  log_info "Test: seam introduces no Phase-2 (triage/upsert/config) surface (TEST-005)..."
  local seam; seam="$(extract_seam "$PROTOCOL")"
  [ -n "$seam" ] || log_fail "TEST-005: seam section is empty or missing"
  local forbidden="aai-feedback-triage feedback.yaml upsert"
  local tok
  for tok in $forbidden; do
    if printf '%s' "$seam" | grep -qiF "$tok"; then
      log_fail "TEST-005: seam must not introduce Phase-2 surface token '$tok'"
    fi
  done
  # No GitHub/network invocation wired into the seam.
  if printf '%s' "$seam" | grep -qE '(^|[^a-zA-Z])gh (issue|pr|api)'; then
    log_fail "TEST-005: seam must not wire a gh network call"
  fi
  log_pass "Seam introduces no Phase-2 surface (TEST-005)"
}

# --- TEST-006 (Spec-AC-06): companion suites green --------------------------

test_006_companion_suites() {
  log_info "Test: companion prompt-diet + layer-profiles suites green (TEST-006)..."
  local out code
  out="$(bash "$PROMPT_DIET_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-006: test-aai-prompt-diet.sh must pass (exit $code): $(printf '%s' "$out" | tail -3)"
  out="$(bash "$LAYER_PROFILES_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-006: test-aai-layer-profiles.sh must pass (exit $code): $(printf '%s' "$out" | tail -3)"
  log_pass "Companion prompt-diet + layer-profiles suites green (TEST-006)"
}

# --- TEST-007 (Spec-AC-01, integration): documented command runs e2e --------

test_007_documented_command_runs() {
  log_info "Test: the documented record command runs end-to-end -> one spool line, exit 0 (TEST-007)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-007: capture CLI missing: $SCRIPT"
  local sp="$TEST_DIR/sp007"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local input="$TEST_DIR/wf007.json"
  cat > "$input" <<'JSON'
{
  "schema_version": 1,
  "skill_id": "SKILL_TDD",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the documented seam command records one observation",
  "observed_behavior": "verifying the prose->CLI seam end-to-end"
}
JSON
  # Invoke exactly the command form the seam documents.
  local code=0
  AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$input" \
    > "$TEST_DIR/o007" 2> "$TEST_DIR/e007" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-007: documented command must exit 0 (got $code): $(cat "$TEST_DIR/e007")"
  local n; n="$(grep -c . "$spool" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || log_fail "TEST-007: expected exactly 1 spool line (got $n)"
  log_pass "Documented record command runs end-to-end: one spool line, exit 0 (TEST-007)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_protocol_seam
  test_002_agents_pointer
  test_003_negative_control
  test_004_shadow_contract
  test_005_no_phase2_surface
  test_006_companion_suites
  test_007_documented_command_runs

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
