---
id: recover-archived-state-runs
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Role runs that live only in archived STATE copies never reach METRICS, and nothing can recover them

## Summary
Follow-up `fu-archived-state-runs-not-in-ledger` (P2, filed by
`flush-drops-reopened-runs`). Archived copies of `docs/ai/STATE.yaml` hold role
runs (`metrics.work_items.<ref>.agent_runs`) that never reached
`docs/ai/METRICS.jsonl`. Some were deleted from the live STATE by the resume
defect that `flush-drops-reopened-runs` fixed. Others belong to rides whose
STATE was archived (merge-cleanup, worktree cleanup, ride handoff, planning
transfer) without a flush. The archive copies are gitignored, so the only copy
of this telemetry sits in local files that nothing reads.

The owner's rule (2026-11-14): "Ty metriky se nesmí ztrácet". The owner chose
to recover them ("Ano, doplnit").

## Type
bug

## Impact
- This repository: measured on 2026-11-15 in the main checkout. 130 archived
  STATE copies under `docs/ai/archive/**`, `docs/ai/reports/**` and
  `.git/aai/checkpoints/**` hold 461 distinct role runs. 181 are already in
  METRICS. 280 runs over 65 refs are not, carrying 79,080,170 recorded
  `tokens_total`. The factory report, metrics report, dashboard and overview
  undercount the factory's real spend by that amount.
- Every downstream project: `merge-cleanup.mjs` and the worktree cleanup in
  `SKILL_WORKTREE` archive a STATE copy before removing it, and no step
  checks that its runs reached the ledger.
- Severity: medium (P2). Telemetry only. No gate reads the missing runs, but
  totals and per-ride rows are wrong.

## Current Behavior
- `metrics-flush.mjs` reads only the live STATE (`--state`). An archived STATE
  copy is never a source.
- There is no command that compares an archived copy's runs with the ledger.
  Recovering them by hand would mean writing ledger lines by hand.

## Expected Behavior
- One repeatable command recovers every run that an archived STATE copy holds
  and the ledger does not. It writes one ledger line per ref, through the same
  entry builder the flush uses, marked `reconstructed` with the source paths
  and the reason.
- A run already in the ledger is never written again, and a second run of the
  command adds nothing.
- Recovered lines are historical telemetry, not gate input. They never count as
  a validation PASS, never prove delivery and never make a ride look flushed.
  Readers that fold a ride's lines keep the ride's real verdict and position.

## Steps to Reproduce (if applicable)
1) In the main checkout, list `docs/ai/archive/**/STATE*.yaml`.
2) For any copy, compare its `metrics.work_items.<ref>.agent_runs` (role and
   started_utc) with the runs of that ref in `docs/ai/METRICS.jsonl`.
3) Actual: e.g. `docs/ai/archive/longhorizon-planning/STATE-before-2026-09-22T22-10-05-898Z.yaml`
   holds 22 runs of `deslop-corpus-honesty`; METRICS has no line for that ref.

## Verification
- New regression tests in `tests/skills/test-aai-metrics.sh`: recovery from a
  fixture archive appends one reconstructed line per ref; runs already in the
  ledger are skipped; a second run appends nothing; the ledger prefix is
  byte-identical.
- Gate and reader tests: a reconstructed line is not a ledger PASS for the PR
  gate, not a delivery record for docs-audit, not a "flushed" record for
  dispatch; the folded ride keeps its real verdict.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh` passes.

## Constraints / Risks
- The archives are gitignored and exist only in the main checkout. Git history
  holds no copy of a gitignored file, so a STATE that was deleted without an
  archive copy cannot be recovered.
- No invented numbers: a field the archive does not hold stays null.
- Append-only: the existing ledger lines stay byte-identical.
- `state.mjs` is not touched.
- Secrets preflight results: no secret referenced.

## Notes
- Related: `ride-handoff.mjs reconcile` keys a run on role and started_utc
  (`origin_runs_not_in_ledger`). Early ledger lines (July 2026) wrote
  `model_id: unknown`, so the 4-field identity alone would write 27 runs twice.
- Implementation mode (autopilot recommendation): tdd. This changes a core
  telemetry path and the readers that feed reports and gates.
