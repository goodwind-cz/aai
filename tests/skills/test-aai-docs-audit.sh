#!/usr/bin/env bash
#
# Test: aai-docs-audit skill (RFC-0002 / SPEC-0001)
# Verifies the docs hygiene & drift audit engine against an isolated fixture
# repo with one fixture per drift class (RFC-0002 Appendix C).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-docs-audit"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_SCRIPT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

assert_file() {
  [[ -f "$1" ]] || log_fail "Missing file: $1"
}

assert_contains() {
  grep -qF "$2" "$1" || log_fail "Expected '$2' in $1"
}

assert_not_contains() {
  if grep -qF "$2" "$1"; then
    log_fail "Did not expect '$2' in $1"
  fi
}

# Print the block of a markdown file/log starting at the heading line that
# begins with the literal prefix $2 (a "## " level-2 heading), up to the next
# heading of the same level. Used to assert a row lands in its OWN section.
extract_section() {
  awk -v want="$2" '
    /^## / { insec = (index($0, want) == 1) }
    insec { print }
  ' "$1"
}

# Same as extract_section but for "### " level-3 headings (docs-audit digest).
extract_section_h3() {
  awk -v want="$2" '
    /^### / { insec = (index($0, want) == 1) }
    insec { print }
  ' "$1"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$AUDIT_SCRIPT" ]] || log_fail "Audit script not found: $AUDIT_SCRIPT"
  log_pass "Dependencies checked"
}

run_audit() {
  (cd "$TEST_DIR" && node .aai/scripts/docs-audit.mjs "$@")
}

setup_fixture() {
  log_info "Setting up fixture repo..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-audit-test.XXXXXX")"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "AAI Test"

  mkdir -p .aai/scripts/lib docs/issues docs/specs docs/ai
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" .aai/scripts/
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" .aai/scripts/
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" .aai/scripts/
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs .aai/scripts/lib/

  git add .aai && git commit -qm "chore: vendor audit scripts"

  # Class 1a — legacy orphan: no frontmatter, committed before legacy_until_date
  cat > docs/issues/ISSUE-001-orphan-legacy.md <<'MD'
# Old issue without frontmatter
Legacy content predating the template mandate.
MD
  # Class 3 — stale-open: valid frontmatter, no activity since the backdated commit
  cat > docs/issues/ISSUE-203-stale-open.md <<'MD'
---
id: ISSUE-203
type: issue
status: implementing
links:
  pr: []
---
# Stale open issue
MD
  git add docs/issues/ISSUE-001-orphan-legacy.md docs/issues/ISSUE-203-stale-open.md
  GIT_COMMITTER_DATE="2026-01-15T10:00:00Z" GIT_AUTHOR_DATE="2026-01-15T10:00:00Z" \
    git commit -qm "docs: legacy fixtures"

  # Class 2 — false-done: status done, AC table not terminal / missing evidence
  cat > docs/specs/SPEC-201-false-done.md <<'MD'
---
id: SPEC-201
type: spec
status: done
links:
  pr: []
---
# False done spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | done         | a1b2c3d  | —         | —     |
| Spec-AC-02 | second      | implementing | —        | —         | —     |
| Spec-AC-03 | third       | implementing | —        | —         | —     |
MD
  # Class 2 variant — partial: spec marked done without the mandated AC table
  cat > docs/specs/SPEC-202-partial.md <<'MD'
---
id: SPEC-202
type: spec
status: done
links:
  pr: []
---
# Done spec without AC table
MD
  # Control — aligned: done with fully terminal, evidenced AC table
  cat > docs/specs/SPEC-204-aligned.md <<'MD'
---
id: SPEC-204
type: spec
status: done
links:
  pr: []
---
# Aligned spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | —         | —     |
| Spec-AC-02 | second      | done   | b2c3d4e  | —         | —     |
MD
  git add docs/specs && git commit -qm "feat: ship SPEC-201 SPEC-202 SPEC-204"

  # Class 1b — new orphan: no frontmatter, committed after legacy_until_date
  cat > docs/issues/ISSUE-101-orphan-new.md <<'MD'
# New issue without frontmatter
Added recently, skipping the template.
MD
  git add docs/issues/ISSUE-101-orphan-new.md && git commit -qm "feat(docs): add ISSUE-101"

  log_pass "Fixture repo ready"
}

test_report_only_without_config() {
  log_info "Test: missing config means report-only (TEST-003)..."
  run_audit --check --no-event > "$TEST_DIR/report-only.log" \
    || log_fail "--check must exit 0 in report-only mode"
  assert_contains "$TEST_DIR/report-only.log" "Mode: report-only"
  assert_contains "$TEST_DIR/report-only.log" "docs-audit.yaml not found"
  log_pass "Report-only mode is lenient and explains enforcement"
}

test_strict_path_intake_gate() {
  log_info "Test: --strict --path hard-fails a new non-compliant artifact (intake gate)..."
  cat > "$TEST_DIR/docs/issues/ISSUE-999-untracked.md" <<'MD'
# Untracked artifact missing frontmatter
MD
  if run_audit --check --strict --no-event --path docs/issues/ISSUE-999-untracked.md \
      > "$TEST_DIR/strict.log"; then
    log_fail "--check --strict must exit 1 for a frontmatter-less new artifact"
  fi
  assert_contains "$TEST_DIR/strict.log" "ISSUE-999-untracked.md"
  rm "$TEST_DIR/docs/issues/ISSUE-999-untracked.md"
  log_pass "Strict intake gate blocks non-compliant artifacts"
}

write_config() {
  cat > "$TEST_DIR/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2026-06-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
YAML
}

test_orphan_split() {
  log_info "Test: new orphan hard-fails, legacy orphan soft-warns (TEST-001)..."
  if run_audit --check --no-event > "$TEST_DIR/enforced.log"; then
    log_fail "--check must exit 1 with a new orphan present"
  fi
  assert_contains "$TEST_DIR/enforced.log" "Mode: enforced"
  assert_contains "$TEST_DIR/enforced.log" "CHECK FAILED: 1 new orphan(s)"
  grep -F "ISSUE-101-orphan-new.md" "$TEST_DIR/enforced.log" | grep -qF "new (hard)" \
    || log_fail "ISSUE-101 must classify as new (hard)"
  grep -F "ISSUE-001-orphan-legacy.md" "$TEST_DIR/enforced.log" | grep -qF "legacy (soft)" \
    || log_fail "ISSUE-001 must classify as legacy (soft)"
  log_pass "Legacy/new orphan split works"
}

