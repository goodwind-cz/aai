#!/usr/bin/env bash
#
# Test: aai-spec-amend
# (docs/specs/SPEC-0165-spec-unsigned-spec-amendment-has-no-outflow.md,
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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SA="$PROJECT_ROOT/.aai/scripts/spec-amend.mjs"
FU="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
SF="$PROJECT_ROOT/.aai/scripts/spec-freeze.mjs"
ROUTINE_EMIT="$PROJECT_ROOT/.aai/scripts/routine-emit.mjs"
LIVE_LEDGER="$PROJECT_ROOT/docs/ai/decisions.jsonl"
CANON="$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md"

# The specs whose amendments stand UNSIGNED are derived from the live ledger
# at run time (spec-amend list --status unsigned --json), never pinned: the
# five that stood unsigned when this scope was written were signed off by the
# owner on 2026-09-14 (menu answer A), and a pinned list then demanded an OPEN
# item for a spec whose decision had already been taken — the pin-instead-of-
# property shape this repository keeps finding. unsigned_spec_ids prints one
# spec id per line; signed_spec_ids the complement, for the negative control.
unsigned_spec_ids() {
  node "$SA" list --ledger "$LIVE_LEDGER" --status unsigned --json 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const ids=[...new Set((j.items||[]).map(r=>r.spec_id).filter(Boolean))];console.log(ids.join("\n"))})'
}
# tracked_by ids of one spec's unsigned records (one per line). A spec whose base
# item was already closed by an owner signature gets a NEW disambiguated item on
# its next amendment (spec-amend.mjs stamped id), so the open item is whichever
# id the unsigned records point at, not only the base id.
unsigned_tracker_ids_for() {  # <spec id>
  node "$SA" list --ledger "$LIVE_LEDGER" --status unsigned --json 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log([...new Set((j.items||[]).filter(r=>r.spec_id===process.argv[1]&&r.tracked_by).map(r=>r.tracked_by))].join("\n"))})' "$1"
}
# Tracked items whose EVERY amendment record is signed (keyed on tracked_by,
# so records with no spec path count too) — these must carry no OPEN item.
fully_signed_tracked_ids() {
  node "$SA" list --ledger "$LIVE_LEDGER" --status all --json 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);const by={};for(const r of (j.items||[])){const t=r.tracked_by;if(!t)continue;by[t]=by[t]||{s:0,u:0};(String(r.bucket||"").startsWith("signed")?by[t].s++:by[t].u++)}console.log(Object.entries(by).filter(([,v])=>v.s>0&&v.u===0).map(([t])=>t).join("\n"))})'
}

# Measured at the base commit be0c8ed. The comment used to say this pin "cannot
# rot as later rides append", while the code read it from the MOVING `origin/main`
# — so the moment PR #337 merged six amendments the count went 10 -> 16 and the
# arm failed on main for everyone, not just on the branch that added them. The
# claim was right and the reference was wrong; the immutable SHA below is what
# the claim always described. TEST-003 asserts the live tree separately, as a
# FLOOR plus an independent recount, which is what tracks later rides.
BASE_AMENDMENT_PIN_COMMIT=be0c8edb53705285063a984cbb0e6304f36db164
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

# --- D11 helpers (SPEC-DRAFT spec-mutation-gate-for-tests TEST-482..485) -----

# mk_freezable_spec <relpath-under-TEST_DIR> <id> [strategy] -> path to a NEW,
# not-yet-frozen fixture spec carrying a minimal AC table + Test Plan, so the
# REAL spec-freeze.mjs (not a hand-written marker) can stamp `frozen_sha256`
# on it — TEST-482/483/484 all need a GENUINE anchor, produced by the tool
# that owns writing one, never faked.
mk_freezable_spec() {
  local f="$TEST_DIR/$1" id="$2" strategy="${3:-direct}"
  mkdir -p "$(dirname "$f")"
  {
    echo "---"
    echo "id: $id"
    echo "type: spec"
    echo "number: null"
    echo "status: draft"
    echo "---"
    echo ""
    echo "# fixture $id"
    echo ""
    echo "## Implementation strategy"
    echo "- Strategy: $strategy"
    echo ""
    echo "## Acceptance Criteria Status"
    echo ""
    echo "| Spec-AC    | Description | Status | Evidence | Review-By | Notes |"
    echo "|------------|-------------|--------|----------|-----------|-------|"
    echo "| Spec-AC-01 | original description text | planned | — | — | |"
    echo ""
    echo "## Test Plan"
    echo ""
    echo "| Test ID | Spec-AC | Type | File path (expected) | Description | Status |"
    echo "|---------|---------|------|-----------------------|--------------|--------|"
    echo "| TEST-001 | Spec-AC-01 | unit | tests/x.sh | does the thing | pending |"
  } > "$f"
  printf '%s' "$f"
}

# freeze_spec <path> -> runs the REAL spec-freeze.mjs against it (no ledger
# event, this is a scratch fixture). Returns non-zero and logs the refusal
# reason on failure, so a caller's own setup assertion names the real cause.
freeze_spec() {
  local out rc=0
  out="$(node "$SF" --path "$1" --no-event 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || log_info "freeze_spec: spec-freeze.mjs refused $1 (rc=$rc): $out"
  return "$rc"
}

# contract_hash_of <path> -> the CURRENT contract-projection hash of a spec
# file, computed by importing lib/spec-contract-hash.mjs directly — never by
# re-deriving the projection by hand, which would let this suite and the
# module under test silently drift apart.
contract_hash_of() {
  node --input-type=module -e "
    import { contractHash } from '$PROJECT_ROOT/.aai/scripts/lib/spec-contract-hash.mjs';
    import fs from 'node:fs';
    process.stdout.write(contractHash(fs.readFileSync(process.argv[1], 'utf8')));
  " "$1"
}

# frozen_sha256_of <path> -> the STORED anchor (frontmatter field), by a plain
# sed read (never through the tool under test, for the same independence
# reason contract_hash_of exists).
frozen_sha256_of() {
  sed -n 's/^frozen_sha256:[ \t]*//p' "$1" | qhead -1
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

# last_amendment_for <ledger> <ref_id> -> the LAST spec_amendment record
# whose ref_id matches, as one JSON line (empty if none) — independent of the
# tool under test, and immune to a follow_up record the SAME `restamp`/`add`
# call appends right after it in the same ledger.
last_amendment_for() {
  node -e '
    const fs=require("fs");
    const raw=fs.readFileSync(process.argv[1],"utf8");
    let found="";
    for (const line of raw.split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment" && r.ref_id===process.argv[2]) found=t;
    }
    process.stdout.write(found);
  ' "$1" "$2"
}

# json_field <json> <node-expression over `j`>
json_field() {
  # The JSON arrives on STDIN, never as argv: `list --json` over the LIVE ledger
  # is ~940 KB today and Linux caps a single argv entry at 128 KiB, so passing it
  # as an argument died with `node: Argument list too long` on CI while passing
  # on macOS, whose limit is ~1 MB. The ledger only grows, so this was going to
  # bite every ride from here on, not just the one that crossed the line.
  printf '%s' "$1" | node -e '
    let raw = "";
    process.stdin.on("data", (d) => { raw += d; });
    process.stdin.on("end", () => {
      let j; try { j=JSON.parse(raw); } catch (e) { console.log("UNPARSEABLE:"+e.message); process.exit(0); }
      console.log(String(eval(process.argv[1])));
    });
  ' "$2"
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
  local ok=1

  # The pin reads an IMMUTABLE COMMIT, never the moving base ref: origin/main
  # gains amendments as later rides merge, and an equality against a moving
  # target is a landmine for whoever merges next.
  if git -C "$PROJECT_ROOT" show "$BASE_AMENDMENT_PIN_COMMIT:docs/ai/decisions.jsonl" > "$TEST_DIR/base.jsonl" 2>/dev/null; then
    local base_parsed base_tight
    base_parsed="$(count_amendments "$TEST_DIR/base.jsonl")"
    base_tight="$(/usr/bin/grep -c '"type":"spec_amendment"' "$TEST_DIR/base.jsonl" || true)"
    [[ "$base_parsed" == "$BASE_AMENDMENT_COUNT" ]] \
      || log_fail "TEST-003: the base ledger must carry exactly $BASE_AMENDMENT_COUNT spec_amendment records when parsed as JSON, counted $base_parsed"
    [[ "$base_tight" == "$BASE_TIGHT_GREP_COUNT" ]] \
      || log_fail "TEST-003: the tight grep must still under-report the base ledger at $BASE_TIGHT_GREP_COUNT (the trap this arm exists for), counted $base_tight"
    log_info "TEST-003: pinned ${BASE_AMENDMENT_PIN_COMMIT:0:7} ledger — parsed=$base_parsed tight-grep=$base_tight (the 60% undercount)"
  else
    # R2-1 (validation round 2): a missing pin commit used to soft-skip this
    # arm (log_info, ok left unset) — the base-vs-live format trap this test
    # exists for was never checked and the arm still log_passed. A shallow
    # clone or fetch-less CI checkout is the real-world version of this
    # branch, and it is exactly the DEBT-0004 shape AC-14 forbids. FAILS
    # CLOSED: the 10-vs-4 base-ledger trap cannot be demonstrated without the
    # pinned commit, so it is refused and named rather than silently skipped.
    log_info "TEST-003: pin commit ${BASE_AMENDMENT_PIN_COMMIT:0:7} unreachable (shallow clone) — the base-ledger format trap cannot be verified here; FAILING CLOSED (this is a missing commit, NOT a detected defect)"
    ok=0
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
    // argv[1] is the PATH run_sa wrote stdout to, never the payload: `list --json`
    // is ~135 KB and Linux caps one argv entry at 128 KiB (macOS ~1 MB), so passing
    // the content was a CI-only `Argument list too long`.
    const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
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
  ' "$TEST_DIR/.stdout" "$LIVE_LEDGER")"
  [[ -z "$missing" ]] \
    || log_fail "TEST-003: space-serialized records missing from \`list --json\`: $missing"

  [[ $ok -eq 1 ]] \
    && log_pass "TEST-003 live ledger: parsed=$parsed (>= $BASE_AMENDMENT_COUNT), tight-grep=$tight, $spaced space-serialized records all reported" \
    || log_fail "TEST-003 the base-ledger format trap is UNCOVERED (pin commit unreachable) — see the INFO line above"
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
  # exists to prevent (TWO of the five live spec ids fit at 38 and 37 chars;
  # THREE do not at 44, 47 and 55 — one shortened, two hashed).
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
    // argv[1] is a PATH, not the payload — see the note at TEST-003.
    let j; try { j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); } catch (e) { console.log("UNPARSEABLE:"+e.message); process.exit(0); }
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
  ' "$TEST_DIR/.stdout")"
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
  local led before ok=1
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
    # R2-1 (validation round 2): a missing base ref used to soft-skip this
    # arm (log_info, ok left unset) — the live ledger's append-only claim
    # against a real pre-change base was never checked and the arm still
    # log_passed. A shallow clone or fetch-less CI checkout is the real-world
    # version of this branch. FAILS CLOSED: the live-append-only claim cannot
    # be demonstrated without the base ref, so it is refused and named rather
    # than silently skipped.
    log_info "TEST-008: base ref $BASE_REF has no docs/ai/decisions.jsonl — the live append-only arm cannot be verified here; FAILING CLOSED (this is a missing ref, NOT a detected rewrite)"
    ok=0
  fi

  [[ $ok -eq 1 ]] \
    && log_pass "TEST-008 both write paths append only; the pre-change bytes survive byte-exact and a planted rewrite is rejected" \
    || log_fail "TEST-008 the live append-only arm is UNCOVERED (base ref unresolvable) — see the INFO line above"
}

# --- TEST-009 (Spec-AC-07) — post-backfill live state + SEAM-4 ---------------

