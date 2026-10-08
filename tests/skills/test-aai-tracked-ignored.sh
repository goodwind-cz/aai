#!/usr/bin/env bash
#
# Test: tracked-ignored guard (CHANGE post-validation-pushes-reuse-test-results /
# SPEC spec-post-validation-pushes-reuse-test-results, Batch A: TEST-1700..1705).
#
# Verifies .aai/scripts/tracked-ignored.mjs --all (repository .gitignore rules
# only), the unconditional `tracked-ignored` job in skill-suite.yml wired into
# the required gate, and that the delivered tree tracks no ignored path.
#
# Fixtures are real git repos (git init -b main, own user.email/name) built
# under a scratch dir; the real repo is touched read-only by TEST-1705.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-tracked-ignored"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
SCRIPT="${TRACKED_IGNORED_SCRIPT:-$PROJECT_ROOT/.aai/scripts/tracked-ignored.mjs}"
WORKFLOW_FILE="${TRACKED_IGNORED_WORKFLOW:-$PROJECT_ROOT/.github/workflows/skill-suite.yml}"

TEST_DIR=""
cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
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

# ---- fixture helpers -------------------------------------------------

new_scratch() {
  if [[ -z "${TEST_DIR:-}" || ! -d "$TEST_DIR" ]]; then
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-tracked-ignored.XXXXXX")"
  fi
}

