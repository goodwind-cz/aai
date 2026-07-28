---
id: dev-progress-hub
type: product
capability: dev-progress-hub
status: current
delivered_by:
  - dev-progress-hub
spec: docs/specs/SPEC-0093-spec-dev-progress-hub.md
updated: 2026-07-27
---

# Dev-progress view in the overview: what the factory is doing right now

## What it does

The stakeholder overview page (`docs/ai/overview.html`) already showed what
was delivered and what was in progress, but nothing about the ride actually
running right now. It now adds an "In flight now" section: the current focus
(what it is, what type of work, what phase it is in), a strategy chip, a
worktree chip, a validation-status chip, a review-status chip, and a compact
table of the last 5 loop ticks (role, scope, duration, harness), newest
first. On a fresh clone, or whenever there is nothing actually running, the
section is simply absent — no error, no empty placeholder.

## How to use it

- `node .aai/scripts/generate-overview.mjs` — regenerates
  `docs/ai/overview.html` and `docs/ai/overview-data.json`; open the HTML
  file in a browser, or read `overview-data.json`'s `in_flight` key for the
  same data in structured form.
- The section reads two local, gitignored runtime files:
  `docs/ai/STATE.yaml` (current focus, phase, strategy, worktree decision,
  validation/review status) and `docs/ai/LOOP_TICKS.jsonl` (recent loop
  ticks). Both are per-developer local state, so the section renders only on
  a machine where a ride actually ran.

## Data model

No new persisted files. New structured field `in_flight` on the existing
`overview-data.json` model:

- `focus`: `{ ref, type, phase }` — the current work item's ref id, intake
  type, and workflow phase (phase is `null` when the ref has no matching
  entry yet in STATE's active work items list).
- `strategy`: the implementation strategy in effect (`loop`/`tdd`/`hybrid`),
  or `null`.
- `worktree`: `{ recommendation, user_decision }`.
- `validation_status`, `review_status`: the last recorded verdicts.
- `ticks`: up to 5 objects `{ tick, role, scope, duration_seconds,
  harness_version }`, newest first.

`in_flight` is the literal value `null` whenever `STATE.yaml` is absent, or
`LOOP_TICKS.jsonl` is absent or has zero parseable rows — the same condition
that omits the HTML section.

## Interfaces and contracts

- `overview-data.json` top-level key `in_flight`: an object shaped as above,
  or `null`. Additive — no existing key changed shape.
- The HTML section and the JSON block are built from one in-memory model
  field, so they can never disagree with each other.
- A malformed (JSON-parse-invalid) line in `LOOP_TICKS.jsonl` is silently
  skipped and never occupies one of the 5 rendered slots.

## Limits and non-goals

- No live auto-refresh; regenerate the page to see the latest state.
- No historical tick analytics — `metrics-report.mjs` owns aggregate/rollup
  views across time; this section only shows the last 5 ticks.
- The tick tail is project-wide (the most recent 5 ticks across all scopes),
  not filtered to the current focus's own ticks.

## Links

- Request: docs/issues/CHANGE-0067-dev-progress-hub.md
- Spec: docs/specs/SPEC-0093-spec-dev-progress-hub.md
- Validation evidence: docs/ai/tdd/ (RED/GREEN logs; local runtime artifacts)
