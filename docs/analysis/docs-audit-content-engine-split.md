# Docs-audit content/engine split

The always-on `aai-docs-audit` suite ran 195 functions on every pull request, although most of its cost cannot be turned red by a document-only change. This note records the case inventory, the paired before/after measurement, the `--gate`-only cases moved to `node:test`, the clusters that stay in Bash, and the change in suite selection. Production audit code under `.aai/` is untouched (`git diff c3e706e71e16ef041269002b08634bdae8612d02 -- .aai/` is empty).

Baseline commit `c3e706e71e16ef041269002b08634bdae8612d02` (main at planning time). Host: macOS arm64, 16 CPUs, Node 22.23.1, Bash 3.2.57, Git 2.54.0. Spec: `docs/specs/SPEC-DRAFT-spec-docs-audit-content-engine-split.md`; intake: `docs/issues/CHANGE-DRAFT-docs-audit-content-engine-split.md`.

## Case inventory

Every entry of the baseline `main()` (195, extracted with `git show` from the baseline commit) has exactly one class. `content` means the assertion reads the live repository corpus under `docs/` as its subject (it calls `live_audit` or `live_index_pair` on the real root, depends on `setup_indexarm_snapshots`, or reads a document under the real `docs/`); these 24 names are `DOCS_AUDIT_CONTENT_CASES` in `tests/skills/test-aai-docs-audit.sh` and run in `tests/skills/test-aai-docs-content.sh`. `node` means the case moved to `tests/skills/lib/docs-audit-gate.test.mjs`. Everything else is `engine`. `check_deps` and `setup_fixture` are setup and run in both suites; they are classed content because the list names them. Counts: 24 content, 5 node, 166 engine.

The 24 are the 23 of spec D2 plus `test_issue0001_posix_paths_noop`, which reads the `setup_indexarm_snapshots` real-index snapshots and so cannot run without the content setup. The two named D2 exceptions stay engine: the first-commit-date equivalence case (compares two engine implementations over the same corpus) and the four helper self-tests that run against a fixture root (TEST-2202 to TEST-2205).

