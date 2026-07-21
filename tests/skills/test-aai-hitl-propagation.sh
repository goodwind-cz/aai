#!/usr/bin/env bash
#
# Test: aai-hitl-propagation (hitl-decision-propagation /
# SPEC-DRAFT-spec-hitl-decision-propagation.md, TEST-001..015).
#
# Verifies the fix that lets resolving a HITL block actually reach the STATE
# field the loop's dispatch reads:
#   - .aai/SKILL_HITL.prompt.md declares the 9-row [HITL-1]..[HITL-9]
#     trigger->target mapping, the narrowed guardrail (replacing the old
#     absolute prohibition), the write-ordering rule, the answer-normalization
#     table, and the fail-closed obligations (TEST-001..007, prompt-contract
#     greps).
#   - .aai/ORCHESTRATION_HITL.prompt.md stamps the literal `[HITL-<n>]` token
#     into blocking_reason on raise; SKILL_HITL declares it reads that token
#     and fails closed when ambiguous (TEST-008/009).
#   - orchestration-dispatch.mjs rule 8 actually stops firing once the
#     declared [HITL-7] command is applied -- TEST-010/011 are CONTROLS
#     (green before AND after this change; they only prove the gate is real),
#     TEST-012 is the SEAM test: extract the command text from the prompt,
#     run it, re-dispatch.
#   - TEST-013 (prompt-diet ledger true-up) lives in test-aai-prompt-diet.sh
#     and is not duplicated here.
#   - TEST-014/015: no protected_paths_l3 path touched; the pre-existing
#     dispatch/state suites stay green.
#
# ALL dispatch fixtures are scratch temp-dir roots (--state/--root overrides);
# the real runtime docs/ai/STATE.yaml is NEVER read or written. bash 3.2
# compatible (no associative arrays, no `${var^^}`).
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -uo pipefail

TEST_NAME="aai-hitl-propagation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISPATCH="$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"
SKILL_HITL="$PROJECT_ROOT/.aai/SKILL_HITL.prompt.md"
ORCH_HITL="$PROJECT_ROOT/.aai/ORCHESTRATION_HITL.prompt.md"
DOCS_AUDIT="$PROJECT_ROOT/docs/ai/docs-audit.yaml"

TEST_DIR=""
FAILED=0

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
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$DISPATCH" ]] || log_skip "dispatch script not found: $DISPATCH"
  [[ -f "$STATE_CLI" ]] || log_skip "state.mjs not found: $STATE_CLI"
  [[ -f "$SKILL_HITL" ]] || { log_fail "SKILL_HITL prompt missing: $SKILL_HITL"; return; }
  [[ -f "$ORCH_HITL" ]] || { log_fail "ORCHESTRATION_HITL prompt missing: $ORCH_HITL"; return; }
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-hitl-prop-test.XXXXXX")"
}

# --- fixture builders (mirrors tests/skills/test-aai-orchestration-dispatch.sh) --

# mk_root <name> — an isolated repo root with TECHNOLOGY.md + WORKFLOW.md + a
# frozen spec present by default. Echoes the dir.
mk_root() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai" "$d/docs/specs" "$d/docs/issues" "$d/.aai/workflow"
  echo "# Workflow fixture" > "$d/.aai/workflow/WORKFLOW.md"
  echo "# Technology fixture" > "$d/docs/TECHNOLOGY.md"
  cat > "$d/docs/specs/SPEC-0001-fx.md" <<MD
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
  printf '%s' "$d"
}

