---
id: telemetry-completeness
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — Telemetry completeness: close the capture gaps behind the factory-performance report

## Summary

The owner's factory-performance report (CHANGE-0098) is honest but half-blind:
it renders `n/a` where data is missing and never imputes, but the economics view
rests on incomplete ledgers. Quantified from the live `docs/ai/METRICS.jsonl`
(104 rides / 411 agent runs, 2026-06-30..2026-07-28):

- **usage marker** (`usage_total_tokens=<N>`): missing on **221/411 runs
  (53.8%)**; present on 190. Ride-level, **46/104 rides (44%)** carry zero
  marked runs; only 33 are fully marked.
- **tokens_in / tokens_out**: **null on ALL 411 runs (100%)** — no decomposed
  in/out split has ever been recorded.
- **reliability block** (first-pass rate, fail/remediation counts): missing on
  **26/104 rides (25%)**.
- **prompt_hash**: **absent on all 411 runs and all 104 rides (0% coverage)**.
- **USD cost**: unattributable by design (no in/out split to price honestly).

This change closes the *ongoing* leaks with a deterministic gate (the factory
lesson: prose "MUST" reminders don't fire; gates do) and makes the remaining
`n/a` explicit and trended, while being honest that historical values are gone.

## Motivation / Business Value

- The report answers "at what token cost" from markers that are absent more than
  half the time. The gap is not random: it is a *produce-side* leak the current
  chain only detects *after the fact*, when the number is already gone.
- The single enforcement lesson of this factory (product_doc_gate,
  doc_number_guard, close-time ceremonies) is that a **deterministic gate** at a
  transition boundary is the only thing that reliably changes orchestrator
  behavior. The usage marker is currently guarded only by prose in
  `SUBAGENT_PROTOCOL.md` / `SKILL_LOOP.prompt.md` — and the weekly coverage
  trend proves prose is insufficient.
- Making the coverage a first-class, trended KPI (not a footnote) lets the owner
  see the data quality *improve* as the gate takes hold, and see honestly how
  much of the economics view is still `n/a`.

## Gap census

Source: `docs/ai/METRICS.jsonl`, 104 rides / 411 runs, 2026-06-30..2026-07-28.

Gap class — coverage — clustering — root cause:

- **usage marker missing** — 221/411 runs (53.8%); 46/104 rides fully unmarked —
  clusters by DATE (see week trend) and by ROLE (Implementation 37/42 = 88%
  missing, Remediation 21/26 = 81%, Planning 47/84 = 56%, Validation 45/93 =
  48%, Code Review 44/98 = 45%, TDD Implementation 20/61 = 33%) — **two root
  causes**: (1) pre-feature history (the marker convention did not exist before
  ~W29); (2) ongoing orchestrator omission at merge/append-run time — the note
  is prose-MANDATORY but has no runtime teeth, so it is silently skipped even
  now.
- **reliability block missing** — 26/104 rides (25%) — clusters **entirely** at
  or before 2026-07-16 (every one of the 26 is pre-feature; the first ride with
  reliability is CHANGE-0027, 2026-07-16) — **root cause: pure pre-feature
  history.** `reliabilityOf()` is now computed *unconditionally* on every flush
  (`metrics-flush.mjs:493`), so every ride flushed since carries it. NOT an
  ongoing leak — backfill-only.
- **prompt_hash missing** — 0/411 runs (0%) — **root cause: never produced.**
  SPEC-0098 wired the orchestrator *instruction* (`--prompt-hash` pass-through)
  but its own residual risk records there is no runtime enforcement and no loop
  run since has emitted a value; flush passes it through only when append-run
  recorded it (`metrics-flush.mjs:470`). All 104 rides predate the wiring.
- **tokens_in / tokens_out null** — 411/411 (100%) — **root cause: the surface
  the factory actually uses (the in-session Agent-tool completion) exposes only
  an undecomposed total** (see In/out verdict). Not an omission.

Weekly marker coverage (marked runs / total runs) — the trend that proves prose
alone is insufficient:

- 2026-W27: 0/46 (0%)
- 2026-W28: 0/6 (0%)
- 2026-W29: 88/175 (50%)
- 2026-W30: 48/112 (43%)
- 2026-W31: 54/72 (75%)

Coverage climbs after the convention lands (~W29) but plateaus around 75% — a
quarter of the most recent week's runs still drop the marker under prose-only
"MANDATORY". That residual is exactly what a gate removes.

## Affected Area

- `.aai/scripts/close-work-item.mjs` — new close-time usage-capture gate
  (reuses the existing STATE `agent_runs` scanner and the guard-config dial
  pattern; additive, evaluated before any write).
- `.aai/scripts/lib/guard-config.mjs` — one new dial name in `GUARD_DIALS`
  (`usage_capture_gate`), fail-open to report-only.
- `docs/ai/docs-audit.yaml` — ship the new dial `report-only` (documented).
- `.aai/scripts/generate-factory-report.mjs` — promote the no-marker footnote to
  a first-class run-level capture-coverage KPI (overall + per-week series).
- Tests: a new/extended suite asserting the gate at both dials + a negative
  control; a factory-report assertion for the coverage KPI.
- Unchanged by design: `.aai/scripts/state.mjs` (L3-protected — see Enforcement
  design, alternative b), `.aai/scripts/metrics-flush.mjs` classification
  (stays warn-never-block — alternative c), `lib/usage-note.mjs` (imported, not
  forked).

## Leak analysis of the capture chain

Where the chain can capture usage, and where it leaks TODAY:

1. **Merge / `append-run` (produce side, `state.mjs`).** The
   `usage_total_tokens=<N>` note is prose-MANDATORY at merge (SUBAGENT_PROTOCOL
   "Merge protocol" step 3) and in SKILL_LOOP step 4, but append-run accepts a
   run with no note silently. Its one warning (`state.mjs:831`) fires whenever
   `tokens_in/out` are undefined — which is the *normal* undecomposed path — so
   it **cannot distinguish an honest undecomposed total from a silently dropped
   one.** Non-discriminating → ignorable noise. **PRIMARY LEAK.**

2. **Flush classification (`metrics-flush.mjs:446-459`).** The SPEC-0085 3-way
   classifier (`decomposed` / `undecomposed-note` / `capture-missing`) is
   correct and discriminating — but it fires at **flush time, after the run is
   already recorded**. The harness task-notification total is ephemeral; by
   flush the number is gone. Post-mortem, not preventive.

3. **Flush WARNING surfacing.** The `capture-missing` WARNING is printed to
   flush stdout (`metrics-flush.mjs:954`) and METRICS_FLUSH.prompt.md step 2
   tells the operator to relay it verbatim. **But flush is loop-final /
   operator-initiated and is NOT wired into close.** In the autonomous loop the
   WARNING lands in flush stdout that no human necessarily reads — the canary
   chirps into an empty room. It is "loud" only in an interactive manual flush.

4. **No per-ride close checkpoint.** `close-work-item.mjs` runs while the ride's
   `agent_runs` are STILL in `STATE.yaml` — it already parses them
   (`countRemediationRuns`, `close-work-item.mjs:588-621`) — i.e. the one
   deterministic per-ride checkpoint that fires *before* flush, with the runs in
   hand, and it does not inspect them for the marker today. **This is the empty
   seat the gate fills.**

## Enforcement design

**Recommended: a close-time usage-capture gate + a first-class coverage KPI.**

**(A) Close-time gate in `close-work-item.mjs`, dialed like `product_doc_gate`.**
Add a `usage_capture_gate` dial to `guard-config.mjs` (`enforce` |
`report-only`, absent/invalid → report-only, fail-open — identical grammar and
default to the existing dials). At close: parse the closing ref's `agent_runs`
from `STATE.yaml` (reuse the `countRemediationRuns` line scanner), and for each
run of a **known harness-dispatched role** (Planning, Implementation, TDD
Implementation, Validation, Code Review, Remediation) that has **neither**
decomposed `tokens_in/out` **nor** a valid `usage_total_tokens` marker (via
`lib/usage-note.mjs` `extractUsageTotal` — single grammar source), emit a
WARNING on stderr (report-only) or REFUSE before any write (enforce, mirroring
the product-doc refuse branch at `close-work-item.mjs:801`).

Why close, not elsewhere:
- It is the **per-ride deterministic transition** — exactly where the factory's
  other gates live and the only place a refusal is safe (a doc-status flip can
  be refused; a state-integrity move cannot).
- It fires **before flush, with `agent_runs` still in STATE** — the last moment
  the omission is fixable by re-recording, not a post-mortem.
- It **already reads STATE `agent_runs`** and **already owns a fail-open dial
  pattern** — the change is additive and small, no L3 surface touched.

**(B) Coverage KPI in the factory-report.** Promote the existing no-marker
footnote (`generate-factory-report.mjs:418-419`) to a first-class **run-level
capture-coverage** metric (`runs_with_marker / total_runs`) with an overall
value and a per-week series, rendered alongside the reliability n/a treatment.
The owner then *sees* the gap and its trend, not just a caveat.

### Rejected alternatives (and why)

- **(b) `state.mjs` append-run note-grammar enforcement — REJECTED.**
  `state.mjs` is L3-protected (`docs-audit.yaml protected_paths_l3`) → the
  heaviest change cost in the repo (ceremony_level 3, worktree, full RED-GREEN),
  and append-run is produce-time per-run with **no ride-close context**, so it
  cannot know whether a given role is *expected* to carry a marker. A warn-only
  change there merely duplicates the flush classifier without adding teeth. Poor
  ROI vs. the close gate. (The existing append-run warning stays as-is.)

- **(c) `metrics-flush` blocking on `capture-missing` — REJECTED (re-examined).**
  SPEC-0085 deliberately chose warn-never-block for flush (Constitution Art 4
  "degrade and report"). Flush is a `STATE → ledger` integrity operation:
  blocking it would **strand completed work in STATE** and wedge the loop just
  because a token note is missing. That decision still holds. The refusable
  boundary is *close* (a doc transition), not *flush* (a state move). Keep flush
  warn-only; fix the *surfacing* by moving the signal to the close gate.

- **(d) Backfill of historical values — REJECTED as unrecoverable.** The 221
  unmarked runs' undecomposed totals and the 26 pre-feature rides' reliability
  blocks came from harness task-notifications that are ephemeral and gone.
  `reconcile-telemetry.mjs` only carries stranded *committed* ledger lines
  between worktrees — it cannot reconstruct values that were never recorded.
  **History stays `n/a`.**

## In/out decomposition verdict

**Genuinely unavailable on the surface the factory actually uses; KEEP the
fields; close only the backfill door.**

- The in-session **Agent-tool completion notification exposes only an
  undecomposed total** (SUBAGENT_PROTOCOL "Undecomposed total" branch,
  lines 120-130). Per-call in/out cannot be recovered from it — by design, and
  splitting a total would fabricate a component claim and poison `cost_usd`.
- It **is** obtainable from other surfaces the protocol already names: a headless
  `claude -p --output-format json` result exposes
  `usage.input_tokens`/`usage.output_tokens` (the "decomposed" branch); OTLP
  telemetry (if enabled) and `~/.claude` transcripts also carry the split. The
  flush classifier already treats `decomposed` as first-class (numeric in AND
  out → priced via `pricing.mjs`, no warning).
- **Therefore: retain `tokens_in`/`tokens_out`.** Cost of keeping = two null
  fields per run (negligible); benefit = the capture path stays open for any run
  dispatched via a decomposing surface, and the classifier's `decomposed` arm
  depends on them. Dropping them would foreclose honest USD forever. The only
  door to close explicitly is **backfilling in/out for history** (impossible).
  USD stays unattributable by design as long as the dominant dispatch surface is
  the undecomposed in-session Agent tool — the report should say so, not carry
  dead expectation.

## Reliability block coverage

Written unconditionally by `metrics-flush.mjs` `reliabilityOf()` (line 493)
since the SPEC-0032 truth-scoring feature (~2026-07-16). All 26 missing rides
(25%) are **100% pre-feature**; every ride flushed since carries it. **No
ongoing leak — already solved forward.** The close gate does NOT fix it "for
free" and does not need to: reliability is a flush-derived block, not an
append-run field, so a close gate can neither add it nor is it missing going
forward. The only residual is backfill of the 26 historical rides, which is a
non-goal (their fail/remediation history was not recorded parseably). The close
gate's value is the **marker**, not reliability.

## Desired Behavior (To-Be)

- A close on a ride whose STATE `agent_runs` include a harness-dispatched-role
  run with no marker and no decomposed tokens triggers the usage-capture gate at
  the configured dial: WARNING (report-only, shipped default) or REFUSE before
  any write (enforce, opt-in).
- The factory-report shows run-level capture coverage as a headline KPI with a
  per-week trend; historical `n/a` stays explicit, never zero, never imputed.
- No change strands work: flush stays non-blocking; report-only is the default
  so no legitimate close is blocked until an operator opts in.

## Acceptance Criteria

- AC-001: Closing a ride whose STATE `agent_runs` include a harness-dispatched
  role run with neither decomposed `tokens_in/out` nor a valid
  `usage_total_tokens` marker triggers the `usage_capture_gate`: a stderr
  WARNING naming ref/role under `report-only`, and a REFUSAL before any write
  (non-zero exit, no state mutation) under `enforce`. Absent/invalid dial →
  report-only (fail-open), mirroring `product_doc_gate`.
- AC-002: The gate reads the marker via `lib/usage-note.mjs extractUsageTotal`
  (single grammar source, no re-declared regex) and reuses the existing STATE
  `agent_runs` scanner. A run carrying a valid marker OR decomposed
  `tokens_in`+`tokens_out` never trips the gate (explicit non-tautology negative
  control).
- AC-003: `--dry-run` never acts on the gate (no refusal, no write), matching the
  product-doc-gate discipline.
- AC-004: The factory-report emits a first-class `capture_coverage` metric
  (`runs_with_marker / total_runs`) with an overall value AND a per-week series;
  the existing no-marker NOTE is preserved; coverage is shown as an explicit
  percentage, never a fabricated zero.
- AC-005: Non-goals are honored mechanically: no historical marker/reliability
  backfill is performed; `tokens_in`/`tokens_out` fields remain in the schema;
  `metrics-flush` remains non-blocking (flush of a capture-missing ride still
  exits 0 with the WARNING).
- AC-006: `docs/ai/docs-audit.yaml` ships `usage_capture_gate: report-only` with
  a documenting comment; `guard-config.mjs` lists it in `GUARD_DIALS` and
  fail-opens an invalid value to report-only WITH a stderr notice.

## Verification

- New/extended suite (e.g. `tests/skills/test-aai-usage-capture-gate.sh`):
  close a fixture ride with an unmarked harness-dispatched run → assert WARNING
  (report-only) and REFUSE+no-write (enforce); negative control (marked run and
  decomposed-tokens run) → assert clean close. Assert `--dry-run` no-op.
- `bash tests/skills/test-aai-factory-report.sh` — assert the `capture_coverage`
  KPI (overall + per-week) present and matching an independent re-sum; HTML
  matches JSON field-for-field (existing AC-006 discipline).
- `bash tests/skills/test-aai-hygiene-pack.sh` — guard-config drift conformance
  (the shell greps and `guard-config.mjs` agree on the new dial).
- `node .aai/scripts/docs-audit.mjs --check` exit 0.

## Constraints / Risks

- **The gate cannot distinguish "orchestrator forgot the marker" from "the
  harness genuinely exposed no usage" — both look like a missing marker.** So
  `enforce` needs a conservative escape hatch: gate only KNOWN
  harness-dispatched roles, and let a genuinely usage-less run pass with an
  explicit sentinel note (e.g. a documented `usage_total_tokens` absence marker
  such as `usage_capture=none`). The shipped `report-only` default sidesteps
  this entirely (warn only); the escape hatch matters only when an operator
  dials to `enforce`. This limitation MUST be documented at the dial.
- Role-classification list drift: the "harness-dispatched roles" set must track
  the canonical role vocabulary (share it with `normalizeRole` in the report /
  the flush classifier) so a new role variant is not silently un-gated.
- History stays `n/a` — the report must keep rendering explicit `n/a`, never a
  zero, for pre-feature rides and unmarked runs.
- Secrets preflight: no secret referenced by this change.

## Notes

- Companion governance (to resolve at planning, per PLANNING step 3a): this
  scope adds no new `.aai/**` prompt-corpus file and edits no `.aai/*.prompt.md`
  in the diet glob, so neither the PROFILES classification nor the prompt-diet
  ledger true-up is triggered; a new test suite needs a `suite-map.yaml` row.
- Sequencing note: the prompt_hash 0% coverage is a *separate* known gap owned
  by SPEC-0098's residual risk (instruction wired, no runtime enforcement, no
  loop run since). It is called out here for completeness but is out of scope —
  the same close-gate pattern could later cover it if the owner wants
  prompt_hash treated as mandatory telemetry.
