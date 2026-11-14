#!/usr/bin/env bash
#
# Test: aai-project-config — the consumer-owned docs/ai/project-config.yaml and
# its routing_override@<harness> section (spec-consumer-config-routing-override).
# TEST-3680..3707 here (parser library, dispatch wiring, twin parity, docs),
# each as one test_NNNN_* function wired into main() below.
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

# shipped_model <root> <harness> <role> [lane] [implementer] — the id the
# fixture's OWN copied MODEL_ROUTING.yaml resolves with no override. Tests
# compare against this, never a literal routed id, so a stamp-clean routing
# refresh cannot turn this suite red (review CR-2).
shipped_model() {
  run_mjs '
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.argv[2]).href);
const [root, harness, role, lane, impl] = process.argv.slice(3);
const out = { verdict: "dispatch", role, harness, suggested_tier: m.TIERS[role], lane: lane ? { selected: lane } : null,
  validator_independence: impl ? { implementer_model: impl, must_differ: true } : null };
process.stdout.write(String(m.suggestModel(out, m.loadModelRouting(root))));
' "$DISPATCH" "$@"
}

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
  local cx; cx="$(shipped_model "$d" codex "Code Review")"
  [[ -n "$cx" && "$cx" != null ]] || log_fail "TEST-3682: the fixture table resolves no codex Code Review id"
  run_d "$d" codex
  [[ "$EC" == 0 ]] || log_fail "TEST-3682: codex dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" "o.role === \"Code Review\" && o.suggested_model === \"$cx\" && !(\"model_override\" in o)"
  [[ ! -s "$ERR" ]] || log_fail "TEST-3682: a valid file printed stderr: $(cat "$ERR")"
  log_pass "TEST-3682: claude gets claude-sonnet-5-5 plus model_override; codex keeps its shipped $cx and no key"
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
  [[ "$got" == "ok:claude-sonnet-5-5:$(shipped_model "$d" codex Planning)" ]] || log_fail "TEST-3685: valid section next to ignored ones resolved '$got'"
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
  jassert "$OUT" "o.suggested_model === \"$(shipped_model "$d" claude "Code Review")\" && !(\"model_override\" in o)"
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
  # Review NB-2: a path that exists but cannot be read (here a directory) is
  # malformed and NOTEd, never silently treated as absent.
  local u; u="$(mk_root t3687-unreadable)"
  mkdir -p "$u/docs/ai/project-config.yaml"
  run_d "$u" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3687[unreadable]: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" "o.suggested_model === \"$(shipped_model "$u" claude "Code Review")\" && !(\"model_override\" in o)"
  [[ "$(count_lines 'unreadable (EISDIR)' "$ERR")" == 1 ]] || log_fail "TEST-3687[unreadable]: stderr lacks the unreadable NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'no override from it is applied' "$ERR")" == 1 ]] || log_fail "TEST-3687[unreadable]: stderr lacks the no-override NOTE: $(cat "$ERR")"
  local d; d="$(mk_root t3687-positive)"
  printf '\357\273\277# project-owned\r\nrouting_override@claude:\r\n  # indented comment\r\n  Code Review: "claude-sonnet-5-5"\r\n  Planning: '"'claude-sonnet-5-5'"'\r\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3687: positive control exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "claude-sonnet-5-5" && o.model_override.model === "claude-sonnet-5-5"'
  [[ ! -s "$ERR" ]] || log_fail "TEST-3687: positive control printed stderr: $(cat "$ERR")"
  log_pass "TEST-3687: 12 malformed files and an unreadable path resolve the shipped id with NOTEs; the BOM+CRLF+quoted file applies"
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

# mk_role_root <name> <role> — a scratch root whose STATE makes the dispatcher
# choose <role> (rule in brackets): Planning [5: spec file missing], Code
# Review [13], Implementation [9c], TDD Implementation [9a], Remediation [10],
# Validation [11], Technology extraction [3], Bootstrap [4], Implementation
# Preparation / Worktree decision [8], Metrics Flush [14]. Echoes the dir.
mk_role_root() {
  local d st; d="$(mk_root "$1")"; st="$d/docs/ai/STATE.yaml"
  case "$2" in
    "Code Review") ;;
    "Validation") d="$(mk_val_root "$1")"; st="$d/docs/ai/STATE.yaml" ;;
    "Metrics Flush") sed -i.bak -e '/^code_review:/,/^last_validation:/ s/^  status: not_run$/  status: pass/' "$st" ;;
    "Remediation") sed -i.bak -e '/^last_validation:/,/^human_input:/ s/^  status: pass$/  status: fail/' "$st" ;;
    "Technology extraction") rm -f "$d/docs/TECHNOLOGY.md" ;;
    "Bootstrap") rm -f "$d/.aai/workflow/WORKFLOW.md" ;;
    "Planning") rm -f "$d/docs/specs/SPEC-0001-fx.md" ;;
    "Implementation Preparation / Worktree decision")
      sed -i.bak -e 's/^  recommendation: optional$/  recommendation: required/' -e 's/^  user_decision: inline$/  user_decision: undecided/' "$st" ;;
    "TDD Implementation") sed -i.bak -e 's/^    phase: implementation$/    phase: preparation/' "$st" ;;
    "Implementation")
      sed -i.bak -e 's/^    phase: implementation$/    phase: preparation/' -e 's/^  selected: tdd$/  selected: loop/' "$st" ;;
    *) log_fail "mk_role_root: unknown role $2" ;;
  esac
  rm -f "$st.bak"
  printf '%s' "$d"
}

