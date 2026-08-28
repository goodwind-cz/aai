#!/usr/bin/env bash
#
# Test: aai-pr validation waiver
# (docs/issues/CHANGE-DRAFT-operator-waiver-unblocks-pr.md, TEST-01..TEST-04;
#  ceremony_level 1 — the intake's Test Plan IS the declared validation scope.)
#
# Drives .aai/scripts/validation-waiver.mjs — the executable form of the
# aai-pr VALIDATION precondition (.aai/SKILL_PR.prompt.md), which before this
# change existed only as a sentence of prose no test could reach.
#
# Every arm asserts BEHAVIOUR, not the presence of a string: the gate's EXIT
# CODE (0 open / 1 blocked) is checked first and the reason token second, and
# each arm carries a NEGATIVE CONTROL built from the same words with only the
# load-bearing part changed — so an implementation that merely contained the
# right vocabulary would fail here.
#
# The STATE fixtures are written by the REAL .aai/scripts/state.mjs
# (`set-validation --status not_run --notes ...`), not hand-rolled YAML: the
# whole design rests on `--notes` being a field the state engine already
# accepts and on the folded block scalar (`>-`) it writes, and a hand-built
# fixture would never have proven either.
#
# ALL fixtures are scratch temp-dir copies — the real docs/ tree is NEVER
# touched. bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-pr-waiver.sh          # run all
#   bash tests/skills/test-aai-pr-waiver.sh 01       # one arm, by TEST id
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-pr-waiver"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$PROJECT_ROOT/.aai/scripts/validation-waiver.mjs"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"
STATE_TEMPLATE="$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml"

# shellcheck source=tests/skills/lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$GATE" ]] || log_fail "validation-waiver.mjs not found: $GATE"
  [[ -f "$STATE_CLI" ]] || log_fail "state.mjs not found: $STATE_CLI"
  [[ -f "$STATE_TEMPLATE" ]] || log_fail "STATE_TEMPLATE.yaml not found: $STATE_TEMPLATE"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-pr-waiver-test.XXXXXX")"; }

# --- helpers -----------------------------------------------------------------

# write_state <name> <status> <notes> -> echoes the fixture STATE path.
# Uses the REAL state.mjs so the notes travel through the same writer the
# operator's own `set-validation` call uses.
write_state() {
  local name="$1" status="$2" notes="$3" sp
  sp="$TEST_DIR/$name.yaml"
  cp "$STATE_TEMPLATE" "$sp"
  node "$STATE_CLI" --state "$sp" set-validation --status "$status" --notes "$notes" >/dev/null 2>&1 \
    || { echo "state.mjs set-validation REFUSED for $name (status=$status)" >&2; return 1; }
  echo "$sp"
}

# run_gate <state-path> -> sets GATE_RC and GATE_OUT. Never dies on a non-zero
# exit (`rc=$?` bare would, under this suite's own `set -e`).
GATE_RC=0
GATE_OUT=""
run_gate() {
  GATE_OUT=""
  GATE_RC=0
  GATE_OUT="$(node "$GATE" --state "$1" 2>&1)" || GATE_RC=$?
}

# run_gate_env <env-assignment> <state-path> — same, with one env var set, so
# an arm can prove the actor is NOT read from the environment.
run_gate_env() {
  GATE_OUT=""
  GATE_RC=0
  GATE_OUT="$(env "$1" node "$GATE" --state "$2" 2>&1)" || GATE_RC=$?
}

expect_rc() {
  local want="$1" what="$2"
  [[ "$GATE_RC" -eq "$want" ]] \
    || log_fail "$what: expected exit $want, got $GATE_RC — output: $(payload_preview "$GATE_OUT")"
}

# --- the waiver records used across the arms ----------------------------------
# ONE timestamp and ONE reason shared by every record below, so the ONLY thing
# that differs between a passing and a refused arm is the part under test.
AT="2026-08-28T17:00:00Z"
REASON_TEXT="operator ran the declared suite by hand and accepts the risk"
OPERATOR_RECORD="[AAI-VALIDATION-WAIVER v1 by=operator at=$AT reason=\"$REASON_TEXT\"]"
AGENT_RECORD="[AAI-VALIDATION-WAIVER v1 by=agent at=$AT reason=\"$REASON_TEXT\"]"

