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

test_list_indent_lint() {  # ISSUE-0007 TEST-002 / Spec-AC-02
  log_info "Test: structural list-indent lint — mis-indented sibling fails LOUD; uniform lists + nested shapes pass (ISSUE-0007 TEST-002)..."
  local bad="$TEST_DIR/state-lint-bad.yaml"
  # The exact 2026-07-15 corruption class: sibling appended 2 spaces past the
  # key under a list whose items sit 4 spaces past the key (line 6 is the bad one).
  cat > "$bad" <<'YAML'
project_status: active
code_review:
  required: true
  report_paths:
      - docs/ai/reviews/r1.md
    - docs/ai/reviews/r2.md
  notes: null
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  if (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$bad" > "$TEST_DIR/lint-bad.log" 2>&1); then
    log_fail "mis-indented list sibling must exit non-zero (this class parsed clean pre-ISSUE-0007)"
  fi
  grep -qF "report_paths" "$TEST_DIR/lint-bad.log" \
    || log_fail "lint failure must name the offending key (report_paths): $(cat "$TEST_DIR/lint-bad.log")"
  grep -qE "line 6" "$TEST_DIR/lint-bad.log" \
    || log_fail "lint failure must name the offending line number (6): $(cat "$TEST_DIR/lint-bad.log")"
  grep -qiE "indent" "$TEST_DIR/lint-bad.log" \
    || log_fail "lint failure must describe the indent mismatch: $(cat "$TEST_DIR/lint-bad.log")"

  # Same class in last_validation.evidence_paths is caught too.
  local bad2="$TEST_DIR/state-lint-bad2.yaml"
  cat > "$bad2" <<'YAML'
project_status: active
last_validation:
  status: not_run
  evidence_paths:
      - docs/ai/tdd/green-a.log
    - docs/ai/tdd/green-b.log
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  if (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$bad2" > "$TEST_DIR/lint-bad2.log" 2>&1); then
    log_fail "mis-indented evidence_paths sibling must exit non-zero"
  fi
  grep -qF "evidence_paths" "$TEST_DIR/lint-bad2.log" \
    || log_fail "lint failure must name evidence_paths: $(cat "$TEST_DIR/lint-bad2.log")"

  # Uniform engine-convention list (key+2) passes.
  local ok1="$TEST_DIR/state-lint-ok1.yaml"
  cat > "$ok1" <<'YAML'
project_status: active
code_review:
  report_paths:
    - docs/ai/reviews/r1.md
    - docs/ai/reviews/r2.md
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$ok1" > "$TEST_DIR/lint-ok1.log" 2>&1) \
    || log_fail "uniform key+2 list must pass: $(cat "$TEST_DIR/lint-ok1.log")"

  # Uniform DEEP list (key+4 — legal YAML another writer may emit) passes.
  local ok2="$TEST_DIR/state-lint-ok2.yaml"
  cat > "$ok2" <<'YAML'
project_status: active
code_review:
  report_paths:
      - docs/ai/reviews/r1.md
      - docs/ai/reviews/r2.md
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$ok2" > "$TEST_DIR/lint-ok2.log" 2>&1) \
    || log_fail "uniform key+4 list must pass (lint binds siblings to the FIRST item, not to a fixed convention): $(cat "$TEST_DIR/lint-ok2.log")"

  # Realistic nested shapes (active_work_items item maps, agent_runs items with
  # continuation lines and a nested key) must produce NO false positives.
  local ok3="$TEST_DIR/state-lint-ok3.yaml"
  cat > "$ok3" <<'YAML'
# docs/ai/STATE.yaml - fixture
#   updated_at_utc: (schema header trap)
project_status: active
active_work_items:
  - ref_id: CHANGE-0001
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0001.md
  - ref_id: ISSUE-0007
    status: in_progress
    phase: implementation
last_validation:
  status: not_run
  evidence_paths:
    - docs/ai/tdd/green-a.log
    - docs/ai/tdd/green-b.log
metrics:
  work_items:
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-test
          note: run-1
        - role: Implementation
          model_id: claude-test
          note: run-2
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$ok3" > "$TEST_DIR/lint-ok3.log" 2>&1) \
    || log_fail "nested item-map/agent_runs shapes must not false-positive: $(cat "$TEST_DIR/lint-ok3.log")"
  log_pass "List-indent lint: mis-indented siblings fail loud with key+line; uniform and nested shapes pass (ISSUE-0007 TEST-002)"
}

test_orphan_item_lint() {  # ISSUE-0007 TEST-008 / Spec-AC-06 (remediation)
  log_info "Test: orphaned-item lint — \`- \` at a key's own indent after its inline value fails LOUD; legal 0-relative lists pass (ISSUE-0007 TEST-008)..."
  # The exact validation-ISSUE-0007-20260715T233312Z probe (d) corruption: a
  # whole-field rewrite over a 0-relative list wrote `report_paths: []` and
  # left the old item orphaned directly below (line 5). BLOCK_KEY_RE never
  # matched the inline-valued key, so the pre-remediation lint exited 0.
  local bad="$TEST_DIR/state-orphan-bad.yaml"
  cat > "$bad" <<'YAML'
project_status: active
code_review:
  status: not_run
  report_paths: []
  - docs/ai/reviews/orphan.md
  notes: null
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  if (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$bad" > "$TEST_DIR/orphan-bad.log" 2>&1); then
    log_fail "orphaned item below an inline-valued key must exit non-zero (pre-remediation lint hole)"
  fi
  grep -qF "report_paths" "$TEST_DIR/orphan-bad.log" \
    || log_fail "orphan lint must name the offending key (report_paths): $(cat "$TEST_DIR/orphan-bad.log")"
  grep -qE "line 5" "$TEST_DIR/orphan-bad.log" \
    || log_fail "orphan lint must name the offending line number (5): $(cat "$TEST_DIR/orphan-bad.log")"

  # RED-D shape: bare key, first item DEEPER, then shallower orphans at the
  # key's own indent (a pre-remediation setField over a populated 0-relative
  # list wrote the new deeper items and orphaned the old ones below).
  local bad2="$TEST_DIR/state-orphan-bad2.yaml"
  cat > "$bad2" <<'YAML'
project_status: active
last_validation:
  status: not_run
  evidence_paths:
    - docs/ai/tdd/green-c.log
  - docs/ai/tdd/orphan-a.log
  - docs/ai/tdd/orphan-b.log
  notes: null
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  if (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$bad2" > "$TEST_DIR/orphan-bad2.log" 2>&1); then
    log_fail "shallower orphans at the key's own indent must exit non-zero"
  fi
  grep -qF "evidence_paths" "$TEST_DIR/orphan-bad2.log" \
    || log_fail "lint must name evidence_paths: $(cat "$TEST_DIR/orphan-bad2.log")"
  grep -qE "line 6" "$TEST_DIR/orphan-bad2.log" \
    || log_fail "lint must name the first orphan line (6): $(cat "$TEST_DIR/orphan-bad2.log")"

  # LEGAL 0-relative block sequences (the metrics suite's own fixture shape:
  # items at the SAME column as their bare key), folded scalars with
  # continuation lines, and nested orchestration shapes must all pass.
  local ok="$TEST_DIR/state-orphan-ok.yaml"
  cat > "$ok" <<'YAML'
project_status: active
code_review:
  status: not_run
  report_paths:
  - docs/ai/reviews/r1.md
  - docs/ai/reviews/r2.md
  notes: null
last_validation:
  status: not_run
  evidence_paths:
  - docs/ai/tdd/green-a.log
  notes: >-
    a folded scalar
    with continuation lines
orchestration:
  mode: single
  k: 1
  groups:
  - kind: sequential
    scopes:
    - null
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
  - ref_id: ISSUE-0007
    status: in_progress
    phase: implementation
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$ok" > "$TEST_DIR/orphan-ok.log" 2>&1) \
    || log_fail "legal 0-relative lists / folded scalars / nested shapes must not false-positive: $(cat "$TEST_DIR/orphan-ok.log")"
  log_pass "Orphaned-item lint: inline-value + equal-indent item fails loud with key+line; legal 0-relative shapes pass (ISSUE-0007 TEST-008)"
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
  test_list_indent_lint
  test_orphan_item_lint
  test_no_regression_real_state
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
