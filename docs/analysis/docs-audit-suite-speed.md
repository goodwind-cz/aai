# Docs-audit suite speed

The always-on `aai-docs-audit` suite spent most of its time repeating work over the real corpus, not in fixture logic. This note records the per-function profile that showed it, the four levers applied, the reconciliation of every migrated assertion, and the paired before/after measurement. Production audit code is untouched.

## Cost profile

Baseline commit `34f0cbcad78fc851ed60972b1c527dcbc4c47779`. Planning sourced the suite in a scratch clone and called each of the 195 functions `main()` runs, in `main()` order, under a monotonic timer (profiler `profile.sh`, raw `prof1.tsv` and `prof3.tsv` under `docs/ai/tdd/docs-audit-suite-speed/planning/`). Pass 1 and Pass 2 are two clean passes on the same host (macOS arm64, 16 CPUs, Node 22.23.1, Bash 3.2.57, Git 2.54.0); the ordinary wrapper run took 115.2 s and 114.6 s. The Lever column uses A (shared live audit), B (shared index pair), C (sharded histmap oracle), N (moved to Node), `-` (untouched).

| Function | Pass 1 s | Pass 2 s | Lever |
|---|---|---|---|
| test_broken_refs_selector_isolates | 0.309 | 0.304 | - |
| check_deps | 0.005 | 0.005 | - |
| test_change0007_lint_body_node | 0.076 | 0.078 | - |
| setup_fixture | 0.201 | 0.197 | - |
| test_deterministic_index_no_clock_line | 3.666 | 3.494 | B |
| test_1351_live_corpus_near_miss_set_is_dispositioned | 1.512 | 1.580 | A |
| test_1348_near_miss_headline_carries_the_count | 1.669 | 1.798 | A |
| test_1349_verdict_names_the_unreadable_tables | 2.064 | 2.058 | A |
| test_1350_bare_ac_status_words_are_checked | 0.346 | 0.355 | - |
| test_report_only_without_config | 0.092 | 0.096 | - |
| test_strict_path_intake_gate | 0.058 | 0.062 | - |
| write_config | 0.007 | 0.008 | - |
| test_orphan_split | 0.109 | 0.127 | - |
| test_drift_verdicts | 0.030 | 0.033 | - |
| test_events_emission | 0.152 | 0.158 | - |
| test_quick_mode | 0.056 | 0.056 | - |
| test_index_sections_and_idempotence | 0.435 | 0.449 | - |
| test_compound_ids_and_frozen_markers | 0.243 | 0.257 | - |
| test_reviewby_literals | 0.386 | 0.393 | - |
| test_uncommitted_doc_not_punished | 0.156 | 0.155 | - |
| test_type_validation | 0.189 | 0.189 | - |
| test_orphan_suggested_id | 0.202 | 0.188 | - |
| test_classification_listing | 0.214 | 0.209 | - |
| test_reviewby_actor_method | 0.169 | 0.161 | - |
| test_events_parent_subref_boundary | 0.240 | 0.243 | - |
| test_plan_scan_mode | 0.171 | 0.172 | - |
| test_suggested_multi_ids | 0.209 | 0.223 | - |
| test_category_prefix_scope | 0.220 | 0.247 | - |
| test_index_legacy_autoskip | 0.655 | 0.668 | - |
| test_skill_prompt_modes | 0.012 | 0.015 | - |
| setup_closeout_fixture | 0.081 | 0.092 | - |
| test_closeout_candidate_flagged | 0.246 | 0.239 | N |
| test_closeout_spec_not_all_done | 0.233 | 0.225 | N |
| test_closeout_terminal_parent | 0.241 | 0.242 | N |
| test_closeout_read_only | 0.297 | 0.270 | - |
| test_closeout_no_false_positive | 0.266 | 0.236 | N |
| test_closeout_report_only_gate | 0.247 | 0.245 | - |
| test_closeout_reverse_only | 0.258 | 0.257 | N |
| test_closeout_forward_nonspec_not_flagged | 0.231 | 0.239 | N |
| test_closeout_display_id_match | 0.242 | 0.237 | N |
| test_closeout_rollout_guard | 0.231 | 0.230 | N |
| test_rollout_status_pipe_styles | 0.032 | 0.031 | N |
| setup_rollout_fixture | 0.047 | 0.044 | - |
| test_rollout_progress_partial | 0.201 | 0.216 | - |
| test_rollout_progress_summary_line | 0.184 | 0.192 | - |
| test_rollout_report_only | 0.385 | 0.381 | - |
| setup_spec0006_opendecision_fixture | 0.046 | 0.039 | - |
| test_spec0006_deferred_whole_doc_section | 1.233 | 1.200 | - |
| test_spec0006_zero_section_strict_fatal | 0.721 | 0.841 | - |
| test_spec0006_zero_section_degrade_report | 1.204 | 1.248 | - |
| test_spec0006_no_double_listing_idempotent | 1.840 | 1.823 | - |
| test_spec0006_close_policy_prose | 0.021 | 0.022 | - |
| test_spec0006_open_decision_guard | 0.154 | 0.157 | - |
| test_spec0006_no_regression_real_repo | 4.938 | 4.927 | A+B |
| test_change0166_closeout_is_clean_and_terminal | 0.097 | 0.101 | - |
| test_534_two_stale_halves_are_closed | 0.217 | 0.198 | - |
| test_issue0001_frontmatter_crlf_tolerance | 0.035 | 0.039 | - |
| test_issue0001_actable_crlf_tolerance | 0.036 | 0.035 | - |
| setup_indexarm_snapshots | 3.470 | 3.559 | B |
| test_indexarm_earlier_day_generation_is_green | 1.109 | 1.068 | - |
| test_issue0001_posix_paths_noop | 0.130 | 0.134 | - |
| test_indexarm_index_is_not_stale | 3.998 | 4.012 | - |
| test_indexarm_overdue_boundary_is_green | 0.651 | 0.671 | - |
| test_issue0001_crlf_corpus_buckets | 0.364 | 0.346 | - |
| test_issue0001_gitattributes | 0.013 | 0.013 | - |
| test_issue0001_legacy_ratio_guard | 0.526 | 0.503 | - |
| test_issue0001_no_regression_real_repo | 5.034 | 4.973 | A+B |
| test_issue0001_posix_helper | 0.034 | 0.034 | - |
| test_spec0010_committed_index_idempotent | 0.992 | 0.842 | - |
| test_spec0010_index_git_state_invariant | 0.458 | 0.458 | - |
| test_spec0010_audit_companion_gitignored | 0.653 | 0.684 | - |
| test_spec0010_ac_row_level_not_whole_doc | 0.259 | 0.227 | - |
| test_spec0010_ac_qualifier_normalized | 0.238 | 0.253 | - |
| test_spec0010_ac_genuine_invalid_flagged_both | 0.292 | 0.287 | - |
| test_spec0011_gate_missing_table | 0.095 | 0.084 | - |
| test_spec0011_gate_fail_conditions | 0.163 | 0.166 | - |
| test_spec0011_gate_pass_and_unknown | 0.140 | 0.138 | - |
| test_spec0011_nearmiss_evidence_column | 0.115 | 0.115 | - |
| test_spec0011_nearmiss_both_surfaces | 0.328 | 0.333 | - |
| test_idxviolations_terminal_exemption | 0.502 | 0.509 | - |
| test_spec0011_review_claim_unbacked | 0.112 | 0.109 | - |
| test_spec0011_review_claim_backed | 0.195 | 0.185 | - |
| test_spec0011_event_types | 0.186 | 0.184 | - |
| test_spec0011_missing_close_telemetry | 0.286 | 0.279 | - |
| test_spec0011_closeout_prompts_wired | 0.020 | 0.021 | - |
| test_spec0011_config_close_gate | 0.079 | 0.078 | - |
| test_spec0011_hook_close_gate | 1.727 | 1.666 | - |
| test_spec0011_hook_parity_grep | 0.025 | 0.029 | - |
| test_spec0011_read_only | 0.202 | 0.220 | - |
| test_spec0011_gate_honors_config_review_by_methods | 0.135 | 0.120 | - |
| test_spec0011_hook_gates_staged_not_worktree | 0.790 | 0.837 | - |
| test_spec0011_work_item_closed_requires_fields | 0.209 | 0.207 | - |
| test_spec0011_review_artifact_boundary | 0.154 | 0.162 | - |
| test_spec0011_regression | 5.035 | 4.892 | A+B |
| test_536_unparseable_ac_table_shape | 0.465 | 0.431 | - |
| test_582_status_vocabulary_scoped_to_spec_ac_col | 0.198 | 0.188 | - |
| test_537_shape_check_live_yield | 3.057 | 3.104 | A |
| test_538_duplicate_ac_id_multiplicity | 0.432 | 0.453 | - |
| test_554_index_tracked_only | 0.428 | 0.458 | - |
| test_576_tracked_but_vanished_is_skipped_not_crashed | 0.229 | 0.231 | - |
| test_581_stat_error_other_than_enoent_is_never_swallowed | 0.400 | 0.370 | - |
| test_559_posix_predicate_infra_exit | 0.073 | 0.063 | - |
| test_change0007_lint_stray_markup | 0.224 | 0.192 | - |
| test_change0007_lint_promotion_pair | 0.446 | 0.388 | - |
| test_change0007_lint_body_file_predicate | 0.135 | 0.143 | - |
| test_change0007_hook_body_lint | 1.176 | 1.495 | - |
| test_change0007_regression | 1.738 | 1.733 | A |
| test_change0007_hook_config_staged | 1.936 | 2.160 | - |
| test_change0007_hook_space_filename | 0.990 | 1.051 | - |
| test_index_continue_on_error | 1.919 | 1.945 | - |
| test_change0012_gate_slug_draft | 0.106 | 0.109 | - |
| test_change0012_draft_scanned_nonvacuous | 0.161 | 0.167 | - |
| test_change0012_gate_resolution_order | 0.120 | 0.119 | - |
| test_change0012_gate_ambiguous_id | 0.088 | 0.086 | - |
| test_change0012_allocation_durability | 0.241 | 0.237 | - |
| test_change0012_regression | 1.708 | 1.714 | A |
| test_l1gate_lean_gate_pass | 0.176 | 0.190 | - |
| test_l1gate_missing_justification | 0.081 | 0.084 | - |
| test_l1gate_done_lean_clean | 0.154 | 0.165 | - |
| test_l1gate_l2_regression | 0.204 | 0.212 | - |
| test_l1gate_garbage_level_fail_closed | 0.084 | 0.082 | - |
| test_l1gate_pipe_drop_reconciled | 0.202 | 0.191 | - |
| test_l1gate_done_drift_pipe_drop | 0.163 | 0.155 | - |
| test_gateac_canonical_pipe_drop_reconciled | 0.291 | 0.272 | - |
| test_gateac_lean_volunteering_full_table | 0.094 | 0.091 | - |
| test_gateac_done_drift_canonical_pipe_drop | 0.164 | 0.163 | - |
| test_gateac_issue330_crosscheck | 0.140 | 0.118 | - |
| test_delta3_provenance_drift | 0.350 | 0.345 | - |
| test_delta3_empty_canonical_control | 0.133 | 0.135 | - |
| test_change0027_delivery_commit_flags | 0.253 | 0.254 | - |
| test_change0027_intake_only_not_flagged | 0.238 | 0.244 | - |
| test_change0027_nondelivery_mentions_not_flagged | 0.309 | 0.293 | - |
| test_change0027_sibling_numbered_boundary | 0.271 | 0.280 | - |
| test_change0027_sibling_slug_boundary | 0.287 | 0.280 | - |
| test_change0027_ac_evidence_event_flags | 0.290 | 0.290 | - |
| test_change0027_ac_table_signal | 0.276 | 0.274 | - |
| test_change0027_digest_and_event | 0.234 | 0.248 | - |
| test_change0027_precedence_over_stale | 0.220 | 0.242 | - |
| test_change0027_frozen_draft_probe | 0.298 | 0.295 | - |
| test_change0027_ac_table_tdd_log_only_not_flagged | 0.253 | 0.261 | - |
| test_change0027_index_seam | 0.285 | 0.378 | - |
| test_change0027_quick_mode_skips_probe | 0.214 | 0.227 | - |
| test_change0027_doc_surfaces_mention_false_open | 0.010 | 0.010 | - |
| test_umbrella_marker_suppresses_visibly | 0.452 | 0.484 | - |
| test_docsaicanon_classes | 0.393 | 0.423 | - |
| test_docsaicanon_real_repo_clean | 0.337 | 0.335 | - |
| test_change0028_mixed_cell_git_hash_flags | 0.291 | 0.295 | - |
| test_change0028_mixed_cell_pr_ref_flags | 0.229 | 0.229 | - |
| test_change0028_mixed_cell_prose_not_flagged | 0.222 | 0.225 | - |
| test_change0028_mixed_cell_unresolvable_hash_not_flagged | 0.245 | 0.246 | - |
| test_change0028_spec0039_verbatim_replica_not_flagged | 0.234 | 0.224 | - |
| test_change0028_arm_b_fileid_ac_evidence_flags | 0.279 | 0.287 | - |
| test_change0028_arm_b_inflight_discriminator_guard | 0.332 | 0.306 | - |
| test_change0028_arm_c_work_item_closed_flags | 0.375 | 0.368 | - |
| test_change0028_real_repo_clean | 1.468 | 1.502 | A |
| test_change0028_userguide_mentions_work_item_closed | 0.008 | 0.009 | - |
| test_fometrics_flush_arm | 0.337 | 0.342 | - |
| test_fometrics_supersession | 2.721 | 2.690 | - |
| test_fometrics_supersession_delivery_arms | 0.402 | 0.352 | - |
| setup_dupid_fixture | 0.043 | 0.042 | - |
| test_spec0057_duplicate_id_flagged | 0.290 | 0.290 | - |
| test_spec0057_check_exit_code_unchanged | 0.274 | 0.260 | - |
| setup_dupid_clean_fixture | 0.042 | 0.052 | - |
| test_spec0057_no_false_positive | 0.207 | 0.216 | - |
| test_spec0057_real_repo_known_collisions | 3.005 | 3.070 | A |
| test_pdcm_product_family_repo_wide_clean | 0.297 | 0.290 | - |
| test_pdci_validation_gate_delegation | 0.029 | 0.033 | - |
| test_pdci_gate_characterization_temporal_gap | 0.094 | 0.086 | - |
| test_histmap_corpus_equivalence | 9.725 | 9.662 | C |
| test_histmap_one_git_call_per_audit | 0.506 | 0.536 | - |
| test_histmap_rename_needs_no_renames | 0.193 | 0.191 | - |
| test_histmap_no_history_yields_null | 0.433 | 0.431 | - |
| test_histmap_first_commit_date_still_exported | 0.095 | 0.098 | - |
| test_idmention_542_one_call_and_correct_dates | 0.430 | 0.442 | - |
| test_acflip_delivery_citation_flags | 0.271 | 0.299 | - |
| test_acflip_deferred_table_clean | 0.238 | 0.246 | - |
| test_acflip_close_end_state_clean | 0.524 | 0.513 | - |
| test_acflip_predicate_agrees_with_check | 0.972 | 0.925 | - |
| test_acflip_remediation_is_reachable | 0.321 | 0.326 | - |
| test_acflip_real_repo_clean | 5.222 | 5.050 | A+B |
| test_441_untracked_new_doc_passes_genuine_drift_still_fails | 0.490 | 0.550 | - |
| test_broken_refs_source_missing | 0.415 | 0.443 | - |
| test_broken_refs_both_clean_is_zero | 0.270 | 0.292 | - |
| test_broken_refs_ac_notes_still_counted | 0.239 | 0.249 | - |
| test_broken_refs_non_paths_ignored | 0.234 | 0.224 | - |
| test_broken_refs_dedup_per_file | 0.222 | 0.227 | - |
| test_broken_refs_one_signal | 0.266 | 0.297 | - |
| test_broken_refs_excluded_trees | 0.228 | 0.239 | - |
| test_broken_refs_closed_root_set | 0.210 | 0.233 | - |
| test_broken_refs_services_root | 0.230 | 0.239 | - |
| test_broken_refs_untracked_skipped | 0.191 | 0.191 | - |
| test_broken_refs_nongit_note | 0.120 | 0.129 | - |
| test_broken_refs_vanished_tracked_skipped | 0.236 | 0.232 | - |
| test_broken_refs_generator_companions_ignored | 0.238 | 0.232 | - |
| test_broken_refs_retired_draft_not_a_row | 0.237 | 0.240 | - |

