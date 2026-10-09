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
# real-git-fixture SEAM, TEST-013's workflow-wiring greps, TEST-020/021/022's
# real-map ceremony/harness-surface pins.
#
# The script under test is overridable via SELECT_SUITES_SCRIPT.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-suite-select"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

# Local restructuring for the NEGATED, per-line-anchored/regex control shape
# (Spec-AC-11): the helper library has no "assert no line matches this ERE"
# primitive, so these sites are restructured rather than substituted.
assert_payload_line_not_matches() {
  local _p="$1" _e="$2" _m="$3" _l
  while IFS= read -r _l; do
    if [[ "$_l" =~ $_e ]]; then log_fail "$_m"; return; fi
  done <<EOF
$_p
EOF
  return 0
}
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELECTOR="${SELECT_SUITES_SCRIPT:-$PROJECT_ROOT/.aai/scripts/select-suites.mjs}"
WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/skill-suite.yml"
# Sharding (ci-test-selection-narrowing-and-sharding) overrides, independent
# of SELECT_SUITES_SCRIPT/WORKFLOW_FILE above: a RED run points these at a
# pre-change snapshot (old workflow / a nonexistent helper) without
# disturbing the existing TEST-013/017/018/020-022/430 invocations, which
# keep using the plain variables.
SHARD_CHECK_SCRIPT="${SHARD_CHECK_SCRIPT:-$PROJECT_ROOT/tests/skills/lib/shard-plan-check.sh}"
SHARD_WORKFLOW_FILE="${SHARD_WORKFLOW_FILE:-$WORKFLOW_FILE}"

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

# ---- sharding fixture helpers (ci-test-selection-narrowing-and-sharding,
# TEST-1420..1439) ----------------------------------------------------

# fixture_suites <dir> <suite...> — creates a stub tests/skills/test-<name>.sh
# for each bare suite name (pass the full name, e.g. "aai-alpha").
fixture_suites() {
  local dir="$1"; shift
  mkdir -p "$dir/tests/skills"
  local name
  for name in "$@"; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/tests/skills/test-${name}.sh"
  done
}

# fixture_tie6_scrambled <dir> — the TEST-1422/1424 weight-tie fixture
# (aai-one/two/three @5, aai-four/five @3, aai-six @1), built so the
# ENUMERATION order discoverSuiteNames() sees is NOT already alphabetical:
# `aai-two` sits under a subdirectory ("aaa_sub", name-sorted before the
# top-level `test-aai-*.sh` files) that readdirSync visits first. On a flat
# layout, readdirSync already returns basenames in alphabetical order on
# this filesystem, so a stable sort's tie-break is a structural no-op (the
# pre-sort order already satisfies ascending-name) and TEST-1422's own
# mandated mutation (S4, reversed name comparison) stayed GREEN undetected
# until this was found empirically running mutation-run.mjs. Nesting one
# suite decouples enumeration order from name order without changing the
# correct (sorted) output, which the mutation-run.mjs record for TEST-1422
# confirms actually differs under the mutated comparator.
fixture_tie6_scrambled() {
  local dir="$1"
  mkdir -p "$dir/tests/skills/aaa_sub"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/tests/skills/aaa_sub/test-aai-two.sh"
  local name
  for name in aai-one aai-three aai-four aai-five aai-six; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/tests/skills/test-${name}.sh"
  done
}

# run_shard <repo-root> <selector-args...> — invoke the selector's shard
# mode; captures stdout+stderr to $OUT, exit code to $CODE. Uses the
# `cmd || rc=$?` capture shape (rc preset to 0) even though select-suites.mjs
# always exits 0 by contract, for uniformity with run_check/run_extract below
# (shard-plan-check.sh genuinely returns non-zero in several of these tests).
run_shard() {
  local dir="$1"; shift
  CODE=0
  OUT="$(node "$SELECTOR" --repo-root "$dir" "$@" 2>&1)" || CODE=$?
}

# run_check <plan-file> <skills-dir> — invoke shard-plan-check.sh --check;
# $OUT/$CODE as above.
run_check() {
  local plan="$1" dir="$2"
  CODE=0
  OUT="$(bash "$SHARD_CHECK_SCRIPT" --check "$plan" "$dir" 2>&1)" || CODE=$?
}

# run_extract <shard-id|all> <plan-file> — invoke shard-plan-check.sh
# --extract; $OUT/$CODE as above.
run_extract() {
  local idx="$1" plan="$2"
  CODE=0
  OUT="$(bash "$SHARD_CHECK_SCRIPT" --extract "$idx" "$plan" 2>&1)" || CODE=$?
}

# real_suite_names <root> — the real find-list of suite names, sorted
# unique, same rule discover_tests() uses.
real_suite_names() {
  local root="$1"
  find "$root/tests/skills" -name 'test-aai-*.sh' -type f -exec basename {} \; \
    | sed -e 's/^test-//' -e 's/\.sh$//' | sort -u
}

# planned_suite_names <outfile> — sorted unique suite names from SHARD lines
# in a selector plan file already written to disk (never piped from a live
# producer, so there is nothing to early-close).
planned_suite_names() {
  awk '/^SHARD /{print $3}' "$1" | sort -u
}

# assert_shard_weights_non_increasing <outfile> <label> — SHARD lines for one
# shard id are emitted contiguously (one inner loop per shard index); fails
# if a later line for the SAME shard id carries a HIGHER weight than the one
# before it.
assert_shard_weights_non_increasing() {
  local outfile="$1" label="$2"
  awk '
    /^SHARD / {
      id = $2; w = $0; sub(/.*weight=/, "", w); w += 0
      if (id == prev_id && w > prev_w) {
        print "VIOLATION shard=" id " weight=" w " after=" prev_w
        exit 1
      }
      prev_id = id; prev_w = w
    }
  ' "$outfile" || log_fail "$label: a shard's weights increased somewhere (non-increasing invariant broken)"
}

test_001_mapped_diff_selects_exact_plus_core() {  # Spec-AC-01
  log_info "Test: mapped diff selects exactly the matched suites + core always present (TEST-001)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/alpha/foo.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "CORE aai-core-a reason=core" "missing CORE aai-core-a: $OUT"
  assert_payload_has_line "$OUT" "CORE aai-core-b reason=core" "missing CORE aai-core-b: $OUT"
  assert_payload_has_line "$OUT" "SELECTED aai-alpha reason=src/alpha/foo.js" "missing SELECTED aai-alpha: $OUT"
  assert_payload_line_not_matches "$OUT" '^SELECTED aai-beta' "aai-beta must NOT be selected (glob does not match foo.js): $OUT"
  assert_payload_has_line "$OUT" "DROPPED 1" "expected DROPPED 1 (only aai-beta unselected): $OUT"
  log_pass "Exact mapped selection + core always present (TEST-001)"
}

test_002_multi_writer_overlap() {  # Spec-AC-01 (fixture diversity: multi-source/multi-writer)
  log_info "Test: one changed path matching multiple suites selects ALL of them (TEST-002)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/alpha/shared.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "SELECTED aai-alpha reason=src/alpha/shared.js" "missing SELECTED aai-alpha: $OUT"
  assert_payload_has_line "$OUT" "SELECTED aai-beta reason=src/alpha/shared.js" "missing SELECTED aai-beta: $OUT"
  assert_payload_has_line "$OUT" "DROPPED 0" "both non-core suites selected -> DROPPED 0: $OUT"
  log_pass "Overlapping selection: one path selects every matching suite (TEST-002)"
}

test_003_zero_remainder() {  # Spec-AC-01 (fixture diversity: fully-covered / zero-remainder)
  log_info "Test: a diff touching every suite's surface drops nothing (TEST-003)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "docs/core-a.md" "docs/core-b.md" "src/alpha/foo.js" "src/beta/bar.js"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  assert_payload_line_matches "$OUT" '^SELECTED aai-alpha' "missing SELECTED aai-alpha: $OUT"
  assert_payload_line_matches "$OUT" '^SELECTED aai-beta' "missing SELECTED aai-beta: $OUT"
  assert_payload_has_line "$OUT" "DROPPED 0" "every non-core suite matched -> DROPPED 0: $OUT"
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
  assert_payload_has_line "$OUT" "CORE aai-core-a reason=core" "missing CORE aai-core-a on empty diff: $OUT"
  assert_payload_line_not_matches "$OUT" '^SELECTED' "empty diff must select nothing beyond core: $OUT"
  assert_payload_has_line "$OUT" "DROPPED 2" "empty diff drops both non-core suites: $OUT"
  log_pass "Degenerate empty diff: core only, DROPPED equals all non-core suites (TEST-004)"
}

test_005_unmapped_fail_open() {  # Spec-AC-02
  log_info "Test: unmapped path forces FULL_RUN naming the triggering path (TEST-005)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "totally/unmapped/file.txt"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  assert_payload_contains "$OUT" "FULL_RUN reason=unmapped path=totally/unmapped/file.txt" "expected FULL_RUN reason=unmapped naming the path: $OUT"
  log_pass "Unmapped path fail-open (TEST-005)"
}

test_006_shared_lib_fail_open() {  # Spec-AC-02
  log_info "Test: .aai/scripts/lib/** change forces FULL_RUN (TEST-006)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" ".aai/scripts/lib/some-shared.mjs"
  [[ "$CODE" -eq 0 ]] || log_fail "exit code must be 0, got $CODE: $OUT"
  assert_payload_contains "$OUT" "FULL_RUN reason=shared-lib path=.aai/scripts/lib/some-shared.mjs" "expected FULL_RUN reason=shared-lib naming the path: $OUT"
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
  assert_payload_contains "$OUT" "FULL_RUN reason=protected-l3 path=docs/CONSTITUTION.md" "expected FULL_RUN reason=protected-l3 naming the path: $OUT"
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
  assert_payload_not_contains "$OUT" "reason=protected-l3" "near-miss must not trip protected-l3 (exact match only): $OUT"
  assert_payload_not_contains "$OUT" "reason=shared-lib" "near-miss must not trip shared-lib (not under .aai/scripts/lib/): $OUT"
  assert_payload_contains "$OUT" "FULL_RUN reason=unmapped path=.aai/scripts/state.mjs.bak" "near-miss falls through to plain unmapped, not a fail-open trigger misfire: $OUT"
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
  assert_payload_line_not_matches "$OUT" '^SELECTED' "no SELECTED line may appear once any path is unmapped: $OUT"
  assert_payload_line_not_matches "$OUT" '^CORE' "no CORE line may appear once any path is unmapped: $OUT"
  local lines
  lines="$(echo "$OUT" | grep -c . || true)"
  [[ "$lines" -eq 1 ]] || log_fail "FULL_RUN must be the ONLY output line, got $lines: $OUT"
  assert_payload_contains "$OUT" "FULL_RUN reason=unmapped path=nowhere/mapped.txt" "expected FULL_RUN naming the unmapped path: $OUT"
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
  echo "$OUT" | grep '^SELECTED ' | qgrep -qv 'reason=' && log_fail "every SELECTED line must carry reason=: $OUT"
  dropped_lines="$(echo "$OUT" | grep -cE '^DROPPED [0-9]+$' || true)"
  [[ "$dropped_lines" -eq 1 ]] || log_fail "expected exactly ONE DROPPED count line, got $dropped_lines: $OUT"
  # Arithmetic: total non-core suites (2: alpha, beta) - selected(1: beta) = 1.
  assert_payload_has_line "$OUT" "DROPPED 1" "DROPPED count must reflect exact arithmetic: $OUT"
  log_pass "Selection output is auditable: reasons present, single accurate DROPPED line (TEST-010)"
}

test_011_cli_robustness_always_exit_zero() {  # Spec-AC-05 (never fails the build)
  log_info "Test: missing args / unreadable map / bad base-ref all degrade to FULL_RUN, exit 0 (TEST-011)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"

  # (a) no --base-ref and no --files-from.
  OUT="$(node "$SELECTOR" --repo-root "$TEST_DIR" 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "no-args must still exit 0, got $CODE: $OUT"
  assert_payload_line_matches "$OUT" '^FULL_RUN reason=internal-error' "no-args must fall open: $OUT"

  # (b) suite-map.yaml absent entirely.
  local empty_dir="$TEST_DIR/no-map"
  mkdir -p "$empty_dir/files-src"
  : > "$empty_dir/files-src/list.txt"
  OUT="$(node "$SELECTOR" --repo-root "$empty_dir" --files-from "$empty_dir/files-src/list.txt" 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "missing map must still exit 0, got $CODE: $OUT"
  assert_payload_line_matches "$OUT" '^FULL_RUN reason=internal-error' "missing map must fall open: $OUT"

  # (c) bad base-ref against a real (but ref-less) git repo.
  local repo="$TEST_DIR/badref-repo"
  mkdir -p "$repo"
  (cd "$repo" && git init -q && small_map "$repo")
  OUT="$(node "$SELECTOR" --repo-root "$repo" --base-ref does-not-exist-anywhere 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "bad base-ref must still exit 0, got $CODE: $OUT"
  assert_payload_line_matches "$OUT" '^FULL_RUN reason=internal-error' "bad base-ref must fall open: $OUT"

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
  assert_payload_has_line "$OUT" "SELECTED aai-alpha reason=src/alpha/new.js" "real git diff must drive the same selection as --files-from: $OUT"
  log_pass "Real git diff --name-only end-to-end selection (TEST-012, SEAM)"
}

