---
id: mutation-gate-for-tests
type: change
number: 187
status: draft
capability: mutation-gate-for-tests
links:
  pr: []
  commits: []
---

# A test is admitted only with the mutation that reddens it

## Summary
- Wave 3, ride 4 after the owner's re-order of 2026-09-14
  (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`, "Re-order").
  Paired maintenance half: `unrecorded-spec-amendment-is-invisible`
  (CHANGE-0181) — both close the same gap: a gate that judges a record instead
  of the thing the record is about.
- Sweeps 1–3 needed three to eight validation rounds each. Almost every
  BLOCKING finding was one class: a control that claimed a property it did not
  test — a pin on a moving ref, a guard whose exception disabled it, a test
  whose fixture could not reach the branch under test, a `cp` retry that
  named a cause the file never had. Every one of them was found by the same
  move: change the code so the property is false, run the test, watch it stay
  green. That move is done today by a subagent because the dispatch text asks
  for it. Nothing in canon asks for it (`SKILL_TDD.prompt.md` and
  `VALIDATION.prompt.md` do not contain the word), and nothing at close checks
  that it happened.
- The capability: mutation evidence becomes a produced artefact with a fixed
  shape, canon requires it for every Test Plan row of a TDD ride, and the close
  ceremony refuses a TDD ride whose Test Plan has a row without one.

## Motivation / Business Value
- The owner's question of 2026-09-14 was "why are you still fixing things".
  The answer was this class. A validator finds it at the price of a round; a
  gate finds it at the price of one command, before the round exists.
- Downstream projects install the same prompts. A discipline that lives in
  one orchestrator's dispatch text does not reach them; a guard does
  (operator contract rule 5: a rule that must hold wherever AAI is installed
  is a guard, not a note).

## Scope
- In scope:
  - `mutation-run.sh` (or `.mjs`): given a test id, a suite, a target file and
    a mutation (a `sed` expression or a patch file), it applies the mutation
    to an isolated clone, runs the selected test, restores nothing in the
    shipping tree because it never touched it, and writes
    `docs/ai/tdd/<spec-id>/mutation-<TEST-id>.txt` with a fixed header
    (test id, suite, file, mutation, tree sha, rc, the first FAIL line) and a
    verdict `RED` / `STAYED GREEN`. A mutation that leaves the test green is
    recorded as such, never dropped.
  - The Test Plan table gains a `Mutation` column (spec-lint aware): the
    mutation id and the observed red line, so the claim is in tracked text
    while the full record stays in the gitignored evidence tree.
  - `mutation-gate.mjs`: for a spec with `implementation_strategy: tdd` (from
    STATE or the spec's Strategy section), every Test Plan row must name a
    mutation whose evidence file exists, whose verdict is `RED`, and whose
    tree sha is an ancestor of HEAD. Exit non-zero naming every row that
    lacks one; a degrade (evidence tree absent in CI, legacy spec frozen
    before this change) is printed by name, never silent.
  - Wiring: `SKILL_TDD.prompt.md` GREEN step requires the mutation before the
    REFACTOR step; `VALIDATION.prompt.md` requires re-running every mutation
    record and reporting any that stayed green as BLOCKING;
    `close-work-item.mjs` (or `SKILL_PR` step 4a's gate list) runs
    `mutation-gate.mjs` for TDD rides; `check-test-registration.mjs` or
    spec-lint refuses a Test Plan row with an empty Mutation cell on an
    in-flight TDD spec.
  - The paired maintenance half (CHANGE-0181): the strict amendment gate
    judges a frozen spec's content against its freeze-time hash, not only the
    presence of a record — same shape, same ride.
  - Bucket from the registry: `fu-test210-branch-now-dead-code` (a mutation
    arm that became unreachable and still passes), `fu-learned-immutable-pin-lint`
    (a comment that claims immutability over a moving resolve),
    `fu-test029-count-not-subset`, `fu-probe-redirect-lands-in-shipping-cwd`
    (the runner's isolation makes this structurally impossible),
    `fu-test-selector-unknown-id-passes` (a selector that runs nothing and
    passes), `fu-dispatch-gate-spawn-seam-untested`, DEBT-0007 (withdrawn-claim
    sweeps are not verifiable — a claim without a mutation is what "not
    verifiable" means here).
- Out of scope: retro-fitting mutation records to the 60 tests of sweep 2 or
  the 25 of sweep 3 (their validators re-ran them; the gate degrades by name
  for specs frozen before this change); mutation *coverage* scoring (one
  mutation per test is the bar, not a percentage); PowerShell suites (Pester
  has its own idiom; a follow-up).

## Affected Area
- `.aai/scripts/mutation-run.sh`, `.aai/scripts/mutation-gate.mjs` (new);
  `.aai/scripts/spec-lint.mjs`, `.aai/scripts/lib/docs-model.mjs` (Test Plan
  reader), `.aai/scripts/close-work-item.mjs` or `SKILL_PR.prompt.md` gate
  list, `.aai/scripts/spec-amend.mjs` + `spec-freeze.mjs` (CHANGE-0181);
  `.aai/SKILL_TDD.prompt.md`, `.aai/VALIDATION.prompt.md`, `.aai/ROLE_COMMON.md`
  (prompt-diet ledger entries; headroom is 2 bytes at 2046/2048 — the ride
  must buy room by diet, not exceed the cap); `.aai/system/PROFILES.yaml`;
  `tests/skills/test-aai-mutation-gate.sh` (new), `test-aai-spec-lint.sh`,
  `test-aai-close-work-item.sh` (re-pin), `test-aai-spec-amend.sh`,
  `test-aai-prompt-diet.sh`.

## Desired Behavior (To-Be)
- A TDD ride cannot close with a test that has never been seen failing for
  the right reason.
- A mutation that stays green is a recorded fact the validator reads, not a
  sentence in a report.
- An honest implementer's cost is one command per test; the dishonest path
  (a Test Plan row with no mutation) is refused by name.

## Acceptance Criteria
- AC-001: `mutation-run.sh` applies a named mutation in an isolated clone,
  runs one selected test, and writes the evidence file with the fixed header;
  the shipping tree is byte-identical before and after (proved by a tripwire
  in the suite).
- AC-002: A mutation that leaves the test green produces a `STAYED GREEN`
  record and a non-zero exit; the record is never deleted by a later run.
- AC-003: `mutation-gate.mjs` exits non-zero and names every Test Plan row of
  an in-flight TDD spec that lacks a `RED` mutation record whose tree sha is
  an ancestor of HEAD; exits 0 when every row has one.
- AC-004: The close ceremony of a TDD ride runs the gate and refuses on its
  non-zero exit; a non-TDD ride is unaffected.
- AC-005: spec-lint refuses an in-flight TDD spec whose Test Plan row has an
  empty or malformed Mutation cell; terminal specs and specs frozen before
  this change are exempt by name.
- AC-006: Canon names the requirement: SKILL_TDD's GREEN step, VALIDATION's
  per-test check and ROLE_COMMON's evidence rules each carry one sentence and
  the command line; prompt-diet stays within cap with a ledger entry.
- AC-007 (CHANGE-0181): a spec frozen by `spec-freeze.mjs` and edited without
  a `spec_amendment` record fails `spec-amend list --strict`, which prints the
  `spec-amend add` line that clears it; edited with a record, it passes;
  legacy frozen specs without a reconstructible freeze state degrade by name.
- AC-008: Every test of this ride has its own mutation record produced by
  `mutation-run.sh` — the gate is the first ride it gates.
- AC-009: The bucket items above are each closed with a test or rejected with
  a recorded reason via `follow-ups.mjs`; DEBT-0007 is resolved or its
  residual named.

## Verification
- `tests/skills/test-aai-mutation-gate.sh` (runner, gate, wiring, tripwire),
  plus the touched suites; CORE; one full sweep before close; validation by a
  different model re-running every mutation record.
- Ceremony 2 unless Planning finds an L3 surface in scope (`close-work-item.mjs`
  is pinned; `SKILL_PR.prompt.md` is a diet-ledgered prompt).