test_009_live_backfill_and_whole_ledger_readers() {
  log_info "Test: the LIVE ledger after the backfill — \`list --strict\` exits 0, every record carries an effective classification, one open item per unsigned spec, and the whole-ledger readers still work (TEST-009)..."
  [[ -f "$FU" ]] || log_skip "follow-ups.mjs not found: $FU"
  local ok=1

  run_sa list --ledger "$LIVE_LEDGER" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-009: \`list --strict\` over the live ledger must exit 0 after the backfill, got $EC (stdout: $OUT) (stderr: $ERR)"

  run_sa list --ledger "$LIVE_LEDGER" --status unclassified --json
  [[ "$(json_field "$OUT" 'j.counts.unclassified')" == 0 ]] \
    || log_fail "TEST-009: the live ledger still carries unclassified amendments: $OUT"

  # One OPEN tracked item per unsigned spec, named through the REAL reader.
  run_fu list --ledger "$LIVE_LEDGER" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-009: follow-ups.mjs list must exit 0 over the live ledger, got $EC (stderr: $ERR)"
  local open_out="$OUT"
  # validation round 5 BLOCKING-2: this arm used to derive its expected id
  # and then `grep -qF "$expect" <<<"$open_out"` — a SUBSTRING match against
  # the whole human-readable rendering, descriptions included. A retrack
  # item's own description prose ("...the previous tracker fu-amend-x was
  # dropped...") contains the OLD id as text, so that grep was satisfied by
  # the id being QUOTED, never by an OPEN item actually carrying it. Anchor
  # on the item ID TOKEN instead: pull `--json`'s `items[].id` (the field the
  # fold actually keys items by) and exact-match (`grep -qxF`) against that
  # list, never the free-text row.
  run_fu list --ledger "$LIVE_LEDGER" --status open --json
  [[ "$EC" == 0 ]] || log_fail "TEST-009: follow-ups.mjs list --json must exit 0 over the live ledger, got $EC (stderr: $ERR)"
  local open_ids sid missing="" unsigned_ids
  open_ids="$(node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const j=JSON.parse(s);
      process.stdout.write((j.items||[]).map((i)=>i.id).join("\n"));
    });
  ' <<<"$OUT")"
  unsigned_ids="$(unsigned_spec_ids)"
  [[ -n "$unsigned_ids" ]] || log_info "TEST-009: no unsigned amendment in the live ledger — the open-item arm has nothing to check (the signed-set control below still runs)"
  for sid in $unsigned_ids; do
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
    if grep -qxF "$expect" <<<"$open_ids"; then continue; fi
    # Fallback for a re-amended spec whose base item was signed and closed:
    # EVERY tracker its unsigned records name must be OPEN and must be this
    # spec's own (the stamped id shares the base id's stem), so a record
    # borrowing another spec's open item, or one left on a closed item, fails.
    local trk found=0 bad=0 stem="${expect%-*}-"
    for trk in $(unsigned_tracker_ids_for "$sid"); do
      found=1
      [[ "$trk" == "$stem"* ]] || bad=1
      grep -qxF "$trk" <<<"$open_ids" || bad=1
    done
    [[ "$found" == 1 && "$bad" == 0 ]] || missing="$missing $sid($expect)"
  done
  [[ -z "$missing" ]] \
    || log_fail "TEST-009: no OPEN tracked item for:$missing — the standing amendments are not surfaced for an owner decision (checked as an id TOKEN against --json items[].id, not a substring of the rendering)"
  # Negative control: a tracked item whose amendment records are ALL signed
  # carries no OPEN follow-up any more (the owner decision closed it) — so the
  # arm above discriminates signed from unsigned rather than demanding an item
  # for everything ever amended. Keyed on tracked_by so records with no spec
  # path count. Requires at least one fully signed item to be a real control;
  # this ledger has had seven since 2026-09-14.
  local signed_items tid signed_checked=0 still_open=""
  signed_items="$(fully_signed_tracked_ids)"
  for tid in $signed_items; do
    signed_checked=$((signed_checked+1))
    grep -qxF -- "$tid" <<<"$open_ids" && still_open="$still_open $tid"
  done
  [[ "$signed_checked" -ge 1 ]] \
    || log_fail "TEST-009: the signed-set control checked zero items — a control that checks nothing proves nothing"
  [[ -z "$still_open" ]] \
    || log_fail "TEST-009: a fully SIGNED amendment item is still OPEN:$still_open — the owner decision was taken but the item was not closed"
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
    # R2-1 (validation round 2): an unresolvable base ref used to soft-skip
    # this arm (log_info, ok left unset) — the untouched-frozen-specs claim
    # was never checked and the arm still log_passed. A shallow clone or
    # fetch-less CI checkout is the real-world version of this branch. FAILS
    # CLOSED: the claim cannot be demonstrated without the base ref, so it is
    # refused and named rather than silently skipped.
    log_info "TEST-009: base ref $BASE_REF not resolvable — the untouched-frozen-specs arm cannot be verified here; FAILING CLOSED (this is a missing ref, NOT a detected edit)"
    ok=0
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
    # R2-1 (validation round 2): a missing routine-emit.mjs used to soft-skip
    # this arm (log_info, ok left unset) — the whole-ledger-reader tolerance
    # claim was never checked and the arm still log_passed. FAILS CLOSED: the
    # SEAM-4 tolerance claim cannot be demonstrated without the script, so it
    # is refused and named rather than silently skipped.
    log_info "TEST-009: routine-emit.mjs not found — the SEAM-4 whole-ledger-reader arm cannot be verified here; FAILING CLOSED (this is a missing script, NOT a detected intolerance)"
    ok=0
  fi

  [[ $ok -eq 1 ]] \
    && log_pass "TEST-009 the live ledger is strict-clean, every unsigned spec has one open item, no frozen spec body was edited, and the whole-ledger readers tolerate the new types" \
    || log_fail "TEST-009 UNCOVERED (base ref or routine-emit.mjs unavailable) — see the INFO line(s) above"
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
  suggested="$(sed -n 's/^ *node \.aai\/scripts\/spec-amend\.mjs \(classify .*\)$/\1/p' <<<"$ERR" | qhead -1)"
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
  # Quoting-agnostic (Spec-AC-22 moved these lines from JSON.stringify to the
  # shq helper): the property is that NO ts placeholder is printed at all,
  # not that one particular quote character does not precede it.
  if grep -qF '<ts>' <<<"$ERR"; then
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
  # Single quotes since Spec-AC-22: the printed remedies now go through `shq`
  # (POSIX single-quote wrapping), which is what makes them runnable when a
  # ts, a ref or a path carries whitespace or a shell metacharacter.
  grep -qF "classify --ts '2026-09-03T20:00:00Z' --ref 't015-ok'" <<<"$ERR" \
    || log_fail "TEST-015 control: a matchable record must still be handed its own runnable line; stderr was: $ERR"
  if grep -qF "no runnable remedy" <<<"$ERR"; then
    log_fail "TEST-015 control: the honesty branch must not fire on a record classify CAN match; stderr was: $ERR"
  fi

  log_pass "TEST-015 an unmatchable record is told so by name; a matchable one still gets its runnable command"
}

test_016_closed_item_cannot_excuse_a_new_amendment() {
  log_info "Test: --tracked-by naming a DISCHARGED obligation is refused, and the refusal's own named remedy works (TEST-016, code review NB-B/NB-E)..."
  local led out ec
  led="$(mk_ledger t016)"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T21:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t016","spec_id":"spec-t016","owner_signoff":false}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T21:01:00Z","actor":"a","type":"follow_up","id":"fu-amend-spec-t016","ref_id":"t016","severity":"P2","finding":"f","decision":"d","source":"s"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T21:02:00Z","actor":"a","type":"follow_up_status","id":"fu-amend-spec-t016","status":"done","resolved_by":"x"}' >> "$led"
  local before after
  before="$(wc -l < "$led")"

  run_sa classify --ts "2026-09-03T21:00:00Z" --ref t016 --signoff none \
    --tracked-by fu-amend-spec-t016 --why w --source s --ledger "$led"
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-016: attaching a new amendment to a DISCHARGED obligation marks it signed by an owner who never saw it — pickAmendItemId's own comment forbids exactly this, so --tracked-by must not be a way around it; got $EC"
  grep -qF "already done" <<<"$ERR" \
    || log_fail "TEST-016: the refusal must say the item is discharged; stderr was: $ERR"
  after="$(wc -l < "$led")"
  [[ "$before" == "$after" ]] \
    || log_fail "TEST-016: a refusal must write NOTHING (HAZ-LEDGER); ledger went $before -> $after"

  # The refusal names a remedy. F1 was a refusal whose remedy did not clear
  # it, so this arm proves the named route actually reaches a green gate AND
  # leaves a DRAINABLE item — an obligation the owner cannot see is the very
  # defect this script removes.
  grep -qF "Drop --tracked-by and re-run" <<<"$ERR" \
    || log_fail "TEST-016: the refusal must NAME the remedy; stderr was: $ERR"
  run_sa classify --ts "2026-09-03T21:00:00Z" --ref t016 --signoff none --why w --source s --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-016: the named remedy must run, got $EC (stderr: $ERR)"
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] || log_fail "TEST-016: the named remedy must take the gate to 0, got $EC (stdout: $OUT)"
  out="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status open --ledger "$led" 2>&1)" || true
  grep -qF "fu-amend-spec-t016" <<<"$out" \
    || log_fail "TEST-016: the reopened obligation must be DRAINABLE — a green gate whose \`--status open\` list is empty is an obligation with no outflow; list was: $out"

  # NB-E: a ref carrying a double quote is reachable through \`add\`, and
  # TEST-013 runs the printed line through eval.
  local led2
  led2="$(mk_ledger t016b)"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T22:00:00Z","actor":"a","type":"spec_amendment","ref_id":"quote\"ride","spec_id":"spec-t016b","owner_signoff":false}' >> "$led2"
  run_sa list --ledger "$led2" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-016 NB-E: the quoted-ref record must still violate, got $EC"
  # Since Spec-AC-22 the remedies are wrapped by `shq` (POSIX single quotes),
  # in which a double quote needs no escape at all — so the property is tested
  # the only way that cannot rot with the quoting style: the printed line is
  # RUN, and the ref it carries must round-trip into the ledger intact.
  local nbe_line nbe_l nbe_rc nbe_out
  nbe_line=""
  while IFS= read -r nbe_l; do
    case "$nbe_l" in *"spec-amend.mjs classify "*) nbe_line="$nbe_l" ;; esac
  done <<<"$ERR"
  [[ -n "$nbe_line" ]] \
    || log_fail "TEST-016 NB-E: the quoted-ref violation must still PRINT a classify remedy; stderr was: $ERR"
  nbe_rc=0
  # --ledger is appended because the printed line names none (it is written
  # for an operator standing in the repo root); the FIXTURE ledger is the one
  # under test and the live tree must stay read-only here.
  eval "node \"\$SA\" classify ${nbe_line#*spec-amend.mjs classify } --ledger \"\$led2\"" > "$TEST_DIR/.t016b.out" 2>&1 || nbe_rc=$?
  [[ "$nbe_rc" == 0 ]] \
    || log_fail "TEST-016 NB-E: a ref containing a double quote must survive the printed remedy, or the line breaks when pasted; the line exited $nbe_rc.
LINE: $nbe_line
OUTPUT: $(cat "$TEST_DIR/.t016b.out")"
  nbe_out="$(node "$SA" list --ledger "$led2" --json 2>&1)"
  grep -qF 'quote\"ride' <<<"$nbe_out" \
    || log_fail "TEST-016 NB-E: the ref must round-trip through the printed remedy unchanged; list --json was: $nbe_out"

  log_pass "TEST-016 a discharged obligation cannot excuse a new amendment, the refusal's named remedy reaches a green gate with a drainable item, and a quoted ref stays pasteable"
}

test_017_reopen_never_lands_on_a_discharged_item() {
  log_info "Test: the automatic reopen keeps searching past DISCHARGED ids — a green gate whose drain list is empty is the failure this script exists to prevent (TEST-017, external review)..."
  local led stamp open_count
  led="$(mk_ledger t017)"
  # The stamp is taken from the classification's OWN clock, so seed the ids
  # this run will actually try. A single retry was not enough: with the base
  # and the first stamped id both closed, the one fallback landed on another
  # discharged item.
  stamp="$(node -e 'const d=new Date();const p=n=>String(n).padStart(2,"0");console.log(`${d.getUTCFullYear()}${p(d.getUTCMonth()+1)}${p(d.getUTCDate())}t${p(d.getUTCHours())}${p(d.getUTCMinutes())}`)')"
  printf '%s\n' '{"v":1,"ts":"2026-09-03T21:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t017","spec_id":"spec-t017","owner_signoff":false}' >> "$led"
  local id
  for id in "fu-amend-spec-t017" "fu-amend-spec-t017-${stamp}" "fu-amend-spec-t017-${stamp}-2"; do
    printf '%s\n' "{\"v\":1,\"ts\":\"2026-09-03T20:00:00Z\",\"actor\":\"a\",\"type\":\"follow_up\",\"id\":\"${id}\",\"ref_id\":\"t017\",\"severity\":\"P2\",\"finding\":\"f\",\"decision\":\"d\",\"source\":\"s\"}" >> "$led"
    printf '%s\n' "{\"v\":1,\"ts\":\"2026-09-03T20:01:00Z\",\"actor\":\"a\",\"type\":\"follow_up_status\",\"id\":\"${id}\",\"status\":\"done\",\"resolved_by\":\"x\"}" >> "$led"
  done

  run_sa classify --ts "2026-09-03T21:00:00Z" --ref t017 --signoff none --why w --source s --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-017: the reopen must succeed, got $EC (stderr: $ERR)"
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] || log_fail "TEST-017: the gate must reach 0 after the reopen, got $EC (stdout: $OUT)"

  # THE ASSERTION THAT MATTERS. A green gate is worthless if the obligation it
  # points at is already discharged: `follow-ups.mjs list --status open` is the
  # drain list the refusal itself advertises, and it must not be empty.
  open_count="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status open --ledger "$led" 2>&1 | grep -c "fu-amend-spec-t017" || true)"
  [[ "$open_count" -ge 1 ]] \
    || log_fail "TEST-017: the gate went green while EVERY fu-amend-spec-t017 item is discharged — an obligation with no outflow, which is the defect this whole script removes"

  log_pass "TEST-017 the reopen searches past discharged ids, so a green gate always leaves a drainable obligation"
}

# --- TEST-018: the tracked item names the spec by ID, never by PATH -----------
# A draft path dies when allocate-doc-number.mjs renames the file. This ledger is
# append-only, so a path written here can never be corrected — and it then lands
# in a generated page and fails the doc-numbering stale-draft-ref guard forever.
# Cost one CI failure on PR #337 before it was found.
test_018_item_names_spec_by_id_not_path() {
  log_info "Test: the manufactured follow-up carries no spec PATH (TEST-018)..."
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/aai-amend-path.XXXXXX")"
  mkdir -p "$d/docs/specs"
  printf -- '---\nid: spec-a-topic\ntype: spec\nnumber: null\nstatus: implementing\n---\n\nSPEC-FROZEN: true\n' \
    > "$d/docs/specs/SPEC-DRAFT-spec-a-topic.md"
  : > "$d/ledger.jsonl"
  node "$SA" add --spec "$d/docs/specs/SPEC-DRAFT-spec-a-topic.md" --ref a-topic \
    --what "a change" --why "a reason" --signoff none --ledger "$d/ledger.jsonl" >/dev/null 2>&1 \
    || log_fail "TEST-018: add must succeed"
  # Only the FOLLOW_UP record. The spec_amendment record's `amends` field is a
  # path on purpose — it states which file was amended at that moment, a
  # historical fact, and nothing renders it into a generated page. The follow-up
  # IS rendered (factory-report lists open items), so a path there is the trap.
  local fu; fu="$(grep -F '"follow_up"' "$d/ledger.jsonl" | qhead -1)"
  [ -n "$fu" ] || log_fail "TEST-018: add must manufacture a follow_up record"
  case "$fu" in *SPEC-DRAFT-*) log_fail "TEST-018: the follow-up must not embed a DRAFT path — it dies at allocation and this ledger is append-only: $fu";; esac
  case "$fu" in *spec-a-topic*) ;; *) log_fail "TEST-018: the follow-up must still name the spec by its frontmatter id: $fu";; esac
  rm -rf "$d"
  log_pass "the tracked item names the spec by id, not by path (TEST-018)"
}

# --- TEST-445 (Spec-AC-12, spec-test-framework-sweep) — negative controls for
# TEST-003/008/009 ------------------------------------------------------------
#
# Validation round 1 (BLOCKING-5): TEST-445 was named in
# docs/specs/SPEC-0179-spec-test-framework-sweep.md's Test Plan and Mutation
# checks as the control covering TEST-003 (the format trap), TEST-008
# (append-only) and TEST-009 (post-backfill classification), but no such test
# existed anywhere — the strings occurred only in the spec's prose. This is
# the deliverable: each of the three properties, driven through a SCRATCH
# FIXTURE that takes the branch it was written for (never the live ledger,
# which can rot into a degenerate "not applicable" path), and each proven to
# fail on a deliberately broken input or a mutated copy of the engine.
test_445_ac12_negative_controls_test003_008_009() {
  log_info "Test: AC-12 negative controls for TEST-003/008/009 — each driven through its own fixture and reddened by a deliberate mutation, not merely reported not-applicable (TEST-445)..."

  # --- Arm A (TEST-003 shape): JSON-parsing, not tight-grepping ------------
  # A fixture ledger with three tightly-serialized and three SPACE-serialized
  # spec_amendment records (the population a naive `grep -F '"type":"spec_amendment"'`
  # silently drops). The real engine must count all six; a copy of the engine
  # mutated to pre-filter lines with that same tight grep before JSON.parse —
  # reproducing exactly the trap TEST-003 exists to catch — must undercount.
  local ledA="$TEST_DIR/t445a.jsonl" i
  rm -f "$ledA"
  {
    echo "# Decision Log — append-only, one JSON object per line (JSONL format)"
    echo "#"
  } > "$ledA"
  for i in 1 2 3; do
    printf '{"v":1,"ts":"2026-09-0%dT00:00:00Z","type":"spec_amendment","ref_id":"t445-tight-%d","spec":"s","amends":"s","what":"w","why":"y","owner_signoff":true}\n' "$i" "$i" >> "$ledA"
  done
  for i in 4 5 6; do
    printf '{"v":1,"ts":"2026-09-0%dT00:00:00Z", "type": "spec_amendment","ref_id":"t445-spaced-%d","spec":"s","amends":"s","what":"w","why":"y","owner_signoff":true}\n' "$i" "$i" >> "$ledA"
  done

  run_sa list --ledger "$ledA" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-445 arm A: \`list --json\` over the fixture must exit 0, got $EC (stderr: $ERR)"
  local totalA
  totalA="$(json_field "$OUT" 'j.counts.total')"
  [[ "$totalA" == 6 ]] \
    || log_fail "TEST-445 arm A: the real engine counted $totalA amendments (want 6) — the space-serialized half was dropped even without any mutation"

  # MUTATION: a scratch copy of spec-amend.mjs, with readDecisionsLedger given
  # a tight-grep pre-filter ahead of JSON.parse — the regression this arm must
  # catch, applied to a THROWAWAY copy only (HAZ-RESTORE / HAZ-SCRATCH).
  # spec-amend.mjs imports './lib/cli-pipe-guard.mjs' relative to its own
  # directory, so the scratch copy needs that sibling too.
  local saDirA="$TEST_DIR/sa-mut-a"
  mkdir -p "$saDirA/lib"
  # every ./lib sibling the engine imports (cli-pipe-guard, iso-time since
  # dispatch-state-sweep, and whatever comes next) — read from the engine
  # itself so a new import does not turn this mutation into a module error
  local _lib
  for _lib in $(/usr/bin/grep -aoE "from '\./lib/[a-z0-9-]+\.mjs'" "$SA" | /usr/bin/grep -oE "[a-z0-9-]+\.mjs"); do
    cp "$(dirname "$SA")/lib/$_lib" "$saDirA/lib/$_lib"
  done
  local saMut="$saDirA/spec-amend.mjs"
  cp "$SA" "$saMut"
  # Portable sed insertion keyed on readDecisionsLedger's unique skip-blank/
  # skip-comment line: append a tight-grep pre-filter right after it, dropping
  # any spec_amendment line serialized with a space before JSON.parse ever
  # sees it — reproducing the exact undercount TEST-003 exists to catch.
  sed -i.bak "/if (t === '' || t.startsWith('#')) continue;/a\\
    if (!/\"type\":\"spec_amendment\"/.test(t)) continue; // MUTATION: tight-grep pre-filter
" "$saMut" && rm -f "$saMut.bak"
  grep -qF 'MUTATION: tight-grep pre-filter' "$saMut" \
    || log_fail "TEST-445 arm A: could not apply the tight-grep mutation to the scratch copy — the anchor line was not found"

  local mutOutA mutEcA=0
  mutOutA="$(node "$saMut" list --ledger "$ledA" --json 2>&1)" || mutEcA=$?
  local mutTotalA
  mutTotalA="$(json_field "$mutOutA" 'j.counts.total')"
  [[ "$mutTotalA" == 3 ]] \
    || log_fail "TEST-445 arm A: the tight-grep mutation reported $mutTotalA amendments (want 3 — only the tightly-serialized half) — the mutation did not bite, so the JSON-parsing property is unproven"

  # --- Arm B (TEST-008 shape): append-only, on a mutated engine ------------
  # The real engine's own append primitive (appendLine -> fs.appendFileSync)
  # must never rewrite existing bytes. A scratch copy with appendFileSync
  # replaced by writeFileSync (truncate-and-rewrite) is the mutation: it must
  # make the SAME before/after prefix check catch a real, in-product
  # regression, not just a hand-edited fixture byte.
  local ledB spec
  ledB="$(mk_ledger t445b)"
  spec="$(mk_spec "SPEC-DRAFT-t445b.md" "spec-t445b-fixture")"
  local beforeB="$TEST_DIR/t445b-before.jsonl"
  cp "$ledB" "$beforeB"
  run_sa add --ledger "$ledB" --spec "$spec" --ref t445b-ride --what "w" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-445 arm B: add must succeed on the real engine, got $EC (stderr: $ERR)"

  local prefixVerdictB
  prefixVerdictB="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    if (head.length < base.length) { console.log("SHORTER"); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    console.log(prefix.equals(base) ? "PREFIX-OK" : "DIVERGES");
  ' "$beforeB" "$ledB")"
  [[ "$prefixVerdictB" == "PREFIX-OK" ]] \
    || log_fail "TEST-445 arm B: the real engine's add did not append cleanly — $prefixVerdictB"

  local saDirB="$TEST_DIR/sa-mut-b"
  mkdir -p "$saDirB/lib"
  # every ./lib sibling the engine imports (cli-pipe-guard, iso-time since
  # dispatch-state-sweep, and whatever comes next) — read from the engine
  # itself so a new import does not turn this mutation into a module error
  local _lib
  for _lib in $(/usr/bin/grep -aoE "from '\./lib/[a-z0-9-]+\.mjs'" "$SA" | /usr/bin/grep -oE "[a-z0-9-]+\.mjs"); do
    cp "$(dirname "$SA")/lib/$_lib" "$saDirB/lib/$_lib"
  done
  local saMutB="$saDirB/spec-amend.mjs"
  cp "$SA" "$saMutB"
  sed -i.bak "s/fs\.appendFileSync(absPath, \`\${prefix}\${JSON\.stringify(entry)}\\\\n\`);/fs.writeFileSync(absPath, \`\${JSON.stringify(entry)}\\\\n\`);/" "$saMutB" && rm -f "$saMutB.bak"
  grep -qF 'fs.writeFileSync(absPath, `${JSON.stringify(entry)}' "$saMutB" \
    || log_fail "TEST-445 arm B: could not apply the truncate-on-append mutation to the scratch copy — the anchor line was not found"

  local ledB2="$TEST_DIR/t445b2.jsonl" beforeB2="$TEST_DIR/t445b2-before.jsonl"
  cp "$ledB" "$ledB2"
  cp "$ledB2" "$beforeB2"
  local spec2; spec2="$(mk_spec "SPEC-DRAFT-t445b2.md" "spec-t445b2-fixture")"
  node "$saMutB" add --ledger "$ledB2" --spec "$spec2" --ref t445b2-ride --what "w" --why "y" --signoff none >/dev/null 2>&1 || true
  local prefixVerdictB2
  prefixVerdictB2="$(node -e '
    const fs=require("fs");
    const base=fs.readFileSync(process.argv[1]);
    const head=fs.readFileSync(process.argv[2]);
    if (head.length < base.length) { console.log("SHORTER"); process.exit(0); }
    const prefix=head.subarray(0, base.length);
    console.log(prefix.equals(base) ? "PREFIX-OK" : "DIVERGES");
  ' "$beforeB2" "$ledB2")"
  [[ "$prefixVerdictB2" == "DIVERGES" || "$prefixVerdictB2" == "SHORTER" ]] \
    || log_fail "TEST-445 arm B: mutation control failed — a truncate-and-rewrite engine still passed the append-only prefix check ($prefixVerdictB2)"

  # --- Arm C (TEST-009 shape): every amendment carries an effective
  # classification, on a fixture — a DELIBERATELY UNCLASSIFIED record is the
  # broken input the guard must catch. ---------------------------------------
  local ledC="$TEST_DIR/t445c.jsonl"
  rm -f "$ledC"
  {
    echo "# Decision Log — append-only, one JSON object per line (JSONL format)"
    echo "#"
  } > "$ledC"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T00:00:00Z","type":"spec_amendment","ref_id":"t445c-ride","spec":"s","amends":"s","what":"w","why":"y","tracked_by":"fu-amend-t445c"}' >> "$ledC"

  run_sa list --ledger "$ledC" --strict
  [[ "$EC" != 0 ]] \
    || log_fail "TEST-445 arm C: \`list --strict\` must refuse an unclassified amendment, got exit 0"
  grep -qiF "unclassified" <<<"$OUT$ERR" \
    || log_fail "TEST-445 arm C: the refusal must name the unclassified violation: out=$OUT err=$ERR"

  run_sa classify --ledger "$ledC" --ts "2026-09-01T00:00:00Z" --ref t445c-ride \
    --signoff none --why "fixture classification" --source "fixture" --tracked-by fu-amend-t445c
  [[ "$EC" == 0 ]] || log_fail "TEST-445 arm C: classify must succeed on the fixture, got $EC (stderr: $ERR)"
  run_sa list --ledger "$ledC" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-445 arm C: \`list --strict\` must exit 0 once the amendment is classified and tracked, got $EC (stdout: $OUT) (stderr: $ERR)"

  log_pass "TEST-445 all three arms (format trap, append-only, classification) are proven on fixtures that take the branch they were written for, and each reddens on its own deliberate mutation (arm A: 6 real vs $mutTotalA mutated; arm B: $prefixVerdictB real vs $prefixVerdictB2 mutated; arm C: unclassified refused, classified accepted)"
}

# --- TEST-482 (Spec-AC-12, spec-mutation-gate-for-tests D11) -----------------
# Undisclosed amendment is caught, and the refusal's OWN printed remedy —
# run verbatim, placeholders filled — clears it in one call.
test_482_undisclosed_amendment_caught() {
  log_info "Test: a frozen spec edited inside the contract projection with no record refuses list --strict, and its own printed remedy clears it (TEST-482)..."
  local specsdir led spec ok=1
  specsdir="$TEST_DIR/t482-specs"
  led="$(mk_ledger t482)"
  spec="$(mk_freezable_spec t482-specs/fixture.md spec-t482-fixture direct)"
  freeze_spec "$spec" || { log_fail "TEST-482 setup: real spec-freeze.mjs refused the fixture"; return; }
  [[ -n "$(frozen_sha256_of "$spec")" ]] || { log_fail "TEST-482 setup: no frozen_sha256 written by the real tool"; return; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-482: baseline (unedited) strict must be clean, got $EC (stdout: $OUT) (stderr: $ERR)"; return; }

  # A Spec-AC Description cell — squarely inside the contract projection.
  sed -i.bak 's/original description text/EDITED description text/' "$spec"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 1 ]] || { log_fail "TEST-482: an undisclosed edit must refuse strict, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION undisclosed-amendment' <<<"$OUT" \
    || { log_fail "TEST-482: refusal must print STRICT-VIOLATION undisclosed-amendment; stdout: $OUT"; ok=0; }
  grep -qF 'spec-t482-fixture' <<<"$OUT" \
    || { log_fail "TEST-482: refusal must name the offending spec; stdout: $OUT"; ok=0; }

  # NB2 (spec-mutation-gate-for-tests): the printed line carries REAL values
  # (ref = the offending spec's own frontmatter id, --what/--why real default
  # sentences) — never a `<placeholder>` token a shell would choke on — so
  # Spec-AC-12's "run VERBATIM" is exercised literally here, no substitution.
  local suggested
  suggested="$(sed -n 's/^ *node \.aai\/scripts\/spec-amend\.mjs \(add .*\)$/\1/p' <<<"$ERR" | qhead -1)"
  [[ -n "$suggested" ]] || { log_fail "TEST-482: no runnable \`add\` line printed on stderr; stderr: $ERR"; ok=0; }
  grep -qF '<' <<<"$suggested" \
    && { log_fail "TEST-482: the printed remedy still carries a <placeholder> token, not runnable verbatim: $suggested"; ok=0; }
  EC=0
  eval "node \"\$SA\" $suggested --ledger \"\$led\"" > "$TEST_DIR/.stdout" 2> "$TEST_DIR/.stderr" || EC=$?
  OUT="$(cat "$TEST_DIR/.stdout")"; ERR="$(cat "$TEST_DIR/.stderr")"
  [[ "$EC" == 0 ]] || { log_fail "TEST-482: the printed remedy, run VERBATIM (no substitution), must succeed, got $EC (stdout: $OUT) (stderr: $ERR)"; ok=0; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-482: after running the printed remedy, strict must reach 0, got $EC (stdout: $OUT)"; ok=0; }

  local stored current
  stored="$(frozen_sha256_of "$spec")"
  current="$(contract_hash_of "$spec")"
  [[ -n "$stored" && "$stored" == "$current" ]] \
    || { log_fail "TEST-482: frozen_sha256 must match the edited projection after the remedy, stored=$stored current=$current"; ok=0; }

  # D10's own claim, exercised directly: the frontmatter block is removed
  # ENTIRELY from the projection, so a harmless frontmatter-only edit (a new
  # top-level key nothing else touches) must never move the anchor. This is
  # exactly the property this row's own Mutation cell ("compare the stored
  # hash against the WHOLE file instead of the contract projection") breaks —
  # under that mutation the two hashes below diverge, which is what makes
  # this exact named mutation redden TEST-482 (not only TEST-483's
  # bookkeeping-cell arm).
  local fm_only_copy fm_only_hash
  fm_only_copy="$TEST_DIR/t482-fm-only.md"
  node -e '
    const fs = require("fs");
    const c = fs.readFileSync(process.argv[1], "utf8")
      .replace(/^type: spec$/m, "type: spec\nx-noop: frontmatter-only-edit");
    fs.writeFileSync(process.argv[2], c);
  ' "$spec" "$fm_only_copy"
  fm_only_hash="$(contract_hash_of "$fm_only_copy")"
  [[ "$current" == "$fm_only_hash" ]] \
    || { log_fail "TEST-482: a frontmatter-only edit must not change the contract-projection hash (D10 — frontmatter is stripped entirely); unedited=$current with-noop-key=$fm_only_hash"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-482 an undisclosed edit is caught, named, and cleared by its own printed \`add\` remedy in one call; frozen_sha256 is re-stamped to the edited projection; frontmatter never enters the hash" \
    || log_fail "TEST-482 undisclosed amendment"
}

# --- TEST-483 (Spec-AC-13) ----------------------------------------------------
# Honest edits (disclosed, either signoff) pass; non-targets leave the gate's
# output byte-identical to the unedited run.
test_483_honest_edits_and_non_targets() {
  log_info "Test: a disclosed amendment passes signed or unsigned-tracked; an unfrozen spec, a non-spec doc and a bookkeeping-only edit change nothing (TEST-483)..."
  local specsdir led ok=1

  # Arm A — signed disclosure.
  specsdir="$TEST_DIR/t483a-specs"; led="$(mk_ledger t483a)"
  local specA; specA="$(mk_freezable_spec t483a-specs/a.md spec-t483-signed direct)"
  freeze_spec "$specA" || { log_fail "TEST-483 arm A setup: freeze refused"; return; }
  sed -i.bak 's/original description text/A EDITED/' "$specA"
  run_sa add --ledger "$led" --spec "$specA" --ref t483a-ride --what "w" --why "y" \
    --signoff owner --authority "owner said so"
  [[ "$EC" == 0 ]] || { log_fail "TEST-483 arm A: add --signoff owner must succeed, got $EC (stderr: $ERR)"; ok=0; }
  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-483 arm A: strict must pass after a SIGNED disclosed amendment, got $EC (stdout: $OUT)"; ok=0; }

  # Arm B — unsigned-tracked disclosure.
  specsdir="$TEST_DIR/t483b-specs"; led="$(mk_ledger t483b)"
  local specB; specB="$(mk_freezable_spec t483b-specs/b.md spec-t483-unsigned direct)"
  freeze_spec "$specB" || { log_fail "TEST-483 arm B setup: freeze refused"; return; }
  sed -i.bak 's/original description text/B EDITED/' "$specB"
  run_sa add --ledger "$led" --spec "$specB" --ref t483b-ride --what "w" --why "y" --signoff none
  [[ "$EC" == 0 ]] || { log_fail "TEST-483 arm B: add --signoff none must succeed, got $EC (stderr: $ERR)"; ok=0; }
  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-483 arm B: strict must pass after an UNSIGNED-TRACKED disclosed amendment, got $EC (stdout: $OUT)"; ok=0; }

  # Arm C — three non-targets, sharing one specs dir + one baseline snapshot.
  specsdir="$TEST_DIR/t483c-specs"; led="$(mk_ledger t483c)"
  local specC; specC="$(mk_freezable_spec t483c-specs/frozen.md spec-t483-bookkeeping direct)"
  freeze_spec "$specC" || { log_fail "TEST-483 arm C setup: freeze refused"; return; }
  # an UNFROZEN spec (never touched by spec-freeze.mjs)
  cat > "$TEST_DIR/t483c-specs/unfrozen.md" <<'EOF'
---
id: spec-t483-unfrozen
type: spec
number: null
status: draft
---

# fixture unfrozen

## Implementation strategy
- Strategy: direct
EOF
  # a NON-SPEC document — even carrying marker-shaped text in its body, it
  # must never be scanned (type gate, not a body-text sniff).
  cat > "$TEST_DIR/t483c-specs/nonspec.md" <<'EOF'
---
id: note-t483
type: note
number: null
status: draft
---

# a note, not a spec

SPEC-FROZEN: true
frozen_sha256: 0000000000000000000000000000000000000000000000000000000000000
EOF

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  local baseline_ec="$EC" baseline_out="$OUT" baseline_err="$ERR"
  [[ "$baseline_ec" == 0 ]] || { log_fail "TEST-483 arm C: baseline over frozen+unfrozen+nonspec must be clean, got $baseline_ec (stdout: $baseline_out)"; ok=0; }
  # NB3 (spec-mutation-gate-for-tests): scanSpecAnchors's specFrozenInBody
  # skip is what keeps the UNFROZEN spec above out of `degraded` (it has no
  # frozen_sha256 either, so without the skip it would be miscounted as "a
  # frozen spec missing its anchor"). Pin the COUNT, not just rc: a removed
  # skip still exits 0 here (degraded is advisory, never a refusal) but
  # moves spec_degraded from 0 to 1 — this line is what catches that.
  grep -qF 'spec_degraded=0' <<<"$baseline_out" \
    || { log_fail "TEST-483 arm C: baseline spec_degraded must be 0 (the unfrozen spec must never be counted as a frozen-but-anchorless spec); stdout: $baseline_out"; ok=0; }

  # (c1) editing the UNFROZEN spec — output unchanged.
  sed -i.bak 's/Strategy: direct/Strategy: direct (edited)/' "$TEST_DIR/t483c-specs/unfrozen.md"
  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == "$baseline_ec" && "$OUT" == "$baseline_out" ]] \
    || { log_fail "TEST-483 arm C1: editing an unfrozen spec must leave the gate's output byte-identical; before=[$baseline_out] after=[$OUT]"; ok=0; }

  # (c2) editing the NON-SPEC doc — output unchanged.
  sed -i.bak 's/a note, not a spec/an edited note/' "$TEST_DIR/t483c-specs/nonspec.md"
  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == "$baseline_ec" && "$OUT" == "$baseline_out" ]] \
    || { log_fail "TEST-483 arm C2: editing a non-spec document must leave the gate's output byte-identical; before=[$baseline_out] after=[$OUT]"; ok=0; }

  # (c3) editing ONLY bookkeeping cells (AC Status/Evidence/Review-By/Notes,
  # Test Plan Status) of the frozen spec — output unchanged.
  sed -i.bak \
    -e 's/| Spec-AC-01 | original description text | planned | — | — | |/| Spec-AC-01 | original description text | done | some evidence | 2026-12-31 | reviewed |/' \
    -e 's/| TEST-001 | Spec-AC-01 | unit | tests\/x.sh | does the thing | pending |/| TEST-001 | Spec-AC-01 | unit | tests\/x.sh | does the thing | green |/' \
    "$specC"
  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == "$baseline_ec" && "$OUT" == "$baseline_out" ]] \
    || { log_fail "TEST-483 arm C3: a bookkeeping-only edit (Status/Evidence/Review-By/Notes/Test-Plan-Status) must leave the gate's output byte-identical; before=[$baseline_out] after=[$OUT]"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-483 a disclosed amendment passes under either signoff; an unfrozen spec, a non-spec document and bookkeeping-only edits change the gate's output not at all" \
    || log_fail "TEST-483 honest edits and non-targets"
}

# --- TEST-484 (Spec-AC-14) ----------------------------------------------------
# Legacy specs (no frozen_sha256) degrade by name, never turn the gate red.
test_484_legacy_degrades_by_name() {
  log_info "Test: three unanchored frozen specs degrade by name and never redden; an anchored spec edited without a record still refuses; the live repo exits 0 naming the degraded count (TEST-484)..."
  local specsdir led ok=1
  specsdir="$TEST_DIR/t484-specs"; led="$(mk_ledger t484)"
  mkdir -p "$specsdir"
  local i
  for i in 1 2 3; do
    cat > "$specsdir/legacy$i.md" <<EOF
---
id: spec-t484-legacy-$i
type: spec
number: null
status: implementing
---

# fixture legacy $i

SPEC-FROZEN: true

## Implementation strategy
- Strategy: direct
EOF
  done
  local anchored; anchored="$(mk_freezable_spec t484-specs/anchored.md spec-t484-anchored direct)"
  freeze_spec "$anchored" || { log_fail "TEST-484 setup: freeze refused"; return; }
  sed -i.bak 's/original description text/ANCHORED EDITED/' "$anchored"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict --list-degraded
  [[ "$EC" == 1 ]] || { log_fail "TEST-484: the anchored spec's undisclosed edit must still refuse, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION undisclosed-amendment spec=spec-t484-anchored' <<<"$OUT" \
    || { log_fail "TEST-484: the refusal must name ONLY the anchored spec; stdout: $OUT"; ok=0; }
  for i in 1 2 3; do
    grep -qF "STRICT-VIOLATION undisclosed-amendment spec=spec-t484-legacy-$i" <<<"$OUT" \
      && { log_fail "TEST-484: an unanchored legacy spec must never turn the gate red (legacy-$i wrongly listed as a violation); stdout: $OUT"; ok=0; }
    grep -qF "DEGRADED no freeze anchor spec=spec-t484-legacy-$i" <<<"$OUT" \
      || { log_fail "TEST-484: legacy-$i must be listed as degraded BY NAME under --list-degraded; stdout: $OUT"; ok=0; }
  done
  grep -qF 'spec_degraded=3' <<<"$OUT" \
    || { log_fail "TEST-484: the summary line must carry the degraded COUNT (3); stdout: $OUT"; ok=0; }

  # Live repository: exits 0, names the degraded count, never retroactively red.
  run_sa list --ledger "$LIVE_LEDGER" --specs-dir "$PROJECT_ROOT/docs/specs" --strict
  [[ "$EC" == 0 ]] \
    || { log_fail "TEST-484: the LIVE repository's strict gate must exit 0 (no legacy spec may turn it red), got $EC (stdout: $OUT)"; ok=0; }
  grep -qE 'spec_degraded=[0-9]+' <<<"$OUT" \
    || { log_fail "TEST-484: the live run must name a degraded count; stdout: $OUT"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-484 unanchored legacy specs degrade by name and never redden; an anchored spec's undisclosed edit still refuses; the live repository is clean and names its degraded count" \
    || log_fail "TEST-484 legacy degrades by name"
}

# --- TEST-485 (Spec-AC-15, D16 / fu-spec-amend-terminal-tracker-counts) -----
# The unsigned-tracked bucket requires an OPEN tracker; a closed or dropped
# one is unsigned-untracked and refused, naming the item and its status.
test_485_tracker_must_be_open() {
  log_info "Test: a record whose tracked_by item is open passes strict; closed or dropped, it is unsigned-untracked and refused, naming the item and its status (TEST-485)..."
  local led ok=1
  led="$(mk_ledger t485)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T00:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t485-ride","spec":"docs/specs/x.md","spec_id":"spec-t485-fixture","owner_signoff":false,"tracked_by":"fu-amend-t485-fixture","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-amend-t485-fixture","ref_id":"t485-ride","severity":"P2","finding":"f","decision":"d","source":"s"}' >> "$led"

  # (a) OPEN tracker: unsigned-tracked, strict passes.
  run_sa list --ledger "$led"
  grep -qF 'unsigned-tracked' <<<"$OUT" \
    || { log_fail "TEST-485 arm a: an open tracker must bucket as unsigned-tracked; stdout: $OUT"; ok=0; }
  grep -qF 'tracked_status=open' <<<"$OUT" \
    || { log_fail "TEST-485 arm a: the row must name the tracker's OWN status; stdout: $OUT"; ok=0; }
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-485 arm a: strict must pass while the tracker is open, got $EC (stdout: $OUT)"; ok=0; }

  # (b) CLOSED (done) tracker: unsigned-untracked, strict refuses, names item+status.
  printf '%s\n' '{"v":1,"ts":"2026-09-02T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-amend-t485-fixture","status":"done"}' >> "$led"
  run_sa list --ledger "$led"
  grep -qF 'unsigned-untracked' <<<"$OUT" \
    || { log_fail "TEST-485 arm b: a CLOSED (done) tracker must bucket as unsigned-untracked; stdout: $OUT"; ok=0; }
  grep -qF 'tracked_status=done' <<<"$OUT" \
    || { log_fail "TEST-485 arm b: the row must name the item and its status (done); stdout: $OUT"; ok=0; }
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 1 ]] || { log_fail "TEST-485 arm b: strict must refuse once the tracker is closed, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION unsigned-untracked' <<<"$OUT" \
    || { log_fail "TEST-485 arm b: the refusal must name the unsigned-untracked violation; stdout: $OUT"; ok=0; }

  # (c) DROPPED tracker: same bucket, same refusal.
  local led2; led2="$(mk_ledger t485c)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T00:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t485c-ride","spec":"docs/specs/x.md","spec_id":"spec-t485c-fixture","owner_signoff":false,"tracked_by":"fu-amend-t485c-fixture","what":"w","why":"y"}' >> "$led2"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-amend-t485c-fixture","ref_id":"t485c-ride","severity":"P2","finding":"f","decision":"d","source":"s"}' >> "$led2"
  printf '%s\n' '{"v":1,"ts":"2026-09-02T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-amend-t485c-fixture","status":"dropped"}' >> "$led2"
  run_sa list --ledger "$led2"
  grep -qF 'unsigned-untracked' <<<"$OUT" \
    || { log_fail "TEST-485 arm c: a DROPPED tracker must bucket as unsigned-untracked; stdout: $OUT"; ok=0; }
  grep -qF 'tracked_status=dropped' <<<"$OUT" \
    || { log_fail "TEST-485 arm c: the row must name the item and its status (dropped); stdout: $OUT"; ok=0; }
  run_sa list --ledger "$led2" --strict
  [[ "$EC" == 1 ]] || { log_fail "TEST-485 arm c: strict must refuse a dropped tracker exactly as a closed one, got $EC (stdout: $OUT)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-485 the unsigned-tracked bucket requires an OPEN tracker; a closed or dropped one is unsigned-untracked and refused, naming the item and its status" \
    || log_fail "TEST-485 tracker must be open"
}

# --- TEST-495 (NB-2, remediation round 3): a missing --specs-dir refuses,
# never silently scans nothing; spec_scanned is printed beside spec_degraded -
test_495_missing_specs_dir_refuses() {
  log_info "Test: list --strict refuses (exit 2) when --specs-dir does not exist, rather than scanning nothing and printing a clean-looking spec_degraded=0; a real scan names spec_scanned=<n> (TEST-495)..."
  local led ok=1
  led="$(mk_ledger t495)"

  # (a) missing dir -> refuse, name the path, write nothing.
  run_sa list --ledger "$led" --specs-dir "$TEST_DIR/t495-does-not-exist" --strict
  [[ "$EC" == 2 ]] \
    || { log_fail "TEST-495 arm a: a missing --specs-dir under --strict must exit 2, got $EC (stdout: $OUT stderr: $ERR)"; ok=0; }
  grep -qF 't495-does-not-exist' <<<"$ERR" \
    || { log_fail "TEST-495 arm a: the refusal must name the missing path; stderr: $ERR"; ok=0; }

  # (b) a plain `list` (no --strict) never triggers the check at all — the
  # scan only runs under --strict (unchanged cost for the plain path).
  run_sa list --ledger "$led" --specs-dir "$TEST_DIR/t495-does-not-exist"
  [[ "$EC" == 0 ]] \
    || { log_fail "TEST-495 arm b: a plain list (no --strict) must not refuse on a missing --specs-dir, got $EC"; ok=0; }

  # (c) a REAL, existing (empty) specs dir under --strict: scans it, prints
  # spec_scanned=0, never refuses.
  local emptydir="$TEST_DIR/t495-empty-specs"
  mkdir -p "$emptydir"
  run_sa list --ledger "$led" --specs-dir "$emptydir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-495 arm c: an EMPTY but existing --specs-dir must not refuse, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'spec_scanned=0' <<<"$OUT" \
    || { log_fail "TEST-495 arm c: spec_scanned=0 must be printed for an empty dir; stdout: $OUT"; ok=0; }

  # (d) the LIVE repository: spec_scanned names a real, non-zero count of
  # frozen specs actually looked at (never silently 0 from the wrong cwd).
  run_sa list --ledger "$LIVE_LEDGER" --specs-dir "$PROJECT_ROOT/docs/specs" --strict
  [[ "$EC" == 0 || "$EC" == 1 ]] \
    || { log_fail "TEST-495 arm d: the live repository's strict gate exited unexpectedly: $EC (stdout: $OUT)"; ok=0; }
  grep -qE 'spec_scanned=[1-9][0-9]*' <<<"$OUT" \
    || { log_fail "TEST-495 arm d: the live run must name a non-zero spec_scanned count; stdout: $OUT"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-495 list --strict refuses a missing --specs-dir (exit 2, naming the path) rather than silently scanning nothing; an existing (even empty) dir is scanned and spec_scanned is always printed beside spec_degraded" \
    || log_fail "TEST-495 missing specs dir refuses"
}

# --- TEST-514 (remediation round 7, PR #384 bot findings) --------------------
# Codex P1: an anchored spec (carries frozen_sha256) that LOSES its
# SPEC-FROZEN body marker was skipped before scanSpecAnchors even compared
# the anchor — deleting one line bypassed the whole undisclosed-amendment
# gate. Now: a spec carrying frozen_sha256 is ALWAYS scanned, and an anchor
# with no marker is itself a STRICT violation naming the spec, with its own
# runnable remedy.
test_514_anchor_without_marker_caught() {
  log_info "Test: a REAL spec-freeze.mjs anchor whose SPEC-FROZEN marker is then deleted, alongside a body edit, refuses list --strict naming the spec (never silently skipped) (TEST-514)..."
  local specsdir led spec ok=1
  specsdir="$TEST_DIR/t514-specs"
  led="$(mk_ledger t514)"
  spec="$(mk_freezable_spec t514-specs/fixture.md spec-t514-fixture direct)"
  freeze_spec "$spec" || { log_fail "TEST-514 setup: real spec-freeze.mjs refused the fixture"; return; }
  [[ -n "$(frozen_sha256_of "$spec")" ]] || { log_fail "TEST-514 setup: no frozen_sha256 written by the real tool"; return; }
  grep -qF 'SPEC-FROZEN: true' "$spec" || { log_fail "TEST-514 setup: no SPEC-FROZEN marker written by the real tool"; return; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-514: baseline (unedited, anchored+marked) strict must be clean, got $EC (stdout: $OUT) (stderr: $ERR)"; return; }

  # The attack this finding names: delete the ONE marker line, and (as an
  # undisclosed amendment would) edit the body too.
  sed -i.bak '/^SPEC-FROZEN: true$/d' "$spec"
  sed -i.bak 's/original description text/EDITED description text/' "$spec"
  grep -qF 'SPEC-FROZEN: true' "$spec" && { log_fail "TEST-514 setup: the marker line must actually be gone: $(cat "$spec")"; return; }
  [[ -n "$(frozen_sha256_of "$spec")" ]] || { log_fail "TEST-514 setup: frozen_sha256 must still be present in frontmatter (untouched)"; return; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" != 0 ]] \
    || { log_fail "TEST-514: an anchored spec with its freeze marker deleted must NOT pass strict silently, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION anchor-without-freeze-marker' <<<"$OUT" \
    || { log_fail "TEST-514: the refusal must print STRICT-VIOLATION anchor-without-freeze-marker; stdout: $OUT"; ok=0; }
  grep -qF 'spec-t514-fixture' <<<"$OUT" \
    || { log_fail "TEST-514: the refusal must name the offending spec; stdout: $OUT"; ok=0; }
  grep -qF 'spec-t514-fixture' <<<"$ERR" \
    || { log_fail "TEST-514: stderr must print a runnable remedy naming the spec; stderr: $ERR"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-514 an anchored spec whose SPEC-FROZEN marker was deleted is ALWAYS scanned and refuses strict as its own violation class, never silently bypassed before the anchor is even compared" \
    || log_fail "TEST-514 anchor without marker"
}

# --- TEST-515 (remediation round 7, PR #384 bot findings) --------------------
# Codex P1: lib/spec-contract-hash.mjs split Test Plan/AC table rows on a
# plain `split('|')`, so an escaped `\|` inside a Mutation cell (SPEC-0181's
# own TEST-511 row has one) shifted the columns — a routine Status flip on
# that row then changed the contract hash (a false undisclosed-amendment).
# Reuses lib/docs-model.mjs's splitTableCells escaping rule instead of a
# second hand-rolled splitter (see spec-contract-hash.mjs blankTableSection).
test_515_contract_hash_escaped_pipe() {
  log_info "Test: a Test Plan row carrying an escaped pipe (\\|) in its Mutation cell — flipping ONLY that row's Status leaves the contract hash unchanged; editing its Description changes it (TEST-515)..."
  local specA="$TEST_DIR/t515-a.md" specB="$TEST_DIR/t515-b.md" specC="$TEST_DIR/t515-c.md"
  cat > "$specA" <<'EOF'
---
id: spec-t515-fixture
type: spec
number: null
status: implementing
---

# fixture t515

## Implementation strategy
- Strategy: tdd

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | original description text | planned | — | — | |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|-----------------------|--------------|----------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh | does the thing | sed:s/if \(a \|\| b\) \{/if (false) {/ | pending |
EOF
  sed 's/| pending |$/| green |/' "$specA" > "$specB"
  sed 's/does the thing/does a DIFFERENT thing/' "$specA" > "$specC"
  # Setup sanity: the Mutation cell's escaped pipes made it into all three
  # fixtures byte-identical outside the cells this test itself edits.
  grep -qF '\|\|' "$specA" || { log_fail "TEST-515 setup: fixture must carry an escaped pipe in its Mutation cell: $(cat "$specA")"; return; }

  local hashA hashB hashC
  hashA="$(contract_hash_of "$specA")"
  hashB="$(contract_hash_of "$specB")"
  hashC="$(contract_hash_of "$specC")"

  [[ "$hashA" == "$hashB" ]] \
    || log_fail "TEST-515: flipping ONLY the Status cell of a row whose Mutation cell carries an escaped pipe must not change the contract hash (Status is bookkeeping), A=$hashA B=$hashB"
  [[ "$hashA" != "$hashC" ]] \
    || log_fail "TEST-515: editing the Description cell of that same row MUST change the contract hash, A=$hashA C=$hashC"

  log_pass "TEST-515 an escaped pipe inside a Mutation cell no longer shifts table columns: a Status-only flip leaves the contract hash unchanged and a real content edit still moves it"
}

# --- TEST-516 (remediation round 7, PR #384 bot findings) --------------------
# Codex P2: an unreadable spec file was silently OMITTED from the strict
# scan (a bare `catch { continue; }`). Now fails CLOSED: reported as its own
# STRICT violation bucket naming the file, never silently skipped.
test_516_unreadable_spec_refuses() {
  if [[ "$(id -u)" == "0" ]]; then
    # A named degrade, never log_skip: log_skip is exit 42 and VOIDS THE WHOLE
    # SUITE (validation round 10 NB1; the same lesson TEST-443 and TEST-486
    # recorded). root ignores chmod 000, so this one arm cannot run there.
    log_info "TEST-516 DEGRADED (named): running as root — chmod 000 is not enforced, this arm cannot prove the refusal here"
    log_pass "TEST-516: degraded by name under root (the refusal is exercised on every non-root run)"
    return 0
  fi
  log_info "Test: an unreadable (chmod 000) spec under --specs-dir refuses list --strict, naming the file, rather than being silently omitted from the scan (TEST-516)..."
  local specsdir led spec ok=1
  specsdir="$TEST_DIR/t516-specs"
  led="$(mk_ledger t516)"
  mkdir -p "$specsdir"
  spec="$specsdir/unreadable.md"
  cat > "$spec" <<'EOF'
---
id: spec-t516-fixture
type: spec
number: null
status: implementing
---

# fixture t516

SPEC-FROZEN: true
frozen_sha256: 0000000000000000000000000000000000000000000000000000000000000
EOF
  chmod 000 "$spec"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  chmod 644 "$spec" # restore before any assertion can early-return and leak an unreadable fixture

  [[ "$EC" != 0 ]] \
    || { log_fail "TEST-516: an unreadable spec must not let strict pass silently, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION unreadable-spec' <<<"$OUT" \
    || { log_fail "TEST-516: the refusal must print STRICT-VIOLATION unreadable-spec; stdout: $OUT"; ok=0; }
  grep -qF 'unreadable.md' <<<"$OUT" \
    || { log_fail "TEST-516: the refusal must name the unreadable file; stdout: $OUT"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-516 an unreadable spec fails the strict scan CLOSED (its own STRICT violation bucket, naming the file) rather than being silently omitted" \
    || log_fail "TEST-516 unreadable spec"
}

# --- TEST-550 (Spec-AC-19, D2) ------------------------------------------------
# `spec-amend.mjs restamp` appends a spec_amendment record carrying the
# from/to frozen_sha256 anchors as 64-hex values, writes the spec ATOMICALLY
# (temp file + rename in the SAME directory — a clean run leaves no stray tmp
# file), and the ledger record lands BEFORE the spec is ever touched: a
# process killed right after the ledger append (AAI_SPEC_AMEND_INJECT_CRASH=
# before-rename, the same fault-hook convention lib/state-engine.mjs uses)
# leaves the spec byte-identical to its pre-restamp state while the ledger
# already carries the disclosure.
test_550_amendment_record_anchors() {
  log_info "Test: restamp's ledger record carries from/to frozen_sha256 as 64-hex values matching the spec before/after, a clean run leaves no stray tmp file, and a crash right after the ledger append leaves the spec byte-identical (TEST-550)..."
  local ok=1

  # --- Arm A: a clean run — record shape + no leftover tmp file ------------
  local specsdir led spec
  specsdir="$TEST_DIR/t550a-specs"; led="$(mk_ledger t550a)"
  spec="$(mk_freezable_spec t550a-specs/fixture.md spec-t550-fixture direct)"
  freeze_spec "$spec" || { log_fail "TEST-550 arm A setup: real spec-freeze.mjs refused the fixture"; return; }
  local pre_anchor; pre_anchor="$(frozen_sha256_of "$spec")"
  [[ -n "$pre_anchor" ]] || { log_fail "TEST-550 arm A setup: no frozen_sha256 written by the real tool"; return; }
  sed -i.bak 's/original description text/RENUMBERED description text/' "$spec"
  local expect_next; expect_next="$(contract_hash_of "$spec")"

  run_sa restamp --spec "$spec" --ref t550a-ride --ledger "$led"
  [[ "$EC" == 0 ]] || { log_fail "TEST-550 arm A: restamp must succeed on a genuinely drifted anchor, got $EC (stdout: $OUT) (stderr: $ERR)"; ok=0; }

  local last from to rtype
  last="$(last_amendment_for "$led" t550a-ride)"
  rtype="$(json_field "$last" 'j.type')"
  from="$(json_field "$last" 'j.from_frozen_sha256')"
  to="$(json_field "$last" 'j.to_frozen_sha256')"
  [[ "$rtype" == "spec_amendment" ]] \
    || { log_fail "TEST-550 arm A: the appended record's type must be spec_amendment, got $rtype: $last"; ok=0; }
  [[ "$from" =~ ^[0-9a-f]{64}$ ]] \
    || { log_fail "TEST-550 arm A: from_frozen_sha256 must be a 64-hex value, got '$from': $last"; ok=0; }
  [[ "$to" =~ ^[0-9a-f]{64}$ ]] \
    || { log_fail "TEST-550 arm A: to_frozen_sha256 must be a 64-hex value, got '$to': $last"; ok=0; }
  [[ "$from" == "$pre_anchor" ]] \
    || { log_fail "TEST-550 arm A: from_frozen_sha256 must equal the spec's pre-restamp anchor; from=$from pre=$pre_anchor"; ok=0; }
  [[ "$to" == "$expect_next" ]] \
    || { log_fail "TEST-550 arm A: to_frozen_sha256 must equal the post-edit contract-projection hash; to=$to expect=$expect_next"; ok=0; }
  local post_anchor; post_anchor="$(frozen_sha256_of "$spec")"
  [[ "$post_anchor" == "$to" ]] \
    || { log_fail "TEST-550 arm A: the spec's OWN stored anchor must now equal to_frozen_sha256; stored=$post_anchor to=$to"; ok=0; }

  # This is the assertion the row's own named mutation reddens: a direct
  # fs.writeFileSync(absSpec, out) in place of fs.renameSync(tmpSpec, absSpec)
  # produces the SAME final spec content but never consumes the tmp file the
  # earlier fs.writeFileSync(tmpSpec, out) line created, so it survives on
  # disk as a stray dotfile next to the spec.
  local stray; stray="$(find "$specsdir" -maxdepth 1 -name '.*.restamp-*.tmp')"
  [[ -z "$stray" ]] \
    || { log_fail "TEST-550 arm A: a clean restamp must leave no leftover .*.restamp-*.tmp file (the atomic rename must consume it); found: $stray"; ok=0; }

  # --- Arm B: a crash right after the ledger append leaves the spec untouched
  local specsdirB ledB specB
  specsdirB="$TEST_DIR/t550b-specs"; ledB="$(mk_ledger t550b)"
  specB="$(mk_freezable_spec t550b-specs/fixture.md spec-t550b-fixture direct)"
  freeze_spec "$specB" || { log_fail "TEST-550 arm B setup: real spec-freeze.mjs refused the fixture"; return; }
  sed -i.bak 's/original description text/RENUMBERED description text/' "$specB"
  local pre_bytes; pre_bytes="$(cat "$specB")"

  AAI_SPEC_AMEND_INJECT_CRASH=before-rename run_sa restamp --spec "$specB" --ref t550b-ride --ledger "$ledB"
  [[ "$EC" -ne 0 ]] \
    || { log_fail "TEST-550 arm B: a SIGKILL-injected restamp must not exit 0, got $EC"; ok=0; }

  local post_bytes; post_bytes="$(cat "$specB")"
  [[ "$post_bytes" == "$pre_bytes" ]] \
    || { log_fail "TEST-550 arm B: a process killed right after the ledger append must leave the spec BYTE-IDENTICAL to its pre-restamp state; it changed"; ok=0; }

  local lastB rtypeB fromB toB
  lastB="$(last_amendment_for "$ledB" t550b-ride)"
  rtypeB="$(json_field "$lastB" 'j.type')"
  fromB="$(json_field "$lastB" 'j.from_frozen_sha256')"
  toB="$(json_field "$lastB" 'j.to_frozen_sha256')"
  [[ "$rtypeB" == "spec_amendment" ]] \
    || { log_fail "TEST-550 arm B: the ledger must ALREADY carry the spec_amendment record even though the file write never landed; got type=$rtypeB: $lastB"; ok=0; }
  [[ "$fromB" =~ ^[0-9a-f]{64}$ && "$toB" =~ ^[0-9a-f]{64}$ ]] \
    || { log_fail "TEST-550 arm B: the pre-crash ledger record must still carry both 64-hex anchors; from=$fromB to=$toB"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-550 restamp's ledger record carries from/to frozen_sha256 as matching 64-hex values, a clean run leaves no stray tmp file, and a crash right after the ledger append leaves the spec byte-identical while the ledger already discloses it" \
    || log_fail "TEST-550 amendment record anchors"
}

# --- TEST-551 (Spec-AC-20, D2, S3) --------------------------------------------
# The real sequence Spec-AC-20 exists for: a frozen spec whose own body names
# its DRAFT path gets that path rewritten (the allocator's own verbatim
# substring substitution, `content.split(oldBase).join(newBase)`, applied
# here to a fixture rather than mocked) — `list --strict` must refuse it as
# undisclosed until `restamp` is run, and pass once it has.
test_551_restamp_after_renumbering() {
  log_info "Test: a frozen fixture spec whose DRAFT self-reference the allocator rewrote fails list --strict as undisclosed-amendment, and passes after restamp (TEST-551)..."
  local ok=1
  local specsdir led spec
  specsdir="$TEST_DIR/t551-specs"; led="$(mk_ledger t551)"
  spec="$(mk_freezable_spec t551-specs/fixture.md spec-t551-fixture direct)"
  # A body self-reference to this spec's own DRAFT path — the exact literal
  # token allocate-doc-number.mjs's rewriteReferences() substitutes verbatim
  # at merge (docs/specs/<TYPE>-DRAFT-<slug>.md -> docs/specs/<TYPE>-000N-<slug>.md).
  printf '\nSee docs/specs/SPEC-DRAFT-spec-t551-fixture.md for the frozen text.\n' >> "$spec"
  freeze_spec "$spec" || { log_fail "TEST-551 setup: real spec-freeze.mjs refused the fixture"; return; }
  grep -qF 'SPEC-DRAFT-spec-t551-fixture.md' "$spec" \
    || { log_fail "TEST-551 setup: the DRAFT self-reference did not survive into the frozen body"; return; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] || { log_fail "TEST-551: baseline (unrenumbered) strict must be clean, got $EC (stdout: $OUT)"; ok=0; }

  # Simulate the allocator's own rewrite pass: a plain verbatim substring
  # substitution of the DRAFT basename for the numbered one, nothing else
  # touched (never spec-amend.mjs, never frozen_sha256).
  sed -i.bak 's/SPEC-DRAFT-spec-t551-fixture\.md/SPEC-0182-spec-t551-fixture.md/' "$spec"
  grep -qF 'SPEC-0182-spec-t551-fixture.md' "$spec" \
    || { log_fail "TEST-551: the simulated allocator rewrite did not land"; ok=0; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 1 ]] \
    || { log_fail "TEST-551: WITHOUT restamp, the renumbered spec must refuse strict as undisclosed, got $EC (stdout: $OUT)"; ok=0; }
  grep -qF 'STRICT-VIOLATION undisclosed-amendment' <<<"$OUT" \
    || { log_fail "TEST-551: the refusal must print STRICT-VIOLATION undisclosed-amendment; stdout: $OUT"; ok=0; }
  grep -qF 'spec-t551-fixture' <<<"$OUT" \
    || { log_fail "TEST-551: the refusal must name the offending spec; stdout: $OUT"; ok=0; }

  run_sa restamp --spec "$spec" --ref t551-ride --ledger "$led"
  [[ "$EC" == 0 ]] || { log_fail "TEST-551: restamp must succeed on the renumbered spec, got $EC (stdout: $OUT) (stderr: $ERR)"; ok=0; }

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] \
    || { log_fail "TEST-551: WITH restamp, list --strict must exit 0 (a disclosed restamp, not a refusal), got $EC (stdout: $OUT)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-551 a frozen spec renumbered by the allocator's own DRAFT-to-numbered rewrite refuses list --strict as undisclosed until restamp is run, and passes once it has" \
    || log_fail "TEST-551 restamp after renumbering"
}

# --- TEST-1354..TEST-1357 (SPEC-DRAFT spec-amendment-signature-asks-the-owner-
# --- too-often, Spec-AC-01..04) — the DECLARED amendment class ----------------
#
# One post-freeze amendment can be two different things: a change to WHAT the
# spec promises (a scope decision — `contract`, which still owes the owner a
# signature and a tracked item) or a change to HOW a claim is measured (the
# author fixing their own instrument — `measurement`, disclosed and counted,
# owing neither). The partition is DECLARED by the writer on the record and is
# never read out of `what`/`why` prose (.aai/scripts/nothing-left-behind.mjs
# lines 68-78 carry the scar from classifying by prose). These four arms cover
# the field itself, its closed vocabulary and the single obligation predicate.

test_1354_measurement_add_owes_no_owner_obligation() {
  log_info "Test: \`add --class measurement --signoff none\` stamps the class, writes NO tracked_by and co-creates NO fu-amend- item (TEST-1354)..."
  local led spec verdict
  led="$(mk_ledger t1354)"
  spec="$(mk_spec "SPEC-DRAFT-t1354.md" "spec-t1354-fixture")"

  run_sa add --ledger "$led" --spec "$spec" --ref t1354-ride \
    --what "corrected the Mutation cell for TEST-001, which named bytes the target does not carry" \
    --why "the cell never reddened, so the row's admission was unproven" \
    --class measurement --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1354: expected exit 0 from \`add --class measurement --signoff none\`, got $EC (stdout: $OUT) (stderr: $ERR)"

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
    if (fu.length!==0) { console.log("FOLLOWUPS="+fu.length); process.exit(0); }
    if (am[0].amendment_class!=="measurement") { console.log("CLASS="+JSON.stringify(am[0].amendment_class)); process.exit(0); }
    if (am[0].owner_signoff!==false) { console.log("SIGNOFF="+JSON.stringify(am[0].owner_signoff)); process.exit(0); }
    if (Object.prototype.hasOwnProperty.call(am[0],"tracked_by")) { console.log("TRACKED_BY="+am[0].tracked_by); process.exit(0); }
    console.log("MEASUREMENT-OK");
  ' "$led")"
  case "$verdict" in
    MEASUREMENT-OK*) : ;;
    *) log_fail "TEST-1354: the measurement-class add did not leave a disclosed, UNTRACKED record — $verdict" ;;
  esac

  # SEAM-2 again: the ABSENCE of the item is read back through the REAL
  # follow-ups.mjs, never by grepping the ledger this suite just wrote.
  run_fu list --ledger "$led" --status all
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1354: follow-ups.mjs list must exit 0 over the produced ledger, got $EC (stderr: $ERR)"
  if grep -qF "fu-amend-" <<<"$OUT"; then
    log_fail "TEST-1354: a measurement-class amendment must co-create NO fu-amend- item; the real reader found one: $OUT"
  fi

  log_pass "TEST-1354 a measurement-class add is disclosed on the ledger and owes no owner obligation (no tracked_by, no fu-amend- item)"
}

test_1355_contract_add_keeps_the_co_created_item() {
  log_info "Test: \`add --class contract --signoff none\` is today's behaviour plus the stamped class, and the \`--class\`-less add lands in that SAME lane (TEST-1355)..."
  local led spec verdict
  led="$(mk_ledger t1355)"
  spec="$(mk_spec "SPEC-DRAFT-t1355.md" "spec-t1355-fixture")"

  # ARM 1 — the declared contract lane.
  run_sa add --ledger "$led" --spec "$spec" --ref t1355-ride \
    --what "widened Spec-AC-03 to cover the absent-key case" \
    --why "the frozen predicate did not cover the data" \
    --class contract --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1355 arm 1: expected exit 0 from \`add --class contract --signoff none\`, got $EC (stdout: $OUT) (stderr: $ERR)"

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
    if (am[0].amendment_class!=="contract") { console.log("CLASS="+JSON.stringify(am[0].amendment_class)); process.exit(0); }
    if (am[0].tracked_by!==fu[0].id) { console.log("LINK="+am[0].tracked_by+" vs "+fu[0].id); process.exit(0); }
    console.log("CONTRACT-OK id="+fu[0].id);
  ' "$led")"
  case "$verdict" in
    CONTRACT-OK*) : ;;
    *) log_fail "TEST-1355 arm 1: the contract-class add did not keep the co-created obligation — $verdict" ;;
  esac

  # ARM 2 — the DEFAULT lane, on its own fresh ledger: an add with NO --class
  # at all must resolve into the SAME heavier lane, so the obligation is still
  # co-created. This is the arm that makes the default load-bearing rather
  # than decorative: point the default at the lighter class and every flagless
  # add in flight silently stops owing anything.
  local led2 spec2
  led2="$(mk_ledger t1355b)"
  spec2="$(mk_spec "SPEC-DRAFT-t1355b.md" "spec-t1355b-fixture")"
  run_sa add --ledger "$led2" --spec "$spec2" --ref t1355b-ride \
    --what "renamed a helper the frozen plan named" --why "the name was wrong" --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1355 arm 2: expected exit 0 from a \`--class\`-less add, got $EC (stdout: $OUT) (stderr: $ERR)"

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
    if (fu.length!==1) { console.log("DEFAULT-LANE-FOLLOWUPS="+fu.length); process.exit(0); }
    if (am[0].tracked_by!==fu[0].id) { console.log("LINK="+am[0].tracked_by+" vs "+fu[0].id); process.exit(0); }
    console.log("DEFAULT-LANE-OK id="+fu[0].id);
  ' "$led2")"
  case "$verdict" in
    DEFAULT-LANE-OK*) : ;;
    *) log_fail "TEST-1355 arm 2: the \`--class\`-less add did not land in the obligation-owing lane — $verdict" ;;
  esac

  log_pass "TEST-1355 the contract lane still co-creates the open obligation and now carries the stamped class, declared or defaulted"
}

test_1356_classless_add_stamps_contract_and_names_the_other_value() {
  log_info "Test: \`add --signoff none\` with no --class exits 0, STAMPS \`contract\` on the record, and prints a NOTE naming --class measurement (TEST-1356)..."
  local led spec verdict
  led="$(mk_ledger t1356)"
  spec="$(mk_spec "SPEC-DRAFT-t1356.md" "spec-t1356-fixture")"

  run_sa add --ledger "$led" --spec "$spec" --ref t1356-ride \
    --what "corrected a TEST id the allocator renumbered" --why "the row pointed at nothing" \
    --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1356: a \`--class\`-less add is NOT a usage error (the flag is optional by Article 5), got $EC (stdout: $OUT) (stderr: $ERR)"

  # The writer always STAMPS: a record written by a live writer is never
  # class-absent, so the reader's absent-key default is only ever consulted
  # for the legacy cohort.
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
    if (am.length!==1) { console.log("AMENDMENTS="+am.length); process.exit(0); }
    if (!Object.prototype.hasOwnProperty.call(am[0],"amendment_class")) { console.log("CLASS-KEY-ABSENT"); process.exit(0); }
    if (am[0].amendment_class!=="contract") { console.log("CLASS="+JSON.stringify(am[0].amendment_class)); process.exit(0); }
    console.log("STAMPED-OK");
  ' "$led")"
  case "$verdict" in
    STAMPED-OK*) : ;;
    *) log_fail "TEST-1356: the flagless add did not STAMP the resolved class on the record — $verdict" ;;
  esac

  if ! grep -q -- "NOTE.*--class measurement" <<<"$OUT"; then
    log_fail "TEST-1356: a flagless add must print a NOTE naming the other value (--class measurement); stdout was: $OUT"
  fi

  log_pass "TEST-1356 a \`--class\`-less add exits 0, stamps contract explicitly, and names the lighter lane in a NOTE"
}

test_1357_class_vocabulary_is_closed() {
  log_info "Test: a --class value outside the closed set exits 2 on BOTH add and classify, and the refusal names both legal values (TEST-1357)..."
  local led spec ts verdict
  led="$(mk_ledger t1357)"
  spec="$(mk_spec "SPEC-DRAFT-t1357.md" "spec-t1357-fixture")"

  # ARM 1 — `add`.
  run_sa add --ledger "$led" --spec "$spec" --ref t1357-ride \
    --what "w" --why "y" --class bogus --signoff none
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1357 arm 1: \`add --class bogus\` must exit 2, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "contract" <<<"$ERR" \
    || log_fail "TEST-1357 arm 1: the refusal must name the legal value contract; stderr was: $ERR"
  grep -qF "measurement" <<<"$ERR" \
    || log_fail "TEST-1357 arm 1: the refusal must name the legal value measurement; stderr was: $ERR"

  # ARM 1b — a usage error is not a write.
  local after1
  after1="$(count_amendments "$led")"
  [[ "$after1" == 0 ]] \
    || log_fail "TEST-1357 arm 1b: a refused invocation must append nothing, found $after1 spec_amendment record(s)"

  # ARM 2 — `classify`, over a REAL target this suite wrote through the writer.
  run_sa add --ledger "$led" --spec "$spec" --ref t1357-ride \
    --what "w" --why "y" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-1357 arm 2 setup: the target add must succeed, got $EC (stderr: $ERR)"
  ts="$(node -e '
    const fs=require("fs");
    let found="";
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment") { found=String(r.ts); break; }
    }
    process.stdout.write(found);
  ' "$led")"
  [[ -n "$ts" ]] || log_fail "TEST-1357 arm 2 setup: no spec_amendment ts could be read back"

  run_sa classify --ledger "$led" --ts "$ts" --ref t1357-ride \
    --signoff none --why "y" --source "s" --class bogus
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1357 arm 2: \`classify --class bogus\` must exit 2, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "contract" <<<"$ERR" \
    || log_fail "TEST-1357 arm 2: the refusal must name the legal value contract; stderr was: $ERR"
  grep -qF "measurement" <<<"$ERR" \
    || log_fail "TEST-1357 arm 2: the refusal must name the legal value measurement; stderr was: $ERR"

  # ARM 2b — the refused classify appended no overlay.
  verdict="$(node -e '
    const fs=require("fs");
    let n=0;
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment_classification") n+=1;
    }
    console.log("OVERLAYS="+n);
  ' "$led")"
  [[ "$verdict" == "OVERLAYS=0" ]] \
    || log_fail "TEST-1357 arm 2b: a refused classify must append nothing, got $verdict"

  log_pass "TEST-1357 the class vocabulary is closed on both writers and the refusal names contract and measurement"
}


# --- TEST-1358..TEST-1361 (SPEC-DRAFT spec-amendment-signature-asks-the-owner-
# --- too-often, Spec-AC-05..07) — the one refusal, the fold, the controls -----
#
# The measurement lane can REDUCE an obligation to disclosure; it can never
# PRODUCE authority. `--class measurement --signoff owner` is therefore the
# one combination the parser refuses (D4), and the fold below is the first
# reader of the declared class. The two Spec-AC-07 arms are the standing
# do-not-weaken proof: the pre-existing strict buckets still refuse, and the
# new bucket is excluded from them ON PURPOSE rather than by omission.

test_1358_measurement_cannot_carry_an_owner_signature() {
  log_info "Test: \`--class measurement --signoff owner\` is a usage error on both writers, appends nothing, and \`--class contract --signoff owner\` is untouched (TEST-1358)..."
  local led spec ts after
  led="$(mk_ledger t1358)"
  spec="$(mk_spec "SPEC-DRAFT-t1358.md" "spec-t1358-fixture")"

  # ARM 1 — `add`. --authority is supplied, so the ONLY thing left for the
  # writer to object to is the contradiction itself: this arm cannot pass by
  # accident on the pre-existing "signed add needs --authority" refusal.
  run_sa add --ledger "$led" --spec "$spec" --ref t1358-ride \
    --what "corrected the Mutation cell for TEST-001" \
    --why "the cell named bytes the target does not carry" \
    --class measurement --signoff owner --authority "docs/ai/decisions.jsonl 2026-10-02 owner menu answer A"
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1358 arm 1: \`add --class measurement --signoff owner\` must exit 2 (the light lane can never manufacture a signature), got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "measurement" <<<"$ERR" \
    || log_fail "TEST-1358 arm 1: the refusal must name the class it refuses; stderr was: $ERR"
  grep -qF "owner" <<<"$ERR" \
    || log_fail "TEST-1358 arm 1: the refusal must name the signature it refuses to attach; stderr was: $ERR"

  # ARM 1b — a refused invocation is NOT a write. The whole point of the
  # refusal is that no record carrying both claims ever reaches the ledger.
  after="$(count_amendments "$led")"
  [[ "$after" == 0 ]] \
    || log_fail "TEST-1358 arm 1b: the refused add must append nothing, found $after spec_amendment record(s)"

  # ARM 2 — the NEGATIVE CONTROL that keeps the refusal narrow: it is a gate
  # on the CONTRADICTION, never on `--signoff owner`. A contract-class signed
  # amendment is exactly as legal as it was before this scope existed.
  run_sa add --ledger "$led" --spec "$spec" --ref t1358-signed \
    --what "widened Spec-AC-02 to cover the absent-key case" \
    --why "the frozen predicate did not cover the data" \
    --class contract --signoff owner --authority "docs/ai/decisions.jsonl 2026-10-02 owner menu answer A"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1358 arm 2: \`add --class contract --signoff owner\` must still exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  after="$(count_amendments "$led")"
  [[ "$after" == 1 ]] \
    || log_fail "TEST-1358 arm 2: the signed contract add must have appended exactly one record, found $after"

  # ARM 3 — `classify` carries the SAME refusal. D4 states the contradiction
  # without naming a subcommand, and a per-record route that could still mint
  # `measurement` + `owner` would reopen by the back door what arm 1 closes.
  ts="$(node -e '
    const fs=require("fs");
    let found="";
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment") { found=String(r.ts); break; }
    }
    process.stdout.write(found);
  ' "$led")"
  [[ -n "$ts" ]] || log_fail "TEST-1358 arm 3 setup: no spec_amendment ts could be read back"

  run_sa classify --ledger "$led" --ts "$ts" --ref t1358-signed \
    --signoff owner --why "y" --source "s" --class measurement
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1358 arm 3: \`classify --class measurement --signoff owner\` must exit 2, got $EC (stdout: $OUT) (stderr: $ERR)"

  # ARM 3b — and that refusal appended no overlay either.
  local overlays
  overlays="$(node -e '
    const fs=require("fs");
    let n=0;
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment_classification") n+=1;
    }
    console.log("OVERLAYS="+n);
  ' "$led")"
  [[ "$overlays" == "OVERLAYS=0" ]] \
    || log_fail "TEST-1358 arm 3b: the refused classify must append nothing, got $overlays"

  log_pass "TEST-1358 the measurement class can never carry an owner signature on either writer, and the refusal stays narrow to that contradiction"
}


test_1359_measurement_folds_to_its_own_bucket() {
  log_info "Test: the fold is the FIRST reader of the declared class — measurement folds to \`measurement\`, the same record signed folds to \`signed\`, and a class-absent legacy record folds exactly where it folds today (TEST-1359)..."
  local led json
  led="$(mk_ledger t1359)"

  # HAND-BUILT records, never written through the writer: this arm is about
  # the READER, and a fixture produced by the writer could only ever show the
  # classes the writer happens to emit. Six shapes, each a different branch:
  #   A measurement + unsigned + NO tracker  -> measurement (the whole point:
  #     untracked stops being a violation because nothing is owed)
  #   B the SAME record with owner_signoff true -> signed (a signature is
  #     never downgraded by a class)
  #   C legacy: no class key at all, unsigned, no tracker -> unsigned-untracked,
  #     bit-for-bit where it folds today. Reading an absent class as
  #     measurement would discharge the whole backlog nobody decided.
  #   D no class on the record, measurement on the OVERLAY -> measurement
  #     (the per-record route; `classify --class` finally has a reader)
  #   E contract on the RECORD, measurement on the overlay -> the record wins,
  #     so unsigned-untracked. Same record-over-overlay precedence tracked_by
  #     already has; an overlay must not re-point a live record's class.
  #   F degenerate: no class key AND no owner_signoff key -> unclassified,
  #     which stays its own bucket on purpose.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-a","spec_id":"spec-a","owner_signoff":false,"amendment_class":"measurement"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-b","spec_id":"spec-b","owner_signoff":true,"amendment_class":"measurement"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T03:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-c","spec_id":"spec-c","owner_signoff":false}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T04:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-d","spec_id":"spec-d","owner_signoff":false}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-02T04:30:00Z","actor":"a","type":"spec_amendment_classification","classifies_ts":"2026-09-01T04:00:00Z","classifies_ref":"t1359-d","owner_signoff":false,"amendment_class":"measurement","why":"w","source":"s"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T05:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-e","spec_id":"spec-e","owner_signoff":false,"amendment_class":"contract"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-02T05:30:00Z","actor":"a","type":"spec_amendment_classification","classifies_ts":"2026-09-01T05:00:00Z","classifies_ref":"t1359-e","owner_signoff":false,"amendment_class":"measurement","why":"w","source":"s"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T06:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1359-f","spec_id":"spec-f"}' >> "$led"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1359: \`list --json\` must exit 0 over the fixture ledger, got $EC (stderr: $ERR)"
  json="$OUT"

  local verdict
  verdict="$(json_field "$json" '
    (() => {
      const want = {
        "t1359-a": "measurement",
        "t1359-b": "signed",
        "t1359-c": "unsigned-untracked",
        "t1359-d": "measurement",
        "t1359-e": "unsigned-untracked",
        "t1359-f": "unclassified",
      };
      const got = {};
      for (const it of j.items) got[it.ref_id] = it.bucket;
      const bad = Object.keys(want).filter((k) => got[k] !== want[k]);
      if (bad.length) return "BUCKETS " + bad.map((k) => k + "=" + got[k] + " (want " + want[k] + ")").join(", ");
      return "BUCKETS-OK";
    })()
  ')"
  [[ "$verdict" == "BUCKETS-OK" ]] \
    || log_fail "TEST-1359: the fold did not read the declared class — $verdict"

  # The COUNTS are the second reader of the bucket vocabulary, and they are
  # what notices if the vocabulary itself is reordered or a name is dropped:
  # `signed` disappearing from the count object is how a bucket list that
  # lost its first entry shows up, and that is a different failure from any
  # single record folding wrong.
  local counts
  counts="$(json_field "$json" '
    "total=" + j.counts.total +
    " signed=" + j.counts.signed +
    " measurement=" + j.counts.measurement +
    " unsigned-tracked=" + j.counts["unsigned-tracked"] +
    " unsigned-untracked=" + j.counts["unsigned-untracked"] +
    " unclassified=" + j.counts.unclassified +
    " shown=" + j.counts.shown
  ')"
  [[ "$counts" == "total=6 signed=1 measurement=2 unsigned-tracked=0 unsigned-untracked=2 unclassified=1 shown=6" ]] \
    || log_fail "TEST-1359: the bucket counts are wrong (every bucket must be named and counted, and the default view must show all six records); got: $counts"

  # And the resolved class is on the item, not merely implied by the bucket:
  # the signed record's class is still measurement — the signature outranked
  # the class, it did not rewrite it.
  local resolved
  resolved="$(json_field "$json" '
    (() => {
      const m = {};
      for (const it of j.items) m[it.ref_id] = it.amendment_class;
      const want = { "t1359-a":"measurement","t1359-b":"measurement","t1359-c":"contract","t1359-d":"measurement","t1359-e":"contract","t1359-f":"contract" };
      const bad = Object.keys(want).filter((k) => m[k] !== want[k]);
      return bad.length ? "CLASS " + bad.map((k) => k + "=" + m[k] + " (want " + want[k] + ")").join(", ") : "CLASS-OK";
    })()
  ')"
  [[ "$resolved" == "CLASS-OK" ]] \
    || log_fail "TEST-1359: the resolved class is not exposed per item — $resolved"

  log_pass "TEST-1359 the fold resolves the declared class from the record then the overlay then the contract-lane default, signed outranks measurement, and every bucket is named and counted"
}

test_1360_strict_violation_buckets_unchanged() {
  log_info "Test: NEGATIVE CONTROL — the pre-existing strict refusal is untouched by the new bucket: an untracked-unsigned record and a no-key record still exit 1 and are still each named (TEST-1360)..."
  local led specs
  led="$(mk_ledger t1360)"
  specs="$TEST_DIR/specs-t1360"
  mkdir -p "$specs"

  # A fixture specs dir of its own (empty, but EXISTING — `list --strict`
  # refuses a missing one) so this arm measures the LEDGER half of --strict
  # and nothing else; the repository's own docs/specs is not this arm's
  # subject and must not be able to change its verdict.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1360-untracked","spec_id":"spec-g","owner_signoff":false}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1360-absent","spec_id":"spec-h"}' >> "$led"
  # A measurement record sits in the SAME ledger: a new bucket that owes
  # nothing must not dilute, mask or re-bucket the two that still owe.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T03:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1360-measurement","spec_id":"spec-i","owner_signoff":false,"amendment_class":"measurement"}' >> "$led"

  run_sa list --ledger "$led" --strict --specs-dir "$specs"
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-1360: \`list --strict\` must still exit 1 while an untracked-unsigned or an unclassified record stands, got $EC (stdout: $OUT) (stderr: $ERR)"

  # Each bucket is named BY NAME, not merely counted: dropping one from the
  # violation set would still exit 1 on the other, so an exit-code-only
  # assertion could not tell the difference. This is the assertion the
  # mutation column for this row attacks.
  grep -qF "STRICT-VIOLATION unsigned-untracked" <<<"$OUT" \
    || log_fail "TEST-1360: \`unsigned-untracked\` must still be a strict violation and must still be named; stdout was: $OUT"
  grep -qF "STRICT-VIOLATION unclassified" <<<"$OUT" \
    || log_fail "TEST-1360: \`unclassified\` must still be a strict violation and must still be named; stdout was: $OUT"
  grep -qF "t1360-untracked" <<<"$OUT" \
    || log_fail "TEST-1360: the untracked record must still be named by ref; stdout was: $OUT"
  grep -qF "t1360-absent" <<<"$OUT" \
    || log_fail "TEST-1360: the unclassified record must still be named by ref; stdout was: $OUT"

  log_pass "TEST-1360 the two standing strict violation buckets still refuse and are still each named, with a measurement record sitting beside them"
}

test_1361_measurement_is_excluded_from_strict_on_purpose() {
  log_info "Test: a measurement-class record owes nothing, so a ledger holding only measurement records is strict-CLEAN — while the identical record in the contract lane still refuses (TEST-1361)..."
  local led led2 specs
  specs="$TEST_DIR/specs-t1361"
  mkdir -p "$specs"

  # ARM 1 — the ledger that must now be CLEAN. Untracked and unsigned, which
  # is exactly `unsigned-untracked` today; the declared class is the only
  # thing that moves it, and moving it is the scope.
  led="$(mk_ledger t1361)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1361-measurement","spec_id":"spec-j","owner_signoff":false,"amendment_class":"measurement"}' >> "$led"
  run_sa list --ledger "$led" --strict --specs-dir "$specs"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1361 arm 1: a ledger holding only measurement-class records must exit 0 under --strict (the class is excluded from the violation set ON PURPOSE), got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "STRICT-VIOLATION" <<<"$OUT" \
    && log_fail "TEST-1361 arm 1: a measurement-only ledger must print no violation line; stdout was: $OUT"

  # ARM 2 — the negative control that stops arm 1 passing for the wrong
  # reason. The SAME shape in the contract lane must still refuse: if --strict
  # had simply gone toothless, arm 1 would pass and prove nothing.
  led2="$(mk_ledger t1361b)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1361-contract","spec_id":"spec-j","owner_signoff":false,"amendment_class":"contract"}' >> "$led2"
  run_sa list --ledger "$led2" --strict --specs-dir "$specs"
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-1361 arm 2: the identical record declared \`contract\` must still exit 1, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "STRICT-VIOLATION unsigned-untracked" <<<"$OUT" \
    || log_fail "TEST-1361 arm 2: the contract-lane record must still be named unsigned-untracked; stdout was: $OUT"

  log_pass "TEST-1361 measurement is excluded from the strict violation set on purpose, and the same record in the contract lane still refuses"
}


# --- TEST-1362..TEST-1365 (SPEC-DRAFT spec-amendment-signature-asks-the-owner-
# --- too-often, Spec-AC-08..11) — the disclosure half, the legacy fold, the
# --- one-place item pick, and restamp as the non-self-reported class ---------
#
# The class partitions what an amendment OWES. It must not touch what the
# ledger DISCLOSES (TEST-1362), must not move a single legacy record
# (TEST-1363), must not give `add` and `classify` two different answers to
# "which item" (TEST-1364), and must be hardcoded at the one site where it is
# not a self-report at all (TEST-1365).

test_1362_undisclosed_amendment_still_refuses() {
  log_info "Test: NEGATIVE CONTROL — a drifted frozen spec still refuses \`list --strict\` as undisclosed-amendment while the ledger holds ONLY measurement records (TEST-1362)..."
  local specsdir led spec
  specsdir="$TEST_DIR/t1362-specs"
  led="$(mk_ledger t1362)"
  spec="$(mk_freezable_spec t1362-specs/fixture.md spec-t1362-fixture direct)"
  freeze_spec "$spec" || log_fail "TEST-1362 setup: real spec-freeze.mjs refused the fixture"
  [[ -n "$(frozen_sha256_of "$spec")" ]] \
    || log_fail "TEST-1362 setup: no frozen_sha256 written by the real tool — this arm cannot test an anchor that does not exist"

  # The ledger half is MEASUREMENT ONLY, and proven clean on its own before
  # the spec is touched. Without this baseline the exit 1 below could be the
  # ledger refusing, and the arm would assert nothing about the spec scan.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1362-m1","spec_id":"spec-t1362-fixture","owner_signoff":false,"amendment_class":"measurement","what":"corrected a Mutation cell","why":"it named bytes the target does not carry"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1362-m2","spec_id":"spec-other","owner_signoff":false,"amendment_class":"measurement","what":"renumbered a TEST id","why":"the id collided"}' >> "$led"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1362 baseline: an unedited frozen spec plus a measurement-only ledger must be strict-CLEAN, got $EC (stdout: $OUT) (stderr: $ERR)"

  # A Spec-AC Description cell — squarely inside the contract projection, the
  # same byte TEST-482 edits, so this arm drifts the anchor exactly as a real
  # undisclosed amendment does.
  sed -i.bak 's/original description text/EDITED description text/' "$spec"
  grep -qF 'EDITED description text' "$spec" \
    || log_fail "TEST-1362: the simulated undisclosed edit did not land in the fixture spec"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-1362: a drifted frozen spec must STILL refuse --strict whatever class the ledger's records carry, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF 'STRICT-VIOLATION undisclosed-amendment' <<<"$OUT" \
    || log_fail "TEST-1362: the refusal must still print STRICT-VIOLATION undisclosed-amendment; stdout was: $OUT"
  grep -qF 'spec-t1362-fixture' <<<"$OUT" \
    || log_fail "TEST-1362: the refusal must still name the offending spec; stdout was: $OUT"

  # And the exit 1 is the SPEC half alone: no ledger bucket was dragged into
  # the violation set to produce it. A measurement record must neither become
  # a violation nor excuse one.
  grep -qF 'STRICT-VIOLATION unsigned-untracked' <<<"$OUT" \
    && log_fail "TEST-1362: no ledger record owes anything here — the refusal must come from the spec scan alone; stdout was: $OUT"
  grep -qF 'STRICT-VIOLATION unclassified' <<<"$OUT" \
    && log_fail "TEST-1362: no ledger record owes anything here — the refusal must come from the spec scan alone; stdout was: $OUT"
  grep -qF 'STRICT-VIOLATION measurement' <<<"$OUT" \
    && log_fail "TEST-1362: a measurement record must never itself become a strict violation; stdout was: $OUT"

  log_pass "TEST-1362 the undisclosed-amendment half of --strict is untouched by the class: a drifted frozen spec still refuses and is still named, over a ledger that owes nothing"
}

test_1363_live_ledger_folds_identically() {
  log_info "Test: folding the LIVE ledger at the pre-migration blob through the new code moves no non-cohort record out of the bucket the pre-change code gave it (TEST-1363)..."
  local dir base_script base_ledger verdict
  dir="$TEST_DIR/t1363"
  mkdir -p "$dir"
  base_script="$dir/spec-amend-base.mjs"
  base_ledger="$dir/base-decisions.jsonl"

  # This arm's baseline is a FIXED POINT IN HISTORY, not a moving ref. It is
  # the ledger as it stood before this ride appended its migration overlays,
  # and `origin/main` stopped being that the moment the ride merged — at which
  # point the arm asserted something only a pre-merge world could satisfy and
  # turned main red. That is precisely the defect this ride relaxed in
  # TEST-1336 (SPEC-0202), reproduced here by this ride's own test.
  # 1ffc03de is the commit this ride branched from; it is the last state of
  # main in which no record declares an amendment_class.
  local pre_migration_ref="${AAI_SPEC_AMEND_PRE_MIGRATION_REF:-1ffc03de}"
  if ! git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$pre_migration_ref^{commit}" >/dev/null 2>&1; then
    log_info "TEST-1363: the pre-migration commit $pre_migration_ref is not in this checkout (shallow clone?) — the historical fold arm cannot be produced here"
    log_pass "TEST-1363 SKIPPED-ARM: pre-migration baseline unreachable; nothing asserted rather than asserting against the wrong baseline"
    return
  fi

  # BOTH halves come from the SAME committed blob: the PRE-CHANGE code and
  # the PRE-MIGRATION ledger. Re-deriving the old bucket rule by hand here
  # would only prove this suite agrees with itself; running the actual
  # superseded program is the only baseline that cannot drift.
  git -C "$PROJECT_ROOT" show "$pre_migration_ref:.aai/scripts/spec-amend.mjs" > "$base_script" 2>/dev/null \
    || log_fail "TEST-1363: base ref $pre_migration_ref has no .aai/scripts/spec-amend.mjs — the pre-change fold cannot be produced here; FAILING CLOSED (this is a missing ref, NOT a detected regression)"
  git -C "$PROJECT_ROOT" show "$pre_migration_ref:docs/ai/decisions.jsonl" > "$base_ledger" 2>/dev/null \
    || log_fail "TEST-1363: base ref $pre_migration_ref has no docs/ai/decisions.jsonl — the pre-migration ledger cannot be produced here; FAILING CLOSED (this is a missing ref, NOT a detected regression)"

  # The extracted program imports its siblings as ./lib/*.mjs, so it is given
  # the REAL lib directory rather than a copy: this arm is about spec-amend's
  # own fold, not about a stale snapshot of its dependencies.
  ln -snf "$PROJECT_ROOT/.aai/scripts/lib" "$dir/lib"

  local old_json new_json
  old_json="$dir/old.json"; new_json="$dir/new.json"
  EC=0; node "$base_script" list --ledger "$base_ledger" --json > "$old_json" 2> "$dir/old.err" || EC=$?
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1363: the PRE-CHANGE spec-amend.mjs failed to fold the pre-migration ledger (rc=$EC): $(cat "$dir/old.err")"
  EC=0; node "$SA" list --ledger "$base_ledger" --json > "$new_json" 2> "$dir/new.err" || EC=$?
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1363: the CURRENT spec-amend.mjs failed to fold the pre-migration ledger (rc=$EC): $(cat "$dir/new.err")"

  # The restamp cohort is excluded because it is the ONE population D3
  # migrates, so once this branch merges its records legitimately move. It is
  # selected structurally — the conjunction of the two anchor fields only
  # cmdRestamp writes — never by reading `what`/`why` prose. (Spec-AC-14's
  # selector narrows this further with the RESTAMP_WHAT equality; excluding
  # the wider set here is the conservative direction.)
  verdict="$(node -e '
    const fs=require("fs");
    const old=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const neu=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
    const cohort=new Set();
    for (const line of fs.readFileSync(process.argv[3],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment" && r.from_frozen_sha256 && r.to_frozen_sha256) {
        cohort.add(String(r.ts)+"\u0000"+String(r.ref_id));
      }
    }
    const key=(i)=>String(i.ts)+"\u0000"+String(i.ref_id);
    const oldB=new Map(old.items.map((i)=>[key(i),i.bucket]));
    const newB=new Map(neu.items.map((i)=>[key(i),i.bucket]));
    if (old.items.length!==neu.items.length) { console.log("TOTAL old="+old.items.length+" new="+neu.items.length); process.exit(0); }
    if (old.items.length===0) { console.log("EMPTY-BASELINE"); process.exit(0); }
    const moved=[], missing=[], classBad=[];
    for (const [k,b] of oldB) {
      if (cohort.has(k)) continue;
      if (!newB.has(k)) { missing.push(k.replace("\u0000"," ")); continue; }
      if (newB.get(k)!==b) moved.push(k.replace("\u0000"," ")+": "+b+" -> "+newB.get(k));
    }
    // The MECHANISM that makes the line above true, asserted directly: a
    // class-absent legacy record resolves to the CONTRACT lane. Reading an
    // absent class as anything else would discharge obligations nobody
    // decided — and a default pointing at a value outside the closed
    // vocabulary would make the resolved class unreadable while the buckets
    // happened to stay put.
    for (const it of neu.items) {
      const k=key(it);
      if (cohort.has(k)) continue;
      if (it.amendment_class!=="contract" && it.amendment_class!=="measurement") classBad.push(k.replace("\u0000"," ")+"="+JSON.stringify(it.amendment_class));
    }
    const absent=[];
    for (const line of fs.readFileSync(process.argv[3],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment" && r.amendment_class===undefined) absent.push(String(r.ts)+"\u0000"+String(r.ref_id));
    }
    const absentWrong=absent.filter((k)=>!cohort.has(k)).filter((k)=>{
      const it=neu.items.find((i)=>key(i)===k);
      return !it || it.amendment_class!=="contract";
    });
    if (moved.length) { console.log("MOVED("+moved.length+") "+moved.slice(0,5).join(" | ")); process.exit(0); }
    if (missing.length) { console.log("MISSING("+missing.length+") "+missing.slice(0,5).join(" | ")); process.exit(0); }
    if (classBad.length) { console.log("CLASS-OUTSIDE-VOCABULARY("+classBad.length+") "+classBad.slice(0,5).join(" | ")); process.exit(0); }
    if (absent.length===0) { console.log("NO-CLASS-ABSENT-RECORDS-IN-BASELINE"); process.exit(0); }
    if (absentWrong.length) { console.log("CLASS-ABSENT-NOT-CONTRACT("+absentWrong.length+") "+absentWrong.slice(0,5).map((k)=>k.replace("\u0000"," ")).join(" | ")); process.exit(0); }
    console.log("FOLD-IDENTICAL total="+old.items.length+" cohort="+cohort.size+" compared="+(old.items.length-cohort.size)+" class_absent="+absent.length+" moved=0");
  ' "$old_json" "$new_json" "$base_ledger")"
  case "$verdict" in
    FOLD-IDENTICAL*) log_info "TEST-1363: $verdict" ;;
    *) log_fail "TEST-1363: the new fold did not reproduce the pre-change buckets on the live pre-migration ledger — $verdict" ;;
  esac

  # Nothing was laundered into the new bucket by the mere act of reading: the
  # pre-migration ledger declares no measurement anywhere, so the new count
  # must be exactly zero.
  local measurement_count
  measurement_count="$(json_field "$(cat "$new_json")" 'String(j.counts.measurement)')"
  [[ "$measurement_count" == "0" ]] \
    || log_fail "TEST-1363: folding the PRE-MIGRATION ledger must yield measurement=0 (no record declares the class yet); got $measurement_count"

  log_pass "TEST-1363 the live pre-migration ledger folds through the new code into the identical buckets the pre-change code produced, with every class-absent record resolving to the contract lane and nothing in the measurement bucket"
}

test_1364_both_writers_pick_one_item_id() {
  log_info "Test: \`add --class contract\` and \`classify --class contract\` attach to the BYTE-IDENTICAL fu-amend- id, and neither measurement call creates an item at all (TEST-1364)..."
  local spec_id="spec-t1364-fixture"
  local led_add led_cls spec id_add id_cls

  # ARM 1 — `add` picks an id for this spec.
  led_add="$(mk_ledger t1364-add)"
  spec="$(mk_spec "SPEC-DRAFT-t1364.md" "$spec_id")"
  run_sa add --ledger "$led_add" --spec "$spec" --ref t1364-add-ride \
    --what "widened Spec-AC-01 to cover the absent-key case" \
    --why "the frozen predicate did not cover the data" \
    --class contract --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 1: \`add --class contract --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  id_add="$(node -e '
    const fs=require("fs");
    let id="";
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment" && r.ref_id===process.argv[2]) id=String(r.tracked_by ?? "");
    }
    process.stdout.write(id);
  ' "$led_add" t1364-add-ride)"
  [[ -n "$id_add" ]] \
    || log_fail "TEST-1364 arm 1: the contract-lane add recorded no tracked_by at all"

  # ARM 2 — `classify` picks an id for the SAME spec id, from a record whose
  # own ref_id DIFFERS from it. The two writers reach pickAmendItemId by
  # different routes; only a shared key makes the two ids the same bytes.
  led_cls="$(mk_ledger t1364-cls)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1364-cls-ride","spec":"docs/specs/SPEC-DRAFT-t1364.md","spec_id":"spec-t1364-fixture","what":"widened Spec-AC-01 to cover the absent-key case","why":"the frozen predicate did not cover the data"}' >> "$led_cls"
  run_sa classify --ledger "$led_cls" --ts "2026-09-01T01:00:00Z" --ref t1364-cls-ride \
    --class contract --signoff none --why "back-classified as unsigned" --source "docs/ai/decisions.jsonl"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 2: \`classify --class contract --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  id_cls="$(node -e '
    const fs=require("fs");
    let id="";
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment_classification") id=String(r.tracked_by ?? "");
    }
    process.stdout.write(id);
  ' "$led_cls")"
  [[ -n "$id_cls" ]] \
    || log_fail "TEST-1364 arm 2: the contract-lane classify recorded no tracked_by at all"

  [[ "$id_add" == "$id_cls" ]] \
    || log_fail "TEST-1364: the two writers drifted — \`add\` attached to \"$id_add\" and \`classify\` attached to \"$id_cls\" for the same spec id $spec_id. One place must decide WHICH item carries the obligation."

  # ARM 3 — the measurement lane creates NO item on EITHER writer. The gate
  # that decides WHETHER anything is owed must sit above the one that decides
  # WHICH item, on both routes, or the lighter lane leaks an obligation back
  # in through whichever writer was forgotten.
  local led_m_add led_m_cls spec_m
  led_m_add="$(mk_ledger t1364-m-add)"
  spec_m="$(mk_spec "SPEC-DRAFT-t1364m.md" "spec-t1364m-fixture")"
  run_sa add --ledger "$led_m_add" --spec "$spec_m" --ref t1364-m-add-ride \
    --what "corrected the Mutation cell for TEST-001" --why "the cell never reddened" \
    --class measurement --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 3a: \`add --class measurement --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_fu list --ledger "$led_m_add" --status all
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 3a: follow-ups.mjs list must exit 0 over the produced ledger, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1364 arm 3a: \`add --class measurement\` must create NO item; the real reader found one: $OUT"

  led_m_cls="$(mk_ledger t1364-m-cls)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1364-m-cls-ride","spec":"docs/specs/SPEC-DRAFT-t1364m.md","spec_id":"spec-t1364m-fixture","what":"corrected the Mutation cell for TEST-001","why":"the cell never reddened"}' >> "$led_m_cls"
  run_sa classify --ledger "$led_m_cls" --ts "2026-09-01T01:00:00Z" --ref t1364-m-cls-ride \
    --class measurement --signoff none --why "the cell never reddened" --source "docs/ai/decisions.jsonl"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 3b: \`classify --class measurement --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_fu list --ledger "$led_m_cls" --status all
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1364 arm 3b: follow-ups.mjs list must exit 0 over the produced ledger, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1364 arm 3b: \`classify --class measurement\` must create NO item either; the real reader found one: $OUT"

  log_pass "TEST-1364 both writers reach the same single item-id decision for one spec ($id_add), and neither creates an item in the measurement lane"
}

test_1365_restamp_is_measurement_by_construction() {
  log_info "Test: \`restamp\` — the one site where the class is NOT a self-report — writes a measurement record with no tracker, creates no item, and leaves \`list --strict\` at exit 0 (TEST-1365)..."
  local specsdir led spec verdict
  specsdir="$TEST_DIR/t1365-specs"
  led="$(mk_ledger t1365)"
  spec="$(mk_freezable_spec t1365-specs/fixture.md spec-t1365-fixture direct)"
  printf '\nSee docs/specs/SPEC-DRAFT-spec-t1365-fixture.md for the frozen text.\n' >> "$spec"
  freeze_spec "$spec" || log_fail "TEST-1365 setup: real spec-freeze.mjs refused the fixture"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1365 baseline: the unrenumbered fixture must be strict-CLEAN, got $EC (stdout: $OUT) (stderr: $ERR)"

  # The allocator's own verbatim DRAFT-to-numbered substitution — the ONLY
  # state cmdRestamp is ever reached from, which is exactly why its class is
  # structural rather than declared by a caller.
  sed -i.bak 's/SPEC-DRAFT-spec-t1365-fixture\.md/SPEC-0205-spec-t1365-fixture.md/' "$spec"
  grep -qF 'SPEC-0205-spec-t1365-fixture.md' "$spec" \
    || log_fail "TEST-1365: the simulated allocator rewrite did not land"

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 1 ]] \
    || log_fail "TEST-1365 precondition: WITHOUT restamp the renumbered spec must refuse strict as undisclosed, got $EC (stdout: $OUT)"

  run_sa restamp --spec "$spec" --ref t1365-ride --ledger "$led"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1365: restamp must succeed on the renumbered spec, got $EC (stdout: $OUT) (stderr: $ERR)"

  verdict="$(node -e '
    const fs=require("fs");
    const recs=[];
    for (const line of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t==="" || t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { console.log("MALFORMED-LINE"); process.exit(0); }
      recs.push(r);
    }
    const am=recs.filter((r)=>r.type==="spec_amendment");
    const fu=recs.filter((r)=>r.type==="follow_up");
    if (am.length!==1) { console.log("AMENDMENTS="+am.length); process.exit(0); }
    if (fu.length!==0) { console.log("FOLLOWUPS="+fu.length+" ids="+fu.map((f)=>f.id).join(",")); process.exit(0); }
    const r=am[0];
    if (r.amendment_class!=="measurement") { console.log("CLASS="+JSON.stringify(r.amendment_class)); process.exit(0); }
    if (Object.prototype.hasOwnProperty.call(r,"tracked_by")) { console.log("TRACKED_BY="+r.tracked_by); process.exit(0); }
    if (r.owner_signoff!==false) { console.log("SIGNOFF="+JSON.stringify(r.owner_signoff)); process.exit(0); }
    // The disclosure itself is untouched: the from/to anchors are what make a
    // restamp a DISCLOSED mechanical change rather than a waived one, and
    // dropping them to buy the lighter lane would be the laundering.
    if (!r.from_frozen_sha256 || !r.to_frozen_sha256) { console.log("ANCHORS from="+JSON.stringify(r.from_frozen_sha256)+" to="+JSON.stringify(r.to_frozen_sha256)); process.exit(0); }
    if (r.from_frozen_sha256===r.to_frozen_sha256) { console.log("ANCHORS-EQUAL"); process.exit(0); }
    console.log("RESTAMP-MEASUREMENT-OK");
  ' "$led")"
  case "$verdict" in
    RESTAMP-MEASUREMENT-OK*) : ;;
    *) log_fail "TEST-1365: restamp did not write a disclosed, untracked measurement record — $verdict" ;;
  esac

  # SEAM-2: the ABSENCE of the item is read back through the REAL
  # follow-ups.mjs, never by grepping the ledger this suite just produced.
  run_fu list --ledger "$led" --status all
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1365: follow-ups.mjs list must exit 0 over the produced ledger, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1365: a restamp must co-create NO fu-amend- item; the real reader found one: $OUT"

  # The bucket is read through the tool's own fold, not inferred from the
  # record: `measurement` is what makes the untracked record stop being a
  # violation, and the next assertion depends on it.
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1365: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  local bucket
  bucket="$(json_field "$OUT" '(j.items.find((i)=>i.ref_id==="t1365-ride")||{}).bucket')"
  [[ "$bucket" == "measurement" ]] \
    || log_fail "TEST-1365: the restamp record must fold to bucket measurement, got \"$bucket\""

  run_sa list --ledger "$led" --specs-dir "$specsdir" --strict
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1365: WITH restamp, \`list --strict\` must exit 0 — the restamp is disclosed and owes nothing, so neither the spec scan nor the ledger may refuse; got $EC (stdout: $OUT) (stderr: $ERR)"

  log_pass "TEST-1365 restamp hardcodes the measurement class by construction: a disclosed, untracked record, no co-created item, and a clean strict gate"
}

# --- TEST-1366..TEST-1371 (SPEC-DRAFT spec-amendment-signature-asks-the-owner-
# --- too-often, Spec-AC-12..16) — the per-record route, the `list` surfaces,
# --- the structural selector, the migration, and the companion canon --------
#
# Wave 4. The partition is only worth having if it is REACHABLE one record at
# a time (TEST-1366), VISIBLE on every surface that reads the fold
# (TEST-1367/1368), SELECTED without reading a word of prose (TEST-1369),
# applied to the one tool-emitted cohort WITHOUT laundering anything else
# (TEST-1370), and NAMED in the canon a role actually reads (TEST-1371).

# RESTAMP_WHAT, duplicated here ON PURPOSE and by hand. Spec-AC-14 is a
# BYTE-EQUALITY claim about one literal, and a test that re-derived the
# literal from the source it is checking would pass for any value of it —
# including the wrong one. The real writer is run below (arm 4) so this hand
# copy can never silently rot: if the product constant moves, that arm says so
# by name rather than quietly agreeing with it.
T1369_RESTAMP_WHAT='mechanical restamp: the allocator rewrote this frozen spec’s own SPEC-DRAFT- path(s) at merge'

test_1366_classify_is_the_per_record_route() {
  log_info "Test: \`classify --class measurement\` moves ONE record and leaves its tracker open, and a \`--class\`-less classify moves no record between lanes (TEST-1366)..."
  local led ts bucket cls
  led="$(mk_ledger t1366)"

  # THE TARGET IS A LEGACY, CLASS-ABSENT RECORD with a real OPEN tracker —
  # the exact shape of every one of the ~190 records already on the live
  # ledger, which is the only population `classify --class` can move. A
  # record written by a LIVE writer always stamps its own class, and the
  # record wins over any overlay (TEST-1359 case E pins that precedence), so
  # a fixture built by `add` would be testing a route that does not exist.
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1366-ride","spec":"docs/specs/SPEC-DRAFT-t1366.md","spec_id":"spec-t1366-fixture","owner_signoff":false,"tracked_by":"fu-amend-spec-t1366-fixture","what":"corrected the Mutation cell for TEST-001","why":"the cell escaped its brackets and never reddened"}' >> "$led"
  run_fu add --ledger "$led" --id fu-amend-spec-t1366-fixture --ref t1366-ride --severity P2 \
    --what "owner sign-off owed on the post-freeze amendment(s) to spec-t1366-fixture" \
    --why "filed unsigned under the additive-with-disclosure convention" \
    --source "$led ts=2026-09-01T01:00:00Z type=spec_amendment ref_id=t1366-ride"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1366 setup: follow-ups.mjs add must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 setup: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  ts="$(json_field "$OUT" 'j.items[0].ts')"
  [[ -n "$ts" && "$ts" != "undefined" ]] \
    || log_fail "TEST-1366 setup: no spec_amendment ts could be read back"
  bucket="$(json_field "$OUT" 'j.items[0].bucket')"
  [[ "$bucket" == "unsigned-tracked" ]] \
    || log_fail "TEST-1366 setup: the legacy class-absent record must start in unsigned-tracked, got \"$bucket\""

  # The tracker's id and status BEFORE, read through the real registry CLI —
  # not inferred from the amendment record, because what must not change is
  # the ITEM, and only follow-ups.mjs owns that answer.
  local item_before
  run_fu list --ledger "$led" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 setup: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  item_before="$OUT"
  grep -qF "fu-amend-" <<<"$item_before" \
    || log_fail "TEST-1366 setup: the fixture has no open fu-amend- item to preserve; got: $item_before"

  run_sa classify --ledger "$led" --ts "$ts" --ref t1366-ride --signoff none --class measurement \
    --origin backfill --why "the amendment only corrected how the claim is measured" \
    --source "docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md D1"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1366 arm 1: \`classify --class measurement --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 arm 1: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  bucket="$(json_field "$OUT" 'j.items[0].bucket')"
  [[ "$bucket" == "measurement" ]] \
    || log_fail "TEST-1366 arm 1: the classified record must fold to bucket measurement, got \"$bucket\" — the per-record route into the partition does not work"
  cls="$(json_field "$OUT" 'j.items[0].amendment_class')"
  [[ "$cls" == "measurement" ]] \
    || log_fail "TEST-1366 arm 1: the overlay's class must be the record's resolved class, got \"$cls\""

  # THE ITEM IS LEFT ALONE. `fu-amend-` is keyed per SPEC, not per record, so
  # moving one record out of the owner queue discharges nothing: closing the
  # item here would forge the signature this whole scope refuses to forge.
  run_fu list --ledger "$led" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 arm 2: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  [[ "$OUT" == "$item_before" ]] \
    || log_fail "TEST-1366 arm 2: the previously-tracking item did not keep its open status unchanged.
BEFORE: $item_before
AFTER:  $OUT"

  # A `--class`-less classify declares NOTHING about the class. It must leave
  # the target exactly where it found it — in BOTH directions, because a
  # default applied here would silently move records every time the printed
  # remedy line is run verbatim.
  run_sa classify --ledger "$led" --ts "$ts" --ref t1366-ride --signoff none \
    --why "a second judgement about the same record, saying nothing about its class" \
    --source "docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1366.log"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1366 arm 3: a \`--class\`-less classify must still exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 arm 3: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  cls="$(json_field "$OUT" 'j.items[0].amendment_class')"
  [[ "$cls" == "measurement" ]] \
    || log_fail "TEST-1366 arm 3: a \`--class\`-less classify changed the resolved class to \"$cls\" — it must declare nothing"
  bucket="$(json_field "$OUT" 'j.items[0].bucket')"
  [[ "$bucket" == "measurement" ]] \
    || log_fail "TEST-1366 arm 3: a \`--class\`-less classify moved the record to bucket \"$bucket\""

  # ... and the same in the other direction, over a contract-lane record, so
  # the arm cannot pass merely because `measurement` happens to be sticky.
  local led2 spec2 ts2
  led2="$(mk_ledger t1366b)"
  spec2="$(mk_spec t1366b-spec.md spec-t1366b-fixture)"
  run_sa add --ledger "$led2" --spec "$spec2" --ref t1366b-ride \
    --what "widened Spec-AC-03 to cover the absent-flag case" --why "the scope outgrew the frozen predicate" \
    --class contract --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 arm 4 setup: add must exit 0, got $EC (stderr: $ERR)"
  run_sa list --ledger "$led2" --json
  ts2="$(json_field "$OUT" 'j.items[0].ts')"
  run_sa classify --ledger "$led2" --ts "$ts2" --ref t1366b-ride --signoff none \
    --why "judged again, with no claim about the class" --source "fixture"
  [[ "$EC" == 0 ]] || log_fail "TEST-1366 arm 4: classify must exit 0, got $EC (stderr: $ERR)"
  run_sa list --ledger "$led2" --json
  cls="$(json_field "$OUT" 'j.items[0].amendment_class')"
  [[ "$cls" == "contract" ]] \
    || log_fail "TEST-1366 arm 4: a \`--class\`-less classify moved a contract record to \"$cls\""

  log_pass "TEST-1366 the per-record route moves exactly one record into the measurement lane, leaves its spec-keyed tracker open and untouched, and declares nothing when --class is omitted"
}

test_1367_list_surfaces_carry_the_class() {
  log_info "Test: every \`list\` surface projects the resolved class — the row label, the per-item \`--json\` field, and the counts object (TEST-1367)..."
  local led json row
  led="$(mk_ledger t1367)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1367-m","spec_id":"spec-m","owner_signoff":false,"amendment_class":"measurement","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1367-c","spec_id":"spec-c","owner_signoff":false,"amendment_class":"contract","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T03:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1367-s","spec_id":"spec-s","owner_signoff":true,"amendment_class":"contract","what":"w","why":"y","authority":"owner said so"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T04:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1367-legacy","spec_id":"spec-l","owner_signoff":false,"what":"w","why":"y"}' >> "$led"

  # --- the human surface -----------------------------------------------------
  run_sa list --ledger "$led"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1367: plain \`list\` must exit 0, got $EC (stderr: $ERR)"

  # EVERY row, not just one: a label printed on the measurement rows alone
  # would still leave the reader unable to tell a contract row from a row
  # whose class was never resolved at all.
  local r
  for r in t1367-m:measurement t1367-c:contract t1367-s:contract t1367-legacy:contract; do
    local want_ref="${r%%:*}" want_cls="${r##*:}"
    row="$(command grep -F "$want_ref" <<<"$OUT" || true)"
    [[ -n "$row" ]] \
      || log_fail "TEST-1367: \`list\` printed no row for $want_ref; stdout was: $OUT"
    grep -qF "class=$want_cls" <<<"$row" \
      || log_fail "TEST-1367: the row for $want_ref carries no \`class=$want_cls\` label; row was: $row"
  done

  # The header is the second human surface and the only one that answers
  # "how many obligations were waived" without reading every row.
  grep -qF "measurement=1" <<<"$OUT" \
    || log_fail "TEST-1367: the \`list\` header does not count the measurement bucket; stdout was: $OUT"

  # --- the machine surface ---------------------------------------------------
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1367: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  json="$OUT"

  local verdict
  verdict="$(json_field "$json" '
    (() => {
      const want = { "t1367-m":"measurement", "t1367-c":"contract", "t1367-s":"contract", "t1367-legacy":"contract" };
      const got = {};
      for (const it of j.items) got[it.ref_id] = it.amendment_class;
      const missing = Object.keys(want).filter((k) => got[k] === undefined);
      if (missing.length) return "MISSING " + missing.join(", ");
      const bad = Object.keys(want).filter((k) => got[k] !== want[k]);
      if (bad.length) return "CLASS " + bad.map((k) => k + "=" + got[k] + " (want " + want[k] + ")").join(", ");
      if (typeof j.counts.measurement !== "number") return "COUNTS counts.measurement is " + JSON.stringify(j.counts.measurement);
      if (j.counts.measurement !== 1) return "COUNTS counts.measurement=" + j.counts.measurement + " (want 1)";
      return "JSON-OK";
    })()
  ')"
  [[ "$verdict" == "JSON-OK" ]] \
    || log_fail "TEST-1367: \`list --json\` does not project the class per item plus a measurement count — $verdict"

  log_pass "TEST-1367 the class is on every list surface: a \`class=\` label on every row, \`amendment_class\` per --json item, and a counted measurement bucket in both headers"
}

test_1368_status_measurement_is_an_enumerable_view() {
  log_info "Test: \`--status measurement\` is a named, enumerable view returning ONLY measurement rows, and an unknown status still exits 2 (TEST-1368)..."
  local led shown refs
  led="$(mk_ledger t1368)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1368-m1","spec_id":"spec-m1","owner_signoff":false,"amendment_class":"measurement","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T02:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1368-m2","spec_id":"spec-m2","owner_signoff":false,"amendment_class":"measurement","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T03:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1368-c","spec_id":"spec-c","owner_signoff":false,"amendment_class":"contract","what":"w","why":"y"}' >> "$led"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T04:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1368-s","spec_id":"spec-s","owner_signoff":true,"amendment_class":"measurement","what":"w","why":"y","authority":"owner said so"}' >> "$led"

  run_sa list --ledger "$led" --status measurement --json
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1368: \`--status measurement\` must be ACCEPTED and exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"

  # The view must be NON-EMPTY and must be the measurement bucket exactly: an
  # accepted filter that selects nothing answers "show me every waived
  # obligation" with silence, which is the same failure as refusing it.
  shown="$(json_field "$OUT" 'j.items.length')"
  [[ "$shown" == "2" ]] \
    || log_fail "TEST-1368: \`--status measurement\` returned $shown row(s), want the 2 measurement-bucket records (the signed one is NOT in this view — a signature outranks the class)"
  refs="$(json_field "$OUT" 'j.items.map((it) => it.ref_id + ":" + it.bucket).sort().join(",")')"
  [[ "$refs" == "t1368-m1:measurement,t1368-m2:measurement" ]] \
    || log_fail "TEST-1368: \`--status measurement\` must return ONLY measurement-bucket rows, got: $refs"

  # The closed vocabulary of --status is unchanged for everything else, and
  # the refusal still enumerates what IS legal — including the new name.
  run_sa list --ledger "$led" --status bogus
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1368: an unknown --status must still exit 2, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF "measurement" <<<"$ERR" \
    || log_fail "TEST-1368: the --status refusal must name \`measurement\` among the legal values; stderr was: $ERR"
  grep -qF "unsigned" <<<"$ERR" \
    || log_fail "TEST-1368: the --status refusal must still name the pre-existing values; stderr was: $ERR"

  log_pass "TEST-1368 \`--status measurement\` is an accepted, non-empty, exactly-the-bucket view, and the unknown-status refusal still enumerates the whole closed set"
}

test_1369_tool_restamp_is_structural() {
  log_info "Test: \`tool_restamp\` is the CONJUNCTION of both anchor fields and a byte-equal \`what\` — no prose is read, and either half alone is false (TEST-1369)..."
  local led verdict
  led="$(mk_ledger t1369)"

  # Five shapes around ONE conjunction. The `what` below is the product's own
  # RESTAMP_WHAT, copied by hand (see the constant's comment) — record A is
  # the only one that satisfies both halves. Record B's near miss is a
  # trailing FULL STOP, not a trailing space: `str()` trims, so a whitespace
  # difference is not a difference at all and would have made B a second
  # positive dressed up as a negative control.
  local w="$T1369_RESTAMP_WHAT"
  node -e '
    const fs = require("fs");
    const [led, what] = process.argv.slice(1);
    const base = { v: 1, actor: "a", type: "spec_amendment", why: "y", owner_signoff: false };
    const rows = [
      { ...base, ts: "2026-09-01T01:00:00Z", ref_id: "t1369-a", spec_id: "spec-a", what, from_frozen_sha256: "aa", to_frozen_sha256: "bb" },
      { ...base, ts: "2026-09-01T02:00:00Z", ref_id: "t1369-b", spec_id: "spec-b", what: what + ".", from_frozen_sha256: "aa", to_frozen_sha256: "bb" },
      { ...base, ts: "2026-09-01T03:00:00Z", ref_id: "t1369-c", spec_id: "spec-c", what, from_frozen_sha256: "aa" },
      { ...base, ts: "2026-09-01T04:00:00Z", ref_id: "t1369-d", spec_id: "spec-d", what, to_frozen_sha256: "bb" },
      { ...base, ts: "2026-09-01T05:00:00Z", ref_id: "t1369-e", spec_id: "spec-e", what },
    ];
    fs.appendFileSync(led, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  ' "$led" "$w"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1369: \`list --json\` must exit 0 over the fixture ledger, got $EC (stderr: $ERR)"

  verdict="$(json_field "$OUT" '
    (() => {
      const want = { "t1369-a": true, "t1369-b": false, "t1369-c": false, "t1369-d": false, "t1369-e": false };
      const got = {};
      for (const it of j.items) got[it.ref_id] = it.tool_restamp;
      const missing = Object.keys(want).filter((k) => typeof got[k] !== "boolean");
      if (missing.length) return "MISSING tool_restamp is not a boolean on: " + missing.map((k) => k + "=" + JSON.stringify(got[k])).join(", ");
      const bad = Object.keys(want).filter((k) => got[k] !== want[k]);
      if (bad.length) return "SELECTOR " + bad.map((k) => k + "=" + got[k] + " (want " + want[k] + ")").join(", ");
      return "SELECTOR-OK";
    })()
  ')"
  [[ "$verdict" == "SELECTOR-OK" ]] \
    || log_fail "TEST-1369: the structural selector is wrong — $verdict"

  # The hand copy above is kept honest by the REAL writer: cmdRestamp is run
  # end to end and its record must be selected. If the product constant ever
  # moves, this arm names it instead of agreeing with it by construction.
  local specsdir led2 spec rwhat
  specsdir="$TEST_DIR/t1369-specs"
  led2="$(mk_ledger t1369b)"
  spec="$(mk_freezable_spec t1369-specs/fixture.md spec-t1369-fixture direct)"
  printf '\nSee docs/specs/SPEC-DRAFT-spec-t1369-fixture.md for the frozen text.\n' >> "$spec"
  freeze_spec "$spec" || log_fail "TEST-1369 setup: real spec-freeze.mjs refused the fixture"
  sed -i.bak 's/SPEC-DRAFT-spec-t1369-fixture\.md/SPEC-0206-spec-t1369-fixture.md/' "$spec"
  run_sa restamp --spec "$spec" --ref t1369-ride --ledger "$led2"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1369 arm 4: restamp must succeed on the renumbered fixture, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led2" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1369 arm 4: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  verdict="$(json_field "$OUT" 'String(j.items.length) + ":" + String(j.items[0] && j.items[0].tool_restamp)')"
  [[ "$verdict" == "1:true" ]] \
    || log_fail "TEST-1369 arm 4: the record the REAL restamp wrote must be selected by the structural selector, got \"$verdict\" — the hand-copied RESTAMP_WHAT and the product constant have drifted"
  rwhat="$(node -e '
    const fs = require("fs");
    for (const line of fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/)) {
      const t = line.trim(); if (t === "" || t.startsWith("#")) continue;
      const r = JSON.parse(t);
      if (r.type === "spec_amendment") { process.stdout.write(String(r.what)); break; }
    }
  ' "$led2")"
  [[ "$rwhat" == "$w" ]] \
    || log_fail "TEST-1369 arm 4: the real restamp wrote what=\"$rwhat\" but this suite pins \"$w\""

  log_pass "TEST-1369 tool_restamp is the conjunction of both anchors and a byte-equal what: one real restamp record selected, four near misses rejected, no prose read"
}

test_1370_migration_moves_only_the_structural_cohort() {
  log_info "Test: the documented migration loop moves exactly the structurally-selected cohort, signs nothing, closes no item and edits no line (TEST-1370)..."
  local led before_bytes fu_before fu_after json moved counts_before counts_after
  led="$(mk_ledger t1370)"

  local w="$T1369_RESTAMP_WHAT"
  # Three cohort records (both anchors + the byte-equal what), each tracked by
  # an OPEN fu-amend- item, exactly as the live cohort is. Two non-cohort:
  #   N1 carries BOTH anchors but a different `what` — the record that tells a
  #      structural selector apart from a sloppy one;
  #   N2 is an ordinary legacy unsigned-tracked record with no anchors at all.
  node -e '
    const fs = require("fs");
    const [led, what] = process.argv.slice(1);
    const base = { v: 1, actor: "a", type: "spec_amendment", why: "y", owner_signoff: false };
    const rows = [];
    for (const n of [1, 2, 3]) {
      rows.push({ ...base, ts: `2026-09-0${n}T01:00:00Z`, ref_id: `t1370-cohort-${n}`, spec_id: `spec-coh-${n}`,
        what, from_frozen_sha256: `aa${n}`, to_frozen_sha256: `bb${n}`, tracked_by: `fu-amend-coh-${n}` });
      rows.push({ v: 1, ts: `2026-09-0${n}T01:00:01Z`, actor: "a", type: "follow_up", id: `fu-amend-coh-${n}`,
        ref_id: `t1370-cohort-${n}`, severity: "P2", finding: `owner sign-off owed on spec-coh-${n}`,
        decision: "filed unsigned under the additive-with-disclosure convention", source: "fixture" });
    }
    rows.push({ ...base, ts: "2026-09-04T01:00:00Z", ref_id: "t1370-n1", spec_id: "spec-n1",
      what: "hand-written amendment that happens to carry both anchor fields", from_frozen_sha256: "cc", to_frozen_sha256: "dd",
      tracked_by: "fu-amend-n1" });
    rows.push({ v: 1, ts: "2026-09-04T01:00:01Z", actor: "a", type: "follow_up", id: "fu-amend-n1", ref_id: "t1370-n1",
      severity: "P2", finding: "owner sign-off owed on spec-n1", decision: "filed unsigned", source: "fixture" });
    rows.push({ ...base, ts: "2026-09-05T01:00:00Z", ref_id: "t1370-n2", spec_id: "spec-n2",
      what: "widened Spec-AC-02", tracked_by: "fu-amend-n2" });
    rows.push({ v: 1, ts: "2026-09-05T01:00:01Z", actor: "a", type: "follow_up", id: "fu-amend-n2", ref_id: "t1370-n2",
      severity: "P2", finding: "owner sign-off owed on spec-n2", decision: "filed unsigned", source: "fixture" });
    fs.appendFileSync(led, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  ' "$led" "$w"

  before_bytes="$TEST_DIR/t1370.before"
  cp "$led" "$before_bytes"

  run_fu list --ledger "$led" --status all
  [[ "$EC" == 0 ]] || log_fail "TEST-1370 setup: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  fu_before="$OUT"

  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1370 setup: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  counts_before="$(json_field "$OUT" '
    "total=" + j.counts.total + " signed=" + j.counts.signed + " measurement=" + j.counts.measurement +
    " unsigned-tracked=" + j.counts["unsigned-tracked"] + " unsigned-untracked=" + j.counts["unsigned-untracked"] +
    " unclassified=" + j.counts.unclassified
  ')"
  [[ "$counts_before" == "total=5 signed=0 measurement=0 unsigned-tracked=5 unsigned-untracked=0 unclassified=0" ]] \
    || log_fail "TEST-1370 setup: the fixture must start as five unsigned-tracked records, got: $counts_before"

  # --- THE DOCUMENTED MIGRATION LOOP ----------------------------------------
  # Selection is STRUCTURAL and comes from the tool's own fold, never from a
  # regex over this ledger: `tool_restamp` is the conjunction TEST-1369 pins.
  # Already-measurement and already-signed records are skipped so the loop is
  # idempotent and can never re-decide a record somebody else decided.
  local cohort
  cohort="$(json_field "$OUT" '
    j.items
      .filter((it) => it.tool_restamp === true && it.bucket !== "signed" && it.amendment_class !== "measurement")
      .map((it) => it.ts + "\t" + it.ref_id)
      .join("\n")
  ')"
  moved=0
  if [[ -n "$cohort" ]]; then
    local mts mref
    while IFS=$'\t' read -r mts mref; do
      [[ -n "$mts" ]] || continue
      run_sa classify --ledger "$led" --ts "$mts" --ref "$mref" --signoff none --class measurement --origin backfill \
        --why "tool-emitted restamp: allocator anchor drift disclosed by spec-amend restamp, which owes no owner signature" \
        --source "docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md D3 (structural selector: both frozen-sha anchors plus a byte-equal RESTAMP_WHAT)" </dev/null
      [[ "$EC" == 0 ]] \
        || log_fail "TEST-1370: the migration's classify refused ts=$mts ref=$mref, got $EC (stdout: $OUT) (stderr: $ERR)"
      moved=$(( moved + 1 ))
    done <<<"$cohort"
  fi

  [[ "$moved" == "3" ]] \
    || log_fail "TEST-1370: the migration moved $moved record(s), want exactly the 3 structurally-selected cohort records — a selector that reads anything but the conjunction sweeps in t1370-n1"

  # --- what the migration must NOT have done --------------------------------
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1370: \`list --json\` must exit 0 after the migration, got $EC (stderr: $ERR)"
  json="$OUT"
  counts_after="$(json_field "$json" '
    "total=" + j.counts.total + " signed=" + j.counts.signed + " measurement=" + j.counts.measurement +
    " unsigned-tracked=" + j.counts["unsigned-tracked"] + " unsigned-untracked=" + j.counts["unsigned-untracked"] +
    " unclassified=" + j.counts.unclassified
  ')"
  [[ "$counts_after" == "total=5 signed=0 measurement=3 unsigned-tracked=2 unsigned-untracked=0 unclassified=0" ]] \
    || log_fail "TEST-1370: the post-migration counts are wrong — signed must be unchanged at 0, measurement must equal the 3 appended overlays, unsigned-tracked must fall by exactly 3, total must be unchanged; got: $counts_after"

  local still
  still="$(json_field "$json" '
    j.items.filter((it) => it.bucket !== "measurement").map((it) => it.ref_id).sort().join(",")
  ')"
  [[ "$still" == "t1370-n1,t1370-n2" ]] \
    || log_fail "TEST-1370: the records left outside the measurement lane must be exactly the two non-cohort ones, got: $still"

  # HAZ-LEDGER: the migration APPENDS. Every pre-existing byte is still there,
  # at the same offset, and only new lines follow it.
  local before_size
  before_size="$(/usr/bin/wc -c < "$before_bytes" | tr -d ' ')"
  local head_now
  head_now="$TEST_DIR/t1370.headnow"
  dd if="$led" of="$head_now" bs=1 count="$before_size" 2>/dev/null
  cmp -s "$before_bytes" "$head_now" \
    || log_fail "TEST-1370: the migration modified pre-existing bytes — docs/ai/decisions.jsonl is append-only (HAZ-LEDGER)"

  # No item changed status, and no item was created: `fu-amend-` is keyed per
  # SPEC, so closing one here would forge the signature this ride refuses.
  run_fu list --ledger "$led" --status all
  [[ "$EC" == 0 ]] || log_fail "TEST-1370: follow-ups.mjs list must exit 0 after the migration, got $EC (stderr: $ERR)"
  fu_after="$OUT"
  [[ "$fu_after" == "$fu_before" ]] \
    || log_fail "TEST-1370: the migration changed the follow-up registry.
BEFORE: $fu_before
AFTER:  $fu_after"

  log_pass "TEST-1370 the migration moves exactly the structural cohort (3 of 5), signs nothing, closes no item, creates no item, and appends without touching one pre-existing byte"
}

test_1371_canon_names_the_two_class_partition() {
  log_info "Test: the canon a role actually reads names both class values — ROLE_COMMON's POST-FREEZE block and AUTONOMOUS_LOOP section 6a (TEST-1371)..."
  local rc="$PROJECT_ROOT/.aai/ROLE_COMMON.md" block
  [[ -f "$rc" ]] || log_fail "TEST-1371: .aai/ROLE_COMMON.md does not exist"

  # The POST-FREEZE block specifically, not the file: a role reads the block
  # its pointer sends it to, and a mention anywhere else would not reach it.
  block="$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/);
    let out = [], on = false;
    for (const l of lines) {
      if (/^## /.test(l)) on = /POST-FREEZE/.test(l);
      if (on) out.push(l);
    }
    process.stdout.write(out.join("\n"));
  ' "$rc")"
  [[ -n "$block" ]] \
    || log_fail "TEST-1371: .aai/ROLE_COMMON.md has no POST-FREEZE section to carry the partition"
  grep -qF -- "--class contract" <<<"$block" \
    || log_fail "TEST-1371: the POST-FREEZE block does not name \`--class contract\`; block was:
$block"
  grep -qF -- "--class measurement" <<<"$block" \
    || log_fail "TEST-1371: the POST-FREEZE block does not name \`--class measurement\`; block was:
$block"

  # The BODY of the convention lives in AUTONOMOUS_LOOP 6a (outside the prompt
  # glob, zero ledger cost), and it is where the partition is explained rather
  # than merely named.
  local sixa
  sixa="$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split(/\r?\n/);
    let out = [], on = false;
    for (const l of lines) {
      if (/^### /.test(l)) on = /^### 6a\)/.test(l);
      if (on) out.push(l);
    }
    process.stdout.write(out.join("\n"));
  ' "$CANON")"
  [[ -n "$sixa" ]] \
    || log_fail "TEST-1371: .aai/system/AUTONOMOUS_LOOP.md has no section 6a"
  local needle
  for needle in "contract" "measurement" "--class"; do
    grep -qF -- "$needle" <<<"$sixa" \
      || log_fail "TEST-1371: AUTONOMOUS_LOOP section 6a does not state the two-class partition (missing \"$needle\")"
  done

  # .aai/SKILL_PR.prompt.md is deliberately NOT edited by this scope: the
  # AMENDMENT GATE's contract ("exit 0 proceed, exit 1 run what it prints") is
  # unchanged, so the live prompt glob must not grow for it.
  grep -qF -- "--class" "$PROJECT_ROOT/.aai/SKILL_PR.prompt.md" \
    && log_fail "TEST-1371: .aai/SKILL_PR.prompt.md names --class — this scope deliberately leaves it untouched (its AMENDMENT GATE contract did not change)"

  log_pass "TEST-1371 the POST-FREEZE block names both class values, AUTONOMOUS_LOOP 6a carries the partition body, and SKILL_PR is untouched"
}

# --- TEST-1373 (SPEC-DRAFT spec-amendment-signature-asks-the-owner-too-often,
# --- Spec-AC-17) — the obligation decision and the fold's bucket cannot
# --- disagree ----------------------------------------------------------------
#
# Code review round 1, BLOCKING, reproduced. `cmdClassify` decided WHETHER an
# owner obligation was owed from the `--class` FLAG, while `foldAmendments`
# lets a record's OWN `amendment_class` outrank every overlay. The two
# therefore disagreed for any record that carries its own class — which is
# EVERY record a live writer produces from now on. Reproduced before the fix:
#
#   add --class measurement …                  -> bucket measurement, 0 items
#   classify --ts … --class contract --signoff none
#   -> "classified … — bucket measurement" AND "tracked by fu-amend-spec-x"
#   -> follow-ups: open fu-amend-spec-x P2 "owner sign-off owed …"
#
# An open P2 owner obligation filed against a record whose bucket is
# `measurement`: the one thing this scope promised never to create, and one
# nothing drains, because the bucket the drain route reads never moves. The
# mirror direction (`--class measurement` over a self-declared `contract`
# record) printed "owing no owner signature and no tracked item" directly
# beneath a `unsigned-tracked` bucket line in the SAME output.
#
# This arm pins the INVARIANT, not the one reproduction: `owes` is read off
# the same `foldAmendments` that assigns the bucket, so the two cannot
# disagree, and a `--class` that the fold would not adopt is refused rather
# than silently acted on.

test_1373_class_flag_cannot_disagree_with_the_fold() {
  log_info "Test: a \`classify --class\` the fold would not adopt is REFUSED, and no measurement-bucket record is ever given an owner obligation (TEST-1373)..."
  local led spec ts before bucket cls same

  # ARM 1 — the reproduction. The target is built by the REAL writer, so it
  # carries its own stamped class, which is the population the defect reached.
  led="$(mk_ledger t1373a)"
  spec="$(mk_spec "SPEC-DRAFT-t1373a.md" "spec-t1373a-fixture")"
  run_sa add --ledger "$led" --spec "$spec" --ref t1373a-ride \
    --what "corrected the Mutation cell for TEST-001" --why "the cell never reddened" \
    --class measurement --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1373 arm 1 setup: \`add --class measurement --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 1 setup: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  ts="$(json_field "$OUT" 'j.items[0].ts')"
  [[ -n "$ts" && "$ts" != "undefined" ]] \
    || log_fail "TEST-1373 arm 1 setup: no spec_amendment ts could be read back"

  before="$TEST_DIR/t1373a-before.jsonl"
  cp "$led" "$before"

  run_sa classify --ledger "$led" --ts "$ts" --ref t1373a-ride \
    --class contract --signoff none --why "judged again, claiming the heavier lane" --source "fixture"
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1373 arm 1: \`classify --class contract\` over a record that DECLARES \`measurement\` must be refused as a usage error (exit 2). The record's own class outranks every overlay, so the flag cannot move the bucket — accepting it only lets the obligation decision disagree with the bucket. Got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF -- "--class contract" <<<"$ERR" \
    || log_fail "TEST-1373 arm 1: the refusal must name the flag it refuses; stderr was: $ERR"
  grep -qF -- '"measurement"' <<<"$ERR" \
    || log_fail "TEST-1373 arm 1: the refusal must name the class the fold actually resolves; stderr was: $ERR"

  same="$(node -e '
    const fs=require("fs");
    const a=fs.readFileSync(process.argv[1]); const b=fs.readFileSync(process.argv[2]);
    console.log(a.equals(b) ? "IDENTICAL" : "CHANGED by "+(b.length-a.length)+" byte(s)");
  ' "$before" "$led")"
  [[ "$same" == "IDENTICAL" ]] \
    || log_fail "TEST-1373 arm 1: a refused classify must append NOTHING — the ledger $same"

  # The invariant itself, read through the two REAL readers rather than
  # inferred from the refusal: the bucket is still measurement and the
  # registry holds no obligation for it.
  run_sa list --ledger "$led" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 1: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  bucket="$(json_field "$OUT" 'j.items[0].bucket')"
  cls="$(json_field "$OUT" 'j.items[0].amendment_class')"
  [[ "$bucket" == "measurement" && "$cls" == "measurement" ]] \
    || log_fail "TEST-1373 arm 1: the record must still fold to the measurement lane, got bucket \"$bucket\" class \"$cls\""
  run_fu list --ledger "$led" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 1: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1373 arm 1: a measurement-bucket record must carry NO open owner obligation — an obligation whose bucket never moves has no outflow; the real reader found: $OUT"

  # ARM 2 — the mirror. A self-declared `contract` record cannot be talked
  # into the lighter lane by an overlay either, and its open obligation
  # survives the attempt untouched.
  local led2 spec2 ts2 before2 same2
  led2="$(mk_ledger t1373b)"
  spec2="$(mk_spec "SPEC-DRAFT-t1373b.md" "spec-t1373b-fixture")"
  run_sa add --ledger "$led2" --spec "$spec2" --ref t1373b-ride \
    --what "widened Spec-AC-01 to cover the absent-key case" --why "the frozen predicate did not cover the data" \
    --class contract --signoff none
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1373 arm 2 setup: \`add --class contract --signoff none\` must exit 0, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led2" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 2 setup: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  ts2="$(json_field "$OUT" 'j.items[0].ts')"
  [[ -n "$ts2" && "$ts2" != "undefined" ]] \
    || log_fail "TEST-1373 arm 2 setup: no spec_amendment ts could be read back"
  before2="$TEST_DIR/t1373b-before.jsonl"
  cp "$led2" "$before2"

  run_sa classify --ledger "$led2" --ts "$ts2" --ref t1373b-ride \
    --class measurement --signoff none --why "judged again, claiming the lighter lane" --source "fixture"
  [[ "$EC" == 2 ]] \
    || log_fail "TEST-1373 arm 2: \`classify --class measurement\` over a record that DECLARES \`contract\` must be refused as a usage error (exit 2) — otherwise the run prints \"owing no owner signature\" under a bucket line that still says unsigned-tracked. Got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF -- "--class measurement" <<<"$ERR" \
    || log_fail "TEST-1373 arm 2: the refusal must name the flag it refuses; stderr was: $ERR"
  grep -qF -- '"contract"' <<<"$ERR" \
    || log_fail "TEST-1373 arm 2: the refusal must name the class the fold actually resolves; stderr was: $ERR"

  same2="$(node -e '
    const fs=require("fs");
    const a=fs.readFileSync(process.argv[1]); const b=fs.readFileSync(process.argv[2]);
    console.log(a.equals(b) ? "IDENTICAL" : "CHANGED by "+(b.length-a.length)+" byte(s)");
  ' "$before2" "$led2")"
  [[ "$same2" == "IDENTICAL" ]] \
    || log_fail "TEST-1373 arm 2: a refused classify must append NOTHING — the ledger $same2"

  run_fu list --ledger "$led2" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 2: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-spec-t1373b-fixture" <<<"$OUT" \
    || log_fail "TEST-1373 arm 2: the contract record's obligation must still be OPEN after the refusal; the real reader found: $OUT"

  # ARM 3 — the refusal is not over-broad. A `--class` that AGREES with the
  # class the fold resolves changes nothing and is still accepted: only a flag
  # the fold would NOT adopt is refused, so the remedy `--strict` prints (which
  # carries no `--class` at all) and every agreeing caller keep working.
  run_sa classify --ledger "$led2" --ts "$ts2" --ref t1373b-ride \
    --class contract --signoff none --why "judged again, agreeing with the record" --source "fixture"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1373 arm 3: a \`--class\` that agrees with the class the fold resolves must still be accepted, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led2" --json
  bucket="$(json_field "$OUT" 'j.items[0].bucket')"
  [[ "$bucket" == "unsigned-tracked" ]] \
    || log_fail "TEST-1373 arm 3: the agreeing classify must leave the record in its own lane, got bucket \"$bucket\""

  # ARM 4 — the positive control for the route that DOES exist. A legacy,
  # class-absent record has no declaration of its own, so the overlay's class
  # wins the fold, and the obligation decision follows it: measurement bucket,
  # no obligation. The fix must not have bought agreement by refusing
  # everything.
  local led3 bucket3
  led3="$(mk_ledger t1373c)"
  printf '%s\n' '{"v":1,"ts":"2026-09-01T01:00:00Z","actor":"a","type":"spec_amendment","ref_id":"t1373c-ride","spec":"docs/specs/SPEC-DRAFT-t1373c.md","spec_id":"spec-t1373c-fixture","owner_signoff":false,"what":"corrected the Mutation cell for TEST-001","why":"the cell escaped its brackets and never reddened"}' >> "$led3"
  run_sa classify --ledger "$led3" --ts "2026-09-01T01:00:00Z" --ref t1373c-ride \
    --class measurement --signoff none --why "the cell never reddened" --source "fixture"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1373 arm 4: \`classify --class measurement\` over a CLASS-ABSENT legacy record must still exit 0 — that is the one population the overlay can move, got $EC (stdout: $OUT) (stderr: $ERR)"
  run_sa list --ledger "$led3" --json
  bucket3="$(json_field "$OUT" 'j.items[0].bucket')"
  [[ "$bucket3" == "measurement" ]] \
    || log_fail "TEST-1373 arm 4: the class-absent record must move to the measurement lane, got \"$bucket3\""
  run_fu list --ledger "$led3" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1373 arm 4: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1373 arm 4: the measurement-lane record must carry no owner obligation; the real reader found: $OUT"

  log_pass "TEST-1373 the obligation decision is read off the same fold that assigns the bucket: a --class the fold would not adopt is refused and appends nothing, an agreeing one still works, and no measurement-bucket record is ever given an owner obligation"
}

# --- TEST-1374 (Spec-AC-18) — the restamp cause is MEASURED, not asserted ----
#
# mk_linked_freezable_spec <relpath-under-TEST_DIR> <id> <intake-slug> -> a
# not-yet-frozen fixture spec that, like every real spec in this corpus,
# carries a frontmatter `links.intake` AND names both its own DRAFT path and
# its intake's DRAFT path in the hashed body. That second reference is the
# reason the cause check cannot look at the spec's self-reference alone: an
# `--all` allocator run numbers the intake in the SAME batch, so both tokens
# are rewritten inside one frozen spec.
mk_linked_freezable_spec() {
  local f="$TEST_DIR/$1" id="$2" intake="$3"
  mkdir -p "$(dirname "$f")"
  {
    echo "---"
    echo "id: $id"
    echo "type: spec"
    echo "number: null"
    echo "status: draft"
    echo "links:"
    echo "  intake: docs/issues/CHANGE-DRAFT-$intake.md"
    echo "---"
    echo ""
    echo "# fixture $id"
    echo ""
    echo "## Links"
    echo "- Intake: docs/issues/CHANGE-DRAFT-$intake.md"
    echo "- This spec: docs/specs/SPEC-DRAFT-$id.md"
    echo ""
    echo "## Implementation strategy"
    echo "- Strategy: direct"
    echo ""
    echo "## Acceptance Criteria Status"
    echo ""
    echo "| Spec-AC    | Description | Status | Evidence | Review-By | Notes |"
    echo "|------------|-------------|--------|----------|-----------|-------|"
    echo "| Spec-AC-01 | original description text | planned | — | — | |"
    echo ""
    echo "## Test Plan"
    echo ""
    echo "| Test ID | Spec-AC | Type | File path (expected) | Description | Status |"
    echo "|---------|---------|------|-----------------------|--------------|--------|"
    echo "| TEST-001 | Spec-AC-01 | unit | tests/x.sh | does the thing | pending |"
  } > "$f"
  printf '%s' "$f"
}

# `restamp` used to HARDCODE `measurement` on the strength of a code comment
# claiming it was "reachable only" after an allocator rewrite. Nothing checked
# that: `computeSpecRestamp` asks only whether the hash MOVED, so any
# post-freeze content edit followed by `restamp` bought the light lane — the
# laundering route this very tool exists to close, opened inside it. The cause
# is now decided from the bytes, and this arm set pins all three outcomes.
test_1374_restamp_cause_is_measured_not_asserted() {
  log_info "Test: \`restamp\` takes the measurement lane only when reverse-applying the allocator's own rewrite reproduces the stored anchor, and the contract lane whenever it does not (TEST-1374)..."
  local specsdir ledA ledB ledC specA specB specC frozen verdict

  specsdir="$TEST_DIR/t1374-specs"
  specA="$(mk_linked_freezable_spec t1374-specs/a.md spec-t1374-fixture t1374-intake)"
  freeze_spec "$specA" || log_fail "TEST-1374 setup: real spec-freeze.mjs refused the fixture"
  # ONE frozen original, copied per arm, so every arm starts from the SAME
  # anchor and the only difference between them is what happened next.
  frozen="$TEST_DIR/t1374-frozen.md"
  cp "$specA" "$frozen"
  cp "$frozen" "$TEST_DIR/t1374-specs/b.md"; specB="$TEST_DIR/t1374-specs/b.md"
  cp "$frozen" "$TEST_DIR/t1374-specs/c.md"; specC="$TEST_DIR/t1374-specs/c.md"
  ledA="$(mk_ledger t1374a)"; ledB="$(mk_ledger t1374b)"; ledC="$(mk_ledger t1374c)"

  # --- ARM 1: a CONTRACT-shaped edit takes the contract lane -----------------
  # The AC Description cell is inside the contract projection and is exactly
  # what the spec PROMISES. Before this fix the same two commands below
  # reported "a measurement-class disclosure owing no owner signature and no
  # tracked item" over it.
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$specB"
  grep -qF 'a DIFFERENT promise this spec never made' "$specB" \
    || log_fail "TEST-1374 arm 1: the contract-shaped edit did not land"

  run_sa restamp --spec "$specB" --ref t1374b-ride --ledger "$ledB"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1374 arm 1: restamp must still re-anchor and disclose, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF 'measurement-class disclosure owing no owner signature' <<<"$OUT" \
    && log_fail "TEST-1374 arm 1: an edit to what the spec PROMISES (an AC Description cell) must not be announced as a measurement-class disclosure owing no owner signature and no tracked item — \`restamp\` may not claim the allocator as its cause unless the bytes prove it; stdout: $OUT"
  grep -qF 'the allocator is NOT verified as the cause' <<<"$OUT" \
    || log_fail "TEST-1374 arm 1: an unverified cause must SAY so rather than name the allocator; stdout: $OUT"

  run_sa list --ledger "$ledB" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1374 arm 1: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  verdict="$(json_field "$OUT" '(j.items[0]||{}).amendment_class + "/" + (j.items[0]||{}).bucket + "/" + (j.items[0]||{}).tool_restamp')"
  [[ "$verdict" == "contract/unsigned-tracked/false" ]] \
    || log_fail "TEST-1374 arm 1: an unverified cause must land in the contract lane with a tracker and must NOT be selected as a tool restamp, got \"$verdict\""

  # The record must not claim a cause it could not confirm — the `what` is the
  # unverified literal, never the mechanical-restamp one.
  verdict="$(json_field "$OUT" '/allocator rewrote this frozen spec/.test(String((j.items[0]||{}).what)) ? "CLAIMS-ALLOCATOR" : (/does not explain/.test(String((j.items[0]||{}).what)) ? "SAYS-UNVERIFIED" : "OTHER:" + (j.items[0]||{}).what)')"
  [[ "$verdict" == "SAYS-UNVERIFIED" ]] \
    || log_fail "TEST-1374 arm 1: the record's \`what\` must say the drift is unexplained, got \"$verdict\""

  # SEAM-2 — the obligation is read back through the REAL follow-ups.mjs.
  run_fu list --ledger "$ledB" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1374 arm 1: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-spec-t1374-fixture" <<<"$OUT" \
    || log_fail "TEST-1374 arm 1: the contract lane must co-create an OPEN owner obligation; the real reader found: $OUT"

  # ...and the obligation is VISIBLE on the gate's own surface.
  run_sa list --ledger "$ledB" --specs-dir "$specsdir" --strict
  grep -qF 'class=contract' <<<"$OUT" \
    || log_fail "TEST-1374 arm 1: \`list --strict\` must show the record in the contract lane; stdout: $OUT"
  grep -qF 'tracked_by=fu-amend-spec-t1374-fixture' <<<"$OUT" \
    || log_fail "TEST-1374 arm 1: \`list --strict\` must name the tracker the amendment owes; stdout: $OUT"

  # --- ARM 2: an allocator rename MIXED with an unrelated edit ---------------
  # The dangerous shape: a real mechanical rewrite is present, so the drift
  # LOOKS allocator-caused, but the content also moved for another reason.
  # Partial resemblance must buy nothing.
  sed -i.bak -e 's/SPEC-DRAFT-spec-t1374-fixture/SPEC-0311-spec-t1374-fixture/g' \
             -e 's/does the thing/does a different thing/' "$specC"
  grep -qF 'SPEC-0311-spec-t1374-fixture' "$specC" \
    || log_fail "TEST-1374 arm 2: the simulated allocator rewrite did not land"

  run_sa restamp --spec "$specC" --ref t1374c-ride --ledger "$ledC"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1374 arm 2: restamp must still re-anchor and disclose, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF 'does not reproduce the stored anchor' <<<"$OUT" \
    || log_fail "TEST-1374 arm 2: the refusal to credit the allocator must name the failed reversal; stdout: $OUT"

  run_sa list --ledger "$ledC" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1374 arm 2: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  verdict="$(json_field "$OUT" '(j.items[0]||{}).amendment_class + "/" + (j.items[0]||{}).bucket + "/" + (j.items[0]||{}).tool_restamp')"
  [[ "$verdict" == "contract/unsigned-tracked/false" ]] \
    || log_fail "TEST-1374 arm 2: a real allocator rename alongside an unrelated edit must NOT buy the light lane, got \"$verdict\""

  # --- ARM 3: a GENUINE allocator rename still takes the light lane ----------
  # Both tokens the allocator's `content.split(oldBase).join(newBase)` pass
  # rewrites at merge: this spec's own DRAFT path and its intake's.
  sed -i.bak -e 's/SPEC-DRAFT-spec-t1374-fixture/SPEC-0310-spec-t1374-fixture/g' \
             -e 's/CHANGE-DRAFT-t1374-intake/CHANGE-0310-t1374-intake/g' "$specA"
  grep -qF 'SPEC-0310-spec-t1374-fixture' "$specA" \
    || log_fail "TEST-1374 arm 3: the simulated allocator rewrite did not land"

  run_sa restamp --spec "$specA" --ref t1374a-ride --ledger "$ledA"
  [[ "$EC" == 0 ]] \
    || log_fail "TEST-1374 arm 3: restamp must succeed on a genuine allocator rename, got $EC (stdout: $OUT) (stderr: $ERR)"
  grep -qF 'the allocator is PROVEN to be the cause' <<<"$OUT" \
    || log_fail "TEST-1374 arm 3: a verified cause must SAY it was verified; stdout: $OUT"
  grep -qF 'CHANGE-0310-t1374-intake' <<<"$OUT" \
    || log_fail "TEST-1374 arm 3: the intake's DRAFT-to-numbered rewrite is part of the same allocator batch and must be among the reversed tokens; stdout: $OUT"

  run_sa list --ledger "$ledA" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1374 arm 3: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  verdict="$(json_field "$OUT" '(j.items[0]||{}).amendment_class + "/" + (j.items[0]||{}).bucket + "/" + (j.items[0]||{}).tool_restamp + "/" + (j.items[0]||{}).tracked_by')"
  [[ "$verdict" == "measurement/measurement/true/null" ]] \
    || log_fail "TEST-1374 arm 3: a proven allocator rename must stay class/bucket measurement, tool_restamp true and untracked, got \"$verdict\""

  run_fu list --ledger "$ledA" --status all
  [[ "$EC" == 0 ]] || log_fail "TEST-1374 arm 3: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-" <<<"$OUT" \
    && log_fail "TEST-1374 arm 3: a proven allocator restamp must co-create NO item; the real reader found: $OUT"

  log_pass "TEST-1374 restamp measures its own cause: a genuine allocator rename (self-reference and intake alike) keeps the measurement lane and owes nothing, while a contract-shaped edit and an allocator rename mixed with one both take the contract lane with an open owner obligation"
}

# --- TEST-1375 (Spec-AC-19) — the migrated cohort is the PROVEN one ----------
#
# The 2026-10-02T08:10 migration moved 25 records into `measurement` on the
# strength of the STRUCTURAL shape alone (both frozen-sha anchors plus a
# byte-equal RESTAMP_WHAT). TEST-1374's own fix is the evidence that the shape
# proves nothing: the OLD `cmdRestamp` wrote exactly that shape after ANY
# post-freeze edit, because it never verified its cause. Re-verifying all 26
# restamp-shaped records against the object store — reversing the allocator's
# DRAFT-to-numbered substitution over the content whose contract hash equals
# each record's `to_frozen_sha256` and comparing against its
# `from_frozen_sha256`, the same reversal `verifyAllocatorCause` implements —
# reproduced the cause for 13 and could NOT reproduce it for the 13 pinned
# below. Unprovable goes back to the contract lane: not because the drift is
# known to be a contract change, but because nothing on the record or in the
# bytes discharges the obligation.
#
# The pin is on the (ts, ref_id) PAIRS, never on a count, and it reads only
# the ledger: a shallow CI checkout has no history to re-derive the proof
# from, so an arm that re-ran the git walk here would be red on CI and green
# locally for a reason that has nothing to do with the records.
T1375_UNPROVABLE_PAIRS='2026-09-24T11:07:42Z|spec-update-installs-ref-guard-undisclosed
2026-09-26T10:54:50Z|gate-checks-declared-mutation
2026-09-26T09:27:13Z|routing-tables-have-an-owner-and-a-seam
2026-09-28T04:19:38Z|routing-tables-have-an-owner-and-a-seam
2026-09-28T19:10:46Z|feedback-triage-missing-output-dir
2026-09-28T19:16:10Z|feedback-triage-missing-output-dir
2026-09-28T19:25:57Z|prompts-invoke-wsl-bash-on-windows
2026-09-28T19:26:42Z|prompts-invoke-wsl-bash-on-windows
2026-09-29T00:02:07Z|mutation-clone-fidelity-windows-eol
2026-09-29T00:14:04Z|mutation-clone-fidelity-windows-eol
2026-09-29T16:40:28Z|antigravity-cli-skill-paths
2026-09-29T22:07:33Z|mutation-clone-windows-run-chain
2026-10-01T08:06:01Z|spec-shipped-guards-have-no-downstream-trigger'

test_1375_migrated_cohort_is_the_proven_one() {
  log_info "Test: the measurement lane holds only the restamp records whose allocator cause the bytes reproduce; the 13 that could not be proven are back in the contract lane (TEST-1375)..."
  local bad pairs

  # --- ARM 1: the LIVE ledger -----------------------------------------------
  pairs="$(printf '%s' "$T1375_UNPROVABLE_PAIRS" | tr '\n' ' ')"
  run_sa list --ledger "$LIVE_LEDGER" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1375 arm 1: \`list --json\` over the live ledger must exit 0, got $EC (stderr: $ERR)"
  bad="$(printf '%s' "$OUT" | node -e '
    let raw = "";
    process.stdin.on("data", (d) => { raw += d; });
    process.stdin.on("end", () => {
      const j = JSON.parse(raw);
      const by = new Map();
      for (const it of (j.items || [])) by.set(it.ts + "|" + it.ref_id, it);
      const bad = [];
      for (const want of process.argv.slice(1)) {
        const it = by.get(want);
        if (!it) { bad.push(want + " -> MISSING from the ledger"); continue; }
        if (it.amendment_class !== "contract" || it.bucket !== "unsigned-tracked") {
          bad.push(want + " -> " + it.amendment_class + "/" + it.bucket);
        }
      }
      console.log(bad.join("; "));
    });
  ' $pairs)"
  if [[ -n "$bad" ]]; then
    log_fail "TEST-1375 arm 1: a restamp-shaped record whose allocator cause the bytes do NOT reproduce is still discharged into the obligation-free measurement lane. The structural shape (both anchors + a byte-equal RESTAMP_WHAT) was written by the OLD cmdRestamp after ANY post-freeze edit, so it is not probative; each record below needs a later-dated \`classify --class contract --signoff none\` overlay putting it back where the obligation is real. Offending: $bad"
  fi
  log_info "TEST-1375 arm 1: all 13 unprovable restamp records resolve to contract/unsigned-tracked"

  # --- ARM 2: the rule itself, on a fixture, with the REAL cause oracle ------
  # Two frozen specs drift: one by the allocator's own DRAFT-to-numbered
  # rewrite, one by an edit to what the spec PROMISES. Both then get a LEGACY
  # restamp-shaped ledger record — the exact shape the old writer emitted for
  # both. The structural selector cannot tell them apart; the corrected
  # migration asks the same reversal `restamp` asks, and moves only the one
  # the bytes prove.
  local specP specU ledL frozenP frozenU toP toU structural verdict
  specP="$(mk_linked_freezable_spec t1375-specs/p.md spec-t1375-proven t1375-intake-p)"
  freeze_spec "$specP" || log_fail "TEST-1375 arm 2 setup: real spec-freeze.mjs refused the proven fixture"
  specU="$(mk_linked_freezable_spec t1375-specs/u.md spec-t1375-unproven t1375-intake-u)"
  freeze_spec "$specU" || log_fail "TEST-1375 arm 2 setup: real spec-freeze.mjs refused the unproven fixture"
  frozenP="$(frozen_sha256_of "$specP")"
  frozenU="$(frozen_sha256_of "$specU")"

  sed -i.bak -e 's/SPEC-DRAFT-spec-t1375-proven/SPEC-0320-spec-t1375-proven/g' \
             -e 's/CHANGE-DRAFT-t1375-intake-p/CHANGE-0320-t1375-intake-p/g' "$specP"
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$specU"
  toP="$(contract_hash_of "$specP")"
  toU="$(contract_hash_of "$specU")"
  [[ "$toP" != "$frozenP" && "$toU" != "$frozenU" ]] \
    || log_fail "TEST-1375 arm 2 setup: both fixture specs must have drifted off their anchors"

  ledL="$(mk_ledger t1375legacy)"
  node -e '
    const fs = require("fs");
    const [led, what, fp, tp, fu, tu] = process.argv.slice(1);
    const base = { v: 1, actor: "orchestrator", type: "spec_amendment", why: "legacy restamp record", owner_signoff: false };
    const rows = [
      { ...base, ts: "2026-09-01T00:00:00Z", ref_id: "t1375-p", spec_id: "spec-t1375-proven",
        spec: "docs/specs/SPEC-0320-spec-t1375-proven.md", what, from_frozen_sha256: fp, to_frozen_sha256: tp,
        tracked_by: "fu-amend-t1375-p" },
      { v: 1, ts: "2026-09-01T00:00:01Z", actor: "a", type: "follow_up", id: "fu-amend-t1375-p", ref_id: "t1375-p",
        severity: "P2", finding: "owner sign-off owed on spec-t1375-proven", decision: "filed unsigned", source: "fixture" },
      { ...base, ts: "2026-09-02T00:00:00Z", ref_id: "t1375-u", spec_id: "spec-t1375-unproven",
        spec: "docs/specs/SPEC-DRAFT-spec-t1375-unproven.md", what, from_frozen_sha256: fu, to_frozen_sha256: tu,
        tracked_by: "fu-amend-t1375-u" },
      { v: 1, ts: "2026-09-02T00:00:01Z", actor: "a", type: "follow_up", id: "fu-amend-t1375-u", ref_id: "t1375-u",
        severity: "P2", finding: "owner sign-off owed on spec-t1375-unproven", decision: "filed unsigned", source: "fixture" },
    ];
    fs.appendFileSync(led, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
  ' "$ledL" "$T1369_RESTAMP_WHAT" "$frozenP" "$toP" "$frozenU" "$toU"

  # NEGATIVE CONTROL: the structural selector the migration used picks BOTH.
  run_sa list --ledger "$ledL" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1375 arm 2: \`list --json\` must exit 0, got $EC (stderr: $ERR)"
  structural="$(json_field "$OUT" 'j.items.filter((it) => it.tool_restamp === true).map((it) => it.ref_id).sort().join(",")')"
  [[ "$structural" == "t1375-p,t1375-u" ]] \
    || log_fail "TEST-1375 arm 2: the structural selector must still match BOTH legacy records — that is the whole defect — got: $structural"

  # THE CORRECTED MIGRATION: the class is decided by the SAME reversal
  # `restamp` runs, read off the real CLI rather than re-implemented here.
  local rts rref rspec probe probe_led klass cause
  while IFS='|' read -r rts rref rspec; do
    [[ -n "$rts" ]] || continue
    probe="$TEST_DIR/t1375-probe-$rref.md"
    cp "$rspec" "$probe"
    probe_led="$(mk_ledger "t1375probe-$rref")"
    run_sa restamp --spec "$probe" --ref "probe-$rref" --ledger "$probe_led"
    [[ "$EC" == 0 ]] || log_fail "TEST-1375 arm 2: the cause probe must exit 0 for $rref, got $EC (stderr: $ERR)"
    klass=contract; cause="NOT reproduced"
    case "$OUT" in *"the allocator is PROVEN to be the cause"*) klass=measurement; cause="reproduced" ;; esac
    run_sa classify --ledger "$ledL" --ts "$rts" --ref "$rref" --signoff none --class "$klass" --origin backfill \
      --why "re-verified restamp cohort: the allocator cause was $cause from the bytes" \
      --source "docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md D3 (corrected: proof of cause, not the structural shape)" </dev/null
    [[ "$EC" == 0 ]] \
      || log_fail "TEST-1375 arm 2: the corrected migration's classify refused $rref as $klass, got $EC (stdout: $OUT) (stderr: $ERR)"
  done <<EOF
2026-09-01T00:00:00Z|t1375-p|$specP
2026-09-02T00:00:00Z|t1375-u|$specU
EOF

  run_sa list --ledger "$ledL" --json
  [[ "$EC" == 0 ]] || log_fail "TEST-1375 arm 2: \`list --json\` must exit 0 after the corrected migration, got $EC (stderr: $ERR)"
  verdict="$(json_field "$OUT" 'j.items.map((it) => it.ref_id + ":" + it.amendment_class + "/" + it.bucket).sort().join(" ")')"
  [[ "$verdict" == "t1375-p:measurement/measurement t1375-u:contract/unsigned-tracked" ]] \
    || log_fail "TEST-1375 arm 2: only the record whose allocator cause the bytes reproduce may take the measurement lane; the other keeps its owner obligation. Got: $verdict"

  run_fu list --ledger "$ledL" --status open
  [[ "$EC" == 0 ]] || log_fail "TEST-1375 arm 2: follow-ups.mjs list must exit 0, got $EC (stderr: $ERR)"
  grep -qF "fu-amend-t1375-u" <<<"$OUT" \
    || log_fail "TEST-1375 arm 2: the unprovable record's owner obligation must still be OPEN; the real reader found: $OUT"

  log_pass "TEST-1375 the measurement lane is the PROVEN cohort: 13 live records whose allocator cause the bytes cannot reproduce are back in the contract lane, and on a fixture the structural selector matches both legacy records while the corrected one moves only the provable half"
}

# --- TEST-1376 (Spec-AC-20) — every command this CLI PRINTS can be run ------
#
# Codex P2 on PR #422: the remedy an unverified `restamp` printed used
# `--authority`, which `classify` does not accept, so the advertised command
# exited 2 on an unknown flag. Advice that cannot be followed is the defect
# class this whole scope is about, one level up. Two arms: the specific line
# is RUN, and every printed invocation in the file is checked against the
# CLI's OWN flag table so a second one cannot regress silently.
test_1376_printed_commands_use_flags_the_cli_accepts() {
  log_info "Test: the remedy an unverified restamp prints actually runs, and every printed spec-amend invocation uses flags FLAG_SPECS declares (TEST-1376)..."
  local spec led line l cmd o e rc

  # --- ARM 1: the printed remedy, executed verbatim -------------------------
  spec="$(mk_linked_freezable_spec t1376-specs/a.md spec-t1376-fixture t1376-intake)"
  freeze_spec "$spec" || log_fail "TEST-1376 setup: real spec-freeze.mjs refused the fixture"
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$spec"
  led="$(mk_ledger t1376)"

  run_sa restamp --spec "$spec" --ref t1376-ride --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-1376: restamp must exit 0 on the unverified fixture, got $EC (stderr: $ERR)"
  grep -qF 'the allocator is NOT verified as the cause' <<<"$OUT" \
    || log_fail "TEST-1376 setup: the fixture must produce an UNVERIFIED restamp; stdout: $OUT"

  line=""
  while IFS= read -r l; do
    case "$l" in *"spec-amend.mjs classify "*) line="$l" ;; esac
  done <<<"$OUT"
  [[ -n "$line" ]] \
    || log_fail "TEST-1376: an unverified restamp must PRINT a classify remedy line; stdout: $OUT"

  grep -qF -- '--authority' <<<"$line" \
    && log_fail "TEST-1376: the printed remedy names \`--authority\`, which \`classify\` does not accept (\`add\` does) — running it exits 2 on an unknown flag. Printed: $line"

  cmd="node \"\$SA\" classify ${line#*spec-amend.mjs classify }"
  o="$TEST_DIR/.t1376.out"; e="$TEST_DIR/.t1376.err"; rc=0
  eval "$cmd" > "$o" 2> "$e" || rc=$?
  [[ "$rc" != 2 ]] \
    || log_fail "TEST-1376: the remedy the tool printed exits 2 — advice that cannot be followed.
COMMAND: $cmd
STDERR:  $(cat "$e")"
  [[ "$rc" == 0 ]] \
    || log_fail "TEST-1376: the remedy the tool printed exited $rc.
COMMAND: $cmd
STDERR:  $(cat "$e")"
  grep -qF 'owner_signoff=true' "$o" \
    || log_fail "TEST-1376: running the printed remedy must actually sign the record off; stdout: $(cat "$o")"

  # --- ARM 2: no printed invocation may name a flag the CLI rejects ---------
  # Read off FLAG_SPECS itself, so the check and the parser can never drift.
  local offenders
  offenders="$(node --input-type=module -e "
    import fs from 'node:fs';
    const mod = await import('$SA');
    const specs = mod.FLAG_SPECS;
    const src = fs.readFileSync('$SA', 'utf8');
    const GLOBAL = new Set(['--json', '--strict', '--list-degraded', '--help']);
    const bad = [];
    const lines = src.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const m = lines[i].match(/spec-amend\.mjs (add|classify|list|restamp)\b/);
      if (!m) continue;
      const sub = m[1];
      const allowed = new Set([...(specs[sub] || []), ...GLOBAL]);
      for (const f of lines[i].slice(m.index).match(/--[a-z][a-z-]*/g) || []) {
        if (!allowed.has(f)) bad.push((i + 1) + ': ' + sub + ' ' + f);
      }
    }
    process.stdout.write(bad.join('; '));
  ")"
  [[ -z "$offenders" ]] \
    || log_fail "TEST-1376 arm 2: a command this script PRINTS names a flag its own FLAG_SPECS table does not accept for that subcommand, so the advertised command exits 2: $offenders"

  log_pass "TEST-1376 the printed remedy runs to a signed record, and every printed spec-amend invocation in the script uses only flags FLAG_SPECS accepts for that subcommand"
}

# --- TEST-1377 (Spec-AC-21) — the workflow prose matches the writer ---------
#
# Codex P2 on PR #422: AUTONOMOUS_LOOP section 6a still said `restamp` is
# "reachable only from allocator anchor drift" and "hardcodes measurement".
# Since TEST-1374's fix an UNVERIFIED restamp deliberately writes a contract
# record and creates an obligation, so the prose described a writer that no
# longer exists — and it described exactly the assumption the migration was
# wrong to trust.
test_1377_canon_states_the_measured_cause_rule() {
  log_info "Test: AUTONOMOUS_LOOP section 6a states restamp's MEASURED-cause rule rather than the retired hardcode claim (TEST-1377)..."
  [[ -f "$CANON" ]] || log_fail "TEST-1377: $CANON does not exist"

  if command grep -qF 'so it hardcodes' "$CANON"; then
    log_fail "TEST-1377: .aai/system/AUTONOMOUS_LOOP.md still says \`restamp\` hardcodes its class — since the Spec-AC-18 fix an unverified restamp writes a contract record and co-creates an obligation"
  fi
  if command grep -qF 'reachable only from allocator anchor drift' "$CANON"; then
    log_fail "TEST-1377: .aai/system/AUTONOMOUS_LOOP.md still claims \`restamp\` is reachable only from allocator anchor drift — it is reachable from ANY post-freeze drift, which is why the cause is now measured"
  fi
  command grep -qF 'takes the measurement lane ONLY when' "$CANON" \
    || log_fail "TEST-1377: the canon must state that restamp takes the measurement lane ONLY when the reversal reproduces the stored anchor"
  command grep -qF 'is disclosed as a contract record' "$CANON" \
    || log_fail "TEST-1377: the canon must state that any other post-freeze drift is disclosed as a contract record"
  command grep -qF 'The light lane is never reachable by the shape of a record alone.' "$CANON" \
    || log_fail "TEST-1377: the canon must say the light lane is never reachable by a record's shape alone — the migration's own mistake"

  log_pass "TEST-1377 the canon states the measured-cause rule, the contract-lane consequence of an unverified restamp, and that a record's shape alone never buys the light lane"
}

# --- TEST-1378 (Spec-AC-22) — printed commands survive their own values -----
#
# Codex P2 on PR #422, second finding: the classify remedy an unverified
# `restamp` prints interpolated `ts`, `ref` and the ledger path RAW, so a
# `--ref 'ref with space'` or a ledger named `decision ledger.jsonl` produced
# a line that split into stray tokens and exited 2. TEST-1376 proved the FLAGS
# are ones the CLI accepts; this proves the VALUES survive the trip through a
# shell. Two arms, the same shape: the specific line is RUN with hostile
# values, and the source is scanned so the next printed interpolation cannot
# regress silently.
test_1378_printed_commands_quote_their_values() {
  log_info "Test: every value a printed command interpolates is shell-quoted, so the advertised line runs verbatim whatever the ref or the ledger path holds (TEST-1378)..."
  local spec led line l cmd o e rc offenders

  # --- ARM 1: the printed remedy, executed verbatim, hostile values ---------
  # Both of Codex's reproduction inputs at once: whitespace in --ref AND
  # whitespace in the ledger path.
  spec="$(mk_linked_freezable_spec t1378-specs/a.md spec-t1378-fixture t1378-intake)"
  freeze_spec "$spec" || log_fail "TEST-1378 setup: real spec-freeze.mjs refused the fixture"
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$spec"
  led="$(mk_ledger 't1378 decision ledger')"

  run_sa restamp --spec "$spec" --ref 'ref with space' --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-1378: restamp must exit 0 on the unverified fixture, got $EC (stderr: $ERR)"
  grep -qF 'the allocator is NOT verified as the cause' <<<"$OUT" \
    || log_fail "TEST-1378 setup: the fixture must produce an UNVERIFIED restamp; stdout: $OUT"

  line=""
  while IFS= read -r l; do
    case "$l" in *"spec-amend.mjs classify "*) line="$l" ;; esac
  done <<<"$OUT"
  [[ -n "$line" ]] \
    || log_fail "TEST-1378: an unverified restamp must PRINT a classify remedy line; stdout: $OUT"

  cmd="node \"\$SA\" classify ${line#*spec-amend.mjs classify }"
  o="$TEST_DIR/.t1378.out"; e="$TEST_DIR/.t1378.err"; rc=0
  eval "$cmd" > "$o" 2> "$e" || rc=$?
  [[ "$rc" == 0 ]] \
    || log_fail "TEST-1378 arm 1: the remedy the tool printed exited $rc once its values carried whitespace — an unquoted interpolation splits into stray tokens, so the advice cannot be followed.
COMMAND: $cmd
STDERR:  $(cat "$e")"
  grep -qF 'owner_signoff=true' "$o" \
    || log_fail "TEST-1378 arm 1: running the printed remedy must actually sign the record off; stdout: $(cat "$o")"

  # --- ARM 2: no printed command may interpolate an unquoted value ----------
  # The guard is a PROPERTY of the source, not a list of known-bad lines: any
  # `${...}` inside a line that prints a `node .aai/scripts/...` command must
  # go through the one quoting helper. Reported by file line so a new offender
  # names itself.
  offenders="$(node --input-type=module -e "
    import fs from 'node:fs';
    const src = fs.readFileSync('$SA', 'utf8');
    const bad = [];
    const lines = src.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const at = lines[i].search(/node \.aai\/scripts\//);
      if (at < 0) continue;
      // From the command token onward ONLY: an interpolation in the PROSE
      // ahead of it is not part of the command and nothing ever runs it.
      // Same slice discipline as TEST-1376 arm 2.
      for (const m of lines[i].slice(at).matchAll(/\\\$\{([^}]*)\}/g)) {
        const inner = m[1].trim();
        if (!inner.startsWith('shq(')) bad.push((i + 1) + ': \${' + inner + '}');
      }
    }
    process.stdout.write(bad.join('; '));
  ")"
  [[ -z "$offenders" ]] \
    || log_fail "TEST-1378 arm 2: a command this script PRINTS interpolates a value without shell quoting, so a ref or path holding whitespace or a shell metacharacter produces a line that cannot be run: $offenders"

  log_pass "TEST-1378 the printed remedy runs verbatim with whitespace in both its ref and its ledger path, and every interpolation inside a printed command goes through the quoting helper"
}

# --- TEST-1379 (Spec-AC-23) — the Test Plan summary is re-derived ----------
#
# Copilot on PR #422, twice: the sentence under this spec's Test Plan claims
# "counted from the table, not asserted" and was, both times, asserted. It
# was written at one round and rotted at the next the moment rows were added
# — first an undercount of the multi-row ACs, then "18 ACs, 21 rows" while
# the tables held 21 and 24. A figure nothing recomputes is exactly the
# defect class this whole scope exists to close, pointed at the spec's own
# prose: this arm parses BOTH tables out of the live spec and fails when the
# sentence disagrees with them, so the next row addition turns the suite red
# instead of quietly making the spec lie.
test_1379_test_plan_summary_is_recomputed_from_the_tables() {
  log_info "Test: the Test Plan summary sentence's figures are re-derived from this spec's own AC table and Test Plan rather than asserted (TEST-1379)..."
  local spec f verdict

  # Globbed on the slug, never pinned to the number: the allocator renames
  # SPEC-DRAFT-<slug> to SPEC-nnnn-<slug> at merge, and a pinned number is
  # the same stale-literal defect one directory over.
  spec=""
  for f in "$PROJECT_ROOT"/docs/specs/SPEC-*-spec-amendment-signature-asks-the-owner-too-often.md; do
    [[ -f "$f" ]] && spec="$f"
  done
  [[ -n "$spec" ]] \
    || log_fail "TEST-1379: no docs/specs/SPEC-*-spec-amendment-signature-asks-the-owner-too-often.md found"

  verdict="$(node --input-type=module -e "
    import fs from 'node:fs';
    const src = fs.readFileSync('$spec', 'utf8');

    // --- read the AC table ------------------------------------------------
    const acIds = [];
    for (const line of src.split('\n')) {
      const m = line.match(/^\|\s*(Spec-AC-\d{2})\s*\|/);
      if (m) acIds.push(m[1]);
    }

    // --- read the Test Plan, expanding Spec-AC-NN..MM ranges --------------
    const rows = [];
    for (const line of src.split('\n')) {
      const m = line.match(/^\|\s*(TEST-\d+)\s*\|([^|]*)\|/);
      if (!m) continue;
      const ids = [];
      for (const tok of m[2].match(/Spec-AC-\d{2}(?:\.\.\d{2})?/g) || []) {
        const r = tok.match(/^Spec-AC-(\d{2})\.\.(\d{2})\$/);
        if (r) {
          for (let n = Number(r[1]); n <= Number(r[2]); n += 1) ids.push('Spec-AC-' + String(n).padStart(2, '0'));
        } else ids.push(tok);
      }
      rows.push({ testId: m[1], ids });
    }

    const perAc = new Map();
    for (const row of rows) for (const id of row.ids) perAc.set(id, (perAc.get(id) || 0) + 1);
    const uncovered = acIds.filter((id) => !perAc.has(id));
    const multi = acIds.filter((id) => (perAc.get(id) || 0) > 1);
    const measured = { acs: acIds.length, rows: rows.length, multi, uncovered };

    // --- read the claim ---------------------------------------------------
    const SENT = /Every Spec-AC has at least one row\.\s*(.+?)\s*carr(?:y|ies) two\s*\((\d+) ACs, (\d+) rows; counted from the table, not asserted\)\./;
    const s = src.match(SENT);
    if (!s) {
      process.stdout.write('the Test Plan summary sentence is missing or no longer matches the grammar this guard reads: \"Every Spec-AC has at least one row. <ids> carry two (<n> ACs, <m> rows; counted from the table, not asserted).\" Measured now: ' + JSON.stringify(measured));
      process.exit(0);
    }
    const claimed = {
      acs: Number(s[2]),
      rows: Number(s[3]),
      multi: s[1].split(/,\s*|\s+and\s+/).map((t) => t.trim()).filter(Boolean),
    };

    const diffs = [];
    if (uncovered.length) diffs.push('the sentence says every Spec-AC has at least one row, but ' + uncovered.join(', ') + ' has none');
    if (claimed.acs !== measured.acs) diffs.push('AC count: sentence says ' + claimed.acs + ', the AC table holds ' + measured.acs);
    if (claimed.rows !== measured.rows) diffs.push('Test Plan row count: sentence says ' + claimed.rows + ', the Test Plan holds ' + measured.rows);
    if (claimed.multi.join(',') !== measured.multi.join(',')) diffs.push('the ACs carrying two rows: sentence names ' + (claimed.multi.join(', ') || '(none)') + ', the tables show ' + (measured.multi.join(', ') || '(none)'));
    process.stdout.write(diffs.join(' | '));
  ")"

  [[ -z "$verdict" ]] \
    || log_fail "TEST-1379: the Test Plan summary sentence disagrees with the tables it claims to be counted from — $verdict"

  log_pass "TEST-1379 the Test Plan summary sentence's AC count, row count and multi-row AC list all re-derive from this spec's own two tables"
}

# --- TEST-1380 (Spec-AC-24) — the signing refusal reads the PROJECTED class --
#
# Code review round 5, Codex P2 on PR #422: round 1 converted
# `owesOwnerObligation` to read the class off `foldAmendments` and left its
# sibling `refuseMeasurementSignedByOwner` reading the caller's `--class`.
# OMIT the flag and the predicate receives `null`, so
# `classify --signoff owner` over a record whose OWN class is `measurement`
# was allowed and folded to `amendment_class: measurement` with
# `bucket: signed` — the light lane minting the authority it exists to stop
# asking for, reached by leaving a flag off.
#
# The arm is the WHOLE input space rather than the one reproduced cell: every
# (record class x --class x --signoff) combination, twelve in all, each on its
# own fixture ledger, each checked against the INVARIANT itself. A predicate
# that reads the wrong input cannot be half-fixed past this.
count_ledger_records() {
  node -e '
    const fs=require("fs");
    const raw=fs.readFileSync(process.argv[1],"utf8");
    let n=0;
    for (const line of raw.split(/\r?\n/)) {
      const t=line.trim();
      if (t==="" || t.startsWith("#")) continue;
      try { JSON.parse(t); n+=1; } catch { /* malformed lines are not records */ }
    }
    process.stdout.write(String(n));
  ' "$1"
}

test_1380_signing_refusal_reads_the_projected_class() {
  log_info "Test: no combination of a record's own class, --class and --signoff can produce a SIGNED record the fold resolves to measurement, and --signoff owner with --class OMITTED over a measurement record exits 2 and appends nothing (TEST-1380)..."
  local spec led ts rec_class flag signoff cell expected classify_ec classify_err before after offenders bucket

  spec="$(mk_spec "SPEC-DRAFT-t1380.md" "spec-t1380-fixture")"

  for rec_class in contract measurement; do
    for flag in none contract measurement; do
      for signoff in none owner; do
        cell="record_class=$rec_class --class=$flag --signoff=$signoff"
        led="$(mk_ledger "t1380-$rec_class-$flag-$signoff")"

        # The record under test is written by the real writer, so its own
        # `amendment_class` is the one a live writer stamps — never hand-built.
        run_sa add --ledger "$led" --spec "$spec" --ref t1380-ride \
          --what "a post-freeze edit" --why "disclosed on the ledger" \
          --class "$rec_class" --signoff none
        [[ "$EC" == 0 ]] \
          || log_fail "TEST-1380 setup ($cell): \`add --class $rec_class\` exited $EC; stderr: $ERR"
        ts="$(json_field "$(last_amendment_for "$led" t1380-ride)" 'j.ts')"
        before="$(count_ledger_records "$led")"

        if [[ "$flag" == none ]]; then
          run_sa classify --ledger "$led" --ts "$ts" --ref t1380-ride \
            --signoff "$signoff" --why "what the drift was" --source "where it was decided"
        else
          run_sa classify --ledger "$led" --ts "$ts" --ref t1380-ride --class "$flag" \
            --signoff "$signoff" --why "what the drift was" --source "where it was decided"
        fi
        classify_ec="$EC"
        classify_err="$ERR"

        # The expectation is DERIVED from the three inputs, never a table of
        # remembered answers: a signature over a measurement projection is
        # refused however the class got there, a `--class measurement
        # --signoff owner` pair is refused on the flags alone, and a `--class`
        # the fold would not adopt is refused as before.
        expected=0
        if [[ "$signoff" == owner && "$flag" == measurement ]]; then
          expected=2
        elif [[ "$signoff" == owner && "$rec_class" == measurement ]]; then
          expected=2
        elif [[ "$flag" != none && "$flag" != "$rec_class" ]]; then
          expected=2
        fi
        [[ "$classify_ec" == "$expected" ]] \
          || log_fail "TEST-1380 ($cell): expected exit $expected, got $classify_ec.
STDOUT: $OUT
STDERR: $classify_err"

        if [[ "$expected" == 2 ]]; then
          after="$(count_ledger_records "$led")"
          [[ "$after" == "$before" ]] \
            || log_fail "TEST-1380 ($cell): a refused classify appended to the ledger — $before record(s) before, $after after"
          grep -qF "measurement" <<<"$classify_err" \
            || log_fail "TEST-1380 ($cell): the refusal must name the class it refuses; stderr was: $classify_err"
        fi

        # THE INVARIANT, checked on every cell whatever the exit code was:
        # the ledger the run leaves behind never holds a record the fold
        # resolves to BOTH `signed` and `measurement`.
        run_sa list --ledger "$led" --status all --json
        [[ "$EC" == 0 ]] \
          || log_fail "TEST-1380 ($cell): \`list --json\` exited $EC; stderr: $ERR"
        offenders="$(json_field "$OUT" '(j.items||[]).filter(i=>i.bucket==="signed"&&i.amendment_class==="measurement").map(i=>i.ts+" "+i.ref_id).join(", ")')"
        [[ -z "$offenders" ]] \
          || log_fail "TEST-1380 ($cell): the fold resolved a SIGNED record whose amendment_class is measurement — the light lane manufactured an owner signature it can never carry: $offenders"

        # ...and the drain route the measurement lane was never meant to close:
        # a CONTRACT record is still signable by the same flagless call, which
        # is the exact line an unverified `restamp` prints as its own remedy.
        if [[ "$rec_class" == contract && "$signoff" == owner && "$flag" != measurement ]]; then
          bucket="$(json_field "$OUT" '((j.items||[])[0]||{}).bucket')"
          [[ "$bucket" == "signed" ]] \
            || log_fail "TEST-1380 ($cell): a contract record must still reach bucket signed through \`classify --signoff owner\`, got \"$bucket\" — refusing the contradiction must not refuse the signature"
        fi
      done
    done
  done

  log_pass "TEST-1380 all twelve (record class x --class x --signoff) combinations refuse exactly the contradiction, append nothing when they refuse, never fold a signed record to measurement, and leave the contract drain route open"
}

