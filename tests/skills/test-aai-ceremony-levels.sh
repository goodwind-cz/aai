#!/usr/bin/env bash
#
# Test: scale-adaptive ceremony levels (RFC-0009 / spec-scale-adaptive-ceremony,
# TEST-001..010).
#
# Verifies:
#   - decide() level-awareness: fail-closed default 2, L0 rule-6 status-arm
#     prune, L3 rule-8 worktree coercion, L3 rule-13 review coercion +
#     waived -> needs_llm; L1/L2 mechanically unchanged (TEST-001..004)
#   - CLI snapshot builder reads ceremony_level from the spec_path file's
#     frontmatter, fail-closed to 2 on absent/garbage/out-of-range/null
#     (TEST-005)
#   - docs-audit close gate: L0/L1 justification-line requirement + enum
#     validation; absent field = legacy implicit L2, never flagged (TEST-006)
#   - declaration surfaces: SPEC_TEMPLATE frontmatter field, PLANNING step-10
#     insertion without renumbering, WORKFLOW.md gate table +
#     protected_paths_l3 config (TEST-007..009)
#   - seam survival: dispatch suite, prompt-diet, repo-wide strict audit
#     (TEST-010)
#
# ALL fixtures are scratch temp-dir repos; real runtime files are NEVER
# touched. bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-ceremony-levels"
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
  [[ -f "$DISPATCH" ]] || log_fail "dispatch script not found: $DISPATCH"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-ceremony-test.XXXXXX")"
}

# --- fixture builders (scratch repos; mirrors the dispatch suite) --------------

# mk_root <name> — isolated repo root; caller writes the spec afterwards.
mk_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  printf '%s' "$d"
}

# write_spec <path> <frontmatter-status> <frozen true|false> [ceremony_level-line]
# The 4th arg, when non-empty, is inserted VERBATIM into the frontmatter
# (e.g. "ceremony_level: 0" or "ceremony_level: banana").
write_spec() {
  local p="$1" status="$2" frozen="$3" clline="${4:-}"
  cat > "$p" <<MD
---
id: SPEC-0001
type: spec
number: 1
status: $status
${clline}
links:
  pr: []
---

# Fixture spec

$([[ "$frozen" == "true" ]] && echo "SPEC-FROZEN: true")

## Test Plan
MD
}

# write_dstate <file> [vstatus] [rstatus] [phase] [istatus] [strategy] [wrec] [wdec] [vref] [rrequired]
write_dstate() {
  local f="$1" vstatus="${2:-not_run}" rstatus="${3:-not_run}" phase="${4:-implementation}" \
    istatus="${5:-in_progress}" strategy="${6:-tdd}" wrec="${7:-optional}" wdec="${8:-inline}" \
    vref="${9:-CHANGE-0001}" rrequired="${10:-true}"
  cat > "$f" <<YAML
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

jassert() {
  node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expr = process.argv[2];
    const fn = new Function("o", "return (" + expr + ");");
    if (!fn(o)) { console.error("assert failed: " + expr + "\n  got: " + JSON.stringify(o)); process.exit(1); }
  ' "$1" "$2" || log_fail "JSON assertion failed on $1"
}

# write_gate_doc <path> <frontmatter-extra-line> <body-extra-line>
# A minimal gate-passing doc (terminal AC table with Evidence + Review-By).
write_gate_doc() {
  local p="$1" fmline="${2:-}" bodyline="${3:-}"
  cat > "$p" <<MD
---
id: fixture-gate-doc
type: spec
number: null
status: done
${fmline}
links:
  pr: []
---

# Gate fixture

${bodyline}

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture     | done   | abc1234  | —         | —     |
MD
}

# --- TEST-001: decide() fail-closed default + legacy baseline ------------------

test_001_decide_fail_closed_default() {
  log_info "Test: decide() treats absent/garbage/out-of-range level as 2; baseline unchanged (TEST-001)..."
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
  validation: { status: 'pass', ref_id: 'CHANGE-0001' },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: 'Validation',
});

