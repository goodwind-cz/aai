#!/usr/bin/env bash
#
# Test: aai-heartbeat (role-progress-heartbeat /
# SPEC-0164-spec-role-progress-heartbeat.md, TEST-001..014 and TEST-018).
#
# Verifies .aai/scripts/heartbeat.mjs — the advisory, machine-written progress
# signal a long-running dispatched role emits so an observer can read it
# WITHOUT asking the orchestrator:
#   - write: one JSON file per slot under <git-common-dir>/aai/heartbeat/,
#     resolved cwd-independently from the script's own location, so a role
#     writing inside a LINKED WORKTREE and an observer reading from the MAIN
#     checkout hit the same file (TEST-001/002, the load-bearing seam).
#   - refusals (exit 2, loud): a caller that cannot identify itself is a
#     WIRING bug and must never degrade into silence (TEST-006/007).
#   - degrades (exit 0, named note): unwritable directory, git absent. The
#     role's own outcome must never move because of a heartbeat, so absence
#     degrades to today's silence (TEST-008/009).
#   - read: cold start prints exactly `heartbeat: none recorded` (TEST-003); a
#     corrupt slot is NAMED, never read as "nothing there" (TEST-010).
#   - NEVER GATES ANYTHING: TEST-012 sweeps the WHOLE .aai/scripts corpus
#     deny-by-default (heartbeat.mjs is the only allowlisted file) rather than
#     an enumerated list of
#     gates, whose forgotten member is where the hole lives. The anti-pattern
#     it guards shipped once already (SPEC-0163 / PR #334) and cost three
#     validation rounds.
#
# The shipping repository is NEVER written: every fixture is built under this
# suite's own TEST_DIR, and each case either sets AAI_HEARTBEAT_DIR or drives a
# fixture repo of its own. bash-3.2 compatible (no associative arrays, no
# mapfile, no ${var^^}).
#
# FIXTURE TRAP pinned here on purpose: every `git init` is immediately followed
# by `git symbolic-ref HEAD refs/heads/main`, because a fresh repository takes
# HEAD from the PER-MACHINE `init.defaultBranch` — a fixture that relies on the
# default branch name is green on this host and red on CI.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -uo pipefail

TEST_NAME="aai-heartbeat"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HB="$PROJECT_ROOT/.aai/scripts/heartbeat.mjs"
VALIDATION_PROMPT="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"

# shellcheck source=tests/skills/lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

TEST_DIR=""
FAILED=0

# Captured by run_hb: stdout, stderr and the real exit code of one invocation.
OUT=""
ERR=""
RC=0

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"; return 0
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    chmod -R u+w "$TEST_DIR" 2>/dev/null || true
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

# run_hb <script> <args...> — run one heartbeat invocation and capture stdout,
# stderr and the exit code into OUT/ERR/RC. `|| RC=$?` (never a bare `rc=$?`
# on the next line) so this is correct under every shell-option combination a
# caller might impose.
run_hb() {
  local script="$1"; shift
  RC=0
  node "$script" "$@" >"$TEST_DIR/hb.out" 2>"$TEST_DIR/hb.err" || RC=$?
  OUT="$(cat "$TEST_DIR/hb.out")"
  ERR="$(cat "$TEST_DIR/hb.err")"
}

# make_repo <dir> — a real, non-bare fixture repository carrying a COPY of the
# heartbeat script and the two libraries it imports, committed, so a linked
# worktree of it has a runnable script of its own.
make_repo() {
  local root="$1"
  mkdir -p "$root/.aai/scripts/lib"
  cp "$HB" "$root/.aai/scripts/heartbeat.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/runtime-file.mjs" "$root/.aai/scripts/lib/"
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$root/.aai/scripts/lib/"
  git -C "$root" init -q .
  # PER-MACHINE init.defaultBranch trap: pin HEAD so `git worktree add` has a
  # deterministic branch to fork from on every host, not just this one.
  git -C "$root" symbolic-ref HEAD refs/heads/main
  git -C "$root" config user.email "heartbeat@test.invalid"
  git -C "$root" config user.name "heartbeat test"
  git -C "$root" add -A
  git -C "$root" commit -qm "fixture"
}

# count_slots <dir> — number of THIS FEATURE's slot files, 0 when the directory
# is absent. Bounded by the same `hb-` prefix the writer, the reader and the GC
# are bounded by: a caller-named directory may hold foreign `.json` files, and a
# prefix-blind `-name '*.json'` count would silently include them.
count_slots() {
  local dir="$1" n=0
  [[ -d "$dir" ]] || { echo 0; return; }
  n="$(find "$dir" -maxdepth 1 -name 'hb-*.json' -type f | wc -l | tr -d ' ')"
  echo "$n"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  [[ -f "$HB" ]] || { log_fail "heartbeat.mjs not found: $HB"; }
  [[ -f "$VALIDATION_PROMPT" ]] || { log_fail "VALIDATION prompt missing: $VALIDATION_PROMPT"; }
  # Every case passes AAI_HEARTBEAT_DIR as a per-command prefix, so an inherited
  # one from the caller's environment would silently redirect the arms that
  # deliberately exercise the git probe instead.
  unset AAI_HEARTBEAT_DIR
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-heartbeat-test.XXXXXX")"
  # REALPATH the fixture root. On macOS `mktemp -d` hands back /var/... while
  # git inside a linked worktree reports the resolved /private/var/... — the
  # same directory under two names. Without this, TEST-002 compares two
  # spellings of one location and fails for a reason that has nothing to do
  # with the code under test (measured on this host during the RED run).
  TEST_DIR="$(node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$TEST_DIR")"
}

