#!/usr/bin/env bash
#
# Test: aai-update-node
# (docs/specs/SPEC-0307-spec-update-on-node.md, TEST-3960..3977; this file grows run by run (TEST-3978 lives in test-aai-update-docs.sh))
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
  local id="$1" file="${2:-$NODE_TEST}" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/aai-update.mjs does not exist"
  [[ -f "$REF_HELPER" ]] || log_fail "$id: tests/skills/lib/update-reference.mjs does not exist"
  [[ -f "$REFERENCE_SH" && -f "$REFERENCE_PS1" ]] || log_fail "$id: a frozen reference copy under tests/fixtures/aai-update-reference does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/aai-update.test.mjs does not exist"
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

test_3969_corpus_bash() {
  command -v bash >/dev/null 2>&1 || log_skip "TEST-3969: bash not found"
  run_node_tests TEST-3969
  log_pass "TEST-3969: every bash-side corpus case agrees with the frozen bash reference in exit, stdout, stderr, tree, source branch and HEAD, TMPDIR listing and gh log after the registered rewrites; each rewrite changes a byte; the asserted divergences hold"
}

test_3970_corpus_powershell() {
  need_tool TEST-3970 pwsh || return 0
  run_node_tests TEST-3970
  log_pass "TEST-3970: every PowerShell-side corpus case agrees with the frozen PowerShell reference run under pwsh, with the module on the pwsh runner, after the registered rewrites; the asserted divergences hold"
}

# --- run 5: the sh launcher and the bash-side re-homes (TEST-3971, TEST-3973) -----------------------------
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-update.sh"
UPDATE_SUITE="$PROJECT_ROOT/tests/skills/test-aai-update.sh"
REFUSAL_LINE="aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run."

# write_stub_module <dir>: an aai-update.mjs that prints {argv, runner} as JSON and exits 7.
write_stub_module() {
  printf '%s\n' 'console.log(JSON.stringify({ argv: process.argv.slice(2), runner: process.env.AAI_UPDATE_SYNC_RUNNER }));' 'process.exit(7);' > "$1/aai-update.mjs"
}

# expect_pass_through <label> <shell> <launcher copy> <expected argv...>: runs the copy beside its stub with a preset
# runner value and requires the argv in order, the runner value bash and exit 7.
expect_pass_through() {
  local label="$1" shell="$2" copy="$3" out rc=0 verdict
  shift 3
  out="$(AAI_UPDATE_SYNC_RUNNER=preset "$shell" "$copy" "$@" 2>&1)" || rc=$?
  [[ "$rc" == 7 ]] || log_fail "TEST-3971: $label: expected exit 7 through the launcher, got $rc: $out"
  verdict="$(node -e '
    const got = JSON.parse(process.argv[1]);
    const want = process.argv.slice(2);
    const same = got.runner === "bash" && got.argv.length === want.length && got.argv.every((a, i) => a === want[i]);
    process.stdout.write(same ? "same" : "differs: " + process.argv[1]);
  ' "$out" "$@")" || log_fail "TEST-3971: $label: the stub output is not JSON: $out"
  [[ "$verdict" == same ]] || log_fail "TEST-3971: $label: $verdict"
}

# expect_refusal <label> <shell> <copy> <path> <target dir>: runs the launcher in the target with the given PATH and
# requires exit 1, empty stdout, exactly the refusal line on stderr and an unchanged target.
expect_refusal() {
  local label="$1" shell="$2" copy="$3" use_path="$4" target="$5" rc=0 before after
  before="$(find "$target" | LC_ALL=C sort)"
  ( cd "$target" && PATH="$use_path" "$shell" "$copy" --dry-run ) > "$target/../refusal.out" 2> "$target/../refusal.err" || rc=$?
  [[ "$rc" == 1 ]] || log_fail "TEST-3971: $label: expected exit 1, got $rc"
  [[ ! -s "$target/../refusal.out" ]] || log_fail "TEST-3971: $label: stdout must be empty"
  [[ "$(cat "$target/../refusal.err")" == "$REFUSAL_LINE" ]] || log_fail "TEST-3971: $label: stderr is not the refusal line: $(cat "$target/../refusal.err")"
  after="$(find "$target" | LC_ALL=C sort)"
  [[ "$before" == "$after" ]] || log_fail "TEST-3971: $label: the target changed"
}