# --- TEST-01 -----------------------------------------------------------------
# A bare not_run still blocks exactly as it did before this change — including
# when the note SAYS, in English, that validation was waived. The prose control
# is the point: a sentence someone types must never read as a waiver.
test_01_bare_not_run_blocks() {
  log_info "TEST-01: bare not_run (and prose that merely claims a waiver) still blocks..."
  local sp
  sp="$(write_state bare not_run "suite re-run by hand; nothing else to add")"
  run_gate "$sp"
  expect_rc 1 "TEST-01 bare not_run"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=validation_not_run_no_waiver" \
    "TEST-01: a bare not_run must block with the no-waiver reason" || return 1

  sp="$(write_state prose not_run "validation was waived by the operator, who reviewed this himself on 2026-08-28 for a good reason")"
  run_gate "$sp"
  expect_rc 1 "TEST-01 prose claiming a waiver"
  assert_payload_contains "$GATE_OUT" "reason=validation_not_run_no_waiver" \
    "TEST-01: an English sentence claiming a waiver must NOT read as one" || return 1

  # Negative control: the gate is not simply always-blocked.
  sp="$(write_state passing pass "the suite ran and passed")"
  run_gate "$sp"
  expect_rc 0 "TEST-01 control (status pass)"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=validation_pass" \
    "TEST-01 control: status pass must still open the gate" || return 1
  log_pass "TEST-01 bare not_run blocks; prose is not a waiver; pass still opens"
}

# --- TEST-02 -----------------------------------------------------------------
# not_run PLUS a well-formed operator waiver opens the gate — through the real
# state.mjs writer, so the folded block scalar round-trip is proven, not assumed.
test_02_operator_waiver_opens() {
  log_info "TEST-02: not_run + a well-formed operator waiver opens the gate..."
  local sp
  sp="$(write_state operator not_run "$OPERATOR_RECORD")"

  # The record must actually have survived state.mjs's folded-scalar writer.
  grep -qF 'notes: >-' "$sp" \
    || log_fail "TEST-02: state.mjs did not write notes as a folded block scalar — the fixture proves nothing"
  grep -qF 'status: not_run' "$sp" \
    || log_fail "TEST-02: status must remain not_run — the waiver never dresses itself as a pass"

  run_gate "$sp"
  expect_rc 0 "TEST-02 operator waiver"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-02: a well-formed operator waiver must open the gate" || return 1
  assert_payload_contains "$GATE_OUT" "waiver_by=operator waiver_at=$AT" \
    "TEST-02: the gate must echo WHO waived and WHEN" || return 1
  assert_payload_contains "$GATE_OUT" "waiver_reason=$REASON_TEXT" \
    "TEST-02: the gate must echo the recorded reason" || return 1
  assert_payload_contains "$GATE_OUT" "status=not_run" \
    "TEST-02: the reported status must stay not_run, never be restated as pass" || return 1
  log_pass "TEST-02 operator waiver opens the gate with status still not_run"
}

# --- TEST-03 -----------------------------------------------------------------
# The reason is what makes a waiver accountable, so every shape that lacks one
# is REFUSED — including the shape that keeps every other word of the grammar.
# A half-typed record must never degrade into "no waiver was intended".
test_03_empty_reason_refused() {
  log_info "TEST-03: empty / whitespace / missing reason is refused, not silently accepted..."
  local sp
  local empty_rec="[AAI-VALIDATION-WAIVER v1 by=operator at=$AT reason=\"\"]"
  local blank_rec="[AAI-VALIDATION-WAIVER v1 by=operator at=$AT reason=\"   \"]"
  local noreason_rec="[AAI-VALIDATION-WAIVER v1 by=operator at=$AT]"

  sp="$(write_state empty_reason not_run "$empty_rec")"
  run_gate "$sp"
  expect_rc 1 "TEST-03 empty reason"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=waiver_empty_reason" \
    "TEST-03: an empty reason must be REFUSED by name" || return 1

  sp="$(write_state blank_reason not_run "$blank_rec")"
  run_gate "$sp"
  expect_rc 1 "TEST-03 whitespace-only reason"
  assert_payload_contains "$GATE_OUT" "reason=waiver_empty_reason" \
    "TEST-03: a whitespace-only reason must be REFUSED" || return 1

  sp="$(write_state missing_reason not_run "$noreason_rec")"
  run_gate "$sp"
  expect_rc 1 "TEST-03 missing reason key"
  assert_payload_contains "$GATE_OUT" "reason=waiver_malformed" \
    "TEST-03: a record with no reason key at all must be REFUSED as malformed, never treated as an absent waiver" || return 1
  assert_payload_not_contains "$GATE_OUT" "VALIDATION-GATE open" \
    "TEST-03: no reasonless shape may open the gate" || return 1

  # Negative control: SAME record, SAME actor, SAME instant — only the reason
  # is non-empty. If this did not open, the arms above would be vacuous.
  sp="$(write_state control_reason not_run "$OPERATOR_RECORD")"
  run_gate "$sp"
  expect_rc 0 "TEST-03 control (non-empty reason)"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-03 control: the identical record with a real reason MUST open" || return 1
  log_pass "TEST-03 empty, whitespace and missing reasons refused; the same record with a reason opens"
}

