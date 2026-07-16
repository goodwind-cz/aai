# Deslop Skill - Diff-Scoped AI-Slop Removal Pass (Advisory)

ADVISORY ONLY — this skill never blocks, gates, or dispatches anything;
skipping or overriding it is always a valid outcome.

## Goal
Remove characteristic AI-generated noise from the CURRENT DIFF before review,
so reviewers spend attention on behavior, not on narration. Strictly
diff-scoped: only lines this change introduced are candidates — never a
repo-wide cleanup crusade.

Source: RES-0001 P3 recommendation 15 — pro-workflow deslop pass.

## When
Optionally, after implementation is functionally complete and before code
review. Input: `git diff <base>...HEAD` (or the staged diff) for the current
scope. If the diff is empty, report "nothing to deslop" and stop.

## Slop-class table
Walk the diff once per class; delete or simplify every hit that the spec did
not explicitly ask for:

| # | Slop class | Signature | Action |
|---|---|---|---|
| 1 | Obvious comments | Comment restates the next line ("// increment i") or narrates the session ("// now we handle X") | Delete the comment |
| 2 | Defensive try/catch on trusted paths | Catch-and-continue around internal calls whose failure should fail fast (Constitution art. 4) | Remove wrapper; let errors surface with context |
| 3 | Premature abstraction | Helper/interface/param introduced for exactly one caller "for flexibility" | Inline it (YAGNI, Constitution art. 2) |
| 4 | Unrequested features | Behavior, flags, or config no AC asked for | Remove; file an intake note if genuinely valuable |
| 5 | Annotations on untouched code | Comments, reformatting, import shuffles on lines outside the change's purpose | Revert those hunks entirely |

## Behavior-unchanged rule
A deslop pass must be a NO-OP for behavior. After edits, run the full test
suite through `.aai/scripts/aai-run-tests.sh <project test command>` (LEARNED
rule — never invoke the runner directly) and it must pass exactly as before
the pass. If any test changes outcome, the pass removed load-bearing code:
revert that edit — do not "fix" the test. Deleting a test is never deslop.

## Output format
```
DESLOP advisory pass — <REF-ID>
  Diff scope: <base>...HEAD (<N> files)
  Removed: class 1 xN, class 2 xN, ... (per-file hunks listed)
  Kept (looked like slop, is not): <item — why>
  Suite after pass: <command> → exit 0
```

## Rules
- Diff-scoped only: a line not touched by this change is out of bounds
  (class 5 exists precisely to enforce this on the diff itself).
- When unsure whether a guard/comment is load-bearing, keep it and note it
  under "Kept" — deslop errs toward keeping.
- The pass's completion claim ("suite green after deslop") goes through the
  `.aai/SKILL_VERIFY.prompt.md` gate: IDENTIFY → RUN → READ → VERIFY → CLAIM,
  with fresh evidence from the post-pass tree.
- Never present this pass as a review verdict; review remains
  `.aai/SKILL_CODE_REVIEW.prompt.md`'s job.
