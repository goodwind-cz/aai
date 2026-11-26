#!/usr/bin/env bash
#
# Test: aai-bootstrap-node
# (docs/specs/SPEC-0306-spec-bootstrap-on-node.md, TEST-3940..3959; this file grows run by run)
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
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/aai-bootstrap.Tests.ps1"
PARITY_DRIVER="$PROJECT_ROOT/tests/skills/lib/install-parity.mjs"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
REFUSED="aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run."

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

test_3946_rendering() {
  run_node_tests TEST-3946
  log_pass "TEST-3946: skills, marker, indices and summary equal the bytes captured from the reference, the fence rule, the empty extra block, the fallback lines, the CI/CD join"
}

test_3947_writes_and_conflicts() {
  run_node_tests TEST-3947
  log_pass "TEST-3947: managed marks, conflicts with exit 1 before any write, force, unchanged after trailing newlines, dry-run, write order, a NUL byte file rewritten"
}

test_3948_gitignore() {
  run_node_tests TEST-3948
  log_pass "TEST-3948: cache and runtime-sidecar patterns, CR handling, one marker, dry-run count line, missing list line, no dependency on gitignore-block.sh"
}

test_3949_corpus_masked() {
  need_tool TEST-3949 bash || return 0
  need_tool TEST-3949 git || return 0
  run_node_tests TEST-3949
  log_pass "TEST-3949: K01 to K27 and K38 in masked mode equal the reference in exit, stdout, stderr and tree, with no container call in any stub log"
}

test_3950_hooks_overlay() {
  run_node_tests TEST-3950
  log_pass "TEST-3950: every hooks overlay branch on scratch roots, file bytes before and after a refusal, exit codes 0 and 3, no settings.json without the flag"
}

test_3951_platform_record() {
  run_node_tests TEST-3951
  log_pass "TEST-3951: an injected child result with exit 0, 6, 1 and 4 gives the relayed or failed text, the dry-run flag reaches the argv, the run exit code is unchanged"
}

test_3952_corpus_full() {
  need_tool TEST-3952 bash || return 0
  need_tool TEST-3952 git || return 0
  run_node_tests TEST-3952
  log_pass "TEST-3952: K01 to K38 in full mode equal the reference, platform stub lines only for K35 to K37, no container call"
}

# launcher_problems <file>: prints the problems of the .sh launcher text (empty when clean): the D-LAUNCH text, at most
# 20 lines, ASCII, no policy token.
launcher_problems() {
  node -e '
    const fs = require("fs");
    const buf = fs.readFileSync(process.argv[1]);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 9))) bad.push("non-ASCII or control byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    if (s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
    if (s.includes("[[") || s.includes("BASH_SOURCE")) bad.push("holds a bash-only construct");
    if (!s.includes(process.argv[2])) bad.push("lacks the refusal line");
    if (!s.includes("exec node \"$MODULE\" \"$@\"")) bad.push("does not exec node on the module with all arguments");
    for (const w of ["package.json", "AAI-DYNAMIC", "aai-test-", "gitignore", "settings-hooks", "platform", "playwright", "pyproject", "RUNTIME_IGNORE", ".claude", ".codex", ".gemini", "docs/ai"]) {
      if (s.includes(w)) bad.push("holds the policy token " + w);
    }
    process.stdout.write(bad.join("; "));
  ' "$1" "$REFUSED"
}

# tree_listing <dir>: a sorted listing of every entry below dir (names only), for the unchanged-target checks.
tree_listing() {
  node -e 'const fs=require("fs");process.stdout.write(fs.readdirSync(process.argv[1],{recursive:true}).map(String).sort().join("\n"));' "$1"
}

