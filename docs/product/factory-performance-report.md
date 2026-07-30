---
id: factory-performance-report
type: product
capability: factory-performance-report
status: current
delivered_by:
  - CHANGE-0098
spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
updated: 2026-07-30
---

# Factory performance report

## What it does

Answers "how efficiently is the factory running" in one self-contained page:
**what it delivers** (throughput), **how fast** (speed), **at what cost**
(tokens), and **at what quality** — each as an overall rollup plus a
per-ISO-week trend, computed deterministically from the local ledgers
(METRICS.jsonl + EVENTS.jsonl, zero network). The page refreshes itself at
every work-item close, so it is a continuous overview, not a one-off snapshot.

## How to use it

- Open `docs/ai/factory-report.html` — it regenerates automatically whenever
  a work item closes (best-effort; a report failure never breaks a close).
- `/aai-factory-report` (or `node .aai/scripts/generate-factory-report.mjs`)
  rebuilds it on demand; `--data-only` writes just
  `docs/ai/factory-report-data.json` for machine consumers.
- Read the notes block first: it names every exclusion (rides without
  telemetry, malformed lines) so you know what the numbers do NOT cover.

## Data model

- Inputs: `docs/ai/METRICS.jsonl` (rides, agent runs, durations, the
  `usage_total_tokens=` note grammar, the reliability block) and
  `docs/ai/EVENTS.jsonl` (`work_item_closed` timestamps); release grouping via
  release-doc `links.members`.
- Outputs: `docs/ai/factory-report.html` (self-contained, inline CSS/SVG) +
  `factory-report-data.json` (field-for-field the same model).

## Interfaces and contracts

- Honesty rules are load-bearing and test-pinned: nulls are never counted as
  zeros; rides predating a telemetry field render as an explicit `n/a` bucket
  (never blended into numeric buckets); **no USD figure anywhere** (tokens
  cannot be priced without an in/out split); ride time is labelled agent
  *busy-time*, not wall-clock; "delivered" counts every `work_item_closed`
  (incl. administrative closes) and says so in a visible caveat.
- Degrade-with-NOTE: malformed ledger lines are skipped and named; an absent
  ledger yields an empty report with a marker, exit 0.
- Close-hook: `close-work-item.mjs` regenerates the report strictly last,
  swallowing failures (exit code of the close never changes).

## Limits and non-goals

- Trends are directional, not statistical — the history is weeks deep.
- No cost in USD by design; runs that expose no usage stay honest-null.
- Quality metrics come only from the flush-recorded reliability block; prose
  run notes are never parsed for load-bearing numbers.

## Links

- Request: docs/issues/CHANGE-0098-factory-performance-report.md
- Spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
