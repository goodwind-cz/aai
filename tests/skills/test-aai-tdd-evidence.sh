#!/usr/bin/env bash
#
# Test: aai-tdd-evidence — RED evidence classification (CHANGE-0033 /
# docs/specs/SPEC-0044-spec-tdd-red-evidence-classification.md, TEST-001..005).
#
# Verifies the machine-readable RED_CLASS classification that lets tooling
# distinguish a genuine PRODUCT red (the test's own assertion output was
# reached) from an INFRASTRUCTURE failure (the run died before any
# assertion executed):
#   - TEST-001 (Spec-AC-01): .aai/scripts/tdd-evidence-check.mjs contract
#     matrix — product_red -> 0, infra_fail -> 1, missing/duplicate/unknown
#     RED_CLASS -> 2, unreadable path/usage error -> 3; no input shape
#     reaches exit 0 without the literal `product_red` token.
#   - TEST-002 (Spec-AC-03): realistic accept/reject fixture pair (Seam 1) —
#     broken-import runner-crash body + RED_CLASS: infra_fail -> exit 1;
#     assertion-failure body (expected-vs-actual reached) + RED_CLASS:
#     product_red -> exit 0.
#   - TEST-003 (Spec-AC-02): canon contract on .aai/SKILL_TDD.prompt.md Phase
#     1 — RED_CLASS grammar (both values), the D5 assertion-output-reached
#     rule, the check invocation, and the product_red-only GREEN hard block.
#   - TEST-004 (Spec-AC-04): canon contract on .aai/VALIDATION.prompt.md step
#     5g — names tdd-evidence-check.mjs, rejects infra_fail/unclassified NEW
#     evidence, and carries the legacy (pre-change, no RED_CLASS) carve-out.
#   - TEST-005 (Spec-AC-05): additive regression — legacy repo log probed
#     explicitly (exit 2, no repo-wide sweep); test-aai-tdd.sh regression;
#     `git diff` empty on .aai/scripts/state.mjs; docs-audit strict exit 0.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped for TEST-001:
#   - degenerate/empty            -> empty log file                  -> 2
#   - zero-remainder               -> header-only single-line log     -> 0
#   - multi-source/multi-writer    -> two conflicting RED_CLASS lines -> 2
#   - mid-operation failure        -> genuine crash-mid-run body      -> 1
#   - negative control              -> indented decoy line, no real header -> 2
#
# ALL fixtures are scratch temp-dir files. The real repo docs/ai/tdd/ logs
# are read-only probed in TEST-005 (legacy carve-out), never written.
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-tdd-evidence"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_SCRIPT="$PROJECT_ROOT/.aai/scripts/tdd-evidence-check.mjs"
SKILL_TDD="$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"
VALIDATION="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
STATE_SCRIPT="$PROJECT_ROOT/.aai/scripts/state.mjs"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
LEGACY_RED_LOG="$PROJECT_ROOT/docs/ai/tdd/dispatch-retarget-red.log"
TDD_REGRESSION_SUITE="$SCRIPT_DIR/test-aai-tdd.sh"
RUN_TESTS_SH="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"

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

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$SKILL_TDD" ]] || log_fail "SKILL_TDD.prompt.md not found: $SKILL_TDD"
  [[ -f "$VALIDATION" ]] || log_fail "VALIDATION.prompt.md not found: $VALIDATION"
  [[ -f "$STATE_SCRIPT" ]] || log_fail "state CLI not found: $STATE_SCRIPT"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  # LEGACY_RED_LOG is NOT checked here: it is a gitignored per-dev runtime
  # artifact (docs/ai/tdd/**), absent on a fresh checkout. ensure_legacy_red_log
  # (called from main after setup_fixture) self-seeds a scratch stand-in when
  # the real one is missing, rather than hard-failing on its absence.
  [[ -f "$TDD_REGRESSION_SUITE" ]] || log_fail "regression suite not found: $TDD_REGRESSION_SUITE"
  [[ -f "$RUN_TESTS_SH" ]] || log_fail "aai-run-tests.sh not found: $RUN_TESTS_SH"
  # NOTE: CHECK_SCRIPT is intentionally NOT required here — TEST-001/002 RED
  # naturally (invocation fails / wrong exits) while the script does not yet
  # exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-tdd-evidence-test.XXXXXX")"
}