Profiled total (pass 1): 113.8 s

Pass 2 sums to 114.4 s. Repeated real-corpus work, measured per launch, was: 14 full real-corpus audits (22.7 s, 3 distinct argument lists, byte-identical output within a run), 11 real-corpus index generations (19.8 s, five identical idempotence pairs plus one fresh snapshot), the serial per-file history oracle (10.2 s) and eight closeout groups that each re-launched the same `--path docs/closeout` audit (about 2 s together). Fixture-repo CLI launches (306, 32.9 s) and the rest of the shell and git work are unchanged by this scope.

## Levers

Each lever lists the functions the profile tags with its letter.

- A: `test_1351_live_corpus_near_miss_set_is_dispositioned`, `test_1348_near_miss_headline_carries_the_count`, `test_1349_verdict_names_the_unreadable_tables`, `test_spec0006_no_regression_real_repo`, `test_issue0001_no_regression_real_repo`, `test_spec0011_regression`, `test_537_shape_check_live_yield`, `test_change0007_regression`, `test_change0012_regression`, `test_change0028_real_repo_clean`, `test_spec0057_real_repo_known_collisions`, `test_acflip_real_repo_clean`
- B: `test_deterministic_index_no_clock_line`, `test_spec0006_no_regression_real_repo`, `setup_indexarm_snapshots`, `test_issue0001_no_regression_real_repo`, `test_spec0011_regression`, `test_acflip_real_repo_clean`
- C: `test_histmap_corpus_equivalence`
- N: `test_closeout_candidate_flagged`, `test_closeout_spec_not_all_done`, `test_closeout_terminal_parent`, `test_closeout_no_false_positive`, `test_closeout_reverse_only`, `test_closeout_forward_nonspec_not_flagged`, `test_closeout_display_id_match`, `test_closeout_rollout_guard`, `test_rollout_status_pipe_styles`

