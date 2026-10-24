#!/usr/bin/env bash
#
# Test: aai-recheck
# (docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, TEST-2701..2721 and TEST-2723..2744;
# TEST-2722 lives in test-aai-prompt-diet.sh)
#
# The delta re-check mode: .aai/scripts/lib/recheck.mjs decides eligibility,
# canon.mjs builds the slim payload, orchestration-dispatch.mjs carries the
# recheck field and stamps the two verdict events. Every function below runs alone
# under single-function dispatch: bash tests/skills/test-aai-recheck.sh <function>.
# The cases are node:test cases in tests/skills/lib/recheck.test.mjs; each builds
# its own temporary git repository, the real repository is only read.
#
# SELF-HOSTING: delta is opt-in, so the node cases set AAI_RECHECK_MODE=delta
# explicitly in every child process (TEST-2738 unsets it), so the suite answers the
# same under AAI_RECHECK_MODE=full.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-recheck"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECHECK_NODE_TEST="$PROJECT_ROOT/tests/skills/lib/recheck.test.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

# run_recheck_node_tests <TEST id>: the node:test cases whose name starts with the
# id must pass, and zero passing tests is a failure (a missing id is RED, never
# vacuously green).
run_recheck_node_tests() {
  local id="$1" out rc=0
  [[ -f "$RECHECK_NODE_TEST" ]] || log_fail "$id: tests/skills/lib/recheck.test.mjs does not exist"
  out="$(node --test --test-name-pattern "$id" "$RECHECK_NODE_TEST" 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test exited $rc"
  fi
  if [[ ! "$out" =~ pass\ [1-9] ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test reported zero passing tests for the pattern"
  fi
}

test_2701_baseline_table_matches_metrics() {
  run_recheck_node_tests TEST-2701
  log_pass "TEST-2701: the Measured baseline table equals the values recomputed from METRICS.jsonl"
}

test_2702_delta_applies() {
  run_recheck_node_tests TEST-2702
  log_pass "TEST-2702: an eligible fixture gets mode delta and the allowlist covers every ledger path"
}

test_2703_production_refused() {
  run_recheck_node_tests TEST-2703
  log_pass "TEST-2703: production paths refuse delta and are named"
}

test_2704_protected_refused() {
  run_recheck_node_tests TEST-2704
  log_pass "TEST-2704: a protected path refuses delta, an unreadable config refuses delta"
}

test_2705_security_refused() {
  run_recheck_node_tests TEST-2705
  log_pass "TEST-2705: a true, missing, doubled or unreadable security marker refuses delta"
}

test_2706_other_refusals() {
  run_recheck_node_tests TEST-2706
  log_pass "TEST-2706: first round, ceremony, ancestry, empty delta, forced and git refusals"
}

test_2707_dispatch_field() {
  run_recheck_node_tests TEST-2707
  log_pass "TEST-2707: the dispatch carries recheck equal to recheckMode, null elsewhere"
}

test_2708_independence_unchanged() {
  run_recheck_node_tests TEST-2708
  log_pass "TEST-2708: role, rule, tier, model, effort, independence and lane are mode-independent"
}

test_2709_prompt_hash_seam() {
  run_recheck_node_tests TEST-2709
  log_pass "TEST-2709: the delta prompt_hash equals canon --print-hash --recheck delta"
}

test_2710_event_schema() {
  run_recheck_node_tests TEST-2710
  log_pass "TEST-2710: append-event accepts and refuses the two check events as specified"
}

test_2711_tick_stamps() {
  run_recheck_node_tests TEST-2711
  log_pass "TEST-2711: --confirm ticks stamp check_dispatched and check_verdict once each"
}

test_2712_canon_delta_payload() {
  run_recheck_node_tests TEST-2712
  log_pass "TEST-2712: canon --recheck delta assembles contract, recheck and scope only"
}

test_2713_canon_refusal_and_identity() {
  run_recheck_node_tests TEST-2713
  log_pass "TEST-2713: canon refuses an ineligible tree with exit 11; full builds equal the base canon"
}

test_2714_end_to_end() {
  run_recheck_node_tests TEST-2714
  log_pass "TEST-2714: real ticks, state.mjs writes and canon agree through a test-only then a production delta"
}

test_2715_measure_ratio() {
  run_recheck_node_tests TEST-2715
  log_pass "TEST-2715: recheck-measure prints delta bytes at most 0.40 of full bytes"
}

test_2716_rfc_phase4_row() {
  run_recheck_node_tests TEST-2716
  log_pass "TEST-2716: the RFC-0017 phase 4 row records the byte pairs"
}

test_2717_ride_stays_full() {
  run_recheck_node_tests TEST-2717
  log_pass "TEST-2717: this ride's own spec yields ceremony_l3"
}

test_2718_prompts() {
  run_recheck_node_tests TEST-2718
  log_pass "TEST-2718: the delta prompt and the wired prompts carry the required literals"
}

test_2719_protocol_and_workflow() {
  run_recheck_node_tests TEST-2719
  log_pass "TEST-2719: protocol and workflow describe the delta re-check"
}

test_2720_profiles_classified() {
  run_recheck_node_tests TEST-2720
  log_pass "TEST-2720: PROFILES lists the new files once each, in core"
}

test_2721_suite_map_selects() {
  run_recheck_node_tests TEST-2721
  log_pass "TEST-2721: the suite map selects aai-recheck for each new file"
}

test_2723_497_amendments_signed() {
  run_recheck_node_tests TEST-2723
  log_pass "TEST-2723: the six #497 amendments are signed and the follow-up is done"
}

test_2724_earliest_unjudged_head() {
  run_recheck_node_tests TEST-2724
  log_pass "TEST-2724: the verdict base is the earliest unjudged dispatch head; an ambiguous base gives no delta"
}

test_2725_orchestration_ref_wiring() {
  run_recheck_node_tests TEST-2725
  log_pass "TEST-2725: the documented canon command engages delta with the dispatch ref_id; a refusal keeps the full identity"
}

test_2726_rename_refused() {
  run_recheck_node_tests TEST-2726
  log_pass "TEST-2726: a rename out of a production path refuses delta"
}

test_2727_delete_refused() {
  run_recheck_node_tests TEST-2727
  log_pass "TEST-2727: a deleted production file refuses delta"
}

test_2728_delta_cannot_lower_level() {
  run_recheck_node_tests TEST-2728
  log_pass "TEST-2728: the delta cannot lower the ceremony level that decides its own eligibility"
}

test_2729_prior_reports_from_base() {
  run_recheck_node_tests TEST-2729
  log_pass "TEST-2729: prior-report markers come from the base commit and a changed prior report refuses"
}

test_2730_tests_gate_inputs_production() {
  run_recheck_node_tests TEST-2730
  log_pass "TEST-2730: gate inputs under tests/ are production, only test code is not"
}

test_2731_mode_switch_fails_closed() {
  run_recheck_node_tests TEST-2731
  log_pass "TEST-2731: AAI_RECHECK_MODE enables delta only when it normalises to delta"
}

test_2732_inherited_role_names() {
  run_recheck_node_tests TEST-2732
  log_pass "TEST-2732: an inherited property name is an unknown role, not a crash"
}

test_2733_delta_payload_contracts() {
  run_recheck_node_tests TEST-2733
  log_pass "TEST-2733: the delta payload carries the output contracts and the scope names the spec"
}

test_2734_stamped_security_marker() {
  run_recheck_node_tests TEST-2734
  log_pass "TEST-2734: the security marker is stamped at verdict time; a flipped report stays full"
}

test_2735_stamp_without_marker_and_sticky() {
  run_recheck_node_tests TEST-2735
  log_pass "TEST-2735: a stamp without a marker is absent and a true stamp keeps the ride full"
}

test_2736_tick_records_marker() {
  run_recheck_node_tests TEST-2736
  log_pass "TEST-2736: the real tick records the marker in the stamp and append-event validates it"
}

test_2737_capture_sites_fallback() {
  run_recheck_node_tests TEST-2737
  log_pass "TEST-2737: every append-run capture site names the recheck.fallback clause"
}

test_2738_default_is_full() {
  run_recheck_node_tests TEST-2738
  log_pass "TEST-2738: the variable unset gives full with recheck_disabled on an eligible tree"
}

test_2739_ledger_rewrite_refused() {
  run_recheck_node_tests TEST-2739
  log_pass "TEST-2739: an in-place rewrite of an earlier stamp refuses delta"
}

test_2740_committed_rewrite_refused() {
  run_recheck_node_tests TEST-2740
  log_pass "TEST-2740: a committed non-append edit of the ledger in the range refuses delta"
}

test_2741_stamps_refused_for_subagent() {
  run_recheck_node_tests TEST-2741
  log_pass "TEST-2741: append-event refuses check stamps when AAI_ROLE is set"
}

test_2742_uncommitted_stamp_rewrite_residual() {
  run_recheck_node_tests TEST-2742
  log_pass "TEST-2742: the uncommitted-stamp rewrite is pinned as a known residual (delta under opt-in, full by default)"
}

test_2743_merge_in_range_refused() {
  run_recheck_node_tests TEST-2743
  log_pass "TEST-2743: a merge commit in the range refuses delta"
}

test_2744_whitespace_role_refused() {
  run_recheck_node_tests TEST-2744
  log_pass "TEST-2744: a whitespace-only AAI_ROLE counts as set"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-cheap-transitions-slice TEST-2701..2744)"
  check_deps
  test_2701_baseline_table_matches_metrics
  test_2702_delta_applies
  test_2703_production_refused
  test_2704_protected_refused
  test_2705_security_refused
  test_2706_other_refusals
  test_2707_dispatch_field
  test_2708_independence_unchanged
  test_2709_prompt_hash_seam
  test_2710_event_schema
  test_2711_tick_stamps
  test_2712_canon_delta_payload
  test_2713_canon_refusal_and_identity
  test_2714_end_to_end
  test_2715_measure_ratio
  test_2716_rfc_phase4_row
  test_2717_ride_stays_full
  test_2718_prompts
  test_2719_protocol_and_workflow
  test_2720_profiles_classified
  test_2721_suite_map_selects
  test_2723_497_amendments_signed
  test_2724_earliest_unjudged_head
  test_2725_orchestration_ref_wiring
  test_2726_rename_refused
  test_2727_delete_refused
  test_2728_delta_cannot_lower_level
  test_2729_prior_reports_from_base
  test_2730_tests_gate_inputs_production
  test_2731_mode_switch_fails_closed
  test_2732_inherited_role_names
  test_2733_delta_payload_contracts
  test_2734_stamped_security_marker
  test_2735_stamp_without_marker_and_sticky
  test_2736_tick_records_marker
  test_2737_capture_sites_fallback
  test_2738_default_is_full
  test_2739_ledger_rewrite_refused
  test_2740_committed_rewrite_refused
  test_2741_stamps_refused_for_subagent
  test_2742_uncommitted_stamp_rewrite_residual
  test_2743_merge_in_range_refused
  test_2744_whitespace_role_refused
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
