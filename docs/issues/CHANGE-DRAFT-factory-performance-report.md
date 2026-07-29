---
id: factory-performance-report
number: null
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Factory Performance Report (continuous efficiency overview)

## Summary
- Add a deterministic Factory Performance Report generator
  (`.aai/scripts/generate-factory-report.mjs`) that reads the existing
  `docs/ai/METRICS.jsonl` and `docs/ai/EVENTS.jsonl` ledgers and renders a
  self-contained `docs/ai/factory-report.html` (+ `factory-report-data.json`)
  answering four questions across time: what the factory delivers (throughput),
  how fast (speed), at what token cost (cost), and at what quality.
- Auto-regenerates at close, wired best-effort into `close-work-item.mjs` the
  same way the stakeholder overview already is.
- Exposed through a thin `/aai-factory-report` skill wrapper.

## Motivation / Business Value
- Owner request (verbatim intent): "chtel bych nejaky prehled jak efektivne
  fabrika jede, co stiha jak rychle a za jakou cenu odbavovat v jake kvalite"
  — a continuous factory-efficiency overview.
- Today only on-demand point-in-time snapshots exist:
  - `/aai-dashboard` (`generate-dashboard.mjs`) renders per-operation activity
    telemetry, keyed on `tokens_in`/`tokens_out` which are null for every run
    in this repo, so its token totals are effectively empty here; it computes
    no trend, no lead time, no per-release rollup, and ignores both the
    per-ride `reliability` block and the `usage_total_tokens=` note markers.
  - `/aai-overview` (`generate-overview.mjs`) is a stakeholder "what shipped"
    view (per-item cards), not an efficiency analytics view.
  - `metrics-report.mjs` computes point-in-time per-item / per-model / per-role
    token rollups and per-strategy reliability, but as one markdown table with
    NO trend over time, NO lead time, NO per-week or per-release bucketing.
- None of the three answers "how is efficiency trending week over week and
  release over release" — which is exactly the owner ask.

## Scope
- In scope:
  - New deterministic generator over the existing ledgers (Node stdlib, zero
    network), reusing the proven building blocks of `generate-overview.mjs`
    (self-contained inline HTML render, `lib/usage-note.mjs` token grammar,
    `links.members` release grouping, `work_item_closed` close-date map).
  - Four KPI dimensions with both an overall rollup and a per-ISO-week series:
    throughput, speed, cost (tokens only), quality.
  - Best-effort auto-regen at close (additive hook in `close-work-item.mjs`).
  - Thin `/aai-factory-report` skill wrapper (mirrors the `aai-overview`
    wrapper — no new `.aai` prompt-corpus file).
  - Governance: PROFILES classification for the new script; suite-map row for
    the new test suite.
- Out of scope:
  - Any USD cost figure (the ledger carries no in/out token split to price
    honestly — tokens-only, mirroring `metrics-report.mjs` discipline).
  - LLM parsing of prose run notes for load-bearing numbers (a note-grammar
    regex like `usage_total_tokens=` is fine; free-text interpretation is not).
  - Publishing (that remains `/aai-share`'s job) and any network access.
  - Rewriting or merging `generate-dashboard.mjs` / `generate-overview.mjs`.

## Affected Area
- New: `.aai/scripts/generate-factory-report.mjs`,
  `tests/skills/test-aai-factory-report.sh`,
  `.claude/skills/aai-factory-report/SKILL.md`.
- Modified (additive): `.aai/scripts/close-work-item.mjs` (one best-effort
  regen call), `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`.
- Outputs (gitignored runtime artifacts, like overview/dashboard):
  `docs/ai/factory-report.html`, `docs/ai/factory-report-data.json`.

## Desired Behavior (To-Be)
- Running `node .aai/scripts/generate-factory-report.mjs` produces a
  self-contained HTML page and a JSON data file with throughput, speed, cost,
  and quality KPIs, each carrying an overall value and a per-week trend series,
  computed only from mechanically-derivable ledger fields.
- Numbers that are not honestly derivable stay visibly null / n/a — never
  imputed, never fabricated, never converted to USD.
- The report refreshes automatically at every successful close, and a
  generator failure never changes the close outcome.

## Acceptance Criteria
- AC-001: A deterministic generator computes the four KPI dimensions from
  `METRICS.jsonl` + `EVENTS.jsonl` using Node stdlib only, with no network.
- AC-002: Throughput — delivered counts per ISO week and per release, plus
  per-item lead time; missing endpoints yield null, never zero.
- AC-003: Speed — per-ride agent busy-seconds and a per-canonical-role split
  with role-variant normalization.
- AC-004: Cost — per-ride and per-role undecomposed token totals via the
  shared marker grammar; null where no marker; never any USD figure.
- AC-005: Quality — first-pass-clean rate, remediation distribution, and
  validation/review fail averages from the recorded `reliability` block only.
- AC-006: The HTML render matches the JSON data field-for-field (one model,
  two renderers).
- AC-007: Auto-regen at close is best-effort and never changes the close
  exit code.
- AC-008: Degraded / excluded inputs are named in output; malformed JSONL is
  skipped without corrupting aggregates; empty ledger exits 0.

## Verification
- `bash tests/skills/test-aai-factory-report.sh` (all cases green).
- `bash tests/skills/test-aai-layer-profiles.sh` and
  `bash tests/skills/test-aai-hygiene-pack.sh` (governance pins green).
- Manual: `node .aai/scripts/generate-factory-report.mjs` over the live repo
  ledgers exits 0 and emits both output files.

## Constraints / Risks
- Honesty rules are load-bearing: tokens-only, null-preserving, no USD, no
  prose-note interpretation (mirrors `metrics-report.mjs`).
- History is modest today (~104 rides over ~4 weeks, 2026-06-30..2026-07-28),
  and only 78/104 rides carry the `reliability` block and 189/411 runs carry a
  token marker — trends are directional, and coverage gaps must render as
  explicit n/a, not silent zeros.
- Secrets preflight: no secret referenced by this change.
