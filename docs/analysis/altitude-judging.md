---
id: altitude-judging
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Analysis — blind judging rubric and blinding plan (altitude-prompt experiment)

Phase 1 of `docs/issues/CHANGE-0113-altitude-prompt-experiment.md`, adapted from
the intake's review-role design to the **PLANNING** pilot. The intake's original
oracle (the external-bot review-miss rate) does not exist for Planning, so the
oracle here is the **ground-truth frozen spec** each task actually produced —
which is why every metric below is defined as a comparison against it, or as an
absolute count that does not need it.

## What the judge receives

Per judged unit, exactly three things and nothing else:

1. The **sanitized task intake** (`docs/analysis/altitude-tasks.md`, "Intake
   sanitization").
2. The **ground-truth spec** — the frozen spec the ride actually produced —
   presented as `REFERENCE`, never as one of the candidates.
3. Three **candidate specs + briefs** labelled `A`, `B`, `C`.

The judge receives **no variant names, no prompt texts, no byte counts, no PR
numbers, no commit refs, and no ordering hint**. Labels are re-randomized per
task, so a judge who guesses "A is always the same variant" gains nothing.

### Harness-enforced blinding (AC-003)

- Candidate artifacts are written to `A.md` / `B.md` / `C.md` and any string
  matching `V0|V1|V2|PLANNING\.prompt|altitude-variants` is stripped from them
  before the judge is dispatched.
- The label→variant mapping exists **only** inside
  `docs/analysis/altitude-blinding.b64`, base64-encoded. It is not restated in
  this document, in the replay results table, or in any run log.
- Tamper check: `sha256` of the decoded plaintext is
  `3196b5230c9239f2ed0ba556fb0760c751b5b919da2b1f2c0ea8a9b1ba433a84`.
  Verify before decoding; a mismatch invalidates the run.
- Decode **only after every judge score for all nine tasks is written down**:
  `base64 --decode < docs/analysis/altitude-blinding.b64` (this spelling works on
  both BSD/macOS and GNU coreutils; bare `base64 -d <file>` fails on BSD).
- Two judges score independently on different models; a third breaks ties on any
  metric where they differ by ≥2 points. Judges never see each other's scores.

## Metrics

### Scored 0-5 (integer)

**M1 — AC measurability** *(absolute; no reference needed)*
Does each Spec-AC name a command, an artifact and an observable that decides it?

| score | meaning |
|---|---|
| 5 | every AC names command + artifact + observable; thresholds numeric |
| 4 | one AC leaves the observable implicit but it is unambiguous |
| 3 | most ACs measurable; ≥2 rely on a reader's judgement ("works correctly") |
| 2 | roughly half the ACs are unfalsifiable as written |
| 1 | measurable only by accident; adjectives instead of thresholds |
| 0 | no AC could fail a competent implementation |

**M2 — Scope fidelity vs the ground-truth spec** *(reference required)*
Does the candidate's scope match what the ride actually turned out to need?

| score | meaning |
|---|---|
| 5 | same surfaces, same deliverables; differences are wording only |
| 4 | one deliverable missing or added, non-load-bearing |
| 3 | one load-bearing deliverable missing OR one substantial addition |
| 2 | two or more load-bearing mismatches |
| 1 | recognisably the same problem, materially the wrong scope |
| 0 | different problem |

Judge on **deliverables and surfaces**, not on AC count. A candidate that covers
the same surfaces more crisply scores 5.

**M3 — Evidence-contract fit to strategy** *(reference required for the recorded
strategy only)*
Given the strategy the candidate itself recommends, does the demanded evidence
match `SPEC_TEMPLATE.md ### Evidence by strategy`?

| score | meaning |
|---|---|
| 5 | strategy is decided and every AC's evidence matches its row exactly |
| 4 | one AC over- or under-demands, harmlessly |
| 3 | a `direct`/`untested` ride demands a stored RED artifact, or a `tdd` ride waives one |
| 2 | the strategy is stated but the evidence contract ignores it throughout |
| 1 | evidence demands are generic boilerplate |
| 0 | strategy `undecided`, or no evidence contract at all |

M3 is the metric `spec-lint --strategy` would partially compute
(`strategy-evidence-mismatch`); the judge scores the whole contract, not just the
lintable half.

### Counted (integers, lower is better)

**M4 — Overreach count.** Requirements in the candidate that are real and
sensible but were **not** part of what the ride delivered, and are not implied by
the intake. Count one per distinct deliverable, not per AC row.

**M5 — Underreach count.** Deliverables present in the ground-truth spec and
traceable to the intake that the candidate simply omits. Count one per
deliverable. A missing COMPANION-OBLIGATIONS companion on T3/T4/T6 counts here.

**M6 — Hallucinated requirements count.** Requirements referencing a file,
script, flag, config key or convention that **does not exist** at `base_ref`.
This is the Planning analogue of the phantom-`process.getpgrp()` class from
`LEARNED.md` 2026-08-02, and it is checkable mechanically: for each named path or
flag, `git cat-file -e <base_ref>:<path>` or a grep of the script's argument
parser. The judge must list each one, not just the total.

### Recorded, not judged

Tokens per run (usage marker), wall-clock, output bytes (spec + brief). These
feed D4 and the honest cost table; they are not part of any 0-5 score.

## Pre-registered decision rule, restated for these metrics

The intake's D1-D4 were written for a review role scored on defect recall. The
concrete Planning equivalents, fixed **before any run**:

- **D1 (no quality regression)** — original: "recall of ground-truth defects:
  V2 >= V0 on the paired sign test". Here: on the **paired per-task composite
  Q = M1 + M2 + M3** (0-15), V2 ≥ V0. Test: sign test over the 9 paired
  differences `Q(V2) − Q(V0)`, one-sided, ties dropped; adopt only if V2 is not
  significantly worse (p > 0.05 against V2 being lower) **and** the median paired
  difference is ≥ 0. Additionally V2 must not lose on M5 (underreach) by more
  than 1 in median — a shorter prompt that silently drops obligations fails D1
  even if its ACs read better.
- **D2 (compliance survives deletion)** — original: "probe suite 100 % green".
  Here: the five behavioral probes from
  `docs/analysis/altitude-disposition-PLANNING.md` (rows R04, R05, R09, R21, R31)
  must be **written and green for V2** before adoption. Until those probes exist,
  D2 is unmet by construction and no adoption may be recorded regardless of D1.
- **D3 (no extra noise)** — original: "false findings: V2 <= V0 + 1 median".
  Here: `M4 + M6` (overreach + hallucinated) median for V2 ≤ median for V0 + 1.
- **D4 (no cost regression)** — unchanged in spirit: median tokens/run for V2 ≤
  median tokens/run for V0.

**Adopt V2 for PLANNING iff D1 ∧ D2 ∧ D3 ∧ D4.** Any other outcome is recorded
verbatim, including a null.

**Mechanism call (V2 vs V1).** Compare `Q(V2)` against `Q(V1)` on the same paired
sign test. If the paired median difference is 0 or the sign test does not
separate them at n=9, record *"compression suffices — altitude unproven here"*
and fold the finding into ordinary diet rides. If V1 ≥ V2 on Q while V1 is also
cheaper, the honest conclusion is that the intake's H2 is **falsified** on this
pilot; write that down. V1 and V2 are within 3.3 % of each other in bytes
(8,109 vs 7,841 against V0's 11,526), so a difference between them cannot be
attributed to size.

## Statistics

- **Paired only.** Per task, compute `Q(V2) − Q(V0)`, `Q(V2) − Q(V1)`,
  `Q(V1) − Q(V0)`. The intake's measured run-token CV of 21-31 % makes any
  unpaired comparison underpowered at n=9; pairing removes per-task difficulty.
- **Sign test at n=9.** With 9 pairs and no ties, 8/9 in one direction gives
  p = 0.020 one-sided; 7/9 gives p = 0.090. Pre-registering this makes the power
  limit explicit: **only a near-sweep is significant**, and a 5-4 split is a null,
  not a "slight edge".
- **Publish the raw 9×3 table** of M1-M6 plus tokens in
  `docs/analysis/altitude-replay.md`, before any aggregation, with per-task
  judge disagreements shown. No cherry-picking, no dropped tasks; a run that
  errored is reported as errored.

## Judge prompt skeleton (verbatim shape)

> You are scoring three candidate implementation specs against one task intake.
> You are told nothing about how they were produced and you must not speculate.
> REFERENCE below is the spec this task actually shipped; treat it as ground
> truth for scope only. Score each of A, B, C independently on M1, M2, M3 (0-5)
> and count M4, M5, M6, listing each counted item. Do not rank. Do not guess
> which candidate came from which process. Output one YAML block per candidate.

Nothing in the judge dispatch names a variant, a prompt style, a byte count, or
this document's hypotheses.
