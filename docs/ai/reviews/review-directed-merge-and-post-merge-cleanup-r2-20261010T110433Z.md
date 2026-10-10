# Code review: directed-merge-and-post-merge-cleanup (round 2)

```yaml
review:
  scope: "delta 3dd377cd..93e6be5c plus regression origin/main...HEAD (2836dcc5...93e6be5c), branch change/directed-merge-and-post-merge-cleanup"
  spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/SKILL_MERGE.prompt.md marked bash/PS blocks; four aai-merge wrappers; SKILL_PR/SHIP/WORKTREE pointers (unchanged since r1); TEST-001/002 (TEST-002 now also asserts the forwarded direction)" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs runPreflight: repo_mismatch + local-HEAD head_changed added before the sweep check; engine still has no gh pr merge path; TEST-003 new arms (repo_mismatch, local head, stale-head sweep via real lane-gate)" }
      - { ac: Spec-AC-03, call: compliant, citation: "readAndGate: checkRepo before the MERGED gate; TEST-005 repo_mismatch + insteadOf control" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since r1; TEST-006/007" }
      - { ac: Spec-AC-05, call: compliant, citation: "syncBase pending journal + resumeSync (merge-cleanup.mjs:404-505); TEST-014 crash arms sync-after-rewrite/sync-after-ff. Residual: NB-r2-1 (concurrent append during an interrupted sync)" }
      - { ac: Spec-AC-06, call: compliant, citation: "worktreeVerdict worktree_missing first (line ~526); PS block harness pid; TEST-011 missing arm, TEST-016 lock under harness pid" }
      - { ac: Spec-AC-07, call: compliant, citation: "deliveredDoneRefs (lines 212-234): status done + links.pr names the PR, branch tail dropped; STATE archived before clear-focus (stateStep); TEST-012 arms (a) other doc (b) draft only (c) other PR + archive cmp. r1 probe re-run: F1 fixed. Residual NB-r2-3 (digit scrape of URL-shaped links.pr)" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-014 step-boundary and in-sync crash resumes converge to control bytes; ledger-merge dedupe makes a repeated re-append idempotent" }
      - { ac: Spec-AC-09, call: compliant, citation: "ps1-quality workflow_dispatch run 38046478732 at 4abc1709: TEST-016 2/2 [+] under Windows PowerShell 5.1 (two legs, 156/0), Windows pwsh 7 and Linux pwsh 7 (log lines 839-841, 1221-1223, 1876-1878, 2455-2457). Deviation listed: evidence is a branch workflow_dispatch, not PR CI as the table row V2 says, at 4abc1709 (4abc1709..93e6be5c touches only spec/INDEX/decisions, so engine and tests are byte-identical)" }
      - { ac: Spec-AC-10, call: compliant, citation: "prompt-diet-ledger.sh +503 entry, TEST-012 pin 59467 -> 59970, pr-preflight pin +503; prompt 2909 -> 3412 B" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 428,
          issue: "resumeSync (fast-forward not done) puts the archived local bytes back ONLY when the live ledger still equals the HEAD blob; otherwise it skips silently, deletes the pending journal and continues. The same shape exists in restore() (line 469) on a failed fast-forward: it overwrites the live ledger with the pre-sync bytes, dropping anything appended in between.",
          failure_scenario: "Reproduced (scratch probe3.sh): origin EVENTS.jsonl carries a dirty local line LOCAL-TAIL; apply is killed at sync-after-rewrite; another session sharing the main checkout appends CONCURRENT; the re-run reports 'sync-base: done (fast-forward ...)' with rc 0 and the final ledger is seed/pr/CONCURRENT: LOCAL-TAIL exists only under docs/ai/archive/merge-cleanup/pr-5/sync/, nothing names it under remaining. Fix: when the live file starts with the HEAD blob, write saved + live.subarray(headBlob.length) (and the same prefix-extend in restore()); else stop with a named reason instead of deleting the journal. Add the concurrent-append arm to TEST-014." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 671,
          issue: "The owner's direction is recorded only inside apply, after the merge already ran, and only when apply gets past planChecks (line 810) and reaches the report step. SKILL_PR step 6 sanctions an agent merge on the operator's explicit, RECORDED direction, and this is the carve the spec's Article 7 deviation relies on.",
          failure_scenario: "Reproduced (scratch probe2.sh arm refuse): /aai-merge 5, preflight exit 10, the printed gh pr merge runs; step 2 apply with AAI_DIRECTION refuses worktree_dirty (an untracked file in the ride) with rc 3, so no directed_merge record exists. A later re-run of apply from a new session without AAI_DIRECTION never writes one. The merge happened with no durable record of the direction. Fix: have the prompt (or a dedicated engine call) append the directed_merge record before it runs the printed merge line, keyed pr+words+head, and let apply only add the merge commit." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 215,
          issue: "linkedPrs extracts every digit run from a links.pr value, so a URL-shaped entry yields extra numbers that can match the merged PR.",
          failure_scenario: "Reproduced (probe2.sh arm urldigits): the delivered doc has id foo, status done, links.pr: [https://github.com/u5/r/pull/77]; merging PR #5 clears focus foo (state: done) although the doc names PR 77. close-work-item writes plain integers, so this needs a hand-written or foreign links.pr. Fix: accept integer entries and a trailing /pull/<n> only." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 407,
          issue: "The pending sync journal is scoped to the PR number's archive dir, and only an apply for that same PR reads it.",
          failure_scenario: "apply --pr 5 is killed at sync-after-rewrite (local ledger tail now only in pr-5/sync/). The owner then runs /aai-merge 6: planSync sees a clean ledger, fast-forwards, and reports done. PR 5's pending.json is never read, and the tail is not re-appended or reported. Fix: syncBase scans docs/ai/archive/merge-cleanup/*/sync/pending.json (or keeps one journal at a fixed path) before planning." }
  cannot_verify:
    - { claim: "Windows parity at the exact PR head 93e6be5c and in PR CI (V2 names PR CI)", closes_with: "ps1-quality and skill-suite pull_request run ids on the PR head; the dispatch run is at 4abc1709 (code-identical)" }
    - { claim: "Get-CimInstance ParentProcessId is the harness pid on a real Windows harness (Claude Code / Codex spawn chain), not an intermediate shell", closes_with: "one live /aai-merge cleanup on Windows with a held ride session lock" }
    - { claim: "Real GitHub shapes of gh pr view (url, statusCheckRollup, mergeStateStatus) and gh pr merge --match-head-commit behaviour", closes_with: "one live directed merge, or recorded gh output fixtures" }
    - { claim: "Suite and mutation results at 93e6be5c (dispatch forbade running suites or mutation-run here)", closes_with: "the concurrent Validation r2 run and mutation-run --replay" }
  overall: pass
```

