#!/usr/bin/env bash
#
# Test: aai-orchestration-dispatch — deterministic orchestration tick
# (CHANGE-0009 / spec-mechanize-deterministic-ticks, TEST-001..005).
#
# Verifies .aai/scripts/orchestration-dispatch.mjs:
#   - pure exported decide(snapshot) reproducing the ORCHESTRATION 14-rule
#     first-match table (TEST-001)
#   - CLI on fixture STATE files: D3 JSON shape on stdout, exit 0/3, --human
#     stderr block, --rules table (TEST-002)
#   - SPEC-0012 G3 post-remediation reset routing (TEST-003)
#   - fail-closed exit 4 + named reasons on invalid STATE and judgment edges,
#     zero writes (TEST-004)
#   - rule-14 metrics-flush arm + validator_independence payload (TEST-005)
#
# ALL fixtures are scratch temp-dir repos (--state/--root overrides); the real
# runtime files are NEVER touched. bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-orchestration-dispatch"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs"

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
  [[ -f "$DISPATCH" ]] || log_fail "dispatch script not found: $DISPATCH (RED until CHANGE-0009 lands)"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-dispatch-test.XXXXXX")"
}

# --- fixture builders ---------------------------------------------------------

# mk_root <name> — an isolated repo root with TECHNOLOGY.md + WORKFLOW.md + a
# frozen DRAFT spec present by default. Echoes the dir.
mk_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true
  printf '%s' "$d"
}

# write_spec <path> <frontmatter-status> <frozen true|false>
write_spec() {
  local p="$1" status="$2" frozen="$3"
  cat > "$p" <<MD
---
id: SPEC-0001
type: spec
number: 1
status: $status
links:
  pr: []
---

# Fixture spec

$([[ "$frozen" == "true" ]] && echo "SPEC-FROZEN: true")

## Test Plan
MD
}

# write_intake_doc <path> <id> <type> <number> <status> — docs/issues fixture
# (spec-dispatch-new-intake-after-completed-scope D2 open_intakes probe input).
write_intake_doc() {
  local p="$1" id="$2" type="$3" number="$4" status="$5"
  cat > "$p" <<MD
---
id: $id
type: $type
number: $number
status: $status
links:
  pr: []
  commits: []
---

# Fixture intake doc
MD
}

# write_dstate <file> [vstatus] [rstatus] [phase] [istatus] [strategy] [wrec] [wdec] [vref] [rrequired]
# Canonical full fixture mirroring the real schema incl. the commented header.
write_dstate() {
  local f="$1" vstatus="${2:-not_run}" rstatus="${3:-not_run}" phase="${4:-implementation}" \
    istatus="${5:-in_progress}" strategy="${6:-tdd}" wrec="${7:-optional}" wdec="${8:-inline}" \
    vref="${9:-CHANGE-0001}" rrequired="${10:-true}"
  cat > "$f" <<YAML
# docs/ai/STATE.yaml - AAI runtime state (managed by orchestration; humans need not edit)
#
# CANONICAL SCHEMA / INVARIANTS (authoritative)
#   project_status:            active | paused
#   last_validation.status:    pass | fail | not_run
#   updated_at_utc:            ISO 8601 UTC
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
active_work_items:
  - ref_id: CHANGE-0001
    status: $istatus
    phase: $phase
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: docs/specs/SPEC-0001-fx.md
implementation_strategy:
  selected: $strategy
  source: docs/specs/SPEC-0001-fx.md
  rationale: null
worktree:
  recommendation: $wrec
  user_decision: $wdec
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: $rrequired
  status: $rstatus
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: $vstatus
  run_at_utc: 2026-07-01T00:00:00Z
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
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# append_metrics_runs <state-file> <ref> <lines...> — appends a metrics block
# with the given agent_runs YAML lines (pre-indented) for <ref>.
append_metrics_block() {
  local f="$1" ref="$2"
  shift 2
  {
    echo "metrics:"
    echo "  work_items:"
    echo "    $ref:"
    echo "      human_time_minutes:"
    echo "        intake: null"
    echo "        reviews: null"
    echo "      agent_runs:"
    local l
    for l in "$@"; do echo "$l"; done
  } >> "$f"
}

# run_dispatch <root> [extra flags...] — stdout to $OUT, stderr to $ERR, exit in $EC.
OUT=""
ERR=""
EC=0
run_dispatch() {
  local d="$1"
  shift
  OUT="$d/out.json"
  ERR="$d/err.log"
  EC=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/orchestration-dispatch.mjs \
    --state "$d/docs/ai/STATE.yaml" --root "$d" "$@" > "$OUT" 2> "$ERR") || EC=$?
}

# jassert <json-file> <js-boolean-expr over `o`>
jassert() {
  node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expr = process.argv[2];
    const fn = new Function("o", "return (" + expr + ");");
    if (!fn(o)) { console.error("assert failed: " + expr + "\n  got: " + JSON.stringify(o)); process.exit(1); }
  ' "$1" "$2" || log_fail "JSON assertion failed on $1"
}

# --- TEST-001: table-driven pure decide() -------------------------------------

test_001_decide_table() {
  log_info "Test: exported decide() reproduces all 14 rules first-match (TEST-001)..."
  cat > "$TEST_DIR/t1.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0001' },
  work_item: { phase: 'implementation', status: 'in_progress' },
  spec: { path: 'docs/specs/SPEC-0001-fx.md', present: true, frozen: true, frontmatter_status: 'draft' },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: null,
});

