#!/usr/bin/env bash
#
# Test: product docs as a capability-keyed SECOND DOC FAMILY on the shared
# doc-engine primitives (fixes #189) — CHANGE-0088-product-docs-capability-
# model / SPEC-0105-spec-product-docs-capability-model.md, TEST-001..005,
# TEST-012, TEST-013.
#
# Covers the shared DOC_FAMILIES scan-admit primitive
# (.aai/scripts/lib/docs-model.mjs) consumed by BOTH docs-audit-core.mjs
# (scanAuditDocs) and generate-docs-index.mjs — one config, two consumers, no
# parallel product scan/index/drift engine.
#
#   - TEST-001 (Spec-AC-01, unit): DOC_TYPE_ENUM has "product" and
#     DOC_STATUS_ENUM has "current".
#   - TEST-002 (Spec-AC-01, integration, RED-first live #189 repro): a
#     template-shaped product doc -> docs-audit --check --strict exit 0,
#     classified tracked-open/aligned (no orphan/type-warning/violation).
#   - TEST-003 (Spec-AC-01, integration): the same fixture appears under
#     docs/INDEX.md "## Product" after generate-docs-index.
#   - TEST-004 (Spec-AC-02, integration, SEAM-1): slugFamilyForPath admits
#     BOTH a canonical and a product path; ONE scan run classifies the SAME
#     product fixture both audited-clean and indexed (not two isolated mocks).
#   - TEST-005 (Spec-AC-02, unit): anti-duplication proof — `git grep -c
#     generate-product-docs` == 0 in the real repo; deleting the product
#     DOC_FAMILIES entry drops the product doc from BOTH engines in lockstep.
#   - TEST-012 (Spec-AC-04, unit): each of the real repo's 12 migrated
#     docs/product/*.md carries capability==its own filename slug + a
#     non-empty delivered_by, is not a placeholder, AND (PR-time baseline)
#     its body is byte-identical to the git HEAD blob's body region.
#   - TEST-013 (Spec-AC-05, e2e): a fresh user_visible ride — template ->
#     docs/product/<capability>.md -> audit clean + INDEX Product row + close
#     gate pass + delivered_by stamped (the inverse of #189).
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-005: docs/product/ present but the
#                                      registry entry deleted -> zero admitted
#   - zero-remainder               -> TEST-002: single fixture, exact scan count
#   - multi-source/multi-writer    -> TEST-004: canonical + product in ONE scan
#   - mid-operation failure         -> covered by TEST-006..009 in
#                                      test-aai-close-work-item.sh (this
#                                      suite is scan/index-level, not the
#                                      close-ceremony transaction)
#   - negative control              -> TEST-005: the SAME fixture with the
#                                      registry entry present (control) vs
#                                      deleted (must drop to zero)
#
# ALL fixtures are throwaway git repos under a mktemp dir, cleaned on EXIT.
# The real repo's docs/ tree is NEVER mutated by any test (TEST-005/012 read
# it read-only; TEST-013 runs entirely inside a fixture).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-product-docs.sh            # run all tests
#   bash tests/skills/test-aai-product-docs.sh test_002_repro
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-product-docs"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
GENERATE_INDEX="$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs"
CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
DOCS_MODEL_LIB="$PROJECT_ROOT/.aai/scripts/lib/docs-model.mjs"

FAILED=0

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  [[ -f "$GENERATE_INDEX" ]] || log_fail "generate-docs-index.mjs not found: $GENERATE_INDEX"
  [[ -f "$DOCS_MODEL_LIB" ]] || log_fail "docs-model.mjs not found: $DOCS_MODEL_LIB"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-product-docs-test.XXXXXX")"
}

# --- fixture repo builder ----------------------------------------------------

# new_fixture_repo <name> -> prints the fixture repo's absolute path. Vendors
# the real engine scripts + lib (so a registry edit made INSIDE the fixture
# never touches the real repo, TEST-005), and a throwaway git repo with an
# initial commit so the audit's git probes have something to read.
new_fixture_repo() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/.aai/scripts/lib" "$dir/docs/issues" "$dir/docs/specs" \
    "$dir/docs/canonical" "$dir/docs/product" "$dir/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$dir/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" "$dir/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" "$dir/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/close-work-item.mjs" "$dir/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$dir/.aai/scripts/lib/"
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

