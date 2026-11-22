#!/usr/bin/env bash
#
# Test: aai-sync-node
# (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, TEST-4000..4019; this file holds TEST-4000..4019 as the runs add
# them (TEST-4020 to TEST-4022 live in test-aai-sync-docs.sh); run 1 holds TEST-4000..4003, run 2 TEST-4004..4006, run 3 TEST-4007..4009,
# run 4 TEST-4010..4012, run 5 TEST-4013..4014, run 6 TEST-4015..4017, run 7 TEST-4018..4019)
#
# The layer sync is one Node module (.aai/scripts/aai-sync.mjs) behind thin sh/ps1 launchers, compared against
# frozen copies of both old twins (tests/fixtures/sync-reference/). Every case works in scratch directories this
# run created (own prefix, ownership marker); nothing here starts a container tool, kills by pattern, syncs into
# this checkout or any real repository, or removes a path it did not provably create (D-SAFETY). Every sync run
# removes every GIT_ variable, sets the system git config off and the global one to an empty file, and asserts the
# target under the run's own scratch root.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-sync-node.sh                       # run all
#   bash tests/skills/test-aai-sync-node.sh test_4000_scratch_safety
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

# No GIT_ variable of the caller reaches a child of this suite: GIT_CONFIG_COUNT/KEY_n/VALUE_n, GIT_CONFIG_PARAMETERS,
# GIT_DIR, GIT_COMMON_DIR ... can each redirect the repository or its configuration. The suite sets the two it
# needs itself, per run.
while IFS= read -r _gv; do unset "$_gv"; done < <(compgen -e | /usr/bin/grep '^GIT_' || true)
unset _gv

TEST_NAME="aai-sync-node"
TEST_DIR=""
OWN_PREFIX="aai-sync-node."
OWN_MARKER=".aai-sn-owned"

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
MJS="$PROJECT_ROOT/.aai/scripts/aai-sync.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/aai-sync.test.mjs"
BASE_TEST="$PROJECT_ROOT/tests/skills/lib/resolve-base.test.mjs"
REF_HELPER="$PROJECT_ROOT/tests/skills/lib/sync-reference.mjs"
REFERENCE_SH="$PROJECT_ROOT/tests/fixtures/sync-reference/aai-sync.sh"
REFERENCE_PS1="$PROJECT_ROOT/tests/fixtures/sync-reference/aai-sync.ps1"
REFERENCE_LIB="$PROJECT_ROOT/tests/fixtures/sync-reference/gitignore-block.sh"
SUITE_FILE="$SCRIPT_DIR/test-aai-sync-node.sh"
SPEC_ID="sync-on-node"

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
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/aai-sync.mjs does not exist"
  [[ -f "$REF_HELPER" ]] || log_fail "$id: tests/skills/lib/sync-reference.mjs does not exist"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" && -f "$REFERENCE_LIB" ]] || log_fail "$id: a frozen reference copy under tests/fixtures/sync-reference does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/aai-sync.test.mjs does not exist"
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
    log_fail "TEST-4000: safe_rm_own accepted $label"
  fi
}

# scratch_env_run <work> <cwd> <cmd...>: runs a command in the isolated git environment: every GIT_ variable removed, the
# system git config off and the global one an empty file under the own scratch root <work>; refuses a root without the
# own prefix or marker and a cwd outside it.
scratch_env_run() {
  local work="$1" cwd="$2" gv
  shift 2
  case "$work" in */"$OWN_PREFIX"*) ;; *) log_fail "scratch_env_run: scratch root without the own prefix: $work" ;; esac
  [[ -f "$work/$OWN_MARKER" ]] || log_fail "scratch_env_run: scratch root without the ownership marker: $work"
  case "$cwd" in "$work"|"$work"/*) ;; *) log_fail "scratch_env_run: cwd outside the scratch root: $cwd" ;; esac
  : > "$work/gitconfig"
  (
    for gv in $(compgen -e | /usr/bin/grep '^GIT_' || true); do unset "$gv"; done
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
    cd "$cwd" && "$@"
  )
}

# run_sync_scratch <work> <cwd> <target> [args...]: the one way this suite starts the sync module (the module of this
# checkout, or the scratch copy named by SYNC_SCRIPT). The target is the first argument of the run, then the arguments
# follow. It refuses a script that is neither the module nor under the root, a root without the own prefix or marker, a cwd outside
# the root, a target that is not under the root's real path or that lies under this checkout. The streams land in
# $work/run.out and $work/run.err, the exit code in RUN_RC.
RUN_RC=0
run_sync_scratch() {
  local work="$1" cwd="$2" target="$3" script="${SYNC_SCRIPT:-$MJS}" real_work real_target
  shift 3
  local -x GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
  case "$work" in */"$OWN_PREFIX"*) ;; *) log_fail "run_sync_scratch: scratch root without the own prefix: $work" ;; esac
  [[ -f "$work/$OWN_MARKER" ]] || log_fail "run_sync_scratch: scratch root without the ownership marker: $work"
  case "$script" in "$MJS"|"$work"/*) ;; *) log_fail "run_sync_scratch: the script is neither the module nor under the scratch root: $script" ;; esac
  [[ -n "$target" && -d "$target" ]] || log_fail "run_sync_scratch: the target is not a directory: $target"
  real_work="$(phys_path "$work")"
  real_target="$(phys_path "$target")"
  case "$real_target" in "$PROJECT_ROOT"|"$PROJECT_ROOT"/*) log_fail "run_sync_scratch: the target $target lies under this checkout" ;; esac
  case "$real_target" in "$real_work"/*) ;; *) log_fail "run_sync_scratch: the target $target lies outside the scratch root $work" ;; esac
  case "$cwd" in "$work"|"$work"/*) ;; *) log_fail "run_sync_scratch: cwd outside the scratch root: $cwd" ;; esac
  RUN_RC=0
  scratch_env_run "$work" "$cwd" node "$script" "$target" "$@" > "$work/run.out" 2> "$work/run.err" || RUN_RC=$?
}

test_4000_scratch_safety() {
  run_node_tests TEST-4000
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
  [[ -d "$foreign" && -d "$unmarked" && -d "$marked" ]] || log_fail "TEST-4000: a refused path was removed"
  # a marked directory with the prefix is removed, and only it
  safe_rm_own "$marked"
  [[ ! -e "$marked" && -d "$foreign" && -d "$unmarked" ]] || log_fail "TEST-4000: safe_rm_own removed the wrong set"
  # a symbolic link with the prefix is refused and its target survives
  ln -s "$unmarked" "$work/${OWN_PREFIX}link"
  expect_refused "a symbolic link" "$work/${OWN_PREFIX}link"
  [[ -d "$unmarked" ]] || log_fail "TEST-4000: the link target was removed"
  rm "$work/${OWN_PREFIX}link"
  # the isolated environment: every caller GIT_ variable is gone, the two the run needs are set
  local envout
  envout="$( export GIT_DIR=/nonexistent/git GIT_COMMON_DIR=/nonexistent/common GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/nonexistent GIT_CONFIG_PARAMETERS="'core.hooksPath=/nonexistent'" GIT_WORK_TREE=/nonexistent; scratch_env_run "$work" "$work" env )" || log_fail "TEST-4000: scratch_env_run failed"
  [[ "$(printf '%s\n' "$envout" | /usr/bin/grep '^GIT_' | LC_ALL=C sort | tr '\n' ' ')" == "GIT_CONFIG_GLOBAL=$work/gitconfig GIT_CONFIG_NOSYSTEM=1 " ]] || log_fail "TEST-4000: the isolated environment holds other GIT_ variables: $(printf '%s\n' "$envout" | /usr/bin/grep '^GIT_')"
  [[ -f "$work/gitconfig" && ! -s "$work/gitconfig" ]] || log_fail "TEST-4000: GIT_CONFIG_GLOBAL is not an empty file"
  # run_sync_scratch refuses a target under this checkout, outside the root, a link to either, and a missing one
  local victim="$work/${OWN_PREFIX}victim-root" link
  mkdir -p "$victim"
  link="$work/link-to-checkout"
  ln -s "$PROJECT_ROOT" "$link"
  if ( run_sync_scratch "$work" "$work" "$PROJECT_ROOT" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted the checkout as a target"; fi
  if ( run_sync_scratch "$work" "$work" "$link" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted a link to the checkout as a target"; fi
  if ( run_sync_scratch "$work" "$work" "$work" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted the scratch root itself as a target"; fi
  if ( run_sync_scratch "$work" "$work" "$work/missing-dir" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted a missing target"; fi
  if ( run_sync_scratch "$work" "$PROJECT_ROOT" "$victim" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted a cwd outside the root"; fi
  if ( run_sync_scratch "${TMPDIR:-/tmp}" "${TMPDIR:-/tmp}" "$victim" -h ) >/dev/null 2>&1; then log_fail "TEST-4000: run_sync_scratch accepted a root without the own prefix"; fi
  # a target under the root is accepted: help exits 0
  run_sync_scratch "$work" "$work" "$victim" -h
  [[ "$RUN_RC" == 0 ]] || log_fail "TEST-4000: help through run_sync_scratch exited $RUN_RC"
  rm "$link"
  # a forced failing copy of the suite leaves no own scratch root behind
  local forced forced_suite rc out left
  forced="$(new_own_scratch forced)"
  mkdir -p "$forced/tests/skills/lib" "$forced/tmp"
  cp "$SCRIPT_DIR/lib/pipe-safe.sh" "$forced/tests/skills/lib/pipe-safe.sh"
  forced_suite="$forced/tests/skills/${SUITE_FILE##*/}"
  sed 's/^  setup_fixture$/  setup_fixture; log_fail "forced failure"/' "$SUITE_FILE" > "$forced_suite"
  /usr/bin/grep -q 'forced failure' "$forced_suite" || log_fail "TEST-4000: the forced failure was not injected into the copy"
  rc=0
  out="$(env -u AAI_ROLE TMPDIR="$forced/tmp" bash "$forced_suite" 2>&1)" || rc=$?
  [[ "$rc" != 0 && "$out" == *"forced failure"* ]] || log_fail "TEST-4000: the forced failing copy did not fail as injected (rc $rc): $out"
  left="$(find "$forced/tmp" -maxdepth 1 -name "${OWN_PREFIX}*")"
  [[ -z "$left" ]] || log_fail "TEST-4000: the failing suite left its scratch root behind: $left"
  safe_rm_own "$forced" "$work"
  [[ ! -e "$work" && ! -e "$forced" ]] || log_fail "TEST-4000: an own scratch root was not removed"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" && -f "$REFERENCE_LIB" && -f "$REF_HELPER" ]] || log_fail "TEST-4000: a reference copy or its helper is missing"
  log_pass "TEST-4000: scratch removal refuses each unsafe path, the three reference copies are pinned and materialize, no test file calls a container tool or a kill by pattern, every sync invocation isolates the git environment and asserts the target under the scratch root, a forced failing copy of the suite leaves no scratch root"
}