# --- TEST-001 / Spec-AC-01 ----------------------------------------------------
# THE seam: written from a real linked worktree, read from the main checkout.
# A stand-in (two directories, one fixture) would prove nothing here — the whole
# design rests on `git rev-parse --git-common-dir` behaving differently in the
# two places, so the two places must be real.
test_001_worktree_to_main_checkout() {
  local root="$TEST_DIR/wt-seam/repo" wt="$TEST_DIR/wt-seam/wt"
  mkdir -p "$TEST_DIR/wt-seam"
  make_repo "$root"
  git -C "$root" worktree add -q "$wt" -b hb-wt

  # WRITE from inside the linked worktree, using the worktree's own copy.
  run_hb "$wt/.aai/scripts/heartbeat.mjs" write \
    --ref role-progress-heartbeat --role Validation --message "full sweep round 2 of 3"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-001: write from the linked worktree exited $RC (stderr: $(payload_preview "$ERR"))"
    return
  fi

  # The file must have landed under the MAIN checkout's .git, not the worktree's.
  local hbdir="$root/.git/aai/heartbeat"
  if [[ "$(count_slots "$hbdir")" -ne 1 ]]; then
    log_fail "TEST-001: expected exactly 1 slot under $hbdir, found $(count_slots "$hbdir")"
    return
  fi

  # READ from the MAIN checkout with its own copy of the script.
  run_hb "$root/.aai/scripts/heartbeat.mjs" read
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-001: read from the main checkout exited $RC (stderr: $(payload_preview "$ERR"))"
    return
  fi
  assert_payload_contains "$OUT" "role-progress-heartbeat" \
    "TEST-001: main-checkout read must name the slot written in the worktree" || return
  assert_payload_contains "$OUT" "full sweep round 2 of 3" \
    "TEST-001: main-checkout read must carry the worktree's message" || return
  assert_payload_contains "$OUT" "$wt" \
    "TEST-001: the payload must record the worktree the write actually ran in" || return
  log_pass "TEST-001 heartbeat written in a real linked worktree is read from the main checkout"
}

# --- TEST-002 / Spec-AC-01 ----------------------------------------------------
# The relative/absolute split, MEASURED rather than asserted from prose.
# git 2.50.1 on this host prints `.git` from the main root, `../.git` from a
# subdirectory of it, and an ABSOLUTE path from a linked worktree. All three
# must resolve to ONE absolute location; and `path.join` must be shown to be
# the wrong tool for at least one of them, or the pin is decorative.
test_002_common_dir_resolves_to_one_path() {
  local root="$TEST_DIR/wt-seam/repo" wt="$TEST_DIR/wt-seam/wt"
  local raw_root raw_sub raw_wt res_root res_sub res_wt joined_wt
  if [[ ! -d "$root/.git" || ! -d "$wt" ]]; then
    log_fail "TEST-002: the TEST-001 worktree fixture is missing, so this pin cannot run"
    return
  fi
  raw_root="$(git -C "$root" rev-parse --git-common-dir)"
  raw_sub="$(git -C "$root/.aai" rev-parse --git-common-dir)"
  raw_wt="$(git -C "$wt" rev-parse --git-common-dir)"
  log_info "TEST-002: raw --git-common-dir  root='$raw_root'  subdir='$raw_sub'  worktree='$raw_wt'"

  res_root="$(node -e 'process.stdout.write(require("path").resolve(process.argv[1], process.argv[2]))' "$root" "$raw_root")"
  res_sub="$(node -e 'process.stdout.write(require("path").resolve(process.argv[1], process.argv[2]))' "$root/.aai" "$raw_sub")"
  res_wt="$(node -e 'process.stdout.write(require("path").resolve(process.argv[1], process.argv[2]))' "$wt" "$raw_wt")"
  joined_wt="$(node -e 'process.stdout.write(require("path").join(process.argv[1], process.argv[2]))' "$wt" "$raw_wt")"

  if [[ "$res_root" != "$res_sub" || "$res_root" != "$res_wt" ]]; then
    log_fail "TEST-002: path.resolve must give ONE location (root='$res_root' sub='$res_sub' worktree='$res_wt')"
    return
  fi
  if [[ "$joined_wt" == "$res_wt" ]]; then
    log_fail "TEST-002: path.join agreed with path.resolve for the worktree case ('$joined_wt') — the trap this pin exists for is not being exercised"
    return
  fi
  log_pass "TEST-002 --git-common-dir resolves to one absolute path from root, subdir and worktree (path.join would land at '$joined_wt' instead)"
}

# --- TEST-003 / Spec-AC-02 ----------------------------------------------------
# Cold start. The intake's named defect is a reader that ERRORS when nothing has
# ever been written, so both the literal text and the exit code are pinned.
test_003_cold_read() {
  local dir="$TEST_DIR/cold/heartbeat"
  mkdir -p "$TEST_DIR/cold"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-003: cold read exited $RC, expected 0 (stderr: $(payload_preview "$ERR"))"
    return
  fi
  if [[ "$OUT" != "heartbeat: none recorded" ]]; then
    log_fail "TEST-003: cold read stdout must be exactly 'heartbeat: none recorded', got '$(payload_preview "$OUT")'"
    return
  fi
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read --json
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-003: cold read --json exited $RC, expected 0"
    return
  fi
  local shape
  shape="$(node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const ok = Array.isArray(o.slots) && o.slots.length === 0
      && Array.isArray(o.degraded) && o.degraded.length === 0
      && Object.keys(o).sort().join(",") === "degraded,slots";
    process.stdout.write(ok ? "ok" : "bad:" + JSON.stringify(o));
  ' "$TEST_DIR/hb.out" 2>&1)"
  if [[ "$shape" != "ok" ]]; then
    log_fail "TEST-003: cold read --json must be {slots:[],degraded:[]}, got $shape"
    return
  fi
  log_pass "TEST-003 cold read prints exactly 'heartbeat: none recorded' (exit 0) and an empty {slots,degraded}"
}

