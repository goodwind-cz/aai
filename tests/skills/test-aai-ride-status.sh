#!/usr/bin/env bash
#
# Test: ride-status.mjs (spec-ride-status-and-resume).
#
# TEST-3144..TEST-3155, TEST-3159..TEST-3162 run as node:test cases in tests/skills/lib/ride-status.test.mjs
# (each selected by its TEST id prefix, so mutation-run.mjs can target one row);
# TEST-3156..TEST-3158 are shell-native rows; TEST-3159..TEST-3160 are node cases.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-ride-status"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/ride-status.test.mjs"

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

test_3144_status_text_six_lines() { node_cases TEST-3144; }
test_3145_status_json_keys() { node_cases TEST-3145; }
test_3146_no_focus() { node_cases TEST-3146; }
test_3147_no_write() { node_cases TEST-3147; }
test_3148_agrees_with_dispatcher() { node_cases TEST-3148; }
test_3149_blocker_kinds() { node_cases TEST-3149; }
test_3150_next_decision() { node_cases TEST-3150; }
test_3151_strategy_reuse() { node_cases TEST-3151; }
test_3152_probe_pushed() { node_cases TEST-3152; }
test_3153_probe_pr_open() { node_cases TEST-3153; }
test_3154_probe_reads_only() { node_cases TEST-3154; }
test_3155_probe_ledgers() { node_cases TEST-3155; }
test_3159_state_invalid_stops() { node_cases TEST-3159; }
test_3160_closed_ride_not_resumed() { node_cases TEST-3160; }
test_3161_resume_verdicts() { node_cases TEST-3161; }
test_3162_ship_resume_clauses() { node_cases TEST-3162; }