test_drift_verdicts() {
  log_info "Test: drift verdicts per class (TEST-002)..."
  local log="$TEST_DIR/enforced.log"
  grep -F "SPEC-201" "$log" | grep -qF "probable-false-done" \
    || log_fail "SPEC-201 must be probable-false-done"
  grep -F "SPEC-202" "$log" | grep -qF "probable-partial" \
    || log_fail "SPEC-202 must be probable-partial"
  grep -F "ISSUE-203" "$log" | grep -qF "probable-stale-open" \
    || log_fail "ISSUE-203 must be probable-stale-open"
  assert_not_contains "$log" "SPEC-204"
  log_pass "All drift verdicts correct; aligned doc stays out of the report"
}

test_events_emission() {
  log_info "Test: full run appends a docs_audit event (TEST-004)..."
  run_audit > "$TEST_DIR/event-run.log" || true
  assert_file "$TEST_DIR/docs/ai/EVENTS.jsonl"
  tail -1 "$TEST_DIR/docs/ai/EVENTS.jsonl" | grep -qF '"event":"docs_audit"' \
    || log_fail "Last EVENTS line must be a docs_audit event"
  tail -1 "$TEST_DIR/docs/ai/EVENTS.jsonl" | grep -qF '"orphans":2' \
    || log_fail "docs_audit payload must carry orphan count"
  log_pass "docs_audit event emitted with counts"
}

test_quick_mode() {
  log_info "Test: --quick is counts-only and emits no event (TEST-006)..."
  local before after
  before="$(wc -l < "$TEST_DIR/docs/ai/EVENTS.jsonl")"
  run_audit --quick > "$TEST_DIR/quick.log"
  after="$(wc -l < "$TEST_DIR/docs/ai/EVENTS.jsonl")"
  [[ "$before" == "$after" ]] || log_fail "--quick must not append a docs_audit event"
  assert_contains "$TEST_DIR/quick.log" "Mode: quick"
  assert_not_contains "$TEST_DIR/quick.log" "### Orphans"
  log_pass "Quick mode stays cheap and event-free"
}

test_index_sections_and_idempotence() {
  log_info "Test: INDEX gains audit sections and is idempotent (TEST-005, TEST-007)..."
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > index-run1.log 2>&1) \
    || log_fail "generate-docs-index.mjs failed: $(cat "$TEST_DIR/index-run1.log")"
  local index="$TEST_DIR/docs/INDEX.md"
  assert_file "$index"
  # RFC-0001 sections survive the lib extraction (TEST-007)
  assert_contains "$index" "## Done"
  assert_contains "$index" "Legacy (no frontmatter)"
  # RFC-0002 sections (TEST-005)
  assert_contains "$index" "## Orphans (need triage) (2)"
  assert_contains "$index" "## Drift report (3)"
  assert_contains "$index" "probable-false-done"

  grep -v '^Generated:' "$index" > "$TEST_DIR/index-run1.snapshot"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > index-run2.log 2>&1)
  grep -v '^Generated:' "$index" > "$TEST_DIR/index-run2.snapshot"
  diff -q "$TEST_DIR/index-run1.snapshot" "$TEST_DIR/index-run2.snapshot" >/dev/null \
    || log_fail "INDEX must be idempotent modulo the Generated timestamp"
  log_pass "INDEX sections present and idempotent"
}

# --- CHANGE-0001 regression fixtures (downstream first-run findings) ---------

test_compound_ids_and_frozen_markers() {
  log_info "Test: compound IDs scanned; legacy SPEC-FROZEN body markers honored (D1, D2)..."
  mkdir -p "$TEST_DIR/docs/decisions"

  # D1+D2 — compound ID, draft frontmatter, bold frozen marker, stale-aged commit:
  # without the marker tolerance this would flag probable-stale-open
  cat > "$TEST_DIR/docs/specs/SPEC-CHANGE-027.md" <<'MD'
---
id: SPEC-CHANGE-027
type: spec
status: draft
links:
  pr: []
---
# Compound-ID spec

## 📋 Spec Status
- **SPEC-FROZEN:** true
MD
  # D1+D2 — emoji-prefixed bare marker form
  cat > "$TEST_DIR/docs/specs/SPEC-PROC-10-import-triggering.md" <<'MD'
---
id: SPEC-PROC-10
type: spec
status: draft
links:
  pr: []
---
# Import triggering

📋 SPEC-FROZEN: true
MD
  (cd "$TEST_DIR" \
    && git add docs/specs/SPEC-CHANGE-027.md docs/specs/SPEC-PROC-10-import-triggering.md \
    && GIT_COMMITTER_DATE="2026-01-15T10:00:00Z" GIT_AUTHOR_DATE="2026-01-15T10:00:00Z" \
       git commit -qm "docs: frozen compound specs")

  # D1 — remaining compound-ID shapes from the brief
  cat > "$TEST_DIR/docs/decisions/DECISION-RFC-002-operator-permission-gating.md" <<'MD'
---
id: DECISION-RFC-002
type: decision
status: accepted
links:
  pr: []
---
# Decision
MD
  cat > "$TEST_DIR/docs/decisions/DECISION-SPEC-FE-13-implementation-reconciliation.md" <<'MD'
---
id: DECISION-SPEC-FE-13
type: decision
status: done
links:
  pr: []
---
# Reconciliation decision
MD
  cat > "$TEST_DIR/docs/specs/SPEC-PRD-022-new-player-draft-reactivation.md" <<'MD'
---
id: SPEC-PRD-022
type: spec
status: implementing
links:
  pr: []
---
# Draft reactivation

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | implementing | —        | —         | —     |
MD
  (cd "$TEST_DIR" && git add docs/decisions docs/specs \
    && git commit -qm "docs: DECISION-RFC-002 DECISION-SPEC-FE-13 SPEC-PRD-022 fixtures")

  run_audit --no-event > "$TEST_DIR/compound.log"
  assert_contains "$TEST_DIR/compound.log" "Scanned: 11 docs"
  assert_not_contains "$TEST_DIR/compound.log" "SPEC-CHANGE-027"
  assert_not_contains "$TEST_DIR/compound.log" "SPEC-PROC-10"
  log_pass "Compound IDs visible; frozen-in-body specs not flagged stale"
}

