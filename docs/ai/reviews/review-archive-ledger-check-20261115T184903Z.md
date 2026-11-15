# Code review: archive-ledger-check (round 2, last round under the two-round cap)

```yaml
review:
  scope: "git diff origin/main (822569b2) in /Users/ales/Projects/aai-worktrees/archive-ledger-check, plus untracked docs/issues/ISSUE-0116-archive-ledger-check.md and docs/specs/SPEC-0293-spec-archive-ledger-check.md"
  spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:230,250,1857; TEST-3751 PASS (this round)" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-flush.mjs dry-run exit line unchanged; TEST-3752 PASS (this round)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:868-870, .aai/scripts/lib/metrics-flush-record.mjs:161-183; TEST-3753 PASS (this round)" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-cleanup.mjs:870; TEST-3754 PASS (this round)" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-cleanup.mjs:1282-1285; TEST-3755 PASS (this round)" }
      - { ac: Spec-AC-06, call: compliant, citation: "metrics-flush-record.mjs:167,178; merge-cleanup.mjs:869; merge-outcomes.mjs:80,118; TEST-3756 PASS (this round)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_WORKTREE.prompt.md:289-295,371; TEST-3757 PASS (this round); ledger credit 268 B" }
      - { ac: Spec-AC-09, call: compliant, citation: "metrics-flush.mjs:1825-1829, metrics-flush-record.mjs:165, merge-cleanup.mjs:868,1284; TEST-3759 and TEST-3760 PASS (this round); round-1 repro TEST-REPRO/TEST-REPRO2 now 1 and 1" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33-35; docs/product/telemetry.md:197-212; TEST-3758 PASS (this round)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 868,
          issue: "--held-in names the main checkout's working ledger BEFORE the base sync; a run that reached origin/main through another merged PR, but that the main checkout has not pulled yet, is in neither consulted ledger, is written again to the worktree ledger, and sync-base then brings the original line in while the tail move appends the recovered one",
          failure_scenario: "ride STATE carries bar's run (same premise as TEST-3760); bar's PR #432 merged to origin/main after the ride branched and before ours (#433); the main checkout has not pulled #432 (its last cleanup was kept, or both PRs were merged before cleanup ran). apply: archive-runtime done '1 archived; 1 run(s) recovered', sync-base fast-forwards through #432, tail move appends the recovered line: bar's Planning run is 2 times in the main METRICS. backed-by: repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r2/repro3.sh --test TEST-R3 (prints 'bar Planning runs in main = 2')" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 161,
          issue: "heldIn has no default; an omitted value is passed by spawnSync as the literal string 'undefined', which metrics-flush resolves to a missing file and silently treats as an empty ledger",
          failure_scenario: "a future third caller omits heldIn: no error, and the held check silently drops back to the round-1 B1/B2 behaviour (double write on a resumed cleanup). Both current callers pass it." }
  cannot_verify:
    - { claim: "the D3 step 3 branch for a worktree NOT at the PR head (writable=false with a METRICS file present) behaves like the no-METRICS case", closes_with: "a merge-cleanup case with the ride worktree one commit past ctx.head and a late run (spec R2 names it untested)" }
    - { claim: "Windows: the child spawn, the --held-in absolute path and the printed fallback command on a native runner", closes_with: "the Windows Pester / native leg on the PR head" }
    - { claim: "the full suite stays green; only selected cases were run here", closes_with: "the one full sweep owed before close" }
    - { claim: "the kept ledger_runs_unchecked outcome is surfaced again after the worktree is gone (a later apply reports noop no_worktree)", closes_with: "a decision that the archive copy plus the default --recover-archives sweep is the accepted backstop, or a durable outcome record" }
  overall: fail
```

security_relevant: false

## Scope and spec

- Scope: `git diff origin/main` (base 822569b2) in the ride worktree (16 files), plus the two untracked drafts. EVENTS.jsonl and decisions.jsonl: the origin/main blob is a byte-exact prefix of each (append-only holds); the new decisions lines are two measurement amendments, the follow_up_status close of `fu-archive-step-skips-ledger-check`, the contract amendment for Spec-AC-09 and its `fu-amend-spec-archive-ledger-check` sign-off follow-up.
- Spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md (frozen, ceremony 2, contract-amended for Spec-AC-09).
- Dispatch note (anti-gaming): the dispatch summarised the remediation and the validator's NON-BLOCKING item and told me to mark BLOCKING only for reproduced metric loss or duplication. It did not pre-rate findings. The full scope was reviewed.

## Round-1 findings: are they cured?

