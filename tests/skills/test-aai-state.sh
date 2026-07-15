#!/usr/bin/env bash
#
# Test: aai-state transactional STATE CLI (CHANGE-0006 / SPEC-0012)
# Verifies .aai/scripts/state.mjs — the structural line-edit STATE.yaml engine
# (atomic tmp+rename write, duplicate-key refusal, closed-set enums, reset-block
# guards, log-tick JSONL append) — plus the nine-prompt migration wiring and the
# implementer AC-table reconciliation gate (D8). TEST-001..020 per SPEC-0012;
# TEST-021..025 per the review-20260704T093742Z W1-W5 hardening remediation.
# test_026..033 per CHANGE-0008 / SPEC-0014 (spec-local ids TEST-001..007 +
# TEST-009): --clear field clearing (F1) + set-phase spec_path placement (F2).
# test_034..036 per the review-20260707T081303Z E1/W1/W2 remediation (spec-local
# ids TEST-010..012): prototype-chain clear names refused, repeated --clear
# accumulates, blank-line block-scalar span cleared whole.
# test_042..051 per CHANGE-0010 / spec-model-tiering-with-teeth (spec-local ids
# TEST-001..005, TEST-007..011): set-validation --model independence check,
# append-run token warning, MODEL dispatch wiring, wrapper model: frontmatter.
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
  # CHANGE-0012: lowercase slugs are now a VALID ref shape, so the bad-shape
  # probe uses a value matching NEITHER shape (mixed case, no digits).
  ec=0; st "$s" "$TEST_DIR/t4-2.log" append-run --ref Nope-Ref --role Implementation --model m --started "$NOW_UTC" || ec=$?
  [[ "$ec" == 2 ]] || log_fail "append-run --ref Nope-Ref (bad ref shape) must exit 2 (got $ec)"
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

# ---------------------------------------------------------------------------
# CHANGE-0008 / SPEC-0014 — F1 `--clear <comma-list>` + F2 set-phase placement.
# Fixture diversity (SKILL_TDD checklist): stale-populated (026/027),
# already-null / already-[] and missing-field (030), guard-bypass negative
# control (028), rejected-input atomicity (028/029), blank-line-separated item
# + minimal item without primary_path + upsert control (031/032).

# Fixture whose code_review block MISSES head_ref and notes entirely (clear
# must CREATE `field: null` at end of block — missing-field shape).
write_sparse_review_state() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0020
  primary_path: docs/issues/CHANGE-0020.md
code_review:
  required: true
  status: not_run
  scope: >-
    fixture review scope
  base_ref: main
  report_paths: []
last_validation:
  status: not_run
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# Fixture with a blank-line-separated work item that has NO spec_path yet —
# the reproduced F2 placement-bug shape (D3).
write_blank_separated_item_state() {
  cat > "$1" <<'YAML'
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0010
  primary_path: docs/issues/CHANGE-0010.md

active_work_items:
  - ref_id: CHANGE-0010
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0010.md

implementation_strategy:
  selected: loop

last_validation:
  status: not_run

updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

test_026_clear_worktree_stale() {  # SPEC-0014 TEST-001 / Spec-AC-01
  log_info "Test: set-worktree --clear branch,path nulls stale fields; block-local diff; check-state clean (SPEC-0014 TEST-001)..."
  local s="$TEST_DIR/t26-state.yaml" before="$TEST_DIR/t26-before.yaml"
  write_state_fixture "$s"
  cp "$s" "$before"

  st "$s" "$TEST_DIR/t26.log" set-worktree --clear branch,path \
    || log_fail "set-worktree --clear branch,path must exit 0: $(cat "$TEST_DIR/t26.log")"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}branch: null$' \
    || log_fail "worktree.branch must be cleared to null"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}path: null$' \
    || log_fail "worktree.path must be cleared to null"
  # Locality: ONLY worktree + updated_at_utc changed.
  strip_block "$before" worktree > "$TEST_DIR/t26-b.txt"
  strip_block "$s" worktree > "$TEST_DIR/t26-a.txt"
  cmp -s "$TEST_DIR/t26-b.txt" "$TEST_DIR/t26-a.txt" \
    || log_fail "--clear leaked outside worktree + updated_at_utc: $(diff "$TEST_DIR/t26-b.txt" "$TEST_DIR/t26-a.txt" | head -5)"
  # Untouched siblings survive inside the block.
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}recommendation: recommended$' \
    || log_fail "unnamed worktree fields must survive the clear"
  ck "$s" "$TEST_DIR/t26-ck.log" || log_fail "check-state after --clear: $(cat "$TEST_DIR/t26-ck.log")"
  log_pass "Stale worktree.branch/path cleared to null, diff block-local, validator clean (SPEC-0014 TEST-001)"
}

test_027_clear_across_subcommands() {  # SPEC-0014 TEST-002 / Spec-AC-01
  log_info "Test: --clear across set-code-review/set-validation/set-focus; clear+set combo; --type none nulls spec_path (SPEC-0014 TEST-002)..."
  local s="$TEST_DIR/t27-state.yaml"
  write_state_fixture "$s"

  # Populate stale values first (the CHANGE-0007 leak shape).
  st "$s" "$TEST_DIR/t27-0.log" set-code-review --head-ref feat/stale-branch --report docs/ai/reviews/stale.md --notes "stale review notes" \
    || log_fail "populating stale review fields must exit 0: $(cat "$TEST_DIR/t27-0.log")"

  # set-code-review: scalar -> null, list -> [], free-text -> null.
  st "$s" "$TEST_DIR/t27-1.log" set-code-review --clear head_ref,report_paths,notes \
    || log_fail "set-code-review --clear must exit 0: $(cat "$TEST_DIR/t27-1.log")"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}head_ref: null$' \
    || log_fail "code_review.head_ref must be null after clear"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}report_paths: \[\]$' \
    || log_fail "code_review.report_paths must be [] after clear (list semantics)"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}notes: null$' \
    || log_fail "code_review.notes must be null after clear"
  grep -qF "docs/ai/reviews/stale.md" "$s" && log_fail "stale report path must be gone after the list clear"
  ck "$s" "$TEST_DIR/t27-1c.log" || log_fail "check-state after review clear: $(cat "$TEST_DIR/t27-1c.log")"

  # list clear unlocks the replace workflow for the append-only --report flag.
  st "$s" "$TEST_DIR/t27-2.log" set-code-review --report docs/ai/reviews/fresh.md \
    || log_fail "re-append after list clear must exit 0: $(cat "$TEST_DIR/t27-2.log")"
  grep -qE '^    - docs/ai/reviews/fresh.md$' "$s" || log_fail "cleared list must accept a fresh append"

  # set-validation clear-only: no --status needed; run_at_utc NOT re-stamped.
  st "$s" "$TEST_DIR/t27-3.log" set-validation --clear evidence_paths,ref_id,notes \
    || log_fail "set-validation --clear (no --status) must exit 0: $(cat "$TEST_DIR/t27-3.log")"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}evidence_paths: \[\]$' \
    || log_fail "last_validation.evidence_paths must be [] after clear"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}ref_id: null$' \
    || log_fail "last_validation.ref_id must be null after clear"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}notes: null$' \
    || log_fail "last_validation.notes must be null after clear"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}run_at_utc: 2026-07-01T00:00:00Z$' \
    || log_fail "clear-only set-validation must NOT re-stamp run_at_utc (no validation ran)"
  sed -n '/^last_validation:/,/^[a-z]/p' "$s" | grep -qE '^ {2}status: not_run$' \
    || log_fail "clear-only set-validation must leave status untouched"
  ck "$s" "$TEST_DIR/t27-3c.log" || log_fail "check-state after validation clear: $(cat "$TEST_DIR/t27-3c.log")"

  # set-focus --clear spec_path (clear-only, no --type).
  st "$s" "$TEST_DIR/t27-4.log" set-focus --clear spec_path \
    || log_fail "set-focus --clear spec_path must exit 0: $(cat "$TEST_DIR/t27-4.log")"
  sed -n '/^current_focus:/,/^[a-z]/p' "$s" | grep -qE '^ {2}spec_path: null$' \
    || log_fail "current_focus.spec_path must be null after clear"
  sed -n '/^current_focus:/,/^[a-z]/p' "$s" | grep -qE '^ {2}type: intake_change$' \
    || log_fail "clear-only set-focus must not touch type"
  sed -n '/^current_focus:/,/^[a-z]/p' "$s" | grep -qE '^ {2}ref_id: CHANGE-0001$' \
    || log_fail "clear-only set-focus must not touch ref_id"
  ck "$s" "$TEST_DIR/t27-4c.log" || log_fail "check-state after focus clear: $(cat "$TEST_DIR/t27-4c.log")"

  # --clear combined with a DISJOINT set flag: both apply in one invocation.
  st "$s" "$TEST_DIR/t27-5.log" set-worktree --clear branch --base-ref develop \
    || log_fail "--clear combined with a disjoint set flag must exit 0: $(cat "$TEST_DIR/t27-5.log")"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}branch: null$' \
    || log_fail "combined invocation must apply the clear"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}base_ref: develop$' \
    || log_fail "combined invocation must apply the disjoint set flag"
  ck "$s" "$TEST_DIR/t27-5c.log" || log_fail "check-state after combined clear+set: $(cat "$TEST_DIR/t27-5c.log")"

  # Bonus normalization: set-focus --type none also nulls spec_path (D2).
  st "$s" "$TEST_DIR/t27-6.log" set-focus --type intake_change --ref CHANGE-0001 --path docs/issues/CHANGE-0001-fixture.md --spec-path docs/specs/SPEC-0001-fixture.md \
    || log_fail "re-setting spec_path must exit 0: $(cat "$TEST_DIR/t27-6.log")"
  st "$s" "$TEST_DIR/t27-7.log" set-focus --type none \
    || log_fail "set-focus --type none must exit 0: $(cat "$TEST_DIR/t27-7.log")"
  sed -n '/^current_focus:/,/^[a-z]/p' "$s" | grep -qE '^ {2}spec_path: null$' \
    || log_fail "set-focus --type none must null spec_path exactly as it nulls ref_id/primary_path"
  sed -n '/^current_focus:/,/^[a-z]/p' "$s" | grep -qE '^ {2}ref_id: null$' \
    || log_fail "set-focus --type none must still null ref_id"
  ck "$s" "$TEST_DIR/t27-7c.log" || log_fail "check-state after --type none: $(cat "$TEST_DIR/t27-7c.log")"
  log_pass "--clear semantics correct across subcommands; combo works; --type none nulls spec_path (SPEC-0014 TEST-002)"
}

