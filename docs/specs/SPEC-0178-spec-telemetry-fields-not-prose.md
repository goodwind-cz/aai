---
id: spec-telemetry-fields-not-prose
type: spec
number: 178
status: done
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0183-telemetry-fields-not-prose.md
  rfc: null
  pr:
    - TBD
  commits:
    - 6105b291
---

# Spec — run telemetry is recorded as fields, and every derived number says which basis produced it

SPEC-FROZEN: true

## Amendment (post-freeze, 2026-09-13 — validation round-2 BLOCKING-1)

This is a FROZEN spec, amended after the freeze and disclosed here rather than
rewritten silently, per the additive-with-disclosure convention already used
by `docs/specs/SPEC-0153-...md` (`## Amendment`), `docs/specs/SPEC-0132-...md`
and `docs/specs/SPEC-0072-...md`.

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`, ts
`2026-09-13T09:31:08Z`, `ref_id: telemetry-fields-not-prose`, tracked by
`fu-amend-spec-telemetry-fields-not-prose` (owner sign-off owed).

That record's `what` field claimed three spec edits — seam S5 redrawn as
record -> triage -> upsert; `aai-feedback-triage.mjs` and its suite joining
`## Scope` and "Components affected" — that had NOT actually been made; the
record described work that was intended but never landed in the spec text.
Validation round 2 measured this directly (`grep -c aai-feedback-triage
<spec>` = 0 against the frozen text) and blocked on it: a false "done" in the
owner-facing disclosure ledger for a post-freeze widening is exactly the class
of defect this ride's own thesis exists to catch. The `decisions.jsonl` record
itself is append-only and is not rewritten; instead the spec is now made to
match what it already claimed, closing the gap named in BLOCKING-1:

- `## Scope` now names `aai-feedback-triage.mjs`'s `ALLOWED_KEYS` gate and
  `safeHarness()` sanitizer, and counts seven suites instead of six.
- "Components affected" (Implementation plan) now lists
  `.aai/scripts/aai-feedback-triage.mjs` (the `ALLOWED_KEYS`/`safeHarness()`
  change) and `tests/skills/test-aai-feedback-triage.sh` (TEST-011, TEST-014)
  with what changed in each.
- Seam S5 is redrawn as `aai-friction.mjs record` -> `aai-feedback-triage.mjs`
  (gate + sanitize) -> `aai-feedback-upsert.mjs` renders, naming TEST-113,
  TEST-014 and TEST-064.

These three edits landed in this remediation round, after validation round 2
found the amendment record ahead of the spec text it described. The owner may
still accept or reverse the underlying post-freeze widening itself (the P2
follow-up above remains open for that decision); this addendum only makes the
spec text match the claim already on the ledger.

## Links
- Requirement: docs/issues/CHANGE-0183-telemetry-fields-not-prose.md
- Roadmap: docs/project-sessions/2026-09-12-wave-2-roadmap.md (wave 2, pair 1, maintenance half)
- Paired capability half (merged): docs/specs/SPEC-0177-spec-harness-universal-routing.md
- Truth-scoring origin: docs/specs/SPEC-0032-spec-truth-scoring.md
- Flush sweep origin: docs/specs/SPEC-0068-spec-metrics-flush-sweep.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake by the user (CHANGE-0183 `## Notes`, `Implementation mode (user choice): tdd`). Planning keeps the recorded choice. It is also the right one on the evidence: every AC in this scope is a DERIVATION that can silently produce a flattering number, and the day this ride was filed produced exactly such numbers (see `## What is established before this scope starts`). A green run over a derivation that was never observed failing proves nothing about the derivation.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope edits `.aai/scripts/state.mjs`, which is a `protected_paths_l3` surface AND the script the orchestration loop executes on every tick to mutate STATE. A half-applied edit inline does not merely fail a test, it breaks the loop that is driving the ride. The checkout is additionally shared between sessions (P1 scar, 2026-09-06). `required` is the correct level here because a protected surface is touched, which is the same fact that sets ceremony level 3.
- User decision: worktree
- Base ref: main (branch `fix/telemetry-fields-not-prose`, off 02455b73)
- Worktree branch/path: to be created by Implementation Preparation
- Inline review scope: `.aai/scripts/state.mjs .aai/scripts/metrics-flush.mjs .aai/scripts/lib/usage-note.mjs .aai/scripts/lib/pricing.mjs .aai/scripts/check-committed-scope.mjs .aai/scripts/aai-friction.mjs .aai/scripts/aai-feedback-upsert.mjs .aai/scripts/generate-factory-report.mjs .aai/scripts/metrics-report.mjs .aai/system/PRICING.yaml .aai/SUBAGENT_PROTOCOL.md docs/ai/STATE.yaml tests/skills/test-aai-state.sh tests/skills/test-aai-metrics.sh tests/skills/test-aai-friction.sh tests/skills/test-aai-feedback-upsert.sh tests/skills/test-aai-factory-report.sh tests/skills/test-aai-learned-routing.sh`

## Registry items closed by this scope

`node .aai/scripts/follow-ups.mjs list --status open --json` was read in full at
freeze (172 open items). Eleven touch this scope's subjects. Three are CLOSED by
this scope, eight are explicitly NOT closed with the reason.

CLOSED FULLY:

- `fu-reliability-marker-is-freetext` (P2) — closed by Spec-AC-03 and Spec-AC-04. The marker stops being the only source: a Validation or Code Review run cannot be appended without a verdict field, and the flush derives from the field with the note as a labelled fallback.
- `fu-flush-window-closes-on-verdict-reset` (P2) — closed by Spec-AC-06 and Spec-AC-07. The default gate stops asking the single global block alone.
- `fu-flush-nulls-review-scope-before-pr` (P2) — closed by Spec-AC-09. The partial reset keeps the scope and names whose it is.

NOT CLOSED, with the reason:

- `fu-usage-marker-omission-unfixable` (P2) — it is about a run ALREADY appended without a usage marker and about the absence of any correction path for it. This scope makes future appends structured; it adds no correction path, because the ledger is append-only and `close-work-item.mjs` (which owns the usage gate and its dial) is out of scope.
- `fu-metrics-verdict-has-no-staleness` (P2) — asks the ledger to say whether a PASS covers the final bytes. Spec-AC-06 makes the tree-hash-bearing `validation_verdict` event reachable from the flush for the first time, which is the enabler, but this scope compares no hashes and writes no staleness field. Naming it as closed would be a false claim.
- `fu-sweep-ledger-verdict-typed-pass` (P3) — asks for the entry-level `verdict` literal to be RE-TYPED for sweep-gated lines. This scope adds `verdict_basis` at entry level so a swept line is machine-distinguishable from a validated one for the first time, but leaves `verdict: PASS` alone, because every consumer (factory report, metrics report, docs-audit) branches on that literal and re-typing it is a ledger-schema break that belongs to its own scope.
- `fu-flush-vacates-code-review-gate` (P2) — about the partial reset setting `code_review.required` to false. Spec-AC-09 deliberately changes `scope`, `base_ref` and `head_ref` only. Flipping `required` changes what the PR gate ENFORCES, not what telemetry RECORDS, and belongs with the gate.
- `fu-metrics-flush-advises-git-restore` (P3) — a warning string at `metrics-flush.mjs:801-803` telling an agent to `git restore` an append-only ledger. This scope edits that file but not that arm; fixing an unrelated string inside an edited file is the unrequested-surface class this repo removes in deslop.
- `fu-usage-pin-misses-appended-flag` (P3) — about `spec-freeze.mjs`'s usage-line pin in another suite. Different surface entirely.
- `fu-amend-metrics-flush-invalidate-59abba` (P2) and `fu-amend-spec-harness-universal-routing` (P2) — both are owner sign-off owed on unsigned post-freeze spec amendments. They need an owner decision, not an implementation; no AC here can discharge them.

## What is established before this scope starts

Every number below was measured on 2026-09-13 against the shipping tree, under
bash with `/usr/bin/grep` (`grep` is aliased to ugrep in the authoring shell).
The measuring scripts read `docs/ai/METRICS.jsonl`, `docs/ai/STATE.yaml`,
`docs/ai/EVENTS.jsonl` and `docs/ai/LOOP_TICKS.jsonl` read-only.