# --- TEST-004 / Spec-AC-03 ----------------------------------------------------
# Per-slot files, so there is no cross-process read-modify-write to lose an
# entry. Two CONCURRENT writers, then a repeat write that must touch only its
# own slot.
test_004_two_slots_survive_concurrency() {
  local dir="$TEST_DIR/concurrent/heartbeat"
  mkdir -p "$dir"
  AAI_HEARTBEAT_DIR="$dir" node "$HB" write --ref refA --role Validation --message "A round 1" >/dev/null 2>&1 &
  local pid_a=$!
  AAI_HEARTBEAT_DIR="$dir" node "$HB" write --ref refB --role CodeReview --message "B pass 1" >/dev/null 2>&1 &
  local pid_b=$!
  wait "$pid_a" || true
  wait "$pid_b" || true

  if [[ "$(count_slots "$dir")" -ne 2 ]]; then
    log_fail "TEST-004: two concurrent writers must leave 2 slots, found $(count_slots "$dir")"
    return
  fi

  # A second write for refA replaces only refA's slot.
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref refA --role Validation --message "A round 2"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-004: repeat write exited $RC"
    return
  fi
  if [[ "$(count_slots "$dir")" -ne 2 ]]; then
    log_fail "TEST-004: a repeat write must REPLACE its own slot, not add one (found $(count_slots "$dir"))"
    return
  fi
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read --json
  local check
  check="$(node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const byRef = {};
    for (const s of o.slots) byRef[s.ref_id] = s.message;
    const ok = o.slots.length === 2 && byRef.refA === "A round 2" && byRef.refB === "B pass 1";
    process.stdout.write(ok ? "ok" : "bad:" + JSON.stringify(o.slots));
  ' "$TEST_DIR/hb.out" 2>&1)"
  if [[ "$check" != "ok" ]]; then
    log_fail "TEST-004: expected refA replaced and refB untouched, got $check"
    return
  fi
  log_pass "TEST-004 two concurrent writers keep both slots; a repeat write replaces only its own"
}

# --- TEST-005 / Spec-AC-04 ----------------------------------------------------
# Sanitization and truncation. A chatty role must be truncated, never refused.
test_005_sanitize_and_truncate() {
  local dir="$TEST_DIR/sanitize/heartbeat"
  mkdir -p "$dir"
  local dirty
  dirty="$(node -e 'process.stdout.write("round\u00012 of\u0085 and\u202E 3")')"
  # The REF and ROLE carry dirty bytes too, not just the message: without that
  # the ref_id/role half of the assertion below would be vacuous, since a clean
  # input is clean however it is stored.
  local dirty_ref dirty_role
  dirty_ref="$(node -e 'process.stdout.write("ref\u202ES")')"
  dirty_role="$(node -e 'process.stdout.write("Valid\u0001ation")')"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref "$dirty_ref" --role "$dirty_role" --message "$dirty"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-005: write with control/bidi bytes exited $RC (stderr: $(payload_preview "$ERR"))"
    return
  fi
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read --json
  local stored
  stored="$(node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const s0 = o.slots[0] || {};
    // ref_id and role are printed to the same terminal as the message, so the
    // same hazard class applies: a bidi override in a ref would reorder
    // everything after it. They are checked here rather than in an arm of
    // their own because it is one Spec-AC-04 hazard, not three.
    const m = [s0.message, s0.ref_id, s0.role].join(" ");
    const dirtyRe = /[\u0000-\u001F\u007F-\u009F\u200E\u200F\u202A-\u202E\u2066-\u2069]/;
    // The surviving text matters as much as the stripped bytes: "carries no
    // control characters" is also true of an EMPTY string, so a sanitizer that
    // ate the whole message would pass a cleanliness-only check.
    if (dirtyRe.test(m)) process.stdout.write("dirty:" + JSON.stringify(m));
    else if (m.indexOf("round") < 0 || m.indexOf("3") < 0) process.stdout.write("lost:" + JSON.stringify(m));
    else process.stdout.write("clean:" + m);
  ' "$TEST_DIR/hb.out" 2>&1)"
  case "$stored" in
    clean:*) : ;;
    *) log_fail "TEST-005: the stored message must keep its readable text with control and bidi characters stripped ($stored)"; return ;;
  esac

  local long
  long="$(node -e 'process.stdout.write("x".repeat(300))')"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref refL --role Validation --message "$long"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-005: a 300-character message must be truncated, not refused (exit $RC)"
    return
  fi
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read --json --ref refL
  local len
  len="$(node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(((o.slots[0] || {}).message || "").length));
  ' "$TEST_DIR/hb.out" 2>&1)"
  if [[ "$len" != "200" ]]; then
    log_fail "TEST-005: a 300-character message must store exactly 200 characters, stored $len"
    return
  fi
  log_pass "TEST-005 control and bidi characters are stripped; a 300-character message stores exactly 200"
}

