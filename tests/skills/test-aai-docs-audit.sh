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
# Absolute self-path captured BEFORE any cd (review CHANGE-0009 W1: a bare
# relative BASH_SOURCE is unresolvable after setup_fixture's cd, which made
# the self-containment guard vacuous — grep exit 2 slipped through '&&').
SUITE_FILE="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

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
  # The aligned doc must stay out of the DRIFT report. (SPEC-0011 adds report-only
  # sections — e.g. Missing close telemetry — that legitimately list every done
  # doc including SPEC-204, so scope this assertion to the Drift report section.)
  extract_section_h3 "$log" "### Drift report" > "$TEST_DIR/drift-sec.txt"
  if grep -qF "SPEC-204" "$TEST_DIR/drift-sec.txt"; then
    log_fail "aligned SPEC-204 must not appear in the Drift report"
  fi
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
  # SPEC-0010 Group A (ISSUE-0003): the git-history-dependent audit sections are
  # RELOCATED out of the committed INDEX into the git-ignored companion
  # docs/INDEX.audit.md (so the committed INDEX is a pure function of on-disk docs).
  assert_not_contains "$index" "## Orphans (need triage)"
  assert_not_contains "$index" "## Drift report"
  local audit="$TEST_DIR/docs/INDEX.audit.md"
  assert_file "$audit"
  assert_contains "$audit" "## Orphans (need triage) (2)"
  assert_contains "$audit" "## Drift report (3)"
  assert_contains "$audit" "probable-false-done"

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
  log_info "Test: index gen auto-skips whole-doc violations in legacy docs (D13)..."
  # SPEC-0010 Group C note: unknown AC *status* is now a row-level (not whole-doc)
  # violation, so it no longer feeds the legacy-autoskip path. This test therefore
  # exercises legacy-autoskip via a whole-doc violation (an unknown FRONTMATTER
  # status), which remains whole-doc.
  cat > "$TEST_DIR/docs/specs/SPEC-100-legacy-bad.md" <<'MD'
---
id: SPEC-100
type: spec
status: wibble-legacy-status
links:
  pr: []
---
# Legacy spec with a pre-canon (unknown) frontmatter status value
MD
  (cd "$TEST_DIR" && git add docs/specs/SPEC-100-legacy-bad.md \
    && GIT_COMMITTER_DATE="2026-01-15T10:00:00Z" GIT_AUTHOR_DATE="2026-01-15T10:00:00Z" \
       git commit -qm "docs: legacy spec fixture")
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > legacy-skip.log 2>&1) \
    || log_fail "Legacy-doc violations must auto-skip, not hard-fail: $(cat "$TEST_DIR/legacy-skip.log")"
  # SPEC-0010 (ISSUE-0003) WARNING-1: the committed INDEX lists the skipped doc
  # PLAINLY (git-invariant) — the git-history-dependent "[legacy — auto-skipped]"
  # annotation now lives ONLY in the git-ignored companion docs/INDEX.audit.md.
  assert_contains "$TEST_DIR/docs/INDEX.md" "SPEC-100"
  assert_not_contains "$TEST_DIR/docs/INDEX.md" "legacy — auto-skipped"
  assert_contains "$TEST_DIR/docs/INDEX.audit.md" "legacy — auto-skipped"
  assert_contains "$TEST_DIR/docs/INDEX.audit.md" "SPEC-100"
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

# --- SPEC-0010 Group A (ISSUE-0003): committed-index idempotence + relocation ---

# An isolated git repo with the vendored scripts, the pre-commit-hook installer,
# and a .gitignore for the audit companion. Echoes the repo path on stdout.
setup_spec0010_hook_repo() {
  local d="$TEST_DIR/iso-hook-$1"
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/specs" "$d/docs/issues" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  printf 'docs/INDEX.audit.md\n' > "$d/.gitignore"
  (cd "$d" && git init -q && git config user.email test@example.com && git config user.name "AAI Test")
  (cd "$d" && git add .aai .gitignore && git commit -qm "chore: vendor scripts")
  (cd "$d" && bash .aai/scripts/install-pre-commit-hook.sh >/dev/null)
  printf '%s' "$d"
}

test_spec0010_committed_index_idempotent() {  # TEST-001 / Spec-AC-01
  log_info "Test: committed docs/INDEX.md == post-commit fresh regen (close-in-same-commit) (TEST-001)..."
  local d; d="$(setup_spec0010_hook_repo idem)"
  # A NON-spec done doc with no AC gate, first-mentioned by ID in the SAME commit.
  # At hook (pre-commit) time no commit references it -> the drift heuristic bakes
  # a probable-false-done row; the instant the commit exists a fresh regen clears
  # it. Pre-fix that makes the committed INDEX non-idempotent.
  cat > "$d/docs/issues/CHANGE-5001-close-in-commit.md" <<'MD'
---
id: CHANGE-5001
type: change
status: done
links:
  pr: []
---
# Closed in the same commit that first mentions it (no AC gate)
MD
  (cd "$d" && git add docs/issues/CHANGE-5001-close-in-commit.md \
    && git commit -qm "feat: ship CHANGE-5001" >/dev/null) \
    || log_fail "hook-driven commit failed"
  # The committed index exactly as the AAI:INDEX-AUTOGEN hook staged it.
  (cd "$d" && git show HEAD:docs/INDEX.md) > "$TEST_DIR/hook-committed.raw" \
    || log_fail "docs/INDEX.md was not committed by the hook"
  grep -v '^Generated:' "$TEST_DIR/hook-committed.raw" > "$TEST_DIR/hook-committed.snap"
  # A fresh regen AFTER the commit object exists.
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1) \
    || log_fail "post-commit regen failed"
  grep -v '^Generated:' "$d/docs/INDEX.md" > "$TEST_DIR/post-commit.snap"
  diff -q "$TEST_DIR/hook-committed.snap" "$TEST_DIR/post-commit.snap" >/dev/null \
    || log_fail "committed INDEX must byte-equal a post-commit fresh regen (modulo Generated) — no follow-up commit needed"
  rm -rf "$d"
  log_pass "Committed docs/INDEX.md is byte-idempotent to a post-commit fresh regen"
}

test_spec0010_index_git_state_invariant() {  # TEST-002 / Spec-AC-02
  log_info "Test: mutating git history (docs unchanged) does not change INDEX; no Drift/Orphans heading (TEST-002)..."
  local d; d="$(setup_iso_repo gitinvariant)"
  mkdir -p "$d/docs/issues"
  cat > "$d/docs/issues/CHANGE-5002-false-done.md" <<'MD'
---
id: CHANGE-5002
type: change
status: done
links:
  pr: []
---
# Done doc with no AC gate and (initially) no commit referencing its ID
MD
  (cd "$d" && git add -A && git commit -qm "docs: add fixture without mentioning the id" >/dev/null)
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1) \
    || log_fail "index gen (run 1) failed"
  local index="$d/docs/INDEX.md"
  grep -v '^Generated:' "$index" > "$TEST_DIR/gi-run1.snap"
  # Mutate git history ONLY (docs on disk unchanged): a commit that now references
  # the doc ID. Pre-fix this clears the baked drift row -> INDEX changes.
  (cd "$d" && git commit --allow-empty -qm "chore: reference CHANGE-5002 now done" >/dev/null)
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1) \
    || log_fail "index gen (run 2) failed"
  grep -v '^Generated:' "$index" > "$TEST_DIR/gi-run2.snap"
  diff -q "$TEST_DIR/gi-run1.snap" "$TEST_DIR/gi-run2.snap" >/dev/null \
    || log_fail "INDEX must be invariant to git-history mutation when docs on disk are unchanged"
  assert_not_contains "$index" "## Drift report"
  assert_not_contains "$index" "## Orphans"
  rm -rf "$d"
  log_pass "Committed INDEX is git-state-invariant; no Drift/Orphans heading embedded"
}

test_spec0010_audit_companion_gitignored() {  # TEST-003 / Spec-AC-03
  log_info "Test: drift/orphan visibility preserved via docs-audit + git-ignored companion not staged by hook (TEST-003)..."
  local d; d="$(setup_spec0010_hook_repo companion)"
  cat > "$d/docs/issues/CHANGE-5003-false-done.md" <<'MD'
---
id: CHANGE-5003
type: change
status: done
links:
  pr: []
---
# Probable-false-done: done, no AC gate, no commit/ac_evidence referencing it
MD
  # Commit WITHOUT mentioning the id, so the drift verdict persists post-commit.
  (cd "$d" && git add docs/issues/CHANGE-5003-false-done.md \
    && git commit -qm "docs: add fixture" >/dev/null) \
    || log_fail "hook commit failed"
  # (a) docs-audit still reports the drift verdict + Orphans section (unchanged).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_contains "$d/audit.log" "Drift report"
  grep -F "CHANGE-5003" "$d/audit.log" | grep -qF "probable-false-done" \
    || log_fail "docs-audit must still report CHANGE-5003 as probable-false-done"
  # (b) the generator wrote the git-ignored companion carrying the relocated sections.
  assert_file "$d/docs/INDEX.audit.md"
  assert_contains "$d/docs/INDEX.audit.md" "## Drift report"
  (cd "$d" && git check-ignore -q docs/INDEX.audit.md) \
    || log_fail "docs/INDEX.audit.md must be git-ignored (git check-ignore should match)"
  # (c) the pre-commit hook must NOT have staged/committed the companion.
  if (cd "$d" && git show HEAD:docs/INDEX.audit.md >/dev/null 2>&1); then
    log_fail "docs/INDEX.audit.md must NOT be committed by the AAI:INDEX-AUTOGEN hook"
  fi
  rm -rf "$d"
  log_pass "Drift/orphans preserved via docs-audit + git-ignored companion; companion never staged"
}

# --- SPEC-0010 Group C (ISSUE-0005): row-level AC status + qualifier normalization ---

test_spec0010_ac_row_level_not_whole_doc() {  # TEST-007 / Spec-AC-07
  log_info "Test: one unknown AC status flags the ROW only; doc stays in its INDEX section (TEST-007)..."
  local d; d="$(setup_iso_repo ac-rowlevel)"
  cat > "$d/docs/specs/SPEC-6007-row-level.md" <<'MD'
---
id: SPEC-6007
type: spec
status: done
links:
  pr: []
---
# Done spec with one genuinely-unknown AC status cell

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | done         | a1b2c3d  | TDD       | —     |
| Spec-AC-02 | second      | bogus-status | —        | —         | —     |
MD
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen.log 2>&1) \
    || log_fail "default generator run must exit 0 (degrade-and-report): $(cat "$d/gen.log")"
  local index="$d/docs/INDEX.md"
  # Row-level, not whole-doc: the doc stays in its correct (Done) placement section.
  extract_section "$index" "## Done" | grep -qF "SPEC-6007" \
    || log_fail "SPEC-6007 must remain in the Done section (row-level skip, not whole-doc)"
  # The offending row is surfaced in a row-level AC-status violations report.
  assert_file "$d/docs/INDEX.violations.md"
  assert_contains "$d/docs/INDEX.violations.md" "AC status violations"
  grep -F "SPEC-6007" "$d/docs/INDEX.violations.md" | grep -qF "Spec-AC-02" \
    || log_fail "the bogus row (SPEC-6007 / Spec-AC-02) must be listed as a row-level AC-status violation"
  # NOT whole-doc-skipped from the index.
  extract_section "$index" "## Skipped (schema violations)" > "$d/skipped.txt" 2>/dev/null || true
  if grep -qF "SPEC-6007" "$d/skipped.txt" 2>/dev/null; then
    log_fail "SPEC-6007 must NOT be whole-doc-skipped from the index"
  fi
  rm -rf "$d"
  log_pass "Unknown AC status flags the row only; the doc stays indexed in its section"
}

test_spec0010_ac_qualifier_normalized() {  # TEST-008 / Spec-AC-08
  log_info "Test: <canonical> (<qualifier>) normalized to base status, not a violation, --strict exit 0 (TEST-008)..."
  local d; d="$(setup_iso_repo ac-qualifier)"
  cat > "$d/docs/specs/SPEC-6008-qualifier.md" <<'MD'
---
id: SPEC-6008
type: spec
status: done
links:
  pr: []
---
# Done spec whose AC row carries a qualified status

## Acceptance Criteria Status

| Spec-AC    | Description | Status              | Evidence | Review-By | Notes                |
|------------|-------------|---------------------|----------|-----------|----------------------|
| Spec-AC-01 | first       | done (pre-existing) | a1b2c3d  | TDD       | inherited from prior |
MD
  # --strict must exit 0 (the qualified status is NOT a violation).
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs --strict > gen-strict.log 2>&1) \
    || log_fail "generate-docs-index --strict must exit 0 on a qualified AC status: $(cat "$d/gen-strict.log")"
  local index="$d/docs/INDEX.md"
  extract_section "$index" "## Done" | grep -qF "SPEC-6008" \
    || log_fail "SPEC-6008 must be indexed normally in the Done section"
  # No AC-status violation recorded for the qualified row.
  if [[ -f "$d/docs/INDEX.violations.md" ]] && grep -qF "SPEC-6008" "$d/docs/INDEX.violations.md"; then
    log_fail "a qualified 'done (pre-existing)' row must NOT be reported as a violation"
  fi
  # normalizeAcStatus preserves the qualifier and stays narrow (unit-level).
  cat > "$d/norm.mjs" <<'EOF'
import { normalizeAcStatus } from './.aai/scripts/lib/docs-model.mjs';
import assert from 'node:assert';
const r = normalizeAcStatus('done (pre-existing)');
assert.strictEqual(r.status, 'done', 'base status must be done');
assert.strictEqual(r.canonical, true, 'qualified canonical token must be canonical');
assert.strictEqual(r.qualifier, 'pre-existing', 'qualifier must be preserved, not dropped');
assert.strictEqual(normalizeAcStatus('done').canonical, true, 'bare canonical still canonical');
assert.strictEqual(normalizeAcStatus('finished').canonical, false, 'finished is genuine garbage');
assert.strictEqual(normalizeAcStatus('donee').canonical, false, 'donee is not normalized');
assert.strictEqual(normalizeAcStatus('done ()').canonical, false, 'empty parenthetical stays non-canonical');
assert.strictEqual(normalizeAcStatus('done (a) (b)').canonical, false, 'multiple parentheticals stay non-canonical');
console.log('ok');
EOF
  (cd "$d" && node norm.mjs) > "$d/norm.log" 2>&1 \
    || log_fail "normalizeAcStatus qualifier handling incorrect: $(cat "$d/norm.log")"
  rm -rf "$d"
  log_pass "Qualified status normalized to base 'done'; qualifier preserved; narrow rule; --strict exit 0"
}

test_spec0010_ac_genuine_invalid_flagged_both() {  # TEST-009 / Spec-AC-09
  log_info "Test: genuine-invalid AC status flagged by BOTH engines; qualified accepted by BOTH (TEST-009)..."
  local d; d="$(setup_iso_repo ac-both)"
  cat > "$d/docs/specs/SPEC-6009-both.md" <<'MD'
---
id: SPEC-6009
type: spec
status: done
links:
  pr: []
---
# Done spec with one genuine-invalid AC status and one qualified status

## Acceptance Criteria Status

| Spec-AC    | Description | Status              | Evidence | Review-By | Notes |
|------------|-------------|---------------------|----------|-----------|-------|
| Spec-AC-01 | first       | done (pre-existing) | a1b2c3d  | TDD       | —     |
| Spec-AC-02 | second      | finished            | —        | —         | —     |
MD
  (cd "$d" && git add -A && git commit -qm "docs: SPEC-6009 fixture" >/dev/null 2>&1) || true
  # Generator --strict: genuine garbage (finished) is still fatal.
  if (cd "$d" && node .aai/scripts/generate-docs-index.mjs --strict > gen-strict.log 2>&1); then
    log_fail "generate-docs-index --strict must exit 1 when a genuinely-invalid AC status is present"
  fi
  grep -qF "finished" "$d/gen-strict.log" \
    || log_fail "generator --strict failure must name the invalid status (finished)"
  # docs-audit: reports `finished`, accepts the qualified `done (pre-existing)`.
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-6009-both.md > audit.log 2>&1) || true
  grep -F "SPEC-6009" "$d/audit.log" | grep -qF 'finished' \
    || log_fail "docs-audit must flag the genuine-invalid status (finished)"
  # Positive control (self-eval trap): the qualified row is NOT reported as a violation.
  if grep -qF 'unknown AC status "done (pre-existing)"' "$d/audit.log"; then
    log_fail "docs-audit must NOT flag the qualified 'done (pre-existing)' row (proves the check is not accept-all inverted)"
  fi
  rm -rf "$d"
  log_pass "Genuine-invalid AC status flagged by both engines; qualified status accepted by both"
}

test_index_continue_on_error() {
  log_info "Test: index generator degrade-and-report default + --strict gate (D9)..."
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
  # Default (and the retained --continue-on-error no-op alias) is degrade-and-report:
  # a schema violation never blocks the index — it exits 0 and writes a best-effort
  # index with a "Skipped (schema violations)" section listing the bad doc.
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs \
    > index-partial.log 2>&1) \
    || log_fail "Default run must degrade-and-report (exit 0): $(cat "$TEST_DIR/index-partial.log")"
  assert_contains "$TEST_DIR/docs/INDEX.md" "Skipped (schema violations)"
  assert_contains "$TEST_DIR/docs/INDEX.md" "SPEC-998"
  # --continue-on-error is a retained no-op alias — same degrade-and-report behavior.
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs --continue-on-error \
    > index-alias.log 2>&1) \
    || log_fail "--continue-on-error (no-op alias) must exit 0: $(cat "$TEST_DIR/index-alias.log")"
  # --strict is the CI/pre-commit gate: it MUST hard-fail (non-zero) on the violation.
  if (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs --strict > index-strict.log 2>&1); then
    log_fail "--strict must hard-fail (non-zero) on a schema violation"
  fi
  rm "$TEST_DIR/docs/specs/SPEC-998-bad-status.md"
  (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1)
  log_pass "Default degrade-and-report + --strict gate both correct"
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

  # Flagged: a done spec whose only marker is the natural PLURAL phrasing
  # "open decisions" with no other token on the line. Guards against a word-
  # boundary false negative (open decision\b would miss the trailing "s").
  cat > docs/opendecision/SPEC-9102-plural-open-decisions.md <<'MD'
---
id: SPEC-9102
type: spec
status: done
links:
  pr: []
---
# Closed spec with a plural open-decisions WARNING

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | only        | done   | c3d4e5f  | TDD       | —     |

WARNING: open decisions RR-1/RR-2 remain.
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
  grep -qF "SPEC-9102" "$TEST_DIR/opendec-sec.txt" \
    || log_fail "done doc with a plural 'open decisions' WARNING (SPEC-9102) must be flagged"
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
  # SPEC-0057: the whole-digest Verdict line now correctly reads NEEDS-TRIAGE
  # on the real repo (3 pre-existing, tracked duplicate-doc-id collisions,
  # verdict-only/not hardFail — unrelated to this test's own regression
  # surface), so assert the hard-gate/orphan signals this stanza actually
  # guards, not the coarse verdict text (mirrors test_change0012_regression's
  # same precedent for pre-existing report-only drift).
  assert_contains "$TEST_DIR/repo-audit.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/repo-audit.log" "CHECK FAILED"
  # Regenerating writes the real docs/INDEX.md (a fresh Generated: timestamp), so
  # back it up first and restore it after the idempotence check — the suite must
  # leave the worktree clean for CI/pre-commit clean-tree gates.
  local idx_backup="$TEST_DIR/INDEX.md.orig"
  cp "$PROJECT_ROOT/docs/INDEX.md" "$idx_backup"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/repo-idx1.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 1) failed: $(cat "$TEST_DIR/repo-idx1.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-idx1.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/repo-idx2.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 2) failed: $(cat "$TEST_DIR/repo-idx2.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-idx2.snap"
  # Restore the real index before asserting (so a diff failure can't leave it dirty).
  cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"
  diff -q "$TEST_DIR/repo-idx1.snap" "$TEST_DIR/repo-idx2.snap" >/dev/null \
    || log_fail "real-repo INDEX must be idempotent modulo the Generated line"
  log_pass "Real-repo audit CLEAN and INDEX idempotent (no regression)"
}

# --- SPEC-0007 fixtures (ISSUE-0001): CRLF/lone-CR-tolerant parsers + POSIX paths ---

# Build an isolated mini-repo under $TEST_DIR with the vendored scripts, so a
# controlled corpus (CRLF / legacy-ratio) is scanned in isolation from the
# accumulated fixture docs above. Echoes the repo path on stdout.
setup_iso_repo() {
  local name="$1"
  local d="$TEST_DIR/iso-$name"
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/specs" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  (cd "$d" && git init -q && git config user.email test@example.com && git config user.name "AAI Test")
  printf '%s' "$d"
}

# Convert stdin (LF) to a CRLF-terminated file at $1.
write_crlf() { awk '{ printf "%s\r\n", $0 }' > "$1"; }

test_issue0001_frontmatter_crlf_tolerance() {  # TEST-001 / Spec-AC-01
  log_info "Test: parseFrontmatter identical for LF/CRLF/lone-CR, no trailing CR (TEST-001)..."
  cat > "$TEST_DIR/t1.mjs" <<'EOF'
import { parseFrontmatter } from './.aai/scripts/lib/docs-model.mjs';
import assert from 'node:assert';
const lf = `---
id: SPEC-9999
type: spec
status: done
links:
  pr: []
---
# Doc
`;
const crlf = lf.replace(/\n/g, '\r\n');
const cr = lf.replace(/\n/g, '\r');
const a = parseFrontmatter(lf), b = parseFrontmatter(crlf), c = parseFrontmatter(cr);
assert(a, 'LF must parse to an object');
assert.deepStrictEqual(b, a, 'CRLF must deep-equal LF (RED pre-fix: parseFrontmatter(crlf) === null)');
assert.deepStrictEqual(c, a, 'lone-CR must deep-equal LF');
const noCR = (o) => o == null ? true
  : typeof o === 'string' ? !o.includes('\r')
  : typeof o === 'object' ? Object.values(o).every(noCR) : true;
assert(noCR(a) && noCR(b) && noCR(c), 'no parsed value may carry a CR');
console.log('ok');
EOF
  (cd "$TEST_DIR" && node t1.mjs) > "$TEST_DIR/t1.log" 2>&1 \
    || log_fail "parseFrontmatter not CRLF/lone-CR tolerant: $(cat "$TEST_DIR/t1.log")"
  rm -f "$TEST_DIR/t1.mjs"
  log_pass "parseFrontmatter normalizes LF/CRLF/lone-CR to an identical object"
}

test_issue0001_actable_crlf_tolerance() {  # TEST-002 / Spec-AC-02
  log_info "Test: parseAcTable rows cell-equal across LF/CRLF/CR; Review-By/refs carry no CR (TEST-002)..."
  cat > "$TEST_DIR/t2.mjs" <<'EOF'
import { parseAcTable, parseReviewBy, extractReferences } from './.aai/scripts/lib/docs-model.mjs';
import assert from 'node:assert';
const lf = `---
id: SPEC-9999
type: spec
status: done
links:
  pr: []
---
# Doc

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By  | Notes          |
|------------|-------------|--------|----------|------------|----------------|
| Spec-AC-01 | first       | done   | a1b2c3d  | 2026-05-01 | see → REF-0001 |
`;
const crlf = lf.replace(/\n/g, '\r\n');
const cr = lf.replace(/\n/g, '\r');
const rLF = parseAcTable(lf).rows, rCRLF = parseAcTable(crlf).rows, rCR = parseAcTable(cr).rows;
assert(rLF.length === 1, 'LF must parse one AC row');
assert.strictEqual(JSON.stringify(rCRLF), JSON.stringify(rLF), 'CRLF rows must equal LF rows');
assert.strictEqual(JSON.stringify(rCR), JSON.stringify(rLF), 'lone-CR rows must equal LF rows (RED pre-fix: rows empty)');
for (const rows of [rLF, rCRLF, rCR]) {
  const row = rows[0];
  for (const v of Object.values(row)) assert(!String(v).includes('\r'), 'no cell may carry a CR');
  assert.strictEqual(parseReviewBy(row['Review-By']).kind, 'date', 'Review-By must parse as a date, not invalid');
  assert.deepStrictEqual(extractReferences(row['Notes']), ['REF-0001'], 'reference must be REF-0001 (no CR)');
}
console.log('ok');
EOF
  (cd "$TEST_DIR" && node t2.mjs) > "$TEST_DIR/t2.log" 2>&1 \
    || log_fail "parseAcTable/parseReviewBy/extractReferences not line-ending tolerant: $(cat "$TEST_DIR/t2.log")"
  rm -f "$TEST_DIR/t2.mjs"
  log_pass "AC-table rows equal across line endings; Review-By/refs clean"
}

