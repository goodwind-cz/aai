#!/usr/bin/env bash
#
# Test: aai-round-budget
# (docs/specs/SPEC-DRAFT-spec-factory-round-cap.md, TEST-3600..3615;
# TEST-3612..3615 are the canon, wiring, pin and CHANGELOG rows of the same ride)
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
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac
PROJECT_ROOT="$SCRIPT_DIR/../.."
RB="$PROJECT_ROOT/.aai/scripts/round-budget.mjs"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"
APPEND_EVENT="$PROJECT_ROOT/.aai/scripts/append-event.mjs"
DISPATCH="$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs"
GATE="$PROJECT_ROOT/.aai/scripts/unattended-gate.mjs"
CHECK_OUT="$PROJECT_ROOT/.aai/scripts/check-role-output.mjs"
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
  [[ "$(node "$RB" status --ref OTHER --events "$ev" 2>&1)" == *'rounds: 1/3 '* ]] || log_fail "TEST-3600: other ref must count its own line"
  [[ "$(node "$RB" status --ref RC-1 --events "$TMP_ROOT/absent.jsonl" 2>&1)" == *'rounds: 0/2 '* ]] || log_fail "TEST-3600: absent EVENTS must count 0"
  log_pass "TEST-3600: status counts the ref's resets, cap 2 plus its extensions, notes a malformed line"
}

