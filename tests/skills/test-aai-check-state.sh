#!/usr/bin/env bash
#
# Test: aai-check-state validator (ISSUE-0004 / SPEC-0010 Group B)
# Verifies .aai/scripts/check-state.mjs detects duplicate top-level keys in
# STATE.yaml (esp. a second `metrics:`) and that --repair merges the duplicate
# metrics blocks with ZERO agent_runs lost. Pure text scan — no YAML dependency.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-check-state"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_SCRIPT="$PROJECT_ROOT/.aai/scripts/check-state.mjs"

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
  [[ -f "$CHECK_SCRIPT" ]] || log_fail "check-state script not found: $CHECK_SCRIPT"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-check-state-test.XXXXXX")"
}

# A well-formed single-metrics STATE (exactly one of every top-level key).
write_clean_state() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: none
  ref_id: null
metrics:
  work_items:
    ISSUE-0003:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-test
          note: run-r1
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

# A STATE carrying a duplicate top-level `metrics:` key. Block A holds
# ISSUE-X.agent_runs=[r1]; block B holds ISSUE-X.agent_runs=[r2] plus
# ISSUE-Y.agent_runs=[r3]. A lenient YAML load would keep only block B (r1 lost).
write_dup_metrics_state() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: none
  ref_id: null
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
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-test
          note: run-r2
    ISSUE-Y:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-test
          note: run-r3
updated_at_utc: 2026-07-01T00:00:00Z
YAML
}

test_detect_duplicate_metrics() {  # TEST-004 / Spec-AC-04
  log_info "Test: check-state.mjs detects a duplicate top-level metrics key, clean STATE exits 0 (TEST-004)..."
  local dup="$TEST_DIR/state-dup.yaml" clean="$TEST_DIR/state-clean.yaml"
  write_dup_metrics_state "$dup"
  write_clean_state "$clean"

  # Clean STATE -> exit 0.
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$clean" > "$TEST_DIR/clean.log" 2>&1) \
    || log_fail "clean STATE (one metrics key) must exit 0: $(cat "$TEST_DIR/clean.log")"

  # Duplicate metrics -> exit non-zero, message names the duplicated key.
  if (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$dup" > "$TEST_DIR/dup.log" 2>&1); then
    log_fail "duplicate top-level metrics key must exit non-zero"
  fi
  grep -qF "metrics" "$TEST_DIR/dup.log" \
    || log_fail "failure message must name the duplicated key (metrics): $(cat "$TEST_DIR/dup.log")"
  log_pass "Duplicate top-level metrics detected (fail loud); clean STATE passes"
}

test_repair_merges_no_data_loss() {  # TEST-005 / Spec-AC-05
  log_info "Test: --repair merges duplicate metrics blocks with ZERO agent_runs lost (TEST-005)..."
  local dup="$TEST_DIR/state-repair.yaml"
  write_dup_metrics_state "$dup"

  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs --repair "$dup" > "$TEST_DIR/repair.log" 2>&1) \
    || log_fail "--repair must succeed and re-validate exit 0: $(cat "$TEST_DIR/repair.log")"

  # Exactly one top-level metrics key after repair.
  local metrics_keys
  metrics_keys="$(grep -cE '^metrics:' "$dup" || true)"
  [[ "$metrics_keys" == "1" ]] \
    || log_fail "repaired STATE must have exactly one top-level metrics key (got $metrics_keys)"

  # ZERO agent_runs lost: all three runs present, total run count preserved (3).
  grep -qF "run-r1" "$dup" || log_fail "run-r1 (block A) must survive the merge (no data loss)"
  grep -qF "run-r2" "$dup" || log_fail "run-r2 (block B) must survive the merge"
  grep -qF "run-r3" "$dup" || log_fail "run-r3 (block B, new work item) must survive the merge"
  local run_count
  run_count="$(grep -cE '^ {8}- role:' "$dup" || true)"
  [[ "$run_count" == "3" ]] \
    || log_fail "merged STATE must carry exactly 3 agent_runs (X:[r1,r2], Y:[r3]); got $run_count"

  # Re-validation of the repaired file exits 0.
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$dup" > "$TEST_DIR/revalidate.log" 2>&1) \
    || log_fail "re-validation after repair must exit 0: $(cat "$TEST_DIR/revalidate.log")"
  log_pass "Repair unions work_items + concatenates agent_runs (X:[r1,r2], Y:[r3]); zero loss; re-validate clean"
}

