#!/usr/bin/env bash
#
# Test: route-independent close-ceremony gate (ride ref
# close-ceremony-fires-only-via-aai-pr, docs/specs/
# SPEC-0175-spec-close-ceremony-fires-only-via-aai-pr.md, TEST-001..013).
#
# Covers .aai/scripts/close-reconcile.mjs (the gate CLI: reads a pushed
# range on the default branch with git alone, names every work-item doc the
# range delivered but left non-terminal, and with --apply closes each by
# SPAWNING the real close-work-item.mjs — never re-implementing it) and
# .github/workflows/close-gate.yml (the CI job that fails loud on push to
# main when the ceremony did not run before merge).
#
#   - TEST-001 (Spec-AC-01): frozen_work_merged arm — a range that leaves a
#     non-terminal doc at status implementing exits 1, naming doc/arm/sha/the
#     close-work-item remediation command. (AMENDED 2026-09-11: the
#     code_with_open_doc arm this test originally exercised was removed on an
#     owner decision — see the spec's `## Amendment` section, item 1.)
#   - TEST-002 (Spec-AC-02): intake-only range (adds a draft doc, touches
#     nothing else) fires neither arm -> exit 0 CLEAN.
#   - TEST-003 (Spec-AC-03): --apply closes the doc via the REAL
#     close-work-item.mjs; a paired DRAFT-intake + IMPLEMENTING-spec pair
#     (the shape this corpus actually produces — spec-freeze.mjs never
#     writes `implementing` to an intake) closes BOTH in ONE invocation;
#     re-check is CLEAN; a second --apply over the now-all-terminal range is
#     a CLEAN no-op (idempotent); a SEPARATE half-closed fixture (spec
#     already `done`, primary still `draft`, both in the same range) proves
#     --check never reports CLEAN over it. (REMEDIATION ROUND 3, BLOCKING-1:
#     the pre-fix fixture paired two docs that both independently reached
#     `implementing`, a shape the corpus never produces and that never
#     exercised pairItems()'s primary-from-spec gap.)
#   - TEST-004 (Spec-AC-03, SEAM S3): EVENTS.jsonl pre-apply bytes stay a
#     byte-exact prefix of the post-apply file; docs-audit --check --strict
#     --no-event is clean over the fixture afterwards.
#   - TEST-005 (Spec-AC-04): close-work-item.mjs's content hash is on the
#     shared allowlist (tests/skills/lib/close-work-item-pin.sh, three
#     consuming suites); close-reconcile.mjs contains no direct file write
#     of its own.
#   - TEST-006 (Spec-AC-05): no commit subject in the range carries a
#     trailing (#N) -> --apply refuses by name, exits non-zero, the doc's
#     bytes are unchanged.
#   - TEST-007 (Spec-AC-06): missing/empty/all-zero/unresolvable --range
#     each exit 2 naming the offending value, in both --check and --apply.
#   - TEST-008 (Spec-AC-07, structure): close-gate.yml triggers on push to
#     main, invokes close-reconcile.mjs --check, carries no
#     continue-on-error key.
#   - TEST-009 (Spec-AC-07, S4 seam): the workflow's OWN embedded
#     range-resolution script (extracted verbatim, never re-typed) is
#     replayed against a non-clean fixture and exits non-zero with a line
#     beginning ::error::.
#   - TEST-010 (Spec-AC-08): a ride merged WITHOUT /aai-pr / SKILL_PR, whose
#     INTAKE doc stays `draft` throughout (the corpus-real shape) while its
#     paired spec reaches `implementing`, ends the INTAKE `status: done`
#     once the gate's own --check/--apply run. (AMENDED 2026-09-12, code
#     review round 3: the pre-amendment fixture put the intake itself at
#     `implementing`, a state 0 of 268 docs/issues docs have ever carried —
#     spec-freeze.mjs is the sole writer of that status and writes it only
#     to docs/specs/** — so the AC was proven on a shape the corpus never
#     produces. See the spec's `## Amendment` item 5.)
#   - TEST-011 (Spec-AC-08, MUTATION control): first exercises the REAL
#     $CLOSE_RECONCILE on the SAME draft-intake/implementing-spec pair
#     (fails if it is missing or degraded to a no-op); then a
#     close-reconcile STUBBED to always exit 0 leaves the intake in `draft`
#     — proves TEST-010's green depends on the real script actually
#     running, not merely on a stub that agrees with it.
#   - TEST-012 (Spec-AC-09): PROFILES.yaml classifies the new file exactly
#     once; suite-map.yaml maps the CLI + the workflow under one suite row.
#   - TEST-013 (Spec-AC-10, BLOCKING-2): a frontmatter `umbrella: true`
#     parent never fires, even while it reads `status: implementing` —
#     matching docs-audit-core.mjs's OWN umbrella predicate, not a second,
#     weaker notion of it.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-002: zero items, CLEAN
#   - zero-remainder                -> TEST-003 second --apply: an
#                                      already-all-terminal range is a
#                                      CLEAN no-op
#   - multi-source/multi-writer      -> TEST-003: a paired issue+spec doc
#                                      closes in ONE close-work-item.mjs
#                                      invocation
#   - mid-operation failure           -> TEST-006: pr-number-unknown
#                                      fail-closed abort, nothing written
#                                      (close-work-item.mjs's OWN D6
#                                      snapshot/rollback transaction is
#                                      PROTECTED/out of scope for this
#                                      ride, so a write-time partial-abort
#                                      fixture cannot legitimately live here)
#   - negative control                -> TEST-011: the mutation control
#
# ALL fixtures are throwaway git repos under a mktemp dir, cleaned on EXIT.
# The real repo's docs/ and docs/ai/EVENTS.jsonl are NEVER touched — every
# invocation under test runs with --root pointed at the fixture.
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-close-reconcile.sh            # run all tests
#   bash tests/skills/test-aai-close-reconcile.sh test_002_intake_only_range_is_clean
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-close-reconcile"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CLOSE_RECONCILE="$PROJECT_ROOT/.aai/scripts/close-reconcile.mjs"
CLOSE_WORK_ITEM="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
CLOSE_GATE_YML="$PROJECT_ROOT/.github/workflows/close-gate.yml"

# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
# shellcheck source=lib/close-work-item-pin.sh
. "$SCRIPT_DIR/lib/close-work-item-pin.sh"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$CLOSE_WORK_ITEM" ]] || log_fail "close-work-item.mjs not found: $CLOSE_WORK_ITEM"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  # NOTE: CLOSE_RECONCILE and CLOSE_GATE_YML are intentionally NOT required
  # here — TEST-001..007/010 and TEST-008/009 RED naturally (invocation
  # fails / file absent) while they do not yet exist, per the spec's own
  # RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-close-reconcile-test.XXXXXX")"
}

# --- fixture repo builder ----------------------------------------------------

# init_range_repo <name> -> prints the fixture repo's absolute path. A
# throwaway git repo with docs/{issues,specs}, src/, docs/ai/EVENTS.jsonl
# (empty), docs/ai/docs-audit.yaml (report-only), one seed commit on main.
# Every scenario then adds its own commits on top and passes the resulting
# <seed-or-later>..<head> range.
init_range_repo() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/issues" "$dir/docs/specs" "$dir/docs/ai" "$dir/src"
  : > "$dir/docs/ai/EVENTS.jsonl"
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  echo "seed" > "$dir/README.md"
  git init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  echo "$dir"
}

# write_issue_doc <path> <id> <status>
write_issue_doc() {
  local path="$1" id="$2" status="$3"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
id: $id
type: issue
status: $status
links:
  pr: []
  commits: []
---

# Issue — Fixture $id

## Summary
- fixture doc for close-reconcile tests.
EOF
}

