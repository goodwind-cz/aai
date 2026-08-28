---
id: tripwire-reporting-and-run-dir-residuals
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# The tripwire reports the wrong thing, and the run directory it reports into can collide

## Summary
- Ten registry items were filed under the ride `suites-must-not-touch-the-shipping-repo`.
  The shared-`.git` mechanism they orbit is closed by a ride in flight. What remains is
  the OBSERVER, not the mechanism: the tripwire's reporting drops the information a
  reader needs, its ratchet has a stated blind spot, its run directory can be shared by
  two processes, and the ledger it writes to is tracked and gitignored at the same time.

## Type
- bug

## Impact
- Affected: `tests/skills/test-framework.sh`, `tests/skills/test-aai-repo-tripwire.sh`,
  `docs/ai/tests/test-runs.jsonl`, and every CI log a human has to read.
- Each item degrades a RED run's diagnosability or its offender list rather than turning
  a run green, which is why they were filed rather than blocking — but a red run nobody
  can diagnose costs a round every time.

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-tripwire-fail-hides-suite-log-tail` (P2). `run_test` routes on ONE outcome value:
  `tests/skills/test-framework.sh:900-903` rewrites `outcome` to `tripwire` whenever
  `tw_fail_kind` is non-empty, so a suite that fails on its own exit code AND trips the
  tripwire takes the `tripwire)` branch (lines 927-964) and never reaches the `*)` branch
  (line 965 onward) that greps the log for failure markers and dumps the tail. The reader
  gets a tripwire report and no reason for the exit code.
- `fu-framework-rundir-same-second` (P2, Codex P2 inline review on PR #266).
  `tests/skills/test-framework.sh:516-517` derives `RUN_ID` from
  `date -u +%Y%m%d-%H%M%S` and `RUN_DIR` from it, so two framework processes started in
  the same second share one results directory. Process B can overwrite A's before-snapshot
  with an already-dirty porcelain state, and both comparisons then read clean.
- `fu-test-runs-jsonl-tracked-ignored` (P2). Measured: `git ls-files --error-unmatch`
  succeeds (TRACKED), `git check-ignore --no-index -v` reports `.gitignore:107`, and
  `tests/skills/test-framework.sh:1153` appends the run record to
  `$PROJECT_ROOT/docs/ai/tests/test-runs.jsonl`. `.gitignore` has no effect on an
  already-tracked file, so the harness dirties the shipping working tree on every run.
- `fu-tripwire-allowed-ignores-pre-dirty` (P2). The ratchet entry path-subset test compares
  only paths that MOVED, so an allowlisted suite writing an ALREADY-dirty non-ratchet path
  still reads `tripwire ALLOWED` inside its listed paths at exit 0. Documented as a stated
  bound in the spec's D8 and in the vendored library header, not enforced.
- `fu-tripwire-degrade-not-on-suite-line` (P3). Under the no-hasher degrade a masked
  writer's own progress line is a bare `PASS` and `metrics.jsonl` records the tripwire
  clean with `tripwire_attested true`; only the two aggregate WARN lines are honest. The
  entry's other half (the drain report printing STALE) is already moot.
- `fu-tripwire-fixture-dirs-leak` (P3, Codex P2 on PR #266). `new_fixture` appends to
  `WORKDIRS` at `tests/skills/test-aai-repo-tripwire.sh:103`, and the file calls
  `$(new_fixture)` 16 times (measured) — always in a command substitution, so the append
  runs in a subshell and the EXIT trap at line 74 drains an empty array. Every full run
  leaves its temporary git repositories behind under `TMPDIR`.

Three members of this cluster are a different mechanism and are recorded here so they are
not lost, not because they belong to the tripwire:

- `fu-parallel-roles-dirty-the-tree` (P2): dispatching a code review and a validation
  concurrently lands the reviewer's own report file in the checkout mid-run. The roles are
  read-only by contract; their REPORTS are not. Measured 2026-08-19 on an 80-suite
  aggregate whose single failure was caused entirely by the parallel reviewer writing
  `docs/ai/reviews/...` at 17:12Z.
- `fu-suggested-ids-read-as-filed` (P2): validation reports list follow-up ids under a
  `filed:` key when the role only SUGGESTED them. This overlaps
  `fu-filed-list-trusted-again` (P2, the same mistake one day later) and
  `fu-report-ids-exceed-registry-cap` (P2, the mechanical cause), both filed with other
  clusters.
- `fu-acgate-vs-falseopen-catch22` (P2): the AC STATUS GATE blocks PASS on non-terminal AC
  rows while docs-audit's false-open heuristic fails closed on a terminal AC table with
  un-timestampable delivery. Every ceremony-1 scope validated before its delivery commit
  hits this and is waived by hand.

One member is no longer reproducible:

- `fu-followups-json-truncated-on-pipe` (P2) recorded that
  `follow-ups.mjs list --json` stopped at exactly 65536 bytes on a pipe. Measured today on
  `origin/main`: `node .aai/scripts/follow-ups.mjs list --status open --json | wc -c` gives
  106502, and the same command redirected to a file gives 106502. The `cli-output-survives-a-pipe`
  ride fixed this one file. The residual is the repo-wide sweep, tracked as
  `fu-cli-exit-truncates-pipe-sweep` under its own cluster.

## Expected Behavior
- A suite that fails its own exit code AND trips the tripwire prints both: the tripwire
  block and the failure-lines-plus-tail dump.
- Two framework processes started in the same second do not share a results directory.
- The harness does not write into the shipping working tree on every run, or
  `docs/ai/tests/test-runs.jsonl` stops being tracked, or stops being gitignored — the
  present combination is incoherent either way.
- The ratchet's ALLOWED verdict accounts for already-dirty non-ratchet paths, or refuses
  to render a verdict it cannot support.
- A degraded tripwire says so on the suite's own line and in telemetry, not only in the
  aggregate.

## Steps to Reproduce (if applicable)
1) Tripwire hides the tail: make a suite exit non-zero AND write a watched path; run
   `tests/skills/test-framework.sh --skill <that suite>`; the log shows the tripwire block
   and no error-details block.
2) Run-dir collision: start two `tests/skills/test-framework.sh` processes within the same
   wall-clock second and compare their `RUN_DIR` values.
3) Tracked-and-ignored: `git ls-files --error-unmatch docs/ai/tests/test-runs.jsonl` and
   `git check-ignore --no-index -v docs/ai/tests/test-runs.jsonl` both succeed.
4) Fixture leak: run `tests/skills/test-aai-repo-tripwire.sh` to completion and count the
   temporary git repositories remaining under `TMPDIR`.

## Verification
- The dual-failure case prints both blocks in one run.
- `RUN_DIR` is unique across two same-second starts.
- After a framework run, `git status --porcelain=v1 -uno` in the shipping checkout is
  empty.
- `tests/skills/test-aai-repo-tripwire.sh` leaves no directories behind.

## Constraints / Risks
- The tripwire is PERMANENT by `hitl_decision 2026-08-23T20:05:00Z`; these are repairs to
  a surface that stays, not steps toward removing it.
- Changing the outcome routing in `run_test` touches the one per-suite verdict and the one
  increment site that the isolation ride's D3 deliberately preserves; the two must be
  sequenced, not merged.

## Notes
- OUT OF SCOPE, closed by the ride `isolation-shares-the-shipping-git` (branch
  `fix/suite-isolation-owns-its-git`): the shared-`.git` mechanism itself. Its spec's D5
  SCOPE FENCE names five neighbours it deliberately leaves open, and five of them are in
  this intake: the three tripwire reporting findings, `fu-framework-rundir-same-second`
  and `fu-test-runs-jsonl-tracked-ignored`.
- OUT OF SCOPE: `fu-followups-json-truncated-on-pipe`, measured fixed above.
- Registry ids covered: `fu-tripwire-fail-hides-suite-log-tail`,
  `fu-tripwire-allowed-ignores-pre-dirty`, `fu-tripwire-degrade-not-on-suite-line`,
  `fu-framework-rundir-same-second`, `fu-test-runs-jsonl-tracked-ignored`,
  `fu-tripwire-fixture-dirs-leak`, `fu-parallel-roles-dirty-the-tree`,
  `fu-suggested-ids-read-as-filed`, `fu-acgate-vs-falseopen-catch22`,
  `fu-followups-json-truncated-on-pipe`.
