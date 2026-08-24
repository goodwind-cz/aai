---
id: spec-a-branch-diff-pin-taxes-every-later-scope
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: a-branch-diff-pin-taxes-every-later-scope
  rfc: null
  pr: []
  commits: []
---

# Spec — a pin on one scope's diff must not bill every later scope

SPEC-FROZEN: true

Ceremony justification: one arm of one test file changes. No product surface,
no script, no prompt, no schema; the durable half of the same arm is held
byte-identical and re-proved by mutation. Single-surface, reversible in one
revert.

## Links
- Requirement: docs/issues/CHANGE-DRAFT-a-branch-diff-pin-taxes-every-later-scope.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Problem in one paragraph

`tests/skills/test-aai-spec-lint.sh` `test_clarify_011_no_new_ceremony` has two
halves. The first pins live text in `.aai/scripts/spec-lint.mjs` and
`.aai/scripts/spec-freeze.mjs` — their usage lines and exit contracts — and is
the arm's actual content. The second walked `git diff --name-only <main> --
.aai/` and refused any path outside a hand-maintained allowlist. Because `main`
moves, that half stopped describing the clarify scope the day it merged and
started describing whatever the current branch does. Six recorded payments, all
from unrelated scopes, none a clarify-scope ceremony addition.

## Implementation strategy
- Strategy: direct
- Rationale: the change is one arm of one existing suite. The evidence that
  matters is a mutation proof per surviving pin plus an unmutated green control,
  observed live in a disposable clone; there is no new module to grow a
  RED-first cycle around.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one tracked file changes; suite mutations happen in a
  detached disposable clone that is removed with a targeted
  `git worktree remove`.
- User decision: inline
- Base ref: fix/allocator-reports-its-own-degrade (cut from main at f65ae56)
- Worktree branch/path: disposable, scratch-only, never committed
- Inline review scope: tests/skills/test-aai-spec-lint.sh plus this spec

## Decision — repair, not remove

The branch-diff half is REPAIRED, not deleted. The repair replaces the moving
reference with a stored manifest of the clarify scope's own three `.aai/` paths
and measures the LIVE tree against it: the clarification gate's vocabulary
(`unresolved-clarification`, `NEEDS-CLARIFICATION`) must appear in exactly the
three files commit `43eef8e` touched, and nowhere else under `.aai/`.

Why not a fixed commit range. `git diff 43eef8e^ 43eef8e -- .aai/` is a fact
frozen in history: it cannot change, so an arm asserting it cannot fail for a
real reason. It can only fail for a false one — a shallow CI checkout where
`43eef8e` is unreachable. That trades a tax for a tautology plus a flake.

Why not deletion. The claim the half was evidence for is CONTAINMENT — the
clarify feature added no ceremony beyond three files — and containment is still
checkable against the live tree, cheaply, with zero cost to unrelated scopes.
Deleting a claim that can still be measured is worse than measuring it.

What the repair still loses, named plainly. The old half was, by accident, a
general tripwire: it made EVERY scope declare its `.aai/` footprint in a code
review that nothing else in this repo performs. That sweep goes away. Nothing
now notices when an unrelated scope edits an `.aai/` path it did not intend to.
That coverage was never owned by this arm, never precise (0 true positives in 6
recorded payments), and belonged to a scope-footprint check nobody has written;
its absence is a real hole and is recorded here rather than sold as a cleanup.

## Acceptance Criteria Mapping

- Maps to: AC-001
- Spec-AC-01: WHEN `spec-freeze.mjs`'s usage line or any of its four exit-contract
  phrases is mutated THEN `test_clarify_011_no_new_ceremony` SHALL report FAIL,
  and SHALL report PASS on the unmutated tree.
- Verification: in a disposable clone, mutate one pinned string at a time and run
  `bash tests/skills/test-aai-spec-lint.sh`; expect the TEST-011(clarify) line to
  read FAIL for each mutation and PASS for the control.

- Maps to: AC-002
- Spec-AC-02: WHEN an arbitrary unrelated `.aai/` file is added or edited on a
  branch cut from main THEN `test_clarify_011_no_new_ceremony` SHALL still report
  PASS.
- Verification: in a disposable clone, create `.aai/scratch-unrelated-probe.md`
  and run `bash tests/skills/test-aai-spec-lint.sh`; expect
  `PASS TEST-011(clarify)`.

- Maps to: AC-003
- Spec-AC-03: The arm SHALL contain no `git diff` against `main` or `origin/main`
  and no path allowlist; it SHALL instead compare a stored three-path manifest to
  the set of `.aai/` files carrying the clarification-gate vocabulary, and SHALL
  report FAIL when a fourth `.aai/` file carries that vocabulary.
- Verification: `grep -n "origin/main\|branch diff\|base_ref" ` over the arm
  returns nothing; and in a disposable clone add `.aai/probe-clarify-spread.md`
  containing `unresolved-clarification`, run
  `bash tests/skills/test-aai-spec-lint.sh`, expect `FAIL TEST-011(clarify)`.

- Maps to: AC-004
- Spec-AC-04: No literal count SHALL appear in the arm's prose or in its pass
  line unless the arm computes it at run time from the measurement it just made.
- Verification: read the arm's pass line; the number in it comes from a shell
  variable assigned by counting the measured carrier set, and the arm's comments
  state no path or group count.

- Maps to: AC-005
- Spec-AC-05: `fu-test011-branch-diff-allowlist-tax` SHALL be closed in the
  follow-up ledger, and the allowlist with its twelve case groups SHALL be gone
  from the arm.
- Verification: `node .aai/scripts/follow-ups.mjs list --status all --json` shows
  the id with a resolution record; `grep -c "payment of this allowlist tax"` over
  the suite returns 0.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                              | Status       | Evidence | Review-By | Notes                          |
|------------|--------------------------------------------------------------------------|--------------|----------|-----------|--------------------------------|
| Spec-AC-01 | the two spec-freeze pins still bite under mutation and pass unmutated      | implementing | —        | —         | durable half held byte-identical |
| Spec-AC-02 | an unrelated .aai/ edit no longer fails the arm                            | implementing | —        | —         | proved in a disposable clone   |
| Spec-AC-03 | the branch-diff half is replaced by a live containment measurement          | implementing | —        | —         | repair, not removal            |
| Spec-AC-04 | any number printed by the arm is computed by the arm                       | implementing | —        | —         | prose carries no count         |
| Spec-AC-05 | the follow-up closes and the allowlist is gone                             | implementing | —        | —         | fu-test011-branch-diff-allowlist-tax |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-spec-lint.sh`, function
  `test_clarify_011_no_new_ceremony` only. No other file in `tests/` and no file
  under `.aai/` changes, so neither prompt-corpus companion obligation applies.
