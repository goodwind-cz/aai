---
id: probe-redirect-lands-in-shipping-cwd
type: issue
number: 66
status: draft
---

# P2 backlog cluster: isolation-shares-the-shipping-git (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `isolation-shares-the-shipping-git`: `fu-probe-redirect-lands-in-shipping-cwd`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-probe-redirect-lands-in-shipping-cwd`**: a mutation probe's relative redirect resolved against the agent's own shell cwd - the shipping repository - because the fixture script ran before any cd, writing a stray file there
  - Measured: an unescaped ampersand in a sed replacement turned a redirect into 2>iso_git; the fixture's iso_create ran before any cd so the relative path resolved in the shipping checkout, the file survived unnoticed into a full 81-suite sweep, and its later removal inside a tripwire snapshot window failed aai-docs-audit; the tripwire was correct. HAZ-SCRATCH covers the agent path only as prose - nothing structurally stops a probe from writing the shipping tree, which is the same class this scope fixes for suites
  - Source: TDD Implementation deviation 1 on ride isolation-shares-the-shipping-git; sweep test-20260827-141912

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `isolation-shares-the-shipping-git`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
