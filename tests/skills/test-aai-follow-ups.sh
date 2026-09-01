#!/usr/bin/env bash
#
# Test: aai-follow-ups
# (docs/specs/SPEC-0129-spec-followup-registry.md, TEST-001..005, 008, 009)
#
# Verifies .aai/scripts/follow-ups.mjs — the typed follow-up registry folded
# out of the EXISTING docs/ai/decisions.jsonl ledger (no new store):
#   TEST-001 schema + id discipline (write-refuse, read-tolerate)
#   TEST-002 query path (determinism, filters, --json, D6 exit contract)
#   TEST-003 degrade-with-NOTE + zero-network source pins
#   TEST-004 backfill accounting (K clauses -> K appended lines)
#   TEST-005 history integrity (base ledger is a byte-exact prefix)
#   TEST-008 close path (append + prove-by-re-read)
#   TEST-009 consumer seam (routine-emit fail-closed; doctor CAT-07)
#
# ALL write fixtures are scratch temp-dir ledgers — the real docs/ai tree is
# only ever READ (TEST-004/005/009 read it; none of them write it).
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Pipeline discipline: this suite runs `set -euo pipefail`, so a `cmd | grep`
# whose reader exits early kills the writer with SIGPIPE and fails the suite
# on CI only (docs/knowledge/LEARNED.md test-harness shell-options trap).
# Every text match below therefore uses a here-string, never a pipe.
#
# Usage:
#   bash tests/skills/test-aai-follow-ups.sh                 # run all
#   bash tests/skills/test-aai-follow-ups.sh test_002_query_path
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-follow-ups"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FU="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
ROUTINE_EMIT="$PROJECT_ROOT/.aai/scripts/routine-emit.mjs"
DOCTOR="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"
LIVE_LEDGER="$PROJECT_ROOT/docs/ai/decisions.jsonl"
# Shared close-work-item.mjs content-hash allowlist (role-verification-guards
# unification, see the lib header): the D5 check below and
# test-aai-doc-numbering.sh TEST-029 both consult this SAME list so their
# two independently frozen invariants on that one file can never silently
# disagree again.
source "$SCRIPT_DIR/lib/close-work-item-pin.sh"
# Base-ref resolution prefers origin/main (CHANGE-0135 TEST-024 lesson,
# re-learned here on PR #257): a GitHub Actions PR checkout is detached-HEAD
# with only origin/main fetched, so a bare `main` never resolves and every
# git-based arm below degrades. Explicit override still wins.
if [[ -n "${AAI_FOLLOWUPS_BASE_REF:-}" ]]; then
  BASE_REF="$AAI_FOLLOWUPS_BASE_REF"
elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  BASE_REF="origin/main"
else
  BASE_REF="main"
fi

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$FU" ]] || log_fail "follow-ups.mjs not found: $FU"
  log_pass "Dependencies checked"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-follow-ups-test.XXXXXX")"; }

# --- helpers -----------------------------------------------------------------

OUT=""    # stdout of the last run_fu
ERR=""    # stderr of the last run_fu
EC=0      # exit code of the last run_fu

run_fu() {  # run_fu <args...>
  local o e
  o="$TEST_DIR/.stdout"; e="$TEST_DIR/.stderr"
  EC=0
  node "$FU" "$@" > "$o" 2> "$e" || EC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}

fsize() {  # fsize <path> -> byte length (portable: node, not stat)
  node -e 'process.stdout.write(String(require("fs").statSync(process.argv[1]).size))' "$1"
}

nlines() {  # nlines <path> -> number of non-empty lines
  node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");process.stdout.write(String(t.split("\n").filter(l=>l.trim()!=="").length))' "$1"
}

# mk_ledger <name> -> echoes a fresh fixture ledger path carrying the SAME
# `#` comment header shape the real docs/ai/decisions.jsonl opens with (the
# comment-line edge every reader in this scope must skip).
mk_ledger() {
  local f="$TEST_DIR/$1.jsonl"
  rm -f "$f"
  {
    echo "# Decision Log — append-only, one JSON object per line (JSONL format)"
    echo "#"
    echo "# Rules:"
    echo "#   - Append only. Never edit existing lines."
  } > "$f"
  printf '%s' "$f"
}

# --- pipe-flush helpers (cli-output-survives-a-pipe, TEST-018..022) ----------
#
# These arms MUST measure through a real pipe. A redirect to a file is exactly
# the configuration that already worked before the fix, so a file-based claim
# about a pipe is not evidence. Everything below therefore runs the CLI as the
# WRITE end of a genuine pipeline, and every pipeline runs under a wall-clock
# bound so a process kept alive by a stray handle fails an arm instead of
# hanging the suite.

BOUNDED_EC=0

# kill_tree <pid> — depth-first kill, so a bounded pipeline cannot leave the
# node processes behind when the bound is breached. Never a pattern-based
# pkill (docs/knowledge/LEARNED.md stress-test busy-loop leak).
kill_tree() {
  local p="$1" c
  if command -v pgrep >/dev/null 2>&1; then
    for c in $(pgrep -P "$p" 2>/dev/null || true); do kill_tree "$c"; done
  fi
  kill -9 "$p" 2>/dev/null || true
}

# run_bounded <seconds> <command string> -> BOUNDED_EC (124 when the bound is
# breached). The command string is run by a fresh `bash -c`, so this suite's
# own `set -euo pipefail` cannot turn an expected non-zero exit into a suite
# abort, and the caller reads the code rather than the shell's reaction to it.
run_bounded() {
  local secs="$1" cmd="$2" pid i=0
  BOUNDED_EC=0
  bash -c "$cmd" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $i -ge $((secs * 10)) ]]; then
      kill_tree "$pid"
      wait "$pid" 2>/dev/null || true
      BOUNDED_EC=124
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  set +e
  wait "$pid"
  BOUNDED_EC=$?
  set -e
  return 0
}

# run_fu_bounded <seconds> <fu args...> -> BOUNDED_EC, OUT, ERR
run_fu_bounded() {
  local secs="$1"; shift
  local o="$TEST_DIR/.bout" e="$TEST_DIR/.berr" cmd q
  cmd="node $(printf '%q' "$FU")"
  for q in "$@"; do cmd="$cmd $(printf '%q' "$q")"; done
  cmd="$cmd > $(printf '%q' "$o") 2> $(printf '%q' "$e")"
  run_bounded "$secs" "$cmd"
  OUT="$(cat "$o" 2>/dev/null || true)"
  ERR="$(cat "$e" 2>/dev/null || true)"
}

PIPE_READER_OUT=""
PIPE_WRITER_ERR=""
PIPE_WRITER_EC=""

# run_pipe_bounded <seconds> <reader command string> <fu args...>
# Runs `{ node follow-ups.mjs <args> 2>err; echo $? >ec; } | <reader> >out`.
# The writer's own exit code is captured INSIDE the write end rather than from
# PIPESTATUS, so it survives the outer shell and is readable even when the
# reader closed the pipe first.
run_pipe_bounded() {
  local secs="$1" reader="$2"; shift 2
  local o="$TEST_DIR/.pout" e="$TEST_DIR/.perr" w="$TEST_DIR/.pwec" cmd q
  rm -f "$o" "$e" "$w"
  cmd="node $(printf '%q' "$FU")"
  for q in "$@"; do cmd="$cmd $(printf '%q' "$q")"; done
  cmd="{ $cmd 2> $(printf '%q' "$e") ; echo \$? > $(printf '%q' "$w") ; } | $reader > $(printf '%q' "$o")"
  run_bounded "$secs" "$cmd"
  PIPE_READER_OUT="$(cat "$o" 2>/dev/null || true)"
  PIPE_WRITER_ERR="$(cat "$e" 2>/dev/null || true)"
  PIPE_WRITER_EC="$(cat "$w" 2>/dev/null || true)"
  [[ -n "$PIPE_WRITER_EC" ]] || PIPE_WRITER_EC="MISSING"
}

# mk_readers — two stdin readers written into the fixture dir.
#   reader-slow   waits <ms> before reading a byte, then prints the count
#   reader-parse  JSON.parse of the whole payload
# Every byte-count assertion in this suite reads through reader-slow, and that
# is deliberate: node's stdin stays paused until a 'data' listener attaches, so
# a delayed listener genuinely does not drain. Through a FAST reader (`cat`, or
# a counter that attaches its listener immediately) the HUMAN listing did not
# truncate even before the fix — many small writes that the reader keeps up
# with — so a fast-reader byte-count assertion is vacuous on that branch and no
# such reader is kept here.
mk_readers() {
  cat > "$TEST_DIR/reader-slow.mjs" <<'READER_SLOW_EOF'
const delay = Number(process.argv[2] || 400);
setTimeout(() => {
  let n = 0;
  process.stdin.on('data', (c) => { n += c.length; });
  process.stdin.on('end', () => { process.stdout.write(`${n}\n`); });
}, delay);
READER_SLOW_EOF
  cat > "$TEST_DIR/reader-parse.mjs" <<'READER_PARSE_EOF'
let d = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { d += c; });
process.stdin.on('end', () => {
  const bytes = Buffer.byteLength(d);
  try {
    const j = JSON.parse(d);
    const items = Array.isArray(j.items) ? j.items.length : -1;
    process.stdout.write(`OK bytes=${bytes} items=${items}\n`);
  } catch (err) {
    process.stdout.write(`FAIL bytes=${bytes} ${err.message}\n`);
  }
});
READER_PARSE_EOF
}

# mk_big_ledger <name> <count> -> a fixture ledger with <count> follow_up
# entries, wide enough that `list --json` over it clears 174080 bytes and the
# human listing clears 65536. Built here rather than read from the live ledger
# on purpose: the live payload is a moving number, and an arm that depends on
# today's 87012 bytes stops proving anything next week.
mk_big_ledger() {
  local f="$TEST_DIR/$1.jsonl"
  rm -f "$f"
  node -e '
    const fs = require("fs");
    const out = ["# Decision Log — append-only, one JSON object per line (JSONL format)"];
    const n = Number(process.argv[2]);
    for (let i = 0; i < n; i += 1) {
      const s = String(i).padStart(4, "0");
      out.push(JSON.stringify({
        v: 1,
        ts: "2026-0" + (1 + (i % 8)) + "-" + String(1 + (i % 27)).padStart(2, "0") + "T0" + (i % 10) + ":0" + (i % 6) + ":00Z",
        actor: "fixture",
        type: "follow_up",
        id: "fu-fixture-" + s,
        ref_id: "CHANGE-" + (1000 + i),
        severity: ["P1", "P2", "P3"][i % 3],
        finding: "synthetic finding " + s + " padded to a realistic one-line width so the human listing also crosses the 64 KB pipe buffer threshold",
        decision: "deferred for fixture purposes, entry " + s,
        source: "docs/ai/reports/fixture-" + s + ".md",
      }));
    }
    fs.writeFileSync(process.argv[1], out.join("\n") + "\n");
  ' "$f" "$2"
  printf '%s' "$f"
}

# ============================ TEST-001 (Spec-AC-01) ==========================
test_001_schema_and_id_discipline() {
  log_info "Test: D1 entry shape + id discipline — valid add accepted and re-read; bad shape, over-length, duplicate, missing flag and bad severity each exit 2 with the ledger byte-length UNCHANGED (TEST-001)..."
  local led; led="$(mk_ledger t001)"
  printf '%s\n' '{"v":1,"ts":"2026-08-01T00:00:00Z","actor":"orchestrator","type":"review_disposition","ref_id":"CHANGE-0001","finding":"unrelated","decision":"unrelated","source":"none"}' >> "$led"

  run_fu add --ledger "$led" --id fu-good-one --ref CHANGE-0142 --severity P2 \
    --what "a one-line finding" --why "deferred for reasons" --source "docs/ai/reviews/x.md"
  [[ "$EC" == 0 ]] || log_fail "a valid add must exit 0, got $EC: $ERR"
  [[ "$(nlines "$led")" == "6" ]] || log_fail "a valid add must append EXACTLY one line (4 comment + 1 seed + 1 new), got $(nlines "$led")"

  # The appended line is machine-serialized JSON of the D1 follow_up shape.
  local probe
  probe="$(node -e '
    const fs=require("fs");
    const lines=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(l=>l.trim()!==""&&!l.startsWith("#"));
    const o=JSON.parse(lines[lines.length-1]);
    const want=["v","ts","actor","type","id","ref_id","severity","finding","decision","source"];
    const missing=want.filter(k=>!(k in o));
    if (missing.length) { console.log("MISSING:"+missing.join(",")); process.exit(0); }
    if (o.type!=="follow_up") { console.log("TYPE:"+o.type); process.exit(0); }
    if (o.v!==1) { console.log("V:"+o.v); process.exit(0); }
    if ("status" in o) { console.log("STATUS-ON-FOLLOW-UP"); process.exit(0); }
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(o.ts)) { console.log("TS:"+o.ts); process.exit(0); }
    console.log("OK");
  ' "$led")"
  [[ "$probe" == "OK" ]] || log_fail "appended follow_up line is not the D1 shape: $probe"

  # It is re-read by the tool's own fold.
  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "list after add must exit 0, got $EC: $ERR"
  grep -qF '"id": "fu-good-one"' <<<"$OUT" || log_fail "the added id must be re-read by the fold: $OUT"

  # --- write-refuse arm: every refusal is exit 2 with NOTHING appended -------
  local before; before="$(fsize "$led")"
  local case_name
  for case_name in badshape toolong dup missing badsev unknownflag; do
    case "$case_name" in
      badshape)    run_fu add --ledger "$led" --id "FU-Bad_Shape" --ref R --severity P1 --what w --why y --source s ;;
      toolong)     run_fu add --ledger "$led" --id "fu-aaaaaaaaaa-bbbbbbbbbb-cccccccccc-dddddddddd" --ref R --severity P1 --what w --why y --source s ;;
      dup)         run_fu add --ledger "$led" --id "fu-good-one" --ref R --severity P1 --what w --why y --source s ;;
      missing)     run_fu add --ledger "$led" --id "fu-missing-why" --ref R --severity P1 --what w --source s ;;
      badsev)      run_fu add --ledger "$led" --id "fu-bad-sev" --ref R --severity P9 --what w --why y --source s ;;
      unknownflag) run_fu add --ledger "$led" --id "fu-unknown-flag" --ref R --severity P1 --what w --why y --source s --nope 1 ;;
    esac
    [[ "$EC" == 2 ]] || log_fail "add/$case_name must exit 2 (usage error), got $EC: $OUT $ERR"
    [[ "$(fsize "$led")" == "$before" ]] || log_fail "add/$case_name must append NOTHING (ledger grew from $before to $(fsize "$led"))"
  done

  # Trailing-newline hygiene: a ledger whose last line lacks \n must not get a
  # glued record (mid-operation/partial-write shape).
  local led2; led2="$(mk_ledger t001b)"
  printf '%s' '{"v":1,"ts":"2026-08-01T00:00:00Z","actor":"a","type":"note","ref_id":"X","decision":"no trailing newline"}' >> "$led2"
  run_fu add --ledger "$led2" --id fu-after-torn --ref R --severity P3 --what w --why y --source s
  [[ "$EC" == 0 ]] || log_fail "add onto a newline-less ledger must exit 0, got $EC: $ERR"
  [[ "$(nlines "$led2")" == "6" ]] || log_fail "add onto a newline-less ledger must not glue records, got $(nlines "$led2") lines"

  log_pass "D1 shape written, re-read, and every malformed/duplicate/missing-flag write refused at exit 2 with a byte-unchanged ledger (TEST-001)"
}

