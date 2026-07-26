---
id: friction-capture-default-on
number: 62
type: change
status: done
links:
  pr:
    - 162
  commits:
    - 5c4d232f249c079ab2a29d8e4667a13cf0154e80
---

# Change — Activate the friction feedback loop: default-on shadow capture + wrap-up triage feed

## Summary
- The RFC-0012 self-improvement loop has complete infrastructure (capture CLI,
  schema v2, redaction, offline triage, review-mode upsert) and ZERO data:
  docs/ai/friction/ holds only .gitkeep after weeks of sessions. Make shadow
  capture actually fire by default for AAI-owned failures, and make the
  wrap-up triage step surface captured observations as proposed intakes.

## Motivation / Business Value
- A self-improvement loop with no input data improves nothing (auditor report
  2026-07-26, roadmap item 4; telemetry finding (c): friction/ empty despite
  RFC-0012/0013 done). This session alone hit 4+ capturable AAI-owned
  frictions (validator monitor stalls, spec-table pipe parser break, stale
  L3 test landmines, prompt-diet cap trap) — none were captured because the
  seam depends on agents remembering a best-effort side-step mid-failure.

## Scope
- In scope:
  - Diagnose WHY zero captures: audit .aai/system/FRICTION_PROTOCOL.md's
    "Skill wiring (shadow capture)" seam (taxonomy, exclusions, trigger
    conditions) against this session's known friction events; identify the
    mechanical gaps (planning deliverable).
  - Strengthen the seam so capture fires at deterministic hook points
    (validation FAIL recorded, remediation dispatched, CI check failure
    handled, gate/lint failure on a canon file) rather than relying on
    free recall; keep capture best-effort and never masking the primary
    result (protocol invariant unchanged).
  - Wire SKILL_WRAP_UP step 6 so a non-empty spool ALWAYS produces the
    triage report and lists top clusters as proposed intake one-liners.
  - Prompt-diet ledger + PROFILES companions per canon.
- Out of scope: any network/publish behavior change (upsert stays
  review-mode, --confirm only); schema changes; new external destinations.

## Affected Area
- .aai/system/FRICTION_PROTOCOL.md, .aai/SKILL_WRAP_UP.prompt.md, possibly
  role prompts at the deterministic hook points, .aai/scripts/aai-friction.mjs
  (only if a mechanical trigger helper is needed), tests/skills friction
  suites.

## Desired Behavior (To-Be)
- An AAI-owned failure at a deterministic hook point yields one spool line
  (schema v2, redacted) without operator action; wrap-up surfaces clusters
  as proposed intakes; empty spool stays silent.

## Acceptance Criteria
- AC-001: the seam names deterministic hook points (at minimum: validation
  FAIL, remediation dispatch, canon-file gate/lint failure) and the wired
  prompts invoke the capture at those points (grep-verified).
- AC-002: a fixture AAI-owned failure produces exactly one valid v2 spool
  line via the documented command; a non-AAI failure (per exclusions)
  produces none (suite-verified).
- AC-003: SKILL_WRAP_UP with a non-empty fixture spool emits the triage
  report and proposed-intake lines; with an empty spool it stays silent
  (suite-verified).
- AC-004: capture remains best-effort: a capture error never changes the
  primary step's exit code (negative-control test).
- AC-005: no regression — targeted friction suites + prompt-diet green
  locally; binding full run on PR CI.

## Verification
- bash tests/skills/test-aai-friction.sh
- bash tests/skills/test-aai-friction-wiring.sh
- bash tests/skills/test-aai-prompt-diet.sh
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected (no protected surface; verify at planning).
- Risk: hook-point prose grows the prompt corpus — ledger true-up required;
  keep additions pointer-thin per the dedup discipline.
- Local-run policy: targeted suites only; CI binding.

## Notes
- Source: auditor roadmap item 4; session evidence of uncaptured frictions
  2026-07-26. Autopilot intake (/aai-ship): metrics question skipped,
  human_time_minutes intake recorded as null.
