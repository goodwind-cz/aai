---
title: Code Review r1 — cheap-transitions-slice
---

# Code Review, round 1 — cheap-transitions-slice

Intended tracked path: `docs/ai/reviews/review-cheap-transitions-slice-20261024T121126Z.md`
(written to the scratchpad because a validator shares the worktree; the orchestrator copies it in).

security_relevant: true

(Rationale for `true`: two BLOCKING findings and two NON-BLOCKING findings are fail-open paths in an eligibility guard
that decides whether an independent check sees the whole ride. I treat that guard as a security guard in the D5 sense.
This ride is L3, so `true` costs nothing here, and it keeps later rounds full.)

```yaml
review:
  scope: "ba552b89..40eabc3a (worktree /private/tmp/aai-cheap-transitions, branch change/cheap-transitions-slice)"
  spec: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "recheck.test.mjs:193-241 TEST-2701; passed in a scratch clone" }
      - { ac: Spec-AC-02, call: compliant, citation: "recheck.mjs:34-61,217-321; TEST-2702 recheck.test.mjs:244-266" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:220-316; TEST-2703..2706 recheck.test.mjs:269-422 (rename/delete arm unpinned, NB-3)" }
      - { ac: Spec-AC-04, call: compliant, citation: "orchestration-dispatch.mjs:1693-1709,1773-1777; TEST-2707..2709" }
      - { ac: Spec-AC-05, call: compliant, citation: "append-event.mjs:172-191; recheck.mjs:356-387; TEST-2710, TEST-2711 (head-change re-tick not covered, B-2)" }
      - { ac: Spec-AC-06, call: compliant, citation: "canon.mjs:304-317,467-523; CANON.yaml delta_sections; TEST-2712, TEST-2713" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714 recheck.test.mjs:620-660 (uses --ref r1, not the documented --ref HEAD, B-1)" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/lib/recheck-measure.mjs; TEST-2715; D11 + RFC row numbers" }
      - { ac: Spec-AC-09, call: compliant, citation: "RFC-0017 phase 4 row; TEST-2716" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 recheck.test.mjs:793-812" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718, TEST-2719; RECHECK_DELTA 2433 B; ORCHESTRATION 43/45 lines" }
      - { ac: Spec-AC-12, call: non-compliant, citation: "select-suites prints only 'FULL_RUN reason=shared-lib path=.aai/scripts/lib/recheck.mjs' (no SELECTED aai-recheck) for a new file; AC says 'selects aai-recheck for each new file with no FULL_RUN line'; TEST-2721 (recheck.test.mjs:857-875) exempts the file and asserts FULL_RUN instead; no spec_amendment, no disclosure" }
      - { ac: Spec-AC-13, call: compliant, citation: "decisions.jsonl +6 classification lines; TEST-2723" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/ORCHESTRATION.prompt.md, line: 7,
          issue: "The documented delta build is `canon.mjs build --role <R> --ref HEAD --recheck delta`. recheckMode keys stamps and STATE on the ref, so with ref 'HEAD' canon always refuses. The orchestrator then builds the full payload, but the dispatch JSON still says system_prompt .aai/RECHECK_DELTA.prompt.md and carries the delta prompt_hash, and that hash goes to append-run --prompt-hash (SUBAGENT_PROTOCOL.md:226,339).",
          failure_scenario: "Probe P1: an eligible fixture gives a dispatch with recheck.mode delta, but `canon build --ref HEAD --recheck delta` exits 11 with 'first_round ceremony_unknown security_marker_absent:validation'. With --ref r1 it exits 0. So the mode never engages on the serial path, and every such round is recorded with a delta prompt identity while it ran the full payload (a false telemetry record). The same mis-record happens on ANY canon refusal after a delta dispatch." }
      - { rank: BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 365-372,
          issue: "check_verdict copies the head of the LATEST check_dispatched. A --confirm re-tick while a check is in flight appends a new check_dispatched at the newer HEAD (382-384), so a production commit that landed after the checker was handed its tree goes into the base and is never re-checked.",
          failure_scenario: "Probe P4: tick1 --confirm dispatches Validation at H1. A production commit .aai/scripts/inflight.mjs makes H2. A re-tick --confirm appends check_dispatched H2. The H1 validator's set-validation fail is stamped check_verdict head=H2. A test-only fix plus reset-block then gives a tick with recheck mode delta, base H2, changed_paths [tests/skills/base-test.sh]. The production file is outside every later delta. Fix: stamp the EARLIEST check_dispatched head since the last check_verdict of that role. That needs a D4 wording amendment." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 198-211,302-315,
          issue: "The eligibility inputs are read from the live tree, and the delta itself may edit them. The focus spec's ceremony_level is under docs/specs/** and the prior-report markers are under docs/ai/reviews/** or reports/**. Both are allowlisted as non-production.",
          failure_scenario: "Probe P2: an L3 fixture gives ceremony_l3. Rewriting the spec frontmatter to ceremony_level: 2 in the delta gives mode delta. Probe P5: a review that says security_relevant: true, edited to false in the delta, gives mode delta. Fix: read both at `base` (git show <base>:<path>) and take the stricter value, or refuse when changed_paths contains the focus spec or a prior report." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 34-45,
          issue: "`tests/**` is wholesale non-production, but production scripts consume files under tests/ as gate inputs. merge-policy.mjs:69 already guards tests/skills/suite-map.yaml as a lane-gate input, check-base-ref-pins.mjs:62 reads tests/skills/lib/base-ref-pin-baseline.tsv, and allocate-doc-number.mjs:158 names prompt-diet-ledger.sh. The two classifiers disagree, and the allowlist rots as new guard inputs land under tests/.",
          failure_scenario: "A remediation that only raises a ratchet baseline or drops a suite-map row (which changes which suites CI runs) qualifies for delta. Fix: subtract merge-policy's guard-input list (import it) or exclude tests/skills/suite-map.yaml, suite-weights.tsv and tests/skills/lib/*baseline*/ratchet/ledger files." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 260,
          issue: "The fail-closed `--no-renames` flag is unpinned. No case covers a rename or deletion out of a production path.",
          failure_scenario: "Mutation: drop '--no-renames' and TEST-2702..2714 still pass 15/15. With the mutant, `git mv .aai/scripts/x.mjs tests/x.mjs` gives mode delta, because default diff renames list only tests/x.mjs (probe P3). Add rename and delete cases to TEST-2703." }
      - { rank: NON-BLOCKING, file: .aai/RECHECK_DELTA.prompt.md, line: 13,
          issue: "The delta payload tells the checker to return 'the same outcome_report and set-validation commands as the full role' and the dual verdict 'as the full role does', but drops every output contract that defines them: report path docs/ai/reviews and the NEVER docs/validation rule, the set-code-review shape, the H6 disposition duty, the anti-gaming contract, the aai-outcome-v1 schema and the LOCAL EVIDENCE rule. The recheck_scope also does not name the spec path that step 4 asks it to re-run.",
          failure_scenario: "A delta Code Review writes its report under docs/validation/ (docs-audit flips to NEEDS-TRIAGE) or omits per-WARNING dispositions, or a delta validator emits a malformed outcome block. Deterministic gates catch most of these (fail-closed, a wasted round), but the seam is untested (spec Risks). Fix: add `spec: <path>` to recheck_scope and one line pointing at the full role prompt's output sections by path." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 294-296,
          issue: "D5 stickiness is enforced in code only for Code Review. last_validation.evidence_paths is REPLACED on every set-validation (state.mjs:981), while report_paths accumulates (state.mjs:1030), so an earlier Validation report that said true drops out of prior_reports.",
          failure_scenario: "V r1 says true (a security finding fixed in round). V r2 runs full and writes false, because a fresh context was never shown r1's marker. A test-only delta then makes V r3 delta. Fix: carry a sticky flag in the check_verdict payload, or scan every validation report of the ref." }
  cannot_verify:
    - { claim: "A delta Validation report passes validation-outcome-check.mjs and check-role-output.mjs", closes_with: "a fixture delta round whose report is fed to both gates (spec Risks names it residual)" }
    - { claim: "The token saving of a delta round (only payload bytes are measured)", closes_with: "first ride with a recheck=delta append-run against the D11 medians" }
    - { claim: "Downstream consumers (where .aai/ and */skills/ are gitignored) classify their product paths correctly", closes_with: "a scratch aai-sync install running recheckMode on a downstream-shaped tree" }
    - { claim: "Full sweep / Windows Pester leg green", closes_with: "CI on the PR head; I ran only recheck, canon, prompt-diet, orchestration-dispatch, hygiene-pack and the node file" }
  overall: fail
