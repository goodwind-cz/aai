#!/usr/bin/env bash
#
# Test: aai-project-config — the consumer-owned docs/ai/project-config.yaml and
# its routing_override@<harness> section (spec-consumer-config-routing-override).
# TEST-3681..3688, 3691, 3694 here (parser library + dispatch wiring);
# the remaining TEST ids (3680, 3689, 3690, 3692, 3693, 3695) join with
# their Spec-ACs, each as one test_NNNN_* function wired into main() below.
# Fixtures are scratch temp-dir repos; nothing real is touched. bash 3.2
# compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-project-config"
TEST_DIR=""
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
# shellcheck source=lib/pipe-safe.sh
. "$SCRIPT_DIR/lib/pipe-safe.sh"
DISPATCH="$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs"
LIB="$PROJECT_ROOT/.aai/scripts/lib/project-config.mjs"
ROUTING="$PROJECT_ROOT/.aai/system/MODEL_ROUTING.yaml"
PRICING="$PROJECT_ROOT/.aai/system/PRICING.yaml"
FRESHNESS="$PROJECT_ROOT/.aai/scripts/table-freshness.mjs"
PRE_RIDE_BLOB="73668e4c1730c5e98f45a5bdcf94f866f0fc5e58"
DISPATCH_BIN=""

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
  [[ -f "$LIB" ]] || log_fail "lib/project-config.mjs missing (RED until the parser lands)"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-project-config.XXXXXX")"
}

# mk_root <name> — scratch root whose STATE dispatches a rule-13 Code Review
# (validation passed, review not run) with the shipped MODEL_ROUTING.yaml.
mk_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow" "$d/.aai/system"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  cp "$ROUTING" "$d/.aai/system/MODEL_ROUTING.yaml"
  cp "$PRICING" "$d/.aai/system/PRICING.yaml"
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
  status: pass
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
# run_d <root> <harness> [dispatch args...]; harness markers scrubbed first
# (CLAUDECODE is set in this runner), then AAI_HARNESS forced.
run_d() {
  local d="$1" h="$2"
  shift 2
  OUT="$d/out.json"; ERR="$d/err.log"; EC=0
  env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CODEX_HOME -u CODEX_SANDBOX \
    -u CURSOR_TRACE_ID -u CURSOR_AGENT -u GEMINI_HOME -u GEMINI_CLI_IDE_SERVER_PORT \
    -u GEMINI_CLI_IDE_AUTH_TOKEN -u GEMINI_CLI_IDE_WORKSPACE_PATH -u CLAUDE_CONFIG_DIR \
    -u AAI_HARNESS -u AAI_ROLE -u CLAUDE_CODE_EFFORT_LEVEL \
    "AAI_HARNESS=$h" node "${DISPATCH_BIN:-$DISPATCH}" --state "$d/docs/ai/STATE.yaml" --root "$d" "$@" > "$OUT" 2> "$ERR" || EC=$?
}

jassert() {
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const fn = new Function("o", "return (" + process.argv[2] + ");");
    if (!fn(o)) { console.error("assert failed: " + process.argv[2] + "\n  got: " + JSON.stringify(o).slice(0, 600)); process.exit(1); }
  ' "$1" "$2" || log_fail "${CUR_TEST:-TEST}: JSON assertion failed: $2"
}

# run_mjs <script> <args...> — runs the script as a file so argv[1] is not the dispatcher.
run_mjs() {
  local f="$TEST_DIR/s$$.mjs"
  printf '%s\n' "$1" > "$f"
  shift
  node "$f" "$@"
}

# count_lines <fixed-string> <file> — grep -c without dying under pipefail on 0.
count_lines() { grep -cF -- "$1" "$2" || true; }

