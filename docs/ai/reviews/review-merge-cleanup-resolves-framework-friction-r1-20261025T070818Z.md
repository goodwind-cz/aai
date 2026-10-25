```yaml
review:
  scope: fb171891..30e17436 (branch change/merge-cleanup-resolves-framework-friction, worktree /private/tmp/aai-merge-friction)
  spec: docs/specs/SPEC-DRAFT-spec-merge-cleanup-resolves-framework-friction.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "lib/merge-outcomes.mjs:25-84 OUTCOME_TABLE, :126-147 classify; TEST-2901/TEST-2902 green (TEST-2901 re-run here, rc 0)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "merge-cleanup.mjs:410-413 staged overlap returns held with option null: take_incoming is accepted, recorded resolved and has no effect (probe P1: main HEAD stays, roadmap untouched, exit 0). PR #485 fixture itself compliant (TEST-2903/2904)" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:250-257 doneDocsBetween proof merge_commit; TEST-2905/2906" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-cleanup.mjs:265-284 classifyDrafts, lib:205-211 compareDraft, :1241-1262 archiveDrafts; TEST-2907..2910 (deviation N2: null ids compare equal)" }
      - { ac: Spec-AC-05, call: compliant, citation: "lib:169-177 choiceFor/parseDecide, merge-cleanup.mjs:203 usage gate, :129-139 choices append once; SKILL_MERGE both blocks; TEST-2911 re-run rc 0, TEST-2912/2913" }
      - { ac: Spec-AC-06, call: compliant, citation: "removeWorktree :1066-1069 keep, deleteBranch :1191-1195 CAS + keepLocalBranch; TEST-2914..2917 (see N1 for an ordering regression the rows do not cover)" }
      - { ac: Spec-AC-07, call: non-compliant, citation: "merge-cleanup.mjs:104-106,124 attemptsFile is null outside apply so preflight gh_read_failed is state retry on every run (probe P0: 4 runs, 4x state retry); D2 lists gh_read_failed as 'both' with 'retry, then external'. Apply-mode chain compliant (TEST-2918/2919 re-run rc 0)" }
      - { ac: Spec-AC-08, call: non-compliant, citation: "staged overlap answered keep_local prints 'Cleanup: complete.' with no Kept: line while sync-base is retained and main is unsynced (probe P1, merge-cleanup.mjs:459-462)" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2924 green log; spec-amend list --strict rc 0; amendments on SPEC-0218/0221/0223 in decisions.jsonl" }
      - { ac: Spec-AC-10, call: compliant, citation: "SKILL_MERGE diff, AGENTS.md:311-313, PROFILES/suite-map; TEST-2922/2923 re-run rc 0; engine 1487/1490 lines, library 283/520" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 124,
          issue: "Retry budget exists only in apply mode: attemptsFile() returns null when mode != apply, so raise() uses { retry: true } for every preflight refusal; gh_read_failed/az_read_failed in preflight never fall back to external. SKILL_MERGE step 1 routes exit 3 'as in step 2', and step 2 says state retry 'run the same block again now, no question (the engine bounds the retries)' - an overclaim for preflight.",
          failure_scenario: "gh auth expired while the owner runs /aai-merge <n>: preflight prints REFUSE gh_read_failed + OUTCOME state retry on every run (reproduced 4/4 with a failing gh stub); the agent following the prompt re-runs preflight without end and never relays the 'check the GitHub CLI login' action." }
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 410,
          issue: "Staged overlap (and the non-regular-file untracked_collision at :447-448) raise an overlap decide with keep_local/take_incoming but return held with option null. raise() still marks the outcome resolved and records the choice, syncBase (:459-462) adds no Kept line because option != keep_local. Result: take_incoming has no effect, keep_local leaves no Kept line, and the summary says 'Cleanup: complete.' with sync-base retained.",
          failure_scenario: "Reproduced (probe P1, ROADMAP_WORLD + ship_append_foo + git add roadmap): run 1 exit 6 with the menu; --decide id=keep_local -> exit 0 'Cleanup: complete.' no Kept line; fresh world --decide id=take_incoming -> exit 0 'Cleanup: complete.', main HEAD 8a897b23 != merge commit 33bf0668, roadmap not taken. The owner is told cleanup completed when main was never synced, and his take_incoming choice is silently ignored." }
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 616,
          issue: "plan.replace now holds GENERATED_PROJECTIONS and answered-take_incoming overlap files, and syncBase reads each with an unguarded fs.readFileSync(abs). A file that is dirty because it was deleted locally throws ENOENT outside archiveFile's try, an uncaught exit 1 with no OUTCOME line. On fb171891 the same state was a clean REFUSE overlap (exit 3).",
          failure_scenario: "Reproduced (probe P2, TEST-2910 world, rm docs/ai/overview-data.json in the main checkout): apply exits 1 with a node stack trace, and every re-run does the same. reconcile-origin, remove-worktree and delete-branch never run, and the prompt has no route for exit 1. The same applies to a locally deleted non-projection file answered take_incoming." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 589,
          issue: "planChecks no longer runs planSync before the step loop, so syncBase now calls resumeSync (pending-journal recovery) BEFORE planSync detects origin_not_on_base / base_diverged. resumeSync's else-branch assumes 'HEAD != pending.head means the fast-forward happened' and runs mergeLedgerTails + regenIndex into the checkout, then deletes the pending journal. Before this change the protected condition refused the whole run first (exit 3, nothing written).",
          failure_scenario: "Run 1 is interrupted after sync-after-rewrite (pending journal present, HEAD unchanged); the owner then checks out another branch (or commits) in the main checkout; run 2 appends the archived ride ledger tail into that branch's EVENTS.jsonl, regenerates its docs/INDEX.md and deletes the journal, and only then keeps sync-base as origin_not_on_base. No bytes are lost (ledger-merge keeps ours, tail archived), but the run writes into a protected checkout. Fix: check branch == base and HEAD an ancestor of target before resumeSync's else-branch. Recommended disposition: remediate in tree (P2)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/merge-outcomes.mjs, line: 208,
          issue: "compareDraft treats two missing frontmatter ids as equal (null === null), but D3 requires 'exactly one such doc whose frontmatter id equals the draft's frontmatter id'.",
          failure_scenario: "An untracked docs/issues/CHANGE-DRAFT-foo.md with no frontmatter and an unrelated CHANGE-0012-foo.md without an id: the draft is compared rather than left untouched. If the texts differ, the owner gets a divergent_draft menu about another item's work, the friction this scope removes. If archive_remove is chosen it is archived first, so no bytes are lost. Recommended disposition: remediate in tree (one-line guard `if (!fmDraft.id || ...)`), P3." }
  cannot_verify:
    - { claim: "The Pester TEST-016 dirty-worktree It and TEST-2913 PowerShell block pass on Windows", closes_with: "the PR's Windows CI leg (pwsh/Pester 5 not run in this review)" }
    - { claim: "The full merge-cleanup suite and neighbour suites are green at 30e17436", closes_with: "the parallel Validation full sweep (only TEST-2901/2911/2918/2919/2922/2923 re-run here, all rc 0)" }
    - { claim: "An agent harness follows the step-2 menu and asks it once", closes_with: "a live /aai-merge run; TEST-2912's router is a test double" }
  overall: fail
```