test_013_workflow_wiring() {  # Spec-AC-04
  log_info "Test: skill-suite.yml wires the selector on pull_request; full framework on push-to-main + schedule + ci-full label (TEST-013)..."
  [[ -f "$WORKFLOW_FILE" ]] || log_fail "missing $WORKFLOW_FILE"
  grep -qF 'select-suites.mjs' "$WORKFLOW_FILE" \
    || log_fail "workflow must invoke .aai/scripts/select-suites.mjs"
  grep -qF -- '--skill' "$WORKFLOW_FILE" \
    || log_fail "workflow must run selected suites via test-framework.sh --skill"
  grep -qF "AAI_TEST_PARALLEL: '4'" "$WORKFLOW_FILE" \
    || log_fail "workflow must pin AAI_TEST_PARALLEL=4 on the skills jobs (a 4-core runner otherwise lands at cpus-2 = width 2)"
  grep -qF 'args+=(--skill' "$WORKFLOW_FILE" \
    || log_fail "skills-selected must accumulate --skill flags into one framework invocation so PARALLEL_WIDTH applies"
  grep -qF 'bash tests/skills/test-framework.sh --skill "$s"' "$WORKFLOW_FILE" \
    && log_fail "skills-selected must not invoke the framework once per suite (serial isolation clones, ignores PARALLEL_WIDTH)"
  grep -qF 'for s in ${{ needs.select.outputs.suites }}' "$WORKFLOW_FILE" \
    && log_fail "skills-selected must not interpolate suites into 'for s in' (empty output becomes a bash syntax error)"
  grep -qF 'suite_list="' "$WORKFLOW_FILE" \
    || log_fail "skills-selected must bind the suite list to a variable before word-splitting"
  FRAMEWORK_FILE="$PROJECT_ROOT/tests/skills/test-framework.sh"
  grep -qF 'SPECIFIC_SKILLS+=("$2")' "$FRAMEWORK_FILE" \
    || log_fail "test-framework.sh --skill must be repeatable (append to SPECIFIC_SKILLS), not a single overwrite"
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
  assert_payload_line_matches "$OUT" '^FULL_RUN reason=internal-error' "hostile core name must degrade to FULL_RUN internal-error: $OUT"
  assert_payload_line_not_matches "$OUT" '^(SELECTED|CORE) ' "no SELECTED/CORE lines may leak past a malformed map: $OUT"
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
  assert_payload_has_line "$OUT" "FULL_RUN reason=internal-error path=core entry has no suites row: aai-ghost" "ghost core entry must degrade to FULL_RUN internal-error naming the entry: $OUT"
  assert_payload_line_not_matches "$OUT" '^(SELECTED|CORE|DROPPED) ' "no selection lines may leak past a ghost core entry: $OUT"
  log_pass "Ghost core entry fails open, never emitted to the workflow (TEST-019)"
}

test_018_gate_job_contract() {  # review remediation: required-check continuity
  log_info "Test: aggregating gate keeps its required-check name and needs native Windows worktree seed (TEST-018)..."
  grep -qF 'name: skill test suite (tests/skills/, via test-framework.sh)' "$WORKFLOW_FILE" \
    || log_fail "gate job must keep the exact required-check name 'skill test suite (tests/skills/, via test-framework.sh)'"
  grep -qE 'needs:\s*\[select, skills-selected, skills-full, native-worktree-seed, tracked-ignored\]' "$WORKFLOW_FILE" \
    || log_fail "gate job must need select + skills-selected + skills-full + native-worktree-seed"
  grep -qF 'needs.native-worktree-seed.result' "$WORKFLOW_FILE" \
    || log_fail "gate job must reject a failed or skipped native Windows worktree seed"
  grep -qE 'if:\s*always\(\)' "$WORKFLOW_FILE" \
    || log_fail "gate job must run on always() so it reports even when a leaf is skipped"
  log_pass "Gate job preserves the required check and requires native Windows seed (TEST-018)"
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

test_021_docs_or_ledger_only_manifests_never_full_run() {  # TEST-009 / Spec-AC-07 (simple-and-friendly-to-use)
  log_info "Test: PR #350 and PR #347 manifests replay through the real map with no FULL_RUN; docs/ai/tests/** and docs/ai/AAI_VERSION.md each select a suite (TEST-009)..."
  local root="${1:-$PROJECT_ROOT}"
  # Fixtures live beside the ROOT under test, not beside this suite: passing a
  # different root and then reading manifests out of $PROJECT_ROOT would test one
  # checkout's map against another checkout's fixtures (Copilot review, PR #355).
  local fx="$root/tests/fixtures/select-suites"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local m out rc
  for m in pr-350.txt pr-347.txt; do
    [[ -f "$fx/$m" ]] || log_fail "test_021: manifest fixture missing: $fx/$m"
    out="$(node "$SELECTOR" --repo-root "$root" --files-from "$fx/$m" 2>&1)"; rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "test_021: exit code must be 0 for $m, got $rc: $out"
    case "$out" in
      *"FULL_RUN"*) log_fail "test_021: $m is docs-or-ledger-only and must not escalate: $out" ;;
    esac
    case "$out" in
      *"SELECTED "*) ;;
      *) log_fail "test_021: $m must select at least one suite: $out" ;;
    esac
  done
  local list="$TEST_DIR/t021-files.txt" p
  for p in "docs/ai/tests/x.jsonl" "docs/ai/AAI_VERSION.md"; do
    printf '%s\n' "$p" > "$list"
    out="$(node "$SELECTOR" --repo-root "$root" --files-from "$list" 2>&1)"; rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "test_021: exit code must be 0 for $p, got $rc: $out"
    case "$out" in
      *"FULL_RUN reason=unmapped"*) log_fail "test_021: $p must be mapped: $out" ;;
    esac
    case "$out" in
      *"SELECTED "*) ;;
      *) log_fail "test_021: $p must select at least one suite: $out" ;;
    esac
  done
  log_pass "test_021: docs-or-ledger-only manifests never FULL_RUN; both ledger paths mapped (TEST-009)"
}

test_022_ceremony_leftovers_never_full_run() {
  log_info "Test: generated skill READMEs and docs/ai/reviews/** are mapped so a close-ceremony PR does not FULL_RUN (TEST-022)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local list="$TEST_DIR/t022-files.txt" p out rc
  for p in \
    ".codex/skills/README.md" \
    ".gemini/skills/README.md" \
    "docs/ai/reviews/review-fixture.md"
  do
    printf '%s\n' "$p" > "$list"
    out="$(node "$SELECTOR" --repo-root "$root" --files-from "$list" 2>&1)"; rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "test_022: exit code must be 0 for $p, got $rc: $out"
    case "$out" in
      *"FULL_RUN"*) log_fail "test_022: $p must not escalate to FULL_RUN: $out" ;;
    esac
    case "$out" in
      *"SELECTED "*|*"CORE "*) ;;
      *) log_fail "test_022: $p must select at least one suite: $out" ;;
    esac
  done
  log_pass "test_022: skill-index READMEs and docs/ai/reviews/** stay selected, never FULL_RUN"
}

test_430_role_common_selects_aai_state() {  # Spec-AC-16 (spec-test-framework-sweep)
  log_info "Test: a change list containing only .aai/ROLE_COMMON.md selects aai-state, against the real repo suite-map (TEST-430)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local list="$TEST_DIR/t430-files.txt" out rc
  printf '%s\n' ".aai/ROLE_COMMON.md" > "$list"
  out="$(node "$SELECTOR" --repo-root "$root" --files-from "$list" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "test_430: exit code must be 0, got $rc: $out"
  case "$out" in
    *"aai-state"*) ;;
    *) log_fail "test_430: .aai/ROLE_COMMON.md must select aai-state: $out" ;;
  esac
  log_pass "test_430: .aai/ROLE_COMMON.md selects aai-state (TEST-430)"
}

# ---- CI test selection narrowing and sharding (ci-test-selection-
# narrowing-and-sharding / SPEC-DRAFT-spec-ci-test-selection-narrowing-and-
# sharding), TEST-1420..1439 ------------------------------------------

test_1420_real_repo_shard_completeness() {  # Spec-AC-01
  log_info "Test: real repo --shards 4: sorted SHARD suite column equals sorted find list, SHARDS suites= count, exit 0 (TEST-1420)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  run_shard "$root" --shards 4
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1420: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  local plan="$TEST_DIR/plan.txt"
  printf '%s\n' "$OUT" > "$plan"
  local planned expected total
  planned="$(planned_suite_names "$plan")"
  expected="$(real_suite_names "$root")"
  [[ "$planned" == "$expected" ]] || log_fail "TEST-1420: planned suite set must equal the find set exactly, each once"
  total="$(printf '%s\n' "$expected" | grep -c . || true)"
  assert_payload_has_line "$OUT" "SHARDS count=4 suites=$total" "TEST-1420: expected SHARDS count=4 suites=$total: $(payload_preview "$OUT")"
  log_pass "TEST-1420: real-repo shard completeness holds (TEST-1420)"
}

test_1421_weight_orphan_and_completeness() {  # Spec-AC-01 (fixture diversity: multi-source/multi-writer via orphan+known mix)
  log_info "Test: fixture of 5 suites, weights for 3 plus an orphan row: all 5 assigned exactly once, orphan reported and never assigned (TEST-1421)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-alpha aai-bravo aai-delta aai-echo aai-zulu
  local weights="$TEST_DIR/weights.tsv"
  printf 'aai-alpha\t10\naai-bravo\t5\naai-delta\t3\naai-ghost-orphan\t99\n' > "$weights"
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1421: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "WEIGHT_ORPHAN aai-ghost-orphan" "TEST-1421: missing WEIGHT_ORPHAN: $(payload_preview "$OUT")"
  local plan="$TEST_DIR/plan.txt"
  printf '%s\n' "$OUT" > "$plan"
  local planned expected
  planned="$(planned_suite_names "$plan")"
  expected="$(printf 'aai-alpha\naai-bravo\naai-delta\naai-echo\naai-zulu\n' | sort -u)"
  [[ "$planned" == "$expected" ]] || log_fail "TEST-1421: all 5 fixture suites must be assigned exactly once, got: $planned"
  if grep -E '^SHARD [0-9]+ aai-ghost-orphan ' "$plan" >/dev/null; then
    log_fail "TEST-1421: the orphan must never be assigned to a shard: $(payload_preview "$OUT")"
  fi
  log_pass "TEST-1421: weight orphan reported, never assigned; completeness holds (TEST-1421)"
}

test_1422_deterministic_tie_break_golden() {  # Spec-AC-02
  log_info "Test: 6-suite fixture with a weight tie at N=2: stdout equals a golden plan byte for byte, two runs are identical (TEST-1422)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_tie6_scrambled "$TEST_DIR"
  local weights="$TEST_DIR/weights.tsv"
  printf 'aai-one\t5\naai-two\t5\naai-three\t5\naai-four\t3\naai-five\t3\naai-six\t1\n' > "$weights"
  local golden
  golden="$(printf 'SHARD 1 aai-one weight=5\nSHARD 1 aai-two weight=5\nSHARD 1 aai-six weight=1\nSHARD 2 aai-three weight=5\nSHARD 2 aai-five weight=3\nSHARD 2 aai-four weight=3\nSHARDS count=2 suites=6')"
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1422: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  [[ "$OUT" == "$golden" ]] || log_fail "TEST-1422: plan must equal the golden byte for byte, got: $(payload_preview "$OUT")"
  local out2
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  out2="$OUT"
  [[ "$out2" == "$golden" ]] || log_fail "TEST-1422: a second run must reproduce the same golden plan byte for byte"
  log_pass "TEST-1422: deterministic weight-tie tie-break matches the golden plan twice (TEST-1422)"
}

