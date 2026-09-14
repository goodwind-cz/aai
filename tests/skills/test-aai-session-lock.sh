#!/usr/bin/env bash
#
# Test: per-worktree session lock (CHANGE-0180 D5 /
# docs/specs/SPEC-0179-spec-test-framework-sweep.md Spec-AC-05).
# Verifies .aai/scripts/lib/session-lock.mjs — an O_EXCL CAS lock keyed on
# PID LIVENESS rather than a TTL: a live holder refuses the acquire (exit 3,
# naming the holder pid + worktree); a holder whose pid is gone is reclaimed
# through the same serialized sentinel docs-lock.mjs uses. Implements
# TEST-409 and TEST-410 from the frozen spec (TEST-4xx band, spec-test-
# framework-sweep).
#
# The lib module under test is overridable via SESSION_LOCK_SCRIPT so the
# RED phase can prove these tests genuinely discriminate against a pre-change
# tree (module absent -> every `node -e "import(...)"` fails loudly, never a
# silent pass).
#
# Usage:
#   bash tests/skills/test-aai-session-lock.sh            # run all
#   bash tests/skills/test-aai-session-lock.sh 409 410     # run only selected
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-session-lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

LOCK_LIB="${SESSION_LOCK_SCRIPT:-$PROJECT_ROOT/.aai/scripts/lib/session-lock.mjs}"

TMP_ROOT=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-session-lock-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Create a throwaway git repo with an initial commit on `main`, print its path.
make_repo() {  # make_repo <slug>
  local repo
  repo="$(mktemp -d "$TMP_ROOT/${1}.XXXXXX")"
  git init -b main "$repo" >/dev/null 2>&1
  ( cd "$repo" \
    && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit \
         --allow-empty -m init >/dev/null 2>&1 )
  echo "$repo"
}

# Run the lock CLI inside <repo>; capture stdout to OUT, stderr to ERR, rc to RC.
OUT=""; ERR=""; RC=0
run_lock() {  # run_lock <repo> <subcommand> [args...]
  local repo="$1"; shift
  local errf
  errf="$(mktemp "$TMP_ROOT/err.XXXXXX")"
  OUT="$( cd "$repo" && node "$LOCK_LIB" "$@" 2>"$errf" )"; RC=$?
  ERR="$(cat "$errf")"
  rm -f "$errf"
}

