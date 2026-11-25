---
id: spec-sync-on-node
type: spec
number: 310
status: done
frozen_sha256: 2f5595c9277f0549d909115f7295da1f175feb43bbcf2d0f2ec47a809b656847
mutation_gate: v1
ceremony_level: 3
links:
  requirement: sync-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run the AAI layer sync as one Node module behind thin launchers

SPEC-FROZEN: true

## Links

- Requirement: [Run the AAI layer sync as one Node module behind thin launchers](../issues/CHANGE-0265-sync-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 12, the last ride (owner sign-off: yes; merge by the owner). Plan
  section 4 decision 1 applies: Node is a hard prerequisite on the install
  and update path; launchers refuse without Node and print an install hint.
  Plan section 5 is the done definition this ride re-measures (D-PHASE5).
- Structural template: [SPEC-0308](SPEC-0308-spec-pre-commit-installer-on-node.md)
  (ride 11: frozen references with a sha256 pin, differential corpora on
  both sides, launchers, Pester, scratch install, the parity harness's module
  twin, wiring named up front, seven runs). Earlier precedents:
  [SPEC-0307](SPEC-0307-spec-update-on-node.md) (ride 10),
  [SPEC-0306](SPEC-0306-spec-bootstrap-on-node.md) (ride 9),
  [SPEC-0267](SPEC-0267-spec-node-first-reap-tests.md) (reaper launchers),
  [SPEC-0284](SPEC-0284-spec-install-path-parity-harness.md) (parity harness).
- Defects of ride 11 this spec designs against: round-2 R2-B1 (`resolveBase`
  checked the identity of the raw `PWD` but returned `path.resolve(PWD)`, so a
  `..` after a symbolic link named another directory; D-BASE), review B1 (an
  in-process run skipped the scratch assertion and git honoured
  `GIT_CONFIG_COUNT/KEY_n/VALUE_n`, `GIT_CONFIG_PARAMETERS` and
  `GIT_COMMON_DIR` from the caller; D-SAFETY), review N1 (a temp file the
  run did not create was deleted on EEXIST; D-COPY), and
  `fu-suite-git-env-scrub-class` (D-GITENV).
- Specs whose tests this ride re-homes (D-REHOME): SPEC-0020, SPEC-0035,
  SPEC-0106, SPEC-0157, SPEC-0184, SPEC-0199, SPEC-0216, SPEC-0237, SPEC-0250,
  SPEC-0253, SPEC-0273, SPEC-0284, SPEC-0306, SPEC-0307, SPEC-0308.
- Shared code read and changed: `.aai/scripts/aai-update.mjs`,
  `.aai/scripts/aai-bootstrap.mjs` and `.aai/scripts/install-pre-commit-hook.mjs`
  (base resolution only, D-BASE). Shared code read and not changed:
  `.aai/scripts/lib/merge-hooks-json.mjs` (imported, D-HOOKS),
  `.aai/system/RUNTIME_IGNORE.list` (data unchanged, header comment updated),
  `.aai/system/COPILOT_SHIM_SHIPPED.list`, `.aai/system/PROFILES.yaml` data
  rules.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 compatible suites, Pester 5, Windows PowerShell 5.1 and pwsh 7).
- Baseline: main `077ee649`.

## Implementation strategy

- Strategy: tdd
- Rationale: owner requirement for every Node-first ride: TDD in runs of
  about three Spec-ACs. The port replaces the consumer install path's two
  drifting twins; every rule test is RED before the module exists, the two
  differential corpora stay RED until the module matches each frozen
  reference (or the named DR), and every Test Plan row carries a mutation
  (mutation_gate v1). Wiring, docs and re-measure rows are inspection tests,
  still seen RED first because the rows, entries and sentences they check
  are absent on the baseline.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: ceremony level 3 (the consumer install and update
  path, which deletes files in the target); a new module, two shared libs,
  two launchers, three frozen references, three shipped modules switched to
  the shared base lib, re-homed assertions in about fifteen suites, the
  parity driver, CI path filters and PROFILES; the main checkout is shared
  with other sessions and holds unrelated uncommitted files.
- User decision: worktree (owner-directed own worktree, already created)
- Base ref: 077ee649
- Worktree branch/path: feat/sync-on-node at /Users/ales/Projects/aai-worktrees/sync-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/aai-sync.mjs .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1
  .aai/scripts/lib/resolve-base.mjs .aai/scripts/lib/gitignore-block.mjs
  .aai/scripts/lib/gitignore-block.sh .aai/scripts/aai-update.mjs
  .aai/scripts/aai-bootstrap.mjs .aai/scripts/install-pre-commit-hook.mjs
  .aai/system/PROFILES.yaml .aai/system/RUNTIME_IGNORE.list
  tests/fixtures/sync-reference/aai-sync.sh tests/fixtures/sync-reference/aai-sync.ps1
  tests/fixtures/sync-reference/gitignore-block.sh tests/skills/lib/sync-reference.mjs
  tests/skills/lib/aai-sync.test.mjs tests/skills/lib/aai-sync-fixtures.mjs
  tests/skills/lib/resolve-base.test.mjs tests/skills/lib/git-env-scrub.sh
  tests/skills/test-aai-sync-node.sh tests/skills/test-aai-sync-docs.sh
  tests/skills/aai-sync.Tests.ps1 tests/skills/test-aai-sync-seed.sh
  tests/skills/test-aai-layer-profiles.sh tests/skills/test-aai-layer-drift.sh
  tests/skills/test-aai-update-check.sh tests/skills/test-aai-harness-shims.sh
  tests/skills/test-aai-legacy-migrations.sh tests/skills/lib/release-notes-docs.test.mjs
  tests/skills/test-aai-bootstrap.sh tests/skills/lib/aai-bootstrap.test.mjs
  tests/skills/lib/bootstrap-reference.mjs tests/skills/aai-bootstrap.Tests.ps1
  tests/skills/lib/aai-update.test.mjs tests/skills/test-aai-update-node.sh
  tests/skills/aai-update.Tests.ps1 tests/skills/lib/install-pre-commit-hook.test.mjs
  tests/skills/test-aai-hook-installer-node.sh tests/skills/lib/vendor-hook-installer.sh
  tests/skills/install-pre-commit-hook.Tests.ps1 tests/skills/test-aai-git-ref-guard.sh
  tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-doctor.sh
  tests/skills/test-aai-pre-commit-checks.sh tests/skills/lib/install-parity.mjs
  tests/skills/lib/install-parity.test.mjs tests/skills/lib/install-parity-allowlist.tsv
  tests/skills/test-aai-install-parity.sh tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv
  tests/skills/test-aai-win-fallback.sh .github/workflows/ps1-quality.yml
  CHANGELOG.md README.md docs/USER_GUIDE.md docs/product/sync-on-node.md
  docs/analysis/node-first-remaining-plan.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-0265-sync-on-node.md
  docs/specs/SPEC-0310-spec-sync-on-node.md docs/INDEX.md
  (decisions.jsonl only for the amendment and follow-up records; the
  allocator renames the two DRAFT files at merge; the fixtures file only if
  the corpus fixtures are split out of the node:test file;
  test-aai-win-fallback.sh only if its ps1 path derivation needs a hop for a
  new helper; docs/product/sync-on-node.md is written after LOOP COMPLETE,
  D-DOCS.)
- Code review required: true (L3: the most capable tier, mandatory; a waiver
  goes to the operator).

## Ceremony

- Level 3, declared on the intake's instruction. Canon does not force it:
  `.aai/scripts/aai-sync.*` are not in `protected_paths_l3`
  (docs/ai/docs-audit.yaml, measured at `077ee649`, and this ride does not
  edit that list), and no protected file is touched (WORKFLOW.md, the state
  engine, the allocator, `pre-commit-checks.sh` and the hook gate stay
  unchanged). The sync is the path every consumer install and update runs
  and it deletes files in the target, so the ride takes L3's mandatory
  most-capable review, the operator checkpoint before merge, and no delta
  re-check.
- Suite selection: Validation runs the selected suites between runs and the
  full sweep once before close (`AAI_TEST_TIMEOUT=3000`).
- One PR. The size is larger than ride 11 (one module of about 900 lines,
  two libs, about fifteen re-homed suites); no split is proposed. D-SLICES
  names the fallback ship point.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2.57, Node 22.23.1, pwsh
7.6.3, git 2.54.0, umask 0022) on 2026-11-22 at `077ee649`, in scratch
directories under the session scratchpad. One run each; they size the work,
they are not thresholds.

- `.aai/scripts/aai-sync.sh`: 1074 lines, 784 code lines
  (`grep -cvE '^[[:space:]]*(#|$)'`), mode 100755, git blob
  `f42b62ca7513462a34d7e5c31a2ac7628752495c`, sha256
  `00aac687f306439cec14ef50a2a48ea0511fb95d9b0c6590ca1c7afc1eea4c06`, 33 lines
  holding a non-ASCII byte.
- `.aai/scripts/aai-sync.ps1`: 1135 lines, 871 code lines, mode 100644, git
  blob `d7ab810f58972717f448c27dc86c991559e847db`, sha256
  `038a640a45142866505669266cb42b05652cc59bb0279a0c7479f729df4c3acd`, one line
  holding a non-ASCII byte.
- `.aai/scripts/lib/gitignore-block.sh`: 88 lines, 30 code lines, mode
  100644, blob `8402ac806c7e66a89af67393bf67e6d4a68f3d92`, sha256
  `5544c8395b5b8ae956a8ffcedafb4bf7e93d1e6171540f0c1a82f81ecee3e7d1`. Its
  shipped callers: `aai-sync.sh` only (the bootstrap is Node since ride 9);
  the frozen bootstrap reference `tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh`
  sources it from the tree `materializeBootstrapReference` copies. The last
  commit touching any of the three files is `51840bde`.
- Arguments, bash: every message goes to stdout and exits 1. `-h` and
  `--bogus` are taken as the target (`ERROR: Target directory does not exist:
  -h`); no argument and `--profile=x` with no target print `Usage: <$0>
  <path-to-target-project> [--profile core|extended]`; a bare `--profile`
  prints `ERROR: --profile needs a value (core|extended)`; an invalid value
  with a target prints `ERROR: invalid --profile value: <v> (allowed:
  core|extended)`. PowerShell: `-h` and `--bogus` are binding errors on
  stderr (exit 1); no argument prompts for the mandatory `TargetRoot` and
  then fails (exit 1); `-Profile bogus` throws with a stack (exit 1).
- A plain extended sync of this tree into an empty `git init` target: exit 0,
  25 stdout lines, 514 files written, 2.6 s wall (bash); pwsh 7 the same
  file count, about 3.3 s of CPU. The pin's template version line reads
  `- Template version:  v2026.11.13` (two spaces, BSD sed has no `\s`) from
  bash and `- Template version: v2026.11.13` from pwsh.
- Syncing a scratch copy of this tree into itself (`bash self/.aai/scripts/aai-sync.sh
  self`): exit 1 after `cp: .../self/.aai/AGENTS.md: No such file or
  directory`; the copy lost a file (2216 files before, 2215 after). Neither
  twin refuses a target that is its own source.
