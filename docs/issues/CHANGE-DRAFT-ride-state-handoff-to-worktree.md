---
id: ride-state-handoff-to-worktree
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# Change: Hand a ride's STATE to its worktree and back, carrying only that ride

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Add a canonical, deterministic handoff for a ride whose worktree is decided
  after Planning: move exactly that ride's runtime state from the originating
  checkout's `docs/ai/STATE.yaml` into the worktree's own fresh STATE, and mark
  it as handed off in the origin so nothing is counted or dispatched twice.
- After merge, reconcile the origin STATE with the ride's final worktree STATE
  so the origin does not keep a stale focus or unflushed runs of a closed ride.
- Second child of RFC-0017 in the owner-approved order of 2026-10-22
  ("ride reliability").

## Motivation / Business Value
- The worktree skill only initializes a fresh STATE for a ride that starts in
  the worktree. When the worktree decision comes after Planning (the common
  `/aai-ship` path, worktree recommendation `recommended`), the only known way
  is to copy the whole origin STATE (LEARNED memory `worktree-carry-live-state`).
- Observed failures from that copy:
  - #482/#484: the copied STATE carried another ref's runs; a flush in the
    worktree wrote them to METRICS and main CI went red (pricing FAIL-002).
  - Stale blocks from other refs (last_validation pass of
    `docs-index-broken-refs-scope`, another ride's worktree path, strategy)
    rode along and had to be reset by hand with `reset-block --force`.
  - After #491 merged, the origin STATE still had the ride as current focus
    with an unflushed Planning run; a later flush or sweep would double count
    it. It was repaired by hand by adopting the archived worktree STATE.
- The owner's attention should not be spent on this; it should be a
  deterministic step with a test.

## Scope
- In scope:
  - A `state.mjs` (or dedicated script) handoff command: given `--ref` and a
    target worktree path, create the worktree STATE through the canonical
    initializer and carry over only that ref's focus, active work item, its
    `metrics.work_items[<ref>]` runs, and the ref-scoped blocks (strategy,
    worktree, code_review, last_validation when they name that ref); in the
    origin, record the handoff and stop treating the ref as live there
    (focus cleared, runs moved, not copied).
  - A post-merge reconcile so the origin STATE reflects the closed ride
    (wired into the directed merge cleanup or as a step it calls), never
    re-flushing runs already flushed in the worktree.
  - Wiring into the worktree skill / ship flow where the mid-ride worktree
    decision is made.
  - Tests that prove no foreign ref's runs or blocks reach the worktree, no
    run is lost or duplicated across the two files, and the origin ends clean
    after merge.
- Out of scope:
  - Changing STATE format or moving it out of YAML (RFC-0017 decision 3).
  - Merge-cleanup roadmap overlap handling (separate draft
    `merge-cleanup-resolves-framework-friction`).
  - Multi-session locking semantics beyond what session-lock already does.

## Affected Area
- `.aai/scripts/state.mjs` (or a new handoff script), `.aai/scripts/merge-cleanup.mjs`
  or the post-merge path, `.aai/SKILL_WORKTREE.prompt.md`, `.aai/SKILL_SHIP.prompt.md` /
  loop guidance where the worktree gate is applied, related suites.
- Downstream: vendored layer behavior; must work on Windows PowerShell paths
  where the existing worktree seed already does.

## Desired Behavior (To-Be)
- One command moves a ride into its worktree; the worktree STATE passes
  `check-state` and dispatches the same next role the origin would have.
- The worktree STATE contains no run or ref-scoped block of any other ref.
- The origin STATE no longer lists the ride as focus and holds none of its
  runs after the handoff; a record says where it went.
- After the PR merges, the origin STATE carries no stale focus, work item or
  unflushed runs for that ride, and METRICS has exactly one entry for it.

## Acceptance Criteria
- AC-001: After the handoff, the worktree STATE passes check-state and orchestration-dispatch returns the same rule and role as the origin did immediately before.
- AC-002: A fixture origin STATE with runs and blocks for two other refs produces a worktree STATE containing none of them; the origin keeps them byte-identical.
- AC-003: The ride's runs exist in exactly one of the two STATE files after the handoff (moved, not copied), proven by a test that counts them.
- AC-004: After a simulated merge and the post-merge reconcile, the origin STATE has no focus, active work item or metrics runs for the ride, and a following metrics-flush (default and sweep) adds no second METRICS entry for it.
- AC-005: The worktree skill and the ship flow name the handoff command for the mid-ride worktree decision, replacing the whole-STATE copy.

## Verification
- Command(s) and expected results:
  - Fixture-based suite for the handoff and reconcile (new or extended).
  - Existing state, worktree-seed, merge-cleanup and metrics-flush suites pass.

## Constraints / Risks
- STATE is gitignored and the only runtime memory; any move must be
  atomic or recoverable (archive before change).
- Other sessions may share the origin checkout; the handoff must not touch
  other refs' entries.
- No secret is referenced.

## Notes
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md), owner decisions of 2026-10-22, order item 2.
- Evidence: PR #482/#484 metrics leak; PR #491 post-merge origin STATE repair
  (archive `docs/ai/archive/merge-cleanup/pr-491/manual/docs/ai/STATE.main-before.yaml`).
- Human intake time: not asked (autopilot `/aai-ship`), recorded as null.