| Function | Class | Owner |
|---|---|---|
| test_broken_refs_selector_isolates | engine | tests/skills/test-aai-docs-audit.sh |
| check_deps | content | both suites (setup) |
| test_change0007_lint_body_node | engine | tests/skills/test-aai-docs-audit.sh |
| test_2208_closeout_node | engine | tests/skills/test-aai-docs-audit.sh |
| setup_fixture | content | both suites (setup) |
| test_deterministic_index_no_clock_line | content | tests/skills/test-aai-docs-content.sh |
| test_1351_live_corpus_near_miss_set_is_dispositioned | content | tests/skills/test-aai-docs-content.sh |
| test_1348_near_miss_headline_carries_the_count | content | tests/skills/test-aai-docs-content.sh |
| test_1349_verdict_names_the_unreadable_tables | content | tests/skills/test-aai-docs-content.sh |
| test_1350_bare_ac_status_words_are_checked | engine | tests/skills/test-aai-docs-audit.sh |
| test_report_only_without_config | engine | tests/skills/test-aai-docs-audit.sh |
| test_strict_path_intake_gate | engine | tests/skills/test-aai-docs-audit.sh |
| write_config | engine | tests/skills/test-aai-docs-audit.sh |
| test_orphan_split | engine | tests/skills/test-aai-docs-audit.sh |
| test_drift_verdicts | engine | tests/skills/test-aai-docs-audit.sh |
| test_events_emission | engine | tests/skills/test-aai-docs-audit.sh |
| test_quick_mode | engine | tests/skills/test-aai-docs-audit.sh |
| test_index_sections_and_idempotence | engine | tests/skills/test-aai-docs-audit.sh |
| test_compound_ids_and_frozen_markers | engine | tests/skills/test-aai-docs-audit.sh |
| test_reviewby_literals | engine | tests/skills/test-aai-docs-audit.sh |
| test_uncommitted_doc_not_punished | engine | tests/skills/test-aai-docs-audit.sh |
| test_type_validation | engine | tests/skills/test-aai-docs-audit.sh |
| test_orphan_suggested_id | engine | tests/skills/test-aai-docs-audit.sh |
| test_classification_listing | engine | tests/skills/test-aai-docs-audit.sh |
| test_reviewby_actor_method | engine | tests/skills/test-aai-docs-audit.sh |
| test_events_parent_subref_boundary | engine | tests/skills/test-aai-docs-audit.sh |
| test_plan_scan_mode | engine | tests/skills/test-aai-docs-audit.sh |
| test_suggested_multi_ids | engine | tests/skills/test-aai-docs-audit.sh |
| test_category_prefix_scope | engine | tests/skills/test-aai-docs-audit.sh |
| test_index_legacy_autoskip | engine | tests/skills/test-aai-docs-audit.sh |
| test_skill_prompt_modes | engine | tests/skills/test-aai-docs-audit.sh |
| setup_closeout_fixture | engine | tests/skills/test-aai-docs-audit.sh |
| test_closeout_read_only | engine | tests/skills/test-aai-docs-audit.sh |
| test_closeout_report_only_gate | engine | tests/skills/test-aai-docs-audit.sh |
| setup_rollout_fixture | engine | tests/skills/test-aai-docs-audit.sh |
| test_rollout_progress_partial | engine | tests/skills/test-aai-docs-audit.sh |
| test_rollout_progress_summary_line | engine | tests/skills/test-aai-docs-audit.sh |
| test_rollout_report_only | engine | tests/skills/test-aai-docs-audit.sh |
| setup_spec0006_opendecision_fixture | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_deferred_whole_doc_section | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_zero_section_strict_fatal | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_zero_section_degrade_report | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_no_double_listing_idempotent | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_close_policy_prose | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_open_decision_guard | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0006_no_regression_real_repo | content | tests/skills/test-aai-docs-content.sh |
| test_change0166_closeout_is_clean_and_terminal | content | tests/skills/test-aai-docs-content.sh |
| test_534_two_stale_halves_are_closed | content | tests/skills/test-aai-docs-content.sh |
| test_issue0001_frontmatter_crlf_tolerance | engine | tests/skills/test-aai-docs-audit.sh |
| test_issue0001_actable_crlf_tolerance | engine | tests/skills/test-aai-docs-audit.sh |
| setup_indexarm_snapshots | content | tests/skills/test-aai-docs-content.sh |
| test_indexarm_earlier_day_generation_is_green | content | tests/skills/test-aai-docs-content.sh |
| test_issue0001_posix_paths_noop | content | tests/skills/test-aai-docs-content.sh |
| test_indexarm_index_is_not_stale | content | tests/skills/test-aai-docs-content.sh |
| test_indexarm_overdue_boundary_is_green | content | tests/skills/test-aai-docs-content.sh |
| test_issue0001_crlf_corpus_buckets | engine | tests/skills/test-aai-docs-audit.sh |
| test_issue0001_gitattributes | engine | tests/skills/test-aai-docs-audit.sh |
| test_issue0001_legacy_ratio_guard | engine | tests/skills/test-aai-docs-audit.sh |
| test_issue0001_no_regression_real_repo | content | tests/skills/test-aai-docs-content.sh |
| test_issue0001_posix_helper | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_committed_index_idempotent | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_index_git_state_invariant | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_audit_companion_gitignored | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_ac_row_level_not_whole_doc | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_ac_qualifier_normalized | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0010_ac_genuine_invalid_flagged_both | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_gate_missing_table | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_gate_fail_conditions | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_gate_pass_and_unknown | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_nearmiss_evidence_column | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_nearmiss_both_surfaces | engine | tests/skills/test-aai-docs-audit.sh |
| test_idxviolations_terminal_exemption | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_review_claim_unbacked | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_review_claim_backed | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_event_types | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_missing_close_telemetry | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_closeout_prompts_wired | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_config_close_gate | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_hook_close_gate | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_hook_parity_grep | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_read_only | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_gate_honors_config_review_by_methods | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_hook_gates_staged_not_worktree | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_work_item_closed_requires_fields | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_review_artifact_boundary | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0011_regression | content | tests/skills/test-aai-docs-content.sh |
| test_536_unparseable_ac_table_shape | engine | tests/skills/test-aai-docs-audit.sh |
| test_582_status_vocabulary_scoped_to_spec_ac_col | engine | tests/skills/test-aai-docs-audit.sh |
| test_537_shape_check_live_yield | content | tests/skills/test-aai-docs-content.sh |
| test_538_duplicate_ac_id_multiplicity | engine | tests/skills/test-aai-docs-audit.sh |
| test_554_index_tracked_only | engine | tests/skills/test-aai-docs-audit.sh |
| test_576_tracked_but_vanished_is_skipped_not_crashed | engine | tests/skills/test-aai-docs-audit.sh |
| test_581_stat_error_other_than_enoent_is_never_swallowed | engine | tests/skills/test-aai-docs-audit.sh |
| test_559_posix_predicate_infra_exit | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_lint_stray_markup | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_lint_promotion_pair | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_lint_body_file_predicate | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_hook_body_lint | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_regression | content | tests/skills/test-aai-docs-content.sh |
| test_change0007_hook_config_staged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0007_hook_space_filename | engine | tests/skills/test-aai-docs-audit.sh |
| test_index_continue_on_error | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_gate_slug_draft | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_draft_scanned_nonvacuous | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_gate_resolution_order | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_gate_ambiguous_id | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_allocation_durability | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0012_regression | content | tests/skills/test-aai-docs-content.sh |
| test_l1gate_lean_gate_pass | engine | tests/skills/test-aai-docs-audit.sh |
| test_l1gate_missing_justification | node | tests/skills/lib/docs-audit-gate.test.mjs G1 |
| test_l1gate_done_lean_clean | engine | tests/skills/test-aai-docs-audit.sh |
| test_l1gate_l2_regression | engine | tests/skills/test-aai-docs-audit.sh |
| test_l1gate_garbage_level_fail_closed | node | tests/skills/lib/docs-audit-gate.test.mjs G2 |
| test_l1gate_pipe_drop_reconciled | node | tests/skills/lib/docs-audit-gate.test.mjs G3 |
| test_l1gate_done_drift_pipe_drop | engine | tests/skills/test-aai-docs-audit.sh |
| test_gateac_canonical_pipe_drop_reconciled | node | tests/skills/lib/docs-audit-gate.test.mjs G4 |
| test_gateac_lean_volunteering_full_table | node | tests/skills/lib/docs-audit-gate.test.mjs G5 |
| test_gateac_done_drift_canonical_pipe_drop | engine | tests/skills/test-aai-docs-audit.sh |
| test_gateac_issue330_crosscheck | engine | tests/skills/test-aai-docs-audit.sh |
| test_delta3_provenance_drift | engine | tests/skills/test-aai-docs-audit.sh |
| test_delta3_empty_canonical_control | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_delivery_commit_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_intake_only_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_nondelivery_mentions_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_sibling_numbered_boundary | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_sibling_slug_boundary | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_ac_evidence_event_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_ac_table_signal | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_digest_and_event | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_precedence_over_stale | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_frozen_draft_probe | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_ac_table_tdd_log_only_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_index_seam | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_quick_mode_skips_probe | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0027_doc_surfaces_mention_false_open | engine | tests/skills/test-aai-docs-audit.sh |
| test_umbrella_marker_suppresses_visibly | engine | tests/skills/test-aai-docs-audit.sh |
| test_docsaicanon_classes | engine | tests/skills/test-aai-docs-audit.sh |
| test_docsaicanon_real_repo_clean | content | tests/skills/test-aai-docs-content.sh |
| test_change0028_mixed_cell_git_hash_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_mixed_cell_pr_ref_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_mixed_cell_prose_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_mixed_cell_unresolvable_hash_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_spec0039_verbatim_replica_not_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_arm_b_fileid_ac_evidence_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_arm_b_inflight_discriminator_guard | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_arm_c_work_item_closed_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_change0028_real_repo_clean | content | tests/skills/test-aai-docs-content.sh |
| test_change0028_userguide_mentions_work_item_closed | engine | tests/skills/test-aai-docs-audit.sh |
| test_fometrics_flush_arm | engine | tests/skills/test-aai-docs-audit.sh |
| test_fometrics_supersession | engine | tests/skills/test-aai-docs-audit.sh |
| test_fometrics_supersession_delivery_arms | engine | tests/skills/test-aai-docs-audit.sh |
| setup_dupid_fixture | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0057_duplicate_id_flagged | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0057_check_exit_code_unchanged | engine | tests/skills/test-aai-docs-audit.sh |
| setup_dupid_clean_fixture | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0057_no_false_positive | engine | tests/skills/test-aai-docs-audit.sh |
| test_spec0057_real_repo_known_collisions | content | tests/skills/test-aai-docs-content.sh |
| test_pdcm_product_family_repo_wide_clean | content | tests/skills/test-aai-docs-content.sh |
| test_pdci_validation_gate_delegation | engine | tests/skills/test-aai-docs-audit.sh |
| test_pdci_gate_characterization_temporal_gap | engine | tests/skills/test-aai-docs-audit.sh |
| test_histmap_corpus_equivalence | engine | tests/skills/test-aai-docs-audit.sh |
| test_histmap_one_git_call_per_audit | engine | tests/skills/test-aai-docs-audit.sh |
| test_histmap_rename_needs_no_renames | engine | tests/skills/test-aai-docs-audit.sh |
| test_histmap_no_history_yields_null | engine | tests/skills/test-aai-docs-audit.sh |
| test_histmap_first_commit_date_still_exported | engine | tests/skills/test-aai-docs-audit.sh |
| test_idmention_542_one_call_and_correct_dates | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_delivery_citation_flags | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_deferred_table_clean | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_close_end_state_clean | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_predicate_agrees_with_check | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_remediation_is_reachable | engine | tests/skills/test-aai-docs-audit.sh |
| test_acflip_real_repo_clean | content | tests/skills/test-aai-docs-content.sh |
| test_441_untracked_new_doc_passes_genuine_drift_still_fails | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_source_missing | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_both_clean_is_zero | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_ac_notes_still_counted | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_non_paths_ignored | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_dedup_per_file | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_one_signal | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_excluded_trees | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_closed_root_set | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_services_root | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_untracked_skipped | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_nongit_note | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_vanished_tracked_skipped | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_generator_companions_ignored | engine | tests/skills/test-aai-docs-audit.sh |
| test_broken_refs_retired_draft_not_a_row | engine | tests/skills/test-aai-docs-audit.sh |
| test_2202_live_audit_memo | engine | tests/skills/test-aai-docs-audit.sh |
| test_2203_live_audit_verify_mode | engine | tests/skills/test-aai-docs-audit.sh |
| test_2204_live_index_pair_restores | engine | tests/skills/test-aai-docs-audit.sh |
| test_2205_committed_index_staleness_survives | engine | tests/skills/test-aai-docs-audit.sh |
| test_2206_no_direct_live_corpus_launch | engine | tests/skills/test-aai-docs-audit.sh |
| test_2201_speed_note_profile | engine | tests/skills/test-aai-docs-audit.sh |
| test_2210_speed_note_measurement | engine | tests/skills/test-aai-docs-audit.sh |
| test_2211_migration_map_owners | engine | tests/skills/test-aai-docs-audit.sh |


