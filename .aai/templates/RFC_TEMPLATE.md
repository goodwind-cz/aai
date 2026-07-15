---
id: <slug>
type: rfc
number: null
status: draft
links:
  spec: null
  pr: []
  commits: []
---

# RFC (Decision Proposal)

<!-- SPEC-0015 / RFC-0007 — Parallel-safe doc identity:
  - `id` is the durable SLUG PRIMARY KEY (e.g. `parallel-safe-doc-numbering`),
    assigned at intake and NEVER changed. Every in-branch cross-reference uses it.
  - `number` is null at intake; the sequential integer is assigned at MERGE by
    `.aai/scripts/allocate-doc-number.mjs`, which renames the file to
    `RFC-000N-<slug>.md`. The human-facing `RFC-000N` display id is DERIVED from
    `type` + `number` by the index generator — it is NOT stored in frontmatter.
  - At intake the file is created as `docs/rfc/RFC-DRAFT-<slug>.md` (the literal
    `DRAFT` token marks an unnumbered doc). -->


Frontmatter status values: draft | proposed | accepted | implementing | done | deferred | rejected | superseded
- draft: under authoring
- proposed: ready for review
- accepted: decision recorded; implementation may begin
- implementing: linked spec is in flight
- done: implementation complete and validated
- deferred: postponed; explain in body
- rejected: decision against the proposal
- superseded: replaced by another RFC (set links.rfc to replacement)

## Context
- Problem or opportunity:
- Drivers/constraints:

## Proposal
- Recommended option:
- Rationale:

## Alternatives Considered
- Option A: pros/cons
- Option B: pros/cons

## Consequences
- Technical impact:
- Operational impact:
- Migration/compatibility notes:

## Risks
- Primary risks and mitigations:

## Open Questions
- Items requiring decision or clarification:

## Approvals
- Required approvers (roles/names):

## Notes
- Use plain Markdown headings and body text. Do not add emoji or decorative
  icons unless there is a strong domain-specific reason.
