---
id: spec-flush-close-event-alignment
type: spec
number: 54
status: draft
ceremony_level: 2
links:
  requirement: flush-close-event-alignment
  rfc: null
  pr: []
  commits: []
---

# SPEC — metrics-flush stops emitting close lifecycle events (CHANGE-0038)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0038-flush-close-event-alignment.md
- Prior art (the correct close source): docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md
  (`close-work-item.mjs`, CHANGE-0037)
- False-open/false-done heuristics: .aai/scripts/lib/docs-audit-core.mjs
  (`falseOpenEvidence` Arm C `work_item_closed`, ~L300; `missing-close-telemetry`, ~L768)
- Technology contract: docs/TECHNOLOGY.md
- Expected merge number: SPEC-0054 (highest allocated across local + all
  `origin/*` branches is SPEC-0053; verified 2026-07-18). The sequential
  integer is reserved/stamped at PR by `allocate-doc-number.mjs`; the file is
  born `SPEC-0054-spec-flush-close-event-alignment.md` with `number: null`.

## Problem (frozen understanding, evidence-backed)

`metrics-flush.mjs`'s `emitEvents()` (L547-569, called at L721) appends, for
EVERY ref in `completedRefs`:
- `doc_lifecycle --from implementing --to done`  (the `from` is HARDCODED)
- `work_item_closed --validation pass --code-review <token>`

`completedRefs` = the keys of STATE `metrics.work_items` (the STATE ref_ids).
Three defects, all confirmed against the golden pair CHANGE-0034/SPEC-0045 in
docs/ai/EVENTS.jsonl:
1. WRONG from-status — L612 is flush's `doc_lifecycle from=implementing`, while
   the doc was actually `draft` (L614 is `close-work-item.mjs`'s correct
   `from=draft`). Hardcoded `implementing` is a lie whenever the doc closed
   from `draft`/`accepted`.
2. WRONG ref form — the STATE ref_id may be a NUMBERED id, but the audit matches
   close telemetry on the doc's frontmatter SLUG `id`
   (`missing-close-telemetry`, docs-audit-core.mjs L768-772, matches `id` only,
   not `fileId`). A numbered-ref `work_item_closed` never clears
   `missing-close-telemetry` for a slug-id doc and can trip
   `probable-false-open` Arm C when it matches a still-open doc's `fileId`.
3. DOUBLE-EMIT — `close-work-item.mjs` (SPEC-0053) now owns the close lifecycle
   correctly-by-construction (bare slug ref, ACTUAL from-status, self-verified,
   idempotent). Flush's parallel emission is redundant AND buggy; the golden
   pair shows two `doc_lifecycle` rows for the same doc (L612 wrong-from + L614
   correct-from).

Temporal hazard: flush frequently runs BEFORE the close ceremony (golden pair —
flush at 15:22:32, `close-work-item.mjs` at 15:22:56). So flush's
`work_item_closed` lands on a doc whose on-disk frontmatter is still
`draft`/`implementing` (flush never flips frontmatter), which is exactly the
`probable-false-open` Arm C trip condition.

## Frozen design decision — OPTION A

`metrics-flush.mjs` STOPS emitting `doc_lifecycle` and `work_item_closed`
entirely. `close-work-item.mjs` (CHANGE-0037/SPEC-0053) is the SINGLE SOURCE OF
TRUTH for the close lifecycle. Flush does ONLY the metrics ledger + surgical
STATE cleanup + ephemeral cleanup (all unchanged).

