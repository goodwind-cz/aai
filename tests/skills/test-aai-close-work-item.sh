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
TEST_SELF="$PROJECT_ROOT/tests/skills/test-aai-close-work-item.sh"
GUARD_CONFIG_LIB="$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs"

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

# --- product-doc-gate fixture builders (product-docs-enforced) --------------

# write_user_visible_change_doc <path> <id> <status> — same shape as
# write_change_doc but with `user_visible: true` in frontmatter (D1 trigger key).
write_user_visible_change_doc() {
  local path="$1" id="$2" status="$3"
  cat > "$path" <<EOF
---
id: $id
type: change
status: $status
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Fixture $id (user_visible)

## Summary
- fixture doc for close-work-item product-doc gate tests.

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

# set_product_doc_gate_dial <fixture_dir> <enforce|report-only|bogus> —
# appends the dial to the fixture's docs-audit.yaml (first occurrence wins in
# guard-config.mjs's column-0 scan, and the fixture's base file has no
# pre-existing product_doc_gate line).
set_product_doc_gate_dial() {
  local dir="$1" value="$2"
  printf 'product_doc_gate: %s\n' "$value" >> "$dir/docs/ai/docs-audit.yaml"
}

# write_real_product_doc <fixture_dir> <slug> — a REAL (non-placeholder)
# product doc at docs/product/<slug>.md: every required section filled
# ("None." for Data model/Interfaces, matching PRODUCT_TEMPLATE's explicit
# positive-empty marker).
write_real_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

None.

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_placeholder_data_model_product_doc <fixture_dir> <slug> — the Data
# model section still carries the unfilled template angle-bracket token;
# Interfaces and contracts is real (isolates the Data-model placeholder case).
write_placeholder_data_model_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

<Entities/records/files this feature introduces or changes: name, fields
worth knowing, where stored, retention. "None." if no data shape changed.>

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_placeholder_interfaces_product_doc <fixture_dir> <slug> — Interfaces
# and contracts still carries the unfilled template token; Data model is
# real (isolates the Interfaces placeholder case, TEST-006).
write_placeholder_interfaces_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

None.

## Interfaces and contracts

<Public surfaces this feature adds or changes: CLI commands and exit codes,
API endpoints, file formats, events, env vars. One line each: surface,
shape, stability promise. "None." if no public surface changed.>

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_none_dot_product_doc <fixture_dir> <slug> — Data model AND Interfaces
# both read the literal "None." (TEST-006: must count as REAL and PASS).
write_none_dot_product_doc() {
  write_real_product_doc "$1" "$2"
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

# --- TEST-013 (CHANGE-0052): brief auto-cleanup on close ---------------------

test_013_brief_cleanup_on_close() {
  log_info "Test: brief auto-cleanup -> a durable close prunes docs/ai/briefs/<ref>.md, spares an unrelated brief, never fails the close (TEST-013)..."
  local dir; dir=$(new_fixture_repo "t013")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t013.md" "t013-slug" "implementing"
  commit_fixture_docs "$dir"

  # Three briefs: the SLUG-named brief (t013-slug.md), the DISPLAY-ID-named brief
  # (CHANGE-0001.md — PLANNING has historically named briefs by either form), and
  # an unrelated one that MUST survive.
  mkdir -p "$dir/docs/ai/briefs"
  printf 'brief for t013-slug\n' > "$dir/docs/ai/briefs/t013-slug.md"
  printf 'brief for CHANGE-0001 display id\n' > "$dir/docs/ai/briefs/CHANGE-0001.md"
  printf 'brief for someone else\n' > "$dir/docs/ai/briefs/other-slug.md"

  local out="$TEST_DIR/t013.out" err="$TEST_DIR/t013.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t013-slug --pr 13 --commit e0e0e13)
  assert_exit "brief-cleanup close" 0 "$code"

  [[ ! -e "$dir/docs/ai/briefs/t013-slug.md" ]] \
    || log_fail "t013: SLUG-named brief for the closed ref was NOT pruned"
  [[ ! -e "$dir/docs/ai/briefs/CHANGE-0001.md" ]] \
    || log_fail "t013: DISPLAY-ID-named brief for the closed ref was NOT pruned (bot-review P2)"
  [[ -e "$dir/docs/ai/briefs/other-slug.md" ]] \
    || log_fail "t013: an UNRELATED brief was wrongly pruned"
  grep -qF "pruned brief" "$out" \
    || log_fail "t013: success line did not report the pruned brief: $(cat "$out")"

  # No-brief close must still succeed cleanly (best-effort, missing brief is a no-op).
  local dir2; dir2=$(new_fixture_repo "t013b")
  write_change_doc "$dir2/docs/issues/CHANGE-0001-t013b.md" "t013b-slug" "implementing"
  commit_fixture_docs "$dir2"
  out="$TEST_DIR/t013b.out"; err="$TEST_DIR/t013b.err"
  code=$(run_close "$dir2" "$out" "$err" --ref t013b-slug --pr 14 --commit f0f0f14)
  assert_exit "no-brief close still succeeds" 0 "$code"
  grep -qF "pruned brief" "$out" \
    && log_fail "t013b: reported a pruned brief when none existed: $(cat "$out")"

  log_pass "Brief auto-cleanup: closed ref's brief pruned, unrelated brief spared, no-brief close clean (TEST-013)"
}

# --- token-economics-end-to-end TEST-008/TEST-009 (Spec-AC-06) ---------------
# best-effort overview-data regen as the STRICTLY LAST step of a successful
# close (after self-verify + pruneBriefs); a generator failure is swallowed —
# never changes the close exit code, never reaches rollback (negative
# control). RED-proof obligation: both are integrity-critical rows.

test_014_overview_regen_best_effort() {  # token-economics TEST-008
  log_info "Test: a successful close regenerates overview-data.json best-effort and exits 0 (token-economics TEST-008)..."
  local dir; dir=$(new_fixture_repo "t014")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t014.md" "t014-slug" "draft"
  commit_fixture_docs "$dir"

  [[ -e "$dir/docs/ai/overview-data.json" ]] \
    && log_fail "t014: fixture setup bug — overview-data.json must not pre-exist"

  local out="$TEST_DIR/t014.out" err="$TEST_DIR/t014.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t014-slug --pr 14 --commit c0c0c14)
  assert_exit "close with overview regen" 0 "$code"

  [[ -f "$dir/docs/ai/overview-data.json" ]] \
    || log_fail "t014: close did not regenerate docs/ai/overview-data.json (Spec-AC-06 best-effort hook)"
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const hit = m.delivered.find(x => x.ref === "t014-slug");
    if (!hit) { console.error("t014-slug not present in regenerated delivered list"); process.exit(1); }
    if (hit.status !== "done") { console.error("regenerated overview shows non-done status: " + hit.status); process.exit(1); }
  ' "$dir/docs/ai/overview-data.json" || log_fail "t014: regenerated overview-data.json does not reflect the just-closed item"

  log_pass "Successful close regenerates overview-data.json best-effort, closed item present as done, exit 0 (token-economics TEST-008)"
}

test_015_overview_regen_failure_negative_control() {  # token-economics TEST-009
  log_info "Test: NEGATIVE CONTROL — a rigged overview-generator failure leaves close exit 0, the doc still done, close events intact (no rollback) (token-economics TEST-009)..."
  local dir; dir=$(new_fixture_repo "t015")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t015.md" "t015-slug" "draft"
  commit_fixture_docs "$dir"

  # Rig the generator to fail: put a DIRECTORY where it must write a file, so
  # generate-overview.mjs's fs.writeFileSync throws EISDIR. No flag/mock
  # needed -- this exercises the REAL generator failing for real.
  mkdir -p "$dir/docs/ai/overview-data.json"

  local out="$TEST_DIR/t015.out" err="$TEST_DIR/t015.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t015-slug --pr 15 --commit d0d0d15)
  assert_exit "close survives a rigged generator failure" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t015.md" \
    || log_fail "t015: the close itself must NOT be rolled back by a generator failure -- doc must still be done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t015-slug)" -ge 1 ]] \
    || log_fail "t015: work_item_closed event must still be present (no rollback triggered by the generator failure)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t015-slug)" -ge 1 ]] \
    || log_fail "t015: doc_lifecycle event must still be present (no rollback triggered by the generator failure)"

  log_pass "Generator failure is swallowed: close exit 0, doc still done, close events intact, no rollback (token-economics TEST-009)"
}