test_028_clear_guard_bypass_refused() {  # SPEC-0014 TEST-003 / Spec-AC-02
  log_info "Test: --clear cannot bypass verdict/policy guards — refused exit 2 naming reset-block, zero writes (SPEC-0014 TEST-003)..."
  local s="$TEST_DIR/t28-state.yaml" ec
  write_state_fixture "$s" pass pass
  cp "$s" "$TEST_DIR/t28-snap.yaml"

  ec=0; st "$s" "$TEST_DIR/t28-1.log" set-validation --clear status || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-validation --clear status must be REFUSED exit 2 (got $ec): $(cat "$TEST_DIR/t28-1.log")"
  grep -qF "reset-block" "$TEST_DIR/t28-1.log" \
    || log_fail "refusal must name reset-block as the sanctioned path: $(cat "$TEST_DIR/t28-1.log")"
  cmp -s "$s" "$TEST_DIR/t28-snap.yaml" || log_fail "refused clear must not write"

  ec=0; st "$s" "$TEST_DIR/t28-2.log" set-code-review --clear status || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-code-review --clear status must be REFUSED exit 2 (got $ec): $(cat "$TEST_DIR/t28-2.log")"
  grep -qF "reset-block" "$TEST_DIR/t28-2.log" \
    || log_fail "review refusal must name reset-block: $(cat "$TEST_DIR/t28-2.log")"
  cmp -s "$s" "$TEST_DIR/t28-snap.yaml" || log_fail "refused review clear must not write"

  # Policy fields with closed-set reset values stay flag-only.
  ec=0; st "$s" "$TEST_DIR/t28-3.log" set-worktree --clear recommendation || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-worktree --clear recommendation must exit 2 (got $ec): $(cat "$TEST_DIR/t28-3.log")"
  ec=0; st "$s" "$TEST_DIR/t28-4.log" set-code-review --clear required || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-code-review --clear required must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t28-5.log" set-validation --clear run_at_utc || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-validation --clear run_at_utc must exit 2 (self-stamped field, got $ec)"
  cmp -s "$s" "$TEST_DIR/t28-snap.yaml" || log_fail "no refused clear may write"

  # D6 guard semantics byte-untouched: reset-block on pass still refused sans --force.
  ec=0; st "$s" "$TEST_DIR/t28-6.log" reset-block last_validation || ec=$?
  [[ "$ec" == 2 ]] || log_fail "reset-block pass-guard must still refuse exit 2 after the --clear feature (got $ec)"
  log_pass "Guard ownership preserved: status/policy fields not clearable, reset-block named, D6 intact (SPEC-0014 TEST-003)"
}

test_029_clear_strict_validation() {  # SPEC-0014 TEST-004 / Spec-AC-03
  log_info "Test: unknown clear field / clear+set contradiction / empty list — exit 2, byte-identical file (SPEC-0014 TEST-004)..."
  local s="$TEST_DIR/t29-state.yaml" ec
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t29-snap.yaml"

  # Unknown field: names the offender AND the full valid clearable set (W5 shape).
  ec=0; st "$s" "$TEST_DIR/t29-1.log" set-worktree --clear bogus || ec=$?
  [[ "$ec" == 2 ]] || log_fail "unknown clear field must exit 2 (got $ec): $(cat "$TEST_DIR/t29-1.log")"
  grep -qF "bogus" "$TEST_DIR/t29-1.log" || log_fail "error must name the offending field: $(cat "$TEST_DIR/t29-1.log")"
  grep -qF "branch" "$TEST_DIR/t29-1.log" && grep -qF "inline_review_scope" "$TEST_DIR/t29-1.log" \
    || log_fail "error must list the valid clearable set: $(cat "$TEST_DIR/t29-1.log")"

  # A field from ANOTHER subcommand's whitelist is unknown here.
  ec=0; st "$s" "$TEST_DIR/t29-2.log" set-focus --clear evidence_paths || ec=$?
  [[ "$ec" == 2 ]] || log_fail "cross-subcommand clear field must exit 2 (got $ec)"

  # clear + set of the SAME field in one invocation: contradiction.
  ec=0; st "$s" "$TEST_DIR/t29-3.log" set-worktree --clear branch --branch feat/x || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--clear branch --branch x must exit 2 contradiction (got $ec): $(cat "$TEST_DIR/t29-3.log")"
  # ...including the non-1:1 flag-to-field mappings (report -> report_paths).
  ec=0; st "$s" "$TEST_DIR/t29-4.log" set-code-review --clear report_paths --report docs/ai/reviews/x.md || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--clear report_paths --report x must exit 2 contradiction (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t29-5.log" set-validation --clear ref_id --ref CHANGE-0001 || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--clear ref_id --ref x must exit 2 contradiction (got $ec)"

  # Empty list: --clear without a value, and --clear "".
  ec=0; st "$s" "$TEST_DIR/t29-6.log" set-worktree --clear || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--clear without a value must exit 2 (got $ec)"
  ec=0; st "$s" "$TEST_DIR/t29-7.log" set-worktree --clear "" || ec=$?
  [[ "$ec" == 2 ]] || log_fail '--clear "" must exit 2 (got '"$ec"')'
  ec=0; st "$s" "$TEST_DIR/t29-8.log" set-worktree --clear ", ," || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--clear with only commas/whitespace must exit 2 (got $ec)"

  cmp -s "$s" "$TEST_DIR/t29-snap.yaml" || log_fail "every rejected --clear must leave the file byte-identical"
  log_pass "Strict clear-list validation: unknown/contradiction/empty all exit 2 with zero writes (SPEC-0014 TEST-004)"
}

test_030_clear_idempotent_and_missing() {  # SPEC-0014 TEST-005 / Spec-AC-04
  log_info "Test: clearing already-null/[] fields is an idempotent exit-0 no-op; missing whitelisted field created as null (SPEC-0014 TEST-005)..."
  local s="$TEST_DIR/t30-state.yaml"
  write_state_fixture "$s"   # head_ref already null, report_paths already [], inline_review_scope already null

  st "$s" "$TEST_DIR/t30-1.log" set-code-review --clear head_ref,report_paths \
    || log_fail "clearing already-null/[] fields must exit 0: $(cat "$TEST_DIR/t30-1.log")"
  local n
  n="$(sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -cE '^ {2}head_ref:' || true)"
  [[ "$n" == "1" ]] || log_fail "exactly one head_ref line after idempotent clear (got $n)"
  n="$(sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -cE '^ {2}report_paths:' || true)"
  [[ "$n" == "1" ]] || log_fail "exactly one report_paths line after idempotent clear (got $n)"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}report_paths: \[\]$' \
    || log_fail "already-[] list must stay a single [] line"

  # Second run: still exit 0, still single lines (stable under repetition).
  st "$s" "$TEST_DIR/t30-2.log" set-code-review --clear head_ref,report_paths \
    || log_fail "second idempotent clear must exit 0: $(cat "$TEST_DIR/t30-2.log")"
  grep -v '^updated_at_utc:' "$s" > "$TEST_DIR/t30-run1.txt"
  st "$s" "$TEST_DIR/t30-3.log" set-code-review --clear head_ref,report_paths \
    || log_fail "third idempotent clear must exit 0"
  grep -v '^updated_at_utc:' "$s" > "$TEST_DIR/t30-run2.txt"
  cmp -s "$TEST_DIR/t30-run1.txt" "$TEST_DIR/t30-run2.txt" \
    || log_fail "repeated clears must be byte-identical modulo updated_at_utc"
  ck "$s" "$TEST_DIR/t30-ck.log" || log_fail "check-state after idempotent clears: $(cat "$TEST_DIR/t30-ck.log")"

  # Already-null free-text field (`>-` in the fixture becomes null, then stays).
  st "$s" "$TEST_DIR/t30-4.log" set-worktree --clear rationale \
    || log_fail "clearing the >- rationale must exit 0: $(cat "$TEST_DIR/t30-4.log")"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}rationale: null$' \
    || log_fail "worktree.rationale (>- scalar) must clear to a single null line"
  grep -qF "Fixture worktree rationale." "$s" && log_fail "the >- continuation lines must be removed by the clear"
  st "$s" "$TEST_DIR/t30-5.log" set-worktree --clear rationale \
    || log_fail "re-clearing the already-null rationale must exit 0"

  # A MISSING whitelisted field is created as `field: null` at end of block.
  local m="$TEST_DIR/t30-sparse.yaml"
  write_sparse_review_state "$m"
  grep -qE '^ {2}head_ref:' "$m" && log_fail "sparse fixture must not carry head_ref (fixture guard)"
  st "$m" "$TEST_DIR/t30-6.log" set-code-review --clear head_ref,notes \
    || log_fail "clearing missing fields must exit 0 (create-as-null): $(cat "$TEST_DIR/t30-6.log")"
  sed -n '/^code_review:/,/^[a-z]/p' "$m" | grep -qE '^ {2}head_ref: null$' \
    || log_fail "missing head_ref must be created as null"
  sed -n '/^code_review:/,/^[a-z]/p' "$m" | grep -qE '^ {2}notes: null$' \
    || log_fail "missing notes must be created as null"
  ck "$m" "$TEST_DIR/t30-6c.log" || log_fail "check-state after create-as-null: $(cat "$TEST_DIR/t30-6c.log")"
  log_pass "Idempotent clears exit 0 with single field lines; missing fields created as null (SPEC-0014 TEST-005)"
}

