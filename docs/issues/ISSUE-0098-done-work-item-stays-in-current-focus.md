---
id: done-work-item-stays-in-current-focus
type: issue
number: 98
status: done
links:
  pr:
    - TBD
  commits:
    - df3a569422103ab58e2e5994d845678736a239b0
---

# Issue — A closed item with no `metrics.work_items` row is unflushable, so rule 4b dispatches a no-op forever and a done item stays in `current_focus`

## Summary
`docs/ai/STATE.yaml` `current_focus` names `readme-portable-workflow-onboarding`
(CHANGE-0199, `status: done`, merged as PR #424). It cannot be cleared by the
canonical path, because the canonical path is a no-op for it:

- `orchestration-dispatch.mjs` correctly detects the condition and dispatches
  **rule 4b -> Metrics Flush**, reason `closed_but_unflushed_focus`.
- `metrics-flush.mjs` enumerates its candidates from STATE
  `metrics.work_items` (`:203` parses that block, `:1327` is the loop that
  applies `--ref`). This ref has **no row** in `metrics.work_items`.
- So the ref never enters the loop. `--ref <ref> --dry-run` returns
  `"flush": []` and the ref is absent even from the `skipped` map, while every
  other ref is reported as `not selected (--ref restriction)`.
- `flushed` is derived from the ref's absence in `docs/ai/METRICS.jsonl`
  (verified: 0 occurrences). Nothing can ever put it there.

The loop is therefore closed: `flushed` stays `false`, rule 4b fires on every
tick, the flush moves nothing, and the done item keeps the focus indefinitely.

## Type
- bug

## Impact
- Who/what is affected: the whole orchestration tick. Every `/aai-ship` or
  `/aai-loop` run on this repository state is routed to a role that cannot
  make progress, so no other rule can ever be reached.
- Collateral, and how this was found: a stale focus makes
  `state.mjs set-strategy --ref <new-ref>` exit 2, so **every subsequent
  intake's implementation-mode choice silently degrades** into a `## Notes`
  line via `INTAKE_COMMON`'s LIVE OTHER FOCUS branch. That branch exists for a
  genuinely concurrent other focus — a legitimate state — and a wedged closed
  focus takes the identical branch and prints the identical result, so the
  degradation is reported to the operator as canon working as intended.
- Second known collateral: a closed ride keeps publishing as the in-flight
  scope — `fu-overview-shows-closed-ride-inflight`, recorded done in
  `docs/ai/decisions.jsonl` (resolved_by dispatch-state-sweep, 2026-09-13).
- Severity/priority: high. It is a stuck state, not a slow one, and its
  primary symptom is indistinguishable from correct behavior.

## Current Behavior
Verified on the live repository, 2026-10-03:

```
# dispatch sees it and prescribes the remedy
$ node .aai/scripts/orchestration-dispatch.mjs --human --confirm
{"verdict":"dispatch","rule":"4b","role":"Metrics Flush",
 "ref_id":"readme-portable-workflow-onboarding",
 "reasons":["closed_but_unflushed_focus"], ...
 "work_item":{"phase":"closed","status":"done"},
 "flushed":false,"close_event_present":true, ...}

# the prescribed remedy has nothing to act on
$ node .aai/scripts/metrics-flush.mjs --ref readme-portable-workflow-onboarding --dry-run
{"dry_run":true,"flush":[],"swept":[],"resume":[],"skipped":{ ...every OTHER
 ref... : "not selected (--ref restriction)" }}
   # note: the requested ref is absent from `skipped` entirely — it was never
   # a candidate, as opposed to a candidate that was filtered out.

# the provenance the flush requires DOES exist
$ grep readme-portable-workflow-onboarding docs/ai/EVENTS.jsonl
  work_item_closed   ref='readme-portable-workflow-onboarding'   (plus
  doc_lifecycle x2, ac_evidence, validation_verdict)

# but the ledger entry never appears, and the row the flush iterates is missing
$ grep -c readme-portable-workflow-onboarding docs/ai/METRICS.jsonl   -> 0
$ grep -n readme-portable-workflow-onboarding docs/ai/STATE.yaml
  27,28   current_focus
  518-522 active_work_items  (phase closed, status done)
  558-560 validation
  # nothing under metrics.work_items
```

Note what is NOT the bug, so a fix does not go after the wrong thing:

- The `set-strategy` exit 2 is **correct and specified**. ISSUE-0086 /
  SPEC-0192 `strategy-unscoped-from-current-focus` (done, PR #405, ceremony L3)
  states it verbatim: "Writing a strategy whose `ref_id` disagrees with
  `current_focus` is refused (non-zero, named error)." That guard worked; its
  precondition was wrong.
- `orchestration-dispatch.mjs` is **also correct**. Rule 4b names the exact
  condition. The detection is not missing.
- `.aai/SKILL_PR.prompt.md:247` already prescribes
  `state.mjs clear-focus --ref <slug>` in the close ceremony, added as
  remediation B2 of SPEC-0180 `spec-dispatch-state-sweep`. The wiring exists.

The bug is the gap BETWEEN those correct parts: a closed ref can reach a state
that the detector flags and the prescribed remedy cannot act on.

## Expected Behavior
- A ref that rule 4b dispatches a Metrics Flush for MUST be actionable by that
  flush, or the dispatcher must route it somewhere that can act. A detector and
  its prescribed remedy must not disagree about what is actionable.
- A closed work item with no `metrics.work_items` row reaches a terminal,
  flushed state rather than wedging — whether by the flush handling a
  row-less closed ref, or by the row being guaranteed to exist for any item
  that can be closed. Which of those is correct is a design question for
  Planning, not frozen here.
- A done work item does not remain in `current_focus` once its ride is closed.
- A no-op remedy is never silently satisfying: if a flush selects nothing for
  an explicitly named `--ref`, that is reported as a refusal naming the reason,
  not as an empty success. An explicitly requested ref that is not a candidate
  must say so.
- `set-strategy`'s mismatch refusal stays exactly as specified. If anything is
  added, it is distinguishing a STALE closed focus from a live other focus, so
  intake can report which case it hit instead of printing the same line for
  both.

## Steps to Reproduce (if applicable)
The current repository state reproduces this with no setup:

1. `node .aai/scripts/orchestration-dispatch.mjs --human --confirm` — observe
   rule 4b, role Metrics Flush, reason `closed_but_unflushed_focus`.
2. `node .aai/scripts/metrics-flush.mjs --ref readme-portable-workflow-onboarding
   --dry-run` — observe `"flush": []` and the ref missing from `skipped`.
3. `grep -c readme-portable-workflow-onboarding docs/ai/METRICS.jsonl` — 0.
4. Re-run step 1 — identical dispatch. The tick cannot advance.
5. Start any intake and choose an implementation mode: `set-strategy --ref
   <new-ref>` exits 2 and the choice lands in `## Notes`.

A fixture reproduction needs a STATE with an `active_work_items` entry whose
`status: done`, a committed `work_item_closed` event for that ref, and no
`metrics.work_items` row for it.

## Verification
- The fixture above: before the fix the tick is stationary across two
  consecutive dispatches; after it, the ref reaches a flushed terminal state
  and `current_focus` is released.
- `metrics-flush.mjs --ref <ref>` on a ref absent from `metrics.work_items`
  reports a named refusal instead of an empty-success `flush: []`.
- A second dispatch after the fix returns a DIFFERENT rule than 4b for the
  same ref — the proof that the wedge is gone, not merely masked.
- `bash tests/skills/test-framework.sh --skill aai-metrics` green — the flush's
  own suite is the regression surface here.
- `bash tests/skills/test-framework.sh --skill aai-orchestration-dispatch`
  green — rule 4b's routing must not be broken by whatever makes it
  satisfiable.
- `bash tests/skills/test-framework.sh --skill aai-state` green — the
  `set-strategy` refusal and the strategy-enum / untested-rationale pins must
  not move.
- `bash tests/skills/test-framework.sh --skill aai-check-state` green
  (always-on `core:` suite).
- End-to-end on the real case: after the fix, `set-strategy --ref
  ci-test-selection-narrowing-and-sharding` succeeds.

## Constraints / Risks
- **Do not fabricate the ledger entry.** `metrics-flush.mjs:61-63` is explicit
  that completion provenance is durable and "fail-closed otherwise, reported,
  never fabricated". A fix that invents a `metrics.work_items` row, or writes a
  METRICS.jsonl entry with made-up numbers, converts a stuck state into a
  false record. A missing row must flush as *absent*, not as zero.
- **Do not weaken the ISSUE-0086 / SPEC-0192 refusal** (ceremony L3). The
  tempting shortcut is letting `set-strategy` proceed when the focus is closed;
  that re-opens the wrong-rigor-lane bug SPEC-0192 closed.
- **An exception can manufacture the state in which the guard stops applying.**
  Anything that auto-clears a focus on "looks closed" could clear past an
  genuinely incomplete close. Report-and-refuse beats auto-repair; any
  auto-repair needs its interaction with the close ceremony's ordering
  evaluated, not just its happy path.
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are gitignored, so CI
  cannot prove this against the real file — fixture coverage IS the
  verification. A gate that degrades to exit 0 when STATE is absent never runs
  in CI.
- `docs/ai/EVENTS.jsonl` is committed and append-only. Never `git restore` it
  while working here: that drops close telemetry and turns this into a
  false-done.
- `metrics-flush.mjs` is a closed-contract single-file mutator doing
  line-surgical STATE edits (`:6`, `:19-20`). Edits there are high-blast-radius
  and `--dry-run` is the cheap check before every write.
- `clear-focus` has an open defect of its own,
  `fu-clearfocus-announces-unwritten-phase` (it replaces an existing
  `phase:`/`status:` line but never inserts a missing one, and prints
  `work item phase=closed status=done` unconditionally). Do not add reliance on
  it without reading that follow-up.
- No local secret is referenced by this scope; the secrets preflight is skipped.

## Notes
Implementation mode: not recorded in STATE — `set-strategy` is blocked by the
very bug this item describes. `/aai-ship` autopilot defaults applied:
`human_time_minutes` null (default 1), explicit assumptions over questions
(default 3). Planning picks the strategy.

Ride gate: REFUSED as maintenance off-roadmap; ridden under an owner
`--override`, logged to `docs/ai/EVENTS.jsonl` as `ride_gate_override`.

Live reproduction captured before any retarget:
`current_focus{type: intake_change, ref_id: readme-portable-workflow-onboarding,
primary_path: docs/issues/CHANGE-0199-readme-portable-workflow-onboarding.md}`
against CHANGE-0199 `number: 199, status: done`. Planning's `set-focus` will
overwrite this, which is why it is recorded here.

Related work that does NOT close this item:
- ISSUE-0086 / SPEC-0192 `strategy-unscoped-from-current-focus` (done, PR #405)
  — delivered the refusal that surfaced this. Correct as built.
- SPEC-0180 `spec-dispatch-state-sweep` — remediation B2 added the SKILL_PR
  `clear-focus` wiring. Prompt wiring is not what failed here; the flush is.
- `fu-overview-shows-closed-ride-inflight` (DONE, resolved_by
  dispatch-state-sweep 2026-09-13) — a second symptom of the same wedged
  state, already closed. Verified: `follow-ups.mjs list --status open` has no
  match.
- `fu-clearfocus-announces-unwritten-phase` (open) — a defect inside
  `clear-focus` itself, adjacent but distinct.

Out of scope, file separately if wanted: making the close ceremony's steps
enforceable as a group rather than one prompt line per step; and which STATE
invariants `check-state.mjs` should own (today it checks only top-level key
uniqueness — it reported `OK` throughout this entire wedged state).