# --- TEST-3681 (Spec-AC-02) ---------------------------------------------------
test_3681_resolution_matrix() {
  CUR_TEST="TEST-3681"
  log_info "TEST-3681: override differs from no-override only on the overridden harness/role pairs..."
  mkdir -p "$TEST_DIR/modea/.aai/system"
  cat > "$TEST_DIR/modea/.aai/system/MODEL_ROUTING.yaml" <<'YAML'
tiers:
  mechanical: mech-a
  standard: std-a
  premium: prem-a
roles:
  Planning: plan-a
YAML
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const lib = await import(pathToFileURL(process.argv[3]).href);
const tables = { shipped: m.loadModelRouting(process.argv[4]), modeA: m.loadModelRouting(process.argv[5]), none: null };
const ov = lib.parseProjectConfig("routing_override@claude:\n  Code Review: claude-sonnet-5-5\n  Validation: claude-sonnet-5-4\nrouting_override@cursor:\n  Planning: cursor-model-1\n").overrides;
const exp = { "claude|Code Review": "claude-sonnet-5-5", "claude|Validation": "claude-sonnet-5-4", "cursor|Planning": "cursor-model-1" };
let n = 0, diffs = 0, cursorNullBase = false;
for (const [tn, table] of Object.entries(tables)) {
  for (const harness of ["claude", "codex", "gemini", "cursor", "unknown"]) {
    for (const role of Object.keys(m.TIERS)) {
      for (const lane of [null, "lightweight"]) {
        const mk = () => ({ verdict: "dispatch", role, harness, suggested_tier: m.TIERS[role], lane: lane ? { selected: lane } : null, validator_independence: null });
        const base = m.suggestModel(mk(), table);
        if (m.suggestModel(mk(), table, null) !== base) { console.error("null overrides changed " + tn + "/" + harness + "/" + role); process.exit(1); }
        const withO = m.suggestModel(mk(), table, ov);
        const want = Object.prototype.hasOwnProperty.call(exp, harness + "|" + role) ? exp[harness + "|" + role] : base;
        if (withO !== want) { console.error("MISMATCH " + tn + "/" + harness + "/" + role + "/" + lane + ": got " + withO + " want " + want); process.exit(1); }
        if (withO !== base) diffs++;
        if (tn === "shipped" && harness === "cursor" && role === "Planning" && base === null && withO === "cursor-model-1") cursorNullBase = true;
        n++;
      }
    }
  }
}
console.log("cases=" + n + " diffs=" + diffs + " cursor_null_base=" + cursorNullBase);
' "$DISPATCH" "$LIB" "$PROJECT_ROOT" "$TEST_DIR/modea")" || log_fail "TEST-3681: matrix check failed: $got"
  case "$got" in
    *cursor_null_base=true*) ;;
    *) log_fail "TEST-3681: the cursor override over a null shipped value did not apply ($got)" ;;
  esac
  log_pass "TEST-3681: $got"
}

# --- TEST-3682 (Spec-AC-02) ---------------------------------------------------
test_3682_dispatch_applies_override() {
  CUR_TEST="TEST-3682"
  log_info "TEST-3682: real dispatch applies the claude override only, with an additive model_override..."
  local d; d="$(mk_root t3682)"
  printf '# project-owned\nrouting_override@claude:\n  Code Review: claude-sonnet-5-5\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3682: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Code Review" && o.suggested_model === "claude-sonnet-5-5" && o.model_override.file === "docs/ai/project-config.yaml" && o.model_override.harness === "claude" && o.model_override.role === "Code Review" && o.model_override.model === "claude-sonnet-5-5"'
  run_d "$d" codex
  [[ "$EC" == 0 ]] || log_fail "TEST-3682: codex dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Code Review" && o.suggested_model === "gpt-6-sol" && !("model_override" in o)'
  [[ ! -s "$ERR" ]] || log_fail "TEST-3682: a valid file printed stderr: $(cat "$ERR")"
  log_pass "TEST-3682: claude gets claude-sonnet-5-5 plus model_override; codex keeps gpt-6-sol and no key"
}

