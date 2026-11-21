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

test_3989_corpus_bash() {
  need_tool TEST-3989 bash || return 0
  need_tool TEST-3989 git || return 0
  run_node_tests TEST-3989
  log_pass "TEST-3989: every bash-side corpus case K01 to K31 gives exit, stdout, stderr, snapshot and TMPDIR listing byte-equal between the frozen bash reference and the module after the registered rewrites, each rewrite changing a byte, and the asserted divergences hold"
}

test_3990_corpus_powershell() {
  need_tool TEST-3990 pwsh || return 0
  need_tool TEST-3990 git || return 0
  run_node_tests TEST-3990
  log_pass "TEST-3990: every PowerShell-side corpus case P01 to P20 gives exit and snapshot equal between the frozen PowerShell reference and the module, and the asserted divergences hold"
}

# --- run 5: the sh launcher and the bash-side re-homes (TEST-3991, TEST-3992) -----------------------------
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh"
REFUSAL_LINE="install-pre-commit-hook: refused - node not found in PATH or install-pre-commit-hook.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run."

# write_stub_module <dir>: an install-pre-commit-hook.mjs that prints its argv as JSON and exits 7.
write_stub_module() {
  printf '%s\n' 'console.log(JSON.stringify({ argv: process.argv.slice(2) }));' 'process.exit(7);' > "$1/install-pre-commit-hook.mjs"
}

# expect_pass_through <label> <shell> <launcher copy> <expected argv...>: the copy beside its stub passes the argv
# in order and exit 7 through.
expect_pass_through() {
  local label="$1" shell="$2" copy="$3" out rc=0 verdict
  shift 3
  out="$("$shell" "$copy" "$@" 2>&1)" || rc=$?
  [[ "$rc" == 7 ]] || log_fail "TEST-3991: $label: expected exit 7 through the launcher, got $rc: $out"
  verdict="$(node -e '
    const got = JSON.parse(process.argv[1]);
    const want = process.argv.slice(2);
    const same = got.argv.length === want.length && got.argv.every((a, i) => a === want[i]);
    process.stdout.write(same ? "same" : "differs: " + process.argv[1]);
  ' "$out" "$@")" || log_fail "TEST-3991: $label: the stub output is not JSON: $out"
  [[ "$verdict" == same ]] || log_fail "TEST-3991: $label: $verdict"
}

# expect_refusal <label> <shell> <copy> <path> <target dir>: runs the launcher in the target with the given PATH and
# requires exit 1, empty stdout, exactly the refusal line on stderr and an unchanged target.
expect_refusal() {
  local label="$1" shell="$2" copy="$3" use_path="$4" target="$5" rc=0 before after
  before="$(find "$target" | LC_ALL=C sort)"
  ( cd "$target" && PATH="$use_path" "$shell" "$copy" --force ) > "$target/../refusal.out" 2> "$target/../refusal.err" || rc=$?
  [[ "$rc" == 1 ]] || log_fail "TEST-3991: $label: expected exit 1, got $rc"
  [[ ! -s "$target/../refusal.out" ]] || log_fail "TEST-3991: $label: stdout must be empty"
  [[ "$(cat "$target/../refusal.err")" == "$REFUSAL_LINE" ]] || log_fail "TEST-3991: $label: stderr is not the refusal line: $(cat "$target/../refusal.err")"
  after="$(find "$target" | LC_ALL=C sort)"
  [[ "$before" == "$after" ]] || log_fail "TEST-3991: $label: the target changed"
}