test_3953_sh_launcher() {
  local problems work bin target out rc sh shells shell expected mode
  problems="$(launcher_problems "$SH_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-3953: the launcher: $problems"
  [[ -x "$SH_LAUNCHER" ]] || log_fail "TEST-3953: the launcher is not executable"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/aai-bootstrap.sh 2>/dev/null | cut -d' ' -f1 || true)"
  [[ -z "$mode" || "$mode" == "100755" ]] || log_fail "TEST-3953: the launcher mode in the index is $mode, expected 100755"
  # a copy beside a stub module: every argument and the exit code pass through, under each shell
  work="$(new_own_scratch launcher)"
  bin="$work/bin"
  mkdir -p "$bin"
  cp "$SH_LAUNCHER" "$bin/aai-bootstrap.sh"
  printf '%s\n' 'process.stdout.write(JSON.stringify(process.argv.slice(2)));' 'process.exit(7);' > "$bin/aai-bootstrap.mjs"
  target="$work/tar get"
  mkdir -p "$target"
  expected='["'"$target"'","--dry-run","--force","--with-claude-hooks","-h"]'
  shells="bash sh"
  need_tool TEST-3953 dash && shells="$shells dash"
  for shell in $shells; do
    sh="$(command -v "$shell")"
    rc=0
    out="$("$sh" "$bin/aai-bootstrap.sh" "$target" --dry-run --force --with-claude-hooks -h)" || rc=$?
    [[ "$rc" == 7 ]] || log_fail "TEST-3953: $shell: exit $rc, expected 7"
    [[ "$out" == "$expected" ]] || log_fail "TEST-3953: $shell: arguments were not passed through: $out"
  done
  # without node on PATH, and with the module missing: exit 1, the one refusal line, the target unchanged
  mkdir -p "$work/only-dirname" "$work/nomodule"
  ln -s "$(command -v dirname)" "$work/only-dirname/dirname"
  cp "$SH_LAUNCHER" "$work/nomodule/aai-bootstrap.sh"
  local before after
  before="$(tree_listing "$target")"
  for shell in $shells; do
    sh="$(command -v "$shell")"
    rc=0
    out="$(env PATH="$work/only-dirname" "$sh" "$bin/aai-bootstrap.sh" "$target" 2>&1 >/dev/null)" || rc=$?
    [[ "$rc" == 1 ]] || log_fail "TEST-3953: $shell without node: exit $rc, expected 1"
    [[ "$out" == "$REFUSED" ]] || log_fail "TEST-3953: $shell without node: stderr was: $out"
    rc=0
    out="$("$sh" "$work/nomodule/aai-bootstrap.sh" "$target" 2>&1 >/dev/null)" || rc=$?
    [[ "$rc" == 1 ]] || log_fail "TEST-3953: $shell without the module: exit $rc, expected 1"
    [[ "$out" == "$REFUSED" ]] || log_fail "TEST-3953: $shell without the module: stderr was: $out"
  done
  after="$(tree_listing "$target")"
  [[ "$before" == "$after" ]] || log_fail "TEST-3953: the target changed after a refusal"
  # PROFILES core lists the module
  awk '$0 == "core:" { f = 1; next } /^[^ ]/ { f = 0 } f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }' "$PROFILES" > "$work/core.list"
  qgrep -qxF ".aai/scripts/aai-bootstrap.mjs" < "$work/core.list" || log_fail "TEST-3953: PROFILES core does not list .aai/scripts/aai-bootstrap.mjs"
  qgrep -qxF ".aai/scripts/aai-bootstrap.sh" < "$work/core.list" || log_fail "TEST-3953: PROFILES core no longer lists .aai/scripts/aai-bootstrap.sh"
  safe_rm_own "$work"
  log_pass "TEST-3953: the .sh launcher is the D-LAUNCH text, passes arguments and exit 7 through bash, sh and dash, refuses without node or module with one line and no write, PROFILES core lists the module"
}

# amendment_problems: the SPEC-0157 and SPEC-0029 contract records of ref bootstrap-on-node, read from spec-amend list --json.
amendment_problems() {
  # the list JSON is large (hundreds of KiB): a scratch file, not a pipe into node (hosted run 45249052651 crashed node on that pipe)
  local jf
  jf="$(mktemp "${TMPDIR:-/tmp}/aai-amend-list.XXXXXX")"
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$jf" || { rm -f "$jf"; echo "spec-amend list failed"; return 0; }
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const want = [
      ["spec-aai-update-gitignore-drift-reconcile", "TEST-011, TEST-016, TEST-017, TEST-019 and TEST-020 re-homed"],
      ["spec-hook-enforced-gates", "TEST-010 re-homed"],
    ];
    const bad = [];
    for (const [spec, what] of want) {
      const hits = j.items.filter((i) => i.ref_id === "bootstrap-on-node" && i.spec_id === spec && i.amendment_class === "contract");
      if (hits.length !== 1) bad.push(spec + ": " + hits.length + " contract records of ref bootstrap-on-node, expected 1");
      else if (!hits[0].what.startsWith(what)) bad.push(spec + ": the record does not begin with " + what);
    }
    process.stdout.write(bad.join("; "));
  ' "$jf"
  rm -f "$jf"
}

test_3954_rehomed_suites() {
  local problems sel rc
  for sel in "test-aai-bootstrap.sh test_gitignore_seed_uses_shared_library" \
    "test-aai-hooks-overlay.sh test_010_bootstrap_wiring" "test-aai-hooks-overlay.sh test_011_bootstrap_behavior" \
    "test-aai-sync-seed.sh test_single_bash_reader_and_sourcing" "test-aai-sync-seed.sh test_runtime_ignore_header_consumer_accuracy" \
    "test-aai-sync-seed.sh test_bootstrap_survives_missing_library" "test-aai-sync-seed.sh test_marker_prefix_pinned_across_call_sites"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } >"$TEST_DIR/rehome.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$TEST_DIR/rehome.log" >&2; log_fail "TEST-3954: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  problems="$(amendment_problems)"
  [[ -z "$problems" ]] || log_fail "TEST-3954: $problems"
  log_pass "TEST-3954: the re-homed selectors of the bootstrap, hooks-overlay and sync-seed suites pass against the launcher, and the SPEC-0157 and SPEC-0029 amendment records exist"
}

