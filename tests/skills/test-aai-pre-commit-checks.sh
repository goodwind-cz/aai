#!/usr/bin/env bash
#
# Test: aai-pre-commit-checks
# (docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md, TEST-3448..3461; the later cases TEST-3831..3868
# and TEST-3871..3882 belong to the staged-content and batched-read specs, TEST-3883..3887 to
# spec-precommit-sentinel-trap, TEST-3918..3922 to spec-precommit-residual-defects, TEST-4080..4104 to
# secrets-gate-false-positives)
#
# Two things: the PowerShell pre-commit checks are a deprecation launcher (one retired line
# naming pre-commit-checks.sh, exit 1), and the bash checks no longer pipe into an
# early-closing reader (a large STATE.yaml or a large debug list used to flip a decision).
# Every case works in fresh mktemp git fixtures; nothing touches the checkout's own hooks or STATE.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-pre-commit-checks.sh                      # run all
#   bash tests/skills/test-aai-pre-commit-checks.sh test_3451_large_state_check1_check5
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-pre-commit-checks"
SPEC_ID="spec-pre-commit-checks-ps1-retire"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH_CHECKS="$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/pre-commit-checks.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/pre-commit-checks-retired.Tests.ps1"
BASE_SHA="3e6b52d5"
GREP=/usr/bin/grep
[[ -x "$GREP" ]] || GREP=grep

# shellcheck source=lib/vendor-hook-installer.sh
. "$SCRIPT_DIR/lib/vendor-hook-installer.sh"
# shellcheck source=lib/git-env-scrub.sh
. "$SCRIPT_DIR/lib/git-env-scrub.sh"

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-pre-commit-checks-suite.XXXXXX")" && pwd -P)"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_fx <dir> [script]: a committed git repository with a local identity that carries the given
# pre-commit-checks.sh (default: the delivered one) at .aai/scripts/pre-commit-checks.sh.
make_fx() {
  local d="$1" script="${2:-$SH_CHECKS}"
  mkdir -p "$d/.aai/scripts" "$d/docs/ai"
  cp "$script" "$d/.aai/scripts/pre-commit-checks.sh"
  printf 'fixture\n' > "$d/README.txt"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config commit.gpgsign false
  git -C "$d" config core.autocrlf false
  git -C "$d" add -A
  git -C "$d" commit -q -m fixture
}

# run_checks <fixture> [args...]: runs the fixture's pre-commit-checks.sh; sets OUT, ERR, RC.
run_checks() {
  local fx="$1"; shift
  RC=0
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/pre-commit-checks.sh "$@" ) >"$TEST_DIR/run.out" 2>"$TEST_DIR/run.err" || RC=$?
  OUT="$TEST_DIR/run.out"; ERR="$TEST_DIR/run.err"
}

# count_in <file> <fixed text>: occurrences (lines) of the text in the file.
count_in() { "$GREP" -cF -- "$2" "$1" || true; }

# filler <n> <indent>: n deterministic filler lines (about 64 bytes each).
filler() {
  awk -v n="$1" -v ind="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%sfiller_%05d: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", ind, i }'
}

# write_state <fixture> <kind> <small|large>: kind = impl | valid | review_pass | review_not_run.
write_state() {
  local fx="$1" kind="$2" size="$3" n=6000 f="$1/docs/ai/STATE.yaml"
  [[ "$size" == small ]] && n=0
  case "$kind" in
    impl)  printf 'current_focus:\n  phase: implementation\nnotes:\n' > "$f"; filler "$n" "" >> "$f" ;;
    valid) printf 'current_focus:\n  phase: validation\nnotes:\n' > "$f"; filler "$n" "" >> "$f" ;;
    review_pass)    printf 'code_review:\n  required: true\n  status: pass\n' > "$f"; filler "$n" "  " >> "$f" ;;
    review_not_run) printf 'code_review:\n  required: true\n  status: not_run\n' > "$f"; filler "$n" "  " >> "$f" ;;
  esac
}

TDD_WARN="TDD cycle may be incomplete"
NO_IMPL="No active implementation phase"
NO_REPORT="No validation report found"
REVIEW_OK="Code review gate satisfied"
REVIEW_WARN="Code review required but not pass/waived"

# state_case <TEST id> <kind> <want present text> <want absent text> [args...]: the small twin and the
# large STATE each decide the same way.
state_case() {
  local id="$1" kind="$2" want="$3" unwant="$4" size fx
  shift 4
  for size in small large; do
    fx="$TEST_DIR/$id-$kind-$size"
    make_fx "$fx"
    write_state "$fx" "$kind" "$size"
    if [[ "$size" == large ]]; then
      [[ "$(wc -c < "$fx/docs/ai/STATE.yaml")" -ge 300000 ]] || log_fail "$id: the large $kind STATE.yaml is under 300000 bytes"
    fi
    run_checks "$fx" "$@"
    [[ "$(count_in "$OUT" "$want")" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: the $size $kind STATE.yaml did not print '$want' exactly once"; }
    if [[ -n "$unwant" ]]; then
      [[ "$(count_in "$OUT" "$unwant")" == 0 ]] || { cat "$OUT" >&2; log_fail "$id: the $size $kind STATE.yaml printed '$unwant'"; }
    fi
  done
}

test_3451_large_state_check1_check5() {
  state_case TEST-3451 impl "$TDD_WARN" "$NO_IMPL"
  state_case TEST-3451 valid "$NO_REPORT" ""
  log_pass "TEST-3451: CHECK 1 and CHECK 5 decide a 380 KB STATE.yaml exactly as its two-line twin (TDD warning, missing validation report)"
}

test_3452_large_code_review_block() {
  local fx
  state_case TEST-3452 review_pass "$REVIEW_OK" "$REVIEW_WARN"
  state_case TEST-3452 review_not_run "$REVIEW_WARN" "$REVIEW_OK"
  fx="$TEST_DIR/t3452-strict"
  make_fx "$fx"
  write_state "$fx" review_not_run large
  run_checks "$fx" --strict
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3452: --strict on the large not_run code_review block exited $RC, expected 1"; }
  log_pass "TEST-3452: CHECK 6 decides a 380 KB code_review block as its small twin and --strict blocks on not_run"
}

test_3453_large_debug_list() {
  local fx="$TEST_DIR/t3453" lines head_before
  make_fx "$fx"
  awk 'BEGIN { for (i = 1; i <= 20000; i++) printf "console.log(\"debug line %d\");\n", i }' > "$fx/app.js"
  git -C "$fx" add app.js
  run_checks "$fx"
  [[ "$RC" == 0 ]] || { tail -5 "$OUT" >&2; log_fail "TEST-3453: the script exited $RC on 20000 debug lines, expected 0"; }
  [[ "$(count_in "$OUT" "Debug statements in app.js:")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3453: the debug warning for app.js is missing"; }
  lines="$(awk '/Debug statements in app.js:/{f=1; next} f && /^    /{c++; next} f{exit} END{print c+0}' "$OUT")"
  [[ "$lines" == 3 ]] || { cat "$OUT" >&2; log_fail "TEST-3453: expected exactly 3 indented match lines, saw $lines"; }
  "$GREP" -q 'PASS WITH WARNINGS' "$OUT" || { cat "$OUT" >&2; log_fail "TEST-3453: the summary line is missing (checks 4 to 9 never ran)"; }
  # Through a real installed hook: the commit must be created.
  vendor_hook_installer "$fx" sh
  aai_assert_hooks_under "$fx" "$TEST_DIR" || log_fail "TEST-3453: the hooks path of $fx lies outside the scratch root"
  ( cd "$fx" && aai_git_scrubbed bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/inst.out" 2>&1 || { cat "$TEST_DIR/inst.out" >&2; log_fail "TEST-3453: the hook installer failed"; }
  git -C "$fx" checkout -q -b work   # the installed ref guard refuses refs/heads/main writes
  head_before="$(git -C "$fx" rev-parse HEAD)"
  RC=0
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m x ) >"$TEST_DIR/commit.out" 2>&1 || RC=$?
  [[ "$RC" == 0 ]] || { cat "$TEST_DIR/commit.out" >&2; log_fail "TEST-3453: git commit through the installed hook exited $RC"; }
  [[ "$(git -C "$fx" rev-parse HEAD)" != "$head_before" ]] || log_fail "TEST-3453: HEAD did not move"
  log_pass "TEST-3453: 20000 debug lines print the warning with 3 match lines, reach the summary and the hook lets the commit through"
}

# base_script: writes the baseline pre-commit-checks.sh (git show) to a file and prints its path;
# prints nothing when the baseline commit is not in this clone (named SKIP-CASE locally, FAIL on CI).
base_script() {
  local out="$TEST_DIR/base-pre-commit-checks.sh"
  if [[ ! -s "$out" ]]; then
    git -C "$PROJECT_ROOT" show "$BASE_SHA:.aai/scripts/pre-commit-checks.sh" > "$out" 2>/dev/null || rm -f "$out"
  fi
  [[ -s "$out" ]] && printf '%s\n' "$out"
  return 0
}

# parity_fixture <name> <kind>: a small fixture for one Spec-AC-07 shape; prints its path.
parity_fixture() {
  local fx="$TEST_DIR/par-$1"
  make_fx "$fx"
  case "$2" in
    impl)       write_state "$fx" impl small ;;
    impl_pass)  printf 'current_focus:\n  phase: implementation\nlast_validation:\n  status: pass\n' > "$fx/docs/ai/STATE.yaml" ;;
    debug5)     awk 'BEGIN { for (i = 1; i <= 5; i++) printf "console.log(%d);\n", i }' > "$fx/app.js"; git -C "$fx" add app.js ;;
    valid)      write_state "$fx" valid small ;;
    valid_rep)  write_state "$fx" valid small; mkdir -p "$fx/docs/ai/reports"; : > "$fx/docs/ai/reports/LATEST.md" ;;
    rev_pass)   write_state "$fx" review_pass small ;;
    rev_not_run) write_state "$fx" review_not_run small ;;
  esac
  printf '%s\n' "$fx"
}

test_3454_small_input_parity() {
  local base fx kind rc_new rc_old numstat
  base="$(base_script)"
  if [[ -z "$base" ]]; then
    [[ -z "${CI:-}" ]] || log_fail "TEST-3454: baseline commit $BASE_SHA is not in this clone on CI"
    echo "SKIP-CASE: TEST-3454 needs commit $BASE_SHA in this clone"
    return 0
  fi
  for kind in impl impl_pass debug5 valid valid_rep rev_pass rev_not_run; do
    fx="$(parity_fixture "$kind" "$kind")"
    ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/pre-commit-checks.sh ) >"$TEST_DIR/new.out" 2>"$TEST_DIR/new.err" && rc_new=0 || rc_new=$?
    ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$base" ) >"$TEST_DIR/old.out" 2>"$TEST_DIR/old.err" && rc_old=0 || rc_old=$?
    [[ "$rc_new" == "$rc_old" ]] || log_fail "TEST-3454: $kind exit code $rc_new differs from the baseline $rc_old"
    cmp -s "$TEST_DIR/new.out" "$TEST_DIR/old.out" || { diff "$TEST_DIR/old.out" "$TEST_DIR/new.out" >&2 || true; log_fail "TEST-3454: $kind stdout differs from the baseline"; }
    cmp -s "$TEST_DIR/new.err" "$TEST_DIR/old.err" || log_fail "TEST-3454: $kind stderr differs from the baseline"
  done
  numstat="$(git -C "$PROJECT_ROOT" diff --numstat "$BASE_SHA" -- .aai/scripts/pre-commit-checks.sh | awk '{print $1" "$2}')"
  # 7 7 from the pipe-safe slice, then +12 -4 from pr-ceremony-friction-fixes (CHECK 2: staged-blob
  # content scan, evidence-folder name check), then +20 -18 from hook-gate-staged-content (NUL-separated
  # staged list, index-existence test, staged-blob reads in CHECKs 2-4, *.env override), then +82 -1 from
  # precommit-blob-read-cost (one batched index read with its fail-closed parser), then +17 -0 from its
  # VALIDATION r1 B1 fix (the list read is still attempted outside a work tree), then -6 -0 from its
  # VALIDATION r2 B2 fix (one `git rev-parse --git-dir` predicate), then +47 -0 from its
  # VALIDATION r3 B3 fix, then +8 -0 from its VALIDATION r4 remediation (leading-zero and length checks on the
  # size, the parse-completed sentinel, the trap closing descriptors 3 and 4 for rm), then +5 -0 from
  # precommit-sentinel-trap (PCC_PARSED set to 0, the sentinel keyed on IN_REPO, the CHECK 4 skip-list comment),
  # then +50 -9 from precommit-residual-defects (the read-and-count loop with one re-read, a pipe probe before the batch read, STATE matched in the
  # shell, line lists walked by parameter expansion, tools looked up in a subshell);
  # then +1 -1 from node-first-leftovers (D-BOM: the doc_number_guard grep accepts an optional leading BOM);
  # the seven fixtures above stay byte-identical;
  # then +620 -42 in total after secrets-gate-false-positives (CHECK 2 rewritten: value-shape rules, key-file and NUL name block, the
  # reviewed allowlist read from the index, fingerprints; the awk programs and their grep prefilter),
  # then +45 -0 from its VALIDATION r1 remediation (NUL-free awk copy of a blob, R5 real-dotenv rule, bracket-only catch-all globs),
  # then +101 -0 from its VALIDATION r3 remediation (inline private key markers, R6 any-key judging in name-hit files, bracket expression parser)
  [[ "$numstat" == "767 42" ]] || log_fail "TEST-3454 (TEST-3877 pin): git diff --numstat $BASE_SHA on the script reads '$numstat', expected '767 42'"
  log_pass "TEST-3454: seven small fixtures give the baseline's stdout, stderr and exit code, and the script differs from it in exactly 767 added and 42 removed lines"
}

# shipping_sites <file or - for stdin>: PGQ_PATTERN matches on non-comment lines.
shipping_sites() {
  { "$GREP" -vE '^[[:space:]]*#' || true; } | { "$GREP" -cE "$PGQ_PATTERN" || true; }
}

test_3455_ratchet_counts_the_file() {
  local lib="$SCRIPT_DIR/lib/pipe-grep-q-ratchet.sh" n total base
  [[ -f "$lib" ]] || log_fail "TEST-3455: $lib is missing"
  # shellcheck source=lib/pipe-grep-q-ratchet.sh
  . "$lib"
  n="$(shipping_sites < "$SH_CHECKS")"
  [[ "$n" == 0 ]] || log_fail "TEST-3455: PGQ_PATTERN matches $n non-comment line(s) of pre-commit-checks.sh, expected 0"
  base="$(base_script)"
  if [[ -n "$base" ]]; then
    n="$(shipping_sites < "$base")"
    [[ "$n" == 7 ]] || log_fail "TEST-3455: positive control: the baseline script reads $n sites, expected 7"
  elif [[ -n "${CI:-}" ]]; then
    log_fail "TEST-3455: baseline commit $BASE_SHA is not in this clone on CI"
  else
    echo "SKIP-CASE: TEST-3455 positive control needs commit $BASE_SHA in this clone"
  fi
  if "$GREP" -q 'PGQ_SHIPPING_DEFERRED_L3' "$lib"; then log_fail "TEST-3455: the ratchet lib still holds PGQ_SHIPPING_DEFERRED_L3"; fi
  total="$(pgq_total "$(pgq_scan_shipping "$PROJECT_ROOT")")"
  [[ "$total" == 0 ]] || log_fail "TEST-3455: pgq_scan_shipping totals $total, expected 0"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-hygiene-pack.sh" test_128_shipping_scripts_pipe_safe_at_zero >"$TEST_DIR/h128.out" 2>&1 || { cat "$TEST_DIR/h128.out" >&2; log_fail "TEST-3455: hygiene-pack test_128 failed"; }
  log_pass "TEST-3455: the ratchet counts pre-commit-checks.sh (0 sites now, 7 in the baseline) and hygiene-pack test_128 gates it at zero"
}

D_LAUNCH='pre-commit-checks.ps1: retired - the PowerShell pre-commit checks are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: bash .aai/scripts/pre-commit-checks.sh (the installed hooks already run it); nothing was checked'

test_3448_ps1_retired_run() {
  need_tool TEST-3448 pwsh || return 0
  local fx="$TEST_DIR/ps1 fx" so="$TEST_DIR/p.out" se="$TEST_DIR/p.err" before_status before_index rc variant
  make_fx "$fx"
  printf "%s = '%s'\n" api_key abcdefgh1234 > "$fx/config.txt"   # assembled so this file does not trip CHECK 2 itself
  git -C "$fx" add config.txt
  before_status="$(git -C "$fx" status --porcelain)"
  before_index="$(git -C "$fx" diff --cached --name-only)"
  for variant in none strict strict_extra; do
    rc=0
    case "$variant" in
      none) ( cd "$fx" && pwsh -NoProfile -File "$PS1_LAUNCHER" ) >"$so" 2>"$se" || rc=$? ;;
      strict) ( cd "$fx" && pwsh -NoProfile -File "$PS1_LAUNCHER" -Strict ) >"$so" 2>"$se" || rc=$? ;;
      strict_extra) ( cd "$fx" && pwsh -NoProfile -File "$PS1_LAUNCHER" -Strict extra ) >"$so" 2>"$se" || rc=$? ;;
    esac
    [[ "$rc" == 1 ]] || log_fail "TEST-3448: the launcher ($variant) exited $rc, expected 1"
    [[ ! -s "$so" ]] || log_fail "TEST-3448: the launcher ($variant) wrote to stdout: $(cat "$so")"
    [[ "$(cat "$se")" == "$D_LAUNCH" ]] || log_fail "TEST-3448: the launcher ($variant) stderr was: $(cat "$se")"
    [[ "$(git -C "$fx" status --porcelain)" == "$before_status" ]] || log_fail "TEST-3448: the launcher ($variant) changed git status"
    [[ "$(git -C "$fx" diff --cached --name-only)" == "$before_index" ]] || log_fail "TEST-3448: the launcher ($variant) changed the staged index"
  done
  log_pass "TEST-3448: the launcher prints the D-LAUNCH line, exits 1 and leaves status and index untouched for no argument, -Strict and -Strict extra"
}

test_3449_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3449: tests/skills/pre-commit-checks-retired.Tests.ps1 does not exist"
  need_tool TEST-3449 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3449 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
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
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3449: pre-commit-checks-retired.Tests.ps1 failed, skipped a case or ran fewer than 3 cases (rc=$rc)"; }
  log_pass "TEST-3449: pre-commit-checks-retired.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# launcher_problems <file> <D-LAUNCH line>: prints the problems of the launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, want] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    const lines = s.split("\n").length - (s.endsWith("\n") ? 1 : 0);
    if (lines > 5) bad.push("more than 5 lines (" + lines + ")");
    const marks = s.split(/\r?\n/).filter((l) => l.startsWith("# RETIRED (RFC-0017 phase 5, pre-commit-checks-ps1-retire)"));
    if (marks.length !== 1) bad.push("RETIRED comment lines: " + marks.length);
    if (!s.includes(want)) bad.push("D-LAUNCH line text missing");
    const last = s.split(/\r?\n/).filter((l) => l.trim() !== "").pop();
    if (last !== "exit 1") bad.push("last line is not exit 1");
    if (/param\s*\(/i.test(s)) bad.push("holds a param block");
    const w = s.match(/\b(node|pwsh|git|param|Write-Host|Write-Error|Invoke-\w+|Start-Process|STATE|cp|rm|mv|mkdir)\b/);
    if (w) bad.push("names " + w[0]);
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3450_launcher_thin() {
  local out mode ctl="$TEST_DIR/ctl-retired.ps1"
  [[ -f "$PS1_LAUNCHER" ]] || log_fail "TEST-3450: pre-commit-checks.ps1 does not exist"
  out="$(launcher_problems "$PS1_LAUNCHER" "$D_LAUNCH")"
  [[ -z "$out" ]] || log_fail "TEST-3450: pre-commit-checks.ps1: $out"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/pre-commit-checks.ps1 | cut -d' ' -f1)"
  [[ "$mode" == 100644 ]] || log_fail "TEST-3450: pre-commit-checks.ps1 git mode is '$mode', not 100644"
  sed 's/^exit 1$/Write-Host done; exit 1/' "$PS1_LAUNCHER" > "$ctl"
  out="$(launcher_problems "$ctl" "$D_LAUNCH")"
  [[ "$out" == *"Write-Host"* ]] || log_fail "TEST-3450: positive control: a launcher holding Write-Host was not reported (got: $out)"
  log_pass "TEST-3450: the launcher is at most 5 lines, ASCII, mode 100644, carries one RETIRED comment and the D-LAUNCH line, ends in exit 1 and names no tool"
}

# ps1_refs <root> <newline list of tracked files>: lines (path:line) naming pre-commit-checks.ps1 or a
# sh-and-ps1 spelling of the name (braces, slash or "or") outside the allowlist: the launcher, PROFILES.yaml,
# the WORKFLOW.md protected-surface line and a protected_paths_l3 entry of the two docs-audit files.
ps1_refs() {
  node -e '
    const fs = require("fs");
    const [root, list] = process.argv.slice(1);
    const name = /pre-commit-checks\.(ps1|\{sh,ps1\}|sh`?(\/| or )`?\.ps1)/;
    const pathOk = new Set([".aai/scripts/pre-commit-checks.ps1", ".aai/system/PROFILES.yaml"]);
    const shapes = {
      ".aai/workflow/WORKFLOW.md": /^- guards: \.aai\/scripts\/pre-commit-checks\.sh, \.aai\/scripts\/pre-commit-checks\.ps1$/,
      "docs/ai/docs-audit.yaml": /^  - \.aai\/scripts\/pre-commit-checks\.ps1$/,
      ".aai/templates/docs-audit.template.yaml": /^  - \.aai\/scripts\/pre-commit-checks\.ps1$/,
    };
    const keepDocs = new Set(["docs/TECHNOLOGY.md", "docs/ai/docs-audit.yaml"]);
    const out = [];
    for (const f of list.split("\n").filter(Boolean)) {
      if ((f.startsWith("docs/") && !keepDocs.has(f)) || f.startsWith("tests/") || f === "CHANGELOG.md" || pathOk.has(f)) continue;
      let t; try { t = fs.readFileSync(root + "/" + f, "utf8"); } catch { continue; }
      t.split("\n").forEach((l, i) => { if (name.test(l) && !(shapes[f] && shapes[f].test(l))) out.push(f + ":" + (i + 1)); });
    }
    process.stdout.write(out.join(" "));
  ' "$1" "$2"
}