# --- TEST-3683 (Spec-AC-03) ---------------------------------------------------
test_3683_override_beats_lightweight_row() {
  CUR_TEST="TEST-3683"
  log_info "TEST-3683: a Validation override beats the shipped Validation@lightweight row..."
  local d; d="$(mk_val_root t3683 claude-opus-5-5)"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3683: control dispatch exited $EC: $(cat "$ERR")"
  local lw; lw="$(shipped_model "$d" claude Validation lightweight claude-opus-5-5)"
  [[ "$lw" != claude-haiku-5-5 ]] || log_fail "TEST-3683: the fixture lane row already resolves the override id; the case would prove nothing"
  jassert "$OUT" "o.role === \"Validation\" && o.lane.selected === \"lightweight\" && o.suggested_model === \"$lw\" && !(\"model_override\" in o)"
  printf 'routing_override@claude:\n  Validation: claude-haiku-5-5\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3683: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.lane.selected === "lightweight" && o.suggested_model === "claude-haiku-5-5" && o.model_override.model === "claude-haiku-5-5" && o.model_override.role === "Validation"'
  log_pass "TEST-3683: lightweight-lane Validation resolves the override (claude-haiku-5-5), not the lane row ($lw)"
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
const ct = shipped.harnesses.claude.tiers;
const want = ["standard", "premium"].map((t) => ct[t]).find((x) => x && x !== "claude-haiku-5-5");
if (!want) fail("the fixture claude tiers offer no replacement; the case would prove nothing");
let o = mk("claude", "claude-haiku-5-5");
let r = m.suggestModel(o, shipped, ov);
if (r !== want || o.validator_independence.residual) fail("claude backstop: " + r + " want " + want);
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
  jassert "$OUT" 'o.role === "Validation" && o.model_override.model === "claude-haiku-5-5" && typeof o.suggested_model === "string" && o.suggested_model !== o.model_override.model'
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
  local h role dd slug
  # Real dispatches: every one of the ten TIERS roles, each from the fixture
  # STATE shape that makes the dispatcher choose it, on all four harnesses.
  for role in "Planning" "Code Review" "Implementation" "TDD Implementation" "Remediation" "Validation" \
    "Technology extraction" "Bootstrap" "Implementation Preparation / Worktree decision" "Metrics Flush"; do
    for h in claude codex gemini cursor; do
      slug="${role//[^A-Za-z]/_}"
      dd="$(mk_role_root "t3691-${slug}-$h" "$role")"
      run_d "$dd" "$h"
      [[ "$EC" == 0 ]] || log_fail "TEST-3691: $role/$h control exited $EC: $(cat "$ERR")"
      jassert "$OUT" "o.verdict === \"dispatch\" && o.role === \"$role\""
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
  log_pass "TEST-3691: effort identical for 40 real dispatches (10 roles x 4 harnesses) and $got; table-freshness output identical"
}

# --- TEST-3690 (Spec-AC-09) ---------------------------------------------------
test_3690_upgrading_note() {
  CUR_TEST="TEST-3690"
  log_info "TEST-3690: UPGRADING comment points at the consumer config; stamp-guard passes..."
  [[ "$(/usr/bin/grep -ci 're-apply' "$ROUTING" || true)" == 0 ]] || log_fail "TEST-3690: MODEL_ROUTING.yaml still says re-apply"
  /usr/bin/grep -qF 'docs/ai/project-config.yaml' "$ROUTING" || log_fail "TEST-3690: UPGRADING note does not name docs/ai/project-config.yaml"
  /usr/bin/grep -qF 'routing_override' "$ROUTING" || log_fail "TEST-3690: UPGRADING note does not name routing_override"
  /usr/bin/grep -qF 'CHANGE-0192' "$ROUTING" || log_fail "TEST-3690: UPGRADING note lost CHANGE-0192"
  /usr/bin/grep -qF 'spec-update-installs-ref-guard-undisclosed Amendment 2' "$ROUTING" || log_fail "TEST-3690: UPGRADING note lost the Amendment 2 citation"
  [[ "$(/usr/bin/grep -c 'CHANGE-DRAFT' "$ROUTING" || true)" == 0 ]] || log_fail "TEST-3690: MODEL_ROUTING.yaml names a CHANGE-DRAFT id"
  local base out ec=0
  base="$(git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null)" || base=""
  [[ -n "$base" ]] || log_fail "TEST-3690: cannot compute the merge-base of HEAD and origin/main (fail closed)"
  out="$(node "$FRESHNESS" stamp-guard --base "$base" --root "$PROJECT_ROOT" 2>&1)" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-3690: stamp-guard exited $ec: $out"
  # The gate, not this ride's comment-only fact: a later correctly re-stamped
  # routing refresh prints CHANGED-STAMPED and must stay green (review CR-1).
  if grep -qF 'VIOLATION .aai/system/MODEL_ROUTING.yaml' <<<"$out"; then log_fail "TEST-3690: stamp-guard reported a MODEL_ROUTING violation: $out"; fi
  grep -qE '^(UNCHANGED|RESTAMPED|CHANGED-STAMPED) \.aai/system/MODEL_ROUTING\.yaml$' <<<"$out" || log_fail "TEST-3690: stamp-guard printed no verdict line for MODEL_ROUTING: $out"
  log_pass "TEST-3690: UPGRADING note names the consumer config, no re-apply, citations kept, stamp-guard passes"
}

