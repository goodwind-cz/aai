---
id: spec-pester-on-windows-ci
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0134-pester-on-windows-ci.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the full Pester suite runs on real Windows CI under both engines

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0134-pester-on-windows-ci.md
- Prior spec (the dispatcher pair this scope keeps honest): docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md
- Prior spec (the four blind CI iterations that motivated this scope): docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md
- Follow-up source: docs/ai/decisions.jsonl entry 2026-08-12T13:52:00Z (CHANGE-0133 review_nb_disposition)
- Product doc extended by this scope: docs/product/windows-test-wrapper.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — a CI job gains two steps, one vendored
PowerShell probe is replaced with the already-proven pattern from its twin, and
the change is otherwise test and documentation surface. No protected path is in
scope (see the L3 check below), the file list is seven files, and the whole
scope is verifiable by named commands plus one named CI job.

## Summary

CHANGE-0133 cost four blind ~10-minute Windows CI iterations for three defects
that were all unit-testable on a real Windows engine: the Windows PowerShell 5.1
`-PassThru`/`ExitCode`-null footgun, the distro-less `wsl.exe` probe, and the
UTF-16LE BOM leak. None of them could be caught locally, because the 111-test
Pester suite runs only under pwsh on macOS and Linux; the `windows-5_1` job does
parse checks plus two functional smokes and nothing else.

This scope closes that gap. The `windows-5_1` job runs the SAME Pester suite the
Linux gate runs, under Windows PowerShell 5.1 AND pwsh 7, so an engine-specific
runtime semantic fails as a named unit test in the same job that already proves
the scripts parse. Tests that are genuinely host-specific (POSIX path
separators, a case-sensitive environment block, a `file://` clone URL, a host
with no Git Bash) are skipped by an explicit, named, COUNTED mechanism rather
than allowed to fail or to pass vacuously.

Two smaller things ride along because they belong to the same surface: the
reaper `.aai/scripts/aai-reap-tests.ps1` still carries the pre-fix
`Test-WslUsable` existence probe that CHANGE-0133 replaced in
`aai-run-tests.ps1` (the reaper would route a sweep into a distro-less WSL and
sweep nothing), and the fast-iteration path for the next Windows debugging
session (`workflow_dispatch` on this one job) is nowhere written down.

## Baseline measured at planning time (do not re-derive)

Run on this host (macOS, pwsh 7, Pester 5) over both suites:

```
TOTAL=111 PASSED=111 FAILED=0 SKIPPED=0 DUR=7.34s
```

So the suite is 111 tests and 7.3 s under pwsh on POSIX — not the "~2 min"
the intake estimated. The Windows cost driver is not the assertions, it is
process creation: the suite spawns roughly a dozen child `pwsh`/`git` processes
(the child-process probes in `aai-win-dispatch.Tests.ps1` and the five
`Invoke-Update` arms in `aai-update.Tests.ps1`), and Windows process creation
plus Pester discovery under Windows PowerShell 5.1 is the slow part.

Budget recorded here so implementation does not have to guess:

- Expected wall clock per engine: 60 s to 240 s.
- Hard per-step ceiling: 600 s of measured Pester duration, asserted by the
  step itself (Spec-AC-01), plus `timeout-minutes: 15` on each step as the
  belt-and-braces runner cap.
- Expected total added job time including the module install and cache:
  under 10 minutes. The job today is parse checks plus two smokes.

If the real run lands outside 60 s to 240 s, that is a recorded finding for
Validation to note — not a failure — provided it stays under the 600 s ceiling.

## Pester availability decision (recorded so implementation does not invent one)

Do NOT rely on the `windows-latest` image shipping Pester 5. The job installs
it the same way the Linux `gate` job already does, with three Windows-only
preconditions:

1. Windows PowerShell 5.1 and pwsh 7 have SEPARATE `CurrentUser` module scopes
   (`Documents\WindowsPowerShell\Modules` versus `Documents\PowerShell\Modules`),
   so the install-if-missing step runs once per engine, each under its own
   `shell:`.
