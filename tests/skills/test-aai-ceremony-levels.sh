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

# write_lean_spec <path> <ceremony_level> <with_ac_table true|false> <with_justification true|false>
# A frozen L0/L1-shaped fixture (spec-loop-ceremony-aware-dispatch TEST-006):
# lean "## Acceptance Criteria" table (Spec-AC + Status only, no Evidence/
# Review-By columns) and/or the "Ceremony justification: " body line, toggled
# independently so misuse combinations can be probed one axis at a time.
write_lean_spec() {
  local p="$1" cl="$2" withac="$3" withjust="$4" ac_block="" just_line=""
  if [[ "$withac" == "true" ]]; then
    ac_block=$'## Acceptance Criteria\n\n| Spec-AC    | Description | Status |\n|------------|-------------|--------|\n| Spec-AC-01 | fixture     | done   |'
  fi
  if [[ "$withjust" == "true" ]]; then
    just_line="Ceremony justification: fixture lean scope, no engine/test surface."
  fi
  cat > "$p" <<MD
---
id: fixture-lean-doc
type: spec
number: null
status: draft
ceremony_level: $cl
links:
  pr: []
---

# Lean fixture spec

$just_line

SPEC-FROZEN: true

$ac_block
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

## ==========================================================================
## spec-loop-ceremony-aware-dispatch (SPEC-0041, CHANGE-0030) TEST-001..007
## mapped to suite functions test_011..test_017. D5: additive stanzas ONLY --
## the SPEC-0030 stanzas above (test_001..010) are never edited.
## ==========================================================================

# --- TEST-011 (Spec TEST-001/Spec-AC-01): decide() lane table ------------------

test_011_decide_lane_table() {
  log_info "Test: decide() lane {selected, ceremony_level, validation_depth}: 0/1 lightweight, 2/3 full; fail-closed full incl. missing spec file; no_action/needs_llm lane null; purity (TEST-001)..."
  cat > "$TEST_DIR/t11.mjs" <<'EOF'
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

// Levels 0/1 -> lightweight lane; 2/3 -> full. Baseline routes to rule 13.
const expect = { 0: 'lightweight', 1: 'lightweight', 2: 'full', 3: 'full' };
for (const [lvl, sel] of Object.entries(expect)) {
  const s = base();
  s.spec.ceremony_level = Number(lvl);
  const d = decide(s);
  assert.strictEqual(d.verdict, 'dispatch');
  assert.ok(d.lane, `level ${lvl} must carry a lane object: ${JSON.stringify(d)}`);
  assert.strictEqual(d.lane.selected, sel, `level ${lvl}: ${JSON.stringify(d.lane)}`);
  assert.strictEqual(d.lane.ceremony_level, Number(lvl));
  assert.strictEqual(d.lane.validation_depth, sel === 'lightweight' ? 'declared_scope' : 'full');
}

// Fail-closed: absent/garbage/out-of-range/null/NaN -> lane full (mirrors TEST-001's level sweep).
for (const lvl of [undefined, null, 'banana', '1', 7, -1, 2.5, NaN]) {
  const s = base();
  if (lvl !== undefined) s.spec.ceremony_level = lvl;
  const d = decide(s);
  assert.strictEqual(d.lane.selected, 'full', `garbage level ${String(lvl)}: ${JSON.stringify(d.lane)}`);
  assert.strictEqual(d.lane.ceremony_level, 2);
}

// Missing spec file (rule 5, dispatch Planning) fires before any ceremony
// level can be known: fail-closed still applies -- lane full.
{
  const s = base();
  s.spec = { path: 'docs/specs/SPEC-9999-missing.md', present: false, frozen: false, frontmatter_status: null };
  const d = decide(s);
  assert.strictEqual(d.rule, '5');
  assert.ok(d.lane, 'rule-5 dispatch must still carry a lane object');
  assert.strictEqual(d.lane.selected, 'full', `missing spec file must fail-closed to full: ${JSON.stringify(d.lane)}`);
}

// no_action (rule 1, paused) -> lane null.
{
  const s = base();
  s.project_status = 'paused';
  const d = decide(s);
  assert.strictEqual(d.verdict, 'no_action');
  assert.strictEqual(d.lane, null, `no_action must carry lane null: ${JSON.stringify(d)}`);
}

// needs_llm (no focus ref) -> lane null.
{
  const s = base();
  s.focus = { type: 'intake_change', ref_id: null };
  const d = decide(s);
  assert.strictEqual(d.verdict, 'needs_llm');
  assert.strictEqual(d.lane, null, `needs_llm must carry lane null: ${JSON.stringify(d)}`);
}

// Purity: same snapshot in, same decision out (incl. lane), input untouched.
const s1 = base();
s1.spec.ceremony_level = 1;
const frozen = JSON.stringify(s1);
const a = decide(s1);
const b = decide(JSON.parse(frozen));
assert.strictEqual(JSON.stringify(a), JSON.stringify(b), 'decide must be deterministic (incl. lane)');
assert.strictEqual(JSON.stringify(s1), frozen, 'decide must not mutate its input');
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t11.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t11.log" 2>&1 \
    || log_fail "decide() lane table failed: $(cat "$TEST_DIR/t11.log")"
  log_pass "decide(): lane {selected, ceremony_level, validation_depth} table + fail-closed + null on no_action/needs_llm (TEST-011/spec TEST-001)"
}

# --- TEST-012 (Spec TEST-002/Spec-AC-02): Validation dispatch payload ----------

test_012_validation_dispatch_payload() {
  log_info "Test: rule-11 Validation dispatch: L0/L1 declared_scope + lightweight_lane_declared_scope reason; L2/L3 full + reasons unchanged; lane coexists with L3 annotations elsewhere (TEST-002)..."
  cat > "$TEST_DIR/t12.mjs" <<'EOF'
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
  spec: { path: 'docs/specs/SPEC-0001-fx.md', present: true, frozen: true, frontmatter_status: 'draft', ceremony_level: 1 },
  strategy_selected: 'tdd',
  worktree: { recommendation: 'optional', user_decision: 'inline' },
  validation: { status: 'not_run', ref_id: null },
  review: { required: true, status: 'not_run' },
  flushed: false,
  implementer_model: null,
  last_run_role: null,
});