# --- TEST-3685 (Spec-AC-04) ---------------------------------------------------
test_3685_ignored_sections() {
  CUR_TEST="TEST-3685"
  log_info "TEST-3685: harness-less and out-of-set headers are ignored with one NOTE each..."
  local d; d="$(mk_root t3685)"
  cat > "$d/docs/ai/project-config.yaml" <<'YAML'
routing_override:
  Code Review: bad-nosuffix
routing_override@unknown:
  Code Review: bad-unknown
routing_override@CLAUDE:
  Code Review: bad-upper
routing_override@codx:
  Code Review: bad-typo
routing_override@:
  Code Review: bad-empty
routing_override@claude:
  Planning: claude-sonnet-5-5
YAML
  local h want
  for h in claude codex gemini cursor unknown; do
    want="$(mk_root t3685-base-$h)"
    run_d "$want" "$h"
    local base_model; base_model="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).suggested_model))' "$OUT")"
    run_d "$d" "$h"
    [[ "$EC" == 0 ]] || log_fail "TEST-3685: $h dispatch exited $EC: $(cat "$ERR")"
    node -e '
      const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      if (String(o.suggested_model) !== process.argv[2] || "model_override" in o) { console.error("Code Review moved on " + process.argv[3] + ": " + o.suggested_model); process.exit(1); }
    ' "$OUT" "$base_model" "$h" || log_fail "TEST-3685: an ignored section changed Code Review on $h"
  done
  local hdr
  for hdr in 'routing_override:' 'routing_override@unknown:' 'routing_override@CLAUDE:' 'routing_override@codx:' 'routing_override@:'; do
    [[ "$(count_lines "section \"$hdr\"" "$ERR")" == 1 ]] || log_fail "TEST-3685: expected exactly one NOTE naming $hdr: $(cat "$ERR")"
  done
  [[ "$(count_lines 'NOTE' "$ERR")" == 5 ]] || log_fail "TEST-3685: expected exactly 5 NOTE lines: $(cat "$ERR")"
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const lib = await import(pathToFileURL(process.argv[3]).href);
const cfg = lib.loadProjectConfig(process.argv[4]);
const routing = m.loadModelRouting(process.argv[4]);
const mk = (harness, role) => ({ verdict: "dispatch", role, harness, suggested_tier: m.TIERS[role], lane: null, validator_independence: null });
console.log(cfg.status + ":" + m.suggestModel(mk("claude", "Planning"), routing, cfg.overrides) + ":" + m.suggestModel(mk("codex", "Planning"), routing, cfg.overrides));
' "$DISPATCH" "$LIB" "$d")"
  [[ "$got" == "ok:claude-sonnet-5-5:gpt-6-sol" ]] || log_fail "TEST-3685: valid section next to ignored ones resolved '$got'"
  log_pass "TEST-3685: five ignored headers noted once each, none applied, the valid claude Planning row applies"
}

# --- TEST-3687 (Spec-AC-06) ---------------------------------------------------
# mal_case <label> <expected "line N: reason" prefix> <file content as printf %b format>
mal_case() {
  local label="$1" want="$2" content="$3"
  local d; d="$(mk_root "t3687-$label")"
  printf '%b' "$content" > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3687[$label]: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "claude-opus-5-5" && !("model_override" in o)'
  [[ "$(count_lines "$want" "$ERR")" == 1 ]] || log_fail "TEST-3687[$label]: stderr lacks exactly one '$want': $(cat "$ERR")"
  [[ "$(count_lines 'no override from it is applied' "$ERR")" == 1 ]] || log_fail "TEST-3687[$label]: stderr lacks the no-override NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'NOTE' "$ERR")" == 2 ]] || log_fail "TEST-3687[$label]: expected 2 NOTE lines: $(cat "$ERR")"
}

test_3687_malformed_all_or_nothing() {
  CUR_TEST="TEST-3687"
  log_info "TEST-3687: twelve malformed fixtures apply nothing; a BOM/CRLF/quoted/commented file applies..."
  local ok='routing_override@claude:\n  Code Review: claude-sonnet-5-5\n'
  mal_case unknown-section   'line 3: unknown section' "${ok}other_section:\n"
  mal_case effort-roles      'line 3: unknown section' "${ok}effort_roles:\n  Code Review: high\n"
  mal_case inline-value      'line 3: unknown section' "${ok}tiers: x\n"
  mal_case repeated-header   'line 3: repeated section' "${ok}routing_override@claude:\n  Planning: claude-sonnet-5-5\n"
  mal_case row-outside       'line 1: row outside a section' "  Code Review: x\n${ok}"
  mal_case tab-row           'line 3: malformed row' "${ok}\tPlanning: claude-sonnet-5-5\n"
  mal_case inline-comment    'line 3: malformed row' "${ok}  Planning: claude-sonnet-5-5 # why\n"
  mal_case duplicate-role    'line 3: duplicate role' "${ok}  Code Review: other-model\n"
  mal_case unknown-role      'line 3: unknown role' "${ok}  Code Reveiw: claude-sonnet-5-5\n"
  mal_case lane-key          'line 3: unknown role' "${ok}  Validation@lightweight: claude-sonnet-5-5\n"
  mal_case null-model        'line 3: invalid model id' "${ok}  Planning: null\n"
  mal_case hash-model        'line 3: invalid model id' "${ok}  Planning: ab#c\n"
  local d; d="$(mk_root t3687-positive)"
  printf '\357\273\277# project-owned\r\nrouting_override@claude:\r\n  # indented comment\r\n  Code Review: "claude-sonnet-5-5"\r\n  Planning: '"'claude-sonnet-5-5'"'\r\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3687: positive control exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "claude-sonnet-5-5" && o.model_override.model === "claude-sonnet-5-5"'
  [[ ! -s "$ERR" ]] || log_fail "TEST-3687: positive control printed stderr: $(cat "$ERR")"
  log_pass "TEST-3687: 12 malformed files resolve the shipped id with line-and-reason NOTEs; the BOM+CRLF+quoted file applies"
}

