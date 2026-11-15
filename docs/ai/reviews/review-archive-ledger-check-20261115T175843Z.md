# Code review: archive-ledger-check (round 1)

```yaml
review:
  scope: "git diff origin/main (822569b2) in /Users/ales/Projects/aai-worktrees/archive-ledger-check, plus untracked docs/issues/ISSUE-0116-archive-ledger-check.md and docs/specs/SPEC-0293-spec-archive-ledger-check.md"
  spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/metrics-flush.mjs:225,245-247,1717,1838; TEST-3751 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-flush.mjs dry-run exit unchanged; TEST-3752 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:867-870, .aai/scripts/lib/metrics-flush-record.mjs:160-181; TEST-3753 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-cleanup.mjs:870; TEST-3754 PASS (incl. stop-after resume arm)" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-cleanup.mjs:1281-1286; TEST-3755 PASS (world digest equal, no archive dir)" }
      - { ac: Spec-AC-06, call: compliant, citation: "metrics-flush-record.mjs:161,176; merge-cleanup.mjs:869; merge-outcomes.mjs:80,118; TEST-3756 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_WORKTREE.prompt.md:289-294,369-371; TEST-3757 PASS; test-aai-prompt-diet.sh rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33-35; docs/product/telemetry.md:197-210; TEST-3758 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 161,
          issue: "the held check reads only the ride worktree's METRICS; once remove-worktree has moved the recovered tail to the main checkout and reset the worktree ledger to its HEAD blob (merge-cleanup.mjs:1045), a re-run of the interrupted cleanup sees the same runs as missing again and writes them a second time",
          failure_scenario: "apply #1: archive-runtime writes the late run to the worktree ledger, moveLedgerTails appends it to main and resets the worktree ledger, then the strict late check (or git worktree remove, e.g. a Windows file lock) stops the run (exit 4). apply #2: archive-runtime reports 'already_archived; 1 run(s) recovered', the tail move appends it again (the journal reset record retires the earlier intent). Main METRICS holds the Code Review run 2 times. Append-only ledger: cannot be undone. backed-by: repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro/test-repro-mc.sh --test TEST-REPRO (prints 'after first: 1', 'after second: 2')" }
      - { rank: BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 161,
          issue: "same root cause, second path: a run already in the MAIN checkout's ledger but not in the PR-head ledger is written again, because the worktree ledger is the only ledger consulted",
          failure_scenario: "the ride STATE carries ref bar's run (a STATE copied from main before bar flushed there, the documented carry-live-STATE practice); bar's line is in main's ledger, not in the ride branch. apply writes bar's run to the worktree ledger and the tail move adds it to main: main holds bar's Planning run 2 times. backed-by: repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro/test-repro-mc.sh --test TEST-REPRO2 (prints 'bar Planning runs in main = 2')" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_WORKTREE.prompt.md, line: 293,
          issue: "the manual cleanup command checks only the main checkout's ledger as it stands; for a branch whose flush lines are not yet in main (merged but not pulled, or pushed and merged later) every flushed run is written again",
          failure_scenario: "operator runs the manual Cleanup on a merged ride before pulling main (step 1 only checks 'has been merged'); the block writes all of the ride's runs as a reconstructed line; the next pull brings the PR's own flush line; each run counted twice." }
  cannot_verify:
    - { claim: "the D3 step 3 branch for a worktree NOT at the PR head (writable=false with a METRICS file present) behaves like the no-METRICS case", closes_with: "a merge-cleanup case with the ride worktree one commit past ctx.head and a late run (spec R2 names it untested)" }
    - { claim: "Windows: the child spawn, the posix rel in the printed fallback command and the step's keep text on a native runner", closes_with: "the Windows Pester / native leg on the PR head" }
    - { claim: "the full suite (test-framework.sh sweep) stays green; only the selected suites were run here", closes_with: "the one full sweep owed before close" }
    - { claim: "the kept outcome (ledger_runs_unchecked) is surfaced again after the worktree is gone; a later apply reports archive-runtime noop no_worktree and the command is no longer printed", closes_with: "a decision on whether the archive copy plus the default --recover-archives sweep is the accepted backstop, or a durable outcome record" }
  overall: fail
```

security_relevant: false

## Scope and spec

- Scope: `git diff origin/main` (base 822569b2) in the ride worktree, plus the two untracked drafts. EVENTS.jsonl and decisions.jsonl: checked append-only (origin/main blob is a byte-exact prefix of both) and the two `spec_amendment` records read (measurement class: mutation re-anchors, no AC change).
- Spec: docs/specs/SPEC-0293-spec-archive-ledger-check.md (frozen, ceremony 2).
- Dispatch note (anti-gaming): the dispatch named areas to think about and asked to ignore the ledger appends except for the append-only check. It did not pre-rate severity. The ledger appends were reviewed anyway (above).
- tests/skills/suite-weights.tsv is in the spec's review scope but unchanged; no new suite was added, so no weight row is needed (INFO).

## AC walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | metrics-flush.mjs parseArgs `--include-focus` + exit 2 without `--recover-archives`; archiveCopies keeps the --state file; focus not skipped. TEST-3751 PASS. |
| Spec-AC-02 | compliant | dry-run exit unchanged; TEST-3752 PASS (plan deep-equals the line, second run recovered=0). |
| Spec-AC-03 | compliant | archiveRuntime -> recoverStateCopy (dry run, then real run into the worktree ledger), tail move to main. TEST-3753 PASS. |
| Spec-AC-04 | compliant | `done 1 archived`, then `noop already_archived`; METRICS equals the merge blob. TEST-3754 PASS. |
| Spec-AC-05 | compliant | planner dry run over the live worktree STATE; TEST-3755 PASS. |
| Spec-AC-06 | compliant | no worktree METRICS -> `retained ledger_runs_unchecked` with the exact command; command run from main writes the runs. TEST-3756 PASS. |
| Spec-AC-07 | compliant | SKILL_WORKTREE step 2 block + Safety bullet; ledger credit 188 B; TEST-3757 PASS; prompt-diet suite rc 0. |
| Spec-AC-08 | compliant | CHANGELOG per-entry heading; telemetry.md names `--include-focus`, merge-cleanup, `ledger_runs_unchecked`. TEST-3758 PASS. |

