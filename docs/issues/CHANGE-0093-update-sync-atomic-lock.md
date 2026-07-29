---
id: update-sync-atomic-lock
number: 93
type: change
status: done
user_visible: false
links:
  pr:
    - 196
  commits:
    - 9c499d97f668742c7e77cee432351502ecfec3e6
---

# Change — auto-update: atomic O_EXCL claim closes the concurrent-sync race (RR-1/RR-2)

## Summary
- Fast-follow to CHANGE-0091 (auto-update). The re-validation + code review of
  #194 found two cross-process TOCTOU races on the OPT-IN auto path, accepted
  as bounded documented residuals (docs/ai/decisions.jsonl, 2026-07-29):
  - RR-1: the `running`-marker concurrent-sync guard has no OS-level lock, so N
    truly-simultaneous same-repo session starts each spawn a detached
    aai-update sync (probe: 5 parallel -> 5 syncs). Bounded (aai-update
    isolates each in a mktemp clone, identical upstream bytes converge) but
    wasteful and a brief torn-file window.
  - RR-2: once-only outcome surfacing can print the "applied" line more than
    once under the same window (cosmetic).
- This change closes both with a single atomic claim.

## Design sketch (planner/impl to finalize)
- Add an ATOMIC claim BEFORE spawning the detached sync: `fs.openSync(
  '.aai/cache/update-sync.lock', 'wx')` (O_CREAT|O_EXCL) — the winner proceeds
  to spawn; a losing racer gets EEXIST and backs off to the existing
  "sync in progress" path (no duplicate spawn). This must be a SEPARATE file
  from update-sync-outcome.json (the outcome file legitimately pre-exists with
  a reported outcome, so O_EXCL there would wrongly fail).
- Age the lock with the SAME >30min stale rule already used for the `running`
  marker (a crashed sync must not wedge auto mode forever): a stale lock is
  reclaimable. Winner removes/ages the lock when the sync finishes (or on the
  stale path).
- RR-2: guard the once-only surfacing with the same atomic-claim discipline
  (e.g. an atomic compare-and-set on `reported`, or a short claim around the
  surface+flip) so simultaneous sessions surface the outcome once.
- Keep .aai/cache/ gitignored + excluded from the PROFILES union (the lock
  lives there).

## Acceptance Criteria
- AC-001: with a sync already claimed (lock present, fresh), a second
  concurrent run does NOT spawn a duplicate aai-update and reports
  "in progress" (suite-verified: N parallel runs -> exactly 1 sync invocation).
- AC-002: a stale lock (older than the stale window) is reclaimable — a fresh
  run may claim and spawn (no permanent wedge); crashed-sync recovery holds.
- AC-003: once-only surfacing holds under concurrency — simultaneous runs
  surface a finished outcome at most once; sequential behavior unchanged.
- AC-004: no regression — all existing auto-update behaviors (notify default,
  canonical refuse, offline degrade, throttle, detached-to-completion, source
  agreement) stay green.
- AC-005: N true-parallel runs reclaiming the SAME pre-existing STALE lock spawn
  exactly ONE sync (concurrent reclaim is atomic, not merely cold-start). A
  crashed/stale lock is still reclaimable (no wedge); a live lock is never
  stolen. Suite-verified with an amplified true-parallel reclaim case.
- AC-006: surfaceOutcome never orphans the outcome. If the read after the atomic
  claim rename fails (a torn write observed mid-write), the outcome is restored
  to its path (best-effort) and surfaces on a later run exactly once; the
  once-only guarantee holds.

## Acceptance Criteria Status

| Spec-AC    | Description                                                             | Status | Evidence                                                                  | Review-By | Notes                                                                          |
|------------|------------------------------------------------------------------------|--------|--------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------|
| Spec-AC-01 | N true-parallel auto+behind runs spawn exactly ONE sync (atomic claim) | done   | docs/ai/tdd/green-20260729T133810Z-update-sync-atomic-lock-full-suite.log | —         | AC-001 TEST-024; O_EXCL wx claim on update-sync.lock; RED red-20260729T133056Z got 5 |
| Spec-AC-02 | Stale or future-dated lock is reclaimed; fresh lock blocks (no wedge)   | done   | docs/ai/tdd/green-20260729T133810Z-update-sync-atomic-lock-full-suite.log | —         | AC-002 TEST-025; symmetric SYNC_STALE_MS window; fresh-lock-blocks was the RED signal |
| Spec-AC-03 | Finished outcome surfaces at most once under concurrency; seq unchanged | done   | docs/ai/tdd/green-20260729T133810Z-update-sync-atomic-lock-full-suite.log | —         | AC-003 TEST-026 (atomic rename claim) + TEST-015 sequential; RED 2 runs printed |
| Spec-AC-04 | No regression across the existing auto-update suite (TEST-001..023)     | done   | docs/ai/tdd/green-20260729T144345Z-update-sync-atomic-reclaim-full-suite.log | —         | AC-004 full suite exit 0, 28 tests now; re-run 3x deterministic                 |
| Spec-AC-05 | N true-parallel racers reclaiming ONE pre-existing STALE lock spawn exactly ONE sync (concurrent reclaim atomic) | done | docs/ai/tdd/green-20260729T144345Z-update-sync-atomic-reclaim-full-suite.log | — | AC-005 TEST-027; serialized reclaim + atomic linkSync lock create; RED red-20260729T141859Z got 14 spawns for 10 rounds; post-fix 30x isolated deterministic |
| Spec-AC-06 | surfaceOutcome restores the outcome on a post-claim read failure (no .surfacing orphan); surfaces once later | done | docs/ai/tdd/green-20260729T144345Z-update-sync-atomic-reclaim-full-suite.log | — | AC-006 TEST-028; injected-read-fault unit check; RED contract absent pre-fix (not exported) |

## Verification
- extend tests/skills/test-aai-update-check.sh: a TRUE-parallel fixture (launch
  several update-check auto+behind runs simultaneously against a slow stub
  aai-update) asserting exactly one sync invocation; a stale-lock reclaim test;
  a concurrent-surfacing test asserting a single "applied" line. Deterministic,
  zero real network.
- docs-audit --check; layer-profiles.

## Constraints / Risks
- Ceremony L2. The lock must NEVER wedge auto mode (stale-reclaim is the
  safety valve); the claim must be genuinely atomic (O_EXCL create), not a
  read-then-write. Keep the detached-sync + report-next-session semantics from
  CHANGE-0091 intact.

## Notes
- Closes the RR-1/RR-2 accepted-residual recorded in docs/ai/decisions.jsonl.
  Builds directly on .aai/scripts/update-check.mjs; no new engine.
- Remediation follow-up (2026-07-29): independent validation PASSed the
  cold-start O_EXCL claim but reproduced a residual on the CONCURRENT stale-lock
  RECLAIM path (two racers both pass the staleness read; the loser's rm deletes
  the winner's fresh lock -> two spawns). Root-caused to two things and both
  fixed: (1) the reclaim rm+create was not serialized (a lone O_EXCL create
  cannot arbitrate a reclaim that first removes the existing lock), now
  serialized behind an exclusive reclaim lock whose holder re-checks staleness
  after gaining exclusivity; (2) openSync('wx')+writeSync left a torn (empty)
  lock window that a concurrent reader mtime-aged as stale under an injected
  clock, now eliminated by creating locks with FULL content atomically
  (writeFile temp then linkSync). AC-005/AC-006 added; RR-1 is now closed for
  cold-start AND concurrent reclaim. Residual scoped in decisions.jsonl.