test_1423_real_repo_balance_bound() {  # Spec-AC-02
  log_info "Test: real repo + committed weights at N=4: the largest shard weight-sum stays within the spec's bound (TEST-1423)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  run_shard "$root" --shards 4
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1423: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  local plan="$TEST_DIR/plan.txt"
  printf '%s\n' "$OUT" > "$plan"
  # Positive control (absence-no-control, LEARNED.md 2026-09-05): a plan with
  # ZERO SHARD lines would trivially satisfy "largest shard sum <= bound"
  # below without shard mode having run at all. Assert the mechanism fired.
  local shard_line_count expected_count
  shard_line_count="$(grep -c '^SHARD ' "$plan" || true)"
  expected_count="$(real_suite_names "$root" | grep -c . || true)"
  [[ "$shard_line_count" -eq "$expected_count" ]] \
    || log_fail "TEST-1423: expected $expected_count SHARD lines (one per real suite), got $shard_line_count: $(payload_preview "$OUT")"
  # D3 ("no hygiene pin", a missing weight "costs minutes, never coverage"):
  # total/max_w come from the PLAN's own emitted weight= values, not from the
  # weights file — the plan gives every unweighted suite maxKnownWeight, so a
  # PR that adds a suite with no weight row still schedules it (NB-1,
  # review-20261003T124300Z.md), and the bound must follow what was actually
  # scheduled rather than go red on an input the spec says is optional.
  local total max_w
  total="$(awk '/^SHARD /{w=$0; sub(/.*weight=/,"",w); t+=w+0} END{print t+0}' "$plan")"
  max_w="$(awk '/^SHARD /{w=$0; sub(/.*weight=/,"",w); w+=0; if (w>m) m=w} END{print m+0}' "$plan")"
  local ideal bound
  ideal=$(( (total + 3) / 4 ))
  bound=$(( (ideal * 105 + 99) / 100 ))
  if [[ "$max_w" -gt "$bound" ]]; then bound="$max_w"; fi
  local max_sum
  max_sum="$(awk '/^SHARD /{w=$0; sub(/.*weight=/,"",w); sum[$2]+=w+0} END{m=0; for (k in sum) if (sum[k]>m) m=sum[k]; print m+0}' "$plan")"
  [[ "$max_sum" -le "$bound" ]] || log_fail "TEST-1423: largest shard weight-sum $max_sum exceeds bound $bound (total=$total ideal=$ideal maxw=$max_w)"
  log_pass "TEST-1423: real-repo balance stays within ceil(1.05*ideal) / max-weight bound (TEST-1423)"
}

test_1424_shards_never_increase_in_weight() {  # Spec-AC-02
  log_info "Test: real repo N=4, and the TEST-1422 fixture: inside every shard the emitted weights never increase (TEST-1424)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  run_shard "$root" --shards 4
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1424: exit code must be 0 for the real repo, got $CODE"
  local plan_real="$TEST_DIR/plan-real.txt"
  printf '%s\n' "$OUT" > "$plan_real"
  # Positive control (absence-no-control, LEARNED.md 2026-09-05): zero SHARD
  # lines would vacuously satisfy "never increase" below. Assert it ran.
  local real_shard_count
  real_shard_count="$(grep -c '^SHARD ' "$plan_real" || true)"
  [[ "$real_shard_count" -ge 1 ]] || log_fail "TEST-1424: expected SHARD lines for the real repo, got none: $(payload_preview "$OUT")"
  assert_shard_weights_non_increasing "$plan_real" "TEST-1424 (real repo)"

  fixture_tie6_scrambled "$TEST_DIR"
  local weights="$TEST_DIR/weights.tsv"
  printf 'aai-one\t5\naai-two\t5\naai-three\t5\naai-four\t3\naai-five\t3\naai-six\t1\n' > "$weights"
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1424: exit code must be 0 for the fixture, got $CODE"
  local plan_fixture="$TEST_DIR/plan-fixture.txt"
  printf '%s\n' "$OUT" > "$plan_fixture"
  local fixture_shard_count
  fixture_shard_count="$(grep -c '^SHARD ' "$plan_fixture" || true)"
  [[ "$fixture_shard_count" -eq 6 ]] || log_fail "TEST-1424: expected 6 SHARD lines for the fixture, got $fixture_shard_count: $(payload_preview "$OUT")"
  assert_shard_weights_non_increasing "$plan_fixture" "TEST-1424 (TEST-1422 fixture)"
  log_pass "TEST-1424: emitted weights never increase within a shard, real repo and fixture alike (TEST-1424)"
}

test_1425_unweighted_gets_max_known_first_in_shard() {  # Spec-AC-02
  log_info "Test: a fixture suite with no weight row is emitted with weight=maxKnownWeight and leads its shard (TEST-1425)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-known-low aai-known-mid aai-unweighted aai-known-high
  local weights="$TEST_DIR/weights.tsv"
  printf 'aai-known-low\t2\naai-known-mid\t5\naai-known-high\t8\n' > "$weights"
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1425: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  local plan="$TEST_DIR/plan.txt"
  printf '%s\n' "$OUT" > "$plan"
  assert_payload_has_line "$OUT" "SHARD 2 aai-unweighted weight=8" "TEST-1425: the unweighted suite must get weight=maxKnownWeight(8) in its shard: $(payload_preview "$OUT")"
  local first_of_shard2
  first_of_shard2="$(awk '/^SHARD /{if ($2==2) {print; exit}}' "$plan")"
  [[ "$first_of_shard2" == "SHARD 2 aai-unweighted weight=8" ]] \
    || log_fail "TEST-1425: the unweighted suite must be the FIRST suite of its shard, got first: $first_of_shard2"
  log_pass "TEST-1425: unweighted suite gets max known weight and leads its shard (TEST-1425)"
}

test_1426_invalid_shard_count_fallback() {  # Spec-AC-03
  log_info "Test: --shards 0, 9, abc and a missing value each print SHARD_FALLBACK reason=invalid-shard-count, no SHARD line, exit 0 (TEST-1426)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local v
  for v in 0 9 abc; do
    run_shard "$PROJECT_ROOT" --shards "$v"
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-1426: exit code must be 0 for --shards $v, got $CODE: $(payload_preview "$OUT")"
    assert_payload_has_line "$OUT" "SHARD_FALLBACK reason=invalid-shard-count" "TEST-1426: --shards $v must fall back cleanly: $(payload_preview "$OUT")"
    assert_payload_line_not_matches "$OUT" '^SHARD ' "TEST-1426: --shards $v must print no SHARD line: $(payload_preview "$OUT")"
  done
  CODE=0
  OUT="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --shards 2>&1)" || CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1426: exit code must be 0 for a missing --shards value, got $CODE: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "SHARD_FALLBACK reason=invalid-shard-count" "TEST-1426: a missing --shards value must fall back cleanly: $(payload_preview "$OUT")"
  log_pass "TEST-1426: invalid shard counts and a missing value all fall back cleanly, exit 0 (TEST-1426)"
}

test_1427_malformed_weights_ignored_whole_file() {  # Spec-AC-03
  log_info "Test: a malformed weights row ignores the WHOLE file (WEIGHTS_IGNORED), plan stays complete, exit 0 (TEST-1427)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-alpha aai-bravo aai-charlie
  local weights="$TEST_DIR/weights.tsv"
  printf '# comment\naai-alpha\t5\nnot-a-valid-row\naai-bravo\t3\n' > "$weights"
  run_shard "$TEST_DIR" --shards 2 --weights "$weights"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1427: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "WEIGHTS_IGNORED reason=malformed-line line=3" "TEST-1427: expected WEIGHTS_IGNORED naming line 3: $(payload_preview "$OUT")"
  local plan="$TEST_DIR/plan.txt"
  printf '%s\n' "$OUT" > "$plan"
  local planned expected
  planned="$(planned_suite_names "$plan")"
  expected="$(printf 'aai-alpha\naai-bravo\naai-charlie\n' | sort -u)"
  [[ "$planned" == "$expected" ]] || log_fail "TEST-1427: every fixture suite must still be assigned exactly once despite the malformed weights file, got: $planned"
  log_pass "TEST-1427: a malformed weights row ignores the WHOLE file but keeps the plan complete (TEST-1427)"
}

test_1428_no_suites_fallback() {  # Spec-AC-03 (fixture diversity: degenerate/empty)
  log_info "Test: a repo root with no on-disk suites prints SHARD_FALLBACK reason=no-suites, no SHARD line, exit 0 (TEST-1428)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  mkdir -p "$TEST_DIR/tests/skills"
  run_shard "$TEST_DIR" --shards 4
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1428: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "SHARD_FALLBACK reason=no-suites" "TEST-1428: expected a no-suites fallback: $(payload_preview "$OUT")"
  assert_payload_line_not_matches "$OUT" '^SHARD ' "TEST-1428: must print no SHARD line: $(payload_preview "$OUT")"
  log_pass "TEST-1428: a repo root with zero suites falls back cleanly (TEST-1428)"
}

test_1429_default_mode_byte_identical_negative_control() {  # Spec-AC-03, negative control
  log_info "Test: negative control — without --shards the default mode stays byte-identical to the pre-shard-mode golden (TEST-1429)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" "src/alpha/foo.js"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1429: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  local golden
  golden="$(printf 'CORE aai-core-a reason=core\nCORE aai-core-b reason=core\nSELECTED aai-alpha reason=src/alpha/foo.js\nDROPPED 1')"
  [[ "$OUT" == "$golden" ]] || log_fail "TEST-1429: default-mode output must stay byte-identical to the pre-shard-mode golden, got: $(payload_preview "$OUT")"
  assert_payload_line_not_matches "$OUT" '^SHARD' "TEST-1429: default mode must never print a SHARD line: $(payload_preview "$OUT")"
  log_pass "TEST-1429: negative control — default mode is unaffected by shard mode's existence (TEST-1429)"
}

test_1430_check_complete_plan_prints_ids() {  # Spec-AC-04
  log_info "Test: --check on a complete 3-shard fixture plan exits 0 and prints exactly shard_ids=[1,2,3] (TEST-1430)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a aai-b aai-c
  local plan="$TEST_DIR/plan.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-b weight=3\nSHARD 3 aai-c weight=1\nSHARDS count=3 suites=3\n' > "$plan"
  run_check "$plan" "$TEST_DIR/tests/skills"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1430: exit code must be 0, got $CODE: $(payload_preview "$OUT")"
  [[ "$OUT" == 'shard_ids=[1,2,3]' ]] || log_fail "TEST-1430: expected exactly shard_ids=[1,2,3], got: $(payload_preview "$OUT")"
  log_pass "TEST-1430: --check on a complete plan prints exactly shard_ids=[1,2,3] (TEST-1430)"
}

test_1431_check_missing_and_extra_suite() {  # Spec-AC-04
  log_info "Test: --check exits non-zero naming the suite for a plan missing one on-disk suite, and for a plan naming a suite not on disk (TEST-1431)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a aai-b aai-c
  local plan_missing="$TEST_DIR/plan-missing.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-b weight=3\nSHARDS count=2 suites=2\n' > "$plan_missing"
  run_check "$plan_missing" "$TEST_DIR/tests/skills"
  [[ "$CODE" -ne 0 ]] || log_fail "TEST-1431: a plan missing an on-disk suite must exit non-zero"
  case "$OUT" in
    *"aai-c"*) ;;
    *) log_fail "TEST-1431: must name the missing suite aai-c: $(payload_preview "$OUT")" ;;
  esac

  local plan_extra="$TEST_DIR/plan-extra.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-b weight=3\nSHARD 2 aai-c weight=1\nSHARD 1 aai-ghost weight=1\nSHARDS count=2 suites=4\n' > "$plan_extra"
  run_check "$plan_extra" "$TEST_DIR/tests/skills"
  [[ "$CODE" -ne 0 ]] || log_fail "TEST-1431: a plan naming a suite not on disk must exit non-zero"
  case "$OUT" in
    *"aai-ghost"*) ;;
    *) log_fail "TEST-1431: must name the extra suite aai-ghost: $(payload_preview "$OUT")" ;;
  esac
  log_pass "TEST-1431: --check names the offending suite for both missing and extra (TEST-1431)"
}

test_1432_check_duplicate_assignment() {  # Spec-AC-04
  log_info "Test: --check exits non-zero naming the suite for a plan that assigns one suite to two shards (TEST-1432)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a aai-b
  local plan="$TEST_DIR/plan-dup.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-a weight=5\nSHARD 1 aai-b weight=1\nSHARDS count=2 suites=2\n' > "$plan"
  run_check "$plan" "$TEST_DIR/tests/skills"
  [[ "$CODE" -ne 0 ]] || log_fail "TEST-1432: a plan assigning one suite to two shards must exit non-zero"
  case "$OUT" in
    *"aai-a"*) ;;
    *) log_fail "TEST-1432: must name the duplicated suite aai-a: $(payload_preview "$OUT")" ;;
  esac
  log_pass "TEST-1432: --check rejects a suite assigned to two shards, naming it (TEST-1432)"
}