## Paired measurement

Before (B) is the baseline commit in a disposable clone with its own git directory, running the ordinary docs-audit suite. After (F) is this change in another disposable clone, running the engine suite and then the content suite, each timed separately. Both use `env -u AAI_ROLE AAI_TEST_TIMEOUT=1800 bash .aai/scripts/aai-run-tests.sh bash <suite>`, serial, on the same host. One untimed warm-up per side, then five pairs alternating B then F and F then B; external monotonic wall seconds, rounded to 0.1 s. Every run exited 0.

| Pair | Order | Before s | Engine s | Content s |
|---|---|---|---|---|
| 1 | BF | 137.7 | 134.2 | 40.7 |
| 2 | FB | 144.8 | 131.5 | 41.5 |
| 3 | BF | 143.3 | 125.2 | 38.4 |
| 4 | FB | 148.0 | 131.7 | 38.0 |
| 5 | BF | 148.3 | 148.2 | 41.8 |

Before median: 144.8 s
Before worst: 148.3 s
Engine median: 131.7 s
Engine worst: 148.2 s
Content median: 40.7 s
Content worst: 41.8 s
Content ratio: 0.28

Reading the figures: the always-on cost of a document-only pull request falls from the before median to the content median (about 28% of it). The engine suite is not cheaper than the old suite (its median is 131.7 s against 144.8 s): it lost the 24 content cases but gained TEST-2304, which runs the whole content suite inside a clone to prove a planted violation still fails it. A pull request that touches an engine input now runs both suites back to back (172.4 s median together against 144.8 s), and that cost is accepted in the spec. The attempts that did not count: the first warm-up of F failed on a stale expectation in the earlier speed note's profile check (TEST-2201) and on an unregistered new row (TEST-2307); both were repaired, the clones were refreshed to the repaired commit and the whole measurement was run again from its warm-ups. The figures above are from that second run only. The candidate clone carried the final suite files; the note itself was a structurally valid placeholder during the timing, because the note-parsing rows (TEST-2301, TEST-2309) cost milliseconds.