test_4001_module_shape() {
  run_node_tests TEST-4001
  log_pass "TEST-4001: the module imports only node: specifiers and the three libraries, exports the D-MODULE names, holds each anchor once, calls spawnSync once, writes only through descriptors 1 and 2 and is ASCII; importing it creates and prints nothing"
}

test_4002_cli() {
  run_node_tests TEST-4002
  # a real process through the suite's own helper: help on stdout, exit 0, then a usage error, nothing created in the target
  local work target
  work="$(new_own_scratch cli)"
  target="$work/target"
  mkdir "$target"
  run_sync_scratch "$work" "$work" "$target" --help
  [[ "$RUN_RC" == 0 ]] || log_fail "TEST-4002: --help exited $RUN_RC"
  [[ ! -s "$work/run.err" ]] || log_fail "TEST-4002: --help wrote to stderr"
  [[ "$(sed -n 1p "$work/run.out")" == "Push AAI layer FROM this repository INTO a target project." ]] || log_fail "TEST-4002: the help does not start with the reference block"
  run_sync_scratch "$work" "$work" "$target" --profile
  [[ "$RUN_RC" == 2 ]] || log_fail "TEST-4002: a bare --profile exited $RUN_RC, want 2"
  [[ "$(sed -n 1p "$work/run.err")" == "ERROR: --profile needs a value (core|extended)" ]] || log_fail "TEST-4002: the bare --profile line differs: $(cat "$work/run.err")"
  [[ "$(sed -n 2p "$work/run.err")" == "Usage: "* ]] || log_fail "TEST-4002: the usage line differs: $(cat "$work/run.err")"
  [[ ! -s "$work/run.out" ]] || log_fail "TEST-4002: a usage error wrote to stdout"
  run_sync_scratch "$work" "$work" "$target" --bogus
  [[ "$RUN_RC" == 2 && "$(sed -n 1p "$work/run.err")" == "ERROR: unexpected argument: --bogus" ]] || log_fail "TEST-4002: an unknown argument exited $RUN_RC: $(cat "$work/run.err")"
  [[ -z "$(ls -A "$target")" ]] || log_fail "TEST-4002: a usage error changed the target"
  safe_rm_own "$work"
  log_pass "TEST-4002: every accepted form in any order and case, help per DR-1, each DR-2 usage case exits 2 with its stderr line and the usage line and no child, a missing target directory exits 1 with the bash line, -T and -Verbose refused"
}

test_4003_root_refusals() {
  run_node_tests TEST-4003
  # a real process: a target equal to its own source is refused before any write, the snapshot is unchanged
  local work src before after
  work="$(new_own_scratch roots)"
  src="$work/S"
  mkdir -p "$src/.aai/scripts/lib" "$src/.aai/system"
  cp "$MJS" "$src/.aai/scripts/aai-sync.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/resolve-base.mjs" "$PROJECT_ROOT/.aai/scripts/lib/gitignore-block.mjs" "$PROJECT_ROOT/.aai/scripts/lib/merge-hooks-json.mjs" "$src/.aai/scripts/lib/"
  before="$(find "$src" -print0 | LC_ALL=C sort -z | xargs -0 ls -ld | cksum)"
  SYNC_SCRIPT="$src/.aai/scripts/aai-sync.mjs" run_sync_scratch "$work" "$work" "$src"
  [[ "$RUN_RC" == 1 ]] || log_fail "TEST-4003: a self sync exited $RUN_RC, want 1"
  [[ "$(cat "$work/run.err")" == "ERROR: target $src is the source $src or lies inside it; nothing was written." ]] || log_fail "TEST-4003: the self-sync line differs: $(cat "$work/run.err")"
  [[ ! -s "$work/run.out" ]] || log_fail "TEST-4003: a self sync wrote to stdout"
  after="$(find "$src" -print0 | LC_ALL=C sort -z | xargs -0 ls -ld | cksum)"
  [[ "$before" == "$after" ]] || log_fail "TEST-4003: a refused self sync changed the tree"
  safe_rm_own "$work"
  log_pass "TEST-4003: the target equal to the source, inside it and at a link to it, a file system root, a source without .aai, a missing manifest and an empty core list each exit 1 with the D-ROOTS line and leave target and source byte-identical; a source inside the target is allowed"
}

# --- run 2: the shared base lib, the .gitignore reconcile and the dropped legacy moves (TEST-4004 to TEST-4006) ------

