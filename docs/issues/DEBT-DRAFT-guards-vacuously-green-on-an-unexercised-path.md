---
id: guards-vacuously-green-on-an-unexercised-path
type: techdebt
number: null
status: draft
links:
  pr: []
  commits: []
---

# Guards that compare a file against itself pass for a year on the path nobody takes

## Debt Summary
- Two release guards structurally FORBADE the correct workflow and nobody noticed,
  because the workflow they forbade was never exercised. They passed vacuously: on the
  path actually taken, each compared a file against itself. The two instances are fixed;
  the CLASS — a guard whose green is produced by an untaken code path — is what stays
  open.

## Root Cause
- A guard is written against the workflow in use at the time. Its assertion is then
  degenerate on that workflow (both sides of the comparison are the same bytes), so it
  cannot fail, and its inability to fail is indistinguishable from correctness.
- The day the project moves to the workflow the guard was nominally protecting, the
  guard fires against the legitimate change instead of the illegitimate one.

## Current Cost / Risk
- `fu-release-guards-forbid-release-by-pr` (P1, 2026-08-23, PR 282, run 32673062532 job
  97276772806): "test-aai-release TEST-024 and TEST-025 both structurally forbid cutting
  a release through a pull request, and both passed only because releases pushed straight
  to main."
- Measured in that entry: "TEST-024 required every merge-base unreleased heading to
  survive verbatim as unreleased, which a roll renames by definition, so it failed all
  nine at once; TEST-025 compared the live released region against the latest ancestor
  tag from line 1, and a release PR inserts a new section above it. On the old direct-push
  path merge-base was HEAD and the new tag was already the latest ancestor, so both
  compared a file against itself and passed vacuously."
- Both were fixed in PR 282 and bite-proved against a real deletion and a real glue. On
  `origin/main` today both arms carry explicit unreachable-ref and no-merge-base skip
  branches (`tests/skills/test-aai-release.sh:818-894`, TEST-024 at 830/836/841, TEST-025
  routing through `released_region_verdict`).
- The cost of the class: a release could not be cut by PR at all until someone tried and
  hit nine simultaneous failures. Any other guard in the same shape is silent until the
  day it is not.

## Target State
- A guard whose assertion is degenerate on the currently-exercised path is either
  (a) exercised by a fixture that takes the other path, or (b) declares itself SKIPPED or
  UNCOVERED on the degenerate path instead of PASSED.
- The repository already has the second pattern: `tests/skills/test-aai-repo-tripwire.sh`
  reports `UNCOVERED` and FAILS rather than passing when its premise no longer holds
  (TEST-013 at line 831/835, TEST-014 at 961/971/983/991). The pattern exists and is not
  applied generally.

## Scope
- In scope: a way to detect or refuse the vacuous-green shape — a guard that compares two
  expressions that are identical on the path CI actually takes.
- In scope: a survey of guards whose green depends on a workflow assumption (direct push
  vs PR, one worktree vs many, one branch vs a fork).
- Out of scope: the two release-guard instances. They are fixed and bite-proved.
- Out of scope: the separate, adjacent class of a check reading a WEAKER SIGNAL than the
  claim it makes (`fu-test028-exitcode-not-clean`), filed with its own cluster.

## Plan / Migration
- Inventory the guards whose comparison collapses under the default CI workflow.
- For each, either add a fixture that takes the non-default path, or convert the
  degenerate outcome from PASS to SKIP/UNCOVERED so the gap is visible in the log.
- Prefer the `UNCOVERED` idiom already shipped in the tripwire suite, so a premise loss
  reads as a failure and not as coverage.

## Verification
- For each converted guard, mutate the thing it claims to protect and observe a red; then
  restore and observe a green. Do the mutation in a disposable copy, never in a tracked
  file.
- A release cut through a PR completes with `aai-release` green — already true on
  `origin/main`, and the regression to watch.

## Constraints / Risks
- Detecting "these two expressions are identical on the taken path" mechanically is hard
  in shell; the realistic first step is the manual inventory plus the UNCOVERED idiom.
- Converting PASS to SKIP on a degenerate path lowers the apparent green count, which is
  the correct signal but reads as a regression to anyone counting passes.

## Notes
- Registry ids covered: `fu-release-guards-forbid-release-by-pr` (P1, class only).
- The instance-level fix is already on `origin/main`; this intake must not be planned as
  a re-fix of TEST-024 and TEST-025.
