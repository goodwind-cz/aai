#!/usr/bin/env bash
#
# Test: aai-run-tests wrapper + aai-reap-tests reaper (SPEC-0009 / ISSUE-0002)
# Verifies the process-group test wrapper and the workspace+etime scoped reaper
# against isolated fixtures, plus the loop/validation/dynamic-skills/bootstrap/
# docs wiring. Implements TEST-001..011 from the frozen spec.
#
# The scripts under test are overridable so the two SAFETY tests can be
# RED-proofed against deliberately-naive stubs:
#   AAI_RUN_TESTS_SCRIPT  wrapper under test (default .aai/scripts/aai-run-tests.sh)
#   AAI_REAP_SCRIPT       reaper under test  (default .aai/scripts/aai-reap-tests.sh)
# TEST-002 RED-proofs the wrapper against a no-group-kill stub (a leaky child
# survives). TEST-005 RED-proofs the reaper against a bare global `pkill -f
# vitest` stub (a non-matching sibling is over-reaped).
#
# No real vitest/esbuild is needed: uniquely-marked `sleep` processes (argv[0]
# rewritten via `exec -a` to embed the `vitest` token + a workspace path) stand
# in for hung test trees, and `ps ... etime` drives the age guard.
#
# Usage:
#   bash tests/skills/test-aai-run-tests.sh            # run all (TEST-001..011)
#   bash tests/skills/test-aai-run-tests.sh 002 005    # run only selected tests
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-run-tests"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_TESTS_SCRIPT="${AAI_RUN_TESTS_SCRIPT:-$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh}"
REAP_SCRIPT="${AAI_REAP_SCRIPT:-$PROJECT_ROOT/.aai/scripts/aai-reap-tests.sh}"

# Wiring targets (grep asserts).
SKILL_LOOP_DOC="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
VALIDATION_DOC="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
DYNAMIC_SKILLS_DOC="$PROJECT_ROOT/.aai/system/DYNAMIC_SKILLS.md"
BOOTSTRAP_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.sh"
USER_GUIDE_DOC="$PROJECT_ROOT/docs/USER_GUIDE.md"
SKILL_BOOTSTRAP_DOC="$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md"

TMP_ROOT=""
SPAWNED_PIDS_FILE=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# Appends to a FILE, not a shell variable: most callers invoke the spawn_*
# helpers via command substitution ($(...)), which runs in a SUBSHELL — a
# variable mutated there is invisible to this script's own trap. A file write
# is a real filesystem effect and survives the subshell exiting, so cleanup()
# below reliably reaps every throwaway marked sleep proc this suite spawns,
# including the ones a test deliberately leaves alive (spared-by-design
# fixtures like an other-workspace or fresh sibling).
track() { [[ -n "$SPAWNED_PIDS_FILE" ]] && echo "$1" >> "$SPAWNED_PIDS_FILE"; }

cleanup() {
  local p
  if [[ -n "${SPAWNED_PIDS_FILE:-}" && -f "$SPAWNED_PIDS_FILE" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && kill -9 "$p" >/dev/null 2>&1 || true
    done < "$SPAWNED_PIDS_FILE"
  fi
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

# Spawn a long-lived process whose command line embeds $1 as argv[0] (so the
# reaper's `vitest`+workspace substring match and `pgrep -f` can find it) and
# print its pid. The process is a plain `sleep` — no real test runner needed.
spawn_marked() {
  local argv0="$1"
  bash -c 'exec -a "$0" sleep 600' "$argv0" >/dev/null 2>&1 &
  local pid=$!
  track "$pid"
  echo "$pid"
}

# Spawn a MATCHED launcher whose argv[0] embeds $1 (the vitest token + a workspace
# path) which FIRST backgrounds a token-less `sleep` child (its argv is plain
# "sleep 600" — NO token) and THEN execs into a marked sleep. The launcher matches
# the reaper's guards while its LIVE descendant does not — the SPEC-0009 P2 fixture
# (a child whose argv dropped the token must still be reaped via the tree walk).
# The child's ppid == the launcher pid (exec keeps the pid). Prints the launcher pid.
spawn_parent_with_child() {
  local argv0="$1"
  bash -c 'sleep 600 & exec -a "$0" sleep 600' "$argv0" >/dev/null 2>&1 &
  local pid=$!
  track "$pid"
  echo "$pid"
}

alive() { kill -0 "$1" >/dev/null 2>&1; }

# Parse the reaper's OWN reported reaped-pids list from its stdout — the
# `reaped pids:<space-list>` line the reaper prints alongside `reaped: N`
# (empty tail when it reaped nothing). This is what lets test_018 ATTRIBUTE a
# reap to the reaper itself instead of inferring it from a proc's liveness
# (which an external kill would mis-attribute). SPEC test-018-legacy-spare-attribution.
reaped_pids_of() { printf '%s\n' "$1" | sed -n 's/^reaped pids://p'; }

# True iff <pid> ($1) appears as a token in the reaper's reported reaped-pids
# list parsed from the reaper stdout ($2).
reaper_reaped_pid() {
  local want="$1" tok
  for tok in $(reaped_pids_of "$2"); do
    [[ "$tok" == "$want" ]] && return 0
  done
  return 1
}

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v ps >/dev/null 2>&1 || log_skip "ps not found"
  command -v pgrep >/dev/null 2>&1 || log_skip "pgrep not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-run-tests-test.XXXXXX")"
  SPAWNED_PIDS_FILE="$TMP_ROOT/.spawned_pids"
  : > "$SPAWNED_PIDS_FILE"
  log_pass "Dependencies checked"
}

# --- TEST-001 — real exit-code passthrough (Spec-AC-01) -----------------------
test_001() {
  log_info "TEST-001: wrapper exists; runs cmd in own group; returns REAL exit code..."
  [[ -f "$RUN_TESTS_SCRIPT" ]] || log_fail "wrapper script not found: $RUN_TESTS_SCRIPT"
  local rc
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "a succeeding command must yield exit 0 (got $rc)"
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 7' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 7 ]] || log_fail "a failing command must pass through its real exit code 7 (got $rc)"
  log_pass "wrapper returns the command's real exit code (0 and 7)"
}

# --- TEST-002 — SAFETY: leaky child leaves NO survivor (Spec-AC-02) -----------
# RED-proofed: against a no-group-kill stub wrapper the backgrounded sleep
# survives, so "no descendant survives" fails RED.
test_002() {
  log_info "TEST-002: leaky child (backgrounds sleep, exits 0) -> prompt return, exit 0, NO survivor..."
  local marker="aai_leak_${$}_${RANDOM}_vitest"
  local start end rc
  start="$(date +%s)"
  # Leaky child: backgrounds a long-lived marked sleep, then exits 0.
  sh "$RUN_TESTS_SCRIPT" bash -c "( exec -a $marker sleep 600 ) & exit 0" >/dev/null 2>&1; rc=$?
  end="$(date +%s)"
  [[ "$rc" -eq 0 ]] || log_fail "a leaky child that exits 0 must yield exit 0 (got $rc)"
  [[ $((end - start)) -lt 30 ]] || log_fail "wrapper must return promptly, took $((end - start))s"
  # Give any straggler a moment, then assert the marker is gone.
  sleep 1
  if pgrep -f "$marker" >/dev/null 2>&1; then
    local survivors
    survivors="$(pgrep -f "$marker" | tr '\n' ' ')"
    kill -9 $survivors >/dev/null 2>&1 || true
    log_fail "leaky descendant survived the wrapper (pids: $survivors) — no group-kill"
  fi
  log_pass "leaky child reaped: no descendant of the spawned group survives"
}

# --- TEST-003 — timeout kill -> exit 124, no survivors (Spec-AC-03) -----------
test_003() {
  log_info "TEST-003: never-exiting cmd killed at AAI_TEST_TIMEOUT -> ~timeout return, exit 124, no survivors..."
  local marker="aai_timeout_${$}_${RANDOM}_vitest"
  local start end rc
  start="$(date +%s)"
  AAI_TEST_TIMEOUT=2 sh "$RUN_TESTS_SCRIPT" bash -c "exec -a $marker sleep 600" >/dev/null 2>&1; rc=$?
  end="$(date +%s)"
  [[ "$rc" -eq 124 ]] || log_fail "a timed-out command must exit 124 (got $rc)"
  [[ $((end - start)) -lt 15 ]] || log_fail "wrapper must return within ~timeout, took $((end - start))s"
  sleep 1
  if pgrep -f "$marker" >/dev/null 2>&1; then
    local survivors
    survivors="$(pgrep -f "$marker" | tr '\n' ' ')"
    kill -9 $survivors >/dev/null 2>&1 || true
    log_fail "timed-out command left a survivor (pids: $survivors)"
  fi
  log_pass "timeout kills the tree, exits 124, leaves no survivors"
}

# --- TEST-004 — exit-code fidelity: 0 / N / 124 (Spec-AC-04) ------------------
test_004() {
  log_info "TEST-004: exit fidelity — success->0, fail->N, timeout->124 (hung distinguishable from failed)..."
  local rc
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 0' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "success must map to 0 (got $rc)"
  sh "$RUN_TESTS_SCRIPT" sh -c 'exit 5' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "a command exiting N must map to N=5 (got $rc)"
  local marker="aai_fidelity_${$}_${RANDOM}_vitest"
  AAI_TEST_TIMEOUT=2 sh "$RUN_TESTS_SCRIPT" bash -c "exec -a $marker sleep 600" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 124 ]] || log_fail "a timeout must map to 124, distinct from an ordinary failure (got $rc)"
  # 124 must be distinguishable from an ordinary failing exit code.
  [[ "$rc" -ne 5 ]] || log_fail "timeout code must differ from the ordinary-failure code"
  pkill -f "$marker" >/dev/null 2>&1 || true
  log_pass "exit codes: success=0, failure=N, timeout=124 (all distinct)"
}

