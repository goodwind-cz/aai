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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$PROJECT_ROOT/.aai/scripts/ride-select.mjs"
SHIPPED="$PROJECT_ROOT/docs/ai/roadmap.yaml"

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

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$ENGINE" ] || log_fail "engine missing: $ENGINE"
  [ -f "$SHIPPED" ] || log_fail "shipped roadmap missing: $SHIPPED"
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
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
