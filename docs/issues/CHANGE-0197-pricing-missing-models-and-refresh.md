---
id: pricing-missing-models-and-refresh
type: change
number: 197
status: done
links:
  pr:
    - 410
  commits:
    - 8eafcc667858e3b95da55eb1b2983e0ff2c1ba74
---

# Refresh PRICING.yaml and add missing model families

## Summary
- Re-read every priced row in `.aai/system/PRICING.yaml` from its official source page and stamp `last_verified_utc`.
- Add an own `models` key for each current catalog family that the table either misses or would bill as an older prefix, when that page publishes a list price.
- Fill `deepseek-v4-flash` when its page publishes a list price.

## Motivation / Business Value
- `pricing_meta.last_updated_utc` is `2026-07-15` and `update_policy.cadence_days` is 30. On 2026-09-29 the table is past its own cadence, so cost figures in the metrics ledger can be wrong.
- Longest-prefix lookup bills a newer id as an older family when the new id starts with an existing key: `claude-fable-5-1` as `claude-fable-5`, `claude-opus-5-5` as `claude-opus-5`, `claude-sonnet-5-5` as `claude-sonnet-5`, `gpt-5.6-sol` and `gpt-5.6-terra` as `gpt-5`.
- Families that match no key fall through to `unknown` and contribute no cost: `gemini-3.8-flash`, `grok-4.7`, `composer-2.5`, `cursor-grok-4.6`, `muse-spark-1.3`.
- `deepseek-v4-flash` is already in the table with null rates because it appears in `docs/ai/METRICS.jsonl`.

## Scope
- In scope: `.aai/system/PRICING.yaml` (`models`, `model_aliases` only when a runtime id still misses its new key, `sources`, `pricing_meta.last_updated_utc`) and the pinned D4 rates in `tests/skills/test-aai-pricing.sh` when a re-read changes one of those four rates. A new contract assertion for each added key and for each catalog family deliberately omitted.
- Out of scope: `.aai/system/MODEL_ROUTING.yaml`, lookup rule order, deleting priced entries, a pricing API, and any rate that was not read from the vendor page during implementation.

## Affected Area
- `.aai/system/PRICING.yaml`
- `tests/skills/test-aai-pricing.sh`
- Cost estimates produced by `.aai/scripts/lib/pricing.mjs` for the affected ids

## Desired Behavior (To-Be)
- Every existing numeric rate has been re-read from its `source_ref` URL. The standard list price stays in `input_usd_per_m` and `output_usd_per_m`. Other tiers are in `notes`. `last_verified_utc` is the verification timestamp.
- Each catalog family below has its own `models` key with both rates, `source_ref`, and `last_verified_utc` when the official page publishes a list price. Effort-suffixed runtime ids of that family resolve to the new key.
- A catalog family whose page publishes no list price is not stored as a null-priced key. The prune rule deletes null-priced keys that are absent from `docs/ai/METRICS.jsonl`, and `tests/skills/test-aai-pricing.sh` fails that case (FAIL-008). The omission, the URL checked, and the reason are recorded in the file notes.
- `deepseek-v4-flash` keeps `source_ref: deepseek-pricing`. A published list price replaces the nulls and sets `last_verified_utc`. A page with no list price leaves both rates null and says so in `notes`. That key stays because it is in metrics history.
- `unknown` stays. `lookup_rules.order` stays. No priced entry is deleted.
- `pricing_meta.last_updated_utc` and every opened `sources` entry get the verification timestamp.
- The four D4 expectations in `tests/skills/test-aai-pricing.sh` (`claude-opus-4-6`, `claude-haiku-4-5`, `claude-fable-5`, `claude-sonnet-5`) equal the rates just verified.

