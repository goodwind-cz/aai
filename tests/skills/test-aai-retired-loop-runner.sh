#!/usr/bin/env bash
#
# Test: aai-retired-loop-runner
# (docs/specs/SPEC-DRAFT-spec-retire-shell-loop-runner.md, TEST-3403..3415)
#
# The shell loop runner retirement: autonomous-loop.sh / .ps1 are deprecation launchers
# that name /aai-loop, change nothing and exit 1. Every case here works in fresh mktemp
# fixtures; nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-retired-loop-runner.sh                       # run all
#   bash tests/skills/test-aai-retired-loop-runner.sh test_3403_sh_retired_run
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-retired-loop-runner"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/autonomous-loop.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/autonomous-loop.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/retired-loop-runner.Tests.ps1"
D1_LINE="autonomous-loop: retired - the autonomous-loop shell runner is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: /aai-loop; nothing was changed"

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-retired-loop-runner-suite.XXXXXX")" && pwd -P)"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_fixture <dir>: a clean committed repository whose docs/ai holds only .gitkeep.
make_fixture() {
  local d="$1"
  mkdir -p "$d/docs/ai"
  : > "$d/docs/ai/.gitkeep"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config commit.gpgsign false
  git -C "$d" add -A
  git -C "$d" commit -q -m fixture
}

# file_listing <dir>: sorted relative file list with content hashes, .git excluded.
file_listing() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }

# assert_retired_run <TEST id> <label> <fixture> <before listing> <so> <se> <rc>: the D1 contract.
assert_retired_run() {
  local id="$1" label="$2" fx="$3" before="$4" so="$5" se="$6" rc="$7"
  [[ "$rc" == 1 ]] || log_fail "$id: $label exited $rc, expected 1"
  [[ ! -s "$so" ]] || log_fail "$id: $label wrote to stdout"
  [[ "$(cat "$se")" == "$D1_LINE" ]] || log_fail "$id: $label stderr was: $(cat "$se")"
  [[ ! -e "$fx/docs/ai/STATE.yaml" && ! -e "$fx/docs/ai/LOOP_TICKS.jsonl" ]] || log_fail "$id: $label created STATE.yaml or LOOP_TICKS.jsonl"
  [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "$id: $label left git status non-empty"
  [[ "$(file_listing "$fx")" == "$before" ]] || log_fail "$id: $label changed the file listing"
}

# scratch_bin <dir>: a PATH directory holding coreutils links only (no node, python3, codex, claude).
scratch_bin() {
  local b="$1" t p
  mkdir -p "$b"
  for t in cat ls env; do
    p="$(command -v "$t" 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then ln -s "$p" "$b/$t"; fi
  done
}

test_3403_sh_retired_run() {
  local fx="$TEST_DIR/sh fx" bin="$TEST_DIR/bin-sh" so="$TEST_DIR/t.out" se="$TEST_DIR/t.err" before sh sh_path rc variant
  mkdir -p "$fx"
  make_fixture "$fx"
  scratch_bin "$bin"
  before="$(file_listing "$fx")"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3403 needs $sh"; continue; }
    for variant in skill none; do
      rc=0
      if [[ "$variant" == skill ]]; then
        ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" --mode skill --agent-command codex --max-iterations 1 --auto-init-state ) >"$so" 2>"$se" || rc=$?
      else
        ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" ) >"$so" 2>"$se" || rc=$?
      fi
      assert_retired_run TEST-3403 "autonomous-loop.sh under $sh ($variant)" "$fx" "$before" "$so" "$se" "$rc"
    done
  done
  log_pass "TEST-3403: autonomous-loop.sh prints the D1 line, exits 1 and changes nothing under bash, sh and dash with no node, python3, codex or claude on PATH"
}

test_3404_ps1_retired_run() {
  need_tool TEST-3404 pwsh || return 0
  local fx="$TEST_DIR/ps1 fx" bin="$TEST_DIR/bin-ps1" so="$TEST_DIR/p.out" se="$TEST_DIR/p.err" before rc variant pwsh_path
  pwsh_path="$(command -v pwsh)"
  mkdir -p "$fx"
  make_fixture "$fx"
  scratch_bin "$bin"
  before="$(file_listing "$fx")"
  for variant in skill none dry; do
    rc=0
    case "$variant" in
      skill) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" -Mode skill -AgentCommand codex -MaxIterations 1 -AutoInitState ) >"$so" 2>"$se" || rc=$? ;;
      none) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" ) >"$so" 2>"$se" || rc=$? ;;
      dry) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" -DryRun ) >"$so" 2>"$se" || rc=$? ;;
    esac
    assert_retired_run TEST-3404 "autonomous-loop.ps1 ($variant)" "$fx" "$before" "$so" "$se" "$rc"
  done
  log_pass "TEST-3404: autonomous-loop.ps1 prints the D1 line, exits 1 and changes nothing under pwsh for skill-mode switches, no argument and -DryRun"
}

test_3405_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3405: tests/skills/retired-loop-runner.Tests.ps1 does not exist"
  need_tool TEST-3405 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3405 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 3) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3405: retired-loop-runner.Tests.ps1 failed, skipped a case or ran fewer than 3 cases (rc=$rc)"; }
  log_pass "TEST-3405: retired-loop-runner.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# launcher_problems <file> <D1 line>: prints problems of one launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, want] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    const marks = s.split(/\r?\n/).filter((l) => l.startsWith("# RETIRED (RFC-0017 phase 5, retire-shell-loop-runner)"));
    if (marks.length !== 1) bad.push("RETIRED comment lines: " + marks.length);
    if (!s.includes(want)) bad.push("D1 line text missing");
    if (file.endsWith(".sh") && s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
    if (file.endsWith(".ps1") && /^\s*param\s*\(/mi.test(s)) bad.push("holds a param block");
    const w = s.match(/\b(node|python\w*|git|codex|claude|gemini|mkdir|rm|cp|mv)\b/);
    if (w) bad.push("names " + w[0]);
    for (const x of ["STATE", "LOOP_TICKS", "SKILL_"]) if (s.includes(x)) bad.push("holds " + x);
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3406_launchers_thin() {
  local name f out mode ctl
  for name in autonomous-loop.sh autonomous-loop.ps1; do
    f="$PROJECT_ROOT/.aai/scripts/$name"
    [[ -f "$f" ]] || log_fail "TEST-3406: $name does not exist"
    out="$(launcher_problems "$f" "$D1_LINE")"; [[ -z "$out" ]] || log_fail "TEST-3406: $name: $out"
    mode="$(git -C "$PROJECT_ROOT" ls-files -s -- ".aai/scripts/$name" | cut -d' ' -f1)"
    [[ "$mode" == 100644 ]] || log_fail "TEST-3406: $name git mode is '$mode', not 100644"
  done
  ctl="$TEST_DIR/ctl-retired.sh"
  { cat "$SH_LAUNCHER"; echo 'git status'; } > "$ctl"
  out="$(launcher_problems "$ctl" "$D1_LINE")"
  [[ "$out" == *"git"* ]] || log_fail "TEST-3406: positive control: a launcher holding git status was not reported"
  log_pass "TEST-3406: both launchers are thin, ASCII, mode 100644, carry the RETIRED comment and the D1 line and name no tool"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-retire-shell-loop-runner TEST-3403..3415)"
  check_deps
  setup_fixture
  test_3403_sh_retired_run
  test_3404_ps1_retired_run
  test_3405_pester
  test_3406_launchers_thin
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
