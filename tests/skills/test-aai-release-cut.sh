#!/usr/bin/env bash
#
# Test: aai-release-cut
# (docs/specs/SPEC-0281-spec-release-on-node.md, TEST-3462..3478)
#
# release-cut is one Node module (.aai/scripts/release-cut.mjs) behind aai-release.sh and aai-release.ps1.
# Every case works in fresh mktemp fixtures with a stub gh first on PATH and local bare origins; no case runs
# a real gh, pushes to a network remote, opens a PR, tags or publishes, and none reads or writes the
# repository's own CHANGELOG.md (the preamble arm runs through the test-aai-release.sh selector).
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-release-cut.sh                      # run all
#   bash tests/skills/test-aai-release-cut.sh test_3462_seam
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-release-cut"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/release-cut.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/release-cut.test.mjs"
SH_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-release.sh"
PS1_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-release.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/release-cut.Tests.ps1"
SPEC_ID="spec-release-on-node"
MISSING_NODE='REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.'

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-release-cut-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/release-cut.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/release-cut.test.mjs does not exist"
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

# code_lines <file> <comment prefix: # or //>: non-blank, non-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE "^[[:space:]]*($2|\$)" "$1" || true
}

test_3462_seam() {
  run_node_tests TEST-3462
  log_pass "TEST-3462: importing the module has no side effect and run drives the audit seam"
}

test_3463_plan_contract() {
  run_node_tests TEST-3463
  log_pass "TEST-3463: the module CLI plan meets the D-OUT contract for both launchers and writes nothing"
}

test_3464_rollup_drift() {
  run_node_tests TEST-3464
  log_pass "TEST-3464: DR-01 to DR-09 behave as decided"
}

test_3465_plan_drift() {
  run_node_tests TEST-3465
  log_pass "TEST-3465: DR-10 and DR-12 to DR-18 behave as decided"
}

test_3466_files_and_launch() {
  run_node_tests TEST-3466
  log_pass "TEST-3466: DR-11 and DR-19 to DR-22 behave as decided"
}

# drift_problems <spec> <node test file>: DR ids of the D-DRIFT table vs test names (empty when they agree).
drift_problems() {
  cat > "$TEST_DIR/drift.cjs" <<'JS'
const fs = require('fs');
const [spec, tests] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DR-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [...fs.readFileSync(tests, 'utf8').matchAll(/^test\('(?:TEST-\d+ )?(DR-\d\d)\b/gm)].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length !== 22) bad.push(`the table holds ${table.length} ids, expected 22`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/drift.cjs" "$1" "$2"
}

test_3467_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3467: no spec with id $SPEC_ID under docs/specs"
  [[ -f "$NODE_TEST" ]] || log_fail "TEST-3467: tests/skills/lib/release-cut.test.mjs does not exist"
  out="$(drift_problems "$spec" "$NODE_TEST")"
  [[ -z "$out" ]] || log_fail "TEST-3467: $out"
  sed "s/'TEST-3465 DR-13 /'TEST-3465 DR-31 /" "$NODE_TEST" > "$TEST_DIR/renamed.test.mjs"
  out="$(drift_problems "$spec" "$TEST_DIR/renamed.test.mjs")"
  [[ "$out" == *"DR-13 begins 0"* && "$out" == *"DR-31 is not in"* ]] || log_fail "TEST-3467: positive control: the renamed DR-13 was not reported ($out)"
  log_pass "TEST-3467: every D-DRIFT id begins exactly one node:test case and no case names a missing id"
}

# make_gh_stub <bin dir>: a gh stub that logs its argv, answers auth status with 0 and fails any other call.
make_gh_stub() {
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo 'printf "%s\n" "$*" >> "${0%/*}/gh.log"'
    echo '[ "$1 $2" = "auth status" ] && exit 0'
    echo 'exit 1'
  } > "$1/gh"
  chmod +x "$1/gh"
}

# init_repo <dir>: an empty git repository on main with a local identity.
init_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email fixture@example.invalid
  git -C "$1" config user.name fixture
  git -C "$1" config commit.gpgsign false
  git -C "$1" config core.autocrlf false
}

