---
id: dispatch-prompt-coaching-bias
type: issue
number: 51
status: draft
---

# P2 backlog cluster: role-verification-guards (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `role-verification-guards`: `fu-dispatch-prompt-coaching-bias`, `fu-ts-precision-unify-source`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-dispatch-prompt-coaching-bias`**: my role dispatches pre-rank findings and name the pattern to look for, which frames the answer before the role forms one
  - Measured: The PR-gate reviewer recorded the coaching per its anti-gaming contract and noted that its BLOCKING finding plus four of eight non-blocking ones were absent from my pre-ranked list. Context is legitimate; a ranked answer key is not. Dispatches should carry evidence and reproductions, never a priority order or a conclusion to weigh first
  - Source: code review 2026-08-16, docs/ai/reviews/review-20260816T191852Z-role-verification-guards.md

- **`fu-ts-precision-unify-source`**: state-engine.mjs nowIso() truncates ISO timestamps to the second while append-event.mjs keeps milliseconds; orchestration-dispatch.mjs now defends against this at the comparison site (Date.parse + Number.isFinite instants), but the two producers still disagree at the source
  - Measured: Any FUTURE consumer that compares a state.mjs-stamped timestamp against an append-event.mjs-stamped timestamp inherits the same same-second trap unless it also remembers to parse-as-instant; unifying precision at the source (both keep milliseconds, or both truncate) removes the trap for every future comparison instead of relying on each call site to defend itself. state-engine.mjs is protected_paths_l3 and out of scope for this remediation, so this cannot be fixed in-tree here
  - Source: docs/ai/validation/validation-20260816T203700Z-role-verification-guards-round4.md BLOCKING-1; .aai/scripts/lib/state-engine.mjs:39-41 nowIso(); .aai/scripts/append-event.mjs:64

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `role-verification-guards`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
