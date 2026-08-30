---
id: test-runs-jsonl-tracked-ignored
type: issue
number: 71
status: done
links:
  commits:
    - 15c9222
  pr:
    - 317
---

# P2 backlog cluster: suites-must-not-touch-the-shipping-repo (7 items)

## Summary
- Consolidated registry intake for 7 open P2 follow-up(s) filed against `suites-must-not-touch-the-shipping-repo`: `fu-test-runs-jsonl-tracked-ignored`, `fu-acgate-vs-falseopen-catch22`, `fu-tripwire-fail-hides-suite-log-tail`, `fu-parallel-roles-dirty-the-tree`, `fu-tripwire-allowed-ignores-pre-dirty`, `fu-suggested-ids-read-as-filed`, `fu-framework-rundir-same-second`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-test-runs-jsonl-tracked-ignored`**: docs/ai/tests/test-runs.jsonl is tracked AND listed in .gitignore, so tests/skills/test-framework.sh dirties the working tree on every run
  - Measured: gitignore has no effect on an already-tracked file; the harness writing to the shipping repo on every run is the very class this scope closes, and it forces the aai-run-tests.sh tripwire to stay report-only
  - Source: measured 2026-08-19: git status --porcelain=v1 -uno shows a modified docs/ai/tests/test-runs.jsonl after every test-framework.sh run, while .gitignore also lists that exact path

- **`fu-acgate-vs-falseopen-catch22`**: AC STATUS GATE rule 1 blocks PASS on non-terminal AC rows while docs-audit's false-open heuristic fails closed on a terminal AC table with un-timestampable delivery, stripping the CLEAN token and turning TEST-013 red
  - Measured: measured both directions on 2026-08-19; every ceremony-1 scope validated before its delivery commit hits this catch-22 and has to be waived by hand
  - Source: docs/ai/validation/validation-20260819T121957Z-suites-must-not-touch-the-shipping-repo-round1.md

- **`fu-tripwire-fail-hides-suite-log-tail`**: a suite that fails on its OWN exit code AND trips the tripwire prints only the tripwire block, so the failure-lines-plus-tail dump that makes a CI log diagnosable is lost
  - Measured: run_test routes on one outcome value: a non-empty tw_fail_kind rewrites outcome to 'tripwire', so the '*' branch that greps the whole log for failure markers and tails 30 lines never runs for that suite; the reader sees a tripwire report and no reason for the exit code
  - Source: code review of tests/skills/test-framework.sh run_test outcome switch, 2026-08-19 remediation pass for spec-suites-must-not-touch-the-shipping-repo

- **`fu-parallel-roles-dirty-the-tree`**: dispatching a code review and a validation concurrently makes the review's own report file land in the checkout mid-run, which the tripwire correctly reports as a suite dirtying the shipping repo
  - Measured: measured 2026-08-19: the 80-suite aggregate carried one failure (aai-deslop) caused entirely by the parallel reviewer writing docs/ai/reviews/... at 17:12Z; the roles are read-only by contract but their REPORTS are not, so parallel dispatch is unsafe while any framework run is in flight
  - Source: validation round 3 of suites-must-not-touch-the-shipping-repo; aai-deslop re-ran clean standalone

- **`fu-tripwire-allowed-ignores-pre-dirty`**: the ratchet entry path-subset test compares only paths that MOVED, so an allowlisted suite writing an already-dirty non-ratchet path still reads tripwire ALLOWED inside its listed paths at exit 0
  - Measured: validation F4 (suggested id fu-tripwire-attested-clean-ignores-pre-dirty-paths, 50 chars, over the 40-char id limit, so filed under this shorter id) and code review NB-1 both measured it: with a pre-existing M docs/other.md an allowlisted suite writing its listed path AND docs/other.md passes with the out-of-entry write landed. Documented as a stated bound in spec D8 and in the vendored library header this pass, not enforced, because on a clean start a non-ratchet path only becomes pre-dirty after an earlier suite already failed the run, so it degrades a red run's offender list rather than turning CI green; mooted by the recorded disposable-worktree successor
  - Source: docs/ai/validation/validation-20260819T174800Z-suites-must-not-touch-the-shipping-repo-round3.md F4; docs/ai/reviews/review-dual-verdict-suites-must-not-touch-the-shipping-repo-20260819T171200Z.md NB-1 fixture fxC
  - **Note (implementation retriage, 2026-08-30).** "Mooted by the recorded
    disposable-worktree successor" is stale: `docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md`
    already carries its own `**CORRECTION (2026-08-23).**` withdrawing exactly
    this framing — "the successor landed and does not moot it ... it is a live
    defect in a layer that now stays." Independently re-derived here: the
    disposable clone changes WHERE an isolated suite's own work happens, not
    whether the shipping repo can still accumulate cross-suite dirt within one
    run — a ratchet-allowlisted suite (by definition one whose production
    script still writes `$PROJECT_ROOT` regardless of isolation, per the open
    P1 `fu-isolated-suite-reaches-shipping-repo`) can still leave a non-ratchet
    path pre-dirty for a later suite in the same run. Left OPEN, P2, not fixed
    in this ride: the fix needs the framework to diff each suite's own
    before-snapshot rather than a class comparison, which is a real framework
    change, not a config/doc correction, and out of proportion to this ride's
    ceremony budget.

- **`fu-suggested-ids-read-as-filed`**: validation reports list follow-up ids under a 'filed:' key when the role only SUGGESTED them, so the orchestrator relays them as filed and they never enter the ledger
  - Measured: measured 2026-08-19: two ids I passed into a dispatch as already filed were absent from decisions.jsonl, and one exceeded the 40-char id cap so it could never have been filed under that name; a finding that reads as recorded but is not is worse than one openly dropped
  - Source: remediation of code-review BLOCKING-3, 2026-08-19; both ids traced back to round-3 validation's report

- **`fu-framework-rundir-same-second`**: tests/skills/test-framework.sh derives RUN_DIR from a second-resolution RUN_ID, so two framework processes started in the same second share one results dir and overwrite each other's per-suite tripwire snapshots
  - Measured: process B can overwrite A's before-snapshot with an already-dirty porcelain state, so both comparisons read clean and the guard is defeated
  - Source: Codex P2 inline review on PR #266, tests/skills/test-framework.sh:363

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `suites-must-not-touch-the-shipping-repo`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
