#!/usr/bin/env bash
#
# Test: ride-handoff.mjs (spec-ride-state-handoff-to-worktree).
#
# TEST-001..TEST-010 run as node:test cases in tests/skills/lib/ride-handoff.test.mjs
# (each selected by its TEST id prefix, so mutation-run.mjs can target one row);
# TEST-012 pins the prompt wiring, TEST-014 the scope companions.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-ride-handoff"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/ride-handoff.test.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

# node_cases <TEST-id>: run the node:test cases whose name starts with the id.
# A pattern that matches nothing would pass vacuously, so the TAP tally must
# show at least one passing case and no failing one.
node_cases() {
  local id="$1" out="" rc=0 passed failed
  out="$(env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern="^$id " "$NODE_TEST" 2>&1)" || rc=$?
  passed="$(printf '%s\n' "$out" | sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p')"
  failed="$(printf '%s\n' "$out" | sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p')"
  if [[ "$rc" -ne 0 || "${failed:-1}" != 0 || "${passed:-0}" -lt 1 ]]; then
    printf '%s\n' "$out" | sed -n '1,60p' >&2
    log_fail "$id node cases failed (rc=$rc pass=${passed:-?} fail=${failed:-?})"
  fi
  log_pass "$id ($passed node case(s))"
}

test_000_node_file_runs_whole() {
  local rc=0
  env -u AAI_ROLE node --test "$NODE_TEST" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-000 node --test tests/skills/lib/ride-handoff.test.mjs exited $rc"
  log_pass "TEST-000 whole node:test file"
}

test_001_out_partition() { node_cases TEST-001; }
test_002_origin_side() { node_cases TEST-002; }
test_003_run_conservation() { node_cases TEST-003; }
test_004_check_state_and_dispatcher() { node_cases TEST-004; }
test_005_flush_names_only_the_ride() { node_cases TEST-005; }
test_006_draft_carry() { node_cases TEST-006; }
test_007_refusals_and_guard() { node_cases TEST-007; }
test_008_crash_and_resume() { node_cases TEST-008; }
test_009_reconcile() { node_cases TEST-009; }
test_010_reconcile_refusals() { node_cases TEST-010; }

# TEST-012 / Spec-AC-12: the canon names the handoff, and never a whole-STATE copy.
test_012_prompt_wiring() {
  local wt="$PROJECT_ROOT/.aai/SKILL_WORKTREE.prompt.md" ship="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  local step4 bash_block ps_block ship_line
  step4="$(sed -n '/^4\. \*\*If the user chooses worktree\*\*/,/^5\. \*\*If the user chooses inline\*\*/p' "$wt")"
  [[ -n "$step4" ]] || log_fail "TEST-012 step 4 (If the user chooses worktree) not found in SKILL_WORKTREE"
  grep -qF 'ride-handoff.mjs out' <<<"$step4" || log_fail "TEST-012 SKILL_WORKTREE step 4 does not name ride-handoff.mjs out"
  bash_block="$(sed -n '/^   Bash, after `git worktree add` succeeds:/,/^   PowerShell, after `git worktree add` succeeds/p' "$wt")"
  ps_block="$(sed -n '/^   PowerShell, after `git worktree add` succeeds/,/^   This is an independent installed snapshot/p' "$wt")"
  [[ -n "$bash_block" && -n "$ps_block" ]] || log_fail "TEST-012 the Setup Worktree bash or PowerShell block was not found"
  grep -qF 'ride-handoff.mjs out' <<<"$bash_block" || log_fail "TEST-012 the SKILL_WORKTREE bash setup block does not name ride-handoff.mjs out"
  grep -qF 'ride-handoff.mjs out' <<<"$ps_block" || log_fail "TEST-012 the SKILL_WORKTREE PowerShell setup block does not name ride-handoff.mjs out"
  ship_line="$(grep -F 'ride-handoff.mjs out' "$ship" || true)"
  [[ -n "$ship_line" ]] || log_fail "TEST-012 SKILL_SHIP does not name ride-handoff.mjs out"
  grep -qF 'recommended' <<<"$ship_line" || log_fail "TEST-012 SKILL_SHIP names the handoff outside autopilot default 2 (recommended -> worktree)"
  # negative: no prompt instructs copying a whole STATE.yaml into a worktree
  local hits=""
  hits="$(grep -nE '(^|[^[:alnum:]_-])(cp|Copy-Item)[^|;&]*STATE\.yaml[^|;&]*(wt|worktree|\$WT|\$\{WT)' "$PROJECT_ROOT"/.aai/*.prompt.md || true)"
  [[ -z "$hits" ]] || log_fail "TEST-012 a prompt copies a whole STATE.yaml into a worktree: $hits"
  log_pass "TEST-012 prompt wiring"
}