The code does what the frozen spec says. The BLOCKING findings come from the spec's design choice (D1/D3: the PR-head worktree ledger is the only ledger consulted), so they fail code_quality, not compliance. The spec's own claims that this contradicts: D3/R1 "a re-run of the cleanup closes it", ISSUE Expected Behavior "A second run over the same state changes nothing", CHANGELOG "a second run changes nothing".

Tests run here (all PASS): merge-cleanup `--test` TEST-3753, 3754, 3755, 3756, 2901, 2902, 2922, 2923, 058 (line count 1490 <= 1490); test-aai-worktree.sh test_3757; test-aai-prompt-diet.sh (full, rc 0); test-aai-metrics.sh (full, rc 0, incl. TEST-3751/3752/3758).

## Findings (code_quality: fail)

### B1 (BLOCKING): a resumed cleanup counts the recovered runs twice

- Where: .aai/scripts/lib/metrics-flush-record.mjs:161 (`--metrics` is only `root/docs/ai/METRICS.jsonl`), consumed by .aai/scripts/merge-cleanup.mjs:868; interacts with merge-cleanup.mjs:1045 (`fs.writeFileSync(abs, t.head)` resets the worktree ledger after the move) and the journal `reset` record that retires earlier intents.
- Sequence: apply #1 writes the late run into the worktree ledger, moves the tail to main, resets the worktree ledger to HEAD, then stops before `git worktree remove` (late strict check, `worktree_remove_failed`, submodule archive stop, crash). apply #2: the dry run checks the reset worktree ledger, finds the run missing again, writes it again; the tail move appends it again.
- Repro: /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro/test-repro-mc.sh `--test TEST-REPRO` (a copy of tests/skills/test-aai-merge-cleanup.sh with ROOT pinned to this worktree and this case added):

```bash
test_repro_double_count() {
  metrics_world trepro 1
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT='before-remove-verify:docs/ai/EVENTS.jsonl' run_engine apply --pr "$PR" --pid 4242 --json
  echo "first apply rc=$ENG_RC"   # 4
  echo "after first: $(runs_of "$ORIGIN/docs/ai/METRICS.jsonl" 'Code Review' 2026-10-11T09:00:00Z)"   # 1
  run_engine apply --pr "$PR" --pid 4242 --json
  # archive-runtime: done "already_archived; 1 run(s) recovered to worktree:docs/ai/METRICS.jsonl"
  echo "after second: $(runs_of "$ORIGIN/docs/ai/METRICS.jsonl" 'Code Review' 2026-10-11T09:00:00Z)"  # 2
}
```

- Fix direction: treat a run as held when EITHER the worktree ledger or the main checkout's ledger holds it (for example, run the dry run against a temporary concatenation of both, or give `--recover-archives` a repeatable `--held-from <ledger>`), and add the resumed-after-move case as a test. Recovering only when the archive copy is fresh would not be enough: a STATE that changed between runs makes a fresh `.1` copy.

### B2 (BLOCKING): a run already in the main checkout's ledger is written again

- Where: same line; the design statement in spec D1 ("The worktree's ledger at the PR head is the one that already holds them") holds for the PR's own flush lines but not for lines that reached main after the branch point.
- Repro: same file, `--test TEST-REPRO2`: the main ledger holds bar's line (added after the ride branched), the ride STATE still carries bar's run; after apply main holds bar's run twice, and the step reports `1 run(s) recovered`.
- Fix: the same union-of-ledgers check as B1 (one change closes both).

### N1 (NON-BLOCKING): the manual cleanup block can double-write a merged-but-not-pulled ride

- Where: .aai/SKILL_WORKTREE.prompt.md:293.
- Scenario: the section says merged rides use `/aai-merge`, but step 1 still allows cleanup of a merged branch; run before pulling main, the command writes every flushed run, and the pull then brings the PR's flush line.
- Recommended disposition: (a) remediate in tree with one clause in step 2 ("on a merged branch, pull main first, or use `/aai-merge`"), or (b) a P3 follow-up. Not an accepted residual: it leaves a false record when it bites.

### INFO

- merge-cleanup.mjs sits exactly at its 1490-line ceiling; the new code fits by packing several statements per line (lines 866, 1282, 1285). No failure mode; the next change to this file has no headroom.
- The kept `ledger_runs_unchecked` outcome is printed only while the worktree exists; once remove-worktree has run, a re-run reports `noop no_worktree`. The archive copy and the default `--recover-archives` sweep remain the backstop (listed in cannot_verify).

## Warning dispositions (H6)

- B1, B2: must be fixed before merge (BLOCKING).
- N1: recommended (a) remediate in tree; the orchestrator records the choice.

## Next steps

1. Remediation: make the held check consult the main checkout's ledger too (B1 + B2), with RED-first tests for the resumed-after-move arm and the main-only line arm; correct R1 in the spec (disclosed amendment) and keep CHANGELOG's "a second run changes nothing" true.
2. Optionally fold N1.
3. Re-review the remediation commit.