# make_fixture_a <dir> [all-noted]: the Spec-AC-02 fixture, tag v0 then merged PRs #12 (noted), #13 and #14 (unnoted).
make_fixture_a() {
  local n
  init_repo "$1"
  printf '%s\n' '# Changelog' '' '## [unreleased]' '' '## [unreleased] — feat: noted thing (#12)' '' 'Body one.' '' '## [unreleased] — second' '' 'Body two.' '' '## [v0] — old' '' 'old body' > "$1/CHANGELOG.md"
  git -C "$1" add -A; git -C "$1" commit -q -m 'chore: base'; git -C "$1" tag v0
  mkdir -p "$1/.aai"
  for n in 12 13 14; do
    [[ "$n" == 12 || -z "${2:-}" ]] || continue
    echo "$n" > "$1/.aai/f$n.txt"
    git -C "$1" add -A
    git -C "$1" commit -q -m "fix: thing $n (#$n)"
  done
}

# make_fixture_b <dir>: CRLF, a byte order mark, interleaved entries and no final newline, committed on main.
make_fixture_b() {
  init_repo "$1"
  printf '\xef\xbb\xbf# Changelog\r\n\r\n## [unreleased]\r\n\r\n## [unreleased] — a\r\n\r\nA body\r\n\r\n## [v0] — old\r\n\r\nold\r\n\r\n## [unreleased] — c\r\n\r\nC body' > "$1/CHANGELOG.md"
  git -C "$1" add -A; git -C "$1" commit -q -m 'chore: base'
}

# snap <repo> [origin]: working tree bytes, index, every ref and the file list (outside .git); origin refs when given.
snap() {
  git -C "$1" status --porcelain
  git -C "$1" ls-files -s
  git -C "$1" show-ref || true
  find "$1" -path "$1/.git" -prune -o -type f -exec cksum {} + | LC_ALL=C sort
  [[ -z "${2:-}" ]] || git -C "$2" show-ref || true
}

# run_release <sh|ps1> <fixture> <words: dry confirm noremote>: runs one script with the version v9; stdout in $SO, stderr in $SE, status in $RC.
SO=""; SE=""; RC=0; GH_BIN=""
run_release() {
  local kind="$1" fx="$2" w; shift 2
  local a=()
  for w in "$@"; do
    case "$kind:$w" in
      sh:dry) a+=(--dry-run) ;; sh:confirm) a+=(--confirm) ;; sh:noremote) a+=(--no-remote) ;;
      ps1:dry) a+=(-DryRun) ;; ps1:confirm) a+=(-Confirm) ;; ps1:noremote) a+=(-NoRemote) ;;
    esac
  done
  if [[ "$kind" == sh ]]; then a+=(--version v9); else a+=(-Version v9); fi
  RC=0
  if [[ "$kind" == sh ]]; then
    ( cd "$fx" && PATH="$GH_BIN:$PATH" bash "$SH_SCRIPT" "${a[@]}" ) >"$SO" 2>"$SE" || RC=$?
  else
    ( cd "$fx" && PATH="$GH_BIN:$PATH" pwsh -NoProfile -NonInteractive -File "$PS1_SCRIPT" "${a[@]}" ) >"$SO" 2>"$SE" || RC=$?
  fi
}

test_3468_one_transform() {
  local kind fx want="$TEST_DIR/t68.want" got="$TEST_DIR/t68.got" heads
  GH_BIN="$TEST_DIR/t68-bin"; SO="$TEST_DIR/t68.out"; SE="$TEST_DIR/t68.err"
  make_gh_stub "$GH_BIN"
  cat > "$TEST_DIR/expect.mjs" <<'JS'
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
const [repo, lib, outFile] = process.argv.slice(2);
const blob = spawnSync('git', ['show', 'main:CHANGELOG.md'], { cwd: repo, encoding: 'buffer' }).stdout;
const { rollup } = await import(pathToFileURL(lib).href);
const { content } = rollup(new TextDecoder('utf-8', { ignoreBOM: true }).decode(blob), 'v9');
fs.writeFileSync(outFile, content);
process.stdout.write(content.split('\n').map((l, i) => [i + 1, l.replace(/\r$/, '')]).filter(([, l]) => l.startsWith('## [v9] — ')).map(([n, l]) => `  ${n}:${l}`).join('\n'));
JS
  for kind in sh ps1; do
    [[ "$kind" == sh ]] || need_tool TEST-3468 pwsh || continue
    fx="$TEST_DIR/t68/$kind/repo"; make_fixture_b "$fx"
    heads="$(node "$TEST_DIR/expect.mjs" "$fx" "$PROJECT_ROOT/.aai/scripts/lib/release-rollup.mjs" "$want")"
    [[ -n "$heads" ]] || log_fail "TEST-3468: the expected rollup of the base blob lists no rolled heading"
    run_release "$kind" "$fx"
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3468: $kind plan exited $RC"; }
    [[ "$(grep -E '^  [0-9]+:## \[v9\] — ' "$SO")" == "$heads" ]] || { cat "$SO" >&2; log_fail "TEST-3468: the $kind plan does not list exactly the rolled headings of the shared rollup"; }
    run_release "$kind" "$fx" confirm noremote
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3468: $kind --confirm --no-remote exited $RC"; }
    git -C "$fx" show chore/release-v9:CHANGELOG.md > "$got"
    cmp -s "$want" "$got" || log_fail "TEST-3468: the $kind cut CHANGELOG.md differs from the shared rollup of the base blob"
  done
  log_pass "TEST-3468: the local cut equals the shared rollup of the base blob byte for byte and the plan lists its headings"
}

