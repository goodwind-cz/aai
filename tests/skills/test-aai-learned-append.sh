#!/usr/bin/env bash
#
# Test: learned-append-gate (CHANGE-0069-learned-append-gate,
# docs/specs/SPEC-0095-spec-learned-append-gate.md, TEST-001..017).
#
# Covers the structurally-enforced append-only gate for docs/knowledge/LEARNED.md:
#   .aai/scripts/learned-append.mjs   — dependency-free gate CLI (rule-text
#                                       mode + --full generic verifier mode).
#   .aai/SKILL_WRAP_UP.prompt.md      — step 3 routes a confirmed rule through
#                                       a critic pass THEN the gate (never a
#                                       direct edit); step 6 cross-references it.
#   .aai/system/FRICTION_PROTOCOL.md  — one-line pointer to the gate.
#   .aai/system/PROFILES.yaml         — classifies the new script (core).
#
# Test map:
#   TEST-001 (Spec-AC-01) pure append, no --section: exact bullet appended at EOF.
#   TEST-002 (Spec-AC-01) --section matching the file's current LAST heading
#                         behaves identically to no --section.
#   TEST-003 (Spec-AC-01) --section naming a brand-new heading creates it at EOF.
#   TEST-004 (Spec-AC-02) --full rewrite (existing byte changed) rejected,
#                         tree byte-identical.
#   TEST-005 (Spec-AC-02) --full reorder (two blocks swapped) rejected,
#                         tree byte-identical.
#   TEST-006 (Spec-AC-02) rule-text mid-insert (--section names an existing,
#                         non-last heading) rejected, tree byte-identical.
#   TEST-007 (Spec-AC-02) --full deletion (an existing line removed) rejected,
#                         tree byte-identical.
#   TEST-008 (Spec-AC-03) --dry-run on an accept-shaped input prints the
#                         would-be append, writes nothing.
#   TEST-009 (Spec-AC-03) --dry-run on a reject-shaped input still exits 1
#                         (dry-run never bypasses the gate).
#   TEST-010 (Spec-AC-01) negative control: usage errors (missing --source,
#                         --text + --file conflict, missing --target) exit 2,
#                         nothing written.
#   TEST-011 (Spec-AC-01) two sequential real appends onto the same file each
#                         succeed; the second builds on the first's result.
#   TEST-012 (Spec-AC-01) --full candidate identical to the current file:
#                         zero-byte no-op, exit 0.
#   TEST-013 (Spec-AC-04) SKILL_WRAP_UP.prompt.md step 3 names the
#                         critic-then-gate flow + the exact invocation; step 6
#                         cross-references it.
#   TEST-014 (Spec-AC-04) FRICTION_PROTOCOL.md carries the one-line pointer.
#   TEST-015 (Spec-AC-04) PROFILES.yaml classifies the script under core;
#                         real test-aai-layer-profiles.sh stays green.
#   TEST-016 (Spec-AC-04) real test-aai-prompt-diet.sh stays green (ledger
#                         true-up proven against the live corpus).
#   TEST-017 (Spec-AC-05) companion suites (friction-wiring, hygiene-pack)
#                         stay green.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty      -> TEST-012 (zero-byte no-op candidate).
#   - zero-remainder        -> TEST-012 (nothing left to append).
#   - multi-source/multi-writer -> TEST-011 (two sequential real appends).
#   - mid-operation failure -> TEST-004..007 (rejected candidate leaves the
#                              tree byte-identical, not partially written).
#   - negative control      -> TEST-010 (usage errors), TEST-009 (dry-run
#                              does not bypass the gate).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Node stdlib only.
#
# Usage:
#   bash tests/skills/test-aai-learned-append.sh                # run all
#   bash tests/skills/test-aai-learned-append.sh test_004_...   # run one
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-learned-append"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCRIPT="$PROJECT_ROOT/.aai/scripts/learned-append.mjs"
WRAP_UP_PROMPT="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"
PROTOCOL="$PROJECT_ROOT/.aai/system/FRICTION_PROTOCOL.md"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"
PROMPT_DIET_TEST="$SCRIPT_DIR/test-aai-prompt-diet.sh"
FRICTION_WIRING_TEST="$SCRIPT_DIR/test-aai-friction-wiring.sh"
HYGIENE_PACK_TEST="$SCRIPT_DIR/test-aai-hygiene-pack.sh"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [ -f "$WRAP_UP_PROMPT" ] || log_fail "SKILL_WRAP_UP.prompt.md not found: $WRAP_UP_PROMPT"
  [ -f "$PROTOCOL" ] || log_fail "FRICTION_PROTOCOL.md not found: $PROTOCOL"
  [ -f "$PROFILES" ] || log_fail "PROFILES.yaml not found: $PROFILES"
  # NOTE: SCRIPT is intentionally NOT required here — the RED phase runs
  # against the absent script so TEST-001..012 fail on their own assertion
  # (product_red), not a missing-precondition skip.
  log_pass "Dependencies checked"
}