test_1433_fallback_plan_check_and_extract_all() {  # Spec-AC-04 (fixture diversity: degenerate/empty)
  log_info "Test: a SHARD_FALLBACK-only plan passes --check printing shard_ids=[\"all\"], and --extract all prints __ALL__ (TEST-1433)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a
  local plan="$TEST_DIR/plan-fallback.txt"
  printf 'SHARD_FALLBACK reason=no-suites\n' > "$plan"
  run_check "$plan" "$TEST_DIR/tests/skills"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1433: a fallback plan must pass --check, got $CODE: $(payload_preview "$OUT")"
  [[ "$OUT" == 'shard_ids=["all"]' ]] || log_fail "TEST-1433: expected shard_ids=[\"all\"], got: $(payload_preview "$OUT")"
  run_extract "all" "$plan"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1433: --extract all on a fallback plan must exit 0, got $CODE: $(payload_preview "$OUT")"
  [[ "$OUT" == '__ALL__' ]] || log_fail "TEST-1433: expected __ALL__, got: $(payload_preview "$OUT")"
  log_pass "TEST-1433: a SHARD_FALLBACK-only plan passes --check and --extract all (TEST-1433)"
}

test_1434_extract_exact_shard_and_unknown_id() {  # Spec-AC-04
  log_info "Test: --extract 2 prints exactly shard 2's suites in plan order; --extract 7 on a 3-shard plan exits non-zero (TEST-1434)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a aai-b aai-c aai-d
  local plan="$TEST_DIR/plan.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-b weight=4\nSHARD 2 aai-d weight=3\nSHARD 3 aai-c weight=1\nSHARDS count=3 suites=4\n' > "$plan"
  run_extract 2 "$plan"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1434: --extract 2 must exit 0, got $CODE: $(payload_preview "$OUT")"
  local golden
  golden="$(printf 'aai-b\naai-d')"
  [[ "$OUT" == "$golden" ]] || log_fail "TEST-1434: --extract 2 must print exactly shard 2's suites in plan order, got: $(payload_preview "$OUT")"
  run_extract 7 "$plan"
  [[ "$CODE" -ne 0 ]] || log_fail "TEST-1434: --extract 7 on a 3-shard plan must exit non-zero"
  log_pass "TEST-1434: --extract prints exactly one shard's suites in plan order; an unknown id fails (TEST-1434)"
}

test_1435_real_repo_seam_selector_to_checker() {  # Spec-AC-04, SEAM
  log_info "Test: real repo SEAM — select-suites.mjs --shards 4 into a plan, --check prints shard_ids=[1,2,3,4], union of --extract equals the find list (TEST-1435)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local plan="$TEST_DIR/plan.txt"
  CODE=0
  node "$SELECTOR" --repo-root "$root" --shards 4 > "$plan" 2>"$TEST_DIR/err.txt" || CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1435: the selector must exit 0, got $CODE"
  run_check "$plan" "$root/tests/skills"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1435: --check on the real plan must exit 0, got $CODE: $(payload_preview "$OUT")"
  [[ "$OUT" == 'shard_ids=[1,2,3,4]' ]] || log_fail "TEST-1435: expected shard_ids=[1,2,3,4], got: $(payload_preview "$OUT")"
  local union_file="$TEST_DIR/union.txt"
  : > "$union_file"
  local i
  for i in 1 2 3 4; do
    run_extract "$i" "$plan"
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-1435: --extract $i must exit 0, got $CODE: $(payload_preview "$OUT")"
    printf '%s\n' "$OUT" >> "$union_file"
  done
  local union_sorted expected union_count find_count
  union_sorted="$(sort -u "$union_file")"
  expected="$(real_suite_names "$root")"
  [[ "$union_sorted" == "$expected" ]] || log_fail "TEST-1435: the union of every --extract must equal the find list"
  union_count="$(grep -c . "$union_file" || true)"
  find_count="$(printf '%s\n' "$expected" | grep -c . || true)"
  [[ "$union_count" -eq "$find_count" ]] || log_fail "TEST-1435: the union must list each suite exactly once, union=$union_count find=$find_count"
  log_pass "TEST-1435: real-repo SEAM — selector plan validates and extracts completely (TEST-1435)"
}

test_1436_workflow_shard_step_and_matrix_pin() {  # Spec-AC-05
  log_info "Test: workflow pin — select's unconditional shard step, and skills-full's fail-fast:false matrix over fromJSON(shard_ids) (TEST-1436)..."
  local wf="$SHARD_WORKFLOW_FILE"
  [[ -f "$wf" ]] || log_fail "TEST-1436: missing workflow file $wf"
  grep -qE '^\s*-\s+id:\s*shard\s*$' "$wf" \
    || log_fail "TEST-1436: the select job must have a step 'id: shard'"
  grep -qF -- '--shards 4' "$wf" \
    || log_fail "TEST-1436: the shard step must run select-suites.mjs --shards 4"
  grep -qF 'shard-plan-check.sh --check' "$wf" \
    || log_fail "TEST-1436: the shard step must run shard-plan-check.sh --check"
  grep -qE 'shard_ids:\s*\$\{\{\s*steps\.shard\.outputs\.shard_ids\s*\}\}' "$wf" \
    || log_fail "TEST-1436: the select job must export shard_ids from the shard step"
  grep -qE 'shard_plan:\s*\$\{\{\s*steps\.shard\.outputs\.shard_plan\s*\}\}' "$wf" \
    || log_fail "TEST-1436: the select job must export shard_plan from the shard step"
  grep -qF 'fail-fast: false' "$wf" \
    || log_fail "TEST-1436: skills-full must set strategy.fail-fast: false"
  grep -qF 'fromJSON(needs.select.outputs.shard_ids)' "$wf" \
    || log_fail "TEST-1436: skills-full matrix must iterate fromJSON(needs.select.outputs.shard_ids)"
  grep -qE 'SHARD_PLAN:\s*\$\{\{\s*needs\.select\.outputs\.shard_plan\s*\}\}' "$wf" \
    || log_fail "TEST-1436: the skills-full leg must pass the plan through env: (SHARD_PLAN), never inline-interpolated"
  grep -qF -- 'shard-plan-check.sh --extract' "$wf" \
    || log_fail "TEST-1436: the skills-full leg must run --extract for its own shard"
  grep -qF 'bash tests/skills/test-framework.sh "${args[@]}"' "$wf" \
    || log_fail "TEST-1436: the skills-full leg must run ONE test-framework.sh invocation with accumulated --skill flags"
  local fd_count
  fd_count="$(grep -c 'fetch-depth: 0' "$wf" || true)"
  [[ "$fd_count" -ge 4 ]] || log_fail "TEST-1436: expected fetch-depth: 0 on every checkout including each skills-full leg's, got count=$fd_count"
  log_pass "TEST-1436: the workflow wires the unconditional shard step and the skills-full matrix (TEST-1436)"
}

test_1437_gate_unchanged_negative_control() {  # Spec-AC-05, negative control
  log_info "Test: negative control — the gate job keeps its exact name, extended needs list, always(), and full-mode success line (TEST-1437)..."
  local wf="$SHARD_WORKFLOW_FILE"
  grep -qF 'name: skill test suite (tests/skills/, via test-framework.sh)' "$wf" \
    || log_fail "TEST-1437: the gate job must keep its exact required-check name"
  grep -qE 'needs:\s*\[select, skills-selected, skills-full, native-worktree-seed, tracked-ignored\]' "$wf" \
    || log_fail "TEST-1437: the gate job must require the selected/full suite and native Windows seed jobs"
  grep -qE 'if:\s*always\(\)' "$wf" \
    || log_fail "TEST-1437: the gate job must keep if: always()"
  grep -qF '[ "${{ needs.skills-full.result }}" = "success" ] || { echo "full-mode run failed"; exit 1; }' "$wf" \
    || log_fail "TEST-1437: the gate job must keep its exact full-mode success line"
  grep -qF 'needs.native-worktree-seed.result' "$wf" \
    || log_fail "TEST-1437: the gate job must reject a failed or skipped native Windows seed"
  log_pass "TEST-1437: negative control — the existing suite verdict and native Windows dependency remain required (TEST-1437)"
}

test_1438_leg_rechecks_before_extract() {  # Spec-AC-05
  log_info "Test: the skills-full leg re-runs --check on its own checkout before --extract (TEST-1438)..."
  local wf="$SHARD_WORKFLOW_FILE"
  local check_line='bash tests/skills/lib/shard-plan-check.sh --check shard-plan.txt tests/skills >/dev/null'
  local check_hits extract_hits check_ln extract_ln
  check_hits="$(grep -nF -- "$check_line" "$wf" || true)"
  extract_hits="$(grep -nF -- 'shard-plan-check.sh --extract' "$wf" || true)"
  [[ -n "$check_hits" ]] || log_fail "TEST-1438: the skills-full leg must re-run --check on its own checkout: $check_line"
  [[ -n "$extract_hits" ]] || log_fail "TEST-1438: the skills-full leg must run --extract"
  check_ln="${check_hits%%:*}"
  extract_ln="${extract_hits%%:*}"
  [[ "$check_ln" -lt "$extract_ln" ]] || log_fail "TEST-1438: --check must run BEFORE --extract in the leg (check@$check_ln extract@$extract_ln)"
  log_pass "TEST-1438: the skills-full leg re-checks the plan before extracting its shard (TEST-1438)"
}

test_1439_real_map_replay_new_paths() {  # Spec-AC-05
  log_info "Test: real map replay — suite-weights.tsv and shard-plan-check.sh each select aai-suite-select, no FULL_RUN (TEST-1439)..."
  local root="${1:-$PROJECT_ROOT}"
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local list="$TEST_DIR/t1439-files.txt" p out rc
  # SUITE_MAP_OVERRIDE (optional): point --map at a snapshot suite-map.yaml,
  # used by a pre-change RED run against the git-HEAD map that pre-dates D6's
  # two new glob rows (SELECTOR's own default is used when unset). A plain
  # if-branch, not an optionally-empty array: bash <4.4 treats
  # "${empty_array[@]}" as unbound under `set -u` (bash-3.2-safe rule).
  for p in "tests/skills/suite-weights.tsv" "tests/skills/lib/shard-plan-check.sh"; do
    printf '%s\n' "$p" > "$list"
    rc=0
    if [[ -n "${SUITE_MAP_OVERRIDE:-}" ]]; then
      out="$(node "$SELECTOR" --repo-root "$root" --map "$SUITE_MAP_OVERRIDE" --files-from "$list" 2>&1)" || rc=$?
    else
      out="$(node "$SELECTOR" --repo-root "$root" --files-from "$list" 2>&1)" || rc=$?
    fi
    [[ "$rc" -eq 0 ]] || log_fail "TEST-1439: exit code must be 0 for $p, got $rc: $out"
    case "$out" in
      *"FULL_RUN"*) log_fail "TEST-1439: $p must not escalate to FULL_RUN: $out" ;;
    esac
    case "$out" in
      *"aai-suite-select"*) ;;
      *) log_fail "TEST-1439: $p must select aai-suite-select: $out" ;;
    esac
  done
  log_pass "TEST-1439: the new sharding files join aai-suite-select's globs (TEST-1439)"
}

test_1440_check_rejects_unresolvable_nested_suite() {  # Spec-AC-04 (post-freeze amendment, BLOCKING-1 review-20261003T124300Z.md)
  log_info "Test: --check rejects a plan naming a suite that only exists nested (no top-level test-<name>.sh, unresolvable by test-framework.sh --skill), naming the offender (TEST-1440)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  fixture_suites "$TEST_DIR" aai-a aai-b
  mkdir -p "$TEST_DIR/tests/skills/nested_sub"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/tests/skills/nested_sub/test-aai-c.sh"
  local plan="$TEST_DIR/plan-nested.txt"
  printf 'SHARD 1 aai-a weight=5\nSHARD 2 aai-b weight=3\nSHARD 3 aai-c weight=1\nSHARDS count=3 suites=3\n' > "$plan"
  # Positive control (absence-no-control, LEARNED.md 2026-09-05): the on-disk
  # RECURSIVE find proves this plan "complete" (aai-c exists, just nested) —
  # confirm the fixture genuinely has 3 on-disk suites (2 top-level + 1
  # nested) so a pass below would mean the new resolvability check did not
  # run, not that there was nothing to catch.
  local recursive_count
  recursive_count="$(find "$TEST_DIR/tests/skills" -name 'test-aai-*.sh' -type f | wc -l | tr -d ' ')"
  [[ "$recursive_count" -eq 3 ]] \
    || log_fail "TEST-1440: fixture setup broken, expected 3 on-disk suites (2 top-level + 1 nested), got $recursive_count"
  run_check "$plan" "$TEST_DIR/tests/skills"
  [[ "$CODE" -ne 0 ]] \
    || log_fail "TEST-1440: --check must reject a plan naming a suite unresolvable by test-framework.sh --skill (nested, no top-level file), got exit 0: $(payload_preview "$OUT")"
  case "$OUT" in
    *"aai-c"*) ;;
    *) log_fail "TEST-1440: must name the unresolvable suite aai-c: $(payload_preview "$OUT")" ;;
  esac
  # Negative control: the same fixture with aai-c promoted to top-level must
  # pass --check cleanly, proving the rejection above is about resolvability,
  # not an unconditional failure on any 3-suite plan.
  rm -rf "$TEST_DIR/tests/skills/nested_sub"
  fixture_suites "$TEST_DIR" aai-c
  run_check "$plan" "$TEST_DIR/tests/skills"
  [[ "$CODE" -eq 0 ]] \
    || log_fail "TEST-1440: the same plan must pass --check once aai-c is top-level, got $CODE: $(payload_preview "$OUT")"
  log_pass "TEST-1440: --check rejects a nested, --skill-unresolvable suite, naming it; the top-level case still passes (TEST-1440)"
}