test_3991_sh_launcher() {
  [[ -f "$SH_LAUNCHER" ]] || log_fail "TEST-3991: .aai/scripts/install-pre-commit-hook.sh does not exist"
  local lines mode token body
  lines="$(wc -l < "$SH_LAUNCHER" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || log_fail "TEST-3991: the launcher has $lines lines, at most 20 allowed"
  [[ "$(head -n 1 "$SH_LAUNCHER")" == "#!/bin/sh" ]] || log_fail "TEST-3991: the launcher does not start with #!/bin/sh"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$SH_LAUNCHER"; then log_fail "TEST-3991: the launcher holds a non-ASCII byte"; fi
  mode="$(git -C "$PROJECT_ROOT" ls-files -s .aai/scripts/install-pre-commit-hook.sh | cut -c1-6)"
  [[ "$mode" == 100755 && -x "$SH_LAUNCHER" ]] || log_fail "TEST-3991: the launcher is not mode 100755 (index: $mode)"
  body="$(/usr/bin/grep -v '^#' "$SH_LAUNCHER")"
  for token in 'git' 'rev-parse' 'ref_guard' 'AAI:' 'docs-audit' 'exit 2' '--force' '--print' '--hooks'; do
    [[ "$body" != *"$token"* ]] || log_fail "TEST-3991: the launcher holds the policy token: $token"
  done

  local work copy bin shell
  work="$(new_own_scratch launcher)"
  mkdir "$work/beside" "$work/alone" "$work/bin" "$work/target"
  cp "$SH_LAUNCHER" "$work/beside/launcher-copy.sh"
  cp "$SH_LAUNCHER" "$work/alone/launcher-copy.sh"
  write_stub_module "$work/beside"
  copy="$work/beside/launcher-copy.sh"
  for shell in bash sh dash; do
    need_tool TEST-3991 "$shell" || continue
    expect_pass_through "$shell with a spaced value" "$shell" "$copy" --hooks "index, ref-guard" --force --uninstall --print "a b" --decline-ref-guard --arm-ref-guard -h
    expect_pass_through "$shell with the bare flags" "$shell" "$copy" --print --hooks=index
  done
  # PATH holding only dirname: the module exists but node is not found
  bin="$work/bin"
  ln -s "$(command -v dirname)" "$bin/dirname"
  mkdir "$work/target/inner"
  for shell in "$(command -v bash)" "$(command -v sh)"; do
    expect_refusal "no node ($shell)" "$shell" "$copy" "$bin" "$work/target"
  done
  # node is on PATH but the module is missing: the launcher copied alone
  expect_refusal "module missing" "$(command -v sh)" "$work/alone/launcher-copy.sh" "$PATH" "$work/target"
  safe_rm_own "$work"
  log_pass "TEST-3991: the sh launcher is at most 20 ASCII lines, mode 100755, holds no policy token, passes every argument and the exit code through under bash, sh and dash, and refuses with the exact line, exit 1 and an unchanged target without node or without the module"
}

# run_suite_selector <suite file> <selector>: one re-homed or vendored selector must exit 0.
run_suite_selector() {
  local suite="$1" sel="$2" rc=0 out
  [[ -f "$PROJECT_ROOT/tests/skills/$suite" ]] || log_fail "TEST-3992: tests/skills/$suite does not exist"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/tests/skills/$suite" "$sel" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3992: $suite $sel exited $rc"; }
}

