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
#   - TEST-005 (Spec-AC-04): close-work-item.mjs carries no uncommitted
#     change (PROTECTED, hash-pinned by four suites); close-reconcile.mjs
#     contains no direct file write of its own.
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
  log_info "TEST-005 (Spec-AC-04): close-work-item.mjs carries no uncommitted change; close-reconcile.mjs writes no doc path of its own..."
  [[ -f "$CLOSE_RECONCILE" ]] || log_fail "TEST-005: close-reconcile.mjs does not exist yet"
  git -C "$PROJECT_ROOT" diff --quiet -- .aai/scripts/close-work-item.mjs \
    || log_fail "TEST-005: .aai/scripts/close-work-item.mjs has uncommitted modifications — PROTECTED, hash-pinned by four suites"
  local hits
  hits=$(grep -c "fs\.writeFileSync\|fs\.appendFileSync\|fs\.writeFile\b" "$CLOSE_RECONCILE" 2>/dev/null || true)
  [[ "${hits:-0}" -eq 0 ]] || log_fail "TEST-005: close-reconcile.mjs writes a file directly (${hits} occurrence(s)) — all mutation must go through close-work-item.mjs"
  log_pass "TEST-005: close-work-item.mjs untouched; close-reconcile.mjs owns no write of its own"
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

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
