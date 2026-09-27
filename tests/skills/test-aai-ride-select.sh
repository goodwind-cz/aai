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
  [ "$(run validate --roadmap "$TEST_DIR/bad4.yaml")" = "2" ] || log_fail "TEST-001: a roadmap without budget must exit 2 (closed shape)"
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
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/nope.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-005: a missing roadmap must refuse"
  grep -qi "roadmap" "$TEST_DIR/err" || log_fail "TEST-005: the refusal must name the roadmap"
  printf 'this: is\n  - not: the shape\n' > "$TEST_DIR/junk.yaml"
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/junk.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-005: an invalid roadmap must refuse"
  grep -q "closed roadmap shape" "$TEST_DIR/err" || log_fail "TEST-005: the invalid-roadmap refusal must name the parse reason: $(err)"
  write_roadmap planned; write_doc cap-one change done
  [ "$(run gate --ref cap-one --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" != "0" ] || log_fail "TEST-005: a done ref must be refused as done"
  grep -qi "done" "$TEST_DIR/err" || log_fail "TEST-005: the refusal must say the ref is done"
  log_pass "fail closed on missing/invalid roadmap and on a done ref (TEST-005)"
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
    grep -qi "not on the roadmap" "$TEST_DIR/err" \
      || log_fail "TEST-583: the live refusal must say the fixture ref is not on the roadmap: $(err)"
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
  ( cd "$NLBROOT" && git init -q && git add -A && git commit -q -m "feat: nlb717-cap ships" )
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
  [ "$(out)" = "roadmap OK: 11 pair(s), 4 wave-2 item(s)" ] \
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
  [ "$(run_propose write --pick 1 --roadmap "$ROADMAP" --docs "$D" --ledger "$TEST_DIR/p743-ledger.jsonl" --spool "$TEST_DIR/p743-spool.jsonl")" = "1" ] \
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
  local SCAN_PATTERN='roadmap-propose'
  local hits
  hits="$(/usr/bin/grep -rl "$SCAN_PATTERN" "$PROJECT_ROOT"/.aai/*.prompt.md "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" 2>/dev/null || true)"
  [ -z "$hits" ] || log_fail "TEST-744: no .aai prompt or orchestration-dispatch.mjs may invoke roadmap-propose automatically, found: $hits"
  log_pass "no prompt or dispatch branch invokes roadmap-propose automatically (TEST-744)"
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
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
