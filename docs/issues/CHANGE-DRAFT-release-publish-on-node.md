---
id: release-publish-on-node
type: change
number: null
status: draft
capability: release-command-finish
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run the whole aai-release command in Node, with the release host calls on the platform adapter

## Summary
- Ride 6 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5), slice (b) of two: "tag, publish and PR on the
  platform adapter, then delete the twins". Slice (a)
  ([CHANGE-0251](CHANGE-0251-release-on-node.md), PR #541) moved the
  CHANGELOG rollup, the tag check, the unlogged-PR audit call and the plan
  into `.aai/scripts/release-cut.mjs`.
- What is left in `.aai/scripts/aai-release.sh` (119 code lines) and
  `.aai/scripts/aai-release.ps1` (200 code lines) is written twice: argument
  parsing, the repository and CHANGELOG checks, the version, the remote
  `--confirm` hand-off, the gh probe, the target branch, and the whole local
  cut (release branch, temporary worktree, `AAI_VERSION.md`, commit, report).
  This slice moves all of it into one Node module, and the two scripts
  become thin launchers.
- The host calls of the release (push and release PR create, edit, view,
  merge, the required-checks read, the release workflow and published
  release reads) live in `.aai/scripts/release-finish.mjs` as direct `gh`
  calls. They move onto the provider adapter of
  `.aai/scripts/lib/platform-adapter.mjs`, which already resolves the
  platform record of `docs/ai/pr-config.yaml`.

## Motivation / Business Value
- The pair still disagrees where slice (a) left it: unknown arguments,
  `-h`/`--help`, `--version=<v>`, the cut report header and Remote line,
  the missing-node lines of the remote path, and exit 12 reused for an
  existing release branch with unmerged commits (named in
  `fu-release-slice-b-delete-twins`). Planning measures the full list.
- One copy of the command means one place to fix and one test surface;
  the plan's measure is code lines removed.
- On an Azure DevOps repository the remote release finish runs `gh`
  against a host it cannot reach; with the adapter it resolves the
  platform first and refuses by name before any write.

## Scope
- In scope:
  - One Node module that runs the whole `/aai-release` command (arguments,
    checks, version, the remote hand-off, the platform and authentication
    probe, the plan, the local cut and its report), reusing
    `release-cut.mjs` and `lib/release-rollup.mjs`.
  - `aai-release.sh` and `aai-release.ps1` become thin launchers (same
    names, modes, flags and environment variables); Planning recommends
    whether they stay as permanent entry points or retire after one
    release as deprecation launchers (owner decision 2026-11-05).
  - The release host calls of `release-finish.mjs` go through the
    platform adapter (the GitHub implementation keeps the exact `gh`
    commands); a platform without a release implementation refuses by name
    before any write.
  - An explicit decision, in the spec, for every behaviour difference found
    between the two scripts' remaining steps, each pinned by a test.
  - The slice-(a) leftover `fu-release-ps1-eap-stop-native-stderr`: fixed by
    PR #541 commit `8ca408f1`; closed at this ride's close with that source.
  - Tests (`node:test`, the bash suite, Pester under Windows PowerShell 5.1
    and pwsh 7, a scratch `aai-sync` install), wiring, the RFC-0017 phase 5
    sentence, `.aai/SKILL_RELEASE.prompt.md` if its contract text changes,
    a before and after code-line measurement, and a CHANGELOG
    `## [unreleased] — <title>` entry.
- Out of scope:
  - The CI tag and publish workflow (`.github/workflows/release.yml`) and
    its behaviour.
  - A release implementation for Azure DevOps or another host (named as a
    follow-up if Planning confirms the refusal design).
  - `release-dry-run.mjs`, `lib/release-rollup.mjs`,
    `tests/skills/test-aai-release-first.sh` and
    `tests/skills/lib/release-first.test.mjs` (another session's corpus).
  - The hook gate (`.aai/scripts/claude-hook-gate.sh`), ridden in parallel.

## Affected Area
- `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1`, a new
  Node module under `.aai/scripts/`, `.aai/scripts/release-cut.mjs`,
  `.aai/scripts/release-finish.mjs`, `.aai/scripts/lib/platform-adapter.mjs`
- `.aai/system/PROFILES.yaml`, `.github/workflows/ps1-quality.yml`,
  `.aai/SKILL_RELEASE.prompt.md`
- `tests/skills/` (release suites, Pester files, wiring files)
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/aai-release.sh` and
  `pwsh -File .aai/scripts/aai-release.ps1` run the same Node code: the
  same output, refusal lines and exit codes for the same repository (only
  the flag spellings in printed commands differ).
- Bare and `--dry-run` runs still write nothing; `--confirm --no-remote`
  still cuts a local release branch only; the remote `--confirm` still runs
  `release-finish.mjs`, now through the platform adapter.

## Acceptance Criteria
- AC-001: The remaining release steps run in one Node module; both scripts
  are launchers that hold no release logic and call it.
- AC-002: Every behaviour difference found between the two scripts' remaining
  steps is listed in the spec with a decision and pinned by a test.
- AC-003: `release-finish.mjs` makes no direct host CLI call; its host calls go
  through the platform adapter with the same commands on GitHub, and a
  repository whose platform has no release implementation is refused by
  name before any write.
- AC-004: No test publishes, tags, pushes to a network remote or opens a PR;
  bare and `--dry-run` runs change nothing; `--confirm` semantics are
  unchanged except for drifts the spec lists.
- AC-005: Both launchers pass under bash and under Windows PowerShell 5.1 and
  pwsh 7 (Pester), the `/aai-release` skill keeps working, and a scratch
  `aai-sync` install ships the module and runs the plan through both
  launchers there.
- AC-006: Wiring is complete, the RFC-0017 sentence is added, the removed
  code lines are measured and recorded, and the launcher keep-or-retire
  recommendation is stated in the spec.

## Verification
- The release suites and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes under both engines; the required
  `release-dry-run` CI job passes.
- No test runs a real `gh` or `az`, pushes to a network remote or tags.

## Constraints / Risks
- Consumer-visible and release-sensitive: `/aai-release` is in the core
  profile. The owner merges this pull request.
- Safety: tests use fixtures, stub `gh`/`az` and local bare origins only.
  The default stays a plan; `--confirm` is never run against a real remote.
- Coordination: the SPEC-0257 session works on the release dry-run corpus
  (`release-dry-run.mjs`, `test-aai-release-first.sh`); this ride does not
  edit those files. PR #535 and that session's worktrees are read-only.
- Secrets preflight: no local secret is referenced by this scope; no
  preflight lines are recorded.
- Windows PowerShell 5.1 parity is proven only by the hosted Windows job.

## Notes
- Source: follow-up `fu-release-slice-b-delete-twins` (P2, ref
  `release-on-node`); plan ride 6 row (b) (the owner merges). The roadmap
  item `release-on-node` is marked done after slice (a).
- Related open follow-ups: `fu-platform-adapter-release` (this slice's
  host move), `fu-release-ps1-eap-stop-native-stderr` (closed at ride close,
  source `8ca408f1`).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
