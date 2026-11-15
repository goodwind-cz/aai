---
id: archive-ledger-check
type: issue
number: 116
status: done
links:
  pr: []
  commits: []
---

# Archiving a ride's STATE copy does not check that its role runs reached METRICS

## Summary
Follow-up `fu-archive-step-skips-ledger-check` (P3, filed by
`recover-archived-state-runs`). Two cleanup paths copy a ride's
`docs/ai/STATE.yaml` into `docs/ai/archive/**` and then remove the worktree:
`merge-cleanup.mjs` step `archive-runtime` (`archiveRuntime`) and the manual
Cleanup Worktree steps in `.aai/SKILL_WORKTREE.prompt.md`. Neither checks that
the role runs the copy holds (`metrics.work_items.<ref>.agent_runs`) are in
`docs/ai/METRICS.jsonl`. Runs recorded after the ride's flush (late review or
CI-fix rounds) stay only in the archive copy until someone runs
`node .aai/scripts/metrics-flush.mjs --recover-archives` (shipped by
`recover-archived-state-runs`, PR #559).

The owner's rule (2026-11-14): "Ty metriky se nesmí ztrácet" (the metrics
must not be lost).

## Type
bug

## Impact
- Every project that vendors the layer: each merged ride whose STATE holds
  runs the ledger does not can strand them in an archive copy. Totals in the
  factory report, metrics report, dashboard and overview undercount until a
  manual recovery run.
- Severity: P3. Telemetry only; no gate reads the missing runs.

## Current Behavior
- `archiveRuntime` copies the ride worktree's STATE into
  `docs/ai/archive/merge-cleanup/pr-<n>/worktree/docs/ai/STATE.yaml` and
  reports `1 archived`; nothing compares its runs with any ledger.
- SKILL_WORKTREE Cleanup step 2 copies STATE with `cp`; step 3 removes the
  worktree. No ledger check.
- `metrics-flush --recover-archives` skips the `--state` focus ref and
  excludes the `--state` file itself from the copies, so it cannot be pointed
  at a ride's own STATE at the end of that ride.

## Expected Behavior
- The archive step leaves no run behind: every role run of the archived copy
  is either already in the ledger (same identity rule the recovery uses: ref,
  role, started_utc) or is written to it through the existing recovery path,
  or the step reports loudly, with the exact command to run, that it could not
  check.
- A plan or dry run writes nothing. A second run over the same state changes
  nothing.
- The manual worktree cleanup has a one-line command for the same check.

## Steps to Reproduce (if applicable)
1) In a ride worktree, flush the ride, then record one more role run with
   `state.mjs append-run` (as a late review round does).
2) Merge the PR and run `merge-cleanup.mjs apply`.
3) Actual: the run is in `docs/ai/archive/merge-cleanup/pr-<n>/worktree/docs/ai/STATE.yaml`
   and in no line of `docs/ai/METRICS.jsonl`.

## Verification
- New cases in `tests/skills/test-aai-merge-cleanup.sh`: a ride STATE with a
  run the ledger lacks ends, after apply, with that run in the main checkout's
  METRICS; an already-flushed STATE changes nothing; plan writes nothing.
- New cases in `tests/skills/test-aai-metrics.sh` for the recovery flag the
  archive step uses.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  and `... test-aai-metrics.sh` pass.

## Constraints / Risks
- merge-cleanup runs in the main checkout after the merge, where METRICS.jsonl
  is tracked: a write there leaves uncommitted ledger lines.
- Reuse the recovery's identity and builder; no second implementation.
- `merge-cleanup.mjs` has a line ceiling of 1490 (TEST-058).
- Secrets preflight results: no secret referenced.

## Notes
- Implementation mode (autopilot recommendation): tdd. Data-integrity change
  to a vendored cleanup engine and a telemetry writer.