1. **The ledger.** 138 lines, 135 of them work-item entries (3 are legacy
   `worktree_create` records with no `ref_id`). 628 recorded agent runs.
2. **Cost.** `totals.total_cost_usd` is null on 135 of 138 lines (measured shape:
   124 literal `null` + 11 key-absent + 3 lines with no `totals` block at all — 0
   of 138 carry a number). `cost_usd` is null on 628 of 628 runs. ZERO runs carry
   both `tokens_in` and `tokens_out`. `LOOP_TICKS.jsonl` is NOT VERIFIABLE HERE —
   the file does not exist in this worktree, so its "239 ticks, no in/out split"
   claim is unmeasured in this evidence pass and must not be read as confirmed.
   The `agent_runs` finding alone (zero of 628 carry both fields) is sufficient
   for the conclusion that follows: the repository has NO measured input/output
   ratio of its own — a fact D5 below turns into a design constraint rather than
   an invented constant.
3. **Cost recoverable from prose.** 400 of 628 runs (63.7%) carry a well-formed
   `usage_total_tokens=<N>` note marker. Today the flush reads that marker only
   to classify the run as undecomposed and print an INFO line; it derives no
   cost from it. Under the note-basis fallback this scope adds, those 400 runs
   become costable where 0 are today.
4. **Model.** `model_id` is `unknown` on 27 of 628 runs. 61 runs carry a
   `requested_model=` note marker.
5. **Reliability.** Stored aggregates across the ledger: `validation_fails` 2,
   `review_fails` 0, `remediation_runs` 69. Re-deriving today's rule
   (`/\bVERDICT:\s*FAIL\b/i`) over all 628 runs finds THREE runs carrying the
   exact marker — `RFC-0004` Code Review, `RFC-0005` Code Review,
   `harness-universal-routing` Validation — and FIVE more carrying
   `VERDICT FAIL` without the colon that the rule cannot see:
   `doctor-vendored-layer-drift` Code Review, `CHANGE-0027` Validation,
   `decapod-prune` Code Review, and `friction-publish-hides-required-followup`
   Validation twice. Those last two are the live 2026-09-12 incident the
   follow-up was filed from.
6. **What the report says on that basis.** `generate-factory-report.mjs` counts
   first-pass-clean over the 109 ledger lines that carry a `reliability` block:
   82 clean, rate **75.2%**, with 26 lines rendered n/a. That is the "76%" the
   intake names. 69 remediation runs against 2 recorded validation fails is the
   internal contradiction.
7. **What the same ledger would say under a FIELD basis.** Zero of 628 runs
   carry any of `harness`, `tokens_total`, `verdict`, `requested_model` or
   `actual_model`. So on today's ledger a field-first derivation yields
   `validation_fails` 0, `review_fails` 0 and `cost_usd` null everywhere, and
   every line would be labelled `basis: note` and none `basis: field`. This is
   the whole argument for the labelled fallback in D3: a field-first flush
   without it would silently zero a four-month ledger.
8. **The flush window.** `metrics.work_items` holds 29 refs; NONE of the 29 is
   in the ledger. All 29 carry a committed `work_item_closed` event.
   `node .aai/scripts/metrics-flush.mjs --state <copy> --dry-run --sweep` on a
   scratch copy of the live STATE flushes exactly FOUR
   (`reaper-test-018-etime-shape-guard`, `spec-vagueness-gate`,
   `agent-shell-can-write-the-shipping-repo`, `simple-and-friendly-to-use`) and
   skips 25 — 24 for `active_work_items status is "in_progress"` and 1
   (`mechanical-context-offload-to-cheap-tier`) for `no agent_runs`. The default
   gate flushes none of them, because `last_validation.status` is `not_run` with
   `ref_id: null` after the harness-universal-routing flush.
9. **Durable per-ref verdict evidence already exists.** `EVENTS.jsonl` holds 20
   `validation_verdict` records across 15 refs, each
   `{ref, payload:{status, hash}}`, stamped by `orchestration-dispatch.mjs`.
   `close-ceremony-fires-only-via-aai-pr` — the ref the P2 follow-up names as
   permanently stranded — carries two of them, both `pass`, the later at
   `2026-09-12T07:31:54Z`. That record is the per-ref provenance D6 reads.
10. **The run parser is already generic.** `metrics-flush.mjs`
    `parseMetricsEntries` reads any `^ {10}(\w+): <value>` line under a run into
    `run[key]`. New fields parse for free; only the numeric-coercion allowlist
    (`duration_seconds, tokens_in, tokens_out, cost_usd, tdd_tests`) needs
    `tokens_total` added.
11. **The prompt corpus does not include the file this scope edits.**
    `tests/skills/test-aai-prompt-diet.sh` TEST-010 measures `.aai/*.prompt.md`
    plus exactly three extras: `INTAKE_COMMON.md`, `STATE_FALLBACK.md`,
    `ROLE_COMMON.md`. `.aai/SUBAGENT_PROTOCOL.md` is in neither set (the same
    precedent the ledger records for `.aai/system/FRICTION_PROTOCOL.md`).
12. **Protected surface.** `.aai/scripts/state.mjs` is listed in
    `protected_paths_l3` in `docs/ai/docs-audit.yaml`. The three most recent
    rides that edited it shipped at L3 (`[L3]` in commits `6de640a9`,
    `4910e779`, `1c2f602f`).
13. **Friction records derive their environment, never accept it.**
    `aai-friction.mjs` builds the persisted record by copying only eight
    allowlisted v1 keys into a fresh object; `os_family`, `aai_pin` and
    `node_major` are DERIVED on the machine (`deriveOsFamily()` et al.), never
    read from input. `aai-feedback-upsert.mjs` renders them through
    closed-set/charset sanitizers (`safeOsFamily`, `safeInt`, `safePin`).

## Decisions

### D1 — Five structured fields on the run, and `note` keeps its job

`append-run` gains `--harness`, `--tokens-total`, `--verdict`,
`--requested-model` and `--actual-model`, each written as its own field on the
`agent_runs` entry. `note` stays free text and is never parsed by `append-run`.

Emission rule, which the flush's basis labelling depends on: `harness` and
`verdict` are ALWAYS emitted (both have defaults, see D2); `tokens_total`,
`requested_model` and `actual_model` are emitted ONLY when the flag was passed.
An absent key must stay distinguishable from a recorded absence — "the
orchestrator recorded no requested model" and "the orchestrator recorded that
none was requested" are different claims, and the second one is not one this
scope invents a spelling for.

Rejected: reusing the note grammar with stricter validation. The grammar is not
the defect; deriving a number from prose is. A validated marker still loses the
distinction between "no marker" and "no value", and still leaves the note as the
only home for five unrelated facts.

### D2 — Defaults, and the one flag whose absence is a refusal

- `--harness` omitted resolves to `detectHarness(process.env)` from
  `.aai/scripts/lib/harness.mjs` — the SAME function pair 1 shipped, imported,
  never re-derived. `state.mjs` runs as a child of the orchestrating session, so
  it inherits that session's harness environment, which is exactly the harness
  that produced the run.
- `--harness` given a value outside `HARNESS_VALUES` is a REFUSAL (exit 2,
  nothing written), not a degrade to `unknown`. `detectHarness` degrades an
  out-of-set `AAI_HARNESS` because an environment variable is ambient; a CLI
  flag is typed by the caller, and `state.mjs`'s standing rule is that a typoed
  flag fails loud rather than silently dropping data.
- `--verdict` accepts `pass | fail | none`. Omitted, it defaults to `none` for
  every role EXCEPT `Validation` and `Code Review`, where its absence is a
  refusal: exit 2, the message naming `--verdict`, and STATE byte-identical.

Why refuse rather than default those two roles to `none`: a Validation run that
records `none` is indistinguishable from one whose verdict was never captured,
which is precisely today's defect wearing a field's clothes. The refusal is the
only shape in which "no usable verdict signal" cannot be produced by omission.

Role matching is exact set membership over `{Validation, Code Review}`, not a
prefix normalizer, because `--role` is already an `enumFlag` over the closed
`ROLES` list, so no variant spelling can arrive. Consequence recorded as a
residual: a `Remediation` run still carries `verdict: none`, and
`remediation_runs` stays the structural witness it is today.

