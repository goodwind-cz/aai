---
id: spec-doctor-win-selftest
type: spec
number: 122
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0135-doctor-win-selftest.md
  rfc: null
  pr: []
  commits: []
---

# Spec — aai-doctor diagnoses the real Windows/agent-CLI environment it is run on

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0135-doctor-win-selftest.md
- Doctor engine this scope EXTENDS (never forks): `.aai/scripts/aai-doctor.mjs` (SPEC-0100 / CHANGE-0079)
- Wrapper whose own probe functions this scope REUSES: `.aai/scripts/aai-run-tests.ps1` (SPEC-0046, SPEC-0120)
- Three-arm smoke technique mirrored locally: `.github/workflows/ps1-quality.yml` and `tests/skills/lib/pester-native-capture.ps1`
- Windows Pester lane this scope's ps1 tests ride: docs/specs/SPEC-0121-spec-pester-on-windows-ci.md
- Capability-field contract reported read-only: `.aai/SUBAGENT_PROTOCOL.md` "Capability detection" (SPEC-0119)
- Product doc created by this scope: docs/product/aai-doctor.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — the scope adds three read-only diagnostic
sections to one existing deterministic engine plus one new vendored PowerShell
probe that dot-sources an existing dispatcher; nothing in the workflow, state,
allocator or guard surface is touched (see the L3 check below), no existing
category, exit code or output line changes, and every acceptance criterion
names a directly executable command. The intake declared level 1 and this
scope keeps it; the one judgement recorded against it is that the surface count
(ten files) sits at the top of what level 1 covers, so an operator may
legitimately raise it to 2 — Planning does not do that silently.

## Summary

CI proves GitHub's Windows image. The failures that cost real time surfaced on
DOWNSTREAM Windows machines — the sticky-escalation incident (CHANGE-0126) and
the `Path`/`PATH` duplicate-casing dictionary collision (CHANGE-0133) were both
found by the owner and reverse-engineered from logs, not diagnosed by a tool.

This scope makes the diagnosis a command. `aai-doctor` gains three sections:

- CAT-14 runs the REAL `.aai/scripts/aai-run-tests.ps1` three-arm smoke locally
  (success / timeout / induced spawn failure) using the same OS-handle capture
  and file-marker technique the CI step proved, and reports each arm with the
  wrapper's own `AAI-BRANCH` / `AAI-TIMEOUT` diagnostic line.
- CAT-15 reports the environment the wrapper actually sees — case-colliding
  variable groups, PowerShell engines and versions, Git Bash candidates, WSL
  tri-state — computed by calling the WRAPPER'S OWN probe functions, never a
  second implementation of them.
- CAT-16 reports which agent CLIs are installed, with versions, and reports the
  four `SUBAGENT_PROTOCOL` capability fields honestly as UNKNOWN, because they
  are resolved at runtime INSIDE an agent session and are not observable from a
  child process. Nothing is fabricated and nothing is inferred from a harness
  name.

The output stays a paste-able report: one `CAT-NN <STATUS> <reason>` line per
section in text mode, a structured `detail` object per section under `--json`,
zero network, zero LLM, and exit 0 on findings unless `--strict` is passed.

## Design decisions recorded at planning time (do not re-derive)

### D1 — how CAT-14/CAT-15 reach the wrapper's probes: a new dot-sourcing probe script

Intake AC-002 forbids a duplicate implementation. Three candidate mechanisms
were considered against `.aai/scripts/aai-run-tests.ps1`'s own file-local
header contract:

1. A shared PowerShell module holding the probes. REJECTED — both dispatcher
   headers state the deliberate no-shared-module convention, and SPEC-0121
   SEAM-3 records it as a knowingly accepted duplication of SHAPE (never of a
   module). Introducing one here rewrites a contract two prior specs depend on.
2. A `--probe` flag on `aai-run-tests.ps1` itself. REJECTED — the wrapper
   deliberately has no `param()` block (its header explains why), treats every
   `$args` token as the command to run, and publishes a closed exit map
   (0/N, 2, 78, 124, 125). A probe mode would need a new exit code and a new
   argument-shaped special case on the one path every test run in the factory
   already goes through.