### Rationale against the ACTUAL flow (why A, not B or hybrid)
1. Flush does not own the doc lifecycle. It never flips frontmatter to `done`
   (.aai/VALIDATION.prompt.md step 8b: "The `done` transition itself — and its
   `doc_lifecycle` event — is performed by `close-work-item.mjs`"). A tool that
   does not perform the transition emitting `doc_lifecycle --to done` /
   `work_item_closed` is a category error — the hardcoded `--from implementing`
   is the symptom.
2. `close-work-item.mjs` ALWAYS runs in the canonical close flow
   (.aai/SKILL_PR.prompt.md step 5c) and is idempotent + self-verifying against
   the REAL docs-audit engine. It always emits the correctly-reffed (bare slug),
   correct-from-status close set (deduped). Flush's emission is pure redundancy.
3. The "standalone flush as sole close emitter" gap is illusory — and, where
   real, HARMFUL:
   - If the doc is already `done` on disk (close ran earlier), close already
     emitted `work_item_closed` (deduped) → flush emitting again is a duplicate.
     Removing flush's emission removes the duplicate, leaves no gap.
   - If the doc is NOT yet `done` (close has not run), flush's `work_item_closed`
     on a still-open doc TRIPS `probable-false-open` Arm C and
     `doc_lifecycle --to done` claims a transition that did not happen. Emitting
     here is worse than silence. The correct standalone close is to run
     `close-work-item.mjs`, which flips frontmatter AND emits atomically with
     self-verify.
   There is NO flow where flush is a CORRECT sole close emitter. Flush was never
   a reliable close emitter (buggy ref + from-status by construction), so
   removing it is strictly safer than status quo.
4. Option B (flush emits, but resolves the slug + actual-from-status + is
   idempotent) re-implements resolution `close-work-item.mjs` already owns AND
   still hits the ordering hazard (flush runs before close): to be safe it would
   have to "emit only if the doc is already `done` on disk", at which point close
   already emitted and flush emits nothing — B collapses into A with more code.
   Rejected. A hybrid's only "emit" branch (emit when the doc is not yet
   terminal) is precisely the Arm C footgun. Rejected.

### Exact frozen behavior
- Flush emits ZERO `doc_lifecycle` and ZERO `work_item_closed` events. It touches
  docs/ai/EVENTS.jsonl not at all.
- Remove the `emitEvents()` function and its call site (metrics-flush.mjs L721),
  and the now-dead `rRequired ? (rStatus ?? 'none') : 'none'` review-token
  computation that fed it.
- The `--events <path>` CLI flag and `opts.events`/`eventsPath` stay PARSED as an
  ACCEPTED NO-OP (back-compat: existing callers/tests pass `--events`; it must
  not become an "unknown flag" error). Document it as deprecated/no-op in the
  header + `parseArgs`.
- Update the header ORDERING comment (metrics-flush.mjs L34-51) to drop "then
  events (best-effort)". Metrics ledger output (METRICS.jsonl record shape),
  STATE cleanup, ephemeral cleanup, and the exit-code contract are ALL unchanged.
- .aai/METRICS_FLUSH.prompt.md: remove "and the doc_lifecycle + work_item_closed
  events (best-effort)" (L16-18); state that `close-work-item.mjs` owns the close
  lifecycle and flush is metrics-ledger only.

## Ceremony level
`ceremony_level: 2` (full pipeline).
- `metrics-flush.mjs` is NOT on `protected_paths_l3` (docs/ai/docs-audit.yaml
  lists only state.mjs, state-engine, state-core, allocate-doc-number,
  pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md) — L3 is not mandated.
- Not L1: although the code delta is single-surface (one function removed), the
  change alters the semantics of the SHARED, COMMITTED governance log
  (EVENTS.jsonl) and the correctness of the docs-audit close/false-open
  heuristics. That warrants the full pipeline (real RED proof + independent
  validation + code review), so L2 is the honest floor.

## Implementation strategy
- Strategy: tdd
- Rationale: a governance-integrity bug fix that needs regression proof and
  touches data-integrity (the shared EVENTS log + audit correctness). Each
  AC-gating test has a clean RED (current flush emits the wrong-ref/wrong-from
  close events and trips the audit) → GREEN (flush emits nothing, audit CLEAN).
  RED-proof is mandatory and natural here.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, single-script removal + test/prompt edits on the
  already-active branch `fix/flush-close-event-alignment`; operator already chose
  inline (STATE `worktree.user_decision: inline`). No cross-cutting or migration
  risk.
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope:
  - .aai/scripts/metrics-flush.mjs
  - tests/skills/test-aai-metrics.sh
  - tests/skills/test-aai-docs-audit.sh
  - .aai/METRICS_FLUSH.prompt.md

## Seam analysis
SEAM-1 (shared committed EVENTS log ↔ docs-audit ↔ close-work-item): flush
writes docs/ai/EVENTS.jsonl, which docs-audit-core.mjs consumes
(`falseOpenEvidence` Arm C, `missing-close-telemetry`) and `close-work-item.mjs`
co-produces. This is the crux seam. It is covered end-to-end by TEST-002
(flush → run the REAL docs-audit engine → assert CLEAN) and TEST-003/TEST-004
(flush↔close in both orders → assert single emission via the real EVENTS log),
NOT by mocking the boundary. No residual uncovered seam.

