#!/usr/bin/env bash
#
# Test: aai-update-node
# (docs/specs/SPEC-DRAFT-update-on-node.md, TEST-3960..3978; this file grows run by run)
#
# The layer updater is one Node module (.aai/scripts/aai-update.mjs) behind thin sh/ps1 launchers,
# compared against frozen copies of both old twins (tests/fixtures/aai-update-reference/). Every case
# works in scratch directories this run created (own prefix, ownership marker); nothing here starts a
# container tool, kills by pattern, or removes a path it did not provably create (D-SAFETY). No test
# reaches the network, and no update run takes this checkout as its source.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-update-node.sh                       # run all
#   bash tests/skills/test-aai-update-node.sh test_3960_scratch_safety
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-update-node"
TEST_DIR=""
OWN_PREFIX="aai-update-node."
OWN_MARKER=".aai-up-owned"

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
MJS="$PROJECT_ROOT/.aai/scripts/aai-update.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/aai-update.test.mjs"
REF_HELPER="$PROJECT_ROOT/tests/skills/lib/update-reference.mjs"
REFERENCE_SH="$PROJECT_ROOT/tests/fixtures/aai-update-reference/aai-update.sh"
REFERENCE_PS1="$PROJECT_ROOT/tests/fixtures/aai-update-reference/aai-update.ps1"
SPEC_ID="spec-update-on-node"

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
  # A failed test leaves its own scratch behind: sweep, through safe_rm_own, exactly the directories of the own
  # prefix whose marker holds this process id. Leftovers of other runs carry another id and are not touched.
  local d mine=()
  for d in "${TMPDIR:-/tmp}/${OWN_PREFIX}"*; do
    [[ -d "$d" && ! -L "$d" && "$(cat "$d/$OWN_MARKER" 2>/dev/null)" == "$$" ]] && mine+=("$d")
  done
  if [[ "${#mine[@]}" -gt 0 ]]; then safe_rm_own "${mine[@]}"; fi
  return 0
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

# run_node_tests <TEST id>: the module, its helper and the node test file must exist; cases named with the
# id must pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/aai-update.mjs does not exist"
  [[ -f "$REF_HELPER" ]] || log_fail "$id: tests/skills/lib/update-reference.mjs does not exist"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" ]] || log_fail "$id: a frozen reference copy under tests/fixtures/aai-update-reference does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/aai-update.test.mjs does not exist"
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
    log_fail "TEST-3960: safe_rm_own accepted $label"
  fi
}

test_3960_scratch_safety() {
  run_node_tests TEST-3960
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
  [[ -d "$foreign" && -d "$unmarked" && -d "$marked" ]] || log_fail "TEST-3960: a refused path was removed"
  # a marked directory with the prefix is removed, and only it
  safe_rm_own "$marked"
  [[ ! -e "$marked" && -d "$foreign" && -d "$unmarked" ]] || log_fail "TEST-3960: safe_rm_own removed the wrong set"
  # a symbolic link with the prefix is refused and its target survives
  ln -s "$unmarked" "$work/${OWN_PREFIX}link"
  expect_refused "a symbolic link" "$work/${OWN_PREFIX}link"
  [[ -d "$unmarked" ]] || log_fail "TEST-3960: the link target was removed"
  safe_rm_own "$work"
  [[ ! -e "$work" ]] || log_fail "TEST-3960: the own scratch root was not removed"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" && -f "$REF_HELPER" ]] || log_fail "TEST-3960: a reference copy or its helper is missing"
  log_pass "TEST-3960: scratch removal refuses each unsafe path, both reference copies are pinned, no test file calls a container tool or a kill by pattern, every update invocation is network-free under the scratch root"
}

test_3961_module_shape() {
  run_node_tests TEST-3961
  log_pass "TEST-3961: the module imports only node: specifiers, exports the D-MODULE names, holds each anchor once, calls spawnSync once, writes only through descriptors 1 and 2 and holds no relocation copy"
}

test_3962_cli_and_base() {
  run_node_tests TEST-3962
  log_pass "TEST-3962: every accepted form in any order with the last wins rule, help per DR-1, DR-2 for an unknown argument, DR-3 for a missing value, base directory per DR-21"
}

test_3963_canonical_guard() {
  run_node_tests TEST-3963
  log_pass "TEST-3963: normSlug reduces every accepted form, a canonical target is refused with the three DR-6 lines and exit 2 before any temp or sync, and no refusal happens with force, a local directory, another repository or no origin"
}

test_3964_source_resolution() {
  run_node_tests TEST-3964
  log_pass "TEST-3964: the local checkout commands run in a real run only, cloneUrl per DR-22, three clone attempts into tmp/src with the stdio closed and the prompt setting on the third only, exit 3 with the auth or DR-18 line"
}

test_3965_temp_lifecycle() {
  run_node_tests TEST-3965
  log_pass "TEST-3965: no aai-src. directory remains after success, exit 3, exit 4, a failing sync or an internal error; --keep-temp keeps one; removeOwnTemp refuses and reports a path it did not create"
}

test_3966_runner_and_sync() {
  run_node_tests TEST-3966
  log_pass "TEST-3966: resolveRunner and syncCommand per D-RUNNER, an invalid runner exits 1 before any child, exit 4 names the runner's sync file, a failing sync is passed through with no evidence, the runner variable is stripped, both Would run lines"
}

test_3967_rendering() {
  run_node_tests TEST-3967
  log_pass "TEST-3967: the dry-run block, the sync header, changed files, pin lines, the newest conflict report, the evidence block and both Recommended forms match the bash reference bytes"
}

test_3968_doctor_postamble() {
  run_node_tests TEST-3968
  log_pass "TEST-3968: the doctor postamble prints the missing or crashed line, runs the helper on process.execPath, never changes the exit code and never runs in a dry-run or after a failed sync"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3960..3978, grows run by run)"
  check_deps
  setup_fixture
  test_3960_scratch_safety
  test_3961_module_shape
  test_3962_cli_and_base
  test_3963_canonical_guard
  test_3964_source_resolution
  test_3965_temp_lifecycle
  test_3966_runner_and_sync
  test_3967_rendering
  test_3968_doctor_postamble
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
