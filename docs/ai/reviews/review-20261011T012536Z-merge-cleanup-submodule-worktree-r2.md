# Code review — merge-cleanup-submodule-worktree (round 2, delta)

```yaml
review:
  scope: "git diff origin/main (uncommitted, worktree fix/merge-cleanup-submodule-worktree) + untracked intake/spec; delta since r1 = .aai/scripts/merge-cleanup.mjs, tests/skills/test-aai-merge-cleanup.sh, docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md, docs/ai/decisions.jsonl; paths: .aai/scripts/merge-cleanup.mjs tests/skills/test-aai-merge-cleanup.sh .aai/SKILL_MERGE.prompt.md tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-pr-preflight.sh docs/issues/ISSUE-0097-merge-cleanup-submodule-worktree.md docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md"
  spec: docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-cleanup.mjs:810-830 unchanged since r1; TEST-028 PASS (reviewer re-run r2)" }
      - { ac: Spec-AC-02, call: compliant, citation: "worktreeVerdict merge-cleanup.mjs:710-722; TEST-029 PASS (r2 re-run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "amended AC row (spec:285) adds 'the listing of a submodule's ignored files fails'; merge-cleanup.mjs:666-669 ignoredListing + :697 push unverifiable; TEST-030 ignored_ls_fails arm PASS (r2 re-run); reviewer mutation 'if (false && ignoredListing...' on a scratch copy -> TEST-030 FAIL 'plan exited 0, want 3' (arm bites)" }
      - { ac: Spec-AC-04, call: compliant, citation: "submoduleIgnored/archiveSubmoduleIgnored merge-cleanup.mjs:770-799; TEST-031 PASS (r2 re-run)" }
      - { ac: Spec-AC-05, call: compliant, citation: "removeWorktree late verify merge-cleanup.mjs:810-818; TEST-032 PASS (r2 re-run)" }
      - { ac: Spec-AC-06, call: compliant, citation: "runPreflight unchanged since r1 (now also reports an ignored-listing failure as cleanup blocked); TEST-033 PASS (r2 re-run)" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_MERGE.prompt.md and ledger unchanged since r1 (mtime 02:33/02:29 local < r1 03:10); TEST-034 PASS; test-aai-prompt-diet.sh exit 0; test-aai-pr-preflight.sh exit 0 (r2 re-runs)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 775,
          issue: "NB-1 is closed only for a failure that persists across calls: submoduleIgnored still 'continue's on a failed listing, and its comment ('already a submodule_unverifiable blocker') is true only if the same call failed in the preceding worktreeVerdict",
          failure_scenario: "listing of sub succeeds in the first worktreeVerdict, fails transiently in archiveSubmoduleIgnored (nothing archived or named for sub), succeeds again in the late worktreeVerdict; --force then deletes sub's ignored files with no manifest or removed.jsonl line. Needs a flapping git failure in exactly that call, so narrow; the seam fails every call and cannot reach it" }
    info:
      - "NB-2 follow-up fu-merge-cleanup-large-ignored-archive is named by the orchestrator but no follow_up record with that id exists in docs/ai/decisions.jsonl yet (grep count 0): it is suggested, not filed, until follow-ups.mjs add runs."
      - "The 01:15:01Z amendment says the ignored-listing failure gives 'late check exit 4'; no test exercises the late-check path for this kind (TEST-030 is plan/apply refusal only). Follows by construction (late check is the same worktreeVerdict)."
  cannot_verify:
    - { claim: "Native Windows forced removal of a submodule worktree (spec R2, D8 named Pester skip)", closes_with: "a Windows CI/Pester run of apply on a submodule fixture" }
    - { claim: "Linux CI green for TEST-028..034 incl. the new ignored_ls_fails arm; reviewer re-runs were on macOS", closes_with: "skill-suite.yml run on the PR head" }
    - { claim: "F1-F5 git behaviour on git versions older than the measured 2.54", closes_with: "re-measure on the CI runner's git and the oldest supported git" }
    - { claim: "Human-editor writes in the verify -> --force window and ignored-file writes in the archive -> --force window (spec R1 as widened)", closes_with: "not closable by test; accepted by spec" }
  overall: pass
```

## Scope and spec

- Worktree `/Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree`, branch
  `fix/merge-cleanup-submodule-worktree`, uncommitted diff vs `origin/main` plus the untracked
  intake and spec. Round 1: `docs/ai/reviews/review-20261011T011054Z-merge-cleanup-submodule-worktree.md`.
- Delta identification (no r1 commit exists): by mtime against the r1 report (03:10:54 local),
  only `.aai/scripts/merge-cleanup.mjs` (03:13:42), `tests/skills/test-aai-merge-cleanup.sh`
  (03:14:28), the spec (03:15:01) and the ledgers changed. `SKILL_MERGE.prompt.md`,
  `prompt-diet-ledger.sh`, `test-aai-prompt-diet.sh`, `test-aai-pr-preflight.sh` and the intake
  predate r1 and are as reviewed there. Ledgers: `EVENTS.jsonl` +7, `decisions.jsonl` +14,
  `test-runs.jsonl` +1, zero removed lines in each (pure appends).
- Dispatch note: the dispatch named the delta files and the orchestrator's dispositions; it did
  not pre-rate severity or exclude areas. The full scope was re-checked.

## What changed since r1

1. `merge-cleanup.mjs` new `ignoredListing(wtPath, member)` (:666-669) wraps the per-submodule
   `ls-files --others --ignored --exclude-standard --directory -z`, with test seam
   `AAI_MERGE_CLEANUP_FAIL_IGNORED_LS=<member>` (gated by the existing `seam()` / TEST_SEAMS switch).
