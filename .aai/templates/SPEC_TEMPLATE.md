---
id: spec-<slug>
type: spec
number: null
status: draft
links:
  requirement: PRD-XXXX
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec Template

<!-- SPEC-0015 / RFC-0007 — Parallel-safe doc identity:
  - `id` is the durable SLUG PRIMARY KEY (e.g. `spec-parallel-safe-doc-numbering`),
    assigned at intake and NEVER changed. Every in-branch cross-reference uses it.
  - `number` is null at intake; the sequential integer is assigned at MERGE by
    `.aai/scripts/allocate-doc-number.mjs`, which renames the file to
    `SPEC-000N-<slug>.md`. The human-facing `SPEC-000N` display id is DERIVED from
    `type` + `number` by the index generator — it is NOT stored in frontmatter.
  - At intake the file is created as `docs/specs/SPEC-DRAFT-<slug>.md` (the literal
    `DRAFT` token marks an unnumbered doc). -->


## Links
- Requirement: <PRD/Requirement document ID>
- Decision records: <ADR links if relevant>
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

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

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                    | Status      | Evidence       | Review-By   | Notes                          |
|------------|--------------------------------|-------------|----------------|-------------|--------------------------------|
| Spec-AC-01 | <implementation-oriented stmt> | planned     | —              | —           | —                              |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence (commit SHA or RUN_ID)
- deferred: explicitly postponed; requires Review-By in the future (minimum +14 days) + Notes naming target doc or reason
- blocked: implementation cannot proceed; requires Review-By + Notes naming blocker
- rejected: AC will not be implemented; requires Notes with rationale; no Review-By needed (terminal)

Gate behavior (enforced by .aai/VALIDATION.prompt.md when this column is present):
- Any planned/implementing AC blocks PASS
- Any done AC with empty Evidence blocks PASS
- Any deferred/blocked AC anywhere in the repo with Review-By in the past blocks any PASS until re-decided
- Review-By must be at least 14 days in the future when set

Legacy specs without the Review-By column are skipped by the gate.

## Implementation plan
- Components/modules affected
- Data flows
- Edge cases

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-xx | unit/int/e2e | <expected test file path> | <what the test verifies>     | pending |

Test status values: pending → red → green
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
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status

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