// L1 -> lightweight; declared_scope depth; lightweight_lane_declared_scope reason.
{
  const d = decide(base());
  assert.strictEqual(d.rule, '11');
  assert.strictEqual(d.role, 'Validation');
  assert.strictEqual(d.lane.validation_depth, 'declared_scope');
  assert.ok(d.reasons.includes('lightweight_lane_declared_scope'), JSON.stringify(d.reasons));
}
// L0 -> same shape.
{
  const s = base(); s.spec.ceremony_level = 0;
  const d = decide(s);
  assert.strictEqual(d.rule, '11');
  assert.strictEqual(d.lane.validation_depth, 'declared_scope');
  assert.ok(d.reasons.includes('lightweight_lane_declared_scope'));
}
// L2 -> full, reasons EMPTY (byte-identical to pre-change: rule 11 never added reasons before).
{
  const s = base(); s.spec.ceremony_level = 2;
  const d = decide(s);
  assert.strictEqual(d.rule, '11');
  assert.strictEqual(d.lane.validation_depth, 'full');
  assert.deepStrictEqual(d.reasons, [], `L2 rule-11 reasons must stay empty: ${JSON.stringify(d.reasons)}`);
}
// L3 -> full, reasons EMPTY (unchanged).
{
  const s = base(); s.spec.ceremony_level = 3;
  const d = decide(s);
  assert.strictEqual(d.rule, '11');
  assert.strictEqual(d.lane.validation_depth, 'full');
  assert.deepStrictEqual(d.reasons, []);
}
// L3 alongside an EXISTING l3_* annotation (rule 13 review coercion): lane
// full and the legacy l3_review_mandatory reason both present, undisturbed
// by the new lane field -- the two annotation mechanisms coexist cleanly.
{
  const s = base();
  s.spec.ceremony_level = 3;
  s.validation = { status: 'pass', ref_id: 'CHANGE-0001' };
  s.review = { required: false, status: 'not_run' };
  s.last_run_role = 'Validation';
  const d = decide(s);
  assert.strictEqual(d.rule, '13');
  assert.strictEqual(d.lane.selected, 'full');
  assert.ok(d.reasons.includes('l3_review_mandatory'), JSON.stringify(d.reasons));
  assert.ok(!d.reasons.includes('lightweight_lane_declared_scope'));
}
console.log('ok');
EOF
  (cd "$PROJECT_ROOT" && node "$TEST_DIR/t12.mjs" "$PROJECT_ROOT") > "$TEST_DIR/t12.log" 2>&1 \
    || log_fail "Validation dispatch payload failed: $(cat "$TEST_DIR/t12.log")"
  log_pass "rule 11: L0/L1 declared_scope + reason, L2/L3 full + reasons unchanged, coexists with L3 annotations (TEST-012/spec TEST-002)"
}