test_3456_no_live_ps1_reference() {
  local files out agents="$PROJECT_ROOT/.aai/AGENTS.md" ctl="$TEST_DIR/ctl-root"
  files="$(git -C "$PROJECT_ROOT" ls-files)"
  out="$(ps1_refs "$PROJECT_ROOT" "$files")"
  [[ -z "$out" ]] || log_fail "TEST-3456: live files still name the PowerShell pre-commit checks: $out"
  mkdir -p "$ctl/docs"
  printf '  - Pre-commit quality gates run via `.aai/scripts/pre-commit-checks.sh`/`.ps1`\n' > "$ctl/docs/TECHNOLOGY.md"
  out="$(ps1_refs "$ctl" "docs/TECHNOLOGY.md")"
  [[ "$out" == *docs/TECHNOLOGY.md* ]] || log_fail "TEST-3456: positive control: the old TECHNOLOGY.md line was not reported (got: $out)"
  "$GREP" -qxF 'Before committing, run quality gate checks (`.aai/scripts/pre-commit-checks.sh`):' "$agents" || log_fail "TEST-3456: AGENTS.md lacks the D-REF line"
  log_pass "TEST-3456: no live file names the PowerShell pre-commit checks outside the launcher, PROFILES and the protected-path lines, and AGENTS.md holds the D-REF line"
}

test_3457_suites_stop_running_the_ps1() {
  local f hits="" sel
  for f in $(git -C "$PROJECT_ROOT" ls-files tests/skills); do
    case "$f" in
      tests/skills/test-aai-pre-commit-checks.sh|tests/skills/pre-commit-checks-retired.Tests.ps1) continue ;;
    esac
    if "$GREP" -qF 'pre-commit-checks.ps1' "$PROJECT_ROOT/$f" 2>/dev/null; then hits="$hits $f"; fi
  done
  [[ -z "$hits" ]] || log_fail "TEST-3457: tests/skills files still name pre-commit-checks.ps1:$hits"
  if "$GREP" -q '^test_809_check8_ps1_twin()' "$SCRIPT_DIR/test-aai-doc-numbering.sh"; then log_fail "TEST-3457: test_809_check8_ps1_twin still exists"; fi
  if "$GREP" -q '^test_1708_precommit_ps1_parity()' "$SCRIPT_DIR/test-aai-tracked-ignored.sh"; then log_fail "TEST-3457: test_1708_precommit_ps1_parity still exists"; fi
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" >"$TEST_DIR/reg.out" 2>&1 || { cat "$TEST_DIR/reg.out" >&2; log_fail "TEST-3457: check-test-registration.mjs failed"; }
  for sel in "test-aai-doc-numbering.sh test_808_check8_enforce_is_merge_point_aware" \
    "test-aai-tracked-ignored.sh test_1706_precommit_sh_refuses_added_ignored_path" "test-aai-tracked-ignored.sh test_1707_precommit_sh_cells" \
    "test-aai-suite-select.sh test_1737_real_map_gitignore_full_and_guard_scripts_select"; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/${sel% *}" "${sel#* }" >"$TEST_DIR/sel.out" 2>&1 || { tail -15 "$TEST_DIR/sel.out" >&2; log_fail "TEST-3457: ${sel% *} ${sel#* } failed"; }
  done
  log_pass "TEST-3457: no suite runs the PowerShell checks any more, the two twin cells are gone and the registration check is clean"
}

selected_for() {
  printf '%s\n' "$1" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT"
}

# row_globs <suite name>: the glob lines of one suite-map row.
row_globs() {
  awk -v want="  $1:" '$0 == want {f=1; next} f && /^  [a-z0-9][a-z0-9-]*:$/ {exit} f' "$SCRIPT_DIR/suite-map.yaml"
}

test_3458_wiring() {
  local f out n row_n wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" tsv="$SCRIPT_DIR/suite-weights.tsv" nsl="$SCRIPT_DIR/lib/nested-suite-lint.mjs" g sel
  for f in tests/skills/test-aai-pre-commit-checks.sh tests/skills/pre-commit-checks-retired.Tests.ps1 tests/skills/lib/pipe-grep-q-ratchet.sh; do
    out="$(selected_for "$f")"
    [[ "$out" == *'SELECTED aai-pre-commit-checks '* ]] || log_fail "TEST-3458: $f does not select aai-pre-commit-checks: $out"
  done
  for f in .aai/scripts/pre-commit-checks.sh .aai/scripts/pre-commit-checks.ps1; do
    out="$(selected_for "$f")"
    [[ "$out" == *'FULL_RUN reason=protected-l3'* ]] || log_fail "TEST-3458: $f is not FULL_RUN protected-l3: $out"
  done
  for g in aai-doc-numbering aai-tracked-ignored; do
    if "$GREP" -qF 'pre-commit-checks.ps1' <<< "$(row_globs "$g")"; then log_fail "TEST-3458: the $g row still globs pre-commit-checks.ps1"; fi
  done
  "$GREP" -qxF '      - tests/skills/pre-commit-checks-retired.Tests.ps1' <<< "$(row_globs aai-pre-commit-checks)" || log_fail "TEST-3458: the aai-pre-commit-checks row lacks the Pester glob"
  n="$(awk -F'\t' '$1=="aai-pre-commit-checks"{c++; w=$2} END{print c+0 ":" w}' "$tsv")"
  [[ "$n" =~ ^1:[1-9][0-9]*$ ]] || log_fail "TEST-3458: suite-weights holds aai-pre-commit-checks as '$n' (rows:weight), expected one positive-integer row"
  "$GREP" -qE '^# sample aai-pre-commit-checks (measured|fallback unsampled)' "$tsv" || log_fail "TEST-3458: suite-weights lacks the aai-pre-commit-checks sample line"
  [[ "$("$GREP" -cE '"\$row_count" -eq [0-9]+ \]\]' "$SCRIPT_DIR/test-aai-hygiene-pack.sh" || true)" == 1 ]] || log_fail "TEST-3458: the hygiene pack does not hold exactly one literal row-count -eq line"
  for sel in test_090_suite_map_pin test_129_mutation_gate_suite_registration test_133_nested_suite_lint_live_and_base; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-hygiene-pack.sh" "$sel" >"$TEST_DIR/w.out" 2>&1 || { tail -8 "$TEST_DIR/w.out" >&2; log_fail "TEST-3458: test-aai-hygiene-pack.sh $sel failed"; }
  done
  node "$nsl" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3458: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3458: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3458: check-test-registration.mjs failed"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-win-fallback.sh" test_034 >/dev/null 2>&1 || log_fail "TEST-3458: test-aai-win-fallback.sh test_034 failed"
  for sel in test_010_audit_and_reduction test_012_growth_sum_matches_ledger test_746_roadmap_takes_direction_growth_ledgered test_769_agents_md_ceiling; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-prompt-diet.sh" "$sel" >"$TEST_DIR/pd.out" 2>&1 || { tail -8 "$TEST_DIR/pd.out" >&2; log_fail "TEST-3458: test-aai-prompt-diet.sh $sel failed"; }
  done
  for g in "'.aai/scripts/**.ps1'" "'tests/skills/*.Tests.ps1'"; do
    n="$(awk -v want="      - $g" '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0==want{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
    [[ "$n" == "1 1" ]] || log_fail "TEST-3458: the ps1-quality path lists hold $g '$n' times (push pr), expected 1 1"
  done
  log_pass "TEST-3458: select-suites, weights, the single hygiene pin, lints, win-fallback, prompt-diet and the ps1-quality path lists are wired"
}

test_3459_downstream_install() {
  local tgt="$TEST_DIR/core target/proj" n out rc=0 lib="$SCRIPT_DIR/lib/pipe-grep-q-ratchet.sh"
  mkdir -p "$tgt"
  git -C "$tgt" init -q
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$tgt" --profile core >"$TEST_DIR/sync.out" 2>&1 || { tail -10 "$TEST_DIR/sync.out" >&2; log_fail "TEST-3459: aai-sync.sh --profile core failed"; }
  cmp -s "$tgt/.aai/scripts/pre-commit-checks.ps1" "$PS1_LAUNCHER" || log_fail "TEST-3459: the installed launcher differs from the source"
  cmp -s "$tgt/.aai/scripts/pre-commit-checks.sh" "$SH_CHECKS" || log_fail "TEST-3459: the installed pre-commit-checks.sh differs from the source"
  if need_tool TEST-3459 pwsh; then
    ( cd "$tgt" && pwsh -NoProfile -File .aai/scripts/pre-commit-checks.ps1 ) >"$TEST_DIR/d.out" 2>"$TEST_DIR/d.err" || rc=$?
    [[ "$rc" == 1 ]] || log_fail "TEST-3459: the installed launcher exited $rc, expected 1"
    [[ ! -s "$TEST_DIR/d.out" ]] || log_fail "TEST-3459: the installed launcher wrote to stdout"
    [[ "$(cat "$TEST_DIR/d.err")" == "$D_LAUNCH" ]] || log_fail "TEST-3459: the installed launcher stderr was: $(cat "$TEST_DIR/d.err")"
  fi
  # shellcheck source=lib/pipe-grep-q-ratchet.sh
  . "$lib"
  n="$(shipping_sites < "$tgt/.aai/scripts/pre-commit-checks.sh")"
  [[ "$n" == 0 ]] || log_fail "TEST-3459: PGQ_PATTERN matches $n non-comment line(s) of the installed pre-commit-checks.sh"
  out="$(awk '/^core:/{c=1; next} /^[a-z]/{c=0} c && $0=="  - .aai/scripts/pre-commit-checks.ps1"{k++} END{print k+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$out" == 1 ]] || log_fail "TEST-3459: PROFILES core lists the launcher $out times, expected 1"
  log_pass "TEST-3459: aai-sync --profile core into a spaced path installs the launcher and the pipe-safe checks byte-identical, and the installed launcher refuses by name"
}

RFC17="${PCC_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
D_RFC_REASON='L3 protected surface; the .ps1 was retired by the [pre-commit-checks slice](../issues/CHANGE-0250-pre-commit-checks-ps1-retire.md), a deprecation launcher for one release naming pre-commit-checks.sh, deleted in the next; the .sh checks 1 to 7 run without Node'
D_RFC_SENTENCE='The ninth slice [retired the PowerShell pre-commit checks](../issues/CHANGE-0250-pre-commit-checks-ps1-retire.md): the uncalled .ps1 became a deprecation launcher for one release that names pre-commit-checks.sh, and the bash checks no longer pipe into an early-closing reader.'

test_3460_rfc() {
  local row phase n
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree >"$TEST_DIR/e.out" 2>&1 || { tail -8 "$TEST_DIR/e.out" >&2; log_fail "TEST-3460: test_2624_inventory_matches_tree failed"; }
  row="$("$GREP" -F '| `pre-commit-checks` |' "$RFC17" || true)"
  [[ -n "$row" && "$(wc -l <<< "$row" | tr -d ' ')" == 1 ]] || log_fail "TEST-3460: expected exactly one pre-commit-checks inventory row"
  [[ "$row" == *'| 323/281 |'* ]] || log_fail "TEST-3460: the inventory row lost 323/281"
  [[ "$row" == *'| platform adapter kept on purpose |'* ]] || log_fail "TEST-3460: the inventory row lost its destination"
  [[ "$row" == *"$D_RFC_REASON"* ]] || log_fail "TEST-3460: the inventory row lacks the D-RFC reason"
  [[ "$row" == *'pre-commit-checks-ps1-retire.md)'* ]] || log_fail "TEST-3460: the inventory row link does not end pre-commit-checks-ps1-retire.md"
  phase="$("$GREP" -E '^\| 5 \|' "$RFC17" || true)"
  [[ -n "$phase" ]] || log_fail "TEST-3460: the phase 5 row is missing"
  n="$(awk -v needle="$D_RFC_SENTENCE" '{ s=$0; while ((i = index(s, needle)) > 0) { c++; s = substr(s, i + length(needle)) } } END { print c+0 }' <<< "$phase")"
  [[ "$n" == 1 ]] || log_fail "TEST-3460: the phase 5 row holds the D-RFC sentence $n times, expected 1"
  p5="$(node "$PROJECT_ROOT/tests/skills/lib/phase5-row-status.mjs" "$RFC17" 2>&1)" || log_fail "TEST-3460: $p5"
  log_pass "TEST-3460: the RFC inventory keeps 323/281 and its destination with the D-RFC reason, and phase 5 holds the ninth-slice sentence once"
}

# code_lines <file> [text]: non-blank, non-comment lines (the plan's method); prints a count.
code_lines() { "$GREP" -cvE '^[[:space:]]*(#|$)' "$1" || true; }

test_3461_line_budget_and_follow_up() {
  local ps_t ps_c sh_t sh_c out
  ps_t="$(wc -l < "$PS1_LAUNCHER" | tr -d ' ')"; ps_c="$(code_lines "$PS1_LAUNCHER")"
  sh_t="$(wc -l < "$SH_CHECKS" | tr -d ' ')"; sh_c="$(code_lines "$SH_CHECKS")"
  echo "LINES before: pre-commit-checks.sh 323/239, pre-commit-checks.ps1 281/221 (total/code)"
  echo "LINES after:  pre-commit-checks.sh $sh_t/$sh_c, pre-commit-checks.ps1 $ps_t/$ps_c (total/code)"
  [[ "$ps_t" -le 5 && "$ps_c" -le 2 ]] || log_fail "TEST-3461: the launcher is $ps_t lines and $ps_c code lines, budget 5 and 2"
  # 323/239 after the pipe-safe slice, then 331/247 after pr-ceremony-friction-fixes (CHECK 2, +8/+8),
  # then 333/245 after hook-gate-staged-content (staged list into an array, +2/-2), then 414/319 after
  # precommit-blob-read-cost (the batched index read and its fail-closed parser, +81/+74), then 431/334
  # after its VALIDATION r1 B1 fix (the list read outside a work tree, +17/+15), then 425/325 after its
  # VALIDATION r2 B2 fix (one `git rev-parse --git-dir` predicate for every scratch and list failure, -6/-9),
  # then 472/357 after its VALIDATION r3 B3 fix (descriptor-safe reads, independent count cross-checks, scan-open
  # checks, +47/+32), then 480/360 after its VALIDATION r4 remediation (+8/+3), then 485/361 after
  # precommit-sentinel-trap (PCC_PARSED initialised, +5/+1), then 526/390 after precommit-residual-defects (the
  # re-read loop, a pipe probe, in-shell STATE matches, parameter-expansion line walks, +41/+29), then 901/747 after
  # secrets-gate-false-positives (CHECK 2 rewritten: the value-shape awk program, the allowlist read and parse, fingerprints, +375/+357),
  # then 947/788 after its VALIDATION r1 remediation (NUL-free awk copy, R5 real-dotenv rule, bracket-only catch-all globs, +45/+41),
  # then 1048/887 after its VALIDATION r3 remediation (inline private key markers, R6 any-key judging in name-hit files, bracket expression parser, +101/+99).
  [[ "$sh_t" == 1048 && "$sh_c" == 887 ]] || log_fail "TEST-3461 (TEST-3877 pin): pre-commit-checks.sh is $sh_t lines and $sh_c code lines, expected 1048 and 887"
  node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status open --json > "$TEST_DIR/fu.json" || log_fail "TEST-3461: follow-ups list failed"
  out="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const hit = j.items.filter((i) => i.id === "fu-delete-retired-pre-commit-checks-ps1");
    const bad = [];
    if (hit.length !== 1) bad.push("open items with the id: " + hit.length);
    else {
      const i = hit[0];
      if (i.ref_id !== "pre-commit-checks-ps1-retire") bad.push("ref_id " + i.ref_id);
      if (i.severity !== "P3") bad.push("severity " + i.severity);
      for (const t of ["pre-commit-checks.ps1", "PROFILES.yaml", "WORKFLOW.md", "docs-audit.yaml"]) if (!String(i.finding).includes(t)) bad.push("finding lacks " + t);
    }
    process.stdout.write(bad.join("; "));
  ' "$TEST_DIR/fu.json")"
  [[ -z "$out" ]] || log_fail "TEST-3461: the delete follow-up: $out"
  log_pass "TEST-3461: the launcher is $ps_t/$ps_c lines, pre-commit-checks.sh is $sh_t/$sh_c, and the delete follow-up is filed (P3)"
}

# --- pr-ceremony-friction-fixes (GitHub #565): CHECK 2 in the AAI evidence folders -------------
EVIDENCE_DIRS="docs/ai/reports docs/ai/tdd docs/ai/validation docs/ai/reviews"
SENSITIVE="Sensitive file staged"
SECRET_HIT="Potential secret detected in"

# stage_file <fixture> <path> <content line>: writes the line to the path and stages it.
stage_file() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -f -- "$2"
}

