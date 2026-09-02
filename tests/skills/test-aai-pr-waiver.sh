#!/usr/bin/env bash
#
# Test: aai-pr validation waiver
# (docs/issues/CHANGE-0167-operator-waiver-unblocks-pr.md, TEST-01..TEST-09;
#  ceremony_level 1 — the intake's Test Plan IS the declared validation scope.)
#
# TEST-05..TEST-08 close the PR #303 bot review: the ambiguous case (F-6), the
# waiver leaking across work items (F-1), the refusal of the pre-scope-binding
# v1 grammar, and the END-TO-END durability of a waiver through the REAL
# metrics flush into the REAL factory report (F-2).
#
# TEST-11..TEST-16 cover the ARCHIVE LANE
# (spec-metrics-flush-invalidates-pr-precondition, Spec-AC-02..Spec-AC-07):
# the flush archives a PASS into METRICS.jsonl and resets the live fields, so
# the gate learns to read the durable proof back. The lane may only ever OPEN
# — every arm below pins either the ONE shape that opens it or one of the
# EIGHT neighbouring shapes that must not, and TEST-16 pins that a note the
# archive lane refuses still opens on its own waiver exactly as it does today.
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

# write_state <name> <status> <notes> [ref] -> echoes the fixture STATE path.
# Uses the REAL state.mjs so the notes travel through the same writer the
# operator's own `set-validation` call uses. `ref` defaults to the scope every
# record below names, so an arm that is not about scope binding stays about
# the thing it is about.
SCOPE_REF="CHANGE-0167"
write_state() {
  local name="$1" status="$2" notes="$3" ref="${4:-$SCOPE_REF}" sp
  sp="$TEST_DIR/$name.yaml"
  cp "$STATE_TEMPLATE" "$sp"
  node "$STATE_CLI" --state "$sp" set-validation --status "$status" --ref "$ref" --notes "$notes" >/dev/null 2>&1 \
    || { echo "state.mjs set-validation REFUSED for $name (status=$status)" >&2; return 1; }
  echo "$sp"
}