```

## Scope and method

- Scope: `ba552b89..40eabc3a`, which covers intake d4738f91, spec 013c7b7a and d57ea6f5, code 2117f94e and docs 40eabc3a. Spec: `docs/specs/SPEC-0250-spec-cheap-transitions-slice.md` (L3, frozen, two measurement amendments recorded).
- I read the full diff once and walked every Spec-AC row. Probes ran only in scratch copies (git archive and a scratch clone), with `AAI_RECHECK_MODE=full`. I wrote nothing to the shared worktree.
- Suites run in a scratch clone at 40eabc3a, through the wrapper with `env -u AAI_ROLE`. All exited 0: `test-aai-recheck.sh`, `test-aai-canon.sh`, `test-aai-prompt-diet.sh`, `test-aai-orchestration-dispatch.sh`, `test-aai-hygiene-pack.sh`, plus `node --test tests/skills/lib/recheck.test.mjs` (24/24).
- Probe files: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr19-work/probes/p1.mjs` and `p4.mjs` in the same folder.
- Dispatch note: the dispatch listed seven focus areas as questions. It did not pre-rate severity or exclude any area, so I do not treat it as a coaching attempt. I still reviewed the full scope.
- Disclosure note: the dispatch said the implementer's deviations are in the commit messages of 2117f94e and 40eabc3a. Neither message discloses any deviation. The one deviation I found (Spec-AC-12 / TEST-2721) is undisclosed.