# RC1 (Spec-AC-02): docs/ai/tdd/dispatch-retarget-red.log is gitignored
# per-dev runtime evidence, so it does not exist on a fresh checkout (e.g.
# Linux CI). Self-seed a representative legacy-format (pre-RED_CLASS) fixture
# under $TEST_DIR when the real file is absent, and repoint LEGACY_RED_LOG at
# it — cleaned up automatically by the existing TEST_DIR trap. When the real
# file IS present (a developer's local checkout), it is used unchanged
# (non-regression; TEST-005's "probed explicitly, no repo-wide sweep" intent
# is unaffected either way since the path is always passed explicitly).
ensure_legacy_red_log() {
  if [[ ! -f "$LEGACY_RED_LOG" ]]; then
    LEGACY_RED_LOG="$TEST_DIR/self-seeded-dispatch-retarget-red.log"
    cat > "$LEGACY_RED_LOG" <<'EOF'
=== RED-proof run: self-seeded legacy fixture (pre-RED_CLASS format) ===
Pre-change tree. Expected: assertion FAIL below (no RED_CLASS header line).

### test_legacy_seed ###
INFO: Checking dependencies...
PASS: Dependencies checked
FAIL: legacy assertion failed: AssertionError [ERR_ASSERTION]
    at file:///self-seeded-legacy-fixture.mjs:1:1
Node.js v22.0.0
exit_code: 1
EOF
    log_info "docs/ai/tdd/dispatch-retarget-red.log absent (fresh checkout) — self-seeded a legacy-format stand-in at $LEGACY_RED_LOG"
  fi
}

run_check() {
  # Runs the classifier against $1, capturing exit code without tripping
  # `set -e`. Prints the exit code on stdout (nothing else).
  local path="$1"
  local code=0
  node "$CHECK_SCRIPT" --red "$path" > "$TEST_DIR/check-out.log" 2>&1 || code=$?
  echo "$code"
}

run_check_noflag() {
  local code=0
  node "$CHECK_SCRIPT" > "$TEST_DIR/check-out.log" 2>&1 || code=$?
  echo "$code"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    || log_fail "$desc: expected exit $expected, got $actual ($(cat "$TEST_DIR/check-out.log" 2>/dev/null | head -3))"
}

# --- TEST-001 (Spec-AC-01): check-script contract matrix ---------------------

