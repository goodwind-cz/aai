---
id: dev-progress-hub
number: 67
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Dev-progress view in the overview: what the factory is doing right now

## Summary
- The overview page shows delivered/in-progress/waiting-on-you but nothing
  about the RUNNING ride: which phase the current focus is in, what the
  last loop ticks did, which verdicts landed. Add an "In flight now"
  section to generate-overview.mjs sourced from STATE.yaml (focus, phase,
  strategy, validation/review status) and the tail of LOOP_TICKS.jsonl
  (last N ticks: role, scope, duration, tick outcome), with honest
  absent-file degradation (fresh clone => section omitted).

## Motivation / Business Value
- Original assignment: a viewer over "jak probiha vyvoj" (how development
  is progressing), not only what was delivered. Operators today read
  STATE.yaml and JSONL tails by hand.
- STATE.yaml and LOOP_TICKS are per-developer local (gitignored) — the
  section renders only where a ride actually runs, which is exactly the
  audience that needs it.

## Scope
- In scope:
  - generate-overview.mjs: "In flight now" section — current focus (ref,
    type, phase, strategy, worktree decision), verdict chips (validation/
    review status), and the last 5 LOOP_TICKS entries (tick, role, scope,
    duration_seconds, harness) rendered as a compact table; graceful
    omission when STATE or ticks are absent/unparseable (no error, no
    empty section).
  - overview-data.json gains the same structured block (in_flight).
  - Tests: fixture STATE+ticks render; absent-file omission; malformed
    tick line skipped (extend test-aai-overview.sh).
- Out of scope: live auto-refresh/websockets; docs hub restructure;
  historical tick analytics (metrics-report owns aggregate views).

## Affected Area
- .aai/scripts/generate-overview.mjs, tests/skills/test-aai-overview.sh,
  docs/product/dev-progress-hub.md (this scope is user_visible).

## Desired Behavior (To-Be)
- Running a ride and regenerating the overview shows the live focus,
  phase, verdicts and recent ticks; a fresh clone shows no In-flight
  section and no errors.

## Acceptance Criteria
- AC-001: fixture STATE + ticks render the section with focus/phase/
  verdicts and exactly the last 5 ticks, newest first (suite-verified).
- AC-002: absent STATE or absent/empty ticks file => section omitted
  entirely, exit 0 (suite-verified).
- AC-003: a malformed JSONL tick line is skipped without error and does
  not consume one of the 5 slots (suite-verified).
- AC-004: overview-data.json carries the structured in_flight block
  mirroring the rendered data (suite-verified).
- AC-005: no regression — overview suite green locally; full run on CI.

## Verification
- bash tests/skills/test-aai-overview.sh
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 (no protected surface).
- STATE parse must reuse the existing minimal reader in the script (no new
  YAML dependency); never render raw STATE content beyond the known enum
  fields (no accidental leak of notes/questions beyond the HITL question
  already shown in waiting_on_you).

## Notes
- Roadmap ride #7 (original-assignment gap: dev-progress viewer).
  Autopilot intake: metrics question skipped, human_time_minutes null.
