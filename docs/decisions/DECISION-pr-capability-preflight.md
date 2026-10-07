# Decision: Isolate PR capability preflight implementation

Date: 2026-10-07
Blocking ref: pr-capability-preflight
Decided by: human

## Question
Use a worktree for the recommended isolation of pr-capability-preflight?

## Decision
W — create a worktree and continue.

## Assumptions
The working checkout is /private/tmp/aai-pr-capability-preflight on change/pr-capability-preflight. The temporary path is writable under the session sandbox. The unused app-managed checkout was archived recoverably.
