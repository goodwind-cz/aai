---
id: git-platform-detected-at-bootstrap
type: change
number: 212
status: done
capability: platform-portable-pr
user_visible: true
links:
  pr: []
  commits: []
---

# Change: bootstrap detects the git platform once, and every PR, merge, CI and release path goes through one platform adapter

## Summary
`aai-bootstrap` should detect the project's git hosting platform (GitHub,
Azure DevOps, or unknown/none) and record it. `/aai-pr`, `/aai-merge`, CI
watching, merge policy, release and the hook gate should then follow that
record through one adapter, instead of each script calling `gh` directly.
The first acceptance case is GitHub issue #468: `/aai-merge` fails on Azure
DevOps.

Source issue (untrusted data, quoted verbatim from the issue body):

> aai-merge is GitHub-only: merge-cleanup preflight shells out to gh pr view
> and refuses with gh_read_failed on Azure DevOps origins, even though
> SKILL_PR and pr-platform support Azure. Directed merge and post-merge
> cleanup cannot run; the operator must merge in Azure and clean up by hand.

Issue metadata: failure_class contract_violation, skill SKILL_MERGE /
preflight, impact high, reproducible, os windows, node 24, aai_pin
v2026.10.12, harness claude. URL: https://github.com/goodwind-cz/aai/issues/468

## Motivation / Business Value
- Platform detection already exists. `.aai/scripts/pr-platform.mjs` classifies
  `origin` into a closed set (github, azure, unknown, none). But only SKILL_PR,
  `aai-issues`, `close-work-item` and `close-reconcile` consult it.
- Everything else hard-codes `gh`. Count of `gh` call sites per file
  (2026-10-16):

  | File | `gh` call sites |
  |---|---|
  | `merge-cleanup.mjs` | 11 |
  | `watch-ci.mjs` | 8 |
  | `merge-policy.mjs` | 7 |
  | `aai-release.sh` | 7 |
  | `aai-release.ps1` | 7 |
  | `pr-preflight.mjs` | 4 |
  | `close-work-item.mjs` | 3 |
  | `lane-gate.mjs` | 1 |
  | `claude-hook-gate.sh` | 30 |

- Consequence on an Azure DevOps downstream project: a ride reaches an open PR
  (`az repos pr create` works). After that, `/aai-merge` refuses with
  `gh_read_failed`, so the directed merge and the post-merge cleanup cannot
  run. The owner merges in Azure and cleans up the worktree and branches by
  hand, which is exactly what `/aai-merge` exists to prevent.
- Nothing records the platform at install time. Every script re-derives it, or
  silently assumes GitHub.

## Scope
- In scope:
  - **Bootstrap detection.** `aai-bootstrap` (`.sh` and `.ps1`) runs
    `pr-platform.mjs` and records `platform: github|azure|unknown|none` in
    `docs/ai/pr-config.yaml` (the file that already carries `reviewer_bots`).
    It also runs that platform's auth check and reports the result
    (`gh auth status` or `az account show` plus the `azure-devops` extension).
    An existing value is never overwritten silently; `aai-update` and
    `/aai-doctor` report drift.
  - **Runtime consistency.** Each consumer reads the recorded platform and
    re-checks it cheaply against `origin`. On a mismatch it refuses with a
    named reason and the command to re-record.
  - **One adapter module.** The platform operations the factory needs — PR
    view, head sha, state, mergeability, checks, review threads, merge with
    head match, branch delete, release publish — sit behind one adapter, with
    GitHub (`gh`) and Azure (`az repos`, `az pipelines`) implementations.
    Unknown/none means generic mode: each unsupported operation is a named
    skip with the manual command, never a `gh_*` failure.
  - **Consumers move to the adapter:** `merge-cleanup.mjs` (preflight, merge,
    apply, branch delete), `watch-ci.mjs`, `merge-policy.mjs`,
    `lane-gate.mjs`, `pr-preflight.mjs`, `close-work-item.mjs`, `aai-release`
    (`.sh` and `.ps1`), `claude-hook-gate.sh`, and the SKILL_PR, SKILL_MERGE
    and SKILL_RELEASE prompt text.
