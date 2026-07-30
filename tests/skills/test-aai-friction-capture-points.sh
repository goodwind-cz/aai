#!/usr/bin/env bash
#
# Test: deterministic friction capture points
# (CHANGE deterministic-friction-capture).
#
# RFC-0012 Phase 2's prose FRICTION HOOK is recall-dependent and demonstrably
# never fires during real work, so the spool stays empty. This suite pins two
# DETERMINISTIC capture points wired directly into the scripts where friction
# provably flows — no LLM judgment at write time, raw observation only:
#
#   CAPTURE POINT 1 — .aai/scripts/aai-run-tests.sh: when the wrapped test/build
#     command exits non-zero (incl. 124 timeout), append ONE raw observation to
#     the spool via the existing aai-friction.mjs `record` CLI. Best-effort: a
#     capture failure NEVER changes the wrapper's own exit code (the
#     never-mask-the-caller invariant). Isolation: fires only when capture is
#     not switched off (AAI_FRICTION_CAPTURE != 0) AND the resolved spool DIR
#     already exists — fixture repos have no docs/ai/friction, so they never
#     pollute the real spool.
#
#   CAPTURE POINT 2 — .aai/scripts/close-work-item.mjs: at close time, when the
#     closing ride carried remediation runs (>=1 `role: Remediation` agent_run
#     for the ref in docs/ai/STATE.yaml), append ONE raw observation. Same
#     best-effort discipline as the report/docs-hub regen hooks: never changes
#     the close exit code; same docs/ai/friction existence isolation.
#
# Test map:
#   TEST-001 (AC-001) wrapper: a failing command (exit N) -> exactly one
#            observation, skill_id=aai-run-tests, failure_class
#            deterministic_script_failure; wrapper still exits N.
#   TEST-002 (AC-002) wrapper: a timed-out command -> exit 124, one observation
#            with failure_class stalled_progress.
#   TEST-003 (AC-003) wrapper: a succeeding command -> exit 0, spool empty
#            (negative control: success is not friction).
#   TEST-004 (AC-004) wrapper isolation: a missing spool DIR and the
#            AAI_FRICTION_CAPTURE=0 off-switch each suppress capture; exit code
#            preserved both ways.
#   TEST-005 (AC-005) wrapper never-mask: a capture that FAILS (spool target is
#            a directory -> EISDIR, root-immune) is swallowed; wrapper exits the
#            command's real code unchanged.
#   TEST-006 (AC-006) close: a ride whose STATE carries remediation runs -> the
#            close appends exactly one observation, skill_id=close-work-item;
#            close exits 0.
#   TEST-007 (AC-007) close negative control: a ride with zero remediation runs
#            appends nothing; close exits 0.
#   TEST-008 (AC-008) close never-mask: a rigged capture failure (EISDIR spool)
#            does not change the close exit code (0).
#   TEST-009 (AC-004) close isolation: remediation present but no
#            docs/ai/friction dir -> no capture, nothing written (fixture repos
#            never pollute the real spool).
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty      -> TEST-003/007 (success / zero-remediation: no line)
#   - zero-remainder         -> TEST-001/006 (exactly one observation)
#   - multi-source/multi-writer -> TEST-006 STATE has Implementation AND
#                              Remediation runs; only Remediation is counted
#   - mid-operation failure  -> TEST-005/008 (capture fails mid-step, swallowed)
#   - negative control       -> TEST-003/004/007/009 (no capture cases)
#
# bash 3.2 compatible. Node stdlib only.
#
# Usage:
#   bash tests/skills/test-aai-friction-capture-points.sh              # all
#   bash tests/skills/test-aai-friction-capture-points.sh test_001_... # one
#
# Exit codes: 0 all pass / 1 failed / 42 skipped (missing deps)

set -uo pipefail

TEST_NAME="aai-friction-capture-points"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WRAPPER="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
FRICTION_CLI="$PROJECT_ROOT/.aai/scripts/aai-friction.mjs"

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
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
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  [ -f "$FRICTION_CLI" ] || log_fail "aai-friction.mjs not found: $FRICTION_CLI"
  # WRAPPER / CLOSE_SCRIPT are intentionally NOT required here so the RED phase
  # fails on each TEST's own assertion (product_red), not a precondition skip.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-friction-capture-test.XXXXXX")"
}

# spool_count <spool-file> -> number of non-empty JSONL lines (0 if absent).
spool_count() {
  node -e 'const fs=require("fs");let n=0;try{n=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(l=>l.trim()).length;}catch(e){}process.stdout.write(String(n))' "$1"
}

