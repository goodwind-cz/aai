#!/usr/bin/env bash
#
# Test: deterministic close-ceremony mechanism (CHANGE-0037 /
# docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md, TEST-001..009).
#
# Covers .aai/scripts/close-work-item.mjs — the script that mechanizes the
# work-item close ceremony (frontmatter status transition, links.pr/
# links.commits stamping, the slug-reffed close event set, and a self-verify
# against the REAL docs-audit engine with total rollback on drift) — plus its
# canon wiring into .aai/SKILL_PR.prompt.md / .aai/VALIDATION.prompt.md.
#
#   - TEST-001 (Spec-AC-01): draft-close — a `draft` change-doc fixture closes
#     to `status: done`, doc_lifecycle from=draft to=done (bare slug ref), exit 0.
#   - TEST-002 (Spec-AC-01, SPEC-0046 regression): implementing-close — an
#     `implementing` fixture closes to done, doc_lifecycle from=implementing
#     to=done; a REAL audit afterward shows tracked-done, never
#     probable-false-open.
#   - TEST-003 (Spec-AC-01): non-done-terminal guard — `deferred` and
#     `superseded` fixtures both refuse with exit 2 and a named reason; the
#     doc file and EVENTS.jsonl are byte/length-unchanged.
#   - TEST-004 (Spec-AC-02, SEAM 1/2): ref-form + real-audit CLEAN — every
#     emitted event carries the bare slug ref (never the numbered fileId);
#     the REAL docs-audit.mjs classifies the ref tracked-done/aligned with no
#     false-done/false-open/missing-close-telemetry.
#   - TEST-005 (Spec-AC-03): pair close — --ref <change> --spec <spec> flips
#     BOTH docs to done with the complete slug-reffed event set each; real
#     audit CLEAN for both refs.
#   - TEST-006 (Spec-AC-03): pair pre-write abort — an unresolvable --spec
#     aborts with exit 2 BEFORE any write; the primary doc and EVENTS.jsonl
#     are untouched.
#   - TEST-007 (Spec-AC-04): idempotent re-run — running close twice appends
#     zero new EVENTS lines and no duplicate links on the second run; exit 0.
#   - TEST-008 (Spec-AC-04, fail-closed): a spec fixture rigged with a
#     non-terminal AC row makes the post-close self-verify audit NOT CLEAN —
#     exit 1, a named finding, and total rollback (doc content + EVENTS.jsonl
#     byte-identical to their pre-run snapshots).
#   - TEST-009 (Spec-AC-05): canon grep contract — SKILL_PR.prompt.md names
#     close-work-item.mjs; VALIDATION.prompt.md no longer hand-emits
#     work_item_closed nor hand-instructs a status:done flip; repo-wide
#     strict docs-audit stays exit 0.
#   - TEST-010 (Spec-AC-04, code-review B1 regression): post-apply INDEX
#     regen failure (rigged docs/INDEX.md marker guard) must NOT bypass
#     rollback via an uncatchable process.exit — the doc frontmatter and
#     EVENTS.jsonl must be restored to their pre-run snapshot and the process
#     must still exit non-zero.
#   - TEST-011 (code-review B2 regression): appending a NEW links.pr value to
#     a doc whose frontmatter already carries an INLINE non-empty list
#     (`pr: [42]`) must normalize to block form, not splice a bare block item
#     after the inline line (malformed mixed YAML).
#   - TEST-012 (code-review B3 regression): a doc resolved via the
#     display-id fallback whose frontmatter carries no `id:` key (fmId null)
#     must be rejected with a clean, named, PRE-WRITE exit 2 — never an
#     internal-error apply/rollback cycle.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-007 second run: zero new events/links
#   - zero-remainder               -> TEST-001: single-doc close, exact event set
#   - multi-source/multi-writer    -> TEST-005: pair close, two docs same transaction
#   - mid-operation failure        -> TEST-008: rigged spec AC row aborts post-write,
#                                      full rollback of a partially-applied close
#   - negative control              -> TEST-003: deferred/superseded MUST NOT close
#
# ALL fixtures are throwaway git repos under a mktemp dir (docs/ + docs/ai/
# EVENTS.jsonl + docs/ai/docs-audit.yaml + `git init`), cleaned on EXIT. The
# real repo's docs/ and docs/ai/EVENTS.jsonl are NEVER touched by TEST-001..008
# (the script under test always runs with cwd = the fixture dir).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-close-work-item.sh            # run all tests
#   bash tests/skills/test-aai-close-work-item.sh test_002_implementing_close
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-close-work-item"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
SKILL_PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
VALIDATION_PROMPT="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"

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
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  [[ -f "$SKILL_PR" ]] || log_fail "SKILL_PR.prompt.md not found: $SKILL_PR"
  [[ -f "$VALIDATION_PROMPT" ]] || log_fail "VALIDATION.prompt.md not found: $VALIDATION_PROMPT"
  # NOTE: CLOSE_SCRIPT is intentionally NOT required here — TEST-001..008 RED
  # naturally (invocation fails / wrong exits) while the script does not yet
  # exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-close-work-item-test.XXXXXX")"
}

