#!/usr/bin/env bash
#
# Test: aai-round-budget
# (docs/specs/SPEC-DRAFT-spec-factory-round-cap.md, TEST-3600..3603 in this batch;
# TEST-3604..3613 are added by later runs of the same ride)
#
# The counted review round cap: .aai/scripts/round-budget.mjs counts round_reset and
# round_extension lines in EVENTS, state.mjs reset-block writes one round_reset per
# changed block and refuses at the cap (exit 5), append-event records the extensions.
# Every fixture STATE and EVENTS file sits in a temp dir, so the real ledger is never
# touched. Every function runs alone: bash tests/skills/test-aai-round-budget.sh <function>.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-round-budget"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RB="$PROJECT_ROOT/.aai/scripts/round-budget.mjs"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"
APPEND_EVENT="$PROJECT_ROOT/.aai/scripts/append-event.mjs"
TMP_ROOT=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

cleanup() { [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"; return 0; }
trap cleanup EXIT

new_tmp() { TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-round-budget.XXXXXX")"; }

# write_state <file> <ref> <validation status>: the smallest STATE reset-block accepts.
write_state() {
  cat > "$1" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: $2
  primary_path: docs/issues/CHANGE-DRAFT-$2.md
last_validation:
  status: $3
  run_at_utc: null
  ref_id: $2
  evidence_paths: []
  notes: null
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# ev_line <event> <ref> <payload json>
ev_line() {
  printf '{"v":1,"ts":"2026-11-12T00:00:00Z","actor":"t","event":"%s","ref":"%s","payload":%s}\n' "$1" "$2" "$3"
}

# reset_line <ref> <from>: one round_reset ledger line.
reset_line() { ev_line round_reset "$1" "{\"block\":\"last_validation\",\"from\":\"$2\",\"forced\":false}"; }

# run_rc <logfile> <cmd...>: run, capture stdout+stderr in the log, print the exit code.
run_rc() {
  local log="$1" rc=0
  shift
  "$@" > "$log" 2>&1 || rc=$?
  echo "$rc"
}

test_3600_status_counts() {
  new_tmp
  local ev="$TMP_ROOT/EVENTS.jsonl" out rc
  {
    reset_line RC-1 fail
    reset_line RC-1 fail
    reset_line OTHER fail
    ev_line round_extension RC-1 '{"authority":"owner","reason":"more"}'
    ev_line round_extension OTHER '{"authority":"owner","reason":"x"}'
    echo 'this is not json'
  } > "$ev"
  rc=0
  out="$(node "$RB" status --ref RC-1 --events "$ev" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3600: status exited $rc: $out"
  grep -q 'rounds: 2/3 extensions: 1 ' <<<"$out" || log_fail "TEST-3600: want rounds 2/3 extensions 1, got: $out"
  grep -q '^NOTE' <<<"$out" || log_fail "TEST-3600: want a NOTE for the malformed line, got: $out"
  node "$RB" status --ref OTHER --events "$ev" 2>&1 | grep -q 'rounds: 1/3 ' || log_fail "TEST-3600: other ref must count its own line"
  node "$RB" status --ref RC-1 --events "$TMP_ROOT/absent.jsonl" 2>&1 | grep -q 'rounds: 0/2 ' || log_fail "TEST-3600: absent EVENTS must count 0"
  log_pass "TEST-3600: status counts the ref's resets, cap 2 plus its extensions, notes a malformed line"
}

test_3601_reset_appends_round() {
  new_tmp
  local st="$TMP_ROOT/STATE.yaml" ev="$TMP_ROOT/EVENTS.jsonl" rc
  write_state "$st" RC-1 fail
  rc="$(run_rc "$TMP_ROOT/r1.log" node "$STATE_CLI" --state "$st" reset-block last_validation)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3601: reset-block exited $rc: $(cat "$TMP_ROOT/r1.log")"
  [[ -f "$ev" ]] || log_fail "TEST-3601: no EVENTS.jsonl beside the STATE file"
  [[ "$(wc -l < "$ev" | tr -d ' ')" == 1 ]] || log_fail "TEST-3601: want exactly one line, got: $(cat "$ev")"
  node -e '
    const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").trim());
    const ok = e.event === "round_reset" && e.ref === "RC-1" && e.payload.block === "last_validation"
      && e.payload.from === "fail" && e.payload.forced === false && e.v === 1 && typeof e.ts === "string";
    process.exit(ok ? 0 : 1);' "$ev" || log_fail "TEST-3601: round_reset shape wrong: $(cat "$ev")"
  rc="$(run_rc "$TMP_ROOT/r2.log" node "$STATE_CLI" --state "$st" reset-block last_validation)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3601: no-op reset exited $rc"
  [[ "$(wc -l < "$ev" | tr -d ' ')" == 1 ]] || log_fail "TEST-3601: a no-op reset must append nothing"
  write_state "$st" RC-1 pass
  rc="$(run_rc "$TMP_ROOT/r3.log" node "$STATE_CLI" --state "$st" reset-block last_validation --force)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3601: forced reset exited $rc"
  tail -1 "$ev" | grep -q '"from":"pass","forced":true' || log_fail "TEST-3601: forced reset line wrong: $(tail -1 "$ev")"
  log_pass "TEST-3601: reset-block appends one round_reset beside the STATE file, a no-op appends none"
}

test_3602_cap_refuses() {
  new_tmp
  local st="$TMP_ROOT/STATE.yaml" ev="$TMP_ROOT/EVENTS.jsonl" rc
  write_state "$st" RC-1 fail
  { reset_line RC-1 fail; reset_line RC-1 fail; reset_line OTHER fail; } > "$ev"
  cp "$st" "$TMP_ROOT/state.before"
  cp "$ev" "$TMP_ROOT/events.before"
  rc="$(run_rc "$TMP_ROOT/r.log" node "$STATE_CLI" --state "$st" reset-block last_validation)"
  [[ "$rc" == 5 ]] || log_fail "TEST-3602: want exit 5 at the cap, got $rc: $(cat "$TMP_ROOT/r.log")"
  grep -q 'REFUSED review-round-cap: 2/2' "$TMP_ROOT/r.log" || log_fail "TEST-3602: missing REFUSED line: $(cat "$TMP_ROOT/r.log")"
  grep -q 'RC-1' "$TMP_ROOT/r.log" || log_fail "TEST-3602: refusal must name the ref"
  grep -q '(1) split the ride' "$TMP_ROOT/r.log" || log_fail "TEST-3602: missing option 1"
  grep -q '(2) one more round' "$TMP_ROOT/r.log" || log_fail "TEST-3602: missing option 2"
  grep -q '(3) park the ride' "$TMP_ROOT/r.log" || log_fail "TEST-3602: missing option 3"
  cmp -s "$st" "$TMP_ROOT/state.before" || log_fail "TEST-3602: STATE changed on a refusal"
  cmp -s "$ev" "$TMP_ROOT/events.before" || log_fail "TEST-3602: EVENTS changed on a refusal"
  # A no-op reset is never refused, even at the cap.
  write_state "$st" RC-1 not_run
  rc="$(run_rc "$TMP_ROOT/n.log" node "$STATE_CLI" --state "$st" reset-block last_validation)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3602: a no-op reset at the cap must exit 0, got $rc"
  log_pass "TEST-3602: the third reset exits 5 with the menu and writes nothing"
}

test_3603_extensions() {
  new_tmp
  local st="$TMP_ROOT/STATE.yaml" ev="$TMP_ROOT/docs/ai/EVENTS.jsonl" rc
  mkdir -p "$TMP_ROOT/docs/ai"
  st="$TMP_ROOT/docs/ai/STATE.yaml"
  write_state "$st" RC-1 fail
  { reset_line RC-1 fail; reset_line RC-1 fail; } > "$ev"
  ae() { (cd "$TMP_ROOT" && node "$APPEND_EVENT" "$@"); }
  rc="$(run_rc "$TMP_ROOT/a1.log" ae --event round_extension --ref RC-1 --authority standing-a --reason "hazard introduced by the feature")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3603: standing-a extension exited $rc: $(cat "$TMP_ROOT/a1.log")"
  tail -1 "$ev" | grep -q '"event":"round_extension"' || log_fail "TEST-3603: extension line missing"
  tail -1 "$ev" | grep -q '"authority":"standing-a"' || log_fail "TEST-3603: authority not recorded"
  rc="$(run_rc "$TMP_ROOT/r.log" node "$STATE_CLI" --state "$st" reset-block last_validation)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3603: reset after one extension exited $rc: $(cat "$TMP_ROOT/r.log")"
  rc="$(run_rc "$TMP_ROOT/a2.log" ae --event round_extension --ref RC-1 --authority standing-a --reason "again")"
  [[ "$rc" == 1 ]] || log_fail "TEST-3603: second standing-a must exit 1, got $rc"
  grep -q 'STANDING DECISION (a)' "$TMP_ROOT/a2.log" || log_fail "TEST-3603: refusal must name STANDING DECISION (a): $(cat "$TMP_ROOT/a2.log")"
  local before; before="$(wc -l < "$ev")"
  rc="$(run_rc "$TMP_ROOT/a3.log" ae --event round_extension --ref RC-1 --authority owner --reason "")"
  [[ "$rc" == 1 ]] || log_fail "TEST-3603: empty reason must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a4.log" ae --event round_extension --ref RC-1 --authority owner)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3603: missing reason must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a5.log" ae --event round_extension --ref RC-1 --authority nobody --reason x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3603: unknown authority must exit 1, got $rc"
  [[ "$(wc -l < "$ev")" == "$before" ]] || log_fail "TEST-3603: a refused extension wrote a line"
  rc="$(run_rc "$TMP_ROOT/a6.log" ae --event round_extension --ref RC-1 --authority owner --reason "owner said one more")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3603: owner extension exited $rc"
  rc="$(run_rc "$TMP_ROOT/a7.log" ae --event round_extension --ref RC-1 --authority owner --reason "and another")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3603: owner extensions are not limited, exited $rc"
  log_pass "TEST-3603: standing-a once, owner unlimited, reason required, reset passes after an extension"
}

main() {
  check_deps
  test_3600_status_counts
  test_3601_reset_appends_round
  test_3602_cap_refuses
  test_3603_extensions
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
