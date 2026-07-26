---
id: token-economics-end-to-end
type: product
status: current
spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
updated: 2026-07-26
---

# Token economics, visible end-to-end

## What it does

Agent runs have been recording real token totals since the token-capture
canary, but no report read them. Now the metrics report shows tokens per
work item and per role, and the stakeholder overview page shows tokens per
delivered feature with a grand total — real numbers from the shared ledger
(first live read: 35 items, 15.27M tokens). The overview also groups
delivered items by release and regenerates itself automatically whenever a
work item closes, so the page can no longer go stale.

## How to use it

- `node .aai/scripts/metrics-report.mjs` — per-item column
  "agent tokens (undecomposed)" + a "Per-Role Token Rollup" section.
- `/aai-overview` (or any successful `close-work-item` run) — refreshed
  `docs/ai/overview.html` with per-item tokens and release groups.
- To group items under a release, list their refs in the release doc
  frontmatter as `links.members`; unlisted items fall back to close-month
  groups.

## Data model

No schema change. New shared helper `.aai/scripts/lib/usage-note.mjs` is the
single source of the `usage_total_tokens=<N>` marker grammar (flush, report
and overview all import it).

## Interfaces and contracts

- Reports display TOKENS ONLY for undecomposed totals — never a fabricated
  USD figure (input/output prices differ; a split would be invented).
- The close-ceremony overview regeneration is strictly best-effort: a
  generator failure logs to stderr and never changes the close exit code.

## Limits and non-goals

- Cost in USD stays unattributable for undecomposed totals by design.
- Release-member matching is by exact ref form; a mismatched id form falls
  back to the close-month group (recorded follow-up).

## Links

- Request: docs/issues/CHANGE-0063-token-economics-end-to-end.md
- Spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
- Validation evidence: docs/ai/reports/validation-token-economics-end-to-end-20260726T223843Z.md
  (local runtime artifact; summarized in the PR)