# write_product_doc <dir> <capability> [<delivered_by_ref>] — a REAL
# (non-placeholder), template-shaped product doc: every required section
# filled, capability == filename slug, a non-empty delivered_by.
write_product_doc() {
  local dir="$1" cap="$2" ref="${3:-$2}"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$cap.md" <<EOF
---
id: $cap
type: product
capability: $cap
status: current
delivered_by:
  - $ref
spec: docs/specs/SPEC-9999-spec-$cap.md
updated: 2026-01-01
---

# Fixture Feature $cap

## What it does

Functional description for the $cap fixture product doc.

## How to use it

Usage instructions for $cap.

## Data model

None.

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$cap.md
- Spec: docs/specs/SPEC-9999-spec-$cap.md
EOF
}

# write_canonical_doc <dir> <domain> — a minimal, schema-valid canonical doc
# (validateCanonicalFrontmatter: type canonical + domain + non-empty sources).
write_canonical_doc() {
  local dir="$1" domain="$2"
  mkdir -p "$dir/docs/canonical"
  cat > "$dir/docs/canonical/$domain.md" <<EOF
---
id: $domain
type: canonical
domain: $domain
status: accepted
sources:
  - docs/issues/CHANGE-DRAFT-$domain.md
---

# $domain (canonical)

## Overview / Intent

Fixture canonical doc for the $domain domain.

## Requirements

## UI

None.

## Processes / Behavior

None.

## Data model

None.

## Superseded decisions

None.
EOF
}

# write_user_visible_change_doc <path> <id> <capability> — a user_visible
# change intake carrying `capability:` (SEAM-2).
write_user_visible_change_doc() {
  local path="$1" id="$2" cap="$3"
  cat > "$path" <<EOF
---
id: $id
type: change
status: draft
user_visible: true
capability: $cap
links:
  pr: []
  commits: []
---

# Change — Fixture $id (user_visible, capability=$cap)

## Summary
- fixture doc for product-docs-capability-model tests.

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

file_size() { wc -c < "$1" | tr -d ' '; }

# --- TEST-001 (Spec-AC-01, unit): enum membership ----------------------------

test_001_enum_membership() {
  log_info "Test: DOC_TYPE_ENUM has 'product' and DOC_STATUS_ENUM has 'current' (TEST-001)..."
  local probe="$TEST_DIR/t001-probe.mjs"
  cat > "$probe" <<PROBE
import { DOC_TYPE_ENUM, DOC_STATUS_ENUM } from '$DOCS_MODEL_LIB';
if (!DOC_TYPE_ENUM.has('product')) { console.error('DOC_TYPE_ENUM missing product'); process.exit(1); }
if (!DOC_STATUS_ENUM.has('current')) { console.error('DOC_STATUS_ENUM missing current'); process.exit(1); }
console.log('OK');
PROBE
  node "$probe" > "$TEST_DIR/t001.out" 2>&1 \
    || { log_fail "t001: enum membership check failed: $(cat "$TEST_DIR/t001.out")"; return; }
  log_pass "DOC_TYPE_ENUM has product; DOC_STATUS_ENUM has current (TEST-001)"
}

# --- TEST-002 (Spec-AC-01, integration, RED-first live #189 repro) ----------

test_002_repro() {
  log_info "Test: #189 repro — a template-shaped product doc audits clean, classified tracked-open/aligned (TEST-002)..."
  local dir; dir=$(new_fixture_repo "t002")
  write_product_doc "$dir" "widget-export"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t002.out" code=0
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/product/widget-export.md > "$out" 2>&1 ) || code=$?
  [[ "$code" == "0" ]] || { log_fail "t002: docs-audit --check --strict must exit 0 on a template-shaped product doc, got $code: $(cat "$out")"; return; }
  grep -qF "Scanned: 1 docs" "$out" \
    || { log_fail "t002: expected 'Scanned: 1 docs' (product doc admitted), got: $(cat "$out")"; return; }

  local list="$TEST_DIR/t002-list.out"
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --list --no-event --path docs/product/widget-export.md > "$list" 2>&1 )
  grep -qF "| widget-export | tracked-open | current | aligned |" "$list" \
    || { log_fail "t002: expected widget-export classified tracked-open/current/aligned, got: $(cat "$list")"; return; }
  grep -qF "Orphans: 0" "$list" || { log_fail "t002: must be zero orphans: $(cat "$list")"; return; }

  log_pass "#189 repro: template-shaped product doc audits clean, tracked-open/aligned (TEST-002)"
}

