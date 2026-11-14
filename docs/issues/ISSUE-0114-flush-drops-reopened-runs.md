---
id: flush-drops-reopened-runs
type: issue
number: 114
status: done
links:
  pr: []
  commits: []
---

# A flush after a reopen deletes the extension rounds' agent runs instead of writing them to METRICS

## Summary
`metrics-flush.mjs` decides that a ref is an "interrupted flush" when its
`ref_id` already has a summary line in `docs/ai/METRICS.jsonl`
(`.aai/scripts/metrics-flush.mjs:1788`, `if (inLedger.has(ref)) toResume.push(entry)`).
A resumed ref is then treated as cleanup-only: its `metrics.work_items` entry is
removed from STATE (`:1858`, `removeMetricsEntries(lines, completedRefs)`) and
no ledger line is appended. The check never compares the runs in STATE with the
runs in the ledger line.

A ride that is closed, flushed, reopened and run again therefore loses every
role run recorded after the first flush. The flush exits 0 and prints only
`RESUME <ref>: already in ledger — cleanup-only pass`. The resume branch also
runs before the verdict and review gates are applied, so the runs are deleted
even while the work item is still in progress.

## Type
bug

## Impact
- Every project with the AAI layer (metrics-flush ships downstream through aai-sync).
- Any ride that is reopened after its first flush (owner extension, bot-review
  rounds after close) loses all later role-run telemetry: tokens, cost,
  duration, verdicts.
- Severity: high. The owner's rule is that role-run metrics must never be lost
  ("Ty metriky se nesmí ztrácet", 2026-11-14), and the loss is silent.
- Observed incident: ride `consumer-config-routing-override` (PR #555). It was
  closed and flushed at 2026-11-14T01:55Z, reopened for an owner extension, and
  recorded 11 more runs with `state.mjs append-run` between 06:31Z and 12:18Z:
  Planning, 3 TDD Implementation, 3 Validation, 2 Remediation and 2 Code Review,
  1,799,150 recorded tokens in total. The flush at 12:19:11Z took the resume
  branch and deleted all 11 runs. Its `RESUME` line was filtered out of the
  caller's output by `grep -E "Flushed|WARNING|rc|Nothing|error"`, so the ride
  saw nothing. The next flush said `Nothing to flush.` The same flush also reset
  `last_validation` and `code_review` with a "reset after flush" note.

## Current Behavior
- When the ledger already has a summary line for the ref, any STATE runs for
  that ref are deleted without being written, whether or not they appear in the
  ledger.
- The flush exits 0. The only trace is a `RESUME` line that reads like a benign
  crash recovery.

## Expected Behavior
- A resume is cleanup-only only when every run in STATE is already in the
  ledger, which is the real interrupted-flush case. Its behaviour stays
  byte-identical, with no duplicate line.
- STATE runs that are not in the ledger are new telemetry. They go through the
  normal flush gates and are appended as a new ledger line that holds only
  those runs. Runs from the first flush are never repeated.
- If the gates do not admit the new runs, they stay in STATE and the flush
  reports a SKIP. They are never deleted.

## Steps to Reproduce (if applicable)
1) Flush a ref with a PASS validation and review (`metrics-flush.mjs`). The ledger gets one line.
2) Reopen the ref (`state.mjs set-focus`), append a new run
   (`state.mjs append-run --ref <ref> --role Validation --verdict pass ...`) and
   record a PASS (`state.mjs set-validation --status pass --ref <ref>`).
3) Run `metrics-flush.mjs` again.
4) Actual: exit 0, `RESUME <ref>: already in ledger — cleanup-only pass`, the
   ledger still has 1 line, the new run is gone from STATE and is not in METRICS.

## Verification
- A new regression test in `tests/skills/test-aai-metrics.sh` covers flush,
  reopen, append-run, flush. Afterwards the ledger holds both lines, the new
  run appears exactly once, and the first flush's runs are not repeated.
- A gate-refused second flush keeps the new runs in STATE.
- TEST-013 (the real interrupted flush, after a crash) still resumes
  cleanup-only with one ledger line.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh` passes.

## Constraints / Risks
- Backward compatible: existing STATE and METRICS shapes are unchanged. A line
  that continues an earlier flush may add one optional field, and readers
  ignore unknown fields.
- Downstream readers that count one ledger line per ride (factory report
  per-ride rows) will see a second line for a reopened ride. Totals summed per
  ref (overview, docs-audit) stay correct.
- Recovery of the incident's 11 runs: the ride's session transcript holds every
  `append-run` command line and its stdout (ended_utc, duration_seconds), so the
  runs can be rebuilt without inventing a number. The rebuilt line must be
  marked as reconstructed and name its source.
- Secrets preflight results: no secret referenced.

## Notes
- Related: `ride-handoff.mjs reconcile` already refuses to clear origin runs
  that are missing from the ledger (`origin_runs_not_in_ledger`, keyed on role
  and started_utc). The flush resume had no such check.
- Implementation mode (autopilot recommendation): tdd. This is a data-integrity
  change to a core telemetry path.
