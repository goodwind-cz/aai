#!/usr/bin/env bash
#
# Test: aai-hook-gate
# (docs/specs/SPEC-DRAFT-spec-hook-gate-on-node.md, TEST-3500..3514)
#
# The Claude hook gate decides in one Node module (.aai/scripts/hook-gate.mjs) behind the bash launcher
# .aai/scripts/claude-hook-gate.sh. Every case works in fresh mktemp fixtures with a stub gh first on PATH;
# payloads are written to files and redirected in (no live pipe); no case runs a real gh, az or network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-hook-gate.sh                    # run all
#   bash tests/skills/test-aai-hook-gate.sh test_3500_seam
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-hook-gate"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/hook-gate.mjs"
LAUNCHER="$PROJECT_ROOT/.aai/scripts/claude-hook-gate.sh"
NODE_TEST="${AAI_HOOK_GATE_NODE_TEST:-$PROJECT_ROOT/tests/skills/lib/hook-gate.test.mjs}"
SPEC_ID="spec-hook-gate-on-node"

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-hook-gate-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/hook-gate.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/hook-gate.test.mjs does not exist"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
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

test_3500_seam() {
  run_node_tests TEST-3500
  log_pass "TEST-3500: importing the module has no side effect; the CLI fails open and never writes stdout"
}

test_3501_parity() {
  need_tool TEST-3501 git || return 0
  git -C "$PROJECT_ROOT" cat-file -e "c88cf708^{commit}" 2>/dev/null \
    || log_fail "TEST-3501: base commit c88cf708 is not a local object (a full-history checkout is required)"
  run_node_tests TEST-3501
  log_pass "TEST-3501: launcher and the c88cf708 script give the same exit code and bytes on every untagged corpus row"
}

# drift_problems <spec> <node test file>: DG ids of the D-DRIFT table vs test names (empty when they agree).
drift_problems() {
  cat > "$TEST_DIR/drift.cjs" <<'JS'
const fs = require('fs');
const [spec, tests] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DG-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [...fs.readFileSync(tests, 'utf8').matchAll(/^\s*test\('(DG-\d\d)\b/gm)].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length < 9) bad.push(`the table holds ${table.length} ids, expected at least 9`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/drift.cjs" "$1" "$2"
}

test_3502_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3502: no spec with id $SPEC_ID under docs/specs"
  [[ -f "$NODE_TEST" ]] || log_fail "TEST-3502: tests/skills/lib/hook-gate.test.mjs does not exist"
  out="$(drift_problems "$spec" "$NODE_TEST")"
  [[ -z "$out" ]] || log_fail "TEST-3502: $out"
  sed "s/'DG-06 /'DG-60 /" "$NODE_TEST" > "$TEST_DIR/renamed.test.mjs"
  out="$(drift_problems "$spec" "$TEST_DIR/renamed.test.mjs")"
  [[ "$out" == *"DG-06 begins 0"* && "$out" == *"DG-60 is not in"* ]] || log_fail "TEST-3502: positive control: the renamed DG-06 was not reported ($out)"
  log_pass "TEST-3502: every D-DRIFT id begins exactly one node:test case and no case names a missing id"
}

test_3503_azure_forms() {
  run_node_tests TEST-3503
  log_pass "TEST-3503: the Azure merge forms are denied like gh pr merge and judged by gate 2b (DG-01)"
}

test_3504_inherited_pipefail() {
  run_node_tests TEST-3504
  log_pass "TEST-3504: an exported pipefail does not flip the merge, state-dump or commit decision (DG-02)"
}

test_3505_kept_decisions() {
  run_node_tests TEST-3505
  log_pass "TEST-3505: DG-03 to DG-09 behave as decided"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3500..3514)"
  check_deps
  setup_fixture
  test_3500_seam
  test_3501_parity
  test_3502_drift_coverage
  test_3503_azure_forms
  test_3504_inherited_pipefail
  test_3505_kept_decisions
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
