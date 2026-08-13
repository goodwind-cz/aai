---
id: aai-dashboard
type: product
capability: aai-dashboard
status: current
delivered_by:
  - CHANGE-0140
spec: docs/specs/SPEC-0127-spec-reporting-docs-true-up.md
updated: 2026-08-13
---

# Workflow metrics dashboard

## What it does

Turns the local metrics ledger (`docs/ai/METRICS.jsonl`) into one
self-contained interactive HTML page of per-run operational charts: token
usage over time, per-skill usage frequency and cost, TDD cycle durations,
worktree distribution, and publishing timeline. Token totals are real even
though the ledger rarely records decomposed input/output numbers — harness
usage captured as an undecomposed `usage_total_tokens=<N>` note on a run is
parsed and reported as a total (never fabricated into an input/output
split). Chart sections whose source data is absent across the whole dataset
show a named "No data recorded in this dataset" state instead of an empty
axis, so a blank chart always means "nothing recorded", never "broken page".

## How to use it

- `/aai-dashboard` (or `node .aai/scripts/generate-dashboard.mjs`) builds
  `docs/ai/dashboard.html` plus its machine-readable twin
  `docs/ai/dashboard-data.json`; open the HTML via `file://`.
- Filters: `--from YYYY-MM-DD` / `--to YYYY-MM-DD` (date range), `--skill
  <name>` (single skill/role), `--data-only` (JSON only, skip HTML),
  `--metrics <path>` / `--output <path>` (alternate files).
- To share the page, use `/aai-share docs/ai/dashboard.html`.
- For trended factory-efficiency KPIs over weeks, use `/aai-factory-report`
  instead — the dashboard is the per-run drill-down view.

## Data model

- Reads `docs/ai/METRICS.jsonl` (one JSON object per line; work-item ledger
  entries with `agent_runs[]` — the shape written today — plus legacy flat
  operation records, auto-detected per line).
- Per-run token precedence: explicit finite `tokens_in`/`tokens_out` win;
  otherwise the run note's `usage_total_tokens=<N>` marker (canonical
  grammar imported from `.aai/scripts/lib/usage-note.mjs`); otherwise the
  run contributes no tokens.
- Writes `docs/ai/dashboard-data.json`: `summary`, `tokensByTime` (per-day
  `{input, output, total}` — `total` is additive and includes undecomposed
  note-carried usage), `skillStats`, `tddStats`, `worktreeStats`,
  `publishStats`, `hasTokenSignal`, `source`, `filters`. No field was
  removed; retention follows the repository (both outputs are committed
  artifacts).

## Interfaces and contracts

- CLI: `node .aai/scripts/generate-dashboard.mjs [--metrics <path>]
  [--output <path>] [--from D] [--to D] [--skill S] [--data-only]` — exit 0
  on success, 1 on missing METRICS/template, 2 on an unknown flag (nothing
  written on 2).
- Template contract: `docs/dashboard-template.html` placeholders
  `{{METRICS_DATA}}`, `{{PANEL_TOKENS}}`, `{{PANEL_TDD}}`,
  `{{PANEL_WORKTREE}}`, `{{PANEL_PUBLISH}}` — each panel placeholder becomes
  either its `<canvas>` or `<div class="no-data" data-panel="...">` (the
  greppable no-data marker, stable).
- Data contract: `tokensByTime[day].total` and the top-level
  `hasTokenSignal` flag are additive fields; existing consumers of `input`/
  `output` are unaffected.

## Limits and non-goals

- A note marker is a single undecomposed total: the Input/Output series stay
  at their explicit recorded values (usually 0 for note-only runs); only the
  Total series reflects marker usage.
- No live/streaming view (see the live-status dashboard for "what is
  running NOW") and no publishing — sharing is `/aai-share`'s job.
- The dashboard never estimates cost in currency; token counts only.

## Links

- Request: docs/issues/CHANGE-0140-reporting-docs-true-up.md
- Spec: docs/specs/SPEC-0127-spec-reporting-docs-true-up.md
- Validation evidence: docs/ai/tdd/ (red-*-reporting-docs-true-up-*.log)
