#!/usr/bin/env bash
#
# Test: aai-model-effort — effort per role, closed vocabulary, harness
# translation and the visible environment override
# (spec-model-effort-routing, TEST-3633..3637 here; later TESTs join with
# their Spec-ACs). Fixtures are scratch temp-dir repos; nothing real is
# touched. bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-model-effort"
TEST_DIR=""
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
# shellcheck source=lib/pipe-safe.sh
. "$SCRIPT_DIR/lib/pipe-safe.sh"
DISPATCH="$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs"
ROUTING="$PROJECT_ROOT/.aai/system/MODEL_ROUTING.yaml"

cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$DISPATCH" && -f "$ROUTING" ]] || log_fail "dispatch script or MODEL_ROUTING.yaml missing"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-model-effort.XXXXXX")"
}

# mk_root <name> — scratch root whose STATE dispatches a rule-11 Validation.
mk_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow" "$d/.aai/system"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  cat > "$d/docs/specs/SPEC-0001-fx.md" <<'MD'
---
id: SPEC-0001
type: spec
number: 1
status: draft
links:
  pr: []
---

# Fixture spec

SPEC-FROZEN: true

## Test Plan
MD
  cat > "$d/docs/ai/STATE.yaml" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
active_work_items:
  - ref_id: CHANGE-0001
    status: in_progress
    phase: implementation
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
  status: not_run
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: not_run
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
  printf '%s' "$d"
}

OUT=""; ERR=""; EC=0; CUR_TEST=""
# run_d <root> <harness|-> [dispatch args...]; env markers scrubbed, the
# effort variable unset unless EFFORT_VAR is exported by the caller.
run_d() {
  local d="$1" h="$2"
  shift 2
  OUT="$d/out.json"; ERR="$d/err.log"; EC=0
  local -a e=(env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CODEX_HOME -u CODEX_SANDBOX
    -u CURSOR_TRACE_ID -u CURSOR_AGENT -u GEMINI_HOME -u GEMINI_CLI_IDE_SERVER_PORT
    -u GEMINI_CLI_IDE_AUTH_TOKEN -u GEMINI_CLI_IDE_WORKSPACE_PATH -u CLAUDE_CONFIG_DIR
    -u AAI_HARNESS -u AAI_ROLE -u CLAUDE_CODE_EFFORT_LEVEL)
  [[ "$h" == "-" ]] || e+=("AAI_HARNESS=$h")
  [[ -z "${EFFORT_VAR:-}" ]] || e+=("CLAUDE_CODE_EFFORT_LEVEL=$EFFORT_VAR")
  "${e[@]}" node "$DISPATCH" --state "$d/docs/ai/STATE.yaml" --root "$d" "$@" > "$OUT" 2> "$ERR" || EC=$?
}

jassert() {
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const fn = new Function("o", "return (" + process.argv[2] + ");");
    if (!fn(o)) { console.error("assert failed: " + process.argv[2] + "\n  got: " + JSON.stringify(o).slice(0, 600)); process.exit(1); }
  ' "$1" "$2" || log_fail "${CUR_TEST:-TEST}: JSON assertion failed: $2"
}

# jeval <json-file> <js-expr> -> prints the value
jeval() {
  node -e 'const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const v = (new Function("o", "return (" + process.argv[2] + ");"))(o); process.stdout.write(String(v));' "$1" "$2"
}

# run_mjs <script> <args...> — runs the script as a file so argv[1] is not the dispatcher.
run_mjs() {
  local f="$TEST_DIR/s$$.mjs"
  printf '%s\n' "$1" > "$f"
  shift
  node "$f" "$@"
}

