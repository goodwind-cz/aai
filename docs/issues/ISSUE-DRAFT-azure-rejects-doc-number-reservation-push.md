---
id: azure-rejects-doc-number-reservation-push
type: issue
number: null
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Issue — Doc numbering is unusable on Azure Repos: the reservation push is rejected

## Summary
- On a project hosted on Azure Repos, `allocate-doc-number.mjs` cannot reserve
  a display number. The push that creates `refs/aai/docnums/<TYPE>-<NNNN>`
  in origin (CHANGE-0035 / SPEC-0047, D2) is rejected by the remote. The
  operator's report quotes git-lfs pre-push output: "Locking support detected
  on remote".
- Every allocation then takes the D4 provisional path and gets
  `number_reserved: false`. `--reserve` completion keeps failing for the same
  reason, and the `--guard` D5(b) unreserved-marker predicate blocks the merge.
  Numbering on Azure has no path to a clean guard.

## Type
- bug

## Impact
- Who/what is affected: every downstream AAI project whose origin is Azure
  Repos (`pr-platform.mjs` classifies these as `platform=azure`). Every
  numbered doc (ISSUE/CHANGE/SPEC/RFC/...) allocated at `/aai-pr` is affected.
- Severity/priority: high. On Azure, numbered docs cannot be merged through
  the guard unless someone strips the marker by hand, which defeats the
  collision guard.

## Current Behavior
- `git push --atomic --force-with-lease=refs/aai/docnums/X: origin <sha>:refs/aai/docnums/X`
  fails on Azure. The failure does not contain "stale info", so
  `pushReservation` classifies it as a non-collision failure. The allocator
  then stamps `number_reserved: false` and warns.
- `allocate-doc-number.mjs --reserve --path <doc>` fails the same way, so the
  marker never clears.
- `allocate-doc-number.mjs --guard` reports
  `GUARD FAIL (unreserved marker)`, and the PR cannot pass.

## Expected Behavior
- On Azure Repos, doc numbering produces a collision-safe, confirmed number
  that the guard accepts. It must not depend on a ref namespace or push shape
  the platform refuses.
- If the platform cannot support origin reservation at all, AAI detects that
  up front and uses a documented alternative strategy. The guard must accept
  that strategy, and a collision must still be caught before merge. AAI must
  never emit a permanent provisional marker that blocks every merge.
- The reason the remote gave for the rejection is surfaced verbatim. A
  git-lfs advisory line such as "Locking support detected on remote" is not
  mistaken for the cause.

## Steps to Reproduce (if applicable)
1) Use a repository whose `origin` is Azure Repos (`dev.azure.com/...` or
   `*.visualstudio.com`), with git-lfs installed and its pre-push hook active.
2) Create an intake draft, then run `/aai-pr` (or
   `node .aai/scripts/allocate-doc-number.mjs`) so the draft is numbered.
3) Observe the reservation push rejection, the `number_reserved: false`
   stamp, and the warning.
4) Run `node .aai/scripts/allocate-doc-number.mjs --guard` and observe
   `GUARD FAIL (unreserved marker)`.

## Verification
- First establish the actual root cause on a real Azure remote. Capture the
  full stderr of the reservation push, not just the git-lfs line. Determine
  which of these is the cause:
  - Azure refuses refs outside `refs/heads/` and `refs/tags/`.
  - Azure refuses `--atomic` or the empty-expected `--force-with-lease`.
  - A branch policy or permission rejects the push.
  - The git-lfs pre-push hook blocks it.
- Tests (stubbed remotes, never a real Azure or other real remote from the
  suite):
  - an Azure-shaped rejection leads to the chosen Azure strategy. The result
    must be a confirmed number, or a guard-accepted alternative, and never a
    permanent `number_reserved: false`.
  - two clones racing on Azure for the same number: exactly one gets it.
  - GitHub and generic remotes keep today's `refs/aai/docnums/*` behavior
    unchanged (existing `test-aai-doc-number-reservation.sh` stays green).
  - the guard still catches a duplicate or cross-branch number on Azure.
- `node .aai/scripts/docs-audit.mjs --strict` and the doc-numbering guard
  return rc 0 on the fixture.

## Constraints / Risks
- Known risks or constraints:
  - Do not weaken the collision guard for GitHub or generic remotes. Any
    Azure path must be selected by detection, through `pr-platform.mjs`
    classification or a probe of the rejection, never by a blanket bypass.
  - A plausible fix is to reserve under a namespace Azure accepts, such as a
    tag (`refs/tags/aai-docnum/<ID>`) or a branch (`refs/heads/aai/docnums/<ID>`).
    That fix has side effects to weigh:
    - tags and branches show up in the UI and in clones and fetches;
    - branch policies or tag permissions may also refuse them;
    - cleanup needs care.
    The planning step chooses the fix after the root cause is measured.
  - Existing projects may already carry docs stamped `number_reserved: false`
    by this failure. The fix needs a completion or migration path for them.
  - Tests must never push to a real remote. Stub the remote with a local bare
    repo plus a pre-receive hook that mimics the Azure rejection.
- Secrets preflight results (if any secret referenced): none referenced.

## Notes
- Reported by the owner in chat on 2026-11-26 (paraphrased from Czech: fix
  numbering on Azure somehow, because Azure refuses the reservation push), with
  the quoted message "Locking support detected on remote".
- That message is the git-lfs pre-push advisory (locking verify not
  configured). It is probably not the rejection reason itself. The decisive
  line of the remote's stderr was not captured in the report. Assumption: the
  push is rejected for a non-collision reason, so it hits the D4 provisional
  path.
- Related: CHANGE-0035 (origin reservation), ISSUE-0032, `pr-platform.mjs`
  (`platform=azure` classification). The Azure side of `/aai-issues` is
  deferred for the same reason: Azure adoption has not been exercised live yet.