test_4004_shared_base() {
  [[ -f "$BASE_TEST" ]] || log_fail "TEST-4004: tests/skills/lib/resolve-base.test.mjs does not exist"
  [[ -f "$PROJECT_ROOT/.aai/scripts/lib/resolve-base.mjs" ]] || log_fail "TEST-4004: .aai/scripts/lib/resolve-base.mjs does not exist"
  run_node_tests TEST-4004 "$BASE_TEST"
  # the existing tests of the three switched modules, by their ids (node:test files)
  run_node_tests TEST-3962 "$PROJECT_ROOT/tests/skills/lib/aai-update.test.mjs"
  run_node_tests TEST-3961 "$PROJECT_ROOT/tests/skills/lib/aai-update.test.mjs"
  run_node_tests TEST-3941 "$PROJECT_ROOT/tests/skills/lib/aai-bootstrap.test.mjs"
  run_node_tests TEST-3942 "$PROJECT_ROOT/tests/skills/lib/aai-bootstrap.test.mjs"
  run_node_tests TEST-3981 "$PROJECT_ROOT/tests/skills/lib/install-pre-commit-hook.test.mjs"
  # every helper that vendors a switched module vendors the lib: the guard of the vendoring class exits 0
  local out rc=0
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4004: check-vendored-script-deps exited $rc"; }
  # the hook installer helper copies the lib once, outside its case blocks
  local helper="$PROJECT_ROOT/tests/skills/lib/vendor-hook-installer.sh" n
  n="$(/usr/bin/grep -cxF -- '  cp "$src/.aai/scripts/lib/resolve-base.mjs" "$root/.aai/scripts/lib/"' "$helper" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-4004: vendor-hook-installer.sh copies resolve-base.mjs $n times, want once"
  # PROFILES core lists the lib (the companion obligation of a new .aai file)
  local verdict
  verdict="$(node -e '
    const t = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const start = t.findIndex((l) => /^core:/.test(l));
    let found = false;
    for (let i = start + 1; i < t.length && !/^[A-Za-z]/.test(t[i]); i++) if (t[i].trim() === "- .aai/scripts/lib/resolve-base.mjs") found = true;
    process.stdout.write(found ? "found" : "missing");
  ' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")" || verdict="unreadable"
  [[ "$verdict" == found ]] || log_fail "TEST-4004: PROFILES core does not list .aai/scripts/lib/resolve-base.mjs ($verdict)"
  # the contract records of this ride's run 2 (D-REHOME): one per named change, unsigned
  local json
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-4004: spec-amend list failed"
  local id
  for id in "SPEC-0307-|TEST-3961 allows the shared base lib" "SPEC-0306-|TEST-3941 allows the shared base lib" \
    "SPEC-0308-|TEST-3981 allows the shared base lib" "SPEC-0308-|vendor-hook-installer.sh vendors the shared base lib" \
    "SPEC-0306-|TEST-3941 drops the samePlace anchor line" "SPEC-0157-|TEST-016 names the Node gitignore lib"; do
    verdict="$(node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const [spec, what] = process.argv[1].split("|");
      const hit = d.items.filter((i) => i.ref_id === "sync-on-node" && i.amendment_class === "contract" && i.spec.includes(spec) && i.what.startsWith(what));
      process.stdout.write(hit.length === 1 ? "found" : "count " + hit.length);
    ' "$id" <<<"$json")"
    [[ "$verdict" == found ]] || log_fail "TEST-4004: contract record of ref $SPEC_ID for $id: $verdict"
  done
  log_pass "TEST-4004: the lib answers every PWD shape (a dot-dot after a link included) and the four users agree with it and hold no check of their own; the existing tests TEST-3961, TEST-3962, TEST-3941, TEST-3942 and TEST-3981 pass, check-vendored-script-deps exits 0, the hook helper vendors the lib, PROFILES core lists it and the six run 2 records exist"
}

test_4005_gitignore() {
  run_node_tests TEST-4005
  log_pass "TEST-4005: the reconcile writes the bytes of the frozen bash reference for the K09 inputs, a second run changes nothing, a 200 KB file with the managed lines at the top is not re-appended, the DR-14 pointer and the missing-list note print, the lib holds no child process"
}

test_4006_legacy_dropped() {
  run_node_tests TEST-4006
  log_pass "TEST-4006: a legacy-layout target keeps every legacy path byte-identical through the module and the reconcile, no MIGRATE or legacy line is printed, and the module source holds none of the dropped paths"
}

# --- run 3: the profile, the core copy and prune, the extended copy and the path guard, the surfaces (TEST-4007 to TEST-4009) ---

test_4007_core_prune() {
  run_node_tests TEST-4007
  log_pass "TEST-4007: the DR-9 and DR-10 readings, the K03 to K05 flows equal the frozen bash twin (copy, WARN, prune, preserve, cache kept, emptied directories removed, deletions recorded), two core syncs with 20,000 extra list entries leave every core-listed file present, a prune never follows a link, an empty core set is a hard failure and every changed path lies under the target"
}

test_4008_copy_and_guard() {
  run_node_tests TEST-4008
  log_pass "TEST-4008: copyReplace keeps modes, timestamps and links and copies a dangling link as a link, the K08 extended flow equals the bash twin, a managed link leaving the target refuses the whole run before any write (DR-7), an outside path and a swapped target exit 1 with the DR-8 line, an EEXIST temp is left in place"
}

test_4009_surfaces() {
  run_node_tests TEST-4009
  log_pass "TEST-4009: the skill trees, indexes, knowledge files, seeds and root shims equal the bash twin for a differing and a fresh target (lines, tree, recorded conflicts), isRetiredSkillWrapper accepts only the shipped shape and keeps every near miss, the sentinel is case-sensitive"
}

# --- run 4: the Copilot shim and the hooks merge, the advisory and the pin, the installer suites' git environment (TEST-4010 to TEST-4012) ---

test_4010_copilot_and_hooks() {
  run_node_tests TEST-4010
  log_pass "TEST-4010: the K15 Copilot shim flows and the K16 hooks flows equal the frozen bash twin (lines, tree, recorded conflicts), the merged shim and override file are the bash bytes, copilotShimIsShipped and extractCopilotOverrides answer for listed, unlisted, empty and CRLF texts, the in-process merge lines equal the library CLI output, a malformed registration or a link is left untouched, session-start.sh is executable"
}

test_4011_report_and_pin() {
  run_node_tests TEST-4011
  log_pass "TEST-4011: renderAdvisory and renderPin write the bash text from one clock read (LF, one space after Template version, tag fallback, UNKNOWN), a run with GIT_DIR exported stamps the commit of the source, a quiet run writes no advisory, the closing lines end the run, native paths under platform win32"
}

# --- run 5: the differential corpora (TEST-4013, TEST-4014) ---

test_4013_corpus_bash() {
  need_tool TEST-4013 bash || return 0
  need_tool TEST-4013 git || return 0
  run_node_tests TEST-4013
  log_pass "TEST-4013: the bash-side corpus (K01 to K32, KR1 and KR2) gives exit code, stdout, stderr, the target snapshot, the source snapshot and the TMPDIR listing equal to the frozen bash twin after the registered normalization and rewrites (DR-4, DR-14, DR-21, DR-26, DR-28), a registered rewrite that changes nothing fails its case, and the asserted divergences (DR-1, DR-2, DR-5, DR-7, DR-13, DR-29, DR-30) hold"
}

test_4014_corpus_powershell() {
  need_tool TEST-4014 pwsh || return 0
  need_tool TEST-4014 git || return 0
  run_node_tests TEST-4014
  log_pass "TEST-4014: the PowerShell-side corpus (P01 to P17) gives the exit code and the target snapshot of the frozen PowerShell twin after the projections (DR-11, DR-18, DR-20, DR-21, DR-26), and the asserted divergences (DR-1, DR-2, DR-11, DR-13, DR-15, DR-16, DR-17, DR-18, DR-25, DR-27) hold"
}

