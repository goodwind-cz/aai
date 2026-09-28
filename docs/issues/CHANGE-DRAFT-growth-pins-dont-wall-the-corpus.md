---
id: growth-pins-dont-wall-the-corpus
type: change
number: null
status: draft
capability: growth-pins-dont-wall-the-corpus
links:
  pr: []
  commits: []
---

# A ride's own growth pin stops walling every ride that comes after it

## Summary
- Three arms in `tests/skills/test-aai-prompt-diet.sh` assert that a prompt file's
  CURRENT on-disk byte count equals the `after` figure recorded in one past
  ride's diet-ledger entry:
  `tests/skills/test-aai-prompt-diet.sh:1503` (`.aai/ROLE_COMMON.md`),
  `:1601` (`.aai/SKILL_UPDATE.prompt.md`), `:1661` (`.aai/VALIDATION.prompt.md`).
- The moment any LATER ride changes one of those files by a single byte, `now`
  stops equalling `after` and the arm fails — for work that has nothing to do
  with the ride that set the pin.
- The only repair the arm accepts is editing that past entry, which
  `tests/skills/test-aai-git-ref-guard.sh:935` (TEST-312) forbids by name:
  *"credit must be paid by ADDING an entry, never by editing history"*.
  **The two constraints are mutually unsatisfiable**, so the file is walled.

## Motivation / Business Value
- Found 2026-09-28 by a validation round bought for PR #388, which changes
  `.aai/VALIDATION.prompt.md`. Measured there: merge-base 21152, main 21570,
  that branch 23163, merged 23581 — merging green is impossible either way.
- Two of the three arms (`:1601`, `:1661`) were shipped by
  `canon-is-a-build-artifact` (SPEC-0186, PR #395) on 2026-09-26, so this is a
  wall this factory built for itself two days ago and has not yet walked into
  on its own account.
- It is the `guard-preconditions-downstream` class: a pin that was true and
  useful for its own ride becomes a precondition every later ride must satisfy
  and cannot.

## Scope
- In scope: the three arms verify what their comment says they verify — that
  the RIDE credited what it actually grew — against a state that cannot rot,
  namely the file as it stood in that ride's own commit, rather than against
  the working tree's current size.
- In scope: a guard that a future arm of this shape cannot be added, so the
  pattern does not reappear the next time someone pins their own ride's growth.
- Out of scope: the diet ledger's append-only discipline, TEST-312, and the
  corpus-wide `want_growth` ratchet — all three are correct and stay.
- Out of scope: PR #388's own content. This unblocks it; it does not judge it.

## Affected Area
- `tests/skills/test-aai-prompt-diet.sh`.

## Desired Behavior (To-Be)
- A ride that edits `.aai/VALIDATION.prompt.md`, `.aai/SKILL_UPDATE.prompt.md`
  or `.aai/ROLE_COMMON.md` and credits its growth in the ledger merges green,
  without editing any historical entry.
- The three arms still catch what they were written to catch: an entry whose
  credited figure disagrees with its own measurement, and a ride that grows the
  corpus without paying for it.

## Notes
- Ceremony 1, TDD. Small and surgical. The risk is writing an arm that no longer
  catches anything — so each must be observed FAILING against a fabricated
  mis-credited entry before it is trusted, not merely observed passing.
