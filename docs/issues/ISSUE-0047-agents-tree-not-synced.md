---
id: agents-tree-not-synced
type: issue
number: 47
status: draft
---

# P2 backlog cluster: harness-surfaces-drift-unguarded (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `harness-surfaces-drift-unguarded`: `fu-agents-tree-not-synced`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-agents-tree-not-synced`**: .agents/skills/ is a tracked shipped skill tree that neither aai-sync.sh nor aai-sync.ps1 copies
  - Measured: it is Cursor's FIRST documented project-skills path, so a vendored downstream project never receives it; grep for '.agents' in both sync scripts returns nothing; deliberately out of the CHANGE scope because the sync scripts carry a byte-identity test plus two managed-prefix lists (distinct blast radius)
  - Source: .aai/scripts/aai-sync.sh; .aai/scripts/aai-sync.ps1; docs/specs/SPEC-DRAFT-harness-surfaces-drift-unguarded.md D5

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `harness-surfaces-drift-unguarded`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
