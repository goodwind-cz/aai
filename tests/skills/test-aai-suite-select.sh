#!/usr/bin/env bash
#
# Test: CI test-impact selection (CHANGE ci-test-impact-selection /
# SPEC spec-ci-test-impact-selection, TEST-001..013 + review remediations
# TEST-017..019).
#
# Verifies .aai/scripts/select-suites.mjs — the deterministic, zero-dep,
# always-exit-0 selector that maps a changed-path diff onto tests/skills/
# suites via tests/skills/suite-map.yaml, with a three-way fail-open
# (unmapped path / .aai/scripts/lib/** shared-lib / docs-audit.yaml
# protected_paths_l3) escalating straight to FULL_RUN instead of narrowing
# coverage silently.
#
# All fixtures use scratch temp-dir trees carrying their OWN tiny
# suite-map.yaml (and, where relevant, their own docs-audit.yaml) — the real
# repo's tests/skills/suite-map.yaml is exercised only by TEST-012's
# real-git-fixture SEAM and TEST-013's workflow-wiring greps.
#
# The script under test is overridable via SELECT_SUITES_SCRIPT.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-suite-select"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELECTOR="${SELECT_SUITES_SCRIPT:-$PROJECT_ROOT/.aai/scripts/select-suites.mjs}"
WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/skill-suite.yml"

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
  [[ -f "$SELECTOR" ]] || log_fail "Selector script not found: $SELECTOR"
  log_pass "Dependencies checked"
}

# ---- fixture helpers -------------------------------------------------