# --- TEST-3692 (Spec-AC-11) — core sync seam -----------------------------------
test_3692_core_sync_seam() {
  CUR_TEST="TEST-3692"
  log_info "TEST-3692: a core sync leaves the consumer file alone and its readers work in the target..."
  local t ec=0 out
  t="$TEST_DIR/t3692"; rm -rf "$t"; mkdir -p "$t"
  git -C "$t" init -q || log_fail "TEST-3692: scratch git init failed"
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t" --profile core >/dev/null 2>&1 || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-3692: core sync exited $ec"
  [[ ! -e "$t/docs/ai/project-config.yaml" ]] || log_fail "TEST-3692: sync seeded docs/ai/project-config.yaml"
  [[ -f "$t/.aai/scripts/lib/project-config.mjs" ]] || log_fail "TEST-3692: sync did not deliver lib/project-config.mjs"
  mkdir -p "$t/docs/ai" "$t/docs/specs" "$t/.aai/workflow"
  [[ -f "$t/.aai/workflow/WORKFLOW.md" ]] || echo "# Workflow fixture" > "$t/.aai/workflow/WORKFLOW.md"
  [[ -f "$t/docs/TECHNOLOGY.md" ]] || echo "# Technology fixture" > "$t/docs/TECHNOLOGY.md"
  cat > "$t/docs/ai/STATE.yaml" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
active_work_items:
  - ref_id: CHANGE-0001
    status: in_progress
    phase: planning
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: null
implementation_strategy:
  selected: undecided
  source: null
  rationale: null
worktree:
  recommendation: optional
  user_decision: undecided
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
  printf 'routing_override@claude:\n  Planning: claude-sonnet-5-5\n' > "$t/docs/ai/project-config.yaml"
  DISPATCH_BIN="$t/.aai/scripts/orchestration-dispatch.mjs"
  run_d "$t" claude
  [[ "$EC" == 0 ]] || { DISPATCH_BIN=""; log_fail "TEST-3692: the target's own dispatch (claude) exited $EC: $(cat "$ERR")"; }
  jassert "$OUT" 'o.role === "Planning" && o.model_override && o.model_override.model === "claude-sonnet-5-5" && o.suggested_model === "claude-sonnet-5-5"'
  run_d "$t" codex
  DISPATCH_BIN=""
  [[ "$EC" == 0 ]] || log_fail "TEST-3692: the target's own dispatch (codex) exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Planning" && !("model_override" in o)'
  out="$(node "$t/.aai/scripts/aai-doctor.mjs" --root "$t" --json 2>&1)" || true
  echo "$out" | node -e '
    let s = ""; process.stdin.on("data", (c) => s += c);
    process.stdin.on("end", () => {
      const c = JSON.parse(s).categories.find((x) => x.id === "CAT-22");
      if (!c || !JSON.stringify(c.detail.overrides).includes("\"role\":\"Planning\"") || !JSON.stringify(c.detail.overrides).includes("\"harness\":\"claude\"")) { console.error(JSON.stringify(c)); process.exit(1); }
    });' || log_fail "TEST-3692: the target's doctor has no CAT-22 naming claude/Planning"
  ec=0
  (cd "$t" && node .aai/scripts/docs-audit.mjs --quick --no-event > audit.log 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-3692: the target's docs-audit failed (rc $ec): $(tail -n 5 "$t/audit.log")"
  if grep -qF 'project-config.yaml' "$t/audit.log"; then log_fail "TEST-3692: the target's docs-audit flags project-config.yaml: $(cat "$t/audit.log")"; fi
  ec=0; git -C "$t" check-ignore -q docs/ai/project-config.yaml || ec=$?
  [[ "$ec" == 1 ]] || log_fail "TEST-3692: git check-ignore exited $ec for docs/ai/project-config.yaml (want 1: not ignored)"
  log_pass "TEST-3692: core sync seeds nothing; the target's dispatch, doctor and docs-audit honour the file; it is not git-ignored"
}

# --- TEST-3693 (Spec-AC-11) — registration -------------------------------------
test_3693_registration() {
  CUR_TEST="TEST-3693"
  log_info "TEST-3693: PROFILES core entry, canon line, select-suites reach..."
  local prof="$PROJECT_ROOT/.aai/system/PROFILES.yaml" secn f out
  secn="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f' "$prof")"
  grep -qxF '  - .aai/scripts/lib/project-config.mjs' <<<"$secn" || log_fail "TEST-3693: PROFILES core block does not list lib/project-config.mjs"
  grep -qxF 'project-config.yaml' "$PROJECT_ROOT/.aai/system/DOCS_AI_CANON.list" || log_fail "TEST-3693: DOCS_AI_CANON.list lacks the exact line project-config.yaml"
  f="$TEST_DIR/t3693-files.txt"
  for p in .aai/scripts/aai-sync.ps1 docs/product/consumer-config.md; do
    printf '%s\n' "$p" > "$f"
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$f" --repo-root "$PROJECT_ROOT" 2>&1)" || true
    grep -qE '^SELECTED aai-project-config ' <<<"$out" || log_fail "TEST-3693: select-suites for only $p does not select aai-project-config: $out"
  done
  log_pass "TEST-3693: PROFILES core, canon line and select-suites reach aai-project-config"
}

# --- TEST-3680 (Spec-AC-01) — both install twins leave the table fresh and the consumer file alone ---
# Drives tests/skills/lib/install-parity.mjs exports with this suite's own scenarios (D-PARITY); nothing of
# SPEC-0284's matrix is touched. Judged on two paths only; other twin divergences are SPEC-0284's business.
test_3680_twin_parity() {
  CUR_TEST="TEST-3680"
  log_info "TEST-3680: sh and ps1 twins of update and sync keep the consumer file and refresh the table..."
  local drv="$TEST_DIR/t3680-driver.mjs" root="$TEST_DIR/t3680-root" out ec=0 have_ps=0
  if command -v pwsh >/dev/null 2>&1; then have_ps=1; else echo "SKIP: TEST-3680 ps1 half skipped, pwsh not found"; fi
  rm -rf "$root"; mkdir -p "$root"
  cat > "$drv" <<'MJS'
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import * as P from '__PARITY__';

const [root, haveps] = process.argv.slice(2);
const TABLE = '.aai/system/MODEL_ROUTING.yaml';
const CONSUMER = 'docs/ai/project-config.yaml';
const planted = Buffer.from('\xEF\xBB\xBFrouting_override@claude:\r\n  Code Review: claude-haiku-5-5\r\npricing:\r\n  acme-model-1:\r\n    input_usd_per_m: 2.00\r\n    output_usd_per_m: 8.00\r\n    source_url: https://acme.example/pricing\r\n    last_verified_utc: "2026-11-14T06:00:00Z"\r\n', 'latin1');
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex').slice(0, 12);
const step = (op) => ({ op, profile: null, flags: [], expect: '0' });
const scenarios = [
  { id: 'CC-UP', tier: 'full', op: 'update', setup: 'older-core', steps: [step('update')], probes: ['.aai/system/AAI_PIN.md'] },
  { id: 'CC-SY', tier: 'full', op: 'sync', setup: 'base', steps: [step('sync')], probes: ['.aai/system/AAI_PIN.md'] },
];
const names = haveps === '1' ? ['sh', 'ps1'] : ['sh'];
const twins = names.map((n) => P.TWINS[n]);
fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
fs.writeFileSync(path.join(root, 'gitconfig'), '');
const ctx = { root, bash: 'bash', ps: 'pwsh', host: P.hostInfo({ ps: haveps === '1' ? 'pwsh' : null, bash: 'bash' }) };
ctx.src = P.buildSource(ctx);
const srcTable = fs.readFileSync(path.join(ctx.src, TABLE));
ctx.setup = (scenario, target, c, twinName) => {
  P.defaultSetup(scenario, target, c, twinName);
  const f = path.join(target, TABLE);
  let t = fs.readFileSync(f, 'utf8');
  const at = t.indexOf('roles@claude:');
  const re = /^  Code Review: \S+/m;
  const head = t.slice(0, at); const tail = t.slice(at).replace(re, '  Code Review: claude-haiku-5-5');
  // The trailing comment keeps the table customized even when a routing
  // refresh makes the shipped Code Review row equal the replacement id.
  t = head + tail + '# consumer edit planted by TEST-3680\n';
  if (Buffer.from(t).equals(srcTable)) throw new Error('planted table equals the source table; the customization did not apply');
  fs.writeFileSync(f, t);
  fs.mkdirSync(path.join(target, 'docs/ai'), { recursive: true });
  fs.writeFileSync(path.join(target, CONSUMER), planted);
};
const rep = P.runMatrix({ scenarios, twins, rows: [], ctx, matrix: 'full', filtered: true });
let bad = 0;
const fail = (m) => { console.log(`FAILCHECK ${m}`); bad += 1; };
for (const sc of rep.scenarios) {
  for (const st of sc.steps) {
    console.log(`EXIT ${sc.id} ${st.twin} ${st.code}`);
    if (st.code !== 0) fail(`${sc.id} ${st.twin} step exited ${st.code}: ${(st.stderr_tail || '').slice(-300)}`);
  }
  for (const b of sc.broken) fail(`${sc.id} broken: ${b}`);
  for (const n of names) {
    const dir = path.join(root, sc.id, `out-${n}`);
    const tb = fs.readFileSync(path.join(dir, TABLE)); const cb = fs.readFileSync(path.join(dir, CONSUMER));
    console.log(`TABLE ${sc.id} ${n} ${tb.equals(srcTable) ? 'replaced-equal-source' : 'DIFFERS'} sha ${sha(tb)} source ${sha(srcTable)}`);
    console.log(`CONSUMER ${sc.id} ${n} ${cb.equals(planted) ? 'unchanged' : 'CHANGED'} sha ${sha(cb)} planted ${sha(planted)}`);
    if (!tb.equals(srcTable)) fail(`${sc.id} ${n}: ${TABLE} is not byte-equal to the source table`);
    if (!cb.equals(planted)) fail(`${sc.id} ${n}: ${CONSUMER} is not byte-equal to the planted bytes`);
  }
  const mine = sc.divergences.filter((d) => d.path === TABLE || d.path === CONSUMER);
  console.log(`DIVERGENCES ${sc.id} on the two paths: ${mine.length} (all paths: ${sc.divergences.length})`);
  for (const d of mine) fail(`${sc.id} twins diverge on ${d.path}: ${d.kind} ${d.detail}`);
}
process.exit(bad ? 1 : 0);
MJS
  sed -i.bak "s#__PARITY__#$PROJECT_ROOT/tests/skills/lib/install-parity.mjs#" "$drv"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE node "$drv" "$root" "$have_ps" 2>&1)" || ec=$?
  printf '%s\n' "$out" | while IFS= read -r l; do case "$l" in EXIT*|TABLE*|CONSUMER*|DIVERGENCES*|FAILCHECK*) echo "  $l";; esac; done
  [[ "$ec" == 0 ]] || log_fail "TEST-3680: twin run failed (rc=$ec): $(printf '%s\n' "$out" | tail -n 15)"
  grep -qF 'EXIT CC-UP sh 0' <<<"$out" || log_fail "TEST-3680: no sh exit line for CC-UP"
  if [[ "$have_ps" == 1 ]]; then grep -qF 'TABLE CC-SY ps1 replaced-equal-source' <<<"$out" || log_fail "TEST-3680: ps1 half did not report CC-SY"; fi
  log_pass "TEST-3680: update and sync twins exit 0, table byte-equal to source, consumer file byte-equal, no twin divergence"
}