# reset_validation_ref <state-path> <ref> — the EXACT call a NEXT work item
# makes: a bare not_run for a different ref, no --notes. state.mjs preserves
# the previous notes here; that preservation is the leak TEST-06 pins.
reset_validation_ref() {
  node "$STATE_CLI" --state "$1" set-validation --status not_run --ref "$2" >/dev/null 2>&1 \
    || { echo "state.mjs set-validation REFUSED for ref $2" >&2; return 1; }
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

# run_gate_ref <state-path> <scope-ref> — the gate with an explicit FALLBACK
# scope, the shape SKILL_PR reaches when the flush has nulled
# `last_validation.ref_id` and the ride in hand is a different one.
run_gate_ref() {
  GATE_OUT=""
  GATE_RC=0
  GATE_OUT="$(node "$GATE" --state "$1" --ref "$2" 2>&1)" || GATE_RC=$?
}

expect_rc() {
  local want="$1" what="$2"
  [[ "$GATE_RC" -eq "$want" ]] \
    || log_fail "$what: expected exit $want, got $GATE_RC — output: $(payload_preview "$GATE_OUT")"
}

# --- the waiver records used across the arms ----------------------------------
# ONE timestamp and ONE reason shared by every record below, so the ONLY thing
# that differs between a passing and a refused arm is the part under test.
# The bare sentinel, used by the PREMISE assertions that check whether a
# record is still physically present in a fixture.
WAIVER_SENTINEL_TOKEN="[AAI-VALIDATION-WAIVER"
AT="2026-08-28T17:00:00Z"
REASON_TEXT="operator ran the declared suite by hand and accepts the risk"
OPERATOR_RECORD="[AAI-VALIDATION-WAIVER v2 by=operator ref=$SCOPE_REF at=$AT reason=\"$REASON_TEXT\"]"
AGENT_RECORD="[AAI-VALIDATION-WAIVER v2 by=agent ref=$SCOPE_REF at=$AT reason=\"$REASON_TEXT\"]"

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
  # The DOCUMENTED return shape of the no-sentinel case, asserted rather than
  # merely commented (PR #303 F-5: the header promised a bare `{present:false}`
  # the code never returned, and a caller reading `.ok` on it would have got
  # `undefined`, which is falsy by luck rather than by contract). Every return
  # of parseWaiver carries the same three keys; this pins that.
  local shape
  shape="$(node -e '
    import("'"$PROJECT_ROOT"'/.aai/scripts/validation-waiver.mjs").then((m) => {
      const r = m.parseWaiver("no sentinel anywhere in this sentence");
      console.log(`${Object.keys(r).sort().join(",")}|${r.present}|${r.ok}|${r.error}`);
    });')"
  [[ "$shape" == "error,ok,present|false|false|null" ]] \
    || log_fail "TEST-01: parseWaiver's no-sentinel return must be exactly {present:false, ok:false, error:null} as documented — got '$shape'"
  log_pass "TEST-01 bare not_run blocks; prose is not a waiver; pass still opens; the no-sentinel return shape matches its own comment"
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
  assert_payload_contains "$GATE_OUT" "waiver_by=operator waiver_ref=$SCOPE_REF waiver_at=$AT" \
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
  local empty_rec="[AAI-VALIDATION-WAIVER v2 by=operator ref=$SCOPE_REF at=$AT reason=\"\"]"
  local blank_rec="[AAI-VALIDATION-WAIVER v2 by=operator ref=$SCOPE_REF at=$AT reason=\"   \"]"
  local noreason_rec="[AAI-VALIDATION-WAIVER v2 by=operator ref=$SCOPE_REF at=$AT]"

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

# --- TEST-05 -----------------------------------------------------------------
# TWO well-formed records must BLOCK, by name, and never "pick one and open"
# (PR #303 F-6). The two records are DELIBERATELY in conflict — an agent's and
# an operator's — because that is the case where picking one silently changes
# who is accountable.
test_05_two_records_block_ambiguous() {
  log_info "TEST-05: two well-formed records BLOCK as waiver_ambiguous, never 'pick one and open'..."
  local sp
  sp="$(write_state ambiguous not_run "$OPERATOR_RECORD $AGENT_RECORD")"
  run_gate "$sp"
  expect_rc 1 "TEST-05 two records"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=waiver_ambiguous" \
    "TEST-05: two records must be REFUSED by name" || return 1
  # The two ways "pick one" would show up. Both are checked, because the
  # ambiguity is only dangerous when it resolves to SOMETHING.
  assert_payload_not_contains "$GATE_OUT" "VALIDATION-GATE open" \
    "TEST-05: an ambiguous note must never open the gate" || return 1
  assert_payload_not_contains "$GATE_OUT" "waived_by_operator" \
    "TEST-05: an ambiguous note must not resolve to the operator record" || return 1
  assert_payload_not_contains "$GATE_OUT" "self_waived_by_agent" \
    "TEST-05: an ambiguous note must not resolve to the agent record" || return 1

  # The REPORT scanner must agree with the gate (F-4): the same note yields
  # ZERO usable records and counts BOTH sentinels as rejected. A scanner that
  # accepted `records.length > 1` with rejected 0 fails right here.
  local scan
  scan="$(node -e '
    import("'"$PROJECT_ROOT"'/.aai/scripts/validation-waiver.mjs").then((m) => {
      const r = m.scanWaivers(process.argv[1]);
      console.log(`records=${r.records.length} rejected=${r.rejected}`);
    });' "$OPERATOR_RECORD $AGENT_RECORD")"
  [[ "$scan" == "records=0 rejected=2" ]] \
    || log_fail "TEST-05: the report scanner must refuse exactly what the gate refuses — got '$scan' (want records=0 rejected=2)"

  # Negative control: ONE of those same two records, alone, opens. Without
  # this the arm above would pass on a gate that simply blocked everything.
  sp="$(write_state ambiguous_control not_run "$OPERATOR_RECORD")"
  run_gate "$sp"
  expect_rc 0 "TEST-05 control (a single record)"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-05 control: either record ALONE must still open the gate" || return 1
  log_pass "TEST-05 two records block as waiver_ambiguous in BOTH consumers; one record still opens"
}

# --- TEST-06 -----------------------------------------------------------------
# THE LEAK (PR #303 F-1). `set-validation --status not_run --ref <other>`
# rewrites status and ref_id but PRESERVES notes. Before the scope binding the
# evaluator read that note without ever consulting a ref, so ride B inherited
# ride A's waiver and opened on a decision nobody made for B.
#
# The whole sequence runs through the REAL state.mjs — a hand-written fixture
# would have proven nothing about the preservation that causes the leak.
test_06_waiver_does_not_leak_across_refs() {
  log_info "TEST-06: a waiver issued for ride A does not open ride B's gate..."
  local sp ride_a="RIDE-A" ride_b="RIDE-B"
  local rec_a="[AAI-VALIDATION-WAIVER v2 by=operator ref=$ride_a at=$AT reason=\"$REASON_TEXT\"]"

  sp="$(write_state leak not_run "$rec_a" "$ride_a")"
  run_gate "$sp"
  expect_rc 0 "TEST-06 ride A opens on its own waiver"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-06: ride A must open on the waiver issued for ride A" || return 1

  # Ride B starts. Exactly the call state.mjs offers: no --notes.
  reset_validation_ref "$sp" "$ride_b" || return 1

  # The preservation is the PREMISE of this arm. Assert it, or the arm could
  # pass for the wrong reason (a state.mjs that cleared notes would make the
  # gate block for a reason this test is not measuring).
  assert_payload_contains "$(cat "$sp")" "$WAIVER_SENTINEL_TOKEN" \
    "TEST-06 premise: state.mjs must still be PRESERVING the previous notes — otherwise this arm proves nothing" || return 1
  grep -qF "ref_id: $ride_b" "$sp" \
    || log_fail "TEST-06 premise: last_validation.ref_id must now name $ride_b"

  run_gate "$sp"
  expect_rc 1 "TEST-06 ride B must NOT inherit ride A's waiver"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=waiver_ref_mismatch" \
    "TEST-06: a waiver issued for another ride must be refused BY NAME, not silently ignored" || return 1
  # A NAMED mismatch, not a generic "no waiver": the operator has to be told
  # which two scopes disagreed, or they will re-issue the same stale record.
  assert_payload_contains "$GATE_OUT" "waiver_ref=$ride_a" \
    "TEST-06: the refusal must name the scope the record was issued FOR" || return 1
  assert_payload_contains "$GATE_OUT" "scope_ref=$ride_b" \
    "TEST-06: the refusal must name the scope in hand" || return 1

  # Negative control, built from the SAME words: re-issue the identical record
  # for ride B. Only the ref differs, and the gate opens. So the arm above is
  # measuring the binding, not a gate that blocks whenever notes were reused.
  local rec_b="[AAI-VALIDATION-WAIVER v2 by=operator ref=$ride_b at=$AT reason=\"$REASON_TEXT\"]"
  sp="$(write_state leak_control not_run "$rec_b" "$ride_b")"
  run_gate "$sp"
  expect_rc 0 "TEST-06 control (record re-issued for ride B)"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-06 control: the same record, issued FOR ride B, must open ride B's gate" || return 1

  # And a waiver with NO scope to check against is refused too — "there is no
  # context" is the leak at its worst, not a free pass.
  GATE_OUT=""; GATE_RC=0
  GATE_OUT="$(node "$GATE" --notes "$rec_a" --status not_run 2>&1)" || GATE_RC=$?
  [[ "$GATE_RC" -eq 1 ]] || log_fail "TEST-06: a waiver with no scope in hand must block (got exit $GATE_RC): $(payload_preview "$GATE_OUT")"
  assert_payload_contains "$GATE_OUT" "reason=waiver_scope_unknown" \
    "TEST-06: an unbindable waiver must be refused by name" || return 1
  log_pass "TEST-06 a waiver is bound to the ref it names; ride B blocks with waiver_ref_mismatch"
}

# --- TEST-07 -----------------------------------------------------------------
# The grammar version is load-bearing, so a record written under the
# pre-scope-binding v1 grammar is REFUSED LOUDLY AND BY ITS OWN NAME — never
# honoured, and never blurred into "somebody mistyped a record".
test_07_v1_record_refused_by_name() {
  log_info "TEST-07: a v1 record is refused as obsolete, never honoured and never called malformed..."
  local sp
  local v1_rec="[AAI-VALIDATION-WAIVER v1 by=operator at=$AT reason=\"$REASON_TEXT\"]"
  sp="$(write_state v1record not_run "$v1_rec")"
  run_gate "$sp"
  expect_rc 1 "TEST-07 v1 record"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=waiver_obsolete_version" \
    "TEST-07: a v1 record must be refused as an OBSOLETE VERSION" || return 1
  assert_payload_not_contains "$GATE_OUT" "VALIDATION-GATE open" \
    "TEST-07: a v1 record must never open the gate" || return 1
  assert_payload_not_contains "$GATE_OUT" "reason=waiver_malformed" \
    "TEST-07: 'this predates the scope binding' is a different fact from 'this is a typo'" || return 1

  # A v1 record that ALSO carries a ref= is still v1 — the version token is
  # what is checked, not whether the fields happen to look modern.
  local v1_with_ref="[AAI-VALIDATION-WAIVER v1 by=operator ref=$SCOPE_REF at=$AT reason=\"$REASON_TEXT\"]"
  sp="$(write_state v1withref not_run "$v1_with_ref")"
  run_gate "$sp"
  expect_rc 1 "TEST-07 v1 record carrying a ref"
  assert_payload_contains "$GATE_OUT" "reason=waiver_obsolete_version" \
    "TEST-07: the VERSION TOKEN decides, not the field list" || return 1

  # Negative control: the same record re-issued at v2 opens. Only the version
  # token differs between this and the first fixture.
  sp="$(write_state v1control not_run "$OPERATOR_RECORD")"
  run_gate "$sp"
  expect_rc 0 "TEST-07 control (v2 record)"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-07 control: the current version must still open" || return 1
  log_pass "TEST-07 a v1 record is refused by name; the same record at v2 opens"
}

# --- TEST-08 -----------------------------------------------------------------
# DURABILITY, END TO END (PR #303 F-2). A waiver lives in STATE
# `last_validation.notes`, and the metrics flush RESETS that field — so before
# this fix the record existed nowhere after close and the factory report's
# waiver section was structurally always zero.
#
# This arm runs the REAL scripts in the REAL order — state.mjs writes the
# waiver, metrics-flush.mjs flushes and resets, generate-factory-report.mjs
# reads the ledger — and asserts the record survives the whole trip. Nothing
# here is mocked; a passing assertion means the pipeline actually carries it.
test_08_waiver_survives_flush_into_report() {
  log_info "TEST-08: a waiver survives the REAL flush and is named by the REAL factory report..."
  local d="$TEST_DIR/e2e" ref="DURABLE-1"
  rm -rf "$d"; mkdir -p "$d/docs/ai" "$d/docs/issues"
  printf '# ledger comment header\n' > "$d/docs/ai/METRICS.jsonl"
  cat > "$d/PRICING.yaml" <<'YAML'
schema_version: 2
models: {}
YAML
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: none
  ref_id: null
  primary_path: null
active_work_items:
  - ref_id: $ref
    status: done
    phase: validation
    primary_path: docs/issues/${ref}.md
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  status: not_run
  run_at_utc: null
  ref_id: null
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    $ref:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:10:00Z
          duration_seconds: 600
          tokens_in: 1000
          tokens_out: 100
          cost_usd: 0.5

updated_at_utc: 2026-07-15T11:30:00Z
YAML
  printf '{"v":1,"ts":"2026-07-15T10:30:00Z","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' \
    "$ref" > "$d/docs/ai/EVENTS.jsonl"

  # 1) The operator records the waiver through the REAL state CLI.
  local rec="[AAI-VALIDATION-WAIVER v2 by=operator ref=$ref at=$AT reason=\"$REASON_TEXT\"]"
  node "$STATE_CLI" --state "$d/docs/ai/STATE.yaml" set-validation --status not_run --ref "$ref" --notes "$rec" >/dev/null 2>&1 \
    || log_fail "TEST-08: state.mjs refused the waiver write"
  run_gate "$d/docs/ai/STATE.yaml"
  expect_rc 0 "TEST-08 the waiver opens the gate before the flush"

  # 2) The REAL flush. --sweep is the path a waived ride takes: its validation
  # status is not_run, so the default PASS gate never fires for it.
  local flush_out="$d/flush.log" fec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now "2026-07-16T00:00:00Z" --sweep \
    > "$flush_out" 2>&1) || fec=$?
  [[ "$fec" == 0 ]] || log_fail "TEST-08: the flush must exit 0 (got $fec): $(cat "$flush_out")"

  # 3) STATE really did lose it — the premise. If the reset stopped clearing
  # notes this arm would pass for the wrong reason.
  assert_payload_not_contains "$(cat "$d/docs/ai/STATE.yaml")" "$WAIVER_SENTINEL_TOKEN" \
    "TEST-08 premise: the flush must have RESET last_validation.notes — otherwise durability is untested" || return 1

  # 4) The LEDGER carries it, structurally, in its own durable field.
  local durable
  durable="$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#"));
    const e = JSON.parse(lines[0]);
    const w = e.validation_waiver;
    console.log(w ? `${w.by}|${w.ref_id}|${w.at}|${w.reason}` : "ABSENT");
  ' "$d/docs/ai/METRICS.jsonl")"
  [[ "$durable" == "operator|$ref|$AT|$REASON_TEXT" ]] \
    || log_fail "TEST-08: the ledger entry must carry the waiver verbatim — got '$durable'"
  grep -qF "Validation waiver persisted to ledger entry $ref" "$flush_out" \
    || log_fail "TEST-08: the flush must SAY where the waiver landed: $(cat "$flush_out")"

  # 5) The REAL report names it. This is the assertion the finding is about:
  # "the report always says zero" must be false.
  local rec_out="$d/report.log" rec2=0
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/generate-factory-report.mjs" \
    --metrics "$d/docs/ai/METRICS.jsonl" --events "$d/docs/ai/EVENTS.jsonl" \
    --output "$d/docs/ai/factory-report.html" \
    > "$rec_out" 2>&1) || rec2=$?
  [[ "$rec2" == 0 ]] || log_fail "TEST-08: the report generator must exit 0: $(cat "$rec_out")"
  local counts
  counts="$(node -e '
    const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const w = m.validation_waivers;
    const r = w.rides.find((x) => x.ref === process.argv[2]) || {};
    console.log(`${w.total}|${w.operator}|${w.agent}|${r.by}|${r.reason}`);
  ' "$d/docs/ai/factory-report-data.json" "$ref")"
  [[ "$counts" == "1|1|0|operator|$REASON_TEXT" ]] \
    || log_fail "TEST-08: the report must name the waived ride — got '$counts' (want 1|1|0|operator|$REASON_TEXT)"
  grep -qF "$ref" "$d/docs/ai/factory-report.html" \
    || log_fail "TEST-08: the rendered HTML must list the waived ride by ref"
  log_pass "TEST-08 a waiver survives STATE -> flush -> ledger -> report; STATE itself is reset, and the report still names it"
}

