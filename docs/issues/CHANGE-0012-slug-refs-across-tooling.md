---
id: slug-refs-across-tooling
type: change
number: 12
status: done
links:
  research: RES-0001
  pr:
    - 51
  commits:
    - 58757fd
---

# Change — Accept Slug Refs Across the Tooling Family (state.mjs, docs-audit --gate)

## Summary
- SPEC-0015 made docs slug-first until merge (`id: <slug>`, `number: null`),
  but the tooling family still requires the `TYPE-000N` id shape. Widen ref
  handling so DRAFT-era docs are first-class citizens.

## Motivation / Business Value
- RES-0001 finding F6: DRAFT-era docs cannot be focused, phased, or metered in
  STATE (`state.mjs` `REF_RE = /^[A-Z]+-\d+$/`, state.mjs:102), and
  `docs-audit.mjs --gate <slug>` returns "no scanned doc resolves to id" for a
  slug the same tool's `--check` accepts. Every new intake now starts as a
  slug-only DRAFT, so this breaks the primary flow, not an edge case.

## Scope
- In scope: `state.mjs` ref validation (set-focus, set-phase, append-run, and
  any REF_RE consumer); `docs-audit.mjs --gate` id resolution; a sweep for any
  other consumer of the `TYPE-000N` shape (check-state.mjs, loop-digest.mjs,
  orchestration prompts referencing ref_id shape).
- Out of scope: changing the SPEC-0015 identity contract itself; renumbering.

## Affected Area
- .aai/scripts/state.mjs, .aai/scripts/docs-audit.mjs (and lib/), check-state.mjs.

## Desired Behavior (To-Be)
- A kebab-case slug (regex e.g. `^[a-z0-9][a-z0-9-]{2,47}$`) is accepted
  anywhere a `TYPE-000N` ref is accepted; both shapes resolve to the same doc
  (slug matches frontmatter `id`, TYPE-000N matches the derived display id).
- After merge-time allocation, existing STATE entries keyed by slug remain
  valid (slug is the durable PK; no forced rewrite).

## Acceptance Criteria
- AC-001: `state.mjs set-focus --ref <slug>` and `set-phase --ref <slug>`
  succeed for a DRAFT doc and pass check-state.mjs invariants.
- AC-002: `docs-audit.mjs --gate <slug>` resolves the doc and evaluates the
  gate for it (same verdict as gating the numbered form after allocation).
- AC-003: invalid shapes (uppercase-mixed, spaces, >48 chars) are still
  rejected with exit 2 and a usage message.
- AC-004: existing `TYPE-000N` refs keep working unchanged (regression suite
  green).

## Verification
- New test stanzas in tests/skills (state suite + doc-numbering suite): slug
  focus/phase/gate paths, invalid-shape rejection, TYPE-000N regression.

## Constraints / Risks
- Ambiguity risk if a slug collides with a display id — resolve by exact
  frontmatter-id match first, display-id second; document the order.

## Notes
- Source: RES-0001 recommendation P1.1 (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md).