# --- TEST-005 — SAFETY: reaper is workspace-scoped, never global (Spec-AC-05) --
# RED-proofed: against a bare `pkill -f vitest` stub the NON-matching sibling in
# a different workspace is also killed, so "non-matching survives" fails RED.
test_005() {
  log_info "TEST-005: reaper kills only vitest+THIS-workspace; a non-matching (other workspace) sibling SURVIVES..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws other match_pid other_pid out
  ws="$(mktemp -d "$TMP_ROOT/ws.XXXXXX")"
  other="$(mktemp -d "$TMP_ROOT/other.XXXXXX")"
  # Matching: cmd line contains vitest + THIS workspace as a proper path component
  # (the '/' after ${ws} ensures *"${WORKSPACE}/"* matches).
  match_pid="$(spawn_marked "vitest_run_${ws}/worker")"
  # Non-matching: contains vitest but a DIFFERENT workspace path (other.XXXX ≠ ws.XXXX).
  other_pid="$(spawn_marked "vitest_run_${other}/worker")"
  sleep 1
  alive "$match_pid" || log_fail "fixture setup: matching proc $match_pid not alive"
  alive "$other_pid" || log_fail "fixture setup: non-matching proc $other_pid not alive"
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=0 sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$match_pid" && log_fail "reaper failed to kill the in-workspace vitest proc $match_pid"
  alive "$other_pid" || log_fail "reaper over-reached: killed a NON-matching (other-workspace) sibling $other_pid — never-global invariant violated"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper must report a non-zero reaped count (got: $out)"
  log_pass "reaper kills only the in-workspace match; the other-workspace sibling survives"
}

# --- TEST-006 — epoch guard: post-step sibling spared, pre-step reaped (Spec-AC-01/02, migrated) ----
# MIGRATED off the fixed-threshold margin-hope (etime >= MIN_AGE=5 with wide
# sleeps) onto the deterministic STEP-START-EPOCH contract: the decision is by
# CONSTRUCTION (relative to a captured step boundary), not by hoping reaper
# overhead stays under a constant.
test_006() {
  log_info "TEST-006: epoch guard — a post-step-boundary matching proc is NOT reaped; a pre-step one IS..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws old_pid step_start fresh_pid out
  ws="$(mktemp -d "$TMP_ROOT/ws6.XXXXXX")"
  # Old matching process predates the step boundary.
  old_pid="$(spawn_marked "vitest_old_${ws}/worker")"
  # SAME zero-slack boundary defect TEST-017 had (see its comment): the reaper
  # reaps iff start_epoch < STEP_START - GRACE(2), and `start_epoch` is derived
  # from a FLOOR-truncated etime, so the minimum reliably-reapable gap is
  # GRACE(2) + 1s truncation = 3s (4s counting the `date +%s` quantization of
  # step_start). The former `sleep 3` sat EXACTLY on that boundary with ZERO
  # slack and flaked under CI load ("reaper failed to reap the pre-step matching
  # proc", observed on PR #131). `sleep 6` leaves 3s of slack under the lenient
  # model and 2s under the conservative one. DO NOT NARROW this back toward 3s:
  # re-derive the slack from GRACE first. Only the PRE-step side needs the
  # margin — the fresh sibling below is spawned after step_start, so it is
  # unambiguously post-boundary.
  sleep 6
  # Step boundary captured HERE — everything spawned at/after this instant is
  # this step's own work and must be spared regardless of reaper overhead.
  step_start="$(date +%s)"
  fresh_pid="$(spawn_marked "vitest_fresh_${ws}/worker")"
  alive "$old_pid" || log_fail "fixture setup: old proc $old_pid not alive"
  alive "$fresh_pid" || log_fail "fixture setup: fresh proc $fresh_pid not alive"
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$old_pid" && log_fail "reaper failed to reap the pre-step matching proc $old_pid"
  alive "$fresh_pid" || log_fail "reaper killed a FRESH sibling $fresh_pid spawned at/after the step boundary — epoch guard violated"
  log_pass "epoch guard reaps the pre-step tree and spares the post-step-boundary sibling, deterministically"
}

