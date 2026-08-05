---
id: cheap-ticks
number: 120
type: change
status: draft
user_visible: true
ceremony_level: 2
links:
  pr: []
  commits: []
---

# Change — mechanical ticks stop respawning agents: confirm-by-script, scope edits by orchestrator, atomic freeze

## Summary
- Live cost forensics (InfluxDriver log): of ~11 agent runs for a one-line
  fix, at least 4 were process-self-repair that needed NO model judgment:
  (a) tick 1 respawned a FULL Implementation agent only to re-confirm an
  unchanged green state after a re-plan; (b) excluding the user's unrelated
  requirements.txt/.gitattributes changes from review scope ran a FULL
  re-Planning agent — a mechanical list edit; (c) Planning wrote
  `SPEC-FROZEN: true` while frontmatter stayed `status: draft` — the
  dispatcher bounced the scope back to Planning to fix its own paperwork.
- Three deterministic fixes:
  1. CONFIRM-BY-SCRIPT: when a re-plan changes no AC/TEST mapping for
     already-green items (computable diff of the spec's AC table + test
     list), the dispatcher marks the phase confirmed via a script check —
     no agent dispatch. Any real delta still dispatches normally.
  2. SCOPE EDITS AS STATE MUTATIONS: review-scope include/exclude of
     files UNTOUCHED by the ride (user side-changes) becomes an
     orchestrator-level spec edit via a small tool (audited, EVENTS line),
     not a Planning dispatch. Content changes to AC/tests still go to
     Planning.
  3. ATOMIC FREEZE: one tool writes status+marker together
     (spec-freeze.mjs or a state.mjs-adjacent script — NOT protected
     surfaces); spec-lint flags the half-frozen state at WRITE time so the
     mismatch cannot survive to dispatch.
- Expected effect (from the log's shape): ~3-4 agent runs saved on small
  rides = the difference between "small fix" and "3-5 % of a weekly limit".

## Acceptance Criteria
- AC-001: no-delta re-plan -> dispatcher confirms via script, EVENTS line
  recorded, zero agent dispatch (fixture); any AC/test delta -> normal
  dispatch (control).
- AC-002: scope-exclusion tool edits the spec's review-scope list only for
  paths with no ride-diff, refuses otherwise; audited.
- AC-003: half-frozen spec (marker without status) is a spec-lint finding;
  the freeze tool cannot produce it.

## Constraints / Risks
- Ceremony L2 — touches orchestration-dispatch.mjs (core) + spec-lint +
  a new small tool + prompts (ledger). The riskiest of the three intakes;
  ride with full validation.
- Honesty: confirm-by-script must compare against the FROZEN spec content,
  not trust the re-plan's self-report.