# --- TEST-1381 (Spec-AC-25) — the printed remedy runs in BOTH shells --------
#
# Code review round 5, Codex P2 on PR #422, second finding: `shq` wrapped every
# interpolated value in POSIX single quotes, which PowerShell cannot parse —
# `'O'\''Brien'` is "The string is missing the terminator: '." — while this
# repo supports Windows (a full `.ps1` layer, a Windows PowerShell 5.1 CI leg
# and a WSL1 leg, and AGENTS.md's Canonical test invocation names both forms).
# TEST-1378 round-tripped through bash only, so it could not see it.
#
# Three arms. Arm 1 asserts the BYTES — the one property that holds on every
# host, so this test still proves something where no PowerShell engine exists.
# Arm 2 runs the printed line in bash. Arm 3 runs the SAME line in pwsh where
# one resolves and says plainly, in the pass line, when it did not: a skip here
# would be exit 42, which VOIDS the suite, and a silent pass would be worse
# than no test at all.
resolve_pwsh() {
  local engine
  for engine in pwsh powershell; do
    if command -v "$engine" >/dev/null 2>&1; then printf '%s' "$engine"; return 0; fi
  done
  printf '%s' ""
}

test_1381_printed_remedy_runs_in_posix_and_powershell() {
  log_info "Test: the remedy an unverified restamp prints is quoted so it runs verbatim in BOTH POSIX sh and PowerShell, and a value no single literal can express in both prints the two labelled forms instead (TEST-1381)..."
  local spec led engine lines line l posix_line ps_line cmd o e rc had_pwsh

  engine="$(resolve_pwsh)"
  had_pwsh="no"
  if [[ -n "$engine" ]]; then had_pwsh="yes"; fi

  # --- ARM 1+2: a quote-bearing --ref, the universal rendering --------------
  spec="$(mk_linked_freezable_spec t1381-specs/a.md spec-t1381-fixture t1381-intake)"
  freeze_spec "$spec" || log_fail "TEST-1381 setup: real spec-freeze.mjs refused the fixture"
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$spec"
  led="$(mk_ledger 't1381 decision ledger')"

  run_sa restamp --spec "$spec" --ref "o'brien ref" --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-1381: restamp must exit 0 on the unverified fixture, got $EC (stderr: $ERR)"
  grep -qF 'the allocator is NOT verified as the cause' <<<"$OUT" \
    || log_fail "TEST-1381 setup: the fixture must produce an UNVERIFIED restamp; stdout: $OUT"

  lines=0; line=""
  while IFS= read -r l; do
    case "$l" in *"spec-amend.mjs classify "*) lines=$((lines + 1)); line="$l" ;; esac
  done <<<"$OUT"
  [[ "$lines" == 1 ]] \
    || log_fail "TEST-1381 arm 1: a --ref holding only a quote has ONE literal both shells read the same way, so exactly one remedy line is owed; got $lines. stdout: $OUT"
  grep -qF '"o'"'"'brien ref"' <<<"$line" \
    || log_fail "TEST-1381 arm 1: the quote-bearing --ref must be rendered in the one form both shells read identically (double quotes, where a single quote is literal in each), not a POSIX-only escape. Printed: $line"
  grep -qF "'\\''" <<<"$line" \
    && log_fail "TEST-1381 arm 1: the printed line carries the POSIX close-escape-reopen form, which PowerShell refuses with \"The string is missing the terminator\". Printed: $line"

  cmd="node \"\$SA\" classify ${line#*spec-amend.mjs classify }"
  o="$TEST_DIR/.t1381.out"; e="$TEST_DIR/.t1381.err"; rc=0
  eval "$cmd" > "$o" 2> "$e" || rc=$?
  [[ "$rc" == 0 ]] \
    || log_fail "TEST-1381 arm 2: the printed remedy exited $rc under bash.
