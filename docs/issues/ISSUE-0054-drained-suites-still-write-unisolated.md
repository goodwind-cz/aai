---
id: drained-suites-still-write-unisolated
type: issue
number: 54
status: draft
---

# P2 backlog cluster: drain-the-tripwire-known-offender-list (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `drain-the-tripwire-known-offender-list`: `fu-drained-suites-still-write-unisolated`, `fu-test013-uncovered-on-legal-max-raise`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-drained-suites-still-write-unisolated`**: the four formerly exempt suites still write the shipping repository when isolation is off, so 'zero tripwire ALLOWED lines before the drain' proves the branch was unreachable, not that nothing was forgiven
  - Measured: under disposable-worktree isolation NO suite can dirty the shipping tree, so zero ALLOWED is structurally guaranteed for all 81 suites and has no discriminating power; the framework comment's 'none of them writes to the shipping repository any more' and the commit message's 'they were just there' overstate what was measured
  - Source: measured 2026-08-23 in a disposable worktree at 7c5a09c with AAI_TEST_ISOLATION=0: bash tests/skills/test-framework.sh --skill aai-state gave FAIL [TRIPWIRE] with ' M docs/INDEX.md' and a ratchet-path hash hit; --skill aai-token-capture gave FAIL [TRIPWIRE] with ' M docs/ai/overview-data.json' and ' M docs/ai/overview.html'; both at 0/1 attested clean

- **`fu-test013-uncovered-on-legal-max-raise`**: TEST-013 is coupled to a shipped entry count of exactly zero, so the ratchet's 'the cheapest legal edit is one number' argument does not hold: raising TRIPWIRE_RATCHET_MAX_ENTRIES leaves the suite red
  - Measured: TEST-014 survives a legitimate max raise but TEST-013 goes UNCOVERED with no legal one-line repair, which reintroduces the delete-the-arm temptation the length ratchet was chosen over an emptiness assertion to avoid; TEST-013 needs only the two fixture suite names absent from the table, not a count of zero
  - Source: measured 2026-08-23 in a disposable worktree at 7c5a09c: mutation M3 added one entry and set TRIPWIRE_RATCHET_MAX_ENTRIES=1; TEST-014 PASS at 1 entry under maximum 1 while TEST-013 FAIL UNCOVERED 'the shipped table holds 1 entr(ies), so this arm is not testing a drained table'; suite exit 1

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `drain-the-tripwire-known-offender-list`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