3. A NEW `.aai/scripts/aai-win-selftest.ps1` that DOT-SOURCES the wrapper.
   CHOSEN — the wrapper's header explicitly blesses this: "Dot-sourcing this
   file (`. $path`) defines the functions WITHOUT running Main". The probe
   script therefore CALLS `Test-WslPresent`, `Test-WslUsable`,
   `Get-GitBashCandidates`, `Find-GitBash`, `Get-ProcessEnvironmentSnapshot`
   and `Get-CanonicalEnvironmentMap` and defines none of them. The production
   dispatcher is not edited at all by this scope.

`aai-doctor.mjs` (Node) spawns that script with the first available engine
(`pwsh`, else `powershell.exe`) and parses one JSON object off its stdout.

### D2 — the collision report is derived from the canonicalizer, not re-invented

`Get-CanonicalEnvironmentMap` is PURE and side-effect-free. The colliding
groups are computed as `keys(Get-ProcessEnvironmentSnapshot)` minus
`keys(Get-CanonicalEnvironmentMap(snapshot))`; each discarded name is attributed
to the surviving key it matches under `OrdinalIgnoreCase`. So the rule for WHICH
key survives and WHAT a collision is stays owned by the wrapper.
`Set-CanonicalProcessEnvironment` is NEVER called — the diagnosis is read-only
and must not mutate the caller's environment.

### D3 — arm 3 must induce a spawn failure without touching the host

The CI step induces the real spawn failure by MOVING the resolved `bash.exe`
aside and writing a decoy in its place. That is unacceptable on a user's
machine. The local arm instead spawns the wrapper in a CHILD process whose
environment is doctored: `ProgramFiles` (and `ProgramFiles(x86)`) point at a
temp root containing `Git\bin\bash.exe` as a non-executable text decoy, and
`PATH` is reduced so neither a real `bash.exe` nor `wsl.exe` resolves. The
wrapper's own resolution order then picks the decoy first, `Start-Process`
throws, and the contract under test (exit 125 plus exactly one
`AAI-SPAWN-ERROR` line naming the branch) is exercised for real. Nothing
outside the temp directory is created, moved or deleted.

### D4 — the capability fields are UNKNOWN, and that is the honest answer

`multi_agent_backend`, `spawn_agent_available`, `spawn_model_catalog` and
`fork_turns_supported` are runtime properties of the ORCHESTRATING SESSION.
A child process cannot observe them, and `.aai/SUBAGENT_PROTOCOL.md` explicitly
bans keying behavior on a harness-name equality test, so "codex is installed"
may not be converted into a capability claim. CAT-16 therefore reports all four
as UNKNOWN with the reason, and reports the one genuinely observable, clearly
separate fact next to them: whether the installed `codex` exposes an `exec`
subcommand (the SUBAGENT_PROTOCOL tier-3 hard-isolation recipe). That
observation is labelled as itself and is never presented as one of the four
fields.

### D5 — the new Pester tests go into the EXISTING aai-win-dispatch.Tests.ps1

`tests/skills/test-aai-win-fallback.sh` test_017 pins the declared
`AAI_EXPECTED_WIN_SKIP_COUNT` against the skips found in a HARDCODED two-file
list. A new `*.Tests.ps1` file would be discovered by the CI job (discovery is
by directory) but invisible to that pin — silent drift. Adding the new
contexts to `tests/skills/aai-win-dispatch.Tests.ps1` avoids introducing the
drift at all. Generalizing test_017 to a glob is the better long-term fix and is
recorded as a follow-up, not smuggled into this scope.

Consequence for the skip budget: the POSIX gate asserts `SkippedCount` is ZERO,
so no new test may skip on POSIX. The Windows-only assertions are therefore
written as ONE host-adaptive test (Windows arm asserts the arms PASS,
non-Windows arm asserts the section SKIPs) rather than a POSIX-skipped test. If
implementation nonetheless adds a `-Skip:$script:SkipOnWindows` test, it MUST
bump `AAI_EXPECTED_WIN_SKIP_COUNT` in `.github/workflows/ps1-quality.yml`
(currently 4) — test_017 enforces the equality.

### D6 — scope gate for CAT-14 and the exit contract

