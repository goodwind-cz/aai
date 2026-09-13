---
id: seed-loss-turns-an-arm-into-a-skip
type: issue
number: 68
status: superseded
---

# P2 backlog cluster: a-half-seeded-checkout-says-it-is-isolated (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `a-half-seeded-checkout-says-it-is-isolated`: `fu-seed-loss-turns-an-arm-into-a-skip`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-seed-loss-turns-an-arm-into-a-skip`**: a seed path present in the working tree but absent from the checkout leaves the run GREEN at exit 0 while a suite reads an empty file, so an assertion silently becomes a passing skip
  - Measured: restated at P2 from the dropped P3 on validation's judgement, which reproduced it (probe J: the suite read an empty seed file and the run stayed green); this is coverage loss that reports itself only as a NOTE, and the same under-severity criticism was made of the sibling axis one ride ago
  - Source: validation round 1 of a-half-seeded-checkout-says-it-is-isolated, 2026-08-22; input to the tripwire-deletion scope

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `a-half-seeded-checkout-says-it-is-isolated`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).

## Superseded (2026-09-13)

This draft is a machine-clustered index of follow-up registry items, not a work item of its own. Under the wave-3 mandate (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`) the registry items it lists are closed by the subsystem sweep that owns them; each item keeps its own `follow-ups.mjs` record and resolution. Superseded so the intake list shows only work.
