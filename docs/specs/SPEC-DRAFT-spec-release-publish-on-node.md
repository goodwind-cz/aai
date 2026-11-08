---
id: spec-release-publish-on-node
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 83ffebe9db3e873a7ee1cc776026ffb531afe065071a61d015acfc5390cdd104
ceremony_level: 2
links:
  requirement: release-publish-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run the whole aai-release command in Node, with the release host calls on the platform adapter

SPEC-FROZEN: true

## Links

- Requirement: [Run the whole aai-release command in Node, with the release host calls on the platform adapter](../issues/CHANGE-DRAFT-release-publish-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 6, slice (b) of two (the owner merges).
- Slice (a): [CHANGE-0251](../issues/CHANGE-0251-release-on-node.md) and
  [SPEC-0281](SPEC-0281-spec-release-on-node.md) (`release-cut.mjs` with
  `plan`, `check` and `roll`; its drift table DR-01 to DR-22; the drifts it
  left for this slice).
- Pattern precedents: the reaper port [CHANGE-0241](../issues/CHANGE-0241-node-first-reap-tests.md)
  and ride 3 [SPEC-0276](SPEC-0276-spec-cloudflare-share-on-node.md)
  (one Node module, permanent thin launchers, `run(argv, deps)` seam, one
  test case per drift).
- Provider adapter reused: `.aai/scripts/lib/platform-adapter.mjs`
  (`resolvePlatform`, `createAdapter`, `authStatus`), from
  spec-git-platform-detected-at-bootstrap.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, `node:test`,
  bash suites, Pester 5).
- Baseline: main `c88cf708`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs for the
  phase 5 rides. This slice replaces behaviour on a shipped, consumer-visible
  core command whose confirm arm writes branches and talks to a git host;
  every drift decision is a behaviour that must be seen failing first on
  the baseline, and every inspection row (launchers, wiring, RFC, skill,
  budget) is RED on the baseline too. Every row carries a mutation record.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped core scripts, a new core
  module, release-finish.mjs, the shared platform adapter, a skill prompt,
  PROFILES, a CI workflow path list, an umbrella RFC, CHANGELOG and several
  suites; the main checkout is shared and holds unrelated uncommitted files.
- User decision: worktree (autopilot default 2, rationale "autopilot
  default"; no touched path is in `protected_paths_l3` and the
  recommendation is not `required`)
- Base ref: main
- Worktree branch/path: refactor/release-publish-on-node at /Users/ales/Projects/aai-worktrees/release-publish-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/aai-release.mjs .aai/scripts/aai-release.sh
  .aai/scripts/aai-release.ps1 .aai/scripts/release-finish.mjs
  .aai/scripts/lib/platform-adapter.mjs .aai/SKILL_RELEASE.prompt.md
  .aai/system/PROFILES.yaml .github/workflows/ps1-quality.yml CHANGELOG.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/product/release-command-finish.md docs/ai/roadmap.yaml
  tests/skills/test-aai-release-cut.sh tests/skills/lib/aai-release.test.mjs
  tests/skills/release-cut.Tests.ps1 tests/skills/aai-release.Tests.ps1
  tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/lib/pester-native-capture.ps1
  tests/skills/test-aai-release.sh tests/skills/test-aai-learned-routing.sh
  tests/skills/suite-map.yaml tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/issues/CHANGE-DRAFT-release-publish-on-node.md
  docs/specs/SPEC-DRAFT-spec-release-publish-on-node.md docs/INDEX.md
  (cd-subshell-leak-baseline.tsv only if the ratchet asks for a row;
  tests/skills/aai-release.Tests.ps1 is deleted).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2, BSD `/usr/bin/grep`,
Node 22, pwsh 7.6, git) on 2026-11-08 at `c88cf708`, by running both scripts
against scratch git fixtures with a stub `gh` first on PATH. Windows
PowerShell 5.1 was not available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`; `//`
instead of `#` for JavaScript).

| File | Total lines | Code lines | Git mode |
|---|---|---|---|
| aai-release.sh | 182 | 119 | 100755 |
| aai-release.ps1 | 255 | 200 | 100644 |
| release-cut.mjs | 216 | 178 | 100644 |
| release-finish.mjs | 694 | 632 | 100644 |
| lib/platform-adapter.mjs | 304 | 250 | 100644 |
| tests/skills/aai-release.Tests.ps1 | 60 | 26 | 100644 |

Before: 319 code lines over the two scripts (641 before slice a). The
`Describe 'aai-release.ps1'` block of `tests/skills/aai-win-dispatch.Tests.ps1`
spans lines 972 to 1156 (185 lines).

### Where each remaining step lives today

| Step | Today | After this slice |
|---|---|---|
| arguments, `--dry-run` wins over `--confirm`, environment twins | each script | `aai-release.mjs` |
| repository check (10), CHANGELOG check (11), version | each script | `aai-release.mjs` |
| remote `--confirm` hand-off to `release-finish.mjs` | each script | `aai-release.mjs` (spawns the same command) |
| gh probe for the plan, target branch | each script | `aai-release.mjs` through the platform adapter |
| plan, `check`, `roll` | `release-cut.mjs` | `release-cut.mjs`, called in process by `aai-release.mjs` |
| release branch reuse, temporary worktree, `AAI_VERSION.md`, commit, cut report | each script | `aai-release.mjs` |
| push, release PR create, edit, view, merge, required checks, workflow and release reads | `release-finish.mjs`, 23 direct `gh` call sites (5 `command('gh', ...)`, 3 `gh(...)`, 14 `json(...)`, 1 `readCurrentChecks` with the default runner) | `release-finish.mjs` through the release operations of the platform adapter |
| tag and publish | CI `.github/workflows/release.yml` on merge | unchanged (out of scope) |

Found while reading: neither script tags, publishes or opens a PR itself.
The remote `--confirm` hands off to `release-finish.mjs`, which pushes and
binds the release PR; the tag and the GitHub release are made by the CI
workflow `release.yml` after the merge, and `release-finish.mjs` only reads
them back to verify. "Tag, publish and PR on the platform adapter" therefore
means the host calls of `release-finish.mjs`. The workflow is GitHub Actions
and is not a vendored file; it stays as it is.

### Observed on the baseline (fixture outputs)

| Case | .sh at c88cf708 | .ps1 at c88cf708 |
|---|---|---|
| `--bogus` | the whole usage comment on stdout, `Unknown argument: --bogus` on stderr, exit 1 | `Unknown argument: --bogus` on stderr, exit 1 |
| `-h`, `--help` | usage on stdout, exit 0 | `Unknown argument: -h`, exit 1 |
| `--version=v9` | `Unknown argument: --version=v9`, usage, exit 1 | accepted, plan for v9 |
| `--version --no-remote` | `--no-remote` taken as the version, plan for `--no-remote`, exit 0 | engine binder error, exit 1 |
| `--confirm --no-remote --version "v 1"` | `fatal: 'chore/release-v 1' is not a valid branch name`, exit 255 | PowerShell exception dump of `Invoke-NativeChecked`, exit 1 |
| release branch exists with unmerged commits | `REFUSED: branch chore/release-v9 already exists with unmerged commits (other work).`, exit 12 | same line, exit 12 |
| a git step of the cut fails (commit without identity) | git's stderr, exit 128, branch left at the base | an exception from `Invoke-NativeChecked`, exit 1 |
| cut report header | `## aai-release — cut complete` | `## aai-release - cut complete` (Write-Host) |
| cut report Remote line | names the release SHA | no SHA, ASCII ` - ` |
| `AAI_VERSION.md` bytes | LF, final newline | same on macOS; `Set-Content` writes the platform newline, so CRLF at the end on Windows (source reading) |
| remote `--confirm` with no node on PATH | `REFUSED: missing-node — Node.js is required for release finish` and a bash Resume line, exit 20 | ASCII ` - `, a pwsh Resume line, exit 20 |
| not a git repository | `cwd=` the logical `pwd` (`/var/...`) | the provider path (`/private/var/...`) |

