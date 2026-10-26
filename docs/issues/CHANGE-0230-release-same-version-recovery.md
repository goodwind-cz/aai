---
id: release-same-version-recovery
type: change
number: 230
status: done
capability: release-command-finish
user_visible: true
links:
  pr: []
  commits: []
---

# A failed release is repaired and finished under the same version

## Summary

`/aai-release --confirm` for v2026.10.26 opened release PR #504, and CI failed it.
The release itself was fine: two tests (`tests/skills/lib/recheck.test.mjs`,
TEST-2819 and TEST-2821) looked up CHANGELOG entries only under
`## [unreleased] — `, and the rollup had renamed them to `## [v2026.10.26] — `.
The test fix (#505) landed on main. The resume then refused with `base-moved —
Remote release base differs from the audited payload; retain this journal/PR and
prepare a newly audited release before merging`.

The only documented way forward is a fresh audited cut, and
`release-finish.mjs` tells the operator to use a new `--version`. One failed
release therefore turns into a second version. The owner wants one release: a
failure is repaired and the same version is finished.

## Motivation / Business Value

A version number is what downstream projects see. Burning v2026.10.26 and
publishing v2026.10.26.1 for the same content is noise, and it teaches the
operator that a failed release means "start over with a new name". A release
should behave like any other ride: it fails, it gets fixed, it finishes.

## Scope

In scope:

- Same-version recovery: when the bound release PR is still open and unmerged
  and the base has moved (or its CI failed and a fix landed on the base),
  `/aai-release --version <v> --confirm` re-audits the current base, rebuilds
  the rollup on it, and updates the SAME release branch and PR, using a lease
  on the old release head. The journal records the re-cut, with the old and
  new base and head. No new version, no second PR.
- Catching the failure class before the PR: the rolled payload runs the checks
  that turned #504 red before the release branch is pushed, or Planning finds
  a cheaper pre-push check that covers it. A CHANGELOG lookup that only
  accepts `[unreleased]` is the measured case.
- The refusal texts, `SKILL_RELEASE.prompt.md` and the product doc
  `docs/product/release-command-finish.md` stop recommending a new `--version`
  for a release that can still be finished.
- Finishing the open v2026.10.26 (PR #504, retained journal) through the new
  path as the acceptance case.

Out of scope:

- Re-releasing a version that is already tagged or published (a published tag
  stays immutable).
- Changing the version scheme.

## Affected Area

`.aai/scripts/release-finish.mjs`, `.aai/scripts/aai-release.sh` and
`aai-release.ps1`, `.aai/SKILL_RELEASE.prompt.md`,
`docs/product/release-command-finish.md`, the release tests.

## Desired Behavior (To-Be)

A release that failed before merge is finished under its own version. The
operator re-runs `/aai-release --version <v> --confirm` after the fix. The tool
re-audits, rebuilds and updates the same PR, waits for CI, merges, tags and
publishes once. A version is never consumed by a failed attempt.

## Acceptance Criteria

- AC-001: With an open, unmerged bound release PR and a moved base,
  `--version <v> --confirm` re-audits the new base, rebuilds the rollup and
  updates the same branch and PR under a lease on the recorded head. It does not
  refuse with base-moved, and it does not ask for a new version.
- AC-002: A re-cut that would lose work is refused, naming the cause: the
  release branch head differs from the journal, the PR was merged or closed,
  or the tag already exists.
- AC-003: The release-sensitive check that failed #504 runs on the rolled
  payload before the push; a CHANGELOG lookup pinned to `[unreleased]` fails
  the cut locally, naming the file.
- AC-004: No refusal text, prompt or product doc tells the operator to cut a new
  `--version` for a release that can still be finished.
- AC-005: The open v2026.10.26 (PR #504) is finished as v2026.10.26 through the
  new path: one PR, one merge, one tag, one GitHub release.

## Verification

- Release suite rows for AC-001..003, red before the change, using a fixture
  remote, a moved base and a failing CI arm.
- AC-005 is checked on the real repository after merge.

## Constraints / Risks

- Merging the release PR stays under the operator confirmation the release
  skill already requires. The owner confirmed v2026.10.26 on 2026-10-26.
- The re-cut force-updates only the release branch, with a lease, and never
  rewrites a merged or tagged state.
- Secrets preflight: no secret referenced.

## Notes

- Owner, 2026-10-26: "to se mi nelibi, mel jsi udelat jeden release a ne dalsi
  release protoze se nepovedl ten prvni, udelej z toho intake".
- #504 and its journal under /private/tmp/aai-release are left untouched for AC-005.