# --- fixture repo builders ---------------------------------------------------

# new_fixture_repo <name> -> prints the fixture repo's absolute path. A
# throwaway git repo with docs/{issues,specs}, docs/ai/EVENTS.jsonl (empty),
# docs/ai/docs-audit.yaml (enforced mode), and an initial commit so the
# audit's git probes have something to read.
new_fixture_repo() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/issues" "$dir/docs/specs" "$dir/docs/ai"
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
  git init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  echo "$dir"
}

commit_fixture_docs() {
  local dir="$1"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "add fixture doc(s)"
}

write_change_doc() {
  local path="$1" id="$2" status="$3"
  cat > "$path" <<EOF
---
id: $id
type: change
status: $status
links:
  pr: []
  commits: []
---

# Change — Fixture $id

## Summary
- fixture doc for close-work-item tests.

## Motivation / Business Value
- n/a

## Scope
- In scope: fixture only.
- Out of scope: everything else.

## Affected Area
- test fixture.

## Desired Behavior (To-Be)
- n/a

## Acceptance Criteria
- AC-001: fixture.

## Verification
- n/a

## Constraints / Risks
- n/a

## Notes
- ephemeral fixture; never committed to the real repo.
EOF
}

# write_spec_doc <path> <id> <status> <ac_status> <evidence>
write_spec_doc() {
  local path="$1" id="$2" status="$3" ac_status="${4:-done}" evidence="${5:-commit-abc}"
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

| Spec-AC    | Description | Status      | Evidence     | Review-By | Notes |
|------------|--------------|-------------|--------------|-----------|-------|
| Spec-AC-01 | fixture      | $ac_status  | $evidence    | —         | —     |

## Test Plan

| Test ID  | Spec-AC    | Type | File path | Description | Status |
|----------|------------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a       | fixture      | green  |
EOF
}

# --- invocation + assertion helpers ------------------------------------------

# run_close <fixture_dir> <outfile> <errfile> <args...> — echoes the exit code.
run_close() {
  local dir="$1" outfile="$2" errfile="$3"
  shift 3
  local code=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" "$@" > "$outfile" 2> "$errfile" ) || code=$?
  echo "$code"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    || log_fail "$desc: expected exit $expected, got $actual"
}

file_size() { wc -c < "$1" | tr -d ' '; }

# events_count <events_file> <event> <ref> [payload_key] [payload_val]
events_count() {
  node -e '
    const fs = require("fs");
    const [file, ev, ref, pk, pv] = process.argv.slice(1);
    const lines = fs.readFileSync(file, "utf8").split("\n").filter(Boolean);
    let n = 0;
    for (const l of lines) {
      let o; try { o = JSON.parse(l); } catch { continue; }
      if (o.event !== ev || o.ref !== ref) continue;
      if (pk && String(o.payload && o.payload[pk]) !== pv) continue;
      n += 1;
    }
    process.stdout.write(String(n));
  ' "$@"
}

# --- TEST-001 (Spec-AC-01): draft-close --------------------------------------

test_001_draft_close() {
  log_info "Test: draft-close -> status: done, doc_lifecycle from=draft to=done, exit 0 (TEST-001)..."
  local dir; dir=$(new_fixture_repo "t001")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t001.md" "t001-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t001.out" err="$TEST_DIR/t001.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t001-slug --pr 1 --commit a0a0a01)
  assert_exit "draft close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t001.md" \
    || log_fail "t001: frontmatter status was not flipped to done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t001-slug from draft)" -ge 1 ]] \
    || log_fail "t001: missing doc_lifecycle event with from=draft"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t001-slug to done)" -ge 1 ]] \
    || log_fail "t001: missing doc_lifecycle event with to=done"

  log_pass "Draft-close: status flipped, bare-slug doc_lifecycle event, exit 0 (TEST-001)"
}