test_001_contract_matrix() {
  log_info "Test: tdd-evidence-check.mjs contract matrix — product_red/infra_fail/missing/duplicate/unknown/unreadable/usage (TEST-001)..."

  local f="$TEST_DIR"

  # product_red, valid single line -> 0
  printf 'RED_CLASS: product_red\nAssertionError: expected 5 got 4\n' > "$f/valid-product-red.log"
  assert_exit "product_red valid" 0 "$(run_check "$f/valid-product-red.log")"

  # infra_fail, valid single line -> 1
  printf 'RED_CLASS: infra_fail\nError: Cannot find module\n' > "$f/valid-infra-fail.log"
  assert_exit "infra_fail valid" 1 "$(run_check "$f/valid-infra-fail.log")"

  # degenerate/empty log file -> 2
  : > "$f/empty.log"
  assert_exit "empty log (degenerate)" 2 "$(run_check "$f/empty.log")"

  # zero-remainder: header-only single-line log, nothing else -> 0
  printf 'RED_CLASS: product_red' > "$f/header-only.log"
  assert_exit "header-only (zero-remainder)" 0 "$(run_check "$f/header-only.log")"

  # missing RED_CLASS line entirely -> 2
  printf 'just a plain log with no header\nsecond line\n' > "$f/missing.log"
  assert_exit "missing RED_CLASS" 2 "$(run_check "$f/missing.log")"

  # multi-source/multi-writer: two conflicting RED_CLASS lines -> 2
  printf 'RED_CLASS: product_red\nsome output\nRED_CLASS: infra_fail\n' > "$f/duplicate-conflict.log"
  assert_exit "duplicate conflicting (multi-writer)" 2 "$(run_check "$f/duplicate-conflict.log")"

  # duplicate IDENTICAL values -> still 2 (exactly-one rule)
  printf 'RED_CLASS: product_red\nRED_CLASS: product_red\n' > "$f/duplicate-identical.log"
  assert_exit "duplicate identical" 2 "$(run_check "$f/duplicate-identical.log")"

  # unknown value -> 2
  printf 'RED_CLASS: bogus_value\n' > "$f/unknown-value.log"
  assert_exit "unknown value" 2 "$(run_check "$f/unknown-value.log")"

  # negative control: decoy line resembling the grammar but not anchored/
  # exact (indented) — must NOT be silently accepted -> 2
  printf '  RED_CLASS: product_red (indented decoy, not a real header)\nno real classification here\n' > "$f/negative-control.log"
  assert_exit "negative control decoy" 2 "$(run_check "$f/negative-control.log")"

  # mid-operation failure: genuine crash-mid-run body, correctly labeled -> 1
  printf 'RED_CLASS: infra_fail\nrunning setup...\nrunning step 2...\nFATAL: process crashed mid-run, no assertion reached\n' > "$f/mid-op-crash.log"
  assert_exit "mid-operation crash" 1 "$(run_check "$f/mid-op-crash.log")"

  # unreadable/nonexistent path -> 3
  assert_exit "nonexistent path (usage)" 3 "$(run_check "$f/does-not-exist.log")"

  # usage error: no --red flag at all -> 3
  assert_exit "missing --red flag (usage)" 3 "$(run_check_noflag)"

  log_pass "Contract matrix: no shape reached exit 0 without the literal product_red token (TEST-001)"
}

# --- TEST-002 (Spec-AC-03): realistic accept/reject fixture pair (Seam 1) ----

test_002_realistic_fixture_pair() {
  log_info "Test: realistic broken-import crash (infra_fail) rejected; realistic assertion failure (product_red) accepted (TEST-002)..."

  local f="$TEST_DIR"

  cat > "$f/realistic-infra-fail.log" <<'LOG'
RED_CLASS: infra_fail
node:internal/modules/cjs/loader:1
Error: Cannot find module '/tmp/fixture/missing-module.js'
    at Module._resolveFilename (node:internal/modules/cjs/loader:1015:15)
    at Module._load (node:internal/modules/cjs/loader:860:27)
    at Function.executeUserEntryPoint (node:internal/modules/run_main:81:12)
Node.js v22.23.1
LOG
  assert_exit "realistic infra_fail rejected" 1 "$(run_check "$f/realistic-infra-fail.log")"

  cat > "$f/realistic-product-red.log" <<'LOG'
RED_CLASS: product_red
AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:

'red' !== 'green'

    at file:///tmp/fixture/t.mjs:10:10 {
  generatedMessage: true,
  code: 'ERR_ASSERTION',
  actual: 'red',
  expected: 'green',
  operator: 'strictEqual'
}
FAIL: TEST-fixture expected green got red
LOG
  assert_exit "realistic product_red accepted" 0 "$(run_check "$f/realistic-product-red.log")"

  log_pass "Realistic accept/reject fixture pair crosses Seam 1 correctly (TEST-002)"
}

# --- TEST-003 (Spec-AC-02): SKILL_TDD Phase 1 canon contract -----------------