| Round-1 | Status | Evidence |
|---|---|---|
| B1 resumed cleanup double-writes | cured | round-1 repro `test-repro-mc.sh --test TEST-REPRO` now prints `after first: 1`, `after second: 1`, archive-runtime `noop already_archived`; TEST-3759 PASS |
| B2 run in the main ledger written again | cured for the case it named (the line is in the main checkout's working ledger) | `--test TEST-REPRO2` prints `bar Planning runs in main = 1`; TEST-3760 PASS. A sibling case is still open: B3 below |
| N1 manual cleanup before a pull | cured (documented) | SKILL_WORKTREE.prompt.md:290 comment `(merged branch: pull main first, or the runs it flushed are written twice)`; telemetry.md says the same |

## AC walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `--include-focus` parse plus the exit 2 guard (metrics-flush.mjs:230,250); focus skip gated (1857). TEST-3751 PASS. |
| Spec-AC-02 | compliant | TEST-3752 PASS (the plan deep-equals the line, the second run reports recovered=0). |
| Spec-AC-03 | compliant | archiveRuntime -> recoverStateCopy -> tail move. TEST-3753 PASS. |
| Spec-AC-04 | compliant | TEST-3754 PASS, including the stop-after resume arm. |
| Spec-AC-05 | compliant | TEST-3755 PASS (digest equal, no archive dir, negative control). |
| Spec-AC-06 | compliant | TEST-3756 PASS. |
| Spec-AC-07 | compliant | TEST-3757 PASS; prompt-diet credit 268 B carried in the ledger, TEST-012 pin and the pr-preflight sum. |
| Spec-AC-09 | compliant | `--held-in` union (metrics-flush.mjs:1825-1829), passed by both callers. TEST-3759 and TEST-3760 PASS. The AC names "only the main checkout's METRICS", which the code meets; B3 is outside the AC's wording. |
| Spec-AC-08 | compliant | TEST-3758 PASS. |

No spec claim is made false by B3: D3, CHANGELOG and telemetry.md all name "the main checkout's" ledger, and D1 itself records that the step runs before the base sync. B3 fails code_quality as a reproduced duplicate, not compliance.

Tests run this round (all rc 0): merge-cleanup `--test` TEST-3753, 3754, 3755, 3756, 3759, 3760, 058 (1490 <= 1490), 2923, 2901, 2902; test-aai-metrics.sh test_3751, test_3752, test_3758; test-aai-worktree.sh test_3757. Logs: /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r2/.

## Findings (code_quality: fail)

### B3 (BLOCKING): a run merged on origin/main but not yet pulled is written twice

- Where: .aai/scripts/merge-cleanup.mjs:868 (and the planner at :1284): `heldIn: path.join(ctx.origin, 'docs', 'ai', 'METRICS.jsonl')`, the main checkout's working file. archive-runtime runs before sync-base, so this file is the pre-sync ledger. It lacks every line merged on origin/main since the checkout's last sync, not only this PR's.
- Sequence: the ride STATE carries bar's run (TEST-3760's premise). bar's flush line reached origin/main through PR #432, merged after the ride branched and before ours. The main checkout has not pulled #432 yet. That happens when two PRs are merged before cleanup runs, or when the last cleanup kept sync-base, which a dirty shared main checkout does. archive-runtime finds bar's run in neither the worktree ledger (PR head) nor the pre-sync main file, so it writes it. sync-base fast-forwards through #432, then the tail move appends the recovered line.
- Repro: /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r2/repro3.sh `--test TEST-R3`. It is a copy of the current suite with ROOT pinned to this worktree, plus one case that commits bar's line as `bar (#432)` on the bare main before the squash `foo (#433)`. Output: archive-runtime `done 1 archived; 1 run(s) recovered`, sync-base `fast-forward`, `bar Planning runs in main = 2`.
- Introduced by this change: on origin/main, archive-runtime writes no ledger, so this duplicate cannot happen there.
- Fix direction: also count as held the ledger that sync-base will land on. That means the METRICS blob at the sync target (the merge commit, or the fetched origin/main tip that planSync uses), not only the working file. The helper can materialise `git show <target>:docs/ai/METRICS.jsonl` to a temp file and pass it as a second `--held-in`, since `--held-in` is already repeatable. Add a TEST-3760 arm in which bar's line is committed on the bare main before the merge commit instead of being an uncommitted line in the main checkout.

### N2 (NON-BLOCKING): recoverStateCopy's heldIn has no default

- Where: .aai/scripts/lib/metrics-flush-record.mjs:161,165. Verified: `spawnSync(node, [..., undefined])` does not throw. Node passes the string `undefined`, metrics-flush resolves it to a missing file, and `ledgerRoleStarts` returns an empty set, so the held check degrades silently.
- Scenario: a future caller that omits it silently gets back the round-1 B1/B2 double write. Both current callers pass the value.
- Recommended disposition: (a) remediate in tree together with B3: default `heldIn = []`, spread it as `--held-in` pairs, and drop the flag when the list is empty. Otherwise (d) accepted residual, P3 maintenance, no observed bite.

### INFO

- `flush_segment` for a continuation is now the larger of the two ledgers' line counts plus one. If each ledger held a different line of the same ref, the numbering would undercount. Readers fold lines by ref_id, so no failure mode was found; not a finding.
- merge-cleanup.mjs is still at its 1490-line ceiling (TEST-058). The B3 fix belongs in the helper.

## Warning dispositions (H6)

- B3: must be fixed before merge (BLOCKING). This is the last review round under the cap, so the orchestrator escalates per the round-cap rule: either a standing round extension for one more remediate-and-review round, or an owner decision.
- N2: recommended (a), remediated together with B3. Otherwise (d), `accepted residual: heldIn default is a P3 maintenance gap with no current caller omitting it`. The orchestrator records the choice.
- N1 (round 1): cured in tree.

## Next steps

1. Remediate B3 RED-first: a TEST-3760 arm with bar merged on origin/main and not pulled, then a held check over the sync target's METRICS blob. Fold N2.
2. Disclose the amendment (D3 names the sync target's ledger) and keep Spec-AC-09's wording true.
3. Re-review only the remediation delta, if the round cap is extended.