## Acceptance Criteria
- AC-001: The catalog set is exactly `claude-fable-5-1`, `claude-opus-5-5`, `claude-sonnet-5-5`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gemini-3.8-flash`, `grok-4.7`, `composer-2.5`, `cursor-grok-4.6`, `muse-spark-1.3`. Each id is either a `models` key with finite `input_usd_per_m` and `output_usd_per_m`, a `source_ref`, and a non-null `last_verified_utc`, or named in the file notes with the URL checked and the reason no list price was published.
- AC-002: For every added key `K`, resolving `K`, `K-high`, and `K-xhigh` returns `K`.
- AC-003: Every `models` key that had numeric rates before this change still has numeric rates. Each rate was re-read from its `source_ref` page. `last_verified_utc` on that entry is the verification timestamp. A tiered price keeps the standard list price in the rate fields and the other tiers in `notes`.
- AC-004: `deepseek-v4-flash` keeps `source_ref: deepseek-pricing`. Published input and output list prices are stored and `last_verified_utc` is set. If the page publishes no list price, both rates stay null and `notes` state that the page was checked.
- AC-005: The D4 pins in `tests/skills/test-aai-pricing.sh` equal the verified rates for `claude-opus-4-6`, `claude-haiku-4-5`, `claude-fable-5`, and `claude-sonnet-5`. A rate the official page changed is updated in both files in the same change.
- AC-006: `unknown` remains with null rates. `lookup_rules.order` is unchanged. No priced entry is deleted. The only null-priced key absent from `docs/ai/METRICS.jsonl` history is `unknown`.
- AC-007: Every `claude-` key has a non-null `last_verified_utc`. `pricing_meta.last_updated_utc` is the verification timestamp. Each `sources` entry whose URL was opened has `last_verified_utc` set to that timestamp.
- AC-008: `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-pricing.sh` exits 0.

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-pricing.sh` exits 0.
- A resolver spot-check prints, for each added key `K`, that `K`, `K-high`, and `K-xhigh` resolve to `K`.
- A spot-check prints each omitted catalog family and confirms it has no `models` key.

## Constraints / Risks
- Prices are read at implementation from the official pages. This intake does not fetch them and does not invent a rate.
- Existing source URLs are `https://platform.openai.com/pricing`, `https://openai.com/index/introducing-upgrades-to-codex/`, `https://www.anthropic.com/pricing`, `https://ai.google.dev/gemini-api/docs/pricing`, and `https://api-docs.deepseek.com/quick_start/pricing`. Grok, Cursor Composer, and Muse need a vendor page found at implementation. No public list price means the family is omitted, not stored as null.
- `tests/skills/test-aai-pricing.sh` pins four Claude rates (FAIL-004) and rejects a null `last_verified_utc` on any `claude-` key (FAIL-007). A refresh that moves a pinned rate must update that assertion in the same change.
- The prune rule and FAIL-008 forbid a null-priced key that is absent from metrics history. Catalog families that are not yet in `docs/ai/METRICS.jsonl` cannot be added with null rates.
- Effort suffixes are not separate products unless the vendor page says they are billed differently. `gpt-5.6-sol` and `gpt-5.6-terra` are separate keys when both are published. If the page publishes one GPT-5.6 rate, both keys carry that rate and `notes` say so.
- No local secret is referenced.

## Notes
- Owner choice at intake: fill what is missing and update existing prices (the broader of the three sets offered).
- Assumption: the missing set is the ten families in AC-001, plus `deepseek-v4-flash`, which is already present with null rates. A scan of `docs/ai/METRICS.jsonl` on 2026-09-29 found no other unresolved `model_id` besides the `unknown` sentinel.
- Assumption: `.aai/system/MODEL_ROUTING.yaml` is unchanged in this change. New keys fix lookup. Rebinding tiers is separate work.
- Owner 2026-09-29: ChatGPT 6.1 sol (`gpt-6.1-sol`) landed on OpenAI pricing the same day; priced in `.aai/system/PRICING.yaml` and recorded in `docs/knowledge/FACTS.md`. Harness routing lists unchanged (out of scope).
- `on_unknown_model` says to add a null-priced row and then verify. FAIL-008 and the prune rule override that for ids that are not in metrics history: verify first, and add the row only when both rates are known.
