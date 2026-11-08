#!/usr/bin/env bash
#
# Test: aai-release-cut
# (docs/specs/SPEC-DRAFT-spec-release-on-node.md, TEST-3462..3477)
#
# release-cut is one Node module (.aai/scripts/release-cut.mjs) behind aai-release.sh and aai-release.ps1.
# Every case works in fresh mktemp fixtures with a stub gh first on PATH and local bare origins; no case runs
# a real gh, pushes to a network remote, opens a PR, tags or publishes, and none reads or writes the
# repository's own CHANGELOG.md (the preamble arm runs through the test-aai-release.sh selector).
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-release-cut.sh                      # run all
#   bash tests/skills/test-aai-release-cut.sh test_3462_seam
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-release-cut"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/release-cut.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/release-cut.test.mjs"
SH_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-release.sh"
PS1_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-release.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/release-cut.Tests.ps1"
SPEC_ID="spec-release-on-node"
MISSING_NODE='REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.'

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-release-cut-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/release-cut.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/release-cut.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# code_lines <file> <comment prefix: # or //>: non-blank, non-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE "^[[:space:]]*($2|\$)" "$1" || true
}

test_3462_seam() {
  run_node_tests TEST-3462
  log_pass "TEST-3462: importing the module has no side effect and run drives the audit seam"
}

test_3463_plan_contract() {
  run_node_tests TEST-3463
  log_pass "TEST-3463: the module CLI plan meets the D-OUT contract for both launchers and writes nothing"
}

test_3464_rollup_drift() {
  run_node_tests TEST-3464
  log_pass "TEST-3464: DR-01 to DR-09 behave as decided"
}

test_3465_plan_drift() {
  run_node_tests TEST-3465
  log_pass "TEST-3465: DR-10 and DR-12 to DR-18 behave as decided"
}

test_3466_files_and_launch() {
  run_node_tests TEST-3466
  log_pass "TEST-3466: DR-11 and DR-19 to DR-22 behave as decided"
}

# drift_problems <spec> <node test file>: DR ids of the D-DRIFT table vs test names (empty when they agree).
drift_problems() {
  cat > "$TEST_DIR/drift.cjs" <<'JS'
const fs = require('fs');
const [spec, tests] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DR-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [...fs.readFileSync(tests, 'utf8').matchAll(/^test\('(?:TEST-\d+ )?(DR-\d\d)\b/gm)].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length !== 22) bad.push(`the table holds ${table.length} ids, expected 22`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/drift.cjs" "$1" "$2"
}

test_3467_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3467: no spec with id $SPEC_ID under docs/specs"
  [[ -f "$NODE_TEST" ]] || log_fail "TEST-3467: tests/skills/lib/release-cut.test.mjs does not exist"
  out="$(drift_problems "$spec" "$NODE_TEST")"
  [[ -z "$out" ]] || log_fail "TEST-3467: $out"
  sed "s/'TEST-3465 DR-13 /'TEST-3465 DR-31 /" "$NODE_TEST" > "$TEST_DIR/renamed.test.mjs"
  out="$(drift_problems "$spec" "$TEST_DIR/renamed.test.mjs")"
  [[ "$out" == *"DR-13 begins 0"* && "$out" == *"DR-31 is not in"* ]] || log_fail "TEST-3467: positive control: the renamed DR-13 was not reported ($out)"
  log_pass "TEST-3467: every D-DRIFT id begins exactly one node:test case and no case names a missing id"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3462..3477)"
  check_deps
  setup_fixture
  test_3462_seam
  test_3463_plan_contract
  test_3464_rollup_drift
  test_3465_plan_drift
  test_3466_files_and_launch
  test_3467_drift_coverage
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
