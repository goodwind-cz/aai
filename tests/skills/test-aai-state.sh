#!/usr/bin/env bash
#
# Test: aai-state transactional STATE CLI (CHANGE-0006 / SPEC-0012)
# Verifies .aai/scripts/state.mjs — the structural line-edit STATE.yaml engine
# (atomic tmp+rename write, duplicate-key refusal, closed-set enums, reset-block
# guards, log-tick JSONL append) — plus the nine-prompt migration wiring and the
# implementer AC-table reconciliation gate (D8). TEST-001..020 per SPEC-0012;
# TEST-021..025 per the review-20260704T093742Z W1-W5 hardening remediation.
#
# ALL fixtures are scratch temp-dir copies (--state/--ticks overrides); the real
# gitignored runtime files are NEVER touched (CHANGE-0006 constraint).
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-state"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_SCRIPT="$PROJECT_ROOT/.aai/scripts/state.mjs"
CORE_LIB="$PROJECT_ROOT/.aai/scripts/lib/state-core.mjs"
CHECK_SCRIPT="$PROJECT_ROOT/.aai/scripts/check-state.mjs"
AUDIT_SCRIPT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"

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
  [[ -f "$STATE_SCRIPT" ]] || log_fail "state CLI not found: $STATE_SCRIPT"
  [[ -f "$CORE_LIB" ]] || log_fail "shared core lib not found: $CORE_LIB"
  [[ -f "$CHECK_SCRIPT" ]] || log_fail "check-state script not found: $CHECK_SCRIPT"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-state-test.XXXXXX")"
}

NOW_UTC=""
capture_now() { NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; }

# st <state-file> <logfile> <cli-args...>  — run state.mjs against a fixture.
st() {
  local s="$1" lg="$2"
  shift 2
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" "$@" > "$lg" 2>&1)
}

# ck <state-file> <logfile> — check-state must exit 0.
ck() {
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$1" > "$2" 2>&1)
}