# --- fixture ------------------------------------------------------------

# A small, fully self-contained fixture document (not the real, growing
# docs/knowledge/LEARNED.md) so this suite never depends on real content
# drifting under future sessions (hermetic per docs/knowledge/LEARNED.md's
# own "do not assume" lesson). "Testing" and "Workflow" are deliberately NOT
# the last section (for the mid-insert case); "Conventions" is the last.
setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-learned-append-test.XXXXXX")"
  BASE="$TEST_DIR/BASE.md"
  cat > "$BASE" <<'FIXTURE'
# Fixture Learned Rules

## Code Style

## Testing
- [2026-01-01] existing testing rule (source: fixture)

## Workflow
- [2026-01-01] existing workflow rule (source: fixture)

## Conventions
- [2026-01-01] existing conventions rule (source: fixture)
FIXTURE
}

fresh_copy() {
  cp "$BASE" "$1"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [ "$actual" = "$expected" ] || log_fail "$desc: expected exit $expected, got $actual"
}

assert_unchanged() {
  local desc="$1" file="$2"
  cmp -s "$BASE" "$file" || log_fail "$desc: target file must be byte-identical to before the call"
}

run_gate() {
  # run_gate <target> <extra args...> -> prints exit code on stdout; stdout/
  # stderr of the CLI captured to $OUT/$ERR.
  local target="$1"; shift
  local code=0
  node "$SCRIPT" --target "$target" "$@" > "$OUT" 2> "$ERR" || code=$?
  echo "$code"
}
OUT=""; ERR=""

# --- TEST-001 (Spec-AC-01): pure append, no --section -----------------------

