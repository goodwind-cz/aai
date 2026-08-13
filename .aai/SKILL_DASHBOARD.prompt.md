# Metrics Dashboard Skill

## Goal
Turn `docs/ai/METRICS.jsonl` into an interactive HTML dashboard by running the
real deterministic engine, `.aai/scripts/generate-dashboard.mjs` (377+ lines).
Do NOT re-implement parsing, aggregation, or HTML generation by hand and do
NOT narrate intermediate steps — run the script and relay its output.

## Usage
```bash
node .aai/scripts/generate-dashboard.mjs
# defaults: metrics docs/ai/METRICS.jsonl, output docs/ai/dashboard.html
# (also writes docs/ai/dashboard-data.json next to the output)

node .aai/scripts/generate-dashboard.mjs --metrics <path> --output <path>
node .aai/scripts/generate-dashboard.mjs --from 2026-03-01 --to 2026-03-07
node .aai/scripts/generate-dashboard.mjs --skill aai-tdd
node .aai/scripts/generate-dashboard.mjs --data-only   # skip HTML, JSON only
```
Positional args are also accepted (`<metrics-path> <output-path>`), but prefer
the named flags — they cannot be silently mis-routed by argument order. An
unrecognized flag exits 2 with a usage line; never proceeds on a typo'd flag.

## Instructions
1. From the project root, run the script with whatever flags the user asked
   for (date range, skill filter, alternate paths, data-only).
2. If `docs/ai/METRICS.jsonl` (or the `--metrics` path) does not exist, the
   script exits 1 with `METRICS file not found: <path>` — relay that verbatim
   and stop; do not fabricate a dashboard.
3. If `docs/dashboard-template.html` is missing, the script exits 1 naming it
   — this is a vendored-layer file; point the user at `/aai-update`.
4. Relay the script's own summary lines verbatim (schema detected, work items
   parsed, operations aggregated, total tokens, success rate, period, output
   file paths). Do not recompute or restate these numbers by hand.
5. Name the output paths at the end: `docs/ai/dashboard.html` (open with
   `file://`) and `docs/ai/dashboard-data.json`.
6. To share the dashboard, point the user at `/aai-share docs/ai/dashboard.html`
   — this skill does not publish; sharing is `/aai-share`'s job.

## Input schema — both shapes are parsed
`docs/ai/METRICS.jsonl` is one JSON object per line. The script auto-detects
which shape each line is (`normalizeLedgerEntry` vs `normalizeOperationRecord`
in `generate-dashboard.mjs`) — a file may mix both.

1. **Work-item ledger (primary, real shape written today)** — one entry per
   work item, with a nested `agent_runs: [{ role, started_utc, ended_utc,
   duration_seconds, tokens_in, tokens_out, model_id, worktree }]` array and a
   top-level `verdict` (PASS/FAIL/CANCELLED). Each `agent_runs[]` element
   becomes one dashboard "operation"; `verdict` maps to that operation's
   status.
2. **Legacy flat entries (still parsed, no longer written)** — one operation
   per line: `{ timestamp, skill, operation, tokens: {input, output},
   duration_ms, status, metadata: {worktree, ...} }`.

**Note-carried usage is parsed.** Real `agent_runs[]` entries almost always
carry `tokens_in: null, tokens_out: null` — harness usage is captured as an
undecomposed `usage_total_tokens=<N>` note on the run (see
`.aai/SUBAGENT_PROTOCOL.md` "Harness-reported usage capture"). The script
parses that marker via the shared grammar in `.aai/scripts/lib/usage-note.mjs`
(imported, never forked). Precedence per run: explicit finite tokens_in/out
win; otherwise the note marker's total; otherwise no contribution. A marker is
only ever a TOTAL — it is reported as the `total` series/field and never split
into fabricated in/out numbers. Chart sections whose source data is absent
across the whole dataset (tdd/worktree/publish on typical ledgers, or tokens
when no run carries any token signal) render a named
"No data recorded in this dataset" state instead of an empty axis.

## Output
- `docs/ai/dashboard.html` — interactive HTML (skipped with `--data-only`)
- `docs/ai/dashboard-data.json` — processed data: summary, tokensByTime,
  skillStats, tddStats, worktreeStats, publishStats, source, filters

## Troubleshooting
| Problem | Fix |
|---------|-----|
| `METRICS file not found` | No metrics recorded yet; run some AAI workflows first |
| `Template not found` | `docs/dashboard-template.html` missing; run `/aai-update` |
| `unknown flag: --x` | Check the Usage block above; the script exits 2, nothing is written |
| Dashboard exists but is empty | All lines fell outside `--from`/`--to`/`--skill` filters |
| Token total is 0 | No run in range carries tokens_in/out or a valid `usage_total_tokens=<N>` note marker — see "Note-carried usage is parsed" above |
| A panel says "No data recorded in this dataset" | Expected — that section's source data is absent across the dataset, the named no-data state replaces the chart |

BEGIN NOW.