Lever A runs each distinct real-corpus audit argument list once per suite run (`live_audit` in `tests/skills/lib/docs-audit-live.sh`), keyed by the argument list plus a fingerprint of the root, HEAD and the two index files, and hands every consumer a byte-identical copy; `AAI_DOCS_AUDIT_LIVE_VERIFY=1` re-runs every hit and fails on a difference. Lever B generates the real index twice once per run (`live_index_pair`), snapshots both runs and restores `docs/INDEX.md` and the violations companion before any assertion; the three Generated-stripped idempotence checks, the acflip check, the no-clock-line check and the fresh snapshot read those snapshots. Lever C computes the per-file `firstCommitDate` oracle in `worker_threads` shards (up to 8) while still comparing every tracked document and keeping the wrong-date bite. Lever N moves the closeout logic groups to `node:test` over the exported `runAudit` (`tests/skills/lib/docs-audit-closeout.test.mjs`).

Defect fixed on the way: `test_deterministic_index_no_clock_line` used to leave the real `docs/INDEX.md` regenerated, so `setup_indexarm_snapshots` copied a freshly generated index as the committed one and `test_indexarm_index_is_not_stale` could not fail in `main()` order (Planning probe `stale-index-masking-probe.txt`). The pair restores before returning, and `test_2205_committed_index_staleness_survives` pins that a stale committed index still fails.