# --- TEST-003 (Spec-AC-01, integration): INDEX Product section --------------

test_003_index_product_section() {
  log_info "Test: the product fixture appears under docs/INDEX.md '## Product' after generate-docs-index (TEST-003)..."
  local dir; dir=$(new_fixture_repo "t003")
  write_product_doc "$dir" "widget-export"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t003-gen.out" code=0
  ( cd "$dir" && node .aai/scripts/generate-docs-index.mjs > "$out" 2>&1 ) || code=$?
  [[ "$code" == "0" ]] || { log_fail "t003: generate-docs-index.mjs failed: $(cat "$out")"; return; }

  grep -qF "## Product (1)" "$dir/docs/INDEX.md" \
    || { log_fail "t003: expected '## Product (1)' section header, got: $(cat "$dir/docs/INDEX.md")"; return; }
  grep -qF "docs/product/widget-export.md" "$dir/docs/INDEX.md" \
    || log_fail "t003: expected widget-export.md listed under Product"

  log_pass "Product fixture indexed under docs/INDEX.md '## Product' (TEST-003)"
}

# --- TEST-004 (Spec-AC-02, integration, SEAM-1) ------------------------------

test_004_seam1_dual_family() {
  log_info "Test: slugFamilyForPath admits both a canonical and a product path; ONE scan audits + indexes both (SEAM-1, TEST-004)..."
  local probe="$TEST_DIR/t004-probe.mjs"
  cat > "$probe" <<PROBE
import { slugFamilyForPath } from '$DOCS_MODEL_LIB';
const c = slugFamilyForPath('docs/canonical/auth.md');
const p = slugFamilyForPath('docs/product/widget-export.md');
if (!c || c.type !== 'canonical') { console.error('canonical path not admitted: ' + JSON.stringify(c)); process.exit(1); }
if (!p || p.type !== 'product') { console.error('product path not admitted: ' + JSON.stringify(p)); process.exit(1); }
if (slugFamilyForPath('docs/issues/CHANGE-0001-x.md') !== null) { console.error('non-family path must not be admitted'); process.exit(1); }
console.log('OK');
PROBE
  node "$probe" > "$TEST_DIR/t004-unit.out" 2>&1 \
    || { log_fail "t004: slugFamilyForPath unit check failed: $(cat "$TEST_DIR/t004-unit.out")"; return; }

  local dir; dir=$(new_fixture_repo "t004")
  write_canonical_doc "$dir" "widget-domain"
  write_product_doc "$dir" "widget-export"
  commit_fixture_docs "$dir"

  local audit="$TEST_DIR/t004-audit.out" code=0
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$audit" 2>&1 ) || code=$?
  [[ "$code" == "0" ]] || { log_fail "t004: combined canonical+product fixture must audit clean, got $code: $(cat "$audit")"; return; }
  grep -qF "Scanned: 2 docs" "$audit" \
    || { log_fail "t004: expected both fixture docs scanned in ONE run, got: $(cat "$audit")"; return; }

  local idx="$TEST_DIR/t004-idx.out"
  ( cd "$dir" && node .aai/scripts/generate-docs-index.mjs > "$idx" 2>&1 )
  grep -qF "widget-domain" "$dir/docs/INDEX.md" || { log_fail "t004: canonical fixture not indexed"; return; }
  grep -qF "docs/product/widget-export.md" "$dir/docs/INDEX.md" || log_fail "t004: product fixture not indexed"

  log_pass "SEAM-1: slugFamilyForPath admits both axes; one scan audits+indexes both (TEST-004)"
}

