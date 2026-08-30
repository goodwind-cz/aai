---
id: sweep-scope-excludes-repo-root
type: issue
number: 70
status: draft
---

# P2 backlog cluster: the-tripwire-is-permanent-not-transitional (3 items)

## Summary
- Consolidated registry intake for 3 open P2 follow-up(s) filed against `the-tripwire-is-permanent-not-transitional`: `fu-sweep-scope-excludes-repo-root`, `fu-sweep-regex-misses-present-tense`, `fu-overview-shows-closed-ride-inflight`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-sweep-scope-excludes-repo-root`**: a claim-correction sweep scoped to .aai/ docs/ tests/ misses CHANGELOG.md at the repo root, where an unreleased entry freezes into a permanent dated section at the next release cut
  - Measured: found by validation: two unreleased entries restated the withdrawn tripwire claim almost verbatim and would have shipped into a dated release section - a false claim made permanent by the one process that is supposed to record history accurately
  - Source: validation round 1 of the-tripwire-is-permanent-not-transitional; the ride's own AC-004 declared the narrower scope and the orchestrator accepted it

- **`fu-sweep-regex-misses-present-tense`**: the AC-004 correction sweep regex matches only future-tense removal wording (will be removed, to be deleted, goes away), so a present-tense statement of a planned deletion passes through uncorrected
  - Measured: validation round 2 found SPEC-0138:75 (they are deleted by a separate change) and CHANGE-0152:31-33 (deleted by a separate one) still uncorrected inside AC-004's own declared docs/** scope; both are the document pair the correcting spec itself links, and both were invisible to the recorded sweep command because it has no bare are/is deleted alternative
  - Source: validation round 2 of the-tripwire-is-permanent-not-transitional; sweep command at docs/specs/SPEC-DRAFT-spec-the-tripwire-is-permanent-not-transitional.md line 332

- **`fu-overview-shows-closed-ride-inflight`**: STATE has no terminal phase and no clear-focus, so after close-work-item the generated overview keeps publishing the finished ride as the current in-flight scope until the NEXT ride calls set-focus
  - Measured: two independent bots flagged the shipped overview-data.json naming a closed scope as in-flight; the phase enum is planning|preparation|implementation|validation|code_review|remediation with nothing terminal, so the dashboard is structurally wrong between every pair of rides, not just this once
  - Source: PR 281 bot sweep; reset-block cleared the stale validation verdict but focus and phase have no supported clear

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `the-tripwire-is-permanent-not-transitional`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