# small_map <dir> — a 4-suite map: two core, two mapped (one glob-only, one
# also matching a second suite so overlap can be proven), plus a shared-lib
# trigger prefix. No docs-audit.yaml — protected-l3 tests supply their own.
small_map() {
  local dir="$1"
  mkdir -p "$dir/tests/skills"
  cat > "$dir/tests/skills/suite-map.yaml" <<'YAML'
core:
  - aai-core-a
  - aai-core-b

full_run_triggers:
  shared_lib_globs:
    - .aai/scripts/lib/**

suites:
  aai-core-a:
    globs:
      - docs/core-a.md
  aai-core-b:
    globs:
      - docs/core-b.md
  aai-alpha:
    globs:
      - src/alpha/**
  aai-beta:
    globs:
      - src/alpha/shared.js
      - src/beta/**
YAML
}

# run <dir> <files...> — invoke the selector via --files-from on a newline
# list; captures stdout to $OUT and exit code to $CODE.
run_sel() {
  local dir="$1"; shift
  local list="$dir/files.txt"
  printf '%s\n' "$@" > "$list"
  OUT="$(node "$SELECTOR" --repo-root "$dir" --files-from "$list" 2>&1)"
  CODE=$?
}

test_001_mapped_diff_selects_exact_plus_core() {  # Spec-AC-01
  log_info "Test: mapped diff selects exactly the matched suites + core always present (TEST-001)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/alpha/foo.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^CORE aai-core-a reason=core$' || log_fail "missing CORE aai-core-a: $OUT"
  echo "$OUT" | grep -qE '^CORE aai-core-b reason=core$' || log_fail "missing CORE aai-core-b: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-alpha reason=src/alpha/foo\.js$' || log_fail "missing SELECTED aai-alpha: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-beta' && log_fail "aai-beta must NOT be selected (glob does not match foo.js): $OUT"
  echo "$OUT" | grep -qE '^DROPPED 1$' || log_fail "expected DROPPED 1 (only aai-beta unselected): $OUT"
  log_pass "Exact mapped selection + core always present (TEST-001)"
}

test_002_multi_writer_overlap() {  # Spec-AC-01 (fixture diversity: multi-source/multi-writer)
  log_info "Test: one changed path matching multiple suites selects ALL of them (TEST-002)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/alpha/shared.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-alpha reason=src/alpha/shared\.js$' || log_fail "missing SELECTED aai-alpha: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-beta reason=src/alpha/shared\.js$' || log_fail "missing SELECTED aai-beta: $OUT"
  echo "$OUT" | grep -qE '^DROPPED 0$' || log_fail "both non-core suites selected -> DROPPED 0: $OUT"
  log_pass "Overlapping selection: one path selects every matching suite (TEST-002)"
}

test_003_zero_remainder() {  # Spec-AC-01 (fixture diversity: fully-covered / zero-remainder)
  log_info "Test: a diff touching every suite's surface drops nothing (TEST-003)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "docs/core-a.md" "docs/core-b.md" "src/alpha/foo.js" "src/beta/bar.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-alpha' || log_fail "missing SELECTED aai-alpha: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-beta' || log_fail "missing SELECTED aai-beta: $OUT"
  echo "$OUT" | grep -qE '^DROPPED 0$' || log_fail "every non-core suite matched -> DROPPED 0: $OUT"
  log_pass "Zero-remainder: nothing dropped when every suite's surface is touched (TEST-003)"
}

test_004_empty_diff() {  # Spec-AC-01 (fixture diversity: degenerate/empty)
  log_info "Test: empty diff selects only core, exit 0 (TEST-004)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  : > "$TEST_DIR/files.txt"
  OUT="$(node "$SELECTOR" --repo-root "$TEST_DIR" --files-from "$TEST_DIR/files.txt" 2>&1)"
  CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^CORE aai-core-a reason=core$' || log_fail "missing CORE aai-core-a on empty diff: $OUT"
  echo "$OUT" | grep -qE '^SELECTED' && log_fail "empty diff must select nothing beyond core: $OUT"
  echo "$OUT" | grep -qE '^DROPPED 2$' || log_fail "empty diff drops both non-core suites: $OUT"
  log_pass "Degenerate empty diff: core only, DROPPED equals all non-core suites (TEST-004)"
}

test_005_unmapped_fail_open() {  # Spec-AC-02
  log_info "Test: unmapped path forces FULL_RUN naming the triggering path (TEST-005)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "totally/unmapped/file.txt"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qF 'FULL_RUN reason=unmapped path=totally/unmapped/file.txt' \
    || log_fail "expected FULL_RUN reason=unmapped naming the path: $OUT"
  log_pass "Unmapped path fail-open (TEST-005)"
}

test_006_shared_lib_fail_open() {  # Spec-AC-02
  log_info "Test: .aai/scripts/lib/** change forces FULL_RUN (TEST-006)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" ".aai/scripts/lib/some-shared.mjs"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qF 'FULL_RUN reason=shared-lib path=.aai/scripts/lib/some-shared.mjs' \
    || log_fail "expected FULL_RUN reason=shared-lib naming the path: $OUT"
  log_pass "Shared-lib fail-open (TEST-006)"
}

test_007_protected_l3_fail_open() {  # Spec-AC-02 — real docs-audit.yaml, live protected_paths_l3
  log_info "Test: docs/ai/docs-audit.yaml protected_paths_l3 path forces FULL_RUN (TEST-007)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  mkdir -p "$TEST_DIR/docs/ai"
  cat > "$TEST_DIR/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2026-06-12
protected_paths_l3:
  - .aai/scripts/state.mjs
  - docs/CONSTITUTION.md
YAML
  run_sel "$TEST_DIR" "docs/CONSTITUTION.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qF 'FULL_RUN reason=protected-l3 path=docs/CONSTITUTION.md' \
    || log_fail "expected FULL_RUN reason=protected-l3 naming the path: $OUT"
  log_pass "Protected-L3 fail-open reads the live docs-audit.yaml list (TEST-007)"
}

test_008_negative_control_near_miss() {  # Spec-AC-02 (fixture diversity: negative control)
  log_info "Test: a near-miss path must NOT trip protected-l3 or shared-lib (TEST-008)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  mkdir -p "$TEST_DIR/docs/ai"
  cat > "$TEST_DIR/docs/ai/docs-audit.yaml" <<'YAML'
protected_paths_l3:
  - .aai/scripts/state.mjs
YAML
  # Not an exact match (extra suffix) and not under .aai/scripts/lib/.
  run_sel "$TEST_DIR" ".aai/scripts/state.mjs.bak"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE 'reason=protected-l3' && log_fail "near-miss must not trip protected-l3 (exact match only): $OUT"
  echo "$OUT" | grep -qE 'reason=shared-lib' && log_fail "near-miss must not trip shared-lib (not under .aai/scripts/lib/): $OUT"
  echo "$OUT" | grep -qF 'FULL_RUN reason=unmapped path=.aai/scripts/state.mjs.bak' \
    || log_fail "near-miss falls through to plain unmapped, not a fail-open trigger misfire: $OUT"
  log_pass "Negative control: near-miss path takes the unmapped path, not L3/shared-lib (TEST-008)"
}

test_009_whole_diff_scanned_before_output() {  # Spec-AC-02 (fixture diversity: mid-operation failure)
  log_info "Test: an unmapped path anywhere in the diff suppresses ALL selection output (TEST-009)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  # First path is cleanly mapped; second is unmapped. Nothing from the first
  # path's match may leak into stdout before the FULL_RUN escalation.
  run_sel "$TEST_DIR" "src/alpha/foo.js" "nowhere/mapped.txt"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^SELECTED' && log_fail "no SELECTED line may appear once any path is unmapped: $OUT"
  echo "$OUT" | grep -qE '^CORE' && log_fail "no CORE line may appear once any path is unmapped: $OUT"
  local lines
  lines="$(echo "$OUT" | grep -c . || true)"
  [[ "$lines" -eq 1 ]] || log_fail "FULL_RUN must be the ONLY output line, got $lines: $OUT"
  echo "$OUT" | grep -qF 'FULL_RUN reason=unmapped path=nowhere/mapped.txt' \
    || log_fail "expected FULL_RUN naming the unmapped path: $OUT"
  log_pass "Mid-diff unmapped path suppresses partial selection output (TEST-009)"
}

test_010_auditable_output_shape() {  # Spec-AC-05
  log_info "Test: every SELECTED line carries reason=, exactly one DROPPED line, count is exact (TEST-010)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/beta/x.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  local selected_lines dropped_lines
  selected_lines="$(echo "$OUT" | grep -c '^SELECTED ' || true)"
  [[ "$selected_lines" -ge 1 ]] || log_fail "expected at least one SELECTED line: $OUT"
  echo "$OUT" | grep '^SELECTED ' | grep -qv 'reason=' && log_fail "every SELECTED line must carry reason=: $OUT"
  dropped_lines="$(echo "$OUT" | grep -cE '^DROPPED [0-9]+$' || true)"
  [[ "$dropped_lines" -eq 1 ]] || log_fail "expected exactly ONE DROPPED count line, got $dropped_lines: $OUT"
  # Arithmetic: total non-core suites (2: alpha, beta) - selected(1: beta) = 1.
  echo "$OUT" | grep -qE '^DROPPED 1$' || log_fail "DROPPED count must reflect exact arithmetic: $OUT"
  log_pass "Selection output is auditable: reasons present, single accurate DROPPED line (TEST-010)"
}

test_011_cli_robustness_always_exit_zero() {  # Spec-AC-05 (never fails the build)
  log_info "Test: missing args / unreadable map / bad base-ref all degrade to FULL_RUN, exit 0 (TEST-011)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"

  # (a) no --base-ref and no --files-from.
  OUT="$(node "$SELECTOR" --repo-root "$TEST_DIR" 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "no-args must still exit 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^FULL_RUN reason=internal-error' || log_fail "no-args must fall open: $OUT"

  # (b) suite-map.yaml absent entirely.
  local empty_dir="$TEST_DIR/no-map"
  mkdir -p "$empty_dir/files-src"
  : > "$empty_dir/files-src/list.txt"
  OUT="$(node "$SELECTOR" --repo-root "$empty_dir" --files-from "$empty_dir/files-src/list.txt" 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "missing map must still exit 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^FULL_RUN reason=internal-error' || log_fail "missing map must fall open: $OUT"

  # (c) bad base-ref against a real (but ref-less) git repo.
  local repo="$TEST_DIR/badref-repo"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && small_map "$repo")
  OUT="$(node "$SELECTOR" --repo-root "$repo" --base-ref does-not-exist-anywhere 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "bad base-ref must still exit 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^FULL_RUN reason=internal-error' || log_fail "bad base-ref must fall open: $OUT"

  log_pass "CLI never fails the build: every error path degrades to FULL_RUN, exit 0 (TEST-011)"
}

test_012_real_git_diff_seam() {  # Spec-AC-01, SEAM: real git diff --name-only -> selector, not mocked
  log_info "Test: real git fixture repo, --base-ref drives an actual git diff --name-only (TEST-012)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo"
  mkdir -p "$repo"
  (
    cd "$repo"
    # -b main: never inherit the runner's init.defaultBranch (CI defaults to
    # master, which broke the base-ref main lookup — PR #171 first CI run)
    git init -q -b main
    small_map "$repo"
    mkdir -p src/alpha
    echo "seed" > README.md
    git add -A
    git -c user.email=t@t.com -c user.name=t commit -q -m init
    git checkout -q -b feature
    echo "change" > src/alpha/new.js
    git add -A
    git -c user.email=t@t.com -c user.name=t commit -q -m change
  )
  OUT="$(node "$SELECTOR" --repo-root "$repo" --base-ref main 2>&1)"
  CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^SELECTED aai-alpha reason=src/alpha/new\.js$' \
    || log_fail "real git diff must drive the same selection as --files-from: $OUT"
  log_pass "Real git diff --name-only end-to-end selection (TEST-012, SEAM)"
}

test_013_workflow_wiring() {  # Spec-AC-04
  log_info "Test: skill-suite.yml wires the selector on pull_request; full framework on push-to-main + schedule + ci-full label (TEST-013)..."
  [[ -f "$WORKFLOW_FILE" ]] || log_fail "missing $WORKFLOW_FILE"
  grep -qF 'select-suites.mjs' "$WORKFLOW_FILE" \
    || log_fail "workflow must invoke .aai/scripts/select-suites.mjs"
  grep -qF -- '--skill' "$WORKFLOW_FILE" \
    || log_fail "workflow must run selected suites via test-framework.sh --skill"
  grep -qE '^\s*branches:\s*\[main\]' "$WORKFLOW_FILE" \
    || log_fail "workflow must keep push-to-main as a full-run trigger"
  grep -qF 'schedule:' "$WORKFLOW_FILE" \
    || log_fail "workflow must add a schedule (nightly) trigger"
  grep -qF 'cron:' "$WORKFLOW_FILE" \
    || log_fail "workflow schedule trigger must carry a cron expression"
  grep -qF 'ci-full' "$WORKFLOW_FILE" \
    || log_fail "workflow must name the ci-full label override"
  grep -qF 'self-hosting-smoke' "$WORKFLOW_FILE" \
    || log_fail "self-hosting-smoke job must be preserved (semantics kept intact)"
  grep -qF 'test-self-hosting-smoke.sh' "$WORKFLOW_FILE" \
    || log_fail "self-hosting-smoke job must still run tests/self-hosting/test-self-hosting-smoke.sh"
  log_pass "skill-suite.yml wires selector on PR + full-run triggers preserved/added (TEST-013)"
}

test_017_hostile_core_name_fails_open() {  # review remediation: core-name charset contract
  log_info "Test: a core entry violating [A-Za-z0-9_-]+ degrades to FULL_RUN internal-error, exit 0 (TEST-017)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  printf 'core:\n  - aai-core-a\n  - bad`name$(x)\n\nsuites:\n  aai-alpha:\n    globs:\n      - src/alpha/**\n' \
    > "$TEST_DIR/tests/skills/suite-map.yaml"
  run_sel "$TEST_DIR" "src/alpha/foo.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0 even on hostile core name, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^FULL_RUN reason=internal-error' || log_fail "hostile core name must degrade to FULL_RUN internal-error: $OUT"
  echo "$OUT" | grep -qE '^(SELECTED|CORE) ' && log_fail "no SELECTED/CORE lines may leak past a malformed map: $OUT"
  log_pass "Hostile core name never reaches the workflow shell: FULL_RUN internal-error, exit 0 (TEST-017)"
}

test_019_ghost_core_entry_fails_open() {  # 5d sweep (Codex P2): core name without a suites row
  log_info "Test: a core entry with no suites row degrades to FULL_RUN internal-error, never CORE <ghost>/negative DROPPED (TEST-019)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  printf 'core:\n  - aai-ghost\n\nsuites:\n  aai-alpha:\n    globs:\n      - src/alpha/**\n' \
    > "$TEST_DIR/tests/skills/suite-map.yaml"
  run_sel "$TEST_DIR" "src/alpha/foo.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0 on ghost core entry, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^FULL_RUN reason=internal-error path=core entry has no suites row: aai-ghost$' \
    || log_fail "ghost core entry must degrade to FULL_RUN internal-error naming the entry: $OUT"
  echo "$OUT" | grep -qE '^(SELECTED|CORE|DROPPED) ' && log_fail "no selection lines may leak past a ghost core entry: $OUT"
  log_pass "Ghost core entry fails open, never emitted to the workflow (TEST-019)"
}

test_018_gate_job_contract() {  # review remediation: required-check continuity
  log_info "Test: aggregating gate job carries the branch-protection check name and needs all three jobs (TEST-018)..."
  grep -qF 'name: skill test suite (tests/skills/, via test-framework.sh)' "$WORKFLOW_FILE" \
    || log_fail "gate job must keep the exact required-check name 'skill test suite (tests/skills/, via test-framework.sh)'"
  grep -qE 'needs:\s*\[select, skills-selected, skills-full\]' "$WORKFLOW_FILE" \
    || log_fail "gate job must need select + skills-selected + skills-full"
  grep -qE 'if:\s*always\(\)' "$WORKFLOW_FILE" \
    || log_fail "gate job must run on always() so it reports even when a leaf is skipped"
  log_pass "Gate job preserves the required check across the selected/full split (TEST-018)"
}

test_020_harness_surfaces_select_hygiene_pack() {  # TEST-010 / Spec-AC-09 (harness-surfaces-drift-unguarded)
  log_info "Test: each of the five harness surface paths selects aai-hygiene-pack with no FULL_RUN unmapped line, against the real repo suite-map (TEST-010)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local list="$TEST_DIR/hsk-020-files.txt"
  local p out rc
  for p in \
    ".agents/skills/aai-ship/SKILL.md" \
    ".cursor/rules/aai.mdc" \
    "AGENTS.md" \
    ".aai/system/HARNESS_SKILLS.yaml" \
    ".aai/scripts/sync-harness-skills.mjs"
  do
    printf '%s\n' "$p" > "$list"
    out="$(node "$SELECTOR" --repo-root "$root" --files-from "$list" 2>&1)"; rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "test_020: exit code must be 0 for $p, got $rc: $out"
    # A `case` glob match takes no second process and no pipe, so it cannot
    # SIGPIPE on a large payload (pipe-grep-q-ratchet: tests/skills/lib/pipe-grep-q-ratchet.sh).
    case "$out" in
      *"FULL_RUN reason=unmapped"*)
        log_fail "test_020: $p must not fail open as unmapped: $out" ;;
    esac
    case "$out" in
      *"aai-hygiene-pack"*) ;;
      *) log_fail "test_020: $p must select aai-hygiene-pack: $out" ;;
    esac
  done
  log_pass "test_020: all five harness surface paths select aai-hygiene-pack, none unmapped (TEST-010)"
}

main() {
  echo "Testing $TEST_NAME (ci-test-impact-selection / spec-ci-test-impact-selection)"
  check_deps
  test_001_mapped_diff_selects_exact_plus_core
  test_002_multi_writer_overlap
  test_003_zero_remainder
  test_004_empty_diff
  test_005_unmapped_fail_open
  test_006_shared_lib_fail_open
  test_007_protected_l3_fail_open
  test_008_negative_control_near_miss
  test_009_whole_diff_scanned_before_output
  test_010_auditable_output_shape
  test_011_cli_robustness_always_exit_zero
  test_012_real_git_diff_seam
  test_013_workflow_wiring
  test_017_hostile_core_name_fails_open
  test_018_gate_job_contract
  test_019_ghost_core_entry_fails_open
  test_020_harness_surfaces_select_hygiene_pack
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
