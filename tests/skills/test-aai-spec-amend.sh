#!/usr/bin/env bash
#
# Test: aai-spec-amend
# (docs/specs/SPEC-DRAFT-spec-unsigned-spec-amendment-has-no-outflow.md,
#  TEST-001..010)
#
# Verifies .aai/scripts/spec-amend.mjs — the fail-OPEN writer that co-creates a
# tracked item for every unsigned post-freeze spec amendment, plus the
# fail-CLOSED `list --strict` detector wired at the PR/close gate:
#   TEST-001 add --signoff none appends BOTH records from ONE invocation
#   TEST-002 REJECTED input + the never-refuses arm (RED-first)
#   TEST-003 the 10-vs-4 format trap over the LIVE ledger
#   TEST-004 SEAM-2 — the item is read back through the REAL follow-ups.mjs
#   TEST-005 three buckets; the field outranks the prose (RED-first)
#   TEST-006 SEAM-1 — the item survives the draft-to-numbered spec rename
#   TEST-007 BOTH --strict arms (RED-first)
#   TEST-008 SEAM-3 — append-only, proved by byte comparison
#   TEST-009 post-backfill live state + SEAM-4 whole-ledger readers
#   TEST-010 the SPEC-0132 canon guard, deny-by-default on repo-relative paths
#   TEST-013 validation F1 — every remedy the refusal NAMES clears the refusal
#   TEST-014 validation NB-2 — a padded `type` cannot hide from the gate
#
# TEST-011 and TEST-012 of this spec's Test Plan live in other suites
# (test-aai-hygiene-pack.sh and test-aai-prompt-diet.sh), so the two arms added
# at remediation continue the numbering at 013 rather than reusing those ids.
#
# ALL write fixtures are scratch temp-dir ledgers — the real docs/ai tree is
# only ever READ (TEST-003/008/009/010 read it; none of them write it).
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Pipeline discipline: this suite runs `set -euo pipefail`, so a `cmd | grep`
# whose reader exits early kills the writer with SIGPIPE and fails the suite
# on CI only (docs/knowledge/LEARNED.md test-harness shell-options trap).
# Every text match below therefore uses a here-string, never a pipe.
#
# No test here creates or clones a bare repository, so the
# `git init --bare` / `init.defaultBranch` HEAD trap does not apply. Recorded
# so the omission is a decision rather than an oversight — if an arm ever adds
# one, it must also run `git -C "$bare" symbolic-ref HEAD refs/heads/main`.
#
# Usage:
#   bash tests/skills/test-aai-spec-amend.sh                 # run all
#   bash tests/skills/test-aai-spec-amend.sh test_005_three_buckets_field_over_prose
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-spec-amend"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SA="$PROJECT_ROOT/.aai/scripts/spec-amend.mjs"
FU="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
ROUTINE_EMIT="$PROJECT_ROOT/.aai/scripts/routine-emit.mjs"
LIVE_LEDGER="$PROJECT_ROOT/docs/ai/decisions.jsonl"
CANON="$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md"

# The five specs whose amendments stood unsigned when this scope was written.
BACKFILLED_SPEC_IDS="spec-close-leaves-state-stale spec-release-protected-branch-fallback spec-ac-table-premature-flip-recurs spec-metrics-flush-invalidates-pr-precondition spec-role-progress-heartbeat"

# Measured at the base commit be0c8ed and pinned there rather than against the
# working tree: the base blob never changes, so this number cannot rot as
# later rides append their own amendments (TEST-003 asserts the live tree
# separately, as a FLOOR plus an independent recount).
BASE_AMENDMENT_COUNT=10
BASE_TIGHT_GREP_COUNT=4

# Base-ref resolution prefers origin/main (a GitHub Actions PR checkout is
# detached-HEAD with only origin/main fetched, so a bare `main` never
# resolves and every git-based arm below degrades). Explicit override wins.
if [[ -n "${AAI_SPEC_AMEND_BASE_REF:-}" ]]; then
  BASE_REF="$AAI_SPEC_AMEND_BASE_REF"
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
  log_pass "Dependencies checked"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-spec-amend-test.XXXXXX")"; }

# --- runners -----------------------------------------------------------------

OUT=""    # stdout of the last run_sa / run_fu
ERR=""    # stderr of the last run_sa / run_fu
EC=0      # exit code of the last run_sa / run_fu

# run_sa never lets a non-zero exit kill the suite: every arm below reaches its
# OWN assertion and prints its own expected-vs-actual. That is what makes the
# stored RED capture a product_red rather than an infrastructure failure.
run_sa() {
  local o e
  o="$TEST_DIR/.stdout"; e="$TEST_DIR/.stderr"
  EC=0
  node "$SA" "$@" > "$o" 2> "$e" || EC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}

run_fu() {
  local o e
  o="$TEST_DIR/.fu.stdout"; e="$TEST_DIR/.fu.stderr"
  EC=0
  node "$FU" "$@" > "$o" 2> "$e" || EC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}

# mk_ledger <name> -> a fresh fixture ledger carrying the SAME `#` comment
# header shape the real docs/ai/decisions.jsonl opens with (the comment-line
# edge every reader in this scope must skip).
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

# mk_spec <name> <frontmatter-id> -> a fixture spec document. The tracked
# item's id must come from THIS id, never from the filename (SEAM-1).
mk_spec() {
  local f="$TEST_DIR/$1"
  {
    echo "---"
    echo "id: $2"
    echo "type: spec"
    echo "number: null"
    echo "status: implementing"
    echo "---"
    echo ""
    echo "# fixture spec"
    echo ""
    echo "SPEC-FROZEN: true"
  } > "$f"
  printf '%s' "$f"
}

# count_amendments <ledger> -> spec_amendment records counted by PARSING each
# line as JSON. Computed independently of the tool under test so the tool's
# own number is checked against something, not against itself.
count_amendments() {
  node -e '
    const fs=require("fs");
    const raw=fs.readFileSync(process.argv[1],"utf8");
    let n=0;
    for (const line of raw.split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment") n+=1;
    }
    process.stdout.write(String(n));
  ' "$1"
}

# count_spaced_amendments <ledger> -> how many of them serialize the key WITH a
# space. This is the population a tight grep silently drops.
count_spaced_amendments() {
  node -e '
    const fs=require("fs");
    const raw=fs.readFileSync(process.argv[1],"utf8");
    let n=0;
    for (const line of raw.split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment" && !t.includes("\"type\":\"spec_amendment\"")) n+=1;
    }
    process.stdout.write(String(n));
  ' "$1"
}

# json_field <json> <node-expression over `j`>
json_field() {
  node -e '
    let j; try { j=JSON.parse(process.argv[1]); } catch (e) { console.log("UNPARSEABLE:"+e.message); process.exit(0); }
    console.log(String(eval(process.argv[2])));
  ' "$1" "$2"
}

# --- TEST-001 (Spec-AC-01) ----------------------------------------------------