# ============================ TEST-002 (Spec-AC-02) ==========================
test_002_query_path() {
  log_info "Test: query path — byte-identical repeat runs, --ref/--status/--age-days filters, --json agreement, empty and non-empty backlogs exit 0, unknown flag exits 2 (TEST-002)..."
  local led; led="$(mk_ledger t002)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-old-one","ref_id":"CHANGE-0100","severity":"P1","finding":"old open item","decision":"deferred","source":"s1"}'
    printf '%s\n' '{"v":1,"ts":"2026-06-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-mid-two","ref_id":"CHANGE-0101","severity":"P2","finding":"mid open item","decision":"deferred","source":"s2"}'
    printf '%s\n' '{"v":1,"ts":"2026-06-02T00:00:00Z","actor":"a","type":"follow_up","id":"fu-done-three","ref_id":"CHANGE-0100","severity":"P3","finding":"resolved item","decision":"deferred","source":"s3"}'
    printf '%s\n' '{"v":1,"ts":"2026-06-03T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-done-three","status":"done","resolved_by":"CHANGE-0102","source":"abc123"}'
  } >> "$led"

  # Determinism: two identical runs are byte-identical.
  run_fu list --ledger "$led"; local run1="$OUT"
  [[ "$EC" == 0 ]] || log_fail "list must exit 0 on a non-empty backlog, got $EC"
  run_fu list --ledger "$led"; local run2="$OUT"
  [[ "$run1" == "$run2" ]] || log_fail "two identical list runs must be byte-identical"

  # Default view is the OPEN backlog; the header still names every bucket.
  grep -qF "fu-old-one" <<<"$run1" || log_fail "default list must show the open items"
  grep -qF "fu-done-three" <<<"$run1" && log_fail "default list must NOT show a closed item"
  grep -qE "open=2 closed=1 total=3" <<<"$run1" || log_fail "header must name open/closed/total honestly: $run1"

  # --ref narrows to the expected id set.
  run_fu list --ledger "$led" --ref CHANGE-0101
  [[ "$EC" == 0 ]] || log_fail "--ref must exit 0"
  grep -qF "fu-mid-two" <<<"$OUT" || log_fail "--ref CHANGE-0101 must keep fu-mid-two"
  grep -qF "fu-old-one" <<<"$OUT" && log_fail "--ref CHANGE-0101 must drop fu-old-one"

  # --status narrows to the expected id set.
  run_fu list --ledger "$led" --status done
  [[ "$EC" == 0 ]] || log_fail "--status done must exit 0"
  grep -qF "fu-done-three" <<<"$OUT" || log_fail "--status done must keep fu-done-three"
  grep -qF "fu-old-one" <<<"$OUT" && log_fail "--status done must drop the open items"

  # --age-days narrows to the expected id set (fu-old-one is far older).
  run_fu list --ledger "$led" --age-days 10000
  [[ "$EC" == 0 ]] || log_fail "--age-days must exit 0 even when it empties the view"
  grep -qE "shown=0" <<<"$OUT" || log_fail "--age-days 10000 must narrow to nothing: $OUT"

  # Non-vacuity (review NB-4): the emptying case alone would also pass for a
  # filter hard-wired to return nothing. Assert the KEEPING case too — a
  # threshold the aged item clears must retain exactly it.
  run_fu list --ledger "$led" --age-days 1
  [[ "$EC" == 0 ]] || log_fail "--age-days 1 must exit 0"
  grep -qF "fu-old-one" <<<"$OUT" \
    || log_fail "--age-days 1 must KEEP the aged item (filter would be vacuous otherwise): $OUT"
  grep -qE "shown=0" <<<"$OUT" \
    && log_fail "--age-days 1 must not empty the view: $OUT"

  # --json parses and its item ids match the text rows exactly.
  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "--json must exit 0"
  local agree
  agree="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const text=process.argv[2];
    const ids=j.items.map(i=>i.id).sort();
    const rows=text.split("\n").filter(l=>/^(open|done|dropped)\b/.test(l)).map(l=>l.trim().split(/\s+/)[1]).sort();
    if (JSON.stringify(ids)!==JSON.stringify(rows)) { console.log("MISMATCH json="+JSON.stringify(ids)+" text="+JSON.stringify(rows)); process.exit(0); }
    if (j.counts.open!==2||j.counts.closed!==1||j.counts.total!==3) { console.log("COUNTS:"+JSON.stringify(j.counts)); process.exit(0); }
    const it=j.items.find(i=>i.id==="fu-old-one");
    if (!it||it.severity!=="P1"||it.ref_id!=="CHANGE-0100"||typeof it.age_days!=="number") { console.log("ITEM:"+JSON.stringify(it)); process.exit(0); }
    if (j.items[0].id!=="fu-old-one") { console.log("ORDER:"+j.items.map(i=>i.id).join(",")); process.exit(0); }
    console.log("OK");
  ' "$OUT" "$run1")"
  [[ "$agree" == "OK" ]] || log_fail "--json must agree with the text rows: $agree"

  # Empty backlog: exit 0, never an error (D6).
  local empty; empty="$(mk_ledger t002-empty)"
  run_fu list --ledger "$empty"
  [[ "$EC" == 0 ]] || log_fail "an EMPTY backlog must exit 0 (never an error), got $EC"
  grep -qE "total=0" <<<"$OUT" || log_fail "empty backlog must report total=0: $OUT"
  run_fu list --ledger "$empty" --json
  [[ "$EC" == 0 ]] || log_fail "empty backlog --json must exit 0"

  # Absent ledger on the READ path is a usage error (unreadable ledger, D6).
  run_fu list --ledger "$TEST_DIR/does-not-exist.jsonl"
  [[ "$EC" == 2 ]] || log_fail "an unreadable ledger must exit 2, got $EC"

  # Unknown flag / unknown subcommand: exit 2 (D6).
  run_fu list --ledger "$led" --nope
  [[ "$EC" == 2 ]] || log_fail "an unknown flag must exit 2, got $EC"
  run_fu frobnicate --ledger "$led"
  [[ "$EC" == 2 ]] || log_fail "an unknown subcommand must exit 2, got $EC"
  run_fu list --ledger "$led" --status bogus
  [[ "$EC" == 2 ]] || log_fail "an unknown --status value must exit 2, got $EC"
  run_fu --help
  [[ "$EC" == 0 ]] || log_fail "--help must exit 0"
  grep -qF "follow-ups.mjs close" <<<"$OUT" || log_fail "--help must document the manual close step (D5)"

  log_pass "Query path deterministic, filtered, --json-consistent; empty and non-empty backlogs exit 0; usage errors exit 2 (TEST-002)"
}

# ============================ TEST-003 (Spec-AC-02) ==========================
test_003_degrade_notes_and_zero_network() {
  log_info "Test: degrade-with-NOTE — comment lines skipped, malformed line named+skipped, id-less legacy folded under a derived id, duplicate id first-wins, dangling status named; source carries no network import (TEST-003)..."
  local led; led="$(mk_ledger t003)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-08-11T05:20:00Z","actor":"orchestrator","type":"follow_up","ref_id":"telemetry-completeness","finding":"legacy id-less entry","decision":"deferred","source":"PR #242"}'
    printf '%s\n' 'this is not json at all'
    printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-dupe","ref_id":"R1","severity":"P2","finding":"first wins","decision":"d","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2026-07-02T00:00:00Z","actor":"a","type":"follow_up","id":"fu-dupe","ref_id":"R2","severity":"P1","finding":"second loses","decision":"d","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2026-07-03T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-never-raised","status":"done","resolved_by":"R9","source":"s"}'
    printf '%s\n' '# a trailing comment line in the middle of the data'
    printf '%s\n' ''
  } >> "$led"

  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "a malformed/dangling/duplicate ledger must still exit 0 on the read path, got $EC: $ERR"
  local probe
  probe="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const notes=j.notes.join(" | ");
    const errs=[];
    if (!/malformed/i.test(notes)) errs.push("no malformed-line note: "+notes);
    if (!/derived/i.test(notes)) errs.push("no derived-id note: "+notes);
    if (!/duplicate/i.test(notes)) errs.push("no duplicate-id note: "+notes);
    if (!/dangling/i.test(notes)) errs.push("no dangling-status note: "+notes);
    const legacy=j.items.find(i=>i.id==="fu-telemetry-completeness-20260811T0520");
    if (!legacy) errs.push("legacy id-less entry not folded under its derived id: "+j.items.map(i=>i.id).join(","));
    else if (legacy.derived_id!==true) errs.push("derived id not flagged: "+JSON.stringify(legacy));
    const dupe=j.items.filter(i=>i.id==="fu-dupe");
    if (dupe.length!==1) errs.push("duplicate id must fold to ONE item, got "+dupe.length);
    else if (dupe[0].finding!=="first wins") errs.push("first occurrence must win, got "+dupe[0].finding);
    if (j.items.some(i=>i.id==="fu-never-raised")) errs.push("a dangling status must never be listed as an item");
    console.log(errs.length?errs.join(" ; "):"OK");
  ' "$OUT")"
  [[ "$probe" == "OK" ]] || log_fail "degrade-with-NOTE contract violated: $probe"

  # The same notes must be visible on the TEXT path too (not JSON-only).
  run_fu list --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "text list must exit 0"
  grep -qE "^NOTE|^EXCLUDED" <<<"$OUT" || log_fail "text output must carry the NOTE/EXCLUDED lines: $OUT"

  # A derived-id legacy entry is an accepted close target (D1b).
  run_fu close --ledger "$led" --id "fu-telemetry-completeness-20260811T0520" --resolved-by CHANGE-0142 --source "test"
  [[ "$EC" == 0 ]] || log_fail "a derived id must be an accepted close target, got $EC: $ERR"

  # Zero-network / zero-LLM source pin.
  local src; src="$(cat "$FU")"
  grep -qE "node:(http|https|net|tls|dgram)" <<<"$src" && log_fail "follow-ups.mjs must not import any network module"
  grep -qE "\bfetch\(" <<<"$src" && log_fail "follow-ups.mjs must not call fetch()"
  grep -qE "https?://[a-zA-Z0-9]" <<<"$src" && log_fail "follow-ups.mjs must not carry a live URL endpoint"

  log_pass "Comment lines skipped; malformed, derived-id, duplicate and dangling cases each named in a NOTE and never fatal; no network surface in source (TEST-003)"
}

# ============================ TEST-004 (Spec-AC-03) ==========================
# Backfill accounting, mechanical: for each PRE-CHANGE ledger line whose
# `decision` carries K occurrences of the literal FOLLOW-UP, the ledger must
# carry EXACTLY K appended lines with `source_ts` equal to that line's `ts`.
# The 11 source timestamps are the D3 inventory, pinned here; K is RECOMPUTED
# from the live ledger so the pin can never drift from the prose silently.
test_004_backfill_accounting() {
  log_info "Test: backfill accounting — per-source-ts clause counts recomputed from the ledger equal the appended origin:backfill counts, totalling 14 across 11 source entries (TEST-004)..."
  [[ -f "$LIVE_LEDGER" ]] || log_fail "live ledger not found: $LIVE_LEDGER"
  local result
  result="$(node -e '
    const fs=require("fs");
    const INVENTORY=[
      ["2026-08-08T14:15:00Z",1],["2026-08-09T10:47:00Z",1],["2026-08-11T21:22:00Z",1],
      ["2026-08-11T23:18:00Z",1],["2026-08-13T01:26:00Z",4],["2026-08-13T02:26:00Z",1],
      ["2026-08-13T10:50:00Z",1],["2026-08-13T11:22:00Z",1],["2026-08-13T15:48:00Z",1],
      ["2026-08-13T16:05:00Z",1],["2026-08-13T18:47:00Z",1],
    ];
    const errs=[];
    const recs=[];
    for (const line of fs.readFileSync(process.argv[1],"utf8").split("\n")) {
      const t=line.trim();
      if (t===""||t.startsWith("#")) continue;
      try { recs.push(JSON.parse(t)); } catch { errs.push("malformed ledger line: "+t.slice(0,60)); }
    }
    // Recompute K per source ts from the ledger itself (never trust the pin alone).
    const clauseCount=new Map();
    for (const r of recs) {
      if (!r || typeof r.ts!=="string" || typeof r.decision!=="string") continue;
      const k=(r.decision.match(/FOLLOW-UP/g)||[]).length;
      if (k>0) clauseCount.set(r.ts,(clauseCount.get(r.ts)||0)+k);
    }
    // Appended backfill lines, grouped by the source ts they cite.
    const backfilled=new Map();
    let backfillTotal=0;
    for (const r of recs) {
      if (!r || r.origin!=="backfill" || typeof r.source_ts!=="string") continue;
      if (r.type!=="follow_up" && r.type!=="follow_up_status") { errs.push("backfill line of unexpected type: "+r.type); continue; }
      backfilled.set(r.source_ts,(backfilled.get(r.source_ts)||0)+1);
      backfillTotal+=1;
    }
    let pinnedTotal=0;
    for (const [ts,k] of INVENTORY) {
      pinnedTotal+=k;
      const live=clauseCount.get(ts)||0;
      if (live!==k) errs.push(`clause count drift at ${ts}: pinned ${k}, ledger ${live}`);
      const got=backfilled.get(ts)||0;
      if (got!==k) errs.push(`accounting violation at ${ts}: ${k} clause(s) but ${got} appended line(s)`);
    }
    if (pinnedTotal!==14) errs.push("D3 inventory must total 14, got "+pinnedTotal);
    if (backfillTotal!==14) errs.push("total source_ts-carrying backfill lines must be 14, got "+backfillTotal);
    // No backfill line may cite a source ts outside the pinned inventory.
    const known=new Set(INVENTORY.map(x=>x[0]));
    for (const ts of backfilled.keys()) if (!known.has(ts)) errs.push("backfill line cites an unknown source_ts: "+ts);
    // Every backfilled follow_up must carry a schema-valid id.
    for (const r of recs) {
      if (r && r.origin==="backfill" && r.type==="follow_up") {
        if (typeof r.id!=="string" || !/^fu-[a-z0-9]+(-[a-z0-9]+)*$/.test(r.id) || r.id.length>40) errs.push("backfill id violates D1: "+r.id);
      }
    }
    console.log(errs.length?errs.join(" ; "):"OK");
  ' "$LIVE_LEDGER")"
  [[ "$result" == "OK" ]] || log_fail "backfill accounting: $result"
  log_pass "14 backfill lines across the 11 D3 source entries, exactly K per K-clause line, every id D1-valid (TEST-004)"
}

