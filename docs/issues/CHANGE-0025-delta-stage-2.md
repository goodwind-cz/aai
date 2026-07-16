---
id: delta-stage-2
type: change
number: 25
status: done
links:
  spec: spec-delta-stage-2
  rfc: delta-spec-lifecycle
  pr:
    - 87
  commits:
    - 489e07d
---

# Change — Delta-Spec Lifecycle, Stage 2: SPEC `## Deltas` Section + Shape Validation

## Summary
- RFC-0011 (delta-spec lifecycle) was accepted with delivery in three staged
  SPECs. Stage 1 (SPEC-0034) shipped the canonical-layer Requirements contract
  (`REQ-<DOMAIN>-NNN` grammar, `parseRequirementsSection`, the six-section
  canonical shape). Stage 2 adds the producer side: a SPEC may declare an
  optional `## Deltas` section stating ADDED / MODIFIED / REMOVED requirement
  changes against named canonical domains, and spec-lint validates its SHAPE.
- Stage 2 is deliberately shape-only. It does NOT apply deltas into
  `docs/canonical/` and does NOT resolve a delta against the live canonical doc
  (both are stage 3: `delta-merge.mjs` at PR ceremony + the docs-audit
  provenance drift check). Specs without a `## Deltas` section are unaffected.

## Motivation
Prevention beats remediation (RES-0001 F5): the canonical layer only stays
current if changes that touch requirements declare their intent in a
machine-checkable, deterministic form at authoring time. Stage 1 defined what a
canonical requirement IS; stage 2 defines how a spec DECLARES a change to one,
so stage 3 can merge it mechanically with no LLM in the write path.

## Acceptance criteria
- AC-001: a SPEC may carry an optional `## Deltas` section whose ADDED /
  MODIFIED / REMOVED blocks are parsed by one shared reader
  (`parseDeltasSection` in docs-model.mjs) that stage 3 will reuse; the reader
  reuses stage 1's REQ grammar as the single source of truth.
- AC-002: spec-lint validates the `## Deltas` shape (operation keyword, id
  grammar per operation, domain derivability, one-SHALL rule for ADDED/MODIFIED,
  empty body for REMOVED, no duplicate/conflicting ops) with precise finding
  codes; a spec with NO `## Deltas` section produces no new findings.
- AC-003: SPEC_TEMPLATE and the planning prompt document the optional section
  (referencing RFC-0011 by content, never a stage token, per the review-taxonomy
  guard); existing flow intact (spec-lint/docs-audit/ceremony suites green,
  strict audit CLEAN, index idempotent, check-state OK).

## Links
- RFC: delta-spec-lifecycle (docs/rfc/RFC-0011-delta-spec-lifecycle.md)
- Spec: spec-delta-stage-2 (docs/specs/SPEC-0037-spec-delta-stage-2.md)
- Builds on: spec-delta-stage-1 (docs/specs/SPEC-0034-spec-delta-stage-1.md, D6 seam)