# Canonical full fixture STATE mirroring the real schema (incl. the commented
# schema header whose `#   updated_at_utc:` line is the CHANGE-0005 regex trap).
# Args: $1 = path, $2 = last_validation.status (default not_run),
#       $3 = code_review.status (default not_run)
write_state_fixture() {
  local f="$1" vstatus="${2:-not_run}" rstatus="${3:-not_run}"
  cat > "$f" <<YAML
# docs/ai/STATE.yaml - AAI runtime state (managed by orchestration; humans need not edit)
#
# CANONICAL SCHEMA / INVARIANTS (authoritative; see .aai/SKILL_CHECK_STATE.prompt.md)
#   project_status:            active | paused
#   current_focus.type:        intake_change | intake_issue | ... | none
#   active_work_items[].status: planned | in_progress | blocked | done
#   active_work_items[].phase:  planning | preparation | implementation | validation |
#                              code_review | remediation
#   implementation_strategy.selected: loop | tdd | hybrid | undecided
#   worktree.recommendation:   not_needed | optional | recommended | required
#   worktree.user_decision:    undecided | worktree | inline | waived
#   code_review.status:        not_run | pass | fail | waived
#   last_validation.status:    pass | fail | not_run
#   updated_at_utc:            ISO 8601 UTC
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
  spec_path: docs/specs/SPEC-0001-fixture.md

active_work_items:
  - ref_id: CHANGE-0001
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: docs/specs/SPEC-0001-fixture.md

implementation_strategy:
  selected: hybrid
  source: docs/specs/SPEC-0001-fixture.md
  rationale: >-
    Fixture strategy rationale.

worktree:
  recommendation: recommended
  user_decision: worktree
  base_ref: main
  branch: feat/fixture
  path: /tmp/fixture-worktree
  inline_review_scope: null
  rationale: >-
    Fixture worktree rationale.

code_review:
  required: true
  status: $rstatus
  scope: >-
    fixture review scope
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null

last_validation:
  status: $vstatus
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: CHANGE-0001/SPEC-0001
  evidence_paths:
    - docs/ai/tdd/green-fixture.log
  notes: >-
    Fixture validation notes.

human_input:
  required: false
  question: null

locks:
  implementation: false

orchestration:
  mode: single
  k: 1

metrics:
  work_items:
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-test
          note: fixture-run-1
          started_utc: 2026-07-01T00:00:00Z
          ended_utc: 2026-07-01T00:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null

tdd_cycle:
  status: IDLE
  test_id: null
  spec_path: null
  test_path: null
  evidence:
    red: null
    green: null
    refactor: null

updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# Minimal init-less STATE (full-happy-path e2e fixture — LEARNED/RFC-0006
# fixture diversity: the CLI must scaffold every missing block itself).
write_minimal_state() {
  cat > "$1" <<'YAML'
project_status: active
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# STATE that is ALREADY corrupt: duplicate top-level `metrics:` key.
write_dup_metrics_state() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: none
  ref_id: null
last_validation:
  status: not_run
metrics:
  work_items:
    ISSUE-X:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-test
          note: run-r1
metrics:
  work_items:
    ISSUE-X:
      agent_runs:
        - role: Implementation
          model_id: claude-test
          note: run-r2
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# STATE with an entry auto-initialized as inline `agent_runs: []` (ISSUE-0004 /
# Codex P2 degenerate shape).
write_inline_runs_state() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0003
  primary_path: docs/issues/CHANGE-0003.md
last_validation:
  status: not_run
metrics:
  work_items:
    CHANGE-0003:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs: []
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# Print a file without one top-level block and without the top-level
# updated_at_utc line (comment lines outside blocks are preserved) — used to
# assert a mutation touched ONLY its target block + updated_at_utc (TEST-020).
strip_block() {
  awk -v key="$2" '
    /^[A-Za-z_][A-Za-z0-9_-]*:/ {
      if (index($0, key ":") == 1) { inblk = 1 } else { inblk = 0 }
    }
    inblk { next }
    /^updated_at_utc:/ { next }
    { print }
  ' "$1"
}

# ---------------------------------------------------------------------------

test_001_happy_focus_phase() {  # TEST-001 / Spec-AC-01
  log_info "Test: set-focus + set-phase happy path; header comments intact; REAL updated_at_utc bumped (TEST-001)..."
  local s="$TEST_DIR/t1-state.yaml"
  write_state_fixture "$s"
  grep '^#' "$s" > "$TEST_DIR/t1-header-before.txt"

  st "$s" "$TEST_DIR/t1a.log" set-focus --type intake_issue --ref ISSUE-0042 --path docs/issues/ISSUE-0042.md \
    || log_fail "set-focus happy path must exit 0: $(cat "$TEST_DIR/t1a.log")"
  ck "$s" "$TEST_DIR/t1a-ck.log" || log_fail "check-state must exit 0 after set-focus: $(cat "$TEST_DIR/t1a-ck.log")"

  st "$s" "$TEST_DIR/t1b.log" set-phase --ref ISSUE-0042 --phase planning --status in_progress --path docs/issues/ISSUE-0042.md \
    || log_fail "set-phase happy path must exit 0: $(cat "$TEST_DIR/t1b.log")"
  ck "$s" "$TEST_DIR/t1b-ck.log" || log_fail "check-state must exit 0 after set-phase: $(cat "$TEST_DIR/t1b-ck.log")"

  grep -qE '^  ref_id: ISSUE-0042$' "$s" || log_fail "current_focus.ref_id must be ISSUE-0042"
  grep -qE '^  - ref_id: ISSUE-0042$' "$s" || log_fail "active_work_items must carry the upserted ISSUE-0042 entry"
  grep -qE '^    phase: planning$' "$s" || log_fail "upserted item must carry phase: planning"

  # Commented schema header byte-identical (incl. the `#   updated_at_utc:` trap line).
  grep '^#' "$s" > "$TEST_DIR/t1-header-after.txt"
  cmp -s "$TEST_DIR/t1-header-before.txt" "$TEST_DIR/t1-header-after.txt" \
    || log_fail "commented schema header must stay byte-identical (CHANGE-0005 regex-mishap class)"
  grep -qF '#   updated_at_utc:            ISO 8601 UTC' "$s" \
    || log_fail "the commented updated_at_utc schema line must survive untouched"

  # The REAL top-level field was bumped (no longer the fixture timestamp).
  grep -qE '^updated_at_utc: 2026-07-01T00:00:00Z$' "$s" \
    && log_fail "real top-level updated_at_utc must be bumped by the mutation"
  grep -cE '^updated_at_utc: ' "$s" | grep -qx '1' || log_fail "exactly one real updated_at_utc line"
  log_pass "set-focus/set-phase mutate cleanly; header intact; real updated_at_utc bumped (TEST-001)"
}

test_002_table_driven_happy() {  # TEST-002 / Spec-AC-01
  log_info "Test: table-driven happy path over the remaining set-* subcommands + init-less e2e (TEST-002)..."
  local s="$TEST_DIR/t2-state.yaml"
  write_state_fixture "$s"

  # Each command: exit 0 and check-state exit 0 afterwards.
  st "$s" "$TEST_DIR/t2-1.log" set-validation --status pass --ref CHANGE-0001/SPEC-0001 --evidence tests/a.log --evidence tests/b.log --notes "fixture validation pass" \
    || log_fail "set-validation must exit 0: $(cat "$TEST_DIR/t2-1.log")"
  ck "$s" "$TEST_DIR/t2-1c.log" || log_fail "check-state after set-validation: $(cat "$TEST_DIR/t2-1c.log")"
  st "$s" "$TEST_DIR/t2-2.log" set-code-review --status not_run --required true --scope "src/ and tests/" --base-ref main --report docs/ai/reviews/r1.md --notes "queued" \
    || log_fail "set-code-review must exit 0: $(cat "$TEST_DIR/t2-2.log")"
  ck "$s" "$TEST_DIR/t2-2c.log" || log_fail "check-state after set-code-review: $(cat "$TEST_DIR/t2-2c.log")"
  st "$s" "$TEST_DIR/t2-3.log" set-strategy --selected tdd --source docs/specs/SPEC-0001-fixture.md --rationale "risky engine core" \
    || log_fail "set-strategy must exit 0: $(cat "$TEST_DIR/t2-3.log")"
  ck "$s" "$TEST_DIR/t2-3c.log" || log_fail "check-state after set-strategy: $(cat "$TEST_DIR/t2-3c.log")"
  st "$s" "$TEST_DIR/t2-4.log" set-worktree --recommendation optional --user-decision inline --inline-scope "src/a.mjs tests/a.sh" --rationale "small scope" \
    || log_fail "set-worktree must exit 0: $(cat "$TEST_DIR/t2-4.log")"
  ck "$s" "$TEST_DIR/t2-4c.log" || log_fail "check-state after set-worktree: $(cat "$TEST_DIR/t2-4c.log")"
  st "$s" "$TEST_DIR/t2-5.log" set-tdd-cycle --status RED --test-id TEST-001 --spec-path docs/specs/SPEC-0001-fixture.md --test-path tests/skills/test-x.sh --red docs/ai/tdd/red-x.log \
    || log_fail "set-tdd-cycle RED must exit 0: $(cat "$TEST_DIR/t2-5.log")"
  ck "$s" "$TEST_DIR/t2-5c.log" || log_fail "check-state after set-tdd-cycle RED: $(cat "$TEST_DIR/t2-5c.log")"
  grep -qE '^  status: RED$' "$s" || log_fail "tdd_cycle.status must be RED"
  grep -qE '^    red: docs/ai/tdd/red-x.log$' "$s" || log_fail "tdd_cycle.evidence.red must be set"
  st "$s" "$TEST_DIR/t2-6.log" set-tdd-cycle --status IDLE \
    || log_fail "set-tdd-cycle IDLE must exit 0: $(cat "$TEST_DIR/t2-6.log")"
  ck "$s" "$TEST_DIR/t2-6c.log" || log_fail "check-state after set-tdd-cycle IDLE: $(cat "$TEST_DIR/t2-6c.log")"
  grep -qE '^  test_id: null$' "$s" || log_fail "IDLE must null tdd_cycle.test_id"
  grep -qE '^    red: null$' "$s" || log_fail "IDLE must null tdd_cycle.evidence.red"
  st "$s" "$TEST_DIR/t2-7.log" set-human-input --required true --question "Which option, A or B?" --reason "ambiguous AC" \
    || log_fail "set-human-input true must exit 0: $(cat "$TEST_DIR/t2-7.log")"
  ck "$s" "$TEST_DIR/t2-7c.log" || log_fail "check-state after set-human-input: $(cat "$TEST_DIR/t2-7c.log")"
  st "$s" "$TEST_DIR/t2-8.log" set-human-input --required false \
    || log_fail "set-human-input false must exit 0: $(cat "$TEST_DIR/t2-8.log")"
  ck "$s" "$TEST_DIR/t2-8c.log" || log_fail "check-state after set-human-input false: $(cat "$TEST_DIR/t2-8c.log")"

  # set-validation self-stamps run_at_utc from the system clock (not the fixture value).
  grep -qE '^  run_at_utc: 20[0-9]{2}-' "$s" || log_fail "set-validation must write an ISO run_at_utc"
  grep -qE '^  run_at_utc: 2026-07-01T00:00:00Z$' "$s" \
    && log_fail "run_at_utc must be SELF-STAMPED (fixture value must be replaced)"
  grep -qE '^    - tests/a.log$' "$s" || log_fail "evidence_paths must carry tests/a.log"
  grep -qE '^    - docs/ai/reviews/r1.md$' "$s" || log_fail "report_paths must carry the appended report"

  # Init-less full happy path: the CLI scaffolds every missing block itself.
  local m="$TEST_DIR/t2-min.yaml"
  write_minimal_state "$m"
  capture_now
  st "$m" "$TEST_DIR/t2-m1.log" set-focus --type intake_change --ref CHANGE-0002 --path docs/issues/CHANGE-0002.md \
    || log_fail "init-less set-focus must exit 0: $(cat "$TEST_DIR/t2-m1.log")"
  ck "$m" "$TEST_DIR/t2-m1c.log" || log_fail "check-state after init-less set-focus: $(cat "$TEST_DIR/t2-m1c.log")"
  st "$m" "$TEST_DIR/t2-m2.log" set-phase --ref CHANGE-0002 --phase implementation \
    || log_fail "init-less set-phase must exit 0: $(cat "$TEST_DIR/t2-m2.log")"
  ck "$m" "$TEST_DIR/t2-m2c.log" || log_fail "check-state after init-less set-phase: $(cat "$TEST_DIR/t2-m2c.log")"
  st "$m" "$TEST_DIR/t2-m3.log" set-strategy --selected loop \
    || log_fail "init-less set-strategy must exit 0: $(cat "$TEST_DIR/t2-m3.log")"
  ck "$m" "$TEST_DIR/t2-m3c.log" || log_fail "check-state after init-less set-strategy: $(cat "$TEST_DIR/t2-m3c.log")"
  st "$m" "$TEST_DIR/t2-m4.log" set-validation --status not_run \
    || log_fail "init-less set-validation must exit 0: $(cat "$TEST_DIR/t2-m4.log")"
  ck "$m" "$TEST_DIR/t2-m4c.log" || log_fail "check-state after init-less set-validation: $(cat "$TEST_DIR/t2-m4c.log")"
  st "$m" "$TEST_DIR/t2-m5.log" append-run --ref CHANGE-0002 --role Implementation --model claude-test --started "$NOW_UTC" \
    || log_fail "init-less append-run must exit 0: $(cat "$TEST_DIR/t2-m5.log")"
  ck "$m" "$TEST_DIR/t2-m5c.log" || log_fail "check-state after init-less append-run: $(cat "$TEST_DIR/t2-m5c.log")"
  st "$m" "$TEST_DIR/t2-m6.log" reset-block last_validation \
    || log_fail "idempotent reset-block on not_run must exit 0: $(cat "$TEST_DIR/t2-m6.log")"
  log_pass "All set-* subcommands green with check-state clean after each; init-less e2e scaffolds cleanly (TEST-002)"
}

test_003_invalid_enums() {  # TEST-003 / Spec-AC-02
  log_info "Test: invalid enum values exit 2 and leave the fixture byte-identical (TEST-003)..."
  local s="$TEST_DIR/t3-state.yaml"
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t3-snapshot.yaml"
  capture_now

  # cmd-args ... => expected exit 2, no write
  set -- \
    "set-validation --status maybe" \
    "set-phase --ref CHANGE-0001 --phase testing" \
    "set-worktree --recommendation always" \
    "set-focus --type bogus --ref CHANGE-0001 --path x.md" \
    "set-strategy --selected yolo" \
    "set-tdd-cycle --status ORANGE" \
    "set-human-input --required perhaps" \
    "set-code-review --status meh"
  local case_args ec
  for case_args in "$@"; do
    ec=0
    # shellcheck disable=SC2086
    st "$s" "$TEST_DIR/t3-case.log" $case_args || ec=$?
    [[ "$ec" == 2 ]] || log_fail "invalid enum ($case_args) must exit 2 (got $ec): $(cat "$TEST_DIR/t3-case.log")"
    cmp -s "$s" "$TEST_DIR/t3-snapshot.yaml" || log_fail "fixture must stay byte-identical after rejected input ($case_args)"
  done

  ec=0
  st "$s" "$TEST_DIR/t3-role.log" append-run --ref CHANGE-0001 --role Wizard --model m --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run with unknown role must exit 2 (got $ec)"
  cmp -s "$s" "$TEST_DIR/t3-snapshot.yaml" || log_fail "fixture must stay byte-identical after rejected role"
  log_pass "Closed-set enum validation rejects with exit 2 and never writes (TEST-003)"
}

test_004_degenerate_inputs() {  # TEST-004 / Spec-AC-02
  log_info "Test: unknown block / bad ref shape / missing flag / missing STATE each exit 2, no write (TEST-004)..."
  local s="$TEST_DIR/t4-state.yaml"
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t4-snapshot.yaml"
  capture_now
  local ec

  ec=0; st "$s" "$TEST_DIR/t4-1.log" reset-block metrics || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block metrics (unknown block) must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-2.log" append-run --ref nope --role Implementation --model m --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run --ref nope (bad ref shape) must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-3.log" set-validation || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-validation without --status must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-4.log" set-code-review || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-code-review without any flag must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-5.log" frobnicate --status pass || ec=$?
  [[ "$ec" == 2 ]] || log_fail "unknown subcommand must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-6.log" append-run --ref CHANGE-0001 --role Implementation --model m --started "not-a-timestamp" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run with malformed --started must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t4-7.log" append-run --ref CHANGE-0001 --role Implementation --model m --started "2099-01-01T00:00:00Z" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run with far-future --started must exit 2 (got $ec)"
  cmp -s "$s" "$TEST_DIR/t4-snapshot.yaml" || log_fail "fixture must stay byte-identical after all rejected inputs"

  # Missing STATE file.
  ec=0; st "$TEST_DIR/no-such-state.yaml" "$TEST_DIR/t4-8.log" set-validation --status pass || ec=$?
  [[ "$ec" == 2 ]] || log_fail "missing STATE file must exit 2 (got $ec)"
  [[ ! -f "$TEST_DIR/no-such-state.yaml" ]] || log_fail "missing STATE must not be created by a rejected command"

  # reset-block on a STATE with no such block instance.
  local m="$TEST_DIR/t4-min.yaml"
  write_minimal_state "$m"
  ec=0; st "$m" "$TEST_DIR/t4-9.log" reset-block code_review || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block on a missing block instance must exit 2 (got $ec)"
  log_pass "Degenerate inputs all refused with exit 2 and zero writes (TEST-004)"
}

test_005_crash_before_rename() {  # TEST-005 / Spec-AC-03
  log_info "Test: AAI_STATE_INJECT_CRASH=before-rename leaves STATE byte-identical (TEST-005)..."
  local s="$TEST_DIR/t5-state.yaml"
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t5-snapshot.yaml"

  local ec=0
  (cd "$PROJECT_ROOT" && AAI_STATE_INJECT_CRASH=before-rename node .aai/scripts/state.mjs --state "$s" set-validation --status pass > "$TEST_DIR/t5.log" 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "injected crash must make the process die non-zero"
  cmp -s "$s" "$TEST_DIR/t5-snapshot.yaml" \
    || log_fail "target STATE must be byte-identical after a crash before rename (atomicity)"
  ck "$s" "$TEST_DIR/t5-ck.log" || log_fail "check-state must still exit 0: $(cat "$TEST_DIR/t5-ck.log")"
  log_pass "Crash before rename: target untouched, validator clean (TEST-005)"
}

test_006_crash_during_write() {  # TEST-006 / Spec-AC-03
  log_info "Test: AAI_STATE_INJECT_CRASH=during-write never truncates the target; clean re-run succeeds (TEST-006)..."
  local s="$TEST_DIR/t6-state.yaml"
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t6-snapshot.yaml"

  local ec=0
  (cd "$PROJECT_ROOT" && AAI_STATE_INJECT_CRASH=during-write node .aai/scripts/state.mjs --state "$s" set-validation --status pass > "$TEST_DIR/t6.log" 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "injected crash must make the process die non-zero"
  cmp -s "$s" "$TEST_DIR/t6-snapshot.yaml" \
    || log_fail "target STATE must never be truncated/mutated by a crash during the tmp write"
  ck "$s" "$TEST_DIR/t6-ck.log" || log_fail "check-state must still exit 0: $(cat "$TEST_DIR/t6-ck.log")"

  # Re-run WITHOUT injection: mutation lands.
  st "$s" "$TEST_DIR/t6b.log" set-validation --status pass \
    || log_fail "clean re-run after the crash must exit 0: $(cat "$TEST_DIR/t6b.log")"
  grep -qE '^  status: pass$' "$s" || log_fail "clean re-run must apply the mutation"
  ck "$s" "$TEST_DIR/t6b-ck.log" || log_fail "check-state after clean re-run: $(cat "$TEST_DIR/t6b-ck.log")"
  log_pass "Crash during write: target intact; clean re-run applies the mutation (TEST-006)"
}

test_007_refuse_corrupt_state() {  # TEST-007 / Spec-AC-04
  log_info "Test: mutation on an ALREADY-corrupt STATE (dup metrics) refused exit 1, file untouched (TEST-007)..."
  local s="$TEST_DIR/t7-state.yaml"
  write_dup_metrics_state "$s"
  cp "$s" "$TEST_DIR/t7-snapshot.yaml"
  capture_now

  local ec=0
  st "$s" "$TEST_DIR/t7.log" set-validation --status pass || ec=$?
  [[ "$ec" == 1 ]] || log_fail "mutating an already-corrupt STATE must exit 1 (got $ec): $(cat "$TEST_DIR/t7.log")"
  grep -qF "check-state.mjs --repair" "$TEST_DIR/t7.log" \
    || log_fail "refusal message must point at check-state.mjs --repair: $(cat "$TEST_DIR/t7.log")"
  cmp -s "$s" "$TEST_DIR/t7-snapshot.yaml" || log_fail "corrupt STATE must be left untouched (never compounded)"

  ec=0
  st "$s" "$TEST_DIR/t7b.log" append-run --ref ISSUE-0001 --role Planning --model m --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 1 ]] || log_fail "append-run on corrupt STATE must also exit 1 (got $ec)"
  cmp -s "$s" "$TEST_DIR/t7-snapshot.yaml" || log_fail "corrupt STATE untouched after second refusal"
  log_pass "Integrity refusal: corrupt input never compounded, repair path named (TEST-007)"
}

test_008_lib_extraction_regression() {  # TEST-008 / Spec-AC-04
  log_info "Test: dup-key logic shared via lib/state-core.mjs; check-state suite green after extraction (TEST-008)..."
  grep -qF "lib/state-core.mjs" "$CHECK_SCRIPT" \
    || log_fail "check-state.mjs must import the shared lib/state-core.mjs (no logic fork)"
  grep -qF "lib/state-core.mjs" "$STATE_SCRIPT" \
    || log_fail "state.mjs must import the shared lib/state-core.mjs (no logic fork)"
  local ec=0
  (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-check-state.sh > "$TEST_DIR/t8.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "test-aai-check-state.sh must stay green after the lib extraction (got $ec): $(tail -5 "$TEST_DIR/t8.log")"
  log_pass "Shared duplicate-key definition; validator suite green post-extraction (TEST-008)"
}

test_009_inline_agent_runs_conversion() {  # TEST-009 / Spec-AC-11
  log_info "Test: append-run converts inline 'agent_runs: []' to block form with ONE nested key (TEST-009)..."
  local s="$TEST_DIR/t9-state.yaml"
  write_inline_runs_state "$s"
  capture_now

  st "$s" "$TEST_DIR/t9.log" append-run --ref CHANGE-0003 --role Validation --model claude-test --started "$NOW_UTC" --note "inline conversion run" \
    || log_fail "append-run into inline agent_runs: [] must exit 0: $(cat "$TEST_DIR/t9.log")"
  local ar_count
  ar_count="$(grep -cE '^ {6}agent_runs:' "$s" || true)"
  [[ "$ar_count" == "1" ]] || log_fail "exactly ONE nested agent_runs key after conversion (got $ar_count)"
  grep -qE '^ {6}agent_runs: \[\]' "$s" && log_fail "the inline [] form must be gone after conversion"
  grep -qE '^ {8}- role: Validation$' "$s" || log_fail "appended run entry must be present in block form"
  grep -qE '^ {10}model_id: claude-test$' "$s" || log_fail "run entry must carry model_id"
  grep -qE '^ {10}started_utc: ' "$s" || log_fail "run entry must carry started_utc"
  grep -qE '^ {10}ended_utc: ' "$s" || log_fail "run entry must carry ended_utc"
  grep -qE '^ {10}cost_usd: null$' "$s" || log_fail "run entry must carry cost_usd: null"
  ck "$s" "$TEST_DIR/t9-ck.log" || log_fail "check-state after inline conversion: $(cat "$TEST_DIR/t9-ck.log")"
  log_pass "Inline agent_runs: [] converted to block form, single nested key, entry complete (TEST-009)"
}

test_010_append_run_autoinit() {  # TEST-010 / Spec-AC-11
  log_info "Test: append-run auto-inits a missing metrics.work_items entry; self-stamped timing (TEST-010)..."
  local s="$TEST_DIR/t10-state.yaml"
  write_state_fixture "$s"
  capture_now

  st "$s" "$TEST_DIR/t10.log" append-run --ref ISSUE-0007 --role "TDD Implementation" --model claude-test --started "$NOW_UTC" --note "auto-init run" --tdd-tests 3 \
    || log_fail "append-run for an unknown ref must auto-init and exit 0: $(cat "$TEST_DIR/t10.log")"

  local mcount
  mcount="$(grep -cE '^metrics:' "$s" || true)"
  [[ "$mcount" == "1" ]] || log_fail "exactly ONE top-level metrics key (got $mcount)"
  grep -qE '^ {4}ISSUE-0007:$' "$s" || log_fail "missing auto-initialized work_items entry for ISSUE-0007"
  # human_time_minutes nulls scaffolded for the new entry.
  sed -n '/^    ISSUE-0007:$/,/^    [A-Za-z]/p' "$s" | grep -qE '^ {8}intake: null$' \
    || log_fail "auto-init must scaffold human_time_minutes.intake: null"
  sed -n '/^    ISSUE-0007:$/,/^    [A-Za-z]/p' "$s" | grep -qE '^ {8}reviews: null$' \
    || log_fail "auto-init must scaffold human_time_minutes.reviews: null"

  # Self-stamped ended_utc >= started; computed integer duration; cost null; tdd_tests carried.
  local started ended
  started="$(sed -n '/^    ISSUE-0007:$/,$p' "$s" | grep -m1 'started_utc:' | awk '{print $2}')"
  ended="$(sed -n '/^    ISSUE-0007:$/,$p' "$s" | grep -m1 'ended_utc:' | awk '{print $2}')"
  [[ "$started" == "$NOW_UTC" ]] || log_fail "started_utc must be the supplied value (got $started)"
  [[ ! "$ended" < "$started" ]] || log_fail "self-stamped ended_utc ($ended) must be >= started_utc ($started)"
  sed -n '/^    ISSUE-0007:$/,$p' "$s" | grep -qE '^ {10}duration_seconds: [0-9]+$' \
    || log_fail "duration_seconds must be a computed integer"
  sed -n '/^    ISSUE-0007:$/,$p' "$s" | grep -qE '^ {10}cost_usd: null$' \
    || log_fail "cost_usd must be null (auto-capture out of scope)"
  sed -n '/^    ISSUE-0007:$/,$p' "$s" | grep -qE '^ {10}tdd_tests: 3$' \
    || log_fail "tdd_tests must be carried when supplied"
  # Pre-existing entry untouched.
  grep -qF "fixture-run-1" "$s" || log_fail "pre-existing CHANGE-0001 run must survive"
  ck "$s" "$TEST_DIR/t10-ck.log" || log_fail "check-state after auto-init append: $(cat "$TEST_DIR/t10-ck.log")"
  log_pass "append-run auto-init + self-stamped clock timing + single metrics key (TEST-010)"
}

test_011_reset_block_guards() {  # TEST-011 / Spec-AC-08
  log_info "Test: reset-block guards — fail resets, not_run idempotent, pass refused without --force (TEST-011)..."
  local s="$TEST_DIR/t11-state.yaml"

  # fail -> not_run, reset marker appended to notes, audit history retained.
  write_state_fixture "$s" fail pass
  st "$s" "$TEST_DIR/t11-1.log" reset-block last_validation \
    || log_fail "reset-block on a fail block must exit 0: $(cat "$TEST_DIR/t11-1.log")"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: not_run$' \
    || log_fail "last_validation.status must be not_run after reset"
  grep -qF "reset by remediation" "$s" || log_fail "reset marker must be appended to notes"
  grep -qF "pending independent re-validation" "$s" || log_fail "reset marker must name the pending independent re-validation"
  grep -qE '^ {2}run_at_utc: 2026-07-01T00:00:00Z$' "$s" || log_fail "prior run_at_utc must be left as audit history"
  grep -qE '^    - docs/ai/tdd/green-fixture.log$' "$s" || log_fail "prior evidence_paths must be left as audit history"
  ck "$s" "$TEST_DIR/t11-1c.log" || log_fail "check-state after reset: $(cat "$TEST_DIR/t11-1c.log")"

  # already not_run -> idempotent no-op exit 0, NO file write.
  cp "$s" "$TEST_DIR/t11-snapshot.yaml"
  st "$s" "$TEST_DIR/t11-2.log" reset-block last_validation \
    || log_fail "reset-block on an already-not_run block must exit 0 (idempotent): $(cat "$TEST_DIR/t11-2.log")"
  cmp -s "$s" "$TEST_DIR/t11-snapshot.yaml" || log_fail "idempotent reset must not rewrite the file"

  # pass -> refused exit 2, no write; --force overrides.
  local p="$TEST_DIR/t11-pass.yaml"
  write_state_fixture "$p" pass fail
  cp "$p" "$TEST_DIR/t11-pass-snap.yaml"
  local ec=0
  st "$p" "$TEST_DIR/t11-3.log" reset-block last_validation || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block on a pass block must be REFUSED exit 2 without --force (got $ec)"
  cmp -s "$p" "$TEST_DIR/t11-pass-snap.yaml" || log_fail "refused reset must not write"
  st "$p" "$TEST_DIR/t11-4.log" reset-block last_validation --force \
    || log_fail "reset-block --force on a pass block must exit 0: $(cat "$TEST_DIR/t11-4.log")"
  sed -n '/^last_validation:/,/^[a-z]/p' "$p" | grep -qE '^ {2}status: not_run$' \
    || log_fail "--force must reset the pass block"

  # code_review fail -> not_run; required + report_paths untouched.
  st "$p" "$TEST_DIR/t11-5.log" reset-block code_review \
    || log_fail "reset-block code_review on fail must exit 0: $(cat "$TEST_DIR/t11-5.log")"
  sed -n '/^code_review:/,/^[a-z]/p' "$p" | grep -qE '^ {2}status: not_run$' \
    || log_fail "code_review.status must be not_run after reset"
  sed -n '/^code_review:/,/^[a-z]/p' "$p" | grep -qE '^ {2}required: true$' \
    || log_fail "code_review.required must be left untouched by the reset"
  ck "$p" "$TEST_DIR/t11-5c.log" || log_fail "check-state after code_review reset: $(cat "$TEST_DIR/t11-5c.log")"

  # waived -> refused without --force.
  local w="$TEST_DIR/t11-waived.yaml"
  write_state_fixture "$w" not_run waived
  ec=0
  st "$w" "$TEST_DIR/t11-6.log" reset-block code_review || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block on a waived review must be REFUSED exit 2 (got $ec)"
  log_pass "reset-block guard semantics correct across fail/not_run/pass/waived/--force (TEST-011)"
}

test_012_log_tick_schema() {  # TEST-012 / Spec-AC-10
  log_info "Test: log-tick emits schema-compatible LOOP_TICKS lines; append-only; no fabricated cost fields (TEST-012)..."
  local s="$TEST_DIR/t12-state.yaml" tk="$TEST_DIR/t12-ticks.jsonl"
  write_state_fixture "$s"
  capture_now

  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 3 --role "Validation" --scope "CHANGE-0001/SPEC-0001" --started "$NOW_UTC" \
      --exit-code 0 --focus-before CHANGE-0001 --validation-before fail --harness 2.1.199 \
      > "$TEST_DIR/t12.log" 2>&1) \
    || log_fail "log-tick must exit 0: $(cat "$TEST_DIR/t12.log")"
  [[ -f "$tk" ]] || log_fail "ticks file must be created"

  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
    if (lines.length !== 1) { console.error("expected exactly 1 line, got " + lines.length); process.exit(1); }
    const o = JSON.parse(lines[0]);
    const expect = (cond, msg) => { if (!cond) { console.error("schema: " + msg + " :: " + lines[0]); process.exit(1); } };
    expect(o.type === "tick", "type must default to tick");
    expect(o.tick === 3, "tick must be numeric 3");
    expect(o.role === "Validation", "role");
    expect(o.scope === "CHANGE-0001/SPEC-0001", "scope");
    expect(typeof o.started_utc === "string" && /Z$/.test(o.started_utc), "started_utc ISO");
    expect(typeof o.ended_utc === "string" && /Z$/.test(o.ended_utc), "ended_utc self-stamped ISO");
    expect(Number.isInteger(o.duration_seconds), "duration_seconds computed integer (never null)");
    expect(o.exit_code === 0, "exit_code");
    expect(o.focus_ref_id_before === "CHANGE-0001", "focus_ref_id_before from caller");
    expect(o.focus_ref_id_after === "CHANGE-0001", "focus_ref_id_after read from STATE");
    expect(o.validation_status_before === "fail", "validation_status_before from caller");
    expect(o.validation_status_after === "not_run", "validation_status_after read from STATE");
    expect(o.orchestration_mode === "single", "orchestration_mode from STATE");
    expect(o.orchestration_k === 1, "orchestration_k from STATE");
    expect(o.harness_version === "2.1.199", "harness_version");
    for (const k of ["input_tokens","output_tokens","cache_read_tokens","est_cost_usd","lingering_procs","free_memory"])
      expect(!(k in o), "must NOT fabricate optional field " + k);
    console.log("ok");
  ' "$tk" > "$TEST_DIR/t12-schema.log" 2>&1 || log_fail "tick line schema: $(cat "$TEST_DIR/t12-schema.log")"

  # Second call appends (never rewrites); --type recovery honored; optional fields only when flagged.
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 4 --role "Remediation" --scope "CHANGE-0001" --started "$NOW_UTC" --type recovery \
      --lingering-procs 0 > "$TEST_DIR/t12b.log" 2>&1) \
    || log_fail "second log-tick must exit 0: $(cat "$TEST_DIR/t12b.log")"
  local n
  n="$(wc -l < "$tk" | tr -d ' ')"
  [[ "$n" == "2" ]] || log_fail "two invocations must yield two lines (append-only), got $n"
  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
    const o = JSON.parse(lines[1]);
    if (o.type !== "recovery") { console.error("--type recovery not honored"); process.exit(1); }
    if (o.lingering_procs !== 0) { console.error("flagged lingering_procs must be emitted"); process.exit(1); }
    if ("input_tokens" in o) { console.error("unflagged token field fabricated"); process.exit(1); }
    console.log("ok");
  ' "$tk" > "$TEST_DIR/t12c.log" 2>&1 || log_fail "recovery line: $(cat "$TEST_DIR/t12c.log")"

  # STATE.yaml itself is NEVER touched by log-tick.
  grep -qE '^updated_at_utc: 2026-07-01T00:00:00Z$' "$s" || log_fail "log-tick must not bump STATE updated_at_utc"
  log_pass "log-tick schema-compatible, append-only, recovery type, clock-stamped, no fabricated usage (TEST-012)"
}

test_013_log_tick_timestamp_guards() {  # TEST-013 / Spec-AC-10
  log_info "Test: log-tick rejects malformed and >300s-future --started with exit 2, no append (TEST-013)..."
  local s="$TEST_DIR/t13-state.yaml" tk="$TEST_DIR/t13-ticks.jsonl"
  write_state_fixture "$s"
  local ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 1 --role r --scope CHANGE-0001 --started "not-a-date" > "$TEST_DIR/t13-1.log" 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "malformed --started must exit 2 (got $ec)"
  [[ ! -f "$tk" ]] || log_fail "nothing may be appended on a rejected timestamp"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
      --tick 1 --role r --scope CHANGE-0001 --started "2099-01-01T00:00:00Z" > "$TEST_DIR/t13-2.log" 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail ">300s-future --started must exit 2 (got $ec)"
  [[ ! -f "$tk" ]] || log_fail "nothing may be appended on a rejected future timestamp"
  log_pass "log-tick timestamp validation rejects with exit 2, zero appends (TEST-013)"
}

test_014_prompt_migration_wiring() {  # TEST-014 / Spec-AC-05
  log_info "Test: all nine prompts use state.mjs as primary path + grep-stable fallback marker (TEST-014)..."
  local p f
  for p in PLANNING IMPLEMENTATION VALIDATION REMEDIATION SKILL_TDD ORCHESTRATION ORCHESTRATION_PARALLEL METRICS_FLUSH SKILL_LOOP; do
    f="$PROJECT_ROOT/.aai/${p}.prompt.md"
    [[ -f "$f" ]] || log_fail "missing prompt $f"
    grep -qF "node .aai/scripts/state.mjs" "$f" \
      || log_fail "$p.prompt.md must reference node .aai/scripts/state.mjs as the primary STATE-mutation path"
    grep -qF "state.mjs is absent" "$f" \
      || log_fail "$p.prompt.md must carry the canonical fallback marker 'state.mjs is absent'"
    grep -qE 'sed -i[^|]*STATE\.yaml|node -e[^|]*STATE\.yaml' "$f" \
      && log_fail "$p.prompt.md must not instruct a raw sed/node -e STATE edit as primary path"
  done
  log_pass "Nine prompts migrated: state.mjs primary + 'state.mjs is absent' fallback everywhere (TEST-014)"
}

test_015_remediation_reset_wiring() {  # TEST-015 / Spec-AC-06
  log_info "Test: REMEDIATION closes via reset-block, forbids own verdict, drops self-run validation (TEST-015)..."
  local f="$PROJECT_ROOT/.aai/REMEDIATION.prompt.md"
  grep -qF "reset-block last_validation" "$f" \
    || log_fail "REMEDIATION must instruct reset-block last_validation"
  grep -qF "reset-block code_review" "$f" \
    || log_fail "REMEDIATION must instruct reset-block code_review"
  grep -qF "NEVER write your own validation/review verdict" "$f" \
    || log_fail "REMEDIATION must carry the verdict-prohibition sentence"
  grep -qF "Re-run validation" "$f" \
    && log_fail "REMEDIATION must no longer instruct the old self-run 'Re-run validation' closing step"
  log_pass "REMEDIATION reset-block wiring + verdict prohibition present, self-validation step gone (TEST-015)"
}

test_016_reset_routes_to_rule11() {  # TEST-016 / Spec-AC-07
  log_info "Test: reset-block last_validation clears the rule-10 input, leaves code_review untouched; ORCHESTRATION documents the reset routing (TEST-016)..."
  local s="$TEST_DIR/t16-state.yaml"
  write_state_fixture "$s" fail pass

  st "$s" "$TEST_DIR/t16.log" reset-block last_validation \
    || log_fail "reset-block on the fail fixture must exit 0: $(cat "$TEST_DIR/t16.log")"
  # Rule-10 input cleared, rule-11 inputs satisfied: validation not_run + implementation present.
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: not_run$' \
    || log_fail "last_validation.status must be not_run (rule-11 decision input)"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: fail$' \
    && log_fail "rule-10 input (fail) must be cleared"
  # code_review untouched by the validation reset.
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: pass$' \
    || log_fail "code_review must be untouched by reset-block last_validation"
  ck "$s" "$TEST_DIR/t16-ck.log" || log_fail "check-state after reset: $(cat "$TEST_DIR/t16-ck.log")"

  local f="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
  grep -qF "post-remediation reset" "$f" \
    || log_fail "ORCHESTRATION must document the post-remediation reset routing"
  grep -qF "reset-block" "$f" \
    || log_fail "ORCHESTRATION reset note must name reset-block"
  grep -qF "rule 11" "$f" || log_fail "ORCHESTRATION reset note must route to rule 11 (fresh Validation)"
  grep -qF "rule 13" "$f" || log_fail "ORCHESTRATION reset note must route to rule 13 (fresh Code Review)"
  log_pass "Post-remediation reset produces rule-11 inputs; ORCHESTRATION documents the routing (TEST-016)"
}

test_017_ac_reconciliation_wiring() {  # TEST-017 / Spec-AC-09
  log_info "Test: IMPLEMENTATION step 9b + SKILL_TDD Phase 4 carry the AC-table reconciliation + --gate self-check (TEST-017)..."
  local f
  for f in "$PROJECT_ROOT/.aai/IMPLEMENTATION.prompt.md" "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"; do
    grep -qF "Acceptance Criteria Status" "$f" \
      || log_fail "$f must instruct reconciling the Acceptance Criteria Status table"
    grep -qF "docs-audit.mjs --gate" "$f" \
      || log_fail "$f must include the docs-audit.mjs --gate self-check"
    grep -qF "exit 0 before reporting complete" "$f" \
      || log_fail "$f must require fixing until exit 0 before reporting complete"
  done
  log_pass "Pre-handoff AC reconciliation + gate self-check wired in both implementer prompts (TEST-017)"
}

test_018_gate_seam() {  # TEST-018 / Spec-AC-09 (SEAM-3)
  log_info "Test: implementer-side --gate catches an unreconciled AC table (exit 1) and passes a reconciled one (exit 0) (TEST-018)..."
  local d="$TEST_DIR/gate-repo"
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/specs" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  (cd "$d" && git init -q && git config user.email test@example.com && git config user.name "AAI Test")

  cat > "$d/docs/specs/SPEC-8801-unreconciled.md" <<'MD'
---
id: SPEC-8801
type: spec
status: implementing
links:
  pr: []
---
# Fixture spec handed off WITHOUT AC-table reconciliation

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | first       | planned | —        | —         | —     |
| Spec-AC-02 | second      | planned | —        | —         | —     |
MD
  cat > "$d/docs/specs/SPEC-8802-reconciled.md" <<'MD'
---
id: SPEC-8802
type: spec
status: implementing
links:
  pr: []
---
# Fixture spec handed off WITH a reconciled AC table

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
| Spec-AC-02 | second      | done   | run-log  | TDD       | —     |
MD

  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-8801 > gate-fail.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "unreconciled handoff must be caught implementer-side: --gate exit 1 (got $ec): $(cat "$d/gate-fail.log")"
  grep -qF "Spec-AC-01" "$d/gate-fail.log" || log_fail "gate output must name the violating row Spec-AC-01"
  grep -qF "non-terminal" "$d/gate-fail.log" || log_fail "gate output must name the non-terminal status"

  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-8802 > gate-pass.log 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "reconciled sibling fixture must pass: --gate exit 0 (got $ec): $(cat "$d/gate-pass.log")"
  log_pass "Gate seam crossed both directions: unreconciled caught exit 1, reconciled exit 0 (TEST-018)"
}

test_019_regression_anchor() {  # TEST-019 / Spec-AC-12
  log_info "Test: real-repo docs-audit CLEAN + generate-docs-index idempotent (TEST-019)..."
  local ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t19-audit.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "real-repo docs-audit --check --strict --no-event must exit 0 (got $ec): $(tail -10 "$TEST_DIR/t19-audit.log")"

  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/t19-idx1.log" 2>&1) \
    || log_fail "generate-docs-index run 1 must exit 0: $(cat "$TEST_DIR/t19-idx1.log")"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/t19-index-1.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/t19-idx2.log" 2>&1) \
    || log_fail "generate-docs-index run 2 must exit 0: $(cat "$TEST_DIR/t19-idx2.log")"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/t19-index-2.md"
  cmp -s "$TEST_DIR/t19-index-1.md" "$TEST_DIR/t19-index-2.md" \
    || log_fail "generate-docs-index must be idempotent (two runs byte-identical modulo Generated:)"
  log_pass "Real-repo audit CLEAN and index idempotent (TEST-019)"
}