test_031_spec_path_placement() {  # SPEC-0014 TEST-006 / Spec-AC-05
  log_info "Test: set-phase --spec-path lands directly after primary_path INSIDE the item block; double-run byte-idempotent (SPEC-0014 TEST-006)..."
  local s="$TEST_DIR/t31-state.yaml"
  write_blank_separated_item_state "$s"

  st "$s" "$TEST_DIR/t31-1.log" set-phase --ref CHANGE-0010 --phase validation --spec-path docs/specs/SPEC-0010-fixture.md \
    || log_fail "set-phase --spec-path must exit 0: $(cat "$TEST_DIR/t31-1.log")"

  # Byte-level placement assertion: the whole file (modulo updated_at_utc) must
  # equal the expected shape — spec_path directly after primary_path, the blank
  # line still TRAILING the item (the pre-fix bug spliced spec_path after it).
  grep -v '^updated_at_utc:' "$s" > "$TEST_DIR/t31-actual.txt"
  cat > "$TEST_DIR/t31-expected.txt" <<'YAML'
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0010
  primary_path: docs/issues/CHANGE-0010.md

active_work_items:
  - ref_id: CHANGE-0010
    status: in_progress
    phase: validation
    primary_path: docs/issues/CHANGE-0010.md
    spec_path: docs/specs/SPEC-0010-fixture.md

implementation_strategy:
  selected: loop

last_validation:
  status: not_run

YAML
  cmp -s "$TEST_DIR/t31-actual.txt" "$TEST_DIR/t31-expected.txt" \
    || log_fail "spec_path placement wrong (must sit directly after primary_path inside the item): $(diff "$TEST_DIR/t31-expected.txt" "$TEST_DIR/t31-actual.txt" | head -8)"
  ck "$s" "$TEST_DIR/t31-ck.log" || log_fail "check-state after placement: $(cat "$TEST_DIR/t31-ck.log")"

  # Double-run idempotence: byte-identical modulo updated_at_utc.
  st "$s" "$TEST_DIR/t31-2.log" set-phase --ref CHANGE-0010 --phase validation --spec-path docs/specs/SPEC-0010-fixture.md \
    || log_fail "second identical set-phase must exit 0: $(cat "$TEST_DIR/t31-2.log")"
  grep -v '^updated_at_utc:' "$s" > "$TEST_DIR/t31-actual2.txt"
  cmp -s "$TEST_DIR/t31-actual.txt" "$TEST_DIR/t31-actual2.txt" \
    || log_fail "double-run must be byte-identical modulo updated_at_utc: $(diff "$TEST_DIR/t31-actual.txt" "$TEST_DIR/t31-actual2.txt" | head -5)"
  ck "$s" "$TEST_DIR/t31-2c.log" || log_fail "check-state after double run: $(cat "$TEST_DIR/t31-2c.log")"
  log_pass "spec_path placed inside the item directly after primary_path; double-run stable (SPEC-0014 TEST-006)"
}

test_032_spec_path_fallback_and_upsert() {  # SPEC-0014 TEST-007 / Spec-AC-05
  log_info "Test: item WITHOUT primary_path gets fields at end of contiguous item lines; upsert order control (SPEC-0014 TEST-007)..."
  local s="$TEST_DIR/t32-state.yaml"
  cat > "$s" <<'YAML'
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0011
  primary_path: docs/issues/CHANGE-0011.md

active_work_items:
  - ref_id: CHANGE-0011
    status: in_progress
    phase: implementation

implementation_strategy:
  selected: loop

last_validation:
  status: not_run

updated_at_utc: 2026-07-01T00:00:00Z
YAML

  # (a) fallback: no primary_path in the item -> spec_path at end of the
  # CONTIGUOUS item lines, never after the trailing blank.
  st "$s" "$TEST_DIR/t32-1.log" set-phase --ref CHANGE-0011 --phase validation --spec-path docs/specs/SPEC-0011-fixture.md \
    || log_fail "set-phase --spec-path on a primary_path-less item must exit 0: $(cat "$TEST_DIR/t32-1.log")"
  grep -v '^updated_at_utc:' "$s" > "$TEST_DIR/t32-actual.txt"
  cat > "$TEST_DIR/t32-expected.txt" <<'YAML'
project_status: active

current_focus:
  type: intake_change
  ref_id: CHANGE-0011
  primary_path: docs/issues/CHANGE-0011.md

active_work_items:
  - ref_id: CHANGE-0011
    status: in_progress
    phase: validation
    spec_path: docs/specs/SPEC-0011-fixture.md

implementation_strategy:
  selected: loop

last_validation:
  status: not_run

YAML
  cmp -s "$TEST_DIR/t32-actual.txt" "$TEST_DIR/t32-expected.txt" \
    || log_fail "fallback placement wrong (end of contiguous item lines): $(diff "$TEST_DIR/t32-expected.txt" "$TEST_DIR/t32-actual.txt" | head -8)"
  ck "$s" "$TEST_DIR/t32-1c.log" || log_fail "check-state after fallback placement: $(cat "$TEST_DIR/t32-1c.log")"

  # (b) creating primary_path later also lands INSIDE the item; spec_path then
  # updates in place (D3: primary_path never after a blank).
  st "$s" "$TEST_DIR/t32-2.log" set-phase --ref CHANGE-0011 --phase validation --path docs/issues/CHANGE-0011.md \
    || log_fail "set-phase --path must exit 0: $(cat "$TEST_DIR/t32-2.log")"
  sed -n '/^active_work_items:/,/^[a-z]/p' "$s" | sed -n '2,6p' > "$TEST_DIR/t32-item.txt"
  grep -qE '^ {4}primary_path: docs/issues/CHANGE-0011.md$' "$TEST_DIR/t32-item.txt" \
    || log_fail "created primary_path must sit inside the contiguous item lines: $(cat "$TEST_DIR/t32-item.txt")"
  ck "$s" "$TEST_DIR/t32-2c.log" || log_fail "check-state after primary_path creation: $(cat "$TEST_DIR/t32-2c.log")"

  # (c) upsert control: a NEW item keeps the ref_id/status/phase/primary_path/
  # spec_path emission order (unchanged behavior, asserted as a control).
  st "$s" "$TEST_DIR/t32-3.log" set-phase --ref ISSUE-0099 --phase planning --status planned --path docs/issues/ISSUE-0099.md --spec-path docs/specs/SPEC-0099.md \
    || log_fail "upsert set-phase must exit 0: $(cat "$TEST_DIR/t32-3.log")"
  awk '/^  - ref_id: ISSUE-0099$/{found=1} found && n<5 {print; n++}' "$s" > "$TEST_DIR/t32-upsert.txt"
  cat > "$TEST_DIR/t32-upsert-expected.txt" <<'YAML'
  - ref_id: ISSUE-0099
    status: planned
    phase: planning
    primary_path: docs/issues/ISSUE-0099.md
    spec_path: docs/specs/SPEC-0099.md
YAML
  cmp -s "$TEST_DIR/t32-upsert.txt" "$TEST_DIR/t32-upsert-expected.txt" \
    || log_fail "upsert field order must stay ref_id/status/phase/primary_path/spec_path: $(cat "$TEST_DIR/t32-upsert.txt")"
  ck "$s" "$TEST_DIR/t32-3c.log" || log_fail "check-state after upsert: $(cat "$TEST_DIR/t32-3c.log")"
  log_pass "Fallback + created-field placement inside contiguous item lines; upsert order preserved (SPEC-0014 TEST-007)"
}