# --- TEST-3633 (Spec-AC-01) ---------------------------------------------------
test_3633_shipped_effort_table() {
  CUR_TEST="TEST-3633"
  log_info "TEST-3633: shipped MODEL_ROUTING.yaml resolves the D-TABLE effort for every TIERS role..."
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const routing = m.loadModelRouting(process.argv[3]);
const rows = [["Planning","premium"],["Code Review","premium"],["Implementation","standard"],["TDD Implementation","standard"],["Remediation","standard"],["Validation","standard"],["Technology extraction","mechanical"],["Bootstrap","mechanical"],["Implementation Preparation / Worktree decision","mechanical"],["Metrics Flush","mechanical"]];
console.log(rows.map(([r, t]) => r + "=" + m.suggestEffort({ verdict: "dispatch", role: r, suggested_tier: t }, routing)).join(";"));
' "$DISPATCH" "$PROJECT_ROOT")"
  local want="Planning=high;Code Review=high;Implementation=medium;TDD Implementation=medium;Remediation=medium;Validation=high;Technology extraction=low;Bootstrap=low;Implementation Preparation / Worktree decision=low;Metrics Flush=low"
  [[ "$got" == "$want" ]] || log_fail "TEST-3633: effort table is '$got', expected '$want'"
  local d; d="$(mk_root t3633)"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3633: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.suggested_effort === "high"'
  log_pass "TEST-3633: ten roles resolve the D-TABLE levels; a CLI Validation dispatch carries high"
}

# --- TEST-3634 (Spec-AC-02) ---------------------------------------------------
test_3634_closed_vocabulary() {
  CUR_TEST="TEST-3634"
  log_info "TEST-3634: default resolves null, turbo is ignored with one NOTE, stdout stays JSON..."
  local d; d="$(mk_root t3634)"
  cat > "$d/.aai/system/MODEL_ROUTING.yaml" <<'YAML'
effort_roles:
  Validation: turbo
  Planning: default
  Code Review: high
YAML
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3634: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.suggested_effort === null'
  local n; n="$(grep -c 'turbo' "$ERR" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3634: $n stderr lines name turbo, expected 1: $(cat "$ERR")"
  n="$(grep -c 'NOTE' "$ERR" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3634: $n NOTE lines, expected exactly 1: $(cat "$ERR")"
  # default and high resolve through the pure function.
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const r = m.loadModelRouting(process.argv[3]);
const f = (role) => m.suggestEffort({ verdict: "dispatch", role, suggested_tier: "standard" }, r);
console.log([f("Planning"), f("Code Review"), f("Validation")].map(String).join(","));
' "$DISPATCH" "$d" 2>/dev/null)"
  [[ "$got" == "null,high,null" ]] || log_fail "TEST-3634: default/high/turbo resolved '$got', expected null,high,null"
  log_pass "TEST-3634: default -> null, high -> high, turbo -> null with one NOTE, stdout valid JSON"
}

# --- TEST-3635 (Spec-AC-03) ---------------------------------------------------
test_3635_harness_effort() {
  CUR_TEST="TEST-3635"
  log_info "TEST-3635: harness_effort per harness, null elsewhere, rest of the verdict unchanged..."
  local d h v; d="$(mk_root t3635)"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  for h in claude codex gemini; do
    run_d "$d" "$h"
    [[ "$EC" == 0 ]] || log_fail "TEST-3635: $h dispatch exited $EC: $(cat "$ERR")"
    v="$(jeval "$OUT" 'o.harness + ":" + o.suggested_effort + ":" + o.harness_effort')"
    [[ "$v" == "$h:high:high" ]] || log_fail "TEST-3635: Validation on $h gave '$v', expected $h:high:high"
  done
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const r = m.loadModelRouting(process.argv[3]);
const f = (h) => m.harnessEffort({ verdict: "dispatch", suggested_effort: m.suggestEffort({ verdict: "dispatch", role: "Remediation", suggested_tier: "standard" }, r) }, r, h);
console.log(["claude", "codex", "gemini", "cursor", "unknown"].map((h) => String(f(h))).join(","));
' "$DISPATCH" "$PROJECT_ROOT")"
  [[ "$got" == "medium,medium,high,null,null" ]] || log_fail "TEST-3635: Remediation harness_effort is '$got', expected medium,medium,high,null,null"
  for h in cursor unknown; do
    run_d "$d" "$h"
    jassert "$OUT" 'o.suggested_effort === "high" && o.harness_effort === null'
  done
  run_d "$d" -
  jassert "$OUT" 'o.harness === "unknown" && o.harness_effort === null'
  # absent file and a file without effort_params
  rm -f "$d/.aai/system/MODEL_ROUTING.yaml"
  run_d "$d" claude
  jassert "$OUT" 'o.suggested_effort === null && o.harness_effort === null'
  printf 'effort_roles:\n  Validation: high\n' > "$d/.aai/system/MODEL_ROUTING.yaml"
  run_d "$d" claude
  jassert "$OUT" 'o.suggested_effort === "high" && o.harness_effort === null'
  # with the new sections removed every other field equals the verdict that had them
  local s="$TEST_DIR/t3635-stripped"
  mkdir -p "$s/docs" && rm -rf "$s" && cp -R "$d" "$s"
  awk '/^effort_params@/{skip=1; next} /^[^ #]/{skip=0} /^#/ && skip{next} !skip{print}' "$ROUTING" > "$s/.aai/system/MODEL_ROUTING.yaml"
  qgrep -q '^effort_params@' < "$s/.aai/system/MODEL_ROUTING.yaml" && log_fail "TEST-3635: stripped fixture still has effort_params"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  run_d "$d" claude; cp "$OUT" "$TEST_DIR/with.json"
  run_d "$s" claude; cp "$OUT" "$TEST_DIR/without.json"
  jassert "$TEST_DIR/without.json" 'o.harness_effort === null'
  local a b
  a="$(jeval "$TEST_DIR/with.json" 'JSON.stringify(Object.fromEntries(Object.entries(o).filter(([k]) => k !== "harness_effort" && k !== "state_summary")))')"
  b="$(jeval "$TEST_DIR/without.json" 'JSON.stringify(Object.fromEntries(Object.entries(o).filter(([k]) => k !== "harness_effort" && k !== "state_summary")))')"
  [[ "$a" == "$b" ]] || log_fail "TEST-3635: verdict differs beyond harness_effort"
  run_d "$d" claude --human
  qgrep -q '^Harness effort: high' < "$ERR" || log_fail "TEST-3635: --human lacks 'Harness effort: high': $(cat "$ERR")"
  run_d "$d" cursor --human
  qgrep -q '^Harness effort: (unset)' < "$ERR" || log_fail "TEST-3635: --human lacks 'Harness effort: (unset)' on cursor"
  log_pass "TEST-3635: claude/codex/gemini map (gemini medium -> high); cursor, unknown, absent and section-less give null"
}

