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
  # a capability on the roadmap always passes, regardless of anything
  [ "$(run gate --ref cap-two --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs")" = "0" ] || log_fail "TEST-003: a roadmap capability must always pass: $(err)"
  log_pass "pair first: refused, then allowed; a capability always passes (TEST-003)"
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

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$ENGINE" ] || log_fail "engine missing: $ENGINE"
  [ -f "$SHIPPED" ] || log_fail "shipped roadmap missing: $SHIPPED"
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_validate
  test_002_next
  test_003_pair_first
  test_004_off_roadmap_fix
  test_005_fail_closed
  test_006_override
  test_007_wiring
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