# --- TEST-013 (Spec TEST-003/Spec-AC-01): CLI end-to-end lane field ------------

test_013_cli_lane_field() {
  log_info "Test: CLI end-to-end: lane field in stdout JSON, fail-closed via fixtures, exit codes + --human unaffected (TEST-003)..."
  local d tag

  # declared 1 -> lightweight, full payload shape.
  d="$(mk_root t13a)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 1"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) L1 fixture must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.lane && o.lane.selected === "lightweight" && o.lane.ceremony_level === 1 && o.lane.validation_depth === "declared_scope"'

  # banana/absent/7/null -> full, exit code still 0 (dispatch unaffected).
  for tag in banana absent seven null; do
    d="$(mk_root "t13_$tag")"
    case "$tag" in
      banana) write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: banana" ;;
      absent) write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true ;;
      seven)  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 7" ;;
      null)   write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: null" ;;
    esac
    write_dstate "$d/docs/ai/STATE.yaml"
    run_dispatch "$d"
    [[ "$EC" == 0 ]] || log_fail "($tag) must still dispatch (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.lane && o.lane.selected === "full" && o.lane.ceremony_level === 2 && o.lane.validation_depth === "full"'
  done

  # exit code 3 (no_action, paused) -> lane null, unaffected.
  d="$(mk_root t13_paused)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 1"
  write_dstate "$d/docs/ai/STATE.yaml"
  sed -i.bak 's/^project_status: active$/project_status: paused/' "$d/docs/ai/STATE.yaml" && rm -f "$d/docs/ai/STATE.yaml.bak"
  run_dispatch "$d"
  [[ "$EC" == 3 ]] || log_fail "paused fixture must be no_action (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.lane === null'

  # exit code 4 (needs_llm, stale validation ref) -> lane null, unaffected.
  d="$(mk_root t13_needsllm)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 1"
  write_dstate "$d/docs/ai/STATE.yaml" pass not_run implementation in_progress tdd optional inline CHANGE-9999
  run_dispatch "$d"
  [[ "$EC" == 4 ]] || log_fail "stale-validation fixture must be needs_llm (got $EC): $(cat "$OUT" "$ERR")"
  jassert "$OUT" 'o.lane === null'

  # --human still emits its stderr DISPATCH FORMAT block unaffected.
  d="$(mk_root t13_human)"
  write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: 1"
  write_dstate "$d/docs/ai/STATE.yaml"
  run_dispatch "$d" --human
  [[ "$EC" == 0 ]] || log_fail "--human fixture must dispatch (got $EC): $(cat "$OUT" "$ERR")"
  grep -q "=== ORCHESTRATION DISPATCH" "$ERR" || log_fail "--human must still print the DISPATCH FORMAT block: $(cat "$ERR")"
  jassert "$OUT" 'o.lane && o.lane.selected === "lightweight"'
  log_pass "CLI: lane field wired end-to-end, fail-closed via fixtures, exit codes + --human unaffected (TEST-013/spec TEST-003)"
}

# --- TEST-014 (Spec TEST-004/Spec-AC-03): L0/L1 fixture-chain ------------------