test_3831_evidence_names_pass() {
  local fx="$TEST_DIR/t3831" d n head_before
  make_fx "$fx"
  for d in $EVIDENCE_DIRS; do
    stage_file "$fx" "$d/worker-env-and-secrets.txt" "API_BASE_URL DB_NAME"
    stage_file "$fx" "$d/db-credentials-check.log" "API_BASE_URL DB_NAME"
  done
  run_checks "$fx"
  n="$(count_in "$OUT" "$SENSITIVE")"
  [[ "$RC" == 0 && "$n" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3831: eight evidence files named with secret/credentials exited $RC with $n '$SENSITIVE' line(s), expected 0 and 0"; }
  # Through a real installed hook: the commit must be created.
  vendor_hook_installer "$fx" sh
  aai_assert_hooks_under "$fx" "$TEST_DIR" || log_fail "TEST-3831: the hooks path of $fx lies outside the scratch root"
  ( cd "$fx" && aai_git_scrubbed bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/inst3831.out" 2>&1 || { cat "$TEST_DIR/inst3831.out" >&2; log_fail "TEST-3831: the hook installer failed"; }
  git -C "$fx" checkout -q -b work
  head_before="$(git -C "$fx" rev-parse HEAD)"
  RC=0
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m evidence ) >"$TEST_DIR/commit3831.out" 2>&1 || RC=$?
  [[ "$RC" == 0 ]] || { cat "$TEST_DIR/commit3831.out" >&2; log_fail "TEST-3831: git commit through the installed hook exited $RC"; }
  [[ "$(git -C "$fx" rev-parse HEAD)" != "$head_before" ]] || log_fail "TEST-3831: HEAD did not move"
  log_pass "TEST-3831: evidence files named with secret/credentials in the four evidence folders pass CHECK 2 and commit through the installed hook"
}

test_3832_content_scan_reads_staged_blob() {
  local fx="$TEST_DIR/t3832" p n line
  make_fx "$fx"
  line="$(printf '%s = "%s"' api_key abcdefgh1234)"   # assembled so this suite does not trip CHECK 2 itself
  for p in docs/ai/validation/run.txt app/config.txt; do
    stage_file "$fx" "$p" "$line"
    printf 'clean\n' > "$fx/$p"   # the working tree no longer holds it; the staged blob does
  done
  run_checks "$fx"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3832: a staged secret behind a clean working tree exited $RC, expected 1"; }
  for p in docs/ai/validation/run.txt app/config.txt; do
    n="$(count_in "$OUT" "$SECRET_HIT $p")"
    [[ "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3832: '$SECRET_HIT $p' printed $n time(s), expected 1"; }
  done
  log_pass "TEST-3832: the content scan reads the staged blob, inside and outside the evidence folders"
}

# sg_value: a credential-shaped value, assembled at run time so this suite does not trip CHECK 2 itself.
sg_value() { printf '%s%s' q7Rk2xZ p9LmW4n; }

# sg_line <path>: the one line a name-hit fixture holds when it must be a finding (JSON for .json, dotenv otherwise).
sg_line() {
  case "$1" in
    *.json) printf '{"%s": "%s"}' password "$(sg_value)" ;;
    *) printf '%s=%s' DB_PASSWORD "$(sg_value)" ;;
  esac
}

test_3833_sensitive_names_still_blocked() {
  local p fx i=0 n
  # secrets-gate-false-positives (D-NAME, D-KEYFILE): a name hit holding nothing credential-shaped passes; one holding
  # a real-looking value blocks by content; a key file still blocks by name whatever it holds.
  for p in .env .env.local config/credentials.json docs/ai/validation/.env docs/ai/tdd/.env.prod; do
    i=$((i + 1))
    fx="$TEST_DIR/t3833-$i"
    make_fx "$fx"
    stage_file "$fx" "$p" "harmless"
    run_checks "$fx"
    [[ "$RC" == 0 && "$(count_in "$OUT" "$SENSITIVE")" == 0 && "$(count_in "$OUT" "$SECRET_HIT")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3833: staged $p holding harmless exited $RC, expected a pass with no secret line"; }
    fx="$TEST_DIR/t3833-v$i"
    make_fx "$fx"
    stage_file "$fx" "$p" "$(sg_line "$p")"
    run_checks "$fx"
    n="$(count_in "$OUT" "$SECRET_HIT $p")"
    [[ "$RC" == 1 && "$n" == 1 && "$(count_in "$OUT" "$SENSITIVE")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3833: staged $p holding a real-looking value exited $RC with $n '$SECRET_HIT $p' line(s), expected 1 and 1"; }
  done
  p=keys/secret.key
  fx="$TEST_DIR/t3833-key"
  make_fx "$fx"
  stage_file "$fx" "$p" "harmless"
  run_checks "$fx"
  n="$(count_in "$OUT" "$SENSITIVE: $p")"
  [[ "$RC" == 1 && "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3833: staged $p exited $RC with $n '$SENSITIVE: $p' line(s), expected 1 and 1"; }
  log_pass "TEST-3833: .env, .env.local, credentials.json and dotenv files inside evidence folders pass holding harmless text and block by content holding a value; secret.key still blocks by name"
}

# --- hook-gate-staged-content: every staged file is checked on its staged blob --------------------
DEBUG_HIT="Debug statements in"

test_3864_deleted_worktree_copy_still_scanned() {
  local fx="$TEST_DIR/t3864" line n
  make_fx "$fx"
  line="$(printf '%s = "%s"' api_key abcdefgh1234)"   # assembled so this suite does not trip CHECK 2 itself
  stage_file "$fx" app/config.txt "$line"
  stage_file "$fx" app.js "console.log(1);"
  rm -f "$fx/app/config.txt" "$fx/app.js"   # the index still holds both blobs
  run_checks "$fx"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3864: a staged secret whose working copy was deleted exited $RC, expected 1"; }
  n="$(count_in "$OUT" "$SECRET_HIT app/config.txt")"
  [[ "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3864: '$SECRET_HIT app/config.txt' printed $n time(s), expected 1"; }
  n="$(count_in "$OUT" "$DEBUG_HIT app.js")"
  [[ "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3864: '$DEBUG_HIT app.js' printed $n time(s), expected 1"; }
  log_pass "TEST-3864: a staged file deleted from the working tree is still scanned on its staged blob (secrets and debug statements)"
}

test_3865_suffix_dotenv_blocked_in_evidence() {
  local p fx i=0 n
  # secrets-gate-false-positives: a *.env basename is still a name hit in each evidence folder, now judged by content.
  for p in docs/ai/tdd/prod.env docs/ai/reports/x.env docs/ai/validation/stage.env docs/ai/reviews/a.env; do
    i=$((i + 1))
    fx="$TEST_DIR/t3865-$i"
    make_fx "$fx"
    stage_file "$fx" "$p" "harmless"
    run_checks "$fx"
    [[ "$RC" == 0 && "$(count_in "$OUT" "$SENSITIVE")" == 0 && "$(count_in "$OUT" "$SECRET_HIT")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3865: staged $p holding harmless exited $RC, expected a pass"; }
    fx="$TEST_DIR/t3865-v$i"
    make_fx "$fx"
    stage_file "$fx" "$p" "$(sg_line "$p")"
    run_checks "$fx"
    n="$(count_in "$OUT" "$SECRET_HIT $p")"
    [[ "$RC" == 1 && "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3865: staged $p holding a real-looking value exited $RC with $n '$SECRET_HIT $p' line(s), expected 1 and 1"; }
  done
  fx="$TEST_DIR/t3865-neg"
  make_fx "$fx"
  stage_file "$fx" docs/ai/tdd/environment-notes.txt "API_BASE_URL DB_NAME"
  run_checks "$fx"
  n="$(count_in "$OUT" "$SENSITIVE")"
  [[ "$RC" == 0 && "$n" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3865: docs/ai/tdd/environment-notes.txt exited $RC with $n '$SENSITIVE' line(s), expected 0 and 0"; }
  log_pass "TEST-3865: a *.env basename in each evidence folder passes holding harmless text and blocks by content holding a value; an env-named note is not a name hit"
}

test_3866_non_ascii_names_checked() {
  local fx="$TEST_DIR/t3866" line n
  make_fx "$fx"
  line="$(printf '%s = "%s"' api_key abcdefgh1234)"
  stage_file "$fx" "app/café.txt" "$line"
  stage_file "$fx" "secrets/clé.key" "harmless"
  run_checks "$fx"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3866: staged non-ASCII names exited $RC, expected 1"; }
  n="$(count_in "$OUT" "$SECRET_HIT app/café.txt")"
  [[ "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3866: '$SECRET_HIT app/café.txt' printed $n time(s), expected 1"; }
  n="$(count_in "$OUT" "$SENSITIVE: secrets/clé.key")"
  [[ "$n" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3866: '$SENSITIVE: secrets/clé.key' printed $n time(s), expected 1"; }
  log_pass "TEST-3866: staged names git would quote are checked under their real path (content and name)"
}

test_3868_changelog_and_product_doc() {
  local cl="$PROJECT_ROOT/CHANGELOG.md" doc="$PROJECT_ROOT/docs/product/docs-close-gate.md" n
  n="$("$GREP" -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — fix: commit-time guards judge the staged content of every staged file' "$cl" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3868: CHANGELOG.md holds $n headings for this fix, want exactly 1"
  [[ -f "$doc" ]] || log_fail "TEST-3868: $doc is missing"
  "$GREP" -qF "from the index" "$doc" || log_fail "TEST-3868: the product doc must say the hook reads the intake doc and its linked specs from the index"
  "$GREP" -qF "HEAD" "$doc" || log_fail "TEST-3868: the product doc must name HEAD as the fallback"
  log_pass "TEST-3868: CHANGELOG heading and product doc statement present"
}

# --- precommit-blob-read-cost: CHECKs 2-4 read the staged content in one batched index read -------
PRE_BATCH_SHA="03f3e6df"
FAIL_CLOSED="Staged content could not be read completely"
REAL_GIT="$(command -v git || true)"

# pre_batch_script: writes the 03f3e6df pre-commit-checks.sh (git show) and prints its path; prints
# nothing when that commit is not in this clone (named SKIP-CASE locally, FAIL on CI).
pre_batch_script() {
  local out="$TEST_DIR/pre-batch-pre-commit-checks.sh"
  if [[ ! -s "$out" ]]; then
    git -C "$PROJECT_ROOT" show "$PRE_BATCH_SHA:.aai/scripts/pre-commit-checks.sh" > "$out" 2>/dev/null || rm -f "$out"
  fi
  [[ -s "$out" ]] && printf '%s\n' "$out"
  return 0
}

# make_git_wrapper <dir> <mode> [logfile]: a `git` shim for the run under test (put first on PATH only
# for that run) with the real git's absolute path baked in. Modes: log (one line per invocation), cut20 (the
# cat-file --batch output loses its last 20 bytes, exit 0), dropid (the last requested id is dropped),
# extra (one extra response line is appended), sizeplus (the first header's size is raised by 1), exit3
# (full batch output, exit 3), list128 (diff --cached --raw exits 128), listcut3 (its output loses 3 bytes),
# listdrop (its output loses its last whole record, exit 0), listempty (no output at all, exit 0), sizehuge (the
# first header's size becomes 20 nines, past 64-bit arithmetic), sizepad (the
# first header's size gets a leading 08: "6" reads "086", a bad octal for bash arithmetic), listspace (every
# record's status gets one extra leading space, so a record holds five spaces), late (logs like log; right
# after it answers the first diff --cached --raw it stages late.txt with the real git, standing in for another
# process changing the index between the script's two list reads).
# blobfail (secrets-gate-false-positives): `git cat-file blob` exits 128 (the allowlist read from the index fails).
make_git_wrapper() {
  local d="$1" mode="$2" log="${3:-/dev/null}"
  mkdir -p "$d"
  {
    printf '#!/bin/bash\nREAL=%q\nMODE=%q\nLOG=%q\nTMP=%q\n' "$REAL_GIT" "$mode" "$log" "$d/wrap.tmp.$$"
    cat <<'WRAP'
if [ "$MODE" = log ] || [ "$MODE" = late ]; then printf '%s\n' "$*" >> "$LOG"; fi
is_batch=0; is_list=0
if [ "$MODE" = blobfail ]; then case " $* " in *" cat-file blob "*) echo "fatal: simulated failure" >&2; exit 128 ;; esac; fi
case " $* " in *" cat-file --batch "*) is_batch=1 ;; esac
case " $* " in *" diff --cached --raw "*) is_list=1 ;; esac
if [ "$is_batch" = 1 ]; then
  case "$MODE" in
    cut20) "$REAL" "$@" > "$TMP"; n=$(wc -c < "$TMP"); head -c $((n - 20)) "$TMP"; rm -f "$TMP"; exit 0 ;;
    dropid) sed '$d' | "$REAL" "$@"; exit "${PIPESTATUS[1]}" ;;
    extra) "$REAL" "$@"; rc=$?; printf 'extra response line\n'; exit "$rc" ;;
    sizeplus)
      "$REAL" "$@" > "$TMP"; hdr=$(head -n 1 "$TMP"); size=${hdr##* }
      printf '%s %s\n' "${hdr% *}" $((size + 1)); tail -n +2 "$TMP"; rm -f "$TMP"; exit 0 ;;
    exit3) "$REAL" "$@"; exit 3 ;;
    sizehuge)
      "$REAL" "$@" > "$TMP"; hdr=$(head -n 1 "$TMP")
      printf '%s 99999999999999999999\n' "${hdr% *}"; tail -n +2 "$TMP"; rm -f "$TMP"; exit 0 ;;
    sizepad)
      "$REAL" "$@" > "$TMP"; hdr=$(head -n 1 "$TMP")
      printf '%s 08%s\n' "${hdr% *}" "${hdr##* }"; tail -n +2 "$TMP"; rm -f "$TMP"; exit 0 ;;
  esac
fi
if [ "$is_list" = 1 ]; then
  case "$MODE" in
    list128) echo "fatal: simulated failure" >&2; exit 128 ;;
    listcut3) "$REAL" "$@" > "$TMP"; n=$(wc -c < "$TMP"); head -c $((n - 3)) "$TMP"; rm -f "$TMP"; exit 0 ;;
    listdrop) "$REAL" "$@" > "$TMP"; tr '\0' '\n' < "$TMP" | sed '$d' | sed '$d' | tr '\n' '\0'; rm -f "$TMP"; exit 0 ;;
    listempty) exit 0 ;;
    listspace) "$REAL" "$@" | tr '\0' '\n' | sed 's/^\(:.* \)\([A-Z]\)$/\1 \2/' | tr '\n' '\0'; exit 0 ;;
    late)
      "$REAL" "$@"; rc=$?
      if [ ! -e "${TMP%/*}/late.done" ]; then : > "${TMP%/*}/late.done"; "$REAL" add late.txt >/dev/null 2>&1 || exit 97; fi
      exit "$rc" ;;
  esac
fi
exec "$REAL" "$@"
WRAP
  } > "$d/git"
  chmod +x "$d/git"
}

# run_with <fixture> <wrapper dir or ""> [VAR=value ...]: runs the fixture's script with the wrapper dir
# first on PATH; RUN_ULIMIT_F, when set, applies `ulimit -f` to the run, RUN_ULIMIT_N `ulimit -n`, and RUN_HOLD_FDS
# (any value) keeps the default soft limit of 256 with descriptors 10..254 inherited open (the descriptor table
# the script's builtin redirections would need to save into), and RUN_STRICT (any value) passes --strict. Sets OUT, ERR, RC.
run_with() {
  local fx="$1" wd="$2" p="$PATH" hold_i
  shift 2
  [[ -z "$wd" ]] || p="$wd:$PATH"
  RC=0
  ( [[ -z "${RUN_ULIMIT_F:-}" ]] || ulimit -f "$RUN_ULIMIT_F"
    [[ -z "${RUN_ULIMIT_N:-}" ]] || ulimit -n "$RUN_ULIMIT_N" || exit 99
    if [[ -n "${RUN_HOLD_FDS:-}" ]]; then
      ulimit -n 256 || exit 99
      for hold_i in $(seq 10 254); do eval "exec $hold_i</dev/null"; done
    fi
    cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null PATH="$p" "$@" bash .aai/scripts/pre-commit-checks.sh ${RUN_STRICT:+--strict} ) >"$TEST_DIR/run.out" 2>"$TEST_DIR/run.err" || RC=$?
  OUT="$TEST_DIR/run.out"; ERR="$TEST_DIR/run.err"
}

# SECRET_LINE: assembled so this suite does not trip CHECK 2 itself.
secret_line() { printf '%s = "%s"' api_key abcdefgh1234; }

# big_fixture <dir>: a.txt plus z-big.txt (about 300 KB, its last line an api_key assignment).
big_fixture() {
  make_fx "$1"
  printf 'alpha\n' > "$1/a.txt"
  { awk 'BEGIN { for (i = 1; i <= 5000; i++) printf "filler_%05d: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i }'; secret_line; echo; } > "$1/z-big.txt"
  git -C "$1" add a.txt z-big.txt
}

