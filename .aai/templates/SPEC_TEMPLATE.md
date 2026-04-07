# Implementation Spec Template

## Links
- Requirement: <PRD/Requirement document ID>
- Decision records: <ADR links if relevant>
- Technology contract: docs/TECHNOLOGY.md

## Spec status
- SPEC-FROZEN: false

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

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
