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
    grep -qxF "$expect" <<<"$open_ids" || missing="$missing $sid($expect)"
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
  grep -qF '\"' <<<"$ERR" \
    || log_fail "TEST-016 NB-E: a ref containing a double quote must be ESCAPED in the printed remedy, or the line breaks when pasted; stderr was: $ERR"

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
    log_skip "TEST-516: running as root — chmod 000 is not enforced, skipping this arm"
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
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
