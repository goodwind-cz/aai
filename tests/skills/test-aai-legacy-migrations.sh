#!/usr/bin/env bash
#
# Test: aai-legacy-migrations
# (docs/specs/SPEC-DRAFT-spec-retire-legacy-migrations.md, TEST-3380..3400)
#
# The legacy-migration retirement: migrate-state-to-local is one Node module
# (.aai/scripts/migrate-state-to-local.mjs) behind thin launchers, and
# aai-canonicalize / migrate-yaml-to-jsonl are deprecation launchers. Every case
# here works in fresh mktemp fixtures; nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-legacy-migrations.sh                       # run all
#   bash tests/skills/test-aai-legacy-migrations.sh test_3380_pure
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-legacy-migrations"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/migrate-state-to-local.test.mjs"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.ps1"
D2_LINE="migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run."

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-legacy-migrations-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/migrate-state-to-local.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/migrate-state-to-local.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

test_3380_pure() {
  run_node_tests TEST-3380
  log_pass "TEST-3380: IGNORE_PATTERNS, parseArgs, missingPatterns and gitignoreAppend follow D1"
}

test_3381_effects() {
  run_node_tests TEST-3381
  log_pass "TEST-3381: a legacy fixture is migrated once and a second run is a byte-identical no-op"
}

