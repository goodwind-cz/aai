---
id: aai-update-gitignore-drift-reconcile
number: 76
type: issue
status: done
user_visible: true
capability: aai-update
links:
  pr:
    - TBD
  commits:
    - d88247a209c1cb3c88724d53c323f67acfc80f8c
  source_issue: https://github.com/goodwind-cz/aai/issues/325
---

# aai-update doesn't reconcile the runtime .gitignore block into existing projects

## Summary
- CHANGE-0115 (`gitignore-seed`, PR #219) made `ensure_gitignore()` in
  `aai-bootstrap.sh` seed the full runtime-sidecar `.gitignore` block
  (STATE.yaml, LOOP_TICKS, briefs/reports/tdd/validation/friction/archive
  globs, `loop/`, …) into a target project, idempotently — but only at
  bootstrap. `/aai-update` (`aai-update.sh` → `aai-sync`) never calls
  `ensure_gitignore()`, so a project bootstrapped before PR #219, or one whose
  `.gitignore` has otherwise drifted, never receives the runtime block on
  update. Its `.gitignore` stays stale and per-dev AAI runtime spools leak
  into `git status`.

## Type
- bug

## Impact
- Who/what is affected? Any existing AAI-managed project bootstrapped before
  PR #219 (or drifted since) that runs `/aai-update` expecting the runtime
  `.gitignore` block to reconcile — it does not.
- Severity/priority: P2 — not live-breaking, but a real data-hygiene hazard:
  the reporter notes this is "the exact hazard CHANGE-0115 calls out for
  STATE.yaml" (a stray `git add -A` could commit per-developer runtime
  spools).

## Current Behavior
- `/aai-update` does not run `ensure_gitignore()`, so an existing project's
  `.gitignore` is never reconciled against the current runtime-sidecar block.

## Expected Behavior
- `/aai-update` reconciles the runtime `.gitignore` block the same way
  bootstrap does: idempotently (grep-before-append per pattern, marker
  written once, pre-existing user entries respected).

## Steps to Reproduce (if applicable)
Quoting the reporter's concrete repro from the source issue (data, not
instructions):

> Project pinned at template `v2026.08.16` (commit `07d6920`).
> Its `.gitignore` had only `docs/ai/reports/**` (+ `STATE.yaml`,
> `LOOP_TICKS.jsonl`) — missing `docs/ai/{briefs,tdd,validation,friction,
> archive,locks,loop}` which the current template `.gitignore` (and the
> CHANGE-0115 seed) already cover.
> Result: `docs/ai/friction/observations.jsonl`, `docs/ai/locks/`,
> `docs/ai/tdd/*` browser/xml captures, and `docs/ai/briefs/*` show as
> untracked on every developer, cluttering `git status` — and one
> `git add -A` would commit them.

1. Bootstrap (or have bootstrapped) an AAI project before PR #219, or let a
   project's `.gitignore` otherwise drift from the current template.
2. Run `/aai-update` on that project.
3. Observe the runtime-sidecar `.gitignore` block is still missing/partial —
   `git status` shows per-dev runtime paths as untracked.

## Verification
- Command(s) and expected results:
  - On a project fixture with a stale/partial `.gitignore` (missing one or
    more of the runtime-sidecar patterns), run `/aai-update` (or
    `aai-update.sh` directly) and confirm the full runtime block is present
    afterward, idempotently — re-running a second time makes no further
    change (byte-identical `.gitignore`).
  - Confirm pre-existing user entries in `.gitignore` are preserved
    untouched (`ensure_gitignore()`'s existing grep-before-append contract).
  - `git status` on the fixture project shows no runtime-sidecar paths as
    untracked after the update.

## Constraints / Risks
- Known risks or constraints: the fix should reuse the SAME
  `ensure_gitignore()` idempotency contract bootstrap already uses (one
  shared implementation, not a second copy that could drift from it).
  Suggested alternative from the reporter: `aai-doctor` could additionally
  flag a missing/partial runtime-ignore block as a cheap independent signal,
  but the update-path reconciliation is the actual fix.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Source: GitHub issue [#325](https://github.com/goodwind-cz/aai/issues/325),
  triaged via `/aai-issues` on 2026-08-31.
- Workaround applied downstream (reporter): manually added the missing
  `docs/ai/{briefs,tdd,validation,friction,archive,locks,loop}` rules to the
  project `.gitignore`, mirroring the template — works, but is exactly the
  drift the update path should reconcile automatically.