test_3971_sh_launcher() {
  [[ -f "$SH_LAUNCHER" ]] || log_fail "TEST-3971: .aai/scripts/aai-update.sh does not exist"
  local lines mode token
  lines="$(wc -l < "$SH_LAUNCHER" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || log_fail "TEST-3971: the launcher has $lines lines, at most 20 allowed"
  [[ "$(head -n 1 "$SH_LAUNCHER")" == "#!/bin/sh" ]] || log_fail "TEST-3971: the launcher does not start with #!/bin/sh"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$SH_LAUNCHER"; then log_fail "TEST-3971: the launcher holds a non-ASCII byte"; fi
  mode="$(git -C "$PROJECT_ROOT" ls-files -s .aai/scripts/aai-update.sh | cut -c1-6)"
  [[ "$mode" == 100755 && -x "$SH_LAUNCHER" ]] || log_fail "TEST-3971: the launcher is not mode 100755 (index: $mode)"
  local body
  body="$(/usr/bin/grep -v '^# Usage:' "$SH_LAUNCHER")"
  for token in 'git' 'gh ' 'aai-sync' 'REFUSED' 'canonical' '--dry-run' 'exit 2' 'exit 3' 'exit 4'; do
    [[ "$body" != *"$token"* ]] || log_fail "TEST-3971: the launcher holds the policy token: $token"
  done

  local work copy bin shell
  work="$(new_own_scratch launcher)"
  mkdir "$work/beside" "$work/alone" "$work/bin" "$work/target"
  cp "$SH_LAUNCHER" "$work/beside/aai-update.sh"
  cp "$SH_LAUNCHER" "$work/alone/aai-update.sh"
  write_stub_module "$work/beside"
  copy="$work/beside/aai-update.sh"
  for shell in bash sh dash; do
    need_tool TEST-3971 "$shell" || continue
    expect_pass_through "$shell with a spaced value" "$shell" "$copy" --repo "dir with space" --ref dev --dry-run --keep-temp --force -h
    expect_pass_through "$shell with the = forms" "$shell" "$copy" "--repo=dir with space" --ref=dev --force
  done
  # PATH holding only dirname: the module exists but node is not found
  bin="$work/bin"
  ln -s "$(command -v dirname)" "$bin/dirname"
  mkdir "$work/target/inner"
  for shell in "$(command -v bash)" "$(command -v sh)"; do
    expect_refusal "no node ($shell)" "$shell" "$copy" "$bin" "$work/target"
  done
  # node is on PATH but the module is missing: the launcher copied alone
  expect_refusal "module missing" "$(command -v sh)" "$work/alone/aai-update.sh" "$PATH" "$work/target"
  safe_rm_own "$work"
  log_pass "TEST-3971: the sh launcher is at most 20 ASCII lines, mode 100755, holds no policy token, passes every argument and the exit code through with the runner bash under bash, sh and dash, and refuses with the exact line, exit 1 and an unchanged target without node or without the module"
}