# ps1_problems <file>: prints the problems of the .ps1 launcher text (empty when clean).
ps1_problems() {
  node -e '
    const fs = require("fs");
    const buf = fs.readFileSync(process.argv[1]);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII or control byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    if (/param\s*\(/i.test(s)) bad.push("holds a param block");
    if (!s.includes(process.argv[2])) bad.push("lacks the refusal line");
    if (!s.includes("exit $LASTEXITCODE")) bad.push("does not end with the module exit code");
    if (!s.includes("& node $Module @args")) bad.push("does not pass every argument to node");
    for (const w of ["package.json", "AAI-DYNAMIC", "aai-test-", "gitignore", "settings-hooks", "platform", "playwright", "pyproject", "RUNTIME_IGNORE", ".claude", ".codex", ".gemini", "docs/ai"]) {
      if (s.includes(w)) bad.push("holds the policy token " + w);
    }
    process.stdout.write(bad.join("; "));
  ' "$1" "$REFUSED"
}

# amendment_check <spec id> <what prefix>: empty when exactly one contract record of ref bootstrap-on-node for that spec begins with the text.
amendment_check() {
  local jf
  jf="$(mktemp "${TMPDIR:-/tmp}/aai-amend-list.XXXXXX")"
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$jf" || { rm -f "$jf"; echo "spec-amend list failed"; return 0; }
  AMEND_JF="$jf" node -e '
    const j = JSON.parse(require("fs").readFileSync(process.env.AMEND_JF, "utf8"));
    const hits = j.items.filter((i) => i.ref_id === "bootstrap-on-node" && i.spec_id === process.argv[1] && i.amendment_class === "contract");
    if (hits.length !== 1) process.stdout.write(process.argv[1] + ": " + hits.length + " contract records of ref bootstrap-on-node, expected 1");
    else if (!hits[0].what.startsWith(process.argv[2])) process.stdout.write(process.argv[1] + ": the record does not begin with " + process.argv[2]);
  ' "$1" "$2"
  rm -f "$jf"
}

test_3955_ps1_launcher() {
  local problems work out rc=0 counts
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-3955: .aai/scripts/aai-bootstrap.ps1 does not exist"
  problems="$(ps1_problems "$PS1_LAUNCHER")"
  [[ -z "$problems" ]] || log_fail "TEST-3955: the launcher: $problems"
  work="$(new_own_scratch ps1)"
  awk '$0 == "core:" { f = 1; next } /^[^ ]/ { f = 0 } f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }' "$PROFILES" > "$work/core.list"
  qgrep -qxF ".aai/scripts/aai-bootstrap.ps1" < "$work/core.list" || log_fail "TEST-3955: PROFILES core does not list .aai/scripts/aai-bootstrap.ps1"
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-validate-skills.sh" test_3201_required_and_first_missing >"$work/vs.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/vs.log" >&2; log_fail "TEST-3955: test_3201_required_and_first_missing exited $rc"; }
  out="$(amendment_check spec-node-first-small-pairs "TEST-3201 REQUIRED grows")"
  [[ -z "$out" ]] || log_fail "TEST-3955: $out"
  node --input-type=module -e '
    const m = await import(process.argv[1] + "/.aai/scripts/validate-skills.mjs");
    const r = m.REQUIRED; const n = r.length;
    if (r[n - 2] !== ".aai/scripts/aai-bootstrap.mjs" || r[n - 1] !== ".aai/scripts/aai-bootstrap.ps1") { console.error("REQUIRED ends with " + r.slice(-2).join(", ")); process.exit(1); }
  ' "$PROJECT_ROOT" || log_fail "TEST-3955: validate-skills REQUIRED does not end with aai-bootstrap.mjs and aai-bootstrap.ps1"
  if need_tool TEST-3955 pwsh; then
    ( cd "$PROJECT_ROOT" && env -u AAI_ROLE pwsh -NoProfile -NonInteractive -Command '
      Import-Module Pester -MinimumVersion 5.0
      $r = Invoke-Pester -Path "tests/skills/aai-bootstrap.Tests.ps1" -PassThru -Output None
      Write-Output ("PESTER passed=" + $r.PassedCount + " skipped=" + $r.SkippedCount + " failed=" + $r.FailedCount + " containers=" + $r.FailedContainersCount)
    ' ) > "$work/pester.log" 2>&1 || { cat "$work/pester.log" >&2; log_fail "TEST-3955: Invoke-Pester did not run"; }
    out="$(cat "$work/pester.log")"
    counts="$(printf '%s\n' "$out" | tail -n 1)"
    [[ "$counts" =~ ^PESTER\ passed=([0-9]+)\ skipped=([0-9]+)\ failed=([0-9]+)\ containers=([0-9]+)$ ]] || log_fail "TEST-3955: unreadable Pester summary: $out"
    [[ "${BASH_REMATCH[1]}" -ge 4 && "${BASH_REMATCH[2]}" == 0 && "${BASH_REMATCH[3]}" == 0 && "${BASH_REMATCH[4]}" == 0 ]] || log_fail "TEST-3955: Pester summary $counts, expected at least 4 passed and 0 skipped, 0 failed, 0 failed containers"
  fi
  safe_rm_own "$work"
  log_pass "TEST-3955: the .ps1 launcher is the D-LAUNCH text, PROFILES core lists it, validate-skills REQUIRED ends with the module and the launcher, the SPEC-0265 record exists, Pester passes"
}

# driver_run <report file> <args...>: the parity driver in this suite's environment; prints its stdout, returns its exit code.
driver_run() {
  local rep="$1"
  shift
  env -u AAI_ROLE -u AAI_GIT_WRITE node "$PARITY_DRIVER" run "$@" --json "$rep"
}

test_3956_parity_bootstrap() {
  need_tool TEST-3956 pwsh || return 0
  need_tool TEST-3956 git || return 0
  local work out rc=0 sel
  work="$(new_own_scratch parity)"
  sel="--scenario BS-01 --scenario BS-02 --scenario BS-03 --scenario BS-04 --scenario BS-05 --scenario BS-06 --scenario BS-07 --scenario BS-08 --scenario BS-09"
  # shellcheck disable=SC2086
  driver_run "$work/bs.json" --matrix full --twins sh,ps1,node $sel > "$work/bs.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/bs.out" >&2; log_fail "TEST-3956: the driver run over BS-01 to BS-09 exited $rc"; }
  out="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    if (r.verdict !== "PASS") bad.push("verdict " + r.verdict);
    for (let n = 1; n <= 9; n += 1) {
      const id = "BS-0" + n;
      const s = r.scenarios.find((x) => x.id === id);
      if (!s) { bad.push(id + " missing"); continue; }
      const twins = [...new Set(s.steps.map((x) => x.twin))].sort().join(",");
      if (twins !== "node,ps1,sh") bad.push(id + " ran twins " + twins);
    }
    for (const p of ["sh:ps1", "sh:node", "ps1:node"]) if (!r.pairs.includes(p)) bad.push("pair " + p + " missing");
    for (const p of ["sh:sh", "ps1:ps1", "node:node"]) if (!r.pairs.includes(p)) bad.push("self pair " + p + " missing (BS-03)");
    const bs3 = r.scenarios.find((x) => x.id === "BS-03");
    if (bs3 && bs3.steps.filter((x) => x.twin === "node").length !== 2) bad.push("BS-03 has no two node steps");
    if (r.uncovered.length || r.stale.length) bad.push("uncovered or stale rows");
    process.stdout.write(bad.join("; "));
  ' "$work/bs.json")"
  [[ -z "$out" ]] || { cat "$work/bs.out" >&2; log_fail "TEST-3956: $out"; }
  # the node twin runs the sync scenarios too since sync-on-node run 6c (bootstrap, update, hooks and sync)
  rc=0
  driver_run "$work/sy.json" --matrix smoke --twins sh,ps1,node --scenario SY-01 > "$work/sy.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/sy.out" >&2; log_fail "TEST-3956: the SY-01 run exited $rc"; }
  out="$(node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const twins = [...new Set(r.scenarios[0].steps.map((x) => x.twin))].sort().join(",");
    process.stdout.write(twins === "node,ps1,sh" ? "" : "SY-01 ran twins " + twins);
  ' "$work/sy.json")"
  [[ -z "$out" ]] || log_fail "TEST-3956: $out"
  run_node_tests TEST-3956
  # a module twin that appends one byte to the marker fails, naming its pair and the path
  cat > "$work/skew-wrapper.mjs" <<'EOS'
import { spawnSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import path from 'node:path';
const [mod, target, ...flags] = process.argv.slice(2);
const r = spawnSync(process.execPath, [mod, target, ...flags], { stdio: 'inherit' });
appendFileSync(path.join(target, '.claude', 'skills', 'AAI_DYNAMIC_SKILLS.md'), 'x');
process.exit(r.status ?? 1);
EOS
  cat > "$work/skew.mjs" <<EOS
import path from 'node:path';
export default {
  argv(step, ctx) {
    return { file: process.execPath, args: ['$work/skew-wrapper.mjs', path.join(ctx.bsref, '.aai', 'scripts', 'aai-bootstrap.mjs'), ctx.target], cwd: ctx.target };
  },
};
EOS
  rc=0
  driver_run "$work/skew.json" --matrix smoke --twins sh --twin-module "skew=$work/skew.mjs" --scenario BS-01 > "$work/skew.out" 2>&1 || rc=$?
  [[ "$rc" == 1 ]] || { cat "$work/skew.out" >&2; log_fail "TEST-3956: the skewed module twin run exited $rc, expected 1"; }
  qgrep -qF "UNCOVERED BS-01 sh:skew" < "$work/skew.out" || { cat "$work/skew.out" >&2; log_fail "TEST-3956: the skew run does not name the pair sh:skew"; }
  qgrep -qF ".claude/skills/AAI_DYNAMIC_SKILLS.md" < "$work/skew.out" || log_fail "TEST-3956: the skew run does not name the marker path"
  for sel in test_3560_matrix_tiers test_3562_normalizations; do
    rc=0
    env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-install-parity.sh" "$sel" > "$work/ip.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/ip.log" >&2; log_fail "TEST-3956: $sel exited $rc"; }
  done
  out="$(amendment_check spec-install-path-parity-harness "TEST-3560 and TEST-3562 widened")"
  [[ -z "$out" ]] || log_fail "TEST-3956: $out"
  safe_rm_own "$work"
  log_pass "TEST-3956: BS-01 to BS-09 pass with the sh, ps1 and node twins and the three pairs, the node twin stays on bootstrap scenarios, N5 and the DR-9 row hold, a skewed twin fails naming its pair, TEST-3560 and TEST-3562 pass, the SPEC-0284 record exists"
}

test_3957_scratch_install() {
  need_tool TEST-3957 git || return 0
  local work target runp shells shell sh out rc before after
  work="$(new_own_scratch install)"
  target="$work/target"
  mkdir -p "$target"
  git -C "$target" init -q
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$target" --profile core > "$work/sync.log" 2>&1 || { cat "$work/sync.log" >&2; log_fail "TEST-3957: aai-sync.sh --profile core failed"; }
  for out in aai-bootstrap.mjs aai-bootstrap.sh aai-bootstrap.ps1; do
    [[ -f "$target/.aai/scripts/$out" ]] || log_fail "TEST-3957: the core sync did not vendor .aai/scripts/$out"
  done
  # three fresh copies at one path, one after another; each run's tree is kept for the comparison
  runp="$work/run/target"
  shells="bash sh"
  need_tool TEST-3957 pwsh && shells="$shells pwsh"
  for shell in $shells; do
    mkdir -p "$work/run"
    cp -R "$target" "$runp"
    rc=0
    case "$shell" in
      bash) ( cd "$runp" && env -u AAI_ROLE bash .aai/scripts/aai-bootstrap.sh . ) > "$work/$shell.log" 2>&1 || rc=$? ;;
      sh) ( cd "$runp" && env -u AAI_ROLE sh .aai/scripts/aai-bootstrap.sh . ) > "$work/$shell.log" 2>&1 || rc=$? ;;
      pwsh) ( cd "$runp" && env -u AAI_ROLE pwsh -NoProfile -File .aai/scripts/aai-bootstrap.ps1 . ) > "$work/$shell.log" 2>&1 || rc=$? ;;
    esac
    [[ "$rc" == 0 ]] || { cat "$work/$shell.log" >&2; log_fail "TEST-3957: the $shell launcher exited $rc"; }
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
  ' "file://$PARITY_DRIVER" "$work" $shells)"
  [[ -z "$out" ]] || log_fail "TEST-3957: the launcher trees differ: $out"
  # without node on PATH sh refuses and the target is unchanged
  mkdir -p "$work/only-dirname" "$work/run"
  ln -s "$(command -v dirname)" "$work/only-dirname/dirname"
  cp -R "$target" "$runp"
  sh="$(command -v sh)"
  before="$(tree_listing "$runp")"
  rc=0
  ( cd "$runp" && env PATH="$work/only-dirname" "$sh" .aai/scripts/aai-bootstrap.sh . ) 2> "$work/refuse.err" > /dev/null || rc=$?
  out="$(cat "$work/refuse.err")"
  [[ "$rc" == 1 ]] || log_fail "TEST-3957: sh without node exited $rc, expected 1"
  [[ "$out" == "$REFUSED" ]] || log_fail "TEST-3957: sh without node wrote: $out"
  after="$(tree_listing "$runp")"
  [[ "$before" == "$after" ]] || log_fail "TEST-3957: the target changed after the refusal"
  safe_rm_own "$work"
  log_pass "TEST-3957: a core sync vendors the module and both launchers, bash, sh and pwsh runs leave equal trees, sh without node refuses with one line and leaves the tree unchanged"
}

