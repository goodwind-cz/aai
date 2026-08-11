---
id: factory-performance-report
type: product
capability: factory-performance-report
status: current
delivered_by:
  - CHANGE-0098
  - CHANGE-0130
spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
updated: 2026-08-11
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

## Role consumption

- The `<section id="role-consumption">` block (`cost.role_consumption` in
  `factory-report-data.json`) answers WHERE tokens go per role, not just the
  lifetime total `cost.by_role` already carried: a per-role table (run count,
  token total, median tokens/run, share of the marked-token grand total) plus
  a per-ISO-week trend of per-role median tokens/run, so context growth reads
  as a curve instead of a single number.
- Every agent run lands in exactly one of three buckets, and they partition
  each role's run count: `runs_marked` (a valid `usage_total_tokens=<N>` note
  marker), `runs_sentinel` (no marker, but the honest `usage_capture=none`
  gap marker), and `runs_unmarked` (neither). A run carrying both a marker
  and the sentinel counts as `runs_marked` — a run with a real total is a
  measured run.
- Marker-only, never imputed: `tokens_total`, `median_tokens_per_run` and
  `share_pct` derive ONLY from marker-carrying (`runs_marked`) runs. A role or
  a week with no marked run renders the literal `n/a` in the HTML and `null`
  (never `0`) in the JSON — a reader must never mistake "not measured" for
  "measured as cheap".
- Sparse-era caveat: usage-marker coverage across the ledger is complete only
  since **2026-08-02**, when the close-time `usage_capture_gate` went to
  `enforce`. Earlier weeks carry a real but thin `runs_marked` denominator —
  carried in the JSON next to every median and total, and rendered in the
  per-role summary table; the weekly trend cells and sparklines do not
  repeat it, so for a thin week check `runs_marked` in the summary table or
  the JSON before reading a curve as growth.

## Limits and non-goals

- Trends are directional, not statistical — the history is weeks deep.
- No cost in USD by design; runs that expose no usage stay honest-null.
- Quality metrics come only from the flush-recorded reliability block; prose
  run notes are never parsed for load-bearing numbers.
- Role-consumption medians over one or two marked runs (especially in the
  sparse era) are arithmetic, not statistics; `runs_marked` is the
  denominator to consult (summary table or JSON) before trusting any
  per-role figure.

## Links

- Request: docs/issues/CHANGE-0098-factory-performance-report.md
- Spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
- Request: docs/issues/CHANGE-0130-role-token-trend.md
- Spec: docs/specs/SPEC-DRAFT-spec-role-token-trend.md
