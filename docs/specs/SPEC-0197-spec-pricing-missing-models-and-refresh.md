---
id: spec-pricing-missing-models-and-refresh
type: spec
number: 197
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0197-pricing-missing-models-and-refresh.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Refresh PRICING.yaml and add missing model families

SPEC-FROZEN: true

Ceremony justification: pricing table and one skills contract test only; no protected L3 paths.

## Links
- Requirement: docs/issues/CHANGE-0197-pricing-missing-models-and-refresh.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: direct
- Rationale: vendor pages re-read at implementation; contract enforced by existing `test-aai-pricing.sh`.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: autopilot inline on dedicated branch; single pricing surface.
- User decision: inline (autopilot default)
- Base ref: main
- Inline review scope: `.aai/system/PRICING.yaml`, `tests/skills/test-aai-pricing.sh`, `docs/issues/CHANGE-0197-pricing-missing-models-and-refresh.md`, `docs/knowledge/FACTS.md`, `docs/specs/SPEC-0197-spec-pricing-missing-models-and-refresh.md`

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Catalog families priced or named omitted in PRICING.yaml notes | done | tests/skills/test-aai-pricing.sh FAIL-010/011 | — | CHANGE-0197 AC-001 |
| Spec-AC-02 | Effort suffixes resolve to own keys | done | tests/skills/test-aai-pricing.sh FAIL-012 | — | CHANGE-0197 AC-002 |
| Spec-AC-03 | Existing numeric rates re-verified with last_verified_utc | done | `.aai/system/PRICING.yaml` | — | CHANGE-0197 AC-003/007 |
| Spec-AC-04 | deepseek-v4-flash priced from vendor page | done | `.aai/system/PRICING.yaml` | — | CHANGE-0197 AC-004 |
| Spec-AC-05 | D4 Claude pins unchanged and match table | done | tests/skills/test-aai-pricing.sh FAIL-004 | — | CHANGE-0197 AC-005 |
| Spec-AC-06 | unknown + prune rule preserved | done | tests/skills/test-aai-pricing.sh FAIL-008 | — | CHANGE-0197 AC-006 |
| Spec-AC-07 | pricing_meta + sources stamped | done | `.aai/system/PRICING.yaml` | — | CHANGE-0197 AC-007 |
| Spec-AC-08 | pricing suite exits 0 | done | tests/skills/test-aai-pricing.sh | — | CHANGE-0197 AC-008 |

## Test Plan

| Test ID  | Spec-AC | Type | File path | Description | Status |
|----------|---------|------|-----------|-------------|--------|
| TEST-006 | Spec-AC-01..08 | integration | tests/skills/test-aai-pricing.sh | PRICING lookup contract + CHANGE-0197 catalog asserts | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-pricing.sh` — exit 0

## Evidence contract
- ref_id: pricing-missing-models-and-refresh
- Strategy: direct — suite green plus scoped diff.
