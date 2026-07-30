---
id: spec-factory-performance-report
type: spec
number: 108
status: done
ceremony_level: 2
links:
  requirement: factory-performance-report
  rfc: null
  pr:
    - 201
  commits:
    - ca08b97f3c998eb0632a8148811b406b44e5c26e
---

# Implementation Spec — Factory Performance Report

## Links
- Requirement: docs/issues/CHANGE-0098-factory-performance-report.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md
- Sibling generators (reuse, do not fork): .aai/scripts/generate-overview.mjs,
  .aai/scripts/metrics-report.mjs, .aai/scripts/lib/usage-note.mjs
- Close-ceremony host: .aai/scripts/close-work-item.mjs

## Summary
A deterministic Factory Performance Report generator answering the owner ask
"how efficiently is the factory running — what does it deliver, how fast, at
what token cost, at what quality — over time". The three existing views each
answer something adjacent but none answers this: `generate-dashboard.mjs`
(generate-dashboard.mjs:104-169) flattens the ledger into per-operation records
keyed on `tokens_in`/`tokens_out` (null for every one of the 411 recorded runs
in this repo) and computes no trend, no lead time, no per-release rollup, and
never reads the per-ride `reliability` block or the `usage_total_tokens=`
markers; `generate-overview.mjs` is a stakeholder "what shipped" cards view;
`metrics-report.mjs` is a single point-in-time markdown table. This spec adds
the missing time-series efficiency layer, built by REUSING the proven pieces of
`generate-overview.mjs` (self-contained inline HTML render, the shared
`lib/usage-note.mjs` token grammar, `readReleaseMembers` release grouping at
generate-overview.mjs:185-209, and the `work_item_closed` close-date map at
generate-overview.mjs:257-262) and mirroring the honesty discipline of
`metrics-report.mjs` (tokens-only, `~`/`n/a`/null preservation, no fabricated
USD; metrics-report.mjs:55-87,196-211).

Freeze-readiness note: this spec is written frozen-ready (all Spec-AC
measurable, every Spec-AC has at least one TEST-xxx, strategy set). The
docs/ai/STATE.yaml freeze write (PLANNING step 12) is intentionally NOT
performed here because this Planning ride runs under a single-writer
constraint in an isolated worktree; Implementation Preparation performs the
STATE transition in the main repo.

Ceremony justification: not required at level 2 (this line documents that the
scope was assessed as standard full-pipeline; no protected L3 surface is
touched — see Constitution deviations).

## Frontmatter status values
- draft: spec being written / frozen-ready, implementation not yet started.

## Implementation strategy
- Strategy: hybrid
- Rationale: the KPI math, the honesty rules (tokens-only, null-preserving, no
  USD), the two cross-generator seams, and the best-effort close-regen
  negative control are new, honesty-critical, and easy to get subtly wrong —
  they earn RED-GREEN-REFACTOR proof (TDD). The inline HTML scaffolding, the
  `/aai-factory-report` wrapper, the PROFILES entry, and the suite-map row are
  low-risk mechanical wiring where a focused loop pass is sufficient.

Allowed strategy values: loop | tdd | hybrid | undecided (see template).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: a PR-bound feature spanning three or more independent
  surfaces (new generator, additive edit to the close ceremony, governance
  files, a skill wrapper, a new test suite); isolation keeps the close-ceremony
  edit from destabilizing the working tree during development. Not `required`:
  no protected L3 path is touched (close-work-item.mjs is not in
  docs/ai/docs-audit.yaml protected_paths_l3).
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/factory-performance-report (already checked out)
- Inline review scope: if inline is chosen —
  .aai/scripts/generate-factory-report.mjs, .aai/scripts/close-work-item.mjs,
  tests/skills/test-aai-factory-report.sh,
  .claude/skills/aai-factory-report/SKILL.md, .aai/system/PROFILES.yaml,
  tests/skills/suite-map.yaml