COMMAND: $cmd
STDERR:  $(cat "$e")"
  grep -qF 'owner_signoff=true' "$o" \
    || log_fail "TEST-1381 arm 2: running the printed remedy under bash must sign the record off; stdout: $(cat "$o")"

  # --- ARM 3: the SAME line, run by a real PowerShell -----------------------
  if [[ -n "$engine" ]]; then
    cmd="node '$SA' classify ${line#*spec-amend.mjs classify }"
    rc=0
    "$engine" -NoProfile -Command "$cmd" > "$o" 2> "$e" || rc=$?
    [[ "$rc" == 0 ]] \
      || log_fail "TEST-1381 arm 3: the printed remedy exited $rc under $engine — the advertised line is not runnable on the Windows path this repo supports.
COMMAND: $cmd
STDERR:  $(cat "$e")"
    grep -qF 'owner_signoff=true' "$o" \
      || log_fail "TEST-1381 arm 3: running the printed remedy under $engine must sign the record off; stdout: $(cat "$o") stderr: $(cat "$e")"
  else
    log_info "TEST-1381 arm 3: no PowerShell engine (pwsh or powershell) on PATH — the printed line was NOT executed by a real PowerShell on this host; arms 1, 2 and 4 still ran and arm 1's byte assertion is the mechanism arm 3 would exercise"
  fi

  # --- ARM 4: a value no single literal covers prints BOTH forms ------------
  # A `--ref` holding a quote AND a `$`: double quotes would expand the `$` in
  # both shells and single quotes diverge on the quote, so no common literal
  # exists. The honest answer is the labelled pair, never one line that is
  # right in one shell and silently misread in the other.
  spec="$(mk_linked_freezable_spec t1381b-specs/a.md spec-t1381b-fixture t1381b-intake)"
  freeze_spec "$spec" || log_fail "TEST-1381 arm 4 setup: real spec-freeze.mjs refused the fixture"
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$spec"
  led="$(mk_ledger 't1381b decision ledger')"

  run_sa restamp --spec "$spec" --ref 'o'"'"'brien $ref' --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-1381 arm 4: restamp must exit 0, got $EC (stderr: $ERR)"

  posix_line=""; ps_line=""
  while IFS= read -r l; do
    case "$l" in
      *"POSIX sh: node .aai/scripts/spec-amend.mjs classify "*) posix_line="$l" ;;
      *"PowerShell: node .aai/scripts/spec-amend.mjs classify "*) ps_line="$l" ;;
    esac
  done <<<"$OUT"
  [[ -n "$posix_line" && -n "$ps_line" ]] \
    || log_fail "TEST-1381 arm 4: a value with no literal both shells read the same way owes BOTH labelled forms, so neither host is handed a line the other's quoting silently misreads. stdout: $OUT"

  cmd="node \"\$SA\" classify ${posix_line#*spec-amend.mjs classify }"
  rc=0
  eval "$cmd" > "$o" 2> "$e" || rc=$?
  [[ "$rc" == 0 ]] \
    || log_fail "TEST-1381 arm 4: the POSIX form exited $rc under bash.