## Migration map

Nine Bash functions were removed. The Node file writes the complete 23 `setup_closeout_fixture` documents byte for byte and calls `runAudit(root, { quick: true, scopePath: 'docs/closeout' })` once; every positive control the Bash functions asserted is kept.

| Map | Removed Bash function | Preserved clauses and Node owner | Retained CLI owner |
|---|---|---|---|
| C1 | `test_closeout_candidate_flagged` | heading, `advance RFC-0010 to` and the row naming SPEC-0010: Node `C1` asserts RFC-0010 is a candidate, its specs include SPEC-0010 and `suggestedStep` starts `advance RFC-0010 to` | `test_closeout_report_only_gate` keeps the `### Closeout candidates: ` heading, `advance RFC-0010 to` and the RFC-0010 plus SPEC-0010 row |
| C2 | `test_closeout_spec_not_all_done` | RFC-0010 control flagged, RFC-0020 not: Node `C2` | none needed |
| C3 | `test_closeout_terminal_parent` | RFC-0010 control flagged, RFC-0030, RFC-0032, RFC-0034 not: Node `C3` | none needed |
| C4 | `test_closeout_no_false_positive` | RFC-0010 control flagged, RFC-0050, CHANGE-0050, RFC-0052 not: Node `C4` | none needed |
| C5 | `test_closeout_reverse_only` | control, RFC-0060 flagged and naming SPEC-0060: Node `C5` | `test_closeout_report_only_gate` renders the RFC-0060 and SPEC-0060 row |
| C6 | `test_closeout_forward_nonspec_not_flagged` | control flagged, RFC-0070 not: Node `C6` | none needed |
| C7 | `test_closeout_display_id_match` | RFC-0080 flagged: Node `C7` | none needed |
| C8 | `test_closeout_rollout_guard` | RFC-0080 control flagged, RFC-0090 not: Node `C8` | none needed |
| C9 | `test_rollout_status_pipe_styles` | `hasUnfinishedRolloutPhases` over the four inputs gives true, true, false, false: Node `C9` | none needed |