# line_get <spool-file> <key> [idx] -> String(value) of the key on line idx
# (default last), or __UNDEF__.
line_get() {
  node -e '
    const fs=require("fs");
    const [file,key,idx]=process.argv.slice(1);
    let lines=[];try{lines=fs.readFileSync(file,"utf8").split("\n").filter(l=>l.trim());}catch(e){}
    const i=(idx===undefined||idx==="")?lines.length-1:Number(idx);
    let v;try{v=JSON.parse(lines[i])[key];}catch(e){}
    process.stdout.write(v===undefined?"__UNDEF__":String(v));
  ' "$1" "$2" "${3:-}"
}

# =============================================================================
# CAPTURE POINT 1 — aai-run-tests.sh wrapper
# =============================================================================

# --- TEST-001 (AC-001): failing command records one observation --------------
test_001_wrapper_failure_records() {
  log_info "Test: a failing wrapped command appends one deterministic_script_failure observation; exit code preserved (TEST-001)..."
  [ -f "$WRAPPER" ] || log_fail "TEST-001: wrapper not found: $WRAPPER"
  local sp="$TEST_DIR/sp001"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local rc=0
  AAI_FRICTION_SPOOL_DIR="$sp" sh "$WRAPPER" sh -c 'exit 7' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "7" ] || log_fail "TEST-001: wrapper must pass through the real exit code 7 (got $rc)"
  [ "$(spool_count "$spool")" = "1" ] \
    || log_fail "TEST-001: a failing command must append exactly one observation (got $(spool_count "$spool"))"
  [ "$(line_get "$spool" skill_id)" = "aai-run-tests" ] \
    || log_fail "TEST-001: skill_id must be aai-run-tests (got $(line_get "$spool" skill_id))"
  [ "$(line_get "$spool" failure_class)" = "deterministic_script_failure" ] \
    || log_fail "TEST-001: a non-timeout failure must record failure_class deterministic_script_failure (got $(line_get "$spool" failure_class))"
  log_pass "Failing command -> one deterministic_script_failure observation, exit 7 preserved (TEST-001)"
}

# --- TEST-002 (AC-002): timeout records stalled_progress ---------------------
test_002_wrapper_timeout_records() {
  log_info "Test: a timed-out wrapped command exits 124 and records failure_class stalled_progress (TEST-002)..."
  [ -f "$WRAPPER" ] || log_fail "TEST-002: wrapper not found: $WRAPPER"
  local sp="$TEST_DIR/sp002"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local rc=0
  AAI_TEST_TIMEOUT=2 AAI_FRICTION_SPOOL_DIR="$sp" sh "$WRAPPER" sh -c 'sleep 30' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "124" ] || log_fail "TEST-002: a timed-out command must exit 124 (got $rc)"
  [ "$(spool_count "$spool")" = "1" ] \
    || log_fail "TEST-002: a timeout must append exactly one observation (got $(spool_count "$spool"))"
  [ "$(line_get "$spool" failure_class)" = "stalled_progress" ] \
    || log_fail "TEST-002: a timeout must record failure_class stalled_progress (got $(line_get "$spool" failure_class))"
  log_pass "Timeout -> exit 124 + one stalled_progress observation (TEST-002)"
}

# --- TEST-003 (AC-003): success records nothing ------------------------------
test_003_wrapper_success_no_record() {
  log_info "Test: a succeeding wrapped command records nothing (success is not friction) (TEST-003)..."
  [ -f "$WRAPPER" ] || log_fail "TEST-003: wrapper not found: $WRAPPER"
  local sp="$TEST_DIR/sp003"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local rc=0
  AAI_FRICTION_SPOOL_DIR="$sp" sh "$WRAPPER" sh -c 'exit 0' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-003: a succeeding command must exit 0 (got $rc)"
  [ "$(spool_count "$spool")" = "0" ] \
    || log_fail "TEST-003: a succeeding command must NOT record friction (got $(spool_count "$spool"))"
  log_pass "Success -> no observation, exit 0 (TEST-003)"
}