test_reviewby_literals() {
  log_info "Test: Review-By accepts skill literals and label:date combos (D4)..."
  cat > "$TEST_DIR/docs/specs/SPEC-301-reviewby-literals.md" <<'MD'
---
id: SPEC-301
type: spec
status: done
links:
  pr: []
---
# Spec validated via skills

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By              | Notes |
|------------|-------------|--------|----------|------------------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD                    | —     |
| Spec-AC-02 | second      | done   | b2c3d4e  | Loop                   | —     |
| Spec-AC-03 | third       | done   | c3d4e5f  | code-review:2026-05-01 | —     |
MD
  (cd "$TEST_DIR" && git add docs/specs/SPEC-301-reviewby-literals.md \
    && git commit -qm "feat: ship SPEC-301")
  run_audit --check --no-event --path docs/specs/SPEC-301-reviewby-literals.md \
    > "$TEST_DIR/reviewby.log" \
    || log_fail "Review-By skill literals must not be schema violations"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > reviewby-index.log 2>&1) \
    || log_fail "generate-docs-index must accept Review-By literals: $(cat "$TEST_DIR/reviewby-index.log")"
  log_pass "Review-By literals and combos accepted"
}

test_uncommitted_doc_not_punished() {
  log_info "Test: uncommitted doc with valid frontmatter passes --check (D6)..."
  cat > "$TEST_DIR/docs/issues/ISSUE-301-fresh.md" <<'MD'
# Fresh doc, no frontmatter yet
MD
  if run_audit --check --no-event --path docs/issues/ISSUE-301-fresh.md > /dev/null; then
    log_fail "Frontmatter-less new doc must fail --check"
  fi
  cat > "$TEST_DIR/docs/issues/ISSUE-301-fresh.md" <<'MD'
---
id: ISSUE-301
type: issue
status: draft
links:
  pr: []
---
# Fresh doc, frontmatter added inline, not yet committed
MD
  run_audit --check --no-event --path docs/issues/ISSUE-301-fresh.md \
    > "$TEST_DIR/pending.log" \
    || log_fail "Doc must stop being an orphan the moment frontmatter is saved (no commit needed)"
  assert_contains "$TEST_DIR/pending.log" "Pending commit"
  assert_contains "$TEST_DIR/pending.log" "ISSUE-301-fresh.md"
  rm "$TEST_DIR/docs/issues/ISSUE-301-fresh.md"
  log_pass "Working tree wins over git state; pending-commit notice shown"
}

test_type_validation() {
  log_info "Test: unknown type warns by default, fails with --strict-types (D7)..."
  cat > "$TEST_DIR/docs/issues/ISSUE-302-bad-type.md" <<'MD'
---
id: ISSUE-302
type: spc
status: draft
links:
  pr: []
---
# Typo in type field
MD
  run_audit --check --no-event --path docs/issues/ISSUE-302-bad-type.md \
    > "$TEST_DIR/type-soft.log" \
    || log_fail "Unknown type must stay a soft warning by default"
  grep -F "ISSUE-302" "$TEST_DIR/type-soft.log" | grep -qF 'unknown type "spc"' \
    || log_fail "Digest must warn about the unknown type"
  if run_audit --check --strict-types --no-event --path docs/issues/ISSUE-302-bad-type.md \
      > /dev/null; then
    log_fail "--strict-types must promote unknown type to a hard failure"
  fi
  rm "$TEST_DIR/docs/issues/ISSUE-302-bad-type.md"
  log_pass "Type enum validated softly, strictly on demand"
}

test_orphan_suggested_id() {
  log_info "Test: orphan table shows the filename-inferred ID (D8)..."
  run_audit --no-event > "$TEST_DIR/suggested-id.log"
  assert_contains "$TEST_DIR/suggested-id.log" "Suggested ID"
  grep -F "ISSUE-101-orphan-new.md" "$TEST_DIR/suggested-id.log" | grep -qF "ISSUE-101" \
    || log_fail "Orphan row must carry the inferred ID ISSUE-101"
  log_pass "Suggested ID column present"
}

test_classification_listing() {
  log_info "Test: --list prints the per-doc classification table..."
  run_audit --list --no-event > "$TEST_DIR/list.log"
  assert_contains "$TEST_DIR/list.log" "### Classification:"
  grep -F "SPEC-204" "$TEST_DIR/list.log" | grep -qF "tracked-done" \
    || log_fail "SPEC-204 must list as tracked-done"
  grep -F "SPEC-201" "$TEST_DIR/list.log" | grep -qF "drifted" \
    || log_fail "SPEC-201 must list as drifted"
  grep -F "SPEC-CHANGE-027" "$TEST_DIR/list.log" | grep -qF "frozen" \
    || log_fail "SPEC-CHANGE-027 must show effective status frozen"
  grep -F "ISSUE-101" "$TEST_DIR/list.log" | grep -qF "orphan" \
    || log_fail "ISSUE-101 must list as orphan"
  log_pass "Per-doc classification table works"
}

# --- CHANGE-0002 regression fixtures (D10-D15) --------------------------------

test_reviewby_actor_method() {
  log_info "Test: Review-By accepts actor+method composition, rejects bare actor (D10)..."
  cat > "$TEST_DIR/docs/specs/SPEC-302-actor-method.md" <<'MD'
---
id: SPEC-302
type: spec
status: done
links:
  pr: []
---
# Spec validated by model+method

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By                            | Notes |
|------------|-------------|--------|----------|--------------------------------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | claude-sonnet-4-6 PlaywrightSuites   | —     |
| Spec-AC-02 | second      | done   | b2c3d4e  | claude-opus-4-7 TDD-snapshot-scripts | —     |
| Spec-AC-03 | third       | done   | c3d4e5f  | claude-sonnet-4-6 Validation         | —     |
| Spec-AC-04 | fourth      | done   | d4e5f6a  | human:ales code-review               | —     |
| Spec-AC-05 | fifth       | done   | e5f6a7b  | claude-sonnet-4-6 TDD:2026-06-01     | —     |
MD
  (cd "$TEST_DIR" && git add docs/specs/SPEC-302-actor-method.md \
    && git commit -qm "feat: ship SPEC-302")
  run_audit --check --no-event --path docs/specs/SPEC-302-actor-method.md \
    > "$TEST_DIR/actor-method.log" \
    || log_fail "actor+method Review-By literals must validate"

  cat > "$TEST_DIR/docs/specs/SPEC-303-bare-actor.md" <<'MD'
---
id: SPEC-303
type: spec
status: done
links:
  pr: []
---
# Bare actor without method

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By         | Notes |
|------------|-------------|--------|----------|-------------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | claude-sonnet-4-6 | —     |
MD
  if run_audit --check --no-event --path docs/specs/SPEC-303-bare-actor.md \
      > "$TEST_DIR/bare-actor.log"; then
    log_fail "Bare actor without method must stay a violation"
  fi
  assert_contains "$TEST_DIR/bare-actor.log" "invalid Review-By"
  rm "$TEST_DIR/docs/specs/SPEC-303-bare-actor.md"
  log_pass "Actor+method composition validated; bare actor rejected"
}