## Scope and spec

Delta `3dd377cd..93e6be5c` (remediation 4abc1709 and the AC-09 flip 93e6be5c),
read in full: engine, prompt, both test suites, spec amendments, ledger and
diet credits. Regression check over `origin/main...HEAD`: file list
unchanged in kind (no new surfaces), `git ls-files -ci` empty, worktree clean.
Spec: the frozen DRAFT with two unsigned amendments (measurement: heading move,
F2; contract: D3/D4/D8/D9/D10/D11 clarifications), owed sign-off
`fu-amend-directed-merge-and-post-007bae`.

Coaching check: the dispatch named focus areas and the CI claim to verify. It
did not pre-rate anything or exclude scope. I reviewed the full scope.

## Round-1 findings re-checked

- B-1 / F1 (focus over-clear): fixed. I re-ran the round-1 probe as
  `cr-probe/probe2.sh` against 93e6be5c with `AAI_MERGE_CLEANUP_TEST_SEAMS=1`.
  Arm f1 (the PR only edits other-item's doc, focus other-item): `state: noop
  (focus_not_this_ref)`, STATE bytes unchanged. Arm tail (focus foo = branch
  tail, no done doc): noop, bytes unchanged. Arm pos (done doc foo with
  links.pr [5]): cleared, and the origin STATE was archived first.
- NB-1 (sweep vs gh head): fixed. Preflight refuses `head_changed` when the
  local HEAD of the judged checkout is not `headRefOid`, before lane-gate
  runs. TEST-003 adds the arm and a real lane-gate stale-head arm.
- NB-2 (ledger tail crash window): fixed for a kill at either in-sync point
  with no concurrent writer (TEST-014). The concurrent-writer interleaving
  still loses the tail from the live ledger (NB-r2-1, reproduced).
- NB-3 (PS pid parity): fixed. The PS block passes the parent pid (CIM, then
  the Get-Process .Parent fallback), and TEST-016 holds the lock under that pid.
- NB-4 (repo_mismatch, worktree_missing): fixed, with arms in TEST-003,
  TEST-005 and TEST-011.
- F3 (direction unrecorded): fixed on the happy path only. The report and
  saved report carry the direction and the merged head, plus one
  directed_merge record (idempotent). The refusal path is NB-r2-2.
- F4 (AC-09 premature): now done on the native Windows evidence below.
  INFO: the AC-09 Notes cell still says "the row stays implementing until
  those run ids exist", which contradicts its own status. The Evidence cell
  cites local logs and puts the run id only in Notes.
- F5 (GH_NODE seam in production): fixed. All three seams go through
  `seam()`, which is inert without `AAI_MERGE_CLEANUP_TEST_SEAMS=1`. TEST-005
  proves this both ways, with a positive control.

## CI claim verification (run 38046478732)

`gh run view`: workflow_dispatch, headSha 4abc1709, conclusion failure. Jobs:
Windows "parse-check + ... both engines" failure, WSL1 5.1 leg success, Linux
pwsh 7 gate failure. From the log:
- TEST-016 has two `[+]` results on every engine: Windows PowerShell 5.1
  (156 passed / 0 failed), WSL1 5.1 (156/0), Windows pwsh 7 and Linux pwsh 7.
- Every failure is a "fatal: empty ident name (for <>) not allowed" fixture
  failure (11 occurrences): the pr-preflight matrix arms, worktree seed
  parity, and update TEST-009. Windows pwsh 7 had 151/5 and Linux had 154/6.
- None of those files is in this ride's diff. The only `.Tests.ps1` the ride
  touches is `aai-merge-cleanup.Tests.ps1`, and its `ps1-quality.yml` change
  is two path-filter lines. Recent push and pull_request ps1-quality runs on
  main are green (38003454059, 37995103581), so the claim holds.

## Focus: Constitution Article 7 vs SKILL_PR step 6

Article 7 is still unedited. It names lane merge as "the sole sanctioned
exception". SKILL_PR step 6 describes the operator-directed merge with the
`AAI_OPERATOR_MERGE` marker "on the operator's explicit, recorded direction".
The spec discloses the deviation and leaves ratification to the owner, which
is correct for an L3 surface. The engine still never runs `gh pr merge`. The
prompt runs only the printed `--match-head-commit` line, and only on an
explicit `/aai-merge <n>`. The one gap against step 6's wording is that the
direction is recorded after the merge, and only on the apply happy path
(NB-r2-2).

## Warning dispositions (H6, recommended; orchestrator records)

- NB-r2-1 (interrupted sync + concurrent append drops the local tail from the
  live ledger): remediate-in-tree (prefix-extend restore plus a TEST-014 arm).
  Otherwise promote P2 `fu-merge-sync-resume-concurrent-append`.
- NB-r2-2 (direction recorded only after the merge, and lost on an apply
  refusal): remediate-in-tree (record before the printed merge runs).
  Otherwise promote P2 `fu-merge-direction-recorded-before-merge`.
- NB-r2-3 (links.pr digit scrape): remediate-in-tree (one-line parser
  tightening plus an arm). Otherwise promote P3 `fu-merge-linked-pr-parse`.
- NB-r2-4 (pending journal only read by the same PR): promote P3
  `fu-merge-sync-pending-cross-pr`. Alternatively `accepted residual: needs a
  hard kill mid-sync followed by abandoning that PR's re-run; bytes stay in
  the per-PR archive`.

## Next steps

No BLOCKING findings. Both verdicts pass, so the PASS is conditional on the
four WARNING dispositions above. The owner sign-off on the contract amendment
is still owed at merge (`fu-amend-directed-merge-and-post-007bae`).

Probes (outside the worktree):
`/private/tmp/claude-501/-Users-ales-Projects-aai/687516a7-9bb3-4b30-9ccf-230f17be6426/scratchpad/cr-probe/probe2.sh`, `.../cr-probe/probe3.sh`.