// Fail-closed level inputs: each must behave EXACTLY like level 2 (full
// ceremony). Baseline snapshot routes to rule 13 (Code Review).
for (const lvl of [undefined, null, 'banana', '1', 7, -1, 2.5, NaN]) {
  const s = base();
  if (lvl !== undefined) s.spec.ceremony_level = lvl;
  const d = decide(s);
  assert.strictEqual(d.verdict, 'dispatch', `level ${String(lvl)}: ${JSON.stringify(d)}`);
  assert.strictEqual(d.rule, '13', `level ${String(lvl)} must keep full ceremony (rule 13), got ${d.rule}`);
  assert.strictEqual(d.role, 'Code Review');
}

// Legacy baseline sweep with NO ceremony_level key at all: rules 6/8/13 keep
// today's behavior bit-for-bit.
{
  const s = base();
  s.spec.frontmatter_status = 'done';   // rule 6 status arm must still fire
  const d = decide(s);
  assert.strictEqual(d.rule, '6', `legacy rule 6 status arm: ${JSON.stringify(d)}`);
}
{
  const s = base();
  s.worktree = { recommendation: 'not_needed', user_decision: 'undecided' };
  const d = decide(s);
  assert.notStrictEqual(d.rule, '8', 'legacy not_needed+undecided must NOT gate on rule 8');
}
{
  const s = base();
  s.review = { required: false, status: 'not_run' };
  s.flushed = true;
  const d = decide(s);
  assert.strictEqual(d.verdict, 'no_action');
  assert.strictEqual(d.rule, '14', `legacy required:false skips rule 13: ${JSON.stringify(d)}`);
}

// Purity: same snapshot in, same decision out, input untouched.
const s1 = base();
s1.spec.ceremony_level = 3;
const frozen = JSON.stringify(s1);
const a = decide(s1);
const b = decide(JSON.parse(frozen));
assert.strictEqual(JSON.stringify(a), JSON.stringify(b), 'decide must be deterministic');
assert.strictEqual(JSON.stringify(s1), frozen, 'decide must not mutate its input');
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t1.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t1.log" 2>&1 \
    || log_fail "decide() fail-closed default cases failed: $(cat "$TEST_DIR/t1.log")"
  log_pass "decide(): absent/garbage/out-of-range level == 2; legacy baseline intact (TEST-001)"
}

# --- TEST-002: decide() L0 rule-6 status-arm prune ------------------------------

test_002_decide_l0_rule6_prune() {
  log_info "Test: decide() L0 prunes the rule-6 frontmatter-status arm, keeps the marker arm (TEST-002)..."
  cat > "$TEST_DIR/t2.mjs" <<'EOF'
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
  // L0 tech-note doc: frozen marker present, but a CHANGE-doc status outside
  // the spec enum {draft, implementing}.
  spec: { path: 'docs/issues/CHANGE-0001-fixture.md', present: true, frozen: true, frontmatter_status: 'done', ceremony_level: 0 },
  strategy_selected: 'loop',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: false, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: null,
});

// L0: status arm pruned -> falls through to rule 11 (Validation).
{
  const d = decide(base());
  assert.strictEqual(d.rule, '11', `L0 must prune the status arm: ${JSON.stringify(d)}`);
  assert.strictEqual(d.role, 'Validation');
}
// Same snapshot at L2: rule 6 fires (status arm intact).
{
  const s = base();
  s.spec.ceremony_level = 2;
  const d = decide(s);
  assert.strictEqual(d.rule, '6', `L2 must keep the status arm: ${JSON.stringify(d)}`);
  assert.strictEqual(d.role, 'Planning');
}
// L0 NEVER prunes the freeze-marker arm: unfrozen -> rule 6.
{
  const s = base();
  s.spec.frozen = false;
  const d = decide(s);
  assert.strictEqual(d.rule, '6', `L0 unfrozen must still dispatch Planning: ${JSON.stringify(d)}`);
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t2.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t2.log" 2>&1 \
    || log_fail "decide() L0 rule-6 prune failed: $(cat "$TEST_DIR/t2.log")"
  log_pass "decide() L0: status arm pruned, marker arm kept; L2 unchanged (TEST-002)"
}