## Acceptance Criteria Mapping
- Maps to CHANGE AC-001 -> Spec-AC-01 (generator + deterministic data model)
- Maps to CHANGE AC-002 -> Spec-AC-02 (throughput + lead time + trend)
- Maps to CHANGE AC-003 -> Spec-AC-03 (speed + role split + trend)
- Maps to CHANGE AC-004 -> Spec-AC-04 (cost honesty, tokens-only)
- Maps to CHANGE AC-005 -> Spec-AC-05 (quality from reliability block)
- Maps to CHANGE AC-006 -> Spec-AC-06, Spec-AC-07 (HTML/JSON + cross-gen seams)
- Maps to CHANGE AC-007 -> Spec-AC-09 (best-effort close regen)
- Maps to CHANGE AC-008 -> Spec-AC-08, Spec-AC-10 (degrade-with-NOTE, empty)

## Constitution deviations

None.

Article check at freeze (docs/CONSTITUTION.md v1): 1 Evidence-before-claims —
every Spec-AC has an executable TEST-xxx. 2 Simplicity — reuses existing
building blocks; adds no dependency; no speculative feature. 3 Portability —
plain git-diffable .mjs/.sh/.md, Node stdlib only, tri-platform. 4 Degrade and
report — Spec-AC-08 makes degrade-with-NOTE a tested behavior. 5 Additive first
— all new files plus one additive best-effort call at the end of the close
sequence; no signature or schema change. 6 Single-writer state — the generator
never writes STATE.yaml (read-only over it). 7 Operator-only merge — Planning
opens no PR and never merges.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN generate-factory-report.mjs runs with --data-only over a fixture the system SHALL write factory-report-data.json containing throughput speed cost and quality blocks computed with Node stdlib only and no network access | done | TEST-001 green plus TEST-018 green (project label from origin remote slug, cwd-basename fallback) (tests/skills/test-aai-factory-report.sh) | — | Node stdlib only imports fs path lib/usage-note child_process for the remote slug |
| Spec-AC-02 | WHEN work_item_closed events exist the system SHALL emit delivered counts per ISO week and per release with links.members grouping and close-month fallback and a per-item lead_time_seconds equal to closed_ts minus the earliest agent_run started_utc emitting null when either endpoint is absent | done | TEST-002 and TEST-003 and TEST-017 green (re-closed ref counts once and buckets at the latest close with an honesty note) | — | lead time null-safe never zero; delivered_total distinct refs; latest close wins |
| Spec-AC-03 | The system SHALL emit per-ride agent busy-seconds as the sum of run duration_seconds and a per-canonical-role duration split that normalizes role-name variants by prefix to the six canonical roles so that Remediation parenthetical variants aggregate under Remediation and a ride with no duration data yields null not zero | done | TEST-004 green | — | busy-seconds labelled not wall-clock |
| Spec-AC-04 | The system SHALL compute per-ride and per-role undecomposed token totals only via the shared lib usage-note extractUsageTotal and SHALL emit null for any ride or role carrying no valid marker and SHALL NOT emit any USD figure anywhere in the data file or the HTML | done | TEST-005 and TEST-006 green | — | tokens-only honesty mirrors metrics-report |
| Spec-AC-05 | The system SHALL compute first-pass-clean rate and remediation-count distribution and average validation and review fails only from the flush-recorded reliability object and SHALL place rides predating that field into an explicit n/a bucket without reinterpreting them and SHALL limit review-verdict data to the ride-level verdict field and the code_review_completed event count | done | TEST-007 green (strengthened: remediation_distribution is reliability-only with an explicit n/a bucket; pre-field rides never inflate a numeric bucket) | — | no prose-note parsing for numbers; DEFECT-1 remediation |
| Spec-AC-06 | WHEN run without --data-only the system SHALL write factory-report.html as a self-contained page with inline CSS and inline SVG and no external or network references whose rendered KPI values match factory-report-data.json field for field | done | TEST-008 and TEST-011 and TEST-012 and TEST-019 green (remediation table sorts numeric ascending with n/a last deterministically) | — | one model two renderers plus two cross-gen seams |
| Spec-AC-07 | Each of the four KPI dimensions SHALL expose both an overall rollup and a per-ISO-week trend series derived from the ride date_utc so week-over-week movement is visible | done | TEST-009 green (extended: counts.active_weeks is the union of delivery and ride weeks matching the rendered trend) | — | trend directional given sparse history |
| Spec-AC-08 | WHEN an input ride or run is excluded or degraded or a JSONL line is malformed the system SHALL name the exclusion in a data-file notes array and skip the malformed line without shifting other aggregates and exit 0 | done | TEST-010 green | — | degrade-with-NOTE convention |
| Spec-AC-09 | WHEN close-work-item.mjs completes a successful close the system SHALL best-effort regenerate the factory report as the strictly-last step after docs-hub regen swallowing any generator failure to an INFO stderr line never reaching rollback and never changing the close exit code | done | TEST-013 green negative control plus test-aai-close-work-item.sh full suite green | — | additive hook drives the real close entrypoint |
| Spec-AC-10 | WHEN METRICS.jsonl is absent or comment-only the system SHALL exit 0 and write a data file with empty KPI blocks and a no-metrics marker and never throw | done | TEST-014 green | — | mirrors metrics-report empty behavior |

