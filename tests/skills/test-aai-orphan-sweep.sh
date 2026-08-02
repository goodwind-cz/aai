#!/usr/bin/env bash
# test-aai-orphan-sweep.sh — orphan-sweep.mjs (CHANGE orphan-sweep-session-hook)
# Deterministic: selection logic via --ps-file fixtures; the real-kill path via
# a purpose-made double-forked orphan with a unique marker and thresholds
# lowered to zero (no dependence on CPU load or wall-clock age).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SWEEP="$REPO_ROOT/.aai/scripts/orphan-sweep.mjs"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-orphan-sweep.XXXXXX")"
FAILURES=0

log_info() { printf 'INFO: %s\n' "$1"; }
log_pass() { printf 'PASS: %s\n' "$1"; }
log_fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

fixture() {
  cat > "$TEST_DIR/ps.txt" <<'EOF'
  PID  PGID  PPID  %CPU     ELAPSED ARGS
    1     1     0   0.3 19-23:32:21 /sbin/launchd
 2059  2047     1  38.0 03-20:46:41 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh busyloop
 2060  2047     1  43.4 03-20:46:41 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh busyloop
 9001  9001  4242  41.0 03-00:01:02 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh live-parented
 9100  9100     1   0.1 05-00:00:01 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh idle-waiter
 9200  9200     1  44.0       05:00 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh too-young
 9300  9300     1  44.0 03-00:00:01 /bin/zsh -c unrelated-hog
 7001  7000     1  40.0 02-00:00:01 /bin/zsh -c source /U/x/.claude/shell-snapshots/snapshot-zsh-123-a.sh mine
EOF
}

# TEST-001 — selection: only the orphaned+old+hot matching group qualifies;
# live-parented, idle, too-young, non-matching are all excluded.
test_001_selection() {
  log_info "Test: only orphaned(PPID=1) + old + hot + pattern-matching groups are selected (TEST-001)..."
  fixture
  local out; out="$(node "$SWEEP" --dry-run --json --ps-file "$TEST_DIR/ps.txt" --self-pgid 777)"
  echo "$out" | node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const pg = j.plan.map(p => p.pgid).sort();
    if (JSON.stringify(pg) !== JSON.stringify([2047, 7000])) { console.error("plan pgids " + JSON.stringify(pg)); process.exit(1); }
    if (j.plan.find(p => p.pgid === 2047).pids.length !== 2) { console.error("2047 must list 2 pids"); process.exit(1); }
    if (j.killed_groups !== 0) { console.error("dry-run must not kill"); process.exit(1); }
  ' || log_fail "TEST-001: selection must be exactly pgids 2047+7000, dry-run kills nothing"
  log_pass "Selection: orphan+age+cpu+pattern all required; dry-run inert (TEST-001)"
}

# TEST-002 — self-protection: the sweep's own PGID is never selected.
test_002_self_pgid_excluded() {
  log_info "Test: the sweep's own process group is never a victim (TEST-002)..."
  fixture
  local out; out="$(node "$SWEEP" --dry-run --json --ps-file "$TEST_DIR/ps.txt" --self-pgid 7000)"
  echo "$out" | node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (j.plan.some(p => p.pgid === 7000)) { console.error("own pgid selected!"); process.exit(1); }
    if (!j.plan.some(p => p.pgid === 2047)) { console.error("2047 lost"); process.exit(1); }
  ' || log_fail "TEST-002: --self-pgid 7000 must drop group 7000 and keep 2047"
  log_pass "Own PGID excluded from the kill plan (TEST-002)"
}