# Code review: CHANGE-0227, merge cleanup resolves framework friction

security_relevant: false

- Scope: `git diff fb171891..30e17436`, 16 files, in worktree `/private/tmp/aai-merge-friction`. The scope was handed off by ref. The dispatch named focus areas but did not pre-rate findings or exclude any area, so the full scope was reviewed.
- Spec: `docs/specs/SPEC-DRAFT-spec-merge-cleanup-resolves-framework-friction.md` (frozen). `spec-lint` passes, `spec-amend list --strict` exits 0 and `check-test-registration` exits 0.

## Answers to the focus questions

- **Backup before change.** Yes on the normal paths. `archiveFile` reads the archive copy back before any unlink. A failed archive now stops with `archive_failed` instead of an uncaught throw (`:306-324`). Drafts are archived, then a crash point, then unlinked (`:1245-1249`). In sync-base, each file is archived and its bytes saved before the HEAD-blob rewrite, and a failed fast-forward restores them (`:615-641`). For take_incoming on an untracked collision, the file is archived and then removed, and it is restored if the fast-forward fails.
- **Can a path destroy uncommitted work, a diverged main or a moved branch?** I found no destructive path:
  - Removing a worktree still re-runs the strict late re-check before `--force`.
  - The local branch is deleted only with `update-ref -d <ref> <head>` (compare-and-swap), and only when the tip equals the PR head. A tip mismatch or a kept worktree keeps the branch.
  - The origin branch is deleted only by lease.

  One regression writes into a protected checkout without destroying bytes (N1). One regression crashes instead of refusing (B3).