- The legacy-layout moves were added in `348d1db9` (2026-03-03, "Refactor
  AI-OS to AAI"); the first release tag is `v2026.07.04`, the newest
  `v2026.11.13`. Every target synced since 2026-03-03 has been migrated.
- `PROFILES.yaml`: the core list holds 237 entries (7537 bytes); the tracked
  `.aai` tree holds 318 files; core lists `aai-sync.sh`, `aai-sync.ps1` and
  `lib/gitignore-block.sh`.
- Callers (read-only sweep, docs history excluded): `aai-update.mjs`
  (`syncCommand`: `<src>/.aai/scripts/aai-sync.sh <target>` under bash, or
  `-NoProfile -NonInteractive [-ExecutionPolicy Bypass] -File <src>/.aai/scripts/aai-sync.ps1
  -TargetRoot <target>`, always the materialized SOURCE's file), the frozen
  update references (`$SRC/.aai/scripts/aai-sync.sh "$TARGET"`, `aai-sync.ps1
  -TargetRoot`), `install.sh` (`bash "$SYNC_SCRIPT" "$TARGET_ROOT"` from the
  downloaded or `--source-root` tree), `install.ps1` (`& $syncScript
  -TargetRoot $TargetRoot`), `golden-flow.mjs` (`bash <self>/aai-sync.sh
  <fixture>`), the self-hosting smokes, `ps1-quality.yml` (the Windows 5.1
  smoke `& .\.aai\scripts\aai-sync.ps1 -TargetRoot $target -Profile
  extended`), README, USER_GUIDE, prompts (prose).
- Tests: 37 source-shape sites read the twins' or the library's text (21 in
  `test-aai-sync-seed.sh`, 7 in `test-aai-layer-profiles.sh`, 2 in
  `test-aai-routine.sh` twice, one each in `test-aai-layer-drift.sh`,
  `release-notes-docs.test.mjs` twice and `test-aai-legacy-migrations.sh`
  twice); 25 break when the twins become launchers. Behaviour runs that break
  besides text pins: `test-aai-layer-drift.sh` TEST-010 and
  `test-aai-update-check.sh` `build_sync_source` copy the `.sh` alone;
  `install-parity.mjs` `buildSource` and `test-aai-legacy-migrations.sh`
  `copy_tracked` copy `git ls-files` (an untracked module is left out);
  `test-aai-sync-seed.sh` TEST-783 runs the sync with no node on PATH;
  TEST-831 requires an awk child under `LC_ALL=C`; `test-aai-harness-shims.sh`
  TEST-3008 case d stubs the sha256 tools to fail. About 70 further
  behaviour runs execute the sync from this checkout or a full-tree copy and
  keep working through the launcher.
- `test-aai-layer-profiles.sh` TEST-464 already pads the core list with
  20,000 fake paths (larger than a pipe buffer) and runs the bash twin;
  TEST-465 a 200 KB `.gitignore`; TEST-466 statically forbids pipes into an
  early-closing reader in `aai-sync.sh`.
- Parity harness: sync scenarios SY-01 to SY-07 (SY-01 smoke) on twins sh and
  ps1, the node twin `ops: ['bootstrap', 'update', 'hooks']`; 17 allowlist
  rows describe sync output (rows 8 to 14 and 16 to 25 of
  `install-parity-allowlist.tsv`), 13 of them `sh:ps1`. `buildSource` copies
  `git ls-files` into the scratch source.
- `tests/skills/suite-map.yaml` holds 142 rows (hygiene test_090 pins 142);
  14 rows list `aai-sync.sh` or `.ps1`; `cd-subshell-leak-baseline.tsv` holds
  `2` for `aai-sync.sh`; hygiene test_128 needs at least 3 shipping `.sh`
  files with pipefail and finds 4, one of them `aai-sync.sh`.
- `.aai/scripts` after ride 11 (code lines): logic-carrying `.sh`/`.ps1` are
  `aai-sync.sh` 784, `aai-sync.ps1` 871, `aai-run-tests.sh` 540, `.ps1` 525,
  `pre-commit-checks.sh` 390, `aai-win-selftest.ps1` 270,
  `claude-hook-gate.sh` 63 (115 lines), `aai-release.ps1` 25 (32 lines),
  `lib/test-residue.sh` 526, `lib/repo-tripwire.sh` 158,
  `lib/append-lock.sh` 50, `lib/git-bash-path.sh` 45,
  `lib/gitignore-block.sh` 30; every other `.sh`/`.ps1` is 20 lines or fewer.

## Decisions

### D-MODULE. `.aai/scripts/aai-sync.mjs`

Dependency-free ESM, Node 22 compatible, imports only `node:` specifiers plus
`./lib/resolve-base.mjs`, `./lib/gitignore-block.mjs` and
`./lib/merge-hooks-json.mjs`, none of `node:http`, `node:https`, `node:net`,
`node:tls`, `node:dgram`; ASCII only (non-ASCII output characters as `\u`
escapes); no side effect on import (main guard compares `realpathSync` of
`process.argv[1]` and of the module); never reads standard input; never
touches `process.stdout` or `process.stderr` (output through `fs.writeSync`
on descriptors 1 and 2). It holds all sync policy. Every child process (git
only) goes through one injectable seam (`io.spawn`, default `runChild`) and
gets `io.env`; the clock is read once per run through `io.now` (default
`() => new Date()`).

Exports at least: `parseArgs`, `resolveRoots`, `readStickyProfile`,
`parseCoreList`, `planCore`, `planPrune`, `copyReplace`, `underRoot`,
`isRetiredSkillWrapper`, `copilotShimIsShipped`, `extractCopilotOverrides`,
`renderAdvisory`, `renderPin`, `run`, `main`. `run(argv, io)` and
`main(argv)` resolve to the exit code; `run` takes injectable `out`, `err`,
`env`, `cwd`, `spawn`, `now`, `scriptPath` and an optional `ledger`
(`{ conflicts, deletions }` arrays the run appends to as it records them, which
the advisory of run 4 renders).

It contains these exact lines, each once, and no comment repeats one (the
Test Plan mutations rely on them):

```js
import { resolveFromBase } from './lib/resolve-base.mjs';
import { reconcileGitignore } from './lib/gitignore-block.mjs';
import { mergeHooksJson, formatSummary, formatConflicts, formatSnapshotError } from './lib/merge-hooks-json.mjs';
const EXIT_FAIL = 1;
const EXIT_USAGE = 2;
const PROFILE_NAMES = ['core', 'extended'];
const PS_NAMES = { '-targetroot': 'target', '-profile': '--profile' };
const ROOT_SHIMS = ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md'];
const SKILL_TREES = ['.claude/skills', '.agents/skills'];
const isCoreListed = (coreSet, rel) => coreSet.has(rel);
const overlapsSource = (roots) => isUnderOrSame(roots.targetReal, roots.srcReal);
const PIN_VERSION_PREFIX = '- Template version: ';
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };
  const roots = resolveRoots(args, io);
  if (!underRoot(roots, abs)) return refuseOutside(roots, abs);
```

Every output string of the DR table occurs once in the module (a sentence
shared by two paths lives in one function).

### D-CLI. Arguments, help and usage (DR-1 to DR-3, DR-25)

- Arguments are read left to right. Accepted: one positional target,
  `--profile <v>`, `--profile=<v>`, `-h`, `--help`, `--` (every later
  argument is positional), and the PowerShell names of the old `.ps1`
  (`-TargetRoot <t>`, which sets the target, and `-Profile <v>`), matched
  case-insensitively, exact names only (`PS_NAMES`); no abbreviation, no
  common parameter (DR-3).
- `-h` or `--help` prints the help text on stdout and exits 0 at its position
  (DR-1): lines 4 to 20 of the bash reference after `s/^# \{0,1\}//` (its
  usage, example and profile lines), then
  `  powershell -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot <path> [-Profile core|extended]   # the bash form works too`
  and `Requires Node.js 22 or later; both launchers run .aai/scripts/aai-sync.mjs.`
- Usage errors, each one stderr line plus the bash usage line `Usage:
  .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]`,
  exit 2, nothing read or written (DR-2): no target or an empty target; a
  second positional (`ERROR: unexpected argument: <arg>`); an argument
  starting with `-` before `--` that is not accepted (`ERROR: unexpected
  argument: <arg>`; the bash twin took it as a target path); a bare
  `--profile` or `-Profile` (`ERROR: --profile needs a value
  (core|extended)`); a value outside `PROFILE_NAMES` (`ERROR: invalid
  --profile value: <v> (allowed: core|extended)`). The order of the checks is
  the bash order (target presence first, then the profile value). The
  PowerShell launcher never prompts (DR-25).
- Exit codes: 0 done; 1 refusal, failed write or internal error
  (`aai-sync: internal error: <message>` on stderr); 2 usage. Every `ERROR:`
  line goes to stderr; the narrative lines go to stdout (DR-4).

### D-ROOTS. Source, target and the refusals before any write (DR-5 to DR-8)

- Base directory: `resolveFromBase` (D-BASE). Target: `resolveFromBase(<arg>,
  env, cwd)`, lexically against the trusted base (the bash `cd` reading); it
  must exist as a directory, else the bash line `ERROR: Target directory does
  not exist: <arg>` and exit 1 (DR-30: the bash twin tested `-d` on the physical
  path and then read the logical one with `cd`, so a relative target through a
  symbolic-link working directory that exists only logically was refused; the
  module reads it logically, once).
- Source root: the parent of the parent of `dirname(scriptPath)`, where
  `scriptPath` is `process.argv[1]` as the launcher passed it (a logical
  path); it is used only when its `.aai/scripts/aai-sync.mjs` names the same
  device and inode as the running module, else the root is taken from the
  module's real path. The source must hold `.aai/` (the bash line `ERROR:
  Source missing .aai/ directory: <src>`, exit 1).
- `roots` = `{ src, target, srcReal, targetReal, targetDev, targetIno }`
  captured once. Refusals, all before any write, exit 1, one stderr line
  naming both paths and `nothing was written`:
  - DR-5: `targetReal` equals `srcReal` or lies under it (the measured
    self-sync deleted a source file). A source inside the target (a vendored
    checkout under the project) is allowed.
  - DR-6: the target is the root of its file system.
  - DR-7: any managed top-level path of the target (`.aai`, `.agents`,
    `.agents/skills`, `.claude`, `.claude/skills`, `.claude-plugin`, `.codex`,
    `.codex/skills`, `.cursor`, `.gemini`, `.gemini/skills`, `.github`, `docs`,
    `docs/ai`, `docs/knowledge`, `hooks`) that is a symbolic link whose real
    path lies outside `targetReal` or inside `srcReal` (both twins wrote and
    pruned through it; closes `fu-sync-symlinked-tree-root`).
  - DR-29: the target's `.gitignore` is checked like the managed top-level
    paths of DR-7 (the reconcile appends to it, which follows a link; both
    twins wrote through a link that left the target); a link that stays inside
    the target is allowed.
- `underRoot(roots, abs)` (DR-8): true only when the real path of the parent
  directory of `abs` (the nearest existing ancestor for a path about to be
  created) lies under `targetReal` and not under `srcReal`, and the target's
  device and inode still equal `targetDev` and `targetIno`. Every write,
  rename, copy, chmod and delete the module performs calls it first; a false
  answer prints `ERROR: <rel> resolves outside the target <target>; refusing
  to write or delete there.` and exits 1. Before the core prune, the extended
  stale clean and the retired-wrapper removal the target identity is
  re-read; a change exits 1 with the same line.
- Profile (D-PROFILE) and the core list are resolved here too, so an empty
  core list refuses before any write.

### D-BASE. One shared base resolution (closes fu-resolvebase-dotdot-after-symlink)

`.aai/scripts/lib/resolve-base.mjs`, stdlib only, no side effect on import,
exports exactly:

- `resolveBase(env = process.env, cwd = process.cwd())`: the environment's
  `PWD` when it is absolute and `path.resolve(PWD)` names the same device and
  inode as `cwd`; else `cwd`. The identity check is applied to the very path
  that is returned (the ride-11 round-2 rule), so a `..` after a symbolic
  link, which the OS follows from the link's target, is not trusted.
- `resolveFromBase(rel = '', env = process.env, cwd = process.cwd())`:
  `resolveBase(env, cwd)` when `rel` is empty, else `path.resolve(base, rel)`.

It contains these exact lines, each once:

```js
export function resolveBase(env = process.env, cwd = process.cwd()) {
    const resolved = path.resolve(pwd);
    const a = statOrNull(resolved);
    if (a && b && a.dev === b.dev && a.ino === b.ino) return resolved;
```

Users, in this ride, test-first:

- `aai-update.mjs`: `resolveBase(rel, env, cwd)` stays exported with its
  signature and delegates to `resolveFromBase` (SPEC-0307 TEST-3962 keeps
  passing; its stale-PWD and trailing-slash cases are unchanged).
- `aai-bootstrap.mjs`: `resolveRoot(target, env, cwd)` delegates to
  `resolveFromBase`.
- `install-pre-commit-hook.mjs`: `resolveBase(env, cwd)` is the lib's
  (re-exported).
- `aai-sync.mjs`: D-ROOTS.
- None of the four modules keeps its own `PWD` identity comparison (no
  `.dev ===` or `samePlace(` on a `PWD` stat).

Each switched module's shape test gains exactly the one allowed relative
import (D-REHOME run 2). Every test helper that vendors one of the three
switched modules also vendors `lib/resolve-base.mjs`
(`check-vendored-script-deps.mjs` exits 0).

### D-GITIGNORE. The `.gitignore` reconcile (slice a; DR-11, DR-12, DR-14)

`.aai/scripts/lib/gitignore-block.mjs` (stdlib only), the one reconcile,
ported from the bash twin and `lib/gitignore-block.sh` byte for byte:

- `export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecars';`
  (exact line, once) and the sync's marker text `# AAI runtime sidecars
  (seeded from .aai/system/RUNTIME_IGNORE.list; per-dev, never commit)`.
- `seedRuntimeGitignore(file, listPath, markerText)`: the bash library
  contract (list lines and the target read with every CR removed; blank and
  `#` lines skipped; exact-line match; the marker written only when no line
  starts with the prefix; `\n`, the marker, the missing lines, each with LF;
  the summary line `<file> add <n> AAI runtime sidecar pattern(s)`; a missing
  list prints `skipped runtime-sidecar gitignore seed: <list> missing` and
  writes nothing). The list is the source's
  `.aai/system/RUNTIME_IGNORE.list`, else the target's.
- `reconcileGitignore(target, { srcList, targetList, out })`: the bash order
  and bytes, every append through one function: `.aai/` (present when any
  line starts with `.aai/`, the twins' prefix reading kept for parity), the
  runtime-sidecar seed, `.cloudflare-publish*` and `.wrangler/` (substring),
  `.aai/cache/` (substring), the reports block (substring
  `docs/ai/reports/**`), the agent-skill block and the runtime-state block
  (exact lines on a CR-stripped read, re-read after each append), then the
  self-heal (managed lines matched exactly after the CR is removed, the first
  kept, runs of blank lines collapsed, every line written with the file's
  line ending, CRLF when any CR exists, written only when a duplicate was
  removed, through a temp sibling the run created exclusively and renamed
  over the file). No shell, no pipe: the early-closing-reader class of the
  bash twin (a `grep -q` closing its pipe and pipefail reading the match as
  a miss) cannot occur, and TEST-4005 proves a large file with the managed
  lines at the top is not re-appended.
- The runtime-state block's pointer (DR-14), after `Added AAI per-dev runtime
  state patterns to <file>`: `  NOTE: If docs/ai/STATE.yaml or
  docs/ai/LOOP_TICKS.jsonl is still tracked,` and `        run bash
  .aai/scripts/migrate-state-to-local.sh (or powershell -NoProfile -File
  .aai/scripts/migrate-state-to-local.ps1) in the target project.` (bash
  named only the `.sh`, the `.ps1` only `pwsh ... .ps1`). The pointer stays
  (plan ride 1 ported `migrate-state-to-local`; `aai-doctor.mjs` names it
  too).
- DR-11: the `.ps1` order (runtime-sidecar seed last), its marker text
  `(seeded by aai-sync.ps1; ...)`, its extra blank lines and, on Windows, its
  CRLF appends become the bash bytes (closes `fu-parity-gitignore-block-order`;
  the gitignore part of `fu-parity-win-ps1-crlf-bom`). DR-12: the `.ps1`
  self-heal matched managed lines after `TrimEnd()`; the module matches
  exactly, as bash.
- `aai-bootstrap.mjs` keeps its own `seedRuntimeGitignore` (out of scope;
  suggested follow-up D-FU).

### D-PROFILE. Profile, core copy and prune (slice b; DR-9, DR-10)

- Profile: the flag, else the target pin's first line starting `- Profile: `
  (CR removed, trailing spaces and tabs removed) when it reads `core` or
  `extended`, else `extended` (DR-9: the `.ps1` took the first line that
  matched a valid value, bash the first line, then validated it).
- Core list (`parseCoreList`), read only for `core`: the bash awk rule (the
  block opens at the line `core:` exactly, closes at the next line not
  starting with a space; entries are lines starting `  - `, trailing spaces,
  tabs and CR removed). The `.ps1` accepted `core:` followed by spaces and
  kept a tab-indented line inside the block (DR-10). A missing manifest (the
  bash line `ERROR: --profile core requires the manifest: <path>`) and an
  empty list (`ERROR: no core entries found in <path>`) exit 1 before any
  write.
- `planCore`: each entry in order; a source path that is not a regular file
  prints `  WARN core-listed file missing in source (skipped): <rel>`.
  Copied with `copyReplace` (D-COPY).
- `planPrune` (pure): every regular file and symbolic link under the
  target's `.aai/` (a directory is never a candidate) whose
  target-relative forward-slash path is not under `.aai/cache/` and is not
  `isCoreListed`; an `.aai/scripts/` path the source does not have is
  preserved (`  PRESERVE target-only script: <rel>`). The core set is a
  `Set` built once; the lookup reads no pipe and no child, so the size of
  the list cannot change a verdict (the hazard class of the measured
  layer-profiles flake). Each prune prints `  PROFILE prune (not in core):
  <rel>` and is recorded in the advisory's Deleted items. The candidates, and so
  the prune and PRESERVE lines and the Deleted items, are in the byte order of
  the whole relative path (DR-26: the bash `find` order is undefined and the
  `.ps1` had its own).
- After the prune, directories under `.aai/` left empty are removed deepest
  first; `.aai/` itself and `.aai/cache/` are never removed.

### D-COPY. Extended copy, copy semantics and the path guard (slice b; DR-15)

- Extended: every top-level entry of the source's `.aai/` except `scripts`
  and `cache` is copy-replaced; every top-level entry of the target's `.aai/`
  except `scripts` and `cache` that the source lacks is removed (`  CLEAN
  removed stale: .aai/<name>`, recorded as a deletion); every entry of the
  source's `.aai/scripts/` is copy-replaced; every target-only entry there is
  preserved with its PRESERVE line. The manifest is never read.
- `copyReplace(src, dst)`: `underRoot` first; the destination (a file, a
  directory tree or a link, never followed) is removed, then the source is
  copied with a small recursive copy over `fs` primitives (`lstat`, `readlink`
  and `symlink` for a link, `mkdir` for a directory, `copyFile` with the
  exclusive flag for a file; file and directory modes and timestamps set from
  the source after the copy), because `fs.cpSync` reads a dangling top-level
  link through `stat` and fails on it under Node 22.23. A dangling source
  link is copied as a link (DR-15: `cp -a` did; the `.ps1` crashed, closing
  `fu-sync-ps1-dangling-src-symlink`). A dangling link that is itself a
  top-level entry of a directory the sync globs (the source's `.aai/*` and
  `.aai/scripts/*`, the skill trees, `docs/knowledge`, the indexes, `hooks/`, and
  the target's `.aai/*` and `.aai/scripts/*`) is skipped, as the bash `[[ -e ]]`
  test of each glob loop skipped it (DR-27); the stale-entry test of the clean
  step follows the link the same way. Kept for parity: a copy-replaced
  directory loses files the target added inside it (the advisory records the
  conflict where the twins did).
- Temp files (the self-heal, the advisory, the pin) are created with the
  exclusive flag under a name holding the run's pid; on EEXIST the run fails
  and never deletes a file it did not create (the ride-11 N1 rule).
- The target directories the twins create up front (`.aai/workflow`,
  `.aai/roles`, `.aai/templates`, `.aai/scripts`, `.aai/system`,
  `.aai/knowledge`, `.agents/skills`, `.claude/skills`, `.claude-plugin`,
  `.codex/skills`, `.codex/skills.local`, `.cursor/rules`, `.gemini/skills`,
  `.gemini/skills.local`, `.github`, `docs/knowledge`, `docs/ai`, `hooks`) are
  created the same way (parity).

### D-SURFACES. Skill trees, indexes, seeds, shims and the Copilot shim (slice b; DR-16, DR-17, DR-19)

- `SKILL_TREES` (`.claude/skills`, `.agents/skills`): each source entry is
  copy-replaced; when the target entry exists, a differing `SKILL.md` (byte
  compare) or a differing directory (same relative file list and bytes)
  records the twins' conflict text; then the retired wrappers are removed,
  then the PRESERVE line. A byte compare that cannot read a file counts as
  not different (the fail-closed rule of `fu-sync-hash-compare-fails-open`).
- `isRetiredSkillWrapper(entry, name)`: the twins' predicate on the file's
  bytes (read as latin1, one character per byte; the em dash of the expected
  line as its UTF-8 bytes): name `^aai-[a-z0-9-]+$` and not `aai-project-`,
  checked before any file system call; a real directory with exactly one
  entry, named `SKILL.md` byte for byte, a regular file of 1 to 65536 bytes
  without NUL; every CR removed; the frontmatter, the optional
  `<SUBAGENT-STOP>` block, the two delegation lines and the prompt the
  SOURCE no longer ships. No locale is consulted (the twins needed `LC_ALL=C`
  and ordinal compares for that). A removal that fails prints the twins'
  WARN line and is not recorded.
- `.codex/skills` and `.gemini/skills`: wholesale copy-replace with the
  directory conflict text; the `skills.local` PRESERVE lines.
  `.claude-plugin/plugin.json` and `.cursor/rules/aai.mdc`: copy-replace with
  their SYNC lines.
- `docs/knowledge`: each source file is copied when the target file is absent
  or contains `AAI-TEMPLATE` (case-sensitive, DR-16: the `.ps1` `-match` was
  case-insensitive), else the SKIP line.
- Seeds when absent: `docs/TECHNOLOGY.md`, `docs/ai/update-config.yaml`,
  `docs/ai/docs-audit.yaml` from their templates with the bash SEED lines;
  the docs/ai PRESERVE line.
- `ROOT_SHIMS` and `README.md` to `README_AAI.md`: copy-replace with the
  conflict text when the target differs.
- Copilot shim: the bash flow and bytes. `copilotShimIsShipped(text, list)`:
  every CR removed, trailing LFs removed, empty or whitespace-only means
  shipped; the sha256 of the UTF-8 bytes through `node:crypto`, compared with
  the list's rows (CR removed) (DR-19: the bash twin read "not shipped" when
  no sha256 tool ran; the hash is now always computed). The merged file and
  the override file are the bash bytes (DR-17: the `.ps1` trimmed the
  overrides, joined with LF without a final newline and wrote a BOM under
  5.1).

### D-HOOKS. Session hooks and the registration merge (slice b; DR-18)

- `hooks/`: every source entry, dotfiles included, is copy-replaced, except
  `hooks.json` and `hooks.windows.json`; target-only entries get the
  PRESERVE line; then `hooks/session-start.sh` gets the three execute bits
  added when it is a regular file (DR-18: the `.ps1` left it non-executable, closing
  `fu-parity-ps1-hook-exec-bit`); then `  SYNC hooks/`.
- `hooks.json` and `hooks.windows.json`: `mergeHooksJson(src, dst, {
  shipped: <target>/.aai/cache/hooks-shipped/<name> })` in process; the
  MERGE line is `formatSummary` and every `formatConflicts` and
  `formatSnapshotError` line, joined as the library's CLI prints them, with
  the target prefix removed and the source prefix replaced by `<source>/`;
  the LEFT-AS-IS and SNAPSHOT-NOT-RECORDED advisory entries and the WARN line
  as in bash; a thrown merge prints the refused WARN line with the message
  and records the advisory entry (the target is untouched, the library
  throws before it writes).
- DR-18 also: the "node unavailable" and "merge library missing" branches
  are gone (the module runs under Node and imports the library statically;
  a source tree without the library fails at load with exit 1 and writes
  nothing), and the Windows PowerShell 5.1 NativeCommandError abort is gone
  (closing `fu-sync-ps1-merge-lib-stderr-5-1`).

### D-REPORT. Advisory report, pin and the closing lines (slice b; DR-20 to DR-24)

- One clock read per run (`io.now`). Advisory, written when a conflict or a
  deletion was recorded: `docs/ai/reports/sync-conflicts-<yyyymmdd-HHMMSS
  UTC>.md` with `- Generated at (UTC): <yyyy-mm-ddTHH:MM:SSZ>` from that read
  and the bash text including its backticks, LF, no BOM (DR-20, closing
  `fu-parity-sh-report-stamp-two-reads`, `fu-parity-ps1-report-name-local-time`,
  `fu-parity-ps1-timestamp-precision` for the report and
  `fu-parity-ps1-report-backticks`).
- Pin `.aai/system/AAI_PIN.md`: the bash text with `- Template version: <v>`
  (one space on every platform, DR-21, closing `fu-parity-pin-template-spacing`):
  the first line of the source's `docs/ai/AAI_VERSION.md` matching
  `^-? *Version:` (the `.ps1` also allowed leading whitespace), the value
  after `Version:` with spaces, tabs and a CR trimmed; else `git describe
  --tags --abbrev=0` plus ` (tag)`; else `UNKNOWN`. `- Template commit:` from
  `git rev-parse HEAD`, `- Canonical repo:` from `git config --get
  remote.origin.url`, each `UNKNOWN` on failure (DR-28: in a source repository
  without a commit the bash twin's `git rev-parse HEAD` printed the word `HEAD`
  before its `|| echo UNKNOWN`, so the commit line held two lines; the module
  writes `UNKNOWN`). `- Synced at (UTC):` from
  the run's clock to the second (DR-21 for the `.ps1`'s seven fraction
  digits). LF, no BOM (DR-21, the pin part of `fu-parity-win-ps1-crlf-bom`).
- DR-22: every git child runs `git -C <src> ...` with the repository-selecting
  variables removed from `io.env` (`GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`,
  `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_NAMESPACE`), stdin ignored,
  stdout piped; both twins inherited them, so a sync run from inside a git
  hook stamped the hook's repository.
- DR-23: paths in messages, the pin and the report are native (`C:\...` on
  win32; the bash twin under Git Bash wrote `/c/...`, closing
  `fu-parity-win-source-path`).
- DR-24: the closing lines are the bash lines (`Sync complete. Review changes
  in <target>:` and `  cd <target> && git status && git diff`; the `.ps1`
  wrote ` :` and `;`).

### D-LEGACY. The legacy-layout moves are dropped (slice c; DR-13)

Both twins carried moves for the pre-`.aai/` layout of 2026-03 (`348d1db9`).
The module performs none of them and prints nothing about them. Dropped,
each with its reason:

| Dropped move (both twins) | Why it is dropped |
|---|---|
| `rm -rf <target>/ai` | deletes a project-owned `ai/` directory unconditionally; the layout it migrated predates every release tag |
| remove `scripts/<name>` for every name the source ships in `.aai/scripts/` | deletes a project's own script that shares a name (for example `triage.sh`, `validate-skills.sh`) |
| remove `scripts/ai-os-*` and an emptied `scripts/` | the `ai-os-` names were renamed to `aai-` in 2026-03 |
| remove root `PLAYBOOK.md` | a project may own a `PLAYBOOK.md`; the AAI one lives in `.aai/` since 2026-03 |
| wipe `docs/workflow`, `docs/roles`, `docs/templates` and leave a `.gitkeep` | deletes project content under generic names |
| remove `docs/ai/{AUTONOMOUS_LOOP.md,SUPERPOWERS_INTEGRATION.md,DYNAMIC_SKILLS.md,PRICING.yaml,AAI_PIN.md,LOCKS.md}` | every target synced since 2026-03 has already moved them; nothing reads them there |
| remove `docs/knowledge/PATTERNS_UNIVERSAL.md` | same; it lives in `.aai/knowledge/` |
| the `MIGRATE ...` and `Legacy paths migrated` lines | no move, no line |

A target that still has the old layout keeps those files; the CHANGELOG
names the manual cleanup. The owner rule this enforces: the sync deletes only
inside the managed set (`.aai/` prune and stale clean, copy-replaced managed
entries, retired skill wrappers) under the re-verified target root. Kept:
the `migrate-state-to-local` pointer (D-GITIGNORE, DR-14).

### D-DRIFT. Every difference from either twin, each with a test

| Id | Bash twin | PowerShell twin | Module | Why | Test |
|---|---|---|---|---|---|
| DR-1 | `-h` is taken as a target path, exit 1 | binding error, exit 1 | help on stdout, exit 0 | help must work on both entries | TEST-4002, K18, P11 |
| DR-2 | usage problems print on stdout, exit 1; an unknown dash argument is a target path | binding errors or a thrown exception, exit 1 | one stderr line plus the usage line, exit 2 | one usage exit, distinct from a failed sync | TEST-4002, K19 to K23, P13 |
| DR-3 | `<target>`, `--profile v`, `--profile=v` | native binding: abbreviations, common parameters, `-Profile:v` | the bash forms plus exact `-TargetRoot` and `-Profile`, any case, and `--` | one grammar for both launchers | TEST-4002, P01 |
| DR-4 | every message on stdout | errors as exceptions on stderr | `ERROR:` lines on stderr, the rest on stdout | an error must be separable from the narrative | TEST-4002, K24 |
| DR-5 | target equal to the source: copies over itself, deletes a source file, exit 1 | same class | refused before any write, exit 1 | a sync must never damage its source | TEST-4003, K25, K26 |
| DR-6 | a file system root is a valid target | same | refused, exit 1 | no project lives at a root | TEST-4003 |
| DR-7 | writes and prunes through a managed link that leaves the target | same | the whole run refused before any write | the sync deletes; it must delete only in the target (closes fu-sync-symlinked-tree-root) | TEST-4008, K27 |
| DR-8 | no check on the delete paths | none | `underRoot` before every mutation and the target identity re-read before each delete phase | the owner's delete-only-under-the-verified-root rule | TEST-4008 |
| DR-9 | sticky profile: the first `- Profile:` line, then validated | the first line matching a valid value | the bash rule | one reading | TEST-4007, K06 |
| DR-10 | core block opens at `core:` exactly, a tab-indented line closes it | `core:` plus spaces opens, a tab line stays inside | the bash rule | one reading of the manifest | TEST-4007 |
| DR-11 | gitignore blocks in its order with its marker text | another order, its own marker, extra blank lines, CRLF on Windows | the bash bytes | one file shape (closes fu-parity-gitignore-block-order) | TEST-4005, P06 |
| DR-12 | self-heal matches managed lines exactly | after `TrimEnd()` | the bash rule | one reading | TEST-4005 |
| DR-13 | legacy-layout moves delete `ai/`, `scripts/*`, `PLAYBOOK.md`, `docs/workflow` and more | same | none, nothing printed | the deletes hit project-owned names; D-LEGACY | TEST-4006, K17, P15 |
| DR-14 | pointer names `bash ...migrate-state-to-local.sh` | names `pwsh ...migrate-state-to-local.ps1` | one line naming both launchers | one text for both entries | TEST-4005 |
| DR-15 | `cp -a`: a dangling source link copied as a link | `Copy-Item` crashes on it | copied as a link | the bash behaviour, no crash (closes fu-sync-ps1-dangling-src-symlink) | TEST-4008, P16 |
| DR-16 | knowledge sentinel `AAI-TEMPLATE` case-sensitive | `-match`, case-insensitive | case-sensitive | the bash reading | TEST-4009, P10 |
| DR-17 | Copilot merge bytes | trimmed overrides, no final newline, BOM under 5.1 | the bash bytes | one file shape | TEST-4010, P07 |
| DR-18 | node-unavailable and library-missing branches; `session-start.sh` made executable | NativeCommandError abort under 5.1; exec bit not set | branches gone (static import), exec bit set | the module runs under Node (closes fu-parity-ps1-hook-exec-bit, fu-sync-ps1-merge-lib-stderr-5-1) | TEST-4010, P08 |
| DR-19 | no sha256 tool: the shim reads as not shipped | .NET SHA256 | `node:crypto`, always computed | a hash that cannot fail | TEST-4010 |
| DR-20 | report name and Generated-at from two `date` calls | local-time name, seven fraction digits, no backticks, CRLF and BOM on Windows | one UTC clock read, seconds, the bash text, LF | one report shape (closes fu-parity-sh-report-stamp-two-reads, fu-parity-ps1-report-name-local-time, fu-parity-ps1-report-backticks) | TEST-4011 |
| DR-21 | BSD sed leaves two spaces after `Template version:` | one space; seven fraction digits in `Synced at`; CRLF and BOM on Windows | one space, seconds, LF, no BOM | one pin shape (closes fu-parity-pin-template-spacing, fu-parity-ps1-timestamp-precision, fu-parity-win-ps1-crlf-bom) | TEST-4011, K30 |
| DR-22 | git children inherit `GIT_DIR` and its siblings | same | those variables removed for the pin's git children | the pin must describe the source | TEST-4011 |
| DR-23 | Git Bash paths `/c/...` on Windows | native | native | the module's platform (closes fu-parity-win-source-path) | TEST-4011, H2 |
| DR-24 | closing lines `in <t>:` and `&&` | ` :` and `;` | the bash lines | one text | TEST-4011, P01 |
| DR-25 | not applicable | a missing `-TargetRoot` prompts in an interactive host | usage, exit 2, never a prompt | a sync must not block on input | TEST-4002, P12 |
| DR-26 | prune lines, PRESERVE lines and the advisory's Deleted items in `find` order, which differs per file system | `Get-ChildItem` order | the byte order of the whole relative path (`LC_ALL=C sort`) | one reproducible order on every host | TEST-4007, TEST-4013 K04 and K31b, TEST-4014 P04 |
| DR-27 | a dangling link that is a top-level entry of a globbed directory (`.aai/*`, `.aai/scripts/*`, the skill trees, `docs/knowledge`, the indexes, `hooks/`) is skipped in the source and the target (`[[ -e ]]`) | `Copy-Item` crashes | skipped the same way; a link nested in a copied entry stays DR-15 | the bash reading; a link that leads nowhere is not a layer file | TEST-4008, TEST-4013 K31a and K31b, TEST-4014 P17 |
| DR-28 | a source repository without a commit: `git rev-parse HEAD` prints the word `HEAD` on stdout, so the pin's commit holds `HEAD` and `UNKNOWN` on two lines | `UNKNOWN` | `UNKNOWN` | a stray line broke the pin's shape | TEST-4011, TEST-4013 K30b |
| DR-29 | a `.gitignore` that is a link leaving the target (or entering the source) is appended through | same | the whole run refused before any write, exit 1 (the DR-7 line) | the reconcile wrote outside the target | TEST-4008, TEST-4013 K32a and K32b |
| DR-30 | a relative target through a symbolic-link working directory: the directory test reads the physical path and `cd` then reads the logical one, so a target present only on the logical reading is refused | resolved by the host | resolved once against the trusted logical base (D-BASE), as `cd` does | one reading, no refusal of a path the user can `cd` to | TEST-4013 K29 and K29b |
| DR-31 | a link at `.aai/cache/hooks-shipped/<name>` (the snapshot) or at a merge temp name `<dir>/.<name>.<pid>.tmp` is written through, so the write can overwrite a file outside the target | same | the snapshot link is removed and a regular file written; the temp name is removed first and created exclusively; nothing is written through a link | a write outside the verified target root is never acceptable (owner policy after the 2026-11-19 incident); closes fu-sync-shipped-snapshot-link-escape | TEST-4008 |
| DR-32 | the target is compared with the source by path spelling; on a case-insensitive file system (macOS and Windows defaults) a target that names the source with other letter case is not refused and the first copy-replace deletes a source file | same | refused before any write, exit 1: both roots are real paths in the file system's own spelling (`fs.realpathSync.native`) and the target's ancestors are also compared with the source by device and inode | a sync must never delete or write the source, whatever the spelling (owner policy after the 2026-11-19 incident) | TEST-4003 |
| DR-33 | a source inside a managed entry of the target (for example `<t>/.aai/upstream`) is deleted by the stale clean or replaced by the copy of that entry, and the run exits 0 | same class | refused before any write, exit 1, one line naming the source and the entry; a source elsewhere inside the target stays allowed (D-ROOTS) | the run must not remove its own source or running engine | TEST-4003 |
| DR-34 | `core:` must be followed by LF; a CR ends up in the line and the block never opens | the line is read without its CR (`Get-Content`), so a CRLF manifest works | a CR before the line feed ends the line and is no part of it; every other DR-10 rule is unchanged | a Windows checkout (core.autocrlf) holds `PROFILES.yaml` with CRLF; the module refused it with no core entries where the PowerShell twin worked | TEST-4003, TEST-4007 |
| DR-35 | device and inode compared as Numbers | the same | read as bigint; a zero device or inode, or a Number beyond 2**53, is no identity and two unknown identities are compared by real path spelling (`realpathSync.native`, else `realpathSync`; case-insensitive on win32), never taken for one file; every `realpathSync.native` call of the module falls back to `realpathSync` when it throws | Windows file ids pass 2**53 and some file systems report inode 0, which made unrelated directories one file (PR review) | TEST-4003, TEST-4004 |

Run 8 amendment (additive with disclosure, Remediation after Validation
round 1): DR-31 is added after the fact. Validation found that the shipped
snapshot write in `lib/merge-hooks-json.mjs` followed a link at
`.aai/cache/hooks-shipped/<name>` and overwrote a file outside the target
(both twins did; `fu-sync-shipped-snapshot-link-escape`, closed by this
amendment's fix). The owner policy is that a write outside the target is never
acceptable, so the module replaces the link and the merge temp file is created
exclusively after any entry at its name is removed. TEST-4008 gains the DR-31
case. The other writes of the module were checked and already hold: the
`.gitignore` append and every managed top-level path are refused when they are
links leaving the target (DR-7, DR-29), `writeManaged` removes a link before it
writes (the report, the pin, the overrides and the shim), the self-heal temp is
created exclusively, and `copyTree` creates files exclusively.

Run 9 amendment (additive with disclosure, Remediation after Code Review
round 1): DR-32 and DR-33 are added. Review B1: the DR-5 refusal and the path
guard compared `fs.realpathSync` spellings, which keep the case the caller
typed, so on a case-insensitive file system a case variant of the source was
not refused and a source file was deleted. The module now reads both roots
with `fs.realpathSync.native`, and `resolveRoots` and `underRoot` also walk
the ancestors by device and inode (`lib/resolve-base.mjs` already compares
the working directory by device and inode and needed no change). Review N1:
`underRoot` guards only the parent of a path, so a source inside a managed
entry of the target was removed by the run itself; `resolveRoots` now refuses
that case up front (D-ROOTS still allows a source elsewhere in the target).
TEST-4003 gains one case per DR (the DR-32 case names its skip reason on a
case-sensitive file system and detects it at runtime). Review N2:
`io.platform`, listed in the D-MODULE `io` fields, is not read by the module
and is removed from that list; the module writes the paths the host gives it
(DR-23), so the TEST-4011 case is renamed to what it checks on POSIX and the
Windows form is hosted evidence H2, which is why `fu-parity-win-source-path`
is reopened. Review N5: `removeOwnScratch` now removes the children first and
the ownership marker last (TEST-4000 gains the case). Review deviations,
stated here and superseding the older sentences: (a) D-COPY "temp files (the
self-heal, the advisory, the pin)": only the self-heal uses an exclusive
temp; the advisory and the pin are written through `writeManaged` (a link at
the name is removed first, then the file is written), as the bash twin wrote
them with `cat >`; (b) the Ceremony and D-WIRE sentences that
`docs/ai/docs-audit.yaml` and WORKFLOW.md are not touched are superseded by
Spec-AC-23, which touches both lists (amendment recorded earlier); (c) N6,
Spec-AC-08 and D-COPY ("never delete a temp the run did not create") read as
excepting the DR-31 merge temp `<dir>/.<name>.<pid>.tmp`: its name carries
the run's own pid inside the target's `hooks/` directory, DR-31 removes a
pre-existing entry at that exact name before the exclusive create, and
nothing outside the target is touched. N3 (Windows PowerShell 5.1 native
argument quoting in `aai-sync.ps1`) is filed as a follow-up and not changed
here.

Run 10 amendment (additive with disclosure, Remediation after the hosted
CI run of the pull request): DR-34 and DR-35 are added, and two evidence
fixes follow from the hosted Windows and release rehearsal jobs. DR-34: the
Windows jobs of CI (native Windows PowerShell 5.1 and pwsh 7, the worktree
seed and the merge cleanup Pester files) synced with `-Profile core` from a
checkout holding `.aai/system/PROFILES.yaml` with CRLF line ends, and the
module found no core entries because DR-10 read `core:` exactly and the CR
stayed in the line. `parseCoreList` now removes a CR before the line feed from
every line; the rest of DR-10 (a tab-indented line closes the block, `core:`
plus spaces does not open it) is unchanged, and the TEST-4003 pin that a CR
after `core:` does not open the block is replaced by its opposite. Every
other text the module reads was checked for the same class: the pin's profile
line, the version line, the Copilot overrides, the shipped list and the
gitignore lists already remove a CR, `hooks.json` is JSON. DR-35 (the Codex
review comment on `sameFile`, closes `fu-sync-win-ino-identity-precision`):
the module reads each real path through `realNative`, which falls back to `realpathSync` when `realpathSync.native` throws (a Windows volume without it
made the roots unreadable); the identity compare moves to `lib/resolve-base.mjs` as the third export
`sameFile`, so the D-BASE sentence "exports exactly `resolveBase` and
`resolveFromBase`" now reads three names; `resolveBase` and the sync module
both use it, and `aai-sync.mjs` imports it on a second import line from the
same lib (the pinned import line is unchanged). Evidence fixes, no behaviour
change of the module: (a) the install-parity allowlist rows
`win-source-path-pin` and `win-source-path-report` accept the `syref` copy
(the frozen twins run from it) besides `fx/src`, and the rows
`sync-source-path-pin` and `sync-source-path-report` stand before the paired
Windows rows, because the first row in file order whose regex matches a line
judges it and a paired row matching every line claimed the Source line;
(b) `test-aai-sync-node.sh` no longer names the change log in one piece,
because the release rehearsal enlists every suite whose text names it as a
reader and runs it under a 540 second timeout; this suite takes minutes, read
nothing of the log, and starved the readers behind it (TEST-4019 now checks
the rehearsal's reader list holds `test-aai-sync-docs.sh` and not this suite).
No owner sign-off was obtained for any of these; the owner's merge direction
signs them.

Kept for parity, pinned as rules and not drifts: the `^\.aai/` prefix reading
of the `.aai/` ignore line; a copy-replaced directory loses target-added
files inside it; the eighteen directories created up front; the extended
profile never reads the manifest; target-only `.aai/scripts/` entries and
`.aai/cache/` survive both profiles; the conflict texts and the PRESERVE,
SEED, SYNC, MERGE, SKIP, CLEAN and PROFILE lines; a second sync in the same
second overwrites that second's report. Any further divergence the corpora
show is added here as a DR row by a recorded amendment before its case is
registered, never normalized away.

### D-REF. Frozen copies of both twins and the library

`tests/fixtures/sync-reference/aai-sync.sh` (byte copy of blob `f42b62ca`,
sha256 `00aac687...`, mode 100755), `tests/fixtures/sync-reference/aai-sync.ps1`
(blob `d7ab810f`, sha256 `038a640a...`, mode 100644) and
`tests/fixtures/sync-reference/gitignore-block.sh` (blob `8402ac80`, sha256
`5544c839...`, mode 100644), LF through the existing `.gitattributes` rules.
`tests/skills/lib/sync-reference.mjs` exports `REFERENCE_SH`,
`REFERENCE_PS1`, `REFERENCE_LIB`, their `*_SHA256`, `REFERENCE_COMMIT`
(`077ee649`), `ENGINE_FILES_REFERENCE` (`.aai/scripts/aai-sync.sh`,
`.aai/scripts/aai-sync.ps1`, `.aai/scripts/lib/gitignore-block.sh`),
`ENGINE_FILES_MODULE` (`.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
`.aai/scripts/aai-sync.mjs`, `.aai/scripts/lib/resolve-base.mjs`,
`.aai/scripts/lib/gitignore-block.mjs`),
`materializeSyncReference(sourceRoot)` (verifies the three hashes, a mismatch
throws naming the file; writes the two twins over
`<sourceRoot>/.aai/scripts/aai-sync.{sh,ps1}` with modes 0755 and 0644 and the
library at `<sourceRoot>/.aai/scripts/lib/gitignore-block.sh`, and removes the
module-side engine files, because both twins take their source from their
own location), and its own scratch helpers `createOwnScratch`,
`removeOwnScratch`, `removeOwnScratchAll` with `const OWN_SCRATCH_PREFIX =
'aai-sy-';` and the marker `.aai-sy-owned`, with the SPEC-0306 D-SAFETY
refusal rules. Where git history holds `077ee649`, TEST-4000 also requires
each copy to equal `git show 077ee649:<path>`. The copies live outside
`.aai/` (never vendored) and outside the ratchets' scan directories.
`materializeBootstrapReference` (SPEC-0306) writes the frozen library into
its tree, so the frozen bootstrap reference keeps sourcing it after the
shipped library is deleted.

### D-CORPUS. The differential corpora

In `tests/skills/lib/aai-sync.test.mjs` (POSIX hosts; bash and git; pwsh for
the PowerShell side). A synthetic source fixture `S` (built by
`aai-sync-fixtures.mjs` or the test file): a git repository with a fixed
identity and fixed author and committer dates, so its commit id is the same
on both sides, holding a small `.aai/` (an `AGENTS.md`, `workflow/`,
`roles/`, `knowledge/`, one `SKILL_X.prompt.md`, `templates/` with the three
seed templates, `system/` with a 12-entry `PROFILES.yaml`, the real
`RUNTIME_IGNORE.list` and `COPILOT_SHIM_SHIPPED.list`, `scripts/` with a
mode-0755 `tool.sh` and the real `lib/merge-hooks-json.mjs`), one skill in
each skill tree, `.codex/skills` and `.gemini/skills` with a top-level
README, `.claude-plugin/plugin.json`, `.cursor/rules/aai.mdc`,
`.github/copilot-instructions.md`, `hooks/` with `hooks.json`,
`hooks.windows.json`, `session-start.sh` and `.hidden-hook.sh`, one
sentinel file under `docs/knowledge`, `docs/ai/AAI_VERSION.md`, the five
root shims and `README.md`, and one tag. The engine files are untracked:
the reference side gets `materializeSyncReference`, the module side the
module, both launchers and the two libs. Each case builds its fixture once
per side at the same absolute path under one own scratch root (the previous
side's trees renamed away first). Both run with cwd the case directory and
the environment: the caller's minus every `AAI_` and every `GIT_` variable,
plus `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL` an empty scratch file,
`LC_ALL=C`, `PWD` the cwd, `TMPDIR` a per-case scratch directory.

- Normalization on both sides, registered once (not a divergence): the
  `- Synced at (UTC):` value, the advisory's file-name stamp and its
  `- Generated at (UTC):` value.
- Bash side (TEST-4013): `bash <S>/.aai/scripts/aai-sync.sh <args>` (the frozen
  twin) against `node <S>/.aai/scripts/aai-sync.mjs <args>`. Compared: exit
  code, stdout bytes, stderr bytes, and the target snapshot: every path under
  the target except `.git/` internals and the engine files of each side
  (whose presence per side is asserted), each with its type (file, link with
  its target text, directory), bytes and `mode & 0o777`; plus the source
  tree's snapshot before and after (unchanged, except in K25 on the bash
  side) and the `TMPDIR` listing. Rewrites before comparing, each registered
  per case on one side, a registered rewrite that changes nothing failing
  the case (an order rewrite, which only sorts, may change nothing, because the
  bash order is undefined): DR-14 (the pointer line), DR-21 (the Template
  version spacing, BSD sed only), DR-4 (an `ERROR:` line moved from stdout to
  stderr), DR-26 (the bash prune lines and Deleted items sorted), DR-28 (the
  two-line commit). Every line that names an engine file of either side (a
  prune, PRESERVE or missing-listed line and a Deleted item) is dropped from
  both sides, because each side's own engine files differ by construction.
- PowerShell side (TEST-4014): `pwsh -NoProfile -NonInteractive -File
  <S>/.aai/scripts/aai-sync.ps1 <PowerShell-form args>` against the module
  with the same arguments. Compared: exit code and the target snapshot after
  four registered projections, each a DR the module took from the bash side:
  the `.gitignore` reduced to its set of pattern lines (order, blank lines,
  comment headers and marker text, DR-11), the report without backticks and
  the pin without the Template version spacing (DR-20, DR-21), the report's
  Deleted items sorted (DR-26) and the hook files without their execute bits
  (DR-18); the asserted divergences below are compared to an expected value.
  Where pwsh is absent the suite skips the side with a named reason and the
  Windows CI job (`ps1-quality`) runs it.
- Asserted divergences (not rewritten): K17 and P15 (DR-13), K18 and P11
  (DR-1), K19 to K23 and P13 (DR-2), P12 (DR-25), K25 and K26 (DR-5), K27
  (DR-7), K29b (DR-30), K32a (DR-29), P06 (DR-11), P07 (DR-17), P08 (DR-18),
  P10 (DR-16), P16 (DR-15), P17 (DR-27).

Bash-side cases (K):

- K01 a fresh empty `git init` target, default profile; K02 K01 twice (the
  second run writes no advisory and leaves the tree byte-identical but the
  normalized stamps); K03 `--profile core` fresh; K04 extended then core
  (extended-only files pruned, a target-only `.aai/scripts/x.sh` preserved,
  `.aai/cache/keep` kept, emptied directories removed, Deleted items in the
  advisory); K05 core then no flag (sticky core), K05b then `--profile
  extended`; K06 a pin whose first `- Profile:` line reads `bogus` and a CRLF
  pin.
- K07 the core list padded with 20,000 fake entries (more than a pipe
  buffer): every real core file present and none pruned, both runs.
- K08 extended with a stale `.aai/OLD.md` (cleaned) and a target-only
  `.aai/scripts/own.sh` (preserved).
- K09a no `.gitignore`; K09b a CRLF `.gitignore`; K09c a `.gitignore` with
  every managed block twice (self-heal); K09d only `.aai/cache/` present (the
  prefix reading); K09e a 200 KB `.gitignore` with the managed lines at the
  top; K09f the `.ps1` marker text already present; K09g no list in the
  source (the target's list is used); K09h no list anywhere (the note); K09i
  no `.gitignore` at all.
- K10 skill trees: a differing template `SKILL.md` (conflict), an
  `aai-project-x` skill kept, a retired wrapper removed, a near-miss wrapper
  (one changed byte) kept, a symbolic-link entry kept; K11 differing
  `.codex/skills` and `.gemini/skills` (conflict) with `skills.local` kept.
- K12 knowledge: a target file with the sentinel replaced, one without it
  skipped; K13 the three seeds absent (seeded) and present (kept); K14
  differing root shims and `README_AAI.md` (conflicts).
- K15a Copilot shim absent, K15b identical, K15c an older shipped shim (hash
  listed: replaced), K15d a project-overrides block (merged), K15e the
  override file fallback.
- K16a a target-only hook kept; K16b `hooks.json` absent; K16c a malformed
  `hooks.json` (refused, untouched); K16d a user-modified entry (LEFT-AS-IS);
  K16e the dotfile hook; K16f `session-start.sh` executable afterwards.
- K17 a legacy-layout target (`ai/x`, `scripts/tool.sh`, `scripts/ai-os-old.sh`,
  `PLAYBOOK.md`, `docs/workflow/x.md`, `docs/ai/LOCKS.md`,
  `docs/knowledge/PATTERNS_UNIVERSAL.md`).
- K18 `-h`; K19 `--bogus` with a target; K20 no argument; K21 two
  positionals; K22 a bare `--profile`; K23 `--profile=bogus <target>`; K24 a
  missing target directory.
- K25 the target is `S` itself; K26 the target is `S/sub`; K27 a target whose
  `.claude/skills` is a link to a directory outside the target.
- K28 a target path holding a space and `[ ]`; K29 a relative `../t` from a
  symlinked cwd with `PWD` the logical path, present on both readings, K29b
  present only logically (DR-30); K30a no `AAI_VERSION.md` (the tag fallback),
  K30b a source repository without a commit (DR-28), K30c a source without git
  (UNKNOWN), K30d neither a tag nor a version file.
- K31a dangling links at the top level of the source's and the target's
  globbed directories and one nested in a copied directory (DR-27, DR-15);
  K31b extended then core with links in the target's `.aai`; K32a a
  `.gitignore` that is a link leaving the target (DR-29), K32b one that stays
  inside it.
- KR1 and KR2: a committed scratch copy of this checkout's tracked files as
  the source, extended and core, into empty targets (the whole layer, once
  each).

PowerShell-side cases (P), PowerShell-form arguments:

- P01 fresh `-TargetRoot <t>`; P02 twice; P03 `-Profile core`; P04 extended
  then core; P05 sticky; P06 a CRLF `.gitignore` with duplicates; P07 a
  Copilot overrides block; P08 a `hooks.json` merge and `session-start.sh`;
  P09 skill conflicts and a retired wrapper; P10 a knowledge file holding
  `aai-template` in lower case; P11 `-h`; P12 no `-TargetRoot` (pwsh with
  `-NonInteractive`); P13 `-Profile bogus`; P14 a missing target; P15 the
  K17 legacy layout; P16 a dangling link nested in a source skill (DR-15);
  P17 a dangling link as a top-level entry of the source's `.claude/skills`
  (DR-27).

After every case the case's scratch root holds no entry besides its
fixtures, the logs and the marker, and no path outside the case directory
changed (a snapshot of the case's parent directory before and after).

### D-PARITY. The parity harness takes the module as a third twin on sync

Changes to `tests/skills/lib/install-parity.mjs`:

- `ctx.syref`: built once per run when a selected scenario has op `sync`: a
  copy of the run's scratch source with `materializeSyncReference` applied.
  sh twin, sync: `bash <syref>/.aai/scripts/aai-sync.sh <target> [--profile
  p]` (the frozen bash twin); ps1 twin, sync: `<ps> ...psHead
  <syref>/.aai/scripts/aai-sync.ps1 -TargetRoot <target> [-Profile p]` (the
  frozen PowerShell twin), so sh:ps1 keeps comparing the two old twins
  natively on Windows 5.1 and 7. node twin: `ops: ['bootstrap', 'update',
  'hooks', 'sync']`, sync argv the exact line
  `      if (step.op === 'sync') return { file: process.execPath, args: [path.join(ctx.src, '.aai', 'scripts', 'aai-sync.mjs'), ctx.target, ...(step.profile ? ['--profile', step.profile] : [])], cwd: ctx.target };`
  Sync scenarios compare all three pairs. `buildSource` copies the tracked
  files plus the module and the two libs when they are untracked (so a run
  before the first commit of a new file is not silently stale).
- Allowlist: the sync rows that describe a `.ps1` behaviour the module did
  not take (rows 9 to 14, 19, 22 to 24: `pin-synced-at-precision`,
  `gitignore-block-order`, `gitignore-block-headers`,
  `session-start-exec-bit`, `conflict-report-name-local-time`,
  `conflict-report-generated-precision`, `conflict-report-next-step-backticks`,
  the three `win-ps1-*-newline-bom` rows) widen their pairs to add `ps1:node`
  with the reviewed reason appended "the module takes the bash side (DR-n)".
  `pin-template-version-spacing` (bsd-sed) and the two `win-source-path-*`
  rows add `sh:node` (DR-21, DR-23). One new row `sync-engine-files` (pairs
  `sh:node,ps1:node`, paths `.aai/scripts/aai-sync.*`,
  `.aai/scripts/lib/gitignore-block.*`, `.aai/scripts/lib/resolve-base.mjs`)
  with the reviewed reason "the frozen twins vendor themselves and the bash
  library; the module side vendors its launchers, the module and its libs".
  No other new row; a divergence a hosted run shows gets a DR, a row and a
  follow-up in a remediation pass, never a normalization (SPEC-0284
  D-ALLOW). The stale-row check (a row covering nothing for a pair that ran)
  keeps failing a whole-tier run.
- No scenario, tier or normalization changes. UP scenarios are unchanged: the
  updaters already run the source's sync file, now the launcher.
- Run 6c amendment (measured, additive with disclosure): the frozen twins run
  from `syref`, a second path, so the pin's `Source path` line and the
  report's `Source` line differ for them (rows `sync-source-path-pin` and
  `sync-source-path-report`, host any, pairs `sh:node,ps1:node`, replacing the
  planned widening of the two `win-source-path-*` rows, which cannot cover the
  `syref` spelling); the one planned row `sync-engine-files` is three rows
  because a row has one path glob and one kind (`sync-engine-files` missing
  `.aai/scripts/aai-sync.*`, `sync-engine-launchers` lines, `sync-engine-libs`
  missing `.aai/scripts/lib/*`); the frozen twins also prune the bash library
  on SY-06 step 2 (`sync-pruned-bash-library`) and keep nothing of the legacy
  layout on SY-07 (five `sync-legacy-moves-dropped-*` rows, DR-13); the three
  `sy06-*` self-pair rows gain `node:node`; `syref` is built when a twin first
  reads it (a getter), so runs without a frozen sync twin build none.

### D-LAUNCH. Launchers

- `.aai/scripts/aai-sync.sh`: at most 20 lines, ASCII, `#!/bin/sh`, POSIX
  only (sh, dash, bash), mode 100755:

  ```sh
  #!/bin/sh
  # AAI layer sync launcher; argument, profile, copy, prune and gitignore rules live in aai-sync.mjs (RFC-0017 phase 5).
  # Usage: bash .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended] [-h]
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-sync.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    exec node "$MODULE" "$@"
  fi
  echo "aai-sync: refused - node not found in PATH or aai-sync.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
  exit 1
  ```

- `.aai/scripts/aai-sync.ps1`: at most 20 lines, ASCII, no param block, 5.1
  and 7 compatible; it sets `$ErrorActionPreference = 'Continue'` and
  `$PSNativeCommandUseErrorActionPreference = $false` in its own scope, runs
  `node <PSScriptRoot>/aai-sync.mjs` with the marshalled arguments and `exit
  $LASTEXITCODE`; without node or the module it writes `aai-sync: refused -
  node not found in PATH or aai-sync.mjs missing; nothing was changed.
  Install Node.js 22 or later (https://nodejs.org/) and re-run.` with
  `[Console]::Error.WriteLine` and exits 1. Argument marshalling is the
  ride-11 rule (an array element joined with `,`; a `-Name:` token loses its
  colon; a `Boolean` element is not passed and `$false` drops the token
  before it; every other element as its string); it names no flag.
- Neither launcher names git, a profile, `.gitignore`, `PROFILES`, `exit 2`,
  or any flag outside its two comment lines.

### D-UPGRADE. The bootstrap problem: old installs, old updaters and the first update

The design, proven by TEST-4018:

1. `/aai-update` always runs the SOURCE's sync file: `aai-update.mjs`
   (`syncCommand`), the pre-ride-10 frozen updaters and `install.sh` /
   `install.ps1` all call `<materialized source>/.aai/scripts/aai-sync.{sh,ps1}`.
   After this release that file is the new launcher, which finds the module
   beside itself in the same source tree. So the first update of an old
   install is already performed by the module, whichever updater the target
   has; the target's own (old) sync file is never run by an update.
2. Which file set is copied and pruned on that first update is decided by
   the SOURCE tree and its `PROFILES.yaml`, never by the version of the
   engine that runs: extended copy-replaces every `.aai/` entry of the source
   (the `scripts/lib` directory as a whole, so the old
   `lib/gitignore-block.sh` disappears) and keeps target-only scripts; core
   copies exactly the source's core list and prunes the target's other
   `.aai/` files (target-only scripts and `.aai/cache/` kept). Therefore
   PROFILES core must list the module and every library it and the three
   switched modules import, `check-vendored-script-deps.mjs` must exit 0,
   and the old `lib/gitignore-block.sh` must leave the core list.
3. The same rule answers the case where an OLD engine copies a NEW tree (a
   frozen twin placed into a new tree, as the parity harness's sh and ps1
   twins do): it vendors the module and the libs (both profiles), and the
   target's `aai-sync.sh` is whatever file the running source carries (the
   frozen twin there); the next update from a new source replaces it with
   the launcher.
4. Node: the new launcher refuses without Node, exit 1, nothing changed. A
   consumer that can run `/aai-update` already has Node (the updater is Node
   since ride 10); `install.sh` / `install.ps1` stop at the launcher's
   refusal line.
5. The `.ps1` entry keeps `-TargetRoot` and `-Profile` (D-CLI), the argument
   forms every caller uses.

TEST-4018 (scratch only, never this checkout as a target):

- U0 scratch install: `bash .aai/scripts/aai-sync.sh <scratch>/t --profile
  core` from this checkout; the module, both launchers and both libs exist
  in `t`; then `t` used as a source: `bash`, `sh` and `<pwsh> -File` of the
  vendored launchers each sync `t` into fresh targets at one path with
  byte-equal trees (after the stamp normalization); `sh` with PATH holding
  only `dirname` exits 1 with the D-LAUNCH line and the fresh target stays
  empty; `bash install.sh --source-root <committed scratch copy> --target-root
  <scratch>` exits 0.
- U1 old install, new updater: `S_old` = a committed scratch copy of this
  checkout's tracked files with `materializeSyncReference` applied, the
  module-side engine files removed and PROFILES core restored to the
  baseline's sync lines; the frozen bash twin of `S_old` installs `T_core`
  (`--profile core`) and `T_ext`; then `bash <T>/.aai/scripts/aai-update.sh
  --repo <S_new> --force` (`S_new` a committed scratch copy of this
  checkout's tracked and staged files) exits 0 for both. Then each target
  holds the new launchers byte-equal to `S_new`'s, the module and both libs,
  no `lib/gitignore-block.sh`; `T_core`'s pin still reads `- Profile: core`
  and its advisory's Deleted items list exactly the `.aai/` files of `T_core`
  that `S_new`'s core list lacks (none of `S_new`'s core files missing); and
  the target's launchers run: `aai-sync.sh` from the target into a fresh
  target exits 0, `aai-update.sh --dry-run`, `install-pre-commit-hook.sh
  --print index` and `aai-bootstrap.sh --help` exit 0 (the import closure of
  the switched modules arrived).
- U2 old engine, new tree: the frozen bash twin placed into a copy of
  `S_new` syncs into fresh targets with `--profile core` and extended; the
  module and both libs are vendored in both, the target's `aai-sync.sh`
  equals the frozen twin; a following `aai-update.sh --repo <S_new>
  --force` leaves the launcher.
- U3 the pre-ride-10 updater: a target whose `.aai/scripts/aai-update.sh` is
  the frozen bash update reference (`tests/fixtures/aai-update-reference/aai-update.sh`)
  updates from `S_new` (its `--repo` form) with exit 0 and the U1 end state.
- U4 the PowerShell runner (pwsh through `need_tool`): `aai-update.mjs` with
  `AAI_UPDATE_SYNC_RUNNER` the pwsh path updates a U1-style core target from
  `S_new` with exit 0 and the U1 end state.

- Run 7a amendment (measured, additive with disclosure): (a) a core target
  keeps `lib/gitignore-block.sh` after the first update. Both frozen twins
  preserve a `.aai/scripts/` path the source does not have as a target-only
  script (`PRESERVE target-only script`), and the file left the source with
  this ride, so only an extended target (which copy-replaces `scripts/lib`
  as a whole) loses it; the cases assert the preserved line and an inert
  file for core, and the absence for extended. (b) `S_old` is the real old
  layer: `git archive` of commit 077ee649 into the scratch root (read-only
  on this checkout; the frozen bash twin's hash is asserted equal to the
  reference pin), not a modified copy of this checkout, because the switched
  modules of this checkout import `resolve-base.mjs`, which a copy without
  the module-side files could not load. (c) The prune oracle is computed
  independently from the target's pre-update `.aai/` list and the new core
  list, with a planted non-core file, a `.aai/cache/` file and a target-only
  script.

Every run with the D-SAFETY environment; every target, source and cwd under
the suite's own scratch root.

### D-PESTER. `tests/skills/aai-sync.Tests.ps1`

A new Pester 5 file, 5.1-compatible syntax, never skips, launching with the
running engine through `ProcessStartInfo` with an explicit PATH, scratch only
under `$TestDrive`, git with `GIT_CONFIG_NOSYSTEM=1` and an empty
`GIT_CONFIG_GLOBAL`:

1. Pass-through under `-File`: the launcher copied beside a stub module that
   writes its argv as JSON and exits 7; `-TargetRoot "C D" -Profile core --
   x` arrive in that order unchanged, exit 7.
2. In-session marshalling: one child engine runs `& <copied launcher>
   -TargetRoot:<t> -Profile core`; the stub records `-TargetRoot`, `<t>`,
   `-Profile`, `core`.
3. Refusal: PATH an empty `$TestDrive` directory; exit 1, stdout empty,
   stderr exactly the D-LAUNCH line, the target unchanged.
4. Module missing: the launcher copied alone; the same refusal.
5. Real run: a `$TestDrive` copy of the D-CORPUS fixture with the module
   side's engine files; the launcher with `-TargetRoot <t> -Profile core`
   (in session) exits 0 and `<t>/.aai/system/AAI_PIN.md` reads `- Profile:
   core`; `-Profile bogus` exits 2.

It runs in the existing jobs through directory discovery (Linux `gate`,
`windows-5_1` with both engines, `windows-wsl1`); no job, step or exclusion
is added; the TotalCount floor 111 and `AAI_EXPECTED_WIN_SKIP_COUNT` 4 stay.
Budget: at most 30 s per engine on a hosted runner.

### D-SAFETY. Scratch only, no daemon, delete only what the run made

- Syncs run only into targets the test created under its own scratch root,
  from sources that are this checkout (read only) or scratch copies. Every
  sync invocation in the new suite, the node:test files, the corpora and the
  Pester file goes through one helper per language (`run_sync_scratch` in the
  suite, `runSync` for a child and `runInProcess` for an in-process `run()`
  in node:test) that asserts, before the run, that the target's real path is
  under the run's own scratch root and not under this checkout, and that
  every `GIT_` variable is removed except `GIT_CONFIG_NOSYSTEM=1` and an
  empty `GIT_CONFIG_GLOBAL`; a static scan (TEST-4000) finds no other call of
  `aai-sync.sh`, `aai-sync.ps1`, `aai-sync.mjs`, `run(` or `main(` of the
  module in those files. In-process runs pass the scrubbed environment as
  `io.env` (the ride-11 B1 rule: a universal claim holds for every path).
- After each run the helper asserts that every path the run wrote or deleted
  lies under the scratch root: the snapshot of the case's parent directory
  and of the source is unchanged outside the target.
- No container daemon: no test or mutation calls `docker`, `pkill`,
  `killall` or a kill by pattern; children are synchronous; the suites run
  under `aai-run-tests.sh`, whose isolation points `DOCKER_HOST` at a
  nonexistent socket.
- Deletion: the module deletes only inside the managed set under the
  re-verified target (D-ROOTS, D-LEGACY) and its own temp files. Test scratch
  is removed through `removeOwnScratch` (prefix `aai-sy-`, marker
  `.aai-sy-owned`) or the suite's `safe_rm_own` (prefix `aai-sync-node.`),
  each refusing an empty path, a relative path, a foreign prefix, a path
  outside the temp directory, a symbolic link and an unmarked directory,
  re-reading the marker right before removing, and treating an empty list
  as a failure; the suite removes its scratch from an EXIT trap and the
  node:test files from `after()` hooks, so a failing case leaves nothing
  behind. Pester uses `$TestDrive`.

### D-GITENV. The installer suites scrub the caller's git environment (closes fu-suite-git-env-scrub-class)

Measured as cheap and the same class (tests passing the caller's `GIT_*`
through and never asserting the written path under scratch): one shared
helper `tests/skills/lib/git-env-scrub.sh` with `aai_git_scrubbed <cmd...>`
(runs the command with every variable whose name starts with `GIT_` removed,
then `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL` an empty file under the
caller's scratch root, refusing when that root is empty or relative) and
`aai_assert_hooks_under <dir> <root>` (`git -C <dir> rev-parse --git-path
hooks/pre-commit` under the scrubbed environment resolves under `<root>`,
else the caller's test fails). Used by `test-aai-git-ref-guard.sh`
(`install_guard`, `git_isolated`, `install_module`, `install_ps1`, and the
comment at lines 167 and 168 corrected), `test-aai-hygiene-pack.sh` test_618's
installs, and the installer runs of `test-aai-doctor.sh` and
`test-aai-pre-commit-checks.sh` (each found by its call of
`install-pre-commit-hook`), and by the new sync suite. The runner-level scrub
in `aai-run-tests.sh` is not done here (it changes every suite's environment;
kept native by the plan). TEST-4012 runs the recorded repro
`docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh`
(exit 0 required) and the same injection (`GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<victim>`, and
`GIT_CONFIG_PARAMETERS`) against one selector each of hygiene test_618, the
doctor suite and the pre-commit-checks suite, requiring the victim directory
(a scratch directory, not a repository) to stay empty.

### D-REHOME. Existing tests that read the old twins, and their amendments

Each named change gets one unsigned amendment record (`node
.aai/scripts/spec-amend.mjs add --spec <spec> --ref sync-on-node --class
contract --signoff none --what "<what>" --why "<one line>"`; the owner's
merge direction signs them). The property each removed text pin stood for
keeps a behaviour test; nothing is dropped without one. Re-homed functions
keep their names and test ids (the selectors of TEST-4015 and TEST-4016 name
them). A test whose id no spec's Test Plan carries (layer-profiles TEST-464
to TEST-466, sync-seed TEST-795 and TEST-831) is re-homed without a record;
its header names its source.

- Run 2, with D-BASE: `aai-update.test.mjs` TEST-3961 and
  `aai-bootstrap.test.mjs` TEST-3941 allow exactly the relative import
  `./lib/resolve-base.mjs` (records for SPEC-0307 and SPEC-0306, what begins
  `TEST-3961 allows the shared base lib` and `TEST-3941 allows the shared
  base lib`); `install-pre-commit-hook.test.mjs` TEST-3981 allows
  `./lib/guard-config.mjs` and `./lib/resolve-base.mjs` (SPEC-0308, `TEST-3981
  allows the shared base lib`); `vendor-hook-installer.sh`,
  `install-pre-commit-hook.Tests.ps1` `Copy-Installers`,
  `test-aai-update-node.sh` TEST-3973's copy, `aai-update.Tests.ps1` and
  `aai-bootstrap.Tests.ps1` vendor the lib (SPEC-0308 record what begins
  `vendor-hook-installer.sh vendors the shared base lib`).
- Run 6a, with the `.sh` swap and the library deletion:
  - `test-aai-sync-seed.sh` TEST-003 and TEST-006 (template names: on the
    module), TEST-011 (no shipped `.sh` reads `RUNTIME_IGNORE`; the module
    imports the one reconcile), TEST-012 and TEST-013 (PROFILES core lists
    `lib/gitignore-block.mjs`, a core sync keeps it), TEST-014 and TEST-021
    (the lib's missing-list note and CRLF case on `gitignore-block.mjs`),
    TEST-016 (the list's header names `aai-bootstrap.mjs`, `aai-sync.mjs` and
    `lib/gitignore-block.mjs`), TEST-020 (the prefix pinned in three copies:
    the lib constant, the bootstrap marker, the sync marker), TEST-628 (the
    byte compare fails closed: on the module), TEST-783 (no node: the
    launcher refuses and leaves `hooks.json` untouched; DR-18), TEST-795 and
    TEST-796 (the profile reader and the cache adoption on the module and
    the launcher), TEST-831 (the predicate's ordinal compares on the module
    with U+200B, U+FEFF, NFD and BOM inputs). Records for SPEC-0106
    (`TEST-003 and TEST-006 re-homed`), SPEC-0157 (`TEST-011 to TEST-021
    re-homed`), SPEC-0184 (`TEST-628 re-homed`), SPEC-0199 (`TEST-783
    re-homed`), SPEC-0216 (`TEST-796 re-homed`).
  - `test-aai-layer-profiles.sh` TEST-008's `.sh` pin, TEST-464 and TEST-465
    (run through the launcher, the module's `Set` lookup), TEST-466 (the
    no-pipe check moves to the module: no `spawn` of a shell, no `|` in a
    child command line). Record for SPEC-0035 (`TEST-008 re-homed`).
  - `test-aai-layer-drift.sh` TEST-010 and `test-aai-update-check.sh`
    `build_sync_source` copy the module and the libs with the launcher
    (records for SPEC-0020 `TEST-010 vendors the module` and SPEC-0106
    `build_sync_source vendors the module`).
  - `test-aai-harness-shims.sh` TEST-3008 case d: the stubbed hash tools no
    longer matter; the case asserts the shipped shim is replaced (DR-19).
    Record for SPEC-0253 (`TEST-3008 case d re-homed`).
  - `release-notes-docs.test.mjs` TEST-2708 reads `ROOT_SHIMS` from the
    module. Record for SPEC-0250 (`TEST-2708 reads ROOT_SHIMS`).
  - `test-aai-legacy-migrations.sh` TEST-3396: the pointer lines are the
    module's DR-14 text; `copy_tracked` includes the untracked module.
    Record for SPEC-0273 (`TEST-3396 re-homed`).
  - `test-aai-bootstrap.sh` TEST-017 and `aai-bootstrap.test.mjs` TEST-3948
    (the shipped library is absent; the bootstrap still seeds the 30
    patterns), `bootstrap-reference.mjs` (writes the frozen library). Record
    for SPEC-0306 (`TEST-3948 the shipped bash library is gone`).
- Run 6b, with the `.ps1` swap and the parity twin: `test-aai-sync-seed.sh`
  TEST-003, TEST-006, TEST-020 and TEST-795 `.ps1` pins, TEST-007 to
  TEST-010, TEST-015, TEST-022, TEST-779, TEST-788, TEST-790, TEST-791,
  TEST-829, TEST-830 and TEST-833 (their `.ps1` arms run the launcher under
  pwsh); `test-aai-layer-profiles.sh` TEST-008 (`.ps1` pins become a pwsh run
  of the launcher with core and default file sets equal to the bash ones);
  `test-aai-layer-drift.sh` TEST-010b; `install-parity.mjs`,
  `install-parity.test.mjs` and the allowlist (D-PARITY; record for SPEC-0284
  `D-SEAM sync twins run the frozen references`); `test-aai-install-parity.sh`
  TEST-3571 (path lists hold `aai-sync.mjs` and the two libs, not
  `gitignore-block.sh`); `aai-bootstrap.test.mjs` TEST-3956 (the node twin's
  operations gain `sync`; record for SPEC-0306 `TEST-3956 node twin
  operations`).
- Unchanged and passing (checked in the sweep): `test-aai-routine.sh`
  TEST-019 and TEST-3672 (negative pins, they now also scan the module),
  `test-aai-sync-seed.sh` TEST-778 (the old engine's advisory equals the
  module's), `test-aai-layer-profiles.sh` TEST-002 (the pre-profile engine
  equals the default run), the about 70 behaviour runs from this checkout,
  `test-self-hosting-smoke.sh` and `.ps1`, `golden-flow`, and the Pester
  files that run the sync.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-sync-node` with globs
  `.aai/scripts/aai-sync.*`, `.aai/scripts/lib/resolve-base.mjs`,
  `.aai/scripts/lib/gitignore-block.mjs`, `.aai/scripts/lib/merge-hooks-json.mjs`,
  `.aai/system/PROFILES.yaml`, `.aai/system/RUNTIME_IGNORE.list`,
  `.aai/system/COPILOT_SHIM_SHIPPED.list`, `install.sh`, `install.ps1`,
  `tests/fixtures/sync-reference/**`, `tests/skills/test-aai-sync-node.sh`,
  `tests/skills/lib/aai-sync.test.mjs`, `tests/skills/lib/aai-sync-fixtures.mjs`,
  `tests/skills/lib/resolve-base.test.mjs`, `tests/skills/lib/sync-reference.mjs`,
  `tests/skills/lib/git-env-scrub.sh`, `tests/skills/aai-sync.Tests.ps1`, and
  every other `tests/skills/lib/*` file the suite sources or reads. New row
  `aai-sync-docs` with `CHANGELOG.md`, `README.md`, `docs/USER_GUIDE.md`,
  `docs/product/sync-on-node.md`, `docs/analysis/node-first-remaining-plan.md`,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-sync-docs.sh` and the suites it runs by selector.
  Every existing row that lists `.aai/scripts/aai-sync.sh` or `.ps1` (the 14
  measured) gains `.aai/scripts/aai-sync.mjs`; every row that lists
  `lib/gitignore-block.sh` lists `lib/gitignore-block.mjs` instead; the rows
  of the suites of the three switched modules gain
  `.aai/scripts/lib/resolve-base.mjs`; hygiene TEST-815 keeps passing.
- Shared-lib note: the two new libs sit under the `.aai/scripts/lib/**`
  shared-lib glob, so a change to either is a FULL_RUN; TEST-4019 checks that
  escalation and the routing to `aai-sync-node` for every other listed file.
- `tests/skills/suite-weights.tsv`: the fallback lines
  `# sample aai-sync-node fallback unsampled (new suite of sync-on-node; no successful observation)`
  with `aai-sync-node<TAB>196`, and the same for `aai-sync-docs` (`split from
  aai-sync-node by sync-on-node`).
- `test-aai-hygiene-pack.sh` test_090: the row-count pin moves 142 to 144 (a
  parallel ride that adds a suite moves it again; the branch merging second
  rebases the pin); test_129 passes; test_128's pipefail floor (at least 3)
  still holds with three shipping scripts.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded with `node
  .aai/scripts/check-cd-subshell-leak.mjs --record`; `.aai/scripts/aai-sync.sh`
  becomes 1 (the launcher's one `$(CDPATH= cd ...)`), the new suites hold no
  `cd` inside a command substitution.
- Nested-suite lint: no new allowlist row (other suites only in selector
  form). `check-test-registration.mjs` and `check-vendored-script-deps.mjs`
  exit 0.
- `.aai/system/PROFILES.yaml` core: `.aai/scripts/aai-sync.mjs`,
  `.aai/scripts/lib/resolve-base.mjs` and `.aai/scripts/lib/gitignore-block.mjs`
  added, `.aai/scripts/lib/gitignore-block.sh` removed (run 6 for the sync
  files, run 2 for `resolve-base.mjs`; the companion obligation for a new
  `.aai/**` file); layer-profiles TEST-001 passes. `.aai/system/RUNTIME_IGNORE.list`:
  its header comment names the new consumers (data lines unchanged).
- `.github/workflows/ps1-quality.yml`: both `push` and `pull_request` path
  lists (identical) gain `.aai/scripts/aai-sync.mjs`,
  `.aai/scripts/lib/resolve-base.mjs`, `.aai/scripts/lib/gitignore-block.mjs`,
  `tests/fixtures/sync-reference/**` and `tests/skills/lib/sync-reference.mjs`,
  and lose `.aai/scripts/lib/gitignore-block.sh`; win-fallback test_034 and
  test_035 pass. No job or step changes; the Windows 5.1 smoke keeps running
  `& .\.aai\scripts\aai-sync.ps1 -TargetRoot $target -Profile extended`, now
  through the launcher (hosted check H3).
- Prompt corpus: no prompt changes (the prompts name `aai-sync` in prose
  only), so no prompt-diet ledger entry; TEST-4019 asserts the corpus bytes
  of `.aai/*.prompt.md` and `.aai/AGENTS.md` are unchanged against
  `077ee649`.
- Left as is, checked: `aai-update.mjs` `syncCommand` (it runs the launchers),
  `install.sh` and `install.ps1` (they run the launchers; their verification
  lists keep `.aai/scripts/aai-sync.sh` and `.ps1`), `golden-flow.mjs`,
  `aai-doctor.mjs`, `docs/TECHNOLOGY.md`, `PSScriptAnalyzerSettings.psd1`,
  `docs/ai/docs-audit.yaml` (not touched by this ride).

### D-DOCS. Documentation, product doc and release note

- CHANGELOG.md: one new heading
  `## [unreleased] — feat: the AAI layer sync runs on Node behind sh and ps1 launchers`
  whose body says that syncing the AAI layer (and so `/aai-update`,
  `install.sh` and `install.ps1`) now requires Node.js 22 or later (both
  launchers refuse without it, exit 1, change nothing), that the synced
  files are the same, and names DR-2, DR-5, DR-7, DR-11, DR-13 (with the
  manual cleanup of an old layout: the paths of the D-LEGACY table), DR-18,
  DR-20 and DR-21 in one sentence each; ends with "Re-run `/aai-update` to
  pick up the new launchers and module."
- `README.md` and `docs/USER_GUIDE.md`: the sync install blocks say both
  files are launchers of one Node module that needs Node.js 22 or later; the
  USER_GUIDE profile section names the DR-5 and DR-7 refusals in one
  sentence.
- RFC-0017 phase 5 row: one sentence after the sixteenth-slice sentence and
  before the remaining-scripts-plan sentence:
  `The seventeenth slice [moved the layer sync to Node](../issues/CHANGE-0265-sync-on-node.md): one module holds the argument, profile, copy, prune and gitignore rules behind thin aai-sync.sh and aai-sync.ps1 launchers, compared with frozen copies of both twins, and the updater, the bootstrap, the hook installer and the sync share one base-resolution library.`
  The allocator rewrites the link at merge (checks match only the suffix
  `sync-on-node.md`). The remaining-pairs inventory loses its `aai-sync` row
  (expert-fetch test_2624 counts only pairs without an `.mjs`). The phase
  status follows D-PHASE5.
- `docs/product/sync-on-node.md`: written in the ship step after LOOP
  COMPLETE (canon: product docs after the flush, so no stale product doc
  adds a validation round), with the product-doc capability sections
  (what changed for a consumer, the Node prerequisite, the refusals, the
  legacy cleanup, how to verify); TEST-4020's product-doc arm is the one row
  checked after that step.

### D-FU. Follow-ups

Closed by Implementation in run 7 with `node .aai/scripts/follow-ups.mjs
close --id <id> --resolved-by sync-on-node --source "<test file> <TEST id>
(<DR or D- id>)"`, each source naming a test id that exists in the named
file:

| Follow-up | Resolved by | Evidence |
|---|---|---|
| fu-resolvebase-dotdot-after-symlink | D-BASE | TEST-4004 |
| fu-suite-git-env-scrub-class | D-GITENV | TEST-4012 |
| fu-parity-pin-template-spacing | DR-21 | TEST-4011, K30 |
| fu-parity-ps1-timestamp-precision | DR-20, DR-21 | TEST-4011 |
| fu-parity-gitignore-block-order | DR-11 | TEST-4005, P06 |
| fu-parity-ps1-hook-exec-bit | DR-18 | TEST-4010, P08 |
| fu-parity-ps1-report-name-local-time | DR-20 | TEST-4011 |
| fu-parity-ps1-report-backticks | DR-20 | TEST-4011 |
| fu-parity-win-source-path (reopened in run 9, hosted H2 closes it) | DR-23 | H2 |
| fu-parity-win-ps1-crlf-bom | DR-11, DR-20, DR-21 | TEST-4011 |
| fu-parity-sh-report-stamp-two-reads | DR-20 | TEST-4011 |
| fu-sync-ps1-merge-lib-stderr-5-1 | DR-18 | TEST-4010 |
| fu-sync-ps1-dangling-src-symlink | DR-15 | TEST-4008, P16 |
| fu-sync-symlinked-tree-root | DR-7 | TEST-4008, K27 |

Suggested at planning, filed by Implementation with `follow-ups.mjs add --ref
sync-on-node --severity P3` (ids at most 40 characters):
`fu-bootstrap-seed-use-shared-lib` (the bootstrap keeps its own
`seedRuntimeGitignore`; switching it to `lib/gitignore-block.mjs` would also
close `fu-bootstrap-gitignore-crlf`), `fu-runner-git-env-scrub` (the
runner-level `GIT_*` scrub in `aai-run-tests.sh`), `fu-sync-aai-prefix-ignore`
(the `^\.aai/` prefix reading lets `.aai/cache/` stand for `.aai/`), and
`fu-sync-sl-skill-dangling-core` only if `fu-sync-core-profile-dangling-wrappers`
is not already the same item (Implementation checks before filing). Every
further divergence a hosted run shows gets one.

Run 7d amendment (additive with disclosure): `fu-guard-config-not-l3-protected`
is closed too (resolved by Spec-AC-23, source `tests/skills/test-aai-ceremony-levels.sh
TEST-4023`), so the closed set is fifteen ids; `fu-sync-sl-skill-dangling-core`
is not filed because `fu-sync-core-profile-dangling-wrappers` is the same item,
so three suggestions are filed (`fu-bootstrap-seed-use-shared-lib`,
`fu-runner-git-env-scrub`, `fu-sync-aai-prefix-ignore`).

### D-PHASE5. The phase 5 re-measure (the final AC)

After run 7's other work, the docs suite measures, with the plan's section 1
method (`/usr/bin/grep -cvE '^[[:space:]]*(#|$)'` under bash), every tracked
`.sh` and `.ps1` under `.aai/scripts/` (lib included) and classifies each as
`launcher` (20 lines or fewer and no policy token), `kept native` (named in
the RFC-0017 kept-native list with its reason), `deprecation launcher` or
`logic`. `docs/analysis/node-first-remaining-plan.md` gains a section `## 6.
Re-measure after ride 12 (<date>)` holding: one table row per file that is
not a `launcher` (file, code lines, class, reason or next step), the twin
duplication number (expected 0: the only remaining pair, `aai-run-tests`, is
kept native and not a twin), the parity harness and Pester status from the
PR's ps1-quality run (H1 to H3), and the open P1 and P2 follow-ups whose
ref is one of the plan's twelve roadmap refs, `install-path-parity-harness`
or starts with `node-first` (from `follow-ups.mjs list --json`). Expected on
the planning tree: `claude-hook-gate.sh` (the bash pre-filter of ride 7, 63
code lines), `aai-release.ps1` (32 lines), `lib/test-residue.sh`,
`lib/repo-tripwire.sh`, `lib/append-lock.sh` and `lib/git-bash-path.sh`
remain beside the kept-native four. RFC-0017's phase 5 status becomes `done`
only when every section-5 criterion holds on that measurement; otherwise it
stays `in progress` and its row names the section-6 list. TEST-4021 re-runs
the measurement and requires the section's rows to equal it.

Run 7e amendment (additive with disclosure): RFC-0017 had no kept-native
list for the classification to read, so it gains a `### Kept native scripts`
table (the four scripts section 5 of the plan names, each with its reason from
section 2 of the plan). The twin duplication is the smaller side of a pair
whose two files are both `logic`; the open follow-up table leaves out the owner
sign-off items `fu-amend-*` (counted by `spec-amend.mjs list`). The measurement
is TEST-4022 (not TEST-4021, which is the follow-up check). Measured result:
phase 5 stays `in progress`: six files still carry logic (`claude-hook-gate.sh`
63, `aai-release.ps1` 25, `lib/test-residue.sh` 526, `lib/repo-tripwire.sh` 158,
`lib/append-lock.sh` 50, `lib/git-bash-path.sh` 45), two P2 follow-ups of the
plan's refs are open and the hosted checks are not yet read.

Post-merge amendment (measurement, additive with disclosure): Spec-AC-19 and TEST-4019 say the prompt corpus bytes equal `077ee649`. Read against the working tree, that pin fails on every later edit of a `.aai/*.prompt.md` file or `.aai/AGENTS.md`, which is not what it guards: the claim is that this ride left the corpus unchanged. TEST-4019 now measures that on history, comparing the corpus at `077ee649` with the corpus at the merge commit `0ff18d63` (file set and bytes, via `git show`), and skips with the existing not-in-this-clone message when either commit is absent. The rows above keep their wording; read "equal `077ee649`" as that historical equality.

### D-SLICES. Runs and the fallback

- Run 1, Spec-AC-01 to 03: frozen references and their helper, the suite
  skeleton (`safe_rm_own`, `run_sync_scratch`, `run_node_tests`, `need_tool`),
  the node:test file, module shape, arguments, help, usage and the D-ROOTS
  refusals; the suite-map, weights and test_090 rows land with the suite.
- Run 2, Spec-AC-04 to 06: the shared base lib and the three switched
  modules with their re-homes and records; the gitignore lib and reconcile
  (slice a); the legacy moves dropped (slice c).
- Run 3, Spec-AC-07 to 09: profile, core copy and prune with the large-list
  test; extended copy, copy semantics and the path guard; skill trees,
  indexes, knowledge, seeds and root shims.
- Run 4, Spec-AC-10 to 12: the Copilot shim and the hooks merge; the advisory
  and the pin; the installer suites' git environment scrub.
- Run 5, Spec-AC-13 and 14: both corpora. Fallback ship point: the module
  present but unreachable (launchers unchanged, the module and its libs not
  in PROFILES except `resolve-base.mjs`, which run 2 already wired), the new
  suite running TEST-4000 to TEST-4014, no CHANGELOG entry for the sync (the
  PR body carries `no-notes: Node sync module added but not yet reachable
  from any launcher`), and Spec-AC-15 to 22 moved to the next ride's spec by
  a recorded amendment.
- Run 6, Spec-AC-15: the `.sh` launcher swap, PROFILES core, the library
  deletion, the bash-side re-homes and their records, so no suite is red
  between runs; Spec-AC-16 and 17: the `.ps1` launcher with the Pester file,
  the `.ps1`-side re-homes and records, the parity harness's third twin.
- Run 7, Spec-AC-18 to 22: the upgrade and scratch install proof, the rest of
  D-WIRE, D-DOCS (the product doc after LOOP COMPLETE), D-FU, D-PHASE5; then
  the full sweep once.

## Acceptance Criteria Mapping

- Intake AC-001 (arguments, roots, profile and refusals before any write)
  maps to Spec-AC-02, Spec-AC-03 and Spec-AC-07.
- Intake AC-002 (byte parity with both references, the large core list)
  maps to Spec-AC-05, Spec-AC-07 to Spec-AC-11, Spec-AC-13 and Spec-AC-14.
- Intake AC-003 (legacy moves dropped, deletes only in the managed set of a
  re-verified root, the pointer kept) maps to Spec-AC-06 and Spec-AC-08.
- Intake AC-004 (one shared base helper) maps to Spec-AC-04.
- Intake AC-005 (the parity third twin) maps to Spec-AC-17 and hosted check
  H2.
- Intake AC-006 (launchers, Pester, scratch install, old-to-new update) maps
  to Spec-AC-15, Spec-AC-16, Spec-AC-18 and hosted checks H1 and H3.
- Intake AC-007 (pins migrated, suites pass, follow-ups, wiring, CHANGELOG,
  product doc, phase 5 re-measure) maps to Spec-AC-12, Spec-AC-15,
  Spec-AC-16, Spec-AC-19 to Spec-AC-22; the unchanged suites in D-REHOME
  pass in the Verification sweep. Refinement, disclosed: the intake left the
  git environment follow-up conditional; Planning measured it as cheap and
  the same class and took it (D-GITENV, Spec-AC-12).
- Owner safety rules (scratch only, no daemon, delete only what the run made
  and only under the re-verified target, empty target or core list a hard
  failure, cleanup on failure, `GIT_CONFIG_*` scrubbed, every written or
  deleted path under the scratch root) map to Spec-AC-01, Spec-AC-03,
  Spec-AC-07, Spec-AC-08, Spec-AC-12 and D-SAFETY in every new test.

## Constitution deviations

None. Article 1: every rule is seen failing first and the corpora compare
real runs of both frozen twins. Article 2: one module, two launchers of at
most 20 lines, two shared libraries each used by more than one caller (the
base lib by four modules, the gitignore lib by the module and its tests), no
dependency. Article 4: without Node both launchers refuse with one named
line and change nothing; every refusal names its path and leaves the target
as it was. Article 5: syncing the layer now requires Node.js 22 or later;
this is the owner's recorded decision (plan section 4, decision 1), stated in
the CHANGELOG entry; both launchers keep their paths, the argument forms
every caller uses, the bytes of every synced file (minus the numbered DRs)
and the exit codes 0 and 1, with every usage error now exit 2; the dropped
legacy moves are named with the manual cleanup.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a test of this ride removes a scratch path the system SHALL refuse (throw or fail the test) an empty path, a relative path, a basename without the own prefix, a path outside the temp directory, a symbolic link, a directory without the .aai-sy-owned marker and an empty removal list; the three frozen copies under tests/fixtures/sync-reference SHALL hash to the D-REF sha256 values and, where git history holds 077ee649, equal the files at that commit; the new test files SHALL hold no docker, pkill or killall call, every sync invocation in them SHALL go through the D-SAFETY helpers, which remove every GIT_ variable except GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL and assert the target under the run's own scratch root and not under this checkout, and the suite SHALL leave no own scratch root after a forced failing copy of itself. | done | TEST-4000 red docs/ai/tdd/sync-on-node/red/TEST-4000.log; TEST-4000 green docs/ai/tdd/sync-on-node/green/TEST-4000.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4000.txt | — | D-SAFETY, D-REF |
| Spec-AC-02 | .aai/scripts/aai-sync.mjs SHALL import only node: specifiers and the three named libs and none of http, https, net, tls or dgram, create no file and print nothing when imported, export the D-MODULE names, hold each D-MODULE anchor line exactly once, call spawnSync exactly once (inside runChild), never reference process.stdout or process.stderr, and be ASCII only. | done | TEST-4001 red docs/ai/tdd/sync-on-node/red/TEST-4001.log; TEST-4001 green docs/ai/tdd/sync-on-node/green/TEST-4001.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4001.txt | — | D-MODULE |
| Spec-AC-03 | WHEN the module is run with arguments the system SHALL follow D-CLI and D-ROOTS: the bash forms and the exact PowerShell names in any case, help per DR-1 on stdout with exit 0, each DR-2 usage case with one stderr line, the usage line and exit 2 and nothing written, a missing target directory with the bash line and exit 1, and a target equal to or inside the source, a file system root, a missing source .aai, a missing manifest and an empty core list each refused with exit 1 before any file in the target or the source changes. | done | TEST-4002 red docs/ai/tdd/sync-on-node/red/TEST-4002.log; TEST-4002 green docs/ai/tdd/sync-on-node/green/TEST-4002.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4002.txt; TEST-4003 red docs/ai/tdd/sync-on-node/red/TEST-4003.log; TEST-4003 green docs/ai/tdd/sync-on-node/green/TEST-4003.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4003.txt | — | D-CLI, D-ROOTS, DR-1 to DR-6, DR-25 |
| Spec-AC-04 | WHEN resolveBase or resolveFromBase of .aai/scripts/lib/resolve-base.mjs runs the system SHALL return PWD resolved only when that resolved path names the same device and inode as the working directory, so a PWD holding .. after a symbolic link, a stale PWD, a relative PWD and an absent PWD each give the working directory; aai-update.mjs resolveBase, aai-bootstrap.mjs resolveRoot, install-pre-commit-hook.mjs resolveBase and the sync module SHALL give the same answers through the lib and hold no PWD identity comparison of their own, and their existing tests (TEST-3962, TEST-3941, TEST-3961, TEST-3981) SHALL pass with the D-REHOME run 2 records present. | done | TEST-4004 red docs/ai/tdd/sync-on-node/red/TEST-4004.log; TEST-4004 green docs/ai/tdd/sync-on-node/green/TEST-4004.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4004.txt | — | D-BASE |
| Spec-AC-05 | WHEN the reconcile runs the system SHALL write the managed .gitignore blocks, the runtime-sidecar seed and the self-heal in the bash order and bytes for an absent, LF, CRLF, duplicated, prefix-only, 200 KB and legacy-marker .gitignore and for a list in the source, only in the target and nowhere, leave a second run byte-identical, never re-append a managed line present at the top of a large file, print the DR-14 pointer when it appends the runtime-state block, and hold no child process or shell. | done | TEST-4005 red docs/ai/tdd/sync-on-node/red/TEST-4005.log; TEST-4005 green docs/ai/tdd/sync-on-node/green/TEST-4005.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4005.txt | — | D-GITIGNORE, DR-11, DR-12, DR-14 |
| Spec-AC-06 | WHEN the target holds the legacy layout of D-LEGACY the system SHALL leave every one of those paths byte-identical, print no MIGRATE or Legacy line and delete nothing outside the managed set, and the module source SHALL hold none of the dropped paths. | done | TEST-4006 red docs/ai/tdd/sync-on-node/red/TEST-4006.log; TEST-4006 green docs/ai/tdd/sync-on-node/green/TEST-4006.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4006.txt | — | D-LEGACY, DR-13 |
| Spec-AC-07 | WHEN the core profile is synced the system SHALL resolve the profile per DR-9 and the core list per DR-10, copy each listed source file, warn for each listed file missing in the source, prune every other regular file and link under the target .aai except .aai/cache and target-only .aai/scripts entries, record each prune in the advisory, remove emptied directories but never .aai or .aai/cache, and with a core list of 20,000 extra entries prune no core-listed file on either of two runs. | done | TEST-4007 red docs/ai/tdd/sync-on-node/red/TEST-4007.log; TEST-4007 green docs/ai/tdd/sync-on-node/green/TEST-4007.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4007.txt | — | D-PROFILE, DR-9, DR-10 |
| Spec-AC-08 | WHEN the extended profile is synced or any write or delete is made the system SHALL copy-replace per D-COPY with modes, timestamps and links kept and a dangling source link copied as a link, clean stale top-level .aai entries and preserve target-only scripts, call underRoot before every mutation, refuse the whole run before any write when a managed path is a link leaving the target (DR-7), exit 1 when a mutation path or the re-read target identity fails the check (DR-8), and never delete a temp file it did not create. | done | TEST-4008 red docs/ai/tdd/sync-on-node/red/TEST-4008.log; TEST-4008 green docs/ai/tdd/sync-on-node/green/TEST-4008.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4008.txt | — | D-COPY, DR-7, DR-8, DR-15 |
| Spec-AC-09 | WHEN the skill trees, indexes, knowledge files, seeds and root shims are synced the system SHALL copy-replace each source entry with the twins' conflict texts for a differing SKILL.md or directory, remove exactly the provably retired wrappers per the byte-level predicate and keep every near-miss, project-owned and linked entry, copy knowledge files per the case-sensitive sentinel, seed the three templates only when absent, and copy the root shims and README_AAI.md with their conflict texts. | done | TEST-4009 red docs/ai/tdd/sync-on-node/red/TEST-4009.log; TEST-4009 green docs/ai/tdd/sync-on-node/green/TEST-4009.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4009.txt | — | D-SURFACES, DR-16 |
| Spec-AC-10 | WHEN the Copilot shim and the hooks are synced the system SHALL replace an absent, identical or listed-shipped shim and merge a project-overrides block or override file in the bash bytes, hash through node:crypto, copy every hook entry including dotfiles, merge hooks.json and hooks.windows.json in process with the MERGE, LEFT-AS-IS and SNAPSHOT-NOT-RECORDED lines and advisory entries of the bash twin, refuse a malformed registration leaving it untouched, and make hooks/session-start.sh executable. | done | TEST-4010 red docs/ai/tdd/sync-on-node/red/TEST-4010.log; TEST-4010 green docs/ai/tdd/sync-on-node/green/TEST-4010.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4010.txt | — | D-SURFACES, D-HOOKS, DR-17 to DR-19 |
| Spec-AC-11 | WHEN a sync ends the system SHALL write the advisory only when a conflict or deletion was recorded, name it and stamp it from one UTC clock read to the second, write the pin with one space after Template version, the version, tag fallback, commit, canonical URL and profile per D-REPORT, run its git children with the DR-22 variables removed, write LF without a BOM, and print the bash closing lines. | done | TEST-4011 red docs/ai/tdd/sync-on-node/red/TEST-4011.log; TEST-4011 green docs/ai/tdd/sync-on-node/green/TEST-4011.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4011.txt | — | D-REPORT, DR-20 to DR-24 |
| Spec-AC-12 | WHEN the recorded repro docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh and the D-GITENV injections against hygiene test_618, the doctor suite and the pre-commit-checks suite run the system SHALL exit 0 with the victim directory empty, and the installer invocation helpers of those four suites SHALL go through aai_git_scrubbed with aai_assert_hooks_under. | done | TEST-4012 red docs/ai/tdd/sync-on-node/red/TEST-4012.log; TEST-4012 green docs/ai/tdd/sync-on-node/green/TEST-4012.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4012.txt | — | D-GITENV |
| Spec-AC-13 | WHEN the D-CORPUS bash-side cases run the system SHALL give exit code, stdout, stderr, the target snapshot, the unchanged source snapshot and the TMPDIR listing byte-equal between the frozen bash reference and the module after only the registered normalization and rewrites, each registered rewrite changing at least one byte, and the asserted divergences SHALL hold. | done | TEST-4013 red docs/ai/tdd/sync-on-node/red/TEST-4013.log; TEST-4013 green docs/ai/tdd/sync-on-node/green/TEST-4013.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4013.txt | — | D-CORPUS bash side, DR-26 to DR-30 |
| Spec-AC-14 | WHEN the D-CORPUS PowerShell-side cases run with pwsh the system SHALL give exit code and the target snapshot equal between the frozen PowerShell reference and the module on the same PowerShell-form arguments, and the asserted divergences SHALL hold. | done | TEST-4014 red docs/ai/tdd/sync-on-node/red/TEST-4014.log; TEST-4014 green docs/ai/tdd/sync-on-node/green/TEST-4014.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4014.txt | — | D-CORPUS PowerShell side, DR-26 and DR-27 |
| Spec-AC-15 | .aai/scripts/aai-sync.sh SHALL be the D-LAUNCH text (at most 20 lines, ASCII, mode 100755, no policy token) and WHEN run by bash, sh and dash beside a stub module it SHALL pass every argument and the exit code through, and without node or the module exit 1 with the D-LAUNCH line on stderr leaving the target unchanged; .aai/scripts/lib/gitignore-block.sh SHALL be absent, PROFILES core SHALL list the module and both libs, check-vendored-script-deps SHALL exit 0, the bash-side D-REHOME selectors SHALL each exit 0, and spec-amend list SHALL hold the run 6a records. | done | TEST-4015 red docs/ai/tdd/sync-on-node/red/TEST-4015.log; TEST-4015 green docs/ai/tdd/sync-on-node/green/TEST-4015.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4015.txt | — | D-LAUNCH, D-REHOME run 6a |
| Spec-AC-16 | .aai/scripts/aai-sync.ps1 SHALL be the D-LAUNCH text (at most 20 lines, ASCII, no param block, no policy token); tests/skills/aai-sync.Tests.ps1 run with Invoke-Pester under pwsh 7 SHALL pass the five D-PESTER cases with 0 skipped, 0 failed and 0 failed containers; the PowerShell-side D-REHOME selectors SHALL each exit 0 with no assertion reading the .ps1's text. | done | TEST-4016 red docs/ai/tdd/sync-on-node/red/TEST-4016.log; TEST-4016 green docs/ai/tdd/sync-on-node/green/TEST-4016.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4016.txt | — | D-PESTER, D-REHOME run 6b; H1 for 5.1 and 7 on Windows |
| Spec-AC-17 | WHEN the parity driver runs the seven SY scenarios with twins sh, ps1 and node against the committed allowlist the system SHALL exit 0 with verdict PASS, pairs sh:ps1, sh:node and ps1:node in each sync scenario, the sh and ps1 twins running the frozen references from syref, and only the D-PARITY allowlist changes; a fake node twin that writes one more byte into the pin SHALL fail naming sh:node; the real-registry unit test and aai-bootstrap.test.mjs TEST-3956 SHALL pass and spec-amend list SHALL hold the SPEC-0284 and SPEC-0306 records. | done | TEST-4017 red docs/ai/tdd/sync-on-node/red/TEST-4017.log; TEST-4017 green docs/ai/tdd/sync-on-node/green/TEST-4017.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4017.txt | — | D-PARITY; H2 on Windows |
| Spec-AC-18 | WHEN the D-UPGRADE cases U0 to U4 run in scratch trees the system SHALL exit 0 for each install and update, vendor the module, both launchers and both libs into every updated target with no lib/gitignore-block.sh left in an extended target (a core target keeps it as the preserved target-only script it was under both twins), keep a core target's profile and prune exactly the .aai files the new core list lacks, run the updated target's sync, update, hook installer and bootstrap launchers with exit 0, leave the frozen twin as aai-sync.sh only in the U2 target until its next update, and exit 1 with the D-LAUNCH line and an unchanged target when node is not on PATH. | done | TEST-4018 red docs/ai/tdd/sync-on-node/red/TEST-4018.log; TEST-4018 green docs/ai/tdd/sync-on-node/green/TEST-4018.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4018.txt | — | D-UPGRADE, run 7a amendment |
| Spec-AC-19 | Wiring per D-WIRE: select-suites SHALL route the module, both launchers, both libs, the three reference copies, the node:test files, the Pester file and git-env-scrub.sh to aai-sync-node, every row listing aai-sync.sh SHALL list aai-sync.mjs and no row SHALL list gitignore-block.sh; both weights rows SHALL be 196 with their fallback lines; hygiene test_090 SHALL pin 144 and test_129 and test_128 pass; the cd-subshell baseline SHALL hold 1 for aai-sync.sh; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps SHALL exit 0; both ps1-quality path lists SHALL be identical and hold the D-WIRE entries with win-fallback test_034 and test_035 passing; the prompt corpus bytes SHALL equal 077ee649. | done | TEST-4019 red docs/ai/tdd/sync-on-node/red/TEST-4019.log; TEST-4019 green docs/ai/tdd/sync-on-node/green/TEST-4019.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4019.txt | — | D-WIRE |
| Spec-AC-20 | CHANGELOG.md SHALL hold the D-DOCS heading exactly once with a body naming Node.js 22, DR-2, DR-5, DR-7, DR-11, DR-13, DR-18, DR-20 and DR-21 and every D-LEGACY path; README.md and docs/USER_GUIDE.md SHALL name aai-sync.mjs and Node.js 22 in the sync install blocks; the RFC-0017 phase 5 row SHALL hold the D-DOCS sentence once with a link ending sync-on-node.md and no aai-sync inventory row, and expert-fetch test_2624 SHALL pass; after LOOP COMPLETE docs/product/sync-on-node.md SHALL exist and pass the product-doc check. | done | TEST-4020 red docs/ai/tdd/sync-on-node/red/TEST-4020.log; TEST-4020 green docs/ai/tdd/sync-on-node/green/TEST-4020.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4020.txt; product doc docs/product/sync-on-node.md written after LOOP COMPLETE (TEST-4020 product-doc arm passes) | — | D-DOCS; the product-doc arm is written after LOOP COMPLETE |
| Spec-AC-21 | follow-ups list --status all SHALL show each of the thirteen D-FU follow-ups that stay closed (run 9 reopened fu-parity-win-source-path, which SHALL show open) and fu-guard-config-not-l3-protected closed with resolved_by sync-on-node and a source naming a test file and a TEST id that occurs in that file followed by a colon, and the three filed suggestions SHALL be listed open with ref sync-on-node. | done | TEST-4021 red docs/ai/tdd/sync-on-node/red/TEST-4021.log; TEST-4021 green docs/ai/tdd/sync-on-node/green/TEST-4021.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4021.txt | — | D-FU, run 7d amendment |
| Spec-AC-22 | WHEN the D-PHASE5 measurement runs the system SHALL find the rows of section 6 of docs/analysis/node-first-remaining-plan.md equal to the measured non-launcher files with their code lines and classes, the twin duplication number 0, the listed open P1 and P2 node-first follow-ups equal to the ledger's, and the RFC-0017 phase 5 status done only when every plan section 5 criterion holds on that measurement. | done | TEST-4022 red docs/ai/tdd/sync-on-node/red/TEST-4022.log; TEST-4022 green docs/ai/tdd/sync-on-node/green/TEST-4022.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4022.txt | — | D-PHASE5; phase 5 stays in progress |
| Spec-AC-23 | Owner-authorised scope addition, relayed 2026-11-22 after PR 580 (additive, disclosed): .aai/scripts/lib/guard-config.mjs SHALL be listed on both protected_paths_l3 lists (docs/ai/docs-audit.yaml and .aai/templates/docs-audit.template.yaml), WORKFLOW.md protected surfaces SHALL carry a guard config bullet naming it, and select-suites SHALL report a change to it as FULL_RUN reason=protected-l3, the same shape PR 580 (SPEC-0309) gave the hook installer. | done | TEST-4023 red docs/ai/tdd/sync-on-node/red/TEST-4023.log; TEST-4023 green docs/ai/tdd/sync-on-node/green/TEST-4023.log, mutation docs/ai/tdd/spec-sync-on-node/mutation-TEST-4023.txt | — | owner scope addition |

## Implementation plan

TDD in seven runs (D-SLICES); each run stores RED under
`docs/ai/tdd/sync-on-node/red/` before its change and GREEN under `green/`,
and one mutation record per row (`node .aai/scripts/mutation-run.mjs`,
records under `docs/ai/tdd/spec-sync-on-node/`) before the run's hand-off.
New files: the module, `.aai/scripts/lib/resolve-base.mjs`,
`.aai/scripts/lib/gitignore-block.mjs`, the three reference copies,
`tests/skills/lib/sync-reference.mjs`, `tests/skills/lib/aai-sync.test.mjs`
(optionally `tests/skills/lib/aai-sync-fixtures.mjs`),
`tests/skills/lib/resolve-base.test.mjs`, `tests/skills/lib/git-env-scrub.sh`,
`tests/skills/test-aai-sync-node.sh`, `tests/skills/test-aai-sync-docs.sh`
(its own small suite, so the sync suite is not a release dry-run CHANGELOG
reader, as ride 10 learned), `tests/skills/aai-sync.Tests.ps1`. Deleted:
`.aai/scripts/lib/gitignore-block.sh`. New files are staged (`git add`)
before any suite that copies `git ls-files` runs (the parity harness and
`copy_tracked`; D-PARITY also copies them when untracked).

Seams this change shares with features it does not own, each crossed by a
test that produces on one side and asserts on the other:

- The materialized source and the updater: `aai-update.mjs` and the frozen
  updaters run the source's sync file; TEST-4018 U1, U3 and U4 run the real
  updaters against scratch sources and read the target.
- PROFILES core and the prune: the list is owned by layer-profiles
  (SPEC-0035), read by the module's prune; TEST-4007 prunes with a padded
  list, layer-profiles TEST-001 classifies the new files, TEST-4018 U1
  compares the prune set with the new list.
- The shared base lib and its four users: TEST-4004 runs each user's export
  on the same symlinked fixtures.
- The hook-registration merge library (SPEC-0199): written by the source,
  merged by the module in process; TEST-4010 and K16 compare with the bash
  twin's CLI run; sync-seed TEST-773 to TEST-793 keep running.
- The `.gitignore` the bootstrap also writes: TEST-4005 seeds after a
  bootstrap marker (K09f) and sync-seed TEST-010 keeps one marker on both.
- The pin and its readers (`layer-drift.mjs`, `aai-doctor.mjs` CAT-13,
  `aai-update.mjs` evidence): layer-drift TEST-010 and layer-profiles
  TEST-006 read a pin the module wrote.
- The parity driver's twin registry and the frozen references on native
  Windows: TEST-4017 and hosted check H2.
- The ps1 launcher's argument marshalling between PowerShell's binder and
  the module's parser: TEST-4016 (in session and under `-File`) and H1.
- The test vendoring helpers and every suite that uses them:
  `check-vendored-script-deps.mjs` and one vendored run per suite in
  TEST-4004 and TEST-4015.
- A residual seam no automated test crosses: a downstream project still on
  the 2026-03 legacy layout keeps its stale files (DR-13; disclosed with the
  manual cleanup in the CHANGELOG), and a consumer whose `.aai` is a
  symbolic link out of the project is now refused (DR-7; disclosed).

Edge cases: a target path with a space and `[ ]` (K28, Pester 5); a
symlinked working directory, a stale `PWD` and `..` after a link; a
relative target; a CRLF pin and `.gitignore`; a `.gitignore` without a final
newline; a 200 KB `.gitignore`; a core list larger than a pipe buffer; a
dangling source link; a link at a managed root; a retired wrapper with a BOM,
U+200B or NFD bytes; a malformed `hooks.json`; no `AAI_VERSION.md`; a source
without git; `GIT_DIR` exported by a caller; PowerShell callers in session
with `-Name:value`; Windows paths (H2, H3).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4000 | Spec-AC-01 | unit | tests/skills/test-aai-sync-node.sh | test_4000_scratch_safety runs run_node_tests TEST-4000 (removeOwnScratch refuses each D-SAFETY case and removes a marked own directory; the three reference copies hash to their pins and equal git show 077ee649 when that object exists; materializeSyncReference writes them and removes the module-side engine files), checks safe_rm_own refuses an empty, relative, foreign, symlinked and unmarked path and an empty list, scans the new test files for docker, pkill and killall and for any sync invocation outside the D-SAFETY helpers, checks the helpers drop every GIT_ variable and assert the target under the own scratch root, and runs a forced failing copy of the suite requiring no own scratch root left | `sed:s/const OWN_SCRATCH_PREFIX = 'aai-sy-';/const OWN_SCRATCH_PREFIX = '';/` on tests/skills/lib/sync-reference.mjs | green |
| TEST-4001 | Spec-AC-02 | inspection | tests/skills/test-aai-sync-node.sh | test_4001_module_shape runs run_node_tests TEST-4001: import in a scratch cwd creates nothing and prints nothing; the export list; only node: imports plus the three libs and none of the network modules; each anchor once; one spawnSync call; no process.stdout or process.stderr; ASCII only | `sed:s/const writeFd = \(fd\) => \(s\) => \{ fs.writeSync\(fd, s\); \};/const writeFd = (fd) => (s) => { process.stdout.write(s); };/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4002 | Spec-AC-03 | unit | tests/skills/test-aai-sync-node.sh | test_4002_cli runs run_node_tests TEST-4002: every accepted form in mixed order and case, -- before a dash-named target, help equal to lines 4 to 20 of the reference after the sed transform plus the two DR-1 lines, each DR-2 case with its exact stderr line, the usage line and exit 2 and no spawn recorded, a missing target directory with the bash line and exit 1, -T and -Verbose refused | `sed:s/const EXIT_USAGE = 2;/const EXIT_USAGE = 0;/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4003 | Spec-AC-03 | unit | tests/skills/test-aai-sync-node.sh | test_4003_root_refusals runs run_node_tests TEST-4003 in scratch trees: the target equal to the source, inside it and at a link to it, a file system root, a source without .aai, a missing manifest and an empty core list each exit 1 with the D-ROOTS line, and the snapshots of target and source are byte-identical afterwards; a source inside the target is allowed | `sed:s/ancestorIsFile\(roots.targetReal, statOrNull\(roots.srcReal\)\)\].some\(Boolean\)/ancestorIsFile(roots.targetReal, statOrNull(roots.srcReal))].some(() => false)/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4004 | Spec-AC-04 | unit | tests/skills/test-aai-sync-node.sh | test_4004_shared_base runs node --test tests/skills/lib/resolve-base.test.mjs (matching PWD, PWD with .. after a link, stale, relative, absent, trailing slash, rel resolution) and the same fixtures through aai-update.mjs resolveBase, aai-bootstrap.mjs resolveRoot, install-pre-commit-hook.mjs resolveBase and the sync module; scans the four modules for a PWD identity comparison of their own; runs the TEST-3962, TEST-3961, TEST-3941 and TEST-3981 selectors and check-vendored-script-deps (exit 0) and reads spec-amend list --json for the three run 2 records | `sed:s/    const a = statOrNull\(resolved\);/    const a = statOrNull(pwd);/` on .aai/scripts/lib/resolve-base.mjs | green |
| TEST-4005 | Spec-AC-05 | unit | tests/skills/test-aai-sync-node.sh | test_4005_gitignore runs run_node_tests TEST-4005: reconcileGitignore on the K09 inputs compared with the frozen bash reference's .gitignore bytes for the same targets, a second run byte-identical, the 200 KB file with the managed lines at the top unchanged on a second run, the DR-14 pointer, the missing-list note, and the lib source holding no child_process import | `sed:s/export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecars';/export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecarsX';/` on .aai/scripts/lib/gitignore-block.mjs | green |
| TEST-4006 | Spec-AC-06 | unit | tests/skills/test-aai-sync-node.sh | test_4006_legacy_dropped runs run_node_tests TEST-4006: a K17 legacy-layout target synced by the module keeps every legacy path byte-identical, stdout holds no MIGRATE or Legacy line, the snapshot outside the managed set is unchanged, and the module source holds none of the D-LEGACY paths | `sed:s/  const roots = resolveRoots\(args, io\);/  const roots = resolveRoots(args, io); if (roots.target) fs.rmSync(path.join(roots.target, 'PLAYBOOK.md'), { force: true });/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4007 | Spec-AC-07 | integration | tests/skills/test-aai-sync-node.sh | test_4007_core_prune runs run_node_tests TEST-4007 in scratch trees: the DR-9 and DR-10 readings on crafted pins and manifests, the K03, K04 and K05 flows (copy, WARN, prune, preserve, cache kept, emptied directories removed, advisory Deleted items), and two core syncs with 20,000 extra list entries leaving every core-listed file present | `sed:s/const isCoreListed = \(coreSet, rel\) => coreSet.has\(rel\);/const isCoreListed = (coreSet, rel) => coreSet.has(rel) && coreSet.size < 1000;/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4008 | Spec-AC-08 | unit | tests/skills/test-aai-sync-node.sh | test_4008_copy_and_guard runs run_node_tests TEST-4008: copyReplace keeps modes, timestamps and links and copies a dangling link as a link; the K08 extended flow; a link at each managed root leaving the target refuses the whole run with the snapshot unchanged; an injected path outside the target and a target whose identity changes before the prune exit 1 with the DR-8 line; an EEXIST temp is left in place; DR-31: a link at the snapshot path or at a merge temp name is replaced and a file outside the target stays untouched | `sed:s/  if \(!underRoot\(roots, abs\)\) return refuseOutside\(roots, abs\);/  if (false) return refuseOutside(roots, abs);/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4009 | Spec-AC-09 | unit | tests/skills/test-aai-sync-node.sh | test_4009_surfaces runs run_node_tests TEST-4009: the K10 to K14 flows compared with the bash reference, isRetiredSkillWrapper on the shipped wrapper shape and on near-miss inputs (one changed byte, a BOM, U+200B, NFD, a second file, a link, 65537 bytes, a NUL, an aai-project- name), and the case-sensitive sentinel | `sed:s/const ROOT_SHIMS = \['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md'\];/const ROOT_SHIMS = ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md'];/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4010 | Spec-AC-10 | unit | tests/skills/test-aai-sync-node.sh | test_4010_copilot_and_hooks runs run_node_tests TEST-4010: the K15 and K16 flows compared with the bash reference, copilotShimIsShipped on listed, unlisted, empty and CRLF texts, the in-process merge lines equal to the library CLI's output on the same files, a malformed registration untouched, session-start.sh executable | `sed:s/import \{ mergeHooksJson, formatSummary, formatConflicts, formatSnapshotError \} from '.\/lib\/merge-hooks-json.mjs';/import { mergeHooksJson, formatSummary, formatSnapshotError } from '.\/lib\/merge-hooks-json.mjs'; const formatConflicts = () => [];/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4011 | Spec-AC-11 | unit | tests/skills/test-aai-sync-node.sh | test_4011_report_and_pin runs run_node_tests TEST-4011: renderAdvisory and renderPin with an injected clock and spawn (name and stamps from one read, the bash text, LF, one space after Template version, the tag fallback and UNKNOWN), a run with GIT_DIR exported pointing at another scratch repository stamping the source's commit, no advisory on a quiet run, the closing lines, and native paths with platform win32 | `sed:s/const PIN_VERSION_PREFIX = '- Template version: ';/const PIN_VERSION_PREFIX = '- Template version:  ';/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4012 | Spec-AC-12 | integration | tests/skills/test-aai-sync-node.sh | test_4012_git_env_scrub runs the recorded repro (exit 0), then injects core.hooksPath through GIT_CONFIG_COUNT, KEY_0 and VALUE_0 and through GIT_CONFIG_PARAMETERS into one selector each of test-aai-hygiene-pack.sh test_618, test-aai-doctor.sh and test-aai-pre-commit-checks.sh with a scratch victim directory and requires it empty, and scans the four suites' installer helpers for aai_git_scrubbed and aai_assert_hooks_under | `sed:s/  \(cd "\$d" && aai_git_scrubbed node "\$INSTALLER_MJS" "\$@"\)/  (cd "$d" && node "$INSTALLER_MJS" "$@")/` on tests/skills/test-aai-git-ref-guard.sh | green |
| TEST-4013 | Spec-AC-13 | integration | tests/skills/test-aai-sync-node.sh | test_4013_corpus_bash needs bash and git and runs run_node_tests TEST-4013: every bash-side D-CORPUS case with the normalization and registered rewrites, the asserted divergences, a failure for a registered rewrite that changes nothing, and KR1 and KR2 on a committed scratch copy of this checkout | `sed:s/Sync complete. Review changes in/Sync complete; review changes in/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4014 | Spec-AC-14 | integration | tests/skills/test-aai-sync-node.sh | test_4014_corpus_powershell needs pwsh (need_tool) and runs run_node_tests TEST-4014: every PowerShell-side D-CORPUS case against the frozen PowerShell reference with the module on the same PowerShell-form arguments, comparing exit and the target snapshot, with the asserted divergences | `sed:s/const PS_NAMES = \{ '-targetroot': 'target', '-profile': '--profile' \};/const PS_NAMES = { '-profile': '--profile' };/` on .aai/scripts/aai-sync.mjs | green |
| TEST-4015 | Spec-AC-15 | integration | tests/skills/test-aai-sync-node.sh | test_4015_sh_launcher checks the launcher text (at most 20 lines, ASCII, mode 100755, no policy token outside the comment lines), runs a copy beside a stub module under bash, sh and dash (need_tool) with both argument forms and -h requiring the argv and exit 7 through, then with PATH holding only dirname and with the module removed requires exit 1, the exact refusal line and an unchanged target; requires lib/gitignore-block.sh absent and PROFILES core to list the module and both libs, runs check-vendored-script-deps (exit 0) and the bash-side D-REHOME selectors (each exit 0), and reads spec-amend list --json for the run 6a records | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE"/` on .aai/scripts/aai-sync.sh | green |
| TEST-4016 | Spec-AC-16 | integration | tests/skills/test-aai-sync-node.sh | test_4016_ps1_launcher checks the .ps1 text (at most 20 lines, ASCII, no param block, no policy token outside the comment lines), then needs pwsh and Pester 5 and runs Invoke-Pester on tests/skills/aai-sync.Tests.ps1 under env -u AAI_ROLE requiring 5 passed, 0 skipped, 0 failed and 0 failed containers, and runs the PowerShell-side D-REHOME selectors (each exit 0, no grep, awk or sed over the .ps1 left in them) | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/aai-sync.ps1 | green |
| TEST-4017 | Spec-AC-17 | integration | tests/skills/test-aai-sync-node.sh | test_4017_parity_sync needs pwsh, runs the driver with the seven SY scenarios and twins sh,ps1,node into a scratch report and requires exit 0, verdict PASS, the three pairs per sync scenario, the sh and ps1 argv naming syref; runs run_node_tests TEST-4017 in install-parity.test.mjs (a fake node twin writing one more byte into the pin fails naming sh:node; the real-registry argv test; the widened rows and the one new row) and aai-bootstrap.test.mjs TEST-3956; requires the SPEC-0284 and SPEC-0306 records | `sed:s/ops: \['bootstrap', 'update', 'hooks', 'sync'\]/ops: ['bootstrap', 'update', 'hooks']/` on tests/skills/lib/install-parity.mjs | green |
| TEST-4018 | Spec-AC-18 | integration | tests/skills/test-aai-sync-node.sh | test_4018_upgrade runs the D-UPGRADE cases U0 to U4 in scratch trees (U4 through need_tool pwsh), each install and update exit 0, the vendored file sets, the kept profile, the prune set equal to the old core files the new list lacks, the updated targets' launchers run with exit 0, the U2 frozen twin replaced by the next update, and the no-node refusal with an unchanged target | `sed:s/  - .aai\/scripts\/lib\/resolve-base.mjs\n//` on .aai/system/PROFILES.yaml | green |
| TEST-4019 | Spec-AC-19 | inspection | tests/skills/test-aai-sync-node.sh | test_4019_wiring pipes the module, both launchers, both libs, the three reference copies, the node:test files, the Pester file and git-env-scrub.sh to select-suites.mjs --files-from - and requires aai-sync-node each time (FULL_RUN for the two libs); requires every suite-map row naming aai-sync.sh to name aai-sync.mjs and no row naming gitignore-block.sh; both weights rows 196 with their fallback lines; runs hygiene-pack test_090, test_128 and test_129 and win-fallback test_034 and test_035 selectors; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the baseline row 1 for aai-sync.sh, identical ps1-quality path lists holding the D-WIRE entries, and the prompt corpus bytes equal to 077ee649 | `sed:s/  aai-sync-node:/  aai-sync-node-gone:/` on tests/skills/suite-map.yaml | green |
| TEST-4020 | Spec-AC-20 | inspection | tests/skills/test-aai-sync-docs.sh | test_4020_docs requires the CHANGELOG heading once with Node.js 22, the eight named DRs and every D-LEGACY path in its body, README.md and the USER_GUIDE sync blocks naming aai-sync.mjs and Node.js 22, the RFC-0017 phase 5 row holding the D-DOCS sentence once with a link ending sync-on-node.md and no aai-sync inventory row, runs expert-fetch test_2624_inventory_matches_tree (exit 0), and after LOOP COMPLETE requires docs/product/sync-on-node.md to pass the product-doc check | `sed:s/The seventeenth slice \[moved the layer sync to Node\]/The seventeenth slice [moved sync]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-4021 | Spec-AC-21 | inspection | tests/skills/test-aai-sync-docs.sh | test_4021_follow_ups reads follow-ups list --status all --json and requires each of the thirteen remaining D-FU ids and fu-guard-config-not-l3-protected closed with resolved_by sync-on-node and a source whose test file exists and contains the cited TEST id followed by a colon, and the suggested ids open with ref sync-on-node | `sed:s/TEST-4004:/TEST-4004X:/g` on tests/skills/lib/resolve-base.test.mjs | green |
| TEST-4022 | Spec-AC-22 | inspection | tests/skills/test-aai-sync-docs.sh | test_4022_phase5_remeasure measures every tracked .sh and .ps1 under .aai/scripts with the plan's section 1 method, classifies each, and requires section 6 of the plan to list exactly the non-launcher files with their code lines and classes, the twin duplication 0, the open P1 and P2 node-first follow-ups equal to the ledger's, and the RFC-0017 phase 5 status done only when every section 5 criterion holds | `sed:s/claude-hook-gate.sh/claude-hook-gateX.sh/g` on docs/analysis/node-first-remaining-plan.md | green |
| TEST-4023 | Spec-AC-23 | inspection | tests/skills/test-aai-ceremony-levels.sh | test_4023_guard_config_is_l3_protected requires .aai/scripts/lib/guard-config.mjs on the live (loadConfig) and the seed protected_paths_l3 lists, a guard config bullet naming it in WORKFLOW.md, and select-suites --files-from - printing FULL_RUN reason=protected-l3 path=.aai/scripts/lib/guard-config.mjs; the TEST-3997 shared-lib expectation for the same path is moved to protected-l3 | `sed:s/  - \.aai\/scripts\/lib\/guard-config\.mjs/  - .aai\/scripts\/lib\/guard-configX.mjs/` on docs/ai/docs-audit.yaml | green |

Test counts by type: unit 10, integration 8, inspection 6 (24 rows). The
re-homed rows of other specs (D-REHOME) keep their own ids and mutations.

RED observations (stored under `docs/ai/tdd/sync-on-node/red/`): TEST-4000 to
TEST-4011 and TEST-4013, TEST-4014 fail on the baseline because the
reference copies, their helper, the node:test files, the module and the two
libs do not exist (TEST-4004 also because the three modules keep their own
identity checks and the `..` case returns the wrong directory); TEST-4012
fails because the recorded repro exits 1 on the baseline; TEST-4015 fails
because the `.sh` is still the bash twin (more than 20 lines); TEST-4016
fails because the `.ps1` is still the twin and the Pester file is absent;
TEST-4017 to TEST-4022 fail because the sync op of the node twin, the
upgrade proof's vendored module, the suite rows, the docs, the follow-up
closures and the plan's section 6 are absent.

Hosted checks (CI, not Test Plan rows; recorded in the validation report
from the PR's ps1-quality run):

- H1: `windows-5_1` (Windows PowerShell 5.1 and pwsh 7) and `windows-wsl1`
  full-suite steps report `aai-sync.Tests.ps1` passed with its five cases,
  skipped count still 4, TotalCount at or above 111, no failed container.
- H2: the `windows-parity` job's two steps pass with the smoke sync
  scenario (SY-01) compared on pairs sh:ps1, sh:node and ps1:node, the node
  twin present; `AAI-PARITY-ELAPSED` recorded per engine.
- H3: the Windows PowerShell 5.1 smoke (`& .\.aai\scripts\aai-sync.ps1
  -TargetRoot $target -Profile extended`) passes, proving the `.ps1`
  launcher and the module natively on Windows.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-node.sh`
  exits 0 (20 rows) and the same for `tests/skills/test-aai-sync-docs.sh`
  (3 rows), plus the touched and selected suites run the same way:
  test-aai-sync-seed.sh, test-aai-layer-profiles.sh, test-aai-layer-drift.sh,
  test-aai-update-check.sh, test-aai-harness-shims.sh,
  test-aai-legacy-migrations.sh, test-aai-bootstrap.sh,
  test-aai-bootstrap-node.sh, test-aai-update-node.sh,
  test-aai-hook-installer-node.sh, test-aai-git-ref-guard.sh,
  test-aai-hygiene-pack.sh, test-aai-doctor.sh, test-aai-pre-commit-checks.sh,
  test-aai-install-parity.sh, test-aai-win-fallback.sh,
  test-aai-expert-fetch.sh, test-aai-routine.sh, test-aai-golden-flow.sh,
  test-ps1-quality.sh; then the full sweep once before close with
  `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/aai-sync.test.mjs`,
  `tests/skills/lib/resolve-base.test.mjs`, `tests/skills/lib/install-parity.test.mjs`,
  `tests/skills/lib/aai-update.test.mjs`, `tests/skills/lib/aai-bootstrap.test.mjs`,
  `tests/skills/lib/install-pre-commit-hook.test.mjs` and
  `tests/skills/lib/release-notes-docs.test.mjs` exit 0 (also under Node 22;
  the PowerShell-side corpus fails on CI and names the tool when pwsh is
  missing, and skips with a named reason locally).
- Hosted checks H1, H2 and H3 from the PR's ps1-quality run; a divergence
  that appears only on Windows gets a DR, an allowlist row and a follow-up in
  a remediation pass, never a normalization.
- `node .aai/scripts/spec-lint.mjs --path <this spec>`,
  `node .aai/scripts/mutation-gate.mjs` for this spec and
  `node .aai/scripts/spec-amend.mjs list --strict` pass.

## Evidence contract

ref_id `sync-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/sync-on-node/` and `docs/ai/tdd/spec-sync-on-node/`
(gitignored); each AC row's Evidence names its green log and mutation
record; the validation report and review verdict under `docs/ai/reports/`
and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- The `.ps1` launcher's marshalling under Windows PowerShell 5.1 (legacy
  native argument passing drops an empty string, so `-TargetRoot ""` reaches
  the module as a missing value; both exit 2) is proven only by H1.
- `fs.cpSync` with `verbatimSymlinks` on Windows needs the symlink privilege
  for a link in the source; the twins had the same dependency (`cp -a`,
  `Copy-Item`); proven only by H2 on the shipped tree, which holds no link.
- `fs.renameSync` over an open or read-only file on Windows fails; the
  module then exits 1 naming the path, as the twins failed; not reproduced at
  planning.
- DR-7 refuses a consumer whose `.aai` or skill tree is a symbolic link out
  of the project, which both twins accepted; disclosed in the CHANGELOG.
- DR-13 leaves the 2026-03 legacy layout in a target that never synced since
  then; disclosed with the manual cleanup.
- The corpora's runtime is estimated at about 40 s for the bash side (35
  cases at about 0.3 s per side plus KR1 and KR2 at about 2.6 s each) and
  about 60 s for the PowerShell side; the suite weight 196 is the fallback.
  TEST-3569's parity bounds now include the node twin on the sync scenarios
  (estimate: under 6 s added); a bound exceeded on the reference host moves
  a scenario's tier by a recorded edit, never the bound.
- A downstream project without Node can no longer sync or install the layer;
  it could not run `/aai-update` without Node since ride 10. This is the
  owner's decision, disclosed in the CHANGELOG.
- The umbrella RFC-0017 stays open across this child-phase delivery unless
  D-PHASE5 finds every criterion met; the close may trip the docs-audit
  false-open on the parent, suppressed with a fresh doc_lifecycle event as in
  earlier slices.

Registry items closed by this scope: fu-resolvebase-dotdot-after-symlink, fu-suite-git-env-scrub-class, fu-parity-pin-template-spacing, fu-parity-ps1-timestamp-precision, fu-parity-gitignore-block-order, fu-parity-ps1-hook-exec-bit, fu-parity-ps1-report-name-local-time, fu-parity-ps1-report-backticks, fu-parity-win-ps1-crlf-bom, fu-parity-sh-report-stamp-two-reads, fu-sync-ps1-merge-lib-stderr-5-1, fu-sync-ps1-dangling-src-symlink, fu-sync-symlinked-tree-root (each with the evidence named in D-FU; run 9 reopened the Windows source-path item, which closes only with hosted evidence H2).

Items this scope touches and leaves open, with reasons:
`fu-sync-core-profile-dangling-wrappers` (a profile-list policy question, not
an engine difference), `fu-sync-invalid-utf8-names-linux` (the module's byte
predicate is probed with invalid UTF-8 names in TEST-4009 on Linux CI only;
the item closes when H2 or the Linux gate records that case, else stays),
`fu-sync-bounded-hang-orphan` (a sync-seed test helper this ride does not
change), `fu-sync-seed-cache-no-ci-gain` (CI timing of a suite, not the
engine), `fu-parity-win-odd-root-dirs` (an `aai-update.sh` Git Bash residue
on Windows, not the sync), `fu-hooks-merge-group-level-keys` (the merge
library's algorithm, out of scope), `fu-merge-sync-writes-via-parent-link`
(merge-cleanup, not this sync), `fu-recheck-state-tracked-premise` (a recheck
binding premise), `fu-parity-stamp-rows-paired` and the other
`fu-parity-*-infra` items (harness tooling this ride does not change),
`fu-docs-audit-yaml-misnamed-guard-config` (the guard-policy file, untouched),
`fu-pipefail-early-readers-other-suites` (other suites' pipelines; the sync's
own instances disappear with the twin), `fu-bootstrap-gitignore-crlf` (the
bootstrap keeps its own seed; suggested follow-up in D-FU).
