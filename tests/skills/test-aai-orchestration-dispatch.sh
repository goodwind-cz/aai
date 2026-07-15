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

main() {
  echo "Testing $TEST_NAME (CHANGE-0009 TEST-001..005)"
  check_deps
  setup_fixture
  test_001_decide_table
  test_002_cli_contract
  test_003_reset_routing
  test_004_fail_closed
  test_005_flush_arm_and_independence
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