test_events_parent_subref_boundary() {
  log_info "Test: PARENT-ID/sub-item refs work; sibling IDs don't cross-match (D11)..."
  cat > "$TEST_DIR/docs/issues/CHANGE-004-parent.md" <<'MD'
---
id: CHANGE-004
type: change
status: done
links:
  pr: []
---
# Multi-file parent change
MD
  (cd "$TEST_DIR" && git add docs/issues/CHANGE-004-parent.md \
    && git commit -qm "docs: add multi-file parent fixture")

  # evidence for a SIBLING id (CHANGE-0045) must not count for CHANGE-004
  (cd "$TEST_DIR" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref CHANGE-0045/other-doc --evidence "unrelated" > /dev/null)
  run_audit --no-event --path docs/issues/CHANGE-004-parent.md \
    > "$TEST_DIR/subref-neg.log"
  grep -F "CHANGE-004" "$TEST_DIR/subref-neg.log" | grep -qF "probable-false-done" \
    || log_fail "CHANGE-0045 evidence must not satisfy CHANGE-004"

  # a true sub-item ref under the parent does count
  (cd "$TEST_DIR" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref CHANGE-004/person-linking --evidence "a1b2c3d" > /dev/null)
  run_audit --no-event --path docs/issues/CHANGE-004-parent.md \
    > "$TEST_DIR/subref-pos.log"
  assert_not_contains "$TEST_DIR/subref-pos.log" "probable-false-done"
  log_pass "Sub-item refs roll up to the parent; sibling IDs are bounded"
}

test_plan_scan_mode() {
  log_info "Test: docs/plans/* lenient by default, strict on demand (D12)..."
  mkdir -p "$TEST_DIR/docs/plans/done"
  cat > "$TEST_DIR/docs/plans/PLAN-2026-backlog-overview.md" <<'MD'
# Operator backlog plan — no frontmatter by design
MD
  cat > "$TEST_DIR/docs/plans/done/PRD-050-shipped-plan.md" <<'MD'
# Done plan note — no frontmatter by design
MD
  (cd "$TEST_DIR" && git add docs/plans && git commit -qm "docs: operator plans")

  run_audit --check --no-event --path docs/plans > "$TEST_DIR/plans-lenient.log" \
    || log_fail "Lenient mode must not hard-fail operator plan files"
  assert_contains "$TEST_DIR/plans-lenient.log" "Orphans (need triage): 0"
  grep -qF "operator plan file" "$TEST_DIR/plans-lenient.log" \
    || log_fail "Lenient plans must be annotated in the digest"

  printf 'plan_scan_mode: strict\n' >> "$TEST_DIR/docs/ai/docs-audit.yaml"
  if run_audit --check --no-event --path docs/plans > "$TEST_DIR/plans-strict.log"; then
    log_fail "Strict mode must flag frontmatter-less plan files as orphans"
  fi
  # restore lenient default for the remaining tests
  grep -v 'plan_scan_mode' "$TEST_DIR/docs/ai/docs-audit.yaml" > "$TEST_DIR/docs/ai/docs-audit.yaml.tmp" \
    && mv "$TEST_DIR/docs/ai/docs-audit.yaml.tmp" "$TEST_DIR/docs/ai/docs-audit.yaml"
  log_pass "plan_scan_mode lenient/strict works"
}

test_suggested_multi_ids() {
  log_info "Test: Suggested ID lists all ID shapes in the filename (D14)..."
  cat > "$TEST_DIR/docs/issues/PRD-022-024-025-planned-test-files.md" <<'MD'
# Multi-ID orphan
MD
  cat > "$TEST_DIR/docs/issues/PRD-022-TEST-021-club-scoped-user.md" <<'MD'
# Cross-ID orphan
MD
  run_audit --no-event > "$TEST_DIR/multi-id.log"
  assert_contains "$TEST_DIR/multi-id.log" "PRD-022 (primary) + PRD-024 + PRD-025"
  assert_contains "$TEST_DIR/multi-id.log" "PRD-022 (primary) + TEST-021"
  rm "$TEST_DIR/docs/issues/PRD-022-024-025-planned-test-files.md" \
     "$TEST_DIR/docs/issues/PRD-022-TEST-021-club-scoped-user.md"
  log_pass "Multi-ID filenames suggest primary + related"
}

test_category_prefix_scope() {
  log_info "Test: category prefixes derive unique slug IDs with scope (D15)..."
  mkdir -p "$TEST_DIR/docs/decisions"
  cat > "$TEST_DIR/docs/decisions/DECISION-PHASE-0-scope.md" <<'MD'
# Phase 0 scope decision — no frontmatter
MD
  cat > "$TEST_DIR/docs/decisions/DECISION-PHASE-0-continue-session.md" <<'MD'
# Phase 0 continuation decision — no frontmatter
MD
  run_audit --list --no-event > "$TEST_DIR/phase.log"
  assert_contains "$TEST_DIR/phase.log" "DECISION-PHASE-0-scope"
  assert_contains "$TEST_DIR/phase.log" "DECISION-PHASE-0-continue-session"
  grep -F "DECISION-PHASE-0-scope" "$TEST_DIR/phase.log" | grep -qF "PHASE-0" \
    || log_fail "--list must surface the PHASE-0 scope"
  rm "$TEST_DIR/docs/decisions/DECISION-PHASE-0-scope.md" \
     "$TEST_DIR/docs/decisions/DECISION-PHASE-0-continue-session.md"
  log_pass "Category-prefixed filenames get unique IDs plus scope"
}