# test_3156: the three prompts name the script's real CLI form, in the stated order.
test_3156_prompt_wiring() {
  local ship="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  local pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  local loop="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
  local input status_at select_at step5 probe_at push_at pr_probe_line summary_at ride_at
  input="$(sed -n '/^INPUT$/,/^AUTOPILOT DEFAULTS/p' "$ship")"
  [[ "$input" == *'node .aai/scripts/ride-status.mjs --json'* ]] || log_fail "TEST-3156: SKILL_SHIP INPUT lacks ride-status.mjs --json"
  [[ "$input" == *'RUN step 2'* ]] || log_fail "TEST-3156: SKILL_SHIP INPUT does not name RUN step 2"
  status_at="${input%%ride-status.mjs --json*}"; select_at="${input%%ride-select.mjs show*}"
  [[ ${#status_at} -lt ${#select_at} ]] || log_fail "TEST-3156: SKILL_SHIP INPUT runs ride-select.mjs show before ride-status.mjs --json"
  step5="$(sed -n '/^5\. OPEN THE PULL REQUEST/,/^6\. MERGE CHECKPOINT/p' "$ship")"
  [[ "$step5" == *'ride-status.mjs probe'* ]] || log_fail "TEST-3156: SKILL_SHIP step 5 lacks ride-status.mjs probe"
  [[ "$step5" != *'If unattended chaining already opened'* ]] || log_fail "TEST-3156: SKILL_SHIP step 5 keeps the old unattended-chaining prose"
  step5="$(sed -n '/^5\. PLATFORM GATE + PUSH + PR:/,/^5b\./p' "$pr")"
  [[ -n "$step5" ]] || step5="$(sed -n '/^5\. PLATFORM GATE + PUSH + PR:/,$p' "$pr")"
  probe_at="${step5%%ride-status.mjs probe*}"; push_at="${step5%%git push -u origin*}"
  [[ "$step5" == *'ride-status.mjs probe'* && ${#probe_at} -lt ${#push_at} ]] || log_fail "TEST-3156: SKILL_PR step 5 probe does not precede the git push -u origin line"
  pr_probe_line="${step5#*ride-status.mjs probe}"; pr_probe_line="${pr_probe_line:0:300}"
  [[ "$pr_probe_line" == *'pushed: done'* && "$pr_probe_line" == *'pr_open: done'* ]] || log_fail "TEST-3156: SKILL_PR probe line does not name pushed and pr_open done"
  summary_at="$(sed -n '/^LOOP SUMMARY$/,$p' "$loop")"
  ride_at="${summary_at#*---}"; ride_at="${ride_at#*---}"; ride_at="${ride_at:0:200}"
  [[ "$ride_at" == *'node .aai/scripts/ride-status.mjs'* ]] || log_fail "TEST-3156: SKILL_LOOP does not name ride-status.mjs after the LOOP SUMMARY block"
  log_pass "TEST-3156 (SHIP INPUT and step 5, PR step 5, LOOP summary name ride-status.mjs)"
}

# test_3157: exactly one diet-ledger entry credits this change, within the 900 B cap.
test_3157_diet_ledger_entry() {
  local ledger="$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh"
  local n bytes line
  n="$(grep -c 'JUSTIFIED_ADDITIONS+=( "[0-9][0-9]* ride-status-and-resume ' "$ledger" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3157: want exactly one ride-status-and-resume ledger entry, found $n"
  line="$(grep 'JUSTIFIED_ADDITIONS+=( "[0-9][0-9]* ride-status-and-resume ' "$ledger")"
  bytes="${line#*\"}"; bytes="${bytes%% *}"
  [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -ge 1 && "$bytes" -le 900 ]] || log_fail "TEST-3157: ledger byte count '$bytes' is outside 1..900"
  log_pass "TEST-3157 (one ledger entry, $bytes B)"
}

# test_3158: PROFILES core row, suite selection through the real select-suites.mjs,
# no launcher pair, no write call, no shell option, line cap.
test_3158_profiles_selection_and_source_shape() {
  local src="$PROJECT_ROOT/.aai/scripts/ride-status.mjs"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
  local f out lines
  grep -qxF '  - .aai/scripts/ride-status.mjs' "$profiles" \
    || log_fail "TEST-3158: PROFILES.yaml lacks the ride-status.mjs core row"
  for f in .aai/scripts/ride-status.mjs .aai/SKILL_SHIP.prompt.md .aai/SKILL_PR.prompt.md .aai/SKILL_LOOP.prompt.md; do
    out="$(printf '%s\n' "$f" | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" \
      || log_fail "TEST-3158: select-suites.mjs failed for $f"
    [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-ride-status($|[[:space:]]) ]] \
      || log_fail "TEST-3158: $f does not select aai-ride-status (got: $(printf '%s' "$out" | tr '\n' ';'))"
  done
  [[ ! -e "$PROJECT_ROOT/.aai/scripts/ride-status.sh" && ! -e "$PROJECT_ROOT/.aai/scripts/ride-status.ps1" ]] \
    || log_fail "TEST-3158: a ride-status launcher exists"
  for f in writeFileSync appendFileSync renameSync mkdirSync rmSync unlinkSync copyFileSync; do
    if grep -qF "$f" "$src"; then log_fail "TEST-3158: ride-status.mjs holds $f"; fi
  done
  if grep -qE 'shell:[[:space:]]*true' "$src"; then log_fail "TEST-3158: ride-status.mjs sets shell: true"; fi
  lines="$(wc -l < "$src" | tr -d ' ')"
  [[ "$lines" -le 400 ]] || log_fail "TEST-3158: ride-status.mjs has $lines lines (cap 400)"
  log_pass "TEST-3158 (core row, selection, no launcher, no writes, $lines lines)"
}

main() {
  echo "Testing $TEST_NAME (spec-ride-status-and-resume)"
  check_deps
  test_3144_status_text_six_lines
  test_3145_status_json_keys
  test_3146_no_focus
  test_3147_no_write
  test_3148_agrees_with_dispatcher
  test_3149_blocker_kinds
  test_3150_next_decision
  test_3151_strategy_reuse
  test_3152_probe_pushed
  test_3153_probe_pr_open
  test_3154_probe_reads_only
  test_3155_probe_ledgers
  test_3156_prompt_wiring
  test_3157_diet_ledger_entry
  test_3158_profiles_selection_and_source_shape
  test_3159_state_invalid_stops
  test_3160_closed_ride_not_resumed
  test_3161_resume_verdicts
  test_3162_ship_resume_clauses
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