COMMAND: $cmd
STDERR:  $(cat "$e")"
  grep -qF 'owner_signoff=true' "$o" \
    || log_fail "TEST-1381 arm 4: the POSIX form must sign the record off under bash; stdout: $(cat "$o")"

  if [[ -n "$engine" ]]; then
    cmd="node '$SA' classify ${ps_line#*spec-amend.mjs classify }"
    rc=0
    "$engine" -NoProfile -Command "$cmd" > "$o" 2> "$e" || rc=$?
    [[ "$rc" == 0 ]] \
      || log_fail "TEST-1381 arm 4: the PowerShell form exited $rc under $engine.
COMMAND: $cmd
STDERR:  $(cat "$e")"
    grep -qF 'owner_signoff=true' "$o" \
      || log_fail "TEST-1381 arm 4: the PowerShell form must sign the record off under $engine; stdout: $(cat "$o") stderr: $(cat "$e")"
  fi

  log_pass "TEST-1381 the printed remedy is rendered in the one literal POSIX sh and PowerShell read identically and runs verbatim in both (live PowerShell run: $had_pwsh), and a value no common literal covers prints both labelled forms, each runnable in its own shell"
}

# --- classify-same-ts-pair (SPEC spec-classify-same-ts-pair, TEST-001..003) ---
# One (ts, ref_id) pair can hold several spec_amendment records; `classify`
# addresses ONE of them by a content key (--record). Fixtures are scratch
# ledgers; the shipping ledger is never written.