test_issue0001_posix_paths_noop() {  # TEST-003 / Spec-AC-03
  log_info "Test: real-repo INDEX paths are POSIX-only and the path change is a no-op on POSIX (TEST-003)..."
  local idx="$PROJECT_ROOT/docs/INDEX.md"
  local backup="$TEST_DIR/INDEX.t003.orig"
  cp "$idx" "$backup"
  grep -v '^Generated:' "$backup" > "$TEST_DIR/t003.before.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/t003.gen.log" 2>&1) \
    || { cp "$backup" "$idx"; log_fail "real-repo index gen failed: $(cat "$TEST_DIR/t003.gen.log")"; }
  grep -v '^Generated:' "$idx" > "$TEST_DIR/t003.after.snap"
  # POSIX-only: the committed artifact carries no backslash separators.
  if grep -q '\\' "$idx"; then cp "$backup" "$idx"; log_fail "INDEX must contain forward-slash paths only (found a backslash)"; fi
  # Restore the real index before asserting (a diff failure must not leave it dirty).
  cp "$backup" "$idx"
  diff -q "$TEST_DIR/t003.before.snap" "$TEST_DIR/t003.after.snap" >/dev/null \
    || log_fail "POSIX-path change must be a no-op on POSIX (real INDEX byte-identical modulo Generated)"
  log_pass "Real-repo INDEX is POSIX-only; path normalization is a no-op on POSIX"
}

test_issue0001_crlf_corpus_buckets() {  # TEST-004 / Spec-AC-04
  log_info "Test: CRLF fixture corpus -> real-status buckets, <=1 Legacy, POSIX paths (TEST-004)..."
  local d; d="$(setup_iso_repo crlf)"
  write_crlf "$d/docs/specs/SPEC-7001-done.md" <<'MD'
---
id: SPEC-7001
type: spec
status: done
links:
  pr: []
---
# Done spec
MD
  write_crlf "$d/docs/specs/SPEC-7002-draft.md" <<'MD'
---
id: SPEC-7002
type: spec
status: draft
links:
  pr: []
---
# Draft spec
MD
  write_crlf "$d/docs/specs/SPEC-7003-impl.md" <<'MD'
---
id: SPEC-7003
type: spec
status: implementing
links:
  pr: []
---
# Implementing spec
MD
  (cd "$d" && git add -A && git commit -qm "crlf corpus")
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen.log 2>&1) \
    || log_fail "generator failed on CRLF corpus: $(cat "$d/gen.log")"
  local index="$d/docs/INDEX.md"
  extract_section "$index" "## Done" | grep -qF "SPEC-7001" \
    || log_fail "SPEC-7001 must land in Done (CRLF parsed), not Legacy"
  extract_section "$index" "## Drafts" | grep -qF "SPEC-7002" \
    || log_fail "SPEC-7002 must land in Drafts"
  extract_section "$index" "## Active (implementing)" | grep -qF "SPEC-7003" \
    || log_fail "SPEC-7003 must land in Active (implementing)"
  assert_contains "$index" "## Legacy (no frontmatter) (0)"
  if grep -q '\\' "$index"; then log_fail "CRLF-corpus INDEX must have forward-slash paths only"; fi
  rm -rf "$d"
  log_pass "CRLF corpus buckets by real status with POSIX paths (NOT all-Legacy)"
}

test_issue0001_gitattributes() {  # TEST-005 / Spec-AC-05
  log_info "Test: .gitattributes carries the docs+mjs eol=lf rules; existing rules intact (TEST-005)..."
  local ga="$PROJECT_ROOT/.gitattributes"
  assert_file "$ga"
  assert_contains "$ga" "docs/**/*.md text eol=lf"
  assert_contains "$ga" "*.mjs text eol=lf"
  # existing executable-script rules must remain untouched
  assert_contains "$ga" "*.sh text eol=lf"
  assert_contains "$ga" "*.bat text eol=crlf"
  log_pass ".gitattributes adds docs/mjs LF rules without disturbing existing rules"
}

test_issue0001_legacy_ratio_guard() {  # TEST-006 / Spec-AC-06
  log_info "Test: report-only legacy-ratio guard (>50% AND >1) warns on stderr, exit unchanged; negative control silent (TEST-006)..."
  local d; d="$(setup_iso_repo legacy)"
  # High-legacy: 3 no-frontmatter docs of 4 = 75% (>50%), legacyCount 3 (>1).
  printf '# Legacy one\nno frontmatter\n' > "$d/docs/specs/LEG-1.md"
  printf '# Legacy two\nno frontmatter\n' > "$d/docs/specs/LEG-2.md"
  printf '# Legacy three\nno frontmatter\n' > "$d/docs/specs/LEG-3.md"
  cat > "$d/docs/specs/SPEC-8001-ok.md" <<'MD'
---
id: SPEC-8001
type: spec
status: draft
links:
  pr: []
---
# Valid draft
MD
  (cd "$d" && git add -A && git commit -qm "high-legacy corpus")
  local ec=0
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen.out 2> gen.err) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "legacy-ratio guard must NOT change the exit code (got $ec)"
  grep -qiF "legacy-ratio guard" "$d/gen.err" \
    || log_fail "high-legacy corpus must emit the legacy-ratio warning on stderr"
  grep -qF "3 of 4 scanned docs are Legacy" "$d/gen.err" \
    || log_fail "warning must name the legacy count (3) and the scanned-doc total (4)"
  # Negative control: drop to 1 legacy of 2 (ratio 50%, count 1) — must stay silent.
  rm "$d/docs/specs/LEG-2.md" "$d/docs/specs/LEG-3.md"
  local ec2=0
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen2.out 2> gen2.err) || ec2=$?
  [[ "$ec2" == 0 ]] || log_fail "negative-control run must still exit 0 (got $ec2)"
  if grep -qiF "legacy-ratio guard" "$d/gen2.err"; then
    log_fail "a normal corpus (<=1 legacy / <=50%) must NOT emit the legacy-ratio warning"
  fi
  rm -rf "$d"
  log_pass "Legacy-ratio guard is report-only: warns on >50%&>1, silent on normal corpus, exit unchanged"
}

test_issue0001_no_regression_real_repo() {  # TEST-007 / Spec-AC-07
  log_info "Test: real-repo docs-audit CLEAN and INDEX idempotent — no regression (TEST-007)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/t007-audit.log" 2>&1) \
    || log_fail "real-repo docs-audit --check --strict must exit 0: $(tail -5 "$TEST_DIR/t007-audit.log")"
  # SPEC-0057: see test_spec0006_no_regression_real_repo's comment — the
  # real-repo Verdict line now correctly reads NEEDS-TRIAGE (3 pre-existing,
  # tracked, verdict-only duplicate-doc-id collisions); assert the hard-gate
  # signal this stanza actually guards instead.
  assert_contains "$TEST_DIR/t007-audit.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/t007-audit.log" "CHECK FAILED"
  local idx_backup="$TEST_DIR/INDEX.t007.orig"
  cp "$PROJECT_ROOT/docs/INDEX.md" "$idx_backup"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/t007-idx1.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 1) failed: $(cat "$TEST_DIR/t007-idx1.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/t007-idx1.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/t007-idx2.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 2) failed: $(cat "$TEST_DIR/t007-idx2.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/t007-idx2.snap"
  cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"
  diff -q "$TEST_DIR/t007-idx1.snap" "$TEST_DIR/t007-idx2.snap" >/dev/null \
    || log_fail "real-repo INDEX must be idempotent modulo the Generated line"
  log_pass "Real-repo audit CLEAN and INDEX idempotent (no regression)"
}

test_issue0001_posix_helper() {  # toPosix unit test / WARNING-1 / SPEC-0007
  log_info "Test: toPosix converts backslash separators to forward slashes, idempotent on POSIX input (WARNING-1)..."
  cat > "$TEST_DIR/t-posix.mjs" <<'EOF'
import { toPosix } from './.aai/scripts/lib/docs-model.mjs';
import assert from 'node:assert';
// RED before the helper exists: import resolves to undefined, assert.strictEqual throws
assert.strictEqual(toPosix('docs\\issues\\x.md'), 'docs/issues/x.md',
  'backslash input must be converted to forward slashes');
assert.strictEqual(toPosix('docs/issues/x.md'), 'docs/issues/x.md',
  'POSIX input must be unchanged (idempotent)');
console.log('ok');
EOF
  (cd "$TEST_DIR" && node t-posix.mjs) > "$TEST_DIR/t-posix.log" 2>&1 \
    || log_fail "toPosix helper missing or incorrect: $(cat "$TEST_DIR/t-posix.log")"
  rm -f "$TEST_DIR/t-posix.mjs"
  log_pass "toPosix normalizes backslash inputs and is idempotent on forward-slash input"
}

# --- SPEC-0011 fixtures (CHANGE-0005): docs-audit closeout guardrails G1-G5 ------

# Isolated hook repo: vendored scripts + installed pre-commit hook + gitignore for
# the audit companion. Echoes the repo path on stdout.
setup_spec0011_hook_repo() {
  local d="$TEST_DIR/iso-s11hook-$1"
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/specs" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  printf 'docs/INDEX.audit.md\n' > "$d/.gitignore"
  (cd "$d" && git init -q && git config user.email test@example.com && git config user.name "AAI Test")
  (cd "$d" && git add .aai .gitignore && git commit -qm "chore: vendor scripts")
  (cd "$d" && bash .aai/scripts/install-pre-commit-hook.sh >/dev/null)
  printf '%s' "$d"
}

test_spec0011_gate_missing_table() {  # TEST-001 / Spec-AC-01
  log_info "Test: --gate exit 1 + 'missing AC Status table' for a done spec with no AC table (TEST-001)..."
  local d; d="$(setup_iso_repo s11-gate-missing)"
  cat > "$d/docs/specs/SPEC-1101-no-table.md" <<'MD'
---
id: SPEC-1101
type: spec
status: done
links:
  pr: []
---
# Done spec with no AC Status table
MD
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1101 > gate.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--gate must exit 1 for a done spec missing its AC table (got $ec): $(cat "$d/gate.log")"
  assert_contains "$d/gate.log" "missing AC Status table"
  rm -rf "$d"
  log_pass "--gate exits 1 naming the missing AC Status table"
}

test_spec0011_gate_fail_conditions() {  # TEST-002 / Spec-AC-01
  log_info "Test: --gate exit 1 for non-terminal row / done-empty-evidence / invalid Review-By, naming the AC (TEST-002)..."
  local d; d="$(setup_iso_repo s11-gate-fail)"
  # (a) non-terminal AC row
  cat > "$d/docs/specs/SPEC-1111-nonterminal.md" <<'MD'
---
id: SPEC-1111
type: spec
status: done
links:
  pr: []
---
# Done spec with a non-terminal AC row

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | done         | a1b2c3d  | TDD       | —     |
| Spec-AC-02 | second      | implementing | —        | —         | —     |
MD
  # (b) done row with empty evidence
  cat > "$d/docs/specs/SPEC-1112-emptyev.md" <<'MD'
---
id: SPEC-1112
type: spec
status: done
links:
  pr: []
---
# Done spec with a done row lacking evidence

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | —        | TDD       | —     |
MD
  # (c) schema-invalid Review-By token
  cat > "$d/docs/specs/SPEC-1113-badreview.md" <<'MD'
---
id: SPEC-1113
type: spec
status: done
links:
  pr: []
---
# Done spec with a schema-invalid Review-By

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | driver    | —     |
MD
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1111 > g1.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "non-terminal row must fail the gate (got $ec)"
  grep -qF "Spec-AC-02" "$d/g1.log" || log_fail "gate reason must name the non-terminal Spec-AC-02"
  grep -qiF "non-terminal" "$d/g1.log" || log_fail "gate reason must say non-terminal"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1112 > g2.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "done row with empty evidence must fail the gate (got $ec)"
  grep -qF "Spec-AC-01" "$d/g2.log" || log_fail "gate reason must name the empty-evidence Spec-AC-01"
  grep -qiF "evidence" "$d/g2.log" || log_fail "gate reason must mention evidence"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1113 > g3.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "invalid Review-By must fail the gate (got $ec)"
  grep -qF "Spec-AC-01" "$d/g3.log" || log_fail "gate reason must name the invalid-Review-By Spec-AC-01"
  grep -qiF "review-by" "$d/g3.log" || log_fail "gate reason must mention Review-By"
  rm -rf "$d"
  log_pass "--gate exit 1 for each failing condition, naming the offending Spec-AC"
}

test_spec0011_gate_pass_and_unknown() {  # TEST-003 / Spec-AC-02
  log_info "Test: --gate exit 0 for a reconciled done spec; exit 2 for an unknown id (TEST-003)..."
  local d; d="$(setup_iso_repo s11-gate-pass)"
  cat > "$d/docs/specs/SPEC-1120-reconciled.md" <<'MD'
---
id: SPEC-1120
type: spec
status: done
links:
  pr: []
---
# Fully reconciled done spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By  | Notes |
|------------|-------------|--------|----------|------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD        | —     |
| Spec-AC-02 | second      | done   | b2c3d4e  | code-review:2026-05-01 | — |
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1120 > gpass.log 2>&1) \
    || log_fail "--gate must exit 0 for a fully-reconciled done spec: $(cat "$d/gpass.log")"
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-9999 > gunknown.log 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--gate must exit 2 for an unresolved id (got $ec)"
  # RED-proof mutation control: dropping one Evidence cell flips the exit to 1.
  sed -i.bak 's/| b2c3d4e  |/| —        |/' "$d/docs/specs/SPEC-1120-reconciled.md"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1120 > gmut.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "dropping an Evidence cell must flip the gate to exit 1 (got $ec)"
  rm -rf "$d"
  log_pass "--gate exit 0 reconciled / exit 2 unknown / exit 1 after Evidence mutation"
}

test_spec0011_nearmiss_evidence_column() {  # TEST-004 / Spec-AC-03
  log_info "Test: 'Evidence (TEST)' near-miss column emits a distinct WARNING in docs-audit (TEST-004)..."
  local d; d="$(setup_iso_repo s11-nearmiss-ev)"
  cat > "$d/docs/specs/SPEC-1130-evcol.md" <<'MD'
---
id: SPEC-1130
type: spec
status: done
links:
  pr: []
---
# Done spec whose AC table cites evidence under an 'Evidence (TEST)' column

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence (TEST) | Review-By | Notes |
|------------|-------------|--------|-----------------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d         | TDD       | —     |
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1130-evcol.md > nm.log 2>&1) || true
  extract_section_h3 "$d/nm.log" "### Near-miss AC tables" > "$d/nm-sec.txt" 2>/dev/null || true
  grep -qF "SPEC-1130" "$d/nm-sec.txt" \
    || log_fail "near-miss section must flag SPEC-1130 (Evidence (TEST) column): $(cat "$d/nm.log")"
  grep -qiF "Evidence (TEST)" "$d/nm-sec.txt" \
    || log_fail "near-miss warning must name the malformed 'Evidence (TEST)' column"
  rm -rf "$d"
  log_pass "Evidence (TEST) column raises a distinct near-miss warning (not a silent mis-report)"
}

test_spec0011_nearmiss_both_surfaces() {  # TEST-005 / Spec-AC-04
  log_info "Test: non-canonical heading / Review-By-like column near-miss in BOTH docs-audit + INDEX.violations; canonical warns in neither (TEST-005)..."
  local d; d="$(setup_iso_repo s11-nearmiss-both)"
  # Near-miss: AC-looking table under a non-canonical heading, with a 'Review By' column.
  cat > "$d/docs/specs/SPEC-1140-noncanon.md" <<'MD'
---
id: SPEC-1140
type: spec
status: done
links:
  pr: []
---
# Done spec with an AC-looking table under a non-canonical heading

## Acceptance Criteria

| Spec-AC    | Description | Status | Evidence | Review By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  # Negative control: the exact canonical shape must warn in neither surface.
  cat > "$d/docs/specs/SPEC-1141-canonical.md" <<'MD'
---
id: SPEC-1141
type: spec
status: done
links:
  pr: []
---
# Done spec with the exact canonical AC table

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  # Surface 1: docs-audit.mjs
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs > nm.log 2>&1) || true
  extract_section_h3 "$d/nm.log" "### Near-miss AC tables" > "$d/nm-sec.txt" 2>/dev/null || true
  grep -qF "SPEC-1140" "$d/nm-sec.txt" \
    || log_fail "docs-audit near-miss section must flag SPEC-1140: $(cat "$d/nm.log")"
  if grep -qF "SPEC-1141" "$d/nm-sec.txt"; then
    log_fail "canonical SPEC-1141 must NOT be flagged as a near-miss (negative control)"
  fi
  # Surface 2: generate-docs-index.mjs -> docs/INDEX.violations.md
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen.log 2>&1) \
    || log_fail "generate-docs-index must exit 0 (degrade-and-report): $(cat "$d/gen.log")"
  assert_file "$d/docs/INDEX.violations.md"
  grep -qF "SPEC-1140" "$d/docs/INDEX.violations.md" \
    || log_fail "INDEX.violations.md must carry the near-miss warning for SPEC-1140"
  if grep -qF "SPEC-1141" "$d/docs/INDEX.violations.md"; then
    log_fail "canonical SPEC-1141 must NOT appear in INDEX.violations.md near-miss (negative control)"
  fi
  rm -rf "$d"
  log_pass "Near-miss surfaces in BOTH docs-audit and INDEX.violations; canonical shape in neither"
}

test_spec0011_review_claim_unbacked() {  # TEST-006 / Spec-AC-05
  log_info "Test: Review-By code-review with no event/artifact -> verdict review-claim-unbacked (TEST-006)..."
  local d; d="$(setup_iso_repo s11-g3-unbacked)"
  cat > "$d/docs/specs/SPEC-1150-claim.md" <<'MD'
---
id: SPEC-1150
type: spec
status: done
links:
  pr: []
---
# Done spec asserting code-review with no backing

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By   | Notes |
|------------|-------------|--------|----------|-------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | code-review | —     |
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1150-claim.md > g3.log 2>&1) || true
  grep -qF "review-claim-unbacked" "$d/g3.log" \
    || log_fail "unbacked code-review claim must yield review-claim-unbacked: $(cat "$d/g3.log")"
  grep -F "SPEC-1150" "$d/g3.log" | grep -qF "review-claim-unbacked" \
    || log_fail "review-claim-unbacked verdict must name SPEC-1150"
  rm -rf "$d"
  log_pass "Unbacked code-review Review-By claim flagged review-claim-unbacked"
}

test_spec0011_review_claim_backed() {  # TEST-007 / Spec-AC-06
  log_info "Test: a corroborating code_review_completed event clears review-claim-unbacked (positive control, TEST-007)..."
  local d; d="$(setup_iso_repo s11-g3-backed)"
  cat > "$d/docs/specs/SPEC-1150-claim.md" <<'MD'
---
id: SPEC-1150
type: spec
status: done
links:
  pr: []
---
# Done spec asserting code-review

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By   | Notes |
|------------|-------------|--------|----------|-------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | code-review | —     |
MD
  # Before backing: flagged (proves the check is a real cross-check, not accept-all).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1150-claim.md > before.log 2>&1) || true
  grep -qF "review-claim-unbacked" "$d/before.log" \
    || log_fail "pre-backing run must flag review-claim-unbacked (cross-check must be genuine)"
  # Produce a real corroborating event via append-event (crosses SEAM-2).
  (cd "$d" && node .aai/scripts/append-event.mjs --event code_review_completed --ref SPEC-1150 --verdict pass > /dev/null) \
    || log_fail "append-event code_review_completed must succeed"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1150-claim.md > after.log 2>&1) || true
  if grep -qF "review-claim-unbacked" "$d/after.log"; then
    log_fail "a backed claim (code_review_completed event) must clear review-claim-unbacked"
  fi
  rm -rf "$d"
  log_pass "Backed code-review claim clears review-claim-unbacked (real event producer -> real audit consumer)"
}

test_spec0011_event_types() {  # TEST-008 / Spec-AC-07
  log_info "Test: append-event accepts work_item_closed + code_review_completed; bogus exits 2 (TEST-008)..."
  local d; d="$(setup_iso_repo s11-events)"
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1160 --validation pass --code-review pass > /dev/null) \
    || log_fail "append-event work_item_closed must exit 0"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"event":"work_item_closed"' \
    || log_fail "work_item_closed must be appended as a JSONL event"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"code_review":"pass"' \
    || log_fail "work_item_closed payload must carry code_review"
  (cd "$d" && node .aai/scripts/append-event.mjs --event code_review_completed --ref SPEC-1160 --verdict pass > /dev/null) \
    || log_fail "append-event code_review_completed must exit 0"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"event":"code_review_completed"' \
    || log_fail "code_review_completed must be appended as a JSONL event"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"verdict":"pass"' \
    || log_fail "code_review_completed payload must carry verdict"
  local ec=0
  (cd "$d" && node .aai/scripts/append-event.mjs --event bogus --ref SPEC-1160 > /dev/null 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "an unknown event type must exit 2 (got $ec)"
  rm -rf "$d"
  log_pass "work_item_closed + code_review_completed accepted; unknown event exits 2"
}

test_spec0011_missing_close_telemetry() {  # TEST-009 / Spec-AC-07
  log_info "Test: done spec with no work_item_closed event -> missing-close-telemetry (report-only), clears when present; sibling id no cross-match (TEST-009)..."
  local d; d="$(setup_iso_repo s11-close-telem)"
  cat > "$d/docs/specs/SPEC-1170-done.md" <<'MD'
---
id: SPEC-1170
type: spec
status: done
links:
  pr: []
---
# Done spec awaiting close telemetry

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  # (a) report-only: --check --strict still exits 0 while the signal is present.
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-1170-done.md > t1.log 2>&1) \
    || log_fail "missing-close-telemetry must be report-only (--check --strict exit 0)"
  grep -qF "missing-close-telemetry" "$d/t1.log" \
    || log_fail "a done spec with no work_item_closed event must be reported missing-close-telemetry"
  grep -F "SPEC-1170" "$d/t1.log" | grep -qF "missing-close-telemetry" \
    || log_fail "missing-close-telemetry must name SPEC-1170"
  # (b) sibling id must NOT satisfy the parent.
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-11700 --validation pass --code-review pass > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1170-done.md > t2.log 2>&1) || true
  grep -qF "missing-close-telemetry" "$d/t2.log" \
    || log_fail "a sibling-id (SPEC-11700) close event must NOT satisfy SPEC-1170"
  # (c) clears once the real event references the id.
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1170 --validation pass --code-review pass > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-1170-done.md > t3.log 2>&1) || true
  if grep -qF "missing-close-telemetry" "$d/t3.log"; then
    log_fail "missing-close-telemetry must clear once a work_item_closed event references SPEC-1170"
  fi
  rm -rf "$d"
  log_pass "missing-close-telemetry is report-only, sibling-bounded, and clears on the real event"
}

