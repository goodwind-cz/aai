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
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
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

test_repair_creates_missing_state_from_template() {  # TEST-001 / Spec-AC-01 (spec-state-bootstrap-template)
  log_info "Test: --repair on a MISSING target creates it from .aai/templates/STATE_TEMPLATE.yaml and dispatch yields no_focus_ref, never state_file_missing (TEST-001)..."
  local template="$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml"
  [[ -f "$template" ]] || log_fail "missing $template"

  local missing="$TEST_DIR/nested/docs/ai/STATE.yaml"
  [[ -e "$missing" ]] && log_fail "fixture precondition: $missing must not pre-exist"

  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs --repair "$missing" > "$TEST_DIR/create.log" 2>&1) \
    || log_fail "--repair on a missing target must exit 0: $(cat "$TEST_DIR/create.log")"
  [[ -f "$missing" ]] || log_fail "--repair must create the target file (including parent dirs)"
  grep -qiF "created from template" "$TEST_DIR/create.log" \
    || log_fail "--repair creation must print a clear 'created from template' line: $(cat "$TEST_DIR/create.log")"

  # Byte-equal to the template EXCEPT the stamped updated_at_utc line.
  local norm_actual="$TEST_DIR/actual-normalized.yaml" norm_template="$TEST_DIR/template-normalized.yaml"
  sed 's/^updated_at_utc:.*/updated_at_utc: NORMALIZED/' "$missing" > "$norm_actual"
  sed 's/^updated_at_utc:.*/updated_at_utc: NORMALIZED/' "$template" > "$norm_template"
  diff -q "$norm_template" "$norm_actual" >/dev/null \
    || log_fail "created STATE must be byte-equal to the template modulo the stamped updated_at_utc line: $(diff "$norm_template" "$norm_actual")"
  grep -qE '^updated_at_utc: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$missing" \
    || log_fail "created STATE must stamp updated_at_utc with a real ISO 8601 UTC timestamp (no placeholder left behind): $(grep '^updated_at_utc:' "$missing")"

  # Dispatch on the created file yields no_focus_ref, not state_file_missing.
  local dispatch_out="$TEST_DIR/dispatch.json" dispatch_exit=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/orchestration-dispatch.mjs --state "$missing" --root "$PROJECT_ROOT" > "$dispatch_out" 2>"$TEST_DIR/dispatch.err") || dispatch_exit=$?
  [[ "$dispatch_exit" == "4" ]] \
    || log_fail "dispatch on the created STATE must exit 4 (needs_llm): got $dispatch_exit ($(cat "$TEST_DIR/dispatch.err"))"
  grep -qF "no_focus_ref" "$dispatch_out" \
    || log_fail "dispatch verdict on the created STATE must name reason no_focus_ref: $(cat "$dispatch_out")"
  grep -qF "state_file_missing" "$dispatch_out" \
    && log_fail "dispatch verdict must NOT report state_file_missing once the file has been created: $(cat "$dispatch_out")"
  # First append-run on the created file must extend metrics.work_items in
  # place — the {} form corrupted it (duplicate inner key + orphaned {}).
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$missing" set-focus --type intake_change --ref pin-demo --path docs/issues/x.md > /dev/null 2>&1) \
    || log_fail "set-focus on the created STATE must succeed"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$missing" append-run --ref pin-demo --role "Planning" --model claude-haiku-4-5 --started 2026-01-01T00:00:00Z > /dev/null 2>&1) \
    || log_fail "first append-run on the created STATE must succeed"
  [[ "$(grep -c '^  work_items:' "$missing")" -eq 1 ]] \
    || log_fail "first append-run must not duplicate the work_items key: $(grep -n 'work_items' "$missing")"
  grep -v '^\s*#' "$missing" | grep -q '{}' && log_fail "no orphaned {} may remain after the first append-run: $(grep -n '{}' "$missing" | grep -v '#')"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$missing" > /dev/null 2>&1) \
    || log_fail "created STATE must still validate after the first append-run"
  log_pass "--repair on a missing target creates the STATE file from the template (stamped, template-parity), dispatch yields no_focus_ref, and the first append-run extends metrics cleanly"
}