Status values: planned | implementing | done | deferred | blocked | rejected

## KPI derivability matrix

Each KPI, the exact ledger field it derives from, and the honest limit.

- Delivered per week / release (throughput): EVENTS.jsonl `work_item_closed`
  `ref`+`ts` bucketed by ISO week; release grouping via release doc
  `links.members` (generate-overview.mjs:185-209), close-month fallback.
  DERIVABLE.
- Lead time per item (throughput): `work_item_closed.ts` minus earliest
  `agent_runs[].started_utc` for that ref. DERIVABLE where both endpoints
  exist; NULL otherwise (some older runs may lack started_utc) — never zero.
- Ride wall time (speed): sum of `agent_runs[].duration_seconds` (equivalently
  `totals.agent_duration_seconds`). DERIVABLE, but this is agent busy-seconds,
  NOT true wall clock (gaps/parallelism are not captured) — must be labelled
  as such.
- Per-role duration split (speed): `duration_seconds` grouped by normalized
  `role`. DERIVABLE; requires prefix normalization (recorded roles include
  variants such as "Remediation (E1 over-kill)", "Code Review (re-review)").
- Remediation-cycle count per ride (speed/quality): `reliability.remediation_runs`
  where present (78/104 rides); a role-prefix count of Remediation runs is the
  fallback. DERIVABLE.
- Tokens per ride / role / feature / release (cost): sum of
  `extractUsageTotal(note)` over runs (lib/usage-note.mjs). DERIVABLE but
  PARTIAL — 189/411 runs carry a marker; NULL where none. TOKENS ONLY.
- USD cost (cost): HONESTLY NOT DERIVABLE. `tokens_in`/`tokens_out` are null
  for all 411 runs and the marker is an undecomposed total with no in/out split
  to price — no USD figure is emitted anywhere (matches metrics-report.mjs).
- First-pass validation rate (quality): `reliability.first_pass_clean` boolean
  over rides carrying it (78/104). DERIVABLE; pre-field rides -> explicit n/a.
- Remediation distribution + avg validation/review fails (quality):
  `reliability.remediation_runs` / `validation_fails` / `review_fails`.
  DERIVABLE from the reliability block only.
- Review-verdict mix (quality): the ride-level `verdict` field (PASS/null) and
  the `code_review_completed` EVENTS count (26 events). Per-review pass/fail
  detail lives only in prose run notes and is HONESTLY NOT mechanically
  derivable (no LLM parsing of notes) — the spec exposes only the ride verdict
  and the review-event count.