test_3958_wiring() {
  local work f out rc sel
  work="$(new_own_scratch wiring)"
  for f in .aai/scripts/aai-bootstrap.mjs .aai/scripts/aai-bootstrap.sh .aai/scripts/aai-bootstrap.ps1 tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh \
    tests/skills/lib/aai-bootstrap.test.mjs tests/skills/aai-bootstrap.Tests.ps1; do
    printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - > "$work/sel.out" 2>&1 || true
    qgrep -q "^SELECTED aai-bootstrap-node " < "$work/sel.out" || { cat "$work/sel.out" >&2; log_fail "TEST-3958: select-suites does not route $f to aai-bootstrap-node"; }
  done
  # the weights row and its fallback line
  qgrep -qE "^# sample aai-bootstrap-node (measured|fallback unsampled)" < "$PROJECT_ROOT/tests/skills/suite-weights.tsv" \
    || log_fail "TEST-3958: the weights sample line for aai-bootstrap-node is missing"
  [[ "$(awk -F'\t' '$1=="aai-bootstrap-node" && $2 ~ /^[1-9][0-9]*$/ {c++} END{print c+0}' "$PROJECT_ROOT/tests/skills/suite-weights.tsv")" == 1 ]] || log_fail "TEST-3958: suite-weights does not hold exactly one positive-integer row for aai-bootstrap-node"
  for sel in "test-aai-hygiene-pack.sh test_090_suite_map_pin" "test-aai-hygiene-pack.sh test_129_mutation_gate_suite_registration" "test-aai-win-fallback.sh test_034"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-3958: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  rc=0
  node "$SCRIPT_DIR/lib/nested-suite-lint.mjs" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" > "$work/lint.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/lint.log" >&2; log_fail "TEST-3958: nested-suite-lint exited $rc"; }
  for f in check-cd-subshell-leak.mjs check-vendored-script-deps.mjs; do
    rc=0
    node "$PROJECT_ROOT/.aai/scripts/$f" > "$work/chk.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-3958: $f exited $rc"; }
  done
  rc=0
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" > "$work/chk.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$work/chk.log" >&2; log_fail "TEST-3958: check-test-registration.mjs exited $rc"; }
  qgrep -qxF "$(printf '1\t.aai/scripts/aai-bootstrap.sh')" < "$SCRIPT_DIR/lib/cd-subshell-leak-baseline.tsv" || log_fail "TEST-3958: the cd-subshell baseline does not hold 1 for .aai/scripts/aai-bootstrap.sh"
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
      for (const w of [".aai/scripts/aai-bootstrap.mjs", ".aai/scripts/aai-bootstrap.sh", "tests/fixtures/aai-bootstrap-reference/**"]) {
        if (!lists[0].includes(w)) bad.push("the push list lacks " + w);
        if (!lists[1].includes(w)) bad.push("the pull_request list lacks " + w);
      }
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/.github/workflows/ps1-quality.yml")"
  [[ -z "$out" ]] || log_fail "TEST-3958: ps1-quality.yml: $out"
  safe_rm_own "$work"
  log_pass "TEST-3958: select-suites routes every bootstrap file to the suite, the weights row and fallback line hold, test_090, test_129 and test_034 pass, the lint and checks exit 0, the baseline holds 1, both ps1-quality path lists are identical and hold the D-WIRE entries"
}