test_020_diff_locality() {  # TEST-020 / Spec-AC-01
  log_info "Test: each mutation touches ONLY its target block + updated_at_utc; comments/key order preserved (TEST-020)..."
  local s="$TEST_DIR/t20-state.yaml" before="$TEST_DIR/t20-before.yaml"
  capture_now

  # (a) set-validation → only last_validation + updated_at_utc may change.
  write_state_fixture "$s"
  cp "$s" "$before"
  st "$s" "$TEST_DIR/t20-1.log" set-validation --status pass --notes "locality check" \
    || log_fail "set-validation must exit 0"
  strip_block "$before" last_validation > "$TEST_DIR/t20-a-before.txt"
  strip_block "$s" last_validation > "$TEST_DIR/t20-a-after.txt"
  cmp -s "$TEST_DIR/t20-a-before.txt" "$TEST_DIR/t20-a-after.txt" \
    || log_fail "set-validation leaked outside last_validation + updated_at_utc: $(diff "$TEST_DIR/t20-a-before.txt" "$TEST_DIR/t20-a-after.txt" | head -5)"

  # (b) set-worktree → only worktree + updated_at_utc.
  write_state_fixture "$s"
  cp "$s" "$before"
  st "$s" "$TEST_DIR/t20-2.log" set-worktree --user-decision inline \
    || log_fail "set-worktree must exit 0"
  strip_block "$before" worktree > "$TEST_DIR/t20-b-before.txt"
  strip_block "$s" worktree > "$TEST_DIR/t20-b-after.txt"
  cmp -s "$TEST_DIR/t20-b-before.txt" "$TEST_DIR/t20-b-after.txt" \
    || log_fail "set-worktree leaked outside worktree + updated_at_utc"

  # (c) append-run → only metrics + updated_at_utc.
  write_state_fixture "$s"
  cp "$s" "$before"
  st "$s" "$TEST_DIR/t20-3.log" append-run --ref CHANGE-0001 --role Remediation --model claude-test --started "$NOW_UTC" \
    || log_fail "append-run must exit 0"
  strip_block "$before" metrics > "$TEST_DIR/t20-c-before.txt"
  strip_block "$s" metrics > "$TEST_DIR/t20-c-after.txt"
  cmp -s "$TEST_DIR/t20-c-before.txt" "$TEST_DIR/t20-c-after.txt" \
    || log_fail "append-run leaked outside metrics + updated_at_utc"

  # Header comment block byte-identical and top-level key ORDER unchanged.
  grep '^#' "$before" > "$TEST_DIR/t20-hdr-before.txt"
  grep '^#' "$s" > "$TEST_DIR/t20-hdr-after.txt"
  cmp -s "$TEST_DIR/t20-hdr-before.txt" "$TEST_DIR/t20-hdr-after.txt" \
    || log_fail "header comment block must stay byte-identical"
  grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' "$before" | sed 's/:.*/:/' > "$TEST_DIR/t20-keys-before.txt"
  grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' "$s" | sed 's/:.*/:/' > "$TEST_DIR/t20-keys-after.txt"
  cmp -s "$TEST_DIR/t20-keys-before.txt" "$TEST_DIR/t20-keys-after.txt" \
    || log_fail "top-level key order must be preserved by construction"
  log_pass "Mutations are block-local; comments and key order preserved by construction (TEST-020)"
}