test_003_skill_tdd_canon() {
  log_info "Test: SKILL_TDD Phase 1 carries RED_CLASS grammar, D5 rule, check invocation, checklist item, product_red-only GREEN hard block (TEST-003)..."

  grep -qF 'RED_CLASS: product_red' "$SKILL_TDD" \
    || log_fail "TEST-003: SKILL_TDD.prompt.md must show the RED_CLASS: product_red grammar token"
  grep -qF 'RED_CLASS: infra_fail' "$SKILL_TDD" \
    || log_fail "TEST-003: SKILL_TDD.prompt.md must show the RED_CLASS: infra_fail grammar token"
  grep -qF 'assertion output reached' "$SKILL_TDD" \
    || log_fail "TEST-003: SKILL_TDD.prompt.md must state the D5 'assertion output reached' distinguishing rule"
  grep -qF 'tdd-evidence-check.mjs' "$SKILL_TDD" \
    || log_fail "TEST-003: SKILL_TDD.prompt.md must instruct running tdd-evidence-check.mjs"
  grep -qF 'product_red-classified' "$SKILL_TDD" \
    || log_fail "TEST-003: SKILL_TDD.prompt.md must state the product_red-only GREEN hard block"

  log_pass "SKILL_TDD Phase 1 RED_CLASS classification wiring present (TEST-003)"
}

# --- TEST-004 (Spec-AC-04): VALIDATION step 5g canon contract ----------------

test_004_validation_canon() {
  log_info "Test: VALIDATION step 5g names tdd-evidence-check.mjs, rejects infra_fail/unclassified NEW evidence, carries legacy carve-out (TEST-004)..."

  grep -qF 'tdd-evidence-check.mjs' "$VALIDATION" \
    || log_fail "TEST-004: VALIDATION.prompt.md step 5g must name tdd-evidence-check.mjs"
  grep -qF 'infra_fail' "$VALIDATION" \
    || log_fail "TEST-004: VALIDATION.prompt.md step 5g must reject infra_fail as RED-proof"
  grep -qF 'Legacy' "$VALIDATION" \
    || log_fail "TEST-004: VALIDATION.prompt.md step 5g must carry the legacy (pre-change) carve-out"
  grep -qF 'RED_CLASS' "$VALIDATION" \
    || log_fail "TEST-004: VALIDATION.prompt.md step 5g must reference the RED_CLASS classification"

  log_pass "VALIDATION step 5g consumes the check with a legacy carve-out (TEST-004)"
}

# --- TEST-005 (Spec-AC-05): additive regression ------------------------------

test_005_additive_regression() {
  log_info "Test: legacy log probe -> 2, no repo-wide sweep, test-aai-tdd.sh regression, state.mjs zero-diff, docs-audit strict (TEST-005)..."

  # Legacy repo log (pre-change, no RED_CLASS line) -> 2 when explicitly probed.
  assert_exit "legacy log explicit probe" 2 "$(run_check "$LEGACY_RED_LOG")"

  # No repo-wide sweep: the check script itself must not glob/walk docs/ai/tdd.
  if grep -qE 'readdirSync|readdir\(|docs/ai/tdd/\*|globSync' "$CHECK_SCRIPT" 2>/dev/null; then
    log_fail "TEST-005: tdd-evidence-check.mjs must not perform a repo-wide sweep of docs/ai/tdd/"
  fi

  # Regression: existing TDD skill test suite still exits 0.
  local regress_log="$TEST_DIR/tdd-regression.log"
  (cd "$PROJECT_ROOT" && AAI_TEST_TIMEOUT="${AAI_TEST_TIMEOUT:-600}" \
    "$RUN_TESTS_SH" bash "$TDD_REGRESSION_SUITE" > "$regress_log" 2>&1) \
    || log_fail "TEST-005: tests/skills/test-aai-tdd.sh must still exit 0: $(tail -20 "$regress_log")"

  # Protected surface: state.mjs must have zero diff.
  local diff_out
  diff_out="$(cd "$PROJECT_ROOT" && git diff --stat -- .aai/scripts/state.mjs)"
  [[ -z "$diff_out" ]] \
    || log_fail "TEST-005: .aai/scripts/state.mjs must have zero diff (protected L3 surface): $diff_out"

  # docs-audit strict check must still exit 0.
  local audit_log="$TEST_DIR/docs-audit.log"
  (cd "$PROJECT_ROOT" && node "$DOCS_AUDIT" --check --strict --no-event > "$audit_log" 2>&1) \
    || log_fail "TEST-005: docs-audit --check --strict --no-event must exit 0: $(tail -20 "$audit_log")"

  log_pass "Additive regression: legacy probe=2, no sweep, tdd.sh green, state.mjs zero-diff, docs-audit clean (TEST-005)"
}

