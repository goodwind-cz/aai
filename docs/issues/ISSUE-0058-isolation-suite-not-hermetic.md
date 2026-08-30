---
id: isolation-suite-not-hermetic
type: issue
number: 58
status: draft
---

# P2 backlog cluster: a-run-must-say-whether-isolation-armed (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `a-run-must-say-whether-isolation-armed`: `fu-isolation-suite-not-hermetic`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-isolation-suite-not-hermetic`**: test-aai-suite-isolation TEST-001, TEST-003 and TEST-005 inherit AAI_TEST_ISOLATION instead of stating it, so they go red when the operator exports 0
  - Measured: A spurious red on a legitimate operator setting trains people to ignore this suite; the TEST-101..107 arms added by CHANGE a-run-must-say-whether-isolation-armed now state their isolation explicitly and the SPEC-0138 arms should do the same
  - Source: measured 2026-08-22: AAI_TEST_ISOLATION=0 bash tests/skills/test-aai-suite-isolation.sh reds TEST-001/003/005 while the framework behaves exactly as designed

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `a-run-must-say-whether-isolation-armed`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
