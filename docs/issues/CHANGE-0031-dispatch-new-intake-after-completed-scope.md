---
id: dispatch-new-intake-after-completed-scope
type: change
number: 31
status: draft
links:
  pr: []
  commits: []
---

# Change — Dispatcher Must Retarget Focus Off a Completed/Flushed Scope

Ceremony justification: deterministic-rule addition confined to
`orchestration-dispatch.mjs`'s `decide()` table (two narrow rule-order
tweaks), no new state schema, no protected-surface expansion beyond the file
itself — L1 per SPEC-0030 (small, well-bounded logic fix with existing test
suites as the regression net). Planning may re-classify upward if the actual
diff touches more than the two named rules.

## Summary
`orchestration-dispatch.mjs`'s deterministic rules cannot retarget
`current_focus` when it still points at a scope whose work item is already
`done`/flushed while a different, open intake document exists. In that
shape, the mechanical rules either fall through to a stale dispatch (Rule 6
re-freezing a closed scope) or fire on residue from a scope that was already
flushed (Rule 11 wanting to re-validate a scope with no live implementation
left to validate), and both cases currently escape to `needs_llm` — costing
an LLM recovery tick for something a deterministic rule should resolve.

## Motivation / Business Value
- Evidence 1 (Rule 6 / stale focus): 2026-07-17 tick 1
  (`docs/ai/LOOP_TICKS.jsonl` line 11) ran
  `"role":"Orchestration+Change Intake"` with
  `"focus_ref_id_before":"CHANGE-0027"` even though CHANGE-0027 had already
  flipped to `status: done` and been flushed the previous session (tick 8,
  2026-07-16T23:48:36Z, `"role":"Orchestration+Metrics Flush"`, and
  `docs/ai/EVENTS.jsonl` line 465 `"event":"work_item_closed","ref":"CHANGE-0027"`
  at 2026-07-16T23:49:01Z). The dispatcher had a fresh open intake
  (`docs-audit-d2-evidence-hardening`) available and had to be steered there
  by the orchestrator rather than retargeting deterministically.
- Evidence 2 (Rule 11 / flushed-scope residue): 2026-07-16 tick 9
  (`docs/ai/LOOP_TICKS.jsonl` line 10) ran
  `"role":"Orchestration (edge resolution)"` with `"exit_code":3` on
  `"scope":"CHANGE-0027"` immediately after the metrics-flush tick — a
  post-flush ("H5-reset") edge the deterministic rule table did not resolve
  on its own, requiring an LLM/edge-resolution pass instead of a mechanical
  rule outcome.
- Both incidents burn an LLM dispatch tick on a shape that is mechanically
  decidable: "current scope is closed/flushed AND exactly one open intake
  exists" has one correct deterministic answer (retarget to the open
  intake), and "a work item is `status: done`" should never be re-offered to
  Rule 11's validation-not-run arm.

## Scope
- In scope:
  - `.aai/scripts/orchestration-dispatch.mjs`: `decide()` rule ordering/
    guards so that (a) when `current_focus` names a work item whose status
    is `done` (or has been flushed / has no active_work_items entry) AND
    exactly one other open intake document exists, the dispatcher
    deterministically issues `set-focus` to that intake and dispatches
    Planning, instead of falling through to a stale rule-6 Planning dispatch
    on the closed scope or to `needs_llm`; (b) Rule 11 (validation not run)
    skips/never fires for a work item whose `status` is `done`.
- Out of scope:
  - Multi-open-intake tie-breaking (more than one open intake with no
    current focus) — remains `needs_llm` (ambiguous, genuinely a judgment
    call); this change only closes the single-open-intake and the
    done-status-residue shapes.
  - Any change to how `Metrics Flush` marks a work item done/flushed, or to
    the flush ceremony itself.

## Affected Area
- `.aai/scripts/orchestration-dispatch.mjs` (`decide()` pure core and the
  snapshot builder, if it needs to surface "other open intake exists" and
  work-item `status`).
