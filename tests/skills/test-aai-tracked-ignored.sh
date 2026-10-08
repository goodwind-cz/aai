#!/usr/bin/env bash
#
# Test: tracked-ignored guard (CHANGE post-validation-pushes-reuse-test-results /
# SPEC spec-post-validation-pushes-reuse-test-results, Batch A: TEST-1700..1705;
# Batch B: TEST-1706..1710).
#
# Verifies .aai/scripts/tracked-ignored.mjs --all (repository .gitignore rules
# only), the unconditional `tracked-ignored` job in skill-suite.yml wired into
# the required gate, and that the delivered tree tracks no ignored path.
#
# Batch B adds the --staged mode, CHECK 9 of pre-commit-checks.sh/.ps1 and the
# `(tracked-ignored)` label of check-committed-scope.mjs.
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

# ---- Batch B: --staged, CHECK 9 (sh + ps1), check-committed-scope -----------

SCRIPTS_DIR="${TRACKED_IGNORED_SCRIPTS_DIR:-$PROJECT_ROOT/.aai/scripts}"

# pc_fixture <name> <plain|legacy> — fixture repo carrying the scripts under
# test. plain: no tracked ignored path. legacy: mod.log and pre.log are tracked
# although `*.log` is ignored (a deliberate pre-existing exception).
pc_fixture() {
  local repo
  repo="$(fx_repo "$1")"
  mkdir -p "$repo/.aai/scripts" "$repo/docs/ai" "$repo/out"
  cp "$SCRIPTS_DIR/pre-commit-checks.sh" "$SCRIPTS_DIR/pre-commit-checks.ps1" \
     "$SCRIPTS_DIR/tracked-ignored.mjs" "$repo/.aai/scripts/"
  printf 'out/**\n*.log\n' > "$repo/.gitignore"
  printf 'x\n' > "$repo/keep.txt"
  printf 'x\n' > "$repo/other.txt"
  printf 'status: idle\n' > "$repo/docs/ai/STATE.yaml"
  fx_git "$repo" add .gitignore keep.txt other.txt docs/ai/STATE.yaml
  if [[ "$2" == "legacy" ]]; then
    printf 'x\n' > "$repo/mod.log"
    printf 'x\n' > "$repo/pre.log"
    fx_git "$repo" add -f mod.log pre.log
  fi
  fx_git "$repo" commit -q -m base
  printf '%s' "$repo"
}

