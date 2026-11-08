---
id: release-on-node
type: change
number: 251
status: done
capability: release-on-node
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move the release CHANGELOG rollup and unlogged-PR check of aai-release to one Node module

## Summary
- Ride 6 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5), slice (a) of two.
- The local paths of `/aai-release` (the plan preview, `--dry-run`, and the
  local cut `--confirm --no-remote`) still roll `CHANGELOG.md` with two
  hand-written copies of the transform (an awk program in
  `.aai/scripts/aai-release.sh`, a PowerShell function in
  `.aai/scripts/aai-release.ps1`) and render the unlogged-PR check twice.
  Slice (a) moves the rollup, its refusals, the unlogged-PR check and the
  plan rendering into one Node module. Both scripts call it for those steps
  and keep their names, flags, exit codes and every other step.

## Motivation / Business Value
- Highest-churn twin pair in the plan (290 bash and 351 PowerShell code
  lines; 4 commits to the pair since 2026-09-08).
- The pair already disagrees with the remote path. The remote `--confirm`
  finish (`release-finish.mjs`) and the PR dry-run (`release-dry-run.mjs`)
  roll through the shared `lib/release-rollup.mjs`. The two scripts roll
  with their own copies, which accept some input the shared transform
  refuses (an entry with an empty body or an empty title) and order
  interleaved entries differently. So the plan preview can show a release
  that `--confirm` then refuses or cuts differently.
- The two scripts also disagree with each other: refusal text, the order and
  wording of the plan's precondition lines, the exit code when the rollup
  fails inside the temporary worktree, line-ending handling, and how the
  unlogged-PR list is joined.

## Scope
- In scope:
  - One new Node module under `.aai/scripts/` that reads `CHANGELOG.md`,
    rolls it through the unchanged `lib/release-rollup.mjs`, maps its
    refusals to the existing exit codes 12 and 13, runs the existing
    unlogged-PR audit (`release-finish.mjs --audit`, unchanged), and renders
    the plan and the cut preconditions (tag exists 15, gh blocked 16, missing
    notes 20).
  - Both scripts call the module for those steps; everything else stays in
    the scripts (argument parsing, the repository and CHANGELOG checks, the
    version, the remote `--confirm` hand-off to `release-finish.mjs`, the gh
    probe, the target branch, the temporary-worktree cut, `AAI_VERSION.md`,
    the commit and the cut report).
  - An explicit decision, in the spec, for every behaviour difference found
    between the two scripts and between the scripts and the shared rollup,
    each pinned by a `node:test` case.
  - Tests: `node:test` for the module, a bash suite running both scripts
    against fixtures with a stub `gh`, Pester for the `.ps1` under Windows
    PowerShell 5.1 and pwsh 7, and a scratch `aai-sync` install.
  - Wiring named up front (suite map, weights, cd-subshell baseline, the
    suite-map row-count pins, nested-suite lint, ps1-quality path lists,
    PROFILES), the RFC-0017 phase 5 sentence, a before and after code-line
    measurement, and a CHANGELOG `## [unreleased] — <title>` entry.
- Out of scope (slice (b), a later ride):
  - Tag, publish and release-PR steps on the platform adapter instead of
    direct `gh` calls (open follow-up `fu-platform-adapter-release`), moving
    the remaining script steps to Node, and deleting the two scripts.
  - `release-finish.mjs`, `release-dry-run.mjs` and `lib/release-rollup.mjs`
    are not changed. The audit's classification itself is not changed: the
    module relays its lines.
  - `.aai/SKILL_RELEASE.prompt.md` and the harness wrappers are not changed.

## Affected Area
- `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1`, one new
  module under `.aai/scripts/`, `.aai/system/PROFILES.yaml`
- `tests/skills/` (new suite, `node:test` file, Pester file, wiring files)
- `.github/workflows/ps1-quality.yml`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/aai-release.sh` and
  `pwsh -File .aai/scripts/aai-release.ps1` print the same plan for the same
  repository (only the flag spelling differs), refuse the same CHANGELOG
  with the same exit code and line, and a local cut writes the same
  `CHANGELOG.md` bytes that the remote finish would write for the same base.
- Bare and `--dry-run` runs still write nothing; `--confirm` still hands the
  remote path to `release-finish.mjs` unchanged.

## Acceptance Criteria
- AC-001: The rollup, its refusals, the unlogged-PR check and the plan
  rendering live in one Node module that uses `lib/release-rollup.mjs`; both
  scripts call it for those steps and no longer hold a rollup of their own.
- AC-002: Every behaviour difference found between the two scripts, and
  between the scripts and the shared rollup, is listed in the spec with a
  decision and pinned by a `node:test` case.
- AC-003: A local cut writes the same `CHANGELOG.md` bytes as the shared
  rollup of the same base, and the plan preview names the same rolled
  headings.
- AC-004: Bare and `--dry-run` runs (also with `--confirm`) change no file,
  ref or index in the repository; no test pushes, opens a PR, tags or
  publishes.
- AC-005: Both scripts pass under bash and under Windows PowerShell 5.1 and
  pwsh 7 (Pester), and a scratch `aai-sync` install ships the module and runs
  the plan through both scripts there.
- AC-006: Wiring is complete, the RFC-0017 sentence is added, and the before
  and after code lines are measured and recorded.

## Verification
- The new suite and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes on the pull request under both engines, and the
  required `release-dry-run` CI job passes with the new test files in its
  corpus.
- No test runs a real `gh`, pushes or reaches the network.

## Constraints / Risks
- Consumer-visible: the release command is shipped in the core profile. The
  owner merges this pull request.
- Safety: the release path must never publish in tests. The default stays a
  plan; `--confirm` semantics are unchanged; tests use fixtures and a stub
  `gh` only.
- Coordination: another session is changing the release test corpus
  (SPEC-0257 Spec-AC-05, branches `chore/spec-0257-ac05` and
  `fix/release-corpus-hermetic`). This ride does not edit
  `release-dry-run.mjs`, `lib/release-rollup.mjs`,
  `tests/skills/test-aai-release-first.sh` or
  `tests/skills/lib/release-first.test.mjs`. The new test files will join
  the release-dry-run reader corpus, because they name CHANGELOG.
- Secrets preflight: no local secret is referenced by this scope; no
  preflight lines are recorded.
- Windows PowerShell 5.1 parity is proven only by the hosted Windows job.

## Notes
- Source: roadmap item `release-on-node`; plan ride 6 (the owner merges).
- Pattern precedents: CHANGE-0241 (the reaper port) and ride 3,
  CHANGE-0248 / SPEC-0276 (drift table, one `node:test` case per drift).
- Slice (b) is not added to the roadmap by this intake. It is named as a
  follow-up in the spec.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
