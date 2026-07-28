---
id: product-docs-capability-model
number: 88
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — product docs become a capability-keyed, generated/validated projection (fixes #189)

## Summary
- Operator decision 2026-07-28: rebuild the product-doc layer. Today
  docs/product/<ref>.md is ONE hand-authored file PER WORK-ITEM (keyed by
  internal ride, e.g. dashboard-refit.md, doctor-determinize.md), it is
  invisible to the doc engines (generate-docs-index SCAN_DIRS omits
  docs/product; docs-audit's scanAuditDocs only admits ID-prefixed/draft/
  canonical basenames, so slug-named product docs are silently skipped),
  and its frontmatter type:product / status:current is not in
  DOC_TYPE_ENUM / DOC_STATUS_ENUM (GitHub issue #189 — real gap, though the
  issue mis-describes it as active rejection; reality is silent omission,
  a no-silent-truncation violation).
- New model: product docs are keyed by USER-FACING CAPABILITY, not by
  ride, and the layer is a generated/validated projection — always in the
  index, audited by construction, updated-in-place when multiple rides
  target one capability, never a per-ride orphan.
- ARCHITECTURE DECISION (operator 2026-07-28): product is NOT a new
  standalone engine and is NOT folded into docs/canonical. It is a SECOND
  DOC FAMILY built on the SAME shared library primitives docs-canon and
  the doc engines already use — the slug scan-admit branch (generalize the
  existing `inCanonical` special-case at docs-audit-core.mjs into a
  doc-family concept that also admits docs/product), the INDEX-section
  machinery, and drift detection. One mechanism, two configured families
  (canonical = requirements axis; product = user-value axis). The axes
  stay SEPARATE so the model works on any target project where
  requirement-domain != user-capability (canon domains cluster internal
  SHALL statements; product capabilities cluster user value — they
  coincide for AAI-the-project but not in general).

## Design
- Capability declaration: a user_visible intake carries `capability:
  <kebab-slug>` naming the user-facing capability it delivers/extends
  (e.g. ci-impact-selection, pr-ceremony, issue-intake, skills-catalog,
  doctor, dashboard, state-bootstrap). Multiple work items may share one
  capability slug — they UPDATE that capability's product doc, never spawn
  a new file.
- Storage: one doc per capability at docs/product/<capability>.md.
  Frontmatter: type: product, capability: <slug>, status (from a small
  valid product enum — see below), delivered_by: [<ref>...] (generated
  provenance), spec (optional), updated. Prose body (What it does / Data
  model / Interfaces and contracts / Limits) is authored by the ship flow
  and PRESERVED across regens; the generator maintains delivered_by + the
  index membership, never overwrites authored prose (marker-delimited or
  frontmatter-only regen, byte-idempotent — mirror userguide-rollup).
- Engine integration (the #189 fix) via SHARED primitives, not a parallel
  path: generalize the `inCanonical` slug-admit special-case into a
  reusable doc-family scan-admit predicate that BOTH canonical and product
  families configure (so docs/product/<capability>.md is admitted the same
  proven way canonical <domain>.md already is); add `product` to
  DOC_TYPE_ENUM; pick the product status enum (current|superseded as a
  small new enum vs reuse done|superseded — planner decides, must pass
  BOTH generate-docs-index and docs-audit); route docs/product through the
  SAME generate-docs-index scan+section machinery canonical uses (add its
  INDEX "Product" section, satisfy the enum->section invariant). No
  duplicated scan/index/drift code — the product family is configuration
  over the shared lib.
- Ship/close wiring: SKILL_SHIP / close-work-item product-doc gate keys on
  `capability` (create docs/product/<capability>.md if absent, else update
  it + append this ref to delivered_by); the gate's exit-3 refusal path is
  preserved. USER_GUIDE rollup re-keys from per-ref to per-capability.
- Migration: the 11 existing per-ride product docs are mapped to
  capabilities — genuine capabilities keep their doc (renamed to the
  capability slug); refactor-shaped ones MERGE into the capability they
  extended (dashboard-refit -> dashboard; doctor-determinize -> doctor;
  follow-ups-* -> their target capability or dropped if internal-only).
  No user-facing content is lost; the mapping is recorded in the spec.

## Acceptance Criteria
- AC-001: a capability-keyed product doc (type:product, valid status,
  capability slug, delivered_by list) passes docs-audit clean AND appears
  in docs/INDEX.md under a Product section (suite-verified; the exact #189
  repro — create from template, audit, index — now succeeds).
- AC-002: two work items sharing a capability slug produce/também update
  ONE docs/product/<capability>.md (delivered_by carries both refs);
  authored prose survives regen byte-idempotently (suite-verified).
- AC-003: the 11 existing product docs are migrated to capabilities with
  zero user-facing content loss; USER_GUIDE rollup renders per-capability;
  no orphan/schema violation repo-wide (docs-audit --check --strict CLEAN).
- AC-004: PRODUCT_TEMPLATE + SKILL_SHIP/close-work-item gate + the
  product-doc enum/scan changes are internally consistent — a fresh
  user_visible ride creates a clean, indexed, audited capability doc out
  of the box (end-to-end, the inverse of #189).

## Verification
- new tests/skills/test-aai-product-docs.sh; test-aai-docs-audit,
  test-aai-layer-profiles, test-aai-userguide-rollup, test-aai-close-work-item
  regressions; docs-audit --check --strict; live #189 repro now clean.

## Constraints / Risks
- Ceremony L2 (docs-model.mjs, generate-docs-index.mjs, docs-audit-core.mjs,
  close-work-item.mjs are NOT protected_paths_l3 — verified). Enum +
  INDEX-section + scan-branch changes touch shared doc-engine surfaces
  used by many suites: full-framework CI run expected; adversarial
  validation on the migration (no content loss) and the enum->section
  invariant.
- Risk: capability taxonomy churn — mitigated by declaring it on the
  intake (single source) and validating slug shape; the planner freezes
  the initial capability set from the 11-doc migration.

## Notes
- Motivated by GitHub issue #189 (triaged via /aai-issues 2026-07-28).
  Per the issues-skill write-back contract, #189 is commented + closed
  ONLY after this ride's PR merges.