CAT-14 runs only when `process.platform === 'win32'` AND an engine is present.
Off Windows the wrapper resolves no POSIX interpreter and the smoke is
meaningless, so the section is a NAMED SKIP and no child process is spawned at
all (the doctor's fixture suites run it dozens of times on POSIX). This is a
deliberate narrowing of intake AC-001's "runs only where pwsh/powershell
exists": both preconditions produce a named SKIP, and the reason says which one
failed.

The pre-existing exit map (0 on clean or WARN-only, 1 on any FAIL, 2 on usage
error) is byte-unchanged: the three new categories cap at WARN and can never
emit FAIL, which is what makes intake AC-004's "exit 0 even on findings" true
without breaking the established contract. `--strict` is the opt-in: exit 1 when
any category is WARN or FAIL, exit 0 when every category is PASS or SKIP (a SKIP
is not a finding).

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml lists `state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. Verified against the live file: none of them is in
this scope.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): NOT touched. The doctor
  skill prompt `.aai/SKILL_DOCTOR.prompt.md` relays the script's output
  verbatim and needs no new bytes for three additional `CAT-NN` lines; if
  implementation nonetheless edits it, the prompt-diet ledger entry plus the
  TEST-012 checkpoint bump become owed (tests/skills/lib/prompt-diet-ledger.sh)
  and the scope must say so.
- New `.aai/**` file: YES — `.aai/scripts/aai-win-selftest.ps1`. A
  classification entry under `core:` in `.aai/system/PROFILES.yaml` is owed and
  is in scope (Spec-AC-05, TEST-013); core because the doctor that consumes it
  is core and a core-only sync must not lose it.

## Implementation strategy
- Strategy: hybrid
- Rationale: Spec-AC-02, Spec-AC-03 and Spec-AC-04 are Node and PowerShell
  behavior with cheap deterministic REDs available on this macOS host today —
  the categories do not exist, so every pin fails on the pre-change tree, and
  the fake-CLI and `--strict` fixtures are pure local runs. Those take the TDD
  lane with a stored RED per AC-gating test under `docs/ai/tdd/`. Spec-AC-01's
  real proof is a Windows execution and Spec-AC-05 is registration plus
  documentation: both take the loop lane, with the RED observation recorded
  (the adaptive Pester test fails on the pre-change tree on POSIX too, because
  CAT-14 does not exist yet). No intake-sourced implementation-mode choice
  exists for CHANGE-0135 — its `## Acceptance Criteria` section carries no
  `Implementation mode (user choice):` line.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: ten files, no protected surface, and the scope already
  sits on its own branch `feat/doctor-win-selftest`. Isolation pays only if
  another ride touches `aai-doctor.mjs` or the Windows Pester file
  concurrently. Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: feat/doctor-win-selftest
- Worktree branch/path: not selected
- Inline review scope: .aai/scripts/aai-doctor.mjs .aai/scripts/aai-win-selftest.ps1 .aai/system/PROFILES.yaml tests/skills/test-aai-doctor.sh tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/suite-map.yaml docs/product/aai-doctor.md docs/USER_GUIDE.md docs/issues/CHANGE-0135-doctor-win-selftest.md docs/specs/SPEC-0122-spec-doctor-win-selftest.md CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0135 AC-001 (Windows wrapper self-test)
  - Spec-AC-01: on a Windows host with an engine, CAT-14 runs the real wrapper
    three times and reports each arm PASS or FAIL with its captured diagnostic
    line; elsewhere it is a named SKIP that spawns nothing.
  - Verification: `node .aai/scripts/aai-doctor.mjs --json` (macOS: SKIP arm);
    `bash tests/skills/test-aai-doctor.sh`; the named
    `ps1-quality / windows-5_1` job on this scope's PR under both engines.
- Maps to: CHANGE-0135 AC-002 (environment diagnosis, no duplicate probe)
  - Spec-AC-02: CAT-15 reports collisions, engines, Git Bash candidates and WSL
    tri-state using the wrapper's own functions, obtained by dot-sourcing it.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (structural REUSE pin)
    and `bash tests/skills/test-ps1-quality.sh` (Pester unit arms).
- Maps to: CHANGE-0135 AC-003 (agent-CLI capability probe)
  - Spec-AC-03: CAT-16 names each CLI PRESENT with its verbatim version or
    ABSENT, and reports the four capability fields as UNKNOWN with a reason.
  - Verification: `bash tests/skills/test-aai-doctor.sh` with the fake-CLI and
    empty-PATH fixtures.
- Maps to: CHANGE-0135 AC-004 (honest output contract)
  - Spec-AC-04: one line per section plus a structured `detail` under `--json`,
    degraded sections named with reasons, no network, no LLM, exit 0 on
    findings unless `--strict`.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (shape, exit and
    zero-network pins).
- Maps to: CHANGE-0135 AC-005 (tests and documentation)
  - Spec-AC-05: the new tests are registered and selected, the new `.aai` file
    is classified, the Windows skip budget still balances, and the product doc
    plus USER_GUIDE tell the truth about what the self-test does and does not
    prove.
  - Verification: `node .aai/scripts/check-test-registration.mjs`,
    `bash tests/skills/test-aai-layer-profiles.sh`,
    `bash tests/skills/test-aai-suite-select.sh`,
    `bash tests/skills/test-aai-win-fallback.sh 017`,
    `bash tests/skills/test-aai-doctor.sh`.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable; the two rows whose real proof is a Windows run stay `planned`
  until the named CI job URL exists.
- Article 2 (Simplicity) — one new file, no abstraction over the existing
  category engine, and the rejected alternatives (shared module, wrapper flag)
  are recorded in D1 rather than built.
- Article 3 (Portability) — the new `.ps1` must parse and run under Windows
  PowerShell 5.1 and pwsh 7 (`$IsWindows` is undefined under 5.1; the
  `-PassThru`/`ExitCode`-null footgun applies to every spawn this file makes),
  and the Node side must behave identically on macOS, Linux and Windows.
- Article 4 (Degrade and report) — every unavailable input is a NAMED
  degradation: no engine, no interpreter, a self-test timeout, an absent CLI, an
  unobservable capability field. None of them is a silent pass and none is a
  fabricated value.
- Article 5 (Additive first) — CAT-01..CAT-13, the text line format, the JSON
  keys and the exit map are unchanged; the new sections and `--strict` are
  purely additive.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN aai-doctor runs on a Windows host where pwsh or powershell.exe resolves THEN CAT-14 invokes .aai/scripts/aai-win-selftest.ps1 which runs the real .aai/scripts/aai-run-tests.ps1 as a child process three times and reports one arm result each for success, timeout and spawnfail, where success asserts exit 3 plus a marker FILE whose content matches and no AAI-SPAWN-ERROR line, timeout asserts exit 124 under AAI_TEST_TIMEOUT of 2 with no AAI-SPAWN-ERROR line, and spawnfail asserts exit 125 with exactly one AAI-SPAWN-ERROR line and no marker file, every arm capturing stdout and stderr at OS-handle level into per-arm temp files, setting its own environment inside the spawned engine command text, touching the process Handle before reading ExitCode, and recording the wrapper AAI-BRANCH and AAI-TIMEOUT diagnostic line verbatim; AND WHEN the host is not Windows or no engine resolves THEN CAT-14 reports SKIP with a reason naming which precondition failed and the JSON detail records spawned false | planned | TEST-001/002/003/004 green locally (docs/ai/tdd/green-20260812T232500Z-doctor-win-selftest.log; Pester in tests/skills/aai-win-dispatch.Tests.ps1, 138/138 passed, SkippedCount 0) | — | arm 3 induces the failure through a doctored CHILD environment and a temp decoy only (D3) — the host Git installation is never moved, renamed or deleted; stays `planned` until the named `ps1-quality / windows-5_1` job has run this PR's three arms green on real Windows, per this doc's own PASS criteria |
| Spec-AC-02 | WHEN CAT-15 runs on a host where the probe script executes THEN it reports the case-colliding environment groups computed as the snapshot keys minus the Get-CanonicalEnvironmentMap survivor keys with each collapsed name attributed to its surviving key, the PowerShell engines present with their versions, the Git Bash candidate list from Get-GitBashCandidates together with the candidate Find-GitBash selects, and the WSL state as exactly one of absent or present-no-distro or functional derived from Test-WslPresent and Test-WslUsable; AND .aai/scripts/aai-win-selftest.ps1 dot-sources .aai/scripts/aai-run-tests.ps1 exactly once at file scope, carries the same direct-invocation guard shape, defines none of those probe functions itself, contains no second Git-Bash candidate list and no second collision rule, and never calls Set-CanonicalProcessEnvironment | done | TEST-005/006/007 green (docs/ai/tdd/red-20260812T231826Z-doctor-win-selftest.log -> green-20260812T232500Z-doctor-win-selftest.log); `bash tests/skills/test-aai-doctor.sh` and `bash tests/skills/test-ps1-quality.sh` both green | — | read-only by construction — the canonicalizer that MUTATES the process environment is deliberately not on this path |
| Spec-AC-03 | WHEN aai-doctor runs on any host THEN CAT-16 reports each of claude, codex and gemini as PRESENT with the version string emitted verbatim by invoking the resolved executable with --version, resolved through PATH honoring PATHEXT on Windows and spawned without a shell under a per-CLI timeout of at most 5 seconds, or as ABSENT when no executable resolves, never inventing a version for an absent CLI; AND the four SUBAGENT_PROTOCOL fields multi_agent_backend, spawn_agent_available, spawn_model_catalog and fork_turns_supported are each reported with the literal value UNKNOWN plus a reason stating they are resolved at runtime inside an agent session and are not observable from a child process, never as true or false; AND the separately labelled observation of whether the installed codex exposes an exec subcommand is reported outside those four fields | done | TEST-008/009 green (docs/ai/tdd/red-20260812T231826Z-doctor-win-selftest.log -> green-20260812T232500Z-doctor-win-selftest.log); real-repo run shows claude/codex/gemini all PRESENT with verbatim versions, codex_exec_subcommand.available=true | — | keying any capability on a harness name is banned by .aai/SUBAGENT_PROTOCOL.md and by SPEC-0119 Spec-AC-02 |
| Spec-AC-04 | WHEN aai-doctor runs in text mode THEN it prints exactly one CAT-14, one CAT-15 and one CAT-16 line in the established CAT-NN STATUS reason format with no detail lines, and the DOCTOR verdict line counts WARN and FAIL categories only — SKIP is diagnostic and excluded from the count — and WHEN it runs with --json THEN each of the three new categories carries a structured detail object alongside its status and reason, per-category detail objects appearing under --json only; AND none of the three new categories can emit FAIL so the pre-existing exit map of 0 on clean or WARN-only, 1 on any FAIL and 2 on a usage error is unchanged; AND WHEN --strict is passed THEN the process exits 1 if any category is WARN or FAIL and 0 when every category is PASS or SKIP; AND neither .aai/scripts/aai-doctor.mjs nor .aai/scripts/aai-win-selftest.ps1 contains any network or LLM primitive | done | TEST-010/011/012 green (docs/ai/tdd/red-20260812T231826Z-doctor-win-selftest.log -> green-20260812T232500Z-doctor-win-selftest.log); `bash tests/skills/test-aai-doctor.sh` full run green | — | a degraded section always names its reason, including self-test timed out, engine missing and probe script unreadable |
| Spec-AC-05 | WHEN the repository hygiene commands run THEN every new test function is registered and reported clean by check-test-registration.mjs, tests/skills/suite-map.yaml selects the doctor suite for the new script and the Pester file, .aai/system/PROFILES.yaml classifies .aai/scripts/aai-win-selftest.ps1 under core with test-aai-layer-profiles.sh green, the declared AAI_EXPECTED_WIN_SKIP_COUNT still equals the actual PosixOnly skip count and the POSIX Pester gate still reports SkippedCount zero; AND docs/product/aai-doctor.md exists with all three required product sections filled and states what the self-test proves and what it does not, docs/USER_GUIDE.md documents the three new sections plus --strict and the UNKNOWN capability reporting, and CHANGELOG.md carries one unreleased heading entry for this scope | done | TEST-013/014/015 green: `node .aai/scripts/check-test-registration.mjs` exit 0, `bash tests/skills/test-aai-layer-profiles.sh` / `test-aai-suite-select.sh` / `test-aai-win-fallback.sh 017` / `test-aai-hygiene-pack.sh` all PASS, `docs/product/aai-doctor.md` + USER_GUIDE + CHANGELOG present | — | product doc slug is the intake capability aai-doctor — the close gate resolves docs/product/aai-doctor.md from it |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/aai-win-selftest.ps1` — NEW. Dot-sources
  `.aai/scripts/aai-run-tests.ps1` (defining, never running, its functions),
  exposes small pure functions for the report shape and the collision
  derivation so Pester can call them without spawning anything, runs the three
  arms with `Start-Process -RedirectStandardOutput/-RedirectStandardError` plus
  `$null = $proc.Handle`, writes every fixture into one temp directory it
  creates and removes, and emits ONE JSON object on stdout. Direct invocation
  runs the whole probe; dot-sourcing defines the functions only, mirroring the
  wrapper's `$MyInvocation.InvocationName -ne '.'` guard.
- `.aai/scripts/aai-doctor.mjs` — three new category functions appended to
  `runDoctor()`, an optional `detail` field on the category object emitted
  under `--json` only (text mode prints no detail lines), a `--strict` flag in
  `parseArgs`, and the engine resolution plus JSON parse for the probe script
  (timeout-bounded; a timeout, a non-zero exit or unparseable stdout degrades to
  WARN with the reason, never a throw).
- `tests/skills/test-aai-doctor.sh` — new `test_023`..`test_0NN` covering the
  SKIP branch, the structural REUSE pins, the fake-CLI fixtures, the output
  shape, the `--strict` matrix and the zero-network pin; each registered in
  `main()`.
- `tests/skills/aai-win-dispatch.Tests.ps1` — new contexts for the probe
  script's pure functions and ONE host-adaptive end-to-end context that runs
  `node .aai/scripts/aai-doctor.mjs --json` and asserts the Windows branch on
  Windows and the SKIP branch elsewhere. No POSIX skip may be introduced.
- `tests/skills/suite-map.yaml` — the `aai-doctor` row gains
  `.aai/scripts/aai-win-selftest.ps1`, `tests/skills/aai-win-dispatch.Tests.ps1`
  and `tests/skills/test-aai-doctor.sh` so a probe-only edit still selects the
  suite that pins it.
- `.aai/system/PROFILES.yaml` — one `core:` entry for the new script.
- `docs/product/aai-doctor.md` — NEW, from `.aai/templates/PRODUCT_TEMPLATE.md`.
- `docs/USER_GUIDE.md` — the `/aai-doctor` section gains the three categories,
  `--strict`, and the honest statement about UNKNOWN capability fields.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry.

Data flows:

The doctor is Node and the probes are PowerShell, so ONE JSON document crosses a
process boundary: produced by `aai-win-selftest.ps1` on stdout, consumed by
`aai-doctor.mjs`. That crossing is SEAM-1. A second crossing is the wrapper's
stderr diagnostic line, produced by `Write-BranchDiag` inside a grandchild
process and consumed as a captured string two levels up (SEAM-2).

Edge cases:

- A Windows host with neither WSL nor Git Bash: arms 1 and 2 cannot pass. The
  self-test must assert the wrapper's OWN documented contract there instead
  (exit 78 with exactly one `AAI-ENV-ERROR` line) and report the section as
  WARN naming the missing interpreter — never FAIL and never a fabricated arm.
- A probe script that hangs: the doctor's spawn is timeout-bounded and degrades
  to WARN.
- Windows PowerShell 5.1 reading `$proc.ExitCode` as `$null` when `.Handle` was
  never touched — the footgun that produced a false PASS in CI.
- A UTF-16LE byte sequence leaking into a captured stream and flipping
  `Get-Content` encoding detection — why the success arm asserts a marker FILE,
  not a stdout regex.
- An agent CLI installed as a `.cmd` shim on Windows (PATHEXT), or one that
  writes its version to stderr rather than stdout.
- A doctor fixture run on POSIX must not pay for any of this: the SKIP branch
  spawns nothing.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-doctor.sh         | On this non-Windows host CAT-14 is SKIP with a reason naming the not-a-Windows-host precondition, the JSON detail records spawned false, and CAT-14 SKIP is excluded from the DOCTOR ISSUES count (SKIP is not an issue), the exit code unchanged. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | The probe script's pure report builder turns three synthetic arm results into the documented object with one entry per arm carrying status, exit code and the captured diag string, marks the overall self-test failed when any single arm failed, and preserves the diag text verbatim including its AAI-TIMEOUT field. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-doctor.sh         | Structural pin over .aai/scripts/aai-win-selftest.ps1 - every arm redirects both standard streams to per-arm temp file paths, the statement immediately after each Start-Process assignment discards proc dot Handle, each arm sets its environment inside the spawned engine command text rather than relying on inheritance, and the source contains no Move-Item, Rename-Item or Remove-Item applied to a resolved bash path so the host Git installation can never be mutated. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-004 | Spec-AC-01 | e2e         | tests/skills/aai-win-dispatch.Tests.ps1 | Host-adaptive end-to-end - running node .aai/scripts/aai-doctor.mjs --json on a Windows host yields CAT-14 with all three arms PASS and a non-empty captured AAI-BRANCH diag on the success arm, and on a non-Windows host yields CAT-14 SKIP; the test carries no Skip mark so the POSIX gate keeps reporting SkippedCount zero. Evidence on Windows is the named ps1-quality windows-5_1 job under both engines on this scope's PR. Command: bash tests/skills/test-ps1-quality.sh locally and gh run view for that job | green |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-doctor.sh         | Structural REUSE pin - .aai/scripts/aai-win-selftest.ps1 dot-sources .aai/scripts/aai-run-tests.ps1 exactly once at file scope, carries a direct-invocation guard of the same shape, references Test-WslPresent, Test-WslUsable, Get-GitBashCandidates, Find-GitBash, Get-ProcessEnvironmentSnapshot and Get-CanonicalEnvironmentMap, defines none of them, contains neither a Program Files Git bin literal nor a System32 bash shim pattern, and never names Set-CanonicalProcessEnvironment. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Given a synthetic dictionary carrying both Path and PATH plus one unrelated key, the collision reporter names exactly one group whose survivor is Path and whose collapsed member is PATH, and given a collision-free dictionary it names zero groups; the derivation calls the wrapper canonicalizer and never mutates the real environment. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-007 | Spec-AC-02 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | The WSL tri-state mapper returns absent when the presence probe is false, present-no-distro when presence is true and usability is false, and functional when both are true, driven by mocked wrapper probes so the arm is deterministic on every host. Command: bash tests/skills/test-ps1-quality.sh | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-doctor.sh         | With a temp directory prepended to PATH containing an executable named claude that prints a known version string, CAT-16 reports claude PRESENT with that exact string; with that directory removed and no agent CLI resolvable, all three CLIs are reported ABSENT and no version string appears anywhere in the CAT-16 detail. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/test-aai-doctor.sh         | The CAT-16 detail names all four fields multi_agent_backend, spawn_agent_available, spawn_model_catalog and fork_turns_supported, each with the literal value UNKNOWN and a reason mentioning runtime resolution inside an agent session, none of them ever carrying true or false, and the codex exec observation is reported under its own separate key. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-010 | Spec-AC-04 | unit        | tests/skills/test-aai-doctor.sh         | Text mode prints exactly one CAT-14, one CAT-15 and one CAT-16 line in the established format, --json carries a detail object for each of the three, the JSON stays parseable, and the categories array length grows from 13 to 16 while CAT-01 through CAT-13 keep their existing ids, statuses and reason wording on a clean fixture. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-011 | Spec-AC-04 | unit        | tests/skills/test-aai-doctor.sh         | Exit matrix - a fixture whose new sections are WARN exits 0 without --strict and 1 with --strict, a fixture whose only non-PASS categories are SKIP exits 0 with --strict, a fixture with a genuine CAT-01 FAIL still exits 1 without --strict, and an unknown flag still exits 2; no new category ever reports FAIL. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-012 | Spec-AC-04 | unit        | tests/skills/test-aai-doctor.sh         | Zero-network and zero-LLM pin - neither .aai/scripts/aai-doctor.mjs nor .aai/scripts/aai-win-selftest.ps1 references a network or model primitive, the checked token set naming fetch, node http, node https, Invoke-WebRequest, Invoke-RestMethod, curl, wget, git fetch, git ls-remote and git clone. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-013 | Spec-AC-05 | integration | tests/skills/test-aai-doctor.sh         | Hygiene set - check-test-registration reports no orphan for the doctor suite, the suite-map aai-doctor row names the new probe script and the Pester file, PROFILES.yaml lists .aai/scripts/aai-win-selftest.ps1 exactly once under core, and the layer-profiles and suite-select suites stay green. Commands: node .aai/scripts/check-test-registration.mjs and bash tests/skills/test-aai-layer-profiles.sh and bash tests/skills/test-aai-suite-select.sh | green |
| TEST-014 | Spec-AC-05 | unit        | tests/skills/test-aai-doctor.sh         | Documentation pin - docs/product/aai-doctor.md exists with all three required product sections non-placeholder and states both what the self-test proves and what it cannot prove, docs/USER_GUIDE.md names the three new categories and the --strict flag and the UNKNOWN capability reporting, and CHANGELOG.md carries one unreleased heading entry for this scope. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-015 | Spec-AC-05 | integration | tests/skills/test-aai-win-fallback.sh   | The Windows skip budget still balances after the new Pester contexts land - the declared AAI_EXPECTED_WIN_SKIP_COUNT equals the actual PosixOnly skip count across the pinned Pester files, and the POSIX Pester gate reports SkippedCount zero. Commands: bash tests/skills/test-aai-win-fallback.sh 017 and bash tests/skills/test-ps1-quality.sh | green |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — the JSON document produced by `aai-win-selftest.ps1` and consumed by
  `aai-doctor.mjs`. Two unit tests either side would test the mock, so TEST-002
  and TEST-006 assert on the PRODUCING side while TEST-004 runs the real Node
  consumer over the real PowerShell producer end to end.
- SEAM-2 — the wrapper's `AAI-BRANCH` / `AAI-TIMEOUT` stderr line is written by
  `[Console]::Error` inside a grandchild and must survive two capture hops. Only
  an OS-handle capture sees it; an in-process redirect never does (the CI step
  header records this being proven). Crossed by TEST-004 asserting a non-empty
  diag on the success arm.
- SEAM-3 — the wrapper's probe functions are shared BY DOT-SOURCE, not by
  module. A rename or signature change in `aai-run-tests.ps1` silently breaks
  the probe script. Crossed by TEST-005 (the name-level pin) and TEST-006 and
  TEST-007 (which call the real functions, so a rename fails the suite).
- SEAM-4 — the Pester result object crosses into the workflow's skip-count
  assertion, which is pinned from a bash suite over a hardcoded file list.
  Crossed by TEST-015 and by D5's choice not to add a new `*.Tests.ps1` file.
- SEAM-5 — the doctor's category array is consumed by
  `.aai/SKILL_DOCTOR.prompt.md`, which enumerates CAT-01..CAT-13 by name. Three
  new ids appear that the prompt does not list. TEST-010 pins the machine
  contract; whether the prompt is updated is an implementation decision that
  carries the prompt-diet obligation named above if taken.

## Residual risks (accepted)

- RR-1 — the arms only prove the wrapper on the machine the doctor runs on. A
  green self-test on windows-latest says nothing about a downstream box; that
  is the point of shipping the command rather than only the CI job.
- RR-2 — the induced spawn failure uses a decoy executable, not a real
  duplicate-casing dictionary collision. The original field defect
  (CHANGE-0133) still cannot be reproduced in-process on Windows (SPEC-0120
  RR-1). CAT-15 mitigates by REPORTING a live collision if one exists, which is
  what the incident actually needed.
- RR-3 — the four capability fields stay UNKNOWN forever unless a harness
  publishes them read-only. This is honesty, not coverage: the doctor reports
  what it cannot know.
- RR-4 — CAT-14 costs wall-clock on Windows (the timeout arm alone burns the 2
  second timeout plus the wrapper's outer grace). Bounded by the doctor's spawn
  timeout and reported as a WARN if exceeded; the section is skipped entirely
  off Windows.
- RR-5 — an agent CLI that hangs on `--version` would stall the probe; bounded
  by the per-CLI timeout, after which the CLI is reported UNKNOWN with the
  timeout as its reason rather than ABSENT.

## Verification

Commands to run:

- `bash tests/skills/test-aai-doctor.sh`
- `bash tests/skills/test-ps1-quality.sh` (parse gate, PSScriptAnalyzer 5.1 and
  7.0 compatibility, full Pester suite, POSIX SkippedCount zero)
- `bash tests/skills/test-aai-win-fallback.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-suite-select.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/aai-doctor.mjs` and `node .aai/scripts/aai-doctor.mjs --json`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0122-spec-doctor-win-selftest.md`
- the `ps1-quality / windows-5_1` job on this scope's PR (both engines)

Evidence artifacts: stored RED logs under `docs/ai/tdd/` for the TDD-lane
AC-gating tests (TEST-005, TEST-008, TEST-009, TEST-011); the recorded RED
observation for the loop-lane rows; full stdout with exit codes for every
command above; and the `windows-5_1` job URL plus the CAT-14 arm results copied
into the Spec-AC-01 evidence cell.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.
Spec-AC-01 may only reach `done` once the named CI job has actually run green on
the PR with the three arms reported PASS; until then it stays `planned`, which
blocks PASS by design.

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
`docs/ai/tdd/` per AC-gating test on the TDD lane (TEST-005, TEST-008, TEST-009,
TEST-011), plus the full verification matrix above. For the loop-lane rows the
RED observation is the pin failing on the pre-change tree, recorded but not
necessarily stored.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
