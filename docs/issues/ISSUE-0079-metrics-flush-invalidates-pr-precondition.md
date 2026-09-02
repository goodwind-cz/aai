---
id: metrics-flush-invalidates-pr-precondition
number: 79
type: issue
status: done
links:
  pr:
    - TBD
  commits:
    - 05c7880
---

# Metrics Flush resets the exact STATE fields SKILL_PR's own preconditions require

## Summary
- `.aai/scripts/metrics-flush.mjs` archives a completed ride's `last_validation`
  and `code_review` blocks into `docs/ai/METRICS.jsonl` and resets both to
  their empty/`not_run` defaults in `docs/ai/STATE.yaml` as part of its
  designed archival behavior.
- `.aai/SKILL_PR.prompt.md`'s PRECONDITIONS read those SAME live STATE fields
  (`validation-waiver.mjs` checks `last_validation.status`; a separate check
  reads `code_review.status`) to decide whether it is safe to stage/commit/push.
- When SKILL_LOOP's tick sequence runs Metrics Flush as its own tick (observed:
  tick 6, "the substantive equivalent of LOOP COMPLETE") BEFORE SKILL_PR runs
  for that same scope, the flush silently invalidates the very gate SKILL_PR
  is about to check — even though the ride genuinely passed and the durable
  proof of that PASS is sitting right there in `docs/ai/METRICS.jsonl`.

## Type
- bug

## Impact
- Who/what is affected? Any autonomous ride whose loop reaches Metrics Flush
  before SKILL_PR executes for the same scope. Confirmed once this session
  with concrete tool-call evidence (`intake-staleness-preflight-warning`
  ride: `validation-waiver.mjs` blocked post-flush, manually restored via
  `state.mjs set-validation`/`set-code-review`). A second ride
  (`adhoc-probes-unisolated-report-only`) also ran Metrics Flush before its
  own SKILL_PR, but that ride's precondition checks happened to read
  `pass` with no restoration needed when SKILL_PR ran — so the underlying
  reset/precondition-ordering hazard is structurally present on any ride
  with this tick ordering, but only ONE occurrence actually manifested as an
  observed block+manual-fix in this session. State this as "confirmed once,
  hazard structurally repeatable" rather than "observed twice."
- Severity/priority: P2 — not data-destructive (the durable record survives
  in METRICS.jsonl), but when it does trigger it silently blocks the ship
  path with a message ("validation_not_run_no_waiver") that reads as "the
  ride never validated", which is false and actively misleading to whoever
  hits it next.

## Current Behavior
- After Metrics Flush runs for a scope, `docs/ai/STATE.yaml`'s
  `last_validation.status` reads `not_run` and `code_review.status` reads
  `not_run`, with a note like "reset after flush of <ref>". Running
  `node .aai/scripts/validation-waiver.mjs --state docs/ai/STATE.yaml`
  immediately afterward returns `VALIDATION-GATE blocked
  reason=validation_not_run_no_waiver`, even though the ride's
  `docs/ai/METRICS.jsonl` entry for that exact `ref_id` shows
  `"verdict": "PASS"` with full per-role evidence.
- The operator (or an agent) hitting this has no signal that the block is an
  archival side effect rather than a genuine "never validated" state, and
  must manually reconstruct the gate by re-running
  `node .aai/scripts/state.mjs set-validation --status pass ...` and
  `set-code-review --status pass ...`, sourcing the values by hand from
  METRICS.jsonl.

## Expected Behavior
- Either: SKILL_PR's PRECONDITIONS check falls back to the scope's own
  `docs/ai/METRICS.jsonl` entry (matched by `ref_id`) when the live STATE
  fields read `not_run` with a "reset after flush" note, treating a durable
  `verdict: PASS` record there as equivalent to a live PASS for gating
  purposes — OR: SKILL_LOOP's canonical tick ordering is fixed so Metrics
  Flush for a scope never runs before that scope's own SKILL_PR, closing the
  window entirely. Planning decides which is the correct fix; this intake
  does not prescribe it.

## Steps to Reproduce (if applicable)
1. Run a ride through SKILL_LOOP to completion: Planning → Implementation →
   Validation (PASS) → Code Review (PASS) → Metrics Flush.
2. Immediately after Metrics Flush completes, inspect
   `docs/ai/STATE.yaml`: `last_validation.status` and `code_review.status`
   both read `not_run`.
3. Run `.aai/SKILL_PR.prompt.md`'s precondition checks
   (`node .aai/scripts/validation-waiver.mjs --state docs/ai/STATE.yaml`) for
   that scope: blocked, `reason=validation_not_run_no_waiver`.
4. Confirm the ride genuinely passed: `grep '"ref_id":"<ref>"'
   docs/ai/METRICS.jsonl` shows `"verdict":"PASS"` with real per-role
   evidence (agent_runs, durations, notes) from the same ride.

## Verification
- Command(s) and expected results:
  - Reproduce the exact sequence above on a fixture ride; confirm the
    precondition blocks pre-fix.
  - After the fix, the same sequence must NOT block SKILL_PR when a matching
    `verdict: PASS` METRICS.jsonl entry exists for the scope — verify via the
    same `validation-waiver.mjs` invocation now reporting the gate open (if
    the fallback approach is chosen), or via a full ride where Metrics Flush
    demonstrably never precedes that scope's SKILL_PR (if the ordering
    approach is chosen).
  - Negative control: a scope with NO METRICS.jsonl entry at all (never
    validated) must still block — the fix must not turn the gate into an
    unconditional pass.

## Constraints / Risks
- `docs/ai/METRICS.jsonl` and `docs/ai/STATE.yaml` are both per-developer
  local/gitignored runtime files (not shared, not append-only-guarded the
  way `docs/ai/decisions.jsonl`/`EVENTS.jsonl` are) — a fallback-to-METRICS
  fix does not touch any append-only invariant, but should still be careful
  not to trust a METRICS.jsonl entry whose `ref_id` matches by coincidence
  across unrelated rides (match on ref_id AND recency, not ref_id alone).
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Related: [[role-progress-heartbeat]] and [[ac-table-premature-flip-recurs]]
  are the other two systemic friction patterns identified in the same
  retrospective review.
- Confirmed once in the same session, manually worked around via:
  `node .aai/scripts/state.mjs set-validation --status pass --ref <ref>
  --evidence docs/ai/METRICS.jsonl --notes "Restored after Metrics Flush
  archival reset: durable PASS record is docs/ai/METRICS.jsonl..."` and the
  equivalent `set-code-review` call, sourcing values by hand from the
  METRICS.jsonl entry and the review report path.
- Filed per operator request after a retrospective review of session
  friction points.
