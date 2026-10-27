---
id: release-passes-first-time
type: change
number: 231
status: superseded
capability: release-command-finish
user_visible: true
links:
  pr: []
  commits: []
---

# A release passes CI on its first attempt

> Superseded 2026-10-27 by owner split decision
> `docs/decisions/DECISION-release-passes-first-time-split.md`.
> Children: `current-head-ci-reader` (first) and `release-rollup-dry-run`
> (parked). Bytes and Validation4 evidence stay.

## Summary

Release v2026.10.26 needed three CI rounds on PR #504:

1. **Test pinned to `[unreleased]`.** `tests/skills/lib/recheck.test.mjs` (TEST-2819, TEST-2821) looked up CHANGELOG entries only under `## [unreleased] — `. The rollup renames those headings to `## [v2026.10.26] — `, so the tests failed. The recheck PR that introduced them was green, because no PR check runs tests against a rolled CHANGELOG. Fixed by #505.
2. **Stale aggregate from a cancelled run.** After the same-version re-cut (#506), the engine pushed and then edited the PR body. That started a second CI run and cancelled the first. The first run's aggregate check ("skill test suite") stayed red, and `watch-ci` refused on it while the second run was still going and later passed.
3. **Windows runner infrastructure.** On PR #506, the Windows jobs failed on PowerShell Gallery `RepositoryNotFound` and an `EBUSY` temp rmdir. A rerun passed.

The release preflight from #506 is the last line of defence. It runs only node tests that read `CHANGELOG`, and only when a release is cut. A shell or PowerShell suite pinned to `[unreleased]` still fails the release PR the first time.

## Motivation / Business Value

A release should be a non-event: one command, one green CI, one tag. Each failed attempt costs an hour of CI and operator attention. It also pushes the operator toward workarounds such as a new version, which the owner explicitly rejected on 2026-10-26.

## Scope

In scope:

- **Release dry-run in PR CI.** A check on every PR rolls `CHANGELOG.md` the way `aai-release` would in a throwaway tree. It then runs every test that reads `CHANGELOG.md`: node, shell and PowerShell. A test that passes on the PR tree and fails on the rolled tree fails the PR, naming the file. Planning measures which suites read `CHANGELOG.md` and what the check costs.
- **CI reading bound to the current head.** `watch-ci` and the release engine judge only the newest check run for each check name on the current head SHA. Cancelled runs superseded by a newer run on the same head are ignored. Planning may instead keep the release from editing the PR body after a push, if that removes the second run.

Out of scope (owner chose a smaller scope 2026-10-27):

- Automatic reruns of jobs that fail on known infrastructure errors (PSGallery, EBUSY, lost runner communication). Kept as a candidate for a later ride.

## Affected Area

CI workflows (`.github/workflows/`), the suite selection and impact map, `.aai/scripts/watch-ci.mjs`, `.aai/scripts/release-finish.mjs` (if it stops editing after push), the release tests, and `docs/product/release-command-finish.md`.

## Desired Behavior (To-Be)

A PR that adds an assertion pinned to `[unreleased]` (or anything else a rollup breaks) is red in its own PR, naming the file. A release cut from a green main passes CI on its first run. A cancelled, superseded CI run never decides a release.

## Acceptance Criteria

- AC-001: A PR adding a test that passes on the PR tree but fails after a CHANGELOG rollup fails the new PR check, naming the test file. This applies to node, shell and PowerShell tests.
- AC-002: The check passes on the current main, and its runtime is measured and stated.
- AC-003: Given a cancelled run whose aggregate is red and a newer successful run on the same head, `watch-ci` (and the release wait) reports success, not failure.
- AC-004: A replay of the #504 history passes: the recheck PR's tests fail the new check before merge, and the re-cut wait in #506's flow does not refuse on the cancelled run.

## Verification

- Suite rows for AC-001..003, red before the change, on fixtures.
- AC-004 via a replay on scratch clones of the real history.

## Constraints / Risks

- The new PR check must not make every PR noticeably slower. Planning picks the cheapest way to cover all CHANGELOG readers.
- Node stdlib only for scripts. CI changes follow the existing workflow conventions.
- Secrets preflight: no secret referenced.

## Notes

- Owner, 2026-10-27: asked what to fix so a release passes the first time, then chose to record it as an intake only and ride it later.
- Related follow-ups: `fu-release-preflight-scrubbed-env` (P2) and `fu-release-unjournaled-recut-merged-old` (P3).
