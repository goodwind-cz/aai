---
id: product-docs-capability-model
type: product
capability: product-docs-capability-model
status: current
delivered_by:
  - product-docs-capability-model
spec: docs/specs/SPEC-0105-spec-product-docs-capability-model.md
updated: 2026-07-28
---

# Product docs (capability-keyed doc family)

## What it does

Product docs — the user-facing "what shipped" layer — are a first-class
doc family: keyed by user capability, scanned by docs-audit, listed in
docs/INDEX.md under a Product section, and updated in place as multiple
rides extend one capability.

## How to use it

- A user_visible intake declares `capability: <slug>`. The ship/close flow
  creates docs/product/<capability>.md if absent, else appends the ride's
  ref to its `delivered_by` provenance list.
- Run `node .aai/scripts/docs-audit.mjs --check --strict --path docs/product`
  to audit the product family; product docs appear in the INDEX Product
  section automatically.

## Data model

- Frontmatter: type: product, capability: <slug>, status (current |
  superseded), delivered_by: [<ref>...], spec (optional), updated.
- DOC_FAMILIES registry (docs-model.mjs) is the single source both engines
  read to admit and place the family — no parallel product engine.

## Interfaces and contracts

- capability slug must match the doc's own filename; delivered_by must be
  non-empty; type/status must be enum-valid — enforced by
  validateProductFrontmatter in docs-audit.
- close-work-item's delivered_by upsert is byte-idempotent and rolls back
  with the rest of the close transaction on self-verify failure.

## Limits and non-goals

- Capabilities are declared on intakes, not auto-derived; the taxonomy is
  the operator's. Short-slug consolidation of the migrated docs is a future
  ride, not frozen here.

## Links

- Request: docs/issues/CHANGE-0088-product-docs-capability-model.md
- Spec: docs/specs/SPEC-0105-spec-product-docs-capability-model.md