# --- TEST-002 (Spec-AC-01, SPEC-0046 regression): implementing-close --------

test_002_implementing_close() {
  log_info "Test: implementing-close (SPEC-0046 regression) -> done; real audit tracked-done, never probable-false-open (TEST-002)..."
  local dir; dir=$(new_fixture_repo "t002")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t002.md" "t002-slug" "implementing"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t002.out" err="$TEST_DIR/t002.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t002-slug --pr 2 --commit b0b0b02)
  assert_exit "implementing close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t002.md" \
    || log_fail "t002: frontmatter status was not flipped to done (SPEC-0046 flip-miss regression)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t002-slug from implementing)" -ge 1 ]] \
    || log_fail "t002: missing doc_lifecycle event with from=implementing (ACTUAL status, not an assumed draft)"

  local audit_out="$TEST_DIR/t002-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t002-slug | tracked-done |" "$audit_out" \
    || log_fail "t002: real audit does not classify t002-slug tracked-done: $(cat "$audit_out")"
  if grep -F "t002-slug" "$audit_out" | grep -q "probable-false-open"; then
    log_fail "t002: real audit flags probable-false-open (the exact SPEC-0046 incident class)"
  fi

  log_pass "Implementing-close: status flipped from ACTUAL value, real audit tracked-done never false-open (TEST-002)"
}

# --- TEST-003 (Spec-AC-01): non-done-terminal guard --------------------------

test_003_non_done_terminal_guard() {
  log_info "Test: non-done-terminal guard -> deferred/superseded refuse with exit 2, doc + EVENTS untouched (TEST-003)..."
  local dir; dir=$(new_fixture_repo "t003")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t003a.md" "t003a-slug" "deferred"
  write_change_doc "$dir/docs/issues/CHANGE-0002-t003b.md" "t003b-slug" "superseded"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t003a.md" "$TEST_DIR/t003a-before.md"
  cp "$dir/docs/issues/CHANGE-0002-t003b.md" "$TEST_DIR/t003b-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t003a.out" err="$TEST_DIR/t003a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t003a-slug --pr 3 --commit c0c0c03)
  assert_exit "deferred doc refuses close" 2 "$code"
  grep -qiE "deferred|non-done-terminal|refus" "$err" \
    || log_fail "t003a: expected a named reason in stderr, got: $(cat "$err")"

  out="$TEST_DIR/t003b.out"; err="$TEST_DIR/t003b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t003b-slug --pr 3 --commit d0d0d03)
  assert_exit "superseded doc refuses close" 2 "$code"
  grep -qiE "superseded|non-done-terminal|refus" "$err" \
    || log_fail "t003b: expected a named reason in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t003a-before.md" "$dir/docs/issues/CHANGE-0001-t003a.md" >/dev/null \
    || log_fail "t003a: doc was mutated despite exit 2"
  diff -q "$TEST_DIR/t003b-before.md" "$dir/docs/issues/CHANGE-0002-t003b.md" >/dev/null \
    || log_fail "t003b: doc was mutated despite exit 2"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t003: EVENTS.jsonl grew despite exit 2"

  log_pass "Non-done-terminal guard: deferred + superseded refuse with a named reason, nothing written (TEST-003)"
}

# --- TEST-004 (Spec-AC-02, SEAM 1/2): ref-form + real-audit CLEAN ------------

