---
id: validation-defers-the-ac-flip-to-close
number: 164
type: change
status: done
user_visible: false
ceremony_level: 2
capability: aai-validation
links:
  pr:
    - 285
  commits:
    - 6774dd786d3814977a9b28d3b0fc3d515a2a9bc9
---

# Change — the canon tells validation to do the thing the repo's own heuristic flags

## Summary
- `VALIDATION.prompt.md` step 8a presumes the validator populates the spec's AC
  Evidence column ("For each Spec-AC that moved to `done` during this
  validation (Evidence column populated)…").
- `docs-audit`'s probable-false-open heuristic flags exactly that state: a
  fully terminal, evidenced AC table under a frontmatter `status` that is still
  `implementing`. The flag is CORRECT — that state is what a false-open looks
  like. The canon instructs the role to manufacture it.

## Evidence
Measured across four rides, 2026-08-22..24:

- Validation round 2 of `the-subagent-contract-omits-the-hazards` followed 8a
  literally, populated the Evidence column, and broke
  `test-aai-doc-numbering.sh` TEST-013 (docs-audit NEEDS-TRIAGE,
  probable-false-open naming the spec). It reverted by hand and filed
  `fu-ac-table-flip-trips-false-open` (P2).
- Since then every ride's dispatch carries a hand-written workaround: "Do NOT
  populate the spec's AC Evidence column; the orchestrator flips it immediately
  before the close." Four dispatches this session repeat it verbatim.
- A rule that lives in dispatch prose is followed unevenly here — that is the
  measured finding of CHANGE-0159, and this is one more instance of the same
  anti-pattern.
- 8a already contains an EXCEPTION with the same logic for the `ac_evidence`
  EVENT (slug-ref, still-open doc → defer emission to close). The column flip
  needs the same rule; today the exception covers the event but not the state
  that triggers the heuristic.

## Impact
- Every ride pays a workaround in dispatch prose; a ride that misses it turns
  `test-aai-doc-numbering.sh` red between validation and close.
- The window is not hypothetical: docs-audit runs inside three CORE suites, so
  ANY suite run in that window fails on an unrelated red.

## Desired Behavior
The deferral IS the canon: validation records per-AC evidence in its report;
the AC table flips terminal at the close step, immediately before
`close-work-item.mjs`, so the false-open-shaped window lasts seconds, not
hours. The heuristic stays exactly as strict as it is.

## Acceptance Criteria
- AC-001: `VALIDATION.prompt.md` states the deferral as the rule — validation
  MUST NOT flip AC rows or populate Evidence on a still-open doc; evidence goes
  in the validation report; the flip happens at close. The existing 8a
  event-EXCEPTION folds into the same statement instead of standing beside it.
- AC-002: the close-side instruction (wherever the close ceremony is specified)
  names the flip as its own step, ordered before `close-work-item.mjs`, so the
  rule has a home at BOTH ends.
- AC-003: prompt-corpus governance satisfied and MEASURED: diet-ledger entry at
  the measured byte delta if the corpus grows, TEST-010/TEST-012 green, and no
  rule sentence duplicated across files (`spec-subagent-protocol-slim` TEST-002
  discipline applies to the corpus generally).
- AC-004: an arm pins the deferral rule so deleting it from the prompt bites.
  Prove by mutation with an unmutated control. The arm must not be a prose
  count nothing asserts.
- AC-005: `docs-audit`'s heuristic is untouched. This scope moves the
  instruction, not the guard.

## Verification
- prove AC-004 by mutation in a disposable clone
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns
- run `bash tests/skills/test-aai-doc-numbering.sh` to prove no regression

## Constraints / Risks
- Ceremony 2: this edits the payload every Validation role reads.
- The prompt corpus is budgeted (`HEADROOM_CAP` 2048 B). The net delta should
  be near zero: the new rule largely REPLACES the existing exception text.
- Do not weaken the heuristic, the close gate, or TEST-013 to make this easier.
- No secret is referenced by this scope.

## Notes
- Closes `fu-ac-table-flip-trips-false-open` (P2).
- Ride discipline: ship on these acceptance criteria and nothing else; the new
  registry policy applies — record no-bite P3 observations as accepted
  residuals in reports, file only what bites or lies.
