#!/usr/bin/env bash
#
# Test: aai-release-cut
# (docs/specs/SPEC-0281-spec-release-on-node.md, TEST-3462..3478;
#  docs/specs/SPEC-DRAFT-spec-release-publish-on-node.md, TEST-3520..3538)
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
AR_MJS="$PROJECT_ROOT/.aai/scripts/aai-release.mjs"
AR_TEST="${RCUT_AR_TEST:-$PROJECT_ROOT/tests/skills/lib/aai-release.test.mjs}"
AR_SPEC_ID="spec-release-publish-on-node"
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

# no_publish_matrix <TEST id>: the no-publish safety matrix through both launchers ($tid and TEST-3530).
no_publish_matrix() {
  local tid="$1"
  local kind fx origin pre words
  GH_BIN="$TEST_DIR/tnp-$tid-bin"; SO="$TEST_DIR/tnp-$tid.out"; SE="$TEST_DIR/tnp-$tid.err"
  make_gh_stub "$GH_BIN"
  for kind in sh ps1; do
    [[ "$kind" == sh ]] || need_tool "$tid" pwsh || continue
    mkdir -p "$TEST_DIR/tnp-$tid/$kind"
    fx="$TEST_DIR/tnp-$tid/$kind/repo"; origin="$TEST_DIR/tnp-$tid/$kind/origin.git"
    make_with_origin "$fx" "$origin" all
    : > "$GH_BIN/gh.log"
    pre="$(snap "$fx" "$origin")"
    for words in "" "dry" "dry confirm"; do
      # shellcheck disable=SC2086
      run_release "$kind" "$fx" $words
      [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "$tid: $kind ($words) exited $RC"; }
      [[ "$(snap "$fx" "$origin")" == "$pre" ]] || log_fail "$tid: $kind ($words) changed the repository or the origin"
      [[ -z "$(grep -vxF 'auth status' "$GH_BIN/gh.log" || true)" ]] || log_fail "$tid: $kind ($words) called gh beyond auth status: $(cat "$GH_BIN/gh.log")"
    done
    run_release "$kind" "$fx" confirm
    [[ "$RC" != 0 ]] || log_fail "$tid: $kind remote --confirm against a stub gh exited 0"
    grep -q '^REFUSED: ' "$SE" || { cat "$SE" >&2; log_fail "$tid: $kind remote --confirm printed no REFUSED line"; }
    grep -q '^Resume: ' "$SE" || { cat "$SE" >&2; log_fail "$tid: $kind remote --confirm printed no Resume line"; }
    [[ "$(snap "$fx" "$origin")" == "$pre" ]] || log_fail "$tid: $kind remote --confirm changed a ref or the working tree"
    fx="$TEST_DIR/tnp-$tid/$kind/cut"; origin="$TEST_DIR/tnp-$tid/$kind/cut-origin.git"
    make_with_origin "$fx" "$origin" all
    : > "$GH_BIN/gh.log"
    pre="$(git -C "$origin" show-ref)"
    run_release "$kind" "$fx" confirm noremote
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "$tid: $kind --confirm --no-remote exited $RC"; }
    [[ "$(git -C "$origin" show-ref)" == "$pre" ]] || log_fail "$tid: $kind --confirm --no-remote changed the origin refs"
    [[ ! -s "$GH_BIN/gh.log" ]] || log_fail "$tid: $kind --confirm --no-remote called gh: $(cat "$GH_BIN/gh.log")"
  done
}

test_3469_no_publish() {
  no_publish_matrix TEST-3469
  log_pass "TEST-3469: bare, dry-run and dry-run plus confirm write nothing; the local cut touches no remote; a remote confirm ends in the finish refusal"
}

test_3530_no_publish() {
  no_publish_matrix TEST-3530
  log_pass "TEST-3530: both launchers leave the origin untouched in every mode and end a remote confirm in a release-finish refusal"
}

# lines_of <file> <pattern>: number of code (non-comment) lines matching a fixed string.
count_code_matches() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -vE '^[[:space:]]*(#|$)' "$1" | "$g" -cF -- "$2" || true
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