# --- TEST-3636 (Spec-AC-03) ---------------------------------------------------
test_3636_params_headers() {
  CUR_TEST="TEST-3636"
  log_info "TEST-3636: unsuffixed and out-of-set effort_params headers are noted and ignored; Mode A stays Mode A..."
  local d; d="$(mk_root t3636)"
  cat > "$d/.aai/system/MODEL_ROUTING.yaml" <<'YAML'
tiers:
  standard: claude-sonnet-5
effort_roles:
  Validation: high
effort_params:
  high: bogus
effort_params@codx:
  high: bogus
effort_params@claude:
  high: high
YAML
  run_d "$d" codex
  [[ "$EC" == 0 ]] || log_fail "TEST-3636: dispatch exited $EC: $(cat "$ERR")"
  local n; n="$(grep -c 'effort_params' "$ERR" || true)"
  [[ "$n" == 2 ]] || log_fail "TEST-3636: $n stderr lines name effort_params, expected 2: $(cat "$ERR")"
  qgrep -q 'effort_params@codx' < "$ERR" || log_fail "TEST-3636: the codx header is not named"
  jassert "$OUT" 'o.harness_effort === null'
  # Mode A: the unsuffixed tiers row still resolves the model.
  jassert "$OUT" 'o.suggested_model === "claude-sonnet-5"'
  run_d "$d" claude
  jassert "$OUT" 'o.harness_effort === "high" && o.suggested_model === "claude-sonnet-5"'
  log_pass "TEST-3636: two effort_params NOTEs, no mapping added, Mode A preserved"
}

# --- TEST-3637 (Spec-AC-04) ---------------------------------------------------
test_3637_effort_override() {
  CUR_TEST="TEST-3637"
  log_info "TEST-3637: CLAUDE_CODE_EFFORT_LEVEL surfaces as effort_override, name only..."
  local d; d="$(mk_root t3637)"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  EFFORT_VAR="sekrit-level" run_d "$d" claude
  jassert "$OUT" 'o.effort_override === "CLAUDE_CODE_EFFORT_LEVEL"'
  if [[ "$(cat "$OUT" "$ERR")" == *sekrit-level* ]]; then log_fail "TEST-3637: the variable value leaked into the output"; fi
  EFFORT_VAR="sekrit-level" run_d "$d" claude --human
  qgrep -q 'CLAUDE_CODE_EFFORT_LEVEL' < "$ERR" || log_fail "TEST-3637: the human block does not name the variable"
  qgrep -q 'will not apply' < "$ERR" || log_fail "TEST-3637: the human block does not say the effort will not apply"
  if [[ "$(cat "$ERR")" == *sekrit-level* ]]; then log_fail "TEST-3637: the value leaked into the human block"; fi
  EFFORT_VAR="" run_d "$d" claude
  jassert "$OUT" 'o.effort_override === null'
  EFFORT_VAR="sekrit-level" run_d "$d" codex
  jassert "$OUT" 'o.effort_override === null'
  run_d "$d" claude
  jassert "$OUT" 'o.effort_override === null'
  log_pass "TEST-3637: override named on claude only, value never printed, null otherwise"
}