test_001_pure_append_no_section() {
  log_info "Test: pure append with no --section lands the exact stamped bullet at EOF (TEST-001)..."
  local f="$TEST_DIR/t001.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o001"; ERR="$TEST_DIR/e001"
  local code; code="$(run_gate "$f" --source "unit test" --text "brand new rule")"
  assert_exit "TEST-001" 0 "$code"

  local today; today="$(date -u +%Y-%m-%d)"
  local expected="- [$today] brand new rule (source: unit test)"
  local last_line; last_line="$(tail -n 1 "$f")"
  [ "$last_line" = "$expected" ] || log_fail "TEST-001: last line '$last_line' != expected '$expected'"

  local base_len new_len; base_len="$(wc -c < "$BASE" | tr -d ' ')"; new_len="$(wc -c < "$f" | tr -d ' ')"
  local want_len=$((base_len + ${#expected} + 1))
  [ "$new_len" = "$want_len" ] || log_fail "TEST-001: file grew to $new_len bytes, expected exactly $want_len (base $base_len + bullet ${#expected} + 1 newline)"
  log_pass "Pure append, no --section: exact stamped bullet at EOF, exit 0 (TEST-001)"
}

# --- TEST-002 (Spec-AC-01): --section matching the current last heading -----

test_002_section_matches_last() {
  log_info "Test: --section naming the file's current LAST heading behaves like no --section (TEST-002)..."
  local f="$TEST_DIR/t002.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o002"; ERR="$TEST_DIR/e002"
  local code; code="$(run_gate "$f" --source "unit test" --text "conventions rule" --section "Conventions")"
  assert_exit "TEST-002" 0 "$code"

  local today; today="$(date -u +%Y-%m-%d)"
  local expected="- [$today] conventions rule (source: unit test)"
  local last_line; last_line="$(tail -n 1 "$f")"
  [ "$last_line" = "$expected" ] || log_fail "TEST-002: last line '$last_line' != expected '$expected'"
  log_pass "--section matching the last heading == plain append (TEST-002)"
}

# --- TEST-003 (Spec-AC-01): --section naming a brand-new heading ------------

test_003_section_new_heading() {
  log_info "Test: --section naming a brand-new heading creates it + the bullet at EOF (TEST-003)..."
  local f="$TEST_DIR/t003.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o003"; ERR="$TEST_DIR/e003"
  local code; code="$(run_gate "$f" --source "unit test" --text "deploy rule" --section "Deploy")"
  assert_exit "TEST-003" 0 "$code"

  grep -qF "## Deploy" "$f" || log_fail "TEST-003: new '## Deploy' heading not found"
  local today; today="$(date -u +%Y-%m-%d)"
  local expected="- [$today] deploy rule (source: unit test)"
  local last_line; last_line="$(tail -n 1 "$f")"
  [ "$last_line" = "$expected" ] || log_fail "TEST-003: last line '$last_line' != expected '$expected'"
  # Everything that existed before must still be present, byte-for-byte, as a prefix.
  head -c "$(wc -c < "$BASE" | tr -d ' ')" "$f" > "$TEST_DIR/t003.prefix"
  cmp -s "$BASE" "$TEST_DIR/t003.prefix" || log_fail "TEST-003: original content is not an unmodified prefix of the new file"
  log_pass "--section naming a brand-new heading: created at EOF, exit 0 (TEST-003)"
}

# --- TEST-004 (Spec-AC-02): --full rewrite rejected --------------------------

test_004_full_rewrite_rejected() {
  log_info "Test: --full mode rewrite (existing byte changed) rejected, tree byte-identical (TEST-004)..."
  local f="$TEST_DIR/t004.md"; fresh_copy "$f"
  local mut="$TEST_DIR/mut004.md"
  sed 's/existing testing rule/REWRITTEN testing rule/' "$BASE" > "$mut"
  OUT="$TEST_DIR/o004"; ERR="$TEST_DIR/e004"
  local code; code="$(run_gate "$f" --full --file "$mut")"
  assert_exit "TEST-004" 1 "$code"
  assert_unchanged "TEST-004" "$f"
  grep -qi "not a pure append" "$ERR" || log_fail "TEST-004: stderr must carry a diff summary explaining the rejection"
  log_pass "--full rewrite rejected, tree byte-identical (TEST-004)"
}

# --- TEST-005 (Spec-AC-02): --full reorder rejected --------------------------

test_005_full_reorder_rejected() {
  log_info "Test: --full mode reorder (two existing blocks swapped) rejected, tree byte-identical (TEST-005)..."
  local f="$TEST_DIR/t005.md"; fresh_copy "$f"
  local mut="$TEST_DIR/mut005.md"
  cat > "$mut" <<'FIXTURE'
# Fixture Learned Rules

## Code Style

## Workflow
- [2026-01-01] existing workflow rule (source: fixture)

## Testing
- [2026-01-01] existing testing rule (source: fixture)

## Conventions
- [2026-01-01] existing conventions rule (source: fixture)
FIXTURE
  OUT="$TEST_DIR/o005"; ERR="$TEST_DIR/e005"
  local code; code="$(run_gate "$f" --full --file "$mut")"
  assert_exit "TEST-005" 1 "$code"
  assert_unchanged "TEST-005" "$f"
  log_pass "--full reorder rejected, tree byte-identical (TEST-005)"
}

# --- TEST-006 (Spec-AC-02): rule-text mid-insert rejected --------------------

test_006_mid_insert_rejected() {
  log_info "Test: --section naming an existing NON-last heading (mid-insert) rejected, tree byte-identical (TEST-006)..."
  local f="$TEST_DIR/t006.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o006"; ERR="$TEST_DIR/e006"
  local code; code="$(run_gate "$f" --source "unit test" --text "sneaky mid rule" --section "Testing")"
  assert_exit "TEST-006" 1 "$code"
  assert_unchanged "TEST-006" "$f"
  ! grep -qF "sneaky mid rule" "$f" || log_fail "TEST-006: rejected content must not appear anywhere in the file"
  log_pass "Mid-insert via a non-last --section rejected, tree byte-identical (TEST-006)"
}

# --- TEST-007 (Spec-AC-02): --full deletion rejected -------------------------

test_007_full_deletion_rejected() {
  log_info "Test: --full mode deletion (existing line removed) rejected, tree byte-identical (TEST-007)..."
  local f="$TEST_DIR/t007.md"; fresh_copy "$f"
  local mut="$TEST_DIR/mut007.md"
  grep -v "existing workflow rule" "$BASE" > "$mut"
  OUT="$TEST_DIR/o007"; ERR="$TEST_DIR/e007"
  local code; code="$(run_gate "$f" --full --file "$mut")"
  assert_exit "TEST-007" 1 "$code"
  assert_unchanged "TEST-007" "$f"
  log_pass "--full deletion rejected, tree byte-identical (TEST-007)"
}

# --- TEST-008 (Spec-AC-03): --dry-run on an accept-shaped input -------------

test_008_dry_run_accept() {
  log_info "Test: --dry-run on an accept-shaped input prints the would-be append and writes nothing (TEST-008)..."
  local f="$TEST_DIR/t008.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o008"; ERR="$TEST_DIR/e008"
  local code; code="$(run_gate "$f" --source "unit test" --text "dry run rule" --dry-run)"
  assert_exit "TEST-008" 0 "$code"
  assert_unchanged "TEST-008" "$f"
  grep -qi "would append" "$OUT" || log_fail "TEST-008: stdout must announce the would-be append"
  grep -qF "dry run rule" "$OUT" || log_fail "TEST-008: stdout must contain the rule text"
  log_pass "--dry-run accept-shaped: prints the would-be append, writes nothing (TEST-008)"
}

# --- TEST-009 (Spec-AC-03): --dry-run on a reject-shaped input --------------

test_009_dry_run_reject_still_fails() {
  log_info "Test: --dry-run on a reject-shaped input still exits 1 (dry-run never bypasses the gate) (TEST-009)..."
  local f="$TEST_DIR/t009.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o009"; ERR="$TEST_DIR/e009"
  local code; code="$(run_gate "$f" --source "unit test" --text "sneaky dry mid rule" --section "Testing" --dry-run)"
  assert_exit "TEST-009" 1 "$code"
  assert_unchanged "TEST-009" "$f"
  log_pass "--dry-run does not bypass the structural gate on a reject-shaped input (TEST-009)"
}

# --- TEST-010 (Spec-AC-01): usage errors -------------------------------------

test_010_usage_errors() {
  log_info "Test: usage errors (missing --source, --text + --file conflict, missing --target) exit 2, nothing written (TEST-010)..."
  local f="$TEST_DIR/t010.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o010a"; ERR="$TEST_DIR/e010a"
  local code
  code="$(run_gate "$f" --text "no source given")"
  assert_exit "TEST-010 missing --source" 2 "$code"
  assert_unchanged "TEST-010 missing --source" "$f"

  local ftxt="$TEST_DIR/t010b.txt"; printf 'file text' > "$ftxt"
  OUT="$TEST_DIR/o010b"; ERR="$TEST_DIR/e010b"
  code="$(run_gate "$f" --source "s" --text "a" --file "$ftxt")"
  assert_exit "TEST-010 --text + --file conflict" 2 "$code"
  assert_unchanged "TEST-010 --text + --file conflict" "$f"

  OUT="$TEST_DIR/o010c"; ERR="$TEST_DIR/e010c"
  code="$(run_gate "$TEST_DIR/does-not-exist.md" --source "s" --text "a")"
  assert_exit "TEST-010 missing --target" 2 "$code"
  [ ! -f "$TEST_DIR/does-not-exist.md" ] || log_fail "TEST-010: missing --target must not create the file"
  log_pass "Usage errors exit 2, nothing written (TEST-010)"
}

# --- TEST-011 (Spec-AC-01): two sequential real appends ---------------------

test_011_sequential_appends() {
  log_info "Test: two sequential real appends each succeed; the second builds on the first (TEST-011)..."
  local f="$TEST_DIR/t011.md"; fresh_copy "$f"
  OUT="$TEST_DIR/o011a"; ERR="$TEST_DIR/e011a"
  local code; code="$(run_gate "$f" --source "writer A" --text "first rule")"
  assert_exit "TEST-011 first append" 0 "$code"
  OUT="$TEST_DIR/o011b"; ERR="$TEST_DIR/e011b"
  code="$(run_gate "$f" --source "writer B" --text "second rule")"
  assert_exit "TEST-011 second append" 0 "$code"

  grep -qF "first rule (source: writer A)" "$f" || log_fail "TEST-011: first append missing after the second call"
  grep -qF "second rule (source: writer B)" "$f" || log_fail "TEST-011: second append missing"
  local first_line_no second_line_no
  first_line_no="$(grep -n "first rule (source: writer A)" "$f" | head -1 | cut -d: -f1)"
  second_line_no="$(grep -n "second rule (source: writer B)" "$f" | head -1 | cut -d: -f1)"
  [ "$first_line_no" -lt "$second_line_no" ] || log_fail "TEST-011: appends must land in call order"
  log_pass "Two sequential real appends both persist, in order (TEST-011)"
}

# --- TEST-012 (Spec-AC-01): --full no-op candidate ---------------------------

test_012_full_noop_identical() {
  log_info "Test: --full candidate identical to the current file is a zero-byte no-op, exit 0 (TEST-012)..."
  local f="$TEST_DIR/t012.md"; fresh_copy "$f"
  local same="$TEST_DIR/same012.md"; fresh_copy "$same"
  OUT="$TEST_DIR/o012"; ERR="$TEST_DIR/e012"
  local code; code="$(run_gate "$f" --full --file "$same")"
  assert_exit "TEST-012" 0 "$code"
  assert_unchanged "TEST-012" "$f"
  grep -qi "no-op" "$OUT" || log_fail "TEST-012: stdout must announce the no-op"
  log_pass "Identical --full candidate: zero-byte no-op, exit 0 (TEST-012)"
}

# --- TEST-013 (Spec-AC-04): SKILL_WRAP_UP wiring -----------------------------

test_013_wrapup_step3_wired() {
  log_info "Test: SKILL_WRAP_UP step 3 routes proposals through critic-then-gate; step 6 cross-references it (TEST-013)..."
  local step3
  step3="$(awk '
    /^3\. PROPOSE NEW LEARNED RULES/ { cap = 1; print; next }
    cap && /^4\./ { cap = 0 }
    cap { print }
  ' "$WRAP_UP_PROMPT")"
  [ -n "$step3" ] || log_fail "TEST-013: step 3 (PROPOSE NEW LEARNED RULES) section not found"
  assert_payload_contains "$step3" "learned-append.mjs" "TEST-013: step 3 must name the gate script learned-append.mjs"
  assert_payload_contains "$step3" "--source" "TEST-013: step 3 must show the --source flag in the invocation"
  printf '%s' "$step3" | grep -qi "critic" \
    || log_fail "TEST-013: step 3 must route the proposal through a critic pass"
  printf '%s' "$step3" | grep -qi "never a direct edit" \
    || log_fail "TEST-013: step 3 must state that direct edits are no longer sanctioned"
  # Ordering pin (review 20260727T111121Z NB-1): critic must PRECEDE the gate
  # invocation — gate-then-critic would be post-hoc critique of a done append.
  local crit_ln gate_ln
  crit_ln=$(printf '%s\n' "$step3" | grep -ni critic | head -1 | cut -d: -f1)
  gate_ln=$(printf '%s\n' "$step3" | grep -nF learned-append.mjs | head -1 | cut -d: -f1)
  { [ -n "$crit_ln" ] && [ -n "$gate_ln" ] && [ "$crit_ln" -lt "$gate_ln" ]; } \
    || log_fail "TEST-013: critic mention must precede the gate invocation (crit=$crit_ln gate=$gate_ln)"

  local step6
  step6="$(awk '
    /^6\. FRICTION FEEDBACK NUDGE/ { cap = 1; print; next }
    cap && /^6b\./ { cap = 0 }
    cap { print }
  ' "$WRAP_UP_PROMPT")"
  [ -n "$step6" ] || log_fail "TEST-013: step 6 (FRICTION FEEDBACK NUDGE) section not found"
  printf '%s' "$step6" | grep -qi "step 3" \
    || log_fail "TEST-013: step 6 must cross-reference the step 3 critic-then-gate flow"
  # Pinned contracts from test-aai-friction-wiring.sh TEST-015 must survive untouched.
  assert_payload_contains "$step6" "aai-feedback-triage.mjs" "TEST-013: step 6 must still name the triage engine (pinned contract)"
  printf '%s' "$step6" | grep -qi "SILENT" \
    || log_fail "TEST-013: step 6 must still document the empty-spool SILENT contract (pinned contract)"
  log_pass "SKILL_WRAP_UP step 3 critic-then-gate wired; step 6 cross-references it (TEST-013)"
}

# --- TEST-014 (Spec-AC-04): FRICTION_PROTOCOL pointer ------------------------

test_014_protocol_pointer() {
  log_info "Test: FRICTION_PROTOCOL.md carries a one-line pointer to the gate (TEST-014)..."
  local n; n="$(grep -cF "## Learned-append gate" "$PROTOCOL" || true)"
  [ "$n" = "1" ] || log_fail "TEST-014: '## Learned-append gate' heading must appear exactly once (got $n)"
  grep -qF "learned-append.mjs" "$PROTOCOL" \
    || log_fail "TEST-014: FRICTION_PROTOCOL.md must name learned-append.mjs"
  # Pinned contract from test-aai-friction-wiring.sh: the shadow-capture seam
  # heading must still appear exactly once, unaffected by the new section.
  n="$(grep -cF "## Skill wiring (shadow capture)" "$PROTOCOL" || true)"
  [ "$n" = "1" ] || log_fail "TEST-014: '## Skill wiring (shadow capture)' heading must still appear exactly once (got $n, pinned contract)"
  log_pass "FRICTION_PROTOCOL.md carries the one-line gate pointer, seam heading intact (TEST-014)"
}

# --- TEST-015 (Spec-AC-04): PROFILES classification + real suite ------------

test_015_profiles_classified() {
  log_info "Test: PROFILES.yaml classifies learned-append.mjs under core; real layer-profiles suite green (TEST-015)..."
  local core_block
  core_block="$(awk '/^core:/{cap=1; next} /^extended:/{cap=0} cap' "$PROFILES")"
  assert_payload_contains "$core_block" ".aai/scripts/learned-append.mjs" "TEST-015: .aai/scripts/learned-append.mjs must be classified under 'core:' in PROFILES.yaml"
  [ -f "$LAYER_PROFILES_TEST" ] || log_fail "TEST-015: $LAYER_PROFILES_TEST missing"
  local out code=0
  out="$(bash "$LAYER_PROFILES_TEST" 2>&1)" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-015: test-aai-layer-profiles.sh must pass (exit $code): $(printf '%s' "$out" | tail -5)"
  log_pass "learned-append.mjs classified under core; layer-profiles suite green (TEST-015)"
}

# --- TEST-016 (Spec-AC-04): prompt-diet ledger true-up -----------------------

test_016_prompt_diet_ledger() {
  log_info "Test: real test-aai-prompt-diet.sh stays green (ledger true-up proven against the live corpus) (TEST-016)..."
  [ -f "$PROMPT_DIET_TEST" ] || log_fail "TEST-016: $PROMPT_DIET_TEST missing"
  local out code=0
  out="$(bash "$PROMPT_DIET_TEST" 2>&1)" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-016: test-aai-prompt-diet.sh must pass (exit $code): $(printf '%s' "$out" | tail -8)"
  log_pass "Prompt-diet ledger trued up: real suite green (TEST-016)"
}

# --- TEST-017 (Spec-AC-05): companion suites stay green ---------------------

test_017_companion_suites_green() {
  log_info "Test: companion friction-wiring + hygiene-pack suites stay green (TEST-017)..."
  [ -f "$FRICTION_WIRING_TEST" ] || log_fail "TEST-017: $FRICTION_WIRING_TEST missing"
  [ -f "$HYGIENE_PACK_TEST" ] || log_fail "TEST-017: $HYGIENE_PACK_TEST missing"
  local out code=0
  out="$(bash "$FRICTION_WIRING_TEST" 2>&1)" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-017: test-aai-friction-wiring.sh must pass (exit $code): $(printf '%s' "$out" | tail -8)"
  code=0
  out="$(bash "$HYGIENE_PACK_TEST" 2>&1)" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-017: test-aai-hygiene-pack.sh must pass (exit $code): $(printf '%s' "$out" | tail -8)"
  log_pass "Companion suites (friction-wiring, hygiene-pack) stay green (TEST-017)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_pure_append_no_section
  test_002_section_matches_last
  test_003_section_new_heading
  test_004_full_rewrite_rejected
  test_005_full_reorder_rejected
  test_006_mid_insert_rejected
  test_007_full_deletion_rejected
  test_008_dry_run_accept
  test_009_dry_run_reject_still_fails
  test_010_usage_errors
  test_011_sequential_appends
  test_012_full_noop_identical
  test_013_wrapup_step3_wired
  test_014_protocol_pointer
  test_015_profiles_classified
  test_016_prompt_diet_ledger
  test_017_companion_suites_green

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