// Each case LAYERS the next rule's trigger on top of later-rule triggers so
// first-match order is asserted, not just per-rule matching.
const cases = [
  // [mutator, expected {verdict, rule, role, tier}]
  [s => { s.project_status = 'paused'; s.human_input_required = true; s.technology_present = false; },
    { verdict: 'no_action', rule: '1' }],
  [s => { s.human_input_required = true; s.technology_present = false; },
    { verdict: 'no_action', rule: '2' }],
  [s => { s.technology_present = false; s.workflow_present = false; },
    { verdict: 'dispatch', rule: '3', role: 'Technology extraction', tier: 'mechanical' }],
  [s => { s.workflow_present = false; s.spec.path = null; s.spec.present = false; },
    { verdict: 'dispatch', rule: '4', role: 'Bootstrap', tier: 'mechanical' }],
  [s => { s.spec.path = null; s.spec.present = false; s.strategy_selected = 'undecided'; },
    { verdict: 'dispatch', rule: '5', role: 'Planning', tier: 'premium' }],
  [s => { s.spec.frozen = false; s.strategy_selected = 'undecided'; },
    { verdict: 'dispatch', rule: '6', role: 'Planning', tier: 'premium' }],
  [s => { s.spec.frontmatter_status = 'done'; },
    { verdict: 'dispatch', rule: '6', role: 'Planning', tier: 'premium' }],
  [s => { s.strategy_selected = 'undecided'; s.worktree = { recommendation: 'required', user_decision: 'undecided' }; },
    { verdict: 'dispatch', rule: '7', role: 'Planning', tier: 'premium' }],
  [s => { s.worktree = { recommendation: 'recommended', user_decision: 'undecided' }; s.work_item = { phase: 'preparation', status: 'in_progress' }; },
    { verdict: 'dispatch', rule: '8', tier: 'mechanical' }],
  [s => { s.work_item = { phase: 'planning', status: 'done' }; s.validation = { status: 'fail', ref_id: 'CHANGE-0001' }; },
    { verdict: 'dispatch', rule: '9a', role: 'TDD Implementation', tier: 'standard' }],
  [s => { s.work_item = { phase: 'preparation', status: 'in_progress' }; s.strategy_selected = 'hybrid'; },
    { verdict: 'dispatch', rule: '9b', role: 'TDD Implementation', tier: 'standard' }],
  [s => { s.work_item = { phase: 'planning', status: 'done' }; s.strategy_selected = 'loop'; },
    { verdict: 'dispatch', rule: '9c', role: 'Implementation', tier: 'standard' }],
  [s => { s.validation = { status: 'fail', ref_id: 'CHANGE-0001' }; s.review = { required: true, status: 'fail' }; s.last_run_role = 'Implementation'; },
    { verdict: 'dispatch', rule: '10', role: 'Remediation', tier: 'standard' }],
  [s => { s.validation = { status: 'not_run', ref_id: null }; s.review = { required: true, status: 'fail' }; },
    { verdict: 'dispatch', rule: '11', role: 'Validation', tier: 'standard' }],
  [s => { s.validation = { status: 'pass', ref_id: 'CHANGE-0001' }; s.review = { required: true, status: 'fail' }; s.last_run_role = 'Code Review'; },
    { verdict: 'dispatch', rule: '12', role: 'Remediation', tier: 'standard' }],
  [s => { s.validation = { status: 'pass', ref_id: 'CHANGE-0001' }; s.review = { required: true, status: 'not_run' }; s.last_run_role = 'Validation'; },
    { verdict: 'dispatch', rule: '13', role: 'Code Review', tier: 'premium' }],
  [s => { s.validation = { status: 'pass', ref_id: 'CHANGE-0001' }; s.review = { required: true, status: 'pass' }; s.last_run_role = 'Code Review'; },
    { verdict: 'dispatch', rule: '14', role: 'Metrics Flush', tier: 'mechanical' }],
  [s => { s.validation = { status: 'pass', ref_id: 'CHANGE-0001' }; s.review = { required: false, status: 'not_run' }; s.flushed = true; s.last_run_role = 'Validation'; },
    { verdict: 'no_action', rule: '14' }],
];

for (const [mut, exp] of cases) {
  const s = base();
  mut(s);
  const d = decide(s);
  assert.strictEqual(d.verdict, exp.verdict, `verdict for expected rule ${exp.rule}: got ${JSON.stringify(d)}`);
  assert.strictEqual(d.rule, exp.rule, `rule: expected ${exp.rule}, got ${d.rule} (${JSON.stringify(d.reasons)})`);
  if (exp.role) assert.strictEqual(d.role, exp.role, `role for rule ${exp.rule}: got ${d.role}`);
  if (exp.tier) assert.strictEqual(d.suggested_tier, exp.tier, `tier for rule ${exp.rule}: got ${d.suggested_tier}`);
}

// decide() must be pure: same snapshot in, same decision out, input untouched.
const s1 = base();
const frozen = JSON.stringify(s1);
const a = decide(s1);
const b = decide(JSON.parse(frozen));
assert.strictEqual(JSON.stringify(a), JSON.stringify(b), 'decide must be deterministic');
assert.strictEqual(JSON.stringify(s1), frozen, 'decide must not mutate its input');
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t1.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t1.log" 2>&1 \
    || log_fail "decide() table-driven cases failed: $(cat "$TEST_DIR/t1.log")"
  log_pass "decide() reproduces the 14-rule first-match table incl. 9a/9b/9c (TEST-001)"
}

# --- TEST-002: CLI JSON shape / exit codes / --human / --rules -----------------

test_002_cli_contract() {
  log_info "Test: CLI emits the D3 JSON + closed exit codes on fixture STATE files (TEST-002)..."
  local d
  d="$(mk_root t2)"
  write_dstate "$d/docs/ai/STATE.yaml"   # not_run + phase implementation -> rule 11 dispatch
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "dispatch fixture must exit 0 (got $EC): $(cat "$OUT" "$ERR")"
  # stdout is EXACTLY ONE JSON object with the full D3 key set.
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "11" && o.role === "Validation"'
  jassert "$OUT" '["verdict","rule","role","ref_id","system_prompt","inputs","expected_outputs","stop_condition","suggested_tier","validator_independence","reasons","state_summary"].every(k => k in o)'
  jassert "$OUT" 'o.ref_id === "CHANGE-0001" && Array.isArray(o.inputs) && Array.isArray(o.expected_outputs) && Array.isArray(o.reasons)'
  jassert "$OUT" 'typeof o.stop_condition === "string" && o.stop_condition.length > 0'
  jassert "$OUT" 'o.system_prompt === ".aai/VALIDATION.prompt.md"'
  jassert "$OUT" 'typeof o.state_summary === "object" && o.state_summary !== null'
  [[ ! -s "$ERR" ]] || log_fail "no --human flag: stderr must stay empty: $(cat "$ERR")"

  # --human: stdout STAYS parseable JSON; stderr carries the dispatch block.
  run_dispatch "$d" --human
  [[ "$EC" == 0 ]] || log_fail "--human must not change the exit code (got $EC)"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "11"'
  grep -q "Role:" "$ERR" || log_fail "--human stderr must carry the DISPATCH FORMAT block: $(cat "$ERR")"
  grep -q "Stop condition:" "$ERR" || log_fail "--human stderr must carry a stop condition line"

  # paused -> no_action exit 3, JSON still on stdout.
  local d3
  d3="$(mk_root t2-paused)"
  write_dstate "$d3/docs/ai/STATE.yaml"
  sed -i.bak 's/^project_status: active$/project_status: paused/' "$d3/docs/ai/STATE.yaml" && rm -f "$d3/docs/ai/STATE.yaml.bak"
  run_dispatch "$d3"
  [[ "$EC" == 3 ]] || log_fail "paused fixture must exit 3 (got $EC): $(cat "$OUT")"
  jassert "$OUT" 'o.verdict === "no_action" && o.rule === "1" && o.role === null'

  # --rules prints the table derived from the SAME rule objects.
  local rl="$TEST_DIR/rules.log" n
  (cd "$PROJECT_ROOT" && node .aai/scripts/orchestration-dispatch.mjs --rules > "$rl" 2>&1) \
    || log_fail "--rules must exit 0: $(cat "$rl")"
  for n in 1 2 3 4 5 6 7 8 9a 9b 9c 10 11 12 13 14; do
    grep -qE "(^| )${n}[ :|.)]" "$rl" || log_fail "--rules table must list rule ${n}: $(cat "$rl")"
  done
  log_pass "CLI: D3 JSON shape, exit 0/3, --human stderr block, --rules table (TEST-002)"
}