test_033_spec0014_regression_backstop() {  # SPEC-0014 TEST-009 / Spec-AC-07
  log_info "Test: USER_GUIDE body-lint PASS (repo audit + index idempotence covered by TEST-019 in this same run) (SPEC-0014 TEST-009)..."
  local ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --lint-body-file docs/USER_GUIDE.md > "$TEST_DIR/t33-lint.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "docs-audit --lint-body-file docs/USER_GUIDE.md must exit 0 (got $ec): $(tail -10 "$TEST_DIR/t33-lint.log")"
  log_pass "USER_GUIDE body lint clean; suite-level regression anchors green (SPEC-0014 TEST-009)"
}

test_034_clear_prototype_names_refused() {  # SPEC-0014 TEST-010 / Spec-AC-03 (review-20260707T081303Z E1)
  log_info "Test: JS prototype-chain field names are NOT clearable — exit 2 naming the valid set, zero writes, all four subcommands (SPEC-0014 TEST-010)..."
  local s="$TEST_DIR/t34-state.yaml" ec f
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t34-snap.yaml"

  # The whole Object.prototype member family must be refused as unknown fields.
  for f in toString __proto__ constructor valueOf hasOwnProperty isPrototypeOf; do
    ec=0; st "$s" "$TEST_DIR/t34-w.log" set-worktree --clear "$f" || ec=$?
    [[ "$ec" == 2 ]] || log_fail "set-worktree --clear $f must exit 2 (got $ec): $(cat "$TEST_DIR/t34-w.log")"
    grep -qF "not clearable" "$TEST_DIR/t34-w.log" \
      || log_fail "refusal for $f must use the unknown-field message: $(cat "$TEST_DIR/t34-w.log")"
    grep -qF "branch" "$TEST_DIR/t34-w.log" && grep -qF "inline_review_scope" "$TEST_DIR/t34-w.log" \
      || log_fail "refusal for $f must name the valid clearable set: $(cat "$TEST_DIR/t34-w.log")"
  done

  # All four --clear subcommands share the whitelist helper: each must refuse.
  ec=0; st "$s" "$TEST_DIR/t34-r.log" set-code-review --clear toString || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-code-review --clear toString must exit 2 (got $ec): $(cat "$TEST_DIR/t34-r.log")"
  ec=0; st "$s" "$TEST_DIR/t34-v.log" set-validation --clear __proto__ || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-validation --clear __proto__ must exit 2 (got $ec): $(cat "$TEST_DIR/t34-v.log")"
  ec=0; st "$s" "$TEST_DIR/t34-f.log" set-focus --clear valueOf || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-focus --clear valueOf must exit 2 (got $ec): $(cat "$TEST_DIR/t34-f.log")"

  # A prototype name smuggled into an otherwise-valid comma list: refused pre-write.
  ec=0; st "$s" "$TEST_DIR/t34-m.log" set-worktree --clear branch,toString || ec=$?
  [[ "$ec" == 2 ]] || log_fail "set-worktree --clear branch,toString must exit 2 (got $ec): $(cat "$TEST_DIR/t34-m.log")"

  cmp -s "$s" "$TEST_DIR/t34-snap.yaml" \
    || log_fail "refused prototype-name clears must leave the file byte-identical: $(diff "$TEST_DIR/t34-snap.yaml" "$s" | head -5)"
  grep -qE '^ {2}(toString|__proto__|constructor|valueOf|hasOwnProperty|isPrototypeOf):' "$s" \
    && log_fail "no prototype-named junk key may be written into STATE"
  log_pass "Prototype-chain clear names refused exit 2 on all four subcommands, zero writes (SPEC-0014 TEST-010)"
}

test_035_clear_repeated_flag_accumulates() {  # SPEC-0014 TEST-011 / review-20260707T081303Z W1
  log_info "Test: repeated --clear flags accumulate (no silent last-wins drop); dedupe; contradiction still caught across occurrences (SPEC-0014 TEST-011)..."
  local s="$TEST_DIR/t35-state.yaml" ec n
  write_state_fixture "$s"

  # Two occurrences: BOTH instructions must apply (pre-fix: first silently dropped).
  st "$s" "$TEST_DIR/t35-1.log" set-worktree --clear branch --clear path \
    || log_fail "set-worktree --clear branch --clear path must exit 0: $(cat "$TEST_DIR/t35-1.log")"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}branch: null$' \
    || log_fail "first --clear occurrence (branch) must not be dropped"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}path: null$' \
    || log_fail "second --clear occurrence (path) must apply"
  sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -qE '^ {2}recommendation: recommended$' \
    || log_fail "unnamed worktree fields must survive the accumulated clear"
  ck "$s" "$TEST_DIR/t35-1c.log" || log_fail "check-state after accumulated clear: $(cat "$TEST_DIR/t35-1c.log")"

  # Repeat mixed with a comma-list: union of all occurrences.
  st "$s" "$TEST_DIR/t35-2.log" set-code-review --clear head_ref --clear report_paths,notes \
    || log_fail "mixed repeat + comma-list --clear must exit 0: $(cat "$TEST_DIR/t35-2.log")"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}head_ref: null$' \
    || log_fail "head_ref from the first occurrence must be cleared"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}report_paths: \[\]$' \
    || log_fail "report_paths from the second occurrence must be cleared"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}notes: null$' \
    || log_fail "notes from the second occurrence must be cleared"

  # Same field twice across occurrences: dedupe, exactly one field line.
  st "$s" "$TEST_DIR/t35-3.log" set-worktree --clear base_ref --clear base_ref \
    || log_fail "duplicate field across --clear occurrences must exit 0 (dedupe): $(cat "$TEST_DIR/t35-3.log")"
  n="$(sed -n '/^worktree:/,/^[a-z]/p' "$s" | grep -cE '^ {2}base_ref:' || true)"
  [[ "$n" == "1" ]] || log_fail "exactly one base_ref line after deduped clear (got $n)"
  ck "$s" "$TEST_DIR/t35-3c.log" || log_fail "check-state after deduped clear: $(cat "$TEST_DIR/t35-3c.log")"

  # Strict validation still spans ALL occurrences: contradiction + unknown field.
  cp "$s" "$TEST_DIR/t35-snap.yaml"
  ec=0; st "$s" "$TEST_DIR/t35-4.log" set-worktree --clear branch --clear path --path /tmp/x || ec=$?
  [[ "$ec" == 2 ]] || log_fail "clear+set contradiction in a later occurrence must exit 2 (got $ec): $(cat "$TEST_DIR/t35-4.log")"
  ec=0; st "$s" "$TEST_DIR/t35-5.log" set-worktree --clear branch --clear bogus || ec=$?
  [[ "$ec" == 2 ]] || log_fail "unknown field in a later occurrence must exit 2 (got $ec): $(cat "$TEST_DIR/t35-5.log")"
  ec=0; st "$s" "$TEST_DIR/t35-6.log" set-worktree --clear branch --clear || ec=$?
  [[ "$ec" == 2 ]] || log_fail "valueless later --clear occurrence must exit 2 (got $ec): $(cat "$TEST_DIR/t35-6.log")"
  cmp -s "$s" "$TEST_DIR/t35-snap.yaml" \
    || log_fail "every refused repeated --clear must leave the file byte-identical"
  log_pass "Repeated --clear accumulates (union + dedupe); strict validation spans all occurrences (SPEC-0014 TEST-011)"
}

