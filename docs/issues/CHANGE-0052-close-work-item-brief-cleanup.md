---
id: close-work-item-brief-cleanup
number: 52
type: change
status: done
links:
  spec: null
  pr:
    - 151
  commits:
    - 4bc117c1698f783ac30600b23c8ad82a9e1214fe
---

# Close-work-item brief auto-cleanup

## Summary
- The deterministic close ceremony (`.aai/scripts/close-work-item.mjs`) now prunes
  each closed ref's Planning-emitted work-item brief
  (`docs/ai/briefs/<ref>.md`) once the close is durably self-verified. Briefs are
  gitignored runtime handoff artifacts (like `docs/ai/reports/`); left on disk they
  accumulate for done items (41 stale local files had built up). The brief is
  consumed the moment the item closes, so close is the natural lifecycle hook to
  remove it — a later re-plan regenerates it from the template.

## Type
- change (close-ceremony housekeeping; best-effort, non-blocking)

## Motivation / Business Value
- Stale briefs for closed items are pure local clutter that obscures which briefs
  are live handoffs. Pruning at close keeps `docs/ai/briefs/` scoped to
  in-flight work with zero operator action.

## Scope
- In scope:
  - `.aai/scripts/close-work-item.mjs`: a best-effort `pruneBriefs(plan)` that runs
    ONLY after the self-verified close (never in `--dry-run`, never before the
    durable write). For each closed doc it prunes EVERY candidate brief name — the
    frontmatter slug `id` AND each numbered display id (`fileIds`), since PLANNING
    has historically named the brief by either form (`friction-capture-foundation.md`
    vs `CHANGE-0027.md`). A missing brief, an unlink error, or a name that could
    escape the briefs dir (`/`, `\`, `..`) is silently skipped; the pruned brief(s)
    are named in the success line.
  - `tests/skills/test-aai-close-work-item.sh`: TEST-013 (closed ref's brief pruned,
    an unrelated brief spared, a no-brief close still exits 0), RED-proofed against
    the pre-change script.
- Out of scope:
  - Bulk retro-prune of the existing 41 backlog briefs (a one-off `rm`, done
    manually — not a code path).
  - `PLANNING.prompt.md` brief-emit step (unchanged; the prompt-corpus is untouched
    so no prompt-diet ledger true-up is due).

## Desired Behavior (To-Be)
- After a successful, self-verified close, `docs/ai/briefs/<ref>.md` for every
  closed ref is removed and named in the success line.
- A failed / rolled-back close removes NO brief (pruning is downstream of
  self-verify).
- A close with no matching brief succeeds unchanged (best-effort no-op).

## Acceptance Criteria
- AC-001: closing a ref whose brief exists removes BOTH the slug-named and the
  display-id-named `docs/ai/briefs/*.md` for that doc and reports it in stdout; an
  unrelated brief in the same dir is untouched. Deterministic test (TEST-013), RED
  without `pruneBriefs` (and RED for the display-id form without the fileIds sweep).
- AC-002: a close with no matching brief still exits 0 and reports no prune.
- AC-003: the full `test-aai-close-work-item.sh` suite passes (no regression to
  TEST-001..012).

## Verification
- `bash tests/skills/test-aai-close-work-item.sh` (all green, incl. TEST-013).
- `bash tests/skills/test-aai-close-work-item.sh test_013_brief_cleanup_on_close`
  RED against the prune-less script (proven), GREEN with it.

## Constraints / Risks
- Best-effort by design: an unlink failure never fails the close (the durable
  close is the outcome that matters). Path-escape guard prevents a crafted ref from
  removing anything outside `docs/ai/briefs/`.
- `.aai/scripts/close-work-item.mjs` is NOT a protected_paths_l3 path (L2).

## Notes
- Related: deterministic-close-ceremony (SPEC-0053), PLANNING step 11 brief emit.