# --- state / flush / report helpers ---------------------------------------------
STATE_MJS="$PROJECT_ROOT/.aai/scripts/state.mjs"
FLUSH_MJS="$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs"
REPORT_MJS="$PROJECT_ROOT/.aai/scripts/metrics-report.mjs"

# st <root> <state.mjs args...> -> OUT/ERR/EC; STATE and ticks live in the root.
st() {
  local d="$1"
  shift
  OUT="$d/st.out"; ERR="$d/st.err"; EC=0
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE -u AAI_GIT_WRITE node "$STATE_MJS" --state "$d/docs/ai/STATE.yaml" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" "$@") > "$OUT" 2> "$ERR" || EC=$?
}

# flush_d <root> -> runs metrics-flush over the root's STATE into its METRICS.
flush_d() {
  local d="$1" fl_ec=0
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE -u AAI_GIT_WRITE node "$FLUSH_MJS" --state "$d/docs/ai/STATE.yaml" \
    --metrics "$d/docs/ai/METRICS.jsonl" --ticks "$d/docs/ai/LOOP_TICKS.jsonl" \
    --pricing "$PROJECT_ROOT/.aai/system/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now 2026-07-02T00:00:00Z) > "$d/fl.out" 2>&1 || fl_ec=$?
  [[ "$fl_ec" == 0 ]] || log_fail "${CUR_TEST:-TEST}: flush exited $fl_ec: $(cat "$d/fl.out")"
}

# jassert_ledger <ledger> <js-expr over o = the single ledger line>
jassert_ledger() {
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split(/\r?\n/).filter(l => l.trim() !== "" && !l.startsWith("#"));
    if (lines.length !== 1) { console.error("expected one ledger line, got " + lines.length); process.exit(1); }
    const o = JSON.parse(lines[0]);
    const fn = new Function("o", "return (" + process.argv[2] + ");");
    if (!fn(o)) { console.error("assert failed: " + process.argv[2] + "\n  got: " + lines[0].slice(0, 800)); process.exit(1); }
  ' "$1" "$2" || log_fail "${CUR_TEST:-TEST}: ledger assertion failed"
}

# rep <ledger> <args...> -> stdout in $TEST_DIR/rep.out; EC set
rep() {
  local m="$1"
  shift
  EC=0
  (cd "$PROJECT_ROOT" && node "$REPORT_MJS" --metrics "$m" --pricing "$PROJECT_ROOT/.aai/system/PRICING.yaml" "$@") > "$TEST_DIR/rep.out" 2> "$TEST_DIR/rep.err" || EC=$?
}

# done_state <root> — turn the fixture STATE into a flushable finished item.
done_state() {
  local d="$1"
  sed -e 's/status: in_progress/status: done/' \
    -e '/^last_validation:/,/^  ref_id/ s/status: not_run/status: pass/' \
    -e '/^code_review:/,/^  base_ref/ s/status: not_run/status: pass/' \
    "$d/docs/ai/STATE.yaml" > "$d/s.yaml"
  mv "$d/s.yaml" "$d/docs/ai/STATE.yaml"
  printf '# Fixture item\n' > "$d/docs/issues/CHANGE-0001-fixture.md"
  : > "$d/docs/ai/METRICS.jsonl"
}