test_004_ref_form_and_audit_clean() {
  log_info "Test: ref-form (bare slug, never numbered) + REAL audit CLEAN for the closed ref (TEST-004)..."
  local dir; dir=$(new_fixture_repo "t004")
  write_change_doc "$dir/docs/issues/CHANGE-0007-t004.md" "t004-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t004.out" err="$TEST_DIR/t004.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t004-slug --pr 7 --commit e0e0e04)
  assert_exit "t004 close" 0 "$code"

  if grep -qF '"CHANGE-0007"' "$dir/docs/ai/EVENTS.jsonl"; then
    log_fail "t004: a numbered ref (CHANGE-0007) leaked into EVENTS.jsonl — must be the bare slug"
  fi
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t004-slug from draft)" -ge 1 ]] \
    || log_fail "t004: missing doc_lifecycle with the bare slug ref"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t004-slug)" -ge 1 ]] \
    || log_fail "t004: missing work_item_closed with the bare slug ref"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" ac_evidence t004-slug commit e0e0e04)" -ge 1 ]] \
    || log_fail "t004: missing ac_evidence with the bare slug ref + commit"

  local audit_out="$TEST_DIR/t004-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t004-slug | tracked-done | done | aligned |" "$audit_out" \
    || log_fail "t004: real audit does not classify t004-slug tracked-done/aligned: $(cat "$audit_out")"
  if grep -F "t004-slug" "$audit_out" | grep -qE "probable-false-done|probable-false-open|missing-close-telemetry"; then
    log_fail "t004: real audit flags false-done/false-open/missing-close-telemetry for t004-slug"
  fi

  log_pass "Ref-form + real-audit CLEAN: every event uses the bare slug, audit classifies tracked-done/aligned (TEST-004)"
}

# --- TEST-005 (Spec-AC-03): pair close ---------------------------------------

test_005_pair_close() {
  log_info "Test: pair close --ref <change> --spec <spec> -> BOTH done, BOTH full event set, real audit CLEAN for both (TEST-005)..."
  local dir; dir=$(new_fixture_repo "t005")
  write_change_doc "$dir/docs/issues/CHANGE-0009-t005.md" "t005-change-slug" "implementing"
  write_spec_doc "$dir/docs/specs/SPEC-0009-t005.md" "t005-spec-slug" "implementing" "done"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t005.out" err="$TEST_DIR/t005.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t005-change-slug --spec t005-spec-slug --pr 9 --commit f0f0f05)
  assert_exit "pair close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0009-t005.md" || log_fail "t005: change doc not flipped to done"
  grep -q '^status: done$' "$dir/docs/specs/SPEC-0009-t005.md" || log_fail "t005: spec doc not flipped to done"

  local ev="$dir/docs/ai/EVENTS.jsonl"
  [[ "$(events_count "$ev" doc_lifecycle t005-change-slug from implementing)" -ge 1 ]] || log_fail "t005: change missing doc_lifecycle"
  [[ "$(events_count "$ev" work_item_closed t005-change-slug)" -ge 1 ]] || log_fail "t005: change missing work_item_closed"
  [[ "$(events_count "$ev" ac_evidence t005-change-slug commit f0f0f05)" -ge 1 ]] || log_fail "t005: change missing ac_evidence"
  [[ "$(events_count "$ev" doc_lifecycle t005-spec-slug from implementing)" -ge 1 ]] || log_fail "t005: spec missing doc_lifecycle"
  [[ "$(events_count "$ev" work_item_closed t005-spec-slug)" -ge 1 ]] || log_fail "t005: spec missing work_item_closed"
  [[ "$(events_count "$ev" ac_evidence t005-spec-slug commit f0f0f05)" -ge 1 ]] || log_fail "t005: spec missing ac_evidence (D5 symmetry)"

  local audit_out="$TEST_DIR/t005-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t005-change-slug | tracked-done | done | aligned |" "$audit_out" || log_fail "t005: change not tracked-done/aligned"
  grep -qF "| t005-spec-slug | tracked-done | done | aligned |" "$audit_out" || log_fail "t005: spec not tracked-done/aligned"

  log_pass "Pair close: both docs done, both carry the complete slug-reffed event set, real audit CLEAN (TEST-005)"
}

# --- TEST-006 (Spec-AC-03): pair pre-write abort -----------------------------