# --- TEST-3695 (Spec-AC-12) — CHANGELOG entry and product docs ------------------
test_3695_docs() {
  CUR_TEST="TEST-3695"
  log_info "TEST-3695: CHANGELOG entry, consumer-config product doc, CAT-22 in the doctor doc..."
  local cl="$PROJECT_ROOT/CHANGELOG.md" pd="$PROJECT_ROOT/docs/product/consumer-config.md" dd="$PROJECT_ROOT/docs/product/aai-doctor.md" n body f
  n="$(awk '/^## \[(unreleased|v[0-9.]+)\] — /{ if (tolower($0) ~ /consumer config|project-config/) c++ } END{print c+0}' "$cl")"
  [[ "$n" == 1 ]] || log_fail "TEST-3695: CHANGELOG holds $n headings naming the consumer config, expected exactly 1"
  body="$(awk '/^## \[(unreleased|v[0-9.]+)\] — /{ on = (tolower($0) ~ /consumer config|project-config/) ; next } on' "$cl")"
  for f in 'docs/ai/project-config.yaml' 'routing_override' 'CAT-22'; do
    grep -qF -- "$f" <<<"$body" || log_fail "TEST-3695: the CHANGELOG entry body does not name $f"
  done
  [[ -f "$pd" ]] || log_fail "TEST-3695: docs/product/consumer-config.md does not exist"
  grep -qxF 'capability: consumer-config' "$pd" || log_fail "TEST-3695: consumer-config.md lacks the line 'capability: consumer-config'"
  for f in 'docs/ai/project-config.yaml' 'routing_override@' 'claude' 'codex' 'gemini' 'cursor' 'all-or-nothing' 'unpriced' 'CAT-22' 'model_override'; do
    grep -qF -- "$f" "$pd" || log_fail "TEST-3695: consumer-config.md does not mention $f"
  done
  grep -qiE 'no sync or update (script )?writes|never writes|does not write' "$pd" || log_fail "TEST-3695: consumer-config.md does not say that no sync or update writes the file"
  grep -qF 'CAT-22 Project Config' "$dd" || log_fail "TEST-3695: aai-doctor.md does not document CAT-22 Project Config"
  log_pass "TEST-3695: CHANGELOG entry, consumer-config product doc and CAT-22 doctor doc present"
}

# --- project pricing section (Spec-AC-13, Spec-AC-14, amended Spec-AC-07) -----
# price_block [extra field lines] — a valid pricing entry for acme-model-1.
PRICE_URL="https://acme.example/pricing"
price_block() {
  printf 'pricing:\n  acme-model-1:\n    input_usd_per_m: 2.00\n    output_usd_per_m: 8.00\n    source_url: %s\n    last_verified_utc: "2026-11-14T06:00:00Z"\n%b' "$PRICE_URL" "${1:-}"
}
OVR_ACME='routing_override@claude:\n  Code Review: acme-model-1\n'

# price_mal_case <label> <expected reason text> <errors> <file content (printf %b)>
price_mal_case() {
  local label="$1" want="$2" nerr="$3" content="$4"
  local d; d="$(mk_root "t3696-$label")"
  printf '%b' "$content" > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3696[$label]: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" "o.suggested_model === \"$(shipped_model "$d" claude "Code Review")\" && !(\"model_override\" in o)"
  [[ "$(count_lines "$want" "$ERR")" == 1 ]] || log_fail "TEST-3696[$label]: stderr lacks exactly one '$want': $(cat "$ERR")"
  [[ "$(count_lines 'no override from it is applied' "$ERR")" == 1 ]] || log_fail "TEST-3696[$label]: stderr lacks the no-override NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'NOTE' "$ERR")" == $((nerr + 1)) ]] || log_fail "TEST-3696[$label]: expected $((nerr + 1)) NOTE lines: $(cat "$ERR")"
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const lib = await import(pathToFileURL(process.argv[2]).href);
const p = await import(pathToFileURL(process.argv[3]).href);
const pr = lib.loadCostPricing(process.argv[4], process.argv[4] + "/.aai/system/PRICING.yaml");
console.log(String(p.priceSource(pr, "acme-model-1")) + ":" + ("project" in pr));
' "$LIB" "$PROJECT_ROOT/.aai/scripts/lib/pricing.mjs" "$d")"
  [[ "$got" == "null:false" ]] || log_fail "TEST-3696[$label]: loadCostPricing attached a project price ($got)"
}