# --- TEST-3638 (Spec-AC-05) ---------------------------------------------------
test_3638_append_run_flags() {
  CUR_TEST="TEST-3638"
  log_info "TEST-3638: append-run carries the four fields only when passed; bad values exit 2 writing nothing..."
  local d; d="$(mk_root t3638)"
  local common=(append-run --ref CHANGE-0001 --role Implementation --model claude-sonnet-5-5 --started 2026-07-01T00:00:00Z --tokens-in 1 --tokens-out 1 --tokens-total 2)
  st "$d" "${common[@]}"
  [[ "$EC" == 0 ]] || log_fail "TEST-3638: plain append-run exited $EC: $(cat "$ERR")"
  if qgrep -q -e 'requested_effort' -e 'effort_applied' -e 'cache_read_tokens' -e 'cache_creation_tokens' < "$d/docs/ai/STATE.yaml"; then
    log_fail "TEST-3638: a plain append-run wrote an effort or cache field"
  fi
  st "$d" "${common[@]}" --requested-effort high --effort-applied param --cache-read 7 --cache-creation 9
  [[ "$EC" == 0 ]] || log_fail "TEST-3638: append-run with the four flags exited $EC: $(cat "$ERR")"
  local want
  for want in 'requested_effort: high' 'effort_applied: param' 'cache_read_tokens: 7' 'cache_creation_tokens: 9'; do
    qgrep -q -x -F "          $want" < "$d/docs/ai/STATE.yaml" || log_fail "TEST-3638: STATE lacks '$want'"
  done
  local before after bad
  before="$(cat "$d/docs/ai/STATE.yaml")"
  for bad in '--requested-effort turbo' '--effort-applied maybe' '--cache-read x' '--cache-creation x'; do
    # shellcheck disable=SC2086
    st "$d" "${common[@]}" $bad
    [[ "$EC" == 2 ]] || log_fail "TEST-3638: '$bad' exited $EC, expected 2"
    qgrep -q 'usage:' < "$ERR" || log_fail "TEST-3638: '$bad' printed no usage line"
    after="$(cat "$d/docs/ai/STATE.yaml")"
    [[ "$before" == "$after" ]] || log_fail "TEST-3638: '$bad' changed STATE"
  done
  st "$d" log-tick --tick 1 --role Implementation --scope CHANGE-0001 --started 2026-07-01T00:00:00Z --cache-creation 5
  [[ "$EC" == 0 ]] || log_fail "TEST-3638: log-tick exited $EC: $(cat "$ERR")"
  qgrep -q '"cache_creation_tokens":5' < "$d/docs/ai/LOOP_TICKS.jsonl" || log_fail "TEST-3638: log-tick did not write cache_creation_tokens 5"
  st "$d" log-tick --tick 2 --role Implementation --scope CHANGE-0001 --started 2026-07-01T00:00:00Z
  [[ "$(grep -c cache_creation_tokens "$d/docs/ai/LOOP_TICKS.jsonl" || true)" == 1 ]] || log_fail "TEST-3638: log-tick wrote cache_creation_tokens without the flag"
  log_pass "TEST-3638: four run fields on flag, none without, exit 2 and STATE untouched on bad values, log-tick cache-creation"
}

# --- TEST-3639 (Spec-AC-06) ---------------------------------------------------
test_3639_flush_carries_fields() {
  CUR_TEST="TEST-3639"
  log_info "TEST-3639: metrics-flush carries the four fields into METRICS; a run without them carries none..."
  local d; d="$(mk_root t3639)"
  done_state "$d"
  local common=(append-run --ref CHANGE-0001 --model claude-sonnet-5-5 --tokens-in 10 --tokens-out 5 --tokens-total 15)
  st "$d" "${common[@]}" --role Implementation --started 2026-07-01T00:00:00Z --requested-effort medium --effort-applied overridden --cache-read 70 --cache-creation 90
  [[ "$EC" == 0 ]] || log_fail "TEST-3639: append-run exited $EC: $(cat "$ERR")"
  st "$d" "${common[@]}" --role Planning --started 2026-07-01T00:10:00Z
  [[ "$EC" == 0 ]] || log_fail "TEST-3639: second append-run exited $EC: $(cat "$ERR")"
  flush_d "$d"
  jassert_ledger "$d/docs/ai/METRICS.jsonl" '(() => { const a = o.agent_runs; const i = a.find(r => r.role === "Implementation"), p = a.find(r => r.role === "Planning");
    return i.requested_effort === "medium" && i.effort_applied === "overridden" && i.cache_read_tokens === 70 && i.cache_creation_tokens === 90
      && !("requested_effort" in p) && !("effort_applied" in p) && !("cache_read_tokens" in p) && !("cache_creation_tokens" in p); })()'
  log_pass "TEST-3639: four fields flushed (strings and numbers); absent stays absent"
}

