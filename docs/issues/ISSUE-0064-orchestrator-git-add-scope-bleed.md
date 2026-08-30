---
id: orchestrator-git-add-scope-bleed
type: issue
number: 64
status: draft
---

# P2 backlog cluster: CHANGE-0142 (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `CHANGE-0142`: `fu-orchestrator-git-add-scope-bleed`, `fu-verify-staged-set-after-commit`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-orchestrator-git-add-scope-bleed`**: orchestrator must never git add -A while a subagent edits the same worktree; stage explicit paths
  - Measured: 2026-08-13: research-doc commits ba638e0/dddc780/8d88219/33f39ae swept the in-flight CHANGE-0142 TDD scope (follow-ups.mjs, generator, suites, prompt, diet ledger) under docs(research) subjects; nothing lost, history misleading
  - Source: git show --stat ba638e0 33f39ae; TDD agent report 2026-08-13T21:56Z

- **`fu-verify-staged-set-after-commit`**: orchestrator must verify git show --stat after every commit, not the exit code
  - Measured: 2026-08-13: a phantom path plus 2>/dev/null made git add fail wholesale, so a commit carried only a rename while every real change stayed unstaged and a branch was pushed without them
  - Source: commits aab26d2 then 2b0165f

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `CHANGE-0142`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