test_spec0011_closeout_prompts_wired() {  # TEST-010 / Spec-AC-08
  log_info "Test: VALIDATION step 8b + METRICS_FLUSH + SKILL_WRAP_UP wire --gate + work_item_closed + enforce/report-only (TEST-010)..."
  local val="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  local flush="$PROJECT_ROOT/.aai/METRICS_FLUSH.prompt.md"
  local wrap="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"
  assert_file "$val"; assert_file "$flush"; assert_file "$wrap"
  # VALIDATION step 8b: runs the gate before the done-flip, emits work_item_closed,
  # and branches on enforce vs report-only.
  assert_contains "$val" "docs-audit.mjs --gate"
  assert_contains "$val" "work_item_closed"
  grep -qF "enforce" "$val" || log_fail "VALIDATION must reference the enforce branch"
  grep -qF "report-only" "$val" || log_fail "VALIDATION must reference the report-only branch"
  # METRICS_FLUSH (SPEC-0054/CHANGE-0038 — flush no longer owns the close
  # lifecycle): must NOT claim it emits work_item_closed/doc_lifecycle, and
  # must point at close-work-item.mjs as the single source of truth instead.
  grep -qF "work_item_closed" "$flush" \
    && log_fail "METRICS_FLUSH.prompt.md must not claim it emits work_item_closed — close-work-item.mjs owns the close lifecycle (SPEC-0054): $(grep -n work_item_closed "$flush")"
  grep -qF "doc_lifecycle" "$flush" \
    && log_fail "METRICS_FLUSH.prompt.md must not claim it emits doc_lifecycle — close-work-item.mjs owns the close lifecycle (SPEC-0054): $(grep -n doc_lifecycle "$flush")"
  assert_contains "$flush" "close-work-item.mjs"
  # SKILL_WRAP_UP: closeout step runs the gate.
  assert_contains "$wrap" "docs-audit.mjs --gate"
  log_pass "Closeout prompts wire --gate + enforce/report-only branch; METRICS_FLUSH no longer claims the close-event emission (SPEC-0054)"
}

test_spec0011_config_close_gate() {  # TEST-011 / Spec-AC-09
  log_info "Test: loadConfig exposes close_gate default report-only; enforce/report-only parsed (TEST-011)..."
  local d; d="$(setup_iso_repo s11-config)"
  cat > "$d/cfg.mjs" <<'EOF'
import { loadConfig } from './.aai/scripts/lib/docs-audit-core.mjs';
import fs from 'node:fs';
import assert from 'node:assert';
const P = 'docs/ai/docs-audit.yaml';
// (a) config present WITHOUT close_gate -> default report-only.
fs.writeFileSync(P, 'legacy_until_date: 2026-06-01\nstale_after_days: 90\n');
assert.strictEqual(loadConfig(process.cwd()).close_gate, 'report-only', 'default must be report-only');
// (b) explicit enforce.
fs.writeFileSync(P, 'legacy_until_date: 2026-06-01\nclose_gate: enforce\n');
assert.strictEqual(loadConfig(process.cwd()).close_gate, 'enforce', 'enforce must be parsed');
// (c) explicit report-only.
fs.writeFileSync(P, 'close_gate: report-only\n');
assert.strictEqual(loadConfig(process.cwd()).close_gate, 'report-only', 'report-only must be parsed');
console.log('ok');
EOF
  (cd "$d" && node cfg.mjs) > "$d/cfg.log" 2>&1 \
    || log_fail "loadConfig close_gate handling incorrect: $(cat "$d/cfg.log")"
  rm -rf "$d"
  log_pass "loadConfig exposes close_gate (default report-only; enforce/report-only parsed)"
}

test_spec0011_hook_close_gate() {  # TEST-012 / Spec-AC-10
  log_info "Test: pre-commit hook aborts an unreconciled done-flip under enforce, warns under report-only, clean when reconciled (TEST-012)..."
  local d; d="$(setup_spec0011_hook_repo gate)"
  # Baseline: three specs committed as 'implementing' with an incomplete AC table.
  for n in 1180 1181 1182; do
    cat > "$d/docs/specs/SPEC-${n}-flip.md" <<MD
---
id: SPEC-${n}
type: spec
status: implementing
links:
  pr: []
---
# Flip candidate ${n}

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | implementing | —        | —         | —     |
MD
  done
  (cd "$d" && git add docs/specs && git commit -qm "docs: baseline implementing specs" >/dev/null) \
    || log_fail "baseline commit failed"

  # (a) report-only default: an unreconciled done-flip WARNS but commits.
  printf 'close_gate: report-only\n' > "$d/docs/ai/docs-audit.yaml"
  sed -i.bak 's/^status: implementing/status: done/' "$d/docs/specs/SPEC-1180-flip.md" && rm -f "$d/docs/specs/SPEC-1180-flip.md.bak"
  (cd "$d" && git add docs/specs/SPEC-1180-flip.md docs/ai/docs-audit.yaml)
  local ec=0
  (cd "$d" && git commit -qm "docs: flip SPEC-1180 to done (report-only)" > report.out 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "report-only default must let the unreconciled done-flip commit (got $ec): $(cat "$d/report.out")"
  grep -qiF "close-gate" "$d/report.out" || log_fail "report-only path must print a close-gate warning"

  # (b) enforce: an unreconciled done-flip ABORTS with reasons.
  printf 'close_gate: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  sed -i.bak 's/^status: implementing/status: done/' "$d/docs/specs/SPEC-1181-flip.md" && rm -f "$d/docs/specs/SPEC-1181-flip.md.bak"
  (cd "$d" && git add docs/specs/SPEC-1181-flip.md docs/ai/docs-audit.yaml)
  ec=0
  (cd "$d" && git commit -qm "docs: flip SPEC-1181 to done (enforce)" > enforce.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "enforce must ABORT an unreconciled done-flip commit"
  grep -qF "SPEC-1181" "$d/enforce.out" || log_fail "enforce abort must name the failing spec SPEC-1181"
  # the failing spec must NOT have been committed
  if (cd "$d" && git cat-file -e "HEAD:docs/specs/SPEC-1181-flip.md" 2>/dev/null) && \
     (cd "$d" && git show HEAD:docs/specs/SPEC-1181-flip.md | grep -qF 'status: done'); then
    log_fail "the aborted done-flip must not have been committed"
  fi
  # Unstage/revert the aborted flip so its staged 'status: done' does not pollute
  # the next commit (a failed commit leaves the index staged). Working-tree
  # docs-audit.yaml stays 'enforce' for sub-case (c).
  (cd "$d" && git reset -q && git checkout -q -- docs/specs/SPEC-1181-flip.md)

  # (c) reconciled done-flip under enforce commits clean.
  cat > "$d/docs/specs/SPEC-1182-flip.md" <<'MD'
---
id: SPEC-1182
type: spec
status: done
links:
  pr: []
---
# Flip candidate 1182 (reconciled)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  (cd "$d" && git add docs/specs/SPEC-1182-flip.md)
  ec=0
  (cd "$d" && git commit -qm "docs: flip SPEC-1182 to done (reconciled, enforce)" > clean.out 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "a reconciled done-flip must commit clean under enforce (got $ec): $(cat "$d/clean.out")"
  rm -rf "$d"
  log_pass "Hook: enforce aborts unreconciled done-flip, report-only warns, reconciled commits clean"
}

test_spec0011_hook_parity_grep() {  # TEST-013 / Spec-AC-10
  log_info "Test: install-pre-commit-hook.sh AND .ps1 both embed the close-gate block at parity (TEST-013)..."
  local sh="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh"
  local ps="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1"
  assert_file "$sh"; assert_file "$ps"
  for f in "$sh" "$ps"; do
    grep -qF "AAI:INDEX-AUTOGEN" "$f" || log_fail "$f must keep the AAI:INDEX-AUTOGEN marker"
    grep -qF "docs-audit.mjs --gate" "$f" || log_fail "$f must embed the --gate call"
    grep -qF "close_gate" "$f" || log_fail "$f must read the close_gate config"
    grep -qF "enforce" "$f" || log_fail "$f must branch on enforce"
    grep -qF "report-only" "$f" || log_fail "$f must branch on report-only"
  done
  log_pass "Both installers embed the close-gate block at parity"
}

test_spec0011_read_only() {  # TEST-014 / Spec-AC-11
  log_info "Test: --gate + G3/G4 audit mutate NO fixture doc (RFC-0002 read-only invariant) (TEST-014)..."
  local d; d="$(setup_iso_repo s11-readonly)"
  cat > "$d/docs/specs/SPEC-1190-nearmiss.md" <<'MD'
---
id: SPEC-1190
type: spec
status: done
links:
  pr: []
---
# Near-miss + code-review claim fixture

## Acceptance Criteria

| Spec-AC    | Description | Status | Evidence | Review By   | Notes |
|------------|-------------|--------|----------|-------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | code-review | —     |
MD
  cat > "$d/docs/specs/SPEC-1191-done.md" <<'MD'
---
id: SPEC-1191
type: spec
status: done
links:
  pr: []
---
# Reconciled done spec

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  local before after
  before="$(cd "$d" && find docs/specs -type f -name '*.md' | sort | xargs shasum | shasum)"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs > ro-audit.log 2>&1) || true
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1191 > ro-gate.log 2>&1) || true
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1190 > ro-gate2.log 2>&1) || true
  after="$(cd "$d" && find docs/specs -type f -name '*.md' | sort | xargs shasum | shasum)"
  [[ "$before" == "$after" ]] || log_fail "the audit/gate paths must not modify any doc file"
  rm -rf "$d"
  log_pass "--gate and the G3/G4 audit are read-only over the fixture docs"
}

test_spec0011_gate_honors_config_review_by_methods() {  # TEST-016 / Spec-AC-01 (BP-001 remediation)
  log_info "Test: --gate threads config.review_by_methods into parseReviewBy, so a configured combo token passes (TEST-016)..."
  local d; d="$(setup_iso_repo s11-gate-cfgmethods)"
  # A fully-reconciled done spec whose only Review-By token ('sast:<date>') is a
  # combo that is INVALID under the built-in method whitelist and ONLY valid when
  # the project configures review_by_methods. Pre-fix gateDoc dropped the
  # extraMethods argument, so this token classified as invalid -> FALSE gate FAIL.
  cat > "$d/docs/specs/SPEC-1200-cfgmethod.md" <<'MD'
---
id: SPEC-1200
type: spec
status: done
links:
  pr: []
---
# Done spec whose Review-By relies on a configured method

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By     | Notes |
|------------|-------------|--------|----------|---------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | sast:2026-05-01 | —   |
MD
  # (a) WITH the configured method: gate must ACCEPT (exit 0). This is the
  #     assertion that FAILS against pre-fix code (extraMethods ignored -> exit 1)
  #     and PASSES post-fix.
  printf 'review_by_methods: [sast]\nclose_gate: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1200 > gcfg.log 2>&1) \
    || log_fail "--gate must exit 0 when config.review_by_methods makes the token valid (BP-001): $(cat "$d/gcfg.log")"
  # (b) Control — WITHOUT the configured method the very same token is genuinely
  #     schema-invalid, so the gate must FAIL (exit 1) naming the AC and Review-By.
  #     Proves the token's validity is contingent on the configured method (i.e.
  #     this is exactly the case BP-001 would have mis-gated).
  printf 'close_gate: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-1200 > gnocfg.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "without review_by_methods the combo token must fail the gate (got $ec): $(cat "$d/gnocfg.log")"
  grep -qF "Spec-AC-01" "$d/gnocfg.log" || log_fail "gate reason must name the offending Spec-AC-01"
  grep -qiF "review-by" "$d/gnocfg.log" || log_fail "gate reason must mention Review-By"
  rm -rf "$d"
  log_pass "--gate honors config.review_by_methods (configured combo passes; unconfigured fails)"
}

test_spec0011_hook_gates_staged_not_worktree() {  # TEST-017 / Spec-AC-10 (F2 remediation)
  log_info "Test: hook gates the STAGED blob, not the worktree — staged-unreconciled done aborts under enforce even when the worktree adds Evidence (TEST-017)..."
  local d; d="$(setup_spec0011_hook_repo stagedgate)"
  # Baseline: an 'implementing' spec whose AC table has a done row with EMPTY evidence.
  cat > "$d/docs/specs/SPEC-1210-flip.md" <<'MD'
---
id: SPEC-1210
type: spec
status: implementing
links:
  pr: []
---
# Flip candidate 1210

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | —        | TDD       | —     |
MD
  (cd "$d" && git add docs/specs && git commit -qm "docs: baseline implementing spec" >/dev/null) \
    || log_fail "baseline commit failed"

  printf 'close_gate: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  # STAGE an unreconciled done-flip: status done but the done row's Evidence is still empty.
  cat > "$d/docs/specs/SPEC-1210-flip.md" <<'MD'
---
id: SPEC-1210
type: spec
status: done
links:
  pr: []
---
# Flip candidate 1210

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | —        | TDD       | —     |
MD
  (cd "$d" && git add docs/specs/SPEC-1210-flip.md docs/ai/docs-audit.yaml)
  # Now the WORKTREE reconciles the row (adds Evidence) but is LEFT UNSTAGED, so the
  # worktree passes the gate while the STAGED content is still unreconciled. Pre-fix
  # the hook gated the worktree and let this through; post-fix it gates the staged blob.
  cat > "$d/docs/specs/SPEC-1210-flip.md" <<'MD'
---
id: SPEC-1210
type: spec
status: done
links:
  pr: []
---
# Flip candidate 1210

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | TDD       | —     |
MD
  local ec=0
  (cd "$d" && git commit -qm "docs: flip SPEC-1210 to done (staged unreconciled)" > staged.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "enforce must ABORT: the STAGED content is unreconciled even though the worktree has Evidence (got $ec): $(cat "$d/staged.out")"
  grep -qF "SPEC-1210" "$d/staged.out" || log_fail "abort must name the failing spec SPEC-1210"
  grep -qiF "evidence" "$d/staged.out" || log_fail "abort reason must name the empty-evidence row (staged content)"
  # the failing spec must NOT have been committed
  if (cd "$d" && git cat-file -e "HEAD:docs/specs/SPEC-1210-flip.md" 2>/dev/null) && \
     (cd "$d" && git show HEAD:docs/specs/SPEC-1210-flip.md | grep -qF 'status: done'); then
    log_fail "the aborted staged-unreconciled done-flip must not have been committed"
  fi
  rm -rf "$d"
  log_pass "Hook gates the STAGED blob, not the worktree (staged-unreconciled done aborts under enforce)"
}

test_spec0011_work_item_closed_requires_fields() {  # TEST-018 / Spec-AC-07 (F3 remediation)
  log_info "Test: work_item_closed requires BOTH --validation and --code-review (empty payload rejected) (TEST-018)..."
  local d; d="$(setup_iso_repo s11-witclose-fields)"
  local ec=0
  # (a) neither field -> exit 2
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1220 > /dev/null 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "work_item_closed with no validation/code-review must exit 2 (got $ec)"
  # (b) only --validation -> exit 2
  ec=0
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1220 --validation pass > /dev/null 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "work_item_closed with only --validation must exit 2 (got $ec)"
  # (c) only --code-review -> exit 2
  ec=0
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1220 --code-review pass > /dev/null 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "work_item_closed with only --code-review must exit 2 (got $ec)"
  # no event may have been appended by the rejected calls
  if [[ -f "$d/docs/ai/EVENTS.jsonl" ]] && grep -qF 'work_item_closed' "$d/docs/ai/EVENTS.jsonl"; then
    log_fail "a rejected work_item_closed must not append an event"
  fi
  # (d) both fields -> exit 0 and a well-formed event is appended
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed --ref SPEC-1220 --validation pass --code-review pass > /dev/null) \
    || log_fail "work_item_closed with both fields must exit 0"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"event":"work_item_closed"' \
    || log_fail "a valid work_item_closed must append a JSONL event"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"validation":"pass"' \
    || log_fail "the valid event payload must carry validation"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"code_review":"pass"' \
    || log_fail "the valid event payload must carry code_review"
  rm -rf "$d"
  log_pass "work_item_closed rejects an empty/partial payload (exit 2); a complete payload exits 0"
}

test_spec0011_review_artifact_boundary() {  # TEST-019 / Spec-AC-06 (F4 remediation)
  log_info "Test: a review artifact named for SPEC-0011 must NOT corroborate a claim for SPEC-001 (substring boundary) (TEST-019)..."
  local d; d="$(setup_iso_repo s11-artifact-boundary)"
  mkdir -p "$d/docs/ai/reviews"
  # Only a longer-sibling artifact exists; it must NOT clear the shorter id's claim.
  : > "$d/docs/ai/reviews/review-SPEC-0011-foo.md"
  cat > "$d/docs/specs/SPEC-001-claim.md" <<'MD'
---
id: SPEC-001
type: spec
status: done
links:
  pr: []
---
# Done spec asserting code-review (shorter id)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By   | Notes |
|------------|-------------|--------|----------|-------------|-------|
| Spec-AC-01 | first       | done   | a1b2c3d  | code-review | —     |
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-001-claim.md > before.log 2>&1) || true
  grep -F "SPEC-001" "$d/before.log" | grep -qF "review-claim-unbacked" \
    || log_fail "a SPEC-0011 artifact must NOT corroborate SPEC-001 (substring false-match): $(cat "$d/before.log")"
  # Positive control: the exact-id artifact DOES corroborate and clears the verdict.
  : > "$d/docs/ai/reviews/review-SPEC-001-bar.md"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event --path docs/specs/SPEC-001-claim.md > after.log 2>&1) || true
  if grep -qF "review-claim-unbacked" "$d/after.log"; then
    log_fail "an exact-id (SPEC-001) artifact must clear review-claim-unbacked"
  fi
  rm -rf "$d"
  log_pass "review artifact match is boundary-aware (SPEC-0011 does not corroborate SPEC-001; exact id does)"
}

test_spec0011_regression() {  # TEST-015 / Spec-AC-12
  log_info "Test: real-repo docs-audit CLEAN, no false near-miss, INDEX idempotent (TEST-015)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/s11-audit.log" 2>&1) \
    || log_fail "real-repo docs-audit --check --strict must exit 0: $(tail -5 "$TEST_DIR/s11-audit.log")"
  # SPEC-0057: see test_spec0006_no_regression_real_repo's comment — the
  # real-repo Verdict line now correctly reads NEEDS-TRIAGE (3 pre-existing,
  # tracked, verdict-only duplicate-doc-id collisions); assert the hard-gate
  # signal this stanza actually guards instead.
  assert_contains "$TEST_DIR/s11-audit.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/s11-audit.log" "CHECK FAILED"
  # No false near-miss on the real corpus (narrow-by-construction detector).
  extract_section_h3 "$TEST_DIR/s11-audit.log" "### Near-miss AC tables" > "$TEST_DIR/s11-nm.txt" 2>/dev/null || true
  grep -qF "_None._" "$TEST_DIR/s11-nm.txt" \
    || log_fail "real-repo near-miss section must be empty (no canonical shape may trip it): $(cat "$TEST_DIR/s11-nm.txt")"
  # INDEX idempotent (backup/restore the real committed index).
  local idx_backup="$TEST_DIR/INDEX.s11.orig"
  cp "$PROJECT_ROOT/docs/INDEX.md" "$idx_backup"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/s11-idx1.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 1) failed: $(cat "$TEST_DIR/s11-idx1.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/s11-idx1.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > "$TEST_DIR/s11-idx2.log" 2>&1) \
    || { cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"; log_fail "real-repo index gen (run 2) failed: $(cat "$TEST_DIR/s11-idx2.log")"; }
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/s11-idx2.snap"
  cp "$idx_backup" "$PROJECT_ROOT/docs/INDEX.md"
  diff -q "$TEST_DIR/s11-idx1.snap" "$TEST_DIR/s11-idx2.snap" >/dev/null \
    || log_fail "real-repo INDEX must be idempotent modulo the Generated line"
  log_pass "Real-repo audit CLEAN, no false near-miss, INDEX idempotent"
}

# --- CHANGE-0007 / SPEC-0013 H1 — body lint (TEST-001..009) ------------------

test_change0007_lint_stray_markup() {  # TEST-001 / Spec-AC-01
  log_info "Test: stray </content> outside code -> stray-tool-markup finding with rule id + line (TEST-001)..."
  local d; d="$(setup_iso_repo c7-stray)"
  cat > "$d/docs/specs/SPEC-7701-stray.md" <<'MD'
---
id: SPEC-7701
type: spec
status: draft
links:
  pr: []
---
# Spec with leaked tool markup

Some prose.
</content>
More residue: <invoke name="Bash"> here.
MD
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "--lint-body without --strict must exit 0 (got $ec): $(cat "$d/lint.log")"
  assert_contains "$d/lint.log" "### Body lint"
  grep -qE 'SPEC-7701-stray\.md:11 .*stray-tool-markup' "$d/lint.log" \
    || log_fail "finding must carry rel:line 11 + rule id stray-tool-markup: $(cat "$d/lint.log")"
  grep -qE 'SPEC-7701-stray\.md:12 .*stray-tool-markup' "$d/lint.log" \
    || log_fail "<invoke ...> on line 12 must also be flagged: $(cat "$d/lint.log")"
  # The same section must ride in the ordinary --check digest (report-only).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > check.log 2>&1) || true
  grep -qE '^### Body lint: [1-9]' "$d/check.log" \
    || log_fail "--check digest must carry a non-zero '### Body lint:' section: $(cat "$d/check.log")"
  rm -rf "$d"
  log_pass "Stray tool markup flagged with rule id + line in the Body lint section (TEST-001)"
}