test_3600b_cli_through_symlink() {
  new_tmp
  mkdir -p "$TMP_ROOT/real"
  ln -s "$PROJECT_ROOT/.aai/scripts" "$TMP_ROOT/link" 2>/dev/null || log_skip "symlinks unavailable"
  local out
  out="$(node "$TMP_ROOT/link/round-budget.mjs" status --ref RC-1 --events "$TMP_ROOT/absent.jsonl" 2>&1)" || true
  [[ "$out" == *'rounds: 0/2 '* ]] || log_fail "TEST-3600: the CLI called through a symlink printed nothing useful: $out"
  log_pass "TEST-3600: round-budget.mjs runs as a CLI through a symlinked scripts directory"
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
  [[ "$(tail -n 1 "$ev")" == *'"from":"pass","forced":true'* ]] || log_fail "TEST-3601: forced reset line wrong: $(tail -1 "$ev")"
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
  [[ "$(tail -n 1 "$ev")" == *'"event":"round_extension"'* ]] || log_fail "TEST-3603: extension line missing"
  [[ "$(tail -n 1 "$ev")" == *'"authority":"standing-a"'* ]] || log_fail "TEST-3603: authority not recorded"
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

# mk_dispatch_root <dir> <vstatus> <rstatus> <phase>: a scratch repo the dispatcher can read (ref CHANGE-0001).
mk_dispatch_root() {
  local d="$1"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  printf -- '---\nid: SPEC-0001\ntype: spec\nnumber: 1\nstatus: implementing\nlinks:\n  pr: []\n---\n\n# Fixture spec\n\nSPEC-FROZEN: true\n\n## Test Plan\n\n| Test ID | Spec-AC | Type | File | Description | Status |\n|---|---|---|---|---|---|\n| TEST-001 | Spec-AC-01 | unit | t.sh | x | pending |\n' > "$d/docs/specs/SPEC-0001-fx.md"
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
active_work_items:
  - ref_id: CHANGE-0001
    status: in_progress
    phase: $4
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: docs/specs/SPEC-0001-fx.md
implementation_strategy:
  selected: tdd
  source: docs/specs/SPEC-0001-fx.md
  rationale: null
worktree:
  recommendation: optional
  user_decision: inline
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: true
  status: $3
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: $2
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: CHANGE-0001
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
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# dispatch_out <dir> <log>: run the dispatcher against a scratch root, print the exit code.
dispatch_rc() {
  local rc=0
  (cd "$PROJECT_ROOT" && node "$DISPATCH" --state "$1/docs/ai/STATE.yaml" --root "$1") > "$2" 2>"$2.err" || rc=$?
  echo "$rc"
}

test_3604_dispatch_stops_at_cap() {
  new_tmp
  local d rc base rule vs rs ph
  for rule in 10 12; do
    if [[ "$rule" == 10 ]]; then vs=fail; rs=not_run; ph=validation; else vs=pass; rs=fail; ph=code_review; fi
    d="$TMP_ROOT/r$rule"
    mk_dispatch_root "$d" "$vs" "$rs" "$ph"
    # No EVENTS: the baseline dispatches Remediation.
    rc="$(dispatch_rc "$d" "$TMP_ROOT/base$rule.json")"
    [[ "$rc" == 0 ]] || log_fail "TEST-3604: rule $rule baseline exited $rc: $(cat "$TMP_ROOT/base$rule.json" "$TMP_ROOT/base$rule.json.err")"
    node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(o.verdict==="dispatch"&&o.rule===process.argv[2]&&o.role==="Remediation"?0:1)' "$TMP_ROOT/base$rule.json" "$rule" \
      || log_fail "TEST-3604: rule $rule baseline must dispatch Remediation: $(cat "$TMP_ROOT/base$rule.json")"
    # One reset: below the cap, byte-identical to the baseline.
    reset_line CHANGE-0001 fail > "$d/docs/ai/EVENTS.jsonl"
    rc="$(dispatch_rc "$d" "$TMP_ROOT/one$rule.json")"
    [[ "$rc" == 0 ]] || log_fail "TEST-3604: rule $rule below the cap exited $rc"
    # prompt_hash and the like are stable for one tree; compare whole output.
    cmp -s "$TMP_ROOT/base$rule.json" "$TMP_ROOT/one$rule.json" || log_fail "TEST-3604: rule $rule below the cap must equal the no-EVENTS baseline"
    # Two resets: the stop.
    reset_line CHANGE-0001 fail >> "$d/docs/ai/EVENTS.jsonl"
    reset_line OTHER fail >> "$d/docs/ai/EVENTS.jsonl"
    rc="$(dispatch_rc "$d" "$TMP_ROOT/cap$rule.json")"
    [[ "$rc" == 3 ]] || log_fail "TEST-3604: rule $rule at the cap must exit 3, got $rc: $(cat "$TMP_ROOT/cap$rule.json" "$TMP_ROOT/cap$rule.json.err")"
    node -e '
      const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
      const c=o.state_update_commands;
      const ok=o.verdict==="no_action"&&o.rule===process.argv[2]&&o.role===null
        &&o.reasons.includes("review_round_cap")&&o.reasons.includes("standing_a_available")
        &&Array.isArray(c)&&c.length===1&&c[0].startsWith("node .aai/scripts/state.mjs set-human-input --required true --reason \"review-round-cap: 2/2")
        &&c[0].includes("(1) split the ride")&&c[0].includes("(3) park the ride");
      process.exit(ok?0:1)' "$TMP_ROOT/cap$rule.json" "$rule" || log_fail "TEST-3604: rule $rule stop shape wrong: $(cat "$TMP_ROOT/cap$rule.json")"
    # A standing-a extension raises the cap to 3: dispatch resumes.
    ev_line round_extension CHANGE-0001 '{"authority":"standing-a","reason":"hazard"}' >> "$d/docs/ai/EVENTS.jsonl"
    rc="$(dispatch_rc "$d" "$TMP_ROOT/ext$rule.json")"
    [[ "$rc" == 0 ]] || log_fail "TEST-3604: rule $rule after one extension must dispatch, got $rc"
    # Three resets at cap 3: the stop again, without standing_a_available.
    reset_line CHANGE-0001 fail >> "$d/docs/ai/EVENTS.jsonl"
    rc="$(dispatch_rc "$d" "$TMP_ROOT/cap3$rule.json")"
    [[ "$rc" == 3 ]] || log_fail "TEST-3604: rule $rule at 3/3 must exit 3, got $rc"
    node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.exit(o.reasons.includes("review_round_cap")&&!o.reasons.includes("standing_a_available")&&o.state_update_commands[0].includes("3/3")?0:1)' "$TMP_ROOT/cap3$rule.json" \
      || log_fail "TEST-3604: rule $rule 3/3 stop must not offer standing_a: $(cat "$TMP_ROOT/cap3$rule.json")"
  done
  log_pass "TEST-3604: rules 10 and 12 stop at the cap with review_round_cap and one set-human-input command; below it unchanged"
}

test_3605_stop_relay_parks() {
  new_tmp
  local d rc reason question st out
  d="$TMP_ROOT/r10"
  mk_dispatch_root "$d" fail not_run validation
  { reset_line CHANGE-0001 fail; reset_line CHANGE-0001 fail; } > "$d/docs/ai/EVENTS.jsonl"
  rc="$(dispatch_rc "$d" "$TMP_ROOT/cap.json")"
  [[ "$rc" == 3 ]] || log_fail "TEST-3605: want the stop (exit 3), got $rc"
  reason="$(node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const m=/--reason "([^"]*)"/.exec(o.state_update_commands[0]); process.stdout.write(m[1])' "$TMP_ROOT/cap.json")"
  question="$(node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const m=/--question "([^"]*)"/.exec(o.state_update_commands[0]); process.stdout.write(m[1])' "$TMP_ROOT/cap.json")"
  [[ "$reason" == review-round-cap:* ]] || log_fail "TEST-3605: reason must start review-round-cap:, got: $reason"
  # Relay: the returned command runs through the real state.mjs.
  st="$d/docs/ai/STATE.yaml"
  rc="$(run_rc "$TMP_ROOT/hi.log" node "$STATE_CLI" --state "$st" set-human-input --required true --reason "$reason" --question "$question")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3605: set-human-input exited $rc: $(cat "$TMP_ROOT/hi.log")"
  grep -q 'review-round-cap: 2/2' "$st" || log_fail "TEST-3605: STATE must carry the reason: $(grep -n human_input -A4 "$st")"
  # The loop reads the trigger token from the reason; the gate parks it.
  out="$(node "$GATE" classify --trigger review-round-cap --ref CHANGE-0001 --question "$question" --ledger "$TMP_ROOT/decisions.jsonl" --json 2>&1)" && rc=0 || rc=$?
  [[ "$rc" == 3 ]] || log_fail "TEST-3605: unattended-gate must park review-round-cap (exit 3), got $rc: $out"
  grep -q '"decision":"park"\|"decision": "park"' <<<"$out" || log_fail "TEST-3605: want decision park: $out"
  # ORCHESTRATION relays the stop within its line ceiling.
  local orch="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
  grep -qE 'review_round_cap([^A-Za-z0-9_]|$)' "$orch" || log_fail "TEST-3605: ORCHESTRATION must name review_round_cap"
  grep -q 'standing_a_available' "$orch" || log_fail "TEST-3605: ORCHESTRATION must name standing_a_available"
  grep -q 'round_extension --ref <ref> --authority standing-a' "$orch" || log_fail "TEST-3605: ORCHESTRATION must name the standing-a command"
  grep -q 'ONCE' <(grep 'review_round_cap' "$orch") || log_fail "TEST-3605: ORCHESTRATION must say the re-run is once"
  [[ "$(wc -l < "$orch" | tr -d ' ')" -le 45 ]] || log_fail "TEST-3605: ORCHESTRATION over the 45-line ceiling"
  log_pass "TEST-3605: the stop reason runs through state.mjs, classifies park, and ORCHESTRATION relays it within 45 lines"
}

# result_block <file> <role> <status> <blocker line or ->: a subagent_result fixture.
result_block() {
  local f="$1" role="$2" status="$3" blocker="$4"
  {
    printf 'Done.\n\n```yaml\nsubagent_result:\n  scope: CHANGE-0001\n  role: %s\n  status: %s\n' "$role" "$status"
    printf '  started_utc: 2026-01-02T00:00:00Z\n  ended_utc: 2026-01-02T00:02:30Z\n  duration_seconds: 150\n'
    printf '  evidence:\n    - command: bash t.sh\n      exit_code: 1\n      output_snippet: "fail"\n  files_changed: []\n'
    if [[ "$blocker" == "-" ]]; then printf '  blockers: []\n'; else printf '  blockers:\n    - %s\n' "$blocker"; fi
    printf '```\n'
  } > "$f"
}

test_3606_fail_needs_backing() {
  new_tmp
  local d="$TMP_ROOT/repo" rc role
  mkdir -p "$d/docs/ai/reports"
  echo "FAIL: step bound exceeded" > "$d/docs/ai/reports/check.log"
  echo "run it twice" > "$d/docs/ai/reports/repro.md"
  echo "outside" > "$TMP_ROOT/repro-outside.md"
  co() { (cd "$d" && node "$CHECK_OUT" --file "$1" --now 2026-01-02T01:00:00Z); }
  for role in Validation "Code Review"; do
    result_block "$TMP_ROOT/b.md" "$role" FAIL -
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] || log_fail "TEST-3606: $role FAIL with no blockers must exit 1, got $rc"
    grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role FAIL with no blockers must name E-FAIL-UNBACKED: $(cat "$TMP_ROOT/o.log")"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] && grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role unbacked BLOCKING line must be rejected: $(cat "$TMP_ROOT/o.log")"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded backed-by: check docs/ai/reports/absent.log exit 1"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] && grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role check naming a missing file must be rejected"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded backed-by: check docs/ai/reports/check.log exit 0"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] && grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role check with exit 0 must be rejected"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded backed-by: repro /etc/hosts"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] && grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role repro naming an absolute path must be rejected"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded backed-by: repro ../repro-outside.md"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 1 ]] && grep -q 'E-FAIL-UNBACKED' "$TMP_ROOT/o.log" || log_fail "TEST-3606: $role repro escaping the repo root must be rejected"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B1: the bound is exceeded backed-by: check docs/ai/reports/check.log exit 1"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 0 ]] || log_fail "TEST-3606: $role backed check line must pass, got $rc: $(cat "$TMP_ROOT/o.log")"
    result_block "$TMP_ROOT/b.md" "$role" FAIL "BLOCKING B2: flaky on load backed-by: repro docs/ai/reports/repro.md"
    rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
    [[ "$rc" == 0 ]] || log_fail "TEST-3606: $role backed repro line must pass, got $rc: $(cat "$TMP_ROOT/o.log")"
  done
  result_block "$TMP_ROOT/b.md" Implementation FAIL -
  rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3606: an Implementation FAIL is unaffected, got $rc: $(cat "$TMP_ROOT/o.log")"
  result_block "$TMP_ROOT/b.md" Validation BLOCKED "needs a human decision"
  rc="$(run_rc "$TMP_ROOT/o.log" co "$TMP_ROOT/b.md")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3606: a Validation BLOCKED is unaffected, got $rc: $(cat "$TMP_ROOT/o.log")"
  log_pass "TEST-3606: a Validation or Code Review FAIL needs a BLOCKING line backed by a failing check or a repro"
}

# in_repo <dir> <cmd...>: run a command with the scratch repo as its working directory.
in_repo() { local d="$1"; shift; (cd "$d" && "$@"); }

# mk_sweep_repo <dir> <ceremony|none> <framework yes|no>: a scratch git repo for sweep-plan (ref SW-1).
mk_sweep_repo() {
  local d="$1" level="$2" fw="$3"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/tests/skills" "$d/.aai/scripts" "$d/.github/workflows"
  if [[ "$level" == none ]]; then
    printf -- '---\nid: spec-sw-1\n---\n\n# spec\n' > "$d/docs/specs/SPEC-DRAFT-spec-SW-1.md"
  else
    printf -- '---\nid: spec-sw-1\nceremony_level: %s\n---\n\n# spec\n' "$level" > "$d/docs/specs/SPEC-DRAFT-spec-SW-1.md"
  fi
  [[ "$fw" == yes ]] && echo 'echo framework' > "$d/tests/skills/test-framework.sh"
  echo 'one' > "$d/.aai/scripts/x.mjs"
  : > "$d/docs/ai/EVENTS.jsonl"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  git -C "$d" add -A
  git -C "$d" commit -q -m base
}

# sw_commit <dir> <path> [content]: change one file and commit it.
sw_commit() {
  mkdir -p "$(dirname "$1/$2")"
  echo "${3:-change}" >> "$1/$2"
  git -C "$1" add -A
  git -C "$1" commit -q -m "edit $2"
}

# sw_record <dir> <head> <rc> <runid>: record a full_sweep through the real append-event.
sw_record() {
  in_repo "$1" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$2" --rc "$3" --run-id "$4" > /dev/null
}

sw_plan() { in_repo "$1" node "$RB" sweep-plan --ref SW-1; }

test_3607_sweep_plan() {
  new_tmp
  local d out head other
  d="$TMP_ROOT/nofw"; mk_sweep_repo "$d" 2 no
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP not-applicable reason=no-sweep-command" ]] || log_fail "TEST-3607: no test-framework.sh: got '$out'"
  d="$TMP_ROOT/l1"; mk_sweep_repo "$d" 1 yes
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP not-applicable reason=lightweight-lane" ]] || log_fail "TEST-3607: ceremony 1: got '$out'"
  d="$TMP_ROOT/l2"; mk_sweep_repo "$d" 2 yes
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP full reason=no-sweep" ]] || log_fail "TEST-3607: no sweep recorded: got '$out'"
  # not-ancestor: the sweep head sits on a branch HEAD does not contain.
  git -C "$d" checkout -q -b side
  sw_commit "$d" tests/side.sh
  other="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -
  sw_record "$d" "$other" 0 r-side
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP full reason=not-ancestor sha=$other" ]] || log_fail "TEST-3607: non-ancestor head: got '$out'"
  # A green sweep at HEAD, then a code delta and a reuse delta.
  d="$TMP_ROOT/l3"; mk_sweep_repo "$d" 2 yes
  head="$(git -C "$d" rev-parse HEAD)"
  sw_record "$d" "$head" 0 r1
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP reuse sha=$head run=r1" ]] || log_fail "TEST-3607: sweep at HEAD, empty delta: got '$out'"
  sw_commit "$d" tests/a.sh
  sw_commit "$d" docs/a.md
  sw_commit "$d" .github/workflows/w.yml
  sw_commit "$d" docs/ai/EVENTS.jsonl '{"v":1}'
  sw_commit "$d" .aai/PROMPT.prompt.md
  echo untracked > "$d/tests/untracked.sh"
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP reuse sha=$head run=r1" ]] || log_fail "TEST-3607: tests, docs, workflow, ledger and an untracked test must reuse: got '$out'"
  sw_commit "$d" .aai/scripts/x.mjs two
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP full reason=code-delta path=.aai/scripts/x.mjs" ]] || log_fail "TEST-3607: a script delta must be full code-delta: got '$out'"
  [[ "$(sw_plan "$d" | wc -l | tr -d ' ')" == 1 ]] || log_fail "TEST-3607: sweep-plan must print exactly one line"
  log_pass "TEST-3607: sweep-plan answers not-applicable, full (no-sweep, not-ancestor, code-delta) and reuse"
}

test_3608_red_sweep_and_record() {
  new_tmp
  local d="$TMP_ROOT/r" head out rc
  mk_sweep_repo "$d" 2 yes
  head="$(git -C "$d" rev-parse HEAD)"
  sw_record "$d" "$head" 1 r-red
  sw_commit "$d" tests/only.sh
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP full reason=red-sweep run=r-red" ]] || log_fail "TEST-3608: a red sweep must stay full even for a test-only delta: got '$out'"
  sw_record "$d" "$(git -C "$d" rev-parse HEAD)" 0 r-green
  out="$(sw_plan "$d")"
  [[ "$out" == "SWEEP reuse sha=$(git -C "$d" rev-parse HEAD) run=r-green" ]] || log_fail "TEST-3608: the newest (green) sweep must win: got '$out'"
  rc="$(run_rc "$TMP_ROOT/s.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head abc123 --rc 0 --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3608: a short head must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/s.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --rc abc --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3608: a non-integer rc must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/s.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --rc 0 --run-id "")"
  [[ "$rc" == 1 ]] || log_fail "TEST-3608: an empty run id must exit 1, got $rc"
  log_pass "TEST-3608: a red newest sweep stays full; append-event refuses a bad head, rc or run id"
}

test_3609_full_sweep_validation() {
  new_tmp
  local d="$TMP_ROOT/r" head rc before
  mk_sweep_repo "$d" 2 yes
  head="$(git -C "$d" rev-parse HEAD)"
  before="$(wc -l < "$d/docs/ai/EVENTS.jsonl" | tr -d ' ')"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --rc 0 --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3609: missing head must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "${head}0" --rc 0 --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3609: a 41-char head must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3609: missing rc must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --rc 1.5 --run-id x)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3609: a fractional rc must exit 1, got $rc"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --rc 0)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3609: missing run id must exit 1, got $rc"
  [[ "$(wc -l < "$d/docs/ai/EVENTS.jsonl" | tr -d ' ')" == "$before" ]] || log_fail "TEST-3609: a refused full_sweep wrote a line"
  rc="$(run_rc "$TMP_ROOT/a.log" in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref SW-1 --head "$head" --rc 0 --run-id fw-1)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3609: a well-formed record must exit 0, got $rc: $(cat "$TMP_ROOT/a.log")"
  [[ "$(tail -n 1 "$d/docs/ai/EVENTS.jsonl")" == *"\"head\":\"$head\""* ]] || log_fail "TEST-3609: the record must carry the head"
  log_pass "TEST-3609: every malformed full_sweep field exits 1 and writes no line"
}

test_3610_sweep_owed() {
  new_tmp
  local d="$TMP_ROOT/r" rc fx="$PROJECT_ROOT/tests/fixtures/role-outputs" head
  mk_sweep_repo "$d" 2 no
  mkdir -p "$d/tests/fixtures"
  cp -R "$fx" "$d/tests/fixtures/role-outputs"
  git -C "$d" add -A
  git -C "$d" commit -q -m fixtures
  co() { in_repo "$d" node "$CHECK_OUT" --file tests/fixtures/role-outputs/validation-valid.md --now 2026-06-01T00:00:00Z --outcome-intake tests/fixtures/role-outputs/outcome-intake.md --outcome-spec tests/fixtures/role-outputs/outcome-spec.md; }
  # No test-framework.sh: not applicable, accepted with a NOTE line.
  rc="$(run_rc "$TMP_ROOT/na.log" co)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3610: not-applicable PASS must exit 0, got $rc: $(cat "$TMP_ROOT/na.log")"
  grep -q '^NOTE: sweep not applicable (no-sweep-command)' "$TMP_ROOT/na.log" || log_fail "TEST-3610: want a NOTE naming the reason: $(cat "$TMP_ROOT/na.log")"
  # Add the sweep command: a PASS with no recorded sweep is refused.
  sw_commit "$d" tests/skills/test-framework.sh
  printf '%s\n' '---' 'id: spec-x' 'ceremony_level: 2' '---' > "$d/docs/specs/SPEC-DRAFT-spec-role-output-contracts.md"
  git -C "$d" add -A; git -C "$d" commit -q -m spec
  rc="$(run_rc "$TMP_ROOT/o.log" co)"
  [[ "$rc" == 1 ]] || log_fail "TEST-3610: a PASS with the sweep owed must exit 1, got $rc: $(cat "$TMP_ROOT/o.log")"
  grep -q 'ROLE-OUTPUT-VIOLATION: E-SWEEP-OWED' "$TMP_ROOT/o.log" || log_fail "TEST-3610: want E-SWEEP-OWED: $(cat "$TMP_ROOT/o.log")"
  # A green sweep at HEAD: accepted.
  head="$(git -C "$d" rev-parse HEAD)"
  in_repo "$d" node "$APPEND_EVENT" --event full_sweep --ref role-output-contracts --head "$head" --rc 0 --run-id fw-1 > /dev/null
  rc="$(run_rc "$TMP_ROOT/g.log" co)"
  [[ "$rc" == 0 ]] || log_fail "TEST-3610: a PASS after the green sweep must exit 0, got $rc: $(cat "$TMP_ROOT/g.log")"
  ! grep -q 'E-SWEEP-OWED' "$TMP_ROOT/g.log" || log_fail "TEST-3610: no E-SWEEP-OWED after a sweep"
  log_pass "TEST-3610: a Validation PASS is refused with E-SWEEP-OWED while the sweep is owed, accepted on reuse and (with a NOTE) not-applicable"
}

test_3611_replay() {
  new_tmp
  local d="$TMP_ROOT/ride" fx="$PROJECT_ROOT/tests/fixtures/round-history/install-path-parity-harness.json" out
  mk_dispatch_root "$d" pass not_run validation
  mkdir -p "$d/tests/skills"
  echo 'echo framework' > "$d/tests/skills/test-framework.sh"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  git -C "$d" add -A
  git -C "$d" commit -q -m base
  out="$(RB="$RB" STATE_CLI="$STATE_CLI" APPEND_EVENT="$APPEND_EVENT" DISPATCH="$DISPATCH" PROJECT_ROOT="$PROJECT_ROOT" ROOT="$d" FX="$fx" node - <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const E = process.env;
const fx = JSON.parse(fs.readFileSync(E.FX, 'utf8'));
const ref = 'CHANGE-0001';
const state = path.join(E.ROOT, 'docs/ai/STATE.yaml');
const run = (script, args, cwd) => spawnSync('node', [script, ...args], { cwd, encoding: 'utf8' });
const st = (...a) => run(E.STATE_CLI, ['--state', state, ...a], E.PROJECT_ROOT);
const git = (...a) => spawnSync('git', ['-C', E.ROOT, ...a], { encoding: 'utf8' });
const need = (r, what) => { if (r.status !== 0) { console.error(`replay: ${what} exited ${r.status}: ${r.stdout}${r.stderr}`); process.exit(1); } return r; };
const dispatch = () => { const r = run(E.DISPATCH, ['--state', state, '--root', E.ROOT], E.PROJECT_ROOT); return { rc: r.status, o: JSON.parse(r.stdout) }; };
let resets = 0, sweeps = 0, stop = 'none', extended = false;
for (const r of fx.rounds) {
  for (const p of r.delta) {
    if (p === 'docs/ai/EVENTS.jsonl') continue;
    const f = path.join(E.ROOT, p);
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.appendFileSync(f, `${r.id}\n`);
  }
  git('add', '-A'); git('commit', '-q', '--allow-empty', '-m', `round ${r.id}`);
  const isVal = r.role === 'validation';
  const block = isVal ? 'last_validation' : 'code_review';
  if (r.verdict === 'PASS') {
    need(isVal ? st('set-validation', '--status', 'pass', '--ref', ref) : st('set-code-review', '--status', 'pass'), `${r.id} pass`);
    if (isVal) {
      const plan = need(run(E.RB, ['sweep-plan', '--ref', ref], E.ROOT), 'sweep-plan').stdout.trim();
      if (plan.startsWith('SWEEP full')) {
        const head = git('rev-parse', 'HEAD').stdout.trim();
        need(run(E.APPEND_EVENT, ['--event', 'full_sweep', '--ref', ref, '--head', head, '--rc', '0', '--run-id', `fw-${r.id}`], E.ROOT), 'full_sweep');
        sweeps += 1;
      }
    }
    continue;
  }
  need(isVal ? st('set-validation', '--status', 'fail', '--ref', ref) : st('set-code-review', '--status', 'fail'), `${r.id} fail`);
  let d = dispatch();
  if (d.rc === 3 && d.o.reasons.includes('review_round_cap')) {
    if (r.hazard_introduced_by_feature && d.o.reasons.includes('standing_a_available') && !extended) {
      need(run(E.APPEND_EVENT, ['--event', 'round_extension', '--ref', ref, '--authority', 'standing-a', '--reason', `${r.id} hazard introduced by the feature`], E.ROOT), 'round_extension');
      extended = true;
      d = dispatch();
    }
    if (d.rc === 3) { stop = r.id; break; }
  }
  if (d.rc !== 0 || d.o.role !== 'Remediation') { console.error(`replay: ${r.id} did not dispatch Remediation: ${JSON.stringify(d.o)}`); process.exit(1); }
  need(st('reset-block', block), `${r.id} reset-block`);
  resets += 1;
}
// The forced V6 re-check after a recorded pass: refused at the cap.
need(st('set-validation', '--status', 'pass', '--ref', ref), 'V6 pass');
const forced = st('reset-block', 'last_validation', '--force');
const rec = fx.recorded;
console.log(`REPLAY ride=${fx.ride} recorded_check_rounds=${rec.check_rounds} recorded_resets=${rec.resets} recorded_sweeps=${rec.sweeps} replay_resets=${resets} replay_stop=${stop} replay_sweeps=${sweeps}`);
console.log(`FORCED_V6 rc=${forced.status}`);
NODE
)" || log_fail "TEST-3611: the replay driver failed: $out"
  printf '%s\n' "$out"
  grep -qx 'REPLAY ride=install-path-parity-harness recorded_check_rounds=9 recorded_resets=5 recorded_sweeps=3 replay_resets=3 replay_stop=R2 replay_sweeps=1' <<<"$out" || log_fail "TEST-3611: the REPLAY line differs from D-REPLAY: $out"
  grep -qx 'FORCED_V6 rc=5' <<<"$out" || log_fail "TEST-3611: the forced V6 reset must be refused with exit 5: $out"
  log_pass "TEST-3611: ride 8 replays to 3 automatic resets, an owner menu at R2, one sweep, the forced V6 reset refused"
}