# --- TEST-3696 (Spec-AC-13) ---------------------------------------------------
test_3696_pricing_section_parse() {
  CUR_TEST="TEST-3696"
  log_info "TEST-3696: pricing section parses; malformed pricing or null casing voids everything..."
  local got
  got="$(run_mjs '
import { pathToFileURL } from "node:url";
const lib = await import(pathToFileURL(process.argv[2]).href);
const fail = (m) => { console.error(m); process.exit(1); };
const txt = "routing_override@claude:\n  Code Review: acme-model-1\npricing:\n  acme-model-1:\n    input_usd_per_m: 2.00\n    output_usd_per_m: 8\n    source_url: https://acme.example/pricing\n    last_verified_utc: \"2026-11-14T06:00:00Z\"\n  \"acme-model-2\":\n    input_usd_per_m: \"1.5\"\n    output_usd_per_m: 3\n    source_url: https://acme.example/p2\n    last_verified_utc: 2026-11-13T06:00:00Z\n    provider: acme\n    unverified_utc: 2026-11-14T00:00:00Z\n";
const r = lib.parseProjectConfig(txt);
if (!r.ok) fail("valid file refused: " + JSON.stringify(r.errors));
const a = r.prices["acme-model-1"], b = r.prices["acme-model-2"];
if (a.input !== 2 || a.output !== 8 || a.source_url !== "https://acme.example/pricing" || a.last_verified_utc !== "2026-11-14T06:00:00Z" || a.provider !== null || a.unverified_utc !== null || a.line !== 4) fail("entry 1: " + JSON.stringify(a));
if (b.input !== 1.5 || b.output !== 3 || b.provider !== "acme" || b.unverified_utc !== "2026-11-14T00:00:00Z") fail("entry 2: " + JSON.stringify(b));
if (Object.getPrototypeOf(r.prices) !== null) fail("prices is not null-prototype");
if (r.overrides.claude["Code Review"] !== "acme-model-1") fail("override lost next to pricing");
const e = lib.parseProjectConfig("pricing:\n");
if (!e.ok || Object.keys(e.prices).length !== 0) fail("empty pricing section");
console.log("ok");
' "$LIB")" || log_fail "TEST-3696: $got"
  local ok="$OVR_ACME"
  local pb; pb="$(price_block)"
  local pbn="${pb//$'\n'/\\n}\\n"
  local n_miss='pricing:\n  acme-model-1:\n    output_usd_per_m: 8\n    source_url: https://acme.example/pricing\n    last_verified_utc: "2026-11-14T06:00:00Z"\n'
  price_mal_case missing-rate   'line 4: model "acme-model-1" is missing field input_usd_per_m' 1 "${ok}${n_miss}"
  price_mal_case unknown-field  'line 9: unknown field "colour"'         1 "${ok}${pbn}    colour: blue\n"
  price_mal_case repeated-field 'line 9: duplicate field "input_usd_per_m"' 1 "${ok}${pbn}    input_usd_per_m: 3\n"
  price_mal_case negative-rate  'invalid rate "-2"'                      1 "${ok}${pbn//2.00/-2}"
  price_mal_case null-rate      'invalid rate "null"'                    1 "${ok}${pbn//8.00/null}"
  price_mal_case comment-rate   'invalid rate "2.00 # list"'             1 "${ok}${pbn//2.00/2.00 # list}"
  price_mal_case http-url       'invalid source_url "http://acme.example/pricing"' 1 "${ok}${pbn//https:/http:}"
  price_mal_case bad-timestamp  'line 8: invalid timestamp' 1 "${ok}${pbn//2026-11-14T06/2026-13-40T06}"
  price_mal_case upper-provider 'invalid provider "Acme"'                1 "${ok}${pbn}    provider: Acme\n"
  price_mal_case field-first    'line 4: field outside a model'          1 "${ok}pricing:\n    input_usd_per_m: 2\n${pbn#pricing:\\n}"
  price_mal_case duplicate-key  'duplicate model "acme-model-1"'         1 "${ok}${pbn}${pbn#pricing:\\n}"
  price_mal_case key-NULL       'invalid model id "NULL"'                1 "${ok}${pbn//acme-model-1:/NULL:}"
  price_mal_case key-unknown    'invalid model id "Unknown"'             1 "${ok}${pbn//acme-model-1:/Unknown:}"
  price_mal_case key-bracketed  'invalid model id "acme-model-1[1m]"'    1 "${ok}${pbn//acme-model-1:/acme-model-1[1m]:}"
  price_mal_case three-space    'line 9: malformed row'                  1 "${ok}${pbn}   provider: acme\n"
  price_mal_case header-suffix  'unknown section "pricing@codex:"'       1 "${ok}pricing@codex:\n  acme-model-1:\n    input_usd_per_m: 2\n"
  price_mal_case second-header  'repeated section "pricing:"'            1 "${ok}${pbn}pricing:\n"
  price_mal_case null-routing-U 'invalid model id "NULL"'                1 "${pbn}routing_override@claude:\n  Code Review: NULL\n"
  price_mal_case null-routing-C 'invalid model id "Null"'                1 "${pbn}routing_override@claude:\n  Code Review: Null\n"
  log_pass "TEST-3696: valid section parses; 19 malformed fixtures (15 field cases, 2 headers, NULL and Null routing) void override and prices with one NOTE per error"
}