# --- TEST-09 -----------------------------------------------------------------
# THE LOSS CASE, MADE LOUD (PR #303 F-2, second half). A flush can reset
# `last_validation.notes` without any flushed ride having taken the waiver —
# the waiver names one ref and a different one is being flushed. That is the
# moment a waiver would disappear. It must not disappear QUIETLY, and it must
# not disappear at all: the record is PRESERVED verbatim in the reset note and
# the flush SAYS so.
test_09_unflushed_waiver_is_loud_not_lost() {
  log_info "TEST-09: a waiver no flushed ride carried is preserved verbatim and WARNed about, never dropped..."
  local d="$TEST_DIR/loss" flushed="ITEM-P" waived="ITEM-Q"
  rm -rf "$d"; mkdir -p "$d/docs/ai" "$d/docs/issues"
  printf '# ledger comment header\n' > "$d/docs/ai/METRICS.jsonl"
  printf 'schema_version: 2\nmodels: {}\n' > "$d/PRICING.yaml"
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: change
  ref_id: $flushed
  primary_path: docs/issues/${flushed}.md
active_work_items:
  - ref_id: $flushed
    status: done
    phase: validation
    primary_path: docs/issues/${flushed}.md
  - ref_id: $waived
    status: in_progress
    phase: validation
    primary_path: docs/issues/${waived}.md
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  status: not_run
  run_at_utc: null
  ref_id: null
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    $flushed:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:10:00Z
          duration_seconds: 600
          tokens_in: 1000
          tokens_out: 100
          cost_usd: 0.5

updated_at_utc: 2026-07-15T11:30:00Z
YAML
  printf '{"v":1,"ts":"2026-07-15T10:30:00Z","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' \
    "$flushed" > "$d/docs/ai/EVENTS.jsonl"

  # The waiver belongs to $waived; $flushed is what the sweep will take.
  local rec="[AAI-VALIDATION-WAIVER v2 by=operator ref=$waived at=$AT reason=\"$REASON_TEXT\"]"
  node "$STATE_CLI" --state "$d/docs/ai/STATE.yaml" set-validation --status not_run --ref "$waived" --notes "$rec" >/dev/null 2>&1 \
    || log_fail "TEST-09: state.mjs refused the waiver write"

  local flush_out="$d/flush.log" fec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now "2026-07-16T00:00:00Z" --sweep \
    > "$flush_out" 2>&1) || fec=$?
  [[ "$fec" == 0 ]] || log_fail "TEST-09: the flush must exit 0 (got $fec): $(cat "$flush_out")"

  # PREMISE: the reset really did run for the flushed ref. Without it the
  # waiver was never in danger and this arm would prove nothing.
  grep -qF "Partial-flush reset applied" "$flush_out" \
    || log_fail "TEST-09 premise: the partial reset must have fired — otherwise nothing threatened the waiver: $(cat "$flush_out")"

  # LOUD: the flush names the waiver it could not place.
  assert_payload_contains "$(cat "$flush_out")" "WARNING validation waiver for $waived" \
    "TEST-09: a waiver that reached no ledger entry must be WARNed about by ref" || return 1
  # NOT LOST: the record itself is still readable, verbatim, in STATE.
  assert_payload_contains "$(cat "$d/docs/ai/STATE.yaml")" "PRESERVED unflushed validation waiver" \
    "TEST-09: the reset note must say the record was preserved" || return 1
  assert_payload_contains "$(cat "$d/docs/ai/STATE.yaml")" "ref=$waived at=$AT" \
    "TEST-09: the preserved record must survive VERBATIM, not as a summary" || return 1
  # And the ledger must NOT claim it: attributing $waived's waiver to $flushed
  # would be worse than losing it.
  local attributed
  attributed="$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#"));
    console.log(lines.map((l) => { const e = JSON.parse(l); return `${e.ref_id}:${e.validation_waiver ? "yes" : "no"}`; }).join(","));
  ' "$d/docs/ai/METRICS.jsonl")"
  [[ "$attributed" == "$flushed:no" ]] \
    || log_fail "TEST-09: the flushed ride must NOT be credited with another ref's waiver — got '$attributed'"
  log_pass "TEST-09 an unplaceable waiver is WARNed and preserved verbatim, and is never attributed to the wrong ride"
}