## AC walk

See the YAML above. Twelve rows are compliant. Spec-AC-12 is non-compliant. The AC and the TEST-2721 row both say "select-suites.mjs selects aai-recheck for each new file with no FULL_RUN line". For `.aai/scripts/lib/recheck.mjs` the selector prints only `FULL_RUN reason=shared-lib ...`, and the test was changed to exempt that file and assert FULL_RUN. The behavior is reasonable (the shared-lib escalation is by design), but the frozen AC is unmet, with no amendment and no disclosure. Remedy: a `spec-amend` record that states the shared-lib escalation, plus updated wording in the AC and TEST-2721 rows.

## Answers to the seven focus questions

1. **Fail-closed.** Most arms are sound: an unknown role, a forced switch, no stamp, a non-ancestor base, an empty delta, a git error, an unreadable config, an absent, doubled or malformed marker, and an unknown level all give full. The allowlist approach means a new top-level directory defaults to production. There are three holes. B-2 is the re-tick head race. NB-1 is that the live spec level and the live report markers can be edited by the delta. NB-2 is that `tests/**` swallows guard inputs. The rename guard holds only by an unpinned flag (NB-3).
2. **Payload adequacy.** Prior reports and changed paths are carried, and the contract carries the five hazards. The spec path and the output contracts are dropped (NB-4).
3. **Marker.** Absent, doubled, malformed and unreadable markers all fall back to full (TEST-2705). Two weaknesses: Validation stickiness exists only in instruction text (NB-5), and the marker can be edited by the delta (NB-1). The column-0 rule ignores an indented `security_relevant: true` next to a column-0 false (probe P7). That matches D5 as written. INFO.
4. **Governance.** The diet entry is +2518 B and TEST-012 moved 58478 to 60996. PROFILES lists both files in core. The suite-map row-count pins moved to 113. ORCHESTRATION is 43/45 lines and RECHECK_DELTA is 2433/4096 B. Every library recheck.mjs imports is already in core.
5. **WORKFLOW against ORCHESTRATION and SUBAGENT_PROTOCOL.** The sentence matches the protocol subsection (L0-L2 only, never L3, production, protected or security-relevant). The orchestration wiring is defective (B-1). INFO: the SYSTEM_PROMPT row in SUBAGENT_PROTOCOL.md still says "the canonical role prompt from ai/<ROLE>.prompt.md", which a delta dispatch contradicts.
6. **Tests.** The refusal paths are real and have positive controls (TEST-2704 control, TEST-2705 ok case, TEST-2706 sibling existence check). Gaps: no rename or delete case (surviving mutant, NB-3), no head-change re-tick case (B-2), and no test drives the documented `--ref HEAD` command (B-1). The TEST-2713 identity arm skips with a SKIP-CASE line when ba552b89 is absent. CI uses fetch-depth 0, so this is INFO.
7. **Downstream.** Consumers get the new EVENTS types, a new marker line in reports, and a canon.mjs import chain that is entirely core. Because of B-1, consumers following ORCHESTRATION.prompt.md never get delta, but they do get mis-recorded prompt hashes. In consumers, `.aai/` is gitignored, so it never appears in a delta. That is harmless for product classification (cannot_verify 3).

## Warning dispositions (H6), recommended

- NB-1 (P2): remediate in tree.
- NB-2 (P2): remediate in tree (import merge-policy's guard list), or promote to a follow-up `suggested: fu-recheck-tests-guard-inputs`.
- NB-3 (P2): remediate in tree (rename and delete cases in TEST-2703, plus a mutation record).
- NB-4 (P2): remediate in tree (`spec:` line in recheck_scope, plus a pointer to the output sections).
- NB-5 (P3): promote to a follow-up `suggested: fu-recheck-validation-marker-sticky`.

## Next steps

1. Fix B-1. Make ORCHESTRATION step 2 and the protocol subsection use the dispatch JSON's `ref_id` for `--ref`. On a canon refusal, re-tick with `AAI_RECHECK_MODE=full` (or otherwise take the full system_prompt and prompt_hash) so append-run records the payload that was actually sent. Add a test that runs the documented command literally.
2. Fix B-2. Stamp the earliest `check_dispatched` head since the last `check_verdict` of that role, add a re-tick-with-new-head case to TEST-2711, and record a D4 spec amendment. That amendment is a scope change on an L3 spec, so it goes to the owner.
3. Amend Spec-AC-12 / TEST-2721 for the shared-lib FULL_RUN.
4. Handle NB-1 to NB-5 per the dispositions above, then run a full Code Review round 2 (this ride is L3, so delta mode does not apply).
