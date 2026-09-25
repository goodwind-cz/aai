#!/usr/bin/env bash
#
# Test: ledger-merge.mjs (spec-friction-channel-sweep Spec-AC-09,
# fu-learned-ledger-merge-procedure). The append-only JSONL ledger merge
# procedure docs/knowledge/LEARNED.md has described in PROSE since 2026-08-24,
# as a command:
#   .aai/scripts/ledger-merge.mjs — keeps the base side a byte-exact PREFIX
#     and appends both sides' new lines after it; refuses (exit 1, nothing
#     written) when either side does not carry base as a byte-exact prefix.
#   .aai/system/PROFILES.yaml — classifies the new script exactly once.
#   tests/skills/suite-map.yaml — carries a row for THIS suite naming the
#     script.
#
# Test map:
#   TEST-666 (Spec-AC-09) four fixture merges (disjoint additions, one side
#             empty, identical sides, a base whose bytes were rewritten)
#             each produce the expected bytes or the expected non-zero
#             refusal; per-side contributed line counts are reported.
#   TEST-667 (Spec-AC-09) PROFILES.yaml classifies the script exactly once;
#             suite-map.yaml carries a row for this suite naming it.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty          -> TEST-666 arm B (one side empty).
#   - zero-remainder            -> TEST-666 arm C (identical sides: nothing
#                                  new for theirs to contribute after dedupe).
#   - multi-source/multi-writer -> TEST-666 arm A (disjoint additions from
#                                  two independent sides).
#   - mid-operation failure     -> TEST-666 arm D (a rewritten base refuses,
#                                  nothing written).
#   - negative control          -> TEST-666 arm D's own non-zero exit +
#                                  absent --out file.
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Node stdlib only.
#
# Usage:
#   bash tests/skills/test-aai-ledger-merge.sh                # run all
#   bash tests/skills/test-aai-ledger-merge.sh test_666_...    # run one
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-ledger-merge"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCRIPT="$PROJECT_ROOT/.aai/scripts/ledger-merge.mjs"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
SUITE_MAP="$PROJECT_ROOT/tests/skills/suite-map.yaml"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

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
  [ -f "$PROFILES" ] || log_fail "PROFILES.yaml not found: $PROFILES"
  [ -f "$SUITE_MAP" ] || log_fail "suite-map.yaml not found: $SUITE_MAP"
  # NOTE: SCRIPT is intentionally NOT required here — the RED phase runs
  # against the absent script so TEST-666 fails on its own assertion
  # (product_red), not a missing-precondition skip.
  log_pass "Dependencies checked"
}

run_merge() {
  # run_merge <base> <ours> <theirs> <out> -> prints exit code on stdout;
  # stdout/stderr of the CLI captured to $OUT/$ERR.
  local base="$1" ours="$2" theirs="$3" out="$4"
  local code=0
  node "$SCRIPT" --base "$base" --ours "$ours" --theirs "$theirs" --out "$out" > "$OUT" 2> "$ERR" || code=$?
  echo "$code"
}
OUT=""; ERR=""

# --- TEST-666 (Spec-AC-09): four fixture merges ------------------------------

