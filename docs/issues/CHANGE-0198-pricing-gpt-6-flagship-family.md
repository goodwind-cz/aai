---
id: pricing-gpt-6-flagship-family
type: change
number: 198
status: done
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Add OpenAI GPT-6 flagship family to PRICING.yaml

Ceremony justification: pricing table and one skills contract test only; no protected L3 paths.

## Summary
- Follow-up to CHANGE-0197 / PR #410: `gpt-6.1-sol` was added; **gpt-6-astra**, **gpt-6-sol**, and **gpt-6-luna** were still absent from `.aai/system/PRICING.yaml`.
- Re-read `https://developers.openai.com/api/docs/pricing` (source_ref `openai-pricing`) and add own `models` keys with standard short-context USD/1M rates.

## Acceptance Criteria
- AC-001: `gpt-6-astra`, `gpt-6-sol`, and `gpt-6-luna` are `models` keys with finite rates, `source_ref: openai-pricing`, and non-null `last_verified_utc`.
- AC-002: `gpt-6.1-sol` rates unchanged ($2 / $10 standard short-context); re-verified timestamp updated.
- AC-003: Effort suffixes (`-high`, `-xhigh`) for each GPT-6 catalog key resolve to that key (FAIL-012).
- AC-004: `gpt-6.1-astra` has no public list price on the OpenAI pricing page (only `gpt-6-astra` and `gpt-6.1-sol`); omission documented in `pricing_meta` notes with URL — no invented row.
- AC-005: `tests/skills/test-aai-pricing.sh` catalog includes GPT-6 family keys; suite exits 0.
- AC-006: `docs/knowledge/FACTS.md` updated briefly.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | gpt-6-astra/sol/luna priced | done | `.aai/system/PRICING.yaml` | — | AC-001 |
| Spec-AC-02 | gpt-6.1-sol unchanged | done | `.aai/system/PRICING.yaml` | — | AC-002 |
| Spec-AC-03 | Effort suffixes resolve | done | tests/skills/test-aai-pricing.sh FAIL-012 | — | AC-003 |
| Spec-AC-04 | gpt-6.1-astra omission noted | done | `.aai/system/PRICING.yaml` pricing_meta | — | AC-004 |
| Spec-AC-05 | Catalog regression pins | done | tests/skills/test-aai-pricing.sh FAIL-010 | — | AC-005 |
| Spec-AC-06 | FACTS updated | done | docs/knowledge/FACTS.md | — | AC-006 |

## Verification
- `bash tests/skills/test-aai-pricing.sh` exit 0
- `node .aai/scripts/generate-docs-index.mjs` and docs-audit close ceremony before push