test_036_clear_blankline_folded_scalar() {  # SPEC-0014 TEST-012 / review-20260707T081303Z W2
  log_info "Test: clearing/overwriting a hand-edited >- field containing a BLANK line replaces the whole scalar — no orphaned continuation (SPEC-0014 TEST-012)..."
  local s="$TEST_DIR/t36-state.yaml" n
  write_state_fixture "$s"
  # Hand-edit code_review.notes into a two-paragraph folded scalar (blank line
  # inside the block scalar — legal YAML, never produced by this engine).
  awk '{
    if ($0 == "  notes: null") {
      print "  notes: >-";
      print "    para one line";
      print "";
      print "    para two line";
    } else print
  }' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
  grep -qF "para two line" "$s" || log_fail "fixture guard: blank-line folded notes not installed"
  ck "$s" "$TEST_DIR/t36-0c.log" || log_fail "fixture control: hand-edited state must be valid pre-clear: $(cat "$TEST_DIR/t36-0c.log")"

  # --clear must remove the WHOLE scalar span including the post-blank paragraph.
  st "$s" "$TEST_DIR/t36-1.log" set-code-review --clear notes \
    || log_fail "set-code-review --clear notes must exit 0: $(cat "$TEST_DIR/t36-1.log")"
  sed -n '/^code_review:/,/^[a-z]/p' "$s" | grep -qE '^ {2}notes: null$' \
    || log_fail "code_review.notes must be a single null line after clear"
  grep -qF "para one line" "$s" && log_fail "pre-blank continuation must be removed by the clear"
  grep -qF "para two line" "$s" && log_fail "post-blank continuation must NOT be orphaned by the clear"
  ck "$s" "$TEST_DIR/t36-1c.log" || log_fail "check-state after blank-line-scalar clear: $(cat "$TEST_DIR/t36-1c.log")"
  # YAML-parser ground truth (PyYAML when available): notes must be real null,
  # not the junk 'null\npara two line' string the orphaned span used to produce.
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
v = d["code_review"]["notes"]
assert v is None, "expected notes == null, got %r" % (v,)
' "$s" || log_fail "PyYAML ground truth: code_review.notes must parse as null after clear"
    log_info "PyYAML ground truth confirmed notes == null"
  else
    log_info "PyYAML unavailable — byte-level orphan assertions stand alone"
  fi

  # Same helper class via setField OVERWRITE (--notes): whole span replaced too.
  local o="$TEST_DIR/t36-over.yaml"
  write_state_fixture "$o"
  awk '{
    if ($0 == "  notes: null") {
      print "  notes: >-";
      print "    para one line";
      print "";
      print "    para two line";
    } else print
  }' "$o" > "$o.tmp" && mv "$o.tmp" "$o"
  st "$o" "$TEST_DIR/t36-2.log" set-code-review --notes "fresh notes" \
    || log_fail "set-code-review --notes over a blank-line scalar must exit 0: $(cat "$TEST_DIR/t36-2.log")"
  grep -qF "para two line" "$o" && log_fail "overwrite must not orphan the post-blank continuation"
  sed -n '/^code_review:/,/^[a-z]/p' "$o" | grep -qE '^ {4}fresh notes$' \
    || log_fail "overwrite must install the fresh >- content"
  n="$(sed -n '/^code_review:/,/^[a-z]/p' "$o" | grep -cE '^ {2}notes:' || true)"
  [[ "$n" == "1" ]] || log_fail "exactly one notes line after overwrite (got $n)"
  ck "$o" "$TEST_DIR/t36-2c.log" || log_fail "check-state after blank-line-scalar overwrite: $(cat "$TEST_DIR/t36-2c.log")"
  log_pass "Blank-line block scalars cleared/overwritten as one span; parser-true null; no orphans (SPEC-0014 TEST-012)"
}

# --- CHANGE-0012 / spec-slug-refs-across-tooling: slug refs in refFlag --------
# SPEC D1: refFlag accepts EITHER the display shape ^[A-Z]+-\d+$ (REF_RE,
# unchanged) OR the slug shape ^(?=[a-z0-9-]{3,53}$)[a-z0-9]+(?:-[a-z0-9]+)*$
# (SLUG_RE, aligned with SPEC-0015 deriveSlug + optional -xxxx suffix). The two
# shapes are disjoint (case); anything else exits 2 pre-write naming BOTH.

test_037_slug_set_focus() {  # CHANGE-0012 TEST-001 / Spec-AC-01
  log_info "Test: set-focus accepts a slug ref; ref_id written verbatim; check-state clean (CHANGE-0012 TEST-001)..."
  local s="$TEST_DIR/t37-state.yaml"
  write_state_fixture "$s"
  st "$s" "$TEST_DIR/t37.log" set-focus --type intake_change --ref slug-refs-across-tooling \
    --path docs/issues/CHANGE-DRAFT-slug-refs-across-tooling.md \
    || log_fail "set-focus with a slug ref must exit 0 (RED today: exit 2): $(cat "$TEST_DIR/t37.log")"
  grep -qE '^  ref_id: slug-refs-across-tooling$' "$s" \
    || log_fail "current_focus.ref_id must carry the slug VERBATIM (unquoted plain scalar)"
  ck "$s" "$TEST_DIR/t37-ck.log" || log_fail "check-state after slug set-focus: $(cat "$TEST_DIR/t37-ck.log")"
  log_pass "set-focus accepts a slug ref verbatim; check-state clean (CHANGE-0012 TEST-001)"
}

test_038_slug_set_phase() {  # CHANGE-0012 TEST-002 / Spec-AC-01
  log_info "Test: set-phase upserts a slug-keyed work item; DRAFT spec-path accepted (CHANGE-0012 TEST-002)..."
  local s="$TEST_DIR/t38-state.yaml"
  write_state_fixture "$s"
  st "$s" "$TEST_DIR/t38.log" set-phase --ref slug-refs-across-tooling --phase planning --status in_progress \
    --spec-path docs/specs/SPEC-DRAFT-slug-refs-across-tooling.md \
    || log_fail "set-phase with a slug ref must exit 0 (RED today: exit 2): $(cat "$TEST_DIR/t38.log")"
  grep -qE '^  - ref_id: slug-refs-across-tooling$' "$s" \
    || log_fail "active_work_items must carry the upserted slug-keyed item"
  grep -qE '^    spec_path: docs/specs/SPEC-DRAFT-slug-refs-across-tooling.md$' "$s" \
    || log_fail "the DRAFT spec_path must be written (it is a path, not a ref)"
  ck "$s" "$TEST_DIR/t38-ck.log" || log_fail "check-state after slug set-phase: $(cat "$TEST_DIR/t38-ck.log")"
  # Second call UPDATES the same item in place (no duplicate slug item).
  st "$s" "$TEST_DIR/t38b.log" set-phase --ref slug-refs-across-tooling --phase implementation \
    || log_fail "slug set-phase update must exit 0: $(cat "$TEST_DIR/t38b.log")"
  local n
  n="$(grep -cE '^  - ref_id: slug-refs-across-tooling$' "$s" || true)"
  [[ "$n" == "1" ]] || log_fail "slug item must be updated in place, not duplicated (got $n items)"
  grep -qE '^    phase: implementation$' "$s" || log_fail "slug item phase must update to implementation"
  log_pass "set-phase upserts/updates the slug-keyed work item with DRAFT spec_path (CHANGE-0012 TEST-002)"
}

test_039_slug_append_run_checkstate() {  # CHANGE-0012 TEST-003 / Spec-AC-01 (integration, Seam 1)
  log_info "Test: append-run auto-inits metrics.work_items.<slug> and the REAL check-state passes (CHANGE-0012 TEST-003)..."
  local s="$TEST_DIR/t39-state.yaml"
  write_state_fixture "$s"
  capture_now
  st "$s" "$TEST_DIR/t39.log" append-run --ref slug-refs-across-tooling --role "TDD Implementation" \
    --model claude-test --started "$NOW_UTC" --tdd-tests 3 \
    || log_fail "append-run with a slug ref must exit 0 (RED today: exit 2): $(cat "$TEST_DIR/t39.log")"
  grep -qE '^    slug-refs-across-tooling:$' "$s" \
    || log_fail "metrics.work_items.<slug> entry must be auto-initialized"
  ck "$s" "$TEST_DIR/t39-ck.log" \
    || log_fail "REAL check-state must exit 0 on the slug-keyed STATE (Seam 1): $(cat "$TEST_DIR/t39-ck.log")"
  # Second append lands INSIDE the same slug entry (no duplicate key).
  st "$s" "$TEST_DIR/t39b.log" append-run --ref slug-refs-across-tooling --role Validation \
    --model claude-test --started "$NOW_UTC" \
    || log_fail "second slug append-run must exit 0: $(cat "$TEST_DIR/t39b.log")"
  local n
  n="$(grep -cE '^    slug-refs-across-tooling:$' "$s" || true)"
  [[ "$n" == "1" ]] || log_fail "exactly one metrics.work_items slug key after two appends (got $n)"
  ck "$s" "$TEST_DIR/t39b-ck.log" || log_fail "check-state after second slug append-run: $(cat "$TEST_DIR/t39b-ck.log")"
  # Init-less STATE: the slug path must scaffold metrics itself too.
  local m="$TEST_DIR/t39-min.yaml"
  write_minimal_state "$m"
  st "$m" "$TEST_DIR/t39m.log" append-run --ref slug-refs-across-tooling --role Planning \
    --model claude-test --started "$NOW_UTC" \
    || log_fail "init-less slug append-run must exit 0: $(cat "$TEST_DIR/t39m.log")"
  ck "$m" "$TEST_DIR/t39m-ck.log" || log_fail "check-state after init-less slug append-run: $(cat "$TEST_DIR/t39m-ck.log")"
  log_pass "append-run auto-inits + appends under the slug key; real check-state clean (CHANGE-0012 TEST-003)"
}