test_3973_rehomed_bash_suites() {
  local sel id rc out verdict
  for sel in test_001_clone_target_is_srcdir test_002_no_midrun_rm_tmp test_003_bash_syntax_check \
    test_004_dry_run_happy_path test_005_integration_file_fixture_clone test_006_0137_update_writes_field_report \
    test_008_0137_induced_failure_update_runs test_010_0137_timeout_and_zero_network test_014_0137_ps1_parity_structural; do
    rc=0
    out="$(env -u AAI_ROLE bash "$UPDATE_SUITE" "$sel" 2>&1)" || rc=$?
    [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3973: test-aai-update.sh $sel exited $rc"; }
  done
  rc=0
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-layer-drift.sh" test_ps1_parity 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3973: test-aai-layer-drift.sh test_ps1_parity exited $rc"; }
  rc=0
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-hygiene-pack.sh" test_128_shipping_scripts_pipe_safe_at_zero 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3973: test-aai-hygiene-pack.sh test_128 exited $rc"; }

  # a forced failing copy of the suite leaves no own scratch root behind
  local work copy_root left forced_suite
  work="$(new_own_scratch forced)"
  copy_root="$work/copy"
  mkdir -p "$copy_root/tests/skills/lib" "$copy_root/.aai/scripts" "$work/tmp"
  cp "$PROJECT_ROOT/tests/skills/lib/pipe-safe.sh" "$copy_root/tests/skills/lib/pipe-safe.sh"
  cp "$SH_LAUNCHER" "$copy_root/.aai/scripts/aai-update.sh"
  cp "$MJS" "$copy_root/.aai/scripts/aai-update.mjs"
  mkdir -p "$copy_root/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/lib/resolve-base.mjs" "$copy_root/.aai/scripts/lib/resolve-base.mjs"
  forced_suite="$copy_root/tests/skills/${UPDATE_SUITE##*/}"
  sed 's/^  check_deps$/  check_deps; log_fail "forced failure"/' "$UPDATE_SUITE" > "$forced_suite"
  /usr/bin/grep -q 'forced failure' "$forced_suite" || log_fail "TEST-3973: the forced failure was not injected into the copy"
  rc=0
  out="$(env -u AAI_ROLE TMPDIR="$work/tmp" bash "$forced_suite" 2>&1)" || rc=$?
  [[ "$rc" != 0 && "$out" == *"forced failure"* ]] || log_fail "TEST-3973: the forced failing copy did not fail as injected (rc $rc): $out"
  left="$(find "$work/tmp" -maxdepth 1 -name 'aai-update-suite.*')"
  [[ -z "$left" ]] || log_fail "TEST-3973: the failing suite left its scratch root behind: $left"
  safe_rm_own "$work"

  # the contract records of ref update-on-node
  local json
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3973: spec-amend list failed"
  for id in "SPEC-0124-|0137-TEST-005 and 0137-TEST-009 re-homed" "SPEC-0020-|TEST-010b re-homed" \
    "SPEC-0179-|TEST-470 vacuity floor" "SPEC-0052-|TEST-001 and TEST-002 re-homed"; do
    verdict="$(node -e '
      const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
      const [spec, what] = process.argv[1].split("|");
      const hit = d.items.filter((i) => i.ref_id === "update-on-node" && i.amendment_class === "contract" && i.spec.includes(spec) && i.what.startsWith(what));
      process.stdout.write(hit.length >= 1 ? "found" : "missing");
    ' "$id" <<<"$json")"
    [[ "$verdict" == found ]] || log_fail "TEST-3973: no contract record of ref update-on-node for $id"
  done
  log_pass "TEST-3973: the re-homed bash selectors exit 0 against the launcher, a forced failing copy of test-aai-update.sh removes its own scratch root, and the four contract records of ref update-on-node exist"
}

# --- run 6: the ps1 launcher, the Pester re-homes and the parity harness third twin (TEST-3972, 3974, 3975) -----
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-update.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/aai-update.Tests.ps1"
PARITY_DRIVER="$PROJECT_ROOT/tests/skills/lib/install-parity.mjs"
PARITY_TEST="$PROJECT_ROOT/tests/skills/lib/install-parity.test.mjs"

# ps1_problems <file>: the D-LAUNCH text rules for the ps1 launcher, one problem per line (empty when none).
ps1_problems() {
  local f="$1" lines token body
  lines="$(wc -l < "$f" | tr -d ' ')"
  [[ "$lines" -le 20 ]] || echo "the launcher has $lines lines, at most 20 allowed"
  if LC_ALL=C /usr/bin/grep -q '[^ -~	]' "$f"; then echo "the launcher holds a non-ASCII byte"; fi
  if /usr/bin/grep -qi '^[[:space:]]*param[[:space:]]*(' "$f"; then echo "the launcher holds a param block"; fi
  body="$(/usr/bin/grep -v '^# Usage:' "$f")"
  for token in 'git' 'gh ' 'aai-sync' 'REFUSED' 'canonical' '--dry-run' 'exit 2' 'exit 3' 'exit 4'; do
    [[ "$body" != *"$token"* ]] || echo "the launcher holds the policy token: $token"
  done
}