# TEST-003 — shared-group safety: a group containing a live-parented process
# WITHOUT the pattern is dropped entirely (never kill a mixed group).
test_003_mixed_group_dropped() {
  log_info "Test: a victim group sharing its PGID with live foreign work is dropped whole (TEST-003)..."
  fixture
  cat >> "$TEST_DIR/ps.txt" <<'EOF'
 2099  2047  8888  10.0 00-00:10:00 /usr/bin/some-live-tool sharing-the-pgid
EOF
  local out; out="$(node "$SWEEP" --dry-run --json --ps-file "$TEST_DIR/ps.txt" --self-pgid 777)"
  echo "$out" | node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    if (j.plan.some(p => p.pgid === 2047)) { console.error("mixed group 2047 must be dropped"); process.exit(1); }
    if (!j.plan.some(p => p.pgid === 7000)) { console.error("clean group 7000 must remain"); process.exit(1); }
  ' || log_fail "TEST-003: group 2047 (mixed) must be dropped, 7000 kept"
  log_pass "Mixed PGID (live foreign member) is never killed (TEST-003)"
}

# TEST-004 — etime parsing: mm:ss / hh:mm:ss / dd-hh:mm:ss / garbage->null.
test_004_etime_parse() {
  log_info "Test: etime parser handles all ps forms; garbage is fail-safe null (TEST-004)..."
  node --input-type=module -e "
    import { parseEtimeSeconds } from '$SWEEP';
    const eq = (a, b, l) => { if (a !== b) { console.error(l + ': ' + a + ' != ' + b); process.exit(1); } };
    eq(parseEtimeSeconds('05:00'), 300, 'mm:ss');
    eq(parseEtimeSeconds('01:00:00'), 3600, 'hh:mm:ss');
    eq(parseEtimeSeconds('03-20:46:41'), 3*86400 + 20*3600 + 46*60 + 41, 'dd-hh:mm:ss');
    eq(parseEtimeSeconds('garbage'), null, 'garbage');
    eq(parseEtimeSeconds(''), null, 'empty');
  " || log_fail "TEST-004: etime parsing broken"
  log_pass "etime parsing exact across all forms; garbage -> null (TEST-004)"
}

# TEST-005 — usage errors: unknown flag / empty pattern / bad numbers exit 2.
test_005_usage_errors() {
  log_info "Test: usage errors exit 2 and never touch ps (TEST-005)..."
  local ec
  node "$SWEEP" --bogus >/dev/null 2>&1; ec=$?
  [[ "$ec" == 2 ]] || log_fail "TEST-005: unknown flag must exit 2 (got $ec)"
  node "$SWEEP" --pattern "" >/dev/null 2>&1; ec=$?
  [[ "$ec" == 2 ]] || log_fail "TEST-005: empty pattern must be refused with exit 2 (got $ec)"
  node "$SWEEP" --min-age-s -5 >/dev/null 2>&1; ec=$?
  [[ "$ec" == 2 ]] || log_fail "TEST-005: negative min-age must exit 2 (got $ec)"
  log_pass "Usage errors exit 2 (TEST-005)"
}

