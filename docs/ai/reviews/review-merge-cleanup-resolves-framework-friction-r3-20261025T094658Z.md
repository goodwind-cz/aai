```yaml
review:
  scope: fe504d3c..8c81c24b (worktree /private/tmp/aai-merge-friction; remediation 5020014b + review record 8c81c24b)
  spec: docs/specs/SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "delta does not touch OUTCOME emission; TEST-2901 re-run rc 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs:1289 plan keep line for a kept sync-base; TEST-2926 plan arm (new) + TEST-046 re-run rc 0; mutation M3 (planner refusal -> []) turns TEST-2926 red" }
      - { ac: Spec-AC-03, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-04, call: compliant, citation: "lib/merge-outcomes.mjs:188 frontmatterId requires a non-space id char; TEST-2929 blank-id arm; mutation M1 (old regex) turns TEST-2929 red; TEST-2927 cmp of recreated bytes vs incoming blob, re-run rc 0; TEST-2909 rc 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-07, call: compliant, citation: "retry logic unchanged (merge-cleanup.mjs:96-126, lib:157-166); TEST-2925 re-run rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "lib:269,282 preflight Needs-you says 'run the preflight again'; TEST-2925 + TEST-2921 rc 0; mutation M2 (needsLine(o,false)) turns TEST-2925 red. See N4 for the OUTCOME action field" }
      - { ac: Spec-AC-09, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-10, call: compliant, citation: "SKILL_MERGE 5114 -> 5177 B (+63), ledger 727 -> 790, TEST-012 pin 63821 -> 63884, pr-preflight +790; TEST-2922/2923 rc 0, TEST-012 pass; engine 1490 lines (= cap), lib 285" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_MERGE.prompt.md, line: 60,
          issue: "retry sentence omits that the fingerprint also keys on the item (reason:subject), and compares journal done lines and manifest row count, not the files",
          failure_scenario: "run 1 retries item A, run 2 hits a different retry item B with HEAD/journal/manifest unchanged: the engine emits a second retry (fingerprint differs by key) while the prompt says it would not" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md, line: 421,
          issue: "amendment narrative says plan names the kept step with a keep line 'instead of planned'; the step line still reads 'sync-base: planned' with the keep text as a '->' target (merge-cleanup.mjs:1393,1368)",
          failure_scenario: "a reader or a future test written from the spec text asserts the step status is not 'planned' and fails against the shipped engine" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/merge-outcomes.mjs, line: 269,
          issue: "the preflight rewording is applied only to the Needs you line; the OUTCOME JSON action for gh_read_failed/az_read_failed in preflight still says 'then run the cleanup again' (lib:89-90 via outcomeLine), and SKILL_MERGE step 1 exit 3 routes OUTCOME lines as step 2, which says relay the external action verbatim",
          failure_scenario: "gh is down during /aai-merge preflight: the agent relays the OUTCOME action 'check the GitHub CLI login and the network, then run the cleanup again' and the Needs-you line '... run the preflight again' - two contradictory instructions; TEST-2925 scopes its unwanted check to Needs-you lines only, so it does not see this" }
  cannot_verify:
    - { claim: "mutation-gate PASS for the spec's Test Plan rows", closes_with: "mutation-gate.mjs --spec on the worktree with its local evidence tree (scratch clone is DEGRADED: evidence gitignored)" }
    - { claim: "full-suite and Pester (TEST-2913/TEST-016) legs green after the delta", closes_with: "the parallel Validation sweep and CI" }
  overall: pass
```

security_relevant: false

# Code Review round 3 — merge-cleanup-resolves-framework-friction (CHANGE-0227)

Scope: `git diff fe504d3c..8c81c24b` in /private/tmp/aai-merge-friction. Spec: SPEC-0252-spec-merge-cleanup-resolves-framework-friction.md (frozen_sha256 restamped to 21630b4c...).
Checks ran in a scratch clone at 8c81c24b. Nothing was written to the worktree.

Dispatch note: the dispatch named items to confirm (N1-N3, the prompt comparison, the planner one-liner). It did not pre-rate severity. I reviewed the whole delta anyway.