test_index_legacy_autoskip() {
  log_info "Test: index gen auto-skips violations in legacy docs (D13)..."
  cat > "$TEST_DIR/docs/specs/SPEC-100-legacy-bad.md" <<'MD'
---
id: SPEC-100
type: spec
status: implementing
links:
  pr: []
---
# Legacy spec with a pre-canon AC status value

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | wip    | —        | —         | —     |
MD
  (cd "$TEST_DIR" && git add docs/specs/SPEC-100-legacy-bad.md \
    && GIT_COMMITTER_DATE="2026-01-15T10:00:00Z" GIT_AUTHOR_DATE="2026-01-15T10:00:00Z" \
       git commit -qm "docs: legacy spec fixture")
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > legacy-skip.log 2>&1) \
    || log_fail "Legacy-doc violations must auto-skip, not hard-fail: $(cat "$TEST_DIR/legacy-skip.log")"
  assert_contains "$TEST_DIR/docs/INDEX.md" "legacy — auto-skipped"
  assert_contains "$TEST_DIR/docs/INDEX.md" "SPEC-100"
  (cd "$TEST_DIR" && git rm -q docs/specs/SPEC-100-legacy-bad.md \
    && git commit -qm "docs: drop legacy fixture")
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Legacy violations demote to the Skipped section automatically"
}

test_skill_prompt_modes() {
  log_info "Test: skill prompt documents all three modes (CHANGE-0003 guard)..."
  local prompt="$PROJECT_ROOT/.aai/SKILL_DOCS_AUDIT.prompt.md"
  assert_file "$prompt"
  assert_contains "$prompt" "PROCESS"
  assert_contains "$prompt" "REMEDIATION MODE"
  assert_contains "$prompt" "VERIFY MODE"
  assert_contains "$prompt" "never writes or"
  log_pass "Audit / remediate / verify modes all documented"
}

test_index_continue_on_error() {
  log_info "Test: index generator --continue-on-error renders a partial index (D9)..."
  cat > "$TEST_DIR/docs/specs/SPEC-998-bad-status.md" <<'MD'
---
id: SPEC-998
type: spec
status: bogus
links:
  pr: []
---
# Schema-violating doc
MD
  if (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > index-fail.log 2>&1); then
    log_fail "Default index run must still hard-fail on schema violations"
  fi
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs --continue-on-error \
    > index-partial.log 2>&1) \
    || log_fail "--continue-on-error must exit 0: $(cat "$TEST_DIR/index-partial.log")"
  assert_contains "$TEST_DIR/docs/INDEX.md" "Skipped (schema violations)"
  assert_contains "$TEST_DIR/docs/INDEX.md" "SPEC-998"
  rm "$TEST_DIR/docs/specs/SPEC-998-bad-status.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Partial index with skipped-violations section works"
}

# --- SPEC-0003 closeout-candidate fixtures (CHANGE-0004) ----------------------

# Builds an isolated subtree (docs/closeout/) holding every closeout case plus a
# committed positive control. Scoped audits over this subtree keep the new
# classification independent of the orphan/drift fixtures above.
setup_closeout_fixture() {
  log_info "Setting up closeout-candidate fixture (SPEC-0003)..."
  mkdir -p "$TEST_DIR/docs/closeout"
  cd "$TEST_DIR"

  # Positive control: non-terminal rfc parent whose every linked spec is done
  # (forward links.spec AND reverse links.rfc both exercised).
  cat > docs/closeout/RFC-0010-shipped-parent.md <<'MD'
---
id: RFC-0010
type: rfc
status: proposed
links:
  spec: SPEC-0010
---
# Shipped parent RFC — all linked specs done
MD
  cat > docs/closeout/SPEC-0010-done-child.md <<'MD'
---
id: SPEC-0010
type: spec
status: done
links:
  rfc: RFC-0010
---
# Done child spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD

  # TEST-002: implementing parent with one linked spec still implementing.
  cat > docs/closeout/RFC-0020-mixed-parent.md <<'MD'
---
id: RFC-0020
type: rfc
status: implementing
links:
  spec: [SPEC-0021, SPEC-0022]
---
# Mixed parent — one spec still open
MD
  cat > docs/closeout/SPEC-0021-done.md <<'MD'
---
id: SPEC-0021
type: spec
status: done
links:
  rfc: RFC-0020
---
# Done sibling

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  cat > docs/closeout/SPEC-0022-open.md <<'MD'
---
id: SPEC-0022
type: spec
status: implementing
links:
  rfc: RFC-0020
---
# Still-open sibling
MD

  # TEST-003: terminal (done/superseded) and draft parents are never flagged.
  cat > docs/closeout/RFC-0030-done-parent.md <<'MD'
---
id: RFC-0030
type: rfc
status: done
links:
  spec: SPEC-0031
---
# Already-terminal parent
MD
  cat > docs/closeout/SPEC-0031-done.md <<'MD'
---
id: SPEC-0031
type: spec
status: done
links:
  rfc: RFC-0030
---
# Done spec under a done parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  cat > docs/closeout/RFC-0032-superseded-parent.md <<'MD'
---
id: RFC-0032
type: rfc
status: superseded
links:
  spec: SPEC-0033
---
# Superseded parent
MD
  cat > docs/closeout/SPEC-0033-done.md <<'MD'
---
id: SPEC-0033
type: spec
status: done
links:
  rfc: RFC-0032
---
# Done spec under a superseded parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  cat > docs/closeout/RFC-0034-draft-parent.md <<'MD'
---
id: RFC-0034
type: rfc
status: draft
links:
  spec: SPEC-0035
---
# Draft parent — not yet ready
MD
  cat > docs/closeout/SPEC-0035-done.md <<'MD'
---
id: SPEC-0035
type: spec
status: done
links:
  rfc: RFC-0034
---
# Done spec under a draft parent

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD

  # TEST-005: false-positive guards — no-link parent, change-type doc, and a
  # parent linking an unresolvable spec id.
  cat > docs/closeout/RFC-0050-no-link.md <<'MD'
---
id: RFC-0050
type: rfc
status: proposed
links:
  pr: []
---
# Parent with no linked specs at all
MD
  cat > docs/closeout/CHANGE-0050-change-parent.md <<'MD'
---
id: CHANGE-0050
type: change
status: proposed
links:
  spec: SPEC-0051
---
# change-type doc linking an all-done spec — out of parent scope
MD
  cat > docs/closeout/SPEC-0051-done.md <<'MD'
---
id: SPEC-0051
type: spec
status: done
links:
  pr: []
---
# Done spec linked only by a change-type doc

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  cat > docs/closeout/RFC-0052-unresolvable.md <<'MD'
---
id: RFC-0052
type: rfc
status: proposed
links:
  spec: SPEC-9999
---
# Parent linking a spec id absent from the scan — cannot prove all-done
MD

  # TEST-007 (WARN-1): reverse-ONLY association — parent has NO links.spec; the
  # done spec points back via links.rfc. Independently exercises the reverse
  # resolution block (removing it would fail this test, unlike RFC-0010 which is
  # also reachable forward).
  cat > docs/closeout/RFC-0060-reverse-only.md <<'MD'
---
id: RFC-0060
type: rfc
status: proposed
links:
  pr: []
---
# Parent with no forward links.spec; only the child links back
MD
  cat > docs/closeout/SPEC-0060-done-reverse.md <<'MD'
---
id: SPEC-0060
type: spec
status: done
links:
  rfc: RFC-0060
---
# Done child that names its parent via links.rfc

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD

  # TEST-008 (INFO-1): parent's forward links.spec names a NON-spec done doc.
  # Must NOT be flagged — "all linked specs done" requires the resolved target to
  # actually be a spec, not any done doc (guards against a misfiled link).
  cat > docs/closeout/RFC-0070-forward-nonspec.md <<'MD'
---
id: RFC-0070
type: rfc
status: proposed
links:
  spec: CHANGE-0070
---
# Parent whose links.spec mistakenly names a non-spec (done) doc
MD
  cat > docs/closeout/CHANGE-0070-done-nonspec.md <<'MD'
---
id: CHANGE-0070
type: change
status: done
links:
  pr: []
---
# A done CHANGE doc — not a spec; must not satisfy all-specs-done
MD

  git add docs/closeout && git commit -qm "test: closeout-candidate fixtures (SPEC-0003)"
  log_pass "Closeout fixture ready"
}