# ============================ TEST-005 (Spec-AC-03) ==========================
test_005_history_integrity() {
  log_info "Test: history integrity — the base ledger is a byte-exact PREFIX of the working-tree ledger; the same predicate REJECTS a planted rewrite (mutation control) (TEST-005)..."
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  local base="$TEST_DIR/base-decisions.jsonl"
  if ! git -C "$PROJECT_ROOT" show "$BASE_REF:docs/ai/decisions.jsonl" > "$base" 2>/dev/null; then
    # NEVER log_skip here: that exits 42 and the framework reports the WHOLE
    # suite as SKIP, which is how this suite silently ran zero tests on CI.
    log_info "TEST-005 skipped: base ref $BASE_REF has no docs/ai/decisions.jsonl (shallow clone or detached base)"
    return 0
  fi
  local verdict
  verdict="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    // isPureAppend, learned-append.mjs:217, applied as a TEST not as a gate.
    if (head.length < base.length) { console.log("SHORTER: working tree is "+(base.length-head.length)+" bytes shorter than base"); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    if (!prefix.equals(base)) {
      let i=0; while (i<base.length && prefix[i]===base[i]) i+=1;
      console.log("DIVERGES at byte offset "+i);
      process.exit(0);
    }
    console.log("PREFIX-OK appended="+(head.length-base.length));
  ' "$base" "$LIVE_LEDGER")"
  grep -qF "PREFIX-OK" <<<"$verdict" || log_fail "existing ledger bytes were rewritten: $verdict"

  # MUTATION CONTROL: the same predicate must REJECT a planted rewrite of an
  # existing line — otherwise the assertion above is vacuous.
  local mutated="$TEST_DIR/mutated-decisions.jsonl"
  node -e '
    const fs=require("fs");
    const lines=fs.readFileSync(process.argv[1],"utf8").split("\n");
    let idx=lines.findIndex((l,i)=>i>20 && l.trim()!=="" && !l.startsWith("#"));
    lines[idx]=lines[idx].replace(/"decision":"/,"\"decision\":\"MUTATED ");
    fs.writeFileSync(process.argv[2], lines.join("\n"));
  ' "$LIVE_LEDGER" "$mutated"
  local mutverdict
  mutverdict="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    if (head.length < base.length) { console.log("SHORTER"); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    if (!prefix.equals(base)) { let i=0; while (i<base.length && prefix[i]===base[i]) i+=1; console.log("DIVERGES at byte offset "+i); process.exit(0); }
    console.log("PREFIX-OK");
  ' "$base" "$mutated")"
  grep -qF "DIVERGES" <<<"$mutverdict" || log_fail "mutation control failed: a planted rewrite was accepted as a pure append ($mutverdict)"

  log_pass "Base ledger is a byte-exact prefix of the working tree, and a planted rewrite is rejected by the same predicate (TEST-005)"
}

# ============================ TEST-008 (Spec-AC-05) ==========================
test_008_close_path() {
  log_info "Test: close appends a follow_up_status, leaves the follow_up line untouched, PROVES the flip by re-reading; unknown id exits 2 with nothing appended; re-close is idempotent at exit 0; a shadowed verification exits 1 (TEST-008)..."
  local led; led="$(mk_ledger t008)"
  printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-close-me","ref_id":"CHANGE-0100","severity":"P2","finding":"needs closing","decision":"deferred","source":"s"}' >> "$led"
  local original; original="$(cat "$led")"

  run_fu close --ledger "$led" --id fu-close-me --resolved-by CHANGE-0143 --source "abc1234"
  [[ "$EC" == 0 ]] || log_fail "close must exit 0 when the re-read confirms the flip, got $EC: $ERR"
  grep -qF "fu-close-me" <<<"$OUT" || log_fail "close must print the folded item: $OUT"
  grep -qF "done" <<<"$OUT" || log_fail "close must print the item's NEW status: $OUT"

  # Append-only: the pre-close bytes are a prefix of the post-close file.
  local head_bytes; head_bytes="$(node -e '
    const fs=require("fs");
    const orig=Buffer.from(process.argv[1]+"\n","utf8");
    const now=fs.readFileSync(process.argv[2]);
    console.log(now.length>=orig.length && now.subarray(0,orig.length).equals(orig) ? "APPEND-ONLY" : "REWRITTEN");
  ' "$original" "$led")"
  [[ "$head_bytes" == "APPEND-ONLY" ]] || log_fail "close must APPEND — the follow_up line was rewritten"

  run_fu list --ledger "$led" --status done --json
  [[ "$EC" == 0 ]] || log_fail "post-close list must exit 0"
  local closed
  closed="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const it=j.items.find(i=>i.id==="fu-close-me");
    if (!it) { console.log("MISSING"); process.exit(0); }
    console.log(it.status==="done" && it.resolved_by==="CHANGE-0143" ? "OK" : JSON.stringify(it));
  ' "$OUT")"
  [[ "$closed" == "OK" ]] || log_fail "post-close fold must show done + resolved_by: $closed"

  # Idempotent re-close: exit 0, a NOTE, and NOTHING appended.
  local before; before="$(fsize "$led")"
  run_fu close --ledger "$led" --id fu-close-me --resolved-by CHANGE-0143 --source "abc1234"
  [[ "$EC" == 0 ]] || log_fail "a re-close must be idempotent at exit 0, got $EC: $ERR"
  grep -qE "NOTE" <<<"$OUT$ERR" || log_fail "a re-close must be NAMED in a NOTE: $OUT $ERR"
  [[ "$(fsize "$led")" == "$before" ]] || log_fail "a re-close must append nothing"

  # Unknown id: exit 2, nothing appended.
  run_fu close --ledger "$led" --id fu-not-here --resolved-by CHANGE-0143
  [[ "$EC" == 2 ]] || log_fail "an unknown close id must exit 2, got $EC"
  [[ "$(fsize "$led")" == "$before" ]] || log_fail "an unknown close id must append nothing"
  run_fu close --ledger "$led" --resolved-by CHANGE-0143
  [[ "$EC" == 2 ]] || log_fail "a close with no --id must exit 2, got $EC"

  # MID-OPERATION FAILURE: the append lands but the re-read does NOT show the
  # flip, because a FUTURE-dated status record for the same id shadows it.
  # This is the only shape that can make the write path return 1 (D6).
  local shadow; shadow="$(mk_ledger t008-shadow)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-shadowed","ref_id":"CHANGE-0100","severity":"P2","finding":"shadowed","decision":"deferred","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2999-01-01T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-shadowed","status":"open","resolved_by":"none","source":"s"}'
  } >> "$shadow"
  run_fu close --ledger "$shadow" --id fu-shadowed --resolved-by CHANGE-0143 --source "abc"
  [[ "$EC" == 1 ]] || log_fail "a shadowed post-append re-read must exit 1 (write-verification failure), got $EC: $OUT $ERR"

  # The manual step is documented where D5 says it is.
  local pdoc="$PROJECT_ROOT/docs/product/aai-decisions.md"
  [[ -f "$pdoc" ]] || log_fail "product doc missing: $pdoc"
  grep -qF "follow-ups.mjs close" "$pdoc" || log_fail "docs/product/aai-decisions.md must document the manual close invocation (D5)"

  # close-work-item.mjs must never gain follow-ups WIRING (D5): D5's actual
  # rejection is "wiring --resolves fu-x into close-work-item.mjs" (coupling
  # its transaction to a second append-only ledger) — NOT "this file may
  # never change again for any reason". role-verification-guards unification:
  # this consults the SAME shared content-hash allowlist as
  # test-aai-doc-numbering.sh TEST-029 (tests/skills/lib/close-work-item-pin.sh)
  # rather than a keyword scan of its own — a legitimate future edit updates
  # ONE shared list, re-affirming BOTH specs' frozen invariants in one place,
  # instead of two suites independently guessing at what changed. The OK-vs-
  # ABSENT/MISMATCH/unrecognized-status assertion is hoisted into
  # close_work_item_pin_assert (role-verification-guards remediation, N-B) so
  # there is exactly one guard, not a copy re-implemented in every caller.
  local result hash
  result="$(close_work_item_pin_assert "$PROJECT_ROOT")" || log_fail "TEST-008: $result"
  hash="${result#OK }"

  log_pass "close appends + proves by re-read, is idempotent, refuses unknown ids, exits 1 on an unproven flip; manual step documented; close-work-item content hash $hash on the shared allowlist (TEST-008)"
}

# ============================ TEST-009 (Spec-AC-06) ==========================
test_009_consumer_seam() {
  log_info "Test: consumer seam — routine-emit still GRANTS over a tool-written ledger; a planted malformed appended line makes it FAIL CLOSED; doctor CAT-07 still reports a non-zero decisions count without WARN (TEST-009)..."
  [[ -f "$ROUTINE_EMIT" ]] || log_skip "routine-emit.mjs not found"
  local led; led="$(mk_ledger t009)"
  printf '%s\n' '{"v":1,"ts":"2026-08-01T00:00:00Z","type":"routine_authorization","ref":"test-ref","by":"human","grants":["merge"],"notes":"fixture"}' >> "$led"

  # The new tool writes into the SAME ledger the fail-closed reader scans.
  run_fu add --ledger "$led" --id fu-seam-one --ref CHANGE-0142 --severity P2 \
    --what "seam item" --why "deferred" --source "s"
  [[ "$EC" == 0 ]] || log_fail "add must succeed before the seam check: $ERR"
  run_fu close --ledger "$led" --id fu-seam-one --resolved-by CHANGE-0143 --source "s"
  [[ "$EC" == 0 ]] || log_fail "close must succeed before the seam check: $ERR"

  local remit_out remit_ec=0
  remit_out="$(node "$ROUTINE_EMIT" --routine SCRYER --harness generic --os macos \
    --repo owner/repo --schedule "0 7 * * *" --model m --tz UTC \
    --merge --ref test-ref --decisions "$led" 2>&1)" || remit_ec=$?
  [[ "$remit_ec" == 0 ]] || log_fail "routine-emit must exit 0 over a tool-written ledger, got $remit_ec: $remit_out"
  grep -qF "MERGE DISABLED" <<<"$remit_out" && log_fail "routine-emit must still GRANT over a ledger the new tool wrote: $remit_out"

  # MUTATION CONTROL: one malformed non-comment line must poison the WHOLE
  # ledger — the fail-closed arm the emission helper exists to protect.
  local poisoned="$TEST_DIR/t009-poisoned.jsonl"
  cp "$led" "$poisoned"
  printf '%s\n' '{"v":1,"ts":"2026-08-14T00:00:00Z","type":"follow_up","id":"fu-broken",' >> "$poisoned"
  local pois_out pois_ec=0
  pois_out="$(node "$ROUTINE_EMIT" --routine SCRYER --harness generic --os macos \
    --repo owner/repo --schedule "0 7 * * *" --model m --tz UTC \
    --merge --ref test-ref --decisions "$poisoned" 2>&1)" || pois_ec=$?
  [[ "$pois_ec" == 0 ]] || log_fail "routine-emit must still exit 0 on a poisoned ledger (degrade, never crash), got $pois_ec"
  grep -qF "MERGE DISABLED" <<<"$pois_out" \
    || log_fail "mutation control failed: a malformed appended line did NOT revoke merge authorization — the fail-closed seam is not really crossed"

  # The reporter reader tolerates exactly what the authorization reader refuses.
  run_fu list --ledger "$poisoned"
  [[ "$EC" == 0 ]] || log_fail "the reporter reader must TOLERATE the same malformed line the authorization reader refuses, got $EC"

  # doctor CAT-07 over the real tree: non-zero decisions count, no WARN.
  if [[ -f "$DOCTOR" ]]; then
    local doc_out doc_ec=0
    doc_out="$(cd "$PROJECT_ROOT" && node "$DOCTOR" --json 2>/dev/null)" || doc_ec=$?
    [[ "$doc_ec" == 0 || "$doc_ec" == 1 ]] || log_fail "aai-doctor --json must not crash, got $doc_ec"
    local cat07
    cat07="$(node -e '
      let j; try { j=JSON.parse(process.argv[1]); } catch { console.log("UNPARSEABLE"); process.exit(0); }
      const cats=j.categories||j.results||[];
      const c=cats.find(x=>x&&(x.id==="CAT-07"||x.code==="CAT-07"));
      if (!c) { console.log("NO-CAT-07"); process.exit(0); }
      const detail=String(c.reason||c.detail||c.message||"");
      const m=detail.match(/decisions\.jsonl:\s*(\d+) entries/);
      if (!m) { console.log("NO-COUNT:"+detail); process.exit(0); }   // handled below
      if (Number(m[1])<=0) { console.log("ZERO-COUNT:"+detail); process.exit(0); }
      console.log(c.status==="PASS" ? "OK" : "STATUS:"+c.status+" "+detail);
    ' "$doc_out")"
    # A fresh checkout has no docs/ai/LOOP_TICKS.jsonl (gitignored), so CAT-07
    # legitimately reports THAT instead of the decisions count — the assertion
    # is then inapplicable, not violated (PR #257 Codex P1, which only became
    # observable once the suite stopped skipping wholesale on CI). Degrade with
    # a NAMED line; never a silent pass, never a false failure.
    case "$cat07" in
      OK) : ;;
      NO-COUNT*LOOP_TICKS*|NO-COUNT*loop_ticks*)
        log_info "TEST-009: CAT-07 decisions-count assertion inapplicable on this checkout — $cat07" ;;
      *) log_fail "doctor CAT-07 over the enlarged ledger: $cat07" ;;
    esac
  fi

  log_pass "routine-emit grants over a tool-written ledger and fails closed on a planted malformed line; reporter tolerates it; doctor CAT-07 PASS with a non-zero count (TEST-009)"
}

# ============================ TEST-010 (Spec-AC-09) ==========================
# N1 regression (validation-20260816T131500Z, closed at
# validation-20260816T143000Z): the shared close-work-item pin's callers
# (here and in test-aai-doc-numbering.sh TEST-029) must ASSERT the positive
# OK status, not just denylist the two known failure statuses
# (ABSENT/MISMATCH). A gutted close_work_item_pin_check (empty stdout, exit
# 0 -- the validation report's own defeat attempt) falls through BOTH the
# ABSENT and MISMATCH arms of a denylist-shaped caller and reads as success.
#
# Hoisted at remediation (role-verification-guards, N-B): N1's static pin
# (validation-20260816T143000Z) grepped the extracted caller function bodies
# for the literal `!= "OK"` -- a real improvement over round-2's inline-copy
# shadow (which proved nothing about the real callers), but STILL a textual
# pin over what was, until this remediation, a textual if/elif chain
# copy-pasted into each caller. A comment mentioning that literal, surviving
# after the real branch is deleted, satisfies a literal grep -- the same
# substitution this scope's own B1/B4/N1 findings kept recurring at one level
# out. The if/elif is now hoisted into ONE function,
# close_work_item_pin_assert (tests/skills/lib/close-work-item-pin.sh), that
# BOTH real callers (test_008_close_path here, and
# test_029_close_work_item_byte_unchanged in test-aai-doc-numbering.sh)
# delegate to in one line -- nothing textual is left to grep for, so this arm
# now shadows close_work_item_pin_check and drives the REAL
# close_work_item_pin_assert directly: a behavioural pin, not a textual one.
test_010_pin_ok_assertion_catches_gutted_check() {
  log_info "Test: close_work_item_pin_assert rejects a gutted close_work_item_pin_check and accepts the real file, and both real callers delegate to it (TEST-010, N-B)..."

  # Behavioural proof: shadow the REAL (sourced) close_work_item_pin_check
  # with the exact defeat shape the validation report proved passes a
  # denylist-only caller (empty output, exit 0), then drive the REAL
  # close_work_item_pin_assert -- not a copy of its logic.
  local probe_rc=0
  (
    set -euo pipefail
    close_work_item_pin_check() { echo ""; }
    close_work_item_pin_assert "$PROJECT_ROOT" >/dev/null
  ) || probe_rc=$?
  [[ "$probe_rc" == 1 ]] \
    || log_fail "TEST-010: a gutted close_work_item_pin_check (empty status, exit 0) must be rejected by close_work_item_pin_assert, got rc=$probe_rc (a denylist-only caller would report rc=0 here)"

  # Positive control: the REAL (unshadowed) check must still assert OK for
  # the real, unmodified close-work-item.mjs.
  close_work_item_pin_assert "$PROJECT_ROOT" >/dev/null \
    || log_fail "TEST-010: close_work_item_pin_assert must accept the real, unmodified close-work-item.mjs"

  # Both real callers are one-line delegations to the shared assert helper --
  # confirms the hoist actually landed in both suites, not only here.
  grep -qF 'close_work_item_pin_assert "$PROJECT_ROOT"' "$PROJECT_ROOT/tests/skills/test-aai-follow-ups.sh" \
    || log_fail "TEST-010: test_008_close_path no longer delegates to close_work_item_pin_assert"
  grep -qF 'close_work_item_pin_assert "$PROJECT_ROOT"' "$PROJECT_ROOT/tests/skills/test-aai-doc-numbering.sh" \
    || log_fail "TEST-010: test_029_close_work_item_byte_unchanged no longer delegates to close_work_item_pin_assert"

  log_pass "TEST-010: close_work_item_pin_assert rejects a gutted check and accepts the real file; both real callers delegate to the single shared guard (N-B)"
}