# rec_key <json line> -> the 12-hex content key (sha256 of the re-serialised
# parsed record), computed here independently of the engine.
rec_key() {
  node -e 'const c=require("crypto");process.stdout.write(c.createHash("sha256").update(JSON.stringify(JSON.parse(process.argv[1]))).digest("hex").slice(0,12))' "$1"
}

# pair_rec <ts> <ref> <class> <what> [tracked_by] -> one spec_amendment line.
pair_rec() {
  local tb=""
  if [[ -n "${5:-}" ]]; then tb=",\"tracked_by\":\"$5\""; fi
  printf '{"v":1,"ts":"%s","actor":"orchestrator","type":"spec_amendment","ref_id":"%s","spec":"docs/specs/SPEC-DRAFT-spec-pair.md","spec_id":"spec-pair","owner_signoff":false,"amendment_class":"%s","what":"%s","why":"fixture"%s}' \
    "$1" "$2" "$3" "$4" "$tb"
}

# json_rows <ledger> <ts> <ref> <class> -> JSON of the matching list --json rows
# with record_key removed (so a pre-change engine's rows compare equal).
json_rows() {
  node "$SA" list --ledger "$1" --json --status all 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const j=JSON.parse(s);
      const rows=j.items.filter(i=>i.ts===process.argv[1]&&i.ref_id===process.argv[2]&&(process.argv[3]===""||i.amendment_class===process.argv[3]))
        .map(i=>{const c=Object.assign({},i);delete c.record_key;return c;});
      process.stdout.write(JSON.stringify(rows));
    })' "$2" "$3" "${4:-}"
}