test_closeout_candidate_flagged() {
  log_info "Test: non-terminal rfc parent with all-done specs flagged (TEST-001)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  assert_contains "$TEST_DIR/closeout.log" "Closeout candidates"
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"
  grep -F "RFC-0010" "$TEST_DIR/closeout.log" | grep -qF "SPEC-0010" \
    || log_fail "Closeout row must name both parent RFC-0010 and done SPEC-0010"
  log_pass "Closeout candidate flagged with parent + satisfying spec id"
}

test_closeout_spec_not_all_done() {
  log_info "Test: parent with a non-done linked spec is NOT flagged; control IS (TEST-002)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  # positive control (RED-proof): flagging must genuinely work before this passes
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0020 to"
  log_pass "Mixed-status parent withheld; positive control flagged"
}

test_closeout_terminal_parent() {
  log_info "Test: terminal/draft parents never flagged; control IS (TEST-003)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0030 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0032 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0034 to"
  log_pass "Terminal (done/superseded) and draft parents excluded"
}

test_closeout_read_only() {
  log_info "Test: audit makes zero doc mutations over closeout fixture (TEST-004)..."
  local before after
  before="$(cd "$TEST_DIR" && find docs/closeout -type f -name '*.md' | sort | xargs shasum | shasum)"
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  # control proves the run actually produced a candidate (genuine RED pre-feature)
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"
  after="$(cd "$TEST_DIR" && find docs/closeout -type f -name '*.md' | sort | xargs shasum | shasum)"
  [[ "$before" == "$after" ]] || log_fail "Audit must not modify any closeout doc file"
  [[ -z "$(cd "$TEST_DIR" && git status --porcelain -- docs/closeout)" ]] \
    || log_fail "git working tree under docs/closeout must stay clean after audit"
  log_pass "Audit is read-only over the closeout fixture"
}

test_closeout_no_false_positive() {
  log_info "Test: no-link / change-type / unresolvable parents not flagged; control IS (TEST-005)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0050 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance CHANGE-0050 to"
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0052 to"
  log_pass "No new false positives from the closeout pass"
}

test_closeout_report_only_gate() {
  log_info "Test: closeout pass is report-only; --check --strict still exits 0 (TEST-006)..."
  run_audit --check --strict --no-event --path docs/closeout > "$TEST_DIR/closeout-gate.log" \
    || log_fail "Closeout candidates must not change the --check --strict exit code"
  assert_contains "$TEST_DIR/closeout-gate.log" "Closeout candidates"
  assert_contains "$TEST_DIR/closeout-gate.log" "advance RFC-0010 to"
  log_pass "Closeout classification is report-only (gate-neutral)"
}

test_closeout_reverse_only() {
  log_info "Test: reverse-only association (child links.rfc, parent has no links.spec) flagged (TEST-007)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"   # positive control
  # the parent is reachable ONLY through the spec's reverse links.rfc
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0060 to"
  grep -F "RFC-0060" "$TEST_DIR/closeout.log" | grep -qF "SPEC-0060" \
    || log_fail "Reverse-only closeout row must name parent RFC-0060 and done SPEC-0060"
  log_pass "Reverse-only (links.rfc) association independently flagged"
}

test_closeout_forward_nonspec_not_flagged() {
  log_info "Test: forward links.spec to a NON-spec done doc is NOT flagged; control IS (TEST-008)..."
  run_audit --no-event --path docs/closeout > "$TEST_DIR/closeout.log"
  assert_contains "$TEST_DIR/closeout.log" "advance RFC-0010 to"   # positive control
  # RFC-0070's links.spec names CHANGE-0070 (type change, done) — not a spec
  assert_not_contains "$TEST_DIR/closeout.log" "advance RFC-0070 to"
  log_pass "Forward link to a non-spec done doc does not satisfy all-specs-done"
}

# --- SPEC-0006 fixtures (DEBT-0001): whole-doc deferred coverage + done close-policy ----