# pc_run <repo> <sh|ps1> [strict] — run the pre-commit checks; sets OUT, CODE.
pc_run() {
  local repo="$1" flavor="$2" strict="${3:-}"
  [[ -n "$repo" && "$repo" == /* && -d "$repo" ]] || log_fail "pc_run: bad fixture dir '$repo'"
  if [[ "$flavor" == "sh" ]]; then
    if [[ "$strict" == "strict" ]]; then
      in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/pre-commit-checks.sh --strict
    else
      in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/pre-commit-checks.sh
    fi
  else
    if [[ "$strict" == "strict" ]]; then
      in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null pwsh -NoProfile -File .aai/scripts/pre-commit-checks.ps1 -Strict
    else
      in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null pwsh -NoProfile -File .aai/scripts/pre-commit-checks.ps1
    fi
  fi
}

out_has() {  # <needle> — substring test on $OUT
  case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac
}

# pc_cell <flavor> <cell> — build the cell's fixture, stage its change, run the
# checks; sets OUT and CODE. Cells: add rename mod modstrict del pre global
# clean strictclean.
PC_SEQ=0
pc_cell() {
  local flavor="$1" cell="$2" repo
  new_scratch
  PC_SEQ=$((PC_SEQ + 1))
  case "$cell" in
    add)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" plain)"
      printf 'n\n' > "$repo/out/new.txt"
      fx_git "$repo" add -f out/new.txt
      pc_run "$repo" "$flavor" ;;
    rename)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" plain)"
      fx_git "$repo" mv keep.txt out/keep.txt
      pc_run "$repo" "$flavor" ;;
    mod|modstrict)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" legacy)"
      printf 'changed\n' > "$repo/mod.log"
      fx_git "$repo" add mod.log
      if [[ "$cell" == "modstrict" ]]; then pc_run "$repo" "$flavor" strict; else pc_run "$repo" "$flavor"; fi ;;
    del)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" legacy)"
      fx_git "$repo" rm -q --cached mod.log pre.log
      pc_run "$repo" "$flavor" ;;
    pre)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" legacy)"
      printf 'changed\n' > "$repo/other.txt"
      fx_git "$repo" add other.txt
      pc_run "$repo" "$flavor" ;;
    global)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" plain)"
      printf 'g.dat\n' > "$TEST_DIR/c$PC_SEQ-global-excludes"
      fx_git "$repo" config core.excludesFile "$TEST_DIR/c$PC_SEQ-global-excludes"
      printf 'g\n' > "$repo/g.dat"
      printf 'i.dat\n' > "$repo/.git/info/exclude"
      printf 'i\n' > "$repo/i.dat"
      fx_git "$repo" add -f g.dat i.dat
      pc_run "$repo" "$flavor" ;;
    clean|strictclean)
      repo="$(pc_fixture "c$PC_SEQ-$flavor-$cell" plain)"
      printf 'changed\n' > "$repo/other.txt"
      fx_git "$repo" add other.txt
      if [[ "$cell" == "strictclean" ]]; then pc_run "$repo" "$flavor" strict; else pc_run "$repo" "$flavor"; fi ;;
    *) log_fail "pc_cell: unknown cell '$cell'" ;;
  esac
}

# assert_cells <flavor> <tag> — the Spec-AC-03 cell table for one flavor.
assert_cells() {
  local flavor="$1" tag="$2"
  pc_cell "$flavor" add
  [[ "$CODE" == "1" ]] || log_fail "$tag($flavor): git add -f of an ignored path must exit 1, got $CODE: $OUT"
  out_has "out/new.txt" || log_fail "$tag($flavor): refusal must name the path, got: $OUT"
  out_has ".gitignore:1:out/**" || log_fail "$tag($flavor): refusal must name the rule, got: $OUT"
  out_has '!out/new.txt' || log_fail "$tag($flavor): refusal must name the ! re-include remedy, got: $OUT"
  pc_cell "$flavor" clean
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): negation — a commit with no ignored path must exit 0, got $CODE: $OUT"
  pc_cell "$flavor" strictclean
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): negation — a clean commit must stay clean under strict, got $CODE: $OUT"
  pc_cell "$flavor" rename
  [[ "$CODE" == "1" ]] || log_fail "$tag($flavor): a rename INTO an ignored dir must exit 1, got $CODE: $OUT"
  out_has "out/keep.txt" || log_fail "$tag($flavor): rename refusal must name the destination, got: $OUT"
  pc_cell "$flavor" mod
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): a modified tracked ignored path warns and exits 0, got $CODE: $OUT"
  out_has "mod.log" || log_fail "$tag($flavor): the modified-path warning must name mod.log, got: $OUT"
  out_has "modified" || log_fail "$tag($flavor): the warning must say modified, got: $OUT"
  pc_cell "$flavor" modstrict
  [[ "$CODE" == "1" ]] || log_fail "$tag($flavor): a modified tracked ignored path blocks under strict, got $CODE: $OUT"
  pc_cell "$flavor" del
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): git rm --cached (deletion) must exit 0, got $CODE: $OUT"
  pc_cell "$flavor" pre
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): untouched pre-existing tracked ignored paths only warn, got $CODE: $OUT"
  out_has "2 tracked path(s) already match .gitignore" \
    || log_fail "$tag($flavor): pre-existing paths must give a count warning, got: $OUT"
  pc_cell "$flavor" global
  [[ "$CODE" == "0" ]] || log_fail "$tag($flavor): paths ignored only by core.excludesFile/info exclude must exit 0, got $CODE: $OUT"
}

test_1706_precommit_sh_refuses_added_ignored_path() {  # Spec-AC-03
  log_info "Test: pre-commit-checks.sh refuses a git add -f of an ignored path, naming path, rule and remedy (TEST-1706)..."
  new_scratch
  pc_cell sh add
  [[ "$CODE" == "1" ]] || log_fail "TEST-1706: git add -f of an ignored path must exit 1, got $CODE: $OUT"
  out_has "out/new.txt" || log_fail "TEST-1706: refusal must name the path, got: $OUT"
  out_has ".gitignore:1:out/**" || log_fail "TEST-1706: refusal must name the rule, got: $OUT"
  out_has '!out/new.txt' || log_fail "TEST-1706: refusal must name the ! re-include remedy, got: $OUT"
  pc_cell sh clean
  [[ "$CODE" == "0" ]] || log_fail "TEST-1706: negation — the same commit without the ignored path must exit 0, got $CODE: $OUT"
  log_pass "TEST-1706: CHECK 9 refuses an added ignored path (TEST-1706)"
}

test_1707_precommit_sh_cells() {  # Spec-AC-03
  log_info "Test: pre-commit-checks.sh cells — rename, modified, strict, deletion, pre-existing, global excludes (TEST-1707)..."
  assert_cells sh "TEST-1707"
  log_pass "TEST-1707: rename blocks; modified warns (blocks under strict); deletion and global-only pass; count warning (TEST-1707)"
}

test_1708_precommit_ps1_parity() {  # Spec-AC-03
  log_info "Test: pre-commit-checks.ps1 gives the same exit codes on the TEST-1706/1707 cells (TEST-1708)..."
  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "SKIP-NAMED: TEST-1708 needs pwsh (not installed here; ubuntu CI has it)"
    return 0
  fi
  assert_cells ps1 "TEST-1708"
  log_pass "TEST-1708: pre-commit-checks.ps1 matches the .sh cell table (TEST-1708)"
}

test_1709_real_hook_refuses_commit() {  # Spec-AC-03, SEAM S2
  log_info "Test: SEAM S2 — the real installed pre-commit hook refuses a git commit of a forced ignored file (TEST-1709)..."
  new_scratch
  local repo before after
  repo="$(pc_fixture t1709 plain)"
  cp "$SCRIPTS_DIR/install-pre-commit-hook.sh" "$repo/.aai/scripts/"
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash .aai/scripts/install-pre-commit-hook.sh --hooks index
  [[ "$CODE" == "0" ]] || log_fail "TEST-1709: hook install failed ($CODE): $OUT"
  [[ -f "$repo/.git/hooks/pre-commit" ]] || log_fail "TEST-1709: pre-commit hook not installed"

  printf 'ok\n' > "$repo/other.txt"
  fx_git "$repo" add other.txt
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m normal
  [[ "$CODE" == "0" ]] || log_fail "TEST-1709: positive control — a normal commit must succeed, got $CODE: $OUT"

  before="$(fx_git "$repo" rev-list --count HEAD)"
  printf 'n\n' > "$repo/out/new.txt"
  fx_git "$repo" add -f out/new.txt
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git commit -q -m forced
  [[ "$CODE" != "0" ]] || log_fail "TEST-1709: the hook must refuse the commit of a forced ignored file, got exit 0: $OUT"
  out_has "out/new.txt" || log_fail "TEST-1709: the refusal must name the path, got: $OUT"
  after="$(fx_git "$repo" rev-list --count HEAD)"
  [[ "$before" == "$after" ]] || log_fail "TEST-1709: HEAD must not advance on a refused commit ($before -> $after)"
  log_pass "TEST-1709: the real hook refuses the forced commit and a normal commit succeeds (TEST-1709)"
}

# ccs_run <repo> <args...> — check-committed-scope in a fixture cwd; OUT, CODE.
ccs_run() {
  local repo="$1"; shift
  in_dir "$repo" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null node "$SCRIPTS_DIR/check-committed-scope.mjs" "$@"
}

test_1710_check_committed_scope_label() {  # Spec-AC-04
  log_info "Test: check-committed-scope lists a tracked ignored in-scope path as (tracked-ignored) (TEST-1710)..."
  new_scratch
  local repo
  repo="$(fx_repo t1710)"
  mkdir -p "$repo/scopedir" "$repo/cleandir"
  printf '*.log\n' > "$repo/.gitignore"
  printf 'x\n' > "$repo/scopedir/ok.txt"
  printf 'x\n' > "$repo/scopedir/bad.log"
  printf 'x\n' > "$repo/cleandir/ok.txt"
  fx_git "$repo" add .gitignore scopedir/ok.txt cleandir/ok.txt
  fx_git "$repo" add -f scopedir/bad.log
  fx_git "$repo" commit -q -m init

  ccs_run "$repo" scopedir
  [[ "$CODE" == "1" ]] || log_fail "TEST-1710: plain mode must exit 1, got $CODE: $OUT"
  out_has "scopedir/bad.log (tracked-ignored)" || log_fail "TEST-1710: plain output must carry the label, got: $OUT"
  ccs_run "$repo" --strict scopedir
  [[ "$CODE" == "1" ]] || log_fail "TEST-1710: --strict must exit 1, got $CODE: $OUT"
  out_has "scopedir/bad.log (tracked-ignored)" || log_fail "TEST-1710: --strict output must carry the label, got: $OUT"
  ccs_run "$repo" --rev HEAD scopedir
  [[ "$CODE" == "1" ]] || log_fail "TEST-1710: --rev HEAD must exit 1, got $CODE: $OUT"
  out_has "scopedir/bad.log (tracked-ignored)" || log_fail "TEST-1710: --rev output must carry the label, got: $OUT"
  ccs_run "$repo" scopedir/bad.log
  [[ "$CODE" == "1" ]] || log_fail "TEST-1710: a file in scope must exit 1, got $CODE: $OUT"

  ccs_run "$repo" cleandir
  [[ "$CODE" == "0" ]] || log_fail "TEST-1710: negation — a scope without a tracked ignored path must exit 0, got $CODE: $OUT"
  ccs_run "$repo" --strict cleandir
  [[ "$CODE" == "0" ]] || log_fail "TEST-1710: negation under --strict must exit 0, got $CODE: $OUT"

  # --rev evaluates that revision's tree: untrack in the index only.
  fx_git "$repo" rm -q --cached scopedir/bad.log
  ccs_run "$repo" scopedir
  [[ "$CODE" == "0" ]] || log_fail "TEST-1710: index no longer tracks it, plain mode must exit 0, got $CODE: $OUT"
  ccs_run "$repo" --rev HEAD scopedir
  [[ "$CODE" == "1" ]] || log_fail "TEST-1710: --rev HEAD must still see it, got $CODE: $OUT"
  log_pass "TEST-1710: (tracked-ignored) label in plain, --strict and --rev modes (TEST-1710)"
}

main() {
  echo "Testing $TEST_NAME (post-validation-pushes-reuse-test-results, Batches A and B)"
  check_deps
  test_1700_all_lists_forced_ignored_and_clean_control
  test_1701_nested_gitignore_and_negation
  test_1702_repo_rules_only_and_rev_mode
  test_1703_workflow_job_and_gate_wiring
  test_1704_workflow_run_text_executes_in_fixture
  test_1705_live_tree_tracks_no_ignored_path
  test_1706_precommit_sh_refuses_added_ignored_path
  test_1707_precommit_sh_cells
  test_1708_precommit_ps1_parity
  test_1709_real_hook_refuses_commit
  test_1710_check_committed_scope_label
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