# --- TEST-005 (Spec-AC-02, unit): anti-duplication proof ---------------------

test_005_anti_duplication() {
  log_info "Test: anti-duplication — no generate-product-docs.mjs SCRIPT anywhere; deleting the product registry entry drops it from BOTH engines (TEST-005)..."
  # Assert no parallel PRODUCT ENGINE FILE exists (the real anti-goal). Match a
  # FILENAME, never prose: this spec + this test legitimately mention the string
  # 'generate-product-docs' as the anti-goal, so a content grep would self-trip
  # once committed (Validation finding — was green only while untracked).
  local engine_files
  engine_files=$(git -C "$PROJECT_ROOT" ls-files '*generate-product-docs*' 2>/dev/null | wc -l | tr -d ' ')
  [[ "$engine_files" == "0" ]] \
    || log_fail "t005: no generate-product-docs.* engine file may exist (parallel engine = anti-goal), found $engine_files"

  local dir; dir=$(new_fixture_repo "t005")
  write_product_doc "$dir" "widget-export"
  commit_fixture_docs "$dir"

  # control: with the registry entry present, the fixture is admitted by both.
  local audit_before="$TEST_DIR/t005-audit-before.out"
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --no-event --path docs/product/widget-export.md > "$audit_before" 2>&1 )
  grep -qF "Scanned: 1 docs" "$audit_before" \
    || { log_fail "t005 control: fixture must be scanned before the registry edit: $(cat "$audit_before")"; return; }
  ( cd "$dir" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1 )
  grep -qF "## Product (1)" "$dir/docs/INDEX.md" \
    || { log_fail "t005 control: fixture must be indexed before the registry edit"; return; }

  # delete the product DOC_FAMILIES entry INSIDE the fixture's vendored copy
  # (never touches the real repo's docs-model.mjs).
  node -e "
    const fs = require('fs');
    const p = '$dir/.aai/scripts/lib/docs-model.mjs';
    let s = fs.readFileSync(p, 'utf8');
    const before = s;
    s = s.replace(/export const DOC_FAMILIES = \[[\s\S]*?\];/,
      \"export const DOC_FAMILIES = [ { type: 'canonical', dir: 'docs/canonical/', indexSection: 'Canonical layer' } ];\");
    if (s === before) { console.error('registry literal not found — cannot rewrite'); process.exit(1); }
    fs.writeFileSync(p, s);
  " || { log_fail "t005: could not rewrite the fixture's DOC_FAMILIES registry"; return; }

  local audit_after="$TEST_DIR/t005-audit-after.out"
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --no-event --path docs/product/widget-export.md > "$audit_after" 2>&1 )
  grep -qF "Scanned: 0 docs" "$audit_after" \
    || { log_fail "t005: deleting the registry entry must drop the product doc from docs-audit's scan, got: $(cat "$audit_after")"; return; }

  ( cd "$dir" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1 )
  if grep -qF "## Product" "$dir/docs/INDEX.md"; then
    log_fail "t005: deleting the registry entry must drop the Product section from generate-docs-index too, got: $(cat "$dir/docs/INDEX.md")"
    return
  fi

  log_pass "Anti-duplication proof: no generate-product-docs.mjs; one registry edit drops product from BOTH engines (TEST-005)"
}

# --- TEST-012 (Spec-AC-04, unit): migrated docs — structural + body-diff ----

