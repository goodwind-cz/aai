---
id: project-dominant-width
type: issue
number: 8
status: draft
links:
  rfc: null
  pr: []
  commits: []
---

# Issue — Empty-Type Width Defaults Ignore the Project's Own Convention

## Summary
- ISSUE-0006 made number width inherit per-type, but the empty-type DEFAULTS
  (PRD: 3, all else: 4) encode the template repo's practice. A vendored
  project whose convention is 3-digit across ALL types gets a 4-digit number
  for the first doc of any new type. Operator follow-up to ISSUE-0006.

## Expected
- Width cascade: (1) the type's own existing docs; (2) else the DOMINANT width
  across all numbered governed docs in the project (mode; tie -> 4);
  (3) else the per-type defaults (PRD: 3, others: 4) for a greenfield repo.

## Actual
- Cascade stops at (1) -> (3); step (2) missing.

## Acceptance Criteria
- AC-001: in a fixture project where all existing docs (any types) are
  3-digit, allocating the FIRST doc of a new type yields a 3-digit number.
- AC-002: in this repo's layout (all 4-digit), a new type still yields
  4-digit (regression: dominant width = 4).
- AC-003: type-own inheritance still beats the project-dominant width
  (a 4-digit type in a mostly-3-digit project continues 4-digit).
- AC-004: greenfield (zero numbered docs anywhere): PRD -> 3, others -> 4
  (unchanged defaults).