- **Is the retry counter bounded?** In apply mode, yes: at most 2 `retry` states per chain, a `no_progress` fingerprint check, a `reset` only through an explicit `retry` choice, and the file lives in `<git-common-dir>/aai-merge-cleanup/pr-<n>/attempts.jsonl`. In preflight there is no bound (B1).
- **Does `--decide` / AAI_DECIDE accept only the listed choices?**
  - The syntax is gated: the strict regex in `parseDecide` gives exit 2, and plan or preflight with `--decide` gives exit 2.
  - An option the item does not offer gives `IGNORED option_not_offered`.
  - An empty `AAI_DECIDE` is skipped in both blocks.
  - Exception: one offered option has no effect (B2).
- **Are the "exit 3, nothing changed" contracts amended?** Yes. SPEC-0218, SPEC-0221 and SPEC-0223 carry `spec_amendment` records with owner-signature follow-ups, and the prior suite arms are rewritten (TEST-2924). The D12 disclosure does not mention SPEC-0222 D6, whose `owner decision, not deleted` remaining-line wording changed. The SPEC-0222 AC rows still hold, because the kept line still names `origin/<b>` and the reason, so this is an INFO-level disclosure gap.
- **Does the prompt describe exactly what the code compares?** No D10 words appear (grep clean). One overclaim: "(the engine bounds the retries)" is false on the preflight path that step 1 routes into step 2 (B1).

## Deviations from the frozen spec (listed even where reasonable)

1. D7: the fingerprint hashes `reason:subject` of the last raised item, not "the sorted outcome ids". The behaviour is equivalent for the halting retry path. INFO.
2. D3: null frontmatter ids are treated as matching (N2).
3. D2/D7: `gh_read_failed` / `az_read_failed` are marked "both", but in preflight they never reach the fallback class (B1).
4. D4: the staged overlap and the non-regular untracked collision offer options whose effects are not implemented (B2).
5. D12: SPEC-0222 D6 is not named in the disclosure. INFO.

## Probes (scratch mirror, never the shipping tree)

- P0: preflight with a failing `gh` stub, run 4 times. Each run gave `REFUSE gh_read_failed`, `OUTCOME state retry` and exit 3.
- P1: staged roadmap overlap. Run 1 exited 6. `keep_local` then gave exit 0, "Cleanup: complete." and no Kept: line. On a fresh world, `take_incoming` gave exit 0, "Cleanup: complete.", and HEAD did not move to the merge commit.
- P2: a locally deleted `docs/ai/overview-data.json` that the merge also changed. Apply exited 1 with an ENOENT stack trace, and the re-run did the same.
- Mirror: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr11root` (a copy of the suite with the probe functions added; `.aai` is a symlink to the worktree).

## Warning dispositions (H6)

- N1 (resumeSync runs before the protected-condition check): remediate in tree. P2. The fix is small: a branch and ancestry check before resumeSync's else-branch.
- N2 (null ids compare equal): remediate in tree. P3, a one-line guard.
- INFO items (D7 fingerprint key, SPEC-0222 disclosure, duplicate pairs for one id printing `option_not_offered`): no disposition required.

## Next steps

1. B1: record attempts for preflight as well (key them by PR under the git dir of `--origin`/cwd), or classify preflight read failures as `external` directly. In either case, correct the step-2 sentence so it states which runs the engine bounds.
2. B2: either offer no `take_incoming` for a staged or non-regular item (make it `external` or `kept`), or implement the effect. In every held path, add a Kept: line when the step is retained. Add a test that answers both options on the staged arm (TEST-046 checks only the first run).
3. B3: guard `readFileSync` in the plan.replace loop. A locally deleted file should be archived as absent (or kept as a decide/overlap item), never an uncaught throw. Add an arm with a deleted projection.
4. Re-review after remediation.