# fx_git <repo> <git args...> — run git in a fixture with global/system config
# neutralised so a developer's own excludes never leak in.
fx_git() {
  local repo="$1"; shift
  [[ -n "$repo" && "$repo" == /* ]] || log_fail "fixture path must be non-empty and absolute: '$repo'"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" "$@"
}

# fx_repo <name> — create an empty fixture repo, print its absolute path.
fx_repo() {
  local repo="$TEST_DIR/$1"
  mkdir -p "$repo"
  fx_git "$repo" init -q -b main
  fx_git "$repo" config user.email "fixture@example.invalid"
  fx_git "$repo" config user.name "Fixture"
  fx_git "$repo" config core.excludesFile ""
  printf '%s' "$repo"
}

# in_dir <abs dir> <cmd...> — run a command with <dir> as cwd in a plain
# subshell (never a command substitution); sets OUT (stdout+stderr) and CODE.
in_dir() {
  local dir="$1"; shift
  [[ -n "$dir" && "$dir" == /* && -d "$dir" ]] || log_fail "in_dir: bad directory '$dir'"
  local outf="$TEST_DIR/in-dir.out"
  CODE=0
  ( cd "$dir" && "$@" ) > "$outf" 2>&1 || CODE=$?
  OUT="$(cat "$outf")"
}

# run_ta <repo> <args...> — run the script in a fixture; sets OUT and CODE.
run_ta() {
  local repo="$1"; shift
  [[ -n "$repo" && "$repo" == /* && -d "$repo" ]] || log_fail "run_ta: bad fixture dir '$repo'"
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null node "$SCRIPT" "$@"
}

contains_line() {  # <payload> <fixed line>
  local _l
  while IFS= read -r _l; do
    [[ "$_l" == "$2" ]] && return 0
  done <<EOF
$1
EOF
  return 1
}

has_line_prefix() {  # <payload> <prefix>
  local _l
  while IFS= read -r _l; do
    [[ "$_l" == "$2"* ]] && return 0
  done <<EOF
$1
EOF
  return 1
}

# job_block <workflow> <job> — print the text of one top-level job (2-space key).
job_block() {
  awk -v job="  $2:" '
    $0 == job { on=1; print; next }
    on && /^  [A-Za-z0-9_-]+:/ { exit }
    on { print }
  ' "$1"
}

# job_run_text <workflow> <job> — print the run: block-scalar of the job, de-indented.
job_run_text() {
  job_block "$1" "$2" | awk '
    inrun {
      match($0, /^ */)
      if (RLENGTH >= indent) { print substr($0, indent + 1); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      inrun = 0
    }
    /^ *run: *\|/ { match($0, /^ */); inrun = 1; indent = RLENGTH + 2 }
  '
}

# ---- tests -----------------------------------------------------------

test_1700_all_lists_forced_ignored_and_clean_control() {  # Spec-AC-01
  log_info "Test: --all reports a force-added ignored file; clean repo prints none checked=n (TEST-1700)..."
  new_scratch
  local repo
  repo="$(fx_repo t1700-dirty)"
  printf 'secret.log\nout/**\n' > "$repo/.gitignore"
  printf 'x\n' > "$repo/keep.txt"
  printf 'x\n' > "$repo/secret.log"
  fx_git "$repo" add .gitignore keep.txt
  fx_git "$repo" add -f secret.log
  fx_git "$repo" commit -q -m init
  run_ta "$repo" --all
  [[ "$CODE" == "1" ]] || log_fail "TEST-1700: force-added ignored file must exit 1, got $CODE: $OUT"
  has_line_prefix "$OUT" "TRACKED_IGNORED secret.log rule=.gitignore:1:secret.log" \
    || log_fail "TEST-1700: expected a TRACKED_IGNORED line naming path and rule, got: $OUT"

  local clean
  clean="$(fx_repo t1700-clean)"
  printf 'secret.log\n' > "$clean/.gitignore"
  printf 'x\n' > "$clean/keep.txt"
  printf 'x\n' > "$clean/other.txt"
  fx_git "$clean" add .gitignore keep.txt other.txt
  fx_git "$clean" commit -q -m init
  run_ta "$clean" --all
  [[ "$CODE" == "0" ]] || log_fail "TEST-1700: clean repo must exit 0, got $CODE: $OUT"
  contains_line "$OUT" "TRACKED_IGNORED none checked=3" \
    || log_fail "TEST-1700: clean repo must print 'TRACKED_IGNORED none checked=3', got: $OUT"
  log_pass "TEST-1700: --all names the forced ignored path with its rule and passes a clean tree (TEST-1700)"
}

test_1701_nested_gitignore_and_negation() {  # Spec-AC-01
  log_info "Test: nested sub/.gitignore is honoured; a ! re-include is not reported (TEST-1701)..."
  new_scratch
  local repo
  repo="$(fx_repo t1701)"
  mkdir -p "$repo/sub" "$repo/docs/ai/reports"
  printf 'docs/ai/reports/**\n!docs/ai/reports/.gitkeep\n' > "$repo/.gitignore"
  printf '*.tmp\n' > "$repo/sub/.gitignore"
  printf '' > "$repo/docs/ai/reports/.gitkeep"
  printf 'x\n' > "$repo/docs/ai/reports/r.md"
  printf 'x\n' > "$repo/sub/a.tmp"
  printf 'x\n' > "$repo/sub/b.txt"
  fx_git "$repo" add .gitignore sub/.gitignore sub/b.txt docs/ai/reports/.gitkeep
  fx_git "$repo" add -f sub/a.tmp docs/ai/reports/r.md
  fx_git "$repo" commit -q -m init
  run_ta "$repo" --all
  [[ "$CODE" == "1" ]] || log_fail "TEST-1701: expected exit 1, got $CODE: $OUT"
  has_line_prefix "$OUT" "TRACKED_IGNORED sub/a.tmp rule=sub/.gitignore:1:*.tmp" \
    || log_fail "TEST-1701: nested sub/.gitignore match must be reported with its source, got: $OUT"
  has_line_prefix "$OUT" "TRACKED_IGNORED docs/ai/reports/r.md rule=.gitignore:1:docs/ai/reports/**" \
    || log_fail "TEST-1701: root rule match must be reported, got: $OUT"
  if has_line_prefix "$OUT" "TRACKED_IGNORED docs/ai/reports/.gitkeep"; then
    log_fail "TEST-1701: the ! re-included .gitkeep must not be reported, got: $OUT"
  fi
  if has_line_prefix "$OUT" "TRACKED_IGNORED sub/b.txt"; then
    log_fail "TEST-1701: a non-ignored sibling must not be reported, got: $OUT"
  fi
  log_pass "TEST-1701: nested rules reported, negation honoured (TEST-1701)"
}

test_1702_repo_rules_only_and_rev_mode() {  # Spec-AC-01
  log_info "Test: global excludes and info/exclude are not counted; --rev reads that revision via a temp index (TEST-1702)..."
  new_scratch
  local repo
  repo="$(fx_repo t1702)"
  printf 'x\n' > "$repo/keep.txt"
  printf 'x\n' > "$repo/globalonly.dat"
  printf 'x\n' > "$repo/infoonly.dat"
  printf 'x\n' > "$repo/repo.log"
  printf 'repo.log\n' > "$repo/.gitignore"
  fx_git "$repo" add .gitignore keep.txt globalonly.dat infoonly.dat
  fx_git "$repo" add -f repo.log
  printf 'globalonly.dat\n' > "$TEST_DIR/t1702-global-excludes"
  fx_git "$repo" config core.excludesFile "$TEST_DIR/t1702-global-excludes"
  mkdir -p "$repo/.git/info"
  printf 'infoonly.dat\n' > "$repo/.git/info/exclude"
  fx_git "$repo" commit -q -m init
  run_ta "$repo" --all
  [[ "$CODE" == "1" ]] || log_fail "TEST-1702: expected exit 1 (repo.log), got $CODE: $OUT"
  has_line_prefix "$OUT" "TRACKED_IGNORED repo.log rule=" || log_fail "TEST-1702: repo.log must be reported, got: $OUT"
  if has_line_prefix "$OUT" "TRACKED_IGNORED globalonly.dat"; then
    log_fail "TEST-1702: a path ignored only by core.excludesFile must not be reported, got: $OUT"
  fi
  if has_line_prefix "$OUT" "TRACKED_IGNORED infoonly.dat"; then
    log_fail "TEST-1702: a path ignored only by .git/info/exclude must not be reported, got: $OUT"
  fi

  # --rev: untrack repo.log in the index only; HEAD still has it.
  fx_git "$repo" rm -q --cached repo.log
  local before after
  before="$(cksum < "$repo/.git/index")"
  run_ta "$repo" --all
  [[ "$CODE" == "0" ]] || log_fail "TEST-1702: index-mode must be clean after rm --cached, got $CODE: $OUT"
  run_ta "$repo" --all --rev HEAD
  [[ "$CODE" == "1" ]] || log_fail "TEST-1702: --rev HEAD must still see repo.log, got $CODE: $OUT"
  has_line_prefix "$OUT" "TRACKED_IGNORED repo.log rule=" || log_fail "TEST-1702: --rev HEAD must list repo.log, got: $OUT"
  after="$(cksum < "$repo/.git/index")"
  [[ "$before" == "$after" ]] || log_fail "TEST-1702: --rev must leave the real index byte-identical ($before vs $after)"
  log_pass "TEST-1702: repo rules only; --rev uses a temporary index (TEST-1702)"
}

test_1703_workflow_job_and_gate_wiring() {  # Spec-AC-01
  log_info "Test: skill-suite.yml has an unconditional tracked-ignored job and the gate depends on it (TEST-1703)..."
  [[ -f "$WORKFLOW_FILE" ]] || log_fail "TEST-1703: workflow not found: $WORKFLOW_FILE"
  local job gate
  job="$(job_block "$WORKFLOW_FILE" tracked-ignored)"
  [[ -n "$job" ]] || log_fail "TEST-1703: job 'tracked-ignored' not found in the workflow"
  local l
  while IFS= read -r l; do
    case "$l" in
      *" if:"*|"    if:"*) log_fail "TEST-1703: the tracked-ignored job must be unconditional (found: $l)" ;;
    esac
  done <<EOF
$job
EOF
  case "$job" in
    *"node .aai/scripts/tracked-ignored.mjs --all"*) : ;;
    *) log_fail "TEST-1703: the job must run 'node .aai/scripts/tracked-ignored.mjs --all'" ;;
  esac
  gate="$(job_block "$WORKFLOW_FILE" gate)"
  [[ -n "$gate" ]] || log_fail "TEST-1703: gate job not found"
  case "$gate" in
    *"name: skill test suite (tests/skills/, via test-framework.sh)"*) : ;;
    *) log_fail "TEST-1703: the gate must keep its required-check name" ;;
  esac
  local needs_line=""
  while IFS= read -r l; do
    case "$l" in "    needs:"*) needs_line="$l" ;; esac
  done <<EOF