Every other observed case printed the same line and exit code on both.

### Callers and references (tracked files; docs history, CHANGELOG history and test results excluded)

- `.aai/SKILL_RELEASE.prompt.md` and the three `aai-release` harness wrappers
  run `.aai/scripts/aai-release.sh` / `.ps1` by name; the product doc
  `docs/product/release-command-finish.md` shows both command lines.
  `release-finish.mjs` and `release-cut.mjs` print Resume lines that name
  the scripts. These names stay (D-LAUNCH).
- `tests/skills/aai-release.Tests.ps1` and the `Describe 'aai-release.ps1'`
  of `tests/skills/aai-win-dispatch.Tests.ps1` dot-source the `.ps1` for
  `Invoke-NativeChecked` and `Select-CapturedValue` and pin its cut-path
  calls; those functions go with the cut logic (D-TESTS).
- `tests/skills/test-aai-release.sh`: TEST-019 greps the `.ps1` for
  `AAI_RELEASE_DATE` and `AAI_RELEASE_NO_REMOTE`, which move to Node; the
  helper-closure case near line 2167 copies the scripts into a scratch tree;
  TEST-034 reads the literal `exit N` lines of the `.sh`; TEST-109 caps
  SKILL_RELEASE at 4921 bytes (its size at `c88cf708`); TEST-033 and
  TEST-700 drive the remote finish through a `gh` transport stub on PATH.
- `tests/skills/test-aai-learned-routing.sh` TEST-002 copies the scripts and
  their closure into a scratch tree.
- `tests/skills/test-aai-release-cut.sh` (slice a): TEST-3470, TEST-3471,
  TEST-3472 and TEST-3477 pin the scripts' slice-(a) internals (three
  `release-cut.mjs` calls in the `.sh`, the `.ps1` helpers, the two Pester
  files above, budgets of 160 and 220); TEST-3476 requires an `aai-release`
  row in the RFC-0017 pair table, which leaves the table once
  `aai-release.mjs` exists (`test-aai-expert-fetch.sh` TEST-2624: a pair is
  `.sh` plus `.ps1` with no `.mjs`).
- `.aai/scripts/lib/platform-adapter.mjs` is read by `merge-cleanup.mjs`,
  `ride-status.mjs`, `platform.mjs` and `aai-bootstrap`; the suites
  `aai-platform-adapter`, `aai-merge-cleanup` and `aai-bootstrap` map it.
- Importing the adapter adds `pr-platform.mjs`, `lib/cli-pipe-guard.mjs` and
  `lib/docs-model.mjs` to the closure that fixtures copying the release
  scripts must copy; all are `core` in PROFILES.

### Coordination

- SPEC-0257 session (release dry-run corpus): this slice does not edit
  `release-dry-run.mjs`, `lib/release-rollup.mjs`,
  `tests/skills/test-aai-release-first.sh` or
  `tests/skills/lib/release-first.test.mjs`. Read only, on 2026-11-08:
  `/private/tmp/aai-release-corpus-hermetic` has uncommitted edits to
  `tests/skills/aai-win-dispatch.Tests.ps1` in hunks near lines 30, 103,
  932 to 938 and 1439; this slice deletes lines 972 to 1156 of the same file
  (a disjoint hunk). Whichever branch merges second rebases.
- The new `tests/skills/lib/aai-release.test.mjs` names CHANGELOG, so
  `release-dry-run.mjs --list` counts it as one more reader; it must pass in
  the rolled arm and finish in under 60 seconds.
- Ride 7 (`hook-gate-on-node`) may run in parallel: no hook-gate file is
  touched. TEST ids start at 3520 to leave 3479 to 3519 to a parallel ride.

## Decisions

### D-SCOPE. What moves

1. All remaining steps of the two scripts move to one new module,
   `.aai/scripts/aai-release.mjs` (D-MOD). `release-cut.mjs` keeps its
   `plan`, `check` and `roll` commands and its CLI unchanged; `aai-release.mjs`
   calls its exported `run` in process with the same arguments the scripts
   pass today.
2. The host calls of `release-finish.mjs` move onto a `release` operation
   group of the GitHub adapter in `lib/platform-adapter.mjs` (D-HOST). The
   `gh` command lines, spawn options and every refusal line on GitHub stay
   byte for byte; the existing `gh` transport stubs of `test-aai-release.sh`
   prove it.
3. Azure DevOps and the generic adapters get no release group. A release on
   such a repository refuses by name before any host call or write
   (DB-15 to DB-18); `--confirm --no-remote` cuts locally on every platform.
   An Azure release finish is a follow-up, not this slice.
4. Out of scope, named: `.github/workflows/release.yml`; `watch-ci.mjs`,
   which `release-finish.mjs` spawns and which calls `gh` itself
   (`fu-platform-adapter-watch-ci`); `lib/github-checks.mjs` itself (it
   already takes a `run` seam, which the release group supplies);
   SKILL_PR's gh-only text (`fu-platform-adapter-skill-pr-release`).

### D-LAUNCHERS. Keep, as permanent thin launchers (recommendation)

`aai-release.sh` and `aai-release.ps1` stay, permanently, as thin launchers
of `aai-release.mjs`; they are not retired and get no deprecation notice.

- They are the entry points users and agents type: SKILL_RELEASE, the three
  harness wrappers, the product doc, the Resume lines printed by
  `release-finish.mjs` and `release-cut.mjs`, and downstream habits all name
  them. Retiring them would move every caller to
  `node .aai/scripts/aai-release.mjs` and drop the PowerShell parameter
  syntax (`-Version`, `-Confirm`, `-NoRemote`).
- The precedents of this phase did the same: `aai-reap-tests` and
  `cloudflare-share` kept permanent `.sh`/`.ps1` launchers over one module.
- The owner decision of 2026-11-05 (one release as a deprecation launcher)
  applies to retired scripts. These are not retired: the plan's "delete the
  twins" deletes the second copy of the logic, which this slice does.

### D-DRIFT. Every remaining behaviour difference, decided

Each row is pinned by exactly one test case whose name begins with the DB id
(a `node:test` case in `tests/skills/lib/aai-release.test.mjs`, or, where
marked, an `It` in `tests/skills/release-cut.Tests.ps1`). `<NR>` is
`--no-remote` for the `sh` launcher and `-NoRemote` for `ps1`.