# need <file> <fixed phrase...>: every phrase must occur in the file.
need() {
  local f="$1" t="$2"
  shift 2
  local p
  for p in "$@"; do
    grep -qF -- "$p" "$PROJECT_ROOT/$f" || log_fail "$t: $f lacks the D-CANON phrase: $p"
  done
}

test_3612_canon_prose() {
  local p="$PROJECT_ROOT"
  need .aai/VALIDATION.prompt.md TEST-3612 'round-budget.mjs sweep-plan' 'round-budget.mjs status' 'round_extension' 'backed-by' 'follow-ups.mjs add' 'review-round-cap' 'wave-2-roadmap'
  need .aai/REMEDIATION.prompt.md TEST-3612 'follow-ups.mjs add' 'counted round' 'round-budget.mjs' 'Exit 5'
  need .aai/SKILL_CODE_REVIEW.prompt.md TEST-3612 'backed-by' 'NON-BLOCKING'
  need .aai/SKILL_VERIFY.prompt.md TEST-3612 'round-budget.mjs sweep-plan' 'sweep-plan. Blast radius is the selector'
  need .aai/ORCHESTRATION.prompt.md TEST-3612 'review_round_cap' 'round_extension'
  need .aai/AGENTS.md TEST-3612 'round-budget.mjs status' 'reset-block'
  if grep -qF 'Run the whole suite' "$p/.aai/SKILL_VERIFY.prompt.md" || grep -qF 'The full sweep before close' "$p/.aai/SKILL_VERIFY.prompt.md"; then
    log_fail "TEST-3612: SKILL_VERIFY still carries the old counter or reuse text"
  fi
  if grep -qE 'ONE full|does NOT require a full sweep|runs before the close ceremony' "$p/.aai/VALIDATION.prompt.md"; then
    log_fail "TEST-3612: VALIDATION c2 still demands or describes the old intermediate full sweep"
  fi
  log_pass "TEST-3612: the six canon prompts name the counted cap, the backed bar, the follow-up default and the sweep-plan sequence"
}