# --- TEST-003: SPEC-0012 G3 post-remediation reset routing ---------------------

test_003_reset_routing() {
  log_info "Test: reset routing 10->11, 12->13, pass+review-reset never re-fires 11 (TEST-003)..."
  # (a) post-remediation: last_validation reset fail->not_run -> rule 11 fresh Validation.
  local d
  d="$(mk_root t3a)"
  write_dstate "$d/docs/ai/STATE.yaml" not_run not_run remediation in_progress
  append_metrics_block "$d/docs/ai/STATE.yaml" CHANGE-0001 \
    "        - role: Implementation" \
    "          model_id: claude-impl-x" \
    "          started_utc: 2026-07-01T00:00:00Z" \
    "          ended_utc: 2026-07-01T00:01:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null" \
    "        - role: Remediation" \
    "          model_id: claude-rem-x" \
    "          started_utc: 2026-07-01T00:02:00Z" \
    "          ended_utc: 2026-07-01T00:03:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) reset->not_run must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "11" && o.role === "Validation"'
  jassert "$OUT" 'o.validator_independence !== null && o.validator_independence.must_differ === true'

  # (b) review fail remediated + review reset -> rule 13 fresh Code Review.
  local db
  db="$(mk_root t3b)"
  write_dstate "$db/docs/ai/STATE.yaml" pass not_run code_review in_progress
  run_dispatch "$db"
  [[ "$EC" == 0 ]] || log_fail "(b) review-reset must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "13" && o.role === "Code Review"'

  # (c) pass + ONLY code_review reset: rule 11 must NOT re-fire (a recorded
  # pass counts as run) — rule 13 dispatches.
  local dc
  dc="$(mk_root t3c)"
  write_dstate "$dc/docs/ai/STATE.yaml" pass not_run remediation in_progress
  run_dispatch "$dc"
  [[ "$EC" == 0 ]] || log_fail "(c) must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "13" && o.role === "Code Review" && o.rule !== "11"'
  log_pass "Reset routing emergent from the proxies: 10->11, 12->13, pass+review-reset->13 (TEST-003)"
}

# --- TEST-004: fail-closed degrade (exit 4 + named reasons, zero writes) -------

test_004_fail_closed() {
  log_info "Test: invalid STATE + judgment edges -> exit 4, named reasons, zero writes (TEST-004)..."
  local d
  # (a) missing STATE file.
  d="$(mk_root t4a)"
  rm -f "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(a) missing STATE must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "needs_llm" && o.reasons.some(r => r.includes("state_file_missing"))'

  # (b) duplicate top-level key.
  d="$(mk_root t4b)"
  write_dstate "$d/docs/ai/STATE.yaml"
  printf 'metrics:\n  work_items: {}\nmetrics:\n  work_items: {}\n' >> "$d/docs/ai/STATE.yaml"
  local before after
  before="$(cksum "$d/docs/ai/STATE.yaml")"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(b) duplicate key must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "needs_llm" && o.reasons.some(r => r.includes("duplicate_top_level_key"))'
  after="$(cksum "$d/docs/ai/STATE.yaml")"
  [[ "$before" == "$after" ]] || log_fail "(b) the script must NEVER write STATE"

  # (c) unknown enum value.
  d="$(mk_root t4c)"
  write_dstate "$d/docs/ai/STATE.yaml"
  sed -i.bak 's/^project_status: active$/project_status: bananas/' "$d/docs/ai/STATE.yaml" && rm -f "$d/docs/ai/STATE.yaml.bak"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(c) unknown enum must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.reasons.some(r => r.includes("unknown_enum_value"))'

  # (d) missing required block.
  d="$(mk_root t4d)"
  write_dstate "$d/docs/ai/STATE.yaml"
  # strip the whole current_focus block
  awk 'BEGIN{skip=0} /^current_focus:/{skip=1;next} skip && /^[a-z_]+:/{skip=0} !skip{print}' \
    "$d/docs/ai/STATE.yaml" > "$d/docs/ai/STATE.tmp" && mv "$d/docs/ai/STATE.tmp" "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(d) missing block must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.reasons.some(r => r.includes("missing_required_block"))'

  # (e) judgment edge — stale pass: validation pass names ANOTHER ref.
  d="$(mk_root t4e)"
  write_dstate "$d/docs/ai/STATE.yaml" pass not_run implementation in_progress tdd optional inline OTHER-9999
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(e) stale-pass edge must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.reasons.some(r => r.includes("validation_staleness_unknown"))'

  # (f) judgment edge — review staleness: verdicts pass but the LAST agent run
  # is an implementer role (code changed after the review).
  d="$(mk_root t4f)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass implementation in_progress
  append_metrics_block "$d/docs/ai/STATE.yaml" CHANGE-0001 \
    "        - role: Remediation" \
    "          model_id: claude-rem-x" \
    "          started_utc: 2026-07-01T00:00:00Z" \
    "          ended_utc: 2026-07-01T00:01:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(f) review-staleness edge must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.reasons.some(r => r.includes("review_staleness_unknown"))'

  # (g) judgment edge — missing-reset forensics: validation fail but the last
  # run is already a Remediation (the reset is what is missing).
  d="$(mk_root t4g)"
  write_dstate "$d/docs/ai/STATE.yaml" fail not_run remediation in_progress
  append_metrics_block "$d/docs/ai/STATE.yaml" CHANGE-0001 \
    "        - role: Remediation" \
    "          model_id: claude-rem-x" \
    "          started_utc: 2026-07-01T00:00:00Z" \
    "          ended_utc: 2026-07-01T00:01:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null"
  before="$(cksum "$d/docs/ai/STATE.yaml")"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(g) missing-reset forensics must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.reasons.some(r => r.includes("possible_missing_remediation_reset"))'
  after="$(cksum "$d/docs/ai/STATE.yaml")"
  [[ "$before" == "$after" ]] || log_fail "(g) the script must NEVER write STATE"

  # (h) usage error: unknown flag -> exit 2.
  local ec2=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/orchestration-dispatch.mjs --nope > /dev/null 2>&1) || ec2=$?
  [[ "$ec2" == 2 ]] || log_fail "(h) unknown flag must exit 2 (got $ec2)"
  log_pass "Fail-closed: exit 4 + named machine-greppable reasons, zero writes; exit 2 usage (TEST-004)"
}

# --- TEST-005: rule-14 flush arm + validator independence ----------------------

