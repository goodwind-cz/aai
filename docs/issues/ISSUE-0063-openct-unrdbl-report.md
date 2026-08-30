---
id: openct-unrdbl-report
type: issue
number: 63
status: draft
---

# P2 backlog cluster: followups-cli-hardening (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `followups-cli-hardening`: `fu-openct-unrdbl-report`, `fu-sync-hash-compare-fails-open`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-openct-unrdbl-report`**: generate-factory-report.mjs:616 publishes follow_ups.open_count: 0 for an UNREADABLE ledger (e.g. --decisions a directory), the same 'a bad input reads as good news' shape D2 refuses on the CLI; the file's own oldest_age_days convention two lines down already uses null, never 0, for exactly this degradation
  - Measured: the honest fix is open_count: registry.unreadable ? null : openFollowUps.length, but Spec-AC-07 of SPEC-DRAFT-spec-followups-cli-hardening.md pins generate-factory-report.mjs byte-unchanged, so it cannot be done inside that scope without breaking a frozen AC
  - Source: docs/ai/reviews/review-20260818T094328Z-followups-cli-hardening.md NB-3

- **`fu-sync-hash-compare-fails-open`**: file_content_different in aai-sync.sh treats an unobtainable hash as different, so a transient sha256sum hiccup silently rewrites the target's copilot shim and plants a project-overrides file
  - Measured: Diagnosed from PR 264's CI-only failure. Under set -o pipefail a failed fork in the sha256sum awk pipeline flips the comparison to different; at aai-sync.sh:445 that switches the copilot-instructions shim from copy_replace into the merge branch, which mutates the tree. Simulating one transient failure on Linux reproduced the reported symptom byte for byte. The fix is to fail closed: treat an unobtainable hash as not different, or read the hash without a pipefail-sensitive pipeline
  - Source: diagnosis of PR 264 skill-suite failure on 2d122b4, aai-sync.sh lines 142-173 and 445

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `followups-cli-hardening`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