# scrub_case <label> <suite file> <selector> <injection>: runs one selector of an installer suite from the checkout root with
# core.hooksPath injected through the caller's git environment ("config" = GIT_CONFIG_COUNT, KEY_0 and VALUE_0; "parameters" =
# GIT_CONFIG_PARAMETERS) pointing at an empty scratch victim directory (never a repository); the run must exit 0 and the
# victim must still be empty afterwards.
scrub_case() {
  local label="$1" suite="$2" selector="$3" mode="$4" victim rc=0 log
  victim="$(mktemp -d "$TEST_DIR/victim.XXXXXX")" || log_fail "TEST-4012: mktemp failed"
  [[ -n "$victim" && "$victim" == "$TEST_DIR"/* && -d "$victim" ]] || log_fail "TEST-4012: the victim directory is not under the suite scratch root"
  log="$TEST_DIR/scrub-${label}-${mode}.log"
  case "$mode" in
    config)
      ( cd "$PROJECT_ROOT" && env -u AAI_ROLE GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$victim" bash "$suite" "$selector" ) >"$log" 2>&1 || rc=$?
      ;;
    parameters)
      ( cd "$PROJECT_ROOT" && env -u AAI_ROLE GIT_CONFIG_PARAMETERS="'core.hooksPath'='$victim'" bash "$suite" "$selector" ) >"$log" 2>&1 || rc=$?
      ;;
    *) log_fail "TEST-4012: unknown injection $mode" ;;
  esac
  if [[ "$rc" != 0 ]]; then
    tail -20 "$log" >&2
    log_fail "TEST-4012: $label $selector with core.hooksPath injected through $mode exited $rc"
  fi
  [[ -z "$(ls -A "$victim")" ]] || { ls -A "$victim" >&2; log_fail "TEST-4012: $label $selector with core.hooksPath injected through $mode wrote into the victim directory"; }
  rmdir "$victim" || log_fail "TEST-4012: the victim directory could not be removed"
}

test_4012_git_env_scrub() {
  local repro="$PROJECT_ROOT/docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh" rc=0 log="$TEST_DIR/repro-n1.log" f
  [[ -f "$repro" ]] || log_fail "TEST-4012: the recorded repro does not exist: $repro"
  ( cd "$PROJECT_ROOT" && env -u AAI_ROLE bash "$repro" ) >"$log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$log" >&2; log_fail "TEST-4012: the recorded repro N1 exited $rc (0 once the defect is gone)"; }
  [[ -f "$PROJECT_ROOT/tests/skills/lib/git-env-scrub.sh" ]] || log_fail "TEST-4012: tests/skills/lib/git-env-scrub.sh does not exist"
  local mode
  for mode in config parameters; do
    scrub_case hygiene tests/skills/test-aai-hygiene-pack.sh test_618_ref_guard_grep_conformance "$mode"
    scrub_case doctor tests/skills/test-aai-doctor.sh test_1344_cat17_seam1_installed_hook_passes "$mode"
    scrub_case pre-commit-checks tests/skills/test-aai-pre-commit-checks.sh test_3453_large_debug_list "$mode"
  done
  # the four suites source the helper, run their installers through aai_git_scrubbed and assert the hooks path
  for f in test-aai-git-ref-guard.sh test-aai-hygiene-pack.sh test-aai-doctor.sh test-aai-pre-commit-checks.sh; do
    local file="$PROJECT_ROOT/tests/skills/$f" bare
    /usr/bin/grep -qF 'lib/git-env-scrub.sh' "$file" || log_fail "TEST-4012: $f does not source lib/git-env-scrub.sh"
    /usr/bin/grep -qF 'aai_assert_hooks_under' "$file" || log_fail "TEST-4012: $f never calls aai_assert_hooks_under"
    # every line that runs an installer for real (not --print, --help or a text probe) goes through aai_git_scrubbed
    bare="$(/usr/bin/grep -nE '(bash|pwsh|node)[^|;&]* +("?\$[A-Za-z_{}]*INSTALL[A-Z_]*"?|[^ ]*install-pre-commit-hook\.(sh|ps1|mjs))' "$file" | /usr/bin/grep -vE '^[0-9]+: *#|--print|--help|--this-flag|grep -qF|aai_git_scrubbed' || true)"
    [[ -z "$bare" ]] || { printf '%s\n' "$bare" >&2; log_fail "TEST-4012: $f runs an installer outside aai_git_scrubbed"; }
  done
  # the false comment of the ref-guard suite is gone
  if /usr/bin/grep -qF 'can never redirect an installer run' "$PROJECT_ROOT/tests/skills/test-aai-git-ref-guard.sh"; then log_fail "TEST-4012: the false comment in test-aai-git-ref-guard.sh is still there"; fi
  log_pass "TEST-4012: the recorded repro exits 0, core.hooksPath injected through GIT_CONFIG_COUNT/KEY_0/VALUE_0 and GIT_CONFIG_PARAMETERS reaches none of hygiene test_618, the doctor suite and the pre-commit-checks suite (the victim stays empty, rc 0), and the four suites run their installers through aai_git_scrubbed with aai_assert_hooks_under"
}

# --- run 6a: the sh launcher and the bash-side re-homes (TEST-4015) ---------------------------------------
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
REFUSAL_LINE="aai-sync: refused - node not found in PATH or aai-sync.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run."

# write_stub_module <dir>: an aai-sync.mjs that prints its argv as JSON and exits 7.
write_stub_module() {
  printf '%s\n' 'console.log(JSON.stringify({ argv: process.argv.slice(2) }));' 'process.exit(7);' > "$1/aai-sync.mjs"
}

# expect_pass_through <label> <shell> <launcher copy> <expected argv...>: the copy beside its stub passes the argv
# in order and exit 7 through.
expect_pass_through() {
  local label="$1" shell="$2" copy="$3" out rc=0 verdict
  shift 3
  out="$("$shell" "$copy" "$@" 2>&1)" || rc=$?
  [[ "$rc" == 7 ]] || log_fail "TEST-4015: $label: expected exit 7 through the launcher, got $rc: $out"
  verdict="$(node -e '
    const got = JSON.parse(process.argv[1]);
    const want = process.argv.slice(2);
    const same = got.argv.length === want.length && got.argv.every((a, i) => a === want[i]);
    process.stdout.write(same ? "same" : "differs: " + process.argv[1]);
  ' "$out" "$@")" || log_fail "TEST-4015: $label: the stub output is not JSON: $out"
  [[ "$verdict" == same ]] || log_fail "TEST-4015: $label: $verdict"
}

# expect_refusal <label> <shell> <copy> <path> <target dir>: runs the launcher in the target with the given PATH and
# requires exit 1, empty stdout, exactly the refusal line on stderr and an unchanged target.
expect_refusal() {
  local label="$1" shell="$2" copy="$3" use_path="$4" target="$5" rc=0 before after
  before="$(find "$target" | LC_ALL=C sort)"
  ( cd "$target" && PATH="$use_path" "$shell" "$copy" "$target" --profile core ) > "$target/../refusal.out" 2> "$target/../refusal.err" || rc=$?
  [[ "$rc" == 1 ]] || log_fail "TEST-4015: $label: expected exit 1, got $rc"
  [[ ! -s "$target/../refusal.out" ]] || log_fail "TEST-4015: $label: stdout must be empty"
  [[ "$(cat "$target/../refusal.err")" == "$REFUSAL_LINE" ]] || log_fail "TEST-4015: $label: stderr is not the refusal line: $(cat "$target/../refusal.err")"
  after="$(find "$target" | LC_ALL=C sort)"
  [[ "$before" == "$after" ]] || log_fail "TEST-4015: $label: the target changed"
}

# run_suite_selector <suite file> <selector>: one re-homed or vendoring selector must exit 0.
run_suite_selector() {
  local suite="$1" sel="$2" rc=0 out
  [[ -f "$PROJECT_ROOT/tests/skills/$suite" ]] || log_fail "TEST-4015: tests/skills/$suite does not exist"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/tests/skills/$suite" "$sel" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4015: $suite $sel exited $rc"; }
}

# run_node_selector <file> <pattern>: one re-homed node:test case must pass (a pattern that matches nothing fails).
run_node_selector() {
  local file="$1" pat="$2" rc=0 out
  out="$(env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern "$pat" "$PROJECT_ROOT/tests/skills/lib/$file" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4015: $file $pat exited $rc"; }
  [[ "$out" =~ pass\ [1-9] && "$out" =~ ok\ [0-9]+\ -\ $pat ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4015: $file reported no passing test named $pat"; }
}

test_4015_sh_launcher() {
  [[ -f "$SH_LAUNCHER" ]] || log_fail "TEST-4015: .aai/scripts/aai-sync.sh does not exist"
  local lines mode token body
  lines="$(wc -l < "$SH_LAUNCHER" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || log_fail "TEST-4015: the launcher has $lines lines, at most 20 allowed"
  [[ "$(head -n 1 "$SH_LAUNCHER")" == "#!/bin/sh" ]] || log_fail "TEST-4015: the launcher does not start with #!/bin/sh"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$SH_LAUNCHER"; then log_fail "TEST-4015: the launcher holds a non-ASCII byte"; fi
  mode="$(git -C "$PROJECT_ROOT" ls-files -s .aai/scripts/aai-sync.sh | cut -c1-6)"
  [[ "$mode" == 100755 && -x "$SH_LAUNCHER" ]] || log_fail "TEST-4015: the launcher is not mode 100755 (index: $mode)"
  body="$(/usr/bin/grep -v '^#' "$SH_LAUNCHER")"
  for token in 'git' 'rev-parse' 'PROFILES' 'profile' '.gitignore' 'exit 2' '--profile' 'core' 'extended' 'rm '; do
    [[ "$body" != *"$token"* ]] || log_fail "TEST-4015: the launcher holds the policy token: $token"
  done

  local work copy bin shell
  work="$(new_own_scratch launcher)"
  mkdir "$work/beside" "$work/alone" "$work/bin" "$work/target"
  cp "$SH_LAUNCHER" "$work/beside/launcher-copy.sh"
  cp "$SH_LAUNCHER" "$work/alone/launcher-copy.sh"
  write_stub_module "$work/beside"
  copy="$work/beside/launcher-copy.sh"
  for shell in bash sh dash; do
    need_tool TEST-4015 "$shell" || continue
    expect_pass_through "$shell with a spaced target and the two forms" "$shell" "$copy" "/some path/target" --profile core --profile=extended -h
    expect_pass_through "$shell with the bare flags" "$shell" "$copy" --profile "a b" -h --bogus
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

  # the bash library is gone; PROFILES core lists the module and both libs
  [[ ! -e "$PROJECT_ROOT/.aai/scripts/lib/gitignore-block.sh" ]] || log_fail "TEST-4015: .aai/scripts/lib/gitignore-block.sh is still shipped"
  local verdict entry
  for entry in .aai/scripts/aai-sync.mjs .aai/scripts/lib/resolve-base.mjs .aai/scripts/lib/gitignore-block.mjs; do
    verdict="$(node -e '
      const fs = require("fs");
      const t = fs.readFileSync(process.argv[1], "utf8").split("\n");
      const start = t.findIndex((l) => /^core:/.test(l));
      let found = false;
      for (let i = start + 1; i < t.length && !/^[A-Za-z]/.test(t[i]); i++) {
        if (t[i].trim() === "- " + process.argv[2]) found = true;
      }
      process.stdout.write(found ? "found" : "missing");
    ' "$PROJECT_ROOT/.aai/system/PROFILES.yaml" "$entry")" || verdict="unreadable"
    [[ "$verdict" == found ]] || log_fail "TEST-4015: PROFILES core does not list $entry ($verdict)"
  done
  local rc=0 out
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4015: check-vendored-script-deps exited $rc"; }

  # the bash-side D-REHOME selectors (run 6a)
  local pair
  for pair in \
    "test-aai-sync-seed.sh test_template_and_parity" \
    "test-aai-sync-seed.sh test_audit_template_single_source" \
    "test-aai-sync-seed.sh test_marker_prefix_pinned_across_call_sites" \
    "test-aai-sync-seed.sh test_single_bash_reader_and_sourcing" \
    "test-aai-sync-seed.sh test_library_in_profiles_core" \
    "test-aai-sync-seed.sh test_core_profile_keeps_library_and_bootstrap_works" \
    "test-aai-sync-seed.sh test_library_missing_list_skips_with_note" \
    "test-aai-sync-seed.sh test_bootstrap_survives_missing_library" \
    "test-aai-sync-seed.sh test_runtime_ignore_header_consumer_accuracy" \
    "test-aai-sync-seed.sh test_bash_seed_crlf_safe" \
    "test-aai-sync-seed.sh test_628_compare_fails_closed" \
    "test-aai-sync-seed.sh test_783_hook_json_no_node_leaves_untouched" \
    "test-aai-sync-seed.sh test_795_sync_cache_equivalence" \
    "test-aai-sync-seed.sh test_796_sync_cache_adoption" \
    "test-aai-sync-seed.sh test_831_predicate_awk_child_runs_under_c_locale" \
    "test-aai-layer-profiles.sh test_464_core_prune_survives_large_core_list" \
    "test-aai-layer-profiles.sh test_465_gitignore_membership_survives_large_gitignore" \
    "test-aai-layer-profiles.sh test_466_no_pipe_into_early_closing_reader" \
    "test-aai-layer-profiles.sh test_ps1_parity" \
    "test-aai-layer-drift.sh test_sync_stamps_pin" \
    "test-aai-update-check.sh test_auto_sync" \
    "test-aai-harness-shims.sh test_3008_sync_sh_recognises_shipped_copilot" \
    "test-aai-harness-shims.sh test_3010_sync_sh_installs_agents_md" \
    "test-aai-legacy-migrations.sh test_3396_doctor_seam" \
    "test-aai-bootstrap.sh test_gitignore_seed_uses_shared_library"; do
    run_suite_selector "${pair%% *}" "${pair#* }"
  done
  run_node_selector release-notes-docs.test.mjs TEST-2708
  run_node_selector aai-bootstrap.test.mjs TEST-3948

  # the run 6a contract records of ref sync-on-node
  local json id
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-4015: spec-amend list failed"
  for id in "SPEC-0106-|TEST-003 and TEST-006 re-homed" "SPEC-0157-|TEST-011 to TEST-021 re-homed" "SPEC-0184-|TEST-628 re-homed" \
            "SPEC-0199-|TEST-783 re-homed" "SPEC-0035-|TEST-008 re-homed" "SPEC-0020-|TEST-010 vendors the module" \
            "SPEC-0106-|build_sync_source vendors the module" "SPEC-0253-|TEST-3008 case d re-homed" \
            "SPEC-0253-|TEST-3010 re-homed" "SPEC-0250-|TEST-2708 reads ROOT_SHIMS" "SPEC-0273-|TEST-3396 re-homed" \
            "SPEC-0306-|TEST-3948 the shipped bash library is gone"; do
    verdict="$(node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const [spec, what] = process.argv[1].split("|");
      const hit = d.items.filter((i) => i.ref_id === "sync-on-node" && i.amendment_class === "contract" && i.spec.includes(spec) && i.what.startsWith(what));
      process.stdout.write(hit.length === 1 ? "found" : "count " + hit.length);
    ' "$id" <<<"$json")"
    [[ "$verdict" == found ]] || log_fail "TEST-4015: contract record of ref sync-on-node for $id: $verdict"
  done
  log_pass "TEST-4015: the sh launcher is at most 20 ASCII lines, mode 100755, holds no policy token, passes every argument and the exit code through under bash, sh and dash, refuses with the exact line, exit 1 and an unchanged target without node or the module; the bash library is gone, PROFILES core lists the module and both libs, check-vendored-script-deps exits 0, the bash-side re-homed selectors exit 0 and the run 6a contract records exist"
}

# --- run 6b: the ps1 launcher, the PowerShell-side re-homes and the Pester launcher context (TEST-4016) ----------
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/aai-sync.Tests.ps1"

# ps1_problems <file>: prints one line per way the launcher text breaks D-LAUNCH.
ps1_problems() {
  local f="$1" lines body token
  lines="$(wc -l < "$f" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || echo "the launcher has $lines lines, at most 20 allowed"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$f"; then echo "the launcher holds a non-ASCII byte"; fi
  if /usr/bin/grep -qi '^[[:space:]]*param[[:space:]]*(' "$f"; then echo "the launcher holds a param block"; fi
  body="$(/usr/bin/grep -v '^#' "$f")"
  for token in 'rev-parse' 'PROFILES' 'profile' 'Profile' '.gitignore' 'exit 2' 'TargetRoot' 'core' 'extended' 'Remove-Item'; do
    [[ "$body" != *"$token"* ]] || echo "the launcher holds the policy token: $token"
  done
  if printf '%s\n' "$body" | qgrep -qE '(^|[^A-Za-z-])git([^A-Za-z-]|$)'; then echo "the launcher names git"; fi
}

# run_pester <label> <work dir> [<full name filter>]: Invoke-Pester on the sync Pester file in the project root; prints
# "PESTER passed=N skipped=N failed=N containers=N" and fails the test when Pester did not run.
run_pester() {
  local label="$1" work="$2" filter="${3:-}" out
  ( cd "$PROJECT_ROOT" && AAI_PESTER_FILTER="$filter" env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command '
    Import-Module Pester -MinimumVersion 5.0
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = "tests/skills/aai-sync.Tests.ps1"
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

# amend_count <list json> <spec id fragment> <what prefix>: prints the number of contract records of ref sync-on-node.
amend_count() {
  node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const hit = d.items.filter((i) => i.ref_id === "sync-on-node" && i.amendment_class === "contract" && i.spec.includes(process.argv[1]) && i.what.startsWith(process.argv[2]));
    process.stdout.write(String(hit.length));
  ' "$2" "$3" <<<"$1"
}

test_4016_ps1_launcher() {
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-4016: .aai/scripts/aai-sync.ps1 does not exist"
  local problems work counts pair rc out json id
  problems="$(ps1_problems "$PS1_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-4016: $problems"
  need_pester TEST-4016 || return 0
  work="$(new_own_scratch pester-launcher)"
  counts="$(run_pester TEST-4016 "$work" '*launcher (sync-on-node)*')"
  [[ "$counts" == "PESTER passed=5 skipped=0 failed=0 containers=0" ]] || { cat "$work/pester.log" >&2; log_fail "TEST-4016: Pester summary '$counts', expected 5 passed, 0 skipped, 0 failed, 0 failed containers"; }
  safe_rm_own "$work"
  # the PowerShell-side re-homed selectors (run 6b): each exits 0 and none skips a part
  for pair in \
    "test-aai-sync-seed.sh test_template_and_parity" \
    "test-aai-sync-seed.sh test_audit_template_single_source" \
    "test-aai-sync-seed.sh test_ps1_seeds_all_patterns" \
    "test-aai-sync-seed.sh test_ps1_second_run_idempotent" \
    "test-aai-sync-seed.sh test_ps1_preserves_user_lines_and_seeds_commented_pattern" \
    "test-aai-sync-seed.sh test_legacy_marker_no_duplicate_across_engines" \
    "test-aai-sync-seed.sh test_marker_prefix_pinned_across_call_sites" \
    "test-aai-sync-seed.sh test_runtime_ignore_header_consumer_accuracy" \
    "test-aai-sync-seed.sh test_git_status_clean_after_spool_creation" \
    "test-aai-sync-seed.sh test_agents_skills_mirror_synced" \
    "test-aai-sync-seed.sh test_628_compare_fails_closed" \
    "test-aai-sync-seed.sh test_779_ps1_engine_hooks_parity" \
    "test-aai-sync-seed.sh test_788_ps1_engine_update_and_left_as_is_parity" \
    "test-aai-sync-seed.sh test_790_ps1_user_edited_matcher_and_fields_preserved" \
    "test-aai-sync-seed.sh test_791_hooks_dotfiles_synced_and_preserved_cross_engine" \
    "test-aai-sync-seed.sh test_795_sync_cache_equivalence" \
    "test-aai-sync-seed.sh test_829_ps1_retired_removal_parity" \
    "test-aai-sync-seed.sh test_830_ps1_preservation_parity" \
    "test-aai-sync-seed.sh test_833_ps1_delete_failure_warns_and_continues" \
    "test-aai-layer-profiles.sh test_ps1_parity" \
    "test-aai-layer-drift.sh test_ps1_parity" \
    "test-aai-harness-shims.sh test_3011_sync_ps1_installs_agents_md"; do
    rc=0
    out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/tests/skills/${pair%% *}" "${pair#* }" 2>&1)" || rc=$?
    [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4016: ${pair%% *} ${pair#* } exited $rc"; }
    [[ "$out" != *"SKIP"* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-4016: ${pair%% *} ${pair#* } skipped a part"; }
  done
  # no re-homed function reads the .ps1's text
  local f
  for f in test-aai-sync-seed.sh test-aai-layer-profiles.sh test-aai-layer-drift.sh; do
    if /usr/bin/grep -E '(grep|egrep|fgrep|awk|sed|cat|head|tail)[^|#]*\$\{?SYNC_PS1' "$PROJECT_ROOT/tests/skills/$f" | /usr/bin/grep -vE 'pwsh|^[[:space:]]*#' >/dev/null; then
      log_fail "TEST-4016: $f still reads the .ps1's text"
    fi
  done
  work="$(new_own_scratch pester-whole)"
  counts="$(run_pester TEST-4016 "$work")"
  [[ "$counts" == "PESTER passed=5 skipped=0 failed=0 containers=0" ]] || { cat "$work/pester.log" >&2; log_fail "TEST-4016: whole-file Pester summary '$counts', expected 5 passed with 0 skips, 0 failures and 0 failed containers"; }
  safe_rm_own "$work"
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-4016: spec-amend list failed"
  id="SPEC-0253-|TEST-3011 re-homed"
  out="$(amend_count "$json" "${id%%|*}" "${id#*|}")"
  [[ "$out" == 1 ]] || log_fail "TEST-4016: contract records of ref sync-on-node for $id: $out, want 1"
  log_pass "TEST-4016: the ps1 launcher is at most 20 ASCII lines with no param block and no policy token, the five Pester launcher cases pass with 0 skips, 0 failures and 0 failed containers, the PowerShell-side re-homed selectors exit 0 with no assertion reading the .ps1 text, and the TEST-3011 record exists"
}

# --- run 6c: the parity third twin (TEST-4017) ----------------------------------------------------------------------
PARITY_DRIVER="$PROJECT_ROOT/tests/skills/lib/install-parity.mjs"
PARITY_TEST="$PROJECT_ROOT/tests/skills/lib/install-parity.test.mjs"
BOOTSTRAP_TEST="$PROJECT_ROOT/tests/skills/lib/aai-bootstrap.test.mjs"

test_4017_parity_sync() {
  need_tool TEST-4017 pwsh || return 0
  local work rc=0 verdict json args id
  work="$(new_own_scratch parity-sync)"
  args=()
  for id in SY-01 SY-02 SY-03 SY-04 SY-05 SY-06 SY-07; do args+=(--scenario "$id"); done
  env -u AAI_ROLE -u AAI_GIT_WRITE node "$PARITY_DRIVER" run --matrix full --twins sh,ps1,node "${args[@]}" --json "$work/sy.json" > "$work/sy.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/sy.out" >&2; log_fail "TEST-4017: the driver run over SY-01 to SY-07 exited $rc"; }
  verdict="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    if (r.verdict !== "PASS") bad.push("verdict " + r.verdict);
    for (const id of ["SY-01", "SY-02", "SY-03", "SY-04", "SY-05", "SY-06", "SY-07"]) {
      const s = r.scenarios.find((x) => x.id === id);
      if (!s) { bad.push(id + " missing"); continue; }
      const twins = [...new Set(s.steps.map((x) => x.twin))].sort().join(",");
      if (twins !== "node,ps1,sh") bad.push(id + " ran twins " + twins);
    }
    const cross = r.pairs.filter((p) => p.split(":")[0] !== p.split(":")[1]).sort().join(" ");
    if (cross !== "ps1:node sh:node sh:ps1") bad.push("pairs " + cross);
    if (r.uncovered.length) bad.push("uncovered " + JSON.stringify(r.uncovered));
    process.stdout.write(bad.length ? bad.join("; ") : "ok");
  ' "$work/sy.json")" || log_fail "TEST-4017: cannot read the driver report"
  [[ "$verdict" == ok ]] || { cat "$work/sy.out" >&2; log_fail "TEST-4017: $verdict"; }
  # the sh and ps1 argv name syref
  verdict="$(AAI_PARITY_DRIVER_PATH="$PARITY_DRIVER" node --input-type=module -e '
    const m = await import(process.env.AAI_PARITY_DRIVER_PATH);
    const bad = [];
    const ctx = { src: "/s", target: "/t", bash: "bash", ps: "pwsh", syref: "/sy" };
    const sy = { op: "sync", profile: "core", flags: [] };
    const sh = m.TWINS.sh.argv(sy, ctx);
    if (sh.args[0] !== "/sy/.aai/scripts/aai-sync.sh") bad.push("sh argv " + sh.args[0]);
    const ps = m.TWINS.ps1.argv(sy, ctx);
    if (!ps.args.includes("/sy/.aai/scripts/aai-sync.ps1")) bad.push("ps1 argv " + ps.args.join(" "));
    process.stdout.write(bad.length ? bad.join("; ") : "ok");
  ')"
  [[ "$verdict" == ok ]] || log_fail "TEST-4017: $verdict"
  run_node_tests TEST-4017 "$PARITY_TEST"
  run_node_tests TEST-3956 "$BOOTSTRAP_TEST"
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-4017: spec-amend list failed"
  for id in "SPEC-0284-|D-SEAM sync twins run the frozen references" "SPEC-0306-|TEST-3956 node twin operations"; do
    verdict="$(amend_count "$json" "${id%%|*}" "${id#*|}")"
    [[ "$verdict" == 1 ]] || log_fail "TEST-4017: contract records of ref sync-on-node for $id: $verdict, want 1"
  done
  safe_rm_own "$work"
  log_pass "TEST-4017: the parity driver passes SY-01 to SY-07 with twins sh, ps1 and node on all three pairs against the allowlist, the sh and ps1 twins run the frozen references from syref, the unit tests and TEST-3956 hold, and the SPEC-0284 and SPEC-0306 records exist"
}

UPGRADE_TEST="$PROJECT_ROOT/tests/skills/lib/sync-upgrade.test.mjs"

# TEST-4018 (D-UPGRADE): the upgrade proof in scratch trees. The old layer is `git archive` of the last commit before the ride
# (read-only) extracted into the suite's own scratch root; every source, target and cwd of the cases lies under that root.
test_4018_upgrade() {
  local work
  need_tool TEST-4018 pwsh || true
  work="$(new_own_scratch upgrade)"
  AAI_SYNC_UPGRADE_ROOT="$work" run_node_tests TEST-4018 "$UPGRADE_TEST"
  safe_rm_own "$work"
  log_pass "TEST-4018: U0 fresh install, U1 old install updated by the new updater, U2 old engine over a new tree, U3 the pre-ride-10 updater and U4 the PowerShell runner (named skip without pwsh) vendor the module and both libs, keep the core profile, prune exactly the old core files the new list lacks and run the target's own sync, update, hook installer and bootstrap launchers; no node refuses with the D-LAUNCH line and an unchanged target"
}

# suite_map_rows <suite-map.yaml>: prints "row<TAB>glob" lines.
suite_map_rows() {
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    let row = "";
    for (const l of lines) {
      const m = /^  ([a-z0-9-]+):$/.exec(l);
      if (m) row = m[1];
      else if (row && /^      - /.test(l)) process.stdout.write(row + "\t" + l.replace(/^      - /, "") + "\n");
    }
  ' "$1"
}

# TEST-4019 (D-WIRE): the wiring of the suites, the weights, the pins, the ratchets and the path lists.
test_4019_wiring() {
  local work f out rc sel rows
  work="$(new_own_scratch wiring)"
  # every file of the ride routes to aai-sync-node; the two shared libs escalate to FULL_RUN (the .aai/scripts/lib/** shared-lib glob)
  for f in .aai/scripts/aai-sync.mjs .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 \
    tests/fixtures/sync-reference/aai-sync.sh tests/fixtures/sync-reference/aai-sync.ps1 tests/fixtures/sync-reference/gitignore-block.sh \
    tests/skills/lib/aai-sync.test.mjs tests/skills/lib/resolve-base.test.mjs tests/skills/lib/sync-reference.mjs tests/skills/lib/sync-upgrade.test.mjs \
    tests/skills/aai-sync.Tests.ps1 tests/skills/lib/git-env-scrub.sh; do
    printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - > "$work/sel.out" 2>&1 || true
    qgrep -q "^SELECTED aai-sync-node " < "$work/sel.out" || { cat "$work/sel.out" >&2; log_fail "TEST-4019: select-suites does not route $f to aai-sync-node"; }
  done
  for f in .aai/scripts/lib/resolve-base.mjs .aai/scripts/lib/gitignore-block.mjs; do
    printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - > "$work/sel.out" 2>&1 || true
    qgrep -q "^FULL_RUN reason=shared-lib path=$f" < "$work/sel.out" || { cat "$work/sel.out" >&2; log_fail "TEST-4019: select-suites does not escalate $f to FULL_RUN shared-lib"; }
  done
  rows="$(suite_map_rows "$PROJECT_ROOT/tests/skills/suite-map.yaml")" || log_fail "TEST-4019: cannot read suite-map.yaml"
  # every suite-map row that names aai-sync.sh or aai-sync.ps1 names the module (or the aai-sync.* glob); no row names the deleted bash library
  out="$(printf '%s\n' "$rows" | node -e '
    const rows = {};
    for (const l of require("fs").readFileSync(0, "utf8").split("\n")) {
      if (!l) continue;
      const [k, v] = l.split("\t");
      (rows[k] = rows[k] || []).push(v);
    }
    const bad = [];
    let named = 0;
    for (const [k, v] of Object.entries(rows)) {
      if (v.includes(".aai/scripts/aai-sync.sh") || v.includes(".aai/scripts/aai-sync.ps1") || v.includes(".aai/scripts/aai-sync.*")) {
        named += 1;
        if (!v.includes(".aai/scripts/aai-sync.mjs") && !v.includes(".aai/scripts/aai-sync.*")) bad.push(k + " lacks aai-sync.mjs");
      }
      if (v.some((g) => /gitignore-block\.sh$/.test(g))) bad.push(k + " names gitignore-block.sh");
    }
    if (named < 14) bad.push("only " + named + " rows name aai-sync.sh or .ps1 (want 14 or more)");
    process.stdout.write(bad.join(", "));
  ')" || log_fail "TEST-4019: the row check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4019: suite-map rows: $out"
  for sel in "aai-sync-node	tests/skills/test-aai-sync-node.sh" "aai-sync-node	tests/skills/lib/sync-upgrade.test.mjs" "aai-sync-docs	tests/skills/test-aai-sync-docs.sh" \
    "aai-sync-docs	CHANGELOG.md" "aai-sync-docs	README.md" "aai-sync-docs	docs/USER_GUIDE.md" "aai-sync-docs	docs/product/sync-on-node.md" \
    "aai-sync-docs	docs/analysis/node-first-remaining-plan.md" "aai-sync-docs	docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"; do
    printf '%s\n' "$rows" | qgrep -qxF "$sel" || log_fail "TEST-4019: the suite-map row is missing: ${sel/	/ -> }"
  done
  for sel in aai-sync-node aai-sync-docs; do
    qgrep -qxF "$(printf '%s\t196' "$sel")" < "$PROJECT_ROOT/tests/skills/suite-weights.tsv" || log_fail "TEST-4019: the weights row $sel 196 is missing"
  done
  qgrep -qxF "# sample aai-sync-node fallback unsampled (new suite of sync-on-node; no successful observation)" < "$PROJECT_ROOT/tests/skills/suite-weights.tsv" \
    || log_fail "TEST-4019: the weights fallback line for aai-sync-node is missing"
  qgrep -qxF "# sample aai-sync-docs fallback unsampled (split from aai-sync-node by sync-on-node; no successful observation)" < "$PROJECT_ROOT/tests/skills/suite-weights.tsv" \
    || log_fail "TEST-4019: the weights fallback line for aai-sync-docs is missing"
  for sel in "test-aai-hygiene-pack.sh test_090_suite_map_pin" "test-aai-hygiene-pack.sh test_128_shipping_scripts_pipe_safe_at_zero" "test-aai-hygiene-pack.sh test_129_mutation_gate_suite_registration" \
    "test-aai-win-fallback.sh test_034" "test-aai-win-fallback.sh test_035"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-4019: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  qgrep -q "row-count pin holds at 144\|-eq 144" < "$SCRIPT_DIR/test-aai-hygiene-pack.sh" || log_fail "TEST-4019: test_090 does not pin 144 suite-map rows"
  rc=0
  node "$SCRIPT_DIR/lib/nested-suite-lint.mjs" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" > "$work/lint.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/lint.log" >&2; log_fail "TEST-4019: nested-suite-lint exited $rc"; }
  for f in check-cd-subshell-leak.mjs check-vendored-script-deps.mjs; do
    rc=0
    node "$PROJECT_ROOT/.aai/scripts/$f" > "$work/chk.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-4019: $f exited $rc"; }
  done
  rc=0
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" > "$work/chk.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-4019: check-test-registration.mjs exited $rc"; }
  qgrep -qxF "$(printf '1\t.aai/scripts/aai-sync.sh')" < "$SCRIPT_DIR/lib/cd-subshell-leak-baseline.tsv" || log_fail "TEST-4019: the cd-subshell baseline does not hold 1 for .aai/scripts/aai-sync.sh"
  out="$(node -e '
    const fs = require("fs");
    const text = fs.readFileSync(process.argv[1], "utf8").split("\n");
    const lists = [];
    for (const key of ["push:", "pull_request:"]) {
      const at = text.findIndex((l) => l === "  " + key);
      if (at < 0) { lists.push(null); continue; }
      const p = text.findIndex((l, i) => i > at && l === "    paths:");
      const out = [];
      for (let i = p + 1; i < text.length && /^      - /.test(text[i]); i += 1) out.push(text[i].replace(/^      - /, "").replace(/^\x27|\x27$/g, ""));
      lists.push(out);
    }
    const bad = [];
    if (!lists[0] || !lists[1]) bad.push("a path list is missing");
    else {
      if (JSON.stringify(lists[0]) !== JSON.stringify(lists[1])) bad.push("the push and pull_request path lists differ");
      for (const w of [".aai/scripts/aai-sync.mjs", ".aai/scripts/lib/resolve-base.mjs", ".aai/scripts/lib/gitignore-block.mjs", "tests/fixtures/sync-reference/**", "tests/skills/lib/sync-reference.mjs"]) {
        if (!lists[0].includes(w)) bad.push("the push list lacks " + w);
        if (!lists[1].includes(w)) bad.push("the pull_request list lacks " + w);
      }
      for (const w of [".aai/scripts/lib/gitignore-block.sh"]) {
        if (lists[0].includes(w) || lists[1].includes(w)) bad.push("a path list still holds " + w);
      }
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/.github/workflows/ps1-quality.yml")" || log_fail "TEST-4019: the path-list check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4019: ps1-quality.yml: $out"
  # the prompt corpus (.aai/*.prompt.md and .aai/AGENTS.md) is byte-equal to the commit before the ride
  out="$(PROJECT_ROOT="$PROJECT_ROOT" node -e '
    const { execFileSync } = require("child_process");
    const fs = require("fs");
    const root = process.env.PROJECT_ROOT;
    const git = (args) => execFileSync("git", ["-C", root, ...args], { encoding: "buffer", maxBuffer: 64 * 1024 * 1024 });
    try { git(["cat-file", "-e", "077ee649^{commit}"]); } catch { process.stdout.write("commit 077ee649 is not in this clone"); process.exit(0); }
    const names = git(["ls-tree", "--name-only", "077ee649", ".aai/"]).toString("utf8").split("\n").filter((n) => /^\.aai\/[^\/]*\.prompt\.md$/.test(n) || n === ".aai/AGENTS.md");
    const now = fs.readdirSync(root + "/.aai").filter((n) => /\.prompt\.md$/.test(n) || n === "AGENTS.md").map((n) => ".aai/" + n).sort();
    const bad = [];
    if (names.length < 30) bad.push("the corpus at 077ee649 lists only " + names.length + " files");
    if (JSON.stringify(names.slice().sort()) !== JSON.stringify(now)) bad.push("the corpus file set differs from 077ee649");
    for (const n of names) {
      let want;
      try { want = git(["show", "077ee649:" + n]); } catch { bad.push(n + " unreadable at 077ee649"); continue; }
      if (!fs.existsSync(root + "/" + n) || Buffer.compare(want, fs.readFileSync(root + "/" + n)) !== 0) bad.push(n + " differs");
    }
    process.stdout.write(bad.join("; "));
  ')" || log_fail "TEST-4019: the prompt corpus check failed to run"
  [[ -z "$out" ]] || log_fail "TEST-4019: the prompt corpus: $out"
  safe_rm_own "$work"
  log_pass "TEST-4019: select-suites routes the module, launchers, libs, reference copies, test files, the Pester file and git-env-scrub.sh to aai-sync-node (FULL_RUN for the two libs), every row naming aai-sync.sh names the module and none names the bash library, the weights rows and fallback lines hold, test_090, test_128, test_129, test_034 and test_035 pass, the lint and checks exit 0, the baseline holds 1 for aai-sync.sh, both ps1-quality path lists are identical and hold the D-WIRE entries, and the prompt corpus equals 077ee649"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4000..4019)"
  check_deps
  setup_fixture
  test_4000_scratch_safety
  test_4001_module_shape
  test_4002_cli
  test_4003_root_refusals
  test_4004_shared_base
  test_4005_gitignore
  test_4006_legacy_dropped
  test_4007_core_prune
  test_4008_copy_and_guard
  test_4009_surfaces
  test_4010_copilot_and_hooks
  test_4011_report_and_pin
  test_4012_git_env_scrub
  test_4013_corpus_bash
  test_4014_corpus_powershell
  test_4015_sh_launcher
  test_4016_ps1_launcher
  test_4017_parity_sync
  test_4018_upgrade
  test_4019_wiring
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