2. `submoduleBlockers` (:697) now pushes `{kind: unverifiable, fact: 'git ls-files --ignored failed'}`
   for a member whose ignored listing fails. It sits after the stash check without a preceding
   `continue`, so it runs for every member that reached the stash check; members that stopped
   earlier already carry a blocker. Effect: `plan`/`apply` refuse exit 3, the late check stops
   exit 4, preflight prints `cleanup blocked: submodule_unverifiable sub (...)`.
3. `submoduleIgnored` (:774-775) uses `ignoredListing` and keeps `continue` on failure with a
   comment that the member is already a blocker (see NB-1r2).
4. `test_030` gains arm `ignored_ls_fails|submodule_unverifiable|sub`: ignored files placed via
   `ignore_in_sub`, seam set, plan and apply refuse with the reason and path, the env is unset
   afterwards, and `sub/x.local` and `sub/ign/out.bin` are asserted to survive.
5. Spec: Spec-AC-03 row and TEST-030 row amended for the new refusal; R1 widened to state the
   ignored-file archive-to-force window. Both recorded as `spec_amendment` (01:15:01Z, contract,
   `tracked_by: fu-amend-merge-cleanup-submodule-d6d779`, owner sign-off owed).

## Verification run by the reviewer (r2)

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-0xx`
  for 028, 029, 030, 031, 032, 033, 034 and regressions 010, 011: all exit 0 / PASS.
- `test-aai-pr-preflight.sh` exit 0; `test-aai-prompt-diet.sh` exit 0.
- `spec-lint.mjs --path <spec>`: LINT PASS, 0 findings. `node --check merge-cleanup.mjs`, `bash -n` on the suite: ok.
- Mutation (scratch copy under the session scratchpad, shipping tree untouched): disabling the
  new `submoduleBlockers` push -> TEST-030 FAIL `plan exited 0, want 3` on the ignored_ls_fails arm.
  The arm bites and has a positive control (the refusal names `sub (` with `submodule_unverifiable`,
  which only the seamed member produces in that world).

## R1 wording (NB-4 disposition) — verified

Spec R1 now reads, after the two-spawn sentence: "For ignored files the window is wider by design
(D3/D4 order): a file that becomes ignored content, or changes, after `archiveSubmoduleIgnored`
listed it and before the `--force` call is deleted unarchived ... That span covers the archive copy
loop and the late check, not milliseconds." This matches the code (late `worktreeVerdict` does not
re-list ignored content) and closes NB-4's record gap.

## Findings

No BLOCKING findings.

- NB-1r2 (P3, NON-BLOCKING) merge-cleanup.mjs:775 — the remediation fails closed when the listing
  failure is persistent (what the seam models), but `submoduleIgnored` still skips a member on a
  failed listing. A failure that occurs only in the archive call, with the late verify's listing
  succeeding, archives and names nothing for that member and `--force` deletes its ignored files.
  The comment on :775 states an invariant that holds only across consistent calls.
  Recommended disposition: remediate-in-tree (replace `continue` with
  `stop('submodule_unverifiable', \`${member} (unverifiable: git ls-files --ignored failed)\`)`, or
  have `submoduleIgnored` return the failure and let `archiveSubmoduleIgnored` stop); acceptable
  alternative: accepted residual (P3, needs a flapping git failure in one specific call, no observed
  bite) with R1/R6 naming it.

INFO:
- The NB-2 follow-up `fu-merge-cleanup-large-ignored-archive` (with NB-5 folded in) is not yet in
  `docs/ai/decisions.jsonl`; until `follow-ups.mjs add` exits 0 for it, it is `suggested:`, and H6
  disposition (b) for NB-2/NB-5 is not yet recorded.
- r1 NB-3 and NB-6 remain accepted residuals (lines in the r1 report); no code changed for them.
- r1 INFO on `test_033`'s `grep -n | cut` under pipefail is unchanged.

accepted residual: NB-3 — preflight-only warning mislabel for a missing ride directory; apply refuses worktree_missing, no false record. (carried from r1)
accepted residual: NB-6 — old-style in-tree submodule .git with orphaned nested module dirs; legacy layout, same class as R6. (carried from r1)

## Warning dispositions (H6)

| Warning | Disposition | Artifact |
|---|---|---|
| r1 NB-1 | remediated in tree | merge-cleanup.mjs:666-669, :697; TEST-030 ignored_ls_fails; amendment 01:15:01Z |
| r1 NB-2 | follow-up (orchestrator) | suggested: fu-merge-cleanup-large-ignored-archive — not yet in ledger |
| r1 NB-3 | accepted residual | r1 report line, repeated above |
| r1 NB-4 | accepted residual + R1 widened | spec R1; amendment 01:15:01Z |
| r1 NB-5 | folded into NB-2 follow-up | same suggested id |
| r1 NB-6 | accepted residual | r1 report line, repeated above |
| r2 NB-1r2 | recommended remediate-in-tree (or accepted residual) | orchestrator to record |

## Next steps

1. File `fu-merge-cleanup-large-ignored-archive` via `follow-ups.mjs add` (NB-2 + NB-5).
2. Decide NB-1r2 (one-line `stop` in place of `continue`, extend the TEST-030 arm or add a seam
   that fails only in the archive call), or record it as an accepted residual.
3. Owner sign-off on the 01:15:01Z amendments rides on the existing `fu-amend-merge-cleanup-submodule-d6d779`.
4. Product doc and CHANGELOG after LOOP COMPLETE; flip the AC Status table at close; CI on the PR head.