# --- TEST-003: decide() L3 worktree coercion ------------------------------------

test_003_decide_l3_worktree() {
  log_info "Test: decide() L3 makes the worktree gate mandatory for ANY recommendation (TEST-003)..."
  cat > "$TEST_DIR/t3.mjs" <<'EOF'
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
  spec: { path: 'docs/specs/SPEC-0001-fx.md', present: true, frozen: true, frontmatter_status: 'draft', ceremony_level: 3 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'not_needed', user_decision: 'undecided' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: null,
});

// L3 + not_needed + undecided -> rule 8 with the coercion reason.
{
  const d = decide(base());
  assert.strictEqual(d.rule, '8', `L3 must gate the worktree decision: ${JSON.stringify(d)}`);
  assert.ok(d.reasons.includes('l3_worktree_mandatory'), `coercion reason expected: ${JSON.stringify(d.reasons)}`);
}
// L2 same snapshot -> falls through past rule 8.
{
  const s = base();
  s.spec.ceremony_level = 2;
  const d = decide(s);
  assert.notStrictEqual(d.rule, '8', `L2 not_needed must NOT gate: ${JSON.stringify(d)}`);
}
// L3 with a decided worktree -> no gate (proceeds to rule 11 here).
{
  const s = base();
  s.worktree = { recommendation: 'not_needed', user_decision: 'worktree' };
  const d = decide(s);
  assert.strictEqual(d.rule, '11', `decided L3 must proceed: ${JSON.stringify(d)}`);
}
// L3 + recommended (legacy trigger) keeps firing WITHOUT the coercion reason.
{
  const s = base();
  s.worktree = { recommendation: 'required', user_decision: 'undecided' };
  const d = decide(s);
  assert.strictEqual(d.rule, '8');
  assert.ok(!d.reasons.includes('l3_worktree_mandatory'), 'no coercion reason when the legacy arm fired');
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t3.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t3.log" 2>&1 \
    || log_fail "decide() L3 worktree coercion failed: $(cat "$TEST_DIR/t3.log")"
  log_pass "decide() L3: worktree decision mandatory regardless of recommendation (TEST-003)"
}

# --- TEST-004: decide() L3 review coercion + waived edge -------------------------

test_004_decide_l3_review() {
  log_info "Test: decide() L3 review mandatory; waived -> needs_llm; L2 waived -> rule 14; L3 fail -> rule 12 (TEST-004)..."
  cat > "$TEST_DIR/t4.mjs" <<'EOF'
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
  spec: { path: 'docs/specs/SPEC-0001-fx.md', present: true, frozen: true, frontmatter_status: 'draft', ceremony_level: 3 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'required', user_decision: 'worktree' },
  validation: { status: 'pass', ref_id: 'CHANGE-0001' },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: 'Validation',
});

