---
id: node-first-cleanup
type: change
number: null
status: draft
capability: node-first-cleanup
user_visible: false
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Node-first cleanup: measured suite weights and the open P2 follow-ups

## Summary
- RFC-0017 phase 5 is done (PR #582) and release v2026.11.24 shipped from
  main 492f8b26. This ride closes the open P2 follow-ups left by the
  Node-first migration and its neighbours, in one pull request. The P3
  leftovers go in a second ride, so that the P2 items and the weights land
  first (owner brief 2026-11-24).
- Items in scope:
  1. `fu-suite-weights-placeholder-196`: re-measure the suite weights from
     successful hosted full runs on main. Make the eight closed-spec tests
     that pin 196 accept a measured weight (TEST-4019, TEST-3475, TEST-3977,
     TEST-3958, TEST-3512, TEST-3997, TEST-3571, TEST-3458), recording each
     edit as an additive-with-disclosure amendment. Then set the
     selected-sharded job's `timeout-minutes` in
     `.github/workflows/skill-suite.yml` back from 25 to 15, provided the
     shards fit.
  2. `fu-release-pwsh-identity-crash`: the release dry-run records
     whatever `pwsh` printed as the PowerShell identity, crash text
     included.
  3. `fu-release-preflight-scrubbed-env`: the release preflight runs
     repository tests from a linked worktree of the real repository with
     the operator's whole environment. On the cut of v2026.11.24 it printed
     `tests/skills/lib/aai-release.test.mjs FAILS ON BASE TOO`.
  4. `fu-seterr-suspended-left-of-or`: a shell function called on the left
     of `||` or `&&` runs its whole body with `set -e` suspended.
  5. `fu-hook-gate-skips-renamed-doc`: the pre-commit index hook lists
     staged docs with `--diff-filter=ACM` under default rename detection,
     so a doc renamed in the commit escapes the close gate and the body
     lint.
  6. `fu-merge-sync-writes-via-parent-link`: merge-cleanup `sync-base` and
     `resumeSync` lstat only the last path component, so they can write
     outside the checkout through a symlinked parent directory.

## Motivation / Business Value
- Weights: PR #582's selected-sharded shard 1 was cancelled at the
  15-minute bound twice, because the planner believed the new node-first
  suites took 196 s each. The hosted logs show otherwise: aai-sync-node
  took 613 s and aai-release 483 s in that run. The owner raised the bound to
  25 minutes as a stopgap and asked for real weights.
- Release preflight: on the owner's Mac, pwsh 7 crashes at startup because
  of a corrupted `~/.cache/powershell/StartupProfileData-NonInteractive`.
  Measured on 2026-11-24: TEST-4027 of `aai-release.test.mjs` (three cases)
  fails with the `FileLoadException` crash text under the operator
  environment, and all 47 cases pass with a fresh `XDG_CACHE_HOME`. The
  preflight also hands the same environment, including gh credentials, to a
  test running in a linked worktree of the real repository.
- The other three items are guard gaps. The close gate skips exactly the
  shape of a close commit that numbers a draft. A cleanup that promises to
  touch only the checkout can write outside it. And one shell idiom reads
  as error handling while it is the opposite.

## Scope
- In scope: the six items above, their tests, CHANGELOG entries, the
  amendment records for the closed specs whose tests change, and closing
  each item with `follow-ups.mjs close` and evidence.
- Out of scope:
  - the P3 leftovers (second ride);
  - `fu-parity-win-odd-root-cause` (owner decision, P3);
  - deleting or editing the owner's PowerShell cache file;
  - any change to how suites are selected (only their weights and the
    timeout change).

## Affected Area
- `tests/skills/suite-weights.tsv` and the eight suites that pin 196;
  `.github/workflows/skill-suite.yml` (L3 surface: a workflow file).
- `.aai/scripts/release-dry-run.mjs`, `.aai/scripts/release-finish.mjs`,
  `tests/skills/lib/aai-release.test.mjs`, `tests/skills/lib/release-first.test.mjs`.
- `.aai/templates/git-hooks/pre-commit-index.sh` (L3 surface: a hook body
  template).
- `.aai/scripts/merge-cleanup.mjs`.
- A lint over the shipped shell corpus for the set -e idiom.

## Desired Behavior (To-Be)
- Every suite weight is a median of successful hosted runs with named
  sources. Only suites with no successful hosted observation keep the
  documented fallback. No test pins a placeholder number.
- The selected-sharded job is bounded at 15 minutes again, with a modelled
  shard wall that leaves headroom. The hosted run on the pull request head
  shows it.
- A PowerShell that crashes or prints no version is never recorded as a
  version.
- The release preflight runs each test in a throwaway clone with no remote,
  a scrubbed environment and its own home and cache. A test that spawns
  pwsh uses its own cache directory. The cut no longer reports
  `FAILS ON BASE TOO` for the corrupted-cache cause.
- A staged doc renamed in the commit is close-gated and body-linted under
  its new path.
- `sync-base` and the resume of an interrupted sync refuse a write target
  whose resolved parent lies outside the checkout.
- A test fails when a shipped shell script that runs under `set -e` calls
  one of its own functions in a condition context.

## Acceptance Criteria
- AC-001: `auditWeights` passes over the re-measured
  `tests/skills/suite-weights.tsv`. Every suite with at least one successful
  hosted PASS observation in the named source runs carries a measured row.
- AC-002: none of the eight pinning tests asserts the literal 196, and each
  still requires exactly one positive weight row for its suite.
- AC-003: the selected-sharded job has `timeout-minutes: 15`. For PR #582's
  45-suite selection, the planner's modelled two-shard wall (`w2`) with the
  new weights is at most 600 s.
- AC-004: when pwsh exits non-zero, the release dry-run report records the
  PowerShell identity as unavailable, never as the crash text.
- AC-005: with an `XDG_CACHE_HOME` whose `powershell` entry is a regular
  file (pwsh then crashes at startup), the TEST-4027 cases of
  `aai-release.test.mjs` still pass.
- AC-006: the release preflight runs a test in a clone with no `origin`
  remote, not a linked worktree. The test does not see the operator's
  `GH_TOKEN`, `GITHUB_TOKEN`, `GIT_*` or `HOME`.
- AC-007: a renamed governed doc that adds `status: done` and fails the
  close gate is refused under `close_gate: enforce`.
- AC-008: `sync-base` with `docs/ai` symlinked outside the checkout
  refuses before any write outside the checkout, and so does
  `resumeSync`.
- AC-009: a lint over the shipped errexit shell scripts finds no local
  function in a condition context, and it refuses a fixture that has one.

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <suite>`
    for each touched suite (Planning names them); exit 0.
  - `node tests/skills/lib/selected-scheduling-benchmark-check.mjs --weights`
    (or the TEST-3338 audit) passes.
  - The hosted skill-suite run on the pull request head: the selected
    sharded legs finish inside 15 minutes.

## Constraints / Risks
- L3 surfaces (`.github/workflows/skill-suite.yml`,
  `.aai/templates/git-hooks/pre-commit-index.sh`), so ceremony level 3:
  the owner merges.
- Tests never use the owner's PowerShell cache, never reach a real Docker
  daemon, and never install hooks or sync into real repositories. Scratch
  targets only.
- The hosted timings vary by about ±30 % between runs. The weights are
  medians, and the 15-minute bound is judged on the hosted run of the
  pull request head, not on the model alone.
- A fallback weight must equal the maximum measured weight (SPEC-0239
  Spec-AC-01). Suites that only ever SKIP on the hosted runner therefore
  take that maximum.
- No secret is referenced.

## Notes
- Worktree: the owner set `/Users/ales/Projects/aai-worktrees/node-first-cleanup`
  from origin/main (owner brief 2026-11-24). The worktree gate is a human
  decision already taken.
- Implementation mode: Planning decides. The owner's brief asks for TDD.
- Measurement method for the weights: hosted skill-suite runs on main
  (push event, conclusion success, full framework legs). Per-suite `PASS
  (<n>s)` lines; SKIP and FAIL are never measured; median, rounded, floor 1.
