---
id: residuals-of-the-per-suite-clone-ride
type: change
number: 166
status: draft
links:
  pr: []
  commits: []
---

# What the per-suite-clone ride leaves behind: a 32-minute sequential sweep it no longer has to be

## Summary
- The ride `isolation-shares-the-shipping-git` (branch `fix/suite-isolation-owns-its-git`)
  gives every suite its own `git clone --local --no-hardlinks`. Its own follow-ups are the
  subject here, scoped to what remains AFTER it merges. The largest is an opportunity its
  mechanism creates rather than a defect it leaves: sequential execution was forced by
  suites sharing one `.git`, and that constraint is gone.

## Motivation / Business Value
- A full framework sweep costs 1914 s (32 minutes), measured on run
  `test-20260827-154347`. The isolation ride paid it four times — roughly an hour of
  wall-clock for rounds whose findings were all reachable from targeted suites.
- Verified today in a disposable clone of `origin/main` (`c6b32d0`):
  `/usr/bin/grep -c 'wait\b|&$|xargs -P|parallel' tests/skills/test-framework.sh` returns
  0. The file contains no parallel constructs at all.
- Also measured on that run: median suite 6 s, 47 of 81 suites under 10 s, top 12 suites
  1172 s = 61 percent of the total (`aai-delta-stage3` 227 s, `aai-docs-audit` 140 s,
  `aai-run-tests` 129 s, `aai-doctor` 102 s). Four-way execution puts the critical path
  near the longest suite: order of 10 to 12 minutes instead of 32.

## Scope
- In scope: parallel execution of the sweep, now that the shared-`.git` constraint is
  removed; and the dispatch policy that demands a full sweep where none is required.
- Out of scope: the per-suite clone mechanism, the `git-common-dir` gate, and the two
  registry items that ride closes fully — all land with it.
- Out of scope: the probe items below, which are covered in full by the agent-shell
  boundary intake and are named here only because they belong to this registry group.

## Affected Area
- `tests/skills/test-framework.sh` (execution model, tripwire snapshot window,
  `docs/ai/tests/test-runs.jsonl` appends).
- The orchestrator's own validation and remediation dispatch habits.

## Desired Behavior (To-Be)
- The sweep runs suites concurrently at a bounded width, with the tripwire snapshot window
  and the run-record appends made safe under concurrency.
- Intermediate validation and remediation rounds run the SELECTED plus CORE suites; ONE
  full sweep runs before the close ceremony as the evidence the TEST rows cite.

## Acceptance Criteria
- AC-001: a full sweep of all 81 suites completes in materially less wall-clock time than
  the sequential baseline of 1914 s, with the same pass/fail set.
- AC-002: concurrent tripwire snapshots do not interfere; no run reports a HEAD-moved
  detection caused by a sibling suite.
- AC-003: appends to `docs/ai/tests/test-runs.jsonl` are serialised, and the file's
  append-only byte-prefix property holds after a concurrent run.
- AC-004: `.aai/VALIDATION.prompt.md` states which suites a round runs, and an intermediate
  round does not require a full sweep.

## Verification
- Time a full sweep before and after; compare the per-suite verdict set byte for byte.
- Run two suites that both write watched paths concurrently and confirm each is attributed
  to the right suite.
- `node .aai/scripts/select-suites.mjs --files-from <changed files>` output is what an
  intermediate round runs.

## Constraints / Risks
- Parallelism is NOT free, and the ride that filed this said so: the tripwire snapshots the
  shipping tree around each suite and concurrent snapshots would interfere — observed once
  as a HEAD-moved detection — and the `test-runs.jsonl` appends would need serialising.
- `fu-framework-rundir-same-second` (filed with another cluster) becomes sharper under
  concurrency: a second-resolution `RUN_ID` shared by two processes is a collision the
  parallel work must not inherit.
- Measured today: `/usr/bin/grep -c 'test-framework.sh|full sweep' .aai/VALIDATION.prompt.md`
  returns 0 — canon never required the sweep. The corrective for
  `fu-dispatch-demands-full-sweep` is an orchestration habit, not a code change, so it
  cannot be verified by a test alone.

## Notes
- Registry ids covered, read from `docs/ai/decisions.jsonl` on branch
  `fix/suite-isolation-owns-its-git` (they are not yet on `origin/main`):
  `fu-sweep-is-strictly-sequential` (P2), `fu-dispatch-demands-full-sweep` (P2),
  `fu-userguide-catalog-drifts-both-ways` (P2),
  `fu-probe-redirect-lands-in-shipping-cwd` (P2),
  `fu-orchestrator-probe-touched-git` (P3).
- `fu-test210-branch-now-dead-code` is named by the dispatch as a member of this group,
  filed hours before this intake. It is NOT present in `docs/ai/decisions.jsonl` on any ref
  in this clone (checked across `refs/heads` and `origin/main` and
  `fix/suite-isolation-owns-its-git`), so nothing is claimed about its content here.
  Planning should read it directly.
- `fu-userguide-catalog-drifts-both-ways` measured today looks ADDRESSED on `origin/main`
  by commits `2420497` ("give the six undocumented skills a catalog entry, and guard the
  set") and `c6b32d0` ("complete the Quick Reference and guard it too"): all six previously
  missing skills (`aai-ship`, `aai-overview`, `aai-issues`, `aai-routine`,
  `aai-feedback-triage`, `aai-feedback-upsert`) now appear in `docs/USER_GUIDE.md` and all
  six exist under `.claude/skills`. The remaining hits for the seven non-skills are prose
  and example URLs, not catalog rows. Verify before planning work on it.
- The probe items are the AGENT-shell class. The spec's own "NOT CLOSED" section says this
  ride "makes the SUITE path structurally safe and leaves the AGENT path exactly where it
  was". They are scoped in the agent-shell boundary intake, not here.
