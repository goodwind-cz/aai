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

  # close-work-item.mjs is deliberately NOT wired (D5).
  if command -v git >/dev/null 2>&1; then
    local cwidiff
    cwidiff="$(git -C "$PROJECT_ROOT" diff "$BASE_REF" -- .aai/scripts/close-work-item.mjs 2>/dev/null || true)"
    [[ -z "$cwidiff" ]] || log_fail "close-work-item.mjs must stay UNTOUCHED (D5), but it differs from $BASE_REF"
  fi

  log_pass "close appends + proves by re-read, is idempotent, refuses unknown ids, exits 1 on an unproven flip; manual step documented; close-work-item untouched (TEST-008)"
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

main() {
  echo "Testing $TEST_NAME (SPEC spec-followup-registry TEST-001..005, 008, 009)"
  check_deps
  setup_fixture
  test_001_schema_and_id_discipline
  test_002_query_path
  test_003_degrade_notes_and_zero_network
  test_004_backfill_accounting
  test_005_history_integrity
  test_008_close_path
  test_009_consumer_seam
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
