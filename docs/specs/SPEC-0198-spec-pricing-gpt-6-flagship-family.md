---
id: spec-pricing-gpt-6-flagship-family
type: spec
number: 198
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0198-pricing-gpt-6-flagship-family.md
  rfc: null
  pr: []
  commits: []
---

# Spec — GPT-6 flagship pricing keys

SPEC-FROZEN: true

Ceremony justification: pricing table and one skills contract test only; no protected L3 paths.

## Implementation strategy
- Strategy: direct
- Worktree: not_needed (inline on `cursor/gpt-6-pricing-family-67e6`)

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | GPT-6 astra/sol/luna priced | done | tests/skills/test-aai-pricing.sh FAIL-010 | — | CHANGE-0198 AC-001 |
| Spec-AC-02 | gpt-6.1-sol unchanged | done | `.aai/system/PRICING.yaml` | — | CHANGE-0198 AC-002 |
| Spec-AC-03 | FAIL-012 suffix loop | done | tests/skills/test-aai-pricing.sh | — | CHANGE-0198 AC-003 |
| Spec-AC-04 | gpt-6.1-astra omission noted | done | `.aai/system/PRICING.yaml` pricing_meta | — | CHANGE-0198 AC-004 |
| Spec-AC-05 | Suite green | done | tests/skills/test-aai-pricing.sh | — | CHANGE-0198 AC-005 |

## Test Plan

| Test ID | Spec-AC | File | Description |
|---------|---------|------|-------------|
| TEST-006 | 01–05 | tests/skills/test-aai-pricing.sh | PRICING contract + GPT-6 catalog |