test_change0007_lint_unbalanced_fence() {  # TEST-002 / Spec-AC-01
  log_info "Test: unclosed \`\`\` fence at EOF -> unbalanced-fence finding (TEST-002)..."
  local d; d="$(setup_iso_repo c7-fence)"
  cat > "$d/docs/specs/SPEC-7702-fence.md" <<'MD'
---
id: SPEC-7702
type: spec
status: draft
links:
  pr: []
---
# Spec with an unclosed fence

Prose.
```js
const x = 1;
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) \
    || log_fail "--lint-body must exit 0 without --strict: $(cat "$d/lint.log")"
  grep -qE 'SPEC-7702-fence\.md:11 .*unbalanced-fence' "$d/lint.log" \
    || log_fail "unclosed fence must be flagged as unbalanced-fence at its opening line 11: $(cat "$d/lint.log")"
  rm -rf "$d"
  log_pass "Unclosed fence at EOF flagged as unbalanced-fence (TEST-002)"
}

test_change0007_lint_placeholder() {  # TEST-003 / Spec-AC-01
  log_info "Test: SPEC-XXXX residue + <PLACEHOLDER> flagged; mixed-case angle prose NOT flagged (TEST-003)..."
  local d; d="$(setup_iso_repo c7-ph)"
  cat > "$d/docs/specs/SPEC-7703-ph.md" <<'MD'
---
id: SPEC-7703
type: spec
status: draft
links:
  pr: []
---
# Spec with template residue

Unfilled id SPEC-XXXX left in the body.
An all-caps token <PLACEHOLDER> and <TODO_FILL> too.
But <why isolation is or is not useful> is legitimate prose.
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) \
    || log_fail "--lint-body must exit 0 without --strict: $(cat "$d/lint.log")"
  grep -qE 'SPEC-7703-ph\.md:10 .*template-placeholder' "$d/lint.log" \
    || log_fail "SPEC-XXXX body residue must be flagged as template-placeholder: $(cat "$d/lint.log")"
  grep -qE 'SPEC-7703-ph\.md:11 .*template-placeholder' "$d/lint.log" \
    || log_fail "<PLACEHOLDER>/<TODO_FILL> must be flagged as template-placeholder: $(cat "$d/lint.log")"
  grep -qF "why isolation" "$d/lint.log" \
    && log_fail "mixed-case angle prose must NOT be flagged (false-positive posture): $(cat "$d/lint.log")"
  grep -qE ':12 ' "$d/lint.log" \
    && log_fail "line 12 (mixed-case angle prose) must carry no finding: $(cat "$d/lint.log")"
  rm -rf "$d"
  log_pass "Template placeholders flagged; mixed-case angle prose spared (TEST-003)"
}

test_change0007_lint_negative_controls() {  # TEST-004 / Spec-AC-01
  log_info "Test: clean doc + stray tag inside fence/inline code -> zero findings (TEST-004)..."
  local d; d="$(setup_iso_repo c7-neg)"
  cat > "$d/docs/specs/SPEC-7704-clean.md" <<'MD'
---
id: SPEC-7704
type: spec
status: draft
links:
  pr: []
---
# Entirely clean spec

Ordinary prose only.
MD
  cat > "$d/docs/specs/SPEC-7705-examples.md" <<'MD'
---
id: SPEC-7705
type: spec
status: draft
links:
  pr: []
---
# Spec whose EXAMPLES carry the tokens (fences-in-examples control)

```text
</content>
<PLACEHOLDER>
SPEC-XXXX
```

Inline `</content>` and `SPEC-XXXX` and `<PLACEHOLDER>` in code spans.
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) \
    || log_fail "--lint-body must exit 0: $(cat "$d/lint.log")"
  grep -qE '^### Body lint: 0' "$d/lint.log" \
    || log_fail "clean + examples-only corpus must yield zero findings: $(cat "$d/lint.log")"
  rm -rf "$d"
  log_pass "Fenced and inline-code examples never flagged; clean doc clean (TEST-004)"
}

test_change0007_lint_degenerate_fixtures() {  # TEST-005 / Spec-AC-01
  log_info "Test: empty body / frontmatter-only / 4-backtick-wraps-3 / tilde fences -> no crash, correct verdicts (TEST-005)..."
  local d; d="$(setup_iso_repo c7-degen)"
  # degenerate: empty body
  printf -- '---\nid: SPEC-7706\ntype: spec\nstatus: draft\nlinks:\n  pr: []\n---\n' \
    > "$d/docs/specs/SPEC-7706-emptybody.md"
  # degenerate: frontmatter-only, no trailing newline
  printf -- '---\nid: SPEC-7707\ntype: spec\nstatus: draft\nlinks:\n  pr: []\n---' \
    > "$d/docs/specs/SPEC-7707-fmonly.md"
  # nesting: 4-backtick fence wrapping a 3-backtick example — balanced, clean
  cat > "$d/docs/specs/SPEC-7708-nested.md" <<'MD'
---
id: SPEC-7708
type: spec
status: draft
links:
  pr: []
---
# Four-backtick fence wrapping a three-backtick example

````markdown
```js
</content>
```
````
MD
  # tilde fence: balanced, tokens inside are content
  cat > "$d/docs/specs/SPEC-7709-tilde.md" <<'MD'
---
id: SPEC-7709
type: spec
status: draft
links:
  pr: []
---
# Tilde fence

~~~
</content>
~~~
MD
  # tilde fence left open -> flagged
  cat > "$d/docs/specs/SPEC-7710-tildeopen.md" <<'MD'
---
id: SPEC-7710
type: spec
status: draft
links:
  pr: []
---
# Unclosed tilde fence

~~~
still open at EOF
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) \
    || log_fail "--lint-body must not crash on degenerate fixtures: $(cat "$d/lint.log")"
  grep -qE '^### Body lint: 1' "$d/lint.log" \
    || log_fail "exactly ONE finding expected (the open tilde fence): $(cat "$d/lint.log")"
  grep -qE 'SPEC-7710-tildeopen\.md:10 .*unbalanced-fence' "$d/lint.log" \
    || log_fail "the open tilde fence must be the flagged finding: $(cat "$d/lint.log")"
  rm -rf "$d"
  log_pass "Degenerate + nesting fixtures: no crash, only the open tilde fence flagged (TEST-005)"
}

test_change0007_lint_promotion_pair() {  # TEST-006 / Spec-AC-01
  log_info "Test: findings -> --check exit 0 (report-only) but --check --strict exit 1 naming body lint; clean -> both 0 (TEST-006)..."
  local d; d="$(setup_iso_repo c7-promo)"
  # config-enforced mode (NOT strict): body lint must NOT promote to hardFail
  printf 'legacy_until_date: 2020-01-01\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7711-dirty.md" <<'MD'
---
id: SPEC-7711
type: spec
status: draft
links:
  pr: []
---
# Dirty body

</content>
MD
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > check.log 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "config-enforced --check WITHOUT --strict must stay exit 0 on body findings (got $ec): $(cat "$d/check.log")"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > strict.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--check --strict must exit 1 on body findings (got $ec): $(cat "$d/strict.log")"
  grep -qiE 'CHECK FAILED.*body lint' "$d/strict.log" \
    || log_fail "the strict failure must NAME body lint: $(cat "$d/strict.log")"
  # clean corpus -> both exit 0
  rm "$d/docs/specs/SPEC-7711-dirty.md"
  cat > "$d/docs/specs/SPEC-7712-clean.md" <<'MD'
---
id: SPEC-7712
type: spec
status: draft
links:
  pr: []
---
# Clean body
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > c1.log 2>&1) \
    || log_fail "clean corpus --check must exit 0: $(cat "$d/c1.log")"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > c2.log 2>&1) \
    || log_fail "clean corpus --check --strict must exit 0: $(cat "$d/c2.log")"
  rm -rf "$d"
  log_pass "Promotion pair: report-only by default, hard-fail only under --strict (TEST-006)"
}

test_change0007_lint_body_file_predicate() {  # TEST-007 / Spec-AC-01
  log_info "Test: --lint-body-file dirty->1 with findings, clean->0, missing->2 (TEST-007)..."
  local d; d="$(setup_iso_repo c7-blob)"
  printf '# Blob\n\n</content>\n' > "$d/dirty-blob.md"
  printf '# Blob\n\nclean prose\n' > "$d/clean-blob.md"
  local ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body-file dirty-blob.md > dirty.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--lint-body-file on a dirty blob must exit 1 (got $ec): $(cat "$d/dirty.log")"
  grep -qF "stray-tool-markup" "$d/dirty.log" \
    || log_fail "dirty blob findings must be printed: $(cat "$d/dirty.log")"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body-file clean-blob.md > clean.log 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "--lint-body-file on a clean blob must exit 0 (got $ec): $(cat "$d/clean.log")"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body-file no-such-file.md > missing.log 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--lint-body-file on a missing file must exit 2 (got $ec): $(cat "$d/missing.log")"
  # No docs_audit event may be emitted by the pure predicate.
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] \
    || log_fail "--lint-body-file must never emit a docs_audit event"
  rm -rf "$d"
  log_pass "--lint-body-file exit contract 1/0/2 honored, no event (TEST-007)"
}

test_change0007_hook_body_lint() {  # TEST-008 / Spec-AC-01
  log_info "Test: hook lints the STAGED blob — warn by default, block under body_lint: enforce, staged-clean passes (TEST-008)..."
  # Wiring greps first: intake POST-SAVE + both installers reference body lint.
  grep -qi "body lint" "$PROJECT_ROOT/.aai/SKILL_INTAKE.prompt.md" \
    || log_fail "SKILL_INTAKE STEP 2.5 must reference body lint"
  grep -qF -- "--lint-body-file" "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" \
    || log_fail "install-pre-commit-hook.sh must embed the --lint-body-file call"
  grep -qF -- "--lint-body-file" "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1" \
    || log_fail "install-pre-commit-hook.ps1 must embed the --lint-body-file call (parity)"
  grep -qF "body_lint" "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" \
    || log_fail "install-pre-commit-hook.sh must read the body_lint config key"
  grep -qF "body_lint" "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1" \
    || log_fail "install-pre-commit-hook.ps1 must read the body_lint config key (parity)"

  local d; d="$(setup_spec0011_hook_repo bodylint)"
  grep -qF -- "--lint-body-file" "$d/.git/hooks/pre-commit" \
    || log_fail "generated hook must carry the body-lint block"

  # (a) staged-dirty / worktree-clean, DEFAULT (no config): warn but commit (TOCTOU rule).
  cat > "$d/docs/specs/SPEC-7801-lint.md" <<'MD'
---
id: SPEC-7801
type: spec
status: draft
links:
  pr: []
---
# Staged dirty

</content>
MD
  (cd "$d" && git add docs/specs/SPEC-7801-lint.md)
  # fix the WORKTREE copy only — the STAGED blob stays dirty
  cat > "$d/docs/specs/SPEC-7801-lint.md" <<'MD'
---
id: SPEC-7801
type: spec
status: draft
links:
  pr: []
---
# Staged dirty

clean now
MD
  local ec=0
  (cd "$d" && git commit -qm "docs: staged-dirty default" > a.out 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "default (report-only) must let the dirty staged blob commit (got $ec): $(cat "$d/a.out")"
  grep -qiF "body-lint" "$d/a.out" \
    || log_fail "default path must print a body-lint WARNING for the STAGED blob (worktree is clean!): $(cat "$d/a.out")"

  # (b) body_lint: enforce blocks the dirty staged blob.
  printf 'body_lint: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7802-lint.md" <<'MD'
---
id: SPEC-7802
type: spec
status: draft
links:
  pr: []
---
# Enforce me

<PLACEHOLDER>
MD
  (cd "$d" && git add docs/specs/SPEC-7802-lint.md docs/ai/docs-audit.yaml)
  ec=0
  (cd "$d" && git commit -qm "docs: enforce block" > b.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "body_lint: enforce must ABORT the commit of a dirty staged doc"
  grep -qiF "body-lint" "$d/b.out" || log_fail "enforce abort must name body-lint: $(cat "$d/b.out")"
  (cd "$d" && git reset -q && rm -f docs/specs/SPEC-7802-lint.md)

  # (c) staged-clean / worktree-dirty passes silently (gate the staged blob, not the worktree).
  rm -f "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7803-lint.md" <<'MD'
---
id: SPEC-7803
type: spec
status: draft
links:
  pr: []
---
# Staged clean

fine
MD
  (cd "$d" && git add docs/specs/SPEC-7803-lint.md)
  printf '\n</content>\n' >> "$d/docs/specs/SPEC-7803-lint.md"   # dirty the WORKTREE only
  ec=0
  (cd "$d" && git commit -qm "docs: staged-clean worktree-dirty" > c.out 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "a clean STAGED blob must commit even with a dirty worktree (got $ec): $(cat "$d/c.out")"
  grep -qiF "body-lint" "$d/c.out" \
    && log_fail "no body-lint warning may fire for a clean staged blob: $(cat "$d/c.out")"
  rm -rf "$d"
  log_pass "Hook body lint: staged-blob discipline, warn default, enforce blocks (TEST-008)"
}

test_change0007_regression() {  # TEST-009 / Spec-AC-09
  # INDEX idempotence on the real repo is asserted by test_spec0011_regression
  # in this same suite run; this case owns the body-lint-specific regression.
  log_info "Test: real repo stays CLEAN under --check --strict with body lint active (TEST-009)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --lint-body --no-event > "$TEST_DIR/c7-lint.log" 2>&1) \
    || log_fail "real-repo --lint-body must exit 0: $(tail -10 "$TEST_DIR/c7-lint.log")"
  grep -qE '^### Body lint: 0' "$TEST_DIR/c7-lint.log" \
    || log_fail "real-repo governed corpus must carry ZERO body-lint findings: $(cat "$TEST_DIR/c7-lint.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/c7-strict.log" 2>&1) \
    || log_fail "real-repo --check --strict must exit 0 with body lint active: $(tail -10 "$TEST_DIR/c7-strict.log")"
  # SPEC-0057: see test_spec0006_no_regression_real_repo's comment — the
  # real-repo Verdict line now correctly reads NEEDS-TRIAGE (3 pre-existing,
  # tracked, verdict-only duplicate-doc-id collisions, unrelated to body
  # lint); assert the hard-gate signal this stanza actually guards instead.
  assert_contains "$TEST_DIR/c7-strict.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/c7-strict.log" "CHECK FAILED"
  log_pass "Real repo CLEAN with body lint active (TEST-009)"
}

test_change0007_hook_config_staged() {  # TEST-019 / Spec-AC-01 (review-20260704T110648Z W1)
  log_info "Test: hook reads body_lint/close_gate mode from the STAGED/HEAD config — an unstaged worktree downgrade cannot bypass enforce (TEST-019)..."
  local d; d="$(setup_spec0011_hook_repo cfgstaged)"
  # Baseline: BOTH gate keys committed as enforce + one implementing spec for
  # the close-gate sub-case.
  printf 'close_gate: enforce\nbody_lint: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7901-flip.md" <<'MD'
---
id: SPEC-7901
type: spec
status: implementing
links:
  pr: []
---
# Flip candidate 7901

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | implementing | —        | —         | —     |
MD
  (cd "$d" && git add docs/ai/docs-audit.yaml docs/specs/SPEC-7901-flip.md \
    && git commit -qm "docs: enforce config + implementing spec" >/dev/null) \
    || log_fail "baseline commit failed"

  # (a) body_lint: an UNSTAGED worktree edit downgrades enforce -> report-only;
  # the staged dirty doc must STILL be blocked (config TOCTOU, SPEC-0011-F2 class).
  printf 'close_gate: enforce\nbody_lint: report-only\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7902-dirty.md" <<'MD'
---
id: SPEC-7902
type: spec
status: draft
links:
  pr: []
---
# Dirty body

</content>
MD
  (cd "$d" && git add docs/specs/SPEC-7902-dirty.md)
  local ec=0
  (cd "$d" && git commit -qm "docs: dirty doc, unstaged config downgrade" > a.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "unstaged config downgrade must NOT bypass body_lint: enforce: $(cat "$d/a.out")"
  grep -qiF "body-lint" "$d/a.out" || log_fail "abort must name body-lint: $(cat "$d/a.out")"
  (cd "$d" && git reset -q && rm -f docs/specs/SPEC-7902-dirty.md)

  # (b) close_gate: the same downgrade vector on the close-gate key (worktree
  # config silently DROPS the key; index/HEAD still say enforce).
  printf 'body_lint: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  sed -i.bak 's/^status: implementing/status: done/' "$d/docs/specs/SPEC-7901-flip.md" && rm -f "$d/docs/specs/SPEC-7901-flip.md.bak"
  (cd "$d" && git add docs/specs/SPEC-7901-flip.md)
  ec=0
  (cd "$d" && git commit -qm "docs: done-flip, unstaged close_gate downgrade" > b.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "unstaged config downgrade must NOT bypass close_gate: enforce: $(cat "$d/b.out")"
  grep -qiF "close-gate" "$d/b.out" || log_fail "abort must name close-gate: $(cat "$d/b.out")"
  (cd "$d" && git reset -q && git checkout -q -- docs/specs/SPEC-7901-flip.md docs/ai/docs-audit.yaml)

  # (c) positive control: a STAGED downgrade governs (the index blob is what commits).
  printf 'close_gate: report-only\nbody_lint: report-only\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7903-dirty.md" <<'MD'
---
id: SPEC-7903
type: spec
status: draft
links:
  pr: []
---
# Dirty body

</content>
MD
  (cd "$d" && git add docs/ai/docs-audit.yaml docs/specs/SPEC-7903-dirty.md)
  ec=0
  (cd "$d" && git commit -qm "docs: staged downgrade governs" > c.out 2>&1) || ec=$?
  [[ "$ec" == 0 ]] || log_fail "a STAGED report-only config must warn, not block (got $ec): $(cat "$d/c.out")"
  grep -qiF "body-lint" "$d/c.out" || log_fail "report-only path must still print the warning: $(cat "$d/c.out")"

  # (d) fresh-repo fallback: config never committed/staged -> the worktree copy
  # is still honored (last-resort read).
  local d2; d2="$(setup_spec0011_hook_repo cfgfresh)"
  printf 'body_lint: enforce\n' > "$d2/docs/ai/docs-audit.yaml"
  cat > "$d2/docs/specs/SPEC-7904-dirty.md" <<'MD'
---
id: SPEC-7904
type: spec
status: draft
links:
  pr: []
---
# Dirty body

</content>
MD
  (cd "$d2" && git add docs/specs/SPEC-7904-dirty.md)
  ec=0
  (cd "$d2" && git commit -qm "docs: fresh-repo untracked enforce config" > d.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "untracked worktree config (fresh repo) must still enforce: $(cat "$d2/d.out")"
  rm -rf "$d" "$d2"
  log_pass "Hook gate modes read from the staged/HEAD config; worktree only as fresh-repo fallback (TEST-019)"
}

test_change0007_hook_space_filename() {  # TEST-020 / Spec-AC-01 (review-20260704T110648Z W2)
  log_info "Test: a staged doc with a SPACE in its name cannot silently bypass enforce (body lint + close gate) (TEST-020)..."
  local d; d="$(setup_spec0011_hook_repo spacename)"
  printf 'close_gate: enforce\nbody_lint: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/specs/SPEC-7912 flip.md" <<'MD'
---
id: SPEC-7912
type: spec
status: implementing
links:
  pr: []
---
# Flip candidate 7912 (space in filename)

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | implementing | —        | —         | —     |
MD
  (cd "$d" && git add docs/ai/docs-audit.yaml "docs/specs/SPEC-7912 flip.md" \
    && git commit -qm "docs: baseline enforce config + space-named implementing spec" >/dev/null) \
    || log_fail "baseline commit failed"

  # (a) body lint: a dirty doc whose name contains a space must be BLOCKED,
  # not word-split into two nonexistent paths and silently skipped.
  cat > "$d/docs/specs/SPEC-7911 draft.md" <<'MD'
---
id: SPEC-7911
type: spec
status: draft
links:
  pr: []
---
# Dirty doc with a space in its filename

</content>
MD
  (cd "$d" && git add "docs/specs/SPEC-7911 draft.md")
  local ec=0
  (cd "$d" && git commit -qm "docs: dirty space-named doc" > a.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "body_lint: enforce must block a dirty staged doc even with a space in its name (silent gate bypass): $(cat "$d/a.out")"
  grep -qiF "body-lint" "$d/a.out" || log_fail "abort must name body-lint: $(cat "$d/a.out")"
  (cd "$d" && git reset -q && rm -f "docs/specs/SPEC-7911 draft.md")

  # (b) close gate: an unreconciled done-flip of the space-named spec must be BLOCKED.
  sed -i.bak 's/^status: implementing/status: done/' "$d/docs/specs/SPEC-7912 flip.md" && rm -f "$d/docs/specs/SPEC-7912 flip.md.bak"
  (cd "$d" && git add "docs/specs/SPEC-7912 flip.md")
  ec=0
  (cd "$d" && git commit -qm "docs: done-flip space-named spec" > b.out 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "close_gate: enforce must block an unreconciled done-flip even with a space in the filename: $(cat "$d/b.out")"
  grep -qiF "close-gate" "$d/b.out" || log_fail "abort must name close-gate: $(cat "$d/b.out")"
  rm -rf "$d"
  log_pass "Space-named staged docs are gated, not silently skipped (TEST-020)"
}

test_change0007_lint_span_edges() {  # TEST-021 / Spec-AC-01 (review-20260704T110648Z W3)
  log_info "Test: multi-line inline span masked; line-initial \`\`\` x \`\`\` is a span, not a fence — no swallow (TEST-021)..."
  local d; d="$(setup_iso_repo c7-spanedges)"
  # (a) a CommonMark inline code span crossing line breaks: its interior must
  # never be flagged (D1: content inside inline code is NEVER flagged).
  cat > "$d/docs/specs/SPEC-7920-mlspan.md" <<'MD'
---
id: SPEC-7920
type: spec
status: draft
links:
  pr: []
---
# Multi-line inline code span

Prose with `code that
</content>
keeps going` and ends clean.
MD
  # (b) a line-initial 3-run code span that CLOSES on the same line is an inline
  # span (backtick fence info strings may not contain backticks), NOT a fence
  # open — no spurious unbalanced-fence, and the rest of the doc is NOT swallowed.
  cat > "$d/docs/specs/SPEC-7921-inlinefence.md" <<'MD'
---
id: SPEC-7921
type: spec
status: draft
links:
  pr: []
---
# Line-initial two-run code span

``` x ```
prose after the span
</content>
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --lint-body > lint.log 2>&1) \
    || log_fail "--lint-body must exit 0 without --strict: $(cat "$d/lint.log")"
  grep -qF "unbalanced-fence" "$d/lint.log" \
    && log_fail "\`\`\` x \`\`\` on one line is an inline span, not a fence open: $(cat "$d/lint.log")"
  grep -qF "SPEC-7920-mlspan.md" "$d/lint.log" \
    && log_fail "no finding may fire inside a multi-line inline code span: $(cat "$d/lint.log")"
  grep -qE 'SPEC-7921-inlinefence\.md:12 .*stray-tool-markup' "$d/lint.log" \
    || log_fail "the real </content> AFTER the inline span must still be flagged (no false-negative cascade): $(cat "$d/lint.log")"
  grep -qE '^### Body lint: 1' "$d/lint.log" \
    || log_fail "exactly ONE finding expected across both fixtures: $(cat "$d/lint.log")"
  rm -rf "$d"
  log_pass "Multi-line spans masked; same-line backtick-run pairs are spans, not fences (TEST-021)"
}

# --- CHANGE-0012 / spec-slug-refs-across-tooling: DRAFT docs in the scan set +
# --- two-pass gate resolution (frontmatter-id, then display-id; ambiguity = exit 2)

# Write a governed doc with frontmatter id/status and a one-row AC table.
# Args: $1 = path, $2 = frontmatter id, $3 = AC row status (e.g. "done" or
# "planned"), $4 = Spec-AC label (default Spec-AC-01)
write_c12_doc() {
  local p="$1" id="$2" acstatus="$3" acid="${4:-Spec-AC-01}" evidence="a1b2c3d"
  [[ "$3" == "done" ]] || evidence="—"
  cat > "$p" <<MD
---
id: $id
type: spec
number: null
status: draft
links:
  pr: []
---
# Fixture doc $id

## Acceptance Criteria Status

| Spec-AC    | Description | Status    | Evidence  | Review-By | Notes |
|------------|-------------|-----------|-----------|-----------|-------|
| $acid | first       | $acstatus | $evidence | —         | —     |
MD
}

test_change0012_gate_slug_draft() {  # CHANGE-0012 TEST-006 / Spec-AC-02
  log_info "Test: --gate <slug> resolves a <TYPE>-DRAFT-<slug>.md doc by frontmatter id and EVALUATES the gate (CHANGE-0012 TEST-006)..."
  local d ec
  d="$(setup_iso_repo c12-gate-slug)"
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-my-widget.md" my-widget done
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate my-widget > gate-pass.log 2>&1) \
    || log_fail "--gate my-widget must exit 0 for a reconciled DRAFT (RED today: exit 2): $(cat "$d/gate-pass.log")"
  assert_contains "$d/gate-pass.log" "GATE PASS"
  # Unreconciled row: exit 1 (evaluation, not mere resolution — never 2).
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-my-widget.md" my-widget planned
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate my-widget > gate-fail.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--gate my-widget must exit 1 for a non-terminal row (RED today: exit 2; got $ec): $(cat "$d/gate-fail.log")"
  grep -qiF "non-terminal" "$d/gate-fail.log" || log_fail "gate reason must say non-terminal"
  log_pass "--gate <slug> resolves the DRAFT by frontmatter id and evaluates content: 0 reconciled / 1 unreconciled (CHANGE-0012 TEST-006)"
}

test_change0012_draft_scanned_nonvacuous() {  # CHANGE-0012 TEST-007 / Spec-AC-05
  log_info "Test: --check --strict --path <DRAFT> scans 1 doc (non-vacuous) and hard-fails a schema-violating DRAFT (CHANGE-0012 TEST-007)..."
  local d ec
  d="$(setup_iso_repo c12-scan)"
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-my-widget.md" my-widget done
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-DRAFT-my-widget.md > scan-ok.log 2>&1) \
    || log_fail "--check --strict on a compliant DRAFT must exit 0: $(cat "$d/scan-ok.log")"
  grep -qF "Scanned: 1 docs" "$d/scan-ok.log" \
    || log_fail "the DRAFT must actually be SCANNED (RED today: 'Scanned: 0 docs' vacuous pass): $(head -3 "$d/scan-ok.log")"
  # Schema-violating DRAFT (frontmatter missing status): hard fail, not vacuous pass.
  cat > "$d/docs/specs/SPEC-DRAFT-broken.md" <<'MD'
---
id: broken-draft
type: spec
number: null
---
# DRAFT missing status
MD
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-DRAFT-broken.md > scan-bad.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--check --strict on a schema-violating DRAFT must exit 1 (RED today: vacuous exit 0; got $ec): $(cat "$d/scan-bad.log")"
  grep -qF "Scanned: 1 docs" "$d/scan-bad.log" || log_fail "the violating DRAFT must be scanned, not skipped"
  grep -qF "SPEC-DRAFT-broken.md" "$d/scan-bad.log" || log_fail "the violation must name the DRAFT file"
  log_pass "DRAFT basenames are first-class audit citizens: scanned non-vacuously, violations hard-fail (CHANGE-0012 TEST-007)"
}

test_change0012_gate_resolution_order() {  # CHANGE-0012 TEST-008 / Spec-AC-06
  log_info "Test: gate resolution order — frontmatter-id pass first, filename display-id pass second (CHANGE-0012 TEST-008)..."
  local d ec
  d="$(setup_iso_repo c12-order)"
  # A: DRAFT whose frontmatter id LOOKS like a lowercased display id; reconciled (gates PASS).
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-order-a.md" spec-0042 done
  # B: numbered file SPEC-0042-widget.md with an UNRELATED frontmatter id; non-terminal row Spec-AC-77 (gates FAIL).
  write_c12_doc "$d/docs/specs/SPEC-0042-widget.md" widget-b planned Spec-AC-77
  # --gate spec-0042 resolves A via the FRONTMATTER pass only (exit 0).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate spec-0042 > order-a.log 2>&1) \
    || log_fail "--gate spec-0042 must gate doc A via the frontmatter pass (RED today: exit 2): $(cat "$d/order-a.log")"
  assert_contains "$d/order-a.log" "GATE PASS"
  # --gate SPEC-0042 resolves B via the DISPLAY pass (exit 1, names B's row).
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-0042 > order-b.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "--gate SPEC-0042 must gate doc B via the display pass (got $ec): $(cat "$d/order-b.log")"
  grep -qF "Spec-AC-77" "$d/order-b.log" || log_fail "the display pass must have gated doc B (expected its Spec-AC-77 reason)"
  log_pass "Frontmatter-id pass wins first; filename display-id pass second; shapes never cross (CHANGE-0012 TEST-008)"
}

test_change0012_gate_ambiguous_id() {  # CHANGE-0012 TEST-009 / Spec-AC-06
  log_info "Test: two docs sharing a frontmatter id — --gate exits 2 listing BOTH candidates (CHANGE-0012 TEST-009)..."
  local d ec
  d="$(setup_iso_repo c12-dup)"
  mkdir -p "$d/docs/issues"
  # docs/issues/ sorts before docs/specs/: pre-fix first-file-wins silently
  # gates the RECONCILED issue doc (exit 0) and never sees the failing spec.
  write_c12_doc "$d/docs/issues/CHANGE-0099-dup.md" dup-target done
  write_c12_doc "$d/docs/specs/SPEC-0098-dup.md" dup-target planned
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate dup-target > dup.log 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--gate on a duplicated id must exit 2 fail-closed (RED today: silent first-file-wins exit 0; got $ec): $(cat "$d/dup.log")"
  assert_contains "$d/dup.log" "docs/issues/CHANGE-0099-dup.md"
  assert_contains "$d/dup.log" "docs/specs/SPEC-0098-dup.md"
  log_pass "Duplicate-id gate fails loud (exit 2) listing every candidate path — never directory-sort-order resolution (CHANGE-0012 TEST-009)"
}

test_change0012_allocation_durability() {  # CHANGE-0012 TEST-010 / Spec-AC-07 (Seam 3)
  log_info "Test: after the simulated merge-time rename the SAME slug gates the SAME doc; slug-keyed STATE needs no migration (CHANGE-0012 TEST-010)..."
  local d ec
  d="$(setup_iso_repo c12-alloc)"
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-my-widget.md" my-widget done
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate my-widget > alloc-before.log 2>&1) \
    || log_fail "--gate my-widget must pass on the DRAFT side: $(cat "$d/alloc-before.log")"
  # Slug-keyed STATE written by the REAL state CLI on the DRAFT side.
  cat > "$d/state.yaml" <<'YAML'
project_status: active
updated_at_utc: 2026-07-01T00:00:00Z
YAML
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$d/state.yaml" set-phase --ref my-widget \
    --phase implementation --status in_progress --spec-path docs/specs/SPEC-DRAFT-my-widget.md > "$d/st1.log" 2>&1) \
    || log_fail "slug set-phase on the DRAFT side must exit 0: $(cat "$d/st1.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$d/state.yaml" append-run --ref my-widget \
    --role Planning --model claude-test --started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$d/st2.log" 2>&1) \
    || log_fail "slug append-run on the DRAFT side must exit 0: $(cat "$d/st2.log")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/state.yaml" > "$d/ck1.log" 2>&1) \
    || log_fail "check-state must pass on the DRAFT side: $(cat "$d/ck1.log")"
  # Simulated allocator rename (SPEC-0015 D2): DRAFT -> numbered file, number
  # stamped, frontmatter id UNCHANGED. STATE is NOT touched (no migration).
  awk '{ if ($0 == "number: null") print "number: 7"; else print }' \
    "$d/docs/specs/SPEC-DRAFT-my-widget.md" > "$d/docs/specs/SPEC-0007-my-widget.md"
  rm "$d/docs/specs/SPEC-DRAFT-my-widget.md"
  grep -qE '^id: my-widget$' "$d/docs/specs/SPEC-0007-my-widget.md" \
    || log_fail "fixture guard: frontmatter id must survive the rename unchanged"
  # The SAME slug gates the SAME doc with the SAME verdict (frontmatter pass).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate my-widget > alloc-after.log 2>&1) \
    || log_fail "--gate my-widget must still pass after the rename (slug is the durable PK): $(cat "$d/alloc-after.log")"
  assert_contains "$d/alloc-after.log" "GATE PASS"
  # The derived display id ALSO resolves now (display pass; no ambiguity).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-0007 > alloc-display.log 2>&1) \
    || log_fail "--gate SPEC-0007 must resolve the renamed doc via the display pass: $(cat "$d/alloc-display.log")"
  # Slug-keyed STATE still validates BYTE-UNCHANGED — no migration required.
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/state.yaml" > "$d/ck2.log" 2>&1) \
    || log_fail "check-state must still pass after the rename with the STATE untouched: $(cat "$d/ck2.log")"
  log_pass "Slug ref resolves the same doc before and after allocation; slug-keyed STATE valid with zero migration (CHANGE-0012 TEST-010)"
}

test_change0012_regression() {  # CHANGE-0012 TEST-011 / Spec-AC-04 (Seam 2)
  log_info "Test: numbered --gate/--gate-file unchanged; real-repo strict audit exit 0 with DRAFT docs newly visible (CHANGE-0012 TEST-011)..."
  local d ec
  d="$(setup_iso_repo c12-reg)"
  write_c12_doc "$d/docs/specs/SPEC-0042-widget.md" SPEC-0042 done
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-0042 > reg-gate.log 2>&1) \
    || log_fail "--gate on an existing numbered doc must stay exit 0: $(cat "$d/reg-gate.log")"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate-file docs/specs/SPEC-0042-widget.md > reg-gatefile.log 2>&1) \
    || log_fail "--gate-file must stay exit 0: $(cat "$d/reg-gatefile.log")"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-9999 > reg-unknown.log 2>&1) || ec=$?
  [[ "$ec" == 2 ]] || log_fail "--gate on an unresolved id must stay exit 2 (got $ec)"
  assert_contains "$d/reg-unknown.log" "no scanned doc resolves"
  # Real repo: the scan widening makes DRAFT docs visible WITHOUT introducing
  # new orphans/violations. (Verdict text may carry pre-existing report-only
  # drift — e.g. RES-0001 — so assert the hard-gate signals, not CLEAN.)
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/c12-repo-audit.log" 2>&1) \
    || log_fail "real-repo --check --strict must stay exit 0 after the scan widening: $(tail -5 "$TEST_DIR/c12-repo-audit.log")"
  assert_contains "$TEST_DIR/c12-repo-audit.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/c12-repo-audit.log" "CHECK FAILED"
  # A DRAFT spec is scanned non-vacuously. CHANGE-0009 D10 (TEST-019): the
  # stanza builds its OWN DRAFT fixture inside the isolated repo — it must
  # never depend on a repo DRAFT file, because every repo DRAFT is destined to
  # be renamed away at number allocation (the original hardcoded slug-refs
  # draft path was deleted exactly so, aborting this suite). The regression
  # intent (DRAFT docs join the scan set; --path <DRAFT> is non-vacuous) is
  # preserved unchanged. NB: this comment deliberately avoids the literal
  # deleted filename — the self-containment grep below would match it.
  write_c12_doc "$d/docs/specs/SPEC-DRAFT-reg-scan-fixture.md" reg-scan-fixture done
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event \
      --path docs/specs/SPEC-DRAFT-reg-scan-fixture.md > reg-draft.log 2>&1) \
    || log_fail "strict check on the constructed DRAFT fixture must exit 0: $(cat "$d/reg-draft.log")"
  grep -qF "Scanned: 1 docs" "$d/reg-draft.log" \
    || log_fail "the constructed DRAFT fixture must be scanned non-vacuously (Scanned: 1 docs): $(head -3 "$d/reg-draft.log")"
  # Self-containment guard: no REPO SPEC-DRAFT path may be hardcoded in this
  # suite (fixture DRAFTs live under the iso repos only). Runs against the
  # absolute SUITE_FILE (review W1: relative BASH_SOURCE broke after cd, and
  # grep's exit-2 error slipped through the '&&' errexit exemption unnoticed).
  [[ -r "$SUITE_FILE" ]] \
    || log_fail "self-containment guard cannot read its own suite file: $SUITE_FILE"
  grep -n 'PROJECT_ROOT[^)]*SPEC-DRAFT' "$SUITE_FILE" \
    && log_fail "suite must not reference a repo SPEC-DRAFT path via PROJECT_ROOT"
  grep -qF "SPEC-DRAFT-slug-refs""-across-tooling" "$SUITE_FILE" \
    && log_fail "the deleted repo DRAFT path must not reappear in this suite"
  log_pass "Numbered gate paths byte-identical; real-repo strict audit exit 0; DRAFT scan proven on a self-built fixture (CHANGE-0012 TEST-011 / CHANGE-0009 TEST-019)"
}

# --- CHANGE l1-close-gate (spec-l1-close-gate): level-aware close gate + drift ---
# SPEC-0030 defined L0/L1 lean specs (lean AC table + `Ceremony justification: `
# line) but gateContent and the done-drift check still demanded the canonical
# AC Status table unconditionally — so no lean spec could ever close (first
# live L1 validation, 2026-07-16). These stanzas freeze the level-aware rules.

# write_l1gate_spec <path> <id> <status> <ceremony-frontmatter-line|-> \
#                   <justification: yes|no> <row-status> <table: lean|canonical|none>
write_l1gate_spec() {
  local p="$1" id="$2" status="$3" cl="$4" just="$5" rowst="$6" table="$7"
  {
    echo '---'
    echo "id: $id"
    echo 'type: spec'
    echo "status: $status"
    [[ "$cl" != "-" ]] && echo "$cl"
    echo 'links:'
    echo '  pr: []'
    echo '---'
    echo "# Fixture spec $id"
    echo ''
    if [[ "$just" == "yes" ]]; then
      echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'
      echo ''
    fi
    if [[ "$table" == "lean" ]]; then
      echo '## Acceptance Criteria'
      echo ''
      echo '| Spec-AC    | Requirement          | Status  |'
      echo '|------------|----------------------|---------|'
      echo "| Spec-AC-01 | does the small thing | $rowst |"
    elif [[ "$table" == "canonical" ]]; then
      echo '## Acceptance Criteria Status'
      echo ''
      echo '| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |'
      echo '|------------|-------------|---------|----------|-----------|-------|'
      echo "| Spec-AC-01 | first       | $rowst | a1b2c3d  | TDD       | —     |"
    fi
  } > "$p"
}

test_l1gate_lean_gate_pass() {  # spec-l1-close-gate TEST-001 / Spec-AC-01
  log_info "Test: L1 lean spec (Spec-AC+Status + justification) passes --gate/--gate-file; non-terminal lean row fails naming it (TEST-001)..."
  local d ec
  d="$(setup_iso_repo l1gate-pass)"
  write_l1gate_spec "$d/docs/specs/SPEC-7101-lean.md" SPEC-7101 draft 'ceremony_level: 1' yes done lean
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7101 > g.log 2>&1) \
    || log_fail "L1 lean spec must pass --gate (RED pre-fix: missing AC Status table): $(cat "$d/g.log")"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate-file docs/specs/SPEC-7101-lean.md > gf.log 2>&1) \
    || log_fail "L1 lean spec must pass --gate-file: $(cat "$d/gf.log")"
  # level 0 gets the same lean acceptance as level 1
  write_l1gate_spec "$d/docs/specs/SPEC-7102-lean0.md" SPEC-7102 draft 'ceremony_level: 0' yes done lean
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7102 > g0.log 2>&1) \
    || log_fail "L0 lean spec must pass --gate: $(cat "$d/g0.log")"
  # non-terminal lean row still blocks the close, naming the row
  write_l1gate_spec "$d/docs/specs/SPEC-7103-open.md" SPEC-7103 draft 'ceremony_level: 1' yes implementing lean
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7103 > gnt.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "non-terminal lean row must fail the gate (got $ec): $(cat "$d/gnt.log")"
  grep -qF "Spec-AC-01" "$d/gnt.log" || log_fail "lean gate reason must name Spec-AC-01"
  grep -qiF "non-terminal" "$d/gnt.log" || log_fail "lean gate reason must say non-terminal"
  rm -rf "$d"
  log_pass "L1/L0 lean specs pass the gate; non-terminal lean rows fail naming the row"
}

test_l1gate_missing_justification() {  # spec-l1-close-gate TEST-002 / Spec-AC-01
  log_info "Test: L1 lean spec WITHOUT the justification line fails the gate naming it — and ONLY it (TEST-002)..."
  local d ec
  d="$(setup_iso_repo l1gate-nojust)"
  write_l1gate_spec "$d/docs/specs/SPEC-7111-nojust.md" SPEC-7111 draft 'ceremony_level: 1' no done lean
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7111 > g.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "L1 without justification must fail the gate (got $ec): $(cat "$d/g.log")"
  grep -qF "Ceremony justification" "$d/g.log" \
    || log_fail "gate reason must name the missing Ceremony justification line"
  # RED pre-fix: the gate ALSO complained 'missing AC Status table' — the lean
  # table must now satisfy the structural check, leaving justification the only gap.
  assert_not_contains "$d/g.log" "missing AC Status table"
  rm -rf "$d"
  log_pass "Missing justification is the single named gate failure for an L1 lean spec"
}

test_l1gate_done_lean_clean() {  # spec-l1-close-gate TEST-003 / Spec-AC-01
  log_info "Test: done L1 lean spec is aligned/CLEAN under --check --strict; dropping justification flips to probable-partial (TEST-003)..."
  local d
  d="$(setup_iso_repo l1gate-done)"
  write_l1gate_spec "$d/docs/specs/SPEC-7115-done.md" SPEC-7115 done 'ceremony_level: 1' yes done lean
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > chk.log 2>&1) \
    || log_fail "strict check must exit 0 for a done L1 lean spec: $(cat "$d/chk.log")"
  assert_contains "$d/chk.log" "Verdict: CLEAN"
  assert_not_contains "$d/chk.log" "probable-partial"
  # mutation control: without the justification line the done lean spec drifts
  write_l1gate_spec "$d/docs/specs/SPEC-7115-done.md" SPEC-7115 done 'ceremony_level: 1' no done lean
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > chk2.log 2>&1) || true
  assert_contains "$d/chk2.log" "NEEDS-TRIAGE"
  assert_contains "$d/chk2.log" "probable-partial"
  rm -rf "$d"
  log_pass "Done L1 lean spec stays CLEAN; justification removal drifts probable-partial"
}

test_l1gate_l2_regression() {  # spec-l1-close-gate TEST-004 / Spec-AC-02
  log_info "Test: L2-explicit and absent-level specs keep canonical requirements byte-for-byte (lean table alone still fails) (TEST-004)..."
  local d ec
  d="$(setup_iso_repo l1gate-l2)"
  write_l1gate_spec "$d/docs/specs/SPEC-7121-l2lean.md" SPEC-7121 draft 'ceremony_level: 2' yes done lean
  write_l1gate_spec "$d/docs/specs/SPEC-7122-nolevel.md" SPEC-7122 draft - yes done lean
  for id in SPEC-7121 SPEC-7122; do
    ec=0
    (cd "$d" && node .aai/scripts/docs-audit.mjs --gate "$id" > "g-$id.log" 2>&1) || ec=$?
    [[ "$ec" == 1 ]] || log_fail "$id (non-lean-eligible) with only a lean table must fail the gate (got $ec)"
    grep -qF "missing AC Status table" "$d/g-$id.log" \
      || log_fail "$id gate reason must stay the canonical 'missing AC Status table'"
  done
  # done + strict: both drift probable-partial exactly as before
  write_l1gate_spec "$d/docs/specs/SPEC-7121-l2lean.md" SPEC-7121 done 'ceremony_level: 2' yes done lean
  write_l1gate_spec "$d/docs/specs/SPEC-7122-nolevel.md" SPEC-7122 done - yes done lean
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > chk.log 2>&1) || true
  assert_contains "$d/chk.log" "probable-partial"
  # canonical L2 done spec still passes the gate (regression the other way)
  write_l1gate_spec "$d/docs/specs/SPEC-7123-canon.md" SPEC-7123 done 'ceremony_level: 2' no done canonical
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7123 > gcanon.log 2>&1) \
    || log_fail "canonical L2 done spec must keep passing the gate: $(cat "$d/gcanon.log")"
  rm -rf "$d"
  log_pass "L2/absent keep canonical gate + drift behavior; canonical table still passes"
}

test_l1gate_garbage_level_fail_closed() {  # spec-l1-close-gate TEST-005 / Spec-AC-02
  log_info "Test: garbage ceremony_level fails CLOSED — schema-invalid reason AND full canonical requirements (TEST-005)..."
  local d ec
  d="$(setup_iso_repo l1gate-garbage)"
  write_l1gate_spec "$d/docs/specs/SPEC-7131-banana.md" SPEC-7131 draft 'ceremony_level: banana' yes done lean
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7131 > g.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "garbage ceremony_level must fail the gate (got $ec): $(cat "$d/g.log")"
  grep -qF "schema-invalid ceremony_level" "$d/g.log" \
    || log_fail "gate must report the schema-invalid ceremony_level"
  grep -qF "missing AC Status table" "$d/g.log" \
    || log_fail "garbage level must NOT unlock the lean shape (fail-closed to canonical requirements)"
  rm -rf "$d"
  log_pass "Garbage ceremony_level fails closed: reported invalid + canonical table still required"
}

test_l1gate_pipe_drop_reconciled() {  # spec-l1-close-gate TEST-007 / Spec-AC-04
  log_info "Test: a lean row broken by a literal pipe is silently dropped by the parser — the gate must RECONCILE declared-vs-parsed ids and FAIL naming it, not PASS on the survivors, incl. an INDENTED broken row (TEST-007)..."
  local d ec
  d="$(setup_iso_repo l1gate-pipedrop)"
  # Spec-AC-02's cell carries a literal '|', so the naive pipe-split yields a
  # phantom cell, the row fails the column-count check, and parseLeanAcTable
  # DROPS it. Pre-fix the gate validated only Spec-AC-01 (terminal) and PASSED.
  {
    echo '---'; echo 'id: SPEC-7141'; echo 'type: spec'; echo 'status: draft'
    echo 'ceremony_level: 1'; echo 'links:'; echo '  pr: []'; echo '---'
    echo '# Fixture spec SPEC-7141'; echo ''
    echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'; echo ''
    echo '## Acceptance Criteria'; echo ''
    echo '| Spec-AC    | Requirement                 | Status |'
    echo '|------------|-----------------------------|--------|'
    echo '| Spec-AC-01 | plain requirement no pipes  | done   |'
    echo '| Spec-AC-02 | value is a | inside the cell | done   |'
  } > "$d/docs/specs/SPEC-7141-pipedrop.md"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7141 > g.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "pipe-dropped declared row must FAIL the gate, not pass on survivors (got $ec): $(cat "$d/g.log")"
  grep -qF "Spec-AC-02" "$d/g.log" || log_fail "gate reason must NAME the unparseable declared row Spec-AC-02: $(cat "$d/g.log")"
  grep -qiF "did not parse" "$d/g.log" || log_fail "gate reason must explain the row did not parse: $(cat "$d/g.log")"
  # negative control: escaping the pipe as \| does NOT rescue the author (the
  # parser does not unescape) — the gate must STILL fail, steering to rewording.
  sed 's/a | inside/a \\| inside/' "$d/docs/specs/SPEC-7141-pipedrop.md" > "$d/docs/specs/SPEC-7142-esc.md"
  sed -i.bak 's/SPEC-7141/SPEC-7142/' "$d/docs/specs/SPEC-7142-esc.md" && rm -f "$d/docs/specs/SPEC-7142-esc.md.bak"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7142 > g2.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "escaped-pipe row must STILL fail (parser does not unescape) (got $ec): $(cat "$d/g2.log")"
  grep -qF "Spec-AC-02" "$d/g2.log" || log_fail "escaped-pipe variant must also name Spec-AC-02"
  # Review F1 regression: an INDENTED broken row. parseLeanAcTable accepts rows
  # via l.trim().startsWith('|') (1-3 leading spaces are valid markdown), so the
  # reconciler MUST use the same whitespace tolerance — a column-0-anchored
  # recovery would miss this and let the gate falsely PASS.
  {
    echo '---'; echo 'id: SPEC-7143'; echo 'type: spec'; echo 'status: draft'
    echo 'ceremony_level: 1'; echo 'links:'; echo '  pr: []'; echo '---'
    echo '# Fixture spec SPEC-7143'; echo ''
    echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'; echo ''
    echo '## Acceptance Criteria'; echo ''
    echo '| Spec-AC    | Requirement                | Status |'
    echo '|------------|----------------------------|--------|'
    echo '| Spec-AC-01 | plain requirement no pipes | done   |'
    echo '  | Spec-AC-02 | indented with a | pipe   | done   |'
  } > "$d/docs/specs/SPEC-7143-indent.md"
  ec=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7143 > g3.log 2>&1) || ec=$?
  [[ "$ec" == 1 ]] || log_fail "INDENTED pipe-dropped row must FAIL the gate, not pass (got $ec): $(cat "$d/g3.log")"
  grep -qF "Spec-AC-02" "$d/g3.log" || log_fail "indented variant must also name Spec-AC-02: $(cat "$d/g3.log")"
  # review re-verify nit: a well-formed but SUFFIXED id cell parses cleanly and
  # must NOT be misreported as a pipe-drop (declaredIds vs stored-id mismatch).
  {
    echo '---'; echo 'id: SPEC-7144'; echo 'type: spec'; echo 'status: draft'
    echo 'ceremony_level: 1'; echo 'links:'; echo '  pr: []'; echo '---'
    echo '# Fixture spec SPEC-7144'; echo ''
    echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'; echo ''
    echo '## Acceptance Criteria'; echo ''
    echo '| Spec-AC          | Requirement                | Status |'
    echo '|------------------|----------------------------|--------|'
    echo '| Spec-AC-01       | plain requirement no pipes | done   |'
    echo '| Spec-AC-02 (opt) | suffixed id, clean row     | done   |'
  } > "$d/docs/specs/SPEC-7144-suffix.md"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --gate SPEC-7144 > g4.log 2>&1) || true
  if grep -qF "did not parse" "$d/g4.log"; then log_fail "suffixed-but-parseable id cell must NOT trip the pipe-drop message: $(cat "$d/g4.log")"; fi
  rm -rf "$d"
  log_pass "Pipe-broken declared lean row is reconciled and fails the gate naming it (plain + escaped + indented)"
}

test_l1gate_done_drift_pipe_drop() {  # spec-l1-close-gate TEST-008 / Spec-AC-04
  log_info "Test: a DONE L1 lean spec with a pipe-dropped NON-TERMINAL declared row must NOT report CLEAN — the done-drift check mirrors the gate (D3) and flags probable-false-done naming it (TEST-008)..."
  local d
  d="$(setup_iso_repo l1gate-driftdrop)"
  # Spec-AC-02 is dropped by the parser (literal pipe) AND its status is
  # non-terminal ('implementing'). Pre-fix the drift check saw only the terminal
  # Spec-AC-01 and reported CLEAN — the SPEC-0012 invisibility on the close path.
  {
    echo '---'; echo 'id: SPEC-7151'; echo 'type: spec'; echo 'status: done'
    echo 'ceremony_level: 1'; echo 'links:'; echo '  pr: []'; echo '---'
    echo '# Fixture spec SPEC-7151'; echo ''
    echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'; echo ''
    echo '## Acceptance Criteria'; echo ''
    echo '| Spec-AC    | Requirement                | Status       |'
    echo '|------------|----------------------------|--------------|'
    echo '| Spec-AC-01 | plain requirement no pipes | done         |'
    echo '| Spec-AC-02 | value is a | in the cell   | implementing |'
  } > "$d/docs/specs/SPEC-7151-driftdrop.md"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --no-event > chk.log 2>&1) || true
  assert_contains "$d/chk.log" "NEEDS-TRIAGE"
  assert_contains "$d/chk.log" "probable-false-done"
  grep -qF "Spec-AC-02" "$d/chk.log" || log_fail "drift reason must NAME the invisible non-terminal row Spec-AC-02: $(cat "$d/chk.log")"
  grep -qiF "unparseable" "$d/chk.log" || log_fail "drift reason must flag the row unparseable: $(cat "$d/chk.log")"
  # negative control: reword the pipe out AND flip status to done -> CLEAN/aligned
  {
    echo '---'; echo 'id: SPEC-7152'; echo 'type: spec'; echo 'status: done'
    echo 'ceremony_level: 1'; echo 'links:'; echo '  pr: []'; echo '---'
    echo '# Fixture spec SPEC-7152'; echo ''
    echo 'Ceremony justification: S-sized single-surface fix (one script, one test).'; echo ''
    echo '## Acceptance Criteria'; echo ''
    echo '| Spec-AC    | Requirement                | Status |'
    echo '|------------|----------------------------|--------|'
    echo '| Spec-AC-01 | plain requirement no pipes | done   |'
    echo '| Spec-AC-02 | value is safe no pipes here | done  |'
  } > "$d/docs/specs/SPEC-7151-driftdrop.md"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > chk2.log 2>&1) \
    || log_fail "reworked done lean spec must be CLEAN under strict: $(cat "$d/chk2.log")"
  assert_contains "$d/chk2.log" "CLEAN"
  rm -rf "$d"
  log_pass "Done-drift check mirrors the gate: pipe-dropped non-terminal row flips probable-false-done naming it"
}

# --- RFC-0011 (delta-spec lifecycle) D3: canonical-provenance drift check ------

# Write a canonical doc for $2 (domain) into repo dir $1 with the requirement
# blocks piped on stdin (heading/SHALL/Provenance authored by the caller).
write_canonical_doc() {
  local d="$1" domain="$2"
  mkdir -p "$d/docs/canonical"
  {
    printf -- '---\nid: CANON-%s\ntype: canonical\ndomain: %s\nstatus: accepted\nsources:\n  - docs/_archive/specs/SPEC-old.md\n---\n\n' "$domain" "$domain"
    printf '# Canonical: %s\n\n## Overview / Intent\n\nIntent.\n\n## Requirements\n\n' "$domain"
    cat
    printf '\n## UI\n\nUI.\n'
  } > "$d/docs/canonical/$domain.md"
}

test_delta3_provenance_drift() {  # spec-delta-stage-3 TEST-004 / Spec-AC-02
  local dash="—"
  log_info "Test: docs-audit --check flags untraced/broken canonical provenance; fully-traced is CLEAN (TEST-004)..."

  # (a) drift repo: one untraced (Provenance —), one broken (names a missing
  # spec), one traced (names a scanned spec) requirement.
  local d; d="$(setup_iso_repo prov-drift)"
  cat > "$d/docs/specs/SPEC-0031-trace-target.md" <<'MD'
---
id: SPEC-0031
type: spec
status: accepted
links:
  pr: []
---
# A scanned spec the traced requirement resolves to
MD
  write_canonical_doc "$d" oauth2-login <<MD
### REQ-OAUTH2_LOGIN-001 ${dash} Untraced
The system SHALL do the untraced thing.

Provenance: —

### REQ-OAUTH2_LOGIN-002 ${dash} Broken
The system SHALL do the broken thing.

Provenance: SPEC-9999

### REQ-OAUTH2_LOGIN-003 ${dash} Traced
The system SHALL do the traced thing.

Provenance: SPEC-0031
MD
  if (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > drift.log 2>&1); then
    log_fail "TEST-004: --check --strict must exit 1 when a canonical requirement is untraced/broken"
  fi
  extract_section_h3 "$d/drift.log" "### Canonical provenance drift" > "$d/prov-sec.txt"
  grep -qF "untraced-canonical-requirement" "$d/prov-sec.txt" \
    || log_fail "TEST-004: an empty Provenance must surface untraced-canonical-requirement"
  grep -qF "broken-canonical-provenance" "$d/prov-sec.txt" \
    || log_fail "TEST-004: a Provenance naming a missing spec must surface broken-canonical-provenance"
  grep -F "REQ-OAUTH2_LOGIN-001" "$d/prov-sec.txt" | grep -qF "untraced-canonical-requirement" \
    || log_fail "TEST-004: REQ-001 (empty Provenance) must be the untraced finding"
  grep -F "REQ-OAUTH2_LOGIN-002" "$d/prov-sec.txt" | grep -qF "broken-canonical-provenance" \
    || log_fail "TEST-004: REQ-002 (SPEC-9999) must be the broken finding"
  # Positive control: the traced requirement is NOT flagged (proves not accept-all).
  if grep -qF "REQ-OAUTH2_LOGIN-003" "$d/prov-sec.txt"; then
    log_fail "TEST-004: the traced REQ-003 (Provenance SPEC-0031, resolvable) must NOT be flagged"
  fi
  rm -rf "$d"

  # (b) fully-traced repo: every requirement resolves -> CLEAN, exit 0.
  d="$(setup_iso_repo prov-clean)"
  cat > "$d/docs/specs/SPEC-0031-trace-target.md" <<'MD'
---
id: SPEC-0031
type: spec
status: accepted
links:
  pr: []
---
# Scanned spec
MD
  write_canonical_doc "$d" oauth2-login <<MD
### REQ-OAUTH2_LOGIN-001 ${dash} Traced
The system SHALL do the traced thing.

Provenance: SPEC-0031
MD
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > clean.log 2>&1) \
    || log_fail "TEST-004: a fully-traced canonical doc must exit 0 (CLEAN): $(cat "$d/clean.log")"
  assert_contains "$d/clean.log" "Canonical provenance drift: 0"
  extract_section_h3 "$d/clean.log" "### Verdict" | grep -qF "CLEAN" \
    || log_fail "TEST-004: a fully-traced repo must report the CLEAN verdict"
  rm -rf "$d"
  log_pass "Provenance drift flags untraced/broken, leaves resolvable requirements CLEAN (TEST-004)"
}

test_delta3_empty_canonical_control() {  # spec-delta-stage-3 TEST-005 / Spec-AC-02
  log_info "Test: no docs/canonical/ -> docs-audit --check --strict emits NO provenance finding (real repo stays CLEAN) (TEST-005)..."
  local d; d="$(setup_iso_repo prov-empty)"
  # A clean doc, but deliberately NO docs/canonical/ directory at all.
  cat > "$d/docs/specs/SPEC-0040-ordinary.md" <<'MD'
---
id: SPEC-0040
type: spec
status: accepted
links:
  pr: []
---
# An ordinary open spec; this repo carries no canonical layer
MD
  [[ -d "$d/docs/canonical" ]] && log_fail "TEST-005: control repo must have NO docs/canonical/"
  # Assert ONLY the no-false-positive invariants (true both before and after the
  # drift check ships — this control passes pre-change by construction).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > empty.log 2>&1) \
    || log_fail "TEST-005: empty-canonical repo must exit 0 (no false positive): $(cat "$d/empty.log")"
  assert_not_contains "$d/empty.log" "untraced-canonical-requirement"
  assert_not_contains "$d/empty.log" "broken-canonical-provenance"
  extract_section_h3 "$d/empty.log" "### Verdict" | grep -qF "CLEAN" \
    || log_fail "TEST-005: empty-canonical repo must report CLEAN"
  rm -rf "$d"
  log_pass "Empty/absent docs/canonical/ contributes no provenance finding; repo stays CLEAN (TEST-005)"
}

# --- CHANGE-0027 / SPEC-0039 — probable-false-open drift heuristic (TEST-001..014) ---
#
# Every stanza below shares a canonical POSITIVE CONTROL doc (CHANGE-9001,
# via setup_fo_repo + assert_fo_control_flagged) so a purely-negative
# assertion can never pass vacuously against the UNMODIFIED (pre-feature)
# engine — the same RED-proof idiom used by test_closeout_spec_not_all_done
# elsewhere in this suite. TEST-001 and TEST-009 carry their own positive
# assertions instead (no separate control needed).

# Isolated repo (setup_iso_repo) plus one delivered-but-open doc (implementing,
# CHANGE-9001) that the false-open heuristic must flag. Echoes the repo path.
setup_fo_repo() {
  local name="$1"
  local d; d="$(setup_iso_repo "$name")"
  mkdir -p "$d/docs/issues"
  cat > "$d/docs/issues/CHANGE-9001-fo-control.md" <<'MD'
---
id: CHANGE-9001
type: change
status: implementing
links:
  pr: []
---
# Positive control: delivered but never closed
MD
  (cd "$d" && git add docs/issues/CHANGE-9001-fo-control.md \
    && git commit -qm "docs: intake CHANGE-9001")
  echo shipped > "$d/CONTROL-DELIVERY.md"
  (cd "$d" && git add CONTROL-DELIVERY.md \
    && git commit -qm "feat: deliver CHANGE-9001 to production")
  printf '%s' "$d"
}

assert_fo_control_flagged() {  # $1 = audit log path
  grep -F "CHANGE-9001" "$1" | grep -qF "probable-false-open" \
    || log_fail "RED-proof: positive control CHANGE-9001 must be flagged probable-false-open"
}

test_change0027_delivery_commit_flags() {  # TEST-001 / Spec-AC-01
  log_info "Test: eligible open doc + later feat: commit mentioning it -> probable-false-open with a cited hash, for every eligible status (TEST-001)..."
  local d; d="$(setup_iso_repo fo-delivery)"
  mkdir -p "$d/docs/issues"
  cat > "$d/docs/issues/CHANGE-5801-fo-draft.md" <<'MD'
---
id: CHANGE-5801
type: change
status: draft
links:
  pr: []
---
# Draft change, delivered but never closed
MD
  cat > "$d/docs/issues/CHANGE-5802-fo-implementing.md" <<'MD'
---
id: CHANGE-5802
type: change
status: implementing
links:
  pr: []
---
# Implementing change, delivered but never closed
MD
  cat > "$d/docs/issues/CHANGE-5803-fo-accepted.md" <<'MD'
---
id: CHANGE-5803
type: change
status: accepted
links:
  pr: []
---
# Accepted change, delivered but never closed
MD
  (cd "$d" && git add docs/issues \
    && git commit -qm "docs: intake CHANGE-5801 CHANGE-5802 CHANGE-5803")
  echo delivered > "$d/DELIVERY.md"
  (cd "$d" && git add DELIVERY.md \
    && git commit -qm "feat: deliver CHANGE-5801 CHANGE-5802 CHANGE-5803 to production")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  for id in CHANGE-5801 CHANGE-5802 CHANGE-5803; do
    grep -F "$id" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
      || log_fail "TEST-001: $id must be flagged probable-false-open"
  done
  local row; row="$(grep -F "CHANGE-5801" "$d/drift-sec.txt" | head -1)"
  echo "$row" | grep -qF "delivery commit(s)" \
    || log_fail "TEST-001: reasons must name the delivery-commit signal"
  echo "$row" | grep -Eq '[0-9a-f]{7}' \
    || log_fail "TEST-001: drift row Evidence cell must carry a short commit hash"
  rm -rf "$d"
  log_pass "Delivery-commit signal flags every eligible open status, with a hash cited (TEST-001)"
}

test_change0027_intake_only_not_flagged() {  # TEST-002 / Spec-AC-02
  log_info "Test: doc referenced only by its own feat:-prefixed add-commit is NOT flagged (TEST-002)..."
  local d; d="$(setup_fo_repo fo-intake-only)"
  cat > "$d/docs/issues/CHANGE-5810-intake-only.md" <<'MD'
---
id: CHANGE-5810
type: change
status: draft
links:
  pr: []
---
# Freshly intaken change
MD
  (cd "$d" && git add docs/issues/CHANGE-5810-intake-only.md \
    && git commit -qm "feat: intake CHANGE-5810")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "CHANGE-5810" "$d/drift-sec.txt"; then
    log_fail "TEST-002: own add-commit (even feat:-prefixed) must NOT count as delivery evidence"
  fi
  rm -rf "$d"
  log_pass "Own add-commit never counts as delivery evidence, even when feat:-prefixed (TEST-002)"
}

test_change0027_nondelivery_mentions_not_flagged() {  # TEST-003 / Spec-AC-02
  log_info "Test: later docs:/merge-subject mentions only do NOT flag (TEST-003)..."
  local d; d="$(setup_fo_repo fo-nondelivery)"
  cat > "$d/docs/issues/CHANGE-5811-docs-only.md" <<'MD'
---
id: CHANGE-5811
type: change
status: implementing
links:
  pr: []
---
# Change mentioned only in non-delivery commits
MD
  (cd "$d" && git add docs/issues/CHANGE-5811-docs-only.md \
    && git commit -qm "docs: add CHANGE-5811 fixture")
  printf '\nnote\n' >> "$d/docs/issues/CHANGE-5811-docs-only.md"
  (cd "$d" && git add docs/issues/CHANGE-5811-docs-only.md \
    && git commit -qm "docs: update CHANGE-5811 notes")
  (cd "$d" && git commit --allow-empty -qm "Merge pull request #1 from origin/CHANGE-5811-branch")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "CHANGE-5811" "$d/drift-sec.txt"; then
    log_fail "TEST-003: docs:/merge-subject mentions must NOT count as delivery evidence"
  fi
  rm -rf "$d"
  log_pass "docs: and merge-subject mentions never count as delivery evidence (TEST-003)"
}

test_change0027_sibling_numbered_boundary() {  # TEST-004 / Spec-AC-03
  log_info "Test: CHANGE-030 open, feat: ... CHANGE-0301 -> CHANGE-030 not flagged (TEST-004)..."
  local d; d="$(setup_fo_repo fo-sibling-numbered)"
  cat > "$d/docs/issues/CHANGE-030-sibling.md" <<'MD'
---
id: CHANGE-030
type: change
status: draft
links:
  pr: []
---
# Sibling-prone numbered id
MD
  (cd "$d" && git add docs/issues/CHANGE-030-sibling.md \
    && git commit -qm "docs: add CHANGE-030 fixture")
  echo shipped > "$d/OTHER-DELIVERY.md"
  (cd "$d" && git add OTHER-DELIVERY.md \
    && git commit -qm "feat: ship CHANGE-0301 unrelated work")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "CHANGE-030" "$d/drift-sec.txt"; then
    log_fail "TEST-004: CHANGE-0301 mention must NOT satisfy sibling CHANGE-030 (boundary D4)"
  fi
  rm -rf "$d"
  log_pass "Numbered sibling-ID boundary respected: CHANGE-0301 does not satisfy CHANGE-030 (TEST-004)"
}

test_change0027_sibling_slug_boundary() {  # TEST-005 / Spec-AC-03
  log_info "Test: slug id not matched inside a longer sibling slug mention (TEST-005)..."
  local d; d="$(setup_fo_repo fo-sibling-slug)"
  cat > "$d/docs/specs/SPEC-DRAFT-delta-merge.md" <<'MD'
---
id: delta-merge
type: spec
status: implementing
links:
  pr: []
---
# Slug-id draft, sibling-prone
MD
  (cd "$d" && git add docs/specs/SPEC-DRAFT-delta-merge.md \
    && git commit -qm "docs: add delta-merge draft fixture")
  echo shipped > "$d/SIBLING-DELIVERY.md"
  (cd "$d" && git add SIBLING-DELIVERY.md \
    && git commit -qm "feat: ship delta-merge-stage-3 fully")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "delta-merge" "$d/drift-sec.txt"; then
    log_fail "TEST-005: delta-merge-stage-3 mention must NOT satisfy sibling slug delta-merge (boundary D4)"
  fi
  rm -rf "$d"
  log_pass "Slug sibling-ID boundary respected: delta-merge-stage-3 does not satisfy delta-merge (TEST-005)"
}

test_change0027_ac_evidence_event_flags() {  # TEST-006 / Spec-AC-04
  log_info "Test: ac_evidence event (rolled-up ref) flags; event named in reasons (TEST-006)..."
  local d; d="$(setup_fo_repo fo-ac-evidence)"
  cat > "$d/docs/issues/CHANGE-5812-ac-evidence.md" <<'MD'
---
id: CHANGE-5812
type: change
status: accepted
links:
  pr: []
---
# Change with delivery proven only by an ac_evidence event
MD
  (cd "$d" && git add docs/issues/CHANGE-5812-ac-evidence.md \
    && git commit -qm "docs: add CHANGE-5812 fixture")
  (cd "$d" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref CHANGE-5812/delivered-subtask --evidence "shipped" > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "CHANGE-5812" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-006: CHANGE-5812 must be flagged via the ac_evidence signal"
  grep -F "CHANGE-5812" "$d/drift-sec.txt" | grep -qF "ac_evidence event" \
    || log_fail "TEST-006: reasons must name the ac_evidence event signal"
  rm -rf "$d"
  log_pass "ac_evidence event (rolled-up ref) flags the doc; event named in reasons (TEST-006)"
}

test_change0027_ac_table_signal() {  # TEST-007 / Spec-AC-05
  log_info "Test: fully terminal evidenced AC table flags; non-terminal control does not (TEST-007)..."
  local d; d="$(setup_fo_repo fo-ac-table)"
  cat > "$d/docs/specs/SPEC-5820-terminal-table.md" <<'MD'
---
id: SPEC-5820
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec whose AC table is already fully terminal + evidenced

## Acceptance Criteria Status

| Spec-AC    | Description | Status    | Evidence | Review-By | Notes |
|------------|-------------|-----------|----------|-----------|-------|
| Spec-AC-01 | first       | done      | a1b2c3d  | —         | —     |
| Spec-AC-02 | second      | deferred  | —        | —         | —     |
MD
  cat > "$d/docs/specs/SPEC-5821-partial-table.md" <<'MD'
---
id: SPEC-5821
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec whose AC table is still partially open (control)

## Acceptance Criteria Status

| Spec-AC    | Description | Status       | Evidence | Review-By | Notes |
|------------|-------------|--------------|----------|-----------|-------|
| Spec-AC-01 | first       | done         | a1b2c3d  | —         | —     |
| Spec-AC-02 | second      | implementing | —        | —         | —     |
MD
  (cd "$d" && git add docs/specs && git commit -qm "docs: add SPEC-5820 SPEC-5821 fixtures")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "SPEC-5820" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-007: fully terminal evidenced AC table must flag SPEC-5820"
  grep -F "SPEC-5820" "$d/drift-sec.txt" | grep -qF "AC Status table fully terminal with evidence" \
    || log_fail "TEST-007: reasons must name the AC-table signal"
  if grep -qF "SPEC-5821" "$d/drift-sec.txt"; then
    log_fail "TEST-007: a non-terminal AC table must NOT trigger the false-open AC-table signal"
  fi
  rm -rf "$d"
  log_pass "Fully terminal evidenced AC table flags; non-terminal table stays unflagged (TEST-007)"
}

test_change0027_digest_and_event() {  # TEST-008 / Spec-AC-06 (SEAM-2)
  log_info "Test: digest row + False-open summary + NEEDS-TRIAGE; EVENTS.jsonl carries the false-open count (TEST-008)..."
  local d; d="$(setup_fo_repo fo-digest)"
  (cd "$d" && node .aai/scripts/docs-audit.mjs > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  assert_contains "$d/audit.log" "False-open: 1"
  extract_section_h3 "$d/audit.log" "### Verdict" | grep -qF "NEEDS-TRIAGE" \
    || log_fail "TEST-008: any false-open doc must flip the overall verdict to NEEDS-TRIAGE"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"event":"docs_audit"' \
    || log_fail "TEST-008: last EVENTS line must be a docs_audit event"
  tail -1 "$d/docs/ai/EVENTS.jsonl" | grep -qF '"false_open":1' \
    || log_fail "TEST-008: docs_audit payload must carry the false-open count"
  rm -rf "$d"
  log_pass "Digest carries the false-open row + summary + NEEDS-TRIAGE; event payload carries the count (TEST-008)"
}

test_change0027_precedence_over_stale() {  # TEST-009 / Spec-AC-07
  log_info "Test: stale AND delivered -> probable-false-open; stale only -> probable-stale-open unchanged (TEST-009)..."
  local d; d="$(setup_iso_repo fo-precedence)"
  mkdir -p "$d/docs/issues"
  cat > "$d/docs/issues/CHANGE-5830-stale-delivered.md" <<'MD'
---
id: CHANGE-5830
type: change
status: implementing
links:
  pr: []
---
# Stale-aged AND delivery-evidenced (must upgrade to false-open)
MD
  cat > "$d/docs/issues/CHANGE-5831-stale-only.md" <<'MD'
---
id: CHANGE-5831
type: change
status: implementing
links:
  pr: []
---
# Stale-aged, no delivery evidence (must stay probable-stale-open)
MD
  (cd "$d" && git add docs/issues \
    && GIT_COMMITTER_DATE="2026-01-15T10:00:00Z" GIT_AUTHOR_DATE="2026-01-15T10:00:00Z" \
       git commit -qm "docs: add CHANGE-5830 CHANGE-5831 fixtures")
  # A backdated delivery commit for CHANGE-5830 ONLY — old enough that, absent
  # the false-open upgrade, its own mention-age would ALSO exceed
  # stale_after_days (default 90d), proving this is a genuine D5 precedence
  # upgrade, not merely a recency artifact.
  echo shipped > "$d/OLD-DELIVERY.md"
  (cd "$d" && git add OLD-DELIVERY.md \
    && GIT_COMMITTER_DATE="2026-01-20T10:00:00Z" GIT_AUTHOR_DATE="2026-01-20T10:00:00Z" \
       git commit -qm "feat: deliver CHANGE-5830 to production")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "CHANGE-5830" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-009: stale-AND-delivered doc must upgrade to probable-false-open"
  if grep -F "CHANGE-5830" "$d/drift-sec.txt" | grep -qF "probable-stale-open"; then
    log_fail "TEST-009: stale-AND-delivered doc must NOT stay probable-stale-open"
  fi
  grep -F "CHANGE-5831" "$d/drift-sec.txt" | grep -qF "probable-stale-open" \
    || log_fail "TEST-009: stale-only doc (no delivery evidence) must keep probable-stale-open exactly as today"
  rm -rf "$d"
  log_pass "False-open takes precedence over stale-open; undelivered stale docs unchanged (TEST-009)"
}

test_change0027_frozen_draft_probe() {  # TEST-011 / Spec-AC-08
  log_info "Test: frozen-in-body draft: evidenced -> flagged; unevidenced -> aligned/tracked-open (TEST-011)..."
  local d; d="$(setup_fo_repo fo-frozen-draft)"
  cat > "$d/docs/specs/SPEC-5840-frozen-evidenced.md" <<'MD'
---
id: SPEC-5840
type: spec
status: draft
links:
  pr: []
---
# Frozen-in-body draft, already delivered

📋 SPEC-FROZEN: true
MD
  cat > "$d/docs/specs/SPEC-5841-frozen-unevidenced.md" <<'MD'
---
id: SPEC-5841
type: spec
status: draft
links:
  pr: []
---
# Frozen-in-body draft, not yet delivered (control)

📋 SPEC-FROZEN: true
MD
  (cd "$d" && git add docs/specs && git commit -qm "docs: add SPEC-5840 SPEC-5841 fixtures")
  echo shipped > "$d/FROZEN-DELIVERY.md"
  (cd "$d" && git add FROZEN-DELIVERY.md \
    && git commit -qm "feat: ship SPEC-5840 fully")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --list --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "SPEC-5840" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-011: a delivery-evidenced frozen-in-body draft must be flagged (D6)"
  if grep -qF "SPEC-5841" "$d/drift-sec.txt"; then
    log_fail "TEST-011: an unevidenced frozen-in-body draft must NOT be flagged"
  fi
  grep -F "SPEC-5841" "$d/audit.log" | grep -qF "frozen" \
    || log_fail "TEST-011: unevidenced frozen-in-body draft must keep its byte-identical frozen classification"
  rm -rf "$d"
  log_pass "Frozen-in-body drafts checked: delivered flags, unevidenced stays aligned/tracked-open (TEST-011)"
}

test_change0027_ac_table_tdd_log_only_not_flagged() {  # TEST-015 / Spec-AC-07
  log_info "Test: in-flight spec — AC table completed by TDD, evidenced ONLY by same-session TDD proof logs, no delivering commit/event -> stays aligned, NOT probable-false-open (TEST-015)..."
  local d; d="$(setup_fo_repo fo-tdd-log-only)"
  cat > "$d/docs/specs/SPEC-5850-inflight-tdd-only.md" <<'MD'
---
id: SPEC-5850
type: spec
status: draft
links:
  pr: []
---
# In-flight spec: AC table completed by TDD, not yet delivered

📋 SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | TEST-001 green — docs/ai/tdd/green-20260101T000000Z-fixture-test001.log | TDD | — |
| Spec-AC-02 | second      | done   | TEST-002 green — docs/ai/tdd/green-20260101T000000Z-fixture-test002.log | TDD | — |
MD
  (cd "$d" && git add docs/specs/SPEC-5850-inflight-tdd-only.md \
    && git commit -qm "docs: add SPEC-5850 in-flight fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --list --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "SPEC-5850" "$d/drift-sec.txt"; then
    log_fail "TEST-015: an in-flight spec whose AC table is evidenced only by same-session TDD proof logs must NOT be flagged probable-false-open without a corroborating delivery commit or ac_evidence event"
  fi
  grep -F "SPEC-5850" "$d/audit.log" | grep -qF "frozen" \
    || log_fail "TEST-015: in-flight frozen-in-body draft must keep its byte-identical frozen classification"
  rm -rf "$d"
  log_pass "In-flight spec with TDD-log-only AC evidence stays aligned, not false-open — no regression on the audit's own repo (TEST-015)"
}

test_change0027_index_seam() {  # TEST-012 / Spec-AC-09 (SEAM-1)
  log_info "Test: generate-docs-index.mjs renders the false-open row + D9 suggested step (TEST-012)..."
  local d; d="$(setup_fo_repo fo-index-seam)"
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > index.log 2>&1) \
    || log_fail "TEST-012: generate-docs-index.mjs failed: $(cat "$d/index.log")"
  local audit="$d/docs/INDEX.audit.md"
  assert_file "$audit"
  assert_contains "$audit" "probable-false-open"
  grep -F "CHANGE-9001" "$audit" | grep -qF "probable-false-open" \
    || log_fail "TEST-012: INDEX.audit.md must carry the false-open row for CHANGE-9001"
  assert_contains "$audit" "confirm delivery, then run close ceremony"
  rm -rf "$d"
  log_pass "generate-docs-index.mjs (SEAM-1) renders the false-open row with the D9 suggested step (TEST-012)"
}

test_change0027_quick_mode_skips_probe() {  # TEST-013 / Spec-AC-07
  log_info "Test: --quick digest carries no false-open probe/row (TEST-013)..."
  local d; d="$(setup_fo_repo fo-quick)"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --quick > quick.log 2>&1) || true
  assert_contains "$d/quick.log" "Mode: quick"
  assert_not_contains "$d/quick.log" "probable-false-open"
  # The summary count field itself is always printed (symmetric with the
  # pre-existing Stale: 0 behavior in quick mode) — it must read zero because
  # the probe never ran, not because the field is hidden.
  assert_contains "$d/quick.log" "False-open: 0"
  # Positive control: the SAME fixture flags under a full run (proves --quick
  # really is skipping the probe, not merely a fixture that never triggers it).
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > full.log 2>&1) || true
  assert_fo_control_flagged "$d/full.log"
  rm -rf "$d"
  log_pass "--quick skips the false-open probe entirely; full run on the same fixture flags it (TEST-013)"
}

test_change0027_doc_surfaces_mention_false_open() {  # TEST-014 / Spec-AC-09
  log_info "Test: USER_GUIDE.md verdict list + SKILL.md description mention false-open (TEST-014)..."
  assert_contains "$PROJECT_ROOT/docs/USER_GUIDE.md" "probable-false-open"
  assert_contains "$PROJECT_ROOT/.claude/skills/aai-docs-audit/SKILL.md" "false-open"
  log_pass "USER_GUIDE.md and SKILL.md both mention the false-open verdict (TEST-014)"
}

# --- CHANGE-0028 / SPEC-docs-audit-d2-evidence-hardening — D2(b)/D2(c)
# delivery-evidence hardening (TEST-001..011) --------------------------------
#
# Every positive-firing stanza below shares the CHANGE-9001 positive control
# (via setup_fo_repo + assert_fo_control_flagged, SPEC-0039 precedent) so a
# purely-negative assertion can never pass vacuously against the unmodified
# engine.

test_change0028_mixed_cell_git_hash_flags() {  # TEST-001 / Spec-AC-01
  log_info "Test: mixed Evidence cell (TDD log + git-verified commit hash) flags via AC-table signal (TEST-001)..."
  local d; d="$(setup_fo_repo fo028-hash)"
  # A commit whose hash gets cited in the mixed Evidence cell below.
  echo "delivery" > "$d/HASH-DELIVERY.md"
  (cd "$d" && git add HASH-DELIVERY.md && git commit -qm "chore: unrelated delivery commit for hash citation")
  local hash; hash="$(cd "$d" && git rev-parse --short=10 HEAD)"
  cat > "$d/docs/specs/SPEC-5860-mixed-hash.md" <<MD
---
id: SPEC-5860
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec with a mixed TDD-log + hash Evidence cell

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | TEST-001 green — docs/ai/tdd/green-20260101T000000Z-fixture.log; delivered ${hash} | — | — |
MD
  (cd "$d" && git add docs/specs/SPEC-5860-mixed-hash.md && git commit -qm "docs: add SPEC-5860 fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "SPEC-5860" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-001: mixed TDD-log + git-verified hash Evidence cell must flag via AC-table signal"
  grep -F "SPEC-5860" "$d/drift-sec.txt" | grep -qF "AC Status table fully terminal with evidence" \
    || log_fail "TEST-001: reasons must name the AC-table signal"
  rm -rf "$d"
  log_pass "Mixed TDD-log + git-verified commit hash Evidence cell flags via AC-table signal (TEST-001)"
}

test_change0028_mixed_cell_pr_ref_flags() {  # TEST-002 / Spec-AC-02
  log_info "Test: mixed Evidence cells with PR #N and /pull/N URL citations flag via AC-table signal (TEST-002)..."
  local d; d="$(setup_fo_repo fo028-pr)"
  cat > "$d/docs/specs/SPEC-5861-mixed-pr.md" <<'MD'
---
id: SPEC-5861
type: spec
status: implementing
links:
  pr: []
---
# Implementing spec with mixed TDD-log + PR-reference Evidence cells

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | TEST-001 green — docs/ai/tdd/green-20260101T000000Z-a.log; landed via PR #91 | — | — |
| Spec-AC-02 | second      | done   | TEST-002 green — docs/ai/tdd/green-20260101T000000Z-b.log; see https://example.com/goodwind-cz/aai/pull/91 | — | — |
MD
  (cd "$d" && git add docs/specs/SPEC-5861-mixed-pr.md && git commit -qm "docs: add SPEC-5861 fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "SPEC-5861" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002: mixed TDD-log + PR-reference Evidence cell must flag via AC-table signal"
  rm -rf "$d"
  log_pass "Mixed TDD-log + PR reference Evidence cells flag via AC-table signal (TEST-002)"
}

test_change0028_mixed_cell_prose_not_flagged() {  # TEST-003 / Spec-AC-04
  log_info "Test: mixed Evidence cell TDD-log + non-delivery prose only stays unflagged (guard control, TEST-003)..."
  local d; d="$(setup_fo_repo fo028-prose)"
  cat > "$d/docs/specs/SPEC-5862-mixed-prose.md" <<'MD'
---
id: SPEC-5862
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec whose Evidence cell mixes a TDD log with non-delivery prose

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | TEST-001 green — docs/ai/tdd/green-20260101T000000Z-c.log; re-verified locally, looks good | — | — |
MD
  (cd "$d" && git add docs/specs/SPEC-5862-mixed-prose.md && git commit -qm "docs: add SPEC-5862 fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "SPEC-5862" "$d/drift-sec.txt"; then
    log_fail "TEST-003: TDD-log + non-delivery prose Evidence cell must NOT flag (precision guard)"
  fi
  rm -rf "$d"
  log_pass "Mixed TDD-log + non-delivery prose Evidence cell stays unflagged (TEST-003)"
}

test_change0028_mixed_cell_unresolvable_hash_not_flagged() {  # TEST-004 / Spec-AC-04
  log_info "Test: mixed Evidence cell TDD-log + hash-shaped token absent from git stays unflagged (git-verify guard, TEST-004)..."
  local d; d="$(setup_fo_repo fo028-badhash)"
  cat > "$d/docs/specs/SPEC-5863-mixed-badhash.md" <<'MD'
---
id: SPEC-5863
type: spec
status: implementing
links:
  pr: []
---
# Implementing spec whose Evidence cell mixes a TDD log with a nonexistent hash-shaped token

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | TEST-001 green — docs/ai/tdd/green-20260101T000000Z-d.log; commit abcdef1 | — | — |
MD
  (cd "$d" && git add docs/specs/SPEC-5863-mixed-badhash.md && git commit -qm "docs: add SPEC-5863 fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "SPEC-5863" "$d/drift-sec.txt"; then
    log_fail "TEST-004: TDD-log + unresolvable hash-shaped token Evidence cell must NOT flag (git-verify guard)"
  fi
  rm -rf "$d"
  log_pass "Mixed TDD-log + unresolvable hash-shaped token Evidence cell stays unflagged (TEST-004)"
}

test_change0028_spec0039_verbatim_replica_not_flagged() {  # TEST-005 / Spec-AC-03
  log_info "Test: verbatim replica of SPEC-0039's real Spec-AC-07 Evidence cell stays unflagged (TEST-005)..."
  local d; d="$(setup_fo_repo fo028-replica)"
  cat > "$d/docs/specs/SPEC-5864-replica.md" <<'MD'
---
id: SPEC-5864
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec replicating SPEC-0039's real Spec-AC-07 Evidence cell verbatim

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-07 | existing verdicts unchanged; quick skips; D5 precedence  | done    | TEST-009/010/013/015 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log (115 PASS, full suite incl. real-repo-CLEAN regressions); repo audit re-verified CLEAN post-fix (`node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0) | TDD | Remediation CHANGE-0027: TEST-015 added (in-flight-spec no-regression control) |
MD
  (cd "$d" && git add docs/specs/SPEC-5864-replica.md && git commit -qm "docs: add SPEC-5864 fixture")
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "SPEC-5864" "$d/drift-sec.txt"; then
    log_fail "TEST-005: verbatim replica of SPEC-0039's real Spec-AC-07 Evidence cell must NOT flag"
  fi
  rm -rf "$d"
  log_pass "Verbatim replica of SPEC-0039's real Spec-AC-07 Evidence cell stays unflagged (TEST-005)"
}

