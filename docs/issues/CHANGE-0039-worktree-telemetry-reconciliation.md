---
id: worktree-telemetry-reconciliation
type: change
number: 39
status: done
links:
  pr:
    - 107
  commits:
    - 41e44c5
---

# Change — reconcile worktree-stranded committed telemetry at PR time

## Summary
- Add a deterministic reconciliation to the PR ceremony that detects
  committed-class telemetry (the scope's `docs/ai/METRICS.jsonl` ledger record
  and any `docs/ai/EVENTS.jsonl` lines for the scope ref) written into the MAIN
  checkout by orchestration/flush while the scope was built in a git worktree,
  and carries them onto the scope branch so they ship in the PR instead of
  being lost when the branch/worktree is cleaned up.

## Motivation / Business Value
- `STATE.yaml`/`LOOP_TICKS.jsonl` are gitignored per-developer (RFC-0001), so
  orchestration + `metrics-flush.mjs` MUST run in the main checkout where STATE
  lives. But `METRICS.jsonl` and `EVENTS.jsonl` are COMMITTED-class (shared).
  When a scope is developed in a worktree (L3/worktree isolation), flush writes
  the scope's ledger record into the MAIN checkout's working tree — on the
  intake/base branch, NOT the worktree's impl branch. The PR is made from the
  worktree branch, so the committed ledger record is left behind and is lost on
  branch cleanup. Observed live on PR #99 (L3 numbering scope): the metrics
  record for a 7-tick scope was stranded and had to be hand-carried into the PR.
- This is the last of the workflow gaps observed this session where a committed
  artifact silently fails to ship with its scope; the workflow should reconcile
  it, not depend on an agent noticing.

## Scope
- In scope: a deterministic reconciliation step in `.aai/SKILL_PR.prompt.md`
  (and/or a small helper `.aai/scripts/reconcile-telemetry.mjs`) that, at PR
  time, carries scope-ref committed-class telemetry from a sibling/main checkout
  onto the current scope branch; its test.
- Out of scope: changing where STATE lives (stays gitignored/main-checkout);
  changing metrics-flush's ledger computation; non-worktree (inline) scopes
  where flush already writes to the same tree (no-op there).

## Affected Area
- PR ceremony; committed telemetry integrity for worktree-isolated scopes.

## Desired Behavior (To-Be)
- At PR time, when the scope used a worktree (STATE `worktree.user_decision ==
  worktree`, or a worktree is detected), the ceremony reconciles committed-class
  telemetry: for the scope ref, any `METRICS.jsonl` record and `EVENTS.jsonl`
  lines present in the main checkout but absent from the scope branch are
  appended (union, append-only, deduped) onto the scope branch and staged into
  the PR. For inline scopes it is a verified no-op (flush wrote to the same
  tree already).
- Deterministic and idempotent; append-only union (never rewrites existing
  lines); leaves the main checkout clean (the reconciled lines are now on the
  branch that will merge them back).

## Acceptance Criteria
- AC-001: for a worktree-isolated scope whose METRICS.jsonl record was written
  in the main checkout, the PR ceremony carries that record onto the scope
  branch so it appears in the PR diff — no manual step, no loss on cleanup.
- AC-002: EVENTS.jsonl lines for the scope ref written in the main checkout are
  likewise reconciled (append-only union, deduped) onto the scope branch.
- AC-003: for an INLINE scope (no worktree), the reconciliation is a verified
  no-op (nothing to carry; main checkout and scope tree are the same).
- AC-004: idempotent + append-only — re-running reconciles nothing new, never
  rewrites/reorders existing telemetry lines, and leaves both trees consistent.

## Verification
- Test fixture: a two-checkout setup (main + linked worktree) where flush writes
  a METRICS record + EVENTS lines in main while the branch is in the worktree;
  assert the reconciliation carries them onto the branch, dedupes, and is a
  no-op on re-run and on an inline single-tree scope.

## Constraints / Risks
- Append-only union semantics (RFC-0001) — never rewrite committed telemetry;
  dedupe by full-line identity. Deterministic; no network.
- Detect the worktree case robustly (STATE worktree decision + `git worktree
  list`); fail-safe to no-op if uncertain rather than moving the wrong lines.

## Notes
- Source: PR #99 stranded-ledger incident (hand-reconciled); CHANGE-0037
  Planning R-notes. Completes the session's workflow-hardening arc
  (close ceremony CHANGE-0037, flush events CHANGE-0038, now worktree telemetry).