# ============================ TEST-011 (Spec-AC-01) ==========================
test_011_flag_values_with_leading_dashes() {
  log_info "Test: D1 — a flag value beginning with two dashes is accepted verbatim for every value-taking flag unless it is EXACTLY a token the subcommand knows; a genuinely missing value still exits 2 in all three shapes; --flag=value works including --what=--why and --what=--help; -h/--help/help in FLAG position still print usage at exit 0; routine-emit still GRANTS over a ledger a dashed value was written into (TEST-011)..."
  local led; led="$(mk_ledger t011)"

  # --- bare dashed values accepted for --what/--why/--source/--ref/--actor ---
  run_fu add --ledger "$led" --id fu-dash-one --ref "--change-like-ref" \
    --severity P2 --what "--decisions is undocumented" --why "--deferred, quoted" \
    --source "--evidence-looking-path" --actor "--weird-actor"
  [[ "$EC" == 0 ]] || log_fail "a dashed value must be accepted for --what/--why/--source/--ref/--actor, got $EC: $ERR"
  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "list after the dashed-value add must exit 0"
  local probe
  probe="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const it=j.items.find(i=>i.id==="fu-dash-one");
    if (!it) { console.log("MISSING"); process.exit(0); }
    const errs=[];
    if (it.finding!=="--decisions is undocumented") errs.push("finding:"+it.finding);
    if (it.decision!=="--deferred, quoted") errs.push("decision:"+it.decision);
    if (it.source!=="--evidence-looking-path") errs.push("source:"+it.source);
    if (it.ref_id!=="--change-like-ref") errs.push("ref_id:"+it.ref_id);
    console.log(errs.length?errs.join(" ; "):"OK");
  ' "$OUT")"
  [[ "$probe" == "OK" ]] || log_fail "dashed values must round-trip verbatim through the fold: $probe"
  local rawactor
  rawactor="$(node -e '
    const fs=require("fs");
    const lines=fs.readFileSync(process.argv[1],"utf8").split("\n").filter(l=>l.trim()!==""&&!l.startsWith("#"));
    const o=JSON.parse(lines[lines.length-1]);
    console.log(o.actor==="--weird-actor" ? "OK" : "ACTOR:"+o.actor);
  ' "$led")"
  [[ "$rawactor" == "OK" ]] || log_fail "a dashed --actor value must round-trip verbatim into the raw appended line: $rawactor"

  # --- list --ref with a dashed value narrows correctly (not swallowed) ------
  run_fu list --ledger "$led" --ref "--change-like-ref"
  [[ "$EC" == 0 ]] || log_fail "list --ref with a dashed value must exit 0, got $EC"
  grep -qF "fu-dash-one" <<<"$OUT" || log_fail "list --ref with a dashed value must keep the matching item: $OUT"

  # --- --id: a dashed value is ACCEPTED as the value (not swallowed into a ---
  # --- missing-value error) even though it is then refused on ID GRAMMAR. ---
  run_fu add --ledger "$led" --id "--looks-like-a-flag" --ref R --severity P1 --what w --why y --source s
  [[ "$EC" == 2 ]] || log_fail "a dashed --id must still be refused (bad id shape), got $EC"
  grep -qF "requires a value" <<<"$ERR" && log_fail "a dashed --id value must be ACCEPTED as a value, not read as missing (the value-swallow defect): $ERR"
  grep -qF "does not match ^fu-" <<<"$ERR" || log_fail "a dashed --id must be refused on id GRAMMAR, not on parsing: $ERR"

  # --- --ledger: a value beginning with two dashes is accepted as a PATH -----
  local dashled="$TEST_DIR/--dash-ledger.jsonl"
  cp "$led" "$dashled"
  run_fu list --ledger "$dashled"
  [[ "$EC" == 0 ]] || log_fail "a dashed --ledger PATH VALUE must be accepted, got $EC: $ERR"
  grep -qF "fu-dash-one" <<<"$OUT" || log_fail "list over the dash-named ledger must show its items: $OUT"

  # --- close --resolved-by with a dashed value: full success, no grammar -----
  run_fu close --ledger "$led" --id fu-dash-one --resolved-by "--change-like-ref" --source s
  [[ "$EC" == 0 ]] || log_fail "close --resolved-by with a dashed value must exit 0, got $EC: $ERR"

  # --- a genuinely missing value still exits 2, in ALL THREE shapes ----------
  local before; before="$(fsize "$led")"
  run_fu add --ledger "$led" --what
  [[ "$EC" == 2 ]] || log_fail "end-of-argv missing value must exit 2, got $EC"
  grep -qF 'flag "--what" requires a value' <<<"$ERR" || log_fail "end-of-argv missing value must name the flag: $ERR"
  run_fu add --ledger "$led" --id fu-x --ref R --severity P1 --what --why y --source s
  [[ "$EC" == 2 ]] || log_fail "a following EXACTLY-known-flag must still read as a missing value, got $EC"
  grep -qF 'flag "--what" requires a value' <<<"$ERR" || log_fail "an exactly-known-flag lookahead must name the flag: $ERR"
  run_fu add --ledger "$led" --id fu-x --ref R --severity P1 --what --json
  [[ "$EC" == 2 ]] || log_fail "a following --json must still read as a missing value, got $EC"
  run_fu add --ledger "$led" --id fu-x --ref R --severity P1 --what --help
  [[ "$EC" == 2 ]] || log_fail "a following --help must still read as a missing value, got $EC"
  grep -qF 'flag "--what" requires a value' <<<"$ERR" || log_fail "a following --help must name the flag as missing, not print usage: $ERR"
  run_fu add --ledger "$led" --id fu-x --ref R --severity P1 --what -h
  [[ "$EC" == 2 ]] || log_fail "a following -h must still read as a missing value, got $EC"

  # --- review NB-1: a REAL flag name from a DIFFERENT subcommand in value ---
  # --- position must also be caught. knownTokens used to be built from ONLY
  # --- the current subcommand's flags, so `add ... --what --resolved-by`
  # --- (--resolved-by is a close-only flag) was silently accepted as the
  # --- literal value "--resolved-by" — the exact "a bad input reads as
  # --- success" shape D2 exists to remove, one function over. -------------
  run_fu add --ledger "$led" --id fu-x --ref R --severity P1 --what --resolved-by --why y --source s
  [[ "$EC" == 2 ]] || log_fail "a foreign-subcommand flag (--resolved-by, close-only) in value position on add must be caught as a missing value, got $EC: $ERR"
  grep -qF 'flag "--what" requires a value' <<<"$ERR" || log_fail "the foreign-subcommand-flag lookahead must name the flag: $ERR"
  [[ "$(fsize "$led")" == "$before" ]] || log_fail "no missing-value arm may append anything (ledger grew from $before to $(fsize "$led"))"

  # --- the --flag=value escape hatch -----------------------------------------
  run_fu add --ledger "$led" --id=fu-eq-test --ref=R2 --severity=P3 --what=w2 --why=y2 --source=s2 --actor=--eq-actor
  [[ "$EC" == 0 ]] || log_fail "the --flag=value form must be accepted for every flag, got $EC: $ERR"
  run_fu add --ledger "$led" --id fu-eq-value-test --ref R --severity P2 --what=--why --why y --source s
  [[ "$EC" == 0 ]] || log_fail "--what=--why must be accepted (the escape hatch for a value that IS a known flag token), got $EC: $ERR"
  run_fu list --ledger "$led" --json
  local eqprobe
  eqprobe="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const a=j.items.find(i=>i.id==="fu-eq-test");
    const b=j.items.find(i=>i.id==="fu-eq-value-test");
    const errs=[];
    if (!a || a.ref_id!=="R2" || a.severity!=="P3" || a.finding!=="w2") errs.push("eq-form:"+JSON.stringify(a));
    if (!b || b.finding!=="--why") errs.push("eq-value:"+JSON.stringify(b));
    console.log(errs.length?errs.join(" ; "):"OK");
  ' "$OUT")"
  [[ "$eqprobe" == "OK" ]] || log_fail "flag=value round-trip failed: $eqprobe"

  # --- --ledger=<path> exercises D1 and D2 at once (edge case) --------------
  run_fu list --ledger="$led"
  [[ "$EC" == 0 ]] || log_fail "--ledger=<path> must be accepted, got $EC: $ERR"

  # --- -h / --help / help in FLAG position still print usage, exit 0 --------
  run_fu --help
  [[ "$EC" == 0 ]] || log_fail "--help must exit 0"
  grep -qF "follow-ups.mjs close" <<<"$OUT" || log_fail "--help must print the usage text"
  run_fu -h
  [[ "$EC" == 0 ]] || log_fail "-h must exit 0"
  run_fu help
  [[ "$EC" == 0 ]] || log_fail "help must exit 0"
  run_fu add --ledger "$led" -h
  [[ "$EC" == 0 ]] || log_fail "-h in flag position on a subcommand must still print usage, got $EC"

  # --- --help documents the dashed-value rule + the flag=value escape hatch -
  run_fu --help
  grep -qE "begin with two dashes" <<<"$OUT" || log_fail "--help must document the dashed-value rule"
  grep -qF "flag=value" <<<"$OUT" || log_fail "--help must document the --flag=value escape hatch"

  # --- SEAM-2: routine-emit still GRANTS over the ledger a dashed value was --
  # --- written into (JSON.stringify escapes it; the ledger cannot be
  # --- malformed by construction) --------------------------------------------
  if [[ -f "$ROUTINE_EMIT" ]]; then
    local seamled; seamled="$(mk_ledger t011-seam)"
    printf '%s\n' '{"v":1,"ts":"2026-08-01T00:00:00Z","type":"routine_authorization","ref":"seam-ref","by":"human","grants":["merge"],"notes":"fixture"}' >> "$seamled"
    run_fu add --ledger "$seamled" --id fu-seam-dash --ref R --severity P2 \
      --what "--this quotes a flag name" --why y --source s
    [[ "$EC" == 0 ]] || log_fail "seam add must succeed: $ERR"
    local remit_out remit_ec=0
    remit_out="$(node "$ROUTINE_EMIT" --routine SCRYER --harness generic --os macos \
      --repo owner/repo --schedule "0 7 * * *" --model m --tz UTC \
      --merge --ref seam-ref --decisions "$seamled" 2>&1)" || remit_ec=$?
    [[ "$remit_ec" == 0 ]] || log_fail "routine-emit must exit 0 over a ledger a dashed value was written into: $remit_ec: $remit_out"
    grep -qF "MERGE DISABLED" <<<"$remit_out" && log_fail "SEAM-2 broken: a dashed value revoked merge authorization: $remit_out"
  fi

  log_pass "D1: dashed values accepted verbatim except exactly-known tokens, missing-value still exits 2 in all three shapes, flag=value escape hatch works, -h/--help/help in flag position still print usage, SEAM-2 (routine-emit) unaffected (TEST-011)"
}

# ============================ TEST-012 (Spec-AC-02) ==========================
test_012_unreadable_ledger_refused() {
  log_info "Test: D2 — a --ledger path that is a directory is refused (exit 2, path+reason on stderr, no total=0/absent/reported-as-empty, ledger byte-unchanged) on list/add/close; a chmod-000 file degrades the same way or is skipped as root; --ledger=<dir> exercises the = form into the same refusal (TEST-012)..."
  local led; led="$(mk_ledger t012)"
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-untouched","ref_id":"R","severity":"P1","finding":"must not be appended to","decision":"d","source":"s"}' >> "$led"
  local before; before="$(fsize "$led")"
  # Node's path.resolve() normalizes a double slash (macOS TMPDIR already ends
  # in "/", so "$TEST_DIR/x" often becomes ".../T//x"); squeeze it here too so
  # the string-containment checks below compare like with like.
  local test_dir_norm; test_dir_norm="$(printf '%s' "$TEST_DIR" | tr -s '/')"
  local dir="$test_dir_norm/adirectory"
  mkdir -p "$dir"

  run_fu list --ledger "$dir"
  [[ "$EC" == 2 ]] || log_fail "list --ledger <directory> must exit 2, got $EC"
  grep -qF "$dir" <<<"$ERR" || log_fail "the refusal must name the resolved path: $ERR"
  grep -qE "total=0" <<<"$OUT$ERR" && log_fail "a directory must never print total=0: $OUT $ERR"
  grep -qiE "absent" <<<"$OUT$ERR" && log_fail "a directory must never say absent: $OUT $ERR"
  grep -qF "reported as empty" <<<"$OUT$ERR" && log_fail "a directory must never say reported as empty: $OUT $ERR"

  run_fu add --ledger "$dir" --id fu-refused --ref R --severity P1 --what w --why y --source s
  [[ "$EC" == 2 ]] || log_fail "add --ledger <directory> must exit 2, got $EC"
  grep -qF "$dir" <<<"$ERR" || log_fail "add's refusal must name the resolved path: $ERR"

  run_fu close --ledger "$dir" --id fu-x --resolved-by R
  [[ "$EC" == 2 ]] || log_fail "close --ledger <directory> must exit 2, got $EC"
  grep -qF "$dir" <<<"$ERR" || log_fail "close's refusal must name the resolved path: $ERR"

  [[ "$(fsize "$led")" == "$before" ]] || log_fail "a directory refusal must never touch the real ledger"

  # --ledger=<directory> exercises D1 (the = form) and D2 (the directory
  # guard) at once.
  run_fu list --ledger="$dir"
  [[ "$EC" == 2 ]] || log_fail "--ledger=<directory> must exit 2 (D1+D2 combined), got $EC"
  grep -qF "$dir" <<<"$ERR" || log_fail "--ledger=<directory> refusal must name the path: $ERR"

  # A chmod-000 FILE (not a directory): same outcome, or degrade when running
  # as root (root ignores file permission bits, so the arm would be vacuous).
  local ro="$test_dir_norm/t012-chmod000.jsonl"
  cp "$led" "$ro"
  chmod 000 "$ro"
  if [[ "$(id -u)" == "0" ]]; then
    log_info "TEST-012: chmod-000 arm skipped — running as root ignores file permission bits"
  else
    run_fu list --ledger "$ro"
    [[ "$EC" == 2 ]] || log_fail "an unreadable (chmod 000) ledger file must exit 2, got $EC"
    grep -qF "$ro" <<<"$ERR" || log_fail "the chmod-000 refusal must name the path: $ERR"
  fi
  chmod 644 "$ro"

  log_pass "D2: a directory --ledger is refused on list/add/close (exit 2, path+reason named, no total=0/absent/reported-as-empty, byte-unchanged); --ledger=<dir> refused the same way; chmod-000 refused or degrades as root (TEST-012)"
}

