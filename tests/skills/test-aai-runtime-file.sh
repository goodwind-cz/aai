#!/usr/bin/env bash
#
# Test: aai-runtime-file — the shared runtime-SIDECAR lifecycle primitives
# (CHANGE runtime-state-consolidation, .aai/scripts/lib/runtime-file.mjs).
#
# NEGATIVE-CONTROL suite: the point of the lib is that the six recurring sidecar
# bug classes (intake A-F) are caught ONCE here instead of re-shipping per sidecar
# per target project. So every case drives the FAILURE input the bespoke code got
# wrong and asserts the primitive does the safe thing:
#   loadOrDegrade  — absent vs corrupt vs wrong-shape vs ok; a damaged ledger is
#                    NEVER read as empty (class B).
#   atomicWrite    — a stray/partial temp never corrupts the committed target;
#                    two concurrent writers each land a WHOLE file (class E).
#   claimExclusive — N true-parallel contenders -> exactly ONE winner; a
#                    hard-link-hostile FS still stays exclusive; a genuine error
#                    is LOUD, never masqueraded as held (class A).
#   isStale        — future-dated / NaN -> stale (never wedge); injected clock is
#                    deterministic (classes C + F).
#   reapAsides     — an aged orphan is swept, a fresh one kept, a missing dir is a
#                    no-op (class D).
#   + determinism x2 (isStale + loadOrDegrade) and a zero-dep import check.
#
# ZERO real network. bash-3.2 compatible (no associative arrays, no mapfile,
# no ${var^^}). Exit codes: 0 pass, 1 fail, 42 skip.

set -uo pipefail

TEST_NAME="aai-runtime-file"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="${AAI_RUNTIME_FILE_LIB:-$PROJECT_ROOT/.aai/scripts/lib/runtime-file.mjs}"

