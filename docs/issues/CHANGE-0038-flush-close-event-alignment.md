---
id: flush-close-event-alignment
type: change
number: 38
status: draft
links:
  pr: []
  commits: []
---

# Change — metrics-flush must not emit wrong-ref / wrong-status close events

## Summary
- `metrics-flush.mjs` emits `doc_lifecycle --from implementing --to done` and
  `work_item_closed` keyed on the STATE work-item `ref_id`. Two defects: the
  `from` state is hardcoded `implementing` (wrong when the doc was `draft`), and
  the ref is the STATE ref_id, which may be a NUMBERED id — but the docs-audit
  matches close events on the doc's slug `id`, so a numbered-ref event never
  matches and leaves the doc flagged `probable-false-done`/`false-open`. It also
  now DOUBLE-emits lifecycle events with the deterministic close ceremony
  (`close-work-item.mjs`, CHANGE-0037), which is the correct single source.

## Motivation / Business Value
- These are the OTHER half of the false-open/false-done trips seen repeatedly
  this session (the close-ceremony half was fixed in CHANGE-0037). A flush that
  emits a numbered-ref or wrong-`from` lifecycle event silently misrepresents
  governance state and can trip the audit even after a correct close. With
  `close-work-item.mjs` now owning the close lifecycle correctly-by-construction,
  flush's parallel emission is redundant AND buggy.

## Scope
- In scope: `.aai/scripts/metrics-flush.mjs` event-emission block (the
  `doc_lifecycle`/`work_item_closed` append-event calls ~lines 555-565); its
  test coverage; any prompt (`METRICS_FLUSH.prompt.md`) that describes flush as
  the close-event emitter.
- Out of scope: the metrics ledger computation itself (unchanged); worktree
  telemetry reconciliation (separate follow-up).

## Affected Area
- metrics flush; docs governance event integrity.

## Desired Behavior (To-Be)
- Decide and freeze ONE of:
  (A) flush STOPS emitting `doc_lifecycle`/`work_item_closed` — the close
      ceremony (`close-work-item.mjs`) is the single source of the close
      lifecycle; flush does only the metrics ledger; OR
  (B) if flush must still emit them for standalone-flush contexts (flush without
      a subsequent close ceremony), it emits with the doc's SLUG `id` ref form
      (resolved from the doc, not the STATE ref_id) and the ACTUAL `from` status
      read from the doc — never a hardcoded `implementing` — and is idempotent
      (no duplicate if the close ceremony already emitted them).
- Whichever is chosen, a flush of a `draft`-closed or numbered-ref work item
  must leave the audit CLEAN (no false-done/false-open from flush's events).

## Acceptance Criteria
- AC-001: flushing a work item whose doc is closed from `draft` does NOT emit a
  `doc_lifecycle --from implementing` (either no lifecycle event, or `from` =
  the doc's actual prior status).
- AC-002: flush emits no close event in a ref form the audit cannot match — a
  post-flush `docs-audit` is CLEAN with no `probable-false-done`/`false-open`
  attributable to flush, including when the STATE ref_id is a numbered id.
- AC-003: no double-emission — running flush and then `close-work-item.mjs`
  (or vice-versa) yields at most one `work_item_closed` / one terminal
  `doc_lifecycle` per doc (idempotent across the two tools).
- AC-004: the metrics ledger output (METRICS.jsonl record) is unchanged;
  existing metrics-flush tests stay green.

## Verification
- Test fixtures: flush a draft-closed item + a numbered-ref item; assert audit
  CLEAN and correct/absent lifecycle events; a flush-then-close and
  close-then-flush sequence assert single emission. Existing suites green.

## Constraints / Risks
- Deterministic; reuse `append-event.mjs`; do not fork the metrics computation.
- If option A (remove emission), confirm no flow relies on flush as the SOLE
  close-event emitter (the canonical flow runs close-work-item.mjs; verify the
  aai-flush skill path).

## Notes
- Source: CHANGE-0037/SPEC-0053 Planning note (R3) + the false-open trips this
  session (CHANGE-0027/0035 numbered-ref, SPEC-0046 draft-flip). Completes the
  "close/flush event correctness" story begun by close-work-item.mjs.