# ============================ TEST-013 (Spec-AC-03) ==========================
test_013_absent_ledger_contract_unchanged() {
  log_info "Test: D2/D3 — the CLI still exits 2 on an absent ledger (the intake's claim of exit 0 is wrong); loadRegistry keeps missing:true + the byte-identical absent note for an absent path, and returns missing:false + an unreadable object + a note matching neither /absent/i nor 'reported as empty' for a directory, neither call throwing (TEST-013)..."
  local absent="$TEST_DIR/t013-does-not-exist.jsonl"
  run_fu list --ledger "$absent"
  [[ "$EC" == 2 ]] || log_fail "an absent ledger must still exit 2 on the CLI, got $EC"
  grep -qF "ledger not found" <<<"$ERR" || log_fail "the absent-ledger CLI message must be unchanged: $ERR"

  local dir="$TEST_DIR/t013-a-directory"
  mkdir -p "$dir"
  local result
  # Env vars, not argv: `node -e` with ANY extra positional arg sets
  # process.argv[1] to that arg, and follow-ups.mjs's own isMain guard
  # compares process.argv[1]'s realpath against ITS OWN realpath — passing
  # $FU as an argv value here would make the IMPORTED module think it is
  # being run as main and execute main() against the other args as a bogus
  # CLI invocation. Zero extra argv sidesteps that collision entirely.
  result="$(FU_PATH="$FU" ABSENT_PATH="$absent" DIR_PATH="$dir" node --input-type=module -e '
    const mod = await import("file://" + process.env.FU_PATH);
    const a = mod.loadRegistry(process.env.ABSENT_PATH);
    const d = mod.loadRegistry(process.env.DIR_PATH);
    const errs = [];
    if (a.missing !== true) errs.push("absent.missing:" + a.missing);
    if (a.unreadable !== null) errs.push("absent.unreadable:" + JSON.stringify(a.unreadable));
    if (!a.notes.some((n) => /absent/i.test(n))) errs.push("absent note missing /absent/i: " + JSON.stringify(a.notes));
    if (d.missing !== false) errs.push("dir.missing:" + d.missing);
    if (!d.unreadable || typeof d.unreadable.code !== "string") errs.push("dir.unreadable:" + JSON.stringify(d.unreadable));
    if (!d.notes.length || d.notes.some((n) => /absent/i.test(n))) errs.push("dir note wrongly matches /absent/i: " + JSON.stringify(d.notes));
    if (d.notes.some((n) => n.includes("reported as empty"))) errs.push("dir note wrongly says reported as empty: " + JSON.stringify(d.notes));
    console.log(errs.length ? errs.join(" ; ") : "OK");
  ' 2>&1)"
  [[ "$result" == "OK" ]] || log_fail "loadRegistry absent-vs-directory contract violated: $result"

  log_pass "CLI still exits 2 on an absent ledger; loadRegistry keeps missing:true+absent-note for an absent path and returns missing:false+unreadable+a discriminable note for a directory, neither call throwing (TEST-013)"
}

# ============================ TEST-014 (Spec-AC-04) ==========================
test_014_malformed_id_named_and_counted() {
  log_info "Test: D3/D3a — a hand-written malformed id is named MALFORMED-ID on the row, id_malformed:true in JSON, counted in counts.malformed_ids and STILL in counts.open; a derived (id-less) legacy entry is NEVER marked malformed; exactly one id-grammar regex literal remains in the source (TEST-014)..."
  local led; led="$(mk_ledger t014)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-well-formed","ref_id":"R1","severity":"P1","finding":"a normal item","decision":"d","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2026-01-02T00:00:00Z","actor":"a","type":"follow_up","id":"BAD ID","ref_id":"R2","severity":"P2","finding":"malformed id item","decision":"d","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2026-01-03T00:00:00Z","actor":"a","type":"follow_up","id":"fu-aaaaaaaaaa-bbbbbbbbbb-cccccccccc-dddddddddd","ref_id":"R3","severity":"P3","finding":"over-length id item","decision":"d","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2026-01-04T00:00:00Z","actor":"a","type":"follow_up","ref_id":"legacy-no-id","finding":"an id-less legacy entry","decision":"d","source":"s"}'
  } >> "$led"

  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "a ledger with malformed ids must still exit 0 on the read path, got $EC: $ERR"
  local probe
  probe="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const errs=[];
    const bad=j.items.find(i=>i.id==="BAD ID");
    const long=j.items.find(i=>i.id&&i.id.length>40);
    const good=j.items.find(i=>i.id==="fu-well-formed");
    const legacy=j.items.find(i=>i.derived_id===true);
    if (!bad || bad.id_malformed!==true) errs.push("BAD-ID id_malformed:"+JSON.stringify(bad));
    if (!long || long.id_malformed!==true) errs.push("over-length id_malformed:"+JSON.stringify(long));
    if (!good || good.id_malformed!==false) errs.push("well-formed id_malformed:"+JSON.stringify(good));
    if (!legacy || legacy.id_malformed!==false) errs.push("derived legacy id_malformed:"+JSON.stringify(legacy));
    if (j.counts.malformed_ids!==2) errs.push("counts.malformed_ids:"+j.counts.malformed_ids);
    if (j.counts.open!==4) errs.push("counts.open:"+j.counts.open+" (nothing may be hidden)");
    const note=j.notes.find(n=>/^NOTE 2 follow-up\(s\) carry an id/.test(n));
    if (!note) errs.push("no note naming the malformed-id count: "+JSON.stringify(j.notes));
    else if (!/still counted/i.test(note)) errs.push("note does not say the items are still counted: "+note);
    console.log(errs.length?errs.join(" ; "):"OK");
  ' "$OUT")"
  [[ "$probe" == "OK" ]] || log_fail "malformed-id contract violated: $probe"

  run_fu list --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "text list must exit 0"
  grep -qF "MALFORMED-ID" <<<"$OUT" || log_fail "the text row must carry the MALFORMED-ID token: $OUT"
  # Row-only count: the summary NOTE line also legitimately says the words
  # "MALFORMED-ID" once, so count only lines that are actual ITEM ROWS
  # (leading open|done|dropped, SEAM-6's own row-detection convention). A
  # here-string into node avoids a `cmd | grep` pipe (this suite's own
  # SIGPIPE-under-pipefail trap, see the file header).
  local markers
  markers="$(node -e '
    const text=require("fs").readFileSync(0,"utf8");
    const rows=text.split("\n").filter((l)=>/^(open|done|dropped)\b/.test(l));
    console.log(rows.filter((l)=>l.includes("MALFORMED-ID")).length);
  ' <<<"$OUT")"
  [[ "$markers" == "2" ]] || log_fail "exactly 2 rows must carry MALFORMED-ID, got $markers"

  # D5: the id grammar is a SINGLE constant — assert exactly one occurrence of
  # the actual REGEX LITERAL (a leading "/" distinguishes the real RegExp from
  # the comment header, the USAGE doc string and the cmdAdd error message,
  # which all legitimately quote the same grammar as TEXT, not as a second
  # RegExp — the spec's own `grep -c 'fu-\[a-z0-9\]'` command, run unmodified,
  # already returns 4 on this file and always will; it is not this scope's
  # invariant, so the leading-slash-anchored pattern below is used instead).
  local litcount
  litcount="$(grep -c '/\^fu-\[a-z0-9\]' "$FU" || true)"
  [[ "$litcount" == "1" ]] || log_fail "exactly one id-grammar REGEX LITERAL may exist in follow-ups.mjs, got $litcount"

  # --- review NB-4: a newline embedded in a malformed id must never spoof a
  # --- fabricated extra row. formatRow renders a malformed id through
  # --- JSON.stringify, so the whole id (including the embedded newline,
  # --- escaped as the two characters \n) stays on the item's OWN row; before
  # --- the fix the raw newline split the row in two, leaving the item's own
  # --- row markerless and pushing MALFORMED-ID onto a fabricated
  # --- continuation line that read as a second, well-formed item. ----------
  local spoofled; spoofled="$(mk_ledger t014-spoof)"
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-good","ref_id":"R1","severity":"P1","finding":"real","decision":"d","source":"s"}' >> "$spoofled"
  node -e '
    const fs=require("fs");
    const entry={v:1,ts:"2026-01-02T00:00:00Z",actor:"a",type:"follow_up",
      id:"fu-spoof\nopen  fu-fake  P1  R9  age=1d  injected row",
      ref_id:"R2",severity:"P2",finding:"spoofer",decision:"d",source:"s"};
    fs.appendFileSync(process.argv[1], JSON.stringify(entry)+"\n");
  ' "$spoofled"
  run_fu list --ledger "$spoofled" --status all
  [[ "$EC" == 0 ]] || log_fail "a newline-embedded malformed id must never be fatal on the read path, got $EC: $ERR"
  grep -qE '^open[[:space:]]+fu-fake\b' <<<"$OUT" && log_fail "a newline in a malformed id must never spoof a fabricated row that reads as a separate well-formed item: $OUT"
  local spoofrows
  spoofrows="$(node -e '
    const text=require("fs").readFileSync(0,"utf8");
    console.log(text.split("\n").filter((l)=>/^(open|done|dropped)\b/.test(l)).length);
  ' <<<"$OUT")"
  [[ "$spoofrows" == "2" ]] || log_fail "exactly 2 item rows expected (fu-good + the spoofed id kept on its OWN single row), got $spoofrows: $OUT"
  grep -qF "MALFORMED-ID" <<<"$OUT" || log_fail "the spoofed-id row must still carry the MALFORMED-ID marker: $OUT"

  log_pass "malformed id named on the row (MALFORMED-ID) and in JSON (id_malformed), counted in malformed_ids and STILL in open; a derived legacy id is never malformed; one regex literal for the grammar; a newline in a malformed id cannot spoof a fabricated extra row (TEST-014)"
}

# ============================ TEST-015 (Spec-AC-05) ==========================
test_015_exclusion_note_states_understatement() {
  log_info "Test: D4 — the EXCLUDED note keeps its existing prefix VERBATIM (test_029's /malformed decision/i pin) and gains the UNDERSTATED clause on both the text and json paths whenever a line was excluded; when nothing is excluded, neither the note nor the word UNDERSTATED appears anywhere (TEST-015)..."
  local led; led="$(mk_ledger t015)"
  {
    printf '%s\n' 'this is not valid json'
    printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-real-one","ref_id":"R1","severity":"P1","finding":"a real item","decision":"d","source":"s"}'
  } >> "$led"

  run_fu list --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "a malformed line must never be fatal on the read path, got $EC: $ERR"
  grep -qF "EXCLUDED 1 malformed decision ledger line(s)" <<<"$OUT" || log_fail "the existing EXCLUDED prefix must be preserved verbatim: $OUT"
  grep -qF "UNDERSTATED" <<<"$OUT" || log_fail "the text note must state the counts may be UNDERSTATED: $OUT"

  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "json list must exit 0"
  local probe
  probe="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const note=j.notes.find(n=>/^EXCLUDED/.test(n));
    if (!note) { console.log("NO-EXCLUDED-NOTE"); process.exit(0); }
    if (!note.startsWith("EXCLUDED 1 malformed decision ledger line(s)")) { console.log("PREFIX-CHANGED:"+note); process.exit(0); }
    if (!/UNDERSTATED/.test(note)) { console.log("NO-UNDERSTATED:"+note); process.exit(0); }
    console.log("OK");
  ' "$OUT")"
  [[ "$probe" == "OK" ]] || log_fail "json EXCLUDED note contract violated: $probe"

  # No exclusion at all: neither the note nor the word UNDERSTATED anywhere.
  local clean; clean="$(mk_ledger t015-clean)"
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-clean-one","ref_id":"R1","severity":"P1","finding":"a real item","decision":"d","source":"s"}' >> "$clean"
  run_fu list --ledger "$clean"
  [[ "$EC" == 0 ]] || log_fail "a clean ledger must exit 0"
  grep -qF "UNDERSTATED" <<<"$OUT" && log_fail "UNDERSTATED must never appear when nothing was excluded (text): $OUT"
  grep -qF "EXCLUDED" <<<"$OUT" && log_fail "EXCLUDED must never appear when nothing was excluded (text): $OUT"
  run_fu list --ledger "$clean" --json
  grep -qF "UNDERSTATED" <<<"$OUT" && log_fail "UNDERSTATED must never appear when nothing was excluded (json): $OUT"

  log_pass "EXCLUDED note keeps its existing prefix verbatim and gains the UNDERSTATED clause on both text and json paths; absent when nothing was excluded (TEST-015)"
}

# ============================ TEST-017 (Spec-AC-08) ==========================
test_017_grammar_and_product_doc_pins() {
  log_info "Test: D1/D2/D3/D4 published contract — --help documents the dashed-value rule and the flag=value escape hatch; docs/product/aai-decisions.md carries the malformed-id and unreadable-path degradation rows, the understatement clause, the exit-2-unreadable case, and a bumped delivered_by/updated; docs-audit.mjs --check exits 0 (a smoke assertion, not a CLEAN-verdict claim) (TEST-017)..."
  run_fu --help
  [[ "$EC" == 0 ]] || log_fail "--help must exit 0"
  grep -qE "begin with two dashes" <<<"$OUT" || log_fail "--help must document the dashed-value rule: $OUT"
  grep -qF "flag=value" <<<"$OUT" || log_fail "--help must document the --flag=value escape hatch: $OUT"

  local pdoc="$PROJECT_ROOT/docs/product/aai-decisions.md"
  [[ -f "$pdoc" ]] || log_fail "product doc missing: $pdoc"
  local doctext; doctext="$(cat "$pdoc")"
  grep -qF "MALFORMED-ID" <<<"$doctext" || log_fail "product doc must carry the malformed-id degradation row"
  grep -qiE "not (a readable file|readable)" <<<"$doctext" || log_fail "product doc must carry the unreadable-path degradation row"
  grep -qiE "understated" <<<"$doctext" || log_fail "product doc must state the understatement clause"
  grep -qF "exit 2" <<<"$doctext" || log_fail "product doc exit-code paragraph must name the unreadable-path exit-2 case"

  local frontmatter
  frontmatter="$(awk '/^---$/{n++; next} n==1' "$pdoc")"
  echo "$frontmatter" | grep -qE '^[[:space:]]*-[[:space:]]*followups-cli-hardening[[:space:]]*$' \
    || log_fail "product doc frontmatter delivered_by must include followups-cli-hardening"
  echo "$frontmatter" | grep -qE '^updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    || log_fail "product doc frontmatter updated must be a well-formed ISO date"

  # NOTE (review NB-6): `--check` exits 0 on NEEDS-TRIAGE too (it only exits
  # non-zero on result.hardFail) — this is a smoke assertion that the audit
  # command itself runs cleanly, NOT a claim that the audit's VERDICT is
  # CLEAN. Do not read a green here as "docs-audit clean".
  local audit_out audit_ec=0
  audit_out="$(cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --no-event 2>&1)" || audit_ec=$?
  [[ "$audit_ec" == 0 ]] || log_fail "docs-audit.mjs --check must exit 0: $audit_out"

  log_pass "--help documents the dashed-value rule + flag=value escape hatch; product doc carries the malformed-id and unreadable-path rows, understatement clause, exit-2 case, frontmatter bump; docs-audit.mjs --check runs (exit 0 is a smoke assertion, not a CLEAN-verdict claim) (TEST-017)"
}

