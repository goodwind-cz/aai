---
id: factory-performance-report
type: product
capability: factory-performance-report
status: current
delivered_by:
  - CHANGE-0098
  - CHANGE-0130
  - CHANGE-0142
  - ride-cost-readout
spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
updated: 2026-08-17
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
  release-doc `links.members`; `docs/ai/decisions.jsonl` for the typed
  follow-up registry (`--decisions <path>` overrides it).
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
- `--decisions <path>` selects the decision ledger the follow-ups block folds
  (default `docs/ai/decisions.jsonl`).

## Open follow-ups

- The `<section id="follow-ups">` block (`follow_ups` in
  `factory-report-data.json`) lists the OPEN typed follow-ups folded out of
  `docs/ai/decisions.jsonl`: `open_count`, `oldest_age_days`, and one item per
  open entry with id, raising ref, severity, `age_days` and the one-line
  finding. Ageing deferred work is a quality-debt signal, which is why it sits
  on this page rather than the stakeholder overview.
- Ordered by AGE, never by severity, so a mis-assigned P-level cannot hide an
  item. Report-only: nothing here gates anything.
- The fold is the SAME code the `follow-ups.mjs` CLI runs, so
  `open_count` and `node .aai/scripts/follow-ups.mjs list --json` can never
  disagree over one ledger. See docs/product/aai-decisions.md for the record
  shape and the manual close command.
- Degradations are named in the existing notes block and never fatal: an
  absent ledger, a malformed line, an id-less legacy entry folded under a
  derived id, and a dangling status record each produce a note, exit 0. An
  empty registry reports `open_count: 0` and `oldest_age_days: null` — never
  a fabricated 0.

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

## Scope cost

- The `<section id="scope-cost">` block (`scope_cost.scopes` in
  `factory-report-data.json`) answers "what did this scope cost" per ride, so
  the ledger never has to be summed by hand — one row per ride recorded in
  `docs/ai/METRICS.jsonl`, none filtered by close state. Rows exist only
  after a ride's runs are flushed to the ledger and the report regenerates at
  close — this is an after-the-fact comparison across finished rides, not a
  live view of a ride still in progress (see Limits and non-goals).
- Two distinct time figures, never confused: **Elapsed (wall clock)** is the
  span from the ride's first run start to its last run end; **Agent time (summed)**
  is the total of each run's own duration. They diverge in BOTH directions —
  agent time falls below elapsed when a ride idles between roles, and above
  it when roles run concurrently — and neither bounds the other, so the
  report never labels either a bare "duration". The count of scopes where
  agent time exceeds elapsed is computed into the data-honesty notes, never
  written as prose that could go stale. A run missing `duration_seconds`
  makes Agent time (summed) a partial sum on that scope; the count of such
  runs is likewise computed into the data-honesty notes, never silently
  dropped.
- The Roles cell lists only the roles that ran, in a fixed canonical order —
  not the order in which they ran, so it must not be read as a chronology. A
  scope with zero recorded runs renders the named line `no runs recorded`,
  never a blank cell.
- Token figures are marker-only, from the same `extractUsageTotal` grammar as
  the rest of the report, and every token cell carries its own
  `runs_marked`/`runs_total` denominator in the same cell — a partial sum is
  shown, never hidden, and never mistaken for a complete one. A scope with
  zero marked runs renders the named line `no usage marker (0/N runs)` and a
  `null` total in the JSON — never a zero.
- The remediation figure counts every `Remediation` run structurally; the
  round whose finding it addressed is not included, so this is a rework
  figure, not a failure rate. `Remediation share (of measured tokens)` is
  `null` unless both the remediation tokens and the scope's tokens_total are
  measured. On a ride with several remediation rounds this figure
  understates total rework (see Limits and non-goals).

## Limits and non-goals

- Trends are directional, not statistical — the history is weeks deep.
- No cost in USD by design; runs that expose no usage stay honest-null.
- Quality metrics come only from the flush-recorded reliability block; prose
  run notes are never parsed for load-bearing numbers.
- Role-consumption medians over one or two marked runs (especially in the
  sparse era) are arithmetic, not statistics; `runs_marked` is the
  denominator to consult (summary table or JSON) before trusting any
  per-role figure.
- Scope cost is not a live view: `agent_runs` only lands in `METRICS.jsonl`
  at metrics-flush and the report only regenerates at close, so a ride still
  in progress has no row. Use it to compare finished rides against each
  other, never to decide whether to stop one that is still running
  (follow-up: a genuinely live view is a separate, unshipped capability).
- The remediation share is a lower bound on rework: it counts only
  `Remediation`-role runs and excludes every round that produced the finding
  a remediation round addressed (the preceding Validation or Code Review
  round). On a multi-round ride, true rework — remediation plus its repeat
  Validation/Code Review rounds — can run well above the rendered share.

## Links

- Request: docs/issues/CHANGE-0098-factory-performance-report.md
- Spec: docs/specs/SPEC-0108-spec-factory-performance-report.md
- Request: docs/issues/CHANGE-0130-role-token-trend.md
- Spec: docs/specs/SPEC-0117-spec-role-token-trend.md
- Request: docs/issues/CHANGE-0142-followup-registry.md
- Spec: docs/specs/SPEC-0129-spec-followup-registry.md
- Request: docs/issues/CHANGE-0148-ride-cost-readout.md
- Spec: docs/specs/SPEC-0134-spec-ride-cost-readout.md