# assert_closed <TEST id> <reason fragment>: the last run failed closed with the single message.
assert_closed() {
  local id="$1" reason="$2" last
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: exit $RC, expected 1 ($reason)"; }
  [[ "$(count_in "$OUT" "$FAIL_CLOSED")" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: the '$FAIL_CLOSED' line was printed $(count_in "$OUT" "$FAIL_CLOSED") times, expected 1 ($reason)"; }
  last="$(tail -n 1 "$OUT")"
  [[ "$last" == *"$FAIL_CLOSED"*"$reason"* ]] || { cat "$OUT" >&2; log_fail "$id: the last stdout line does not name '$reason': $last"; }
  if "$GREP" -qE 'ALL CHECKS PASS|PASS WITH WARNINGS' "$OUT"; then cat "$OUT" >&2; log_fail "$id: a summary line was printed ($reason)"; fi
}

# js_fixture <dir> <n>: n clean staged .js files.
js_fixture() {
  local i
  make_fx "$1"
  for i in $(seq 1 "$2"); do printf 'var x_%d = %d;\n' "$i" "$i" > "$1/f$i.js"; done
  git -C "$1" add -A
}

test_3871_one_batched_read_whatever_the_count() {
  local n log lines5 lines40 fx wd="$TEST_DIR/w3871"
  make_git_wrapper "$wd" log "$TEST_DIR/t3871.log"
  for n in 5 40; do
    fx="$TEST_DIR/t3871-$n"
    js_fixture "$fx" "$n"
    : > "$TEST_DIR/t3871.log"
    run_with "$fx" "$wd"
    [[ "$RC" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3871: $n clean staged .js files exited $RC, expected 0"; }
    log="$TEST_DIR/t3871-$n.lines"
    cp "$TEST_DIR/t3871.log" "$log"
    [[ "$(count_in "$log" "cat-file")" == 1 ]] || { cat "$log" >&2; log_fail "TEST-3871: $n files: expected exactly one cat-file invocation, saw $(count_in "$log" cat-file)"; }
    [[ "$(count_in "$log" "cat-file --batch")" == 1 ]] || { cat "$log" >&2; log_fail "TEST-3871: $n files: the one cat-file invocation is not cat-file --batch"; }
    [[ "$(count_in "$log" "cat-file -e")" == 0 ]] || log_fail "TEST-3871: $n files: a cat-file -e invocation was logged"
    if "$GREP" -qE '(^| )show( |$)' "$log"; then cat "$log" >&2; log_fail "TEST-3871: $n files: a git show invocation was logged"; fi
  done
  lines5="$(wc -l < "$TEST_DIR/t3871-5.lines" | tr -d ' ')"
  lines40="$(wc -l < "$TEST_DIR/t3871-40.lines" | tr -d ' ')"
  [[ "$lines5" == "$lines40" ]] || log_fail "TEST-3871: git invocations grow with the staged count: $lines5 for 5 files, $lines40 for 40"
  log_pass "TEST-3871: 5 and 40 staged files start the same number of git processes ($lines5), exactly one of them cat-file --batch, no show and no cat-file -e"
}

test_3872_truncation_and_write_failure_fail_closed() {
  local fx="$TEST_DIR/t3872"
  big_fixture "$fx"
  make_git_wrapper "$TEST_DIR/w3872" cut20
  run_with "$fx" "$TEST_DIR/w3872"
  assert_closed TEST-3872 "size mismatch for z-big.txt"
  RUN_ULIMIT_F=200 run_with "$fx" ""
  assert_closed TEST-3872 "git cat-file --batch failed"
  log_pass "TEST-3872: a batch output cut by 20 bytes names size mismatch for z-big.txt, a write refused by ulimit -f 200 names git cat-file --batch failed, both single messages with no summary"
}

test_3873_response_count_mismatch_fails_closed() {
  local fx="$TEST_DIR/t3873"
  big_fixture "$fx"
  make_git_wrapper "$TEST_DIR/w3873a" dropid
  run_with "$fx" "$TEST_DIR/w3873a"
  assert_closed TEST-3873 "response missing for z-big.txt"
  make_git_wrapper "$TEST_DIR/w3873b" extra
  run_with "$fx" "$TEST_DIR/w3873b"
  assert_closed TEST-3873 "unrequested trailing output"
  make_git_wrapper "$TEST_DIR/w3873c" sizeplus
  run_with "$fx" "$TEST_DIR/w3873c"
  assert_closed TEST-3873 "separator missing after a.txt"
  # a size with a leading zero (a bad octal for bash arithmetic) is not a decimal size: it fails closed
  make_git_wrapper "$TEST_DIR/w3873d" sizepad
  run_with "$fx" "$TEST_DIR/w3873d"
  assert_closed TEST-3873 "unexpected response for a.txt"
  # and so is a size too long for the arithmetic to hold
  make_git_wrapper "$TEST_DIR/w3873e" sizehuge
  run_with "$fx" "$TEST_DIR/w3873e"
  assert_closed TEST-3873 "unexpected response for a.txt"
  # with that check removed the same input aborts the arithmetic, and bash 3.2 then drops the whole parse block
  # (the count cross-checks with it); the parse-completed sentinel, a separate command, must still block
  local mfx="$TEST_DIR/t3873m" msh="$TEST_DIR/t3873m.sh"
  sed 's/|0?\*)/)/' "$SH_CHECKS" > "$msh"
  ! cmp -s "$msh" "$SH_CHECKS" || log_fail "TEST-3873: the leading-zero mutant did not apply"
  make_fx "$mfx" "$msh"
  printf 'alpha\n' > "$mfx/a.txt"
  printf '%s\n' "$(secret_line)" > "$mfx/b.txt"
  git -C "$mfx" add a.txt b.txt
  run_with "$mfx" "$TEST_DIR/w3873d"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; cat "$ERR" >&2; log_fail "TEST-3873: leading-zero check removed, padded size: exit $RC, expected 1 (the parse block was discarded)"; }
  if "$GREP" -qE 'ALL CHECKS PASS|PASS WITH WARNINGS' "$OUT"; then cat "$OUT" >&2; log_fail "TEST-3873: leading-zero check removed: a passing summary was printed"; fi
  if [[ "$(count_in "$OUT" "$FAIL_CLOSED")" == 1 ]]; then
    [[ "$(tail -n 1 "$OUT")" == *"parse did not complete"* ]] || { cat "$OUT" >&2; log_fail "TEST-3873: leading-zero check removed: the fail-closed line does not name the sentinel"; }
  fi
  log_pass "TEST-3873: a dropped response, an extra response, a size that does not match the bytes, a zero-padded size and a 20-digit size each fail closed with their own single message, and the parse-completed sentinel blocks when the leading-zero check is removed"
}

test_3874_unreadable_object_and_failed_reads_fail_closed() {
  local fx="$TEST_DIR/t3874" sha obj
  make_fx "$fx"
  printf 'clean content of c, unique 3874\n' > "$fx/c.txt"
  git -C "$fx" add c.txt
  sha="$(git -C "$fx" rev-parse :c.txt)"
  obj="$fx/.git/objects/${sha:0:2}/${sha:2}"
  [[ -f "$obj" ]] || log_fail "TEST-3874: the staged blob is not a loose object at $obj"
  rm -f "$obj"
  run_with "$fx" ""
  assert_closed TEST-3874 "unexpected response for c.txt"
  big_fixture "$TEST_DIR/t3874b"
  make_git_wrapper "$TEST_DIR/w3874a" exit3
  run_with "$TEST_DIR/t3874b" "$TEST_DIR/w3874a"
  assert_closed TEST-3874 "git cat-file --batch failed"
  make_git_wrapper "$TEST_DIR/w3874b" list128
  run_with "$TEST_DIR/t3874b" "$TEST_DIR/w3874b"
  assert_closed TEST-3874 "git diff --cached failed"
  make_git_wrapper "$TEST_DIR/w3874c" listcut3
  run_with "$TEST_DIR/t3874b" "$TEST_DIR/w3874c"
  assert_closed TEST-3874 "malformed staged list"
  log_pass "TEST-3874: a staged blob with a deleted object, a reader exiting 3, a failing list read and a list cut by 3 bytes each fail closed with their own single message"
}

test_3875_scratch_failures_and_cleanup() {
  local fx="$TEST_DIR/t3875" t="$TEST_DIR/t3875-tmp" stub="$TEST_DIR/w3875dd"
  big_fixture "$fx"
  run_with "$fx" "" TMPDIR="$TEST_DIR/no-such-dir"
  assert_closed TEST-3875 "cannot create a scratch directory"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 1\n' > "$stub/dd"
  chmod +x "$stub/dd"
  run_with "$fx" "$stub"
  assert_closed TEST-3875 "copy failed for a.txt"
  mkdir -p "$t"
  git -C "$fx" rm -q --cached z-big.txt
  run_with "$fx" "" TMPDIR="$t"
  [[ "$RC" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3875: the passing run exited $RC"; }
  [[ -z "$(ls -A "$t")" ]] || log_fail "TEST-3875: the scratch directory was left behind after a passing run: $(ls -A "$t")"
  git -C "$fx" add z-big.txt
  make_git_wrapper "$TEST_DIR/w3875cut" cut20
  run_with "$fx" "$TEST_DIR/w3875cut" TMPDIR="$t"
  assert_closed TEST-3875 "size mismatch for z-big.txt"
  [[ -z "$(ls -A "$t")" ]] || log_fail "TEST-3875: the scratch directory was left behind after a fail-closed run: $(ls -A "$t")"
  # cwd inside .git: no work tree, but the index is readable, so every scratch failure must still block
  # (VALIDATION r2 B2: a refused list write read as "no staged files" and a staged secret passed).
  # The run is captured through a pipe so that `ulimit -f 0` cannot refuse the script's own output.
  local gd="$TEST_DIR/t3875-gd" how rcg ng="$TEST_DIR/t3875-nongit"
  make_fx "$gd"
  printf '%s\n' "$(secret_line)" > "$gd/b.txt"
  git -C "$gd" add b.txt
  for how in ulimit-f-0 missing-tmpdir; do
    rcg=0
    case "$how" in
      ulimit-f-0) ( cd "$gd/.git" && ulimit -f 0 && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$gd/.aai/scripts/pre-commit-checks.sh" 2>&1 ) | cat > "$TEST_DIR/t3875-gd.out" || rcg=$? ;;
      missing-tmpdir) ( cd "$gd/.git" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null TMPDIR="$TEST_DIR/no-such-dir" bash "$gd/.aai/scripts/pre-commit-checks.sh" 2>&1 ) | cat > "$TEST_DIR/t3875-gd.out" || rcg=$? ;;
    esac
    [[ "$rcg" == 1 ]] || { cat "$TEST_DIR/t3875-gd.out" >&2; log_fail "TEST-3875: cwd inside .git, $how, staged secret: exit $rcg, expected 1"; }
    [[ "$(count_in "$TEST_DIR/t3875-gd.out" "$FAIL_CLOSED")" == 1 ]] || { cat "$TEST_DIR/t3875-gd.out" >&2; log_fail "TEST-3875: cwd inside .git, $how: the '$FAIL_CLOSED' line was not printed exactly once"; }
    if "$GREP" -qE 'ALL CHECKS PASS|PASS WITH WARNINGS|No staged files to check' "$TEST_DIR/t3875-gd.out"; then cat "$TEST_DIR/t3875-gd.out" >&2; log_fail "TEST-3875: cwd inside .git, $how: read as no staged files or passed"; fi
  done
  # a directory that is no repository needs no scratch directory, so a missing TMPDIR does not block it
  mkdir -p "$ng/.aai/scripts"
  cp "$SH_CHECKS" "$ng/.aai/scripts/pre-commit-checks.sh"
  rcg=0
  ( cd "$ng" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CEILING_DIRECTORIES="$TEST_DIR" TMPDIR="$TEST_DIR/no-such-dir" bash .aai/scripts/pre-commit-checks.sh ) >"$TEST_DIR/t3875-ng.out" 2>&1 || rcg=$?
  [[ "$rcg" == 0 ]] || { cat "$TEST_DIR/t3875-ng.out" >&2; log_fail "TEST-3875: a non-repository directory with a missing TMPDIR exited $rcg, expected 0"; }
  [[ "$(count_in "$TEST_DIR/t3875-ng.out" "No staged files to check")" == 1 ]] || { cat "$TEST_DIR/t3875-ng.out" >&2; log_fail "TEST-3875: a non-repository directory did not report no staged files"; }
  log_pass "TEST-3875: a missing TMPDIR and a failing dd fail closed, cwd inside .git fails closed on a refused list write and on a missing TMPDIR (staged secret), a non-repository directory needs no scratch directory, and the scratch directory is gone after a passing run and after a fail-closed run"
}

# staged_fx <dir>: a clean a.txt, b.txt holding the api_key line, and three more clean files, all staged. The
# secret is the SECOND record of the staged list, so a loop that stops after one record loses it.
staged_fx() {
  local i
  make_fx "$1"
  printf 'clean a\n' > "$1/a.txt"
  printf '%s\n' "$(secret_line)" > "$1/b.txt"
  for i in c d e; do printf 'clean %s\n' "$i" > "$1/$i.txt"; done
  git -C "$1" add -A
}

# assert_blocked <TEST id> <what>: exit 1, no passing summary, and the staged secret or the fail-closed line named.
assert_blocked() {
  local id="$1" what="$2"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; cat "$ERR" >&2; log_fail "$id: $what: exit $RC, expected 1"; }
  if "$GREP" -qE 'ALL CHECKS PASS|PASS WITH WARNINGS' "$OUT"; then cat "$OUT" >&2; log_fail "$id: $what: a passing summary was printed"; fi
  [[ "$(count_in "$OUT" "$SECRET_HIT b.txt")" == 1 || "$(count_in "$OUT" "$FAIL_CLOSED")" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: $what: neither the secret hit nor the fail-closed line was printed"; }
}

test_3880_descriptor_exhaustion_fails_closed() {
  local fx="$TEST_DIR/t3880" n
  staged_fx "$fx"
  for n in 8 10; do
    RUN_ULIMIT_N="$n" run_with "$fx" ""
    [[ "$RC" != 99 ]] || log_fail "TEST-3880: ulimit -n $n could not be set"
    assert_blocked TEST-3880 "ulimit -n $n, staged secret in the second record"
    [[ "$(count_in "$OUT" "cannot duplicate fd")" == 0 && "$("$GREP" -c 'cannot duplicate fd' "$ERR" || true)" == 0 ]] || { cat "$ERR" >&2; log_fail "TEST-3880: ulimit -n $n: a builtin redirection could not save its descriptor"; }
  done
  RUN_HOLD_FDS=1 run_with "$fx" ""
  [[ "$RC" != 99 ]] || log_fail "TEST-3880: the descriptor limit could not be set to 256"
  assert_blocked TEST-3880 "descriptors 10..254 inherited open at the 256 limit"
  [[ "$("$GREP" -c 'cannot duplicate fd' "$ERR" || true)" == 0 ]] || { cat "$ERR" >&2; log_fail "TEST-3880: inherited descriptors: a builtin redirection could not save its descriptor"; }
  log_pass "TEST-3880: with ulimit -n 8 and 10, and with descriptors 10..254 inherited at the 256 limit, a staged secret in the second record still blocks (exit 1, no summary) and no builtin redirection fails to save its descriptor"
}

test_3881_list_count_crosscheck_fails_closed() {
  local fx="$TEST_DIR/t3881" mode
  staged_fx "$fx"
  printf '%s\n' "$(secret_line)" > "$fx/zz.txt"
  git -C "$fx" add zz.txt
  for mode in listdrop listempty; do
    make_git_wrapper "$TEST_DIR/w3881$mode" "$mode"
    run_with "$fx" "$TEST_DIR/w3881$mode"
    assert_closed TEST-3881 "staged list count mismatch"
  done
  run_with "$fx" ""
  [[ "$RC" == 1 && "$(count_in "$OUT" "$SECRET_HIT zz.txt")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3881: positive control: the unwrapped run did not report the last file's secret once with exit 1"; }
  # the NUL-terminator count, by a tr stub that adds one NUL to its first output (the list's): every record still
  # parses, so only the NUL count (twice the records) can notice
  local td="$TEST_DIR/w3881tr" real_tr
  real_tr="$(command -v tr)"
  mkdir -p "$td"
  printf '#!/bin/bash\nif [ ! -e %q ]; then : > %q; %q "$@"; rc=$?; printf "\\0"; exit $rc; fi\nexec %q "$@"\n' "$td/done" "$td/done" "$real_tr" "$real_tr" > "$td/tr"
  chmod +x "$td/tr"
  run_with "$fx" "$td"
  [[ -e "$td/done" ]] || log_fail "TEST-3881: the tr stub never ran, the NUL-count case is not exercising the check"
  assert_closed TEST-3881 "malformed staged list"
  # the four-space record shape, by a record whose status carries one extra space: it still splits into usable
  # fields, so only the space count can notice
  make_git_wrapper "$TEST_DIR/w3881sp" listspace
  run_with "$fx" "$TEST_DIR/w3881sp"
  assert_closed TEST-3881 "malformed staged list"
  # the copy count cannot be reached from outside by any input that passes the size and separator checks
  # (it only sees a copy lost inside the loop), so its line is pinned by its text
  "$GREP" -qF '[ "$ncopy" -eq "${#STAGED_REQ[@]}" ] || staged_read_fail "copy count mismatch"' "$SH_CHECKS" || log_fail "TEST-3881: the copy-count cross-check is not in the script"
  log_pass "TEST-3881: a staged list that loses its last whole record, or all of them, with git exiting 0, is caught by the independent name count, an extra NUL by the NUL count and a five-space record by the shape check (each fails closed with a single message; the unwrapped run reports the secret), and the copy-count line is pinned by its text"
}

test_3882_scan_open_failure_fails_closed() {
  local fx="$TEST_DIR/t3882" sd="$TEST_DIR/w3882" t="$TEST_DIR/t3882-tmp"
  staged_fx "$fx"
  mkdir -p "$sd" "$t"
  # the first grep call removes every scratch copy: standing in for something deleting the hook's private files
  # between the parse and the scan, so the scan of the next copy cannot open it
  printf '#!/bin/bash\nif [ ! -e %q ]; then : > %q; rm -f "$TMPDIR"/aai-pre-commit.*/[0-9]*; fi\nexec %q "$@"\n' "$sd/done" "$sd/done" "$GREP" > "$sd/grep"
  chmod +x "$sd/grep"
  run_with "$fx" "$sd" TMPDIR="$t"
  [[ -e "$sd/done" ]] || log_fail "TEST-3882: the grep shim never ran, the case is not exercising the scan"
  assert_closed TEST-3882 "copy failed for b.txt"
  [[ -z "$(ls -A "$t")" ]] || log_fail "TEST-3882: the scratch directory was left behind: $(ls -A "$t")"
  log_pass "TEST-3882: a scratch copy that cannot be opened at scan time blocks with copy failed for the file instead of reading as no hits"
}

# sentinel_fx <dir> <script>: a.txt clean and b.txt holding the api_key line, staged, with <script> as the checks.
sentinel_fx() {
  make_fx "$1" "$2"
  printf 'alpha\n' > "$1/a.txt"
  printf '%s\n' "$(secret_line)" > "$1/b.txt"
  git -C "$1" add a.txt b.txt
}

# assert_sentinel <TEST id> <what>: the last run was blocked by the parse-completed sentinel.
assert_sentinel() {
  local id="$1" what="$2"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; cat "$ERR" >&2; log_fail "$id: $what: exit $RC, expected 1"; }
  assert_closed "$id" "parse did not complete"
}

test_3883_sentinel_ignores_the_environment() {
  local fx="$TEST_DIR/t3883" msh="$TEST_DIR/t3883m.sh" wd="$TEST_DIR/w3883"
  # TEST-3873's mutant (no leading-zero check) and padded size abort the parse block; the flags a caller could
  # export must not stand in for a parse that never completed
  sed 's/|0?\*)/)/' "$SH_CHECKS" > "$msh"
  ! cmp -s "$msh" "$SH_CHECKS" || log_fail "TEST-3883: the leading-zero mutant did not apply"
  sentinel_fx "$fx" "$msh"
  make_git_wrapper "$wd" sizepad
  run_with "$fx" "$wd" PCC_PARSED=1 PCC_LIST=0 IN_REPO=0
  assert_sentinel TEST-3883 "PCC_PARSED=1 PCC_LIST=0 IN_REPO=0 exported, parse block aborted"
  # negative control: the same flags exported to the delivered script change nothing when the parse completes
  sentinel_fx "$TEST_DIR/t3883c" "$SH_CHECKS"
  run_with "$TEST_DIR/t3883c" "" PCC_PARSED=1 PCC_LIST=0 IN_REPO=0
  [[ "$RC" == 1 && "$(count_in "$OUT" "$SECRET_HIT b.txt")" == 1 && "$(count_in "$OUT" "$FAIL_CLOSED")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3883: negative control: the delivered script with the flags exported did not report the b.txt secret alone (exit $RC)"; }
  log_pass "TEST-3883: with PCC_PARSED=1, PCC_LIST=0 and IN_REPO=0 in the environment an aborted parse still blocks with parse did not complete"
}

test_3884_sentinel_covers_an_abort_before_the_list() {
  local fx="$TEST_DIR/t3884" msh="$TEST_DIR/t3884m.sh"
  # an abort in the first block (scratch directory and list read), before PCC_LIST=1, must block too
  sed 's/^  PCC_LIST=1$/  : $((08)); PCC_LIST=1/' "$SH_CHECKS" > "$msh"
  ! cmp -s "$msh" "$SH_CHECKS" || log_fail "TEST-3884: the abort-before-the-list mutant did not apply"
  sentinel_fx "$fx" "$msh"
  run_with "$fx" ""
  assert_sentinel TEST-3884 "abort before PCC_LIST=1"
  run_with "$fx" "" PCC_PARSED=1
  assert_sentinel TEST-3884 "abort before PCC_LIST=1, PCC_PARSED=1 exported"
  log_pass "TEST-3884: an abort before the list flag is set blocks with parse did not complete, with and without PCC_PARSED=1 exported"
}

test_3885_trap_closes_descriptors_before_cleanup() {
  local fx="$TEST_DIR/t3885" t="$TEST_DIR/t3885-tmp" n
  staged_fx "$fx"
  mkdir -p "$t"
  # on bash 3.2 an rm -rf child that inherits descriptors 3 and 4 at ulimit -n 5 cannot walk the scratch
  # directory, which holds the staged blobs, so the trap closes them in the child
  for n in 4 5 6; do
    RUN_ULIMIT_N="$n" run_with "$fx" "" TMPDIR="$t"
    [[ "$RC" != 99 ]] || log_fail "TEST-3885: ulimit -n $n could not be set"
    assert_blocked TEST-3885 "ulimit -n $n, staged secret"
    [[ -z "$(ls -A "$t")" ]] || { ls -A "$t" >&2; rm -rf "${t:?}"/*; log_fail "TEST-3885: ulimit -n $n: the scratch directory was left behind after a blocked run"; }
  done
  # bash 5 removes the directory either way, so the line itself is pinned as well
  "$GREP" -qF "trap 'rm -rf \"\$PCC_TMP\" 3<&- 4<&-' EXIT" "$SH_CHECKS" || log_fail "TEST-3885: the EXIT trap no longer closes descriptors 3 and 4 for rm"
  log_pass "TEST-3885: blocked runs at ulimit -n 4, 5 and 6 leave no scratch directory, and the trap closes descriptors 3 and 4 for rm"
}

test_3886_check3_copy_removed_still_blocks() {
  local fx="$TEST_DIR/t3886" sd="$TEST_DIR/w3886" t="$TEST_DIR/t3886-tmp"
  make_fx "$fx"
  printf 'console.log("x");\n' > "$fx/app.js"
  git -C "$fx" add app.js
  mkdir -p "$sd" "$t"
  # CHECK 3's grep (the only one whose pattern names console.log) removes every scratch copy: standing in for a
  # copy that vanishes while CHECK 3 reads it. CHECK 4 scans every file CHECK 3 scans and re-tests the copy.
  printf '#!/bin/bash\ncase "$*" in *console*) if [ ! -e %q ]; then : > %q; rm -f "$TMPDIR"/aai-pre-commit.*/[0-9]*; fi ;; esac\nexec %q "$@"\n' "$sd/done" "$sd/done" "$GREP" > "$sd/grep"
  chmod +x "$sd/grep"
  run_with "$fx" "$sd" TMPDIR="$t"
  [[ -e "$sd/done" ]] || log_fail "TEST-3886: the grep shim never ran for CHECK 3, the case is not exercising the window"
  assert_closed TEST-3886 "copy failed for app.js"
  [[ -z "$(ls -A "$t")" ]] || log_fail "TEST-3886: the scratch directory was left behind: $(ls -A "$t")"
  log_pass "TEST-3886: a scratch copy removed while CHECK 3 scans it blocks with copy failed for app.js (CHECK 4 re-tests it)"
}

test_3887_preservation_and_moved_pins() {
  local sel
  for sel in test_3454_small_input_parity test_3461_line_budget_and_follow_up test_3873_response_count_mismatch_fails_closed \
    test_3875_scratch_failures_and_cleanup test_3880_descriptor_exhaustion_fails_closed test_3882_scan_open_failure_fails_closed; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-pre-commit-checks.sh" "$sel" >"$TEST_DIR/self3887.out" 2>&1 || { tail -10 "$TEST_DIR/self3887.out" >&2; log_fail "TEST-3887: $sel failed"; }
  done
  log_pass "TEST-3887: the seven-fixture parity and its numstat pin, the line-count pin, and TEST-3873, TEST-3875, TEST-3880 and TEST-3882 hold"
}

# --- precommit-residual-defects (spec-precommit-residual-defects): one re-read absorbs an index change
# between the two list reads (D3); no builtin redirection loses the report under a full descriptor table
# (D4). ---------------------------------------------------------------------------------------------------

test_3918_index_race_reread() {
  local fx wd kind
  for kind in secret clean; do
    fx="$TEST_DIR/t3918$kind"; wd="$TEST_DIR/w3918$kind"
    make_fx "$fx"
    printf 'clean a\n' > "$fx/a.txt"
    git -C "$fx" add a.txt
    if [[ "$kind" == secret ]]; then printf '%s\n' "$(secret_line)" > "$fx/late.txt"; else printf 'clean late\n' > "$fx/late.txt"; fi
    make_git_wrapper "$wd" late "$TEST_DIR/t3918$kind.log"
    run_with "$fx" "$wd"
    [[ -e "$wd/late.done" ]] || log_fail "TEST-3918: ($kind) the wrapper never staged late.txt, the case is not exercising the race"
    [[ "$(count_in "$TEST_DIR/t3918$kind.log" "diff --cached --raw")" == 2 ]] || { cat "$TEST_DIR/t3918$kind.log" >&2; log_fail "TEST-3918: ($kind) the staged list was read $(count_in "$TEST_DIR/t3918$kind.log" "diff --cached --raw") times, expected 2"; }
    [[ "$(count_in "$OUT" "$FAIL_CLOSED")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3918: ($kind) an index change between the two reads blocked the commit as unreadable"; }
    if [[ "$kind" == secret ]]; then
      [[ "$RC" == 1 && "$(count_in "$OUT" "$SECRET_HIT late.txt")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3918: the secret in the file staged between the reads was not reported once with exit 1 (exit $RC)"; }
    else
      [[ "$RC" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-3918: a clean file staged between the reads: exit $RC, expected 0"; }
      "$GREP" -qE 'ALL CHECKS PASS|PASS WITH WARNINGS' "$OUT" || { cat "$OUT" >&2; log_fail "TEST-3918: a clean file staged between the reads: no passing summary"; }
    fi
  done
  staged_fx "$TEST_DIR/t3918drop"
  make_git_wrapper "$TEST_DIR/w3918drop" listdrop
  run_with "$TEST_DIR/t3918drop" "$TEST_DIR/w3918drop"
  assert_closed TEST-3918 "staged list count mismatch"
  log_pass "TEST-3918: a file staged by another process between the two list reads is absorbed by one re-read of both lists (its secret reported, a clean one passes); a list still short on the re-read fails closed"
}

# hold_node_shim <dir>: a node on PATH that closes descriptors 10..254 before it runs the real node, so
# CHECK 9's tracked-ignored.mjs can run under RUN_HOLD_FDS while the script itself keeps the full table.
hold_node_shim() {
  mkdir -p "$1"
  printf '#!/bin/bash\nfor i in $(seq 10 254); do eval "exec $i<&-"; done\nexec %q "$@"\n' "$(command -v node)" > "$1/node"
  chmod +x "$1/node"
}

test_3919_full_descriptor_table_reports() {
  local fx="$TEST_DIR/t3919" sd="$TEST_DIR/w3919" fx2="$TEST_DIR/t3919s"
  hold_node_shim "$sd"
  make_fx "$fx"
  cp "$PROJECT_ROOT/.aai/scripts/tracked-ignored.mjs" "$fx/.aai/scripts/"
  printf 'ignored.log\n' > "$fx/.gitignore"
  git -C "$fx" add .gitignore .aai/scripts/tracked-ignored.mjs
  git -C "$fx" commit -q -m ignore
  printf 'data\n' > "$fx/ignored.log"
  git -C "$fx" add -f ignored.log
  RUN_HOLD_FDS=1 run_with "$fx" "$sd"
  [[ "$RC" != 99 ]] || log_fail "TEST-3919: the descriptor limit could not be set to 256"
  [[ "$RC" == 1 ]] || { cat "$OUT" "$ERR" >&2; log_fail "TEST-3919: an added ignored path under a full table: exit $RC, expected 1"; }
  [[ "$(count_in "$OUT" "Gitignored path staged for ADD: ignored.log")" == 1 ]] || { cat "$OUT" "$ERR" >&2; log_fail "TEST-3919: the ADD line for ignored.log was not printed once"; }
  [[ "$(count_in "$OUT" "BLOCKED:")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3919: the BLOCKED summary was not printed"; }
  [[ "$(count_in "$ERR" "cannot duplicate fd")" == 0 ]] || { cat "$ERR" >&2; log_fail "TEST-3919: a builtin redirection could not save its descriptor"; }
  make_fx "$fx2"
  write_state "$fx2" review_not_run small
  RUN_HOLD_FDS=1 RUN_STRICT=1 run_with "$fx2" "$sd"
  [[ "$RC" == 1 ]] || { cat "$OUT" "$ERR" >&2; log_fail "TEST-3919: --strict with a review not run under a full table: exit $RC, expected 1"; }
  [[ "$(count_in "$OUT" "$REVIEW_WARN")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-3919: the review warning was not printed once"; }
  [[ "$(count_in "$OUT" "BLOCKED (strict mode)")" == 1 ]] || { cat "$OUT" "$ERR" >&2; log_fail "TEST-3919: the BLOCKED (strict mode) summary was not printed"; }
  [[ "$(count_in "$ERR" "cannot duplicate fd")" == 0 ]] || { cat "$ERR" >&2; log_fail "TEST-3919: --strict: a builtin redirection could not save its descriptor"; }
  log_pass "TEST-3919: at the 256 limit with descriptors 10..254 inherited, an added ignored path is reported and blocks with its summary, a --strict review warning blocks with its summary, and no redirection fails to save a descriptor"
}

# builtin_redir_scan <script>: prints every line of a bash script holding a redirection on a builtin, a shell
# function or a compound command (done, fi, }, esac): the redirections bash 3.2 must save a descriptor for. Quoted
# text and comments are dropped first; a simple command is split at |, &&, ||, ;, $( and ( and judged by its first
# word after assignments, a case pattern (`x)`) and if/then/else/elif/do/while/until/!; command substitutions and
# backticks are blanked first. The two permanent `exec N< file` opens (they save nothing) are the only builtin
# redirections allowed. A here-string or here-document is reported too. A lexical scan, not a parser: a shape outside
# the planted set below can escape it; TEST-3919 guards the behaviour under a full descriptor table.
builtin_redir_scan() {
  node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8").split("\n");
    const builtins = new Set(("alias bg bind break builtin caller cd command compgen complete continue declare dirs disown " +
      "echo enable eval exec exit export false fc fg getopts hash help history jobs kill let local logout mapfile popd " +
      "printf pushd pwd read readarray readonly return set shift shopt source suspend test times trap true type typeset " +
      "ulimit umask unalias unset wait : . [ [[ done fi } esac").split(" "));
    const fns = new Set();
    for (const l of src) { const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{/.exec(l); if (m) fns.add(m[1]); }
    const lead = new Set(["if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"]);
    const out = [];
    src.forEach((raw, i) => {
      if (/^\s*#/.test(raw)) return;
      let l = raw.replace(/\x27[^\x27]*\x27/g, "Q").replace(/"(?:\\.|[^"\\])*"/g, "Q").replace(/\s#.*$/, "");
      for (let prev = ""; prev !== l;) { prev = l; l = l.replace(/\$\([^()]*\)/g, "Q").replace(/`[^`]*`/g, "Q"); }
      if (/<</.test(l)) { out.push((i + 1) + ": here-string or here-document: " + raw.trim()); return; }
      if (/^\s*exec [34]< Q/.test(l)) return;
      for (const seg of l.split(/\|\||&&|\||;|\$\(|\(/)) {
        if (!/[0-9]?(>>?|<)&?/.test(seg.replace(/\[\[.*?\]\]/g, ""))) continue;
        if (/\)\s*[0-9]?(>>?|<)/.test(seg)) continue;   // ( ... ) >: the subshell redirects in its own child
        const words = seg.replace(/^\s*case\s+\S+\s+in\s+/, "").trim().split(/\s+/).filter(Boolean);
        let k = 0;
        while (k < words.length && (lead.has(words[k]) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k]) || /.\)$/.test(words[k]))) k++;
        const w = words[k] ?? "";
        if (w === ")" || /^\)/.test(w)) continue;
        if (builtins.has(w) || fns.has(w) || /^[0-9]?(>>?|<)/.test(w)) out.push((i + 1) + ": " + (w || "(none)") + ": " + raw.trim());
      }
    });
    process.stdout.write(out.join("\n"));
  ' "$1"
}

test_3920_no_builtin_redirection_text() {
  local bad probe="$TEST_DIR/t3920-probe.sh" m
  bad="$(builtin_redir_scan "$SH_CHECKS")"
  [[ -z "$bad" ]] || log_fail "TEST-3920: pre-commit-checks.sh holds a builtin, function or compound-command redirection: $bad"
  bad="$(awk '/command -v/ && !/\( command -v [a-z]+ \)/ { print FNR": "$0 }' "$SH_CHECKS")"
  [[ -z "$bad" ]] || log_fail "TEST-3920: command -v outside the subshell form: $bad"
  [[ "$("$GREP" -c '( command -v [a-z]* )' "$SH_CHECKS" || true)" -ge 3 ]] || log_fail "TEST-3920: CHECKs 7, 8 and 9 do not test for their tool in a subshell"
  # the scan itself must see each shape it claims to forbid (one planted line each, in a copy)
  for m in 'hash node >/dev/null 2>&1' 'command -v node >/dev/null 2>&1' 'echo "x" > "$PCC_TMP/f"' 'read -r x < "$PCC_TMP/f"' \
    'pass "ok" 2>/dev/null' ': > "$PCC_TMP/f"' 'grep -q x <<< "$y"' 'done < "$PCC_TMP/f"' '} >/dev/null' 'if [ -f x ] && type node >/dev/null; then :; fi' \
    'case "$x" in *) staged_read_fail "y" >&2 ;; esac' 'case "$x" in D|U) warn x >&2 ;; esac' 'echo $(date) >/dev/null' 'echo `date` >/dev/null'; do
    { cat "$SH_CHECKS"; printf '%s\n' "$m"; } > "$probe"
    [[ -n "$(builtin_redir_scan "$probe")" ]] || log_fail "TEST-3920: the scan does not see a planted builtin redirection: $m"
  done
  log_pass "TEST-3920: pre-commit-checks.sh holds no redirection on a builtin, a function or a compound command (only the two exec opens), no here-string or here-document, and tests for a tool only in a subshell; the scan sees each planted shape (a lexical scan: TEST-3919 guards the behaviour)"
}

test_3921_preservation_and_moved_pins() {
  local sel
  for sel in test_3451_large_state_check1_check5 test_3454_small_input_parity test_3461_line_budget_and_follow_up \
    test_3873_response_count_mismatch_fails_closed test_3880_descriptor_exhaustion_fails_closed \
    test_3881_list_count_crosscheck_fails_closed test_3885_trap_closes_descriptors_before_cleanup; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-pre-commit-checks.sh" "$sel" >"$TEST_DIR/self3921.out" 2>&1 || { tail -10 "$TEST_DIR/self3921.out" >&2; log_fail "TEST-3921: $sel failed"; }
  done
  log_pass "TEST-3921: TEST-3451, the seven-fixture parity and its numstat pin, the line-count pin, TEST-3873, TEST-3880, TEST-3881 and TEST-3885 hold"
}

test_3922_changelog_and_product_doc() {
  local cl="$PROJECT_ROOT/CHANGELOG.md" doc="$PROJECT_ROOT/docs/product/docs-close-gate.md" n
  n="$("$GREP" -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — fix: commit-time guards skip a deleted linked spec' "$cl" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3922: CHANGELOG.md holds $n headings for this fix, want exactly 1"
  "$GREP" -qF "the commit deletes is not read" "$doc" || log_fail "TEST-3922: the product doc must say a linked spec the commit deletes is not read"
  log_pass "TEST-3922: one CHANGELOG heading, and the product doc states the deletion policy"
}

# sg_strip_detail <file>: the file without the finding detail lines D-OUTPUT adds under each secret hit.
sg_strip_detail() { sed -E '/^    line [0-9]+, fingerprint [0-9a-f]+$/d;/^    \.\.\. and [0-9]+ more$/d' "$1"; }

# build_ac06 <dir> <script>: the Spec-AC-06 fixture, staged and unstaged shapes in one repository.
build_ac06() {
  local d="$1" line n sub
  line="$(secret_line)"
  make_fx "$d" "$2"
  printf 'conflict base\n' > "$d/conflict.txt"
  printf 'to delete\n' > "$d/gone.txt"
  printf 'moved: line one\nline two\nline three\n' > "$d/oldname.txt"
  git -C "$d" add -A
  git -C "$d" commit -q -m base
  git -C "$d" checkout -q -b side
  printf 'conflict side\n' > "$d/conflict.txt"
  git -C "$d" commit -q -am side
  git -C "$d" checkout -q -
  printf 'conflict main\n' > "$d/conflict.txt"
  git -C "$d" commit -q -am mainside
  git -C "$d" merge side >/dev/null 2>&1 || true
  for n in "with space.txt" "-dash.txt" "$(printf 'new\nline.txt')" "$(printf 'car\rret.txt')" "café.txt"; do
    stage_file "$d" "$n" "$line"
  done
  git -C "$d" mv oldname.txt moved-dest.txt
  printf '%s\n' "$line" >> "$d/moved-dest.txt"
  git -C "$d" add moved-dest.txt
  stage_file "$d" removed-later.txt "$line"
  rm -f "$d/removed-later.txt"
  git -C "$d" rm -q gone.txt
  git -C "$d" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,sub
  printf 'console.log(1)\0\nbinary\n' > "$d/bin.dat"
  : > "$d/empty.txt"
  ln -s target "$d/link"
  { awk 'BEGIN { for (i = 1; i <= 50000; i++) printf "filler_%06d: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i }'; echo "$line"; } > "$d/big32.txt"
  printf 'console.log(1);\n// FIXME later\n' > "$d/app.js"
  git -C "$d" add -f bin.dat empty.txt link big32.txt app.js
  sub="$(wc -c < "$d/big32.txt" | tr -d ' ')"
  [[ "$sub" -ge 3200000 ]] || log_fail "TEST-3876: the big fixture is $sub bytes, expected at least 3200000"
}

test_3876_semantics_match_the_baseline_script() {
  local base a b rca rcb nongit="$TEST_DIR/t3876-nongit" k
  base="$(pre_batch_script)"
  if [[ -z "$base" ]]; then
    [[ -z "${CI:-}" ]] || log_fail "TEST-3876: baseline commit $PRE_BATCH_SHA is not in this clone on CI"
    echo "SKIP-CASE: TEST-3876 needs commit $PRE_BATCH_SHA in this clone"
    return 0
  fi
  a="$TEST_DIR/t3876-new"; b="$TEST_DIR/t3876-old"
  build_ac06 "$a" "$SH_CHECKS"
  build_ac06 "$b" "$base"
  run_with "$a" ""; rca="$RC"; cp "$OUT" "$TEST_DIR/t3876-new.out"; cp "$ERR" "$TEST_DIR/t3876-new.err"
  run_with "$b" ""; rcb="$RC"; cp "$OUT" "$TEST_DIR/t3876-old.out"; cp "$ERR" "$TEST_DIR/t3876-old.err"
  [[ "$rca" == "$rcb" ]] || log_fail "TEST-3876: exit code $rca differs from the 03f3e6df script's $rcb"
  # secrets-gate-false-positives (D-AMEND): the new script's finding detail lines are removed from ITS output only
  sg_strip_detail "$TEST_DIR/t3876-new.out" > "$TEST_DIR/t3876-new.flt"
  cmp -s "$TEST_DIR/t3876-new.flt" "$TEST_DIR/t3876-old.out" || { diff "$TEST_DIR/t3876-old.out" "$TEST_DIR/t3876-new.flt" >&2 || true; log_fail "TEST-3876: stdout differs from the 03f3e6df script"; }
  cmp -s "$TEST_DIR/t3876-new.err" "$TEST_DIR/t3876-old.err" || log_fail "TEST-3876: stderr differs from the 03f3e6df script"
  [[ "$(count_in "$TEST_DIR/t3876-new.out" "$FAIL_CLOSED")" == 0 ]] || log_fail "TEST-3876: a fail-closed line was printed on the fixture"
  [[ "$(count_in "$TEST_DIR/t3876-new.out" "$SECRET_HIT")" -ge 5 ]] || { cat "$TEST_DIR/t3876-new.out" >&2; log_fail "TEST-3876: positive control: fewer than 5 secret hits, the fixture is not exercising the scan"; }
  mkdir -p "$nongit/.aai/scripts"
  for k in new old; do
    if [[ "$k" == new ]]; then cp "$SH_CHECKS" "$nongit/.aai/scripts/pre-commit-checks.sh"; else cp "$base" "$nongit/.aai/scripts/pre-commit-checks.sh"; fi
    ( cd "$nongit" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CEILING_DIRECTORIES="$TEST_DIR" bash .aai/scripts/pre-commit-checks.sh ) >"$TEST_DIR/t3876-ng-$k.out" 2>"$TEST_DIR/t3876-ng-$k.err" && RC=0 || RC=$?
    [[ "$RC" == 0 ]] || { cat "$TEST_DIR/t3876-ng-$k.out" >&2; log_fail "TEST-3876: the $k script outside a work tree exited $RC, expected 0"; }
  done
  cmp -s "$TEST_DIR/t3876-ng-new.out" "$TEST_DIR/t3876-ng-old.out" || { diff "$TEST_DIR/t3876-ng-old.out" "$TEST_DIR/t3876-ng-new.out" >&2 || true; log_fail "TEST-3876: stdout outside a work tree differs"; }
  cmp -s "$TEST_DIR/t3876-ng-new.err" "$TEST_DIR/t3876-ng-old.err" || log_fail "TEST-3876: stderr outside a work tree differs"
  # cwd inside the git directory: outside a work tree, but the index is readable from there (03f3e6df
  # read it from $(pwd) and blocked a staged secret; D7 keeps that). Clean and secret shapes, both scripts.
  local shape gd rcn rco
  for shape in clean secret; do
    gd="$TEST_DIR/t3876-gd-$shape"
    make_fx "$gd"
    if [[ "$shape" == clean ]]; then printf 'var a = 1;\n' > "$gd/a.js"; git -C "$gd" add a.js
    else printf '%s\n' "$(secret_line)" > "$gd/b.txt"; git -C "$gd" add b.txt; fi
    rcn=0; rco=0
    ( cd "$gd/.git" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$SH_CHECKS" ) >"$TEST_DIR/t3876-gd-new.out" 2>"$TEST_DIR/t3876-gd-new.err" || rcn=$?
    ( cd "$gd/.git" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$base" ) >"$TEST_DIR/t3876-gd-old.out" 2>"$TEST_DIR/t3876-gd-old.err" || rco=$?
    [[ "$rcn" == "$rco" ]] || { cat "$TEST_DIR/t3876-gd-new.out" >&2; log_fail "TEST-3876: cwd inside .git, $shape shape: exit code $rcn differs from the 03f3e6df script's $rco"; }
    sg_strip_detail "$TEST_DIR/t3876-gd-new.out" > "$TEST_DIR/t3876-gd-new.flt"
    cmp -s "$TEST_DIR/t3876-gd-new.flt" "$TEST_DIR/t3876-gd-old.out" || { diff "$TEST_DIR/t3876-gd-old.out" "$TEST_DIR/t3876-gd-new.flt" >&2 || true; log_fail "TEST-3876: cwd inside .git, $shape shape: stdout differs from the 03f3e6df script"; }
    cmp -s "$TEST_DIR/t3876-gd-new.err" "$TEST_DIR/t3876-gd-old.err" || log_fail "TEST-3876: cwd inside .git, $shape shape: stderr differs from the 03f3e6df script"
    if [[ "$shape" == secret ]]; then
      [[ "$rcn" == 1 ]] || log_fail "TEST-3876: cwd inside .git, secret shape: exit $rcn, expected 1 (the staged secret must block)"
      [[ "$(count_in "$TEST_DIR/t3876-gd-new.out" "$SECRET_HIT")" == 1 ]] || log_fail "TEST-3876: cwd inside .git, secret shape: the secret hit was not reported once"
    fi
  done
  log_pass "TEST-3876: the fixture of odd names, deletions, an unmerged path, a gitlink, binary, empty, symlink and 3.2 MB content gives the 03f3e6df script's stdout, stderr and exit code, as does a directory outside a work tree and a cwd inside .git (clean and secret shapes)"
}

test_3877_preservation_and_moved_pins() {
  local f sel
  for sel in test_3454_small_input_parity test_3455_ratchet_counts_the_file test_3461_line_budget_and_follow_up \
    test_3864_deleted_worktree_copy_still_scanned test_3866_non_ascii_names_checked; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-pre-commit-checks.sh" "$sel" >"$TEST_DIR/self.out" 2>&1 || { tail -10 "$TEST_DIR/self.out" >&2; log_fail "TEST-3877: $sel failed"; }
  done
  for f in test_3860 test_3861 test_3862 test_3863 test_3869 test_3870; do
    "$GREP" -oE "^${f}[a-z0-9_]*\(\)" "$SCRIPT_DIR/test-aai-docs-audit.sh" > "$TEST_DIR/da.names" || true
    sel="$(sed -n 1p "$TEST_DIR/da.names" | tr -d '()')"
    [[ -n "$sel" ]] || log_fail "TEST-3877: no $f case in test-aai-docs-audit.sh"
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-docs-audit.sh" "$sel" >"$TEST_DIR/da.out" 2>&1 || { tail -10 "$TEST_DIR/da.out" >&2; log_fail "TEST-3877: test-aai-docs-audit.sh $sel failed"; }
  done
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >"$TEST_DIR/cd.out" 2>&1 || { cat "$TEST_DIR/cd.out" >&2; log_fail "TEST-3877: check-cd-subshell-leak.mjs failed"; }
  log_pass "TEST-3877: the seven-fixture parity and its numstat pin, the 0-site ratchet, the line-count pin, the moved SPEC-0300 cases, the docs-audit cases and the cd-subshell-leak check hold"
}

test_3878_changelog_entry() {
  local cl="$PROJECT_ROOT/CHANGELOG.md" n body
  n="$("$GREP" -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — perf: pre-commit checks read the staged content in one batched index read' "$cl" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3878: CHANGELOG.md holds $n headings for this change, want exactly 1"
  body="$(awk '/^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — perf: pre-commit checks read the staged content in one batched index read/{f=1; next} f && /^## /{exit} f' "$cl")"
  [[ "$body" == *"$FAIL_CLOSED"* ]] || log_fail "TEST-3878: the CHANGELOG entry does not name the '$FAIL_CLOSED' message"
  log_pass "TEST-3878: the CHANGELOG holds one heading for the batched read and its entry names the fail-closed message"
}

test_3879_installed_hook_reads_the_commits_index() {
  local fx="$TEST_DIR/t3879" head_before i n
  make_fx "$fx"
  vendor_hook_installer "$fx" sh
  aai_assert_hooks_under "$fx" "$TEST_DIR" || log_fail "TEST-3879: the hooks path of $fx lies outside the scratch root"
  ( cd "$fx" && aai_git_scrubbed bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/inst3879.out" 2>&1 || { cat "$TEST_DIR/inst3879.out" >&2; log_fail "TEST-3879: the hook installer failed"; }
  git -C "$fx" checkout -q -b work
  mkdir -p "$fx/app"
  printf 'clean\n' > "$fx/app/config.txt"
  git -C "$fx" add app/config.txt
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m clean ) >"$TEST_DIR/c3879.out" 2>&1 || { cat "$TEST_DIR/c3879.out" >&2; log_fail "TEST-3879: the clean seed commit failed"; }
  secret_line > "$fx/app/config.txt"
  echo >> "$fx/app/config.txt"
  head_before="$(git -C "$fx" rev-parse HEAD)"
  RC=0
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m x -- app/config.txt ) >"$TEST_DIR/c3879.out" 2>&1 || RC=$?
  [[ "$RC" != 0 ]] || { cat "$TEST_DIR/c3879.out" >&2; log_fail "TEST-3879: the partial commit of a secret exited 0"; }
  [[ "$(git -C "$fx" rev-parse HEAD)" == "$head_before" ]] || log_fail "TEST-3879: HEAD moved on the blocked partial commit"
  n="$(count_in "$TEST_DIR/c3879.out" "$SECRET_HIT app/config.txt")"
  [[ "$n" == 1 ]] || { cat "$TEST_DIR/c3879.out" >&2; log_fail "TEST-3879: '$SECRET_HIT app/config.txt' printed $n time(s), expected 1"; }
  printf 'clean\n' > "$fx/app/config.txt"
  for i in $(seq 1 40); do printf 'clean %d\n' "$i" > "$fx/n$i.txt"; done
  git -C "$fx" add -A
  head_before="$(git -C "$fx" rev-parse HEAD)"
  RC=0
  ( cd "$fx" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m forty ) >"$TEST_DIR/c3879b.out" 2>&1 || RC=$?
  [[ "$RC" == 0 ]] || { cat "$TEST_DIR/c3879b.out" >&2; log_fail "TEST-3879: committing 40 clean files through the hook exited $RC"; }
  [[ "$(git -C "$fx" rev-parse HEAD)" != "$head_before" ]] || log_fail "TEST-3879: HEAD did not move for the 40-file commit"
  log_pass "TEST-3879: through the installed hook a partial commit is judged on the commit's own index (blocked, HEAD unmoved) and 40 clean staged files commit"
}

# --- secrets-gate-false-positives (docs/specs/SPEC-DRAFT-secrets-gate-false-positives.md, TEST-4080..4110) -------
# CHECK 2 judges values by shape, a name hit selects rules instead of blocking, and a reviewed allowlist read from
# the index exempts false positives. Every fixture value any rule would flag is assembled at run time (D-FIXTURES),
# so this suite passes the gate it tests with no allowlist entry (TEST-4100).
SG_ALLOW="docs/ai/secrets-allowlist.txt"
SG_ALLOWED_LINE="Secrets allowlist: "

# sg_gen <n>: n deterministic letters and digits (no repeated or placeholder-looking run).
sg_gen() { awk -v n="$1" 'BEGIN { s = "aB3dE5gH7jK9mN2pQ4sT6vW8yZ1"; o = ""; for (i = 0; i < n; i++) o = o substr(s, (i % 27) + 1, 1); printf "%s", o }'; }
sg_aws() { printf '%s%s%s' AK IA "$(sg_gen 16 | tr a-z A-Z)"; }
sg_ghp() { printf '%s_%s' "${1:-ghp}" "$(sg_gen 36)"; }
sg_pat() { printf '%s_%s_%s_%s' github pat "$(sg_gen 22)" "$(sg_gen 59)"; }
# sg_block <words incl. trailing blank or empty> [body]: a private key block (header, body line, footer).
sg_block() { printf '%s%s%s\n%s\n%s%s%s' '-----BEGIN ' "$1" 'PRIVATE KEY-----' "${2:-$(sg_gen 64)}" '-----END ' "$1" 'PRIVATE KEY-----'; }

# sg_count <kind> <path>: lines of the last run's stdout that print exactly that kind and path.
sg_count() { count_in "$OUT" "$1 $2"$'\033'; }

# sg_found <file>: the paths the file's CHECK 2 lines report as holding a secret.
sg_found() { sed -n 's/^.*Potential secret detected in \(.*\)'$'\033''\[0m$/\1/p' "$1"; }

# sg_pass <TEST id> <fixture>: the run exits 0 and prints neither a secret nor a sensitive-file line.
sg_pass() {
  run_checks "$2"
  [[ "$RC" == 0 && "$(count_in "$OUT" "$SECRET_HIT")" == 0 && "$(count_in "$OUT" "$SENSITIVE")" == 0 ]] || { cat "$OUT" >&2; log_fail "$1: exit $RC, expected 0 with no '$SECRET_HIT' and no '$SENSITIVE' line"; }
}

# sg_blocks <TEST id> <fixture> <kind> <path>...: exit 1 and exactly one line of that kind for each path, no other.
sg_blocks() {
  local id="$1" fx="$2" kind="$3" p
  shift 3
  run_checks "$fx"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: exit $RC, expected 1"; }
  for p in "$@"; do
    [[ "$(sg_count "$kind" "$p")" == 1 ]] || { cat "$OUT" >&2; log_fail "$id: '$kind $p' printed $(sg_count "$kind" "$p") time(s), expected 1"; }
  done
  [[ "$(count_in "$OUT" "$kind")" == "$#" ]] || { cat "$OUT" >&2; log_fail "$id: $(count_in "$OUT" "$kind") '$kind' line(s), expected $#"; }
}

# sg_labels <fixture> <value> <key>...: stages one YAML file per key holding key: "value" (assembled).
sg_stage_kv() { stage_file "$1" "$2" "$(printf '%s: "%s"' "$3" "$4")"; }

test_4080_labels_with_blanks_pass() {
  local fx="$TEST_DIR/t4080"
  make_fx "$fx"
  sg_stage_kv "$fx" locales/en.yml forgotPassword 'Forgot your password?'
  stage_file "$fx" locales/en.js "$(printf '  %s: "%s",' forgotPassword 'Forgot your password?')"
  stage_file "$fx" locales/en.json "$(printf '{"%s": "%s"}' forgotPassword 'Forgot your password?')"
  stage_file "$fx" scripts/ask.sh "$(printf "%s='%s'" password 'Enter your password')"
  sg_stage_kv "$fx" locales/tab.yml passwd "$(printf 'abcd\tefgh%s' 12345)"
  sg_pass TEST-4080 "$fx"
  log_pass "TEST-4080: keyed assignments whose value holds a space or a tab (YAML, JS, JSON, shell) are not findings"
}

test_4081_wordlike_labels_pass() {
  local fx="$TEST_DIR/t4081"
  make_fx "$fx"
  sg_stage_kv "$fx" locales/de.yml resetPassword Passwort
  sg_stage_kv "$fx" locales/cs.yml password 'Přihlášení'
  sg_stage_kv "$fx" locales/fr.yml passwordHint 'Mot-de-passe'
  sg_stage_kv "$fx" locales/en.yml password 'Forgot-password?'
  sg_pass TEST-4081 "$fx"
  log_pass "TEST-4081: word-like values (Passwort, Přihlášení, Mot-de-passe, Forgot-password?) are not findings"
}

test_4082_references_pass() {
  local fx="$TEST_DIR/t4082"
  make_fx "$fx"
  stage_file "$fx" ci/a.sh "$(printf '%s="%s"' password '${DB_PASSWORD}')"
  sg_stage_kv "$fx" ci/b.yml api_key '$API_KEY'
  sg_stage_kv "$fx" ci/c.yml password '{{vault_db_password}}'
  sg_stage_kv "$fx" ci/d.js apiKey 'process.env.API_KEY'
  sg_stage_kv "$fx" ci/e.yml password '%DB_PASSWORD%'
  sg_pass TEST-4082 "$fx"
  log_pass "TEST-4082: variable and template references are not findings"
}

test_4083_placeholders_pass() {
  local fx="$TEST_DIR/t4083" v i=0
  make_fx "$fx"
  for v in '<your-api-key>' xxxxxxxx '********' changeme123 your-api-key-here REPLACE_ME_LATER; do
    i=$((i + 1))
    sg_stage_kv "$fx" "cfg/p$i.yml" api_key "$v"
  done
  sg_pass TEST-4083 "$fx"
  log_pass "TEST-4083: placeholder values (angle brackets, repeated characters, changeme, your-...-here, REPLACE_ME) are not findings"
}

test_4084_plain_urls_pass() {
  local fx="$TEST_DIR/t4084"
  make_fx "$fx"
  stage_file "$fx" .env.example "$(printf '%s=%s' TOKEN_URL https://auth.acme.io/oauth/token)"
  stage_file "$fx" cfg/url.yml "$(printf '%s: "%s"' token_url https://auth.acme.io/oauth/token)"
  sg_pass TEST-4084 "$fx"
  log_pass "TEST-4084: a URL without credentials is not a finding (a .env.example with a token URL commits)"
}

test_4085_name_hits_scanned_not_blocked() {
  local fx="$TEST_DIR/t4085"
  make_fx "$fx"
  stage_file "$fx" .env.example "$(printf '%s=\n%s=%s' API_KEY DB_PASSWORD '<your-password>')"
  stage_file "$fx" .env.sample "$(printf '%s=%s' SECRET_KEY changeme)"
  stage_file "$fx" .env.template "$(printf '%s=%s' STRIPE_TOKEN '${STRIPE_TOKEN}')"
  stage_file "$fx" .env "$(printf 'NODE_ENV=production\nPORT=3000')"
  stage_file "$fx" config/credentials.json '{"service": "billing", "region": "eu"}'
  stage_file "$fx" docs/secret-rotation.md "Rotate the keys every 90 days; each token expires after one hour."
  stage_file "$fx" docs/ai/tdd/.env.prod "$(printf '%s=' DB_PASSWORD)"
  sg_pass TEST-4085 "$fx"
  log_pass "TEST-4085: name-hit files with empty, placeholder, reference or plain values are scanned and pass (no Sensitive line)"
}

test_4086_keyfiles_and_binary_blocked() {
  local fx p i=0 e
  for e in key pem p12 pfx jks keystore; do
    i=$((i + 1))
    fx="$TEST_DIR/t4086-$i"
    make_fx "$fx"
    stage_file "$fx" "keys/secret.$e" "harmless"
    sg_blocks TEST-4086 "$fx" "$SENSITIVE:" "keys/secret.$e"
  done
  fx="$TEST_DIR/t4086-bin"
  make_fx "$fx"
  mkdir -p "$fx/blobs"
  printf 'ab\0cd\n' > "$fx/blobs/secret-store.dat"
  git -C "$fx" add -f blobs/secret-store.dat
  sg_blocks TEST-4086 "$fx" "$SENSITIVE:" blobs/secret-store.dat
  fx="$TEST_DIR/t4086-neg"
  make_fx "$fx"
  stage_file "$fx" certs/server.pem "harmless"
  stage_file "$fx" docs/ai/tdd/secret-notes.key "harmless"
  sg_pass TEST-4086 "$fx"
  log_pass "TEST-4086: key-file extensions and a NUL blob under a name-hit path block by name (one line each); the same extension outside a name hit, and in an evidence folder, does not"
}

test_4087_aws_key_blocked() {
  local fx="$TEST_DIR/t4087" k
  k="$(sg_aws)"
  make_fx "$fx"
  stage_file "$fx" app/keyed.txt "$(printf 'aws_access = %s' "$k")"
  stage_file "$fx" app/bare.txt "$k"
  sg_blocks TEST-4087 "$fx" "$SECRET_HIT" app/keyed.txt app/bare.txt
  fx="$TEST_DIR/t4087-ok"
  make_fx "$fx"
  stage_file "$fx" app/doc.txt "$(printf '%s%s%s' AK IA IOSFODNN7EXAMPLE)"
  stage_file "$fx" app/xs.txt "$(printf '%s%s%s' AK IA XXXXXXXXXXXXXXXX)"
  stage_file "$fx" app/long.txt "$(printf 'Z%s' "$k")"
  sg_pass TEST-4087 "$fx"
  log_pass "TEST-4087: an AWS access key id is a finding keyed or bare; the EXAMPLE key, an x-filled one and one inside a longer run pass"
}

test_4088_github_classic_blocked() {
  local fx="$TEST_DIR/t4088"
  make_fx "$fx"
  stage_file "$fx" app/a.txt "$(sg_ghp ghp)"
  stage_file "$fx" app/b.txt "$(printf 'export GH=%s' "$(sg_ghp gho)")"
  sg_blocks TEST-4088 "$fx" "$SECRET_HIT" app/a.txt app/b.txt
  fx="$TEST_DIR/t4088-ok"
  make_fx "$fx"
  stage_file "$fx" app/x.txt "$(printf 'ghp_%s' "$(printf '%36s' '' | tr ' ' x)")"
  stage_file "$fx" app/short.txt "ghp_abc123"
  sg_pass TEST-4088 "$fx"
  log_pass "TEST-4088: ghp_ and gho_ tokens are findings; an x-filled one and a short one pass"
}

test_4089_github_fine_grained_blocked() {
  local fx="$TEST_DIR/t4089"
  make_fx "$fx"
  stage_file "$fx" app/pat.txt "$(sg_pat)"
  sg_blocks TEST-4089 "$fx" "$SECRET_HIT" app/pat.txt
  fx="$TEST_DIR/t4089-ok"
  make_fx "$fx"
  stage_file "$fx" app/short.txt "$(printf 'github_pat_%s_%s' "$(sg_gen 10)" "$(sg_gen 20)")"
  sg_pass TEST-4089 "$fx"
  log_pass "TEST-4089: a github_pat_ token of the 22 plus 59 shape is a finding; a short one passes"
}

test_4090_private_key_blocks_blocked() {
  local fx="$TEST_DIR/t4090" w i=0
  make_fx "$fx"
  for w in "RSA " "OPENSSH " ""; do
    i=$((i + 1))
    stage_file "$fx" "keys-in/block$i.txt" "$(sg_block "$w")"
  done
  stage_file "$fx" keys-in/pgp.txt "$(sg_block 'PGP ' | sed 's/PRIVATE KEY-----/PRIVATE KEY BLOCK-----/')"
  stage_file "$fx" keys-in/enc.txt "$(sg_block 'RSA ' 'Proc-Type: 4,ENCRYPTED')"
  sg_blocks TEST-4090 "$fx" "$SECRET_HIT" keys-in/block1.txt keys-in/block2.txt keys-in/block3.txt keys-in/pgp.txt keys-in/enc.txt
  fx="$TEST_DIR/t4090-ok"
  make_fx "$fx"
  stage_file "$fx" docs/mention.txt "$(printf '%s%s\n%s' '-----BEGIN ' 'PRIVATE KEY-----' 'is the line a key file starts with')"
  stage_file "$fx" docs/short.txt "$(sg_block '' 'short')"
  sg_pass TEST-4090 "$fx"
  log_pass "TEST-4090: RSA, OPENSSH, PKCS8, PGP and encrypted private key blocks are findings; a header-only mention and a block with a short body pass"
}

test_4091_name_hit_values_blocked() {
  local fx="$TEST_DIR/t4091" v
  v="$(sg_value)"
  make_fx "$fx"
  stage_file "$fx" .env "$(printf '%s=%s' DB_PASSWORD "$v")"
  stage_file "$fx" .env.local "$(printf '%s=sk_live_%s' STRIPE_SECRET_KEY "$v")"
  stage_file "$fx" config/credentials.json "$(printf '{"%s": "%s"}' password "$v")"
  stage_file "$fx" deploy/.env.url "$(printf '%s=postgres://app:%s@db:5432/app' DATABASE_URL "$v")"
  stage_file "$fx" docs/ai/tdd/.env.prod "$(printf 'export %s=%s' DB_PASSWORD "$v")"
  sg_blocks TEST-4091 "$fx" "$SECRET_HIT" .env .env.local config/credentials.json deploy/.env.url docs/ai/tdd/.env.prod
  log_pass "TEST-4091: dotenv, JSON and URL-credential values in name-hit files are findings, one line per file"
}

test_4092_quoted_keyed_blocked() {
  local fx="$TEST_DIR/t4092" v
  v="$(sg_value)"
  make_fx "$fx"
  stage_file "$fx" app/a.txt "$(secret_line)"
  stage_file "$fx" app/b.txt "$(printf "%s: '%s'" access_token "$v")"
  stage_file "$fx" app/c.yml "$(printf '%s="%s"' passwd "$v")"
  sg_blocks TEST-4092 "$fx" "$SECRET_HIT" app/a.txt app/b.txt app/c.yml
  log_pass "TEST-4092: quoted credential values behind api_key, access_token and passwd keys are findings in ordinary files"
}

# sg_corpus <fixture>: the false-positive and true-positive fixtures above, one per file in ordinary paths, plus the
# unkeyed shapes only a name hit may flag. Prints nothing; the files are staged.
sg_corpus() {
  local fx="$1" v n=0 l
  v="$(sg_value)"
  while IFS= read -r l; do
    n=$((n + 1))
    stage_file "$fx" "corpus/c$(printf '%02d' "$n").txt" "$l"
  done <<EOF_CORPUS
$(printf '%s: "%s"' forgotPassword 'Forgot your password?')
$(printf "%s='%s'" password 'Enter your password')
$(printf '%s: "%s"' resetPassword Passwort)
$(printf '%s: "%s"' password 'Přihlášení')
$(printf '%s="%s"' password '${DB_PASSWORD}')
$(printf '%s: "%s"' api_key '$API_KEY')
$(printf '%s: "%s"' apiKey 'process.env.API_KEY')
$(printf '%s: "%s"' api_key '<your-api-key>')
$(printf '%s: "%s"' password changeme123)
$(printf '%s: "%s"' token_url https://auth.acme.io/oauth/token)
$(printf '%s: "%s"' api_key "$v")
$(printf "%s: '%s'" access_token "$v")
$(printf '%s=%s' DB_PASSWORD "$v")
$(printf '%s=postgres://app:%s@db:5432/app' DATABASE_URL "$v")
$(printf '{"%s": "%s"}' password "$v")
$(printf '%s: "%s"' api_key "ab'$(sg_gen 12)")
$(secret_line)
$(sg_aws)
$(printf '%s%s%s' AK IA IOSFODNN7EXAMPLE)
$(sg_ghp ghp)
$(sg_pat)
EOF_CORPUS
  stage_file "$fx" corpus/block.txt "$(sg_block 'RSA ')"
  stage_file "$fx" corpus/mention.txt "$(printf '%s%s' '-----BEGIN ' 'PRIVATE KEY-----')"
}

# sg_oracle <file>: 0 when the old content regex or an R4 token pattern matches the file.
sg_oracle() {
  local old='(api[_-]?key|api[_-]?secret|password|passwd|secret[_-]?key|access[_-]?token|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}'
  local aws gh pat key
  aws="$(printf '%s%s' '(AK|AS)' 'IA[A-Z0-9]{16}')"
  gh='gh[pousr]_[A-Za-z0-9]{36}'
  pat='github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}'
  key='^-----BEGIN .*PRIVATE KEY'
  "$GREP" -qEi "$old" "$1" && return 0
  "$GREP" -qE "$aws|$gh|$pat|$key" "$1" && return 0
  return 1
}

test_4093_monotone_outside_name_hits() {
  local fx="$TEST_DIR/t4093" p n=0 bad=""
  make_fx "$fx"
  sg_corpus "$fx"
  run_checks "$fx"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4093: the corpus run exited $RC, expected 1 (it holds findings)"; }
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    n=$((n + 1))
    sg_oracle "$fx/$p" || bad="$bad $p"
  done <<EOF_REPORTED
$(sg_found "$OUT")
EOF_REPORTED
  [[ "$n" -ge 7 ]] || { cat "$OUT" >&2; log_fail "TEST-4093: only $n corpus files were reported, the corpus is not exercising the rules"; }
  [[ -z "$bad" ]] || log_fail "TEST-4093: reported outside the old-regex-or-token oracle:$bad"
  log_pass "TEST-4093: in ordinary paths the $n reported corpus files are all matched by the old regex or an R4 token pattern"
}

# sg_allow_commit <fixture> <allowlist text...>: writes the allowlist, commits it (tracked) and leaves the index clean.
sg_allow_commit() {
  local fx="$1"
  shift
  mkdir -p "$fx/docs/ai"
  printf '%s\n' "$@" > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  git -C "$fx" commit -q -m allowlist
}

test_4094_allowlist_path_entries() {
  local fx="$TEST_DIR/t4094" v
  v="$(sg_value)"
  make_fx "$fx"
  sg_allow_commit "$fx" "# reviewed" "path locales/*.yml"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_stage_kv "$fx" locales/sub/x.yml api_key "$v"
  sg_stage_kv "$fx" config/app.yml api_key "$v"
  sg_blocks TEST-4094 "$fx" "$SECRET_HIT" config/app.yml
  [[ "$(count_in "$OUT" "${SG_ALLOWED_LINE}2 finding(s) allowed by $SG_ALLOW")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4094: the allowed-count line was not printed once with 2"; }
  git -C "$fx" rm -q --cached -f config/app.yml
  sg_pass TEST-4094 "$fx"
  [[ "$(count_in "$OUT" "${SG_ALLOWED_LINE}2 finding(s)")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4094: the allowed-count line was not printed on the passing run"; }
  log_pass "TEST-4094: a tracked allowlist path entry allows two findings (counted once), another file still blocks, and without it the commit passes"
}

test_4095_fingerprint_lines_and_entries() {
  local fx="$TEST_DIR/t4095" v i line want got n h1 h2
  v="$(sg_value)"
  make_fx "$fx"
  for i in 1 2 3 4 5; do
    printf '%s: "%s%s"\n' api_key "$v" "$i"
  done > "$TEST_DIR/t4095.txt"
  mkdir -p "$fx/app"
  cp "$TEST_DIR/t4095.txt" "$fx/app/many.yml"
  git -C "$fx" add app/many.yml
  run_checks "$fx"
  [[ "$RC" == 1 && "$(sg_count "$SECRET_HIT" app/many.yml)" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: five findings did not print one '$SECRET_HIT' line (exit $RC)"; }
  [[ "$("$GREP" -c '^    line [0-9]*, fingerprint [0-9a-f]*$' "$OUT" || true)" == 3 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: expected exactly 3 detail lines"; }
  [[ "$(count_in "$OUT" "    ... and 2 more")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: the '... and 2 more' line is missing"; }
  for i in 1 2 3; do
    line="$(sed -n "${i}p" "$TEST_DIR/t4095.txt")"
    want="$(printf '%s\n%s' app/many.yml "$line" | git hash-object --stdin)"
    [[ "$(count_in "$OUT" "    line $i, fingerprint $want")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: detail line $i does not carry the D-FP fingerprint $want"; }
  done
  for line in "$v" "${v}1"; do
    [[ "$(count_in "$OUT" "$line")" == 0 && "$(count_in "$ERR" "$line")" == 0 ]] || log_fail "TEST-4095: the fixture value was printed"
  done
  # two lines; one fingerprint allowed: that finding passes, the other still blocks
  fx="$TEST_DIR/t4095b"
  make_fx "$fx"
  mkdir -p "$fx/app"
  sed -n '1,2p' "$TEST_DIR/t4095.txt" > "$fx/app/two.yml"
  h1="$(printf '%s\n%s' app/two.yml "$(sed -n 1p "$TEST_DIR/t4095.txt")" | git hash-object --stdin)"
  h2="$(printf '%s\n%s' app/two.yml "$(sed -n 2p "$TEST_DIR/t4095.txt")" | git hash-object --stdin)"
  git -C "$fx" add app/two.yml
  mkdir -p "$fx/docs/ai"
  printf 'fingerprint %s\n' "$h1" > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  run_checks "$fx"
  [[ "$RC" == 1 && "$(sg_count "$SECRET_HIT" app/two.yml)" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: with one fingerprint allowed the other line must still block (exit $RC)"; }
  [[ "$(count_in "$OUT" "    line 2, fingerprint $h2")" == 1 && "$(count_in "$OUT" "    line 1,")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: the allowed finding was reported or the other not"; }
  [[ "$(count_in "$OUT" "${SG_ALLOWED_LINE}1 finding(s)")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4095: the allowed-count line is missing"; }
  printf 'fingerprint %s\nfingerprint %s\n' "$h1" "$h2" > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_pass TEST-4095 "$fx"
  n="$(count_in "$OUT" "${SG_ALLOWED_LINE}2 finding(s)")"
  [[ "$n" == 1 ]] || log_fail "TEST-4095: both fingerprints allowed: the count line printed $n time(s), expected 1"
  log_pass "TEST-4095: detail lines carry the D-FP fingerprint (3 shown, '... and k more'), no value is printed, and a fingerprint entry allows exactly its own finding"
}

test_4096_catch_all_and_malformed_rejected() {
  local fx v bad i=0 want
  # each bad line, then a clean staged file: one error naming the reason
  for bad in '*|catch' '**|catch' '**/*|catch' '*.*|catch' '?*|catch' '[a-z]*|catch' 'pathx a|unrecognised' 'fingerprint xyz|unrecognised' \
    "fingerprint $(printf '%039d' 0)|unrecognised" 'path |unrecognised' 'bogus|unrecognised'; do
    i=$((i + 1))
    want="${bad##*|}"
    bad="${bad%|*}"
    fx="$TEST_DIR/t4096-$i"
    make_fx "$fx"
    case "$want" in
      catch) printf 'path %s\n' "$bad" > "$TEST_DIR/t4096.al" ;;
      *) printf '%s\n' "$bad" > "$TEST_DIR/t4096.al" ;;
    esac
    mkdir -p "$fx/docs/ai"
    cp "$TEST_DIR/t4096.al" "$fx/$SG_ALLOW"
    stage_file "$fx" app/clean.txt "clean"
    git -C "$fx" add -f "$SG_ALLOW"
    run_checks "$fx"
    [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4096: the allowlist line '$bad' exited $RC, expected 1"; }
    [[ "$(count_in "$OUT" "Secrets allowlist line 1:")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4096: '$bad' did not print exactly one 'Secrets allowlist line 1:' error"; }
    case "$want" in
      catch) [[ "$(count_in "$OUT" "catch-all")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4096: '$bad' did not name a catch-all"; } ;;
      *) [[ "$(count_in "$OUT" "unrecognised")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4096: '$bad' did not name an unrecognised entry"; } ;;
    esac
  done
  fx="$TEST_DIR/t4096-ok"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf '# reviewed\n\npath locales/*.yml\r\npath *.json\n   \nfingerprint %s\n' "$(printf '%040d' 0)" > "$fx/$SG_ALLOW"
  stage_file "$fx" app/clean.txt "clean"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_pass TEST-4096 "$fx"
  [[ "$(count_in "$OUT" "Secrets allowlist line")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-4096: a valid allowlist raised an error"; }
  # a bad allowlist with no judged file stays silent (the allowlist is staged and nothing else is)
  fx="$TEST_DIR/t4096-none"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf 'bogus\n' > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  git -C "$fx" commit -q -m al
  git -C "$fx" rm -q --cached "$SG_ALLOW"
  sg_pass TEST-4096 "$fx"
  log_pass "TEST-4096: a catch-all path glob or a malformed line blocks with one error naming the reason; comments, blank, CRLF and narrow globs raise none"
}

# wrapper mode blobfail (added to make_git_wrapper): `git cat-file blob` fails.
test_4097_allowlist_read_from_index() {
  local fx v wd="$TEST_DIR/w4097"
  v="$(sg_value)"
  # untracked: present in the work tree only
  fx="$TEST_DIR/t4097-untracked"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf 'path locales/*.yml\n' > "$fx/$SG_ALLOW"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_blocks TEST-4097 "$fx" "$SECRET_HIT" locales/de.yml
  # unstaged edit: tracked without the entry, the work tree adds it
  fx="$TEST_DIR/t4097-unstaged"
  make_fx "$fx"
  sg_allow_commit "$fx" "# empty"
  printf 'path locales/*.yml\n' >> "$fx/$SG_ALLOW"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_blocks TEST-4097 "$fx" "$SECRET_HIT" locales/de.yml
  # staged deletion: the entry exists in HEAD, the commit deletes the file
  fx="$TEST_DIR/t4097-deleted"
  make_fx "$fx"
  sg_allow_commit "$fx" "path locales/*.yml"
  git -C "$fx" rm -q "$SG_ALLOW"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_blocks TEST-4097 "$fx" "$SECRET_HIT" locales/de.yml
  # staged: the commit adds the allowlist with the entry
  fx="$TEST_DIR/t4097-staged"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf 'path locales/*.yml\n' > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_pass TEST-4097 "$fx"
  # tracked unchanged
  fx="$TEST_DIR/t4097-tracked"
  make_fx "$fx"
  sg_allow_commit "$fx" "path locales/*.yml"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  sg_pass TEST-4097 "$fx"
  [[ "$(count_in "$OUT" "${SG_ALLOWED_LINE}1 finding(s)")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4097: the tracked allowlist did not allow the finding"; }
  # unreadable: the index entry resolves but cat-file blob fails
  make_git_wrapper "$wd" blobfail
  run_with "$fx" "$wd"
  assert_closed TEST-4097 "secrets allowlist"
  log_pass "TEST-4097: the allowlist is the index's (untracked, unstaged and staged-deleted entries do nothing; staged and tracked ones allow); an unreadable index entry fails closed"
}

test_4098_git_process_budget() {
  local wd="$TEST_DIR/w4098" n fx lines5 lines40 v i
  v="$(sg_value)"
  make_git_wrapper "$wd" log "$TEST_DIR/t4098.log"
  for n in 5 40; do
    fx="$TEST_DIR/t4098-$n"
    make_fx "$fx"
    sg_allow_commit "$fx" "path locales/*.yml"
    for i in $(seq 1 "$n"); do printf 'var x_%d = %d;\n' "$i" "$i" > "$fx/f$i.js"; done
    git -C "$fx" add -A
    : > "$TEST_DIR/t4098.log"
    run_with "$fx" "$wd"
    [[ "$RC" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-4098: $n clean files with a tracked allowlist exited $RC"; }
    cp "$TEST_DIR/t4098.log" "$TEST_DIR/t4098-$n.lines"
    [[ "$(count_in "$TEST_DIR/t4098-$n.lines" hash-object)" == 0 ]] || log_fail "TEST-4098: $n clean files started a hash-object process"
  done
  lines5="$(wc -l < "$TEST_DIR/t4098-5.lines" | tr -d ' ')"
  lines40="$(wc -l < "$TEST_DIR/t4098-40.lines" | tr -d ' ')"
  [[ "$lines5" == "$lines40" ]] || log_fail "TEST-4098: git invocations grow with the staged count: $lines5 for 5 files, $lines40 for 40"
  fx="$TEST_DIR/t4098-find"
  make_fx "$fx"
  for i in 1 2 3; do sg_stage_kv "$fx" "app/f$i.yml" api_key "$v$i"; done
  : > "$TEST_DIR/t4098.log"
  run_with "$fx" "$wd"
  [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4098: three finding files exited $RC, expected 1"; }
  [[ "$(count_in "$TEST_DIR/t4098.log" hash-object)" == 1 ]] || { cat "$TEST_DIR/t4098.log" >&2; log_fail "TEST-4098: three finding files started $(count_in "$TEST_DIR/t4098.log" hash-object) hash-object processes, expected 1"; }
  [[ "$(count_in "$TEST_DIR/t4098.log" cat-file)" == 1 ]] || { cat "$TEST_DIR/t4098.log" >&2; log_fail "TEST-4098: with no allowlist in the index expected exactly one cat-file process"; }
  log_pass "TEST-4098: 5 and 40 clean files start $lines5 git processes each and no hash-object; three finding files start exactly one hash-object; no allowlist means exactly one cat-file"
}

# sg_hook_fx <dir>: a fixture with the delivered hook installed on a work branch.
sg_hook_fx() {
  make_fx "$1"
  vendor_hook_installer "$1" sh
  aai_assert_hooks_under "$1" "$TEST_DIR" || log_fail "TEST-4099: the hooks path of $1 lies outside the scratch root"
  ( cd "$1" && aai_git_scrubbed bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/inst4099.out" 2>&1 || { cat "$TEST_DIR/inst4099.out" >&2; log_fail "TEST-4099: the hook installer failed"; }
  git -C "$1" checkout -q -b work
}

# sg_commit <fixture>: git commit through the installed hook; sets RC and COMMIT_OUT.
sg_commit() {
  RC=0
  ( cd "$1" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m "$2" ) >"$TEST_DIR/c4099.out" 2>&1 || RC=$?
  COMMIT_OUT="$TEST_DIR/c4099.out"
}

test_4099_installed_hook_seam() {
  local fx="$TEST_DIR/t4099" head v
  v="$(sg_value)"
  sg_hook_fx "$fx"
  sg_stage_kv "$fx" locales/en.yml forgotPassword 'Forgot your password?'
  stage_file "$fx" .env.example "$(printf '%s=%s' TOKEN_URL https://auth.acme.io/oauth/token)"
  sg_stage_kv "$fx" ci/ref.yml password '${DB_PASSWORD}'
  sg_stage_kv "$fx" ci/ph.yml api_key '<your-api-key>'
  sg_stage_kv "$fx" locales/pt.yml password Passwort
  head="$(git -C "$fx" rev-parse HEAD)"
  sg_commit "$fx" labels
  [[ "$RC" == 0 && "$(git -C "$fx" rev-parse HEAD)" != "$head" ]] || { cat "$COMMIT_OUT" >&2; log_fail "TEST-4099: the false-positive commit through the hook exited $RC or HEAD did not move"; }
  stage_file "$fx" app/aws.txt "$(sg_aws)"
  stage_file "$fx" .env "$(printf '%s=%s' DB_PASSWORD "$v")"
  head="$(git -C "$fx" rev-parse HEAD)"
  sg_commit "$fx" leak
  [[ "$RC" != 0 && "$(git -C "$fx" rev-parse HEAD)" == "$head" ]] || { cat "$COMMIT_OUT" >&2; log_fail "TEST-4099: the true-positive commit exited $RC or HEAD moved"; }
  [[ "$(count_in "$COMMIT_OUT" "$SECRET_HIT app/aws.txt")" == 1 && "$(count_in "$COMMIT_OUT" "$SECRET_HIT .env")" -ge 1 ]] || { cat "$COMMIT_OUT" >&2; log_fail "TEST-4099: the blocked commit does not print the finding lines"; }
  git -C "$fx" rm -q --cached -f app/aws.txt .env
  mkdir -p "$fx/docs/ai"
  printf 'path locales/*.yml\n' > "$fx/$SG_ALLOW"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_stage_kv "$fx" locales/de.yml api_key "$v"
  head="$(git -C "$fx" rev-parse HEAD)"
  sg_commit "$fx" allowed
  [[ "$RC" == 0 && "$(git -C "$fx" rev-parse HEAD)" != "$head" ]] || { cat "$COMMIT_OUT" >&2; log_fail "TEST-4099: the allowlisted commit exited $RC or HEAD did not move"; }
  log_pass "TEST-4099: through the installed hook a false-positive commit lands, a true-positive commit is refused with its finding lines, and an allowlisted commit lands"
}

# sg_self_corpus <dir> <with allowlist 0|1>: HEAD's tracked files staged in a fresh repository, the working-tree script
# overlaid (so an uncommitted ride is judged); sets OUT.
sg_self_corpus() {
  local d="$1" with="$2"
  mkdir -p "$d"
  git -C "$PROJECT_ROOT" archive HEAD | tar -x -C "$d"
  # files of the ride not committed yet (modified or new) join the corpus (none once it is committed)
  git -C "$PROJECT_ROOT" ls-files -z -m -o --exclude-standard > "$TEST_DIR/self4100.untracked"
  if [[ -s "$TEST_DIR/self4100.untracked" ]]; then tar -c --null -T "$TEST_DIR/self4100.untracked" -C "$PROJECT_ROOT" -f - 2>/dev/null | tar -x -C "$d" || true; fi
  cp "$SH_CHECKS" "$d/.aai/scripts/pre-commit-checks.sh"
  rm -f "$d/$SG_ALLOW"
  if [[ "$with" == 1 ]]; then
    [[ -f "$PROJECT_ROOT/$SG_ALLOW" ]] || log_fail "TEST-4100: $SG_ALLOW is missing from the repository"
    mkdir -p "$d/docs/ai"
    cp "$PROJECT_ROOT/$SG_ALLOW" "$d/$SG_ALLOW"
  fi
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config core.autocrlf false
  git -C "$d" add -A -f
  RC=0
  ( cd "$d" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/pre-commit-checks.sh ) >"$TEST_DIR/self4100.out" 2>"$TEST_DIR/self4100.err" || RC=$?
  OUT="$TEST_DIR/self4100.out"
}

test_4100_self_corpus() {
  local d="$TEST_DIR/t4100" found glob p ok al n
  al="$PROJECT_ROOT/$SG_ALLOW"
  sg_self_corpus "$d" 1
  [[ "$(count_in "$OUT" "$SECRET_HIT")" == 0 && "$(count_in "$OUT" "$SENSITIVE")" == 0 && "$(count_in "$OUT" "Secrets allowlist line")" == 0 ]] || { "$GREP" -E 'Potential secret|Sensitive|Secrets allowlist|^    line' "$OUT" >&2 || true; log_fail "TEST-4100: with the repository allowlist the corpus has blocking findings"; }
  rm -rf "$d"
  sg_self_corpus "$d" 0
  cp "$OUT" "$TEST_DIR/t4100-noal.out"
  OUT="$TEST_DIR/t4100-noal.out"
  sg_found "$OUT" > "$TEST_DIR/t4100.found"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    case "$p" in tests/skills/test-aai-pre-commit-checks.sh) log_fail "TEST-4100: this suite needs an allowlist entry" ;; esac
  done < "$TEST_DIR/t4100.found"
  n=0
  while IFS= read -r p; do
    case "$p" in
      path\ *)
        glob="${p#path }"
        glob="${glob%$'\r'}"
        ok=0
        while IFS= read -r found; do
          case "$found" in $glob) ok=1 ;; esac
        done < "$TEST_DIR/t4100.found"
        [[ "$ok" == 1 ]] || log_fail "TEST-4100: the allowlist entry 'path $glob' matches no finding file of the corpus (unused entry)"
        n=$((n + 1))
        ;;
      fingerprint\ *)
        "$GREP" -qF "fingerprint ${p#fingerprint }" "$OUT" || log_fail "TEST-4100: the allowlist entry '$p' is not among the printed fingerprints (unused entry)"
        n=$((n + 1))
        ;;
    esac
  done < "$al"
  log_pass "TEST-4100: every tracked file staged passes CHECK 2 with the repository allowlist; without it the $n allowlist entries each match a finding and this suite needs none"
}

# sg_fixture_awks: the awks found on PATH (name per line).
sg_awks() {
  local a
  for a in awk mawk gawk nawk; do
    command -v "$a" >/dev/null 2>&1 && printf '%s\n' "$a"
  done
  return 0
}

# sg_c2_lines <file>: the CHECK 2 lines of a run's stdout.
sg_c2_lines() { "$GREP" -E 'Potential secret|Sensitive file|^    line |^    \.\.\.|Secrets allowlist|No secrets detected' "$1" || true; }

test_4101_portability_and_anchors() {
  local prog="$TEST_DIR/t4101.awk" a n bin sd fx ref="" cur a_name nodedir="$TEST_DIR/w4101node" ran=0
  for a in AL ""; do
    if [[ "$a" == AL ]]; then
      awk "/^PCC_AWK_AL='\$/ { f = 1; next } f && /^'\$/ { exit } f" "$SH_CHECKS" > "$prog"
    else
      awk "/^PCC_AWK='\$/ { f = 1; next } f && /^'\$/ { exit } f" "$SH_CHECKS" > "$prog"
    fi
    [[ "$(wc -l < "$prog" | tr -d ' ')" -ge 8 ]] || log_fail "TEST-4101: the awk program text was not found in pre-commit-checks.sh"
    if "$GREP" -nE '\{[0-9]' "$prog" >"$TEST_DIR/t4101.bad"; then cat "$TEST_DIR/t4101.bad" >&2; log_fail "TEST-4101: the awk program holds an interval expression"; fi
    if "$GREP" -nwE 'gensub|IGNORECASE|strtonum|asort|asorti|PROCINFO|systime' "$prog" >"$TEST_DIR/t4101.bad"; then cat "$TEST_DIR/t4101.bad" >&2; log_fail "TEST-4101: the awk program uses a gawk-only feature"; fi
    if "$GREP" -q "'" "$prog"; then log_fail "TEST-4101: the awk program holds an apostrophe (it sits in shell single quotes)"; fi
  done
  for a in 'PCC_VALUE_MINLEN=8' 'PCC_ALLOWLIST="docs/ai/secrets-allowlist.txt"' 'function has_space(v) {' 'function is_wordlike(v) {' \
    'function is_reference(v) {' 'function is_placeholder(v) {' 'function is_url(v) {' 'AKIA' 'gh[pousr]_' 'github_pat_' 'PRIVATE KEY' \
    'pcc_namehit=0' 'pcc_namehit=1' 'pcc_keyfile=0' 'pcc_keyfile=1' 'pcc_catch_all=1' '--verify ":$PCC_ALLOWLIST"' ', fingerprint ' \
    '"$pcc_nfind" -gt 0' 'No secrets detected in staged files'; do
    n="$("$GREP" -oF -- "$a" "$SH_CHECKS" | wc -l | tr -d ' ')"
    [[ "$n" == 1 ]] || log_fail "TEST-4101: the anchor '$a' occurs $n times in pre-commit-checks.sh, expected exactly 1"
  done
  [[ "$("$GREP" -oF -- 'secrets-allowlist.txt' "$SH_CHECKS" | wc -l | tr -d ' ')" == 1 ]] || log_fail "TEST-4101: the literal secrets-allowlist.txt must occur once"
  fx="$TEST_DIR/t4101"
  make_fx "$fx"
  sg_corpus "$fx"
  stage_file "$fx" .env "$(printf '%s=%s' DB_PASSWORD "$(sg_value)")"
  stage_file "$fx" keys/secret.pem "harmless"
  nodedir="$TEST_DIR/w4101node"
  mkdir -p "$nodedir"
  printf '#!/bin/sh\necho "node: unavailable" >&2\nexit 99\n' > "$nodedir/node"
  chmod +x "$nodedir/node"
  while IFS= read -r a_name; do
    [[ -n "$a_name" ]] || continue
    bin="$(command -v "$a_name")"
    sd="$TEST_DIR/w4101-$a_name"
    mkdir -p "$sd"
    ln -sf "$bin" "$sd/awk"
    run_with "$fx" "$sd"
    [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4101: the corpus run under $a_name exited $RC, expected 1"; }
    sg_c2_lines "$OUT" > "$TEST_DIR/t4101-$a_name.c2"
    [[ -s "$TEST_DIR/t4101-$a_name.c2" ]] || log_fail "TEST-4101: no CHECK 2 lines under $a_name"
    if [[ -z "$ref" ]]; then ref="$TEST_DIR/t4101-$a_name.c2"; else cmp -s "$ref" "$TEST_DIR/t4101-$a_name.c2" || { diff "$ref" "$TEST_DIR/t4101-$a_name.c2" >&2 || true; log_fail "TEST-4101: the CHECK 2 output under $a_name differs from the first awk"; }; fi
    ran=$((ran + 1))
  done < <(sg_awks)
  [[ "$ran" -ge 1 ]] || log_fail "TEST-4101: no awk on PATH"
  run_with "$fx" "$nodedir"
  sg_c2_lines "$OUT" > "$TEST_DIR/t4101-node.c2"
  cmp -s "$ref" "$TEST_DIR/t4101-node.c2" || { diff "$ref" "$TEST_DIR/t4101-node.c2" >&2 || true; log_fail "TEST-4101: CHECK 2 differs when node fails (it must not start Node)"; }
  log_pass "TEST-4101: the awk programs hold no interval expression or gawk-only feature, each D-ANCHORS string occurs once, and CHECK 2 prints identical output under $ran awk(s) and with a failing node first on PATH"
}

test_4102_preservation() {
  local sel s
  for sel in test_3454_small_input_parity test_3455_ratchet_counts_the_file test_3461_line_budget_and_follow_up test_3833_sensitive_names_still_blocked \
    test_3865_suffix_dotenv_blocked_in_evidence test_3866_non_ascii_names_checked test_3871_one_batched_read_whatever_the_count \
    test_3876_semantics_match_the_baseline_script test_3919_full_descriptor_table_reports test_3920_no_builtin_redirection_text test_4047_seterr_lint; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-pre-commit-checks.sh" "$sel" >"$TEST_DIR/self4102.out" 2>&1 || { tail -10 "$TEST_DIR/self4102.out" >&2; log_fail "TEST-4102: $sel failed"; }
  done
  # the neighbouring suites by selector (a whole-suite run nested here is what the nested-suite lint forbids); the
  # canonical verification runs the three suites whole
  for s in test-aai-install-parity.sh:test_3571_wiring test-aai-hook-installer-node.sh:test_3992_rehomed_bash_side \
    test-aai-hook-installer-node.sh:test_3995_parity_hooks test-aai-hook-installer-node.sh:test_3996_scratch_install \
    test-aai-git-hook-templates.sh:test_3433_sh_writes_templates test-aai-git-hook-templates.sh:test_3441_downstream_install; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/${s%%:*}" "${s##*:}" >"$TEST_DIR/self4102.out" 2>&1 || { tail -10 "$TEST_DIR/self4102.out" >&2; log_fail "TEST-4102: ${s%%:*} ${s##*:} failed"; }
  done
  log_pass "TEST-4102: the parity pins, ratchet, line pin, amended cases, batched read, descriptor and lint cases hold, and the install-parity wiring, hook-installer-node and git-hook-templates install cases pass"
}

test_4103_sync_leaves_allowlist() {
  local t1="$TEST_DIR/t4103-with" t2="$TEST_DIR/t4103-without" canon="$PROJECT_ROOT/.aai/system/DOCS_AI_CANON.list"
  mkdir -p "$t1/docs/ai" "$t2"
  printf '# project-owned\npath locales/*.yml\n' > "$t1/$SG_ALLOW"
  cp "$t1/$SG_ALLOW" "$TEST_DIR/t4103.before"
  git -C "$t1" init -q
  git -C "$t2" init -q
  env -u AAI_ROLE bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t1" --profile core >"$TEST_DIR/t4103a.out" 2>&1 || { tail -10 "$TEST_DIR/t4103a.out" >&2; log_fail "TEST-4103: the sync into the target with an allowlist failed"; }
  env -u AAI_ROLE bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t2" --profile core >"$TEST_DIR/t4103b.out" 2>&1 || { tail -10 "$TEST_DIR/t4103b.out" >&2; log_fail "TEST-4103: the sync into the target without one failed"; }
  cmp -s "$TEST_DIR/t4103.before" "$t1/$SG_ALLOW" || log_fail "TEST-4103: the sync changed the project allowlist"
  [[ ! -e "$t2/$SG_ALLOW" ]] || log_fail "TEST-4103: the sync created an allowlist in a target without one"
  "$GREP" -qxF 'secrets-allowlist.txt' "$canon" || log_fail "TEST-4103: DOCS_AI_CANON.list does not list secrets-allowlist.txt"
  [[ "$("$GREP" -cxF 'secrets-allowlist.txt' "$canon" || true)" == 1 ]] || log_fail "TEST-4103: DOCS_AI_CANON.list lists secrets-allowlist.txt more than once"
  log_pass "TEST-4103: aai-sync --profile core leaves a project allowlist byte-identical, creates none, and DOCS_AI_CANON.list names it once"
}

test_4104_docs_and_amendments() {
  local cl="$PROJECT_ROOT/CHANGELOG.md" doc="$PROJECT_ROOT/docs/product/pre-commit-secrets-gate.md" ug="$PROJECT_ROOT/docs/USER_GUIDE.md" n intake out
  n="$("$GREP" -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — fix: the pre-commit secrets gate judges values instead of file names and reads a reviewed allowlist' "$cl" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-4104: CHANGELOG.md holds $n headings for this fix, want exactly 1"
  [[ -f "$doc" ]] || log_fail "TEST-4104: $doc is missing"
  for n in "$SG_ALLOW" 'path <glob>' 'fingerprint <hex>' 'catch-all'; do
    "$GREP" -qF -- "$n" "$doc" || log_fail "TEST-4104: the product doc does not name '$n'"
  done
  "$GREP" -qF -- "$SG_ALLOW" "$ug" || log_fail "TEST-4104: USER_GUIDE.md does not name $SG_ALLOW"
  intake="$(ls "$PROJECT_ROOT"/docs/issues/ISSUE-*secrets-gate-false-positives*.md 2>/dev/null | sed -n 1p)"
  [[ -n "$intake" ]] || log_fail "TEST-4104: the intake document is missing"
  "$GREP" -qx 'user_visible: true' "$intake" || log_fail "TEST-4104: the intake lacks user_visible: true"
  out="$(node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --strict --json 2>&1)" || { printf '%s\n' "$out" >&2; log_fail "TEST-4104: spec-amend list --strict failed"; }
  n="$(printf '%s' "$out" | "$GREP" -o '"ref_id": "secrets-gate-false-positives"' | wc -l | tr -d ' ')"
  [[ "$n" -ge 3 ]] || log_fail "TEST-4104: spec-amend list holds $n mentions of secrets-gate-false-positives, expected the three D-AMEND records"
  log_pass "TEST-4104: one CHANGELOG heading, the product doc, USER_GUIDE and intake statements are present and spec-amend list --strict holds the three D-AMEND records"
}

# --- secrets-gate-false-positives remediation round 1 (VALIDATION V1, V2 and N1; TEST-4105..4107) ---------------------

test_4105_nul_blob_credentials_blocked() {
  local fx="$TEST_DIR/t4105" k
  k="$(sg_aws)"
  make_fx "$fx"
  mkdir -p "$fx/img"
  { printf 'x\0y '; printf '%s_key = "%s"\n' api "Qz8$(sg_value)"; } > "$fx/img/keyed.bin"
  { printf 'x\0y '; printf 'aws_access = %s\n' "$k"; } > "$fx/img/aws.bin"
  { printf 'junk\0'; sg_block ''; printf '\n'; } > "$fx/img/block.bin"
  git -C "$fx" add -f -- img/keyed.bin img/aws.bin img/block.bin
  sg_blocks TEST-4105 "$fx" "$SECRET_HIT" img/keyed.bin img/aws.bin img/block.bin
  fx="$TEST_DIR/t4105-ok"
  make_fx "$fx"
  mkdir -p "$fx/img"
  { printf 'x\0y '; printf '%s: "%s"\n' password 'Enter your password'; } > "$fx/img/label.bin"
  git -C "$fx" add -f -- img/label.bin
  sg_pass TEST-4105 "$fx"
  log_pass "TEST-4105: a keyed credential, an AWS key id and a private key block after a NUL byte on the same line of an ordinary binary blob are findings; a label there passes"
}

test_4106_real_dotenv_any_key_blocks() {
  local fx="$TEST_DIR/t4106" v i=0 key f
  v="sk_live_$(sg_value)"
  make_fx "$fx"
  for key in DB_PASS MYSQL_PWD ENCRYPTION_KEY STRIPE_KEY JWT_SIGNING_KEY; do
    i=$((i + 1))
    case "$i" in 1) f=.env ;; 2) f=.env.local ;; 3) f=deploy/prod.env ;; 4) f=.env.production ;; *) f=docs/ai/tdd/.env.test ;; esac
    stage_file "$fx" "$f" "$(printf 'export %s="%s"' "$key" "$v")"
  done
  sg_blocks TEST-4106 "$fx" "$SECRET_HIT" .env .env.local deploy/prod.env .env.production docs/ai/tdd/.env.test
  fx="$TEST_DIR/t4106-ok"
  make_fx "$fx"
  stage_file "$fx" .env "$(printf 'NODE_ENV=production\nPORT=3000\nLOG_LEVEL=debug\nAPI_BASE_URL=https://api.example.com\nGREETING=Hello there\nEMPTY_KEY=\n# a plain comment line without any assignment')"
  stage_file "$fx" .env.example "$(printf '%s=\n%s=%s' STRIPE_KEY SESSION_KEY '<your-key>')"
  stage_file "$fx" .env.sample "$(printf '%s=%s' STRIPE_KEY "$v")"
  stage_file "$fx" .env.defaults "$(printf '%s=%s' JWT_SIGNING_KEY "$v")"
  sg_pass TEST-4106 "$fx"
  log_pass "TEST-4106: in a real dotenv file every key holding a credential-shaped value is a finding (DB_PASS, MYSQL_PWD, ENCRYPTION_KEY, STRIPE_KEY, JWT_SIGNING_KEY); plain settings, URLs, empty values, plain comments and template forms pass"
}

test_4107_negated_class_catch_all_rejected() {
  local fx bad i=0
  for bad in '[!z]*' '*[!z]' '[!.]*' '[a-z]?*' '*/[!z]*' '?[!z]*'; do
    i=$((i + 1))
    fx="$TEST_DIR/t4107-$i"
    make_fx "$fx"
    mkdir -p "$fx/docs/ai"
    printf 'path %s\n' "$bad" > "$fx/$SG_ALLOW"
    stage_file "$fx" app/clean.txt "clean"
    git -C "$fx" add -f "$SG_ALLOW"
    run_checks "$fx"
    [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4107: the allowlist glob '$bad' exited $RC, expected 1"; }
    [[ "$(count_in "$OUT" "catch-all")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4107: '$bad' did not print exactly one catch-all error"; }
  done
  fx="$TEST_DIR/t4107-ok"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf 'path locales/[!z]*.yml\npath [ab]foo/*\npath app/?.json\n' > "$fx/$SG_ALLOW"
  stage_file "$fx" app/clean.txt "clean"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_pass TEST-4107 "$fx"
  [[ "$(count_in "$OUT" "catch-all")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-4107: an anchored bracket glob was rejected as a catch-all"; }
  log_pass "TEST-4107: a path glob with no literal character outside wildcards and bracket expressions is a catch-all; anchored globs with a class are accepted"
}

# --- secrets-gate-false-positives remediation round 3 (VALIDATION round 2 V3, V4 and N5; TEST-4108..4110) -----------

test_4108_inline_private_key_blocks() {
  local fx="$TEST_DIR/t4108" b m e kc ks ku
  kc="$(printf '%s%s' private Key)"
  ks="$(printf '%s%s' private_ key)"
  ku="$(printf '%s' "$ks" | tr a-z A-Z)"
  b="MIIEvQIBADANBgkqhkiG9w0BAQEFAASC$(sg_gen 40)"
  m="$(printf '%s%s%s' '-----BEGIN ' 'PRIVATE KEY-----')"
  e="$(printf '%s%s%s' '-----END ' 'PRIVATE KEY-----' '')"
  make_fx "$fx"
  stage_file "$fx" src/firebase.js "$(printf 'const %s = "%s\\n%s\\n%s\\n";' "$kc" "$m" "$b" "$e")"
  stage_file "$fx" infra/main.tf "$(printf '%s = "%s\\n%s\\n%s"' "$ks" "$m" "$b" "$e")"
  stage_file "$fx" app/settings.py "$(printf "%s = '%s\\\\\\\\n%s\\\\\\\\n%s'" "$ku" "$m" "$b" "$e")"
  stage_file "$fx" config/app.yml "$(printf '%s: "%s\\n%s\\n%s"' "$ks" "$m" "$b" "$e")"
  stage_file "$fx" .env "$(printf '%s="%s\\n%s\\n%s"' "$ku" "$m" "$b" "$e")"
  stage_file "$fx" .env.local "$(printf 'GITHUB_APP_%s="%s\n%s\n%s"' "$ku" "$m" "$b" "$e")"
  stage_file "$fx" config/service-account.json "$(printf '{"type": "service_account", "%s": "%s\\n%s\\n%s\\n"}' "$ks" "$m" "$b" "$e")"
  stage_file "$fx" src/concat.js "$(printf 'const k = "%s\\n" +\n  "%s\\n" +\n  "%s";' "$m" "$b" "$e")"
  sg_blocks TEST-4108 "$fx" "$SECRET_HIT" src/firebase.js infra/main.tf app/settings.py config/app.yml .env .env.local config/service-account.json src/concat.js
  fx="$TEST_DIR/t4108-ok"
  make_fx "$fx"
  stage_file "$fx" docs/pk-mention.md "$(printf 'The file starts with `%s` and ends with `%s`.' "$m" "$e")"
  stage_file "$fx" docs/pk-prose.md "$(printf '%s header, then the base64 body\nis described in the next section.' "$m")"
  stage_file "$fx" src/short.js "$(printf 'const k = "%s\\n%s\\n";' "$m" short)"
  stage_file "$fx" config/placeholder.yml "$(printf '%s: "%s\\n<your-key-here>\\n%s"' "$ks" "$m" "$e")"
  sg_pass TEST-4108 "$fx"
  log_pass "TEST-4108: a private key begin marker anywhere in a line, followed by a base64 body on the line (escaped or not) or on the next line, is a finding in JS, Terraform, Python, YAML, JSON, .env, .env.local and concatenated strings; a mention, a short or placeholder body passes"
}

test_4109_name_hit_any_key_blocks() {
  local fx="$TEST_DIR/t4109" v
  v="sk_live_$(sg_value)"
  make_fx "$fx"
  stage_file "$fx" .envrc "$(printf 'export DB_PASS=Zq9%s\nexport STRIPE_KEY=%s' "$(sg_gen 17)" "$v")"
  stage_file "$fx" k8s/db-secret.yaml "$(printf 'apiVersion: v1\nkind: Secret\ndata:\n  DB_PASS: %sZz9=' "$(sg_gen 20)")"
  stage_file "$fx" config/credentials.json "$(printf '{"stripe": "%s"}' "$v")"
  stage_file "$fx" deploy/secrets.toml "$(printf 'stripe = "%s"' "$v")"
  stage_file "$fx" .env.staging "$(printf '# STRIPE_KEY=%s' "$v")"
  stage_file "$fx" ops/secrets.yml "$(printf -- '- stripe: %s' "$v")"
  stage_file "$fx" scripts/load-secrets.sh "$(printf 'export DB_PASS=Zq9%s' "$(sg_gen 17)")"
  sg_blocks TEST-4109 "$fx" "$SECRET_HIT" .envrc k8s/db-secret.yaml config/credentials.json deploy/secrets.toml .env.staging ops/secrets.yml scripts/load-secrets.sh
  fx="$TEST_DIR/t4109-ok"
  make_fx "$fx"
  stage_file "$fx" .envrc "$(printf 'export NODE_ENV=production\nexport PATH_ADD=$HOME/bin\nexport GREETING="Hello there"\nexport DB_PASS=${DB_PASS}\nexport REGION=\nexport STRIPE_KEY=<your-key>')"
  stage_file "$fx" k8s/db-secret.yaml "$(printf 'kind: Secret\n  title: Přihlášení\n  label: "Forgot your password?"\n  hint: Forgot-your-password\n  url: https://auth.acme.io/oauth/token\n  DB_PASS: <your-password>')"
  stage_file "$fx" config/credentials.json '{"service": "billing", "url": "https://auth.acme.io/x", "region": "eu"}'
  stage_file "$fx" docs/secret-rotation.md "$(printf -- '---\nspec: docs/specs/SPEC-0001-x.md\nupdated: 2026-11-25\n---\nRotate the keys every 90 days; each token expires after one hour.')"
  stage_file "$fx" src/secrets.js "$(printf 'const base = basename(path);\nconst tok = argv[i];\n// KEY=v/KEY=/absent -> exists')"
  stage_file "$fx" tools/read-secrets.sh "$(printf 'E2E_DRAFT="docs/issues/CHANGE-DRAFT-x.md"\n# .env KEY=v/KEY=/absent -> exists')"
  stage_file "$fx" .env.example "$(printf '%s=%s\nSTRIPE_KEY=%s' OTHER "$v" "$v")"
  sg_pass TEST-4109 "$fx"
  log_pass "TEST-4109: in name-hit files that are not dotenv templates a credential-shaped value under any key (export, YAML, JSON, TOML, commented) is a finding in a data or config file, and an export line in any other file; labels, references, placeholders, empty values, prose, documents and code with plain assignments pass"
}

test_4110_bracket_class_catch_all_rejected() {
  local fx bad i=0
  for bad in '[!]z]*' '[![:digit:]z]*' '[^]z]*' '*[!]z]' '[![:digit:][:alpha:]]*'; do
    i=$((i + 1))
    fx="$TEST_DIR/t4110-$i"
    make_fx "$fx"
    mkdir -p "$fx/docs/ai"
    printf 'path %s\n' "$bad" > "$fx/$SG_ALLOW"
    stage_file "$fx" app/clean.txt "clean"
    git -C "$fx" add -f "$SG_ALLOW"
    run_checks "$fx"
    [[ "$RC" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4110: the allowlist glob '$bad' exited $RC, expected 1"; }
    [[ "$(count_in "$OUT" "catch-all")" == 1 ]] || { cat "$OUT" >&2; log_fail "TEST-4110: '$bad' did not print exactly one catch-all error"; }
  done
  fx="$TEST_DIR/t4110-ok"
  make_fx "$fx"
  mkdir -p "$fx/docs/ai"
  printf 'path []a]foo/*\npath [[:alpha:]]bar/*\npath docs/[![:digit:]]x.md\n' > "$fx/$SG_ALLOW"
  stage_file "$fx" app/clean.txt "clean"
  git -C "$fx" add -f "$SG_ALLOW"
  sg_pass TEST-4110 "$fx"
  [[ "$(count_in "$OUT" "catch-all")" == 0 ]] || { cat "$OUT" >&2; log_fail "TEST-4110: an anchored bracket glob was rejected as a catch-all"; }
  log_pass "TEST-4110: a negated class holding a leading ] or a POSIX class is parsed as one bracket expression, so a glob made only of such classes is a catch-all; anchored ones are accepted"
}

test_4047_seterr_lint() {
  local lint="$SCRIPT_DIR/lib/seterr-lint.mjs" out files fx
  [[ -f "$lint" ]] || log_fail "TEST-4047: $lint does not exist"
  fx="$TEST_DIR/seterr-fixtures"; mkdir -p "$fx"
  printf '#!/usr/bin/env bash\nset -euo pipefail\ncheck() { false; }\ncheck || echo recovered\n' > "$fx/with-errexit.sh"
  printf '#!/usr/bin/env bash\nset -uo pipefail\ncheck() { false; }\ncheck || echo recovered\n' > "$fx/without-errexit.sh"
  # every tracked .aai shell script: zero findings
  files="$TEST_DIR/aai-sh-files.txt"
  git -C "$PROJECT_ROOT" ls-files -z -- '.aai/**/*.sh' > "$files"
  [[ -s "$files" ]] || log_fail "TEST-4047: git lists no tracked .aai shell script"
  out="$(node -e '
    const fs = require("fs");
    import(process.argv[1]).then((m) => {
      const paths = fs.readFileSync(process.argv[2], "utf8").split("\0").filter(Boolean);
      process.stdout.write(paths.length + " " + JSON.stringify(m.lintFiles(paths)));
    });
  ' "$lint" "$files")" || log_fail "TEST-4047: the lint crashed over the tracked scripts"
  [[ "${out#* }" == "[]" ]] || log_fail "TEST-4047: findings in tracked .aai scripts: $out"
  [[ "${out%% *}" -ge 20 ]] || log_fail "TEST-4047: the lint saw only ${out%% *} scripts"
  out="$(node -e '
    import(process.argv[1]).then((m) => {
      const n = (f) => m.lintFiles([f]).length;
      process.stdout.write(n(process.argv[2]) + " " + n(process.argv[3]));
    });
  ' "$lint" "$fx/with-errexit.sh" "$fx/without-errexit.sh")" || log_fail "TEST-4047: the lint crashed over the fixtures"
  [[ "$out" == "1 0" ]] || log_fail "TEST-4047: fixture findings (with set -e, without) were '$out', expected '1 0'"
  log_pass "TEST-4047: the errexit idiom lint is clean over the tracked .aai scripts and exact over the two fixtures"
}

# node-first-leftovers D-BOM (Spec-AC-07): readGuardConfig reads a dial on the first line after a leading BOM.
test_4055_guard_config_bom() {
  local d="$TEST_DIR/t4055" got
  mkdir -p "$d"
  printf '\xef\xbb\xbfclose_gate: enforce\ndoc_number_guard: enforce\n' > "$d/docs-audit.yaml"
  got="$(GC_LIB="$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs" node --input-type=module -e '
    import { pathToFileURL } from "node:url";
    const { readGuardConfig } = await import(pathToFileURL(process.env.GC_LIB).href);
    const g = readGuardConfig(process.argv[1], { warn: () => {} });
    console.log(g.close_gate, g.doc_number_guard, g.raw.startsWith("\uFEFF"));
  ' "$d")" || log_fail "TEST-4055: the reader run failed"
  [[ "$got" == "enforce enforce true" ]] || log_fail "TEST-4055: a BOM-prefixed config read as '$got', expected 'enforce enforce true' (first dial read, raw keeps the BOM)"
  log_pass "TEST-4055: readGuardConfig reads the dial on the first line after a leading BOM and keeps the bytes in raw"
}

# node-first-leftovers D-BOM (Spec-AC-08): each shell mirror pattern, run over the conformance fixtures plus BOM fixtures, agrees with the reader.
test_4056_shell_mirrors_bom() {
  local d="$TEST_DIR/t4056" mirror file key pat label content want got line_bom
  mkdir -p "$d"
  line_bom() { printf '\xef\xbb\xbf%s\n' "$1"; }
  for mirror in "pre-commit-checks.sh|doc_number_guard|$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh" \
                "pre-commit-index.sh|close_gate|$PROJECT_ROOT/.aai/templates/git-hooks/pre-commit-index.sh" \
                "pre-commit-index.sh|body_lint|$PROJECT_ROOT/.aai/templates/git-hooks/pre-commit-index.sh" \
                "pre-push.sh|close_gate|$PROJECT_ROOT/.aai/templates/git-hooks/pre-push.sh"; do
    label="${mirror%%|*}"; file="${mirror##*|}"; key="${mirror#*|}"; key="${key%%|*}"
    pat="$(awk -F"'" -v k="$key:" '/grep -Eq/ && index($0, k) { print $(NF-1); exit }' "$file")"
    [[ -n "$pat" ]] || log_fail "TEST-4056: could not extract the $key pattern from $label"
    pat="$(printf '%b' "$pat")"
    for variant in "enforce|1|$key: enforce" "report-only|0|$key: report-only" "comment|1|$key: enforce  # note" \
                   "commented-out|0|# $key: enforce" "invalid|0|$key: enforced"; do
      content="${variant##*|}"
      want="${variant#*|}"; want="${want%%|*}"
      for bom in "" bom; do
        if [[ -n "$bom" ]]; then line_bom "$content" > "$d/c"; else printf '%s\n' "$content" > "$d/c"; fi
        got=0; "$GREP" -Eq "$pat" "$d/c" && got=1
        [[ "$got" == "$want" ]] || log_fail "TEST-4056: $label $key '${variant%%|*}' ${bom:-plain}: the mirror grep says $got, expected $want"
        if [[ "$key" != body_lint ]]; then
          # the reader reads the config dir: place the fixture where it looks
          cp "$d/c" "$d/docs-audit.yaml"
          got="$(GC_LIB="$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs" node --input-type=module -e '
            import { pathToFileURL } from "node:url";
            const { readGuardConfig } = await import(pathToFileURL(process.env.GC_LIB).href);
            console.log(readGuardConfig(process.argv[1], { warn: () => {} })[process.argv[2]]);
          ' "$d" "$key")"
          [[ "$got" == "enforce" ]] && got=1 || got=0
          [[ "$got" == "$want" ]] || log_fail "TEST-4056: $label $key '${variant%%|*}' ${bom:-plain}: the reader says $got, expected $want (the mirror agrees)"
        fi
      done
    done
  done
  log_pass "TEST-4056: every shell mirror accepts an optional leading BOM and agrees with readGuardConfig on the plain and BOM fixtures"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3448..3461, TEST-3831..3868, TEST-3871..3887, TEST-3918..3922, TEST-4080..4110)"
  check_deps
  setup_fixture
  test_3448_ps1_retired_run
  test_3449_pester
  test_3450_launcher_thin
  test_3451_large_state_check1_check5
  test_3452_large_code_review_block
  test_3453_large_debug_list
  test_3454_small_input_parity
  test_3455_ratchet_counts_the_file
  test_3456_no_live_ps1_reference
  test_3457_suites_stop_running_the_ps1
  test_3458_wiring
  test_3459_downstream_install
  test_3460_rfc
  test_3461_line_budget_and_follow_up
  test_3831_evidence_names_pass
  test_3832_content_scan_reads_staged_blob
  test_3833_sensitive_names_still_blocked
  test_3864_deleted_worktree_copy_still_scanned
  test_3865_suffix_dotenv_blocked_in_evidence
  test_3866_non_ascii_names_checked
  test_3868_changelog_and_product_doc
  test_3871_one_batched_read_whatever_the_count
  test_3872_truncation_and_write_failure_fail_closed
  test_3873_response_count_mismatch_fails_closed
  test_3874_unreadable_object_and_failed_reads_fail_closed
  test_3875_scratch_failures_and_cleanup
  test_3880_descriptor_exhaustion_fails_closed
  test_3881_list_count_crosscheck_fails_closed
  test_3882_scan_open_failure_fails_closed
  test_3876_semantics_match_the_baseline_script
  test_3877_preservation_and_moved_pins
  test_3878_changelog_entry
  test_3879_installed_hook_reads_the_commits_index
  test_3883_sentinel_ignores_the_environment
  test_3884_sentinel_covers_an_abort_before_the_list
  test_3885_trap_closes_descriptors_before_cleanup
  test_3886_check3_copy_removed_still_blocks
  test_3887_preservation_and_moved_pins
  test_3918_index_race_reread
  test_3919_full_descriptor_table_reports
  test_3920_no_builtin_redirection_text
  test_3921_preservation_and_moved_pins
  test_3922_changelog_and_product_doc
  test_4047_seterr_lint
  test_4080_labels_with_blanks_pass
  test_4081_wordlike_labels_pass
  test_4082_references_pass
  test_4083_placeholders_pass
  test_4084_plain_urls_pass
  test_4085_name_hits_scanned_not_blocked
  test_4086_keyfiles_and_binary_blocked
  test_4087_aws_key_blocked
  test_4088_github_classic_blocked
  test_4089_github_fine_grained_blocked
  test_4090_private_key_blocks_blocked
  test_4091_name_hit_values_blocked
  test_4092_quoted_keyed_blocked
  test_4093_monotone_outside_name_hits
  test_4094_allowlist_path_entries
  test_4095_fingerprint_lines_and_entries
  test_4096_catch_all_and_malformed_rejected
  test_4097_allowlist_read_from_index
  test_4098_git_process_budget
  test_4099_installed_hook_seam
  test_4100_self_corpus
  test_4101_portability_and_anchors
  test_4102_preservation
  test_4103_sync_leaves_allowlist
  test_4104_docs_and_amendments
  test_4105_nul_blob_credentials_blocked
  test_4106_real_dotenv_any_key_blocks
  test_4107_negated_class_catch_all_rejected
  test_4108_inline_private_key_blocks
  test_4109_name_hit_any_key_blocks
  test_4110_bracket_class_catch_all_rejected
  test_4055_guard_config_bom
  test_4056_shell_mirrors_bom
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