$gate
EOF
  case "$needs_line" in
    *tracked-ignored*) : ;;
    *) log_fail "TEST-1703: gate.needs must include tracked-ignored (got: $needs_line)" ;;
  esac
  case "$gate" in
    *'needs.tracked-ignored.result'*) : ;;
    *) log_fail "TEST-1703: the gate script must check needs.tracked-ignored.result" ;;
  esac
  log_pass "TEST-1703: tracked-ignored job unconditional, gate needs it and checks its result (TEST-1703)"
}

test_1704_workflow_run_text_executes_in_fixture() {  # Spec-AC-01, SEAM S1
  log_info "Test: SEAM S1 — the job's own run text, extracted from the YAML, is red on a forced ignored file and green clean (TEST-1704)..."
  new_scratch
  local run_text
  run_text="$(job_run_text "$WORKFLOW_FILE" tracked-ignored)"
  [[ -n "$run_text" ]] || log_fail "TEST-1704: could not extract a run: block from job tracked-ignored"
  local runner="$TEST_DIR/t1704-run.sh"
  printf '%s\n' "$run_text" > "$runner"

  local repo clean
  repo="$(fx_repo t1704-dirty)"
  mkdir -p "$repo/.aai/scripts"
  cp "$SCRIPT" "$repo/.aai/scripts/tracked-ignored.mjs"
  printf 'bad.log\n' > "$repo/.gitignore"
  printf 'x\n' > "$repo/bad.log"
  printf 'x\n' > "$repo/ok.txt"
  fx_git "$repo" add .gitignore ok.txt
  fx_git "$repo" add -f bad.log
  fx_git "$repo" commit -q -m init
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -e "$runner"
  [[ "$CODE" != "0" ]] || log_fail "TEST-1704: the job's run text must fail with a force-added ignored file, got exit 0: $OUT"

  clean="$(fx_repo t1704-clean)"
  mkdir -p "$clean/.aai/scripts"
  cp "$SCRIPT" "$clean/.aai/scripts/tracked-ignored.mjs"
  printf 'bad.log\n' > "$clean/.gitignore"
  printf 'x\n' > "$clean/ok.txt"
  fx_git "$clean" add .gitignore ok.txt
  fx_git "$clean" commit -q -m init
  in_dir "$clean" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash -e "$runner"
  [[ "$CODE" == "0" ]] || log_fail "TEST-1704: the job's run text must pass on a clean repo, got $CODE: $OUT"
  log_pass "TEST-1704: the workflow's run text is red with a forced file and green clean (TEST-1704)"
}