test_040_ref_shape_validation() {  # CHANGE-0012 TEST-004 / Spec-AC-03
  log_info "Test: refs matching NEITHER shape exit 2 pre-write naming both shapes; boundary slugs accepted (CHANGE-0012 TEST-004)..."
  local s="$TEST_DIR/t40-state.yaml"
  write_state_fixture "$s"
  cp "$s" "$TEST_DIR/t40-snapshot.yaml"
  capture_now
  local slug53 slug54 ec bad
  slug53="$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48)-b234"
  slug54="a${slug53}"
  [[ "${#slug53}" == 53 && "${#slug54}" == 54 ]] || log_fail "fixture guard: slug53/54 lengths wrong (${#slug53}/${#slug54})"

  # Invalid under BOTH shapes: exit 2, byte-identical, message names both shapes.
  for bad in "Mixed-Case" "has space" "$slug54" "-lead" "trail-" "a--b" "ab" ""; do
    ec=0; st "$s" "$TEST_DIR/t40-case.log" set-focus --type intake_change --ref "$bad" --path docs/x.md || ec=$?
    [[ "$ec" == 2 ]] || log_fail "set-focus --ref '$bad' must exit 2 (got $ec): $(cat "$TEST_DIR/t40-case.log")"
    grep -qF '[A-Z]+-\d+' "$TEST_DIR/t40-case.log" \
      || log_fail "usage message for '$bad' must name the display shape: $(cat "$TEST_DIR/t40-case.log")"
    grep -qF '[a-z0-9-]{3,53}' "$TEST_DIR/t40-case.log" \
      || log_fail "usage message for '$bad' must name the slug shape: $(cat "$TEST_DIR/t40-case.log")"
    ec=0; st "$s" "$TEST_DIR/t40-case.log" set-phase --ref "$bad" --phase planning || ec=$?
    [[ "$ec" == 2 ]] || log_fail "set-phase --ref '$bad' must exit 2 (got $ec)"
    ec=0; st "$s" "$TEST_DIR/t40-case.log" append-run --ref "$bad" --role Planning --model m --started "$NOW_UTC" || ec=$?
    [[ "$ec" == 2 ]] || log_fail "append-run --ref '$bad' must exit 2 (got $ec)"
    cmp -s "$s" "$TEST_DIR/t40-snapshot.yaml" \
      || log_fail "STATE must stay byte-identical after rejected ref '$bad'"
  done

  # Boundary accepts (negative controls for the reject set): 53-char slug with
  # -xxxx suffix, minimum 3-char slug, pure-digit slug (never collides: lowercase).
  for good in "$slug53" "abc" "2026-07"; do
    st "$s" "$TEST_DIR/t40-good.log" set-phase --ref "$good" --phase planning --status planned \
      || log_fail "set-phase --ref '$good' must exit 0 (valid slug): $(cat "$TEST_DIR/t40-good.log")"
  done
  ck "$s" "$TEST_DIR/t40-ck.log" || log_fail "check-state after boundary slugs: $(cat "$TEST_DIR/t40-ck.log")"

  # Review W1 (CHANGE-0012): bare YAML-keyword slugs would be re-typed by YAML
  # parsers when written unquoted (ref_id: null -> None) — refuse them exit 2,
  # byte-identical. Longer slugs CONTAINING a keyword stay valid.
  cp "$TEST_DIR/t40-snapshot.yaml" "$s"
  local kw
  for kw in null true false yes off; do
    ec=0; st "$s" "$TEST_DIR/t40-kw.log" set-focus --type intake_change --ref "$kw" --path docs/x.md || ec=$?
    [[ "$ec" == 2 ]] || log_fail "set-focus --ref '$kw' (YAML keyword) must exit 2 (got $ec)"
    grep -qi 'YAML keyword' "$TEST_DIR/t40-kw.log" \
      || log_fail "rejection for '$kw' must explain the YAML-keyword hazard: $(cat "$TEST_DIR/t40-kw.log")"
    cmp -s "$s" "$TEST_DIR/t40-snapshot.yaml" \
      || log_fail "STATE must stay byte-identical after rejected YAML-keyword ref '$kw'"
  done
  st "$s" "$TEST_DIR/t40-kw-good.log" set-phase --ref null-handling-fix --phase planning --status planned \
    || log_fail "slug CONTAINING a keyword (null-handling-fix) must stay valid: $(cat "$TEST_DIR/t40-kw-good.log")"

  log_pass "Neither-shape refs refused exit 2 naming both shapes, zero writes; boundary slugs accepted; YAML-keyword slugs refused (CHANGE-0012 TEST-004 + review W1)"
}

test_041_display_ref_regression() {  # CHANGE-0012 TEST-005 / Spec-AC-04
  log_info "Test: TYPE-000N display refs still accepted on all three subcommands (REF_RE untouched) (CHANGE-0012 TEST-005)..."
  local s="$TEST_DIR/t41-state.yaml"
  write_state_fixture "$s"
  capture_now
  st "$s" "$TEST_DIR/t41a.log" set-focus --type intake_change --ref CHANGE-0012 --path docs/issues/CHANGE-0012.md \
    || log_fail "set-focus with a display ref must stay exit 0: $(cat "$TEST_DIR/t41a.log")"
  grep -qE '^  ref_id: CHANGE-0012$' "$s" || log_fail "display ref_id must be written verbatim"
  st "$s" "$TEST_DIR/t41b.log" set-phase --ref CHANGE-0012 --phase implementation --status in_progress \
    || log_fail "set-phase with a display ref must stay exit 0: $(cat "$TEST_DIR/t41b.log")"
  st "$s" "$TEST_DIR/t41c.log" append-run --ref CHANGE-0012 --role Implementation --model claude-test --started "$NOW_UTC" \
    || log_fail "append-run with a display ref must stay exit 0: $(cat "$TEST_DIR/t41c.log")"
  ck "$s" "$TEST_DIR/t41-ck.log" || log_fail "check-state after display-ref trio: $(cat "$TEST_DIR/t41-ck.log")"
  log_pass "Display refs behave byte-identically on all three subcommands (CHANGE-0012 TEST-005)"
}

# --- CHANGE-0010 / spec-model-tiering-with-teeth ------------------------------
# test_042..046 = spec-local TEST-001..005 (set-validation --model independence
# check, D2/D3); test_047 = TEST-007 (append-run token warning, D5); test_048 =
# TEST-008 (MODEL dispatch wiring, D1); test_049 = TEST-009 (wrapper model:
# frontmatter, D6); test_050 = TEST-010 (METRICS_FLUSH wiring, D5); test_051 =
# TEST-011 (regression: real-repo audit; full-suite exit 0 is main() itself).
# TEST-006 (pricing lookup_rules) lives in tests/skills/test-aai-pricing.sh.

# Isolated fixture dir: state.mjs resolves the independence config as
# dirname(statePath)/docs-audit.yaml, so a per-test subdir gives config
# isolation for free (SPEC D3).
setup_independence_dir() {  # $1 = subdir name; echoes the dir path
  local d="$TEST_DIR/$1"
  mkdir -p "$d"
  write_state_fixture "$d/STATE.yaml"
  echo "$d"
}

# Sibling guard-policy file carrying close_gate/doc_number_guard AND
# independence together (Seam C: coexistence with the existing dials).
write_enforce_config() {  # $1 = dir
  cat > "$1/docs-audit.yaml" <<'YAML'
# fixture guard-policy file (Seam C: independence coexists with prior dials)
legacy_until_date: 2026-06-12
close_gate: report-only
doc_number_guard: report-only
independence: enforce
YAML
}

test_042_independence_warn_default() {  # CHANGE-0010 TEST-001 / Spec-AC-02
  log_info "Test: same-model verdict warns under report-only default but still writes (CHANGE-0010 TEST-001)..."
  local d s
  d="$(setup_independence_dir t42)"; s="$d/STATE.yaml"
  capture_now
  # Seam A: the implementer run is recorded by actually running append-run.
  st "$s" "$d/ar.log" append-run --ref CHANGE-0001 --role Implementation --model claude-fable-5 --started "$NOW_UTC" \
    || log_fail "fixture append-run must exit 0: $(cat "$d/ar.log")"
  st "$s" "$d/sv.log" set-validation --status pass --ref CHANGE-0001 --model claude-fable-5 \
    || log_fail "report-only violation must still exit 0 (RED today: unknown flag exit 2): $(cat "$d/sv.log")"
  grep -q 'WARNING independence violation' "$d/sv.log" \
    || log_fail "stderr must carry the WARNING independence violation line: $(cat "$d/sv.log")"
  grep -q 'validator model "claude-fable-5"' "$d/sv.log" \
    || log_fail "warning must name the validator model: $(cat "$d/sv.log")"
  grep -q 'implementer model "claude-fable-5"' "$d/sv.log" \
    || log_fail "warning must name the implementer model: $(cat "$d/sv.log")"
  grep -qE '^  status: pass$' "$s" || log_fail "verdict must still be written under report-only"
  ck "$s" "$d/ck.log" || log_fail "check-state after warned write: $(cat "$d/ck.log")"
  log_pass "Same-model verdict: WARNING on stderr, write proceeds, exit 0 (CHANGE-0010 TEST-001)"
}

