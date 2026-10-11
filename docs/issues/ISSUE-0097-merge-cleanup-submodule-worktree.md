---
id: merge-cleanup-submodule-worktree
type: issue
number: 97
status: done
links:
  pr:
    - TBD
  commits:
    - 37946f0563d22a82bc5707552e4f6be6bfcc786e
---

# /aai-merge cleanup stops on a ride worktree with submodules, and the stop invites a forbidden manual --force

## Summary
- In a downstream project with git submodules (`apps/fh-*`), `/aai-merge 829` merged the PR and ran `merge-cleanup.mjs apply`. The `remove-worktree` step stopped (exit 4, `worktree_remove_failed`) on git's `fatal: working trees containing submodules cannot be moved or removed`.
- The engine calls a plain `git worktree remove <path>` (`.aai/scripts/merge-cleanup.mjs`, `removeWorktree`). Git refuses that for any worktree with initialized submodules, even clean ones. So every downstream project with submodules hits this stop on every worktree ride.
- The operating agent then removed the worktree by hand with `git worktree remove --force` and re-ran `apply`. `SKILL_MERGE.prompt.md` forbids that in its hard rules. The prompt, though, never says what to do when `apply` stops, so the agent filled the gap itself.

## Type
- bug

## Impact
- Every downstream project that uses submodules: `/aai-merge` cannot finish its cleanup without a manual step.
- Data-loss risk: a manual `--force` deletes whatever lives only in the worktree's submodules, with no check and no archive. That includes modified or untracked files, gitignored files, and submodule commits never pushed to the submodule's remote.
- Severity: medium (cleanup blocked, data-loss path through the workaround). Priority: high: the owner chose "fix now" (2026-10-11).

## Current Behavior
- `worktreeVerdict` checks `git status --porcelain` of the superproject worktree only. It never checks whether a submodule's checked-out commit exists on any remote.
- `removeWorktree` runs `git worktree remove <path>`, which git refuses when submodules are initialized. The step stops with `worktree_remove_failed` and the git message.
- Preflight says nothing about submodules, so the owner directs the merge without knowing the cleanup will stop.
- `SKILL_MERGE.prompt.md` lists exit 4 as "stopped (re-run resumes)", but never tells the agent to relay the stop to the owner and stop.

## Expected Behavior
- `removeWorktree` removes a worktree with initialized submodules on its own, but only after proving for every submodule (recursively, nested ones included):
  - its working tree is clean (no modified or untracked files);
  - its checked-out commit is reachable from a remote-tracking ref of that submodule.
- After that proof the engine deinitializes the submodules in that worktree, or forces the removal, and only then removes the worktree. Which of the two is the Planning decision.
- When the proof fails, the step stops with a named reason that lists each offending submodule path and why (`dirty` or `unpushed`). Nothing is removed and nothing is forced.
- Preflight (and `plan`) surface the same submodule blocker before the merge, so the owner sees it before giving the direction.
- `SKILL_MERGE.prompt.md` states: when `apply` stops (exit 4), relay the stop reason to the owner verbatim and stop. Never finish a step by hand, which means no manual `git worktree remove --force` and no manual branch delete. Re-running `apply` after the owner resolves the cause is the only way forward.

## Steps to Reproduce (if applicable)
1) A repo with a submodule; a ride on a worktree where `git submodule update --init` has run.
2) Merge the ride's PR via `/aai-merge <n>`.
3) `apply` stops at `remove-worktree` with `worktree_remove_failed: fatal: working trees containing submodules cannot be moved or removed`.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-merge-cleanup.sh` passes new cases built on a real submodule fixture (a local bare submodule origin):
  - Clean, pushed submodule: `apply` removes the worktree and deletes the branch (exit 0).
  - Dirty submodule (modified file, and separately an untracked file): `apply` stops with a named reason that names the submodule path. The worktree and the dirty file survive.
  - Submodule HEAD on a commit absent from its remote: `apply` stops with the named `unpushed` reason. The worktree and the commit survive.
  - Preflight reports the submodule blocker for the dirty and unpushed cases.
- A grep pin on `SKILL_MERGE.prompt.md` asserts the stop-and-relay rule and the "never by hand" wording.
- A mutation that drops the submodule proof (straight `--force`) turns the dirty and unpushed cases red.

## Constraints / Risks
- Never `--force` before the proof; the proof must cover nested submodules.
- Gitignored files inside a submodule are not visible to `git status`. Planning decides whether they block the removal or get archived first (archive-first is the engine's D7 principle). Losing them silently is not acceptable.
- The submodule fixture must stay CI-safe: `protocol.file.allow=always` for the local-path submodule, plus a fixture-owned git identity (see the bare-origin fixture lessons).
- The existing archive-first, no-stash, no-reset rules of the engine stay unchanged.
- No secret referenced; secrets preflight skipped.

## Notes
- Reported by the owner 2026-10-11 from a downstream `/aai-merge 829` run; the agent's own account names the forbidden manual `--force`.
- Implementation mode: left to Planning (autopilot default, /aai-ship).
