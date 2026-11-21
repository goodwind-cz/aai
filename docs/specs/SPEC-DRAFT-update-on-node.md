---
id: spec-update-on-node
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 94de2aabeeb68df66eb36000b4d33cca92b47ae08be65ed654435646fdcad7ce
ceremony_level: 2
links:
  requirement: update-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run the AAI layer updater as one Node module behind thin launchers

SPEC-FROZEN: true

## Links

- Requirement: [Run the AAI layer updater as one Node module behind thin launchers](../issues/CHANGE-DRAFT-update-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 10 (owner sign-off: yes; merge by the owner). Plan section 4 decision 1
  applies: Node is a hard prerequisite on the install and update path;
  launchers refuse without Node and print an install hint.
- Structural template: [SPEC-0306](SPEC-0306-spec-bootstrap-on-node.md)
  (ride 9: one module, frozen reference copy with a sha256 pin, differential
  corpus, launchers, Pester, scratch install, the parity harness's module
  twin, wiring named up front). Earlier precedents:
  [SPEC-0267](SPEC-0267-spec-node-first-reap-tests.md) (reaper launchers),
  [SPEC-0284](SPEC-0284-spec-install-path-parity-harness.md) (the parity
  harness this ride extends).
- Specs whose tests this ride re-homes (D-REHOME): SPEC-0052
  (`spec-aai-update-temp-toctou`), SPEC-0124
  (`spec-update-doctor-field-report`), SPEC-0285
  (`spec-update-ps1-git-stderr`), SPEC-0284
  (`spec-install-path-parity-harness`), SPEC-0020
  (`spec-doctor-vendored-layer-drift`), SPEC-0179
  (`spec-test-framework-sweep`).
- Shared code read but not changed: `.aai/scripts/aai-sync.sh`,
  `.aai/scripts/aai-sync.ps1` (the module still runs the source checkout's
  sync twin; porting the sync is ride 12), `.aai/scripts/update-doctor-report.mjs`,
  `.aai/scripts/update-check.mjs` (keeps spawning `aai-update.sh` or
  `aai-update.ps1`; it needs no change).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 compatible suites, Pester 5, Windows PowerShell 5.1 and pwsh 7).
- Baseline: main `30c983ef`.

## Implementation strategy

- Strategy: tdd
- Rationale: owner requirement for every Node-first ride: TDD in runs of
  about three Spec-ACs. The port replaces two drifting twins whose rules were
  only ever covered end to end; every rule test is RED before the module
  exists, the two differential corpora stay RED until the last byte matches
  each reference (or the named DR rewrite), and every Test Plan row carries a
  mutation (mutation_gate v1). Wiring rows are inspection tests, still seen
  RED first because the rows, pins and entries they check are absent on the
  baseline.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: a new module, two launchers, two frozen reference
  copies, re-homed assertions in six existing suites, the parity driver, CI
  path filters and PROFILES; the main checkout is shared with other sessions
  and holds unrelated uncommitted files.
- User decision: worktree (owner-directed own worktree, recorded in STATE)
- Base ref: main
- Worktree branch/path: feat/update-on-node at /Users/ales/Projects/aai-worktrees/update-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/aai-update.mjs .aai/scripts/aai-update.sh .aai/scripts/aai-update.ps1
  .aai/system/PROFILES.yaml .aai/SKILL_UPDATE.prompt.md
  tests/fixtures/aai-update-reference/aai-update.sh tests/fixtures/aai-update-reference/aai-update.ps1
  tests/skills/lib/update-reference.mjs tests/skills/lib/aai-update.test.mjs
  tests/skills/lib/aai-update-fixtures.mjs tests/skills/test-aai-update-node.sh
  tests/skills/test-aai-update.sh tests/skills/aai-update.Tests.ps1
  tests/skills/test-aai-layer-drift.sh tests/skills/test-aai-hygiene-pack.sh
  tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity.test.mjs
  tests/skills/lib/install-parity-allowlist.tsv
  tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
  tests/skills/test-aai-pr-preflight.sh tests/skills/test-aai-suite-reuse.sh
  tests/skills/suite-map.yaml tests/skills/suite-weights.tsv
  tests/skills/lib/cd-subshell-leak-baseline.tsv .github/workflows/ps1-quality.yml
  CHANGELOG.md docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-DRAFT-update-on-node.md
  docs/specs/SPEC-DRAFT-update-on-node.md docs/INDEX.md
  (decisions.jsonl only for the amendment and follow-up records; the
  allocator renames the two DRAFT files at merge; `aai-update-fixtures.mjs`
  only if the corpus fixtures are split out of the test file.)
- Code review required: true.

## Ceremony

- Level 2: production scripts, tests, one CI workflow path filter, one
  prompt and docs; no file in `protected_paths_l3` (docs/ai/docs-audit.yaml)
  is touched.
- Suite selection: the wiring files select many suites; Validation runs the
  selected suites between runs and the full sweep once before close
  (`AAI_TEST_TIMEOUT=3000`).
- One PR. The size is comparable to ride 9 (one module of about 400 lines,
  one node:test file, one new suite, edits to six suites); no split is
  proposed. If run 4 (the corpora) cannot close inside the ride, D-SLICES
  names the fallback.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2.57, Node 22.23.1, pwsh
7.6.3) on 2026-11-21 at `30c983ef`, scratch fixtures under the session
scratchpad. One run each; they size the work, they are not thresholds.

- `.aai/scripts/aai-update.sh`: 180 lines, 122 code lines
  (`grep -cvE '^[[:space:]]*(#|$)'`), mode 100755, git blob
  `6922cbbff62687fe45fca816b0236b1f10928c3c`, sha256
  `5f5cb9eedd6b1453d57afc0a2b8d09c7804ce7d7086b9b754a6d13d5c21110d5`.
- `.aai/scripts/aai-update.ps1`: 212 lines, 151 code lines, mode 100644,
  git blob `3d4134e919ff916d12c08a3da1dd971802471444`, sha256
  `136c3d35a6f35385ad4d9b6b00989d37a557622e8a4b5a925b1b7b17867e9dd4`.
  Both are LF in index and work tree (`*.sh` and `*.ps1` carry
  `text eol=lf`).
