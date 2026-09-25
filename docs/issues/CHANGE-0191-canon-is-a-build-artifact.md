---
id: canon-is-a-build-artifact
type: change
number: 191
status: done
capability: canon-is-a-build-artifact
links:
  pr:
    - 395
  commits:
    - 3ec7d6e0aa293b8f10a41e6ffdacda23cdedce17
---

# The rules that bind agents are assembled and asserted, not pasted

## Summary
- Wave 3, sweep 7 (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`).
  Paired maintenance half: `mutation-gate-for-tests`.
- DEBT-0005: the rules that bind agents are prose whose delivery, uniqueness
  and counts nothing asserts. The dispatch payload is assembled by an
  orchestrator reading a 40-line ORCHESTRATION prompt, a contract, a
  protocol and a role prompt, and the only guard on what a role actually
  receives is a byte budget. The same month: the contract's prefix order
  lives only as prose (`fu-contract-prefix-order-unenforced`), the
  allowlist count is a log string (`fu-allowlist-count-is-prose-not-asserted`),
  a rule against backgrounding sweeps lived only in dispatch text, the
  amendment record convention was followed by nobody until a gate was
  written (CHANGE-0181), and a withdrawn claim is corrected by a
  hand-written sweep that misses whatever it did not think of (DEBT-0007).
- The mutation discipline that found five false controls this month is
  still a section the Planner remembers to write. `mutation-gate-for-tests`
  makes `spec-lint` require a Mutation checks section at ceremony 2 and
  above and makes the TDD role record one mutation run per test.
- CHANGE-0167 (an operator who validated the change themselves can reach a
  PR without lying) is the same subsystem: the waiver grammar the ceremony
  accepts is canon, and it must be assembled, not remembered.

## Motivation / Business Value
- A rule that binds by construction cannot drift, be pasted twice, or be
  forgotten by a new model. The owner asked that the framework run on
  Claude, Codex and Gemini alike; canon that is a build artifact is the same
  on all three.

## Scope
- In scope: a `build-dispatch.mjs` (or equivalent) that assembles the
  dispatch prefix from the canonical files in a declared order, asserts the
  declared counts and uniqueness, and is what the orchestrator hands a role;
  `spec-lint` mutation-section gate; TDD role records one mutation per
  test in the evidence contract; a withdrawn-claim sweep driven by a
  declared claim list, not by grep memory (DEBT-0007); CHANGE-0167 waiver
  grammar as canon with a guard; `fu-contract-*`, `fu-allowlist-count-*`,
  `fu-empty-path-cd-stays-in-shipping-repo`, `fu-spec-d6-enumeration-stale`,
  `review-round-cap-in-validation-canon` text (standing decision (a)).
- Out of scope: rewriting the role prompts' substance.

## Affected Area
- `.aai/ORCHESTRATION.prompt.md`, `.aai/SUBAGENT_CONTRACT.md`,
  `.aai/SUBAGENT_PROTOCOL.md`, `.aai/VALIDATION.prompt.md`, `.aai/TDD.prompt.md`,
  `.aai/scripts/spec-lint.mjs`, a new `.aai/scripts/build-dispatch.mjs`,
  `tests/skills/lib/prompt-diet-ledger.sh`, the suites for each.

## Desired Behavior (To-Be)
- The dispatch prefix a role receives is produced by one script whose
  output a test asserts: order, uniqueness, counts, byte size.
- A ceremony-2 spec without a Mutation checks section does not lint.
- A TDD role's evidence directory carries one recorded mutation per test.

## Notes
- Ceremony 2, TDD; sibling worktree (it edits the dispatch canon).