# Fixture whose last_validation notes use a chomping-variant block scalar
# ($2 = the block-scalar header, e.g. '|-' or '>+') — the W1 data-loss shape.
write_block_notes_state() {
  cat > "$1" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-fixture.md
last_validation:
  status: fail
  run_at_utc: 2026-07-01T00:00:00Z
  ref_id: CHANGE-0001/SPEC-0001
  notes: ${2}
    prior note line one
    prior note line two
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# Fixture whose target top-level block header carries an INLINE value
# ($2 = the metrics header line, e.g. 'metrics: {}') — the W2 corruption shape.
write_inline_header_state() {
  cat > "$1" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0009
  primary_path: docs/issues/CHANGE-0009.md
last_validation:
  status: not_run
${2}
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

test_021_reset_block_literal_notes() {  # TEST-021 / review W1
  log_info "Test: reset-block preserves prior notes under |- / >+ block-scalar headers (TEST-021)..."
  local hdr s
  for hdr in '|-' '>+' '|'; do
    s="$TEST_DIR/t21-state.yaml"
    write_block_notes_state "$s" "$hdr"
    st "$s" "$TEST_DIR/t21.log" reset-block last_validation \
      || log_fail "reset-block on a 'notes: $hdr' fixture must exit 0: $(cat "$TEST_DIR/t21.log")"
    grep -qF "prior note line one" "$s" \
      || log_fail "reset-block on 'notes: $hdr' must NOT delete prior note line one (audit history)"
    grep -qF "prior note line two" "$s" \
      || log_fail "reset-block on 'notes: $hdr' must NOT delete prior note line two (audit history)"
    grep -qF "reset by remediation" "$s" \
      || log_fail "reset marker must be appended to the 'notes: $hdr' block"
    grep -qF "notes: $hdr" "$s" \
      || log_fail "the existing block-scalar header 'notes: $hdr' must be kept (not rewritten)"
    # The marker must live INSIDE the scalar (indented deeper than the field).
    grep -qE '^    reset by remediation ' "$s" \
      || log_fail "reset marker must be appended as block-scalar content (4-space indent)"
    sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^  status: not_run$' \
      || log_fail "status must still be reset to not_run for 'notes: $hdr'"
    ck "$s" "$TEST_DIR/t21-ck.log" || log_fail "check-state after 'notes: $hdr' reset: $(cat "$TEST_DIR/t21-ck.log")"
  done
  log_pass "reset-block keeps prior |- / >+ / | note lines and appends the marker in-scalar (TEST-021)"
}

test_022_inline_header_refused() {  # TEST-022 / review W2
  log_info "Test: mutating under an inline-valued block header is REFUSED (never corrupts); validator catches the corrupt shape (TEST-022)..."
  local s="$TEST_DIR/t22-state.yaml" ec

  # (a) append-run into `metrics: {}` must refuse exit 1 and leave the file byte-identical.
  write_inline_header_state "$s" 'metrics: {}'
  cp "$s" "$TEST_DIR/t22-snap.yaml"
  capture_now
  ec=0
  st "$s" "$TEST_DIR/t22-1.log" append-run --ref CHANGE-0009 --role Remediation --model claude-test --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 1 ]] || log_fail "append-run under 'metrics: {}' must refuse exit 1, never splice (got $ec): $(cat "$TEST_DIR/t22-1.log")"
  grep -qi "inline" "$TEST_DIR/t22-1.log" || log_fail "refusal must explain the inline-header cause: $(cat "$TEST_DIR/t22-1.log")"
  cmp -s "$s" "$TEST_DIR/t22-snap.yaml" || log_fail "file must stay byte-identical after the inline-header refusal"

  # (b) non-empty inline mapping refused the same way.
  write_inline_header_state "$s" 'metrics: {placeholder: 1}'
  cp "$s" "$TEST_DIR/t22-snap2.yaml"
  ec=0
  st "$s" "$TEST_DIR/t22-2.log" append-run --ref CHANGE-0009 --role Remediation --model claude-test --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 1 ]] || log_fail "append-run under 'metrics: {placeholder: 1}' must refuse exit 1 (got $ec)"
  cmp -s "$s" "$TEST_DIR/t22-snap2.yaml" || log_fail "file must stay byte-identical after the non-empty inline refusal"

  # (c) same seam for a set-* block: current_focus with an inline value.
  cat > "$s" <<'YAML'