# Isolated subtree holding the open-decision-on-done cases (TEST-006). Committed
# so the strict gate treats them as real tracked docs.
setup_spec0006_opendecision_fixture() {
  log_info "Setting up open-decision-on-done fixture (SPEC-0006)..."
  mkdir -p "$TEST_DIR/docs/opendecision"
  cd "$TEST_DIR"

  # Flagged: a done spec carrying a buried open-decision WARNING in its body.
  cat > docs/opendecision/SPEC-9100-open-decision.md <<'MD'
---
id: SPEC-9100
type: spec
status: done
links:
  pr: []
---
# Closed spec carrying a buried open decision

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | only        | done   | a1b2c3d  | TDD       | —     |

WARNING: decisions RR-1 and RR-2 must be confirmed before the next release.
MD

  # Negative control: a done spec with only an ordinary informational note plus a
  # fenced code example that merely *looks* like a warning (must NOT be flagged).
  cat > docs/opendecision/SPEC-9101-informational.md <<'MD'
---
id: SPEC-9101
type: spec
status: done
links:
  pr: []
---
# Closed spec with only an informational note

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | only        | done   | b2c3d4e  | TDD       | —     |

Note: this behavior is documented in the user guide; see the changelog.

See `WARNING: mentions unresolved as an example in inline code` — not a real decision.

```
WARNING: this example value must be confirmed by the operator before use.
```
MD
  git add docs/opendecision && git commit -qm "test: open-decision-on-done fixtures (SPEC-0006)"
  log_pass "Open-decision fixture ready"
}

test_spec0006_deferred_whole_doc_section() {  # TEST-001 / Spec-AC-01
  log_info "Test: whole-doc deferred renders its own INDEX section, distinct from per-AC (TEST-001)..."
  cat > "$TEST_DIR/docs/specs/SPEC-9001-whole-deferred.md" <<'MD'
---
id: SPEC-9001
type: spec
status: deferred
links:
  pr: []
---
# Whole-doc deferred spec
MD
  cat > "$TEST_DIR/docs/specs/SPEC-9002-perac-deferred.md" <<'MD'
---
id: SPEC-9002
type: spec
status: implementing
links:
  pr: []
---
# Non-deferred spec carrying a deferred AC row

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By  | Notes          |
|------------|-------------|--------------|----------|------------|----------------|
| Spec-AC-01 | first       | implementing | —        | —          | —              |
| Spec-AC-02 | second      | deferred     | —        | 2099-01-01 | needs upstream |
MD
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > index-defer.log 2>&1) \
    || log_fail "generate-docs-index (default) must succeed: $(cat "$TEST_DIR/index-defer.log")"
  local index="$TEST_DIR/docs/INDEX.md"
  assert_contains "$index" "## Deferred (whole-doc)"
  extract_section "$index" "## Deferred (whole-doc)" > "$TEST_DIR/whole.txt"
  grep -qF "SPEC-9001" "$TEST_DIR/whole.txt" \
    || log_fail "whole-doc deferred section must list SPEC-9001"
  # the per-AC deferred section is a different, still-present section
  assert_contains "$index" "## Deferred items (per-AC"
  rm "$TEST_DIR/docs/specs/SPEC-9001-whole-deferred.md" "$TEST_DIR/docs/specs/SPEC-9002-perac-deferred.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Whole-doc deferred section present and distinct from per-AC deferred items"
}

test_spec0006_zero_section_strict_fatal() {  # TEST-002 / Spec-AC-02
  log_info "Test: a non-legacy zero-section doc makes --strict exit non-zero, named (TEST-002)..."
  # Control: a doc declaring a valid DOC_STATUS_ENUM value ('legacy') that has NO
  # doc-level placement section AND is not the no-frontmatter Legacy section, so
  # it lands in zero placement sections. Data-driven over actual membership.
  cat > "$TEST_DIR/docs/specs/SPEC-9003-zero-section.md" <<'MD'
---
id: SPEC-9003
type: spec
status: legacy
links:
  pr: []
---
# Frontmatter status with no doc-level placement section
MD
  if (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs --strict > zero-strict.log 2>&1); then
    log_fail "generate-docs-index --strict must exit non-zero on a zero-section doc"
  fi
  assert_contains "$TEST_DIR/zero-strict.log" "SPEC-9003"
  grep -qiE "zero|coverage" "$TEST_DIR/zero-strict.log" \
    || log_fail "strict coverage failure must mention coverage / zero-section"
  rm "$TEST_DIR/docs/specs/SPEC-9003-zero-section.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Zero-section coverage invariant is fatal under --strict"
}

test_spec0006_zero_section_degrade_report() {  # TEST-003 / Spec-AC-03
  log_info "Test: zero-section doc degrades — exit 0, best-effort INDEX, gap surfaced (TEST-003)..."
  cat > "$TEST_DIR/docs/specs/SPEC-9003-zero-section.md" <<'MD'
---
id: SPEC-9003
type: spec
status: legacy
links:
  pr: []
---
# Frontmatter status with no doc-level placement section
MD
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > zero-soft.log 2>&1) \
    || log_fail "default (non-strict) run must exit 0 with a zero-section doc: $(cat "$TEST_DIR/zero-soft.log")"
  assert_file "$TEST_DIR/docs/INDEX.md"
  assert_contains "$TEST_DIR/docs/INDEX.md" "SPEC-9003"
  assert_contains "$TEST_DIR/docs/INDEX.md" "Coverage gaps"
  rm "$TEST_DIR/docs/specs/SPEC-9003-zero-section.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Degrade-and-report: best-effort INDEX written, gap surfaced, exit 0"
}

test_spec0006_no_double_listing_idempotent() {  # TEST-004 / Spec-AC-04
  log_info "Test: whole-doc vs per-AC deferred not double-listed; INDEX idempotent (TEST-004)..."
  cat > "$TEST_DIR/docs/specs/SPEC-9001-whole-deferred.md" <<'MD'
---
id: SPEC-9001
type: spec
status: deferred
links:
  pr: []
---
# Whole-doc deferred spec (no deferred AC rows)
MD
  cat > "$TEST_DIR/docs/specs/SPEC-9002-perac-deferred.md" <<'MD'
---
id: SPEC-9002
type: spec
status: implementing
links:
  pr: []
---
# Non-deferred spec carrying a deferred AC row

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By  | Notes          |
|------------|-------------|--------------|----------|------------|----------------|
| Spec-AC-01 | first       | implementing | —        | —          | —              |
| Spec-AC-02 | second      | deferred     | —        | 2099-01-01 | needs upstream |
MD
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > dbl-run1.log 2>&1) \
    || log_fail "index gen failed: $(cat "$TEST_DIR/dbl-run1.log")"
  local index="$TEST_DIR/docs/INDEX.md"
  extract_section "$index" "## Deferred (whole-doc)" > "$TEST_DIR/whole.txt"
  extract_section "$index" "## Deferred items (per-AC" > "$TEST_DIR/perac.txt"
  grep -qF "SPEC-9001" "$TEST_DIR/whole.txt" \
    || log_fail "SPEC-9001 must be in the whole-doc deferred section"
  if grep -qF "SPEC-9001" "$TEST_DIR/perac.txt"; then
    log_fail "SPEC-9001 (whole-doc deferred) must NOT appear in the per-AC deferred section"
  fi
  grep -qF "SPEC-9002" "$TEST_DIR/perac.txt" \
    || log_fail "SPEC-9002's deferred AC row must be in the per-AC deferred section"
  if grep -qF "SPEC-9002" "$TEST_DIR/whole.txt"; then
    log_fail "SPEC-9002 (non-deferred doc) must NOT appear in the whole-doc deferred section"
  fi
  grep -v '^Generated:' "$index" > "$TEST_DIR/dbl1.snap"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  grep -v '^Generated:' "$index" > "$TEST_DIR/dbl2.snap"
  diff -q "$TEST_DIR/dbl1.snap" "$TEST_DIR/dbl2.snap" >/dev/null \
    || log_fail "INDEX must be idempotent modulo the Generated line"
  rm "$TEST_DIR/docs/specs/SPEC-9001-whole-deferred.md" "$TEST_DIR/docs/specs/SPEC-9002-perac-deferred.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "No double-listing across whole-doc vs per-AC deferred; INDEX idempotent"
}

