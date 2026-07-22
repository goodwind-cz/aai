---
id: spec-metrics-flush-sweep
type: spec
number: 68
status: draft
ceremony_level: 2
links:
  requirement: metrics-flush-strands-completed-refs
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec: metrics-flush `--sweep` (durable-provenance multi-ref flush)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0022-metrics-flush-strands-completed-refs.md (id: metrics-flush-strands-completed-refs)
- Decision records: SPEC-0054/CHANGE-0038 (flush is metrics-ledger-only; close-work-item.mjs owns the close lifecycle); CHANGE-0037/SPEC-0053 (close-work-item.mjs self-verify audit)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: per template

## Problem (WHAT/WHY lives in the intake — this is HOW)

`metrics-flush.mjs` flushes ONLY the single work item named by the transient
`last_validation` singleton (gate at metrics-flush.mjs ~597:
`vStatus === 'pass' && refMatches(vRef, ref)`). Every other completed item is
skipped, and once the loop moves on the verdict is overwritten, so the item can
NEVER be flushed — it strands in `STATE.metrics.work_items` and never reaches
the committed `docs/ai/METRICS.jsonl` ledger (this repo currently strands
`pr-67-post-merge-review`, and 12+ done items were reported downstream). This
spec adds an OPT-IN `--sweep` mode that flushes EVERY stranded entry carrying
DURABLE completion provenance, re-anchoring the truth-scoring guarantee on
tamper-evident committed proof instead of the transient singleton — with NO
STATE schema change (stays entirely in metrics-flush.mjs, an L2 surface).

## Design decisions (frozen)

### D1 — The provenance gate for a swept ref (STRICT / fail-closed)
A stranded `metrics.work_items` entry `ref` is SWEPT in `--sweep` mode iff ALL
hold:
1. it is NOT already in the ledger (`inLedger` — else the existing resume path
   handles it, cleanup-only, no second append);
2. `entry.runs.length > 0` (existing skip reason kept — nothing to move);
3. a committed `work_item_closed` event exists in `docs/ai/EVENTS.jsonl` whose
   `event === 'work_item_closed' && ref === entry.ref` (EXACT ref match — the
   same predicate `close-work-item.mjs:hasWorkItemClosed` uses); AND
4. `active_work_items[ref].status === 'done'` (corroboration in STATE).

**The close event is REQUIRED, not optional.** A `done`-without-close ref is
LEFT STRANDED and REPORTED (`SKIP <ref>: no durable work_item_closed event in
EVENTS.jsonl — fail-closed`), never flushed. A close-event-without-done ref
(active_work_items status is in_progress/blocked/planned, i.e. still in flight)
is likewise NOT swept and reported — the in-flight item must never be disturbed.