# --- TEST-3694 (Spec-AC-06) ---------------------------------------------------
test_3694_role_set_pinned() {
  CUR_TEST="TEST-3694"
  log_info "TEST-3694: OVERRIDE_ROLES equals the dispatch TIERS keys; odd role names parse safely..."
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const lib = await import(pathToFileURL(process.argv[3]).href);
const a = [...lib.OVERRIDE_ROLES].sort().join("|"), b = Object.keys(m.TIERS).sort().join("|");
if (a !== b) { console.error("role sets differ:\n  " + a + "\n  " + b); process.exit(1); }
const slash = lib.parseProjectConfig("routing_override@claude:\n  Implementation Preparation / Worktree decision: claude-haiku-5-5\n");
if (!slash.ok || slash.overrides.claude["Implementation Preparation / Worktree decision"] !== "claude-haiku-5-5") { console.error("slash role did not parse"); process.exit(1); }
const odd = lib.parseProjectConfig("routing_override@claude:\n  constructor: claude-haiku-5-5\n  toString: claude-haiku-5-5\nrouting_override@constructor:\n  Planning: claude-haiku-5-5\n");
if (odd.ok || odd.errors.length !== 2 || !odd.errors.every((e) => e.includes("unknown role"))) { console.error("odd roles: " + JSON.stringify(odd)); process.exit(1); }
if (lib.overrideFor(odd.overrides, "constructor", "Planning") !== null || lib.overrideFor(slash.overrides, "toString", "constructor") !== null) { console.error("inherited member resolved"); process.exit(1); }
console.log("roles=" + lib.OVERRIDE_ROLES.length);
' "$DISPATCH" "$LIB")" || log_fail "TEST-3694: $got"
  log_pass "TEST-3694: closed role set equals TIERS ($got); slash role parses; constructor/toString are unknown roles"
}

# mk_val_root <name> — like mk_root but a Validation dispatch (rule 11) on the
# lightweight lane (spec ceremony_level 1), last implementer model recorded.
mk_val_root() {
  local d; d="$(mk_root "$1")"
  sed -i.bak -e 's/^  status: pass$/  status: not_run/' "$d/docs/ai/STATE.yaml"
  sed -i.bak -e 's/^number: 1$/number: 1\nceremony_level: 1/' "$d/docs/specs/SPEC-0001-fx.md"
  rm -f "$d/docs/ai/STATE.yaml.bak" "$d/docs/specs/SPEC-0001-fx.md.bak"
  cat >> "$d/docs/ai/STATE.yaml" <<YAML
metrics:
  work_items:
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: TDD Implementation
          model_id: ${2:-claude-haiku-5-5}
          started_utc: 2026-07-01T00:02:00Z
          ended_utc: 2026-07-01T00:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
YAML
  printf '%s' "$d"
}

# --- TEST-3683 (Spec-AC-03) ---------------------------------------------------
test_3683_override_beats_lightweight_row() {
  CUR_TEST="TEST-3683"
  log_info "TEST-3683: a Validation override beats the shipped Validation@lightweight row..."
  local d; d="$(mk_val_root t3683 claude-opus-5-5)"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3683: control dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.lane.selected === "lightweight" && o.suggested_model === "claude-sonnet-5-5" && !("model_override" in o)'
  printf 'routing_override@claude:\n  Validation: claude-haiku-5-5\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3683: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.lane.selected === "lightweight" && o.suggested_model === "claude-haiku-5-5" && o.model_override.model === "claude-haiku-5-5" && o.model_override.role === "Validation"'
  log_pass "TEST-3683: lightweight-lane Validation resolves the override (claude-haiku-5-5), not the lane row (claude-sonnet-5-5)"
}

