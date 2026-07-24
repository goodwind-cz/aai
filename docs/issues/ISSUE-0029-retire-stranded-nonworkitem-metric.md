---
id: retire-stranded-nonworkitem-metric
number: 29
type: issue
status: draft
links:
  pr: []
  commits: []
---

# metrics-flush has no way to retire a stranded NON-work-item entry, so `pr-67-post-merge-review` prints SKIP forever

## Summary
- `docs/ai/STATE.yaml` `metrics.work_items` contains `pr-67-post-merge-review` — a
  one-off post-merge Code Review of PR #67 (fable-5, PASS, 686s, report at
  docs/ai/reviews/review-20260716-120448.md). It is NOT a work item and never went
  through the close ceremony, so it has neither a `last_validation` PASS naming it
  nor a committed `work_item_closed` event. `metrics-flush.mjs` therefore skips it
  on EVERY run, by BOTH paths:
  - default flush needs `last_validation.status == pass` naming the ref -> SKIP
    ("validation verdict does not name pr-67-post-merge-review");
  - `--sweep` needs a committed `work_item_closed` event in EVENTS.jsonl -> SKIP
    ("no durable work_item_closed event — fail-closed").
- There is no sanctioned exit for "this entry is legitimately not a work item and
  should be removed from the work-item ledger". So the SKIP line prints on every
  flush indefinitely, and the entry sits in STATE forever.

## Type
- bug

## Impact
- Low-severity but permanent: every `metrics-flush` (each work-item close, each
  `--sweep`) prints a misleading SKIP for a ref that can NEVER flush, training the
  operator to ignore SKIP lines — which defeats the point of SKIP as a signal that
  something genuinely needs attention. Also a slow accretion risk: any future
  mis-recorded non-work-item telemetry (post-merge reviews, ad-hoc audits) strands
  the same way with no cleanup path. AAI-layer -> inherited downstream via
  `/aai-update`.

## Current Behavior
- `metrics-flush.mjs` has exactly two dispositions for a `metrics.work_items` entry:
  flush (truth-gated) or SKIP. A non-work-item entry can satisfy neither gate, so it
  is permanently SKIPped and never leaves STATE.

## Expected Behavior
- A sanctioned, fail-closed `--retire <ref>` disposition removes a stranded
  NON-work-item entry from `metrics.work_items` with a durable audit record, so the
  SKIP stops and STATE stays clean — WITHOUT ever letting a real (flushable) work
  item be retired to dodge the truth-gate.

## Steps to Reproduce (if applicable)
- `node .aai/scripts/metrics-flush.mjs --dry-run` -> `skipped` always lists
  `pr-67-post-merge-review`; `--sweep --dry-run` skips it too. It never flushes.

## Verification
- New `--retire <ref> [--reason "..."]` mode on `metrics-flush.mjs`:
  - FAIL-CLOSED guard: refuses (non-zero exit, no mutation) to retire a ref that
    WOULD flush — i.e. one that `last_validation` names with PASS, OR that has a
    committed `work_item_closed` event in EVENTS.jsonl. Those must flush, not
    retire. It also refuses a ref not present in `metrics.work_items`.
  - On a genuinely-stranded ref: appends a durable audit record to
    `docs/ai/EVENTS.jsonl` (e.g. a `metric_retired` event carrying the ref, the
    reason, and a compact summary of the discarded `agent_runs` — roles/models/
    durations — so the telemetry is not silently lost), THEN removes the entry from
    `STATE.metrics.work_items`.
  - Read-mostly / idempotent otherwise; `--dry-run` reports what it WOULD retire
    without writing; default (no `--retire`) behavior is byte-unchanged.
- Running `--retire pr-67-post-merge-review` clears it: subsequent
  `metrics-flush --dry-run` no longer lists it in `skipped`, STATE no longer
  contains the entry, and EVENTS.jsonl carries the `metric_retired` audit record.
- Attempting `--retire <a real flushable ref>` is REFUSED with a clear message.
- Full `tests/skills/test-aai-metrics.sh` green (incl. the SPEC-0054 flush
  invariants), and the skill-suite green on Ubuntu CI.

## Constraints / Risks
- `.aai/scripts/metrics-flush.mjs` is NOT `protected_paths_l3`. Do NOT touch any
  protected path (`state*.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.*`,
  `WORKFLOW.md`, `CONSTITUTION.md`).
- The fail-closed guard is the WHOLE point: `--retire` must be impossible to use as
  a truth-gate bypass. Reuse the EXISTING flushability predicates
  (last_validation-names-with-PASS; committed `work_item_closed`) rather than a new
  looser check — if a ref is flushable by either, retire REFUSES.
- Preserve the audit trail: retirement records the discarded run summary durably
  (EVENTS.jsonl), it does not just delete real telemetry. EVENTS.jsonl is
  append-only; write via the existing append path, never rewrite it.
- Keep the reused `work_item_closed` provenance predicate intact — do NOT reword
  `METRICS_FLUSH.prompt.md` (the SPEC-0054 invariant test greps it for the literal
  `work_item_closed`); document `--retire` in the script's own `--help`/comments,
  NOT in the prompt, to avoid both that trip AND a prompt-diet ledger companion.
- Integrity/rollback: reuse the flush's existing ledger-before-STATE ordering and
  refusal/rollback shape so a partial write cannot strand STATE.
- No secret referenced — SECRETS PREFLIGHT skipped.
- Companion obligations (PLANNING step 3a): metrics-flush.mjs is not a
  prompt-corpus file and is not a NEW `.aai/**` file; the test extends the existing
  `tests/skills/test-aai-metrics.sh`. Expect no ledger true-up, no PROFILES entry.

## Notes
- This is the smaller half of a two-item cleanup (the other is the recurring
  TEST-018 legacy-reaper flake). `pr-67-post-merge-review` is the only stranded
  entry today; the fix is general (any non-work-item strand), and running it once
  clears the standing SKIP.
