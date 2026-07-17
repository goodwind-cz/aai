---
id: tdd-red-evidence-classification
type: change
number: 33
status: done
links:
  pr:
    - 96
  commits:
    - a8a3bf2
---

# Change — Machine-Distinguish Product RED from Infrastructure-Failure RED

## Summary
`.aai/SKILL_TDD.prompt.md` Phase 1 requires RED evidence to show the test
"FAILS for the right reason (not syntax error)" (RED Phase Checklist item),
but the evidence FORMAT it prescribes — a raw saved log at
`docs/ai/tdd/red-[timestamp].log` plus a `state.mjs set-tdd-cycle --status
RED --red <path>` call — carries no structured field that distinguishes (a)
an expected PRODUCT red (the test ran, exercised the not-yet-implemented
behavior, and its assertion failed for the spec'd reason) from (b) an
INFRASTRUCTURE failure (test runner crashed, import/module resolution
error, timeout, syntax error in the test file itself). Both currently
produce a non-zero exit code and a saved log, and both currently satisfy the
letter of "RED observed." This change adds a classification field to the RED
evidence/log so infra-fail RED can be mechanically rejected as RED-proof.

## Motivation / Business Value
- `.aai/SKILL_TDD.prompt.md` already names the risk in prose ("Failure is
  for the right reason (not syntax error)" — RED Phase Checklist) and in the
  Troubleshooting section ("Test never fails (can't get RED)... Verify test
  is actually calling new functionality"), which shows the authors knew this
  failure mode exists — but enforcement is left to the author/reviewer
  reading the log by eye, not to a check any tooling (spec-lint, docs-audit,
  Validation) can run.
- Same root class as the SPEC-0013 H7 "fixture diversity" and "would this
  suite stay green if only the happy path were implemented" rules already in
  this file (lines 132-139) — those close the "RED evidence exists but is
  vacuous" gap for MISSING fixtures; this change closes the parallel gap for
  a RED that exists but is the WRONG KIND (infra noise, not a real assertion
  failure against the spec'd behavior).
- Concrete risk: a broken import path or a runner crash on a freshly-created
  test file exits non-zero and produces a log that satisfies today's
  "test FAILS when run (verified)" checklist item mechanically, letting a
  TDD cycle proceed to GREEN "fixing" the crash rather than proving the
  originally intended behavior was ever exercised — a false-RED that
  quietly invalidates the RED-GREEN proof the whole SKILL_TDD ceremony
  exists to produce.

## Scope
- In scope:
  - RED evidence format (the saved `docs/ai/tdd/red-*.log` artifact and/or
    the `set-tdd-cycle --status RED` STATE record): add a classification
    field distinguishing `product_red` (assertion failed for the spec'd
    reason) from `infra_fail` (runner/import/timeout/syntax error before the
    intended assertion could even run).
  - `.aai/SKILL_TDD.prompt.md` Phase 1 wording: make the classification step
    explicit (how to tell the two apart — e.g. an infra_fail log shows a
    stack trace/exception from the runner or module loader BEFORE any
    assertion output, vs. a product_red log shows the test's own assertion
    message).
  - A gate (spec-lint at freeze-adjacent time, or a TDD-evidence check
    consumed by Validation) that rejects `infra_fail`-classified RED as
    satisfying the "RED observed" requirement.
- Out of scope:
  - Changing the GREEN or REFACTOR phase evidence formats.
  - Auto-detecting the classification purely by parsing arbitrary test
    runner output across every language/framework (out of scope for a first
    pass) — the author records the classification; a best-effort heuristic
    check is a reasonable stretch goal, not a hard requirement of this
    change.

## Affected Area
- `.aai/SKILL_TDD.prompt.md` (Phase 1: RED evidence capture and checklist).
- `.aai/scripts/state.mjs` (`set-tdd-cycle` — if the classification is
  recorded as a STATE field rather than only inside the log file).
- Any consumer that currently reads TDD RED evidence for a completeness
  check (spec-lint, Validation's TDD-evidence review).

## Desired Behavior (To-Be)
- Every RED evidence artifact carries an explicit classification:
  `product_red` or `infra_fail` (naming convention open to Planning; the
  field must be present and machine-readable, e.g. a line in the log file
  header and/or a `--red-class` flag on `set-tdd-cycle`).
- `product_red` requires the log to show the test's OWN assertion failure
  message (the expected-vs-actual the test was written to check), not a
  runner/import/syntax exception.
- An `infra_fail`-classified RED does NOT satisfy the SKILL_TDD "RED
  observed" gate — the author must fix the infrastructure issue and
  re-capture a `product_red` before proceeding to GREEN.
- Existing RED evidence (pre-change logs) is not retroactively reclassified
  or invalidated — this is a forward-looking gate on newly captured
  evidence.

## Acceptance Criteria
- AC-001: The RED evidence format (log and/or STATE `set-tdd-cycle` record)
  carries a classification field with exactly two values,
  `product_red`/`infra_fail` (or equivalent named pair), with no default
  that silently passes as `product_red`.
- AC-002: `.aai/SKILL_TDD.prompt.md` Phase 1 gives a concrete, checkable
  rule for telling the two apart (e.g. "assertion output present before any
  runner-level exception" vs. "runner/import/syntax exception with no
  assertion output reached").
- AC-003: A fixture representing an `infra_fail` RED (e.g. a deliberately
  broken import in a new test file) is rejected by the gate — the TDD cycle
  cannot advance to GREEN on that evidence; a fixture representing a genuine
  `product_red` (assertion failure for the spec'd reason) is accepted.
- AC-004: No regression to existing TDD cycles that already recorded
  `product_red`-shaped evidence under the old, unclassified format — the
  gate change is additive (new RED evidence going forward) and does not
  retroactively fail closed/done work items.

## Verification
- Fixture-driven test proving AC-003's accept/reject split (new suite
  stanza or extension of an existing TDD-evidence check).
- `grep -n "RED Phase Checklist" -A 15 .aai/SKILL_TDD.prompt.md` shows the
  amended checklist including the classification step.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- Manual dry run: a scratch test file with a broken import captured as RED
  evidence is correctly flagged `infra_fail` and rejected; the same test
  file fixed to fail only on its intended assertion is accepted as
  `product_red`.

## Constraints / Risks
- The classification is initially author-asserted (recorded, not fully
  auto-derived) — risk of a careless/incorrect self-classification; mitigate
  by keeping AC-002's rule concrete enough for a reviewer or Validation to
  spot-check against the raw log, same as today's "for the right reason"
  checklist item is spot-checked.
- Must not add ceremony to every TDD cycle disproportionate to the problem —
  a single required field plus one gate check, not a new phase.
- Language/framework-agnostic: the rule in AC-002 must work across the
  polyglot test runners this repo and downstream AAI projects use (bash
  suites, npm/vitest, pytest, cargo, etc.) — express it in terms of
  "assertion output reached" rather than a specific runner's exception
  format.

## Notes
- Existing related discipline in the same file: SPEC-0013 H7 fixture
  diversity checklist and the "would this suite stay green with only the
  happy path" RED-proof extension (`.aai/SKILL_TDD.prompt.md` lines
  132-139) — this change is the natural sibling gate for RED evidence KIND
  rather than RED evidence COVERAGE.
- Filed as part of the same 2026-07-17 intake batch responding to EEX
  downstream operator feedback and independent in-repo confirmation of
  related gaps.