# --- TEST-04 -----------------------------------------------------------------
# An agent MAY waive, but it is recorded DISTINCTLY. The assertion is a
# property — the two verdicts must not be equal — so a build that accepted an
# agent waiver and reported it as an operator one fails here even though every
# expected word is still present in the output.
test_04_self_waived_marked_distinctly() {
  log_info "TEST-04: a self-waived (agent) record is accepted but marked distinctly..."
  local sp_agent sp_op agent_out op_out
  sp_agent="$(write_state agent_waiver not_run "$AGENT_RECORD")"
  sp_op="$(write_state operator_waiver not_run "$OPERATOR_RECORD")"

  run_gate "$sp_agent"
  expect_rc 0 "TEST-04 agent waiver accepted"
  agent_out="$GATE_OUT"
  run_gate "$sp_op"
  expect_rc 0 "TEST-04 operator waiver accepted"
  op_out="$GATE_OUT"

  [[ "$agent_out" != "$op_out" ]] \
    || log_fail "TEST-04: the agent and operator verdicts are IDENTICAL — a self-waiver is not marked distinctly at all: $(payload_preview "$agent_out")"

  assert_payload_contains "$agent_out" "VALIDATION-GATE open reason=self_waived_by_agent" \
    "TEST-04: an agent waiver must be reported as self-waived" || return 1
  assert_payload_not_contains "$agent_out" "waived_by_operator" \
    "TEST-04: an agent waiver must NEVER be reported as an operator waiver" || return 1
  assert_payload_contains "$agent_out" "waiver_by=agent" \
    "TEST-04: the recorded actor must be echoed as agent" || return 1
  assert_payload_contains "$op_out" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-04: an operator waiver must be reported as an operator waiver" || return 1

  # The actor comes from the RECORD, never from the environment. AAI_ROLE was
  # measured UNSET live in this repo on a dispatch that mandated it, so it can
  # carry no accountability claim (intake, owner decision 2).
  run_gate_env "AAI_ROLE=operator" "$sp_agent"
  expect_rc 0 "TEST-04 agent record under AAI_ROLE=operator"
  assert_payload_contains "$GATE_OUT" "reason=self_waived_by_agent" \
    "TEST-04: AAI_ROLE must not be able to promote a self-waiver to an operator one" || return 1
  run_gate_env "AAI_ROLE=agent" "$sp_op"
  expect_rc 0 "TEST-04 operator record under AAI_ROLE=agent"
  assert_payload_contains "$GATE_OUT" "reason=waived_by_operator" \
    "TEST-04: AAI_ROLE must not be able to demote an operator waiver" || return 1
  log_pass "TEST-04 self-waived marked distinctly and the actor is read from the record, not the environment"
}

# --- runner ------------------------------------------------------------------

ALL_TESTS="01_bare_not_run_blocks 02_operator_waiver_opens 03_empty_reason_refused 04_self_waived_marked_distinctly"

main() {
  local requested="${1:-}"
  check_deps
  setup_fixture
  local selected="" t
  for t in $ALL_TESTS; do
    if [[ -z "$requested" || "$t" == "$requested"* ]]; then
      selected="$selected $t"
    fi
  done
  if [[ -z "$selected" ]]; then
    log_fail "no arm matches '$requested' (available: $ALL_TESTS)"
  fi
  for t in $selected; do
    "test_${t}"
  done
  echo "ALL TESTS PASSED: $TEST_NAME ($selected )"
}

main "$@"
