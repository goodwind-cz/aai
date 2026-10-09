---
id: spec-ci-windows-leg-waits-and-ps1-path-filter
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: ca8867fa1e7f14de7b3afd72f3a73db06c08436eea565de69bd059e8db7435ff
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/DEBT-DRAFT-ci-windows-leg-waits-and-ps1-path-filter.md
  pr: []
  commits: []
---

# Spec — The Windows wrapper timeout reaps the child tree, and ps1-quality runs only when a PowerShell-read file changes

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-DRAFT-ci-windows-leg-waits-and-ps1-path-filter.md (techdebt intake, id `ci-windows-leg-waits-and-ps1-path-filter`)
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md (platform matrix row "Windows + Git-Bash-only (no WSL)", unchanged by this spec)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, as re-verified by Planning (2026-10-09)

Planning re-read the CI evidence. It did not take the intake's numbers on trust.

1. The two "Real-wrapper smoke" steps still take about 300 s each. Run
   37860824798 (push to main, 2026-10-08), job 113595858379 (`windows-5_1`):
   the 5.1 smoke step took 306 s and the pwsh 7 step took 305 s. Run 37433146658
   (PR #431) shows the same: 07:59:53 to 08:05:00, then 08:05:00 to 08:10:06.
2. The timeout arm waits on the `sleep 300` fixture. In job 113595858379 the
   5.1 success arm returned at 23:41:48.99 and the timeout arm returned at
   23:46:50.44, so the arm took 301.4 s with `AAI_TEST_TIMEOUT=2`. The
   wrapper's own stderr in that arm shows that the inner watchdog DID fire at
   2 s: `AAI-TIMEOUT: 2s (source=env)` and then
   `aai-run-tests: TIMED OUT after 2s with no progress`. Exit code 124 was
   correct.
3. The wrapper itself returns in seconds. The 300 s is spent waiting for an
   orphan. The same job's Pester step runs the CAT-14 selftest
   (`.aai/scripts/aai-win-selftest.ps1`, `Invoke-SelfTestArmTimeout`). It uses
   the same wrapper, `AAI_TEST_TIMEOUT=2` and a `sleep 30` hang, but waits with
   `Process.WaitForExit(30 s)` on the engine process. It reported
   `exitCode 124, timedOut false`, and all three of its arms finished within
   11.72 s. The smoke harness waits with `Start-Process -Wait`, which waits for
   the started process AND ITS DESCENDANTS. The only process that can keep
   `-Wait` blocked for about 300 s after the wrapper has exited 124 is a
   surviving descendant of the `sleep 300` fixture. So the timeout does not
   reap the child tree on native Windows. The exit-code-only assertion in both
   the smoke step and CAT-14 hides that.
4. ps1-quality does trigger on ledger-only PRs. PR #431 changed only
   `tests/skills/lib/prompt-diet-ledger.sh` outside the filter's other
   entries, and it ran ps1-quality three times (runs 37433146658, 37425886824,
   37424658430). Over the 45 PRs in the analysis window, 23 triggered
   ps1-quality and 15 of those matched ONLY through `tests/skills/lib/**`. The
   lib files that caused those 15 triggers were `prompt-diet-ledger.sh` (11 PRs),
   `cd-subshell-leak-baseline.tsv` (6), `close-work-item-pin.sh` (2), and one
   PR each for `gh-merge-queue-stub.sh`, `shard-plan-check.sh`,
   `no-nul-guard.sh` and `learned-guard-lints.mjs`.
5. `windows-5_1` has no `timeout-minutes`, so the job inherits the 360-minute
   default. Measured over the 124 successful runs in the window: p50 12.4 min,
   p90 18.9 min, max 20.6 min. The job jumped from about 12.4 min to about
   19-20 min on 2026-10-08, when `tests/skills/aai-pr-preflight.Tests.ps1`
   (PR #434) joined the Pester steps. In job 113595858379 the two Pester steps
   took 242 s and 221 s.

### Corrections to the intake

- C1. The intake says PowerShell never reads `prompt-diet-ledger.sh`. That is
  FALSE since PR #434. `tests/skills/aai-pr-preflight.Tests.ps1` runs the
  TEST-008 Node matrix extracted from `tests/skills/test-aai-pr-preflight.sh`
  on every engine, Windows included. That matrix reads
  `tests/skills/lib/prompt-diet-ledger.sh` (around
  `tests/skills/test-aai-pr-preflight.sh:233`). D4 below decides what to do
  about it.
- C2. The intake expects `windows-5_1` p50 to drop to about 2-3 min. With the
  Pester growth of 2026-10-08 the realistic figure is about 19.5 - 10 = 9-10 min.
  This scope removes the about 10 min of smoke wait. It does not touch the
  Pester steps; those belong to the separate intake
  `slowest-suite-hot-spots`.
- C3. The intake places the bash wrapper out of scope. The defect lives in the
  bash wrapper's MSYS branch (`.aai/scripts/aai-run-tests.sh`), which is
  exactly the code the PowerShell dispatcher's Git-Bash branch executes. The
  intake's own Target State ("reaps the child tree") cannot be met without
  touching it. This spec therefore brings the MSYS branch of
  `.aai/scripts/aai-run-tests.sh` into scope. The macOS and Linux branches of
  that file stay untouched, and that is what the intake's exclusion meant.
  Disclosed here as a scope change against the intake.

## Root cause (decided)

The bash wrapper on Git-Bash/MSYS (`DEGRADED_MSYS=1`) reaps on timeout like this:

- The watchdog runs `taskkill //PID "$CMD_PID" //T` WITHOUT `//F`, and falls
  back to `kill -TERM "$CMD_PID"`.
- The always-reap step (`aai_reap_group`) then runs `taskkill //PID "$CMD_PID" //T //F`.

Two defects compound:

- H1, wrong PID namespace. `$CMD_PID` is the MSYS (Cygwin) pid from `$!`.
  `taskkill` wants a Windows PID. MSYS exposes the Windows PID at
  `/proc/<pid>/winpid`, and the wrapper never reads it.
- H2, the leader dies before the tree is walked. A non-forced `taskkill` is
  refused for console processes ("can only be terminated forcefully"). The
  fallback MSYS `kill -TERM` then ends only the leader `sh`. Its `sleep`
  child is orphaned. The orphan's Windows parent is now gone, so the forced
  `taskkill //T` in `aai_reap_group` can no longer reach it through the
  parent chain. That holds even if the PID had been right.

Either defect alone leaves the `sleep` alive. The ps1 dispatcher is not at
fault. Its outer `WaitForExit(timeout + 5 s)` is never reached, because
`bash.exe` exits on its own once the inner watchdog fires, and it exits 124.

Batch 1's first CI run (RED) confirms which of H1 and H2 actually fires,
through the survivor probe in D2. The fix in D1 removes both, so the design
does not depend on that answer. The answer is recorded in the TDD evidence.

## Implementation strategy
- Strategy: tdd
- Rationale: The owner chose `tdd` at intake. It is recorded in STATE with
  `source: intake` and `ref_id: ci-windows-leg-waits-and-ps1-path-filter`, and
  in the intake `## Notes` line "Implementation mode (user choice): tdd".
  Planning agrees. This is a behavioral fix in a process-reaping path whose
  previous tests stayed green over a real defect, because they asserted only
  the exit code. Only an observed RED (the CI survivor probe failing, and the
  local MSYS-branch tests failing on the pre-change wrapper) proves that the
  new assertions bite.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the main checkout is shared with other live sessions,
  and it currently holds four foreign untracked drafts. This scope changes the
  test wrapper that every suite runs through, and it needs a pushed branch so
  that CI can produce the Windows RED and GREEN runs. Implementation must not
  push from, or switch, the shared checkout.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be chosen by Implementation Preparation (suggested branch `debt/ci-windows-leg-waits-and-ps1-path-filter`)
- Inline review scope: `.aai/scripts/aai-run-tests.sh`, `.github/workflows/ps1-quality.yml`, `tests/skills/test-aai-win-fallback.sh`

## Design decisions

- D1, the fix lives in the MSYS branch of `.aai/scripts/aai-run-tests.sh` and
  nowhere else. It uses two new functions with these mandated shapes, and the
  mutations in the Test Plan target them.
  - `aai_msys_winpid <msys-pid>` prints the Windows PID it reads from
    `"${AAI_PROC_ROOT:-/proc}/$1/winpid"`, through the mandated line
    `aai_wp_file="${AAI_PROC_ROOT:-/proc}/$1/winpid"`. When that file is
    missing, unreadable or not all digits, it prints the MSYS pid unchanged,
    through the mandated case arm `''|*[!0-9]*) aai_wp="$1" ;;`. That is the
    Article 4 degrade: never an empty pid, never an abort.
    `AAI_PROC_ROOT` is a test-only override, in the same family as `AAI_UNAME`,
    and it is documented in the file header's Environment block.
  - `aai_msys_tree_kill <msys-pid>` runs one FORCED tree kill on the
    translated PID, with the mandated line
    `taskkill //PID "$aai_tk_wp" //T //F >/dev/null 2>&1 || kill -KILL "$1" 2>/dev/null`.
    The leader-only MSYS kill is only the fallback, after the forced tree
    kill has failed.
  - Both MSYS call sites, the watchdog subshell and `aai_reap_group`, call
    `aai_msys_tree_kill "$CMD_PID"` when `taskkill` is present. The polite
    non-forced `taskkill` is removed on MSYS: Windows refuses it for console
    processes anyway, and it was the trigger for H2. When `taskkill` is absent,
    the current `kill -TERM`, `sleep 1`, `kill -KILL` chain stays as it is.
  - The non-MSYS branches (setsid, perl-setsid, `set -m`, bare) and the
    `AAI_UNAME`-unset path stay byte-identical in behavior. The existing
    `test_007` pins this.
  - The `.aai/scripts/aai-run-tests.ps1` dispatcher is NOT changed. Its exit-code
    contract (0/N, 2, 78, 124, 125) and its outer watchdog stay as they are.
- D1-fallback, pre-declared and not pre-approved: if the Batch 2 CI run still
  shows a survivor after D1, for example because MSYS exec leaves the `sleep`
  outside the leader's Windows parent chain even with the right PID, the next
  step is a Windows Job Object in the ps1 dispatcher's Git-Bash launch. That
  is an additive spec amendment with its own TEST rows. It is not a silent
  redesign.
- D1-fallback ACTIVATED (amendment 1, 2026-10-09, additive, owner sign-off
  pending). The Batch 2 CI run 37894665268 still showed a survivor after D1.
  The diagnostic run 37896117512 then showed the cause: the forced
  `taskkill //PID <winpid> //T //F` did hit the right PID (sh.exe, MSYS pid
  1453 to winpid 4384) and killed it, but the orphan `sleep.exe` (winpid 2672)
  had Windows ParentProcessId 3184, a process that no longer existed. sh.exe
  itself had parent 6476, which was also gone. MSYS fork+exec gives each
  exec'd program a new Windows process whose parent is the short-lived fork
  stub, so the Windows parent chain is broken at every exec and no
  `taskkill /T` walk can reach the grandchild. So D1 stays as is (the right
  PID namespace, and harmless), and the pre-declared fallback is added:
  - `.aai/scripts/aai-run-tests.ps1` starts bash.exe SUSPENDED
    (`CreateProcessW` with `CREATE_SUSPENDED`), assigns it with
    `AssignProcessToJobObject` to a job carrying
    `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, then resumes it. Every descendant
    is in the job whatever its parent chain looks like. The job is terminated
    in `Invoke-ViaGitBash`'s `finally` on every exit path. The P/Invoke type
    is compiled with Add-Type on both Windows PowerShell 5.1 and pwsh 7.
  - If the job cannot be created or assigned, one stderr line
    `AAI-DEGRADED-MODE: [Git Bash] no Windows Job Object (<cause>) ...` is
    printed and the launch falls back to the previous Start-Process path. A
    CreateProcess failure is still a spawn failure (exit 125).
  - The exit-code contract (0/N, 2, 78, 124, 125) and stdout/stderr handling
    do not change. The platform-matrix rows do not change.
  - D1's sentence "the ps1 dispatcher is NOT changed" is superseded by this
    amendment. New Spec-AC-05 and TEST-010 to TEST-012 cover it.
  - Harness defect found on the first job run (37896949975): with NO
    survivor, `Get-SmokeHangSurvivors` returned `,$found` (unary comma), and
    the caller's `@(...)` turned the empty result into one phantom survivor,
    printed as `pid= ParentProcessId=`. The function now returns `$found`
    plainly. New TEST-013 (Spec-AC-02) runs the real function and caller
    line under pwsh with Win32_Process stubbed. The smoke harness also keeps
    one permanent line that names the survivor's parent and whether it is
    alive.
  - Residual: a wrapper run from Git Bash directly, without the ps1 in front,
    has no job. D1's forced tree kill still misses MSYS exec'd grandchildren
    there. The edge case below that says "D1 covers it" is therefore only
    partly true. Suggested follow-up: `fu-msys-direct-run-misses-exec-grandchildren`.
- D2, the smoke harness measures the wrapper, not the orphan. This applies to
  BOTH Real-wrapper smoke steps (5.1 and pwsh 7), in `Invoke-WrapperSmokeArm`:
  - Replace `Start-Process ... -Wait` with `-PassThru` plus
    `$null = $p.Handle`. That is the 5.1 ExitCode-null workaround and it is
    mandatory once `-Wait` is gone. Then use a bounded
    `$p.WaitForExit($armCeilingSeconds * 1000)` with
    `$armCeilingSeconds = 60`. If the ceiling is hit, the harness runs
    `taskkill /PID <pid> /T /F` and FAILS the arm. A future regression then
    costs at most 60 s, not 300 s.
  - The timeout arm measures with a Stopwatch from spawn to wrapper exit and
    asserts that the elapsed time is at most `$timeoutArmBoundSeconds = 20`.
    That is the wrapper's 2 s timeout, plus the inner 1 s poll and the reap
    grace, plus Windows engine start (the success arm takes about 3.5 s), with
    margin.
  - Survivor probe: a new function `Get-SmokeHangSurvivors -Token <arg>` lists
    `Get-CimInstance Win32_Process -Filter "Name = 'sleep.exe'"` entries whose
    CommandLine carries the hang fixture's own argument. It polls for up to
    5 s after the wrapper exits. Any survivor is a `FAIL timeout:` line that
    names its PID and ParentProcessId. That line is the RED observable and it
    identifies H1 or H2. Survivors are then force-stopped, so the step never
    stalls.
  - Positive control, so that an absence is never asserted vacuously: the hang
    fixture first writes a started-marker file, then sleeps:
    `echo started > "$AAI_SMOKE_HANG_MARKER"; sleep 300`. The arm FAILS if the
    marker is missing. On the pre-change tree the probe must FIND the
    survivor. That RED run is the proof that the probe can see the thing it
    asserts is absent.
- D3, the derived `paths:` filter. The `tests/skills/lib/**` entry in BOTH
  the `push` and `pull_request` lists is replaced by exactly these three entries:
  `tests/skills/lib/*.ps1`, `tests/skills/lib/assert-payload.sh` and
  `tests/skills/lib/pipe-safe.sh`. Every other existing entry stays. The
  derived set D is defined mechanically. It is every file that exists in
  `tests/skills/lib/` and is named as `lib/<name>` (or
  `tests/skills/lib/<name>`) in any of these:
  - `.aai/scripts/*.ps1`, `tests/skills/*.Tests.ps1` and `tests/skills/lib/*.ps1`
    (the PowerShell sources),
  - `tests/skills/test-ps1-quality.sh` (the `gate` job's entry point),
  - any `tests/skills/test-*.sh` that a `*.Tests.ps1` names (one hop, which
    today means `test-ps1-quality.sh` and `test-aai-pr-preflight.sh`).

  Measured today, D = { `pester-host-skip.ps1`, `pester-native-capture.ps1`,
  `assert-payload.sh`, `pipe-safe.sh`, `prompt-diet-ledger.sh` }.
- D4, a declared exemption, not a silent omission: `prompt-diet-ledger.sh` is
  in D (see C1) but is NOT added to the filter. The exemption is written in
  the workflow as one comment line of the form
  `# ps1-paths-exempt: tests/skills/lib/prompt-diet-ledger.sh -- <reason>`.
  The pin test requires every exemption to name a current member of D and to
  carry a non-empty reason. The reason is that the file's only PowerShell-side
  reader is the TEST-008 ledger arithmetic, which is platform-neutral Node
  logic. The same matrix runs on Linux in `test-aai-pr-preflight.sh`, and its
  own LF/CRLF parity assertion covers the one Windows-specific difference.
  Keeping the file in the filter would cut the saving from 15 lib-only PRs to
  4 out of 45. This is offered to the owner as a menu (see Return). The spec
  freezes the recommended option.
- D5, `timeout-minutes: 30` on the `windows-5_1` job. 30 is at least 1.45 times
  the measured pre-fix maximum (20.6 min) and 1.6 times the measured p90
  (18.9 min). So the pre-fix tree, which Batch 1's RED commit still runs, is
  never cut by the new bound. It also caps a hung runner at 30 min instead of
  360. The expected post-fix duration is about 9-10 min. The step-level
  `timeout-minutes: 15` on the two Pester steps stays, and `test_016` pins it.
- D6, the new static pins live in `tests/skills/test-aai-win-fallback.sh`. That
  suite already owns the Windows-fallback wiring and `ps1-quality.yml` pins.
  It is a `test-aai-*` sweep suite, and `select-suites.mjs` selects it for both
  `.github/workflows/ps1-quality.yml` and changes to its own file. The new
  functions are `test_029` to `test_037`, and they are added to `ALL_TESTS`.
  `tests/skills/test-ps1-quality.sh` is deliberately not used, because it is
  outside the sweep glob (`fu-ps1-quality-outside-sweep-glob`).

## Implementation plan

Components:
- `.aai/scripts/aai-run-tests.sh`: the MSYS branch per D1, and a header line for `AAI_PROC_ROOT`.
- `.github/workflows/ps1-quality.yml`: the fixture-prep step writes the
  started marker (D2). Both Real-wrapper smoke steps get the D2 changes. Both
  `paths:` lists change and the exemption comment is added (D3, D4). The
  `windows-5_1` job gets `timeout-minutes: 30` (D5).
- `tests/skills/test-aai-win-fallback.sh`: `test_029` to `test_037`.

Batches (about 3 AC each). The order is load-bearing, because the CI RED
needs the new harness running against the OLD wrapper:

1. Batch 1, Spec-AC-02 (TEST-004, TEST-005). Change the harness and add the
   static pins. Then push the branch and dispatch
   `gh workflow run ps1-quality.yml --ref <branch>`. The expected CI RED is a
   `FAIL timeout:` survivor line in both smoke steps, with both steps done in
   about 60-70 s instead of 300 s. Save the excerpt as the RED artifact.
2. Batch 2, Spec-AC-01 (TEST-001, TEST-002, TEST-003). Run local TDD on the
   MSYS branch with RED-then-GREEN per test, then push and dispatch again. The
   expected CI GREEN is no survivor, the timeout arm elapsed at most 20 s,
   each smoke step at most 60 s, and CAT-14 still PASS. Save the excerpt as
   the GREEN artifact.
3. Batch 3, Spec-AC-03 and Spec-AC-04 (TEST-006 to TEST-009). Make the
   filter, exemption and timeout changes, and record local RED and GREEN for
   each pin.

Edge cases:
- `/proc/<pid>/winpid` is missing because the process has already exited.
  `aai_msys_winpid` then degrades to the MSYS pid, `taskkill` fails quietly,
  and the `kill -KILL` fallback runs. The result is the same as today and
  never worse.
- The wrapper is invoked from Git Bash directly, without the ps1 in front. D1
  covers it, because the fix is in the `.sh` file itself.
- A survivor's stdout handle holds the arm's `.out` file open. PowerShell's
  `Get-Content` opens with shared read, but the implementer must verify this
  on the RED run, where the survivor really exists.
- A legitimately slow Windows runner: the 20 s bound is about 5 times the
  measured success-arm latency. A flake would show as a named `FAIL timeout:
  elapsed` line, not as a silent hang.

Locally provable (macOS, bash, plus pwsh 7 for parsing only): TEST-001 to TEST-003 use
`AAI_UNAME=MINGW64_NT-10.0`, a PATH-stubbed `taskkill` and an `AAI_PROC_ROOT`
fixture. The stub models Windows: it refuses non-forced calls on a
console-process target, and for `//T` it walks children by parent pid, just as
Windows walks ParentProcessId. A leader killed before the walk therefore
orphans its child exactly as it does on Windows. TEST-004 to TEST-009 are
static. Only CI can prove the Windows behavior itself (see RR-1).

## Seams this change crosses

- SEAM-1. The `.sh` MSYS reap and the ps1 dispatcher's Git-Bash branch
  (`Invoke-ViaGitBash` waits on `bash.exe` and propagates 124). This is
  crossed for real only by the CI smoke timeout arm: the real
  `aai-run-tests.ps1`, the real `bash.exe`, a real `sh` and a real
  `sleep.exe`, on 5.1 and pwsh 7. Evidence comes from the RED and GREEN CI
  logs.
- SEAM-2. The wrapper and the CAT-14 selftest (`aai-win-selftest.ps1`), which
  `aai-doctor` and `aai-win-dispatch.Tests.ps1` run. Its timeout arm must stay
  PASS (exit 124, no AAI-SPAWN-ERROR). This is crossed by the existing Pester
  step in the same GREEN CI run, and checked in its log.
- SEAM-3. The `paths:` filter and what the PowerShell jobs actually read. This
  is crossed by TEST-006 to TEST-008, which derive D from the real sources and
  check the real workflow.
- SEAM-4. The exit-code contract. On 124 and 125 the success, timeout and
  spawnfail arms keep their exact assertions, and both GREEN smoke steps show
  them.
- SEAM-5 (residual, not crossed). D4 assumes that a ledger-only change is
  still covered on Linux. However, `select-suites.mjs` today maps
  `tests/skills/lib/prompt-diet-ledger.sh` to `aai-win-fallback` plus the core
  suites, and NOT to `aai-pr-preflight`, which Planning measured with
  `--files-from`. A ledger-only PR in selected mode therefore runs the TEST-008
  ledger arm nowhere, until a full run. See RR-3 and the suggested follow-up.

## Acceptance Criteria Mapping
- Maps to: intake Target State bullet 1. Spec-AC-01 and Spec-AC-02 verify it
  with local TEST-001 to TEST-005 and the CI RED and GREEN logs.
- Maps to: intake Target State bullet 2. Spec-AC-03 verifies it with TEST-006
  to TEST-008.
- Maps to: intake Target State bullet 3. Spec-AC-04 verifies it with TEST-009.

## Constitution deviations

None.

Article 4 (degrade and report) is honored by the D1 winpid fallback. Article 1
(evidence before claims) is honored by keeping every Windows claim tied to a
named CI run log. Article 5 (additive first) holds: the wrapper's exit codes
and the platform-matrix text stay unchanged.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the wrapper runs under Git-Bash/MSYS and the watchdog fires, the system SHALL issue one forced tree kill (taskkill //T //F) on the Windows PID read from the proc winpid entry of the command's MSYS pid, before any leader-only kill, and SHALL fall back to the MSYS pid itself when no winpid entry is readable. | planned | — | — | D1; non-MSYS branches unchanged (test_007) |
| Spec-AC-02 | WHEN the ps1-quality timeout arm runs aai-run-tests.ps1 with AAI_TEST_TIMEOUT=2 around a 300 s hang on Windows PowerShell 5.1 and on pwsh 7, the harness SHALL wait on the wrapper process only (no Start-Process -Wait), SHALL fail the arm unless the wrapper exits 124 within 20 s and no process of the hang fixture survives 5 s after that exit, and SHALL fail the arm when the fixture's started marker is missing. | planned | — | — | D2; Windows proof is the CI RED and GREEN run logs |
| Spec-AC-03 | WHEN any PowerShell source, Pester test, or bash suite named by a Pester test names a file under tests/skills/lib, the ps1-quality push and pull_request path lists SHALL match that file or carry a reasoned ps1-paths-exempt line for it, and the lists SHALL be identical and SHALL match no other tests/skills/lib file. | planned | — | — | D3, D4 |
| Spec-AC-04 | The windows-5_1 job SHALL declare a job-level timeout-minutes between 26 and 45 inclusive (value 30). | planned | — | — | D5 |
| Spec-AC-05 | WHEN aai-run-tests.ps1 launches the Git-Bash branch on Windows, the dispatcher SHALL start bash.exe suspended inside a Job Object carrying JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, assign it before resuming it, and terminate the job on every exit path with the exit-code contract unchanged; WHEN no job can be created or assigned it SHALL print one AAI-DEGRADED-MODE line naming the cause and launch as before. | planned | — | — | Amendment 1 (D1-fallback); Windows proof is the windows-5_1 smoke timeout arm |

Status values: planned | implementing | done | deferred | blocked | rejected

## Test Plan

Every TEST row is a function in `tests/skills/test-aai-win-fallback.sh` and is
run as `bash tests/skills/test-aai-win-fallback.sh <NNN>`. The Mutation cells
target shapes this spec MANDATES (D1 to D5) or, for TEST-008, a mandated line
inside the pin itself (`local scan_tests_glob='*.Tests.ps1'`). If
implementation renames a mandated shape, restamp the mutation mechanically and
disclose the restamp in the TDD record. Every RED observation goes under
`docs/ai/tdd/` as `ci-windows-leg-waits-and-ps1-path-filter-red-<TEST-ID>.log`.
Every mutation record goes to
`docs/ai/tdd/spec-ci-windows-leg-waits-and-ps1-path-filter/mutation-<TEST-ID>.txt`.
The CI artifacts are
`docs/ai/tdd/ci-windows-leg-waits-and-ps1-path-filter-ci-red.log` and
`...-ci-green.log`. Each one is a `gh run view <run> --log --job <job>`
excerpt that starts with the run id, the job id and the headSha. Fixtures live
in `mktemp -d` scratch directories. Every fixture-spawned `sleep` is recorded
by pid and killed in a trap, so no busy or sleeping process outlives the suite.

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Mutation | Status |
|----------|------------|-------------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-win-fallback.sh | test_029: under AAI_UNAME=MINGW64_NT-10.0 with a fixture command that writes its own winpid entry (MSYS pid plus 100000) into AAI_PROC_ROOT, the stub taskkill log shows the timeout-path kill aimed at the mapped Windows PID, never the raw MSYS pid | sed:s/winpid"/winpid_absent"/ | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-win-fallback.sh | test_030: with a parent-walking stub that refuses non-forced calls, the first taskkill call carries //T and //F, the wrapper exits 124 within TIMEOUT plus 8 s, and the fixture's grandchild sleep (pid file written before the timeout as a positive control) is gone after the wrapper returns | sed:s/ \/\/T \/\/F >/ \/\/T >/ | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-win-fallback.sh | test_031: with an empty AAI_PROC_ROOT the stub taskkill receives the MSYS pid itself (never an empty pid) and the wrapper still exits 124 | sed:s/aai_wp="\$1" ;;/aai_wp="" ;;/ | green |
| TEST-004 | Spec-AC-02 | static      | tests/skills/test-aai-win-fallback.sh | test_032: in BOTH Real-wrapper smoke step bodies the arm's Start-Process line carries no -Wait, a bounded $p.WaitForExit($armCeilingSeconds * 1000) follows it, and $timeoutArmBoundSeconds is greater than 2 and at most 30 | sed:s/\$p\.WaitForExit\(\$armCeilingSeconds \* 1000\)/$true/ | green |
| TEST-005 | Spec-AC-02 | static      | tests/skills/test-aai-win-fallback.sh | test_033: in BOTH smoke steps the timeout arm calls Get-SmokeHangSurvivors -Token and turns a non-empty result into a FAIL timeout line, and asserts the AAI_SMOKE_HANG_MARKER started marker; the fixture-prep step writes that marker before sleep 300 | sed:s/Get-SmokeHangSurvivors -Token/Get-SmokeHangSurvivorsOff -Token/ | green |
| TEST-006 | Spec-AC-03 | static      | tests/skills/test-aai-win-fallback.sh | test_034: the push and pull_request path lists are identical; every member of the derived set D is matched by a list entry or named by a ps1-paths-exempt line with a non-empty reason; positive control: D has at least 4 members and contains pester-host-skip.ps1 and assert-payload.sh | sed:s/tests\/skills\/lib\/pipe-safe\.sh/tests\/skills\/lib\/pipe-safe-gone.sh/ | green |
| TEST-007 | Spec-AC-03 | static      | tests/skills/test-aai-win-fallback.sh | test_035: under GitHub glob semantics the lists match no tests/skills/lib file outside D, so prompt-diet-ledger.sh and cd-subshell-leak-baseline.tsv do not trigger ps1-quality, and no list entry is the bare tests/skills/lib/** glob | sed:s/tests\/skills\/lib\/\*\.ps1/tests\/skills\/lib\/**/ | green |
| TEST-008 | Spec-AC-03 | integration | tests/skills/test-aai-win-fallback.sh | test_036: on a scratch fixture tree whose Tests.ps1 reads a new lib data file, the derived-set check fails and names that file, which proves a new PowerShell-read helper cannot be missed | sed:s/scan_tests_glob='\*\.Tests\.ps1'/scan_tests_glob='*.none'/ | green |
| TEST-009 | Spec-AC-04 | static      | tests/skills/test-aai-win-fallback.sh | test_037: the windows-5_1 job block carries a job-level timeout-minutes between 26 and 45 inclusive, while windows-wsl1 keeps 25 and the step-level 15 on the Pester steps stays | sed:s/    timeout-minutes: 30/    timeout-minutes: 360/ | green |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-win-fallback.sh | test_038: under pwsh with the dispatcher's seams stubbed, Invoke-ViaGitBash launches through Start-ProcessInJob, never Start-Process, keeps exit 7 on the normal path and 124 on the timeout path, and calls Stop-KillOnCloseJob on the job exactly once on each path (after the tree kill on timeout); it also passes the PowerShell location (not the process directory) to Start-ProcessInJob as the working directory, and the P/Invoke source hands that cwd to CreateProcessW (M1, validation round 1) | sed:s/Stop-KillOnCloseJob -Job \$proc\.AaiJob/$null/ | green |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-win-fallback.sh | test_039: a job that cannot be created, or a failed assignment, prints one named AAI-DEGRADED-MODE line carrying the cause and launches through Start-Process with the exit code kept; a CreateProcess failure stays an AAI-SPAWN-ERROR exit 125 and closes the job without a second launch | sed:s/Write-JobDegradedLine -Reason \$_\.Exception\.Message/$null/ | green |
| TEST-012 | Spec-AC-05 | static      | tests/skills/test-aai-win-fallback.sh | test_040: the P/Invoke source sets LimitFlags to JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE (0x2000), creates bash with CREATE_SUSPENDED, calls AssignProcessToJobObject before ResumeThread, and the AaiJobObject type compiles under pwsh (named skip without pwsh) | sed:s/LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE/LimitFlags = 0/ | green |
| TEST-013 | Spec-AC-02 | integration | tests/skills/test-aai-win-fallback.sh | test_041: in both smoke steps the survivor function and its caller line, run under pwsh with Win32_Process stubbed, report zero survivors when none exist and exactly one (pid 2672) when one sleep 300 exists beside an unrelated sleep 1 | sed:s/\{ return \$found \}/{ return ,$found }/g | green |

Test status values: pending → red → green

## Verification

Commands, all run from the worktree root:
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh`
  (the new 029 to 037 plus the existing 007, 009 and 016 to 028, as non-regression)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`
  (the non-MSYS reap contract must not move)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-friction-capture-points.sh`,
  `test-aai-repo-tripwire.sh`, `test-aai-suite-isolation.sh`, `test-aai-sweep-parallel.sh`,
  `test-aai-tdd-evidence.sh` (the suites `select-suites.mjs` picks for `.aai/scripts/aai-run-tests.sh`)
- `bash tests/skills/test-ps1-quality.sh` locally (pwsh 7 is present on this
  host). PSScriptAnalyzer and Pester degrade by name if they are absent.
- CI: `gh workflow run ps1-quality.yml --ref <branch>` after Batch 1 (RED) and
  after Batch 2 (GREEN), then `gh run view <run> --json jobs` for step timings
  and `gh run view <run> --log --job <windows-5_1 job>` for the arm lines. Wait
  about 40 s after a push before watching.
- `node .aai/scripts/mutation-run.mjs` per row, then
  `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-DRAFT-spec-ci-windows-leg-waits-and-ps1-path-filter.md`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-ci-windows-leg-waits-and-ps1-path-filter.md`
- `node .aai/scripts/docs-audit.mjs --strict`
- One full sweep before close: `AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`

PASS criteria:
- All TEST-xxx are green with mutation records, and all Spec-AC are in a terminal status.
- The CI RED log shows a `FAIL timeout:` survivor line on at least one engine,
  run against the pre-fix wrapper.
- The CI GREEN log shows these on BOTH engines: no survivor, timeout-arm
  elapsed at most 20 s, success exit 3, spawnfail exit 125, the
  `REAL-WRAPPER SMOKE OK` line, and each Real-wrapper smoke step at most 60 s
  by `gh run view --json jobs`.
- In the same GREEN run, the CAT-14 timeout arm still reports PASS.
- `docs-audit --strict` is CLEAN.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: `ci-windows-leg-waits-and-ps1-path-filter`
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available (for the CI artifacts: run id, job id and headSha)

### Evidence by strategy

The recorded strategy is `tdd`, so the demanded evidence is the `tdd / hybrid`
row: a stored RED artifact per AC-gating test under `docs/ai/tdd/`, a verified
Mutation record per Test Plan row, the two CI run artifacts, and the full
verification matrix above.

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope

Source: `node .aai/scripts/follow-ups.mjs list`, read on 2026-10-09 and scanned
for windows, ps1, pester, msys, taskkill, timeout, smoke, reap and path-filter subjects.
Re-read at the validation FAIL (round 1): this scope delivers none of the four
items below, so it closes none of them.

NOT CLOSED, with reason (all four stay open):
- `fu-mutation-gate-skips-pester` (P3). This is the reason the Windows
  behavior is proven by CI run logs plus static pins with mutations, and not
  by a Pester row. Nothing here adds Pester mutation support.
- `fu-ps1-quality-outside-sweep-glob` (P3). This scope routes around it: the
  new pins go to `test-aai-win-fallback.sh`, not `test-ps1-quality.sh`.
  It does not fix the glob.
- `fu-runtests-ps1-captures-no-friction` (P3). Amendment 1 changed the ps1
  dispatcher's Git-Bash launch (Job Object), but it added no friction-channel
  capture point, so a Windows-only failure still never reaches the channel.
- `fu-lib-graph-narrowing-after-sharding` (P2). This item is about
  `select-suites`' lib mapping. SEAM-5 is an instance of that subject, and
  this scope does not change `select-suites`.

## Residual risks

- RR-1. The Windows behavior can only be proven on GitHub's `windows-latest`
  runner. The local tests model Windows' parent-chain tree kill with a stub, so
  they prove the wrapper's ORDER and PID choice, not Windows itself. If the D1
  mechanism is insufficient on real MSYS, only the Batch 2 CI run can show it.
  The answer then is the D1-fallback amendment.
- RR-2. The static pins TEST-004 and TEST-005 prove that the harness assertions
  EXIST and stay wired. They do not prove the assertions run correctly. That
  proof is the CI RED and GREEN pair, and it is not replayable by
  `mutation-run`.
- RR-3. Because of the D4 exemption and SEAM-5, a ledger-only PR in selected
  mode runs the TEST-008 ledger arm on no platform until the next full run.
  This is accepted for the saving (15 of 45 PRs no longer start a Windows VM).
  The suggested follow-up is
  `fu-select-suites-misses-preflight-ledger-read`.
- RR-4. The derived set D covers `tests/skills/lib/` only. Planning found that
  the Pester steps also read files outside lib which are NOT in the filter
  today: `.aai/scripts/aai-doctor.mjs`, `.aai/scripts/check-state.mjs`,
  `.aai/scripts/aai-reap-tests.sh`, `.aai/scripts/pr-preflight.mjs`,
  `tests/skills/test-aai-pr-preflight.sh` and `.aai/SKILL_PR.prompt.md`. That
  gap predates this scope and this scope does not widen it. The suggested
  follow-up is `fu-ps1-filter-misses-non-lib-reads`.
- RR-5. Removing the polite `taskkill` on MSYS removes the grace that would
  let a Windows GUI-capable child shut down cleanly. Test runners are console
  processes, which Windows refuses to close politely anyway, so nothing is
  lost in practice. Disclosed all the same.