test_3959_docs() {
  local work out rc sel
  work="$(new_own_scratch docs)"
  out="$(node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // A release cut rolls "## [unreleased] \u2014 " into "## [vYYYY.MM.DD] \u2014 ", so the pin accepts both
    // (an unreleased-only pin rots at the first cut; the release dry-run CI job proves it).
    const head = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] \u2014 feat: project bootstrap runs on Node with a native Windows launcher$/;
    const cl = read("CHANGELOG.md").split("\n");
    const at = cl.map((l, i) => (head.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("the CHANGELOG heading appears " + at.length + " times");
    else {
      let end = cl.length;
      for (let i = at[0] + 1; i < cl.length; i += 1) if (cl[i].startsWith("## ")) { end = i; break; }
      const body = cl.slice(at[0] + 1, end).join("\n");
      for (const w of ["Node.js 22", "aai-bootstrap.ps1", "DR-1", "DR-2", "DR-4", "DR-5", "DR-9"]) if (!body.includes(w)) bad.push("the CHANGELOG body lacks " + w);
      if (body.trim() === "") bad.push("the CHANGELOG body is empty");
    }
    const sb = read(".aai/SKILL_BOOTSTRAP.prompt.md").split("\n");
    const once = (l) => sb.filter((x) => x === l).length;
    for (const l of ["powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 . --dry-run", "powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 .", "./.aai/scripts/aai-bootstrap.sh . --dry-run", "./.aai/scripts/aai-bootstrap.sh ."]) {
      if (once(l) !== 1) bad.push("SKILL_BOOTSTRAP holds the line " + JSON.stringify(l) + " " + once(l) + " times");
    }
    if (!read(".aai/SKILL_BOOTSTRAP.prompt.md").includes("Node.js 22 or later")) bad.push("SKILL_BOOTSTRAP does not say Node.js 22 or later");
    if (!read(".aai/system/DYNAMIC_SKILLS.md").includes("`.aai/scripts/aai-bootstrap.mjs`")) bad.push("DYNAMIC_SKILLS.md does not name aai-bootstrap.mjs");
    if (!read(".aai/system/RUNTIME_IGNORE.list").split("\n").slice(0, 8).join("\n").includes("aai-bootstrap.mjs")) bad.push("the RUNTIME_IGNORE.list header does not name aai-bootstrap.mjs");
    const rfc = read("docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md").split("\n");
    const row = rfc.filter((l) => l.startsWith("| 5 |"));
    if (row.length !== 1) bad.push("the RFC phase 5 row appears " + row.length + " times");
    else {
      const r = row[0];
      { const p5 = require("child_process").spawnSync("node", [root + "/tests/skills/lib/phase5-row-status.mjs", root + "/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"], { encoding: "utf8" }); if (p5.status !== 0) bad.push((p5.stdout || p5.stderr || "phase 5 status check failed").trim()); }
      const sentence = "The fourteenth slice [moved the project bootstrap to Node](../issues/CHANGE-0261-bootstrap-on-node.md): one module holds the detection, rendering and write policy behind thin aai-bootstrap.sh and aai-bootstrap.ps1 launchers, byte-equivalent to the frozen bash reference in the parity harness, so Windows gets a native bootstrap.";
      if (r.split(sentence).length !== 2) bad.push("the RFC row does not hold the D-DOCS sentence once");
      const a = r.indexOf("The thirteenth slice"); const b = r.indexOf("The fourteenth slice"); const c = r.indexOf("The [remaining-scripts plan]");
      if (!(a >= 0 && a < b && b < c)) bad.push("the RFC sentence is not between the thirteenth slice and the remaining-scripts plan");
      if (!/\(\.\.\/issues\/[A-Za-z0-9-]*bootstrap-on-node\.md\)/.test(r)) bad.push("the RFC link does not end with bootstrap-on-node.md");
    }
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT")"
  [[ -z "$out" ]] || log_fail "TEST-3959: $out"
  for sel in "test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger" "test-aai-expert-fetch.sh test_2624_inventory_matches_tree"; do
    rc=0
    # shellcheck disable=SC2086
    env -u AAI_ROLE bash "$SCRIPT_DIR/${sel%% *}" ${sel#* } > "$work/sel.log" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$work/sel.log" >&2; log_fail "TEST-3959: ${sel#* } of ${sel%% *} exited $rc"; }
  done
  safe_rm_own "$work"
  log_pass "TEST-3959: the CHANGELOG entry, the PowerShell lines of SKILL_BOOTSTRAP, DYNAMIC_SKILLS, the list header and the RFC-0017 sentence hold, and the prompt-diet ledger and RFC inventory suites pass"
}

# --- onboarding-tech-contract-and-lint-gaps (docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md) ---

test_4125_bootstrap_tech_pointer() {
  run_node_tests TEST-4125
  log_pass "TEST-4125: the template seed gives the trailing Technology contract block in normal and dry-run mode, the file is untouched, generated and absent give none"
}

test_4127_eslintrc_pin() {
  run_node_tests TEST-4127
  log_pass "TEST-4127: a legacy eslintrc without eslint gives npx eslint@8 . under every lockfile and with no package.json, plus the pin block in the aai-lint skill"
}

test_4128_local_eslint_preferred() {
  run_node_tests TEST-4128
  log_pass "TEST-4128: a project eslint (four dependency blocks, .bin, .bin cmd) gives the package manager form with no pin block, flat config unchanged, a lint target still wins"
}

test_4130_k05_reviewed_drift() {
  need_tool TEST-4130 bash || return 0
  need_tool TEST-4130 git || return 0
  run_node_tests TEST-4130
  log_pass "TEST-4130: K05 alone agrees with the reference through the DR-12 rewrite, disagrees without it with eslint-only problems, and a pair that matches nothing is reported"
}

# fenced_command <SKILL.md>: the text between the ```bash fence and its closing fence (the one command the skill runs).
fenced_command() {
  awk '/^```/ { if (inb) exit; if ($0 ~ /^```bash/) inb = 1; next } inb { print }' "$1"
}

# stub_npx_dir <work>: a bin directory whose npx only appends its arguments to <work>/npx.log.
stub_npx_dir() {
  local bin="$1/stub-bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> "$NPX_LOG"' 'exit 0' > "$bin/npx"
  chmod +x "$bin/npx"
  printf '%s\n' "$bin"
}

# run_lint_skill <work> <fixture> <expected-log>: runs the written aai-lint fenced command in the fixture with the
# stub npx first on PATH; the stub log must be exactly the expected line (an empty log is a failure).
run_lint_skill() {
  local work="$1" fixture="$2" want="$3" cmd bin log got rc=0
  cmd="$(fenced_command "$fixture/.claude/skills/aai-lint/SKILL.md")"
  [[ -n "$cmd" ]] || log_fail "TEST-4129: no fenced command in $fixture/.claude/skills/aai-lint/SKILL.md"
  bin="$(stub_npx_dir "$work")"
  log="$work/npx.log"
  : > "$log"
  (cd "$fixture" && env NPX_LOG="$log" PATH="$bin:$PATH" sh -c "$cmd") || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-4129: the fenced command '$cmd' exited $rc"
  got="$(cat "$log")"
  [[ -n "$got" ]] || log_fail "TEST-4129: the stub npx log is empty after '$cmd' (the command never reached npx)"
  [[ "$got" == "$want" ]] || log_fail "TEST-4129: npx got '$got', expected '$want' (command '$cmd')"
}

test_4129_lint_skill_runs_as_written() {
  local work legacy modern viash
  work="$(new_own_scratch lintskill)"
  legacy="$work/legacy"
  modern="$work/modern"
  viash="$work/via-sh"
  mkdir -p "$legacy" "$modern" "$viash"
  printf '%s\n' '{}' > "$legacy/.eslintrc.json"
  printf '%s\n' '{}' > "$viash/.eslintrc.json"
  printf '%s\n' 'export default [];' > "$modern/eslint.config.js"
  printf '%s\n' '{ "name": "modern", "devDependencies": { "eslint": "9.0.0" } }' > "$modern/package.json"
  env -u AAI_ROLE node "$MJS" "$legacy" >/dev/null
  env -u AAI_ROLE node "$MJS" "$modern" >/dev/null
  env -u AAI_ROLE sh "$SH_LAUNCHER" "$viash" >/dev/null
  run_lint_skill "$work" "$legacy" 'eslint@8 .'
  run_lint_skill "$work" "$modern" 'eslint .'
  cmp -s "$legacy/.claude/skills/aai-lint/SKILL.md" "$viash/.claude/skills/aai-lint/SKILL.md" \
    || log_fail "TEST-4129: the eslintrc aai-lint skill written through the sh launcher differs from the module's"
  [[ "$(cat "$legacy/.claude/skills/aai-lint/SKILL.md")" == *"## ESLint 8 pin"* ]] || log_fail "TEST-4129: the legacy skill carries no pin block"
  [[ "$(cat "$modern/.claude/skills/aai-lint/SKILL.md")" != *"## ESLint 8 pin"* ]] || log_fail "TEST-4129: the flat-config skill carries a pin block"
  safe_rm_own "$work"
  log_pass "TEST-4129: the written aai-lint command runs through a stub npx as eslint@8 . (legacy eslintrc) and eslint . (flat config with eslint); the sh launcher writes the same skill bytes"
}

test_4133_launchers_thin_and_docs() {
  local launcher report n
  for launcher in "$SH_LAUNCHER" "$PS1_LAUNCHER"; do
    if qgrep -qi 'eslint' < "$launcher"; then log_fail "TEST-4133: $launcher holds lint logic (the text eslint)"; fi
  done
  n="$(awk '{ c += gsub(/eslint@8/, "&") } END { print c + 0 }' "$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md")"
  [[ "$n" == 1 ]] || log_fail "TEST-4133: SKILL_BOOTSTRAP holds eslint@8 $n times, expected exactly 1"
  report="$(awk '/^## / { f = ($0 == "## Report Results") } f' "$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md")"
  [[ -n "$report" ]] || log_fail "TEST-4133: SKILL_BOOTSTRAP has no Report Results section"
  n="$(printf '%s\n' "$report" | awk '/^- / && /Technology contract/ && /TECH_EXTRACT/ { c += 1 } END { print c + 0 }')"
  [[ "$n" == 1 ]] || log_fail "TEST-4133: $n Report Results bullets name Technology contract and TECH_EXTRACT, expected 1"
  log_pass "TEST-4133: the launchers hold no lint logic; SKILL_BOOTSTRAP holds eslint@8 once and a Report Results bullet for the Technology contract line"
}

test_4135_changelog_and_amendment() {
  local out rc=0
  out="$(node -e '
    const fs = require("fs");
    const root = process.argv[1];
    const read = (p) => fs.readFileSync(root + "/" + p, "utf8");
    const bad = [];
    // A release cut rolls "## [unreleased] — " into "## [vYYYY.MM.DD] — ", so the pin accepts both.
    const head = /^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — fix: onboarding points to TECH_EXTRACT and generates a working lint skill$/;
    const cl = read("CHANGELOG.md").split("\n");
    const at = cl.map((l, i) => (head.test(l) ? i : -1)).filter((i) => i >= 0);
    if (at.length !== 1) bad.push("the CHANGELOG heading appears " + at.length + " times");
    else {
      let end = cl.length;
      for (let i = at[0] + 1; i < cl.length; i += 1) if (cl[i].startsWith("## ")) { end = i; break; }
      const body = cl.slice(at[0] + 1, end).join("\n");
      for (const w of ["CAT-05", "eslint@8", "TECH_EXTRACT"]) if (!body.includes(w)) bad.push("the CHANGELOG body lacks " + w);
    }
    const spec = read("docs/specs/SPEC-0306-spec-bootstrap-on-node.md").split("\n");
    const n = spec.filter((l) => l === "## Amendment (onboarding-tech-contract-and-lint-gaps)").length;
    if (n !== 1) bad.push("SPEC-0306 holds the amendment heading " + n + " times");
    if (!spec.some((l) => l.startsWith("| DR-12 |") && l.includes("eslint@8"))) bad.push("SPEC-0306 holds no DR-12 row naming eslint@8");
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT")"
  [[ -z "$out" ]] || log_fail "TEST-4135: $out"
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --strict >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-4135: spec-amend list --strict exited $rc"
  log_pass "TEST-4135: the CHANGELOG heading holds in unreleased or rolled form, SPEC-0306 holds the amendment heading and the DR-12 row, and spec-amend list --strict exits 0"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3940..3959, onboarding TEST-4125..4135)"
  check_deps
  setup_fixture
  test_3940_scratch_safety
  test_3941_module_shape
  test_3942_cli_and_root
  test_3943_detection
  test_3944_commands
  test_3945_auth_and_plan
  test_3946_rendering
  test_3947_writes_and_conflicts
  test_3948_gitignore
  test_3949_corpus_masked
  test_3950_hooks_overlay
  test_3951_platform_record
  test_3952_corpus_full
  test_3953_sh_launcher
  test_3954_rehomed_suites
  test_3955_ps1_launcher
  test_3956_parity_bootstrap
  test_3957_scratch_install
  test_3958_wiring
  test_3959_docs
  test_4125_bootstrap_tech_pointer
  test_4127_eslintrc_pin
  test_4128_local_eslint_preferred
  test_4130_k05_reviewed_drift
  test_4129_lint_skill_runs_as_written
  test_4133_launchers_thin_and_docs
  test_4135_changelog_and_amendment
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
