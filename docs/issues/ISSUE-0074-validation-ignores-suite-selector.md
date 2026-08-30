---
id: validation-ignores-suite-selector
type: issue
number: 74
status: draft
---

# P2 backlog cluster: ride-cost-readout (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `ride-cost-readout`: `fu-validation-ignores-suite-selector`, `fu-orchestrator-does-not-watch-ci`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-validation-ignores-suite-selector`**: validation picks its suites from the declared review scope while CI picks them from select-suites, so a CORE suite can be skipped in validation and fail in CI
  - Measured: On CHANGE-0148 the selector marks aai-spec-lint CORE for any change, but the L1 validation dispatch told the role that the owning suite plus siblings were the relevant surface, so spec-lint never ran and TEST-011 failed 20 minutes into CI instead. The orchestrator wrote that instruction, so the fix is a rule not a reminder: a validation dispatch should run what select-suites returns for the changed files, never a hand-picked list
  - Source: PR 263 CI failure 2026-08-18, select-suites output CORE aai-spec-lint

- **`fu-orchestrator-does-not-watch-ci`**: after pushing a PR the orchestrator stops instead of watching CI, so a failure sits undetected until the owner asks
  - Measured: On PR 263 the full framework failed around 04:52 and the orchestrator learned of it at 07:02 when the owner asked — two hours and ten minutes of dead time. Every CI check today was owner-prompted, never self-initiated. Waiting is not watching. The fix is mechanical: after a push, poll the checks to settlement in the background rather than idling, the same discipline already demanded of subagents waiting on a long run
  - Source: PR 263, push 04:25, failure 04:52, detection 07:02

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `ride-cost-readout`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
