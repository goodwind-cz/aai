---
id: uncarved-dispatch-lanes
type: issue
number: 73
status: draft
---

# P2 backlog cluster: CHANGE-0165 (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `CHANGE-0165`: `fu-uncarved-dispatch-lanes`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-uncarved-dispatch-lanes`**: three dispatchable prompts still direct a subagent to run a STATE mutator without the dispatched-subagent carve, and STATE_FALLBACK's hand-edit path is un-reconciled
  - Measured: SKILL_CODE_REVIEW:150 grants the write on 'an explicit instruction' (broader than the D1 sole-agent carve — wording must be reconciled, not just pointed); SKILL_WORKTREE:166-167 writes target the NEW worktree's own STATE so the clause cannot be copied verbatim; METRICS_FLUSH:42 degraded path; found by validation r2 F7 and review r2 P3-N4 of CHANGE-0165, out of that spec's authoritative surface list
  - Source: docs/ai/reviews/review-20260824T172907Z-single-writer-canon-contradiction-round2.md

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `CHANGE-0165`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