test_change0028_arm_b_fileid_ac_evidence_flags() {  # TEST-006 / Spec-AC-05
  log_info "Test: ac_evidence event ref matching fileId (not frontmatter id) with hash-shaped payload.commit fires Arm B (TEST-006)..."
  local d; d="$(setup_fo_repo fo028-armb)"
  cat > "$d/docs/specs/SPEC-5865-armb-fileid.md" <<'MD'
---
id: armb-legacy-slug
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec whose frontmatter id differs from its numbered filename
MD
  (cd "$d" && git add docs/specs/SPEC-5865-armb-fileid.md \
    && git commit -qm "docs: add SPEC-5865 fixture")
  (cd "$d" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref SPEC-5865/Spec-AC-01 --commit a1b2c3d4e5 > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "armb-legacy-slug" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-006: Arm B (fileId-ref ac_evidence with hash payload) must flag the doc (armb-legacy-slug)"
  grep -F "armb-legacy-slug" "$d/drift-sec.txt" | grep -qF "ac_evidence event" \
    || log_fail "TEST-006: reasons must name the ac_evidence event signal"
  rm -rf "$d"
  log_pass "Arm B: fileId-ref ac_evidence event with hash-shaped payload.commit fires (TEST-006)"
}

test_change0028_arm_b_inflight_discriminator_guard() {  # TEST-007 / Spec-AC-06
  log_info "Test: Arm B in-flight discriminator rejects validation-window payload.commit and evidence-only payload (guard control, TEST-007)..."
  local d; d="$(setup_fo_repo fo028-armb-guard)"
  cat > "$d/docs/specs/SPEC-5866-armb-guard.md" <<'MD'
---
id: armb-guard-slug
type: spec
status: implementing
links:
  pr: []
---
# Implementing spec whose fileId-ref ac_evidence events are validation-window/evidence-only
MD
  (cd "$d" && git add docs/specs/SPEC-5866-armb-guard.md \
    && git commit -qm "docs: add SPEC-5866 fixture")
  (cd "$d" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref SPEC-5866/Spec-AC-01 --commit "validation-20260101T000000Z re-verified PASS (full suite green)" > /dev/null)
  (cd "$d" && node .aai/scripts/append-event.mjs --event ac_evidence \
    --ref SPEC-5866/Spec-AC-02 --evidence "shipped" > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  if grep -qF "armb-guard-slug" "$d/drift-sec.txt"; then
    log_fail "TEST-007: Arm B must NOT fire for a validation-window payload.commit or an evidence-only payload"
  fi
  rm -rf "$d"
  log_pass "Arm B in-flight discriminator rejects validation-window and evidence-only payloads (TEST-007)"
}

test_change0028_arm_c_work_item_closed_flags() {  # TEST-008 / Spec-AC-07
  log_info "Test: work_item_closed event fires unconditionally for either id candidate — fileId ref AND slug-id ref (TEST-008)..."
  local d; d="$(setup_fo_repo fo028-armc)"
  cat > "$d/docs/specs/SPEC-5867-armc-fileid-ref.md" <<'MD'
---
id: armc-fileid-slug
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec closed via a fileId-ref work_item_closed event
MD
  cat > "$d/docs/specs/SPEC-5868-armc-slugid-ref.md" <<'MD'
---
id: armc-slugid-slug
type: spec
status: accepted
links:
  pr: []
---
# Accepted spec closed via a slug-id-ref work_item_closed event
MD
  (cd "$d" && git add docs/specs/SPEC-5867-armc-fileid-ref.md docs/specs/SPEC-5868-armc-slugid-ref.md \
    && git commit -qm "docs: add SPEC-5867 SPEC-5868 fixtures")
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed \
    --ref SPEC-5867 --validation pass --code-review pass > /dev/null)
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed \
    --ref armc-slugid-slug --validation pass --code-review pass > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  grep -F "armc-fileid-slug" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-008: work_item_closed fileId-ref must flag the doc (armc-fileid-slug)"
  grep -F "armc-fileid-slug" "$d/drift-sec.txt" | grep -qF "work_item_closed event" \
    || log_fail "TEST-008: reasons must name the work_item_closed event signal (fileId ref)"
  grep -F "armc-slugid-slug" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-008: work_item_closed slug-id-ref must flag the doc (armc-slugid-slug)"
  grep -F "armc-slugid-slug" "$d/drift-sec.txt" | grep -qF "work_item_closed event" \
    || log_fail "TEST-008: reasons must name the work_item_closed event signal (slug-id ref)"
  rm -rf "$d"
  log_pass "work_item_closed event fires unconditionally for both fileId-ref and slug-id-ref forms (TEST-008)"
}

test_change0028_real_repo_clean() {  # TEST-009 / Spec-AC-08
  log_info "Test: real-repo docs-audit stays CLEAN with zero false-open verdicts after D2 hardening (TEST-009)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/c0028-audit.log" 2>&1) \
    || log_fail "real-repo docs-audit --check --strict must exit 0: $(tail -5 "$TEST_DIR/c0028-audit.log")"
  # SPEC-0057: see test_spec0006_no_regression_real_repo's comment — the
  # real-repo Verdict line now correctly reads NEEDS-TRIAGE (3 pre-existing,
  # tracked, verdict-only duplicate-doc-id collisions, unrelated to
  # false-open); assert the hard-gate signal this stanza actually guards
  # instead. False-open: 0 (below) remains this test's real regression proof.
  assert_contains "$TEST_DIR/c0028-audit.log" "Orphans (need triage): 0"
  assert_not_contains "$TEST_DIR/c0028-audit.log" "CHECK FAILED"
  assert_contains "$TEST_DIR/c0028-audit.log" "False-open: 0"
  if grep -qF "probable-false-open" "$TEST_DIR/c0028-audit.log"; then
    log_fail "TEST-009: real-repo audit must carry zero probable-false-open verdicts (SPEC-0039 and all in-flight docs must stay unflagged)"
  fi
  log_pass "Real-repo audit stays CLEAN with zero false-open verdicts (TEST-009)"
}

