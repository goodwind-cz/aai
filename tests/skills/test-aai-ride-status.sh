#!/usr/bin/env bash
#
# Test: ride-status.mjs (spec-ride-status-and-resume).
#
# TEST-3144..TEST-3155 run as node:test cases in tests/skills/lib/ride-status.test.mjs
# (each selected by its TEST id prefix, so mutation-run.mjs can target one row);
# TEST-3156..TEST-3158 are shell-native rows.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-ride-status"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/ride-status.test.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

# node_cases <TEST-id>: run the node:test cases whose name starts with the id.
# A pattern that matches nothing would pass vacuously, so the TAP tally must
# show at least one passing case and no failing one.
node_cases() {
  local id="$1" out="" rc=0 passed failed
  out="$(env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern="^$id " "$NODE_TEST" 2>&1)" || rc=$?
  passed="$(printf '%s\n' "$out" | sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p')"
  failed="$(printf '%s\n' "$out" | sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p')"
  if [[ "$rc" -ne 0 || "${failed:-1}" != 0 || "${passed:-0}" -lt 1 ]]; then
    printf '%s\n' "$out" | sed -n '1,60p' >&2
    log_fail "$id node cases failed (rc=$rc pass=${passed:-?} fail=${failed:-?})"
  fi
  log_pass "$id ($passed node case(s))"
}

test_3144_status_text_six_lines() { node_cases TEST-3144; }
test_3145_status_json_keys() { node_cases TEST-3145; }
test_3146_no_focus() { node_cases TEST-3146; }
test_3147_no_write() { node_cases TEST-3147; }
test_3148_agrees_with_dispatcher() { node_cases TEST-3148; }
test_3149_blocker_kinds() { node_cases TEST-3149; }
test_3150_next_decision() { node_cases TEST-3150; }
test_3151_strategy_reuse() { node_cases TEST-3151; }

# test_3158: PROFILES core row, suite selection through the real select-suites.mjs,
# no launcher pair, no write call, no shell option, line cap.
test_3158_profiles_selection_and_source_shape() {
  local src="$PROJECT_ROOT/.aai/scripts/ride-status.mjs"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
  local f out lines
  grep -qxF '  - .aai/scripts/ride-status.mjs' "$profiles" \
    || log_fail "TEST-3158: PROFILES.yaml lacks the ride-status.mjs core row"
  for f in .aai/scripts/ride-status.mjs .aai/SKILL_SHIP.prompt.md .aai/SKILL_PR.prompt.md .aai/SKILL_LOOP.prompt.md; do
    out="$(printf '%s\n' "$f" | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" \
      || log_fail "TEST-3158: select-suites.mjs failed for $f"
    [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-ride-status($|[[:space:]]) ]] \
      || log_fail "TEST-3158: $f does not select aai-ride-status (got: $(printf '%s' "$out" | tr '\n' ';'))"
  done
  [[ ! -e "$PROJECT_ROOT/.aai/scripts/ride-status.sh" && ! -e "$PROJECT_ROOT/.aai/scripts/ride-status.ps1" ]] \
    || log_fail "TEST-3158: a ride-status launcher exists"
  for f in writeFileSync appendFileSync renameSync mkdirSync rmSync unlinkSync copyFileSync; do
    if grep -qF "$f" "$src"; then log_fail "TEST-3158: ride-status.mjs holds $f"; fi
  done
  if grep -qE 'shell:[[:space:]]*true' "$src"; then log_fail "TEST-3158: ride-status.mjs sets shell: true"; fi
  lines="$(wc -l < "$src" | tr -d ' ')"
  [[ "$lines" -le 400 ]] || log_fail "TEST-3158: ride-status.mjs has $lines lines (cap 400)"
  log_pass "TEST-3158 (core row, selection, no launcher, no writes, $lines lines)"
}

main() {
  echo "Testing $TEST_NAME (spec-ride-status-and-resume)"
  check_deps
  test_3144_status_text_six_lines
  test_3145_status_json_keys
  test_3146_no_focus
  test_3147_no_write
  test_3148_agrees_with_dispatcher
  test_3149_blocker_kinds
  test_3150_next_decision
  test_3151_strategy_reuse
  test_3158_profiles_selection_and_source_shape
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Single-function invocation mode (mutation-run.mjs positional dispatch).
  if [[ -n "${1:-}" ]]; then
    "$1"
  else
    main "$@"
  fi
fi
