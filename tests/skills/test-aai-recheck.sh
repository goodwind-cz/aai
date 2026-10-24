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
# TEST-2801..2839 (docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md): the judged round is the
# check_binding block of STATE written by state.mjs bind-check; every fixture builds it through that
# real CLI.
#
# SELF-HOSTING: the node cases set AAI_RECHECK_MODE=delta explicitly in every child process
# (TEST-2738 and the default env of TEST-2820 unset it), so the suite answers the same under
# AAI_RECHECK_MODE=full.
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
  log_pass "TEST-2731: AAI_RECHECK_MODE unset, empty, blank and delta enable the mode; full and any other value do not"
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

test_2738_default_is_delta() {
  run_recheck_node_tests TEST-2738
  log_pass "TEST-2738: the default is delta: the variable unset gives delta on an eligible tree, AAI_RECHECK_MODE=full gives recheck_disabled"
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
  log_pass "TEST-2742: an uncommitted stamp rewrite gives full, because eligibility reads the STATE binding and the stamps are telemetry"
}

test_2743_merge_in_range_refused() {
  run_recheck_node_tests TEST-2743
  log_pass "TEST-2743: a merge commit in the range refuses delta"
}

test_2744_whitespace_role_refused() {
  run_recheck_node_tests TEST-2744
  log_pass "TEST-2744: a whitespace-only AAI_ROLE counts as set"
}

test_2745_delta_identity_covers_sent_layers() {
  run_recheck_node_tests TEST-2745
  log_pass "TEST-2745: the delta prompt_hash covers the re-check prompt and the contract, never LEARNED.md"
}

test_2746_needs_full_recheck_escalates() {
  run_recheck_node_tests TEST-2746
  log_pass "TEST-2746: needs_full_recheck re-dispatches the full role and is no human stop"
}

test_2801_bind_on_dispatch() {
  run_recheck_node_tests TEST-2801
  log_pass "TEST-2801: bind-check --on dispatch records ref, checkout, the pending head and the report set"
}

test_2803_bind_on_verdict() {
  run_recheck_node_tests TEST-2803
  log_pass "TEST-2803: bind-check --on verdict writes head, status, reports, digests and the marker"
}

test_2804_bind_refusals() {
  run_recheck_node_tests TEST-2804
  log_pass "TEST-2804: bind-check --on verdict writes nothing without a dispatch, a verdict or a new report"
}

test_2805_eligibility_reads_binding() {
  run_recheck_node_tests TEST-2805
  log_pass "TEST-2805: each failing binding comparison gives full with exactly its reason"
}

test_2806_stamps_not_read() {
  run_recheck_node_tests TEST-2806
  log_pass "TEST-2806: forged check_ stamps change nothing and give first_round without a binding"
}

test_2807_uncommitted_and_amend() {
  run_recheck_node_tests TEST-2807
  log_pass "TEST-2807: D5 shapes 1 and 2 give full"
}

test_2808_rebase_and_squash() {
  run_recheck_node_tests TEST-2808
  log_pass "TEST-2808: D5 shapes 3 and 4 give full"
}

test_2809_rewrite_before_base() {
  run_recheck_node_tests TEST-2809
  log_pass "TEST-2809: D5 shape 5 gives full"
}

test_2810_git_replace() {
  run_recheck_node_tests TEST-2810
  log_pass "TEST-2810: D5 shape 6, git replace in every form, gives full"
}

test_2811_forged_append() {
  run_recheck_node_tests TEST-2811
  log_pass "TEST-2811: D5 shapes 7 and 8 give production_path or first_round"
}

test_2812_merge_ours_and_rerecord() {
  run_recheck_node_tests TEST-2812
  log_pass "TEST-2812: D5 shapes 9 and 10 give full"
}

test_2813_bound_report_flip() {
  run_recheck_node_tests TEST-2813
  log_pass "TEST-2813: D5 shape 11, a flipped bound report, gives full"
}

test_2829_fenced_marker() {
  run_recheck_node_tests TEST-2829
  log_pass "TEST-2829: markerOfText counts a marker line only at column 0 outside every fence"
}

test_2830_fenced_marker_seam() {
  run_recheck_node_tests TEST-2830
  log_pass "TEST-2830: a fenced-only false marker gives full through bind-check and recheckMode"
}

test_2831_specpath_repoint() {
  run_recheck_node_tests TEST-2831
  log_pass "TEST-2831: a spec_path re-point inside the same block, in the work item or the focus, keeps the recorded ceremony level (TEST-2836 covers a replaced block)"
}

test_2802_bind_refused_for_subagent() {
  run_recheck_node_tests TEST-2802
  log_pass "TEST-2802: bind-check is refused under any AAI_ROLE, a returned bind-check command is refused, a subagent tick leaves the block alone"
}

test_2814_handoff_and_copy() {
  run_recheck_node_tests TEST-2814
  log_pass "TEST-2814: the handoff does not carry the binding, a hand copy names another checkout, an archived copy is never read"
}

test_2815_flush_reset_and_check_state() {
  run_recheck_node_tests TEST-2815
  log_pass "TEST-2815: partial flush clears, full flush removes, reset-block and check-state leave the block alone"
}

test_2816_end_to_end_binding() {
  run_recheck_node_tests TEST-2816
  log_pass "TEST-2816: real ticks bind both roles and the next dispatch of each is delta from the bound head"
}

test_2817_escalation_knows_mode() {
  run_recheck_node_tests TEST-2817
  log_pass "TEST-2817: RECHECK-ESCALATION only for a delta round; the prompts say an escalated round merges nothing"
}