test_change0028_userguide_mentions_work_item_closed() {  # TEST-011 / Spec-AC-10
  log_info "Test: USER_GUIDE.md probable-false-open bullet (specifically) names the work_item_closed event (TEST-011)..."
  # Scoped to the probable-false-open bullet's own lines (up to the next
  # top-level bullet) — USER_GUIDE.md already mentions work_item_closed
  # elsewhere (the missing-close-telemetry bullet), so a whole-file grep
  # would pass vacuously and not prove THIS bullet was updated (D8).
  local bullet
  bullet="$(awk '/^- `probable-false-open`/{flag=1} flag{print} flag && /^- `probable-partial`/{exit}' "$PROJECT_ROOT/docs/USER_GUIDE.md")"
  echo "$bullet" | grep -qF "work_item_closed" \
    || log_fail "TEST-011: the probable-false-open bullet itself must name the work_item_closed event"
  log_pass "USER_GUIDE.md probable-false-open bullet names the work_item_closed event (TEST-011)"
}

# --- false-open-metrics-and-supersession (#133 METRICS arm + #134 supersession) ---
#
# Both stanzas reuse setup_fo_repo's positive control (CHANGE-9001, flagged via
# a real delivery commit) as the RED-proof anchor, so the negative guardrail
# assertions can never pass vacuously against the UNMODIFIED engine — the same
# idiom the SPEC-0039 stanzas above use. Every fixture is synthetic (a throwaway
# doc plus a synthetic METRICS.jsonl line and/or a synthetic doc_lifecycle
# event): the real upstream corpus has zero open docs and proves nothing here.