- Bash twin argument handling: `-h` prints the comment block of lines 2 to
  16 (15 lines, first line `AAI layer updater — one deterministic command
  for /aai-update.`) and exits 0; `--bogus` prints `Unknown argument:
  --bogus` to stderr, the usage to stdout and exits 1; `--repo` with no value
  and `--ref ''` print `<relocated copy>: line 48: 2: --repo needs a value`
  and exit 0 (the EXIT trap's last status wins under bash 3.2), doing
  nothing else.
- PowerShell twin: `-h` is WARN-ignored and the run proceeds (with
  `-DryRun` it printed the plan); `--repo` with no value keeps the default
  slug; an unknown argument prints `WARN: ignoring unrecognized argument
  '<arg>'` and continues with exit 0.
- Without a param block, `pwsh -File <launcher> -Repo 'a b' -Ref main -DryRun
  -Force -KeepTemp --repo=x/y -h --bogus -Repo:z` hands the launcher's
  `$args` exactly `-Repo`, `a b`, `-Ref`, `main`, `-DryRun`, `-Force`,
  `-KeepTemp`, `--repo=x/y`, `-h`, `--bogus`, `-Repo`, `z` (the colon form
  is split by pwsh), and `& node $Module @args` passes them unchanged;
  `(Get-Process -Id $PID).Path` names the running engine
  (`.../libexec/pwsh`). `pwsh -NoProfile -ExecutionPolicy Bypass` exits 0 on
  macOS.
- Dry-run with `--repo acme/foo --ref dev`: both twins print `- Upstream:
  https://github.com/acme/foo.git@dev`; the bash `Would run` line is
  `- Would run: <source>/.aai/scripts/aai-sync.sh "<target>"`, the
  PowerShell one `- Would run: SOURCE/.aai/scripts/aai-sync.ps1 -TargetRoot
  "<target>"`; headers differ by `—` against `-`.
- Canonical guard: a target origin `git@github.com:Goodwind-CZ/AAI.git` is
  refused by the bash twin (exit 2); `https://GITHUB.COM/goodwind-cz/aai.GIT`
  is not refused by the bash twin (exit 0) and is refused by the PowerShell
  twin (exit 2).
- The bash twin leaves no file in `TMPDIR` after `-h`, a usage error or a
  dry-run (the relocated copy is removed by its trap).
- Parity harness, scenarios UP-01 to UP-03, twins sh and ps1 (37.9 s; UP-01
  15 s, UP-02 7.9 s, UP-03 14.2 s): every divergence is a sync divergence
  covered by an existing row: `pin-template-version-spacing`,
  `pin-synced-at-precision`, `conflict-report-name-local-time`,
  `conflict-report-generated-precision`,
  `conflict-report-next-step-backticks`, `session-start-exec-bit` on all
  three, and `gitignore-block-order` and `gitignore-block-headers` on UP-02
  only. On a smoke run only UP-01 executes, so a row widened to a new pair
  for UP-02's `.gitignore` divergence would be judged stale there.
- `.aai/scripts/*.sh` and `.aai/scripts/lib/*.sh` holding `pipefail`: 6
  (aai-sync.sh, aai-update.sh, claude-hook-gate.sh,
  install-pre-commit-hook.sh, pre-commit-checks.sh, lib/repo-tripwire.sh);
  hygiene test_128's vacuity guard requires more than 5.
- Callers and pins of `aai-update.sh` or `.ps1` outside docs history:
  `SKILL_UPDATE.prompt.md`, PROFILES core, `update-check.mjs` (spawns the
  `.sh` on POSIX with `bash`, the `.ps1` on Windows with pwsh or
  powershell.exe), `ps1-quality.yml` path lists, suite-map rows
  `aai-install-parity`, `aai-layer-drift`, `aai-update-check`, `aai-update`,
  `aai-project-config`, `cd-subshell-leak-baseline.tsv` (1 for the `.sh`,
  18 for test-aai-update.sh), `install-parity.mjs` and its unit test, and
  behaviour or source-shape pins in `test-aai-update.sh`,
  `aai-update.Tests.ps1`, `test-aai-layer-drift.sh` (TEST-010b),
  `test-aai-update-check.sh` (runs the real `.sh`, stubs it elsewhere),
  `test-aai-install-parity.sh`, `test-aai-win-fallback.sh` (TEST-017 skip
  count), `test-aai-hygiene-pack.sh` (test_128 count).
- `tests/skills/suite-map.yaml` holds 138 rows (hygiene test_090 pins 138);
  the highest Test Plan id in the 3000 range is TEST-3959.
- CI: `skill-suite.yml` runs on ubuntu-latest with `fetch-depth: 0` and has
  pwsh (its release job uses `shell: pwsh`); `ps1-quality.yml` checks out
  at depth 1; its full-suite Pester steps carry `AAI_EXPECTED_WIN_SKIP_COUNT:
  "4"` and a TotalCount floor of 111; `windows-parity` runs the smoke matrix
  with the default twins and `--bash` set to Git for Windows' bash.

## Decisions

### D-MODULE. `.aai/scripts/aai-update.mjs`

Dependency-free ESM, Node 22 compatible, imports only `node:` specifiers
and none of `node:http`, `node:https`, `node:net`, `node:tls`, `node:dgram`,
ASCII only (non-ASCII output characters are written as `\u` escapes), no side
effect on import (the main guard compares `realpathSync` of
`process.argv[1]` and of the module), never reads standard input, never
touches `process.stdout` or `process.stderr` (all output goes through
`fs.writeSync` on descriptors 1 and 2, so its lines and the lines of the
children it starts with inherited stdio appear in program order on every
host, macOS pipes included). It holds all update policy: arguments, the
base directory, the canonical-repo guard, source resolution and the clone
chain, temp lifecycle, the sync runner, the dry-run plan, post-sync
evidence, the doctor field report postamble, the next-steps block and the
exit code. Every child process goes through one injectable seam
(`io.spawn`, default `runChild`).

Exports at least: `parseArgs`, `resolveBase`, `normSlug`,
`canonicalGuard`, `cloneUrl`, `resolveSource`, `resolveRunner`,
`syncCommand`, `renderDryRun`, `changedFiles`, `pinLines`,
`latestConflict`, `renderEvidence`, `doctorReport`, `renderNext`,
`createOwnTemp`, `removeOwnTemp`, `run`, `main`. `run(argv, io)` takes
injectable `out`, `err`, `env`, `cwd`, `spawn`, `tmpdir` and `platform`.

It contains these exact lines, each once, and no comment repeats one (the
Test Plan mutations rely on them):

```js
const DEFAULT_REPO = 'goodwind-cz/aai';
const DEFAULT_REF = 'main';
const EXIT_USAGE = 1;
const EXIT_REFUSED = 2;
const EXIT_FETCH = 3;
const EXIT_MALFORMED = 4;
const TMP_PREFIX = 'aai-src.';
const SRC_SUBDIR = 'src';
const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER';
const SLUG_CASE_FLAGS = 'i';
const PIN_KEYWORDS = ['source', 'version', 'commit', 'canonical', 'ref'];
const ANON_CLONE = ['-c', 'credential.helper=', '-c', 'http.https://github.com/.extraheader='];
const HELPER_REL = '.aai/scripts/update-doctor-report.mjs';
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };
  if (!state.keepTemp && state.tmp) removeOwnTemp(state.tmp, state.created);
export function doctorReport(
```

`doctorReport` is the doctor postamble region: it runs from its
`export function doctorReport(` line to the next line starting
`export function ` (D-REHOME reads this region). Each output string of the
DR table and of D-EVIDENCE occurs once in the module.

### D-CLI. Arguments, help, base directory (DR-1 to DR-4, DR-21)

- Arguments are read left to right; a later occurrence of a setting wins.
  Accepted on every entry point: `--repo <v>`, `--ref <v>`, `--repo=<v>`,
  `--ref=<v>`, `--dry-run`, `--keep-temp`, `--force`, `-h`, `--help`
  (case-sensitive), and the PowerShell names `-Repo <v>`, `-Ref <v>`,
  `-DryRun`, `-KeepTemp`, `-Force` (matched case-insensitively, exact names
  only, no abbreviation). A value flag at the end, or with an empty value,
  prints `aai-update: <flag as given> needs a value` to stderr and exits 1
  (DR-3). `-h` or `--help` prints the help text to stdout and exits 0 at that
  position (DR-1). Any other argument prints `Unknown argument: <arg>` to
  stderr and the help text to stdout and exits 1 at that position (DR-2, the
  bash streams kept). Nothing else is started before arguments are fully
  read.
- Help text (DR-1): the bash reference's 15 help lines byte for byte,
  followed by
  `  powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force]   # the long flags work too`
  and `Requires Node.js 22 or later; both launchers run .aai/scripts/aai-update.mjs.`
- Base directory (DR-21, the SPEC-0306 D-ROOT rule): the environment's `PWD`
  when it is absolute and names the same device and inode as the process
  working directory, else `process.cwd()`. The target is the base; a
  relative `--repo` that names a directory resolves lexically against the
  base (`path.resolve`), as bash's logical `cd` does; `CDPATH` is ignored.
- Exit codes: 0 done (also after a refused or crashed doctor helper); 1
  usage error, an invalid runner (D-RUNNER), or an internal error after
  cleanup (`aai-update: internal error: <message>` on stderr); 2 canonical
  refusal; 3 fetch failed; 4 sync script missing in the source; a nonzero
  sync exit is passed through (D-RUNNER).

### D-GUARD. Canonical-repo guard (DR-5, DR-6)

`normSlug(s)`: empty for an empty value; strip a trailing `.git` (case
per `SLUG_CASE_FLAGS`); drop everything up to and including the LAST
`github.com:` or `github.com/` (case per `SLUG_CASE_FLAGS`); the result
counts only when it matches `^[^/]+/[^/]+$`, and is then lowercased; else
empty. The guard reads the target's `remote.origin.url` through
`git -C <target> config --get remote.origin.url` (stdout only; any failure
reads as empty) and refuses, unless `--force`, when `normSlug(repo)` is
non-empty and equal to `normSlug(origin)`: three stderr lines,
`REFUSED: this project (<origin>) looks like the canonical AAI repo.`,
`  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git.`,
`  Pass --force (or -Force) to override.` and exit 2, before any source
work, temp directory or sync.

### D-SOURCE. Source resolution and the clone chain (DR-7, DR-9, DR-18, DR-20, DR-22)

- Local checkout: `--repo` names an existing directory (resolved per D-CLI).
  Description `local checkout <abs path>`. In a real run three best-effort
  commands run in it, outputs discarded, failures and a missing git ignored:
  `git -C <src> fetch --depth 1 origin <ref>`, `git -C <src> checkout <ref>`,
  `git -C <src> pull --ff-only origin <ref>`. In a dry-run none of them runs
  (DR-7).
- Otherwise `cloneUrl(repo)`: the value as given when it contains `://`, or
  an `@` followed later by a `:` (DR-22); else
  `https://github.com/<repo>.git`. Description `<url>@<ref>`. A dry-run
  starts no clone and creates no temp directory.
- Real run: `createOwnTemp` (D-TEMP) then `srcDir = path.join(tmp,
  SRC_SUBDIR)`; three attempts, each preceded by removing `srcDir` (never
  `tmp`): (1) `gh repo clone <repo> <srcDir> -- --branch <ref> --depth 1`;
  (2) `git clone --branch <ref> --depth 1 <url> <srcDir>`; (3) `git
  ...ANON_CLONE clone --branch <ref> --depth 1 <url> <srcDir>` with
  `GIT_TERMINAL_PROMPT=0` added to that one child's environment only (DR-9).
  An attempt succeeds on exit 0; a child that cannot start (ENOENT) is a
  failed attempt. git and gh calls run with stdin, stdout and stderr all
  `ignore` (DR-20), except the two readers in D-GUARD and D-EVIDENCE whose
  stdout is piped.
- All three failed: when attempts 2 and 3 both failed to start, stderr
  `ERROR: could not fetch <repo>@<ref>: git was not found on PATH.` (DR-18);
  otherwise `ERROR: could not fetch <repo>@<ref> (auth or network?). Treat as
  an access issue, not a missing repo.`; exit 3 after D-TEMP cleanup.
- The temp directory's identity never changes during the run (no remove and
  re-create of `tmp`; SPEC-0052's TOCTOU property).

### D-TEMP. Temp lifecycle (DR-8, DR-10)

- `createOwnTemp(tmpdir)` = `fs.mkdtempSync(path.join(tmpdir, TMP_PREFIX))`
  (so `aai-src.XXXXXX`, DR-10), recording the returned path and the realpath
  of `tmpdir` in `state.created`. `tmpdir` is `os.tmpdir()` unless injected.
- `removeOwnTemp(dir, created)` removes `dir` recursively only when all
  hold, re-checked right before the removal: `dir` is a non-empty absolute
  string equal to `created.path`; its basename starts with `TMP_PREFIX`; it is
  a real directory (lstat, not a symbolic link); the realpath of its parent
  equals `created.parentReal`. Otherwise nothing is removed, stderr gets
  `aai-update: kept <dir>: <reason>`, and the exit code is unchanged.
- Cleanup runs in a `finally` around everything after `createOwnTemp`, on
  every exit path (success, exit 3, exit 4, a failed sync, an internal
  error), and from SIGINT and SIGTERM handlers (exit 130 and 143) once a
  blocking child has returned; `--keep-temp` keeps the directory and prints
  nothing about it. The module creates no other file or directory outside
  the target and the temp directory; there is no self-relocated copy (DR-8).

### D-RUNNER. Which sync twin of the source runs (DR-11, DR-12, DR-16)

This is the ride's key decision. Each launcher names its own entry, and the
module runs the source's sync twin that this entry ran before, under the
same interpreter, so no user's sync changes engine and no sync bytes change
(porting the sync is ride 12):

- The `.sh` launcher exports `AAI_UPDATE_SYNC_RUNNER=bash`; the `.ps1`
  launcher sets it to `(Get-Process -Id $PID).Path` (the engine running the
  launcher: powershell.exe under 5.1, pwsh under 7) and restores the
  caller's previous value afterwards.
- `resolveRunner(env, platform)`: the value `bash`, or an absolute path whose
  basename (case-insensitive) is `bash` or `bash.exe`, selects the bash
  runner with that executable; an absolute path whose basename is `pwsh`,
  `pwsh.exe`, `powershell` or `powershell.exe` selects the PowerShell runner
  with that executable. Unset or empty: `bash` on POSIX, `powershell.exe` on
  win32. Any other value: stderr
  `aai-update: AAI_UPDATE_SYNC_RUNNER must be bash or a path to bash, pwsh or powershell, got '<value>'`
  and exit 1 before anything else starts.
- `syncCommand`: bash runner `<exe> <src>/.aai/scripts/aai-sync.sh <target>`,
  with every backslash in the two paths turned into `/` on win32 (Git Bash
  reads `C:/...`; a backslash path would break the sync's own
  `dirname "$0"`); PowerShell runner `<exe> -NoProfile -NonInteractive
  [-ExecutionPolicy Bypass on win32] -File <src>/.aai/scripts/aai-sync.ps1
  -TargetRoot <target>`. The chosen sync file must be a regular file, else
  stderr `ERROR: sync script missing in source: <path>` and exit 4.
- The sync child runs with cwd the target, stdio inherited, and the caller's
  environment minus `AAI_UPDATE_SYNC_RUNNER` (the doctor helper gets the
  same environment). A nonzero exit ends the run with that code before any
  post-sync output (DR-12; a signal ends it with 128 plus the signal
  number); the PowerShell twin ran the sync in-process and continued after a
  sync `exit N`.
- The dry-run `Would run` line names the runner's command (DR-16): bash
  `- Would run: <source>/.aai/scripts/aai-sync.sh "<target>"`, PowerShell
  `- Would run: <source>/.aai/scripts/aai-sync.ps1 -TargetRoot "<target>"`.
- Why not one twin per platform: a user on Git Bash under Windows would
  silently switch to the PowerShell sync, and a PowerShell 7 user to 5.1
  (whose sync writes a byte order mark into AAI_PIN.md, allowlist row
  `win-ps1-pin-newline-bom`); the hint keeps both exactly as today. Direct
  `node aai-update.mjs` (no launcher) takes the platform default.

### D-EVIDENCE. Dry-run, evidence and next steps (DR-13 to DR-17)

The module prints the bash reference's bytes; each difference from the
PowerShell reference is a DR:

- Dry-run (exit 0, nothing written, no child except the guard's git read):
  `## aai-update (dry-run) — no files changed`, `- Target:   <target>`,
  `- Upstream: <description>`, the D-RUNNER `Would run` line, `- Then check:
  git status --short, .aai/system/AAI_PIN.md,
  docs/ai/reports/sync-conflicts-*.md`, `- Next: /aai-doctor (and
  /aai-bootstrap if skills changed)`. The em dash is DR-13 against the
  PowerShell `-`.
- Real run: `## aai-update — syncing <description> into <target>` (DR-13),
  the sync's own output, an empty line, `## Post-sync evidence`.
- Changed files: stdout of `git -C <target> status --short` split on LF,
  empty lines dropped, no CR stripping; any failure reads as none. Non-empty:
  `- Changed files (<n>):` then each line indented by two spaces; empty:
  `- Changed files: none (already up to date)`. (Both twins agree; one rule.)
- AAI_PIN: when `<target>/.aai/system/AAI_PIN.md` is a regular file,
  `- AAI_PIN:` then every line matching any of `PIN_KEYWORDS`
  case-insensitively, indented by two spaces, after removing a leading UTF-8
  byte order mark and each trailing CR (DR-17: the bash grep kept both).
- Conflict advisory: among regular files of `<target>/docs/ai/reports` whose
  name matches `^sync-conflicts-.*\.md$`, the one with the greatest mtime
  (nanoseconds), ties to the smallest name; printed as `- ⚠ Conflict
  advisory: docs/ai/reports/<name> — review before committing.` with a
  forward-slash target-relative path (DR-14: PowerShell printed `- !`, the
  bare name and ` - `).
- Doctor field report: D-DOCTOR.
- `## Next`, `- Review the diff (git diff), then commit manually (this tool
  never auto-commits).`, and `- Recommended: /aai-doctor ; /aai-bootstrap if
  skills/indexes changed` when changed files exist, else `- Recommended:
  /aai-doctor` (DR-15: PowerShell always printed `- Recommended: /aai-doctor
  (and /aai-bootstrap if skills/indexes changed)`). Empty lines between the
  sections as in the bash reference.

### D-DOCTOR. The doctor postamble (DR-19)

After an empty line, `## Doctor field report`, then: the helper
`<target>/HELPER_REL` not a regular file prints `DOCTOR-REPORT SKIP helper
missing - update unaffected`; otherwise it runs as `process.execPath
<helper> --root <target>` with cwd the target and stdio inherited; a
nonzero exit, a signal or a start failure prints `DOCTOR-REPORT SKIP helper
crashed - update unaffected`. Nothing in the region can change the exit
code or throw past it. It never runs in a dry-run or after a failed sync.
The twins' `node missing` branch is gone (DR-19: Node runs the module, and
the helper runs on the same Node).

### D-DRIFT. Every difference from either twin, each with a test

| Id | Bash twin | PowerShell twin | Module | Why | Test |
|---|---|---|---|---|---|
| DR-1 | `-h` prints the usage block | `-h` WARN-ignored, the run proceeds | the bash block plus the PowerShell usage line and the Node line; exit 0 on every entry | help must never run an update; one help names both entries | TEST-3962, corpus U09 |
| DR-2 | unknown argument: error line, usage, exit 1 | WARN and continue, exit 0 | the bash behaviour | a mistyped `--dry-runn` must not run a real update | TEST-3962, U10 |
| DR-3 | missing or empty value: shell error, exit 0, nothing done | ignored, the default slug is used | `aai-update: <flag> needs a value`, exit 1 | a usage error must say so and fail; the PowerShell twin could update from the wrong source | TEST-3962, U11 |
| DR-4 | long flags only | native parameters with abbreviation and colon forms, `--x=v`, long flags; a long flag overrides a native one regardless of order | long flags, `--x=v`, the five exact PowerShell names on every entry; left to right, last wins | one argument grammar for both launchers | TEST-3962, U20, U21 |
| DR-5 | case-sensitive `.git` and host, last `github.com` | case-insensitive, first `github.com` | case-insensitive, last `github.com` | hostnames are case-insensitive; the guard is a safety refusal | TEST-3963, U08 |
| DR-6 | `Pass --force to override.` | `Pass -Force to override.` | `Pass --force (or -Force) to override.` | one text for both entries | TEST-3963, U06 |
| DR-7 | dry-run fetches, checks out and pulls in a local source checkout | same | dry-run starts no git command in the source | a dry-run promises to change nothing; `checkout` can switch the user's branch | TEST-3964, U04 |
| DR-8 | copies itself to `$TMPDIR/aai-update.XXXXXX` and re-executes | none | none | a loaded module cannot be overwritten by the sync | TEST-3961, U02 |
| DR-9 | `GIT_TERMINAL_PROMPT=0` for the anonymous clone only | set process-wide at attempt 3, inherited by sync and doctor | the bash behaviour | the setting belongs to the clone that needs it | TEST-3964, U23 |
| DR-10 | temp `aai-src.XXXXXX` | temp `aai-src-<random>` | `aai-src.XXXXXX` | one prefix; ownership is checked on it | TEST-3965, U03k |
| DR-11 | runs `bash <src>/.aai/scripts/aai-sync.sh` | runs `aai-sync.ps1` in-process | the runner the launcher names (D-RUNNER); PowerShell sync as a child of the same engine | every entry keeps its sync twin and engine | TEST-3966, U01 |
| DR-12 | a failing sync ends the run with its code | in-process: a sync `exit N` continues to the evidence, a throw ends with 1 | the bash behaviour | evidence after a failed sync is misleading | TEST-3966, U13 |
| DR-13 | headers with an em dash | ASCII hyphen | em dash | the bash bytes | TEST-3967, corpus ps1 rewrite |
| DR-14 | `- ⚠ Conflict advisory: docs/ai/reports/<name> — review before committing.` | `- ! Conflict advisory: <name> - review before committing.` | the bash form | the relative path is unambiguous | TEST-3967, U01 |
| DR-15 | Recommended names /aai-bootstrap only when files changed | always the long form | the bash form | the conditional is the useful one | TEST-3967, U14 |
| DR-16 | `Would run: <source>/...aai-sync.sh "<target>"` | `Would run: SOURCE/...aai-sync.ps1 -TargetRoot "<target>"` | the runner's command with `<source>` | the line names what the run would start | TEST-3966, U05 |
| DR-17 | AAI_PIN lines keep a CR and a leading BOM | stripped | stripped | output lines carry no line-end artefacts | TEST-3967, U18 |
| DR-18 | git missing: `auth or network?` | same | `ERROR: could not fetch <repo>@<ref>: git was not found on PATH.` | closes `fu-update-missing-git-msg` | TEST-3964 |
| DR-19 | `node missing` SKIP branch; helper on PATH node | same | branch gone; helper on `process.execPath` | Node runs the module | TEST-3961, TEST-3968 |
| DR-20 | git and gh inherit stdin | in-process | stdin, stdout and stderr closed | nothing can block on input | TEST-3964 |
| DR-21 | local source and target as bash's logical `pwd` | `Resolve-Path` and `Get-Location` | the PWD rule of D-CLI | the bash bytes on POSIX | TEST-3962, U01 |
| DR-22 | clone URL when `@` is followed later by `:` | needs a character between them | the bash rule | the bash bytes | TEST-3964 |

Kept for parity, pinned as rules and not drifts: the help text on stdout
after an unknown argument, `--ref` not validated, the local checkout's
`git checkout <ref>` in a real run (it can switch the user's source
branch), `--keep-temp` printing no path, `gh repo clone` given the raw
`--repo` value. Each gets a suggested follow-up (D-FU).

### D-REF. Frozen copies of both twins

`tests/fixtures/aai-update-reference/aai-update.sh` (byte copy of blob
`6922cbbf`, sha256 `5f5cb9ee...`, mode 100755) and
`tests/fixtures/aai-update-reference/aai-update.ps1` (blob `3d4134e9`,
sha256 `136c3d35...`, mode 100644), both LF through the existing
`.gitattributes` rules. `tests/skills/lib/update-reference.mjs` exports
`REFERENCE_SH`, `REFERENCE_PS1`, `REFERENCE_SH_SHA256`,
`REFERENCE_PS1_SHA256`, `REFERENCE_COMMIT` (`30c983ef`),
`materializeUpdateReference(fromRoot, intoRoot)` (verifies both hashes, a
mismatch throws naming the file; writes the two files to
`<intoRoot>/.aai/scripts/` with modes 0755 and 0644; the twins source no
sibling, so no `.aai` tree is copied), and its own scratch helpers
`createOwnScratch`, `removeOwnScratch`, `removeOwnScratchAll` with
`const OWN_SCRATCH_PREFIX = 'aai-up-';` and the marker `.aai-up-owned`, with
the refusal rules of SPEC-0306 D-SAFETY. Where git history holds
`30c983ef`, TEST-3960 also requires each copy to equal `git show
30c983ef:.aai/scripts/<name>`. The copies live outside `.aai/` (never
vendored) and outside the ratchets' scan directories; the same lifetime
rule as SPEC-0306 D-REF applies.

### D-CORPUS. The differential corpora (stdout, stderr, exit, trees)

In `tests/skills/lib/aai-update.test.mjs` (POSIX hosts; bash, git and, for
the PowerShell side, pwsh). Each case builds its fixture once per side at the
same absolute path under one own scratch root (the previous side's tree
renamed away first), then runs the reference and the module with cwd the
target and the environment: the caller's minus every `AAI_` variable and
minus `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`,
`GITHUB_ENTERPRISE_TOKEN`; plus `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL`
an empty scratch file, `GIT_ALLOW_PROTOCOL=file`, `GH_CONFIG_DIR` an empty
scratch directory, `TMPDIR` a per-case scratch directory, and a scratch stub
directory first on `PATH` holding a `gh` stub that appends its argv to a
scratch log and exits 1 (and, for U23 only, a `git` wrapper that logs and
fails `clone` unless its argv holds `credential.helper=`, else runs the real
git by absolute path).

- Bash side (TEST-3969): `bash <ref>/aai-update.sh <args>` against
  `node <module> <args>` with `AAI_UPDATE_SYNC_RUNNER=bash`.
- PowerShell side (TEST-3970): `pwsh -NoProfile -NonInteractive -File
  <ref>/aai-update.ps1 <args>` against the module with
  `AAI_UPDATE_SYNC_RUNNER=<absolute pwsh path>`.
- Fixture source: a scratch git repository (branches `main` and `dev`,
  own identity) whose `.aai/scripts/aai-sync.sh` and `aai-sync.ps1` stubs do
  the same thing: print `FX-SYNC target=<arg>`, `FX-GTP=<GIT_TERMINAL_PROMPT
  or unset>` and `FX-RUNNER=<AAI_UPDATE_SYNC_RUNNER or unset>`; copy into the
  target an AAI_PIN.md variant, two sync-conflicts reports with fixed mtimes,
  the real `update-doctor-report.mjs` (or a broken one, or none) and a stub
  `aai-doctor.mjs` printing a CLEAN verdict; exit with `FX_SYNC_EXIT` when set
  (the PowerShell stub throws when `FX_SYNC_THROW` is set). Knobs are
  environment variables without the `AAI_` prefix.
- Compared: exit code, stdout bytes, stderr bytes, the target tree through
  the harness's `snapshotNormalized` and `compareSnapshots` (N4 and E2
  included, `.git/` excluded), the source checkout's branch and HEAD after
  the run, the `TMPDIR` listing after the run, and the `gh` stub log. The only
  rewrites before comparing: doctor report names `doctor-<14 digits>Z-<host>.md`
  become `doctor-<stamp>.md` on both sides; temp names `aai-src[.-]<id>`
  become `aai-src.<id>` (DR-10, PowerShell side); and the named DR rewrites
  below. Each DR rewrite applies to one side's output, is registered per case,
  and a registered rewrite that changes nothing fails the case.