# --- TEST-3684 (Spec-AC-03) ---------------------------------------------------
test_3684_validator_independence_backstop() {
  CUR_TEST="TEST-3684"
  log_info "TEST-3684: the validator-independence backstop runs after an override (Mode A and B)..."
  cat > "$TEST_DIR/modea-va.yaml" <<'YAML'
tiers:
  mechanical: mech-a
  standard: std-a
  premium: prem-a
validation_alternate: alt-a
YAML
  mkdir -p "$TEST_DIR/modea-va/.aai/system"
  cp "$TEST_DIR/modea-va.yaml" "$TEST_DIR/modea-va/.aai/system/MODEL_ROUTING.yaml"
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const lib = await import(pathToFileURL(process.argv[3]).href);
const shipped = m.loadModelRouting(process.argv[4]);
const modeA = m.loadModelRouting(process.argv[5]);
const mk = (harness, impl) => ({ verdict: "dispatch", role: "Validation", harness, suggested_tier: "standard", lane: { selected: "lightweight" }, validator_independence: { implementer_model: impl, must_differ: true } });
const ov = lib.parseProjectConfig("routing_override@claude:\n  Validation: claude-haiku-5-5\nrouting_override@cursor:\n  Validation: cursor-x\nrouting_override@codex:\n  Validation: gpt-6.1-sol\n").overrides;
const fail = (msg) => { console.error(msg); process.exit(1); };
// Mode B, claude: override == implementer -> replaced from the claude tiers at or above standard.
let o = mk("claude", "claude-haiku-5-5");
let r = m.suggestModel(o, shipped, ov);
if (r !== "claude-sonnet-5-5" || o.validator_independence.residual) fail("claude backstop: " + r);
// Mode B, cursor: override == implementer, no cursor map -> kept, residual recorded.
o = mk("cursor", "cursor-x");
r = m.suggestModel(o, shipped, ov);
if (r !== "cursor-x" || o.validator_independence.residual !== "single_model_harness_reuse") fail("cursor residual: " + r + " " + JSON.stringify(o.validator_independence));
// Mode B, codex: override differs from implementer -> kept.
o = mk("codex", "gpt-6-sol");
r = m.suggestModel(o, shipped, ov);
if (r !== "gpt-6.1-sol" || o.validator_independence.residual) fail("codex distinct: " + r);
// Mode A: override == implementer -> validation_alternate.
o = mk("claude", "claude-haiku-5-5");
r = m.suggestModel(o, modeA, ov);
if (r !== "alt-a") fail("mode A backstop: " + r);
console.log("ok");
' "$DISPATCH" "$LIB" "$PROJECT_ROOT" "$TEST_DIR/modea-va")" || log_fail "TEST-3684: $got"
  # CLI: the consumer value is reported, the backstop value is dispatched.
  local d; d="$(mk_val_root t3684 claude-haiku-5-5)"
  printf 'routing_override@claude:\n  Validation: claude-haiku-5-5\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3684: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.model_override.model === "claude-haiku-5-5" && o.suggested_model === "claude-sonnet-5-5" && o.suggested_model !== o.model_override.model'
  log_pass "TEST-3684: backstop replaces an implementer-equal override (Mode A and B), residual on an empty map; model_override keeps the consumer value"
}