2. Under 5.1 the install needs `[Net.ServicePointManager]::SecurityProtocol`
   forced to TLS 1.2 and the NuGet package provider bootstrapped
   non-interactively, or `Install-Module` fails or prompts.
3. Windows PowerShell 5.1 ships Pester 3.4.0 as a system module. Each Pester
   step must `Import-Module Pester -MinimumVersion 5.0` explicitly and FAIL if
   the imported major version is below 5 — a silent bind to Pester 3 would run
   a subset of the file and report success.

The module cache is keyed per runner OS so the install is a no-op on warm runs.

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml lists `state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. Verified against the live file: none of them is in
this scope. `.github/workflows/ps1-quality.yml` is a workflow FILE, not the
"workflow canon" document `.aai/workflow/WORKFLOW.md`, so it does not force L3.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): NOT touched. No
  diet-ledger entry and no TEST-012 checkpoint bump are owed.
- New `.aai/**` file: none created. The one new file this scope may add
  (`tests/skills/lib/pester-host-skip.ps1`) lives under `tests/`, not `.aai/`,
  so no `.aai/system/PROFILES.yaml` classification is owed.

## Implementation strategy
- Strategy: hybrid
- Rationale: Spec-AC-03 (the reaper probe) has a cheap deterministic RED
  available today — the current probe accepts any exit 0, so a test that feeds
  it a distro-less `wsl.exe` emulation and demands `$false` fails on the
  pre-change tree — and so does the structural `Handle`-touch pin, which
  targets a function that does not yet exist. Those take the TDD lane with a
  stored RED per AC-gating test. Spec-AC-01, Spec-AC-02 and Spec-AC-04 are a CI
  workflow edit, a test-harness mechanism and documentation: every pin fails on
  the pre-change tree by construction, so they take the loop lane with the RED
  observation recorded but not necessarily stored. No intake-sourced
  implementation-mode choice exists for CHANGE-0134 (the intake `## Notes`
  section carries no `Implementation mode (user choice):` line).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: seven files, no protected surface, and the scope already
  sits on its own branch `feat/pester-on-windows-ci`. Isolation only pays if
  another ride touches the same dispatcher pair or the same workflow at the
  same time. Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: feat/pester-on-windows-ci
- Worktree branch/path: <if selected>
- Inline review scope: .github/workflows/ps1-quality.yml .aai/scripts/aai-reap-tests.ps1 tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/aai-update.Tests.ps1 tests/skills/lib/pester-host-skip.ps1 tests/skills/test-aai-win-fallback.sh tests/skills/test-ps1-quality.sh tests/skills/suite-map.yaml docs/TECHNOLOGY.md docs/product/windows-test-wrapper.md docs/issues/CHANGE-0134-pester-on-windows-ci.md CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0134 AC-001 (full Pester suite on the Windows job, both engines)
  - Spec-AC-01: the `windows-5_1` job installs Pester 5 per engine and runs the
    whole `tests/skills` Pester discovery under `shell: powershell` and under
    `shell: pwsh`, failing the job on any test failure and on a runtime over
    the recorded ceiling.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 016` for the
    step contract; the named `ps1-quality / windows-5_1` job on this scope's PR
    for its execution. Observables are the grep pins in the first, and
    `AAI-PESTER-VERSION`, `AAI-PESTER-ELAPSED` and a zero failed count printed
    by each engine step in the second.
- Maps to: CHANGE-0134 AC-002 (host-specific tests skipped with a named reason, counted)
  - Spec-AC-02: every test that cannot pass on a Windows host is either made
    host-portable or carries an explicit Windows skip whose reason is printed,
    the skip count is asserted against a declared expected count in both
    directions, and the POSIX gate keeps skipping nothing.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 017` (source
    pin), `bash tests/skills/test-ps1-quality.sh` (POSIX skip count is zero),
    and the Windows job log. Observables are one `AAI-WIN-SKIP:` line per
    skipped test, the equality of that count with Pester's own `SkippedCount`
    and with the declared expected count, and `SkippedCount` zero on POSIX.
- Maps to: CHANGE-0134 AC-003 (the reaper's latent existence-probe bug)
  - Spec-AC-03: `.aai/scripts/aai-reap-tests.ps1` replaces its existence probe
    with the functional sentinel probe proven in `aai-run-tests.ps1`, including
    the redirected, handle-touched probe spawn, and Pester covers both the
    distro-less rejection and the sentinel acceptance.
  - Verification: `bash tests/skills/test-ps1-quality.sh` (Pester
    `aai-win-dispatch.Tests.ps1`). Observables are `Test-WslUsable` returning
    `$false` for a probe that exits 0 without the sentinel, `$true` only for
    the exact sentinel, and the source-level pin that both dispatchers use the
    same sentinel and the same probe argv.
- Maps to: CHANGE-0134 AC-004 (the fast-iteration path is written down)
  - Spec-AC-04: the product doc, the workflow header and docs/TECHNOLOGY.md all
    state that the Windows job can be run standalone via `workflow_dispatch`,
    and TECHNOLOGY.md stops claiming Pester runs on Linux only.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 018`. Observables
    are the grep pins for `workflow_dispatch`, the literal
    `gh workflow run ps1-quality.yml` invocation, and the absence of the stale
    "Pester on Linux" claim.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable. The two ACs whose real proof is a CI run declare that named job
  as their evidence, and stay `planned` until the run URL exists.
- Article 2 (Simplicity) — no new abstraction in the shipped scripts: the
  reaper gets the same two functions its twin already has, and the CI gets
  steps that mirror the Linux gate's existing install-and-run shape.
- Article 3 (Portability) — this scope IS that article applied to the test
  layer: the suite must now run under Windows PowerShell 5.1, so the skip
  predicate may not use `$IsWindows` alone (undefined under 5.1) and every
  new step must avoid pwsh-7-only syntax.
- Article 4 (Degrade and report) — a host-specific test degrades to a NAMED,
  COUNTED skip, never to a silent pass and never to a red job.
- Article 5 (Additive first) — the existing parse-check and smoke steps are
  untouched; the Pester steps are added beside them.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the ps1-quality workflow runs on windows-latest THEN its windows-5_1 job installs Pester 5 once per engine into that engine's own CurrentUser scope with TLS 1.2 and the NuGet provider bootstrapped for Windows PowerShell 5.1, and then runs Pester discovery over the tests/skills directory once under shell powershell and once under shell pwsh, each step importing Pester with MinimumVersion 5.0 and failing when the imported major version is below 5, printing AAI-PESTER-VERSION and AAI-PESTER-ELAPSED for its engine, failing the job when FailedCount is greater than zero, failing when the measured Pester duration exceeds 600 seconds, and carrying timeout-minutes 15 | planned | — | — | discovery is by directory so a future Tests.ps1 file is picked up without a workflow edit; the workflow push and pull_request paths filters widen to tests/skills/*.Tests.ps1 for the same reason |
| Spec-AC-02 | WHEN the suite runs on a Windows host THEN every test that cannot pass there is either made host-portable or marked skipped through one shared discovery-time predicate that is true under Windows PowerShell 5.1 and under pwsh 7 on Windows and false on macOS and Linux, each skipped test name carries the literal token PosixOnly followed by a non-empty reason, the step prints one AAI-WIN-SKIP line per skipped test, the step fails when that line count differs from Pester SkippedCount or from the expected skip count declared in one place, the step fails when FailedCount is greater than zero, AND WHEN the same suite runs on the Linux gate THEN SkippedCount is zero | planned | — | — | the predicate must be evaluated at Pester discovery time at file scope because a BeforeAll variable is invisible to a Skip expression; $IsWindows alone is undefined under 5.1 and would silently un-skip |
| Spec-AC-03 | WHEN Test-WslUsable in .aai/scripts/aai-reap-tests.ps1 probes a wsl.exe that is present but has no installed distribution and therefore exits 0 without running the sentinel THEN it returns false and the reaper falls through to Git Bash, WHEN the probe returns the exact sentinel exit code THEN it returns true, WHEN the probe does not complete within the watchdog THEN it returns false and the probe process is stopped, AND the probe spawn redirects both of its own standard streams to per-call temp files and touches the process Handle in the statement immediately after the Start-Process assignment, with both dispatchers using the same sentinel value and the same probe argv | planned | — | — | identical pre-fix defect to the one CHANGE-0133 fixed in aai-run-tests.ps1; the reaper currently has neither Start-WslProbeProcess nor Wait-ProcessWithTimeout and gains both, kept file-local per the deliberate no-shared-module convention in both headers |
| Spec-AC-04 | WHEN docs/product/windows-test-wrapper.md, the .github/workflows/ps1-quality.yml header comment and docs/TECHNOLOGY.md are read THEN all three state that the Windows job runs the full Pester suite under both engines and that it can be run standalone on demand, the product doc and the workflow header both name the literal command gh workflow run ps1-quality.yml, and docs/TECHNOLOGY.md no longer claims that Pester runs on Linux only | planned | — | — | the stale claim is the CI/CD bullet in the Tooling section; the Pester row of the version table stays correct and only its evidence pointer needs to keep matching |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.github/workflows/ps1-quality.yml` — the `windows-5_1` job gains, in order:
  a module cache step, an install-if-missing step under `shell: powershell`
  (TLS 1.2, NuGet provider, `Install-Module Pester -Scope CurrentUser -Force
  -SkipPublisherCheck`), an install-if-missing step under `shell: pwsh`, and
  two run steps. Each run step imports Pester with `-MinimumVersion 5.0`,
  builds a `New-PesterConfiguration` with `Run.Path = 'tests/skills'` and
  `Run.PassThru = $true`, prints `AAI-PESTER-VERSION: <engine> <version>` and
  `AAI-PESTER-ELAPSED: <engine> <seconds>`, prints one `AAI-WIN-SKIP:` line per
  entry in `$result.Skipped` using its `ExpandedPath`, and exits non-zero on a
  failed count, a version below 5, a duration over 600 s, or a skip-count
  mismatch. The job header comment and the workflow's top-of-file comment gain
  the `workflow_dispatch` fast-iteration note. The `push` and `pull_request`
  `paths:` lists replace the two literal `Tests.ps1` entries with
  `tests/skills/*.Tests.ps1` and add `tests/skills/lib/**`.
- `tests/skills/lib/pester-host-skip.ps1` — NEW, three lines of substance: a
  `Test-IsWindowsHostFor -Edition <string> -IsWindowsFlag <object>` helper that
  returns true when the edition is `Desktop` (Windows PowerShell 5.1, where
  `$IsWindows` does not exist) or the flag is really `$true`, and nothing else.
  Both `.Tests.ps1` files dot-source it at FILE scope — outside `BeforeAll` —
  and set `$SkipOnWindows = Test-IsWindowsHostFor -Edition
  $PSVersionTable.PSEdition -IsWindowsFlag $IsWindows` so a `-Skip:` expression
  can read it during discovery.
- `tests/skills/aai-win-dispatch.Tests.ps1` — the skip marks, the portability
  fixes and the new reaper coverage:
  - `TEST-004` first `It` (real invocation, expects exit 78) — SKIP on Windows.
    `windows-latest` HAS a real Git Bash, so the dispatcher resolves it and
    runs the command instead of erroring. Reason token: no-interpreter host.
  - `CHANGE-0133 TEST-001` (PATH collision union) — PORTABLE, not skipped. The
    fixture values are POSIX-separated strings while the assertion joins with
    `[IO.Path]::PathSeparator`; build the fixture values with the same
    separator and the test asserts identically on both platforms. This is the
    one case where the logic under test is genuinely engine-relevant, so
    skipping it would forfeit real Windows coverage.
  - `CHANGE-0133 TEST-003` (real dual-casing environment) — SKIP on Windows.
    The Win32 environment block is case-insensitive, so the CONTROL arm cannot
    be constructed in-process; this is the same limitation SPEC-0120 RR-1
    already records.
  - The `CR-1` H3 grandchild probe — SKIP on Windows for the same reason plus a
    second one: its fixture overwrites PATH with a nonexistent directory, which
    on Windows breaks the `Start-Process -FilePath 'pwsh'` resolution the
    assertion depends on.
  - NEW contexts for the reaper probe (Spec-AC-03), inside the existing
    `Describe 'aai-reap-tests.ps1'`.
- `tests/skills/aai-update.Tests.ps1` — `TEST-009` (the `file://` fixture clone
  with `-KeepTemp`) — SKIP on Windows: it redirects the temp base through
  `$env:TMPDIR`, which `[System.IO.Path]::GetTempPath()` ignores on Windows,
  and it builds a `file://C:\...` URL from a backslash path. Reason token
  names both. Making it portable is a larger change than this scope owns.
- `.aai/scripts/aai-reap-tests.ps1` — NEW `Start-WslProbeProcess` and NEW
  `Wait-ProcessWithTimeout` copied in shape from `aai-run-tests.ps1`, and
  `Test-WslUsable` rewritten to the sentinel probe. The header's probe comment
  block gains the same "REAL functional probe" rationale.
- `tests/skills/test-aai-win-fallback.sh` — NEW `test_016`, `test_017`,
  `test_018`, each added to `ALL_TESTS` (`check-test-registration.mjs` reports
  an orphan otherwise).
- `tests/skills/test-ps1-quality.sh` — the Pester invocation switches to
  `PassThru` and fails when `SkippedCount` is non-zero, which is the POSIX half
  of Spec-AC-02.
- `tests/skills/suite-map.yaml` — the `aai-win-fallback` entry gains
  `.github/workflows/ps1-quality.yml`, `tests/skills/aai-win-dispatch.Tests.ps1`,
  `tests/skills/aai-update.Tests.ps1` and `tests/skills/lib/**`, so a
  workflow-only or test-only edit still selects the suite that pins it.
- `docs/TECHNOLOGY.md`, `docs/product/windows-test-wrapper.md`, `CHANGELOG.md`
  (one `## [unreleased] — <title>` heading entry).

Data flows:

The shared state is the Pester RESULT OBJECT. Today it is consumed only as an
exit code. This scope makes three of its fields load-bearing across a process
boundary — `FailedCount`, `SkippedCount` and `Duration` are read in the
workflow step, while the values that produce them are decided in the test files
by a discovery-time predicate. That crossing is SEAM-1 below.

Edge cases:

- A Pester 3 bind under Windows PowerShell 5.1 runs a subset and reports
  success — caught by the explicit version assertion, not by the exit code.
- A skip predicate that is true everywhere turns the whole POSIX gate green and
  empty — caught by the POSIX `SkippedCount` zero assertion.
- A skip predicate that is false under Windows PowerShell 5.1 (the `$IsWindows`
  trap) makes the 5.1 step red while the pwsh step is green — visible, but the
  helper's `Desktop` arm is what prevents it.
- A `-Skip:` expression referencing a `BeforeAll` variable evaluates to `$null`
  at discovery and silently does not skip.
- A new `*.Tests.ps1` file added later must be picked up by both the discovery
  path and the workflow `paths:` filter, or the job is quietly not run.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-win-fallback.sh   | New test_016 registered in ALL_TESTS asserts the windows-5_1 job carries a Pester install step per engine and two Invoke-Pester steps, one under shell powershell and one under shell pwsh, each naming Import-Module Pester with MinimumVersion 5.0, printing AAI-PESTER-VERSION and AAI-PESTER-ELAPSED, discovering the tests/skills directory rather than two hardcoded files, carrying timeout-minutes 15 and asserting a 600 second ceiling. Command: bash tests/skills/test-aai-win-fallback.sh 016 | pending |
| TEST-002 | Spec-AC-01 | e2e         | .github/workflows/ps1-quality.yml       | On the real windows-latest runner both Pester steps complete with FailedCount zero and an imported Pester major version of 5 or higher under Windows PowerShell 5.1 and under pwsh 7, and both print their AAI-PESTER-ELAPSED value. Evidence is the named ps1-quality windows-5_1 job URL on this scope's PR plus the two elapsed values copied into the AC Status row. Command: gh run view --job for that job | pending |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Test-IsWindowsHostFor returns true for edition Desktop with a null flag, true for edition Core with flag true, false for edition Core with flag false, and false for edition Desktop is never asserted because 5.1 is always Windows - proving the predicate cannot silently un-skip on Windows PowerShell 5.1 nor over-skip on POSIX. Command: bash tests/skills/test-ps1-quality.sh | pending |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-win-fallback.sh   | New test_017 registered in ALL_TESTS asserts every Skip expression in both .Tests.ps1 files references the shared SkipOnWindows variable, every test carrying it has the literal token PosixOnly followed by a non-empty reason in its name, the shared helper is dot-sourced at file scope and not inside a BeforeAll block, and the expected-skip-count constant is declared exactly once. Command: bash tests/skills/test-aai-win-fallback.sh 017 | pending |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-ps1-quality.sh        | The POSIX Pester run reports SkippedCount zero and a TotalCount of at least 111, and the gate fails when SkippedCount is non-zero - the guard that a Windows skip predicate cannot leak into the Linux gate and turn it vacuously green. Mutation proof - temporarily forcing the predicate to true must make this gate FAIL. Command: bash tests/skills/test-ps1-quality.sh | pending |
| TEST-006 | Spec-AC-02 | e2e         | .github/workflows/ps1-quality.yml       | On the real windows-latest runner each Pester step prints one AAI-WIN-SKIP line per skipped test, the line count equals Pester SkippedCount and equals the declared expected count, every printed line contains the PosixOnly token, and FailedCount is zero. Evidence is the same named CI job URL. Command: gh run view --job for that job | pending |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Reaper Test-WslUsable with a mocked Start-WslProbeProcess that exits 0 without the sentinel returns false, with a probe that returns the exact sentinel returns true, and with a probe that never completes returns false and calls the stop primitive once - RED on the pre-change tree, where any exit 0 is accepted as usable. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Structural pin over .aai/scripts/aai-reap-tests.ps1 - Start-WslProbeProcess exists, redirects both standard streams to per-call temp file paths, and the statement immediately after the Start-Process assignment discards proc dot Handle, mirroring the pin that already guards aai-run-tests.ps1. RED on the pre-change tree, where the function does not exist. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Cross-file parity pin - both dispatchers declare the same sentinel exit value and the same probe argument list, and reaper Resolve-Interpreter falls through to gitbash when the probe is not sentinel-clean. RED on the pre-change tree, where the reaper probe argv is the bare true command. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-010 | Spec-AC-04 | unit        | tests/skills/test-aai-win-fallback.sh   | New test_018 registered in ALL_TESTS asserts docs/product/windows-test-wrapper.md and the ps1-quality.yml header both contain the literal gh workflow run ps1-quality.yml and the token workflow_dispatch, that all three of the product doc, the workflow header and docs/TECHNOLOGY.md state the two-engine Pester coverage, and that docs/TECHNOLOGY.md no longer carries the Pester on Linux only phrasing. Command: bash tests/skills/test-aai-win-fallback.sh 018 | pending |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — the Pester result object crosses from the test files into the
  workflow step. A skip decided at discovery inside a `.Tests.ps1` file is
  consumed as a NUMBER by a shell assertion in the job. Two unit tests either
  side would test nothing, so TEST-005 asserts the count on the producing side
  for POSIX and TEST-006 asserts the same count on the consuming side for
  Windows, with the expected value declared once and compared both ways.
- SEAM-2 — Windows PowerShell 5.1 versus pwsh 7 as two DIFFERENT consumers of
  the same test files. This is the seam the whole scope exists to close: the
  files have never been discovered or executed under 5.1. Crossed by TEST-002
  (both engines, same discovery) and guarded by TEST-003 (the predicate cannot
  behave differently between them by accident).
- SEAM-3 — the two dispatchers share a probe SHAPE but deliberately no module.
  Fixing one and not the other is exactly how this defect survived. Crossed by
  TEST-009, which asserts the sentinel and the argv agree across both files.
- SEAM-4 — the workflow `paths:` filter versus the set of files the job
  actually runs. A new `Tests.ps1` file that the filter does not match means
  the job silently does not run for the change that needed it. Crossed by the
  directory-based discovery plus the widened glob, pinned by TEST-001.
- SEAM-5 — `suite-map.yaml` selection versus the suite that pins the workflow.
  Today a workflow-only edit does not select `aai-win-fallback`, so TEST-001,
  TEST-004 and TEST-010 would not run on the change that breaks them. Closed by
  the suite-map widening; verified by `bash tests/skills/test-aai-suite-select.sh`
  and `bash tests/skills/test-aai-hygiene-pack.sh`.
- SEAM-6 — a Windows-skipped test is coverage LOST on Windows. Each skip is
  therefore an entry in the residual-risk list below, not merely a line in a
  log.

## Residual risks (accepted)

- RR-1 — the dual-casing environment defect that CHANGE-0133 fixed still cannot
  be reproduced on Windows CI (SPEC-0120 RR-1, unchanged). The two tests that
  prove it are the ones this scope skips on Windows. Mitigation: the mocked
  `OrdinalIgnoreCase` arm (TEST-001 of CHANGE-0133) IS made portable and DOES
  run on Windows, so the canonicalizer's own logic gains real Windows coverage
  even though the environment-block arm cannot.
- RR-2 — the real-invocation `AAI-ENV-ERROR` path (exit 78) has no Windows
  coverage at all, because every Windows runner has Git Bash. It stays covered
  by the mocked `TEST-003` arm and by the existing manual verification
  protocol.
- RR-3 — `aai-update.Tests.ps1` TEST-009 (the real clone) is skipped on
  Windows, so the updater's real clone path stays proven only on POSIX. The
  parse, guard, dry-run and flag-parity arms all still run under both Windows
  engines.
- RR-4 — the reaper's fixed probe is proven by mocks plus the parity pin, not
  by a real distro-less `wsl.exe` call. The `windows-latest` runner IS
  distro-less, so the Pester run does exercise the real `wsl.exe` binary
  through the unmocked arms of the reaper suite where they exist; the
  end-to-end sweep itself stays under the SPEC-0046 manual protocol.
- RR-5 — Windows runner minutes cost more than Linux minutes. The scope adds
  two steps of an expected 60 s to 240 s each to a job that already runs on
  every `.ps1` change. Accepted deliberately: the alternative measured price
  was four blind ten-minute iterations plus a human debugging session.

## Verification

Commands to run:

- `bash tests/skills/test-ps1-quality.sh` (parse gate, PSScriptAnalyzer 5.1 and
  7.0 compatibility, the full Pester suite, and the new POSIX
  `SkippedCount` zero assertion; pwsh 7 with Pester 5 is present on this host,
  so a SKIP here is a finding)
- `bash tests/skills/test-aai-win-fallback.sh`
- `bash tests/skills/test-aai-suite-select.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh` (test-function registration)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-pester-on-windows-ci.md`
- the `ps1-quality / windows-5_1` job on this scope's PR

Evidence artifacts: stored RED logs under `docs/ai/tdd/` for TEST-007, TEST-008
and TEST-009; the recorded RED observation for TEST-001, TEST-004, TEST-005 and
TEST-010; the mutation-proof output for TEST-005 (the forced-predicate arm
FAILING); full stdout with exit codes for every command above; and the
`windows-5_1` job URL plus the two `AAI-PESTER-ELAPSED` values as the sole
evidence for TEST-002 and TEST-006.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
status. Spec-AC-01 and Spec-AC-02 may only reach `done` once the named CI job
has actually run green on the PR; until then they stay `planned`, which blocks
PASS by design.

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
`docs/ai/tdd/` per AC-gating test on the TDD lane (TEST-007, TEST-008,
TEST-009), plus the full verification matrix above. For the loop-lane items the
RED observation is the pin failing on the pre-change tree — recorded the same
way, and for TEST-005 recorded as the mutation proof described in the Test
Plan.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