test_3382_refusals_dry_run() {
  run_node_tests TEST-3382
  log_pass "TEST-3382: every refusal carries its D1 text and exit code, and a dry run changes nothing"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_legacy <dir>: a clean committed legacy fixture (CRLF .gitignore, tracked runtime state).
make_legacy() {
  local d="$1"
  mkdir -p "$d/docs/ai/tdd/x" "$d/docs/ai/loop"
  printf 'node_modules\r\n' > "$d/.gitignore"
  echo x > "$d/docs/ai/STATE.yaml"; echo x > "$d/docs/ai/LOOP_TICKS.jsonl"
  echo x > "$d/docs/ai/tdd/.gitkeep"; echo x > "$d/docs/ai/tdd/x/red.log"; echo x > "$d/docs/ai/loop/a.txt"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config commit.gpgsign false
  git -C "$d" add -A
  git -C "$d" commit -q -m legacy
}

# launcher_problems <file> <sh|ps1>: prints problems of one migrate-state launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, kind] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    if (!s.includes("migrate-state-to-local.mjs")) bad.push("does not name migrate-state-to-local.mjs");
    if (kind === "sh") {
      if (s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
      if (s.includes("[[")) bad.push("holds [[");
      if (s.includes("BASH_SOURCE")) bad.push("holds BASH_SOURCE");
    }
    for (const w of ["rm --cached", "ls-files", ".gitignore", "EVENTS.jsonl", "UNTRACK", "docs/ai/"]) {
      if (s.includes(w)) bad.push("holds forbidden string " + w);
    }
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3385_launchers_thin() {
  local out mode ctl
  out="$(launcher_problems "$SH_LAUNCHER" sh)"; [[ -z "$out" ]] || log_fail "TEST-3385: sh launcher: $out"
  out="$(launcher_problems "$PS1_LAUNCHER" ps1)"; [[ -z "$out" ]] || log_fail "TEST-3385: ps1 launcher: $out"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/migrate-state-to-local.sh | cut -d' ' -f1)"
  [[ "$mode" == 100755 ]] || log_fail "TEST-3385: sh launcher git mode is '$mode', not 100755"
  ctl="$TEST_DIR/ctl.sh"
  { cat "$SH_LAUNCHER"; echo 'git rm --cached x'; } > "$ctl"
  out="$(launcher_problems "$ctl" sh)"
  [[ "$out" == *"rm --cached"* ]] || log_fail "TEST-3385: positive control: a launcher holding rm --cached was not reported"
  log_pass "TEST-3385: both migrate-state launchers are thin, ASCII, POSIX (sh) and hold no migration logic"
}

# assert_refused <TEST id> <label> <stdout file> <stderr file> <rc> <fixture>
assert_refused() {
  local id="$1" label="$2" so="$3" se="$4" rc="$5" fx="$6"
  [[ "$rc" == 1 ]] || log_fail "$id: $label exited $rc, expected 1"
  [[ ! -s "$so" ]] || log_fail "$id: $label wrote to stdout"
  [[ "$(cat "$se")" == "$D2_LINE" ]] || log_fail "$id: $label stderr was: $(cat "$se")"
  [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "$id: $label changed the fixture"
  [[ "$(od -An -c "$fx/.gitignore" | tr -d ' \n')" == "node_modules\r\n" ]] || log_fail "$id: $label changed .gitignore"
}

test_3386_refusal_no_node() {
  local fx="$TEST_DIR/refuse fx" bin="$TEST_DIR/nonode-bin" sh_path sh rc so se copy
  mkdir -p "$fx" "$bin"
  make_legacy "$fx"
  ln -sf "$(command -v git)" "$bin/git"; ln -sf "$(command -v dirname)" "$bin/dirname"
  so="$TEST_DIR/r.out"; se="$TEST_DIR/r.err"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3386 needs $sh"; continue; }
    rc=0; ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" "$fx" ) >"$so" 2>"$se" || rc=$?
    assert_refused TEST-3386 "sh launcher under $sh without node" "$so" "$se" "$rc" "$fx"
  done
  copy="$TEST_DIR/nomodule"; mkdir -p "$copy"; cp "$SH_LAUNCHER" "$copy/migrate-state-to-local.sh"
  rc=0; ( cd "$fx" && sh "$copy/migrate-state-to-local.sh" "$fx" ) >"$so" 2>"$se" || rc=$?
  assert_refused TEST-3386 "sh launcher copy without the module" "$so" "$se" "$rc" "$fx"
  if need_tool TEST-3386 pwsh; then
    cp "$PS1_LAUNCHER" "$copy/migrate-state-to-local.ps1"
    rc=0; ( cd "$fx" && pwsh -NoProfile -File "$copy/migrate-state-to-local.ps1" -TargetRoot "$fx" ) >"$so" 2>"$se" || rc=$?
    assert_refused TEST-3386 "ps1 launcher copy without the module" "$so" "$se" "$rc" "$fx"
  fi
  log_pass "TEST-3386: without node or without the module each launcher prints the D2 refusal, exits 1 and changes nothing"
}

# assert_migrated <TEST id> <label> <fixture>: the Spec-AC-02 effects on a launcher-migrated fixture.
assert_migrated() {
  local id="$1" label="$2" fx="$3" tracked n
  tracked="$(git -C "$fx" ls-files | sort | tr '\n' ' ')"
  [[ "$tracked" == ".gitignore docs/ai/tdd/.gitkeep " ]] || log_fail "$id: $label tracked set is: $tracked"
  n="$(grep -c -E '^(!?docs/ai/|docs/INDEX.audit.md)' "$fx/.gitignore" || true)"
  [[ "$n" == 16 ]] || log_fail "$id: $label .gitignore holds $n runtime entries, expected 16"
  [[ -f "$fx/docs/ai/EVENTS.jsonl" && ! -s "$fx/docs/ai/EVENTS.jsonl" ]] || log_fail "$id: $label EVENTS.jsonl is missing or not empty"
}

test_3387_sh_launcher_e2e() {
  local base="$TEST_DIR/e2e space" src sh sh_path fx so rc
  mkdir -p "$base"
  src="$base/src"; mkdir -p "$src"; make_legacy "$src"
  so="$TEST_DIR/e.out"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3387 needs $sh"; continue; }
    fx="$base/arg-$sh"; cp -R "$src" "$fx"
    rc=0; ( cd "$TEST_DIR" && "$sh_path" "$SH_LAUNCHER" "$fx" ) >"$so" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$so" >&2; log_fail "TEST-3387: $sh with an argument exited $rc"; }
    grep -qxF "Target: $fx" "$so" || log_fail "TEST-3387: $sh with an argument did not print Target: $fx"
    assert_migrated TEST-3387 "$sh with an argument" "$fx"
    fx="$base/cwd-$sh"; cp -R "$src" "$fx"
    rc=0; ( cd "$fx" && "$sh_path" "$SH_LAUNCHER" ) >"$so" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$so" >&2; log_fail "TEST-3387: $sh with no argument exited $rc"; }
    grep -qxF "Target: $fx" "$so" || log_fail "TEST-3387: $sh with no argument did not print Target: $fx"
    assert_migrated TEST-3387 "$sh with no argument" "$fx"
  done
  fx="$base/dry"; cp -R "$src" "$fx"
  rc=0; ( cd "$TEST_DIR" && sh "$SH_LAUNCHER" "$fx" --dry-run ) >"$so" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3387: --dry-run exited $rc"
  grep -qxF 'Dry-run only. Re-run without the dry-run flag to apply.' "$so" || log_fail "TEST-3387: --dry-run was not forwarded to the module"
  [[ -z "$(git -C "$fx" status --porcelain)" && ! -e "$fx/docs/ai/EVENTS.jsonl" ]] || log_fail "TEST-3387: --dry-run changed the fixture"
  log_pass "TEST-3387: the sh launcher migrates a fixture in a path with a space under bash, sh and dash, with and without an argument, and forwards --dry-run"
}

test_3383_hostile_names() {
  run_node_tests TEST-3383
  log_pass "TEST-3383: hostile tracked names are untracked literally, run no command and keep .gitkeep tracked"
}

test_3384_rm_failure() {
  run_node_tests TEST-3384
  log_pass "TEST-3384: a failing git rm prints the D1 error, exits 1 and writes nothing else"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-retire-legacy-migrations TEST-3380..3400)"
  check_deps
  setup_fixture
  test_3380_pure
  test_3381_effects
  test_3382_refusals_dry_run
  test_3383_hostile_names
  test_3384_rm_failure
  test_3385_launchers_thin
  test_3386_refusal_no_node
  test_3387_sh_launcher_e2e
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