# --- TEST-007 — SKILL_LOOP routing + preflight + tick accounting (Spec-AC-07) --
test_007() {
  log_info "TEST-007: grep SKILL_LOOP — wrapper routing, preflight count+warn+reap, tick-log lingering_procs/free_memory..."
  [[ -f "$SKILL_LOOP_DOC" ]] || log_fail "missing $SKILL_LOOP_DOC"
  grep -qF "aai-run-tests.sh" "$SKILL_LOOP_DOC" \
    || log_fail "SKILL_LOOP must route test commands through aai-run-tests.sh"
  grep -qF "aai-reap-tests.sh" "$SKILL_LOOP_DOC" \
    || log_fail "SKILL_LOOP must run the scoped reaper aai-reap-tests.sh"
  grep -qiE "pre-?flight" "$SKILL_LOOP_DOC" \
    || log_fail "SKILL_LOOP must describe a pre-flight workspace proc count"
  grep -qF "lingering_procs" "$SKILL_LOOP_DOC" \
    || log_fail "SKILL_LOOP must record lingering_procs in the tick log"
  grep -qF "free_memory" "$SKILL_LOOP_DOC" \
    || log_fail "SKILL_LOOP must record free_memory in the tick log"
  log_pass "SKILL_LOOP wires wrapper routing + preflight/reap + tick-log accounting"
}

# --- TEST-008 — VALIDATION routes via wrapper + reaps (Spec-AC-08) ------------
test_008() {
  log_info "TEST-008: grep VALIDATION — discovered tests via aai-run-tests.sh + reap on step boundary..."
  [[ -f "$VALIDATION_DOC" ]] || log_fail "missing $VALIDATION_DOC"
  grep -qF "aai-run-tests.sh" "$VALIDATION_DOC" \
    || log_fail "VALIDATION must run discovered test commands through aai-run-tests.sh"
  grep -qF "aai-reap-tests.sh" "$VALIDATION_DOC" \
    || log_fail "VALIDATION must reap workspace survivors via aai-reap-tests.sh on the step boundary"
  log_pass "VALIDATION routes discovered tests through the wrapper and reaps on the boundary"
}

# --- TEST-009 — DYNAMIC_SKILLS documents wrapper routing (Spec-AC-09) ---------
test_009() {
  log_info "TEST-009: grep DYNAMIC_SKILLS — generated aai-test-* skills route through the wrapper..."
  [[ -f "$DYNAMIC_SKILLS_DOC" ]] || log_fail "missing $DYNAMIC_SKILLS_DOC"
  grep -qF "aai-run-tests.sh" "$DYNAMIC_SKILLS_DOC" \
    || log_fail "DYNAMIC_SKILLS must document that generated aai-test-* skills route through aai-run-tests.sh"
  log_pass "DYNAMIC_SKILLS documents wrapper routing for generated test skills"
}

# --- TEST-010 — bootstrap emits wrapped cmd + leak-safe vitest guidance (Spec-AC-10)
# RED-proofed: the pre-change generator emits a BARE `npm exec vitest run` and no
# leak-safe guidance.
test_010() {
  log_info "TEST-010: bootstrap on a vitest fixture -> generated unit cmd wrapped + leak-safe vitest guidance; no config overwrite..."
  [[ -f "$BOOTSTRAP_SCRIPT" ]] || log_fail "missing $BOOTSTRAP_SCRIPT"
  local fx unit marker existing_before existing_after
  fx="$(mktemp -d "$TMP_ROOT/bootstrap.XXXXXX")"
  cat > "$fx/package.json" <<'JSON'
{
  "name": "vitest-fixture",
  "version": "1.0.0",
  "devDependencies": { "vitest": "^1.0.0" }
}
JSON
  cat > "$fx/vitest.config.ts" <<'TS'
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { pool: "threads" } });
TS
  existing_before="$(cat "$fx/vitest.config.ts")"

  bash "$BOOTSTRAP_SCRIPT" "$fx" >/dev/null 2>&1 || log_fail "bootstrap run failed on the vitest fixture"

  unit="$fx/.claude/skills/aai-test-unit/SKILL.md"
  marker="$fx/.claude/skills/AAI_DYNAMIC_SKILLS.md"
  [[ -f "$unit" ]] || log_fail "bootstrap did not generate the aai-test-unit skill"

  # Wrapped, not bare: the detected vitest command must be prefixed by the wrapper.
  grep -qF ".aai/scripts/aai-run-tests.sh" "$unit" \
    || log_fail "generated unit-test command must be WRAPPED via .aai/scripts/aai-run-tests.sh (bare command is the RED state)"
  grep -Eq "aai-run-tests\.sh.*vitest" "$unit" \
    || log_fail "the wrapper must prefix the detected vitest command in the generated skill"

  # Leak-safe vitest guidance emitted somewhere in the generated outputs.
  grep -rqF "maxForks" "$fx/.claude/skills/" \
    || log_fail "bootstrap must emit leak-safe vitest guidance (maxForks) when vitest is detected"
  grep -rqiE "pool['\": ]+.*forks|pool.*forks" "$fx/.claude/skills/" \
    || log_fail "bootstrap must emit leak-safe vitest guidance (pool: 'forks')"
  grep -rqF "teardownTimeout" "$fx/.claude/skills/" \
    || log_fail "bootstrap must emit leak-safe vitest guidance (teardownTimeout)"

  # Must NOT overwrite the user's existing vitest config.
  existing_after="$(cat "$fx/vitest.config.ts")"
  [[ "$existing_before" == "$existing_after" ]] \
    || log_fail "bootstrap must NOT overwrite an existing user vitest config"

  log_pass "bootstrap wraps the generated vitest command + emits leak-safe guidance without overwriting user config"
}