| DB | Behaviour | .sh at c88cf708 | .ps1 at c88cf708 | Decision |
|---|---|---|---|---|
| DB-01 | unknown argument | usage on stdout, line on stderr, exit 1 | line on stderr, exit 1 | `Unknown argument: <a>` then `Run with --help for usage.` on stderr, nothing on stdout, exit 1 |
| DB-02 | `-h`, `--help` | usage, exit 0 | unknown argument, exit 1 | the D-OUT usage on stdout in the launcher's flag spelling, exit 0, nothing else runs |
| DB-03 | `--version=<v>` | unknown argument, exit 1 | accepted | accepted on both, same as `--version <v>` |
| DB-04 | `--version` with no value or followed by a flag | the next flag becomes the version, or a bash error | engine binder error | `REFUSED: --version needs a value.` exit 1 (a value that starts with `-` counts as missing) |
| DB-05 | version that is not a valid tag and branch name | the plan prints it; the cut dies in git (exit 255) | the cut dies in an exception (exit 1) | `REFUSED: invalid version '<V>' — not a valid git tag or branch name.` exit 1 in every mode, before any git write (`git check-ref-format refs/tags/<V>` and `--branch chore/release-<V>`) |
| DB-06 | release branch exists with unmerged commits | exit 12 | exit 12 | same line, exit 14 (12 stays the malformed-CHANGELOG code) |
| DB-07 | a git step of the local cut fails | git's own code (128, 255) and raw stderr | exit 1 and an exception dump | `REFUSED: git-command — git <args>: <first stderr line>` exit 20; the temporary worktree is removed |
| DB-08 | cut report header | em dash | ASCII ` - ` | `## aai-release — cut complete` on both |
| DB-09 | cut report Remote line | names the release SHA | no SHA | the `.sh` form with `<NR>`, naming the SHA, on both |
| DB-10 | cut report stream | stdout | Write-Host (information stream) | the module's stdout, relayed by the `.ps1` on its success stream (Pester) |
| DB-11 | `AAI_VERSION.md` bytes | LF, final newline | the platform newline at the end (CRLF on Windows) | the `.sh` bytes on every engine |
| DB-12 | node missing on the remote `--confirm` | own two-line refusal with a bash Resume line | ASCII ` - ` and a pwsh Resume line | the one D-LAUNCH missing-node line for every mode, exit 20, no Resume line |
| DB-13 | `cwd=` in the not-a-repository refusal | logical `pwd` | provider path | `process.cwd()` on both |
| DB-14 | SIGINT or SIGTERM during the local cut | the EXIT trap removes the worktree | `finally` removes the worktree | the module removes the temporary worktree, prints `REFUSED: interrupted (<SIG>) — the temporary worktree was removed.` and exits 130 or 143 (POSIX only; Windows is a residual risk) |
| DB-15 | plan on a repository whose platform is not GitHub (azure, or a recorded `unknown` or `none`) | probes `gh` | probes `gh` | no `gh` call; `- would block (publish path): the remote release finish runs on GitHub only (platform <p>); cut locally with <NR>` |
| DB-16 | plan when the platform record disagrees with the remote | record ignored | record ignored | `- would block (publish path): platform record does not match the remote (recorded=<r>, detected=<d>); re-record: node .aai/scripts/platform.mjs record --force` |
| DB-17 | remote `--confirm` on a non-GitHub platform | `gh` runs against the host and fails later | same | `release-finish.mjs` refuses `REFUSED: release-platform — the remote release finish runs on GitHub only (platform <p>); cut locally with --no-remote and open the release PR on your host` with exit 20 before any host call, journal, ref or push |
| DB-18 | remote `--confirm` with a platform mismatch | record ignored | record ignored | `REFUSED: platform-mismatch — recorded=<r> detected=<d>; re-record: node .aai/scripts/platform.mjs record --force` exit 20 before any host call |
| DB-19 | dot-sourcing the `.ps1` | defines the helpers, runs nothing | same | defines nothing and runs nothing; the dot-source guard stays (Pester) |