## Implementation plan
- Components:
  - `.aai/scripts/generate-factory-report.mjs` — new. Structure mirrors
    generate-overview.mjs: `parseArgs` (`--output`, `--data-only`, `--metrics`,
    `--events` for fixtures), a `buildModel()` that returns one model object,
    `renderHtml(model)` inline (no template file, no external assets), and a
    `main()` that always writes `docs/ai/factory-report-data.json` and, unless
    `--data-only`, `docs/ai/factory-report.html`.
  - Shared imports: `extractUsageTotal` from `./lib/usage-note.mjs` (single
    source of the token grammar — do NOT re-inline the regex).
  - Role normalization helper: map a recorded role string to one of
    {Planning, Implementation, TDD Implementation, Validation, Code Review,
    Remediation} by longest canonical-prefix match; unmatched -> "Other" and
    named in the notes array (Spec-AC-08).
  - ISO-week helper: derive `YYYY-Www` from `date_utc` deterministically (no
    locale, no `Date.getWeek` — compute from the UTC date components).
  - `close-work-item.mjs` — add `GENERATE_FACTORY_REPORT` const beside
    GENERATE_DOCS_HUB (close-work-item.mjs:92-95) and a
    `regenerateFactoryReportBestEffort()` cloned verbatim from
    `regenerateDocsHubBestEffort()` (close-work-item.mjs:546-553), invoked as
    the new strictly-last line after close-work-item.mjs:829.
  - `.claude/skills/aai-factory-report/SKILL.md` — thin wrapper mirroring
    `.claude/skills/aai-overview/SKILL.md` (no `.aai` prompt-corpus file).
  - `.aai/system/PROFILES.yaml` — add
    `.aai/scripts/generate-factory-report.mjs` to the `extended:` list
    (reporting & publishing class).
  - `tests/skills/suite-map.yaml` — add a `suites.aai-factory-report` row.
- Data flows: METRICS.jsonl + EVENTS.jsonl (+ release docs `links.members`) ->
  buildModel() -> single model -> {data.json, html}. Read-only over all
  inputs; writes only the two output files.
- Edge cases: absent/comment-only ledger (Spec-AC-10); malformed JSONL line
  (skip, note, no aggregate shift — Spec-AC-08); ride with no reliability
  block (n/a bucket); run with no token marker (null); run with no started_utc
  (null lead time); unnormalizable role (Other + note); a week with zero
  delivered items (present in the series as 0 delivered, not omitted).

## Seam analysis
Two cross-feature seams — both covered by an integration test that crosses the
boundary end to end on ONE shared fixture, not two mocked unit tests:
- SEAM 1 — token grammar shared with metrics-report.mjs. The factory report's
  per-item undecomposed token total MUST equal metrics-report.mjs's per-item
  undecomposed token column on the same METRICS fixture (both go through
  extractUsageTotal). Covered by TEST-011.
- SEAM 2 — release grouping shared with generate-overview.mjs. The factory
  report's delivered-per-release grouping MUST match generate-overview.mjs's
  `delivered_groups` release membership on the same release+EVENTS fixture
  (both use links.members + close-month fallback). Covered by TEST-012.
- SEAM 3 (internal) — the HTML render and the JSON data are produced from one
  model; TEST-008 asserts field-for-field agreement so they cannot drift.
- Residual risk (no automated cross test): the best-effort close hook depends
  on close-work-item.mjs's real run sequence; TEST-013 exercises the hook
  through the actual close entrypoint (negative control), not a mock.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---------|---------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-factory-report.sh | --data-only over a fixture writes factory-report-data.json with throughput speed cost quality blocks and exits 0 | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-factory-report.sh | delivered counts bucket by ISO week and by release membership with close-month fallback | green |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-factory-report.sh | lead_time_seconds equals closed_ts minus earliest started_utc and is null when either endpoint is absent never zero | green |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-factory-report.sh | per-role duration split normalizes a Remediation parenthetical variant under canonical Remediation and sums duration_seconds | green |