test_043_independence_enforce_refusal() {  # CHANGE-0010 TEST-002 / Spec-AC-02
  log_info "Test: independence: enforce refuses the write (exit 1, byte-identical STATE) (CHANGE-0010 TEST-002)..."
  local d s ec
  d="$(setup_independence_dir t43)"; s="$d/STATE.yaml"
  capture_now
  st "$s" "$d/ar.log" append-run --ref CHANGE-0001 --role Implementation --model claude-fable-5 --started "$NOW_UTC" \
    || log_fail "fixture append-run must exit 0: $(cat "$d/ar.log")"
  write_enforce_config "$d"
  cp "$s" "$d/snapshot.yaml"
  ec=0; st "$s" "$d/sv.log" set-validation --status pass --ref CHANGE-0001 --model claude-fable-5 || ec=$?
  [[ "$ec" == 1 ]] || log_fail "enforce violation must exit 1 (got $ec): $(cat "$d/sv.log")"
  grep -q 'validator model "claude-fable-5"' "$d/sv.log" \
    || log_fail "refusal must name the validator model: $(cat "$d/sv.log")"
  grep -q 'implementer model "claude-fable-5"' "$d/sv.log" \
    || log_fail "refusal must name the implementer model: $(cat "$d/sv.log")"
  grep -q 'independence' "$d/sv.log" \
    || log_fail "refusal must name the independence config key: $(cat "$d/sv.log")"
  cmp -s "$s" "$d/snapshot.yaml" \
    || log_fail "STATE must stay byte-identical after the enforce refusal (no write)"

  # Review W1 (CHANGE-0010): a present-but-INVALID independence value must fall
  # open to report-only (write proceeds, exit 0) but must SAY SO on stderr.
  printf 'independence: enforced\n' > "$d/docs-audit.yaml"
  ec=0; st "$s" "$d/sv-typo.log" set-validation --status pass --ref CHANGE-0001 --model claude-fable-5 || ec=$?
  [[ "$ec" == 0 ]] || log_fail "invalid config value must fail open (exit 0, got $ec): $(cat "$d/sv-typo.log")"
  grep -q 'WARNING independence value "enforced"' "$d/sv-typo.log" \
    || log_fail "invalid config value must emit a stderr notice (review W1): $(cat "$d/sv-typo.log")"

  log_pass "Enforce violation: exit 1, both models + config key named, zero write; invalid value fails open WITH notice (CHANGE-0010 TEST-002 + review W1)"
}

test_044_independence_different_models() {  # CHANGE-0010 TEST-003 / Spec-AC-02
  log_info "Test: different-weights validator passes silently even under enforce (CHANGE-0010 TEST-003)..."
  local d s
  d="$(setup_independence_dir t44)"; s="$d/STATE.yaml"
  capture_now
  st "$s" "$d/ar.log" append-run --ref CHANGE-0001 --role Implementation --model claude-fable-5 --started "$NOW_UTC" \
    || log_fail "fixture append-run must exit 0: $(cat "$d/ar.log")"
  write_enforce_config "$d"
  st "$s" "$d/sv.log" set-validation --status pass --ref CHANGE-0001 --model claude-sonnet-5 \
    || log_fail "different validator model must exit 0 under enforce: $(cat "$d/sv.log")"
  grep -q 'violation' "$d/sv.log" && log_fail "no violation text expected for independent models: $(cat "$d/sv.log")"
  grep -q 'WARNING' "$d/sv.log" && log_fail "no WARNING expected for independent models: $(cat "$d/sv.log")"
  grep -qE '^  status: pass$' "$s" || log_fail "verdict must be written for the independent validator"
  ck "$s" "$d/ck.log" || log_fail "check-state after independent write: $(cat "$d/ck.log")"
  log_pass "Different weights = independent: silent pass, verdict written (CHANGE-0010 TEST-003)"
}

test_045_independence_suffix_and_case() {  # CHANGE-0010 TEST-004 / Spec-AC-02
  log_info "Test: [1m]-suffixed implementer equals its base id; comparison is case-insensitive (CHANGE-0010 TEST-004)..."
  local d s ec
  d="$(setup_independence_dir t45)"; s="$d/STATE.yaml"
  capture_now
  # Multi-run fixture: an EARLIER Implementation run with a different model —
  # the scan must use the LAST Implementation-role run.
  st "$s" "$d/ar0.log" append-run --ref CHANGE-0001 --role Implementation --model claude-sonnet-5 --started "$NOW_UTC" \
    || log_fail "fixture append-run (earlier impl) must exit 0: $(cat "$d/ar0.log")"
  st "$s" "$d/ar1.log" append-run --ref CHANGE-0001 --role "TDD Implementation" --model 'claude-opus-4-8[1m]' --started "$NOW_UTC" \
    || log_fail "fixture append-run (bracket suffix) must exit 0: $(cat "$d/ar1.log")"
  # Default (report-only): warn + write + exit 0.
  st "$s" "$d/sv1.log" set-validation --status fail --ref CHANGE-0001 --model claude-opus-4-8 \
    || log_fail "suffix-equal violation must exit 0 under default: $(cat "$d/sv1.log")"
  grep -q 'WARNING independence violation' "$d/sv1.log" \
    || log_fail "[1m] suffix must normalize EQUAL to the base id (last impl run wins): $(cat "$d/sv1.log")"
  # Case variant is still the same weights.
  st "$s" "$d/sv2.log" set-validation --status fail --ref CHANGE-0001 --model 'Claude-Opus-4-8' \
    || log_fail "case-variant violation must exit 0 under default: $(cat "$d/sv2.log")"
  grep -q 'WARNING independence violation' "$d/sv2.log" \
    || log_fail "comparison must be case-insensitive: $(cat "$d/sv2.log")"
  # Under enforce: exit 1, no write.
  write_enforce_config "$d"
  cp "$s" "$d/snapshot.yaml"
  ec=0; st "$s" "$d/sv3.log" set-validation --status pass --ref CHANGE-0001 --model claude-opus-4-8 || ec=$?
  [[ "$ec" == 1 ]] || log_fail "suffix-equal violation must exit 1 under enforce (got $ec): $(cat "$d/sv3.log")"
  cmp -s "$s" "$d/snapshot.yaml" || log_fail "STATE must stay byte-identical after enforce refusal"
  log_pass "Bracket suffix + case normalize EQUAL; warn by default, refuse under enforce (CHANGE-0010 TEST-004)"
}

test_046_independence_safe_skips() {  # CHANGE-0010 TEST-005 / Spec-AC-02
  log_info "Test: safe skips never block honest work (CHANGE-0010 TEST-005)..."
  local d s
  d="$(setup_independence_dir t46)"; s="$d/STATE.yaml"
  # (a) verdict + --model but the ref has NO Implementation-role run (fixture
  # only carries a Planning run for CHANGE-0001).
  st "$s" "$d/a.log" set-validation --status pass --ref CHANGE-0001 --model claude-x \
    || log_fail "(a) no-implementer-run skip must exit 0: $(cat "$d/a.log")"
  grep -q 'independence not checked' "$d/a.log" \
    || log_fail "(a) must print the stderr info line: $(cat "$d/a.log")"
  grep -q 'violation' "$d/a.log" && log_fail "(a) must not report a violation: $(cat "$d/a.log")"
  grep -qE '^  status: pass$' "$s" || log_fail "(a) verdict must be written"
  # (b) verdict WITHOUT --model (backward compatible).
  st "$s" "$d/b.log" set-validation --status fail --ref CHANGE-0001 \
    || log_fail "(b) verdict without --model must exit 0: $(cat "$d/b.log")"
  grep -q 'independence not checked' "$d/b.log" \
    || log_fail "(b) must print the stderr info line: $(cat "$d/b.log")"
  # (b2) unresolvable ref via the last_validation.ref_id default (fixture
  # scalar CHANGE-0001/SPEC-0001 is not a work_items key) — reset ref_id first.
  local d2 s2
  d2="$(setup_independence_dir t46b)"; s2="$d2/STATE.yaml"
  st "$s2" "$d2/b2.log" set-validation --status pass --model claude-x \
    || log_fail "(b2) unresolvable default ref must exit 0: $(cat "$d2/b2.log")"
  grep -q 'independence not checked' "$d2/b2.log" \
    || log_fail "(b2) must print the stderr info line: $(cat "$d2/b2.log")"
  # (c) --status not_run --model X never triggers the check.
  st "$s" "$d/c.log" set-validation --status not_run --model claude-x \
    || log_fail "(c) not_run must exit 0: $(cat "$d/c.log")"
  grep -q 'independence' "$d/c.log" && log_fail "(c) not_run must not touch the independence check: $(cat "$d/c.log")"
  # (d) clear-only invocation never triggers the check.
  st "$s" "$d/dd.log" set-validation --clear notes --model claude-x \
    || log_fail "(d) clear-only must exit 0: $(cat "$d/dd.log")"
  grep -q 'independence' "$d/dd.log" && log_fail "(d) clear-only must not touch the independence check: $(cat "$d/dd.log")"
  # (e) degenerate inline `agent_runs: []` — skip, never crash.
  cat > "$d/STATE2.yaml" <<'YAML'
project_status: active
last_validation:
  status: not_run
metrics:
  work_items:
    CHANGE-0002:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs: []
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  st "$d/STATE2.yaml" "$d/e.log" set-validation --status pass --ref CHANGE-0002 --model claude-x \
    || log_fail "(e) inline empty agent_runs must skip safely exit 0: $(cat "$d/e.log")"
  grep -q 'independence not checked' "$d/e.log" \
    || log_fail "(e) must print the stderr info line: $(cat "$d/e.log")"
  ck "$s" "$d/ck.log" || log_fail "check-state after skip-path writes: $(cat "$d/ck.log")"
  log_pass "Safe skips (no impl run / no --model / bad ref / not_run / clear-only / empty runs) all exit 0 (CHANGE-0010 TEST-005)"
}

