---
id: metrics-flush-strands-completed-refs
number: 22
type: issue
status: draft
links:
  pr: []
  commits: []
---

# metrics-flush strands completed work items: only the current-validation ref is ever flushed

# Summary
- `metrics-flush.mjs` flushes ONLY the single work item named by
  `last_validation.ref_id` (gate at `metrics-flush.mjs:597`:
  `vStatus === 'pass' && refMatches(vRef, ref)`). Any completed item that is not
  the ref of the CURRENT validation verdict is SKIPPED — and once the loop moves
  on, that ref's PASS verdict is overwritten in the `last_validation` singleton,
  so the item can NEVER be flushed. Completed work therefore accumulates in
  `STATE.metrics.work_items` and never reaches the committed `METRICS.jsonl`
  ledger. Reported downstream (19 stranded items); confirmed in THIS repo (12
  `status: done` work items stranded in `active_work_items`, plus
  `pr-67-post-merge-review` which flush SKIPPED on every tick this session).

## Type
- bug

## Impact
- The COMMITTED `docs/ai/METRICS.jsonl` (read by the dashboard / metrics-report)
  is INCOMPLETE — it is missing the cost/timing of every stranded item. STATE
  itself is per-dev gitignored so the loop is not broken, but the durable
  telemetry record silently under-counts real work. Stranded refs also cause
  flush friction (they can keep the partial-flush reset firing). Severity: low —
  cosmetic to the loop, but a real gap in the one telemetry artifact meant to
  persist across devs.

## Current Behavior
- Flush is single-ref by DESIGN — a truth-scoring provenance guarantee: it only
  moves metrics for a ref that has a recorded PASS verdict (the
  `last_validation` singleton). That singleton holds exactly one ref at a time,
  so a second completed item strands the first. This is not an oversight in the
  gate; it is the absence of a per-ref completion record the sweep could trust.

## Expected Behavior
- Completed work items eventually reach `METRICS.jsonl` — not only the one that
  happens to be the current validation ref — WITHOUT weakening the truth-scoring
  guarantee (never flush a ref that did not legitimately complete).

## Steps to Reproduce (if applicable)
1) Complete work item A (validation PASS), do NOT flush; complete work item B
   (validation PASS) — `last_validation.ref_id` is now B.
2) Run `metrics-flush.mjs`: A is SKIPPED ("validation verdict does not name A"),
   only B flushes. A is now stranded forever (its verdict was overwritten).

## Verification
- A new opt-in `--sweep` mode of `metrics-flush.mjs` flushes EVERY stranded
  `metrics.work_items` entry whose ref carries DURABLE completion provenance,
  moving it to `METRICS.jsonl` and surgically removing it from STATE — with the
  same integrity refusal / rollback discipline the current flush already has.
- The DEFAULT (no flag) behavior is BYTE-UNCHANGED: single-ref flush on
  `last_validation` (existing tests stay green).
- A stranded entry WITHOUT durable completion provenance is NOT flushed (fail
  closed — never fabricate a PASS).
- After `--sweep`, `STATE.metrics.work_items` retains only genuinely-incomplete
  entries; a re-run is a no-op (idempotent).
- `./tests/skills/test-aai-metrics.sh` (or the suite Planning selects) proves the
  sweep flushes a fixture stranded-but-closed ref, SKIPS a stranded-but-unproven
  ref, and leaves default single-ref behavior identical. Existing metrics tests
  stay green; skill-suite CI green on Ubuntu.

## Constraints / Risks
- **Stays L2 (the whole point of the design):** the fix lives ENTIRELY in
  `metrics-flush.mjs`, which is NOT in `protected_paths_l3` (only `state.mjs` &
  friends are). It must NOT add a field to the STATE schema (that would touch
  `state.mjs` → force L3 → mandatory worktree, the gate this very kind of fix
  keeps hitting). `metrics-flush.mjs` already writes STATE surgically, so no
  `state.mjs` change is needed.
- **Provenance gate (Planning to finalize) — use EXISTING durable proof, not a
  new schema field.** Candidate: flush a stranded ref iff there is a committed
  `work_item_closed` event for it in `docs/ai/EVENTS.jsonl` (stamped by
  close-work-item.mjs only AFTER its self-verify audit passed — stronger, durable,
  tamper-evident proof than the transient `last_validation` singleton),
  corroborated by `active_work_items[ref].status == 'done'`. Decide whether the
  close event is REQUIRED (safest — a `done`-without-close ref is left stranded and
  reported) or whether `done` alone suffices; recommend the stricter option and
  justify against the truth-scoring guarantee.
- Edge cases: a stranded entry with `runs.length == 0` (no metrics to move) —
  keep the existing skip; an entry mid-interrupted-flush (already in `inLedger`)
  — the existing resume path; a `done` ref with NO close event — report it, do
  not flush. Never double-flush (idempotent vs `METRICS.jsonl`).
- Cost/pricing + timing come from the entry's own `agent_runs` (unchanged); the
  "cost unattributable" warnings still fire truthfully per run.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the third downstream report this session in the "the workflow itself
  must remove the problem" class. Fixing it upstream clears it for every
  deployment via `/aai-update`, and clears this repo's own 12 stranded items
  (a `--sweep` run after merge).
- The reporter correctly classified it as legitimate flush behavior for the
  CURRENT ref plus a separate telemetry-hygiene gap needing multi-ref flush — this
  spec is that multi-ref sweep, done provenance-safely and without an L3 schema
  change.