## Acceptance Criteria Mapping
- Maps to CHANGE-0038 AC-001 → Spec-AC-01
- Maps to CHANGE-0038 AC-002 → Spec-AC-02
- Maps to CHANGE-0038 AC-003 → Spec-AC-03
- Maps to CHANGE-0038 AC-004 → Spec-AC-04
- New (drift-guard) → Spec-AC-05

- Spec-AC-01: Flushing a work item whose doc closed from `draft` emits NO
  `doc_lifecycle --from implementing` (in fact NO `doc_lifecycle` at all from
  flush). Verification: run flush on a draft-closed fixture; assert flush wrote
  no `doc_lifecycle` line attributable to it.
- Spec-AC-02: Flush emits no close event in a ref form the audit cannot match; a
  post-flush `docs-audit` is CLEAN — no `probable-false-open` /
  `probable-false-done` / `missing-close-telemetry` attributable to flush,
  INCLUDING when the STATE `metrics.work_items` key is a NUMBERED id while the
  doc carries a slug frontmatter `id`. Verification: numbered-ref fixture; run
  the REAL docs-audit engine; assert no flush-attributable finding.
- Spec-AC-03: No double-emission across the two tools — running flush then
  `close-work-item.mjs` (and vice-versa) yields AT MOST one `work_item_closed`
  and one terminal (`--to done`) `doc_lifecycle` per doc. Verification: both
  orderings; count events per ref in EVENTS.jsonl.
- Spec-AC-04: The metrics ledger output (METRICS.jsonl record) is byte/shape
  unchanged and the existing metrics-flush suite stays green. Verification:
  assert the flushed ledger entry deep-equals the pre-change shape; run the full
  tests/skills/test-aai-metrics.sh suite (all green).
- Spec-AC-05: No canonical prose still describes flush as a close-event emitter —
  .aai/METRICS_FLUSH.prompt.md and the flush header no longer claim flush emits
  `work_item_closed`/`doc_lifecycle`; the stale TEST-010 assertion in
  test-aai-docs-audit.sh (L2224, "flush contains work_item_closed") is corrected.
  Verification: grep guards.

## Constitution deviations

None.

- Article 5 (Additive first) — the change REMOVES an event-emission behavior at
  the EVENTS-log boundary. This is permitted: the article allows breaking
  changes when "explicit and documented". It is documented here + in the flush
  prompt + (at PR) CHANGELOG; the `--events` CLI flag stays accepted as a no-op
  so no caller breaks; the removed events were "best-effort" and buggy (never a
  reliable contract), and `close-work-item.mjs` supplies the correct events. No
  unjustifiable deviation → freeze is not blocked.

## Implementation plan
- Component: `.aai/scripts/metrics-flush.mjs`
  - Delete `emitEvents()` (L547-569) and its call at L721.
  - Remove the review-token argument computation feeding that call.
  - Keep `--events`/`opts.events`/`eventsPath` parsed as an accepted no-op;
    annotate deprecated in header + parseArgs comment.
  - Rewrite the header ORDERING bullet (L34-51) to drop the events step.
- Component: `.aai/METRICS_FLUSH.prompt.md` — drop the close-events clause;
  point at `close-work-item.mjs` as the close-lifecycle owner.
- Tests: invert the two existing assertions that lock in the buggy behavior
  (test-aai-metrics.sh L605-608; test-aai-docs-audit.sh L2224) and add the new
  seam-crossing tests below.
- Data flows: flush → METRICS.jsonl (ledger) + STATE (cleanup) ONLY. EVENTS.jsonl
  is no longer a flush output.
- Edge cases: (a) EVENTS.jsonl absent before flush → stays absent (flush never
  creates it); (b) numbered STATE ref_id + slug doc id; (c) resume/interrupted
  flush (`toResume`) — no events either; (d) `--dry-run` plan JSON must no longer
  advertise an events step.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | Draft-closed flush emits no `doc_lifecycle --from implementing`    | done   | TEST-001, docs/ai/tdd/red-20260718T063623Z-test_019_no_close_events_from_flush.log, docs/ai/tdd/green-20260718T064547Z-flush-close-event-alignment-metrics.log | — | emitEvents() + call site removed (metrics-flush.mjs) |