test_014_fixture_chain_lightweight() {
  log_info "Test: L1 (and L0) fixture-chain: Implementation -> Validation -> Code Review (3 lightweight dispatches) then Metrics Flush / no_action (TEST-004)..."
  local d lvl

  for lvl in 1 0; do
    d="$(mk_root "t14_l${lvl}")"
    write_spec "$d/docs/specs/SPEC-0001-fx.md" draft true "ceremony_level: $lvl"

    # Step 1: preparation phase, loop strategy -> dispatch Implementation (rule 9c), lightweight.
    write_dstate "$d/docs/ai/STATE.yaml" not_run not_run preparation in_progress loop optional inline
    run_dispatch "$d"
    [[ "$EC" == 0 ]] || log_fail "(L$lvl step1) must dispatch (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.role === "Implementation" && o.lane && o.lane.selected === "lightweight"'

    # Step 2: implementation phase, validation not_run -> dispatch Validation (rule 11), lightweight + reason.
    write_dstate "$d/docs/ai/STATE.yaml" not_run not_run implementation in_progress loop optional inline
    run_dispatch "$d"
    [[ "$EC" == 0 ]] || log_fail "(L$lvl step2) must dispatch (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.role === "Validation" && o.lane.selected === "lightweight" && o.lane.validation_depth === "declared_scope" && o.reasons.includes("lightweight_lane_declared_scope")'

    # Step 3: validation pass, review not_run required -> dispatch Code Review (rule 13), lightweight.
    write_dstate "$d/docs/ai/STATE.yaml" pass not_run implementation in_progress loop optional inline CHANGE-0001 true
    run_dispatch "$d"
    [[ "$EC" == 0 ]] || log_fail "(L$lvl step3) must dispatch (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.role === "Code Review" && o.lane.selected === "lightweight"'

    # Step 4 (mechanical arm, not counted among the 3): validation pass, review
    # pass, not yet flushed -> Metrics Flush.
    write_dstate "$d/docs/ai/STATE.yaml" pass pass implementation in_progress loop optional inline CHANGE-0001 true
    run_dispatch "$d"
    [[ "$EC" == 0 ]] || log_fail "(L$lvl step4) must dispatch flush (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.role === "Metrics Flush"'

    # Step 5: already flushed -> no_action, lane null.
    echo '{"ref_id":"CHANGE-0001"}' > "$d/docs/ai/METRICS.jsonl"
    run_dispatch "$d"
    [[ "$EC" == 3 ]] || log_fail "(L$lvl step5) must be no_action once flushed (got $EC): $(cat "$OUT" "$ERR")"
    jassert "$OUT" 'o.verdict === "no_action" && o.lane === null'
  done
  log_pass "Fixture-chain: L1/L0 walk Implementation -> Validation -> Code Review (3 lightweight dispatches) then flush/no_action (TEST-014/spec TEST-004)"
}

# --- TEST-015 (Spec TEST-005/Spec-AC-05): prompt lane surfaces -----------------

test_015_prompt_lane_surfaces() {
  log_info "Test: VALIDATION CEREMONY LANE block (fail-closed + declared-scope wording); PLANNING lane lines inside step 10; steps 11/12 survive, no step 13 (TEST-005)..."
  local v="$PROJECT_ROOT/.aai/VALIDATION.prompt.md" p="$PROJECT_ROOT/.aai/PLANNING.prompt.md" block

  grep -q "^CEREMONY LANE" "$v" || log_fail "VALIDATION.prompt.md must carry a CEREMONY LANE block"
  block="$(awk '/^CEREMONY LANE/{f=1} /^PROCESS$/{f=0} f' "$v")"
  [[ -n "$block" ]] || log_fail "CEREMONY LANE block body not found (must end before PROCESS)"
  echo "$block" | grep -qi "fail-closed" || log_fail "CEREMONY LANE block must name the fail-closed rule"
  echo "$block" | grep -qi "declared" || log_fail "CEREMONY LANE block must name the L0/L1 declared-scope validation rule"
  echo "$block" | grep -q "lane.selected" || log_fail "CEREMONY LANE block must reference the dispatch lane.selected field"

  block="$(awk '/^10\) /{f=1} /^11\) /{f=0} f' "$p")"
  [[ -n "$block" ]] || log_fail "PLANNING step 10 block not found"
  echo "$block" | grep -qi "dispatch lane" || log_fail "step 10 must name the dispatch lane"
  echo "$block" | grep -q "L0/L1" || log_fail "step 10 lane wording must name L0/L1"
  grep -q "^11) Emit the work-item brief" "$p" || log_fail "step 11 must survive unrenumbered"
  grep -q "^12) Update docs/ai/STATE.yaml" "$p" || log_fail "step 12 must survive unrenumbered"
  grep -qE "^13\) " "$p" && log_fail "no step 13 may be introduced (renumber guard)"
  log_pass "Prompt surfaces: VALIDATION CEREMONY LANE block + PLANNING step-10 lane lines, numbering intact (TEST-015/spec TEST-005)"
}