# --- TEST-011 — user docs describe the 4-part leak-safe contract (Spec-AC-11) --
test_011() {
  log_info "TEST-011: grep USER_GUIDE / SKILL_BOOTSTRAP — 4-part leak-safe test contract documented..."
  # AC-11 is USER_GUIDE and/or SKILL_BOOTSTRAP: at least ONE doc must carry the
  # COMPLETE four-part contract (killable group + timeout, bounded forks, scoped
  # reaper never global, tick-log accounting) with both scripts named.
  local doc complete=0
  for doc in "$USER_GUIDE_DOC" "$SKILL_BOOTSTRAP_DOC"; do
    [[ -f "$doc" ]] || continue
    grep -qF "aai-run-tests.sh" "$doc" || continue
    grep -qF "aai-reap-tests.sh" "$doc" || continue
    grep -qiE "process group|killable group|group-kill" "$doc" || continue
    grep -qiE "maxForks|bounded fork|pool.*forks" "$doc" || continue
    grep -qiE "workspace|etime|never global|scoped reap" "$doc" || continue
    grep -qiE "lingering_procs|tick[- ]log|accounting|free_memory" "$doc" || continue
    complete=1
  done
  [[ "$complete" -eq 1 ]] \
    || log_fail "USER_GUIDE or SKILL_BOOTSTRAP must document the FULL 4-part leak-safe test contract (killable group + timeout, bounded forks, scoped reaper never-global, tick-log accounting)"
  log_pass "user docs describe the 4-part leak-safe test contract"
}

# --- TEST-012 — SAFETY: reaper does NOT over-kill a prefix-sibling workspace (E1 fix) -----
# RED-proofed: against the original substring guard (*"$WORKSPACE"*) the prefix-sibling
# process — whose argv[0] embeds ${ws}-fork (WORKSPACE is a string prefix of that path) —
# is also killed (over-kill E1, live-confirmed by reviewer). The path-separator guard
# *"${WORKSPACE}/"* fixes this by requiring a literal '/' after the workspace path, so
# /x/myproject does NOT match /x/myproject-fork.
test_012() {
  log_info "TEST-012: prefix-sibling safety — reaper scoped to WORKSPACE must NOT kill a process in WORKSPACE-fork..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws ws_fork match_pid prefix_pid out
  ws="$(mktemp -d "$TMP_ROOT/myproject.XXXXXX")"
  # The fork workspace is a PATH whose name begins with the base workspace name.
  # Its path is a string-prefix sibling (e.g. /tmp/.../myproject.XXXX-fork).
  # This does NOT need to be a real directory — the reaper only inspects argv[0].
  ws_fork="${ws}-fork"
  # In-workspace: cmd line contains vitest + THIS workspace as a proper path component.
  match_pid="$(spawn_marked "vitest_run_${ws}/worker")"
  # Prefix-sibling: contains vitest + the FORK workspace (WORKSPACE is a string prefix
  # of this path). Must NOT be killed when reaping for ws.
  prefix_pid="$(spawn_marked "vitest_run_${ws_fork}/worker")"
  sleep 1
  alive "$match_pid" || log_fail "fixture setup: match proc $match_pid not alive"
  alive "$prefix_pid" || log_fail "fixture setup: prefix-sibling proc $prefix_pid not alive"
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=0 sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$match_pid" && log_fail "reaper failed to kill the in-workspace vitest proc $match_pid"
  alive "$prefix_pid" \
    || log_fail "reaper over-killed: killed prefix-sibling proc $prefix_pid in ${ws_fork} — pre-fix substring match (E1)"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper must report a non-zero reaped count (got: $out)"
  log_pass "prefix-sibling workspace process survives; in-workspace process reaped (E1 fixed)"
}

test_013() {
  log_info "TEST-013: reaper runs under POSIX sh (dash), not bash-only [[ ]] (W1)..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  # Static guard: a #!/bin/sh script must not use bash-only [[ ]] in CODE
  # (comments are stripped so a mention of the construct doesn't false-positive).
  ! sed 's/#.*$//' "$REAP_SCRIPT" | grep -qE '\[\[' || log_fail "reaper (#!/bin/sh) must not use bash-only [[ ]] in code (W1)"
  # Dynamic guard: under a strict POSIX shell (dash) the reaper must (a) run with
  # NO shell errors on stderr and (b) actually reap an in-workspace match whose age
  # exceeds the threshold. bash-only constructs no-op or error under dash: [[ ]] →
  # 'not found' (guard skips every proc → reaped 0); 10# base-notation in the etime
  # arithmetic → 'expecting EOF' errors → age falls back to 0 → old leaks spared
  # (silent under-reap on Linux). This exercises BOTH the guard and the etime path.
  if command -v dash >/dev/null 2>&1; then
    local ws match_pid out err
    ws="$(mktemp -d "$TMP_ROOT/posix.XXXXXX")"
    match_pid="$(spawn_marked "vitest_run_${ws}/worker")"
    sleep 2   # let the match age past the 1s threshold below (exercises etime parsing)
    alive "$match_pid" || log_fail "fixture setup: match proc $match_pid not alive"
    err="$TMP_ROOT/dash-stderr.$$"
    out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=1 dash "$REAP_SCRIPT" 2>"$err")"
    sleep 1
    if grep -qiE 'not found|expecting EOF|arithmetic|[Ss]yntax error|unexpected' "$err"; then
      log_fail "reaper emitted shell errors under dash (bashism) — $(tr '\n' ';' < "$err")"
    fi
    alive "$match_pid" && log_fail "reaper under dash did not reap the aged in-workspace proc $match_pid — bashism no-op/under-reap under POSIX sh (W1)"
    echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper under dash must report a non-zero reaped count (got: $out)"

    # Extend W1 to the EPOCH path (Spec-AC-04): the STEP-START-relative
    # decision must also be bashism-free under dash — spare a post-step
    # sibling, reap a pre-step survivor, in the SAME dash invocation contract.
    local ws2 old_pid step_start fresh_pid out2 err2
    ws2="$(mktemp -d "$TMP_ROOT/posix-epoch.XXXXXX")"
    old_pid="$(spawn_marked "vitest_epoch_old_${ws2}/worker")"
    # SAME zero-slack boundary defect as TEST-006/TEST-017 (see their comments):
    # the minimum reliably-reapable pre-step gap is GRACE(2) + 1s etime
    # floor-truncation = 3s (4s counting step_start's own `date +%s`
    # quantization), so `sleep 3` sat EXACTLY on the boundary. It survived local
    # runs only because this branch needs `dash` (absent on many macOS hosts) and
    # so effectively ran on CI alone. DO NOT NARROW back toward 3s: re-derive the
    # slack from GRACE first.
    sleep 6
    step_start="$(date +%s)"
    fresh_pid="$(spawn_marked "vitest_epoch_fresh_${ws2}/worker")"
    alive "$old_pid" || log_fail "fixture setup: epoch-old proc $old_pid not alive"
    alive "$fresh_pid" || log_fail "fixture setup: epoch-fresh proc $fresh_pid not alive"
    err2="$TMP_ROOT/dash-epoch-stderr.$$"
    out2="$(AAI_REAP_WORKSPACE="$ws2" AAI_REAP_STEP_START_EPOCH="$step_start" dash "$REAP_SCRIPT" 2>"$err2")"
    sleep 1
    if grep -qiE 'not found|expecting EOF|arithmetic|[Ss]yntax error|unexpected' "$err2"; then
      log_fail "epoch mode emitted shell errors under dash (bashism) — $(tr '\n' ';' < "$err2")"
    fi
    alive "$old_pid" && log_fail "epoch mode under dash failed to reap the pre-step survivor $old_pid"
    alive "$fresh_pid" || log_fail "epoch mode under dash killed the post-step-boundary sibling $fresh_pid"
    echo "$out2" | grep -qiE "reaped: *[1-9]" || log_fail "epoch mode under dash must report a non-zero reaped count (got: $out2)"

    log_pass "reaper runs clean under POSIX sh (dash): no bashisms in legacy OR epoch path (W1 fixed + extended)"
  else
    log_pass "reaper contains no bash-only [[ ]] in code (W1); dash absent, dynamic check skipped"
  fi
}