test_3992_rehomed_bash_side() {
  need_tool TEST-3992 git || return 0
  local sel pair rc out verdict id
  for pair in \
    "test-aai-git-ref-guard.sh test_314_print_flag" \
    "test-aai-hygiene-pack.sh test_618_ref_guard_grep_conformance" \
    "test-aai-docs-audit.sh test_spec0011_hook_parity_grep" \
    "test-aai-docs-audit.sh test_change0007_hook_body_lint" \
    "test-aai-git-ref-guard.sh test_310_doctor_category" \
    "test-aai-pre-commit-checks.sh test_3453_large_debug_list" \
    "test-aai-doctor.sh test_1344_cat17_seam1_installed_hook_passes" \
    "test-aai-git-hook-templates.sh test_3445_cdpath_relative_install" \
    "test-aai-tracked-ignored.sh test_1709_real_hook_refuses_commit" \
    "test-aai-hygiene-pack.sh test_800_installed_hook_reaches_guard"; do
    run_suite_selector "${pair%% *}" "${pair#* }"
  done
  rc=0
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3992: check-vendored-script-deps exited $rc"; }
  # the helper holds the two copy lines once each, outside its case blocks
  local helper="$PROJECT_ROOT/tests/skills/lib/vendor-hook-installer.sh" line n
  for line in '  cp "$src/.aai/scripts/install-pre-commit-hook.mjs" "$root/.aai/scripts/"' '  cp "$src/.aai/scripts/lib/guard-config.mjs" "$root/.aai/scripts/lib/"'; do
    n="$(/usr/bin/grep -cxF -- "$line" "$helper" || true)"
    [[ "$n" == 1 ]] || log_fail "TEST-3992: vendor-hook-installer.sh holds the line '$line' $n times, want once"
  done
  # PROFILES core lists the module
  verdict="$(node -e '
    const fs = require("fs");
    const t = fs.readFileSync(process.argv[1], "utf8").split("\n");
    const start = t.findIndex((l) => /^core:/.test(l));
    let found = false;
    for (let i = start + 1; i < t.length && !/^[A-Za-z]/.test(t[i]); i++) {
      if (t[i].trim() === "- .aai/scripts/install-pre-commit-hook.mjs") found = true;
    }
    process.stdout.write(found ? "found" : "missing");
  ' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")" || verdict="unreadable"
  [[ "$verdict" == found ]] || log_fail "TEST-3992: PROFILES core does not list .aai/scripts/install-pre-commit-hook.mjs ($verdict)"
  # the contract records of ref pre-commit-installer-on-node
  local json
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3992: spec-amend list failed"
  for id in "SPEC-0156-|TEST-314 re-homed" "SPEC-0184-|TEST-618 re-homed" "SPEC-0011-|TEST-013 re-homed" "SPEC-0013-|TEST-008 re-homed"; do
    verdict="$(node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const [spec, what] = process.argv[1].split("|");
      const hit = d.items.filter((i) => i.ref_id === "pre-commit-installer-on-node" && i.amendment_class === "contract" && i.spec.includes(spec) && i.what.startsWith(what));
      process.stdout.write(hit.length === 1 ? "found" : "count " + hit.length);
    ' "$id" <<<"$json")"
    [[ "$verdict" == found ]] || log_fail "TEST-3992: contract record of ref pre-commit-installer-on-node for $id: $verdict"
  done
  log_pass "TEST-3992: the re-homed and vendoring selectors of seven suites exit 0 against the launcher, check-vendored-script-deps exits 0, the helper copies module and guard-config once each, PROFILES core lists the module and the four contract records exist"
}

# --- run 6: the ps1 launcher, the PowerShell-side re-homes and the parity third twin (TEST-3993 to TEST-3995) ---------
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/install-pre-commit-hook.Tests.ps1"
PARITY_DRIVER="$PROJECT_ROOT/tests/skills/lib/install-parity.mjs"
PARITY_TEST="$PROJECT_ROOT/tests/skills/lib/install-parity.test.mjs"
BOOTSTRAP_TEST="$PROJECT_ROOT/tests/skills/lib/aai-bootstrap.test.mjs"

# ps1_problems <file>: prints one line per way the launcher text breaks D-LAUNCH.
ps1_problems() {
  local f="$1" lines body token
  lines="$(wc -l < "$f" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || echo "the launcher has $lines lines, at most 20 allowed"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$f"; then echo "the launcher holds a non-ASCII byte"; fi
  if /usr/bin/grep -qi '^[[:space:]]*param[[:space:]]*(' "$f"; then echo "the launcher holds a param block"; fi
  body="$(/usr/bin/grep -v '^#' "$f")"
  for token in 'rev-parse' 'ref_guard' 'AAI:' 'docs-audit' 'exit 2' '-Force' '-Print' '-Hooks' '-Uninstall' 'DeclineRefGuard' 'ArmRefGuard'; do
    [[ "$body" != *"$token"* ]] || echo "the launcher holds the policy token: $token"
  done
  if printf '%s\n' "$body" | /usr/bin/grep -qE '(^|[^A-Za-z-])git([^A-Za-z-]|$)'; then echo "the launcher names git"; fi
}

