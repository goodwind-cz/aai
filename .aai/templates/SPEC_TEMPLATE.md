# Implementation Spec Template

## Links
- Requirement: <PRD/Requirement document ID>
- Decision records: <ADR links if relevant>
- Technology contract: docs/TECHNOLOGY.md

## Spec status
- SPEC-FROZEN: false

## Implementation strategy
- Strategy: undecided
- Rationale: <why loop, tdd, or hybrid is appropriate>

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: <why isolation is or is not useful>
- User decision: undecided
- Base ref: <main/develop/current branch>
- Worktree branch/path: <if selected>
- Inline review scope: <explicit paths or diff range if inline is selected>

Allowed worktree recommendation values:
- not_needed: small, low-risk, clearly scoped change
- optional: useful but not important for safety
- recommended: larger, experimental, PR-bound, or parallelizable work
- required: protected workflow/state/schema, migration, or high-risk work; user may still explicitly override inline

Allowed user decision values:
- undecided: no implementation may start when recommendation is recommended or required
- worktree: create/use a git worktree before implementation
- inline: continue in the current working tree with a clean explicit review scope
- waived: user explicitly accepts the risk of ambiguous isolation or review scope

## Acceptance Criteria Mapping
For each requirement AC:
- Maps to: PRD-AC-xxx
- Spec-AC-xxx: <implementation-oriented, verifiable statement>
- Verification: <command(s) + expected evidence>

## Implementation plan
- Components/modules affected
- Data flows
- Edge cases

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-xx | unit/int/e2e | <expected test file path> | <what the test verifies>     | pending |

Status values: pending → red → green
- pending: test not yet written
- red: test written and verified failing (TDD RED phase)
- green: test passes with implementation

Notes:
- Every Spec-AC must have at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- Test file paths are suggestions; implementation may adjust with justification.

## Verification
- Commands to run (derived from Test Plan above)
- Evidence artifacts (logs, screenshots, outputs)
- PASS criteria: all TEST-xxx in status green

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
