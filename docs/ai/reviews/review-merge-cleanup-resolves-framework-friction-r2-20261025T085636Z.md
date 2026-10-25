```yaml
review:
  scope: fb171891..fe504d3c (branch change/merge-cleanup-resolves-framework-friction, worktree /private/tmp/aai-merge-friction), focus 02c07d91
  spec: docs/specs/SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "lib/merge-outcomes.mjs:25-86 OUTCOME_TABLE (+overlap_staged, untracked_not_file kept), classify :126-150; TEST-2901 re-run rc 0 (scan now also reads clash( literals)" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs:470 staged -> refusal overlap_staged, :501 non-file -> untracked_not_file, both kept('sync-base'); probe PB2: exit 0, Kept: line, 'Cleanup: complete; kept 1 item(s)', main HEAD != MC, no decide outcome; TEST-2926, TEST-046 re-run rc 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:319-338 doneDocsBetween; links.pr ~ filtered :331; TEST-2929 arm 2 re-run rc 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "lib:210 compareDraft `!fmDraft.id` guard (r1 N2 closed); TEST-2929 arm 1; TEST-2927 deleted projection/guide re-run rc 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged since r1 (parseDecide, usage gate, choices once); SKILL_MERGE AAI_DECIDE in both blocks" }
      - { ac: Spec-AC-06, call: compliant, citation: "syncBase :591 syncGate before resumeSync (r1 N1 closed); TEST-2928 re-run rc 0; probe PFF/PCD: protected bytes unchanged" }
      - { ac: Spec-AC-07, call: compliant, citation: "raise :109 no attempts record -> retry:false (preflight/plan go straight to fallback); probe PB1 4/4 external; probe PCH: apply chain alternates retry/decide, never >2 consecutive retry lines; TEST-2919, TEST-2925 re-run rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "apply kept paths now print Kept: + 'complete; kept N' (probe PB2, PUD); TEST-2921 green at r1. See N2 for plan-mode under-reporting of a kept sync" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-046 amendment recorded (spec_amendment contract + fu-amend-merge-cleanup-ride-lefto-007e1e); spec-amend list --strict rc 0; D12 now names SPEC-0222 D6 wording (r1 INFO closed). See N3 on the own-spec record's class" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2922/2923 re-run rc 0 (in a mirror with suite-map/diet files); engine 1490/1490 lines (at cap), library 285/520; spec-lint PASS, check-test-registration rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_MERGE.prompt.md, line: 60,
          issue: "'State retry (only apply emits it, at most twice in a row and never when nothing changed)': the engine compares the fingerprint only with the previous run, and only when that previous run itself emitted a retry (lib nextAttempt: last = chain > 0 ? ... : null). The first run of a chain emits retry whatever changed. 'only apply' and 'at most twice in a row' hold.",
          failure_scenario: "Probe PCH: the fast-forward always fails. r2 is decide, r3 --decide id=retry, then r4 emits auto retry with the same HEAD, journal and manifest (nothing changed). Without an answer, r5 is decide and r6 is auto retry again with nothing changed. An agent that trusts the sentence reads the r4/r6 retry as proof of progress. Routing stays bounded (retry and decide alternate), so there is no loop. The defect is a false statement in the prompt the dispatch asked to check." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1288,
          issue: "PLANNERS['sync-base'] returns [] when planSync gives a refusal (a kept reason), so plan prints 'sync-base: planned' with no target and no keep line. The remove-worktree planner prints 'keep <path> (<reason>)' for the same situation. The change set introduced this (f099de28; at fb171891, plan refused with exit 3). 02c07d91 made it reachable for staged and non-file clashes too.",
          failure_scenario: "Probe PPL: a staged roadmap overlap, or the main checkout on another branch. plan exits 0 with '  sync-base: planned' and 'Cleanup: not started; nothing was changed.', then apply keeps sync-base (overlap_staged / origin_not_on_base). The preview tells the owner the base sync will run when it will not." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2440,
          issue: "The own-spec amendment that adds the D12 'Remediation round 1' paragraph and TEST-2925..2929 is recorded as amendment_class measurement. By spec-amend's own definition (spec-amend.mjs:184-193), measurement covers only HOW a claim is measured. This paragraph changes WHAT the frozen spec promises: the D2 table row 'gh_read_failed, az_read_failed | both | retry, then external' (spec :155) no longer holds in preflight, and D2 gains two kept reasons (overlap_staged, untracked_not_file) the table does not list.",
          failure_scenario: "spec-amend list puts the record in the measurement bucket, which owes no owner signature and no fu-amend- tracker. The owner is never asked to sign the behaviour change to his frozen spec, while the parallel TEST-046 change to SPEC-0221 in the same commit did get the contract lane. This leaves a light-lane record for a contract change (append a contract-class record; never rewrite the line)." }
  cannot_verify:
    - { claim: "Full merge-cleanup suite, neighbour suites and the Pester TEST-016 It are green at fe504d3c", closes_with: "the parallel Validation full sweep plus the Windows CI leg (this review re-ran TEST-009, 046, 2901, 2919, 2922, 2923, 2925-2929 only, all rc 0, in a scratch mirror)" }
    - { claim: "An agent harness routes the step-2 menu once and stops on external", closes_with: "a live /aai-merge run; TEST-2912's router is a test double" }
  overall: pass
```