# --- TEST-004 (AC-004): isolation — missing dir + off-switch -----------------
test_004_wrapper_isolation() {
  log_info "Test: a missing spool dir and AAI_FRICTION_CAPTURE=0 each suppress capture; exit preserved (TEST-004)..."
  [ -f "$WRAPPER" ] || log_fail "TEST-004: wrapper not found: $WRAPPER"

  # (a) existence gate: point at a dir that does NOT exist -> no capture, no dir
  # created (a fixture repo lacking docs/ai/friction must never pollute a spool).
  local missing="$TEST_DIR/sp004-missing/friction"
  local rc=0
  AAI_FRICTION_SPOOL_DIR="$missing" sh "$WRAPPER" sh -c 'exit 3' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || log_fail "TEST-004a: exit code must be preserved (got $rc)"
  [ ! -e "$missing" ] \
    || log_fail "TEST-004a: capture must NOT create a spool when its dir does not pre-exist"

  # (b) off-switch: dir exists but AAI_FRICTION_CAPTURE=0 -> no capture.
  local sp="$TEST_DIR/sp004-off"; mkdir -p "$sp"
  rc=0
  AAI_FRICTION_CAPTURE=0 AAI_FRICTION_SPOOL_DIR="$sp" sh "$WRAPPER" sh -c 'exit 3' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "3" ] || log_fail "TEST-004b: exit code must be preserved with the off-switch (got $rc)"
  [ "$(spool_count "$sp/observations.jsonl")" = "0" ] \
    || log_fail "TEST-004b: AAI_FRICTION_CAPTURE=0 must suppress capture (got $(spool_count "$sp/observations.jsonl"))"
  log_pass "Isolation: missing-dir gate + off-switch both suppress capture, exit preserved (TEST-004)"
}

# --- TEST-005 (AC-005): capture failure never masks the wrapper --------------
test_005_wrapper_never_masks() {
  log_info "Test: a capture that FAILS (EISDIR spool) is swallowed; wrapper exits the real code (TEST-005)..."
  [ -f "$WRAPPER" ] || log_fail "TEST-005: wrapper not found: $WRAPPER"
  local sp="$TEST_DIR/sp005"; mkdir -p "$sp"
  # Root-immune forced failure: make the append TARGET a directory so
  # appendFileSync throws EISDIR for every uid (chmod would not stop root).
  mkdir -p "$sp/observations.jsonl"
  local rc=0
  AAI_FRICTION_SPOOL_DIR="$sp" sh "$WRAPPER" sh -c 'exit 9' >/dev/null 2>&1 || rc=$?
  [ "$rc" = "9" ] \
    || log_fail "TEST-005: a failing capture must not change the wrapper's exit code (want 9, got $rc)"
  [ -d "$sp/observations.jsonl" ] \
    || log_fail "TEST-005: setup invalid — the EISDIR target must remain a directory"
  log_pass "Capture failure swallowed; wrapper exit code 9 unchanged (TEST-005)"
}

# =============================================================================
# CAPTURE POINT 2 — close-work-item.mjs
# =============================================================================

# new_close_fixture <name> <remediation:0|1> <make_friction_dir:0|1> -> prints dir.
# Builds a throwaway git repo with a draft change doc, docs-audit.yaml, empty
# EVENTS.jsonl, and a STATE.yaml whose metrics carry the requested number of
# Remediation runs for the closing ref (plus one Implementation run to prove
# only Remediation is counted). docs/ai/friction is created only when asked.
new_close_fixture() {
  local name="$1" remediation="$2" friction_dir="$3"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/issues" "$dir/docs/ai"
  : > "$dir/docs/ai/EVENTS.jsonl"
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  cat > "$dir/docs/issues/CHANGE-0001-$name.md" <<EOF
---
id: $name-slug
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Fixture $name

## Summary
- fixture doc for friction capture-point tests.

## Acceptance Criteria
- AC-001: fixture.

## Notes
- ephemeral fixture; never committed.
EOF
  # STATE.yaml with a metrics.work_items block for the closing ref.
  if [ "$remediation" = "1" ]; then
    cat > "$dir/docs/ai/STATE.yaml" <<EOF
project_status: active
metrics:
  work_items:
    $name-slug:
      agent_runs:
        - role: Implementation
          model_id: test
        - role: Remediation
          model_id: test
        - role: Remediation
          model_id: test
updated_at_utc: 2026-01-01T00:00:00Z
EOF
  else
    cat > "$dir/docs/ai/STATE.yaml" <<EOF
project_status: active
metrics:
  work_items:
    $name-slug:
      agent_runs:
        - role: Implementation
          model_id: test
updated_at_utc: 2026-01-01T00:00:00Z
EOF
  fi
  [ "$friction_dir" = "1" ] && mkdir -p "$dir/docs/ai/friction"
  git init -q -b main "$dir" 2>/dev/null || git -c init.defaultBranch=main init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  echo "$dir"
}

