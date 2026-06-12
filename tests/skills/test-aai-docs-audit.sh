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
  test_index_continue_on_error
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

main "$@"