# Code review round 2: CHANGE-0227, merge cleanup resolves framework friction

security_relevant: false

- Scope: `git diff fb171891..fe504d3c` (10 commits, 17 files), with the remediation commit `02c07d91` read hunk by hunk. The handoff was by ref.
- Dispatch note: the dispatch listed areas to check (the syncGate split, the new kept reasons, the deleted-file archive and rollback, the attempts ledger, compareDraft, `links.pr ~`, the prompt wording). It did not pre-rate severity or exclude any area. The full range was reviewed.
- Spec: frozen `SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md` (frozen_sha256 restamped in 02c07d91). `spec-lint --path` passes, `spec-amend list --strict` exits 0, `check-test-registration` exits 0.
- Nothing was written into the worktree. `git status --porcelain` is clean and `git ls-files -ci` is empty. The ledger diffs over the range are pure appends.

## r1 BLOCKING findings, re-probed against the new code

Probe mirror: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr12root`. It is a copy of the current suite with probe functions added (PB1, PB2, PB3, PFF, PCD, PUD, PCH, PPL), and `.aai` is a symlink to the worktree.

| r1 | Probe | Result at fe504d3c |
|---|---|---|
| B1: preflight retry unbounded | PB1: gh fails every read, 4 preflight runs | Every run: exit 3, `REFUSE gh_read_failed`, OUTCOME `external pending`, `Needs you: check the GitHub CLI login...`. **Closed.** |
| B2: staged overlap menu with no effect | PB2: staged roadmap overlap, 2 apply runs | Exit 0, `overlap_staged` auto/resolved, a `Kept:` line, `Cleanup: complete; kept 1 item(s), nothing needs you.`, main HEAD not moved, no menu. PUD (a directory at an added path) gives the same with `untracked_not_file`. **Closed.** |
| B3: ENOENT on a locally deleted file | PB3: deleted overview-data.json | Exit 0, fast-forward to MC, file recreated as `{"v":2}`, no stack trace. **Closed.** |

## r1 NON-BLOCKING findings

- N1 (resumeSync ran before the protection check): closed. `syncBase` runs `syncGate` first (`merge-cleanup.mjs:591`). TEST-2928 shows that a branch switch after a crash at sync-after-rewrite leaves the file and the journal intact.
- N2 (null ids compare equal): closed (`lib/merge-outcomes.mjs:210`, TEST-2929 with a mutation cell).
- INFO, SPEC-0222 D6 disclosure: closed by the D12 paragraph.

## Regression hunt on the remediation

- **syncGate split.** The gate runs twice: once in `syncBase` and once inside `planSync`. Both calls only read. The `noop` check moved into `planSync`, so an interrupted fast-forward (HEAD already at the target) still reaches resumeSync's re-append branch. OK.
- **Deleted file, then a failed fast-forward (PFF).** The rollback `rmSync`s the recreated file, so the deletion is restored (` D` in status). The other dirty file gets its local bytes back. The next run converges to MC. OK.
- **Deleted file, then a crash at sync-after-rewrite (PCD).**
  - If the deleted file is the only dirty file, no pending journal is written. After the crash the file holds the HEAD blob, so the local deletion is undone. The re-run then takes the incoming file, which is what the run would have done anyway.
  - In the mixed case, the journal lists only the file that existed. The re-run restores that file and converges to MC.
  - No bytes are lost either way. INFO: the mkdir for a deleted parent directory can leave an empty directory after rollback (git does not track directories).
- **Attempts ledger.** `raise` now defaults to `retry:false` without an attempts file. That covers preflight, plan, and an apply whose git dir cannot be resolved. Apply resolves origin before the first gh read (`resolveOrigin`, `:276`), so the apply chain still retries first (TEST-2919 rc 0). PCH confirms there are never more than two consecutive retry lines.
- **Kept reasons.** `overlap_staged` and `untracked_not_file` are `kept('sync-base')`. `halt` with `phase: 'plan'` raises the Keep inside the step, so the step is retained with a Kept line and the other steps finish.
- **`links.pr ~`.** The YAML parser returns the string `~`, now filtered. `null` and the empty value were already null. `[~]` parses as the string `[~]`, which names no PR and leaves the doc unproven. That is the safe direction. INFO.
- **The prompt.** "only apply emits it" and "at most twice in a row" match the engine. "never when nothing changed" does not (N1 below).

## New findings

- **N1 (NON-BLOCKING, P3), SKILL_MERGE.prompt.md:60.** "never when nothing changed" overclaims. The engine compares the fingerprint only with the immediately previous run that emitted a retry, so the first run of a chain (after a decide run or an owner `retry` choice) can retry with nothing changed (PCH r4, r6). **Disposition: remediate in tree.** Suggested wording: "at most twice in a row; the second only when origin HEAD, the journal or the manifest changed since the first". The prompt bytes are pinned, so re-credit the diet ledger, the TEST-012 pin and the pr-preflight marker together (TEST-2923).
- **N2 (NON-BLOCKING, P3), merge-cleanup.mjs:1288.** Plan says `sync-base: planned` for a sync that apply keeps (PPL). **Disposition: remediate in tree.** Mirror remove-worktree and return `keep the main checkout (<reason> <detail>)` on `plan.refusal`. Add a plan arm to TEST-2926.
- **N3 (NON-BLOCKING, P2), decisions.jsonl.** The own-spec D12 remediation amendment changes the D2 contract, but it is recorded as `measurement`. **Disposition: remediate in tree.** Append a `spec-amend add --class contract` record for the D12 behaviour change, which co-creates the fu-amend tracker that owes the owner signature. Do not rewrite the existing line (HAZ-LEDGER). This item leaves a false record, so H6 option (d) does not apply.

## Deviations from the frozen spec (listed even where reasonable)

1. D2 table, row `gh_read_failed/az_read_failed both: retry, then external`: preflight is now external on the first run. Disclosed in D12. The record class is N3.
2. D2 table: `overlap_staged` and `untracked_not_file` are kept reasons the table does not list. Disclosed in D12.
3. D7 fingerprint key: `reason:subject`, not the sorted outcome ids. Unchanged from r1, INFO.

## Warning dispositions (H6)

- N1: remediate in tree (P3).
- N2: remediate in tree (P3).
- N3: remediate in tree (P2; append-only contract record).

## Next steps

Both verdicts pass, and the three NON-BLOCKING findings each need their disposition recorded before closeout. N1 and N3 are small. N2 needs a two-line planner change and an assert. Re-review can be a delta check of those hunks.
