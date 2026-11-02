---
id: spec-node-first-reap-tests
type: spec
number: null
status: implementing
frozen_sha256: ef5017b6d951815a09dd3bdd54a708af5d2c8801cb0a15ade783340559760c16
mutation_gate: v1
ceremony_level: 2
links:
  requirement: node-first-reap-tests
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the test-process reaper (aai-reap-tests) to Node

SPEC-FROZEN: true

## Links

- Requirement: [Move the test-process reaper to Node](../issues/CHANGE-DRAFT-node-first-reap-tests.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5 (process adapters) and the section "Remaining paired scripts after
  phase 3".
- Pattern precedents: [SPEC-0247](SPEC-0247-spec-node-first-sync-hook-slice.md),
  [SPEC-0248](SPEC-0248-spec-node-first-second-slice.md),
  [SPEC-0249](SPEC-0249-spec-node-first-third-slice.md) and
  [SPEC-0265](SPEC-0265-spec-node-first-small-pairs.md): one module, thin
  launchers, a measured drift table, Windows parity proven only on the hosted
  Windows jobs, a hosted failure diagnosed with a probe first.
- Reaper contracts this scope re-homes (amendment records, D3):
  [SPEC-0046](SPEC-0046-spec-test-wrapper-windows-fallback.md) TEST-006 and
  TEST-009, [SPEC-0064](SPEC-0064-spec-reaper-deterministic-age-guard.md)
  TEST-004 and TEST-005,
  [SPEC-0083](SPEC-0083-spec-reaper-test-018-etime-shape-guard.md) TEST-022,
  [SPEC-0121](SPEC-0121-spec-pester-on-windows-ci.md) TEST-007, TEST-008 and
  TEST-009, and SPEC-0249 TEST-2624.
- Reaper history kept intact: SPEC-0009 (workspace scope, group and subtree
  kill), SPEC-0064 (epoch mode), SPEC-0072 (age-wait margins), SPEC-0076 and
  SPEC-0083 (diagnostic lines, impossible-age clamp).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor
  downstream, Node 24 CI).
- Baseline: main `f5a4f49d`; the ride branch adds only the intake (`06b881d9`).

## Implementation strategy

- Strategy: hybrid
- Rationale: the module, the two launchers, the decision logic and every
  drift choice are new behavior on a safety-critical path, so every row that
  gates them goes RED first on the baseline (the module does not exist; the
  current copies fail the drift cases) and carries a mutation record. The
  re-homing of existing reaper tests, the wiring (PROFILES, suite map, the
  ps1-quality path filter), the RFC and the documentation lines are
  mechanical and done in loop mode, each pinned by a mutation-gated row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a shipped core script pair, a CI
  workflow, the vendored profile manifest, five closed specs' tests and an
  umbrella RFC, running beside the reuse-for-docs-reading-suites ride; the
  ride already runs in its own linked worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: feat/node-first-reap-tests at /Users/ales/Projects/aai-worktrees/node-first-reap-tests
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/aai-reap-tests.mjs .aai/scripts/aai-reap-tests.sh
  .aai/scripts/aai-reap-tests.ps1 .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/test-aai-reap-tests.sh
  tests/skills/lib/aai-reap-tests.test.mjs tests/skills/aai-reap-tests.Tests.ps1
  tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/test-aai-run-tests.sh
  tests/skills/test-aai-win-fallback.sh tests/skills/test-aai-expert-fetch.sh
  docs/TECHNOLOGY.md docs/USER_GUIDE.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl CHANGELOG.md
  docs/issues/CHANGE-DRAFT-node-first-reap-tests.md
  docs/specs/SPEC-DRAFT-spec-node-first-reap-tests.md
  (suite-weights.tsv only if the selector asks for a row).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash with `/usr/bin/grep`, dash,
Node 22.23.1, pwsh 7.6.3) on 2026-11-02. The sh copy ran on real marked
`sleep` processes in a scratch workspace; the ps1 copy's decision functions
ran under pwsh 7 against fixture snapshots (dot-sourced, as the Pester file
does), because `Get-CimInstance` and `taskkill` exist only on Windows. Windows
PowerShell 5.1 was not available to Planning; rows marked "by inspection"
were read from the code.

- Lines before: `aai-reap-tests.sh` 368, `aai-reap-tests.ps1` 419, total 787.
- Callers outside docs: SKILL_LOOP, VALIDATION and SKILL_BOOTSTRAP name the
  two commands (`.aai/scripts/aai-reap-tests.sh`, `powershell -NoProfile -File
  .aai/scripts/aai-reap-tests.ps1`) and point at "the script's header" for the
  safety contract; `aai-run-tests.{sh,ps1}` only name the reaper in comments;
  PROFILES lists both files in `core:`; suite-map rows `aai-run-tests` and
  `aai-win-fallback` glob both files. No caller reads the reaper's exit code.
- Executing tests today: `tests/skills/test-aai-run-tests.sh` TEST-005, 006,
  012, 013, 015, 016, 017, 018, 021 and 023 run the sh copy on real processes;
  TEST-019 and TEST-022 read the sh source (TEST-022 extracts
  `etime_to_secs` with sed); TEST-030 counts seven `AGE-WAIT` tags in that file;
  `tests/skills/test-aai-win-fallback.sh` TEST-009 greps the 5-row platform
  matrix in the sh file; `tests/skills/aai-win-dispatch.Tests.ps1` holds a
  Describe `aai-reap-tests.ps1` of 24 cases that dot-source the ps1 and mock
  its functions; `tests/skills/test-aai-expert-fetch.sh` TEST-2624 requires an
  inventory row `aai-reap-tests` with destination `phase 5 process adapter`.
- The windows-wsl1 job's Debian distro has no Node (the workflow installs
  none); no job runs the real reaper on Windows today, only the mocked Pester
  cases.
- The reaper suite has a known CI-load flake history (TEST-018 legacy
  direction, TEST-006, 015, 016 epoch direction); the impossible-age clamp
  (SPEC-0083) is the root-cause guard for the epoch over-reach and must
  survive the move unchanged.

### Drift between the two copies (measured or by inspection)

