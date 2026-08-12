---
id: spec-ps1-wrapper-path-dup
type: spec
number: 120
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0133-ps1-wrapper-path-dup.md
  rfc: null
  pr: []
  commits: []
---

# Spec — aai-run-tests.ps1: canonical env before every spawn, explicit infra exit code, no fake 124

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0133-ps1-wrapper-path-dup.md
- Prior spec (the dispatcher this scope repairs): docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md
- Prior spec (the POSIX twin's process-group contract): docs/specs/SPEC-0009 (leak-safe test execution, see docs/USER_GUIDE.md "Leak-safe test execution")
- Prior spec (the ps1 native-stderr discipline this scope reuses): docs/specs/SPEC-0067-spec-ps1-native-stderr-guard.md
- Product doc created by this scope: docs/product/windows-test-wrapper.md
- Technology contract: docs/TECHNOLOGY.md

## Summary

A downstream owner (Codex on Windows, 2026-08-12) reported three defects in the
Git-Bash branch of `.aai/scripts/aai-run-tests.ps1`, with a minimal repro:
`python --version` runs fine directly, and through the wrapper it dies with
`Item has already been added. Key in dictionary: 'Path'` and exits 124. The
validator downstream then spent ~20 minutes and weekly-limit tokens
orchestrating around a wrapper that had never run anything.

Three independent faults compose into that outcome:

1. The process environment can carry BOTH `Path` and `PATH`. PowerShell's
   `$env:` view is case-insensitive and hides this, but the .NET dictionary
   built for a child process is `OrdinalIgnoreCase`, so the second key throws.
   The wrapper hands the ambient environment to `Start-Process`
   (`aai-run-tests.ps1:239`) without ever canonicalizing it.
2. The failure is never caught. `Start-Process` produces no process,
   `Wait-ProcessWithTimeout` runs against `$null`, `WaitForExit` on `$null`
   answers falsy, and `Invoke-ViaGitBash` returns **124** — the code the whole
   factory reads as "a test run TIMED OUT". A run that never started is
   reported as a hung run.
3. Cleanup does not cover the spawn-failed branch: `Stop-ProcessTree` is only
   reached on the timeout path, and there is no `finally`, so a partially
   created process object is never reaped and no diagnostic names the branch
   (WSL versus Git Bash) that failed.

This scope closes all three with one canonicalization seam, one new exit code,
and one cleanup contract, plus a real-Windows CI smoke that runs the wrapper
end to end for the first time.

## Exit-code decision (recorded here so implementation does not invent one)

The wrapper already borrows two conventions: `78` from sysexits (`EX_CONFIG`,
no usable interpreter) and `124` from GNU `timeout` (a process that RAN and was
killed at the deadline). The new code is **125**, taken from the same GNU
`timeout` family where 125 means "the timeout machinery itself failed" — an
exact semantic match for "the wrapper could not start the command", and it sits
next to the 124 it must be distinguishable from. `2` (usage) is taken; `126`
and `127` are reserved by POSIX shells for cannot-execute and not-found and are
produced verbatim by the `.sh` twin, so neither may be reused. A repo-wide
grep for a consumer branching on 125 returns nothing, so nothing downstream
changes meaning. The residual ambiguity — a wrapped command that legitimately
exits 125 — is identical in kind to the one 124 already carries and is
disambiguated by the mandatory `AAI-SPAWN-ERROR:` stderr line (RR-3).

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml lists `state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. `.aai/scripts/aai-run-tests.ps1` is NOT on that
list (verified against the live file), and no protected path is in this scope's
file list. The declared level is 2, the intake's own level.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): NOT touched. The
  exit-code contract lands in the two wrapper headers, docs/TECHNOLOGY.md and
  docs/USER_GUIDE.md — never in the prompt corpus — so no diet-ledger entry and
  no TEST-012 bump are owed.
- New `.aai/**` file: none created. No `.aai/system/PROFILES.yaml`
  classification is owed.

## Implementation strategy
- Strategy: hybrid
- Rationale: Spec-AC-01 to Spec-AC-04 are executable PowerShell on the exact
  failure path that shipped untested, and every one of them has a cheap,
  deterministic RED available today (the `OrdinalIgnoreCase` collision throws
  in this repo's pwsh right now, and a mocked spawn failure returns 124 on the
  pre-change tree) — that is the TDD lane, RED artifact stored per AC-gating
  test. Spec-AC-05 to Spec-AC-07 are a CI workflow step, a characterization
  guard on the POSIX twin, and documentation plus a product doc; those take the
  loop lane, with the RED observation still recorded (each pin fails on the
  pre-change tree by construction, and the Spec-AC-06 guard is mutation-proved
  because it is the one test that would otherwise pass unchanged). No
  intake-sourced implementation-mode choice exists for CHANGE-0133.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the file list is small, touches no protected surface, and
  the ride already sits on its own branch `fix/ps1-wrapper-path-dup`. Isolation
  is only useful if another ride is in flight against the same wrapper pair.
  Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: fix/ps1-wrapper-path-dup
- Worktree branch/path: <if selected>
- Inline review scope: .aai/scripts/aai-run-tests.ps1 tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/test-aai-win-fallback.sh tests/skills/test-aai-run-tests.sh .github/workflows/ps1-quality.yml .aai/scripts/aai-run-tests.sh docs/TECHNOLOGY.md docs/USER_GUIDE.md docs/product/windows-test-wrapper.md docs/issues/CHANGE-0133-ps1-wrapper-path-dup.md CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0133 AC-001 (case-insensitive environment normalization)
  - Spec-AC-01: a pure canonicalizer collapses duplicate-casing environment
    keys deterministically, leaving exactly one `Path`.
  - Verification: `bash tests/skills/test-ps1-quality.sh` (Pester
    aai-win-dispatch.Tests.ps1); observables are the returned key set and a
    `Dictionary[string,string]` built with `StringComparer::OrdinalIgnoreCase`
    accepting every returned key without throwing.
- Maps to: CHANGE-0133 AC-001 (applies on both branches, before any spawn)
  - Spec-AC-02: the canonicalizer is applied to the real process environment
    once per dispatch, before the WSL probe and before either launch
    primitive.
  - Verification: `bash tests/skills/test-ps1-quality.sh`; observables are a
    recorded call order in the mocked dispatch and, in a child pwsh with both
    casings really present, a control-versus-treatment dictionary build.
- Maps to: CHANGE-0133 AC-002 (explicit infrastructure error, never a fake 124)
  - Spec-AC-03: a spawn failure exits 125 with one `AAI-SPAWN-ERROR:` stderr
    line naming the real exception, and the wait logic is never reached with
    `$null`; 124 keeps its "a process RAN and timed out" meaning.
  - Verification: `bash tests/skills/test-ps1-quality.sh`; observables are the
    returned code, the invocation count of `Wait-ProcessWithTimeout`, and the
    stderr text captured from a child pwsh.
- Maps to: CHANGE-0133 AC-003 (no orphans on failure paths, branch named)
  - Spec-AC-04: every failure path reaps a process object if one exists, never
    kills a `$null` pid, and names the branch it failed on.
  - Verification: `bash tests/skills/test-ps1-quality.sh`; observables are
    `Stop-ProcessTree` invocation counts with a parameter filter on the pid,
    and the branch token in the diagnostic line.
- Maps to: CHANGE-0133 AC-004 (proven on the repo's pwsh, plus real Windows)
  - Spec-AC-05: the ps1-quality Windows job runs the wrapper END TO END on a
    real Windows host under both PowerShell engines and asserts exit fidelity.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh` for the step's
    presence and assertions; the CI job result on the PR for its execution.
- Maps to: CHANGE-0133 AC-005 (POSIX parity check)
  - Spec-AC-06: the failure-masquerade class provably does not exist in
    `.aai/scripts/aai-run-tests.sh`, pinned by an executable guard.
  - Verification: `bash tests/skills/test-aai-run-tests.sh 024`; observables
    are the wrapper's real exit codes for a non-existent command, a
    non-executable file, and a genuinely hung command.
- Maps to: CHANGE-0133 AC-005 (docs updated truthfully) and the close-time
  product-doc gate (the intake carries `user_visible: true`)
  - Spec-AC-07: the three-code exit contract is documented consistently in both
    wrapper headers, docs/TECHNOLOGY.md and docs/USER_GUIDE.md, and the
    user-visible scope ships a real product doc.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh` and
    `bash tests/skills/test-aai-product-docs.sh`; observables are the grep pins
    and `missingProductSections()` returning an empty list.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC below names one command and one
  observable; the one AC that cannot be executed in this repo (Spec-AC-05's CI
  run) declares its evidence as the named CI job on the PR, not as a claim.
- Article 2 (Simplicity) — the canonicalizer is one pure function plus one
  applier; no configuration knob, no new file under `.aai/`.
- Article 3 (Portability) — the fix is plain PowerShell that must parse and run
  under Windows PowerShell 5.1 as well as pwsh 7 (pinned by the existing
  PSUseCompatibleSyntax gate and the real-5.1 CI job), so `Start-Process
  -Environment` (7.4+) is explicitly out of bounds.
- Article 4 (Degrade and report) — this scope IS that article applied: a silent
  infrastructure failure becomes an explicit, named, non-colliding error.
- Article 5 (Additive first) — 125 is a NEW code; 78, 124, 2, 126 and 127 keep
  their exact current meanings, so no public boundary is repurposed.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the canonicalizer is given an environment map containing more than one casing of the same name THEN it returns a map whose keys are unique under OrdinalIgnoreCase, the PATH group survives under the single literal key Path with the ordinal-key-ordered union of the group values joined by the platform path separator and duplicate directory entries dropped preserving first occurrence, every other collision group survives under its ordinal-first key with that key's value and no concatenation, a map with no collisions is returned unchanged, and normalizing twice is identical to normalizing once | done | TEST-001, TEST-002 green; docs/ai/tdd/green-20260812T121937Z-change-0133-ps1-wrapper.log | — | pure function, no process state touched; PATH-merge applies only to a genuine multi-casing collision (single-member PATH is left unchanged, so an already-clean host is a no-op) |
| Spec-AC-02 | WHEN Invoke-Dispatch runs THEN the process environment is canonicalized exactly once BEFORE the WSL probe and before either launch primitive on both the wsl and the gitbash branch, and afterwards the live process environment contains exactly one casing of PATH so that a Dictionary of string to string built with StringComparer OrdinalIgnoreCase over the whole environment does not throw | done | TEST-003, TEST-004 green; docs/ai/tdd/green-20260812T121937Z-change-0133-ps1-wrapper.log | — | applier reads Environment GetEnvironmentVariables and applies via Environment SetEnvironmentVariable, never the case-insensitive env drive for detection; a verified-necessary fallback (exact literal name only) covers a real .NET/Unix runtime quirk where SetEnvironmentVariable(name,$null) can leave an empty key instead of truly removing it |
| Spec-AC-03 | WHEN a launch primitive throws or returns no process object on either branch THEN the dispatcher exits 125, writes exactly one stderr line beginning AAI-SPAWN-ERROR that contains the originating exception message, never calls the wait logic, and never returns 124; AND when a process really RAN and exceeded the deadline the dispatcher still returns 124 with no AAI-SPAWN-ERROR line, and a normally completed process still returns its own real exit code | done | TEST-005, TEST-006, TEST-007 green; docs/ai/tdd/green-20260812T121937Z-change-0133-ps1-wrapper.log | — | 124 semantics are a regression pin, not a change |
| Spec-AC-04 | WHEN a failure occurs AFTER a process object exists THEN that object is tree-killed exactly once by its own pid and the dispatcher still exits 125; WHEN the spawn produced no object THEN Stop-ProcessTree is not invoked at all so no null or empty pid is ever passed to taskkill; AND every failure diagnostic names the branch it failed on using the literal token WSL or the literal token Git Bash | done | TEST-008, TEST-009 green; docs/ai/tdd/green-20260812T121937Z-change-0133-ps1-wrapper.log | — | closes intake defect 3 for the spawn-failed branch only, see RR-5 |
| Spec-AC-05 | WHEN the ps1-quality workflow runs on windows-latest THEN its windows-5_1 job carries a step that invokes .aai/scripts/aai-run-tests.ps1 for real under Windows PowerShell 5.1 AND under pwsh 7 across three arms - a success arm whose command prints a marker and exits 3, asserting exit 3, the marker on stdout, and no AAI-SPAWN-ERROR line; a timeout arm whose command hangs past AAI_TEST_TIMEOUT, asserting exit 124 and no AAI-SPAWN-ERROR line; and a spawnfail arm with the resolved Git Bash executable swapped for a non-executable decoy, asserting exit 125, an AAI-SPAWN-ERROR line, and no marker on stdout - and the step fails unless every arm's assertions hold under both engines | planned | TEST-010 green (step presence); TEST-011 pending real CI run on this scope's PR | — | first real-Windows execution of this dispatcher; step is added to .github/workflows/ps1-quality.yml windows-5_1 job; stays planned by design until the named CI job runs green on the PR |
| Spec-AC-06 | WHEN .aai/scripts/aai-run-tests.sh is given a command that cannot be launched THEN it exits with the shell's own real code 127 for a missing command and 126 for a non-executable file and never 124, AND a genuinely hung command under AAI_TEST_TIMEOUT 1 still exits 124, proving the failure-masquerade class does not exist in the POSIX twin; the guard is mutation-proved by observing it FAIL against a stub wrapper that returns 124 unconditionally | done | TEST-012 green; `bash tests/skills/test-aai-run-tests.sh 024` exit 0 | — | characterization guard surfaced one narrow, root-caused defect on a setsid-less host (perl launch fallback collapsed the non-executable case to 127 instead of 126); fixed at cause with a one-line change to that same fallback's exec-failure handling — no other .sh behavior changed |
| Spec-AC-07 | WHEN the exit-code contract is read from .aai/scripts/aai-run-tests.ps1, .aai/scripts/aai-run-tests.sh, docs/TECHNOLOGY.md and docs/USER_GUIDE.md THEN all four state 124 as the timeout of a process that RAN, 125 as a spawn or infrastructure failure that never ran anything, and 78 as no usable interpreter, the pre-existing five-row platform matrix pins still pass in all three matrix documents, AND docs/product/windows-test-wrapper.md exists with What it does, Data model and Interfaces and contracts all non-placeholder while the intake doc declares capability windows-test-wrapper | done | TEST-013, TEST-014 green; `bash tests/skills/test-aai-win-fallback.sh 015` and `bash tests/skills/test-aai-product-docs.sh test_015_windows_test_wrapper_product_doc` exit 0 | — | product-doc gate is report-only in this repo but is satisfied honestly rather than warned past |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components/modules affected:

- `.aai/scripts/aai-run-tests.ps1` — the whole scope of behavior change:
  - NEW `Get-CanonicalEnvironmentMap -Environment <IDictionary>` — pure,
    side-effect free, returns an ordered map. Grouping is
    `OrdinalIgnoreCase`; within a group the members are ordered by
    `[StringComparer]::Ordinal`. For the PATH group the surviving key is the
    literal `Path` and the value is the ordinal-ordered union of the group's
    values split on `[IO.Path]::PathSeparator`, empty segments dropped,
    duplicates dropped preserving first occurrence. For any other group the
    ordinal-first member's key AND value survive unchanged; concatenating
    unrelated values would corrupt them.
  - NEW `Set-CanonicalProcessEnvironment` — applies that map to the CURRENT
    process via `[Environment]::SetEnvironmentVariable(<name>, $null)` for each
    discarded casing and one set for each survivor, and RETURNS the list of
    collapsed names so the caller can report them. It must read
    `[Environment]::GetEnvironmentVariables()`, never the `$env:` drive, which
    is exactly the case-insensitive view that hides the defect.
  - `Invoke-Dispatch` calls `Set-CanonicalProcessEnvironment` once, before
    `Resolve-Interpreter` — the WSL probe itself calls `Start-Process`, so
    normalizing only before the launch would leave the probe on the broken
    path.
  - NEW `Write-SpawnError -Branch <string> -Message <string>` — one
    `[Console]::Error.WriteLine` line beginning `AAI-SPAWN-ERROR:` carrying the
    branch token and the exception message, mirroring the single-line
    discipline of `Write-EnvError`.
  - `Start-GitBashProcess` stays the thin, mockable primitive and gains
    `-ErrorAction Stop` so a non-terminating Start-Process error becomes
    catchable.
  - `Invoke-ViaGitBash` wraps spawn plus wait in `try`/`catch`/`finally`:
    a throw or a `$null`/pid-less return writes the spawn error and returns
    125 WITHOUT calling `Wait-ProcessWithTimeout`; a throw after a live object
    exists reaps that object in `finally` (guarded on a non-null pid) and
    returns 125; the timeout path is byte-equivalent to today (tree-kill, 124).
  - `Invoke-ViaWsl` gets the same guard: an exception from `Invoke-WslProcess`
    is a spawn failure (125, branch token `WSL`); a non-zero `$LASTEXITCODE`
    from a delegation that RAN is passed through unchanged.
  - Header block: the resolution-order comment, the exit-code list and the
    platform matrix gain the 125 row.
- `.aai/scripts/aai-run-tests.sh` — header-only exit-code paragraph plus one
  sanctioned, root-caused one-line deviation confined to the setsid-less perl
  fallback's exec-failure handling (collapsed a non-executable file to 127
  instead of the real 126; disclosed in the AC-Status Notes, a code comment
  and CHANGELOG per Spec-AC-06's own mutation-proved characterization guard):
  the exit-code paragraph states 124-versus-125 explicitly and records that
  this file can only ever produce the shell's real 126/127 for an unlaunchable
  command (the property Spec-AC-06 pins).
- `tests/skills/aai-win-dispatch.Tests.ps1` — new contexts for TEST-001 to
  TEST-009 inside the existing `Describe 'aai-run-tests.ps1'`. Two of them
  spawn a CHILD pwsh (the established pattern in this file) because
  `[Console]::Error` output cannot be captured in-process by Pester, and
  because the real-process-environment arm must not corrupt the parent test
  run's own environment.
- `tests/skills/test-aai-win-fallback.sh` — new `test_014` (Spec-AC-05 step
  presence) and `test_015` (Spec-AC-07 doc pins); BOTH must be added to
  `ALL_TESTS` or `check-test-registration.mjs` reports an orphan test function.
- `tests/skills/test-aai-run-tests.sh` — new `test_024` (Spec-AC-06), added to
  `ALL_TESTS`. The suite already exports `AAI_FRICTION_CAPTURE=0` and already
  supports `AAI_RUN_TESTS_SCRIPT` for stub-based RED-proofing, which is exactly
  the seam the mutation proof needs.
- `.github/workflows/ps1-quality.yml` — new step in the `windows-5_1` job. The
  existing `paths:` triggers already include `.aai/scripts/**.ps1`,
  `tests/skills/aai-win-dispatch.Tests.ps1` and the workflow itself, so no
  trigger edit is needed.
- `docs/TECHNOLOGY.md`, `docs/USER_GUIDE.md` — exit-code contract rows and
  prose. USER_GUIDE edits stay OUTSIDE the generated rollup markers; the new
  product doc reaches the generated section by re-running
  `node .aai/scripts/generate-userguide-rollup.mjs`.
- `docs/product/windows-test-wrapper.md` — NEW product doc (capability
  `windows-test-wrapper`), plus `capability: windows-test-wrapper` added to the
  intake's frontmatter so the close-time gate resolves that path rather than
  `docs/product/ps1-wrapper-path-dup.md`.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry.

Data flows:

The ambient process environment is the shared state this whole defect lives in.
It is produced by whatever launched pwsh (Git Bash, MSYS, WSL interop, a CI
runner) and consumed by .NET when it builds the child's environment dictionary.
The wrapper sits in the middle and, today, passes it through untouched. After
this change the wrapper OWNS one canonicalization point and every spawn — the
WSL probe, the WSL delegation and the Git Bash launch — is downstream of it.

Edge cases:

- A collision group whose members hold IDENTICAL values must collapse to one
  entry, not a doubled PATH.
- An empty or absent PATH must not be synthesized into existence.
- `AAI_TEST_TIMEOUT` is written with `$env:` today; after canonicalization that
  is still safe because the applier has already collapsed the duplicates, and
  the value it writes cannot itself create one.
- On a normal, already-clean environment the applier must be a NO-OP: zero
  `SetEnvironmentVariable` calls, so the common path cannot regress.
- A process that spawns and dies instantly is a process that RAN — it keeps its
  real exit code and must never be reported as a spawn failure.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                      | Description | Status |
|----------|------------|-------------|-------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | Get-CanonicalEnvironmentMap over a map holding Path, PATH and path returns exactly one key spelled Path whose value is the ordinal-key-ordered union of all three with duplicate directory entries dropped, and feeding every returned key into a Dictionary of string to string built with StringComparer OrdinalIgnoreCase does not throw | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | Non-PATH collision group Temp and TEMP collapses to the ordinal-first key with that key's value and no concatenation, identical-value duplicates collapse to a single entry, a collision-free map is returned unchanged, and normalizing the output a second time yields an identical map | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/aai-win-dispatch.Tests.ps1   | Child pwsh really creates both Path and PATH via Environment SetEnvironmentVariable and reports two arms - the CONTROL arm builds an OrdinalIgnoreCase dictionary from the live environment and THROWS, the TREATMENT arm runs Set-CanonicalProcessEnvironment first and does NOT throw while exactly one casing of PATH remains and its value still contains both original directories | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | Invoke-Dispatch records call order in both modes - the canonicalizer is invoked exactly once and before Test-WslUsable, before Start-GitBashProcess on the gitbash branch and before Invoke-WslProcess on the wsl branch - and on an already-clean environment the applier performs zero SetEnvironmentVariable calls | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | Start-GitBashProcess that throws and Start-GitBashProcess that returns null both make Invoke-ViaGitBash return 125 with Wait-ProcessWithTimeout invoked zero times, and neither returns 124 | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/aai-win-dispatch.Tests.ps1   | Child pwsh dot-sources the dispatcher, redefines the launch primitive to throw a uniquely named exception, invokes the Git Bash path and exits with its code - stderr holds exactly one line starting AAI-SPAWN-ERROR that contains both the exception text and the literal token Git Bash, and the exit code is 125 | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | Regression pins that 124 keeps its meaning - a live process object plus a wait that returns false still yields 124 with the tree-kill invoked once and no AAI-SPAWN-ERROR written, and a completed process still propagates its own exit code 7 | green |
| TEST-008 | Spec-AC-04 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | A throw raised AFTER a live process object exists tree-kills exactly that pid once and returns 125, while a spawn that produced no object invokes Stop-ProcessTree zero times so no null pid can reach taskkill | green |
| TEST-009 | Spec-AC-04 | unit        | tests/skills/aai-win-dispatch.Tests.ps1   | WSL branch parity - Invoke-WslProcess that throws makes Invoke-ViaWsl return 125 with a diagnostic naming the literal token WSL, Invoke-Dispatch surfaces that 125 unchanged, and a delegation that RAN and returned non-zero is passed through as its own code | green |
| TEST-010 | Spec-AC-05 | unit        | tests/skills/test-aai-win-fallback.sh     | New test_014 registered in ALL_TESTS asserts the ps1-quality windows-5_1 job carries a real-wrapper smoke step naming aai-run-tests.ps1, running it under both powershell and pwsh, and asserting exit code 3 plus the stdout marker plus the absence of AAI-SPAWN-ERROR | green |
| TEST-011 | Spec-AC-05 | e2e         | .github/workflows/ps1-quality.yml         | On the real windows-latest runner the wrapper is invoked under both Windows PowerShell 5.1 and pwsh 7 across three arms - success (command prints a marker and exits 3: asserts exit 3, marker on stdout, no AAI-SPAWN-ERROR), timeout (command hangs past AAI_TEST_TIMEOUT: asserts exit 124, no AAI-SPAWN-ERROR), and spawnfail (the resolved Git Bash executable is swapped for a non-executable decoy: asserts exit 125, an AAI-SPAWN-ERROR line, and no marker); the step fails unless every arm's assertions hold under both engines. Evidence is the named CI job on this scope's PR | pending |
| TEST-012 | Spec-AC-06 | integration | tests/skills/test-aai-run-tests.sh        | New test_024 registered in ALL_TESTS drives the real POSIX wrapper - a non-existent command exits 127, a non-executable fixture file exits 126, and a hung command under AAI_TEST_TIMEOUT 1 exits 124 - and the same case list run against a stub wrapper injected through AAI_RUN_TESTS_SCRIPT that always returns 124 must FAIL, which is the mutation proof that the guard bites | green |
| TEST-013 | Spec-AC-07 | unit        | tests/skills/test-aai-win-fallback.sh     | New test_015 registered in ALL_TESTS asserts both wrapper headers plus docs/TECHNOLOGY.md plus docs/USER_GUIDE.md each state 124 as a timeout of a process that ran, 125 as a spawn or infrastructure failure, and 78 as no usable interpreter, while the pre-existing five-row platform-matrix assertions in test_009 still pass | green |
| TEST-014 | Spec-AC-07 | integration | tests/skills/test-aai-product-docs.sh     | missingProductSections over docs/product/windows-test-wrapper.md returns an empty list and evaluateProductDocGate for a fixture primary doc carrying user_visible true and capability windows-test-wrapper reports severity none | green |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — canonicalizer to the REAL process environment to a real spawn. Two
  mocked unit tests would only test the mock, so TEST-003 creates both casings
  in a real child process and runs a control arm that must throw beside a
  treatment arm that must not; TEST-011 crosses the same seam on a real Windows
  host with a real Git Bash spawn.
- SEAM-2 — the dispatcher's exit code to every consumer that reads 124 as
  "hung". Crossed by TEST-007 (124 unchanged for a real timeout) and TEST-013
  (all four documents agree on the three codes). A grep at planning time found
  no consumer branching on 125, so nothing silently changes meaning.
- SEAM-3 — the WSL probe as a spawn site. `Test-WslUsable` calls
  `Start-Process` before any launch decision, so normalizing at the launch site
  would leave the probe broken; TEST-004 asserts the ORDER, not merely the
  fact, of canonicalization.
- SEAM-4 — the ps1 header text to the three-document platform matrix already
  pinned by `test_009`. Editing the header is exactly where that pin can be
  broken; TEST-013 asserts the new rows while re-running the old assertions.
- SEAM-5 — Windows PowerShell 5.1 versus pwsh 7. The new code must PARSE and
  RUN under both; parse is already gated by PSUseCompatibleSyntax and the real
  5.1 parse job, and TEST-011 adds the runtime half by executing under both
  engines.
- SEAM-6 — new product doc to the close-time gate and to the USER_GUIDE rollup
  generator. Crossed by TEST-014 through the gate's own library plus an
  explicit rollup regeneration in the Verification list.

## Residual risks (accepted)

- RR-1 — the EXACT field failure cannot be synthesized on Windows CI. On
  Windows the process environment block is case-insensitive at the Win32 layer,
  so `SetEnvironmentVariable` cannot create both casings from inside the
  process; the duplicate arrives from a PARENT that built the block (Git
  Bash/MSYS, WSL interop). The dictionary-collision arm is therefore proved by
  faithful simulation — an explicit `OrdinalIgnoreCase` dictionary, which is
  precisely what .NET builds on Windows — plus a real dual-casing environment
  under pwsh on macOS/Linux, plus the real-Windows end-to-end smoke. The field
  evidence stays the downstream owner's repro of 2026-08-12. Mitigation: the
  canonicalizer is TOTAL (it collapses any casing group, not a PATH special
  case) and runs before every spawn, so a real dup block cannot bypass it.
- RR-2 — `Start-Process` on real Windows can fail in ways that neither throw
  nor return `$null` (a process that starts and dies immediately). That is a
  process that RAN and keeps its real exit code by contract, so it is out of
  the 125 class by design, not by oversight.
- RR-3 — a wrapped command that legitimately exits 125 is indistinguishable
  from an infrastructure failure by exit code alone. Identical in kind to the
  ambiguity 124 already carries; the mandatory `AAI-SPAWN-ERROR:` stderr line
  is the disambiguator and is asserted by TEST-006.
- RR-4 — `taskkill /T` tree-kill completeness on a real Windows host is
  unchanged and remains unverified by this repo's CI (inherited SPEC-0046
  residual, MV-1 to MV-3).
- RR-5 — the intake's third defect (a hanging wrapper/subagent process observed
  once) is not proven to be caused by the dup. This scope closes the
  spawn-failed cleanup branch and names the failing branch in diagnostics; it
  cannot prove that particular observed hang is gone. If it recurs, the branch
  token in the new diagnostic is the evidence the next report will carry.

## Verification

Commands to run:

- `bash tests/skills/test-ps1-quality.sh` (parse gate, PSScriptAnalyzer 5.1 and
  7.0 compatibility, Pester TEST-001 to TEST-009; pwsh 7.6.3 with Pester 5 and
  PSScriptAnalyzer are present on this host, so a SKIP here is a finding)
- `bash tests/skills/test-aai-win-fallback.sh`
- `bash tests/skills/test-aai-run-tests.sh`
- `bash tests/skills/test-aai-product-docs.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh` (test-function registration)
- `node .aai/scripts/generate-userguide-rollup.mjs` then confirm the USER_GUIDE
  diff is contained to the marker block plus the hand-edited exit-code prose
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md`

Evidence artifacts: the stored RED logs under `docs/ai/tdd/` for TEST-001 to
TEST-009 and the recorded RED observation for TEST-010, TEST-012, TEST-013 and
TEST-014; the mutation-proof output for TEST-012 (the stub arm FAILING); full
stdout with exit codes for every command above; and the ps1-quality
`windows-5_1` job URL from this scope's PR as the sole evidence for TEST-011.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
status. Spec-AC-05 may only reach `done` once the named CI job has actually run
green on the PR; until then it stays `planned`, which blocks PASS by design.

## Evidence contract

For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `hybrid`, so the full contract applies: a stored RED artifact under
`docs/ai/tdd/` per AC-gating test on the TDD lane (TEST-001 to TEST-009), plus
the full verification matrix above. For the loop-lane items the RED observation
is the pin failing on the pre-change tree — recorded the same way, and for
TEST-012 recorded as the mutation proof described in the Test Plan.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