# make_with_origin <repo> <bare origin> [all-noted]: fixture A with a local bare origin whose HEAD is main.
make_with_origin() {
  git init -q -b main --bare "$2"
  make_fixture_a "$1" "${3:-}"
  git -C "$1" remote add origin "$2"
  git -C "$1" push -q origin main
  git -C "$1" remote set-head origin main
}

test_3469_no_publish() {
  local kind fx origin pre words
  GH_BIN="$TEST_DIR/t69-bin"; SO="$TEST_DIR/t69.out"; SE="$TEST_DIR/t69.err"
  make_gh_stub "$GH_BIN"
  for kind in sh ps1; do
    [[ "$kind" == sh ]] || need_tool TEST-3469 pwsh || continue
    mkdir -p "$TEST_DIR/t69/$kind"
    fx="$TEST_DIR/t69/$kind/repo"; origin="$TEST_DIR/t69/$kind/origin.git"
    make_with_origin "$fx" "$origin" all
    : > "$GH_BIN/gh.log"
    pre="$(snap "$fx" "$origin")"
    for words in "" "dry" "dry confirm"; do
      # shellcheck disable=SC2086
      run_release "$kind" "$fx" $words
      [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3469: $kind ($words) exited $RC"; }
      [[ "$(snap "$fx" "$origin")" == "$pre" ]] || log_fail "TEST-3469: $kind ($words) changed the repository or the origin"
      [[ -z "$(grep -vxF 'auth status' "$GH_BIN/gh.log" || true)" ]] || log_fail "TEST-3469: $kind ($words) called gh beyond auth status: $(cat "$GH_BIN/gh.log")"
    done
    run_release "$kind" "$fx" confirm
    [[ "$RC" != 0 ]] || log_fail "TEST-3469: $kind remote --confirm against a stub gh exited 0"
    grep -q '^REFUSED: ' "$SE" || { cat "$SE" >&2; log_fail "TEST-3469: $kind remote --confirm printed no REFUSED line"; }
    grep -q '^Resume: ' "$SE" || { cat "$SE" >&2; log_fail "TEST-3469: $kind remote --confirm printed no Resume line"; }
    [[ "$(snap "$fx" "$origin")" == "$pre" ]] || log_fail "TEST-3469: $kind remote --confirm changed a ref or the working tree"
    fx="$TEST_DIR/t69/$kind/cut"; origin="$TEST_DIR/t69/$kind/cut-origin.git"
    make_with_origin "$fx" "$origin" all
    : > "$GH_BIN/gh.log"
    pre="$(git -C "$origin" show-ref)"
    run_release "$kind" "$fx" confirm noremote
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3469: $kind --confirm --no-remote exited $RC"; }
    [[ "$(git -C "$origin" show-ref)" == "$pre" ]] || log_fail "TEST-3469: $kind --confirm --no-remote changed the origin refs"
    [[ ! -s "$GH_BIN/gh.log" ]] || log_fail "TEST-3469: $kind --confirm --no-remote called gh: $(cat "$GH_BIN/gh.log")"
  done
  log_pass "TEST-3469: bare, dry-run and dry-run plus confirm write nothing; the local cut touches no remote; a remote confirm ends in the finish refusal"
}

# lines_of <file> <pattern>: number of code (non-comment) lines matching a fixed string.
count_code_matches() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -vE '^[[:space:]]*(#|$)' "$1" | "$g" -cF -- "$2" || true
}