# --- product-docs-enforced TEST-001 (Spec-AC-01): report-only warns ---------

test_016_gate_report_only_warns() {
  log_info "Test: user_visible + missing product doc + report-only dial: WARNING on stderr, close exit 0, doc flipped (product-docs-enforced TEST-001)..."
  local dir; dir=$(new_fixture_repo "t016")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t016.md" "t016-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t016.out" err="$TEST_DIR/t016.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t016-slug --pr 16 --commit a1a1a16)
  assert_exit "report-only gate close" 0 "$code"

  grep -qi 'WARNING.*product-doc gate' "$err" \
    || log_fail "t016: expected a product-doc-gate WARNING on stderr, got: $(cat "$err")"
  grep -qF 't016-slug' "$err" || log_fail "t016: WARNING did not name the scope"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t016.md" \
    || log_fail "t016: report-only must still let the close proceed (status not flipped)"

  log_pass "Report-only gate: WARNING on stderr, close proceeds, doc flipped (product-docs-enforced TEST-001)"
}

# --- product-docs-enforced TEST-002 (Spec-AC-01): enforce refuses pre-write -

test_017_gate_enforce_refuses_pre_write() {
  log_info "Test: user_visible + missing product doc + enforce dial: refuse exit non-zero, doc bytes + EVENTS length unchanged (pre-write) (product-docs-enforced TEST-002)..."
  local dir; dir=$(new_fixture_repo "t017")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t017.md" "t017-slug" "draft"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t017.md" "$TEST_DIR/t017-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t017.out" err="$TEST_DIR/t017.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t017-slug --pr 17 --commit b1b1b17)
  assert_exit "enforce gate refuses" 3 "$code"
  grep -qi 'REFUSED.*product-doc gate' "$err" \
    || log_fail "t017: expected a product-doc-gate REFUSED line on stderr, got: $(cat "$err")"
  grep -qF 't017-slug' "$err" || log_fail "t017: REFUSED reason did not name the scope"

  diff -q "$TEST_DIR/t017-before.md" "$dir/docs/issues/CHANGE-0001-t017.md" >/dev/null \
    || log_fail "t017: doc was mutated despite a pre-write refusal"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t017: EVENTS.jsonl grew despite a pre-write refusal"
  [[ ! -e "$dir/docs/INDEX.md" ]] \
    || log_fail "t017: docs/INDEX.md was created despite a pre-write refusal (gate must fire before ANY write, including self-verify's INDEX regen)"

  log_pass "Enforce gate: refuse exit 3, nothing written (doc + EVENTS + INDEX untouched) (product-docs-enforced TEST-002)"
}