# --- TEST-10 -----------------------------------------------------------------
# state-route-exists-but-is-undiscoverable: a genuinely ABSENT STATE.yaml
# (`state_unreadable`, the `existsSync` check at the very top of the --state
# branch) must name the real bootstrap route (check-state.mjs --repair, then
# state.mjs set-focus). A PRESENT-but-broken STATE.yaml — no `last_validation:`
# block at all, or one with no readable `status` — lands on the DIFFERENT
# reason `validation_block_unreadable` from evaluateGate and must NOT get that
# suggestion, because `check-state.mjs --repair` only ever creates a file that
# does not already exist and would silently do nothing here.
test_10_absent_vs_corrupt_state() {
  log_info "TEST-10: absent STATE.yaml names the bootstrap route; a present-but-broken one keeps the distinct block_unreadable reason with no --repair suggestion..."

  # Case A — genuinely absent path (never created).
  local absent="$TEST_DIR/does-not-exist.yaml"
  [[ ! -e "$absent" ]] || log_fail "TEST-10 fixture: $absent must not exist"
  run_gate "$absent"
  expect_rc 1 "TEST-10 absent STATE"
  assert_payload_contains "$GATE_OUT" "reason=state_unreadable" \
    "TEST-10: absent STATE must report state_unreadable" || return 1
  assert_payload_contains "$GATE_OUT" "check-state.mjs --repair" \
    "TEST-10: absent STATE must name check-state.mjs --repair" || return 1
  assert_payload_contains "$GATE_OUT" "state.mjs set-focus" \
    "TEST-10: absent STATE must name state.mjs set-focus" || return 1
  assert_payload_not_contains "$GATE_OUT" "reason=validation_block_unreadable" \
    "TEST-10: absent STATE must NOT be reported under the corrupt-file reason" || return 1

  # Case A' — same, --json: the machine-readable shape carries the same
  # remediation, not just the human-readable text.
  local json_out
  json_out="$(node "$GATE" --state "$absent" --json 2>&1)" || true
  assert_payload_contains "$json_out" '"reason": "state_unreadable"' \
    "TEST-10 (json): absent STATE must report state_unreadable" || return 1
  assert_payload_contains "$json_out" "check-state.mjs --repair" \
    "TEST-10 (json): absent STATE must carry the repair command in its remediation array" || return 1

  # Case B — present but genuinely broken: no last_validation: block at all
  # (garbage content), so readValidationBlock returns null and evaluateGate
  # reports validation_block_unreadable, a DIFFERENT reason than Case A's.
  local corrupt="$TEST_DIR/corrupt.yaml"
  printf ': : : garbage {{{ not yaml at all\n' > "$corrupt"
  run_gate "$corrupt"
  expect_rc 1 "TEST-10 corrupt STATE"
  assert_payload_contains "$GATE_OUT" "reason=validation_block_unreadable" \
    "TEST-10: present-but-broken STATE must keep the distinct block_unreadable reason" || return 1
  assert_payload_not_contains "$GATE_OUT" "reason=state_unreadable" \
    "TEST-10: present-but-broken STATE must NOT be reported as absent" || return 1
  assert_payload_not_contains "$GATE_OUT" "check-state.mjs --repair" \
    "TEST-10: present-but-broken STATE must NOT suggest --repair (it would silently do nothing to an existing file)" || return 1

  log_pass "TEST-10 absent STATE names the bootstrap route (text and json); present-but-broken STATE keeps its own distinct reason with no --repair suggestion"
}

# --- the archive lane: fixture builder ----------------------------------------
# spec-metrics-flush-invalidates-pr-precondition. Every archive arm starts from
# a STATE the REAL metrics-flush.mjs produced: the reset note, the re-stamped
# `run_at_utc` and the METRICS.jsonl line all come out of ONE `nowIso` in ONE
# transaction, and the gate cross-checks all three. A hand-built note would
# test the mock — it could never prove the folded block scalar round-trips the
# grammar, nor that the writer and the reader agree on the instant.
ARCHIVED_REF="ARCH-1"
HOLD_REF="ARCH-2"
SWEPT_REF="ARCH-3"
FLUSH_NOW="2026-08-30T09:00:00Z"
FLUSH_DAY="2026-08-30"
ARCHIVE_SENTINEL_TOKEN="[AAI-VALIDATION-ARCHIVED"

# mk_flushed <name> [focus-ref] -> echoes the repo dir. `focus-ref` defaults to
# the flushed ref; pass `null` for the scope-less shape. The second work item
# is what keeps the flush on the PARTIAL branch (a full reset nulls
# current_focus, and branch-guard.mjs refuses before the gate is ever reached).
#
# Five OPTIONAL env overrides exist for TEST-17 alone, each defaulting to the
# value every other arm already relied on, so TEST-11..16 are byte-unchanged:
#   MK_VSTATUS / MK_VREF     — last_validation.status / ref_id (pass/$ARCHIVED_REF)
#   MK_REVIEW_REQUIRED       — code_review.required (false)
#   MK_SWEPT                 — a THIRD work item, `done`, with its own metrics
#                              entry, plus `--sweep` and a durable
#                              work_item_closed event for every done ref, so
#                              the flush's sweep gate is the one that fires
#                              (empty = the default gate only, as before)
#   MK_RESUME                — puts the ref in the ledger BEFORE the measured
#                              flush, so metrics-flush takes its RESUME branch
#                              (`inLedger.has(ref)`) instead of either gate:
#                                crash   — a first flush killed after the ledger
#                                          append (AAI_FLUSH_INJECT_CRASH, the
#                                          real fault hook TEST-107 uses); the
#                                          MEASURED flush is a plain re-run
#                                cheat   — a pre-existing same-day PASS line for
#                                          $ARCHIVED_REF; no crash, no --sweep
#                              (empty = one flush, as before)
mk_flushed() {
  local name="$1" focus="${2:-$ARCHIVED_REF}" d fec=0
  local vstatus="${MK_VSTATUS:-pass}" vref="${MK_VREF:-$ARCHIVED_REF}"
  local review_required="${MK_REVIEW_REQUIRED:-false}" swept="${MK_SWEPT:-}"
  local resume="${MK_RESUME:-}"
  d="$TEST_DIR/$name"
  rm -rf "$d"; mkdir -p "$d/docs/ai" "$d/docs/issues"
  printf '# ledger comment header\n' > "$d/docs/ai/METRICS.jsonl"
  printf 'schema_version: 2\nmodels: {}\n' > "$d/PRICING.yaml"
  # The optional third item is spliced in as a LEADING-newline chunk so an
  # empty $swept leaves the fixture byte-identical to what TEST-11..16 built.
  local swept_item="" swept_metrics="" sweep_flag=""
  if [[ -n "$swept" ]]; then
    swept_item="
  - ref_id: $swept
    status: done
    phase: validation
    primary_path: docs/issues/${swept}.md"
    swept_metrics="
    $swept:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-08-30T07:20:00Z
          ended_utc: 2026-08-30T07:30:00Z
          duration_seconds: 600
          tokens_in: 1000
          tokens_out: 100
          cost_usd: 0.5"
    sweep_flag="--sweep"
    : > "$d/docs/ai/EVENTS.jsonl"
    local cref
    for cref in "$ARCHIVED_REF" "$swept"; do
      printf '{"v":1,"ts":"2026-08-30T08:00:00Z","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' \
        "$cref" >> "$d/docs/ai/EVENTS.jsonl"
    done
  fi
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_issue
  ref_id: $focus
  primary_path: docs/issues/${ARCHIVED_REF}.md
active_work_items:
  - ref_id: $ARCHIVED_REF
    status: done
    phase: validation
    primary_path: docs/issues/${ARCHIVED_REF}.md${swept_item}
  - ref_id: $HOLD_REF
    status: in_progress
    phase: implementation
    primary_path: docs/issues/${HOLD_REF}.md
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: $review_required
  status: not_run
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: $vstatus
  run_at_utc: 2026-08-30T08:00:00Z
  ref_id: $vref
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    $ARCHIVED_REF:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-08-30T07:00:00Z
          ended_utc: 2026-08-30T07:10:00Z
          duration_seconds: 600
          tokens_in: 1000
          tokens_out: 100
          cost_usd: 0.5${swept_metrics}

updated_at_utc: 2026-08-30T08:30:00Z
YAML
  # RESUME SETUP — get $ARCHIVED_REF into the ledger WITHOUT committing STATE,
  # which is the one shape that makes the measured flush take its resume
  # branch. Both routes are real: `crash` is the fault hook TEST-107 already
  # exercises; `cheat` is a same-day ledger line that simply already exists.
  if [[ "$resume" == cheat ]]; then
    printf '{"date_utc":"%s","ref_id":"%s","title":"pre-existing same-day line","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":0},"strategy":"tdd","reliability":null,"verdict":"PASS"}\n' \
      "$FLUSH_DAY" "$ARCHIVED_REF" >> "$d/docs/ai/METRICS.jsonl"
  fi
  if [[ "$resume" == crash ]]; then
    local cec=0
    (cd "$PROJECT_ROOT" && AAI_FLUSH_INJECT_CRASH=after-ledger node .aai/scripts/metrics-flush.mjs \
      --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
      --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
      --events "$d/docs/ai/EVENTS.jsonl" --now "$FLUSH_NOW" $sweep_flag \
      > "$d/crash.log" 2>&1) || cec=$?
    [[ "$cec" != 0 ]] \
      || { echo "mk_flushed($name): the injected crash must NOT exit 0: $(cat "$d/crash.log")" >&2; return 1; }
    grep -qE "^ {4}${ARCHIVED_REF}:" "$d/docs/ai/STATE.yaml" \
      || { echo "mk_flushed($name): STATE must still carry $ARCHIVED_REF pre-resume (the crash is before the commit)" >&2; return 1; }
    # The MEASURED flush is a PLAIN re-run — no --sweep, nothing but cleanup.
    sweep_flag=""
  fi
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now "$FLUSH_NOW" $sweep_flag \
    > "$d/flush.log" 2>&1) || fec=$?
  [[ "$fec" == 0 ]] \
    || { echo "mk_flushed($name): the REAL flush must exit 0 (got $fec): $(cat "$d/flush.log")" >&2; return 1; }
  grep -qF "Partial-flush reset applied" "$d/flush.log" \
    || { echo "mk_flushed($name): the PARTIAL reset must have fired: $(cat "$d/flush.log")" >&2; return 1; }
  echo "$d"
}