TEST_DIR=""
DRV=""
FAILED=0

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"; return 0
  fi
  [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# A tiny ESM driver: import the lib and dispatch on argv so bash can exercise
# each primitive and read a single JSON/scalar line off stdout.
write_driver() {
  DRV="$TEST_DIR/drv.mjs"
  cat > "$DRV" <<'MJS'
import { pathToFileURL } from 'node:url';
const lib = await import(pathToFileURL(process.env.RF_LIB).href);
const [op, ...a] = process.argv.slice(2);
if (op === 'load') {
  process.stdout.write(JSON.stringify(lib.loadOrDegrade(a[0])));
} else if (op === 'load-shape') {
  const r = lib.loadOrDegrade(a[0], { isShape: (d) => d && Array.isArray(d.entries), empty: { entries: [] } });
  process.stdout.write(JSON.stringify(r));
} else if (op === 'write') {
  lib.atomicWrite(a[0], a[1]);
} else if (op === 'leftover-temp') {
  // Simulate a crashed writer: stage a partial temp beside the target, NEVER
  // rename it. Proves a stray temp cannot corrupt the committed target.
  const fs = await import('node:fs');
  fs.writeFileSync(`${a[0]}.tmp.99999.0`, 'PARTIAL-TORN-GARBAGE');
} else if (op === 'claim') {
  process.stdout.write(lib.claimExclusive(a[0], a[1]).status);
} else if (op === 'claim-json') {
  process.stdout.write(JSON.stringify(lib.claimExclusive(a[0], a[1])));
} else if (op === 'stale') {
  const ts = a[0] === 'NaN' ? NaN : Number(a[0]);
  process.stdout.write(String(lib.isStale(ts, Number(a[1]), Number(a[2]))));
} else if (op === 'reap') {
  process.stdout.write(JSON.stringify(lib.reapAsides(a[0], a[1], Number(a[2]), Number(a[3]))));
} else {
  console.error(`unknown op: ${op}`); process.exit(3);
}
MJS
}

OUT=""; EC=0
drv() {  # drv <op> <args...>  -> captures stdout in OUT, exit in EC
  OUT="$(RF_LIB="$LIB" node "$DRV" "$@" 2>"$TEST_DIR/drv.err")"; EC=$?
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  [[ -f "$LIB" ]] || { log_fail "runtime-file.mjs not found: $LIB"; exit 1; }
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-runtime-file-test.XXXXXX")"
  write_driver
}

# jval <json> <js-expr over `o`> — echo the evaluated value.
jval() {
  node -e '
    const o=JSON.parse(process.argv[1]);
    const fn=new Function("o","return ("+process.argv[2]+");");
    const v=fn(o); process.stdout.write(v===undefined?"":String(v));
  ' "$1" "$2"
}

# ---------------- TEST-001 (AC-001, class B): absent -> empty, status absent ---
test_001_absent() {
  log_info "TEST-001: loadOrDegrade on an absent file is a NORMAL empty (status=absent), never corrupt..."
  drv load "$TEST_DIR/does-not-exist.json"
  [[ "$EC" == 0 ]] || { log_fail "TEST-001: driver exited $EC ($(cat "$TEST_DIR/drv.err"))"; return; }
  local st; st="$(jval "$OUT" 'o.status')"
  if [[ "$st" == "absent" ]]; then
    log_pass "TEST-001: absent file -> status=absent (normal empty)"
  else
    log_fail "TEST-001: expected status=absent, got '$st' ($OUT)"
  fi
}

# ---------------- TEST-002 (AC-001, class B): corrupt -> NEVER empty ----------
test_002_corrupt_truncated() {
  log_info "TEST-002: a truncated/unparseable ledger degrades to status=corrupt, NEVER read as empty..."
  local f="$TEST_DIR/corrupt.json"
  printf '{ this is not valid json ]]]\n' > "$f"
  drv load "$f"
  [[ "$EC" == 0 ]] || { log_fail "TEST-002: driver exited $EC"; return; }
  local st; st="$(jval "$OUT" 'o.status')"
  if [[ "$st" == "corrupt" ]]; then
    log_pass "TEST-002: truncated JSON -> status=corrupt (damaged, not empty)"
  else
    log_fail "TEST-002: expected status=corrupt, got '$st' ($OUT)"
  fi
}

# ---------------- TEST-003 (AC-001, class B): wrong-shape -> corrupt ----------
test_003_wrong_shape() {
  log_info "TEST-003: valid JSON of the WRONG shape (isShape reject) -> status=corrupt..."
  local f="$TEST_DIR/wrongshape.json"
  printf '{"not_entries": 1}\n' > "$f"
  drv load-shape "$f"
  [[ "$EC" == 0 ]] || { log_fail "TEST-003: driver exited $EC"; return; }
  local st; st="$(jval "$OUT" 'o.status')"
  if [[ "$st" == "corrupt" ]]; then
    log_pass "TEST-003: wrong-shape-but-parseable JSON -> status=corrupt"
  else
    log_fail "TEST-003: expected status=corrupt, got '$st' ($OUT)"
  fi
}

# ---------------- TEST-004 (AC-001): valid -> ok + parsed data ----------------
test_004_valid_ok() {
  log_info "TEST-004: a valid, shape-correct ledger -> status=ok with parsed data..."
  local f="$TEST_DIR/valid.json"
  printf '{"entries":[{"id":7}]}\n' > "$f"
  drv load-shape "$f"
  [[ "$EC" == 0 ]] || { log_fail "TEST-004: driver exited $EC"; return; }
  local st id; st="$(jval "$OUT" 'o.status')"; id="$(jval "$OUT" 'o.data.entries[0].id')"
  if [[ "$st" == "ok" && "$id" == "7" ]]; then
    log_pass "TEST-004: valid ledger -> status=ok, data parsed"
  else
    log_fail "TEST-004: expected ok/id=7, got status=$st id=$id ($OUT)"
  fi
}

# ---------------- TEST-005 (AC-002, class E): whole-file write, no temp left ---
test_005_atomic_write_whole() {
  log_info "TEST-005: atomicWrite lands the whole file and leaves no .tmp behind..."
  local f="$TEST_DIR/aw/state.json"
  drv write "$f" 'HELLO-WHOLE'
  [[ "$EC" == 0 ]] || { log_fail "TEST-005: write exited $EC ($(cat "$TEST_DIR/drv.err"))"; return; }
  local got; got="$(cat "$f" 2>/dev/null)"
  local temps; temps="$(ls "$TEST_DIR/aw/" 2>/dev/null | grep -c '\.tmp\.' || true)"
  if [[ "$got" == "HELLO-WHOLE" && "$temps" == 0 ]]; then
    log_pass "TEST-005: atomicWrite committed the whole file (mkdir -p, no temp leftover)"
  else
    log_fail "TEST-005: got='$got' temps=$temps (want HELLO-WHOLE / 0)"
  fi
}

# ---------------- TEST-006 (AC-002, class E): a stray temp never torns target --
test_006_torn_temp_isolated() {
  log_info "TEST-006: a crashed writer's leftover temp NEVER corrupts the committed target..."
  local f="$TEST_DIR/torn.json"
  drv write "$f" 'PRIOR-COMMITTED'
  [[ "$EC" == 0 ]] || { log_fail "TEST-006: seed write exited $EC"; return; }
  drv leftover-temp "$f"          # simulate a crash mid-write: stray partial temp
  [[ "$EC" == 0 ]] || { log_fail "TEST-006: leftover-temp exited $EC"; return; }
  local got; got="$(cat "$f")"
  if [[ "$got" == "PRIOR-COMMITTED" ]]; then
    log_pass "TEST-006: target holds its PRIOR content; the stray temp is inert (rename is the sole commit point)"
  else
    log_fail "TEST-006: target torn by a stray temp, got '$got'"
  fi
}

# ---------------- TEST-007 (AC-002): two concurrent writers each land whole ----
test_007_concurrent_writers() {
  log_info "TEST-007: two TRUE-parallel atomicWrite writers -> target is exactly ONE whole file, never a mix..."
  local f="$TEST_DIR/conc.json"
  local A; A="$(printf 'A%.0s' $(seq 1 2000))"   # 2000-byte distinct payloads
  local B; B="$(printf 'B%.0s' $(seq 1 2000))"
  RF_LIB="$LIB" node "$DRV" write "$f" "$A" &
  local p1=$!
  RF_LIB="$LIB" node "$DRV" write "$f" "$B" &
  local p2=$!
  wait "$p1"; wait "$p2"
  local got; got="$(cat "$f")"
  if [[ "$got" == "$A" || "$got" == "$B" ]]; then
    log_pass "TEST-007: concurrent writers each landed a WHOLE file (winner is all-A or all-B, no interleave)"
  else
    log_fail "TEST-007: target is a torn mix (len=${#got})"
  fi
}

# ---------------- TEST-008 (AC-003, class A): N-parallel -> exactly one winner -
test_008_race_single_winner() {
  log_info "TEST-008: 8 TRUE-parallel claimExclusive contenders -> EXACTLY ONE 'claimed', the rest 'held'..."
  local lock="$TEST_DIR/race.lock" res="$TEST_DIR/race.results"
  : > "$res"
  local i
  for i in 1 2 3 4 5 6 7 8; do
    ( s="$(RF_LIB="$LIB" node "$DRV" claim "$lock" "body-$i")"; echo "$s" >> "$res" ) &
  done
  wait
  local claimed held; claimed="$(grep -c '^claimed$' "$res" || true)"; held="$(grep -c '^held$' "$res" || true)"
  if [[ "$claimed" == 1 && "$held" == 7 ]]; then
    log_pass "TEST-008: race resolved to exactly one winner (claimed=1, held=7)"
  else
    log_fail "TEST-008: expected 1 claimed / 7 held, got claimed=$claimed held=$held ($(tr '\n' ' ' < "$res"))"
  fi
}

# ---------------- TEST-009 (AC-003): hard-link-hostile FS still exclusive ------
test_009_hardlink_fallback() {
  log_info "TEST-009: with hard links disabled, claimExclusive falls back to O_EXCL 'wx' and stays exclusive..."
  local lock="$TEST_DIR/fallback.lock"
  local s1 s2
  s1="$(AAI_RUNTIME_FILE_NO_HARDLINK=1 RF_LIB="$LIB" node "$DRV" claim "$lock" one)"
  s2="$(AAI_RUNTIME_FILE_NO_HARDLINK=1 RF_LIB="$LIB" node "$DRV" claim "$lock" two)"
  if [[ "$s1" == "claimed" && "$s2" == "held" ]]; then
    log_pass "TEST-009: wx fallback stays exclusive (first=claimed, second=held)"
  else
    log_fail "TEST-009: fallback not exclusive (s1=$s1 s2=$s2)"
  fi
}

# ---------------- TEST-010 (AC-003): a genuine error is LOUD, never held -------
test_010_genuine_error_loud() {
  log_info "TEST-010: a genuine claim failure returns status=error (never silently 'held')..."
  # Parent of the target is a regular FILE -> staging the temp fails (ENOTDIR).
  local blocker="$TEST_DIR/iamafile"
  printf 'x' > "$blocker"
  drv claim-json "$blocker/child.lock" body
  [[ "$EC" == 0 ]] || { log_fail "TEST-010: driver crashed instead of returning a status ($EC)"; return; }
  local st; st="$(jval "$OUT" 'o.status')"
  if [[ "$st" == "error" ]]; then
    log_pass "TEST-010: genuine failure -> status=error (loud, not masqueraded as held)"
  else
    log_fail "TEST-010: expected status=error, got '$st' ($OUT)"
  fi
}

# ---------------- TEST-011 (AC-004, class C+F): future/NaN stale; fresh not ----
test_011_stale_semantics() {
  log_info "TEST-011: isStale — far-future -> stale, NaN -> stale, fresh -> not stale (never wedges)..."
  local now=1000000 window=1000
  local future=$(( now + 10 * window ))   # far future, beyond the window
  local fresh=$(( now - 100 ))            # within the window
  local r_future r_nan r_fresh
  drv stale "$future" "$now" "$window"; r_future="$OUT"
  drv stale NaN "$now" "$window";       r_nan="$OUT"
  drv stale "$fresh" "$now" "$window";  r_fresh="$OUT"
  if [[ "$r_future" == "true" && "$r_nan" == "true" && "$r_fresh" == "false" ]]; then
    log_pass "TEST-011: future=stale, NaN=stale, fresh=not-stale (symmetric window, no wedge)"
  else
    log_fail "TEST-011: future=$r_future nan=$r_nan fresh=$r_fresh (want true/true/false)"
  fi
}

# ---------------- TEST-012 (AC-004, determinism #1): injected clock -----------
test_012_stale_determinism() {
  log_info "TEST-012 [DETERMINISM]: isStale with an injected clock gives the SAME verdict every run..."
  local ts=500000 now=500600 window=1000    # 600ms old, within window -> not stale
  local a b
  drv stale "$ts" "$now" "$window"; a="$OUT"
  drv stale "$ts" "$now" "$window"; b="$OUT"
  if [[ "$a" == "false" && "$b" == "false" ]]; then
    log_pass "TEST-012: injected-clock verdict is deterministic (no wall-clock dependence)"
  else
    log_fail "TEST-012: non-deterministic verdict (a=$a b=$b, want false/false)"
  fi
}

# ---------------- TEST-013 (AC-005, class D): reap aged, keep fresh -----------
test_013_reap_aged_keep_fresh() {
  log_info "TEST-013: reapAsides sweeps an AGED orphan, KEEPS a fresh one, and is prefix-scoped..."
  local dir="$TEST_DIR/asides"; mkdir -p "$dir"
  local aged="$dir/x.surfacing.old" fresh="$dir/x.surfacing.new" other="$dir/keepme.txt"
  printf 'aged\n'  > "$aged"
  printf 'fresh\n' > "$fresh"
  printf 'other\n' > "$other"
  # Age the orphan's mtime well beyond the window (portable touch -t: 2001-01-01).
  touch -t 200101010000 "$aged"
  local now; now="$(node -e 'process.stdout.write(String(Date.now()))')"
  local window=60000     # 60s window; the fresh file (just created) is within it
  drv reap "$dir" "x.surfacing." "$now" "$window"
  [[ "$EC" == 0 ]] || { log_fail "TEST-013: reap exited $EC"; return; }
  local reaped kept; reaped="$(jval "$OUT" 'o.reaped')"; kept="$(jval "$OUT" 'o.kept')"
  if [[ ! -e "$aged" && -e "$fresh" && -e "$other" && "$reaped" == 1 && "$kept" == 1 ]]; then
    log_pass "TEST-013: aged orphan swept, fresh kept, non-prefix file untouched (reaped=1 kept=1)"
  else
    log_fail "TEST-013: aged-exists=$( [[ -e "$aged" ]] && echo y || echo n ) fresh-exists=$( [[ -e "$fresh" ]] && echo y || echo n ) other-exists=$( [[ -e "$other" ]] && echo y || echo n ) reaped=$reaped kept=$kept"
  fi
}

# ---------------- TEST-014 (AC-005): missing directory is a no-op -------------
test_014_reap_missing_dir() {
  log_info "TEST-014: reapAsides on a missing directory is a no-op (never throws)..."
  drv reap "$TEST_DIR/no-such-dir" "pfx." 1000 1000
  [[ "$EC" == 0 ]] || { log_fail "TEST-014: missing-dir reap threw / exited $EC ($(cat "$TEST_DIR/drv.err"))"; return; }
  local reaped kept; reaped="$(jval "$OUT" 'o.reaped')"; kept="$(jval "$OUT" 'o.kept')"
  if [[ "$reaped" == 0 && "$kept" == 0 ]]; then
    log_pass "TEST-014: missing directory -> {reaped:0,kept:0} no-op, no throw"
  else
    log_fail "TEST-014: expected 0/0 no-op, got reaped=$reaped kept=$kept"
  fi
}

# ---------------- TEST-015 (determinism #2): loadOrDegrade is deterministic ---
test_015_load_determinism() {
  log_info "TEST-015 [DETERMINISM]: loadOrDegrade returns byte-identical output for the same input twice..."
  local f="$TEST_DIR/det.json"
  printf '{"entries":[{"id":1}]}\n' > "$f"
  local a b
  drv load-shape "$f"; a="$OUT"
  drv load-shape "$f"; b="$OUT"
  if [[ "$a" == "$b" && -n "$a" ]]; then
    log_pass "TEST-015: identical input -> identical loadOrDegrade output (deterministic)"
  else
    log_fail "TEST-015: non-deterministic output (a=$a b=$b)"
  fi
}

# ---------------- TEST-016 (AC-012): zero runtime dependencies ----------------
test_016_zero_dep() {
  log_info "TEST-016: the lib imports NOTHING outside node:* (zero runtime deps)..."
  local bad; bad="$(grep -nE "^import|^const .*=.*require\(" "$LIB" | grep -vE "from 'node:|require\('node:" || true)"
  if [[ -z "$bad" ]]; then
    log_pass "TEST-016: zero-dep — only node:* imports"
  else
    log_fail "TEST-016: non-node import found: $bad"
  fi
}

# --- run ----------------------------------------------------------------------
check_deps
test_001_absent
test_002_corrupt_truncated
test_003_wrong_shape
test_004_valid_ok
test_005_atomic_write_whole
test_006_torn_temp_isolated
test_007_concurrent_writers
test_008_race_single_winner
test_009_hardlink_fallback
test_010_genuine_error_loud
test_011_stale_semantics
test_012_stale_determinism
test_013_reap_aged_keep_fresh
test_014_reap_missing_dir
test_015_load_determinism
test_016_zero_dep

if [[ "$FAILED" == 0 ]]; then
  echo "=== ALL TESTS PASSED: $TEST_NAME (TEST-001..016) ==="
  exit 0
else
  echo "=== FAIL: $TEST_NAME suite had failures ===" >&2
  exit 1
fi