# --- TEST-014 — P1: wrapper under dash reaps a REPARENTED leaky child (SPEC-0009 P1)
# RED-proofed: the `set -m` wrapper under NON-interactive dash (the Linux /bin/sh)
# never creates the process group, so a reparented sleeper survives `kill -$PGID`.
# The setsid/perl session-leader fix turns it GREEN. The original miss was that ALL
# tests ran under macOS bash (where `set -m` DOES create the group), hiding the
# Linux break — so this test runs the wrapper EXPLICITLY under `dash`.
test_014() {
  log_info "TEST-014: wrapper under dash — reparented leaky child leaves NO survivor (P1)..."
  command -v dash >/dev/null 2>&1 || { log_pass "dash absent; P1 dash test skipped"; return 0; }
  local marker="aai_p1dash_${$}_${RANDOM}_vitest"
  local start end rc
  start="$(date +%s)"
  # The leaky child REPARENTS its worker: a subshell backgrounds a marked sleep,
  # then the parent exits 0, orphaning the sleeper to init — only a real
  # session/process-group (NOT `set -m` under dash) keeps it killable.
  dash "$RUN_TESTS_SCRIPT" bash -c "( exec -a $marker sleep 300 ) & exit 0" >/dev/null 2>&1; rc=$?
  end="$(date +%s)"
  [[ "$rc" -eq 0 ]] || log_fail "a leaky child that exits 0 must yield exit 0 under dash (got $rc)"
  [[ $((end - start)) -lt 30 ]] || log_fail "wrapper under dash must return promptly, took $((end - start))s"
  sleep 1
  if pgrep -f "$marker" >/dev/null 2>&1; then
    local survivors
    survivors="$(pgrep -f "$marker" | tr '\n' ' ')"
    kill -9 $survivors >/dev/null 2>&1 || true
    log_fail "reparented leaky descendant SURVIVED the wrapper under dash (pids: $survivors) — set -m does not create a group under dash (P1)"
  fi
  # Regression: the new group mechanism must NOT break exit-code / timeout fidelity
  # under dash (setsid/perl exec keeps the pid, so wait sees the real status).
  dash "$RUN_TESTS_SCRIPT" sh -c 'exit 7' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 7 ]] || log_fail "exit-code fidelity broke under dash: exit 7 -> $rc"
  AAI_TEST_TIMEOUT=2 dash "$RUN_TESTS_SCRIPT" sh -c 'sleep 300' >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 124 ]] || log_fail "timeout must still map to 124 under dash (got $rc)"
  log_pass "wrapper under dash reaps the reparented child AND keeps exit/timeout fidelity (P1 fixed)"
}