ledger_sha() { node -e 'const c=require("crypto");process.stdout.write(c.createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"; }

# mk_mixed_pair <name> -> sets PAIR_LED, PAIR_TS, PAIR_REF, PAIR_CK (contract key), PAIR_MK (measurement key)
mk_mixed_pair() {
  local led c m
  PAIR_TS="2026-10-10T11:35:07Z"; PAIR_REF="pair-ref"
  led="$(mk_ledger "$1")"
  c="$(pair_rec "$PAIR_TS" "$PAIR_REF" contract "contract change" fu-amend-spec-pair)"
  m="$(pair_rec "$PAIR_TS" "$PAIR_REF" measurement "measurement change")"
  {
    printf '%s\n' '{"v":1,"ts":"2026-10-10T11:35:08Z","actor":"orchestrator","type":"follow_up","id":"fu-amend-spec-pair","priority":"P2","what":"owner sign-off owed","why":"fixture"}'
    printf '%s\n' "$c"
    printf '%s\n' "$m"
  } >> "$led"
  PAIR_LED="$led"; PAIR_CK="$(rec_key "$c")"; PAIR_MK="$(rec_key "$m")"
}

test_classify_record_signs_one_of_a_pair() {
  log_info "Test: classify --record signs exactly one record of a same-(ts, ref) pair (TEST-001)..."
  local specs before_m after_m strict_before strict_after lines_before lines_after new_line
  mk_mixed_pair t001
  specs="$TEST_DIR/t001-specs"; mkdir -p "$specs"
  [[ "$PAIR_CK" != "$PAIR_MK" && "${#PAIR_CK}" == 12 ]] || log_fail "TEST-001 setup: the two records must have distinct 12-hex keys (got $PAIR_CK / $PAIR_MK)"

  before_m="$(json_rows "$PAIR_LED" "$PAIR_TS" "$PAIR_REF" measurement)"
  run_sa list --ledger "$PAIR_LED" --strict --specs-dir "$specs"; strict_before="$EC"
  lines_before="$(wc -l < "$PAIR_LED" | tr -d ' ')"

  run_sa classify --ledger "$PAIR_LED" --ts "$PAIR_TS" --ref "$PAIR_REF" --record "$PAIR_CK" --signoff owner --why "owner signed" --source "owner answer"
  [[ "$EC" == 0 ]] || log_fail "TEST-001: classify --record $PAIR_CK must exit 0, got $EC (stderr: $ERR)"

  lines_after="$(wc -l < "$PAIR_LED" | tr -d ' ')"
  [[ "$lines_after" == "$((lines_before + 1))" ]] || log_fail "TEST-001: exactly one overlay line must be appended (before=$lines_before after=$lines_after)"
  new_line="$(tail -n 1 "$PAIR_LED")"
  [[ "$new_line" == *'"classifies_record":"'"$PAIR_CK"'"'* ]] || log_fail "TEST-001 positive control: the overlay must carry classifies_record=$PAIR_CK; got: $new_line"
  [[ "$new_line" != *classifies_ts* && "$new_line" != *classifies_ref* ]] || log_fail "TEST-001: a record-addressed overlay must carry NO classifies_ts / classifies_ref (an older reader would apply it to both records); got: $new_line"

  local rows
  rows="$(node "$SA" list --ledger "$PAIR_LED" --json --status all | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
      const c=j.items.find(i=>i.amendment_class==="contract");
      process.stdout.write(c.bucket+" "+(c.classified_by===null?"null":"set"))})')"
  [[ "$rows" == "signed set" ]] || log_fail "TEST-001: the contract record must fold to bucket signed with classified_by set; got: $rows"

  after_m="$(json_rows "$PAIR_LED" "$PAIR_TS" "$PAIR_REF" measurement)"
  [[ "$before_m" == "$after_m" ]] || log_fail "TEST-001: the measurement sibling's row must be unchanged.
before: $before_m
after:  $after_m"
  run_sa list --ledger "$PAIR_LED" --strict --specs-dir "$specs"; strict_after="$EC"
  [[ "$strict_before" == "$strict_after" ]] || log_fail "TEST-001: list --strict exit must be unchanged (before=$strict_before after=$strict_after)"
  log_pass "TEST-001 classify --record signed exactly the contract record; the measurement sibling and the strict exit are unchanged"
}

test_record_overlay_folds_to_its_record_only() {
  log_info "Test: a hand-written record-addressed overlay folds to its record only (TEST-002)..."
  mk_mixed_pair t002
  local led="$PAIR_LED" before_m after out
  before_m="$(json_rows "$led" "$PAIR_TS" "$PAIR_REF" measurement)"
  printf '%s\n' '{"v":1,"ts":"2026-10-10T14:00:00Z","actor":"hand","type":"spec_amendment_classification","classifies_record":"'"$PAIR_CK"'","owner_signoff":true,"why":"hand written","source":"fixture"}' >> "$led"
  after="$(node "$SA" list --ledger "$led" --json --status all | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
      process.stdout.write(j.items.map(i=>i.amendment_class+":"+i.bucket).sort().join(","))})')"
  [[ "$after" == "contract:signed,measurement:measurement" ]] || log_fail "TEST-002: only the addressed record may fold signed; got: $after"
  [[ "$(json_rows "$led" "$PAIR_TS" "$PAIR_REF" measurement)" == "$before_m" ]] || log_fail "TEST-002: the sibling row must be untouched"

  # An overlay naming a key no record has is counted in a NOTE and applied to nothing.
  printf '%s\n' '{"v":1,"ts":"2026-10-10T14:00:01Z","actor":"hand","type":"spec_amendment_classification","classifies_record":"000000000000","owner_signoff":true,"why":"hand written","source":"fixture"}' >> "$led"
  out="$(node "$SA" list --ledger "$led" --status all)"
  [[ "$out" == *"address a record key with no spec_amendment"* ]] || log_fail "TEST-002: an overlay addressing an unknown record key must be counted in a NOTE; got: $out"
  [[ "$out" != *"carry no usable classifies_ts"* ]] || log_fail "TEST-002: a record-addressed overlay must not be counted as dangling by THIS reader"
  after="$(node "$SA" list --ledger "$led" --json --status all | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
      process.stdout.write(j.items.filter(i=>i.bucket==="signed").length+"/"+j.items.length)})')"
  [[ "$after" == "1/2" ]] || log_fail "TEST-002: the unknown-key overlay must be applied to nothing; signed/total=$after"
  log_pass "TEST-002 a record-addressed overlay folds to its record only; an unknown key is a counted NOTE and applies to nothing"
}

test_classify_refuses_what_it_cannot_tell_apart() {
  log_info "Test: classify refuses what it cannot tell apart, ledger untouched (TEST-003)..."
  mk_mixed_pair t003
  local led="$PAIR_LED" sha n

  # arm 1: shared pair, no --record -> ambiguous, one record= line per candidate
  sha="$(ledger_sha "$led")"
  run_sa classify --ledger "$led" --ts "$PAIR_TS" --ref "$PAIR_REF" --signoff owner --why w --source s
  [[ "$EC" == 2 ]] || log_fail "TEST-003 arm 1: expected exit 2, got $EC"
  [[ "$ERR" == *ambiguous* ]] || log_fail "TEST-003 arm 1: stderr must say ambiguous; got: $ERR"
  n="$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'record=' || true)"
  [[ "$n" -ge 2 && "$ERR" == *"record=$PAIR_CK"* && "$ERR" == *"record=$PAIR_MK"* ]] || log_fail "TEST-003 arm 1: one record= line per candidate expected (both keys); got: $ERR"
  [[ "$sha" == "$(ledger_sha "$led")" ]] || log_fail "TEST-003 arm 1: ledger must be byte-identical"
  # D5: the refusal ends with the runnable --record form; D7: the duplicate-key NOTE names --record.
  [[ "$ERR" == *"spec-amend.mjs classify --ts"*"--record <key> --signoff owner"* ]] || log_fail "TEST-003 arm 1: the refusal must print the runnable --record form (D5); got: $ERR"
  local note
  note="$(node "$SA" list --ledger "$led" --status all)"
  [[ "$note" == *"only \`classify\` without --record refuses such a pair, as ambiguous"* ]] || log_fail "TEST-003 arm 1: the duplicate-key NOTE must say classify refuses only without --record (D7); got: $note"

  # arm 2: two byte-identical records -> --record cannot tell them apart
  local twin ledtw
  ledtw="$(mk_ledger t003-twin)"
  twin="$(pair_rec "$PAIR_TS" "$PAIR_REF" contract "same content" fu-amend-spec-pair)"
  { printf '%s\n' "$twin"; printf '%s\n' "$twin"; } >> "$ledtw"
  sha="$(ledger_sha "$ledtw")"
  run_sa classify --ledger "$ledtw" --ts "$PAIR_TS" --ref "$PAIR_REF" --record "$(rec_key "$twin")" --signoff owner --why w --source s
  [[ "$EC" == 2 && "$ERR" == *indistinguishable* ]] || log_fail "TEST-003 arm 2: expected exit 2 + indistinguishable; got $EC: $ERR"
  [[ "$sha" == "$(ledger_sha "$ledtw")" ]] || log_fail "TEST-003 arm 2: ledger must be byte-identical"

  # arm 3: a well-formed key that is not in the pair -> names the pair's keys
  sha="$(ledger_sha "$led")"
  run_sa classify --ledger "$led" --ts "$PAIR_TS" --ref "$PAIR_REF" --record 000000000000 --signoff owner --why w --source s
  [[ "$EC" == 2 && "$ERR" == *"$PAIR_CK"* && "$ERR" == *"$PAIR_MK"* ]] || log_fail "TEST-003 arm 3: expected exit 2 naming the pair's candidate keys; got $EC: $ERR"
  [[ "$sha" == "$(ledger_sha "$led")" ]] || log_fail "TEST-003 arm 3: ledger must be byte-identical"

  # arm 4: malformed --record -> usage error naming the format
  run_sa classify --ledger "$led" --ts "$PAIR_TS" --ref "$PAIR_REF" --record NOTHEX --signoff owner --why w --source s
  [[ "$EC" == 2 && "$ERR" == *"12 lowercase hex"* ]] || log_fail "TEST-003 arm 4: expected exit 2 naming the 12-lowercase-hex format; got $EC: $ERR"
  [[ "$sha" == "$(ledger_sha "$led")" ]] || log_fail "TEST-003 arm 4: ledger must be byte-identical"

  # positive control: the same shape with a valid, distinguishable --record succeeds
  run_sa classify --ledger "$led" --ts "$PAIR_TS" --ref "$PAIR_REF" --record "$PAIR_CK" --signoff owner --why w --source s
  [[ "$EC" == 0 ]] || log_fail "TEST-003 positive control: a valid --record on a distinguishable pair must exit 0, got $EC: $ERR"
  [[ "$sha" != "$(ledger_sha "$led")" ]] || log_fail "TEST-003 positive control: the successful call must have appended"
  log_pass "TEST-003 every indistinguishable shape exits 2 with its reason and leaves the ledger byte-identical; the distinguishable control succeeds"
}

# --- classify-same-ts-pair batch B (TEST-004, TEST-005, TEST-008) ---

# fold_vs_baseline <old-json> <new-json> <ledger> -> one line:
# "OK <items> <overlays> <compared>" or the first difference. record_key is
# removed from the new items; records a classifies_record overlay targets are
# skipped (counts and violations are compared only when none is targeted).
fold_vs_baseline() {
  node -e '
    const fs=require("fs");
    const old=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const neu=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
    const targeted=new Set();
    let overlays=0;
    for (const line of fs.readFileSync(process.argv[3],"utf8").split(/\r?\n/)) {
      const t=line.trim(); if (t===""||t.startsWith("#")) continue;
      let r; try { r=JSON.parse(t); } catch { continue; }
      if (r && r.type==="spec_amendment_classification") {
        overlays+=1;
        if (r.classifies_record) targeted.add(String(r.classifies_record));
      }
    }
    if (old.items.length!==neu.items.length) { console.log("ITEMS old="+old.items.length+" new="+neu.items.length); process.exit(0); }
    const strip=(i)=>{const c=Object.assign({},i);delete c.record_key;return JSON.stringify(c);};
    let compared=0;
    for (let n=0;n<old.items.length;n+=1) {
      if (targeted.has(neu.items[n].record_key)) continue;
      compared+=1;
      if (strip(old.items[n])!==strip(neu.items[n])) { console.log("ITEM "+n+" old="+strip(old.items[n])+" new="+strip(neu.items[n])); process.exit(0); }
    }
    if (targeted.size===0) {
      if (JSON.stringify(old.counts)!==JSON.stringify(neu.counts)) { console.log("COUNTS old="+JSON.stringify(old.counts)+" new="+JSON.stringify(neu.counts)); process.exit(0); }
      const sv=(j)=>JSON.stringify(j.violations.map((v)=>{const c=Object.assign({},v);delete c.record_key;return c;}));
      if (sv(old)!==sv(neu)) { console.log("VIOLATIONS differ"); process.exit(0); }
    }
    console.log("OK "+old.items.length+" "+overlays+" "+compared);
  ' "$1" "$2" "$3"
}

test_existing_overlays_fold_unchanged() {
  log_info "Test: every existing overlay folds exactly as the cf39c58f engine folds it (TEST-004)..."
  local dir base_ref base_script base_ledger verdict n_items n_overlays
  base_ref="${AAI_SPEC_AMEND_PAIR_BASE_REF:-cf39c58f}"
  dir="$TEST_DIR/t004"
  mkdir -p "$dir"
  if ! git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null 2>&1; then
    log_info "TEST-004: the base commit $base_ref is not in this checkout (shallow clone?) — the baseline fold cannot be produced here"
    log_pass "TEST-004 SKIPPED-ARM: baseline unreachable; nothing asserted rather than asserting against the wrong baseline"
    return
  fi
  base_script="$dir/spec-amend-base.mjs"
  base_ledger="$dir/base-decisions.jsonl"
  git -C "$PROJECT_ROOT" show "$base_ref:.aai/scripts/spec-amend.mjs" > "$base_script" 2>/dev/null \
    || log_fail "TEST-004: $base_ref has no .aai/scripts/spec-amend.mjs — FAILING CLOSED (a missing ref, not a detected regression)"
  git -C "$PROJECT_ROOT" show "$base_ref:docs/ai/decisions.jsonl" > "$base_ledger" 2>/dev/null \
    || log_fail "TEST-004: $base_ref has no docs/ai/decisions.jsonl — FAILING CLOSED (a missing ref, not a detected regression)"
  ln -snf "$PROJECT_ROOT/.aai/scripts/lib" "$dir/lib"

  # arm 1 (historical): the base ledger through the base program and the new one.
  EC=0; node "$base_script" list --ledger "$base_ledger" --json --status all > "$dir/h-old.json" 2> "$dir/h-old.err" || EC=$?
  [[ "$EC" == 0 ]] || log_fail "TEST-004 arm 1: the base program failed to fold the base ledger (rc=$EC): $(cat "$dir/h-old.err")"
  EC=0; node "$SA" list --ledger "$base_ledger" --json --status all > "$dir/h-new.json" 2> "$dir/h-new.err" || EC=$?
  [[ "$EC" == 0 ]] || log_fail "TEST-004 arm 1: the current program failed to fold the base ledger (rc=$EC): $(cat "$dir/h-new.err")"
  verdict="$(fold_vs_baseline "$dir/h-old.json" "$dir/h-new.json" "$base_ledger")"
  [[ "$verdict" == OK\ * ]] || log_fail "TEST-004 arm 1: the historical ledger must fold identically (record_key removed): $verdict"
  n_items="$(printf '%s' "$verdict" | cut -d' ' -f2)"; n_overlays="$(printf '%s' "$verdict" | cut -d' ' -f3)"
  # positive control: the comparison actually read a real corpus
  [[ "$n_items" -gt 300 && "$n_overlays" -ge 100 ]] || log_fail "TEST-004 positive control: expected over 300 items and at least 100 overlays read, got items=$n_items overlays=$n_overlays"

  # arm 2 (live): the live ledger, every record no classifies_record overlay targets.
  EC=0; node "$base_script" list --ledger "$LIVE_LEDGER" --json --status all > "$dir/l-old.json" 2> "$dir/l-old.err" || EC=$?
  [[ "$EC" == 0 ]] || log_fail "TEST-004 arm 2: the base program failed to fold the live ledger (rc=$EC): $(cat "$dir/l-old.err")"
  EC=0; node "$SA" list --ledger "$LIVE_LEDGER" --json --status all > "$dir/l-new.json" 2> "$dir/l-new.err" || EC=$?
  [[ "$EC" == 0 ]] || log_fail "TEST-004 arm 2: the current program failed to fold the live ledger (rc=$EC): $(cat "$dir/l-new.err")"
  verdict="$(fold_vs_baseline "$dir/l-old.json" "$dir/l-new.json" "$LIVE_LEDGER")"
  [[ "$verdict" == OK\ * ]] || log_fail "TEST-004 arm 2: the live ledger must fold identically for every record no record overlay targets: $verdict"
  log_pass "TEST-004 $base_ref and the current engine fold the historical ledger ($n_items items, $n_overlays overlays) and the live ledger identically, record_key aside"
}

# buckets_of <program> <ledger> -> "what=bucket;..." in fold order.
buckets_of() {
  node "$1" list --ledger "$2" --json --status all | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(j.items.map(i=>i.what+"="+i.bucket).join(";"))})'
}

