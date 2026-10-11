# Code review — merge-cleanup-submodule-worktree (round 3, delta)

```yaml
review:
  scope: "git diff origin/main (uncommitted, worktree fix/merge-cleanup-submodule-worktree) + untracked intake/spec; delta since r2 = .aai/scripts/merge-cleanup.mjs, tests/skills/test-aai-merge-cleanup.sh, docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md, docs/ai/decisions.jsonl; paths: .aai/scripts/merge-cleanup.mjs tests/skills/test-aai-merge-cleanup.sh .aai/SKILL_MERGE.prompt.md tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-pr-preflight.sh docs/issues/ISSUE-0097-merge-cleanup-submodule-worktree.md docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md"
  spec: docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "removeWorktree unchanged apart from the archive call path; TEST-028 PASS (r3 re-run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "worktreeVerdict/submoduleBlockers unchanged since r2; TEST-029 PASS (r3 re-run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "ignoredListing default phase 'verify' keeps the proof path (merge-cleanup.mjs:667-670, :699); TEST-030 incl. ignored_ls_fails arm PASS (r3 re-run)" }
      - { ac: Spec-AC-04, call: compliant, citation: "submoduleIgnored :772-788 / archiveSubmoduleIgnored :793-804; TEST-031 PASS (r3 re-run)" }
      - { ac: Spec-AC-05, call: compliant, citation: "amended row spec:287; merge-cleanup.mjs:779 stop('submodule_unverifiable', ...) on a failed listing; archiveSubmoduleIgnored passes phase 'archive' (:795); TEST-032 archive-listing arm PASS; reviewer mutation stop->continue on a scratch copy -> TEST-032 FAIL 'archive-listing arm: apply exited 0, want 4' (arm bites)" }
      - { ac: Spec-AC-06, call: compliant, citation: "runPreflight unchanged since r2; TEST-033 PASS (r3 re-run)" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_MERGE.prompt.md, prompt-diet ledger/suite, pr-preflight suite unchanged since r2 (mtimes 02:29-02:49 local < r2 03:26); TEST-034 PASS (r3 re-run)" }
  code_quality:
    verdict: pass
    findings: []
    info:
      - "plan-mode PLANNERS['remove-worktree'] (merge-cleanup.mjs:1193, phase 'verify') now reaches stop() on a listing failure, so a read-only plan whose listing fails only in that call prints STOPPED and exits 4 rather than omitting the member. Fail-closed, nothing written, nothing lost; a persistent failure is refused exit 3 earlier by the proof (TEST-030). Exit-code semantics only (exit 4 = 'earlier steps wrote'), no failure scenario with harm."
      - "TEST-032's mutation column still names only the late-verify mutation; the new arm's mutation (stop -> continue at :779) is verified here but not recorded in the spec's mutation column."
  cannot_verify:
    - { claim: "Native Windows forced removal of a submodule worktree (spec R2, D8 named Pester skip)", closes_with: "a Windows CI/Pester run of apply on a submodule fixture" }
    - { claim: "Linux CI green for TEST-028..034 incl. the ignored_ls_fails and archive-listing arms; reviewer re-runs were on macOS", closes_with: "skill-suite.yml run on the PR head" }
    - { claim: "F1-F5 git behaviour on git versions older than the measured 2.54", closes_with: "re-measure on the CI runner's git and the oldest supported git" }
    - { claim: "Human-editor writes in the verify -> --force window and ignored-file writes in the archive -> --force window (spec R1 as widened)", closes_with: "not closable by test; accepted by spec" }
  overall: pass
```

## Scope and spec

- Worktree `/Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree`, branch
  `fix/merge-cleanup-submodule-worktree`, uncommitted diff vs `origin/main` plus the untracked
  intake and spec. Prior rounds: `review-20261011T011054Z-...md` (r1), `review-20261011T012536Z-...-r2.md` (r2).
- Delta identified by mtime against the r2 report (03:26:17 local): `merge-cleanup.mjs` (03:36:11),
  `test-aai-merge-cleanup.sh` (03:35:44), the spec (03:38:32), and the ledgers. All other scope files
  predate r2. Ledgers vs origin/main: 0 removed lines in `EVENTS.jsonl`, `decisions.jsonl`,
  `tests/test-runs.jsonl` (pure appends).