test_3470_sh_script() {
  local n bin="$TEST_DIR/t70-bin" fx="$TEST_DIR/t70/repo" nonode="$TEST_DIR/t70-nonode" t p want got
  GH_BIN="$bin"; SO="$TEST_DIR/t70.out"; SE="$TEST_DIR/t70.err"
  make_gh_stub "$bin"
  n="$(code_lines "$SH_SCRIPT" '#')"
  [[ "$n" -le 160 ]] || log_fail "TEST-3470: aai-release.sh has $n code lines, expected at most 160"
  for t in 'awk' 'perform_rollup' '## aai-release (plan)' 'CHANGELOG rollup (would write)'; do
    [[ "$(count_code_matches "$SH_SCRIPT" "$t")" == 0 ]] || log_fail "TEST-3470: aai-release.sh still holds '$t'"
  done
  [[ "$(count_code_matches "$SH_SCRIPT" 'release-cut.mjs')" == 3 ]] || log_fail "TEST-3470: aai-release.sh must call release-cut.mjs exactly three times"
  for t in plan check roll; do
    [[ "$(count_code_matches "$SH_SCRIPT" "release-cut.mjs\" $t ")" == 1 ]] || log_fail "TEST-3470: aai-release.sh must call release-cut.mjs $t once"
  done
  make_fixture_a "$fx"
  run_release sh "$fx"
  [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3470: the sh plan exited $RC"; }
  want="$(node "$MJS" plan --root "$fx" --version v9 --target-branch main --launcher sh)"
  got="$(cat "$SO")"
  [[ "$got" == "$want" && "$got" == "## aai-release (plan) — no files changed"* ]] || { printf '%s\n' "$got" >&2; log_fail "TEST-3470: the sh plan differs from the D-OUT plan of the module"; }
  [[ ! -s "$SE" ]] || log_fail "TEST-3470: the sh plan wrote stderr: $(cat "$SE")"
  mkdir -p "$nonode"
  for t in git dirname; do p="$(command -v "$t")"; ln -sf "$p" "$nonode/$t"; done
  cp "$bin/gh" "$nonode/gh"
  RC=0; ( cd "$fx" && PATH="$nonode" "$(command -v bash)" "$SH_SCRIPT" --version v9 ) >"$SO" 2>"$SE" || RC=$?
  [[ "$RC" == 20 && ! -s "$SO" && "$(cat "$SE")" == "$MISSING_NODE" ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3470: without node the sh script gave rc=$RC, not the missing-node line with exit 20"; }
  log_pass "TEST-3470: aai-release.sh is $n code lines, holds no rollup, calls the module three times, prints the plan and names a missing node"
}

test_3471_ps1_script() {
  need_tool TEST-3471 pwsh || return 0
  local n bin="$TEST_DIR/t71-bin" fx="$TEST_DIR/t71/repo" t want got
  GH_BIN="$bin"; SO="$TEST_DIR/t71.out"; SE="$TEST_DIR/t71.err"
  make_gh_stub "$bin"
  n="$(code_lines "$PS1_SCRIPT" '#')"
  [[ "$n" -le 220 ]] || log_fail "TEST-3471: aai-release.ps1 has $n code lines, expected at most 220"
  for t in 'Invoke-ChangelogRollup' 'aai-release (plan)' 'Resolved version' 'CHANGELOG rollup (would write)'; do
    [[ "$(count_code_matches "$PS1_SCRIPT" "$t")" == 0 ]] || log_fail "TEST-3471: aai-release.ps1 still holds '$t'"
  done
  local g=grep guard fn
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  guard="$("$g" -nF "if (\$MyInvocation.InvocationName -ne '.')" "$PS1_SCRIPT" | cut -d: -f1 | sed -n 1p)"
  [[ -n "$guard" ]] || log_fail "TEST-3471: the dot-source guard line is missing"
  for fn in Invoke-NativeChecked Select-CapturedValue; do
    t="$("$g" -nE "^function $fn " "$PS1_SCRIPT" | cut -d: -f1 | sed -n 1p)"
    [[ -n "$t" && "$t" -lt "$guard" ]] || log_fail "TEST-3471: $fn is not defined above the dot-source guard"
  done
  make_fixture_a "$fx"
  run_release ps1 "$fx" noremote
  [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3471: the ps1 plan exited $RC"; }
  want="$(node "$MJS" plan --root "$fx" --version v9 --target-branch main --launcher ps1 --no-remote)"
  [[ "$want" == *'- -NoRemote / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED' ]] || log_fail "TEST-3471: the expected ps1 plan does not carry the ps1 flag spelling"
  got="$(cat "$SO")"
  [[ "$got" == "$want" && "$got" == "## aai-release (plan) — no files changed"* ]] || { printf '%s\n' "$got" >&2; log_fail "TEST-3471: the ps1 plan differs from the D-OUT ps1 plan of the module"; }
  log_pass "TEST-3471: aai-release.ps1 is $n code lines, holds no rollup and prints the D-OUT ps1 plan"
}

test_3472_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3472: tests/skills/release-cut.Tests.ps1 does not exist"
  need_tool TEST-3472 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3472 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PROJECT_ROOT="$PROJECT_ROOT" pwsh -NoProfile -Command '
    $root = $env:PROJECT_ROOT
    $bad = 0
    foreach ($job in @(
      @{ File = "release-cut.Tests.ps1"; Filter = $null; Strict = $true },
      @{ File = "aai-win-dispatch.Tests.ps1"; Filter = "aai-release.ps1*"; Strict = $false },
      @{ File = "aai-release.Tests.ps1"; Filter = $null; Strict = $false })) {
      $cfg = New-PesterConfiguration
      $cfg.Run.Path = Join-Path $root ("tests/skills/" + $job.File)
      $cfg.Run.PassThru = $true
      $cfg.Output.Verbosity = "None"
      if ($job.Filter) { $cfg.Filter.FullName = $job.Filter }
      $r = Invoke-Pester -Configuration $cfg
      Write-Host "PESTER-RESULT: $($job.File) Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
      if ($r.FailedCount -gt 0) { $bad = 1 }
      if ($job.Strict -and ($r.SkippedCount -gt 0 -or $r.TotalCount -lt 5)) { $bad = 1 }
      if (-not $job.Strict -and $r.TotalCount -lt 1) { $bad = 1 }
    }
    exit $bad
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 60 >&2; log_fail "TEST-3472: a Pester file failed, skipped a case or ran fewer cases than required (rc=$rc)"; }
  log_pass "TEST-3472: release-cut.Tests.ps1 and the existing aai-release Pester cases pass under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p' | tr '\n' ';'))"
}

test_3473_downstream_install() {
  local tgt="$TEST_DIR/inst target" bin="$TEST_DIR/t73-bin" f
  GH_BIN="$bin"; SO="$TEST_DIR/t73.out"; SE="$TEST_DIR/t73.err"
  make_gh_stub "$bin"
  init_repo "$tgt"
  printf '# target\n' > "$tgt/README.md"
  git -C "$tgt" add -A; git -C "$tgt" commit -q -m init
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$tgt" --profile core >/dev/null 2>&1 || log_fail "TEST-3473: aai-sync.sh --profile core failed"
  for f in release-cut.mjs aai-release.sh aai-release.ps1 lib/release-rollup.mjs release-finish.mjs release-notes-gate.mjs; do
    [[ -f "$tgt/.aai/scripts/$f" ]] || log_fail "TEST-3473: the core install lacks .aai/scripts/$f"
  done
  printf '%s\n' '# Changelog' '' '## [unreleased] — feat: target thing' '' 'Body.' '' > "$tgt/CHANGELOG.md"
  git -C "$tgt" add -A; git -C "$tgt" commit -q -m 'chore: target changelog'
  RC=0; ( cd "$tgt" && PATH="$bin:$PATH" bash .aai/scripts/aai-release.sh --dry-run --no-remote --version v9 ) >"$SO" 2>"$SE" || RC=$?
  [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3473: the target's own sh script exited $RC"; }
  grep -qxF '  5:## [v9] — feat: target thing' "$SO" || { cat "$SO" >&2; log_fail "TEST-3473: the target's sh plan lacks the rolled heading line"; }
  if need_tool TEST-3473 pwsh; then
    RC=0; ( cd "$tgt" && PATH="$bin:$PATH" pwsh -NoProfile -NonInteractive -File .aai/scripts/aai-release.ps1 -DryRun -NoRemote -Version v9 ) >"$SO" 2>"$SE" || RC=$?
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3473: the target's own ps1 script exited $RC"; }
    grep -qxF '  5:## [v9] — feat: target thing' "$SO" || { cat "$SO" >&2; log_fail "TEST-3473: the target's ps1 plan lacks the rolled heading line"; }
  fi
  log_pass "TEST-3473: a core install holds the module and both scripts, and the target's own scripts print the plan"
}

# copiers: test files that copy aai-release.sh into a scratch tree (and so must copy release-cut.mjs too).
copier_problems() {
  local f g=grep out=""
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  for f in $("$g" -rlE "(cp|copyFileSync)[^|;&]*aai-release\\.sh|'aai-release\\.sh'," "$PROJECT_ROOT/tests" 2>/dev/null || true); do
    [[ "$f" == "$SCRIPT_DIR/test-aai-release-cut.sh" ]] && continue
    [[ "$f" == "$SCRIPT_DIR/lib/release-cut.test.mjs" ]] && continue
    "$g" -qF 'release-cut.mjs' "$f" || out="$out ${f#"$PROJECT_ROOT"/}"
  done
  printf '%s' "$out"
}

test_3474_callers() {
  local out rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-learned-routing.sh" test_002_release_names_unlogged_pr 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3474: test-aai-learned-routing.sh test_002_release_names_unlogged_pr exited $rc"; }
  rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-release.sh" test_031_unprotected_path_byte_identical 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3474: test-aai-release.sh test_031_unprotected_path_byte_identical exited $rc"; }
  out="$(copier_problems)"
  [[ -z "$out" ]] || log_fail "TEST-3474: these files copy aai-release.sh without release-cut.mjs:$out"
  rc=0
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3474: check-vendored-script-deps.mjs exited $rc"; }
  log_pass "TEST-3474: the existing callers keep working and every copier of aai-release.sh also copies the module"
}

test_3475_wiring() {
  local f out n pin wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" tsv="$PROJECT_ROOT/tests/skills/suite-weights.tsv" nsl="$PROJECT_ROOT/tests/skills/lib/nested-suite-lint.mjs"
  local hyg="$SCRIPT_DIR/test-aai-hygiene-pack.sh"
  for f in .aai/scripts/release-cut.mjs .aai/scripts/aai-release.sh .aai/scripts/aai-release.ps1 tests/skills/lib/release-cut.test.mjs tests/skills/test-aai-release-cut.sh tests/skills/release-cut.Tests.ps1; do
    out="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" == *'SELECTED aai-release-cut '* ]] || log_fail "TEST-3475: $f does not select aai-release-cut: $out"
  done
  out="$(printf '%s\n' .aai/scripts/release-cut.mjs | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
  [[ "$out" == *'SELECTED aai-release '* ]] || log_fail "TEST-3475: the module does not select aai-release: $out"
  n="$(awk -F'\t' '$1=="aai-release-cut" && $2==196{c++} END{print c+0}' "$tsv")"
  [[ "$n" == 1 ]] || log_fail "TEST-3475: suite-weights holds $n aai-release-cut rows at 196, expected 1"
  grep -qxF '# sample aai-release-cut fallback unsampled (new suite of release-on-node; no successful observation)' "$tsv" || log_fail "TEST-3475: suite-weights lacks the aai-release-cut fallback line"
  n="$(grep -cE '"\$row_count" -eq [0-9]+ \]\]' "$hyg" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3475: the hygiene pack holds $n literal row-count -eq lines, expected exactly 1"
  pin="$(grep -E '"\$row_count" -eq [0-9]+ \]\]' "$hyg" | sed -n 1p | sed 's/.*-eq \([0-9][0-9]*\) \]\].*/\1/')"
  n="$(grep -c '^  aai-[a-z0-9-]*:$' "$PROJECT_ROOT/tests/skills/suite-map.yaml" || true)"
  [[ "$pin" == "$n" ]] || log_fail "TEST-3475: the hygiene pin reads $pin but suite-map.yaml holds $n suite rows"
  for f in "$SCRIPT_DIR/test-aai-cloudflare-share.sh" "$SCRIPT_DIR/test-aai-pre-commit-checks.sh"; do
    ! grep -qE 'suite(-map\.yaml holds [^"]*)? rows, expected [0-9]+' "$f" || log_fail "TEST-3475: ${f##*/} still carries a literal suite-map row count"
  done
  for f in test_090_suite_map_pin test_129_mutation_gate_suite_registration; do
    env -u AAI_ROLE bash "$hyg" "$f" >/dev/null 2>&1 || log_fail "TEST-3475: test-aai-hygiene-pack.sh $f failed"
  done
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-cloudflare-share.sh" test_3428_wiring >/dev/null 2>&1 || log_fail "TEST-3475: test-aai-cloudflare-share.sh test_3428_wiring failed"
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-pre-commit-checks.sh" test_3458_wiring >/dev/null 2>&1 || log_fail "TEST-3475: test-aai-pre-commit-checks.sh test_3458_wiring failed"
  node "$nsl" --allowlist "$PROJECT_ROOT/tests/skills/lib/nested-suite-allowlist.tsv" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3475: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3475: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3475: check-test-registration.mjs failed"
  n="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - .aai/scripts/release-cut.mjs"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$n" == 1 ]] || log_fail "TEST-3475: PROFILES core lists the module $n times, expected 1"
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3475: test-aai-layer-profiles.sh test_manifest_conformance failed"
  n="$(awk '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0=="      - '"'"'.aai/scripts/release-cut.mjs'"'"'"{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
  [[ "$n" == "1 1" ]] || log_fail "TEST-3475: the ps1-quality path lists hold the module '$n' times (push pr), expected 1 1"
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-win-fallback.sh" test_034 >/dev/null 2>&1 || log_fail "TEST-3475: test-aai-win-fallback.sh test_034 failed"
  log_pass "TEST-3475: suite-map, weights, the single row-count pin, lints, PROFILES and both ps1-quality path lists are wired"
}

