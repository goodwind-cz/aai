---
id: merged-worktrees-linger-after-close
type: issue
number: 91
status: draft
links:
  pr: []
  commits: []
---

# A merged ride leaves its worktree and branch behind, and nothing says so

## Summary
- The close ceremony closes the documents, stamps the PR and flips the state, but says nothing about the WORKTREE the ride ran in. After the merge the directory and its branch stay on disk indefinitely.
- Measured on 2026-10-01: four worktrees were removed by hand during one session, and three more had appeared by the end of it — one belonging to a ride whose PR had already merged, and two scratch clones a validation role created under the session scratchpad and never removed.
- The residue is not inert. A stale worktree holds a branch ref alive, keeps a second copy of `docs/ai/STATE.yaml` that reads as a live focus, and is indistinguishable at a glance from a ride still in progress.

## Type
- bug

## Impact
- Every ride whose recorded worktree decision actually CREATED one. That is not the same as every L3 ride: an L3 scope recommends a worktree but the operator may record `inline` instead, and then no checkout exists to leave behind. The factory's own repository accumulated seven in a day.
- Severity: medium. Nothing is lost, but the operator cannot tell a finished ride from a live one without checking each branch against its PR by hand — which is what the orchestrator did repeatedly today.
- The confusion is worse than the disk: a leftover `STATE.yaml` in a stale worktree names a `current_focus` that no longer exists, and a leftover branch makes `git worktree list` read as parallel work in flight.

## Current Behavior
- `close-work-item.mjs` closes the item and reconciles STATE; `nothing-left-behind.mjs` and `close-before-push-guard.mjs` gate the push. None of them mentions the worktree.
- After `gh pr merge --delete-branch` the REMOTE branch is removed. The local worktree, its checkout and its local branch remain, and `git worktree list` keeps showing them.
- Nothing distinguishes "merged, safe to remove" from "mid-ride, do not touch". The operator has to ask GitHub whether each branch's PR merged and compare its `headRefOid` to the local tip — the check this session ran by hand four times today.

## Expected Behavior
- After a ride's PR merges, something states plainly that the worktree is finished and can go — ideally offering the removal rather than performing it unasked, since a worktree is the operator's workspace.
- The statement is earned, not assumed: a worktree is only reported as finished when its tree is clean AND its branch has a merged PR whose head commit equals the local tip. Anything else is reported as still in use, with the reason.
- Scratch worktrees a role creates for comparison (under the session scratchpad, in detached HEAD) are the role's own litter and should be removed by the role that made them, or reported as orphans.

## Steps to Reproduce
1) Run any ride in a worktree and merge its PR with `--delete-branch`.
2) `git worktree list` — the worktree and its local branch are still there.
3) Nothing in the close output, the push gates or `aai-doctor` mentions them.

## Verification
- A fixture repository with one merged-PR worktree and one mid-ride worktree: the reporter names exactly the first as finished and the second as in use, with its reason.
- A worktree whose tree is dirty is never reported as finished, even when its PR merged.
- A worktree whose local tip differs from the merged head is never reported as finished — the case that catches a local commit made after the merge.
- A detached-HEAD scratch worktree under the session scratchpad is reported separately from a ride worktree, not conflated with one.
- The reporter performs no removal of its own in any arm.

## Constraints / Risks
- **A worktree is the operator's workspace and may hold uncommitted work that exists nowhere else.** Automatic removal is out of the question; this is a reporting feature with an offer, not a cleaner. The same reasoning the canon already applies to worktree CREATION applies to destruction.
- The merged check needs the platform (`gh pr list --head`), which is unavailable offline and on a repository with no remote. Degrade to "cannot verify, left alone" and say so — never to "probably finished".
- A squash merge means the local tip is NOT an ancestor of the default branch, so `git branch --merged` answers wrongly here. The comparison that works is the PR's own `headRefOid` against the local tip, which is what this session used.
- Scope risk: this could grow into worktree lifecycle management. It should not. Report, and offer.
- No secret referenced; secrets preflight skipped.

## Notes
- Raised by the owner on 2026-10-01 after the orchestrator removed four merged worktrees by hand and a fifth appeared during the same session.
- Suggested home: `aai-doctor` already reports wiring that is present but inert (CAT-18, added in ISSUE-0090), which is the same shape of question — "this exists, is anything still using it?".
- Related: the close ceremony is the natural trigger, but it runs BEFORE the merge, so the report belongs either to the next `aai-doctor` run or to a post-merge step. That choice is Planning's.