test_006_pair_pre_write_abort() {
  log_info "Test: pair pre-write abort -> unresolvable --spec exits 2 BEFORE any write (TEST-006)..."
  local dir; dir=$(new_fixture_repo "t006")
  write_change_doc "$dir/docs/issues/CHANGE-0011-t006.md" "t006-change-slug" "draft"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0011-t006.md" "$TEST_DIR/t006-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t006.out" err="$TEST_DIR/t006.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t006-change-slug --spec no-such-spec-slug --pr 11 --commit 11a11a1)
  assert_exit "unresolvable spec aborts pre-write" 2 "$code"
  grep -qiE "no scanned doc resolves|unresolv" "$err" \
    || log_fail "t006: expected a named unresolvable-ref reason, got: $(cat "$err")"

  diff -q "$TEST_DIR/t006-before.md" "$dir/docs/issues/CHANGE-0011-t006.md" >/dev/null \
    || log_fail "t006: primary doc was mutated despite pre-write abort"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t006: EVENTS.jsonl grew despite pre-write abort"

  log_pass "Pair pre-write abort: unresolvable spec exits 2, primary doc + EVENTS untouched, never half-closed (TEST-006)"
}

# --- TEST-007 (Spec-AC-04): idempotent re-run --------------------------------

test_007_idempotent_rerun() {
  log_info "Test: idempotent re-run -> second close appends zero new events, no duplicate links, exit 0 (TEST-007)..."
  local dir; dir=$(new_fixture_repo "t007")
  write_change_doc "$dir/docs/issues/CHANGE-0013-t007.md" "t007-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t007a.out" err="$TEST_DIR/t007a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t007-slug --pr 13 --commit 22b22b2)
  assert_exit "t007 first close" 0 "$code"

  local events_after_first; events_after_first=$(file_size "$dir/docs/ai/EVENTS.jsonl")
  local doc_after_first; doc_after_first=$(cat "$dir/docs/issues/CHANGE-0013-t007.md")

  out="$TEST_DIR/t007b.out"; err="$TEST_DIR/t007b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t007-slug --pr 13 --commit 22b22b2)
  assert_exit "t007 second (idempotent) close" 0 "$code"

  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_after_first" ]] \
    || log_fail "t007: second run appended new EVENTS.jsonl lines (not idempotent)"
  [[ "$(cat "$dir/docs/issues/CHANGE-0013-t007.md")" == "$doc_after_first" ]] \
    || log_fail "t007: second run mutated the doc again (duplicate links.pr/links.commits?)"

  log_pass "Idempotent re-run: zero new events, zero duplicate links, exit 0 (TEST-007)"
}

# --- TEST-008 (Spec-AC-04, fail-closed): rigged self-verify failure ---------

test_008_fail_closed_rollback() {
  log_info "Test: fail-closed rollback -> rigged non-terminal AC row fails self-verify, exit non-zero, total rollback (TEST-008)..."
  local dir; dir=$(new_fixture_repo "t008")
  write_change_doc "$dir/docs/issues/CHANGE-0015-t008.md" "t008-change-slug" "implementing"
  write_spec_doc "$dir/docs/specs/SPEC-0015-t008.md" "t008-spec-slug" "implementing" "planned" "—"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0015-t008.md" "$TEST_DIR/t008-change-before.md"
  cp "$dir/docs/specs/SPEC-0015-t008.md" "$TEST_DIR/t008-spec-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t008.out" err="$TEST_DIR/t008.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t008-change-slug --spec t008-spec-slug --pr 15 --commit 33c33c3)
  [[ "$code" != "0" ]] || log_fail "t008: expected a non-zero exit (self-verify must catch the rigged non-terminal AC row), got 0"
  grep -qiE "not clean|rolled back|probable-false-done|non-terminal" "$err" \
    || log_fail "t008: expected a named finding in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t008-change-before.md" "$dir/docs/issues/CHANGE-0015-t008.md" >/dev/null \
    || log_fail "t008: change doc was not restored to its pre-run snapshot"
  diff -q "$TEST_DIR/t008-spec-before.md" "$dir/docs/specs/SPEC-0015-t008.md" >/dev/null \
    || log_fail "t008: spec doc was not restored to its pre-run snapshot"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t008: EVENTS.jsonl was not truncated back to its pre-run byte length"

  log_pass "Fail-closed rollback: rigged non-terminal AC row rolls back BOTH docs + EVENTS byte-length, named finding (TEST-008)"
}

# --- TEST-009 (Spec-AC-05): canon grep contract ------------------------------

