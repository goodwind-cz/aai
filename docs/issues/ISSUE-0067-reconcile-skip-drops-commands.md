---
id: reconcile-skip-drops-commands
type: issue
number: 67
status: draft
---

# P2 backlog cluster: ISSUE-0035 (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `ISSUE-0035`: `fu-reconcile-skip-drops-commands`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-reconcile-skip-drops-commands`**: planStateReconcile skip() rebuilds the result with an empty echo array, so a reason raised by the second arm discards a command the first arm already planned
  - Measured: with a valid work item but a current_focus type outside the mirrored enum, the healthy set-phase vanishes and the WARN echoes nothing, so the close leaves the item stale, the next dispatch halts on closed_focus_stale_state and the operator is never told the repair command — D3 promises the WARN echoes the exact commands to run; found independently by review r1 Q-2 and by Codex on PR #290; deferred because the fix moves close-work-item.mjs's pinned content hash and must be bundled with the fu-closeworkitem-pin-tail-wording re-pin
  - Source: .aai/scripts/close-work-item.mjs:1123,1207; docs/ai/reviews/review-20260825T040439Z-close-leaves-state-stale.md

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `ISSUE-0035`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