| Spec-AC-02 | Post-flush docs-audit CLEAN incl. numbered STATE ref_id           | done   | TEST-002, docs/ai/tdd/red-20260718T063623Z-test_020_numbered_ref_audit_clean.log, docs/ai/tdd/green-20260718T064547Z-flush-close-event-alignment-metrics.log | — | real docs-audit.mjs run, no probable-false-open/missing-close-telemetry |
| Spec-AC-03 | No double-emission across flush ↔ close-work-item (both orders)    | done   | TEST-003/004, docs/ai/tdd/red-20260718T063623Z-test_021_flush_then_close_no_double_emit.log, docs/ai/tdd/red-20260718T063623Z-test_022_close_then_flush_no_double_emit.log, docs/ai/tdd/green-20260718T064547Z-flush-close-event-alignment-metrics.log | — | both orderings, real EVENTS.jsonl counts |
| Spec-AC-04 | Metrics ledger record unchanged; existing flush suite green       | done   | TEST-005 + TEST-006..018 regression, docs/ai/tdd/green-20260718T064547Z-flush-close-event-alignment-metrics.log | — | ledger key set/order unchanged; full suite 23/23 |
| Spec-AC-05 | No canon/test still describes flush as a close-event emitter       | done   | TEST-006, docs/ai/tdd/red-20260718T063918Z-test_spec0011_closeout_prompts_wired-flush-claim.log, docs/ai/tdd/green-20260718T064547Z-flush-close-event-alignment-docs-audit.log | — | METRICS_FLUSH.prompt.md rewritten; test-aai-docs-audit.sh L2224 inverted |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                                   | Status  |
|----------|------------|-------------|-------------------------------------|--------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh    | Flush a `draft`-closed work item; assert flush writes NO `doc_lifecycle` and NO `work_item_closed` to EVENTS. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh    | Numbered STATE key + slug-id draft doc; flush; run REAL `docs-audit.mjs`; assert no false-open/false-done/missing-close-telemetry attributable to flush. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh    | flush THEN `close-work-item.mjs`; assert exactly one `work_item_closed` and one `--to done` `doc_lifecycle` per ref. | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh    | `close-work-item.mjs` THEN flush; assert flush adds no duplicate close event (same single-emission invariant). | green |
| TEST-005 | Spec-AC-04 | unit        | tests/skills/test-aai-metrics.sh    | Assert the flushed METRICS.jsonl entry deep-equals the pre-change shape; full metrics suite green (regression). | green |
| TEST-006 | Spec-AC-05 | unit        | tests/skills/test-aai-docs-audit.sh | Assert METRICS_FLUSH.prompt.md no longer claims flush emits `work_item_closed`/`doc_lifecycle`; correct the stale L2224 assertion. | green |

Notes:
- RED-proof obligation (all AC-gating tests TEST-001..004, 006): each must be
  observed FAILING against the CURRENT `metrics-flush.mjs` before the change —
  current flush emits the events (TEST-001/003/004 see them; TEST-002 sees the
  audit trip; TEST-006 sees the prompt still claim emission). TEST-005 is the
  regression control (stays green; the ledger-shape assertion is the new witness).
- The two pre-existing assertions that currently lock in the buggy behavior
  (test-aai-metrics.sh L605-608 "events emitted"; test-aai-docs-audit.sh L2224)
  are INVERTED as part of this scope, not left dangling.

## Verification
- Commands:
  - `bash tests/skills/test-aai-metrics.sh` (TEST-001..005; full suite green)
  - `bash tests/skills/test-aai-docs-audit.sh` (TEST-006 + suite green)
  - `bash tests/skills/test-aai-close-work-item.sh` (unaffected — stays green)
  - Real-audit seam: the fixture repos in TEST-002 invoke
    `node .aai/scripts/docs-audit.mjs` and assert CLEAN.
- Evidence: RED/GREEN logs under docs/ai/tdd/; test-suite exit codes.
- PASS criteria: every TEST-xxx green AND every Spec-AC terminal.

## Evidence contract
- ref_id: flush-close-event-alignment
- Spec-AC ↔ TEST links: per the Test Plan table above.
- Commands + expected exit code 0 + evidence path per Verification.
- Commit SHA / PR number stamped at close by `close-work-item.mjs`.

This document defines HOW, not WHAT/WHY. It does not define workflow.