test_fometrics_flush_arm() {  # TEST-001 / Spec-AC-01 (+ Spec-AC-03 garble sub-case)
  log_info "Test: METRICS.jsonl flush record flags an open intake by slug id (a); fileId-only (c) + no-match (b) + garbled lines (d) do NOT flag (TEST-001)..."
  local d; d="$(setup_fo_repo fo-metrics-arm)"
  # (a) flushed intake, frontmatter id == fileId, ONLY proof is the METRICS line
  cat > "$d/docs/issues/CHANGE-5830-flush-a.md" <<'MD'
---
id: CHANGE-5830
type: change
status: draft
links:
  pr: []
---
# Flushed intake whose only delivery proof is the METRICS ledger
MD
  # (b) same shape, NO matching flush line -> must stay unflagged (guardrail)
  cat > "$d/docs/issues/CHANGE-5831-noflush.md" <<'MD'
---
id: CHANGE-5831
type: change
status: draft
links:
  pr: []
---
# Intake with no ledger flush record
MD
  # (c) numbered file whose frontmatter slug id (flush-fileid-slug) DIFFERS from
  # its numbered fileId (CHANGE-5832); the METRICS record is keyed by the
  # numbered fileId. The arm must key on the slug id ONLY, so this must NOT flag
  # (SPEC-0054 "Problem #2" — a numbered STATE ref coinciding with a doc's
  # filename must not falsely flag it; asserted independently by metrics TEST-020).
  cat > "$d/docs/issues/CHANGE-5832-flush-fileid.md" <<'MD'
---
id: flush-fileid-slug
type: change
status: draft
links:
  pr: []
---
# Numbered filename whose slug id differs from the METRICS ref_id (fileId)
MD
  (cd "$d" && git add docs/issues \
    && git commit -qm "docs: intake CHANGE-5830 CHANGE-5831 CHANGE-5832")
  # (d) METRICS.jsonl carries a `#`-comment preamble AND one unparseable line
  mkdir -p "$d/docs/ai"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
# AAI Metrics Ledger — append-only, one JSON object per line (JSONL format)
#
{"date_utc":"2026-07-20","ref_id":"CHANGE-5830","title":"flushed a"}
{ this line is deliberately not valid json and must be skipped, never thrown
{"date_utc":"2026-07-20","ref_id":"CHANGE-5832","title":"flushed via fileId"}
JSONL
  local rc=0
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || rc=$?
  # (d) fail-closed: a comment header + garbled line must NOT throw
  [[ "$rc" -eq 0 ]] \
    || log_fail "TEST-001(d): docs-audit must complete without throwing on comment/garbled METRICS lines (rc=$rc): $(tail -5 "$d/audit.log")"
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  # (a) id match -> flagged, with a reason naming the flush/METRICS signal
  grep -F "CHANGE-5830" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-001(a): CHANGE-5830 must be flagged via the METRICS flush record"
  grep -F "CHANGE-5830" "$d/drift-sec.txt" | grep -qF "flush record" \
    || log_fail "TEST-001(a): reasons must name the flush-record (METRICS) signal, distinct from the four existing reasons"
  # (c) fileId-ONLY match (slug id differs) -> must NOT flag (key on slug id,
  # never the numbered filename; SPEC-0054 Problem #2 / metrics TEST-020)
  if grep -qF "flush-fileid-slug" "$d/drift-sec.txt"; then
    log_fail "TEST-001(c): a METRICS ref_id matching only the numbered fileId (CHANGE-5832) must NOT flag the slug-id doc (SPEC-0054 Problem #2)"
  fi
  # (b) no flush line, and (d) garbled lines did not spuriously flag it
  if grep -qF "CHANGE-5831" "$d/drift-sec.txt"; then
    log_fail "TEST-001(b): a doc with no METRICS flush line must NOT be flagged by the METRICS arm"
  fi
  rm -rf "$d"
  log_pass "METRICS flush arm flags by slug id (a); fileId-only (c), no-match (b) + garbled/comment lines (d) stay unflagged (TEST-001)"
}

test_fometrics_supersession() {  # TEST-002 / Spec-AC-02
  log_info "Test: newer doc_lifecycle reopen supersedes delivery evidence (e); older reopen (f) + no reopen (g) still flag (TEST-002)..."
  local d; d="$(setup_fo_repo fo-supersession)"
  # (e) delivered via work_item_closed, THEN reopened (reopen ts > close ts)
  cat > "$d/docs/specs/SPEC-5840-reopened-newer.md" <<'MD'
---
id: SPEC-5840
type: spec
status: implementing
links:
  pr: []
---
# Delivered, then legitimately reopened with a NEWER lifecycle event
MD
  # (f) reopened BEFORE the delivery evidence (reopen ts < close ts) -> still flags
  cat > "$d/docs/specs/SPEC-5841-reopened-older.md" <<'MD'
---
id: SPEC-5841
type: spec
status: implementing
links:
  pr: []
---
# A reopen that predates the delivery evidence must NOT suppress
MD
  # (g) delivered, left open, NO doc_lifecycle event at all -> still flags
  cat > "$d/docs/specs/SPEC-5842-no-reopen.md" <<'MD'
---
id: SPEC-5842
type: spec
status: accepted
links:
  pr: []
---
# Delivered but left open with no reopen event (genuine false-open)
MD
  # (h) METRICS-ONLY delivery + a reopen OLDER than the flush -> STILL flags.
  # The flush record's date_utc must be able to timestamp the delivery; a doc
  # whose only evidence is a flush that POSTDATES the reopen must not be
  # superseded (#133 x #134 interaction).
  cat > "$d/docs/issues/CHANGE-5850-metrics-older-reopen.md" <<'MD'
---
id: CHANGE-5850
type: change
status: draft
links:
  pr: []
---
# Flush-only delivery whose flush postdates a stale reopen
MD
  # (h-boundary) METRICS-only delivery + a SAME-DAY flush+reopen -> STILL flags.
  # date_utc is day-granular while the reopen carries a full ISO ts; a same-day
  # reopen must NOT be treated as strictly newer than the flush (conservative:
  # only a strictly-later-day reopen supersedes a flush).
  cat > "$d/docs/issues/CHANGE-5851-metrics-sameday.md" <<'MD'
---
id: CHANGE-5851
type: change
status: draft
links:
  pr: []
---
# Flush-only delivery reopened the same UTC day as the flush
MD
  (cd "$d" && git add docs/specs docs/issues \
    && git commit -qm "docs: intake SPEC-5840 SPEC-5841 SPEC-5842 CHANGE-5850 CHANGE-5851")
  # Synthetic flush ledger: CHANGE-5850's flush is 30 days in the FUTURE of the
  # reopen (emitted below at real now); CHANGE-5851's flush is the reopen's own
  # UTC day. Dates computed at run time so the fixture never expires.
  local fo_today fo_future
  fo_today="$(date -u +%Y-%m-%d)"
  fo_future="$(node -e 'console.log(new Date(Date.now()+30*864e5).toISOString().slice(0,10))')"
  mkdir -p "$d/docs/ai"
  {
    printf '# synthetic flush ledger for supersession boundary cases\n'
    printf '{"date_utc":"%s","ref_id":"CHANGE-5850","title":"flush postdates the reopen"}\n' "$fo_future"
    printf '{"date_utc":"%s","ref_id":"CHANGE-5851","title":"same-day flush and reopen"}\n' "$fo_today"
  } > "$d/docs/ai/METRICS.jsonl"
  # (e) close FIRST, then reopen -> latest doc_lifecycle is newer than the close
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed \
    --ref SPEC-5840 --validation pass --code-review pass > /dev/null)
  sleep 1
  (cd "$d" && node .aai/scripts/append-event.mjs --event doc_lifecycle \
    --ref SPEC-5840 --from done --to implementing > /dev/null)
  # (f) reopen FIRST, then close -> the reopen is OLDER than the delivery evidence
  (cd "$d" && node .aai/scripts/append-event.mjs --event doc_lifecycle \
    --ref SPEC-5841 --from done --to implementing > /dev/null)
  sleep 1
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed \
    --ref SPEC-5841 --validation pass --code-review pass > /dev/null)
  # (g) close only, no lifecycle event
  (cd "$d" && node .aai/scripts/append-event.mjs --event work_item_closed \
    --ref SPEC-5842 --validation pass --code-review pass > /dev/null)
  # (h) + (h-boundary) reopens emitted at real now (older than the future flush,
  # same day as the same-day flush) via the real writer
  (cd "$d" && node .aai/scripts/append-event.mjs --event doc_lifecycle \
    --ref CHANGE-5850 --from done --to implementing > /dev/null)
  (cd "$d" && node .aai/scripts/append-event.mjs --event doc_lifecycle \
    --ref CHANGE-5851 --from done --to implementing > /dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  # (e) newer reopen supersedes the work_item_closed evidence -> NOT flagged
  if grep -qF "SPEC-5840" "$d/drift-sec.txt"; then
    log_fail "TEST-002(e): a NEWER doc_lifecycle reopen must supersede delivery evidence (SPEC-5840 must NOT be flagged)"
  fi
  # (f) reopen older than delivery evidence -> STILL flagged
  grep -F "SPEC-5841" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(f): a reopen OLDER than the delivery evidence must NOT suppress (SPEC-5841 must STILL flag)"
  # (g) no reopen event at all -> STILL flagged (supersession never blinds a genuine false-open)
  grep -F "SPEC-5842" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(g): a delivered doc left open with NO reopen event must STILL flag (SPEC-5842)"
  # (h) METRICS-only delivery + reopen OLDER than the flush -> STILL flagged
  grep -F "CHANGE-5850" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(h): METRICS-only evidence with a reopen OLDER than the flush must STILL flag (CHANGE-5850)"
  # (h-boundary) same-day flush + reopen -> STILL flagged (day-granular flush not beaten by a same-day ts)
  grep -F "CHANGE-5851" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(h-boundary): a same-day flush+reopen must STILL flag (CHANGE-5851)"
  rm -rf "$d"
  log_pass "Newer reopen supersedes (e); older (f), no-reopen (g), METRICS-only older reopen (h) + same-day boundary still flag (TEST-002)"
}