test_3613_wiring() {
  local list sel
  grep -qxF '  - .aai/scripts/round-budget.mjs' "$PROJECT_ROOT/.aai/system/PROFILES.yaml" || log_fail "TEST-3613: PROFILES core does not list round-budget.mjs"
  new_tmp
  list="$TMP_ROOT/files.txt"
  printf '%s\n' '.aai/scripts/round-budget.mjs' > "$list"
  sel="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --repo-root "$PROJECT_ROOT" --files-from "$list")" || log_fail "TEST-3613: select-suites failed: $sel"
  local s
  for s in aai-round-budget aai-state aai-orchestration-dispatch aai-role-output; do
    grep -qE "^(SELECTED|CORE) $s( |$)" <<<"$sel" || log_fail "TEST-3613: round-budget.mjs does not select $s: $sel"
  done
  [[ "$(grep -c '^aai-round-budget'$'\t' "$SCRIPT_DIR/suite-weights.tsv")" == 1 ]] || log_fail "TEST-3613: suite-weights does not hold exactly one aai-round-budget row"
  grep -qxF '# sample aai-round-budget fallback unsampled (new suite of factory-round-cap; no successful observation)' "$SCRIPT_DIR/suite-weights.tsv" || log_fail "TEST-3613: suite-weights lacks the aai-round-budget fallback line"
  log_pass "TEST-3613: round-budget.mjs is core, selects the four suites, and the suite has its weight row"
}

