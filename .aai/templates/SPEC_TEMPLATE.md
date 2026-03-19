# Implementation Spec Template

## Links
- Requirement: <PRD/Requirement document ID>
- Decision records: <ADR links if relevant>
- Technology contract: docs/TECHNOLOGY.md

## Spec status
- SPEC-FROZEN: false
- Feature class: standard | runtime-critical

## Acceptance Criteria Mapping
For each requirement AC:
- Maps to: PRD-AC-xxx
- Spec-AC-xxx: <implementation-oriented, verifiable statement>
- Verification: <command(s) + expected evidence>

## Implementation plan
- Components/modules affected
- Data flows
- Edge cases

## Implementation proof obligations
- Primary runnable entrypoint(s): <command / script / service / CLI path>
- Runtime proof required: yes/no
- Evidence targets: <log/report/manifest/screenshot/transcript paths>
- Static-only checks allowed as sole proof: no

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
- Runtime-critical scopes must include at least one integration or e2e TEST-xxx that executes the runnable entrypoint.
- Runtime-critical scopes must not rely solely on file-existence, snapshot-only, or string-match tests.

## Verification
- Commands to run (derived from Test Plan above)
- Runnable proof command(s) for primary behavior
- Evidence artifacts (logs, screenshots, outputs)
- PASS criteria: all TEST-xxx in status green

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
