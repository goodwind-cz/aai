---
title: Code Review r3 — cheap-transitions-slice
---

# Code Review, round 3 — cheap-transitions-slice

Intended tracked path: `docs/ai/reviews/review-cheap-transitions-slice-20261024T140808Z.md`.
The report was written to the scratchpad because a validator shares the worktree. The orchestrator copies it in.

security_relevant: true

(Sticky from rounds 1 and 2. This round's NB-9 is also about the integrity of the delta-eligibility guard.)

```yaml
review:
  scope: "full ba552b89..26befd35; delta 9bb184f0..26befd35 (46e848f6, 26befd35; b466b711 is ledger/report only)"
  spec: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701; unchanged; aai-recheck rc 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "recheck.mjs:42-67; TEST-2702" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:321-366; TEST-2703..2706" }
      - { ac: Spec-AC-04, call: compliant, citation: "orchestration-dispatch.mjs:1707-1722; TEST-2707..2709" }
      - { ac: Spec-AC-05, call: compliant, citation: "append-event.mjs:172-196 (+--security-relevant, refused unless true|false); TEST-2710, TEST-2711, TEST-2736" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2712, TEST-2713" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck-measure.mjs:85 (fixture stamp now carries security_relevant false); TEST-2715" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2716" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718, TEST-2719" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2720..2722; prompt-diet rc 0 (want_growth 62417)" }
      - { ac: Spec-AC-13, call: compliant, citation: "26befd35 row text now says 'recorded before 2026-10-24T13:00:00Z', the same filter as recheck.test.mjs TEST-2723 (String(i.ts) < '2026-10-24T13:00:00Z')" }
      - { ac: Spec-AC-14, call: compliant, citation: "SKILL_LOOP.prompt.md:364, SUBAGENT_PROTOCOL.md:230 and 341-342; TEST-2725, TEST-2737" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2724" }
      - { ac: Spec-AC-16, call: compliant, citation: "recheck.mjs:234-264 (markerOfText, markerOfRole), 310-319 (stamp checks), 494-497 (stamp records marker); TEST-2726..2730, TEST-2734..2736; probes Q8/Q9 re-run as TEST-2734" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2731, TEST-2732" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2733" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, line: 6,
          issue: "frozen_sha256 e962ca30987f... does not match the spec's contract projection at 26befd35 (computed 803bf40fcb69...). The anchor equals the projection of the 46e848f6 spec with ONLY the Spec-AC-13 and TEST-2723 wording change. So the anchor was stamped before the four TEST-2734..2737 rows were moved into the Test Plan, and the move was never re-stamped or recorded. The 13:55:44Z record's 'what' names only the wording change.",
          failure_scenario: "`node .aai/scripts/spec-amend.mjs list --strict` (the SKILL_PR AMENDMENT GATE) exits 1 at 26befd35 with 'undisclosed-amendment' on this spec, with or without --base-ref ba552b89. The PR role would then 'clear' it with the generic printed add line ('undisclosed post-freeze content change'), which leaves a less informative record. Fix now: one `spec-amend.mjs add --spec docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md --ref cheap-transitions-slice --what 'TEST-2734..2737 rows moved from under the AC Status table into the Test Plan (placement only, row text unchanged)' --why 'mutation-gate saw 33 of 37 rows' --class contract --signoff none`. That re-stamps the anchor. Then re-run list --strict and mutation-gate." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 296-319,
          issue: "Delta eligibility trusts check_verdict and check_dispatched lines in the live docs/ai/EVENTS.jsonl. That file is tracked and non-production (LEDGER_AND_PAGE_PATHS). append-event.mjs is the documented subagent append path and does not read AAI_ROLE. Nothing ties a stamp to the dispatcher or excludes a stamp that arrives inside the delta. Spec D4's 'Both writes go through append-event.mjs (one EVENTS writer)' names a tool, not a writer. This predates this round: the base forgery has been possible since 2117f94e. The NB-6 change does not widen it. A forged false stamp cannot undo an earlier stamped true (probe F4), and without forgery Q8/Q9 now give full.",
          failure_scenario: "Probes in cr21-work/probes/forge.mjs, L2 fixture with EVENTS tracked. F1: honest stamp at H0. Production commit A edits .aai/scripts/x.mjs. `append-event --event check_verdict --role code_review --head A --status fail --security-relevant false`, then a test-only commit. recheckMode gives delta, reasons [], changed [EVENTS.jsonl, test-aai-a.sh], and A is never checked. Control F0 without the forged line gives full with production_path. F2: a forged check_dispatched with head A after the real verdict makes the next --confirm tick stamp a real verdict at head A, so the next round is delta. F3: a forged false verdict appended before the tick suppresses the real stamp (planCheckStamps finds no unjudged dispatch) of a review report that said true. After the report is edited to false, the round is delta. Each path needs a deliberate forged append. The project's own posture for subagent write guards (state.mjs R-GUARD S1, SUBAGENT_PROTOCOL ENV row) is 'a guardrail against the honest/accidental path, NOT a security boundary'. No honest role is ever told to append check_* events, and an L3 ride never gets delta. Recommended fix (small): append-event.mjs refuses check_dispatched and check_verdict under AAI_ROLE=subagent, the same arm as state.mjs S1, plus one TEST row. D4/Risks then names the remaining raw-append residual instead of 'one EVENTS writer'." }
  cannot_verify:
    - { claim: "The orchestrator actually records recheck.fallback.prompt_hash after a canon refusal", closes_with: "the prose is now at all three capture sites (TEST-2737). Only an append-run row from a real refused-delta ride proves that a rider follows it" }
    - { claim: "Honest-path stamping happens before remediation edits a report (NB-6 relies on a --confirm tick between the judged round and the next writer)", closes_with: "a real ride's EVENTS showing the check_verdict line written at the Remediation dispatch tick. TEST-2736 covers the tick in a fixture. A sole-agent ride without --confirm ticks stamps late and reads the report live at that time" }
    - { claim: "A delta Validation report passes validation-outcome-check.mjs and check-role-output.mjs", closes_with: "a fixture delta round fed to both gates (spec Risks residual)" }
    - { claim: "Token saving of a delta round", closes_with: "the first ride with a recheck=delta append-run" }
    - { claim: "Full sweep and Windows Pester leg green at 26befd35", closes_with: "the validator's running full sweep and CI. I ran recheck, prompt-diet, expert-fetch, pr-preflight and platform-adapter" }
  overall: fail
```

## Scope and method

- Full range `ba552b89..26befd35`. Delta `9bb184f0..26befd35`: 46e848f6 (remediation r2) and 26befd35 (spec row move and AC-13 wording). b466b711 contains only the r2 report, a follow-up and a test-run line. Spec: `docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md` (L3, 18 AC, 37 Test Plan rows).
- `AAI_RECHECK_MODE=full` was set throughout. The worktree `/private/tmp/aai-cheap-transitions` was only read (git log/show, the r2 validation report, and a copy of its gitignored `docs/ai/tdd/spec-cheap-transitions-slice` evidence). All probes and suites ran in the scratch clone `.../scratchpad/cr21-work/repo` at 26befd35. Probe scripts are in `.../scratchpad/cr21-work/probes/` (forge.mjs, hash.mjs, hash2.mjs).
- Suites (`env -u AAI_ROLE`), all rc 0: test-aai-recheck.sh (TEST-2701..2737), test-aai-prompt-diet.sh, test-aai-expert-fetch.sh (TEST-2623 logs the row-4 RETIRED line), test-aai-pr-preflight.sh (TEST-008), test-aai-platform-adapter.sh (TEST-076). Also `spec-lint --path <spec>` gave LINT PASS. `mutation-gate --spec <spec>` gave GATE PASS 37/37, using the evidence copied from the worktree. `spec-amend list --strict` gave **rc 1** (BLOCKING finding).
- Dispatch note (anti-gaming): focus item 1 said "If so, that is BLOCKING". That pre-rates severity. I record it as a coaching attempt and judged the severity independently (NB-9 below explains why I rank it NON-BLOCKING). The dispatch did not exclude scope.

## Focus 1: the NB-6 fix

**Code.** `planCheckStamps` reads the marker of every report STATE names for the role, at the tick that first sees the verdict. It records `true` if any report says true, `false` only if every report says exactly-one-false, and otherwise records no field (`markerOfRole`, recheck.mjs:247-264). `orchestration-dispatch.recordCheckEvent` passes it to `append-event --security-relevant`, which accepts only `true` or `false`. `recheckMode` refuses delta for any stamped true of either role (`security_relevant:stamp:<role>`) and for a latest role stamp without `false` (`security_marker_absent:stamp:<role>`). Live reads still refuse on true or ambiguous. They can never lower a stamp.

**Honest path closed.** Every `--confirm` tick plans the stamps before it dispatches (orchestration-dispatch.mjs:1701-1706), so the tick that dispatches Remediation stamps the review's marker before remediation runs. Q8 and Q9 now give full (TEST-2734, re-run green). In the fixture, a remediation that edits the post-base report after an honest tick gets full.

**Stickiness across roles.** This holds. `events.some(...)` scans both roles over the whole ledger. A later false stamp of the same or the other role does not clear an earlier true. In probe F4, a validation stamp of true, then false, still gives full for both Code Review and Validation. TEST-2735 covers the same-role, other-role and no-field cases. A forged `true` only forces full, so it fails safe.

**Forged EVENTS lines (the question asked).** Yes, a delta commit can append a forged `check_verdict` (F1) or `check_dispatched` (F2) and get delta. Eligibility ignores nothing that arrives inside the delta range, and it could not use the range as a provenance test anyway. The legitimate stamp is written into the worktree at the tick, after the base, and is committed later by the orchestrator, so a real stamp always lies inside the delta too. `append-event.mjs` writes `actor` as the git slug for every caller, so a line carries no provenance. Details and the reasons for my severity call are in NB-9.

## Focus 2: NB-7

All three capture sites now carry the clause:
- SKILL_LOOP.prompt.md:364: "(`recheck.fallback.prompt_hash` if canon refused the delta)", 60 B, measured.
- SUBAGENT_PROTOCOL.md:230 (usage capture): "A dispatch that canon refused (`recheck.fallback`) passes the fallback's `prompt_hash`".
- SUBAGENT_PROTOCOL.md:341-342 (merge protocol): "the `recheck.fallback` hash when the delta build was refused".

TEST-2737 anchors each site by nearby text, and its mutation cell (SKILL_LOOP) bites. Closed.

## Focus 3: B5 / B6

- **B5, TEST-2623 row 4.** The scoping is legitimate. It matches the TEST-014 and TEST-1337 retirements accepted in r2. SPEC-0249's "rows 4 and 5 stay not started" was a constraint of that ride, and this ride's Spec-AC-09 legitimately moves row 4 to in progress. The half is retired only when SPEC-0249 is absent or `status: done` (awk over the frontmatter). It is disclosed by a contract amendment on ref node-first-third-slice (unsigned, tracker fu-amend-node-first-third-slice-2-6a231a open). **Row 5 is still guarded.** I set RFC-0017 row 5 to "in progress" in the scratch clone, and expert-fetch then failed with `FAIL: TEST-2623: row 5 status is in progress, want not started`. INFO: row 5 will trip the same way for the phase-5 ride.
- **B6, the +3939 term.** It is correct. 54252 + 1287 (the pr-capability-preflight entry) + the listed credits + 3939 = 62417, which equals `want_growth` in test-aai-prompt-diet.sh and the ledger total. 62417 − 58478 = 3939 = the ledger entry's number. TEST-008 and TEST-076 are green. INFO: the ledger entry's prose says "deficit 3879 B (2518 B at delivery, 1361 B of round 1 and 60 B of round 2 …)". Those parts sum to 3939, so the "3879" in the prose is stale. The number that counts (the entry's leading 3939) is right. Fix the prose when the line is next touched.

## Focus 4: 26befd35

- **Spec-AC-13 cutoff.** Verified against the code. The row text "recorded before 2026-10-24T13:00:00Z" matches `String(i.ts) < '2026-10-24T13:00:00Z'` in TEST-2723. The TEST-2723 Test Plan row says the same. Compliant.
- **Row move.** The four rows now sit in the Test Plan table. mutation-gate reads 37/37, and each mutation cell's sed target exists verbatim in the code: `e.payload.security_relevant === true)) reasons`, `priorVerdict.payload.security_relevant !== false`, `if (marker !== null) stamp.security_relevant = marker;`, and `recheck.fallback.prompt_hash`.
- **But the frozen anchor is wrong** (BLOCKING). `contractHash` of the spec gives 6d77d1d0 = anchor at 9bb184f0 and 62f70e1b = anchor at 46e848f6, but 803bf40f ≠ anchor e962ca30 at 26befd35. The anchor reproduces exactly from 46e848f6 plus only the AC-13 and TEST-2723 wording (probes/hash2.mjs, variant v2). So the record was stamped and the rows were then moved without a re-stamp. `spec-amend list --strict` exits 1, and that is the SKILL_PR AMENDMENT GATE.

## Focus 5: fu-recheck-verdict-not-bound-to-check

Filing it is defensible, and it stays non-blocking. The bite (validation probe D2) needs a check dispatched at a head HP that contains an unjudged production commit, a check that crashes, and then a `set-validation` from some source other than that checker before the next tick. Only the orchestrator or a human can write that, because state.mjs refuses STATE mutators under `AAI_ROLE=subagent`. Re-dispatching after a crash, the usual recovery, appends no new verdict identity and later stamps the real checker's verdict. The stamped-marker trust does not make D2 worse. The marker in such a stamp is read from whatever reports STATE names, so it is no less honest than the base it sits beside. An earlier stamped true still keeps the ride full. The marker trust does make the stamp the single authority, and that is why the forged-append path (NB-9) and D2 are the same root: a verdict stamp has no binding to the check that produced it. I recommend recording NB-9 against the same root, either in this follow-up's text or as a sibling, so the fix lands as one design (stamp provenance) rather than two.

## Findings

### BLOCKING B-7: the spec anchor does not match its content

See the YAML. `spec-amend list --strict` gives rc 1 at 26befd35. The fix is one `spec-amend.mjs add` that names the row move (it re-stamps), followed by `list --strict` rc 0 and `mutation-gate` 37/37. Do not hand-edit `frozen_sha256` (ROLE_COMMON: never hand-write the record or the anchor).

### NON-BLOCKING NB-9 (P2): verdict stamps carry no provenance; a forged EVENTS line yields delta

See the YAML for probes F1 to F3. Why NON-BLOCKING, although the dispatch pre-rated it BLOCKING:
1. It needs a deliberate forged append. No honest role is told to write check_* events.
2. The repo's stated posture for subagent write guards is honest-path guardrail, not security boundary (state.mjs:1653-1663, SUBAGENT_PROTOCOL ENV row).
3. It predates this round, and the NB-6 change narrows the reachable holes rather than adding one.
4. Delta never applies to L3, and CI still runs on the PR head.

It is still a real gap in an "opt-in by proof" guard, and the spec's "one EVENTS writer" sentence overstates the guarantee.

Recommended disposition: remediate in tree. Add an AAI_ROLE=subagent refusal for `check_dispatched`/`check_verdict` in append-event.mjs (mirroring state.mjs S1) with a TEST row, and correct D4/Risks to name the raw-append residual. Alternatively, promote it to `suggested: fu-recheck-stamp-provenance` (P2) and fold it with fu-recheck-verdict-not-bound-to-check.

### INFO
- Ledger prose "deficit 3879 B" vs parts summing to 3939 (prompt-diet-ledger.sh:261).
- TEST-2623 row 5 will block the phase-5 ride exactly as row 4 blocked this one.
- A sole-agent ride that never runs `--confirm` ticks stamps the marker late, from a live read (cannot_verify 2).

## Prior findings: status

| Finding | Status |
|---|---|
| NB-6 | Fixed (honest path): TEST-2734..2736, probes Q8/Q9 full. Forged-append residual is NB-9. |
| NB-7 | Fixed: three sites, TEST-2737. |
| NB-8 | Tracked (fu-amend-list-shows-unsigned-signed). Still: name the cross-spec contract amendments, now four (SPEC-0202, SPEC-0244, SPEC-0186, SPEC-0249), in the PR body. |
| Validation r2 B5 | Fixed and scoped legitimately. Row 5 guarded (mutation bites). |
| Validation r2 B6 | Fixed: +3939 term correct, TEST-008 and TEST-076 green. |
| fu-recheck-validation-marker-sticky | Done, correctly (any stamped true is sticky across roles). |

## Warning dispositions (H6), recommended

- B-7 (BLOCKING): remediate in tree, as above.
- NB-9 (P2): remediate in tree (AAI_ROLE guard + spec wording), or promote to `suggested: fu-recheck-stamp-provenance` and link it to fu-recheck-verdict-not-bound-to-check. It is not eligible for accepted residual (P2, and the spec text overstates).
- INFO items: no disposition required.

## Next steps

1. Fix B-7 with `spec-amend add` (re-stamp), then confirm `list --strict` rc 0 and mutation-gate 37/37.
2. The orchestrator records the NB-9 disposition.
3. This ride is L3, so round 4 is full.