# --- TEST-006 (AC-006): remediation-carrying close records one observation ----
test_006_close_with_remediation_records() {
  log_info "Test: a close whose STATE carries remediation runs appends one close-work-item observation; exit 0 (TEST-006)..."
  [ -f "$CLOSE_SCRIPT" ] || log_fail "TEST-006: close script not found: $CLOSE_SCRIPT"
  local dir; dir="$(new_close_fixture t006 1 1)"
  local spool="$dir/docs/ai/friction/observations.jsonl"
  local rc=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" --ref t006-slug --pr 1 --commit a0a0a01 ) >/dev/null 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-006: close must exit 0 (got $rc)"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t006.md" \
    || log_fail "TEST-006: setup invalid — the close did not flip the doc to done"
  [ "$(spool_count "$spool")" = "1" ] \
    || log_fail "TEST-006: a remediation-carrying close must append exactly one observation (got $(spool_count "$spool"))"
  [ "$(line_get "$spool" skill_id)" = "close-work-item" ] \
    || log_fail "TEST-006: observation skill_id must be close-work-item (got $(line_get "$spool" skill_id))"
  log_pass "Remediation-carrying close -> one close-work-item observation, exit 0 (TEST-006)"
}

# --- TEST-007 (AC-007): zero-remediation close records nothing ---------------
test_007_close_without_remediation_no_record() {
  log_info "Test: a close with zero remediation runs appends nothing; exit 0 (TEST-007)..."
  [ -f "$CLOSE_SCRIPT" ] || log_fail "TEST-007: close script not found: $CLOSE_SCRIPT"
  local dir; dir="$(new_close_fixture t007 0 1)"
  local spool="$dir/docs/ai/friction/observations.jsonl"
  local rc=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" --ref t007-slug --pr 1 --commit b0b0b02 ) >/dev/null 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-007: close must exit 0 (got $rc)"
  [ "$(spool_count "$spool")" = "0" ] \
    || log_fail "TEST-007: a close with no remediation must record nothing (got $(spool_count "$spool"))"
  log_pass "Zero-remediation close -> no observation, exit 0 (TEST-007)"
}

# --- TEST-008 (AC-008): close capture failure never masks the close ----------
test_008_close_never_masks() {
  log_info "Test: a rigged capture failure (EISDIR spool) does not change the close exit code (TEST-008)..."
  [ -f "$CLOSE_SCRIPT" ] || log_fail "TEST-008: close script not found: $CLOSE_SCRIPT"
  local dir; dir="$(new_close_fixture t008 1 1)"
  # Root-immune forced capture failure: the append target is a directory.
  mkdir -p "$dir/docs/ai/friction/observations.jsonl"
  local rc=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" --ref t008-slug --pr 1 --commit c0c0c03 ) >/dev/null 2>&1 || rc=$?
  [ "$rc" = "0" ] \
    || log_fail "TEST-008: a failing friction capture must not change the close exit code (want 0, got $rc)"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t008.md" \
    || log_fail "TEST-008: the close itself must still have succeeded (doc flipped to done)"
  log_pass "Close friction-capture failure swallowed; close exit 0 unchanged (TEST-008)"
}

# --- TEST-009 (AC-004): close isolation — no friction dir, no pollution ------
test_009_close_isolation_no_friction_dir() {
  log_info "Test: remediation present but no docs/ai/friction dir -> no capture, nothing written (TEST-009)..."
  [ -f "$CLOSE_SCRIPT" ] || log_fail "TEST-009: close script not found: $CLOSE_SCRIPT"
  local dir; dir="$(new_close_fixture t009 1 0)"
  local rc=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" --ref t009-slug --pr 1 --commit d0d0d04 ) >/dev/null 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-009: close must exit 0 (got $rc)"
  [ ! -e "$dir/docs/ai/friction" ] \
    || log_fail "TEST-009: close must NOT create docs/ai/friction when it is absent (fixture repos must never pollute a spool)"
  log_pass "No friction dir -> no capture, nothing created (fixture isolation) (TEST-009)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_wrapper_failure_records
  test_002_wrapper_timeout_records
  test_003_wrapper_success_no_record
  test_004_wrapper_isolation
  test_005_wrapper_never_masks

  test_006_close_with_remediation_records
  test_007_close_without_remediation_no_record
  test_008_close_never_masks
  test_009_close_isolation_no_friction_dir

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
