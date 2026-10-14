# Decision: split the combined one-command release ride

Date: 2026-10-13T23:11:45Z
Blocking ref: release-one-command-no-findings
Decided by: human

## Question

Validation round 2 failed. A third finding-bearing round on the combined ride is a stop whose only instruction is to split the ride. Split into (1) the notes gate and (2) release finish, or authorize one more combined remediation round?

## Decision

Split. The owner selected the recommended option: separate A (notes gate, `/aai-pr`, and PR CI) from B (release classification and resumable finish). No combined pull request. The worktree and its failed evidence stay.

## Assumptions

- Child A is `release-notes-gate`. Child B is `release-finish-one-command`. A owns the shared shipped-surface classifier and `no-notes` marker. B depends on that module and does not copy it.
- Both round-2 defects (extensionless executable mode, stale origin base) belong to B.
- The parent intake and spec are superseded. Their bytes and the round-2 report stay as evidence. Nothing in the worktree is discarded.
- This decision does not start implementation of either child and does not waive validation or review.