# TEST-006 — REAL KILL: double-forked orphan with a unique marker; thresholds
# zeroed so the test is deterministic. The orphan self-terminates in 60s as a
# backstop even if the sweep fails (this suite practices what the incident
# taught: load processes carry their own death).
test_006_real_kill() {
  log_info "Test: a real double-forked orphan is killed by process group (TEST-006)..."
  local marker="AAI_ORPHAN_SWEEP_TEST_$$_$RANDOM"
  # Stage via node spawn({detached:true}) -> setsid -> the orphan gets its OWN
  # process group (pgid == pid). CRITICAL: a bash `( cmd & )` background job in
  # a non-interactive shell SHARES the suite's PGID — sweeping that group kills
  # the test run itself (observed live on first write of this test; the exact
  # foot-gun the sweep's self-pgid guard exists for). The loop self-terminates
  # in 60s as a backstop (the incident's lesson: load procs carry their own death).
  local pidfile="$TEST_DIR/orphan.pid"
  node -e '
    const { spawn } = require("node:child_process");
    const c = spawn("bash", ["-c", "t=$((SECONDS+60)); while ((SECONDS<t)); do sleep 1; done"],
      { detached: true, stdio: "ignore" });
    require("node:fs").writeFileSync(process.argv[1], String(c.pid));
    c.unref();
  ' "$pidfile"
  sleep 1
  local opid; opid="$(cat "$pidfile" 2>/dev/null)"
  if [[ -z "$opid" ]] || ! kill -0 "$opid" 2>/dev/null; then
    log_info "TEST-006: could not stage an orphan on this platform — skipping (real-kill covered on darwin/linux dev machines)"
    return 0
  fi
  # feed the sweep a fixture describing the REAL orphan (pattern = marker is
  # embedded via the fixture args, thresholds zeroed) — the kill is real.
  local pgid; pgid="$(ps -o pgid= -p "$opid" | tr -d ' ')"
  local ppid; ppid="$(ps -o ppid= -p "$opid" | tr -d ' ')"
  local mypgid; mypgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  if [[ "$ppid" != "1" || -z "$pgid" || "$pgid" == "$mypgid" ]]; then
    log_info "TEST-006: orphan not isolated on this platform (ppid=$ppid pgid=$pgid my=$mypgid) — skipping real-kill leg"
    kill -9 "$opid" 2>/dev/null
    return 0
  fi
  printf '  PID  PGID  PPID  %%CPU     ELAPSED ARGS\n%5s %5s     1  50.0 03-00:00:01 /bin/bash %s\n' \
    "$opid" "$pgid" "$marker" > "$TEST_DIR/real.txt"
  node "$SWEEP" --ps-file "$TEST_DIR/real.txt" --pattern "$marker" \
    --min-age-s 0 --min-cpu 0 --self-pgid 999999 > "$TEST_DIR/kill.out" 2>&1
  sleep 1
  if kill -0 "$opid" 2>/dev/null; then
    log_fail "TEST-006: orphan $opid survived the sweep"
    kill -9 "$opid" 2>/dev/null
  else
    grep -q "killed 1 orphaned process group" "$TEST_DIR/kill.out" \
      || log_fail "TEST-006: kill happened but the one-line report is missing/wrong: $(cat "$TEST_DIR/kill.out")"
    log_pass "Real orphan killed by PGID + one-line report emitted (TEST-006)"
  fi
}

# TEST-007 — hook contract: silent + exit 0 when nothing matches.
test_007_silent_noop() {
  log_info "Test: nothing to reap -> zero output, exit 0 (hook never-noise contract) (TEST-007)..."
  printf '  PID  PGID  PPID  %%CPU     ELAPSED ARGS\n    1     1     0   0.3 19-23:32:21 /sbin/launchd\n' > "$TEST_DIR/empty.txt"
  local out ec
  out="$(node "$SWEEP" --ps-file "$TEST_DIR/empty.txt" --self-pgid 777)"; ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-007: must exit 0 (got $ec)"
  [[ -z "$out" ]] || log_fail "TEST-007: must be silent on no-op (got: $out)"
  log_pass "Silent no-op, exit 0 (TEST-007)"
}

# TEST-008 — hook wiring pin: session-start.sh carries the bounded sweep block.
test_008_hook_wiring_pinned() {
  log_info "Test: hooks/session-start.sh wires the sweep with watchdog + swallowed errors (TEST-008)..."
  local hook="$REPO_ROOT/hooks/session-start.sh"
  grep -q 'orphan-sweep.mjs' "$hook" \
    || log_fail "TEST-008: hook must invoke orphan-sweep.mjs"
  grep -q 'AAI_ORPHAN_SWEEP_TIMEOUT_S' "$hook" \
    || log_fail "TEST-008: hook must bound the sweep with a watchdog timeout"
  log_pass "Hook wiring pinned (bounded, best-effort) (TEST-008)"
}

main() {
  log_info "orphan-sweep suite starting (dir: $TEST_DIR)"
  test_001_selection
  test_002_self_pgid_excluded
  test_003_mixed_group_dropped
  test_004_etime_parse
  test_005_usage_errors
  test_006_real_kill
  test_007_silent_noop
  test_008_hook_wiring_pinned
  if [[ "$FAILURES" -gt 0 ]]; then
    printf 'RESULT: %d failure(s)\n' "$FAILURES"; exit 1
  fi
  printf 'RESULT: all orphan-sweep tests passed\n'
}

main "$@"
