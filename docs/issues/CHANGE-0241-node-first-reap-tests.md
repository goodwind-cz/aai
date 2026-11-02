---
id: node-first-reap-tests
type: change
number: 241
status: done
capability: node-first-core
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move the test-process reaper (aai-reap-tests) to Node

## Summary
- RFC-0017 phase 5, second slice: the first of the three process adapters
  moves to Node. `aai-reap-tests` (368 lines of sh, 419 of PowerShell) kills
  leaked test process trees that escaped the test wrapper, scoped to the
  workspace and to processes older than the step start.
- Its logic moves to one Node module, `.aai/scripts/aai-reap-tests.mjs`, and
  the `.sh` and `.ps1` become thin launchers, following the pattern of the
  earlier Node-first slices (CHANGE-0222, CHANGE-0223, CHANGE-0224,
  CHANGE-0239).
- RFC-0017 says process supervision migrates last and only with native
  evidence; this is the smallest of the three adapters, so it goes first.

## Motivation / Business Value
- Two copies of safety-critical kill logic drift apart; the reaper's safety
  invariant (never global, workspace-scoped, age-guarded) must hold
  identically on every platform, which one implementation makes checkable.
- It proves the process-adapter migration pattern on the smallest adapter
  before `aai-run-tests` (958 lines) and `autonomous-loop` (488).
- The owner asked for it on 2026-11-02 (menu answer "1 a 3").

## Scope
- In scope:
  - The reaper logic (process listing, command-line match on `vitest` and
    `esbuild` plus the workspace path, epoch and legacy age guards, grace,
    dry-run and reporting, exit codes) in `.aai/scripts/aai-reap-tests.mjs`
    with exported functions and a thin CLI.
  - Process listing per platform: `ps` on macOS and Linux, the Windows
    process table (CIM or `tasklist`/`wmic` fallback as the PowerShell copy
    does today) on native Windows; killing a whole tree on each.
  - The `.sh` and `.ps1` become launchers with the same arguments, environment
    variables (`AAI_REAP_WORKSPACE`, `AAI_REAP_STEP_START_EPOCH`,
    `AAI_REAP_GRACE_SECS`, `AAI_REAP_MIN_AGE_SECS` and the rest) and exit
    codes; callers (`aai-run-tests.sh`/`.ps1`, SKILL_LOOP, VALIDATION,
    SKILL_BOOTSTRAP) keep working unchanged.
  - Parity: the existing reaper tests (`tests/skills/test-aai-run-tests.sh`
    reaper cases, the Windows dispatch Pester file, win-fallback) pass against
    the new implementation on Linux, macOS and native Windows (Windows
    PowerShell 5.1 and pwsh 7); new `node:test` cases for the decision logic
    and for every measured drift between the two copies.
  - Downstream installs made by `aai-sync` keep working (PROFILES, launchers).
  - RFC-0017 remaining-pairs table and phase 5 row updated; the line count
    before and after is recorded.
- Out of scope:
  - `aai-run-tests` and `autonomous-loop` (later slices).
  - Changing which processes are reaped, the guards or their defaults, beyond
    recorded drift choices.
  - Behaviour when Node is absent: the launchers name the missing runtime and
    exit non-zero (a reaper that silently does nothing is the unsafe failure
    to avoid naming wrongly; Planning decides the exit code).

## Affected Area
- `.aai/scripts/aai-reap-tests.{sh,ps1}` and a new `.aai/scripts/aai-reap-tests.mjs`
- Callers: `.aai/scripts/aai-run-tests.{sh,ps1}`, `.aai/SKILL_LOOP.prompt.md`,
  `.aai/VALIDATION.prompt.md`, `.aai/SKILL_BOOTSTRAP.prompt.md` (wording only
  if needed)
- Tests: `tests/skills/test-aai-run-tests.sh`, `tests/skills/aai-win-dispatch.Tests.ps1`,
  `tests/skills/test-aai-win-fallback.sh`, new `tests/skills/lib/aai-reap-tests.test.mjs`
  and a Pester file
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `.github/workflows/ps1-quality.yml`, RFC-0017

## Desired Behavior (To-Be)
- The reaper has exactly one implementation, in Node.
- Running it through the old `.sh` or `.ps1` command reaps the same processes
  with the same output and exit codes on every platform, apart from recorded
  drift choices.
- The safety invariant is stated once and tested once: never global,
  workspace-scoped, never kills this step's own in-flight work.

## Acceptance Criteria
- AC-001: The reaper's logic lives in one Node module; the `.sh` and `.ps1`
  contain no copy of it.
- AC-002: The pre-existing reaper tests pass (or carry a recorded, justified
  adjustment) on Linux, macOS and the native Windows CI job under Windows
  PowerShell 5.1 and pwsh 7.
- AC-003: New `node:test` cases cover the decision logic (workspace scope,
  epoch mode, legacy mode, invalid and future epochs, grace) and every case
  where the two copies behaved differently.
- AC-004: A matching process in a sibling workspace, and a matching process
  younger than the step start, are never killed on any platform (tested with
  real child processes, not only mocks).
- AC-005: A downstream install made by `aai-sync` still runs the reaper from
  its launchers.
- AC-006: The net line count of the pair plus the module is lower than before,
  and the measurement is recorded; RFC-0017 records the slice.

## Verification
- Reaper suites and the new `node:test` file pass (rc 0).
- The native Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync` install runs the reaper from its launcher.

## Constraints / Risks
- This is process supervision: a bug kills the wrong processes. The tests that
  spawn real processes must clean up after themselves and must never use a
  global `pkill` (see the stress-test busy-loop memory: load loops must
  self-terminate).
- Reaper tests are known to flake under CI load (reaper-test CI-load flake);
  a flake is re-run, not chased as a bug, but a new flake introduced by the
  module is a finding.
- Windows parity is proven only by the hosted Windows PowerShell 5.1 job; a
  hosted failure is diagnosed with a probe before code changes.
- Changing a shipped script is consumer-visible; merge stays with the owner.
- No secrets referenced.

## Notes
- Source: RFC-0017 "Remaining paired scripts after phase 3" (phase 5 process
  adapter); owner menu answer 2026-11-02 "Mergni to a pak 1 a 3".
- Runs in parallel with the `reuse-for-docs-reading-suites` ride in its own
  worktree; full sweeps of the two rides are not run at the same time.