### D3 — Field first, note second, and the basis is written down

`metrics-flush.mjs` derives reliability, cost and model from FIELDS first. The
note-marker parse stays exactly as it is today, as a FALLBACK, and every derived
number carries the basis that produced it:

- per run: `verdict` (`pass|fail|none|null`), `verdict_basis`
  (`field|note|none`), `harness` (string or null), `tokens_total` (number or
  null), `cost_basis` (`decomposed|total-blended|none`).
- per entry: `reliability.basis` (`field|note|mixed|none`),
  `totals.cost_basis` (`decomposed|total-blended|mixed|none`), and
  `verdict_basis` naming which gate admitted the ref (D6).

Every one of those is an ADDITIVE key. No existing ledger line is read, rewritten
or migrated; the append-only ledger is only ever appended to. Measurement 7 above
is why the fallback is not optional: a field-first flush WITHOUT it would derive
zero fails and null costs from a 138-line history and present that as truth.

A run whose fail is known only from a note produces ONE NOTE line on stderr
naming the run and the basis — the same degrade-and-report discipline the
undecomposed-token classifier already uses.

### D4 — The reliability counters read the field, and `first_pass_clean` keeps all three witnesses

`validation_fails` and `review_fails` count runs whose `verdict` FIELD is `fail`;
a run with no verdict field falls back to the note marker. `remediation_runs`
stays structural (role contains "remediation") and `first_pass_clean` still
requires all three counts to be zero. The third witness is not removed just
because the first two got better: a fail cycle recorded before this scope, or by
a harness that omitted the flag, is still visible through the remediation count.

### D5 — Cost from a total is an estimate, and it says how wide it is

When a run has no `tokens_in`/`tokens_out` split but does have a token total
(from the `tokens_total` field, or failing that from the `usage_total_tokens=`
note marker), the flush computes

    cost_usd = total * (share * input_rate + (1 - share) * output_rate) / 1e6

and labels it `cost_basis: total-blended`. It additionally records
`cost_bounds_usd: [total * input_rate / 1e6, total * output_rate / 1e6]` — the
all-input and all-output extremes.

`share` is READ from a new `cost_blend.input_share` key in
`.aai/system/PRICING.yaml`, never hardcoded in the flush. Its shipped value is
`0.5`, declared in the file itself as a CONVENTION with `source_ref: null` and
the reason: measurement 2 above establishes that this repository has no recorded
in/out split anywhere, so 0.5 is the midpoint of the only interval that is known,
not an observation. The bounds field is what keeps that honest — a reader who
needs the true width has it on the line, and a reader who needs a different share
can re-derive from `tokens_total` and the bounds.

Rejected: pricing the whole total at the output rate. It is an honest ceiling but
it overstates by roughly 5x for every Claude model in PRICING, and a ceiling
printed in a `cost_usd` column is read as a cost.

Rejected: leaving `cost_usd` null and publishing only bounds. The intake asks for
a non-null figure and the factory report has had nothing to show for 138 rides;
a labelled estimate beside its own bounds is more useful and no less honest.

A run with both tokens keeps today's exact arithmetic and is labelled
`decomposed`. A run with neither keeps `cost_usd: null`, is labelled `none`, and
keeps today's WARNING line verbatim.

### D6 — The flush window closes at cause: per-ref verdict provenance

Today the default gate asks ONE question — does the single global
`last_validation` block say `pass` and name this ref. Two legitimate
`reset-block --force` calls, each taken to get an independent verdict on a later
scope, therefore close the window on an earlier merged ride permanently
(measurement 8: 29 stranded refs, 0 flushable by the default gate).

The gate's question becomes: does DURABLE, PER-REF evidence of a validation PASS
for this ref exist. It is answered from three sources, in this fixed order, and
the plan/skip line NAMES which one decided it:

1. `metrics.work_items[<ref>].validation.status === 'pass'` — the per-ref field
   D7 writes. Basis `per-ref-field`.
2. the global `last_validation` block saying `pass` and naming the ref —
   today's predicate, evaluated byte-unchanged. Basis `global-block`.
3. the LATEST `validation_verdict` event in `EVENTS.jsonl` whose `ref` matches,
   whose `payload.status` is `pass`, AND which is **corroborated** (below).
   Basis `event`.

All three feed `defaultOkRefs`, so an event-admitted ref IS archive-eligible —
correctly, because a `validation_verdict` PASS is the very claim the default gate
demands, not the weaker substitute `--sweep` accepts. `--sweep`'s own predicate
(closed event plus `status: done`) is untouched and stays NON-archive-eligible.

**Source 3 corroboration (post-review-2026-09-13T105322Z fix at cause,
BLOCKING-1).** A `validation_verdict` event is a SNAPSHOT of what
`last_validation.status` WAS at stamp time — it never changes after the fact
(the N-4 lesson `orchestration-dispatch.mjs:351-362` already states, and
`withStaleAdvisory()` already honours). "Latest wins, never any-pass-ever" is
only real if a later `fail` CAN outrank an earlier `pass`, and the dispatcher
stamps only `pass` events (`orchestration-dispatch.mjs:1591-1597`) — so before
this fix, no later event could ever contradict an earlier one, and a
`validation_verdict: pass` event survived forever regardless of what the ref's
CURRENT verdict became. `eventContradictedByNewerFail` (`metrics-flush.mjs`)
closes that: an event-admitted `pass` is corroborated only when no NEWER `fail`
for the same ref is recorded in (i) the D7 per-ref field
(`entry.validation.status === 'fail'`), (ii) `last_validation` when it names
the ref, or (iii) any `agent_runs` entry with role Validation carrying
`verdict: fail` (the field) or, when the field does NOT decide it — absent,
OR the explicit non-answer `none` — the note marker. "Newer" means timestamped
after the event's own `ts`. A fail signal whose timestamp is missing or
unparseable is treated as newer (fail-closed): ambiguity must never
manufacture a PASS in the append-only ledger. A ref contradicted this way
is skipped with a named reason (`... event exists ... but is not admitted —
a newer fail is recorded ...`), not silently dropped into the generic
"validation verdict is ..." message.

**Round-4 refinement (review-telemetry-fields-not-prose-20260913T114019Z,
NON-BLOCKING-3 and NON-BLOCKING-4).** Two edges in the fixed-order-first-match
scan above needed closing. First, arm (iii)'s field/note choice originally
mirrored `reliabilityOf`'s field-first rule exactly — but that rule is right
for reliability COUNTS, where `verdict: none` legitimately means "not
counted", and wrong for THIS fail-closed corroboration gate, where a `none`
field must never SILENCE a `VERDICT: FAIL` note and manufacture corroboration
for a stale pass; only `verdict: fail` and `verdict: pass` now decide the arm
outright, exactly as before, and `none` (or an absent field) falls to the
note. Second, "newer" is now compared at whole-SECOND precision with a tie
counting as newer, not at raw millisecond precision with a strict `>`:
`state.mjs`'s `nowIso()` truncates every STATE-stamped timestamp to the
second, while `append-event.mjs` keeps milliseconds, so a fail recorded
inside the event's own second could read as numerically "older" purely
because its sub-second part was truncated away. Both are guarded by TEST-144
arms (d) and (h) respectively (mutation matrix: `docs/ai/tdd/spec-telemetry-fields-not-prose/`
remediation evidence).

**Decided against: also making the dispatcher stamp `fail` events.** The
reviewer asked whether `orchestration-dispatch.mjs` should record a
`validation_verdict: fail` event to make "latest wins" literally true inside
`EVENTS.jsonl` itself. Rejected for this fix: the corroboration sources above
(i-iii) are already durable, current, and independent of whether a `fail`
event was ever stamped — they are exactly the facts D6 sources 1 and 2 already
trust. Teaching the dispatcher to stamp `fail` events would duplicate that
truth into a second, append-only-and-therefore-never-correctable channel for
no added safety, and would pull `orchestration-dispatch.mjs` and
`test-aai-orchestration-dispatch.sh` into this review's surface for a
change this fix does not need. `orchestration-dispatch.mjs` was NOT modified
by this remediation and stays out of scope.

This reads `EVENTS.jsonl` on the default path for the first time. The invariant
`test-aai-metrics.sh` TEST-012 pins is that the flush never CREATES or WRITES
that file; a read that tolerates absence does not violate it, and Spec-AC-08
pins that explicitly so the distinction is a test, not a claim.