// L3 + required:false coerced -> rule 13 with the coercion reason.
{
  const s = base();
  s.review = { required: false, status: 'not_run' };
  const d = decide(s);
  assert.strictEqual(d.rule, '13', `L3 must coerce review required: ${JSON.stringify(d)}`);
  assert.strictEqual(d.role, 'Code Review');
  assert.strictEqual(d.suggested_tier, 'premium', 'L3 review runs on the most capable tier');
  assert.ok(d.reasons.includes('l3_review_mandatory'), `coercion reason expected: ${JSON.stringify(d.reasons)}`);
}
// L2 same snapshot -> required:false skips rule 13 (flush arm).
{
  const s = base();
  s.spec.ceremony_level = 2;
  s.review = { required: false, status: 'not_run' };
  const d = decide(s);
  assert.strictEqual(d.rule, '14', `L2 required:false must skip review: ${JSON.stringify(d)}`);
}
// L3 + waived -> needs_llm with the operator-checkpoint reason (fail-closed).
{
  const s = base();
  s.review = { required: true, status: 'waived' };
  const d = decide(s);
  assert.strictEqual(d.verdict, 'needs_llm', `L3 waived must flag: ${JSON.stringify(d)}`);
  assert.ok(d.reasons.includes('l3_review_waived_requires_operator_checkpoint'), JSON.stringify(d.reasons));
}
// L2 + waived (explicit human waiver) -> proceeds to rule 14.
{
  const s = base();
  s.spec.ceremony_level = 2;
  s.review = { required: true, status: 'waived' };
  const d = decide(s);
  assert.strictEqual(d.rule, '14', `L2 waived must proceed: ${JSON.stringify(d)}`);
}
// L3 + review fail: rule 12 (Remediation) fires BEFORE any coercion.
{
  const s = base();
  s.review = { required: true, status: 'fail' };
  s.last_run_role = 'Validation';
  const d = decide(s);
  assert.strictEqual(d.rule, '12', `L3 review fail must remediate: ${JSON.stringify(d)}`);
}
// L0 + required:true + not_run: review still dispatches (optionality is an
// input-side policy, not a mechanical skip).
{
  const s = base();
  s.spec.ceremony_level = 0;
  const d = decide(s);
  assert.strictEqual(d.rule, '13', `L0 with required:true still reviews: ${JSON.stringify(d)}`);
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t4.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t4.log" 2>&1 \
    || log_fail "decide() L3 review coercion failed: $(cat "$TEST_DIR/t4.log")"
  log_pass "decide() L3: review coerced, waived flags needs_llm; L2/L0 semantics intact (TEST-004)"
}

# --- TEST-005: CLI snapshot fail-closed frontmatter parsing ---------------------

test_005_cli_fail_closed_parsing() {
  log_info "Test: CLI reads ceremony_level from spec frontmatter, fail-closed to 2 (TEST-005)..."
  local d

  # (a) absent field -> 2 (legacy implicit L2).
  d="$(mk_root t5a)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) legacy fixture must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 2'
  jassert "$OUT" 'o.rule === "11"'

  # (b) garbage token -> 2.
  d="$(mk_root t5b)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: banana"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) garbage level must still dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 2'

  # (c) out-of-range integer -> 2.
  d="$(mk_root t5c)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 7"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 2'

  # (d) yaml null -> 2.
  d="$(mk_root t5d)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: null"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 2'

  # (e) declared 0 on a frozen tech-note with a non-spec status: rule 6
  # status arm pruned END-TO-END (dispatches past Planning).
  d="$(mk_root t5e)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" done true "ceremony_level: 0"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(e) L0 fixture must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 0'
  jassert "$OUT" 'o.rule === "11" && o.role === "Validation"'
  # ...and the SAME fixture without the level declaration routes to Planning.
  write_spec "$d/docs/specs/SPEC-0001-fx.md" done true
  run_dispatch "$d"
  jassert "$OUT" 'o.rule === "6" && o.role === "Planning"'

  # (f) declared 3: worktree gate fires end-to-end on optional+undecided.
  d="$(mk_root t5f)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 3"
  write_dstate "$d/docs/ai/STATE.yaml" not_run not_run implementation in_progress tdd optional undecided
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(f) L3 fixture must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.state_summary.spec.ceremony_level === 3'
  jassert "$OUT" 'o.rule === "8" && o.reasons.includes("l3_worktree_mandatory")'
  log_pass "CLI fail-closed proof: absent/banana/7/null -> 2; declared 0/3 honored end-to-end (TEST-005)"
}

# --- TEST-006: docs-audit close gate — justification + enum ---------------------