# ledger_field <metrics-path> — echoes "<ref_id>|<verdict>|<date_utc>" of the
# single flushed entry, so an arm can mutate exactly one of the three bindings.
ledger_field() {
  node -e '
    const fs = require("fs");
    const l = fs.readFileSync(process.argv[1], "utf8").split("\n").filter((x) => x.trim() && !x.startsWith("#"));
    const e = JSON.parse(l[0]);
    console.log(`${e.ref_id}|${e.verdict}|${e.date_utc}`);
  ' "$1"
}

# rewrite_ledger <metrics-path> <key> <value> — rewrites ONE field of the one
# flushed entry, leaving the record otherwise byte-identical. The negative
# controls need to change exactly one binding at a time.
rewrite_ledger() {
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    const raw = fs.readFileSync(p, "utf8").split("\n");
    const out = raw.map((l) => {
      if (!l.trim() || l.startsWith("#")) return l;
      const e = JSON.parse(l);
      e[process.argv[2]] = process.argv[3];
      return JSON.stringify(e);
    });
    fs.writeFileSync(p, out.join("\n"));
  ' "$1" "$2" "$3"
}

# --- TEST-11 -----------------------------------------------------------------
# THE SEAM (Spec-AC-02). The intake's block: the flush archives the PASS, the
# gate reads `not_run` and refuses a ride that DID validate. This arm runs the
# REAL flush and then the REAL gate over the STATE and ledger it produced —
# nothing hand-built on either side — and the gate must open by its own named
# reason. The negative control strips ONLY the archive record from the note
# (the ledger PASS stays put), proving it is the record that opens the gate
# and not the mere existence of a ledger line.
test_11_archived_pass_opens() {
  log_info "TEST-11: a real flush followed by the real gate opens on the durable ledger PASS..."
  local d
  d="$(mk_flushed arch_ok)" || log_fail "TEST-11: fixture build failed"
  local sp="$d/docs/ai/STATE.yaml"

  # PREMISE: the flush really did invalidate the live verdict. Without this the
  # arm would be passing on `status: pass` and prove nothing at all.
  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$sp" > "$d/lv.block"
  grep -qE '^  status: not_run$' "$d/lv.block" \
    || log_fail "TEST-11 premise: the flush must have reset last_validation to not_run: $(cat "$d/lv.block")"
  grep -qE '^  ref_id: null$' "$d/lv.block" \
    || log_fail "TEST-11 premise: the flush must have nulled last_validation.ref_id: $(cat "$d/lv.block")"

  run_gate "$sp"
  expect_rc 0 "TEST-11 archived pass"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=validation_archived_pass" \
    "TEST-11: the archived PASS must open the gate by its own named reason" || return 1
  assert_payload_contains "$GATE_OUT" "status=not_run" \
    "TEST-11: the reported status must stay not_run — the archive never dresses itself as a pass" || return 1
  assert_payload_contains "$GATE_OUT" "scope_ref=$ARCHIVED_REF" \
    "TEST-11: the scope must resolve from current_focus once the flush nulled last_validation.ref_id" || return 1
  assert_payload_contains "$GATE_OUT" "archive_ref=$ARCHIVED_REF archive_at=$FLUSH_NOW" \
    "TEST-11: the gate must echo WHICH record it honoured and WHEN it was archived" || return 1

  # NEGATIVE CONTROL — the record text, and NOTHING else, cut out of the file
  # (a surgical strip rather than a state.mjs rewrite, because set-validation
  # requires --status and would re-stamp run_at_utc, changing two things at
  # once). The ledger PASS, the reset prose and the instant all stay exactly as
  # the flush left them, so the ONLY variable between the two runs is the
  # record itself.
  local before_at after_at
  before_at="$(node -e 'const m=require("fs").readFileSync(process.argv[1],"utf8").match(/^  run_at_utc: (\S+)$/m);console.log(m?m[1]:"MISSING")' "$sp")"
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    fs.writeFileSync(p, fs.readFileSync(p, "utf8").replace(/ *\[AAI-VALIDATION-ARCHIVED[^\]]*\]/g, ""));
  ' "$sp"
  after_at="$(node -e 'const m=require("fs").readFileSync(process.argv[1],"utf8").match(/^  run_at_utc: (\S+)$/m);console.log(m?m[1]:"MISSING")' "$sp")"
  [[ "$before_at" == "$after_at" && "$before_at" != "MISSING" ]] \
    || log_fail "TEST-11 control: run_at_utc must be untouched by the strip (before=$before_at after=$after_at)"
  assert_payload_not_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN" \
    "TEST-11 control: the record must actually be gone from the note" || return 1
  [[ "$(ledger_field "$d/docs/ai/METRICS.jsonl")" == "$ARCHIVED_REF|PASS|$FLUSH_DAY" ]] \
    || log_fail "TEST-11 control: the ledger PASS must still be there — it is what must NOT be sufficient on its own"
  run_gate "$sp"
  expect_rc 1 "TEST-11 control (record stripped, ledger PASS still there)"
  assert_payload_contains "$GATE_OUT" "reason=validation_not_run_no_waiver" \
    "TEST-11 control: a ledger PASS with no archive record must block exactly as a bare not_run does" || return 1
  log_pass "TEST-11 the real flush-to-gate seam opens on validation_archived_pass; stripping the record alone re-blocks it"
}