Measured consequence, which is also the recovery half: on the live STATE this
admits `close-ceremony-fires-only-via-aai-pr` (two `pass` events, the later
2026-09-12T07:31:54Z) — the exact ref the P2 names as permanently stranded.
`--sweep` continues to recover the four of measurement 8, `simple-and-friendly-to-use`
among them. The remaining 24 stranded refs carry no `validation_verdict` event
and stay stranded, fail-closed, which is correct: nothing durable says they
passed. Their honest exits remain `--retire` and a real verdict.

Rejected: a `--ref` recovery arm. `--ref` already exists as a RESTRICTION, not a
grant; overloading it to also grant provenance would make the same flag mean
"only this ref" and "trust this ref", and the second meaning is a truth-gate
bypass wearing a filter's name.

Rejected: folding the event read into `--sweep`. That would make event-admitted
refs non-archive-eligible, understating evidence that is strictly stronger than
what `--sweep` accepts.

### D7 — `set-validation` stamps the ref it names

`state.mjs set-validation --ref <R> --status <s>` additionally writes
`validation: {status: <s>, at: <ISO>}` onto `metrics.work_items[<R>]` when that
entry ALREADY EXISTS. The global block is written exactly as today.

It does NOT auto-init a missing entry. `append-run` auto-inits because a run is
the thing being recorded; a verdict for a ref with no recorded runs would mint a
metrics entry that the flush can then never flush (`no agent_runs recorded`),
which is how one of the 29 strands (`mechanical-context-offload-to-cheap-tier`)
already looks. Creating more of them to fix stranding would be self-defeating.

The per-ref stamp is what makes D6 source 1 exist going forward; source 3 covers
backwards.

### D8 — The partial-flush reset keeps the review scope and says whose it is

`applyPartialReset` stops nulling `code_review.scope`, `base_ref` and `head_ref`,
and instead stamps `code_review.scope_ref_id: <the flushed ref>`. `status`,
`report_paths` and `notes` reset exactly as today — those are verdict state; the
scope is an INPUT to a later step, not a verdict.

`check-committed-scope.mjs --from-state` then uses the scope only when
`scope_ref_id` is ABSENT (legacy STATE, back-compat) or EQUALS
`current_focus.ref_id`. Otherwise it degrades with a line naming both refs,
rather than silently comparing a previous ride's path list. The guard is the
reason keeping the scope is safe: without it, the fix for
`NOTHING CHECKED (degraded: null not on disk)` would be a stale-scope hazard.

Rejected: teaching step 4a to read the scope from the ledger. The ledger entry
does not carry the review scope, adding it would be a second schema change, and
the value is already in STATE one line above where it is nulled.

### D9 — The orchestrator instruction lives outside the prompt corpus (one wired exception, round-1 remediation)

The prose telling the orchestrator to pass the five flags — and that a Validation
or Code Review append without `--verdict` is refused — goes into
`.aai/SUBAGENT_PROTOCOL.md`'s existing "Harness-reported usage capture" section,
which is already the single home of that contract. Measurement 11: that file is
in neither the `.aai/*.prompt.md` glob nor TEST-010's three extras, so the
SUBAGENT_PROTOCOL.md half of this instruction adds ZERO prompt-corpus bytes. No
`.aai/*.prompt.md` file is edited for it.

Round-1 validation (BLOCKING-3) found a SECOND, unwired caller: `.aai/ROLE_COMMON.md`'s
own PRIMARY PATH `append-run` example — the block every role's DIRECT-EXECUTION
path (Planning, Implementation, Validation, Remediation, SKILL_TDD) actually
runs — never mentioned `--verdict` at all, so a direct-execution Validation or
Code Review run following it now hit the new refusal with no way to satisfy it.
`.aai/ROLE_COMMON.md` IS one of TEST-010's three extras, so wiring `--verdict`
into its example is NOT free: it cost a measured 216 B, credited 1:1 in
`tests/skills/lib/prompt-diet-ledger.sh` (`JUSTIFIED_ADDITIONS` +
`JUSTIFIED_GROWTH_BYTES` bump), with a matching TEST-012 checkpoint re-sum. It
needs no new `PROFILES.yaml` entry — ROLE_COMMON.md is an existing classified
file, not a new `.aai/**` one.

Therefore the PLANNING companion-obligation check resolves to: ONE prompt-diet
ledger entry (crediting the ROLE_COMMON.md edit), one TEST-012 checkpoint bump,
and no `PROFILES.yaml` entry. Spec-AC-13 pins the SUBAGENT_PROTOCOL.md half of
the claim (all five flags + refusal named there; zero corpus occurrences of the
three orchestrator-only flag names) so that half is tested rather than
asserted; it does NOT claim the ROLE_COMMON.md wiring added no corpus bytes,
because — as of this remediation — it does.

### D10 — `harness` on friction observations is DERIVED, never accepted

`aai-friction.mjs` gains a ninth allowlisted v1 key, `harness`, set from
`detectHarness(process.env)` on the recording machine — the same shape as
`os_family`/`node_major` (measurement 13). An input key named `harness` is
dropped by the deny-by-default copy, exactly like every other unlisted key.
`aai-feedback-upsert.mjs` renders it through a new closed-set sanitizer
`safeHarness()` over `HARNESS_VALUES`, appended to the existing
`os_family / node_major / aai_pin` facts line. A spool line is untrusted input
and this value reaches a public GitHub issue body; the closed set is the whole
reason the upsert side needs its own sanitizer rather than trusting the recorder.

Legacy observations with no `harness` key still triage and still upsert, with the
field rendered `unknown`.

## Scope

In scope: the five `append-run` fields and their defaults and refusals; the
`set-validation` per-ref stamp; field-first derivation of reliability, cost and
model in the flush with a labelled note fallback; the blended-total cost and its
PRICING-declared share and bounds; the three-source default flush gate and the
`EVENTS.jsonl` read; the partial-reset scope preservation and the
`check-committed-scope` provenance guard; `harness` on friction observations,
`aai-feedback-triage.mjs`'s `ALLOWED_KEYS` gate and closed-set `safeHarness()`
sanitizer that let a `harness`-carrying observation survive triage instead of
being dropped as `unsanitized_key`, and in the upsert payload; the basis
columns in the factory and metrics reports; the `SUBAGENT_PROTOCOL.md`
instruction; the seven suites (the sixth-suite count is post-freeze widened by
one — see `## Amendment` — to include `tests/skills/test-aai-feedback-triage.sh`)
— plus four caller fixes for the Article-5 `append-run --verdict` breaking
change (round-3 NB-3 erratum: eleven test files ship, not seven):
`tests/skills/test-aai-token-capture.sh` and `tests/skills/test-aai-overview.sh`
(new assertions, previously named only in `## Verification`/nowhere), and
`tests/skills/test-aai-prompt-diet.sh` plus `tests/skills/lib/prompt-diet-ledger.sh`
(already disclosed in D9). All eleven are inside `docs/ai/STATE.yaml`'s review
scope; nothing here was hidden, only under-named.

Out of scope, stated so the delivery is not read as more than it is:

- **Rewriting existing ledger lines.** `docs/ai/METRICS.jsonl` is append-only
  (HAZ-LEDGER). The 138 lines measured above keep their numbers, wrong ones
  included. Spec-AC-14 pins that the file before and after this ride's own flush
  differs only by appended bytes.
- **`close-work-item.mjs`.** Hash-pinned by four suites; SPEC-0175 R6 names its
  hardcoded `validation: pass` in `work_item_closed`. It stays a named residual.
- **A per-token input/output split** where the harness does not expose one. No
  estimation path is created; `total-blended` is a labelled estimate and is never
  relabelled `decomposed`.
- **Recovering the 24 stranded refs that carry no durable pass evidence.** Named
  in D6 with the count; fail-closed by design.
- **`code_review.required`** and the PR gate's enforcement semantics
  (`fu-flush-vacates-code-review-gate`).
- **Any `.aai/*.prompt.md` byte change** (D9).

## Constitution deviations

