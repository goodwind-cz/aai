---
id: no-nul-guard
type: issue
number: 62
status: draft
---

# P2 backlog cluster: docs-model-nul-escape (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `docs-model-nul-escape`: `fu-no-nul-guard`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-no-nul-guard`**: nothing checks tracked text files for NUL bytes, so a control character can silently turn a source file binary to POSIX grep
  - Measured: CHANGE-0147 found two NUL bytes in a shared library that had silently disarmed the negative taxonomy guard in test-aai-delta-stage2.sh line 210 (proven with a planted canary: the guard logged PASS while finding nothing). git grep and ripgrep still match, but the repo's own suites use POSIX grep, so the failure lands exactly where it is least visible. A repo-wide no-NUL check would have caught the original and all three relapses while writing the fix
  - Source: code review of PR 262, docs/ai/reviews/review-docs-model-nul-escape-20260817T153931Z.md

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `docs-model-nul-escape`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