test_005_flush_arm_and_independence() {
  log_info "Test: rule 14 flush arm (absent->dispatch, present->exit 3) + validator_independence (TEST-005)..."
  local d
  # (a) PASS + review pass + ref ABSENT from the ledger -> Metrics Flush dispatch.
  d="$(mk_root t5a)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass implementation in_progress
  printf '# ledger comment\n' > "$d/docs/ai/METRICS.jsonl"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) unflushed PASS must dispatch Metrics Flush (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "14" && o.role === "Metrics Flush" && o.suggested_tier === "mechanical"'
  jassert "$OUT" 'o.system_prompt === ".aai/METRICS_FLUSH.prompt.md"'

  # (b) ref PRESENT in the ledger -> no_action exit 3.
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' >> "$d/docs/ai/METRICS.jsonl"
  run_dispatch "$d"
  [[ "$EC" == 3 ]] || log_fail "(b) flushed ref must be no_action exit 3 (got $EC): $(cat "$OUT")"
  jassert "$OUT" 'o.verdict === "no_action" && o.rule === "14"'

  # (c) Validation dispatch carries validator_independence with the LAST
  # implementer model read from metrics.work_items[ref].agent_runs.
  d="$(mk_root t5c)"
  write_dstate "$d/docs/ai/STATE.yaml" not_run not_run implementation in_progress
  append_metrics_block "$d/docs/ai/STATE.yaml" CHANGE-0001 \
    "        - role: Implementation" \
    "          model_id: claude-early-model" \
    "          started_utc: 2026-07-01T00:00:00Z" \
    "          ended_utc: 2026-07-01T00:01:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null" \
    "        - role: TDD Implementation" \
    "          model_id: claude-impl-final" \
    "          started_utc: 2026-07-01T00:02:00Z" \
    "          ended_utc: 2026-07-01T00:03:00Z" \
    "          duration_seconds: 60" \
    "          tokens_in: null" \
    "          tokens_out: null" \
    "          cost_usd: null"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(c) must dispatch Validation (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "11" && o.role === "Validation"'
  jassert "$OUT" 'o.validator_independence && o.validator_independence.implementer_model === "claude-impl-final" && o.validator_independence.must_differ === true'
  # Non-Validation dispatch carries null independence.
  local d2
  d2="$(mk_root t5d)"
  write_dstate "$d2/docs/ai/STATE.yaml" pass not_run implementation in_progress
  run_dispatch "$d2"
  jassert "$OUT" 'o.rule === "13" && o.validator_independence === null'
  log_pass "Rule-14 flush arm + validator_independence payload correct (TEST-005)"
}

## ==========================================================================
## spec-dispatch-new-intake-after-completed-scope (SPEC-0042, CHANGE-0031)
## TEST-001..007, mapped to suite functions test_006..test_012. New fixtures
## live ONLY here (SPEC-0041 D5 reserved this suite for this scope); the
## CHANGE-0009 stanzas above (test_001..005) are never edited.
## ==========================================================================

# --- TEST-006 (Spec TEST-001/Spec-AC-01): decide() 4a table ---------------------

test_006_arm4a_decide_table() {
  log_info "Test: decide() 4a arm: done+flushed / absent+flushed + one open intake -> Planning retarget with payload/reason/lane full; done+unflushed -> close pipeline untouched (TEST-001)..."
  cat > "$TEST_DIR/t6.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const candidate = {
  ref_id: 'docs-audit-d2-evidence-hardening',
  primary_path: 'docs/issues/CHANGE-0028-docs-audit-d2-evidence-hardening.md',
  doc_type: 'change',
  item_status: 'draft',
  unmappable: false,
};

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'validation', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'done', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'pass', ref_id: 'CHANGE-0027' },
  review: { required: true, status: 'pass' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Metrics Flush',
  open_intakes: [candidate],
});

// (1) done + flushed -> 4a retarget dispatch.
{
  const d = decide(base());
  assert.strictEqual(d.verdict, 'dispatch');
  assert.strictEqual(d.rule, '4a');
  assert.strictEqual(d.role, 'Planning');
  assert.strictEqual(d.ref_id, candidate.ref_id);
  assert.deepStrictEqual(d.retarget, {
    from_ref: 'CHANGE-0027', to_ref: candidate.ref_id, to_type: 'intake_change', to_primary_path: candidate.primary_path,
  });
  assert.ok(d.reasons.includes('focus_completed_retarget_to_open_intake'), JSON.stringify(d.reasons));
  assert.deepStrictEqual(d.lane, { selected: 'full', ceremony_level: 2, validation_depth: 'full' });
  assert.ok(d.inputs.includes(candidate.primary_path) && d.inputs.includes('docs/TECHNOLOGY.md'), JSON.stringify(d.inputs));
  assert.ok(!d.inputs.includes('docs/specs/SPEC-0027-fx.md'), 'must not carry the CLOSED scope spec path into the new-scope inputs');
}

// (2) absent (flushed removed the item) + flushed -> same retarget shape.
{
  const s = base();
  s.work_item = null;
  const d = decide(s);
  assert.strictEqual(d.verdict, 'dispatch');
  assert.strictEqual(d.rule, '4a');
  assert.strictEqual(d.retarget.to_ref, candidate.ref_id);
}

// (3) done but NOT yet flushed -> the normal close pipeline (rule 14) fires
// untouched; 4a must not hijack a not-yet-flushed done item.
{
  const s = base();
  s.flushed = false;
  s.spec.frontmatter_status = 'implementing';
  const d = decide(s);
  assert.strictEqual(d.rule, '14', JSON.stringify(d));
  assert.strictEqual(d.role, 'Metrics Flush');
  assert.strictEqual(d.retarget, null);
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t6.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t6.log" 2>&1 \
    || log_fail "decide() 4a arm table failed: $(cat "$TEST_DIR/t6.log")"
  log_pass "decide() 4a arm: retarget dispatch (done/absent+flushed), close pipeline untouched when unflushed (TEST-006/spec TEST-001)"
}

# --- TEST-007 (Spec TEST-002/Spec-AC-02): rule-11 done-skip ---------------------

test_007_rule11_done_skip() {
  log_info "Test: rule-11 done-skip: done+not_run never dispatches Validation (flushed -> 4a; unflushed -> needs_llm no_rule_matched); non-done items still fire rule 11 (TEST-002)..."
  cat > "$TEST_DIR/t7rule11.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'implementation', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'implementing', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: null,
  open_intakes: [],
});

// (a) done + not_run + flushed -> 4a resolves it (here: zero candidates -> no_action), NEVER rule 11.
{
  const s = base();
  s.flushed = true;
  const d = decide(s);
  assert.notStrictEqual(d.rule, '11', JSON.stringify(d));
  assert.strictEqual(d.rule, '4a');
  assert.strictEqual(d.verdict, 'no_action');
}

// (b) done + not_run + NOT flushed -> degrades to needs_llm no_rule_matched
// (structurally ambiguous residue, D5 recorded edge case).
{
  const d = decide(base());
  assert.strictEqual(d.verdict, 'needs_llm');
  assert.strictEqual(d.rule, null);
  assert.ok(d.reasons.includes('no_rule_matched'), JSON.stringify(d.reasons));
}

