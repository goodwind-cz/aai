---
id: rollup-exclusion-visibility
number: 75
type: change
status: done
user_visible: false
links:
  pr:
    - 181
  commits:
    - 3d2945b923fe2e625307120e3fa09e0c8a406a10
---

# Change — userguide rollup names every excluded product doc and the missing section

## Summary
- Universality-proof F2: `generate-userguide-rollup.mjs` silently excludes
  a product doc failing the placeholder predicate — the operator sees
  "0 delivered feature(s)" with no reason (violates the factory's
  no-silent-truncation principle). Emit one NOTE line per excluded doc:
  `userguide-rollup: EXCLUDED docs/product/<slug>.md missing=<sections>`.

## Acceptance Criteria
- AC-001: a fixture product doc with a placeholder "Data model" section
  yields an EXCLUDED line naming the doc and section; rendered output
  unchanged (suite-verified RED/GREEN).
- AC-002: fully-valid docs produce no EXCLUDED lines; byte-idempotent
  rollup output preserved.

## Verification
- tests/skills/test-aai-userguide-rollup.sh (extended)

## Constraints / Risks
- Ceremony L1; stdout-only change, marker-delimited output untouched.

## Notes
- Found by the universality proof (target project rendered "None yet."
  after a half-written product doc with zero explanation).