# write_worktree_state <file> <recommendation> <user_decision> — the ONLY
# fixture knob TEST-010/011/012 need: a full valid STATE.yaml with the
# worktree block set from the two arguments, everything else a stable,
# rule-8-irrelevant default.
write_worktree_state() {
  local f="$1" wrec="$2" wdec="$3"
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
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: docs/specs/SPEC-0001-fx.md
implementation_strategy:
  selected: tdd
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
  (cd "$PROJECT_ROOT" && node "$DISPATCH" \
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
  ' "$1" "$2"
}

# --- TEST-001 (Spec-AC-01): all 9 mapping rows present -------------------------

test_001_all_rows_present() {
  log_info "Test: all 9 [HITL-1]..[HITL-9] mapping rows present in SKILL_HITL (TEST-001)..."
  local n missing=0
  for n in 1 2 3 4 5 6 7 8 9; do
    if [[ "$(grep -c "\[HITL-$n\]" "$SKILL_HITL")" -lt 1 ]]; then
      log_fail "TEST-001: [HITL-$n] not found in $SKILL_HITL"
      missing=1
    fi
  done
  [[ "$missing" == 0 ]] && log_pass "All 9 trigger tokens present (TEST-001)"
}

# --- TEST-002 (Spec-AC-01): rows 7/8/9 name literal commands, 1-6 name none ----

test_002_rows_name_targets() {
  log_info "Test: rows 1-6 name 'none', rows 7/8/9 name the literal typed commands (TEST-002)..."
  local n
  for n in 1 2 3 4 5 6; do
    grep -E "^\| \`\[HITL-$n\]\`.*\| none \|$" "$SKILL_HITL" >/dev/null \
      || log_fail "TEST-002: [HITL-$n] mapping row does not end in a literal 'none' target"
  done
  grep -F '`node .aai/scripts/state.mjs set-worktree --user-decision' "$SKILL_HITL" >/dev/null \
    || log_fail "TEST-002: [HITL-7] row missing literal set-worktree --user-decision command"
  grep -F '`node .aai/scripts/state.mjs set-code-review --scope' "$SKILL_HITL" >/dev/null \
    || log_fail "TEST-002: [HITL-8] row missing literal set-code-review --scope command"
  grep -F '`node .aai/scripts/state.mjs set-code-review --status waived`' "$SKILL_HITL" >/dev/null \
    || log_fail "TEST-002: [HITL-9] row missing literal set-code-review --status waived command"
  grep -F '`node .aai/scripts/state.mjs set-code-review --status fail`' "$SKILL_HITL" >/dev/null \
    || log_fail "TEST-002: [HITL-9] row missing literal set-code-review --status fail command"
  [[ "$FAILED" == 0 ]] && log_pass "Rows 1-6 -> none, rows 7/8/9 -> literal typed commands (TEST-002)" \
    || true
}

# --- TEST-003 (Spec-AC-02): absolute prohibition sentences GONE ---------------

test_003_prohibition_gone() {
  log_info "Test: the old absolute-prohibition sentences are GONE (the observed RED) (TEST-003)..."
  local c1 c2
  c1="$(grep -c 'Do NOT modify any STATE.yaml field other than' "$SKILL_HITL")"
  c2="$(grep -c 'Do NOT change any other fields\.' "$SKILL_HITL")"
  [[ "$c1" == 0 ]] || log_fail "TEST-003: STRICT RULES absolute prohibition still present ($c1 hits)"
  [[ "$c2" == 0 ]] || log_fail "TEST-003: STEP 5 'Do NOT change any other fields.' still present ($c2 hits)"
  [[ "$c1" == 0 && "$c2" == 0 ]] && log_pass "Old absolute-prohibition sentences are gone (TEST-003)"
}

# --- TEST-004 (Spec-AC-02): narrowed guardrail wording present -----------------

test_004_narrowed_guardrail() {
  log_info "Test: narrowed guardrail wording present (TEST-004)..."
  grep -q 'ONE declared target field' "$SKILL_HITL" || log_fail "TEST-004: missing 'ONE declared target field'"
  grep -q 'via the typed' "$SKILL_HITL" || log_fail "TEST-004: missing 'via the typed'"
  grep -q 'nothing else' "$SKILL_HITL" || log_fail "TEST-004: missing 'nothing else'"
  if grep -q 'ONE declared target field' "$SKILL_HITL" \
    && grep -q 'via the typed' "$SKILL_HITL" \
    && grep -q 'nothing else' "$SKILL_HITL"; then
    log_pass "Narrowed guardrail wording present (TEST-004)"
  fi
}

# --- TEST-005 (Spec-AC-02): write-ordering rule present -------------------------

test_005_write_ordering() {
  log_info "Test: write-ordering rule (setter BEFORE clearing human_input) present (TEST-005)..."
  grep -q 'BEFORE clearing' "$SKILL_HITL" && log_pass "Write-ordering rule present (TEST-005)" \
    || log_fail "TEST-005: no 'BEFORE clearing' write-ordering wording found"
}

# --- TEST-006 (Spec-AC-03): normalization synonyms present ---------------------

test_006_normalization_present() {
  log_info "Test: normalization synonyms present for worktree/inline/waived and waive/fix (TEST-006)..."
  grep -q '`worktree`' "$SKILL_HITL" || log_fail "TEST-006: missing worktree enum in normalization table"
  grep -q '`inline`' "$SKILL_HITL" || log_fail "TEST-006: missing inline enum in normalization table"
  grep -q '`waived`' "$SKILL_HITL" || log_fail "TEST-006: missing waived enum in normalization table"
  grep -qE '\`fix\`|"fix them"' "$SKILL_HITL" || log_fail "TEST-006: missing fix/remediate synonym"
  grep -qE '\`waive\`|"accept"' "$SKILL_HITL" || log_fail "TEST-006: missing waive/accept synonym"
  if grep -q '`worktree`' "$SKILL_HITL" && grep -q '`inline`' "$SKILL_HITL" && grep -q '`waived`' "$SKILL_HITL" \
    && grep -qE '\`fix\`|"fix them"' "$SKILL_HITL" && grep -qE '\`waive\`|"accept"' "$SKILL_HITL"; then
    log_pass "Normalization synonyms present (TEST-006)"
  fi
}

# --- TEST-007 (Spec-AC-03): fail-closed trio present ----------------------------

test_007_fail_closed_trio() {
  log_info "Test: fail-closed trio -- no guess, human_input.required stays true, HITL UNRESOLVED (TEST-007)..."
  grep -qi 'UNMAPPABLE' "$SKILL_HITL" || log_fail "TEST-007: missing UNMAPPABLE wording"
  grep -q 'MUST NOT guess' "$SKILL_HITL" || log_fail "TEST-007: missing 'MUST NOT guess'"
  grep -q 'human_input.required: true' "$SKILL_HITL" || log_fail "TEST-007: missing 'human_input.required: true' fail-closed obligation"
  grep -q 'HITL UNRESOLVED' "$SKILL_HITL" || log_fail "TEST-007: missing 'HITL UNRESOLVED' exit wording"
  if grep -qi 'UNMAPPABLE' "$SKILL_HITL" && grep -q 'MUST NOT guess' "$SKILL_HITL" \
    && grep -q 'human_input.required: true' "$SKILL_HITL" && grep -q 'HITL UNRESOLVED' "$SKILL_HITL"; then
    log_pass "Fail-closed trio present (TEST-007)"
  fi
}

# --- TEST-008 (Spec-AC-04): ORCHESTRATION_HITL stamps the token ----------------

test_008_raise_side_stamps_token() {
  log_info "Test: ORCHESTRATION_HITL stamps [HITL-<n>] into blocking_reason on raise (TEST-008)..."
  grep -q '\[HITL-<n>\]' "$ORCH_HITL" || { log_fail "TEST-008: no [HITL-<n>] token declaration in $ORCH_HITL"; return; }
  grep -q 'blocking_reason' "$ORCH_HITL" || { log_fail "TEST-008: no blocking_reason mention in $ORCH_HITL"; return; }
  # The declaration must live in/near the STATE WRITEBACK section and mention
  # the prefix obligation explicitly.
  grep -qi 'prefixed' "$ORCH_HITL" || { log_fail "TEST-008: no 'prefixed' obligation wording in $ORCH_HITL"; return; }
  # Every individual trigger line 1-9 also carries its own literal token.
  local n missing=0
  for n in 1 2 3 4 5 6 7 8 9; do
    grep -q "\[HITL-$n\]" "$ORCH_HITL" || { log_fail "TEST-008: trigger $n missing its [HITL-$n] token in $ORCH_HITL"; missing=1; }
  done
  [[ "$missing" == 0 ]] && log_pass "ORCHESTRATION_HITL stamps [HITL-<n>] into blocking_reason (TEST-008)"
}

# --- TEST-009 (Spec-AC-04): SKILL_HITL reads the token, fails closed ----------

test_009_resolve_side_reads_token() {
  log_info "Test: SKILL_HITL declares it reads the [HITL-<n>] token and fails closed when ambiguous (TEST-009)..."
  grep -q '\[HITL-<n>\]' "$SKILL_HITL" || { log_fail "TEST-009: no [HITL-<n>] token-reading declaration in $SKILL_HITL"; return; }
  grep -qi 'fail closed' "$SKILL_HITL" || { log_fail "TEST-009: no 'fail closed' wording in $SKILL_HITL"; return; }
  grep -qi 'ambiguous\|unambiguous' "$SKILL_HITL" || { log_fail "TEST-009: no ambiguity-handling wording in $SKILL_HITL"; return; }
  log_pass "SKILL_HITL declares it reads the token and fails closed on ambiguity (TEST-009)"
}

# --- TEST-010 (Spec-AC-05, CONTROL): recommended+undecided -> rule 8 fires ----

test_010_control_rule8_fires_on_undecided() {
  log_info "Test [CONTROL]: recommendation=recommended, user_decision=undecided -> dispatch rule 8 (TEST-010)..."
  local d
  d="$(mk_root t10)"
  write_worktree_state "$d/docs/ai/STATE.yaml" recommended undecided
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || { log_fail "TEST-010: dispatch must exit 0 (got $EC): $(cat "$OUT" "$ERR")"; return; }
  jassert "$OUT" 'o.verdict === "dispatch" && o.rule === "8"' \
    || { log_fail "TEST-010: expected rule 8 dispatch, got $(cat "$OUT")"; return; }
  log_pass "CONTROL: undecided fixture dispatches rule 8 (TEST-010)"
}

# --- TEST-011 (Spec-AC-05, CONTROL): recommended+inline -> rule 8 does NOT fire

test_011_control_rule8_silent_on_inline() {
  log_info "Test [CONTROL]: recommendation=recommended, user_decision=inline -> rule 8 does NOT fire (TEST-011)..."
  local d
  d="$(mk_root t11)"
  write_worktree_state "$d/docs/ai/STATE.yaml" recommended inline
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || { log_fail "TEST-011: dispatch must exit 0 (got $EC): $(cat "$OUT" "$ERR")"; return; }
  jassert "$OUT" 'o.rule !== "8"' \
    || { log_fail "TEST-011: rule 8 must NOT fire once user_decision=inline, got $(cat "$OUT")"; return; }
  log_pass "CONTROL: inline fixture never dispatches rule 8 (TEST-011)"
}

# --- TEST-012 (Spec-AC-05, SEAM 1): declared [HITL-7] command flips the gate ---

test_012_seam_command_flips_gate() {
  log_info "Test [SEAM]: extract [HITL-7] command from SKILL_HITL, run it, re-dispatch -> rule 8 stops firing (TEST-012)..."
  local d cmd_line cmd_template cmd
  d="$(mk_root t12)"
  write_worktree_state "$d/docs/ai/STATE.yaml" recommended undecided

  # Confirm the gate is live BEFORE applying the extracted command (the
  # baseline this test's flip must be measured against).
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || { log_fail "TEST-012: baseline dispatch must exit 0 (got $EC): $(cat "$OUT" "$ERR")"; return; }
  jassert "$OUT" 'o.rule === "8"' \
    || { log_fail "TEST-012: baseline fixture must dispatch rule 8 before the flip, got $(cat "$OUT")"; return; }

  # EXTRACT the literal command text from the [HITL-7] mapping row -- not a
  # hand-written duplicate. This is the seam: prompt-declared string -> real
  # CLI -> real dispatch verdict.
  cmd_line="$(grep '\[HITL-7\]' "$SKILL_HITL" | grep 'state.mjs set-worktree')"
  [[ -n "$cmd_line" ]] || { log_fail "TEST-012: could not find a [HITL-7] set-worktree row in $SKILL_HITL"; return; }
  cmd_template="$(printf '%s' "$cmd_line" | grep -oE 'node \.aai/scripts/state\.mjs[^`]*')"
  [[ -n "$cmd_template" ]] || { log_fail "TEST-012: could not extract the state.mjs command from: $cmd_line"; return; }

  # Normalize: substitute the enum placeholder with "inline" (an accepted
  # TEST-006 synonym target), unescape the markdown-escaped pipe.
  cmd="$(printf '%s' "$cmd_template" | sed 's/<[^>]*>/inline/' | sed 's/\\|/|/g')"
  case "$cmd" in
    "node .aai/scripts/state.mjs set-worktree --user-decision inline") ;;
    *) log_fail "TEST-012: normalized command has an unexpected shape: $cmd"; return ;;
  esac

  # RUN the extracted command for real against the fixture STATE (--state
  # override; the real runtime docs/ai/STATE.yaml is never touched).
  local apply_out="$d/apply.log" apply_ec=0
  (cd "$PROJECT_ROOT" && eval "$cmd --state \"$d/docs/ai/STATE.yaml\"" > "$apply_out" 2>&1) || apply_ec=$?
  [[ "$apply_ec" == 0 ]] || { log_fail "TEST-012: extracted command failed (exit $apply_ec): $(cat "$apply_out")"; return; }
  grep -q 'user_decision: inline' "$d/docs/ai/STATE.yaml" \
    || { log_fail "TEST-012: STATE.yaml worktree.user_decision was not flipped to inline"; return; }

  # RE-DISPATCH: the other side of the seam -- rule 8 must no longer match.
  run_dispatch "$d"
  [[ "$EC" == 0 ]] || { log_fail "TEST-012: post-flip dispatch must exit 0 (got $EC): $(cat "$OUT" "$ERR")"; return; }
  jassert "$OUT" 'o.rule !== "8"' \
    || { log_fail "TEST-012: rule 8 still fires after applying the declared [HITL-7] command, got $(cat "$OUT")"; return; }
  log_pass "SEAM: prompt-declared [HITL-7] command -> state.mjs -> dispatch verdict, rule 8 stops firing (TEST-012)"
}

