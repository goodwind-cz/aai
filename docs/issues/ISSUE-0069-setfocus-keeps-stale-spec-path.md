---
id: setfocus-keeps-stale-spec-path
type: issue
number: 69
status: draft
---

# P2 backlog cluster: deslop-scope-and-unrequested-engine (3 items)

## Summary
- Consolidated registry intake for 3 open P2 follow-up(s) filed against `deslop-scope-and-unrequested-engine`: `fu-setfocus-keeps-stale-spec-path`, `fu-tdd-skips-full-sweep`, `fu-validation-staleness-undetected`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-setfocus-keeps-stale-spec-path`**: set-focus to a new ref leaves the previous scope's spec_path in current_focus, so the next dispatch hands the role a foreign spec as an input
  - Measured: Retargeting focus to the new intake still listed SPEC-0131 from the finished scope on the Planning inputs line; it took an explicit --clear spec_path to remove it, and nothing warns when ref and spec_path disagree
  - Source: observed 2026-08-14T10:54Z, .aai/scripts/state.mjs set-focus

- **`fu-tdd-skips-full-sweep`**: the TDD role declares done after targeted suites only, so defects visible only to the full framework sweep surface two roles later and cost a whole validate-remediate lap each
  - Measured: This ride burned roughly 2.5 hours on two extra laps for F0 (spec-lint allowlist) and F10 (CHANGELOG scaffold), both of which only the sweep sees; the cheap suites run early and the 47-minute one runs last, so its findings always arrive after the expensive roles have finished
  - Source: ticks 104-109, 2026-08-14; sweep is 47 min and nests suites (delta-stage3 to delta-stage2 to spec-lint)

- **`fu-validation-staleness-undetected`**: a validation pass survives a later remediation that rewrites the validated code, and the default routing skips re-validation
  - Measured: Round 3 passed at 15:37Z; code review then failed and remediation rewrote the engine, suite, prompt and eight surfaces, yet SPEC-0012 G3 routing sends a pass-with-review-reset straight to rule 13 and never re-fires rule 11. Only the validator noticing its own staleness caught it, and clearing it needed an owner-approved reset-block --force. The verdict should carry the content hash it was taken against so staleness is mechanical, not a matter of an agent volunteering it
  - Source: observed 2026-08-14, owner decision recorded; state.mjs reset-block refusal message

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `deslop-scope-and-unrequested-engine`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