# --- product-docs-enforced TEST-003 (Spec-AC-01): absent key negative control

test_018_gate_absent_user_visible_negative_control() {
  log_info "Test: user_visible absent (legacy) -- gate silent, close proceeds regardless of product doc, even under enforce (product-docs-enforced TEST-003)..."
  local dir; dir=$(new_fixture_repo "t018")
  set_product_doc_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t018.md" "t018-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t018.out" err="$TEST_DIR/t018.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t018-slug --pr 18 --commit c1c1c18)
  assert_exit "absent user_visible proceeds under enforce" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t018: gate must be SILENT when user_visible is absent, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t018.md" \
    || log_fail "t018: close did not proceed for a legacy (non-user_visible) doc"

  log_pass "Negative control: absent user_visible is silent and unaffected by the enforce dial (product-docs-enforced TEST-003)"
}

# --- product-docs-enforced TEST-004 (Spec-AC-01): real product doc passes ---

test_019_gate_real_product_doc_passes_enforce() {
  log_info "Test: user_visible + real product doc present under enforce: close proceeds, no warning (product-docs-enforced TEST-004)..."
  local dir; dir=$(new_fixture_repo "t019")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t019.md" "t019-slug" "draft"
  write_real_product_doc "$dir" "t019-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t019.out" err="$TEST_DIR/t019.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t019-slug --pr 19 --commit d1d1d19)
  assert_exit "real product doc under enforce proceeds" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t019: a REAL product doc must not warn/refuse, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t019.md" \
    || log_fail "t019: close did not proceed despite a real product doc"

  log_pass "Real product doc present: enforce proceeds silently (product-docs-enforced TEST-004)"
}

# --- product-docs-enforced TEST-005 (Spec-AC-02): placeholder Data model ----

test_020_gate_placeholder_data_model_counts_missing() {
  log_info "Test: a product doc with a placeholder Data model section counts as missing (enforce refuses) (product-docs-enforced TEST-005)..."
  local dir; dir=$(new_fixture_repo "t020")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t020.md" "t020-slug" "draft"
  write_placeholder_data_model_product_doc "$dir" "t020-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t020.out" err="$TEST_DIR/t020.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t020-slug --pr 20 --commit e1e1e20)
  assert_exit "placeholder Data model refuses under enforce" 3 "$code"
  grep -qF 'Data model' "$err" \
    || log_fail "t020: REFUSED reason did not name the placeholder Data model section, got: $(cat "$err")"

  log_pass "Placeholder Data model counts as missing: enforce refuses, names the section (product-docs-enforced TEST-005)"
}