# --- TEST-006 / Spec-AC-04 (REJECTED input) -----------------------------------
# A message that sanitizes to nothing is a WIRING bug: it must be loud (exit 2)
# against the component's own literal text, not degrade into a nameless file.
test_006_reject_empty_after_sanitization() {
  local dir="$TEST_DIR/reject/heartbeat"
  mkdir -p "$dir"
  local ctl
  ctl="$(node -e 'process.stdout.write("\u0001\u0002\u202E\u0007")')"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref refR --role Validation --message "$ctl"
  if [[ "$RC" -ne 2 ]]; then
    log_fail "TEST-006: a control-characters-only message must exit 2, got $RC (stdout: $(payload_preview "$OUT"))"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: --message is empty after sanitization" \
    "TEST-006: the refusal must carry the component's own literal message" || return
  if [[ "$(count_slots "$dir")" -ne 0 ]]; then
    log_fail "TEST-006: a refused write must create no slot file (found $(count_slots "$dir"))"
    return
  fi
  log_pass "TEST-006 a control-characters-only message is REFUSED (exit 2, literal message, no file)"
}

# --- TEST-007 / Spec-AC-04 (REJECTED input) -----------------------------------
test_007_reject_missing_and_empty_ref() {
  local dir="$TEST_DIR/reject/heartbeat"
  mkdir -p "$dir"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --role Validation --message "round 1"
  if [[ "$RC" -ne 2 ]]; then
    log_fail "TEST-007: a missing --ref must exit 2, got $RC"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: --ref is required" \
    "TEST-007: a missing --ref must name itself" || return

  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref "" --role Validation --message "round 1"
  if [[ "$RC" -ne 2 ]]; then
    log_fail "TEST-007: a --ref that sanitizes empty must exit 2, got $RC"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: --ref is empty after sanitization" \
    "TEST-007: an empty-after-sanitization --ref must carry its own literal message" || return
  if [[ "$(count_slots "$dir")" -ne 0 ]]; then
    log_fail "TEST-007: a refused write must create no slot file (found $(count_slots "$dir"))"
    return
  fi
  log_pass "TEST-007 a missing --ref and an empty-after-sanitization --ref each REFUSE with their own literal message"
}

# --- TEST-008 / Spec-AC-05 (DEGRADED path) ------------------------------------
# The role's own outcome must never move because of a heartbeat.
test_008_unwritable_dir_degrades() {
  if [[ "$(id -u)" == "0" ]]; then
    log_info "TEST-008: running as root, a read-only directory is still writable — skipping this arm"
    return
  fi
  local parent="$TEST_DIR/unwritable"
  mkdir -p "$parent"
  chmod 555 "$parent"
  AAI_HEARTBEAT_DIR="$parent/heartbeat" run_hb "$HB" write \
    --ref refU --role Validation --message "round 1"
  local rc_seen="$RC"
  chmod 755 "$parent"
  if [[ "$rc_seen" -ne 0 ]]; then
    log_fail "TEST-008: an unwritable heartbeat directory must exit 0 (best effort), got $rc_seen"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: degraded —" \
    "TEST-008: an unwritable directory must print a NAMED degrade note on stderr" || return
  if [[ -d "$parent/heartbeat" ]]; then
    log_fail "TEST-008: a degraded write must create nothing, but $parent/heartbeat exists"
    return
  fi
  log_pass "TEST-008 an unwritable heartbeat directory degrades (exit 0, named note, nothing written)"
}

# --- TEST-009 / Spec-AC-05 (DEGRADED path) ------------------------------------
# git absent from PATH: the probe cannot run, so there is no location to write
# to. Absence degrades to today's silence, never to a new failure mode.
test_009_git_absent_degrades() {
  # process.execPath, not `command -v node`: on a host where node is a version-
  # manager SHIM (a shell script that itself needs PATH), emptying PATH would
  # break the interpreter rather than the git probe, and the arm would pass for
  # the wrong reason.
  local stub="$TEST_DIR/nogitbin" node_bin
  node_bin="$(node -e 'process.stdout.write(process.execPath)')"
  mkdir -p "$stub"
  # `hash -r` inside the probe subshell is load-bearing: bash CACHES resolved
  # command paths, so a bare `PATH=$stub command -v git` answers from the hash
  # table and reports git as reachable when it is not (this arm skipped itself
  # for exactly that reason during the RED run).
  if ( hash -r; PATH="$stub"; command -v git >/dev/null 2>&1 ); then
    log_info "TEST-009: git is still reachable from an empty PATH on this host — skipping this arm"
    return
  fi

  RC=0
  PATH="$stub" "$node_bin" "$HB" write \
    --ref refG --role Validation --message "round 1" \
    >"$TEST_DIR/hb.out" 2>"$TEST_DIR/hb.err" || RC=$?
  OUT="$(cat "$TEST_DIR/hb.out")"
  ERR="$(cat "$TEST_DIR/hb.err")"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-009: write with git absent must exit 0, got $RC (stderr: $(payload_preview "$ERR"))"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: degraded —" \
    "TEST-009: an absent git must print a NAMED degrade note on stderr" || return

  RC=0
  PATH="$stub" "$node_bin" "$HB" read \
    >"$TEST_DIR/hb.out" 2>"$TEST_DIR/hb.err" || RC=$?
  OUT="$(cat "$TEST_DIR/hb.out")"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-009: read with git absent must exit 0, got $RC"
    return
  fi
  if [[ "$OUT" != "heartbeat: none recorded" ]]; then
    log_fail "TEST-009: read with git absent must print 'heartbeat: none recorded', got '$(payload_preview "$OUT")'"
    return
  fi
  log_pass "TEST-009 an absent git degrades the write (exit 0, named note) and the read prints 'none recorded'"
}

