# Deslop Skill - AI-Slop Removal Pass (Advisory)

ADVISORY ONLY — this skill never blocks, gates, or dispatches anything;
skipping or overriding it is always a valid outcome.

## Goal
Remove characteristic AI-generated noise before review, so reviewers spend
attention on behavior, not on narration. Scope is an explicit parameter —
see Scope below — never a silent repo-wide cleanup crusade.

Source: RES-0001 P3 recommendation 15 — pro-workflow deslop pass.

## Scope
Two scopes; the choice is never silent:
- `--diff`: classes 1-5 over `git diff <base>...HEAD` (or the staged diff)
  for the current scope.
- `--all`: class 4 ONLY (unrequested surface), over `.aai/scripts/**` and
  `.aai/system/*.yaml` only — not the whole `.aai/` tree (prompts, workflow
  and templates are out of scope) — report-only, run on demand, never an
  edit. Its suppression corpus is every `docs/specs/**`, `docs/issues/**` and
  `docs/rfc/**` document whose type is spec, change, issue, techdebt or rfc
  and whose status is accepted, implementing or done.

CONVENTION: a document that records FINDINGS about this tool (e.g. an
adjudication table naming candidate symbols) belongs in `docs/analysis/`,
never in a spec/change/issue/techdebt/rfc document — naming a symbol there
suppresses it, turning a finding into its own false negative (see
`docs/analysis/deslop-candidate-adjudication-20260815.md`).

If the invocation names neither scope, ASK the operator to pick one of the
two above and STOP until answered — never assume `--diff` by default.

If `--diff` finds an empty diff, the engine (below) exits 0 with a literal
`rerun with --all` note; OFFER the operator the wide scope at that point
instead of stopping.

## When
Optionally, after implementation is functionally complete and before code
review (`--diff`), or on demand at any time (`--all`).

## Slop-class table
Walk the diff once per class (`--diff`); delete or simplify every hit the
spec did not explicitly ask for. Class 4 is mechanically checked, both
scopes, by the companion engine:

```
node .aai/scripts/deslop-unrequested.mjs --diff [--base <ref>] [--json]
node .aai/scripts/deslop-unrequested.mjs --all [--json]
```

| # | Slop class | Signature | Action |
|---|---|---|---|
| 1 | Obvious comments | Comment restates the next line ("// increment i") or narrates the session ("// now we handle X") | Delete the comment |
| 2 | Defensive try/catch on trusted paths | Catch-and-continue around internal calls whose failure should fail fast (Constitution art. 4) | Remove wrapper; let errors surface with context |
| 3 | Premature abstraction | Helper/interface/param introduced for exactly one caller "for flexibility" | Inline it (YAGNI, Constitution art. 2) |
| 4 | Unrequested features | Behavior, flags, or config no AC asked for — run the engine above; its LIMITS block (suppressed count) is at most an upper bound on prose-suppression false negatives, never a floor, and never a clean bill of health | Remove; file an intake note if genuinely valuable |
| 5 | Annotations on untouched code | Comments, reformatting, import shuffles on lines outside the change's purpose | Revert those hunks entirely |

## Behavior-unchanged rule
A deslop pass must be a NO-OP for behavior. After edits, run the full test
suite through `bash .aai/scripts/aai-run-tests.sh <project test command>` (LEARNED
rule — never invoke the runner directly) and it must pass exactly as before
the pass. If any test changes outcome, the pass removed load-bearing code:
revert that edit — do not "fix" the test. Deleting a test is never deslop.
`--all` never edits anything — report-only by construction.

## Output format
`--diff`:
```
DESLOP advisory pass — <REF-ID> (scope: diff)
  Diff scope: <base>...HEAD (<N> files)
  Removed: class 1 xN, class 2 xN, ... (per-file hunks listed)
  Kept (looked like slop, is not): <item — why>
  Suite after pass: <command> → exit 0
```
`--all`: relay the engine's own report verbatim (human or `--json`), LIMITS
block included — there is nothing to walk, since this pass edits nothing.

## Rules
- Under `--diff`, a line not touched by this change is out of bounds (class 5
  exists to enforce this on the diff itself). `--all` is safe to look wider
  because nothing in the workflow dispatches this skill mid-ride.
- When unsure whether a guard/comment is load-bearing, keep it and note it
  under "Kept" — deslop errs toward keeping.
- The pass's completion claim ("suite green after deslop") goes through the
  `.aai/SKILL_VERIFY.prompt.md` gate: IDENTIFY → RUN → READ → VERIFY → CLAIM,
  with fresh evidence from the post-pass tree.
- Never present this pass as a review verdict; review remains
  `.aai/SKILL_CODE_REVIEW.prompt.md`'s job.