test_012_migration_body_diff_zero() {
  log_info "Test: all 12 real docs/product/*.md carry capability==own slug + non-empty delivered_by, are non-placeholder, and their body is byte-identical to the git HEAD blob's body (TEST-012)..."
  local probe="$TEST_DIR/t012-probe.mjs"
  cat > "$probe" <<PROBE
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { parseFrontmatter } from '$DOCS_MODEL_LIB';
import { missingProductSections } from '$PROJECT_ROOT/.aai/scripts/lib/product-doc.mjs';

const root = '$PROJECT_ROOT';
const dir = path.join(root, 'docs/product');
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.md'));
if (files.length < 1) { console.error('expected at least one product doc, found ' + files.length); process.exit(1); }
// No hardcoded count floor: the capability model consolidates (telemetry
// trio -> one doc, CHANGE product-capability-refinements) and grows over
// time; assert the per-doc invariants below over whatever the live set is.

const bodyOf = (s) => {
  const parts = String(s).split('---\n');
  return parts.slice(2).join('---\n');
};

let bad = [];
for (const f of files) {
  const slug = f.replace(/\.md\$/, '');
  const abs = path.join(dir, f);
  const content = fs.readFileSync(abs, 'utf8');
  const fm = parseFrontmatter(content);
  if (String(fm.capability ?? '') !== slug) bad.push(f + ': capability != own slug (' + fm.capability + ')');
  if (!Array.isArray(fm.delivered_by) || fm.delivered_by.length === 0) bad.push(f + ': empty/missing delivered_by');
  const missing = missingProductSections(content);
  if (missing.length > 0) bad.push(f + ': placeholder section(s) ' + missing.join(','));
  let before;
  try {
    before = execSync('git show HEAD:docs/product/' + f, { cwd: root, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
  } catch {
    before = null; // untracked (new file, no HEAD blob yet) -- nothing to diff
  }
  if (before != null && bodyOf(before) !== bodyOf(content)) {
    bad.push(f + ': body differs from git HEAD blob (prose loss risk)');
  }
}
if (bad.length > 0) { console.error(bad.join('\\n')); process.exit(1); }
console.log('OK ' + files.length + ' product docs verified');
PROBE
  node "$probe" > "$TEST_DIR/t012.out" 2>&1 \
    || { log_fail "t012: migration structural/body-diff check failed:\n$(cat "$TEST_DIR/t012.out")"; return; }
  log_pass "$(cat "$TEST_DIR/t012.out") (TEST-012)"
}

# --- TEST-013 (Spec-AC-05, e2e): fresh ride, inverse of #189 ----------------

test_013_fresh_ride_e2e() {
  log_info "Test: fresh user_visible ride -- template-shaped doc -> audit clean + INDEX Product + close gate pass + delivered_by stamped (inverse of #189, TEST-013)..."
  local dir; dir=$(new_fixture_repo "t013")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t013.md" "t013-slug" "cap-t013"
  write_product_doc "$dir" "cap-t013" "seed-ref"
  commit_fixture_docs "$dir"

  # audit clean
  local audit="$TEST_DIR/t013-audit.out" code=0
  ( cd "$dir" && node .aai/scripts/docs-audit.mjs --check --strict --no-event > "$audit" 2>&1 ) || code=$?
  [[ "$code" == "0" ]] || { log_fail "t013: fresh-ride fixture must audit clean, got $code: $(cat "$audit")"; return; }

  # indexed under Product
  ( cd "$dir" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1 )
  grep -qF "docs/product/cap-t013.md" "$dir/docs/INDEX.md" \
    || { log_fail "t013: capability doc must be indexed under Product"; return; }

  # close gate pass + delivered_by stamped
  local close_out="$TEST_DIR/t013-close.out" close_err="$TEST_DIR/t013-close.err" close_code=0
  ( cd "$dir" && node .aai/scripts/close-work-item.mjs --ref t013-slug --pr 13 --commit e2e0013 > "$close_out" 2> "$close_err" ) || close_code=$?
  [[ "$close_code" == "0" ]] || { log_fail "t013: close-work-item must exit 0 (gate pass), got $close_code: $(cat "$close_err")"; return; }
  if grep -qi 'product-doc gate' "$close_err"; then
    log_fail "t013: a real, complete product doc must not warn/refuse: $(cat "$close_err")"
    return
  fi

  grep -qF 't013-slug' "$dir/docs/product/cap-t013.md" \
    || { log_fail "t013: delivered_by must be stamped with the closing ref t013-slug: $(cat "$dir/docs/product/cap-t013.md")"; return; }

  log_pass "Fresh user_visible ride: template -> audit clean + INDEX Product + gate pass + delivered_by stamped (inverse of #189, TEST-013)"
}

# --- TEST-014 (validation-cost-calibration spec TEST-013/Spec-AC-06) -------
# The real docs/product/validation-cost-calibration.md this scope ships:
# missingProductSections must return empty, and a fixture ref carrying this
# slug + user_visible true must resolve gate severity 'none' via the real
# close-work-item.mjs end-to-end (mirrors TEST-013's fresh-ride e2e shape,
# against the REAL product doc rather than a synthetic fixture body).

test_014_validation_cost_calibration_product_doc() {
  log_info "Test: docs/product/validation-cost-calibration.md is a real, non-placeholder product doc; close-work-item gate severity is none for a fixture ref carrying this slug (spec TEST-013)..."
  local real="$PROJECT_ROOT/docs/product/validation-cost-calibration.md"
  [[ -f "$real" ]] || { log_fail "t014: docs/product/validation-cost-calibration.md does not exist"; return; }

  local probe="$TEST_DIR/t014-probe.mjs"
  cat > "$probe" <<PROBE
import fs from 'node:fs';
import { missingProductSections } from '$PROJECT_ROOT/.aai/scripts/lib/product-doc.mjs';
const content = fs.readFileSync('$real', 'utf8');
const missing = missingProductSections(content);
if (missing.length > 0) { console.error('missing/placeholder sections: ' + missing.join(',')); process.exit(1); }
console.log('OK missingProductSections empty');
PROBE
  node "$probe" > "$TEST_DIR/t014.out" 2>&1 \
    || { log_fail "t014: missingProductSections must be empty for the real doc: $(cat "$TEST_DIR/t014.out")"; return; }

  # Gate severity: fixture ref carrying this exact slug + user_visible true,
  # closed through the REAL close-work-item.mjs against a fixture repo whose
  # docs/product/validation-cost-calibration.md is a COPY of the real file
  # (never mutate the real one; the fixture proves the gate resolves 'none').
  local dir; dir=$(new_fixture_repo "t014")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-9014-t014.md" "t014-slug" "validation-cost-calibration"
  cp "$real" "$dir/docs/product/validation-cost-calibration.md"
  commit_fixture_docs "$dir"

  local close_out="$TEST_DIR/t014-close.out" close_err="$TEST_DIR/t014-close.err" close_code=0
  ( cd "$dir" && node .aai/scripts/close-work-item.mjs --ref t014-slug --pr 14 --commit e2e0014 > "$close_out" 2> "$close_err" ) || close_code=$?
  [[ "$close_code" == "0" ]] || { log_fail "t014: close-work-item must exit 0 (gate severity none), got $close_code: $(cat "$close_err")"; return; }
  if grep -qi 'product-doc gate' "$close_err"; then
    log_fail "t014: gate severity must be none for this slug — no warn/refuse expected: $(cat "$close_err")"
    return
  fi

  log_pass "docs/product/validation-cost-calibration.md: missingProductSections empty, close-work-item gate severity none (TEST-014/spec TEST-013)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [[ $# -gt 0 ]]; then
    "$1"
    if [[ "$FAILED" == "1" ]]; then
      echo "=== $TEST_NAME: SELECTED TEST FAILED ($1) ==="
      exit 1
    fi
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    exit 0
  fi

  test_001_enum_membership
  test_002_repro
  test_003_index_product_section
  test_004_seam1_dual_family
  test_005_anti_duplication
  test_012_migration_body_diff_zero
  test_013_fresh_ride_e2e
  test_014_validation_cost_calibration_product_doc

  if [[ "$FAILED" == "1" ]]; then
    echo "=== $TEST_NAME: SOME TESTS FAILED ==="
    exit 1
  fi
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