# --- TEST-014 (Spec-AC-07): no protected_paths_l3 path touched -----------------

test_014_no_protected_path_touched() {
  log_info "Test: branch diff touches no protected_paths_l3 path (TEST-014)..."
  [[ -f "$DOCS_AUDIT" ]] || { log_fail "TEST-014: $DOCS_AUDIT not found"; return; }
  local protected changed hit
  protected="$(sed -n 's/^  - //p' "$DOCS_AUDIT" | head -8)"
  [[ -n "$protected" ]] || { log_fail "TEST-014: no protected_paths_l3 entries extracted from $DOCS_AUDIT"; return; }

  # Covers BOTH shapes: committed history (git diff --name-only main...HEAD,
  # the spec's standalone verification form) AND the still-uncommitted
  # working tree (this scope is mid-TDD and has not committed yet, per the
  # role's constraints) -- staged, unstaged, and untracked files alike.
  changed="$( (cd "$PROJECT_ROOT" && {
    git diff --name-only main...HEAD 2>/dev/null
    git status --porcelain 2>/dev/null | sed -E 's/^...//'
  }) | sort -u)"

  hit="$(printf '%s\n' "$changed" | grep -x -F -f <(printf '%s\n' "$protected") || true)"
  if [[ -n "$hit" ]]; then
    log_fail "TEST-014: branch diff touches protected_paths_l3 path(s): $hit"
  else
    log_pass "TEST-014: no protected_paths_l3 path touched by this branch"
  fi
}