# budget_problems <dir>: problems with the two launchers' code-line budgets in a scripts directory (empty when within budget).
budget_problems() {
  local n out=""
  n="$(code_lines "$1/aai-release.sh" '#')"
  [[ "$n" -le 12 ]] || out="$out; aai-release.sh has $n code lines, expected at most 12"
  n="$(code_lines "$1/aai-release.ps1" '#')"
  [[ "$n" -le 40 ]] || out="$out; aai-release.ps1 has $n code lines, expected at most 40"
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

test_3478_early_close() {
  run_node_tests TEST-3478
  log_pass "TEST-3478: a plan piped into head -1 ends quietly with exit 141"
}

# run_ar_tests <TEST id>: the aai-release node:test cases named with the id must pass; zero passing tests is a failure.
run_ar_tests() {
  local id="$1" out rc=0
  [[ -f "$AR_TEST" ]] || log_fail "$id: tests/skills/lib/aai-release.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$AR_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

test_3520_seam() {
  run_ar_tests TEST-3520
  log_pass "TEST-3520: importing aai-release.mjs has no side effect, run hands a remote confirm to finish and a bare run to the plan"
}

test_3521_argument_drift() {
  run_ar_tests TEST-3521
  log_pass "TEST-3521: DB-01 to DB-05 behave as decided"
}

test_3537_group_signal() {
  run_ar_tests TEST-3537
  log_pass "TEST-3537: a signal to the whole process group during a git step reports the interrupt, and the handlers are removed after the cut"
}

test_3538_no_origin() {
  run_ar_tests TEST-3538
  log_pass "TEST-3538: DB-20, a repository with no origin and no record blocks the plan and refuses release-platform"
}

# db_problems <spec> <node test file> <pester file>: DB ids of the D-DRIFT table vs test names (empty when they agree).
db_problems() {
  cat > "$TEST_DIR/db-drift.cjs" <<'JS'
const fs = require('fs');
const [spec, nodeTests, pester] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DB-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [
  ...fs.readFileSync(nodeTests, 'utf8').matchAll(/^test\('(?:TEST-\d+ )?(DB-\d\d)\b/gm),
  ...fs.readFileSync(pester, 'utf8').matchAll(/^\s*It '(DB-\d\d)\b/gm),
].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length !== 21) bad.push(`the table holds ${table.length} ids, expected 21`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/db-drift.cjs" "$1" "$2" "$3"
}

test_3522_local_cut_drift() {
  run_ar_tests TEST-3522
  log_pass "TEST-3522: DB-06 to DB-09, DB-11 and DB-14 behave as decided in committed temp repositories"
}

test_3528_sh_launcher() {
  local n mode t bin="$TEST_DIR/t28-bin" fx="$TEST_DIR/t28/repo" nonode="$TEST_DIR/t28-nonode" want got
  GH_BIN="$bin"; SO="$TEST_DIR/t28.out"; SE="$TEST_DIR/t28.err"
  make_gh_stub "$bin"
  n="$(code_lines "$SH_SCRIPT" '#')"
  [[ "$n" -le 12 ]] || log_fail "TEST-3528: aai-release.sh has $n code lines, expected at most 12"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/aai-release.sh | cut -d' ' -f1)"
  [[ "$mode" == 100755 ]] || log_fail "TEST-3528: aai-release.sh has index mode '$mode', expected 100755"
  for t in git gh CHANGELOG worktree AAI_RELEASE_DATE; do
    [[ "$(count_code_matches "$SH_SCRIPT" "$t")" == 0 ]] || log_fail "TEST-3528: aai-release.sh still holds '$t'"
  done
  [[ "$(count_code_matches "$SH_SCRIPT" 'exec node')" == 1 ]] || log_fail "TEST-3528: aai-release.sh must hold exactly one exec node line"
  [[ "$(count_code_matches "$SH_SCRIPT" 'aai-release.mjs')" -ge 1 && "$(count_code_matches "$SH_SCRIPT" '--launcher sh')" == 1 ]] || log_fail "TEST-3528: the exec line must name aai-release.mjs and --launcher sh"
  make_fixture_a "$fx"
  RC=0; ( cd "$fx" && PATH="$bin:$PATH" "$SH_SCRIPT" --dry-run --no-remote --version v9 ) >"$SO" 2>"$SE" || RC=$?
  [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3528: the direct sh plan exited $RC"; }
  want="$(node "$MJS" plan --root "$fx" --version v9 --target-branch main --launcher sh --no-remote)"
  got="$(cat "$SO")"
  [[ "$got" == "$want" && "$got" == "## aai-release (plan) — no files changed"* ]] || { printf '%s\n' "$got" >&2; log_fail "TEST-3528: the sh plan differs from the D-OUT plan of release-cut.mjs"; }
  [[ ! -s "$SE" ]] || log_fail "TEST-3528: the sh plan wrote stderr: $(cat "$SE")"
  mkdir -p "$nonode"
  RC=0; ( cd "$fx" && PATH="$nonode" "$(command -v bash)" "$SH_SCRIPT" --version v9 ) >"$SO" 2>"$SE" || RC=$?
  [[ "$RC" == 20 && ! -s "$SO" && "$(cat "$SE")" == "$MISSING_NODE" ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3528: without node the sh launcher gave rc=$RC, not the missing-node line with exit 20"; }
  log_pass "TEST-3528: aai-release.sh is $n code lines, mode $mode, holds no release logic, prints the plan and names a missing node"
}

test_3536_early_close() {
  run_ar_tests TEST-3536
  log_pass "TEST-3536: the sh launcher plan and usage end quietly when the reader closes early"
}

# parity_run <sh|ps1> <fixture> <env assignment or empty> <args...>: one launcher run; stdout in $SO, stderr in $SE, status in $RC.
parity_run() {
  local kind="$1" fx="$2" envs="$3"; shift 3
  RC=0
  if [[ "$kind" == sh ]]; then
    # shellcheck disable=SC2086
    ( cd "$fx" && env $envs PATH="$GH_BIN:$PATH" bash "$SH_SCRIPT" "$@" ) >"$SO" 2>"$SE" || RC=$?
  else
    # shellcheck disable=SC2086
    ( cd "$fx" && env $envs PATH="$GH_BIN:$PATH" pwsh -NoProfile -NonInteractive -File "$PS1_SCRIPT" "$@" ) >"$SO" 2>"$SE" || RC=$?
  fi
}

# ps1_spelling_to_sh <file> <fixture>: the ps1 flag spellings and the fixture path mapped to the sh ones.
ps1_spelling_to_sh() {
  sed -E -e 's/-NoRemote/--no-remote/g; s/-Confirm/--confirm/g; s/-DryRun/--dry-run/g; s/-Version/--version/g; s/-Yes/--yes/g; s/aai-release\.ps1/aai-release.sh/g' -e "s|$2|<FX>|g" -e 's/[0-9a-f]{40}/<SHA>/g; s/(Commit: +)[0-9a-f]{7,}/\1<SHORT>/' "$1"
}

test_3523_launcher_parity() {
  run_ar_tests TEST-3523
  need_tool TEST-3523 pwsh || return 0
  local label envs sh_args ps_args n=0 shfx psfx sh_out sh_err sh_rc ps_spelling
  local sh_flags_re='--(no-remote|confirm|dry-run)|aai-release\.sh'
  GH_BIN="$TEST_DIR/t23-bin"; SO="$TEST_DIR/t23.out"; SE="$TEST_DIR/t23.err"
  make_gh_stub "$GH_BIN"
  while IFS=';' read -r label envs sh_args ps_args; do
    [[ -n "$label" ]] || continue
    n=$((n + 1))
    shfx="$TEST_DIR/t23/$label/sh/repo"; psfx="$TEST_DIR/t23/$label/ps1/repo"
    mkdir -p "$TEST_DIR/t23/$label/sh" "$TEST_DIR/t23/$label/ps1"
    make_with_origin "$shfx" "$TEST_DIR/t23/$label/sh/origin.git" all
    make_with_origin "$psfx" "$TEST_DIR/t23/$label/ps1/origin.git" all
    # shellcheck disable=SC2086
    parity_run sh "$shfx" "$envs" $sh_args
    sh_rc=$RC; sh_out="$(sed -E -e "s|$shfx|<FX>|g" -e 's/[0-9a-f]{40}/<SHA>/g; s/(Commit: +)[0-9a-f]{7,}/\1<SHORT>/' "$SO")"; sh_err="$(sed "s|$shfx|<FX>|g" "$SE")"
    # shellcheck disable=SC2086
    parity_run ps1 "$psfx" "$envs" $ps_args
    [[ "$RC" == "$sh_rc" ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3523: '$label' exits $sh_rc under sh and $RC under ps1"; }
    # A captured variable and a bash regex, not a pipe into grep -q: an early-closing reader flips the upstream status under pipefail.
    ps_spelling="$(grep -hv '^Resume: node' "$SO" "$SE" || true)"
    [[ ! "$ps_spelling" =~ $sh_flags_re ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3523: '$label' prints the sh flag spelling under ps1"; }
    [[ "$(ps1_spelling_to_sh "$SO" "$psfx")" == "$sh_out" ]] || { diff <(printf '%s\n' "$sh_out") <(ps1_spelling_to_sh "$SO" "$psfx") >&2 || true; log_fail "TEST-3523: '$label' prints different stdout under sh and ps1"; }
    [[ "$(ps1_spelling_to_sh "$SE" "$psfx")" == "$sh_err" ]] || { diff <(printf '%s\n' "$sh_err") <(ps1_spelling_to_sh "$SE" "$psfx") >&2 || true; log_fail "TEST-3523: '$label' prints different stderr under sh and ps1"; }
  done <<'MATRIX'
bare;;;
dry;;--dry-run;-DryRun
version;;--version v9;-Version v9
versioneq;;--version=v9;--version=v9
yes;;--yes --version v9;-Yes -Version v9
dryconfirm;;--dry-run --confirm --version v9;-DryRun -Confirm -Version v9
help;;-h;-h
bogus;;--bogus;--bogus
date;AAI_RELEASE_DATE=2026-07-20;--dry-run;-DryRun
envnoremote;AAI_RELEASE_NO_REMOTE=1;--dry-run;-DryRun
confirmnoremote;;--confirm --no-remote --version v9;-Confirm -NoRemote -Version v9
MATRIX
  [[ "$n" == 11 ]] || log_fail "TEST-3523: the matrix ran $n invocations, expected 11"
  log_pass "TEST-3523: DB-12 and DB-13 pin the node side; the sh and ps1 launchers agree on stdout, stderr and exit code for $n invocations"
}

test_3529_ps1_launcher() {
  local n t g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  n="$(code_lines "$PS1_SCRIPT" '#')"
  [[ "$n" -le 40 ]] || log_fail "TEST-3529: aai-release.ps1 has $n code lines, expected at most 40"
  for t in Version DryRun Confirm Yes NoRemote ExtraArgs; do
    "$g" -qF "]\$$t" "$PS1_SCRIPT" || log_fail "TEST-3529: aai-release.ps1 lacks the param $t"
  done
  [[ "$(count_code_matches "$PS1_SCRIPT" "if (\$MyInvocation.InvocationName -ne '.')")" == 1 ]] || log_fail "TEST-3529: the dot-source guard is missing"
  for t in Invoke-NativeChecked Invoke-Quiet Select-CapturedValue ErrorActionPreference; do
    [[ "$(count_code_matches "$PS1_SCRIPT" "$t")" == 0 ]] || log_fail "TEST-3529: aai-release.ps1 still holds '$t'"
  done
  ! "$g" -vE '^[[:space:]]*(#|$)' "$PS1_SCRIPT" | "$g" -E '& node.*2>' >/dev/null || log_fail "TEST-3529: the node call redirects stderr"
  need_tool TEST-3529 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3529 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PROJECT_ROOT="$PROJECT_ROOT" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = Join-Path $env:PROJECT_ROOT "tests/skills/release-cut.Tests.ps1"
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "None"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 10) { exit 1 }
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 60 >&2; log_fail "TEST-3529: release-cut.Tests.ps1 failed, skipped a case or ran fewer than 10 cases (rc=$rc)"; }
  log_pass "TEST-3529: aai-release.ps1 is $n code lines with the six params and the guard, and release-cut.Tests.ps1 passes ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

test_3524_plan_platform() {
  run_ar_tests TEST-3524
  log_pass "TEST-3524: DB-15 and DB-16 and the two GitHub reasons shape the plan's publish-path block"
}

test_3525_release_host_argv() {
  run_ar_tests TEST-3525
  log_pass "TEST-3525: every release method of the github adapter spawns gh with its D-HOST argv and options; other platforms have no release group"
}

test_3526_finish_on_adapter() {
  local f="$PROJECT_ROOT/.aai/scripts/release-finish.mjs" g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  [[ "$("$g" -cE "command\\('gh'|spawnSync\\('gh'|function gh\\(|function json\\(" "$f" || true)" == 0 ]] || log_fail "TEST-3526: release-finish.mjs still spawns gh itself or holds a gh helper"
  "$g" -qF 'run=host?.checksRunner()' "$f" || log_fail "TEST-3526: release-finish.mjs does not hand the release checksRunner to readCurrentChecks"
  run_ar_tests TEST-3526
  log_pass "TEST-3526: release-finish.mjs makes its gh calls through the adapter and refuses non-GitHub platforms and mismatches by name before any host call"
}

test_3531_downstream_install() {
  local tgt="$TEST_DIR/inst3531 target" bin="$TEST_DIR/t31-bin" f
  GH_BIN="$bin"; SO="$TEST_DIR/t31.out"; SE="$TEST_DIR/t31.err"
  make_gh_stub "$bin"
  init_repo "$tgt"
  printf '# target\n' > "$tgt/README.md"
  git -C "$tgt" add -A; git -C "$tgt" commit -q -m init
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$tgt" --profile core >/dev/null 2>&1 || log_fail "TEST-3531: aai-sync.sh --profile core failed"
  for f in aai-release.mjs release-cut.mjs aai-release.sh aai-release.ps1 lib/platform-adapter.mjs pr-platform.mjs release-finish.mjs; do
    [[ -f "$tgt/.aai/scripts/$f" ]] || log_fail "TEST-3531: the core install lacks .aai/scripts/$f"
  done
  printf '%s\n' '# Changelog' '' '## [unreleased] — feat: target thing' '' 'Body.' '' > "$tgt/CHANGELOG.md"
  git -C "$tgt" add -A; git -C "$tgt" commit -q -m 'chore: target changelog'
  RC=0; ( cd "$tgt" && PATH="$bin:$PATH" bash .aai/scripts/aai-release.sh --dry-run --no-remote --version v9 ) >"$SO" 2>"$SE" || RC=$?
  [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3531: the target's own sh launcher exited $RC"; }
  grep -qxF '  5:## [v9] — feat: target thing' "$SO" || { cat "$SO" >&2; log_fail "TEST-3531: the target's sh plan lacks the rolled heading line"; }
  if need_tool TEST-3531 pwsh; then
    RC=0; ( cd "$tgt" && PATH="$bin:$PATH" pwsh -NoProfile -NonInteractive -File .aai/scripts/aai-release.ps1 -DryRun -NoRemote -Version v9 ) >"$SO" 2>"$SE" || RC=$?
    [[ "$RC" == 0 ]] || { cat "$SO" "$SE" >&2; log_fail "TEST-3531: the target's own ps1 launcher exited $RC"; }
    grep -qxF '  5:## [v9] — feat: target thing' "$SO" || { cat "$SO" >&2; log_fail "TEST-3531: the target's ps1 plan lacks the rolled heading line"; }
  fi
  log_pass "TEST-3531: a core install into a path with a space holds the seven files, and the target's own launchers print the plan"
}

# ar_copier_problems: test files that copy aai-release.sh into a scratch tree must also copy the module and the adapter.
ar_copier_problems() {
  local f g=grep out=""
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  for f in $("$g" -rlE "(cp|copyFileSync)[^|;&]*aai-release\\.sh|'aai-release\\.sh'," "$PROJECT_ROOT/tests" 2>/dev/null || true); do
    [[ "$f" == "$SCRIPT_DIR/test-aai-release-cut.sh" ]] && continue
    "$g" -qF 'aai-release.mjs' "$f" && "$g" -qF 'platform-adapter.mjs' "$f" || out="$out ${f#"$PROJECT_ROOT"/}"
  done
  printf '%s' "$out"
}

test_3532_callers() {
  local out rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-learned-routing.sh" test_002_release_names_unlogged_pr 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3532: test-aai-learned-routing.sh test_002_release_names_unlogged_pr exited $rc"; }
  rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-release.sh" test_019_ps1_flag_parity 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3532: test-aai-release.sh test_019_ps1_flag_parity exited $rc"; }
  [[ ! -e "$SCRIPT_DIR/aai-release.Tests.ps1" ]] || log_fail "TEST-3532: tests/skills/aai-release.Tests.ps1 still exists"
  ! grep -qE "^Describe '[^']*aai-release\\.ps1" "$SCRIPT_DIR/aai-win-dispatch.Tests.ps1" || log_fail "TEST-3532: aai-win-dispatch.Tests.ps1 still has an aai-release.ps1 Describe"
  out="$(ar_copier_problems)"
  [[ -z "$out" ]] || log_fail "TEST-3532: these files copy aai-release.sh without aai-release.mjs and lib/platform-adapter.mjs:$out"
  rc=0
  out="$(node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3532: check-vendored-script-deps.mjs exited $rc"; }
  log_pass "TEST-3532: the existing callers keep working, the deleted Pester files are gone and every copier also copies the module and the adapter"
}

test_3533_wiring() {
  local f out n pin wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" nsl="$PROJECT_ROOT/tests/skills/lib/nested-suite-lint.mjs" hyg="$SCRIPT_DIR/test-aai-hygiene-pack.sh" tool
  out="$(printf '%s\n' .aai/scripts/aai-release.mjs | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
  [[ "$out" == *'SELECTED aai-release-cut '* && "$out" == *'SELECTED aai-release '* ]] || log_fail "TEST-3533: aai-release.mjs does not select aai-release-cut and aai-release: $out"
  out="$(printf '%s\n' .aai/scripts/lib/platform-adapter.mjs | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
  [[ "$out" == *'SELECTED aai-release-cut '* || "$out" == FULL_RUN* ]] || log_fail "TEST-3533: lib/platform-adapter.mjs selects neither aai-release-cut nor the full run (a shared-lib path): $out"
  pin="$(grep -E '"\$row_count" -eq [0-9]+ \]\]' "$hyg" | sed -n 1p | sed 's/.*-eq \([0-9][0-9]*\) \]\].*/\1/')"
  n="$(grep -c '^  aai-[a-z0-9-]*:$' "$PROJECT_ROOT/tests/skills/suite-map.yaml" || true)"
  [[ "$pin" == "$n" ]] || log_fail "TEST-3533: the hygiene pin reads $pin but suite-map.yaml holds $n suite rows (a row was added or dropped)"
  env -u AAI_ROLE bash "$hyg" test_090_suite_map_pin >/dev/null 2>&1 || log_fail "TEST-3533: test-aai-hygiene-pack.sh test_090_suite_map_pin failed"
  node "$nsl" --allowlist "$PROJECT_ROOT/tests/skills/lib/nested-suite-allowlist.tsv" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3533: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3533: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$PROJECT_ROOT/tests/skills" >/dev/null 2>&1 || log_fail "TEST-3533: check-test-registration.mjs failed"
  n="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - .aai/scripts/aai-release.mjs"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$n" == 1 ]] || log_fail "TEST-3533: PROFILES core lists aai-release.mjs $n times, expected 1"
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3533: test-aai-layer-profiles.sh test_manifest_conformance failed"
  for tool in '.aai/scripts/aai-release.mjs' '.aai/scripts/lib/platform-adapter.mjs'; do
    n="$(awk -v want="      - '$tool'" '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0==want{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
    [[ "$n" == "1 1" ]] || log_fail "TEST-3533: the ps1-quality path lists hold $tool '$n' times (push pr), expected 1 1"
  done
  env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-win-fallback.sh" test_034 >/dev/null 2>&1 || log_fail "TEST-3533: test-aai-win-fallback.sh test_034 failed"
  log_pass "TEST-3533: select-suites, the unchanged suite-map row count, the lints, PROFILES and both ps1-quality path lists are wired"
}

# ar_rfc_problems <rfc> <after>: problems with the RFC-0017 pair table, the pair sentence and the phase 5 sentence (empty when clean).
ar_rfc_problems() {
  node -e '
    const fs = require("fs");
    const text = fs.readFileSync(process.argv[1], "utf8");
    const after = process.argv[2];
    const bad = [];
    if (text.split("\n").some((l) => l.startsWith("| `aai-release` |"))) bad.push("the pair table still has an aai-release row");
    const pair = /The \[release slices\]\(\.\.\/issues\/[A-Za-z0-9-]*release-publish-on-node\.md\) moved aai-release to Node modules with thin launchers \(pair 319 to (\d+) code lines\)\./g;
    const found = [...text.matchAll(pair)];
    if (found.length !== 1) bad.push("the pair sentence appears " + found.length + " times, expected once");
    else if (found[0][1] !== after) bad.push("the pair sentence says " + found[0][1] + " code lines, measured " + after);
    const five = text.split("\n").find((l) => /^\| 5 \| /.test(l)) || "";
    if (!five.includes("| in progress |")) bad.push("the phase 5 row is not in progress");
    const phase = /The eleventh slice \[ran the whole release command in Node\]\(\.\.\/issues\/[A-Za-z0-9-]*release-publish-on-node\.md\): aai-release\.sh and aai-release\.ps1 are thin launchers of aai-release\.mjs, and the release host calls run on the platform adapter\./g;
    if ((text.match(phase) || []).length !== 1) bad.push("the phase 5 sentence appears " + (text.match(phase) || []).length + " times, expected once");
    if (!(five.match(phase) || []).length) bad.push("the phase 5 row lacks the phase 5 sentence");
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3534_rfc_and_skill() {
  local out rc=0 prompt="$PROJECT_ROOT/.aai/SKILL_RELEASE.prompt.md" after bytes
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3534: test_2624_inventory_matches_tree exited $rc"; }
  after=$(( $(code_lines "$SH_SCRIPT" '#') + $(code_lines "$PS1_SCRIPT" '#') ))
  out="$(ar_rfc_problems "$RFC17" "$after")"
  [[ -z "$out" ]] || log_fail "TEST-3534: $out"
  sed 's/moved aai-release to Node modules with thin launchers/moved aai-release to Node modules/' "$RFC17" > "$TEST_DIR/rfc-copy34.md"
  out="$(ar_rfc_problems "$TEST_DIR/rfc-copy34.md" "$after")"
  [[ "$out" == *"pair sentence"* ]] || log_fail "TEST-3534: positive control: an RFC without the pair sentence was not reported ($out)"
  grep -qxF -- '- exit 14 = release branch exists with unmerged commits.' "$prompt" || log_fail "TEST-3534: SKILL_RELEASE lacks the exit 14 line"
  ! grep -q -- '^- exit 16 = ' "$prompt" || log_fail "TEST-3534: SKILL_RELEASE still has an exit 16 line"
  bytes="$(wc -c < "$prompt" | tr -d ' ')"
  [[ "$bytes" -le 4921 ]] || log_fail "TEST-3534: SKILL_RELEASE is $bytes bytes, expected at most 4921"
  rc=0
  out="$(env -u AAI_ROLE bash "$SCRIPT_DIR/test-aai-release.sh" test_034_exit_codes_documented 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3534: test_034_exit_codes_documented exited $rc"; }
  log_pass "TEST-3534: the RFC-0017 pair table and sentences and the SKILL_RELEASE exit-code line state the release slice ($bytes bytes)"
}

test_3535_line_budget() {
  local d="${RCUT_BUDGET_DIR:-$PROJECT_ROOT/.aai/scripts}" out sh ps1 mod before=319 after removed ctl="$TEST_DIR/t35-ctl" i
  out="$(budget_problems "$d")"
  [[ -z "$out" ]] || log_fail "TEST-3535: ${out#; }"
  mkdir -p "$ctl"; cp "$d/aai-release.sh" "$d/aai-release.ps1" "$ctl/"
  for i in $(seq 1 6); do echo "echo extra $i" >> "$ctl/aai-release.sh"; done
  for i in $(seq 1 20); do echo "Write-Host extra $i" >> "$ctl/aai-release.ps1"; done
  out="$(budget_problems "$ctl")"
  [[ "$out" == *"aai-release.sh has "* && "$out" == *"aai-release.ps1 has "* ]] || log_fail "TEST-3535: positive control: an oversized launcher was not reported ($out)"
  out="$(exit_problems "$AR_MJS" "$PROJECT_ROOT/.aai/SKILL_RELEASE.prompt.md")"
  [[ -z "$out" ]] || log_fail "TEST-3535: aai-release.mjs: $out"
  out="$(exit_problems "$MJS" "$PROJECT_ROOT/.aai/SKILL_RELEASE.prompt.md")"
  [[ -z "$out" ]] || log_fail "TEST-3535: release-cut.mjs: $out"
  sh="$(code_lines "$d/aai-release.sh" '#')"; ps1="$(code_lines "$d/aai-release.ps1" '#')"; mod="$(code_lines "$AR_MJS" '//')"
  after=$((sh + ps1)); removed=$((before - after))
  log_pass "TEST-3535: code lines before $before, after $after (sh $sh, ps1 $ps1), removed $removed, aai-release.mjs $mod (JS: non-blank lines not starting with //)"
}

test_3527_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $AR_SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3527: no spec with id $AR_SPEC_ID under docs/specs"
  [[ -f "$AR_TEST" ]] || log_fail "TEST-3527: tests/skills/lib/aai-release.test.mjs does not exist"
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3527: tests/skills/release-cut.Tests.ps1 does not exist"
  out="$(db_problems "$spec" "$AR_TEST" "$PESTER_FILE")"
  [[ -z "$out" ]] || log_fail "TEST-3527: $out"
  sed "s/'TEST-3522 DB-06 /'TEST-3522 DB-60 /" "$AR_TEST" > "$TEST_DIR/renamed-ar.test.mjs"
  out="$(db_problems "$spec" "$TEST_DIR/renamed-ar.test.mjs" "$PESTER_FILE")"
  [[ "$out" == *"DB-06 begins 0"* && "$out" == *"DB-60 is not in"* ]] || log_fail "TEST-3527: positive control: the renamed DB-06 was not reported ($out)"
  log_pass "TEST-3527: every D-DRIFT id begins exactly one test name and no name begins with a missing id"
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
  test_3473_downstream_install
  test_3474_callers
  test_3475_wiring
  test_3476_rfc_and_preamble
  test_3478_early_close
  test_3520_seam
  test_3521_argument_drift
  test_3527_drift_coverage
  test_3522_local_cut_drift
  test_3528_sh_launcher
  test_3529_ps1_launcher
  test_3523_launcher_parity
  test_3530_no_publish
  test_3524_plan_platform
  test_3525_release_host_argv
  test_3526_finish_on_adapter
  test_3531_downstream_install
  test_3532_callers
  test_3533_wiring
  test_3534_rfc_and_skill
  test_3535_line_budget
  test_3536_early_close
  test_3537_group_signal
  test_3538_no_origin
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
