---
id: index-regen-eats-untracked
type: issue
number: 56
status: draft
---

# P2 backlog cluster: operator-waiver-unblocks-pr (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `operator-waiver-unblocks-pr`: `fu-index-regen-eats-untracked`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-index-regen-eats-untracked`**: the AAI:INDEX-AUTOGEN pre-commit regen writes untracked working-tree files into the tracked docs/INDEX.md, so CI fails on an index listing a file it cannot see
  - Measured: measured three times on 2026-08-28 in one session: a local ISSUE-DRAFT and later a local CHANGE-DRAFT were each written into a committed index and failed the docs-audit suite with 'index lists X which no longer exists on disk'. The hook stages the regenerated index automatically, so the leak is silent at commit time and only surfaces on another machine
  - Source: tests/skills/test-aai-docs-audit.sh CI job 98919754521; .aai/scripts/install-pre-commit-hook.sh AAI:INDEX-AUTOGEN block; .aai/scripts/generate-docs-index.mjs

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `operator-waiver-unblocks-pr`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