# ---- inert class and delta mode (post-validation-pushes-reuse-test-results,
# D4, TEST-1711..1716 and TEST-1727) -----------------------------------------

# inert_map <dir> — small_map plus inert_globs and carry_forward_globs. aai-alpha
# also claims docs/ai/reports/** so the inert-vs-suite precedence is observable;
# aai-ledger maps the two ledger paths the delta fixtures touch.
inert_map() {
  local dir="$1"
  mkdir -p "$dir/tests/skills"
  cat > "$dir/tests/skills/suite-map.yaml" <<'YAML'
core:
  - aai-core-a
  - aai-core-b

inert_globs:
  - docs/ai/reports/**
  - docs/ai/tdd/**

carry_forward_globs:
  - docs/ai/EVENTS.jsonl
  - docs/INDEX.md

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
      - docs/ai/reports/**
  aai-ledger:
    globs:
      - docs/ai/EVENTS.jsonl
  aai-index:
    globs:
      - docs/INDEX.md
  aai-other:
    globs:
      - src/other/**
YAML
}

test_1711_inert_paths_select_core_only() {  # Spec-AC-05
  log_info "Test: inert-only changes give CORE only, no FULL_RUN; an unmapped path beside them still FULL_RUNs (TEST-1711)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  inert_map "$TEST_DIR"
  run_sel "$TEST_DIR" docs/ai/reports/VALIDATION-x.md docs/ai/tdd/spec/red-1.log
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1711: exit must be 0, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "CORE aai-core-a reason=core" "TEST-1711: CORE a must run: $OUT"
  assert_payload_has_line "$OUT" "CORE aai-core-b reason=core" "TEST-1711: CORE b must run: $OUT"
  assert_payload_has_line "$OUT" "DROPPED 4" "TEST-1711: every non-core suite is dropped: $OUT"
  assert_payload_line_not_matches "$OUT" '^(FULL_RUN|SELECTED )' "TEST-1711: inert paths must neither FULL_RUN nor select: $OUT"
  # negation: the same list plus an unmapped path
  run_sel "$TEST_DIR" docs/ai/reports/VALIDATION-x.md zz/unmapped.txt
  assert_payload_has_line "$OUT" "FULL_RUN reason=unmapped path=zz/unmapped.txt" "TEST-1711: negation — an unmapped path must still FULL_RUN, naming it: $OUT"
  log_pass "TEST-1711: inert paths select CORE only; unmapped neighbour still falls open"
}

test_1712_inert_precedence_and_byte_identity() {  # Spec-AC-05
  log_info "Test: inert beats suite match; protected-l3 and shared-lib still FULL_RUN; absent inert_globs selects byte-identically (TEST-1712)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  inert_map "$TEST_DIR"
  run_sel "$TEST_DIR" docs/ai/reports/VALIDATION-x.md
  assert_payload_line_not_matches "$OUT" '^SELECTED aai-alpha' "TEST-1712: an inert path matched by a suite glob must select nothing: $OUT"
  # protected-l3 outranks inert
  mkdir -p "$TEST_DIR/docs/ai"
  printf 'protected_paths_l3:\n  - docs/ai/reports/PROTECTED.md\n' > "$TEST_DIR/docs/ai/docs-audit.yaml"
  run_sel "$TEST_DIR" docs/ai/reports/PROTECTED.md
  assert_payload_has_line "$OUT" "FULL_RUN reason=protected-l3 path=docs/ai/reports/PROTECTED.md" "TEST-1712: protected-l3 must outrank inert: $OUT"
  rm -f "$TEST_DIR/docs/ai/docs-audit.yaml"
  # shared-lib outranks inert
  run_sel "$TEST_DIR" docs/ai/reports/x.md .aai/scripts/lib/y.mjs
  assert_payload_has_line "$OUT" "FULL_RUN reason=shared-lib path=.aai/scripts/lib/y.mjs" "TEST-1712: shared-lib must outrank inert: $OUT"
  # byte identity: a map without the two lists selects exactly as before
  local plain="$TEST_DIR/plain" a b
  mkdir -p "$plain"
  small_map "$plain"
  local sans="$TEST_DIR/sans"
  mkdir -p "$sans"
  small_map "$sans"
  printf 'inert_globs:\n  - nothing/at/all/**\n' >> "$sans/tests/skills/suite-map.yaml"
  run_sel "$plain" src/alpha/a.js src/beta/b.js docs/core-a.md
  a="$OUT"
  run_sel "$sans" src/alpha/a.js src/beta/b.js docs/core-a.md
  b="$OUT"
  [[ "$a" == "$b" ]] || log_fail "TEST-1712: a map with an unrelated inert list must select byte-identically: [$a] vs [$b]"
  run_sel "$plain" docs/ai/reports/x.md
  assert_payload_has_line "$OUT" "FULL_RUN reason=unmapped path=docs/ai/reports/x.md" "TEST-1712: without inert_globs the report path is unmapped as before: $OUT"
  log_pass "TEST-1712: inert precedence below protected-l3 and shared-lib, above suite match; old maps unchanged"
}

test_1713_real_map_inert_pinned_to_ignored_dirs() {  # Spec-AC-05
  log_info "Test: every real inert glob is <dir>/** over a gitignored dir; every carry-forward glob classifies without FULL_RUN (TEST-1713)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local map="$PROJECT_ROOT/tests/skills/suite-map.yaml" line sect="" g dir n_inert=0 n_carry=0 out rc
  local probes="$TEST_DIR/probes.txt"
  : > "$probes"
  while IFS= read -r line; do
    case "$line" in
      "inert_globs:") sect=inert; continue ;;
      "carry_forward_globs:") sect=carry; continue ;;
      "  - "*) ;;
      "") continue ;;
      "#"*) continue ;;
      *) sect=""; continue ;;
    esac
    [[ -n "$sect" ]] || continue
    g="${line#  - }"
    if [[ "$sect" == "inert" ]]; then
      n_inert=$((n_inert + 1))
      case "$g" in
        */'**') ;;
        *) log_fail "TEST-1713: inert glob must be <dir>/**, got: $g" ;;
      esac
      dir="${g%/\*\*}"
      case "$dir" in *'*'*) log_fail "TEST-1713: inert dir must be a literal directory: $g" ;; esac
      git -C "$PROJECT_ROOT" check-ignore -q "$dir/probe" \
        || log_fail "TEST-1713: $dir/probe is not ignored by the repository .gitignore, so $g could swallow a committed surface"
      printf '%s/probe\n' "$dir" >> "$probes"
    else
      n_carry=$((n_carry + 1))
      printf '%s\n' "${g//\*\*/probe/x.txt}" >> "$probes"
    fi
  done < "$map"
  [[ "$n_inert" -ge 1 ]] || log_fail "TEST-1713: the real map declares no inert_globs"
  [[ "$n_carry" -ge 1 ]] || log_fail "TEST-1713: the real map declares no carry_forward_globs"
  # one representative path per glob, classified one at a time: no FULL_RUN
  local p
  while IFS= read -r p; do
    printf '%s\n' "$p" > "$TEST_DIR/one.txt"
    out="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --files-from "$TEST_DIR/one.txt" 2>&1)"; rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "TEST-1713: exit must be 0 for $p, got $rc: $out"
    case "$out" in
      *FULL_RUN*) log_fail "TEST-1713: $p must classify as mapped or inert, got: $out" ;;
    esac
  done < "$probes"
  log_pass "TEST-1713: $n_inert inert globs pinned to ignored dirs; $n_carry carry-forward globs classify without FULL_RUN"
}

# real_select <path> — run the real selector on one path against the real map.
real_select() {
  printf '%s\n' "$1" > "$TEST_DIR/one.txt" || log_fail "real_select: write failed"
  OUT="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --files-from "$TEST_DIR/one.txt" 2>&1)" || log_fail "real_select: selector failed for $1: $OUT"
}

test_1737_real_map_gitignore_full_and_guard_scripts_select() {  # validation round 1 BLOCKING-1
  log_info "Test: a .gitignore-only path list stays FULL_RUN; the commit-guard scripts and LOCAL EVIDENCE prompts select aai-tracked-ignored (TEST-1737)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  real_select .gitignore
  case "$OUT" in
    *"FULL_RUN reason=unmapped path=.gitignore"*) ;;
    *) log_fail "TEST-1737: a .gitignore-only PR must stay FULL_RUN reason=unmapped, got: $OUT" ;;
  esac
  local p
  for p in .aai/scripts/check-committed-scope.mjs .aai/scripts/pre-commit-checks.sh .aai/scripts/pre-commit-checks.ps1 \
           .aai/VALIDATION.prompt.md .aai/SKILL_TDD.prompt.md .aai/SKILL_PR.prompt.md; do
    real_select "$p"
    case "$OUT" in
      *FULL_RUN*) continue ;;   # protected-l3 / shared surface: whole sweep already covers it
    esac
    case "$OUT" in
      *aai-tracked-ignored*) ;;
      *) log_fail "TEST-1737: $p must select aai-tracked-ignored (or be FULL_RUN), got: $OUT" ;;
    esac
  done
  real_select .aai/scripts/check-committed-scope.mjs
  case "$OUT" in
    *FULL_RUN*) log_fail "TEST-1737: check-committed-scope.mjs is a mapped surface, not FULL_RUN, got: $OUT" ;;
    *aai-tracked-ignored*) ;;
    *) log_fail "TEST-1737: check-committed-scope.mjs must select aai-tracked-ignored, got: $OUT" ;;
  esac
  real_select .aai/scripts/tracked-ignored.mjs
  case "$OUT" in
    *aai-close-work-item*) ;;
    *) log_fail "TEST-1737: tracked-ignored.mjs (imported by lib/evidence-paths.mjs) must select aai-close-work-item, got: $OUT" ;;
  esac
  log_pass "TEST-1737: .gitignore stays unmapped (FULL_RUN); guard scripts select aai-tracked-ignored (TEST-1737)"
}

