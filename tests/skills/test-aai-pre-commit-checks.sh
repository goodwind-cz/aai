#!/usr/bin/env bash
#
# Test: aai-pre-commit-checks
# (docs/specs/SPEC-DRAFT-spec-pre-commit-checks-ps1-retire.md, TEST-3448..3461)
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
  ( cd "$fx" && bash .aai/scripts/install-pre-commit-hook.sh ) >"$TEST_DIR/inst.out" 2>&1 || { cat "$TEST_DIR/inst.out" >&2; log_fail "TEST-3453: the hook installer failed"; }
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
  [[ "$numstat" == "7 7" ]] || log_fail "TEST-3454: git diff --numstat $BASE_SHA on the script reads '$numstat', expected '7 7'"
  log_pass "TEST-3454: seven small fixtures give the baseline's stdout, stderr and exit code, and the script differs from it in exactly 7 lines"
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

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3448..3461)"
  check_deps
  setup_fixture
  test_3451_large_state_check1_check5
  test_3452_large_code_review_block
  test_3453_large_debug_list
  test_3454_small_input_parity
  test_3455_ratchet_counts_the_file
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