Rationale (why the STRICTER option, justified against the truth-scoring
guarantee): the `work_item_closed` event is stamped by `close-work-item.mjs`
ONLY after its self-verify audit passes against the REAL docs-audit engine
(status-flip-first, then the event, with total rollback on any self-verify
failure — close-work-item.mjs D6). It is committed, append-only, and
tamper-evident — a STRICTLY STRONGER completion proof than the per-dev,
mutable, transient `last_validation` singleton. Accepting `done`-status alone
would let a hand-set STATE flag fabricate a PASS ledger line for work that never
legitimately closed — exactly the truth-scoring violation the single-ref gate
exists to prevent. Requiring the durable event preserves that guarantee while
removing the single-ref restriction. (Constitution Art. 1 "evidence before
claims"; Art. 4 "degrade and report".)

### D2 — Default behaviour BYTE-UNCHANGED (`--sweep` is purely additive)
With NO `--sweep` flag the eligibility gate is the EXACT current logic
(last_validation PASS names the ref + code_review pass/waived when required +
runs>0). `--sweep` only ADDS a second acceptance path per entry: an entry
flushes if the DEFAULT gate passes (the current-validation ref) OR the D1 sweep
gate passes. It never removes or weakens any ref the default path would flush.
`EVENTS.jsonl` is READ only when `--sweep` is set (default mode never opens it,
so the "flush never touches EVENTS" invariant and its tests stay green).

### D3 — Targeted sweep `--sweep --ref <X>` composes for free
The existing `--ref` restriction (`if (opts.ref && ref !== opts.ref) skip`)
already filters entries before any gate; `--sweep --ref X` therefore sweeps ONLY
X and reports every other stranded ref as `not selected (--ref restriction)`.
No extra code beyond the D1 gate — supported and tested.

### D4 — Idempotence + safety (reuse existing discipline, add nothing)
- `inLedger` + still-in-STATE → existing resume path (cleanup-only, no duplicate
  ledger line) — unchanged, now also reached by swept refs.
- A second `--sweep` after a successful sweep is a no-op: the entries are gone
  from `metrics.work_items`, nothing matches → `Nothing to flush.`
- `runs.length === 0` stays skipped; every stranded ref NOT swept is reported
  with its named reason.
- The in-memory pre-validation (`duplicateKeys` / `inlineChildConflicts`),
  integrity refusal (nothing written, original preserved), ledger-before-STATE
  ordering, atomic tmp+rename commit, and post-commit `check-state` are ALL
  reused unchanged — the sweep only widens which entries enter `toFlush`.

### D5 — STATE hygiene (reuse `removeMetricsEntries` / `removeDoneWorkItems`)
`completedRefs` gains the swept refs; the existing
`removeMetricsEntries(lines, completedRefs)` +
`removeDoneWorkItems(lines, completedRefs)` remove each flushed entry AND its
`status: done` active_work_items entry surgically. `removeDoneWorkItems` already
removes ONLY `status === 'done'` items, so non-done/in-flight items are untouched
by construction. The existing full-vs-partial reset branch composes: after
removal, remaining in-flight items keep STATE from full-resetting (partial reset
applies only to refs matching `current_focus`/`last_validation`, so a swept
non-focus ref never triggers a spurious verdict-block reset).

## Constitution deviations

None.

- Art. 1 (evidence before claims): upheld — the sweep gate REQUIRES a committed
  self-verified `work_item_closed` event before any PASS ledger line (D1).
- Art. 2 (simplicity/YAGNI): upheld — additive gate + one events-read helper;
  reuses all existing removal/reset/transaction machinery, no new schema.
- Art. 3 (portability): upheld — plain Node stdlib, git-diffable JSONL/YAML only.
- Art. 4 (degrade and report): upheld — every un-swept stranded ref is reported
  with a named reason; absent EVENTS.jsonl → fail-closed, not a crash.
- Art. 5 (additive first): upheld — `--sweep`/`--ref` are additive opt-in flags;
  default flush byte-unchanged; prompt edit is additive.
- Art. 6 (single-writer state): upheld — metrics-flush.mjs already writes STATE
  surgically via the shared line engine; NO `state.mjs`/schema change (this is
  the L2 constraint that keeps the fix off the L3 protected surface).
- Art. 7 (operator-only merge): not applicable (no merge in this scope).

## Acceptance Criteria Mapping

- Maps to: Verification bullet 1 (opt-in `--sweep` flushes stranded, durably-closed refs)
  - Spec-AC-01: `metrics-flush.mjs` accepts a boolean `--sweep` flag (no value); the
    unknown-flag usage/help string lists `--sweep`; `opts.sweep` defaults false.
  - Spec-AC-02: In `--sweep` mode a stranded `metrics.work_items` entry is FLUSHED iff
    the D1 gate holds (committed `work_item_closed` for the ref AND
    `active_work_items[ref].status==='done'` AND `runs>0` AND not-in-ledger); the
    appended ledger line is shape-identical to a normal flush (same key set/order,
    `verdict:"PASS"`, strategy+reliability fields).
  - Verification: `test-aai-metrics.sh test_1XX_sweep_flushes_closed` — exit 0, exactly
    one new ledger line for the stranded ref, golden key-set assertion.
- Maps to: Verification bullet 3 (a stranded entry WITHOUT durable provenance is NOT flushed — fail closed)
  - Spec-AC-03: In `--sweep` mode a stranded `done` ref with NO `work_item_closed`
    event is SKIPPED + reported (`no durable work_item_closed event`), ledger
    byte-unchanged; a ref with a close event but non-done (in-flight)
    active_work_items status is NOT swept and reported.
  - Verification: `test_1XX_sweep_fail_closed` — ledger `cmp -s` byte-identical, report
    names the fail-closed reason, in-flight item byte-present.
- Maps to: Verification bullet 2 (DEFAULT no-flag behaviour BYTE-UNCHANGED)
  - Spec-AC-04: With NO `--sweep` flag the flush is byte-identical to today; the full
    existing suite (TEST-006..023) stays green; a stranded-but-closed non-focus ref
    stays SKIPPED without the flag.
  - Verification: full `test-aai-metrics.sh` green; `test_1XX_default_unchanged` re-runs
    the TEST-006 golden path and asserts a byte-identical ledger line + non-focus ref skipped.
- Maps to: Verification bullet 4 (idempotent re-run) + Constraints (never double-flush; resume path)
  - Spec-AC-05: STATE hygiene — after a sweep each flushed ref's `metrics.work_items`
    entry AND its `status: done` active_work_items entry are surgically removed; a
    remaining in-flight item is byte-present; the mutated STATE passes the in-memory
    duplicate/inline-conflict pre-check AND post-commit `check-state`; integrity
    refusal + rollback still hold (nothing written, original preserved) when the
    planned STATE would be structurally invalid.
  - Spec-AC-06: A second `--sweep` after a successful sweep is a no-op
    (`Nothing to flush.`, ledger unchanged); a swept ref already in the ledger but
    still in STATE (interrupted flush) takes the existing resume cleanup-only path
    with no duplicate ledger line.
  - Verification: `test_1XX_sweep_state_hygiene`, `test_1XX_sweep_integrity_refusal`,
    `test_1XX_sweep_idempotent` (incl. `AAI_FLUSH_INJECT_CRASH=after-ledger` resume).
- Maps to: Constraints (multi-ref sweep) + intake note (targeted single-ref sweep)
  - Spec-AC-07: `--sweep --ref X` restricts the sweep to the single stranded ref X;
    other stranded closed refs report `not selected (--ref restriction)`.
  - Verification: `test_1XX_sweep_targeted_ref`.
- Maps to: Constraints (stays metrics-ledger-only; never touch EVENTS) + SEAM-1
  - Spec-AC-08: EVENTS.jsonl is READ-ONLY in sweep mode — flush never creates or
    writes EVENTS.jsonl; absent EVENTS in `--sweep` → all stranded refs fail-closed;
    a REAL `close-work-item.mjs`-produced `work_item_closed` event is the exact record
    the sweep reads (cross-tool seam), and existing "flush never touches EVENTS" tests
    (TEST-012/019) stay green.
  - Verification: `test_1XX_sweep_seam_close_then_sweep` (integration, no mock) +
    absent-EVENTS fail-closed assertion + `[[ ! -f EVENTS.jsonl ]]` after a sweep that
    started without one.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | `--sweep` boolean flag parsed; listed in usage; defaults false    | done | test-aai-metrics.sh TEST-101 PASS 2026-07-22 | — | — |
| Spec-AC-02 | Sweep flushes a stranded durably-closed ref; ledger shape-identical | done | test-aai-metrics.sh TEST-102 PASS 2026-07-22 | — | — |
| Spec-AC-03 | Fail-closed: no close event (or in-flight) → skip + report, ledger untouched | done | test-aai-metrics.sh TEST-103 PASS 2026-07-22 | — | — |
| Spec-AC-04 | Default (no flag) byte-unchanged; existing suite green            | done | test-aai-metrics.sh TEST-104 + full suite (TEST-006..023) PASS 2026-07-22 | — | — |
| Spec-AC-05 | STATE hygiene: surgical removal + integrity refusal/rollback hold | done | test-aai-metrics.sh TEST-105/106 PASS 2026-07-22 | — | — |
| Spec-AC-06 | Idempotent re-run + interrupted-flush resume, no double-flush     | done | test-aai-metrics.sh TEST-107 PASS 2026-07-22 | — | — |
| Spec-AC-07 | `--sweep --ref X` targeted single-ref sweep composes             | done | test-aai-metrics.sh TEST-108 PASS 2026-07-22 | — | — |
| Spec-AC-08 | EVENTS.jsonl read-only in sweep mode; real close-event seam       | done | test-aai-metrics.sh TEST-109 PASS 2026-07-22 | — | — |

## Implementation plan

### Components/modules affected
- `.aai/scripts/metrics-flush.mjs` (L2 — the ONLY behavioural change):
  - `parseArgs`: add `sweep: false`; parse `--sweep` as a boolean like
    `--dry-run`; add `--sweep` to the unknown-flag valid-list message.
  - Add a `closedRefs(eventsPath)` read helper (mirror `ledgerRefs`): best-effort
    JSONL parse, return `Set` of `ref` for lines where
    `event === 'work_item_closed'`. Read ONLY when `opts.sweep` (never create the
    file; return empty Set when absent).
  - Build a done-status lookup from `parseWorkItems(origLines)` (status by ref).
  - In the eligibility loop, when `opts.sweep`, add the D1 acceptance path as an
    OR alongside the existing default gate; keep every existing skip reason and
    add the two fail-closed reasons (no close event / in-flight not-done).
  - Extend the `--dry-run` plan JSON with the swept refs (fold into `flush`).
  - Everything downstream (`buildEntry`, `removeMetricsEntries`,
    `removeDoneWorkItems`, reset branch, pre-validation, integrity refusal,
    ledger-before-STATE, post-commit check-state, reporting) is REUSED unchanged.
- `tests/skills/test-aai-metrics.sh` (L2): add the sweep tests (fixture STATE +
  fixture EVENTS.jsonl in the scratch temp repo; real docs/ai files NEVER
  touched). Register them in `main()`.
- `.aai/METRICS_FLUSH.prompt.md` (L2): add a one-line `--sweep` mention (opt-in
  multi-ref sweep of durably-closed stranded refs). ADDITIVE prose.
- `tests/skills/lib/prompt-diet-ledger.sh` (L2, conditional): if the prompt edit
  pushes corpus headroom above `HEADROOM_CAP` (2048), add ONE
  `JUSTIFIED_ADDITIONS+=("<deficit> metrics-flush-strands-completed-refs --sweep mention")`
  true-up line (TEST-010 of test-aai-prompt-diet.sh echoes the exact deficit to
  paste). Skip the edit if headroom is not breached.

### Data flows
- READ (sweep only): `docs/ai/EVENTS.jsonl` → set of refs with a committed
  `work_item_closed` event (durable provenance).
- READ: `STATE.metrics.work_items` (stranded entries) + `active_work_items`
  (done-status corroboration) + `last_validation`/`code_review` (default gate).
- WRITE: append PASS ledger line(s) to `METRICS.jsonl`; surgical removal of the
  flushed metrics + done active_work_items entries in `STATE.yaml`. EVENTS.jsonl
  is NEVER written.

### Edge cases
- `runs.length === 0` on a closed ref → existing skip kept.
- Ref in ledger + still in STATE (interrupted flush) → existing resume path.
- Absent EVENTS.jsonl under `--sweep` → empty closed-set → every stranded ref
  fail-closed/reported; EVENTS.jsonl NOT created.
- Ref-form mismatch (numbered STATE ref vs slug close-event ref) → EXACT match
  fails → fail-closed skip (RESIDUAL RISK below).
- Cost/pricing + timing untouched (from each entry's own `agent_runs`);
  null-token WARNING lines still fire per run.

### Seam analysis (SEAM-1)
The sweep provenance gate READS a `work_item_closed` event that
`close-work-item.mjs` WRITES (via `append-event.mjs`). This is a cross-tool
seam: the record produced on the close side must be the exact record the sweep
consumes. TEST-109 crosses it end-to-end with the REAL `close-work-item.mjs`
(no mock): produce the event by closing a work item, then sweep and assert the
ref flushes. RESIDUAL RISK (recorded): when the STATE `metrics.work_items` key
is a NUMBERED id but the committed close event carries the doc's SLUG id (the
exact mismatch TEST-020 documents), the EXACT-match gate fail-closes and the ref
stays stranded+reported rather than flushed. This is the SAFE failure direction
(never a fabricated PASS); broadening the match to `refMatches` is deliberately
OUT OF SCOPE (would reintroduce ambiguity into a truth-scoring gate).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                                   | Status  |
|----------|------------|-------------|-------------------------------------|---------------------------------------------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh    | `grep -c -- --sweep` in metrics-flush.mjs ≥1; `--sweep` accepted (exit 0); usage/help string lists `--sweep`.  | green  |
| TEST-102 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh    | Fixture STATE stranded done ref B (not last_validation) + fixture EVENTS `work_item_closed` B → `--sweep` flushes B: exactly one ledger line, golden key-set/order, verdict PASS. | green  |
| TEST-103 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh    | Stranded done ref with NO close event → `--sweep` SKIP + named reason, ledger `cmp -s` byte-identical; ref with close event but in_progress status NOT swept, byte-present. | green  |
| TEST-104 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh    | No-flag run reproduces TEST-006 golden ledger byte-for-byte; a stranded-but-closed non-focus ref stays SKIPPED without `--sweep`. | green  |
| TEST-105 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh    | `--sweep` of two done closed refs while an in_progress ref remains: both metrics + both done active_work_items removed, in_progress item byte-present, partial (not full) reset, check-state green. | green  |
| TEST-106 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh    | Structurally-invalid planned STATE (pre-existing duplicate top-level key) under `--sweep` → exit 1 integrity refusal, STATE original preserved, ledger untouched. | green  |
| TEST-107 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh    | Two `--sweep` runs: second is `Nothing to flush.`, ledger unchanged; plus `AAI_FLUSH_INJECT_CRASH=after-ledger` then `--sweep` resume → cleanup-only, no duplicate ledger line. | green  |
| TEST-108 | Spec-AC-07 | integration | tests/skills/test-aai-metrics.sh    | `--sweep --ref B` with two stranded closed refs → only B flushes; E reported `not selected (--ref restriction)`. | green  |
| TEST-109 | Spec-AC-08 | integration | tests/skills/test-aai-metrics.sh    | SEAM-1: `mk_seam_repo`, run REAL `close-work-item.mjs` to produce a genuine `work_item_closed`, then `metrics-flush --sweep` flushes the ref (no mock); absent-EVENTS `--sweep` fail-closes and creates no EVENTS.jsonl. | green  |

Notes:
- Every Spec-AC has ≥1 TEST-xxx. Test IDs stable — do not renumber after freeze.
- RED-proof (observed): `grep -c -- --sweep .aai/scripts/metrics-flush.mjs` → 0
  today, so TEST-101/102/108/109 cannot pass without the change; TEST-102's
  stranded-but-closed fixture is currently SKIPPED by the single-ref gate
  (observed RED baseline). Each AC-gating test MUST be observed failing before
  its green counts.
- All fixtures are scratch temp-dir repos via the path-override flags
  (`--state/--metrics/--events/--ticks/--pricing`); the real `docs/ai/STATE.yaml`
  and `docs/ai/METRICS.jsonl` are NEVER mutated by the suite.

## Verification
- Commands:
  - `bash tests/skills/test-aai-metrics.sh` (full suite; TEST-006..023 must stay green + new TEST-101..109 green)
  - `bash tests/skills/test-aai-metrics.sh test_1XX_<name>` (per-test, for TDD RED/GREEN evidence)
  - `bash tests/skills/test-aai-prompt-diet.sh` (green after any prompt edit + ledger true-up)
  - `grep -c -- --sweep .aai/scripts/metrics-flush.mjs` (RED-proof baseline: 0 pre-change)
- PASS criteria: all TEST-101..109 green AND the pre-existing TEST-006..023 green
  AND the prompt-diet suite green AND every Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code-review artifact record:
- ref_id: metrics-flush-strands-completed-refs
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (test log / ledger diff / RUN_ID)
- commit SHA or diff range when available

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the sweep eligibility gate and the
  surgical STATE removal — a truth-scoring, data-integrity gate that must be
  observed failing on a stranded-but-closed fixture and fail-closed on an
  unproven one (TEST-102/103/105/106/109); loop for the low-risk argv/prompt/
  ledger wiring (TEST-101/104/108) where RED-GREEN adds little signal.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single script + one test file + one prompt line + one
  conditional ledger line, all L2 and additive; a dedicated branch
  (`feat/metrics-flush-sweep`) already isolates it. No schema/protected surface.
- User decision: undecided
- Base ref: feat/metrics-flush-sweep (off main)
- Worktree branch/path: n/a
- Inline review scope: `.aai/scripts/metrics-flush.mjs`,
  `tests/skills/test-aai-metrics.sh`, `.aai/METRICS_FLUSH.prompt.md`,
  `tests/skills/lib/prompt-diet-ledger.sh` (if the true-up line is added)

## Review plan
- code_review.required: true (code + test + prompt change)
- Scope: the four paths above (diff range on `feat/metrics-flush-sweep` vs main)

## Ceremony
- ceremony_level: 2 (full pipeline; default)
- L2 justification: no scope path is in `protected_paths_l3`
  (docs/ai/docs-audit.yaml lists only state.mjs, lib/state-engine.mjs,
  lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
  WORKFLOW.md, CONSTITUTION.md). `metrics-flush.mjs`, `test-aai-metrics.sh`,
  `METRICS_FLUSH.prompt.md`, and `prompt-diet-ledger.sh` are all L2. The design
  deliberately makes NO STATE schema change (no state.mjs edit) precisely to
  avoid forcing L3 + a mandatory worktree.
- Prompt-diet true-up (if prompt edited): add a single JUSTIFIED_ADDITIONS ledger
  line in `tests/skills/lib/prompt-diet-ledger.sh` and re-run
  `test-aai-prompt-diet.sh`.