test_template_header_matches_live_state() {  # TEST-002 / Spec-AC-02 (spec-state-bootstrap-template)
  log_info "Test: STATE_TEMPLATE.yaml's leading comment header byte-equals the live docs/ai/STATE.yaml header, when a live file exists (TEST-002)..."
  local template="$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml"
  local live="$PROJECT_ROOT/docs/ai/STATE.yaml"
  [[ -f "$template" ]] || log_fail "missing $template"
  if [[ ! -f "$live" ]]; then
    log_info "no live docs/ai/STATE.yaml present (per-dev, gitignored) — skipping header-parity check"
    log_pass "template/live header-parity check skipped (no live STATE.yaml)"
    return
  fi
  # The header is the leading contiguous run of comment ('#') lines.
  local header_lines
  header_lines="$(awk '/^#/{print; next} {exit}' "$template" | wc -l | tr -d ' ')"
  [[ "$header_lines" -gt 0 ]] || log_fail "template has no leading comment header block"
  local tmpl_header="$TEST_DIR/tmpl-header.txt" live_header="$TEST_DIR/live-header.txt"
  head -n "$header_lines" "$template" > "$tmpl_header"
  head -n "$header_lines" "$live" > "$live_header"
  diff -q "$tmpl_header" "$live_header" >/dev/null \
    || log_fail "template header (first $header_lines lines) must byte-equal the live STATE.yaml header: $(diff "$tmpl_header" "$live_header" | head -20)"
  log_pass "Template schema header byte-equals the live docs/ai/STATE.yaml header ($header_lines lines)"
}

test_template_standalone_parses_and_carries_canonical_keys() {  # TEST-003 / Spec-AC-02 (spec-state-bootstrap-template)
  log_info "Test: STATE_TEMPLATE.yaml parses under check-state's structural loader and carries every canonical top-level key (TEST-003)..."
  local template="$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml"
  [[ -f "$template" ]] || log_fail "missing $template"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$template" > "$TEST_DIR/template-parse.log" 2>&1) \
    || log_fail "template must parse clean under check-state.mjs (no duplicate/mis-indented/orphaned structure): $(cat "$TEST_DIR/template-parse.log")"
  local key
  for key in project_status current_focus active_work_items implementation_strategy worktree code_review last_validation updated_at_utc; do
    grep -qE "^${key}:" "$template" \
      || log_fail "template must carry canonical top-level key '$key'"
  done
  log_pass "Template parses clean and carries every canonical top-level key"
}

test_skill_check_state_names_template_as_authoritative() {  # TEST-004 / Spec-AC-02 (spec-state-bootstrap-template)
  log_info "Test: SKILL_CHECK_STATE.prompt.md's AUTHORITATIVE SCHEMA paragraph names the template as the canonical schema source (TEST-004)..."
  local skill="$PROJECT_ROOT/.aai/SKILL_CHECK_STATE.prompt.md"
  [[ -f "$skill" ]] || log_fail "missing $skill"
  local para
  para="$(awk '/^AUTHORITATIVE SCHEMA$/{flag=1; next} flag && /^$/{exit} flag' "$skill")"
  [[ -n "$para" ]] || log_fail "AUTHORITATIVE SCHEMA paragraph not found in $skill"
  assert_payload_contains "$para" ".aai/templates/STATE_TEMPLATE.yaml" "AUTHORITATIVE SCHEMA paragraph must name .aai/templates/STATE_TEMPLATE.yaml as the canonical schema source: $para"
  echo "$para" | grep -qiF "gitignored" \
    || log_fail "AUTHORITATIVE SCHEMA paragraph should explain docs/ai/STATE.yaml is gitignored on a fresh checkout (why the template, not the live file, is canonical): $para"
  log_pass "SKILL_CHECK_STATE.prompt.md names the template as the authoritative schema source"
}

test_repair_existing_file_untouched_by_creation_path() {  # TEST-005 / Spec-AC-03 (spec-state-bootstrap-template, regression)
  log_info "Test: --repair on an EXISTING, already-clean STATE file never takes the create-from-template path (byte-unchanged) (TEST-005)..."
  local existing="$TEST_DIR/state-existing-clean.yaml"
  write_clean_state "$existing"
  local before="$TEST_DIR/state-existing-clean.before.yaml"
  cp "$existing" "$before"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs --repair "$existing" > "$TEST_DIR/repair-existing.log" 2>&1) \
    || log_fail "--repair on an already-clean existing file must exit 0: $(cat "$TEST_DIR/repair-existing.log")"
  diff -q "$before" "$existing" >/dev/null \
    || log_fail "--repair on an already-clean EXISTING file must not rewrite it (create-from-template must never fire when the file already exists): $(diff "$before" "$existing")"
  grep -qiF "created from template" "$TEST_DIR/repair-existing.log" \
    && log_fail "an EXISTING file's --repair run must never print the create-from-template message: $(cat "$TEST_DIR/repair-existing.log")"
  log_pass "--repair on an existing clean file is a byte-unchanged no-op; the create-from-template path never fires"
}

