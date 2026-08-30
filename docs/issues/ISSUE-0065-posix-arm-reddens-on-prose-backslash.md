---
id: posix-arm-reddens-on-prose-backslash
type: issue
number: 65
status: draft
---

# P2 backlog cluster: index-arm-diffs-whole-file-for-a-path-claim (3 items)

## Summary
- Consolidated registry intake for 3 open P2 follow-up(s) filed against `index-arm-diffs-whole-file-for-a-path-claim`: `fu-posix-arm-reddens-on-prose-backslash`, `fu-staleness-source-line-self-certifies`, `fu-posix-predicate-exit-conflates-infra`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-posix-arm-reddens-on-prose-backslash`**: index_posix_findings tests every line for a backslash, not only path tokens, so a Notes cell mentioning a regex reddens the arm with index path is not POSIX
  - Measured: inherited from the retired arm so not a regression, but it is the same misattribution defect class this ride was chartered to eliminate, surviving inside the narrowed arm
  - Source: validation round1 attack A11

- **`fu-staleness-source-line-self-certifies`**: index_stale_findings derives its scanned dirs from the Source: line of the index under test, so an index stale because a family was added never checks that family
  - Measured: demonstrated rc 0 on a genuinely stale index with tracked_checked silently falling 369 to 227; the arm self-certifies
  - Source: validation-20260821T123200Z-index-arm-diffs-whole-file-for-a-path-claim-round1.md attack A5

- **`fu-posix-predicate-exit-conflates-infra`**: index_posix_findings exits 1 both for real path findings and for the predicate failing to run, and does not fold stderr into the captured output, so an infrastructure failure surfaces as a path defect with an empty message
  - Measured: reproduced: with the docs-model.mjs import failing the shipped predicate exits 1 with empty stdout, so the arm prints FAIL: committed docs/INDEX.md must carry forward-slash paths only: with nothing after the colon; the shell sibling index_stale_findings gets this right with STALE-CHECK ABORTED; fix is exit 2 for cannot-run plus 2>&1 capture
  - Source: review-20260821T130500Z-index-arm-diffs-whole-file-for-a-path-claim.md finding 2; tests/skills/test-aai-docs-audit.sh:1956-2007,2246,2250

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `index-arm-diffs-whole-file-for-a-path-claim`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
