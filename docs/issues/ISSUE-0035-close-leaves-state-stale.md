---
id: close-leaves-state-stale
type: issue
number: 35
status: draft
links:
  pr: []
  commits: []
---

# Close ceremony leaves STATE lying and the dispatcher serves the closed scope

## Summary
- After a successful close ceremony, `docs/ai/STATE.yaml` still describes the
  closed scope as in-flight (work item `in_progress`, spec/primary paths
  pointing at pre-allocation `*-DRAFT-*` files that no longer exist), and
  `orchestration-dispatch.mjs` rules 5/6 then dispatch Planning onto the
  closed ref — the exact scope the state summary itself reports as closed
  (`close_event_present: true`).

## Type
- bug

## Impact
- Every ride's first post-merge orchestration tick. Observed 2026-08-14
  (registry `fu-dispatch-targets-closed-scope`, P2 — four hand edits to
  recover) and again 2026-08-24/25 on the CHANGE-0165 ride, three stumbles in
  a row on one tick sequence:
  1. rule 5 dispatched Planning at the closed ref because
     `current_focus.spec_path` and `active_work_items[ref].spec_path` held the
     dead `SPEC-DRAFT-*` path (the allocator renamed the file to
     `SPEC-0152-*` during the PR step; nothing updated STATE);
  2. after hand-fixing the paths, rule 6 dispatched Planning because the
     closed spec's frontmatter status is `done`;
  3. rule 4b (closed-but-unflushed -> Metrics Flush) only matched after a
     manual `state.mjs set-phase --status done`, because `close-work-item.mjs`
     flips document frontmatter and emits the close event but leaves the STATE
     work item `in_progress`.
- Severity/priority: P2 — no data loss, but every ride pays manual recovery,
  and an unattended orchestrator would burn a Planning dispatch on a finished
  scope (the 2026-08-14 instance did exactly that).

## Current Behavior
- `close-work-item.mjs` (after its self-verify audit passes): updates doc
  frontmatter, emits the close event, prunes the brief — and never touches
  the STATE work item entry or the focus paths.
- `orchestration-dispatch.mjs`: rule 5 fires on "spec_path null or file
  missing" and rule 6 on "status not draft/implementing" with no earlier
  check that the focus ref already has a committed close event; the
  state summary carries `close_event_present: true` and a non-empty
  `open_intakes` list while `retarget` stays null.

## Expected Behavior
- `close-work-item.mjs`, immediately after its self-verify audit passes (same
  transaction boundary as the close event): set
  `active_work_items[ref].status: done`, and reconcile
  `active_work_items[ref].spec_path` plus `current_focus`
  `primary_path`/`spec_path` to paths that exist at close time (the
  post-allocation numbered files) — via the existing `state.mjs` CLI /
  engine API, never by editing protected files.
- `orchestration-dispatch.mjs`: a focus ref with a committed close event must
  NEVER produce a Planning dispatch from rules 5/6. That state falls to the
  4a/4b arms (retarget / metrics flush) when their conditions hold, and
  otherwise returns needs_llm with a named reason (e.g.
  `closed_focus_stale_state`) — fail-flagged, never fail-dispatched.
- Both behaviors pinned by tests, bite-proved in both directions.

## Steps to Reproduce (if applicable)
1) Complete a ride through `close-work-item.mjs` (the CHANGE-0165 ride is the
   recorded reproduction: close commit on `docs/single-writer-canon`, merged
   PR #287).
2) Run `node .aai/scripts/orchestration-dispatch.mjs --human` on main.
3) Observe rule 5 (or, after fixing paths by hand, rule 6) dispatching
   Planning at the closed ref instead of 4b Metrics Flush.

## Verification
- New/extended suite arms: a fixture STATE + docs tree where the focus ref
  carries a committed close event and stale paths/status must yield (a) after
  the close-work-item fix: work item `done` and live paths, (b) dispatcher:
  never `role: Planning` for that ref — 4a/4b or needs_llm with the named
  reason. Arms shown red against the pre-fix code, green after.
- `bash tests/skills/test-framework.sh` full sweep green.
- Live check: next real ride's first post-merge tick reaches rule 4b with no
  hand edits.

## Constraints / Risks
- HARD boundary: `state.mjs`, `lib/state-engine.mjs`, `lib/state-core.mjs`,
  `allocate-doc-number.mjs` are protected_paths_l3 — the fix calls their
  existing CLIs/APIs; it never edits them. If a needed field turns out to be
  unreachable through the existing API surface, the ride STOPS and reports
  instead of touching protected code.
- `fu-setfocus-keeps-stale-spec-path` is NOT closed by this scope (its root —
  set-focus field handling — lives inside protected state.mjs); its record
  gets a narrowing note only.
- close-work-item.mjs's rollback path must stay coherent: if the new STATE
  reconciliation fails mid-write, the close must either roll back whole or
  leave a named, detectable partial state — never a silent half-close.
- Dispatcher rule ordering is canon (SPEC-0012 G3 emergent routing); the fix
  must not reorder existing rules, only stop 5/6 from matching a closed ref.

## Notes
- Registry: closes `fu-dispatch-targets-closed-scope`; narrows (does not
  close) `fu-setfocus-keeps-stale-spec-path`.
- The dispatcher already computes everything needed (`close_event_present`,
  `open_intakes`) — this is wiring truth it already knows into rules that
  currently ignore it, the same shape as CHANGE-0165.
