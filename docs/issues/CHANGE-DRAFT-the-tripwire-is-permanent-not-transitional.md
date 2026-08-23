---
id: the-tripwire-is-permanent-not-transitional
number: null
type: change
status: draft
user_visible: false
ceremony_level: 2
capability: aai-suite-isolation
links:
  pr: []
  commits: []
---

# Change — the tripwire is permanent, and calling it transitional is now the false claim

## Summary
- On 2026-08-19 the owner recorded an `hitl_decision`: the tripwire is
  **explicitly TRANSITIONAL**, and once suites run in a disposable worktree
  "the tripwire, its known-offender ratchet and the hashing all go".
- Disposable-worktree isolation landed (SPEC-0138). The successor arrived. The
  tripwire cannot go, and the reason is measured, not a matter of appetite.

## Evidence
Measured on `main` at `07e6d81`, and re-verified by hand:

```
cd <disposable worktree>
git rev-parse --git-common-dir   ->  <shipping repo>/.git
dirname                          ->  <shipping working tree>
```

A worktree **shares the common git dir**, so isolation relocates a suite's cwd
and script path but does not remove its reach. A suite that resolves that path
writes the shipping tree while the run correctly reports `isolated` — `degraded`
cannot fire, because nothing degraded. Filed as
`fu-isolated-suite-reaches-shipping-repo` (P1).

The retirement scope that tried to act on the 2026-08-19 decision measured the
counterfactual end to end: with the tripwire deleted and the proposed
degraded-gate in place, a run exits 0 at `Passed: 2 (100%) / 0 degraded` **with
the write landed**. It stopped on its own AC-002 rather than proceed.

Both isolation documents already concede this in prose ("not `cannot` … that is
not closed here"), and give it as the reason the tripwire stays armed. So the
repository simultaneously states that the tripwire is temporary and that the
thing which would replace it does not cover the case.

## Impact
- `SPEC-0137` line 318 tells a reader the ratchet and the hashing are going
  away. They are not. A frozen spec that promises a removal nobody can perform
  is the same defect class this programme has spent three days removing.
- While "transitional" stands, every defect in the tripwire has a standing
  excuse for not being fixed: it is about to be deleted. **Fifteen are open.**

## Desired Behavior
The record says what is true: the tripwire is a permanent layer, its removal is
not scheduled, and the condition that would change that is named.

## Acceptance Criteria
- AC-001: `SPEC-0137`'s transitional claim is corrected in place — as a dated
  correction citing the measurement, never a silent edit of a frozen spec.
- AC-002: a new `hitl_decision` supersedes the 2026-08-19 one, appended not
  rewritten, naming what changed (the successor landed and does not cover the
  reach case) and what would reopen the question.
- AC-003: exactly one registry item closes —
  `fu-tripwire-removal-needs-a-gate` (P2), whose whole content is a
  precondition for a deletion that is no longer planned. **Do not close the
  other fifteen.** They are defects in a layer that now stays, and the
  scope must state that count rather than bury it.
- AC-004: any other surface that calls the tripwire temporary is found and
  corrected. Sweep, do not assume `SPEC-0137` is the only one.
- AC-005: no behaviour changes. Not one line of `repo-tripwire.sh`,
  `test-framework.sh` or `aai-run-tests.sh` moves. This scope edits the record.

## Verification
- prove AC-004 by a sweep over `.aai/**`, `docs/**` and `tests/**` for
  transitional/temporary/"will be removed" wording about the tripwire
- prove AC-005 by `git diff --stat` naming zero executable files
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- **This is a decision record, not a fix.** It must not read as if the fifteen
  open defects were resolved. The honest headline is that one item closes and
  fifteen lose their excuse.
- `SPEC-0137` is frozen and `done`. Correct it as an append-style dated
  correction; do not rewrite history to look consistent.
- `docs/ai/decisions.jsonl` is append-only. The 2026-08-19 `hitl_decision`
  stays exactly as written; the new one supersedes it by being later.
- Ceremony 2: this reverses a recorded owner decision on the basis of a
  measurement. The owner approved that reversal in this session, and the
  approval belongs in the record alongside the measurement.
- No secret is referenced by this scope.

## Notes
- Closes `fu-tripwire-removal-needs-a-gate` (P2). Fifteen tripwire defects stay
  open and are listed in the spec so nobody has to re-derive the set.
- Ride discipline: ship on these acceptance criteria and nothing else.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, reading an exit code after a pipe reports the
  pipe's last command, and in JavaScript `String.replace` a `$'` in the
  REPLACEMENT means "everything after the match".