# --- product-docs-enforced TEST-006 (Spec-AC-02): placeholder Interfaces + --
# an explicit None. section counts as real --------------------------------

test_021_gate_placeholder_interfaces_and_none_dot_passes() {
  log_info "Test: placeholder Interfaces section counts as missing; a section reading None. counts as real and passes (product-docs-enforced TEST-006)..."
  local dir; dir=$(new_fixture_repo "t021")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t021a.md" "t021a-slug" "draft"
  write_placeholder_interfaces_product_doc "$dir" "t021a-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t021a.out" err="$TEST_DIR/t021a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t021a-slug --pr 21 --commit f1f1f21)
  assert_exit "placeholder Interfaces refuses under enforce" 3 "$code"
  grep -qF 'Interfaces and contracts' "$err" \
    || log_fail "t021a: REFUSED reason did not name the placeholder Interfaces section, got: $(cat "$err")"

  # Sibling case in the SAME fixture repo: a doc whose Data model AND
  # Interfaces both read the literal "None." must PASS (D2: "None." is REAL).
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0002-t021b.md" "t021b-slug" "draft"
  write_none_dot_product_doc "$dir" "t021b-slug"
  commit_fixture_docs "$dir"

  out="$TEST_DIR/t021b.out"; err="$TEST_DIR/t021b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t021b-slug --pr 21 --commit 01f1f21)
  assert_exit "None. sections pass under enforce" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t021b: explicit None. sections must PASS (be treated as real), got: $(cat "$err")"
  fi

  log_pass "Placeholder Interfaces refuses (named); explicit None. sections pass (product-docs-enforced TEST-006)"
}

# --- product-docs-enforced TEST-011 (Spec-AC-04 SEAM): best-effort rollup ---
# hook updates USER_GUIDE on a real close --------------------------------

test_022_seam_close_updates_userguide_rollup() {
  log_info "Test: SEAM -- a real close of a user_visible item with a real product doc updates the USER_GUIDE marked region (product-docs-enforced TEST-011)..."
  local dir; dir=$(new_fixture_repo "t022")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t022.md" "t022-slug" "draft"
  write_real_product_doc "$dir" "t022-slug"
  commit_fixture_docs "$dir"

  [[ ! -e "$dir/docs/USER_GUIDE.md" ]] \
    || log_fail "t022: fixture setup bug -- docs/USER_GUIDE.md must not pre-exist"

  local out="$TEST_DIR/t022.out" err="$TEST_DIR/t022.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t022-slug --pr 22 --commit a2a2a22)
  assert_exit "close with rollup hook" 0 "$code"

  [[ -f "$dir/docs/USER_GUIDE.md" ]] \
    || log_fail "t022: close did not regenerate docs/USER_GUIDE.md (best-effort rollup hook, D5)"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:BEGIN' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t022: USER_GUIDE.md missing the rollup BEGIN marker"
  grep -qF 'Fixture Feature t022-slug' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t022: rendered rollup does not carry the just-closed item's product doc title"

  log_pass "SEAM: a real close regenerates USER_GUIDE with the product doc rendered in the marked region (product-docs-enforced TEST-011)"
}

# --- product-docs-enforced TEST-012 (Spec-AC-04): negative control ----------
# a rigged rollup failure never changes the close exit code -----------------

test_023_negative_control_rollup_failure() {
  log_info "Test: NEGATIVE CONTROL -- a rigged rollup-generator failure leaves close exit 0, doc done, close events intact (no rollback) (product-docs-enforced TEST-012)..."
  local dir; dir=$(new_fixture_repo "t023")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t023.md" "t023-slug" "draft"
  commit_fixture_docs "$dir"

  # Rig the generator to fail: put a DIRECTORY where it must write a file, so
  # generate-userguide-rollup.mjs's fs.writeFileSync throws EISDIR -- the same
  # deterministic in-repo rigging technique as the overview-regen negative
  # control (test_015).
  mkdir -p "$dir/docs/USER_GUIDE.md"

  local out="$TEST_DIR/t023.out" err="$TEST_DIR/t023.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t023-slug --pr 23 --commit b2b2b23)
  assert_exit "close survives a rigged rollup failure" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t023.md" \
    || log_fail "t023: the close itself must NOT be rolled back by a rollup-generator failure -- doc must still be done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t023-slug)" -ge 1 ]] \
    || log_fail "t023: work_item_closed event must still be present (no rollback triggered by the rollup failure)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t023-slug)" -ge 1 ]] \
    || log_fail "t023: doc_lifecycle event must still be present (no rollback triggered by the rollup failure)"
  grep -qi 'userguide rollup regen skipped' "$out" "$err" 2>/dev/null || true

  log_pass "Generator failure is swallowed: close exit 0, doc still done, close events intact, no rollback (product-docs-enforced TEST-012)"
}