# --- TEST-015 — P2: reaper kills the WHOLE matched tree incl. a token-less child --
# RED-proofed: the pre-fix reaper TERMs only the matched launcher pid, so a
# descendant whose argv dropped the vitest token survives. The tree/group kill turns
# it GREEN. Regression: a DIFFERENT-workspace tree and a FRESH sibling MUST still
# survive — the fix widens completeness for the matched target only, never the E1
# workspace scope or the etime guard.
test_015() {
  log_info "TEST-015: reaper kills the matched launcher AND its token-less descendant; other-ws + post-step-boundary fresh survive (P2, migrated)..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws other p_pid p_child o_pid o_child step_start fresh_pid out
  ws="$(mktemp -d "$TMP_ROOT/p2ws.XXXXXX")"
  other="$(mktemp -d "$TMP_ROOT/p2other.XXXXXX")"
  p_pid="$(spawn_parent_with_child "vitest_run_${ws}/worker")"
  o_pid="$(spawn_parent_with_child "vitest_run_${other}/worker")"
  # FOURTH site of the same zero-slack defect as TEST-006/013/017 — and a
  # REPEAT: commit eedea6d once widened this to `sleep 8` for exactly this
  # CI-load race, and the epoch-mode migration (d45fe4e) narrowed it back to 4 on
  # the reasoning the old comment here used ("comfortably beyond GRACE(2)").
  # That reasoning is WRONG: the pre-step gap must exceed
  # GRACE(2) + 1s etime floor-truncation + 1s `date +%s` quantization = 4s, so
  # `sleep 4` sat AT the conservative minimum — measured real slack was ~60ms,
  # supplied only by the pgrep/ps calls below. Restored to `sleep 8` (4s slack).
  # DO NOT NARROW: re-derive from GRACE first. The deterministic spare/reap
  # boundary itself is pinned by TEST-021, not by this margin.
  sleep 8   # let the forked child come up AND clear the epoch boundary band
  p_child="$(pgrep -P "$p_pid" | head -1)"
  o_child="$(pgrep -P "$o_pid" | head -1)"
  [[ -n "$p_child" ]] || log_fail "fixture: matched launcher $p_pid has no live child"
  track "$p_child"; [[ -n "$o_child" ]] && track "$o_child"
  # The descendant must NOT carry the token — that is the whole point of P2.
  if ps -o args= -p "$p_child" 2>/dev/null | grep -q "vitest"; then
    log_fail "fixture invalid: the descendant argv still carries the vitest token"
  fi
  # Step boundary captured HERE — both matched trees predate it; the fresh
  # sibling below is spawned at/after it and must survive DETERMINISTICALLY
  # (epoch guard by construction, not a margin-hope on ps etime granularity).
  step_start="$(date +%s)"
  fresh_pid="$(spawn_marked "vitest_fresh_${ws}/worker")"
  alive "$p_pid"   || log_fail "fixture: matched launcher $p_pid not alive"
  alive "$p_child" || log_fail "fixture: token-less child $p_child not alive"
  alive "$o_pid"   || log_fail "fixture: other-ws launcher $o_pid not alive"
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$p_pid"   && log_fail "reaper failed to kill the matched launcher $p_pid"
  alive "$p_child" && log_fail "reaper left the token-less descendant $p_child resident — matched tree not fully reaped (P2)"
  alive "$o_pid"   || log_fail "reaper over-reached: killed the DIFFERENT-workspace launcher $o_pid — E1 workspace scope broadened"
  if [[ -n "$o_child" ]]; then
    alive "$o_child" || log_fail "reaper over-reached: killed the DIFFERENT-workspace child $o_child — E1 workspace scope broadened"
  fi
  alive "$fresh_pid" || log_fail "reaper over-reached: killed a FRESH sibling $fresh_pid spawned at/after the step boundary — epoch guard broadened"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper must report a non-zero reaped count (got: $out)"
  log_pass "reaper reaps the matched launcher + its token-less descendant; other-ws tree and post-step-boundary sibling survive (P2 fixed; E1+epoch intact)"
}

# --- TEST-016 — epoch mode is invariant to injected reaper delay (Spec-AC-01/02) --
# RED-proofed: against a pre-change (fixed-threshold) reaper, the SAME scenario
# spares at delay=0 but FLIPS to reap at delay>=MIN_AGE+GRACE — the exact flake
# (PR #118/#119). The fixed reaper spares at BOTH delays because SNAP_NOW and the
# sampled etime grow together (overhead cancels out): start_epoch stays constant.
# AAI_REAP_MIN_AGE_SECS=5 is passed alongside STEP_START purely so the SAME
# invocation RED-proofs a pre-change reaper (which ignores STEP_START and falls
# back to its only guard, the fixed MIN_AGE); the fixed reaper's epoch mode
# ignores MIN_AGE entirely once STEP_START is valid.
test_016() {
  log_info "TEST-016: epoch mode — fresh sibling SPARED regardless of injected reaper delay (overhead-independent; RED-proofs the pre-change flake)..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws step_start fresh_pid out delay
  ws="$(mktemp -d "$TMP_ROOT/ws16.XXXXXX")"
  for delay in 0 7; do
    step_start="$(date +%s)"
    fresh_pid="$(spawn_marked "vitest_fresh16_${delay}_${ws}/worker")"
    alive "$fresh_pid" || log_fail "fixture setup: fresh proc $fresh_pid not alive (delay=$delay)"
    sleep "$delay"   # simulate reaper overhead / host load between step-start and the reap sweep
    out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" AAI_REAP_MIN_AGE_SECS=5 sh "$REAP_SCRIPT" 2>&1)"
    sleep 1
    if ! alive "$fresh_pid"; then
      log_fail "reaper killed a FRESH sibling $fresh_pid at injected delay=${delay}s — overhead not cancelled (reaper output: $out)"
    fi
    kill -9 "$fresh_pid" >/dev/null 2>&1 || true
  done
  log_pass "epoch mode spares the fresh sibling identically at delay=0 and delay=7s (overhead-independent, deterministic)"
}

# --- TEST-017 — epoch mode reaps a genuine pre-step survivor regardless of MIN_AGE (Spec-AC-01) --
test_017() {
  log_info "TEST-017: epoch mode — a genuine PRE-STEP survivor is REAPED even at a MIN_AGE the legacy fixed threshold would have used to spare it..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws survivor_pid step_start out
  ws="$(mktemp -d "$TMP_ROOT/ws17.XXXXXX")"
  # Survivor predates the step: spawn it, wait, THEN capture step_start — so
  # survivor's start_epoch is strictly before STEP_START-GRACE.
  survivor_pid="$(spawn_marked "vitest_survivor17_${ws}/worker")"
  # MARGIN — DO NOT NARROW. Epoch mode reaps iff
  #   start_epoch < STEP_START - GRACE,   start_epoch = SNAP_NOW - age
  # with GRACE(2) the reaper's production default and `age` derived from
  # `ps etime`, which is FLOOR-truncated to whole seconds — so the computed
  # start_epoch can read up to ~1s LATER than the true spawn instant. The
  # minimum theoretically-clearing gap is therefore GRACE(2) + 1s(truncation)
  # = 3s, and counting the additional 1s quantization of the `date +%s` that
  # captures step_start below it is GRACE(2) + 1 + 1 = 4s. The former `sleep 3`
  # sat EXACTLY ON that boundary with ZERO slack, and flaked under CI load
  # ("reaped: 0", observed on PR #129). `sleep 6` leaves 3s of slack under the
  # lenient model and 2s under the conservative one. DO NOT NARROW this back
  # toward 3s: re-derive the slack from GRACE first — the deterministic
  # spare/reap boundary itself is pinned by TEST-021, not by this margin.
  sleep 6
  step_start="$(date +%s)"
  alive "$survivor_pid" || log_fail "fixture setup: survivor proc $survivor_pid not alive"
  # MIN_AGE=999 is IRRELEVANT to epoch mode; if the reaper wrongly fell back to
  # legacy behavior here it would SPARE this (~6s old) survivor instead.
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" AAI_REAP_MIN_AGE_SECS=999 sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$survivor_pid" && log_fail "epoch mode failed to reap a genuine pre-step survivor $survivor_pid (reaper output: $out)"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper must report a non-zero reaped count (got: $out)"
  log_pass "epoch mode reaps a genuine pre-step survivor regardless of a high legacy MIN_AGE"
}

