---
id: withdrawn-claim-sweeps-are-not-verifiable
type: techdebt
number: 7
status: draft
links:
  pr: []
  commits: []
---

# A withdrawn claim is corrected by a hand-written sweep that misses whatever it did not think of

## Debt Summary
- On 2026-08-23 an owner decision withdrew the claim that the repo tripwire is
  transitional. Correcting the corpus was done by a regex sweep over a hand-chosen path
  set. The sweep's SCOPE missed a file, its REGEX missed a tense, its own enumeration of
  what it corrected was wrong, and two executable files still assert the withdrawn claim
  today. Six registry items describe one mechanism: the repository has no reliable way to
  retract a statement it has made in many places.

## Root Cause
- A claim spreads across specs, intakes, CHANGELOG entries, test comments and generated
  dashboards. Retracting it is a search problem solved by whoever writes the search, once,
  with no independent check that the search was complete.

## Current Cost / Risk
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-tripwire-suite-comment-transitional` (P3) is LIVE.
  `tests/skills/test-aai-repo-tripwire.sh:529-531` still reads: "Left uncovered
  deliberately — the ratchet is transitional (owner hitl_decision 2026-08-19: tripwire,
  ratchet and hashing are deleted once suites run in a disposable worktree)." The tripwire
  is permanent by `hitl_decision 2026-08-23T20:05:00Z`, which supersedes the 2026-08-19
  one, so the comment states a FALSIFIED reason for leaving an arm uncovered. The coverage
  gap must be re-argued on its own merit or closed. It was not fixed in the correcting
  scope because that scope's AC-005 forbade any executable file appearing in the diff.
- `fu-isolation-suite-presumes-deletion` (P3) is LIVE.
  `tests/skills/test-aai-suite-isolation.sh:638-639` reads: "which is the hard precondition
  for deleting the tripwire: with the tripwire gone, a run where isolation never armed
  would otherwise stay green in silence." Same withdrawn premise, same AC-005 exclusion,
  and validation round 2 found it unfiled — which would have left an executable file
  asserting something the record now denies.
- `fu-sweep-scope-excludes-repo-root` (P2). The correction sweep was scoped to `.aai/`,
  `docs/` and `tests/`, which misses `CHANGELOG.md` at the repository root — the one file
  where an unreleased entry freezes into a permanent dated section at the next release
  cut. Validation found two unreleased entries restating the withdrawn claim almost
  verbatim, on their way into a dated release section.
- `fu-sweep-regex-misses-present-tense` (P2). The AC-004 sweep regex matched only
  future-tense removal wording ("will be removed", "to be deleted", "goes away"), with no
  bare "are/is deleted" alternative. Validation round 2 found SPEC-0138:75 ("they are
  deleted by a separate change") and CHANGE-0152:31-33 ("deleted by a separate one") still
  uncorrected INSIDE AC-004's own declared `docs/**` scope — and both are the document pair
  the correcting spec itself links.
- `fu-spec-d6-enumeration-stale` (P3). The correcting spec's own enumerations undercount
  what it corrected: D6 names 2 specs and 3 intakes while the diff corrects 3 specs and 4
  intakes; the AC-004 Notes cell says one executable surface was filed while two were. And
  "closed as moot" survives at SPEC-0138:87, CHANGE-0152:43 and CHANGELOG:165, where the
  authoritative decision uses `closed` as a precondition for a deletion that is no longer
  planned. Partially remediated since: `CHANGELOG.md:289` now carries a
  "**WITHDRAWN 2026-08-23** by a superseding" annotation beside its "closed as moot"
  sentence; the other sites were not re-checked in this intake.
- `fu-overview-shows-closed-ride-inflight` (P2) is a DIFFERENT mechanism and is recorded
  here because it shares the registry group, not because a sweep fixes it. Measured at
  `.aai/scripts/state.mjs:136`: `PHASES = ['planning', 'preparation', 'implementation',
  'validation', 'code_review', 'remediation']` — nothing terminal — and there is no
  clear-focus mutator. After `close-work-item.mjs` the generated overview keeps publishing
  the finished ride as the current in-flight scope until the NEXT ride calls `set-focus`.
  Two independent bots flagged the shipped `overview-data.json` naming a closed scope as
  in-flight. The dashboard is structurally wrong between every pair of rides.

## Target State
- Retracting a claim is a repeatable operation with a declared corpus (including the
  repository root), a pattern set that covers tense and voice, and a verification pass
  that re-searches independently of the sweep that made the edits.
- A test comment that justifies an uncovered arm cites a decision that is still current,
  or the arm loses its justification.
- STATE gains a terminal phase or a clear-focus, so the overview stops asserting a closed
  ride is in flight.

## Scope
- In scope: the two executable files still carrying the withdrawn claim; the sweep's scope
  and pattern gaps; the stale enumerations; the terminal-phase gap.
- Out of scope: reopening the 2026-08-23 decision. The tripwire is permanent and that is
  settled.
- Out of scope: the tripwire's reporting defects and the ratchet's coverage gaps, filed
  with their own clusters.

## Plan / Migration
- Correct the two test comments and re-argue or close the arms they justify.
- Re-run a widened sweep over `.` including `CHANGELOG.md`, with present-tense
  alternatives, and record the command in the artifact so the next retraction can reuse it.
- Re-check the three "closed as moot" sites.
- Add a terminal phase or a clear-focus to `state.mjs` and regenerate the overview.

## Verification
- `/usr/bin/grep -rn 'transitional'` over `tests/` returns nothing that justifies an
  uncovered arm.
- A repository-wide search for both tenses of the removal wording returns zero live
  assertions of the withdrawn claim.
- After a close ceremony, the generated overview shows no in-flight scope.

## Constraints / Risks
- The correcting scope's AC-005 (no executable in the diff) is what left the two test
  comments behind; a follow-on scope must permit executable edits or the same exclusion
  repeats.
- Adding a phase value changes an enum that `docs/ai/tests/test-runs.jsonl`, the overview
  generator and the dispatch router all read.

## Notes
- Registry ids covered: `fu-tripwire-suite-comment-transitional`,
  `fu-isolation-suite-presumes-deletion`, `fu-sweep-scope-excludes-repo-root`,
  `fu-sweep-regex-misses-present-tense`, `fu-spec-d6-enumeration-stale`,
  `fu-overview-shows-closed-ride-inflight`.
