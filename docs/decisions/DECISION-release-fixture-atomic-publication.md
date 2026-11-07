# Decision: Split release fixture reliability into a separate ride

Date: 2026-11-07
Blocking ref: singleton-reservation-portability, PR #535
Decided by: human

## Question

After reproducing an inherited TEST-021 transport publication race, authorize a separate repair, retry the same head once, or leave PR #535 blocked?

## Decision

The owner answered `1`: authorize a separate fixture repair in an isolated worktree and pull request, then reverify and finish PR #535. Preserve the failing CI run 42317483792 and the prior narrow TEST-829/830 and incomplete-full-sweep exception. No additional waiver, merge, or release is authorized.

## Assumptions

The repair targets every release-fixture transport writer and deterministic concurrent-reader coverage. Existing SIGKILL/resume assertions remain intact. PR #535 remains independently identifiable; merging the separate repair remains the owner's action.