`test_closeout_read_only` keeps its assertions unchanged. `test_closeout_report_only_gate` additionally became self-sufficient under single-function dispatch. The one assertion type that left the CLI path is the substring match on the rendered log; the Node cases assert on the structured `closeoutCandidates` the renderer prints from, and the retained CLI function proves the renderer.

## Ordinary suite measurement

Before (B) is the baseline commit in a disposable checkout with its own git directory; after (F) is the candidate in another. Both run the ordinary wrapper command `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` on the same host, Node, Bash, Git and serial width, with external wall time per run, one untimed warm-up per side, and alternating order.

| Pair | Order | Before s | After s |
|---|---|---|---|
| 1 | B-F | 116.6 | 79.3 |
| 2 | F-B | 115.6 | 78.5 |
| 3 | B-F | 116.5 | 79.4 |
| 4 | F-B | 115.5 | 79.3 |
| 5 | B-F | 116.5 | 79.4 |

Before median: 116.5 s
After median: 79.3 s
Median reduction: 31.9%

Environment: macOS arm64, 16 CPUs, Node 22.23.1, Bash 3.2.57, Git 2.54.0, wrapper `aai-run-tests.sh` serial. B is `34f0cbcad78fc851ed60972b1c527dcbc4c47779`; F is candidate commit `7767338470761a52fb86bd95740ffae98c5859d1` (the final commit changes only this note, spec status cells and product docs, none of which the ordinary run's cost depends on). B and F are `git clone` checkouts, each with its own git directory; the candidate carries a few extra tracked docs. One untimed warm-up per side (B 118.6 s, F 79.6 s). Every run exited 0 and printed `PASS: All aai-docs-audit tests passed`; no attempt was voided. Times are external monotonic wall seconds rounded to 0.1 s; raw JSON lines and logs are under `docs/ai/tdd/docs-audit-suite-speed/measurement/`.

Launch budget under a node shim (full run): 3 full real-corpus docs-audit launches (was 14) and 2 real-corpus index generations plus the pinned-clock one (was 11 plus the pinned one).

## Hosted CI

Docs-audit seconds from the `aai-docs-audit PASS (Ns)` log line of existing successful skill-suite runs. Hosted durations varied from 116 s to 207 s on unchanged code, so they are reported, never gated.

| Phase | Run | Head SHA | Seconds |
|---|---|---|---|
| before | 39874440898 | 34f0cbca | 116 |
| before | 39857896709 | 5e3b1773 | 142 |
| before | 39855256906 | 4f3f231a | 180 |
| before | 39852540377 | e1569bea | 207 |
| before | 39832331697 | d2824419 | 203 |
| before | 39831572019 | 9994c614 | 120 |
| before | 39830467382 | b84a73e7 | 175 |
| before | 39829624747 | 4f667f12 | 176 |
| before | 39814813112 | b06ef61a | 140 |
| before | 39813922700 | c373f296 | 166 |

Hosted after status: pending until the branch is pushed and at least 3 hosted runs on a head whose docs-audit suite blob equals the final one succeed; the `aai-docs-audit` row of `tests/skills/suite-weights.tsv` stays unchanged until then.
