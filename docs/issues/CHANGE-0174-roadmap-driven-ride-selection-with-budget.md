---
id: roadmap-driven-ride-selection-with-budget
number: 174
type: change
status: draft
links:
  pr: []
  commits: []
---

# Rides come from the roadmap, and every maintenance ride must be paired with a capability

## Summary
- Roadmap wave 1, pair 1, maintenance half. Paired capability ride:
  `live-agent-dashboard-served-locally`.
- Implements four owner decisions of 2026-09-05 (`hitl_decision`
  `capability-roadmap-drives-rides`, `maintenance-budget-one-to-one`,
  `internal-work-without-asking`, `review-round-cap`). Today they are ledger
  lines; nothing in the factory reads them.

## Why (measured)
Since 2026-08-01: 132 merged PRs, ~10 operator-visible capabilities, ~31 of 81
feat+fix rides in fix-of-fix chains around six concerns. Rides were chosen from
whatever the last review surfaced. Nothing stopped a fix from spawning the next.

## Change
A deterministic ride-selection gate consulted by SKILL_SHIP / SKILL_LOOP before
a new ride starts, plus the canon text that makes the rules binding downstream.

## Acceptance Criteria
- **AC-001** `docs/ai/roadmap.yaml` is the machine-readable form of
  `docs/project-sessions/2026-09-05-capability-roadmap.md`: ordered pairs, each
  with a `capability` ref and a `maintenance` ref and a status. A validator
  refuses a pair with two maintenance refs.
- **AC-002** `node .aai/scripts/ride-select.mjs` prints the next ride: the
  first pair whose capability is not done, capability half first. It exits
  non-zero with a named reason when asked to start a maintenance ride whose
  paired capability is not at least `implementing`.
- **AC-003** A fix/chore/harness/guard ride that is not on the roadmap is
  refused by the gate with the message "file it to the backlog" and the
  follow-ups command — unless the intake carries `blocks: <roadmap ref>`, which
  the gate verifies exists and is not done.
- **AC-004** `.aai/AGENTS.md` (vendored, so `/aai-update` carries it) states the
  four rules in operator terms: internal work is done without asking; owner
  questions only as a menu with a recommended default; two review rounds max
  then split; 1:1 maintenance budget. Under 40 added lines; prompt-diet ledger
  credited to the measured byte count.
- **AC-005** VALIDATION canon: a third finding-bearing round is a STOP with the
  instruction to split the ride, not a fourth round.
- **AC-006** Suite `tests/skills/test-aai-ride-select.sh` covers AC-001..003
  both arms; `test-aai-prompt-diet.sh` green with the credit.

## Out of scope
- Rewriting existing open follow-ups into the roadmap.
- The dashboard itself (paired ride).

## Constraints / Risks
- This IS a guard ride — the one the budget allows because it is what makes the
  budget real. It ships in the same pair as the dashboard, never alone.
- The gate must be bypassable by the owner with an explicit flag that is
  logged, never silently.
