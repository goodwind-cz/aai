#!/usr/bin/env bash
#
# Test: SPEC roadmap-driven-ride-selection-with-budget — rides come from
# docs/ai/roadmap.yaml, and a maintenance ride must be paired with a capability.
# (.aai/scripts/ride-select.mjs), TEST-001..007.
#
# Every gate case runs against a FIXTURE roadmap and a fixture EVENTS ledger;
# only TEST-001/002's "shipped roadmap" arms and TEST-007 read the repository,
# read-only.

set -u
TEST_NAME="test-aai-ride-select"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$PROJECT_ROOT/.aai/scripts/ride-select.mjs"
SHIPPED="$PROJECT_ROOT/docs/ai/roadmap.yaml"
PROPOSE="$PROJECT_ROOT/.aai/scripts/roadmap-propose.mjs"
FOLLOWUPS="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-ride-select.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

# A fixture roadmap: pair 1 capability status controllable, pair 2 planned.
write_roadmap() { # $1=status of pair 1 (planned|active|done)  $2=capability-1 doc status hint file? (unused)
  cat > "$TEST_DIR/roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-one
    maintenance: maint-one
    status: $1
  - capability: cap-two
    maintenance: maint-two
    status: planned
wave_2:
  - later-thing
YAML
}
# A 3-pair fixture roadmap (Spec-AC-29 ranking): each pair's own status is
# independently controllable so a test can move which pair is first-unfinished.
write_roadmap3() { # $1=pair1 status $2=pair2 status $3=pair3 status
  cat > "$TEST_DIR/roadmap3.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: $1
  - capability: cap-b
    maintenance: maint-b
    status: $2
  - capability: cap-c
    maintenance: maint-c
    status: $3
wave_2:
  - later-thing
YAML
}
# Doc status for a ref is read from a docs dir: the gate needs to know whether
# a capability is planned/implementing/done. Fixture docs dir with frontmatter.
write_doc() { # $1=slug $2=type $3=status [$4=extra frontmatter line]
  mkdir -p "$TEST_DIR/docs/issues"
  printf -- '---\nid: %s\nnumber: null\ntype: %s\nstatus: %s\n%s\nlinks:\n  pr: []\n---\n\n# %s\n' "$1" "$2" "$3" "${4:-}" "$1" > "$TEST_DIR/docs/issues/CHANGE-DRAFT-$1.md"
}
run() { node "$ENGINE" "$@" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?; }
out() { cat "$TEST_DIR/out"; }
err() { cat "$TEST_DIR/err"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
# dirhash <dir> — a stable hash of a whole directory tree's file CONTENTS
# (path-sorted), so a `waiting` call that is supposed to be read-only can be
# proven not to have touched anything under it (Spec-AC-08).
dirhash() { find "$1" -type f 2>/dev/null | LC_ALL=C sort | xargs -- shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1; }

# --- roadmap-propose.mjs harvest fixtures (Spec-AC-06..11) -------------------
# Every harvest test gets its OWN docs dir (pNNNdocs), roadmap path, ledger
# and spool — never the shared $TEST_DIR/docs write_doc() accumulates into
# across this whole suite, which would otherwise leak dozens of unrelated
# fixture docs into a harvest's intake source.
propose_write_doc() { # $1=docsRoot $2=slug $3=type $4=status [$5=extra frontmatter line]
  mkdir -p "$1/issues"
  printf -- '---\nid: %s\nnumber: null\ntype: %s\nstatus: %s\n%s\nlinks:\n  pr: []\n---\n\n# %s\n' "$2" "$3" "$4" "${5:-}" "$2" > "$1/issues/CHANGE-DRAFT-$2.md"
}
run_propose() { node "$PROPOSE" "$@" > "$TEST_DIR/pout" 2> "$TEST_DIR/perr"; echo $?; }
pout() { cat "$TEST_DIR/pout"; }
perr() { cat "$TEST_DIR/perr"; }
# propose_field <id> <field> -> JSON.stringify()'d value of that field on the
# candidate with that id, from the LAST run_propose's stdout ($TEST_DIR/pout).
propose_field() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[3], "utf8"));
    const c = j.candidates.find((x) => x.id === process.argv[1]);
    if (!c) { process.stdout.write("__MISSING__"); process.exit(0); }
    process.stdout.write(JSON.stringify(c[process.argv[2]]));
  ' "$1" "$2" "$TEST_DIR/pout"
}
propose_top_id() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(j.candidates.length ? j.candidates[0].id : "__EMPTY__");
  ' "$TEST_DIR/pout"
}
propose_index_of() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
    process.stdout.write(String(j.candidates.findIndex((x) => x.id === process.argv[1])));
  ' "$1" "$TEST_DIR/pout"
}

# --- TEST-001 (Spec-AC-01): validate — shipped roadmap 0; malformed fixtures 2 -
test_001_validate() {
  log_info "Test: validate accepts the shipped roadmap and refuses three malformed shapes (TEST-001)..."
  [ "$(run validate --roadmap "$SHIPPED")" = "0" ] || log_fail "TEST-001: the shipped docs/ai/roadmap.yaml must validate: $(err)"
  # Refs are real slugs: a one-letter ref fails the SLUG rule and made both arms
  # below exit 2 for the WRONG reason (mutation 'duplicate ref accepted' shipped green).
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: cap-a\n    status: planned\n' > "$TEST_DIR/bad1.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad1.yaml")" = "2" ] || log_fail "TEST-001: a pair whose two refs are the same must exit 2"
  grep -q 'are the same ref' "$TEST_DIR/err" || log_fail "TEST-001: the same-ref refusal must say so, not fail on another rule: $(err)"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: planned\n  - capability: cap-c\n    maintenance: cap-a\n    status: planned\n' > "$TEST_DIR/bad2.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad2.yaml")" = "2" ] || log_fail "TEST-001: a duplicate ref across pairs must exit 2"
  grep -q 'cap-a" appears twice' "$TEST_DIR/err" || log_fail "TEST-001: the duplicate refusal must name cap-a as appearing twice: $(err)"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: "Not A Slug!"\n    maintenance: cap-b\n    status: planned\n' > "$TEST_DIR/bad3.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad3.yaml")" = "2" ] || log_fail "TEST-001: a non-slug ref must exit 2"
  printf 'pairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: planned\n' > "$TEST_DIR/bad4.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad4.yaml")" = "0" ] || log_fail "TEST-001: a roadmap without budget must exit 0 (the budget is opt-in): $(err)"
  # closed shape means closed: a duplicated key inside a pair or a second section
  # must refuse — last-wins would silently hide a second maintenance ref (F-03)
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    maintenance: cap-c\n    status: planned\n' > "$TEST_DIR/bad5.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad5.yaml")" = "2" ] || log_fail "TEST-001: two maintenance keys in one pair must exit 2"
  grep -q '"maintenance" appears twice' "$TEST_DIR/err" || log_fail "TEST-001: the refusal must name the duplicated key: $(err)"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: done\n    status: planned\n' > "$TEST_DIR/bad6.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad6.yaml")" = "2" ] || log_fail "TEST-001: two status keys in one pair must exit 2"
  printf 'budget:\n  maintenance_per_capability: 1\nbudget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: planned\n' > "$TEST_DIR/bad7.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad7.yaml")" = "2" ] || log_fail "TEST-001: a second budget section must exit 2"
  printf 'budget:\n  maintenance_per_capability: 2\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: planned\n' > "$TEST_DIR/bad8.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/bad8.yaml")" = "2" ] || log_fail "TEST-001: a budget other than 1 must exit 2 (owner decision)"
  log_pass "validate: shipped 0, eight malformed shapes refused by the named reason (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): next ----------------------------------------------