// (c) non-done item in an eligible phase still fires rule 11 exactly as today.
for (const phase of ['implementation', 'validation', 'remediation', 'code_review']) {
  const s = base();
  s.work_item = { phase, status: 'in_progress' };
  const d = decide(s);
  assert.strictEqual(d.rule, '11', `phase ${phase}: ${JSON.stringify(d)}`);
  assert.strictEqual(d.role, 'Validation');
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t7rule11.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t7rule11.log" 2>&1 \
    || log_fail "rule-11 done-skip failed: $(cat "$TEST_DIR/t7rule11.log")"
  log_pass "Rule 11 never fires on a done work item; non-done items unaffected (TEST-007/spec TEST-002)"
}

# --- TEST-008 (Spec TEST-003/Spec-AC-03): decide() ambiguity outcomes -----------

test_008_arm4a_ambiguity() {
  log_info "Test: decide() 4a ambiguity: 0 -> no_action scope_complete_no_open_intake; 2+ -> needs_llm multiple_open_intakes; unmappable -> open_intake_unmappable; scan-failed -> open_intake_scan_failed (TEST-003)..."
  cat > "$TEST_DIR/t8.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: null,
  spec: { path: null, present: false, frozen: false, frontmatter_status: null, ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'pass', ref_id: 'CHANGE-0027' },
  review: { required: true, status: 'pass' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Metrics Flush',
  open_intakes: [],
});

// (a) zero candidates -> no_action, exit-class rule 4a, named reason.
{
  const d = decide(base());
  assert.strictEqual(d.verdict, 'no_action');
  assert.strictEqual(d.rule, '4a');
  assert.deepStrictEqual(d.reasons, ['scope_complete_no_open_intake']);
  assert.strictEqual(d.retarget, null);
}

// (b) two or more candidates -> needs_llm, reason names EVERY candidate ref.
{
  const s = base();
  s.open_intakes = [
    { ref_id: 'CHANGE-0002', primary_path: 'docs/issues/CHANGE-0002-a.md', doc_type: 'change', item_status: 'draft', unmappable: false },
    { ref_id: 'CHANGE-0003', primary_path: 'docs/issues/CHANGE-0003-b.md', doc_type: 'issue', item_status: 'implementing', unmappable: false },
  ];
  const d = decide(s);
  assert.strictEqual(d.verdict, 'needs_llm');
  assert.strictEqual(d.rule, '4a');
  assert.strictEqual(d.reasons.length, 1);
  assert.ok(/^multiple_open_intakes:/.test(d.reasons[0]), d.reasons[0]);
  assert.ok(d.reasons[0].includes('CHANGE-0002') && d.reasons[0].includes('CHANGE-0003'), d.reasons[0]);
  assert.strictEqual(d.retarget, null);
}

// (c) single unmappable candidate (e.g. techdebt, no enum member) -> named reason.
{
  const s = base();
  s.open_intakes = [
    { ref_id: 'prompt-diet-byte-budget-true-up', primary_path: 'docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md', doc_type: 'techdebt', item_status: 'draft', unmappable: true },
  ];
  const d = decide(s);
  assert.strictEqual(d.verdict, 'needs_llm');
  assert.strictEqual(d.rule, '4a');
  assert.deepStrictEqual(d.reasons, ['open_intake_unmappable:docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md']);
}

// (d) probe failure (open_intakes: null) -> named reason, never a guess.
{
  const s = base();
  s.open_intakes = null;
  const d = decide(s);
  assert.strictEqual(d.verdict, 'needs_llm');
  assert.strictEqual(d.rule, '4a');
  assert.deepStrictEqual(d.reasons, ['open_intake_scan_failed']);
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t8.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t8.log" 2>&1 \
    || log_fail "4a ambiguity outcomes failed: $(cat "$TEST_DIR/t8.log")"
  log_pass "Fail-closed ambiguity: 0/2+/unmappable/scan-failed all named, never a guess (TEST-008/spec TEST-003)"
}

# --- TEST-009 (Spec TEST-004/Spec-AC-01+03): CLI end-to-end on fixture repos ----

test_009_cli_integration() {
  log_info "Test: CLI 4a end-to-end on REAL docs/issues fixtures: exit 0/3/4, retarget payload valid for set-focus, mixed ref-convention, scan-failure, retarget null elsewhere (TEST-004)..."
  local d

  # (a) exit 0 + mixed ref-convention: the candidate's OWN active_work_items
  # entry uses a number-based ref (CHANGE-0002) while its frontmatter carries a
  # DIFFERENT slug id -- primary_path match must win (D2), not the frontmatter id.
  d="$(mk_root t9a)"
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0027
  primary_path: docs/issues/CHANGE-0027-fixture.md
active_work_items:
  - ref_id: CHANGE-0027
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0027-fixture.md
    spec_path: docs/specs/SPEC-0001-fx.md
  - ref_id: CHANGE-0002
    status: planned
    phase: planning
    primary_path: docs/issues/CHANGE-0002-other.md
    spec_path: null
implementation_strategy:
  selected: tdd
  source: null
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
  status: pass
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: CHANGE-0027
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
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0027","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-other.md" some-slug-id change 2 draft
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) 4a retarget must exit 0 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "4a" && o.role === "Planning"'
  jassert "$OUT" 'o.ref_id === "CHANGE-0002"'
  jassert "$OUT" 'o.retarget.from_ref === "CHANGE-0027" && o.retarget.to_ref === "CHANGE-0002" && o.retarget.to_type === "intake_change" && o.retarget.to_primary_path === "docs/issues/CHANGE-0002-other.md"'
  jassert "$OUT" '["intake_change","intake_issue","intake_prd","intake_hotfix","intake_research","intake_rfc","intake_release","technology_extraction","maintenance","none"].includes(o.retarget.to_type)'
  jassert "$OUT" 'o.lane.selected === "full" && o.lane.ceremony_level === 2 && o.lane.validation_depth === "full"'
  jassert "$OUT" 'o.inputs.includes("docs/issues/CHANGE-0002-other.md") && o.inputs.includes("docs/TECHNOLOGY.md")'

  # (b) zero candidates -> no_action exit 3.
  d="$(mk_root t9b)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass validation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  run_dispatch "$d"
  [[ "$EC" == 3 ]] || log_fail "(b) zero candidates must exit 3 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "no_action" && o.rule === "4a" && o.reasons.includes("scope_complete_no_open_intake") && o.retarget === null'

  # (c) two candidates -> needs_llm exit 4, naming every ref.
  d="$(mk_root t9c)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass validation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-a.md" CHANGE-0002 change 2 draft
  write_intake_doc "$d/docs/issues/CHANGE-0003-b.md" CHANGE-0003 change 3 implementing
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(c) two candidates must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "needs_llm" && o.rule === "4a" && o.retarget === null'
  jassert "$OUT" 'o.reasons.some(r => /^multiple_open_intakes:/.test(r) && r.includes("CHANGE-0002") && r.includes("CHANGE-0003"))'

  # (d) single unmappable candidate (techdebt) -> needs_llm exit 4, named path.
  d="$(mk_root t9d)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass validation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/DEBT-0001-techdebt.md" some-debt-id techdebt 1 draft
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(d) unmappable candidate must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "needs_llm" && o.rule === "4a"'
  jassert "$OUT" 'o.reasons.includes("open_intake_unmappable:docs/issues/DEBT-0001-techdebt.md")'

  # (e) directory scan failure (docs/issues is not a directory) -> needs_llm exit 4.
  d="$(mk_root t9e)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass validation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  rm -rf "$d/docs/issues"
  printf 'not a directory' > "$d/docs/issues"
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "(e) scan failure must exit 4 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "needs_llm" && o.rule === "4a" && o.reasons.includes("open_intake_scan_failed")'

  # (f) non-4a verdict still carries retarget: null (additive-only contract).
  d="$(mk_root t9f)"
  write_dstate "$d/docs/ai/STATE.yaml"   # not_run + phase implementation, status in_progress -> rule 11
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(f) live-focus fixture must still dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "11" && o.retarget === null'

  log_pass "CLI 4a end-to-end: exit 0/3/4 shapes, mixed-convention match, scan failure, retarget null elsewhere (TEST-009/spec TEST-004)"
}