test_047_append_run_token_warning() {  # CHANGE-0010 TEST-007 / Spec-AC-04
  log_info "Test: append-run persists integer tokens; omitting them warns ONCE on stderr, exit 0 (CHANGE-0010 TEST-007)..."
  local s="$TEST_DIR/t47-state.yaml" n
  write_state_fixture "$s"
  capture_now
  # Tokens provided: persisted as integers, NO warning.
  st "$s" "$TEST_DIR/t47a.log" append-run --ref CHANGE-0001 --role Implementation --model claude-test \
    --started "$NOW_UTC" --tokens-in 1200 --tokens-out 340 \
    || log_fail "append-run with tokens must exit 0: $(cat "$TEST_DIR/t47a.log")"
  grep -qE '^ {10}tokens_in: 1200$' "$s" || log_fail "tokens_in must persist as integer 1200"
  grep -qE '^ {10}tokens_out: 340$' "$s" || log_fail "tokens_out must persist as integer 340"
  grep -q 'WARNING tokens_in/tokens_out null' "$TEST_DIR/t47a.log" \
    && log_fail "no token warning expected when both tokens are supplied: $(cat "$TEST_DIR/t47a.log")"
  # Tokens omitted: exit 0 AND exactly ONE stderr warning line.
  st "$s" "$TEST_DIR/t47b.log" append-run --ref CHANGE-0001 --role Validation --model claude-test --started "$NOW_UTC" \
    || log_fail "append-run without tokens must still exit 0 (warn, never block): $(cat "$TEST_DIR/t47b.log")"
  n="$(grep -c 'WARNING tokens_in/tokens_out null' "$TEST_DIR/t47b.log" || true)"
  [[ "$n" == "1" ]] || log_fail "exactly ONE token warning line expected (got $n): $(cat "$TEST_DIR/t47b.log")"
  grep -q 'role=Validation' "$TEST_DIR/t47b.log" || log_fail "warning must name the role: $(cat "$TEST_DIR/t47b.log")"
  # Partial supply (only --tokens-in) still warns.
  st "$s" "$TEST_DIR/t47c.log" append-run --ref CHANGE-0001 --role Planning --model claude-test \
    --started "$NOW_UTC" --tokens-in 10 \
    || log_fail "partial-token append-run must exit 0: $(cat "$TEST_DIR/t47c.log")"
  grep -q 'WARNING tokens_in/tokens_out null' "$TEST_DIR/t47c.log" \
    || log_fail "partial token supply must still warn: $(cat "$TEST_DIR/t47c.log")"
  ck "$s" "$TEST_DIR/t47-ck.log" || log_fail "check-state after token appends: $(cat "$TEST_DIR/t47-ck.log")"
  log_pass "Integer tokens persisted; omission warns once and exits 0 (CHANGE-0010 TEST-007)"
}

test_048_model_dispatch_wiring() {  # CHANGE-0010 TEST-008 / Spec-AC-01
  log_info "Test: MODEL is a documented required dispatch field (grep wiring) (CHANGE-0010 TEST-008)..."
  grep -qE '^\| .MODEL. \|' "$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md" \
    || log_fail "SUBAGENT_PROTOCOL.md contract table must carry a MODEL row"
  grep -q '^MODEL SELECTION' "$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md" \
    || log_fail "ORCHESTRATION.prompt.md must keep its MODEL SELECTION section"
  grep -q '^MODEL SELECTION' "$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md" \
    || log_fail "ORCHESTRATION_PARALLEL.prompt.md must gain the MODEL SELECTION section"
  grep -q 'VALIDATOR INDEPENDENCE' "$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md" \
    || log_fail "ORCHESTRATION_PARALLEL.prompt.md must carry the validator independence rule"
  grep -q 'Scope, Role, Model, Inputs' "$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md" \
    || log_fail "PARALLEL OUTPUT FORMAT workstream fields must include Model"
  grep -q 'Model: per MODEL SELECTION' "$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md" \
    || log_fail "PARALLEL SUBAGENT EXECUTION dispatch fields must include MODEL"
  log_pass "MODEL dispatch-contract wiring present in protocol + both orchestration prompts (CHANGE-0010 TEST-008)"
}

test_049_wrapper_model_frontmatter() {  # CHANGE-0010 TEST-009 / Spec-AC-05
  log_info "Test: >=3 skill wrappers carry model: frontmatter; the 4 D6 wrappers pin model: haiku (CHANGE-0010 TEST-009)..."
  local count w
  count="$( (grep -l '^model:' "$PROJECT_ROOT"/.claude/skills/*/SKILL.md 2>/dev/null || true) | wc -l | tr -d ' ')"
  [[ "$count" -ge 3 ]] || log_fail "expected >=3 wrappers with model: frontmatter (got $count)"
  for w in aai-intake aai-check-state aai-flush aai-validate-report; do
    sed -n '1,/^---$/p' "$PROJECT_ROOT/.claude/skills/$w/SKILL.md" | tail -n +2 | grep -q '^model: haiku$' \
      || log_fail "$w/SKILL.md must carry model: haiku in its YAML frontmatter"
  done
  log_pass "Wrapper model: frontmatter present ($count wrappers; 4 D6 wrappers pinned haiku) (CHANGE-0010 TEST-009)"
}

test_050_flush_prompt_token_wiring() {  # CHANGE-0010 TEST-010 / Spec-AC-04
  log_info "Test: METRICS_FLUSH prompt mandates null-token report warning + lookup_rules pricing resolution (CHANGE-0010 TEST-010)..."
  local f="$PROJECT_ROOT/.aai/METRICS_FLUSH.prompt.md"
  grep -q 'cost unattributable' "$f" \
    || log_fail "flush prompt must mandate the visible 'cost unattributable — tokens not recorded' warning line"
  grep -q 'lookup_rules' "$f" \
    || log_fail "flush prompt pricing step must reference PRICING.yaml lookup_rules"
  grep -qi 'bracket suffix' "$f" \
    || log_fail "flush prompt must call out suffix normalization before lookup"
  log_pass "Flush prompt carries the null-token warning contract and lookup_rules reference (CHANGE-0010 TEST-010)"
}

test_051_change0010_regression() {  # CHANGE-0010 TEST-011 / Spec-AC-05
  log_info "Test: real-repo docs-audit stays CLEAN with the CHANGE-0010 docs; pricing suite present (CHANGE-0010 TEST-011)..."
  local ec=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t51-audit.log" 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "docs-audit --check --strict --no-event must exit 0 (got $ec): $(tail -10 "$TEST_DIR/t51-audit.log")"
  [[ -f "$PROJECT_ROOT/tests/skills/test-aai-pricing.sh" ]] \
    || log_fail "tests/skills/test-aai-pricing.sh (CHANGE-0010 TEST-006 suite) must exist"
  log_pass "Docs stay audit-CLEAN; pricing suite wired (CHANGE-0010 TEST-011; full-suite exit 0 = this run)"
}

main() {
  echo "Testing $TEST_NAME (transactional STATE CLI — SPEC-0012 TEST-001..025 + SPEC-0014 additions)"
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
  test_026_clear_worktree_stale
  test_027_clear_across_subcommands
  test_028_clear_guard_bypass_refused
  test_029_clear_strict_validation
  test_030_clear_idempotent_and_missing
  test_031_spec_path_placement
  test_032_spec_path_fallback_and_upsert
  test_033_spec0014_regression_backstop
  test_034_clear_prototype_names_refused
  test_035_clear_repeated_flag_accumulates
  test_036_clear_blankline_folded_scalar
  test_037_slug_set_focus
  test_038_slug_set_phase
  test_039_slug_append_run_checkstate
  test_040_ref_shape_validation
  test_041_display_ref_regression
  test_042_independence_warn_default
  test_043_independence_enforce_refusal
  test_044_independence_different_models
  test_045_independence_suffix_and_case
  test_046_independence_safe_skips
  test_047_append_run_token_warning
  test_048_model_dispatch_wiring
  test_049_wrapper_model_frontmatter
  test_050_flush_prompt_token_wiring
  test_051_change0010_regression
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