project_status: active
current_focus: {}
last_validation:
  status: not_run
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  cp "$s" "$TEST_DIR/t22-snap3.yaml"
  ec=0
  st "$s" "$TEST_DIR/t22-3.log" set-focus --type intake_change --ref CHANGE-0009 --path docs/issues/CHANGE-0009.md || ec=$?
  [[ "$ec" == 1 ]] || log_fail "set-focus under 'current_focus: {}' must refuse exit 1 (got $ec)"
  cmp -s "$s" "$TEST_DIR/t22-snap3.yaml" || log_fail "file must stay byte-identical after the set-focus refusal"

  # (d) the paired validator is no longer blind: a hand-corrupted
  # child-lines-under-inline-header file must FAIL check-state.
  cat > "$s" <<'YAML'
project_status: active
metrics: {}
  work_items:
    CHANGE-0009:
      agent_runs: []
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  ec=0
  ck "$s" "$TEST_DIR/t22-4.log" || ec=$?
  [[ "$ec" == 1 ]] || log_fail "check-state must exit 1 on child lines under an inline-valued header (got $ec): $(cat "$TEST_DIR/t22-4.log")"
  grep -qF "metrics" "$TEST_DIR/t22-4.log" || log_fail "validator must name the conflicting key: $(cat "$TEST_DIR/t22-4.log")"

  # (e) an inline header WITHOUT children stays valid YAML — validator still clean.
  write_inline_header_state "$s" 'metrics: {}'
  ck "$s" "$TEST_DIR/t22-5.log" || log_fail "check-state must stay exit 0 on a childless inline header: $(cat "$TEST_DIR/t22-5.log")"
  log_pass "Inline-valued block headers refused exit 1 by the writer and caught by the validator (TEST-022)"
}