## Gate batch measurement

Five `--gate`-only Bash functions moved to `node:test` cases over the exported `gateDoc`, in `tests/skills/lib/docs-audit-gate.test.mjs` (fixture files in a temp directory, no git commit, no child process). The retained CLI owners stay in Bash: `test_l1gate_lean_gate_pass` (exit codes of `--gate` and `--gate-file`, row named on failure) and `test_gateac_issue330_crosscheck` (spec-lint and `--gate` agree). The engine function `test_2308_gate_node` runs the Node file once and fails naming TEST-2308 when any case fails.

Matched timing: five alternating pairs after an untimed warm-up of each side. B is the five Bash functions run in order in the baseline clone (`source` the suite, `setup_fixture`, the five calls, including the 15 `--gate` CLI launches); F is `node --test tests/skills/lib/docs-audit-gate.test.mjs` in the candidate clone. Seconds are external wall time rounded to 0.1 s, so the B side carries about 0.2 s of Bash startup and fixture setup that the Node side does not need; that is the point of the move, and it is not hidden by subtracting it.

| Pair | Order | Gate before s | Gate after s |
|---|---|---|---|
| 1 | BF | 1.5 | 0.1 |
| 2 | FB | 1.6 | 0.2 |
| 3 | BF | 1.5 | 0.1 |
| 4 | FB | 1.5 | 0.1 |
| 5 | BF | 1.6 | 0.1 |

