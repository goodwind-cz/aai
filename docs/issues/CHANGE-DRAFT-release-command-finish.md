---
id: release-command-finish
type: change
number: null
status: draft
capability: release-command-finish
user_visible: true
links:
  pr: []
  commits: []
---

# Complete a release through one resumable owner-confirmed command

## Summary
Narrow release-finish split from release-one-command-no-findings after two independent finding-bearing validation rounds. Standalone PR notes gate and local/CI wiring are delivered separately by release-notes-pr-gate. This scope owns the historical audit, remote release completion, resume, publication verification, safe cleanup and native capture.

## Motivation / Business Value
The v2026.10.12 cut needed separate merge and verification steps, exposed missing-note false positives, and encountered an empty native-output failure. The owner directed release --confirm to merge only the release PR created by that run and finish publication.

## Scope
- Release history audit uses authoritative remote base/object metadata, including Git executable mode, and refuses real note omissions before preparing/pushing/creating a PR.
- CHANGELOG-only, previous release PR and explicit same-line nonempty no-notes markers are classified accurately using the shared notes-gate contract.
- One explicit version/repository/base/release-head/PR identity progresses through required CI, pinned merge, release.yml, peeled tag/body verification, leased branch cleanup and safe base sync.
- Resume completes missing stages without duplicate artifacts; remote identity changes refuse truthfully by name. Pending checks exit8 are waited for; degraded/error results never pass.
- Preserve unrelated dirty/detached/feature callers. Manual no-workflow tagging and no-remote local cuts remain explicit skips; dry-run writes no persistent refs/journal/GitHub state.
- Shell and PowerShell share the dependency-free finish implementation, validate required output, and retain Windows 5.1/pwsh7 contract.
- Release prompt/user/product docs, workflow notes extraction and measured packaging/test companions follow this scope only.
- Out of scope: standalone PR notes gate implementation/CI/localPR wiring, generic merge policy, branch protection or protected constitution edits.

## Desired Behavior (To-Be)
A clean normal --confirm ends with named version, merged PR SHA, verified tag/release URL, deleted branch and synced base. Failures identify completed stages and an exact version-specific resume command. Missing history is a refusal, not guessed clean history. Confirm can fetch missing commit objects without changing caller refs/FETCH_HEAD; write-free preview refuses if authoritative objects are unavailable.

## Acceptance Criteria
- AC-001: CHANGELOG-only/previous release/valid marker classifications cause no false finding; real omissions, including extensionless executable added/deleted/chmod and a stale origin tracking ref, refuse before any refs or GitHub mutations.
- AC-002: Green settled required checks allow only the bound PR/head merge with --match-head-commit; pending exit8 settles through watcher; failed/degraded/missing checks stop. Remote base movement before the final check stops merge with explicit resume.
- AC-003: Successful workflow on merge SHA yields matching peeled tag and exact rolled notes in the GitHub release. Wrong workflow/SHA/body refuses before cleanup.
- AC-004: Every interruption resumes without duplicate PR/merge/tag/release; remote branch cleanup uses expected-head lease, dependency/moved-head checks; divergent/dirty bases and feature/worktree callers preserve data truthfully.
- AC-005: Native required SHA/URL normal/empty/error controls pass on PowerShell and Linux; 20 actual TEST033 executions on the Linux CI runner pass without skips. Windows5.1/pwsh7 execution remains required evidence; local/container proof never claims hosted execution.
- AC-006: Release documentation describes narrow authorization and compatibility/refusal/resume paths, profiles/suite mapping/prompt ledger/generated companions are accurate, and affected suites plus independent review pass.

## Verification
Disposable origins perform real Git commits, pushes, merge transition, workflow notes shell, tags and cleanup; only GitHub transport is stubbed with exact deny-by-default argv and values. Independent real-caller/remote-base race probes are required. No live release is performed by this development ride. Hosted CI follows pushed source; Planning must describe honestly how that evidence requirement interacts with the pre-commit Validation gate, without self-authorizing a waiver.

## Constraints / Risks
Owner narrow release-only merge direction from2026-10-12 stays authorized; every other PR merge boundary is unchanged. GitHub CLI pins PR head and cannot atomically pin the base between observation and merge: retain that external race limitation explicitly rather than promising an unsupported conditional API. Zero dependencies, NodeESM, bash3.2, PS5.1/7. No secrets referenced. Original full-scope RED chronology cannot be retroactively represented as RED-first; new split evidence must distinguish reused prechange replays and fresh controls.

## Notes
Source implementation and immutable original FAIL reports preserved in /private/tmp/aai-release-one-command-worktree. Audit split fixes have observed RED then passing target and legacy suites, not an independent verdict. Notes-gate branch is a dependency; final implementation worktree will start from its reviewed commit and use explicit scoped diff. Intake human time null/autopilot; Planning chooses strategy.