# --- TEST-3686 (Spec-AC-05) ---------------------------------------------------
test_3686_byte_identity_vs_pre_ride() {
  CUR_TEST="TEST-3686"
  log_info "TEST-3686: absent, non-matching and comments-only files are byte-identical to the pre-ride dispatch..."
  local pre="$TEST_DIR/pre-ride" f
  mkdir -p "$pre"
  for f in "$PROJECT_ROOT"/.aai/scripts/*; do
    [[ "${f##*/}" == orchestration-dispatch.mjs ]] && continue
    ln -s "$f" "$pre/${f##*/}"
  done
  git -C "$PROJECT_ROOT" cat-file -p "$PRE_RIDE_BLOB" > "$pre/orchestration-dispatch.mjs" \
    || log_fail "TEST-3686: pre-ride blob $PRE_RIDE_BLOB not readable (fail closed)"
  [[ -s "$pre/orchestration-dispatch.mjs" ]] || log_fail "TEST-3686: pre-ride blob is empty"
  local label content d
  for label in absent codex-only comments-only; do
    d="$(mk_root "t3686-$label")"
    case "$label" in
      absent) ;;
      codex-only) printf 'routing_override@codex:\n  Planning: gpt-6-sol\n' > "$d/docs/ai/project-config.yaml" ;;
      comments-only) printf '# project-owned\n\n# nothing yet\n' > "$d/docs/ai/project-config.yaml" ;;
    esac
    local h
    for h in claude codex; do
      DISPATCH_BIN="$pre/orchestration-dispatch.mjs"
      run_d "$d" "$h"
      local pre_ec="$EC"
      cp "$OUT" "$d/pre.json"; cp "$ERR" "$d/pre.err"
      DISPATCH_BIN=""
      run_d "$d" "$h"
      [[ "$pre_ec" == 0 && "$EC" == 0 ]] || log_fail "TEST-3686[$label/$h]: exit codes pre=$pre_ec now=$EC: $(cat "$ERR")"
      cmp -s "$d/pre.json" "$OUT" || log_fail "TEST-3686[$label/$h]: stdout differs from the pre-ride dispatch"
      cmp -s "$d/pre.err" "$ERR" || log_fail "TEST-3686[$label/$h]: stderr differs from the pre-ride dispatch: $(cat "$ERR")"
      [[ "$(count_lines 'model_override' "$OUT")" == 0 ]] || log_fail "TEST-3686[$label/$h]: model_override key present"
      [[ "$(count_lines 'project-config' "$ERR")" == 0 ]] || log_fail "TEST-3686[$label/$h]: project-config NOTE on stderr"
    done
  done
  log_pass "TEST-3686: stdout, stderr and exit code byte-equal to blob $PRE_RIDE_BLOB for absent, non-matching and comments-only files"
}

# --- TEST-3688 (Spec-AC-07) ---------------------------------------------------
test_3688_unpriced_applied_and_noted() {
  CUR_TEST="TEST-3688"
  log_info "TEST-3688: an unpriced override is applied with one NOTE; priced ids are silent..."
  local d; d="$(mk_root t3688)"
  printf 'routing_override@claude:\n  Code Review: acme-model-1\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3688: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "acme-model-1" && o.model_override.model === "acme-model-1"'
  [[ "$(count_lines 'unpriced' "$ERR")" == 1 ]] || log_fail "TEST-3688: expected exactly one unpriced NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'claude/Code Review -> acme-model-1' "$ERR")" == 1 ]] || log_fail "TEST-3688: NOTE must name harness, role and model: $(cat "$ERR")"
  local id
  for id in claude-sonnet-5-5 'claude-sonnet-5-5[1m]' claude-sonnet-5-5-20261101; do
    d="$(mk_root t3688-priced)"
    printf 'routing_override@claude:\n  Code Review: %s\n' "$id" > "$d/docs/ai/project-config.yaml"
    run_d "$d" claude
    [[ "$EC" == 0 ]] || log_fail "TEST-3688: $id dispatch exited $EC: $(cat "$ERR")"
    [[ ! -s "$ERR" ]] || log_fail "TEST-3688: priced id $id printed stderr: $(cat "$ERR")"
    jassert "$OUT" 'o.suggested_model === "'"$id"'"'
    local cost
    cost="$(run_mjs '
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const p = await import(pathToFileURL(process.argv[2]).href);
const o = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const c = p.runCostUsd(p.loadPricing(process.argv[4]), o.suggested_model, 1000, 1000);
console.log(c === null ? "null" : "number");
' "$PROJECT_ROOT/.aai/scripts/lib/pricing.mjs" "$OUT" "$d/.aai/system/PRICING.yaml")"
    [[ "$cost" == number ]] || log_fail "TEST-3688: dispatched $id does not cost through runCostUsd"
  done
  log_pass "TEST-3688: acme-model-1 applied with one unpriced NOTE; three priced spellings silent and costable"
}