test_009_canon_grep_contract() {
  log_info "Test: canon grep contract — SKILL_PR names the script, VALIDATION drops hand-flip/hand-emit, strict audit exit 0 (TEST-009)..."

  grep -qF "close-work-item.mjs" "$SKILL_PR" \
    || log_fail "t009: SKILL_PR.prompt.md must name close-work-item.mjs"
  grep -qF "close-work-item.mjs" "$VALIDATION_PROMPT" \
    || log_fail "t009: VALIDATION.prompt.md must point to close-work-item.mjs"

  if grep -qF "append-event.mjs --event work_item_closed" "$VALIDATION_PROMPT"; then
    log_fail "t009: VALIDATION.prompt.md still hand-emits work_item_closed via append-event.mjs"
  fi
  if grep -qF 'writing `status: done`' "$VALIDATION_PROMPT"; then
    log_fail "t009: VALIDATION.prompt.md still instructs a hand status:done flip"
  fi

  local audit_log="$TEST_DIR/t009-strict-audit.log"
  ( cd "$PROJECT_ROOT" && node "$DOCS_AUDIT" --check --strict --no-event > "$audit_log" 2>&1 ) \
    || log_fail "t009: repo-wide strict docs-audit must exit 0: $(tail -20 "$audit_log")"

  log_pass "Canon grep contract: SKILL_PR names the script, VALIDATION drops hand-flip/hand-emit, strict audit clean (TEST-009)"
}

# --- TEST-010 (Spec-AC-04, code-review B1 regression): post-apply INDEX ------
# regen failure must not bypass rollback -----------------------------------

test_010_fail_closed_index_regen_rollback() {
  log_info "Test: fail-closed rollback -> post-apply INDEX regen failure (rigged marker-guard) must run rollback via the catch, never bypass it via an uncatchable process.exit (TEST-010, code-review B1)..."
  local dir; dir=$(new_fixture_repo "t010")
  write_change_doc "$dir/docs/issues/CHANGE-0021-t010.md" "t010-slug" "draft"
  commit_fixture_docs "$dir"
  # Rig docs/INDEX.md so generate-docs-index.mjs's own marker guard (checkMarker)
  # refuses to overwrite it and exits non-zero — a deterministic, in-repo way to
  # make the post-apply self-verify's INDEX regeneration fail without touching
  # any shared script (mirrors the spec's R4 downstream-missing-generator case:
  # self-verify cannot complete, so the close must not proceed silently).
  printf 'not the auto-generated marker\n' > "$dir/docs/INDEX.md"

  cp "$dir/docs/issues/CHANGE-0021-t010.md" "$TEST_DIR/t010-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t010.out" err="$TEST_DIR/t010.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t010-slug --pr 21 --commit 44d44d4)
  [[ "$code" != "0" ]] \
    || log_fail "t010: expected a non-zero exit (INDEX regen failure must not silently succeed), got 0"
  grep -qiE "internal error|index regeneration|rolled back" "$err" \
    || log_fail "t010: expected a named finding in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t010-before.md" "$dir/docs/issues/CHANGE-0021-t010.md" >/dev/null \
    || log_fail "t010: doc was NOT restored to its pre-run snapshot (B1: half-closed doc left on disk)"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t010: EVENTS.jsonl was NOT truncated back to its pre-run byte length (B1: half-closed event set left on disk)"

  log_pass "Fail-closed rollback: post-apply INDEX regen failure rolls back doc + EVENTS (no half-close), exit non-zero (TEST-010, B1)"
}

# --- TEST-011 (code-review B2 regression): inline non-empty links.pr --------
# normalized to block form before appending ----------------------------------