- `tests/skills/test-aai-orchestration-dispatch.sh` (new fixtures).

## Desired Behavior (To-Be)
- When `current_focus.ref_id` names a work item that is `status: done` (or
  is absent from `active_work_items` because it was flushed) AND the
  repository has exactly one other open (`draft`/`implementing`) intake
  document with no corresponding `active_work_items` entry yet, the
  dispatcher deterministically: issues `set-focus` to that intake's ref and
  dispatches Planning (or Change/Issue Intake if the doc has no work item
  yet) — no `needs_llm` escape for this specific, unambiguous shape.
- Rule 11 ("implementation exists but validation not run") never fires for a
  work item whose recorded `status` is `done` — a done work item is
  terminal; only `implementing`/`validation`/`remediation`/`code_review`-phase,
  not-done items are eligible, mirroring the existing phase-based guard but
  adding the status check as an explicit skip.
- All other dispatch rules and their existing evidence/ordering are
  unchanged; this is an additive guard plus one deterministic retarget path,
  not a rule-table rewrite.

## Acceptance Criteria
- AC-001: Given a fixture STATE where `current_focus` names a `status: done`
  work item and exactly one open intake document exists with no matching
  active work item, the dispatcher output is `set-focus` to that intake's ref
  followed by a Planning (or Intake) dispatch — never `needs_llm` and never a
  stale Rule 6 Planning dispatch on the closed scope.
- AC-002: Rule 11 fixture with a `status: done` work item and
  `validation.status: not_run` residue does NOT dispatch Validation; either
  a no-op (`already_flushed`-style) or the AC-001 retarget fires instead.
- AC-003: Existing dispatch suite (`tests/skills/test-aai-orchestration-dispatch.sh`)
  and the ceremony-levels suite stay green with no changed behavior for
  fixtures where the focus IS the live, non-done work item (regression
  guard — this change must not alter any currently-passing dispatch path).
- AC-004: The two real-world shapes cited in Motivation (2026-07-16 tick 9
  post-flush residue; 2026-07-17 tick 1 stale-focus-with-open-intake) no
  longer require LLM recovery when replayed against fixture STATE snapshots
  modeled on them.

## Verification
- `bash tests/skills/test-aai-orchestration-dispatch.sh` -> exit 0, including
  new AC-001..AC-004 fixtures.
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0 (regression, D5
  byte-identity style check against the shared `decide()` core).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- `node .aai/scripts/check-state.mjs` -> OK.

## Constraints / Risks
- Must stay fail-closed: the new retarget path fires ONLY on the exact,
  unambiguous single-open-intake shape; anything with more than one
  candidate or any structural ambiguity keeps falling to `needs_llm` rather
  than guessing (Constitution art. 4, degrade and report).
- `orchestration-dispatch.mjs` is a `protected_paths_l3` surface
  (docs/ai/docs-audit.yaml) — despite the L1 ceremony justification above
  (small, bounded diff), Planning should explicitly weigh L2/L3
  reclassification given the file is protected; this doc records the L1
  intent but does not foreclose that call.
- Risk of interaction with the `loop-ceremony-aware-dispatch` change
  (same batch) — both touch `orchestration-dispatch.mjs`'s rule table;
  sequence them (or land one first) to avoid a merge conflict on the same
  function.

## Notes
- Evidence citations: `docs/ai/LOOP_TICKS.jsonl` lines 10-11 (ticks 9 of
  2026-07-16 and 1 of 2026-07-17); `docs/ai/EVENTS.jsonl` line 465
  (`work_item_closed`, CHANGE-0027, 2026-07-16T23:49:01Z).
- Filed as part of the same 2026-07-17 intake batch as
  `loop-ceremony-aware-dispatch`, `loop-token-usage-capture`, and
  `tdd-red-evidence-classification`; all four are independent AAI-repo
  confirmations of gaps the EEX downstream project also reported.