test_006_close_gate_justification() {
  log_info "Test: docs-audit --gate-file enforces L0/L1 justification + enum; legacy passes (TEST-006)..."
  local fx="$TEST_DIR/gate" ec
  mkdir -p "$fx"

  # (a) L1 WITHOUT the justification line -> exit 1 with a named reason.
  write_gate_doc "$fx/l1-nojust.md" "ceremony_level: 1"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l1-nojust.md" > "$fx/a.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(a) L1 without justification must fail the gate (got $ec): $(cat "$fx/a.log")"
  grep -qi "ceremony" "$fx/a.log" || log_fail "(a) gate reason must name the ceremony check: $(cat "$fx/a.log")"

  # (b) L1 WITH the justification line -> exit 0.
  write_gate_doc "$fx/l1-just.md" "ceremony_level: 1" "Ceremony justification: single-surface render fix, no behavior change."
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l1-just.md" > "$fx/b.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(b) L1 with justification must pass (got $ec): $(cat "$fx/b.log")"

  # (c) L0 without justification -> exit 1.
  write_gate_doc "$fx/l0-nojust.md" "ceremony_level: 0"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l0-nojust.md" > "$fx/c.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(c) L0 without justification must fail (got $ec): $(cat "$fx/c.log")"

  # (d) schema-invalid enum -> exit 1 with a named reason.
  write_gate_doc "$fx/badenum.md" "ceremony_level: high"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/badenum.md" > "$fx/d.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(d) invalid enum must fail the gate (got $ec): $(cat "$fx/d.log")"
  grep -qi "schema-invalid ceremony_level" "$fx/d.log" || log_fail "(d) reason must name schema-invalid ceremony_level: $(cat "$fx/d.log")"

  # (e) absent field (legacy implicit L2) -> exit 0, never flagged.
  write_gate_doc "$fx/legacy.md"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/legacy.md" > "$fx/e.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(e) absent field must pass (legacy implicit L2, got $ec): $(cat "$fx/e.log")"

  # (f) L2/L3 need no justification line -> exit 0.
  write_gate_doc "$fx/l3.md" "ceremony_level: 3"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l3.md" > "$fx/f.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(f) L3 must not require the justification line (got $ec): $(cat "$fx/f.log")"
  log_pass "Close gate: L0/L1 justification required, enum validated, legacy/L2/L3 pass (TEST-006)"
}

# --- TEST-007: SPEC_TEMPLATE surface --------------------------------------------

test_007_spec_template() {
  log_info "Test: SPEC_TEMPLATE carries ceremony_level: 2 + guidance (TEST-007)..."
  local t="$PROJECT_ROOT/.aai/templates/SPEC_TEMPLATE.md"
  # frontmatter field with default 2, inside the frontmatter block
  awk '/^---$/{n++} n==1' "$t" | grep -q "^ceremony_level: 2$" \
    || log_fail "SPEC_TEMPLATE frontmatter must declare ceremony_level: 2"
  grep -q "Ceremony justification:" "$t" \
    || log_fail "SPEC_TEMPLATE must name the justification-line requirement"
  grep -q "protected_paths_l3" "$t" \
    || log_fail "SPEC_TEMPLATE guidance must point at protected_paths_l3"
  log_pass "SPEC_TEMPLATE: ceremony_level field + guidance comment (TEST-007)"
}

# --- TEST-008: PLANNING step-10 insertion, no renumber ---------------------------

test_008_planning_step10() {
  log_info "Test: PLANNING declares the level INSIDE step 10; steps 11/12 survive; no step 13 (TEST-008)..."
  local p="$PROJECT_ROOT/.aai/PLANNING.prompt.md" block
  # Extract the step-10 block (from '10)' to the '11)' line).
  block="$(awk '/^10\) /{f=1} /^11\) /{f=0} f' "$p")"
  [[ -n "$block" ]] || log_fail "PLANNING step 10 block not found"
  echo "$block" | grep -q "ceremony_level" \
    || log_fail "level declaration must live INSIDE the step-10 block"
  echo "$block" | grep -q "Ceremony justification:" \
    || log_fail "step 10 must name the L0/L1 justification line"
  grep -q "^11) Emit the work-item brief" "$p" || log_fail "step 11 must survive unrenumbered"
  grep -q "^12) Update docs/ai/STATE.yaml" "$p" || log_fail "step 12 must survive unrenumbered"
  grep -qE "^13\) " "$p" && log_fail "no step 13 may be introduced (renumber guard)"
  log_pass "PLANNING: ceremony-level declaration inside step 10, numbering intact (TEST-008)"
}

# --- TEST-009: WORKFLOW gate table + protected_paths_l3 config -------------------