Gate before median: 1.5 s
Gate after median: 0.1 s
Gate ratio: 0.07

Migration map. Every clause each Bash function asserted is an assertion in the Node case; only the exit code and the rendered text of the CLI stay with the two retained owners.

| Id | Removed Bash function | Node case |
|---|---|---|
| G1 | `test_l1gate_missing_justification` | `G1 missing justification` (reason names the Ceremony justification line, no missing-table reason) |
| G2 | `test_l1gate_garbage_level_fail_closed` | `G2 garbage ceremony_level` (schema-invalid reason and canonical table still required) |
| G3 | `test_l1gate_pipe_drop_reconciled` | `G3 lean pipe-drop` (plain, escaped, indented, and the suffixed id that must not trip) |
| G4 | `test_gateac_canonical_pipe_drop_reconciled` | `G4 canonical pipe-drop` (plain, escaped, indented, L2, L3, and the clean table that passes) |
| G5 | `test_gateac_lean_volunteering_full_table` | `G5 lean-eligible doc volunteering the full canonical table` |


## Remaining Bash clusters

One profile pass over the 174 functions the engine `main()` now runs (monotonic timer around each call, total 141.2 s, every function exit 0), with a `node` and a `git` shim on `PATH` that count launches per function. The table lists the twelve most expensive clusters (functions grouped by name stem). Columns: functions, seconds, `node` launches, `git commit` calls, `git init` calls, and the most a move to in-process Node could save from the functions that need no git history (those launches times 70 ms, the per-launch saving measured at planning). Total node launches over the pass: 364.

| Cluster | Functions | Seconds | Node launches | Git commits | Git inits | No-git launch saving s |
|---|---|---|---|---|---|---|
| t2304 | 1 | 15.8 | 4 | 4 | 1 | 0.00 |
| spec0006 | 6 | 11.9 | 11 | 0 | 0 | 0.77 |
| change0007 | 7 | 9.8 | 33 | 15 | 7 | 0.07 |
| spec0011 | 18 | 9.5 | 50 | 8 | 16 | 0.00 |
| broken | 15 | 8.6 | 16 | 0 | 0 | 1.12 |
| index | 3 | 7.0 | 8 | 2 | 0 | 0.42 |
| change0027 | 14 | 7.0 | 16 | 39 | 13 | 0.00 |
| histmap | 5 | 6.8 | 8 | 4 | 4 | 0.14 |
| t2306 | 1 | 6.6 | 21 | 0 | 0 | 1.47 |
| spec0010 | 6 | 5.3 | 13 | 7 | 6 | 0.00 |
| fometrics | 3 | 4.7 | 11 | 11 | 3 | 0.00 |
| change0028 | 9 | 4.7 | 13 | 25 | 8 | 0.00 |

