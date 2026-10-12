---
id: release-tagged-by-ci-after-merge
type: techdebt
number: 15
status: done
links:
  pr: []
  commits: []
---

# Tech Debt: a release is a PR, and CI tags and publishes it after the merge

## Debt Summary
- `aai-release.sh` assumes a direct push to the target branch. On this repo
  that path never works, because `main` is protected (required checks,
  `enforce_admins`). Every release since 2026-09-01 has taken the fallback:
  a release PR, exit 17, then a manual tail (merge, re-point the tag, push the
  tag, `gh release create`). The skill forbids the agent from running that
  tail.
- Every release is followed by a separate golden-flow record PR (#397, #446,
  #451). Release-prep and notes-fix PRs (#348, #411, #425) add more.
- The script also runs `gh release create`, although `.github/workflows/release.yml`
  (#364) already publishes every pushed tag. That workflow is idempotent and
  has succeeded 10 of 10 times.

## Root Cause
- The protected-branch fallback (CHANGE-0169 / #332) was added as a
  recovery path on top of the direct-push design. It became the only path,
  but the design was never inverted.

## Current Cost / Risk
- Per release: 2 PRs, 2 CI rounds, 2 owner merges and about 10 manual
  commands. About 22% of commits on main since 2026-09-01 are release
  ceremony.
- v2026.10.11 (2026-10-11): `--confirm` in a detached-HEAD worktree committed
  and tagged locally, then died raw on push with exit 1. The script comment
  near `aai-release.sh:537` calls that intended. The fallback run then stopped
  half-done at PR #457 and the owner had to ask for it to be finished.

## Target State
- `/aai-release --confirm` always opens one release PR. The script builds the
  release commit itself, on a branch from `origin/main` in its own temporary
  worktree, so the caller's HEAD state never matters.
- On merge to main of a `chore(release): <version>` commit, CI creates the
  annotated tag on the merge commit and publishes the GitHub release from the
  rolled `[<version>]` CHANGELOG sections, in the same job. A tag pushed with
  GITHUB_TOKEN does not trigger `release.yml`.
- The script never calls `gh release create` and never pushes a tag.
- The golden-flow per-release record PR and the release-time golden-flow
  warning are dropped. CI already runs the full flow (TEST-001 of
  test-aai-golden-flow.sh).
- The "NAMED" no-notes warning either matches the house link style
  (`goodwind-cz/aai#N`) or is removed. Today it flags documented PRs.

## Scope
- In scope: `.aai/scripts/aai-release.sh` and `.ps1`,
  `.aai/SKILL_RELEASE.prompt.md`, `.github/workflows/release.yml` (or a new
  on-merge workflow), golden-flow release check and its record step, release
  test suites, and the exits 16, 17 and 18 that disappear.
- Out of scope: the CHANGELOG `[unreleased]` heading convention and its
  MALFORMED refusal (kept). Downstream projects without the workflow get a
  documented manual tag command; check whether aai-sync vendors workflows.

## Plan / Migration
- Step 1: CI tag-and-publish on a release merge. Until step 2 lands, the
  old fallback keeps working.
- Step 2: PR-only script mode built in its own worktree. Delete the
  direct-push path, the rejection classifier, the pre-cut reset and exits
  17 and 18.
- Step 3: drop golden-flow release coupling and fix or remove NAMED.
- Rollback: revert the workflow; the manual tag commands stay documented.

## Verification
- Integration test: `--confirm` from a detached HEAD, from a dirty main
  checkout and from a clean branch each produces exactly one release PR and
  leaves the caller's checkout byte-identical. No local tag is created.
- Workflow test or dry-run: a merge commit with subject
  `chore(release): vX` yields tag vX on that commit and a release whose
  notes equal the rolled sections. Re-running is a no-op.
- Live proof: the next real release needs only `/aai-release --confirm`
  plus the owner's merge of its PR.

## Constraints / Risks
- The CI job needs `contents: write` (release.yml already has it).
- Windows `.ps1` parity.

## Notes
- Owner direction 2026-10-12: "1 Release přes CI tag", after the complexity
  audit. Replaces the drafts release-finishes-through-protected-branch and
  release-detached-head-cuts-before-refusing (deleted unfiled).
