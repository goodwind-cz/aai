---
id: telemetry
type: product
capability: telemetry
status: current
delivered_by:
  - CHANGE-0058
  - CHANGE-0070
  - CHANGE-0063
spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
updated: 2026-07-28
---

# Usage & cost telemetry

## What it does

The factory records what each run cost and under which instructions it ran,
surfaces those numbers in reports and the stakeholder overview, and makes
every capture gap loud instead of silent. Three delivered pieces make up
one capability:

- **Loud capture (CHANGE-0058)** — a run that observed real token usage but
  never recorded it no longer looks identical to one where the runtime
  exposed nothing; the flush classifies each run and the tick logger warns
  on a bogus start time or missing harness version.
- **Instruction identity (CHANGE-0070)** — every run can carry a
  content-addressed sha256 of the effective instruction stack (role prompt +
  SUBAGENT_CONTRACT + LEARNED), so "which prompt version produced this run"
  is a query, not a guess.
- **Visible economics (CHANGE-0063)** — the metrics report shows tokens per
  work item and per role, and the overview shows tokens per delivered
  feature with a grand total, grouped by release and auto-regenerated at
  close so the page cannot go stale.

## How to use it

- `node .aai/scripts/metrics-report.mjs` — per-item and per-role token
  rollups; any role whose runs carry more than one distinct prompt hash gets
  a "Prompt versions" section.
- `/aai-overview` (or any successful `close-work-item`) — refreshed
  `docs/ai/overview.html` with per-item tokens + release groups.
- `/aai-flush` — INFO marks runs unattributable by design (undecomposed
  harness total), WARNING marks capture-missing runs (the defect to chase).
- `node .aai/scripts/state.mjs append-run --prompt-hash <12-64 hex>` records
  a run's instruction version (omit it and behaviour is unchanged);
  `log-tick` warns on duration-0 or missing `--harness`.
- `node .aai/scripts/orchestration-dispatch.mjs --human` prints an advisory
  `Prompt hash: <12-hex>` line for the about-to-run role.
- When merging a subagent result, recording
  `--note "usage_total_tokens=<N> (harness total; in/out not exposed)"` is
  mandatory whenever the harness reported a total (else the run counts as
  capture-missing, not undecomposed-note).
- To group overview items under a release, list their refs in the release
  doc frontmatter as `links.members` (exact ref form); unlisted items fall
  back to close-month groups.

## Data model

- No breaking schema change. `agent_runs[].note` carries the canonical
  `usage_total_tokens=<N>` grammar (single source
  `.aai/scripts/lib/usage-note.mjs`); `agent_runs[].prompt_hash` is an
  optional 12-64 lowercase hex string in STATE.yaml and copied byte-for-byte
  into METRICS.jsonl. Absent fields render exactly as before.

## Interfaces and contracts

- `metrics-flush.mjs` — three-way per-run classification
  (decomposed | undecomposed-note | capture-missing) as INFO/WARNING; flush
  exit code unchanged (warn, never block). Carries `prompt_hash` through
  additively.
- `state.mjs log-tick` / `append-run --prompt-hash` — stderr WARNING on
  duration-0 / missing harness; `--prompt-hash` validated (bad value exits 2,
  writes nothing).
- `metrics-report.mjs` / overview — TOKENS ONLY for undecomposed totals,
  never a fabricated USD figure; overview regeneration at close is
  best-effort (a generator failure never changes the close exit code).
- `orchestration-dispatch.mjs` — `prompt_hash` (full 64-char hex) on the
  dispatch-verdict stdout JSON; absent on `no_action` / `needs_llm` verdicts.
- `.aai/scripts/lib/prompt-hash.mjs` — `computeEffectivePromptHash` /
  `componentHashes`; Node stdlib only, missing input = `ABSENT`, never
  throws.

## Limits and non-goals

- Cost in USD stays unattributable for undecomposed totals by design; no
  token estimation or in/out splitting — runtimes that expose nothing stay
  honest-null.
- Observability only: nothing enforces a prompt-hash match, and there is no
  backfill for runs recorded before the feature landed.
- Release-member matching is by exact ref form; a mismatched id form falls
  back to the close-month group.

## Links

- Requests: docs/issues/CHANGE-0058-token-capture-canary.md,
  docs/issues/CHANGE-0070-prompt-hash-telemetry.md,
  docs/issues/CHANGE-0063-token-economics-end-to-end.md
- Specs: docs/specs/SPEC-0085-spec-token-capture-canary.md,
  docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md,
  docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