# run_pester <label> <work dir> [<full name filter>]: Invoke-Pester on the update Pester file in the project root;
# prints "PESTER passed=N skipped=N failed=N containers=N" and fails the test when Pester did not run.
run_pester() {
  local label="$1" work="$2" filter="${3:-}" out
  ( cd "$PROJECT_ROOT" && AAI_PESTER_FILTER="$filter" env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command '
    Import-Module Pester -MinimumVersion 5.0
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = "tests/skills/aai-update.Tests.ps1"
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

test_3972_ps1_launcher() {
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-3972: .aai/scripts/aai-update.ps1 does not exist"
  local problems work counts
  problems="$(ps1_problems "$PS1_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-3972: $problems"
  need_tool TEST-3972 pwsh || return 0
  work="$(new_own_scratch pester-launcher)"
  counts="$(run_pester TEST-3972 "$work" '*launcher (update-on-node)*')"
  [[ "$counts" == "PESTER passed=5 skipped=0 failed=0 containers=0" ]] || { cat "$work/pester.log" >&2; log_fail "TEST-3972: Pester summary '$counts', expected 5 passed, 0 skipped, 0 failed, 0 failed containers"; }
  safe_rm_own "$work"
  log_pass "TEST-3972: the ps1 launcher is at most 20 ASCII lines with no param block and no policy token, and the five launcher cases pass under Invoke-Pester with 0 skips, 0 failures and 0 failed containers"
}

test_4050_colon_grammar() {
  run_node_tests TEST-4050
  log_pass "TEST-4050: parseArgs reads -DryRun false, -DryRun \$true, -DryRun:true, -Repo:X and -Repo: X like the release module does"
}

# marshal_json <work> <mode> <args...>: runs the launcher copy beside the stub module and prints the argv the stub saw as JSON.
# mode "session" runs it from -Command with the args as PowerShell text; mode "file" runs it with -File.
marshal_json() {
  local work="$1" mode="$2" copy
  shift 2
  copy="$work/launcher.ps1"
  case "$mode" in
    session) env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command "& '$copy' $*" ;;
    *) env -u AAI_ROLE pwsh -NoProfile -NonInteractive -File "$copy" "$@" ;;
  esac
}

test_4051_ps1_marshalling() {
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-4051: .aai/scripts/aai-update.ps1 does not exist"
  local problems
  problems="$(ps1_problems "$PS1_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-4051: $problems"
  need_tool TEST-4051 pwsh || return 0
  local work got
  work="$(new_own_scratch ps1-marshal)"
  cp "$PS1_LAUNCHER" "$work/launcher.ps1"
  printf '%s\n' 'console.log(JSON.stringify(process.argv.slice(2)));' > "$work/aai-update.mjs"
  check_marshal() {
    local label="$1" want="$2" mode="$3"
    shift 3
    got="$(marshal_json "$work" "$mode" "$@" 2>&1)" || { printf '%s\n' "$got" >&2; log_fail "TEST-4051: $label: the launcher run failed"; }
    [[ "$got" == "$want" ]] || log_fail "TEST-4051: $label: the module received $got, expected $want"
  }
  check_marshal "-DryRun:false in session" '[]' session '-DryRun:$false'
  check_marshal "-DryRun:true in session" '["-DryRun"]' session '-DryRun:$true'
  check_marshal "-Force then -DryRun:false in session" '["-Force"]' session '-Force -DryRun:$false'
  check_marshal "-Repo:X in session" '["-Repo","X"]' session '-Repo:X'
  check_marshal "an array value in session" '["-Repo","a,b"]' session '-Repo:a,b'
  check_marshal "-Repo: X by -File" '["-Repo","X"]' file '-Repo:' X
  got="$(marshal_json "$work" file '-DryRun:true' -Repo:X 2>&1)" || log_fail "TEST-4051: the -File run failed"
  case "$got" in *':"'* | *':,'* | *'"true"'* | *'"false"'*) log_fail "TEST-4051: -File run left a bare boolean word or a trailing colon: $got" ;; esac
  safe_rm_own "$work"
  log_pass "TEST-4051: the update launcher drops a false switch, a true boolean, a trailing colon and joins an array, in session and by -File, and stays within 20 ASCII lines"
}

# amend_found <list json> <spec id fragment> <what prefix>: prints found or missing for a contract record of ref update-on-node.
# The list goes in on stdin: as one argument it outgrows the 128 KiB Linux limit on a single argv string.
amend_found() {
  node -e '
    const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const hit = d.items.filter((i) => i.ref_id === "update-on-node" && i.amendment_class === "contract" && i.spec.includes(process.argv[1]) && i.what.startsWith(process.argv[2]));
    process.stdout.write(hit.length >= 1 ? "found" : "missing");
  ' "$2" "$3" <<<"$1"
}