# --- TEST-12 -----------------------------------------------------------------
# THE INTAKE'S NEGATIVE CONTROL (Spec-AC-03). The record is a CLAIM; the ledger
# is the proof. All four sub-cases keep a perfectly well-formed record and
# break exactly one of the three ledger bindings — presence, verdict, day — or
# duplicate the proof. A gate that trusted the note alone passes none of them.
test_12_archive_needs_ledger_pass() {
  log_info "TEST-12: an archive record with no single matching ledger PASS is refused by name..."
  local d sp

  # (a) no ledger entry at all.
  d="$(mk_flushed arch_noledger)" || log_fail "TEST-12(a): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  printf '# ledger comment header\n' > "$d/docs/ai/METRICS.jsonl"
  run_gate "$sp"
  expect_rc 1 "TEST-12(a) empty ledger"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=archive_no_ledger_pass" \
    "TEST-12(a): a record whose scope has no ledger PASS must be refused by name" || return 1

  # (b) the entry exists but its verdict is not PASS.
  d="$(mk_flushed arch_notpass)" || log_fail "TEST-12(b): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  [[ "$(ledger_field "$d/docs/ai/METRICS.jsonl")" == "$ARCHIVED_REF|PASS|$FLUSH_DAY" ]] \
    || log_fail "TEST-12(b) premise: the flushed entry must be $ARCHIVED_REF|PASS|$FLUSH_DAY — got $(ledger_field "$d/docs/ai/METRICS.jsonl")"
  rewrite_ledger "$d/docs/ai/METRICS.jsonl" verdict FAIL
  run_gate "$sp"
  expect_rc 1 "TEST-12(b) non-PASS verdict"
  assert_payload_contains "$GATE_OUT" "reason=archive_no_ledger_pass" \
    "TEST-12(b): a ledger entry that is not a PASS must not open the gate" || return 1

  # (c) the entry is a PASS for the right ref but on a DIFFERENT day — the
  # inherited-record shape a ref check alone would wave through.
  d="$(mk_flushed arch_otherday)" || log_fail "TEST-12(c): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  rewrite_ledger "$d/docs/ai/METRICS.jsonl" date_utc 2026-08-29
  run_gate "$sp"
  expect_rc 1 "TEST-12(c) PASS on another day"
  assert_payload_contains "$GATE_OUT" "reason=archive_no_ledger_pass" \
    "TEST-12(c): a PASS whose date_utc does not match the record's day must not open the gate" || return 1

  # (d) two matching PASS entries: which ride is being proven is no longer
  # decidable, so the gate refuses rather than picking one.
  d="$(mk_flushed arch_dupledger)" || log_fail "TEST-12(d): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/dup.line"
  cat "$d/dup.line" >> "$d/docs/ai/METRICS.jsonl"
  run_gate "$sp"
  expect_rc 1 "TEST-12(d) duplicated ledger PASS"
  assert_payload_contains "$GATE_OUT" "reason=archive_ledger_ambiguous" \
    "TEST-12(d): two matching ledger PASS entries must be refused as ambiguous, never resolved by picking one" || return 1
  log_pass "TEST-12 the ledger PASS is load-bearing: absent, non-PASS, wrong-day and duplicated all refuse by name"
}

# --- TEST-13 -----------------------------------------------------------------
# RECENCY, NOT ref_id ALONE (Spec-AC-04). `state.mjs set-validation` re-stamps
# `run_at_utc` on any call carrying a --status while PRESERVING notes — the
# exact call the NEXT ride makes. The record therefore goes stale the moment a
# later ride writes a status, and an inherited record can never open the gate
# for a ride that did not earn it.
test_13_archive_goes_stale_on_restamp() {
  log_info "TEST-13: a later set-validation re-stamps run_at_utc and the inherited record goes stale..."
  local d
  d="$(mk_flushed arch_stale)" || log_fail "TEST-13: fixture build failed"
  local sp="$d/docs/ai/STATE.yaml"

  run_gate "$sp"
  expect_rc 0 "TEST-13 premise (the record opens the gate before the re-stamp)"

  # The next ride's bare status write. No --notes: the record is INHERITED.
  reset_validation_ref "$sp" "$ARCHIVED_REF" || log_fail "TEST-13: state.mjs refused the re-stamp"

  # PREMISE: the record is still physically there and the ledger PASS is still
  # there — the ONLY thing that changed is the instant beside it.
  assert_payload_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN v1 ref=$ARCHIVED_REF at=$FLUSH_NOW" \
    "TEST-13 premise: the record must survive the re-stamp verbatim, or staleness is not what is being tested" || return 1
  [[ "$(ledger_field "$d/docs/ai/METRICS.jsonl")" == "$ARCHIVED_REF|PASS|$FLUSH_DAY" ]] \
    || log_fail "TEST-13 premise: the ledger PASS must be untouched"

  run_gate "$sp"
  expect_rc 1 "TEST-13 re-stamped run_at_utc"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=archive_stale" \
    "TEST-13: a record whose at no longer equals run_at_utc must be refused as stale, by name" || return 1
  log_pass "TEST-13 an inherited archive record goes stale the instant a later ride writes a status"
}

# --- TEST-14 -----------------------------------------------------------------
# SCOPE BINDING (Spec-AC-05), the same leak v2 closed for waivers. A record
# names ONE ride; a different ride in hand must be refused BY NAME, never
# silently, and a ride with no scope at all is the worst case of the same bug.
test_14_archive_ref_binding() {
  log_info "TEST-14: a record naming another ride, and a ride with no scope at all, are both refused by name..."
  local d
  d="$(mk_flushed arch_mismatch)" || log_fail "TEST-14: fixture build failed"
  local sp="$d/docs/ai/STATE.yaml"

  run_gate_ref "$sp" "$HOLD_REF"
  expect_rc 1 "TEST-14 record names another ride"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=archive_ref_mismatch" \
    "TEST-14: a record issued for another ride must be refused by name, not as a generic no-waiver" || return 1
  assert_payload_contains "$GATE_OUT" "scope_ref=$HOLD_REF" \
    "TEST-14: the gate must say which scope it was asked about" || return 1

  # Control: the SAME state, asked about the ride the record actually names.
  run_gate_ref "$sp" "$ARCHIVED_REF"
  expect_rc 0 "TEST-14 control (the ride the record names)"
  assert_payload_contains "$GATE_OUT" "reason=validation_archived_pass" \
    "TEST-14 control: the named ride must still open — only the scope differs between these two runs" || return 1

  # No scope anywhere: last_validation.ref_id nulled by the flush AND
  # current_focus.ref_id null. A record with no context to check against is
  # refused, exactly as a scope-less waiver is.
  d="$(mk_flushed arch_noscope null)" || log_fail "TEST-14: scope-less fixture build failed"
  run_gate "$d/docs/ai/STATE.yaml"
  expect_rc 1 "TEST-14 no scope at all"
  assert_payload_contains "$GATE_OUT" "reason=archive_scope_unknown" \
    "TEST-14: a record with no scope to check against must be refused by its own name" || return 1
  log_pass "TEST-14 the archive record is scope-bound: another ride refuses, no ride at all refuses, the named ride opens"
}

# --- TEST-15 -----------------------------------------------------------------
# FAIL-CLOSED ON A BROKEN RECORD (Spec-AC-06). A sentinel that is PRESENT but
# whose grammar is not satisfied must be refused BY NAME and must never fall
# through to a silent open. A future-version record is refused under its OWN
# name — "this predates the binding" and "somebody mistyped" are different
# facts, the same doctrine the waiver grammar already applies.
test_15_archive_grammar_fail_closed() {
  log_info "TEST-15: a present-but-broken archive sentinel is refused by name, never silently honoured..."
  local sp
  local bad_instant="[AAI-VALIDATION-ARCHIVED v1 ref=$SCOPE_REF at=yesterday]"
  local impossible="[AAI-VALIDATION-ARCHIVED v1 ref=$SCOPE_REF at=2026-13-45T99:00:00Z]"
  local future_ver="[AAI-VALIDATION-ARCHIVED v2 ref=$SCOPE_REF at=$AT]"
  local doubled="[AAI-VALIDATION-ARCHIVED v1 ref=$SCOPE_REF at=$AT] [AAI-VALIDATION-ARCHIVED v1 ref=$SCOPE_REF at=$AT]"

  sp="$(write_state arch_badinstant not_run "reset after flush of $SCOPE_REF $bad_instant")"
  run_gate "$sp"
  expect_rc 1 "TEST-15 unparseable instant"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE blocked reason=archive_malformed" \
    "TEST-15: a sentinel the grammar cannot parse must be REFUSED by name" || return 1

  sp="$(write_state arch_impossible not_run "reset after flush of $SCOPE_REF $impossible")"
  run_gate "$sp"
  expect_rc 1 "TEST-15 calendar-impossible instant"
  assert_payload_contains "$GATE_OUT" "reason=archive_malformed" \
    "TEST-15: an instant that matches the shape but is not a real date must be REFUSED" || return 1

  sp="$(write_state arch_futurever not_run "reset after flush of $SCOPE_REF $future_ver")"
  run_gate "$sp"
  expect_rc 1 "TEST-15 non-current version"
  assert_payload_contains "$GATE_OUT" "reason=archive_obsolete_version" \
    "TEST-15: a non-current version must be refused under its OWN name, never degraded to malformed" || return 1

  sp="$(write_state arch_doubled not_run "reset after flush of $SCOPE_REF $doubled")"
  run_gate "$sp"
  expect_rc 1 "TEST-15 duplicated record"
  assert_payload_contains "$GATE_OUT" "reason=archive_ambiguous" \
    "TEST-15: two records for one ref must be refused as ambiguous, never resolved by picking one" || return 1
  log_pass "TEST-15 broken, calendar-impossible, future-version and duplicated records all refuse by their own names"
}

