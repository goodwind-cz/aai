---
id: release-protected-branch-fallback
number: 169
type: change
status: done
links:
  pr:
    - 332
  commits:
    - b84819c
---

# aai-release should fall back to a PR when main is a protected branch

## Summary
- `.aai/scripts/aai-release.sh` (and its PowerShell twin) perform the release
  cut's commit, tag, and `git push origin <branch>` directly against
  whatever branch the release is cut from — assuming that push succeeds.
- When that branch is a GitHub-protected branch requiring status checks (a
  common, unexceptional repository setting — this very repo, `goodwind-cz/aai`,
  has it on `main`), the push is rejected outright (`GH006: Protected branch
  update failed`, "3 of 3 required status checks are expected"), and the
  script has no fallback: it has already committed and tagged locally, then
  simply fails to publish, leaving the operator to untangle a
  half-finished cut by hand.

## Motivation / Business Value
- AAI is deployed to downstream projects it doesn't control the branch
  settings of; a protected `main` is one of the most standard GitHub
  configurations a real project can have. Any downstream project with this
  setting hits the exact same wall on its very first `/aai-release --confirm`.
- Observed directly cutting `v2026.09.01` for AAI itself (this repo) on
  2026-09-01: the script committed `chore(release): v2026.09.01` locally,
  created the annotated tag, pushed the tag to origin successfully, then the
  branch push was rejected. Recovery required manually moving the commit onto
  a new branch, resetting `main` back to origin, opening PR #329, and — once
  merged — will require re-pointing the already-pushed tag at the resulting
  merge commit. None of this is scripted; all of it was done by hand,
  mid-session, under time pressure to keep the release moving.
- A scripted fallback removes this as an operator-facing surprise: the tool
  itself detects the wall and does the mechanical recovery, instead of
  leaving a half-cut release for a human (or an agent working from
  incomplete context) to reconstruct correctly.

## Scope
- In scope: detecting a protected-branch push rejection in
  `aai-release.sh`/`.ps1`'s CONFIRM path, and automatically falling back to
  creating a release branch, pushing it, and opening a PR carrying the
  release commit — then STOPPING and reporting, rather than pushing to the
  target branch directly. Correctly re-pointing the tag at the PR's eventual
  merge commit is part of this scope only as far as documenting/reporting
  the follow-up step needed; actually performing the re-tag after a
  human-driven merge is explicitly out of scope (see Desired Behavior).
- Out of scope: having the release script itself wait for CI and merge the
  PR — that would cross the same operator-only-merge boundary AAI already
  enforces for every other work item's SKILL_PR flow, and this change should
  not carve out a special exception for releases. Also out of scope:
  detecting or working around any OTHER class of push rejection (e.g. a
  stale local branch, an actual auth failure) — this change targets
  specifically the protected-branch/required-status-checks rejection shape.

## Affected Area
- `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1` (the CONFIRM
  cut sequence's push step).
- `.aai/SKILL_RELEASE.prompt.md` (Usage/Safety sections need a paragraph
  documenting the fallback path and the manual re-tag step it still leaves
  for the operator).

## Desired Behavior (To-Be)
- On `--confirm`, after the local commit + annotated tag are created, the
  script attempts `git push origin <branch>` as today. If that push is
  rejected specifically as a protected-branch/required-status-checks
  failure (matching GitHub's `GH006` message, or the equivalent for other
  git hosts if/when supported), the script does NOT fail silently or leave
  the operator to figure out recovery:
  - it creates a new branch (a deterministic name, e.g.
    `chore/release-<version>`) at the release commit,
  - resets the local target branch back to its pre-cut position (matching
    origin), so the target branch is left clean,
  - pushes the new branch and opens a PR via `gh pr create` carrying the
    release commit,
  - reports clearly to the operator: the PR URL, that CI must pass and the
    PR must be merged before the release is live, and that the annotated
    tag already pushed to origin points at a commit that will need to be
    re-pointed at the PR's eventual merge commit after merge (since a squash
    merge produces a new commit hash) — spelling out the exact
    `git tag -d`/`git tag -a`/`git push` sequence needed, not just naming the
    problem.
  - When the target branch is NOT protected (the common case for most
    projects), behavior is completely unchanged: direct push, immediate `gh
    release create`, done in one shot.

## Acceptance Criteria
- AC-001: Running `--confirm` against a branch protected by required status
  checks results in a new release branch + open PR (not a failed push and a
  stuck local commit), with the script's own output naming the PR URL and
  the exact remaining manual step (re-tag after merge).
- AC-002: Running `--confirm` against an unprotected branch is unaffected —
  same single-shot commit/tag/push/publish behavior as today, verified via
  the existing release-script tests/fixtures.
- AC-003: The script never leaves an orphaned or dangling tag as a *silent*
  outcome — either the tag correctly points at the branch's tip after a
  same-shot cut, or the operator is explicitly told the tag is provisional
  and exactly what to do about it once the fallback PR merges.
- AC-004: No change to the `--dry-run`/plan-only path's behavior or output
  shape (this change only alters what happens inside the CONFIRM branch's
  push step).

## Verification
- Command(s) and expected results:
  - Fixture/integration test against a scratch bare repo with a simulated
    protected-branch rejection (a local `pre-receive`-style hook or a
    stubbed git remote that rejects the push with the GH006 message shape)
    — `--confirm` must produce a new branch + local reset + a reported
    "would open a PR" or actual PR-create call (mockable in the test), and
    must NOT report the release as fully published.
  - Fixture/integration test against a scratch repo with an unprotected
    remote — `--confirm` behavior byte-identical to pre-change.
  - Manual/real-world verification: this exact scenario already reproduced
    live on `goodwind-cz/aai` cutting `v2026.09.01` (PR #329) — that
    incident's transcript is the reference reproduction case.

## Constraints / Risks
- Detecting "this specific rejection reason" from `git push`'s stderr is
  inherently a string/pattern match against GitHub's message text (`GH006`,
  "protected branch", "required status checks") — must degrade gracefully
  (report the raw failure, don't silently swallow it) if the message shape
  ever changes or another git host's protected-branch rejection wording
  differs.
- Must not weaken or bypass the existing "never auto-merge / --confirm is
  operator-only" safety rule — the fallback opens a PR and stops; it must
  never itself call `gh pr merge`.
- The re-tag-after-merge step is manual by design (see Scope) — if a future
  iteration wants to automate that too, it would need to watch the PR to
  completion, which is a separate, larger scope decision the same operator-
  merge boundary applies to.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Reference incident: `goodwind-cz/aai` PR #329 (`chore(release):
  v2026.09.01`), 2026-09-01 — direct push to `main` rejected by branch
  protection after the local commit + tag were already created; recovered
  by hand (new branch, reset main, open PR, tag re-point still pending the
  PR's merge at the time this was filed).
- Related: filed alongside three other systemic-friction intake docs from
  the same retrospective review:
  [[metrics-flush-invalidates-pr-precondition]],
  [[role-progress-heartbeat]], [[ac-table-premature-flip-recurs]].