test_3614_prompt_diet_pins() {
  local l="$SCRIPT_DIR/lib/prompt-diet-ledger.sh" t rc
  [[ "$(grep -c ' factory-round-cap ' "$l")" == 1 ]] || log_fail "TEST-3614: the ledger must hold exactly one factory-round-cap entry"
  new_tmp
  for t in prompt-diet:test_010_audit_and_reduction prompt-diet:test_012_growth_sum_matches_ledger pr-preflight:test_008 legacy-migrations:test_3398_diet retired-loop-runner:test_3410_diet; do
    rc=0
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-${t%%:*}.sh" "${t#*:}" > "$TMP_ROOT/${t%%:*}.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || log_fail "TEST-3614: ${t#*:} of ${t%%:*} is red: $(tail -5 "$TMP_ROOT/${t%%:*}.log")"
  done
  log_pass "TEST-3614: the ledger entry and the four companion pins agree with the corpus"
}

test_3615_changelog() {
  local cl="$PROJECT_ROOT/CHANGELOG.md"
  [[ "$(grep -c '^## \[unreleased\]$' "$cl")" == 1 ]] || log_fail "TEST-3615: CHANGELOG must keep exactly one bare unreleased scaffold"
  [[ "$(grep -c '^## \[unreleased\] — .*round cap' "$cl")" == 1 ]] || log_fail "TEST-3615: CHANGELOG must hold exactly one per-entry unreleased heading for the round cap"
  local body
  body="$(awk '/^## \[unreleased\] — .*round cap/{f=1;next} f&&/^## /{exit} f' "$cl")"
  local p
  for p in 'E-FAIL-UNBACKED' 'E-SWEEP-OWED' 'round-budget.mjs status' 'review-round-cap' '5 resets' '3 sweeps' '1 sweep'; do
    grep -qF -- "$p" <<<"$body" || log_fail "TEST-3615: the CHANGELOG entry lacks: $p"
  done
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-release.sh" test_022_live_changelog_scaffold_invariants >/dev/null 2>&1 || log_fail "TEST-3615: release TEST-022 is red"
  log_pass "TEST-3615: one per-entry unreleased heading below the bare scaffold names the cap, bar, sweep plan and gain"
}

main() {
  check_deps
  test_3600_status_counts
  test_3600b_cli_through_symlink
  test_3601_reset_appends_round
  test_3602_cap_refuses
  test_3603_extensions
  test_3604_dispatch_stops_at_cap
  test_3605_stop_relay_parks
  test_3606_fail_needs_backing
  test_3607_sweep_plan
  test_3608_red_sweep_and_record
  test_3609_full_sweep_validation
  test_3610_sweep_owed
  test_3611_replay
  test_3612_canon_prose
  test_3613_wiring
  test_3614_prompt_diet_pins
  test_3615_changelog
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