# --- TEST-16 -----------------------------------------------------------------
# THE LANE MAY ONLY OPEN (Spec-AC-07). The flush PRESERVES an unflushed waiver
# into the very note it writes the archive records to, and by construction that
# waiver names a ref that was NOT flushed — a different ref from every record
# beside it. An archive-decides-terminally rule would therefore have BLOCKED a
# scope whose own preserved waiver opens the gate today. This arm is that
# regression, pinned in both directions: a refused archive record must leave
# the waiver lane running exactly as it did before this change.
test_16_archive_never_blocks_a_waiver() {
  log_info "TEST-16: a note whose archive record is refused still opens on its own waiver..."
  local sp
  local foreign="[AAI-VALIDATION-ARCHIVED v1 ref=OTHER-RIDE at=$AT]"
  local broken="[AAI-VALIDATION-ARCHIVED v1 ref=$SCOPE_REF at=nonsense]"

  # The real preserved-waiver shape: prose, the waiver, and a record for a ref
  # the waiver does not name.
  sp="$(write_state arch_with_waiver not_run "reset after flush of OTHER-RIDE — PRESERVED unflushed validation waiver: $OPERATOR_RECORD $foreign")"
  run_gate "$sp"
  expect_rc 0 "TEST-16 preserved waiver beside a foreign archive record"
  assert_payload_contains "$GATE_OUT" "VALIDATION-GATE open reason=waived_by_operator" \
    "TEST-16: a preserved waiver must still open the gate when a foreign archive record sits beside it" || return 1

  # And a record the archive lane refuses OUTRIGHT still must not become
  # terminal: the waiver lane runs and opens.
  sp="$(write_state arch_broken_with_waiver not_run "$OPERATOR_RECORD $broken")"
  run_gate "$sp"
  expect_rc 0 "TEST-16 broken archive record beside a valid waiver"
  assert_payload_contains "$GATE_OUT" "reason=waived_by_operator" \
    "TEST-16: an archive refusal must never take precedence over a waiver that opens today" || return 1

  # Symmetrically: a BROKEN WAIVER beside a good record keeps its own waiver
  # refusal. The archive lane adds an opening, never a loosening.
  local broken_waiver="[AAI-VALIDATION-WAIVER v2 by=operator ref=$SCOPE_REF at=$AT reason=\"\"]"
  sp="$(write_state arch_with_broken_waiver not_run "$broken_waiver $foreign")"
  run_gate "$sp"
  expect_rc 1 "TEST-16 broken waiver beside an archive record"
  assert_payload_contains "$GATE_OUT" "reason=waiver_empty_reason" \
    "TEST-16: an existing waiver refusal must survive byte-for-byte — the archive lane never overrides it" || return 1
  log_pass "TEST-16 the archive lane only ever OPENS: preserved waivers still open, waiver refusals still refuse"
}

