# Performance Profiling Skill

## Goal
Analyze real AAI workflow telemetry — token usage, cost, duration, cache
efficiency — from the data the workflow actually records, identify bottlenecks,
and produce an actionable markdown report. This skill reads existing telemetry;
it does not instrument anything and it invents no numbers.

## Real data sources (the only inputs)
| Source                              | What it holds                                                                 |
|-------------------------------------|-------------------------------------------------------------------------------|
| docs/ai/METRICS.jsonl               | Append-only ledger: one JSON line per flushed work item (agent_runs with role, model_id, started/ended UTC, duration_seconds, tokens_in/out, cost_usd; human_time_minutes; totals) |
| docs/ai/LOOP_TICKS.jsonl            | Per-tick loop telemetry (role, scope, duration_seconds, optional input/output/cache_read tokens and est_cost_usd, lingering_procs, free_memory) — may be absent between runs (flushed) |
| docs/ai/STATE.yaml                  | metrics.work_items for not-yet-flushed scopes (in-flight agent_runs)          |
| .aai/system/PRICING.yaml            | Model cost table (used to price runs whose cost_usd is null but tokens known) |

Helper scripts (both exist; use them instead of re-deriving):
- `node .aai/scripts/loop-digest.mjs [--json|--write]` — digest of the last
  autonomous run from LOOP_TICKS.jsonl (ticks, duration, scopes, cost, git).
- `node .aai/scripts/generate-dashboard.mjs [--metrics <path>] [--output <path>]
  [--from D --to D]` — HTML dashboard rendered from METRICS.jsonl.

If a source file is missing or empty, say so and analyze what exists. Never
fabricate or estimate values that were not recorded (null stays null).

## Process
1. Read the sources above (skip absent ones, note which were skipped).
2. Aggregate per work item and per role:
   - agent time: sum of non-null duration_seconds across agent_runs
   - tokens: sum tokens_in / tokens_out where recorded
   - cost: recorded cost_usd; where null and tokens are known, price with
     .aai/system/PRICING.yaml ((tokens_in * input_usd_per_m + tokens_out *
     output_usd_per_m) / 1e6) and label it "priced from PRICING.yaml"
   - human time: human_time_minutes (intake + reviews)
3. From LOOP_TICKS.jsonl (when present): ticks per run, duration per tick,
   recovery/stagnation events, cache_read share where recorded, lingering_procs
   and free_memory trends (leak signal, SPEC-0009).
4. Rank bottlenecks with the measured data only, e.g.:
   - roles/work items with the largest share of total agent seconds or cost
   - runs where cache_read is low relative to input tokens (cold-start cost —
     see SKILL_LOOP CACHING DISCIPLINE)
   - ticks with exit_code != 0, recoveries, or non-zero lingering_procs
5. Write the report to docs/ai/reports/profile-<UTC-stamp>.md with:
   - data coverage (which sources existed, line counts, date range)
   - per-work-item and per-role tables (time, tokens, cost)
   - bottleneck list, each backed by the specific lines/fields observed
   - concrete suggestions (each tied to an observed number, never generic)
6. Optionally render the visual companion:
   `node .aai/scripts/generate-dashboard.mjs` (publish via /aai-share if asked).

## Operations
- `/aai-profile` — full analysis over METRICS.jsonl (+ LOOP_TICKS.jsonl and
  STATE.yaml in-flight items when present); writes the report.
- `/aai-profile <ref-id or skill>` — same analysis filtered to one work item
  (match by ref_id in METRICS.jsonl/STATE.yaml).
- `/aai-profile --last-run` — loop-digest view only: run
  `node .aai/scripts/loop-digest.mjs --json` and summarize the last autonomous
  run (ticks, duration, scopes, cost, stop reason).

## Output format (chat summary accompanying the saved report)
```
AAI Performance Profile
Sources:   METRICS.jsonl (<n> items), LOOP_TICKS.jsonl (<n> ticks | absent), STATE.yaml (<n> in-flight)
Range:     <first UTC> .. <last UTC>
Totals:    <agent hh:mm> agent time, <tokens in/out>, $<cost or "unpriced">, <human minutes> human min
Top costs: <ref_id/role — share> (up to 3 lines)
Findings:  <k> bottlenecks (each with the measured number behind it)
Report:    docs/ai/reports/profile-<stamp>.md
```

## Strict rules
- Only measured/recorded values. If tokens or timing are null, report them as
  null/unknown — never estimate.
- Read-only over telemetry: never modify METRICS.jsonl, LOOP_TICKS.jsonl, or
  STATE.yaml. The only write is the report under docs/ai/reports/ (and the
  dashboard HTML if requested).
- Every suggestion must cite the observed data point that motivates it.

BEGIN NOW.