- DR rewrites, bash side: DR-1 (append the two help lines), DR-6, DR-17 (strip
  CR and BOM from AAI_PIN lines). PowerShell side: DR-6, DR-13, DR-14, DR-15,
  DR-16 (`SOURCE` to `<source>`).
- Asserted divergences (compared to an expected value, not rewritten): U04
  bash and PowerShell (the references move the source branch, the module
  does not), U08 bash (exit 0 against the module's 2), U10 PowerShell (exit
  0 and WARN against exit 1), U11 both (a reference exit of 0 or any
  nonzero against the module's 1 and its line), U13 PowerShell (evidence
  printed after the failed sync), U20 bash and U21 bash (exit 1 against the
  module's 0), U23 PowerShell (`FX-GTP=0` against `unset`).

Cases (sides in brackets; every target a git repository with origin
`https://github.com/acme/target.git` and one commit unless named otherwise):

- U01 [both] local source given as a relative `../src`, real run, files
  changed, plain LF pin, two conflict reports, helper present.
- U02 [both] `file://` source: `gh` stub fails, git clones; `TMPDIR` empty
  after the run on both sides. U03 [both] `file://` source that does not
  exist: exit 3, `TMPDIR` empty; U03k the same with `--keep-temp`: one temp
  directory kept, no content under its `src`.
- U04 [both] dry-run on a local source whose checked-out branch is `dev`,
  `--ref main`. U05 [both] dry-run `--repo acme/foo --ref dev`: no `gh` log
  line, no temp directory.
- U06 [both] origin `https://github.com/goodwind-cz/aai.git`, no force:
  exit 2, target unchanged. U07 [both] the same with `--force --dry-run`:
  exit 0. U08 [both] origin `https://GITHUB.COM/Goodwind-CZ/AAI.GIT`.
- U09 [bash] `-h`. U10 [both] `--bogus --dry-run --force`. U11 [both]
  `--dry-run --repo`.
- U12 [both] source without the side's sync script: exit 4. U13 [both]
  `FX_SYNC_EXIT=5`; U13t [PowerShell] `FX_SYNC_THROW=1` (exit 1 on both).
- U14 [both] target that is not a git repository. U15 [both] helper not
  copied. U16 [both] broken helper. U17 [both] no pin and no reports
  directory. U18 [both] pin with a byte order mark and CRLF lines. U19
  [both] two conflict reports with the same mtime.
- U20 [both] `--repo=<src> --ref=main --dry-run --force`. U21 [both]
  `-Repo <src> -Ref main -DryRun -Force`. U22 [both] target path with a
  space, real run. U23 [both] `file://` source through the `git` wrapper:
  attempts gh, git, anonymous git in that order on both sides.

After every case the `gh` log holds only `repo clone` lines, no case
reaches a non-file URL, and the case's scratch root holds no entry besides
its fixtures, the stub directory, the logs and the marker.

### D-PARITY. The parity harness takes the module as a third twin on update

Changes to `tests/skills/lib/install-parity.mjs`:

- A twin may carry `peers`, a map from operation to the twin names it is
  compared with; `runScenario` skips a pair when either twin lists peers for
  the scenario's op that exclude the other. A twin without `peers` pairs with
  every twin, as before.
- `ctx.upref`: built once per run when a selected scenario has op update,
  by `materializeUpdateReference(REPO_ROOT, <root>/upref)`; passed to every
  twin's argv ctx (like `bsref`).
- sh twin, update: `bash <upref>/.aai/scripts/aai-update.sh --repo <src>
  --ref main` (the frozen bash reference, forward-slash paths). ps1 twin,
  update: unchanged line (`<src>/.aai/scripts/aai-update.ps1 -Repo <src>
  -Ref main`), which now runs the PowerShell launcher, so the module runs
  the PowerShell sync under the twin's engine on every leg, natively on
  Windows 5.1 and 7. node twin: `ops: ['bootstrap', 'update']`, `peers: {
  update: ['sh'] }`, update argv `process.execPath
  <src>/.aai/scripts/aai-update.mjs --repo <src> --ref main` with env
  `AAI_UPDATE_SYNC_RUNNER` set to `ctx.bash`, containing the exact line
  `      return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-update.mjs'), '--repo', ctx.src, '--ref', 'main'], cwd: ctx.target, env: { AAI_UPDATE_SYNC_RUNNER: ctx.bash } };`
  and the exact text `peers: { update: ['sh'] }` once.
- Why `peers`: on an update scenario the ps1 and node twins run the same
  module and differ only by the sync twin (PowerShell against bash), which
  sh:ps1 already compares against the reference under the reviewed sync
  rows. A ps1:node pair would repeat every sync divergence under a second
  pair name, and a row widened to it would be stale on a smoke run (UP-02's
  `.gitignore` rows never fire there, measured). So update scenarios compare
  sh:ps1 (bash reference against the PowerShell launcher, module and
  PowerShell sync, under the existing rows) and sh:node (bash reference
  against the module with the bash sync, expected byte-equal with no row).
  Bootstrap scenarios keep all three pairs.
- Allowlist: no new row. The intermittent row `win-sh-odd-root-dirs` widens
  its pairs to `sh:ps1,sh:node` (its cause is the bash reference's doctor
  run under Git Bash; intermittent rows are never judged stale); reviewed
  reason appended: "the module twin runs the doctor helper on its own Node
  and is compared with the same bash reference". A further divergence a
  hosted run shows gets a row and a follow-up in a remediation pass, never a
  normalization (SPEC-0284 D-ALLOW).
- No scenario, tier or normalization changes: TEST-3560 and TEST-3562 stay
  as they are.
- The scratch source is built from `git ls-files`, so the module and the
  launchers must be in the index (staged) before a driver run sees them.

### D-LAUNCH. Launchers

- `.aai/scripts/aai-update.sh`: at most 20 lines, ASCII, `#!/bin/sh`, POSIX
  only (sh, dash, bash), mode 100755:

  ```sh
  #!/bin/sh
  # AAI layer updater launcher; argument, source, sync and report policy live in aai-update.mjs (RFC-0017 phase 5).
  # Usage: ./.aai/scripts/aai-update.sh [--repo <slug|url|path>] [--ref <ref>] [--dry-run] [--keep-temp] [--force] [-h]
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-update.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    AAI_UPDATE_SYNC_RUNNER=bash
    export AAI_UPDATE_SYNC_RUNNER
    exec node "$MODULE" "$@"
  fi
  echo "aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
  exit 1
  ```

- `.aai/scripts/aai-update.ps1`: at most 20 lines, ASCII, no param block,
  5.1 and 7 compatible; it neutralizes the caller's error preferences in its
  own scope so a nonzero module exit is passed through, never turned into a
  terminating error:

  ```powershell
  # AAI layer updater launcher; argument, source, sync and report policy live in aai-update.mjs (RFC-0017 phase 5).
  # Usage: powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force] (the --long flags work too)
  $ErrorActionPreference = 'Continue'
  $PSNativeCommandUseErrorActionPreference = $false
  $Module = Join-Path $PSScriptRoot 'aai-update.mjs'
  if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
    $prev = $env:AAI_UPDATE_SYNC_RUNNER
    $env:AAI_UPDATE_SYNC_RUNNER = (Get-Process -Id $PID).Path
    try { & node $Module @args } finally { $env:AAI_UPDATE_SYNC_RUNNER = $prev }
    exit $LASTEXITCODE
  }
  [Console]::Error.WriteLine('aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
  exit 1
  ```

- Neither launcher names a git or gh command, a sync script, a flag value,
  the guard or an exit code other than 1 and the module's own. Policy
  tokens checked absent: `git`, `gh `, `aai-sync`, `REFUSED`, `canonical`,
  `--dry-run` outside the usage comment, `exit 2`, `exit 3`, `exit 4`.
- A consumer updating from an older layer runs its old bash or PowerShell
  twin once (the bash twin's self-relocation protects that run); that sync
  vendors the launchers and the module, and the next update runs the new
  path.

### D-PESTER. `tests/skills/aai-update.Tests.ps1`

A new `Context 'launcher (update-on-node)'`, Pester 5, 5.1-compatible
syntax, never skips, launching with the running engine
(`(Get-Process -Id $PID).Path`) through `ProcessStartInfo` with an explicit
PATH, scratch only under `$TestDrive`:

1. Pass-through: the launcher copied into `$TestDrive` beside a stub
   `aai-update.mjs` that writes `{argv, runner}` as JSON and exits 7;
   arguments `-Repo "dir with space" --ref dev -DryRun --keep-temp -Force -h`
   arrive in that order unchanged, `runner` equals the engine path, exit 7.
2. Scope hygiene: inside one child engine, `$env:AAI_UPDATE_SYNC_RUNNER =
   'preset'; & <copied launcher>; $env:AAI_UPDATE_SYNC_RUNNER` prints
   `preset` (the caller's value is restored), and with no preset it prints
   nothing.
3. Refusal: PATH an empty `$TestDrive` directory; exit 1, stdout empty,
   stderr exactly the D-LAUNCH line, the target directory unchanged.
4. Module missing: the launcher copied alone; the same refusal.
5. Real run: the repository's launcher, cwd a `$TestDrive` git target,
   `-Repo <a $TestDrive source whose aai-sync.ps1 stub writes
   (Get-Process -Id $PID).Path into the target> -Force`; exit 0, the
   recorded engine path equals the test engine's path, stdout holds `##
   Post-sync evidence` and `## Next`.

It runs in the existing jobs through directory discovery (Linux `gate`,
`windows-5_1` with both engines, `windows-wsl1`); no job, step or exclusion
is added; the TotalCount floor 111 and `AAI_EXPECTED_WIN_SKIP_COUNT` 4 stay
(D-REHOME removes five cases and these add five). Budget: at most 30 s per
engine on a hosted runner.

### D-INSTALL. A scratch aai-sync install runs both launchers

TEST-3976: `bash .aai/scripts/aai-sync.sh <scratch>/target --profile core`
from this checkout into a fresh `git init` target; the vendored
`aai-update.mjs`, `.sh` and `.ps1` exist in the target. On three fresh
copies of the synced target (same absolute path, one after another), `bash
.aai/scripts/aai-update.sh --repo <scratch fixture source> --force`, `sh` of
the same, and `<pwsh> -NoProfile -File .aai/scripts/aai-update.ps1 -Repo
<scratch fixture source> -Force` each exit 0, and the trees are equal under
`snapshotNormalized` (the fixture source's two sync stubs write the same
files); with PATH a scratch directory holding only `dirname`, `sh
.aai/scripts/aai-update.sh --dry-run` exits 1 with the D-LAUNCH line and the
tree is unchanged. pwsh through `need_tool`. The source is never this
checkout (D-SAFETY).

### D-SAFETY. No network, no daemon, delete only what the run made

- No network: tests run update only against local directories or `file://`
  URLs; every update run in the new suite, the node:test file, the corpora,
  `test-aai-update.sh` and the clone cases of `aai-update.Tests.ps1` sets
  `GIT_ALLOW_PROTOCOL=file`, `GH_CONFIG_DIR` to an empty scratch directory
  and removes `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` and
  `GITHUB_ENTERPRISE_TOKEN`; on POSIX a `gh` stub sits first on PATH. Unit
  tests of the clone chain use the injected `spawn` and start nothing. A
  dry-run against a slug starts no clone by rule (D-SOURCE).
- The shipping checkout is never a source: the local-checkout path runs
  `git checkout` and `pull` in the source directory, so every `--repo` (and
  `-Repo`) a test passes must lie under the run's own scratch root; the new
  suite asserts this for every update invocation it makes.
- No container daemon: no test or mutation calls `docker`, `pkill`,
  `killall` or a kill by pattern; children are synchronous; the suites run
  under `aai-run-tests.sh`, whose isolation points `DOCKER_HOST` at a
  nonexistent socket.
- Deletion: the module's own temp through `removeOwnTemp` only (D-TEMP);
  test scratch through `removeOwnScratch` (prefix `aai-up-`, marker
  `.aai-up-owned`) or the new suite's `safe_rm_own` (prefix
  `aai-update-node.`); each refuses an empty path, a relative path, a
  foreign prefix, a path outside the temp directory, a symbolic link and an
  unmarked directory, re-reads the marker right before removing, and treats
  an empty list as a failure. `test-aai-update.sh` creates one own scratch
  root at start (prefix `aai-update-suite.`, marker `.aai-up-owned`),
  points `TMPDIR` into it for its cases, and removes it from an EXIT trap
  through the same refusal rules, so a failing case leaves nothing behind.
  Pester uses `$TestDrive` (and TEST-009's existing try/finally).

### D-REHOME. Existing tests that read the old twins, and their amendments

Behaviour assertions stay byte for byte unless named here; each named change
gets one unsigned amendment record (`node .aai/scripts/spec-amend.mjs add
--spec <spec> --ref update-on-node --class contract --signoff none --what
"<what>" --why "<one line>"`; the owner's merge direction signs them):

- `tests/skills/test-aai-update.sh` (run 5, with the `.sh` swap):
  - test_001 and test_002 (SPEC-0052 source shape of the bash twin) read the
    module instead: `SRC_SUBDIR` and its one `path.join(tmp, SRC_SUBDIR)`,
    exactly one `mkdtempSync(` call, the `srcDir` removal inside the attempt
    loop, `tmp` removed only through `removeOwnTemp`. Record for SPEC-0052,
    what begins `TEST-001 and TEST-002 re-homed`.
  - test_010 and test_014 (SPEC-0124 0137-TEST-005 and 0137-TEST-009) read
    the module's `doctorReport` region instead of the two twins' postambles:
    no network primitive (the same token set), the region names
    `update-doctor-report.mjs` and `DOCTOR-REPORT SKIP`, ASCII only; the
    try/catch and or-guard assertions are dropped (TEST-3968 proves the
    exit code behaviourally). Record for SPEC-0124, what begins
    `0137-TEST-005 and 0137-TEST-009 re-homed`.
  - Environment class: the suite-level own scratch root and EXIT trap
    (D-SAFETY), and the network-free environment for the update runs of
    test_004, test_005, test_006 and test_008 (their assertions unchanged).
  - Unchanged and passing against the launcher: test_003 (`bash -n`),
    test_004 (the `Would run:.*aai-sync\.sh` line, no `aai-src.*` in
    `TMPDIR`), test_005 (clone at `$TMP/src`, owner, exit 3, no stray
    `src`), test_006, test_008, and every helper-only case.
- `tests/skills/test-aai-layer-drift.sh` test_ps1_parity (SPEC-0020
  TEST-010b): the update-evidence half reads the module's `PIN_KEYWORDS`
  line for `'canonical'` instead of grepping `aai-update.sh`. Record for
  SPEC-0020, what begins `TEST-010b re-homed`.
- `tests/skills/test-aai-hygiene-pack.sh` test_128 (SPEC-0179 TEST-470):
  the pipefail-bearing shipping-script floor moves from more than 5 to at
  least 3 (`aai-update.sh` becomes a launcher without pipefail; rides 11
  and 12 remove two more; three stay kept-native per plan section 5).
  Record for SPEC-0179, what begins `TEST-470 vacuity floor`.
- `tests/skills/aai-update.Tests.ps1` (run 6, with the `.ps1` swap):
  - TEST-006 and TEST-007 (source shape of the PowerShell twin) are
    removed; the property is proven on the module by TEST-3964 and
    TEST-3965. TEST-009's temp filter becomes `aai-src.*` (DR-10); its
    PosixOnly skip stays. The robustness case expects exit 1 and stderr
    `Unknown argument: --bogus` (DR-2). Record for SPEC-0052, what begins
    `TEST-006, TEST-007, TEST-009 and the robustness case re-homed`.
  - TEST-3584 asserts the launcher holds no git or gh token and is ASCII
    only (the native-call class is gone from the update path); TEST-3587 and
    TEST-3588 move to the module's node:test (TEST-3964, git missing);
    TEST-3589 is retired (closes `fu-update-test-3589-isolation`);
    TEST-3580 to TEST-3583 stay, run through the launcher. Record for
    SPEC-0285, what begins `TEST-3584, TEST-3587, TEST-3588 and TEST-3589
    re-homed`.
  - Environment class: the clone cases (TEST-009, TEST-3581, TEST-3582) set
    the D-SAFETY network-free environment.
  - Unchanged and passing against the launcher: parses, both guard cases,
    both dry-run cases (`Would run:.*aai-sync\.ps1 -TargetRoot "` holds with
    the PowerShell runner), the `--repo=` and `--ref` case.
- `tests/skills/lib/install-parity.mjs` and `install-parity.test.mjs`
  (SPEC-0284 D-SEAM): D-PARITY's `peers` field, `ctx.upref`, the sh and node
  update argv; the real-registry unit test's update assertions follow
  (sh `[<upref>/.aai/scripts/aai-update.sh, --repo, /s, --ref, main]`, node
  as D-PARITY); the `win-sh-odd-root-dirs` pairs widen. Record for SPEC-0284,
  what begins `D-SEAM gains the twin peers field`.
- Unchanged and passing: `test-aai-update-check.sh` (runs the real `.sh`
  launcher for TEST-003 and TEST-004), `test-aai-install-parity.sh`
  (TEST-3565 now runs three twins on UP-01; TEST-3569's bounds unchanged),
  `install-parity.Tests.ps1`, `test-aai-win-fallback.sh` TEST-017 (skip
  count 4), `test-ps1-quality.sh`, `test-aai-doctor.sh`,
  `test-aai-sync-seed.sh`.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-update-node` with globs
  `.aai/scripts/aai-update.*`, `.aai/scripts/update-doctor-report.mjs`,
  `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
  `.aai/system/PROFILES.yaml`, `tests/fixtures/aai-update-reference/**`,
  `tests/skills/test-aai-update-node.sh`, `tests/skills/lib/aai-update.test.mjs`,
  `tests/skills/lib/aai-update-fixtures.mjs`,
  `tests/skills/lib/update-reference.mjs`, `tests/skills/lib/install-parity.mjs`,
  `tests/skills/lib/install-parity-allowlist.tsv`,
  `tests/skills/aai-update.Tests.ps1`, `tests/skills/lib/pester-native-capture.ps1`,
  and every other `tests/skills/lib/*` file the suite sources or reads.
  Every existing row that lists `.aai/scripts/aai-update.sh` gains
  `.aai/scripts/aai-update.mjs` (`aai-install-parity`, `aai-layer-drift`,
  `aai-update-check`, `aai-update`, `aai-project-config`);
  `aai-install-parity` also gains `tests/fixtures/aai-update-reference/**`
  and `tests/skills/lib/update-reference.mjs`.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-update-node fallback unsampled (new suite of update-on-node; no successful observation)`
  and `aai-update-node<TAB>196`.
- `test-aai-hygiene-pack.sh` test_090: the row-count pin moves 138 to 139
  (a parallel ride that adds a suite moves it again; the branch merging
  second rebases the pin); test_129 passes.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record`;
  `.aai/scripts/aai-update.sh` stays 1 (the launcher's one
  `$(CDPATH= cd ...)`), the `test-aai-update.sh` row is whatever the
  re-homed suite measures, and the new suite holds no `cd` inside a command
  substitution.
- Nested-suite lint: no new allowlist row (other suites only in selector
  form). `check-test-registration.mjs` and `check-vendored-script-deps.mjs`
  exit 0.
- `.aai/system/PROFILES.yaml` core: `.aai/scripts/aai-update.mjs` beside the
  two launchers (companion obligation for a new `.aai/**` file).
- `.github/workflows/ps1-quality.yml`: both `push` and `pull_request` path
  lists (identical) gain `.aai/scripts/aai-update.mjs`,
  `tests/fixtures/aai-update-reference/**` and
  `tests/skills/lib/update-reference.mjs`; the launchers and the Pester file
  are covered by existing entries; win-fallback test_034 passes. No job or
  step changes.
- Prompt corpus companion: `SKILL_UPDATE.prompt.md` grows (D-DOCS), so
  `tests/skills/lib/prompt-diet-ledger.sh` gains one JUSTIFIED_ADDITIONS
  entry with the measured byte growth (`/usr/bin/wc -c` against
  `30c983ef`), and the same number moves the TEST-012 `want_growth` pin in
  `test-aai-prompt-diet.sh` and the growth sums in `test-aai-pr-preflight.sh`
  and `test-aai-suite-reuse.sh` (as ride 9 did).
- Left as is, checked: `validate-skills.mjs` REQUIRED (does not list the
  updater), `update-check.mjs`, `layer-drift.mjs`, `aai-doctor.mjs`
  (remedy text only), `PSScriptAnalyzerSettings.psd1` (its `-DryRun` example
  stays true), `docs/TECHNOLOGY.md`.

### D-DOCS. Documentation and release note

- CHANGELOG.md: one new heading
  `## [unreleased] — feat: the AAI layer updater runs on Node behind sh and ps1 launchers`
  whose body says `/aai-update` now requires Node.js 22 or later (both
  launchers refuse without it, exit 1, change nothing), that each launcher
  keeps running the sync twin it ran before, and names DR-2, DR-3, DR-5,
  DR-7 and DR-12; ends with "Re-run `/aai-update` to pick up the new
  launchers and module."
- `.aai/SKILL_UPDATE.prompt.md`: step 1 gains one sentence, `Both launchers
  run .aai/scripts/aai-update.mjs and need Node.js 22 or later.`; step 3
  gains one bullet, `- exit 1 = an unknown argument, a missing flag value, or
  Node.js missing (the message says which)`. Nothing else changes.
- RFC-0017 phase 5 row: one sentence after the fourteenth-slice sentence and
  before the remaining-scripts-plan sentence:
  `The fifteenth slice [moved the layer updater to Node](../issues/CHANGE-DRAFT-update-on-node.md): one module holds the argument, source, sync and report policy behind thin aai-update.sh and aai-update.ps1 launchers, compared with frozen copies of both twins, and each launcher keeps running the sync twin it ran before.`
  Status stays `in progress`; frontmatter untouched; the allocator rewrites
  the link at merge (checks match only the suffix `update-on-node.md`).
  The inventory table is unchanged (expert-fetch test_2624 passes).
- `docs/product/aai-update.md` is updated by the close ceremony after the
  loop completes, not by Implementation.

### D-FU. Follow-ups

Suggested at planning, filed by Implementation with `node
.aai/scripts/follow-ups.mjs add --id <id> --ref update-on-node --severity P3
--what ... --why ... --source ...` (ids at most 40 characters):
`fu-update-local-checkout-switches-branch` (a real run's `git checkout
<ref>` switches the user's source checkout), `fu-update-keep-temp-path-unprinted`,
`fu-update-ps1-ref-not-run-on-windows` (the frozen PowerShell reference
runs only in the POSIX corpus), `fu-update-usage-help-on-stdout`. Every
further divergence a hosted run shows gets one.

### D-SLICES. Runs and the fallback

- Run 1, Spec-AC-01 to 03: frozen references and their helper, the suite
  skeleton (`safe_rm_own`, `run_node_tests`, `need_tool`), the node:test
  file, module shape, arguments, help, base directory; suite-map, weights
  and test_090 rows land with the suite.
- Run 2, Spec-AC-04 to 06: guard, source resolution, temp lifecycle.
- Run 3, Spec-AC-07 to 09: runner and sync step, rendering, doctor postamble.
- Run 4, Spec-AC-10 and 11: both corpora. Fallback ship point: the module
  present but unreachable (launchers unchanged, the module not in PROFILES),
  the new suite running TEST-3960 to TEST-3970, no CHANGELOG entry (the PR
  body carries `no-notes: Node updater module added but not yet reachable
  from any launcher`), and Spec-AC-12 to 19 moved to the next ride's spec by
  a recorded amendment.
- Run 5, Spec-AC-12 and 14: the `.sh` launcher swap together with the
  bash-side re-homes and their records, so no suite is red between runs.
- Run 6, Spec-AC-13, 15 and 16: the `.ps1` launcher with the Pester re-homes
  and records, the PROFILES entry, the parity harness third twin.
- Run 7, Spec-AC-17 to 19: scratch install, the rest of D-WIRE, D-DOCS with
  the prompt-diet ledger, D-FU; then the full sweep once.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-03 to Spec-AC-06 (and Spec-AC-10, 11 for
  the fixture-level equivalence).
- Intake AC-002 maps to Spec-AC-07 to Spec-AC-11.
- Intake AC-003 maps to Spec-AC-06 (and Spec-AC-01 for the tests' own
  scratch).
- Intake AC-004 maps to Spec-AC-16 and hosted check H2.
- Intake AC-005 maps to Spec-AC-12, Spec-AC-13, Spec-AC-17 and hosted
  check H1.
- Intake AC-006 maps to Spec-AC-14, Spec-AC-15, Spec-AC-18 and Spec-AC-19;
  the unchanged suites in D-REHOME pass in the Verification sweep.
- Owner safety rules (no network, no daemon, delete only what the run made,
  cleanup on failure) map to Spec-AC-01 and Spec-AC-06.

## Constitution deviations

None. Article 1: every rule is seen failing first and the corpora compare
real runs of both references. Article 2: one module, two launchers of at
most 13 lines, no dependency. Article 4: without Node both launchers refuse
with one named line and change nothing; a missing or crashing doctor helper
still degrades to a named SKIP line with exit 0. Article 5: downstream
update now requires Node.js 22 or later; this is the owner's recorded
decision (plan section 4, decision 1), stated in the CHANGELOG entry, and
both launchers keep their paths, the argument forms they accepted and the
exit codes 0, 2, 3 and 4.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a test of this ride removes a scratch path the system SHALL refuse (throw or fail the test) an empty path, a relative path, a basename without the own prefix, a path outside the temp directory, a symbolic link, a directory without the .aai-up-owned marker and an empty removal list; both frozen copies under tests/fixtures/aai-update-reference SHALL hash to the D-REF sha256 values and, where git history holds 30c983ef, equal the twins at that commit; the new test files SHALL hold no docker, pkill or killall call, and every update invocation in them SHALL carry GIT_ALLOW_PROTOCOL=file, an empty GH_CONFIG_DIR and a repo argument under the run's own scratch root. | done | TEST-3960 red docs/ai/tdd/update-on-node/red/TEST-3960.log; TEST-3960 green docs/ai/tdd/update-on-node/green/TEST-3960-3962.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3960.txt | — | D-SAFETY, D-REF |
| Spec-AC-02 | .aai/scripts/aai-update.mjs SHALL import only node: specifiers and none of http, https, net, tls or dgram, create no file and print nothing when imported, export the D-MODULE names, hold each D-MODULE anchor line exactly once, call spawnSync exactly once (inside runChild), never reference process.stdout or process.stderr, hold no relocation copy logic and none of the strings node missing or aai-update.XXXXXX, and be ASCII only. | done | TEST-3961 red docs/ai/tdd/update-on-node/red/TEST-3961.log; TEST-3961 green docs/ai/tdd/update-on-node/green/TEST-3960-3962.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3961.txt | — | D-MODULE, DR-8, DR-19 |
| Spec-AC-03 | WHEN the module is run with arguments the system SHALL follow D-CLI: long flags, the equals forms and the five exact PowerShell names in any order with the last occurrence winning, help per DR-1 on stdout with exit 0, an unknown argument per DR-2 with exit 1 and no child started, a value flag without a value or with an empty value per DR-3 with exit 1; resolveBase SHALL use PWD only when it names the same device and inode as the working directory and SHALL resolve a relative repo directory lexically, ignoring CDPATH. | done | TEST-3962 red docs/ai/tdd/update-on-node/red/TEST-3962.log; TEST-3962 green docs/ai/tdd/update-on-node/green/TEST-3960-3962.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3962.txt | — | D-CLI, DR-1 to DR-4, DR-21 |
| Spec-AC-04 | WHEN the target origin and the repo value name the same owner and repository after normSlug (a slug, an https or ssh URL, upper-case host or .GIT suffix, github.com occurring twice) the system SHALL print the three D-GUARD lines with the DR-6 hint and exit 2 before creating a temp directory or starting a sync, and SHALL not refuse with --force, with a local directory as repo, with a different repository, or without an origin. | done | TEST-3963 red docs/ai/tdd/update-on-node/red/TEST-3963.log; TEST-3963 green docs/ai/tdd/update-on-node/green/TEST-3963-3965.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3963.txt | — | D-GUARD, DR-5, DR-6 |
| Spec-AC-05 | WHEN the source is resolved with an injected spawn the system SHALL run the three local-checkout git commands in a real run and none in a dry-run, build the clone URL per DR-22, run the three clone attempts in order with the D-SOURCE argv into tmp/src only, remove tmp/src before each attempt while the inode of tmp stays the same, add GIT_TERMINAL_PROMPT=0 to the third attempt only, close the stdio of every git and gh child, exit 3 with the auth line when all attempts fail and with the DR-18 line when git cannot start, and with git missing still sync a local checkout and exit 0. | done | TEST-3964 red docs/ai/tdd/update-on-node/red/TEST-3964.log; TEST-3964 green docs/ai/tdd/update-on-node/green/TEST-3963-3965.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3964.txt | — | D-SOURCE, DR-7, DR-9, DR-18, DR-20, DR-22 |
| Spec-AC-06 | WHEN a real clone run ends by success, exit 3, exit 4, a failing sync or an internal error the system SHALL leave no aai-src. directory in TMPDIR unless --keep-temp is given, and removeOwnTemp SHALL refuse and keep (with the kept line, exit code unchanged) a path that differs from the created one, lacks the prefix, is a symbolic link, or whose parent realpath differs; a dry-run, a usage error and a refusal SHALL create no temp directory. | done | TEST-3965 red docs/ai/tdd/update-on-node/red/TEST-3965.log; TEST-3965 green docs/ai/tdd/update-on-node/green/TEST-3963-3965.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3965.txt | — | D-TEMP, DR-10 |
| Spec-AC-07 | WHEN resolveRunner and syncCommand run the system SHALL map bash, an absolute bash path and an absolute pwsh or powershell path to the D-RUNNER commands (forward slashes for bash on win32, ExecutionPolicy Bypass only on win32), take bash on POSIX and powershell.exe on win32 when unset, refuse any other value with the named line and exit 1 before any child, exit 4 naming the missing sync file of the chosen runner, pass a nonzero sync exit through with no post-sync output, strip AAI_UPDATE_SYNC_RUNNER from the sync and helper environment, and print the runner's Would run line in a dry-run. | done | TEST-3966 red docs/ai/tdd/update-on-node/red/TEST-3966.log; TEST-3966 green docs/ai/tdd/update-on-node/green/TEST-3960-3968.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3966.txt | — | D-RUNNER, DR-11, DR-12, DR-16 |
| Spec-AC-08 | WHEN renderDryRun, changedFiles, pinLines, latestConflict, renderEvidence and renderNext run on fixed inputs the system SHALL return the D-EVIDENCE bytes: the dry-run block, the sync header, the changed-files list and count or the none line, the AAI_PIN lines matched case-insensitively with a BOM and trailing CR removed, the newest conflict report with ties to the smallest name as a target-relative path with the bash mark, and the Recommended line with or without the bootstrap clause. | done | TEST-3967 red docs/ai/tdd/update-on-node/red/TEST-3967.log; TEST-3967 green docs/ai/tdd/update-on-node/green/TEST-3960-3968.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3967.txt | — | D-EVIDENCE, DR-13 to DR-15, DR-17 |
| Spec-AC-09 | WHEN doctorReport runs the system SHALL print the helper missing line for an absent or non-file helper, run the helper with process.execPath, --root and the target as cwd when present, print the helper crashed line for a nonzero exit, a signal or a start failure, never change the run's exit code, and never run in a dry-run or after a failed sync. | done | TEST-3968 red docs/ai/tdd/update-on-node/red/TEST-3968.log; TEST-3968 green docs/ai/tdd/update-on-node/green/TEST-3960-3968.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3968.txt | — | D-DOCTOR, DR-19 |
| Spec-AC-10 | WHEN the D-CORPUS bash-side cases run the system SHALL give exit code, stdout, stderr, normalized target tree, source branch and HEAD, TMPDIR listing and gh log byte-equal between the bash reference and the module after only the registered rewrites, each registered rewrite changing at least one byte, and the asserted divergences SHALL hold. | done | TEST-3969 red docs/ai/tdd/update-on-node/red/TEST-3969.log; TEST-3969 green docs/ai/tdd/update-on-node/green/TEST-3960-3970.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3969.txt | — | D-CORPUS bash side |
| Spec-AC-11 | WHEN the D-CORPUS PowerShell-side cases run with pwsh the system SHALL give the same comparison byte-equal between the PowerShell reference and the module with the PowerShell runner after only the registered rewrites, and the asserted divergences SHALL hold. | done | TEST-3970 red docs/ai/tdd/update-on-node/red/TEST-3970.log; TEST-3970 green docs/ai/tdd/update-on-node/green/TEST-3960-3970.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3970.txt | — | D-CORPUS PowerShell side |
| Spec-AC-12 | .aai/scripts/aai-update.sh SHALL be the D-LAUNCH text (at most 20 lines, ASCII, mode 100755, no policy token), and WHEN run by bash, sh and dash beside a stub module it SHALL pass every argument (a spaced value included) and the exit code through with AAI_UPDATE_SYNC_RUNNER=bash in the module's environment; WHEN node is not on PATH or the module is missing it SHALL exit 1 with the D-LAUNCH line on stderr and leave the target unchanged. | done | TEST-3971 red docs/ai/tdd/update-on-node/red/TEST-3971.log; TEST-3971 green docs/ai/tdd/update-on-node/green/TEST-3971.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3971.txt | — | D-LAUNCH |
| Spec-AC-13 | .aai/scripts/aai-update.ps1 SHALL be the D-LAUNCH text (at most 20 lines, ASCII, no param block, no policy token); the launcher context of tests/skills/aai-update.Tests.ps1 run with Invoke-Pester under pwsh 7 SHALL pass the five D-PESTER cases with 0 skipped, 0 failed and 0 failed containers. | planned | — | — | D-PESTER; H1 for 5.1 and 7 on Windows |
| Spec-AC-14 | WHEN the re-homed bash-side selectors run against the sh launcher (test-aai-update.sh test_001 to test_006, test_008, test_010 and test_014, test-aai-layer-drift.sh test_ps1_parity, test-aai-hygiene-pack.sh test_128) each SHALL exit 0, test-aai-update.sh SHALL remove its own scratch root on a forced failure, and spec-amend list SHALL hold one contract record of ref update-on-node for SPEC-0124, SPEC-0020 and SPEC-0179 and the first one for SPEC-0052 whose what begins with the D-REHOME text. | done | TEST-3973 red docs/ai/tdd/update-on-node/red/TEST-3973.log; TEST-3973 green docs/ai/tdd/update-on-node/green/TEST-3973.log, mutation docs/ai/tdd/spec-update-on-node/mutation-TEST-3973.txt | — | D-REHOME bash side |
| Spec-AC-15 | WHEN tests/skills/aai-update.Tests.ps1 runs whole with Invoke-Pester under pwsh 7 on POSIX it SHALL pass with 0 failed and 0 skipped, without TEST-006, TEST-007, TEST-3587, TEST-3588 and TEST-3589, with the robustness case expecting exit 1, TEST-009 filtering aai-src.* and TEST-3584 checking the launcher; spec-amend list SHALL hold the second SPEC-0052 record and the SPEC-0285 record, and follow-ups SHALL show fu-update-test-3589-isolation and fu-update-missing-git-msg closed. | planned | — | — | D-REHOME PowerShell side |
| Spec-AC-16 | WHEN the parity driver runs --scenario UP-01, UP-02 and UP-03 with twins sh, ps1 and node against the committed allowlist the system SHALL exit 0 with verdict PASS, pairs exactly sh:ps1 and sh:node in each update scenario and no divergence on sh:node, node present only in update and bootstrap scenarios, no new allowlist row and win-sh-odd-root-dirs paired sh:ps1,sh:node; a fake node twin with peers that writes one more byte SHALL fail naming sh:node; the real-registry unit test SHALL pass and spec-amend list SHALL hold the SPEC-0284 record. | planned | — | — | D-PARITY; H2 on Windows |
| Spec-AC-17 | WHEN this checkout is synced with aai-sync.sh --profile core into a scratch target the system SHALL vendor the module and both launchers, and bash, sh and pwsh runs of the vendored launchers against a scratch fixture source SHALL each exit 0 with normalized-equal trees, while sh without node on PATH SHALL exit 1 with the refusal line and leave the tree unchanged. | planned | — | — | D-INSTALL |
| Spec-AC-18 | Wiring per D-WIRE: select-suites SHALL route the module, both launchers, both reference copies, the node:test file and the Pester file to aai-update-node, and every row listing aai-update.sh SHALL list aai-update.mjs; the weights row SHALL be 196 with its fallback line; hygiene test_090 SHALL pin 139 and test_129 pass; the cd-subshell baseline SHALL hold 1 for aai-update.sh; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps SHALL exit 0; PROFILES core SHALL list aai-update.mjs; both ps1-quality path lists SHALL be identical and hold the D-WIRE entries with win-fallback test_034 passing. | planned | — | — | D-WIRE |
| Spec-AC-19 | CHANGELOG.md SHALL hold the D-DOCS heading exactly once with a body naming Node.js 22, DR-2, DR-3, DR-5, DR-7 and DR-12; SKILL_UPDATE.prompt.md SHALL hold the D-DOCS sentence and bullet once each with both launcher lines unchanged, and test-aai-prompt-diet.sh test_012, the pr-preflight growth case and the suite-reuse growth case SHALL pass; the RFC-0017 phase 5 row SHALL keep status in progress and hold the D-DOCS sentence once with a link ending update-on-node.md, and expert-fetch test_2624 SHALL pass. | planned | — | — | D-DOCS |

## Implementation plan

TDD in seven runs (D-SLICES); each run stores RED under
`docs/ai/tdd/update-on-node/red/` before its change and GREEN under
`green/`, and one mutation record per row (`node
.aai/scripts/mutation-run.mjs`, records under
`docs/ai/tdd/spec-update-on-node/`) before the run's hand-off. New files:
the module, `tests/fixtures/aai-update-reference/aai-update.sh` and `.ps1`,
`tests/skills/lib/update-reference.mjs`, `tests/skills/lib/aai-update.test.mjs`
(optionally `tests/skills/lib/aai-update-fixtures.mjs`),
`tests/skills/test-aai-update-node.sh`.

Edge cases: a target path with a space (U22, Pester case 1); a symlinked
working directory and a stale `PWD`; a relative `../src` source; a local
source on another branch than `--ref`; an upper-case origin; a pin with a
byte order mark and CRLF lines; two conflict reports with one mtime; a sync
that exits nonzero or throws; git absent from PATH; gh present but failing;
`--repo` at the end of the arguments; a PowerShell caller with
`$PSNativeCommandUseErrorActionPreference` on (TEST-3580 to TEST-3583 run
through it); Windows paths handed to Git Bash as `C:/...` (H2 only).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3960 | Spec-AC-01 | unit | tests/skills/test-aai-update-node.sh | test_3960_scratch_safety runs run_node_tests TEST-3960 (removeOwnScratch refuses each D-SAFETY case and removes a marked own directory; both reference copies hash to their pins and equal git show 30c983ef of the twins when that object exists), checks safe_rm_own refuses an empty, relative, foreign, symlinked and unmarked path, scans the new test files for docker, pkill and killall calls, and checks every update invocation helper in them sets GIT_ALLOW_PROTOCOL=file and an empty GH_CONFIG_DIR and asserts its repo argument lies under the own scratch root | `sed:s/const OWN_SCRATCH_PREFIX = 'aai-up-';/const OWN_SCRATCH_PREFIX = '';/` on tests/skills/lib/update-reference.mjs | green |
| TEST-3961 | Spec-AC-02 | inspection | tests/skills/test-aai-update-node.sh | test_3961_module_shape runs run_node_tests TEST-3961: import in a scratch cwd creates nothing and prints nothing; the export list; only node: imports and none of the network modules; each anchor once; one spawnSync call; no process.stdout or process.stderr; no relocation copy or node missing text; ASCII only | `sed:s/const writeFd = \(fd\) => \(s\) => \{ fs.writeSync\(fd, s\); \};/const writeFd = (fd) => (s) => { process.stdout.write(s); };/` on .aai/scripts/aai-update.mjs | green |
| TEST-3962 | Spec-AC-03 | unit | tests/skills/test-aai-update-node.sh | test_3962_cli_and_base runs run_node_tests TEST-3962: every accepted form in mixed order with the last wins rule, help equal to the reference help plus the two DR-1 lines, unknown argument with exit 1 and no spawn recorded, a trailing and an empty value flag with exit 1 and the DR-3 line, the case-insensitive PowerShell names and a refused abbreviation, resolveBase with a matching PWD, a stale PWD, a relative dot-dot repo and CDPATH set | `sed:s/const EXIT_USAGE = 1;/const EXIT_USAGE = 0;/` on .aai/scripts/aai-update.mjs | green |
| TEST-3963 | Spec-AC-04 | unit | tests/skills/test-aai-update-node.sh | test_3963_canonical_guard runs run_node_tests TEST-3963: normSlug on slug, https, ssh, upper-case host and suffix, two github.com occurrences, a path and an empty value; refusal lines and exit 2 with no temp directory and no sync spawn; no refusal with force, a local directory, another repository or no origin | `sed:s/const SLUG_CASE_FLAGS = 'i';/const SLUG_CASE_FLAGS = '';/` on .aai/scripts/aai-update.mjs | green |
| TEST-3964 | Spec-AC-05 | unit | tests/skills/test-aai-update-node.sh | test_3964_source_resolution runs run_node_tests TEST-3964 with an injected spawn: the three local-checkout commands in a real run and none in a dry-run; cloneUrl per DR-22; the three clone argv in order into tmp/src, a partial clone planted at attempt 1 gone at attempt 2, the tmp inode unchanged; GIT_TERMINAL_PROMPT only on attempt 3; stdio ignore for git and gh; exit 3 with the auth line, exit 3 with the DR-18 line when git cannot start, and a local checkout synced with exit 0 when git cannot start | `sed:s/const SRC_SUBDIR = 'src';/const SRC_SUBDIR = '';/` on .aai/scripts/aai-update.mjs | green |
| TEST-3965 | Spec-AC-06 | unit | tests/skills/test-aai-update-node.sh | test_3965_temp_lifecycle runs run_node_tests TEST-3965: real runs ending in success, exit 3, exit 4, a failing sync and a thrown injected error leave no aai-src. entry in an injected tmpdir; --keep-temp keeps exactly one; removeOwnTemp keeps and reports a different path, a foreign prefix, a symbolic link and a moved parent; dry-run, usage error and refusal create none | `sed:s/if \(!state.keepTemp && state.tmp\) removeOwnTemp/if (false) removeOwnTemp/` on .aai/scripts/aai-update.mjs | green |
| TEST-3966 | Spec-AC-07 | unit | tests/skills/test-aai-update-node.sh | test_3966_runner_and_sync runs run_node_tests TEST-3966: resolveRunner for bash, an absolute bash.exe path, pwsh and powershell.exe paths, unset on posix and win32, and a refused value; syncCommand on posix and win32 (forward slashes, Bypass on win32 only); exit 4 naming the runner's sync file; sync exit 5 passed through with no evidence; the runner variable absent from the sync and helper environment; both Would run lines | `sed:s/const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER';/const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER_X';/` on .aai/scripts/aai-update.mjs | green |
| TEST-3967 | Spec-AC-08 | unit | tests/skills/test-aai-update-node.sh | test_3967_rendering runs run_node_tests TEST-3967: the dry-run block for a local and a remote source, the sync header, changed files with count and the none line, pin lines with mixed case, a BOM and CRLF, a non-file pin, conflict reports by mtime and by name on a tie with a directory of the same name ignored, both Recommended forms; expected bytes captured once from the bash reference and committed in the test | `sed:s/'commit', 'canonical', 'ref'\]/'commit', 'canonical']/` on .aai/scripts/aai-update.mjs | green |
| TEST-3968 | Spec-AC-09 | unit | tests/skills/test-aai-update-node.sh | test_3968_doctor_postamble runs run_node_tests TEST-3968: helper absent, a directory in its place, exit 0, exit 1, a signal and a start failure through the injected spawn give the D-DOCTOR lines with the run's exit code 0; the helper argv is process.execPath, the helper path, --root and the target; no helper spawn in a dry-run or after a failed sync | `sed:s/DOCTOR-REPORT SKIP helper crashed - update unaffected/DOCTOR-REPORT SKIP helper failed - update unaffected/` on .aai/scripts/aai-update.mjs | green |
| TEST-3969 | Spec-AC-10 | integration | tests/skills/test-aai-update-node.sh | test_3969_corpus_bash needs bash and git and runs run_node_tests TEST-3969: every bash-side D-CORPUS case, comparing exit, stdout, stderr, the normalized tree, the source branch and HEAD, the TMPDIR listing and the gh log after the registered rewrites, with the asserted divergences and a failure for a registered rewrite that changes nothing | `sed:s/## Post-sync evidence/## Post sync evidence/` on .aai/scripts/aai-update.mjs | green |
| TEST-3970 | Spec-AC-11 | integration | tests/skills/test-aai-update-node.sh | test_3970_corpus_powershell needs pwsh (need_tool) and runs run_node_tests TEST-3970: every PowerShell-side D-CORPUS case against the frozen PowerShell reference with the module on the pwsh runner, after the registered rewrites, with the asserted divergences | `sed:s/aai-sync.ps1 -TargetRoot "/aai-sync.ps1 -Target "/` on .aai/scripts/aai-update.mjs | green |
| TEST-3971 | Spec-AC-12 | integration | tests/skills/test-aai-update-node.sh | test_3971_sh_launcher checks the launcher text (at most 20 lines, ASCII, mode 100755, no policy token), runs a copy beside a stub module under bash, sh and dash (dash through need_tool) with a spaced repo value, both flag forms and -h and requires the argv, the runner value bash and exit 7 through, then with PATH holding only dirname and with the module removed requires exit 1, the exact refusal line and an unchanged target | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE"/` on .aai/scripts/aai-update.sh | done |
| TEST-3972 | Spec-AC-13 | integration | tests/skills/test-aai-update-node.sh | test_3972_ps1_launcher checks the .ps1 text (at most 20 lines, ASCII, no param block, no policy token), then needs pwsh and Pester 5 and runs Invoke-Pester on tests/skills/aai-update.Tests.ps1 filtered to the launcher context under env -u AAI_ROLE requiring 5 passed, 0 skipped, 0 failed and 0 failed containers | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/aai-update.ps1 | pending |
| TEST-3973 | Spec-AC-14 | integration | tests/skills/test-aai-update-node.sh | test_3973_rehomed_bash_suites runs the selectors test-aai-update.sh test_001_clone_target_is_srcdir, test_002_no_midrun_rm_tmp, test_003_bash_syntax_check, test_004_dry_run_happy_path, test_005_integration_file_fixture_clone, test_006_0137_update_writes_field_report, test_008_0137_induced_failure_update_runs, test_010_0137_timeout_and_zero_network and test_014_0137_ps1_parity_structural, test-aai-layer-drift.sh test_ps1_parity and test-aai-hygiene-pack.sh test_128_shipping_scripts_pipe_safe_at_zero, each exit 0; a forced failing copy of test-aai-update.sh leaves no aai-update-suite. directory; reads spec-amend list --json for the SPEC-0124, SPEC-0020, SPEC-0179 and first SPEC-0052 records of ref update-on-node | `sed:s/export function doctorReport\(/export function doctorReportX(/` on .aai/scripts/aai-update.mjs | done |
| TEST-3974 | Spec-AC-15 | integration | tests/skills/test-aai-update-node.sh | test_3974_rehomed_pester needs pwsh and Pester 5, runs Invoke-Pester on the whole tests/skills/aai-update.Tests.ps1 under env -u AAI_ROLE requiring 0 failed, 0 skipped and 0 failed containers, checks the five retired cases are absent by name and the robustness, TEST-009 and TEST-3584 edits are present, reads spec-amend list --json for the second SPEC-0052 and the SPEC-0285 records, and requires follow-ups to list fu-update-test-3589-isolation and fu-update-missing-git-msg as closed | `sed:s/Unknown argument: /Unknown option: /` on .aai/scripts/aai-update.mjs | pending |
| TEST-3975 | Spec-AC-16 | integration | tests/skills/test-aai-update-node.sh | test_3975_parity_update needs pwsh, runs the driver with --scenario UP-01, UP-02 and UP-03 and twins sh,ps1,node into a scratch report and requires exit 0, verdict PASS, pairs exactly sh:ps1 and sh:node per update scenario with no sh:node divergence and node only on UP and BS scenarios; runs run_node_tests TEST-3975 in install-parity.test.mjs for the peers rule (a fake node twin with peers that writes one more byte fails naming sh:node), the real-registry argv test and the widened row; requires the SPEC-0284 record | `sed:s/peers: { update: \['sh'\] }/peers: { update: ['sh', 'ps1'] }/` on tests/skills/lib/install-parity.mjs | pending |
| TEST-3976 | Spec-AC-17 | integration | tests/skills/test-aai-update-node.sh | test_3976_scratch_install syncs this checkout with --profile core into a scratch git target, requires the module and both launchers vendored, runs bash, sh and pwsh (need_tool) launchers against a scratch fixture source on three fresh copies at one path with equal normalized trees, then sh with PATH holding only dirname exits 1 with the refusal line and an unchanged tree | `sed:s/  - .aai\/scripts\/aai-update.mjs\n//` on .aai/system/PROFILES.yaml | pending |
| TEST-3977 | Spec-AC-18 | inspection | tests/skills/test-aai-update-node.sh | test_3977_wiring pipes the module, both launchers, both reference copies, the node:test file and the Pester file to select-suites.mjs --files-from - and requires aai-update-node each time; requires every suite-map row naming aai-update.sh to name aai-update.mjs; requires the weights row 196 with its fallback line; runs hygiene-pack test_090_suite_map_pin and test_129_mutation_gate_suite_registration and win-fallback test_034 selectors; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the baseline row 1 for aai-update.sh, PROFILES core listing aai-update.mjs, and identical ps1-quality path lists holding the D-WIRE entries | `sed:s/  aai-update-node:/  aai-update-node-gone:/` on tests/skills/suite-map.yaml | pending |
| TEST-3978 | Spec-AC-19 | inspection | tests/skills/test-aai-update-node.sh | test_3978_docs requires the CHANGELOG heading once with Node.js 22, DR-2, DR-3, DR-5, DR-7 and DR-12 in its body, the SKILL_UPDATE sentence and bullet once each with both launcher lines present, the RFC-0017 phase 5 row in progress holding the D-DOCS sentence once with a link ending update-on-node.md, and runs test-aai-prompt-diet.sh test_012, the pr-preflight and suite-reuse growth selectors and expert-fetch test_2624_inventory_matches_tree (exit 0) | `sed:s/The fifteenth slice \[moved the layer updater to Node\]/The fifteenth slice [moved update]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |

Test counts by type: unit 8, integration 8, inspection 3 (19 rows). The
re-homed rows of other specs (D-REHOME) keep their own ids and mutations.

Seams crossed (Principle 2): the module against both frozen twins on the
same fixtures (TEST-3969, TEST-3970: stdout, stderr, exit, tree, source
checkout, TMPDIR, gh log); the module against the shared children it does
not own, the source's `aai-sync.sh` and `aai-sync.ps1` (real runs in the
parity harness, TEST-3975; stubs in the corpora) and the target's
`update-doctor-report.mjs` (real helper in the corpora and in
test-aai-update.sh test_006 and test_008, TEST-3973); the launchers against
the module, the runner hint and an environment without Node (TEST-3971,
TEST-3972, natively on Windows in H1); `update-check.mjs`, which spawns the
`.sh` launcher, against the module (test-aai-update-check.sh TEST-003 and
TEST-004 in the sweep); aai-sync vendoring the module through PROFILES into
a target whose launchers then run it (TEST-3976); the parity driver's twin
registry, the PowerShell launcher and the bash reference on native Windows
(TEST-3975 and H2); select-suites, the hygiene pins, the ratchets and the
ps1 path-filter derivation reading the new files (TEST-3977); the RFC
inventory and the prompt-diet ledger and its two mirrors reading the docs
(TEST-3978).

RED observations (stored under `docs/ai/tdd/update-on-node/red/`):
TEST-3960 to TEST-3970 fail on the baseline because the reference copies,
their helper, the node:test file and the module do not exist; TEST-3971
fails because the `.sh` is still the bash twin (more than 20 lines);
TEST-3973 fails on the re-homed selectors after the `.sh` swap and before
their edits (the run 5 order makes this the RED); TEST-3972 and TEST-3974
fail because the `.ps1` is still the twin and the Pester edits are absent;
TEST-3975 to TEST-3978 fail because the peers field, the vendoring, the
suite row and the docs are absent.

Hosted checks (CI, not Test Plan rows; recorded in the validation report
from the PR's ps1-quality run):

- H1: `windows-5_1` (Windows PowerShell 5.1 and pwsh 7) and `windows-wsl1`
  full-suite steps report `aai-update.Tests.ps1` passed including the five
  launcher cases, skipped count still 4, TotalCount at or above 111, no
  failed container, elapsed under 600 s.
- H2: the `windows-parity` job's two steps pass with UP-01 in the smoke
  report compared on pairs sh:ps1 and sh:node, the node twin present, at
  most the widened `win-sh-odd-root-dirs` row covering an update
  divergence on sh:node; `AAI-PARITY-ELAPSED` recorded for each engine.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-update-node.sh`
  exits 0 (19 rows), plus the touched and selected suites run the same way:
  test-aai-update.sh, test-aai-update-check.sh, test-aai-layer-drift.sh,
  test-aai-install-parity.sh, test-aai-hygiene-pack.sh,
  test-aai-win-fallback.sh, test-aai-prompt-diet.sh,
  test-aai-pr-preflight.sh, test-aai-suite-reuse.sh,
  test-aai-expert-fetch.sh, test-aai-layer-profiles.sh, test-aai-doctor.sh,
  test-ps1-quality.sh; then the full sweep once before close with
  `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/aai-update.test.mjs` and
  `env -u AAI_ROLE node --test tests/skills/lib/install-parity.test.mjs`
  exit 0 (also under Node 22, as the skill-suite Node 22 step runs every
  `tests/skills/lib/*.test.mjs`; the PowerShell-side corpus fails on CI and
  names the tool when pwsh is missing, and skips with a named reason
  locally).
- Hosted checks H1 and H2 from the PR's ps1-quality run; a divergence that
  appears only on Windows gets an allowlist row and a follow-up in a
  remediation pass, never a normalization.
- `node .aai/scripts/spec-lint.mjs --path <this spec>`,
  `node .aai/scripts/mutation-gate.mjs` for this spec and
  `node .aai/scripts/spec-amend.mjs list --strict` pass.

## Evidence contract

ref_id `update-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/update-on-node/` and `docs/ai/tdd/spec-update-on-node/`
(gitignored); each AC row's Evidence names its green log and mutation
record; the validation report and review verdict under `docs/ai/reports/`
and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- The bash runner on win32 (forward-slash paths handed to Git Bash, H2's
  sh:node pair) and gh's refusal without a config directory on Windows
  (Pester clone cases) are not verified at planning; a hosted failure is a
  remediation-pass row or fix, never a normalization.
- The frozen PowerShell reference runs only in the POSIX corpus with pwsh 7;
  Windows PowerShell 5.1 behaviour of the PowerShell path is proven only
  through sh:ps1 in the parity harness and the Pester real-run case
  (`fu-update-ps1-ref-not-run-on-windows`).
- `fs.writeSync` on a descriptor a parent made non-blocking can raise
  EAGAIN; the module never touches `process.stdout`, so Node leaves the
  descriptor as inherited. A signal during a blocking clone or sync is
  handled after the child returns; a SIGKILL leaves the temp clone behind
  (as with both twins).
- Removing a clone on Windows relies on `fs.rmSync` handling read-only pack
  files; the hosted Pester clone cases exercise it.
- TEST-3569's reference-host bounds (150 s default, 75 s smoke) now include
  the node twin on UP-01 (estimate: under 6 s added); if a reference-host run
  exceeds a bound, the remediation moves a scenario's tier by a recorded
  edit, never the bound.
- A downstream project without Node can no longer update through the new
  launchers; the first update from an older layer still runs the old twin,
  and only the next one needs Node. This is the owner's decision, disclosed
  in the CHANGELOG.
- The corpora's runtime is not measured at planning (estimate: about 90 s
  for both sides with stub syncs); the suite weight 196 is the fallback.
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope: fu-update-test-3589-isolation (TEST-3589 retired with the PowerShell native-call class it tested) and fu-update-missing-git-msg (DR-18).

Items this scope leaves open, with reasons: `fu-parity-win-odd-root-dirs`
(its cause is the bash reference's doctor run under Git Bash, which the
harness keeps running; the row widens to sh:node and H2 shows whether the
module twin is free of it), the other `fu-parity-*` sync items (the sync is
ride 12), `fu-parity-node22-step-wire` (the Node 22 step will also run the
new node:test file; its time is reported in the validation report),
`fu-platform-record-doctor-update-drift` (a feature, not this port).
