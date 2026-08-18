---
id: spec-ride-cost-readout
type: spec
number: 134
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0148-ride-cost-readout.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Factory report: what one scope cost

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0148-ride-cost-readout.md
- Prior spec (the generator this change extends): docs/specs/SPEC-0108-spec-factory-performance-report.md
- Prior spec (the additive-section precedent in the same file and suite): docs/specs/SPEC-0117-spec-role-token-trend.md
- Prior spec (the marker grammar and the canonical role list): docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
- Product doc updated by this scope: docs/product/factory-performance-report.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — one existing `.aai` script gains an additive,
read-only per-scope fold over data its own loop already walks, plus rows in the
one suite that already covers it, plus that suite's product doc. No
`protected_paths_l3` surface appears in the file list (state engine, allocator,
pre-commit guards, `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`), no new
script, no new dependency, no network, no gate. The generator runs best-effort
at close and its failure never changes a close exit code (SPEC-0108 Spec-AC-09,
pinned by the existing TEST-013), so a defect's blast radius is a wrong number
on a report page. Level 1 still owes a suite re-run plus a targeted probe and a
full dual-verdict review; the Test Plan below IS the declared validation scope
and every row names a directly executable command.

## Summary

The factory records every role run and never totals one scope. The report
already carries a per-ride array (`speed.per_ride`) but it holds only
`busy_seconds` and `remediation_runs`, it is JSON-only, and it answers neither
question the owner actually asked four times on 2026-08-16/17: how long did
this ride take, and how many tokens did it burn. Both are computable today from
`docs/ai/METRICS.jsonl` alone, which is why answering them by hand is possible
at all — and why it keeps happening.

This scope adds ONE additive top-level block, `scope_cost`, and ONE new HTML
section rendered from it. Per scope: the elapsed span, the agent time, the run
count per role, the token total with its own coverage denominator, and a
remediation figure. Report-only — nothing here gates, refuses, or changes an
exit code, and no new input is read.

Three things measured on the live ledger on 2026-08-17 (124 rides, 541 agent
runs) shape every decision below, and each one contradicts an intuition the
intake or a reader might carry:

1. Elapsed wall clock and summed agent time are NOT the same number and neither
   bounds the other. `deslop-scope-and-unrequested-engine` (CHANGE-0145): 25.0 h
   elapsed vs 17.7 h agent. `role-verification-guards` (CHANGE-0146): 14.6 h vs
   11.1 h. On 23 of 124 rides the agent sum EXCEEDS the elapsed span, because
   roles ran concurrently. The hand figures the intake quotes ("about 30 hours",
   "about 15") are wall-clock-shaped; showing agent time under an unqualified
   "duration" label would answer the owner's question wrong by roughly 30%.
2. Token markers are missing in patches, not in blocks: 52 rides carry a marker
   on every run, 46 on none, and 24 carry them on SOME runs. A partial sum is
   the common case, not the corner case, so it cannot be handled by a footnote.
3. A `Remediation` run does not imply a failed validation. Of the 32 rides with
   at least one remediation run, 18 record `validation_fails: 0` — their
   remediation came from review or bot findings. The figure this scope ships is
   therefore named for what it measures (remediation), never for what it does
   not (failed rounds).

## Design decisions

- D1 — BOTH time figures, under labels that cannot be read as synonyms, plus a
  computed divergence note. `elapsed_wall_seconds` is the last `ended_utc`
  minus the first `started_utc` across the ride's `agent_runs`;
  `agent_seconds` is the sum of `duration_seconds` over the same runs. The
  rendered column headings are `Elapsed (wall clock)` and `Agent time
  (summed)`, never a bare "duration", and the section caption states that agent
  time falls BELOW elapsed when a ride idles between roles and ABOVE it when
  roles overlap. The count of scopes where `agent_seconds` exceeds
  `elapsed_wall_seconds` is COMPUTED into `notes` rather than written as prose,
  so the caveat cannot go stale as the ledger grows.

- D2 — Agent time is the run-level sum, not `totals.agent_duration_seconds`.
  The existing loop already computes that sum as `perRide.busy_seconds`, and
  the new block reuses it; deriving the same quantity twice from two fields is
  how the two silently drift. The two agree on all 124 rides today, and
  Spec-AC-01 keeps them agreeing by asserting the identity on the real ledger
  rather than trusting it.

- D3 — Tokens come only from `extractUsageTotal` in
  `.aai/scripts/lib/usage-note.mjs`. No second regex literal for that grammar
  is added anywhere; the single-source rule is already pinned by the metrics
  suite's TEST-003 grep contract and Spec-AC-03 re-asserts it over this file.
  A run with no valid marker contributes NOTHING — it is not read as zero.

