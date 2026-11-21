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

test_3983_policy_writer() {
  run_node_tests TEST-3983
  log_pass "TEST-3983: writeRefGuardPolicy seeds, writes through a link, keeps mode, per-line endings and a BOM, collapses a doubled or value-less key with the removed line numbers, appends with the file terminator, writes nothing when unchanged, refuses a read-only target and a dangling link, leaves no temp and checks its read-back; the reader reads a BOM-prefixed declined and keeps every other verdict; aai-doctor CAT-17 reports DECLINED on it"
}

test_3984_policy_flows() {
  run_node_tests TEST-3984
  # a real process through the suite's own helper: a plain install on a scratch repository that declined the guard
  local work repo
  work="$(new_own_scratch policy)"
  repo="$work/repo"
  mkdir -p "$repo/docs/ai"
  ( cd "$repo" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig" git init -q ) || log_fail "TEST-3984: git init failed"
  printf 'ref_guard: declined\n' > "$repo/docs/ai/docs-audit.yaml"
  run_installer "$work" "$repo"
  [[ "$RUN_RC" == 0 ]] || { cat "$work/run.err" >&2; log_fail "TEST-3984: a plain install on a declined scratch repository exited $RUN_RC"; }
  grep -qF "Skipped AAI reference-transaction hook (AAI:REF-GUARD)" "$work/run.out" || log_fail "TEST-3984: the Skipped line is missing"
  [[ ! -e "$repo/.git/hooks/reference-transaction" ]] || log_fail "TEST-3984: the declined guard was installed"
  [[ -f "$repo/.git/hooks/pre-commit" && -f "$repo/.git/hooks/pre-push" ]] || log_fail "TEST-3984: the other two hooks were not installed"
  run_installer "$work" "$repo" --arm-ref-guard
  [[ "$RUN_RC" == 0 ]] || { cat "$work/run.err" >&2; log_fail "TEST-3984: --arm-ref-guard exited $RUN_RC"; }
  [[ "$(cat "$repo/docs/ai/docs-audit.yaml")" == "ref_guard: armed" ]] || log_fail "TEST-3984: arm did not record armed"
  [[ -x "$repo/.git/hooks/reference-transaction" ]] || log_fail "TEST-3984: the armed guard is not an executable hook"
  safe_rm_own "$work"
  log_pass "TEST-3984: plain skip exactly when declined, decline order, arm, the DR-18 uninstall disclosure, the doubled-key warning and repair, the DR-10 re-arm line, no ref_guard pattern in the module"
}

test_3985_templates() {
  run_node_tests TEST-3985
  # --print outside a repository through the suite's own helper
  local work
  work="$(new_own_scratch print)"
  run_installer "$work" "$work" --print guard-checks
  [[ "$RUN_RC" == 0 ]] || log_fail "TEST-3985: --print guard-checks outside a repository exited $RUN_RC"
  [[ "$(sed -n 1p "$work/run.out")" == "# AAI:GUARD-CHECKS BEGIN" ]] || log_fail "TEST-3985: the guard block does not start with its BEGIN line"
  cmp -s <(tr -d '\r' < "$PROJECT_ROOT/.aai/templates/git-hooks/pre-commit-guard-checks.sh") "$work/run.out" || log_fail "TEST-3985: --print guard-checks differs from the template"
  safe_rm_own "$work"
  log_pass "TEST-3985: templates read from the module's own location with every CR removed, each missing one named before any write, malformed index and guard-checks templates refused, --print outside a repository, composePreCommit with a final LF equal to the bash reference bytes"
}

# git_scratch_repo <work> <name>: a scratch repository under <work> with the isolated git environment; prints its path.
git_scratch_repo() {
  local repo="$1/$2"
  mkdir -p "$repo"
  ( cd "$repo" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$1/gitconfig" git init -q ) || log_fail "git init failed in $repo"
  printf '%s\n' "$repo"
}

test_3986_paths() {
  need_tool TEST-3986 git || return 0
  run_node_tests TEST-3986
  # a real process: core.hooksPath relative and not yet existing, from a subdirectory; then outside a repository
  local work repo
  work="$(new_own_scratch paths)"
  : > "$work/gitconfig"
  repo="$(git_scratch_repo "$work" repo)"
  ( cd "$repo" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig" git config core.hooksPath .custom-hooks ) || log_fail "TEST-3986: git config failed"
  mkdir -p "$repo/sub"
  run_installer "$work" "$repo/sub"
  [[ "$RUN_RC" == 0 ]] || { cat "$work/run.err" >&2; log_fail "TEST-3986: an install from a subdirectory exited $RUN_RC"; }
  [[ -f "$repo/.custom-hooks/pre-commit" && -f "$repo/.custom-hooks/reference-transaction" && -f "$repo/.custom-hooks/pre-push" ]] || log_fail "TEST-3986: the hooks are not where git resolves them"
  [[ ! -e "$repo/.git/hooks/pre-commit" && ! -e "$repo/sub/.custom-hooks" ]] || log_fail "TEST-3986: a hook was written to a guessed path"
  mkdir "$work/plain"
  run_installer "$work" "$work/plain"
  [[ "$RUN_RC" == 1 ]] || log_fail "TEST-3986: outside a repository exited $RUN_RC, want 1"
  [[ "$(cat "$work/run.err")" == "ERROR: not inside a git repository." ]] || log_fail "TEST-3986: the not-a-repository line differs: $(cat "$work/run.err")"
  safe_rm_own "$work"
  log_pass "TEST-3986: the slot paths equal git rev-parse --git-path for every hooksPath shape, from a subdirectory and in a linked worktree, the not-a-repository and git-missing lines, PWD message paths"
}

test_3987_attestation() {
  need_tool TEST-3987 git || return 0
  run_node_tests TEST-3987
  # a real process: a foreign pre-commit and a directory in the pre-push slot refuse the whole run and write nothing
  local work repo before after
  work="$(new_own_scratch refuse)"
  : > "$work/gitconfig"
  repo="$(git_scratch_repo "$work" repo)"
  mkdir -p "$repo/.git/hooks/pre-push"
  printf '#!/bin/sh\necho mine\n' > "$repo/.git/hooks/pre-commit"
  before="$(find "$repo" -print0 | LC_ALL=C sort -z | xargs -0 ls -ld | cksum)"
  run_installer "$work" "$repo"
  [[ "$RUN_RC" == 1 ]] || log_fail "TEST-3987: a refused run exited $RUN_RC, want 1"
  grep -qF "ERROR: refusing the whole run" "$work/run.err" || log_fail "TEST-3987: the whole-run line is missing"
  [[ ! -s "$work/run.out" ]] || log_fail "TEST-3987: a refusal wrote to stdout"
  [[ ! -e "$repo/.git/hooks/reference-transaction" && ! -e "$repo/docs" ]] || log_fail "TEST-3987: a refused run wrote a hook or a policy"
  after="$(find "$repo" -print0 | LC_ALL=C sort -z | xargs -0 ls -ld | cksum)"
  [[ "$before" == "$after" ]] || log_fail "TEST-3987: a refused run changed the tree"
  safe_rm_own "$work"
  log_pass "TEST-3987: every D-SLOT state, the byte marker rule, the declined slot left alone, each refusal kind in each slot with a byte-identical tree, refusals in slot order"
}

test_3988_writes() {
  need_tool TEST-3988 git || return 0
  run_node_tests TEST-3988
  # a real process under umask 077: new hooks are 0777 minus umask
  local work repo mode old_umask
  work="$(new_own_scratch writes)"
  : > "$work/gitconfig"
  repo="$(git_scratch_repo "$work" repo)"
  old_umask="$(umask)"
  umask 077
  run_installer "$work" "$repo"
  umask "$old_umask"
  [[ "$RUN_RC" == 0 ]] || { cat "$work/run.err" >&2; log_fail "TEST-3988: an install under umask 077 exited $RUN_RC"; }
  mode="$(node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$repo/.git/hooks/pre-commit")"
  [[ "$mode" == 700 ]] || log_fail "TEST-3988: pre-commit mode is $mode under umask 077, want 700"
  safe_rm_own "$work"
  log_pass "TEST-3988: temp and rename with the landing check, the upgrade by insertion and interior refresh against the bash reference, the marked-differs NOTE, modes under two umasks, the post-run attestation and the win32 skip"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3980..3997, grows run by run)"
  check_deps
  setup_fixture
  test_3980_scratch_safety
  test_3981_module_shape
  test_3982_cli_and_mode
  test_3983_policy_writer
  test_3984_policy_flows
  test_3985_templates
  test_3986_paths
  test_3987_attestation
  test_3988_writes
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