## Disposition of round-2 NBs
- N1 (retry wording): folded. "never when nothing changed" is replaced by "the second only when origin HEAD, the journal or the manifest changed since the retrying run". This now matches `nextAttempt` (lib:157-166): the chain budget is MAX_AUTO_ATTEMPTS-1 = 2, and only the second retry is compared with the last record's fingerprint. It is still not exact, see N4-a below.
- N2 (plan for a kept sync-base): folded. merge-cleanup.mjs:1289 returns `keep <base> checkout (<reason> <detail>)` on `plan.refusal`. Every reason planSync can refuse with (origin_not_on_base, base_diverged, overlap_staged, ledger_rewritten, untracked_not_file) is classed `kept('sync-base')` in OUTCOME_TABLE, so the keep wording is never shown for a refusal that is not kept. TEST-2926 now has a plan arm, and it bites (M3).
- N3 (contract-class own-spec amendment): folded. A contract record plus its tracker `fu-amend-merge-cleanup-resolves-f-1abe0b` is appended. No earlier line was rewritten. `spec-amend list --strict` returns rc 0 and shows it as unsigned-tracked.
- Validation NBs: a blank or whitespace id now counts as missing (lib:188, `[ \t]*(\S.*?)`). The old `\s*(.+?)` matched `id: ` as `" "`, so two blank-id texts compared equal. TEST-2929's new arm turns red on the old regex (M1). TEST-2927 now has a byte `cmp`. The preflight Needs-you text was changed (TEST-2925, bites: M2). The spec D2 rows were amended.

## Engine one-liner (archive-runtime planner)
`const wt = findRideWorktree(ctx); if (!wt) return [];` is the same two statements joined on one line. It changes no behaviour. It keeps merge-cleanup.mjs at exactly 1490 lines, the TEST-2923 cap.

## Does the prompt state exactly what the engine compares?
Not exactly. `fingerprint()` (merge-cleanup.mjs:88-94) hashes four things:
- origin HEAD
- the journal's `done` lines, with timestamps stripped
- the manifest's row count
- the item key (`reason:subject`)

The prompt sentence leaves out the item key and gives the journal and manifest as whole files. See N4-a.

## Findings (all NON-BLOCKING)
- N4-a (P3, SKILL_MERGE.prompt.md:60): the retry sentence leaves out the item key. A different retry item gets a second automatic retry even when nothing else changed. **Disposition: remediate in tree.** Suggested wording: "the second only when the item, origin HEAD, the journal's done lines or the manifest's row count differ from the retrying run". Re-credit the ledger, the TEST-012 pin and the pr-preflight marker together. The router's action does not depend on this sentence, so the impact is descriptive only. It is still a false statement, which rules out disposition (d).
- N4-b (P3, spec line 421): the narrative says "instead of `planned`", but the step status is still `planned` and the keep line is a target under it. The D2 row ("plan mode prints a keep line with the reason") and the contract record are accurate. **Disposition: remediate in tree.** Drop "instead of `planned`" and restamp. Fold it into the next spec touch.
- N4-c (P3, lib/merge-outcomes.mjs:269): in preflight, the OUTCOME JSON `action` still says "run the cleanup again". The skill tells the agent to relay that field verbatim, so a gh outage at preflight gives contradictory instructions. **Disposition: remediate in tree.** Option 1: apply the preflight substitution where the outcome is classified (raise/classify when mode is preflight), so the OUTCOME action and the Needs-you line agree. Then widen TEST-2925's `unwanted` check to the whole output. Option 2: promote to a P3 follow-up. The effect is bounded: running the cleanup on an unmerged PR is refused with not_merged (external) and changes nothing.

## Evidence run (scratch clone)
- Re-run with rc 0: TEST-2925, 2926, 2927, 2929, 2921, 2922, 2923, 2909, 2901, 046. Prompt-diet TEST-012 also passes.
- Mutations: M1 (old id regex) turns TEST-2929 red. M2 (`needsLine(o,false)`) turns TEST-2925 red. M3 (planner refusal returns []) turns TEST-2926 red. All three bite.
- spec-lint returns PASS. spec-amend `--strict` returns rc 0. mutation-gate is DEGRADED: the evidence tree is absent in the clone.

## Next steps
Both verdicts pass. N4-a, N4-b and N4-c each need a disposition recorded before closeout. All three are small. N4-a and N4-c touch pinned bytes or engine lines: the engine is at its 1490-line cap, so put the N4-c change in the library.