| Id | Case | sh copy | ps1 copy | Decision |
|---|---|---|---|---|
| R-1 | token case (`VITEST`, `Vitest`) | not matched (measured) | matched, `(?i)` (measured) | case-insensitive on win32, exact on every other platform (each platform keeps its current set) |
| R-2 | workspace case (`/WS/A` for `/ws/a`) | not matched (measured) | matched, `-notmatch` folds case (measured) | same rule as R-1 |
| R-3 | separator after the workspace | `/` only (backslash not matched, measured) | backslash or `/` (measured) | win32 accepts backslash or `/`; every other platform `/` only |
| R-4 | trailing separators on the workspace | strips one; `ws//` matches nothing (measured) | strips all (measured) | strip all trailing separators (`/` on POSIX, backslash and `/` on win32) |
| R-5 | workspace that is a filesystem root (`/`, `C:\`, empty) | matches every process with a `/` in its arguments (by inspection; not run live) | matches every process (measured) | refused: nothing is listed or killed, stderr `aai-reap-tests: refused - workspace is a filesystem root (<raw>); nothing reaped`, the four report lines with 0, exit 0 |
| R-6 | Windows process without a creation time | n/a | reaped in StepStart mode, throws in legacy mode (measured) | spared in both modes, like an unparseable etime |
| R-7 | `AAI_REAP_MIN_AGE_SECS` or `AAI_REAP_GRACE_SECS` beyond 32-bit, or with a trailing newline | digits-only check; overflow compares false and spares (by inspection) | `[int]` cast throws; `^[0-9]+$` accepts a trailing newline (measured) | digits only, no trailing newline, any length, parsed with `Number` (a huge minimum age spares everything); otherwise the default (0 and 2) |
| R-8 | `AAI_REAP_STEP_START_EPOCH` validity | digits, above 0, at most the snapshot second (by inspection) | same, compared to `Get-Date` before listing (measured: 0, future, huge give legacy; `00012` gives 12) | digits, above 0, at most the snapshot second taken right after listing; else legacy mode |
| R-9 | self and parent exclusion | skips `$$` and `$PPID` | none | skips `process.pid` and `process.ppid` on every platform (the sh launcher execs, so these equal the old `$$` and `$PPID`) |
| R-10 | report lines | `reaped: N`, `reaped pids:`, `reaped ages:`, `reaped raw:` on every path | `reaped: N` only | the four sh lines on every platform and path; on win32 an age is whole seconds since creation and a raw entry is `<pid> <creation ms> <command line>` |
| R-11 | tree kill | group leader: TERM the group; else TERM the ppid subtree; 1 s; KILL the same targets | `taskkill /PID n /T /F` | unchanged per platform: the sh behavior on POSIX, `taskkill` on win32 |
| R-12 | WSL half | n/a | when the sentinel probe returns exactly 42 within 5 s, runs the sh copy inside WSL with `env` overrides, prints its output, suppresses the native summary; on an exception prints `reaped: 0` | kept, same probe argv and delegation argv; the WSL side is now the sh launcher, which needs Node inside WSL: delegate stdout that holds a `reaped: ` line is printed verbatim and the native summary is suppressed; otherwise the native four lines are printed and stderr gets `aai-reap-tests: WSL half did not report (exit <code>); native summary follows` |
| R-13 | process listing fails | the four lines with 0, exit 0 | uncaught error (by inspection) | the four lines with 0, stderr `aai-reap-tests: process listing failed: <reason>`, exit 0 |
| R-14 | default workspace | logical `$PWD` | `(Get-Location).Path` | the sh launcher exports `AAI_REAP_WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"` (logical path kept); the ps1 launcher sets nothing and the module defaults to `process.cwd()`, which PowerShell sets to the current FileSystem location for a native call |
| R-15 | Windows time base | local `DateTime` values compared | same | UTC milliseconds (`ToUnixTimeMilliseconds`), so a DST fold cannot shift a decision |
| R-16 | Node absent or module missing | never needed Node | never needed Node | each launcher prints exactly `aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped` on stderr, nothing on stdout, exit 1 |
| R-17 | unparseable or impossible etime | sentinel -1, spared before either mode, incl. the pre-epoch clamp | n/a | unchanged, same grammar, range guard and clamp |
| R-18 | listing size | file redirect, no limit | n/a | `spawnSync` with a 64 MiB buffer, so a busy CI process table cannot truncate the listing |
| R-19 | sh copy run from Git Bash on Windows | MSYS `ps` (not the primary path per its header) | n/a | Node there is the Windows Node, so the native Windows listing and `taskkill` run (the ps1 native path) |

Observed and left alone (no new features): the WSL half receives the Windows
workspace path (`C:\...`) as `AAI_REAP_WORKSPACE`, while processes inside WSL
carry `/mnt/c/...` paths, so the WSL half matches only command lines that
contain the Windows form. Changing that changes which processes are reaped;
it is filed as a follow-up at delivery (Registry disposition), not changed
here.

## Decisions

- D-LIST (process listing per platform): POSIX runs `ps axo pid=,etime=,args=`
  for matching (identical to the sh copy) and, after matching, one
  `ps axo pid=,ppid=,pgid=` snapshot for the group check and the subtree walk
  (it replaces the sh copy's separate pid-to-ppid snapshot and per-pid pgid
  calls); the snapshot second is `Math.floor(Date.now() / 1000)` taken right
  after the matching `ps` returns. win32 runs `powershell.exe` (then `pwsh` when
  `powershell.exe` cannot start) with `-NoProfile -NonInteractive -Command`, a
  script that sets the console output encoding to UTF-8 and prints one line per
  `Get-CimInstance Win32_Process` entry: process id, parent id, creation time in
  UTC milliseconds (empty when absent) and the command line, tab-separated, the
  command line last. The intake's "tasklist/wmic fallback as the PowerShell
  copy does today" is not in the ps1 copy (measured: CIM only); `tasklist`
  carries no command line and `wmic` is removed from current Windows, so no such
  fallback is added.
- D-KILL (tree kill per platform): R-11. POSIX: a matched pid that is its own
  group leader gets SIGTERM to the group, otherwise SIGTERM to it and its
  ppid-subtree; one 1000 ms wait only when at least one target exists; then
  SIGKILL to the same targets; ESRCH ignored. win32: `taskkill /PID <pid> /T /F`
  per candidate.
- D-NODE (Node absent): R-16, exit 1. Exit 1 is otherwise reached only by an
  internal error (`aai-reap-tests: error: <message>` on stderr), so a non-zero
  exit always means the sweep did not complete; the empty stdout means no
  parser can read a refusal as `reaped: 0`.
- D-DRIFT: R-1 to R-19 as tabled. The guiding rule: no platform reaps a process
  it spared before, except R-4 (a workspace written with extra trailing
  separators now names its own directory) and R-19 (Git Bash on Windows now gets
  the native pass); R-5 and R-6 narrow scope.
- D-CLEAN (real-process tests clean up safely): fixtures are Node sleepers
  (`process.execPath -e "setTimeout(() => {}, 90000)" vitest <ws>/worker`) that
  exit on their own after 90 s; every spawned pid, including the token-less
  child each fixture parent reports on its first stdout line, is recorded and
  killed by pid in `after()` / `AfterEach` (SIGKILL on POSIX, `Stop-Process -Id
  -Force` on Windows); a final check lists processes and fails if any command
  line still holds the test's unique workspace root. No `pkill`, no kill by
  name or pattern, workspaces are fresh `mkdtemp` directories, so a sibling
  checkout's processes are never candidates.
- D-WSL: R-12. The probe is `wsl.exe -e sh -c "exit 42"` with a 5 s timeout and
  ignored stdio; usable only on exit code exactly 42. The delegation argv is
  `-e env AAI_REAP_WORKSPACE=<ws> AAI_REAP_MIN_AGE_SECS=<n>` plus
  `AAI_REAP_STEP_START_EPOCH=<raw>` (and `AAI_REAP_GRACE_SECS=<raw>` when set)
  only when the raw epoch is non-empty, then the `wsl.exe wslpath -a` form of
  the sh launcher (the raw path when wslpath fails): the same argv
  `Get-ReapWslDelegationArgs` builds today.

## Scope and design

### D1. `.aai/scripts/aai-reap-tests.mjs`

Dependency-free ESM, Node 22 compatible (`node:child_process`, `node:fs`,
`node:path`, `node:url` only), at most 320 lines, ASCII only, no side effects on
import, never reads standard input, writes no file. Its header carries the
safety invariant (never global, workspace-scoped, age-guarded, both modes), the
environment variables and the 5-row platform matrix the sh header carries
today (macOS, Linux, Windows + WSL, Windows + Git-Bash-only, Windows neither
WSL nor Git Bash), with the words `SAFETY INVARIANT` exactly once. The main
guard compares `realpathSync` of `process.argv[1]` and of the module, as
aai-live.mjs does.

Exports (pure unless noted): `etimeToSecs(et, nowSec)`, `parseConfig(env,
nowSec)`, `normalizeWorkspace(raw, platform)` (null for a root), `matches(cmd,
ws, platform)`, `decide(proc, cfg)`, `parsePosixSnapshot(text)`,
`parseWinSnapshot(text)`, `subtreePids(root, pairs)`, `selectCandidates(procs,
cfg, opts)`, `formatReport(candidates)`, `wslDelegationArgs(opts)`,
`run(deps)` (orchestration with injected `platform`, `env`, `list`, `tree`,
`kill`, `sleep`, `wsl`, `out`, `err`, `selfPid`, `parentPid`) and `main()`.
It contains these exact lines, each once, and no comment repeats an anchor:

```js
const TOKENS = ['vitest', 'esbuild'];
const DEFAULT_GRACE = 2;
const KILL_GRACE_MS = 1000;
const WSL_SENTINEL = 42;
const MAX_BUFFER = 64 * 1024 * 1024;
const PS_MATCH_ARGS = ['axo', 'pid=,etime=,args='];
const PS_TREE_ARGS = ['axo', 'pid=,ppid=,pgid='];
const WIN_LIST_SHELLS = ['powershell.exe', 'pwsh'];
const fold = platform === 'win32' ? (s) => s.toLowerCase() : (s) => s;
const skip = new Set([opts.selfPid, opts.parentPid]);
  if (now !== undefined && total >= now) return -1;
  return startSec < stepStart - grace;
  return ageSec >= minAge;
```

Decision semantics: a process is a candidate iff it is not skipped (R-9), its
command line holds a token (R-1) and the normalized workspace followed by an
allowed separator (R-2 to R-4), and its age decides REAP. POSIX age comes from
`etimeToSecs` (grammar, range guard and clamp of the sh copy, sentinel -1 for
anything else); win32 age and start come from the creation milliseconds (none:
sentinel, R-6). A sentinel is spared before either mode. Epoch mode (R-8):
reap iff `startSec < stepStart - grace`, where POSIX `startSec = snapNowSec -
ageSec` and win32 `startSec = creationMs / 1000`. Legacy mode: reap iff `ageSec
>= minAge`.

Output on every path that reaches a listing: exactly the four sh lines in
order, `reaped: N`, `reaped pids:` plus ` <pid>` per reaped pid, `reaped ages:`
plus ` <pid>=<age>`, `reaped raw:` plus ` <pipe-separator> <raw line>` per reaped
pid (the sh copy's separator character, a vertical bar), empty tails when N is
0. Exit 0 except R-16 and an internal error (exit 1).

### D2. Launchers

- `aai-reap-tests.sh`: at most 10 lines, ASCII, `#!/bin/sh`, POSIX only (no
  `[[`, no `BASH_SOURCE`; it runs under `sh` and `dash`), executable bit kept:

  ```sh
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-reap-tests.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    export AAI_REAP_WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"
    exec node "$MODULE" "$@"
  fi
  echo "aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped" >&2
  exit 1
  ```

  plus a comment line saying the logic and the safety contract live in
  aai-reap-tests.mjs (RFC-0017 phase 5) and one usage line. The callers' "see
  the script's header" pointer therefore lands on a header that names the
  module; no prompt is edited.
- `aai-reap-tests.ps1`: at most 12 lines, ASCII, no param block, the same
  pointer comment, the usage comment
  `# Usage: powershell -NoProfile -File .aai/scripts/aai-reap-tests.ps1`,
  `$Module = Join-Path $PSScriptRoot 'aai-reap-tests.mjs'`, `& node $Module;
  exit $LASTEXITCODE` when node and the module exist, else the R-16 line through
  `[Console]::Error.WriteLine` and `exit 1`.
- Neither launcher holds a token, `etime`, `taskkill`, `Get-CimInstance`,
  `wsl` or an age rule.

### D3. Existing tests: recorded adjustments and amendments

- `tests/skills/test-aai-run-tests.sh`: TEST-005, 006, 012, 013, 015, 016,
  017, 018, 021, 023 and 030 unchanged. TEST-019 reads the module instead of
  the sh file: no `lstart` in code, `AAI_REAP_STEP_START_EPOCH` present,
  `PS_MATCH_ARGS` names `etime=`, the snapshot second uses `Date.now()`.
  TEST-022 imports `etimeToSecs` from the module (`node --input-type=module`)
  and asserts the same cases with the same expected values. No sleep is added
  to this file (TEST-030 keeps seven tags).
- `tests/skills/test-aai-win-fallback.sh` TEST-009 greps the five matrix rows
  in the module instead of the sh file (the run-tests sh and TECHNOLOGY.md
  checks unchanged); `check_deps` keeps requiring the sh launcher.
- `tests/skills/aai-win-dispatch.Tests.ps1`: the Describe `aai-reap-tests.ps1`
  (24 cases) and the `$script:ReapDispatcher` variable are removed; their
  contracts move to TEST-3230 to TEST-3235 and TEST-3239. The total Pester
  discovery stays above the floor of 111.
- `tests/skills/test-aai-expert-fetch.sh` TEST-2624: `aai-reap-tests` leaves
  the phase 5 list (`["aai-run-tests", "autonomous-loop"]`).
- Five unsigned amendment records (`--signoff none`, the autopilot default; the
  owner's merge direction signs them), each `node .aai/scripts/spec-amend.mjs
  add --spec <spec> --ref node-first-reap-tests --class contract --signoff none
  --authority "intake node-first-reap-tests (owner menu answer 2026-11-02 '1 a
  3')" --what "<what>" --why "<one line>"`, filed under THIS ride's ref
  (merge-time binding signs only records of the merged ref):
  - SPEC-0046: what begins `TEST-006 and TEST-009 re-homed`.
  - SPEC-0064: what begins `TEST-004 and TEST-005 re-homed`.
  - SPEC-0083: what begins `TEST-022 re-homed`.
  - SPEC-0121: what begins `TEST-007, TEST-008 and TEST-009 re-homed`.
  - SPEC-0249: what begins `TEST-2624 drops aai-reap-tests`.

### D4. Wiring

- `.aai/system/PROFILES.yaml`: `.aai/scripts/aai-reap-tests.mjs` once in
  `core:` beside the two launchers (companion obligation for a new `.aai/**`
  file).
- `tests/skills/suite-map.yaml`: new row `aai-reap-tests` with globs
  `.aai/scripts/aai-reap-tests.*`, `tests/skills/test-aai-reap-tests.sh`,
  `tests/skills/lib/aai-reap-tests.test.mjs`,
  `tests/skills/aai-reap-tests.Tests.ps1`; rows `aai-run-tests` and
  `aai-win-fallback` gain `.aai/scripts/aai-reap-tests.mjs`.
- `.github/workflows/ps1-quality.yml`: the module added to the `push` and
  `pull_request` path lists, which stay identical (plus whatever
  test-aai-win-fallback.sh's derivation needs). No job, runner or step added.
- New suite `tests/skills/test-aai-reap-tests.sh` holding the `test_32xx`
  functions of the Test Plan, the node wrappers failing on zero passing tests.

### D5. RFC-0017 and documentation

- The inventory table drops the `aai-reap-tests` row; every other row stays
  byte for byte. After the small-pairs paragraph, one paragraph:
  `The [reaper slice](../issues/CHANGE-DRAFT-node-first-reap-tests.md) moved aai-reap-tests to a Node module (pair 787 to <N> lines).`
  where `<N>` is the `wc -l` sum of the module and both launchers at delivery.
- The phase 5 row's last sentence becomes: `The second slice moved the
  [test-process reaper](../issues/CHANGE-DRAFT-node-first-reap-tests.md) to one
  Node module with thin launchers; aai-run-tests and autonomous-loop are later
  slices.` Status stays `in progress`; frontmatter untouched. The allocator
  rewrites both links at merge; checks match only the suffix
  `node-first-reap-tests.md`.
- docs/TECHNOLOGY.md, paragraph "Reaper age guard": names
  `.aai/scripts/aai-reap-tests.mjs` behind both launchers, states that the
  Windows path compares real creation times in UTC milliseconds, and no longer
  names `Get-ReapCandidates` or `-StepStart`; the platform matrix rows are not
  edited.
- docs/USER_GUIDE.md item 3 of the leak-safe contract gains one sentence: the
  reaper runs on Node (`aai-reap-tests.mjs`) and without Node its launchers
  refuse with exit 1 and reap nothing.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(scripts): test-process reaper moves to Node`
  naming R-1 to R-6, R-10, R-12, R-16 and R-19.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 to Spec-AC-03 (logic in one module),
  Spec-AC-04 (launchers hold no copy) and Spec-AC-08 (no PowerShell reaper logic
  left).
- Intake AC-002 maps to Spec-AC-07 (pre-existing tests pass or carry recorded
  adjustments) and Spec-AC-06 locally, and to hosted check H1 (native Windows,
  both engines, and the WSL1 leg).
- Intake AC-003 maps to Spec-AC-01 to Spec-AC-03; every drift row has a named
  test: R-7, R-8, R-6, R-17 TEST-3230 and TEST-3231; R-1 to R-5 TEST-3232; R-9
  TEST-3233; R-10, R-11, R-13, R-18 TEST-3234; R-12, R-15 TEST-3235; R-14,
  R-16 TEST-3237 and TEST-3239; R-19 by inspection only (residual risk).
- Intake AC-004 maps to Spec-AC-05 (POSIX, real processes) and Spec-AC-06
  (PowerShell engines, real processes; Windows in H1).
- Intake AC-005 maps to Spec-AC-09.
- Intake AC-006 maps to Spec-AC-11; Spec-AC-10 keeps installs and CI selection
  right; Spec-AC-12 keeps the docs true.

## Constitution deviations

None. Article 4 (degrade and report): without Node each launcher prints a named
refusal and exits 1; a listing failure and a root workspace are reported on
stderr. Article 5 (additive first): the four report lines are additive on
Windows; R-4 and R-19 are the only scope widenings and are documented here and
in CHANGELOG. Article 2 (simplicity): no new environment variable, flag or
seam; the WSL delegation keeps its argv.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the module's pure functions run on fixtures the system SHALL map every valid etime form exactly and return -1 for an unparseable, out-of-range or impossible (at or above the snapshot second) etime; parse the three variables per R-7 and R-8; and decide REAP with the strict epoch rule and the inclusive legacy rule, sparing a sentinel age (also under minimum age 0) and a win32 process without a creation time in both modes (R-6). | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3230, TEST-3231 |
| Spec-AC-02 | WHEN matches and normalizeWorkspace run on fixtures the system SHALL apply R-1 to R-4 per platform, refuse a root workspace (R-5), treat glob characters literally, never match a prefix-sibling workspace, skip the module's own pid and parent pid (R-9), and return a matched pid plus all its descendants from a pid and ppid snapshot. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3232, TEST-3233 |
| Spec-AC-03 | WHEN run executes with injected dependencies the system SHALL on POSIX TERM a group leader's group or else the pid and its subtree, wait exactly 1000 ms once and KILL the same targets only when something matched; on win32 call taskkill with PID, T and F per candidate; print the four report lines in order on both; report a listing failure on stderr with four zero lines and exit 0 (R-13); and probe and delegate to WSL per R-12 and D-WSL with WSL_SENTINEL equal to the sentinel in aai-run-tests.ps1. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3234, TEST-3235 |
| Spec-AC-04 | The two launchers are thin: at most 10 and 12 lines, ASCII only, naming aai-reap-tests.mjs, holding none of vitest, esbuild, etime, taskkill, Get-CimInstance or wsl; the sh launcher has the sh shebang, no double-bracket test, the executable bit and the workspace export line; without node or without the module each prints exactly the R-16 line on stderr with empty stdout and exit 1 (sh launcher under sh and dash, ps1 launcher under pwsh); and the sh launcher with no AAI_REAP_WORKSPACE reaps a match carrying the logical path of a symlinked current directory. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3236, TEST-3237 |
| Spec-AC-05 | WHEN sh .aai/scripts/aai-reap-tests.sh runs in epoch mode with grace 0 against real Node sleepers the system SHALL kill the two pre-step in-workspace matches and their token-less children (one a group leader, one not), leave alive a sibling-workspace match, a prefix-sibling-workspace match and a post-step in-workspace match, and report exactly the two matched pids; the test then leaves no process whose command line holds its workspace root. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3238 |
| Spec-AC-06 | WHEN the new Pester file runs under the engine running it the system SHALL show through the ps1 launcher on real Node sleepers that a pre-step in-workspace match dies while a sibling-workspace match and a post-step match live, that a run from a pushed location without AAI_REAP_WORKSPACE reaps the in-workspace match, that a workspace name with a non-ASCII letter still matches, and that a launcher copy without the module gives the R-16 line and exit 1; Invoke-Pester reports no failure, no skip and at least 4 tests. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3239 |
| Spec-AC-07 | The pre-existing reaper tests pass on the changed tree: test-aai-run-tests.sh TEST-005, 006, 012, 013, 015, 016, 017, 018, 021, 023 and 030 unchanged, TEST-019 and TEST-022 adjusted to the module, test-aai-win-fallback.sh TEST-009 reading the module; spec-amend list shows five contract records of ref node-first-reap-tests for SPEC-0046, SPEC-0064, SPEC-0083, SPEC-0121 and SPEC-0249 regardless of owner_signoff. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3240, TEST-3241, TEST-3242 |
| Spec-AC-08 | Outside docs no tracked file names Get-ReapCandidates, Invoke-ReapNative, Invoke-ReapDispatch, Get-ReapWslDelegationArgs or Get-StepStartFromEpoch, aai-win-dispatch.Tests.ps1 has no aai-reap-tests Describe, and the module holds the words SAFETY INVARIANT exactly once while neither launcher holds them. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3243 |
| Spec-AC-09 | WHEN aai-sync installs the core profile into a target whose path holds a space the system SHALL place the module and both launchers there, the target's sh launcher SHALL reap an aged matched sleeper in a workspace under the target (reaped: 1, process gone) and the target's ps1 launcher under pwsh SHALL print reaped: 0 with exit 0 on an empty workspace. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3244 |
| Spec-AC-10 | The module is classified once in the core PROFILES list, select-suites maps the module and the three new test files to aai-reap-tests and the module also to aai-run-tests and aai-win-fallback without a FULL_RUN line, and the two ps1-quality path lists name the module and stay identical. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3245, TEST-3246, TEST-3247 |
| Spec-AC-11 | The wc -l sum of the module and both launchers is at most 345 (787 before) and equals the number in the RFC-0017 slice paragraph; the RFC inventory equals the pair set of the tree (TEST-2624 exits 0) without an aai-reap-tests row, TEST-2623 still exits 0, and the phase 5 row and the slice paragraph each link a document ending node-first-reap-tests.md. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3248, TEST-3249 |
| Spec-AC-12 | docs/TECHNOLOGY.md's reaper paragraph names aai-reap-tests.mjs and neither Get-ReapCandidates nor -StepStart, and docs/USER_GUIDE.md states that without Node the reaper's launchers refuse with exit 1. | done | docs/ai/tdd/node-first-reap-tests/green/green-suite.log | - | TEST-3250 |

## Implementation plan

1. RED: write `tests/skills/lib/aai-reap-tests.test.mjs`,
   `tests/skills/aai-reap-tests.Tests.ps1` and `tests/skills/test-aai-reap-tests.sh`;
   run each row's function alone on the unchanged tree and store the output
   under `docs/ai/tdd/node-first-reap-tests/red/`. TEST-3240 is green on the
   baseline (its RED is the mutation record).
2. Write the module (D1): TEST-3230 to TEST-3235 go green.
3. Replace both scripts with launchers (D2): TEST-3236 to TEST-3239 go green;
   run TEST-3240 (the unchanged real-process reaper cases) on the new tree.
4. Adjust TEST-019, TEST-022, win-fallback TEST-009, TEST-2624, remove the
   dispatch Describe, append the five amendment records (D3): TEST-3241 to
   TEST-3243.
5. Wiring, RFC and docs (D4, D5): TEST-3244 to TEST-3250.
6. Mutation records per row, then the Verification list.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3230 | Spec-AC-01 | unit | tests/skills/test-aai-reap-tests.sh | test_3230_etime runs node --test --test-name-pattern TEST-3230 on tests/skills/lib/aai-reap-tests.test.mjs: 00:00 is 0, 00:03 is 3, 01:00 is 60, 1-00:00:00 is 86400, 01:02:03 is 3723; the empty string, vitest_fresh18, worker, abc:def, 1.2.3, a path, 99:99, 77 and 38109073018720 give -1; 441077234-00:18:40 gives 38109073018720 without a snapshot second and -1 with 1753000000; 10-00:00:00 gives 864000 with it; the wrapper fails on zero passing tests | `sed:s/if \(now !== undefined && total >= now\) return -1;/if (false) return -1;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3231 | Spec-AC-01 | unit | tests/skills/test-aai-reap-tests.sh | test_3231_config_and_decide runs the TEST-3231 node cases: parseConfig gives legacy mode for an unset, empty, abc, -5, 0, future and 21-digit epoch and epoch mode 12 for 00012; minimum age 0 by default, 10 for 010, 0 for 5 plus newline, a 20-digit value kept; grace 2 by default and for abc, 0 for 0; decide in epoch mode with stepStart 1000 and grace 2 spares startSec 998 and reaps 997, in legacy mode with minimum age 5 reaps age 5 and spares 4, spares age -1 under minimum age 0, and spares a win32 process with a null creation time in both modes | `sed:s/return startSec < stepStart - grace;/return startSec <= stepStart - grace;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3232 | Spec-AC-02 | unit | tests/skills/test-aai-reap-tests.sh | test_3232_matching runs the TEST-3232 node cases: on linux and darwin VITEST and Vitest do not match, /WS/A does not match workspace /ws/a, a backslash after the workspace does not match, workspace /ws/a// matches /ws/a/x, /ws/a-fork/x does not match, a workspace holding a star matches only literally; on win32 VITEST matches, C:\WS\A\x matches workspace c:\ws\a, a forward slash after it matches; normalizeWorkspace returns null for /, for the empty string, for C:\ and for C: on win32 | `sed:s/platform === 'win32' \? \(s\) => s\.toLowerCase\(\) : \(s\) => s;/platform === 'never' ? (s) => s.toLowerCase() : (s) => s;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3233 | Spec-AC-02 | unit | tests/skills/test-aai-reap-tests.sh | test_3233_snapshot_and_tree runs the TEST-3233 node cases: parsePosixSnapshot keeps the verbatim line with leading spaces and gives -1 age for a line whose etime column holds an argv word; parseWinSnapshot reads id, parent, creation milliseconds (empty gives null) and a command line holding spaces; selectCandidates skips selfPid and parentPid even when they match; subtreePids returns the root and its grandchildren and nothing from another branch | `sed:s/const skip = new Set\(\[opts\.selfPid, opts\.parentPid\]\);/const skip = new Set([]);/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3234 | Spec-AC-03 | unit | tests/skills/test-aai-reap-tests.sh | test_3234_run_posix runs the TEST-3234 node cases on run with platform linux and injected list, tree, kill, sleep and out: a group-leader match gets SIGTERM to the negative pgid, a non-leader match gets SIGTERM to itself and its two descendants, sleep is called once with 1000, then SIGKILL hits the same targets; with no match neither sleep nor kill is called; the four lines equal the sh format for both cases; a list that throws gives the four zero lines, one stderr line starting aai-reap-tests: process listing failed and exit 0; a root workspace gives the refusal line, no list call and four zero lines | `sed:s/const KILL_GRACE_MS = 1000;/const KILL_GRACE_MS = 0;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3235 | Spec-AC-03 | unit | tests/skills/test-aai-reap-tests.sh | test_3235_run_win32 runs the TEST-3235 node cases on run with platform win32: one aged in-workspace match, one sibling, one young and one with no creation time give one taskkill call with PID, the pid, T and F and the four lines; the WSL probe is called with -e sh -c exit 42 and only exit 42 counts as usable (0 and a timeout do not); wslDelegationArgs equals the two argv lists the retired Pester cases pinned (with and without a step-start epoch); delegate stdout holding reaped: 2 is printed verbatim and no native summary follows; a delegate exiting 1 without a reaped line gives the native four lines and the stderr note; WSL_SENTINEL equals the integer of the sentinel assignment in .aai/scripts/aai-run-tests.ps1 | `sed:s/const WSL_SENTINEL = 42;/const WSL_SENTINEL = 0;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3236 | Spec-AC-04 | inspection | tests/skills/test-aai-reap-tests.sh | test_3236_launchers_thin checks both launchers: no byte above 0x7E, at most 10 and 12 lines, a reference to aai-reap-tests.mjs, none of the tokens vitest, esbuild, etime, taskkill, Get-CimInstance, wsl, the R-16 line exactly once; the sh file starts with the sh shebang, has no double bracket after comments are stripped, is executable and holds the export line of D2 | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" "$@" # vitest/` on .aai/scripts/aai-reap-tests.sh | green |
| TEST-3237 | Spec-AC-04 | integration | tests/skills/test-aai-reap-tests.sh | test_3237_launcher_refusal_and_pwd runs the sh launcher under sh and under dash and the ps1 launcher under pwsh -File with PATH holding only a directory of symlinks to sh, dash, dirname and pwsh (positive control: command -v node fails there) and from a copy without the module: each prints exactly the R-16 line on stderr, nothing on stdout, exit 1; then from a symlinked directory entered by its logical path, with AAI_REAP_WORKSPACE unset and AAI_REAP_MIN_AGE_SECS 0, the sh launcher reaps a sleeper whose command line holds the logical path (reaped: 1, process gone) | `sed:s/nothing was reaped/nothing reaped/` on .aai/scripts/aai-reap-tests.ps1 | green |
| TEST-3238 | Spec-AC-05 | integration | tests/skills/test-aai-reap-tests.sh | test_3238_real_posix_safety runs the TEST-3238 node case: in a fresh mkdtemp root it starts a detached in-workspace sleeper with a token-less child, a non-detached one with a token-less child, a sibling-workspace sleeper and a ws-fork sleeper, waits 4 s, takes the step-start second, starts a post-step in-workspace sleeper, runs sh .aai/scripts/aai-reap-tests.sh with AAI_REAP_STEP_START_EPOCH and AAI_REAP_GRACE_SECS 0; within 5 s both matched parents and both children are gone, the three spared sleepers are alive, reaped pids lists exactly the two parents; after() kills every recorded pid by pid and a ps scan finds no command line holding the root | `sed:s/const TOKENS = \['vitest', 'esbuild'\];/const TOKENS = ['vitestx', 'esbuild'];/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3239 | Spec-AC-06 | integration | tests/skills/test-aai-reap-tests.sh | test_3239_pester_reap runs Invoke-Pester on tests/skills/aai-reap-tests.Tests.ps1 with PassThru under pwsh and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 4; the cases launch the ps1 launcher with the engine running the test on real Node sleepers with grace 0 and a step-start epoch taken 4 s after the old sleeper: old in-workspace dies, sibling and post-step live; from Push-Location into the workspace without AAI_REAP_WORKSPACE the match dies; a workspace named with an e-acute letter matches; a launcher copy without the module gives the R-16 line and exit 1; AfterEach stops every recorded pid by id | `sed:s/const MAX_BUFFER = 64 \* 1024 \* 1024;/const MAX_BUFFER = 64;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3240 | Spec-AC-07 | integration | tests/skills/test-aai-reap-tests.sh | test_3240_existing_reaper_cases runs bash tests/skills/test-aai-run-tests.sh 005 006 012 013 015 016 017 018 021 023 030 (exit 0, the real-process reaper cases through the sh launcher, TEST-030 still seven AGE-WAIT tags) | `sed:s/const DEFAULT_GRACE = 2;/const DEFAULT_GRACE = 0;/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3241 | Spec-AC-07 | integration | tests/skills/test-aai-reap-tests.sh | test_3241_adjusted_cases runs bash tests/skills/test-aai-run-tests.sh 019 022 and bash tests/skills/test-aai-win-fallback.sh 009 (each exit 0) and requires the TEST-019 and TEST-022 functions and win-fallback TEST-009 to name aai-reap-tests.mjs | `sed:s/const PS_MATCH_ARGS = \['axo', 'pid=,etime=,args='\];/const PS_MATCH_ARGS = ['axo', 'pid=,lstart=,args='];/` on .aai/scripts/aai-reap-tests.mjs | green |
| TEST-3242 | Spec-AC-07 | inspection | tests/skills/test-aai-reap-tests.sh | test_3242_amendment_records runs node .aai/scripts/spec-amend.mjs list --json and requires contract records of ref node-first-reap-tests whose spec paths name SPEC-0046, SPEC-0064, SPEC-0083, SPEC-0121 and SPEC-0249, each what beginning with the D3 text, regardless of owner_signoff | `sed:s/"ref_id":"node-first-reap-tests","spec":"docs/"ref_id":"node-first-reap-tests","spec":"gone/` on docs/ai/decisions.jsonl | green |
| TEST-3243 | Spec-AC-08 | inspection | tests/skills/test-aai-reap-tests.sh | test_3243_no_ps_reaper_logic runs git ls-files outside docs/ and requires no file naming Get-ReapCandidates, Invoke-ReapNative, Invoke-ReapDispatch, Get-ReapWslDelegationArgs or Get-StepStartFromEpoch; no Describe aai-reap-tests in aai-win-dispatch.Tests.ps1; SAFETY INVARIANT exactly once in the module and absent from both launchers; positive control: a fixture file list with one extra naming file is reported | `sed:s/# Usage: powershell/# Get-ReapCandidates usage: powershell/` on .aai/scripts/aai-reap-tests.ps1 | green |
| TEST-3244 | Spec-AC-09 | e2e | tests/skills/test-aai-reap-tests.sh | test_3244_downstream_core_sync runs .aai/scripts/aai-sync.sh --profile core into TEST_DIR/target with space, requires the module and both launchers there, starts a sleeper whose command line holds vitest and a workspace under the target, waits 2 s, runs the target's sh launcher with that workspace and minimum age 1 (exit 0, reaped: 1, sleeper gone within 5 s), then pwsh -File on the target's ps1 launcher with an empty workspace (exit 0, reaped: 0); every sleeper killed by pid at the end | `sed:s/\/aai-reap-tests\.mjs"/\/aai-reap-tests-gone.mjs"/` on .aai/scripts/aai-reap-tests.sh | green |
| TEST-3245 | Spec-AC-10 | inspection | tests/skills/test-aai-reap-tests.sh | test_3245_profiles_core requires .aai/scripts/aai-reap-tests.mjs exactly once in PROFILES.yaml, inside the core list (the whole-tree classification check stays with test-aai-layer-profiles.sh in Verification) | `sed:s/aai-reap-tests\.mjs/aai-reap-tests-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3246 | Spec-AC-10 | integration | tests/skills/test-aai-reap-tests.sh | test_3246_suite_map_selects feeds each path to node .aai/scripts/select-suites.mjs --files-from - : the module selects aai-reap-tests, aai-run-tests and aai-win-fallback; the three new test files select aai-reap-tests; no output holds a FULL_RUN line | `sed:s/aai-reap-tests\.mjs/aai-reap-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-3247 | Spec-AC-10 | inspection | tests/skills/test-aai-reap-tests.sh | test_3247_ps1_quality_paths extracts the push and pull_request path lists of .github/workflows/ps1-quality.yml and requires both to name .aai/scripts/aai-reap-tests.mjs and to be identical | `sed:s/aai-reap-tests\.mjs/aai-reap-gone.mjs/` on .github/workflows/ps1-quality.yml | green |
| TEST-3248 | Spec-AC-11 | inspection | tests/skills/test-aai-reap-tests.sh | test_3248_line_budget parses pair 787 to N lines from the RFC-0017 slice paragraph and requires N to equal the live wc -l sum of the module and both launchers and to be at most 345 | `sed:s/pair 787 to (\d+) lines/pair 787 to 1$1 lines/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3249 | Spec-AC-11 | inspection | tests/skills/test-aai-reap-tests.sh | test_3249_rfc_inventory runs bash tests/skills/test-aai-expert-fetch.sh test_2624_inventory_matches_tree and test_2623_rfc_phase3_done (each exit 0), then requires no inventory row for aai-reap-tests, a phase 5 row linking a document ending node-first-reap-tests.md and a paragraph after the table with such a link | `sed:s/node-first-reap-tests\.md\)/node-first-gone.md)/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3250 | Spec-AC-12 | inspection | tests/skills/test-aai-reap-tests.sh | test_3250_docs_true requires the Reaper age guard paragraph of docs/TECHNOLOGY.md to name aai-reap-tests.mjs and to name neither Get-ReapCandidates nor -StepStart, and docs/USER_GUIDE.md to hold a sentence naming aai-reap-tests.mjs and exit 1 | `sed:s/aai-reap-tests\.mjs/aai-reap-gone.mjs/` on docs/TECHNOLOGY.md | green |

Test counts by type: unit 6, integration 7, inspection 7, e2e 1 (21).

Seams crossed (Principle 2): sh launcher to module to `ps` and real signals
(TEST-3237, TEST-3238, TEST-3240); ps1 launcher under the engine running the
test to module to the platform listing and kill (TEST-3239; Windows CIM and
`taskkill` in H1); the module to the sentinel in aai-run-tests.ps1 (TEST-3235);
aai-sync install to the target's own launchers (TEST-3244); the RFC inventory
read by SPEC-0249's checks (TEST-3249); select-suites reading the suite map
(TEST-3246); the amendment ledger read by spec-amend (TEST-3242). The WSL
delegate on a real distro with and without Node is a seam only H1's WSL1 leg
crosses (without Node there).

### RED observations and positive controls

- TEST-3230 to TEST-3235: RED on the baseline, the module does not exist; the
  wrapper's zero-passing-tests guard makes a missing name RED.
- TEST-3236: RED on the baseline (the current scripts are 368 and 419 lines
  and hold the tokens). TEST-3237: RED on the baseline (no refusal line; the sh
  copy needs no node and prints `reaped: 0`).
- TEST-3238: passes against the baseline sh copy (the run is stored under
  `red/` as the proof that its assertions encode the old behavior); its RED is
  the mutation record.
- TEST-3239: RED on the baseline (the old ps1 runs `Get-CimInstance`, absent
  on macOS and Linux, and prints no refusal line).
- TEST-3240: passes on the baseline; its RED is the mutation record.
- TEST-3241: RED on the baseline (the adjusted functions name the module,
  which does not exist). TEST-3242: RED (no records).
- TEST-3243: RED on the baseline (the ps1 and the dispatch Describe hold the
  names; no module).
- TEST-3244 to TEST-3250: RED on the baseline (module, entries, rows,
  paragraphs absent; the inventory still lists the pair).

## Verification

- New suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-reap-tests.sh` exits 0.
- Run-tests suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh` exits 0 (all 30 cases).
- Windows fallback pins: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` exits 0.
- Expert-fetch (inventory and phase 3 checks): `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-expert-fetch.sh` exits 0.
- Layer profiles, suite selection, hygiene pack:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`
  for test-aai-layer-profiles, test-aai-suite-select and test-aai-hygiene-pack,
  each exit 0.
- Direct Node tests: `node --test tests/skills/lib/aai-reap-tests.test.mjs` exits 0 under local Node 22.
- PowerShell gate: `bash tests/skills/test-ps1-quality.sh` exits 0 locally (PSScriptAnalyzer and full Pester discovery, TotalCount at least 111, SkippedCount 0).
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records per row with `node .aai/scripts/mutation-run.mjs`, then `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- After every local run: `ps axo pid=,args=` shows no command line holding a
  test workspace root of this suite (no leaked sleeper).
- No full sweep while the reuse-for-docs-reading-suites ride runs one (intake
  constraint).

### Hosted delivery checks (after PR creation, before merge-readiness)

Not Spec-ACs and not claimed by local Validation; Windows parity (intake
AC-002) is proven only here.

- H1: on the PR head the ps1-quality run concludes success for `gate`,
  `windows-5_1` and `windows-wsl1`. In both Pester discovery steps of
  `windows-5_1` (Windows PowerShell 5.1 and pwsh 7) and in the WSL1 leg's 5.1
  step, every case of aai-reap-tests.Tests.ps1 is listed passed (on Windows the
  listing is CIM and the kill is `taskkill`; on the WSL1 leg the WSL half runs
  and, with no Node in that distro, the native summary is printed), and the
  skipped count still equals `AAI_EXPECTED_WIN_SKIP_COUNT` (4). A hosted-only
  failure is diagnosed with a probe (the listing script's raw output in hex,
  the arguments Node received, `$LASTEXITCODE`) before any code change, and the
  change is recorded as an amendment.
- H2: the skill-suite run concludes success with `aai-reap-tests`,
  `aai-run-tests` and `aai-win-fallback` selected or a full run, and the Node 22
  compatibility step passing. A reaper failure there on a known flake signature
  (TEST-018 legacy direction, TEST-006, 015, 016 epoch direction) is re-run
  once; the same failure twice, or a failure in TEST-3238 or TEST-3239, is a
  finding with its `reaped ages:` and `reaped raw:` lines read first.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/node-first-reap-tests/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the Verification
list. H1 and H2 are recorded separately after PR creation. Planning's
measurements above are inputs, not attestations.

## Risks and rollback

- Process supervision: a bug kills the wrong processes. Mitigations: every
  scope decision is a pure function with unit cases (TEST-3230 to TEST-3233),
  real-process cases on both sides of every guard (TEST-3238, TEST-3239,
  TEST-3240), and the fixtures follow D-CLEAN.
- Windows listing and kill (CIM through `powershell.exe`, `taskkill`, UTF-8
  output, a non-ASCII workspace) are proven only on the hosted Windows jobs
  (H1); a local host cannot run them.
- R-19 (the sh launcher under Git Bash now does the native Windows pass) is
  checked by inspection only; no job runs the sh launcher from Git Bash.
- R-12: the WSL half now needs Node inside the distro. A distro without Node
  cannot host a `vitest` process; a stand-alone `esbuild` binary leaked inside
  such a distro would no longer be reaped by the WSL half (residual, recorded).
  The pre-existing Windows-path scoping of the WSL half is unchanged and filed
  as a follow-up.
- Reaper tests flake under CI load (known); H2 states the re-run rule and when
  a failure is a finding.
- The five amendments are recorded unsigned (`--signoff none`, the autopilot
  default) citing the owner's intake answer; the canon assigns the sign-off to
  the owner, whose merge direction signs them (records filed under this ride's
  ref).
- SPEC-0249 TEST-2624's stored mutation record names the `validate-skills`
  and other rows, not `aai-reap-tests`; it stays valid evidence for that
  closed spec.
- Changing a shipped core script pair is consumer-visible: merge stays with
  the owner.
- Rollback is one revert of the scope's files plus the amendment records'
  disclosure.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list` (282 open) holds no item on
aai-reap-tests, the reaper's guards or the remaining-pairs inventory. Related
but left open: `fu-msys-reap-fallback-foreign-pid` and
`fu-msys-direct-run-misses-exec-grandkids` (both in aai-run-tests.sh, a later
slice), `fu-mutation-gate-skips-pester` (TEST-3239's mutation runs through its
bash wrapper, which does not close the class), `fu-ps1-quality-outside-sweep-glob`
(test-ps1-quality.sh still runs only in Verification and H1). To be filed at
delivery: the WSL half's Windows-path scoping (Drift, observed and left alone).

Registry items closed by this scope: none.