# --- TEST-010 / Spec-AC-06 ----------------------------------------------------
# Class B: a damaged slot is NAMED, never read as "nothing there" and never
# allowed to hide the readable slots beside it.
test_010_corrupt_slot_named_not_dropped() {
  local dir="$TEST_DIR/corrupt/heartbeat"
  mkdir -p "$dir"
  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref refOk --role Validation --message "still fine"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-010: setup write exited $RC"
    return
  fi
  # The hb- prefix is what marks a file as THIS feature's, for reading as well
  # as for the GC sweep: an unprefixed file in a caller-named directory belongs
  # to someone else and is neither read nor reported as a damaged slot.
  printf '{ not json at all' > "$dir/hb-refBad__Validation.json"

  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-010: read with a corrupt slot must exit 0, got $RC"
    return
  fi
  assert_payload_contains "$OUT" "hb-refBad__Validation.json" \
    "TEST-010: the corrupt slot must be NAMED in the output" || return
  assert_payload_contains "$OUT" "still fine" \
    "TEST-010: the readable slot beside a corrupt one must still be printed" || return

  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" read --json
  local check
  check="$(node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const named = o.degraded.some((d) => String(d.source || "").indexOf("refBad") >= 0);
    const ok = o.slots.length === 1 && o.slots[0].ref_id === "refOk" && named;
    process.stdout.write(ok ? "ok" : "bad:" + JSON.stringify(o));
  ' "$TEST_DIR/hb.out" 2>&1)"
  if [[ "$check" != "ok" ]]; then
    log_fail "TEST-010: --json must carry the readable slot and name the corrupt one in degraded, got $check"
    return
  fi
  log_pass "TEST-010 a corrupt slot is named in both outputs, the readable slot survives, exit 0"
}