- D4 — A partial token sum is SHOWN, never suppressed, and never shown alone.
  Every token figure travels with its own denominator, `runs_marked` of
  `runs_total`, rendered in the same cell. Refusing to total until coverage is
  complete would blank 24 of 124 rides — including rides mid-2026 that are
  exactly the ones worth comparing — and would make the section useless where
  it is most needed. Showing a bare partial would understate silently. The
  denominator is the whole answer: it is not optional decoration, and
  Spec-AC-04 asserts it is present in every rendered token cell.

- D5 — Zero measured runs renders a NAMED line, never a zero. When
  `runs_marked` is 0, `tokens_total` is `null` and the cell renders the literal
  `no usage marker (0/N runs)`. This is the same never-impute rule the sibling
  `capture_coverage` and `role_consumption` blocks already follow.

- D6 — Rework is the REMEDIATION figure, derived structurally per run, and it
  is named for that. The reasoning the intake asks for:
  - Structural derivation is forced, not chosen. The rework figure needs
    per-RUN attribution (which runs' tokens count), and `reliability` is a
    per-RIDE block with no per-run linkage. `normalizeRole(r.role) ===
    'Remediation'` is the only available attribution.
  - It does NOT contradict SPEC-0108 Spec-AC-05 ("remediation count is
    reliability-only, NOT a role-prefix guess"). That rule governs the QUALITY
    distribution, a ride-level rate where a pre-`reliability` ride must land in
    an explicit `n/a` bucket instead of inflating the zero bucket. Here every
    ride has runs, so there is no n/a case to protect, and the two derivations
    already agree on all 98 rides that carry the block (measured 2026-08-17).
    Spec-AC-05 keeps them agreeing by emitting a named note when they disagree
    — a report-only note, not a gate.
  - The preceding Validation run's cost is EXCLUDED. Attributing it would
    require deciding that it failed, and no field records that: the
    `verdict=fail` text in some notes is an ad-hoc mid-ride convention,
    inconsistent across records, and the intake forbids reading prose. Counting
    every Validation run that precedes a remediation would also be wrong on the
    18 measured rides where remediation followed a clean validation.
  - The label therefore says remediation, not failure. The section states that
    the figure counts remediation runs only, and that the round which produced
    the finding is not included.

- D7 — The share is a share of MEASURED tokens. `remediation_share_pct` is
  `round(100 * remediation_tokens / tokens_total)` where both are marker-only
  sums, and it is `null` whenever either is `null` or `tokens_total` is 0. It
  is labelled `Remediation share (of measured tokens)`, and the row's
  `runs_marked/runs_total` denominator sits in the same table row, so a share
  computed over half a ride is visibly that.

- D8 — Token-shaped, not duration-shaped. A remediation share can be computed
  over agent seconds too, and it is a materially different number: 19% vs 45%
  on CHANGE-0145, 16% vs 35% on CHANGE-0146. The intake's ask is token-shaped,
  and shipping two rework percentages that disagree by more than twofold would
  manufacture exactly the confusion D1 exists to prevent. Only the token share
  ships; the duration share is out of scope and named as such in Notes.

- D9 — Extend `generate-factory-report.mjs`; no new file. Every input is
  already walked by the existing `for (const m of rides)` /
  `for (const r of m.agent_runs ?? [])` loop, which today computes `busy`,
  `tok`, `roleDurations`, `roleTokens`, `coverageByWeek` and `roleConsumption`
  in one pass. This is the same call SPEC-0117 D8 made in the same function for
  the same reason: one extra accumulator inside the existing loop, no second
  read, no second parse. A `lib/scope-cost.mjs` module would either re-walk the
  rides or take the accumulators as arguments, and it would add a new
  `.aai/**` file whose only consumer is this generator (the dashboard is
  explicitly out of scope), buying a `PROFILES.yaml` classification obligation
  for no reuse. The file grows by roughly 60 lines of model code and one render
  block; `buildModel` stays a single-pass fold.

- D10 — One ordering, defined in the model. `scope_cost.scopes` is sorted by
  `elapsed_wall_seconds` DESCENDING with `null` last and ties broken by `ref`
  ascending; the HTML renders that array in order. Sorting only in the renderer
  would give the two surfaces different orders and make the parity assertion
  meaningless. Descending-by-elapsed is what serves the stated purpose —
  deciding about scope size — and a named scope is still one page-search away.

- D11 — Every ride in `METRICS.jsonl` gets a row; none are filtered by close
  state. `agent_runs` exists only there, 122 of 124 rides also carry a close
  event, and filtering the other two out would hide real cost for a
  bookkeeping reason. The section caption says the row set is the metrics
  ledger.

- D12 — The per-scope role cell lists only roles that ran. SPEC-0117 D5 keeps
  never-ran roles visible with `runs_total: 0` because that table is a global
  rollup where "this role never ran at all" is a finding. Per scope it is
  routine — most rides never run every role — and 124 rows times six roles is
  noise that hides the signal. `runs_total` is present on the row, so the
  counts are still auditable.

## Implementation strategy
- Strategy: direct
- Rationale: this is an additive fold over a ledger the same function already
  parses, with a fixture-driven suite that already exists; there is no new
  subsystem, no new input and no interface to discover, so the RED-GREEN cycle
  per test would be ceremony over arithmetic. The intake's `## Notes` records
  "Strategy suggestion: direct with targeted tests" and carries no
  `Implementation mode (user choice):` line; STATE's recorded `direct` belongs
  to the `docs-model-nul-escape` ride (its `source` names that intake), so this
  is Planning's call and it agrees with the suggestion. Direct does NOT waive
  the failing-first observation: every new arm asserts on `scope_cost`, a key
  that does not exist on the pre-change tree, so each one fails naturally
  before the edit. See the failing-first discipline under the Test Plan for
  what must be observed and where it is recorded.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one script, one test file, one product doc, one intake
  frontmatter line; no `protected_paths_l3` surface and no parallel scope
  touching these paths. Isolation is not needed for safety. It is offered only
  because `docs/ai/factory-report.html` and `factory-report-data.json` are
  regenerated by `close-work-item.mjs` on EVERY close, so a concurrent scope
  closing in the shared tree will rewrite both generated files mid-ride and
  make a diff read as this scope's work. A dedicated branch is required
  regardless by the one-branch-per-work-item rule `branch-guard.mjs` enforces
  at PR. Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/ride-cost-readout (proposed)
- Inline review scope: .aai/scripts/generate-factory-report.mjs,
  tests/skills/test-aai-factory-report.sh,
  docs/product/factory-performance-report.md,
  docs/specs/SPEC-0134-spec-ride-cost-readout.md,
  docs/issues/CHANGE-0148-ride-cost-readout.md, CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: ride-cost-readout AC-001
- Spec-AC-01: `factory-report-data.json` carries a top-level `scope_cost.scopes`
  array with one entry per `METRICS.jsonl` ride, each carrying `ref`,
  `date_utc`, `runs_total`, `elapsed_wall_seconds` and `agent_seconds`.
  `elapsed_wall_seconds` is the maximum parseable `ended_utc` minus the minimum
  parseable `started_utc` over that ride's `agent_runs`, in whole seconds, and
  is `null` when no run carries a parseable pair. `agent_seconds` is the sum of
  the runs' `duration_seconds` and is `null` when no run carries one. The array
  is ordered by `elapsed_wall_seconds` descending, `null` last, ties broken by
  `ref` ascending. `notes` gains one entry naming the count of scopes whose
  `agent_seconds` exceeds `elapsed_wall_seconds` whenever that count is above
  zero.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_031_scope_cost_elapsed_and_agent_time`
    over a fixture holding one ride with an idle gap between roles, one with
    two overlapping runs, one whose runs carry no timestamps, and one with no
    runs at all; plus a real-ledger arm asserting for every ride that
    `agent_seconds` equals `totals.agent_duration_seconds` (D2); plus a
    real-ledger SHADOW-MODEL arm that independently re-derives every
    `scope_cost.scopes[]` field (not only elapsed/agent time) straight from
    `docs/ai/METRICS.jsonl` using only the canonical `normalizeRole`/
    `extractUsageTotal`/`CANONICAL_ROLES` (D3), and diffs the full D10 sort
    order (tie-break included) and the emitted `(scope_cost)` notes against
    that independent computation — round-3 validation's finding: a fixture
    can only pin the shapes its author thought of, so the corpus itself is
    the anchor that cannot go stale. Evidence: suite stdout.

- Maps to: ride-cost-readout AC-002
- Spec-AC-02: each `scope_cost.scopes[]` entry carries a `roles` array of
  `{role, runs}` objects covering exactly the roles with at least one run in
  that ride, in `CANONICAL_ROLES` order with `Other` last, where `role` is
  `normalizeRole(r.role) ?? 'Other'` and the `runs` values sum to `runs_total`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_032_scope_cost_role_counts`
    over a fixture with a role variant string that `normalizeRole` maps to a
    canonical role, one it rejects into `Other`, a repeated role, and a ride
    whose `agent_runs` key is absent. Evidence: suite stdout.

- Maps to: ride-cost-readout AC-003
- Spec-AC-03: every token number in the block comes from `extractUsageTotal`
  imported from `.aai/scripts/lib/usage-note.mjs`, and a run whose note carries
  no valid marker contributes nothing rather than zero. `tokens_total` is the
  sum over marker-carrying runs and `runs_marked` is their count; a malformed
  marker (`usage_total_tokens=123oops`) and a prefixed key
  (`not_usage_total_tokens=456`) are both excluded. No capturing regex literal
  for the `usage_total_tokens` grammar appears in
  `.aai/scripts/generate-factory-report.mjs`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_033_scope_cost_token_source`
    over a fixture holding a valid marker, a malformed one, a prefixed key and
    a bare note, with hand-computed totals; plus
    `grep -c 'usage_total_tokens=(' .aai/scripts/generate-factory-report.mjs`
    returning 0 and `grep -c "from './lib/usage-note.mjs'" .aai/scripts/generate-factory-report.mjs`
    returning 1. Evidence: suite stdout and the two grep counts.

- Maps to: ride-cost-readout AC-003, AC-005
- Spec-AC-04: no token figure is ever rendered without its denominator. Every
  `scope_cost.scopes[]` entry carries `runs_marked` and `runs_total`, and every
  HTML table cell that shows a token count also shows the `runs_marked` of
  `runs_total` fraction in the same cell. A scope whose `runs_marked` is 0 has
  `tokens_total` `null` and renders the literal `no usage marker (0/N runs)`
  where N is `runs_total`, never a zero and never an empty cell.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_034_scope_cost_partial_and_no_data`
    over a fixture holding one fully marked ride, one ride marked on some runs
    only, and one ride marked on none, asserting the JSON nulls and the three
    rendered cell shapes. Evidence: suite stdout.

- Maps to: ride-cost-readout AC-004
- Spec-AC-05: each entry carries `remediation_runs`, the count of runs whose
  `normalizeRole` result is `Remediation`; `remediation_tokens`, the sum over
  marker-carrying remediation runs, `null` when none is marked; and
  `remediation_share_pct`, `round(100 * remediation_tokens / tokens_total)`,
  `null` whenever either input is `null` or `tokens_total` is 0. No value in
  the block is derived from prose in a note. When a ride carries
  `reliability.remediation_runs` and it differs from the structural count,
  `notes` gains one entry naming the ride and both numbers; when the block is
  absent no note is emitted.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_035_scope_cost_rework`
    over a fixture holding a ride with marked remediation runs and a
    hand-computed share, a ride with remediation runs that carry no marker
    (count present, tokens and share `null`), a ride with a `Remediation (E1
    over-kill)` variant string, a ride with a `reliability` block that
    disagrees with the structural count, and a ride with no `reliability` block
    at all; plus the note text for the disagreement. TEST-031's real-ledger
    shadow-model arm additionally re-derives `remediation_runs`,
    `remediation_tokens` and `remediation_share_pct` for every real ride and
    the exact `(scope_cost)` disagreement-note set, including the
    agreeing-block case this fixture's rows do not exercise (98 of 98 real
    rides carrying the block agree) — a fixture-independent check on the
    exact attribution rule this AC turns on. Evidence: suite stdout.

- Maps to: ride-cost-readout AC-006
- Spec-AC-06: the change is report-only. `node .aai/scripts/generate-factory-report.mjs`
  exits 0 on all five ledger shapes — absent `METRICS.jsonl`, empty file,
  comment-only file, a file with one malformed JSON line among valid ones, and
  the repository's real ledger — and no string matching `process.exit(` with a
  non-zero argument appears in `.aai/scripts/generate-factory-report.mjs`. No
  dollar-amount figure (`$` followed by a digit) appears in either output.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_036_scope_cost_report_only`
    for the five shapes, the `process.exit` grep and the dollar-amount grep.
    Evidence: the five exit codes and the two grep results.

- Maps to: ride-cost-readout AC-007
- Spec-AC-07: the HTML carries one new `<section id="scope-cost">` with an
  `<h2>` naming the section, a caption stating the wall-clock-versus-agent-time
  rule (D1), the remediation-not-failure rule (D6) and the metrics-ledger row
  set (D11), and one table row per `scope_cost.scopes[]` entry in array order.
  For every entry, the rendered `ref`, elapsed, agent time, role counts, token
  cell, remediation run count and share reproduce the values that same run
  wrote into `factory-report-data.json`, with the literal `n/a` wherever the
  model holds `null` (except the token cell, which follows Spec-AC-04).
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_037_scope_cost_html_parity`,
    which reads the expectations OUT of the JSON produced by the same run and
    asserts each is present in the HTML in row order, rather than restating
    literals. Evidence: suite stdout.

- Maps to: ride-cost-readout AC-006, AC-007
- Spec-AC-08: the change is additive at the byte level and nothing else
  regresses. On the existing sparse fixture, `factory-report-data.json` with
  `scope_cost` deleted alongside the two keys already deleted there, and
  `factory-report.html` with `<section id="scope-cost">` excised alongside the
  two sections already excised, remain byte-identical to the committed goldens
  in `tests/fixtures/factory-report/` after the existing `generatedAt`
  normalization; the goldens themselves are NOT regenerated. On that same
  all-unmarked fixture `scope_cost` is present with every `tokens_total`,
  `remediation_tokens` and `remediation_share_pct` `null`. The whole
  `tests/skills/test-aai-factory-report.sh` suite exits 0 with zero `FAIL`
  lines and still runs TEST-001 through TEST-029, and `test-aai-metrics.sh`,
  `test-aai-overview.sh` and `test-aai-close-work-item.sh` each exit 0.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_026_role_consumption_backcompat`
    (extended in place, the CHANGE-0142 precedent), then the four suite
    commands. Evidence: the four stdouts and the unchanged golden files.

- Maps to: ride-cost-readout AC-007
- Spec-AC-09: `docs/product/factory-performance-report.md` documents the new
  section, carrying as greppable text the heading naming the section, the two
  time labels `Elapsed (wall clock)` and `Agent time (summed)` with the
  statement that they diverge in both directions, the statement that token
  figures are marker-only and always carry a `runs_marked` denominator, the
  statement that a scope with no marker renders a named line and never a zero,
  and the statement that the remediation figure counts remediation runs and not
  the round that produced the finding. Its frontmatter `delivered_by` gains
  this scope's CHANGE id and `updated` is bumped. The intake's frontmatter
  `capability` reads `factory-performance-report`.
  - Verification: `bash tests/skills/test-aai-factory-report.sh test_039_scope_cost_product_doc_pins`
    for the greppable pins, the frontmatter fields and the intake `capability`
    value, plus `node .aai/scripts/docs-audit.mjs --check` exiting 0. Evidence:
    suite stdout and the audit stdout.

## Constitution deviations

None. Article 2 (simplicity): D9 keeps the change to one additive fold in the
loop that already walks the data, with no new file and no new dependency.
Article 3 (portability): the outputs stay a self-contained HTML page and a
git-diffable JSON. Article 4 (degrade and report): Spec-AC-06 pins exit 0 on
five ledger shapes, and D4, D5 and D7 make every unmeasured quantity say so by
name instead of rendering a zero. Article 5 (additive first): Spec-AC-08 makes
additivity a byte-level, test-pinned property rather than an intention.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the generator runs THEN every ride gets a scope_cost row carrying elapsed wall clock computed from first started_utc to last ended_utc AND summed agent time as two distinctly labelled figures, null rather than zero when unmeasurable, ordered by elapsed descending, with a computed note counting the scopes whose agent time exceeds their elapsed span | done | TEST-031 | — | agent time reuses the existing per-ride sum and is asserted equal to totals.agent_duration_seconds on the real ledger (D2); 2 of 124 zero-agent-run rides render null vs the ledger's literal 0, excluded from that identity as a representational, not a drift, difference; round-3 validation F3/F4/F5 (divergence-note boundary, date_utc, ref tie-break) now closed by the real-ledger shadow-model arm re-deriving every field from the raw ledger |
| Spec-AC-02 | WHEN a scope row is built THEN it carries a per-role run count covering exactly the roles that ran, in CANONICAL_ROLES order with Other last, summing to runs_total | done | TEST-032 | — | role vocabulary comes from normalizeRole, never a local list (D12) |
| Spec-AC-03 | WHEN token figures are computed THEN they come only from extractUsageTotal in lib/usage-note.mjs, a run with no valid marker contributes nothing rather than zero, and no capturing regex for that grammar exists in the generator | done | TEST-033 | — | single-source rule, greppable both ways (D3) |
| Spec-AC-04 | WHEN a token figure is rendered THEN the runs_marked of runs_total denominator is in the same cell, and a scope with zero marked runs renders a named no-marker line with a null total rather than a zero | done | TEST-034 | — | 24 of 124 rides are partially marked, so partial is the common case (D4 D5) |
| Spec-AC-05 | WHEN the rework figure is built THEN remediation runs tokens and share derive structurally from the Remediation role with no prose read, the share is null unless both inputs are measured, and a disagreement with reliability.remediation_runs emits a named note | done | TEST-035, TEST-031 | — | the preceding validation run is deliberately excluded and the label says remediation not failure (D6 D7); the disagreement note is tagged "(scope_cost)" so TEST-026's unrelated pre-existing fixture (which also trips it) can filter it, same as the deleted new keys; round-3 validation F1 (Validation counted as Remediation) and F2 (disagreement note firing on agreement) closed by TEST-031's real-ledger shadow-model arm, which re-derives remediation_runs/tokens/share_pct and the exact note set from the raw ledger, independent of the fixture |
| Spec-AC-06 | WHEN the generator runs over an absent empty comment-only malformed or real ledger THEN it exits 0 every time, the source contains no non-zero process.exit, and neither output carries a dollar amount | done | TEST-036 | — | report-only is the whole constraint; a cost figure that gates anything is a scope violation |
| Spec-AC-07 | WHEN the HTML renders THEN a section id scope-cost carries a caption stating the two time rules and the remediation rule plus one row per scope in array order reproducing that run's JSON values with n/a for nulls | done | TEST-037 | — | expectations are read out of the JSON of the same run, never restated (S3) |
| Spec-AC-08 | WHEN the sparse fixture is rendered THEN the outputs minus the new key and the new section stay byte-identical to the committed goldens which are not regenerated, the new key is present all-null, and the factory metrics overview and close-work-item suites all exit 0 | done | TEST-026, TEST-038 | — | extends the existing TEST-026 pin in place, the CHANGE-0142 precedent; mutation pair captured (busy_seconds+1 fails naming the byte diff, revert passes) |
| Spec-AC-09 | WHEN the product doc is read THEN it names the section the two time labels the marker-only denominator rule the named no-marker line and the remediation-not-failure rule, and the intake capability reads factory-performance-report | done | TEST-039 | — | the intake capability aai-factory-report resolves to a product doc that does not exist |

## Implementation plan

Components:

- `.aai/scripts/generate-factory-report.mjs` (EDIT — the whole substance):
  - `buildModel`, inside the existing `for (const m of rides)` loop and its
    inner `for (const r of m.agent_runs ?? [])` loop: alongside the existing
    `busy` / `tok` / `roleConsumption` accumulation, collect per ride the
    minimum parseable `Date.parse(r.started_utc)`, the maximum parseable
    `Date.parse(r.ended_utc)`, a `Map` of `roleKey` to run count, the marked-run
    count, and the remediation run count and marked-remediation token sum. The
    values `busy`, `hasBusy`, `tok` and `roleKey` are already in scope — no
    second read and no second parse (D9).
  - Extend the object pushed into `perRide` with those fields rather than
    building a parallel array, so the two cannot fall out of sync.
  - After the loop, project `perRide` into the top-level `scope_cost` block:
    map to the output shape, apply the D10 sort, and push the D1 divergence
    note and any D6 disagreement notes into `notes`. Reuse the existing `median`
    helper only if a median is wanted; none is required by the AC set.
  - `renderHtml`: one new `<section id="scope-cost">` between the Role
    consumption section and the Quality section, emitted as one contiguous
    string starting `<section id="scope-cost">` and ending `</section>` plus one
    blank line, so the Spec-AC-08 excision restores the prior bytes exactly.
    Reuse `esc`, `na` and `fmtDur` (`fmtDur` already renders 52405 as `14.6h`).
  - The empty-ledger render path (`m.empty`) returns before any section is
    emitted and stays untouched.
- `tests/skills/test-aai-factory-report.sh` (EDIT): eight new functions
  registered in `main()` as TEST-031 through TEST-037 and TEST-039, following
  the file's conventions (`mk_repo`, `run_report`, `node_get`,
  `log_pass`/`log_fail`, bash 3.2, scratch temp-dir repos only), plus two added
  lines inside the existing `test_026_role_consumption_backcompat`: `scope_cost`
  in the deleted-keys list and `<section id="scope-cost">` in the excised-tags
  list. TEST-038 adds no function — it is the whole-suite plus sibling-suite
  regression row. Numbering continues past the highest id already used by this
  suite's specs (030); 015 and 016 stay unused, as they are today.
- `docs/product/factory-performance-report.md` (EDIT): the Spec-AC-09 pins,
  `delivered_by` and `updated`.
- `docs/issues/CHANGE-0148-ride-cost-readout.md` (EDIT): one frontmatter line,
  `capability: factory-performance-report`.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading carrying this
  change's entry (per-entry heading form, never bullets under a bare scaffold).

Data flows:

- `METRICS.jsonl` line -> ride -> `agent_runs[]` -> (`Date.parse(started_utc)`,
  `Date.parse(ended_utc)`, `duration_seconds`, `normalizeRole(role)`,
  `extractUsageTotal(note)`) -> per-ride accumulator -> `perRide` entry ->
  `scope_cost.scopes[]` -> the new HTML section. `EVENTS.jsonl`,
  `docs/releases/` and `decisions.jsonl` are NOT read by this block.

Edge cases:

- A ride with zero `agent_runs` (2 exist in the live ledger) gets a row with
  `runs_total` 0, `elapsed_wall_seconds` and `agent_seconds` `null`, an empty
  `roles` array and the named no-marker line.
- A single-run ride: elapsed equals that run's own span, which is correct and
  not a special case.
- An unparseable or absent `started_utc` or `ended_utc` on SOME runs: the ride's
  span uses the parseable ones only, matching how the existing `earliestStart`
  map already treats them.
- A run missing `duration_seconds` (4 of 541 today): excluded from
  `agent_seconds`, which is then a partial sum; `notes` names the count.
- `elapsed_wall_seconds` must never be negative — a max end earlier than the
  min start means unusable timestamps and yields `null`, mirroring the existing
  lead-time guard.
- Two rides could share a `ref_id`; none do today (124 rows, 124 distinct
  refs). Each METRICS line is one row, so a duplicate would appear twice with
  the `ref` tiebreak keeping the order deterministic. Not special-cased.
- `remediation_share_pct` needs a guard for a `null` or zero `tokens_total` —
  `null`, never a division result.

## Seams

- S1 — the new block and the existing `speed.per_ride` / `speed.role_split` /
  `cost.capture_coverage` aggregations. Four code paths now count the same runs
  and sum the same markers. A per-scope rule that drifts from `extractUsageTotal`
  or from `normalizeRole` shows up only here. Crossed by TEST-031's real-ledger
  arm (`agent_seconds` versus `totals.agent_duration_seconds` for all 124 rides)
  and by TEST-033's totals, both re-summed from the same run's own output
  rather than from hand-written expectations. No mock exists on this path.
- S2 — the new block and `reliability.remediation_runs`, written by
  `metrics-flush.mjs` and consumed by the existing quality section. Two
  derivations of one quantity from two sources is the classic silent-drift
  shape. Crossed by Spec-AC-05's disagreement note, asserted in both directions
  by TEST-035 (a rigged disagreement produces the note; an absent block produces
  none).
- S3 — `factory-report-data.json` and `factory-report.html`. One model, two
  renderings; a formatter that turns a `null` into `0` in the HTML while the
  JSON stays honest is the classic failure. Crossed by TEST-037, which reads
  expectations out of the JSON produced by the same run.
- S4 — the generator and `close-work-item.mjs`, which regenerates the report
  best-effort at every close. Already crossed by the existing TEST-013 negative
  control (a rigged generator failure must leave the close exit code and the doc
  status unchanged); re-run unchanged under Spec-AC-08 rather than duplicated.
- S5 — the goldens and future legitimate edits to existing fields. A
  maintenance seam, not a runtime one: TEST-026 will fail on any later change to
  a pre-existing field, and the correct response is a deliberate golden refresh
  recorded in that change, never a silent regeneration. Written down so the
  failure reads as a signal.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-031 | Spec-AC-01 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_031_scope_cost_elapsed_and_agent_time` — idle-gap ride, overlapping-run ride, no-timestamp ride and no-run ride give the hand-computed elapsed and agent values with nulls not zeros, order is elapsed descending with nulls last and ref tiebreak, the divergence note names the overlap count, a real-ledger arm asserts agent_seconds equals totals.agent_duration_seconds for every ride, and a real-ledger shadow-model arm independently re-derives every scope_cost field (roles, tokens_total, runs_marked, date_utc, remediation_runs/tokens/share_pct), the full sort order and the scope_cost note set straight from METRICS.jsonl and diffs them against the generator's own output | green |
| TEST-032 | Spec-AC-02 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_032_scope_cost_role_counts` — roles array covers exactly the roles that ran in CANONICAL_ROLES order with Other last, a recognised variant string normalizes, an unrecognised one buckets to Other, counts sum to runs_total, and a ride with no agent_runs key yields an empty array | green |
| TEST-033 | Spec-AC-03 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_033_scope_cost_token_source` — hand-computed totals over a valid marker plus a malformed marker plus a prefixed key plus a bare note, unmarked runs contribute nothing not zero, and the generator source carries no capturing regex for the marker grammar while importing lib/usage-note.mjs exactly once | green |
| TEST-034 | Spec-AC-04 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_034_scope_cost_partial_and_no_data` — fully marked, partially marked and unmarked rides give the expected JSON nulls, every rendered token cell carries the runs_marked of runs_total fraction, and the unmarked ride renders the literal no-usage-marker line | green |
| TEST-035 | Spec-AC-05 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_035_scope_cost_rework` — hand-computed remediation runs tokens and share, a Remediation variant string counted, unmarked remediation runs giving a count with null tokens and null share, a rigged reliability disagreement emitting the named note, and an absent reliability block emitting none | green |
| TEST-036 | Spec-AC-06 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_036_scope_cost_report_only` — absent, empty, comment-only, one-malformed-line and real ledgers each exit 0, the generator source carries no non-zero process.exit, and neither output carries a dollar amount | green |
| TEST-037 | Spec-AC-07 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_037_scope_cost_html_parity` — section id scope-cost exists with the caption sentences and one row per scope in array order, and every rendered value is read out of the same run's factory-report-data.json with n/a literals for the nulls | green |
| TEST-026 | Spec-AC-08 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_026_role_consumption_backcompat` — extended in place so the sparse fixture outputs minus scope_cost and minus the scope-cost section stay byte-identical to the unchanged committed goldens, and scope_cost is present all-null | green |
| TEST-038 | Spec-AC-08 | int  | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh` then `bash tests/skills/test-aai-metrics.sh` then `bash tests/skills/test-aai-overview.sh` then `bash tests/skills/test-aai-close-work-item.sh` — the whole suite exits 0 with zero FAIL lines and still runs TEST-001 through TEST-029, and the three sibling consumers of lib/usage-note.mjs each exit 0 | green |
| TEST-039 | Spec-AC-09 | unit | tests/skills/test-aai-factory-report.sh | run `bash tests/skills/test-aai-factory-report.sh test_039_scope_cost_product_doc_pins` — the product doc carries the section heading, both time labels, the marker-only denominator rule, the named no-marker rule and the remediation-not-failure rule, frontmatter delivered_by and updated are bumped, and the intake capability reads factory-performance-report | green |

Failing-first discipline (strategy `direct`, so exit codes are the record, not a
stored artifact). TEST-031 through TEST-037 and TEST-039 all assert on
`scope_cost`, which does not exist on the pre-change tree, so each one fails
naturally before the generator is edited. Run each of the eight on the
unmodified tree FIRST, capture the non-zero exit code and the failing assertion
line, and record both in the Implementation return record's `evidence` list
next to the passing run. An arm that cannot be shown failing before the edit
must be reported as such rather than counted as proof.

The byte-stability half of TEST-026 cannot fail before the change — deleting an
absent key and excising an absent section are both no-ops. Its honest failing
observation is a MUTATION run after the generator is edited: perturb exactly one
pre-existing model field (for example round `cost.tokens_per_ride.mean` to an
integer), observe TEST-026 fail naming the byte difference, revert, observe it
pass. Record both exit codes. Without that pair the pin is unproven and must not
be counted.

TEST-038 is a regression row: a green run is the evidence.

## Verification

Commands:
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-overview.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh`
- `node .aai/scripts/generate-factory-report.mjs` over this repository, then
  read the `deslop-scope-and-unrequested-engine` and `role-verification-guards`
  rows: elapsed 25.0h and 14.6h, agent time 17.7h and 11.1h, 18 and 13 runs, 8
  and 4 remediation runs
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs`
- `git diff --name-only main...HEAD`

Evidence artifacts: suite stdout with per-TEST pass lines, the failing-first
exit codes recorded in the Implementation return record, the unchanged golden
files, the regenerated `docs/ai/factory-report.html` and
`docs/ai/factory-report-data.json`, and the scope diff listing.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or review verdict, evidence path, commit SHA or diff range.

### Evidence by strategy

Strategy is `direct`: what this spec demands is the targeted regression arms
green with their exit codes, the failing-first exit codes named above recorded
in the return record, and the scoped diff. No stored per-test artifact and no
verification matrix beyond the seven commands listed under Verification.

## Residual risks

- R1 — The elapsed span is bounded by the runs the orchestrator remembered to
  record. A ride whose Planning run was never flushed starts the clock at
  Implementation, and the section cannot know that. The mitigation is that
  `runs_total` and the per-role counts sit in the same row, so a ride with no
  Planning run is visibly odd; the fix belongs to the capture path, not the
  report. Accepted, not tested.
- R2 — The remediation share understates rework by construction (D6): the
  validation or review round that produced the finding is not counted, and a
  re-run Implementation after a finding is bucketed as Implementation. The
  section says so in its caption. Making it exact needs a per-run outcome field
  the schema does not have; that is a separate scope. Accepted.
- R3 — A partial token sum stays a partial sum (D4). The denominator is
  mandatory and adjacent, but a reader who ignores it can still compare a fully
  measured ride against a half-measured one as if both were totals. No code can
  prevent that; capture coverage has been complete since 2026-08-02, so the
  exposure shrinks with every new ride. Accepted.
- R4 — The table grows one row per ride forever (124 today). At a few hundred
  rows the section stays usable inside its scroll container; at a few thousand
  the page weight becomes a real cost. No pagination ships now (YAGNI); the
  trigger to revisit is a report HTML above roughly 1 MB. Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
A duration-based remediation share is deliberately NOT shipped (D8); it is a
different measure, materially different in value, and belongs to a later scope
if it is ever wanted.
