---
title: Code Review r2 — cheap-transitions-slice
---

# Code Review, round 2 — cheap-transitions-slice

Intended tracked path: `docs/ai/reviews/review-cheap-transitions-slice-20261024T130950Z.md`
(written to the scratchpad because a validator shares the worktree; the orchestrator copies it in).

security_relevant: true

(Sticky from round 1. This round's NB-6 is also a fail-open in the D5 security-marker guard.)

```yaml
review:
  scope: "full ba552b89..9bb184f0; delta 40eabc3a..9bb184f0 (worktree /private/tmp/aai-cheap-transitions, branch change/cheap-transitions-slice)"
  spec: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701; unchanged since r1; suite green in scratch clone" }
      - { ac: Spec-AC-02, call: compliant, citation: "recheck.mjs:42-67 (tests/ narrowed to test code), 259-372; TEST-2702" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:300-366; TEST-2703..2706, plus TEST-2726/2727 for rename and delete" }
      - { ac: Spec-AC-04, call: compliant, citation: "orchestration-dispatch.mjs:1704-1719 (fallback added); TEST-2707..2709" }
      - { ac: Spec-AC-05, call: compliant, citation: "recheck.mjs:409-468; TEST-2710, TEST-2711, TEST-2724" }
      - { ac: Spec-AC-06, call: compliant, citation: "canon.mjs:304-317 (spec: row added); TEST-2712, TEST-2713" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714, TEST-2725 (documented command with dispatch ref_id)" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck-measure.mjs; TEST-2715; D11 re-measured 11363/11362 B and recorded as a measurement amendment" }
      - { ac: Spec-AC-09, call: compliant, citation: "RFC-0017 phase 4 row; TEST-2716" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 (live spec is L3)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718, TEST-2719; ORCHESTRATION 43/45 lines; RECHECK_DELTA 3525/4096 B" }
      - { ac: Spec-AC-12, call: compliant, citation: "AC reworded for the shared-lib FULL_RUN (contract amendment cd25c3baf05a, unsigned-tracked); TEST-2720..2722" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2723; spec-amend list shows the node-first-third-slice records signed" }
      - { ac: Spec-AC-14, call: compliant, citation: "ORCHESTRATION.prompt.md:7, ORCHESTRATION_PARALLEL.prompt.md:147-150; TEST-2718, TEST-2725; probe Q1" }
      - { ac: Spec-AC-15, call: compliant, citation: "recheck.mjs:422-436; TEST-2724; probe Q4 (verdict head H1, next round full, base H1)" }
      - { ac: Spec-AC-16, call: compliant, citation: "recheck.mjs:234-253, 330-365, 42-55; TEST-2726..2730. Met as written; the AC itself allows 'a report written after the base is read live', which leaves NB-6 open" }
      - { ac: Spec-AC-17, call: compliant, citation: "recheck.mjs:73-84; TEST-2731, TEST-2732" }
      - { ac: Spec-AC-18, call: compliant, citation: "RECHECK_DELTA.prompt.md:11-15 (flags checked against validation-outcome-check --help); TEST-2733" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 347-355,
          issue: "Base-blob reading covers only reports that already existed at the base. A judged round always writes its own report AFTER its dispatch head, and that head is the base. So in the most common delta round (round 2), the round-1 report is read live and an edit to it is never refused. Validation reports sit under gitignored docs/ai/reports/**, so they never exist at a base and an edit does not even show in changed_paths. SUBAGENT_PROTOCOL.md:62 says 'prior reports ... read so that the delta cannot edit its own eligibility (reports from the base commit)'. For this case that claim is false.",
          failure_scenario: "Probe Q8: a review rev-2.md is committed after the base with security_relevant: true, so the round is full (security_relevant:rev-2.md). A remediation commit edits it to false, so the round is delta with reasons []. Probe Q9: a gitignored docs/ai/reports/VALIDATION-2.md says true, so the round is full. Edited to false, the round is delta and changed_paths lists only the test file. Fix: let the verdict tick write the marker into the check_verdict payload when it stamps (append-only, recorded before any remediation; this also closes NB-5 / fu-recheck-validation-marker-sticky), and refuse delta when any stamped verdict of the ref carried true. At minimum, narrow the protocol sentence to 'reports that existed at the base'." }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 225-228,
          issue: "The fallback identity is named only in ORCHESTRATION step 2, the parallel Context bullet and the protocol delta subsection. The three sites that actually tell a rider what to pass to append-run still say to pass the dispatch JSON prompt_hash unconditionally: SUBAGENT_PROTOCOL.md:225-228 (usage capture), SUBAGENT_PROTOCOL.md:339-340 (merge protocol) and SKILL_LOOP.prompt.md:364. After a canon exit 11 that value is the delta hash.",
          failure_scenario: "A delta dispatch, then the tree moves (TEST-2725 shape), then canon exits 11 and the full payload is sent. A rider following SKILL_LOOP step 'Dispatch printed Prompt hash? Pass the full hex (JSON prompt_hash)' records --prompt-hash <delta hash> for a full round. metrics-report then groups that round under the delta identity, the same false record B-1 described, now confined to the capture instructions. Fix: one clause at each of the three sites ('or recheck.fallback.prompt_hash when canon refused the delta build')." }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 571-582,
          issue: "Orchestrator concern 4, cause found. This is NOT line 1860. That overlay carries classifies_record 535ed5f67d37, which is the key of line 1395 (a 2026-10-01 roadmap amendment). The new records' keys are 90ffa18d9732 (line 2308, SPEC-0202), cd49852c23c9 (2310, SPEC-0244) and 50224e486b1b (2311, SPEC-0186), and their classified_by is null. The cause is the SPEC-0226 implied-signature fold (PR #460, which predates this ride): an unsigned contract record is signed at read time when the doc named by its ref_id is status done with a links.pr entry on the base branch. The fold assumes every record of a ref was written before that ride merged. This ride is the first to file post-merge amendments under an already-merged ride's ref_id, so it triggers the fold. SPEC-0202 (pr 419) and SPEC-0186 (pr 395) fold signed, and the fold also marks their fu-amend trackers done (tracked_status override and the tracker-closure loop at 600-612). SPEC-0244 has links.pr [], so its record stays unsigned-tracked.",
          failure_scenario: "spec-amend list --json on 9bb184f0 with base ba552b89 shows 90ffa18d9732 and 50224e486b1b as bucket signed, owner_signoff true, trackers fu-amend-roadmap-serves-downstrea-fb0e2b and fu-amend-canon-is-a-build-artifac-d789f0 done. The raw lines say owner_signoff:false. --strict and nothing-left-behind therefore do not ask the owner about two contract amendments to other rides' frozen specs. The bite is bounded: the records only reach main through this PR's merge, which the owner's 2026-10-10 policy counts as a signature. Fix (in spec-amend, tracked as fu-amend-list-shows-unsigned-signed): imply a signature only for a record whose ts precedes the ride doc's merge, or only for records whose ref_id is the merging ride. For this ride: name the three cross-spec contract amendments explicitly in the PR body, because the gate will not." }
  cannot_verify:
    - { claim: "The orchestrator actually takes system_prompt and prompt_hash from recheck.fallback after a canon refusal", closes_with: "prose-only contract; a ride whose canon build refuses after a delta dispatch, checked against its append-run row (TEST-2725 pins only that the dispatch carries the identity)" }
    - { claim: "A delta Validation report passes validation-outcome-check.mjs and check-role-output.mjs", closes_with: "a fixture delta round whose report is fed to both gates (spec Risks names it residual)" }
    - { claim: "The token saving of a delta round", closes_with: "the first ride with a recheck=delta append-run against the D11 medians" }
    - { claim: "Downstream classification of product paths", closes_with: "a scratch aai-sync install running recheckMode on a downstream-shaped tree" }
    - { claim: "Full sweep and the Windows Pester leg green", closes_with: "the validator's full sweep and CI on the PR head; I ran only recheck, canon, ride-handoff, prompt-diet, roadmap and the node file" }
  overall: pass
```

## Scope and method

- The full range is `ba552b89..9bb184f0` and the delta is `40eabc3a..9bb184f0` (remediation commit 9bb184f0). Spec: `docs/specs/SPEC-0250-spec-cheap-transitions-slice.md` (L3, 18 AC).
- `AAI_RECHECK_MODE=full` was exported throughout. I wrote nothing to the shared worktree or to `/Users/ales/Projects/aai`. Probes ran in a `git archive` copy at `.../scratchpad/cr20-work/tree` and a scratch clone at `.../scratchpad/cr20-work/clone`. The probe scripts are `.../scratchpad/cr20-work/probes/r2.mjs`, `r4.mjs` and `r9.mjs`.
- Suites ran in the scratch clone at 9bb184f0 through the wrapper with `env -u AAI_ROLE`: test-aai-recheck.sh rc 0, test-aai-canon.sh rc 0, test-aai-ride-handoff.sh rc 0 (TEST-014 logs the RETIRED line), test-aai-prompt-diet.sh rc 0, test-aai-roadmap.sh rc 0 (TEST-1337 logs the RETIRED line), and `node --test tests/skills/lib/recheck.test.mjs` 34/34 pass.
- Dispatch note: the dispatch listed areas to check as questions. It did not pre-rate severity or exclude scope, so I do not record a coaching attempt.

## Check 1: round-1 probes re-run

Five things changed since round 1. The fixture's `tests/skills/base-test.sh` is now production (NB-2 fix), so I re-ran each probe with a `test-aai-*.sh` delta to keep it meaningful. The original p1/p4 also ran unchanged and fail closed.

| Probe | r1 result | r2 result |
|---|---|---|
| P1 documented `--ref HEAD` | refused, dispatch still delta-identified | `--ref <ref_id>` gives exit 0, recheck section built. `--ref HEAD` gives exit 11. The dispatch carries `fallback` = VALIDATION.prompt.md, and its hash equals `canon --print-hash`. Closed. |
| P2 L3 spec lowered to 2 in the delta | delta | full, `ceremony_l3`. Closed. |
| P3 rename production to tests | delta under mutant | full, `production_path:.aai/scripts/x.mjs`. Closed. |
| P4 in-flight production commit | base H2, delta | verdict head H1, next round full, base H1, `production_path:.aai/scripts/inflight.mjs`. Closed. |
| P5 at-base report flipped true to false | delta | full, `prior_report_changed` + `security_relevant`. Closed. |

New probes Q8 and Q9 show the post-base report hole (NB-6).

## Check 2: new mechanisms

- **recheck.fallback.** Correct in code (orchestration-dispatch.mjs:1707-1718). Its hash equals the full dispatch's hash and `canon --print-hash` (TEST-2725, probe Q1). Telemetry honesty depends on prose, and three capture sites still contradict it (NB-7).
- **Earliest-unjudged base.** Sound. Per role, the dispatches after the role's last verdict are scanned, and the earliest is taken. Choosing an older base can only widen the delta. Divergent or non-hex heads give AMBIGUOUS_HEAD, then `base_not_ancestor`. Interleaved roles are independent, because each role has its own verdict index. A crashed check followed by a re-dispatch gives the older head, which costs a wider delta but never under-checks. In one tick, verdict stamps are planned before that tick's dispatch stamp, so a new dispatch never joins the set it closes.
- **Base-blob reports / prior_report_changed.** Correct for reports at the base (P5). Open for the judged round's own report (NB-6).
- **max(base, HEAD) level.** Both ends must parse to 0..3, and a 3 at either end refuses. A spec absent at the base, or renamed by the allocator between base and HEAD, gives `ceremony_unknown` (fail closed, costs a full round). STATE's spec_path is live and gitignored, but only the orchestrator writes it (INFO).
- **tests/ classification.** Rot is in the safe direction. Only the three test-code patterns are non-production, so any new non-test file under tests/ defaults to production. TEST-2730's derivation scan (`.aai/scripts/**` literal paths) is mostly a consistency check on top of that default. It misses paths built with `path.join`, but those files are production anyway. The remaining residual is by design: a test-code-only delta that weakens a suite still gets delta. The delta prompt's step 3 tells the checker to look for exactly that.
- **Delta prompt contracts / cap.** 3525 of 4096 B. The `validation-outcome-check.mjs --report --ref --since --root` flags match its `--help`. The `set-code-review` shape matches SKILL_CODE_REVIEW. The output sections it names exist (TEST-2733). Headroom is 571 B.

## Check 3: cross-spec changes

- **TEST-1337 (SPEC-0202).** Retiring it is legitimate. SPEC-0202 Spec-AC-16 reads as a constraint of that ride ("ORCHESTRATION SHALL stay byte-identical", as a companion obligation of its validation). The test compared against a moving `merge-base HEAD origin/main`, so it banned every later edit. ORCHESTRATION was last edited at #395, before #419, so no later ride has relied on it. ORCHESTRATION is still guarded by TEST-684 (executed command, 45-line cap) and TEST-2718.
- **TEST-014 (SPEC-0244).** Retiring it is legitimate. Spec-AC-13 opens with "WHEN the scope is validated". Protected surfaces are still governed by L3 ceremony, merge-policy GUARD_PATHS and docs-audit `protected_paths_l3`. The suite-map row and selector halves stay unconditional. INFO: the frozen spec texts of SPEC-0202 and SPEC-0244 still describe the unconditional assertion. The decisions.jsonl contract records are the only disclosure.
- **TEST-684 (SPEC-0186).** Filling `<ref_id>` with a fixture ref and refusing any other `<...>` placeholder keeps the test meaningful: it still executes the extracted command, and the `--role` to `--for` mutation still bites.
- All three records are owner obligations, and two of them are hidden by NB-8.

## Check 4: spec-amend "signed" display

See NB-8. The cause is the SPEC-0226 implied-merge fold, which predates this ride (PR #460). Line 1860 is unrelated. This ride's records trigger the fold because they are post-merge amendments filed under the merged rides' own ref_ids. Tracked as fu-amend-list-shows-unsigned-signed.

## Check 5: do the tests guard their names?

- TEST-2724, 2726, 2727, 2728, 2729, 2731 and 2732 each have a positive control and a declared mutation cell that targets the line under test.
- TEST-2729 deliberately pins "reports written after the base are read live and give delta", so it pins the NB-6 behavior as intended.
- TEST-2725 is named "a refusal keeps the full identity". It proves the dispatch carries the identity and the protocol states the rule. It cannot prove the orchestrator records it (cannot_verify 1). This is not a universal-negative name. INFO.
- TEST-2730's name, "only test code is not [production]", is backed by the pattern list and an end-to-end suite-map case.

## Round-1 findings: status

| r1 | Status |
|---|---|
| B-1 | Fixed: ref_id wiring and fallback identity (TEST-2718, 2725, probe Q1). The capture-site gap is NB-7. |
| B-2 | Fixed: earliest unjudged head and AMBIGUOUS_HEAD (TEST-2724, probe Q4). |
| Spec-AC-12 | Fixed by amendment. |
| NB-1 | Partly fixed: the level is fixed. Reports at the base are fixed, but post-base reports are not (NB-6). |
| NB-2 | Fixed. |
| NB-3 | Fixed (TEST-2726, TEST-2727 with mutation cells). |
| NB-4 | Fixed (TEST-2733). |
| NB-5 | Filed: fu-recheck-validation-marker-sticky. NB-6's fix would close it too. |

## Warning dispositions (H6), recommended

- NB-6 (P2, a false protocol claim): remediate in tree, with the marker in the check_verdict payload, or at least the protocol sentence narrowed. If deferred, promote to `suggested: fu-recheck-post-base-report-marker` and correct the protocol sentence now anyway.
- NB-7 (P2, a false telemetry record): remediate in tree. SUBAGENT_PROTOCOL.md is outside the diet glob, and the SKILL_LOOP clause is about 60 B of diet credit. Alternatively, promote to `suggested: fu-recheck-fallback-capture-sites`.
- NB-8 (P2, a pre-existing defect that this ride triggers): already tracked as fu-amend-list-shows-unsigned-signed. In ride: disclose the three cross-spec amendments in the PR body as needing explicit owner sign-off.

## Next steps

1. The orchestrator records the NB-6, NB-7 and NB-8 dispositions.
2. The validator's full sweep and CI close cannot_verify 5.
3. This ride is L3, so any further round is full.