# --- TEST-010 (SPEC-0046 Spec-AC-08): BOM+CRLF product_red -> exit 0 ACCEPTED --

test_006_bom_foldin_accept() {
  log_info "Test: BOM+CRLF RED_CLASS: product_red -> exit 0 ACCEPTED (SPEC-0046 TEST-010)..."

  local f="$TEST_DIR"

  # UTF-8 BOM (EF BB BF) + CRLF line endings, otherwise a valid single header line.
  printf '\xEF\xBB\xBFRED_CLASS: product_red\r\nAssertionError: expected 5 got 4\r\n' \
    > "$f/bom-crlf-product-red.log"
  assert_exit "BOM+CRLF product_red accepted" 0 "$(run_check "$f/bom-crlf-product-red.log")"

  # BOM + LF (no CRLF) header-only line -> 0 (zero-remainder shape, BOM variant).
  printf '\xEF\xBB\xBFRED_CLASS: product_red\n' > "$f/bom-lf-header-only.log"
  assert_exit "BOM+LF header-only accepted" 0 "$(run_check "$f/bom-lf-header-only.log")"

  log_pass "BOM-prefixed logs (CRLF and LF) with a valid product_red header are ACCEPTED (TEST-010)"
}

# --- TEST-011 (SPEC-0046 Spec-AC-08): fail-closed behavior unchanged with BOM --

test_007_bom_failclosed_unchanged() {
  log_info "Test: fail-closed unchanged with BOM — 0/2 headers->2, bad value->2, infra_fail->1, mid-file BOM inert (SPEC-0046 TEST-011)..."

  local f="$TEST_DIR"

  # BOM + zero RED_CLASS lines -> 2 (still unclassified).
  printf '\xEF\xBB\xBFjust a plain log, no header\r\n' > "$f/bom-missing.log"
  assert_exit "BOM + missing header" 2 "$(run_check "$f/bom-missing.log")"

  # BOM + two conflicting RED_CLASS lines -> 2 (exactly-one rule still holds).
  printf '\xEF\xBB\xBFRED_CLASS: product_red\r\nRED_CLASS: infra_fail\r\n' > "$f/bom-duplicate.log"
  assert_exit "BOM + duplicate conflicting headers" 2 "$(run_check "$f/bom-duplicate.log")"

  # BOM + unrecognized value -> 2.
  printf '\xEF\xBB\xBFRED_CLASS: bogus\r\n' > "$f/bom-unknown.log"
  assert_exit "BOM + unknown value" 2 "$(run_check "$f/bom-unknown.log")"

  # BOM + infra_fail -> 1 (REJECTED, not silently accepted or unclassified).
  printf '\xEF\xBB\xBFRED_CLASS: infra_fail\r\nError: crash mid-run\r\n' > "$f/bom-infra.log"
  assert_exit "BOM + infra_fail" 1 "$(run_check "$f/bom-infra.log")"

  # A BOM byte sequence anywhere OTHER than byte 0 must be inert — a valid header
  # at the true start of the file still classifies normally even if a stray
  # BOM-like byte sequence appears later in the body.
  printf 'RED_CLASS: product_red\r\nsome output \xEF\xBB\xBF embedded mid-file, inert\r\n' \
    > "$f/bom-midfile.log"
  assert_exit "mid-file BOM is inert (byte-0-only strip)" 0 "$(run_check "$f/bom-midfile.log")"

  log_pass "Fail-closed behaviors unchanged with BOM combos; BOM stripped ONLY at byte 0 (TEST-011)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture
  ensure_legacy_red_log

  test_001_contract_matrix
  test_002_realistic_fixture_pair
  test_003_skill_tdd_canon
  test_004_validation_canon
  test_005_additive_regression
  test_006_bom_foldin_accept
  test_007_bom_failclosed_unchanged

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