test_023_scalar_quoting() {  # TEST-023 / review W3
  log_info "Test: hostile plain-scalar values are single-quoted (or rejected); safe values stay unquoted (TEST-023)..."
  local s="$TEST_DIR/t23-state.yaml" ec
  write_state_fixture "$s"
  capture_now

  # (a) `: ` inside a value — the reproduced W3 corruption.
  st "$s" "$TEST_DIR/t23-1.log" set-validation --status pass --ref "CHANGE-1: bad" \
    || log_fail "set-validation with a colon-bearing --ref must exit 0: $(cat "$TEST_DIR/t23-1.log")"
  grep -qF "  ref_id: 'CHANGE-1: bad'" "$s" \
    || log_fail "colon-bearing ref must be written single-quoted (got: $(grep '  ref_id:' "$s" | head -1))"
  ck "$s" "$TEST_DIR/t23-1c.log" || log_fail "check-state after quoted ref: $(cat "$TEST_DIR/t23-1c.log")"

  # (b) branch with `: ` + leading-quote model value.
  st "$s" "$TEST_DIR/t23-2.log" set-worktree --branch "fix: colon" --base-ref main \
    || log_fail "set-worktree with a colon-bearing --branch must exit 0: $(cat "$TEST_DIR/t23-2.log")"
  grep -qF "  branch: 'fix: colon'" "$s" || log_fail "colon-bearing branch must be single-quoted"
  grep -qE '^  base_ref: main$' "$s" || log_fail "safe values must stay UNQUOTED (minimal diffs)"
  st "$s" "$TEST_DIR/t23-3.log" append-run --ref CHANGE-0001 --role Remediation --model "'weird" --started "$NOW_UTC" \
    || log_fail "append-run with a leading-quote model must exit 0: $(cat "$TEST_DIR/t23-3.log")"
  grep -qF "model_id: '''weird'" "$s" \
    || log_fail "leading single quote must be escaped by doubling inside a quoted scalar"

  # (c) leading '#' and trailing ' #' comment-openers quoted.
  st "$s" "$TEST_DIR/t23-4.log" set-tdd-cycle --status RED --test-id "#5" --red "evidence #1.log" \
    || log_fail "set-tdd-cycle with #-bearing values must exit 0: $(cat "$TEST_DIR/t23-4.log")"
  grep -qF "  test_id: '#5'" "$s" || log_fail "leading-# value must be single-quoted"
  grep -qF "    red: 'evidence #1.log'" "$s" || log_fail "value containing ' #' must be single-quoted"
  ck "$s" "$TEST_DIR/t23-4c.log" || log_fail "check-state after quoted scalars: $(cat "$TEST_DIR/t23-4c.log")"

  # (d) a NEWLINE cannot be represented on a plain-scalar line: reject exit 2, no write.
  cp "$s" "$TEST_DIR/t23-snap.yaml"
  ec=0
  st "$s" "$TEST_DIR/t23-5.log" set-worktree --branch "$(printf 'a\nb')" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "newline-bearing scalar value must be rejected exit 2 (got $ec): $(cat "$TEST_DIR/t23-5.log")"
  cmp -s "$s" "$TEST_DIR/t23-snap.yaml" || log_fail "rejected newline value must not write"
  log_pass "Hostile plain scalars quoted/escaped, newlines rejected, safe values untouched (TEST-023)"
}