test_002_next() {
  log_info "Test: next prints the right half, and 'wave 1 complete' when all pairs are done (TEST-002)..."
  write_roadmap planned; write_doc cap-one change draft; write_doc maint-one change draft
  [ "$(run next --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-002: next must exit 0: $(err)"
  [ "$(out)" = "cap-one" ] || log_fail "TEST-002: with pair 1 planned, next must be its capability, got: $(out)"
  # D2: once the capability has STARTED (implementing), next is the maintenance half —
  # proposing an implementing ride is proposing to start it twice (validation F-02)
  write_doc cap-one change implementing
  [ "$(run next --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-002: next must exit 0"
  [ "$(out)" = "maint-one" ] || log_fail "TEST-002: with the capability implementing, next must be the maintenance half, got: $(out)"
  write_doc cap-one change done
  [ "$(run next --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-002: next must exit 0"
  [ "$(out)" = "maint-one" ] || log_fail "TEST-002: with the capability done, next must be the maintenance half, got: $(out)"
  # all done
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-one\n    maintenance: maint-one\n    status: done\n' > "$TEST_DIR/done.yaml"
  [ "$(run next --roadmap "$TEST_DIR/done.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-002: all-done must exit 0"
  grep -qi "wave 1 complete" "$TEST_DIR/out" || log_fail "TEST-002: all-done must print 'wave 1 complete', got: $(out)"
  # shipped: pair 1 capability (live dashboard) is done on main -> maintenance half is next
  # INVARIANT, not a literal: pinning "the next ride is X" is the moving-ref trap
  # of 9deda6c3 (it goes red the moment X closes). What must always hold: the
  # shipped `next` names a ref that the shipped gate ADMITS, or says wave 1 is complete.
  local shipped; shipped="$(run next --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")"
  [ "$shipped" = "0" ] || log_fail "TEST-002: next on the shipped roadmap must exit 0: $(err)"
  local nxt; nxt="$(out)"
  case "$nxt" in
    "wave 1 complete"*) ;;
    *) [ "$(run gate --ref "$nxt" --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" = "0" ] \
         || log_fail "TEST-002: the shipped next ($nxt) must be admitted by the shipped gate: $(err)" ;;
  esac
  log_pass "next: capability first, then maintenance, then wave 1 complete; shipped agrees (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): pair first ----------------------------------------
test_003_pair_first() {
  log_info "Test: a maintenance ride is refused until its capability is at least implementing (TEST-003)..."
  write_roadmap planned; write_doc cap-one change draft; write_doc maint-one change draft
  [ "$(run gate --ref maint-one --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-003: maintenance before its capability must be refused"
  grep -qi "pair first" "$TEST_DIR/err" || log_fail "TEST-003: the refusal must say 'pair first': $(err)"
  grep -q "cap-one" "$TEST_DIR/err" || log_fail "TEST-003: the refusal must name the capability to do first"
  write_doc cap-one change implementing
  [ "$(run gate --ref maint-one --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-003: maintenance must pass once the capability is implementing: $(err)"
  # a pair the ROADMAP marks done refuses both halves, whatever the docs say
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-one\n    maintenance: maint-one\n    status: done\n' > "$TEST_DIR/pairdone.yaml"
  write_doc cap-one change draft
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/pairdone.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-003: a pair marked done in the roadmap must refuse its capability"
  grep -qi "already marked done" "$TEST_DIR/err" || log_fail "TEST-003: the refusal must say the pair is marked done: $(err)"
  # CORRECTED (Spec-AC-29, TDD run 10): this used to assert "a capability on
  # the roadmap always passes, regardless of anything" — that WAS the
  # CHANGE-0184 defect (the gate admitted any on-roadmap capability, not only
  # the next one). Sequential admission means pair 2's capability is refused
  # while pair 1 is unfinished; TEST-565 in this suite covers the full ranking
  # matrix (first-pair admission, later-pair refusal, in-flight, override).
  [ "$(run gate --ref cap-two --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-003: pair 2's capability must be refused while pair 1 is unfinished (Spec-AC-29)"
  grep -qi "cap-one" "$TEST_DIR/err" || log_fail "TEST-003: the refusal must name pair 1's capability cap-one as ahead: $(err)"
  log_pass "pair first: refused, then allowed; a later pair's capability is refused until pair 1 is done (TEST-003, corrected under Spec-AC-29)"
}

# --- TEST-004 (Spec-AC-04): off-roadmap fix goes to the backlog ---------------
test_004_off_roadmap_fix() {
  log_info "Test: an off-roadmap fix is refused with the backlog remedy; blocks: admits it only for a real roadmap ref (TEST-004)..."
  write_roadmap planned; write_doc cap-one change draft
  write_doc some-fix issue draft
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-004: an off-roadmap issue-type ride must be refused"
  grep -qi "file it to the backlog" "$TEST_DIR/err" || log_fail "TEST-004: the refusal must say 'file it to the backlog': $(err)"
  grep -q "follow-ups.mjs add" "$TEST_DIR/err" || log_fail "TEST-004: the refusal must name the follow-ups command"
  write_doc some-fix issue draft "blocks: cap-one"
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-004: blocks: <roadmap ref> must admit the fix: $(err)"
  write_doc cap-one change done; write_doc some-fix issue draft "blocks: cap-one"
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-004: blocks: naming a DONE roadmap ref must be refused (nothing left to block)"
  grep -qi "already done" "$TEST_DIR/err" || log_fail "TEST-004: the refusal must say the blocked ref is done: $(err)"
  write_doc cap-one change draft
  write_doc some-fix issue draft "blocks: not-on-roadmap"
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-004: blocks: naming an unknown ref must be refused"
  grep -q "not-on-roadmap" "$TEST_DIR/err" || log_fail "TEST-004: the refusal must name the unknown ref"
  # slug-word detection when the intake is a change: 'fix' / 'guard' / 'harness' in the slug
  write_doc harness-guard-tweak change draft
  [ "$(run gate --ref harness-guard-tweak --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-harness-guard-tweak.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-004: a change whose slug says guard/harness is maintenance and must be refused off-roadmap"
  grep -qi "is maintenance and not on the roadmap" "$TEST_DIR/err" || log_fail "TEST-004: the slug-word refusal must give the maintenance reason: $(err)"
  log_pass "off-roadmap fix refused with remedy; blocks: works only for a real roadmap ref (TEST-004)"
}

# --- TEST-005 (Spec-AC-05): fail closed ---------------------------------------
test_005_fail_closed() {
  log_info "Test: missing/invalid roadmap and a done ref are refused, never passed (TEST-005)..."
  write_doc cap-one change draft
  # TEST-1201 (Spec-AC-01): an ABSENT roadmap admits (the file is the posture switch)
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/nope.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-1201: an absent roadmap must admit (exit 0): $(err)"
  grep -q "ADMIT cap-one — roadmap absent" "$TEST_DIR/out" || log_fail "TEST-1201: stdout must carry 'ADMIT cap-one — roadmap absent': $(out)"
  grep -q "not consulted" "$TEST_DIR/out" || log_fail "TEST-1201: stdout must say 'not consulted': $(out)"
  printf 'this: is\n  - not: the shape\n' > "$TEST_DIR/junk.yaml"
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/junk.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-005: an invalid roadmap must refuse"
  grep -q "closed roadmap shape" "$TEST_DIR/err" || log_fail "TEST-005: the invalid-roadmap refusal must name the parse reason: $(err)"
  write_roadmap planned; write_doc cap-one change done
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-005: a done ref must be refused as done"
  grep -qi "done" "$TEST_DIR/err" || log_fail "TEST-005: the refusal must say the ref is done"
  log_pass "fail closed on missing/invalid roadmap and on a done ref (TEST-005)"
}

# --- TEST-1202 (Spec-AC-01): the absent admit is side-effect free -------------
test_1202_absent_admit_is_side_effect_free() {
  log_info "Test: an absent-roadmap admit with --override and --events writes no roadmap and no events file, one stdout line (TEST-1202)..."
  write_doc cap-one change draft
  local rc=0
  rc="$(run gate --ref cap-one --roadmap "$TEST_DIR/s1202/roadmap.yaml" --docs "$TEST_DIR/docs" --events "$TEST_DIR/s1202/events.jsonl" --override "owner: nothing to override")" || true
  [ "$rc" = "0" ] || log_fail "TEST-1202: absent roadmap with --override must admit: $(err)"
  [ ! -e "$TEST_DIR/s1202/roadmap.yaml" ] || log_fail "TEST-1202: the roadmap path must not be created"
  [ ! -e "$TEST_DIR/s1202/events.jsonl" ] || log_fail "TEST-1202: no events file may be created for an absent-roadmap admit"
  [ ! -e "$TEST_DIR/s1202" ] || log_fail "TEST-1202: no directory may be created for an absent-roadmap admit"
  local n; n="$(wc -l < "$TEST_DIR/out" | tr -d ' ')"
  [ "$n" = "1" ] || log_fail "TEST-1202: stdout must be exactly one line, got $n: $(out)"
  if grep -q '?' "$TEST_DIR/out"; then log_fail "TEST-1202: the admit line must carry no question mark"; fi
  log_pass "absent admit creates nothing and prints one line (TEST-1202)"
}

# --- TEST-1203 (Spec-AC-02): present-but-invalid roadmap still refuses --------
test_1203_malformed_and_empty_refuse() {
  log_info "Test: a malformed and an empty roadmap file each refuse (exit 1, REFUSED) (TEST-1203)..."
  write_doc cap-one change draft
  printf 'this: is\n  - not: the shape\n' > "$TEST_DIR/bad1203.yaml"
  : > "$TEST_DIR/empty1203.yaml"
  local f rc
  for f in bad1203 empty1203; do
    rc="$(run gate --ref cap-one --roadmap "$TEST_DIR/$f.yaml" --docs "$TEST_DIR/docs")" || true
    [ "$rc" = "1" ] || log_fail "TEST-1203: $f must refuse with exit 1, got $rc"
    grep -q "REFUSED" "$TEST_DIR/err" || log_fail "TEST-1203: $f refusal must say REFUSED: $(err)"
  done
  log_pass "malformed and empty roadmap files refuse (TEST-1203)"
}

# --- TEST-1204 (Spec-AC-02): a directory at the roadmap path refuses ----------
test_1204_directory_refuses() {
  log_info "Test: a directory at the roadmap path refuses as not readable (TEST-1204)..."
  write_doc cap-one change draft
  mkdir -p "$TEST_DIR/dir1204.yaml"
  local rc
  rc="$(run gate --ref cap-one --roadmap "$TEST_DIR/dir1204.yaml" --docs "$TEST_DIR/docs")" || true
  [ "$rc" = "1" ] || log_fail "TEST-1204: a directory roadmap must refuse with exit 1, got $rc"
  grep -q "REFUSED" "$TEST_DIR/err" || log_fail "TEST-1204: must say REFUSED: $(err)"
  grep -q "roadmap not readable" "$TEST_DIR/err" || log_fail "TEST-1204: must say 'roadmap not readable': $(err)"
  log_pass "directory at the roadmap path refuses (TEST-1204)"
}

# --- TEST-1217 (Spec-AC-02, Codex P1 on PR #416): a roadmap path that -------
# exists but cannot be stat-ed (ELOOP self-symlink; EACCES unsearchable parent)
# is PRESENT-unreadable, never "absent": existsSync() is false for both, so the
# absent branch must stat and refuse. Root ignores directory modes, so the
# EACCES arm records a skip there instead of a vacuous pass; the ELOOP arm
# runs everywhere.
test_1217_unstatable_roadmap_refuses() {
  log_info "Test: an unstat-able roadmap path (ELOOP, EACCES) refuses as not readable, never admits as absent (TEST-1217)..."
  write_doc cap-one change draft
  local rc loop="$TEST_DIR/loop1217.yaml"
  ln -s "$loop" "$loop"
  rc="$(run gate --ref cap-one --roadmap "$loop" --docs "$TEST_DIR/docs")" || true
  [ "$rc" = "1" ] || log_fail "TEST-1217 (ELOOP): must refuse with exit 1, got $rc: $(out) $(err)"
  grep -q "REFUSED" "$TEST_DIR/err" || log_fail "TEST-1217 (ELOOP): must say REFUSED: $(err)"
  grep -q "roadmap not readable" "$TEST_DIR/err" || log_fail "TEST-1217 (ELOOP): must say 'roadmap not readable': $(err)"
  grep -q "roadmap absent" "$TEST_DIR/out" && log_fail "TEST-1217 (ELOOP): must never print the absent admit line: $(out)"
  if [ "$(id -u)" = "0" ]; then
    log_info "TEST-1217 (EACCES): running as root — directory modes are not enforced, arm skipped (not a pass)"
  else
    local locked="$TEST_DIR/locked1217"
    mkdir -p "$locked"
    printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-one\n    status: planned\n' > "$locked/roadmap.yaml"
    chmod 000 "$locked"
    rc="$(run gate --ref cap-one --roadmap "$locked/roadmap.yaml" --docs "$TEST_DIR/docs")" || true
    chmod 755 "$locked"
    [ "$rc" = "1" ] || log_fail "TEST-1217 (EACCES): must refuse with exit 1, got $rc: $(out) $(err)"
    grep -q "roadmap not readable" "$TEST_DIR/err" || log_fail "TEST-1217 (EACCES): must say 'roadmap not readable': $(err)"
    grep -q "roadmap absent" "$TEST_DIR/out" && log_fail "TEST-1217 (EACCES): must never print the absent admit line: $(out)"
  fi
  log_pass "unstat-able roadmap refuses, never admits as absent (TEST-1217)"
}

# --- TEST-1205 (Spec-AC-02): validate and next keep their absent behavior -----
test_1205_validate_next_unchanged_on_absent() {
  log_info "Test: validate on an absent path exits 2 and next on an absent path exits 1 (TEST-1205)..."
  local rc
  rc="$(run validate --roadmap "$TEST_DIR/nope1205.yaml")" || true
  [ "$rc" = "2" ] || log_fail "TEST-1205: validate on an absent roadmap must exit 2, got $rc"
  rc="$(run next --roadmap "$TEST_DIR/nope1205.yaml" --docs "$TEST_DIR/docs")" || true
  [ "$rc" = "1" ] || log_fail "TEST-1205: next on an absent roadmap must exit 1, got $rc"
  log_pass "validate and next unchanged on an absent roadmap (TEST-1205)"
}

# --- TEST-1206 (Spec-AC-03): usage checks run before the absent admit ---------
test_1206_usage_checks_before_absent() {
  log_info "Test: with an absent roadmap, missing/non-slug --ref and an empty --override are usage errors (TEST-1206)..."
  write_doc cap-one change draft
  local rc
  rc="$(run gate --roadmap "$TEST_DIR/nope1206.yaml" --docs "$TEST_DIR/docs")" || true
  [ "$rc" = "2" ] || log_fail "TEST-1206: missing --ref must exit 2, got $rc"
  rc="$(run gate --ref "NOT A SLUG" --roadmap "$TEST_DIR/nope1206.yaml" --docs "$TEST_DIR/docs")" || true
  [ "$rc" = "2" ] || log_fail "TEST-1206: a non-slug --ref must exit 2, got $rc"
  rc="$(run gate --ref cap-one --roadmap "$TEST_DIR/nope1206.yaml" --docs "$TEST_DIR/docs" --override " ")" || true
  [ "$rc" = "2" ] || log_fail "TEST-1206: an empty --override reason must exit 2, got $rc"
  log_pass "usage errors precede the absent-roadmap admit (TEST-1206)"
}

# --- TEST-1208 (Spec-AC-05): default roadmap path keeps the strict gate -------
test_1208_default_roadmap_refuses_off_roadmap() {
  log_info "Test: with no --roadmap flag the shipped roadmap refuses an off-roadmap maintenance ref (TEST-1208)..."
  write_doc zz-offroadmap-fix issue draft
  local rc
  rc="$(run gate --ref zz-offroadmap-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-zz-offroadmap-fix.md" --docs "$TEST_DIR/docs" --events "$TEST_DIR/events1208.jsonl")" || true
  # The shipped roadmap is read on the default path either way; what it then
  # decides follows its own budget posture (CHANGE-0201: the budget is opt-in).
  if grep -q '^budget:' "$SHIPPED"; then
    [ "$rc" = "1" ] || log_fail "TEST-1208: the shipped roadmap carries a budget, so it must refuse an off-roadmap fix with exit 1, got $rc: $(out) $(err)"
    grep -q "REFUSED" "$TEST_DIR/err" || log_fail "TEST-1208: must say REFUSED: $(err)"
  else
    [ "$rc" = "0" ] || log_fail "TEST-1208: the shipped roadmap carries no budget, so it must admit an off-roadmap fix, got $rc: $(out) $(err)"
    grep -q "no maintenance budget" "$TEST_DIR/out" "$TEST_DIR/err" || log_fail "TEST-1208: the admission must come from the shipped roadmap's budget posture: $(out) $(err)"
  fi
  log_pass "default roadmap path still governs (TEST-1208)"
}

# --- TEST-1209 (Spec-AC-06): header and AGENTS rule 4 state the posture switch
test_1209_header_and_rule4_state_the_switch() {
  log_info "Test: the ride-select header and AGENTS rule 4 name the roadmap file as the switch (TEST-1209)..."
  head -n 20 "$ENGINE" > "$TEST_DIR/hdr1209.txt"
  grep -qi "absent" "$TEST_DIR/hdr1209.txt" || log_fail "TEST-1209: header must say an absent roadmap admits"
  grep -q "not consulted" "$TEST_DIR/hdr1209.txt" || log_fail "TEST-1209: header must say 'not consulted'"
  grep -qi "refuse" "$TEST_DIR/hdr1209.txt" || log_fail "TEST-1209: header must say a present invalid roadmap refuses"
  if grep -qF 'never "no roadmap, anything goes"' "$TEST_DIR/hdr1209.txt"; then log_fail "TEST-1209: header must drop the old anything-goes sentence"; fi
  awk '/^### Operator contract/{f=1;next} /^### |^## /{if(f)exit} f' "$PROJECT_ROOT/.aai/AGENTS.md" > "$TEST_DIR/contract1209.txt"
  awk '/^4\. \*\*/{f=1;print;next} /^5\. \*\*/{f=0} f' "$TEST_DIR/contract1209.txt" > "$TEST_DIR/rule4-1209.txt"
  [ -s "$TEST_DIR/rule4-1209.txt" ] || log_fail "TEST-1209: rule 4 not found in the operator contract"
  grep -q 'docs/ai/roadmap.yaml' "$TEST_DIR/rule4-1209.txt" || log_fail "TEST-1209: rule 4 must name docs/ai/roadmap.yaml"
  grep -q 'absent' "$TEST_DIR/rule4-1209.txt" || log_fail "TEST-1209: rule 4 must say 'absent'"
  grep -q 'not consulted' "$TEST_DIR/rule4-1209.txt" || log_fail "TEST-1209: rule 4 must say 'not consulted'"
  local n; n="$(wc -l < "$TEST_DIR/contract1209.txt" | tr -d ' ')"
  [ "$n" -le 40 ] || log_fail "TEST-1209: the operator contract must stay at most 40 lines, got $n"
  log_pass "posture switch stated in header and rule 4; contract ≤40 lines (TEST-1209)"
}

# --- TEST-006 (Spec-AC-06): override is loud and logged -----------------------
test_006_override() {
  log_info "Test: --override passes and appends exactly one event with ref+reason; no reason is a usage error (TEST-006)..."
  write_roadmap planned; write_doc cap-one change draft; write_doc some-fix issue draft
  : > "$TEST_DIR/events.jsonl"
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs" --events "$TEST_DIR/events.jsonl" --override "owner: hotfix for a customer")" = "0" ] \
    || log_fail "TEST-006: override must pass: $(err)"
  local n; n="$(grep -c '"event":"ride_gate_override"' "$TEST_DIR/events.jsonl")"
  [ "$n" = "1" ] || log_fail "TEST-006: exactly one override event must be appended, got $n"
  grep -q '"ref":"some-fix"' "$TEST_DIR/events.jsonl" || log_fail "TEST-006: the event must carry the ref"
  grep -q 'hotfix for a customer' "$TEST_DIR/events.jsonl" || log_fail "TEST-006: the event must carry the reason"
  grep -qi "override" "$TEST_DIR/out" || grep -qi "override" "$TEST_DIR/err" || log_fail "TEST-006: the override must be printed, never silent"
  [ "$(run gate --ref some-fix --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs" --events "$TEST_DIR/events.jsonl" --override)" = "2" ] \
    || log_fail "TEST-006: --override without a reason must be a usage error (2)"
  [ "$(grep -c 'ride_gate_override' "$TEST_DIR/events.jsonl")" = "1" ] || log_fail "TEST-006: a refused override must not append an event"
  # --intake must be the intake OF --ref, or the gate would classify one ride by another's frontmatter
  write_doc other-thing change draft
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-other-thing.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "2" ] \
    || log_fail "TEST-006: --intake whose id is not --ref must be a usage error (2)"
  log_pass "override passes, is logged once with ref+reason, and needs a reason; intake/ref mismatch is usage (TEST-006)"
}

# --- TEST-007 (Spec-AC-07): canon wiring --------------------------------------
test_007_wiring() {
  log_info "Test: SHIP and LOOP invoke the gate, VALIDATION carries the two-round STOP, AGENTS carries the operator contract (TEST-007)..."
  grep -q 'ride-select.mjs gate' "$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md" || log_fail "TEST-007: SKILL_SHIP must invoke ride-select.mjs gate"
  grep -q 'ride-select.mjs gate' "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md" || log_fail "TEST-007: SKILL_LOOP must invoke ride-select.mjs gate"
  # anchored on tokens that sit on one line; the canon sentence wraps
  grep -q 'TWO ROUNDS MAX' "$PROJECT_ROOT/.aai/VALIDATION.prompt.md" || log_fail "TEST-007: VALIDATION c2 must carry the TWO ROUNDS MAX stop"
  grep -q 'never a fourth round' "$PROJECT_ROOT/.aai/VALIDATION.prompt.md" || log_fail "TEST-007: VALIDATION c2 must forbid a fourth round"
  grep -q '^### Operator contract' "$PROJECT_ROOT/.aai/AGENTS.md" || log_fail "TEST-007: AGENTS.md must carry '### Operator contract'"
  awk '/^### Operator contract/{f=1;next} /^### |^## /{if(f)exit} f' "$PROJECT_ROOT/.aai/AGENTS.md" > "$TEST_DIR/contract.txt"
  local n; n="$(wc -l < "$TEST_DIR/contract.txt" | tr -d ' ')"
  [ "$n" -le 40 ] || log_fail "TEST-007: the operator contract must be at most 40 lines, got $n"
  for k in "without asking" "menu" "two" "1:1"; do grep -qi -- "$k" "$TEST_DIR/contract.txt" || log_fail "TEST-007: the operator contract must state the rule about '$k'"; done
  log_pass "canon wiring present: gate in SHIP and LOOP, two-round STOP, operator contract ≤40 lines (TEST-007)"
}

# --- TEST-565 (Spec-AC-29): sequential admission -------------------------
test_565_gate_admits_only_the_next_pair() {
  log_info "Test: gate admits only the first unfinished pair; an in-flight ref and blocks: stay unaffected; override still one-shot (TEST-565)..."
  write_roadmap3 planned planned planned
  write_doc cap-a change draft; write_doc cap-b change draft; write_doc cap-c change draft
  # nothing started: pair 1 admitted, pairs 2/3 refused naming pair 1's capability
  [ "$(run gate --ref cap-a --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: pair 1's capability must be admitted: $(err)"
  [ "$(run gate --ref cap-b --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-565: pair 2's capability must be refused while pair 1 is unfinished"
  grep -q "cap-a" "$TEST_DIR/err" || log_fail "TEST-565: pair 2's refusal must name pair 1's capability cap-a: $(err)"
  [ "$(run gate --ref cap-c --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-565: pair 3's capability must be refused while pair 1 is unfinished"
  grep -q "cap-a" "$TEST_DIR/err" || log_fail "TEST-565: pair 3's refusal must name pair 1's capability cap-a: $(err)"

  # pair 1 capability implementing: its maintenance is admitted, the capability
  # itself stays admitted (in flight), pair 2 stays refused. maint-a's own
  # document must exist too (Amendment 17: gate requires the REF IT ADMITS
  # to resolve to a document, capability or maintenance alike — the same
  # authority validate uses, never a second copy of that resolution).
  write_doc cap-a change implementing
  write_doc maint-a change draft
  [ "$(run gate --ref maint-a --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: pair 1's maintenance must be admitted once its capability is implementing: $(err)"
  [ "$(run gate --ref cap-a --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: an implementing capability must stay admitted: $(err)"
  [ "$(run gate --ref cap-b --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-565: pair 2 must still be refused while pair 1 is not done"

  # pair 1 done (roadmap-level): pair 2's capability is now admitted, pair 3
  # refused naming pair 2
  write_roadmap3 done planned planned
  [ "$(run gate --ref cap-b --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: pair 2's capability must be admitted once pair 1 is done: $(err)"
  [ "$(run gate --ref cap-c --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-565: pair 3 must be refused while pair 2 is unfinished"
  grep -q "cap-b" "$TEST_DIR/err" || log_fail "TEST-565: pair 3's refusal must name pair 2's capability cap-b: $(err)"

  # AC-004: an implementing ref in a later, non-first pair stays admitted as in flight
  write_doc cap-c change implementing
  [ "$(run gate --ref cap-c --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: an implementing ref in a non-first pair must stay admitted (in flight): $(err)"
  grep -qi "in flight" "$TEST_DIR/out" || log_fail "TEST-565: the in-flight admission must say so: $(out)"
  write_doc cap-c change draft

  # AC-005: blocks: naming a not-first roadmap ref is admitted unchanged
  write_doc some-fix issue draft "blocks: cap-c"
  [ "$(run gate --ref some-fix --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-some-fix.md" --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-565: blocks: naming a not-first roadmap ref must still admit: $(err)"

  # AC-007: --override stays one-shot and logged, even against the new ranking refusal
  : > "$TEST_DIR/events565.jsonl"
  [ "$(run gate --ref cap-c --roadmap "$TEST_DIR/roadmap3.yaml" --docs "$TEST_DIR/docs" --events "$TEST_DIR/events565.jsonl" --override "owner: out of order for a customer")" = "0" ] \
    || log_fail "TEST-565: --override must admit a ranking refusal: $(err)"
  local n; n="$(grep -c '"event":"ride_gate_override"' "$TEST_DIR/events565.jsonl")"
  [ "$n" = "1" ] || log_fail "TEST-565: exactly one override event must be appended, got $n"

  # shipped roadmap: pair 7 (close-ceremony-sweep) closed with its real
  # PR/commit (Spec-AC-10, spec-close-ceremony-sweep) makes pair 8
  # the FIRST UNFINISHED pair's capability is admitted by ranking (same
  # property as the pair-1/2 arm above, re-pointed at the live file instead of
  # a fixture). This assertion used to name a pair by INDEX and went stale on
  # every close: it named pair 7, then pair 8, each time after the gate had
  # started correctly refusing the finished one. It now DERIVES the ref from
  # the shipped roadmap, so completing a pair moves the target instead of
  # breaking the test — a maintenance tax two rides paid before anyone read
  # the pattern.
  local first_unfinished
  first_unfinished="$(awk '/^  - capability:/ { cap=$3 } /^    status:/ { if ($2 != "done" && cap != "") { print cap; exit } }' "$SHIPPED")"
  # The derivation above fixed "the target moves on every close". It did not
  # fix "the list runs out": completing the last pair of the last wave leaves
  # NO unfinished pair, and the shipped roadmap reached that state when wave 3
  # closed (canon-is-a-build-artifact, PR #395). An exhausted roadmap is a
  # legitimate state, not a broken fixture, so this arm asserts the behaviour
  # of whichever state the shipped file is actually in — and never log_skip,
  # which is exit 42 and would void the whole suite.
  if [ -n "$first_unfinished" ]; then
    [ "$(run gate --ref "$first_unfinished" --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" = "0" ] \
      || log_fail "TEST-565: shipped roadmap: the first unfinished pair's capability ($first_unfinished) must be admitted: $(err)"
  else
    # Every pair done. `next` must SAY so rather than name a ride, and the
    # gate must still refuse — both a finished capability and a name that is
    # only a wave-2 candidate. A gate that admitted either here would be
    # handing out rides off a roadmap with nothing left on it.
    local done_cap
    done_cap="$(awk '/^  - capability:/ { cap=$3 } /^    status:/ { if ($2 == "done" && cap != "") { last=cap } } END { print last }' "$SHIPPED")"
    [ -n "$done_cap" ] || log_fail "TEST-565: exhausted roadmap: no done pair found either — the file is not a roadmap"
    [ "$(run gate --ref "$done_cap" --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" != "0" ] \
      || log_fail "TEST-565: exhausted roadmap: a finished capability ($done_cap) must still be refused: $(err)"
    grep -qi "already done" "$TEST_DIR/err" \
      || log_fail "TEST-565: exhausted roadmap: the refusal must say the capability is already done: $(err)"
    [ "$(run gate --ref no-such-capability-anywhere --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" != "0" ] \
      || log_fail "TEST-565: exhausted roadmap: an off-roadmap ref must still be refused: $(err)"
    run next --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs" >/dev/null 2>&1
    grep -qi "complete" "$TEST_DIR/out" \
      || log_fail "TEST-565: exhausted roadmap: next must report the wave complete, got: $(cat "$TEST_DIR/out")"
    grep -qF "$done_cap" "$TEST_DIR/out" \
      && log_fail "TEST-565: exhausted roadmap: next must not name a finished capability ($done_cap) as the next ride: $(cat "$TEST_DIR/out")"
  fi
  log_pass "gate admits only the first unfinished pair; in-flight and blocks: unaffected; override still one-shot logged (TEST-565)"
}

# --- TEST-566 (Spec-AC-29): validate refuses an unresolvable started ref --
test_566_validate_refuses_unknown_refs() {
  log_info "Test: validate refuses a STARTED pair's ref with no matching document id, naming the slug and its pair; a still-planned pair is exempt; the live roadmap still passes (TEST-566)..."
  write_doc cap-one change draft
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-one\n    maintenance: no-such-doc-slug\n    status: active\n' > "$TEST_DIR/typo.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/typo.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-566: an active pair naming a non-existent doc id must refuse"
  grep -q "no-such-doc-slug" "$TEST_DIR/err" || log_fail "TEST-566: the refusal must name the unknown ref: $(err)"
  grep -q "pair 1" "$TEST_DIR/err" || log_fail "TEST-566: the refusal must name the pair: $(err)"
  # a STILL-PLANNED pair naming an unfiled slug is exempt (named ahead of its
  # own intake is legitimate — it has not started yet)
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-one\n    maintenance: not-yet-intaken\n    status: planned\n' > "$TEST_DIR/planned-ahead.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/planned-ahead.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-566: a still-planned pair naming an unfiled ref must NOT refuse: $(err)"
  # the live roadmap validates clean (every active/done pair resolves)
  [ "$(run validate --roadmap "$SHIPPED")" = "0" ] || log_fail "TEST-566: the shipped roadmap must still validate: $(err)"
  # Spec-AC-29's own text ("SHALL refuse a roadmap ref that matches no
  # document id") is proven load-bearing on the LIVE roadmap, not just on a
  # synthetic fixture: without the still-planned exemption, the SAME live
  # roadmap must refuse (proving the exemption is genuinely exercised by
  # real data, not a carve-out nothing ever needs), and the started-pair
  # half is proven non-vacuous the same way (disclosed Amendment 16, B5).
  local nx_engine="$TEST_DIR/ride-select-no-exemption.mjs"
  sed "s/if (pr.status === 'planned') continue;//" "$ENGINE" > "$nx_engine"
  local nx_rc; nx_rc="$(node "$nx_engine" validate --roadmap "$SHIPPED" > "$TEST_DIR/nx.out" 2> "$TEST_DIR/nx.err"; echo $?)"
  [ "$nx_rc" != "0" ] \
    || log_fail "TEST-566: removing the still-planned exemption must make the LIVE roadmap refuse (a real undocumented planned slug exists) — got 0: $(cat "$TEST_DIR/nx.out")"
  log_pass "validate refuses a started pair's unknown ref, exempts a still-planned one (exercised for real on the live roadmap, not vacuously), live roadmap unaffected (TEST-566)"
}

# --- TEST-535 (spec-close-ceremony-sweep Spec-AC-10): the live roadmap's
# pair 7 (mutation-gate-for-tests / unrecorded-spec-amendment-is-invisible,
# M5) reads status done now that its maintenance half (CHANGE-0181) closed
# with a real PR/commit, and the live roadmap still validates. Pair 7 sitting
# at status: active (both docs terminal, the roadmap simply never told) is
# what let ride-select.mjs gate ADMIT close-ceremony-sweep's own pair 8 ahead
# of an unfinished earlier pair under the pre-fix reading (M5) -- flipping it
# is this AC's whole content; `validate` itself only checks that a
# started pair's refs resolve to real documents, so it stays green either
# way and is asserted here only per the row's own text, not as the property
# this test actually proves.
test_535_roadmap_pair_seven_done() {
  log_info "TEST-535: roadmap pair 7 (mutation-gate-for-tests / unrecorded-spec-amendment-is-invisible) reads status done, and ride-select.mjs validate passes over the live file..."
  local block cap maint status
  block="$(awk '
    /^  - capability:/ { n++ }
    n==7 { print }
    n==8 { exit }
  ' "$SHIPPED")"
  [ -n "$block" ] || log_fail "TEST-535: docs/ai/roadmap.yaml has no 7th pair block"
  cap="$(printf '%s\n' "$block" | awk -F': ' '/^  - capability:/{print $2; exit}')"
  maint="$(printf '%s\n' "$block" | awk -F': ' '/^    maintenance:/{print $2; exit}')"
  status="$(printf '%s\n' "$block" | awk -F': ' '/^    status:/{print $2; exit}')"
  [ "$cap" = "mutation-gate-for-tests" ] \
    || log_fail "TEST-535: pair 7's capability must be mutation-gate-for-tests, got '$cap'"
  [ "$maint" = "unrecorded-spec-amendment-is-invisible" ] \
    || log_fail "TEST-535: pair 7's maintenance must be unrecorded-spec-amendment-is-invisible, got '$maint'"
  [ "$status" = "done" ] \
    || log_fail "TEST-535: pair 7 status must be done, got '$status'"
  [ "$(run validate --roadmap "$SHIPPED")" = "0" ] \
    || log_fail "TEST-535: ride-select.mjs validate must pass over the live roadmap: $(err)"
  log_pass "TEST-535: roadmap pair 7 reads done, live roadmap validates"
}

# --- TEST-583 (Spec-AC-29, Amendment 17, R6 closed) — gate refuses a ref
# that matches no document, on the SAME authority validate uses -----------
test_583_gate_refuses_undocumented_ref() {
  log_info "Test: gate refuses a first-unfinished roadmap ref (capability OR maintenance) that matches no document, naming the ref and the missing doc; admits once the document exists (TEST-583)..."
  # Dedicated slugs (cap-t583/maint-t583), never used by an earlier test in
  # this suite's SHARED $TEST_DIR — reusing write_roadmap's cap-one/maint-one
  # would collide with docs those earlier tests already wrote there.
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-t583\n    maintenance: maint-t583\n    status: planned\n' > "$TEST_DIR/roadmap583.yaml"
  # Arm A: the CAPABILITY ref has no document at all (typo'd-but-internally-
  # consistent slug) — gate must refuse, not admit "a roadmap capability".
  [ "$(run gate --ref cap-t583 --roadmap "$TEST_DIR/roadmap583.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-583: an undocumented capability ref must NOT be admitted: $(out)"
  grep -qF "cap-t583" "$TEST_DIR/err" || log_fail "TEST-583: the refusal must name the ref cap-t583: $(err)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-583: the refusal must name the missing document: $(err)"
  # Arm B: same fixture, the capability's document now exists — gate admits.
  write_doc cap-t583 change draft
  [ "$(run gate --ref cap-t583 --roadmap "$TEST_DIR/roadmap583.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-583: a documented capability ref must be admitted once its doc exists: $(err)"
  grep -qF "a roadmap capability" "$TEST_DIR/out" || log_fail "TEST-583: the admission must read 'a roadmap capability': $(out)"
  # Arm C: the capability has STARTED (implementing) but the MAINTENANCE
  # ref itself has no document — gate must refuse the maintenance ref too,
  # not just check the capability's own status.
  write_doc cap-t583 change implementing
  [ "$(run gate --ref maint-t583 --roadmap "$TEST_DIR/roadmap583.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-583: an undocumented maintenance ref must NOT be admitted even though its capability started: $(out)"
  grep -qF "maint-t583" "$TEST_DIR/err" || log_fail "TEST-583: the refusal must name the ref maint-t583: $(err)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-583: the refusal must name the missing document: $(err)"
  # Arm D: same fixture, the maintenance document now exists — gate admits.
  write_doc maint-t583 change draft
  [ "$(run gate --ref maint-t583 --roadmap "$TEST_DIR/roadmap583.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-583: a documented maintenance ref must be admitted once its doc exists: $(err)"
  grep -qF "the maintenance half of a pair" "$TEST_DIR/out" || log_fail "TEST-583: the admission must read the maintenance-half reason: $(out)"
  # Control: the live roadmap is unaffected by this check (every ref gate
  # can currently reach is either the live pair 8 capability, which HAS a
  # document, or refused earlier for ranking — B5/R6's own measurement).
  # Like TEST-565's live arm, this used to name the admissible pair by index
  # and went stale on every close. It now derives it from the shipped roadmap.
  local live_admissible
  live_admissible="$(awk '/^  - capability:/ { cap=$3 } /^    status:/ { if ($2 != "done" && cap != "") { print cap; exit } }' "$SHIPPED")"
  # Same exhaustion as TEST-565's live arm: with wave 3 closed there is no
  # unfinished pair left to admit. The control's POINT is that the fixture
  # arms above did not disturb the live file, so when nothing is admissible
  # it asserts the live refusal instead — never log_skip (exit 42 voids the
  # suite) and never a silent pass.
  if [ -n "$live_admissible" ]; then
    [ "$(run gate --ref "$live_admissible" --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" = "0" ] \
      || log_fail "TEST-583: the live roadmap's own admissible ref ($live_admissible) must still be admitted: $(err)"
  else
    [ "$(run gate --ref maint-t583 --roadmap "$SHIPPED" --docs "$PROJECT_ROOT/docs")" != "0" ] \
      || log_fail "TEST-583: the fixture ref maint-t583 must not be admissible against the LIVE roadmap: $(err)"
    # With a budget the live gate refuses an off-roadmap ref; without one
    # (CHANGE-0201) roadmap order no longer refuses it and the refusal comes
    # from the missing document instead. Either way it must be refused.
    grep -qiE "not on the roadmap|no document resolves" "$TEST_DIR/err" \
      || log_fail "TEST-583: the live refusal must say the fixture ref is off the roadmap or has no document: $(err)"
  fi
  log_pass "TEST-583: gate refuses an undocumented roadmap ref (capability or maintenance), naming the ref and the missing document, and admits once the document exists; live roadmap unaffected"
}

# --- TEST-588 (Spec-AC-29, validation-round2 NB-3) — --intake must resolve
# to a PARSED intake document, not merely a readable file --------------------
test_588_gate_intake_requires_a_real_document() {
  log_info "Test: gate --intake refuses a readable file that is not a parseable intake document (no frontmatter, no --- fence, no id, or an id with no recognized type); admits a real one (TEST-588)..."
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-t588\n    maintenance: maint-t588\n    status: planned\n' > "$TEST_DIR/roadmap588.yaml"

  # Arm A (NB-3): a readable file with no frontmatter at all must NOT admit.
  printf 'not frontmatter, just junk text\n' > "$TEST_DIR/junk588.txt"
  [ "$(run gate --ref cap-t588 --intake "$TEST_DIR/junk588.txt" --roadmap "$TEST_DIR/roadmap588.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-588: gate --intake junk588.txt (no frontmatter) must NOT be admitted: $(out)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-588: the refusal must name the missing document: $(err)"

  # Arm B: a readable file WITH frontmatter but no `id:` line — still not a
  # document (the pre-fix code's own id-mismatch check never even fired here).
  printf -- '---\ntype: change\nstatus: draft\n---\n\n# no id\n' > "$TEST_DIR/noid588.txt"
  [ "$(run gate --ref cap-t588 --intake "$TEST_DIR/noid588.txt" --roadmap "$TEST_DIR/roadmap588.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-588: gate --intake noid588.txt (frontmatter, no id) must NOT be admitted: $(out)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-588: the no-id refusal must name the missing document: $(err)"

  # Arm C: a readable file with an id but a type OUTSIDE the corpus type map
  # — still not a document.
  printf -- '---\nid: cap-t588\ntype: not-a-real-type\nstatus: draft\n---\n\n# cap-t588\n' > "$TEST_DIR/badtype588.txt"
  [ "$(run gate --ref cap-t588 --intake "$TEST_DIR/badtype588.txt" --roadmap "$TEST_DIR/roadmap588.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-588: gate --intake badtype588.txt (unrecognized type) must NOT be admitted: $(out)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-588: the bad-type refusal must name the missing document: $(err)"

  # Arm D (validation-round3 D2): bare id:/type: lines with NO --- fence at
  # all, both values otherwise valid (a real id, a recognized type) — must
  # still NOT admit. "Parses as frontmatter" is not the same property as
  # "carries an id and a known type"; a fallback ad hoc line scan that only
  # checks the latter would admit this file. parseFrontmatter requires the
  # opening `---` fence before it looks at any key, so this must be refused
  # on the fence, not merely on a missing id or type.
  printf 'id: cap-t588\ntype: change\nstatus: draft\n\n# cap-t588\n' > "$TEST_DIR/nofence588.txt"
  [ "$(run gate --ref cap-t588 --intake "$TEST_DIR/nofence588.txt" --roadmap "$TEST_DIR/roadmap588.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-588: gate --intake nofence588.txt (id/type lines, no --- fence) must NOT be admitted: $(out)"
  grep -qi "no document resolves" "$TEST_DIR/err" || log_fail "TEST-588: the no-fence refusal must name the missing document: $(err)"

  # Control: a genuine intake document (frontmatter, id, recognized type) IS admitted.
  write_doc cap-t588 change draft
  [ "$(run gate --ref cap-t588 --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-cap-t588.md" --roadmap "$TEST_DIR/roadmap588.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-588: control -- a real intake document must still be admitted: $(err)"
  grep -qF "a roadmap capability" "$TEST_DIR/out" || log_fail "TEST-588: the control admission must read 'a roadmap capability': $(out)"

  log_pass "TEST-588: gate --intake refuses a readable-but-unparseable file (no frontmatter, no --- fence, no id, or an unrecognized type), and admits a real intake document"
}

# --- TEST-715 (Spec-AC-01, D2): maintenance becomes optional ------------------
test_715_validate_unbound_maintenance_slot() {
  log_info "Test: validate accepts a two-pair fixture whose last pair carries no maintenance line (TEST-715)..."
  cat > "$TEST_DIR/roadmap715.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t715-a
    maintenance: maint-t715-a
    status: planned
  - capability: cap-t715-b
    status: planned
YAML
  [ "$(run validate --roadmap "$TEST_DIR/roadmap715.yaml")" = "0" ] \
    || log_fail "TEST-715: a pair with no maintenance line must still validate: $(err)"
  grep -qF 'roadmap OK: 2 pair(s), 0 wave-2 item(s)' "$TEST_DIR/out" \
    || log_fail "TEST-715: the summary must count both pairs, got: $(out)"
  log_pass "validate accepts a capability-only pair with no maintenance line (TEST-715)"
}

# --- TEST-716 (Spec-AC-01, D2): the doc-existence check is skipped for an ----
# unbound slot on an active (non-planned) pair --------------------------------
test_716_validate_skips_unbound_doc_check() {
  log_info "Test: validate skips the document-existence check for an unbound maintenance slot on an active pair (TEST-716)..."
  cat > "$TEST_DIR/roadmap716.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t716
    status: active
YAML
  write_doc cap-t716 change implementing
  [ "$(run validate --roadmap "$TEST_DIR/roadmap716.yaml" --docs "$TEST_DIR/docs")" = "0" ] \
    || log_fail "TEST-716: an active pair with a documented capability and an unbound maintenance slot must validate: $(err)"
  log_pass "validate skips the document check for an unbound maintenance slot on an active pair (TEST-716)"
}

# --- TEST-717 (Spec-AC-01, S2 seam): nothing-left-behind over a --------------
# capability-only pair — pinned, no change owed in nothing-left-behind.mjs ----
test_717_nlb_seam_unbound_maintenance() {
  log_info "Test: nothing-left-behind over a capability-only roadmap pair exits 0 and reports no paired maintenance half (TEST-717)..."
  local NLB="$PROJECT_ROOT/.aai/scripts/nothing-left-behind.mjs"
  local NLBROOT="$TEST_DIR/nlb717"
  rm -rf "$NLBROOT"
  mkdir -p "$NLBROOT/docs/ai" "$NLBROOT/docs/issues"
  cat > "$NLBROOT/docs/ai/roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: nlb717-cap
    status: done
YAML
  printf -- '---\nid: nlb717-cap\ntype: change\nstatus: done\nlinks:\n  pr: []\n---\n\n# nlb717-cap\n' \
    > "$NLBROOT/docs/issues/CHANGE-DRAFT-nlb717-cap.md"
  # A second, unrelated in-flight doc — present so a mutated readRoadmapPairs
  # that stops requiring `pair.maintenance` has somewhere spurious to match
  # (the seam this row pins), while the UNMUTATED code must ignore it.
  printf -- '---\nid: nlb717-other\ntype: change\nstatus: draft\nlinks:\n  pr: []\n---\n\n# nlb717-other\n' \
    > "$NLBROOT/docs/issues/CHANGE-DRAFT-nlb717-other.md"
  ( cd "$NLBROOT" && git init -q && git config user.email nlb717@example.com && git config user.name nlb717 && git add -A && git commit -q -m "feat: nlb717-cap ships" ) \
    || log_fail "TEST-717: fixture git init/commit must succeed (a CI runner has no default git identity): $(git -C "$NLBROOT" status --porcelain)"
  local out2 rc2
  out2="$(node "$NLB" --ref nlb717-cap --root "$NLBROOT" --json)"; rc2=$?
  [ "$rc2" = "0" ] || log_fail "TEST-717: nothing-left-behind must exit 0 over a capability-only pair: $out2"
  assert_payload_contains "$out2" '"docs_open":0' "TEST-717: docs_open must be 0 (no paired maintenance half reported)"
  assert_payload_not_contains "$out2" 'paired maintenance half' "TEST-717: a capability-only pair must never report a paired maintenance half"
  log_pass "nothing-left-behind reports no paired maintenance half for a capability-only roadmap pair (TEST-717)"
}

# --- TEST-718 (Spec-AC-02): shipped roadmap regression proof -----------------
test_718_validate_shipped_regression() {
  log_info "Test: validate over the shipped docs/ai/roadmap.yaml still prints the identical summary after the relaxation (TEST-718)..."
  [ "$(run validate --roadmap "$SHIPPED")" = "0" ] || log_fail "TEST-718: the shipped roadmap must still validate: $(err)"
  [ "$(out)" = "roadmap OK: 13 pair(s), 4 wave-2 item(s)" ] \
    || log_fail "TEST-718: the summary line must be byte-identical, got: $(out)"
  log_pass "the shipped roadmap still validates with the identical summary line (TEST-718)"
}

# --- TEST-719 (Spec-AC-03, D4): next proposes a bind, never a null ref -------
test_719_next_proposes_bind() {
  log_info "Test: next on a started capability with an unbound maintenance slot returns action bind, never a null ref (TEST-719)..."
  cat > "$TEST_DIR/roadmap719.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t719
    status: active
YAML
  write_doc cap-t719 change implementing
  [ "$(run next --roadmap "$TEST_DIR/roadmap719.yaml" --docs "$TEST_DIR/docs" --json)" = "0" ] \
    || log_fail "TEST-719: next must exit 0: $(err)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" || log_fail "TEST-719: the JSON action field must be bind, got: $(out)"
  grep -qF '"capability":"cap-t719"' "$TEST_DIR/out" || log_fail "TEST-719: the JSON capability field must name cap-t719, got: $(out)"
  grep -qF '"ref":null' "$TEST_DIR/out" && log_fail "TEST-719: next must never emit a null ref, got: $(out)"
  log_pass "next proposes a bind for a started capability with an unbound maintenance slot, never a null ref (TEST-719)"
}

# --- TEST-720 (Spec-AC-03, D13): the bind action names the runnable command --
test_720_next_bind_names_command() {
  log_info "Test: the bind action names the capability slug and the runnable roadmap-propose.mjs bind command (TEST-720)..."
  cat > "$TEST_DIR/roadmap720.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t720
    status: active
YAML
  write_doc cap-t720 change implementing
  [ "$(run next --roadmap "$TEST_DIR/roadmap720.yaml" --docs "$TEST_DIR/docs" --json)" = "0" ] \
    || log_fail "TEST-720: next must exit 0: $(err)"
  grep -qF 'roadmap-propose.mjs bind' "$TEST_DIR/out" \
    || log_fail "TEST-720: the command field must name roadmap-propose.mjs bind, got: $(out)"
  grep -qF 'cap-t720' "$TEST_DIR/out" || log_fail "TEST-720: the command must name the capability cap-t720, got: $(out)"
  log_pass "the bind action names the runnable roadmap-propose.mjs bind command (TEST-720)"
}

# --- TEST-721 (Spec-AC-04, D5): an exhausted roadmap offers the harvest ------
test_721_next_offers_harvest_when_exhausted() {
  log_info "Test: next on an exhausted roadmap emits harvest_command alongside the wave-2 list (TEST-721)..."
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-t721\n    maintenance: maint-t721\n    status: done\nwave_2:\n  - later-t721\n' \
    > "$TEST_DIR/roadmap721.yaml"
  [ "$(run next --roadmap "$TEST_DIR/roadmap721.yaml" --docs "$TEST_DIR/docs" --json)" = "0" ] \
    || log_fail "TEST-721: next must exit 0 on an exhausted roadmap: $(err)"
  grep -qF 'harvest_command' "$TEST_DIR/out" || log_fail "TEST-721: the JSON must carry a harvest_command field, got: $(out)"
  grep -qF 'roadmap-propose.mjs harvest --direction' "$TEST_DIR/out" \
    || log_fail "TEST-721: the harvest_command must name roadmap-propose.mjs harvest --direction, got: $(out)"
  grep -qF 'later-t721' "$TEST_DIR/out" || log_fail "TEST-721: the wave-2 list must still be present, got: $(out)"
  log_pass "an exhausted roadmap offers the harvest command alongside the wave-2 list (TEST-721)"
}

# --- TEST-722 (Spec-AC-05, D3): the off-roadmap maintenance refusal names ----
# the bind command as well as the backlog command -----------------------------
test_722_gate_refusal_names_bind() {
  log_info "Test: the off-roadmap maintenance refusal exits 1 and names both the backlog and the bind command (TEST-722)..."
  write_roadmap planned
  [ "$(run gate --ref some-flake-fix-t722 --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] \
    || log_fail "TEST-722: an off-roadmap maintenance ref must still be refused: $(out)"
  grep -qF 'follow-ups.mjs add' "$TEST_DIR/err" || log_fail "TEST-722: the refusal must still name the backlog command: $(err)"
  grep -qF 'roadmap-propose.mjs bind' "$TEST_DIR/err" || log_fail "TEST-722: the refusal must also name the bind command: $(err)"
  log_pass "the off-roadmap maintenance refusal names both the backlog and the bind command, and stays exit 1 (TEST-722)"
}

# =============================================================================
# roadmap-propose.mjs harvest (Spec-AC-06..11) — the harvest and the ranking.
# Every candidate must print its source and all four ranking components
# (Spec-AC-06); Spec-AC-07..10 are MOVEMENT proofs, never a "a list was
# produced" control (spec Implementation strategy).
# =============================================================================

# --- TEST-723 (Spec-AC-06): every candidate prints source + all four ---------
# ranking components ----------------------------------------------------------
test_723_harvest_prints_ranking_components() {
  log_info "Test: harvest --json emits source, label, direction, direction_tokens, observations, blocks_in and age_days on every candidate (TEST-723)..."
  local D="$TEST_DIR/p723docs"
  propose_write_doc "$D" cap-t723 change draft
  [ "$(run_propose harvest --direction "cap t723 direction sentence" --roadmap "$TEST_DIR/p723-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p723-ledger.jsonl" --spool "$TEST_DIR/p723-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-723: harvest must exit 0: $(perr)"
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const c = j.candidates.find((x) => x.id === "cap-t723");
    if (!c) { console.error("candidate cap-t723 missing"); process.exit(1); }
    const need = ["source", "label", "direction", "direction_tokens", "observations", "blocks_in", "age_days"];
    for (const k of need) { if (c[k] === undefined || c[k] === null) { console.error("missing field " + k); process.exit(1); } }
  ' "$TEST_DIR/pout" || log_fail "TEST-723: every candidate must carry source/label/direction/direction_tokens/observations/blocks_in/age_days: $(pout)"
  log_pass "harvest prints all four ranking components plus source and label on every candidate (TEST-723)"
}

# --- TEST-724 (Spec-AC-06): intake source is capability-typed drafts only ----
test_724_harvest_intake_capability_types_only() {
  log_info "Test: harvest draws intake candidates only from draft docs whose type is in the capability set (TEST-724)..."
  local D="$TEST_DIR/p724docs"
  propose_write_doc "$D" cap-t724-change change draft
  propose_write_doc "$D" cap-t724-issue issue draft
  propose_write_doc "$D" cap-t724-done change done
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p724-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p724-ledger.jsonl" --spool "$TEST_DIR/p724-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-724: harvest must exit 0: $(perr)"
  grep -qF '"id":"cap-t724-change"' "$TEST_DIR/pout" || log_fail "TEST-724: a draft change-type doc must be harvested: $(pout)"
  grep -qF '"id":"cap-t724-issue"' "$TEST_DIR/pout" && log_fail "TEST-724: an issue-type doc must NOT be harvested: $(pout)"
  grep -qF '"id":"cap-t724-done"' "$TEST_DIR/pout" && log_fail "TEST-724: a done (non-draft) doc must NOT be harvested: $(pout)"
  log_pass "harvest draws intake candidates only from draft docs of a capability type (TEST-724)"
}

# --- TEST-725 (Spec-AC-06): wave_2 excludes already-paired slugs -------------
test_725_harvest_wave2_excludes_paired() {
  log_info "Test: harvest draws wave_2 slugs that are not already pairs (TEST-725)..."
  cat > "$TEST_DIR/p725-roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t725-paired
    maintenance: maint-t725-paired
    status: planned
wave_2:
  - cap-t725-paired
  - cap-t725-free
YAML
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p725-roadmap.yaml" --docs "$TEST_DIR/p725docs" --ledger "$TEST_DIR/p725-ledger.jsonl" --spool "$TEST_DIR/p725-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-725: harvest must exit 0: $(perr)"
  grep -qF '"id":"cap-t725-free"' "$TEST_DIR/pout" || log_fail "TEST-725: an un-paired wave_2 slug must be harvested: $(pout)"
  grep -qF '"id":"cap-t725-paired"' "$TEST_DIR/pout" && log_fail "TEST-725: a wave_2 slug already paired must NOT be harvested: $(pout)"
  log_pass "harvest draws only wave_2 slugs that are not already a pair (TEST-725)"
}

# --- TEST-726 (Spec-AC-07): MOVEMENT — direction sentence swaps the top ------
# candidate and changes the matching candidate's own direction count. Both
# fixture candidates carry a SINGULAR noun in their id (option / menu); both
# directions below use the ordinary PLURAL form of that noun ("options" /
# "menus") and never the candidate's own exact token — an owner writing a
# natural sentence, not the slug, is the whole premise of Spec-AC-07 (measured
# live-corpus defect: "decisions as menus" scored 0 against a candidate
# labelled "decision-menu-options-parser" under exact-token matching). A
# regression to exact equality reddens this test (see mutation below).
test_726_harvest_direction_movement() {
  log_info "Test: MOVEMENT — two directions over one fixture swap the top candidate and change its direction count (TEST-726)..."
  local D="$TEST_DIR/p726docs"
  propose_write_doc "$D" cap-t726-option change draft
  propose_write_doc "$D" cap-t726-menu change draft
  local ROADMAP="$TEST_DIR/p726-roadmap.yaml" LEDGER="$TEST_DIR/p726-ledger.jsonl" SPOOL="$TEST_DIR/p726-spool.jsonl"
  [ "$(run_propose harvest --direction "align with the available options here" --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-726: first harvest must exit 0: $(perr)"
  [ "$(propose_top_id)" = "cap-t726-option" ] || log_fail "TEST-726: a sentence naming options (plural of the option candidate's own singular token) must rank it first, got $(propose_top_id): $(pout)"
  local menu_dir_1; menu_dir_1="$(propose_field cap-t726-menu direction)"
  [ "$(run_propose harvest --direction "align with the various menus here" --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-726: second harvest must exit 0: $(perr)"
  [ "$(propose_top_id)" = "cap-t726-menu" ] || log_fail "TEST-726: a sentence naming menus (plural of the menu candidate's own singular token) must rank it first, got $(propose_top_id): $(pout)"
  local menu_dir_2; menu_dir_2="$(propose_field cap-t726-menu direction)"
  [ "$menu_dir_1" != "$menu_dir_2" ] \
    || log_fail "TEST-726: menu's own direction count must differ between the two runs, got $menu_dir_1 both times"
  log_pass "changing the direction sentence rises the matching candidate and changes its direction count (TEST-726)"
}

# --- TEST-727 (Spec-AC-07): direction is the PRIMARY sort key ----------------
test_727_harvest_direction_is_primary_key() {
  log_info "Test: direction is the PRIMARY sort key — a lower-evidence candidate that matches the sentence outranks a higher-evidence one that does not (TEST-727)..."
  local D="$TEST_DIR/p727docs"
  propose_write_doc "$D" cap-t727-cache-speed change draft
  propose_write_doc "$D" cap-t727-search-relevance change draft
  local ROADMAP="$TEST_DIR/p727-roadmap.yaml" LEDGER="$TEST_DIR/p727-ledger.jsonl" SPOOL="$TEST_DIR/p727-spool.jsonl"
  : > "$LEDGER"
  node "$FOLLOWUPS" add --id fu-t727-probe --ref cap-t727-cache-speed --severity P2 --what "w" --why "y" --source "s" --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-727: adding the fixture follow-up must succeed"
  [ "$(run_propose harvest --direction "the team should improve search relevance next" --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-727: harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t727-cache-speed observations)" = "1" ] \
    || log_fail "TEST-727: cap-t727-cache-speed must show observations 1 from the fixture follow-up: $(pout)"
  [ "$(propose_field cap-t727-cache-speed direction)" = "0" ] \
    || log_fail "TEST-727: cap-t727-cache-speed must show direction 0 (the sentence names the OTHER candidate): $(pout)"
  local idx_evidence idx_direction
  idx_evidence="$(propose_index_of cap-t727-cache-speed)"
  idx_direction="$(propose_index_of cap-t727-search-relevance)"
  [ "$idx_direction" -lt "$idx_evidence" ] \
    || log_fail "TEST-727: the direction-matching candidate must outrank the higher-evidence, non-matching one (direction idx=$idx_direction, evidence idx=$idx_evidence): $(pout)"
  log_pass "direction outranks higher evidence on a non-matching candidate (TEST-727)"
}

# --- TEST-728 (Spec-AC-07): tokens under 4 characters never count ------------
test_728_harvest_tokenize_filters_short_tokens() {
  log_info "Test: tokens under 4 characters never count toward a direction match, even when not a stopword (TEST-728)..."
  local D="$TEST_DIR/p728docs"
  propose_write_doc "$D" cap-t728-ux change draft
  [ "$(run_propose harvest --direction "improve the ux now" --roadmap "$TEST_DIR/p728-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p728-ledger.jsonl" --spool "$TEST_DIR/p728-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-728: harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t728-ux direction)" = "0" ] \
    || log_fail "TEST-728: a short shared token (ux) below the 4-character floor must not count as a direction match, got: $(pout)"
  log_pass "tokens under 4 characters never count toward a direction match (TEST-728)"
}

# --- TEST-729 (Spec-AC-08): MOVEMENT — one open follow-up naming B raises ----
# its observations 0 to 1 and lowers its index --------------------------------
test_729_harvest_observations_movement() {
  log_info "Test: MOVEMENT — adding one open follow-up naming candidate B raises its observations 0 to 1 and lowers its index (TEST-729)..."
  local D="$TEST_DIR/p729docs"
  propose_write_doc "$D" cap-t729-aaa change draft
  propose_write_doc "$D" cap-t729-bbb change draft
  local ROADMAP="$TEST_DIR/p729-roadmap.yaml" LEDGER="$TEST_DIR/p729-ledger.jsonl" SPOOL="$TEST_DIR/p729-spool.jsonl"
  : > "$LEDGER"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-729: first harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t729-bbb observations)" = "0" ] || log_fail "TEST-729: cap-t729-bbb must start at observations 0: $(pout)"
  local idx_before; idx_before="$(propose_index_of cap-t729-bbb)"
  node "$FOLLOWUPS" add --id fu-rank-probe-729 --ref cap-t729-bbb --severity P2 --what "w" --why "y" --source "s" --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-729: adding the fixture follow-up must succeed"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-729: second harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t729-bbb observations)" = "1" ] || log_fail "TEST-729: cap-t729-bbb's observations must rise to 1, got: $(pout)"
  local idx_after; idx_after="$(propose_index_of cap-t729-bbb)"
  [ "$idx_after" -lt "$idx_before" ] \
    || log_fail "TEST-729: cap-t729-bbb must overtake its earlier tie (index before=$idx_before, after=$idx_after): $(pout)"
  log_pass "adding one open follow-up naming a candidate raises its observations and its rank (TEST-729)"
}

# --- TEST-730 (Spec-AC-08): a CLOSED follow-up does not raise observations --
test_730_harvest_closed_followup_ignored() {
  log_info "Test: a CLOSED follow-up naming candidate B does not raise its observations (TEST-730)..."
  local D="$TEST_DIR/p730docs"
  propose_write_doc "$D" cap-t730 change draft
  local ROADMAP="$TEST_DIR/p730-roadmap.yaml" LEDGER="$TEST_DIR/p730-ledger.jsonl" SPOOL="$TEST_DIR/p730-spool.jsonl"
  : > "$LEDGER"
  node "$FOLLOWUPS" add --id fu-t730-probe --ref cap-t730 --severity P2 --what "w" --why "y" --source "s" --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-730: adding the fixture follow-up must succeed"
  node "$FOLLOWUPS" close --id fu-t730-probe --resolved-by cap-t730 --source "sha:deadbeef" --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-730: closing the fixture follow-up must succeed"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-730: harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t730 observations)" = "0" ] \
    || log_fail "TEST-730: a closed follow-up must not count toward observations, got: $(pout)"
  log_pass "a closed follow-up naming a candidate does not raise its observations (TEST-730)"
}

# --- TEST-731 (Spec-AC-09): MOVEMENT — a non-terminal blocking document ------
# naming B raises its blocks_in 0 to 1 and lowers its index -------------------
test_731_harvest_blocks_in_movement() {
  log_info "Test: MOVEMENT — adding a non-terminal document with blocks naming B raises its blocks_in 0 to 1 and lowers its index (TEST-731)..."
  local D="$TEST_DIR/p731docs"
  propose_write_doc "$D" cap-t731-aaa change draft
  propose_write_doc "$D" cap-t731-bbb change draft
  local ROADMAP="$TEST_DIR/p731-roadmap.yaml" LEDGER="$TEST_DIR/p731-ledger.jsonl" SPOOL="$TEST_DIR/p731-spool.jsonl"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-731: first harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t731-bbb blocks_in)" = "0" ] || log_fail "TEST-731: cap-t731-bbb must start at blocks_in 0: $(pout)"
  local idx_before; idx_before="$(propose_index_of cap-t731-bbb)"
  propose_write_doc "$D" cap-t731-blocker issue draft "blocks: cap-t731-bbb"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-731: second harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t731-bbb blocks_in)" = "1" ] || log_fail "TEST-731: cap-t731-bbb's blocks_in must rise to 1, got: $(pout)"
  local idx_after; idx_after="$(propose_index_of cap-t731-bbb)"
  [ "$idx_after" -lt "$idx_before" ] \
    || log_fail "TEST-731: cap-t731-bbb must overtake its earlier tie on direction and observations (index before=$idx_before, after=$idx_after): $(pout)"
  log_pass "adding a non-terminal blocking document raises blocks_in and rank (TEST-731)"
}

# --- TEST-732 (Spec-AC-09): a TERMINAL blocking document does not raise ------
# blocks_in --------------------------------------------------------------------
test_732_harvest_terminal_blocker_ignored() {
  log_info "Test: a TERMINAL document blocking B does not raise its blocks_in (TEST-732)..."
  local D="$TEST_DIR/p732docs"
  propose_write_doc "$D" cap-t732 change draft
  propose_write_doc "$D" cap-t732-blocker issue done "blocks: cap-t732"
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p732-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p732-ledger.jsonl" --spool "$TEST_DIR/p732-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-732: harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t732 blocks_in)" = "0" ] \
    || log_fail "TEST-732: a blocking document whose OWN status is terminal (done) must not raise blocks_in, got: $(pout)"
  log_pass "a terminal (done) blocking document does not raise blocks_in (TEST-732)"
}

# --- TEST-733 (Spec-AC-10): MOVEMENT — tied on every earlier key, the -------
# older first-commit date ranks first -----------------------------------------
test_733_harvest_age_tiebreak() {
  log_info "Test: MOVEMENT — with every earlier key tied the older first-commit date ranks first (TEST-733)..."
  local D="$TEST_DIR/p733docs"
  mkdir -p "$D/issues"
  ( cd "$D" && git init -q && git config user.email t733@example.com && git config user.name t733 )
  propose_write_doc "$D" cap-t733-older change draft
  ( cd "$D" && git add -A && GIT_AUTHOR_DATE="2026-01-01T00:00:00" GIT_COMMITTER_DATE="2026-01-01T00:00:00" git commit -q -m older )
  propose_write_doc "$D" cap-t733-newer change draft
  ( cd "$D" && git add -A && GIT_AUTHOR_DATE="2026-06-01T00:00:00" GIT_COMMITTER_DATE="2026-06-01T00:00:00" git commit -q -m newer )
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p733-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p733-ledger.jsonl" --spool "$TEST_DIR/p733-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-733: harvest must exit 0: $(perr)"
  local age_older age_newer
  age_older="$(propose_field cap-t733-older age_days)"
  age_newer="$(propose_field cap-t733-newer age_days)"
  [ "$age_older" -gt "$age_newer" ] \
    || log_fail "TEST-733: the older candidate must report a larger age_days (older=$age_older, newer=$age_newer): $(pout)"
  local idx_older idx_newer
  idx_older="$(propose_index_of cap-t733-older)"
  idx_newer="$(propose_index_of cap-t733-newer)"
  [ "$idx_older" -lt "$idx_newer" ] \
    || log_fail "TEST-733: tied on every earlier key, the older candidate must rank first (older idx=$idx_older, newer idx=$idx_newer): $(pout)"
  log_pass "with every earlier key tied, the older first-commit date ranks first (TEST-733)"
}

# --- TEST-734 (Spec-AC-10): an untracked candidate reports age unknown ------
test_734_harvest_untracked_age_unknown() {
  log_info "Test: an untracked candidate reports age_days 0 and the literal note age unknown (TEST-734)..."
  local D="$TEST_DIR/p734docs"
  propose_write_doc "$D" cap-t734 change draft
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p734-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p734-ledger.jsonl" --spool "$TEST_DIR/p734-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-734: harvest must exit 0: $(perr)"
  [ "$(propose_field cap-t734 age_days)" = "0" ] || log_fail "TEST-734: an untracked candidate must report age_days 0, got: $(pout)"
  [ "$(propose_field cap-t734 age_note)" = '"age unknown"' ] \
    || log_fail "TEST-734: an untracked candidate must carry the literal note 'age unknown', got: $(pout)"
  log_pass "an untracked candidate reports age_days 0 and the note age unknown (TEST-734)"
}

# --- TEST-735 (Spec-AC-11): only review_candidate clusters become friction --
# candidates -------------------------------------------------------------------
test_735_harvest_friction_review_candidates_only() {
  log_info "Test: only review_candidate clusters become friction candidates (TEST-735)..."
  local SPOOL="$TEST_DIR/p735-spool.jsonl"
  cat > "$SPOOL" <<JSONL
{"schema_version":2,"harness":"claude-code","skill_id":"aai-tdd","skill_phase":"test-execution","failure_class":"deterministic_script_failure","fingerprint":"fp-t735-above","impact":"high","confidence":"high","reproducible":true}
{"schema_version":2,"harness":"claude-code","skill_id":"aai-other","skill_phase":"other-phase","failure_class":"stalled_progress","fingerprint":"fp-t735-below"}
JSONL
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p735-roadmap.yaml" --docs "$TEST_DIR/p735docs" --ledger "$TEST_DIR/p735-ledger.jsonl" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-735: harvest must exit 0: $(perr)"
  local n_friction
  n_friction="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.filter((c) => c.source === "friction").length));
  ' "$TEST_DIR/pout")"
  [ "$n_friction" = "1" ] || log_fail "TEST-735: exactly one review_candidate cluster must become a friction candidate, got $n_friction: $(pout)"
  grep -qF 'friction-aai-tdd-deterministic-script-failure' "$TEST_DIR/pout" \
    || log_fail "TEST-735: the surviving candidate must be labelled from the above-threshold row's skill_id and failure_class: $(pout)"
  log_pass "harvest contributes only review_candidate friction clusters (TEST-735)"
}

# --- TEST-736 (Spec-AC-11): the friction label never carries the raw --------
# fingerprint hash --------------------------------------------------------------
test_736_harvest_friction_label_never_hash() {
  log_info "Test: a friction label carries skill_id and failure_class and no v1 fingerprint hash appears in the output (TEST-736)..."
  local SPOOL="$TEST_DIR/p736-spool.jsonl"
  cat > "$SPOOL" <<JSONL
{"schema_version":2,"harness":"claude-code","skill_id":"aai-run-tests","skill_phase":"test-execution","failure_class":"deterministic_script_failure","fingerprint":"v1:abc123deadbeef","impact":"high","confidence":"high","reproducible":true}
JSONL
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p736-roadmap.yaml" --docs "$TEST_DIR/p736docs" --ledger "$TEST_DIR/p736-ledger.jsonl" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-736: harvest must exit 0: $(perr)"
  grep -qF 'friction-aai-run-tests-deterministic-script-failure' "$TEST_DIR/pout" \
    || log_fail "TEST-736: the friction candidate must be labelled from skill_id and failure_class, got: $(pout)"
  [ "$(/usr/bin/grep -c 'v1:' "$TEST_DIR/pout")" = "0" ] \
    || log_fail "TEST-736: no candidate label may contain the raw v1: fingerprint hash: $(pout)"
  log_pass "the friction label carries skill_id and failure_class, never the raw fingerprint (TEST-736)"
}

# --- TEST-737 (Spec-AC-11): an empty or absent spool degrades to a NOTE -----
test_737_harvest_empty_spool_note() {
  log_info "Test: an empty or absent spool yields zero friction candidates, exit 0 and one NOTE line (TEST-737)..."
  local SPOOL="$TEST_DIR/p737-spool-absent.jsonl"
  rm -f "$SPOOL"
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p737-roadmap.yaml" --docs "$TEST_DIR/p737docs" --ledger "$TEST_DIR/p737-ledger.jsonl" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-737: harvest over an absent spool must exit 0: $(perr)"
  grep -qF 'spool is empty' "$TEST_DIR/pout" || log_fail "TEST-737: the NOTE must say the spool is empty (or absent): $(pout)"
  local n_notes
  n_notes="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.notes.length));
  ' "$TEST_DIR/pout")"
  [ "$n_notes" = "1" ] || log_fail "TEST-737: exactly one NOTE must be printed for an absent spool, got $n_notes: $(pout)"
  local n_friction
  n_friction="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.filter((c) => c.source === "friction").length));
  ' "$TEST_DIR/pout")"
  [ "$n_friction" = "0" ] || log_fail "TEST-737: an absent spool must contribute zero friction candidates, got $n_friction: $(pout)"
  log_pass "an empty or absent friction spool yields zero candidates, exit 0, and one NOTE (TEST-737)"
}

# --- TEST-747 (Spec-AC-06): a duplicate id across two sources contributes ---
# exactly ONE candidate set member, naming every contributing source --------
# (measured live-corpus defect: decision-menu-options-parser printed twice,
# once [intake] from its own draft doc and once [wave_2] from the roadmap's
# wave_2 list, because nothing ever asked whether two sources named the SAME
# capability id).
test_747_harvest_dedupes_by_id() {
  log_info "Test: a candidate id reachable from both an intake draft and an unpaired wave_2 slug contributes exactly one candidate, naming both sources (TEST-747)..."
  local D="$TEST_DIR/p747docs"
  propose_write_doc "$D" cap-t747-both change draft
  cat > "$TEST_DIR/p747-roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t747-other
    maintenance: maint-t747-other
    status: planned
wave_2:
  - cap-t747-both
YAML
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p747-roadmap.yaml" --docs "$D" --ledger "$TEST_DIR/p747-ledger.jsonl" --spool "$TEST_DIR/p747-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-747: harvest must exit 0: $(perr)"
  local n_both
  n_both="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.filter((c) => c.id === "cap-t747-both").length));
  ' "$TEST_DIR/pout")"
  [ "$n_both" = "1" ] || log_fail "TEST-747: a candidate reachable from two sources must contribute exactly ONE row, got $n_both: $(pout)"
  local source
  source="$(propose_field cap-t747-both source)"
  [ "$source" = '"intake,wave_2"' ] \
    || log_fail "TEST-747: the merged candidate's source must name BOTH contributing sources, got $source: $(pout)"
  log_pass "a duplicate id across intake and wave_2 contributes exactly one candidate, naming both sources (TEST-747)"
}

# --- TEST-738 (Spec-AC-12): write appends planned capability-only pairs -----
test_738_write_appends_and_certifies() {
  log_info "Test: write appends planned capability-only pairs, leaves prior bytes identical, and the REAL validator accepts (TEST-738)..."
  local D="$TEST_DIR/p738docs"
  propose_write_doc "$D" cap-t738-existing change planned
  propose_write_doc "$D" cap-t738-new change draft
  local ROADMAP="$TEST_DIR/p738-roadmap.yaml"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t738-existing
    maintenance: maint-t738-existing
    status: planned
YAML
  cp "$ROADMAP" "$TEST_DIR/p738-roadmap.orig.yaml"
  [ "$(run_propose write --direction "cap t738 new direction" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p738-ledger.jsonl" --spool "$TEST_DIR/p738-spool.jsonl")" = "0" ] \
    || log_fail "TEST-738: write must exit 0: $(perr)"
  local n_orig
  n_orig="$(wc -l < "$TEST_DIR/p738-roadmap.orig.yaml" | tr -d ' ')"
  diff <(head -n "$n_orig" "$ROADMAP") "$TEST_DIR/p738-roadmap.orig.yaml" >/dev/null \
    || log_fail "TEST-738: every pre-existing byte must be unchanged (prefix diff)"
  local appended
  appended="$(tail -n +$((n_orig + 1)) "$ROADMAP")"
  assert_payload_contains "$appended" 'capability: cap-t738-new' \
    "TEST-738: the appended block must name the picked candidate"
  assert_payload_contains "$appended" 'status: planned' \
    "TEST-738: the appended pair must carry status: planned"
  assert_payload_not_contains "$appended" 'maintenance:' \
    "TEST-738: the appended block must carry no maintenance: line"
  [ "$(run validate --roadmap "$ROADMAP" --docs "$D")" = "0" ] \
    || log_fail "TEST-738: the REAL ride-select.mjs validate must accept the written roadmap: $(err)"
  log_pass "write appends a planned capability-only pair, prior bytes unchanged, real validator accepts (TEST-738)"
}

# --- TEST-739 (Spec-AC-12): certification spawns ride-select.mjs validate --
# as a REAL child process — proven by an argv-recording shim, never a
# test-owned parser or an in-process import.
test_739_write_certifies_via_real_child_process() {
  log_info "Test: certification spawns ride-select.mjs validate as a real child process, proven by an argv-recording shim (TEST-739)..."
  local COPY="$TEST_DIR/p739-scripts"
  rm -rf "$COPY"
  mkdir -p "$COPY"
  cp -R "$PROJECT_ROOT/.aai/scripts/." "$COPY/"
  cat > "$COPY/ride-select.mjs" <<'SHIM'
#!/usr/bin/env node
import fs from 'node:fs';
fs.writeFileSync(process.env.T739_ARGV_RECORDER, JSON.stringify(process.argv.slice(2)));
process.exit(0);
SHIM
  local D="$TEST_DIR/p739docs"
  propose_write_doc "$D" cap-t739 change draft
  local ROADMAP="$TEST_DIR/p739-roadmap.yaml"
  rm -f "$ROADMAP"
  local RECORDER="$TEST_DIR/p739-argv.json"
  rm -f "$RECORDER"
  T739_ARGV_RECORDER="$RECORDER" node "$COPY/roadmap-propose.mjs" write --direction "cap t739" --pick 1 \
    --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p739-ledger.jsonl" --spool "$TEST_DIR/p739-spool.jsonl" \
    > "$TEST_DIR/pout" 2> "$TEST_DIR/perr"
  local rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-739: write against the always-admitting shim must exit 0: rc=$rc $(perr)"
  [ -f "$RECORDER" ] || log_fail "TEST-739: the shim must have recorded an argv (certification never ran a child process)"
  local argv
  argv="$(cat "$RECORDER")"
  assert_payload_contains "$argv" '"validate"' "TEST-739: certification must invoke the shim with 'validate'"
  assert_payload_contains "$argv" '"--roadmap"' "TEST-739: certification must pass --roadmap"
  assert_payload_contains "$argv" "\"$ROADMAP\"" "TEST-739: certification must name the written roadmap path"
  log_pass "certification runs ride-select.mjs validate as a real child process (TEST-739)"
}

# --- TEST-740 (Spec-AC-13): a refused certification restores original bytes -
test_740_write_rollback_on_refused_certification() {
  log_info "Test: a refused certification restores the original bytes, exits 1 and prints the validator's own stderr (TEST-740)..."
  local COPY="$TEST_DIR/p740-scripts"
  rm -rf "$COPY"
  mkdir -p "$COPY"
  cp -R "$PROJECT_ROOT/.aai/scripts/." "$COPY/"
  cat > "$COPY/ride-select.mjs" <<'SHIM'
#!/usr/bin/env node
process.stderr.write('ride-select: REFUSED -- TEST-740 stub always refuses\n');
process.exit(1);
SHIM
  local D="$TEST_DIR/p740docs"
  propose_write_doc "$D" cap-t740 change draft
  local ROADMAP="$TEST_DIR/p740-roadmap.yaml"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t740-existing
    maintenance: maint-t740-existing
    status: planned
YAML
  cp "$ROADMAP" "$TEST_DIR/p740-roadmap.orig.yaml"
  node "$COPY/roadmap-propose.mjs" write --direction "cap t740" --pick 1 \
    --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p740-ledger.jsonl" --spool "$TEST_DIR/p740-spool.jsonl" \
    > "$TEST_DIR/pout" 2> "$TEST_DIR/perr"
  local rc=$?
  [ "$rc" = "1" ] || log_fail "TEST-740: a refused certification must exit 1, got $rc: $(perr)"
  cmp -s "$ROADMAP" "$TEST_DIR/p740-roadmap.orig.yaml" \
    || log_fail "TEST-740: the original bytes must be restored on a refused certification"
  grep -qF 'TEST-740 stub always refuses' "$TEST_DIR/perr" \
    || log_fail "TEST-740: stderr must carry the validator's own refusal text: $(cat "$TEST_DIR/perr")"
  log_pass "a refused certification restores the original bytes and reports the validator's refusal (TEST-740)"
}

# --- TEST-741 (Spec-AC-14): bind refuses a ref outside the backlog ----------
test_741_bind_refuses_unknown_ref() {
  log_info "Test: bind refuses a ref that is neither an open follow-up nor a resolvable document and writes nothing (TEST-741)..."
  local D="$TEST_DIR/p741docs"
  local ROADMAP="$TEST_DIR/p741-roadmap.yaml"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t741
    status: planned
YAML
  cp "$ROADMAP" "$TEST_DIR/p741-roadmap.orig.yaml"
  [ "$(run_propose bind --capability cap-t741 --ref nowhere-to-be-found --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p741-ledger.jsonl")" = "1" ] \
    || log_fail "TEST-741: bind with an unresolvable ref must exit 1: $(pout)"
  cmp -s "$ROADMAP" "$TEST_DIR/p741-roadmap.orig.yaml" || log_fail "TEST-741: bind must write nothing on refusal"
  log_pass "bind refuses a ref that is neither an open follow-up nor a resolvable document, and writes nothing (TEST-741)"
}

# --- TEST-742 (Spec-AC-14): bind adds exactly one maintenance line ----------
test_742_bind_adds_maintenance_line_and_certifies() {
  log_info "Test: bind adds exactly one maintenance line to the named pair, the real validator accepts, and a re-bind is refused (TEST-742)..."
  local D="$TEST_DIR/p742docs"
  mkdir -p "$D"
  local ROADMAP="$TEST_DIR/p742-roadmap.yaml" LEDGER="$TEST_DIR/p742-ledger.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t742
    status: planned
YAML
  : > "$LEDGER"
  node "$FOLLOWUPS" add --id fu-t742-probe --ref cap-t742 --severity P3 --what w --why y --source s --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-742: adding the fixture follow-up must succeed"
  [ "$(run_propose bind --capability cap-t742 --ref fu-t742-probe --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-742: bind with a valid open follow-up ref must exit 0: $(perr)"
  local n_maint
  n_maint="$(/usr/bin/grep -c '^    maintenance:' "$ROADMAP")"
  [ "$n_maint" = "1" ] || log_fail "TEST-742: exactly one maintenance: line must be added, got $n_maint"
  [ "$(run validate --roadmap "$ROADMAP" --docs "$D")" = "0" ] \
    || log_fail "TEST-742: the real validator must accept the bound roadmap: $(err)"
  node "$FOLLOWUPS" add --id fu-t742-second --ref cap-t742 --severity P3 --what w --why y --source s --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-742: adding the second fixture follow-up must succeed"
  [ "$(run_propose bind --capability cap-t742 --ref fu-t742-second --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "1" ] \
    || log_fail "TEST-742: a second bind on an already-bound pair must be refused: $(pout)"
  # The refusal must come from bind's OWN already-bound guard, not merely
  # from certify() catching a duplicate maintenance: line after the fact
  # (ride-select.mjs's closed-shape parser refuses two maintenance keys in
  # one pair regardless, which would otherwise mask this guard's removal).
  grep -qF 'already bound' "$TEST_DIR/perr" \
    || log_fail "TEST-742: the re-bind refusal must name the pair as already bound (bind's own guard, not certify's): $(perr)"
  n_maint="$(/usr/bin/grep -c '^    maintenance:' "$ROADMAP")"
  [ "$n_maint" = "1" ] || log_fail "TEST-742: the maintenance line count must stay at exactly 1 after a refused re-bind, got $n_maint"
  log_pass "bind adds exactly one maintenance line, the real validator accepts, and a re-bind is refused (TEST-742)"
}

# --- TEST-743 (Spec-AC-15): an absent roadmap and zero candidates leave -----
# no file behind
test_743_opt_out_leaves_no_file() {
  log_info "Test: an absent roadmap and zero harvested candidates leave no file behind (TEST-743)..."
  local D="$TEST_DIR/p743docs"
  mkdir -p "$D/issues"
  local ROADMAP="$TEST_DIR/p743-nonexistent/roadmap.yaml"
  rm -rf "$TEST_DIR/p743-nonexistent"
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p743-ledger.jsonl" --spool "$TEST_DIR/p743-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-743: harvest over an absent roadmap must exit 0: $(perr)"
  [ ! -e "$ROADMAP" ] || log_fail "TEST-743: harvest must create no roadmap file"
  local n_candidates
  n_candidates="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.length));
  ' "$TEST_DIR/pout")"
  [ "$n_candidates" = "0" ] || log_fail "TEST-743: an empty docs dir and absent roadmap must yield zero candidates, got $n_candidates"
  [ "$(run_propose write --direction "p743 direction" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p743-ledger.jsonl" --spool "$TEST_DIR/p743-spool.jsonl")" = "1" ] \
    || log_fail "TEST-743: write with zero harvested candidates must exit 1: $(pout)"
  grep -qF 'nothing harvested' "$TEST_DIR/perr" || log_fail "TEST-743: the refusal must say nothing harvested: $(perr)"
  [ ! -e "$ROADMAP" ] || log_fail "TEST-743: write with zero candidates must create no roadmap file"
  log_pass "an absent roadmap and zero harvested candidates leave no file behind (TEST-743)"
}

# --- TEST-744 (Spec-AC-15): no prompt or dispatch branch invokes -----------
# roadmap-propose automatically. The scan pattern below lives in its own
# assigned variable (never written out in this comment, so the recorded
# mutation's first — and only — match is the real assignment line, not a
# prose mention of it) so the mutation that flips the scan target to the
# WRONG, legitimately-wired name hits exactly this test's own assertion
# rather than one of the many unrelated occurrences of the harvester's name
# earlier in this suite file (e.g. the $PROPOSE path assignment) — a bare,
# unanchored rename would hit whichever occurs FIRST in the file, not this
# check.
test_744_no_automatic_invocation_site() {
  log_info "Test: no .aai prompt or orchestration-dispatch.mjs invokes roadmap-propose automatically (TEST-744)..."
  # Narrowed (roadmap-serves-downstream-projects D9, TEST-1330): the user-invoked
  # /aai-roadmap prompt is the ONE allowed site; everything else stays refused.
  local SCAN_PATTERN='roadmap-propose' ALLOWED="$PROJECT_ROOT/.aai/SKILL_ROADMAP.prompt.md"
  local hits f
  hits="$(/usr/bin/grep -rl "$SCAN_PATTERN" "$PROJECT_ROOT"/.aai/*.prompt.md "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" 2>/dev/null || true)"
  local others=""
  while IFS= read -r f; do [ -z "$f" ] || [ "$f" = "$ALLOWED" ] || others="$others $f"; done <<<"$hits"
  [ -z "$others" ] || log_fail "TEST-1330 (amends TEST-744): no .aai prompt except SKILL_ROADMAP.prompt.md, and not orchestration-dispatch.mjs, may name roadmap-propose, found:$others"
  # positive control: the allowlisted prompt really is a site (the allowance is not vacuous)
  /usr/bin/grep -q "$SCAN_PATTERN" "$ALLOWED" 2>/dev/null || log_fail "TEST-1330 (amends TEST-744): positive control — SKILL_ROADMAP.prompt.md must name roadmap-propose (harvest/write)"
  log_pass "only the user-invoked SKILL_ROADMAP prompt names roadmap-propose; no dispatch branch does (TEST-744)"
}

# === Remediation round (validation-round1.txt) ==============================

# --- TEST-748 (Spec-AC-06, Spec-AC-12): BLOCKING-1 — harvest prints stable ---
# 1-based row numbers, and write --pick N writes exactly the Nth-ranked
# candidate off that SAME ranking — never row 1 regardless of N (widened,
# multi-candidate fixture: TEST-738's single-candidate fixture could never
# exercise pick fidelity at all).
test_748_harvest_row_numbers_and_write_pick_fidelity() {
  log_info "Test: harvest prints 1-based row numbers and write --pick N writes exactly the Nth-ranked candidate (TEST-748)..."
  local D="$TEST_DIR/p748docs"
  propose_write_doc "$D" cap-t748-gamma change draft
  propose_write_doc "$D" cap-t748-beta change draft
  propose_write_doc "$D" cap-t748-alpha change draft
  local ROADMAP="$TEST_DIR/p748-roadmap.yaml" LEDGER="$TEST_DIR/p748-ledger.jsonl" SPOOL="$TEST_DIR/p748-spool.jsonl"
  : > "$LEDGER"
  local DIRECTION="the beta idea please"
  [ "$(run_propose harvest --direction "$DIRECTION" --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-748: harvest must exit 0: $(perr)"
  # Ranked order under this direction: beta (direction=1) first, then alpha
  # and gamma tied at direction=0, id-ASC ("cap-t748-alpha" < "cap-t748-gamma").
  [ "$(propose_field cap-t748-beta index)" = "1" ] || log_fail "TEST-748: cap-t748-beta must be row 1, got: $(pout)"
  [ "$(propose_field cap-t748-alpha index)" = "2" ] || log_fail "TEST-748: cap-t748-alpha must be row 2, got: $(pout)"
  [ "$(propose_field cap-t748-gamma index)" = "3" ] || log_fail "TEST-748: cap-t748-gamma must be row 3, got: $(pout)"
  # The TEXT rows must carry the same numbers, not just the JSON field.
  [ "$(run_propose harvest --direction "$DIRECTION" --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-748: text harvest must exit 0: $(perr)"
  grep -qE '^1\. cap-t748-beta ' "$TEST_DIR/pout" || log_fail "TEST-748: the text row for cap-t748-beta must be numbered 1: $(pout)"
  grep -qE '^2\. cap-t748-alpha ' "$TEST_DIR/pout" || log_fail "TEST-748: the text row for cap-t748-alpha must be numbered 2: $(pout)"
  grep -qE '^3\. cap-t748-gamma ' "$TEST_DIR/pout" || log_fail "TEST-748: the text row for cap-t748-gamma must be numbered 3: $(pout)"
  # write --pick 2 must write row 2 (alpha) — NOT row 1 (beta). A write that
  # recomputed a prefix (candidates.slice(0, picks.length)) instead of
  # indexing candidates[pick-1] would write beta here instead.
  local ROADMAP2="$TEST_DIR/p748-write-roadmap.yaml"
  [ "$(run_propose write --direction "$DIRECTION" --pick 2 --roadmap "$ROADMAP2" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-748: write --pick 2 must exit 0: $(perr)"
  /usr/bin/grep -q 'capability: cap-t748-alpha' "$ROADMAP2" \
    || log_fail "TEST-748: write --pick 2 must write the SECOND-ranked candidate (cap-t748-alpha): $(cat "$ROADMAP2")"
  /usr/bin/grep -q 'capability: cap-t748-beta' "$ROADMAP2" \
    && log_fail "TEST-748: write --pick 2 must NOT write the first-ranked candidate (cap-t748-beta): $(cat "$ROADMAP2")"
  /usr/bin/grep -q 'capability: cap-t748-gamma' "$ROADMAP2" \
    && log_fail "TEST-748: write --pick 2 must NOT write the third-ranked candidate (cap-t748-gamma): $(cat "$ROADMAP2")"
  log_pass "harvest prints stable row numbers and write --pick N writes exactly the Nth-ranked candidate (TEST-748)"
}

# --- TEST-749 (Spec-AC-12): BLOCKING-1 — write refuses (usage, exit 2) when --
# --direction is omitted, and writes nothing.
test_749_write_requires_direction() {
  log_info "Test: write refuses with a usage error when --direction is omitted, and writes nothing (TEST-749)..."
  local D="$TEST_DIR/p749docs"
  propose_write_doc "$D" cap-t749 change draft
  local ROADMAP="$TEST_DIR/p749-nonexistent/roadmap.yaml"
  rm -rf "$TEST_DIR/p749-nonexistent"
  [ "$(run_propose write --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p749-ledger.jsonl" --spool "$TEST_DIR/p749-spool.jsonl")" = "2" ] \
    || log_fail "TEST-749: write with no --direction must exit 2 (usage), got $(pout): $(perr)"
  grep -qF -- '--direction' "$TEST_DIR/perr" || log_fail "TEST-749: the usage refusal must name --direction: $(perr)"
  [ ! -e "$ROADMAP" ] || log_fail "TEST-749: write with no --direction must create no roadmap file"
  log_pass "write refuses with a usage error when --direction is omitted, and writes nothing (TEST-749)"
}

# --- TEST-750 (Spec-AC-12): BLOCKING-1 — the SENTENCE, not merely its --------
# presence, drives what write picks: the same --pick 1 writes a DIFFERENT
# candidate when --direction changes.
test_750_write_direction_value_drives_pick() {
  log_info "Test: the same --pick 1 writes a different candidate when --direction changes, proving write's ranking is driven by the sentence itself (TEST-750)..."
  local D="$TEST_DIR/p750docs"
  propose_write_doc "$D" cap-t750-gamma change draft
  propose_write_doc "$D" cap-t750-beta change draft
  propose_write_doc "$D" cap-t750-alpha change draft
  local LEDGER="$TEST_DIR/p750-ledger.jsonl" SPOOL="$TEST_DIR/p750-spool.jsonl"
  : > "$LEDGER"
  local ROADMAP_BETA="$TEST_DIR/p750-roadmap-beta.yaml"
  [ "$(run_propose write --direction "the beta idea please" --pick 1 --roadmap "$ROADMAP_BETA" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-750: write directed at beta must exit 0: $(perr)"
  /usr/bin/grep -q 'capability: cap-t750-beta' "$ROADMAP_BETA" \
    || log_fail "TEST-750: --direction naming beta with --pick 1 must write cap-t750-beta: $(cat "$ROADMAP_BETA")"
  local ROADMAP_GAMMA="$TEST_DIR/p750-roadmap-gamma.yaml"
  [ "$(run_propose write --direction "the gamma idea please" --pick 1 --roadmap "$ROADMAP_GAMMA" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-750: write directed at gamma must exit 0: $(perr)"
  /usr/bin/grep -q 'capability: cap-t750-gamma' "$ROADMAP_GAMMA" \
    || log_fail "TEST-750: --direction naming gamma with --pick 1 must write cap-t750-gamma: $(cat "$ROADMAP_GAMMA")"
  log_pass "the same --pick 1 writes a different candidate when --direction changes (TEST-750)"
}

# --- TEST-751 (Spec-AC-14): validation round 2 B1/B2 — bind refuses a ref ----
# that the ROADMAP already records as a capability (a `capability:` slot on
# ANY pair, not just the one being bound into — N14: a check narrowed to a
# single hardcoded capability name must not pass this), and still succeeds
# for a `type: change` ref that is not a roadmap capability — the 8-of-11
# MAJORITY shape on the shipped roadmap, which round 1's now-reverted
# doc-`type` check refused outright (B1).
test_751_bind_refuses_roadmap_capability_ref() {
  log_info "Test: bind refuses a ref that is already a roadmap capability (any pair, not just the one being bound), and still accepts a type:change ref that is not one (TEST-751)..."
  local D="$TEST_DIR/p751docs"
  local ROADMAP="$TEST_DIR/p751-roadmap.yaml" LEDGER="$TEST_DIR/p751-ledger.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t751-a
    status: planned
  - capability: cap-t751-b
    status: planned
  - capability: cap-t751-c
    status: planned
YAML
  cp "$ROADMAP" "$TEST_DIR/p751-roadmap.orig.yaml"
  : > "$LEDGER"
  # cap-t751-c must itself resolve to a document (D13's backlog check runs
  # FIRST) so the refusal below is proven to come from the roadmap-capability
  # check, not from "no document resolves".
  propose_write_doc "$D" cap-t751-c change draft
  [ "$(run_propose bind --capability cap-t751-a --ref cap-t751-c --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "1" ] \
    || log_fail "TEST-751: bind must refuse a ref that is already a roadmap capability (cap-t751-c, the THIRD pair's own capability — not cap-t751-a): $(pout)"
  grep -qF 'roadmap CAPABILITY' "$TEST_DIR/perr" || log_fail "TEST-751: the refusal must name the roadmap-capability mismatch: $(perr)"
  cmp -s "$ROADMAP" "$TEST_DIR/p751-roadmap.orig.yaml" || log_fail "TEST-751: bind must write nothing on a roadmap-capability ref refusal"
  propose_write_doc "$D" cap-t751-maintdoc change draft
  [ "$(run_propose bind --capability cap-t751-a --ref cap-t751-maintdoc --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-751: bind must accept a type:change ref that is NOT a roadmap capability (the 8-of-11 majority shape, B1): $(perr)"
  /usr/bin/grep -q '^    maintenance: cap-t751-maintdoc' "$ROADMAP" \
    || log_fail "TEST-751: the accepted type:change ref must be bound: $(cat "$ROADMAP")"
  log_pass "bind refuses a ref that is a roadmap capability on any pair, and accepts a type:change ref that is not one (TEST-751)"
}

# --- TEST-757 (Spec-AC-14): validation round 2 B2 — the doc-type denylist ---
# is GONE: a ref whose resolved document carries a type in NEITHER
# CAPABILITY_TYPES nor ride-select.mjs's MAINT_TYPES (measured live: 197 such
# ids — spec/product/release) is admitted when it is not a roadmap
# capability, on a stated reason (roadmap membership), never a silent type
# filter. Two different type values prove it is not a single-value carve-out.
test_757_bind_no_type_denylist() {
  log_info "Test: bind admits a spec-typed and a product-typed ref that are not roadmap capabilities — no type denylist survives (TEST-757)..."
  local D="$TEST_DIR/p757docs"
  local ROADMAP="$TEST_DIR/p757-roadmap.yaml" LEDGER="$TEST_DIR/p757-ledger.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t757-a
    status: planned
  - capability: cap-t757-b
    status: planned
YAML
  : > "$LEDGER"
  propose_write_doc "$D" cap-t757-specdoc spec current
  [ "$(run_propose bind --capability cap-t757-a --ref cap-t757-specdoc --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-757: bind must admit a spec-typed ref that is not a roadmap capability: $(perr)"
  propose_write_doc "$D" cap-t757-productdoc product current
  [ "$(run_propose bind --capability cap-t757-b --ref cap-t757-productdoc --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-757: bind must admit a product-typed ref that is not a roadmap capability: $(perr)"
  /usr/bin/grep -q '^    maintenance: cap-t757-specdoc' "$ROADMAP" \
    || log_fail "TEST-757: the spec-typed ref must be bound: $(cat "$ROADMAP")"
  /usr/bin/grep -q '^    maintenance: cap-t757-productdoc' "$ROADMAP" \
    || log_fail "TEST-757: the product-typed ref must be bound: $(cat "$ROADMAP")"
  log_pass "bind admits refs of types outside every denylist, on the roadmap-membership reason alone (TEST-757)"
}

# --- TEST-758 (Spec-AC-14): validation round 2 B1 finding — a ref already ---
# bound as another pair's maintenance half is refused: one ref cannot serve
# two capabilities under the 1:1 budget (the "decide and defend" addition the
# round 2 remediation brief asked for alongside the roadmap-capability check).
test_758_bind_refuses_ref_bound_elsewhere() {
  log_info "Test: bind refuses a ref already bound as another pair's maintenance half (TEST-758)..."
  local D="$TEST_DIR/p758docs"
  local ROADMAP="$TEST_DIR/p758-roadmap.yaml" LEDGER="$TEST_DIR/p758-ledger.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t758-a
    status: planned
  - capability: cap-t758-b
    status: planned
YAML
  : > "$LEDGER"
  propose_write_doc "$D" maint-t758-shared change draft
  [ "$(run_propose bind --capability cap-t758-a --ref maint-t758-shared --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-758: the first bind of the shared ref must succeed: $(perr)"
  cp "$ROADMAP" "$TEST_DIR/p758-roadmap.after-first-bind.yaml"
  [ "$(run_propose bind --capability cap-t758-b --ref maint-t758-shared --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "1" ] \
    || log_fail "TEST-758: binding the SAME ref into a second pair must be refused: $(pout)"
  grep -qF 'already bound as the maintenance half of' "$TEST_DIR/perr" \
    || log_fail "TEST-758: the refusal must name which pair the ref is already bound to: $(perr)"
  cmp -s "$ROADMAP" "$TEST_DIR/p758-roadmap.after-first-bind.yaml" \
    || log_fail "TEST-758: the refused second bind must write nothing: $(cat "$ROADMAP")"
  log_pass "bind refuses a ref already bound as another pair's maintenance half (TEST-758)"
}

# --- TEST-759 (Spec-AC-05, Spec-AC-14): validation round 2 NB-3 — the gate's --
# off-roadmap maintenance refusal advertises a bind command that must ACTUALLY
# succeed (round 1's type check made it always refuse for exactly the class
# F1's own repro used).
test_759_gate_bind_remedy_succeeds() {
  log_info "Test: the bind command the gate's maintenance refusal advertises actually succeeds (TEST-759, NB-3)..."
  local D="$TEST_DIR/p759docs"
  mkdir -p "$D"
  local ROADMAP="$TEST_DIR/p759-roadmap.yaml" LEDGER="$TEST_DIR/p759-ledger.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t759
    status: planned
YAML
  : > "$LEDGER"
  # A type:change intake whose SLUG carries a maintenance word (MAINT_WORDS)
  # — the gate classifies it as maintenance by REF, bind must classify it by
  # roadmap membership, and the two must agree.
  propose_write_doc "$D" a-guard-rail-view-of-spend-t759 change draft
  [ "$(run gate --ref a-guard-rail-view-of-spend-t759 --intake "$D/issues/CHANGE-DRAFT-a-guard-rail-view-of-spend-t759.md" --roadmap "$ROADMAP" --docs "$D")" = "1" ] \
    || log_fail "TEST-759: gate must refuse the off-roadmap maintenance ref: $(out)"
  grep -qF 'roadmap-propose.mjs bind' "$TEST_DIR/err" \
    || log_fail "TEST-759: the refusal must name the bind command: $(err)"
  [ "$(run_propose bind --capability cap-t759 --ref a-guard-rail-view-of-spend-t759 --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER")" = "0" ] \
    || log_fail "TEST-759: the bind command the gate advertises must actually succeed: $(perr)"
  log_pass "the gate's advertised bind command actually succeeds (TEST-759, NB-3)"
}

# --- TEST-760 (Spec-AC-03): validation round 2 NB-6 — next stops proposing --
# a maintenance ref that resolves to no document (a bind from an open
# follow-up id, D13's first arm): the OLD behaviour handed an autonomous loop
# a ref `gate` immediately refuses — a livelock, not merely an un-closeable
# pair (R7). `next` now proposes filing the intake instead.
test_760_next_stops_proposing_dead_ref() {
  log_info "Test: next never proposes a maintenance ref with no resolvable document — it proposes filing the intake instead (TEST-760, NB-6)..."
  cat > "$TEST_DIR/roadmap760.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t760
    maintenance: fu-t760-dead
    status: active
YAML
  write_doc cap-t760 change implementing
  [ "$(run next --roadmap "$TEST_DIR/roadmap760.yaml" --docs "$TEST_DIR/docs" --json)" = "0" ] \
    || log_fail "TEST-760: next must exit 0: $(err)"
  grep -qF '"next":"fu-t760-dead"' "$TEST_DIR/out" \
    && log_fail "TEST-760: next must never propose a maintenance ref with no resolvable document (the R7 livelock): $(out)"
  grep -qF '"action":"file-intake"' "$TEST_DIR/out" \
    || log_fail "TEST-760: next must propose filing the intake instead of the dead ref: $(out)"
  grep -qF 'fu-t760-dead' "$TEST_DIR/out" \
    || log_fail "TEST-760: the file-intake action must still name the ref that needs an intake: $(out)"
  [ "$(run gate --ref fu-t760-dead --roadmap "$TEST_DIR/roadmap760.yaml" --docs "$TEST_DIR/docs")" = "1" ] \
    || log_fail "TEST-760: gate must still refuse the dead ref (R7 unchanged): $(out)"
  grep -qF 'no document resolves' "$TEST_DIR/err" \
    || log_fail "TEST-760: gate's refusal reason must be unchanged: $(err)"
  log_pass "next stops proposing a maintenance ref nothing can resolve, and proposes filing its intake instead (TEST-760, NB-6)"
}

# --- TEST-752 (Spec-AC-12, D10 amendment): BLOCKING-3 — promoting a wave_2- --
# sourced pick removes its old wave_2 listing and the real validator accepts
# (the D10 amendment / removeWave2Entries, shipped in run 3 with no test of
# its own — validation round 1 F3).
test_752_write_promotes_wave2_slug_and_removes_it() {
  log_info "Test: write promoting a wave_2-sourced pick removes the slug from wave_2 and the real validator accepts (TEST-752)..."
  local D="$TEST_DIR/p752docs"
  mkdir -p "$D"
  local ROADMAP="$TEST_DIR/p752-roadmap.yaml" LEDGER="$TEST_DIR/p752-ledger.jsonl" SPOOL="$TEST_DIR/p752-spool.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t752-existing
    maintenance: maint-t752-existing
    status: planned
wave_2:
  - cap-t752-promote
YAML
  : > "$LEDGER"
  [ "$(run_propose write --direction "please promote t752 item" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-752: write promoting the wave_2 slug must exit 0: $(perr)"
  /usr/bin/grep -q 'capability: cap-t752-promote' "$ROADMAP" \
    || log_fail "TEST-752: the promoted slug must appear as a pair: $(cat "$ROADMAP")"
  /usr/bin/grep -qE '^  - cap-t752-promote$' "$ROADMAP" \
    && log_fail "TEST-752: the promoted slug's OLD wave_2 listing must be removed: $(cat "$ROADMAP")"
  [ "$(run validate --roadmap "$ROADMAP" --docs "$D")" = "0" ] \
    || log_fail "TEST-752: the real validator must accept the roadmap after promotion: $(err)"
  log_pass "write promoting a wave_2-sourced pick removes it from wave_2 and the real validator accepts (TEST-752)"
}

# --- TEST-761 (Spec-AC-12): validation round 2 NB-1/N15 — promoting a -------
# wave_2-sourced pick removes ONLY its own line; a mutation that deletes
# EVERY wave_2 row (not just the matching one) must redden this, which
# TEST-752's single-entry fixture could not (round 2 measured: against the
# shipped roadmap, one promotion emptied all four of the owner's deferred
# wave_2 items and `validate` still said OK).
test_761_promotion_leaves_other_wave2_entries() {
  log_info "Test: promoting one wave_2 slug leaves every OTHER wave_2 entry in place (TEST-761, N15)..."
  local D="$TEST_DIR/p761docs"
  mkdir -p "$D"
  local ROADMAP="$TEST_DIR/p761-roadmap.yaml" LEDGER="$TEST_DIR/p761-ledger.jsonl" SPOOL="$TEST_DIR/p761-spool.jsonl"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t761-existing
    maintenance: maint-t761-existing
    status: planned
wave_2:
  - cap-t761-promote
  - cap-t761-keep-one
  - cap-t761-keep-two
YAML
  : > "$LEDGER"
  [ "$(run_propose write --direction "please promote t761 item" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL")" = "0" ] \
    || log_fail "TEST-761: write promoting the wave_2 slug must exit 0: $(perr)"
  /usr/bin/grep -qE '^  - cap-t761-promote$' "$ROADMAP" \
    && log_fail "TEST-761: the promoted slug's OLD wave_2 listing must be removed: $(cat "$ROADMAP")"
  /usr/bin/grep -qE '^  - cap-t761-keep-one$' "$ROADMAP" \
    || log_fail "TEST-761: an UNTOUCHED wave_2 entry must survive the promotion (N15 — deleting every wave_2 row must redden this): $(cat "$ROADMAP")"
  /usr/bin/grep -qE '^  - cap-t761-keep-two$' "$ROADMAP" \
    || log_fail "TEST-761: a SECOND untouched wave_2 entry must also survive the promotion: $(cat "$ROADMAP")"
  [ "$(run validate --roadmap "$ROADMAP" --docs "$D")" = "0" ] \
    || log_fail "TEST-761: the real validator must accept the roadmap after promotion: $(err)"
  log_pass "promoting one wave_2 slug leaves every other wave_2 entry in place (TEST-761, N15)"
}

# --- TEST-753 (Spec-AC-06): F4 — harvest excludes an intake draft whose id ---
# is already a roadmap pair (the steady state after the first write).
test_753_harvest_excludes_already_paired_intake() {
  log_info "Test: harvest excludes an intake draft whose id is already a roadmap capability pair (TEST-753)..."
  local D="$TEST_DIR/p753docs"
  propose_write_doc "$D" cap-t753-paired change draft
  propose_write_doc "$D" cap-t753-free change draft
  local ROADMAP="$TEST_DIR/p753-roadmap.yaml"
  cat > "$ROADMAP" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t753-paired
    maintenance: maint-t753-paired
    status: planned
YAML
  [ "$(run_propose harvest --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p753-ledger.jsonl" --spool "$TEST_DIR/p753-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-753: harvest must exit 0: $(perr)"
  grep -qF '"id":"cap-t753-free"' "$TEST_DIR/pout" || log_fail "TEST-753: an unpaired intake draft must still be harvested: $(pout)"
  grep -qF '"id":"cap-t753-paired"' "$TEST_DIR/pout" \
    && log_fail "TEST-753: an intake draft already paired on the roadmap must NOT be harvested again: $(pout)"
  log_pass "harvest excludes an intake draft whose id is already a roadmap pair (TEST-753)"
}

# --- TEST-754 (Spec-AC-05): F6 — the "pair ahead" refusal never prints the --
# literal word null for an unbound (capability-only) maintenance slot.
test_754_gate_pair_ahead_never_prints_null() {
  log_info "Test: the pair-ahead refusal names the unbound maintenance slot as unbound, never the literal word null (TEST-754)..."
  local D="$TEST_DIR/p754docs"
  mkdir -p "$D"
  cat > "$TEST_DIR/p754-roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t754-first
    status: planned
  - capability: cap-t754-second
    status: planned
YAML
  [ "$(run gate --ref cap-t754-second --roadmap "$TEST_DIR/p754-roadmap.yaml" --docs "$D")" = "1" ] \
    || log_fail "TEST-754: gate on the second (not-first-unfinished) pair must refuse: $(out)"
  grep -qF 'null' "$TEST_DIR/err" && log_fail "TEST-754: the pair-ahead refusal must never print the literal word null: $(err)"
  grep -qF 'unbound' "$TEST_DIR/err" || log_fail "TEST-754: the pair-ahead refusal must name the unbound maintenance slot: $(err)"
  log_pass "the pair-ahead refusal names an unbound maintenance slot as unbound, never null (TEST-754)"
}

# --- TEST-755 (Spec-AC-29): F6 — the doc-missing refusal never prints the ---
# literal word null for an unbound (capability-only) maintenance slot.
test_755_gate_doc_missing_never_prints_null() {
  log_info "Test: the doc-missing refusal names the unbound maintenance slot as unbound, never the literal word null (TEST-755)..."
  local D="$TEST_DIR/p755docs"
  mkdir -p "$D"
  cat > "$TEST_DIR/p755-roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t755-first
    status: planned
YAML
  [ "$(run gate --ref cap-t755-first --roadmap "$TEST_DIR/p755-roadmap.yaml" --docs "$D")" = "1" ] \
    || log_fail "TEST-755: gate on the first-unfinished pair with no resolvable document must refuse: $(out)"
  grep -qF 'null' "$TEST_DIR/err" && log_fail "TEST-755: the doc-missing refusal must never print the literal word null: $(err)"
  grep -qF 'unbound' "$TEST_DIR/err" || log_fail "TEST-755: the doc-missing refusal must name the unbound maintenance slot: $(err)"
  log_pass "the doc-missing refusal names an unbound maintenance slot as unbound, never null (TEST-755)"
}

# --- TEST-756 (Spec-AC-15): F7 — write against a project with no roadmap ----
# discloses, in its own success line, that the ride gate is now ON.
test_756_write_discloses_gate_turned_on() {
  log_info "Test: write against a project with no roadmap discloses in its success line that the ride gate is now on (TEST-756)..."
  local D="$TEST_DIR/p756docs"
  propose_write_doc "$D" cap-t756 change draft
  local ROADMAP="$TEST_DIR/p756-nonexistent/roadmap.yaml"
  rm -rf "$TEST_DIR/p756-nonexistent"
  [ "$(run_propose write --direction "cap t756" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p756-ledger.jsonl" --spool "$TEST_DIR/p756-spool.jsonl")" = "0" ] \
    || log_fail "TEST-756: write creating a fresh roadmap must exit 0: $(perr)"
  assert_payload_contains "$(pout)" 'gate is now ON' \
    "TEST-756: the success line must disclose that the ride gate is now on for this project"
  log_pass "write against a project with no roadmap discloses that the ride gate is now on (TEST-756)"
}

# --- TEST-762 (Spec-AC-03): validation round 3 NB-1 — next stops proposing --
# a CAPABILITY ref with no resolvable document: NB-6/D16 (TEST-760) closed
# this livelock on the maintenance half only. `write` promotes a wave_2 or
# friction candidate straight into a pair's `capability:` slot with no
# document filed yet far more often than it binds a documentless maintenance
# ref, so this was the FIRST dead end an owner actually met, not a rare edge
# (validation-round3 NB-1). `next` now proposes filing the intake instead,
# the same as the maintenance half already does.
test_762_next_stops_proposing_dead_capability_ref() {
  log_info "Test: next never proposes a capability ref with no resolvable document — it proposes filing the intake instead (TEST-762, NB-1)..."
  cat > "$TEST_DIR/roadmap762.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t762-nodoc
    status: planned
YAML
  [ "$(run next --roadmap "$TEST_DIR/roadmap762.yaml" --docs "$TEST_DIR/docs" --json)" = "0" ] \
    || log_fail "TEST-762: next must exit 0: $(err)"
  grep -qF '"next":"cap-t762-nodoc"' "$TEST_DIR/out" \
    && log_fail "TEST-762: next must never propose a capability ref with no resolvable document (the NB-1 livelock): $(out)"
  grep -qF '"action":"file-intake"' "$TEST_DIR/out" \
    || log_fail "TEST-762: next must propose filing the intake instead of the dead capability ref: $(out)"
  grep -qF 'cap-t762-nodoc' "$TEST_DIR/out" \
    || log_fail "TEST-762: the file-intake action must still name the ref that needs an intake: $(out)"
  [ "$(run gate --ref cap-t762-nodoc --roadmap "$TEST_DIR/roadmap762.yaml" --docs "$TEST_DIR/docs")" = "1" ] \
    || log_fail "TEST-762: gate must still refuse the dead capability ref: $(out)"
  grep -qF 'no document resolves' "$TEST_DIR/err" \
    || log_fail "TEST-762: gate's refusal reason must name the missing document: $(err)"
  log_pass "next stops proposing a capability ref nothing can resolve, and proposes filing its intake instead (TEST-762, NB-1)"
}

# --- TEST-763 (Spec-AC-08): PR #399 Codex review F1 (D18 amendment) — a -----
# malformed decision ledger line's UNDERSTATED warning reaches harvest's own
# notes. `follow-ups.mjs list --json` SUCCEEDS over a ledger holding a
# malformed line and says so in its own `parsed.notes` (an "EXCLUDED …
# UNDERSTATED" line); the reader used to keep only `parsed.items` and drop
# the notes, so `observations` could come out low with no warning anywhere.
test_763_harvest_surfaces_followups_understated_note() {
  log_info "Test: a malformed decision ledger line's UNDERSTATED warning reaches harvest's own notes (TEST-763, F1)..."
  local D="$TEST_DIR/p763docs"
  propose_write_doc "$D" cap-t763 change draft
  local LEDGER="$TEST_DIR/p763-ledger.jsonl"
  : > "$LEDGER"
  node "$FOLLOWUPS" add --id fu-t763-probe --ref cap-t763 --severity P2 --what "w" --why "y" --source "s" --ledger "$LEDGER" >/dev/null 2>&1 \
    || log_fail "TEST-763: adding the fixture follow-up must succeed"
  printf 'not valid json at all\n' >> "$LEDGER"
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p763-roadmap.yaml" --docs "$D" --ledger "$LEDGER" --spool "$TEST_DIR/p763-spool.jsonl" --json)" = "0" ] \
    || log_fail "TEST-763: harvest must exit 0 even though the ledger holds a malformed line: $(perr)"
  assert_payload_contains "$(pout)" 'follow-ups:' \
    "TEST-763: the surfaced note must be attributed to the follow-ups source"
  assert_payload_contains "$(pout)" 'UNDERSTATED' \
    "TEST-763: harvest's notes must surface the follow-ups reader's own UNDERSTATED warning"
  log_pass "a malformed decision ledger line's UNDERSTATED warning reaches harvest's own notes (TEST-763)"
}

# --- TEST-764 (Spec-AC-11): PR #399 Codex review F2 (D18 amendment) — a -----
# malformed friction spool line is always surfaced as a NOTE, whether the
# spool is partially or entirely malformed. `readSpoolRows` used to filter a
# partial/malformed/non-object JSONL row with no count anywhere: a PARTIALLY
# malformed spool got no note at all, and an ALL-malformed spool reached the
# empty branch and printed "the friction spool is empty or absent" — a
# healthy-read description of what was actually a corrupt read.
test_764_harvest_surfaces_corrupt_spool_note() {
  log_info "Test: a malformed friction spool line is surfaced as a NOTE, whether the spool is partially or entirely malformed (TEST-764, F2)..."
  local SPOOL="$TEST_DIR/p764-spool.jsonl"
  cat > "$SPOOL" <<JSONL
{"schema_version":2,"harness":"claude-code","skill_id":"aai-t764","skill_phase":"test-execution","failure_class":"deterministic_script_failure","fingerprint":"fp-t764","impact":"high","confidence":"high","reproducible":true}
{not valid json
JSONL
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p764-roadmap.yaml" --docs "$TEST_DIR/p764docs" --ledger "$TEST_DIR/p764-ledger.jsonl" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-764: harvest must exit 0 over a partially malformed spool: $(perr)"
  local n_friction
  n_friction="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.filter((c) => c.source === "friction").length));
  ' "$TEST_DIR/pout")"
  [ "$n_friction" = "1" ] || log_fail "TEST-764: the one well-formed row must still become a friction candidate, got $n_friction: $(pout)"
  assert_payload_contains "$(pout)" 'malformed friction spool line' \
    "TEST-764: a partially malformed spool must surface a malformed-line note, not silence"
  assert_payload_contains "$(pout)" 'UNDERSTATED' \
    "TEST-764: the malformed-spool note must warn friction observations may be understated"

  local SPOOL2="$TEST_DIR/p764-spool-allbad.jsonl"
  printf '{not json\nalso not json\n' > "$SPOOL2"
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p764b-roadmap.yaml" --docs "$TEST_DIR/p764bdocs" --ledger "$TEST_DIR/p764b-ledger.jsonl" --spool "$SPOOL2" --json)" = "0" ] \
    || log_fail "TEST-764: harvest must exit 0 over an entirely malformed spool: $(perr)"
  assert_payload_contains "$(pout)" '2 malformed friction spool line' \
    "TEST-764: an entirely malformed spool must still count and name its malformed lines"
  assert_payload_not_contains "$(pout)" 'is empty or absent' \
    "TEST-764: an entirely malformed spool must never be described as merely empty or absent"
  log_pass "a malformed friction spool line is surfaced as a NOTE, whether the spool is partially or entirely malformed (TEST-764)"
}

# --- TEST-765 (Spec-AC-06): PR #399 Codex review F3 (D18 amendment) — dedup -
# never drops a friction candidate's recurrence. When a friction-generated id
# also exists as a wave_2 slug (or intake draft), mergeDuplicateCandidates
# used to keep the richest duplicate's OWN `recurrence` field (undefined for
# a non-friction record) and evaluateCandidate's `c.source === 'friction'`
# exact-equality check never matched a merged, comma-joined source ("wave_2,
# friction") — silently dropping the friction row's recurrence from
# observations with no warning anywhere.
test_765_harvest_dedup_keeps_friction_recurrence() {
  log_info "Test: a friction candidate's recurrence survives a dedup merge with a colliding wave_2 slug (TEST-765, F3)..."
  local D="$TEST_DIR/p765docs"
  local SPOOL="$TEST_DIR/p765-spool.jsonl"
  local LEDGER="$TEST_DIR/p765-ledger.jsonl"
  : > "$LEDGER"
  # skill_id + failure_class must slugify to the SAME id the wave_2 fixture
  # below deliberately collides with (frictionLabel: friction-<skill_id>-
  # <failure_class>); failure_class must also be a real taxonomy class (a
  # non-taxonomy one is dropped before scoring, per aai-feedback-triage.mjs).
  cat > "$SPOOL" <<JSONL
{"schema_version":2,"harness":"claude-code","skill_id":"t765","skill_phase":"test-execution","failure_class":"deterministic_script_failure","fingerprint":"fp-t765","impact":"high","confidence":"high","reproducible":true}
{"schema_version":2,"harness":"claude-code","skill_id":"t765","skill_phase":"test-execution","failure_class":"deterministic_script_failure","fingerprint":"fp-t765","impact":"high","confidence":"high","reproducible":true}
JSONL
  cat > "$TEST_DIR/p765-roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-t765-other
    maintenance: maint-t765-other
    status: planned
wave_2:
  - friction-t765-deterministic-script-failure
YAML
  [ "$(run_propose harvest --roadmap "$TEST_DIR/p765-roadmap.yaml" --docs "$D" --ledger "$LEDGER" --spool "$SPOOL" --json)" = "0" ] \
    || log_fail "TEST-765: harvest must exit 0: $(perr)"
  local source
  source="$(propose_field friction-t765-deterministic-script-failure source)"
  [ "$source" = '"wave_2,friction"' ] \
    || log_fail "TEST-765: the merged candidate's source must name both wave_2 and friction, got $source: $(pout)"
  [ "$(propose_field friction-t765-deterministic-script-failure observations)" = "2" ] \
    || log_fail "TEST-765: the friction row's recurrence (2) must still count toward observations after the dedup merge, got: $(pout)"
  log_pass "a friction candidate's recurrence survives a dedup merge with a colliding wave_2 slug (TEST-765)"
}

# --- Budget is opt-in (SPEC roadmap-serves-downstream-projects, TEST-1301..1310) ---
# nb_roadmap <path> [budget]  — a two-pair fixture roadmap; with a 2nd arg it carries the 1:1 budget block.
nb_roadmap() { # $1=path  $2=with-budget (any non-empty) $3=status of pair 1 (default active)
  {
    [ -n "${2:-}" ] && printf 'budget:\n  maintenance_per_capability: 1\n'
    printf 'pairs:\n  - capability: cap-a\n    status: %s\n  - capability: cap-b\n    status: planned\nwave_2:\n  - later-thing\n' "${3:-active}"
  } > "$1"
}

test_1301_validate_accepts_no_budget() {
  log_info "Test: a roadmap with no budget block validates exit 0 (TEST-1301)..."
  printf 'pairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: planned\n' > "$TEST_DIR/t1301-a.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1301-a.yaml")" = "0" ] || log_fail "TEST-1301: a pairs-only roadmap must validate: $(err)"
  [ "$(out)" = "roadmap OK: 1 pair(s), 0 wave-2 item(s)" ] || log_fail "TEST-1301: pairs-only summary wrong: $(out)"
  nb_roadmap "$TEST_DIR/t1301-b.yaml" "" planned
  [ "$(run validate --roadmap "$TEST_DIR/t1301-b.yaml")" = "0" ] || log_fail "TEST-1301: pairs plus wave_2 without budget must validate: $(err)"
  [ "$(out)" = "roadmap OK: 2 pair(s), 1 wave-2 item(s)" ] || log_fail "TEST-1301: pairs+wave_2 summary wrong: $(out)"
  # negative control: no budget AND no pairs is still invalid
  printf 'wave_2:\n  - later-thing\n' > "$TEST_DIR/t1301-c.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1301-c.yaml")" = "2" ] || log_fail "TEST-1301: a roadmap with no pairs must still exit 2"
  grep -q 'no pairs' "$TEST_DIR/err" || log_fail "TEST-1301: the no-pairs refusal must name its reason: $(err)"
  log_pass "a roadmap without a budget block validates; no pairs still refuses (TEST-1301)"
}

test_1302_budget_block_stays_strict() {
  log_info "Test: a PRESENT budget block must still be exactly maintenance_per_capability: 1 (TEST-1302)..."
  printf 'budget:\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1302-empty.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1302-empty.yaml")" = "2" ] || log_fail "TEST-1302: an empty budget block must exit 2"
  grep -q 'maintenance_per_capability is missing' "$TEST_DIR/err" || log_fail "TEST-1302: the empty-block refusal must name the missing key: $(err)"
  printf 'budget:\n  maintenance_per_capability: 1\nbudget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1302-dup.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1302-dup.yaml")" = "2" ] || log_fail "TEST-1302: a duplicated budget block must exit 2"
  printf 'budget:\n  maintenance_per_capability: 2\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1302-two.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1302-two.yaml")" = "2" ] || log_fail "TEST-1302: maintenance_per_capability 2 must exit 2"
  grep -q 'must be 1' "$TEST_DIR/err" || log_fail "TEST-1302: the value refusal must say must be 1: $(err)"
  [ "$(run validate --roadmap "$SHIPPED")" = "0" ] || log_fail "TEST-1302: the shipped roadmap must validate: $(err)"
  [ "$(out)" = "roadmap OK: 13 pair(s), 4 wave-2 item(s)" ] || log_fail "TEST-1302: the shipped summary must be byte-identical, got: $(out)"
  log_pass "empty, duplicate and non-1 budget blocks still exit 2; shipped summary unchanged (TEST-1302)"
}

# nb_gate_fixture <dir> <with-budget> — roadmap + docs shared by TEST-1303/1304/1305
nb_gate_fixture() {
  local d="$1"
  [ -n "$d" ] && [ "${d#/}" != "$d" ] || log_fail "nb_gate_fixture: dir must be absolute and non-empty"
  mkdir -p "$d"
  nb_roadmap "$d/roadmap.yaml" "${2:-}"
  propose_write_doc "$d/docs" cap-a change implementing
  propose_write_doc "$d/docs" cap-b change draft
  propose_write_doc "$d/docs" iss-off issue draft
  propose_write_doc "$d/docs" chg-off change draft
  propose_write_doc "$d/docs" chg-done change done
}
gate_at() { # $1=dir $2=ref [extra args]
  local d="$1" r="$2"; shift 2
  run gate --ref "$r" --roadmap "$d/roadmap.yaml" --docs "$d/docs" --events "$d/events.jsonl" "$@"
}

test_1303_nobudget_gate_admits() {
  log_info "Test: without a budget gate admits off-roadmap maintenance, off-roadmap capability and an out-of-order ref (TEST-1303)..."
  local d="$TEST_DIR/t1303"; nb_gate_fixture "$d"
  local r
  for r in iss-off chg-off cap-b; do
    [ "$(gate_at "$d" "$r")" = "0" ] || log_fail "TEST-1303: no-budget gate must admit $r: $(err)"
    grep -q 'ADMIT' "$TEST_DIR/out" || log_fail "TEST-1303: $r must print an ADMIT line: $(out)"
    grep -q 'no maintenance budget' "$TEST_DIR/out" || log_fail "TEST-1303: the ADMIT line for $r must say no maintenance budget: $(out)"
  done
  [ ! -e "$d/events.jsonl" ] || log_fail "TEST-1303: an admit must write no EVENTS line"
  log_pass "no-budget gate admits the three shapes, ADMIT lines say no maintenance budget, nothing written (TEST-1303)"
}

test_1304_nobudget_gate_still_refuses() {
  log_info "Test: without a budget gate refuses a done ref and a ref with no document (TEST-1304)..."
  local d="$TEST_DIR/t1304"; nb_gate_fixture "$d"
  [ "$(gate_at "$d" chg-done)" = "1" ] || log_fail "TEST-1304: a done ref must be refused exit 1"
  grep -q 'REFUSED' "$TEST_DIR/err" || log_fail "TEST-1304: the done refusal must print REFUSED: $(err)"
  [ "$(gate_at "$d" ghost-ref)" = "1" ] || log_fail "TEST-1304: a ref with no document must be refused exit 1, got: $(out)"
  grep -q 'REFUSED' "$TEST_DIR/err" || log_fail "TEST-1304: the documentless refusal must print REFUSED: $(err)"
  grep -q 'no document resolves' "$TEST_DIR/err" || log_fail "TEST-1304: the documentless refusal must name its reason: $(err)"
  # a ref inside a pair already marked done is refused too
  nb_roadmap "$d/roadmap.yaml" "" done
  [ "$(gate_at "$d" cap-a)" = "1" ] || log_fail "TEST-1304: a ref in a done pair must be refused"
  # positive control: a documented, undone ref is admitted on the same fixture
  [ "$(gate_at "$d" iss-off)" = "0" ] || log_fail "TEST-1304: control — a documented off-roadmap ref must still be admitted: $(err)"
  log_pass "no-budget gate refuses done, documentless and done-pair refs (TEST-1304)"
}

test_1305_budget_gate_unchanged() {
  log_info "Test: the same fixtures WITH a budget refuse with today's reasons (TEST-1305)..."
  local d="$TEST_DIR/t1305"; nb_gate_fixture "$d" yes
  [ "$(gate_at "$d" iss-off)" = "1" ] || log_fail "TEST-1305: off-roadmap maintenance must be refused under a budget"
  grep -q 'is maintenance and not on the roadmap' "$TEST_DIR/err" || log_fail "TEST-1305: wrong reason for iss-off: $(err)"
  [ "$(gate_at "$d" chg-off)" = "1" ] || log_fail "TEST-1305: an off-roadmap capability must be refused under a budget"
  grep -q 'is not on the roadmap' "$TEST_DIR/err" || log_fail "TEST-1305: wrong reason for chg-off: $(err)"
  [ "$(gate_at "$d" cap-b)" = "1" ] || log_fail "TEST-1305: a pair behind an unfinished pair must be refused under a budget"
  grep -q 'pair ahead' "$TEST_DIR/err" || log_fail "TEST-1305: wrong reason for cap-b: $(err)"
  log_pass "with a budget the three fixtures refuse exactly as before (TEST-1305)"
}

test_1306_nobudget_next_never_binds() {
  log_info "Test: without a budget next names a started capability-only pair and skips a done pair (TEST-1306)..."
  local d="$TEST_DIR/t1306"; mkdir -p "$d"
  printf 'pairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: active\n' > "$d/roadmap.yaml"
  propose_write_doc "$d/docs" cap-a change done
  propose_write_doc "$d/docs" cap-b change implementing
  [ "$(run next --roadmap "$d/roadmap.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1306: next must exit 0: $(err)"
  grep -qF '"next":"cap-b"' "$TEST_DIR/out" || log_fail "TEST-1306: next must name cap-b, got: $(out)"
  grep -qF '"half":"capability"' "$TEST_DIR/out" || log_fail "TEST-1306: next must carry half capability, got: $(out)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" && log_fail "TEST-1306: without a budget next must never print action bind: $(out)"
  # fixture diversity: a capability with no document asks for the intake; an exhausted roadmap names null
  printf 'pairs:\n  - capability: cap-z\n    status: planned\n' > "$d/roadmap-z.yaml"
  [ "$(run next --roadmap "$d/roadmap-z.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1306: next over a documentless capability must exit 0"
  grep -qF '"action":"file-intake"' "$TEST_DIR/out" || log_fail "TEST-1306: a documentless capability must say file-intake, got: $(out)"
  printf 'pairs:\n  - capability: cap-a\n    status: done\n' > "$d/roadmap-x.yaml"
  [ "$(run next --roadmap "$d/roadmap-x.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1306: next over an exhausted roadmap must exit 0"
  grep -qF '"next":null' "$TEST_DIR/out" || log_fail "TEST-1306: an exhausted roadmap must name next null, got: $(out)"
  # negative control: the SAME started capability-only pair under a budget DOES propose bind
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-b\n    status: active\n' > "$d/roadmap-bud.yaml"
  [ "$(run next --roadmap "$d/roadmap-bud.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1306: budget next must exit 0"
  grep -qF '"action":"bind"' "$TEST_DIR/out" || log_fail "TEST-1306: control — a budget roadmap must still propose bind, got: $(out)"
  log_pass "no-budget next names the capability, skips done, never binds; budget control still binds (TEST-1306)"
}

test_1307_nobudget_next_skips_done_capability_doc() {
  log_info "Test: without a budget next skips a pair whose capability DOCUMENT is done (TEST-1307)..."
  local d="$TEST_DIR/t1307"; mkdir -p "$d"
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\n' > "$d/roadmap.yaml"
  propose_write_doc "$d/docs" cap-a change done
  propose_write_doc "$d/docs" cap-b change draft
  [ "$(run next --roadmap "$d/roadmap.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1307: next must exit 0: $(err)"
  grep -qF '"next":"cap-b"' "$TEST_DIR/out" || log_fail "TEST-1307: next must skip the done-document pair and name cap-b, got: $(out)"
  log_pass "no-budget next skips a pair whose capability document is done (TEST-1307)"
}

test_1308_next_json_carries_path() {
  log_info "Test: next --json carries the resolving document path in both postures (TEST-1308)..."
  local d="$TEST_DIR/t1308" posture
  for posture in "" yes; do
    rm -rf "$d"; nb_gate_fixture "$d" "$posture"
    propose_write_doc "$d/docs" cap-a change draft   # not started: a budget roadmap then names cap-a itself, not a bind
    [ "$(run next --roadmap "$d/roadmap.yaml" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1308: next must exit 0: $(err)"
    local one="/" want; want="${d//\/\//$one}/docs/issues/CHANGE-DRAFT-cap-a.md"   # node path.join collapses a double slash in TMPDIR
    grep -qF "\"path\":\"$want\"" "$TEST_DIR/out" \
      || log_fail "TEST-1308: next json (budget='${posture:-none}') must carry the document path, got: $(out)"
  done
  log_pass "next --json carries the resolving document path with and without a budget (TEST-1308)"
}

test_1309_show() {
  log_info "Test: show prints the posture, the next item, no roadmap when absent, json keys, exit 2 when invalid (TEST-1309)..."
  local d="$TEST_DIR/t1309"; nb_gate_fixture "$d"
  [ "$(run show --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1309: show must exit 0: $(err)"
  grep -qF 'maintenance budget: off' "$TEST_DIR/out" || log_fail "TEST-1309: a no-budget fixture must print maintenance budget: off, got: $(out)"
  grep -qF 'cap-a' "$TEST_DIR/out" || log_fail "TEST-1309: show must name the next item cap-a, got: $(out)"
  nb_roadmap "$d/roadmap-b.yaml" yes
  [ "$(run show --roadmap "$d/roadmap-b.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1309: show over a budget fixture must exit 0: $(err)"
  grep -qF 'maintenance budget: on' "$TEST_DIR/out" || log_fail "TEST-1309: a budget fixture must print maintenance budget: on, got: $(out)"
  [ "$(run show --roadmap "$d/absent.yaml")" = "0" ] || log_fail "TEST-1309: show over an absent path must exit 0: $(err)"
  grep -qF 'no roadmap' "$TEST_DIR/out" || log_fail "TEST-1309: an absent path must print no roadmap, got: $(out)"
  [ "$(wc -l < "$TEST_DIR/out" | tr -d ' ')" = "1" ] || log_fail "TEST-1309: the absent answer must be exactly one line"
  [ ! -e "$d/absent.yaml" ] || log_fail "TEST-1309: show must not create the roadmap"
  [ "$(run show --json --roadmap "$d/roadmap-b.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1309: show --json must exit 0: $(err)"
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    for (const k of ["budget", "next", "pairs", "wave_2"]) if (!(k in j)) { console.error("missing " + k); process.exit(1); }
    if (j.budget !== true) { console.error("budget must be true"); process.exit(1); }
  ' "$TEST_DIR/out" 2> "$TEST_DIR/err" || log_fail "TEST-1309: show --json keys wrong: $(err) / $(out)"
  [ "$(run show --json --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1309: show --json (no budget) must exit 0"
  grep -qF '"budget":false' "$TEST_DIR/out" || log_fail "TEST-1309: a no-budget fixture must report budget false, got: $(out)"
  printf 'pairs:\n  - nonsense\n' > "$d/bad.yaml"
  [ "$(run show --roadmap "$d/bad.yaml")" = "2" ] || log_fail "TEST-1309: an invalid roadmap must exit 2"
  log_pass "show reports posture, next, no roadmap, json keys and exit 2 (TEST-1309)"
}

test_1310_write_seed_has_no_budget() {
  log_info "Test: write --pick 1 against an absent roadmap seeds NO budget block (TEST-1310)..."
  local D="$TEST_DIR/p1310docs" ROADMAP="$TEST_DIR/p1310-roadmap.yaml"
  propose_write_doc "$D" cap-t1310-new change draft
  [ "$(run_propose write --direction "cap t1310 new direction" --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p1310-ledger.jsonl" --spool "$TEST_DIR/p1310-spool.jsonl")" = "0" ] \
    || log_fail "TEST-1310: write must exit 0: $(perr)"
  [ -f "$ROADMAP" ] || log_fail "TEST-1310: write must create the roadmap"
  if grep -q 'budget' "$ROADMAP"; then log_fail "TEST-1310: a freshly seeded roadmap must carry no budget line: $(cat "$ROADMAP")"; fi
  grep -q 'capability: cap-t1310-new' "$ROADMAP" || log_fail "TEST-1310: the picked capability must be written"
  [ "$(run validate --roadmap "$ROADMAP" --docs "$D")" = "0" ] || log_fail "TEST-1310: the seeded roadmap must validate: $(err)"
  [ "$(run next --roadmap "$ROADMAP" --docs "$D" --json)" = "0" ] || log_fail "TEST-1310: next must exit 0: $(err)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" && log_fail "TEST-1310: next over a seeded roadmap must never carry action bind: $(out)"
  log_pass "write seeds a budget-free roadmap that validates and never proposes bind (TEST-1310)"
}

# --- Advisory maintenance budget (SPEC roadmap-maintenance-budget-advisory,
# TEST-1600..1644) — D1/D2: a third posture, a two-line block (mode +
# maintenance_threshold) parsed by the SAME loadRoadmap. This file covers
# Spec-AC-01/02 only (TEST-1600..1605); later ACs land in later TDD runs.

test_1600_validate_accepts_advisory_block() {
  log_info "Test: an advisory budget block validates exit 0 in either line order, threshold 1 and 12 (TEST-1600)..."
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1600-mode-first.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1600-mode-first.yaml")" = "0" ] || log_fail "TEST-1600: mode-first advisory block must validate: $(err)"
  [ "$(out)" = "roadmap OK: 1 pair(s), 0 wave-2 item(s)" ] || log_fail "TEST-1600: mode-first summary wrong: $(out)"
  printf 'budget:\n  maintenance_threshold: 5\n  mode: advisory\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1600-threshold-first.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1600-threshold-first.yaml")" = "0" ] || log_fail "TEST-1600: threshold-first advisory block must validate: $(err)"
  [ "$(out)" = "roadmap OK: 1 pair(s), 0 wave-2 item(s)" ] || log_fail "TEST-1600: threshold-first summary wrong: $(out)"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 1\npairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\nwave_2:\n  - later-thing\n' > "$TEST_DIR/t1600-threshold-1.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1600-threshold-1.yaml")" = "0" ] || log_fail "TEST-1600: threshold 1 must validate: $(err)"
  [ "$(out)" = "roadmap OK: 2 pair(s), 1 wave-2 item(s)" ] || log_fail "TEST-1600: threshold 1 summary wrong: $(out)"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 12\npairs:\n  - capability: cap-a\n    status: planned\n' > "$TEST_DIR/t1600-threshold-12.yaml"
  [ "$(run validate --roadmap "$TEST_DIR/t1600-threshold-12.yaml")" = "0" ] || log_fail "TEST-1600: threshold 12 must validate: $(err)"
  [ "$(out)" = "roadmap OK: 1 pair(s), 0 wave-2 item(s)" ] || log_fail "TEST-1600: threshold 12 summary wrong: $(out)"
  log_pass "advisory block validates in either line order with threshold 1 and 12 (TEST-1600)"
}

test_1601_threshold_shapes_refuse() {
  log_info "Test: every invalid maintenance_threshold shape exits 2 naming it, file unchanged (TEST-1601)..."
  local f="$TEST_DIR/t1601.yaml" before after
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 0\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: threshold 0 must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: threshold 0 refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: threshold 0 must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: -3\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: threshold -3 must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: threshold -3 refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: threshold -3 must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 1.5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: threshold 1.5 must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: threshold 1.5 refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: threshold 1.5 must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 05\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: leading-zero threshold must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: leading-zero refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: leading-zero must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: "5"\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: double-quoted threshold must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: double-quoted refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: double-quoted must leave the file unchanged"
  printf "budget:\n  mode: advisory\n  maintenance_threshold: '5'\npairs:\n  - capability: cap-a\n    status: planned\n" > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: single-quoted threshold must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: single-quoted refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: single-quoted must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold:\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: empty threshold value must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: empty-value refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: empty value must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 5 # inline comment\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: inline-comment threshold must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: inline-comment refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: inline comment must leave the file unchanged"
  printf 'budget:\n  mode: advisory\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: threshold line missing must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: missing-line refusal must name maintenance_threshold: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: missing line must leave the file unchanged"
  # NB1 (validation round 1): a shape-valid digit string above
  # Number.MAX_SAFE_INTEGER must be refused, never silently rounded by
  # Number(bthr) (9007199254740993 reads back as ...992).
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 9007199254740993\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1601: threshold above MAX_SAFE_INTEGER must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold' "$TEST_DIR/err" || log_fail "TEST-1601: above-MAX_SAFE_INTEGER refusal must name maintenance_threshold: $(err)"
  grep -q '9007199254740993' "$TEST_DIR/err" || log_fail "TEST-1601: above-MAX_SAFE_INTEGER refusal must quote the exact over-cap digit string, not a rounded one: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1601: above-MAX_SAFE_INTEGER must leave the file unchanged"
  # The cap itself (Number.MAX_SAFE_INTEGER, 9007199254740991) must still validate.
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 9007199254740991\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  [ "$(run validate --roadmap "$f")" = "0" ] || log_fail "TEST-1601: threshold AT MAX_SAFE_INTEGER must validate: $(out) $(err)"
  log_pass "every invalid maintenance_threshold shape exits 2 naming it, file unchanged (TEST-1601)"
}

test_1602_mode_shapes_refuse() {
  log_info "Test: every invalid budget.mode shape exits 2 naming it, file unchanged (TEST-1602)..."
  local f="$TEST_DIR/t1602.yaml" before after
  printf 'budget:\n  mode: on\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1602: mode on must exit 2: $(out) $(err)"
  grep -q 'budget.mode' "$TEST_DIR/err" || log_fail "TEST-1602: mode-on refusal must name budget.mode: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1602: mode on must leave the file unchanged"
  printf 'budget:\n  mode: off\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1602: mode off must exit 2: $(out) $(err)"
  grep -q 'budget.mode' "$TEST_DIR/err" || log_fail "TEST-1602: mode-off refusal must name budget.mode: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1602: mode off must leave the file unchanged"
  printf 'budget:\n  mode: Advisory\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1602: mode Advisory must exit 2: $(out) $(err)"
  grep -q 'budget.mode' "$TEST_DIR/err" || log_fail "TEST-1602: mode-Advisory refusal must name budget.mode: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1602: mode Advisory must leave the file unchanged"
  printf 'budget:\n  mode: "advisory"\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1602: quoted mode must exit 2: $(out) $(err)"
  grep -q 'budget.mode' "$TEST_DIR/err" || log_fail "TEST-1602: quoted-mode refusal must name budget.mode: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1602: quoted mode must leave the file unchanged"
  printf 'budget:\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1602: threshold without any mode line must exit 2: $(out) $(err)"
  grep -q 'budget.mode' "$TEST_DIR/err" || log_fail "TEST-1602: mode-missing refusal must name budget.mode: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1602: mode-missing must leave the file unchanged"
  log_pass "every invalid budget.mode shape exits 2 naming it, file unchanged (TEST-1602)"
}

test_1603_mode_and_threshold_duplicates_refuse() {
  log_info "Test: mode or maintenance_threshold appearing twice exits 2 naming appears twice (TEST-1603)..."
  local f="$TEST_DIR/t1603.yaml" before after
  printf 'budget:\n  mode: advisory\n  mode: advisory\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1603: mode twice (same value) must exit 2: $(out) $(err)"
  grep -q 'budget.mode appears twice' "$TEST_DIR/err" || log_fail "TEST-1603: mode-twice refusal must say appears twice: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1603: mode twice must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  mode: on\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1603: mode twice (different values) must exit 2: $(out) $(err)"
  grep -q 'budget.mode appears twice' "$TEST_DIR/err" || log_fail "TEST-1603: mode-twice-different refusal must say appears twice: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1603: mode twice (different) must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 5\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1603: threshold twice (same value) must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold appears twice' "$TEST_DIR/err" || log_fail "TEST-1603: threshold-twice refusal must say appears twice: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1603: threshold twice must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 5\n  maintenance_threshold: 7\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1603: threshold twice (different values) must exit 2: $(out) $(err)"
  grep -q 'maintenance_threshold appears twice' "$TEST_DIR/err" || log_fail "TEST-1603: threshold-twice-different refusal must say appears twice: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1603: threshold twice (different) must leave the file unchanged"
  log_pass "duplicated budget.mode and budget.maintenance_threshold exit 2 naming appears twice (TEST-1603)"
}

test_1604_combined_and_unknown_key_refuse() {
  log_info "Test: mode/threshold combined with maintenance_per_capability, and an unknown budget key, both exit 2 (TEST-1604)..."
  local f="$TEST_DIR/t1604.yaml" before after
  printf 'budget:\n  maintenance_per_capability: 1\n  mode: advisory\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1604: mode+threshold combined with maintenance_per_capability must exit 2: $(out) $(err)"
  grep -q 'cannot be combined' "$TEST_DIR/err" || log_fail "TEST-1604: combined refusal must say cannot be combined: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1604: combined (mode+threshold) must leave the file unchanged"
  printf 'budget:\n  maintenance_per_capability: 1\n  maintenance_threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1604: threshold alone combined with maintenance_per_capability must exit 2: $(out) $(err)"
  grep -q 'cannot be combined' "$TEST_DIR/err" || log_fail "TEST-1604: combined (threshold alone) refusal must say cannot be combined: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1604: combined (threshold alone) must leave the file unchanged"
  printf 'budget:\n  mode: advisory\n  threshold: 5\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1604: an unknown key inside budget must exit 2: $(out) $(err)"
  grep -q 'does not fit the closed roadmap shape' "$TEST_DIR/err" || log_fail "TEST-1604: unknown-key refusal must be the closed-shape message: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1604: unknown key must leave the file unchanged"
  log_pass "combined forms and an unknown budget key both exit 2 (TEST-1604)"
}

test_1605_empty_block_and_regression() {
  log_info "Test: an empty budget block keeps today's exact message; TEST-1301/TEST-1302 selectors stay green (TEST-1605)..."
  local f="$TEST_DIR/t1605.yaml" before after
  printf 'budget:\npairs:\n  - capability: cap-a\n    status: planned\n' > "$f"
  before="$(sha "$f")"
  [ "$(run validate --roadmap "$f")" = "2" ] || log_fail "TEST-1605: an empty budget block must exit 2: $(out) $(err)"
  [ "$(err)" = "ride-select: invalid roadmap $f: budget: block present but maintenance_per_capability is missing" ] \
    || log_fail "TEST-1605: the empty-block message must stay byte-identical, got: $(err)"
  after="$(sha "$f")"; [ "$before" = "$after" ] || log_fail "TEST-1605: empty block must leave the file unchanged"
  test_1301_validate_accepts_no_budget
  test_1302_budget_block_stays_strict
  log_pass "empty budget block message unchanged; TEST-1301/TEST-1302 still pass (TEST-1605)"
}

# --- Advisory next/gate (Spec-AC-03..06, TEST-1606..1620) --------------------
# D2/D9: gate under advisory is structurally the off gate (rm.budget stays
# null); D3..D6: next proposes maintenance under a threshold or a related
# trigger. Every fixture passes its OWN --ledger/--events/--docs; none reads
# the live repository.

# write_1606_roadmap <path> <budget-lines|''> — SAME 3-pair body every time,
# so the only difference between the advisory/off/on runs is the budget block.
write_1606_roadmap() {
  {
    [ -n "${2:-}" ] && printf '%b' "$2"
    printf 'pairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: active\n  - capability: cap-c\n    status: planned\n'
  } > "$1"
}
gate_at_ev() { # $1=roadmap $2=docs $3=ref $4=eventsPath [extra args]
  local r="$1" docs="$2" ref="$3" ev="$4"; shift 4
  run gate --ref "$ref" --roadmap "$r" --docs "$docs" --events "$ev" "$@"
}

test_1606_gate_advisory_equals_off() {
  log_info "Test: gate on an advisory roadmap equals gate on the same roadmap without a budget, byte for byte, over a 7-case ref matrix (TEST-1606)..."
  local d="$TEST_DIR/t1606"; mkdir -p "$d/docs"
  # cap-a's own DOCUMENT is still implementing although its PAIR is already
  # marked done (a hand-run close that never flipped the pair) — this is the
  # "ref in a done pair" case, distinct from "done ref" (chg-done) below.
  propose_write_doc "$d/docs" cap-a change implementing
  propose_write_doc "$d/docs" cap-b change implementing
  propose_write_doc "$d/docs" cap-c change draft
  propose_write_doc "$d/docs" iss-off issue draft
  propose_write_doc "$d/docs" chg-off change draft
  propose_write_doc "$d/docs" chg-done change done

  local adv="$d/roadmap-advisory.yaml" off="$d/roadmap-off.yaml" on="$d/roadmap-on.yaml"
  write_1606_roadmap "$adv" 'budget:\n  mode: advisory\n  maintenance_threshold: 50\n'
  write_1606_roadmap "$off" ''
  write_1606_roadmap "$on" 'budget:\n  maintenance_per_capability: 1\n'

  local refs="cap-a cap-c chg-done ghost-ref iss-off chg-off" r
  for r in $refs; do
    rm -f "$d/ev-adv.jsonl" "$d/ev-off.jsonl"
    local eadv oadv sadv eoff ooff soff evadv evoff
    eadv="$(gate_at_ev "$adv" "$d/docs" "$r" "$d/ev-adv.jsonl")"; oadv="$(out)"; sadv="$(err)"
    evadv=""; [ -f "$d/ev-adv.jsonl" ] && evadv="$(cat "$d/ev-adv.jsonl")"
    eoff="$(gate_at_ev "$off" "$d/docs" "$r" "$d/ev-off.jsonl")"; ooff="$(out)"; soff="$(err)"
    evoff=""; [ -f "$d/ev-off.jsonl" ] && evoff="$(cat "$d/ev-off.jsonl")"
    [ "$eadv" = "$eoff" ] || log_fail "TEST-1606: exit code differs for $r: advisory=$eadv off=$eoff"
    [ "$oadv" = "$ooff" ] || log_fail "TEST-1606: stdout differs for $r: advisory=[$oadv] off=[$ooff]"
    [ "$sadv" = "$soff" ] || log_fail "TEST-1606: stderr differs for $r: advisory=[$sadv] off=[$soff]"
    [ "$evadv" = "$evoff" ] || log_fail "TEST-1606: EVENTS bytes differ for $r"
  done

  # 7th case: the out-of-order ref cap-c with --override — admitted directly
  # in both postures (off/advisory never rank), so --override is never
  # consulted and no EVENTS line is written in either.
  rm -f "$d/ev-adv.jsonl" "$d/ev-off.jsonl"
  local eadv oadv eoff ooff
  eadv="$(gate_at_ev "$adv" "$d/docs" cap-c "$d/ev-adv.jsonl" --override "owner wants it now")"; oadv="$(out)"
  eoff="$(gate_at_ev "$off" "$d/docs" cap-c "$d/ev-off.jsonl" --override "owner wants it now")"; ooff="$(out)"
  [ "$eadv" = "0" ] || log_fail "TEST-1606: advisory must ADMIT cap-c with --override: $(err)"
  [ "$eoff" = "0" ] || log_fail "TEST-1606: off must ADMIT cap-c with --override: $(err)"
  [ "$oadv" = "$ooff" ] || log_fail "TEST-1606: stdout differs for cap-c --override: [$oadv] vs [$ooff]"
  [ ! -f "$d/ev-adv.jsonl" ] || log_fail "TEST-1606: an admit must write no EVENTS line (advisory, --override)"
  [ ! -f "$d/ev-off.jsonl" ] || log_fail "TEST-1606: an admit must write no EVENTS line (off, --override)"

  # positive control: the SAME out-of-order ref IS refused under the 1:1 budget
  [ "$(run gate --ref cap-c --roadmap "$on" --docs "$d/docs" --events "$d/ev-on.jsonl")" = "1" ] \
    || log_fail "TEST-1606: control — the 1:1-budget roadmap must refuse the out-of-order ref cap-c"
  grep -q 'pair ahead' "$TEST_DIR/err" || log_fail "TEST-1606: control refusal must say pair ahead: $(err)"
  log_pass "gate on advisory equals gate on off byte for byte over the ref matrix; on-budget control still refuses out-of-order (TEST-1606)"
}

# adv_roadmap <path> <threshold> — one capability-only pair, documented, so
# `next`'s off-equivalent answer is a plain ref (never file-intake/bind).
adv_roadmap() {
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: %s\npairs:\n  - capability: zz-cap\n    status: planned\n' "$2" > "$1"
}
fu_add() { # $1=ledger $2=id $3=ref $4=severity
  [ -f "$1" ] || : > "$1"   # add requires an existing (even empty) ledger file
  node "$FOLLOWUPS" add --ledger "$1" --id "$2" --ref "$3" --severity "$4" \
    --what "t" --why "t" --source "t" > "$TEST_DIR/fuout" 2> "$TEST_DIR/fuerr" \
    || log_fail "fu_add($2) failed: $(cat "$TEST_DIR/fuerr")"
}
fu_close() { # $1=ledger $2=id [$3=status]
  node "$FOLLOWUPS" close --ledger "$1" --id "$2" --resolved-by x --status "${3:-done}" > "$TEST_DIR/fuout" 2> "$TEST_DIR/fuerr" \
    || log_fail "fu_close($2) failed: $(cat "$TEST_DIR/fuerr")"
}
events_closes() { # $1=path $2=ts $3=ref — append one work_item_closed record
  printf '{"v":1,"ts":"%s","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{}}\n' "$2" "$3" >> "$1"
}
next_at() { # $1=roadmap $2=docs $3=ledger $4=events [extra args, e.g. --json]
  local r="$1" docs="$2" ledger="$3" ev="$4"; shift 4
  run next --roadmap "$r" --docs "$docs" --ledger "$ledger" --events "$ev" "$@"
}

test_1607_threshold_fires_at_count() {
  log_info "Test: waiting maintenance AT the threshold fires reason threshold (TEST-1607)..."
  local d="$TEST_DIR/t1607"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml"
  adv_roadmap "$roadmap" 4
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1607-a cap-other P2
  fu_add "$ledger" fu-t1607-b cap-other P2
  propose_write_doc "$docs" iss-t1607 issue draft
  propose_write_doc "$docs" td-t1607 techdebt draft
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1607: next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1607: must propose maintenance, got: $(out)"
  grep -qF '"reason":"threshold"' "$TEST_DIR/out" || log_fail "TEST-1607: reason must be threshold, got: $(out)"
  grep -qF '"waiting":{"count":4,"threshold":4}' "$TEST_DIR/out" || log_fail "TEST-1607: waiting must be count 4 of threshold 4, got: $(out)"
  log_pass "waiting maintenance at the threshold fires reason threshold (TEST-1607)"
}

test_1608_one_below_threshold_equals_off() {
  log_info "Test: waiting maintenance one below the threshold prints exactly the off answer, json and text, no stderr (TEST-1608)..."
  local d="$TEST_DIR/t1608"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" off="$d/roadmap-off.yaml"
  adv_roadmap "$roadmap" 5
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$off"
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1608-a cap-other P2
  fu_add "$ledger" fu-t1608-b cap-other P2
  propose_write_doc "$docs" iss-t1608 issue draft
  propose_write_doc "$docs" td-t1608 techdebt draft
  local flag
  for flag in --json x; do
    local ej oj sj eo oo so
    if [ "$flag" = "--json" ]; then
      ej="$(next_at "$roadmap" "$docs" "$ledger" "$d/ev1.jsonl" --json)"; oj="$(out)"; sj="$(err)"
      eo="$(run next --roadmap "$off" --docs "$docs" --json)"; oo="$(out)"; so="$(err)"
    else
      ej="$(next_at "$roadmap" "$docs" "$ledger" "$d/ev2.jsonl")"; oj="$(out)"; sj="$(err)"
      eo="$(run next --roadmap "$off" --docs "$docs")"; oo="$(out)"; so="$(err)"
    fi
    [ "$ej" = "$eo" ] || log_fail "TEST-1608: exit differs (flag=$flag): adv=$ej off=$eo"
    [ "$oj" = "$oo" ] || log_fail "TEST-1608: stdout differs (flag=$flag): [$oj] vs [$oo]"
    [ -z "$sj" ] || log_fail "TEST-1608: advisory stderr must be empty (flag=$flag): $sj"
    [ -z "$so" ] || log_fail "TEST-1608: off stderr must be empty (flag=$flag): $so"
  done
  log_pass "waiting maintenance one below the threshold equals the off answer, json and text, no stderr (TEST-1608)"
}

test_1609_p3_never_counts() {
  log_info "Test: open P3 follow-ups never count toward waiting maintenance (TEST-1609)..."
  local d="$TEST_DIR/t1609"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" off="$d/roadmap-off.yaml"
  adv_roadmap "$roadmap" 5
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$off"
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1609-a cap-other P2
  fu_add "$ledger" fu-t1609-b cap-other P2
  propose_write_doc "$docs" iss-t1609 issue draft
  propose_write_doc "$docs" td-t1609 techdebt draft
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do fu_add "$ledger" "fu-t1609-p3-$i" cap-other P3; done
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1609: next must exit 0: $(err)"
  [ "$(run next --roadmap "$off" --docs "$docs" --json)" = "0" ] || log_fail "TEST-1609: off next must exit 0"
  local off_out; off_out="$(out)"
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events2.jsonl" --json)" = "0" ] || log_fail "TEST-1609: next (rerun) must exit 0"
  [ "$(out)" = "$off_out" ] || log_fail "TEST-1609: ten open P3 follow-ups must never push waiting to the threshold, got: $(out)"
  # sanity check on fixture counts: exactly 0 P1 and 2 P2 are open (never the ten P3)
  node "$FOLLOWUPS" list --ledger "$ledger" --status open --json > "$TEST_DIR/fuout" 2> "$TEST_DIR/fuerr" \
    || log_fail "TEST-1609: follow-ups list failed: $(cat "$TEST_DIR/fuerr")"
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const p1 = j.items.filter((i) => i.severity === "P1").length;
    const p2 = j.items.filter((i) => i.severity === "P2").length;
    if (p1 !== 0 || p2 !== 2) { console.error("p1=" + p1 + " p2=" + p2); process.exit(1); }
  ' "$TEST_DIR/fuout" || log_fail "TEST-1609: fixture sanity check failed (expected P1 0, P2 2)"
  log_pass "open P3 follow-ups never count toward waiting maintenance (TEST-1609)"
}

test_1610_closed_followups_never_count() {
  log_info "Test: closed/dropped P1/P2 follow-ups never count; reopening one makes it fire (TEST-1610)..."
  local d="$TEST_DIR/t1610"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml"
  adv_roadmap "$roadmap" 5
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1610-a cap-other P2
  fu_add "$ledger" fu-t1610-b cap-other P2
  propose_write_doc "$docs" iss-t1610 issue draft
  propose_write_doc "$docs" td-t1610 techdebt draft
  fu_add "$ledger" fu-t1610-c cap-other P2
  fu_add "$ledger" fu-t1610-d cap-other P2
  fu_add "$ledger" fu-t1610-e cap-other P1
  fu_close "$ledger" fu-t1610-c done
  fu_close "$ledger" fu-t1610-d done
  fu_close "$ledger" fu-t1610-e dropped
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1610: next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" && log_fail "TEST-1610: closed/dropped items must not push waiting to the threshold: $(out)"
  # positive control: reopening one makes it count again, reaching the threshold
  node "$FOLLOWUPS" reopen --ledger "$ledger" --id fu-t1610-c --reason "still open" > /dev/null 2>&1 \
    || log_fail "TEST-1610: reopen failed"
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events2.jsonl" --json)" = "0" ] || log_fail "TEST-1610: next (reopened) must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1610: reopening fu-t1610-c must make the threshold fire, got: $(out)"
  log_pass "closed/dropped follow-ups never count; reopening one restores the count (TEST-1610)"
}

test_1611_terminal_intakes_never_count() {
  log_info "Test: terminal-status issue/techdebt intakes never count; an implementing one does (TEST-1611)..."
  local d="$TEST_DIR/t1611"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml"
  adv_roadmap "$roadmap" 5
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1611-a cap-other P2
  fu_add "$ledger" fu-t1611-b cap-other P2
  propose_write_doc "$docs" iss-t1611 issue draft
  propose_write_doc "$docs" td-t1611 techdebt draft
  propose_write_doc "$docs" done-t1611 issue done
  propose_write_doc "$docs" deferred-t1611 issue deferred
  propose_write_doc "$docs" rejected-t1611 techdebt rejected
  propose_write_doc "$docs" superseded-t1611 issue superseded
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1611: next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" && log_fail "TEST-1611: terminal-status intakes must not push waiting to the threshold: $(out)"
  propose_write_doc "$docs" impl-t1611 issue implementing
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events2.jsonl" --json)" = "0" ] || log_fail "TEST-1611: next (plus implementing) must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1611: an implementing issue intake must make the threshold fire, got: $(out)"
  log_pass "terminal-status intakes never count; a non-terminal one makes the threshold fire (TEST-1611)"
}

test_1612_change_intakes_never_count() {
  log_info "Test: draft change-type intakes never count toward waiting maintenance (TEST-1612)..."
  local d="$TEST_DIR/t1612"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml"
  # threshold 4: if the three change-type docs below counted too, W would be
  # 7 and this would still fire (uninformative); at 4 it fires ONLY if they
  # are excluded, so the exact waiting count proves the exclusion.
  adv_roadmap "$roadmap" 4
  propose_write_doc "$docs" zz-cap change draft
  fu_add "$ledger" fu-t1612-a cap-other P2
  fu_add "$ledger" fu-t1612-b cap-other P2
  propose_write_doc "$docs" iss-t1612 issue draft
  propose_write_doc "$docs" td-t1612 techdebt draft
  propose_write_doc "$docs" chg1-t1612 change draft
  propose_write_doc "$docs" chg2-t1612 change draft
  propose_write_doc "$docs" chg3-t1612 change draft
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1612: next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1612: with the three change docs excluded, waiting must reach the threshold, got: $(out)"
  grep -qF '"waiting":{"count":4,"threshold":4}' "$TEST_DIR/out" || log_fail "TEST-1612: waiting must be count 4 of threshold 4 (change docs excluded), got: $(out)"
  grep -qF 'chg1-t1612' "$TEST_DIR/out" && log_fail "TEST-1612: a change-type intake must never appear as a candidate: $(out)"
  log_pass "draft change-type intakes never count toward waiting maintenance (TEST-1612)"
}

test_1613_related_fires() {
  log_info "Test: an open P1/P2 follow-up referencing the most recently closed capability fires reason related (TEST-1613)..."
  local d="$TEST_DIR/t1613"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-b change draft
  events_closes "$events" "2026-10-01T00:00:00Z" cap-a
  fu_add "$ledger" fu-t1613-rel cap-a P2
  fu_add "$ledger" fu-t1613-unrel cap-zzz P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$events" --json)" = "0" ] || log_fail "TEST-1613: next must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1613: reason must be related, got: $(out)"
  grep -qF '"capability":"cap-a"' "$TEST_DIR/out" || log_fail "TEST-1613: capability must be cap-a, got: $(out)"
  grep -qF '"capability_source":"events"' "$TEST_DIR/out" || log_fail "TEST-1613: capability_source must be events, got: $(out)"
  grep -qF '"candidates":[{"kind":"follow_up","id":"fu-t1613-rel"' "$TEST_DIR/out" \
    || log_fail "TEST-1613: candidates must be exactly the cap-a follow-up, got: $(out)"
  grep -qF 'fu-t1613-unrel' "$TEST_DIR/out" && log_fail "TEST-1613: the unrelated follow-up must not appear in candidates: $(out)"
  log_pass "a related open follow-up fires reason related with capability and source (TEST-1613)"
}

test_1614_related_negations_equal_off() {
  log_info "Test: every related negation prints exactly the off answer (threshold not reached) (TEST-1614)..."
  local d="$TEST_DIR/t1614"; mkdir -p "$d"
  local roadmap="$d/roadmap.yaml" off="$d/roadmap-off.yaml" docs="$d/docs" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: planned\n' > "$roadmap"
  printf 'pairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: planned\n' > "$off"
  propose_write_doc "$docs" cap-b change draft
  events_closes "$events" "2026-10-01T00:00:00Z" cap-a
  events_closes "$events" "2026-09-01T00:00:00Z" cap-z

  # case 1: no follow-up at all for cap-a
  local ledger1="$d/ledger1.jsonl"
  fu_add "$ledger1" fu-t1614-other cap-zzz P2
  [ "$(next_at "$roadmap" "$docs" "$ledger1" "$events" --json)" = "0" ] || log_fail "TEST-1614: case1 next must exit 0: $(err)"
  local adv1; adv1="$(out)"
  [ "$(run next --roadmap "$off" --docs "$docs" --json)" = "0" ] || log_fail "TEST-1614: case1 off must exit 0"
  [ "$adv1" = "$(out)" ] || log_fail "TEST-1614: case1 (no related follow-up) must equal off, got: $adv1 vs $(out)"

  # case 2: only a P3 references cap-a
  local ledger2="$d/ledger2.jsonl"
  fu_add "$ledger2" fu-t1614-p3 cap-a P3
  [ "$(next_at "$roadmap" "$docs" "$ledger2" "$events" --json)" = "0" ] || log_fail "TEST-1614: case2 next must exit 0: $(err)"
  local adv2; adv2="$(out)"
  [ "$adv2" = "$(run next --roadmap "$off" --docs "$docs" --json >/dev/null; out)" ] \
    || log_fail "TEST-1614: case2 (only a P3 references cap-a) must equal off, got: $adv2"

  # case 3: the cap-a reference is closed (done)
  local ledger3="$d/ledger3.jsonl"
  fu_add "$ledger3" fu-t1614-closed cap-a P2
  fu_close "$ledger3" fu-t1614-closed done
  [ "$(next_at "$roadmap" "$docs" "$ledger3" "$events" --json)" = "0" ] || log_fail "TEST-1614: case3 next must exit 0: $(err)"
  local adv3; adv3="$(out)"
  [ "$(run next --roadmap "$off" --docs "$docs" --json)" = "0" ] || log_fail "TEST-1614: case3 off must exit 0"
  [ "$adv3" = "$(out)" ] || log_fail "TEST-1614: case3 (cap-a reference closed) must equal off, got: $adv3 vs $(out)"

  # case 4: the follow-up references an OLDER closed capability (cap-z), not the most recent (cap-a)
  local ledger4="$d/ledger4.jsonl"
  fu_add "$ledger4" fu-t1614-old cap-z P2
  [ "$(next_at "$roadmap" "$docs" "$ledger4" "$events" --json)" = "0" ] || log_fail "TEST-1614: case4 next must exit 0: $(err)"
  local adv4; adv4="$(out)"
  [ "$(run next --roadmap "$off" --docs "$docs" --json)" = "0" ] || log_fail "TEST-1614: case4 off must exit 0"
  [ "$adv4" = "$(out)" ] || log_fail "TEST-1614: case4 (follow-up references an older closed capability) must equal off, got: $adv4 vs $(out)"
  log_pass "every related negation (none, P3-only, closed, older-capability) equals the off answer (TEST-1614)"
}

test_1615_related_wins_over_threshold() {
  log_info "Test: when both triggers fire the reason is related (TEST-1615)..."
  local d="$TEST_DIR/t1615"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 1\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-b change draft
  events_closes "$events" "2026-10-01T00:00:00Z" cap-a
  fu_add "$ledger" fu-t1615-rel cap-a P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$events" --json)" = "0" ] || log_fail "TEST-1615: next must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1615: reason must be related even though threshold also fires, got: $(out)"
  grep -qF '"candidates":[{"kind":"follow_up","id":"fu-t1615-rel"' "$TEST_DIR/out" \
    || log_fail "TEST-1615: candidates must be only the related follow-up, not every counted item, got: $(out)"
  log_pass "when both triggers fire the reason is related, with only related candidates (TEST-1615)"
}

test_1616_latest_event_wins() {
  log_info "Test: the capability with the LATEST work_item_closed ts wins, not the earliest (TEST-1616)..."
  local d="$TEST_DIR/t1616"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: done\n  - capability: cap-c\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-c change draft
  events_closes "$events" "2026-10-01T10:00:00Z" cap-b
  events_closes "$events" "2026-10-01T11:00:00Z" cap-a
  fu_add "$ledger" fu-t1616-b cap-b P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$events" --json)" = "0" ] || log_fail "TEST-1616: next (ref to cap-b) must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" && log_fail "TEST-1616: cap-b is not the latest closed capability, related must not fire: $(out)"
  local ledger2="$d/ledger2.jsonl"
  fu_add "$ledger2" fu-t1616-a cap-a P2
  [ "$(next_at "$roadmap" "$docs" "$ledger2" "$events" --json)" = "0" ] || log_fail "TEST-1616: next (ref to cap-a) must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1616: cap-a (latest closed, 11:00) must fire related, got: $(out)"
  grep -qF '"capability":"cap-a"' "$TEST_DIR/out" || log_fail "TEST-1616: capability must be cap-a, got: $(out)"
  log_pass "the capability with the latest work_item_closed ts wins (TEST-1616)"
}

test_1617_tie_goes_to_later_pair() {
  log_info "Test: a timestamp tie goes to the pair listed later in the roadmap (TEST-1617)..."
  local d="$TEST_DIR/t1617"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: done\n  - capability: cap-c\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-c change draft
  events_closes "$events" "2026-10-01T10:00:00Z" cap-a
  events_closes "$events" "2026-10-01T10:00:00Z" cap-b
  fu_add "$ledger" fu-t1617-b cap-b P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$events" --json)" = "0" ] || log_fail "TEST-1617: next must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1617: a same-ts tie must resolve to cap-b (listed later), got: $(out)"
  grep -qF '"capability":"cap-b"' "$TEST_DIR/out" || log_fail "TEST-1617: capability must be cap-b (listed later), got: $(out)"
  log_pass "a timestamp tie resolves to the pair listed later in the roadmap (TEST-1617)"
}

test_1618_roadmap_order_fallback() {
  log_info "Test: with no matching event, C falls back to the last done pair in roadmap order (TEST-1618)..."
  local d="$TEST_DIR/t1618"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: done\n  - capability: cap-c\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-c change draft
  fu_add "$ledger" fu-t1618-b cap-b P2
  # absent EVENTS path
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/no-such-events.jsonl" --json)" = "0" ] || log_fail "TEST-1618: next (absent events) must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1618: absent EVENTS must still resolve C via roadmap order (cap-b), got: $(out)"
  grep -qF '"capability":"cap-b"' "$TEST_DIR/out" || log_fail "TEST-1618: capability must be cap-b, got: $(out)"
  grep -qF '"capability_source":"roadmap_order"' "$TEST_DIR/out" || log_fail "TEST-1618: capability_source must be roadmap_order, got: $(out)"
  # EVENTS present but its only close refs are spec-cap-a (prefixed, never matches) and an off-roadmap ref
  local events2="$d/events2.jsonl"
  events_closes "$events2" "2026-10-01T00:00:00Z" spec-cap-a
  events_closes "$events2" "2026-10-01T00:00:00Z" off-roadmap-ref
  local ledger2="$d/ledger2.jsonl"
  fu_add "$ledger2" fu-t1618-b2 cap-b P2
  [ "$(next_at "$roadmap" "$docs" "$ledger2" "$events2" --json)" = "0" ] || log_fail "TEST-1618: next (non-matching events) must exit 0: $(err)"
  grep -qF '"capability":"cap-b"' "$TEST_DIR/out" || log_fail "TEST-1618: a spec-prefixed ref must never match; C must still be cap-b, got: $(out)"
  grep -qF '"capability_source":"roadmap_order"' "$TEST_DIR/out" || log_fail "TEST-1618: capability_source must stay roadmap_order, got: $(out)"
  log_pass "with no matching event C falls back to the last done pair in roadmap order (TEST-1618)"
}

test_1619_events_beats_roadmap_order() {
  log_info "Test: an EVENTS close record wins over an undone-by-event-but-done pair earlier in the roadmap (TEST-1619)..."
  local d="$TEST_DIR/t1619"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" events="$d/events.jsonl"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: done\n  - capability: cap-b\n    status: done\n  - capability: cap-c\n    status: planned\n' > "$roadmap"
  propose_write_doc "$docs" cap-c change draft
  # cap-a (listed first) has an EVENTS close; cap-b (listed second, done without an event) does not
  events_closes "$events" "2026-10-01T00:00:00Z" cap-a
  fu_add "$ledger" fu-t1619-a cap-a P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$events" --json)" = "0" ] || log_fail "TEST-1619: next must exit 0: $(err)"
  grep -qF '"reason":"related"' "$TEST_DIR/out" || log_fail "TEST-1619: related must fire for cap-a: $(out)"
  grep -qF '"capability":"cap-a"' "$TEST_DIR/out" || log_fail "TEST-1619: capability must be cap-a (the one WITH an EVENTS close), got: $(out)"
  grep -qF '"capability_source":"events"' "$TEST_DIR/out" || log_fail "TEST-1619: capability_source must be events, got: $(out)"
  log_pass "an EVENTS close record wins over a later-in-roadmap done pair with no event (TEST-1619)"
}

test_1620_no_done_pair_no_events_related_cannot_fire() {
  log_info "Test: with no done pair and no EVENTS, related cannot fire even when a follow-up references the planned last capability (TEST-1620)..."
  local d="$TEST_DIR/t1620"; mkdir -p "$d"
  local ledger="$d/ledger.jsonl" docs="$d/docs" roadmap="$d/roadmap.yaml" off="$d/roadmap-off.yaml"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\n' > "$roadmap"
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\n' > "$off"
  fu_add "$ledger" fu-t1620-b cap-b P2
  [ "$(next_at "$roadmap" "$docs" "$ledger" "$d/no-such-events.jsonl" --json)" = "0" ] || log_fail "TEST-1620: next must exit 0: $(err)"
  local adv; adv="$(out)"
  [ "$(run next --roadmap "$off" --docs "$docs" --json)" = "0" ] || log_fail "TEST-1620: off next must exit 0"
  [ "$adv" = "$(out)" ] || log_fail "TEST-1620: with no done pair and no events, related cannot fire; must equal off, got: $adv vs $(out)"
  log_pass "with no done pair and no EVENTS, related cannot fire; equals off (TEST-1620)"
}

# --- Proposal shape, waiting, show, degrade (Spec-AC-07..09, TEST-1621..1630) -
# D6's exact key order and the shared off helper (so `alternative` cannot
# drift), D6's severity/cap candidate ordering, D7's degrade, D8's read-only
# `waiting` query and D9's `show` advisory line/key.

test_1621_proposal_shape_and_alternative() {
  log_info "Test: the proposal carries D6's exact key order and alternative deep-equals the off next --json for all three alternative kinds (TEST-1621)..."
  local d="$TEST_DIR/t1621"; mkdir -p "$d"

  # case A: next-with-path (a documented, not-yet-started capability-only pair)
  local da="$d/a" ledgerA="$d/a-ledger.jsonl"
  mkdir -p "$da/docs"
  adv_roadmap "$da/roadmap.yaml" 2
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$da/off.yaml"
  propose_write_doc "$da/docs" zz-cap change draft
  fu_add "$ledgerA" fu-t1621a-1 cap-other P2
  fu_add "$ledgerA" fu-t1621a-2 cap-other P2
  [ "$(next_at "$da/roadmap.yaml" "$da/docs" "$ledgerA" "$da/events.jsonl" --json)" = "0" ] || log_fail "TEST-1621 case a: next must exit 0: $(err)"
  cp "$TEST_DIR/out" "$da/adv.json"
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const expected = ["action","reason","capability","capability_source","waiting","candidates","alternative"];
    if (JSON.stringify(Object.keys(j)) !== JSON.stringify(expected)) { console.error("keys=" + JSON.stringify(Object.keys(j))); process.exit(1); }
  ' "$da/adv.json" || log_fail "TEST-1621 case a: proposal key order must be D6's exact order"
  [ "$(run next --roadmap "$da/off.yaml" --docs "$da/docs" --json)" = "0" ] || log_fail "TEST-1621 case a: off next must exit 0"
  cp "$TEST_DIR/out" "$da/off.json"
  node -e '
    const adv = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const off = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
    if (JSON.stringify(adv.alternative) !== JSON.stringify(off)) { console.error("alt=" + JSON.stringify(adv.alternative) + " off=" + JSON.stringify(off)); process.exit(1); }
  ' "$da/adv.json" "$da/off.json" || log_fail "TEST-1621 case a: alternative must deep-equal the off next --json object (next-with-path)"

  # case B: file-intake (same shape, but the capability has no document yet)
  local db="$d/b" ledgerB="$d/b-ledger.jsonl"
  mkdir -p "$db/docs"
  adv_roadmap "$db/roadmap.yaml" 2
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$db/off.yaml"
  fu_add "$ledgerB" fu-t1621b-1 cap-other P2
  fu_add "$ledgerB" fu-t1621b-2 cap-other P2
  [ "$(next_at "$db/roadmap.yaml" "$db/docs" "$ledgerB" "$db/events.jsonl" --json)" = "0" ] || log_fail "TEST-1621 case b: next must exit 0: $(err)"
  cp "$TEST_DIR/out" "$db/adv.json"
  [ "$(run next --roadmap "$db/off.yaml" --docs "$db/docs" --json)" = "0" ] || log_fail "TEST-1621 case b: off next must exit 0"
  cp "$TEST_DIR/out" "$db/off.json"
  node -e '
    const adv = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const off = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
    if (adv.alternative.action !== "file-intake") { console.error("not file-intake: " + JSON.stringify(adv.alternative)); process.exit(1); }
    if (JSON.stringify(adv.alternative) !== JSON.stringify(off)) { console.error("alt=" + JSON.stringify(adv.alternative) + " off=" + JSON.stringify(off)); process.exit(1); }
  ' "$db/adv.json" "$db/off.json" || log_fail "TEST-1621 case b: alternative must deep-equal the off next --json object (file-intake)"

  # case C: all-done (wave_1 complete)
  local dc="$d/c" ledgerC="$d/c-ledger.jsonl"
  mkdir -p "$dc/docs"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 2\npairs:\n  - capability: cap-a\n    status: done\nwave_2:\n  - later-thing\n' > "$dc/roadmap.yaml"
  printf 'pairs:\n  - capability: cap-a\n    status: done\nwave_2:\n  - later-thing\n' > "$dc/off.yaml"
  fu_add "$ledgerC" fu-t1621c-1 cap-other P2
  fu_add "$ledgerC" fu-t1621c-2 cap-other P2
  [ "$(next_at "$dc/roadmap.yaml" "$dc/docs" "$ledgerC" "$dc/events.jsonl" --json)" = "0" ] || log_fail "TEST-1621 case c: next must exit 0: $(err)"
  cp "$TEST_DIR/out" "$dc/adv.json"
  [ "$(run next --roadmap "$dc/off.yaml" --docs "$dc/docs" --json)" = "0" ] || log_fail "TEST-1621 case c: off next must exit 0"
  cp "$TEST_DIR/out" "$dc/off.json"
  node -e '
    const adv = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const off = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
    if (adv.alternative.wave_1 !== "complete") { console.error("not wave_1 complete: " + JSON.stringify(adv.alternative)); process.exit(1); }
    if (JSON.stringify(adv.alternative) !== JSON.stringify(off)) { console.error("alt=" + JSON.stringify(adv.alternative) + " off=" + JSON.stringify(off)); process.exit(1); }
  ' "$dc/adv.json" "$dc/off.json" || log_fail "TEST-1621 case c: alternative must deep-equal the off next --json object (wave_1 complete)"

  log_pass "proposal keys match D6 order and alternative equals off for all three kinds (TEST-1621)"
}

test_1622_advisory_never_binds() {
  log_info "Test: advisory next never prints action bind, firing or not; the on variant of the same fixture does (positive control) (TEST-1622)..."
  local d="$TEST_DIR/t1622"; mkdir -p "$d/docs"
  local ledger="$d/ledger.jsonl" roadmap_adv="$d/adv.yaml" roadmap_on="$d/on.yaml"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 2\npairs:\n  - capability: zz-cap\n    status: planned\n' > "$roadmap_adv"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: zz-cap\n    status: planned\n' > "$roadmap_on"
  propose_write_doc "$d/docs" zz-cap change implementing

  # trigger NOT firing (no counted items)
  [ "$(next_at "$roadmap_adv" "$d/docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1622: advisory (not firing) next must exit 0: $(err)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" && log_fail "TEST-1622: advisory (not firing) must never print action bind: $(out)"

  # trigger firing
  fu_add "$ledger" fu-t1622-a cap-other P2
  fu_add "$ledger" fu-t1622-b cap-other P2
  [ "$(next_at "$roadmap_adv" "$d/docs" "$ledger" "$d/events2.jsonl" --json)" = "0" ] || log_fail "TEST-1622: advisory (firing) next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1622: advisory must fire for this fixture, got: $(out)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" && log_fail "TEST-1622: advisory (firing) must never print action bind: $(out)"

  # positive control: the SAME fixture under the on (1:1) posture DOES print bind
  [ "$(run next --roadmap "$roadmap_on" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1622: on-variant next must exit 0: $(err)"
  grep -qF '"action":"bind"' "$TEST_DIR/out" || log_fail "TEST-1622: on-variant must print action bind as a positive control, got: $(out)"
  log_pass "advisory never prints action bind, firing or not; the on variant does (TEST-1622)"
}

test_1623_candidate_order_by_severity() {
  log_info "Test: candidates rank P1 before P2 (fold order within each), then intakes by id, cap 5 (TEST-1623)..."
  local d="$TEST_DIR/t1623"; mkdir -p "$d"

  # case 1: 1 P1 + 4 P2 + 2 intakes at threshold 3 -> exactly 5 candidates, P1 first then P2 oldest-first
  local d1="$d/1"
  local ledger1="$d1/ledger.jsonl" docs1="$d1/docs"
  mkdir -p "$docs1"
  adv_roadmap "$d1/roadmap.yaml" 3
  propose_write_doc "$docs1" zz-cap change draft
  fu_add "$ledger1" fu-t1623-p1 cap-other P1
  fu_add "$ledger1" fu-t1623-p2a cap-other P2
  fu_add "$ledger1" fu-t1623-p2b cap-other P2
  fu_add "$ledger1" fu-t1623-p2c cap-other P2
  fu_add "$ledger1" fu-t1623-p2d cap-other P2
  propose_write_doc "$docs1" iss-t1623-1 issue draft
  propose_write_doc "$docs1" td-t1623-1 techdebt draft
  [ "$(next_at "$d1/roadmap.yaml" "$docs1" "$ledger1" "$d1/events.jsonl" --json)" = "0" ] || log_fail "TEST-1623: case1 next must exit 0: $(err)"
  local ids1; ids1="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(j.candidates.map((c) => c.id).join(","));
  ' "$TEST_DIR/out")"
  [ "$ids1" = "fu-t1623-p1,fu-t1623-p2a,fu-t1623-p2b,fu-t1623-p2c,fu-t1623-p2d" ] \
    || log_fail "TEST-1623: case1 candidate order/cap wrong, got: $ids1"

  # case 2: 1 P1 + 1 P2 + 2 intakes at threshold 3 -> all 4, order P1, P2, intakes by id
  local d2="$d/2"
  local ledger2="$d2/ledger.jsonl" docs2="$d2/docs"
  mkdir -p "$docs2"
  adv_roadmap "$d2/roadmap.yaml" 3
  propose_write_doc "$docs2" zz-cap change draft
  fu_add "$ledger2" fu-t1623b-p1 cap-other P1
  fu_add "$ledger2" fu-t1623b-p2 cap-other P2
  propose_write_doc "$docs2" zz-t1623b-issue issue draft
  propose_write_doc "$docs2" aa-t1623b-techdebt techdebt draft
  [ "$(next_at "$d2/roadmap.yaml" "$docs2" "$ledger2" "$d2/events.jsonl" --json)" = "0" ] || log_fail "TEST-1623: case2 next must exit 0: $(err)"
  local ids2; ids2="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(j.candidates.map((c) => c.id).join(","));
  ' "$TEST_DIR/out")"
  [ "$ids2" = "fu-t1623b-p1,fu-t1623b-p2,aa-t1623b-techdebt,zz-t1623b-issue" ] \
    || log_fail "TEST-1623: case2 order (P1, P2, intakes by id) wrong, got: $ids2"
  log_pass "candidates rank P1 before P2 and intakes by id, capped at 5 (TEST-1623)"
}

test_1624_candidate_cap_five() {
  log_info "Test: candidates are capped at 5 even when more items are waiting (TEST-1624)..."
  local d="$TEST_DIR/t1624"; mkdir -p "$d/docs"
  local ledger="$d/ledger.jsonl" roadmap="$d/roadmap.yaml"
  adv_roadmap "$roadmap" 3
  propose_write_doc "$d/docs" zz-cap change draft
  local i
  for i in 1 2 3 4 5 6; do fu_add "$ledger" "fu-t1624-$i" cap-other P2; done
  propose_write_doc "$d/docs" iss-t1624 issue draft
  propose_write_doc "$d/docs" td-t1624 techdebt draft
  [ "$(next_at "$roadmap" "$d/docs" "$ledger" "$d/events.jsonl" --json)" = "0" ] || log_fail "TEST-1624: next must exit 0: $(err)"
  grep -qF '"waiting":{"count":8,"threshold":3}' "$TEST_DIR/out" || log_fail "TEST-1624: waiting must be count 8 of threshold 3, got: $(out)"
  local n; n="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(j.candidates.length));
  ' "$TEST_DIR/out")"
  [ "$n" = "5" ] || log_fail "TEST-1624: candidates must be capped at exactly 5, got: $n ($(out))"
  log_pass "candidates are capped at exactly 5 regardless of how many are waiting (TEST-1624)"
}

test_1625_text_form_three_lines() {
  log_info "Test: next without --json on a firing fixture prints exactly D6's three lines (TEST-1625)..."
  local d="$TEST_DIR/t1625"; mkdir -p "$d/docs"
  local ledger="$d/ledger.jsonl" roadmap="$d/roadmap.yaml" off="$d/off.yaml"
  adv_roadmap "$roadmap" 2
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$off"
  propose_write_doc "$d/docs" zz-cap change draft
  fu_add "$ledger" fu-t1625-a cap-other P2
  fu_add "$ledger" fu-t1625-b cap-other P2
  [ "$(next_at "$roadmap" "$d/docs" "$ledger" "$d/events.jsonl")" = "0" ] || log_fail "TEST-1625: next must exit 0: $(err)"
  cp "$TEST_DIR/out" "$d/adv.txt"
  local n_lines; n_lines="$(wc -l < "$d/adv.txt" | tr -d ' ')"
  [ "$n_lines" = "3" ] || log_fail "TEST-1625: must print exactly three lines, got $n_lines: $(cat "$d/adv.txt")"
  local line1 line2 line3
  line1="$(sed -n '1p' "$d/adv.txt")"
  line2="$(sed -n '2p' "$d/adv.txt")"
  line3="$(sed -n '3p' "$d/adv.txt")"
  case "$line1" in
    'maintenance proposed (threshold): '*) : ;;
    *) log_fail "TEST-1625: line 1 wrong: $line1" ;;
  esac
  case "$line2" in
    'waiting: '*) : ;;
    *) log_fail "TEST-1625: line 2 wrong: $line2" ;;
  esac
  case "$line3" in
    'or continue with: '*) : ;;
    *) log_fail "TEST-1625: line 3 wrong: $line3" ;;
  esac
  [ "$(run next --roadmap "$off" --docs "$d/docs")" = "0" ] || log_fail "TEST-1625: off (text) next must exit 0"
  local off_text; off_text="$(out)"
  local last_line; last_line="$line3"
  [ "$last_line" = "or continue with: $off_text" ] || log_fail "TEST-1625: line 3 must end with the off text answer, got [$last_line] vs off=[$off_text]"
  log_pass "the text form prints exactly D6's three lines, the third ending with the off answer (TEST-1625)"
}

test_1626_degrade_on_unreadable_ledger() {
  log_info "Test: an unreadable --ledger degrades next to the off answer with a stderr note; an absent ledger still counts intakes (TEST-1626)..."
  local d="$TEST_DIR/t1626"; mkdir -p "$d/docs"
  local roadmap="$d/roadmap.yaml" off="$d/off.yaml" baddir="$d/ledger-is-a-dir"
  mkdir -p "$baddir"
  adv_roadmap "$roadmap" 3
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$off"
  propose_write_doc "$d/docs" zz-cap change draft
  [ "$(next_at "$roadmap" "$d/docs" "$baddir" "$d/events.jsonl")" = "0" ] || log_fail "TEST-1626: next with an unreadable ledger must still exit 0: $(err)"
  local adv_out; adv_out="$(out)"
  local adv_err; adv_err="$(err)"
  [ "$(run next --roadmap "$off" --docs "$d/docs")" = "0" ] || log_fail "TEST-1626: off next must exit 0"
  [ "$adv_out" = "$(out)" ] || log_fail "TEST-1626: stdout must equal the off answer, got: $adv_out vs $(out)"
  case "$adv_err" in
    "ride-select: advisory not evaluated — "*) : ;;
    *) log_fail "TEST-1626: stderr must start 'ride-select: advisory not evaluated — ', got: $adv_err" ;;
  esac

  # absent ledger path + three draft issues at threshold 3: fires, counting intakes only
  local d2="$d/absent"
  local ledger2="$d2/no-such-ledger.jsonl"
  mkdir -p "$d2/docs"
  local roadmap2="$d2/roadmap.yaml"
  adv_roadmap "$roadmap2" 3
  propose_write_doc "$d2/docs" zz-cap change draft
  propose_write_doc "$d2/docs" iss-t1626-1 issue draft
  propose_write_doc "$d2/docs" iss-t1626-2 issue draft
  propose_write_doc "$d2/docs" iss-t1626-3 issue draft
  [ "$(next_at "$roadmap2" "$d2/docs" "$ledger2" "$d2/events.jsonl" --json)" = "0" ] || log_fail "TEST-1626: next (absent ledger) must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1626: an absent ledger must still count the three draft issue intakes and fire, got: $(out)"
  [ -z "$(err)" ] || log_fail "TEST-1626: an absent ledger (ENOENT) must not degrade (no stderr), got: $(err)"
  log_pass "an unreadable ledger degrades to the off answer; an absent one still counts intakes (TEST-1626)"
}

test_1627_on_off_unaffected_by_ledger_events() {
  log_info "Test: on/off next ignores --ledger/--events entirely, even when they point at directories (TEST-1627)..."
  local d="$TEST_DIR/t1627"; mkdir -p "$d/docs"
  local baddir="$d/not-a-file"; mkdir -p "$baddir"
  propose_write_doc "$d/docs" zz-cap change draft

  local off="$d/off.yaml" on="$d/on.yaml"
  printf 'pairs:\n  - capability: zz-cap\n    status: planned\n' > "$off"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: zz-cap\n    status: planned\n' > "$on"

  local r
  for r in "$off" "$on"; do
    [ "$(run next --roadmap "$r" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1627: $r baseline next must exit 0: $(err)"
    local base_out; base_out="$(out)"
    local base_err; base_err="$(err)"
    [ "$(run next --roadmap "$r" --docs "$d/docs" --ledger "$baddir" --events "$baddir" --json)" = "0" ] \
      || log_fail "TEST-1627: $r next with directory --ledger/--events must still exit 0: $(err)"
    [ "$base_out" = "$(out)" ] || log_fail "TEST-1627: $r stdout must be unaffected by --ledger/--events, got: $base_out vs $(out)"
    [ "$base_err" = "$(err)" ] || log_fail "TEST-1627: $r stderr must be unaffected by --ledger/--events (both empty), got: [$base_err] vs [$(err)]"
  done
  log_pass "on/off next ignores --ledger/--events entirely (TEST-1627)"
}

test_1628_waiting_counts_and_recommended_threshold() {
  log_info "Test: waiting --json reports D8's counts and recommended_threshold = max(5, W+5), read-only, with no roadmap present (TEST-1628)..."
  local d="$TEST_DIR/t1628"; mkdir -p "$d/docs/issues"
  local ledger="$d/ledger.jsonl"
  fu_add "$ledger" fu-t1628-p1 cap-other P1
  fu_add "$ledger" fu-t1628-p2a cap-other P2
  fu_add "$ledger" fu-t1628-p2b cap-other P2
  propose_write_doc "$d/docs" iss-t1628-1 issue draft
  propose_write_doc "$d/docs" iss-t1628-2 issue draft
  propose_write_doc "$d/docs" td-t1628-1 techdebt draft
  local ledger_before; ledger_before="$(sha "$ledger")"
  local docs_before; docs_before="$(dirhash "$d/docs")"
  [ "$(run waiting --docs "$d/docs" --ledger "$ledger" --json)" = "0" ] || log_fail "TEST-1628: waiting must exit 0: $(err)"
  grep -qF '"count":6' "$TEST_DIR/out" || log_fail "TEST-1628: count must be 6, got: $(out)"
  grep -qF '"follow_ups":{"P1":1,"P2":2}' "$TEST_DIR/out" || log_fail "TEST-1628: follow_ups must be P1 1 P2 2, got: $(out)"
  grep -qF '"intakes":{"issue":2,"techdebt":1}' "$TEST_DIR/out" || log_fail "TEST-1628: intakes must be issue 2 techdebt 1, got: $(out)"
  grep -qF '"recommended_threshold":11' "$TEST_DIR/out" || log_fail "TEST-1628: recommended_threshold must be 11 (max(5, 6+5)), got: $(out)"
  local ledger_after; ledger_after="$(sha "$ledger")"
  local docs_after; docs_after="$(dirhash "$d/docs")"
  [ "$ledger_before" = "$ledger_after" ] || log_fail "TEST-1628: waiting must never write the ledger"
  [ "$docs_before" = "$docs_after" ] || log_fail "TEST-1628: waiting must never write the docs tree"

  # floor: with zero waiting items recommended_threshold is still at least 5
  local d2="$d/empty"; mkdir -p "$d2/docs"
  local ledger2="$d2/ledger.jsonl"
  : > "$ledger2"
  [ "$(run waiting --docs "$d2/docs" --ledger "$ledger2" --json)" = "0" ] || log_fail "TEST-1628: waiting (empty) must exit 0: $(err)"
  grep -qF '"count":0' "$TEST_DIR/out" || log_fail "TEST-1628: count must be 0 with nothing waiting, got: $(out)"
  grep -qF '"recommended_threshold":5' "$TEST_DIR/out" || log_fail "TEST-1628: recommended_threshold must floor at 5, got: $(out)"
  log_pass "waiting reports D8's counts, recommended_threshold, and never writes (TEST-1628)"
}

test_1629_waiting_unreadable_and_absent_ledger() {
  log_info "Test: waiting exits 2 naming an unreadable ledger; an absent ledger exits 0 counting intakes only (TEST-1629)..."
  local d="$TEST_DIR/t1629"; mkdir -p "$d/docs"
  local baddir="$d/ledger-is-a-dir"; mkdir -p "$baddir"
  [ "$(run waiting --docs "$d/docs" --ledger "$baddir" --json)" = "2" ] || log_fail "TEST-1629: waiting with a directory ledger must exit 2: $(out) $(err)"
  grep -q "$baddir" "$TEST_DIR/err" || log_fail "TEST-1629: the exit-2 refusal must name the ledger path, got: $(err)"

  propose_write_doc "$d/docs" iss-t1629-1 issue draft
  propose_write_doc "$d/docs" iss-t1629-2 issue draft
  [ "$(run waiting --docs "$d/docs" --ledger "$d/no-such-ledger.jsonl" --json)" = "0" ] \
    || log_fail "TEST-1629: waiting with an absent ledger must exit 0: $(err)"
  grep -qF '"count":2' "$TEST_DIR/out" || log_fail "TEST-1629: an absent ledger must still count intakes, got: $(out)"
  grep -qF '"follow_ups":{"P1":0,"P2":0}' "$TEST_DIR/out" || log_fail "TEST-1629: an absent ledger folds to zero follow-ups, got: $(out)"
  log_pass "waiting exits 2 on an unreadable ledger; an absent ledger counts intakes only (TEST-1629)"
}

test_1630_show_advisory() {
  log_info "Test: show prints the advisory line and json carries the advisory key; on/off show stays unchanged (TEST-1630)..."
  local d="$TEST_DIR/t1630"; mkdir -p "$d/docs"
  local roadmap="$d/roadmap.yaml"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 7\npairs:\n  - capability: cap-a\n    status: planned\n' > "$roadmap"
  propose_write_doc "$d/docs" cap-a change draft
  [ "$(run show --roadmap "$roadmap" --docs "$d/docs")" = "0" ] || log_fail "TEST-1630: show must exit 0: $(err)"
  [ "$(sed -n '1p' "$TEST_DIR/out")" = "maintenance budget: advisory (threshold 7)" ] \
    || log_fail "TEST-1630: show first line wrong, got: $(sed -n '1p' "$TEST_DIR/out")"
  [ "$(run show --roadmap "$roadmap" --docs "$d/docs" --json)" = "0" ] || log_fail "TEST-1630: show --json must exit 0: $(err)"
  grep -qF '"budget":false' "$TEST_DIR/out" || log_fail "TEST-1630: show --json must keep budget false, got: $(out)"
  grep -qF '"advisory":{"maintenance_threshold":7}' "$TEST_DIR/out" || log_fail "TEST-1630: show --json must carry the advisory key, got: $(out)"
  test_1309_show
  log_pass "show prints the advisory posture line and json key; TEST-1309 still passes (TEST-1630)"
}

# --- TEST-1645 (Spec-AC-08, validation round 1 NB2): an issue/techdebt doc --
# with no frontmatter `id` still counts toward W, and its candidate gets a
# derived (non-empty) id instead of a hole in the shape.
test_1645_intake_without_id_gets_derived_id() {
  log_info "Test: an issue doc with no frontmatter id still counts and gets a derived candidate id, never an empty one (TEST-1645)..."
  local d="$TEST_DIR/t1645"; mkdir -p "$d/docs/issues"
  adv_roadmap "$d/roadmap.yaml" 1
  propose_write_doc "$d/docs" zz-cap change draft
  # No `id:` line at all — the exact shape NB2 named.
  printf -- '---\nnumber: null\ntype: issue\nstatus: draft\nlinks:\n  pr: []\n---\n\n# no id\n' \
    > "$d/docs/issues/ISSUE-DRAFT-t1645-no-id.md"
  [ "$(next_at "$d/roadmap.yaml" "$d/docs" "$d/ledger.jsonl" "$d/events.jsonl" --json)" = "0" ] \
    || log_fail "TEST-1645: next must exit 0: $(err)"
  grep -qF '"action":"propose_maintenance"' "$TEST_DIR/out" || log_fail "TEST-1645: must propose maintenance, got: $(out)"
  local id; id="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(j.candidates.length ? (j.candidates[0].id ?? "__NULL__") : "__EMPTY__");
  ' "$TEST_DIR/out")"
  [ -n "$id" ] || log_fail "TEST-1645: candidate id must not be empty"
  [ "$id" != "__NULL__" ] || log_fail "TEST-1645: candidate id must not be null/undefined: $(out)"
  [ "$id" != "__EMPTY__" ] || log_fail "TEST-1645: must yield at least one candidate: $(out)"
  [ "$id" = "ISSUE-DRAFT-t1645-no-id" ] \
    || log_fail "TEST-1645: id-less doc must derive its id from the filename stem (docs-model convention), got: $id"
  # The text form must not print a trailing/doubled comma around the hole
  # the original report reproduced ("...: fu-x-one, fu-x-two, ").
  [ "$(next_at "$d/roadmap.yaml" "$d/docs" "$d/ledger.jsonl" "$d/events2.jsonl")" = "0" ] \
    || log_fail "TEST-1645: text-form next must exit 0: $(err)"
  case "$(out)" in
    *", "$'\n'*|*", "$) log_fail "TEST-1645: text form must not trail with an empty id after a comma: $(out)" ;;
  esac
  grep -qF 'ISSUE-DRAFT-t1645-no-id' "$TEST_DIR/out" || log_fail "TEST-1645: text form must name the derived id, got: $(out)"
  log_pass "an id-less issue doc counts and gets a derived candidate id (TEST-1645)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$ENGINE" ] || log_fail "engine missing: $ENGINE"
  [ -f "$SHIPPED" ] || log_fail "shipped roadmap missing: $SHIPPED"
  [ -f "$PROPOSE" ] || log_fail "roadmap-propose.mjs missing: $PROPOSE"
  if [ $# -gt 0 ]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return
  fi
  test_001_validate
  test_002_next
  test_003_pair_first
  test_004_off_roadmap_fix
  test_005_fail_closed
  test_006_override
  test_007_wiring
  test_1202_absent_admit_is_side_effect_free
  test_1203_malformed_and_empty_refuse
  test_1204_directory_refuses
  test_1205_validate_next_unchanged_on_absent
  test_1217_unstatable_roadmap_refuses
  test_1206_usage_checks_before_absent
  test_1208_default_roadmap_refuses_off_roadmap
  test_1209_header_and_rule4_state_the_switch
  test_565_gate_admits_only_the_next_pair
  test_566_validate_refuses_unknown_refs
  test_535_roadmap_pair_seven_done
  test_583_gate_refuses_undocumented_ref
  test_588_gate_intake_requires_a_real_document
  test_715_validate_unbound_maintenance_slot
  test_716_validate_skips_unbound_doc_check
  test_717_nlb_seam_unbound_maintenance
  test_718_validate_shipped_regression
  test_719_next_proposes_bind
  test_720_next_bind_names_command
  test_721_next_offers_harvest_when_exhausted
  test_722_gate_refusal_names_bind
  test_723_harvest_prints_ranking_components
  test_724_harvest_intake_capability_types_only
  test_725_harvest_wave2_excludes_paired
  test_726_harvest_direction_movement
  test_727_harvest_direction_is_primary_key
  test_728_harvest_tokenize_filters_short_tokens
  test_729_harvest_observations_movement
  test_730_harvest_closed_followup_ignored
  test_731_harvest_blocks_in_movement
  test_732_harvest_terminal_blocker_ignored
  test_733_harvest_age_tiebreak
  test_734_harvest_untracked_age_unknown
  test_735_harvest_friction_review_candidates_only
  test_736_harvest_friction_label_never_hash
  test_737_harvest_empty_spool_note
  test_747_harvest_dedupes_by_id
  test_738_write_appends_and_certifies
  test_739_write_certifies_via_real_child_process
  test_740_write_rollback_on_refused_certification
  test_741_bind_refuses_unknown_ref
  test_742_bind_adds_maintenance_line_and_certifies
  test_743_opt_out_leaves_no_file
  test_744_no_automatic_invocation_site
  test_748_harvest_row_numbers_and_write_pick_fidelity
  test_749_write_requires_direction
  test_750_write_direction_value_drives_pick
  test_751_bind_refuses_roadmap_capability_ref
  test_752_write_promotes_wave2_slug_and_removes_it
  test_753_harvest_excludes_already_paired_intake
  test_754_gate_pair_ahead_never_prints_null
  test_755_gate_doc_missing_never_prints_null
  test_756_write_discloses_gate_turned_on
  test_757_bind_no_type_denylist
  test_758_bind_refuses_ref_bound_elsewhere
  test_759_gate_bind_remedy_succeeds
  test_760_next_stops_proposing_dead_ref
  test_761_promotion_leaves_other_wave2_entries
  test_762_next_stops_proposing_dead_capability_ref
  test_763_harvest_surfaces_followups_understated_note
  test_764_harvest_surfaces_corrupt_spool_note
  test_765_harvest_dedup_keeps_friction_recurrence
  test_1301_validate_accepts_no_budget
  test_1302_budget_block_stays_strict
  test_1303_nobudget_gate_admits
  test_1304_nobudget_gate_still_refuses
  test_1305_budget_gate_unchanged
  test_1306_nobudget_next_never_binds
  test_1307_nobudget_next_skips_done_capability_doc
  test_1308_next_json_carries_path
  test_1309_show
  test_1310_write_seed_has_no_budget
  test_1600_validate_accepts_advisory_block
  test_1601_threshold_shapes_refuse
  test_1602_mode_shapes_refuse
  test_1603_mode_and_threshold_duplicates_refuse
  test_1604_combined_and_unknown_key_refuse
  test_1605_empty_block_and_regression
  test_1606_gate_advisory_equals_off
  test_1607_threshold_fires_at_count
  test_1608_one_below_threshold_equals_off
  test_1609_p3_never_counts
  test_1610_closed_followups_never_count
  test_1611_terminal_intakes_never_count
  test_1612_change_intakes_never_count
  test_1613_related_fires
  test_1614_related_negations_equal_off
  test_1615_related_wins_over_threshold
  test_1616_latest_event_wins
  test_1617_tie_goes_to_later_pair
  test_1618_roadmap_order_fallback
  test_1619_events_beats_roadmap_order
  test_1620_no_done_pair_no_events_related_cannot_fire
  test_1621_proposal_shape_and_alternative
  test_1622_advisory_never_binds
  test_1623_candidate_order_by_severity
  test_1624_candidate_cap_five
  test_1625_text_form_three_lines
  test_1626_degrade_on_unreadable_ledger
  test_1627_on_off_unaffected_by_ledger_events
  test_1628_waiting_counts_and_recommended_threshold
  test_1629_waiting_unreadable_and_absent_ledger
  test_1630_show_advisory
  test_1645_intake_without_id_gets_derived_id
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
