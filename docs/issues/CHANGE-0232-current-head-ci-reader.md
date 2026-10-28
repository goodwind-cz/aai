---
id: current-head-ci-reader
type: change
number: 232
status: done
capability: release-command-finish
user_visible: true
links:
  pr: [508]
  commits: [2cf5369a]
---

# Current-head CI result selection

## Summary

First half of the split of `release-passes-first-time`. `watch-ci` and the
release engine judge only the newest check run for each check name on the
current PR head SHA. Cancelled or failed runs superseded by a newer run on
the same head are ignored.

## Motivation / Business Value

Release v2026.10.26 failed because `watch-ci` refused on a cancelled
aggregate while a newer run on the same head was still going and later
passed. A release cut from green main should not stop on a superseded
check.

## Scope

In scope:

- One shared reader/normalizer consumed by `watch-ci` and every release
  required-check observation.
- Bind the PR head SHA, paginate authoritative GitHub check-run and status
  data, reject other-head observations, and select only the newest run of
  each check name using workflow creation identity (not response order or
  success preference).
- Preserve registration grace, required-context filtering, timeout,
  skipped-check and merge-queue semantics.
- Replay fixture for the #504/#506 current-head cancelled-then-success
  shape.

Out of scope:

- Release CHANGELOG dry-run job, rolled-tree test execution, and Git
  metadata report-target protection (child `release-rollup-dry-run`).
- Automatic reruns of infrastructure failures.

## Affected Area

`.aai/scripts/lib/github-checks.mjs`, `.aai/scripts/watch-ci.mjs`,
`.aai/scripts/release-finish.mjs` required-check reads, related tests and
fixtures, `docs/product/release-command-finish.md`.

## Desired Behavior (To-Be)

Given a cancelled red aggregate and a newer successful (or still pending)
run on the same head, `watch-ci` and the release wait report the current
head outcome, not the superseded failure.

## Acceptance Criteria

- AC-001: Given a cancelled run whose aggregate is red and a newer
  successful run on the same head, `watch-ci` (and the release wait)
  reports success, not failure.
- AC-002: Mixed heads, incomplete pagination, malformed identities and
  transport failures refuse closed; they never become PASS.
- AC-003: A replay of the #504/#506 current-head shape does not refuse on
  the cancelled superseded aggregate.

## Verification

- Fixture suites for newest-run selection, queued supersession, mixed
  heads, paging and required filters.
- Historical transport replay from the preserved #504 payload.

## Constraints / Risks

- Node stdlib only. No secret referenced.
- Parent combined ride evidence stays; this child does not re-claim parent
  Validation PASS.

## Notes

- Split from `release-passes-first-time` by
  `docs/decisions/DECISION-release-passes-first-time-split.md`.
- Sibling (parked): `release-rollup-dry-run`.
