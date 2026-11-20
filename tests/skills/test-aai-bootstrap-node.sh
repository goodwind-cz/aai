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
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.sh"
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
  local json
  json="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json)" || { echo "spec-amend list failed"; return 0; }
  printf '%s' "$json" | node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
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
  '
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

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3940..3954 so far)"
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
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