# --- TEST-018 — fail-safe: invalid/unset/future STEP_START -> exact legacy MIN_AGE behavior (Spec-AC-03) --
test_018() {
  log_info "TEST-018: fail-safe — unset/empty/non-integer/negative/non-positive/future AAI_REAP_STEP_START_EPOCH falls back to EXACT legacy MIN_AGE behavior; never global..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws invalid old_pid fresh_pid out future
  future=$(( $(date +%s) + 100000 ))
  # LOAD-IMMUNE MARGINS (do not "widen" a single threshold — that is what flaked).
  # Legacy mode is the UNCHANGED pre-epoch fixed-threshold path, so it still
  # carries the whole-second `ps etime` rounding + reaper-overhead race that epoch
  # mode exists to fix. One MIN_AGE cannot thread BOTH needles under CI load, so
  # each DIRECTION gets a threshold where load pushes it AWAY from failure:
  #   - reap-old   : MIN_AGE=1 vs a ~3s-old proc — overhead only ages it further
  #                  (more reapable), so this direction cannot flip.
  #   - spare-fresh: MIN_AGE=60 vs a ~0s proc — flipping needs a 60s stall between
  #                  spawn and the reaper's ps sample, which is not plausible.
  # Both directions still prove the LEGACY path was taken (invalid STEP_START).
  reap_run() {  # reap_run <invalid-case> <min-age>
    case "$1" in
      UNSET) AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS="$2" sh "$REAP_SCRIPT" 2>&1 ;;
      EMPTY) AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="" AAI_REAP_MIN_AGE_SECS="$2" sh "$REAP_SCRIPT" 2>&1 ;;
      *)     AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$1" AAI_REAP_MIN_AGE_SECS="$2" sh "$REAP_SCRIPT" 2>&1 ;;
    esac
  }
  for invalid in UNSET EMPTY "abc" "-5" "0" "$future"; do
    # STATE ISOLATION: a FRESH workspace per case so the reaper (which matches by
    # AAI_REAP_WORKSPACE) can NEVER match a marker process spawned by an earlier
    # case or the other direction — the shared-workspace pollution that flaked
    # the spare-fresh assertion under CI load (reaped a leaked cross-iteration
    # proc). The split-direction margins below are unchanged.
    ws="$(mktemp -d "$TMP_ROOT/ws18.XXXXXX")"
    # Direction 1 — legacy still REAPS a genuine pre-threshold survivor.
    old_pid="$(spawn_marked "vitest_old18_${ws}/worker")"
    sleep 3
    alive "$old_pid" || log_fail "fixture setup: old proc $old_pid not alive (case='$invalid')"
    out="$(reap_run "$invalid" 1)"
    sleep 1
    if alive "$old_pid"; then
      kill -9 "$old_pid" >/dev/null 2>&1 || true
      log_fail "fail-safe broken (case='$invalid'): legacy MIN_AGE=1 should have reaped the ~3s-old match (reaper output: $out)"
    fi

    # Direction 2 — legacy still SPARES a genuine fresh sibling. ATTRIBUTION,
    # not a liveness proxy (SPEC test-018-legacy-spare-attribution / Spec-AC-03):
    # assert fresh_pid is NOT in the reaper's OWN reported reaped-pids list, so
    # an EXTERNAL death of fresh_pid (a Linux ps-etime read race, an unrelated
    # runner kill) is no longer mis-attributed to the reaper. Only the reaper
    # actually reaping fresh_pid fails this direction — fresh_pid dying for a
    # non-reaper reason no longer flakes the test.
    fresh_pid="$(spawn_marked "vitest_fresh18_${ws}/worker")"
    alive "$fresh_pid" || log_fail "fixture setup: fresh proc $fresh_pid not alive (case='$invalid')"
    out="$(reap_run "$invalid" 60)"
    sleep 1
    # On ANY reaped>0 in this spare-fresh direction (suspicious under this
    # ~0s-fresh / MIN_AGE=60 fixture), DUMP evidence (Spec-AC-04): the
    # workspace-scoped `ps` snapshot + each reported pid's parsed etime — so a
    # Linux `ps etime` read-race that recurs in CI is captured with the data
    # needed to root-cause it. Silent on the normal `reaped: 0` path (no noise).
    if echo "$out" | grep -qiE "reaped: *[1-9]"; then
      {
        echo "DIAG(test_018 spare-fresh case='$invalid'): reaper reported reaped>0 — evidence follows"
        echo "DIAG reaper output: $out"
        echo "DIAG workspace ps snapshot (pid ppid etime args, scoped to $ws):"
        ps axo pid=,ppid=,etime=,args= 2>/dev/null | grep -F "$ws" || true
        for _rp in $(reaped_pids_of "$out"); do
          echo "DIAG reported-pid $_rp parsed etime: $(ps -o etime= -p "$_rp" 2>/dev/null | tr -d ' ')"
        done
      } >&2
    fi
    if reaper_reaped_pid "$fresh_pid" "$out"; then
      log_fail "fail-safe broken (case='$invalid'): legacy MIN_AGE=60 reaper's OWN reaped-pids list claims the fresh match $fresh_pid (reaper output: $out)"
    fi
    # Guaranteed teardown of BOTH marker processes before the next case — a
    # reap-old that missed under load must not leak old_pid into a later case
    # (the fresh workspace above already isolates, but leave nothing running).
    kill -9 "$old_pid" "$fresh_pid" >/dev/null 2>&1 || true
  done
  log_pass "invalid/unset/future STEP_START falls back to EXACT legacy MIN_AGE behavior for every case (never global)"
}

# --- TEST-019 — portability: epoch mode is ps etime + date +%s ONLY (Spec-AC-04) --
test_019() {
  log_info "TEST-019: portability — epoch mode uses ONLY ps etime + date +%s; no ps -o lstart, no date -d/-j string parsing..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  # Static guard on CODE only (comments legitimately name the forbidden
  # constructs to document why they're avoided — strip comments first, same
  # technique TEST-013 uses for the [[ ]] guard).
  local code
  code="$(sed 's/#.*$//' "$REAP_SCRIPT")"
  echo "$code" | grep -qE 'lstart' \
    && log_fail "reaper must not parse ps -o lstart (BSD/GNU epoch-parsing minefield, LEARNED 2026-07-19)"
  echo "$code" | grep -qE 'date -d|date -j' \
    && log_fail "reaper must not use date -d/-j string parsing (BSD/GNU minefield, LEARNED 2026-07-19)"
  grep -qF 'AAI_REAP_STEP_START_EPOCH' "$REAP_SCRIPT" \
    || log_fail "reaper must support AAI_REAP_STEP_START_EPOCH (epoch mode not implemented)"
  grep -qE 'date \+%s' "$REAP_SCRIPT" \
    || log_fail "reaper must capture the snapshot instant via date +%s"
  log_pass "reaper source uses only ps etime + date +%s (no lstart, no date -d/-j string parsing)"
}