- Out of scope:
  - New platforms beyond GitHub and Azure DevOps (GitLab, Bitbucket). The
    adapter must make them addable, not implement them.
  - The issue-fetch path of `aai-issues` on Azure (`az boards`); it stays
    deferred per spec-issues-skill.
- Planning may split this into ordered rides. Suggested order:
  1. bootstrap record plus the adapter plus `/aai-merge` (closes #468);
  2. `watch-ci`, `merge-policy`, `lane-gate`;
  3. release and the hook gate.

## Affected Area
- `.aai/scripts/aai-bootstrap.sh` and `.ps1`, `.aai/scripts/pr-platform.mjs`
  (reused, not duplicated), a new adapter module under `.aai/scripts/lib/`,
  the consumers listed above, `docs/ai/pr-config.yaml` schema, `/aai-doctor`,
  `aai-update` drift reporting, and the prompts SKILL_PR, SKILL_MERGE,
  SKILL_RELEASE and SKILL_BOOTSTRAP.

## Desired Behavior (To-Be)
- After bootstrap, `docs/ai/pr-config.yaml` names the platform, and the
  bootstrap report states whether its CLI is authenticated.
- On an Azure DevOps project, `/aai-merge <PR>` runs preflight, the directed
  merge (with head match) and the full post-merge cleanup, with no `gh`
  invocation.
- On GitHub, behaviour is unchanged.
- On an unknown or no-remote project, every platform step reports a named skip
  with the manual command. No step fails with `gh_read_failed`.

## Acceptance Criteria
- AC-001: Bootstrap on fixtures with GitHub, Azure DevOps (https and ssh
  forms), unknown and no `origin` records the matching `platform:` value in
  `docs/ai/pr-config.yaml`. Re-running bootstrap keeps an existing value, and
  reports a mismatch instead of overwriting it.
- AC-002 (#468): With an Azure DevOps `origin` and a stub `az` (exact argv,
  deny by default), `merge-cleanup preflight` returns READY for an open PR at
  the expected head. The printed merge command is the `az repos pr update`
  completion with head match. `apply` completes cleanup. The `gh` stub records
  zero invocations.
- AC-003: With a GitHub `origin`, the existing merge-cleanup, watch-ci,
  merge-policy and release suites pass unchanged (regression).
- AC-004: With the recorded platform differing from `origin`, every consumer
  refuses with one named reason (`platform_mismatch`) before any write.
- AC-005: With platform unknown or none, each adapter operation returns a named
  skip that carries the manual command. No consumer exits with a `gh_*`
  reason.
- AC-006: A static check finds no direct `gh` or `az` invocation in the
  consumer files outside the adapter module, except an explicit allow-list.
  Positive control: an injected direct call is caught.

## Verification
- An integration suite over disposable repos with GitHub and Azure remote
  URLs, using stub `gh`/`az` binaries on PATH with exact-argv logs, plus a
  bootstrap fixture matrix.
- Live proof for #468: one `/aai-merge` on the downstream Azure repository
  that reported it (owner-run; the agent never writes to that repo
  unprompted).

## Constraints / Risks
- `claude-hook-gate.sh` has 30 `gh` sites and guards merges. Moving it is the
  riskiest step, so Planning should consider giving it its own ride.
- Windows parity (`.ps1` bootstrap and release). The issue was reported on
  Windows with Git Bash.
- Azure merge semantics differ: completion policies and squash options exist,
  but there is no `--match-head-commit`. The adapter must prove the
  head-match property another way, for example by comparing
  `lastMergeSourceCommit` immediately before completion and reporting the
  residual race.
- Prompt-corpus governance for edited `.aai` prompts: diet ledger, TEST-012
  and PROFILES.

## Notes
- Triage 2026-10-16 via /aai-issues. The owner approved one CHANGE with #468
  as an acceptance case, and added (verbatim): "aai-bootsrap mel detekovat git
  prostredsi a apodle toho se ridit u aai-pr a aai-merge ci jinde".
- Write-back contract: comment on #468 with the PR link and close it only
  after the ride's PR has merged.