test_024_concurrent_guard() {  # TEST-024 / review W4
  log_info "Test: a mid-flight concurrent modification is detected before rename — refuse exit 1, no lost update (TEST-024)..."
  local s="$TEST_DIR/t24-state.yaml" ec=0
  write_state_fixture "$s"

  # Deterministic race: the injection hook appends a foreign line to the TARGET
  # between load and the commit rename (simulating a second writer that won).
  (cd "$PROJECT_ROOT" && AAI_STATE_INJECT_CONCURRENT=before-rename node .aai/scripts/state.mjs --state "$s" set-validation --status pass > "$TEST_DIR/t24.log" 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "a concurrent modification must be refused exit 1 (got $ec): $(cat "$TEST_DIR/t24.log")"
  grep -qi "concurrent modification" "$TEST_DIR/t24.log" \
    || log_fail "refusal must say 'concurrent modification' and advise retry: $(cat "$TEST_DIR/t24.log")"
  # The OTHER writer's line survives (never clobbered by our stale copy)...
  grep -qF "# concurrent-writer" "$s" || log_fail "the concurrent writer's committed line must survive"
  # ...and OUR stale mutation was NOT committed.
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^  status: not_run$' \
    || log_fail "the losing mutation must NOT be committed over the concurrent write"
  # No stale tmp file left behind by the refusal.
  ls "$TEST_DIR"/t24-state.yaml.tmp-* 2>/dev/null && log_fail "refusal must clean up its tmp file"

  # Retry without contention succeeds.
  st "$s" "$TEST_DIR/t24b.log" set-validation --status pass \
    || log_fail "retry without contention must exit 0: $(cat "$TEST_DIR/t24b.log")"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^  status: pass$' \
    || log_fail "retry must apply the mutation"
  ck "$s" "$TEST_DIR/t24-ck.log" || log_fail "check-state after retry: $(cat "$TEST_DIR/t24-ck.log")"

  # The single-writer concurrency posture is DOCUMENTED (state.mjs header + SPEC-0012).
  grep -qi "single-writer" "$STATE_SCRIPT" \
    || log_fail "state.mjs header must document the single-writer concurrency posture"
  grep -qi "single-writer" "$PROJECT_ROOT/docs/specs/SPEC-0012-loop-reliability-transactional-state-cli.md" \
    || log_fail "SPEC-0012 must document the single-writer concurrency posture"
  log_pass "Concurrent modification detected pre-rename: refused exit 1, retry clean, posture documented (TEST-024)"
}

test_025_unknown_flags_rejected() {  # TEST-025 / review W5
  log_info "Test: unknown/misspelled flags exit 2 naming the flag — data is never silently dropped (TEST-025)..."
  local s="$TEST_DIR/t25-state.yaml" ec
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t25-snap.yaml"
  capture_now

  # (a) the reproduced W5 case: --evidnce/--notse silently dropped pre-fix.
  ec=0
  st "$s" "$TEST_DIR/t25-1.log" set-validation --status pass --evidnce tests/a.log --notse "typo" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "misspelled --evidnce must exit 2 (got $ec): $(cat "$TEST_DIR/t25-1.log")"
  grep -qF -- "--evidnce" "$TEST_DIR/t25-1.log" || log_fail "error must NAME the unknown flag: $(cat "$TEST_DIR/t25-1.log")"
  grep -qF -- "--evidence" "$TEST_DIR/t25-1.log" || log_fail "error must list the valid flag set: $(cat "$TEST_DIR/t25-1.log")"
  cmp -s "$s" "$TEST_DIR/t25-snap.yaml" || log_fail "rejected unknown flag must not write"

  # (b) every subcommand rejects a flag belonging to a DIFFERENT subcommand.
  ec=0
  st "$s" "$TEST_DIR/t25-2.log" append-run --ref CHANGE-0001 --role Remediation --model m --started "$NOW_UTC" --evidence x.log || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run with set-validation's --evidence must exit 2 (got $ec)"
  ec=0
  st "$s" "$TEST_DIR/t25-3.log" reset-block last_validation --frce || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block --frce (misspelled --force) must exit 2 (got $ec)"
  ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$s" --ticks "$TEST_DIR/t25.jsonl" log-tick \
      --tick 1 --role r --scope CHANGE-0001 --started "$NOW_UTC" --hrness 2.1.199 > "$TEST_DIR/t25-4.log" 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "log-tick --hrness must exit 2 (got $ec)"
  [[ ! -f "$TEST_DIR/t25.jsonl" ]] || log_fail "rejected log-tick must not append"
  cmp -s "$s" "$TEST_DIR/t25-snap.yaml" || log_fail "no rejected command may write"

  # (c) the full VALID flag surface still works (global --state/--ticks included).
  st "$s" "$TEST_DIR/t25-5.log" set-validation --status pass --ref CHANGE-0001/SPEC-0001 --evidence tests/a.log --notes ok \
    || log_fail "valid flags must still be accepted after the strict-args fix: $(cat "$TEST_DIR/t25-5.log")"
  st "$s" "$TEST_DIR/t25-6.log" append-run --ref CHANGE-0001 --role Remediation --model claude-test --started "$NOW_UTC" --note n --tokens-in 1 --tokens-out 2 \
    || log_fail "valid append-run flags must still be accepted: $(cat "$TEST_DIR/t25-6.log")"
  log_pass "Unknown flags fail loud with exit 2 + named flag + valid set; valid surface intact (TEST-025)"
}

main() {
  echo "Testing $TEST_NAME (transactional STATE CLI — SPEC-0012 TEST-001..025)"
  check_deps
  setup_fixture
  test_001_happy_focus_phase
  test_002_table_driven_happy
  test_003_invalid_enums
  test_004_degenerate_inputs
  test_005_crash_before_rename
  test_006_crash_during_write
  test_007_refuse_corrupt_state
  test_008_lib_extraction_regression
  test_009_inline_agent_runs_conversion
  test_010_append_run_autoinit
  test_011_reset_block_guards
  test_012_log_tick_schema
  test_013_log_tick_timestamp_guards
  test_014_prompt_migration_wiring
  test_015_remediation_reset_wiring
  test_016_reset_routes_to_rule11
  test_017_ac_reconciliation_wiring
  test_018_gate_seam
  test_019_regression_anchor
  test_020_diff_locality
  test_021_reset_block_literal_notes
  test_022_inline_header_refused
  test_023_scalar_quoting
  test_024_concurrent_guard
  test_025_unknown_flags_rejected
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
