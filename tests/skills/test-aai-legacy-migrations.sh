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
PESTER_FILE="$PROJECT_ROOT/tests/skills/legacy-migrations.Tests.ps1"
CANON_LINE="aai-canonicalize: retired - the aai-canonicalize script and the /aai-canonicalize skill are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed"
YAML_LINE="migrate-yaml-to-jsonl: retired - the migrate-yaml-to-jsonl script is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed"
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

test_3388_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3388: tests/skills/legacy-migrations.Tests.ps1 does not exist"
  need_tool TEST-3388 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3388 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 6) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3388: legacy-migrations.Tests.ps1 failed, skipped a case or ran fewer than 6 cases (rc=$rc)"; }
  log_pass "TEST-3388: legacy-migrations.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# file_listing <dir>: sorted relative file list with content hashes, .git excluded.
file_listing() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }

test_3389_retired_run() {
  local fx="$TEST_DIR/retired fx" bin="$TEST_DIR/empty-bin" so="$TEST_DIR/t.out" se="$TEST_DIR/t.err" before name line sh sh_path rc
  mkdir -p "$fx" "$bin"
  make_legacy "$fx"
  before="$(file_listing "$fx")"
  for name in aai-canonicalize migrate-yaml-to-jsonl; do
    line="$CANON_LINE"; [[ "$name" == migrate-yaml-to-jsonl ]] && line="$YAML_LINE"
    for sh in bash sh dash; do
      sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3389 needs $sh"; continue; }
      rc=0; ( cd "$fx" && PATH="$bin" "$sh_path" "$PROJECT_ROOT/.aai/scripts/$name.sh" . --dry-run ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-3389: $name.sh under $sh exited $rc, expected 1"
      [[ ! -s "$so" ]] || log_fail "TEST-3389: $name.sh under $sh wrote to stdout"
      [[ "$(cat "$se")" == "$line" ]] || log_fail "TEST-3389: $name.sh under $sh stderr was: $(cat "$se")"
      [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "TEST-3389: $name.sh under $sh changed the fixture"
      [[ "$(file_listing "$fx")" == "$before" ]] || log_fail "TEST-3389: $name.sh under $sh changed the file listing"
    done
    if need_tool TEST-3389 pwsh; then
      rc=0; ( cd "$fx" && PATH="$bin" "$(command -v pwsh)" -NoProfile -File "$PROJECT_ROOT/.aai/scripts/$name.ps1" -TargetRoot . -DryRun ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-3389: $name.ps1 exited $rc, expected 1"
      [[ ! -s "$so" ]] || log_fail "TEST-3389: $name.ps1 wrote to stdout"
      [[ "$(cat "$se")" == "$line" ]] || log_fail "TEST-3389: $name.ps1 stderr was: $(cat "$se")"
      [[ -z "$(git -C "$fx" status --porcelain)" && "$(file_listing "$fx")" == "$before" ]] || log_fail "TEST-3389: $name.ps1 changed the fixture"
    fi
  done
  log_pass "TEST-3389: the four retirement launchers print their D3 line, exit 1 and change nothing, with no node and no python3 on PATH"
}

# retired_problems <file> <expected line>: prints problems of one retirement launcher (empty when clean).
retired_problems() {
  node -e '
    const fs = require("fs");
    const [file, want] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    const marks = s.split(/\r?\n/).filter((l) => l.startsWith("# RETIRED (RFC-0017 phase 5, retire-legacy-migrations)"));
    if (marks.length !== 1) bad.push("RETIRED comment lines: " + marks.length);
    if (!s.includes(want)) bad.push("D3 line text missing");
    const w = s.match(/\b(python\w*|node|git|mv|cp|rm|mkdir)\b/);
    if (w) bad.push("names " + w[0]);
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3390_retired_thin() {
  local name line f out mode ctl
  for name in aai-canonicalize.sh aai-canonicalize.ps1 migrate-yaml-to-jsonl.sh migrate-yaml-to-jsonl.ps1; do
    line="$CANON_LINE"; [[ "$name" == migrate-yaml-to-jsonl* ]] && line="$YAML_LINE"
    f="$PROJECT_ROOT/.aai/scripts/$name"
    out="$(retired_problems "$f" "$line")"; [[ -z "$out" ]] || log_fail "TEST-3390: $name: $out"
    mode="$(git -C "$PROJECT_ROOT" ls-files -s -- ".aai/scripts/$name" | cut -d' ' -f1)"
    [[ "$mode" == 100644 ]] || log_fail "TEST-3390: $name git mode is '$mode', not 100644"
  done
  ctl="$TEST_DIR/ctl-retired.sh"
  { cat "$PROJECT_ROOT/.aai/scripts/migrate-yaml-to-jsonl.sh"; echo 'python3 -c pass'; } > "$ctl"
  out="$(retired_problems "$ctl" "$YAML_LINE")"
  [[ "$out" == *"python3"* ]] || log_fail "TEST-3390: positive control: a launcher holding python3 was not reported"
  log_pass "TEST-3390: the four retirement launchers are thin, ASCII, mode 100644, carry the RETIRED comment and name no tool"
}

test_3396_doctor_seam() {
  local fx="$TEST_DIR/doctor fx" out rc=0 f
  mkdir -p "$fx/docs/ai" "$fx/.aai"
  cp -R "${AAI_LM_SCRIPTS:-$PROJECT_ROOT/.aai/scripts}" "$fx/.aai/scripts"
  echo x > "$fx/docs/ai/STATE.yaml"
  printf 'docs/ai/STATE.yaml\n' > "$fx/.gitignore"
  git -C "$fx" init -q
  git -C "$fx" config user.email fixture@example.invalid
  git -C "$fx" config user.name fixture
  git -C "$fx" config commit.gpgsign false
  git -C "$fx" add -A -f
  git -C "$fx" commit -q -m legacy
  out="$(node "$fx/.aai/scripts/aai-doctor.mjs" --root "$fx" 2>&1)" || true
  [[ "$out" == *INCONSISTENT* && "$out" == *migrate-state-to-local.sh* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3396: the doctor did not report INCONSISTENT naming migrate-state-to-local.sh"; }
  ( cd "$fx" && bash .aai/scripts/migrate-state-to-local.sh ) >/dev/null 2>&1 || log_fail "TEST-3396: the named launcher failed"
  git -C "$fx" add .gitignore docs/ai/EVENTS.jsonl
  git -C "$fx" commit -q -m migrate
  out="$(node "$fx/.aai/scripts/aai-doctor.mjs" --root "$fx" 2>&1)" || true
  [[ "$out" != *migrate-state-to-local* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3396: the doctor still names migrate-state-to-local after the migration"; }
  for f in .aai/scripts/aai-doctor.mjs .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 README.md; do
    [[ "$(git -C "$PROJECT_ROOT" show "f324b66f:$f" | grep -F migrate-state-to-local)" == "$(grep -F migrate-state-to-local "$PROJECT_ROOT/$f")" ]] \
      || log_fail "TEST-3396: the migrate-state-to-local lines of $f differ from f324b66f"
  done
  log_pass "TEST-3396: the doctor names the launcher, the launcher clears the finding, and the caller lines equal f324b66f"
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
  test_3388_pester
  test_3389_retired_run
  test_3390_retired_thin
  test_3396_doctor_seam
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
