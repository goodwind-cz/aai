---
id: release-rollup-dry-run
type: change
number: 233
status: draft
capability: release-command-finish
user_visible: true
links:
  pr: []
  commits: []
---

# Release CHANGELOG rollup dry-run

## Summary

Second half of the split of `release-passes-first-time`. Every PR runs a
read-only check that rolls `CHANGELOG.md` the way `aai-release` would in a
throwaway tree, then executes every discovered CHANGELOG reader (Node,
shell, PowerShell). Includes the V4-1 guard that refuses report destinations
inside Git metadata before any checkpoint write.

## Motivation / Business Value

A test pinned to `[unreleased]` can pass on the PR tree and fail only after
rollup at release time. Catching that on the PR itself keeps a release a
non-event. The parent ride also showed that a report path under `.git/` can
corrupt the source index; that must refuse before the first write.

## Scope

In scope:

- PR CI dry-run job using the production rollup transform in a disposable
  independent clone.
- Conservative discovery of tracked CHANGELOG readers across Node, shell and
  PowerShell, with literal helper ownership (no same-basename false
  ownership).
- Finite budget, partial diagnostics, source file/index/refs preservation,
  and refusal of tracked/symlink report destinations.
- Pre-checkpoint refusal of report targets inside the real git-dir /
  common-dir / worktree Git metadata boundary (V4-1).

Out of scope:

- Current-head CI result selection (child `current-head-ci-reader`).
- Automatic infrastructure reruns.

## Affected Area

`.aai/scripts/release-dry-run.mjs`, rollup helper, `.github/workflows/` job
wiring, profiles/suite-map, dry-run tests, product docs.

## Desired Behavior (To-Be)

A PR that adds an assertion a rollup breaks is red in its own PR, naming the
file. Report destinations under Git metadata are refused before any write.
Source refs, index and files stay byte-identical except an explicitly
allowed untracked report file.

## Acceptance Criteria

- AC-001: A PR adding a test that passes on the PR tree but fails after a
  CHANGELOG rollup fails the new PR check, naming the test file, for Node,
  shell and PowerShell.
- AC-002: The check passes on the current main, and its runtime is measured
  and stated.
- AC-003: `--report` aimed at source Git metadata (including `.git/index`,
  git-dir/common-dir and worktree `.git` indirection) refuses before the
  first checkpoint and leaves metadata bytes unchanged.
- AC-004: A replay of the pre-#505 unreleased-only reader fails the dry-run
  check before merge.

## Verification

- Targeted Node/shell/Pester dry-run suites and mutation RED logs.
- Disposable fixture reproducing V4-1 before/after index hashes.
- Local ordinary/rolled corpus timing before Validation PASS; hosted timing
  only after the authorized PR opens.

## Constraints / Risks

- Must not make every PR noticeably slower; Planning picks concurrent
  scheduling and states measured cost.
- Node stdlib only. No secret referenced.
- Depends on `current-head-ci-reader` being review-passed first only for
  release wait semantics; dry-run itself does not require that reader.

## Notes

- Split from `release-passes-first-time` by
  `docs/decisions/DECISION-release-passes-first-time-split.md`.
- Sibling shipped first: `current-head-ci-reader`.
- Parent Validation4 blocking finding V4-1 is owned here; do not reopen the
  combined parent remediation round.