# delta_repo <dir> — a real git repo with the inert_map, branch main, and
# its own identity; prints nothing. Every setup exit code is checked.
delta_repo() {
  local repo="$1"
  [[ -n "$repo" && "$repo" == /* ]] || log_fail "delta_repo: path must be non-empty and absolute: '$repo'"
  mkdir -p "$repo" || log_fail "delta_repo: mkdir failed"
  git -C "$repo" init -q -b main || log_fail "delta_repo: git init failed"
  git -C "$repo" symbolic-ref HEAD refs/heads/main || log_fail "delta_repo: symbolic-ref failed"
  git -C "$repo" config user.email fixture@example.invalid || log_fail "delta_repo: config email failed"
  git -C "$repo" config user.name Fixture || log_fail "delta_repo: config name failed"
  inert_map "$repo"
}

# delta_commit <repo> <msg> <path...> — write each path then commit them.
delta_commit() {
  local repo="$1" msg="$2" p; shift 2
  for p in "$@"; do
    case "$p" in */*) mkdir -p "$repo/${p%/*}" || log_fail "delta_commit: mkdir failed: $p" ;; esac
    printf '%s\n' "$msg" >> "$repo/$p" || log_fail "delta_commit: write failed: $p"
  done
  git -C "$repo" add -A || log_fail "delta_commit: add failed"
  git -C "$repo" commit -q -m "$msg" || log_fail "delta_commit: commit failed"
}

delta_sel() {  # <repo> <args...> — sets OUT and CODE
  local repo="$1"; shift
  local rc=0
  OUT="$(node "$SELECTOR" --repo-root "$repo" "$@" 2>&1)" || rc=$?
  CODE=$rc
}

test_1714_delta_selects_over_the_delta_only() {  # Spec-AC-06
  log_info "Test: --delta-base S --head H over EVENTS.jsonl and INDEX.md selects those paths' suites only (TEST-1714)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo" s h x
  delta_repo "$repo"
  delta_commit "$repo" seed README.md docs/core-a.md
  s="$(git -C "$repo" rev-parse HEAD)"
  delta_commit "$repo" ledger docs/ai/EVENTS.jsonl docs/INDEX.md
  h="$(git -C "$repo" rev-parse HEAD)"
  # a later commit beyond H that must NOT leak into the delta
  delta_commit "$repo" later src/alpha/late.js
  x="$(git -C "$repo" rev-parse HEAD)"
  delta_sel "$repo" --delta-base "$s" --head "$h"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1714: exit must be 0, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "DELTA base=$s" "TEST-1714: DELTA line must name the base: $OUT"
  assert_payload_has_line "$OUT" "CORE aai-core-a reason=core" "TEST-1714: CORE must be printed: $OUT"
  assert_payload_has_line "$OUT" "SELECTED aai-ledger reason=docs/ai/EVENTS.jsonl" "TEST-1714: the ledger suite must be selected: $OUT"
  assert_payload_has_line "$OUT" "SELECTED aai-index reason=docs/INDEX.md" "TEST-1714: the index suite must be selected: $OUT"
  assert_payload_line_not_matches "$OUT" '^(SELECTED aai-alpha|DELTA_REFUSED|FULL_RUN)' "TEST-1714: a commit past H must not leak into the delta: $OUT"
  assert_payload_has_line "$OUT" "DROPPED 2" "TEST-1714: the other two suites are dropped: $OUT"
  # empty delta (S..S): DELTA plus CORE only
  delta_sel "$repo" --delta-base "$h" --head "$h"
  assert_payload_has_line "$OUT" "DELTA base=$h" "TEST-1714: empty delta still prints DELTA: $OUT"
  assert_payload_line_not_matches "$OUT" '^(SELECTED|DELTA_REFUSED|FULL_RUN)' "TEST-1714: empty delta selects nothing beyond CORE: $OUT"
  # head defaults to HEAD
  delta_sel "$repo" --delta-base "$h"
  assert_payload_has_line "$OUT" "DELTA_REFUSED reason=ineligible path=src/alpha/late.js" "TEST-1714: --head defaults to HEAD ($x): $OUT"
  log_pass "TEST-1714: delta mode selects over S..H only"
}

test_1715_delta_ineligible_cells() {  # Spec-AC-06
  log_info "Test: ineligible delta paths refuse by name and print no CORE line (TEST-1715)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo" s p n=0
  delta_repo "$repo"
  mkdir -p "$repo/docs/ai"
  printf 'protected_paths_l3:\n  - .aai/scripts/state.mjs\n' > "$repo/docs/ai/docs-audit.yaml"
  delta_commit "$repo" seed README.md
  s="$(git -C "$repo" rev-parse HEAD)"
  for p in .aai/scripts/x.mjs tests/skills/test-aai-x.sh .aai/X.prompt.md .github/workflows/y.yml .aai/scripts/state.mjs zz/u.txt; do
    n=$((n + 1))
    git -C "$repo" reset -q --hard "$s" || log_fail "TEST-1715: reset failed"
    delta_commit "$repo" "cell$n" docs/ai/EVENTS.jsonl "$p"
    delta_sel "$repo" --delta-base "$s"
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-1715: exit must be 0 for $p, got $CODE: $OUT"
    assert_payload_has_line "$OUT" "DELTA_REFUSED reason=ineligible path=$p" "TEST-1715: $p must be refused by name: $OUT"
    assert_payload_line_not_matches "$OUT" '^(CORE|SELECTED|DELTA base=)' "TEST-1715: a refusal prints no CORE/SELECTED line ($p): $OUT"
  done
  # negation: a carry-forward-only delta is NOT refused
  git -C "$repo" reset -q --hard "$s" || log_fail "TEST-1715: reset failed"
  delta_commit "$repo" ok docs/ai/EVENTS.jsonl docs/ai/reports/r.md
  delta_sel "$repo" --delta-base "$s"
  assert_payload_line_not_matches "$OUT" '^DELTA_REFUSED' "TEST-1715: negation — carry-forward plus inert paths are eligible: $OUT"
  log_pass "TEST-1715: $n ineligible cells refuse by name; carry-forward negation passes"
}

test_1716_delta_ancestry_and_unknown_sha() {  # Spec-AC-06
  log_info "Test: non-ancestor base refuses not-ancestor; unknown sha refuses internal-error; exit 0 always (TEST-1716)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo" base s h
  delta_repo "$repo"
  delta_commit "$repo" seed README.md
  base="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q -b old || log_fail "TEST-1716: checkout old failed"
  delta_commit "$repo" onold docs/ai/EVENTS.jsonl
  s="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main || log_fail "TEST-1716: checkout main failed"
  delta_commit "$repo" onmain docs/ai/EVENTS.jsonl
  h="$(git -C "$repo" rev-parse HEAD)"
  delta_sel "$repo" --delta-base "$s" --head "$h"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1716: exit must be 0, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "DELTA_REFUSED reason=not-ancestor" "TEST-1716: a force-pushed (diverged) base must refuse not-ancestor: $OUT"
  delta_sel "$repo" --delta-base 0000000000000000000000000000000000000000 --head "$h"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-1716: exit must be 0 for an unknown sha, got $CODE: $OUT"
  assert_payload_has_line "$OUT" "DELTA_REFUSED reason=internal-error" "TEST-1716: an unknown sha must refuse internal-error: $OUT"
  # positive control: the real ancestor works
  delta_sel "$repo" --delta-base "$base" --head "$h"
  assert_payload_has_line "$OUT" "DELTA base=$base" "TEST-1716: positive control — a true ancestor is accepted: $OUT"
  log_pass "TEST-1716: not-ancestor and unknown-sha refuse by name, exit 0"
}

test_1727_pr434_last_push_replay() {  # Spec-AC-09
  log_info "Test: the recorded PR #434 last-push path list selects CORE plus suites, never FULL_RUN (TEST-1727)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local fx="$PROJECT_ROOT/tests/fixtures/ci-carry-forward/pr434-last-push-paths.txt" out rc n
  [[ -f "$fx" ]] || log_fail "TEST-1727: replay manifest missing: $fx"
  n="$(wc -l < "$fx")"
  [[ "${n// /}" -ge 100 ]] || log_fail "TEST-1727: the manifest must hold the recorded 102 paths, has $n"
  out="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --files-from "$fx" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-1727: exit must be 0, got $rc: $out"
  assert_payload_line_not_matches "$out" '^FULL_RUN' "TEST-1727: the PR #434 last push must not FULL_RUN: $out"
  assert_payload_line_matches "$out" '^CORE ' "TEST-1727: CORE must be selected: $out"
  assert_payload_line_matches "$out" '^SELECTED ' "TEST-1727: the ledger and index paths must select suites: $out"
  # the same list without any report or tdd path: the six ceremony paths alone
  local rest="$TEST_DIR/rest.txt" line
  : > "$rest"
  while IFS= read -r line; do
    case "$line" in
      docs/ai/reports/*|docs/ai/tdd/*) ;;
      *) printf '%s\n' "$line" >> "$rest" ;;
    esac
  done < "$fx"
  [[ -s "$rest" ]] || log_fail "TEST-1727: the manifest holds no ceremony path outside the inert dirs"
  out="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --files-from "$rest" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-1727: exit must be 0 without report paths, got $rc: $out"
  assert_payload_line_not_matches "$out" '^FULL_RUN' "TEST-1727: without report paths there must be no FULL_RUN: $out"
  assert_payload_line_matches "$out" '^SELECTED ' "TEST-1727: without report paths suites are still selected: $out"
  # at least one report path really is in the manifest (the case under replay)
  assert_payload_line_matches "$(cat "$fx")" '^docs/ai/reports/' "TEST-1727: the manifest must carry report paths"
  log_pass "TEST-1727: PR #434 last push replays to CORE plus SELECTED, with and without report paths"
}

# ---- companions (nested-suite-reruns-duplicate-sweep-time, D1/D2/D4,
# TEST-001..005 = test_1750..test_1754) -----------------------------------

# write_map <dir> — read a suite-map.yaml body on stdin into <dir>.
write_map() {
  local dir="$1"
  [[ -n "$dir" && "$dir" == /* ]] || log_fail "write_map: path must be non-empty and absolute: '$dir'"
  mkdir -p "$dir/tests/skills" || log_fail "write_map: mkdir failed"
  cat > "$dir/tests/skills/suite-map.yaml" || log_fail "write_map: write failed"
}

# sel_count <payload> <ere> — number of payload lines matching the ERE.
sel_count() {
  local _p="$1" _e="$2" _l _n=0
  while IFS= read -r _l; do
    if [[ "$_l" =~ $_e ]]; then _n=$((_n + 1)); fi
  done <<EOT
$_p
EOT
  echo "$_n"
}

test_1750_companion_is_selected_with_its_parent() {  # Spec-AC-01 / TEST-001
  log_info "Test: a companion is selected after its parent with reason=companion:<parent> and counted in DROPPED (TEST-001)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  write_map "$TEST_DIR" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-y
    globs:
      - src/x/**
  aai-y:
    globs:
      - src/y/**
  aai-w:
    globs:
      - src/w/**
YAML
  run_sel "$TEST_DIR" src/x/a.js
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-001: exit must be 0, got $CODE: $OUT"
  local want
  want="CORE aai-c reason=core
SELECTED aai-x reason=src/x/a.js
SELECTED aai-y reason=companion:aai-x
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-001: companion selection output differs. want: $want -- got: $(payload_preview "$OUT")"
  # a companion the diff also selects by path keeps its path reason, once
  run_sel "$TEST_DIR" src/x/a.js src/y/b.js
  want="CORE aai-c reason=core
SELECTED aai-x reason=src/x/a.js
SELECTED aai-y reason=src/y/b.js
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-001: a path-selected companion keeps its path reason. got: $(payload_preview "$OUT")"
  # negative control: a diff that does not select the parent adds no companion
  run_sel "$TEST_DIR" src/w/a.js
  assert_payload_line_not_matches "$OUT" 'aai-y' "TEST-001: an unrelated diff must not pull in a companion: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "DROPPED 2" "TEST-001: unrelated diff drops x and y: $(payload_preview "$OUT")"
  log_pass "TEST-001: companions follow their parent with reason=companion:<parent>, DROPPED counts them (TEST-001)"
}

test_1751_companions_are_transitive_cycle_safe() {  # Spec-AC-01 / TEST-002
  log_info "Test: companions are followed transitively, a cycle terminates, a core companion prints no SELECTED line (TEST-002)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  write_map "$TEST_DIR" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-y
    globs:
      - src/x/**
  aai-y:
    companions:
      - aai-z
    globs:
      - src/y/**
  aai-z:
    globs:
      - src/z/**
  aai-w:
    companions:
      - aai-w2
      - aai-y
    globs:
      - src/w/**
  aai-w2:
    companions:
      - aai-w
      - aai-w2x
      - aai-c
    globs:
      - src/w2/**
  aai-w2x:
    globs:
      - src/w2x/**
YAML
  local want
  run_sel "$TEST_DIR" src/x/a.js
  want="CORE aai-c reason=core
SELECTED aai-x reason=src/x/a.js
SELECTED aai-y reason=companion:aai-x
SELECTED aai-z reason=companion:aai-y
DROPPED 3"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-002: x -> y -> z must select all three in order. got: $(payload_preview "$OUT")"
  # cycle w -> w2 -> w, plus a diamond into y (multi-source), plus a core companion
  run_sel "$TEST_DIR" src/w/a.js
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-002: a cycle must still exit 0, got $CODE"
  want="CORE aai-c reason=core
SELECTED aai-w reason=src/w/a.js
SELECTED aai-w2 reason=companion:aai-w
SELECTED aai-y reason=companion:aai-w
SELECTED aai-w2x reason=companion:aai-w2
SELECTED aai-z reason=companion:aai-y
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-002: cycle/diamond output differs. want: $want -- got: $(payload_preview "$OUT")"
  [[ "$(sel_count "$OUT" '^SELECTED aai-w ')" -eq 1 ]] || log_fail "TEST-002: the cycle must print aai-w once: $(payload_preview "$OUT")"
  [[ "$(sel_count "$OUT" '^SELECTED aai-c ')" -eq 0 ]] || log_fail "TEST-002: a core companion must print no SELECTED line: $(payload_preview "$OUT")"
  # degenerate: a suite whose companion list is empty-ish (listed twice) prints once
  write_map "$TEST_DIR" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-y
      - aai-y
    globs:
      - src/x/**
  aai-y:
    globs:
      - src/y/**
YAML
  run_sel "$TEST_DIR" src/x/a.js
  [[ "$(sel_count "$OUT" '^SELECTED aai-y ')" -eq 1 ]] || log_fail "TEST-002: a duplicated companion entry must print once: $(payload_preview "$OUT")"
  log_pass "TEST-002: companions are transitive, cycle-safe, deduplicated, and skip core suites (TEST-002)"
}

test_1752_malformed_companion_fails_open() {  # Spec-AC-02 / TEST-003
  log_info "Test: a ghost, self or bad-charset companion fails open in whole-PR and delta mode, exit 0 (TEST-003)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo" bad variant
  delta_repo "$repo"
  delta_commit "$repo" seed README.md
  for variant in ghost self charset; do
    case "$variant" in
      ghost) bad="aai-ghost" ;;
      self) bad="aai-x" ;;
      charset) bad="aai x!" ;;
    esac
    write_map "$repo" <<YAML
core:
  - aai-c

carry_forward_globs:
  - docs/INDEX.md

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - $bad
    globs:
      - src/x/**
YAML
    run_sel "$repo" src/x/a.js
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-003 ($variant): whole-PR exit must be 0, got $CODE: $OUT"
    case "$OUT" in
      "FULL_RUN reason=internal-error "*) ;;
      *) log_fail "TEST-003 ($variant): whole-PR must print FULL_RUN reason=internal-error, got: $(payload_preview "$OUT")" ;;
    esac
    delta_sel "$repo" --delta-base HEAD
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-003 ($variant): delta exit must be 0, got $CODE: $OUT"
    assert_payload_has_line "$OUT" "DELTA_REFUSED reason=internal-error" "TEST-003 ($variant): delta must refuse by name: $(payload_preview "$OUT")"
  done
  # the failure detail names the offending edge
  write_map "$repo" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-ghost
    globs:
      - src/x/**
YAML
  run_sel "$repo" src/x/a.js
  assert_payload_contains "$OUT" "companion has no suites row: aai-x -> aai-ghost" "TEST-003: ghost detail must name the edge: $(payload_preview "$OUT")"
  # flow-form companions (inline content on the key line) must not be silently
  # ignored: fail open like every other malformed companions block.
  local flow
  for flow in '[aai-c]' 'aai-c'; do
    write_map "$repo" <<YAML
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions: $flow
    globs:
      - src/x/**
YAML
    run_sel "$repo" src/x/a.js
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-003 (flow '$flow'): whole-PR exit must be 0, got $CODE: $OUT"
    case "$OUT" in
      "FULL_RUN reason=internal-error "*) ;;
      *) log_fail "TEST-003 (flow '$flow'): inline companions must print FULL_RUN reason=internal-error, got: $(payload_preview "$OUT")" ;;
    esac
    delta_sel "$repo" --delta-base HEAD
    assert_payload_has_line "$OUT" "DELTA_REFUSED reason=internal-error" "TEST-003 (flow '$flow'): delta must refuse by name: $(payload_preview "$OUT")"
  done
  # negative control: the same map with the ghost row defined selects normally
  write_map "$repo" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-ghost
    globs:
      - src/x/**
  aai-ghost:
    globs:
      - src/ghost/**
YAML
  run_sel "$repo" src/x/a.js
  assert_payload_line_not_matches "$OUT" '^FULL_RUN' "TEST-003: a defined companion must not fail open: $(payload_preview "$OUT")"
  assert_payload_has_line "$OUT" "SELECTED aai-ghost reason=companion:aai-x" "TEST-003: a defined companion is selected: $(payload_preview "$OUT")"
  log_pass "TEST-003: malformed companions fail open (FULL_RUN / DELTA_REFUSED internal-error), exit 0 (TEST-003)"
}

test_1753_core_companions_empty_diff_golden_and_workflow_line() {  # Spec-AC-03 / TEST-004
  log_info "Test: core companions on empty diff/delta, byte-identical golden without companions, workflow SUITES line (TEST-004)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local repo="$TEST_DIR/repo" want
  delta_repo "$repo"
  delta_commit "$repo" seed README.md
  write_map "$repo" <<'YAML'
core:
  - aai-c

carry_forward_globs:
  - docs/INDEX.md

suites:
  aai-c:
    companions:
      - aai-y
    globs:
      - docs/c.md
  aai-x:
    globs:
      - src/x/**
      - docs/INDEX.md
  aai-y:
    companions:
      - aai-z
    globs:
      - src/y/**
  aai-z:
    globs:
      - src/z/**
YAML
  # whole-PR empty diff: the core suite's companions (transitive) are selected
  run_sel "$repo"
  want="CORE aai-c reason=core
SELECTED aai-y reason=companion:aai-c
SELECTED aai-z reason=companion:aai-y
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004: empty diff must select the core companions. got: $(payload_preview "$OUT")"
  # delta empty: same
  delta_sel "$repo" --delta-base HEAD
  want="DELTA base=HEAD
CORE aai-c reason=core
SELECTED aai-y reason=companion:aai-c
SELECTED aai-z reason=companion:aai-y
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004: empty delta must select the core companions. got: $(payload_preview "$OUT")"
  # delta non-empty: path selection plus core companions
  local s
  git -C "$repo" add -A || log_fail "TEST-004: add failed"
  git -C "$repo" commit -q -m map || log_fail "TEST-004: commit failed"
  s="$(git -C "$repo" rev-parse HEAD)" || log_fail "TEST-004: rev-parse failed"
  delta_commit "$repo" idx docs/INDEX.md
  delta_sel "$repo" --delta-base "$s"
  want="DELTA base=$s
CORE aai-c reason=core
SELECTED aai-x reason=docs/INDEX.md
SELECTED aai-y reason=companion:aai-c
SELECTED aai-z reason=companion:aai-y
DROPPED 0"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004: delta must carry companions. got: $(payload_preview "$OUT")"

  # the workflow's own SUITES extraction line, read from the real file
  local line
  line="$(sed -n '/SUITES="\$(echo "\$OUT"/{p;q;}' "$WORKFLOW_FILE")"
  [[ -n "$line" ]] || log_fail "TEST-004: SUITES extraction line not found in $WORKFLOW_FILE"
  OUT="$(node "$SELECTOR" --repo-root "$repo" --files-from /dev/null 2>&1)" || true
  eval "$line"
  [[ " $SUITES " == *" aai-y "* ]] || log_fail "TEST-004: whole-PR output must yield aai-y through the workflow line, got: $SUITES"
  delta_sel "$repo" --delta-base "$s"
  eval "$line"
  [[ " $SUITES " == *" aai-z "* && " $SUITES " == *" aai-x "* ]] || log_fail "TEST-004: delta output must yield aai-x and aai-z through the workflow line, got: $SUITES"

  # a map without companions: byte-identical to the frozen pre-change golden
  small_map "$TEST_DIR"
  run_sel "$TEST_DIR" src/alpha/x.js
  want="CORE aai-core-a reason=core
CORE aai-core-b reason=core
SELECTED aai-alpha reason=src/alpha/x.js
DROPPED 1"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004 golden 1 differs: $(payload_preview "$OUT")"
  run_sel "$TEST_DIR" src/alpha/shared.js src/beta/b.js
  want="CORE aai-core-a reason=core
CORE aai-core-b reason=core
SELECTED aai-alpha reason=src/alpha/shared.js
SELECTED aai-beta reason=src/alpha/shared.js
DROPPED 0"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004 golden 2 differs: $(payload_preview "$OUT")"
  run_sel "$TEST_DIR" foo.txt
  [[ "$OUT" == "FULL_RUN reason=unmapped path=foo.txt" ]] || log_fail "TEST-004 golden 3 differs: $(payload_preview "$OUT")"
  run_sel "$TEST_DIR" .aai/scripts/lib/x.mjs
  [[ "$OUT" == "FULL_RUN reason=shared-lib path=.aai/scripts/lib/x.mjs" ]] || log_fail "TEST-004 golden 4 differs: $(payload_preview "$OUT")"
  run_sel "$TEST_DIR"
  want="CORE aai-core-a reason=core
CORE aai-core-b reason=core
DROPPED 2"
  [[ "$OUT" == "$want" ]] || log_fail "TEST-004 golden 5 (empty diff) differs: $(payload_preview "$OUT")"
  log_pass "TEST-004: core companions on empty diff/delta, workflow line yields them, no-companion maps unchanged (TEST-004)"
}

test_1754_assert_companions_helper() {  # Spec-AC-04 / TEST-005
  log_info "Test: assert_companions returns 0 for declared/core companions and 1 naming the MISSING one (TEST-005)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local lib="$SCRIPT_DIR/lib/companion-assert.sh" out rc
  [[ -f "$lib" ]] || log_fail "TEST-005: helper missing: $lib"
  # shellcheck source=lib/companion-assert.sh
  . "$lib"
  write_map "$TEST_DIR" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
  aai-x:
    companions:
      - aai-y
    globs:
      - src/x/**
  aai-y:
    globs:
      - src/y/**
  aai-w:
    globs:
      - src/w/**
YAML
  export COMPANION_ASSERT_ROOT="$TEST_DIR" SELECT_SUITES_SCRIPT="$SELECTOR"
  rc=0; out="$(assert_companions aai-x aai-y)" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-005: a declared companion must pass, rc=$rc: $out"
  assert_payload_contains "$out" "aai-y" "TEST-005: success must name the companions: $out"
  rc=0; out="$(assert_companions aai-x aai-c)" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-005: a core companion must pass through the CORE line, rc=$rc: $out"
  rc=0; out="$(assert_companions aai-w aai-y)" || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-005: an absent edge must return 1, rc=$rc: $out"
  assert_payload_contains "$out" "MISSING companion aai-y for aai-w" "TEST-005: the miss must be named: $out"
  # partial: one present, one absent -> only the absent one is named
  rc=0; out="$(assert_companions aai-x aai-y aai-w)" || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-005: a partial miss must return 1, rc=$rc: $out"
  assert_payload_contains "$out" "MISSING companion aai-w for aai-x" "TEST-005: partial miss names aai-w: $out"
  assert_payload_not_contains "$out" "MISSING companion aai-y" "TEST-005: the present companion must not be reported: $out"
  # a malformed map (FULL_RUN) selects nothing by name and must fail
  write_map "$TEST_DIR" <<'YAML'
core:
  - aai-c

suites:
  aai-c:
    globs:
      - docs/c.md
YAML
  rc=0; out="$(assert_companions aai-x aai-y)" || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-005: an outer suite the map does not cover (FULL_RUN) must fail, rc=$rc: $out"
  unset COMPANION_ASSERT_ROOT SELECT_SUITES_SCRIPT
  log_pass "TEST-005: assert_companions passes declared/core companions, fails naming the missing one (TEST-005)"
}

test_1755_real_map_declares_the_pinned_companion_edges() {  # Spec-AC-11 / TEST-032
  log_info "Test: the real suite-map.yaml declares exactly the pinned D3 companion edges, none to a core suite, and each row selects its whole closure (TEST-032)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-select.XXXXXX")"
  local pin="$TEST_DIR/pinned.txt" got="$TEST_DIR/got.txt" rc=0
  cat > "$pin" <<'PIN'
aai-advisory-skills aai-prompt-diet
aai-ceremony-levels aai-orchestration-dispatch
aai-ceremony-levels aai-prompt-diet
aai-constitution aai-prompt-diet
aai-debug-gate aai-prompt-diet
aai-delta-stage1 aai-docs-canon
aai-delta-stage2 aai-delta-stage1
aai-delta-stage3 aai-delta-stage1
aai-delta-stage3 aai-delta-stage2
aai-deslop aai-advisory-skills
aai-deslop aai-prompt-diet
aai-doc-number-reservation aai-doc-numbering
aai-doctor aai-layer-profiles
aai-doctor aai-suite-select
aai-feedback-upsert aai-layer-profiles
aai-feedback-upsert aai-prompt-diet
aai-friction aai-layer-profiles
aai-friction-wiring aai-layer-profiles
aai-friction-wiring aai-prompt-diet
aai-git-ref-guard aai-prompt-diet
aai-hitl-propagation aai-orchestration-dispatch
aai-hitl-propagation aai-state
aai-hooks-overlay aai-prompt-diet
aai-learned-append aai-friction-wiring
aai-learned-append aai-layer-profiles
aai-learned-append aai-prompt-diet
aai-ledger-merge aai-layer-profiles
aai-merge-policy aai-layer-profiles
aai-release aai-layer-profiles
aai-secrets-preflight aai-intake
aai-spec-lint aai-prompt-diet
aai-sync-seed aai-bootstrap
aai-sync-seed aai-hooks-overlay
aai-sync-seed aai-layer-drift
aai-sync-seed aai-layer-profiles
aai-tdd-evidence aai-tdd
PIN
  # The pin is the spec's D3 table (36 edges over 24 rows; a body with more
  # edges than the spec says is a measurement the spec must record, never
  # silent drift). The edges and the core list are read from the real map.
  node - "$PROJECT_ROOT" "$SELECTOR" "$got" <<'JS' || rc=$?
const fs = require('fs');
const cp = require('child_process');
const [root, selector, out] = process.argv.slice(2);
const lines = fs.readFileSync(root + '/tests/skills/suite-map.yaml', 'utf8').split('\n');
const core = new Set();
const edges = [];
const decl = {};
let section = '';
let row = null;
let inList = false;
for (const l of lines) {
  let m = l.match(/^(core|suites):\s*$/);
  if (m) { section = m[1]; row = null; inList = false; continue; }
  if (section === 'core' && (m = l.match(/^  - (\S+)/))) { core.add(m[1]); continue; }
  if (section !== 'suites') continue;
  if ((m = l.match(/^  (aai-[a-z0-9-]+):\s*$/))) { row = m[1]; inList = false; continue; }
  if (/^    companions:\s*$/.test(l)) { inList = true; continue; }
  if (inList && (m = l.match(/^      - (\S+)/))) { edges.push(row + ' ' + m[1]); (decl[row] = decl[row] || []).push(m[1]); continue; }
  inList = false;
}
const bad = edges.filter((e) => core.has(e.split(' ')[1]));
const closure = (r) => {
  const seen = new Set();
  const stack = [...(decl[r] || [])];
  while (stack.length) { const c = stack.pop(); if (seen.has(c)) continue; seen.add(c); stack.push(...(decl[c] || [])); }
  return [...seen];
};
const miss = [];
for (const r of Object.keys(decl)) {
  const sel = cp.execFileSync('node', [selector, '--files-from', '-', '--repo-root', root],
    { input: 'tests/skills/test-' + r + '.sh\n', encoding: 'utf8' });
  for (const c of closure(r)) {
    if (!core.has(c) && !sel.split('\n').some((x) => x.startsWith('SELECTED ' + c + ' '))) miss.push(r + ' -> ' + c);
  }
}
fs.writeFileSync(out, edges.sort().join('\n') + '\nROWS ' + Object.keys(decl).length + '\nCOREEDGES ' + bad.join(',') + '\nCLOSUREMISS ' + miss.join(',') + '\n');
JS
  [[ "$rc" -eq 0 ]] || log_fail "TEST-032 (plan row TEST-032): edge extraction failed (rc=$rc)"
  local want_edges got_edges
  want_edges="$(sort "$pin")"
  got_edges="$(sed '/^ROWS /,$d' "$got")"
  [[ "$got_edges" == "$want_edges" ]] || log_fail "TEST-032 (plan row TEST-032): the real map's companion edges differ from the pinned list. want: $(printf '%s' "$want_edges" | tr '\n' ';') -- got: $(printf '%s' "$got_edges" | tr '\n' ';')"
  [[ "$(wc -l < "$pin" | tr -d ' ')" == "36" ]] || log_fail "TEST-032 (plan row TEST-032): the pinned list must hold 36 edges"
  grep -qxF "ROWS 24" "$got" || log_fail "TEST-032 (plan row TEST-032): the edges must sit on 24 rows: $(grep '^ROWS' "$got")"
  grep -qxF "COREEDGES " "$got" || log_fail "TEST-032 (plan row TEST-032): an edge names a core suite: $(grep '^COREEDGES' "$got")"
  grep -qxF "CLOSUREMISS " "$got" || log_fail "TEST-032 (plan row TEST-032): a row's own test file does not select its whole closure: $(grep '^CLOSUREMISS' "$got")"
  log_pass "TEST-032: the real map declares exactly the 36 pinned edges on 24 rows, none to a core suite, each row selects its closure (TEST-032)"
}

test_1756_weights_reseeded_from_a_named_run() {  # Spec-AC-12 / TEST-035
  log_info "Test: suite-weights.tsv names its source run and head SHA, weighs learned-append at most 15 and delta-stage3 at most 30, and the balance bound holds (TEST-035)..."
  local f="$PROJECT_ROOT/tests/skills/suite-weights.tsv" header w
  [[ -f "$f" ]] || log_fail "TEST-035 (plan row TEST-035): missing $f"
  header="$(sed -n '/^#/p' "$f")"
  # the header names a CI run id (8+ digits after 'run') or the local-sweep fallback
  if [[ ! "$header" =~ run[[:space:]]+[0-9]{8,} && ! "$header" == *"local sweep"* ]]; then
    log_fail "TEST-035 (plan row TEST-035): the weights header must name a run id or the local-sweep fallback"
  fi
  [[ "$header" =~ [0-9a-f]{40} ]] || log_fail "TEST-035 (plan row TEST-035): the weights header must name a 40-hex head SHA"
  w="$(awk -F'\t' '$1 == "aai-learned-append" {print $2}' "$f")"
  [[ "$w" =~ ^[0-9]+$ && "$w" -ge 1 && "$w" -le 15 ]] \
    || log_fail "TEST-035 (plan row TEST-035): aai-learned-append weight must be 1..15 after the nested runs left, got '$w'"
  w="$(awk -F'\t' '$1 == "aai-delta-stage3" {print $2}' "$f")"
  [[ "$w" =~ ^[0-9]+$ && "$w" -ge 1 && "$w" -le 30 ]] \
    || log_fail "TEST-035 (plan row TEST-035): aai-delta-stage3 weight must be 1..30 after the nested runs left, got '$w'"
  # the balance bound is TEST-1423's; running it here binds it to THESE weights
  test_1423_real_repo_balance_bound "$PROJECT_ROOT"
  log_pass "TEST-035: weights re-seeded from a named run (learned-append <= 15, delta-stage3 <= 30), balance bound holds (TEST-035)"
}

# --- slowest-suite-hot-spots D6 (plan rows TEST-005, 009, 015, 016, 017) ------
# The committed weights are measured CI seconds, so a weight bound is the CI
# half of a hot-spot reduction (the local half is timed by hand).
_hot_spot_weight() {  # $1 suite name -> the committed weight, or empty
  awk -F'\t' -v s="$1" '$1 == s {print $2}' "$PROJECT_ROOT/tests/skills/suite-weights.tsv"
}

_assert_weight_at_most() {  # $1 suite $2 bound $3 plan row id
  local w
  w="$(_hot_spot_weight "$1")"
  [[ "$w" =~ ^[0-9]+$ ]] || log_fail "$3: no numeric weight for $1 in suite-weights.tsv (got '$w')"
  [[ "$w" -le "$2" ]] || log_fail "$3: the committed CI weight of $1 is $w, the bound is $2"
}

test_1757_hygiene_pack_weight() {  # Spec-AC-03 / TEST-005
  log_info "Test: the committed CI weight of aai-hygiene-pack is at most 65 (TEST-005)..."
  _assert_weight_at_most aai-hygiene-pack 65 "TEST-005"
  log_pass "TEST-005: aai-hygiene-pack weighs at most 65"
}

test_1758_sync_seed_weight() {  # Spec-AC-06 / TEST-009
  log_info "Test: the committed CI weight of aai-sync-seed is at most 118 (TEST-009)..."
  _assert_weight_at_most aai-sync-seed 118 "TEST-009"
  log_pass "TEST-009: aai-sync-seed weighs at most 118"
}

test_1759_run_tests_weight() {  # Spec-AC-09 / TEST-015
  log_info "Test: the committed CI weight of aai-run-tests is at most 92 (TEST-015)..."
  _assert_weight_at_most aai-run-tests 92 "TEST-015"
  log_pass "TEST-015: aai-run-tests weighs at most 92"
}

test_1760_weights_provenance() {  # Spec-AC-10 / TEST-016
  log_info "Test: the weights header names a re-seed run other than 37930287459, four job ids and a head SHA; the balance bound holds (TEST-016)..."
  local f="$PROJECT_ROOT/tests/skills/suite-weights.tsv" header run jobs
  [[ -f "$f" ]] || log_fail "TEST-016: missing $f"
  header="$(sed -n '/^#/p' "$f")"
  run="$(printf '%s\n' "$header" | sed -n -E 's/^# Actions run ([0-9]{8,}).*/\1/p' | head -n 1)"
  [[ -n "$run" ]] || log_fail "TEST-016: the header must carry a line starting '# Actions run <id>'"
  [[ "$run" != "37930287459" ]] || log_fail "TEST-016: the header still names the previous seed run 37930287459"
  jobs="$(printf '%s\n' "$header" | sed -n -E 's/^# legs (.*)/\1/p' | head -n 1 | /usr/bin/grep -oE '[0-9]{9,}' | sort -u | wc -l | tr -d ' ')"
  [[ "$jobs" == "4" ]] || log_fail "TEST-016: the header must name four distinct leg job ids on its '# legs' line, found $jobs"
  [[ "$header" =~ [0-9a-f]{40} ]] || log_fail "TEST-016: the header must name a 40-hex head SHA"
  test_1423_real_repo_balance_bound "$PROJECT_ROOT"
  log_pass "TEST-016: weights re-seeded from run $run, four job ids and a head SHA named, balance bound holds"
}

test_1761_leg_walls_bound() {  # Spec-AC-11 / TEST-017
  log_info "Test: the weights header's Leg walls line has four positive integers and the largest is at most 1.25 times their mean (TEST-017)..."
  local f="$PROJECT_ROOT/tests/skills/suite-weights.tsv" line nums count
  line="$(/usr/bin/grep -E '^# Leg walls' "$f" | head -n 1 || true)"
  [[ -n "$line" ]] || log_fail "TEST-017: the weights header has no '# Leg walls' line"
  if [[ "$line" == *"pending"* ]]; then
    # Pending marker, honest and loud: the second CI run has not measured yet.
    log_info "TEST-017: Leg walls pending the second full-mode CI run (Spec-AC-11 stays implementing)"
    return 0
  fi
  [[ "$line" =~ ^#\ Leg\ walls\ \(run\ [0-9]{8,}\):\ ([0-9]+)\ ([0-9]+)\ ([0-9]+)\ ([0-9]+)$ ]] \
    || log_fail "TEST-017: the Leg walls line must read '# Leg walls (run <id>): w1 w2 w3 w4', got: $line"
  nums="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
  count="$(printf '%s\n' $nums | awk '$1 > 0' | wc -l | tr -d ' ')"
  [[ "$count" == "4" ]] || log_fail "TEST-017: all four leg walls must be positive integers: $nums"
  printf '%s\n' $nums | awk '{s += $1; if ($1 > m) m = $1} END {exit !(m * 4 <= s * 1.25)}' \
    || log_fail "TEST-017: the slowest leg wall exceeds 1.25 times the mean of the four ($nums)"
  log_pass "TEST-017: the slowest leg is within 1.25 times the mean ($nums)"
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
  test_021_docs_or_ledger_only_manifests_never_full_run
  test_022_ceremony_leftovers_never_full_run
  test_430_role_common_selects_aai_state
  test_1420_real_repo_shard_completeness
  test_1421_weight_orphan_and_completeness
  test_1422_deterministic_tie_break_golden
  test_1423_real_repo_balance_bound
  test_1424_shards_never_increase_in_weight
  test_1425_unweighted_gets_max_known_first_in_shard
  test_1426_invalid_shard_count_fallback
  test_1427_malformed_weights_ignored_whole_file
  test_1428_no_suites_fallback
  test_1429_default_mode_byte_identical_negative_control
  test_1430_check_complete_plan_prints_ids
  test_1431_check_missing_and_extra_suite
  test_1432_check_duplicate_assignment
  test_1433_fallback_plan_check_and_extract_all
  test_1434_extract_exact_shard_and_unknown_id
  test_1435_real_repo_seam_selector_to_checker
  test_1436_workflow_shard_step_and_matrix_pin
  test_1437_gate_unchanged_negative_control
  test_1438_leg_rechecks_before_extract
  test_1439_real_map_replay_new_paths
  test_1440_check_rejects_unresolvable_nested_suite
  test_1711_inert_paths_select_core_only
  test_1712_inert_precedence_and_byte_identity
  test_1713_real_map_inert_pinned_to_ignored_dirs
  test_1737_real_map_gitignore_full_and_guard_scripts_select
  test_1714_delta_selects_over_the_delta_only
  test_1715_delta_ineligible_cells
  test_1716_delta_ancestry_and_unknown_sha
  test_1727_pr434_last_push_replay
  test_1750_companion_is_selected_with_its_parent
  test_1751_companions_are_transitive_cycle_safe
  test_1752_malformed_companion_fails_open
  test_1753_core_companions_empty_diff_golden_and_workflow_line
  test_1754_assert_companions_helper
  test_1755_real_map_declares_the_pinned_companion_edges
  test_1756_weights_reseeded_from_a_named_run
  test_1757_hygiene_pack_weight
  test_1758_sync_seed_weight
  test_1759_run_tests_weight
  test_1760_weights_provenance
  test_1761_leg_walls_bound
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Single-function invocation mode (mutation-run.mjs's positional-dispatch
  # convention, isPositionalDispatchSuite): a function name as $1 runs just
  # that test, so mutation-run.mjs can isolate one TEST-xxx instead of
  # re-running the whole file; no args preserves the full-suite default.
  if [[ -n "${1:-}" ]]; then
    "$1"
  else
    main "$@"
  fi
fi
