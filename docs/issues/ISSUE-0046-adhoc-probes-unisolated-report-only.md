---
id: adhoc-probes-unisolated-report-only
type: issue
number: 46
status: done
links:
  commits:
    - 24385e3
  pr:
    - TBD
---

# P2 backlog cluster: registry-audit-20260820 (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `registry-audit-20260820`: `fu-adhoc-probes-unisolated-report-only`, `fu-spec-closes-claim-unverified`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-adhoc-probes-unisolated-report-only`**: aai-run-tests.sh isolates suite runs only, by design, so every generator, build, node one-liner and probe a role runs through the canonical wrapper executes in the shipping tree with a guard that cannot fail the run
  - Measured: measured: a helper script through the canonical wrapper printed toplevel and pwd as the shipping repo on branch main; this is the surface the P1 fu-subagent-probe-hits-real-repo actually names, and worktree isolation does not cover it
  - Source: registry audit 2026-08-20; probe run through .aai/scripts/aai-run-tests.sh, PROBE-TOPLEVEL and PROBE-HEAD both the live repo

- **`fu-spec-closes-claim-unverified`**: a spec's 'Registry items closed by this scope' line is never checked against the ledger, so a frozen document can claim closures that never happened
  - Measured: measured 2026-08-20: SPEC-0137 named 3 items closed and 0 of those 3 were; CHANGE-0146 named 4 and 2 were. tests/skills/test-aai-deslop.sh test_030 already performs exactly this check for one scope, so the pattern exists and is simply not a general close-ceremony gate; a generic arm would have caught all three misses
  - Source: registry audit 2026-08-20, 85 open items reviewed against current main

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `registry-audit-20260820`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