test_fometrics_supersession_delivery_arms() {  # TEST-002 / Spec-AC-02 (i, j, k)
  log_info "Test: supersession deliveryTs covers the commit + AC-table arms; fail-closed when un-timestampable (i, j, k)..."
  local d; d="$(setup_fo_repo fo-superarms)"
  mkdir -p "$d/docs/ai"
  # (i) reopened THEN commit-delivered (commit NEWER than reopen) -> STILL flagged
  cat > "$d/docs/specs/SPEC-5860-reopen-then-commit.md" <<'MD'
---
id: SPEC-5860
type: spec
status: implementing
links:
  pr: []
---
# Reopened, then delivered by a LATER commit (commit date > reopen ts)
MD
  # (j) commit-delivered THEN reopened (reopen strictly NEWER than commit) -> NOT flagged
  cat > "$d/docs/specs/SPEC-5861-commit-then-reopen.md" <<'MD'
---
id: SPEC-5861
type: spec
status: implementing
links:
  pr: []
---
# Delivered, then legitimately reopened AFTER the commit (reopen ts > commit date)
MD
  # (k) AC-table-only evidence (D2c: terminal + evidenced, no event/commit/flush)
  # + a reopen -> STILL flagged (delivery is genuinely un-timestampable)
  cat > "$d/docs/specs/SPEC-5862-actable-only.md" <<'MD'
---
id: SPEC-5862
type: spec
status: accepted
links:
  pr: []
---
# Un-timestampable AC-table delivery evidence, reopened

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence                            | Review-By | Notes |
|------------|-------------|--------|-------------------------------------|-----------|-------|
| Spec-AC-01 | only        | done   | shipped in prod, see release notes  | —         | —     |
MD
  (cd "$d" && git add docs/specs \
    && git commit -qm "docs: intake SPEC-5860 SPEC-5861 SPEC-5862")
  # Delivery commits with EXPLICIT committer dates: %cI is second-granular, so
  # a real-clock commit could tie the reopen ts within a second and flake.
  # Fixed past dates keep (i)/(j) ordering deterministic and non-expiring.
  echo s860 > "$d/D860.md"
  (cd "$d" && git add D860.md \
    && GIT_AUTHOR_DATE="2025-06-01T00:00:00Z" GIT_COMMITTER_DATE="2025-06-01T00:00:00Z" \
       git commit -qm "feat: deliver SPEC-5860 to production")
  echo s861 > "$d/D861.md"
  (cd "$d" && git add D861.md \
    && GIT_AUTHOR_DATE="2025-03-01T00:00:00Z" GIT_COMMITTER_DATE="2025-03-01T00:00:00Z" \
       git commit -qm "feat: deliver SPEC-5861 to production")
  # Hand-written doc_lifecycle reopens with controlled ts (synthetic ledger):
  #   SPEC-5860 reopen 2025-03-01 < commit 2025-06-01  -> (i) still flags
  #   SPEC-5861 reopen 2025-06-01 > commit 2025-03-01  -> (j) supersedes
  #   SPEC-5862 reopen 2025-06-01, no dated delivery    -> (k) still flags
  {
    printf '{"v":1,"ts":"2025-03-01T00:00:00.000Z","actor":"test","event":"doc_lifecycle","ref":"SPEC-5860","payload":{"from":"done","to":"implementing"}}\n'
    printf '{"v":1,"ts":"2025-06-01T00:00:00.000Z","actor":"test","event":"doc_lifecycle","ref":"SPEC-5861","payload":{"from":"done","to":"implementing"}}\n'
    printf '{"v":1,"ts":"2025-06-01T00:00:00.000Z","actor":"test","event":"doc_lifecycle","ref":"SPEC-5862","payload":{"from":"done","to":"implementing"}}\n'
  } >> "$d/docs/ai/EVENTS.jsonl"
  (cd "$d" && node .aai/scripts/docs-audit.mjs --no-event > audit.log 2>&1) || true
  assert_fo_control_flagged "$d/audit.log"
  extract_section_h3 "$d/audit.log" "### Drift report" > "$d/drift-sec.txt"
  # (i) commit newer than reopen -> STILL flagged
  grep -F "SPEC-5860" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(i): reopen THEN newer commit-delivery must STILL flag (SPEC-5860 — commit date must feed deliveryTs)"
  # (j) reopen strictly newer than commit -> NOT flagged (proves commit dates are used)
  if grep -qF "SPEC-5861" "$d/drift-sec.txt"; then
    log_fail "TEST-002(j): a reopen strictly newer than the delivery commit must supersede (SPEC-5861 must NOT be flagged)"
  fi
  # (k) un-timestampable AC-table evidence + reopen -> STILL flagged (fail-closed)
  grep -F "SPEC-5862" "$d/drift-sec.txt" | grep -qF "probable-false-open" \
    || log_fail "TEST-002(k): un-timestampable AC-table evidence must STILL flag on any reopen (SPEC-5862)"
  rm -rf "$d"
  log_pass "Supersession deliveryTs covers commit dates (i, j) and fail-closes on un-timestampable AC-table evidence (k) (TEST-002 i-k)"
}

# --- SPEC-0057 / ISSUE-0014 — duplicate frontmatter doc-id detection (TEST-101..104) ---

setup_dupid_fixture() {
  log_info "Setting up duplicate-doc-id fixture (SPEC-0057)..."
  mkdir -p "$TEST_DIR/docs/dupid"
  cd "$TEST_DIR"

  # TEST-101 positive control: a spec + an issue sharing one frontmatter id
  # (mirrors the motivating bug — a spec created without the `spec-` prefix
  # colliding with its own intake's slug).
  cat > docs/dupid/SPEC-9401-collision.md <<'MD'
---
id: dupid-collision-x
type: spec
status: draft
links:
  pr: []
---
# Spec sharing an id with its own intake (the motivating bug)
MD
  cat > docs/dupid/ISSUE-9401-collision.md <<'MD'
---
id: dupid-collision-x
type: issue
status: draft
links:
  pr: []
---
# Issue sharing an id with its spec
MD

  # Multi-writer case (SPEC-0057 edge case: 3+ carriers in one group) — proves
  # the Count column and grouping are not hardcoded to exactly two carriers.
  cat > docs/dupid/SPEC-9402-triple-a.md <<'MD'
---
id: dupid-collision-triple
type: spec
status: draft
links:
  pr: []
---
# First of three docs sharing one id
MD
  cat > docs/dupid/ISSUE-9402-triple-b.md <<'MD'
---
id: dupid-collision-triple
type: issue
status: draft
links:
  pr: []
---
# Second of three docs sharing one id
MD
  cat > docs/dupid/CHANGE-9402-triple-c.md <<'MD'
---
id: dupid-collision-triple
type: change
status: draft
links:
  pr: []
---
# Third of three docs sharing one id
MD

  git add docs/dupid && git commit -qm "test: duplicate-doc-id fixtures (SPEC-0057)"
  log_pass "Duplicate-doc-id fixture ready"
}

setup_dupid_clean_fixture() {
  log_info "Setting up duplicate-doc-id negative-control fixture (SPEC-0057)..."
  mkdir -p "$TEST_DIR/docs/dupid-clean"
  cd "$TEST_DIR"

  # Negative control (Spec-AC-02): a correctly `spec-`-prefixed change+spec
  # pair — change id X, spec id spec-X — has two DISTINCT effective ids and
  # must never be flagged.
  cat > docs/dupid-clean/CHANGE-9410-cleanpair.md <<'MD'
---
id: dupid-cleanpair
type: change
status: draft
links:
  pr: []
---
# Change (the intake side of a correctly prefixed pair)
MD
  cat > docs/dupid-clean/SPEC-9410-cleanpair.md <<'MD'
---
id: spec-dupid-cleanpair
type: spec
status: draft
links:
  requirement: dupid-cleanpair
  pr: []
---
# Spec (correctly spec-prefixed; distinct effective id from its intake)
MD

  # Slug-vs-fileId of the SAME doc (structural exclusion, Spec-AC-02a): the
  # frontmatter id differs from this doc's own numbered fileId (SPEC-9411).
  # One docs[] record, one effective id — never a self-collision.
  cat > docs/dupid-clean/SPEC-9411-sluginfo.md <<'MD'
---
id: dupid-standalone-slug
type: spec
status: draft
links:
  pr: []
---
# Slug id differs from this doc's own numbered fileId (SPEC-9411) — not a duplicate
MD

  git add docs/dupid-clean && git commit -qm "test: duplicate-doc-id negative-control fixture (SPEC-0057)"
  log_pass "Duplicate-doc-id negative-control fixture ready"
}

test_spec0057_duplicate_id_flagged() {  # TEST-101 / Spec-AC-01
  log_info "Test: two docs sharing one frontmatter id are flagged, naming id + both paths; verdict NEEDS-TRIAGE (TEST-101)..."
  run_audit --no-event --path docs/dupid > "$TEST_DIR/dupid.log"
  assert_contains "$TEST_DIR/dupid.log" "### Duplicate doc ids"
  grep -F "dupid-collision-x" "$TEST_DIR/dupid.log" | grep -qF "SPEC-9401-collision.md" \
    || log_fail "TEST-101: duplicate-doc-id row must name id dupid-collision-x + SPEC-9401 path"
  grep -F "dupid-collision-x" "$TEST_DIR/dupid.log" | grep -qF "ISSUE-9401-collision.md" \
    || log_fail "TEST-101: duplicate-doc-id row must name id dupid-collision-x + ISSUE-9401 path"
  # multi-writer (3 carriers): the Count column reflects 3, not hardcoded to 2
  grep -F "dupid-collision-triple" "$TEST_DIR/dupid.log" | grep -qF "| 3 |" \
    || log_fail "TEST-101: a 3-carrier group must report Count 3"
  assert_contains "$TEST_DIR/dupid.log" "Verdict: NEEDS-TRIAGE"
  log_pass "Duplicate frontmatter id flagged with id + all carrying paths (TEST-101)"
}

test_spec0057_no_false_positive() {  # TEST-102 / Spec-AC-02
  log_info "Test: unique-id corpus incl. spec-prefixed pair + slug-vs-fileId doc -> zero findings, CLEAN (TEST-102)..."
  run_audit --no-event --path docs/dupid-clean > "$TEST_DIR/dupid-clean.log"
  assert_contains "$TEST_DIR/dupid-clean.log" "### Duplicate doc ids: 0"
  assert_contains "$TEST_DIR/dupid-clean.log" "Verdict: CLEAN"
  log_pass "Unique-id corpus reports zero duplicate-doc-id findings (TEST-102)"
}

test_spec0057_check_exit_code_unchanged() {  # TEST-103 / Spec-AC-03
  log_info "Test: duplicate-doc-id is verdict-only, not hardFail — --check exits 0 on a duplicate-bearing fixture (TEST-103)..."
  run_audit --check --no-event --path docs/dupid > "$TEST_DIR/dupid-check.log" \
    || log_fail "TEST-103: --check must exit 0 on a duplicate-doc-id-only fixture (verdict-only, not hardFail)"
  assert_contains "$TEST_DIR/dupid-check.log" "### Duplicate doc ids"
  log_pass "Duplicate-doc-id detection is verdict-only; --check exit code unchanged (TEST-103)"
}

test_spec0057_real_repo_known_collisions() {  # TEST-104 / Spec-AC-04
  log_info "Test: real repo is free of duplicate-doc-id collisions after remediation; --check --strict exits 0 (TEST-104)..."
  # The 3 legacy collisions SPEC-0057's detector originally surfaced
  # (prompt-diet-byte-budget-true-up, secrets-preflight-env-multiline,
  # spec-lint-duplicate-ac-id — specs created without the spec- prefix) were
  # remediated (ISSUE-0015: spec ids -> spec-<slug> + telemetry backfill). This
  # control now guards that the detector runs on the real repo and finds NONE.
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --no-event > "$TEST_DIR/s57-real.log" 2>&1) \
    || log_fail "real-repo docs-audit must exit 0: $(tail -5 "$TEST_DIR/s57-real.log")"
  assert_contains "$TEST_DIR/s57-real.log" "### Duplicate doc ids: 0"
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$TEST_DIR/s57-check.log" 2>&1) \
    || log_fail "TEST-104: real-repo --check --strict must exit 0: $(tail -10 "$TEST_DIR/s57-check.log")"
  log_pass "Real repo has zero duplicate-doc-id collisions post-remediation; CI exit 0 (TEST-104)"
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
  test_issue0001_frontmatter_crlf_tolerance
  test_issue0001_actable_crlf_tolerance
  test_issue0001_posix_paths_noop
  test_issue0001_crlf_corpus_buckets
  test_issue0001_gitattributes
  test_issue0001_legacy_ratio_guard
  test_issue0001_no_regression_real_repo
  test_issue0001_posix_helper
  test_spec0010_committed_index_idempotent
  test_spec0010_index_git_state_invariant
  test_spec0010_audit_companion_gitignored
  test_spec0010_ac_row_level_not_whole_doc
  test_spec0010_ac_qualifier_normalized
  test_spec0010_ac_genuine_invalid_flagged_both
  test_spec0011_gate_missing_table
  test_spec0011_gate_fail_conditions
  test_spec0011_gate_pass_and_unknown
  test_spec0011_nearmiss_evidence_column
  test_spec0011_nearmiss_both_surfaces
  test_spec0011_review_claim_unbacked
  test_spec0011_review_claim_backed
  test_spec0011_event_types
  test_spec0011_missing_close_telemetry
  test_spec0011_closeout_prompts_wired
  test_spec0011_config_close_gate
  test_spec0011_hook_close_gate
  test_spec0011_hook_parity_grep
  test_spec0011_read_only
  test_spec0011_gate_honors_config_review_by_methods
  test_spec0011_hook_gates_staged_not_worktree
  test_spec0011_work_item_closed_requires_fields
  test_spec0011_review_artifact_boundary
  test_spec0011_regression
  test_change0007_lint_stray_markup
  test_change0007_lint_unbalanced_fence
  test_change0007_lint_placeholder
  test_change0007_lint_negative_controls
  test_change0007_lint_degenerate_fixtures
  test_change0007_lint_promotion_pair
  test_change0007_lint_body_file_predicate
  test_change0007_hook_body_lint
  test_change0007_regression
  test_change0007_hook_config_staged
  test_change0007_hook_space_filename
  test_change0007_lint_span_edges
  test_index_continue_on_error
  test_change0012_gate_slug_draft
  test_change0012_draft_scanned_nonvacuous
  test_change0012_gate_resolution_order
  test_change0012_gate_ambiguous_id
  test_change0012_allocation_durability
  test_change0012_regression
  test_l1gate_lean_gate_pass
  test_l1gate_missing_justification
  test_l1gate_done_lean_clean
  test_l1gate_l2_regression
  test_l1gate_garbage_level_fail_closed
  test_l1gate_pipe_drop_reconciled
  test_l1gate_done_drift_pipe_drop
  test_delta3_provenance_drift
  test_delta3_empty_canonical_control
  test_change0027_delivery_commit_flags
  test_change0027_intake_only_not_flagged
  test_change0027_nondelivery_mentions_not_flagged
  test_change0027_sibling_numbered_boundary
  test_change0027_sibling_slug_boundary
  test_change0027_ac_evidence_event_flags
  test_change0027_ac_table_signal
  test_change0027_digest_and_event
  test_change0027_precedence_over_stale
  test_change0027_frozen_draft_probe
  test_change0027_ac_table_tdd_log_only_not_flagged
  test_change0027_index_seam
  test_change0027_quick_mode_skips_probe
  test_change0027_doc_surfaces_mention_false_open
  test_change0028_mixed_cell_git_hash_flags
  test_change0028_mixed_cell_pr_ref_flags
  test_change0028_mixed_cell_prose_not_flagged
  test_change0028_mixed_cell_unresolvable_hash_not_flagged
  test_change0028_spec0039_verbatim_replica_not_flagged
  test_change0028_arm_b_fileid_ac_evidence_flags
  test_change0028_arm_b_inflight_discriminator_guard
  test_change0028_arm_c_work_item_closed_flags
  test_change0028_real_repo_clean
  test_change0028_userguide_mentions_work_item_closed
  test_fometrics_flush_arm
  test_fometrics_supersession
  test_fometrics_supersession_delivery_arms
  setup_dupid_fixture
  test_spec0057_duplicate_id_flagged
  test_spec0057_check_exit_code_unchanged
  setup_dupid_clean_fixture
  test_spec0057_no_false_positive
  test_spec0057_real_repo_known_collisions
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
