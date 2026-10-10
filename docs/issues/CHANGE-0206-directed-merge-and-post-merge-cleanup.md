---
id: directed-merge-and-post-merge-cleanup
type: change
number: 206
status: draft
links:
  pr: []
  commits: []
---

# Change — Directed merge and safe post-merge cleanup

## Summary

Add a reusable `/aai-merge <PR>` entrypoint that completes an explicitly
requested merge and its local cleanup. It must also accept an already merged
PR and complete only the remaining cleanup. Back the fragile cleanup
decisions with deterministic tooling and executable regression tests.

## Motivation / Business Value

PR #433 completed `worktree-lacks-vendored-aai-layer-downstream` in a feature
worktree. The original checkout still held untracked copies of its issue
and spec under DRAFT filenames, stale runtime focus, and the pre-merge HEAD.
The numbered issue and spec were already done in the merged PR. Git does
not propagate changes to untracked files between worktrees.

The owner discovered the leftovers when invoking `/aai-ship` on the old
draft. Manual recovery archived the superseded drafts, reconciled runtime
state, fast-forwarded the original checkout to main, preserved unrelated
drafts, reconciled the audit ledger, and regenerated the docs index.

The workflow has a missing handoff: `/aai-ship` ends at the PR/merge
checkpoint, while `/aai-worktree cleanup` covers worktree removal but not
origin-checkout reconciliation or superseded draft copies. This failure is
already recorded in open follow-up `fu-seeded-copies-lesson-no-guard`.
One repeatable completion procedure should make merged work stop appearing
unfinished locally without endangering other work.

## Scope

In scope:

- A canonical merge-and-cleanup prompt and discoverable agent skill wrappers.
- Explicitly directed merge using existing CI, review, sweep, platform and
  merge-authorization contracts; no new standing merge authorization.
- Cleanup-only resumption for an already merged PR.
- Deterministic identification and recoverable archival of superseded local
  intake/spec copies by durable document identity and merged content.
- Reconciliation of the originating checkout, per-scope runtime state,
  append-only ledgers, generated docs index, completed worktree and local
  branches, with protection for unrelated work and live sessions.
- A named plan/report, idempotent recovery and behavior-based fixture tests.
- Planning assessment of whether this scope closes
  `fu-seeded-copies-lesson-no-guard` and overlaps
  `docs/issues/ISSUE-0091-merged-worktrees-linger-after-close.md`.

Out of scope:

- Implementing the delivered work again, reopening its PR, or releasing.
- Automatic merging merely because `/aai-ship` opened a PR.
- Broad cleanup of other work items, automatic conflict resolution, or
  deletion of remote branches.
- Changing owner-signed merge policies or bypassing branch protection.

## Affected Area

- PR-to-merge handoff in `.aai/SKILL_PR.prompt.md` and
  `.aai/SKILL_SHIP.prompt.md`.
- Existing cleanup in `.aai/SKILL_WORKTREE.prompt.md`.
- Vendored `.aai/` tooling and agent skill distribution.
- Originating checkout, linked worktree, draft documents, runtime state,
  telemetry and generated document index.

## Desired Behavior (To-Be)

Resolve the explicit PR, repository, base branch, delivered scope and local
checkout/worktree identities. Produce a concrete plan naming each target,
its reason and its backup location before mutations. Reuse existing gates
for the final PR head; invoking the merge entrypoint is explicit direction
for that named PR, not permission to merge another PR or a later unjudged
head. When authorization or a required gate is missing, stop with its reason.

Read back `MERGED` and the merge commit before cleanup. Already merged PRs
skip the merge operation and resume cleanup. Archive runtime/evidence before
removing a worktree. Detect superseded draft copies using durable IDs and
the merged canonical documents, not filename patterns alone. Preserve any
local content that is not proven delivered; divergent copies require a
named decision rather than silent disposal. Archive removable copies
recoverably outside the active document corpus before synchronization.

Synchronize the originating checkout with the PR's base using a verified
fast-forward when possible. Preserve unrelated dirty/untracked work and
all audit records; use the existing append-only ledger merge contract.
Conflicts, divergent history, occupied checkouts or uncertain ownership
produce a partial-completion report and an actionable stop, not a reset,
stash, force removal or broad clean.