RFC17="${RCUT_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
CHANGELOG_FILE="${RCUT_CHANGELOG:-$PROJECT_ROOT/CHANGELOG.md}"

# rfc_problems <rfc>: problems with the aai-release inventory row and the phase 5 sentence (empty when clean).
rfc_problems() {
  node -e '
    const fs = require("fs");
    const text = fs.readFileSync(process.argv[1], "utf8");
    const bad = [];
    const row = text.split("\n").find((l) => l.startsWith("| `aai-release` |")) || "";
    if (!row.includes("release-cut.mjs")) bad.push("the aai-release inventory row does not name release-cut.mjs");
    const five = text.split("\n").find((l) => /^\| 5 \| /.test(l)) || "";
    if (!five.includes("| in progress |")) bad.push("the phase 5 row is not in progress");
    const sentence = /The tenth slice \[moved the release rollup to Node\]\(\.\.\/issues\/[A-Za-z0-9-]*release-on-node\.md\): the plan, the local cut and the remote finish roll CHANGELOG\.md through one transform, and the unlogged-PR check renders once; a later slice moves the tag, publish and PR steps to the platform adapter and deletes the twins\./g;
    const n = (text.match(sentence) || []).length;
    if (n !== 1) bad.push("the D-RFC sentence appears " + n + " times, expected once");
    if (!(five.match(sentence) || []).length) bad.push("the phase 5 row lacks the D-RFC sentence");
    process.stdout.write(bad.join("; "));
  ' "$1"
}