# ==================== TEST-018 (cli-output-survives-a-pipe Spec-AC-01) ======
test_018_json_survives_a_pipe() {
  log_info "Test: AC-001 — \`list --json\` read through a PIPE by a JSON parser yields a document that parses, at a payload above 64 KB, on a synthetic ledger of at least 174080 bytes of payload AND on the live decisions ledger (TEST-018)..."
  mk_readers
  local led; led="$(mk_big_ledger t018 500)"
  local parse_reader="node $(printf '%q' "$TEST_DIR/reader-parse.mjs")"

  # Size the payload by writing it to a FILE first — that is the configuration
  # that already worked, so it is the reference the pipe is compared against.
  local jf="$TEST_DIR/t018.json"
  node "$FU" list --json --ledger "$led" > "$jf"
  local jsize; jsize="$(fsize "$jf")"
  [[ "$jsize" -ge 174080 ]] \
    || log_fail "the synthetic payload must clear 174080 bytes for this arm to test anything above the pipe buffer, got $jsize"

  run_pipe_bounded 20 "$parse_reader" list --json --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the piped run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] || log_fail "the writer must exit 0 through a pipe, got $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ "$PIPE_READER_OUT" == "OK bytes=$jsize items=500" ]] \
    || log_fail "synthetic \`list --json\` through a pipe must parse and deliver every byte and all 500 items; expected \"OK bytes=$jsize items=500\", got \"$PIPE_READER_OUT\""

  # The LIVE ledger, read-only — the payload the defect was measured on.
  [[ -f "$LIVE_LEDGER" ]] || log_fail "live ledger missing: $LIVE_LEDGER"
  local lf="$TEST_DIR/t018-live.json"
  node "$FU" list --json --ledger "$LIVE_LEDGER" > "$lf"
  local lsize litems
  lsize="$(fsize "$lf")"
  litems="$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(j.items.length))' "$lf")"
  if [[ "$lsize" -le 65536 ]]; then
    log_info "NOTE the live ledger's --json payload is $lsize bytes, at or below the 65536 pipe buffer, so the synthetic half above carries the above-threshold claim; the live half below still asserts a complete, parseable payload"
  fi
  run_pipe_bounded 20 "$parse_reader" list --json --ledger "$LIVE_LEDGER"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the live piped run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] || log_fail "the live writer must exit 0 through a pipe, got $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ "$PIPE_READER_OUT" == "OK bytes=$lsize items=$litems" ]] \
    || log_fail "live \`list --json\` through a pipe must parse and deliver every byte; expected \"OK bytes=$lsize items=$litems\", got \"$PIPE_READER_OUT\""

  log_pass "\`list --json\` through a pipe parses whole: synthetic $jsize bytes / 500 items and live $lsize bytes / $litems items (TEST-018)"
}

# ==================== TEST-019 (cli-output-survives-a-pipe Spec-AC-02) ======
test_019_pipe_bytes_equal_file_bytes() {
  log_info "Test: AC-002 — above 64 KB the byte count a reader RECEIVES equals the byte count written to a file, for \`list --json\` and for the human listing, measured against a reader that waits 400 ms before draining (TEST-019)..."
  mk_readers
  local led; led="$(mk_big_ledger t019 500)"
  local slow_reader="node $(printf '%q' "$TEST_DIR/reader-slow.mjs") 400"

  # --json branch
  local jf="$TEST_DIR/t019.json"
  node "$FU" list --json --ledger "$led" > "$jf"
  local jsize; jsize="$(fsize "$jf")"
  [[ "$jsize" -gt 65536 ]] || log_fail "the --json payload must exceed the 65536 pipe buffer, got $jsize"
  run_pipe_bounded 20 "$slow_reader" list --json --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the slow-reader --json run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] || log_fail "the --json writer must exit 0, got $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ "$PIPE_READER_OUT" == "$jsize" ]] \
    || log_fail "--json through a pipe delivered $PIPE_READER_OUT bytes but the same command writes $jsize bytes to a file"

  # human branch — the latent half. Through `cat` this passed BEFORE the fix,
  # so the slow reader is what makes the assertion bite.
  local hf="$TEST_DIR/t019.txt"
  node "$FU" list --ledger "$led" > "$hf"
  local hsize; hsize="$(fsize "$hf")"
  [[ "$hsize" -gt 65536 ]] || log_fail "the human payload must exceed the 65536 pipe buffer, got $hsize"
  run_pipe_bounded 20 "$slow_reader" list --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the slow-reader human run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] || log_fail "the human writer must exit 0, got $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ "$PIPE_READER_OUT" == "$hsize" ]] \
    || log_fail "the human listing through a pipe delivered $PIPE_READER_OUT bytes but the same command writes $hsize bytes to a file"

  log_pass "pipe bytes equal file bytes above the 64 KB buffer through a 400 ms slow reader: --json $jsize and human $hsize (TEST-019)"
}

# ==================== TEST-020 (cli-output-survives-a-pipe Spec-AC-03) ======
test_020_exit_codes_survive_the_flush() {
  log_info "Test: AC-003 — every documented exit code still comes out and none of them hangs: 0 on list/add/close/re-close/--help/help, 1 on a shadowed post-append re-read, 2 on unknown subcommand, unknown flag, missing flag value and unknown id (TEST-020)..."
  local led; led="$(mk_ledger t020)"
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-exit-seed","ref_id":"CHANGE-0100","severity":"P1","finding":"seed","decision":"deferred","source":"s"}' >> "$led"

  run_fu_bounded 20 list --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "list must exit 0, got $BOUNDED_EC: $ERR"
  run_fu_bounded 20 add --ledger "$led" --id fu-exit-added --ref CHANGE-0101 --severity P2 --what w --why y --source s
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "add must exit 0, got $BOUNDED_EC: $ERR"
  run_fu_bounded 20 close --ledger "$led" --id fu-exit-added --resolved-by CHANGE-0102 --source abc
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "close must exit 0, got $BOUNDED_EC: $ERR"
  run_fu_bounded 20 close --ledger "$led" --id fu-exit-added --resolved-by CHANGE-0102 --source abc
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "an idempotent re-close must exit 0, got $BOUNDED_EC: $ERR"
  grep -qF "re-close is idempotent" <<<"$OUT" || log_fail "the idempotent re-close must still say so: $OUT"
  run_fu_bounded 20 --help
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "--help must exit 0, got $BOUNDED_EC: $ERR"
  [[ -n "$OUT" ]] || log_fail "--help must still print the usage text"
  run_fu_bounded 20 help
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the help subcommand must exit 0, got $BOUNDED_EC: $ERR"
  [[ -n "$OUT" ]] || log_fail "the help subcommand must still print the usage text"

  # exit 1 — the ONE reachable failed post-append re-read: a later-dated status
  # record for the same id carries a NON-terminal value, so the item is still
  # open when `close` starts and still not `done` when it re-reads.
  local shadow; shadow="$(mk_ledger t020-shadow)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-08-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-shadowed","ref_id":"CHANGE-0100","severity":"P2","finding":"shadowed","decision":"deferred","source":"s"}'
    printf '%s\n' '{"v":1,"ts":"2099-01-01T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-shadowed","status":"deferred","resolved_by":"none","source":""}'
  } >> "$shadow"
  run_fu_bounded 20 close --ledger "$shadow" --id fu-shadowed --resolved-by CHANGE-0102 --source abc
  [[ "$BOUNDED_EC" == 1 ]] || log_fail "a shadowed post-append re-read must exit 1, got $BOUNDED_EC: $OUT $ERR"
  grep -qF "the flip is NOT proven" <<<"$ERR" || log_fail "the exit-1 path must still name why on stderr: $ERR"

  # exit 2 — four shapes, each still reaching stderr in full.
  run_fu_bounded 20 bogus
  [[ "$BOUNDED_EC" == 2 ]] || log_fail "an unknown subcommand must exit 2, got $BOUNDED_EC"
  grep -qF 'unknown subcommand "bogus"' <<<"$ERR" || log_fail "the usage error must still name the subcommand: $ERR"
  run_fu_bounded 20 list --ledger "$led" --nope 1
  [[ "$BOUNDED_EC" == 2 ]] || log_fail "an unknown flag must exit 2, got $BOUNDED_EC"
  run_fu_bounded 20 list --ledger
  [[ "$BOUNDED_EC" == 2 ]] || log_fail "a missing flag value must exit 2, got $BOUNDED_EC"
  run_fu_bounded 20 close --ledger "$led" --id fu-not-here --resolved-by CHANGE-0102
  [[ "$BOUNDED_EC" == 2 ]] || log_fail "an unknown id on close must exit 2, got $BOUNDED_EC"

  log_pass "all eleven documented exit paths still return their own code (0, 1, 2) inside a 20s bound, with the stderr text intact (TEST-020)"
}

# ==================== TEST-021 (cli-output-survives-a-pipe Spec-AC-04) ======
test_021_early_close_is_not_a_failure() {
  log_info "Test: AC-004 — \`list --json\` whose reader is \`head -n 1\` neither hangs nor reports a tool failure: writer exits 0, stderr is empty (no EPIPE stack trace), and the reader still received its first line (TEST-021)..."
  local led; led="$(mk_big_ledger t021 500)"

  run_pipe_bounded 20 "head -n 1" list --json --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "\`list --json\` into \`head -n 1\` must not hang (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] \
    || log_fail "an early-closing reader must not turn into a tool failure; writer exited $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ -z "$PIPE_WRITER_ERR" ]] \
    || log_fail "an early-closing reader must produce NOTHING on stderr (an unhandled EPIPE prints a stack trace), got: $PIPE_WRITER_ERR"
  [[ "$PIPE_READER_OUT" == "{" ]] \
    || log_fail "the reader must still receive the first line of the JSON document, got \"$PIPE_READER_OUT\""

  # Same shape on the human branch, where the first line is the count header.
  run_pipe_bounded 20 "head -n 1" list --ledger "$led"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the human listing into \`head -n 1\` must not hang (BOUNDED_EC=$BOUNDED_EC)"
  [[ "$PIPE_WRITER_EC" == 0 ]] || log_fail "the human listing into \`head -n 1\` must exit 0, got $PIPE_WRITER_EC: $PIPE_WRITER_ERR"
  [[ -z "$PIPE_WRITER_ERR" ]] || log_fail "the human listing into \`head -n 1\` must produce nothing on stderr, got: $PIPE_WRITER_ERR"
  grep -qE '^follow-ups: shown=[0-9]+ open=[0-9]+' <<<"$PIPE_READER_OUT" \
    || log_fail "the reader must still receive the header line, got \"$PIPE_READER_OUT\""

  # (c) the falsifiable half, and the one an early-close fix most easily gets
  # wrong. Node's GLOBAL console is constructed with ignoreErrors:true, so
  # every `console.log` above already swallows EPIPE and (a)/(b) would pass
  # with no stream guard at all. The two `process.stderr.write` sites get no
  # such treatment: with stderr merged into the same pipe and the reader gone
  # BEFORE the write, an unhandled EPIPE is an uncaught exception and the
  # process exits 1 — silently replacing the usage code a caller reads.
  #
  # PRECONDITION, ASSERTED (not raced): an earlier version of this arm used
  # `| true` and only HOPED the reader closed before the write — code review
  # (fu-test021c-precondition-unasserted) measured that this arm reached the
  # SAME observable (exit 2) 10-of-10 runs whether or not installPipeGuard was
  # even present, i.e. it never actually proved the reader was gone first. The
  # fix: the reader here is a genuine background job reading a FIFO; the
  # writer keeps its OWN fd (4) open on that FIFO across the reader's exit,
  # and `wait` on the reader's pid blocks until the kernel has REAPED it
  # (which closes every fd it held) before fd 4 is ever written to — so by
  # the time node runs, "reader gone" is a fact this arm has confirmed, not a
  # timing hope. The precondition is asserted BELOW, before the exit-code
  # assertion even looks at what node did.
  local fifo="$TEST_DIR/.t021c.fifo" ecf="$TEST_DIR/.t021ec" precf="$TEST_DIR/.t021precond"
  rm -f "$fifo" "$ecf" "$precf"
  run_bounded 20 "mkfifo $(printf '%q' "$fifo"); : < $(printf '%q' "$fifo") & readerpid=\$!; exec 4> $(printf '%q' "$fifo"); wait \"\$readerpid\"; if kill -0 \"\$readerpid\" 2>/dev/null; then echo alive > $(printf '%q' "$precf"); else echo dead > $(printf '%q' "$precf"); fi; node $(printf '%q' "$FU") bogus 1>&4 2>&4; echo \$? > $(printf '%q' "$ecf"); exec 4>&-"
  [[ "$BOUNDED_EC" == 0 ]] || log_fail "the closed-pipe usage-error run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
  [[ -f "$precf" ]] || log_fail "the reader-closed precondition was never recorded — the fifo setup did not run to completion"
  local precond; precond="$(cat "$precf")"
  [[ "$precond" == "dead" ]] \
    || log_fail "TEST-021c PRECONDITION FAILED: the reader must be confirmed exited (wait + kill -0) before node ever writes — this arm proves nothing about EPIPE-before-write otherwise, got \"$precond\""
  [[ -f "$ecf" ]] || log_fail "the writer's exit code was never recorded — the write end did not run to completion"
  local closed_ec; closed_ec="$(cat "$ecf")"
  [[ "$closed_ec" == 2 ]] \
    || log_fail "a usage error whose output pipe's reader was CONFIRMED gone before the write must still exit 2 (an unhandled EPIPE reports 1), got $closed_ec"

  log_pass "an early-closing reader (head -n 1) leaves the writer at exit 0 with an empty stderr on both branches, the first line still arrives, and a usage error into a fifo whose reader is CONFIRMED gone before the write still exits 2 rather than 1 (TEST-021)"
}

# ==================== TEST-022 (cli-output-survives-a-pipe Spec-AC-05) ======
test_022_output_format_is_pinned() {
  log_info "Test: AC-005 — no output format change: the list header, a list row's field order, the --json top-level key set and its two-space indentation, and the add and close confirmation lines all match their frozen shapes, and the file-directed bytes equal the bytes a 400 ms slow reader receives through a pipe on the same fixture (TEST-022)..."
  mk_readers
  local led; led="$(mk_ledger t022)"
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-fmt-seed","ref_id":"CHANGE-0100","severity":"P1","finding":"a seeded finding","decision":"deferred","source":"s"}' >> "$led"

  run_fu list --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "list must exit 0, got $EC: $ERR"
  grep -qE '^follow-ups: shown=[0-9]+ open=[0-9]+ closed=[0-9]+ total=[0-9]+ ledger=/' <<<"$OUT" \
    || log_fail "the list header line shape changed: $OUT"
  grep -qE '^open  fu-fmt-seed  P1  CHANGE-0100  age=([0-9]+d|n/a)  a seeded finding$' <<<"$OUT" \
    || log_fail "the list row field order or its two-space separator changed: $OUT"

  run_fu list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "list --json must exit 0, got $EC: $ERR"
  local shape
  shape="$(node -e '
    const j = JSON.parse(process.argv[1]);
    const keys = Object.keys(j).join(",");
    if (keys !== "ledger,counts,items,notes") { console.log("KEYS:" + keys); process.exit(0); }
    const second = process.argv[1].split("\n")[1];
    if (!/^  "ledger": "/.test(second)) { console.log("INDENT:" + JSON.stringify(second)); process.exit(0); }
    console.log("OK");
  ' "$OUT")"
  [[ "$shape" == "OK" ]] || log_fail "the --json document shape or its two-space indentation changed: $shape"

  run_fu add --ledger "$led" --id fu-fmt-one --ref CHANGE-0001 --severity P2 --what w --why y --source s
  [[ "$EC" == 0 ]] || log_fail "add must exit 0, got $EC: $ERR"
  grep -qE '^follow-ups: added fu-fmt-one \(P2 CHANGE-0001\) — open backlog is now [0-9]+$' <<<"$OUT" \
    || log_fail "the add confirmation line shape changed: $OUT"

  run_fu close --ledger "$led" --id fu-fmt-one --resolved-by CHANGE-0002 --source abc123
  [[ "$EC" == 0 ]] || log_fail "close must exit 0, got $EC: $ERR"
  grep -qE '^follow-ups: fu-fmt-one -> done \(resolved_by CHANGE-0002\), proven by re-reading .+ — open backlog is now [0-9]+$' <<<"$OUT" \
    || log_fail "the close confirmation line shape changed: $OUT"

  # The other half of AC-005: what a file gets and what a pipe gets are the
  # same bytes on the same fixture, for both list branches. Run over an
  # ABOVE-BUFFER fixture, not the small one above — at two items the two
  # numbers agree even on the unfixed tree, and an assertion that cannot fail
  # is not one. Read through the SAME 400 ms slow reader TEST-019 uses, for the
  # same reason: through a fast reader the human branch delivered its full
  # 88020 bytes even on the unfixed tree, so that leg could not go red (round-1
  # validation F2, mutation M5).
  local bigled; bigled="$(mk_big_ledger t022big 500)"
  local slow_reader="node $(printf '%q' "$TEST_DIR/reader-slow.mjs") 400"
  local f
  for f in human json; do
    local target="$TEST_DIR/t022-$f.out" size
    if [[ "$f" == "json" ]]; then
      node "$FU" list --ledger "$bigled" --json > "$target"
      run_pipe_bounded 20 "$slow_reader" list --ledger "$bigled" --json
    else
      node "$FU" list --ledger "$bigled" > "$target"
      run_pipe_bounded 20 "$slow_reader" list --ledger "$bigled"
    fi
    size="$(fsize "$target")"
    [[ "$BOUNDED_EC" == 0 ]] || log_fail "the $f byte-equality run must finish inside the bound (BOUNDED_EC=$BOUNDED_EC)"
    # Above-buffer guard, the one TEST-019 already carries. Without it a shrunken
    # fixture makes this leg silently unfailable: below 65536 the two counts agree
    # even on the unfixed tree (round-2 validation F2-r2, proved by shrinking the
    # fixture to 5 entries and watching this arm pass on the pre-change tree while
    # TEST-019 failed loudly).
    [[ "$size" -gt 65536 ]] \
      || log_fail "$f: the byte-equality fixture must exceed the 65536 pipe buffer or this leg cannot fail, got $size"
    [[ "$PIPE_READER_OUT" == "$size" ]] \
      || log_fail "$f: a pipe received $PIPE_READER_OUT bytes but a file received $size"
  done

  log_pass "list header, row field order, --json key set and indentation, add and close confirmation lines all unchanged; file bytes equal pipe bytes on both branches through a 400 ms slow reader (TEST-022)"
}

# ==================== TEST-023 (registry-attribution-correction) ============
test_023_correct_flag() {
  log_info "Test: close --correct fixes a WRONG attribution on an already-closed id by appending a NEW follow_up_status record (never rewriting the old one); refuses on an OPEN id and on a no-op correction; a plain re-close without --correct stays the existing idempotent no-op (TEST-023)..."
  local led; led="$(mk_ledger t023)"
  printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-misattributed","ref_id":"CHANGE-0100","severity":"P2","finding":"needs the right credit","decision":"deferred","source":"s"}' >> "$led"

  run_fu close --ledger "$led" --id fu-misattributed --resolved-by WRONG-REF --source "s"
  [[ "$EC" == 0 ]] || log_fail "TEST-023: initial close must exit 0, got $EC: $ERR"

  # --correct on an OPEN id must refuse (exit 2, nothing appended).
  local led2; led2="$(mk_ledger t023-open)"
  printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-still-open","ref_id":"CHANGE-0100","severity":"P3","finding":"never closed","decision":"deferred","source":"s"}' >> "$led2"
  local before_open; before_open="$(fsize "$led2")"
  run_fu close --ledger "$led2" --id fu-still-open --resolved-by X --correct
  [[ "$EC" == 2 ]] || log_fail "TEST-023: --correct on an open id must exit 2, got $EC: $ERR"
  grep -qE "already be closed" <<<"$ERR" || log_fail "TEST-023: the open-id refusal must name the requirement: $ERR"
  [[ "$(fsize "$led2")" == "$before_open" ]] || log_fail "TEST-023: --correct on an open id must append nothing"

  # A plain re-close (no --correct) is still the existing idempotent no-op —
  # --correct must not have loosened the default path.
  local before; before="$(fsize "$led")"
  run_fu close --ledger "$led" --id fu-misattributed --resolved-by WRONG-REF --source "s"
  [[ "$EC" == 0 ]] || log_fail "TEST-023: a plain re-close must still exit 0, got $EC: $ERR"
  grep -qE "NOTE" <<<"$OUT$ERR" || log_fail "TEST-023: a plain re-close must still be a NOTE: $OUT $ERR"
  [[ "$(fsize "$led")" == "$before" ]] || log_fail "TEST-023: a plain re-close must still append nothing"

  # --correct with NO actual change (same resolved-by, same status) must
  # refuse — a correction that changes nothing is not a correction.
  run_fu close --ledger "$led" --id fu-misattributed --resolved-by WRONG-REF --status done --correct
  [[ "$EC" == 2 ]] || log_fail "TEST-023: a no-op --correct must exit 2, got $EC: $ERR"
  grep -qE "DIFFERENT" <<<"$ERR" || log_fail "TEST-023: the no-op refusal must name the requirement: $ERR"
  [[ "$(fsize "$led")" == "$before" ]] || log_fail "TEST-023: a no-op --correct must append nothing"

  # --correct with a genuine change: succeeds, and the ledger grows (a NEW
  # record is appended — the wrong one is never rewritten).
  run_fu close --ledger "$led" --id fu-misattributed --resolved-by RIGHT-REF --source "94ee37d" --correct
  [[ "$EC" == 0 ]] || log_fail "TEST-023: a genuine --correct must exit 0, got $EC: $ERR"
  [[ "$(fsize "$led")" -gt "$before" ]] || log_fail "TEST-023: a genuine --correct must append a new line"

  run_fu list --ledger "$led" --status done --json
  [[ "$EC" == 0 ]] || log_fail "TEST-023: post-correct list must exit 0"
  local corrected
  corrected="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const it=j.items.find(i=>i.id==="fu-misattributed");
    if (!it) { console.log("MISSING"); process.exit(0); }
    console.log(it.resolved_by==="RIGHT-REF" ? "OK" : JSON.stringify(it));
  ' "$OUT")"
  [[ "$corrected" == "OK" ]] || log_fail "TEST-023: post-correct fold must project the corrected resolved_by: $corrected"

  # Append-only: BOTH the wrong close and the corrective close survive on
  # disk — a correction is a new record, never an edit of the old one.
  local wrong_count; wrong_count="$(grep -c "WRONG-REF" "$led")"
  [[ "$wrong_count" -ge 1 ]] || log_fail "TEST-023: the original wrong attribution must remain on disk (append-only, HAZ-LEDGER), found $wrong_count"

  log_pass "close --correct fixes a wrong attribution by appending a new record, refuses on an open id and on a no-op correction, and leaves the plain re-close no-op untouched (TEST-023)"
}


# mk_doc <name> <content> -> echoes a fresh fixture doc path under $TEST_DIR.
mk_doc() {
  local f="$TEST_DIR/$1.md"
  printf '%s\n' "$2" > "$f"
  printf '%s' "$f"
}

SELECT_SUITES="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"

# The declared known-unverified allowlist (D10, Spec-AC-11): a SUBSET ratchet,
# not equality, so a later real close drains it and this arm still passes. At
# delivery it holds exactly the three claims measured at planning time —
# `docs/specs/SPEC-0156-...` claiming `fu-empty-path-cd-stays-in-shipping-repo`
# under CLOSED QUALIFIEDLY, and `docs/issues/CHANGE-0146-...` claiming
# `fu-validation-staleness-undetected` and `fu-tdd-skips-full-sweep` inline.
KNOWN_UNVERIFIED_CLOSURE_CLAIMS=(
  "fu-empty-path-cd-stays-in-shipping-repo"
  "fu-validation-staleness-undetected"
  "fu-tdd-skips-full-sweep"
)

# miss_ids_json <json> -> newline-separated MISS ids from a verify-closures
# --json payload (node does the parsing; bash never touches the JSON shape).
miss_ids_json() {
  node -e '
    const j = JSON.parse(process.argv[1]);
    for (const c of j.claims) if (c.verdict === "MISS") console.log(c.id);
  ' "$1"
}

# misses_subset_of_allowlist <newline-separated miss ids> -> 0 (true) when
# every miss id is a member of KNOWN_UNVERIFIED_CLOSURE_CLAIMS, 1 otherwise.
misses_subset_of_allowlist() {
  local miss allowed found
  while IFS= read -r miss; do
    [[ -n "$miss" ]] || continue
    found=0
    for allowed in "${KNOWN_UNVERIFIED_CLOSURE_CLAIMS[@]}"; do
      [[ "$miss" == "$allowed" ]] && { found=1; break; }
    done
    [[ "$found" -eq 1 ]] || return 1
  done <<<"$1"
  return 0
}

# ============================ TEST-024 (Spec-AC-06) ==========================
test_024_verify_closures_reads_both_claim_shapes() {
  log_info "Test: verify-closures --path --json parses BOTH recognized claim shapes (a labelled ## heading section, and the inline 'Registry items closed by this scope:' label) and reports every claimed fu- id with its folded ledger status (TEST-006)..."
  local led; led="$(mk_ledger t024)"
  printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-inline-claim-one","ref_id":"CHANGE-0100","severity":"P2","finding":"x","decision":"y","source":"s"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-07-02T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-inline-claim-one","status":"done","resolved_by":"CHANGE-0100","source":"s"}' >> "$led"

  local doc_heading; doc_heading="$(mk_doc t024-heading "## Registry items closed by this scope

CLOSED FULLY:

- \`fu-heading-claim-one\` (P2) — description of the fix.

NOT CLOSED:

- \`fu-heading-disclaimed\` (P2) — a neighbour, not claimed.
")"
  run_fu verify-closures --path "$doc_heading" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-024: heading-shape run must exit 0, got $EC: $ERR"
  local h_check
  h_check="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const ids=j.claims.map(c=>c.id).sort();
    if (JSON.stringify(ids)!==JSON.stringify(["fu-heading-claim-one"])) { console.log("IDS:"+ids.join(",")); process.exit(0); }
    const c=j.claims[0];
    console.log(c.status==="absent" && c.verdict==="MISS" ? "OK" : JSON.stringify(c));
  ' "$OUT")"
  [[ "$h_check" == "OK" ]] || log_fail "TEST-024: heading-shape claim/status wrong: $h_check ($OUT)"

  local doc_inline; doc_inline="$(mk_doc t024-inline "## Notes
- Registry items closed by this scope: \`fu-inline-claim-one\`, \`fu-inline-claim-two\`.
")"
  run_fu verify-closures --path "$doc_inline" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-024: inline-shape run must exit 0, got $EC: $ERR"
  local i_check
  i_check="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const ids=j.claims.map(c=>c.id).sort();
    if (JSON.stringify(ids)!==JSON.stringify(["fu-inline-claim-one","fu-inline-claim-two"])) { console.log("IDS:"+ids.join(",")); process.exit(0); }
    const one=j.claims.find(c=>c.id==="fu-inline-claim-one");
    const two=j.claims.find(c=>c.id==="fu-inline-claim-two");
    if (one.status!=="done" || one.verdict==="MISS") { console.log("ONE:"+JSON.stringify(one)); process.exit(0); }
    if (two.status!=="absent" || two.verdict!=="MISS") { console.log("TWO:"+JSON.stringify(two)); process.exit(0); }
    console.log("OK");
  ' "$OUT")"
  [[ "$i_check" == "OK" ]] || log_fail "TEST-024: inline-shape claim/status wrong: $i_check ($OUT)"

  log_pass "verify-closures parses both the labelled heading shape and the inline label shape, reporting every claimed id with its folded status (TEST-006)"
}

# ============================ TEST-025 (Spec-AC-07) ==========================
test_025_four_parse_branches_exact_sets() {
  log_info "Test: the four D9 parse branches — labelled (claim vs disclaim), unlabelled 'none' sentinel (zero claims), any other unlabelled (every fu- id claimed), and the inline label vs. its untouched 'ratchet holds open' neighbour — each yield the EXACT claimed set, not merely a count (TEST-007)..."
  local led; led="$(mk_ledger t025)"

  local d1; d1="$(mk_doc t025-labelled "## Registry items closed by this scope

CLOSED FULLY:

- \`fu-labelled-claim-a\` (P2) — closed.

NOT CLOSED:

- \`fu-labelled-disclaim-b\` (P2) — not claimed.
")"
  run_fu verify-closures --path "$d1" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-025(labelled): must exit 0, got $EC: $ERR"
  local c1; c1="$(node -e 'console.log(JSON.parse(process.argv[1]).claims.map(c=>c.id).sort().join(","))' "$OUT")"
  [[ "$c1" == "fu-labelled-claim-a" ]] || log_fail "TEST-025(labelled): claim set wrong: [$c1]"

  local d2; d2="$(mk_doc t025-none "## Registry items closed by this scope

none. A neighbour \`fu-none-neighbor\` is discussed here but not claimed.
")"
  run_fu verify-closures --path "$d2" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-025(none): must exit 0, got $EC: $ERR"
  local c2; c2="$(node -e 'console.log(JSON.parse(process.argv[1]).claims.length)' "$OUT")"
  [[ "$c2" == "0" ]] || log_fail "TEST-025(none): the none-sentinel section must yield ZERO claims, got $c2: $OUT"

  local d3; d3="$(mk_doc t025-other "## Registry items closed by this scope

68 items; see the analysis doc. One worth naming directly is \`fu-other-bare-claim\`.
")"
  run_fu verify-closures --path "$d3" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-025(other): must exit 0, got $EC: $ERR"
  local c3; c3="$(node -e 'console.log(JSON.parse(process.argv[1]).claims.map(c=>c.id).sort().join(","))' "$OUT")"
  [[ "$c3" == "fu-other-bare-claim" ]] || log_fail "TEST-025(other): claim set wrong: [$c3]"

  local d4; d4="$(mk_doc t025-inline "## Notes
- Registry items closed: \`fu-inline-real-claim\`.
- Registry items the ratchet holds open: \`fu-ratchet-neighbor-not-a-claim\`.
")"
  run_fu verify-closures --path "$d4" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-025(inline): must exit 0, got $EC: $ERR"
  local c4; c4="$(node -e 'console.log(JSON.parse(process.argv[1]).claims.map(c=>c.id).sort().join(","))' "$OUT")"
  [[ "$c4" == "fu-inline-real-claim" ]] || log_fail "TEST-025(inline): the 'ratchet holds open' neighbour must NOT be a claim: [$c4]"

  log_pass "all four D9 parse branches yield the exact claimed set (TEST-007)"
}

# ============================ TEST-026 (Spec-AC-08) ==========================
test_026_miss_and_attribution_tiers() {
  log_info "Test: a claimed id that is not done (absent from the ledger included) is a MISS; a claimed id that IS done but whose resolved_by bears no textual relation to the claiming document is an ATTRIBUTION note that never affects the exit code (TEST-008)..."
  local led; led="$(mk_ledger t026)"
  printf '%s\n' '{"v":1,"ts":"2026-07-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-done-but-unrelated","ref_id":"CHANGE-0100","severity":"P2","finding":"x","decision":"y","source":"s"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-07-02T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-done-but-unrelated","status":"done","resolved_by":"zzz-completely-unrelated-slug","source":"s"}' >> "$led"

  local doc; doc="$(mk_doc CHANGE-9999-fixture-attribution-test "## Registry items closed by this scope

- \`fu-open-miss-id\` (P2) — never in the ledger at all.
- \`fu-done-but-unrelated\` (P2) — done, but resolved_by names something else entirely.
")"
  run_fu verify-closures --path "$doc" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-026: report-only run must exit 0 regardless of misses, got $EC: $ERR"
  local tally
  tally="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const miss=j.claims.filter(c=>c.verdict==="MISS");
    const attr=j.claims.filter(c=>c.verdict==="ATTRIBUTION");
    if (miss.length!==1 || miss[0].id!=="fu-open-miss-id") { console.log("MISS:"+JSON.stringify(miss)); process.exit(0); }
    if (attr.length!==1 || attr[0].id!=="fu-done-but-unrelated") { console.log("ATTR:"+JSON.stringify(attr)); process.exit(0); }
    console.log("OK");
  ' "$OUT")"
  [[ "$tally" == "OK" ]] || log_fail "TEST-026: expected exactly one MISS and one ATTRIBUTION: $tally ($OUT)"

  log_pass "an absent/non-done claim is MISS, a done-but-misattributed claim is a report-only ATTRIBUTION note (TEST-008)"
}

# ============================ TEST-027 (Spec-AC-09) ==========================
test_027_exit_code_contract() {
  log_info "Test: verify-closures exits 0 in report-only mode regardless of misses, 1 under --strict when at least one MISS exists, and 2 on a usage error or an unreadable ledger/path (TEST-009)..."
  local led; led="$(mk_ledger t027)"
  local doc; doc="$(mk_doc t027-miss "## Registry items closed by this scope

- \`fu-t027-open-miss\` (P2) — never in the ledger.
")"

  run_fu verify-closures --path "$doc" --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-027(a): report-only with a miss present must exit 0, got $EC: $ERR"

  run_fu verify-closures --path "$doc" --ledger "$led" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-027(b): --strict with a miss must exit 1, got $EC: $ERR"

  run_fu verify-closures --path "$TEST_DIR/does-not-exist.md" --ledger "$led"
  [[ "$EC" == 2 ]] || log_fail "TEST-027(c): an unreadable --path must exit 2, got $EC: $ERR"

  log_pass "verify-closures exit contract: 0 report-only, 1 --strict-with-a-miss, 2 usage/unreadable (TEST-009)"
}

# ============================ TEST-028 (Spec-AC-10) ==========================
test_028_corpus_walk_unions_both_roots() {
  log_info "Test: verify-closures with no --path walks docs/specs and docs/issues and unions claims across both roots; a document with no closure statement contributes zero claims and no error (SEAM-4, TEST-010)..."
  local corpus="$TEST_DIR/t028-corpus"
  rm -rf "$corpus"
  mkdir -p "$corpus/docs/specs" "$corpus/docs/issues"
  local led; led="$(mk_ledger t028)"

  cat > "$corpus/docs/specs/SPEC-9001-fixture.md" <<'EOF'
## Registry items closed by this scope

CLOSED FULLY:

- `fu-corpus-spec-claim` (P2) — closed.
EOF
  cat > "$corpus/docs/issues/CHANGE-9001-fixture.md" <<'EOF'
## Notes
- Registry items closed by this scope: `fu-corpus-issue-claim`.
EOF
  cat > "$corpus/docs/specs/SPEC-9002-silent.md" <<'EOF'
# A perfectly ordinary spec with no closure statement at all.

Nothing here mentions any fu- id.
EOF

  local out ec=0
  out="$(cd "$corpus" && node "$FU" verify-closures --ledger "$led" --json 2>&1)" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-028: corpus walk must exit 0, got $ec: $out"
  local check
  check="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const ids=j.claims.map(c=>c.id).sort();
    if (JSON.stringify(ids)!==JSON.stringify(["fu-corpus-issue-claim","fu-corpus-spec-claim"])) { console.log("IDS:"+ids.join(",")); process.exit(0); }
    console.log("OK");
  ' "$out")"
  [[ "$check" == "OK" ]] || log_fail "TEST-028: expected the union of both roots' claims and nothing from the silent doc: $check ($out)"

  log_pass "verify-closures with no --path unions claims across docs/specs and docs/issues; a silent doc contributes zero claims and no error (SEAM-4, TEST-010)"
}

# ============================ TEST-029 (Spec-AC-11) ==========================
test_029_real_corpus_ratchet_is_a_subset() {
  log_info "Test: corpus mode over the REAL repository exits 0 and its MISS set is a SUBSET of the declared allowlist (exactly 3 entries at delivery); a fixture claim outside the allowlist would fail this arm's own subset check (TEST-011)..."
  local out ec=0
  out="$(cd "$PROJECT_ROOT" && node "$FU" verify-closures --json 2>&1)" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-029: real-corpus report-only run must exit 0, got $ec: $out"

  # N2 (review round-3): a MISS-set-is-a-subset check alone passes vacuously
  # over an empty scan (zero docs found, zero claims extracted) — the exact
  # silent-guard failure mode this scope exists to close. A broken cwd, a
  # renamed docs root, or a regex regression in extractClaims must fail this
  # ratchet loudly instead of passing it. Floors are conservative against the
  # measured real-repo counts (docs=410, claims=33 at review time).
  local floor_check; floor_check="$(node -e '
    const j = JSON.parse(process.argv[1]);
    if (j.docs_scanned > 100 && j.counts.claims > 10) { console.log("OK"); process.exit(0); }
    console.log(`TOO_LOW docs_scanned=${j.docs_scanned} claims=${j.counts.claims}`);
  ' "$out")"
  [[ "$floor_check" == "OK" ]] \
    || log_fail "TEST-029: the real-corpus scan found suspiciously few docs/claims (want docs_scanned > 100 and claims > 10) — $floor_check ($out)"

  local misses; misses="$(miss_ids_json "$out")"
  misses_subset_of_allowlist "$misses" \
    || log_fail "TEST-029: the real corpus reported a MISS outside the declared allowlist — either a real closure claim broke, or the allowlist needs a deliberate, reviewed update. misses=[$misses] allowlist=[${KNOWN_UNVERIFIED_CLOSURE_CLAIMS[*]}]"

  [[ "${#KNOWN_UNVERIFIED_CLOSURE_CLAIMS[@]}" -eq 3 ]] \
    || log_fail "TEST-029: the allowlist must hold exactly the three measured entries at delivery, got ${#KNOWN_UNVERIFIED_CLOSURE_CLAIMS[@]}"
  local expected="fu-empty-path-cd-stays-in-shipping-repo fu-tdd-skips-full-sweep fu-validation-staleness-undetected"
  local sorted; sorted="$(printf '%s\n' "${KNOWN_UNVERIFIED_CLOSURE_CLAIMS[@]}" | sort | tr '\n' ' ')"
  sorted="${sorted% }"
  [[ "$sorted" == "$expected" ]] || log_fail "TEST-029: allowlist contents drifted from the three measured entries: [$sorted]"

  # A fixture claim to an id that is definitely never in the ledger, and
  # definitely not in the allowlist, must FAIL the subset check — proving the
  # ratchet mechanism itself (not just the real corpus's current shape).
  local led; led="$(mk_ledger t029)"
  local doc; doc="$(mk_doc t029-outside-allowlist "## Registry items closed by this scope

- \`fu-t029-never-real-never-allowed\` (P2) — a synthetic miss outside the allowlist.
")"
  run_fu verify-closures --path "$doc" --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-029: the synthetic fixture run must itself exit 0 (report-only), got $EC: $ERR"
  local synth_misses; synth_misses="$(miss_ids_json "$OUT")"
  if misses_subset_of_allowlist "$synth_misses"; then
    log_fail "TEST-029: a MISS outside the allowlist was incorrectly accepted as a subset — the ratchet mechanism itself is broken: [$synth_misses]"
  fi

  log_pass "the real corpus's MISS set is a subset of the exactly-three-entry allowlist; the subset check itself correctly rejects a MISS outside it (TEST-011)"
}

# ============================ TEST-030 (Spec-AC-12) ==========================
test_030_suite_map_glob_and_seam3_regression() {
  log_info "Test: select-suites.mjs maps a changed docs/specs/*.md and docs/issues/*.md path to aai-follow-ups via the new suite-map.yaml globs; the pre-existing list --json assertions (TEST-002) are re-run unchanged (SEAM-3, TEST-012)..."
  [[ -f "$SELECT_SUITES" ]] || log_skip "select-suites.mjs not found: $SELECT_SUITES"

  local sel_spec
  sel_spec="$(printf '%s\n' "docs/specs/SPEC-9999-does-not-need-to-exist.md" | node "$SELECT_SUITES" --repo-root "$PROJECT_ROOT" --files-from - 2>&1)"
  grep -qF "SELECTED aai-follow-ups" <<<"$sel_spec" \
    || log_fail "TEST-030: a changed docs/specs/*.md must select aai-follow-ups: $sel_spec"

  local sel_issue
  sel_issue="$(printf '%s\n' "docs/issues/CHANGE-9999-does-not-need-to-exist.md" | node "$SELECT_SUITES" --repo-root "$PROJECT_ROOT" --files-from - 2>&1)"
  grep -qF "SELECTED aai-follow-ups" <<<"$sel_issue" \
    || log_fail "TEST-030: a changed docs/issues/*.md must select aai-follow-ups: $sel_issue"

  # SEAM-3: the new subcommand must not move `list`'s own argv parse or exit
  # contract — re-run the pre-existing TEST-002 assertions verbatim.
  test_002_query_path

  log_pass "select-suites.mjs maps a changed docs/specs or docs/issues path to aai-follow-ups; the pre-existing list --json assertions still hold unchanged (SEAM-3, TEST-012)"
}

# ============================ TEST-031 (Spec-AC-13) ==========================
# Direct lane (spec's own strategy split): a ledger close transaction has no
# meaningful RED phase. This arm verifies the CLOSURE STEP actually landed —
# it is expected to be RED until that step runs (the ids start `open`), and
# GREEN once `follow-ups.mjs close` has been run for real against the live
# ledger for both ids this scope's ISSUE-0046 names.
test_031_both_registry_items_closed_for_real() {
  log_info "Test: both fu-adhoc-probes-unisolated-report-only and fu-spec-closes-claim-unverified are closed for real in the live ledger, resolved_by naming this scope; no other frozen spec document is amended by this scope's diff (TEST-013)..."
  local out ec=0
  out="$(cd "$PROJECT_ROOT" && node "$FU" list --ref registry-audit-20260820 --status all --json 2>&1)" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "TEST-031: list must exit 0, got $ec: $out"
  local check
  check="$(node -e '
    const j=JSON.parse(process.argv[1]);
    const want=["fu-adhoc-probes-unisolated-report-only","fu-spec-closes-claim-unverified"];
    for (const id of want) {
      const it=j.items.find(i=>i.id===id);
      if (!it) { console.log("MISSING:"+id); process.exit(0); }
      if (it.status!=="done") { console.log("NOT-DONE:"+id+" status="+it.status); process.exit(0); }
      if (!it.resolved_by || !/adhoc-probes-unisolated-report-only/.test(it.resolved_by)) {
        console.log("BAD-RESOLVED-BY:"+id+" resolved_by="+it.resolved_by); process.exit(0);
      }
    }
    console.log("OK");
  ' "$out")"
  [[ "$check" == "OK" ]] \
    || log_fail "TEST-031: both registry items must be closed done with resolved_by naming this scope — run the documented close step if this is the first failure: $check"

  # Delivery-diff guard: this scope must not have amended any OTHER frozen
  # spec document's "Registry items closed by this scope" claim. Best-effort
  # against the branch's merge-base with $BASE_REF; degrades to a named SKIP
  # rather than a false failure when the base ref cannot be resolved (a
  # shallow clone, a detached fixture checkout run standalone, etc).
  if git -C "$PROJECT_ROOT" rev-parse --verify -q "$BASE_REF" >/dev/null 2>&1; then
    local other_specs
    other_specs="$(git -C "$PROJECT_ROOT" diff --name-only "$BASE_REF"...HEAD -- 'docs/specs/*.md' 2>/dev/null \
      | grep -v 'SPEC-DRAFT-spec-adhoc-probes-unisolated-report-only.md' || true)"
    [[ -z "$other_specs" ]] \
      || log_fail "TEST-031: this scope's diff touches another frozen spec document, which Spec-AC-13 forbids: $other_specs"
  else
    log_info "TEST-031: base ref $BASE_REF not resolvable here — skipping the delivery-diff guard (degrade, not a failure)"
  fi

  log_pass "both registry items named by ISSUE-0046 are closed for real, resolved_by naming this scope; no other frozen spec document is touched (TEST-013)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-followup-registry TEST-001..005, 008, 009; role-verification-guards TEST-010/Spec-AC-09 N1)"
  echo "  + followups-cli-hardening TEST-011..015,017"
  echo "  + cli-output-survives-a-pipe TEST-018..022"
  echo "  + registry-attribution-correction TEST-023"
  echo "  + spec-adhoc-probes-unisolated-report-only verify-closures TEST-006..013"
  check_deps
  setup_fixture
  test_001_schema_and_id_discipline
  test_002_query_path
  test_003_degrade_notes_and_zero_network
  test_004_backfill_accounting
  test_005_history_integrity
  test_008_close_path
  test_009_consumer_seam
  test_010_pin_ok_assertion_catches_gutted_check
  test_011_flag_values_with_leading_dashes
  test_012_unreadable_ledger_refused
  test_013_absent_ledger_contract_unchanged
  test_014_malformed_id_named_and_counted
  test_015_exclusion_note_states_understatement
  test_017_grammar_and_product_doc_pins
  test_018_json_survives_a_pipe
  test_019_pipe_bytes_equal_file_bytes
  test_020_exit_codes_survive_the_flush
  test_021_early_close_is_not_a_failure
  test_022_output_format_is_pinned
  test_023_correct_flag
  test_024_verify_closures_reads_both_claim_shapes
  test_025_four_parse_branches_exact_sets
  test_026_miss_and_attribution_tiers
  test_027_exit_code_contract
  test_028_corpus_walk_unions_both_roots
  test_029_real_corpus_ratchet_is_a_subset
  test_030_suite_map_glob_and_seam3_regression
  test_031_both_registry_items_closed_for_real
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