Reconcile only the completed ref's runtime state through the canonical
writer, regenerate the document index, and clean up only proven eligible
worktrees/local branches. A squash-merged branch must be recognized from
PR evidence rather than assuming Git ancestry proves it unmerged.
Report final base/HEAD identity, retained work, archived files and any
remaining cleanup. A second invocation must safely resume or report a no-op.

## Acceptance Criteria

- AC-001: A discoverable entrypoint supports a named open PR with explicit
  merge direction and an already merged PR in cleanup-only mode. Existing
  PR/ship instructions link to the completion procedure.
- AC-002: Merge refuses missing authorization, failed required CI/review
  gates or a changed head. No cleanup eligible only after merge runs until
  a read-back proves the named PR is MERGED; no protection bypass is used.
- AC-003: A fixture reproducing PR #433's origin/feature-worktree layout
  archives the superseded issue and spec drafts and retains the merged
  numbered canonical documents. Unrelated drafts and locally divergent
  copies survive; each exclusion/refusal names its reason.
- AC-004: Base synchronization preserves unrelated dirty and untracked
  files and all ledger records. The incoming base remains a byte-exact
  ledger prefix. Divergent history or overlapping edits stops safely.
- AC-005: Cleanup archives runtime/evidence before removal, checks session
  ownership and dirty state, recognizes squash merge, and removes only
  eligible named worktrees/local branches. It leaves other active work
  items, sessions and branches intact.
- AC-006: The completed ref stops appearing as active in runtime focus or
  the regenerated index. The report includes the verified base/HEAD,
  archival paths, retained changes and unfinished steps.
- AC-007: Repeating or resuming after an interrupted cleanup does not lose
  files, duplicate ledger events or repeat a merge. Already completed
  steps are named no-ops.
- AC-008: The deterministic cleanup regression runs against real disposable
  Git repositories, including downstream installed-AAI layout, and the
  chosen implementation works on supported Bash and PowerShell/Windows
  paths. Planning defines the native-platform evidence required.

## Verification

Planning must define exact commands and evidence paths for the regression
matrix before implementation. Fixtures must use private absolute scratch
roots, configure their own Git identities, check setup exits and never
mutate the shipping repository. Include positive controls for successful
merge/cleanup and refusal tests for changed heads, divergent draft content,
unrelated dirty files, ledger additions, live locks, dirty worktrees,
squash merge, repeated invocation and interrupted recovery.

Run suites through the canonical test dispatcher. Verify prompt/wrapper
distribution, profile classification and prompt-growth accounting using
existing project checks. Static token matching alone cannot prove safe
cleanup behavior.

## Constraints / Risks

- Keep the operation scope explicit; no `git clean`, hard reset, blanket
  staging, automatic stashing, forced worktree removal or remote deletion.
- Use existing state, session-lock, ledger and merge-policy interfaces.
- Saved drafts can contain unique user work even when their IDs match a
  delivered document. Preserve bytes and a recovery path before relocation.
- A prompt alone does not enforce the repeated cleanup failure; implement
  deterministic guards for the fragile decisions and test observable effects.
- Installed downstream AAI infrastructure may be ignored and therefore
  absent from commits; do not require a source-repository-only layout.
- No local secret value is referenced by this intake; secrets preflight is
  not applicable. Existing authenticated platform tooling is reused.

## Notes

- Owner request: sync this checkout to main, explain the leftovers, and
  propose a merge-and-cleanup prompt; then save that proposal as intake.
- Proposed entrypoint name: `/aai-merge`; Planning may refine the packaging
  while preserving directed merge and already-merged cleanup semantics.
- Implementation mode is not chosen by the owner; Planning decides.
  Full TDD is recommended because this spans Git, filesystem cleanup,
  authorization boundaries and append-only data integrity.
- Intake human-time estimate: not supplied.
- Evidence/context: PR #433, ISSUE-0093, SPEC-0209,
  `.aai/SKILL_PR.prompt.md` merge boundary, `.aai/SKILL_WORKTREE.prompt.md`
  cleanup command, and the seeded-copy entry in `docs/knowledge/LEARNED.md`.