- **Article 5 (additive first) — one deliberate breaking change at a public CLI
  boundary.** `append-run --role Validation` and `--role "Code Review"` without
  `--verdict` now EXIT 2 where they previously succeeded. Justified: the whole
  defect is that a missing verdict is indistinguishable from a passing one, and
  every non-refusing shape (default `none`, warn-and-continue) reproduces that
  ambiguity in a field instead of a note. It is loud, it names the flag, it
  writes nothing, and D9 (as amended by round-1 remediation, BLOCKING-3) wires
  EVERY caller that exists: the dispatched-subagent path documented in
  `.aai/SUBAGENT_PROTOCOL.md` and the direct-execution path documented in
  `.aai/ROLE_COMMON.md`'s own shared `append-run` example. Every OTHER change in
  this scope is additive: new optional flags, new additive ledger keys, a widened
  gate that never removes a ref the old gate would have flushed, and a preserved
  STATE field that used to be nulled.

Otherwise:

- Article 1 (evidence before claims): this scope IS the article's subject — it
  replaces a derived claim with a recorded one and labels what remains derived.
- Article 2 (simplicity): no new module, no dependency; one imported function
  from pair 1, one new PRICING key, additive fields on shapes that already exist.
- Article 3 (portability): `harness` is a five-value closed set written into
  plain git-diffable files; nothing is vendor-bound.
- Article 4 (degrade and report): every fallback prints a NOTE naming the run and
  the basis; a missing `EVENTS.jsonl` degrades to "no event evidence" and never
  creates the file.
- Article 6 (single-writer state): every STATE write in this scope goes through
  `state.mjs` or the flush's own engine; no hand-edit.
- Article 7 (operator-only merge): unchanged.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0183 AC-001 through AC-007, plus the wave-3 flush-window
  bucket the ride also owns (Spec-AC-06 through Spec-AC-09) and the orchestrator
  wiring (Spec-AC-13).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN append-run is called with the five new flags the agent_runs entry SHALL carry harness, tokens_total, verdict, requested_model and actual_model as fields, the note SHALL be written unchanged, and check-state on the result SHALL exit 0. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-026.txt; validation-round6.txt (M1a-M1e red per field) | — | TEST-026 |