# --- TEST-011 / Spec-AC-07 ----------------------------------------------------
# Class D orphan GC, and the REAL BOUND on it. `--dir` / AAI_HEARTBEAT_DIR is a
# documented first-class override ("tests, and any host where the git probe
# cannot run"), so the directory is caller-named and may hold files this feature
# does not own.
#
# THE BOUND IS THE `hb-` PREFIX, NOT OWNERSHIP — and this arm asserts the bound
# that EXISTS rather than the one an earlier draft of Spec-AC-07 wished for.
# That draft said the sweep "leaves untouched every file it did not itself
# write"; validation falsified it by reproduction (an `hb-`-named file this
# script never wrote, aged past the window, was deleted at exit 0 with a success
# line). Both halves are pinned below, because a test that only plants
# UNPREFIXED foreign files is strictly weaker than the criterion it carries and
# would stay green under either mechanism:
#   - an UNPREFIXED foreign file SURVIVES  (the bound that is real)
#   - an `hb-`-PREFIXED foreign file IS REAPED  (the honest cost of that bound)
# The prefix bound was chosen over shape-gating on isSlotShape deliberately: a
# shape gate cannot cover the abandoned `<slot>.tmp.<pid>.<seq>` temps the sweep
# exists to collect, and it is more machinery than the risk warrants. Anyone
# pointing this feature at a shared directory must therefore keep `hb-` free.
#
# The window is also SYMMETRIC, not "older than": reapAsides delegates to
# isStale, which is stale iff |now - mtime| > window (runtime-file.mjs classes
# C+F — a far-future timestamp must never wedge a GC). A FUTURE-dated `hb-` file
# is therefore reaped too, and that is pinned here rather than left as folklore.
#
# Plus the cwd case, which is the unbounded-sweep defect at its worst:
# `--dir ""` resolves to the CURRENT DIRECTORY, so from the repo root — the
# canonical invocation directory — an unbounded sweep deletes every stale
# top-level file in the shipping repo. That is a USAGE error (exit 2), the same
# grade the other empty-value refusals already carry.
test_011_reap_stale_keep_fresh() {
  local dir="$TEST_DIR/reap/heartbeat"
  mkdir -p "$dir"
  AAI_HEARTBEAT_DIR="$dir" node "$HB" write --ref refOld --role Validation --message "yesterday" >/dev/null 2>&1
  AAI_HEARTBEAT_DIR="$dir" node "$HB" write --ref refRecent --role Validation --message "an hour ago" >/dev/null 2>&1
  if [[ "$(count_slots "$dir")" -ne 2 ]]; then
    log_fail "TEST-011: setup expected 2 slots, found $(count_slots "$dir")"
    return
  fi

  # Slot files carry a COMMON PREFIX so the sweep has something to be bounded
  # BY. Without it reapAsides is called with an empty prefix and matches every
  # entry in the directory, which is outside its documented terms.
  local old_slot="$dir/hb-refOld__Validation.json"
  local recent_slot="$dir/hb-refRecent__Validation.json"
  local new_slot="$dir/hb-refNew__Validation.json"
  if [[ ! -f "$old_slot" || ! -f "$recent_slot" ]]; then
    log_fail "TEST-011: slot files must carry the hb- prefix that bounds the GC sweep; expected $old_slot and $recent_slot, found: $(find "$dir" -maxdepth 1 -name '*.json' -type f -exec basename {} \; | tr '\n' ' ')"
    return
  fi

  # Files the heartbeat does not own, aged well PAST the window. UNPREFIXED, so
  # the prefix bound must keep them.
  printf 'operator notes\n' > "$dir/operator-notes.txt"
  printf '{"tool":"other"}\n' > "$dir/other-tool.json"
  # Files the heartbeat does not own but which DO carry the prefix. The bound is
  # the prefix, so these are reaped — asserted, not wished away.
  printf '{"tool":"someone-else"}\n' > "$dir/hb-foreign-tool.json"
  printf 'not even json\n' > "$dir/hb-foreign-notes.txt"
  # A prefixed file dated into the FUTURE. isStale's window is symmetric, so
  # this is stale too.
  printf '{"tool":"clock-skewed"}\n' > "$dir/hb-future-tool.json"

  node -e '
    const fs = require("fs");
    const now = Date.now();
    const age = (f, hours) => {
      const t = new Date(now - hours * 3600 * 1000);
      fs.utimesSync(f, t, t);
    };
    age(process.argv[1], 25);
    age(process.argv[2], 1);
    age(process.argv[3], 30);
    age(process.argv[4], 30);
    age(process.argv[5], 30);
    age(process.argv[6], 30);
    age(process.argv[7], -48);
  ' "$old_slot" "$recent_slot" "$dir/operator-notes.txt" "$dir/other-tool.json" \
    "$dir/hb-foreign-tool.json" "$dir/hb-foreign-notes.txt" "$dir/hb-future-tool.json"

  AAI_HEARTBEAT_DIR="$dir" run_hb "$HB" write --ref refNew --role Validation --message "now"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-011: the reaping write exited $RC"
    return
  fi
  if [[ -f "$old_slot" ]]; then
    log_fail "TEST-011: a 25-hour-old slot must be reaped by the next write"
    return
  fi
  if [[ ! -f "$recent_slot" ]]; then
    log_fail "TEST-011: a 1-hour-old slot must be KEPT (a live producer is never swept)"
    return
  fi
  if [[ ! -f "$new_slot" ]]; then
    log_fail "TEST-011: the write that ran the GC must still have written its own slot"
    return
  fi
  if [[ ! -f "$dir/operator-notes.txt" || ! -f "$dir/other-tool.json" ]]; then
    log_fail "TEST-011: the GC must not touch a file that does not carry the hb- prefix, but a 30-hour-old UNPREFIXED foreign file was deleted from the caller-named directory (survivors: $(find "$dir" -maxdepth 1 -type f -exec basename {} \; | tr '\n' ' '))"
    return
  fi
  # The honest other half. The bound is the PREFIX, not ownership: an hb--named
  # file this script never wrote IS reaped. Asserted so the suite records the
  # mechanism that exists — if the sweep is ever narrowed to files it owns, this
  # fails and Spec-AC-07's third clause has to be re-widened in the same commit.
  if [[ -f "$dir/hb-foreign-tool.json" || -f "$dir/hb-foreign-notes.txt" ]]; then
    log_fail "TEST-011: the GC is bounded by the hb- PREFIX, not by ownership, so a stale hb--prefixed file this script never wrote must be reaped — Spec-AC-07 and the heartbeat.mjs header both state that bound (survivors: $(find "$dir" -maxdepth 1 -type f -exec basename {} \; | tr '\n' ' '))"
    return
  fi
  # isStale's window is SYMMETRIC (|now - mtime| > window), so a future-dated
  # prefixed file is stale and reclaimable — a far-future mtime must never wedge
  # the GC (runtime-file.mjs classes C+F).
  if [[ -f "$dir/hb-future-tool.json" ]]; then
    log_fail "TEST-011: the reap window is symmetric, so an hb- file dated 48 hours into the FUTURE must be reaped too — a far-future mtime must never wedge the sweep (survivors: $(find "$dir" -maxdepth 1 -type f -exec basename {} \; | tr '\n' ' '))"
    return
  fi

  # The cwd case. path.resolve("") is the current directory, so an accepted
  # empty --dir points the whole write — GC included — at wherever the caller
  # happens to stand.
  local cwdfix="$TEST_DIR/reap-cwd"
  mkdir -p "$cwdfix"
  printf 'export const x = 1;\n' > "$cwdfix/important.mjs"
  printf 'load-bearing\n' > "$cwdfix/NOTES.md"
  node -e '
    const fs = require("fs");
    const t = new Date(Date.now() - 30 * 3600 * 1000);
    for (const f of process.argv.slice(1)) fs.utimesSync(f, t, t);
  ' "$cwdfix/important.mjs" "$cwdfix/NOTES.md"

  RC=0
  # A plain subshell, NOT `$(cd ...)`: a cd inside a command substitution leaks
  # its scope back to the parent shell (check-cd-subshell-leak.mjs).
  ( cd "$cwdfix" && node "$HB" write --ref refE --role Validation --message "round 1" --dir "" ) \
    >"$TEST_DIR/hb.out" 2>"$TEST_DIR/hb.err" || RC=$?
  OUT="$(cat "$TEST_DIR/hb.out")"
  ERR="$(cat "$TEST_DIR/hb.err")"
  if [[ "$RC" -ne 2 ]]; then
    log_fail "TEST-011: an empty --dir must be REFUSED at usage grade (exit 2), got $RC — path.resolve(\"\") is the current directory, so accepting it aims the write and its GC at the caller's cwd (stderr: $(payload_preview "$ERR"))"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: --dir is empty" \
    "TEST-011: an empty --dir must carry its own literal message, like the other empty-value refusals" || return
  if [[ ! -f "$cwdfix/important.mjs" || ! -f "$cwdfix/NOTES.md" ]]; then
    log_fail "TEST-011: an empty --dir deleted stale files from the CURRENT DIRECTORY (survivors: $(find "$cwdfix" -maxdepth 1 -type f -exec basename {} \; | tr '\n' ' '))"
    return
  fi
  log_pass "TEST-011 the GC reaps a 25-hour-old slot, keeps the 1-hour-old one, is bounded by the hb- prefix (unprefixed foreign files survive; prefixed ones, future-dated included, are reaped), and an empty --dir is refused before it can sweep the cwd"
}

