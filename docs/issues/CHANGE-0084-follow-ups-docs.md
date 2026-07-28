---
id: follow-ups-docs
number: 84
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — recorded follow-ups batch B: stalled_progress friction class, EARS AC guidance, hash-display disposition

## Summary
- Remaining small follow-ups (operator direction 2026-07-28):
  1. NEW `stalled_progress` failure_class (7th taxonomy value): an
     AAI-directed run stalled — parked on a dead watcher, waited on an
     artifact no step produces, or looped without state change. Added to
     FRICTION_PROTOCOL taxonomy + all three enum sites (aai-friction,
     feedback-triage, feedback-upsert); TEST-020 pins accept+reject.
  2. EARS guidance in SPEC_TEMPLATE's AC-status section: write testable
     Description cells as "WHEN <trigger> the system SHALL <response>"
     (Kiro pattern) so ACs map 1:1 onto TEST assertions; plain statements
     stay legal for structural ACs; pipes stay forbidden.
  3. DISPOSITION (no code): the "metrics-report per-run hash display"
     follow-up is RESOLVED-AS-DESIGNED — the conditional grouping section
     (a role appears once its runs carry >1 distinct prompt_hash) shipped
     in SPEC-0096 and preserves report additivity; the always-on variant
     stays rejected. Mothership METRICS gain hashes with the first
     dispatch-driven loop runs (orchestrator Agent-tool dispatches bypass
     the dispatch hash by construction).

## Acceptance Criteria
- AC-001: stalled_progress accepted by record path and persisted; unknown
  class rejection names the seven-value enum (TEST-020, RED via the
  pre-change six-value rejection message).
- AC-002: SPEC_TEMPLATE carries the EARS guidance sentence (grep pin not
  needed — template text, spec-lint unaffected).
- AC-003: friction/triage/wiring suites green; taxonomy doc says seven.

## Verification
- bash tests/skills/test-aai-friction.sh (TEST-020)
- bash tests/skills/test-aai-feedback-triage.sh; test-aai-friction-wiring.sh

## Constraints / Risks
- Ceremony L1 (additive enum value + template prose); review waived with
  rationale (closed-set extension pinned both directions; bots at PR).
