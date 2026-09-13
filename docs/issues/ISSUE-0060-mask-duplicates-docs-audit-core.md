---
id: mask-duplicates-docs-audit-core
type: issue
number: 60
status: superseded
---

# P2 backlog cluster: CHANGE-0144 (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `CHANGE-0144`: `fu-mask-duplicates-docs-audit-core`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-mask-duplicates-docs-audit-core`**: the specimen masker in spec-lint.mjs duplicates docs-audit-core.mjs:782-875 more weakly, reintroducing both bugs that file fixed under SPEC-0013 W3
  - Measured: review NB-2: a line-initial three-backtick inline span opens a phantom fence and silences the gate document-wide; a three-backtick example nested in a four-backtick fence falsely refuses a legitimate freeze; corpus impact today is nil (0 candidates across 130 specs), so it is deferred, not ignored
  - Source: docs/ai/reviews/review-20260814T020405Z-CHANGE-0144-vagueness-gate.md NB-2

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `CHANGE-0144`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).

## Superseded (2026-09-13)

This draft is a machine-clustered index of follow-up registry items, not a work item of its own. Under the wave-3 mandate (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`) the registry items it lists are closed by the subsystem sweep that owns them; each item keeps its own `follow-ups.mjs` record and resolution. Superseded so the intake list shows only work.
