---
id: <slug>
type: spec
number: null
status: draft
ceremony_level: 2
links:
  requirement: PRD-XXXX
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec Template

<!-- SPEC-0015 / RFC-0007 — Parallel-safe doc identity:
  - `id` is the durable SLUG PRIMARY KEY (e.g. `parallel-safe-doc-numbering`),
    assigned at intake and NEVER changed. Every in-branch cross-reference uses it.
  - `number` is null at intake; the sequential integer is assigned at MERGE by
    `.aai/scripts/allocate-doc-number.mjs`, which renames the file to
    `SPEC-000N-<slug>.md`. The human-facing `SPEC-000N` display id is DERIVED from
    `type` + `number` by the index generator — it is NOT stored in frontmatter.
  - At intake the file is created as `docs/specs/SPEC-DRAFT-<slug>.md` (the literal
    `DRAFT` token marks an unnumbered doc). -->

<!-- RFC-0009 — Scale-adaptive ceremony:
  `ceremony_level: 0..3` is declared by Planning at spec freeze
  (.aai/PLANNING.prompt.md step 10) against the gate table in
  .aai/workflow/WORKFLOW.md "Ceremony levels". Keep the default 2 (today's
  full pipeline) unless the scope genuinely fits a lighter or heavier tier:
  - 0 (typo/docs-only, no behavior change) and 1 (small single-surface fix)
    REQUIRE a body line starting with the literal
    `Ceremony justification: ` naming why the scope is small/safe — the
    docs-audit close gate checks it (report-only by default via close_gate).
  - 3 is MANDATORY when the scope touches a protected surface — see
    `protected_paths_l3` in docs/ai/docs-audit.yaml (state engine, allocator,
    guards, workflow canon by default).
  Legacy specs without the field are implicit level 2 (never flagged); the
  dispatch fail-closes any absent/unparseable value to 2 (full ceremony). -->


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

## Constitution deviations

None.

<!-- Filled by Planning at spec freeze (.aai/PLANNING.prompt.md step 10) by
  checking each article of docs/CONSTITUTION.md against the planned scope.
  Keep the literal `None.`, or replace it with a justified list — article
  number, the deviation, why it is justified. Required for new specs going
  forward; optional for pre-existing specs (docs-audit never flags legacy
  docs for lacking this section). -->

<!-- OPTIONAL `## Deltas` section (RFC-0011, delta-spec lifecycle). Include it
  ONLY when this change alters canonical requirements; omit it entirely
  otherwise (a spec with no `## Deltas` section is completely unaffected — the
  section is optional and legacy specs stay valid). To use it, uncomment the
  heading and the block(s) below. spec-lint validates the SHAPE
  (parseDeltasSection); the deterministic delta merge applies the blocks into
  docs/canonical/ at PR ceremony — nothing is resolved against the live
  canonical layer here.

  Each level-3 block is ONE operation on ONE canonical requirement. `<DOMAIN>`
  is the uppercase-snake REQ domain token; the target canonical slug is DERIVED
  from it by snake→kebab (OAUTH2_LOGIN -> oauth2-login) — no separate target
  line. The three ops:
  - ADDED   `### ADDED REQ-<DOMAIN> — <title>` proposes a NEW requirement. NO
            `-NNN` number (the next unused NNN per domain is assigned at merge).
            Body: exactly one SHALL line; optional `- Scenario: WHEN … THEN …`.
  - MODIFIED `### MODIFIED REQ-<DOMAIN>-NNN — <title>` replaces an EXISTING
            requirement's body. Body: exactly one SHALL line; optional scenarios.
  - REMOVED `### REMOVED REQ-<DOMAIN>-NNN` retires an EXISTING id permanently.
            Empty block — no title, no SHALL, no scenarios.

## Deltas

### ADDED REQ-OAUTH2_LOGIN — Password grant retired
The system SHALL reject the OAuth2 password grant on the login endpoint.

- Scenario: WHEN a password-grant token request arrives THEN it is refused with 400.

### MODIFIED REQ-AUTH-001 — Session expiry tightened
The system SHALL expire an idle authenticated session after 15 minutes.

### REMOVED REQ-AUTH-009
-->

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
