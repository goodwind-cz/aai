---
id: product-capability-refinements
number: 89
type: change
status: done
user_visible: true
links:
  pr:
    - 192
  commits:
    - ee85667b36a23ad0ad84f6141797381909c3c324
---

# Change — product capability refinements: delivered_by provenance + telemetry trio consolidation

## Summary
- Two follow-ups from the CHANGE-0088 product-docs review, operator-approved
  2026-07-28 ("4"):
  1. delivered_by provenance: the 13 migrated product docs seed delivered_by
     with the capability SLUG (tautological with the filename). Reseed each
     to its real work-item CHANGE ref (e.g. token-capture-canary ->
     CHANGE-0058) so delivered_by is honest provenance, not a restated slug.
  2. Telemetry consolidation: token-capture-canary, prompt-hash-telemetry,
     and token-economics-end-to-end are three per-ride product docs that are
     ONE user capability ("usage & cost telemetry"). Merge into a single
     docs/product/telemetry.md (delivered_by = the three CHANGE refs, prose
     synthesized with zero user-facing loss), remove the three per-ride docs.
     This is the exact per-capability-not-per-ride consolidation the
     CHANGE-0088 model was built to enable (its spec reserved it as a
     "future ride, no engine change").
- Deliberately NOT doing: speculative single-doc slug renames
  (issues-skill -> issue-intake etc.) — pure churn, slug==filename is fine.

## Acceptance Criteria
- AC-001: every docs/product/*.md delivered_by carries its real CHANGE ref
  (CHANGE-NNNN), non-empty, capability still == own slug; audit clean
  (suite-verified).
- AC-002: docs/product/telemetry.md exists (one capability), delivered_by
  = the three telemetry CHANGE refs, all four required product sections
  non-placeholder; the three per-ride telemetry docs are removed; no
  user-facing content dropped (the merged doc covers capture canary +
  prompt-hash identity + cost/usage reporting).
- AC-003: no regression — TEST-012's migration integrity check updated to
  not hardcode a doc count (assert per-doc invariants over the live set,
  not a magic >= 12 floor); docs-audit --check --strict CLEAN; INDEX +
  rollup regenerated (rollup renders telemetry once, not three times).

## Verification
- bash tests/skills/test-aai-product-docs.sh; test-aai-docs-audit;
  test-aai-userguide-rollup; docs-audit --check --strict; INDEX Product
  section shows the consolidated set.

## Constraints / Risks
- Ceremony L2 (product-doc content + one test assertion; no engine code).
- Risk: prose loss in the telemetry merge — mitigated by synthesizing all
  three docs' What/Data-model/Interfaces/Limits into the merged doc and an
  adversarial review pass on content coverage.