write_effort_ledger() {
  cat > "$1" <<'JSONL'
# fixture ledger
{"date_utc":"2026-07-01","ref_id":"AAA-0001","title":"First","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5-5","tokens_in":null,"tokens_out":null,"cost_usd":1.5,"tokens_total":1000},{"role":"Validation","model_id":"claude-sonnet-5-5","tokens_in":null,"tokens_out":null,"cost_usd":null,"tokens_total":400}],"verdict":"PASS"}
{"date_utc":"2026-07-10","ref_id":"AAA-0002","title":"Second","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation (review round 2)","model_id":"claude-sonnet-5-5","tokens_in":null,"tokens_out":null,"cost_usd":2,"tokens_total":900,"requested_effort":"medium","cache_read_tokens":30,"cache_creation_tokens":10},{"role":"Implementation","model_id":"claude-sonnet-5-5","tokens_in":null,"tokens_out":null,"cost_usd":null,"tokens_total":null,"requested_effort":"medium"},{"role":"Validation","model_id":"claude-sonnet-5-5","tokens_in":null,"tokens_out":null,"cost_usd":0.5,"tokens_total":500,"requested_effort":"high"}],"verdict":"PASS"}
JSONL
}

# --- TEST-3640 (Spec-AC-07) ---------------------------------------------------
test_3640_by_effort_tables() {
  CUR_TEST="TEST-3640"
  log_info "TEST-3640: metrics-report --by-effort and --split print the exact tables..."
  local d="$TEST_DIR/t3640"; mkdir -p "$d"
  write_effort_ledger "$d/METRICS.jsonl"
  rep "$d/METRICS.jsonl" --by-effort
  [[ "$EC" == 0 ]] || log_fail "TEST-3640: --by-effort exited $EC: $(cat "$TEST_DIR/rep.err")"
  cat > "$d/want1.md" <<'MD'
### By role and requested effort
| role | effort | runs | runs with tokens_total | sum tokens_total | median tokens_total | sum cost USD | sum cache_read | sum cache_creation | runs with cache |
|------|--------|------|------------------------|------------------|---------------------|--------------|----------------|--------------------|-----------------|
| Implementation | medium | 2 | 1 | 900 | 900 | ~$2.00 | 30 | 10 | 1 |
| Implementation | unset | 1 | 1 | 1000 | 1000 | $1.50 | 0 | 0 | 0 |
| Validation | high | 1 | 1 | 500 | 500 | $0.50 | 0 | 0 | 0 |
| Validation | unset | 1 | 1 | 400 | 400 | n/a | 0 | 0 | 0 |
MD
  diff -u "$d/want1.md" "$TEST_DIR/rep.out" > "$d/d1" 2>&1 || log_fail "TEST-3640: --by-effort table differs: $(cat "$d/d1")"
  rep "$d/METRICS.jsonl" --by-effort --split 2026-07-05
  [[ "$EC" == 0 ]] || log_fail "TEST-3640: --split exited $EC: $(cat "$TEST_DIR/rep.err")"
  cat > "$d/want2.md" <<'MD'
### Before 2026-07-05
| role | effort | runs | runs with tokens_total | sum tokens_total | median tokens_total | sum cost USD | sum cache_read | sum cache_creation | runs with cache |
|------|--------|------|------------------------|------------------|---------------------|--------------|----------------|--------------------|-----------------|
| Implementation | unset | 1 | 1 | 1000 | 1000 | $1.50 | 0 | 0 | 0 |
| Validation | unset | 1 | 1 | 400 | 400 | n/a | 0 | 0 | 0 |

### From 2026-07-05
| role | effort | runs | runs with tokens_total | sum tokens_total | median tokens_total | sum cost USD | sum cache_read | sum cache_creation | runs with cache |
|------|--------|------|------------------------|------------------|---------------------|--------------|----------------|--------------------|-----------------|
| Implementation | medium | 2 | 1 | 900 | 900 | ~$2.00 | 30 | 10 | 1 |
| Validation | high | 1 | 1 | 500 | 500 | $0.50 | 0 | 0 | 0 |

### Delta by role
| role | median tokens_total before | median tokens_total from | change |
|------|----------------------------|--------------------------|--------|
| Implementation | 1000 | 900 | -10.0% |
| Validation | 400 | 500 | +25.0% |
MD
  diff -u "$d/want2.md" "$TEST_DIR/rep.out" > "$d/d2" 2>&1 || log_fail "TEST-3640: --split tables differ: $(cat "$d/d2")"
  rep "$d/METRICS.jsonl" --by-effort --split 2026-07-20
  qgrep -q -x -F '| Validation | 450 | n/a | n/a |' < "$TEST_DIR/rep.out" || log_fail "TEST-3640: delta lacks the n/a row: $(cat "$TEST_DIR/rep.out")"
  rep "$d/METRICS.jsonl" --split 2026-07-05
  [[ "$EC" == 2 ]] || log_fail "TEST-3640: --split without --by-effort exited $EC, expected 2"
  log_pass "TEST-3640: exact by-effort, Before/From/Delta tables, one-decimal percent, n/a, split-alone refused"
}