test_repair_inline_agent_runs() {  # TEST-011 / Codex P2 (ISSUE-0004 self-fix)
  log_info "Test: --repair of a ref auto-initialized with inline 'agent_runs: []' + a dup block leaves NO duplicate nested agent_runs (TEST-011)..."
  local dup="$TEST_DIR/state-inline.yaml"
  cat > "$dup" <<'YAML'
project_status: active
metrics:
  work_items:
    ISSUE-9001:
      human_time_minutes:
        intake: null
      agent_runs: []
updated_at_utc: 2026-07-01T00:00:00Z
metrics:
  work_items:
    ISSUE-9001:
      agent_runs:
        - role: run-inline-a
          model_id: x
        - role: run-inline-b
          model_id: y
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs --repair "$dup" > "$TEST_DIR/inline-repair.log" 2>&1) \
    || log_fail "--repair must succeed on the inline-agent_runs case: $(cat "$TEST_DIR/inline-repair.log")"
  # Exactly ONE nested agent_runs line for the ref (the Codex P2 bug emitted two:
  # the inline `agent_runs: []` AND a block-form `agent_runs:`).
  local ar_count
  ar_count="$(grep -cE '^ {6}agent_runs:' "$dup" || true)"
  [[ "$ar_count" == "1" ]] \
    || log_fail "repaired STATE must have exactly ONE nested agent_runs: for the ref (got $ar_count — duplicate nested key)"
  grep -qF "run-inline-a" "$dup" || log_fail "run-inline-a must survive (no data loss)"
  grep -qF "run-inline-b" "$dup" || log_fail "run-inline-b must survive (no data loss)"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$dup" > "$TEST_DIR/inline-reval.log" 2>&1) \
    || log_fail "re-validate after inline-agent_runs repair must exit 0: $(cat "$TEST_DIR/inline-reval.log")"
  log_pass "Inline 'agent_runs: []' + dup block merges to ONE canonical agent_runs, both runs kept, re-validate clean"
}

test_prevention_wiring_present() {  # TEST-006 / Spec-AC-06
  log_info "Test: SKILL_CHECK_STATE [INV-14] + role-prompt append-into-existing guidance present (TEST-006)..."
  local skill="$PROJECT_ROOT/.aai/SKILL_CHECK_STATE.prompt.md"
  [[ -f "$skill" ]] || log_fail "missing $skill"
  grep -qF "[INV-14]" "$skill" \
    || log_fail "SKILL_CHECK_STATE.prompt.md must document invariant [INV-14]"
  grep -qiF "duplicate top-level key" "$skill" \
    || log_fail "[INV-14] must describe the duplicate top-level key invariant"
  grep -qF "check-state.mjs --repair" "$skill" \
    || log_fail "[INV-14] must point at check-state.mjs --repair"

  # Since CHANGE-0011 the append-into-existing / never-emit-a-second-metrics
  # guidance is single-sourced in .aai/STATE_FALLBACK.md; role prompts carry a
  # short fallback pointer at it instead of the inlined footer.
  local fb="$PROJECT_ROOT/.aai/STATE_FALLBACK.md"
  [[ -f "$fb" ]] || log_fail "missing $fb (single-source fallback doc, CHANGE-0011)"
  grep -qF "never emit a second top-level" "$fb" \
    || log_fail "STATE_FALLBACK.md must warn: never emit a second top-level metrics: key"
  grep -qF "EXISTING" "$fb" && grep -qF "metrics.work_items" "$fb" \
    || log_fail "STATE_FALLBACK.md must instruct appending into the EXISTING metrics.work_items"
  local found=0
  for p in "$PROJECT_ROOT/.aai/IMPLEMENTATION.prompt.md" "$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"; do
    [[ -f "$p" ]] || log_fail "missing role prompt $p"
    grep -qF "STATE_FALLBACK.md" "$p" \
      || log_fail "role prompt must point at .aai/STATE_FALLBACK.md for the hand-edit fallback ($p)"
    found=$((found + 1))
  done
  [[ "$found" -ge 1 ]] || log_fail "no role prompt carried the fallback pointer"
  log_pass "[INV-14] invariant + single-sourced fallback guidance wired (STATE_FALLBACK.md + role-prompt pointers)"
}

test_no_regression_real_state() {  # TEST-010 (check-state half) / Spec-AC-10
  log_info "Test: real repo STATE.yaml (if present) validates clean (TEST-010)..."
  local real="$PROJECT_ROOT/docs/ai/STATE.yaml"
  if [[ -f "$real" ]]; then
    (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs docs/ai/STATE.yaml > "$TEST_DIR/real.log" 2>&1) \
      || log_fail "real repo STATE.yaml must validate clean (no duplicate top-level key): $(cat "$TEST_DIR/real.log")"
    log_pass "Real repo STATE.yaml has no duplicate top-level key"
  else
    log_info "no real STATE.yaml present (per-dev, gitignored) — skipping real-repo check"
    log_pass "check-state real-repo check skipped (no STATE.yaml)"
  fi
}

main() {
  echo "Testing $TEST_NAME skill (STATE duplicate-key validator)"
  check_deps
  setup_fixture
  test_detect_duplicate_metrics
  test_repair_merges_no_data_loss
  test_repair_inline_agent_runs
  test_prevention_wiring_present
  test_no_regression_real_state
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
