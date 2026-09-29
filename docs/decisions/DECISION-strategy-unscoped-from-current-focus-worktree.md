# Decision: L3 worktree gate for strategy-unscoped-from-current-focus

Date: 2026-09-28T19:49:35Z
Blocking ref: [HITL-7] ceremony L3 / worktree.recommendation=required on protected state.mjs
Decided by: human

## Question

WORKTREE DECISION REQUIRED. Scope: strategy-unscoped-from-current-focus. Recommendation: required. Reason: ceremony L3 protected .aai/scripts/state.mjs (protected_paths_l3). Options: w - Create a git worktree and continue there; i - Continue inline in the current working tree; p - Pause before implementation. Question: Use a worktree for this scope?

## Decision

The operator answered: **i** — inline in the current working tree, not a git worktree, not pause.

Normalized enum: `inline` (`[HITL-7]` accepted form `i`).

## Assumptions

Review scope is the Isolation / `code_review.scope` path list already recorded on SPEC-0192 and in STATE. No worktree will be created. No review waiver and no merge authorization.