| TEST-005 | Spec-AC-04 | unit | tests/skills/test-aai-factory-report.sh | per-ride and per-role token totals sum only valid markers a malformed marker is ignored and a no-marker ride is null | green |
| TEST-006 | Spec-AC-04 | unit | tests/skills/test-aai-factory-report.sh | neither factory-report-data.json nor factory-report.html contains any dollar or USD figure on a token-only fixture | green |
| TEST-007 | Spec-AC-05 | unit | tests/skills/test-aai-factory-report.sh | first-pass-clean rate and remediation distribution derive from the reliability block and a ride without that block lands in an explicit n/a bucket | green |
| TEST-008 | Spec-AC-06 | unit | tests/skills/test-aai-factory-report.sh | rendered HTML KPI values match factory-report-data.json field for field on one run | green |
| TEST-009 | Spec-AC-07 | unit | tests/skills/test-aai-factory-report.sh | each dimension exposes a per-ISO-week series and a zero-delivery week appears in the series as zero not omitted | green |
| TEST-010 | Spec-AC-08 | unit | tests/skills/test-aai-factory-report.sh | a malformed JSONL line is skipped and named in the notes array without shifting other aggregates and the run exits 0 | green |
| TEST-011 | Spec-AC-06 | integration | tests/skills/test-aai-factory-report.sh | SEAM 1 factory-report per-item token total equals metrics-report.mjs per-item token column on the same METRICS fixture | green |
| TEST-012 | Spec-AC-06 | integration | tests/skills/test-aai-factory-report.sh | SEAM 2 factory-report delivered-per-release grouping matches generate-overview.mjs delivered_groups on the same release and EVENTS fixture | green |
| TEST-013 | Spec-AC-09 | integration | tests/skills/test-aai-factory-report.sh | invoking close-work-item.mjs with a generator that throws leaves the close exit code unchanged and emits an INFO stderr line and never rolls back | green |
| TEST-014 | Spec-AC-10 | unit | tests/skills/test-aai-factory-report.sh | an absent and a comment-only METRICS.jsonl both exit 0 and write a data file with empty blocks and a no-metrics marker | green |
| TEST-015 | Spec-AC-01 | integration | tests/skills/test-aai-layer-profiles.sh | the new generate-factory-report.mjs is classified in PROFILES.yaml so the union-equals-tree pin stays green | green |
| TEST-016 | Spec-AC-01 | integration | tests/skills/test-aai-hygiene-pack.sh | the new test suite has a suites.aai-factory-report row in suite-map.yaml so the hygiene pin stays green | green |
| TEST-017 | Spec-AC-02 | unit | tests/skills/test-aai-factory-report.sh | a ref closed more than once counts once in delivered_total buckets at the latest close and is named in an honesty note | green |
| TEST-018 | Spec-AC-01 | unit | tests/skills/test-aai-factory-report.sh | the project label derives from the origin remote owner/repo slug and falls back to the cwd basename when no remote is set | green |
| TEST-019 | Spec-AC-06 | unit | tests/skills/test-aai-factory-report.sh | the rendered remediation table sorts numeric buckets ascending with the n/a bucket last deterministically | green |

Test status values: pending -> red -> green.

RED-proof obligation: every AC-gating test above must be observed FAILING
without the change before its green counts as evidence (regardless of hybrid
lane), including TEST-013's negative control and the two governance pins.

## Verification
- Commands:
  - `bash tests/skills/test-aai-factory-report.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `bash tests/skills/test-aai-hygiene-pack.sh`
  - `node .aai/scripts/generate-factory-report.mjs` (live repo smoke; exit 0,
    both output files written)
- Evidence artifacts: test stdout logs; the generated
  docs/ai/factory-report-data.json for the live smoke.
- PASS criteria: all TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract
For each implementation, TDD, validation, and code review artifact record:
ref_id (factory-performance-report); the Spec-AC and TEST-xxx touched; the
command run or the review scope; the exit code or review verdict; the evidence
path; and the commit SHA or diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow. Plain
Markdown headings and body text; no emoji or decorative icons.
