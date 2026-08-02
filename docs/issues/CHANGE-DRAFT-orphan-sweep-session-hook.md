---
id: orphan-sweep-session-hook
number: null
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — orphan-sweep: leaked runaway shells die at the next session start

## Summary
- Incident (2026-07-29 → 08-02): stress-test tool calls left 37 orphaned CPU
  busy-loops (~15 cores, almost 4 days) because their cleanup was a TRAILING
  `kill` that died with the parent when the harness's 120s tool timeout
  fired. The operator found them by hand; prose ("clean up after load
  tests") demonstrably does not fire.
- Measure (owner-directed): a deterministic session-start backstop.
  `.aai/scripts/orphan-sweep.mjs` selects processes that are ALL of:
  orphaned (PPID 1), agent-shell wrappers (args contain
  `shell-snapshots/snapshot-zsh-`), old (>=2 h), and hot (>=20 % CPU) — and
  kills them by PROCESS GROUP. Wired into `hooks/session-start.sh` with the
  same never-block watchdog contract as update-check; its one-line kill
  report rides the hook's context so the session SEES what was reaped
  (silent when nothing found).
- Safety: own PGID excluded; PGIDs <= 1 excluded; a group sharing its PGID
  with live foreign work is dropped whole; degenerate/garbage `ps` fields
  fail SAFE (not old enough); no `ps` (Windows) = silent no-op; empty
  pattern refused. Never pattern-kill by snapshot-id — a live session's own
  calls carry the same string (self-kill, verified live).

## Acceptance Criteria
- AC-001: selection requires ALL four predicates; live-parented, idle,
  young, and non-matching processes are never selected (fixture-proven).
- AC-002: the sweep's own process group and mixed groups (live foreign
  member) are never killed.
- AC-003: a real double-forked orphan (own PGID, PPID 1) is killed by group
  and the one-line report is emitted (real-kill test, thresholds zeroed for
  determinism).
- AC-004: nothing to reap -> zero output, exit 0; usage errors exit 2.
- AC-005: hook wiring is bounded (watchdog), best-effort, and pinned by test.

## Verification
- tests/skills/test-aai-orphan-sweep.sh TEST-001..008 (incl. the real-kill
  leg with platform skip guards); layer-profiles + hygiene-pack green.

## Constraints / Risks
- Ceremony L1, strategy direct (deterministic selection logic + real-kill
  test; no protected surface).
- The sweep only fires when a session starts in this project — a leak on a
  machine nobody opens sessions on stays alive (accepted: that machine's
  CPU is not being used by sessions either).
- Thresholds (2 h / 20 % CPU) are deliberately conservative; a pathological
  leaked process that idles below 20 % CPU is not reaped (accepted — the
  harm class is CPU burn).

## Notes
- Discovered risk during test authoring: a bash `( cmd & )` background job
  in a non-interactive shell SHARES the suite's PGID — a naive group-kill
  test kills the test run itself. The real-kill test stages its orphan via
  node `spawn({detached:true})` (setsid -> own PGID); recorded here because
  it is exactly the foot-gun class the self-pgid guard exists for.