# Resolve the lock path for <repo> via the module's own exported function
# (never re-derived in the test — a duplicated derivation could agree with a
# bug in the module and still pass).
lock_path_for() {  # lock_path_for <repo>
  ( cd "$1" && node --input-type=module -e "
    import { lockPath } from '$LOCK_LIB';
    process.stdout.write(lockPath(process.cwd()));
  " )
}

# --- TEST-409 — pid-liveness CAS: live holder refuses, dead holder reclaims,
#     N concurrent acquires yield exactly one winner (Spec-AC-05) ------------
test_409() {
  log_info "TEST-409: live holder refuses (exit 3, names pid+worktree); dead holder reclaims (exit 0); N-concurrent -> exactly one winner..."
  local repo repo_real; repo="$(make_repo t409)"
  # git resolves symlinks (macOS: /var -> /private/var), so the worktree
  # string the module records is the REALPATH, not $repo's raw mktemp spelling.
  repo_real="$( cd "$repo" && pwd -P )"

  # -- (a) live holder refuses --
  # A real, definitely-alive OS process: `sleep` in the background. Its pid
  # is what the lock records as the holder — not the short-lived acquiring
  # CLI's own pid, which would already be dead by the time a second acquirer
  # checks liveness.
  local live_pid
  ( sleep 30 & echo $! ) > "$TMP_ROOT/live.pid" &
  wait
  live_pid="$(cat "$TMP_ROOT/live.pid")"
  kill -0 "$live_pid" 2>/dev/null \
    || log_fail "fixture setup: the background sleep process is not alive (pid $live_pid)"

  run_lock "$repo" acquire --pid "$live_pid" --ref t409
  [[ "$RC" -eq 0 ]] || log_fail "first acquire (live pid) must exit 0 (got $RC; stderr: $ERR)"

  run_lock "$repo" acquire --pid 999999
  [[ "$RC" -eq 3 ]] || log_fail "second acquire against a LIVE holder must exit 3 (got $RC; stderr: $ERR)"
  assert_payload_contains "$ERR" "$live_pid" "refusal must name the holding pid"
  assert_payload_contains "$ERR" "$repo_real" "refusal must name the holding worktree"

  # -- (b) dead holder reclaims --
  kill "$live_pid" 2>/dev/null || true
  local waited=0
  while kill -0 "$live_pid" 2>/dev/null; do
    sleep 0.2
    waited=$((waited + 1))
    [[ "$waited" -lt 50 ]] || log_fail "fixture teardown: pid $live_pid did not die in time"
  done

  run_lock "$repo" acquire --pid 424242
  [[ "$RC" -eq 0 ]] || log_fail "acquire against a DEAD holder must reclaim and exit 0 (got $RC; stderr: $ERR)"
  local status
  status="$( cd "$repo" && node --input-type=module -e "
    import { status } from '$LOCK_LIB';
    process.stdout.write(JSON.stringify(status(process.cwd())));
  " )"
  assert_payload_contains "$status" "\"pid\":424242" "reclaimed lock must record the new holder pid"

  run_lock "$repo" release --pid 424242
  [[ "$RC" -eq 0 ]] || log_fail "release by the true holder must exit 0 (got $RC; stderr: $ERR)"

  # -- (c) N concurrent acquires -> exactly one winner --
  # Every concurrent attempt names the SAME live pid ($$ — this test script's
  # own, alive for the whole race): whichever wins the O_EXCL create leaves a
  # fresh lock recording a pid that stays alive throughout, so every OTHER
  # concurrent attempt takes the live-holder-refuses branch deterministically
  # (never the reclaim branch racing against itself).
  local n=20 rcdir i
  rcdir="$(mktemp -d "$TMP_ROOT/rc.XXXXXX")"
  for ((i = 0; i < n; i++)); do
    (
      set +e
      ( cd "$repo" && node "$LOCK_LIB" acquire --pid "$$" >/dev/null 2>&1 )
      echo "$?" > "$rcdir/$i"
    ) &
  done
  wait
  local zeros threes total
  zeros="$(grep -lx 0 "$rcdir"/* 2>/dev/null | wc -l | tr -d ' ')"
  threes="$(grep -lx 3 "$rcdir"/* 2>/dev/null | wc -l | tr -d ' ')"
  total="$(ls -1 "$rcdir" | wc -l | tr -d ' ')"
  log_info "  results: $zeros winner(s), $threes contended, $total total"
  [[ "$total" -eq "$n" ]] || log_fail "expected $n results, got $total"
  [[ "$zeros" -eq 1 ]] || log_fail "exactly ONE concurrent acquire must exit 0 (got $zeros) — double-claim race"
  [[ "$threes" -eq $((n - 1)) ]] || log_fail "the other $((n - 1)) acquires must exit 3 (got $threes)"

  log_pass "live holder refuses naming pid+worktree; dead holder reclaims; N-concurrent acquires yield exactly one winner"
}

# --- TEST-410 — lock path is per-worktree: main checkout vs linked worktree
#     resolve to DIFFERENT paths and never share a lock (Spec-AC-05) ---------
test_410() {
  log_info "TEST-410: lock resolves under the per-worktree git-dir for the primary checkout and a linked worktree, and the two never share a lock..."
  local repo; repo="$(make_repo t410)"
  local wt="$TMP_ROOT/t410-linked-worktree"
  ( cd "$repo" && git worktree add -q -b t410-branch "$wt" ) \
    || log_fail "fixture setup: could not add a linked worktree"

  local main_git_dir wt_git_dir main_lock wt_lock
  main_git_dir="$( cd "$repo" && git rev-parse --git-dir )"
  wt_git_dir="$( cd "$wt" && git rev-parse --git-dir )"
  [[ "$main_git_dir" != "$wt_git_dir" ]] \
    || log_fail "fixture is not exercising distinct git-dirs (main=$main_git_dir wt=$wt_git_dir)"

  main_lock="$(lock_path_for "$repo")"
  wt_lock="$(lock_path_for "$wt")"
  [[ -n "$main_lock" && -n "$wt_lock" ]] || log_fail "lockPath() returned empty for main or linked worktree"
  [[ "$main_lock" != "$wt_lock" ]] \
    || log_fail "main checkout and linked worktree resolved to the SAME lock path: $main_lock"
  assert_payload_contains "$main_lock" "/aai/session.lock" "main lock path must live under .../aai/session.lock"
  assert_payload_contains "$wt_lock" "/aai/session.lock" "worktree lock path must live under .../aai/session.lock"

  # A lock acquired in the main checkout must NOT block an acquire in the
  # linked worktree (they are structurally different files), and vice versa.
  run_lock "$repo" acquire --pid "$$"
  [[ "$RC" -eq 0 ]] || log_fail "acquire in the main checkout must exit 0 (got $RC; stderr: $ERR)"
  run_lock "$wt" acquire --pid "$$"
  [[ "$RC" -eq 0 ]] || log_fail "acquire in the linked worktree must ALSO exit 0 — the two must not share a lock (got $RC; stderr: $ERR)"

  [[ -f "$main_lock" ]] || log_fail "main checkout lock file missing at $main_lock"
  [[ -f "$wt_lock" ]] || log_fail "linked worktree lock file missing at $wt_lock"

  log_pass "lock path is per-worktree (git-dir derived); main checkout and linked worktree never share a lock"
}

# --- TEST-457 (round 8, Codex P2) — a corrupt/unparseable lock file is
#     reclaimed (dead-OR-corrupt), never a permanent wedge ------------------
test_457() {
  log_info "TEST-457: a corrupt/unparseable lock file is reclaimed on acquire, never a permanent wedge..."
  local repo; repo="$(make_repo t457)"
  local lock_file; lock_file="$(lock_path_for "$repo")"
  mkdir -p "$(dirname "$lock_file")"
  # A half-written lock: valid start, no closing brace — exactly the shape a
  # holder that died mid-write (after `openSync(..., 'wx')`, before
  # `writeSync(payload)` completed) leaves behind. `readLock` parses this as
  # null (JSON.parse throws, caught) — the SAME null a truly-gone holder's
  # absent file produces — so the reclaim path must treat them alike.
  printf '{"pid": 12345, "worktree": "/tmp/x", "ref_id":' > "$lock_file"

  run_lock "$repo" acquire --pid 555555 --ref t457
  [[ "$RC" -eq 0 ]] || log_fail "acquire against a corrupt lock file must reclaim it (exit 0), got $RC; stderr: $ERR"
  local status
  status="$( cd "$repo" && node --input-type=module -e "
    import { status } from '$LOCK_LIB';
    process.stdout.write(JSON.stringify(status(process.cwd())));
  " )"
  assert_payload_contains "$status" "\"pid\":555555" "reclaimed lock must record the NEW holder pid, not the corrupt bytes it replaced"

  # Not a one-shot fluke: corrupt it again (different garbage — not even
  # JSON-shaped) and reclaim again. Bug shape (P2 finding): the old code only
  # ran `fs.rmSync(p, ...)` when `readLock(p)` returned a TRUTHY value, so a
  # corrupt file (readLock -> null) was NEVER removed — the reclaim's own
  # `openSync(p, 'wx')` then hit the SAME EEXIST forever, and every
  # subsequent acquire repeated exit 3 with holderPid/holderWorktree both
  # null (a permanent, self-inflicted wedge visible only as "held by pid
  # null" — the file on disk never changes again without manual deletion).
  printf 'not even close to json' > "$lock_file"
  run_lock "$repo" acquire --pid 555556 --ref t457
  [[ "$RC" -eq 0 ]] || log_fail "a SECOND corrupt lock must ALSO reclaim (exit 0) — not a one-shot fluke (got $RC; stderr: $ERR)"
  assert_payload_not_contains "$ERR" "pid null" "a reclaimed acquire must never still be reporting the P2 'held by pid null' wedge"

  log_pass "a corrupt/unparseable lock file is reclaimed on acquire (twice, independently), never a permanent wedge"
}

# --- TEST-458 (round 8, Codex P1) — the SESSION-LIVED-owner fix itself:
#     a lock keyed on the PARENT pid ($PPID) survives the acquiring
#     one-shot shell's own exit; a lock keyed on that shell's OWN pid ($$)
#     is immediately reclaimable once it exits — the exact bug an agent's
#     per-command one-shot shell execution model triggers in the field
#     (Spec-AC-05 amendment) ----------------------------------------------
test_458() {
  log_info "TEST-458: a lock keyed on \$PPID survives its acquiring shell's exit; keyed on \$\$ it is reclaimable immediately..."
  local repo; repo="$(make_repo t458)"

  # (a) $PPID case — the REAL calling shape the prompts now use. Deliberately
  # NOT wrapped in an extra `( cd ... && bash -c ... )` subshell — THAT
  # subshell would itself be a one-shot process and die the instant the
  # compound command finishes, making its OWN pid the thing $PPID resolves
  # to inside the nested bash -c (silently reproducing the very bug this
  # test exists to rule out, one level removed). Running `bash -c` directly
  # from this function's own shell makes $PPID resolve to THIS TEST SCRIPT's
  # pid ($$) — alive for the whole suite run, same as an agent's one-shot
  # command shell's parent (the harness) is alive for its whole session.
  bash -c 'cd "$1" && node "$2" acquire --pid "$PPID" --ref t458a' _ "$repo" "$LOCK_LIB" \
    >/dev/null 2>"$TMP_ROOT/458a.err"
  [[ $? -eq 0 ]] || log_fail "PPID acquire (arm a) must exit 0: $(cat "$TMP_ROOT/458a.err")"
  # The acquiring one-shot shell has already exited (the `bash -c` above
  # returned) — a SECOND, independent one-shot shell probing the SAME
  # worktree must see the lock STILL held and STILL live, because the
  # recorded pid ($PPID = this test script's own pid) never exited. Run the
  # SAME way: directly from this shell, no extra subshell layer.
  local out2 rc2
  out2="$(bash -c 'cd "$1" && node "$2" acquire --pid 909090 --ref t458a-second' _ "$repo" "$LOCK_LIB" 2>&1)"; rc2=$?
  [[ "$rc2" -eq 3 ]] || log_fail "a second session must be REFUSED (exit 3) after the acquiring one-shot shell exited, if the lock is keyed on a session-lived \$PPID (got $rc2: $out2)"
  assert_payload_contains "$out2" "$$" "the still-held lock must name THIS test script's own pid ($$) as the live holder"

  # round 9 (F-6): owner_kind was stamped by acquire() and read by nothing —
  # status() now surfaces it; assert the CLI's `status` JSON line actually
  # carries it rather than leaving the field write-only.
  run_lock "$repo" status
  [[ "$RC" -eq 0 ]] || log_fail "status must exit 0 while the lock is held (got $RC; stderr: $ERR)"
  assert_payload_contains "$OUT" '"owner_kind":"harness-parent"' "status must surface the owner_kind stamp acquire() wrote (got: $OUT)"

  run_lock "$repo" release --pid "$$"
  [[ "$RC" -eq 0 ]] || log_fail "cleanup: release of the PPID-held lock (arm a) must exit 0 (got $RC; stderr: $ERR)"

  # (b) $$ case — the OLD, now-wrong calling shape (a fresh worktree, so it
  # cannot collide with arm (a)'s already-released lock). The acquiring
  # `bash -c` subshell's OWN $$ dies the instant that subshell exits — by
  # the time this `bash -c` above returns, the recorded holder pid is
  # ALREADY DEAD. A second acquire must therefore reclaim it immediately
  # (exit 0), never refuse — this IS the bug the prompts used to have.
  local repo2; repo2="$(make_repo t458b)"
  bash -c 'cd "$1" && node "$2" acquire --pid "$$" --ref t458b' _ "$repo2" "$LOCK_LIB" \
    >/dev/null 2>"$TMP_ROOT/458b.err"
  [[ $? -eq 0 ]] || log_fail "\$\$ acquire (arm b, first) must exit 0: $(cat "$TMP_ROOT/458b.err")"
  local out3 rc3
  out3="$(bash -c 'cd "$1" && node "$2" acquire --pid 909091 --ref t458b-second' _ "$repo2" "$LOCK_LIB" 2>&1)"; rc3=$?
  [[ "$rc3" -eq 0 ]] || log_fail "a second session must RECLAIM (exit 0) when the first was keyed on \$\$ (its shell already exited) — got $rc3: $out3 (if this refuses, \$\$ is somehow still alive, which would invalidate this arm's fixture rather than prove the fix)"

  log_pass "a \$PPID-keyed lock survives its acquiring one-shot shell's exit (refused, live); a \$\$-keyed lock does not (reclaimed immediately) — the exact real-execution-model bug and its fix"
}

ALL_TESTS="409 410 457 458"

main() {
  echo "Testing $TEST_NAME (per-worktree session lock, pid-liveness CAS)"
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
