---
id: docs-rollup-userguide
number: 57
type: change
status: draft
links:
  spec: null
  pr: []
  commits: []
---

# USER_GUIDE: docs-audit rollup / closeout / brief sweep + close completed RFC-0013

## Summary
- Operator-docs drift close-out for this session's new docs-audit surfaces. Adds a
  `## Docs health & umbrella progress (docs-audit)` section to `docs/USER_GUIDE.md`
  documenting the `- Rollout:` line + `### Rollout progress` table (CHANGE-0055),
  the Rollout-Status-guarded closeout candidate (CHANGE-0056), and the stale-brief
  sweep (`prune-stale-briefs.mjs`, CHANGE-0054) — none of which were in the guide.
- Also closes the now-complete **RFC-0013** (schema v2 + redaction): all its
  proposals are `done`, its child spec is done, and docs-audit surfaces it as a
  closeout candidate. Advance `implementing → done`.

## Type
- change (operator docs + a lifecycle close of a completed umbrella RFC)

## Motivation / Business Value
- `SKILL_WRAP_UP` step 4d (operator-docs drift check) flags new CLI/output surfaces
  that never reached USER_GUIDE — the Rollout progress rollup and the brief sweep
  were exactly that gap. Closing RFC-0013 keeps the tracked-open set honest (it is
  done; leaving it `implementing` overstates open work).

## Scope
- In scope:
  - `docs/USER_GUIDE.md`: new "Docs health & umbrella progress" section (Rollout
    progress, closeout candidates, stale-brief sweep).
  - `docs/rfc/RFC-0013-friction-record-v2-redaction.md`: `implementing → done`
    (via the close ceremony, with its doc_lifecycle + work_item_closed events).
- Out of scope:
  - RFC-0012 (legitimately open — phases 3-5 not started).
  - Any engine change (docs-audit behaviour is unchanged; this is docs + a close).

## Desired Behavior (To-Be)
- USER_GUIDE explains how to read `- Rollout: <id> N/M`, the `### Rollout progress`
  table, closeout candidates, and the brief sweep.
- RFC-0013 is `status: done`, classified tracked-done by docs-audit (no false-open);
  RFC-0012's rollup consequently reads 11/11.

## Acceptance Criteria
- AC-001: `docs/USER_GUIDE.md` contains a section documenting `Rollout progress`,
  closeout candidates, and `prune-stale-briefs`. Verified by grep for the headings /
  keywords (previously 0 hits for "Rollout").
- AC-002: RFC-0013 is `status: done` with a `doc_lifecycle` (implementing→done) and
  `work_item_closed` event; repo-wide `docs-audit --check --strict` stays CLEAN
  (RFC-0013 tracked-done, never false-open/false-done).
- AC-003: docs-audit rollup now reads `RFC-0012 11/11` (RFC-0013 counted done) and
  RFC-0013 no longer appears as a closeout candidate.

## Verification
- `grep -c "Rollout progress" docs/USER_GUIDE.md` > 0; the section names the brief
  sweep + closeout.
- `docs-audit --check --strict --no-event` CLEAN; `--list` shows RFC-0012 11/11 and
  no RFC-0013 closeout row.

## Constraints / Risks
- Docs-only change plus one lifecycle transition; no code touched. The close
  ceremony self-verifies against the real audit engine and rolls back if RFC-0013
  would not classify tracked-done.
- `docs/USER_GUIDE.md` and `docs/rfc/**` are not protected_paths_l3.

## Notes
- Related: umbrella-progress-rollup (CHANGE-0055), closeout-display-id-match
  (CHANGE-0056), prune-stale-briefs (CHANGE-0054) — the surfaces documented here.