test_009_workflow_and_config() {
  log_info "Test: WORKFLOW.md ceremony-levels gate table + docs-audit.yaml protected_paths_l3 (TEST-009)..."
  local w="$PROJECT_ROOT/.aai/workflow/WORKFLOW.md" y="$PROJECT_ROOT/docs/ai/docs-audit.yaml"
  grep -qi "^## Ceremony levels" "$w" || log_fail "WORKFLOW.md must carry a Ceremony levels section"
  # the per-level gate table: a markdown table header row naming all four levels
  grep -E '^\|' "$w" | grep -q "L0" || log_fail "gate table must carry an L0 column"
  grep -E '^\|' "$w" | grep "L0" | grep "L1" | grep "L2" | grep -q "L3" \
    || log_fail "gate table header must name L0, L1, L2, L3"
  grep -q "protected_paths_l3" "$w" || log_fail "WORKFLOW.md must point at protected_paths_l3"
  # canonical default surfaces named in the canon
  grep -q "state-engine.mjs" "$w" || log_fail "canon defaults must name the state engine"
  grep -q "allocate-doc-number.mjs" "$w" || log_fail "canon defaults must name the allocator"
  # absent-field semantics documented
  grep -qi "implicit level 2\|implicit L2" "$w" || log_fail "canon must document absent-field == implicit L2"
  # config key present and parsed
  grep -q "^protected_paths_l3:" "$y" || log_fail "docs-audit.yaml must carry protected_paths_l3"
  node -e '
    import(process.argv[1] + "/.aai/scripts/lib/docs-audit-core.mjs").then(m => {
      const cfg = m.loadConfig(process.argv[1]);
      if (!Array.isArray(cfg.protected_paths_l3) || cfg.protected_paths_l3.length < 4) {
        console.error("loadConfig must parse protected_paths_l3 as a non-trivial list, got: " + JSON.stringify(cfg.protected_paths_l3));
        process.exit(1);
      }
      if (!cfg.protected_paths_l3.some(p => p.includes("state.mjs"))) {
        console.error("protected_paths_l3 must include the state engine");
        process.exit(1);
      }
    });
  ' "$PROJECT_ROOT" || log_fail "loadConfig protected_paths_l3 parsing failed"
  log_pass "WORKFLOW gate table + protected_paths_l3 config wired (TEST-009)"
}

# --- TEST-010: seam survival (dispatch suite, prompt-diet, strict audit) ----------

test_010_seam_survival() {
  log_info "Test: dispatch suite, prompt-diet, and repo-wide strict audit survive (TEST-010)..."
  (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-orchestration-dispatch.sh > "$TEST_DIR/t10-dispatch.log" 2>&1) \
    || log_fail "existing dispatch suite must stay green: $(tail -20 "$TEST_DIR/t10-dispatch.log")"
  (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-prompt-diet.sh > "$TEST_DIR/t10-diet.log" 2>&1) \
    || log_fail "prompt-diet floor must hold: $(tail -20 "$TEST_DIR/t10-diet.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t10-audit.log" 2>&1) \
    || log_fail "repo-wide strict audit must exit 0: $(tail -30 "$TEST_DIR/t10-audit.log")"
  grep -qE "Scanned: [1-9][0-9]* docs" "$TEST_DIR/t10-audit.log" \
    || log_fail "strict audit must be non-vacuous: $(head -10 "$TEST_DIR/t10-audit.log")"
  log_pass "Seams survive: dispatch suite, prompt-diet, strict audit all green (TEST-010)"
}

main() {
  echo "Testing $TEST_NAME (spec-scale-adaptive-ceremony TEST-001..010)"
  check_deps
  setup_fixture
  test_001_decide_fail_closed_default
  test_002_decide_l0_rule6_prune
  test_003_decide_l3_worktree
  test_004_decide_l3_review
  test_005_cli_fail_closed_parsing
  test_006_close_gate_justification
  test_007_spec_template
  test_008_planning_step10
  test_009_workflow_and_config
  test_010_seam_survival
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