# --- TEST-010 (Spec TEST-005/Spec-AC-05): evidence replay -----------------------

test_010_evidence_replay() {
  log_info "Test: evidence replay -- tick-1 (2026-07-17) -> 4a retarget; tick-9 (2026-07-16) -> no_action; neither needs_llm (TEST-005)..."
  local d

  # Tick-1 shape (LOOP_TICKS line 11): CHANGE-0027 done+flushed, its spec
  # present with terminal (done) frontmatter status, ONE open intake with no
  # work item yet (docs-audit-d2-evidence-hardening). Pre-change this fixture
  # reproduces the stale rule-6 Planning dispatch on the closed scope.
  d="$(mk_root t10-tick1)"
  write_spec "$d/docs/specs/SPEC-0039-fx.md" done true
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0027
  primary_path: docs/issues/CHANGE-0027-false-open-drift-heuristic.md
  spec_path: docs/specs/SPEC-0039-fx.md
active_work_items: []
implementation_strategy:
  selected: tdd
  source: null
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
  status: pass
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-16T23:40:00Z
  ref_id: CHANGE-0027
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
updated_at_utc: 2026-07-17T00:00:00Z
YAML
  printf '{"date_utc":"2026-07-16","ref_id":"CHANGE-0027","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0028-docs-audit-d2-evidence-hardening.md" docs-audit-d2-evidence-hardening change 28 draft
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "tick-1 replay must dispatch 4a retarget (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "4a" && o.role === "Planning"'
  jassert "$OUT" 'o.retarget && o.retarget.from_ref === "CHANGE-0027" && o.retarget.to_ref === "docs-audit-d2-evidence-hardening"'

  # Tick-9 shape (LOOP_TICKS line 10): focus done+flushed, last_validation
  # reset to not_run (H5-reset residue), zero open intakes. Pre-change this
  # fixture reproduces the rule-11 Validation dispatch on a flushed corpse.
  d="$(mk_root t10-tick9)"
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0027
  primary_path: docs/issues/CHANGE-0027-false-open-drift-heuristic.md
active_work_items: []
implementation_strategy:
  selected: tdd
  source: null
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
  run_at_utc: 2026-07-16T23:50:00Z
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
updated_at_utc: 2026-07-16T23:50:00Z
YAML
  printf '{"date_utc":"2026-07-16","ref_id":"CHANGE-0027","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  run_dispatch "$d"
  [[ "$EC" == 3 ]] || log_fail "tick-9 replay must resolve no_action (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "no_action" && o.rule === "4a" && o.reasons.includes("scope_complete_no_open_intake")'

  log_pass "Evidence replay: tick-1 -> 4a retarget, tick-9 -> no_action; neither needs_llm (TEST-010/spec TEST-005)"
}

# --- TEST-011 (Spec TEST-006/Spec-AC-04): seam survival -------------------------

test_011_seam_survival() {
  log_info "Test: seam survival -- legacy dispatch stanzas + real ceremony-suite lane stanzas green; live-focus additive-only diff retarget:null (TEST-006)..."
  # (a) the full legacy dispatch suite (CHANGE-0009 TEST-001..005), re-run
  # post-change (S1 crossing test).
  test_001_decide_table
  test_002_cli_contract
  test_003_reset_routing
  test_004_fail_closed
  test_005_flush_arm_and_independence

  # (b) the REAL ceremony-suite lane stanzas, single-function invocation
  # (LEARNED 2026-07-17 masking note: the suite's main() aborts on the
  # pre-existing prompt-diet TEST-010 byte-budget shortfall before reaching
  # test_011..016, so each function is invoked directly here).
  local ceremony_log="$TEST_DIR/t11-ceremony.log" fn
  : > "$ceremony_log"
  for fn in test_011_decide_lane_table test_012_validation_dispatch_payload test_013_cli_lane_field \
            test_014_fixture_chain_lightweight test_015_prompt_lane_surfaces test_016_misuse_guard_survival; do
    (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-ceremony-levels.sh "$fn") >> "$ceremony_log" 2>&1 \
      || log_fail "ceremony-suite stanza $fn must stay green: $(tail -30 "$ceremony_log")"
  done

  # (c) live-focus (non-done) fixture output differs from pre-change ONLY by
  # the additive retarget: null field.
  local d
  d="$(mk_root t11live)"
  write_dstate "$d/docs/ai/STATE.yaml"   # not_run + phase implementation, status in_progress -> rule 11
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "live-focus fixture must still dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "11" && o.role === "Validation" && o.retarget === null'

  log_pass "Seam survival: legacy dispatch + real ceremony-suite stanzas green; live-focus additive-only diff (TEST-011/spec TEST-006)"
}

# --- TEST-012 (Spec TEST-007/Spec-AC-06): purity + zero-writes + hygiene -------