# --- TEST-020 — producer wiring documented in SKILL_LOOP + VALIDATION (Spec-AC-06) --
test_020() {
  log_info "TEST-020: grep SKILL_LOOP + VALIDATION — step owner captures AAI_REAP_STEP_START_EPOCH=\$(date +%s) at the step boundary and hands it to the reaper..."
  [[ -f "$SKILL_LOOP_DOC" ]] || log_fail "missing $SKILL_LOOP_DOC"
  [[ -f "$VALIDATION_DOC" ]] || log_fail "missing $VALIDATION_DOC"
  local doc
  for doc in "$SKILL_LOOP_DOC" "$VALIDATION_DOC"; do
    grep -qF "AAI_REAP_STEP_START_EPOCH" "$doc" \
      || log_fail "$doc must document capturing/passing AAI_REAP_STEP_START_EPOCH"
    grep -qE 'date \+%s' "$doc" \
      || log_fail "$doc must document capturing the step-start epoch via date +%s"
  done
  log_pass "SKILL_LOOP and VALIDATION document the step-start-epoch capture + handoff to the reaper"
}

# --- TEST-021 — deterministic epoch-boundary probe: SPARE at it, REAP past it (Spec-AC-02) --
# Companion to TEST-017, not a duplicate. TEST-017 positions its survivor with a
# real wall-clock gap (proving the end-to-end ps/date sampling path against a
# realistic pre-step leak); this test instead pins the spare-vs-reap DECISION by
# INJECTING AAI_REAP_STEP_START_EPOCH computed with integer arithmetic from a
# reference epoch captured immediately BEFORE the spawn — so the outcome cannot
# drift with host load at all. Both step_start values stay in the PAST, so epoch
# mode really is active (a FUTURE value would trip the legacy fail-safe, which is
# TEST-018's job, not this one's).
#
# Arithmetic. With ref_epoch = floor(T0) captured just before the spawn, the
# reaper computes start_epoch = SNAP_NOW - age = ref_epoch - floor(g - f - d),
# where f = frac(T0), g = frac(the reaper's own snapshot instant) and d = the
# spawn delay. floor(g - f - d) <= 0 always (g < 1), and is >= -1 whenever
# d < 1s, so start_epoch lands in {ref_epoch, ref_epoch+1} — NEVER below
# ref_epoch. Hence:
#   Case A  step_start = ref_epoch + GRACE      -> threshold = ref_epoch
#           start_epoch < ref_epoch is impossible          => SPARE by construction
#   Case B  step_start = ref_epoch + GRACE + 2  -> threshold = ref_epoch + 2
#           start_epoch <= ref_epoch+1 < ref_epoch+2       => REAP  by construction
# The +2 in Case B clears the WHOLE {ref_epoch, ref_epoch+1} band. Measured
# (macOS, 20 samples over offsets GRACE+0..GRACE+3): start_epoch - ref_epoch was
# 0 every time, so GRACE+1 already reaped and GRACE+2 carries a full extra second
# of margin over the observed reading while still covering the theoretical
# ref_epoch+1 case. DO NOT NARROW +2 to +1: that puts the ref_epoch+1 reading
# exactly ON the threshold — the same zero-slack mistake TEST-017 above documents.
#
# GRACE below MUST track aai-reap-tests.sh's own AAI_REAP_GRACE_SECS default (2).
# The test deliberately does NOT override that env var, so it exercises the
# PRODUCTION default; if the reaper's default ever changes, this constant must
# change with it.
test_021() {
  log_info "TEST-021: epoch mode — injected STEP_START pins the boundary deterministically: SPARE at ref+GRACE, REAP at ref+GRACE+2..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws grace ref_epoch survivor_pid step_start out
  grace=2
  ws="$(mktemp -d "$TMP_ROOT/ws21.XXXXXX")"
  # ref_epoch BEFORE the spawn: a `date +%s` taken earlier can only floor to the
  # same or an earlier second than the true spawn instant.
  ref_epoch="$(date +%s)"
  survivor_pid="$(spawn_marked "vitest_boundary21_${ws}/worker")"
  sleep 4   # clear of the etime 0-1s rounding edge (same idiom as TEST-015), and
            # enough that both injected step_start values are already in the past
  alive "$survivor_pid" || log_fail "fixture setup: survivor proc $survivor_pid not alive"

  # Case A — AT the boundary: threshold == ref_epoch => must SPARE.
  step_start=$(( ref_epoch + grace ))
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$survivor_pid" || log_fail "Case A: reaper killed the survivor $survivor_pid AT the boundary (ref_epoch=$ref_epoch step_start=$step_start threshold=$(( step_start - grace )); reaper output: $out)"
  echo "$out" | grep -qxE "reaped: *0" || log_fail "Case A: reaper must report 'reaped: 0' at the boundary (got: $out)"

  # Case B — 2s PAST the boundary: threshold == ref_epoch+2 => must REAP.
  step_start=$(( ref_epoch + grace + 2 ))
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_STEP_START_EPOCH="$step_start" sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$survivor_pid" && log_fail "Case B: reaper failed to reap the survivor $survivor_pid past the boundary (ref_epoch=$ref_epoch step_start=$step_start threshold=$(( step_start - grace )); reaper output: $out)"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "Case B: reaper must report a non-zero reaped count past the boundary (got: $out)"
  log_pass "epoch boundary pinned by arithmetic: SPARE at ref+GRACE, REAP at ref+GRACE+2 (no wall-clock race)"
}

ALL_TESTS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015 016 017 018 019 020 021"

main() {
  echo "Testing $TEST_NAME (process-group wrapper + workspace/etime-scoped reaper + wiring)"
  check_deps
  local selected="$*"
  [[ -n "$selected" ]] || selected="$ALL_TESTS"
  local t
  for t in $selected; do
    t="${t#TEST-}"
    "test_${t}"
  done
  echo ""
  log_pass "All selected $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