| Spec-AC-02 | WHEN --harness is omitted the field SHALL equal detectHarness(process.env), WHEN --harness names a value outside HARNESS_VALUES the call SHALL exit 2 and write nothing, and WHEN --verdict is omitted for a role other than Validation and Code Review the field SHALL be none. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-027.txt; validation-round6.txt (scrubbed and env arms) | — | TEST-027 |
| Spec-AC-03 | WHEN the role is Validation or Code Review and --verdict is absent, append-run SHALL exit 2 with a message naming --verdict and STATE SHALL be byte-identical to before the call; with --verdict fail the run SHALL carry verdict fail. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-028.txt; validation-round6.txt (M5 equivalent mutant, liveness probe red) | — | TEST-028 |
| Spec-AC-04 | WHEN a fixture carries two Validation runs with verdict fail and no note marker the flush SHALL record validation_fails 2 with reliability.basis field; with the fields removed and notes reading VERDICT FAIL without a colon it SHALL record validation_fails 0 with reliability.basis note and one NOTE line naming each run and its basis; WHEN a run's verdict field and note marker DISAGREE the FIELD SHALL win in both directions and exactly one disagreement NOTE SHALL be emitted per affected run. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-135.txt; green-TEST-136.txt; green-TEST-145.txt; validation-round6.txt | — | TEST-135, TEST-136, TEST-145 |
| Spec-AC-05 | WHEN a run carries a token total and a PRICING-resolvable model the flush SHALL write a non-null cost_usd equal to the total times the PRICING-declared blend, cost_basis total-blended and cost_bounds_usd holding the all-input and all-output extremes; a run with both token fields SHALL be labelled decomposed and a run with neither SHALL keep cost_usd null with cost_basis none and today's WARNING line. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-137.txt; validation-round6.txt (blend re-derived on the live ledger) | — | TEST-137 |
| Spec-AC-06 | WHEN metrics.work_items names a ref whose per-ref validation status is pass, or whose latest validation_verdict event in EVENTS.jsonl is pass AND is not contradicted by a newer recorded fail for that ref (per-ref field, last_validation, or an agent_runs Validation entry), the default flush gate SHALL admit that ref even while last_validation names a different ref or is not_run, and the plan SHALL name which of the three sources decided it; a contradicted event SHALL be skipped with a named reason, never silently admitted. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-138.txt; green-TEST-139.txt; green-TEST-144.txt; validation-round6.txt (arms a-i, 8 inner mutations red) | — | TEST-138, TEST-139, TEST-144 |
| Spec-AC-07 | WHEN set-validation --ref R runs and metrics.work_items[R] exists the entry SHALL gain validation with status and at fields; WHEN that entry does not exist no entry SHALL be created and the global block SHALL still be written. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-029.txt; validation-round6.txt (stamp value asserted) | — | TEST-029 |
| Spec-AC-08 | WHEN the flush runs without --sweep over a tree that has no EVENTS.jsonl it SHALL exit 0 and SHALL NOT create that file. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-140.txt; green-TEST-031.txt; validation-round6.txt | — | TEST-140 |
| Spec-AC-09 | WHEN a partial-flush reset runs, code_review scope, base_ref and head_ref SHALL be unchanged and code_review.scope_ref_id SHALL name the flushed ref; check-committed-scope --from-state SHALL use that scope when scope_ref_id equals current_focus.ref_id and SHALL degrade with a line naming both refs when it does not; WHEN set-code-review --scope runs it SHALL refresh scope_ref_id to current_focus.ref_id, and reset-block code_review SHALL clear it. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-141.txt; green-TEST-007.txt; validation-round6.txt | — | TEST-141, TEST-007, TEST-031 |
| Spec-AC-10 | WHEN aai-friction.mjs record persists an observation the record SHALL carry a harness key derived from detectHarness(process.env), an input key named harness SHALL NOT reach the record, and a legacy observation without the key SHALL still validate and triage. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-113.txt; triage TEST-014; validation-round6.txt (record to triage to upsert chain run live) | — | TEST-113 |
| Spec-AC-11 | WHEN a draft is prepared the structured facts SHALL carry harness beside os_family, node_major and aai_pin, and a spool value outside HARNESS_VALUES SHALL render as unknown. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-064.txt; validation-round6.txt (real record call in arm a) | — | TEST-064 |
| Spec-AC-12 | The factory report SHALL render a verdict-source and a cost-basis per ride and state how many rides are field-derived versus marker-derived, and the metrics report SHALL carry a cost-basis marker in its per-ride table and a basis column in its reliability section. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-042.txt; green-TEST-142.txt; validation-round6.txt | — | TEST-042, TEST-142 |
| Spec-AC-13 | .aai/SUBAGENT_PROTOCOL.md SHALL name all five flags and the Validation and Code Review refusal, and the prompt-diet corpus SHALL contain zero occurrences of the three orchestrator-only flag names (`--tokens-total`, `--requested-model`, `--actual-model`), proving THOSE three added no corpus bytes; `--harness` (a pre-existing log-tick flag) and `--verdict` (legitimately carried by .aai/ROLE_COMMON.md's own append-run example, round-1 remediation BLOCKING-3) are excluded from that zero-occurrences probe on purpose and are not claimed to be corpus-byte-free. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-030.txt; token-capture TEST-003; validation-round6.txt (+216 B = ledger = pin) | — | TEST-030 |
| Spec-AC-14 | WHEN this ride's own flush runs, docs/ai/METRICS.jsonl before the flush SHALL be a byte-exact prefix of the file after it. | done | docs/ai/tdd/spec-telemetry-fields-not-prose/green-TEST-143.txt; validation-round6.txt | — | TEST-143 |

## Implementation plan

Components affected:

- `.aai/scripts/state.mjs` — `CMD_FLAGS['append-run']` gains the five keys;
  `cmdAppendRun` gains the flag reads, the `detectHarness` default, the
  `VERDICT_REQUIRED_ROLES` refusal and the field emission; `CMD_FLAGS['set-validation']`
  is unchanged but `cmdSetValidation` gains the per-ref stamp (D7); imports
  `detectHarness`/`HARNESS_VALUES` from `lib/harness.mjs`.
- `.aai/scripts/metrics-flush.mjs` — `parseMetricsEntries` numeric allowlist gains
  `tokens_total`; `reliabilityOf` becomes field-first with a basis; `buildEntry`
  gains the per-run basis keys, the blended cost and the bounds; the default gate
  loop gains the three-source resolution and the plan/skip basis naming;
  `applyPartialReset` stops nulling three fields and stamps `scope_ref_id`; a new
  read-only `latestValidationEvent(eventsPath, ref, warnings)` helper (returns
  `{status, ts}`) that tolerates a missing file and NEVER creates it; and
  `eventContradictedByNewerFail(...)` (BLOCKING-1 fix, review-telemetry-fields-not-prose-20260913T105322Z)
  which corroborates a source-3 pass event against the D7 per-ref field,
  `last_validation`, and `agent_runs` before admitting it.
- `.aai/scripts/lib/pricing.mjs` — `parsePricing` gains `cost_blend.input_share`;
  a new `blendedCostUsd(pricing, modelId, total)` returning `{cost, bounds}`.
- `.aai/system/PRICING.yaml` — one new `cost_blend:` block with the share, its
  `basis: convention` and the reason.
- `.aai/scripts/check-committed-scope.mjs` — `scopeFromState` additionally reads
  `code_review.scope_ref_id` and `current_focus.ref_id` and degrades on mismatch.
- `.aai/scripts/aai-friction.mjs` — `deriveHarness()` plus one allowlist key.
- `.aai/scripts/aai-feedback-triage.mjs` — post-freeze addition (see
  `## Amendment`): imports `HARNESS_VALUES` from `lib/harness.mjs`; `ALLOWED_KEYS`
  gains the `harness` key (the key is allowed unconditionally; without this the
  triage gate's sanitizer rejects every newly recorded observation whole as
  `unsanitized_key`, which round-1 BLOCKING-1 named as the cause); a new
  closed-set `safeHarness(v)` normalizes an out-of-set or absent value to
  `unknown` rather than rejecting the row, mirroring the sibling upsert
  sanitizer; `triage()`'s emitted cluster gains a `harness: safeHarness(...)` field.
- `.aai/scripts/aai-feedback-upsert.mjs` — `safeHarness()` plus one rendered field.
- `.aai/scripts/generate-factory-report.mjs`, `.aai/scripts/metrics-report.mjs` —
  basis columns and the field-versus-marker counts.
- `.aai/SUBAGENT_PROTOCOL.md` — the "Harness-reported usage capture" section.
- Suites: `tests/skills/test-aai-state.sh` (TEST-026..031),
  `tests/skills/test-aai-metrics.sh` (TEST-135..145),
  `tests/skills/test-aai-friction.sh` (TEST-113),
  `tests/skills/test-aai-feedback-triage.sh` (TEST-011, TEST-014 — post-freeze
  addition, see `## Amendment`),
  `tests/skills/test-aai-feedback-upsert.sh` (TEST-064),
  `tests/skills/test-aai-factory-report.sh` (TEST-042),
  `tests/skills/test-aai-learned-routing.sh` (TEST-007) — plus four callers
  fixed for the Article-5 `append-run --verdict` breaking change (round-3
  NB-3 erratum): `tests/skills/test-aai-token-capture.sh`,
  `tests/skills/test-aai-overview.sh`, `tests/skills/test-aai-prompt-diet.sh`
  and `tests/skills/lib/prompt-diet-ledger.sh` (the latter two already
  disclosed in D9).

Data flow: harness env inherited by the `state.mjs` child -> `harness` field on
the run -> flush reads the field -> ledger line -> factory and metrics reports.
Verdict: role subagent -> orchestrator merge -> `append-run --verdict` ->
`verdict` field -> `reliabilityOf` -> `reliability` + `basis` -> report quality
KPIs. Provenance: `set-validation --ref` -> per-ref `validation` field AND the
dispatcher's `validation_verdict` event -> the flush's three-source gate ->
`defaultOkRefs` -> archive record and partial reset.

Edge cases: a run appended by an older orchestrator (no fields at all); a note
carrying BOTH a marker and a field that disagree (the FIELD wins, and the
disagreement is a NOTE line); `tokens_total` present with a model that resolves
to the `unknown` PRICING entry (null rates -> `cost_usd` null, `cost_basis`
`none`, no fabricated number); a `validation_verdict` event whose latest payload
for the ref is `fail` (not admitted — latest wins, never any-pass-ever); an
`EVENTS.jsonl` that does not exist; a `validation_verdict` line that is malformed
JSON (skipped, one NOTE, never a crash); a ref whose per-ref field says `pass`
and whose latest event says `fail` (source order decides, and the plan names
`per-ref-field` so the disagreement is visible); a partial reset on a STATE whose
`code_review.scope` is already null (nothing to preserve, `scope_ref_id` still
stamped); a friction spool line from a pre-change AAI (no `harness` key).

One hazard the implementer must respect or the suite passes locally and fails
only on CI: these suites run INSIDE a harness. `CLAUDECODE` is set in a
developer's session and absent on a GitHub runner, so any test that lets
`append-run` or `aai-friction.mjs` read the ambient environment asserts different
things in the two places. Every new test either scrubs the harness variables
(`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT ...`) or sets `AAI_HARNESS`
explicitly. This is the same hazard SPEC-0177 recorded, now reaching two more
scripts.

Second hazard, specific to this scope: the suites must run under
`AAI_ROLE=subagent`-free environments for their own `state.mjs` fixtures
(`fu-role-guard-blocks-own-fixtures`), and the flush tests must NEVER be pointed
at the shipping `docs/ai/STATE.yaml` — every fixture is a scratch copy
(HAZ-SCRATCH, HAZ-LEDGER).

## Test Plan

Test ids continue each OWNING suite's own existing sequence, which is how this
repository numbers them; the highest existing id per suite was read at freeze
(`test-aai-state.sh` 025, `test-aai-metrics.sh` 134, `test-aai-friction.sh` 112,
`test-aai-feedback-upsert.sh` 063, `test-aai-factory-report.sh` 041,
`test-aai-learned-routing.sh` 006). Every id below is unique within this spec.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-026 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | append-run with all five flags on a fixture STATE writes five fields with the expected values and indentation, leaves the note text unchanged, and check-state on the result exits 0. | pending |
| TEST-027 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Defaults and enum refusal — AAI_HARNESS=codex with no --harness writes harness codex, a scrubbed env writes unknown, --harness bogus exits 2 with STATE byte-identical, and a Planning run with no --verdict writes verdict none. | pending |
| TEST-028 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | Verdict refusal — --role Validation and --role Code Review each without --verdict exit 2 with the flag named on stderr and cmp of STATE before and after identical; the same call with --verdict fail exits 0 and writes verdict fail. | pending |
| TEST-029 | Spec-AC-07 | integration | tests/skills/test-aai-state.sh | set-validation --ref R --status pass stamps validation status and at on an EXISTING metrics.work_items entry, creates no entry for a ref that has none, writes the global block in both cases, and check-state exits 0 after each. | pending |
| TEST-030 | Spec-AC-13 | unit | tests/skills/test-aai-state.sh | SUBAGENT_PROTOCOL.md names all five flags and carries the refusal sentence, and a grep for the three orchestrator-only flag names (`--tokens-total`, `--requested-model`, `--actual-model`) over the prompt-diet corpus files returns zero, proving those three added no corpus bytes (`--harness`/`--verdict` are excluded from that probe — see Spec-AC-13). | pending |
| TEST-031 | Spec-AC-09 | integration | tests/skills/test-aai-state.sh | code_review.scope_ref_id lifecycle (NON-BLOCKING-A, review-telemetry-fields-not-prose-20260913T105322Z) — set-code-review --scope REFRESHES scope_ref_id to current_focus.ref_id, an unrelated set-code-review call leaves it alone, and reset-block code_review CLEARS it without creating it on a legacy STATE. | pending |
| TEST-135 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | Field basis — a fixture with two Validation runs carrying verdict fail and no note marker flushes to validation_fails 2, review_fails counted from a Code Review run with verdict fail, first_pass_clean false and reliability.basis field. | pending |
| TEST-136 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | Note fallback and its label — the same fixture with the verdict fields deleted and notes reading VERDICT FAIL without a colon flushes to validation_fails 0, reliability.basis note, and one NOTE line per affected run naming the run and the basis. | pending |
| TEST-137 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh | Cost basis table — a run with tokens_total and a priced model yields the blend-derived cost_usd, cost_basis total-blended and the two bounds; a run with tokens_in and tokens_out yields today's exact figure with cost_basis decomposed; a run with neither yields null with cost_basis none and the existing WARNING; a run whose model resolves to the unknown PRICING entry yields null, never a number. | pending |
| TEST-138 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh | Per-ref field basis — a fixture whose last_validation is not_run with ref_id null but whose metrics entry carries validation status pass flushes that ref, the plan names per-ref-field, and the ref is archive-eligible. | pending |
| TEST-139 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh | Event basis — a fixture whose last_validation names a DIFFERENT ref and whose EVENTS.jsonl carries a pass validation_verdict for the stranded ref flushes it naming basis event; the same fixture with the latest event for that ref being fail skips it with the reason named; a malformed event line is skipped with a NOTE and does not crash. | pending |
| TEST-144 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh | Event corroboration (BLOCKING-1, review-telemetry-fields-not-prose-20260913T105322Z) — a fixture whose per-ref field is fail, whose last_validation names the ref as fail, and whose one Validation run carries verdict fail, alongside an OLDER validation_verdict pass event for that ref, is SKIPPED with a named reason and zero ledger bytes; a positive control with a pass event and no contradicting fail anywhere still flushes naming basis event. Round-4 NON-BLOCKING-1 arms (a)-(h) isolate each corroboration source (per-ref field, last_validation with a REAL run_at_utc, a Validation run's verdict field, and `verdict: none` plus a VERDICT: FAIL note — the field must NOT mask the note fallback) one at a time, an older-fail control, an unparseable fail/event ts on each side (fail-closed), and a same-second ts tie (review NON-BLOCKING-3 — counts as newer). | pending |
| TEST-145 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | Field/note disagreement (NON-BLOCKING-B, review-telemetry-fields-not-prose-20260913T105322Z) — a run whose verdict field and note marker DISAGREE resolves from the FIELD in both directions (never the note) and emits exactly one field/note disagreement NOTE per affected run, none for an agreeing run. | pending |
| TEST-140 | Spec-AC-08 | integration | tests/skills/test-aai-metrics.sh | Default path never creates EVENTS — a flush with no --sweep over a fixture tree containing no docs/ai/EVENTS.jsonl exits 0, flushes by the global block, and the file still does not exist afterwards. | pending |
| TEST-141 | Spec-AC-09 | integration | tests/skills/test-aai-metrics.sh | Partial reset preserves scope — after a partial-flush reset, code_review scope, base_ref and head_ref hold their pre-flush values, scope_ref_id names the flushed ref, and status, report_paths and notes are reset exactly as today. | pending |
| TEST-142 | Spec-AC-12 | integration | tests/skills/test-aai-metrics.sh | metrics-report golden over a fixture ledger mixing a field-derived line, a marker-derived line and a pre-basis legacy line renders a cost-basis marker per ride and a basis column in the reliability section, byte-deterministically. | pending |
| TEST-143 | Spec-AC-14 | integration | tests/skills/test-aai-metrics.sh | Append-only — head -c of the fixture ledger taken before the flush is byte-identical to the same prefix of the file after it, and the line count grows by exactly the number of flushed refs. | pending |
| TEST-113 | Spec-AC-10 | integration | tests/skills/test-aai-friction.sh | harness on observations — a record under AAI_HARNESS=codex persists harness codex, an input object carrying harness gemini persists the DERIVED value not the supplied one, and a legacy spool line with no harness key still validates and triages. | pending |
| TEST-064 | Spec-AC-11 | integration | tests/skills/test-aai-feedback-upsert.sh | harness in the payload — a prepared draft from a spool line with harness codex renders it on the facts line beside os_family, a line carrying an off-set value renders unknown, and a line with no harness key renders unknown. | pending |
| TEST-042 | Spec-AC-12 | integration | tests/skills/test-aai-factory-report.sh | factory report over a fixture ledger mixing field-derived, marker-derived and pre-basis entries renders a verdict-source and cost-basis per ride and a KPI stating the field-derived versus marker-derived ride counts, with legacy rides shown n/a and never zero. | pending |
| TEST-007 | Spec-AC-09 | integration | tests/skills/test-aai-learned-routing.sh | check-committed-scope --from-state uses a preserved scope when scope_ref_id equals current_focus.ref_id, degrades with a line naming BOTH refs when it does not, and behaves exactly as today when scope_ref_id is absent. | pending |

Every Spec-AC has at least one TEST row and every TEST row names exactly one
Spec-AC.

## Mutation checks

The ride immediately before this one shipped five controls that claimed a
property they did not test; four were caught by mutation, one by an external bot.
So every test above is paired here with the SOURCE MUTATION that must redden it.
Each mutation is applied to a scratch COPY of the tree, never to a shipping file
(HAZ-RESTORE, HAZ-SCRATCH), and its failing output is recorded one file per entry
under `docs/ai/tdd/spec-telemetry-fields-not-prose/`.

RED-first — every test above asserts behaviour that does not exist on the
pre-change tree, so each is observed FAILING there before any engine edit, as
`red-<id>.txt`. No test in this plan is exempt: there is no byte-identity arm.

| Mutation | Must redden | What it proves |
|----------|-------------|----------------|
| M1 | TEST-026 | Delete ONE of the five field-emitting lines in `cmdAppendRun` (each of the five deleted in turn, five sub-runs). A test that greps only for the block's presence rather than each field passes and is too weak. |
| M2 | TEST-027 | Replace the `detectHarness(process.env)` default with the literal `'claude'`. The scrubbed-env arm must go red; if only the AAI_HARNESS arm reds, the test never exercised the default. |
| M3 | TEST-027 | Change the `--harness` read from `enumFlag` to `strFlag`. The `--harness bogus` arm must go red on the exit code, not merely on the message text. |
| M4 | TEST-028 | Change the refusal set from `{Validation, Code Review}` to `{Validation}`. The Code Review arm must go red independently of the Validation arm. |
| M5 | TEST-028 | Move the refusal to AFTER the `editBlock` write. The byte-identity `cmp` arm must go red even though the exit code stays 2 — this is the arm that proves nothing was written. |
| M6 | TEST-029 | Make the per-ref stamp auto-init a missing entry. The no-entry arm must go red; a test that only asserts the positive case cannot see the strand-minting regression D7 rejects. |
| M7 | TEST-030 | Add one of the three orchestrator-only flag names (`--tokens-total`, `--requested-model`, `--actual-model`) to a `.aai/*.prompt.md` file. The corpus-grep arm for that flag must go red, proving the zero-bytes claim is measured and not asserted; `--verdict` and `--harness` are excluded from this probe on purpose (Spec-AC-13) and must NOT go red. |
| M8 | TEST-135 | Delete the field-first branch in `reliabilityOf` so it falls straight through to the note marker. This is the intake's named mutation and the defining control of the scope. |
| M9 | TEST-136 | Hardcode `reliability.basis` to the literal `'field'`. TEST-136's note arm must go red, proving the label is derived and not constant. (Round-3 NB-1 erratum: this cell previously named TEST-135; the mutation reddens TEST-136, matching the prose.) |
| M10 | TEST-136 | Delete the per-run NOTE emission in the fallback path. The NOTE-line arm must go red; the counts alone still agree, so a test that checks only counts is too weak. |
| M11 | TEST-137 | Replace the PRICING `cost_blend.input_share` read with a hardcoded `0.5`, then change the fixture PRICING share to `0.9`. The cost value must go red, proving the share is read and not compiled in. |
| M12 | TEST-137 | Relabel the blended arm `decomposed`. The label assertion must go red — this is the control against an estimate being presented as a measurement. |
| M13 | TEST-137 | Remove the null-rate guard so the `unknown` PRICING entry yields `NaN` or `0`. The unknown-model arm must go red rather than silently recording a fabricated figure. |
| M14 | TEST-138 | Reorder the three gate sources so the global block is consulted first and short-circuits. The per-ref-field arm's BASIS assertion must go red even though the ref still flushes — a test that asserts only "it flushed" cannot see a wrong provenance label. |
| M15 | TEST-139 | Change the event selection from "latest for the ref" to "any pass for the ref". The latest-is-fail arm must go red. |
| M16 | TEST-139 | Remove the try/catch around the event line parse. The malformed-line arm must go red on the crash, not on the skip message. |
| M17 | TEST-140 | Replace the existence-guarded event read with a `mkdirSync` plus `appendFileSync` open. The file-absence arm must go red, proving the TEST-012 invariant is preserved by construction and not by luck. |
| M18 | TEST-141 | Restore the `setField(bl, 2, 'scope', null)` line in `applyPartialReset`. The preservation arm must go red. |
| M19 | TEST-141 | Delete the `scope_ref_id` stamp while keeping the preservation. The provenance arm must go red independently of the preservation arm. |
| M20 | TEST-007 | Make `scopeFromState` ignore `scope_ref_id` entirely. The mismatch-degrade arm must go red while the matching arm still passes — the control against a stale scope being silently used. |
| M21 | TEST-113 | Copy `harness` from the INPUT object instead of deriving it. The supplied-value arm must go red; this is the deny-by-default control. |
| M22 | TEST-064 | Replace `safeHarness()` with a pass-through. The off-set-value arm must go red — a spool line reaches a public issue body, so this is the injection control. |
| M23 | TEST-042 | Hardcode the factory report's verdict-source column to `field`. The marker-derived and legacy rows must go red. |
| M24 | TEST-142 | Drop the basis column from the metrics-report reliability section. The golden must go red on the missing column, not merely on whitespace. |
| M25 | TEST-143 | Make the ledger write use `writeFileSync` instead of `appendFileSync`. The prefix `cmp` must go red. |
| M26 | TEST-144 | Replace the `eventContradictedByNewerFail(...)` call with a hardcoded `false` (corroboration removed). The stale-pass-event arm must go red: the ref flushes with `verdict_basis event` and a self-contradicting ledger line (`verdict PASS` beside `validation_fails 1`, `first_pass_clean false`). This is BLOCKING-1's own reproduction fixture (review-telemetry-fields-not-prose-20260913T105322Z). |

## Seams

Each row is a boundary this change shares with something it does not own, with
the test that produces on one side and asserts on the other. Two unit tests that
mock the boundary would test the mock.

| Seam | Produced by | Asserted by | Test |
|------|-------------|-------------|------|
| S1 | `state.mjs append-run` writes the five fields as STATE lines | `metrics-flush.mjs parseMetricsEntries` reads them into `run[key]`; `tokens_total` must reach the numeric allowlist or it arrives as a STRING and the cost arithmetic silently yields `NaN` | TEST-135 and TEST-137 both drive a REAL `append-run` into a real flush, never a hand-written fixture only |
| S2 | `state.mjs set-validation --ref` writes the per-ref `validation` field | the flush's gate source 1 reads it | TEST-138 drives a real `set-validation` then a real flush |
| S3 | `orchestration-dispatch.mjs` appends `validation_verdict` events (not edited here) | the flush's gate source 3 reads the LATEST per ref | TEST-139 uses event lines in the exact shape the dispatcher emits, including the `payload.hash` key the flush ignores |
| S4 | the flush's `applyPartialReset` writes `code_review.*` | `check-committed-scope.mjs --from-state` reads them one step later in SKILL_PR | TEST-007 runs the real `check-committed-scope` against a STATE produced by a real partial-flush reset, not a synthesized one |
| S5 | `aai-friction.mjs record` writes a spool line, then `aai-feedback-triage.mjs` gates it through `ALLOWED_KEYS` (the `harness` key survives) and normalizes the value through the closed-set `safeHarness()` sanitizer | `aai-feedback-upsert.mjs` renders the surviving cluster into an issue body | TEST-113 (record derives `harness`, never copies a supplied value), TEST-014 (the triage gate must not drop a `harness`-carrying or out-of-set observation as `unsanitized_key`), TEST-064 (one arm feeds a spool line produced by a real `record` call, the others a hand-poisoned off-set line and a legacy no-key line) |
| S6 | the flush writes the ledger line | `generate-factory-report.mjs` and `metrics-report.mjs` render it | TEST-042 and TEST-142 read a ledger produced by a real flush |
| S7 | `.aai/scripts/lib/harness.mjs` `detectHarness` (pair 1, not edited here) | three new callers: `append-run`, `aai-friction.mjs`, and the upsert's closed set | TEST-027 and TEST-113 both assert the SAME closed set, so a divergent private copy would show |
| S8 | this scope's widened default gate | the RUNNING factory: the first real flush after this ships will additionally admit `close-ceremony-fires-only-via-aai-pr`, changing which refs a partial-versus-full reset covers | TEST-139 pins the multi-ref reset shape; the live consequence is disclosed as R3 below |

Residual risks, written down rather than left out:

- **R1 — a harness that exposes no usage still records nothing.** `tokens_total`
  absent means `cost_basis: none` and a null cost, exactly as today. This scope
  widens what CAN be recorded; it cannot make a silent harness speak.
- **R2 — `Remediation` runs carry `verdict: none`.** The refusal covers only
  Validation and Code Review (D2). `remediation_runs` stays the structural
  witness for everything else.
- **R3 — the first post-merge flush changes shape.** It will flush one extra ref
  (measurement 8 plus D6) and therefore reset differently than a pre-change flush
  would have. This is the intended recovery, but it lands on the ride's own close
  ceremony and must be read as expected, not as a defect.
- **R4 — 24 refs stay stranded.** They carry no durable pass evidence. Named
  with the count in D6; the honest exits are `--retire` and a real verdict.
- **R5 — `close-work-item.mjs` still hardcodes `validation: pass`** in
  `work_item_closed` (SPEC-0175 R6). Out of scope, unchanged, still true.
- **R6 — the blend share is a convention, not a measurement.** Declared as such
  in PRICING.yaml, labelled on every derived number, and bounded by
  `cost_bounds_usd`. It is the honest shape of an unmeasurable quantity, not a
  measured one.
- **R7 — a note and a field that disagree.** The field wins and the disagreement
  prints a NOTE. Nothing reconciles the two, because the note is prose and the
  whole scope exists to stop trusting it.
- **R8 — pre- and post-merge flushed lines are cost-incomparable (round-1
  validation NB-4).** D5 changes two EXISTING keys on a legacy note-marker-only
  STATE, not only additive ones: `agent_runs[].cost_usd` moves `null` ->
  a blended number, and `totals.total_cost_usd` moves `null` -> a number. That
  is intended (Spec-AC-05 exists to make this recoverable), but it means a
  legacy ride flushed AFTER this scope merges is priced while the 138
  already-flushed lines measured above are not (0 of 138 carry any numeric
  cost today, per measurements.txt). Any report or comparison that sums or
  averages `cost_usd`/`total_cost_usd` across the merge boundary without first
  partitioning on `cost_basis`/`verdict_basis` presence will silently compare
  priced and unpriced rides as if they were the same unit. No AC in this scope
  closes that gap; it is named here so a later consumer partitions on basis
  rather than assuming uniform pricing across the whole ledger.

## Verification

Commands, in the order the evidence is produced:

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-upsert.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-learned-routing.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-token-capture.sh`
  and `tests/skills/test-aai-pr-waiver.sh` (existing flush consumers — regression)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  (Spec-AC-13's corpus half)
- one full sweep before close, `AAI_TEST_TIMEOUT=3000`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md`
- `env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --check --strict --no-event`

PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status, and
every mutation in `## Mutation checks` observed RED with its output recorded.

## Evidence contract

All evidence for this scope lives under
`docs/ai/tdd/spec-telemetry-fields-not-prose/`:

- `red-<test-id>.txt` — the failing run of each test on the pre-change tree.
- `green-<test-id>.txt` — the passing run after the engine edit.
- `mutation-<Mnn>.txt` — the failing run of the named test under the named source
  mutation, applied to a scratch copy.
- `measurements.txt` — the re-run of the `## What is established before this
  scope starts` scripts, so the numbers in this spec are reproducible at review.
- `sweep-<ts>.txt` — the full-suite sweep before close.

Each artifact records: ref_id `telemetry-fields-not-prose`, the Spec-AC and
TEST-xxx it belongs to, the exact command, the exit code, and the commit or diff
range it was produced against.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix. That is what the contract above demands.