test_old_reader_never_applies_a_record_overlay() {
  log_info "Test: the cf39c58f reader counts a record-addressed overlay as dangling and applies it to no record (TEST-005)..."
  local dir base_ref base_script led ck ck2 a b old_before old_after new_after old_note
  base_ref="${AAI_SPEC_AMEND_PAIR_BASE_REF:-cf39c58f}"
  dir="$TEST_DIR/t005"
  mkdir -p "$dir"
  if ! git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null 2>&1; then
    log_info "TEST-005: the base commit $base_ref is not in this checkout (shallow clone?)"
    log_pass "TEST-005 SKIPPED-ARM: the old reader is unreachable; nothing asserted rather than asserting against the wrong reader"
    return
  fi
  base_script="$dir/spec-amend-base.mjs"
  git -C "$PROJECT_ROOT" show "$base_ref:.aai/scripts/spec-amend.mjs" > "$base_script" 2>/dev/null \
    || log_fail "TEST-005: $base_ref has no .aai/scripts/spec-amend.mjs — FAILING CLOSED"
  ln -snf "$PROJECT_ROOT/.aai/scripts/lib" "$dir/lib"

  # A pair of two CONTRACT records (the shape the old classify refused as ambiguous).
  led="$(mk_ledger t005)"
  a="$(pair_rec "2026-10-10T11:35:07Z" t005-ref contract "first contract change" fu-amend-t005)"
  b="$(pair_rec "2026-10-10T11:35:07Z" t005-ref contract "second contract change" fu-amend-t005)"
  {
    printf '%s\n' '{"v":1,"ts":"2026-10-10T11:35:08Z","actor":"orchestrator","type":"follow_up","id":"fu-amend-t005","priority":"P2","what":"owner sign-off owed","why":"fixture"}'
    printf '%s\n' "$a"; printf '%s\n' "$b"
  } >> "$led"
  ck="$(rec_key "$a")"; ck2="$(rec_key "$b")"
  [[ "$ck" != "$ck2" ]] || log_fail "TEST-005 setup: the two contract records must have distinct keys"

  old_before="$(buckets_of "$base_script" "$led")"
  [[ "$old_before" == "first contract change=unsigned-tracked;second contract change=unsigned-tracked" ]] || log_fail "TEST-005 setup: both records must start unsigned-tracked; got: $old_before"

  run_sa classify --ledger "$led" --ts "2026-10-10T11:35:07Z" --ref t005-ref --record "$ck" --signoff owner --why "owner signed" --source "owner answer"
  [[ "$EC" == 0 ]] || log_fail "TEST-005: the new classify --record must exit 0, got $EC (stderr: $ERR)"

  new_after="$(buckets_of "$SA" "$led")"
  [[ "$new_after" == "first contract change=signed;second contract change=unsigned-tracked" ]] || log_fail "TEST-005: the new reader must show exactly one signed record; got: $new_after"

  old_after="$(buckets_of "$base_script" "$led")"
  [[ "$old_after" == "$old_before" ]] || log_fail "TEST-005: the old reader must keep BOTH records at their pre-call bucket.
before: $old_before
after:  $old_after"
  old_note="$(node "$base_script" list --ledger "$led" --status all)"
  [[ "$old_note" == *"NOTE 1 spec_amendment_classification record(s) carry no usable classifies_ts/classifies_ref pair — counted, never applied"* ]] \
    || log_fail "TEST-005: the old reader's dangling NOTE must count exactly 1 overlay; got: $old_note"
  log_pass "TEST-005 the cf39c58f reader counts the record overlay as dangling (NOTE 1) and signs neither record; the new reader signs exactly one"
}

# legacy_rec <ts> <ref> <what> -> an unclassified spec_amendment (no owner_signoff, no class).
legacy_rec() {
  printf '{"v":1,"ts":"%s","actor":"remediation","type":"spec_amendment","ref_id":"%s","spec":"docs/specs/SPEC-DRAFT-spec-t008.md","spec_id":"spec-t008","what":"%s","why":"fixture"}' "$1" "$2" "$3"
}

test_printed_remedies_address_the_record() {
  log_info "Test: list --strict prints classify remedies that name the record of a shared pair, and each runs verbatim (TEST-008)..."
  local dir base_ref base_script led specs a b c ka kb kc strict_err old_err la lb lc n line cmd keys
  base_ref="${AAI_SPEC_AMEND_PAIR_BASE_REF:-cf39c58f}"
  dir="$TEST_DIR/t008"; mkdir -p "$dir"; specs="$dir/specs"; mkdir -p "$specs"
  led="$(mk_ledger t008)"
  a="$(legacy_rec "2026-10-10T11:35:07Z" t008-ref "shared legacy one")"
  b="$(legacy_rec "2026-10-10T11:35:07Z" t008-ref "shared legacy two")"
  c="$(legacy_rec "2026-10-10T11:40:00Z" t008-solo "unshared legacy")"
  { printf '%s\n' "$a"; printf '%s\n' "$b"; printf '%s\n' "$c"; } >> "$led"
  ka="$(rec_key "$a")"; kb="$(rec_key "$b")"; kc="$(rec_key "$c")"

  run_sa list --ledger "$led" --specs-dir "$specs" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-008 setup: the fixture must refuse --strict, got $EC (stderr: $ERR)"
  strict_err="$ERR"
  la="$(printf '%s\n' "$strict_err" | /usr/bin/grep -F 'classify --ts' | /usr/bin/grep -F "$ka" || true)"
  lb="$(printf '%s\n' "$strict_err" | /usr/bin/grep -F 'classify --ts' | /usr/bin/grep -F "$kb" || true)"
  lc="$(printf '%s\n' "$strict_err" | /usr/bin/grep -F 'classify --ts' | /usr/bin/grep -F 't008-solo' || true)"
  n="$(printf '%s\n' "$strict_err" | /usr/bin/grep -cF 'classify --ts' || true)"
  [[ "$n" == 3 ]] || log_fail "TEST-008: exactly three classify remedies expected, got $n; stderr: $strict_err"
  [[ -n "$la" && -n "$lb" ]] || log_fail "TEST-008: each record of the shared pair must be named by its --record key in its remedy ($ka / $kb); stderr: $strict_err"
  [[ "$la" == *"--record $ka"* && "$lb" == *"--record $kb"* ]] || log_fail "TEST-008: the shared remedies must carry --record <key>; got: $la / $lb"
  [[ -n "$lc" && "$lc" != *--record* ]] || log_fail "TEST-008: the unshared remedy must carry no --record; got: $lc"

  # the unshared line is byte-equal to what the base program printed
  if git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null 2>&1; then
    base_script="$dir/spec-amend-base.mjs"
    git -C "$PROJECT_ROOT" show "$base_ref:.aai/scripts/spec-amend.mjs" > "$base_script" 2>/dev/null \
      || log_fail "TEST-008: $base_ref has no spec-amend.mjs — FAILING CLOSED"
    ln -snf "$PROJECT_ROOT/.aai/scripts/lib" "$dir/lib"
    old_err="$(node "$base_script" list --ledger "$led" --specs-dir "$specs" --strict 2>&1 >/dev/null || true)"
    [[ "$(printf '%s\n' "$old_err" | /usr/bin/grep -F 't008-solo' | /usr/bin/grep -F 'classify --ts' || true)" == "$lc" ]] \
      || log_fail "TEST-008: the unshared remedy must be byte-identical to the base program's line.
base: $(printf '%s\n' "$old_err" | /usr/bin/grep -F 't008-solo' | /usr/bin/grep -F 'classify --ts' || true)
now:  $lc"
  else
    log_info "TEST-008: base commit $base_ref unreachable — the byte-equality arm is skipped (the --record-free assertion above still ran)"
  fi

  # each printed line runs verbatim (placeholders filled, nothing else rewritten)
  for line in "$la" "$lb" "$lc"; do
    line="${line#"${line%%node *}"}"
    cmd="${line//<one line>/back-classified at the gate}"
    cmd="${cmd//<evidence>/tests/skills/test-aai-spec-amend.sh TEST-008}"
    cmd="${cmd#node .aai/scripts/spec-amend.mjs }"
    EC=0
    eval "node \"\$SA\" $cmd --ledger \"\$led\"" > "$dir/.out" 2> "$dir/.err" || EC=$?
    [[ "$EC" == 0 ]] || log_fail "TEST-008: the printed remedy, run verbatim, must exit 0, got $EC: $line
stderr: $(cat "$dir/.err")"
  done
  run_sa list --ledger "$led" --specs-dir "$specs" --strict
  [[ "$EC" == 0 ]] || log_fail "TEST-008: after the three printed remedies --strict must exit 0, got $EC (stderr: $ERR)"

  # list --json items carry the recomputed key; --help documents --record
  keys="$(node "$SA" list --ledger "$led" --json --status all | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{process.stdout.write(JSON.parse(s).items.map(i=>i.record_key).sort().join(","))})')"
  [[ "$keys" == "$(printf '%s\n' "$ka" "$kb" "$kc" | sort | paste -sd, -)" ]] || log_fail "TEST-008: list --json record_key must equal the recomputed key of each record; got: $keys"
  run_sa --help
  [[ "$OUT" == *"--record"* ]] || log_fail "TEST-008: --help must document --record"
  log_pass "TEST-008 shared-pair remedies name --record, the unshared remedy is byte-identical to the base, every printed line runs verbatim and clears --strict"
}

# --- classify-same-ts-pair batch C (TEST-006, TEST-007, TEST-009) ---

# seed_window <ledger> <ref> <spec-relpath> -> appends one SIGNED contract
# spec_amendment per second from now-1 to now+8 under <ref>, so whatever
# second the writer under test stamps, its (ts, ref_id) pair already holds a
# record (a deterministic same-second collision). Ids carry a distinct `what`.
seed_window() {
  node -e '
    const fs=require("fs");
    const [led,ref,spec]=process.argv.slice(1);
    const now=Math.floor(Date.now()/1000);
    let out="";
    for (let s=-1;s<=8;s+=1) {
      const ts=new Date((now+s)*1000).toISOString().replace(/\.\d{3}Z$/,"Z");
      out+=JSON.stringify({v:1,ts,actor:"orchestrator",type:"spec_amendment",ref_id:ref,spec,spec_id:"spec-seed",owner_signoff:true,amendment_class:"contract",what:"seeded signed record "+s,why:"fixture",authority:"fixture owner decision"})+"\n";
    }
    fs.appendFileSync(led,out);
  ' "$1" "$2" "$3"
}

# ledger_amendments <ledger> -> the number of spec_amendment lines.
ledger_amendments() {
  node -e '
    const fs=require("fs");let n=0;
    for (const l of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=l.trim(); if (t===""||t.startsWith("#")) continue;
      try { if (JSON.parse(t).type==="spec_amendment") n+=1; } catch { /* skip */ }
    }
    process.stdout.write(String(n));
  ' "$1"
}

# last_amendment_key <ledger> -> recordKey of the last spec_amendment line,
# computed here independently of the engine.
last_amendment_key() {
  node -e '
    const fs=require("fs"),c=require("crypto");let last=null;
    for (const l of fs.readFileSync(process.argv[1],"utf8").split(/\r?\n/)) {
      const t=l.trim(); if (t===""||t.startsWith("#")) continue;
      try { if (JSON.parse(t).type==="spec_amendment") last=t; } catch { /* skip */ }
    }
    process.stdout.write(c.createHash("sha256").update(JSON.stringify(JSON.parse(last))).digest("hex").slice(0,12));
  ' "$1"
}

# signed_keys <ledger> -> sorted record_keys whose bucket is signed, comma-joined.
signed_keys() {
  node "$SA" list --ledger "$1" --json --status all | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{process.stdout.write(JSON.parse(s).items.filter(i=>i.bucket==="signed").map(i=>i.record_key).sort().join(","))})'
}

test_add_collision_is_addressable() {
  log_info "Test: an add that collides on (ts, ref_id) is appended, judged on ITS record, and addressable by --record (TEST-006)..."
  local led spec before_n after_n key signed_before signed_after note
  led="$(mk_ledger t006)"
  spec="$(mk_spec "SPEC-DRAFT-t006.md" "spec-t006-fixture")"
  seed_window "$led" t006-ref "docs/specs/SPEC-DRAFT-spec-seed.md"
  before_n="$(ledger_amendments "$led")"
  [[ "$before_n" == 10 ]] || log_fail "TEST-006 setup: the seeded window must hold 10 records, got $before_n"
  signed_before="$(signed_keys "$led")"

  run_sa add --ledger "$led" --spec "$spec" --ref t006-ref --what "colliding change" --why "same second as a seeded record" --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-006: a same-second collision must not refuse the add; exit $EC (stdout: $OUT) (stderr: $ERR)"
  after_n="$(ledger_amendments "$led")"
  [[ "$after_n" == "$((before_n + 1))" ]] || log_fail "TEST-006 positive control: exactly one amendment must be appended (before=$before_n after=$after_n)"

  key="$(last_amendment_key "$led")"
  note="$(printf '%s\n' "$OUT" | /usr/bin/grep -F 'NOTE this record shares (ts, ref_id) with' || true)"
  [[ -n "$note" ]] || log_fail "TEST-006: the collision must be disclosed in a NOTE; stdout: $OUT"
  [[ "$note" == *"earlier record(s); address it with --record $key"* ]] || log_fail "TEST-006: the NOTE must name --record <the appended line's key $key>; got: $note"
  [[ "$OUT" == *"UNSIGNED amendment"*"bucket unsigned-tracked"* ]] || log_fail "TEST-006: the add must judge ITS OWN record (unsigned-tracked), not the earlier sibling; stdout: $OUT"

  run_sa classify --ledger "$led" --ts "$(node -e 'const fs=require("fs");const ls=fs.readFileSync(process.argv[1],"utf8").trim().split(/\n/);let t="";for(const l of ls){try{const r=JSON.parse(l);if(r.type==="spec_amendment")t=r.ts}catch{}}process.stdout.write(t)' "$led")" --ref t006-ref --record "$key" --signoff owner --why "owner signed" --source "owner answer"
  [[ "$EC" == 0 ]] || log_fail "TEST-006: classify --record $key (the key the writer printed) must exit 0, got $EC (stderr: $ERR)"
  signed_after="$(signed_keys "$led")"
  [[ "$signed_after" == "$(printf '%s\n%s\n' "${signed_before//,/$'\n'}" "$key" | sort | paste -sd, -)" ]] \
    || log_fail "TEST-006: exactly the new record may turn signed.
before: $signed_before
after:  $signed_after
key:    $key"
  log_pass "TEST-006 a same-second add exits 0, names --record <key> equal to its own line's key, judges its own record, and classify --record signs only it"
}

test_restamp_collision_is_addressable() {
  log_info "Test: a restamp that collides on (ts, ref_id) is judged on ITS record, verified and unverified, and its remedy names --record (TEST-007)..."
  local led spec frozen specU ledU key keyU note line cmd before_n after_n bucket
  frozen="$TEST_DIR/t007-frozen.md"
  spec="$(mk_linked_freezable_spec t007-specs/a.md spec-t007-fixture t007-intake)"
  freeze_spec "$spec" || log_fail "TEST-007 setup: real spec-freeze.mjs refused the fixture"
  cp "$spec" "$frozen"
  specU="$TEST_DIR/t007-specs/u.md"; cp "$frozen" "$specU"

  # ARM 1 - a genuine allocator rename (verified cause): the NEW record is a measurement record.
  sed -i.bak -e 's/SPEC-DRAFT-spec-t007-fixture/SPEC-0312-spec-t007-fixture/g' \
             -e 's/CHANGE-DRAFT-t007-intake/CHANGE-0312-t007-intake/g' "$spec"
  /usr/bin/grep -qF 'SPEC-0312-spec-t007-fixture' "$spec" || log_fail "TEST-007 arm 1: the simulated allocator rewrite did not land"
  led="$(mk_ledger t007a)"
  seed_window "$led" t007-ref "docs/specs/SPEC-DRAFT-spec-seed.md"
  before_n="$(ledger_amendments "$led")"
  run_sa restamp --spec "$spec" --ref t007-ref --ledger "$led"
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 1: a same-second collision must not refuse the restamp; exit $EC (stdout: $OUT) (stderr: $ERR)"
  after_n="$(ledger_amendments "$led")"
  [[ "$after_n" == "$((before_n + 1))" ]] || log_fail "TEST-007 positive control: exactly one amendment must be appended (before=$before_n after=$after_n)"
  key="$(last_amendment_key "$led")"
  note="$(printf '%s\n' "$OUT" | /usr/bin/grep -F 'NOTE this record shares (ts, ref_id) with' || true)"
  [[ "$note" == *"earlier record(s); address it with --record $key"* ]] || log_fail "TEST-007 arm 1: the NOTE must name --record <the appended line's key $key>; stdout: $OUT"
  [[ "$OUT" == *"bucket measurement"* ]] || log_fail "TEST-007 arm 1: the restamp must judge ITS OWN record (measurement); stdout: $OUT"
  bucket="$(node "$SA" list --ledger "$led" --json --status all | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(j.items.filter(i=>i.bucket==="measurement").map(i=>i.record_key).join(",")+"|"+j.items.filter(i=>i.bucket==="signed").length)})')"
  [[ "$bucket" == "$key|10" ]] || log_fail "TEST-007 arm 1: the new record is the only measurement row and the 10 seeded records stay signed; got: $bucket (key $key)"

  # ARM 2 - an unverified restamp: the printed classify remedy names --record and runs verbatim.
  sed -i.bak 's/original description text/a DIFFERENT promise this spec never made/' "$specU"
  ledU="$(mk_ledger t007b)"
  seed_window "$ledU" t007-ref "docs/specs/SPEC-DRAFT-spec-seed.md"
  run_sa restamp --spec "$specU" --ref t007-ref --ledger "$ledU"
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 2: an unverified colliding restamp must exit 0; exit $EC (stdout: $OUT) (stderr: $ERR)"
  keyU="$(last_amendment_key "$ledU")"
  [[ "$OUT" == *"bucket unsigned-tracked"* ]] || log_fail "TEST-007 arm 2: the restamp must judge ITS OWN record (unsigned-tracked); stdout: $OUT"
  line="$(printf '%s\n' "$OUT" | /usr/bin/grep -F 'NOTE sign it off once someone has said what changed:' | /usr/bin/grep -F 'classify --ts' || true)"
  [[ -n "$line" ]] || log_fail "TEST-007 arm 2: the unverified restamp must print a classify remedy; stdout: $OUT"
  [[ "$line" == *"--record $keyU"* ]] || log_fail "TEST-007 arm 2: the remedy of a shared pair must carry --record $keyU; got: $line"
  cmd="${line#*: }"
  cmd="${cmd#node .aai/scripts/spec-amend.mjs }"
  cmd="${cmd//<who decided, where>/owner answer}"
  cmd="${cmd//<what the drift really was>/fixture drift}"
  EC=0
  eval "node \"\$SA\" $cmd" > "$TEST_DIR/.out" 2> "$TEST_DIR/.err" || EC=$?
  [[ "$EC" == 0 ]] || log_fail "TEST-007 arm 2: the printed remedy, run verbatim, must exit 0, got $EC: $line
stderr: $(cat "$TEST_DIR/.err")"
  [[ "$(signed_keys "$ledU")" == *"$keyU"* ]] || log_fail "TEST-007 arm 2: the remedy must have signed the new record $keyU; signed: $(signed_keys "$ledU")"
  log_pass "TEST-007 a same-second restamp (verified and unverified) exits 0, judges its own record, names --record <key>, and the printed remedy signs it"
}

test_448_record_signed_on_the_live_ledger() {
  log_info "Test: the PR #448 contract record is signed on the live ledger (TEST-009)..."
  local led row fu ov
  led="$PROJECT_ROOT/docs/ai/decisions.jsonl"
  [[ -f "$led" ]] || log_fail "TEST-009: the live ledger $led is missing"
  row="$(node "$SA" list --ledger "$led" --json --status all | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);
      const f=(k)=>j.items.find(i=>i.record_key===k)||null;
      const a=f("ae5529c8b535"), m=f("1c45f52a2649");
      process.stdout.write(JSON.stringify({a:a&&{ts:a.ts,ref:a.ref_id,bucket:a.bucket,by:a.classified_by},m:m&&{bucket:m.bucket,by:m.classified_by}}));
    })')"
  [[ "$row" == *'"a":{"ts":"2026-10-10T11:35:07Z","ref":"directed-merge-and-post-merge-cleanup","bucket":"signed"'* ]] \
    || log_fail "TEST-009: record ae5529c8b535 must exist at 2026-10-10T11:35:07Z/directed-merge-and-post-merge-cleanup and be signed; got: $row"
  [[ "$row" == *'"by":null'* && "$row" == *'"m":{"bucket":"measurement","by":null}'* ]] \
    || log_fail "TEST-009: the measurement sibling 1c45f52a2649 must stay measurement with classified_by null; got: $row"
  ov="$(/usr/bin/grep -F '"classifies_record":"ae5529c8b535"' "$led" || true)"
  [[ -n "$ov" ]] || log_fail "TEST-009 positive control: a classifies_record overlay for ae5529c8b535 must be on the ledger"
  [[ "$ov" == *Podepsat* ]] || log_fail "TEST-009: the overlay source must cite the owner's 'Podepsat' answer; got: $ov"
  [[ "$ov" == *"PR #448"* ]] || log_fail "TEST-009: the overlay source must cite PR #448; got: $ov"
  for fu in fu-amend-directed-merge-and-post-007bae fu-classify-same-ts-pair; do
    run_fu list --ledger "$led" --status all --json
    [[ "$OUT" == *"$fu"* ]] || log_fail "TEST-009 positive control: follow-ups list must show $fu"
    printf '%s' "$OUT" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        const j=JSON.parse(s);const arr=Array.isArray(j)?j:(j.items||j.follow_ups||[]);
        const it=arr.find(x=>x.id===process.argv[1]);
        process.exit(it&&it.status==="done"?0:1)})' "$fu" \
      || log_fail "TEST-009: follow-up $fu must be done"
  done
  run_sa list --ledger "$led" --strict
  [[ "$EC" == 0 ]] || log_fail "TEST-009: list --strict on the live ledger must exit 0, got $EC (stderr: $ERR)"
  log_pass "TEST-009 the #448 contract record is signed through a record-addressed overlay citing 'Podepsat', its sibling stays measurement, both follow-ups are done, strict is clean"
}

# --- classify-same-ts-pair bot sweep, PR #449 (TEST-010, TEST-011) ---

test_add_duplicate_is_idempotent() {
  log_info "Test: an add byte-identical to a record already on the ledger appends nothing and names that record's key (TEST-010)..."
  local led spec rel before_n after_n key
  led="$(mk_ledger t010)"
  spec="$(mk_spec "SPEC-DRAFT-t010.md" "spec-t010-fixture")"
  rel="$(node -e 'process.stdout.write(require("path").relative(process.cwd(), process.argv[1]))' "$spec")"
  # Seed, for every second of the window the writer can stamp, the EXACT line
  # `add --class measurement --signoff none` will build, so the collision is a
  # byte-identical one whichever second the writer lands in.
  node -e '
    const fs=require("fs");
    const [led,spec,specId]=process.argv.slice(1);
    const now=Math.floor(Date.now()/1000);
    let out="";
    for (let s=-1;s<=8;s+=1) {
      const ts=new Date((now+s)*1000).toISOString().replace(/\.\d{3}Z$/,"Z");
      out+=JSON.stringify({v:1,ts,actor:"orchestrator",type:"spec_amendment",ref_id:"t010-ref",spec,spec_id:specId,owner_signoff:false,amendment_class:"measurement",what:"repeated change",why:"repeated within one second"})+"\n";
    }
    fs.appendFileSync(led,out);
  ' "$led" "$rel" "spec-t010-fixture"
  before_n="$(ledger_amendments "$led")"
  [[ "$before_n" == 10 ]] || log_fail "TEST-010 setup: the seeded window must hold 10 records, got $before_n"

  run_sa add --ledger "$led" --spec "$spec" --ref t010-ref --what "repeated change" --why "repeated within one second" --class measurement --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-010: an identical add must be an idempotent no-op that exits 0; exit $EC (stdout: $OUT) (stderr: $ERR)"
  after_n="$(ledger_amendments "$led")"
  [[ "$after_n" == "$before_n" ]] || log_fail "TEST-010: nothing may be appended for a byte-identical record (before=$before_n after=$after_n)"
  key="$(printf '%s\n' "$OUT" | sed -n 's/.*addressed by --record \([0-9a-f]\{12\}\).*/\1/p;t' )"
  [[ -n "$key" ]] || log_fail "TEST-010: the no-op must print the existing record's --record key; stdout: $OUT"
  [[ "$(node "$SA" list --ledger "$led" --json --status all | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{process.stdout.write(String(JSON.parse(s).items.filter(i=>i.record_key===process.argv[1]).length))})' "$key")" == 1 ]] \
    || log_fail "TEST-010: the printed key $key must address exactly one record on the ledger"

  # Positive control: a NON-identical add in the same window still appends.
  run_sa add --ledger "$led" --spec "$spec" --ref t010-ref --what "a different change" --why "repeated within one second" --class measurement --signoff none
  [[ "$EC" == 0 ]] || log_fail "TEST-010 positive control: a non-identical collision must still append; exit $EC (stderr: $ERR)"
  [[ "$(ledger_amendments "$led")" == "$((before_n + 1))" ]] || log_fail "TEST-010 positive control: exactly one record must be appended for the non-identical add"
  log_pass "TEST-010 an add identical to a ledger record is an exit-0 no-op naming that record's key, and a non-identical collision still appends"
}

test_strict_remedy_for_identical_pair_is_a_named_note() {
  log_info "Test: list --strict prints a named note, not an unrunnable --record line, for byte-identical records (TEST-011)..."
  local dir specs led a c strict_err n line
  dir="$TEST_DIR/t011"; mkdir -p "$dir"; specs="$dir/specs"; mkdir -p "$specs"
  led="$(mk_ledger t011)"
  a="$(legacy_rec "2026-10-10T11:35:07Z" t011-dup "identical legacy")"
  c="$(legacy_rec "2026-10-10T11:40:00Z" t011-solo "unshared legacy")"
  { printf '%s\n' "$a"; printf '%s\n' "$a"; printf '%s\n' "$c"; } >> "$led"

  run_sa list --ledger "$led" --specs-dir "$specs" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-011 setup: the fixture must refuse --strict, got $EC (stderr: $ERR)"
  strict_err="$ERR"
  n="$(printf '%s\n' "$strict_err" | /usr/bin/grep -cF 'classify --ts' || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-011: only the unshared record may get a classify line, got $n; stderr: $strict_err"
  line="$(printf '%s\n' "$strict_err" | /usr/bin/grep -F 'classify --ts' || true)"
  [[ "$line" == *t011-solo* ]] || log_fail "TEST-011: the one classify line must be the unshared record's; stderr: $strict_err"
  [[ "$line" != *--record* ]] || log_fail "TEST-011: the unshared line must carry no --record; stderr: $strict_err"
  n="$(printf '%s\n' "$strict_err" | /usr/bin/grep -cF 'indistinguishable duplicate records: no classify can address one; see the ledger lines' || true)"
  [[ "$n" == 2 ]] || log_fail "TEST-011: each identical record must get the named note (2 expected), got $n; stderr: $strict_err"
  log_pass "TEST-011 byte-identical records get a named note instead of an unrunnable --record line, the unshared line is unchanged"
}

test_identical_pair_prose_and_refusal_stay_honest() {
  log_info "Test: for byte-identical records the strict trailer and the classify refusal promise nothing they cannot deliver (TEST-012)..."
  local dir specs led solo_led a c strict_err refuse_err n
  dir="$TEST_DIR/t012"; mkdir -p "$dir"; specs="$dir/specs"; mkdir -p "$specs"
  a="$(legacy_rec "2026-10-10T11:35:07Z" t012-dup "identical legacy")"
  c="$(legacy_rec "2026-10-10T11:40:00Z" t012-solo "unshared legacy")"
  led="$(mk_ledger t012)"
  { printf '%s\n' "$a"; printf '%s\n' "$a"; printf '%s\n' "$c"; } >> "$led"
  solo_led="$(mk_ledger t012solo)"
  printf '%s\n' "$c" >> "$solo_led"

  # (a) the trailer: positive control first, the original sentence is byte-identical when every violation got a runnable command.
  run_sa list --ledger "$solo_led" --specs-dir "$specs" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-012 control: the solo fixture must refuse --strict, got $EC (stderr: $ERR)"
  n="$(printf '%s\n' "$ERR" | /usr/bin/grep -cF 'so each command above takes its record to `unsigned-tracked` and this gate to exit 0;' || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-012 control: the trailer must be unchanged when every violation has a command; stderr: $ERR"
  run_sa list --ledger "$led" --specs-dir "$specs" --strict
  [[ "$EC" == 1 ]] || log_fail "TEST-012 setup: the identical-pair fixture must refuse --strict, got $EC (stderr: $ERR)"
  strict_err="$ERR"
  n="$(printf '%s\n' "$strict_err" | /usr/bin/grep -cF 'this gate to exit 0' || true)"
  [[ "$n" == 0 ]] || log_fail "TEST-012: the trailer must not promise exit 0 while indistinguishable records remain; stderr: $strict_err"
  n="$(printf '%s\n' "$strict_err" | /usr/bin/grep -cF 'no command above can clear' || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-012: the trailer must say the indistinguishable records have no command, once; stderr: $strict_err"

  # (b) the pair-addressed refusal: byte-identical candidates list their key once and print no --record template.
  run_sa classify --ledger "$led" --ts "2026-10-10T11:35:07Z" --ref t012-dup --signoff none --why "x" --source "y"
  [[ "$EC" == 2 ]] || log_fail "TEST-012: classify on an identical pair must refuse with 2, got $EC (stderr: $ERR)"
  refuse_err="$ERR"
  n="$(printf '%s\n' "$refuse_err" | /usr/bin/grep -cF 'record=' || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-012: an identical pair's key must be listed once, got $n; stderr: $refuse_err"
  [[ "$refuse_err" != *'<key>'* ]] || log_fail "TEST-012: no --record <key> template may be printed for an identical pair; stderr: $refuse_err"
  [[ "$refuse_err" == *indistinguishable* ]] || log_fail "TEST-012: the refusal must say the records are indistinguishable; stderr: $refuse_err"
  # positive control: a pair of DISTINCT records still lists both keys and the template.
  led="$(mk_ledger t012b)"
  { printf '%s\n' "$a"; printf '%s\n' "$(legacy_rec "2026-10-10T11:35:07Z" t012-dup "a different legacy")"; } >> "$led"
  run_sa classify --ledger "$led" --ts "2026-10-10T11:35:07Z" --ref t012-dup --signoff none --why "x" --source "y"
  [[ "$EC" == 2 ]] || log_fail "TEST-012 control: classify on a distinct pair must refuse with 2, got $EC"
  n="$(printf '%s\n' "$ERR" | /usr/bin/grep -cF 'record=' || true)"
  [[ "$n" == 2 && "$ERR" == *'--record <key>'* ]] || log_fail "TEST-012 control: a distinct pair must list both keys and the template, got $n; stderr: $ERR"
  log_pass "TEST-012 the strict trailer admits the indistinguishable records have no command, the identical-pair refusal lists its key once with no template, distinct pairs unchanged"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-unsigned-spec-amendment-has-no-outflow TEST-001..010, plus TEST-013..016 from validation and code review)"
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
  test_016_closed_item_cannot_excuse_a_new_amendment
  test_017_reopen_never_lands_on_a_discharged_item
  test_018_item_names_spec_by_id_not_path
  test_445_ac12_negative_controls_test003_008_009
  test_482_undisclosed_amendment_caught
  test_483_honest_edits_and_non_targets
  test_484_legacy_degrades_by_name
  test_485_tracker_must_be_open
  test_495_missing_specs_dir_refuses
  test_514_anchor_without_marker_caught
  test_515_contract_hash_escaped_pipe
  test_516_unreadable_spec_refuses
  test_550_amendment_record_anchors
  test_551_restamp_after_renumbering
  test_1354_measurement_add_owes_no_owner_obligation
  test_1355_contract_add_keeps_the_co_created_item
  test_1356_classless_add_stamps_contract_and_names_the_other_value
  test_1357_class_vocabulary_is_closed
  test_1358_measurement_cannot_carry_an_owner_signature
  test_1359_measurement_folds_to_its_own_bucket
  test_1360_strict_violation_buckets_unchanged
  test_1361_measurement_is_excluded_from_strict_on_purpose
  test_1362_undisclosed_amendment_still_refuses
  test_1363_live_ledger_folds_identically
  test_1364_both_writers_pick_one_item_id
  test_1365_restamp_is_measurement_by_construction
  test_1366_classify_is_the_per_record_route
  test_1367_list_surfaces_carry_the_class
  test_1368_status_measurement_is_an_enumerable_view
  test_1369_tool_restamp_is_structural
  test_1370_migration_moves_only_the_structural_cohort
  test_1371_canon_names_the_two_class_partition
  test_1373_class_flag_cannot_disagree_with_the_fold
  test_1374_restamp_cause_is_measured_not_asserted
  test_1375_migrated_cohort_is_the_proven_one
  test_1376_printed_commands_use_flags_the_cli_accepts
  test_1377_canon_states_the_measured_cause_rule
  test_1378_printed_commands_quote_their_values
  test_1379_test_plan_summary_is_recomputed_from_the_tables
  test_1380_signing_refusal_reads_the_projected_class
  test_1381_printed_remedy_runs_in_posix_and_powershell
  test_classify_record_signs_one_of_a_pair
  test_record_overlay_folds_to_its_record_only
  test_classify_refuses_what_it_cannot_tell_apart
  test_existing_overlays_fold_unchanged
  test_old_reader_never_applies_a_record_overlay
  test_printed_remedies_address_the_record
  test_add_collision_is_addressable
  test_restamp_collision_is_addressable
  test_448_record_signed_on_the_live_ledger
  test_add_duplicate_is_idempotent
  test_strict_remedy_for_identical_pair_is_a_named_note
  test_identical_pair_prose_and_refusal_stay_honest
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
