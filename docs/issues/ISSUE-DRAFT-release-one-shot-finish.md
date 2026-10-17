---
id: release-one-shot-finish
number: null
type: issue
status: draft
user_visible: true
capability: release-command-finish
links:
  pr: []
  commits: []
---

# Release finish stops twice on a live run: unreported required contexts and the ref-guard on the base sync

## Summary
- The first live run of the release finish (v2026.10.17.3, PR #476) stopped twice, both times fail-closed, and each stop needed a manual resume:
  1. `release-finish.mjs` waits only on `gh pr checks --required`, which lists required checks that have already reported. A required context of the base branch that has not reported yet is invisible, so the engine settled on 2 of 3 required checks and `gh pr merge` failed with "the base branch policy prohibits the merge" (refused as `github-command`).
  2. After publication, the registered-base fast-forward (`git update-ref --stdin` transaction into `refs/heads/main`) was refused by this repository's `AAI:REF-GUARD` reference-transaction hook because `AAI_GIT_WRITE=1` was not set, so the run refused `base-transaction` and needed a manual `AAI_GIT_WRITE=1` resume.

## Type
- bug

## Impact
- Every operator running `/aai-release --confirm` on a repository whose base branch requires a context that reports late (here `skill test suite (tests/skills/, via test-framework.sh)`), and every repository with the `AAI:REF-GUARD` hook installed (this repository and downstream repos that accepted it) that has a registered base checkout.
- Severity/priority: P2. No unsafe merge or write happened (both stops are fail-closed), but the "one confirmed run" promise of the release finish is broken on the common path, and each stop costs a manual resume. Ledger follow-up `fu-release-required-contexts-unreported` (P2, ref `release-command-finish`) is closed by this scope.

## Current Behavior
- Required checks (release-finish.mjs `requiredChecks()` / `registeredChecks()` around lines 359-379, and `watch-ci.mjs --required`): the set of required checks is whatever `gh pr checks --required` reports at the time. Branch protection on `main` requires 3 contexts (`gh api repos/goodwind-cz/aai/branches/main/protection --jq .required_status_checks.contexts`): "skill test suite (tests/skills/, via test-framework.sh)", "self-hosting smoke (...)", "doc-numbering guards (...)". The first reports late; watch-ci settled on 2/2 passing, the post-watch read also saw 2/2, and `gh pr merge` was refused by GitHub. The engine classifies that refusal as a generic `github-command` (exit 20).
- Base sync (release-finish.mjs `baseTransaction()` around line 229): the transaction child inherits the caller environment only. With the `AAI:REF-GUARD` hook installed and `AAI_GIT_WRITE` unset, `prepare` is refused by the hook, so `syncBase()` refuses `base-transaction` after the release is already merged, tagged and published.
- Secondary: a closed PR on `chore/release-<version>` (closed PR #473 for v2026.10.17.2) blocks reusing that version with a generic identity message ("Existing or ambiguous release PR has no matching journal" / "Bound release PR is closed without merge") that names neither the PR nor the remedy.

## Expected Behavior
- The engine learns the base branch's required contexts from GitHub (classic branch protection and/or repository rulesets) and waits, bounded by the existing wait limits, until every required context has reported and passed before it merges. A required context that fails refuses at once; one that never reports refuses with a named cause after the bounded wait. Fail-closed semantics are kept.
- When the required contexts cannot be read (no permission, endpoint absent, unprotected branch), the engine degrades explicitly with a printed named line and keeps today's behavior (wait on reported required checks); GitHub's own merge-time policy stays the final gate.
- GitHub's "base branch policy prohibits the merge" refusal is a named, retryable pending state (`PENDING: merge-policy`, exit 8, exact resume command), not a generic `github-command` refusal.
- The registered-base fast-forward completes in one run on a repository with the `AAI:REF-GUARD` hook, through a deliberate, narrow exception scoped to that single base ref transaction (never ambient), and still works unchanged in repositories without the hook.
- A closed release PR refusal names the PR number and the remedy.

## Steps to Reproduce (if applicable)
1) In a repository whose base branch requires a context that reports after the other required checks, run `/aai-release --confirm`.
2) Observe watch-ci settle on the reported required checks only and `gh pr merge` fail with "the base branch policy prohibits the merge"; the run exits 20 `github-command`.
3) Resume after the late context passes; the merge, publication and cleanup complete.
4) With `.git/hooks/reference-transaction` carrying `AAI:REF-GUARD` and a registered `main` checkout, observe `REFUSED: base-transaction` at the base sync; a resume with `AAI_GIT_WRITE=1` set completes it.

## Verification
- Stubbed `gh` in `tests/skills/test-aai-release.sh` whose branch-protection/ruleset answer lists a context that reports late: the engine waits for it and merges exactly once, after it passed; a context that never reports refuses with a named cause and zero merge calls; a failed context refuses at once.
- Stubbed protection/ruleset endpoints that are unreadable: a named degrade line is printed and the run proceeds on reported required checks; a stubbed policy merge refusal exits 8 `PENDING: merge-policy` with the resume command, and the resume merges once.
- Fixture repository with the real `AAI:REF-GUARD` hook installed and `AAI_GIT_WRITE` unset: the confirmed run completes with `- Base: synced`; exactly one git invocation (the base `update-ref --stdin` transaction) receives `AAI_GIT_WRITE=1`.
- Existing release suites stay green (including the PowerShell frontend parity case).

## Constraints / Risks
- Assumption: classic protection is read through the read-access branch endpoint (`GET repos/{owner}/{repo}/branches/{branch}`, `protection.required_status_checks`), not the admin-only protection endpoint; rulesets through `GET repos/{owner}/{repo}/rules/branches/{branch}`. Planning confirms the response shapes and the degrade rules.
- Assumption: the ref-guard exception belongs in the engine, set only on the one base ref transaction it already verifies as a fast-forward to the verified merge SHA; the frontends and SKILL_RELEASE do not set it (that would be ambient for the whole engine process tree). Planning records the decision.
- Risk: the deny-default `gh` stub in the release suite dies on unknown argv, so every new GitHub call must be taught to the stub (with a default answer that keeps existing cases green).
- release-finish.mjs is shared by `aai-release.sh` and `aai-release.ps1`; parity is inherited but the PowerShell case must stay green.
- Secrets preflight: no secret referenced.

## Notes
- Metrics: human_time_minutes null (autopilot default). No clarifying questions asked; assumptions above are explicit.
- Implementation mode: not chosen at intake (autopilot); Planning decides.
- Source: live run of v2026.10.17.3 (PR #476), 2026-10-17; prior refusal on v2026.10.17.2 (PR #473).