test_012_purity_and_hygiene() {
  log_info "Test: decide() purity on retarget snapshots + CLI zero-writes (cksum) + docs-audit strict + check-state (TEST-007)..."
  cat > "$TEST_DIR/t12.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const s1 = {
  project_status: 'active', human_input_required: false, technology_present: true, workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: null,
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'done', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'pass', ref_id: 'CHANGE-0027' },
  review: { required: true, status: 'pass' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Metrics Flush',
  open_intakes: [{ ref_id: 'docs-audit-d2-evidence-hardening', primary_path: 'docs/issues/CHANGE-0028-docs-audit-d2-evidence-hardening.md', doc_type: 'change', item_status: 'draft', unmappable: false }],
};
const frozen = JSON.stringify(s1);
const a = decide(s1);
const b = decide(JSON.parse(frozen));
assert.strictEqual(JSON.stringify(a), JSON.stringify(b), 'decide must be deterministic on retarget snapshots');
assert.strictEqual(JSON.stringify(s1), frozen, 'decide must not mutate its retarget-snapshot input');
assert.strictEqual(a.rule, '4a');
assert.strictEqual(a.verdict, 'dispatch');
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t12.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t12.log" 2>&1 \
    || log_fail "decide() purity on retarget snapshot failed: $(cat "$TEST_DIR/t12.log")"

  # CLI zero-writes: cksum STATE + the fixture docs/issues tree unchanged
  # across a 4a-shaped run.
  local d before_state after_state before_issues after_issues
  d="$(mk_root t12cli)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass implementation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-other.md" CHANGE-0002 change 2 draft
  before_state="$(cksum "$d/docs/ai/STATE.yaml")"
  before_issues="$(find "$d/docs/issues" -type f -exec cksum {} \; | sort)"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "purity fixture must dispatch 4a (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.rule === "4a" && o.retarget !== null'
  after_state="$(cksum "$d/docs/ai/STATE.yaml")"
  after_issues="$(find "$d/docs/issues" -type f -exec cksum {} \; | sort)"
  [[ "$before_state" == "$after_state" ]] || log_fail "the 4a arm must NEVER write STATE"
  [[ "$before_issues" == "$after_issues" ]] || log_fail "the 4a arm must NEVER write the docs/issues fixture tree"

  # Repo-wide hygiene gates.
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t12-audit.log" 2>&1) \
    || log_fail "docs-audit --check --strict --no-event must exit 0: $(tail -30 "$TEST_DIR/t12-audit.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs > "$TEST_DIR/t12-checkstate.log" 2>&1) \
    || log_fail "check-state.mjs must exit 0: $(tail -30 "$TEST_DIR/t12-checkstate.log")"
  grep -q "OK" "$TEST_DIR/t12-checkstate.log" || log_fail "check-state.mjs must report OK: $(cat "$TEST_DIR/t12-checkstate.log")"

  log_pass "Purity on retarget snapshots + zero writes + docs-audit strict + check-state OK (TEST-012/spec TEST-007)"
}

## ==========================================================================
## dispatch-4a-fail-verdict-precedence (SPEC-0050, CHANGE-0036)
## Spec TEST-001..006, mapped to suite functions test_013..test_018. New
## fixtures live ONLY here (SPEC-0041 D5 reserved this suite for this
## dispatch scope); test_001..test_012 above are never edited.
## ==========================================================================

# --- TEST-013 (Spec TEST-001/Spec-AC-01): validation fail -> rule 10, not 4a ---

test_013_fail_verdict_validation_precedence() {
  log_info "Test: decide(): done+flushed + validation fail + one open intake + eligible shape -> rule 10 Remediation, not 4a (Spec TEST-001)..."
  cat > "$TEST_DIR/t13.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const candidate = {
  ref_id: 'some-open-intake',
  primary_path: 'docs/issues/CHANGE-9999-some-open-intake.md',
  doc_type: 'change',
  item_status: 'draft',
  unmappable: false,
};

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'validation', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'implementing', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'fail', ref_id: 'CHANGE-0027' },
  review: { required: true, status: 'not_run' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Validation',
  open_intakes: [candidate],
});

const d = decide(base());
assert.strictEqual(d.verdict, 'dispatch', JSON.stringify(d));
assert.strictEqual(d.rule, '10', JSON.stringify(d));
assert.strictEqual(d.role, 'Remediation', JSON.stringify(d));
assert.strictEqual(d.retarget, null, JSON.stringify(d));
assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t13.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t13.log" 2>&1 \
    || log_fail "validation-fail precedence over 4a failed: $(cat "$TEST_DIR/t13.log")"
  log_pass "decide(): validation fail on done+flushed focus -> rule 10 Remediation, not 4a (TEST-013/spec TEST-001)"
}

# --- TEST-014 (Spec TEST-002/Spec-AC-02): code_review fail -> rule 12, not 4a --

test_014_fail_verdict_review_precedence() {
  log_info "Test: decide(): done+flushed + validation not_run + code_review fail + phase code_review -> rule 12 Remediation, not 4a (Spec TEST-002)..."
  cat > "$TEST_DIR/t14.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const candidate = {
  ref_id: 'some-open-intake',
  primary_path: 'docs/issues/CHANGE-9999-some-open-intake.md',
  doc_type: 'change',
  item_status: 'draft',
  unmappable: false,
};

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'code_review', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'implementing', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'fail' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Code Review',
  open_intakes: [candidate],
});

const d = decide(base());
assert.strictEqual(d.verdict, 'dispatch', JSON.stringify(d));
assert.strictEqual(d.rule, '12', JSON.stringify(d));
assert.strictEqual(d.role, 'Remediation', JSON.stringify(d));
assert.strictEqual(d.retarget, null, JSON.stringify(d));
assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t14.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t14.log" 2>&1 \
    || log_fail "code_review-fail precedence over 4a failed: $(cat "$TEST_DIR/t14.log")"
  log_pass "decide(): code_review fail on done+flushed focus -> rule 12 Remediation, not 4a (TEST-014/spec TEST-002)"
}

# --- TEST-015 (Spec TEST-003/Spec-AC-01+02): CLI end-to-end fail precedence ----

test_015_cli_fail_precedence() {
  log_info "Test: CLI end-to-end on real fixture repos: validation-fail -> exit 0 rule 10; review-fail -> exit 0 rule 12; retarget null in both (Spec TEST-003)..."
  local d

  # (a) validation fail, done+flushed, eligible phase validation -> rule 10.
  d="$(mk_root t15a)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" implementing true
  write_dstate "$d/docs/ai/STATE.yaml" fail not_run validation done tdd optional inline CHANGE-0001 true
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-other.md" CHANGE-0002 change 2 draft
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) validation-fail fixture must exit 0 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "10" && o.role === "Remediation"'
  jassert "$OUT" 'o.retarget === null'

  # (b) code_review fail, done+flushed, eligible phase code_review -> rule 12.
  d="$(mk_root t15b)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" implementing true
  write_dstate "$d/docs/ai/STATE.yaml" not_run fail code_review done tdd optional inline CHANGE-0001 true
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-other.md" CHANGE-0002 change 2 draft
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) review-fail fixture must exit 0 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "12" && o.role === "Remediation"'
  jassert "$OUT" 'o.retarget === null'

  log_pass "CLI end-to-end: validation-fail -> rule 10, review-fail -> rule 12, retarget null (TEST-015/spec TEST-003)"
}

# --- TEST-016 (Spec TEST-004/Spec-AC-03): survival + negative control ---------

