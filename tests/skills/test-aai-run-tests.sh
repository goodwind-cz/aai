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
SPAWNED_PIDS=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

track() { SPAWNED_PIDS="$SPAWNED_PIDS $1"; }

cleanup() {
  local p
  for p in $SPAWNED_PIDS; do
    kill -9 "$p" >/dev/null 2>&1 || true
  done
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

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v ps >/dev/null 2>&1 || log_skip "ps not found"
  command -v pgrep >/dev/null 2>&1 || log_skip "pgrep not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-run-tests-test.XXXXXX")"
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

# --- TEST-006 — etime guard: fresh sibling spared, old reaped (Spec-AC-06) ----
test_006() {
  log_info "TEST-006: etime guard — a fresh (younger-than-threshold) matching proc is NOT reaped; an older one IS..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws old_pid fresh_pid out
  ws="$(mktemp -d "$TMP_ROOT/ws6.XXXXXX")"
  # Old matching process: spawn, then let it age past the threshold.
  old_pid="$(spawn_marked "vitest_old_${ws}/worker")"
  sleep 8
  # Fresh matching process (same workspace): started just now.
  fresh_pid="$(spawn_marked "vitest_fresh_${ws}/worker")"
  alive "$old_pid" || log_fail "fixture setup: old proc $old_pid not alive"
  alive "$fresh_pid" || log_fail "fixture setup: fresh proc $fresh_pid not alive"
  # Threshold 5s, old sleeps 8s: wide margins on BOTH sides (old comfortably >
  # threshold; fresh comfortably < threshold) so the whole-second `ps etime`
  # granularity plus a loaded/throttled CI runner's fork+exec/ps-snapshot
  # latency between "fresh spawned" and "reaper samples etime" (a real timing
  # race — not an etime-format bug — observed on Linux CI with the old 3s/2s
  # margins) cannot push a genuinely-fresh sibling's observed age across the
  # threshold. old (~8s) is eligible, fresh (~0s, needs <5s of overhead to
  # stay spared) is a sibling's in-flight run.
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=5 sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$old_pid" && log_fail "reaper failed to reap the OLD matching proc $old_pid"
  alive "$fresh_pid" || log_fail "reaper killed a FRESH sibling $fresh_pid younger than the step-start threshold — concurrency guard violated"
  log_pass "etime guard reaps the old tree and spares the fresh concurrent sibling"
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
    log_pass "reaper runs clean under POSIX sh (dash): no bashisms, guard + etime path work (W1 fixed)"
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
  log_info "TEST-015: reaper kills the matched launcher AND its token-less descendant; other-ws + fresh survive (P2)..."
  [[ -f "$REAP_SCRIPT" ]] || log_fail "reaper script not found: $REAP_SCRIPT"
  local ws other p_pid p_child o_pid o_child fresh_pid out
  ws="$(mktemp -d "$TMP_ROOT/p2ws.XXXXXX")"
  other="$(mktemp -d "$TMP_ROOT/p2other.XXXXXX")"
  p_pid="$(spawn_parent_with_child "vitest_run_${ws}/worker")"
  o_pid="$(spawn_parent_with_child "vitest_run_${other}/worker")"
  sleep 8   # let both matched trees age well past the 5s threshold below
  p_child="$(pgrep -P "$p_pid" | head -1)"
  o_child="$(pgrep -P "$o_pid" | head -1)"
  [[ -n "$p_child" ]] || log_fail "fixture: matched launcher $p_pid has no live child"
  track "$p_child"; [[ -n "$o_child" ]] && track "$o_child"
  # The descendant must NOT carry the token — that is the whole point of P2.
  if ps -o args= -p "$p_child" 2>/dev/null | grep -q "vitest"; then
    log_fail "fixture invalid: the descendant argv still carries the vitest token"
  fi
  # Fresh sibling in the SAME workspace, spawned just now (younger than threshold).
  fresh_pid="$(spawn_marked "vitest_fresh_${ws}/worker")"
  alive "$p_pid"   || log_fail "fixture: matched launcher $p_pid not alive"
  alive "$p_child" || log_fail "fixture: token-less child $p_child not alive"
  alive "$o_pid"   || log_fail "fixture: other-ws launcher $o_pid not alive"
  # Threshold 5s, matched trees sleep 8s: wide margins on BOTH sides (see
  # TEST-006's comment for why — a real Linux-CI timing race, not an etime
  # format bug: whole-second `ps etime` granularity plus a loaded runner's
  # fork+exec/ps-snapshot latency between "fresh spawned" and "reaper samples
  # etime" could push the old 3s/2s margins' fresh sibling across the
  # threshold). The matched trees (~8s) are eligible; the fresh sibling (~0s,
  # needs <5s of overhead to stay spared) is not.
  out="$(AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=5 sh "$REAP_SCRIPT" 2>&1)"
  sleep 1
  alive "$p_pid"   && log_fail "reaper failed to kill the matched launcher $p_pid"
  alive "$p_child" && log_fail "reaper left the token-less descendant $p_child resident — matched tree not fully reaped (P2)"
  alive "$o_pid"   || log_fail "reaper over-reached: killed the DIFFERENT-workspace launcher $o_pid — E1 workspace scope broadened"
  if [[ -n "$o_child" ]]; then
    alive "$o_child" || log_fail "reaper over-reached: killed the DIFFERENT-workspace child $o_child — E1 workspace scope broadened"
  fi
  alive "$fresh_pid" || log_fail "reaper over-reached: killed a FRESH sibling $fresh_pid younger than the step-start threshold — etime guard broadened"
  echo "$out" | grep -qiE "reaped: *[1-9]" || log_fail "reaper must report a non-zero reaped count (got: $out)"
  log_pass "reaper reaps the matched launcher + its token-less descendant; other-ws tree and fresh sibling survive (P2 fixed; E1+etime intact)"
}

ALL_TESTS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 015"

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
