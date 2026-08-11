---
id: spec-role-token-trend
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0130-role-token-trend.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Factory report: per-role token consumption and weekly trend

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0130-role-token-trend.md
- Prior spec (the generator this change extends): docs/specs/SPEC-0108-spec-factory-performance-report.md
- Prior spec (the marker/sentinel grammar and the canonical role list): docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
- Product doc updated by this scope: docs/product/factory-performance-report.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — one existing `.aai` script gains an additive,
read-only aggregation over data it already parses, plus rows in the one test
suite that already covers it, plus its product doc. No `protected_paths_l3`
surface is touched (state engine, allocator, pre-commit guards,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` — none appear in the file
list), no new script, no new runtime dependency, no network. The generator is
invoked best-effort at close and its failure never changes a close exit code
(SPEC-0108 Spec-AC-09, pinned by the existing TEST-013), so the blast radius of
a defect is a wrong number on a report page, not a broken workflow. Level 1
still demands a suite re-run plus a targeted probe and a full dual-verdict code
review; the Test Plan below IS the declared validation scope and every row
names a directly executable command.

## Summary

`generate-factory-report.mjs` already answers "what does the factory deliver,
how fast, at what token cost, at what quality" and already reads every input
this change needs: `agent_runs[].role`, `agent_runs[].note` (the
`usage_total_tokens=<N>` marker and the `usage_capture=none` sentinel from
`lib/usage-note.mjs`), and the ride `date_utc` it buckets into ISO weeks. What
it does NOT answer is WHERE the tokens go: `cost.by_role` is a single
undecomposed lifetime total per role, with no run count, no per-run central
tendency, no share, and no time axis. That is the unmeasured layer the owner's
5-layer-map audit named (context, L2) — per-role context growth is invisible
because a lifetime total conflates "this role got more expensive" with "this
role ran more often".

This scope adds ONE additive block, `cost.role_consumption`, to the model, and
ONE new HTML section rendered from it. Nothing existing is recomputed, no
input is newly parsed, and the honesty rules that make the report trustworthy
are inherited verbatim: tokens only, null is never a zero, nothing imputed, no
USD, no LLM parsing of prose notes.

The honesty problem this scope must not get wrong is the SPARSE ERA. Over the
live ledger today (139 lines, 107 rides, 437 agent runs) only 215 runs carry a
marker; 222 carry neither marker nor sentinel. Coverage is 100% only since
2026-08-02, when the close-time `usage_capture_gate` went to `enforce`. A
per-role median computed over "the runs we happen to have" and rendered next to
a run count computed over "all runs" would silently present a half-measured
history as a measured one. So every per-role figure states its own denominator
explicitly, and the three run buckets — marked, sentinel, unmarked — are
first-class output, not a footnote.

## Design decisions

- D1 — Three run buckets, and they partition. Every agent run in a ride lands
  in EXACTLY ONE of `runs_marked` (a valid `usage_total_tokens=<N>` marker via
  `extractUsageTotal`), `runs_sentinel` (no marker, but the canonical
  `usage_capture=none` sentinel via `hasUsageSentinel` — the honest-gap escape
  hatch the enforce dial accepts), and `runs_unmarked` (neither). Marker WINS
  over sentinel when a note somehow carries both: a run with a real total is a
  measured run. The three counts summing to `runs_total` is an asserted
  invariant, not a convention — it is what makes the section auditable at a
  glance.

- D2 — Only `runs_marked` feeds a number. `tokens_total`,
  `median_tokens_per_run` and `share_pct` are computed over marker-carrying
  runs alone and are `null` — never `0` — when a role has no marked run. This
  is the same rule the sibling `capture_coverage` KPI already follows (an
  empty ledger yields `pct: null`, an all-unmarked ledger yields an honest
  `0`), and the same rule the remediation `n/a` bucket follows. A reader must
  never be able to mistake "not measured" for "measured as cheap".

- D3 — The week vocabulary is BORROWED, never recomputed. `by_week` uses the
  existing `m.trend[].week` array verbatim — the union of delivery weeks and
  ride weeks — in the same order and with the same length. Recomputing weeks
  from marked runs alone would produce a shorter series than the report's other
  four charts, so a reader comparing the token curve against the delivery curve
  would be comparing different x-axes. This is a seam (S1) and it gets an
  equality assertion, not a comment.

- D4 — Marker-only, matching the sibling KPI, NOT the close gate. The close-
  time gate also accepts decomposed `tokens_in`/`tokens_out` as captured; this
  report does not, exactly as the pre-existing `capture_coverage` KPI in the
  same section does not. Both fields are `null` across the entire ledger, so
  the boundary is theoretical today, and internal consistency inside one
  section beats consistency with a differently-purposed gate. Recorded as R1.

- D5 — Six canonical roles always, `Other` only when populated. `roles` carries
  the six `CANONICAL_ROLES` in the SAME order the pre-existing
  `cost.by_role` uses (the length-sorted canonical order), so the two tables
  read as one; a role with zero runs is present with `runs_total: 0` and null
  measures rather than being filtered out, because a missing row and a
  never-ran row are different facts. `Other` (roles that `normalizeRole`
  rejects — the live ledger has seven such variant strings) is appended only
  when it holds at least one run.

- D6 — The new HTML block is the ONLY element in the page carrying an `id`
  attribute. That is what makes the back-compat pin (Spec-AC-05) mechanical:
  the test excises exactly `<section id="role-consumption">` through the
  following `</section>` and compares the remainder byte-for-byte against a
  golden captured from the PRE-change generator. Adding `id`s to the existing
  sections would break that comparison on its first run, so the change adds
  exactly one.

- D7 — Goldens are captured BEFORE the script is edited, never regenerated
  after. The whole value of `tests/fixtures/factory-report/*` is that it
  contains bytes the new code never produced. A golden refreshed from the new
  generator proves only that the new generator agrees with itself.

- D8 — No new script, no new dependency, no network. Node stdlib only, and the
  aggregation reuses `extractUsageTotal`, `hasUsageSentinel`, `CANONICAL_ROLES`
  and `normalizeRole` from `.aai/scripts/lib/usage-note.mjs` — never a
  re-declared regex or a forked role list (the TEST-003 grep contract in the
  metrics suite pins the single-source rule).

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the aggregation math and the honesty buckets
  (TEST-022/023/024) — bucket partitioning, null-not-zero, and the
  cross-KPI denominators are precisely the class of code that looks right and
  is off by one unmarked run, and each of these tests fails naturally on the
  pre-change generator (`cost.role_consumption` is undefined), so a genuine RED
  is cheap and honest. Loop for the render and the product doc
  (TEST-025/027), where the HTML-versus-data assertion is the evidence and a
  RED is produced automatically the moment the section is absent. TEST-026 is
  a regression pin whose RED is a MUTATION run, spelled out under RED
  discipline below. STATE carries no intake-sourced strategy for this scope
  (the recorded `hybrid` belongs to the CHANGE-0129 ride, with `source` naming
  that spec, not `intake`) and CHANGE-0130 records no
  `Implementation mode (user choice):` line, so this is Planning's call.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one script, one test file, one product doc and two new
  fixture files; no `protected_paths_l3` surface. Work is already on the
  dedicated branch `feat/role-token-trend`, which gives the isolation a
  worktree would give. Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/role-token-trend (current checkout)
- Inline review scope: .aai/scripts/generate-factory-report.mjs,
  tests/skills/test-aai-factory-report.sh,
  tests/fixtures/factory-report/backcompat-sparse-data.json,
  tests/fixtures/factory-report/backcompat-sparse.html,
  docs/product/factory-performance-report.md,
  docs/specs/SPEC-DRAFT-spec-role-token-trend.md,
  docs/issues/CHANGE-0130-role-token-trend.md, CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0130 AC-001
- Spec-AC-01: `factory-report-data.json` carries `cost.role_consumption.roles`,
  an array holding the six `CANONICAL_ROLES` in the same order as
  `cost.by_role`, plus a trailing `Other` entry if and only if at least one run
  normalizes to no canonical role. Each entry carries `role`, `runs_total`,
  `runs_marked`, `runs_sentinel`, `runs_unmarked`, `tokens_total`,
  `median_tokens_per_run` and `share_pct`. The three bucket counts partition
  `runs_total` (they sum to it exactly), a run whose note carries both a marker
  and the sentinel counts as marked, and `tokens_total`,
  `median_tokens_per_run` and `share_pct` are `null` — never `0` — for every
  role whose `runs_marked` is `0`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_022_role_consumption_buckets`
    against a fixture with hand-computed per-role runs covering all three
    buckets, a both-markers run, a never-ran role and a non-canonical role
    variant. Evidence: suite stdout plus the stored RED transcript.

- Maps to: CHANGE-0130 AC-001
- Spec-AC-02: the new block agrees with the KPIs already in the same section,
  on any ledger. Summed over `cost.role_consumption.roles`: `runs_total` equals
  `cost.capture_coverage.total_runs`, `runs_marked` equals
  `cost.capture_coverage.runs_with_marker`, and the non-null `tokens_total`
  values sum to `cost.tokens_total`. Per role, `tokens_total` equals the
  matching `cost.by_role[].tokens` (both null when the role carries no marked
  run) and `share_pct` equals `Math.round(100 * tokens_total / cost.tokens_total)`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_023_role_consumption_seam_invariants`,
    which asserts every identity above TWICE — once on a crafted fixture and
    once on the repository's REAL `docs/ai/METRICS.jsonl` and
    `docs/ai/EVENTS.jsonl` read read-only into a scratch output dir (the
    identities are ledger-independent, so the assertion does not rot as the
    ledger grows, and the real ledger is the only input that exercises the
    sparse era, the seven non-canonical role variants and 222 unmarked runs at
    once). Evidence: suite stdout plus the stored RED transcript.

- Maps to: CHANGE-0130 AC-002
- Spec-AC-03: `cost.role_consumption.by_week` is an array of one entry per ISO
  week whose `week` values equal `m.trend.map(t => t.week)` exactly — same
  values, same order, same length. Each entry carries a `roles` array with the
  same role vocabulary and order as `cost.role_consumption.roles`, and each of
  those carries `runs_marked` for that role in that week and `median_tokens`,
  the median over that role's marker-carrying runs in that week, or `null` when
  the role has no marked run that week. A week present in `m.trend` because a
  delivery closed in it, with no ride at all, appears with every
  `median_tokens` null and every `runs_marked` zero.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_024_role_consumption_weekly_trend`
    against a fixture spanning two ride weeks plus one delivery-only week, with
    one role marked in both ride weeks (two different medians, one of them over
    an even number of runs to pin the rounding), one role marked in only the
    first, and one role never marked. Evidence: suite stdout plus the stored
    RED transcript.

- Maps to: CHANGE-0130 AC-003
- Spec-AC-04: the HTML carries one new `<section id="role-consumption">` with
  an `<h2>Role consumption</h2>`; a per-role table whose cells render the same
  values `factory-report-data.json` carries for that role, with the literal
  `n/a` wherever the model holds `null`; a weekly table whose first column is
  the ISO week and whose per-role cells render `median_tokens` or the literal
  `n/a`; and exactly one `class="spark"` SVG per role whose `runs_marked` is
  greater than zero. No dollar-amount figure (`$` followed by a digit) appears
  anywhere in either output.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_025_role_consumption_html`,
    which reads the values out of `factory-report-data.json` and asserts each
    one is rendered, counts the sparklines against the model, asserts the `n/a`
    literals for the null cells, and re-runs the TEST-006 dollar-amount grep
    over both outputs. Evidence: suite stdout plus the stored RED transcript.

- Maps to: CHANGE-0130 AC-003
- Spec-AC-05: the change is additive at the byte level for a sparse ledger. On
  a fixture whose runs carry NO marker at all, `factory-report-data.json` with
  the `cost.role_consumption` key deleted and the `generatedAt` value replaced
  by a fixed placeholder is byte-identical to
  `tests/fixtures/factory-report/backcompat-sparse-data.json`; and
  `factory-report.html` with the `<section id="role-consumption">` block
  excised (through the following `</section>` and its trailing blank line) and
  the same `generatedAt` normalization applied is byte-identical to
  `tests/fixtures/factory-report/backcompat-sparse.html`. Both goldens are
  produced by the PRE-change generator on that fixture and are never
  regenerated afterwards (D7). On the same sparse fixture the new key IS
  present, with every `tokens_total`, `median_tokens_per_run` and `share_pct`
  null and every run in `runs_unmarked`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_026_role_consumption_backcompat`.
    Evidence: the two committed goldens, the suite stdout, the stored RED
    transcript for the new-key arm, and the stored MUTATION RED transcript for
    the byte-stability arm (see RED discipline).

- Maps to: CHANGE-0130 AC-003
- Spec-AC-06: nothing else regresses and no companion obligation fires. The
  whole `tests/skills/test-aai-factory-report.sh` suite exits 0 with zero
  `FAIL` lines and still runs TEST-001 through TEST-021; the three sibling
  suites over the shared `lib/usage-note.mjs` grammar and the close hook —
  `test-aai-metrics.sh`, `test-aai-overview.sh`, `test-aai-close-work-item.sh` —
  each exit 0; `test-aai-layer-profiles.sh` exits 0; and
  `git diff --name-only main...HEAD` contains neither `.aai/system/PROFILES.yaml`
  nor `tests/skills/lib/prompt-diet-ledger.sh` nor
  `tests/skills/test-aai-prompt-diet.sh`, because no new `.aai/**` file is added
  and no `.aai/*.prompt.md` byte changes.
  - Verification: the five suite commands above plus the `git diff --name-only`
    listing. Evidence: the five stdouts and the diff listing.

- Maps to: CHANGE-0130 AC-004
- Spec-AC-07: `docs/product/factory-performance-report.md` documents the new
  section and its honesty semantics, carrying as greppable text: the heading
  `Role consumption`; the three bucket names `runs_marked`, `runs_sentinel`,
  `runs_unmarked`; the statement that medians, totals and shares derive only
  from marker-carrying runs; the statement that a role or week with no marked
  run renders `n/a` and is never imputed; and the sparse-era caveat naming
  `2026-08-02` as the date from which capture is complete. Its frontmatter
  `delivered_by` gains `CHANGE-0130` and `updated` is bumped to the delivery
  date.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_027_product_doc_pins`
    for the greppable pins and the frontmatter fields, plus
    `node .aai/scripts/docs-audit.mjs --check` exiting 0. Evidence: suite
    stdout and the audit stdout.

## Constitution deviations

None. Article 2 (simplicity): D8 keeps the change to one additive block in an
existing script with no new dependency. Article 3 (portability): output stays
a plain self-contained HTML file plus a git-diffable JSON. Article 4 (degrade
and report): the new block inherits the generator's degrade-with-NOTE contract
— an absent or malformed ledger still exits 0, and unmeasured runs are named
rather than dropped. Article 5 (additive first): Spec-AC-05 makes additivity a
byte-level, test-pinned property rather than an intention.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the generator runs THEN cost.role_consumption.roles lists the six canonical roles in cost.by_role order plus Other when populated, each with three partitioning run buckets, and null rather than zero for tokens median and share when no run is marked | done | TEST-022 green; docs/ai/tdd/red-TEST-022-20260811T210000Z.log; docs/ai/tdd/green-20260811T204338Z-factory-report-full.log | — | marker beats sentinel on a both-markers note (D1) |
| Spec-AC-02 | WHEN the block is summed THEN run counts match capture_coverage, token totals match cost.tokens_total and cost.by_role per role, and share_pct is the rounded percentage of the grand total | done | TEST-023 green (fixture + real docs/ai ledger arms); docs/ai/tdd/red-TEST-023-20260811T210000Z.log | — | asserted on a fixture AND on the real ledger (S2) |
| Spec-AC-03 | WHEN the weekly view is built THEN its week list equals m.trend week for week in order, and a role with no marked run in a week has median_tokens null | done | TEST-024 green; docs/ai/tdd/red-TEST-024-20260811T210000Z.log | — | borrowed week vocabulary is seam S1 (D3) |
| Spec-AC-04 | WHEN the HTML renders THEN a section id role-consumption carries a per-role table, a weekly table with n/a literals, and one spark SVG per role with marked runs, and no dollar figure appears | done | TEST-025 green; docs/ai/tdd/red-TEST-025-20260811T210000Z.log | — | html-versus-data seam S3 |
| Spec-AC-05 | WHEN a sparse no-marker ledger is rendered THEN the outputs minus the new key and the new section are byte-identical to goldens captured from the pre-change generator, and the new key is present all-null | done | TEST-026 green; docs/ai/tdd/red-TEST-026-20260811T210000Z.log (new-key arm); docs/ai/tdd/red-TEST-026-mutation-20260811T204356Z.log + docs/ai/tdd/green-TEST-026-mutation-revert-20260811T204402Z.log (byte-stability mutation pair) | — | byte-stability arm proven RED by mutation |
| Spec-AC-06 | WHEN the suites re-run THEN the factory-report suite plus metrics overview close-work-item and layer-profiles all exit 0 and no governance path appears in the scope diff | done | docs/ai/tdd/green-20260811T204338Z-factory-report-full.log (TEST-001..027, 0 FAIL); test-aai-metrics.sh, test-aai-overview.sh, test-aai-close-work-item.sh, test-aai-layer-profiles.sh all exit 0; `git diff --name-only main...HEAD` free of PROFILES.yaml/prompt-diet-ledger.sh/test-aai-prompt-diet.sh | — | companion obligations do not fire |
| Spec-AC-07 | WHEN the product doc is read THEN it names the Role consumption section, the three buckets, the marker-only rule, the never-imputed n/a rule and the 2026-08-02 sparse-era caveat | done | TEST-027 green; docs/ai/tdd/red-TEST-027-20260811T210000Z.log; docs/product/factory-performance-report.md frontmatter delivered_by/updated bumped | — | frontmatter delivered_by and updated bumped |

## Implementation plan

Components:

- `.aai/scripts/generate-factory-report.mjs` (EDIT — the whole substance):
  - `buildModel`, inside the existing `for (const m of rides)` /
    `for (const r of m.agent_runs ?? [])` loop that already computes
    `roleDurations`, `roleTokens` and `coverageByWeek`: accumulate, per
    `roleKey` (the existing `normalizeRole(r.role) ?? 'Other'`), the three
    bucket counts and the per-run token list, and per `(rideWeek, roleKey)` the
    per-run token list. One extra pass over data already in hand — no second
    read, no second parse.
  - After the trend series is built (so the `weeks` array exists), project the
    accumulators into `cost.role_consumption`, reusing the existing `median()`
    helper for both the overall and the per-week medians.
  - `renderHtml`: one new `<section id="role-consumption">` inserted between
    the Cost section and the Quality section, emitted as a single contiguous
    string that begins with `<section id="role-consumption">` and ends with
    `</section>` plus one blank line, so the Spec-AC-05 excision restores the
    prior bytes exactly. Reuse `esc`, `na` and `barSeries` — `barSeries` takes
    `{week, median_tokens}` points directly and already renders a null point as
    a grey bar with an `n/a` title.
  - The empty-ledger render path (`m.empty`) is untouched: it returns before
    any section is emitted.
- `tests/skills/test-aai-factory-report.sh` (EDIT): six new test functions
  registered in `main()` as TEST-022 through TEST-027, following the file's
  conventions (`mk_repo`, `run_report`, `node_get`, `log_pass`/`log_fail`,
  bash 3.2, scratch temp-dir repos only). Numbering continues past the suite's
  current maximum (021); 015 and 016 stay unused, as they are today.
- `tests/fixtures/factory-report/backcompat-sparse-data.json` and
  `tests/fixtures/factory-report/backcompat-sparse.html` (NEW): the two
  goldens, captured per D7 from the pre-change generator, `generatedAt`
  normalized. New files under `tests/`, not `.aai/**` — no PROFILES entry is
  owed.
- `docs/product/factory-performance-report.md` (EDIT): the Spec-AC-07 pins.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading carrying this
  change's entry (per-entry heading form, never bullets under a bare scaffold).

Data flows:

- `METRICS.jsonl` line -> ride -> `agent_runs[]` -> (`normalizeRole(role)`,
  `extractUsageTotal(note)`, `hasUsageSentinel(note)`) -> per-role accumulator
  and per-(week, role) accumulator -> `cost.role_consumption` -> the new HTML
  section. `EVENTS.jsonl` enters only through the already-built `weeks` array
  (delivery weeks), which is exactly the D3 borrowing.

Edge cases:

- A ride with `date_utc` absent or unparseable yields `isoWeek(...) === null`;
  its runs count in the overall per-role buckets but belong to no week, exactly
  as the pre-existing `coverageByWeek` treats them. State this in the section's
  caption so overall and weekly run counts are allowed to disagree honestly.
- An even number of marked runs makes `median()` average the two middle values
  and `Math.round` the result — pinned deliberately by TEST-024.
- `share_pct` needs a guard when `cost.tokens_total` is null or zero: null, not
  a division result.
- Roles that `normalizeRole` rejects already trigger the existing
  `unnormalizedRoleRuns` NOTE; the `Other` row must be consistent with that
  count, not a second, differently-derived one.
- A ride whose `agent_runs` is absent contributes nothing and must not create a
  role row out of thin air.

## Seams

- S1 — the new weekly series <-> the existing `m.trend` week vocabulary.
  Produced by the trend builder, consumed by the role-consumption projection.
  A recomputed week list would silently desynchronize the new chart's x-axis
  from the four charts above it, and every value would still look plausible.
  Crossed by TEST-024, which asserts array equality against `m.trend`, not a
  hand-written expectation.
- S2 — the new per-role aggregation <-> the pre-existing `capture_coverage`
  and `cost.by_role`/`cost.tokens_total` aggregations. Three independent code
  paths now count the same runs and sum the same markers; a bucket rule that
  drifts from `extractUsageTotal` shows up here and nowhere else. Crossed by
  TEST-023, which re-sums the new block and compares it against the OTHER
  block's numbers on the same run, including on the real ledger. No mock
  exists on this path.
- S3 — `factory-report-data.json` <-> `factory-report.html`. One model, two
  renderings; a formatting helper that turns a null into `0` in the HTML while
  the JSON stays honest is the classic failure here. Crossed by TEST-025,
  which reads expectations OUT of the JSON produced by the same run and
  asserts them present in the HTML, rather than restating literals.
- S4 — the generator <-> `close-work-item.mjs`, which regenerates the report
  best-effort at every close. Already crossed by the existing TEST-013
  negative control (a rigged generator failure must leave the close exit code
  and the doc status unchanged); re-run unchanged under Spec-AC-06 rather than
  duplicated.
- S5 — the goldens <-> future legitimate edits to existing fields. Not a
  runtime seam but a maintenance one: any later change to a pre-existing field
  will fail TEST-026 by design, and the correct response is a deliberate
  golden refresh recorded in that change, never a silent regeneration. Stated
  here so the failure reads as a signal rather than a flake.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-022 | Spec-AC-01 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_022_role_consumption_buckets` — six canonical roles in cost.by_role order plus Other when populated, three buckets summing to runs_total, marker beats sentinel, never-marked role all-null never zero | green |
| TEST-023 | Spec-AC-02 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_023_role_consumption_seam_invariants` — re-summed run counts equal capture_coverage, token totals equal cost.tokens_total and cost.by_role, share_pct is the rounded share, asserted on a fixture AND on the real docs/ai ledgers | green |
| TEST-024 | Spec-AC-03 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_024_role_consumption_weekly_trend` — by_week weeks equal m.trend weeks in order, per-role weekly medians correct incl. even-count rounding, unmarked role-week null, delivery-only week all-null | green |
| TEST-025 | Spec-AC-04 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_025_role_consumption_html` — section id role-consumption renders the JSON values, n/a literals for nulls, one spark SVG per role with marked runs, no dollar figure in either output | green |
| TEST-026 | Spec-AC-05 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_026_role_consumption_backcompat` — sparse no-marker fixture: outputs minus the new key and the new section equal the pre-change goldens byte-for-byte after generatedAt normalization, and the new key is present all-null | green |
| TEST-027 | Spec-AC-07 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_027_product_doc_pins` — the product doc carries the Role consumption heading, the three bucket names, the marker-only rule, the never-imputed n/a rule, the 2026-08-02 caveat, and frontmatter delivered_by CHANGE-0130 | green |
| TEST-028 | Spec-AC-06 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh` — the whole suite exits 0 with zero FAIL lines and TEST-001 through TEST-021 still run | green |
| TEST-029 | Spec-AC-06 | int  | tests/skills/test-aai-metrics.sh | run `bash tests/skills/test-aai-metrics.sh` then `bash tests/skills/test-aai-overview.sh` then `bash tests/skills/test-aai-close-work-item.sh` — the three sibling consumers of lib/usage-note.mjs and the close hook each exit 0 | green |
| TEST-030 | Spec-AC-06 | int  | tests/skills/test-aai-layer-profiles.sh | run `bash tests/skills/test-aai-layer-profiles.sh` and `git diff --name-only main...HEAD` — profiles union still equals the live .aai tree and the diff names none of PROFILES.yaml, prompt-diet-ledger.sh, test-aai-prompt-diet.sh | green |

RED discipline (strategy hybrid). TEST-022, TEST-023, TEST-024, TEST-025 and
TEST-027, plus the new-key arm of TEST-026, are the AC-gating tests and MUST be
observed FAILING on the PRE-change tree before the generator is edited — all of
them reference `cost.role_consumption`, which does not exist yet, so the RED is
real rather than staged. Store each transcript under `docs/ai/tdd/`.

The byte-stability arm of TEST-026 cannot fail before the change (deleting an
absent key is a no-op), so a pre-change run of it proves nothing. Its honest
RED is a MUTATION, run AFTER the goldens are captured and the generator is
edited: perturb exactly one pre-existing model field (for example round
`cost.tokens_per_ride.mean` to an integer), observe TEST-026 FAIL naming the
byte difference, revert the perturbation, observe GREEN. Store BOTH transcripts
under `docs/ai/tdd/`. Without that pair the pin is unproven and must not be
counted as evidence.

TEST-028, TEST-029 and TEST-030 are loop-covered regression rows: a green run
is the evidence.

## Verification

Commands:
- `bash tests/skills/test-aai-factory-report.sh`
- `bash tests/skills/test-aai-metrics.sh`
- `bash tests/skills/test-aai-overview.sh`
- `bash tests/skills/test-aai-close-work-item.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `node .aai/scripts/generate-factory-report.mjs --data-only` (real ledger, exit 0)
- `node .aai/scripts/docs-audit.mjs --check`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-role-token-trend.md`
- `git diff --name-only main...HEAD`

Evidence artifacts: suite stdout with per-TEST pass lines, the RED transcripts
under `docs/ai/tdd/` (including the TEST-026 mutation pair), the two committed
goldens, the regenerated `docs/ai/factory-report.html` and
`docs/ai/factory-report-data.json`, and the scope diff listing.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or review verdict, evidence path, commit SHA or diff range.

### Evidence by strategy

Strategy is `hybrid`: stored RED artifacts are demanded for TEST-022, TEST-023,
TEST-024, TEST-025, TEST-027 and both arms of TEST-026, together with the full
verification matrix above. TEST-028 through TEST-030 need green runs only.

## Residual risks

- R1 — Marker-only capture boundary (D4). If decomposed `tokens_in`/
  `tokens_out` telemetry ever starts landing in the ledger, those runs will
  count as `runs_unmarked` here and in the pre-existing `capture_coverage` KPI,
  while the close-time gate counts them as captured. Both fields are null
  across the entire ledger today, so nothing is currently mis-reported. The
  mitigation is that the divergence is shared with the sibling KPI in the same
  section, so it can only ever be fixed jointly, and TEST-023's identity
  assertions would keep the two consistent while they drift together. Accepted,
  not tested.
- R2 — Median over a small n. Per-role, per-week medians over one or two marked
  runs are arithmetic, not statistics, and the sparse era makes early weeks
  especially thin. Nothing in the data can fix this; the mitigation is that
  `runs_marked` sits next to every median in both the JSON and the rendered
  tables, so the denominator is never hidden, and the product doc says so
  (Spec-AC-07). Accepted.
- R3 — Golden maintenance (S5). TEST-026 will fail on any future legitimate
  change to an existing field, and a hurried refresh of the goldens from the
  then-current generator would silently retire the pin. Mitigation: D7 and this
  risk are written down, and the goldens live in a dedicated directory whose
  only purpose is to hold pre-change bytes. Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
