---
id: telemetry
type: product
capability: telemetry
status: current
delivered_by:
  - CHANGE-0058
  - CHANGE-0070
  - CHANGE-0063
  - telemetry-fields-not-prose
spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
updated: 2026-09-13
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
- **Fields, not prose (telemetry-fields-not-prose)** — verdict, harness,
  requested/actual model and a harness-reported token total are now written
  as STRUCTURED fields on `agent_runs[]` (`append-run --verdict / --harness /
  --tokens-total / --requested-model / --actual-model`), not just narrated in
  free-text `note`. Reliability, cost and per-role model counts derive
  FIELD-FIRST at flush time: the `VERDICT: FAIL` note marker is now a
  fallback, used only when no field was recorded, and the ledger names which
  one produced each ride's numbers (`reliability.basis`:
  `field | note | mixed | none`). A run whose field and note DISAGREE always
  resolves from the field and prints one NOTE naming the disagreement. A
  Validation or Code Review run recorded without `--verdict` is REFUSED
  (exit 2, nothing written) — a missing verdict can no longer look identical
  to a passing one. The default flush gate also widened to recognise a
  per-ref verdict field or a corroborated `validation_verdict` ledger event,
  not only the single global `last_validation` block, so an earlier PASS is
  not stranded by a later, unrelated validation round.

## How to use it

- `node .aai/scripts/metrics-report.mjs` — per-item and per-role token
  rollups; any role whose runs carry more than one distinct prompt hash gets
  a "Prompt versions" section.
- `/aai-overview` (or any successful `close-work-item`) — refreshed
  `docs/ai/overview.html` with per-item tokens + release groups.
- `/aai-flush` — for an undecomposed harness total (field or note), INFO
  states what happened to the cost: a priced model gets an estimate blended
  from the total (`cost_basis total-blended`), an unpriced model stays
  unattributable by design. WARNING marks capture-missing runs — no total
  anywhere (the defect to chase).
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
- `node .aai/scripts/state.mjs append-run --role Validation --verdict
  pass|fail|none ...` — Validation and Code Review runs REQUIRE `--verdict`
  (refused, nothing written, otherwise); `--harness` defaults to the
  detected harness; `--tokens-total` records a harness-reported total when
  the runtime exposes only one number (no in/out split); `--requested-model`
  / `--actual-model` record a routing decision and what actually ran.
- `node .aai/scripts/state.mjs set-validation --ref <R> --status <pass|fail>`
  additionally stamps a per-ref `validation: {status, at}` field on that
  ref's metrics entry when one already exists — the provenance the default
  flush gate's `per-ref-field` source reads.

## Data model

- No breaking schema change. `agent_runs[].note` carries the canonical
  `usage_total_tokens=<N>` grammar (single source
  `.aai/scripts/lib/usage-note.mjs`); `agent_runs[].prompt_hash` is an
  optional 12-64 lowercase hex string in STATE.yaml and copied byte-for-byte
  into METRICS.jsonl. Absent fields render exactly as before.
- Additive fields on `agent_runs[]`: `harness` (closed enum, derived — never
  caller-supplied), `tokens_total` (numeric, undecomposed), `verdict`
  (`pass | fail | none`), `requested_model` / `actual_model`. The ledger's
  per-ride `reliability` object carries `basis`; `cost_usd`/`cost_basis` may
  read `total-blended` (with a `cost_bounds_usd` all-input/all-output range)
  when only a token total is known — derived from `PRICING.yaml`'s
  `cost_blend.input_share`, a labelled CONVENTION, never a measurement.
  `metrics.work_items[<ref>].validation` (STATE) and each ledger line's
  `verdict_basis` (`per-ref-field | global-block | event`) name which source
  admitted the ride past the flush gate.

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
- Ledger lines flushed before and after telemetry-fields-not-prose are
  COST-INCOMPARABLE without partitioning on `cost_basis`/`verdict_basis`
  first: a legacy note-marker-only line still carries `cost_usd: null`,
  while a later line may carry a blended estimate. Any report that sums or
  averages `cost_usd`/`total_cost_usd` across that boundary without
  partitioning treats priced and unpriced rides as the same unit.
- 24 pre-existing "stranded" work items (a merged validation PASS with no
  durable per-ref field, no matching global block, and no
  `validation_verdict` ledger event) remain unflushable by design — nothing
  durable says they passed; the honest exits are `--retire` or a fresh
  verdict, never a fabricated one.

## Links

- Requests: docs/issues/CHANGE-0058-token-capture-canary.md,
  docs/issues/CHANGE-0070-prompt-hash-telemetry.md,
  docs/issues/CHANGE-0063-token-economics-end-to-end.md,
  docs/issues/CHANGE-0183-telemetry-fields-not-prose.md
- Specs: docs/specs/SPEC-0085-spec-token-capture-canary.md,
  docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md,
  docs/specs/SPEC-0089-spec-token-economics-end-to-end.md,
  docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md