# preamble_problems <changelog>: the four exit-12 arms must be named before the first unreleased heading.
preamble_problems() {
  local pre="$TEST_DIR/preamble.txt" out="" t
  awk '/^## \[unreleased\]/{exit} {print}' "$1" > "$pre"
  for t in 'exit 12' 'scaffold with body text' 'trailing text' 'title or body is empty' 'not valid UTF-8'; do
    grep -qF -- "$t" "$pre" || out="$out; the preamble lacks '$t'"
  done
  printf '%s' "$out"
}

test_3476_rfc_and_preamble() {
  local out rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3476: test_2624_inventory_matches_tree exited $rc"; }
  out="$(rfc_problems "$RFC17")"
  [[ -z "$out" ]] || log_fail "TEST-3476: $out"
  sed 's/The tenth slice \[moved the release rollup to Node\]/The tenth slice [moved the release rollup]/' "$RFC17" > "$TEST_DIR/rfc-copy.md"
  out="$(rfc_problems "$TEST_DIR/rfc-copy.md")"
  [[ "$out" == *"D-RFC sentence"* ]] || log_fail "TEST-3476: positive control: an RFC without the sentence was not reported ($out)"
  out="$(preamble_problems "$CHANGELOG_FILE")"
  [[ -z "$out" ]] || log_fail "TEST-3476: ${out#; }"
  printf '%s\n' '# Changelog' '' 'aai-release enforces only the prefix.' '' '## [unreleased]' > "$TEST_DIR/cl-copy.md"
  out="$(preamble_problems "$TEST_DIR/cl-copy.md")"
  [[ "$out" == *"not valid UTF-8"* ]] || log_fail "TEST-3476: positive control: a preamble without the exit-12 arms was not reported"
  rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-release.sh" test_570_changelog_shape_is_documented 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3476: test_570_changelog_shape_is_documented exited $rc"; }
  log_pass "TEST-3476: the RFC-0017 inventory and phase 5 row and the CHANGELOG preamble state the release slice"
}

