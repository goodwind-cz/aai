#!/usr/bin/env bash
#
# Test: suite-reuse.mjs (spec-precise-suite-evidence-reuse).
#
# Library and CLI rows run as node:test cases in tests/skills/lib/suite-reuse.test.mjs
# (each selected by its TEST id prefix, so mutation-run.mjs can target one row);
# TEST-3188 is a shell-native contract row. Rows that need the framework wiring,
# the Pester file, the prompts or the analysis note (TEST-3165, 3175, 3177,
# 3179, 3180, 3184..3187, 3189) are added by the later runs of this change.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-suite-reuse"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/suite-reuse.test.mjs"

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

test_3166_inputs_tracked_and_untracked() { node_cases TEST-3166; }
test_3167_closure_directory_and_seed() { node_cases TEST-3167; }
test_3168_env_component() { node_cases TEST-3168; }
test_3169_args_component() { node_cases TEST-3169; }
test_3170_runtime_component() { node_cases TEST-3170; }
test_3171_policy_component() { node_cases TEST-3171; }
test_3172_history_component() { node_cases TEST-3172; }
test_3173_undeclared_live_invalid_library() { node_cases TEST-3173; }
test_3174_manifest_invalid() { node_cases TEST-3174; }
test_3176_record_refusals() { node_cases TEST-3176; }
test_3178_off_modes() { node_cases TEST-3178; }
test_3181_log_missing() { node_cases TEST-3181; }
test_3182_lint_and_live_manifest() { node_cases TEST-3182; }
test_3183_select_suites_import() { node_cases TEST-3183; }

# test_3188: PROFILES core row, selection through the real select-suites.mjs,
# source shape of the helper (line cap, imports, no shell option, identity list).
test_3188_profiles_selection_and_source_shape() {
  local src="$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
  local f out lines imp line
  grep -qxF '  - .aai/scripts/suite-reuse.mjs' "$profiles" \
    || log_fail "TEST-3188: PROFILES.yaml lacks the suite-reuse.mjs core row"
  for f in .aai/scripts/suite-reuse.mjs tests/skills/suite-reuse.json tests/skills/test-framework.sh .aai/scripts/release-dry-run.mjs; do
    out="$(printf '%s\n' "$f" | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" \
      || log_fail "TEST-3188: select-suites.mjs failed for $f"
    [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-suite-reuse($|[[:space:]]) ]] \
      || log_fail "TEST-3188: $f does not select aai-suite-reuse (got: $(printf '%s' "$out" | tr '\n' ';'))"
  done
  lines="$(wc -l < "$src" | tr -d ' ')"
  [[ "$lines" -le 600 ]] || log_fail "TEST-3188: suite-reuse.mjs has $lines lines (cap 600)"
  while IFS= read -r imp; do
    case "$imp" in
      node:*|./select-suites.mjs|./lib/tree-hash.mjs) ;;
      *) log_fail "TEST-3188: suite-reuse.mjs imports '$imp'" ;;
    esac
  done < <(sed -n "s/^import .* from '\\([^']*\\)';\$/\\1/p" "$src")
  if grep -qE 'shell:[[:space:]]*true' "$src"; then log_fail "TEST-3188: suite-reuse.mjs sets shell: true"; fi
  line="$(grep -m1 'IDENTITY_COMPONENTS = ' "$src" || true)"
  [[ "$line" == "const IDENTITY_COMPONENTS = ['inputs', 'env', 'args', 'runtime', 'policy', 'history'];" ]] \
    || log_fail "TEST-3188: IDENTITY_COMPONENTS line differs from the D4 literal: $line"
  log_pass "TEST-3188 (core row, selection, imports, no shell option, $lines lines)"
}

# test_3190: the guarded select-suites.mjs still runs as the entry point and prints
# its selection (CLI contract); the full contract is the unchanged aai-suite-select
# suite, run in Verification. This row exists so the guard's mutation record can
# name a TEST id in a FAIL line.
test_3190_select_suites_cli_still_runs() {
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs" out rc=0
  out="$(printf '%s\n' .aai/scripts/ride-status.mjs | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-3190: select-suites.mjs exited $rc as the entry point"
  [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-ride-status($|[[:space:]]) ]] \
    || log_fail "TEST-3190: select-suites.mjs printed no SELECTED aai-ride-status line (got: $(printf '%s' "$out" | tr '\n' ';'))"
  log_pass "TEST-3190 (select-suites.mjs entry point prints its selection)"
}

main() {
  echo "Testing $TEST_NAME (spec-precise-suite-evidence-reuse)"
  check_deps
  test_3166_inputs_tracked_and_untracked
  test_3167_closure_directory_and_seed
  test_3168_env_component
  test_3169_args_component
  test_3170_runtime_component
  test_3171_policy_component
  test_3172_history_component
  test_3173_undeclared_live_invalid_library
  test_3174_manifest_invalid
  test_3176_record_refusals
  test_3178_off_modes
  test_3181_log_missing
  test_3182_lint_and_live_manifest
  test_3183_select_suites_import
  test_3188_profiles_selection_and_source_shape
  test_3190_select_suites_cli_still_runs
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