# run_pester <label> <work dir> [<full name filter>]: Invoke-Pester on the hook installer Pester file in the project root;
# prints "PESTER passed=N skipped=N failed=N containers=N" and fails the test when Pester did not run.
run_pester() {
  local label="$1" work="$2" filter="${3:-}" out
  ( cd "$PROJECT_ROOT" && AAI_PESTER_FILTER="$filter" env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command '
    Import-Module Pester -MinimumVersion 5.0
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = "tests/skills/install-pre-commit-hook.Tests.ps1"
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "None"
    if ($env:AAI_PESTER_FILTER) { $cfg.Filter.FullName = $env:AAI_PESTER_FILTER }
    $r = Invoke-Pester -Configuration $cfg
    Write-Output ("PESTER passed=" + $r.PassedCount + " skipped=" + $r.SkippedCount + " failed=" + $r.FailedCount + " containers=" + $r.FailedContainersCount)
  ' ) > "$work/pester.log" 2>&1 || { cat "$work/pester.log" >&2; log_fail "$label: Invoke-Pester did not run"; }
  out="$(tail -n 1 "$work/pester.log")"
  [[ "$out" =~ ^PESTER\ passed=([0-9]+)\ skipped=([0-9]+)\ failed=([0-9]+)\ containers=([0-9]+)$ ]] || { cat "$work/pester.log" >&2; log_fail "$label: unreadable Pester summary: $out"; }
  printf '%s\n' "$out"
}

# need_pester <TEST id>: 0 when pwsh has Pester 5 or later; fail on CI when it has not; named SKIP-CASE otherwise.
need_pester() {
  need_tool "$1" pwsh || return 1
  if env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -ge 5 }) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then return 0; fi
  [[ -z "${CI:-}" ]] || log_fail "$1: Pester 5 is required on CI but pwsh has none"
  echo "SKIP-CASE: $1 needs Pester 5, which pwsh here does not have"
  return 1
}

test_3993_ps1_launcher() {
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-3993: .aai/scripts/install-pre-commit-hook.ps1 does not exist"
  local problems work counts
  problems="$(ps1_problems "$PS1_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-3993: $problems"
  need_pester TEST-3993 || return 0
  work="$(new_own_scratch pester-launcher)"
  counts="$(run_pester TEST-3993 "$work" '*launcher (pre-commit-installer-on-node)*')"
  [[ "$counts" == "PESTER passed=5 skipped=0 failed=0 containers=0" ]] || { cat "$work/pester.log" >&2; log_fail "TEST-3993: Pester summary '$counts', expected 5 passed, 0 skipped, 0 failed, 0 failed containers"; }
  safe_rm_own "$work"
  log_pass "TEST-3993: the ps1 launcher is at most 20 ASCII lines with no param block and no policy token, and the five launcher cases pass under Invoke-Pester with 0 skips, 0 failures and 0 failed containers"
}

# amend_count <list json> <spec id fragment> <what prefix>: prints the number of contract records of ref pre-commit-installer-on-node.
# The list goes in on stdin: as one argument it outgrows the 128 KiB Linux limit on a single argv string.
amend_count() {
  node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const hit = d.items.filter((i) => i.ref_id === "pre-commit-installer-on-node" && i.amendment_class === "contract" && i.spec.includes(process.argv[1]) && i.what.startsWith(process.argv[2]));
    process.stdout.write(String(hit.length));
  ' "$2" "$3" <<<"$1"
}

# fn_body <file> <function name>: the source of one shell function (from its definition to the closing brace in column 0).
fn_body() {
  awk -v name="$2" '$0 ~ "^" name "\\(\\) \\{" { p = 1 } p { print } p && /^}$/ { exit }' "$1"
}