test_3974_rehomed_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3974: tests/skills/aai-update.Tests.ps1 does not exist"
  local id
  # the five retired cases are gone by name, the robustness, TEST-009 and TEST-3584 edits are present
  for id in 'TEST-006:' 'TEST-007:' 'TEST-3587:' 'TEST-3588:' 'TEST-3589:'; do
    if /usr/bin/grep -qF "'$id" "$PESTER_FILE"; then log_fail "TEST-3974: the Pester file still holds the retired case $id"; fi
  done
  /usr/bin/grep -qF "Unknown argument: --bogus" "$PESTER_FILE" || log_fail "TEST-3974: the robustness case does not expect 'Unknown argument: --bogus'"
  /usr/bin/grep -qF -e "-Filter 'aai-src.*'" "$PESTER_FILE" || log_fail "TEST-3974: TEST-009 does not filter aai-src.*"
  if /usr/bin/grep -qF "aai-src-" "$PESTER_FILE"; then log_fail "TEST-3974: the Pester file still names the old aai-src- prefix"; fi
  /usr/bin/grep -qF "TEST-3584: the launcher" "$PESTER_FILE" || log_fail "TEST-3974: TEST-3584 does not check the launcher"
  # the contract records and the two closed follow-ups
  local json verdict
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3974: spec-amend list failed"
  verdict="$(amend_found "$json" "SPEC-0052-" "TEST-006, TEST-007, TEST-009 and the robustness case re-homed")"
  [[ "$verdict" == found ]] || log_fail "TEST-3974: no second SPEC-0052 contract record of ref update-on-node"
  verdict="$(amend_found "$json" "SPEC-0285-" "TEST-3584, TEST-3587, TEST-3588 and TEST-3589 re-homed")"
  [[ "$verdict" == found ]] || log_fail "TEST-3974: no SPEC-0285 contract record of ref update-on-node"
  node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status all --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl" > "$TEST_DIR/follow-ups.json" || log_fail "TEST-3974: follow-ups list failed"
  for id in fu-update-test-3589-isolation fu-update-missing-git-msg; do
    verdict="$(node -e '
      const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const f = d.items.find((i) => i.id === process.argv[2]);
      process.stdout.write(f && f.closed === true ? "closed" : "not closed");
    ' "$TEST_DIR/follow-ups.json" "$id")"
    [[ "$verdict" == closed ]] || log_fail "TEST-3974: follow-up $id is $verdict"
  done
  need_tool TEST-3974 pwsh || return 0
  local work counts
  work="$(new_own_scratch pester-whole)"
  counts="$(run_pester TEST-3974 "$work")"
  [[ "$counts" =~ ^PESTER\ passed=([0-9]+)\ skipped=0\ failed=0\ containers=0$ && "${BASH_REMATCH[1]}" -ge 1 ]] || { cat "$work/pester.log" >&2; log_fail "TEST-3974: Pester summary '$counts', expected passes with 0 skips, 0 failures and 0 failed containers"; }
  safe_rm_own "$work"
  log_pass "TEST-3974: aai-update.Tests.ps1 passes whole under Invoke-Pester with 0 skips, 0 failures and 0 failed containers; the five retired cases are gone, the three edits are present, both contract records exist and both follow-ups are closed"
}