Why they stay in Bash. The spec0006 cluster runs the audit and the index generator over the shared fixture repository (printed sections, exit codes under strict and degraded modes): each case is a CLI-boundary assertion over a corpus a Node test would also have to build, and its 11 launches are worth at most 0.77 s. The git-fixture clusters (change0007, spec0011, change0027, spec0010, fometrics, change0028) spend their time in `git init`, `git commit` and hook execution that a Node test would still pay, and what they assert is the process boundary: a pre-commit hook blocking a commit, the generator printing its note, an exit code. The `broken` cluster is 15 functions around the generator CLI's printed `Wrote docs/INDEX.md (... N broken refs)` line and its exit status over a fixture that needs git-tracked-file semantics; its upper-bound saving is the largest of the no-git clusters, and it is disclosed for Validation under assumption A3 of the spec rather than settled here. The histmap cluster compares two engine implementations over a real history and is dominated by the git log walk. TEST-2304 (15 s in this pass) and TEST-2306 are the new rows of this change; the first runs a whole suite by design, and the second launches the selector once per real-tree path.


## Selection

One document-only fixture diff, fed to the real selector over the real map, before (baseline clone) and after (this change):

```
docs/issues/CHANGE-0228-provider-adapter-registry-slice.md
docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
docs/decisions/DECISION-original-request-outcome-backcheck-round-extension.md
docs/INDEX.md
```

Before (`node .aai/scripts/select-suites.mjs --files-from <list>` in the baseline clone):

```
CORE aai-check-state reason=core
CORE aai-docs-audit reason=core
CORE aai-spec-lint reason=core
CORE aai-hygiene-pack reason=core
SELECTED aai-follow-ups reason=docs/issues/CHANGE-0228-provider-adapter-registry-slice.md
SELECTED aai-spec-amend reason=docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
SELECTED aai-doc-numbering reason=docs/INDEX.md
SELECTED aai-prompt-diet reason=companion:aai-spec-lint
DROPPED 110
```

After:

```
CORE aai-check-state reason=core
CORE aai-docs-content reason=core
CORE aai-spec-lint reason=core
CORE aai-hygiene-pack reason=core
SELECTED aai-follow-ups reason=docs/issues/CHANGE-0228-provider-adapter-registry-slice.md
SELECTED aai-spec-amend reason=docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
SELECTED aai-doc-numbering reason=docs/INDEX.md
SELECTED aai-prompt-diet reason=companion:aai-spec-lint
DROPPED 111
```

The before run schedules `aai-docs-audit` as an always-on core suite; the after run schedules `aai-docs-content` instead and names no `aai-docs-audit` line and no `FULL_RUN`. An engine input (the audit script, its library, its config, the index generator, the skill prompt, both suite files, the live helper, the Node test files and this note) selects `aai-docs-audit`, and every literal real-tree path an engine case reads does the same (TEST-2305, TEST-2306).

Hosted weights (`tests/skills/suite-weights.tsv`), reported and not gated: `aai-docs-audit` 212 s (five measured main-push runs, 159 to 217 s); `aai-docs-content` 212 s by the file's fallback convention until hosted runs exist, so an engine-change pull request may plan two runners where it planned one. A hosted reseed is a later chore. The local split above predicts about 41 s for the content suite on this host against 145 s for the old suite.


## Deviations from the frozen spec

Disclosed here and in the spec's Amendment 1 (additive-with-disclosure; no owner sign-off obtained).

- a) 24 content cases, not 23: `test_issue0001_posix_paths_noop` reads the real-index snapshots built by `setup_indexarm_snapshots`.
- b) `check_deps` and `setup_fixture` are registered in both suites; TEST-2307 allows exactly these two names to overlap. The five Node-moved names are disjoint from both registrations.
- c) TEST-2304 asserts a `FAIL:` line plus `Orphans: [1-9]` in the output; the strict audit prints its headline on continuation lines after the FAIL line.
- d) TEST-2306 also excludes `test_2206_no_direct_live_corpus_launch` (it inspects suite text, not the corpus) and itself.
- e) `docs/INDEX.md` and `docs/ai/EVENTS.jsonl` map to the `aai-docs-content` row; the hygiene-pack suite-map row pin moved 118 to 119; failure messages name their TEST ids; the `aai-docs-audit` row gained `.aai/ROLE_COMMON.md`, `.aai/scripts/spec-lint.mjs`, `.claude/skills/aai-docs-audit/SKILL.md`, `docs/USER_GUIDE.md` and `tests/skills/suite-map.yaml`; TEST-2201 accepts the five Node-moved names in the earlier speed note's profile; TEST-2310 joins the content list.
- f) `mutation-run.mjs` has no `m` regex flag and no delete form, so the Mutation cells were rewritten to the substitution or lookbehind forms actually run; before that, the gate read TEST-2301, TEST-2307 and TEST-2312 as uncomparable.