# --- TEST-015 (Spec-AC-07): pre-existing dispatch + state suites stay green ---

test_015_existing_suites_green() {
  log_info "Test: pre-existing dispatch + state suites stay green (TEST-015)..."
  local dispatch_suite="$SCRIPT_DIR/test-aai-orchestration-dispatch.sh"
  local state_suite="$SCRIPT_DIR/test-aai-state.sh"
  local ec1=0 ec2=0
  local log1="$TEST_DIR/dispatch-suite.log" log2="$TEST_DIR/state-suite.log"
  if [[ -f "$dispatch_suite" ]]; then
    bash "$dispatch_suite" > "$log1" 2>&1 || ec1=$?
  else
    log_fail "TEST-015: $dispatch_suite not found"
    return
  fi
  if [[ -f "$state_suite" ]]; then
    bash "$state_suite" > "$log2" 2>&1 || ec2=$?
  else
    log_fail "TEST-015: $state_suite not found"
    return
  fi
  # 0 pass, 42 skip (missing optional deps) are both acceptable; only a hard
  # failure (any other exit) breaks this control.
  if [[ "$ec1" != 0 && "$ec1" != 42 ]]; then
    log_fail "TEST-015: test-aai-orchestration-dispatch.sh exited $ec1: $(tail -n 20 "$log1")"
  fi
  if [[ "$ec2" != 0 && "$ec2" != 42 ]]; then
    log_fail "TEST-015: test-aai-state.sh exited $ec2: $(tail -n 20 "$log2")"
  fi
  if [[ ( "$ec1" == 0 || "$ec1" == 42 ) && ( "$ec2" == 0 || "$ec2" == 42 ) ]]; then
    log_pass "TEST-015: dispatch (exit $ec1) + state (exit $ec2) suites stay green"
  fi
}

# --- run ------------------------------------------------------------------------

check_deps
setup_fixture

test_001_all_rows_present
test_002_rows_name_targets
test_003_prohibition_gone
test_004_narrowed_guardrail
test_005_write_ordering
test_006_normalization_present
test_007_fail_closed_trio
test_008_raise_side_stamps_token
test_009_resolve_side_reads_token
test_010_control_rule8_fires_on_undecided
test_011_control_rule8_silent_on_inline
test_012_seam_command_flips_gate
test_014_no_protected_path_touched
test_015_existing_suites_green

if [[ "$FAILED" == 0 ]]; then
  echo "PASS: all aai-hitl-propagation tests (TEST-001..012, 014, 015)"
  exit 0
else
  echo "FAIL: aai-hitl-propagation suite had failures" >&2
  exit 1
fi