- Dispatch note: the dispatch named the delta and restated prior dispositions; it did not pre-rate
  severity of new findings or exclude areas. The full scope was re-checked for regression.

## What changed since r2 (NB-1r2 remediation)

1. `ignoredListing(wtPath, member, phase = 'verify')` gains a phase argument and a second seam
   `AAI_MERGE_CLEANUP_FAIL_IGNORED_LS_AT=<phase>`: with it set, the failure fires only in that phase.
   Without it, behaviour is as in r2 (fails in every call).
2. `submoduleIgnored(wtPath, phase = 'verify')` now calls `stop('submodule_unverifiable', '<member>
   (unverifiable: git ls-files --ignored failed)')` instead of `continue` on a failed listing. The
   listing loop runs before any archive copy, so the stop happens before this step writes anything.
3. `archiveSubmoduleIgnored` passes phase `'archive'`; the plan-targets caller keeps the default `'verify'`.
4. TEST-032 gains an archive-listing arm: ignored files in sub, both seams set with `_AT=archive`;
   asserts exit 4, `STOPPED submodule_unverifiable sub`, ride dir and `sub/x.local`, `sub/ign/out.bin`
   survive; a re-run without seams exits 0 and removes the ride.
5. Spec-AC-05 and TEST-032 rows amended; `spec_amendment` record at 01:38:32Z, contract class,
   `tracked_by: fu-amend-merge-cleanup-submodule-d6d779` (verified in `docs/ai/decisions.jsonl` tail).

NB-1r2's failure scenario (listing passes in the proof, fails in the archive call, passes in the late
verify, `--force` deletes unarchived files) is now closed: the archive-call failure stops exit 4.

## Verification run by the reviewer (r3)

- `node --check merge-cleanup.mjs`, `bash -n` on the suite: ok.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-0xx`
  for 028, 029, 030, 031, 032, 033, 034 and regressions 010, 011: all rc 0 / PASS.
- `spec-lint.mjs --path <spec>`: LINT PASS.
- Mutation (scratch copy under the session scratchpad, removed afterwards; shipping tree untouched):
  `stop(...)` at :779 replaced by `continue` -> TEST-032 FAIL `archive-listing arm: apply exited 0,
  want 4`. The arm bites; its positive control is the exit code plus the named STOPPED reason.

## Findings

No BLOCKING and no NON-BLOCKING findings.

INFO (non-gating, no failure scenario with harm):
- Plan-mode `remove-worktree` planner (:1193) now stops exit 4 on a listing failure that occurs only
  in that call; previously the member was silently omitted from the plan listing. Fail-closed and
  read-only; only the exit code's meaning ("earlier steps wrote") is slightly off for `plan`.
- TEST-032's mutation column does not record the new arm's stop->continue mutation (verified here).

## Warning dispositions (H6)

| Warning | Disposition | Artifact |
|---|---|---|
| r1 NB-1 | remediated in tree | merge-cleanup.mjs:667-670, :699; TEST-030 ignored_ls_fails; amendment 01:15:01Z |
| r1 NB-2 + NB-5 | follow-up (orchestrator) | suggested: fu-merge-cleanup-large-ignored-archive — not yet in the ledger; must be filed via follow-ups.mjs add before close |
| r1 NB-3 | accepted residual | see line below |
| r1 NB-4 | accepted residual + R1 widened | spec R1; amendment 01:15:01Z |
| r1 NB-6 | accepted residual | see line below |
| r2 NB-1r2 | remediated in tree | merge-cleanup.mjs:779, :795; TEST-032 archive-listing arm; amendment 01:38:32Z |

accepted residual: NB-3 — preflight-only warning mislabel for a missing ride directory; apply refuses worktree_missing, no false record. (carried from r1)
accepted residual: NB-6 — old-style in-tree submodule .git with orphaned nested module dirs; legacy layout, same class as R6. (carried from r1)

## Next steps

1. File `fu-merge-cleanup-large-ignored-archive` via `follow-ups.mjs add` (NB-2 + NB-5).
2. Owner sign-off on the 01:15:01Z and 01:38:32Z amendments rides on `fu-amend-merge-cleanup-submodule-d6d779`.
3. Product doc and CHANGELOG after LOOP COMPLETE; flip the AC Status table at close; CI on the PR head.