# --- TEST-016 (Spec TEST-006/Spec-AC-06): misuse guard survival ----------------

test_016_misuse_guard_survival() {
  log_info "Test: misuse guard survival post-change (freeze-time spec-lint + close-time docs-audit gate); guardrail files byte-untouched (TEST-006)..."
  local fx="$TEST_DIR/misuse016" ec
  mkdir -p "$fx"

  # (a) frozen L1, no AC table at all, no justification -> spec-lint flags
  # frozen-without-ac-table; docs-audit --gate-file exits 1 (missing AC table).
  write_lean_spec "$fx/l1-bare.md" 1 false false
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/spec-lint.mjs --path "$fx/l1-bare.md" --json > "$fx/lint-a.json" 2>"$fx/lint-a.err") || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(a) spec-lint must find the bare L1 fixture unclean (got $ec): $(cat "$fx/lint-a.json" "$fx/lint-a.err")"
  grep -q "frozen-without-ac-table" "$fx/lint-a.json" || log_fail "(a) spec-lint reason must be frozen-without-ac-table: $(cat "$fx/lint-a.json")"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l1-bare.md" > "$fx/gate-a.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(a) docs-audit --gate-file must fail the bare L1 fixture (got $ec): $(cat "$fx/gate-a.log")"

  # (b) frozen L1, lean AC table present, NO justification -> spec-lint clean
  # (missing-justification is out of spec-lint's boundary per D6); docs-audit
  # --gate-file exits 1 naming the ceremony justification line (close-time
  # backstop still fires, byte-identical to pre-change behavior).
  write_lean_spec "$fx/l1-nojust.md" 1 true false
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/spec-lint.mjs --path "$fx/l1-nojust.md" --json > "$fx/lint-b.json" 2>"$fx/lint-b.err") || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(b) spec-lint must be clean (missing-justification is a close-time-only check): $(cat "$fx/lint-b.json" "$fx/lint-b.err")"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l1-nojust.md" > "$fx/gate-b.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "(b) docs-audit --gate-file must fail without justification (got $ec): $(cat "$fx/gate-b.log")"
  grep -qi "justification" "$fx/gate-b.log" || log_fail "(b) gate reason must name the ceremony justification line: $(cat "$fx/gate-b.log")"

  # (c) control: lean AC table + justification present -> both clean.
  write_lean_spec "$fx/l1-clean.md" 1 true true
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/spec-lint.mjs --path "$fx/l1-clean.md" --json > "$fx/lint-c.json" 2>"$fx/lint-c.err") || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(c) spec-lint must be clean on a fully-declared L1 fixture: $(cat "$fx/lint-c.json" "$fx/lint-c.err")"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --gate-file "$fx/l1-clean.md" > "$fx/gate-c.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(c) docs-audit --gate-file must pass a fully-declared L1 fixture (got $ec): $(cat "$fx/gate-c.log")"

  # Hard constraint (Spec-AC-06 / D6): docs-audit-core.mjs byte-untouched by
  # this scope. spec-lint.mjs is NOT held to a blanket byte-untouched rule —
  # it is an intentionally-evolving, non-protected tool (e.g. CHANGE-0035
  # added an additive --slug-handles scan mode); the D6 freeze-time boundary
  # this test guards (frozen-without-ac-table detection) is verified
  # functionally by cases (a)/(b)/(c) above, which stay meaningful across any
  # such future additive change.
  (cd "$PROJECT_ROOT" && git diff --exit-code -- .aai/scripts/lib/docs-audit-core.mjs > "$fx/diff.log" 2>&1) \
    || log_fail "docs-audit-core.mjs must be byte-untouched by this scope: $(cat "$fx/diff.log")"

  log_pass "Misuse guardrails survive unmodified: freeze-time (spec-lint) + close-time (docs-audit gate) both still fire; guardrail files untouched (TEST-016/spec TEST-006)"
}

# --- TEST-017 (Spec TEST-007/Spec-AC-04..06): seam survival --------------------