- Data flow: the arm reads two script files for the durable pins, then reads the
  live `.aai/` tree once for the containment measurement. It no longer invokes
  `git` at all.
- Edge cases: a `.aai/` file that mentions the vocabulary in passing counts as a
  carrier and fails the arm — that is the intended bite, and it names the defect
  class rather than a path. An unreadable file under `.aai/` surfaces on stderr
  rather than being suppressed.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                 | Description                                                            | Status  |
|----------|------------|-------------|--------------------------------------|------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01 | integration | tests/skills/test-aai-spec-lint.sh   | mutate spec-freeze usage line in a clone; arm reports FAIL              | pending |
| TEST-102 | Spec-AC-01 | integration | tests/skills/test-aai-spec-lint.sh   | mutate one spec-freeze exit-contract phrase in a clone; arm reports FAIL | pending |
| TEST-103 | Spec-AC-01 | integration | tests/skills/test-aai-spec-lint.sh   | unmutated control clone; arm reports PASS                               | pending |
| TEST-104 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh   | add an unrelated .aai/ file in a clone; arm still reports PASS          | pending |
| TEST-105 | Spec-AC-03 | integration | tests/skills/test-aai-spec-lint.sh   | add a fourth .aai/ carrier of the gate vocabulary; arm reports FAIL     | pending |
| TEST-106 | Spec-AC-04 | unit        | tests/skills/test-aai-spec-lint.sh   | the pass line's number is a shell variable computed from the carrier set | pending |
| TEST-107 | Spec-AC-05 | unit        | tests/skills/test-aai-spec-lint.sh   | no allowlist case group and no payment comment remain in the suite      | pending |

Every command above is directly executable: `bash tests/skills/test-aai-spec-lint.sh`
inside the named clone, plus the greps quoted in the Verification lines.

## Verification
- `bash tests/skills/test-aai-spec-lint.sh` on the real tree — whole suite green.
- The five clone runs above, each read for the TEST-011(clarify) line, not for
  the process exit code alone.
- `node .aai/scripts/select-suites.mjs --files-from <changed>` and every suite it
  returns.
- Evidence artifacts: the transcripts of each clone run, quoted in the return
  block.
- PASS criteria: all TEST-1xx green AND all Spec-AC in a terminal status. This
  ride leaves them at `implementing` by dispatch instruction; the close ceremony
  is not run here.

## Evidence contract
- ref_id: a-branch-diff-pin-taxes-every-later-scope
- Spec-AC and TEST links: as tabulated above.
- Command / scope: `bash tests/skills/test-aai-spec-lint.sh` in the real tree and
  in each disposable clone; `tests/skills/test-aai-spec-lint.sh` is the whole diff
  besides this spec.
- Exit code: recorded per run, alongside the TEST-011(clarify) line itself.
- Evidence path: run transcripts in the return block; no stored artifact is owed
  by a `direct` ride.
- Commit SHA: not applicable — this dispatch does not commit.
