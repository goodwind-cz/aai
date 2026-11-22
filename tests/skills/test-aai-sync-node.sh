#!/usr/bin/env bash
#
# Test: aai-sync-node
# (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, TEST-4000..4019; this file holds TEST-4000..4019 as the runs add
# them (TEST-4020 to TEST-4022 live in test-aai-sync-docs.sh); run 1 holds TEST-4000..4003, run 2 TEST-4004..4006, run 3 TEST-4007..4009)
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

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-4000..4009)"
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
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
