---
id: exit-contract-pin-comment-dup
type: issue
number: 55
status: draft
---

# P2 backlog cluster: a-branch-diff-pin-taxes-every-later-scope (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `a-branch-diff-pin-taxes-every-later-scope`: `fu-exit-contract-pin-comment-dup`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-exit-contract-pin-comment-dup`**: TEST-011(clarify)'s spec-freeze exit-contract pins (grep -qF "$p" "$f") check the WHOLE FILE, not the emitted string; spec-freeze.mjs's header comment (lines 54-61) duplicates all four exit-contract phrases verbatim above the runtime strings (lines 101-106) that actually compose the CLI output
  - Measured: mutating ONLY the live runtime string (leaving the header comment untouched) for any of the four phrases -- 0 frozen, 2 usage error, 3 REFUSED, 1 internal error -- still reports PASS TEST-011(clarify), because the comment's identical substring still satisfies grep -qF; validated on all 4 phrases independently in a disposable clone, each reverted before the next; the usage-line pin (single occurrence, no duplicate comment) is unaffected and correctly bites on the same in-string mutation style
  - Source: disposable worktree val-abdptl-wt at 0672ab5; per-phrase sed mutation + bash tests/skills/test-aai-spec-lint.sh, reverted with git checkout HEAD -- .aai/scripts/spec-freeze.mjs between runs; distinct from fu-usage-pin-misses-appended-flag (that one is an appended-flag substring-superset issue on the usage line; this one is a same-file duplicate-comment issue on all four exit-contract phrases)

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `a-branch-diff-pin-taxes-every-later-scope`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
