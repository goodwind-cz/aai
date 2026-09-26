---
id: gate-checks-declared-mutation
type: change
number: 193
status: done
capability: gate-checks-declared-mutation
links:
  pr:
    - 398
  commits:
    - 3e43a9ebe92b707f58c26faf8a9135ed63359a8c
---

# The mutation gate checks that the recorded run is the mutation the row declares

## Summary
- Drains `fu-gate-ignores-declared-mutation` (P2), named in SPEC-0186's Registry
  section as NOT CLOSED BY THAT SCOPE.
- `mutation-gate.mjs:273-279` checks only that a Test Plan row's Mutation cell is
  non-empty and not a placeholder (`-`, `—`, `TBD`, `pending`). It never compares
  that cell to what the stored record actually mutated, so a record produced by a
  DIFFERENT mutation satisfies the row.

## Motivation / Business Value
- Found live on 2026-09-25: TEST-694's cell declared "stop comparing
  `owner_signoff` … the arm that asserts an unsigned record is refused reddens".
  No such arm existed, and `mutation-TEST-694.txt` carried
  `target: .aai/VALIDATION.prompt.md` — a different file entirely. The gate
  printed `GATE PASS: 26 row(s) satisfied`.
- Every ride since PR #384 has cited GATE PASS as evidence that the DECLARED
  mutation reddens. It only ever proved that SOME mutation reddened SOMETHING.
  The discipline this project runs on — "every claim is held by a test that
  provably reddens" — is enforced at scale by this gate alone, so the gap makes
  that enforcement an honour system.
- Validation round 3 of SPEC-0186 read all 26 records by hand: 23 matched their
  cell, 3 were faithful paraphrases, 1 was a genuine substitution. Hand-reading
  does not scale and is exactly what the gate exists to replace.

## Measurement (taken 2026-09-26, before any change)
- The gate governs 5 specs and 229 non-empty Mutation cells (every other spec's
  Test Plan predates it; 1904 rows corpus-wide carry an empty cell).
- Of those 229: **124** already carry a machine-readable `sed:` or `patch:`
  token, **15** name a file path but no token, **90** are pure prose.
- A record stores `target` (repo-relative path) and `mutation` (the expression,
  e.g. `sed:s/OLD/NEW/` or `patch:<path>`) — `lib/mutation-record.mjs:17-18`.

So more than half the corpus is comparable TODAY with no format change.

## Scope
- In scope: the gate compares a row's declared mutation to its record where the
  declaration is machine-readable (a `sed:`/`patch:` token, or a named path that
  must match the record's `target`); a row whose cell cannot be compared is
  reported in a NAMED, visible class rather than counted as satisfied in silence;
  a ratchet so the count of uncomparable cells cannot grow.
- Out of scope: rewriting the 90 prose cells. They become visible and drainable,
  not a blocker — converting them is the next ride's work if the owner wants it.
- Out of scope: `fu-mutation-evidence-is-gitignored` and
  `fu-mutation-gate-absent-tree-passes`. They are the same neighbourhood but
  their repair is an owner policy decision about whether mutation evidence stops
  being gitignored.

## Affected Area
- `.aai/scripts/mutation-gate.mjs`, `.aai/scripts/lib/mutation-record.mjs`,
  `tests/skills/test-aai-mutation-gate.sh`.

## Desired Behavior (To-Be)
- A row whose cell declares a comparable mutation and whose record does not match
  it is OFFENDING and named, with both the declared and the recorded value
  printed — the failure must say what was declared and what was found.
- A row whose cell cannot be compared is counted and named in its own class, so
  `GATE PASS` never again means "we did not look".
- The uncomparable count is ratcheted downward only.

## Notes
- Ceremony 2, TDD. The gate is the thing being fixed, so every criterion needs a
  mutation that reddens it — a gate that cannot detect its own sabotage would be
  the very defect this change exists to close.