# --- TEST-012 / Spec-AC-08 ----------------------------------------------------
# THE anti-SPEC-0163 pin, and the reason it is a test rather than a sentence:
# an advisory signal a gate learned to read became a blocker nobody intended,
# shipped in PR #334, and cost three validation rounds. "No gate reads this" is
# only true while something fails when it stops being true.
#
# DENY BY DEFAULT, not an enumerated list. This arm shipped its first round as
# ten named gate scripts, and the forgotten member is exactly where the hole
# lives: a heartbeat reference planted in lane-gate.mjs — a deterministic PR
# fast-lane gate sitting in the same PROFILES `core:` list as the ten — left
# the suite GREEN, while the same mutation in branch-guard.mjs failed. The list
# also never named close-before-push-guard.mjs, check-test-registration.mjs,
# check-base-ref-pins.mjs, tdd-evidence-check.mjs, spec-lint.mjs,
# layer-drift.mjs or claude-hook-gate.sh. So the corpus is now EVERY executable
# under .aai/scripts/ and the exceptions are enumerated instead — a new gate is
# covered the day it is added, with nobody having to remember a list.
#
# The allowlist is exactly ONE file: heartbeat.mjs itself. generate-live-status.mjs
# was allowlisted in the first deny-by-default round and is REMOVED here: it has
# zero heartbeat references, the spec calls that seam "NOT built here, NOT a
# follow-up obligation", and a 674-line `core:` script is the file most likely to
# grow one — validation planted a gate-shaped read in it and this arm stayed
# green. Pre-authorising an unbuilt seam buys nothing that adding one allowlist
# line the day it is built would not buy, and costs the only coverage that would
# have caught it. If that panel is ever built, add it back HERE with the reason.
test_012_no_gate_reads_the_heartbeat() {
  # Allowlist on the REPO-RELATIVE PATH, never the basename: code review round 2
  # planted .aai/scripts/lib/heartbeat.mjs with a gate-shaped read and this arm
  # PASSED, silently dropping its own count 119 -> 118. That is the same shape as
  # the enumerated-list hole that drove this arm's inversion, one directory down.
  # aai-live-serve.mjs READS slots (heartbeat.mjs read --json) to display them on
  # the /aai-live page; it gates nothing and changes no verdict — a consumer, not
  # a gate (SPEC live-agent-dashboard-served-locally D2).
  local allow=" .aai/scripts/heartbeat.mjs .aai/scripts/aai-live-serve.mjs "
  local f rel hits offenders="" checked=0
  # A `while read` over find, not a glob: the corpus is recursive (lib/,
  # live-parsers/) and bash-3.2 has no globstar.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rel="${f#"$PROJECT_ROOT/"}"
    case "$allow" in *" $rel "*) continue ;; esac
    checked=$((checked + 1))
    hits="$(grep -ic 'heartbeat' "$f" || true)"
    if [[ "$hits" != "0" ]]; then
      offenders="$offenders ${f#"$PROJECT_ROOT/"}($hits)"
    fi
  done <<EOF
$(find "$PROJECT_ROOT/.aai/scripts" -type f \( -name '*.mjs' -o -name '*.sh' -o -name '*.ps1' \) | sort)
EOF
  # A deny-by-default sweep whose corpus came back empty would pass while
  # proving nothing. The floor is well under the live count (119 at the time of
  # writing) so it tracks a broken find, not the corpus growing or shrinking.
  if [[ "$checked" -lt 60 ]]; then
    log_fail "TEST-012: the corpus sweep found only $checked scripts under .aai/scripts — that is a broken enumeration, not a clean result, and a deny-by-default check that scans nothing passes vacuously"
    return
  fi
  if [[ -n "$offenders" ]]; then
    log_fail "TEST-012: a script in the gate corpus now references the heartbeat —$offenders. The heartbeat is advisory and must never gate anything (SPEC-0163 / PR #334 is what happens when it does). If this is a deliberate, non-gating seam, add it to this arm's allowlist and say why."
    return
  fi
  log_pass "TEST-012 zero heartbeat references across all $checked .aai/scripts entries outside the one-file allowlist (heartbeat.mjs)"
}

# --- TEST-013 / Spec-AC-08 ----------------------------------------------------
# The storage location is structurally uncommittable (nothing under .git/ can
# enter the index), so this scope owes NO ignore-list entry anywhere. An entry
# appearing would mean the location quietly moved out from under .git/.
test_013_no_ignore_list_entries() {
  local lists=".gitignore .aai/system/RUNTIME_IGNORE.list .aai/system/DOCS_AI_CANON.list"
  local l path hits offenders="" checked=0
  for l in $lists; do
    path="$PROJECT_ROOT/$l"
    if [[ ! -f "$path" ]]; then
      log_fail "TEST-013: expected list file is missing: $path"
      return
    fi
    checked=$((checked + 1))
    hits="$(grep -ic 'heartbeat' "$path" || true)"
    if [[ "$hits" != "0" ]]; then
      offenders="$offenders $l($hits)"
    fi
  done
  if [[ -n "$offenders" ]]; then
    log_fail "TEST-013: an ignore/canon list now names the heartbeat —$offenders. Under .git/ nothing can be committed, so an entry here means the storage location moved."
    return
  fi
  log_pass "TEST-013 zero heartbeat entries across all $checked ignore/canon lists"
}

