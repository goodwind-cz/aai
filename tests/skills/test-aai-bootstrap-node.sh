#!/usr/bin/env bash
#
# Test: aai-bootstrap-node
# (docs/specs/SPEC-DRAFT-bootstrap-on-node.md, TEST-3940..3959; this file grows run by run)
#
# The project bootstrap is one Node module (.aai/scripts/aai-bootstrap.mjs) behind thin sh/ps1 launchers,
# compared against a frozen bash reference (tests/fixtures/aai-bootstrap-reference/). Every case works in
# scratch directories this run created (own prefix, ownership marker); nothing here starts a container
# tool, kills by pattern, or removes a path it did not provably create (D-SAFETY).
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-bootstrap-node.sh                       # run all
#   bash tests/skills/test-aai-bootstrap-node.sh test_3940_scratch_safety
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-bootstrap-node"
TEST_DIR=""
OWN_PREFIX="aai-bootstrap-node."
OWN_MARKER=".aai-bs-owned"

# The script directory without a cd inside a command substitution (the cd-subshell ratchet).
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" != "${BASH_SOURCE[0]}" ]] || SCRIPT_DIR="."
case "$SCRIPT_DIR" in /*) ;; *) SCRIPT_DIR="$PWD/$SCRIPT_DIR" ;; esac
. "$SCRIPT_DIR/lib/pipe-safe.sh"

# phys_path <path>: the physical absolute path (symlinks resolved); empty and failing when it does not exist.
phys_path() {
  node -e 'try { process.stdout.write(require("fs").realpathSync(process.argv[1])); } catch (e) { process.exit(1); }' "$1"
}

PROJECT_ROOT="$(phys_path "$SCRIPT_DIR/../..")"
MJS="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/aai-bootstrap.test.mjs"
REF_HELPER="$PROJECT_ROOT/tests/skills/lib/bootstrap-reference.mjs"
REFERENCE="$PROJECT_ROOT/tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh"
SPEC_ID="spec-bootstrap-on-node"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# safe_rm_own <path>...: removes only scratch directories this suite created. It fails the test (never
# skips) for no path at all, an empty path, a relative path, a basename without the own prefix, a path
# outside the temp directory, a symbolic link and a directory without the numeric ownership marker; the
# marker is read again right before the removal.
safe_rm_own() {
  [[ "$#" -gt 0 ]] || log_fail "safe_rm_own: an empty list of paths to remove is a failure"
  local p base real tmp_real
  for p in "$@"; do
    [[ -n "$p" ]] || log_fail "safe_rm_own: empty path"
    [[ "$p" == /* ]] || log_fail "safe_rm_own: relative path: $p"
    base="${p%/}"
    base="${base##*/}"
    [[ "$base" == "$OWN_PREFIX"* ]] || log_fail "safe_rm_own: basename lacks the own prefix $OWN_PREFIX: $p"
    [[ -d "$p" && ! -L "$p" ]] || log_fail "safe_rm_own: not a real directory: $p"
    real="$(phys_path "$p")" || log_fail "safe_rm_own: cannot resolve $p"
    tmp_real="$(phys_path "${TMPDIR:-/tmp}")" || log_fail "safe_rm_own: cannot resolve the temp directory"
    case "$real" in "$tmp_real"/*) ;; *) log_fail "safe_rm_own: outside the temp directory: $p" ;; esac
    [[ "$(cat "$real/$OWN_MARKER" 2>/dev/null)" =~ ^[0-9]+$ ]] || log_fail "safe_rm_own: no ownership marker in $p"
    [[ "$(cat "$real/$OWN_MARKER" 2>/dev/null)" =~ ^[0-9]+$ ]] || log_fail "safe_rm_own: ownership marker vanished in $p"
    rm -rf -- "$real"
  done
}

# new_own_scratch <label>: prints a fresh own scratch directory (own prefix, marker holding this process id).
new_own_scratch() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/${OWN_PREFIX}$1.XXXXXX")" || log_fail "mktemp failed"
  d="$(phys_path "$d")"
  printf '%s\n' "$$" > "$d/$OWN_MARKER"
  printf '%s\n' "$d"
}

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then safe_rm_own "$TEST_DIR"; fi
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(new_own_scratch suite)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/aai-bootstrap.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/aai-bootstrap.test.mjs does not exist"
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

# expect_refused <label> <safe_rm_own args...>: safe_rm_own must fail the test (here: end its subshell non-zero).
expect_refused() {
  local label="$1"
  shift
  if ( safe_rm_own "$@" ) >/dev/null 2>&1; then
    log_fail "TEST-3940: safe_rm_own accepted $label"
  fi
}

test_3940_scratch_safety() {
  run_node_tests TEST-3940
  # safe_rm_own refuses an empty list, an empty, a relative, a foreign, an outside and an unmarked path
  local work foreign unmarked marked
  work="$(new_own_scratch safe)"
  foreign="$work/foreign-name"
  unmarked="$work/${OWN_PREFIX}unmarked"
  marked="$work/${OWN_PREFIX}marked"
  mkdir "$foreign" "$unmarked" "$marked"
  printf '%s\n' "$$" > "$foreign/$OWN_MARKER"
  printf '%s\n' "$$" > "$marked/$OWN_MARKER"
  expect_refused "an empty list"
  expect_refused "an empty path" ""
  expect_refused "a relative path" "${OWN_PREFIX}relative"
  expect_refused "a foreign basename" "$foreign"
  expect_refused "a directory without the marker" "$unmarked"
  expect_refused "a missing directory" "$work/${OWN_PREFIX}missing"
  expect_refused "a path outside the temp directory" "/${OWN_PREFIX}outside"
  expect_refused "the project root" "$PROJECT_ROOT"
  [[ -d "$foreign" && -d "$unmarked" && -d "$marked" ]] || log_fail "TEST-3940: a refused path was removed"
  # a marked directory with the prefix is removed, and only it
  safe_rm_own "$marked"
  [[ ! -e "$marked" && -d "$foreign" && -d "$unmarked" ]] || log_fail "TEST-3940: safe_rm_own removed the wrong set"
  # a symbolic link with the prefix is refused and its target survives
  ln -s "$unmarked" "$work/${OWN_PREFIX}link"
  expect_refused "a symbolic link" "$work/${OWN_PREFIX}link"
  [[ -d "$unmarked" ]] || log_fail "TEST-3940: the link target was removed"
  safe_rm_own "$work"
  [[ ! -e "$work" ]] || log_fail "TEST-3940: the own scratch root was not removed"
  [[ -f "$REFERENCE" && -f "$REF_HELPER" ]] || log_fail "TEST-3940: the reference copy or its helper is missing"
  log_pass "TEST-3940: scratch removal refuses each unsafe path, the reference copy is pinned, no test file calls a container tool or a kill by pattern"
}

test_3941_module_shape() {
  run_node_tests TEST-3941
  log_pass "TEST-3941: the module imports only node: specifiers, exports the D-MODULE names, holds each anchor once and starts children only through spawnSync(process.execPath"
}

test_3942_cli_and_root() {
  run_node_tests TEST-3942
  log_pass "TEST-3942: modes in any position, help per DR-1, exit 2 on a second positional, DR-2 for a missing target, root resolution per D-ROOT"
}

test_3943_detection() {
  run_node_tests TEST-3943
  log_pass "TEST-3943: one positive and one negative fixture per detection rule, lockfile precedence, first-seen order without duplicates, package.json queries on invalid and null JSON"
}

test_3944_commands() {
  run_node_tests TEST-3944
  log_pass "TEST-3944: each command chain step on its own fixture, task runner precedence, script and exec forms per manager, dockerTag"
}

test_3945_auth_and_plan() {
  run_node_tests TEST-3945
  log_pass "TEST-3945: the auth search and credential order, the session line, the skill plan and its extra blocks, equal to the reference on shared fixtures"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3940..3945 so far)"
  check_deps
  setup_fixture
  test_3940_scratch_safety
  test_3941_module_shape
  test_3942_cli_and_root
  test_3943_detection
  test_3944_commands
  test_3945_auth_and_plan
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