# --- TEST-3641 (Spec-AC-07) ---------------------------------------------------
test_3641_dispatch_to_report() {
  CUR_TEST="TEST-3641"
  log_info "TEST-3641: dispatch effort feeds append-run, flush and the report; default output unchanged..."
  local d; d="$(mk_root t3641)"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  sed -e '/^last_validation:/,/^  ref_id/ s/status: not_run/status: pass/' "$d/docs/ai/STATE.yaml" > "$d/s0.yaml"
  mv "$d/s0.yaml" "$d/docs/ai/STATE.yaml"
  run_d "$d" claude
  local eff; eff="$(jeval "$OUT" 'o.suggested_effort')"
  [[ "$eff" == high ]] || log_fail "TEST-3641: dispatch suggested_effort is '$eff', expected high for Validation: $(cat "$OUT")"
  done_state "$d"
  st "$d" append-run --ref CHANGE-0001 --role Validation --model claude-sonnet-5-5 --started 2026-07-01T00:00:00Z --tokens-in 10 --tokens-out 5 \
    --tokens-total 15 --verdict pass --requested-effort "$eff" --effort-applied param
  [[ "$EC" == 0 ]] || log_fail "TEST-3641: append-run exited $EC: $(cat "$ERR")"
  flush_d "$d"
  rep "$d/docs/ai/METRICS.jsonl" --by-effort
  [[ "$EC" == 0 ]] || log_fail "TEST-3641: --by-effort exited $EC: $(cat "$TEST_DIR/rep.err")"
  qgrep -q -F '| Validation | high | 1 | 1 | 15 |' < "$TEST_DIR/rep.out" || log_fail "TEST-3641: no Validation high row: $(cat "$TEST_DIR/rep.out")"
  # Default output ignores the new fields: byte-identical with them stripped.
  rep "$d/docs/ai/METRICS.jsonl"
  cp "$TEST_DIR/rep.out" "$d/default-with.md"
  if qgrep -q 'requested effort' < "$d/default-with.md"; then log_fail "TEST-3641: default output grew an effort section"; fi
  node -e '
    const fs = require("fs");
    const out = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/).map(l => {
      if (l.trim() === "" || l.startsWith("#")) return l;
      const o = JSON.parse(l);
      for (const r of o.agent_runs) { delete r.requested_effort; delete r.effort_applied; delete r.cache_read_tokens; delete r.cache_creation_tokens; }
      return JSON.stringify(o);
    }).join("\n");
    fs.writeFileSync(process.argv[2], out);
  ' "$d/docs/ai/METRICS.jsonl" "$d/stripped.jsonl"
  rep "$d/stripped.jsonl"
  cmp -s "$d/default-with.md" "$TEST_DIR/rep.out" || log_fail "TEST-3641: default output changed with the effort fields present"
  log_pass "TEST-3641: dispatch effort -> append-run -> flush -> report row; default output unchanged"
}

main() {
  check_deps
  test_3633_shipped_effort_table
  test_3634_closed_vocabulary
  test_3635_harness_effort
  test_3636_params_headers
  test_3637_effort_override
  test_3638_append_run_flags
  test_3639_flush_carries_fields
  test_3640_by_effort_tables
  test_3641_dispatch_to_report
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