# --- TEST-3697 (Spec-AC-14) ---------------------------------------------------
test_3697_lib_fallback_precedence() {
  CUR_TEST="TEST-3697"
  log_info "TEST-3697: shipped wins, project fills the rest, malformed attaches nothing..."
  local d="$TEST_DIR/t3697"
  mkdir -p "$d/docs/ai" "$d/.aai/system"
  cat > "$d/.aai/system/PRICING.yaml" <<'YAML'
sources:
  acme-pricing:
    provider: acme
models:
  acme-shipped-1:
    input_usd_per_m: 1
    output_usd_per_m: 2
    source_ref: acme-pricing
  acme-nullrate-1:
    input_usd_per_m: null
    output_usd_per_m: null
    source_ref: acme-pricing
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
  # A real shipped priced id, derived from the shipped table (never literal).
  local real
  real="$(run_mjs '
import { pathToFileURL } from "node:url";
const p = await import(pathToFileURL(process.argv[2]).href);
const pr = p.loadPricing(process.argv[3]);
const k = Object.keys(pr.models).find((x) => x !== "unknown" && pr.models[x].input !== null && pr.models[x].output !== null);
process.stdout.write(k || "");
' "$PROJECT_ROOT/.aai/scripts/lib/pricing.mjs" "$PRICING")"
  [[ -n "$real" ]] || log_fail "TEST-3697: shipped PRICING.yaml has no priced row"
  local blk='  %s:\n    input_usd_per_m: %s\n    output_usd_per_m: %s\n    source_url: https://acme.example/p\n    last_verified_utc: "2026-11-14T06:00:00Z"\n'
  {
    printf 'pricing:\n'
    printf "$blk" acme-shipped-1 50 60
    printf "$blk" acme-model-1 2 8
    printf "$blk" acme-nullrate-1 3 12
    printf "$blk" "$real" 99 99
  } > "$d/docs/ai/project-config.yaml"
  got="$(run_mjs '
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const lib = await import(pathToFileURL(process.argv[2]).href);
const p = await import(pathToFileURL(process.argv[3]).href);
const [root, real] = process.argv.slice(4);
const fail = (m) => { console.error(m); process.exit(1); };
const pf = root + "/.aai/system/PRICING.yaml";
const pr = lib.loadCostPricing(root, pf);
const shippedOnly = p.loadPricing(pf);
const M = 1000000;
const cost = (id) => p.runCostUsd(pr, id, M, M);
if (cost("acme-shipped-1") !== 3) fail("shipped did not win for acme-shipped-1: " + cost("acme-shipped-1"));
const realShipped = p.runCostUsd(p.loadPricing(process.argv[6]), real, M, M);
const realPr = lib.loadCostPricing(root, process.argv[6]);
if (p.runCostUsd(realPr, real, M, M) !== realShipped || realShipped === 198) fail("shipped did not win for the real id " + real);
for (const id of ["acme-model-1", "acme-model-1[1m]", "acme-model-1-2026"]) if (cost(id) !== 10) fail(id + " cost " + cost(id));
if (cost("acme-nullrate-1") !== 15) fail("null-priced shipped row not filled: " + cost("acme-nullrate-1"));
for (const id of ["acme-model-1", "acme-model-1[1m]", "acme-model-1-2026"]) {
  const b = p.blendedCostUsd(pr, id, M);
  if (!b || b.cost !== 5) fail("blended " + id + ": " + JSON.stringify(b));
}
if (p.blendedCostUsd(pr, "acme-shipped-1", M).cost !== 1.5) fail("blended shipped");
if (p.runCostUsd(pr, "acme-other-9", M, M) !== null || p.runCostUsd(pr, "acme-model-1", "x", M) !== null) fail("unpriced must stay null");
const src = ["acme-shipped-1", "acme-model-1", "acme-nullrate-1", "acme-other-9"].map((id) => String(p.priceSource(pr, id)));
if (src.join() !== "shipped,project,project,null") fail("priceSource " + src.join());
if (p.priceSource(shippedOnly, "acme-model-1") !== null) fail("shipped-only must not price acme-model-1");
if (p.modelProvider(pr, "acme-shipped-1") !== "acme" || p.modelProvider(pr, "acme-other-9") !== null) fail("modelProvider");
// A malformed file attaches nothing.
fs.appendFileSync(root + "/docs/ai/project-config.yaml", "bogus_section:\n");
const bad = lib.loadCostPricing(root, pf);
if ("project" in bad || p.runCostUsd(bad, "acme-model-1", M, M) !== null || p.priceSource(bad, "acme-nullrate-1") !== null) fail("malformed file attached prices");
console.log("ok");
' "$LIB" "$PROJECT_ROOT/.aai/scripts/lib/pricing.mjs" "$d" "$real" "$PRICING")" || log_fail "TEST-3697: $got"
  log_pass "TEST-3697: shipped wins (synthetic and real ids), project prices fill unknown, null-priced, bracketed and prefix ids; malformed attaches nothing"
}

# --- TEST-3698 (Spec-AC-14) ---------------------------------------------------
# mk_flush_root <name> — scratch root with a done work item whose one run
# recorded tokens on acme-model-1, plus the shipped PRICING.yaml.
mk_flush_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/docs/ai/reviews" "$d/docs/ai/reports"
  cp "$PRICING" "$d/PRICING.yaml"
  printf '# Golden\n\nBody.\n' > "$d/docs/issues/CHANGE-0001-golden.md"
  cat > "$d/docs/ai/STATE.yaml" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-golden.md
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0001-golden.md
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
  status: pass
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths:
  - docs/ai/reviews/review-fixture.md
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-15T11:00:00Z
  ref_id: CHANGE-0001
  evidence_paths:
  - docs/ai/reports/validation-fixture.md
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
tdd_cycle:
  status: IDLE
  test_id: null
metrics:
  work_items:
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: acme-model-1
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:10:00Z
          duration_seconds: 600
          tokens_in: 1000000
          tokens_out: 500000
          cost_usd: null
updated_at_utc: 2026-07-15T11:30:00Z
YAML
  printf '%s' "$d"
}

test_3698_metrics_flush_seam() {
  CUR_TEST="TEST-3698"
  log_info "TEST-3698: real metrics-flush costs a project-priced run; null without the file..."
  local variant d cost basis
  for variant in with without; do
    d="$(mk_flush_root "t3698-$variant")"
    if [[ "$variant" == with ]]; then
      price_block > "$d/docs/ai/project-config.yaml"
    fi
    EC=0
    (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs" --state "$d/docs/ai/STATE.yaml" \
      --metrics "$d/docs/ai/METRICS.jsonl" --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
      --events "$d/docs/ai/EVENTS.jsonl" --now 2026-07-15T12:00:00Z > "$d/flush.log" 2>&1) || EC=$?
    [[ "$EC" == 0 ]] || log_fail "TEST-3698[$variant]: flush exited $EC: $(cat "$d/flush.log")"
    [[ -s "$d/docs/ai/METRICS.jsonl" ]] || log_fail "TEST-3698[$variant]: no ledger row written: $(cat "$d/flush.log")"
    cost="$(node -e 'const l=require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter((x)=>x&&!x.startsWith("#")).pop();const r=JSON.parse(l).agent_runs[0];process.stdout.write(String(r.cost_usd)+"|"+String(r.cost_basis))' "$d/docs/ai/METRICS.jsonl")"
    if [[ "$variant" == with ]]; then
      # 1,000,000 in x 2.00 + 500,000 out x 8.00, per million = 6
      [[ "$cost" == "6|decomposed" ]] || log_fail "TEST-3698: with the file the run cost is '$cost', want 6|decomposed"
    else
      [[ "$cost" == "null|none" ]] || log_fail "TEST-3698: without the file the run cost is '$cost', want null|none"
    fi
  done
  log_pass "TEST-3698: flush wrote cost_usd 6 (decomposed) with the pricing section and null without it"
}

