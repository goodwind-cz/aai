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

## Shared-page coordination

PR preparation detects overlap with our earlier PR #535 in six generated shared pages. The owner-authorized separate repair goes first. PR #535 remains open and must be rebased/regenerated and reverified after the owner merges this repair; its generated pages are not copied into this branch. No other open PR conflict was reported. This records coordination of the two owned scopes without merging either.

## Post-rebase verification

Selected+CORE run test-20261107-100738 completed 15/15 PASS, zero reuse, all15 isolated/seeded and suite-tripwire clean, wrapper exit0, 747.347seconds. The outer report-only wrapper reported the single legitimate framework summary append in docs/ai/tests/test-runs.jsonl; aai-run-tests.sh documents this contract and test-framework.sh names fu-framework-appends-tracked-testruns. The row is retained, not reverted. No whole-wrapper clean claim is made.

A post-close ride-gate call correctly refused an already-done intake. A read-only retrospective gate using the exact draft reconstructed from checkpoint20261107T033225Z returned ADMIT (off-roadmap requested maintenance; budget does not gate); no status was changed and no override was recorded. Roadmap ship-append was a named maintenance no-op.