test_spec0006_close_policy_prose() {  # TEST-005 / Spec-AC-05
  log_info "Test: resolve-or-promote close-policy present in WORKFLOW.md + VALIDATION.prompt.md (TEST-005)..."
  local wf="$PROJECT_ROOT/.aai/workflow/WORKFLOW.md"
  local val="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  assert_file "$wf"
  assert_file "$val"
  for f in "$wf" "$val"; do
    grep -qF 'transition to `status: done`' "$f" \
      || log_fail "close-policy missing 'transition to status: done' rule in $f"
    grep -qF 'free-text WARNING' "$f" \
      || log_fail "close-policy missing 'free-text WARNING' wording in $f"
    grep -qF 'promote' "$f" \
      || log_fail "close-policy missing the promote-to-tracked rule in $f"
    grep -qF 'tracked item' "$f" \
      || log_fail "close-policy missing 'tracked item' wording in $f"
  done
  log_pass "Resolve-or-promote close-policy codified in workflow + validation prompt"
}

test_spec0006_open_decision_guard() {  # TEST-006 / Spec-AC-06
  log_info "Test: report-only open-decision-on-done guard flags WARNINGs, not notes; gate unchanged (TEST-006)..."
  run_audit --no-event --path docs/opendecision > "$TEST_DIR/opendec.log"
  assert_contains "$TEST_DIR/opendec.log" "Open decisions on done docs"
  extract_section_h3 "$TEST_DIR/opendec.log" "### Open decisions on done docs" > "$TEST_DIR/opendec-sec.txt"
  grep -qF "SPEC-9100" "$TEST_DIR/opendec-sec.txt" \
    || log_fail "done doc with a buried WARNING decision (SPEC-9100) must be flagged"
  if grep -qF "SPEC-9101" "$TEST_DIR/opendec-sec.txt"; then
    log_fail "done doc with only an informational note (SPEC-9101) must NOT be flagged"
  fi
  # report-only: --check --strict exit code is unchanged (0) AND the section is present.
  run_audit --check --strict --no-event --path docs/opendecision > "$TEST_DIR/opendec-gate.log" \
    || log_fail "open-decision guard must not change the --check --strict exit code"
  assert_contains "$TEST_DIR/opendec-gate.log" "Open decisions on done docs"
  grep -qF "SPEC-9100" "$TEST_DIR/opendec-gate.log" \
    || log_fail "the --check --strict run must still surface SPEC-9100"
  log_pass "Open-decision-on-done guard is report-only with a clean negative control"
}

test_spec0006_no_regression_real_repo() {  # TEST-007 / Spec-AC-07
  log_info "Test: real-repo docs-audit CLEAN and index idempotent — no regression (TEST-007)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/repo-audit.log" 2>&1) \
    || log_fail "real-repo docs-audit --check --strict must exit 0: $(tail -5 "$TEST_DIR/repo-audit.log")"
  assert_contains "$TEST_DIR/repo-audit.log" "Verdict: CLEAN"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/repo-idx1.log" 2>&1) \
    || log_fail "real-repo index gen (run 1) failed: $(cat "$TEST_DIR/repo-idx1.log")"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-idx1.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/repo-idx2.log" 2>&1) \
    || log_fail "real-repo index gen (run 2) failed: $(cat "$TEST_DIR/repo-idx2.log")"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-idx2.snap"
  diff -q "$TEST_DIR/repo-idx1.snap" "$TEST_DIR/repo-idx2.snap" >/dev/null \
    || log_fail "real-repo INDEX must be idempotent modulo the Generated line"
  log_pass "Real-repo audit CLEAN and INDEX idempotent (no regression)"
}

main() {
  echo "Testing $TEST_NAME skill (engine + fixtures)"
  check_deps
  setup_fixture
  test_report_only_without_config
  test_strict_path_intake_gate
  write_config
  test_orphan_split
  test_drift_verdicts
  test_events_emission
  test_quick_mode
  test_index_sections_and_idempotence
  test_compound_ids_and_frozen_markers
  test_reviewby_literals
  test_uncommitted_doc_not_punished
  test_type_validation
  test_orphan_suggested_id
  test_classification_listing
  test_reviewby_actor_method
  test_events_parent_subref_boundary
  test_plan_scan_mode
  test_suggested_multi_ids
  test_category_prefix_scope
  test_index_legacy_autoskip
  test_skill_prompt_modes
  setup_closeout_fixture
  test_closeout_candidate_flagged
  test_closeout_spec_not_all_done
  test_closeout_terminal_parent
  test_closeout_read_only
  test_closeout_no_false_positive
  test_closeout_report_only_gate
  test_closeout_reverse_only
  test_closeout_forward_nonspec_not_flagged
  setup_spec0006_opendecision_fixture
  test_spec0006_deferred_whole_doc_section
  test_spec0006_zero_section_strict_fatal
  test_spec0006_zero_section_degrade_report
  test_spec0006_no_double_listing_idempotent
  test_spec0006_close_policy_prose
  test_spec0006_open_decision_guard
  test_spec0006_no_regression_real_repo
  test_index_continue_on_error
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
