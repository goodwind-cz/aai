#!/usr/bin/env bash
#
# Test: USER_GUIDE "Delivered features (generated)" rollup generator
# (docs/specs/SPEC-0092-spec-product-docs-enforced.md D4, TEST-007..010).
#
# Covers .aai/scripts/generate-userguide-rollup.mjs — a NEW generator that
# renders one marker-delimited section into docs/USER_GUIDE.md from
# docs/product/*.md: containment (bytes outside the markers are untouched),
# byte-idempotence (no volatile content inside the marked region), sort by
# frontmatter `updated` descending, and placeholder-doc exclusion (D2).
#
#   - TEST-007 (Spec-AC-03): containment — bytes OUTSIDE the markers are
#     byte-identical before/after a run; markers absent on first run appends
#     the block at EOF.
#   - TEST-008 (Spec-AC-03): byte-idempotence — a second run with unchanged
#     inputs produces a byte-identical docs/USER_GUIDE.md (no timestamp inside
#     the marked region).
#   - TEST-009 (Spec-AC-03): sorted by frontmatter `updated` descending.
#   - TEST-010 (Spec-AC-03, D2): a product doc that fails the placeholder
#     predicate (unfilled Data model section) is EXCLUDED from the rendered
#     block; a real doc with an explicit "None." section still renders.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-011: zero product docs -> a stable
#                                      empty-state block, still marker-contained
#   - zero-remainder               -> TEST-008: second run, nothing left to change
#   - multi-source/multi-writer    -> TEST-009: 3 product docs, one rollup output
#   - mid-operation failure         -> covered by the close-work-item negative
#                                      control (TEST-012 there); this suite is
#                                      unit-level on the generator alone
#   - negative control              -> TEST-010: the placeholder doc must NOT
#                                      appear anywhere in the rendered block
#
# ALL fixtures are throwaway directories under a mktemp dir (docs/product/ +
# docs/USER_GUIDE.md), cleaned on EXIT. The real repo's docs/ is NEVER touched
# (the generator always runs with cwd = the fixture dir).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-userguide-rollup.sh            # run all tests
#   bash tests/skills/test-aai-userguide-rollup.sh test_007_containment
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-userguide-rollup"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

ROLLUP_SCRIPT="$PROJECT_ROOT/.aai/scripts/generate-userguide-rollup.mjs"

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
  # NOTE: ROLLUP_SCRIPT is intentionally NOT required here — every TEST-xxx
  # in this suite RED-naturally (invocation fails) while the generator does
  # not yet exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-userguide-rollup-test.XXXXXX")"
}

# new_fixture_dir <name> -> prints the fixture dir's absolute path (docs/product/
# ready, docs/USER_GUIDE.md NOT created — a caller seeds it per-test).
new_fixture_dir() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/product"
  echo "$dir"
}