test_3994_rehomed_ps1_side() {
  need_tool TEST-3994 git || return 0
  local pair suite fn body rc out
  # no assertion in a re-homed function reads the .ps1's text
  for pair in \
    "test-aai-git-ref-guard.sh test_309_ps1_twin_static" "test-aai-git-ref-guard.sh test_608_ps1_hooks_static" \
    "test-aai-git-ref-guard.sh test_631_ps1_decline_arm_params_static" "test-aai-git-ref-guard.sh test_632_ps1_policy_reader_fails_closed_static" \
    "test-aai-git-ref-guard.sh test_633_ps1_foreign_refusal_shared_helper" "test-aai-git-ref-guard.sh test_637_ps1_plain_reinstall_honours_decline_static" \
    "test-aai-git-ref-guard.sh test_641_ps1_write_policy_corrects_stray_value" "test-aai-git-ref-guard.sh test_642_ps1_decline_orders_write_before_removal" \
    "test-aai-git-ref-guard.sh test_644_ps1_decline_seeds_or_discloses_new_config" "test-aai-git-ref-guard.sh test_646_ps1_hooks_contradicts_decline_arm" \
    "test-aai-git-ref-guard.sh test_647_arm_ref_guard_creates_missing_hooks_dir" \
    "test-aai-hygiene-pack.sh test_813_ps1_twin_parity" "test-aai-hygiene-pack.sh test_818_ps1_upgrade_is_byte_exact_and_order_checked"; do
    suite="${pair%% *}"
    fn="${pair#* }"
    body="$(fn_body "$PROJECT_ROOT/tests/skills/$suite" "$fn")"
    [[ -n "$body" ]] || log_fail "TEST-3994: $suite has no function $fn"
    if printf '%s\n' "$body" | /usr/bin/grep -E '(^|[^A-Za-z_])(grep|egrep|fgrep|awk|sed|cat|head|tail)[^|#]*INSTALLER_PS1' >/dev/null; then
      log_fail "TEST-3994: $suite $fn still reads the .ps1's text"
    fi
  done
  need_pester TEST-3994 || return 0
  for pair in \
    "test-aai-git-ref-guard.sh test_309_ps1_twin_static" "test-aai-git-ref-guard.sh test_608_ps1_hooks_static" \
    "test-aai-git-ref-guard.sh test_631_ps1_decline_arm_params_static" "test-aai-git-ref-guard.sh test_632_ps1_policy_reader_fails_closed_static" \
    "test-aai-git-ref-guard.sh test_633_ps1_foreign_refusal_shared_helper" "test-aai-git-ref-guard.sh test_637_ps1_plain_reinstall_honours_decline_static" \
    "test-aai-git-ref-guard.sh test_641_ps1_write_policy_corrects_stray_value" "test-aai-git-ref-guard.sh test_642_ps1_decline_orders_write_before_removal" \
    "test-aai-git-ref-guard.sh test_644_ps1_decline_seeds_or_discloses_new_config" "test-aai-git-ref-guard.sh test_646_ps1_hooks_contradicts_decline_arm" \
    "test-aai-git-ref-guard.sh test_647_arm_ref_guard_creates_missing_hooks_dir" \
    "test-aai-hygiene-pack.sh test_813_ps1_twin_parity" "test-aai-hygiene-pack.sh test_818_ps1_upgrade_is_byte_exact_and_order_checked"; do
    rc=0
    out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/tests/skills/${pair%% *}" "${pair#* }" 2>&1)" || rc=$?
    [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3994: ${pair%% *} ${pair#* } exited $rc"; }
    [[ "$out" != *"SKIP"* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3994: ${pair%% *} ${pair#* } skipped a part"; }
  done
  local work counts json id
  work="$(new_own_scratch pester-whole)"
  counts="$(run_pester TEST-3994 "$work")"
  [[ "$counts" =~ ^PESTER\ passed=([0-9]+)\ skipped=0\ failed=0\ containers=0$ && "${BASH_REMATCH[1]}" -ge 12 ]] || { cat "$work/pester.log" >&2; log_fail "TEST-3994: Pester summary '$counts', expected at least 12 passes with 0 skips, 0 failures and 0 failed containers"; }
  safe_rm_own "$work"
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3994: spec-amend list failed"
  for id in "SPEC-0184-|TEST-608 to TEST-647 re-homed" "SPEC-0156-|TEST-309 re-homed" "SPEC-0201-|TEST-813 and TEST-818 re-homed" "SPEC-0278-|install-pre-commit-hook.Tests.ps1 vendors the module"; do
    out="$(amend_count "$json" "${id%%|*}" "${id#*|}")"
    [[ "$out" == 1 ]] || log_fail "TEST-3994: contract records of ref pre-commit-installer-on-node for $id: $out, want 1"
  done
  log_pass "TEST-3994: the thirteen PowerShell-side re-homed selectors exit 0 with no assertion reading the .ps1 text, the whole Pester file passes with 0 skips, 0 failures and 0 failed containers, and the four contract records exist"
}

test_3995_parity_hooks() {
  need_pester TEST-3995 || return 0
  local work rc=0 verdict json args id
  work="$(new_own_scratch parity-hooks)"
  args=()
  for id in HK-01 HK-02 HK-03 HK-04 HK-05 HK-06 HK-07 HK-08 HK-09 HK-10; do args+=(--scenario "$id"); done
  env -u AAI_ROLE -u AAI_GIT_WRITE node "$PARITY_DRIVER" run --matrix full --twins sh,ps1,node "${args[@]}" --json "$work/hk.json" > "$work/hk.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/hk.out" >&2; log_fail "TEST-3995: the driver run over HK-01 to HK-10 exited $rc"; }
  verdict="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    if (r.verdict !== "PASS") bad.push("verdict " + r.verdict);
    const ids = ["HK-01", "HK-02", "HK-03", "HK-04", "HK-05", "HK-06", "HK-07", "HK-08", "HK-09", "HK-10"];
    for (const id of ids) {
      const s = r.scenarios.find((x) => x.id === id);
      if (!s) { bad.push(id + " missing"); continue; }
      const twins = [...new Set(s.steps.map((x) => x.twin))].sort().join(",");
      if (twins !== "node,ps1,sh") bad.push(id + " ran twins " + twins);
    }
    const cross = r.pairs.filter((p) => p.split(":")[0] !== p.split(":")[1]).sort().join(" ");
    if (cross !== "ps1:node sh:node sh:ps1") bad.push("pairs " + cross);
    if (r.uncovered.length) bad.push("uncovered " + JSON.stringify(r.uncovered));
    process.stdout.write(bad.length ? bad.join("; ") : "ok");
  ' "$work/hk.json")" || log_fail "TEST-3995: cannot read the driver report"
  [[ "$verdict" == ok ]] || { cat "$work/hk.out" >&2; log_fail "TEST-3995: $verdict"; }
  # the sh and ps1 argv name hkref, the node twin runs only update, bootstrap and hooks scenarios
  verdict="$(AAI_PARITY_DRIVER_PATH="$PARITY_DRIVER" node --input-type=module -e '
    const m = await import(process.env.AAI_PARITY_DRIVER_PATH);
    const bad = [];
    const ctx = { src: "/s", target: "/t", bash: "bash", ps: "pwsh", hkref: "/hk" };
    const hk = { op: "hooks", profile: null, flags: [] };
    const sh = m.TWINS.sh.argv(hk, ctx);
    if (sh.args[0] !== "/hk/.aai/scripts/install-pre-commit-hook.sh") bad.push("sh argv " + sh.args[0]);
    const ps = m.TWINS.ps1.argv(hk, ctx);
    if (!ps.args.includes("/hk/.aai/scripts/install-pre-commit-hook.ps1")) bad.push("ps1 argv " + ps.args.join(" "));
    const odd = m.SCENARIOS.filter((s) => m.twinsFor([m.TWINS.node], s).length > 0 && !["update", "bootstrap", "hooks"].includes(s.op)).map((s) => s.id);
    if (odd.length) bad.push("node runs " + odd.join(","));
    process.stdout.write(bad.length ? bad.join("; ") : "ok");
  ')"
  [[ "$verdict" == ok ]] || log_fail "TEST-3995: $verdict"
  run_node_tests TEST-3995 "$PARITY_TEST"
  run_node_tests TEST-3956 "$BOOTSTRAP_TEST"
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3995: spec-amend list failed"
  for id in "SPEC-0284-|D-SEAM hook twins run the frozen references" "SPEC-0306-|TEST-3956 node twin operations"; do
    verdict="$(amend_count "$json" "${id%%|*}" "${id#*|}")"
    [[ "$verdict" == 1 ]] || log_fail "TEST-3995: contract records of ref pre-commit-installer-on-node for $id: $verdict, want 1"
  done
  safe_rm_own "$work"
  log_pass "TEST-3995: the parity driver passes HK-01 to HK-10 with twins sh, ps1 and node on all three pairs, the sh and ps1 twins run the frozen references, the node twin runs only update, bootstrap and hooks scenarios, the unit tests and TEST-3956 hold, and the SPEC-0284 and SPEC-0306 records exist"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3980..3995, grows run by run)"
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
  test_3989_corpus_bash
  test_3990_corpus_powershell
  test_3991_sh_launcher
  test_3992_rehomed_bash_side
  test_3993_ps1_launcher
  test_3994_rehomed_ps1_side
  test_3995_parity_hooks
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