test_2818_comments_state_comparison() {
  run_recheck_node_tests TEST-2818
  log_pass "TEST-2818: the ledger comment states the comparison it makes and the code names no guarantee"
}

test_2819_docs_state_comparison() {
  run_recheck_node_tests TEST-2819
  log_pass "TEST-2819: protocol, workflow and changelog name check_binding and bind-check and carry one Residual: line"
}

test_2822_profiles_classified() {
  run_recheck_node_tests TEST-2822
  log_pass "TEST-2822: PROFILES lists check-binding.mjs exactly once, in core"
}

test_2823_suite_map_selects() {
  run_recheck_node_tests TEST-2823
  log_pass "TEST-2823: the suite map selects aai-recheck for the files the scope touches"
}

test_2825_rfc_phase4_row() {
  run_recheck_node_tests TEST-2825
  log_pass "TEST-2825: the RFC-0017 phase 4 row links this slice and stays in progress"
}

test_2826_498_amendments_signed() {
  run_recheck_node_tests TEST-2826
  log_pass "TEST-2826: the #498 amendments are signed and their trackers are done"
}

test_2827_ride_stays_full() {
  run_recheck_node_tests TEST-2827
  log_pass "TEST-2827: ceremony_l3 on this ride own spec for both roles"
}

test_2828_spec0250_superseded() {
  run_recheck_node_tests TEST-2828
  log_pass "TEST-2828: SPEC-0250 points at this spec for the stamp residual and the amendment is recorded"
}

test_2832_specpath_recorded() {
  run_recheck_node_tests TEST-2832
  log_pass "TEST-2832: the spec path is recorded once and survives a verdict write, a later dispatch and a partial flush"
}

test_2820_default_on() {
  run_recheck_node_tests TEST-2820
  log_pass "TEST-2820: the default is on for unset, empty, blank and delta; full and any other value give recheck_disabled"
}

test_2821_default_on_docs() {
  run_recheck_node_tests TEST-2821
  log_pass "TEST-2821: the docs state the default as on with AAI_RECHECK_MODE=full as the opt-out"
}

test_2833_focus_alternation_sticky() {
  run_recheck_node_tests TEST-2833
  log_pass "TEST-2833: a focus switch away and back leaves the per-ref security record raised and the next test-only round full"
}

test_2834_worktree_move_sticky() {
  run_recheck_node_tests TEST-2834
  log_pass "TEST-2834: git worktree move replaces the block, not the per-ref record, and the next test-only round is full"
}

test_2835_handoff_sticky() {
  run_recheck_node_tests TEST-2835
  log_pass "TEST-2835: ride-handoff out copies the per-ref record into the worktree STATE"
}

test_2836_specpath_record() {
  run_recheck_node_tests TEST-2836
  log_pass "TEST-2836: a spec path re-pointed after a focus switch is added to the record, never replacing the L3 path"
}

test_2837_record_kept_by_flush_and_reset() {
  run_recheck_node_tests TEST-2837
  log_pass "TEST-2837: a flush and reset-block leave the record, and an absent or unparseable record gives full"
}

test_2838_unparsable_item_kept() {
  run_recheck_node_tests TEST-2838
  log_pass "TEST-2838: a bind for another ref keeps an unparsable record item byte for byte and the ref stays full"
}

test_2839_duplicate_items_merged() {
  run_recheck_node_tests TEST-2839
  log_pass "TEST-2839: a bind for another ref merges duplicated record items to the highest flag and the ref stays full"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-cheap-transitions-slice TEST-2701..2746, SPEC spec-recheck-verdict-binding TEST-2801..2839)"
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
  test_2738_default_is_delta
  test_2739_ledger_rewrite_refused
  test_2740_committed_rewrite_refused
  test_2741_stamps_refused_for_subagent
  test_2742_uncommitted_stamp_rewrite_residual
  test_2743_merge_in_range_refused
  test_2744_whitespace_role_refused
  test_2745_delta_identity_covers_sent_layers
  test_2746_needs_full_recheck_escalates
  test_2801_bind_on_dispatch
  test_2803_bind_on_verdict
  test_2804_bind_refusals
  test_2805_eligibility_reads_binding
  test_2806_stamps_not_read
  test_2807_uncommitted_and_amend
  test_2808_rebase_and_squash
  test_2809_rewrite_before_base
  test_2810_git_replace
  test_2811_forged_append
  test_2812_merge_ours_and_rerecord
  test_2813_bound_report_flip
  test_2829_fenced_marker
  test_2830_fenced_marker_seam
  test_2831_specpath_repoint
  test_2802_bind_refused_for_subagent
  test_2814_handoff_and_copy
  test_2815_flush_reset_and_check_state
  test_2816_end_to_end_binding
  test_2817_escalation_knows_mode
  test_2818_comments_state_comparison
  test_2819_docs_state_comparison
  test_2822_profiles_classified
  test_2823_suite_map_selects
  test_2825_rfc_phase4_row
  test_2826_498_amendments_signed
  test_2827_ride_stays_full
  test_2828_spec0250_superseded
  test_2832_specpath_recorded
  test_2833_focus_alternation_sticky
  test_2834_worktree_move_sticky
  test_2835_handoff_sticky
  test_2836_specpath_record
  test_2837_record_kept_by_flush_and_reset
  test_2838_unparsable_item_kept
  test_2839_duplicate_items_merged
  test_2820_default_on
  test_2821_default_on_docs
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi
fi