Kept identical (no row): every other flag, `--yes` and `-Yes`,
`AAI_RELEASE_DATE` and `AAI_RELEASE_NO_REMOTE`, `--dry-run` winning over
`--confirm`, exit codes 10, 11, 12, 13, 15 and 20 with their lines, the
target-branch resolution, the release-branch reuse rule (a branch whose last
subject is `chore(release): <V>` or which is merged into the base is
deleted and re-cut), the plan (`release-cut.mjs plan`, unchanged; for a
GitHub repository, recorded or assumed, the gh-block reasons
`gh CLI not found on PATH` and `gh CLI not authenticated (gh auth status failed)`
stay), the remote finish on GitHub, and the Resume lines of
`release-cut.mjs` and `release-finish.mjs`. An unrecorded platform with a
remote that is not recognisably GitHub or Azure (a local path, as every test
fixture uses) keeps resolving to GitHub (the adapter's legacy rule), so
nothing changes for those repositories.

Slice (a)'s out-of-scope drifts are all decided above: unknown arguments
(DB-01), `-h`/`--help` (DB-02), the cut report's Remote line (DB-09) and the
reuse of exit 12 (DB-06).

### D-MOD. The module

`.aai/scripts/aai-release.mjs`, Node stdlib only, no side effect on import
(the CLI runs only when the file is the entry point, the `release-cut.mjs`
guard). It imports `run` from `./release-cut.mjs` and `resolvePlatform`,
`createAdapter` from `./lib/platform-adapter.mjs`. It holds the literal
constants
`const FINISH_SCRIPT = 'release-finish.mjs';`,
`const REPORT_HEADER = '## aai-release — cut complete';`,
`const EXIT = { USAGE: 1, NOT_REPO: 10, NO_CHANGELOG: 11, BRANCH: 14, REFUSED: 20 };`
and the statement `if (o.dryRun) o.confirm = false;`, and exports:

- `parseArgs(argv)`: `{ launcher, launcherPath, version, dryRun, confirm,
  noRemote, help }` or `{ error, code }`. `--launcher sh|ps1` and
  `--launcher-path P` come first from the launcher; the user's flags follow
  verbatim. `AAI_RELEASE_NO_REMOTE=1` sets `noRemote`.
- `resolveVersion({ version, env, now })`: the explicit version, else
  `v` plus `AAI_RELEASE_DATE` with dashes turned into dots, else the UTC
  CalVer of `now`.
- `platformBlock({ root, noRemote, deps })`: the gh-block reason for the
  plan (D-DRIFT DB-15, DB-16, and the two GitHub reasons), or empty.
- `cutReport(...)` and `usage(launcher)`: the D-OUT lines.
- `run(argv, deps)`: the whole command, returning the exit code. `deps`
  holds `git(args, cwd)` returning `{ status, stdout, stderr }`,
  `finish(args)` (spawns `process.execPath` on `FINISH_SCRIPT` next to the
  module with inherited stdio and returns its exit code),
  `adapter(root)` (returns `{ resolved, adapter }` from the platform
  adapter), `cut` (the `release-cut.mjs` `run`), `readFile`, `writeFile`,
  `mkdtemp`, `rm`, `exists`, `env`, `now`, `cwd`, `out(line)`, `err(line)`.
  Tests pass fakes for the unit cases and the real wiring for the
  integration cases.

Order of `run`: arguments (1) and help; repository (10); CHANGELOG (11);
version and DB-05 (1); remote `--confirm` hands off to `FINISH_SCRIPT` with
`--root <root> --version <V> --confirm` and returns its code; otherwise the
target branch, then the plan (`cut(['plan', ...])` with the
`platformBlock` reason unless `<NR>`) or the local cut: `cut(['check',
...])`, release-branch reuse (14), `git worktree add -q -b chore/release-<V>`
in a fresh temp directory, `cut(['roll', '--file', <worktree CHANGELOG>,
...])`, `AAI_VERSION.md`, `git add`, `git commit -q -m "chore(release): <V>"`,
worktree removal, the D-OUT cut report. Any failing git step is DB-07; the
worktree is removed on every exit path and on SIGINT and SIGTERM (DB-14).
Stdout errors with `EPIPE` end the process quietly with exit 141
(`e.code === 'EPIPE'`, as in `release-cut.mjs`).

### D-HOST. The release operations on the platform adapter

The GitHub adapter of `createAdapter('github', { cwd, runner })` gains a
`release` group. Every method spawns `gh` through the adapter's injectable
`runner` with the options `release-finish.mjs` uses today, held as
`export const RELEASE_GH_OPTIONS = { encoding: 'utf8', timeout: 60000, maxBuffer: 8 * 1024 * 1024 };`
plus `cwd` and `env: process.env`, and returns the raw spawn result
(`status`, `stdout`, `stderr`, `error`) so `release-finish.mjs` keeps its own
parsing and refusal lines. The argv is the contract:

| Method | argv |
|---|---|
| `authStatus()` | `auth status` |
| `repoView()` | `repo view --json nameWithOwner` |
| `prList({ repo, head, base, state, json })` | `pr list --repo <repo> --head <b>` or `--base <b>`, `--state <state> --json <fields>` |
| `prView({ n, repo, json })` | `pr view <n> [--repo <repo>] --json <fields>` |
| `prCreate({ repo, base, head, title, bodyFile })` | `pr create --repo <repo> --base <base> --head <head> --title <title> --body-file <file>` |
| `prEdit({ repo, n, bodyFile })` | `pr edit <n> --repo <repo> --body-file <file>` |
| `prMerge({ repo, n, head })` | `pr merge <n> --repo <repo> --squash --match-head-commit <head>` |
| `api({ endpoint, paged })` | `api <endpoint>`, or `api --paginate --slurp <endpoint>?per_page=100` |
| `runList({ repo, workflow, commit, json })` | `run list --repo <repo> --workflow <workflow> --commit <commit> --json <fields>` |
| `releaseView({ repo, tag, json })` | `release view <tag> --repo <repo> --json <fields>` |
| `checksRunner()` | a `run(args)` for `readCurrentChecks` that spawns `gh <args>` with `maxBuffer` 32 MiB and timeout 60000 (the options `lib/github-checks.mjs` uses by default) |

The argument order of each method equals the argv `release-finish.mjs`
builds at `c88cf708` for that call site. The Azure and generic adapters
have no `release` group.

`release-finish.mjs` resolves the platform once, after the
`--confirm`/version checks and before `gh auth status` (and, in `--audit`
mode, only when `--online` is set): a mismatch or an invalid record refuses
`platform-mismatch` (DB-18), a platform without a release group refuses
`release-platform` (DB-17), an unrecorded legacy GitHub stays silent. Every
host call then goes through `adapter.release`; the file has no
`command('gh'`, no `gh(` or `json(` helper that spawns `gh` itself, and
passes `run: release.checksRunner()` to `readCurrentChecks`. The existing
`refuse('github-command', ...)` and `refuse('github-data', ...)` texts stay.

### D-OUT. Output contract (additions to SPEC-0281 D-OUT)

- Usage (`-h`, `--help`), first line by launcher:
  `usage: aai-release.sh [--version <v>] [--dry-run] [--confirm] [--no-remote]`
  or `usage: aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote]`;
  the following lines name `--yes` / `-Yes`, the CalVer default with
  `AAI_RELEASE_DATE`, `AAI_RELEASE_NO_REMOTE=1`, and
  `Exit codes: see .aai/SKILL_RELEASE.prompt.md`.
- Refusals (stderr, one line, exit code in brackets): DB-01 (1, two lines),
  DB-04 (1), DB-05 (1), DB-06 (14), DB-07 (20), DB-14 (130, 143), DB-17 and
  DB-18 (20, followed by the existing `release-finish.mjs` Resume line).
- Cut report (stdout):

```
## aai-release — cut complete
- Version: <V>
- Commit:  <short sha>
- Release branch: chore/release-<V> (<sha>)
- Remote:  SKIPPED (<NR>/AAI_RELEASE_NO_REMOTE=1) — release branch chore/release-<V> created locally at <sha>
```

- `docs/ai/AAI_VERSION.md` of the cut: the eight lines the `.sh` writes at
  `c88cf708`, LF, with a final newline.

### D-LAUNCH. The two launchers

Both keep their names, modes (100755 and 100644) and every flag and
environment variable. They hold no release logic: no git, gh, version,
CHANGELOG or worktree handling.

- `aai-release.sh`: a POSIX `sh` launcher in the `aai-reap-tests.sh` shape.
  It resolves `aai-release.mjs` next to itself; when `node` is on PATH and
  the module exists it runs
  `exec node "$MODULE" --launcher sh --launcher-path "$0" "$@"`; otherwise
  it prints the slice (a) line
  `REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.`
  on stderr and exits 20. At most 12 code lines.
- `aai-release.ps1`: keeps the `param` block (`Version`, `DryRun`,
  `Confirm`, `Yes`, `NoRemote`, `ExtraArgs`) and the dot-source guard
  (DB-19); maps them to `--version`, `--dry-run`, `--confirm`,
  `--no-remote` after `'--launcher', 'ps1', '--launcher-path', $PSCommandPath`,
  passes `ExtraArgs` verbatim, runs `& node $module @args` and ends with
  `exit $LASTEXITCODE`. The missing-node line is the same text (the em
  dash built with `[char]0x2014`), exit 20. It does not set
  `$ErrorActionPreference = 'Stop'` and does not redirect node's stderr, so
  a refusal keeps its exit code under Windows PowerShell 5.1 when a caller
  captures stderr (the `fu-release-ps1-eap-stop-native-stderr` class).
  `Invoke-NativeChecked`, `Invoke-Quiet` and `Select-CapturedValue` are
  deleted. At most 40 code lines.
- Budgets are upper bounds, not exact pins.

### D-TESTS. Test files

- New `tests/skills/lib/aai-release.test.mjs` (`node:test`): the DB cases,
  the seam cases and the D-HOST argv contract.
- `tests/skills/test-aai-release-cut.sh` gains the TEST-3520 to TEST-3536
  functions (no new suite, so no new suite-map row, no new weights row and
  no change to the hygiene-pack row-count literal, which reads 131 at
  `c88cf708`).
- `tests/skills/release-cut.Tests.ps1` gains the `ps1` launcher cases,
  including DB-10 and DB-19, a missing-node case, and a case that runs the launcher with
  stderr captured into a variable under `$ErrorActionPreference = 'Stop'`
  and asserts a malformed CHANGELOG still exits 12.
- Superseded slice-(a) rows: the functions `test_3470_sh_script`,
  `test_3471_ps1_script`, `test_3472_pester` and `test_3477_line_budget`
  are removed with their calls (TEST-3528, TEST-3529 and TEST-3535 replace
  them); `test_3476_rfc_and_preamble` drops only its inventory-row
  assertion (TEST-3534 replaces it). SPEC-0281 stays frozen as history.
- `tests/skills/aai-release.Tests.ps1` is deleted; the
  `Describe 'aai-release.ps1'` block and the `$script:ReleaseScript` line of
  `tests/skills/aai-win-dispatch.Tests.ps1` are deleted (their plan case is
  covered by `release-cut.Tests.ps1`). The header comment of
  `tests/skills/lib/pester-native-capture.ps1` that names the `.ps1`'s
  `Invoke-NativeChecked` in the present tense is reworded (comment only).
- `tests/skills/test-aai-release.sh`: TEST-019 checks behaviour instead of
  greps (the `ps1` launcher with `AAI_RELEASE_DATE=2026-07-20` plans
  `v2026.07.20`, and with `AAI_RELEASE_NO_REMOTE=1` prints the SKIPPED
  Remote line; SKIP-CASE without pwsh locally, required on CI); the
  helper-closure case copies `aai-release.mjs`, `lib/platform-adapter.mjs`,
  `pr-platform.mjs`, `lib/cli-pipe-guard.mjs` and `lib/docs-model.mjs` too.
- `tests/skills/test-aai-learned-routing.sh` TEST-002 copies the same
  closure.
- Every fixture is a fresh temp git repository with a local identity; every
  case that can reach a host puts a stub `gh` (and, for DB-15 and DB-17, a
  stub `az`) first on PATH that logs its argv, answers `auth status` with
  exit 0 and exits 1 on anything else; origins are local bare repositories,
  or a `dev.azure.com` URL that is never fetched. No case pushes to a
  network remote, opens a PR, tags or publishes.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: the `aai-release-cut` row gains
  `.aai/scripts/aai-release.mjs`, `.aai/scripts/lib/platform-adapter.mjs`,
  `.aai/scripts/pr-platform.mjs` and `tests/skills/lib/aai-release.test.mjs`;
  the `aai-release` row gains `.aai/scripts/aai-release.mjs` and
  `.aai/scripts/lib/platform-adapter.mjs` and drops
  `tests/skills/aai-release.Tests.ps1`; the `aai-learned-routing` row gains
  `.aai/scripts/aai-release.mjs`. No row is added (131 rows stay).
- `tests/skills/suite-weights.tsv`: unchanged (no new suite).
- Hygiene-pack `test_090_suite_map_pin`: stays the one literal, at 131.
- Nested-suite lint: no new allowlist row; cross-suite calls are selector
  form.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: a row only if
  `check-cd-subshell-leak.mjs` asks, recorded with `--record`.
- `check-test-registration.mjs`: every `test_*` function is called.
- `.github/workflows/ps1-quality.yml`: `- '.aai/scripts/aai-release.mjs'`
  and `- '.aai/scripts/lib/platform-adapter.mjs'` in both the push and the
  pull_request path lists (each once).
- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/aai-release.mjs` under
  `core:`, after `.aai/scripts/release-cut.mjs`.
- `check-vendored-script-deps.mjs` exits 0 (the copier fixtures above).
- Prompt corpus: `.aai/SKILL_RELEASE.prompt.md` changes by one line (D-RFC)
  with no byte growth. If its byte count changes at all, the prompt-diet
  true-up applies (`tests/skills/lib/prompt-diet-ledger.sh` entry for
  growth, the TEST-012 expectation of `tests/skills/test-aai-prompt-diet.sh`,
  and the companion pins in `test-aai-pr-preflight.sh`,
  `test-aai-legacy-migrations.sh` and `test-aai-retired-loop-runner.sh`);
  with an equal byte count none of them moves. No other `.aai/*.prompt.md`
  and no `.aai/AGENTS.md` change.
- Release-notes gate: the CHANGELOG entry below is the shipped-surface note
  for `.aai/scripts/**` and `.aai/SKILL_RELEASE.prompt.md`.

### D-RFC. RFC-0017, SKILL_RELEASE, CHANGELOG, product doc

- RFC-0017 pair table: the `aai-release` row is removed (it is no longer a
  pair). After the reaper sentence below the table, one sentence:
  `The [release slices](../issues/CHANGE-DRAFT-release-publish-on-node.md) moved aai-release to Node modules with thin launchers (pair 319 to <after> code lines).`
  with the measured after value.
- Phase 5 row: one sentence after the tenth-slice sentence and before the
  remaining-scripts-plan sentence:
  `The eleventh slice [ran the whole release command in Node](../issues/CHANGE-DRAFT-release-publish-on-node.md): aai-release.sh and aai-release.ps1 are thin launchers of aai-release.mjs, and the release host calls run on the platform adapter.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  both links at merge; checks match only the suffix
  `release-publish-on-node.md`.
- SKILL_RELEASE: the line `- exit 16 = gh absent/unauthenticated on the remote path`
  (no path emits 16: the cut-path branch was removed by slice a and the
  remote finish maps it to 20) is replaced by
  `- exit 14 = release branch exists with unmerged commits.` (the same 56
  bytes). The file stays at most 4921 bytes (TEST-109). Every value of the
  `EXIT` constants of `aai-release.mjs` and `release-cut.mjs` is documented
  as `exit N =`.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST
  row): CHANGELOG
  `## [unreleased] — refactor(release): the whole aai-release command runs in one Node module; the release host calls run on the platform adapter`
  naming the launcher decision, every DB decision a user can see (DB-01 to
  DB-18), the non-GitHub refusal, and the before and after code lines; and
  `docs/product/release-command-finish.md` updated in place.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-09 and Spec-AC-10.
- Intake AC-002 maps to Spec-AC-02, Spec-AC-03, Spec-AC-04, Spec-AC-05 and Spec-AC-08.
- Intake AC-003 maps to Spec-AC-06 and Spec-AC-07.
- Intake AC-004 maps to Spec-AC-11.
- Intake AC-005 maps to Spec-AC-10, Spec-AC-12, Spec-AC-13, Spec-AC-17 and hosted check H1.
- Intake AC-006 maps to Spec-AC-14, Spec-AC-15 and Spec-AC-16 (the launcher recommendation is D-LAUNCHERS).

## Constitution deviations

None. Article 4 (degrade and report): every refusal names its cause on
stderr with a documented exit code; a non-GitHub platform, a platform
mismatch and a missing Node are named instead of failing inside a host call.
Article 5 (additive first): both command names, flags, environment
variables, Resume commands and the GitHub remote finish stay; the changed
behaviours are listed in D-DRIFT and in the CHANGELOG; exit 14 is new and
documented. Article 2 (simplicity): no new flag or dependency; the module
reuses `release-cut.mjs`, the shared rollup and the existing adapter.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Importing .aai/scripts/aai-release.mjs in a child node with a temp cwd writes nothing and exports parseArgs, resolveVersion, platformBlock, cutReport, usage and run; run with recording fakes calls finish exactly once with the FINISH_SCRIPT path, --root, the root, --version and --confirm for a remote confirm (after the 10 and 11 checks, with no adapter, cut or git write call), and calls cut with plan and the D-MOD arguments for a bare run. | planned | — | — | — |
| Spec-AC-02 | The node:test cases DB-01 to DB-05 pass and each asserts the D-DRIFT decision of its row: the exact stdout and stderr lines, the exit code, and that no git write and no cut or finish call happened. | planned | — | — | — |
| Spec-AC-03 | WHEN aai-release.mjs runs a local cut in committed temp repositories, the node:test cases DB-06 to DB-09, DB-11 and DB-14 SHALL pass: exit 14 with the unchanged line for an unmerged release branch, exit 20 with the git-command line and no worktree left for a failing git step, the D-OUT cut report, the exact AAI_VERSION.md bytes, and after SIGTERM exit 143 with the interrupted line and git worktree list showing only the main tree. | planned | — | — | — |
| Spec-AC-04 | The node:test cases DB-12 and DB-13 pass, and for each invocation of a matrix (bare, --dry-run, --version v9, --version=v9, --yes, --dry-run --confirm, -h, --bogus, AAI_RELEASE_DATE=2026-07-20, AAI_RELEASE_NO_REMOTE=1, --confirm --no-remote) the sh launcher under bash and the ps1 launcher under pwsh print the same stdout and stderr after the flag spellings are mapped and exit with the same code. | planned | — | — | — |
| Spec-AC-05 | The node:test cases DB-15 and DB-16 pass: a plan in a fixture whose origin is a dev.azure.com URL, and one whose recorded platform is none, prints the DB-15 block line and makes no gh call; a fixture whose docs/ai/pr-config.yaml records azure under a github.com origin URL prints the DB-16 line; a GitHub fixture with gh missing or unauthenticated prints the two unchanged reasons. | planned | — | — | — |
| Spec-AC-06 | With a recording runner, every method of createAdapter github release group spawns gh with exactly the D-HOST argv and options, checksRunner spawns with maxBuffer 32 MiB, and the azure, unknown and none adapters have no release group; test-aai-platform-adapter.sh, test-aai-merge-cleanup.sh and test-aai-bootstrap.sh exit 0. | planned | — | — | — |
| Spec-AC-07 | release-finish.mjs holds no command call with gh as the executable and no helper that spawns gh itself, and passes the release checksRunner to readCurrentChecks; the node:test cases DB-17 and DB-18 pass with an empty gh and az log, no journal under the git common dir, and unchanged refs; test-aai-release.sh and test-aai-release-notes.sh exit 0 with their gh transport stubs unchanged. | planned | — | — | — |
| Spec-AC-08 | Every DB id of the D-DRIFT table begins exactly one test name across tests/skills/lib/aai-release.test.mjs and tests/skills/release-cut.Tests.ps1, and no test name there begins with a DB id the table lacks; a scratch copy with one id renamed is reported. | planned | — | — | — |
| Spec-AC-09 | aai-release.sh has at most 12 code lines, mode 100755, no git, gh, CHANGELOG, worktree or version handling, and execs node on aai-release.mjs with --launcher sh; run directly as ./.aai/scripts/aai-release.sh --dry-run in a fixture it prints the D-OUT sh plan with exit 0, and with no node on PATH it prints the D-LAUNCH missing-node line on stderr only with exit 20. | planned | — | — | — |
| Spec-AC-10 | aai-release.ps1 has at most 40 code lines, keeps the six param names and the dot-source guard, holds no Invoke-NativeChecked, Invoke-Quiet or Select-CapturedValue, no ErrorActionPreference Stop and no redirect of node stderr; tests/skills/release-cut.Tests.ps1 passes under Pester 5 with at least 10 cases and none failed or skipped, including DB-10, DB-19, a missing-node case and the captured-stderr case that exits 12. | planned | — | — | — |
| Spec-AC-11 | WHEN either launcher runs bare, --dry-run, --dry-run --confirm, --confirm --no-remote and remote --confirm in a fixture with a bare local origin and the D-TESTS gh stub, the system SHALL leave the origin refs unchanged in every case, leave working tree bytes, index, local refs and file list unchanged for the first three with no gh call other than auth status, and end the remote confirm in a release-finish.mjs refusal with no ref change. | planned | — | — | — |
| Spec-AC-12 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space, the target SHALL hold aai-release.mjs, release-cut.mjs, both launchers, lib/platform-adapter.mjs, pr-platform.mjs and release-finish.mjs, and the target's own launchers (sh under bash; ps1 under pwsh when present) SHALL print the plan with the rolled heading line and exit 0. | planned | — | — | — |
| Spec-AC-13 | The existing callers keep working: test-aai-release.sh (its TEST-019 now behavioural), test-aai-learned-routing.sh and test-aai-release-notes.sh exit 0; tests/skills/aai-release.Tests.ps1 is gone and aai-win-dispatch.Tests.ps1 has no aai-release.ps1 Describe and passes; every tests file that copies aai-release.sh into a scratch tree also copies aai-release.mjs and lib/platform-adapter.mjs; check-vendored-script-deps.mjs exits 0. | planned | — | — | — |
| Spec-AC-14 | Wiring per D-WIRE: select-suites selects aai-release-cut and aai-release for aai-release.mjs and aai-release-cut for lib/platform-adapter.mjs; no suite-map row is added and hygiene-pack test_090 passes; nested-suite lint, check-cd-subshell-leak and check-test-registration exit 0; PROFILES lists aai-release.mjs once under core and layer-profiles test_manifest_conformance passes; both ps1-quality path lists name aai-release.mjs and lib/platform-adapter.mjs once and win-fallback test_034 passes. | planned | — | — | — |
| Spec-AC-15 | test-aai-expert-fetch.sh test_2624_inventory_matches_tree exits 0 with no aai-release row in the pair table, the pair sentence and the phase 5 sentence of D-RFC each appear once with a link ending release-publish-on-node.md, and the phase 5 row keeps status in progress; SKILL_RELEASE holds the exit 14 line and no exit 16 line, is at most 4921 bytes, and test-aai-release.sh test_034_exit_codes_documented and test-aai-prompt-diet.sh exit 0. | planned | — | — | — |
| Spec-AC-16 | Measured with the plan's method on the delivered tree, the suite prints before 319, the after sum of both launchers, the removed code lines and the code lines of aai-release.mjs, and fails when either launcher exceeds its D-LAUNCH budget; every value of the EXIT constants of aai-release.mjs and release-cut.mjs is documented as exit N = in SKILL_RELEASE. | planned | — | — | — |
| Spec-AC-17 | WHEN stdout of the sh launcher is closed early on a plan or a usage, the system SHALL print nothing on stderr and no Node EPIPE stack trace; piped into head -1 it exits 0 or 141, and when the reader is already gone before the first write it exits 141. | planned | — | — | — |

## Implementation plan

TDD in six runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/release-publish-on-node/red/` before its change, GREEN under
`green/`, and one mutation record per row (`node .aai/scripts/mutation-run.mjs`)
before the run's hand-off.

1. Run 1, Spec-AC-01, 02, 08: the `node:test` file with the seam cases and
   all 19 DB case names, the suite functions, then the module skeleton
   (D-MOD arguments, version, help, hand-off).
2. Run 2, Spec-AC-03, 09, 17: the local cut in Node, the `.sh` launcher,
   the EPIPE handling.
3. Run 3, Spec-AC-10, 04, 11: the `.ps1` launcher and its Pester cases, the
   launcher parity matrix, the no-publish safety matrix.
4. Run 4, Spec-AC-06, 07, 05: the adapter's release group, release-finish
   on the adapter, the platform block in the plan.
5. Run 5, Spec-AC-12, 13, 14: the scratch install, the callers and the
   deleted Pester files, D-WIRE.
6. Run 6, Spec-AC-15, 16: D-RFC (RFC-0017 and SKILL_RELEASE) and the
   measurement; then the CHANGELOG entry and the product doc after LOOP
   COMPLETE.

Edge cases: a version holding a space or `..` (DB-05); `--version` as the
last argument (DB-04); a CRLF or BOM CHANGELOG through the cut (already
pinned by slice a TEST-3468, which keeps running through the launchers); a
release branch whose last subject is `chore(release): <V>` (kept identical,
re-cut); the worktree temp directory on a path with a space (the scratch
install, Spec-AC-12); a recorded `platform: invalid` value (DB-18 through
the adapter's mismatch rule).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3520 | Spec-AC-01 | unit | tests/skills/test-aai-release-cut.sh | test_3520_seam runs run_node_tests TEST-3520 on tests/skills/lib/aai-release.test.mjs: an import in a child node with a temp cwd writes nothing to stdout, stderr or the cwd and exposes the six exports; run with recording fakes hands a remote confirm to finish once with the FINISH_SCRIPT path and the three flags after the 10 and 11 checks and calls no adapter, cut or git write; a bare run calls cut with plan, root, version, target branch and launcher | `sed:s/const FINISH_SCRIPT = 'release-finish.mjs'/const FINISH_SCRIPT = 'release-finish-gone.mjs'/` on .aai/scripts/aai-release.mjs | pending |
| TEST-3521 | Spec-AC-02 | unit | tests/skills/test-aai-release-cut.sh | test_3521_argument_drift runs run_node_tests TEST-3521: cases DB-01 to DB-05 (unknown argument, help per launcher, --version=v9, --version without a value and before a flag, a version with a space and one with a double dot), each asserting stdout, stderr, the exit code and the absence of git writes | `sed:s/Run with --help for usage./Run with -h for usage./` on .aai/scripts/aai-release.mjs | pending |
| TEST-3522 | Spec-AC-03 | integration | tests/skills/test-aai-release-cut.sh | test_3522_local_cut_drift runs run_node_tests TEST-3522: cases DB-06 to DB-09, DB-11 and DB-14 in committed temp repositories (an unmerged release branch, a commit without an identity, the report lines, the AAI_VERSION.md bytes, a git wrapper on PATH that sleeps on commit while the test sends SIGTERM) | `sed:s/BRANCH: 14/BRANCH: 12/` on .aai/scripts/aai-release.mjs | pending |
| TEST-3523 | Spec-AC-04 | integration | tests/skills/test-aai-release-cut.sh | test_3523_launcher_parity runs run_node_tests TEST-3523 for DB-12 and DB-13, then (need_tool pwsh) runs the Spec-AC-04 matrix through bash aai-release.sh and pwsh -NoProfile -NonInteractive -File aai-release.ps1 in twin fixtures, maps the flag spellings and requires equal stdout, stderr and exit code per invocation | `sed:s/'--launcher', 'ps1'/'--launcher', 'sh'/` on .aai/scripts/aai-release.ps1 | pending |
| TEST-3524 | Spec-AC-05 | integration | tests/skills/test-aai-release-cut.sh | test_3524_plan_platform runs run_node_tests TEST-3524: DB-15 (dev.azure.com origin and recorded none, with gh and az stubs logging), DB-16 (recorded azure under a github.com origin URL that is never fetched), and the two GitHub reasons with gh absent and with a stub failing auth status | `sed:s/the remote release finish runs on GitHub only/the remote release finish runs here/` on .aai/scripts/aai-release.mjs | pending |
| TEST-3525 | Spec-AC-06 | unit | tests/skills/test-aai-release-cut.sh | test_3525_release_host_argv runs run_node_tests TEST-3525: each release method of the github adapter with a recording runner equals its D-HOST argv and options, checksRunner uses 32 MiB, the azure, unknown and none adapters expose no release group; then runs test-aai-platform-adapter.sh, test-aai-merge-cleanup.sh and test-aai-bootstrap.sh as Verification steps recorded in the green log | `sed:s/'--match-head-commit'/'--match-head'/` on .aai/scripts/lib/platform-adapter.mjs | pending |
| TEST-3526 | Spec-AC-07 | integration | tests/skills/test-aai-release-cut.sh | test_3526_finish_on_adapter requires no command call with gh as the executable and no gh-spawning helper in release-finish.mjs and the checksRunner hand-over; runs run_node_tests TEST-3526 for DB-17 (dev.azure.com origin) and DB-18 (recorded azure, github.com origin) through release-finish.mjs --confirm with gh and az stubs: the exact REFUSED line, exit 20, empty stub logs, no aai/releases journal, refs unchanged; the full test-aai-release.sh and test-aai-release-notes.sh runs are Verification steps | `sed:s/refuse\('release-platform'/refuse('release-host'/` on .aai/scripts/release-finish.mjs | pending |
| TEST-3527 | Spec-AC-08 | inspection | tests/skills/test-aai-release-cut.sh | test_3527_drift_coverage reads the DB ids of the D-DRIFT table of this spec (found by its id spec-release-publish-on-node under docs/specs) and the test names of tests/skills/lib/aai-release.test.mjs and tests/skills/release-cut.Tests.ps1; each table id begins exactly one name and no name begins with an id the table lacks; positive control: a scratch copy with DB-06 renamed is reported | `sed:s/'TEST-3522 DB-06 /'TEST-3522 DB-60 /` on tests/skills/lib/aai-release.test.mjs | pending |
| TEST-3528 | Spec-AC-09 | integration | tests/skills/test-aai-release-cut.sh | test_3528_sh_launcher counts aai-release.sh code lines (at most 12), checks mode 100755 in the index, requires none of git, gh, CHANGELOG, worktree, AAI_RELEASE_DATE in its code lines and one exec node line naming aai-release.mjs and --launcher sh; runs ./.aai/scripts/aai-release.sh --dry-run directly in a fixture (D-OUT sh plan, exit 0); runs it with PATH holding only a scratch bin without node: stderr equals the D-LAUNCH line, stdout empty, exit 20 | `sed:s/Node.js 22 or later is required for \/aai-release/Node.js is required for \/aai-release/` on .aai/scripts/aai-release.sh | pending |
| TEST-3529 | Spec-AC-10 | integration | tests/skills/test-aai-release-cut.sh | test_3529_ps1_launcher (need_tool pwsh) counts aai-release.ps1 code lines (at most 40), requires the six param names, the dot-source guard, none of the three helper names, no Stop preference and no 2> redirect on the node call; runs Invoke-Pester on tests/skills/release-cut.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 10 (SKIP-CASE without Pester 5 locally) | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/aai-release.ps1 | pending |
| TEST-3530 | Spec-AC-11 | integration | tests/skills/test-aai-release-cut.sh | test_3530_no_publish puts the D-TESTS gh stub first on PATH and a bare local origin behind twin fixtures; for each launcher runs bare, --dry-run and --dry-run --confirm (exit 0, tree, index, local and origin refs and file list unchanged, gh log at most auth status), --confirm --no-remote (origin refs unchanged, no gh call) and remote --confirm (a release-finish.mjs REFUSED line, refs unchanged) | `sed:s/if \(o\.dryRun\) o\.confirm = false;/if (o.dryRun) o.confirm = o.confirm;/` on .aai/scripts/aai-release.mjs | pending |
| TEST-3531 | Spec-AC-12 | e2e | tests/skills/test-aai-release-cut.sh | test_3531_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, requires the seven files there, commits a fixture CHANGELOG in the target, runs the target's own aai-release.sh under bash and, when pwsh is present, its aai-release.ps1 under pwsh, each with the gh stub first on PATH and --no-remote: exit 0 and the rolled heading line | `sed:s/  - \.aai\/scripts\/aai-release\.mjs/  - .aai\/scripts\/aai-release-gone.mjs/` on .aai/system/PROFILES.yaml | pending |
| TEST-3532 | Spec-AC-13 | integration | tests/skills/test-aai-release-cut.sh | test_3532_callers runs the test-aai-learned-routing.sh test_002_release_names_unlogged_pr and test-aai-release.sh test_019_ps1_flag_parity selectors (exit 0); requires tests/skills/aai-release.Tests.ps1 absent and no Describe naming aai-release.ps1 in aai-win-dispatch.Tests.ps1; scans tests/ for files that copy aai-release.sh into a scratch tree and requires each to name aai-release.mjs and lib/platform-adapter.mjs; runs check-vendored-script-deps.mjs (exit 0); the full test-aai-release.sh, test-aai-learned-routing.sh, test-aai-release-notes.sh and the aai-win-dispatch Pester runs are Verification steps | `patch:docs/ai/tdd/spec-release-publish-on-node/mutation-TEST-3532.patch` on tests/skills/test-aai-learned-routing.sh | pending |
| TEST-3533 | Spec-AC-14 | inspection | tests/skills/test-aai-release-cut.sh | test_3533_wiring pipes aai-release.mjs and lib/platform-adapter.mjs to node .aai/scripts/select-suites.mjs --files-from - and requires the D-WIRE suites; requires the suite-map row count unchanged and runs hygiene-pack test_090_suite_map_pin; runs nested-suite-lint with its allowlist, check-cd-subshell-leak and check-test-registration (exit 0); requires aai-release.mjs once under core in PROFILES and runs layer-profiles test_manifest_conformance; requires both files once in each ps1-quality path list and runs win-fallback test_034 | `sed:s/      - \.aai\/scripts\/aai-release\.mjs/      - .aai\/scripts\/aai-release-gone.mjs/` on tests/skills/suite-map.yaml | pending |
| TEST-3534 | Spec-AC-15 | inspection | tests/skills/test-aai-release-cut.sh | test_3534_rfc_and_skill runs test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires no aai-release row in the RFC-0017 pair table, the D-RFC pair sentence and phase 5 sentence exactly once each with a link ending release-publish-on-node.md and the phase 5 status in progress; requires the SKILL_RELEASE exit 14 line, no exit 16 line and at most 4921 bytes; runs test-aai-release.sh test_034_exit_codes_documented (exit 0); test-aai-prompt-diet.sh is a Verification step | `sed:s/- exit 14 = /- exit 41 = /` on .aai/SKILL_RELEASE.prompt.md | pending |
| TEST-3535 | Spec-AC-16 | inspection | tests/skills/test-aai-release-cut.sh | test_3535_line_budget counts code lines with grep -cvE on the hash comment and blank pattern under bash with /usr/bin/grep when present: aai-release.sh at most 12, aai-release.ps1 at most 40; prints before 319, the after sum, the removed lines and the code lines of aai-release.mjs (double-slash pattern); positive control on scratch copies padded past each budget; reads the EXIT constants of aai-release.mjs and release-cut.mjs and requires each value as exit N = in SKILL_RELEASE | `patch:docs/ai/tdd/spec-release-publish-on-node/mutation-TEST-3535.patch` on .aai/scripts/aai-release.sh | pending |
| TEST-3536 | Spec-AC-17 | integration | tests/skills/test-aai-release-cut.sh | test_3536_early_close runs run_node_tests TEST-3536: the sh launcher plan and the usage piped into head -1 under bash, asserting empty stderr and exit 0 or 141 from PIPESTATUS, plus a case whose reader exited before the first write, asserting empty stderr and exit 141 | `sed:s/e.code === 'EPIPE'/e.code === 'EXXXX'/` on .aai/scripts/aai-release.mjs | pending |

Test counts by type: unit 3, integration 9, inspection 4, e2e 1 (17 rows;
the 19 DB cases are test cases inside TEST-3521 to TEST-3526 and the Pester
file).

Seams crossed (Principle 2): the module and the real `release-cut.mjs`
plan, check and roll (TEST-3520, TEST-3522, slice a's TEST-3468 through the
launchers); the module and the real `release-finish.mjs` hand-off
(TEST-3530); `release-finish.mjs` and the adapter's release group over the
existing `gh` transport stubs of `test-aai-release.sh` (TEST-3526); the
adapter and its other consumers `merge-cleanup`, `ride-status`, `platform`
and bootstrap (TEST-3525); the platform record in `docs/ai/pr-config.yaml`
read by the plan and by the finish (TEST-3524, TEST-3526); each launcher
under every engine that runs it (TEST-3523, TEST-3528, TEST-3529; Windows
PowerShell 5.1 and pwsh 7 on native Windows in H1); aai-sync's core profile
copy to the target's own launchers (TEST-3531); fixtures in other suites
that copy the scripts (TEST-3532); the RFC inventory read by SPEC-0249's
check (TEST-3534); SKILL_RELEASE's exit-code list (TEST-3534, TEST-3535);
select-suites, the hygiene pin, the nested-suite lint, the cd ratchet and
the registration check (TEST-3533).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-cut.sh`
  exits 0, plus the touched and selected suites, each run the same way:
  test-aai-release.sh, test-aai-release-notes.sh, test-aai-learned-routing.sh,
  test-aai-platform-adapter.sh, test-aai-merge-cleanup.sh,
  test-aai-bootstrap.sh, test-aai-hygiene-pack.sh, test-aai-layer-profiles.sh,
  test-aai-expert-fetch.sh, test-aai-win-fallback.sh, test-aai-suite-select.sh,
  test-aai-prompt-diet.sh, test-ps1-quality.sh. No full sweep is required by
  this spec; Validation decides its own.
- `env -u AAI_ROLE node --test tests/skills/lib/aai-release.test.mjs` exits 0
  with at least 20 passing cases.
- Pester: `tests/skills/release-cut.Tests.ps1` and
  `tests/skills/aai-win-dispatch.Tests.ps1` pass under pwsh 7 locally.
- Not edited (coordination): `git diff --stat main -- .aai/scripts/release-dry-run.mjs .aai/scripts/lib/release-rollup.mjs .aai/scripts/lib/github-checks.mjs .aai/scripts/watch-ci.mjs .aai/scripts/claude-hook-gate.sh tests/skills/test-aai-release-first.sh tests/skills/lib/release-first.test.mjs tests/skills/aai-update.Tests.ps1 .github/workflows/release.yml`
  prints nothing.
- Prompt corpus: `git diff --stat main -- '.aai/*.prompt.md' .aai/AGENTS.md`
  names only `.aai/SKILL_RELEASE.prompt.md` (recorded in the validation
  report).
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell
  5.1 and pwsh 7 with `release-cut.Tests.ps1` discovered and not skipped
  (DB-11, DB-12 and the captured-stderr case are proven on 5.1 only there).
- H2 (hosted): the required `release-dry-run` CI job passes with
  `tests/skills/lib/aai-release.test.mjs` in its reader corpus.

## Evidence contract

ref_id `release-publish-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/release-publish-on-node/` and
`docs/ai/tdd/spec-release-publish-on-node/` (gitignored); each AC row's
Evidence names its green log and mutation record; the validation report and
review verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity (DB-10, DB-11, DB-12, the captured-stderr
  case) is proven only on the hosted job (H1); Planning had no Windows
  engine. DB-14 (signals) is POSIX only; on Windows an interrupted cut may
  leave a temporary worktree that `git worktree prune` removes.
- DB-15 to DB-18 make a release on an Azure DevOps repository, or one whose
  record disagrees with its remote, refuse by name where it used to fail
  inside a `gh` call. A repository with a recorded `platform: none` or
  `unknown` can no longer run the remote finish; it can cut locally.
- DB-06 changes an exit code (12 to 14) that a downstream wrapper could
  have matched; the line is unchanged and the CHANGELOG names it.
- `watch-ci.mjs`, spawned by the remote finish, still calls `gh` directly
  (`fu-platform-adapter-watch-ci`).
- The new `node:test` file joins the release-dry-run reader corpus and its
  CI budget (Coordination).

## Follow-ups

- `fu-release-azure-remote-finish` (P3, ref `release-publish-on-node`, added
  with `follow-ups.mjs add` at the close of this ride): an Azure DevOps
  release group for the adapter (`az repos pr create`, the `platform.mjs`
  merge executor, a tag push in place of `release.yml`), so the remote
  finish runs there instead of refusing (DB-17).
- `fu-release-ps1-eap-stop-native-stderr` is closed at this ride's close
  with `--resolved-by release-publish-on-node --source 8ca408f1` (fixed by
  PR #541 commit `8ca408f1`; this slice deletes the remaining native calls
  of the `.ps1` and pins the class with the captured-stderr Pester case).

Registry items closed by this scope: fu-release-slice-b-delete-twins, fu-platform-adapter-release, fu-release-ps1-eap-stop-native-stderr.

Items this scope leaves open, with reasons: fu-platform-adapter-watch-ci (watch-ci.mjs is not changed), fu-platform-adapter-skill-pr-release (SKILL_PR still describes gh-only mechanics; SKILL_RELEASE changes by one exit-code line only), fu-release-unlogged-pr-three-classes (the audit classifier is not changed), fu-changelog-shape-third-statement (the advice line stays in release-cut.mjs; widening TEST-570 is a wording decision outside this port), fu-release-pr-lookup-failure-cause, fu-release-nested-merge-test, fu-release-normalized-refusal-recovery and fu-release-ruleset-paging-test (release-finish.mjs behaviour and its tests on GitHub are kept byte for byte; the host move changes who spawns gh, not what a failed or paged read means), fu-platform-adapter-lane-gate, fu-platform-adapter-merge-policy, fu-platform-adapter-close-work-item, fu-platform-adapter-pr-preflight and fu-platform-adapter-hook-gate (other consumers of the adapter; the hook gate is ride 7), fu-followups-correct-source-only and fu-spec-lint-inline-closure-label (tooling items of the slice-a ride, not release behaviour).