test_create_fail_loud_missing_template() {  # TEST-006 / review pin: absent template -> exit 2, clear ERROR, no file created
  log_info "Test: --repair on a missing target with an ABSENT template exits 2 with a clear ERROR and creates nothing (TEST-006)..."
  local sandbox="$TEST_DIR/no-template"
  mkdir -p "$sandbox/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/check-state.mjs" "$sandbox/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/lib/state-core.mjs" "$sandbox/.aai/scripts/lib/"
  # deliberately NO .aai/templates/STATE_TEMPLATE.yaml sibling
  local rc=0
  (cd "$sandbox" && node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml > "$TEST_DIR/no-template.log" 2>&1) || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "absent template must exit 2, got $rc: $(cat "$TEST_DIR/no-template.log")"
  grep -q "ERROR:" "$TEST_DIR/no-template.log" || log_fail "absent template must print a clear ERROR line: $(cat "$TEST_DIR/no-template.log")"
  [[ ! -e "$sandbox/docs/ai/STATE.yaml" ]] || log_fail "absent template must never create a STATE file"
  log_pass "absent template fails loud (exit 2, ERROR named, nothing created) (TEST-006)"
}

test_create_fail_loud_missing_placeholder() {  # TEST-007 / review pin: template without the stamp placeholder -> exit 1, refusal, no file
  log_info "Test: --repair refuses (exit 1) a template missing the updated_at_utc placeholder and creates nothing (TEST-007)..."
  local sandbox="$TEST_DIR/bad-template"
  mkdir -p "$sandbox/.aai/scripts/lib" "$sandbox/.aai/templates"
  cp "$PROJECT_ROOT/.aai/scripts/check-state.mjs" "$sandbox/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/lib/state-core.mjs" "$sandbox/.aai/scripts/lib/"
  sed '/^updated_at_utc: TEMPLATE_PLACEHOLDER$/d' "$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml" \
    > "$sandbox/.aai/templates/STATE_TEMPLATE.yaml"
  local rc=0
  (cd "$sandbox" && node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml > "$TEST_DIR/bad-template.log" 2>&1) || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "placeholder-less template must exit 1, got $rc: $(cat "$TEST_DIR/bad-template.log")"
  grep -q "placeholder" "$TEST_DIR/bad-template.log" || log_fail "refusal must name the missing placeholder: $(cat "$TEST_DIR/bad-template.log")"
  [[ ! -e "$sandbox/docs/ai/STATE.yaml" ]] || log_fail "placeholder-less template must never create a STATE file"
  log_pass "unstampable template refused (exit 1, placeholder named, nothing created) (TEST-007)"
}

test_single_state_creator() {  # CHANGE follow-ups-scripts AC-001: no second creator
  log_info "Test: autonomous-loop.sh delegates STATE creation to check-state --repair and carries NO inline heredoc creator (single-creator pin)..."
  local al="$PROJECT_ROOT/.aai/scripts/autonomous-loop.sh"
  [[ -f "$al" ]] || log_fail "missing $al"
  grep -qF 'check-state.mjs --repair' "$al" \
    || log_fail "autonomous-loop.sh must delegate to check-state.mjs --repair"
  grep -qF 'cat > "$STATE_PATH"' "$al" \
    && log_fail "autonomous-loop.sh must not carry an inline heredoc STATE creator (drifted second schema source)"
  log_pass "single STATE creator: autonomous-loop delegates to check-state --repair"
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
  test_repair_creates_missing_state_from_template
  test_template_header_matches_live_state
  test_template_standalone_parses_and_carries_canonical_keys
  test_skill_check_state_names_template_as_authoritative
  test_repair_existing_file_untouched_by_creation_path
  test_create_fail_loud_missing_template
  test_create_fail_loud_missing_placeholder
  test_single_state_creator
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