# --- product-docs-enforced TEST-013 (Spec-AC-05): legacy suite regression ---

test_024_legacy_suite_regression() {
  log_info "Test: full existing close-work-item suite (legacy TEST-001..015) stays green -- no regression from the product-doc gate + rollup hook (product-docs-enforced TEST-013)..."
  local legacy_tests="test_001_draft_close test_002_implementing_close test_003_non_done_terminal_guard \
test_004_ref_form_and_audit_clean test_005_pair_close test_006_pair_pre_write_abort \
test_007_idempotent_rerun test_008_fail_closed_rollback test_009_canon_grep_contract \
test_010_fail_closed_index_regen_rollback test_011_inline_nonempty_links_normalized \
test_012_null_fm_id_pre_write_guard test_013_brief_cleanup_on_close \
test_014_overview_regen_best_effort test_015_overview_regen_failure_negative_control"
  local t out
  for t in $legacy_tests; do
    out="$TEST_DIR/regress-$t.out"
    if ! bash "$TEST_SELF" "$t" > "$out" 2>&1; then
      log_fail "product-docs-enforced TEST-013: legacy $t FAILED under regression re-run: $(tail -20 "$out")"
    fi
  done
  log_pass "Legacy suite regression: all 15 pre-existing close-work-item tests still pass standalone (product-docs-enforced TEST-013)"
}

# --- product-docs-enforced TEST-014 (Spec-AC-05): guard-config dial (unit) --

test_025_guard_config_product_doc_gate_dial() {
  log_info "Test: guard-config readGuardConfig returns product_doc_gate for enforce, report-only, and invalid-value fail-open (product-docs-enforced TEST-014, unit)..."
  local dir="$TEST_DIR/t025-guard-config"
  mkdir -p "$dir"
  local probe="$TEST_DIR/t025-probe.mjs"
  cat > "$probe" <<PROBE
import { readGuardConfig } from '$GUARD_CONFIG_LIB';
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: enforce\n');
let cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'enforce') { console.error('expected enforce, got ' + cfg.product_doc_gate); process.exit(1); }

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: report-only\n');
cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected report-only, got ' + cfg.product_doc_gate); process.exit(1); }

let warned = false;
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: bogus\n');
cfg = readGuardConfig(dir, { warn: () => { warned = true; } });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected fail-open report-only for an invalid value, got ' + cfg.product_doc_gate); process.exit(1); }
if (!warned) { console.error('expected a warning callback on an invalid product_doc_gate value'); process.exit(1); }

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'legacy_until_date: 2020-01-01\n');
cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected default report-only when the key is absent, got ' + cfg.product_doc_gate); process.exit(1); }

console.log('OK');
PROBE

  node "$probe" "$dir" > "$TEST_DIR/t025.out" 2>&1 \
    || log_fail "product-docs-enforced TEST-014: guard-config product_doc_gate dial checks failed: $(cat "$TEST_DIR/t025.out")"

  log_pass "guard-config product_doc_gate: enforce / report-only / invalid-fail-open / absent-default all correct (product-docs-enforced TEST-014)"
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
  test_013_brief_cleanup_on_close
  test_014_overview_regen_best_effort
  test_015_overview_regen_failure_negative_control
  test_016_gate_report_only_warns
  test_017_gate_enforce_refuses_pre_write
  test_018_gate_absent_user_visible_negative_control
  test_019_gate_real_product_doc_passes_enforce
  test_020_gate_placeholder_data_model_counts_missing
  test_021_gate_placeholder_interfaces_and_none_dot_passes
  test_022_seam_close_updates_userguide_rollup
  test_023_negative_control_rollup_failure
  test_024_legacy_suite_regression
  test_025_guard_config_product_doc_gate_dial

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