test_666_merge_keeps_base_prefix() {
  log_info "Test: base stays a byte-exact prefix; both sides' new lines appended after it; per-side contributed counts reported; a rewritten base refuses (TEST-666)..."

  # --- Arm A: disjoint additions -------------------------------------------
  local base="$TEST_DIR/a-base.jsonl"
  printf '{"e":"b1"}\n{"e":"b2"}\n' > "$base"
  local ours="$TEST_DIR/a-ours.jsonl"
  cat "$base" > "$ours"; printf '{"e":"o1"}\n{"e":"o2"}\n' >> "$ours"
  local theirs="$TEST_DIR/a-theirs.jsonl"
  cat "$base" > "$theirs"; printf '{"e":"t1"}\n{"e":"t2"}\n{"e":"t3"}\n' >> "$theirs"
  local out="$TEST_DIR/a-out.jsonl"
  OUT="$TEST_DIR/a-out.log"; ERR="$TEST_DIR/a-err.log"
  local code; code="$(run_merge "$base" "$ours" "$theirs" "$out")"
  [ "$code" = "0" ] || log_fail "TEST-666 arm A: expected exit 0, got $code: $(cat "$ERR")"
  local expected="$TEST_DIR/a-expected.jsonl"
  cat "$base" > "$expected"
  printf '{"e":"o1"}\n{"e":"o2"}\n{"e":"t1"}\n{"e":"t2"}\n{"e":"t3"}\n' >> "$expected"
  cmp -s "$expected" "$out" || log_fail "TEST-666 arm A: merged bytes did not match the expected disjoint-union file"
  grep -qF "ours contributed 2 line(s)" "$OUT" || log_fail "TEST-666 arm A: stdout must report ours contributed 2 line(s), got: $(cat "$OUT")"
  grep -qF "theirs contributed 3 line(s)" "$OUT" || log_fail "TEST-666 arm A: stdout must report theirs contributed 3 line(s), got: $(cat "$OUT")"

  # --- Arm B: one side empty (theirs == base, nothing new) -----------------
  local ours_b="$TEST_DIR/b-ours.jsonl"
  cat "$base" > "$ours_b"; printf '{"e":"o1"}\n' >> "$ours_b"
  local out_b="$TEST_DIR/b-out.jsonl"
  OUT="$TEST_DIR/b-out.log"; ERR="$TEST_DIR/b-err.log"
  code="$(run_merge "$base" "$ours_b" "$base" "$out_b")"
  [ "$code" = "0" ] || log_fail "TEST-666 arm B: expected exit 0, got $code: $(cat "$ERR")"
  cmp -s "$ours_b" "$out_b" || log_fail "TEST-666 arm B: with theirs == base, output must equal ours exactly"
  grep -qF "theirs contributed 0 line(s)" "$OUT" || log_fail "TEST-666 arm B: stdout must report theirs contributed 0 line(s), got: $(cat "$OUT")"

  # --- Arm C: identical sides (ours == theirs, byte-identical) -------------
  local ours_c="$TEST_DIR/c-ours.jsonl"
  cat "$base" > "$ours_c"; printf '{"e":"same1"}\n{"e":"same2"}\n' >> "$ours_c"
  local theirs_c="$TEST_DIR/c-theirs.jsonl"
  cp "$ours_c" "$theirs_c"
  local out_c="$TEST_DIR/c-out.jsonl"
  OUT="$TEST_DIR/c-out.log"; ERR="$TEST_DIR/c-err.log"
  code="$(run_merge "$base" "$ours_c" "$theirs_c" "$out_c")"
  [ "$code" = "0" ] || log_fail "TEST-666 arm C: expected exit 0, got $code: $(cat "$ERR")"
  cmp -s "$ours_c" "$out_c" || log_fail "TEST-666 arm C: identical sides must merge to exactly that content, not a duplicate"
  grep -qF "ours contributed 2 line(s)" "$OUT" || log_fail "TEST-666 arm C: stdout must report ours contributed 2 line(s), got: $(cat "$OUT")"
  grep -qF "theirs contributed 0 line(s)" "$OUT" || log_fail "TEST-666 arm C: identical theirs must contribute 0 NEW line(s) (fully deduped), got: $(cat "$OUT")"

  # --- Arm D: a base whose bytes were rewritten (not merely extended) ------
  local theirs_d="$TEST_DIR/d-theirs.jsonl"
  printf '{"e":"REWRITTEN"}\n{"e":"b2"}\n{"e":"t1"}\n' > "$theirs_d"
  local out_d="$TEST_DIR/d-out.jsonl"
  OUT="$TEST_DIR/d-out.log"; ERR="$TEST_DIR/d-err.log"
  code="$(run_merge "$base" "$ours" "$theirs_d" "$out_d")"
  [ "$code" != "0" ] || log_fail "TEST-666 arm D: a rewritten base must refuse (non-zero exit), got 0"
  [ ! -f "$out_d" ] || log_fail "TEST-666 arm D: a refused merge must write NOTHING to --out"
  grep -qi "prefix" "$ERR" || log_fail "TEST-666 arm D: stderr must name the prefix violation, got: $(cat "$ERR")"

  log_pass "Base stays a byte-exact prefix across all four fixture arms; per-side counts reported; a rewritten base refuses cleanly (TEST-666)"
}

# --- TEST-667 (Spec-AC-09): classification + suite-map row ------------------

test_667_new_script_is_classified() {
  log_info "Test: PROFILES.yaml classifies ledger-merge.mjs exactly once; suite-map.yaml carries a row for this suite naming it (TEST-667)..."
  local n; n="$(grep -cF '.aai/scripts/ledger-merge.mjs' "$PROFILES" || true)"
  [ "$n" = "1" ] || log_fail "TEST-667: PROFILES.yaml must classify .aai/scripts/ledger-merge.mjs EXACTLY once, found $n"
  [ -f "$LAYER_PROFILES_TEST" ] || log_fail "TEST-667: $LAYER_PROFILES_TEST missing"
  local out code=0
  out="$(bash "$LAYER_PROFILES_TEST" 2>&1)" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-667: test-aai-layer-profiles.sh must pass (exit $code): $(printf '%s' "$out" | tail -5)"

  local row_block
  row_block="$(awk '/^  aai-ledger-merge:/{cap=1; print; next} cap && /^  [a-zA-Z]/{exit} cap' "$SUITE_MAP")"
  [ -n "$row_block" ] || log_fail "TEST-667: suite-map.yaml must carry a 'aai-ledger-merge:' row"
  case "$row_block" in
    *".aai/scripts/ledger-merge.mjs"*) : ;;
    *) log_fail "TEST-667: the aai-ledger-merge suite-map row must name .aai/scripts/ledger-merge.mjs" ;;
  esac
  log_pass "ledger-merge.mjs classified exactly once; suite-map.yaml row present and correct (TEST-667)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-ledger-merge-test.XXXXXX")"

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_666_merge_keeps_base_prefix
  test_667_new_script_is_classified

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