# write_product_doc <dir> <slug> <updated> <title> [<data_model_body>]
# Writes a REAL (non-placeholder) product doc: every required section filled.
# data_model_body defaults to "None." (must count as REAL per D2).
write_product_doc() {
  local dir="$1" slug="$2" updated="$3" title="$4" data_model="${5:-None.}"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: $updated
---

# $title

## What it does

Functional description for $slug. This is the first paragraph of prose that
the rollup renders as the summary line for this feature.

Second paragraph, must not appear in the rendered summary.

## How to use it

Some usage instructions for $slug.

## Data model

$data_model

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_placeholder_product_doc <dir> <slug> <updated> <title> — a product doc
# whose Data model section still carries the unfilled template token (D2
# placeholder) — must be EXCLUDED from the rendered rollup.
write_placeholder_product_doc() {
  local dir="$1" slug="$2" updated="$3" title="$4"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: $updated
---

# $title

## What it does

Functional description for $slug.

## How to use it

Usage.

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

run_rollup() {
  local dir="$1" outfile="$2" errfile="$3"
  local code=0
  ( cd "$dir" && node "$ROLLUP_SCRIPT" > "$outfile" 2> "$errfile" ) || code=$?
  echo "$code"
}

file_size() { wc -c < "$1" | tr -d ' '; }

# --- TEST-007 (Spec-AC-03): containment --------------------------------------

test_007_containment() {
  log_info "Test: rollup writes only between markers -- bytes outside untouched; markers absent on first run append at EOF (TEST-007)..."
  local dir; dir=$(new_fixture_dir "t007")
  write_product_doc "$dir" "feature-a" "2026-01-01" "Feature A"

  cat > "$dir/docs/USER_GUIDE.md" <<'EOF'
# AAI User Guide

Hand-written intro paragraph that must never be touched.

## Getting Started

Hand-written getting-started content.
EOF
  local before; before=$(cat "$dir/docs/USER_GUIDE.md")

  local out="$TEST_DIR/t007.out" err="$TEST_DIR/t007.err" code
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t007: generator exited $code: $(cat "$err")"

  local after; after=$(cat "$dir/docs/USER_GUIDE.md")
  [[ "$after" == "$before"* ]] \
    || log_fail "t007: hand-written content before the markers was altered"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:BEGIN' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t007: BEGIN marker not appended on first run"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:END -->' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t007: END marker not appended on first run"
  grep -qF 'Feature A' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t007: rendered block missing the product doc title"

  # Now re-run with EXTRA hand-written content appended after the markers --
  # containment must preserve bytes on BOTH sides of the marked region.
  printf '\n## Troubleshooting\n\nHand-written troubleshooting tail.\n' >> "$dir/docs/USER_GUIDE.md"
  local before2; before2=$(cat "$dir/docs/USER_GUIDE.md")
  local head_before; head_before=$(sed -n '1,5p' "$dir/docs/USER_GUIDE.md")
  local tail_before; tail_before=$(tail -3 "$dir/docs/USER_GUIDE.md")

  write_product_doc "$dir" "feature-a" "2026-01-02" "Feature A Renamed"
  out="$TEST_DIR/t007b.out"; err="$TEST_DIR/t007b.err"
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t007b: second run exited $code: $(cat "$err")"

  local head_after; head_after=$(sed -n '1,5p' "$dir/docs/USER_GUIDE.md")
  local tail_after; tail_after=$(tail -3 "$dir/docs/USER_GUIDE.md")
  [[ "$head_after" == "$head_before" ]] \
    || log_fail "t007b: bytes BEFORE the markers were altered by a re-run"
  [[ "$tail_after" == "$tail_before" ]] \
    || log_fail "t007b: bytes AFTER the markers were altered by a re-run"
  grep -qF 'Feature A Renamed' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t007b: marked region was not refreshed with the new content"

  log_pass "Containment: hand-written bytes outside the markers untouched, first-run EOF append (TEST-007)"
}

# --- TEST-008 (Spec-AC-03): byte-idempotence ---------------------------------

test_008_byte_idempotent() {
  log_info "Test: rollup is byte-identical on a second run with unchanged inputs (TEST-008)..."
  local dir; dir=$(new_fixture_dir "t008")
  write_product_doc "$dir" "feature-a" "2026-01-01" "Feature A"
  write_product_doc "$dir" "feature-b" "2026-01-05" "Feature B"

  local out="$TEST_DIR/t008a.out" err="$TEST_DIR/t008a.err" code
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t008: first run exited $code: $(cat "$err")"
  local snap1; snap1=$(cat "$dir/docs/USER_GUIDE.md")

  out="$TEST_DIR/t008b.out"; err="$TEST_DIR/t008b.err"
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t008: second run exited $code: $(cat "$err")"
  local snap2; snap2=$(cat "$dir/docs/USER_GUIDE.md")

  [[ "$snap1" == "$snap2" ]] \
    || log_fail "t008: docs/USER_GUIDE.md changed on a second run with unchanged inputs (not byte-idempotent)"
  if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' "$dir/docs/USER_GUIDE.md"; then
    log_fail "t008: marked region carries a generation timestamp (violates D4 byte-idempotence)"
  fi

  log_pass "Byte-idempotence: second run with unchanged inputs is byte-identical, no timestamp inside the marker (TEST-008)"
}

# --- TEST-009 (Spec-AC-03): sorted by updated descending ---------------------

test_009_sorted_updated_desc() {
  log_info "Test: rollup lists product docs sorted by frontmatter updated descending (TEST-009)..."
  local dir; dir=$(new_fixture_dir "t009")
  write_product_doc "$dir" "feature-old" "2026-01-01" "Feature Old"
  write_product_doc "$dir" "feature-new" "2026-03-01" "Feature New"
  write_product_doc "$dir" "feature-mid" "2026-02-01" "Feature Mid"

  local out="$TEST_DIR/t009.out" err="$TEST_DIR/t009.err" code
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t009: generator exited $code: $(cat "$err")"

  local guide="$dir/docs/USER_GUIDE.md"
  local pos_new pos_mid pos_old
  pos_new=$(grep -n 'Feature New' "$guide" | head -1 | cut -d: -f1)
  pos_mid=$(grep -n 'Feature Mid' "$guide" | head -1 | cut -d: -f1)
  pos_old=$(grep -n 'Feature Old' "$guide" | head -1 | cut -d: -f1)
  [[ -n "$pos_new" && -n "$pos_mid" && -n "$pos_old" ]] \
    || log_fail "t009: not all three feature titles were rendered"
  [[ "$pos_new" -lt "$pos_mid" ]] || log_fail "t009: Feature New (2026-03-01) must render before Feature Mid (2026-02-01)"
  [[ "$pos_mid" -lt "$pos_old" ]] || log_fail "t009: Feature Mid (2026-02-01) must render before Feature Old (2026-01-01)"

  log_pass "Sorted by updated descending: New before Mid before Old (TEST-009)"
}

# --- TEST-010 (Spec-AC-03, D2): placeholder-doc exclusion --------------------

test_010_placeholder_excluded() {
  log_info "Test: a placeholder-failing product doc is excluded; a real doc with an explicit None. section still renders (TEST-010)..."
  local dir; dir=$(new_fixture_dir "t010")
  write_product_doc "$dir" "feature-real" "2026-01-01" "Feature Real" "None."
  write_placeholder_product_doc "$dir" "feature-placeholder" "2026-01-02" "Feature Placeholder"

  local out="$TEST_DIR/t010.out" err="$TEST_DIR/t010.err" code
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t010: generator exited $code: $(cat "$err")"

  grep -qF 'Feature Real' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t010: the real product doc (None. data model) was NOT rendered"
  if grep -qF 'Feature Placeholder' "$dir/docs/USER_GUIDE.md"; then
    log_fail "t010: the placeholder-failing product doc LEAKED into the rendered rollup"
  fi

  log_pass "Placeholder-doc exclusion: real (None.) doc renders, placeholder doc excluded (TEST-010)"
}

# --- TEST-011 (fixture diversity: degenerate/empty) --------------------------

test_011_empty_product_dir() {
  log_info "Test: zero product docs still produces a stable, marker-contained empty-state block, exit 0 (fixture diversity: degenerate/empty)..."
  local dir; dir=$(new_fixture_dir "t011")

  local out="$TEST_DIR/t011.out" err="$TEST_DIR/t011.err" code
  code=$(run_rollup "$dir" "$out" "$err")
  [[ "$code" == "0" ]] || log_fail "t011: generator exited $code on an empty docs/product/: $(cat "$err")"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:BEGIN' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t011: BEGIN marker missing on an empty-product-dir run"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:END -->' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t011: END marker missing on an empty-product-dir run"

  log_pass "Degenerate/empty: zero product docs -> stable marker-contained block, exit 0"
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

  test_007_containment
  test_008_byte_idempotent
  test_009_sorted_updated_desc
  test_010_placeholder_excluded
  test_011_empty_product_dir

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
