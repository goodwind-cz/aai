#!/usr/bin/env bash
#
# Test: aai-hook-installer-node
# (docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md, TEST-3980..3999; this file grows run by run
# (TEST-3998 and TEST-3999 live in test-aai-hook-installer-docs.sh))
#
# The git hook installer is one Node module (.aai/scripts/install-pre-commit-hook.mjs) behind thin sh/ps1
# launchers, compared against frozen copies of both old twins (tests/fixtures/hook-installer-reference/).
# Every case works in scratch directories this run created (own prefix, ownership marker); nothing here
# starts a container tool, kills by pattern, installs a hook into this checkout or any real repository, or
# removes a path it did not provably create (D-SAFETY). Every installer run sets GIT_CONFIG_NOSYSTEM=1 and an
# empty GIT_CONFIG_GLOBAL and asserts the hooks path under the run's own scratch root.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-hook-installer-node.sh                       # run all
#   bash tests/skills/test-aai-hook-installer-node.sh test_3980_scratch_safety
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-hook-installer-node"
TEST_DIR=""
OWN_PREFIX="aai-hook-installer-node."
OWN_MARKER=".aai-hk-owned"

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
MJS="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/install-pre-commit-hook.test.mjs"
REF_HELPER="$PROJECT_ROOT/tests/skills/lib/hook-installer-reference.mjs"
REFERENCE_SH="$PROJECT_ROOT/tests/fixtures/hook-installer-reference/install-pre-commit-hook.sh"
REFERENCE_PS1="$PROJECT_ROOT/tests/fixtures/hook-installer-reference/install-pre-commit-hook.ps1"
SPEC_ID="pre-commit-installer-on-node"

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
  local id="$1" file="${2:-$NODE_TEST}" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/install-pre-commit-hook.mjs does not exist"
  [[ -f "$REF_HELPER" ]] || log_fail "$id: tests/skills/lib/hook-installer-reference.mjs does not exist"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" ]] || log_fail "$id: a frozen reference copy under tests/fixtures/hook-installer-reference does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/install-pre-commit-hook.test.mjs does not exist"
  [[ -f "$file" ]] || log_fail "$id: ${file##*/} does not exist"
  out="$(env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern "$id" "$file" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  # the tap reporter is forced (Node 24 defaults to spec off a TTY); node 22 reports an unmatched pattern as one
  # passing file, so a passing case named with the id must be seen.
  local named="ok [0-9]+ - $id "
  [[ "$out" =~ pass\ [1-9] && "$out" =~ $named ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported no passing test named $id for the pattern"; }
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
    log_fail "TEST-3980: safe_rm_own accepted $label"
  fi
}


# run_installer <work> <cwd> <args...>: the one way this suite starts the installer module. It sets no system git
# config and an empty global one, and refuses a cwd outside the scratch root <work> or a hooks path that git
# resolves outside it. The streams land in $work/run.out and $work/run.err, the exit code in RUN_RC.
RUN_RC=0
run_installer() {
  local work="$1" cwd="$2" resolved
  shift 2
  local -x GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
  : > "$work/gitconfig"
  case "$work" in */"$OWN_PREFIX"*) ;; *) log_fail "run_installer: scratch root without the own prefix: $work" ;; esac
  [[ -f "$work/$OWN_MARKER" ]] || log_fail "run_installer: scratch root without the ownership marker: $work"
  case "$cwd" in "$work"|"$work"/*) ;; *) log_fail "run_installer: cwd outside the scratch root: $cwd" ;; esac
  resolved="$(git -C "$cwd" rev-parse --git-path hooks/pre-commit 2>/dev/null)" || resolved="$cwd/none"
  case "$resolved" in /*) ;; *) resolved="$cwd/$resolved" ;; esac
  case "$resolved" in "$work"/*) ;; *) log_fail "run_installer: the hooks path $resolved lies outside $work" ;; esac
  RUN_RC=0
  ( cd "$cwd" && node "$MJS" "$@" ) > "$work/run.out" 2> "$work/run.err" || RUN_RC=$?
}

test_3980_scratch_safety() {
  run_node_tests TEST-3980
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
  [[ -d "$foreign" && -d "$unmarked" && -d "$marked" ]] || log_fail "TEST-3980: a refused path was removed"
  # a marked directory with the prefix is removed, and only it
  safe_rm_own "$marked"
  [[ ! -e "$marked" && -d "$foreign" && -d "$unmarked" ]] || log_fail "TEST-3980: safe_rm_own removed the wrong set"
  # a symbolic link with the prefix is refused and its target survives
  ln -s "$unmarked" "$work/${OWN_PREFIX}link"
  expect_refused "a symbolic link" "$work/${OWN_PREFIX}link"
  [[ -d "$unmarked" ]] || log_fail "TEST-3980: the link target was removed"
  safe_rm_own "$work"
  [[ ! -e "$work" ]] || log_fail "TEST-3980: the own scratch root was not removed"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" && -f "$REF_HELPER" ]] || log_fail "TEST-3980: a reference copy or its helper is missing"
  log_pass "TEST-3980: scratch removal refuses each unsafe path, both reference copies are pinned and materialize with the templates, no test file calls a container tool or a kill by pattern, every installer invocation isolates git config and asserts the hooks path under the scratch root"
}

test_3981_module_shape() {
  run_node_tests TEST-3981
  log_pass "TEST-3981: the module imports only node: specifiers and guard-config, exports the D-MODULE names, holds each anchor and the arm rationale once, calls spawnSync once, writes only through descriptors 1 and 2, holds no template line and is ASCII"
}

test_3982_cli_and_mode() {
  run_node_tests TEST-3982
  # a real process through the suite's own helper: help on stdout, exit 0, nothing created in the scratch cwd
  local work
  work="$(new_own_scratch cli)"
  run_installer "$work" "$work" -Force --help
  [[ "$RUN_RC" == 0 ]] || log_fail "TEST-3982: --help exited $RUN_RC"
  [[ ! -s "$work/run.err" ]] || log_fail "TEST-3982: --help wrote to stderr"
  [[ "$(sed -n 1p "$work/run.out")" == "Install the AAI git hook SET into the EFFECTIVE hooks directory "* ]] || log_fail "TEST-3982: the help does not start with the reference block"
  run_installer "$work" "$work" --arm-ref-guard --decline-ref-guard
  [[ "$RUN_RC" == 2 ]] || log_fail "TEST-3982: two mode flags exited $RUN_RC, want 2"
  [[ "$(cat "$work/run.err")" == "ERROR: --decline-ref-guard and --arm-ref-guard are contradictory." ]] || log_fail "TEST-3982: the contradiction line differs: $(cat "$work/run.err")"
  [[ ! -s "$work/run.out" ]] || log_fail "TEST-3982: a usage error wrote to stdout"
  safe_rm_own "$work"
  log_pass "TEST-3982: every accepted form, the last wins rule, help per DR-1, DR-2, DR-3, DR-7, the mode flag pairs per DR-4, DR-5 and DR-6 each exit 2 with one line and no child, resolveBase per DR-20"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3980..3997, grows run by run)"
  check_deps
  setup_fixture
  test_3980_scratch_safety
  test_3981_module_shape
  test_3982_cli_and_mode
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
