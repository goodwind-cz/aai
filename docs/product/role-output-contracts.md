---
id: role-output-contracts
type: product
status: current
spec: docs/specs/SPEC-0094-spec-role-output-contracts.md
updated: 2026-07-27
---

# Role output contracts (deterministic EXPECT validation)

## What it does

Every dispatched subagent must end with a structured result block. Until
now, only another model read it — a malformed or incomplete block cost an
expensive round of confusion. The factory now validates each returned
result block deterministically (no model call): required fields, status
enum, ISO-UTC timestamps, duration arithmetic (including the
negative-duration corner), and at least one evidence entry with an integer
exit code. A violating block is rejected with machine-readable reasons and
one re-prompt before anything reaches the shared state.

## How to use it

- Orchestrators: the merge protocol invokes
  `node .aai/scripts/check-role-output.mjs --file <message.md>` (or stdin)
  before merging any subagent result. Exit 0 = proceed; exit 1 = reject
  and re-prompt once with the printed violation lines.
- Violations print one per line: `ROLE-OUTPUT-VIOLATION: E-<CODE> <detail>`
  (codes: E-NO-BLOCK, E-MISSING-FIELD, E-BAD-STATUS, E-NO-EVIDENCE,
  E-BAD-TIMESTAMP, E-BAD-DURATION, E-FUTURE-STARTED).
- Extra scope-specific extension fields are tolerated by design.

## Data model

No schema change — the checker enforces the existing result-block contract
from `.aai/SUBAGENT_CONTRACT.md` (which carries a one-line EXPECT pointer;
the postconditions live in the checker header and the spec).

## Interfaces and contracts

- CLI: `check-role-output.mjs [--file <path>] [--now <ISO>]`, exit 0/1,
  zero dependencies, deterministic (double-run byte-identical).
- Fixtures: `tests/fixtures/role-outputs/` (valid + violating per role
  class) exercised by `tests/skills/test-aai-role-output.sh` in CI.

## Limits and non-goals

- Format validation only — semantic quality stays with the independent
  validation and code-review roles.
- The reject-and-re-prompt step binds the orchestrator by protocol prose,
  not by a runtime guard (recorded residual risk).

## Links

- Request: docs/issues/CHANGE-0068-role-output-contracts.md
- Spec: docs/specs/SPEC-0094-spec-role-output-contracts.md
- Validation evidence: inline verdict summarized in the PR