# TEST-014 / Spec-AC-13: no protected path in the diff, a suite-map row, a selector replay.
test_014_scope_companions() {
  local protected changed p map_row sel files row ride_spec ride_status
  protected="$(awk '/^protected_paths_l3:/ {f=1; next} f && /^  - / {sub(/^  - /, ""); print; next} f {exit}' "$PROJECT_ROOT/docs/ai/docs-audit.yaml")"
  [[ -n "$protected" ]] || log_fail "TEST-014 no protected_paths_l3 entries read from docs/ai/docs-audit.yaml"
  # The "no protected path in the diff" half is a constraint of THIS ride (spec-cheap-transitions-slice
  # amendment, contract, --signoff none). Once SPEC-0244 is done a later ride may legitimately edit
  # a protected surface under its own L3 gates, so the diff check applies only while the ride is
  # open. The suite-map row and the selector replay below stay unconditional.
  ride_spec="$PROJECT_ROOT/docs/specs/SPEC-0244-spec-ride-state-handoff-to-worktree.md"
  ride_status=""
  if [[ -f "$ride_spec" ]]; then
    ride_status="$(awk '/^---[[:space:]]*$/ { n++; next } n == 1 && /^status:/ { print $2; exit } n >= 2 { exit }' "$ride_spec")"
  fi
  if [[ -f "$ride_spec" && "$ride_status" != "done" ]]; then
    # The base ref: origin/main first (a CI pull_request checkout has no local main), then main; none resolves -> fail closed.
    local cand base=""
    for cand in origin/main main; do
      if git -C "$PROJECT_ROOT" rev-parse -q --verify "$cand^{commit}" >/dev/null 2>&1; then base="$cand"; break; fi
    done
    [[ -n "$base" ]] || log_fail "TEST-014 neither origin/main nor main resolves; cannot read the diff"
    # committed range plus the not-yet-committed working tree, so the check bites before the commit too
    changed="$({ git -C "$PROJECT_ROOT" diff --name-only "$base"...HEAD; git -C "$PROJECT_ROOT" diff --name-only "$base"; git -C "$PROJECT_ROOT" ls-files -o --exclude-standard; } 2>/dev/null || true)"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if grep -qxF "$p" <<<"$changed"; then log_fail "TEST-014 the diff touches protected path $p"; fi
    done <<<"$protected"
  else
    log_info "TEST-014: protected-diff half RETIRED for a closed ride (SPEC-0244 status '${ride_status:-absent}')"
  fi
  map_row="$(grep -c '^  aai-ride-handoff:$' "$PROJECT_ROOT/tests/skills/suite-map.yaml" || true)"
  [[ "$map_row" == 1 ]] || log_fail "TEST-014 suite-map.yaml has $map_row rows for aai-ride-handoff, want 1"
  row="$(sed -n '/^  aai-ride-handoff:$/,/^$/p' "$PROJECT_ROOT/tests/skills/suite-map.yaml")"
  grep -qF 'tests/skills/test-aai-ride-handoff.sh' <<<"$row" || log_fail "TEST-014 the aai-ride-handoff row does not list its own suite file"
  files="$(mktemp "${TMPDIR:-/tmp}/aai-ride-handoff-files.XXXXXX")"
  printf '.aai/scripts/ride-handoff.mjs\n' > "$files"
  sel="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$files" --repo-root "$PROJECT_ROOT" 2>&1 || true)"
  rm -f "$files"
  grep -qF 'aai-ride-handoff' <<<"$sel" || log_fail "TEST-014 the selector replay for ride-handoff.mjs does not pick aai-ride-handoff: $sel"
  log_pass "TEST-014 scope companions"
}

main() {
  echo "Testing $TEST_NAME (spec-ride-state-handoff-to-worktree)"
  check_deps
  test_000_node_file_runs_whole
  test_001_out_partition
  test_002_origin_side
  test_003_run_conservation
  test_004_check_state_and_dispatcher
  test_005_flush_names_only_the_ride
  test_006_draft_carry
  test_007_refusals_and_guard
  test_008_crash_and_resume
  test_009_reconcile
  test_010_reconcile_refusals
  test_012_prompt_wiring
  test_014_scope_companions
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