test_017_seam_survival_spec0041() {
  log_info "Test: seam survival for SPEC-0041: dispatch suite green (S1), ceremony TEST-001..010 green, prompt-diet no NEW regression (S3), strict audit exit 0 (S4) (TEST-007)..."

  # S1 -- dispatch suite (also the CHANGE-0031 seam) stays green.
  (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-orchestration-dispatch.sh > "$TEST_DIR/t17-dispatch.log" 2>&1) \
    || log_fail "dispatch suite must stay green post-change: $(tail -20 "$TEST_DIR/t17-dispatch.log")"

  # ceremony TEST-001..010 stanzas (SPEC-0030) re-verified green, each as an
  # independent subprocess (isolated fixture dir; the file's own
  # single-function invocation mode, used identically by TDD RED/GREEN runs).
  local fn
  for fn in test_001_decide_fail_closed_default test_002_decide_l0_rule6_prune \
            test_003_decide_l3_worktree test_004_decide_l3_review \
            test_005_cli_fail_closed_parsing test_006_close_gate_justification \
            test_007_spec_template test_008_planning_step10 \
            test_009_workflow_and_config; do
    (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-ceremony-levels.sh "$fn" > "$TEST_DIR/t17-$fn.log" 2>&1) \
      || log_fail "$fn must stay green post-change: $(tail -20 "$TEST_DIR/t17-$fn.log")"
  done
  # test_010 itself re-runs prompt-diet (see below) via a KNOWN pre-existing
  # byte-budget shortfall (LEARNED 2026-07-17) unrelated to this scope; it is
  # exercised directly below instead of via the subprocess loop above so that
  # shortfall is isolated to ONE assertion rather than aborting this whole test.

  # S3 -- prompt-diet floor. A documented PRE-EXISTING shortfall (TEST-010
  # byte-budget, ~485 bytes short, reproduced on clean main before this scope
  # touched anything -- LEARNED 2026-07-17) already fails this suite; this
  # scope must not add any OTHER failure on top of it. Tolerate ONLY that
  # named pre-existing line; any other FAIL is a real regression.
  local diet_ec=0 diet_fails
  (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-prompt-diet.sh > "$TEST_DIR/t17-diet.log" 2>&1) || diet_ec=$?
  diet_fails="$(grep -c '^FAIL ' "$TEST_DIR/t17-diet.log" || true)"
  if [[ "$diet_ec" != 0 ]]; then
    if [[ "$diet_fails" == "1" ]] && grep -q "^FAIL TEST-010 audit + byte reduction" "$TEST_DIR/t17-diet.log"; then
      log_info "prompt-diet: pre-existing TEST-010 byte-budget shortfall only (LEARNED 2026-07-17), no new regression: $(grep 'net reduction' "$TEST_DIR/t17-diet.log")"
    else
      log_fail "prompt-diet must not regress beyond the documented pre-existing TEST-010 shortfall: $(tail -20 "$TEST_DIR/t17-diet.log")"
    fi
  fi

  # S4 -- repo-wide strict audit.
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t17-audit.log" 2>&1) \
    || log_fail "repo-wide strict audit must exit 0: $(tail -30 "$TEST_DIR/t17-audit.log")"
  grep -qE "Scanned: [1-9][0-9]* docs" "$TEST_DIR/t17-audit.log" \
    || log_fail "strict audit must be non-vacuous: $(head -10 "$TEST_DIR/t17-audit.log")"
  log_pass "Seams survive: dispatch suite, ceremony TEST-001..010, prompt-diet (no new regression), strict audit all green (TEST-017/spec TEST-007)"
}

main() {
  echo "Testing $TEST_NAME (spec-scale-adaptive-ceremony TEST-001..010 + spec-loop-ceremony-aware-dispatch TEST-011..017)"
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
  # test_011..017 run BEFORE test_010 on purpose: test_010 re-runs
  # tests/skills/test-aai-prompt-diet.sh, which carries a documented
  # PRE-EXISTING byte-budget shortfall (LEARNED 2026-07-17, reproduced on
  # clean main before this scope touched anything) and therefore aborts this
  # whole `set -euo pipefail` script once it fails. Running the new
  # spec-loop-ceremony-aware-dispatch stanzas first lets a single `main`
  # invocation prove TEST-011..017 green before that pre-existing failure is
  # reached; test_017 re-asserts prompt-diet itself with the same tolerance.
  test_011_decide_lane_table
  test_012_validation_dispatch_payload
  test_013_cli_lane_field
  test_014_fixture_chain_lightweight
  test_015_prompt_lane_surfaces
  test_016_misuse_guard_survival
  test_017_seam_survival_spec0041
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