# write_spec_doc <path> <id> <status>
write_spec_doc() {
  local path="$1" id="$2" status="$3"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
id: $id
type: spec
number: null
status: $status
ceremony_level: 2
links:
  requirement: null
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture $id

SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture | done | commit-abc | — | — |

## Test Plan

| Test ID | Spec-AC | Type | File path | Description | Status |
|---------|---------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a | fixture | green |
EOF
}

# write_umbrella_doc <path> <id> <status> — a deliberately-open multi-phase
# parent (BLOCKING-2): same shape as write_issue_doc plus frontmatter
# `umbrella: true`.
write_umbrella_doc() {
  local path="$1" id="$2" status="$3"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
---
id: $id
type: rfc
status: $status
umbrella: true
links:
  pr: []
  commits: []
---

# RFC — Fixture $id (umbrella parent)

## Summary
- fixture umbrella-parent doc for close-reconcile tests.
EOF
}

# seed_make_unreadable <path> -> 0 if this uid is actually denied read access
# after chmod 000, 1 if not (root/CI perm bypass — same shape as
# test-aai-suite-isolation.sh's helper of the same name; chmod denies
# nothing to root, so an arm that assumed it worked would measure a
# perfectly-seeded run and call it a bug).
seed_make_unreadable() {
  chmod 000 "$1" 2>/dev/null
  if cat "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# --- TEST-001 (Spec-AC-01) ---------------------------------------------------
test_001_open_range_reports_doc_arm_sha_remediation() {
  log_info "TEST-001 (Spec-AC-01): a non-terminal doc left status:implementing -> --check exits 1, names doc/arm/sha/remediation..."
  local dir base head out rc
  dir=$(init_range_repo "t001")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0001-t001.md" "t001-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t001 (#101)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-001: expected exit 1, got $rc. Output:\n$out"
  assert_payload_contains "$out" "OPEN docs/issues/ISSUE-0001-t001.md" "TEST-001: missing OPEN line for the doc"
  assert_payload_contains "$out" "id=t001-ref" "TEST-001: missing id=t001-ref"
  assert_payload_contains "$out" "arm=frozen_work_merged" "TEST-001: missing arm=frozen_work_merged"
  assert_payload_contains "$out" "sha=$head" "TEST-001: missing sha=$head"
  assert_payload_contains "$out" "node .aai/scripts/close-work-item.mjs --ref t001-ref" "TEST-001: missing the remediation command"
  log_pass "TEST-001: frozen_work_merged arm reports doc/arm/sha/remediation, exits 1"
}

# --- TEST-002 (Spec-AC-02) ---------------------------------------------------
test_002_intake_only_range_is_clean() {
  log_info "TEST-002 (Spec-AC-02): a range that only adds a draft doc and touches nothing else -> exit 0 CLEAN..."
  local dir base head out rc
  dir=$(init_range_repo "t002")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0002-t002.md" "t002-ref" "draft"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "intake t002 (#102)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-002: expected exit 0, got $rc. Output:\n$out"
  assert_payload_contains "$out" "CLEAN" "TEST-002: expected CLEAN in output"
  log_pass "TEST-002: intake-only range is CLEAN, exits 0"
}

# --- TEST-003 (Spec-AC-03) ---------------------------------------------------
test_003_apply_closes_paired_docs_recheck_clean_idempotent() {
  log_info "TEST-003 (Spec-AC-03): --apply closes a DRAFT-intake + IMPLEMENTING-spec pair in ONE invocation, re-check CLEAN, second apply is a no-op..."
  local dir base head out rc out2 rc2 out3 rc3
  dir=$(init_range_repo "t003")
  base=$(git -C "$dir" rev-parse HEAD)
  # BLOCKING-1 (REMEDIATION ROUND 3): the primary is `draft`, the ONLY
  # status this corpus's intake docs ever carry pre-close — spec-freeze.mjs
  # never writes `implementing` to a docs/issues doc. Pairing the primary
  # with an already-`implementing` spec fixture (as this test did
  # pre-remediation) never exercised pairItems()'s primary-from-spec gap.
  write_issue_doc "$dir/docs/issues/ISSUE-0003-t003.md" "t003-ref" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0003-t003.md" "spec-t003-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t003 (#103)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-003: expected exit 0 from --apply, got $rc. Output:\n$out"
  assert_payload_contains "$out" "CLOSED docs/issues/ISSUE-0003-t003.md" "TEST-003: missing CLOSED confirmation for the primary doc"

  grep -q "^status: done" "$dir/docs/issues/ISSUE-0003-t003.md" || log_fail "TEST-003: primary doc frontmatter status not flipped to done"
  grep -qF "    - 103" "$dir/docs/issues/ISSUE-0003-t003.md" || log_fail "TEST-003: primary doc links.pr does not carry 103"
  grep -qF "    - $head" "$dir/docs/issues/ISSUE-0003-t003.md" || log_fail "TEST-003: primary doc links.commits does not carry the delivery sha"

  # multi-source/multi-writer: the paired spec closed in the SAME transaction.
  grep -q "^status: done" "$dir/docs/specs/SPEC-0003-t003.md" || log_fail "TEST-003: paired spec doc was not closed alongside its primary doc"

  out2="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 0 ]] || log_fail "TEST-003: re-check expected exit 0, got $rc2. Output:\n$out2"
  assert_payload_contains "$out2" "CLEAN" "TEST-003: re-check expected CLEAN"

  # zero-remainder: a second --apply over an already-all-terminal range is a
  # clean no-op, not a second write.
  out3="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc3=0 || rc3=$?
  [[ "$rc3" -eq 0 ]] || log_fail "TEST-003: second --apply (zero-remainder) expected exit 0, got $rc3. Output:\n$out3"
  assert_payload_contains "$out3" "CLEAN" "TEST-003: second --apply expected CLEAN (nothing left to apply)"

  # BLOCKING-1 regression guard — a pair that was only HALF closed (the
  # spec already flipped to `done`, the primary left at its original
  # non-terminal status — exactly the corruption issue #352 reports, and
  # the state a pre-fix --apply left behind) must NEVER read CLEAN. Built
  # fresh so it does not depend on --apply's own correctness above.
  local dir2 base2 head2 out4 rc4
  dir2=$(init_range_repo "t003half")
  base2=$(git -C "$dir2" rev-parse HEAD)
  write_issue_doc "$dir2/docs/issues/ISSUE-0003-t003half.md" "t003half-ref" "draft"
  write_spec_doc "$dir2/docs/specs/SPEC-0003-t003half.md" "spec-t003half-ref" "done"
  echo "changed" >> "$dir2/src/app.js"
  git -C "$dir2" add -A
  git -C "$dir2" commit -q -m "half-closed pair t003half (#1003)"
  head2=$(git -C "$dir2" rev-parse HEAD)

  out4="$(node "$CLOSE_RECONCILE" --check --range "$base2..$head2" --root "$dir2" 2>&1)" && rc4=0 || rc4=$?
  [[ "$rc4" -eq 1 ]] || log_fail "TEST-003: a half-closed pair (spec done, primary still draft) must not report CLEAN, got rc=$rc4. Output:\n$out4"
  assert_payload_contains "$out4" "OPEN docs/issues/ISSUE-0003-t003half.md" "TEST-003: half-closed pair must still name the un-closed primary"
  assert_payload_not_contains "$out4" "close-reconcile: CLEAN" "TEST-003: half-closed pair must not report CLEAN"

  log_pass "TEST-003: apply closes a draft-intake+implementing-spec pair in one transaction; re-check CLEAN; idempotent on a second apply; a half-closed pair never reads CLEAN"
}

# --- TEST-004 (Spec-AC-03, SEAM S3) ------------------------------------------
test_004_apply_preserves_events_prefix_and_audit_clean() {
  log_info "TEST-004 (Spec-AC-03, SEAM S3): EVENTS.jsonl stays a byte-exact prefix through --apply; docs-audit --check --strict clean..."
  local dir base head before out rc audit_rc
  dir=$(init_range_repo "t004")
  echo '{"v":1,"ts":"2020-01-01T00:00:00Z","event":"doc_lifecycle","ref":"unrelated-seed-doc","from":"draft","to":"done","actor":"test"}' >> "$dir/docs/ai/EVENTS.jsonl"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed events"
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0004-t004.md" "t004-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t004 (#104)"
  head=$(git -C "$dir" rev-parse HEAD)

  before="$(cat "$dir/docs/ai/EVENTS.jsonl")"
  out="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-004: expected exit 0, got $rc. Output:\n$out"

  head -c "${#before}" "$dir/docs/ai/EVENTS.jsonl" | diff -q - <(printf '%s' "$before") >/dev/null \
    || log_fail "TEST-004: EVENTS.jsonl pre-apply bytes are not a byte-exact prefix of the post-apply file"

  ( cd "$dir" && node "$DOCS_AUDIT" --check --strict --no-event ) > "$TEST_DIR/t004-audit.log" 2>&1 && audit_rc=0 || audit_rc=$?
  [[ "$audit_rc" -eq 0 ]] || log_fail "TEST-004: docs-audit --check --strict --no-event not clean over the fixture: $(cat "$TEST_DIR/t004-audit.log")"

  log_pass "TEST-004: EVENTS.jsonl append-only through apply; docs-audit clean"
}

# --- TEST-005 (Spec-AC-04) ---------------------------------------------------
test_005_close_work_item_untouched_and_no_own_writes() {
  log_info "TEST-005 (Spec-AC-04): close-work-item.mjs content is on the shared hash-pin allowlist; close-reconcile.mjs writes no doc path of its own..."
  [[ -f "$CLOSE_RECONCILE" ]] || log_fail "TEST-005: close-reconcile.mjs does not exist yet"
  # review remediation (test-framework-sweep, code review NB-1): this used
  # to be a raw `git diff --quiet` against HEAD, which reads any LEGITIMATE,
  # reviewed, re-pinned edit to close-work-item.mjs (tests/skills/lib/
  # close-work-item-pin.sh's own stated, intended path — "growing the list
  # is the INTENDED path for a legitimate future edit") as a failure, purely
  # because the edit had not yet been committed — a false negative on the
  # exact ride this ceremony runs uncommitted-until-close. The shared
  # allowlist this file already vendors is the real guard (a reviewed,
  # itemized re-affirmation of both frozen invariants, keyed off CONTENT,
  # not commit status); reuse it instead of a second, weaker, independent
  # check on the same file (this suite is now the THIRD consumer of the
  # shared pin in tests/skills/lib/close-work-item-pin.sh, alongside
  # test-aai-doc-numbering.sh and test-aai-follow-ups.sh).
  local pin_result
  pin_result="$(close_work_item_pin_assert "$PROJECT_ROOT")" \
    || log_fail "TEST-005: $pin_result"
  local hits
  hits=$(grep -c "fs\.writeFileSync\|fs\.appendFileSync\|fs\.writeFile\b" "$CLOSE_RECONCILE" 2>/dev/null || true)
  [[ "${hits:-0}" -eq 0 ]] || log_fail "TEST-005: close-reconcile.mjs writes a file directly (${hits} occurrence(s)) — all mutation must go through close-work-item.mjs"
  log_pass "TEST-005: close-work-item.mjs content is on the shared pin allowlist ($pin_result); close-reconcile.mjs owns no write of its own"
}

# --- TEST-006 (Spec-AC-05) ---------------------------------------------------
test_006_apply_refuses_when_pr_number_unknown() {
  log_info "TEST-006 (Spec-AC-05): no commit subject in the range carries a PR number -> --apply refuses, exits non-zero, doc unchanged..."
  local dir base head before after out rc
  dir=$(init_range_repo "t006")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0006-t006.md" "t006-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t006 without a PR number"
  head=$(git -C "$dir" rev-parse HEAD)

  before="$(cat "$dir/docs/issues/ISSUE-0006-t006.md")"
  out="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-006: expected non-zero exit, got 0. Output:\n$out"
  assert_payload_contains "$out" "pr-number-unknown" "TEST-006: expected reason=pr-number-unknown in output"
  after="$(cat "$dir/docs/issues/ISSUE-0006-t006.md")"
  [[ "$before" == "$after" ]] || log_fail "TEST-006: doc bytes changed despite the pr-number-unknown refusal"
  log_pass "TEST-006: pr-number-unknown refuses the apply, exits non-zero, writes nothing"
}

# --- TEST-007 (Spec-AC-06) ---------------------------------------------------
test_007_range_validation_fail_closed() {
  log_info "TEST-007 (Spec-AC-06): missing/empty/all-zero/unresolvable --range each exit 2, in both modes..."
  local dir out rc mode
  dir=$(init_range_repo "t007")

  for mode in check apply; do
    out="$(node "$CLOSE_RECONCILE" "--$mode" --root "$dir" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || log_fail "TEST-007 ($mode, missing): expected exit 2, got $rc. Output:\n$out"
    assert_payload_contains "$out" "range" "TEST-007 ($mode, missing): message does not mention the range"

    out="$(node "$CLOSE_RECONCILE" "--$mode" --range "" --root "$dir" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || log_fail "TEST-007 ($mode, empty): expected exit 2, got $rc. Output:\n$out"

    out="$(node "$CLOSE_RECONCILE" "--$mode" --range "0000000000000000000000000000000000000000..HEAD" --root "$dir" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || log_fail "TEST-007 ($mode, all-zero): expected exit 2, got $rc. Output:\n$out"
    assert_payload_contains "$out" "0000000000000000000000000000000000000000..HEAD" "TEST-007 ($mode, all-zero): message does not name the offending value"

    out="$(node "$CLOSE_RECONCILE" "--$mode" --range "not-a-real-ref..also-not-real" --root "$dir" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 2 ]] || log_fail "TEST-007 ($mode, unresolvable): expected exit 2, got $rc. Output:\n$out"
    assert_payload_contains "$out" "not-a-real-ref..also-not-real" "TEST-007 ($mode, unresolvable): message does not name the offending value"
  done

  log_pass "TEST-007: missing/empty/all-zero/unresolvable --range fail-closed at exit 2 in both modes, naming the value"
}

# --- TEST-008 (Spec-AC-07, structure) ----------------------------------------
test_008_workflow_structure() {
  log_info "TEST-008 (Spec-AC-07): close-gate.yml triggers on push to main, invokes close-reconcile.mjs --check, no continue-on-error..."
  [[ -f "$CLOSE_GATE_YML" ]] || log_fail "TEST-008: .github/workflows/close-gate.yml does not exist"
  grep -q "^on:" "$CLOSE_GATE_YML" || log_fail "TEST-008: missing on: trigger block"
  grep -q "push:" "$CLOSE_GATE_YML" || log_fail "TEST-008: missing push: trigger"
  grep -Eq "branches:[[:space:]]*\[main\]|- main" "$CLOSE_GATE_YML" || log_fail "TEST-008: missing branches: [main]"
  grep -qF "close-reconcile.mjs" "$CLOSE_GATE_YML" || log_fail "TEST-008: does not invoke close-reconcile.mjs"
  grep -q -- "--check" "$CLOSE_GATE_YML" || log_fail "TEST-008: does not invoke --check"
  grep -q "continue-on-error" "$CLOSE_GATE_YML" && log_fail "TEST-008: carries a continue-on-error key — must fail loud, no report-only dial"
  log_pass "TEST-008: close-gate.yml structure matches Spec-AC-07"
}

# --- TEST-009 (Spec-AC-07, S4 seam) ------------------------------------------
test_009_workflow_command_replay_behavioral() {
  log_info "TEST-009 (Spec-AC-07, S4): replaying the workflow's own range-resolution script against a non-clean fixture exits non-zero with ::error::..."
  [[ -f "$CLOSE_GATE_YML" ]] || log_fail "TEST-009: .github/workflows/close-gate.yml does not exist"
  local script
  script="$TEST_DIR/t009-script.sh"
  sed -n '/# BEGIN close-gate-range/,/# END close-gate-range/p' "$CLOSE_GATE_YML" | sed '1d;$d' > "$script"
  [[ -s "$script" ]] || log_fail "TEST-009: could not extract the close-gate-range script from $CLOSE_GATE_YML"

  local dir base head out rc
  dir=$(init_range_repo "t009")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0009-t009.md" "t009-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t009 (#109)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(RANGE_BEFORE="$base" RANGE_SHA="$head" \
      CLOSE_RECONCILE_BIN="$CLOSE_RECONCILE" CLOSE_RECONCILE_ROOT="$dir" \
      bash "$script" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-009: expected the replayed script to exit non-zero over a non-clean fixture. Output:\n$out"
  assert_payload_contains "$out" "::error::" "TEST-009: expected a line beginning with ::error::"
  log_pass "TEST-009: the workflow's own script exits non-zero and emits an ::error:: annotation over a non-clean fixture"
}

# --- TEST-010 (Spec-AC-08) ---------------------------------------------------
test_010_e2e_route_independent_close() {
  log_info "TEST-010 (Spec-AC-08): a ride merged WITHOUT /aai-pr ends its INTAKE doc done via the route-independent gate..."
  local dir base head out_check rc_check out_apply rc_apply
  dir=$(init_range_repo "t010")
  base=$(git -C "$dir" rev-parse HEAD)
  # AMENDED 2026-09-12 (code review round 3, spec_compliance non-compliant):
  # the intake stays `draft` — the ONLY status this corpus's intake docs
  # ever carry pre-close — and its PAIRED spec is what reaches
  # `implementing`, matching the real shape spec-freeze.mjs and
  # close-work-item.mjs produce. A fixture that put the intake itself at
  # `implementing` proved the AC on a state 0 of 268 docs/issues docs have
  # ever carried.
  write_issue_doc "$dir/docs/issues/ISSUE-0010-t010.md" "t010-ref" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0010-t010.md" "spec-t010-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "merge t010 without SKILL_PR (#110)"
  head=$(git -C "$dir" rev-parse HEAD)

  out_check="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc_check=0 || rc_check=$?
  [[ "$rc_check" -ne 0 ]] || log_fail "TEST-010: gate --check should have flagged the skipped ceremony. Output:\n$out_check"

  out_apply="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc_apply=0 || rc_apply=$?
  [[ "$rc_apply" -eq 0 ]] || log_fail "TEST-010: gate --apply should have closed the ride. Output:\n$out_apply"

  grep -q "^status: done" "$dir/docs/issues/ISSUE-0010-t010.md" \
    || log_fail "TEST-010: the INTAKE doc did not end status: done despite the ride never invoking /aai-pr"
  log_pass "TEST-010: a ride merged without /aai-pr still ends its INTAKE doc done via the route-independent gate"
}

# --- TEST-011 (Spec-AC-08, MUTATION control) ---------------------------------
test_011_mutation_control_stub_leaves_draft() {
  log_info "TEST-011 (Spec-AC-08, MUTATION control): a close-reconcile stubbed to always exit 0 leaves the doc in draft..."
  local dir base head stub out rc

  # This control is only meaningful if it EXERCISES $CLOSE_RECONCILE — the
  # real binary, the same path TEST-010 invokes. A prior version of this
  # test built its own throwaway stub and never touched $CLOSE_RECONCILE at
  # all, so it passed unchanged whether the real script existed, worked, or
  # was deleted (measured: PASSES with close-reconcile.mjs DELETED from the
  # tree). Fail loud, before building anything, if there is nothing to
  # mutate.
  [[ -f "$CLOSE_RECONCILE" ]] || log_fail "TEST-011: close-reconcile.mjs not found at $CLOSE_RECONCILE — nothing to mutate, this control cannot prove anything"

  dir=$(init_range_repo "t011")
  base=$(git -C "$dir" rev-parse HEAD)
  # AMENDED 2026-09-12 (code review round 3): the SAME draft-intake +
  # implementing-spec pair TEST-010 uses — see its comment for why.
  write_issue_doc "$dir/docs/issues/ISSUE-0011-t011.md" "t011-ref" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0011-t011.md" "spec-t011-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "merge t011 without SKILL_PR (#111)"
  head=$(git -C "$dir" rev-parse HEAD)

  # Step A — exercise the REAL binary on this fixture first. This is the
  # part that makes the control non-vacuous: it FAILS (this test goes RED)
  # if close-reconcile.mjs is absent (node cannot find the module, so rc
  # will not be 1 and/or the payload will not name the arm) or has itself
  # regressed to a no-op that always reports CLEAN (rc would be 0, not 1).
  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-011: the REAL close-reconcile.mjs did not flag this fixture (rc=$rc, expected 1) — it is missing, broken, or degraded to a no-op, so this control cannot prove anything. Output:\n$out"
  assert_payload_contains "$out" "arm=frozen_work_merged" "TEST-011: the REAL close-reconcile.mjs did not name arm=frozen_work_merged"

  # Step B — the MUTATION itself: a close-reconcile that has regressed to
  # always exit 0 and never spawn close-work-item.mjs, run over the SAME
  # fixture Step A just proved the real binary flags. close-reconcile.mjs
  # itself is never edited (HAZ-RESTORE) — the mutation lives only in this
  # throwaway stub file.
  stub="$TEST_DIR/t011-stub-close-reconcile.mjs"
  cat > "$stub" <<'JS'
// MUTATION control stub — always reports clean/success and never spawns
// close-work-item.mjs, regardless of --range/--root/--check/--apply. Used
// ONLY to prove TEST-010's green depends on the REAL script running.
console.log('close-reconcile: CLEAN (stub)');
process.exit(0);
JS

  out="$(node "$stub" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-011: stub --check should always exit 0. Output:\n$out"
  out="$(node "$stub" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-011: stub --apply should always exit 0. Output:\n$out"

  grep -q "^status: draft" "$dir/docs/issues/ISSUE-0011-t011.md" \
    || log_fail "TEST-011: MUTATION control expected the INTAKE doc to stay at its original non-terminal status (the stub never really closes anything) — TEST-010 is not proving anything if this fails"
  log_pass "TEST-011: the REAL binary flags this fixture (rc=1, arm=frozen_work_merged), and the stubbed gate leaves the intake doc non-terminal, proving TEST-010's green depends on the real script running"
}

# --- TEST-012 (Spec-AC-09) ---------------------------------------------------
test_012_profiles_and_suite_map_wiring() {
  log_info "TEST-012 (Spec-AC-09): PROFILES.yaml classifies close-reconcile.mjs exactly once; suite-map.yaml maps CLI + workflow..."
  local profiles map hits
  profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  hits=$(grep -c "\.aai/scripts/close-reconcile\.mjs" "$profiles" 2>/dev/null || true)
  [[ "${hits:-0}" -eq 1 ]] || log_fail "TEST-012: PROFILES.yaml should classify .aai/scripts/close-reconcile.mjs exactly once, found ${hits:-0}"

  map="$PROJECT_ROOT/tests/skills/suite-map.yaml"
  grep -q "aai-close-reconcile:" "$map" || log_fail "TEST-012: suite-map.yaml missing the aai-close-reconcile: row"
  awk '/aai-close-reconcile:/{f=1;next} /^  aai-[a-z-]+:/{f=0} f' "$map" > "$TEST_DIR/t012-block.txt"
  grep -qF ".aai/scripts/close-reconcile.mjs" "$TEST_DIR/t012-block.txt" || log_fail "TEST-012: suite-map row does not glob the CLI"
  grep -qF ".github/workflows/close-gate.yml" "$TEST_DIR/t012-block.txt" || log_fail "TEST-012: suite-map row does not glob the workflow"

  log_pass "TEST-012: PROFILES.yaml + suite-map.yaml wiring is correct (green run of the two neighbour suites is asserted separately per the Evidence Contract)"
}

# --- TEST-013 (Spec-AC-10, BLOCKING-2) ---------------------------------------
test_013_umbrella_parent_is_exempt() {
  log_info "TEST-013 (Spec-AC-10, BLOCKING-2): a frontmatter umbrella: true parent never fires, even at status implementing..."
  local dir base head out rc
  dir=$(init_range_repo "t013")
  base=$(git -C "$dir" rev-parse HEAD)
  write_umbrella_doc "$dir/docs/rfc/RFC-0013-t013.md" "t013-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "phase 2 lands on the still-open umbrella parent (#113)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-013: expected exit 0 CLEAN over an umbrella parent, got $rc. Output:\n$out"
  assert_payload_contains "$out" "CLEAN" "TEST-013: expected CLEAN — the umbrella marker exempts the parent"
  log_pass "TEST-013: umbrella: true parent is exempt even while status: implementing"
}

# --- TEST-014 (Spec-AC-11, REMEDIATION ROUND 4, Codex P1 / PR #372 bot review) ---
test_014_attribution_is_resolved_per_item_not_per_range() {
  log_info "TEST-014 (Spec-AC-11): a range carrying TWO delivery commits attributes EACH item to the commit that touched IT, not to the range's newest commit..."
  local dir base head1 head out rc

  dir=$(init_range_repo "t014")
  base=$(git -C "$dir" rev-parse HEAD)

  write_issue_doc "$dir/docs/issues/ISSUE-0014-t014a.md" "t014a-ref" "implementing"
  echo "changed a" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver a (#201)"
  head1=$(git -C "$dir" rev-parse HEAD)

  write_issue_doc "$dir/docs/issues/ISSUE-0014-t014b.md" "t014b-ref" "implementing"
  echo "changed b" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver b (#202)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-014: expected exit 1, got $rc. Output:\n$out"
  assert_payload_contains "$out" "OPEN docs/issues/ISSUE-0014-t014a.md id=t014a-ref arm=frozen_work_merged sha=$head1" \
    "TEST-014: item a must carry ITS OWN delivery sha ($head1), not the range's newest ($head)"
  assert_payload_contains "$out" "remediation: node .aai/scripts/close-work-item.mjs --ref t014a-ref --pr 201 --commit $head1" \
    "TEST-014: item a's remediation command must carry PR 201 and sha $head1, resolved from the commit that touched item a"
  assert_payload_contains "$out" "OPEN docs/issues/ISSUE-0014-t014b.md id=t014b-ref arm=frozen_work_merged sha=$head" \
    "TEST-014: item b must carry its own delivery sha ($head)"
  assert_payload_contains "$out" "remediation: node .aai/scripts/close-work-item.mjs --ref t014b-ref --pr 202 --commit $head" \
    "TEST-014: item b's remediation command must carry PR 202 and sha $head"

  out="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-014: expected exit 0 from --apply, got $rc. Output:\n$out"

  grep -qF "    - 201" "$dir/docs/issues/ISSUE-0014-t014a.md" \
    || log_fail "TEST-014: item a must carry ITS OWN PR (201) in links.pr, not the range's newest"
  grep -qF "    - $head1" "$dir/docs/issues/ISSUE-0014-t014a.md" \
    || log_fail "TEST-014: item a must carry ITS OWN delivery commit ($head1) in links.commits, not the range's newest ($head)"
  if grep -qF "    - 202" "$dir/docs/issues/ISSUE-0014-t014a.md"; then
    log_fail "TEST-014: item a wrongly carries PR 202 (the range-wide-attribution defect this test guards against)"
  fi
  if grep -qF "    - $head" "$dir/docs/issues/ISSUE-0014-t014a.md"; then
    log_fail "TEST-014: item a wrongly carries the range's newest commit ($head) instead of its own ($head1)"
  fi
  grep -qF "    - 202" "$dir/docs/issues/ISSUE-0014-t014b.md" \
    || log_fail "TEST-014: item b must carry PR 202 in links.pr"
  grep -qF "    - $head" "$dir/docs/issues/ISSUE-0014-t014b.md" \
    || log_fail "TEST-014: item b must carry the delivery commit ($head) in links.commits"

  log_pass "TEST-014: each item is attributed from the commit that actually touched IT, never from the range's aggregate newest commit"
}

# --- TEST-015 (Spec-AC-12, REMEDIATION ROUND 4, Codex P2 / PR #372 bot review) ---
test_015_unreadable_doc_never_reads_clean() {
  log_info "TEST-015 (Spec-AC-12): an unreadable touched document must never let --check print CLEAN or exit 0..."
  local dir base head out rc target

  dir=$(init_range_repo "t015")
  base=$(git -C "$dir" rev-parse HEAD)
  target="$dir/docs/issues/ISSUE-0015-t015.md"
  write_issue_doc "$target" "t015-ref" "implementing"
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t015 (#115)"
  head=$(git -C "$dir" rev-parse HEAD)

  if ! seed_make_unreadable "$target"; then
    log_info "TEST-015: chmod 000 denies this uid nothing (root/CI perm bypass) — the unreadable-doc defect cannot be exercised on this machine, skipping this test's assertions"
    chmod 644 "$target" 2>/dev/null || true
    return 0
  fi

  # The file stays unreadable through BOTH invocations below (only restored
  # at the very end, for cleanup) — restoring it between --check and
  # --apply would let --apply actually read and close it, proving nothing
  # about the refusal path this test exists to cover.
  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] || { chmod 644 "$target" 2>/dev/null || true; log_fail "TEST-015: an unreadable doc must not let --check exit 0, got rc=0. Output:\n$out"; }
  assert_payload_not_contains "$out" "close-reconcile: CLEAN" \
    "TEST-015: --check reported CLEAN despite a touched document it could not read — the gate certified an incomplete scan"
  assert_payload_contains "$out" "docs/issues/ISSUE-0015-t015.md" \
    "TEST-015: output does not name the unreadable path"
  assert_payload_contains "$out" "doc-unreadable" \
    "TEST-015: output does not name the doc-unreadable reason"

  local out2 rc2
  out2="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc2=0 || rc2=$?
  chmod 644 "$target" 2>/dev/null || true
  [[ "$rc2" -ne 0 ]] || log_fail "TEST-015: --apply must also refuse (non-zero) rather than silently skip the unreadable doc, got rc=0. Output:\n$out2"

  log_pass "TEST-015: an unreadable touched document fails the gate closed (named path, non-zero exit) in both --check and --apply, instead of vanishing into a false CLEAN"
}

# --- TEST-524 (Spec-AC-04(a)) ------------------------------------------------
test_524_terminal_without_telemetry() {
  log_info "TEST-524 (Spec-AC-04): a doc terminal at the delivery sha with empty links.commits and no work_item_closed event is itemed by --check..."
  local dir base head out rc

  dir=$(init_range_repo "t524")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0524-t524.md" "t524-ref" "done"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "flip t524 done with no telemetry (#524)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-524: expected exit 1, got $rc. Output:\n$out"
  assert_payload_contains "$out" "OPEN docs/issues/ISSUE-0524-t524.md" "TEST-524: missing OPEN line for the terminal-without-telemetry doc"
  assert_payload_contains "$out" "id=t524-ref" "TEST-524: missing id=t524-ref"
  assert_payload_contains "$out" "reason=terminal-without-telemetry" "TEST-524: missing reason=terminal-without-telemetry"

  # negative control: --apply must refuse (never guess a commit/PR for an
  # already-terminal doc) and leave the doc's bytes unchanged.
  local before after out_apply rc_apply
  before="$(cat "$dir/docs/issues/ISSUE-0524-t524.md")"
  out_apply="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc_apply=0 || rc_apply=$?
  [[ "$rc_apply" -ne 0 ]] || log_fail "TEST-524: --apply expected non-zero (refusal), got 0. Output:\n$out_apply"
  assert_payload_contains "$out_apply" "reason=terminal-without-telemetry" "TEST-524: --apply refusal missing reason=terminal-without-telemetry"
  after="$(cat "$dir/docs/issues/ISSUE-0524-t524.md")"
  [[ "$before" == "$after" ]] || log_fail "TEST-524: --apply must not write to a terminal-without-telemetry doc"

  # positive control: a terminal doc WITH links.commits and a work_item_closed
  # event must never be itemed — the ceremony genuinely ran.
  local dir2 base2 head2 out2 rc2
  dir2=$(init_range_repo "t524ctrl")
  base2=$(git -C "$dir2" rev-parse HEAD)
  cat > "$dir2/docs/issues/ISSUE-0524-t524ctrl.md" <<'EOF'
---
id: t524ctrl-ref
type: issue
status: done
links:
  pr:
    - 999
  commits:
    - deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
---

# Issue — Fixture t524ctrl-ref

## Summary
- fixture doc for close-reconcile tests.
EOF
  echo '{"v":1,"ts":"2020-01-01T00:00:00Z","actor":"test","event":"work_item_closed","ref":"t524ctrl-ref","payload":{}}' >> "$dir2/docs/ai/EVENTS.jsonl"
  git -C "$dir2" add -A
  git -C "$dir2" commit -q -m "already properly closed t524ctrl (#525)"
  head2=$(git -C "$dir2" rev-parse HEAD)

  out2="$(node "$CLOSE_RECONCILE" --check --range "$base2..$head2" --root "$dir2" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 0 ]] || log_fail "TEST-524: positive control (real telemetry present) expected exit 0 CLEAN, got $rc2. Output:\n$out2"
  assert_payload_contains "$out2" "CLEAN" "TEST-524: positive control expected CLEAN"

  # SPLIT-CONJUNCT ARMS (T2): the predicate is `linksCommitsEmpty &&
  # !hasCloseEvent` — dropping EITHER conjunct alone must still leave a
  # doc that satisfies only the OTHER one CLEAN, so each half needs its
  # own input that would falsely redden if that half were removed.

  # Arm B: links.commits EMPTY, but a work_item_closed event DOES exist —
  # pins the `!hasCloseEvent` half: without it (mutated to always-true),
  # this doc would be wrongly itemed on the commits-empty half alone.
  local dir3 base3 head3 out3 rc3
  dir3=$(init_range_repo "t524b")
  base3=$(git -C "$dir3" rev-parse HEAD)
  write_issue_doc "$dir3/docs/issues/ISSUE-0524-t524b.md" "t524b-ref" "done"
  echo '{"v":1,"ts":"2020-01-01T00:00:00Z","actor":"test","event":"work_item_closed","ref":"t524b-ref","payload":{}}' >> "$dir3/docs/ai/EVENTS.jsonl"
  git -C "$dir3" add -A
  git -C "$dir3" commit -q -m "flip t524b done, event present, commits still empty (#524)"
  head3=$(git -C "$dir3" rev-parse HEAD)
  out3="$(node "$CLOSE_RECONCILE" --check --range "$base3..$head3" --root "$dir3" 2>&1)" && rc3=0 || rc3=$?
  [[ "$rc3" -eq 0 ]] || log_fail "TEST-524: empty links.commits BUT a work_item_closed event present must stay CLEAN (the !hasCloseEvent conjunct alone must not fire), got $rc3. Output:\n$out3"
  assert_payload_contains "$out3" "CLEAN" "TEST-524: arm B (event present, commits empty) expected CLEAN"

  # Arm C: links.commits NON-EMPTY, but NO work_item_closed event — pins
  # the `linksCommitsEmpty` half: without it (mutated to always-true),
  # this doc would be wrongly itemed on the no-event half alone.
  local dir4 base4 head4 out4 rc4
  dir4=$(init_range_repo "t524c")
  base4=$(git -C "$dir4" rev-parse HEAD)
  cat > "$dir4/docs/issues/ISSUE-0524-t524c.md" <<'EOF'
---
id: t524c-ref
type: issue
status: done
links:
  pr:
    - 999
  commits:
    - deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
---

# Issue — Fixture t524c-ref

## Summary
- fixture doc for close-reconcile tests.
EOF
  git -C "$dir4" add -A
  git -C "$dir4" commit -q -m "flip t524c done, commits present, event still absent (#524)"
  head4=$(git -C "$dir4" rev-parse HEAD)
  out4="$(node "$CLOSE_RECONCILE" --check --range "$base4..$head4" --root "$dir4" 2>&1)" && rc4=0 || rc4=$?
  [[ "$rc4" -eq 0 ]] || log_fail "TEST-524: links.commits present BUT no work_item_closed event must stay CLEAN (the linksCommitsEmpty conjunct alone must not fire), got $rc4. Output:\n$out4"
  assert_payload_contains "$out4" "CLEAN" "TEST-524: arm C (commits present, event absent) expected CLEAN"

  log_pass "TEST-524: a terminal doc with no links.commits and no work_item_closed event is itemed reason=terminal-without-telemetry and --apply refuses it; a properly-closed terminal doc stays CLEAN; either telemetry half alone (event-only or commits-only) also stays CLEAN, pinning both conjuncts independently"
}

# --- TEST-525 (Spec-AC-04(b)) ------------------------------------------------
test_525_unpaired_draft_intake() {
  log_info "TEST-525 (Spec-AC-04): a draft intake with NO paired spec whose frontmatter id a range commit names is itemed; one no commit names is not..."
  local dir base head out rc

  dir=$(init_range_repo "t525")
  base=$(git -C "$dir" rev-parse HEAD)
  # The MAINTENANCE HALF itself is never touched by this range (M2's own
  # shape) — only a doc the range DOES touch names its id, the way this
  # corpus's own intake/spec docs already do ("Paired maintenance half:
  # `<id>`"). Written straight into the seed commit so the range under test
  # never touches ISSUE-0525-t525.md at all.
  write_issue_doc "$dir/docs/issues/ISSUE-0525-t525.md" "t525-ref" "draft"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed the untouched maintenance half"
  base=$(git -C "$dir" rev-parse HEAD)
  cat > "$dir/docs/issues/ISSUE-0525-carrier.md" <<'EOF'
---
id: t525-carrier-ref
type: change
status: implementing
links:
  pr: []
  commits: []
---

# Change — Fixture t525-carrier-ref

## Summary
- Paired maintenance half: `t525-ref`.
EOF
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver the carrier that names t525-ref (#526)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-525: expected exit 1, got $rc. Output:\n$out"
  assert_payload_contains "$out" "OPEN docs/issues/ISSUE-0525-t525.md" "TEST-525: missing OPEN line for the unpaired, unmentioned-until-now doc"
  assert_payload_contains "$out" "id=t525-ref" "TEST-525: missing id=t525-ref"
  assert_payload_contains "$out" "reason=id-mention-unpaired" "TEST-525: missing reason=id-mention-unpaired"
  # the carrier itself is ALSO an item (status implementing) — not this row's
  # concern, but its presence must not crowd out the maintenance half's line.
  assert_payload_contains "$out" "id=t525-carrier-ref" "TEST-525: carrier doc (status implementing) should still be reported too"

  # negative control: a draft doc NO commit in the range names is not itemed
  # by this arm (it may still be silent overall — a bare draft, no spec, no
  # mention — the CLEAN case this escape must not over-fire on).
  local dir2 base2 head2 out2 rc2
  dir2=$(init_range_repo "t525ctrl")
  base2=$(git -C "$dir2" rev-parse HEAD)
  write_issue_doc "$dir2/docs/issues/ISSUE-0525-ctrl.md" "t525ctrl-ref" "draft"
  git -C "$dir2" add -A
  git -C "$dir2" commit -q -m "seed the never-mentioned doc"
  base2=$(git -C "$dir2" rev-parse HEAD)
  echo "unrelated" >> "$dir2/src/app.js"
  git -C "$dir2" add -A
  git -C "$dir2" commit -q -m "deliver something that never names t525ctrl-ref (#527)"
  head2=$(git -C "$dir2" rev-parse HEAD)

  out2="$(node "$CLOSE_RECONCILE" --check --range "$base2..$head2" --root "$dir2" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 0 ]] || log_fail "TEST-525: negative control (never mentioned) expected exit 0 CLEAN, got $rc2. Output:\n$out2"
  assert_payload_contains "$out2" "CLEAN" "TEST-525: negative control expected CLEAN"

  log_pass "TEST-525: a range-mentioned, unpaired draft intake is itemed reason=id-mention-unpaired; an un-mentioned draft intake stays CLEAN"
}

# --- TEST-526 (Spec-AC-04, real corpus replay) -------------------------------
test_526_replays_the_two_real_ranges() {
  log_info "TEST-526 (Spec-AC-04): replaying PR 382's and PR 384's real merge ranges over THIS repository no longer names ISSUE-0040 or CHANGE-0181 (spec-close-ceremony-sweep Spec-AC-10 closed both, run 11); a fully closed pair in the same shape stays CLEAN..."
  local out rc

  # Replayed directly against $PROJECT_ROOT's own git history (read-only:
  # --check never writes) — these two ranges and the two doc ids are the
  # literal M2 measurement this AC exists to close. THIS ROW WAS ORIGINALLY
  # WRITTEN (TDD run 2/12) asserting exit 1 with the doc named — the state
  # M2 measured, before Spec-AC-10 (this ride's OWN run 11) closed both
  # docs with their real pr/commit. Re-run against the now-corrected live
  # corpus: each range still separately surfaces one UNRELATED, genuinely
  # still-open pre-existing item (DEBT-0003 / DEBT-0007 — real, out of this
  # ride's scope) — asserted on by name here (not merely exit 1) so this row
  # keeps exercising missingCloseEvidence's real id-mention-unpaired
  # detection instead of only proving a negative; a mutation that disables
  # that detection now reddens THIS assertion (its own real doc going
  # unnoticed) rather than staying green on a property neither range
  # exercises any more. The narrower, ride-specific property is the
  # not-contains pair below: neither output names ISSUE-0040 or CHANGE-0181
  # by id any more.
  out="$(node "$CLOSE_RECONCILE" --check --range "68fd2e14..e6aae10b" --root "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-526: PR 382's range expected exit 1 (an unrelated open item, DEBT-0003, is still unpaired), got $rc. Output:\n$out"
  assert_payload_contains "$out" "console-log-then-exit-across-41-clis" \
    "TEST-526: PR 382's range must still name the unrelated open item DEBT-0003 (console-log-then-exit-across-41-clis) — proves id-mention-unpaired detection is still armed"
  assert_payload_not_contains "$out" "focus-and-validation-state-go-stale-silently" \
    "TEST-526: PR 382's range must no longer name ISSUE-0040 (focus-and-validation-state-go-stale-silently) — Spec-AC-10 closed it with links.pr 382/links.commits e6aae10b"

  out="$(node "$CLOSE_RECONCILE" --check --range "94a983ec..7270a29c" --root "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-526: PR 384's range expected exit 1 (an unrelated open item, DEBT-0007, is still unpaired), got $rc. Output:\n$out"
  assert_payload_contains "$out" "withdrawn-claim-sweeps-are-not-verifiable" \
    "TEST-526: PR 384's range must still name the unrelated open item DEBT-0007 (withdrawn-claim-sweeps-are-not-verifiable) — proves id-mention-unpaired detection is still armed"
  assert_payload_not_contains "$out" "unrecorded-spec-amendment-is-invisible" \
    "TEST-526: PR 384's range must no longer name CHANGE-0181 (unrecorded-spec-amendment-is-invisible) — Spec-AC-10 closed it with links.pr 384/links.commits 7270a29c"

  # A fully closed pair in the SAME shape (carrier names a maintenance half
  # that is itself already terminal) must stay CLEAN — proving this arm
  # reads the maintenance half's OWN status, not just the mention.
  local dir base head out2 rc2
  dir=$(init_range_repo "t526closed")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0526-t526.md" "t526-ref" "done"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed the already-closed maintenance half"
  base=$(git -C "$dir" rev-parse HEAD)
  cat > "$dir/docs/issues/ISSUE-0526-carrier.md" <<'EOF'
---
id: t526-carrier-ref
type: change
status: done
links:
  pr:
    - 528
  commits:
    - cafebabecafebabecafebabecafebabecafebabe
---

# Change — Fixture t526-carrier-ref

## Summary
- Paired maintenance half: `t526-ref`.
EOF
  echo '{"v":1,"ts":"2020-01-01T00:00:00Z","actor":"test","event":"work_item_closed","ref":"t526-carrier-ref","payload":{}}' >> "$dir/docs/ai/EVENTS.jsonl"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver the carrier, already fully closed (#528)"
  head=$(git -C "$dir" rev-parse HEAD)

  out2="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 0 ]] || log_fail "TEST-526: a fully closed pair expected exit 0 CLEAN, got $rc2. Output:\n$out2"
  assert_payload_contains "$out2" "CLEAN" "TEST-526: a fully closed pair expected CLEAN"

  log_pass "TEST-526: replaying PR 382's and PR 384's real ranges no longer names ISSUE-0040 or CHANGE-0181 (Spec-AC-10 closed both); a fully closed pair in the same shape stays CLEAN"
}

# --- TEST-527 (Spec-AC-05) ----------------------------------------------------
test_527_pairs_by_links_requirement() {
  log_info "TEST-527 (Spec-AC-05): an off-convention pair is paired through the spec's links.requirement; --apply closes both halves; a second --check is CLEAN for a non-empty candidate set..."
  local dir base head out rc

  dir=$(init_range_repo "t527")
  base=$(git -C "$dir" rev-parse HEAD)
  write_issue_doc "$dir/docs/issues/ISSUE-0527-t527.md" "t527-ref" "implementing"
  # The spec's id deliberately does NOT read "spec-t527-ref" — the literal
  # convention pairItems() tries first — so only the links.requirement
  # fallback can pair it to its primary.
  cat > "$dir/docs/specs/SPEC-0527-t527.md" <<'EOF'
---
id: spec-t527-alt
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0527-t527.md
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture spec-t527-alt

SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture | done | commit-abc | — | — |

## Test Plan

| Test ID | Spec-AC | Type | File path | Description | Status |
|---------|---------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a | fixture | green |
EOF
  echo "changed" >> "$dir/src/app.js"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver t527 off-convention pair (#529)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-527: first --check expected exit 1 (non-empty candidate set), got $rc. Output:\n$out"
  assert_payload_contains "$out" "id=t527-ref" "TEST-527: first --check does not name the primary"

  out="$(node "$CLOSE_RECONCILE" --apply --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-527: --apply expected exit 0, got $rc. Output:\n$out"
  local closed_lines
  closed_lines=$(printf '%s\n' "$out" | grep -c "^close-reconcile: CLOSED " || true)
  [[ "${closed_lines:-0}" -eq 1 ]] || log_fail "TEST-527: expected exactly ONE close-work-item.mjs invocation (one CLOSED line), got ${closed_lines:-0}. Output:\n$out"

  grep -q "^status: done" "$dir/docs/issues/ISSUE-0527-t527.md" || log_fail "TEST-527: primary doc was not closed"
  grep -q "^status: done" "$dir/docs/specs/SPEC-0527-t527.md" || log_fail "TEST-527: off-convention spec was not closed alongside its primary"

  local out2 rc2
  out2="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 0 ]] || log_fail "TEST-527: second --check expected exit 0, got $rc2. Output:\n$out2"
  assert_payload_contains "$out2" "CLEAN" "TEST-527: second --check expected CLEAN (both halves now terminal, not an empty candidate set)"

  log_pass "TEST-527: an off-convention pair is paired via links.requirement, closed in ONE invocation, and a re-check is genuinely CLEAN"
}

# --- TEST-594 (Spec-AC-04(b), P1 Codex / PR #385 bot review, Amendment 27) ---
test_594_unreadable_untouched_candidate_never_reads_clean() {
  log_info "TEST-594 (Spec-AC-04(b)): an unreadable UNTOUCHED corpus document must never let --check print CLEAN, even when the range names its id..."
  local dir base head out rc target

  dir=$(init_range_repo "t594")
  target="$dir/docs/issues/ISSUE-0594-t594.md"
  write_issue_doc "$target" "t594-ref" "draft"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed the untouched maintenance half"
  base=$(git -C "$dir" rev-parse HEAD)
  cat > "$dir/docs/issues/ISSUE-0594-carrier.md" <<'EOF'
---
id: t594-carrier-ref
type: change
status: implementing
links:
  pr: []
  commits: []
---

# Change — Fixture t594-carrier-ref

## Summary
- Paired maintenance half: `t594-ref`.
EOF
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver the carrier that names t594-ref (#594)"
  head=$(git -C "$dir" rev-parse HEAD)

  if ! seed_make_unreadable "$target"; then
    log_info "TEST-594: chmod 000 denies this uid nothing (root/CI perm bypass) — the unreadable-candidate defect cannot be exercised on this machine, skipping this test's assertions"
    chmod 644 "$target" 2>/dev/null || true
    return 0
  fi

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  chmod 644 "$target" 2>/dev/null || true
  [[ "$rc" -ne 0 ]] || log_fail "TEST-594: an unreadable untouched candidate must not let --check exit 0, got rc=0. Output:\n$out"
  assert_payload_not_contains "$out" "close-reconcile: CLEAN" \
    "TEST-594: --check reported CLEAN despite an untouched candidate document it could not read — id-mention-unpaired printed CLEAN precisely because a document could not be inspected"
  assert_payload_contains "$out" "docs/issues/ISSUE-0594-t594.md" \
    "TEST-594: output does not name the unreadable untouched candidate path"
  assert_payload_contains "$out" "doc-unreadable" \
    "TEST-594: output does not name the doc-unreadable reason"

  log_pass "TEST-594: an unreadable untouched corpus document refuses the gate closed instead of letting id-mention-unpaired read CLEAN"
}

# --- TEST-595 (Spec-AC-04(b)/Spec-AC-05, P2 Codex / PR #385 bot review, Amendment 27) ---
test_595_candidate_pairs_by_links_requirement() {
  log_info "TEST-595 (Spec-AC-04(b)): an untouched candidate mentioned by the range is not id-mention-unpaired when an off-convention spec elsewhere in the corpus pairs it via links.requirement..."
  local dir base head out rc

  dir=$(init_range_repo "t595")
  write_issue_doc "$dir/docs/issues/ISSUE-0595-t595.md" "t595-ref" "draft"
  # Off-convention spec id (does NOT read "spec-t595-ref") whose OWN
  # links.requirement names the primary's path verbatim -- the SAME fallback
  # pairItems() already honours for docs already in `items`, now also
  # honoured at the candidate-detection stage (missingPairedSpecMention).
  cat > "$dir/docs/specs/SPEC-0595-t595.md" <<'EOF'
---
id: spec-t595-alt
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0595-t595.md
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture spec-t595-alt

SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture | done | commit-abc | — | — |

## Test Plan

| Test ID | Spec-AC | Type | File path | Description | Status |
|---------|---------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a | fixture | green |
EOF
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "seed the untouched primary and its off-convention spec"
  base=$(git -C "$dir" rev-parse HEAD)
  cat > "$dir/docs/issues/ISSUE-0595-carrier.md" <<'EOF'
---
id: t595-carrier-ref
type: change
status: implementing
links:
  pr: []
  commits: []
---

# Change — Fixture t595-carrier-ref

## Summary
- Paired maintenance half: `t595-ref`.
EOF
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "deliver the carrier that names t595-ref (#595)"
  head=$(git -C "$dir" rev-parse HEAD)

  out="$(node "$CLOSE_RECONCILE" --check --range "$base..$head" --root "$dir" 2>&1)" && rc=0 || rc=$?
  assert_payload_not_contains "$out" "reason=id-mention-unpaired" \
    "TEST-595: an off-convention spec paired via links.requirement must not be reported id-mention-unpaired: $out"
  assert_payload_not_contains "$out" "docs/issues/ISSUE-0595-t595.md" \
    "TEST-595: the paired primary must not be named as an item at all: $out"
  assert_payload_contains "$out" "id=t595-carrier-ref" "TEST-595: carrier doc (status implementing) should still be reported"
  [[ "$rc" -eq 1 ]] || log_fail "TEST-595: expected exit 1 (carrier still open on its own account), got $rc. Output:\n$out"

  log_pass "TEST-595: an untouched candidate paired via an off-convention spec's links.requirement is not flagged id-mention-unpaired"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_open_range_reports_doc_arm_sha_remediation
  test_002_intake_only_range_is_clean
  test_003_apply_closes_paired_docs_recheck_clean_idempotent
  test_004_apply_preserves_events_prefix_and_audit_clean
  test_005_close_work_item_untouched_and_no_own_writes
  test_006_apply_refuses_when_pr_number_unknown
  test_007_range_validation_fail_closed
  test_008_workflow_structure
  test_009_workflow_command_replay_behavioral
  test_010_e2e_route_independent_close
  test_011_mutation_control_stub_leaves_draft
  test_012_profiles_and_suite_map_wiring
  test_013_umbrella_parent_is_exempt
  test_014_attribution_is_resolved_per_item_not_per_range
  test_015_unreadable_doc_never_reads_clean
  test_524_terminal_without_telemetry
  test_525_unpaired_draft_intake
  test_526_replays_the_two_real_ranges
  test_527_pairs_by_links_requirement
  test_594_unreadable_untouched_candidate_never_reads_clean
  test_595_candidate_pairs_by_links_requirement

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