# --- TEST-3699 (Spec-AC-14) ---------------------------------------------------
test_3699_metrics_report_seam() {
  CUR_TEST="TEST-3699"
  log_info "TEST-3699: real metrics-report fills a null ledger cost from the project price..."
  local variant d
  for variant in with without; do
    d="$TEST_DIR/t3699-$variant"
    rm -rf "$d"; mkdir -p "$d/docs/ai"
    cp "$PRICING" "$d/PRICING.yaml"
    printf '%s\n' '{"date_utc":"2026-07-15","ref_id":"CHANGE-0001","title":"Fixture","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"acme-model-1","started_utc":"2026-07-15T10:00:00Z","ended_utc":"2026-07-15T10:10:00Z","duration_seconds":600,"tokens_in":1000000,"tokens_out":500000,"cost_usd":null,"cost_basis":"none","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"none"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null,"cost_basis":"none"},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note","verdict_after_last_implementer":true},"verdict_basis":"global-block","verdict":"PASS"}' > "$d/docs/ai/METRICS.jsonl"
    if [[ "$variant" == with ]]; then price_block > "$d/docs/ai/project-config.yaml"; fi
    EC=0
    (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/metrics-report.mjs" --metrics docs/ai/METRICS.jsonl --pricing PRICING.yaml > "$d/report.txt" 2>&1) || EC=$?
    [[ "$EC" == 0 ]] || log_fail "TEST-3699[$variant]: report exited $EC: $(cat "$d/report.txt")"
  done
  [[ "$(count_lines '$6.00' "$TEST_DIR/t3699-with/report.txt")" -ge 1 ]] || log_fail "TEST-3699: with the file the report shows no 6.00 cost: $(cat "$TEST_DIR/t3699-with/report.txt")"
  [[ "$(count_lines '$6.00' "$TEST_DIR/t3699-without/report.txt")" == 0 ]] || log_fail "TEST-3699: without the file the report shows a cost: $(cat "$TEST_DIR/t3699-without/report.txt")"
  log_pass "TEST-3699: report total is the project arithmetic with the file and shows no cost without it"
}

# --- TEST-3700 (amended Spec-AC-07) -------------------------------------------
test_3700_notes_after_final_model() {
  CUR_TEST="TEST-3700"
  log_info "TEST-3700: no unpriced NOTE for a project-priced id or a backstop-swapped override..."
  local d; d="$(mk_root t3700-priced)"
  { printf 'routing_override@claude:\n  Code Review: acme-model-1\n'; price_block; } > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3700: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "acme-model-1" && o.model_override.model === "acme-model-1"'
  [[ ! -s "$ERR" ]] || log_fail "TEST-3700: a project-priced override printed stderr: $(cat "$ERR")"
  d="$(mk_val_root t3700-swap acme-model-1)"
  printf 'routing_override@claude:\n  Validation: acme-model-1\n' > "$d/docs/ai/project-config.yaml"
  run_d "$d" claude
  [[ "$EC" == 0 ]] || log_fail "TEST-3700: swap dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.role === "Validation" && o.model_override.model === "acme-model-1" && o.suggested_model !== "acme-model-1"'
  [[ "$(count_lines 'unpriced' "$ERR")" == 0 ]] || log_fail "TEST-3700: the swapped override was NOTEd unpriced: $(cat "$ERR")"
  log_pass "TEST-3700: project-priced override silent; a backstop-swapped unpriced override is not NOTEd and keeps model_override"
}

# --- TEST-3702 (Spec-AC-16) ---------------------------------------------------
# cv_case <label> <harness> <override-model> <file-extra> -> runs a Code Review
# dispatch under <harness> with routing_override@<harness> set to the model.
cv_case() {
  local label="$1" h="$2" model="$3" extra="${4:-}"
  local d; d="$(mk_root "t3702-$label")"
  { printf 'routing_override@%s:\n  Code Review: %s\n' "$h" "$model"; printf '%b' "$extra"; } > "$d/docs/ai/project-config.yaml"
  run_d "$d" "$h"
  [[ "$EC" == 0 ]] || log_fail "TEST-3702[$label]: dispatch exited $EC: $(cat "$ERR")"
  jassert "$OUT" 'o.suggested_model === "'"$model"'" && o.model_override.model === "'"$model"'"'
  CV_ROOT="$d"
}

test_3702_cross_vendor_override() {
  CUR_TEST="TEST-3702"
  log_info "TEST-3702: a cross-vendor override is applied with exactly one NOTE and named by the doctor..."
  cv_case codex codex claude-sonnet-5-5
  [[ "$(count_lines 'is cross-vendor' "$ERR")" == 1 ]] || log_fail "TEST-3702: expected exactly one cross-vendor NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'NOTE' "$ERR")" == 1 ]] || log_fail "TEST-3702: expected exactly one NOTE line: $(cat "$ERR")"
  [[ "$(count_lines 'codex/Code Review -> claude-sonnet-5-5 is cross-vendor: a anthropic model on the codex harness (openai); applied' "$ERR")" == 1 ]] \
    || log_fail "TEST-3702: NOTE text is not the D-VENDOR line: $(cat "$ERR")"
  local h
  for h in claude cursor; do
    cv_case "same-$h" "$h" claude-sonnet-5-5
    [[ "$(count_lines 'cross-vendor' "$ERR")" == 0 ]] || log_fail "TEST-3702: $h printed a cross-vendor NOTE: $(cat "$ERR")"
  done
  cv_case unknown codex acme-model-1
  [[ "$(count_lines 'cross-vendor' "$ERR")" == 0 ]] || log_fail "TEST-3702: an id no table knows printed a vendor NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'unpriced' "$ERR")" == 1 && "$(count_lines 'NOTE' "$ERR")" == 1 ]] || log_fail "TEST-3702: unknown id must print only the unpriced NOTE: $(cat "$ERR")"
  cv_case projvendor codex acme-model-1 "$(price_block '    provider: anthropic\n')\n"
  [[ "$(count_lines 'acme-model-1 is cross-vendor: a anthropic model on the codex harness (openai)' "$ERR")" == 1 ]] || log_fail "TEST-3702: a project-priced anthropic id on codex printed no cross-vendor NOTE: $(cat "$ERR")"
  [[ "$(count_lines 'unpriced' "$ERR")" == 0 && "$(count_lines 'NOTE' "$ERR")" == 1 ]] || log_fail "TEST-3702: project-priced id must print only the vendor NOTE: $(cat "$ERR")"
  # the doctor over the same file: PASS naming the cross-vendor override
  cv_case doctor codex claude-sonnet-5-5
  local d="$CV_ROOT" doc line
  mkdir -p "$d/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs" "$d/.aai/scripts/aai-doctor.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/table-freshness.mjs" "$d/.aai/scripts/table-freshness.mjs"
  local f
  for f in cli-pipe-guard guard-config harness project-config pricing; do
    cp "$PROJECT_ROOT/.aai/scripts/lib/$f.mjs" "$d/.aai/scripts/lib/$f.mjs"
  done
  doc="$(env -u AAI_TABLES_HORIZON_DAYS node "$d/.aai/scripts/aai-doctor.mjs" --json 2>/dev/null)" || true
  line="$(printf '%s' "$doc" | node -e '
    let s = ""; process.stdin.on("data", (c) => s += c);
    process.stdin.on("end", () => { const c = JSON.parse(s).categories.find((x) => x.id === "CAT-22"); console.log(c.status + "|" + c.reason + "|" + c.detail.overrides[0].cross_vendor); });')"
  [[ "$line" == PASS\|*"(cross-vendor: anthropic on codex)"*\|true ]] || log_fail "TEST-3702: doctor CAT-22 is not PASS naming the cross-vendor override: $line"
  # HARNESS_VENDOR keys and values pinned
  local pin
  pin="$(run_mjs '
