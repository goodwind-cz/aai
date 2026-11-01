# Code Review: precise-suite-evidence-reuse (round 7, delta re-check)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head 891af2ee); delta since round 6 6fd8a8c1..891af2ee (e4c3416a r6 report, cb2cafdd follow-up reopen, 891af2ee analysis note)
  spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md (frozen, amended; amendments unsigned, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "no code in delta; r6 walk stands; TEST-3165 PASS in validation r12 full sweep at 891af2ee" }
      - { ac: Spec-AC-02, call: compliant, citation: "suite-reuse.mjs unchanged since r6 (git diff 6fd8a8c1..891af2ee touches only decisions.jsonl, the note, the r6 report); TEST-3167 PASS (r12)" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged; TEST-3168..3172 PASS (r12)" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged; TEST-3173/3174 PASS (r12)" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; TEST-3175/3176 PASS (r12)" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged; TEST-3177..3179 PASS (r12)" }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged; TEST-3180/3181 PASS (r12)" }
      - { ac: Spec-AC-08, call: compliant, citation: "manifest unchanged; reviewer explain at 891af2ee: feedback-status/pricing/redact 0 unresolved, orchestration-mode 3, runtime-file 1" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged; TEST-3183/3190 PASS (r12)" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged; TEST-3184/3185 PASS (r12); native Windows post-PR" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; TEST-3186/3187 PASS (r12)" }
      - { ac: Spec-AC-12, call: compliant, citation: "unchanged; TEST-3188 PASS (r12)" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md:88-93 adds the R3 re-measurement (3 of 5, off 16 s, on 10 s, procedure named); :101 keeps the 3-of-5-at-head qualification; TEST-3189 PASS (r12, mutation re-stamped)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/analysis/precise-suite-evidence-reuse.md, line: 99,
          issue: "'Where reuse helps' still leads with the first R3 figure (all five reused, 5 s to 1 s) before qualifying it as commit-bound; the head figure (3 of 5, 16 s to 10 s under a different, five-run procedure) sits in the paragraph above. (= validation r12 NB-3.)",
          failure_scenario: "A reader who skims only 'Where reuse helps' quotes 5 of 5 / 5 s to 1 s as the shipped behaviour. The next sentence corrects it, so no false statement is made; it is a misread risk, not a wrong claim." }
  cannot_verify:
    - { claim: "R3 re-measurement wall times (off 16 s x3, on 10 s x3) at cb2cafdd", closes_with: "the raw per-sample framework logs; none is committed. The reused count (3 of 5, which three) is verified independently by explain at head" }
    - { claim: "SKILL_VERIFY reuse exception links docs/product/precise-suite-evidence-reuse.md", closes_with: "the product doc written after LOOP COMPLETE (carried since round 1)" }
    - { claim: "Windows behaviour of the Pester twin", closes_with: "native Windows pwsh run (post-PR, carried)" }
    - { claim: "Read channels the R1 residual names for the 3 reusable suites", closes_with: "manifest note plus minimal-tree gate are the only evidence (carried from r6; reviewer literal read found no read outside their closures)" }
  overall: pass
```

security_relevant: false

## Scope and method

Branch feat/precise-suite-evidence-reuse at 891af2ee, read-only on code. Delta re-check of 6fd8a8c1..891af2ee. The rest of the branch was walked in round 6 (spec_compliance pass) and nothing in the delta touches code, tests, the manifest or the spec, so the AC rows carry with r12 sweep evidence. Commands run (env -u AAI_ROLE): `spec-amend.mjs list --strict`, `follow-ups.mjs list`, `test-framework.sh --skill aai-spec-amend` (AAI_SUITE_REUSE=0), `suite-reuse.mjs explain --suite <s>` for the five manifest suites. No full sweep (validation r12 ran one at this head). My suite run appended one line to tracked `docs/ai/tests/test-runs.jsonl`; I restored that file. The pre-existing uncommitted `docs/ai/EVENTS.jsonl` validation_verdict line was left untouched.

Dispatch note: the dispatch named the prior blocker and what to verify. That is scope for a delta re-check, not coaching. I read the full delta, including the r6 report commit.

## Round-6 findings: resolution

| id | status | evidence |
|---|---|---|
| B1 decisions.jsonl:2650 erroneous close of fu-amend-spec-doctor-determinize | resolved | cb2cafdd appends a `follow_up_status` `open` record (decisions.jsonl:2651, append-only, no edit of :2650). `spec-amend list --strict` rc 0: unsigned-untracked=0; the 12:38:15Z doctor-determinize record (:2612) is `unsigned-tracked tracked_by=fu-amend-spec-doctor-determinize tracked_status=open`. `follow-ups list` shows the item open (P2). `--skill aai-spec-amend` PASS 1/1 (TEST-009 green) |
| NB-1 trailing dot at lib/ site | carried | fu-reuse-trailing-dot-literal (filed) |
| r11 N1/N2/N4 | carried | filed (fu-reuse-lib-dirname-base, fu-reuse-lib-after-expansion, fu-reuse-mutation-rows-3167) |
| N5 args | carried | accepted residual |

## Analysis note (891af2ee)

The added paragraph (:88-93) claims: re-measured at cb2cafdd, after the after-literal rule and the lib/ allowlist; five separate wrapped framework runs per sample, so each sample carries five wrapper start-ups; off 16 s, on 10 s in all three samples; reused 3 of 5 (aai-feedback-status, aai-pricing, aai-redact); orchestration-mode and runtime-file ran in both modes.

- The reused set matches the helper at head: `explain` gives 0 unresolved for the three named suites and unresolved entries for exactly the two named as running (runtime-file: `.aai/scripts/lib/runtime-file.mjs is followed by more than a terminator`).
- cb2cafdd differs from 891af2ee only by the note itself, so the measured commit is representative.
- The procedure difference from the first R3 table (one framework run per sample) is stated, so 16 to 10 is not presented as comparable to 5 to 1. The note does not overclaim.
- The timings themselves have no committed raw log (cannot_verify), but a saving of about 6 s for three reused suites at about 2 s of wrapper start-up each is plausible.

INFO: the reopen record carries `"source":""` (the CLI default when `--source` is omitted). The reader accepts it and the item projects as open; the reason field names the cause. No gate depends on it.

## BLOCKING

None.

## NON-BLOCKING and dispositions (H6)

- NB-1 `docs/analysis/precise-suite-evidence-reuse.md:99` (validation r12 NB-3): the "Where reuse helps" paragraph leads with the superseded 5-of-5 figure. Recommended disposition (d). accepted residual: P3 wording, the paragraph qualifies the figure in its next sentence, no false record, no bite. Remediating in tree at the next touch (lead with the head figure) is also acceptable.
- Carried: fu-reuse-trailing-dot-literal, fu-reuse-lib-dirname-base, fu-reuse-lib-after-expansion, fu-reuse-mutation-rows-3167 (disposition (b), already filed). accepted residual: N5 args constant default (P3, carried from round 1).

## Next steps

1. Orchestrator: record the code_review block (command in the dispatch return) and quote both accepted residual lines in the notes.
2. Proceed to the PR ceremony. The product doc follows LOOP COMPLETE (cannot_verify row 2).