test_3975_parity_update() {
  need_tool TEST-3975 pwsh || return 0
  need_tool TEST-3975 git || return 0
  local work out rc=0 json verdict
  work="$(new_own_scratch parity-update)"
  env -u AAI_ROLE -u AAI_GIT_WRITE node "$PARITY_DRIVER" run --matrix full --twins sh,ps1,node --scenario UP-01 --scenario UP-02 --scenario UP-03 --json "$work/up.json" > "$work/up.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/up.out" >&2; log_fail "TEST-3975: the driver run over UP-01 to UP-03 exited $rc"; }
  verdict="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    if (r.verdict !== "PASS") bad.push("verdict " + r.verdict);
    for (const id of ["UP-01", "UP-02", "UP-03"]) {
      const s = r.scenarios.find((x) => x.id === id);
      if (!s) { bad.push(id + " missing"); continue; }
      const twins = [...new Set(s.steps.map((x) => x.twin))].sort().join(",");
      if (twins !== "node,ps1,sh") bad.push(id + " ran twins " + twins);
      const pairs = [...new Set(s.divergences.map((d) => d.pair))].filter((p) => p !== "sh:ps1" && p !== "sh:node");
      if (pairs.length) bad.push(id + " divergence pairs " + pairs.join(","));
      if (s.divergences.some((d) => d.pair === "sh:node")) bad.push(id + " has a sh:node divergence");
    }
    const up = r.pairs.filter((p) => p.split(":")[0] !== p.split(":")[1]).sort().join(" ");
    if (up !== "sh:node sh:ps1") bad.push("pairs " + up);
    process.stdout.write(bad.length ? bad.join("; ") : "ok");
  ' "$work/up.json")" || log_fail "TEST-3975: cannot read the driver report"
  [[ "$verdict" == ok ]] || { cat "$work/up.out" >&2; log_fail "TEST-3975: $verdict"; }
  # node only on update, bootstrap, hooks and (since sync-on-node run 6c) sync scenarios
  verdict="$(AAI_PARITY_DRIVER_PATH="$PARITY_DRIVER" node --input-type=module -e '
    const m = await import(process.env.AAI_PARITY_DRIVER_PATH);
    const bad = m.SCENARIOS.filter((s) => m.twinsFor([m.TWINS.node], s).length > 0 && s.op !== "update" && s.op !== "bootstrap" && s.op !== "hooks" && s.op !== "sync").map((s) => s.id);
    process.stdout.write(bad.length ? "node runs " + bad.join(",") : "ok");
  ')"
  [[ "$verdict" == ok ]] || log_fail "TEST-3975: $verdict"
  run_node_tests TEST-3975 "$PARITY_TEST"
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json --ledger "$PROJECT_ROOT/docs/ai/decisions.jsonl")" || log_fail "TEST-3975: spec-amend list failed"
  verdict="$(amend_found "$json" "SPEC-0284-" "D-SEAM gains the twin peers field")"
  [[ "$verdict" == found ]] || log_fail "TEST-3975: no SPEC-0284 contract record of ref update-on-node"
  safe_rm_own "$work"
  log_pass "TEST-3975: the parity driver passes UP-01 to UP-03 with twins sh, ps1 and node on pairs sh:ps1 and sh:node only, without a sh:node divergence; the peers rule, the real-registry argv and the widened row hold; the SPEC-0284 record exists"
}

# --- run 7: scratch install, wiring and docs (TEST-3976, TEST-3977) -----------------------------
FIXTURES_MOD="$PROJECT_ROOT/tests/skills/lib/aai-update-fixtures.mjs"

# tree_listing <dir>: a sorted listing of every entry below dir (names only), for the unchanged-target checks.
tree_listing() {
  find "$1" | LC_ALL=C sort
}

