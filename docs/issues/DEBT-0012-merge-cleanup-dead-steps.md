---
id: merge-cleanup-dead-steps
type: techdebt
number: 12
status: done
links:
  pr:
    - TBD
  commits:
    - 733db13489c49ddb8a777c223722e7f94245ebae
---

# Tech Debt: delete merge-cleanup steps that never act, and gates GitHub already enforces

## Debt Summary
- 8 apply journals (`docs/ai/archive/merge-cleanup/pr-448..457`) show 4 steps
  that have never done anything. Each step reported a noop or never ran
  (verified by grep for "done" per step):
  - `archive-drafts`: 0/8
  - `state`: 0/8 (`focus_not_this_ref`)
  - `index-audit`: 0/8 (`index_current`)
  - `reexec`: 0 (`reexec` journal entries with status done: 0)
- Preflight duplicates what GitHub already enforces: `checks_failing`,
  `not_mergeable` and the PR-side `head_changed`. Branch protection and
  `--match-head-commit` already do these.
- `archive-runtime` copies 25 to 1384 gitignored files per merge, 34 MB for
  PR #455, plus a copy into the main checkout. Nobody reads it.
- The report is also saved as a file, and on two PRs (#452, #454) it was
  written twice.

## Root Cause
- These steps were added as forward guards in SPEC-0218, SPEC-0221 and
  SPEC-0223. Since SPEC-0224 the focus is cleared at close, and CI already
  runs the docs audit and index check.

## Current Cost / Risk
- About 350 engine lines in `merge-cleanup.mjs` (1972 lines), the matching
  parts of `test-aai-merge-cleanup.sh` (3436 lines), and SKILL_MERGE text.
  Every future change to merge-cleanup has to keep these steps working.

## Target State
- **Deleted:** `archive-drafts`, `state`, `index-audit`, `reexec`, and the
  duplicate preflight gates. An unexpected leftover draft becomes one report
  line from `classifyDrafts`.
- **archive-runtime:** keeps only the ride's STATE file, or nothing.
- **Report:** stdout only.
- **Branch deletion:** `delete-branch` and `delete-remote-branch` merge into
  one step.

## Scope
- In scope: `.aai/scripts/merge-cleanup.mjs`, `.aai/SKILL_MERGE.prompt.md`,
  `tests/skills/test-aai-merge-cleanup.sh` (delete tests of removed steps),
  and the profile/suite-map/diet entries.
- Out of scope: ledger handling in sync-base (handled by
  amendment-signoff-implied-by-merge and possibly a later ledger-location
  decision), and the worktree and submodule proof.

## Plan / Migration
- Delete one step at a time with its tests. The journal reader must tolerate
  old journals that name removed steps.
- Rollback: revert.

## Verification
- `/aai-merge` on a real PR still merges, syncs base, removes the worktree
  and deletes both branches. The journal lists only the remaining steps.
- `wc -l` of merge-cleanup.mjs and its suite drops by at least the deleted
  steps. The merge-cleanup suite stays green.

## Constraints / Risks
- Low: the journals show these steps had no effect in 8 of 8 runs.

## Notes
- Owner direction 2026-10-12: "4 Smazat mrtvé kroky". Ride order: this one
  first, then amendment-signoff-implied-by-merge, which also edits
  merge-cleanup.