# --- TEST-17 -----------------------------------------------------------------
# ONLY A REF THAT SATISFIED THE DEFAULT GATE MAY BE ARCHIVED (Spec-AC-09). The
# archive record claims a validation PASS existed and merely MOVED to the
# ledger. Only metrics-flush's DEFAULT gate establishes that. Two other lanes
# reach the same partial reset and neither establishes it:
#   * `--sweep` substitutes a durable `work_item_closed` event plus
#     `status: done` for the PASS — a sound basis for RETIRING stranded metrics
#     and no basis at all for opening the PR gate;
#   * the RESUME branch (`inLedger.has(ref)`) short-circuits BEFORE either gate
#     is evaluated and completes the reset for any ref that merely already HAS a
#     ledger line, whatever wrote it.
# Minting a record on either lane hands a ride that never validated an opening
# it never had — and because the same reset also zeroes `code_review.required`,
# BOTH SKILL_PR preconditions would be satisfied for a ride that satisfied
# neither.
#
# Five arms, two of them non-vacuity controls in OPPOSITE directions:
#  (a) harm case, sweep lane, end to end on the real flush and the real gate:
#      the verdict must be the one base gives (`validation_not_run_no_waiver`).
#  (b) control — one flush that sweeps ONE ref and default-flushes ANOTHER into
#      the same partial reset. Exactly one record, naming the DEFAULT-flushed
#      ref. A fix that stopped archiving whenever `--sweep` was passed fails (b).
#  (c) harm case, resume lane via the sweep: TEST-107's own crash-then-resume
#      fixture. A resumed ref is never in `sweptRefs`, so subtracting the sweep
#      set cannot reach it — this arm is what forces a POSITIVE eligibility
#      property rather than a subtraction.
#  (d) harm case, resume lane with NO sweep and NO crash: a pre-existing
#      same-day ledger line for the focus ref plus a plain flush.
#  (e) control — a crash-resume of a ride that DOES satisfy the default gate
#      must STILL archive. A fix that never archived on resume fails (e), and
#      would break SPEC-0068's designed crash-recovery path.
test_17_swept_ref_is_never_archived() {
  log_info "TEST-17: neither the sweep gate nor the resume branch mints an archive record..."
  local d sp

  # (a) THE HARM CASE. Nothing validated: last_validation not_run / ref_id
  # null, code_review REQUIRED and not_run — the shape base refuses.
  d="$(MK_VSTATUS=not_run MK_VREF=null MK_REVIEW_REQUIRED=true MK_SWEPT=$SWEPT_REF \
        mk_flushed swept_norecord)" || log_fail "TEST-17(a): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"

  # PREMISE: the sweep really did fire and really did retire the metrics — the
  # arm must not be passing because the flush quietly did nothing.
  grep -qF "Flushed: $ARCHIVED_REF" "$d/flush.log" \
    || log_fail "TEST-17(a) premise: the sweep must have flushed $ARCHIVED_REF: $(cat "$d/flush.log")"
  [[ "$(grep -cv -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" || true)" == 2 ]] \
    || log_fail "TEST-17(a) premise: the sweep must still append both ledger entries — this fix retires nothing: $(cat "$d/docs/ai/METRICS.jsonl")"
  ! grep -qE "^ {4}${ARCHIVED_REF}:" "$sp" \
    || log_fail "TEST-17(a) premise: the swept metrics entry must be gone from STATE (the sweep's whole job)"

  # The reset itself is BYTE-UNCHANGED: the prose still names every reset ref.
  assert_payload_contains "$(cat "$sp")" "reset after flush of" \
    "TEST-17(a): the partial-reset prose must be untouched — only the record is withheld" || return 1
  assert_payload_not_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN" \
    "TEST-17(a): a ref that reached the ledger through the SWEEP gate must mint NO archive record" || return 1

  run_gate "$sp"
  expect_rc 1 "TEST-17(a) swept ref, nothing validated"
  assert_payload_contains "$GATE_OUT" "reason=validation_not_run_no_waiver" \
    "TEST-17(a): a swept ride must reach the PR gate with exactly the verdict it had before the flush" || return 1
  assert_payload_not_contains "$GATE_OUT" "validation_archived_pass" \
    "TEST-17(a): the archive lane must never open for a ride that never validated" || return 1

  # (b) NON-VACUITY CONTROL. One flush, one partial reset, two refs: $SWEPT_REF
  # satisfies the DEFAULT gate (the live PASS names it) and $ARCHIVED_REF only
  # the sweep gate. Both are reset; exactly one is archived.
  d="$(MK_VSTATUS=pass MK_VREF=$SWEPT_REF MK_SWEPT=$SWEPT_REF \
        mk_flushed swept_mixed)" || log_fail "TEST-17(b): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  # The reset writes the SAME note into both `last_validation` and
  # `code_review`, so the count is taken over one block, not the whole file.
  local lv_block="$d/lv17.block" nrec=0
  sed -n '/^last_validation:/,/^human_input:/p' "$sp" > "$lv_block"
  nrec="$(grep -c -F "$ARCHIVE_SENTINEL_TOKEN" "$lv_block" || true)"
  [[ "$nrec" == 1 ]] \
    || log_fail "TEST-17(b): exactly one archive record must survive a mixed sweep — got $nrec: $(cat "$lv_block")"
  assert_payload_contains "$(cat "$lv_block")" "[AAI-VALIDATION-ARCHIVED v1 ref=$SWEPT_REF at=$FLUSH_NOW]" \
    "TEST-17(b): the DEFAULT-flushed ref must still be archived — the fix withholds records per ref, it does not disable the lane" || return 1
  assert_payload_not_contains "$(cat "$lv_block")" "ref=$ARCHIVED_REF at=" \
    "TEST-17(b): the SWEPT ref must not appear in any archive record beside it" || return 1
  assert_payload_contains "$(cat "$lv_block")" "reset after flush of" \
    "TEST-17(b): both refs must still be named by the reset prose" || return 1

  # And the gate agrees per ref: open for the one that validated, blocked for
  # the one that was only swept.
  run_gate_ref "$sp" "$SWEPT_REF"
  expect_rc 0 "TEST-17(b) default-flushed ref"
  assert_payload_contains "$GATE_OUT" "reason=validation_archived_pass" \
    "TEST-17(b): the default-flushed ref must still open on its archived PASS" || return 1
  # The swept ref resolves its scope from current_focus and finds only the
  # SIBLING's record, so it blocks by the lane's own scope-mismatch name (the
  # binding TEST-14 pins) rather than the generic no-waiver token. Either way
  # it blocks — what matters is that no record ever names it.
  run_gate "$sp"
  expect_rc 1 "TEST-17(b) swept ref (resolved from current_focus)"
  assert_payload_contains "$GATE_OUT" "reason=archive_ref_mismatch" \
    "TEST-17(b): the swept ref must stay blocked even while a sibling record sits in the same note" || return 1
  assert_payload_not_contains "$GATE_OUT" "open reason=" \
    "TEST-17(b): nothing in a mixed sweep may open the gate for the swept ref" || return 1

  # (c) THE RESUME LANE, VIA THE SWEEP. `metrics-flush.mjs` short-circuits on
  # `inLedger.has(ref)` BEFORE either gate is evaluated, so a ref that reached
  # the ledger through the sweep and was then resumed is not in `sweptRefs` at
  # all — subtracting the sweep set cannot reach it. The fixture is TEST-107's
  # own designed state (SPEC-0068 Spec-AC-06: crash-then-resume is
  # cleanup-only): --sweep, killed after the ledger append, then a plain
  # re-flush. Nothing validated at any point, so the verdict must be the one
  # base gives.
  d="$(MK_VSTATUS=not_run MK_VREF=null MK_REVIEW_REQUIRED=true MK_SWEPT=$SWEPT_REF MK_RESUME=crash \
        mk_flushed swept_resume)" || log_fail "TEST-17(c): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"

  # PREMISE: the measured flush really took the RESUME branch and really
  # appended nothing — the arm must not pass because the flush did no work.
  grep -qF "RESUME $ARCHIVED_REF" "$d/flush.log" \
    || log_fail "TEST-17(c) premise: the measured flush must RESUME $ARCHIVED_REF: $(cat "$d/flush.log")"
  ! grep -qF "Flushed:" "$d/flush.log" \
    || log_fail "TEST-17(c) premise: a resume is cleanup-only — it must append no ledger line: $(cat "$d/flush.log")"
  [[ "$(grep -cv -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" || true)" == 2 ]] \
    || log_fail "TEST-17(c) premise: the pre-crash sweep's two ledger lines must survive un-duplicated: $(cat "$d/docs/ai/METRICS.jsonl")"
  assert_payload_contains "$(cat "$sp")" "reset after flush of" \
    "TEST-17(c): the partial-reset prose must be untouched — only the record is withheld" || return 1
  assert_payload_not_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN" \
    "TEST-17(c): a ref RESUMED into the ledger without satisfying the default gate must mint NO archive record" || return 1

  run_gate "$sp"
  expect_rc 1 "TEST-17(c) resumed swept ref, nothing validated"
  assert_payload_contains "$GATE_OUT" "reason=validation_not_run_no_waiver" \
    "TEST-17(c): a resumed swept ride must reach the PR gate with exactly the verdict it had before the flush" || return 1
  assert_payload_not_contains "$GATE_OUT" "validation_archived_pass" \
    "TEST-17(c): the archive lane must never open for a ride that never validated, resumed or not" || return 1

  # (d) THE RESUME LANE WITHOUT A SWEEP AND WITHOUT A CRASH. A same-day PASS
  # line for the focus ref already sits in METRICS.jsonl while STATE still
  # carries the metrics entry; a plain flush then resumes it. No `--sweep` is
  # passed anywhere in this arm, which is what proves the defect is the RESUME
  # branch itself and not a sweep-only carve-out.
  d="$(MK_VSTATUS=not_run MK_VREF=null MK_REVIEW_REQUIRED=true MK_RESUME=cheat \
        mk_flushed plain_resume)" || log_fail "TEST-17(d): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"

  grep -qF "RESUME $ARCHIVED_REF" "$d/flush.log" \
    || log_fail "TEST-17(d) premise: the flush must RESUME $ARCHIVED_REF: $(cat "$d/flush.log")"
  [[ ! -e "$d/crash.log" ]] \
    || log_fail "TEST-17(d) premise: this arm must involve no crashed flush at all"
  [[ "$(grep -cv -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" || true)" == 1 ]] \
    || log_fail "TEST-17(d) premise: exactly the pre-existing line, no duplicate: $(cat "$d/docs/ai/METRICS.jsonl")"
  assert_payload_not_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN" \
    "TEST-17(d): a plain flush that only RESUMES a ledger line must mint no archive record" || return 1

  run_gate "$sp"
  expect_rc 1 "TEST-17(d) resumed ref, no sweep, no crash, nothing validated"
  assert_payload_contains "$GATE_OUT" "reason=validation_not_run_no_waiver" \
    "TEST-17(d): a pre-existing ledger line must not become a PR-gate opening" || return 1

  # (e) SECOND NON-VACUITY CONTROL. The resume lane is not the defect — an
  # UNVALIDATED resume is. A ride that genuinely satisfies the default gate and
  # is resumed after a crash MUST still archive, or the fix would have been
  # "never archive on resume", which breaks the very crash-recovery path
  # SPEC-0068 designed.
  d="$(MK_RESUME=crash mk_flushed validated_resume)" || log_fail "TEST-17(e): fixture build failed"
  sp="$d/docs/ai/STATE.yaml"
  grep -qF "RESUME $ARCHIVED_REF" "$d/flush.log" \
    || log_fail "TEST-17(e) premise: the measured flush must RESUME $ARCHIVED_REF: $(cat "$d/flush.log")"
  assert_payload_contains "$(cat "$sp")" "$ARCHIVE_SENTINEL_TOKEN v1 ref=$ARCHIVED_REF at=$FLUSH_NOW" \
    "TEST-17(e): a resumed ref that DOES satisfy the default gate must still be archived" || return 1
  run_gate "$sp"
  expect_rc 0 "TEST-17(e) resumed ref that genuinely validated"
  assert_payload_contains "$GATE_OUT" "reason=validation_archived_pass" \
    "TEST-17(e): the archive lane must still open for a genuinely-validated resumed ride" || return 1

  log_pass "TEST-17 neither the sweep gate nor the resume branch mints an opening; refs that satisfy the DEFAULT gate still archive"
}

# --- runner ------------------------------------------------------------------

ALL_TESTS="01_bare_not_run_blocks 02_operator_waiver_opens 03_empty_reason_refused 04_self_waived_marked_distinctly 05_two_records_block_ambiguous 06_waiver_does_not_leak_across_refs 07_v1_record_refused_by_name 08_waiver_survives_flush_into_report 09_unflushed_waiver_is_loud_not_lost 10_absent_vs_corrupt_state 11_archived_pass_opens 12_archive_needs_ledger_pass 13_archive_goes_stale_on_restamp 14_archive_ref_binding 15_archive_grammar_fail_closed 16_archive_never_blocks_a_waiver 17_swept_ref_is_never_archived"

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