# run_update <dir> <work> <shell> <source>: the one place this suite runs a real update. It refuses a source outside
# the run's own scratch root or a non-empty gh config, then runs the launcher in dir with the closed-network
# environment of D-SAFETY (file protocol only, empty gh config, no tokens, a failing gh stub first on PATH).
run_update() {
  local dir="$1" work="$2" shell="$3" src="$4"
  [[ -n "$work" && -d "$work" ]] || log_fail "run_update: no scratch root"
  case "$src" in "$work"/*) ;; *) log_fail "run_update: repo $src lies outside the scratch root $work" ;; esac
  [[ -d "$work/ghcfg" && -z "$(ls -A "$work/ghcfg")" ]] || log_fail "run_update: GH_CONFIG_DIR $work/ghcfg is missing or not empty"
  cd "$dir" || return 1
  case "$shell" in
    pwsh) set -- pwsh -NoProfile -File .aai/scripts/aai-update.ps1 -Repo "$src" -Force ;;
    *) set -- "$shell" .aai/scripts/aai-update.sh --repo "$src" --force ;;
  esac
  env -u AAI_ROLE -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
    PATH="$work/ghbin:$PATH" GIT_ALLOW_PROTOCOL=file GH_CONFIG_DIR="$work/ghcfg" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig" "$@"
}

test_3976_scratch_install() {
  need_tool TEST-3976 git || return 0
  local work target runp src shells shell sh out rc before after fakebin
  work="$(new_own_scratch install)"
  target="$work/target"
  mkdir -p "$target"
  git -C "$target" init -q
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$target" --profile core > "$work/sync.log" 2>&1 || { cat "$work/sync.log" >&2; log_fail "TEST-3976: aai-sync.sh --profile core failed"; }
  for out in aai-update.mjs aai-update.ps1 aai-update.sh; do
    [[ -f "$target/.aai/scripts/$out" ]] || log_fail "TEST-3976: the core sync did not vendor .aai/scripts/$out"
  done
  # a fixture source whose two sync stubs write the same files; never this checkout (D-SAFETY)
  src="$work/source"
  mkdir -p "$src" "$work/ghbin" "$work/ghcfg"
  node --input-type=module -e '
    const m = await import(process.argv[1]);
    const fs = await import("node:fs");
    m.buildSource(process.argv[2], { head: "main", helperReal: fs.readFileSync(process.argv[3], "utf8"), env: process.env });
  ' "file://$FIXTURES_MOD" "$src" "$PROJECT_ROOT/.aai/scripts/update-doctor-report.mjs" || log_fail "TEST-3976: cannot build the fixture source"
  printf '%s\n' '#!/bin/sh' 'echo "gh stub: the network is closed in this suite" >&2' 'exit 1' > "$work/ghbin/gh"
  chmod 755 "$work/ghbin/gh"
  : > "$work/gitconfig"
  # three fresh copies at one path, one after another; each run's tree is kept for the comparison
  runp="$work/run/target"
  shells="bash sh"
  need_tool TEST-3976 pwsh && shells="$shells pwsh"
  for shell in $shells; do
    mkdir -p "$work/run"
    cp -R "$target" "$runp"
    rc=0
    ( run_update "$runp" "$work" "$shell" "$src" ) > "$work/$shell.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/$shell.log" >&2; log_fail "TEST-3976: the $shell launcher exited $rc"; }
    mv "$work/run" "$work/out-$shell"
  done
  # equal normalized trees
  out="$(node --input-type=module -e '
    const m = await import(process.argv[1]);
    const names = process.argv.slice(3);
    const base = process.argv[2];
    const bad = [];
    for (let i = 1; i < names.length; i += 1) {
      const d = m.compareTrees(base + "/out-" + names[0] + "/target", base + "/out-" + names[i] + "/target", { pair: names[0] + ":" + names[i] });
      for (const x of d) bad.push(x.pair + " " + x.kind + " " + x.path + ": " + x.detail);
    }
    process.stdout.write(bad.join("\n"));
  ' "file://$PARITY_DRIVER" "$work" $shells)" || log_fail "TEST-3976: the tree comparison failed to run"
  [[ -z "$out" ]] || log_fail "TEST-3976: the launcher trees differ: $out"
  # without node on PATH sh refuses and the target is unchanged
  fakebin="$work/only-dirname"
  mkdir -p "$fakebin" "$work/run"
  ln -s "$(command -v dirname)" "$fakebin/dirname"
  cp -R "$target" "$runp"
  sh="$(command -v sh)"
  before="$(tree_listing "$runp")"
  rc=0
  ( cd "$runp" && env PATH="$fakebin" "$sh" .aai/scripts/aai-update.sh --dry-run ) 2> "$work/refuse.err" > /dev/null || rc=$?
  out="$(cat "$work/refuse.err")"
  [[ "$rc" == 1 ]] || log_fail "TEST-3976: sh without node exited $rc, expected 1"
  [[ "$out" == "$REFUSAL_LINE" ]] || log_fail "TEST-3976: sh without node wrote: $out"
  after="$(tree_listing "$runp")"
  [[ "$before" == "$after" ]] || log_fail "TEST-3976: the target changed after the refusal"
  safe_rm_own "$work"
  log_pass "TEST-3976: a core sync vendors the module and both launchers, bash, sh and pwsh runs against a fixture source leave equal trees, sh without node refuses with one line and leaves the tree unchanged"
}

test_3977_wiring() {
  local work f out rc sel
  work="$(new_own_scratch wiring)"
  # the order keeps a name ending in sh from standing before another updater name (the D-SAFETY line scan)
  for f in .aai/scripts/aai-update.mjs .aai/scripts/aai-update.ps1 tests/fixtures/aai-update-reference/aai-update.ps1 .aai/scripts/aai-update.sh \
    tests/skills/lib/aai-update.test.mjs tests/fixtures/aai-update-reference/aai-update.sh tests/skills/aai-update.Tests.ps1; do
    printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - > "$work/sel.out" 2>&1 || true
    qgrep -q "^SELECTED aai-update-node " < "$work/sel.out" || { cat "$work/sel.out" >&2; log_fail "TEST-3977: select-suites does not route $f to aai-update-node"; }
  done
  # every suite-map row that names aai-update.sh names aai-update.mjs
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    let row = ""; const rows = {};
    for (const l of lines) {
      const m = /^  ([a-z0-9-]+):$/.exec(l);
      if (m) { row = m[1]; rows[row] = []; }
      else if (row && /^      - /.test(l)) rows[row].push(l.replace(/^      - /, ""));
    }
    const bad = [];
    for (const [k, v] of Object.entries(rows)) {
      if (v.includes(".aai/scripts/aai-update.sh") && !v.includes(".aai/scripts/aai-update.mjs")) bad.push(k);
    }
    process.stdout.write(bad.join(","));
  ' "$PROJECT_ROOT/tests/skills/suite-map.yaml")" || log_fail "TEST-3977: cannot read suite-map.yaml"
  [[ -z "$out" ]] || log_fail "TEST-3977: suite-map rows name aai-update.sh but not aai-update.mjs: $out"
  # the weights row and its fallback line
  qgrep -qE "^# sample aai-update-node (measured|fallback unsampled)" < "$PROJECT_ROOT/tests/skills/suite-weights.tsv" \
    || log_fail "TEST-3977: the weights sample line for aai-update-node is missing"
  [[ "$(awk -F'\t' '$1=="aai-update-node" && $2 ~ /^[1-9][0-9]*$/ {c++} END{print c+0}' "$PROJECT_ROOT/tests/skills/suite-weights.tsv")" == 1 ]] || log_fail "TEST-3977: suite-weights does not hold exactly one positive-integer row for aai-update-node"
  for sel in "test-aai-hygiene-pack.sh test_090_suite_map_pin" "test-aai-hygiene-pack.sh test_129_mutation_gate_suite_registration" "test-aai-win-fallback.sh test_034" "test-aai-win-fallback.sh test_035"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-3977: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  rc=0
  node "$SCRIPT_DIR/lib/nested-suite-lint.mjs" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" > "$work/lint.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/lint.log" >&2; log_fail "TEST-3977: nested-suite-lint exited $rc"; }
  for f in check-cd-subshell-leak.mjs check-vendored-script-deps.mjs; do
    rc=0
    node "$PROJECT_ROOT/.aai/scripts/$f" > "$work/chk.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-3977: $f exited $rc"; }
  done
  rc=0
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" > "$work/chk.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-3977: check-test-registration.mjs exited $rc"; }
  qgrep -qxF "$(printf '1\t.aai/scripts/aai-update.sh')" < "$SCRIPT_DIR/lib/cd-subshell-leak-baseline.tsv" || log_fail "TEST-3977: the cd-subshell baseline does not hold 1 for .aai/scripts/aai-update.sh"
  qgrep -qxF "  - .aai/scripts/aai-update.mjs" < "$PROJECT_ROOT/.aai/system/PROFILES.yaml" || log_fail "TEST-3977: PROFILES.yaml core does not list .aai/scripts/aai-update.mjs"
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
      for (const w of [".aai/scripts/aai-update.mjs", "tests/fixtures/aai-update-reference/**", "tests/skills/lib/update-reference.mjs"]) {
        if (!lists[0].includes(w)) bad.push("the push list lacks " + w);
        if (!lists[1].includes(w)) bad.push("the pull_request list lacks " + w);
      }
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/.github/workflows/ps1-quality.yml")"
  [[ -z "$out" ]] || log_fail "TEST-3977: ps1-quality.yml: $out"
  safe_rm_own "$work"
  log_pass "TEST-3977: select-suites routes every updater file to the suite, every row naming aai-update.sh names aai-update.mjs, the weights row and fallback line hold, test_090, test_129, test_034 and test_035 pass, the lint and checks exit 0, the baseline holds 1, PROFILES core lists the module, both ps1-quality path lists are identical and hold the D-WIRE entries"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3960..3977, grows run by run)"
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
  test_3969_corpus_bash
  test_3970_corpus_powershell
  test_3971_sh_launcher
  test_3973_rehomed_bash_suites
  test_3972_ps1_launcher
  test_3974_rehomed_pester
  test_3975_parity_update
  test_3976_scratch_install
  test_3977_wiring
  test_4050_colon_grammar
  test_4051_ps1_marshalling
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