# --- TEST-3691 (Spec-AC-10) ---------------------------------------------------
test_3691_effort_unaffected() {
  CUR_TEST="TEST-3691"
  log_info "TEST-3691: an override never moves suggested_effort / harness_effort / table freshness..."
  local h role dd
  # Real dispatches: Code Review (rule 13) and Validation (rule 11) fixtures.
  for role in "Code Review" Validation; do
    for h in claude codex gemini cursor; do
      if [[ "$role" == Validation ]]; then dd="$(mk_val_root "t3691-v-$h")"; else dd="$(mk_root "t3691-c-$h")"; fi
      run_d "$dd" "$h"
      [[ "$EC" == 0 ]] || log_fail "TEST-3691: $role/$h control exited $EC: $(cat "$ERR")"
      cp "$OUT" "$dd/base.json"
      printf 'routing_override@%s:\n  %s: acme-effort-probe-1\n' "$h" "$role" > "$dd/docs/ai/project-config.yaml"
      run_d "$dd" "$h"
      [[ "$EC" == 0 ]] || log_fail "TEST-3691: $role/$h override exited $EC: $(cat "$ERR")"
      jassert "$OUT" 'o.model_override.model === "acme-effort-probe-1"'
      node -e '
        const rd = (f) => JSON.parse(require("fs").readFileSync(f, "utf8"));
        const a = rd(process.argv[1]), b = rd(process.argv[2]);
        if (a.suggested_effort !== b.suggested_effort || a.harness_effort !== b.harness_effort) { console.error("effort moved: " + a.suggested_effort + "/" + a.harness_effort + " vs " + b.suggested_effort + "/" + b.harness_effort); process.exit(1); }
      ' "$dd/base.json" "$OUT" || log_fail "TEST-3691: $role on $h: an override moved effort"
    done
  done
  # Every TIERS role through the pure resolvers (the effort functions take no override input).
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const lib = await import(pathToFileURL(process.argv[3]).href);
const routing = m.loadModelRouting(process.argv[4]);
let n = 0;
for (const harness of ["claude", "codex", "gemini", "cursor"]) {
  for (const role of Object.keys(m.TIERS)) {
    const ov = lib.parseProjectConfig("routing_override@" + harness + ":\n  " + role + ": acme-effort-probe-1\n").overrides;
    const mk = () => ({ verdict: "dispatch", role, harness, suggested_tier: m.TIERS[role], lane: null, validator_independence: null });
    const a = mk(), b = mk();
    m.suggestModel(a, routing, null);
    m.suggestModel(b, routing, ov);
    a.suggested_effort = m.suggestEffort(a, routing); b.suggested_effort = m.suggestEffort(b, routing);
    if (a.suggested_effort !== b.suggested_effort || m.harnessEffort(a, routing, harness) !== m.harnessEffort(b, routing, harness)) { console.error("moved " + harness + "/" + role); process.exit(1); }
    n++;
  }
}
console.log("pairs=" + n);
' "$DISPATCH" "$LIB" "$PROJECT_ROOT")" || log_fail "TEST-3691: $got"
  # Table freshness with a pinned clock: identical with and without the file.
  local fd; fd="$(mk_root t3691-fresh)"
  node "$FRESHNESS" check --root "$fd" --now 2026-11-14T00:00:00Z > "$fd/fresh-a.txt" 2>&1 || true
  printf 'routing_override@claude:\n  Code Review: acme-effort-probe-1\n' > "$fd/docs/ai/project-config.yaml"
  node "$FRESHNESS" check --root "$fd" --now 2026-11-14T00:00:00Z > "$fd/fresh-b.txt" 2>&1 || true
  [[ -s "$fd/fresh-a.txt" ]] || log_fail "TEST-3691: table-freshness printed nothing"
  cmp -s "$fd/fresh-a.txt" "$fd/fresh-b.txt" || log_fail "TEST-3691: table-freshness output changed with the file present"
  log_pass "TEST-3691: effort identical for 8 real dispatches and $got; table-freshness output identical"
}

main() {
  check_deps
  test_3681_resolution_matrix
  test_3682_dispatch_applies_override
  test_3683_override_beats_lightweight_row
  test_3684_validator_independence_backstop
  test_3685_ignored_sections
  test_3686_byte_identity_vs_pre_ride
  test_3687_malformed_all_or_nothing
  test_3688_unpriced_applied_and_noted
  test_3691_effort_unaffected
  test_3694_role_set_pinned
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
