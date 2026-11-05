#!/usr/bin/env bash
#
# Test: aai-legacy-migrations
# (docs/specs/SPEC-DRAFT-spec-retire-legacy-migrations.md, TEST-3380..3400)
#
# The legacy-migration retirement: migrate-state-to-local is one Node module
# (.aai/scripts/migrate-state-to-local.mjs) behind thin launchers, and
# aai-canonicalize / migrate-yaml-to-jsonl are deprecation launchers. Every case
# here works in fresh mktemp fixtures; nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-legacy-migrations.sh                       # run all
#   bash tests/skills/test-aai-legacy-migrations.sh test_3380_pure
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-legacy-migrations"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/migrate-state-to-local.test.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-legacy-migrations-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/migrate-state-to-local.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/migrate-state-to-local.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

test_3380_pure() {
  run_node_tests TEST-3380
  log_pass "TEST-3380: IGNORE_PATTERNS, parseArgs, missingPatterns and gitignoreAppend follow D1"
}

test_3381_effects() {
  run_node_tests TEST-3381
  log_pass "TEST-3381: a legacy fixture is migrated once and a second run is a byte-identical no-op"
}

test_3382_refusals_dry_run() {
  run_node_tests TEST-3382
  log_pass "TEST-3382: every refusal carries its D1 text and exit code, and a dry run changes nothing"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-retire-legacy-migrations TEST-3380..3400)"
  check_deps
  setup_fixture
  test_3380_pure
  test_3381_effects
  test_3382_refusals_dry_run
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