test_001_add_creates_both_records() {
  log_info "Test: ONE \`add --signoff none\` appends BOTH the spec_amendment (owner_signoff false) AND the open follow_up naming the spec and the sign-off owed (TEST-001)..."
  local led spec
  led="$(mk_ledger t001)"
  spec="$(mk_spec "SPEC-DRAFT-t001.md" "spec-t001-fixture")"

  run_sa add --ledger "$led" --spec "$spec" --ref t001-ride \
    --what "widened D3 to cover the absent-key case" \
    --why "the frozen spec's fold had two buckets and the data has three" \
    --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-001: expected exit 0 from \`add --signoff none\`, got $EC (stderr: $ERR)"

  local verdict
  verdict="$(node -e '
    const fs=require("fs");
    const recs=[];
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { console.log("MALFORMED-LINE"); process.exit(0); }
      recs.push(r);
    }
    const am=recs.filter(r=>r.type==="spec_amendment");
    const fu=recs.filter(r=>r.type==="follow_up");
    if (am.length!==1) { console.log("AMENDMENTS="+am.length); process.exit(0); }
    if (fu.length!==1) { console.log("FOLLOWUPS="+fu.length); process.exit(0); }
    if (am[0].owner_signoff!==false) { console.log("SIGNOFF="+JSON.stringify(am[0].owner_signoff)); process.exit(0); }
    if (am[0].spec_id!=="spec-t001-fixture") { console.log("SPECID="+am[0].spec_id); process.exit(0); }
    if (am[0].tracked_by!==fu[0].id) { console.log("LINK="+am[0].tracked_by+" vs "+fu[0].id); process.exit(0); }
    if (!String(fu[0].finding).includes("spec-t001-fixture")) { console.log("FINDING-NO-SPEC:"+fu[0].finding); process.exit(0); }
    if (!/sign-off owed/i.test(String(fu[0].finding))) { console.log("FINDING-NO-SIGNOFF:"+fu[0].finding); process.exit(0); }
    if (Object.prototype.hasOwnProperty.call(fu[0],"status")) { console.log("FU-CARRIES-STATUS"); process.exit(0); }
    console.log("BOTH-OK id="+fu[0].id);
  ' "$led")"
  case "$verdict" in
    BOTH-OK*) : ;;
    *) log_fail "TEST-001: one invocation did not leave BOTH records in a usable shape — $verdict" ;;
  esac

  log_pass "TEST-001 one add appended both the amendment and its open tracked item ($verdict)"
}

# --- TEST-002 (Spec-AC-02) — RED-first ---------------------------------------

test_002_rejected_input_and_never_refuses() {
  log_info "Test: REJECTED input — \`add --signoff owner\` with no --authority exits 2 and NAMES the flag; and \`add --signoff none\` against a ledger holding no tracked item exits 0, proving the writer never refuses for a missing item (TEST-002)..."
  local led spec
  led="$(mk_ledger t002)"
  spec="$(mk_spec "SPEC-DRAFT-t002.md" "spec-t002-fixture")"

  # ARM 1 — the REJECTED input, and the guard's OWN message text.
  run_sa add --ledger "$led" --spec "$spec" --ref t002-ride \
    --what "w" --why "y" --signoff owner
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-002 arm 1: expected exit 2 for \`--signoff owner\` with no --authority, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF -- "--authority" <<<"$ERR" \
    || log_fail "TEST-002 arm 1: the refusal must NAME the flag it wants; stderr was: $ERR"

  # ARM 1b — nothing was written by the refusal (a usage error is not a write).
  local after1
  after1="$(count_amendments "$led")"
  [[ "$after1" == 0 ]] \
    || log_fail "TEST-002 arm 1b: a refused invocation must append nothing, found $after1 spec_amendment record(s)"

  # ARM 2 — the accepting twin, on a ledger with NO tracked item anywhere. This
  # is the fail-OPEN half: AC-001 is satisfied by co-creation, never by a
  # refusal that could strand a remediation round.
  run_sa add --ledger "$led" --spec "$spec" --ref t002-ride \
    --what "w" --why "y" --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-002 arm 2: \`add --signoff none\` must NEVER refuse for a missing tracked item, got exit $EC (stderr: $ERR)"

  # ARM 3 — the owner form is accepted once the authority IS on the record.
  run_sa add --ledger "$led" --spec "$spec" --ref t002-signed \
    --what "w" --why "y" --signoff owner --authority "owner decision, 2026-09-03, chat"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-002 arm 3: \`--signoff owner --authority ...\` must be accepted, got exit $EC (stderr: $ERR)"

  # ARM 4 — a missing required flag is the OTHER usage-error class, and it
  # names the flag too.
  run_sa add --ledger "$led" --ref t002-ride --what "w" --why "y" --signoff none
  [[ "$EC" == 2 ]] || log_fail "TEST-002 arm 4: a missing --spec must exit 2, got $EC"
  grep -qF -- "--spec" <<<"$ERR" || log_fail "TEST-002 arm 4: the refusal must name --spec; stderr was: $ERR"

  # ARM 5 — a spec with no frontmatter `id` is exit 2 NAMING the file: the
  # tracked id keys on that field and must never be guessed from the path.
  local bad="$TEST_DIR/SPEC-DRAFT-no-id.md"
  printf '%s\n' '# no frontmatter here' > "$bad"
  run_sa add --ledger "$led" --spec "$bad" --ref t002-ride --what "w" --why "y" --signoff none
  [[ "$EC" == 2 ]] || log_fail "TEST-002 arm 5: a spec with no frontmatter id must exit 2, got $EC"
  grep -qF "SPEC-DRAFT-no-id.md" <<<"$ERR" || log_fail "TEST-002 arm 5: the refusal must name the file; stderr was: $ERR"

  log_pass "TEST-002 the writer refuses ONLY usage errors, names the flag it wants, and never refuses an unsigned amendment for a missing tracked item"
}

# --- TEST-003 (Spec-AC-03) — the format trap ---------------------------------

test_003_live_ledger_format_trap() {
  log_info "Test: \`list --json\` over the LIVE ledger counts by PARSING, not by grepping — the arm a grep-based implementation fails (TEST-003)..."
  [[ -f "$LIVE_LEDGER" ]] || log_fail "TEST-003: live ledger not found at $LIVE_LEDGER"

  # The base blob is the durable pin: it cannot rot as later rides append.
  if git -C "$PROJECT_ROOT" show "$BASE_REF:docs/ai/decisions.jsonl" > "$TEST_DIR/base.jsonl" 2>/dev/null; then
    local base_parsed base_tight
    base_parsed="$(count_amendments "$TEST_DIR/base.jsonl")"
    base_tight="$(/usr/bin/grep -c '"type":"spec_amendment"' "$TEST_DIR/base.jsonl" || true)"
    [[ "$base_parsed" == "$BASE_AMENDMENT_COUNT" ]] \
      || log_fail "TEST-003: the base ledger must carry exactly $BASE_AMENDMENT_COUNT spec_amendment records when parsed as JSON, counted $base_parsed"
    [[ "$base_tight" == "$BASE_TIGHT_GREP_COUNT" ]] \
      || log_fail "TEST-003: the tight grep must still under-report the base ledger at $BASE_TIGHT_GREP_COUNT (the trap this arm exists for), counted $base_tight"
    log_info "TEST-003: base $BASE_REF ledger — parsed=$base_parsed tight-grep=$base_tight (the 60% undercount)"
  else
    log_info "TEST-003: base ref $BASE_REF has no docs/ai/decisions.jsonl (shallow clone or detached base) — base pin not applicable here"
  fi

  local parsed spaced tool_total
  parsed="$(count_amendments "$LIVE_LEDGER")"
  spaced="$(count_spaced_amendments "$LIVE_LEDGER")"

  run_sa list --ledger "$LIVE_LEDGER" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-003: \`list --json\` over the live ledger must exit 0 without --strict, got $EC (stderr: $ERR)"
  tool_total="$(json_field "$OUT" 'j.counts.total')"
  [[ "$tool_total" == "$parsed" ]] \
    || log_fail "TEST-003: the tool reported $tool_total spec_amendment records; an INDEPENDENT JSON recount of the same file found $parsed"
  [[ "$parsed" -ge "$BASE_AMENDMENT_COUNT" ]] \
    || log_fail "TEST-003: the live ledger must still carry at least the $BASE_AMENDMENT_COUNT records measured at the base commit, counted $parsed"
  [[ "$spaced" -ge 6 ]] \
    || log_fail "TEST-003: the space-serialized population this arm exists to catch has vanished ($spaced < 6) — re-derive the trap before weakening the arm"

  # The trap itself, stated as an inequality against the live file so it stays
  # true as the ledger grows: a tight grep sees strictly fewer.
  local tight
  tight="$(/usr/bin/grep -c '"type":"spec_amendment"' "$LIVE_LEDGER" || true)"
  [[ "$tight" -lt "$parsed" ]] \
    || log_fail "TEST-003: a tight grep counted $tight and JSON parsing counted $parsed — the arm that proves a grep-based query is wrong is no longer proving anything"

  # Every space-serialized record must actually appear in the tool's output.
  local missing
  missing="$(node -e '
    const fs=require("fs");
    const j=JSON.parse(process.argv[1]);
    const seen=new Set(j.items.map(i=>i.ts+" "+i.ref_id));
    const miss=[];
    for (const line of fs.readFileSync(process.argv[2],"utf8").split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (!r || r.type!=="spec_amendment") continue;
      if (t.includes("\"type\":\"spec_amendment\"")) continue;   // the grep-visible half
      if (!seen.has(r.ts+" "+r.ref_id)) miss.push(r.ts+" "+r.ref_id);
    }
    process.stdout.write(miss.join(","));
  ' "$OUT" "$LIVE_LEDGER")"
  [[ -z "$missing" ]] \
    || log_fail "TEST-003: space-serialized records missing from \`list --json\`: $missing"

  log_pass "TEST-003 live ledger: parsed=$parsed (>= $BASE_AMENDMENT_COUNT), tight-grep=$tight, $spaced space-serialized records all reported"
}

# --- TEST-004 (Spec-AC-01) — SEAM-2 ------------------------------------------

test_004_seam2_read_back_through_follow_ups() {
  log_info "Test: SEAM-2 — the item spec-amend.mjs PRODUCES is read back through the REAL follow-ups.mjs, not a mock (TEST-004)..."
  [[ -f "$FU" ]] || log_skip "follow-ups.mjs not found: $FU"
  local led spec
  led="$(mk_ledger t004)"
  spec="$(mk_spec "SPEC-DRAFT-t004.md" "spec-t004-fixture")"

  run_sa add --ledger "$led" --spec "$spec" --ref t004-ride \
    --what "extended the writer" --why "the frozen spec did not cover it" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-004: add must succeed before the seam check, got $EC (stderr: $ERR)"

  local item_id
  item_id="$(node -e '
    const fs=require("fs");
    let found="";
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="follow_up") { found=String(r.id); break; }
    }
    process.stdout.write(found);
  ' "$led")"
  [[ -n "$item_id" ]] || log_fail "TEST-004: no follow_up record was written"

  run_fu list --ledger "$led" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-004: follow-ups.mjs list must exit 0 over the produced ledger, got $EC (stderr: $ERR)"
  grep -qF "$item_id" <<<"$OUT" \
    || log_fail "TEST-004: the real follow-ups.mjs reader does not name the item spec-amend wrote ($item_id): $OUT"

  # The consumer must not merely SEE the id — it must accept it as well-formed.
  # A MALFORMED-ID marker here means the producer wrote an id outside the
  # consumer's own grammar, which is what the amendItemId fitting function
  # exists to prevent (three of the five live spec ids fit, two do not).
  grep -qF "MALFORMED-ID" <<<"$OUT" \
    && log_fail "TEST-004: follow-ups.mjs flagged the produced id as MALFORMED-ID — the producer wrote outside the consumer's grammar: $OUT"

  # The obligation is OPEN by construction: the writer never writes a status.
  grep -qE "^open[[:space:]]+$item_id" <<<"$OUT" \
    || log_fail "TEST-004: the produced item is not open in the consumer's projection: $OUT"

  log_pass "TEST-004 the item written by spec-amend.mjs reads back OPEN and well-formed through the real follow-ups.mjs ($item_id)"
}

# --- TEST-005 (Spec-AC-04) — RED-first ---------------------------------------

test_005_three_buckets_field_over_prose() {
  log_info "Test: the bucket is decided by the owner_signoff KEY alone — an absent key is its own \`unclassified\` bucket, and prose saying \"NOT an owner decision\" loses to a key that says true (TEST-005)..."
  local led
  led="$(mk_ledger t005)"
  {
    # A — key true
    echo '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t005-signed","spec_id":"spec-a","owner_signoff":true,"authority":"owner decision, chat"}'
    # B — key false, tracked_by pointing at an item that EXISTS below
    echo '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t005-tracked","spec_id":"spec-b","owner_signoff":false,"tracked_by":"fu-amend-spec-b"}'
    echo '{"v":1,"ts":"2026-09-01T02:00:01Z","actor":"a","type":"follow_up","id":"fu-amend-spec-b","ref_id":"t005-tracked","severity":"P2","finding":"f","decision":"d","source":"s"}'
    # C — key ABSENT: unclassified, and NEITHER of the other two
    echo '{"v":1,"ts":"2026-09-01T03:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t005-absent","spec_id":"spec-c","authority":"planning, NOT an owner decision"}'
    # D — prose says NOT an owner decision, the KEY says true: signed
    echo '{ "v":1, "ts":"2026-09-01T04:00:00Z", "actor":"a", "type": "spec_amendment", "ref_id":"t005-prose", "spec_id":"spec-d", "owner_signoff":true, "authority":"NOT an owner decision, filed by remediation" }'
    # E — key false, NO tracked_by anywhere: unsigned-untracked
    echo '{"v":1,"ts":"2026-09-01T05:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t005-untracked","spec_id":"spec-e","owner_signoff":false}'
  } >> "$led"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-005: \`list --json\` must exit 0 without --strict even with violations present, got $EC (stderr: $ERR)"

  local verdict
  verdict="$(node -e '
    let j; try { j=JSON.parse(process.argv[1]); } catch (e) { console.log("UNPARSEABLE:"+e.message); process.exit(0); }
    const want = {
      "t005-signed":"signed",
      "t005-tracked":"unsigned-tracked",
      "t005-absent":"unclassified",
      "t005-prose":"signed",
      "t005-untracked":"unsigned-untracked",
    };
    const got = {};
    for (const i of (j.items||[])) got[i.ref_id]=i.bucket;
    const bad=[];
    for (const k of Object.keys(want)) if (got[k]!==want[k]) bad.push(k+": want "+want[k]+", got "+String(got[k]));
    if (bad.length) { console.log("MISMATCH "+bad.join(" | ")); process.exit(0); }
    // The absent-key record must land in unclassified and in NEITHER of the
    // other two: three buckets, not two with a default.
    if (j.counts.unclassified!==1) { console.log("UNCLASSIFIED-COUNT="+j.counts.unclassified); process.exit(0); }
    if (j.counts.signed!==2) { console.log("SIGNED-COUNT="+j.counts.signed); process.exit(0); }
    const absent=(j.items||[]).find(i=>i.ref_id==="t005-absent");
    if (absent.owner_signoff!==null) { console.log("ABSENT-SIGNOFF-GUESSED="+JSON.stringify(absent.owner_signoff)); process.exit(0); }
    console.log("BUCKETS-OK");
  ' "$OUT")"
  [[ "$verdict" == "BUCKETS-OK" ]] || log_fail "TEST-005: $verdict"

  # --status is a VIEW, and each of the three views is exact.
  run_sa list --ledger "$led" --status unclassified --json
  [[ "$(json_field "$OUT" 'j.items.map(i=>i.ref_id).join(",")')" == "t005-absent" ]] \
    || log_fail "TEST-005: --status unclassified must show exactly the absent-key record, got $OUT"
  run_sa list --ledger "$led" --status signed --json
  [[ "$(json_field "$OUT" 'j.items.map(i=>i.ref_id).sort().join(",")')" == "t005-prose,t005-signed" ]] \
    || log_fail "TEST-005: --status signed must show exactly the two key-true records, got $OUT"
  run_sa list --ledger "$led" --status unsigned --json
  [[ "$(json_field "$OUT" 'j.items.map(i=>i.ref_id).sort().join(",")')" == "t005-tracked,t005-untracked" ]] \
    || log_fail "TEST-005: --status unsigned must show both unsigned buckets, got $OUT"

  # An overlay OUTRANKS the record's own key, and the LATEST overlay wins.
  printf '%s\n' '{"v":1,"ts":"2026-09-02T00:00:00Z","actor":"b","type":"spec_amendment_classification","classifies_ts":"2026-09-01T03:00:00Z","classifies_ref":"t005-absent","owner_signoff":false,"why":"back-classified","origin":"backfill","source":"evidence"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T00:00:00Z","actor":"b","type":"spec_amendment_classification","classifies_ts":"2026-09-01T03:00:00Z","classifies_ref":"t005-absent","owner_signoff":true,"why":"corrected","source":"evidence-2"}' >> "$led"
  run_sa list --ledger "$led" --json
  [[ "$(json_field "$OUT" '(j.items.find(i=>i.ref_id==="t005-absent")||{}).bucket')" == "signed" ]] \
    || log_fail "TEST-005: the LATEST classification overlay must win, got $OUT"

  log_pass "TEST-005 three buckets decided by the field alone; the absent key is its own bucket and is never guessed; the latest overlay wins"
}

# --- TEST-006 (Spec-AC-04) — SEAM-1 ------------------------------------------

test_006_seam1_survives_the_rename() {
  log_info "Test: SEAM-1 — allocate-doc-number.mjs renames SPEC-DRAFT-<slug>.md to SPEC-000N-<slug>.md at merge; the tracked id keys on the frontmatter id, so it survives (TEST-006)..."
  local led draft
  led="$(mk_ledger t006)"
  draft="$(mk_spec "SPEC-DRAFT-t006.md" "spec-t006-fixture")"

  run_sa add --ledger "$led" --spec "$draft" --ref t006-ride --what "first" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-006: the pre-rename add must succeed, got $EC (stderr: $ERR)"
  local first_id
  first_id="$(json_field "$(node "$SA" list --ledger "$led" --json)" 'j.items[0].tracked_by')"
  [[ -n "$first_id" && "$first_id" != "null" ]] || log_fail "TEST-006: no tracked_by on the first amendment"

  # The rename the allocator performs at merge.
  local numbered="$TEST_DIR/SPEC-0999-t006.md"
  mv "$draft" "$numbered"

  run_sa add --ledger "$led" --spec "$numbered" --ref t006-ride-2 --what "second" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-006: the post-rename add must succeed, got $EC (stderr: $ERR)"
  grep -qF "already open" <<<"$OUT" \
    || log_fail "TEST-006: a second amendment on a spec with an OPEN item must attach to it and say so, got: $OUT"

  local verdict
  verdict="$(node -e '
    const fs=require("fs");
    const ids=new Set(); let amendments=0, followUps=0;
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r.type==="spec_amendment") { amendments+=1; ids.add(r.tracked_by); }
      if (r.type==="follow_up") followUps+=1;
    }
    if (amendments!==2) { console.log("AMENDMENTS="+amendments); process.exit(0); }
    if (ids.size!==1) { console.log("FORKED-IDS="+[...ids].join(",")); process.exit(0); }
    if (followUps!==1) { console.log("DUPLICATE-ITEMS="+followUps); process.exit(0); }
    console.log("SAME-ITEM "+[...ids][0]);
  ' "$led")"
  case "$verdict" in
    SAME-ITEM*) : ;;
    *) log_fail "TEST-006: the rename forked or duplicated the obligation — $verdict" ;;
  esac
  grep -qF "$first_id" <<<"$verdict" \
    || log_fail "TEST-006: the post-rename item id differs from the pre-rename one ($first_id vs $verdict)"

  # A path-keyed id would have produced two different ids here; prove the id is
  # a function of the FRONTMATTER, by changing only the frontmatter.
  local other
  other="$(mk_spec "SPEC-DRAFT-t006.md" "spec-t006-other")"
  run_sa add --ledger "$led" --spec "$other" --ref t006-ride-3 --what "third" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-006: the differing-frontmatter add must succeed, got $EC"
  local third_id
  third_id="$(node -e '
    const fs=require("fs");
    let last=null;
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r.type==="spec_amendment") last=r.tracked_by;
    }
    process.stdout.write(String(last));
  ' "$led")"
  [[ "$third_id" != "$first_id" ]] \
    || log_fail "TEST-006: two DIFFERENT frontmatter ids collapsed onto one tracked item ($third_id) — the id is not keyed on the frontmatter"

  log_pass "TEST-006 the tracked item survives the draft-to-numbered rename and forks only when the frontmatter id differs ($first_id)"
}

# --- TEST-007 (Spec-AC-05) — RED-first ---------------------------------------

test_007_both_strict_arms() {
  log_info "Test: BOTH \`--strict\` arms — exit 1 with the offending ref named while a record is untracked or unclassified, exit 0 once every record is signed or unsigned-tracked, and exit 0 in BOTH cases without --strict (TEST-007)..."
  [[ -f "$FU" ]] || log_skip "follow-ups.mjs not found: $FU"
  local led
  led="$(mk_ledger t007)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t007-untracked","spec_id":"spec-g","owner_signoff":false}' >> "$led"
  printf '%s\n' '{ "v":1, "ts":"2026-09-01T07:00:00Z", "actor":"a", "type": "spec_amendment", "ref_id":"t007-absent", "spec_id":"spec-h" }' >> "$led"

  # ARM 1 — the FAILING arm, and the message names each offending record.
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-007 arm 1: \`list --strict\` must exit 1 while an untracked or unclassified record stands, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "t007-untracked" <<<"$OUT" \
    || log_fail "TEST-007 arm 1: --strict must NAME the untracked record; stdout was: $OUT"
  grep -qF "t007-absent" <<<"$OUT" \
    || log_fail "TEST-007 arm 1: --strict must NAME the unclassified record; stdout was: $OUT"
  grep -qF "unsigned-untracked" <<<"$OUT" \
    || log_fail "TEST-007 arm 1: --strict must state WHICH violation each record is; stdout was: $OUT"

  # ARM 2 — the same ledger, same moment, WITHOUT --strict: exit 0. A reporter
  # and a gate are different jobs and this pins that they stay different.
  run_sa list --ledger "$led"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-007 arm 2: without --strict the SAME violating ledger must exit 0, got $EC"

  # ARM 3 — remediate by APPEND only, then --strict must clear.
  run_fu add --ledger "$led" --id fu-amend-spec-g --ref t007-untracked --severity P2 \
    --what "owner sign-off owed on spec-g" --why "filed unsigned" --source "s"
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 3: follow-ups add must succeed, got $EC (stderr: $ERR)"
  run_sa classify --ledger "$led" --ts "2026-09-01T06:00:00Z" --ref t007-untracked \
    --signoff none --why "back-classified" --source "evidence" --origin backfill --tracked-by fu-amend-spec-g
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 3: classify must succeed, got $EC (stderr: $ERR)"
  run_sa classify --ledger "$led" --ts "2026-09-01T07:00:00Z" --ref t007-absent \
    --signoff owner --why "owner decision on the record" --source "evidence" --origin backfill
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 3: the owner classify must succeed, got $EC (stderr: $ERR)"

  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-007 arm 3: once every record is signed or unsigned-tracked, --strict must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "STRICT-VIOLATION" <<<"$OUT" \
    && log_fail "TEST-007 arm 3: a clean ledger must print no violation lines; stdout was: $OUT"

  # ARM 4 — --strict is judged over the WHOLE ledger, never over the filtered
  # view: a gate that could be silenced by narrowing its own query is not a
  # gate. Re-introduce one violation and query a view that excludes it.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T08:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t007-hidden","spec_id":"spec-i","owner_signoff":false}' >> "$led"
  run_sa list --ledger "$led" --status signed --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-007 arm 4: --strict must judge the whole ledger, not the --status view (a narrowed query must not silence the gate), got $EC"

  # ARM 5 — classify refuses an unmatched and an ambiguous target rather than
  # guessing, with exit 2 in both cases.
  run_sa classify --ledger "$led" --ts "1999-01-01T00:00:00Z" --ref nope \
    --signoff none --why "w" --source "s"
  [[ "$EC" == 2 ]] || log_fail "TEST-007 arm 5: an unmatched classify target must exit 2, got $EC"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T08:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t007-hidden","spec_id":"spec-i","owner_signoff":false}' >> "$led"
  run_sa classify --ledger "$led" --ts "2026-09-01T08:00:00Z" --ref t007-hidden \
    --signoff none --why "w" --source "s"
  [[ "$EC" == 2 ]] || log_fail "TEST-007 arm 5: an AMBIGUOUS classify target must exit 2, got $EC"
  grep -qiF "ambiguous" <<<"$ERR" || log_fail "TEST-007 arm 5: the ambiguity refusal must say so; stderr was: $ERR"

  log_pass "TEST-007 both --strict arms hold, the gate cannot be silenced by narrowing the view, and classify refuses rather than guesses"
}

# --- TEST-008 (Spec-AC-06) — SEAM-3, append-only ------------------------------

test_008_append_only() {
  log_info "Test: SEAM-3 — every write path APPENDS; the pre-change bytes are a byte-exact prefix afterwards, and the same predicate REJECTS a planted rewrite (TEST-008)..."
  local led before
  led="$(mk_ledger t008)"
  # Seed the fixture with a real copy of the live ledger so the comparison is
  # over the shape this scope actually backfilled, not a toy file.
  cat "$LIVE_LEDGER" >> "$led"
  before="$TEST_DIR/t008-before.jsonl"
  cp "$led" "$before"

  local spec
  spec="$(mk_spec "SPEC-DRAFT-t008.md" "spec-t008-fixture")"
  run_sa add --ledger "$led" --spec "$spec" --ref t008-ride --what "w" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-008: add must succeed, got $EC (stderr: $ERR)"
  run_sa classify --ledger "$led" --ts "2026-08-28T11:20:00Z" --ref agent-shell-can-write-the-shipping-repo \
    --signoff owner --why "owner decision on the record" --source "evidence" --origin backfill
  [[ "$EC" == 0 ]] || log_fail "TEST-008: classify must succeed, got $EC (stderr: $ERR)"

  local verdict
  verdict="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    if (head.length < base.length) { console.log("SHORTER by "+(base.length-head.length)); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    if (!prefix.equals(base)) {
      let i=0; while (i<base.length && prefix[i]===base[i]) i+=1;
      console.log("DIVERGES at byte offset "+i); process.exit(0);
    }
    console.log("PREFIX-OK appended="+(head.length-base.length));
  ' "$before" "$led")"
  grep -qF "PREFIX-OK" <<<"$verdict" || log_fail "TEST-008: a write path rewrote existing ledger bytes — $verdict"

  # MUTATION CONTROL: the same predicate must REJECT a planted in-place edit,
  # or the assertion above is vacuous.
  local mutated="$TEST_DIR/t008-mutated.jsonl"
  # The mutation must land INSIDE the base region and must be guaranteed to
  # change a byte — a text substitution that happens not to match would make
  # this control silently vacuous, which is the same defect class the control
  # exists to catch. Flip one byte at a fixed offset well inside the prefix.
  node -e '
    const fs=require("fs");
    const buf=Buffer.from(fs.readFileSync(process.argv[1]));
    const base=fs.statSync(process.argv[3]).size;
    const at=Math.floor(base/2);
    buf[at]=buf[at]===0x41 ? 0x42 : 0x41;
    fs.writeFileSync(process.argv[2], buf);
  ' "$led" "$mutated" "$before"
  local mutverdict
  mutverdict="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    if (head.length < base.length) { console.log("SHORTER"); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    if (!prefix.equals(base)) { let i=0; while (i<base.length && prefix[i]===base[i]) i+=1; console.log("DIVERGES at byte offset "+i); process.exit(0); }
    console.log("PREFIX-OK");
  ' "$before" "$mutated")"
  grep -qF "DIVERGES" <<<"$mutverdict" \
    || log_fail "TEST-008: mutation control failed — a planted in-place rewrite was accepted as a pure append ($mutverdict)"

  # The LIVE ledger, against the base commit: this scope's own backfill must be
  # appended lines and nothing else.
  if git -C "$PROJECT_ROOT" show "$BASE_REF:docs/ai/decisions.jsonl" > "$TEST_DIR/t008-base.jsonl" 2>/dev/null; then
    local live_verdict
    live_verdict="$(node -e '
      const fs=require("fs");
      const base=fs.readFileSync(process.argv[1]);
      const head=fs.readFileSync(process.argv[2]);
      if (head.length < base.length) { console.log("SHORTER by "+(base.length-head.length)); process.exit(0); }
      const prefix=head.subarray(0, base.length);
      if (!prefix.equals(base)) { let i=0; while (i<base.length && prefix[i]===base[i]) i+=1; console.log("DIVERGES at byte offset "+i); process.exit(0); }
      const baseLines=base.toString("utf8").split("\n").filter(l=>l.trim()!=="").length;
      console.log("PREFIX-OK base_lines="+baseLines+" appended_bytes="+(head.length-base.length));
    ' "$TEST_DIR/t008-base.jsonl" "$LIVE_LEDGER")"
    grep -qF "PREFIX-OK" <<<"$live_verdict" \
      || log_fail "TEST-008: the live ledger is not a pure append over $BASE_REF — $live_verdict"
    log_info "TEST-008: live ledger vs $BASE_REF — $live_verdict"
  else
    log_info "TEST-008: base ref $BASE_REF has no docs/ai/decisions.jsonl — the live append-only arm is not applicable here"
  fi

  log_pass "TEST-008 both write paths append only; the pre-change bytes survive byte-exact and a planted rewrite is rejected"
}

# --- TEST-009 (Spec-AC-07) — post-backfill live state + SEAM-4 ---------------

test_009_live_backfill_and_whole_ledger_readers() {
  log_info "Test: the LIVE ledger after the backfill — \`list --strict\` exits 0, every record carries an effective classification, one open item per unsigned spec, and the whole-ledger readers still work (TEST-009)..."
  [[ -f "$FU" ]] || log_skip "follow-ups.mjs not found: $FU"

  run_sa list --ledger "$LIVE_LEDGER" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-009: \`list --strict\` over the live ledger must exit 0 after the backfill, got $EC (stdout: $OUT) (stderr: $ERR)"

  run_sa list --ledger "$LIVE_LEDGER" --status unclassified --json
  [[ "$(json_field "$OUT" 'j.counts.unclassified')" == 0 ]] \
    || log_fail "TEST-009: the live ledger still carries unclassified amendments: $OUT"

  # One OPEN tracked item per unsigned spec, named through the REAL reader.
  run_fu list --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-009: follow-ups.mjs list must exit 0 over the live ledger, got $EC (stderr: $ERR)"
  local open_out="$OUT" sid missing=""
  for sid in $BACKFILLED_SPEC_IDS; do
    local expect
    # The spec id comes FIRST on purpose: spec-amend.mjs decides isMain by
    # comparing realpath(process.argv[1]) against its own module path, so
    # passing the module path in that slot would make the import execute the
    # CLI with the next argument as its subcommand.
    expect="$(node -e '
      const { pathToFileURL } = require("node:url");
      import(pathToFileURL(process.argv[2]).href)
        .then((m) => process.stdout.write(m.amendItemId(process.argv[1])));
    ' "$sid" "$SA")"
    grep -qF "$expect" <<<"$open_out" || missing="$missing $sid($expect)"
  done
  [[ -z "$missing" ]] \
    || log_fail "TEST-009: no OPEN tracked item for:$missing — the standing amendments are not surfaced for an owner decision"
  grep -qF "MALFORMED-ID" <<<"$open_out" \
    && log_fail "TEST-009: the backfilled item ids are outside follow-ups.mjs's own grammar: $open_out"

  # Nothing was reversed and no spec body was edited by this scope's backfill:
  # the five specs are still status: done, exactly as the requirement demands
  # (surfaced for a decision, never reversed by default).
  if git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1; then
    local touched
    touched="$(git -C "$PROJECT_ROOT" diff --name-only "$BASE_REF"...HEAD -- \
      'docs/specs/SPEC-0153-*' 'docs/specs/SPEC-0161-*' 'docs/specs/SPEC-0162-*' \
      'docs/specs/SPEC-0163-*' 'docs/specs/SPEC-0164-*' 2>/dev/null || true)"
    [[ -z "$touched" ]] \
      || log_fail "TEST-009: this scope edited a frozen \`status: done\` spec body, which the requirement puts out of scope: $touched"
  else
    log_info "TEST-009: base ref $BASE_REF not resolvable — the untouched-frozen-specs arm is not applicable here"
  fi

  # SEAM-4 — routine-emit.mjs reads the WHOLE ledger fail-closed and returns
  # false on the FIRST unparseable non-comment line. The new record types must
  # be transparent to it. Asserted on a fixture that copies the live ledger and
  # adds the authorization record the reader is looking for.
  if [[ -f "$ROUTINE_EMIT" ]]; then
    local seam="$TEST_DIR/t009-seam.jsonl"
    cat "$LIVE_LEDGER" > "$seam"
    printf '%s\n' '{"v":1,"ts":"2026-08-01T00:00:00Z","type":"routine_authorization","ref":"test-ref","by":"human","grants":["merge"],"notes":"fixture"}' >> "$seam"
    local remit_out remit_ec=0
    remit_out="$(node "$ROUTINE_EMIT" --routine SCRYER --harness generic --os macos \
      --repo owner/repo --schedule "0 7 * * *" --model m --tz UTC \
      --merge --ref test-ref --decisions "$seam" 2>&1)" || remit_ec=$?
    [[ "$remit_ec" == 0 ]] \
      || log_fail "TEST-009 SEAM-4: routine-emit must exit 0 over a ledger carrying the new record types, got $remit_ec: $remit_out"
    grep -qF "MERGE DISABLED" <<<"$remit_out" \
      && log_fail "TEST-009 SEAM-4: the new spec_amendment_classification / follow_up records revoked merge authorization — routine-emit's whole-ledger reader does NOT tolerate them: $remit_out"
    # Mutation control: the same reader must still fail closed on a genuinely
    # malformed line, or the tolerance assertion above proves nothing.
    printf '%s\n' '{"v":1,"type":"spec_amendment_classification","classifies_ts":' >> "$seam"
    local pois_ec=0 pois_out
    pois_out="$(node "$ROUTINE_EMIT" --routine SCRYER --harness generic --os macos \
      --repo owner/repo --schedule "0 7 * * *" --model m --tz UTC \
      --merge --ref test-ref --decisions "$seam" 2>&1)" || pois_ec=$?
    grep -qF "MERGE DISABLED" <<<"$pois_out" \
      || log_fail "TEST-009 SEAM-4: mutation control failed — a malformed line did NOT revoke authorization, so the tolerance arm above is vacuous"
  else
    log_info "TEST-009: routine-emit.mjs not found — SEAM-4 arm not applicable here"
  fi

  log_pass "TEST-009 the live ledger is strict-clean, every unsigned spec has one open item, no frozen spec body was edited, and the whole-ledger readers tolerate the new types"
}

# --- TEST-010 (Spec-AC-08) — the SPEC-0132 canon guard ------------------------
#
# DENY-BY-DEFAULT, matched on the REPO-RELATIVE PATH. An allowlist matched on
# the BASENAME shipped in an earlier ride this session and an external reviewer
# broke it by planting a nested file one directory down; arm 3 below plants
# exactly that shape and requires the sweep to catch it.

# spec0132_sweep <scan-root> — prints "SCANNED <n>" and one "VIOLATION <path>"
# line per offending file, where <path> is the repo-relative path formed as
# `.aai/` + the path relative to <scan-root>.
spec0132_sweep() {
  node -e '
    const fs=require("fs"), path=require("path");
    const root=process.argv[1];
    // The exemption list is a closed set of REPO-RELATIVE paths, never
    // basenames: the canon file below is required by Spec-AC-08 to NAME
    // SPEC-0132 (as an owner decision, explicitly not precedent), and it is
    // the only file allowed to mention it at all.
    const EXEMPT = new Set([".aai/system/AUTONOMOUS_LOOP.md"]);
    let scanned=0; const violations=[];
    function walk(dir, rel) {
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries.sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0)) {
        const full=path.join(dir, e.name);
        const r = rel ? rel+"/"+e.name : e.name;
        if (e.isDirectory()) { if (r==="cache") continue; walk(full, r); continue; }
        if (!e.isFile()) continue;
        scanned+=1;
        const repoRel=".aai/"+r;
        let text;
        try { text = fs.readFileSync(full,"utf8"); } catch { continue; }
        if (!text.includes("SPEC-0132")) continue;
        if (EXEMPT.has(repoRel)) continue;
        violations.push(repoRel);
      }
    }
    walk(root, "");
    console.log("SCANNED "+scanned);
    for (const v of violations) console.log("VIOLATION "+v);
  ' "$1"
}

test_010_spec0132_canon_guard() {
  log_info "Test: the canon states the convention and classifies SPEC-0132 as an OWNER decision; no other file under .aai/** cites it, deny-by-default on repo-relative paths (TEST-010)..."
  [[ -f "$CANON" ]] || log_fail "TEST-010: canon file not found: $CANON"

  # ARM 1 — the canon text itself.
  local canon_text
  canon_text="$(cat "$CANON")"
  grep -qF "SPEC-0132" <<<"$canon_text" \
    || log_fail "TEST-010 arm 1: the canon must NAME SPEC-0132 — an unnamed precedent cannot be corrected"
  grep -qF "hitl_decision" <<<"$canon_text" \
    || log_fail "TEST-010 arm 1: the canon must cite SPEC-0132's hitl_decision record, not merely assert it was signed"
  # The ledger serializes this record's ts with milliseconds; the canon must
  # cite the form that can actually be looked up, not a tidied one.
  grep -qF "2026-08-15T08:14:24.000Z" <<<"$canon_text" \
    || log_fail "TEST-010 arm 1: the canon must cite the hitl_decision record's ledger timestamp (2026-08-15T08:14:24.000Z) so the claim is checkable"
  grep -qF "spec-amend.mjs" <<<"$canon_text" \
    || log_fail "TEST-010 arm 1: the canon must name the writer that makes the convention runnable"
  grep -qiF "not precedent" <<<"$canon_text" \
    || log_fail "TEST-010 arm 1: the canon must state in terms that SPEC-0132 is NOT precedent for proceeding unsigned"

  # ARM 2 — the live sweep over the real .aai tree.
  local live_sweep scanned
  live_sweep="$(spec0132_sweep "$PROJECT_ROOT/.aai")"
  scanned="$(node -e '
    const m=String(process.argv[1]).match(/^SCANNED (\d+)$/m);
    process.stdout.write(m ? m[1] : "0");
  ' "$live_sweep")"
  # A corpus-size FLOOR: a broken walk that scans nothing must fail loudly
  # rather than pass vacuously. Measured at 234 files at be0c8ed.
  [[ "$scanned" -ge 150 ]] \
    || log_fail "TEST-010 arm 2: the sweep scanned only $scanned files under .aai/ — a broken enumeration must never pass vacuously"
  grep -qF "VIOLATION" <<<"$live_sweep" \
    && log_fail "TEST-010 arm 2: a file under .aai/** cites SPEC-0132 outside the exemption — $live_sweep"

  # ARM 3 — the PLANTED violation, one directory down, sharing the exempted
  # file's BASENAME. A basename-matched allowlist passes this; a
  # repo-relative-path one does not.
  local plant="$TEST_DIR/plant"
  mkdir -p "$plant/system/nested"
  cp "$CANON" "$plant/system/AUTONOMOUS_LOOP.md"
  printf '%s\n' 'Proceeding unsigned here, following the precedent set by SPEC-0132.' \
    > "$plant/system/nested/AUTONOMOUS_LOOP.md"
  local plant_sweep
  plant_sweep="$(spec0132_sweep "$plant")"
  grep -qF "VIOLATION .aai/system/nested/AUTONOMOUS_LOOP.md" <<<"$plant_sweep" \
    || log_fail "TEST-010 arm 3: the planted nested file was NOT caught — the exemption is matching the basename, not the repo-relative path: $plant_sweep"
  # And the exempted path itself is still exempt in the same run, so arm 3 is
  # proving path-matching and not merely "everything fails".
  grep -qF "VIOLATION .aai/system/AUTONOMOUS_LOOP.md" <<<"$plant_sweep" \
    && log_fail "TEST-010 arm 3: the exempted repo-relative path was itself reported — the sweep is not honouring its own closed list: $plant_sweep"

  # ARM 4 — deny-by-default: an ARBITRARY new file citing SPEC-0132 anywhere
  # under the tree is a violation without being enumerated anywhere.
  printf '%s\n' 'see SPEC-0132 for why we may skip the sign-off' > "$plant/some-brand-new-prompt.md"
  local plant_sweep2
  plant_sweep2="$(spec0132_sweep "$plant")"
  grep -qF "VIOLATION .aai/some-brand-new-prompt.md" <<<"$plant_sweep2" \
    || log_fail "TEST-010 arm 4: a brand-new file citing SPEC-0132 was not denied — the sweep is not deny-by-default: $plant_sweep2"

  log_pass "TEST-010 the canon names SPEC-0132 as an owner decision and not precedent; the .aai/** sweep is deny-by-default on repo-relative paths ($scanned files scanned)"
}

# --- TEST-013 (validation round 1, F1) ----------------------------------------
# THE GATE'S OWN REFUSAL MUST NAME A REACHABLE FIXED POINT.
#
# `list --strict` is a fail-CLOSED backstop, so the role that hits it is by
# construction a role that has already gone wrong once. Every command its
# refusal names must therefore take the ledger OUT of the refusing state. Round
# 1 measured that none of them did: `spec-amend add` (named in
# .aai/SKILL_PR.prompt.md) left exit 1 AND appended a spurious second
# amendment, `follow-ups.mjs add` (named in the stderr) filed an item attached
# to nothing, and `classify` without `--tracked-by` (also named in the stderr)
# re-classified the record as exactly the bucket it was already in. The only
# working route existed in no prose at all.
#
# The strongest arm here does not construct a command from this file's own idea
# of the remedy — it READS the command out of the tool's refusal and runs THAT.
# A prose fix that drifts from the behaviour reddens here.
test_013_refusal_names_a_reachable_fixed_point() {
  log_info "Test: every remedy \`list --strict\` names actually clears \`list --strict\`, and the ones that do not are named as not doing it (TEST-013, validation F1)..."
  [[ -f "$FU" ]] || log_skip "follow-ups.mjs not found: $FU"
  local led spec suggested cmd n_before n_after
  led="$(mk_ledger t013)"
  spec="$(mk_spec t013-spec.md spec-t013-fixture)"

  # The R1 shape, and the shape all nine live records had before the backfill:
  # a hand-appended amendment that never went through the writer.
  printf '%s\n' '{"v":1,"ts":"2026-09-03T20:00:00Z","actor":"remediation","type":"spec_amendment","ref_id":"t013-ride","spec":"docs/specs/SPEC-DRAFT-spec-t013-fixture.md","spec_id":"spec-t013-fixture","owner_signoff":false,"what":"widened D3","why":"scope outgrew the frozen spec"}' >> "$led"
  n_before="$(count_amendments "$led")"
  [[ "$n_before" == 1 ]] || log_fail "TEST-013 setup: fixture must hold exactly 1 amendment, got $n_before"

  run_sa list --ledger "$led" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-013 setup: the fixture must refuse, got $EC"

  # ARM 1 — the refusal's OWN suggested command, read off its stderr, run
  # verbatim, and the gate must then reach 0. Placeholders are filled and the
  # fixture ledger is pointed at; nothing else about the line is rewritten.
  suggested="$(sed -n 's/^ *node \.aai\/scripts\/spec-amend\.mjs \(classify .*\)$/\1/p' <<<"$ERR" | head -1)"
  [[ -n "$suggested" ]] \
    || log_fail "TEST-013 arm 1: the --strict refusal must PRINT a runnable remedy naming the offending record; stderr was: $ERR"
  grep -qF 't013-ride' <<<"$suggested" \
    || log_fail "TEST-013 arm 1: the suggested remedy must carry the offending record's OWN ref, not a placeholder; got: $suggested"
  grep -qF '2026-09-03T20:00:00Z' <<<"$suggested" \
    || log_fail "TEST-013 arm 1: the suggested remedy must carry the offending record's OWN ts; got: $suggested"
  cmd="${suggested//<one line>/back-classified at the gate}"
  cmd="${cmd//<evidence>/tests/skills/test-aai-spec-amend.sh TEST-013}"
  EC=0
  eval "node \"\$SA\" $cmd --ledger \"\$led\"" > "$TEST_DIR/.stdout" 2> "$TEST_DIR/.stderr" || EC=$?
  OUT="$(cat "$TEST_DIR/.stdout")"; ERR="$(cat "$TEST_DIR/.stderr")"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-013 arm 1: the command the refusal itself printed must succeed, got $EC (stdout: $OUT) (stderr: $ERR)"

  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-013 arm 1: after running the ONLY command the refusal named, --strict must reach 0 — a refusal whose documented remedy leaves it refusing has no outflow, which is the defect this whole scope removes; got $EC (stdout: $OUT) (stderr: $ERR)"

  # ARM 2 — the item is REAL, asserted through the other tool, no mock (SEAM-2).
  run_fu list --ledger "$led" --status open
  grep -qF "fu-amend-spec-t013-fixture" <<<"$OUT" \
    || log_fail "TEST-013 arm 2: the co-created obligation must appear in the REAL follow-ups.mjs open list; stdout was: $OUT"
  grep -qF "spec-t013-fixture" <<<"$OUT" \
    || log_fail "TEST-013 arm 2: the obligation must NAME the spec whose sign-off is owed; stdout was: $OUT"

  # ARM 3 — clearing the gate must not grow the amendment population. `classify`
  # is an overlay writer; a remedy that appends a SECOND amendment has made the
  # ledger worse while claiming to fix it.
  n_after="$(count_amendments "$led")"
  [[ "$n_after" == "$n_before" ]] \
    || log_fail "TEST-013 arm 3: clearing the gate must append NO new spec_amendment record (append-only ledger), went $n_before -> $n_after"

  # ARM 4 — the two NON-remedies are named as such, and still do not work. This
  # pins the measurement that made F1 blocking, so no later edit can quietly
  # re-name `add` as the fix.
  local led2
  led2="$(mk_ledger t013b)"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T20:00:00Z","actor":"remediation","type":"spec_amendment","ref_id":"t013-ride","spec":"x","spec_id":"spec-t013-fixture","owner_signoff":false,"what":"widened D3","why":"y"}' >> "$led2"
  run_sa list --ledger "$led2" --strict
  grep -qF 'spec-amend.mjs add' <<<"$ERR" \
    || log_fail "TEST-013 arm 4: the refusal must say plainly that \`add\` is NOT the remedy; stderr was: $ERR"
  grep -qF 'follow-ups.mjs add' <<<"$ERR" \
    || log_fail "TEST-013 arm 4: the refusal must say plainly that \`follow-ups.mjs add\` is NOT the remedy; stderr was: $ERR"
  run_sa add --ledger "$led2" --spec "$spec" --ref t013-ride \
    --what "widened D3" --why "scope outgrew the frozen spec" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-013 arm 4: \`add\` must still never refuse (D2 fail-OPEN), got $EC"
  run_sa list --ledger "$led2" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-013 arm 4: \`add\` must NOT clear a pre-existing untracked record — it records a NEW amendment; got $EC"
  [[ "$(count_amendments "$led2")" == 2 ]] \
    || log_fail "TEST-013 arm 4: \`add\` appends a second amendment, which is exactly why it is not the remedy"

  # ARM 5 — the prose the role actually reads names the working route, and no
  # longer names the one that leaves the gate red.
  local gate_bullet
  gate_bullet="$(sed -n '/AMENDMENT GATE/,/^   - /p' "$PROJECT_ROOT/.aai/SKILL_PR.prompt.md")"
  [[ -n "$gate_bullet" ]] || log_fail "TEST-013 arm 5: .aai/SKILL_PR.prompt.md has no AMENDMENT GATE bullet"
  grep -qF 'spec-amend.mjs classify' <<<"$gate_bullet" \
    || log_fail "TEST-013 arm 5: the AMENDMENT GATE bullet must name the remedy that CLEARS the gate; bullet was: $gate_bullet"
  # `add` may be NAMED here, but only as the thing not to run. The round-1
  # bullet offered it ("file the missing obligation (`spec-amend.mjs add`)"),
  # which is the exact wording this arm exists to keep out.
  if grep -qF 'spec-amend.mjs add' <<<"$gate_bullet"; then
    grep -qF 'never `spec-amend.mjs add`' <<<"$gate_bullet" \
      || log_fail "TEST-013 arm 5: the AMENDMENT GATE bullet may mention \`spec-amend.mjs add\` ONLY to rule it out — it does not clear a record the gate already named; bullet was: $gate_bullet"
  fi
  grep -qF 'spec-amend.mjs classify' "$CANON" \
    || log_fail "TEST-013 arm 5: AUTONOMOUS_LOOP.md section 6a must name the remedy for a red gate, not only the writer"

  # ARM 6 — `--tracked-by` still wins when given (the backfill route, unchanged),
  # and an owner classification owes no item at all.
  local led3
  led3="$(mk_ledger t013c)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t013-explicit","spec_id":"spec-t013-explicit","owner_signoff":false}' >> "$led3"
  printf '%s\n' '{ "v":1, "ts":"2026-09-01T07:00:00Z", "actor":"a", "type": "spec_amendment", "ref_id":"t013-absent", "spec_id":"spec-t013-absent" }' >> "$led3"
  run_sa classify --ledger "$led3" --ts "2026-09-01T06:00:00Z" --ref t013-explicit \
    --signoff none --why "w" --source "s" --tracked-by fu-amend-chosen-by-hand
  [[ "$EC" == 0 ]] || log_fail "TEST-013 arm 6: an explicit --tracked-by must still be honoured, got $EC (stderr: $ERR)"
  run_fu list --ledger "$led3" --status open
  grep -qF "fu-amend-chosen-by-hand" <<<"$OUT" \
    || log_fail "TEST-013 arm 6: the EXPLICIT id must be the one filed, never a derived one; stdout was: $OUT"
  grep -qF "fu-amend-spec-t013-explicit" <<<"$OUT" \
    && log_fail "TEST-013 arm 6: no derived id may be filed alongside the explicit one (that is an orphan item); stdout was: $OUT"
  run_sa classify --ledger "$led3" --ts "2026-09-01T07:00:00Z" --ref t013-absent \
    --signoff owner --why "the owner decided" --source "hitl_decision record"
  [[ "$EC" == 0 ]] || log_fail "TEST-013 arm 6: an owner classification must succeed, got $EC (stderr: $ERR)"
  run_fu list --ledger "$led3" --status open
  grep -qF "fu-amend-spec-t013-absent" <<<"$OUT" \
    && log_fail "TEST-013 arm 6: an OWNER-signed classification owes no obligation and must file none; stdout was: $OUT"
  run_sa list --ledger "$led3" --strict
  [[ "$EC" == 0 ]] || log_fail "TEST-013 arm 6: both routes together must clear the gate, got $EC (stdout: $OUT)"

  log_pass "TEST-013 the refusal prints a runnable remedy, that remedy clears the gate in ONE call without growing the amendment population, and the two non-remedies are named as such"
}

# --- TEST-014 (validation round 1, NB-2) --------------------------------------
# The gate's reach and the excuse's reach point in OPPOSITE directions.
test_014_whitespace_type_cannot_evade_the_gate() {
  log_info "Test: a \`type\` value carrying stray whitespace is still caught by --strict, while a whitespace-typed follow_up still does NOT excuse an amendment (TEST-014, validation NB-2)..."
  local led led2
  led="$(mk_ledger t014)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:00:00Z","actor":"a","type":" spec_amendment ","ref_id":"t014-padded","spec_id":"spec-t014","owner_signoff":false}' >> "$led"
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-014: a record whose \`type\` reads as an amendment to any human must not be invisible to the GATE, got $EC (stdout: $OUT)"
  grep -qF "t014-padded" <<<"$OUT" \
    || log_fail "TEST-014: --strict must NAME the padded record; stdout was: $OUT"

  # The opposite direction, on purpose: over-detecting what EXCUSES an
  # amendment would launder one, so the follow-up types stay exact-match.
  led2="$(mk_ledger t014b)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t014-excuse","spec_id":"spec-t014b","owner_signoff":false,"tracked_by":"fu-amend-spec-t014b"}' >> "$led2"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:30:00Z","actor":"a","type":" follow_up ","id":"fu-amend-spec-t014b","ref_id":"t014-excuse","severity":"P2","finding":"f","decision":"d","source":"s"}' >> "$led2"
  run_sa list --ledger "$led2" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-014: a padded follow_up is not an obligation any registry reader can drain, so it must NOT excuse the amendment; got $EC (stdout: $OUT)"
  grep -qF "unsigned-untracked" <<<"$OUT" \
    || log_fail "TEST-014: the amendment excused only by a padded follow_up must stay unsigned-untracked; stdout was: $OUT"

  log_pass "TEST-014 the trim widens what the gate CATCHES and never what EXCUSES it — the two error directions stay opposite"
}

test_015_unmatchable_record_gets_an_honest_refusal() {
  log_info "Test: a record classify cannot match must be told so, not handed a placeholder it can never fill (TEST-015, validation OBS-1)..."
  local led led2
  led="$(mk_ledger t015)"
  # No `ts`. `classify` keys on the ts+ref pair, so no invocation can reach
  # this record. Neither writer can emit it (`add` always stamps both), so
  # this shape only exists on a hand-appended ledger.
  printf '%s\n' '{"v":1,"type":"spec_amendment","ref_id":"t015-no-ts","spec_id":"spec-t015","owner_signoff":false}' >> "$led"
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-015: an unmatchable record must still violate, got $EC (stdout: $OUT)"
  if grep -qF 'classify --ts "<ts>"' <<<"$ERR"; then
    log_fail "TEST-015: printing a <ts> placeholder is a remedy that cannot be run — the exact defect F1 removed, one shape down; stderr was: $ERR"
  fi
  grep -qF "no runnable remedy" <<<"$ERR" \
    || log_fail "TEST-015: the refusal must SAY the record is unmatchable rather than implying a command exists; stderr was: $ERR"
  grep -qF "carries no ts" <<<"$ERR" \
    || log_fail "TEST-015: the refusal must name WHICH field is missing, or the operator cannot act on it; stderr was: $ERR"

  # CONTROL, opposite direction: a well-formed record must still get a real,
  # runnable command — the honesty branch must not swallow the happy path.
  led2="$(mk_ledger t015b)"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T20:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t015-ok","spec_id":"spec-t015b","owner_signoff":false}' >> "$led2"
  run_sa list --ledger "$led2" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-015 control: a well-formed violation must still exit 1, got $EC"
  grep -qF 'classify --ts "2026-09-03T20:00:00Z" --ref "t015-ok"' <<<"$ERR" \
    || log_fail "TEST-015 control: a matchable record must still be handed its own runnable line; stderr was: $ERR"
  if grep -qF "no runnable remedy" <<<"$ERR"; then
    log_fail "TEST-015 control: the honesty branch must not fire on a record classify CAN match; stderr was: $ERR"
  fi

  log_pass "TEST-015 an unmatchable record is told so by name; a matchable one still gets its runnable command"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-unsigned-spec-amendment-has-no-outflow TEST-001..010)"
  check_deps
  setup_fixture
  test_001_add_creates_both_records
  test_002_rejected_input_and_never_refuses
  test_003_live_ledger_format_trap
  test_004_seam2_read_back_through_follow_ups
  test_005_three_buckets_field_over_prose
  test_006_seam1_survives_the_rename
  test_007_both_strict_arms
  test_008_append_only
  test_009_live_backfill_and_whole_ledger_readers
  test_010_spec0132_canon_guard
  test_013_refusal_names_a_reachable_fixed_point
  test_014_whitespace_type_cannot_evade_the_gate
  test_015_unmatchable_record_gets_an_honest_refusal
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