test_1705_live_tree_tracks_no_ignored_path() {  # Spec-AC-02
  log_info "Test: the live tree tracks no gitignored path (TEST-1705)..."
  [[ -d "$PROJECT_ROOT/.git" || -f "$PROJECT_ROOT/.git" ]] || log_skip "TEST-1705: not a git checkout"
  new_scratch
  in_dir "$PROJECT_ROOT" node "$SCRIPT" --all
  [[ "$CODE" == "0" ]] || log_fail "TEST-1705: tracked-ignored --all must exit 0 on the delivered tree, got $CODE: $OUT"
  local ls_out
  ls_out="$(git -C "$PROJECT_ROOT" -c core.excludesFile=/dev/null ls-files -ci --exclude-standard)"
  [[ -z "$ls_out" ]] || log_fail "TEST-1705: ls-files -ci --exclude-standard must print nothing, got: $ls_out"
  log_pass "TEST-1705: zero tracked ignored paths on the live tree (TEST-1705)"
}

main() {
  echo "Testing $TEST_NAME (post-validation-pushes-reuse-test-results, Batch A)"
  check_deps
  test_1700_all_lists_forced_ignored_and_clean_control
  test_1701_nested_gitignore_and_negation
  test_1702_repo_rules_only_and_rev_mode
  test_1703_workflow_job_and_gate_wiring
  test_1704_workflow_run_text_executes_in_fixture
  test_1705_live_tree_tracks_no_ignored_path
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Single-function invocation mode (mutation-run.mjs positional dispatch).
  if [[ -n "${1:-}" ]]; then
    "$1"
  else
    main "$@"
  fi
fi