test_016_survival_negative_control() {
  log_info "Test: negative control -- no-fail done+flushed+one intake retains today's 4a retarget; full legacy suite test_001..012 stays green, zero assertion edits (Spec TEST-004)..."
  local d

  # Negative control: no fail verdict present -> rule 4a fires exactly as
  # before the guard (unaffected).
  d="$(mk_root t16neg)"
  write_dstate "$d/docs/ai/STATE.yaml" pass pass validation done tdd optional inline CHANGE-0001
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' > "$d/docs/ai/METRICS.jsonl"
  write_intake_doc "$d/docs/issues/CHANGE-0002-other.md" CHANGE-0002 change 2 draft
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "negative control must still exit 0 (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "4a" && o.role === "Planning"'
  jassert "$OUT" 'o.retarget !== null && o.retarget.to_ref === "CHANGE-0002"'

  # Survival: the FULL legacy suite (test_001..test_012, which internally
  # re-runs the real ceremony-suite lane stanzas via test_011) re-run
  # post-change, zero assertion edits (Seam S1 crossing test).
  test_001_decide_table
  test_002_cli_contract
  test_003_reset_routing
  test_004_fail_closed
  test_005_flush_arm_and_independence
  test_006_arm4a_decide_table
  test_007_rule11_done_skip
  test_008_arm4a_ambiguity
  test_009_cli_integration
  test_010_evidence_replay
  test_011_seam_survival
  test_012_purity_and_hygiene

  log_pass "Survival + negative control: 4a unchanged with no fail verdict; full legacy suite exit 0 (TEST-016/spec TEST-004)"
}

# --- TEST-017 (Spec TEST-005/Spec-AC-05): fail-closed invariant, parametric ----

test_017_fail_closed_invariant() {
  log_info "Test: fail-closed invariant -- done+validation fail, done+review fail, work_item null+fail, both fail -- NONE yields a 4a dispatch/non-null retarget (Spec TEST-005)..."
  cat > "$TEST_DIR/t17.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const candidate = {
  ref_id: 'some-open-intake',
  primary_path: 'docs/issues/CHANGE-9999-some-open-intake.md',
  doc_type: 'change',
  item_status: 'draft',
  unmappable: false,
};

const base = () => ({
  project_status: 'active',
  human_input_required: false,
  technology_present: true,
  workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'validation', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'implementing', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'not_run' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Validation',
  open_intakes: [candidate],
});

// (1) done + validation fail.
{
  const s = base();
  s.validation = { status: 'fail', ref_id: 'CHANGE-0027' };
  const d = decide(s);
  assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
  assert.strictEqual(d.retarget, null, JSON.stringify(d));
}

// (2) done + review fail (eligible phase code_review).
{
  const s = base();
  s.work_item = { phase: 'code_review', status: 'done' };
  s.review = { required: true, status: 'fail' };
  const d = decide(s);
  assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
  assert.strictEqual(d.retarget, null, JSON.stringify(d));
}

// (3) work_item == null + validation fail -> needs_llm focus_ref_not_in_active_work_items.
{
  const s = base();
  s.work_item = null;
  s.validation = { status: 'fail', ref_id: 'CHANGE-0027' };
  const d = decide(s);
  assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
  assert.strictEqual(d.verdict, 'needs_llm', JSON.stringify(d));
  assert.ok(d.reasons.includes('focus_ref_not_in_active_work_items'), JSON.stringify(d.reasons));
  assert.strictEqual(d.retarget, null, JSON.stringify(d));
}

// (4) both verdicts fail -> still abstains (no 4a retarget).
{
  const s = base();
  s.validation = { status: 'fail', ref_id: 'CHANGE-0027' };
  s.review = { required: true, status: 'fail' };
  const d = decide(s);
  assert.notStrictEqual(d.rule, '4a', JSON.stringify(d));
  assert.strictEqual(d.retarget, null, JSON.stringify(d));
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t17.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t17.log" 2>&1 \
    || log_fail "fail-closed invariant failed: $(cat "$TEST_DIR/t17.log")"
  log_pass "Fail-closed invariant: no 4a retarget for any fail shape, incl. null work_item (TEST-017/spec TEST-005)"
}

# --- TEST-018 (Spec TEST-006/Spec-AC-04): purity + 4a doc-string guard --------

test_018_purity_and_docstring_guard() {
  log_info "Test: decide() purity on a fail-verdict snapshot (double-decide + input-freeze) + RULES 4a when doc string documents the abstention guard (Spec TEST-006)..."
  cat > "$TEST_DIR/t18.mjs" <<'EOF'
import assert from 'node:assert';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { decide } = await import(pathToFileURL(path.join(process.argv[2], '.aai/scripts/orchestration-dispatch.mjs')).href);

const s1 = {
  project_status: 'active', human_input_required: false, technology_present: true, workflow_present: true,
  locks_present: false,
  focus: { type: 'intake_change', ref_id: 'CHANGE-0027' },
  work_item: { phase: 'validation', status: 'done' },
  spec: { path: 'docs/specs/SPEC-0027-fx.md', present: true, frozen: true, frontmatter_status: 'implementing', ceremony_level: 2 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'fail', ref_id: 'CHANGE-0027' },
  review: { required: true, status: 'not_run' },
  flushed: true,
  implementer_model: null,
  last_run_role: 'Validation',
  open_intakes: [{ ref_id: 'some-open-intake', primary_path: 'docs/issues/CHANGE-9999-some-open-intake.md', doc_type: 'change', item_status: 'draft', unmappable: false }],
};
const frozen = JSON.stringify(s1);
const a = decide(s1);
const b = decide(JSON.parse(frozen));
assert.strictEqual(JSON.stringify(a), JSON.stringify(b), 'decide must be deterministic on a fail-verdict guard snapshot');
assert.strictEqual(JSON.stringify(s1), frozen, 'decide must not mutate its fail-verdict-guard-snapshot input');
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t18.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t18.log" 2>&1 \
    || log_fail "decide() purity on fail-verdict snapshot failed: $(cat "$TEST_DIR/t18.log")"

  # RULES table 4a `when` doc string must document the fail-verdict guard
  # (greppable for fail + Remediation, per Spec-AC-04).
  local when4a="$TEST_DIR/t18-when4a.txt"
  grep "id: '4a'" "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" > "$when4a" \
    || log_fail "RULES table must still contain the id: '4a' entry"
  grep -qi "fail" "$when4a" || log_fail "4a when doc string must document the fail-verdict guard (mention 'fail'): $(cat "$when4a")"
  grep -q "Remediation" "$when4a" || log_fail "4a when doc string must document the fall-through to Remediation: $(cat "$when4a")"

  log_pass "decide() purity on fail-verdict snapshot; 4a when doc string documents the guard (TEST-018/spec TEST-006)"
}

main() {
  echo "Testing $TEST_NAME (CHANGE-0009 TEST-001..005 + spec-dispatch-new-intake-after-completed-scope TEST-006..012 + dispatch-4a-fail-verdict-precedence TEST-013..018)"
  check_deps
  setup_fixture
  test_001_decide_table
  test_002_cli_contract
  test_003_reset_routing
  test_004_fail_closed
  test_005_flush_arm_and_independence
  test_006_arm4a_decide_table
  test_007_rule11_done_skip
  test_008_arm4a_ambiguity
  test_009_cli_integration
  test_010_evidence_replay
  test_011_seam_survival
  test_012_purity_and_hygiene
  test_013_fail_verdict_validation_precedence
  test_014_fail_verdict_review_precedence
  test_015_cli_fail_precedence
  test_016_survival_negative_control
  test_017_fail_closed_invariant
  test_018_purity_and_docstring_guard
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then
    check_deps
    setup_fixture
    "$1"
  else
    main
  fi
fi