# budget_problems <dir>: problems with the two scripts' code-line budgets in a scripts directory (empty when within budget).
budget_problems() {
  local n out=""
  n="$(code_lines "$1/aai-release.sh" '#')"
  [[ "$n" -le 160 ]] || out="$out; aai-release.sh has $n code lines, expected at most 160"
  n="$(code_lines "$1/aai-release.ps1" '#')"
  [[ "$n" -le 220 ]] || out="$out; aai-release.ps1 has $n code lines, expected at most 220"
  printf '%s' "$out"
}

# exit_problems <module> <skill prompt>: every EXIT value of the module and the usage code 1 must be documented as exit N =.
exit_problems() {
  node -e '
    const fs = require("fs");
    const mod = fs.readFileSync(process.argv[1], "utf8");
    const doc = fs.readFileSync(process.argv[2], "utf8");
    const m = /const EXIT = \{([^}]*)\};/.exec(mod);
    const bad = [];
    if (!m) bad.push("the module has no EXIT constant");
    const codes = new Set([1, ...[...(m ? m[1] : "").matchAll(/:\s*(\d+)/g)].map((x) => Number(x[1]))]);
    for (const c of codes) if (!new RegExp("exit " + c + " = ").test(doc)) bad.push("exit " + c + " is not documented as exit " + c + " =");
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3477_line_budget() {
  local d="${RCUT_BUDGET_DIR:-$PROJECT_ROOT/.aai/scripts}" out sh ps1 mod before=641 after removed ctl="$TEST_DIR/t77-ctl" i
  out="$(budget_problems "$d")"
  [[ -z "$out" ]] || log_fail "TEST-3477: ${out#; }"
  mkdir -p "$ctl"; cp "$d/aai-release.sh" "$d/aai-release.ps1" "$ctl/"
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "echo extra line $i $(seq 1 25 | tr '\n' ' ')" >> "$ctl/aai-release.sh"; done
  for i in $(seq 1 70); do echo "echo extra $i" >> "$ctl/aai-release.sh"; done
  out="$(budget_problems "$ctl")"
  [[ "$out" == *"aai-release.sh has "* ]] || log_fail "TEST-3477: positive control: an oversized script was not reported"
  out="$(exit_problems "$MJS" "$PROJECT_ROOT/.aai/SKILL_RELEASE.prompt.md")"
  [[ -z "$out" ]] || log_fail "TEST-3477: $out"
  sh="$(code_lines "$d/aai-release.sh" '#')"; ps1="$(code_lines "$d/aai-release.ps1" '#')"; mod="$(code_lines "$MJS" '//')"
  after=$((sh + ps1)); removed=$((before - after))
  log_pass "TEST-3477: code lines before $before, after $after (sh $sh, ps1 $ps1), removed $removed, module $mod (JS: non-blank lines not starting with //; the # pattern would count its // comment lines too)"
}

test_3478_early_close() {
  run_node_tests TEST-3478
  log_pass "TEST-3478: a plan piped into head -1 ends quietly with exit 141"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3462..3478)"
  check_deps
  setup_fixture
  test_3462_seam
  test_3463_plan_contract
  test_3464_rollup_drift
  test_3465_plan_drift
  test_3466_files_and_launch
  test_3467_drift_coverage
  test_3468_one_transform
  test_3469_no_publish
  test_3470_sh_script
  test_3471_ps1_script
  test_3472_pester
  test_3473_downstream_install
  test_3474_callers
  test_3475_wiring
  test_3476_rfc_and_preamble
  test_3477_line_budget
  test_3478_early_close
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
