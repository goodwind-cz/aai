---
id: wrapper-hidden-suite-run-unreported
type: issue
number: 75
status: draft
---

# P2 backlog cluster: retire-the-tripwire-behind-its-replacement (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `retire-the-tripwire-behind-its-replacement`: `fu-wrapper-hidden-suite-run-unreported`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-wrapper-hidden-suite-run-unreported`**: aai-run-tests.sh reports not-applicable and stays SILENT for a real suite run whose command shape hides the suite path, running it in the shipping tree with no isolation line at all
  - Measured: aai_iso_is_suite_run only recognises an argument that is itself an existing file under REPO_ROOT/tests, so sh -c bash tests/skills/test-x.sh is classed as an invocation isolation was never meant to cover; not-applicable prints nothing, so the run is neither isolated nor degraded and the degraded gate can never see it
  - Source: measured 2026-08-22 on a throwaway wrapper fixture: the SAME ordinary probe suite ran isolated under bash tests/skills/test-aai-probe-ordinary.sh (write landed in the disposable checkout) and wrote straight to the shipping fixture tracked.txt under sh -c bash tests/skills/test-aai-probe-ordinary.sh, with no AAI-ISOLATION line emitted and only the report-only tripwire naming it; sibling of fu-adhoc-probes-unisolated-report-only, which covers non-suite commands rather than a suite run

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `retire-the-tripwire-behind-its-replacement`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