# --- TEST-014 / Spec-AC-09 ----------------------------------------------------
# The wiring pin. This pins the INSTRUCTION, not the behaviour — no automated
# test can prove an LLM role actually emits the heartbeat at runtime (residual
# R3 in the spec). It also pins that exactly ONE role prompt is wired: the
# others staying silent is a recorded decision, not an omission.
test_014_validation_prompt_is_the_only_wiring() {
  # Matching PER LINE is the point, not an accident: an invocation wrapped
  # across two lines of prose is not greppable as one command, and this arm
  # caught exactly that during the GREEN run — the first wiring split
  # `--message` onto a continuation line.
  # No `grep | head` anywhere on this path either: `head` closes the pipe at its
  # first line, grep takes SIGPIPE, and `pipefail` turns a MATCH into a failure —
  # a shape that is green locally and red on CI.
  local invocation
  invocation="$(grep 'heartbeat\.mjs write' "$VALIDATION_PROMPT" || true)"
  if [[ -z "$invocation" ]]; then
    log_fail "TEST-014: .aai/VALIDATION.prompt.md carries no live 'heartbeat.mjs write' invocation"
    return
  fi
  assert_payload_contains "$invocation" "--ref" "TEST-014: the wired invocation must pass --ref" || return
  assert_payload_contains "$invocation" "--role" "TEST-014: the wired invocation must pass --role" || return
  assert_payload_contains "$invocation" "--message" "TEST-014: the wired invocation must pass --message" || return

  if ! grep -qi 'never changes the verdict' "$VALIDATION_PROMPT"; then
    log_fail "TEST-014: the wiring must state that the heartbeat's outcome NEVER CHANGES THE VERDICT — without it a role could read a failed write as a signal"
    return
  fi

  local p others=""
  for p in "$PROJECT_ROOT"/.aai/*.prompt.md; do
    [[ "$p" == "$VALIDATION_PROMPT" ]] && continue
    if grep -q 'heartbeat\.mjs' "$p"; then
      others="$others $(basename "$p")"
    fi
  done
  if [[ -n "$others" ]]; then
    log_fail "TEST-014: exactly ONE role prompt is wired in this scope, but heartbeat.mjs is also named in —$others (D8: the other role prompts are a separately-priced decision)"
    return
  fi
  log_pass "TEST-014 VALIDATION.prompt.md carries the live wiring plus the never-changes-the-verdict wording, and is the only wired prompt"
}

# --- TEST-018 / Spec-AC-05 (DEGRADED path) ------------------------------------
# The THIRD degrade branch. D4 names "GC failure" beside the unwritable
# directory and the absent git, but only the other two had arms: TEST-008's
# read-only parent fails at `cannot write`, never at `orphan sweep failed`, so
# that branch shipped with no coverage at all. Driven here by pointing the
# override at a REGULAR FILE, which makes the sweep's readdir fail ENOTDIR —
# a real host condition (a stale file where a directory is expected), not an
# injected fault.
test_018_sweep_failure_degrades() {
  local notadir="$TEST_DIR/sweep-fail/heartbeat"
  mkdir -p "$TEST_DIR/sweep-fail"
  printf 'not a directory\n' > "$notadir"

  AAI_HEARTBEAT_DIR="$notadir" run_hb "$HB" write \
    --ref refS --role Validation --message "round 1"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-018: a failed orphan sweep must exit 0 (best effort), got $RC — a role's outcome must never move because of a heartbeat (stderr: $(payload_preview "$ERR"))"
    return
  fi
  assert_payload_contains "$ERR" "heartbeat: degraded — orphan sweep failed" \
    "TEST-018: the failed sweep must NAME its own branch, not borrow another degrade's wording" || return
  # Nothing written, and nothing clobbered: the file that stood in for the
  # directory must still hold its own content.
  if [[ "$(cat "$notadir")" != "not a directory" ]]; then
    log_fail "TEST-018: a degraded write must write nothing, but $notadir was modified"
    return
  fi
  log_pass "TEST-018 a failed orphan sweep degrades (exit 0, its own named note, nothing written)"
}

# --- run ----------------------------------------------------------------------
check_deps
test_001_worktree_to_main_checkout
test_002_common_dir_resolves_to_one_path
test_003_cold_read
test_004_two_slots_survive_concurrency
test_005_sanitize_and_truncate
test_006_reject_empty_after_sanitization
test_007_reject_missing_and_empty_ref
test_008_unwritable_dir_degrades
test_009_git_absent_degrades
test_010_corrupt_slot_named_not_dropped
test_011_reap_stale_keep_fresh
test_012_no_gate_reads_the_heartbeat
test_013_no_ignore_list_entries
test_014_validation_prompt_is_the_only_wiring
test_018_sweep_failure_degrades

if [[ "$FAILED" == 0 ]]; then
  echo "PASS: all $TEST_NAME tests (TEST-001..014, TEST-018)"
  exit 0
else
  echo "FAIL: $TEST_NAME suite had failures" >&2
  exit 1
fi