test_011_inline_nonempty_links_normalized() {
  log_info "Test: stampLink normalizes a pre-existing INLINE non-empty links.pr list to block form before appending, instead of splicing a block item after the inline line (TEST-011, code-review B2)..."
  local dir; dir=$(new_fixture_repo "t011")
  local doc="$dir/docs/issues/CHANGE-0022-t011.md"
  cat > "$doc" <<'EOF'
---
id: t011-slug
type: change
status: draft
links:
  pr: [42]
  commits: []
---

# Change — Fixture t011-slug

## Summary
- fixture doc for close-work-item tests (inline non-empty links.pr).

## Motivation / Business Value
- n/a

## Scope
- In scope: fixture only.
- Out of scope: everything else.

## Affected Area
- test fixture.

## Desired Behavior (To-Be)
- n/a

## Acceptance Criteria
- AC-001: fixture.

## Verification
- n/a

## Constraints / Risks
- n/a

## Notes
- ephemeral fixture; never committed to the real repo.
EOF
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t011.out" err="$TEST_DIR/t011.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t011-slug --pr 99 --commit 55e55e5)
  assert_exit "t011 close with pre-existing inline non-empty links.pr" 0 "$code"

  # The malformed-mixed-YAML bug (B2) left the raw inline line `  pr: [42]`
  # in place and spliced a bare block item (`    - 99`) directly after it.
  # Assert that shape is ABSENT — the inline line must be normalized away.
  if grep -qF '  pr: [42]' "$doc"; then
    log_fail "t011: links.pr still carries the raw inline form — not normalized to block (malformed mixed YAML)"
  fi
  grep -q '^  pr:$' "$doc" || log_fail "t011: links.pr was not normalized to block form"
  grep -qF '    - 42' "$doc" || log_fail "t011: pre-existing inline value 42 was lost during normalization"
  grep -qF '    - 99' "$doc" || log_fail "t011: newly stamped value 99 is missing"

  local doc_after_first; doc_after_first=$(cat "$doc")

  # Re-run with the SAME args: this exercises the normalized block form
  # through the script's OWN reader (locateLinksField/hasLinkValue) — the
  # idempotency short-circuit must recognize both 42 and 99 as already
  # present and write nothing further (proves the normalized shape round-trips
  # cleanly through the script's own parser, not just a generic YAML parser).
  out="$TEST_DIR/t011b.out"; err="$TEST_DIR/t011b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t011-slug --pr 99 --commit 55e55e5)
  assert_exit "t011 second (idempotent) close after normalization" 0 "$code"
  [[ "$(cat "$doc")" == "$doc_after_first" ]] \
    || log_fail "t011: second run mutated the normalized doc again (not idempotent / not round-trippable)"

  log_pass "Inline non-empty links.pr normalized to block form on append, both values present, idempotent re-run confirms round-trip (TEST-011, B2)"
}

# --- TEST-012 (code-review B3 regression): null fm.id pre-write guard -------

test_012_null_fm_id_pre_write_guard() {
  log_info "Test: a doc with no frontmatter id (resolved only by display-id) is rejected with a clean PRE-WRITE exit 2, never an internal-error apply/rollback cycle (TEST-012, code-review B3)..."
  local dir; dir=$(new_fixture_repo "t012")
  local doc="$dir/docs/issues/CHANGE-0023-t012.md"
  cat > "$doc" <<'EOF'
---
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Fixture CHANGE-0023-t012 (no frontmatter id)

## Summary
- fixture doc for close-work-item tests (missing id: key).

## Motivation / Business Value
- n/a

## Scope
- In scope: fixture only.
- Out of scope: everything else.

## Affected Area
- test fixture.

## Desired Behavior (To-Be)
- n/a

## Acceptance Criteria
- AC-001: fixture.

## Verification
- n/a

## Constraints / Risks
- n/a

## Notes
- ephemeral fixture; never committed to the real repo.
EOF
  commit_fixture_docs "$dir"
  cp "$doc" "$TEST_DIR/t012-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t012.out" err="$TEST_DIR/t012.err" code
  code=$(run_close "$dir" "$out" "$err" --ref CHANGE-0023 --pr 23 --commit 66f66f6)
  assert_exit "null fm.id resolved-by-display-id refuses pre-write" 2 "$code"
  grep -qiE 'no frontmatter.*id|frontmatter has no.*id|has no.*"?id"?' "$err" \
    || log_fail "t012: expected a named missing-id reason in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t012-before.md" "$doc" >/dev/null \
    || log_fail "t012: doc was mutated despite exit 2 (must be pre-write)"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t012: EVENTS.jsonl grew despite exit 2 (must be pre-write)"

  log_pass "Null fm.id resolved by display-id: clean pre-write exit 2, doc + EVENTS untouched (TEST-012, B3)"
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

  test_001_draft_close
  test_002_implementing_close
  test_003_non_done_terminal_guard
  test_004_ref_form_and_audit_clean
  test_005_pair_close
  test_006_pair_pre_write_abort
  test_007_idempotent_rerun
  test_008_fail_closed_rollback
  test_009_canon_grep_contract
  test_010_fail_closed_index_regen_rollback
  test_011_inline_nonempty_links_normalized
  test_012_null_fm_id_pre_write_guard

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