import { pathToFileURL } from "node:url";
const lib = await import(pathToFileURL(process.argv[2]).href);
const p = await import(pathToFileURL(process.argv[3]).href);
const keys = Object.keys(lib.HARNESS_VENDOR).sort().join(",");
const want = [...lib.OVERRIDE_HARNESSES].sort().join(",");
const providers = new Set(Object.values(p.loadPricing(process.argv[4]).sources).map((x) => x.provider));
const bad = Object.values(lib.HARNESS_VENDOR).filter((v) => v !== null && !providers.has(v));
console.log(keys === want && bad.length === 0 && lib.HARNESS_VENDOR.cursor === null ? "ok" : "bad " + keys + " " + bad.join(","));
' "$LIB" "$PROJECT_ROOT/.aai/scripts/lib/pricing.mjs" "$PRICING")"
  [[ "$pin" == ok ]] || log_fail "TEST-3702: HARNESS_VENDOR is not pinned to OVERRIDE_HARNESSES and the shipped providers ($pin)"
  log_pass "TEST-3702: cross-vendor override applied with one NOTE, silent for same-vendor, cursor and unknown vendors, named by CAT-22"
}

# --- TEST-3706 (Spec-AC-20) — CHANGELOG body and product docs for project prices --
test_3706_docs_pricing() {
  CUR_TEST="TEST-3706"
  log_info "TEST-3706: CHANGELOG body, consumer-config, universal-routines and doctor docs cover project prices..."
  local cl="$PROJECT_ROOT/CHANGELOG.md" pd="$PROJECT_ROOT/docs/product/consumer-config.md" ur="$PROJECT_ROOT/docs/product/universal-routines.md" dd="$PROJECT_ROOT/docs/product/aai-doctor.md" body f
  body="$(awk '/^## \[(unreleased|v[0-9.]+)\] — /{ on = (tolower($0) ~ /consumer config|project-config/) ; next } on' "$cl")"
  for f in 'pricing:' 'cross-vendor' 'ROUTING_REFRESH' 'table-freshness.mjs priced'; do
    grep -qF -- "$f" <<<"$body" || log_fail "TEST-3706: the CHANGELOG entry body does not name $f"
  done
  for f in 'pricing:' 'routing_override@codex:' 'routing_override@gemini:' 'shipped' 'cross-vendor' 'freshness WARN'; do
    grep -qF -- "$f" "$pd" || log_fail "TEST-3706: consumer-config.md does not mention $f"
  done
  grep -qiE 'shipped (table|PRICING\.yaml)? ?wins' "$pd" || log_fail "TEST-3706: consumer-config.md does not say the shipped price wins"
  grep -qF 'downstream mode' "$ur" || log_fail "TEST-3706: universal-routines.md does not describe downstream mode"
  grep -qF 'docs/ai/project-config.yaml' "$ur" || log_fail "TEST-3706: universal-routines.md does not name docs/ai/project-config.yaml"
  grep -qF 'project price freshness WARN' "$dd" || log_fail "TEST-3706: aai-doctor.md does not name the project price freshness WARN"
  log_pass "TEST-3706: CHANGELOG body and three product docs cover project prices"
}

# --- TEST-3707 (Spec-AC-21) — suite selection, vendored deps, no new .aai file ---
test_3707_distribution() {
  CUR_TEST="TEST-3707"
  log_info "TEST-3707: select-suites reach, vendored-script deps, no new .aai file or prompt..."
  local f out p want mb ec=0 added prompts
  f="$TEST_DIR/t3707-files.txt"
  printf '%s\n' .aai/routines/ROUTING_REFRESH.routine.md > "$f"
  out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$f" --repo-root "$PROJECT_ROOT" 2>&1)" || true
  for want in aai-routine aai-pricing; do
    grep -qE "^SELECTED $want " <<<"$out" || log_fail "TEST-3707: select-suites for only ROUTING_REFRESH.routine.md does not select $want: $out"
  done
  for p in .aai/scripts/lib/pricing.mjs .aai/scripts/metrics-flush.mjs .aai/scripts/metrics-report.mjs; do
    printf '%s\n' "$p" > "$f"
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$f" --repo-root "$PROJECT_ROOT" 2>&1)" || true
    # a lib/** path escalates to FULL_RUN reason=shared-lib (select-suites fail-open), which runs this suite too
    if [[ "$p" == .aai/scripts/lib/* ]]; then
      grep -qE '^(SELECTED aai-project-config |FULL_RUN reason=shared-lib )' <<<"$out" || log_fail "TEST-3707: select-suites for only $p neither selects aai-project-config nor runs everything: $out"
    else
      grep -qE '^SELECTED aai-project-config ' <<<"$out" || log_fail "TEST-3707: select-suites for only $p does not select aai-project-config: $out"
    fi
  done
  node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" >"$TEST_DIR/t3707-deps.log" 2>&1 || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-3707: check-vendored-script-deps.mjs exited $ec: $(tail -n 8 "$TEST_DIR/t3707-deps.log")"
  ec=0; mb="$(git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null)" || ec=$?
  if [[ "$ec" != 0 || -z "$mb" ]]; then log_fail "TEST-3707: cannot compute the merge-base with origin/main (failing closed)"; fi
  added="$( { git -C "$PROJECT_ROOT" diff --name-status "$mb" -- .aai | awk '$1 ~ /^A/ {print $2}'; git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- .aai; } )"
  # lib/project-config.mjs is the one .aai file the pre-extension ride (SPEC-0290 D-LIB) added; the extension adds none
  added="$(printf '%s\n' "$added" | grep -vxF '.aai/scripts/lib/project-config.mjs' || true)"
  [[ -z "$added" ]] || log_fail "TEST-3707: the change adds a path under .aai/: $added"
  prompts="$( { git -C "$PROJECT_ROOT" diff --name-only "$mb" -- .aai; git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- .aai; } | grep -E '^\.aai/[^/]*\.prompt\.md$' || true )"
  [[ -z "$prompts" ]] || log_fail "TEST-3707: the change touches a .aai/*.prompt.md file: $prompts"
  log_pass "TEST-3707: suite reach, vendored deps clean, no new .aai path and no prompt change"
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
  test_3690_upgrading_note
  test_3692_core_sync_seam
  test_3693_registration
  test_3694_role_set_pinned
  test_3680_twin_parity
  test_3695_docs
  test_3696_pricing_section_parse
  test_3697_lib_fallback_precedence
  test_3698_metrics_flush_seam
  test_3699_metrics_report_seam
  test_3700_notes_after_final_model
  test_3702_cross_vendor_override
  test_3706_docs_pricing
  test_3707_distribution
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
