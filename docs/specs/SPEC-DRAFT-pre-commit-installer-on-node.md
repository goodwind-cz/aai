---
id: spec-pre-commit-installer-on-node
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 26a40fa3c44b213778d517841d5beb831298b8ebf8c44b06a86f33c64f7bbbc5
ceremony_level: 3
links:
  requirement: pre-commit-installer-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run the git hook installer as one Node module behind thin launchers

SPEC-FROZEN: true

## Links

- Requirement: [Run the git hook installer as one Node module behind thin launchers](../issues/CHANGE-DRAFT-pre-commit-installer-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 11 (owner sign-off: yes; merge by the owner). Plan section 4
  decision 1 applies: Node is a hard prerequisite on the install and update
  path; launchers refuse without Node and print an install hint.
- Structural template: [SPEC-0307](SPEC-0307-spec-update-on-node.md) (ride
  10: frozen references with a sha256 pin, differential corpora on both
  sides, launchers, Pester, scratch install, the parity harness's module
  twin, wiring named up front). Earlier precedents:
  [SPEC-0306](SPEC-0306-spec-bootstrap-on-node.md) (ride 9),
  [SPEC-0267](SPEC-0267-spec-node-first-reap-tests.md) (reaper launchers),
  [SPEC-0284](SPEC-0284-spec-install-path-parity-harness.md) (parity
  harness), [SPEC-0278](SPEC-0278-spec-git-hook-bodies-single-source.md)
  (hook bodies single-sourced in `.aai/templates/git-hooks/`; unchanged here).
- Specs whose tests this ride re-homes (D-REHOME): SPEC-0156
  (`spec-agent-shell-can-write-the-shipping-repo`), SPEC-0184
  (`spec-update-installs-ref-guard-undisclosed`), SPEC-0201
  (`spec-shipped-guards-have-no-downstream-trigger`), SPEC-0011
  (`docs-audit-closeout-guardrails`), SPEC-0013 (`workflow-hygiene-pack`),
  SPEC-0278, SPEC-0284, SPEC-0306.
- Shared code read and changed: `.aai/scripts/lib/guard-config.mjs` (gains
  the one ref_guard writer; its reader strips a leading byte order mark,
  D-POLICY). Shared code read but not changed: the four hook templates,
  `.aai/templates/docs-audit.template.yaml`, `.aai/scripts/aai-doctor.mjs`
  (CAT-12 and CAT-17 keep naming `install-pre-commit-hook.sh`), `aai-sync.sh`
  and `aai-sync.ps1`.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 compatible suites, Pester 5, Windows PowerShell 5.1 and pwsh 7).
- Baseline: main `bf0148d6`.

## Implementation strategy

- Strategy: tdd
- Rationale: owner requirement for every Node-first ride: TDD in runs of
  about three Spec-ACs. The port replaces two drifting twins whose `.ps1`
  side is covered mostly by pins on its source text; every rule test is RED
  before the module exists, the two differential corpora stay RED until the
  module matches each frozen reference (or the named DR), and every Test
  Plan row carries a mutation (mutation_gate v1). Wiring and docs rows are
  inspection tests, still seen RED first because the rows, entries and
  sentences they check are absent on the baseline.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: ceremony level 3 (the installer writes the ref-guard
  and close-gate hooks); a new module, two launchers, two frozen references,
  a shared lib change, re-homed assertions in nine existing suites, the
  parity driver, CI path filters and PROFILES; the main checkout is shared
  with other sessions and holds unrelated uncommitted files.
- User decision: worktree (owner-directed own worktree, already recorded in STATE)
- Base ref: bf0148d6
- Worktree branch/path: feat/pre-commit-installer-on-node at /Users/ales/Projects/aai-worktrees/pre-commit-installer-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/install-pre-commit-hook.mjs .aai/scripts/install-pre-commit-hook.sh
  .aai/scripts/install-pre-commit-hook.ps1 .aai/scripts/lib/guard-config.mjs
  .aai/system/PROFILES.yaml .aai/SKILL_UPDATE.prompt.md
  tests/fixtures/hook-installer-reference/install-pre-commit-hook.sh
  tests/fixtures/hook-installer-reference/install-pre-commit-hook.ps1
  tests/skills/lib/hook-installer-reference.mjs tests/skills/lib/install-pre-commit-hook.test.mjs
  tests/skills/lib/install-pre-commit-hook-fixtures.mjs tests/skills/test-aai-hook-installer-node.sh
  tests/skills/test-aai-hook-installer-docs.sh tests/skills/install-pre-commit-hook.Tests.ps1
  tests/skills/lib/vendor-hook-installer.sh tests/skills/test-aai-git-ref-guard.sh
  tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-docs-audit.sh
  tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity.test.mjs
  tests/skills/lib/install-parity-allowlist.tsv tests/skills/lib/aai-bootstrap.test.mjs
  tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
  tests/skills/test-aai-pr-preflight.sh tests/skills/test-aai-suite-reuse.sh
  tests/skills/suite-map.yaml tests/skills/suite-weights.tsv
  tests/skills/lib/cd-subshell-leak-baseline.tsv tests/skills/test-aai-win-fallback.sh
  tests/skills/test-aai-update-node.sh
  .github/workflows/ps1-quality.yml CHANGELOG.md docs/USER_GUIDE.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-DRAFT-pre-commit-installer-on-node.md
  docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md docs/INDEX.md
  (decisions.jsonl only for the amendment and follow-up records; the
  allocator renames the two DRAFT files at merge; the fixtures file only if
  the corpus fixtures are split out of the node:test file;
  test-aai-win-fallback.sh only if its ps1 path derivation needs a hop for
  the new helper.)
- Code review required: true (L3: the most capable tier, mandatory; a waiver
  goes to the operator).

## Ceremony

- Level 3, declared voluntarily and on the intake's instruction. Canon does
  not force it: `.aai/scripts/install-pre-commit-hook.*` and
  `.aai/scripts/lib/guard-config.mjs` are not in `protected_paths_l3`
  (docs/ai/docs-audit.yaml, measured at `bf0148d6`), and no protected file
  is touched (WORKFLOW.md, the state engine, the allocator,
  `pre-commit-checks.sh` and the hook gate stay unchanged). The installer
  writes the reference-transaction guard and the close gate that
  `/aai-update` installs into every consumer, so the ride takes L3's
  mandatory most-capable review, the operator checkpoint before merge, and
  no delta re-check. Adding the installer to `protected_paths_l3` is the
  owner's call and is filed as a follow-up (D-FU), not done here.
- Suite selection: Validation runs the selected suites between runs and the
  full sweep once before close (`AAI_TEST_TIMEOUT=3000`).
- One PR. The size is comparable to ride 10 (one module of about 600 lines,
  one node:test file, two new suites, edits to nine suites); no split is
  proposed. D-SLICES names the fallback ship point.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2.57, Node 22.23.1, pwsh
7.6.3, git 2.54.0, umask 0022) on 2026-11-21 at `bf0148d6`, in scratch
repositories under the session scratchpad. One run each; they size the
work, they are not thresholds.

- `.aai/scripts/install-pre-commit-hook.sh`: 1020 lines, 550 code lines
  (`grep -cvE '^[[:space:]]*(#|$)'`), mode 100755, git blob
  `2d9e1626bf1e1030f31ab4dfcad734ee19aac08a`, sha256
  `140b17eb636eff8c7ae13d04166e46be589fd7aef3e3a983b2b0fa018684d5ff`, 68
  em dashes (non-ASCII) in its text.
- `.aai/scripts/install-pre-commit-hook.ps1`: 819 lines, 557 code lines,
  mode 100644, ASCII, git blob `c46255f4cafda88a1f8ffced7fbdc12333766ea6`,
  sha256 `b8c8697a969a123277afdb21933f5a9f6c93041b1f449716c20f9a1ddbb6e28b`.
  Both LF; last commit touching either is `3e6b52d5`.
- Help: bash `-h` prints every `#` line of the whole script through
  `sed 's/^# \{0,1\}//'`, 377 lines, the first one `!/usr/bin/env bash`;
  PowerShell `-h` is a binding error (`Missing an argument for parameter
  'Hooks'`), exit 1.
- Unknown argument: bash `ERROR: unexpected argument: <arg>` on stderr, exit
  2; PowerShell binding error, exit 1. `--print bogus` exits 2 in bash (the
  token is not consumed and is then unexpected), not 0 as the text of
  `fu-installer-flag-lattice-no-mode` says; its other two examples hold.
- Flag lattice, bash: `--uninstall --decline-ref-guard` exits 0, removes the
  ref-guard, records `ref_guard: declined` and leaves pre-commit and pre-push
  installed; `--uninstall --arm-ref-guard` installs the ref-guard, exit 0;
  `--print --uninstall`, `--hooks index --print` and `--print pre-push --hooks
  index` print and exit 0; `--force --uninstall` uninstalls (force
  ignored); `--hooks index --hooks ref-guard` takes the last one. PowerShell:
  `-Uninstall -DeclineRefGuard` and `-Uninstall -ArmRefGuard` behave the same
  way (exit 0).
- `--hooks` tokens: bash accepts `index,` (trailing empty token ignored,
  exit 0), refuses ` index` and `Index` (exit 2); PowerShell trims and
  matches case-insensitively (`-Hooks Index` and `-Hooks ' index , ref-guard'`
  install, exit 0) and refuses `index,` (exit 2, empty token). PowerShell
  also accepts abbreviations (`-F`), common parameters (`-Verbose`) and, under
  pwsh 7, `--force`.
- Not a repository: bash `ERROR: not inside a git repository.` exit 1;
  PowerShell `You cannot call a method on a null-valued expression.` exit 1.
- Declined plus a foreign reference-transaction hook, plain run: both twins
  refuse the whole run (exit 1, nothing installed) although the declared
  decline means that slot would not be written.
- A directory at the reference-transaction slot, bash plain run: pre-commit
  and pre-push are written, a stray `reference-transaction.aai-tmp.<pid>`
  lands inside the directory, the attestation fails, exit 1 (the
  cross-slot preflight covers pre-commit and pre-push only).
- PowerShell, a directory at the pre-push slot: refused as foreign at the
  first `Write-Error`, which terminates under `ErrorActionPreference Stop`;
  only the first refused slot is ever reported.
- Policy writes, bash replace branch (`mktemp` plus `mv`): a 0644
  `docs/ai/docs-audit.yaml` becomes 0600; a symlinked config is replaced by a
  regular file and the link target keeps the old value; on a CRLF file the
  replaced line loses its CR (the other lines keep theirs). PowerShell on
  POSIX (`Set-Content`): every CRLF becomes LF. The template
  `.aai/templates/docs-audit.template.yaml` carries no `ref_guard` key, so a
  seeded file takes the append branch.
- PowerShell argument marshalling into a launcher without a param block,
  measured with a stub: `pwsh -File x.ps1 -Hooks index,ref-guard` hands
  `-Hooks`, `index,ref-guard`; in-session `& x.ps1 -Hooks index,ref-guard`
  hands `-Hooks` and an `Object[]`, which `& node ... @args` flattens to two
  arguments; `-Force:$false` arrives as `-Force:` (in session) or `-Force`
  (`-File`) followed by a `Boolean`, and the native call drops the colon
  token and passes `False`.
- Both twins write byte-identical hooks on a plain install (cmp of the
  pre-commit hook, mode 0755 under umask 0022). Timing: five bash plain
  installs 1 s, three pwsh plain installs 2 s.
- Callers outside docs history: `SKILL_UPDATE.prompt.md` step 4 (`bash
  .aai/scripts/install-pre-commit-hook.sh  # .ps1 on Windows`),
  `SKILL_INTAKE.prompt.md` (prose), PROFILES core (both twins;
  `lib/guard-config.mjs` and the four templates are core too),
  `aai-doctor.mjs` (existence check and remedy text naming the `.sh`), the
  hook templates (prose and the uninstall lines inside
  `reference-transaction.sh`), `ps1-quality.yml` (path lists and the
  Windows CAT-17 step running `bash .aai/scripts/install-pre-commit-hook.sh
  --arm-ref-guard`), `docs/USER_GUIDE.md`. `aai-sync` and `aai-update.mjs`
  never run the installer; `/aai-update` runs it as SKILL_UPDATE step 4,
  after the update script has returned 0.
- Source-shape pins (counted by a read-only sweep: one assertion reading
  the installer's working-tree text is one site): 62 against the `.ps1`, 51
  of which break when it becomes a launcher, and 8 against the `.sh`, 6 of
  which break (the intake's "about 99" counted raw lines naming the `.ps1`).
  Breaking sites: `test-aai-git-ref-guard.sh` 43 `.ps1` and 2 `.sh` (TEST-309,
  314, 608, 631, 632, 633, 637, 641, 642, 644, 646, 647),
  `test-aai-hygiene-pack.sh` 6 `.ps1` and 2 `.sh` (test_618, test_813,
  test_818), `test-aai-docs-audit.sh` 2 and 2 (TEST-013, TEST-008).
  `test-aai-git-hook-templates.sh` (TEST-3432, 3437, 3444) and
  `test-aai-git-ref-guard.sh` TEST-316 keep passing. `test-aai-doctor.sh` and
  `test-aai-update-check.sh` hold no source-shape pin on the installer.
- Behaviour runs of the installer that the swap affects through vendoring:
  `tests/skills/lib/vendor-hook-installer.sh` (17 call sites in
  git-ref-guard, pre-commit-checks, doctor, git-hook-templates, docs-audit,
  tracked-ignored, hygiene-pack) and the Pester `Copy-Installers` copy only
  the `.sh`/`.ps1` and the templates; a launcher there finds no module.
- Parity harness: ten hook scenarios HK-01 to HK-10 run the target's synced
  installers (`bash .aai/scripts/install-pre-commit-hook.sh`, `<ps> -File
  .aai/scripts/install-pre-commit-hook.ps1`) on twins sh and ps1 only; the
  node twin has `ops: ['bootstrap', 'update']`; allowlist row
  `hk-uninstall-removes-hooks` (pairs `sh:sh,ps1:ps1`, HK-09) is the only
  hook row; smoke tier holds HK-01, HK-03, HK-05, HK-07 and HK-10.
- `tests/skills/suite-map.yaml` holds 140 rows (hygiene test_090 pins 140);
  the highest Test Plan id in the 3000 range is TEST-3978.
- `.aai/SKILL_UPDATE.prompt.md` is 3600 bytes (`/usr/bin/wc -c`); its step 4
  (lines 47 to 65) is 1196 bytes; TEST-621 pins `AAI:REF-GUARD`,
  `refs/heads/main`, `AAI_GIT_WRITE=1`, `--decline-ref-guard` and the
  absence of `refuses to overwrite a foreign pre-commit hook`.

## Decisions

### D-MODULE. `.aai/scripts/install-pre-commit-hook.mjs`

Dependency-free ESM, Node 22 compatible, imports only `node:` specifiers
plus `./lib/guard-config.mjs`, none of `node:http`, `node:https`,
`node:net`, `node:tls`, `node:dgram`; ASCII only (non-ASCII output
characters as `\u` escapes, so the em dashes of the bash lines are
`\u2014`); no side effect on import (main guard compares `realpathSync` of
`process.argv[1]` and of the module); never reads standard input; never
touches `process.stdout` or `process.stderr` (output through `fs.writeSync`
on descriptors 1 and 2). It holds all installer policy: arguments and the
one resolved mode, the ref_guard policy decisions, template loading, path
resolution, slot attestation, composition, writes, upgrade, uninstall,
decline, arm, post-run attestation and the exit code. Every child process
(git only) goes through one injectable seam (`io.spawn`, default
`runChild`); the rename of a written temp file goes through `io.rename`
(default `fs.renameSync`) so the landing check (D-WRITE) is testable. The
module holds no hook body: no line of 40 or more characters of any template
occurs in it.

Exports at least: `parseArgs`, `resolveMode`, `resolveBase`,
`loadTemplates`, `composePreCommit`, `hasMarkerLine`, `resolveSlots`,
`classifySlot`, `planUpgrade`, `writeSlot`, `run`, `main`. `run(argv, io)`
and `main(argv)` resolve to the exit code; `run` takes injectable `out`,
`err`, `env`, `cwd`, `spawn`, `rename`, `platform` and `scriptDir`.

It contains these exact lines, each once, and no comment repeats one (the
Test Plan mutations rely on them):

```js
import { readRefGuardPolicy, writeRefGuardPolicy } from './lib/guard-config.mjs';
const EXIT_FAIL = 1;
const EXIT_USAGE = 2;
const GUARD_BEGIN = '# AAI:GUARD-CHECKS BEGIN';
const GUARD_END = '# AAI:GUARD-CHECKS END';
const HOOK_TOKENS = ['index', 'ref-guard', 'close-gate'];
const PRINT_KINDS = ['index', 'ref-guard', 'guard-checks', 'pre-push'];
const MODE_FLAGS = ['--uninstall', '--print', '--decline-ref-guard', '--arm-ref-guard'];
const PS_NAMES = { '-force': '--force', '-uninstall': '--uninstall', '-hooks': '--hooks', '-declinerefguard': '--decline-ref-guard', '-armrefguard': '--arm-ref-guard' };
const GIT_PATH_ARGS = (name) => ['rev-parse', '--git-path', `hooks/${name}`];
const SKIP_DECLINED = (mode, policy) => !mode.force && policy === 'declined';
const ensureFinalLf = (b) => (b.length && b[b.length - 1] !== 10 ? Buffer.concat([b, Buffer.from('\n')]) : b);
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };
  if (refusals.length) return refuseWholeRun(refusals);
    if (!landed(slot, bytes)) return landingFailure(slot);
```

Every output string of the DR table occurs once in the module (a refusal
sentence shared by two paths lives in one function, the SPEC-0184 TEST-633
discipline).

### D-CLI. Arguments, help and the one resolved mode (slice a; DR-1 to DR-7)

- Arguments are read left to right. Accepted on every entry point:
  `--force`, `--uninstall`, `--print [kind]`, `--hooks <csv>`,
  `--decline-ref-guard`, `--arm-ref-guard`, `-h`, `--help` (case-sensitive),
  and the five PowerShell names of the old `.ps1` (`-Force`, `-Uninstall`,
  `-Hooks <csv>`, `-DeclineRefGuard`, `-ArmRefGuard`), matched
  case-insensitively, exact names only (`PS_NAMES`); no abbreviation, no
  common parameter, no `=` form (DR-3).
- `--print` consumes the next argument only when it is one of `PRINT_KINDS`
  (bare `--print` means `index`), as the bash twin. `--hooks` and `-Hooks`
  need a value: at the end, the bash line `ERROR: --hooks requires a value
  (closed set: index, ref-guard, close-gate, all)` and exit 2 (DR-7). `-h`
  or `--help` prints the help text to stdout and exits 0 at its position
  (DR-1). Any other argument prints `ERROR: unexpected argument: <arg>` to
  stderr and exits 2 at its position (DR-2). A repeated `--hooks` or
  `--print` kind: the last one wins; a repeated flag is one flag.
- Help text (DR-1): lines 4 to 78 of the bash reference (its leading comment
  block: what the three hooks are, the usage lines, the idempotence and
  refusal rules; 75 lines, the first `Install the AAI git hook SET into the
  EFFECTIVE hooks directory — the one`) after `s/^# \{0,1\}//`, so every
  token hygiene TEST-814 requires stays (`token close-gate`, the closed set,
  `--print guard-checks`, `--print pre-push`, `ref_guard: declined`,
  `AAI:CLOSE-GATE`), then
  `  powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 [-Force] [-Uninstall] [-Hooks <csv>] [-DeclineRefGuard] [-ArmRefGuard]   # the long flags work too`
  and `Requires Node.js 22 or later; both launchers run .aai/scripts/install-pre-commit-hook.mjs.`
- `resolveMode` runs after parsing, before any git child or file access, in
  this order, each failure exit 2 with one stderr line and nothing else:
  1. Two different mode flags (`MODE_FLAGS`, canonical order): `ERROR: <a>
     and <b> are contradictory.` (for decline plus arm this is the bash
     line byte for byte) (DR-4).
  2. `--hooks` given with `--decline-ref-guard` or `--arm-ref-guard`: the
     bash line `ERROR: --hooks is contradictory with
     --decline-ref-guard/--arm-ref-guard (these act on the
     reference-transaction hook alone).`
  3. `--hooks` with `--print`: `ERROR: --hooks has no effect with --print
     (name the body instead: --print index, ref-guard, guard-checks or
     pre-push).`; `--force` with `--print`, `--uninstall` or
     `--decline-ref-guard`: `ERROR: --force has no effect with <mode flag>.`
     (DR-5).
  4. The `--hooks` value: split on `,`, each token trimmed of spaces and
     tabs, matched case-sensitively against `HOOK_TOKENS` and `all`; an
     empty value or token or an unknown token: the bash line `ERROR: unknown
     --hooks value: '<token>' (closed set: index, ref-guard, close-gate,
     all)` (DR-6).
- The result is exactly one mode (`help`, `print`, `uninstall`, `decline`,
  `arm`, `install`) with its modifiers (`force`, the selected slot set,
  `print kind`), and `selected` is kept apart from what the run will write
  (D-SLOT's `planned`), which closes `fu-installer-want-refguard-overloaded`.
- Base directory (DR-20): the environment's `PWD` when it is absolute and
  names the same device and inode as the process working directory, else
  `process.cwd()` (the SPEC-0307 D-CLI rule); git children run with that
  cwd and relative `--git-path` answers resolve against it.
- Exit codes: 0 done; 1 refusal, failed write, failed attestation, not a
  repository, git missing, or an internal error (`install-pre-commit-hook:
  internal error: <message>` on stderr); 2 usage.

### D-POLICY. One reader and one writer of `ref_guard` (slice a; DR-15 to DR-17)

- The module reads the policy only through `readRefGuardPolicy(<repo
  root>/docs/ai, { warnPrefix: 'install-pre-commit-hook', warn })` (its
  warning goes to descriptor 2) and writes it only through the new
  `writeRefGuardPolicy`; it holds no `ref_guard` pattern of its own. Closes
  `fu-three-readers-three-whitespaces` (one reader for every case: the
  `.ps1`'s BOM, U+0085 and CR-only readings of `declined` become the
  reader's fail-closed `armed`, except the BOM case below) and
  `fu-test618-positional-pattern` (the conformance test it names is
  re-homed, D-REHOME).
- `readRefGuardPolicy` change (DR-16): a single leading U+FEFF of the file is
  ignored, so `\uFEFFref_guard: declined` on line 1 reads `declined` (it
  read `armed` before; the `.ps1` twin read `declined`). Nothing else in the
  reader changes: first column-0 key with a non-blank token wins, an
  out-of-vocabulary value reads `armed` with the warning, `readGuardConfig`
  and every dial are untouched (`pre-commit-checks.sh`'s shell mirror stays
  conformant, hygiene test_031). `aai-doctor.mjs` CAT-17 reads through the
  same function, so a BOM-prefixed declined file now reports DECLINED
  there too (the seam row of TEST-3983).
- `writeRefGuardPolicy(dir, value, { seedFrom })` in
  `.aai/scripts/lib/guard-config.mjs`, with the exact lines
  `const REF_GUARD_KEY_LINE = /^ref_guard:/;` and `const BOM = '\uFEFF';`
  each once. `value` must be `armed` or `declined`, else it throws. It
  returns `{ path, seeded: 'template'|'empty'|null, changed, removed:
  [<line numbers>] }` and:
  - Absent file: with `seedFrom` a regular file, copies its bytes (the
    caller prints the bash SEED line); otherwise starts from an empty file
    (the caller prints the bash NOTE line); a parent directory is created.
  - A symbolic link at the path is followed to its target, which is written
    in place of the link (the link is kept); a dangling link or a target
    that is not a regular file throws `<path> is a symbolic link to <x>;
    nothing was written` (DR-15).
  - Lines are split keeping each line's own terminator (LF, CRLF, or none on
    the last line); a leading BOM is kept byte for byte and is not part of
    line 1 for matching. Key lines are column-0 lines matching
    `REF_GUARD_KEY_LINE` (valued or not). The first key line becomes
    `ref_guard: <value>` with its own terminator; every later key line is
    removed and its 1-based line number reported in `removed` (DR-17; this
    also makes a value-less key line count as the key, closing
    `fu-ac05-counts-a-valueless-key` and `fu-doubled-key-has-no-repair`).
    With no key line: when the file is non-empty and its last line has no
    terminator, the file's terminator (the first CRLF or LF found, LF when
    none) is appended first; then `ref_guard: <value>` plus that terminator.
  - A target the process cannot write (`fs.accessSync(target, W_OK)`
    fails, as for a 0444 file) throws `<path> is not writable; nothing was
    written` before any temp file exists, so a read-only config is refused
    as the bash append was (SPEC-0184 TEST-635).
  - When the result equals the current bytes nothing is written
    (`changed: false`). Otherwise the bytes go to a temp sibling of the real
    target (`<target>.aai-tmp.<pid>`, created exclusively, permission bits
    of the existing target, 0666 minus umask for a new file) and are renamed
    over it; the temp is removed on any failure (DR-15: mode, link, line
    endings and BOM kept).
  - Read-back: `readRefGuardPolicy(dir)` must equal `value`, else it throws
    `wrote ref_guard: <value> to <path> but reading it back gives <x>`.
- Plain install with more than one key line: no write; one stderr line
  `WARNING: <cfg> carries <n> ref_guard: lines (lines <a>, <b>); the first
  one wins. Repair: bash <root>/.aai/scripts/install-pre-commit-hook.sh
  --arm-ref-guard (or --decline-ref-guard).` Arm and decline print
  `Removed <n> duplicate ref_guard: line(s) from <cfg> (lines <a>, <b>).`
  when `removed` is non-empty.

### D-TEMPLATE. Templates, `--print` and composition (DR-19)

- Templates are read from `<scriptDir>/../templates/git-hooks/` (the
  module's own location, never the target), every CR byte removed. For the
  run's needs (print: the kind; install: index and guard-checks for
  pre-commit, ref-guard when planned, pre-push for close-gate; arm:
  ref-guard; uninstall and decline: none), every missing file prints the
  bash line `ERROR: AAI hook template missing: <path>` and the run exits 1
  before any write. Malformed: the index template needs a first and a
  second line (the bash line `ERROR: AAI hook template malformed (needs a
  first line and a second line): <path>`); the guard-checks template needs
  exactly one `GUARD_BEGIN` line and one `GUARD_END` line, BEGIN first, and
  a final LF (`ERROR: AAI hook template malformed (needs one GUARD-CHECKS
  BEGIN line, then one END line, and a final newline): <path>`, DR-19).
- `--print <kind>` (no repository needed, no git child): the CR-stripped
  template bytes on stdout, exit 0.
- Fresh pre-commit: `composePreCommit(index, guard)` = the index template's
  first line with its LF, the guard block, the rest of the index template,
  then `ensureFinalLf` (the bash bytes; the `.ps1` wrote one byte less for an
  index template without a final LF, DR-19, closing
  `fu-hook-tmpl-final-lf-parity`). Reference-transaction and pre-push are
  the CR-stripped template bytes.

### D-SLOT. Paths, slot attestation and the whole-run refusal (slice b; DR-8 to DR-12, DR-21)

- Repository: `git rev-parse --show-toplevel` (stdout, trailing newlines
  removed); a nonzero exit prints the bash line `ERROR: not inside a git
  repository.` and exits 1; git that cannot start prints `ERROR: git was not
  found on PATH.` and exits 1 (DR-8, closing
  `fu-hook-installer-not-a-repo-msg`). Each slot's path is
  `git rev-parse --git-path hooks/<name>` (`GIT_PATH_ARGS`; names
  pre-commit, reference-transaction, pre-push), resolved against the base
  directory when relative, so `core.hooksPath` (relative, absolute, not yet
  existing), a linked worktree and a subdirectory cwd behave as git itself
  resolves them; a failure prints the bash three-line refusal for that slot
  and exits 1. git children run with stdin ignored and stdout piped.
- `planned` = the selected slots, minus the reference-transaction slot when
  `SKIP_DECLINED(mode, policy)` holds in an install run (it prints the
  bash Skipped line and the DR-10 re-arm line). A slot that is selected but
  not planned is neither attested nor written (DR-11: both twins refused
  the whole run for a foreign hook in a declined slot).
- `classifySlot` (lstat, then content as bytes) gives one state per planned
  slot, all computed before anything is written:
  - `absent`;
  - `current` (pre-commit: an AAI marker line and a guard block whose
    interior equals the shipped one; reference-transaction and pre-push:
    bytes equal to the template);
  - `older` (pre-commit only: AAI marker line, provably upgradable per
    D-WRITE);
  - `marked-differs` (reference-transaction or pre-push: marker line, other
    bytes; no write without `--force`, DR-14);
  - `foreign` (a regular file without the slot's marker line);
  - `unprovable` (pre-commit carrying the marker but refused by name: a
    UTF-8 BOM, no newline-terminated line, a CR-terminated first line, a
    stray END, more than one BEGIN or END, END above BEGIN: the six bash
    lines);
  - `link-file` (a symbolic link to a regular file: classified by its
    target's bytes for `current` and `marked-differs`, which need no write;
    any other target state is refused with the bash symlink line, because
    nothing is ever written through a link; with `--force` the link itself
    is replaced by a regular file);
  - `bad-type` (a directory, a dangling link, a link to a non-regular file,
    a named pipe, a socket or other: the bash `assert_regular_slot` lines,
    refused even with `--force`, now for all three slots, DR-12).
- `hasMarkerLine` works on bytes: the marker opens a line (column 0) and is
  followed by a space, an LF, the end of the file, or a CR that is followed
  by an LF or the end of the file (DR-21).
- The whole-run refusal: `foreign` without `--force`, `unprovable`, a
  refused `link-file` and `bad-type` slots are all collected; every refusal
  prints its lines in slot order pre-commit, reference-transaction, pre-push
  (DR-9: the `.ps1` stopped at the first and used the order pre-commit,
  pre-push, reference-transaction), then, when any was not a foreign
  refusal, the bash line `ERROR: refusing the whole run — nothing was
  written. Fix the slot(s) named above and re-run.`; exit 1. Nothing is
  written on a refusal: no hook, no temp file, no hooks directory, no
  policy line (DR-12).
- The hooks directory (the parent of the resolved slot paths) is created
  only after the checks pass; when it exists and is not a directory the bash
  two-line refusal, exit 1.
- On win32 the executable checks are skipped (DR-22); everywhere else a
  written hook is created with mode 0777 minus umask (bash `chmod +x` of a
  new file).

### D-WRITE. Writes, upgrade, uninstall, decline, arm (DR-13, DR-14, DR-18)

- Every write composes the bytes in memory, writes a temp sibling
  `<slot>.aai-tmp.<pid>` (exclusive create), renames it over the slot through
  `io.rename`, then checks the landing: the slot is a regular file (not a
  link) holding exactly the composed bytes. A failed landing removes the
  temp and any stray `<slot>/<temp basename>`, prints the bash line `ERROR:
  the <label> hook was composed but did not land at <slot> — ...`, exit 1
  (DR-13: the bash twin checked the landing only for a fresh pre-commit and
  pre-push, the `.ps1` never).
- Pre-commit `older` upgrade (`planUpgrade`, pure on bytes): no BEGIN
  anywhere in the file (substring) and no stray END: insert the guard block
  after line 1 when it starts with `#!`, else at the top; exactly one BEGIN
  line above exactly one END line: replace only the interior between them
  when it differs; every other byte stays as it was. The bash lines
  `Upgraded AAI pre-commit hook at <p>: added the AAI:GUARD-CHECKS block
  ...`, `Refreshed the AAI:GUARD-CHECKS block at <p> (...)` and
  `AAI pre-commit hook already installed at <p>. No action taken.`
- `marked-differs` (DR-14): no write; after the bash `already installed ...
  No action taken.` line one more line `NOTE: <p> carries <marker> but its
  bytes differ from the shipped body; pass --force to replace it.` Arm does
  the same (the `.ps1`'s `-ArmRefGuard` always rewrote the hook).
- Install success lines, effects, the `Uninstall with:` footer and the
  post-run attestation (re-resolve each planned slot, a regular file,
  the marker line, executable off win32; the bash error lines and the
  two-line summary, exit 1) are the bash reference's bytes.
- Uninstall: per selected slot, a slot path whose (followed) target is a
  regular file carrying the slot's marker line is unlinked (a link itself is
  unlinked, its target kept) with the bash Uninstalled line, else the bash
  `No AAI ... found ...` line; no template, no policy read except below.
  When the reference-transaction hook was removed and the policy reads
  `armed`, two more lines (DR-18, closing `fu-uninstall-refguard-leaves-armed`; when
  `docs/ai/docs-audit.yaml` does not exist the first line reads `NOTE: docs/ai/docs-audit.yaml does not exist, so ref_guard reads as armed by default and the next plain install (for example /aai-update) installs the guard again.`):
  `NOTE: docs/ai/docs-audit.yaml still reads ref_guard: armed, so the next plain install (for example /aai-update) installs the guard again.`
  and `To keep it off, run: bash <root>/.aai/scripts/install-pre-commit-hook.sh --decline-ref-guard`.
- Decline: a foreign reference-transaction hook (also one reached through a
  symlink) is refused unmodified (the bash two lines, exit 1); a directory or
  other bad-type slot is refused (DR-23); otherwise the declaration is written first, and
  only then an AAI hook is removed (an unwritable config leaves the hook in
  place and exits 1); the bash lines follow.
- Arm: the template is required; a foreign hook refused unless `--force`; a
  `bad-type` slot refused; the hooks directory created; the hook written when
  absent or forced (current and marked-differs as above); attested; then
  `armed` recorded and `Recorded ref_guard: armed in <cfg>` printed. The
  module keeps the bash order and carries the D4 rationale comment once
  (closing `fu-ps1-enable-refguard-no-rationale`, there is no second twin).
- Disclosure texts (DR-10): one text for both entries, the bash lines, with
  errors on stderr. The foreign reference-transaction refusal names
  `--print ref-guard` (closing `fu-ps1-refusal-no-manual-merge`, the
  `.ps1` launcher accepts `--print`), the install disclosure names the
  decline command (closing `fu-ps1-decline-not-disclosed`), and the re-arm
  advice after a skipped guard becomes
  `Re-arm with: bash <root>/.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard (--force installs the hook for this run only; ref_guard: declined stays recorded).`
  for both entries (closing `fu-ps1-decline-force-advice-wrong`: "or pass
  --force" did not re-arm the declaration).

### D-DRIFT. Every difference from either twin, each with a test

| Id | Bash twin | PowerShell twin | Module | Why | Test |
|---|---|---|---|---|---|
| DR-1 | `-h` prints all 377 `#` lines of the script | binding error, exit 1 | the 75-line leading comment block plus the PowerShell and Node lines, exit 0 | help must be short and work on both entries | TEST-3982, K18, P18 |
| DR-2 | unknown argument: error line, exit 2 | binding error, exit 1 | the bash line, exit 2 | one usage exit | TEST-3982, P19 |
| DR-3 | long flags only | native binding: abbreviations, common parameters, case-insensitive names, pwsh 7 also `--force` | long flags plus the five exact PowerShell names, case-insensitive | one grammar for both launchers | TEST-3982, P01 |
| DR-4 | two modes: the first dispatched wins, exit 0 | same | `ERROR: <a> and <b> are contradictory.`, exit 2 | the run must do what was asked or nothing (closes fu-installer-flag-lattice-no-mode) | TEST-3982, K20, P20 |
| DR-5 | `--force` and `--hooks` silently ignored where they mean nothing | same | usage line, exit 2 | a flag with no effect is a mistake the user should see | TEST-3982, K21 |
| DR-6 | `index,` accepted; ` index` and `Index` refused | trimmed, case-insensitive, `index,` refused | trimmed, case-sensitive, any empty token refused | one closed set spelled one way | TEST-3982, K22, P11 |
| DR-7 | missing `--hooks` value: exit 2 | binding error, exit 1 | the bash line, exit 2 | one usage exit | TEST-3982, P12 |
| DR-8 | git missing reads as not a repository | not a repository crashes with a null-method message | `ERROR: git was not found on PATH.`; the bash not-a-repo line | say the real cause (closes fu-hook-installer-not-a-repo-msg) | TEST-3986, K28, P17 |
| DR-9 | every foreign slot reported | stops at the first refusal; slot order pre-commit, pre-push, reference-transaction; attestation errors on stdout | every refusal, order pre-commit, reference-transaction, pre-push, stderr | Write-Error under Stop exited 1 by coincidence (closes fu-ps1-writeerror-terminates-before-exit) | TEST-3987, P03 |
| DR-10 | its own lines; re-arm says "or pass --force" | different lines: no decline hint, no `--print` hint, `pwsh ... -ArmRefGuard (or pass -Force)` | the bash lines with the rewritten re-arm line | one text; the advice must not misroute | TEST-3984, K16, P13 |
| DR-11 | a foreign hook in a declined ref-guard slot refuses the whole run | same | a declined, unforced slot is neither attested nor written | the decline means the slot is not ours to judge (closes fu-installer-want-refguard-overloaded) | TEST-3987, K23, P14 |
| DR-12 | reference-transaction slot not preflighted: partial install, stray temp in a directory slot; hooks dir created before the checks | no cross-slot preflight | every planned slot classified first; a refusal writes nothing, not even the hooks directory | a refusal must leave the tree as it was | TEST-3987, K24, P15 |
| DR-13 | landing checked for fresh pre-commit and pre-push only | never | every written slot | exit 0 must mean the bytes are where git looks | TEST-3988 |
| DR-14 | marked but different: "already installed", nothing said about the difference | same on install; `-ArmRefGuard` always rewrites | no write without `--force`, one NOTE line | never overwrite a hand-merged hook; say why it was left | TEST-3988, K30 |
| DR-15 | replace branch: mode to 0600, a symlinked config replaced, the replaced line loses its CR | Set-Content: symlink replaced, every line ending rewritten, BOM dropped | written through the link, mode kept, each line's ending and a BOM kept, no write when unchanged | the policy file is the user's (closes fu-ps1-symlink-config-replaced, fu-ps1-setcontent-rewrites-seed-eol) | TEST-3983, K25, K26, P16 |
| DR-16 | own grep: any column-0 `declined` line anywhere; locale-dependent whitespace | Get-Content decoding: BOM, U+0085 and CR-only read `declined` | `readRefGuardPolicy`, first key wins, a leading BOM ignored | one reader for the installer and the doctor | TEST-3983, TEST-3984, K27 |
| DR-17 | doubled key: arm writes then fails its read-back; decline exits 0 leaving both | same | arm and decline keep the first key line and remove the rest; a plain run warns and names the repair | an ambiguous file needs a command that repairs it | TEST-3983, TEST-3984, K27, P16 |
| DR-18 | uninstalling the ref-guard says nothing about the armed declaration | same | two lines naming the re-install and the decline command | the next /aai-update re-installs it silently otherwise | TEST-3984, K13 |
| DR-19 | index template without a final LF: LF added; guard template not checked | no LF added; not checked | LF added; the guard template checked for its markers and final LF | the twins wrote hooks one byte apart; a guard template without END would glue lines | TEST-3985 |
| DR-20 | message paths from the logical `$PWD` | `Get-Location` | the PWD rule of D-CLI | the bash bytes on POSIX | TEST-3986, K09 |
| DR-21 | marker followed by space, end of line, or a CR at the end of the line, via grep | on bytes; a CR followed by more bytes also counts | on bytes; a CR counts only before an LF or the end of the file | ownership is decided on the bytes | TEST-3987 |
| DR-22 | `-x` checked also under Git Bash | skipped on Windows | skipped on win32 | Git for Windows runs hooks regardless of mode bits | TEST-3988 |
| DR-23 | decline on a directory at the reference-transaction slot: records `declined`, exit 0 | same | refused as a bad-type slot (exit 1, the bad-type lines, nothing written); a symlinked foreign hook is refused like a regular one, as in bash, and is not a drift | a decline must not leave a slot git cannot run a hook from unexplained; the follows-the-link refusal is parity | TEST-3984, K14d |

Kept for parity, pinned as rules and not drifts: `--force` installs a
declined guard for that run and leaves `ref_guard: declined` recorded (the
SPEC-0184 NB3 decision); an upgraded or rewritten hook takes mode 0777 minus
umask, not its old mode; the help and usage lines go to stdout and stderr as
in bash; the SEED and NOTE disclosure on a first policy write; the
template-missing check runs before the hooks directory is created.

### D-REF. Frozen copies of both twins

`tests/fixtures/hook-installer-reference/install-pre-commit-hook.sh` (byte
copy of blob `2d9e1626`, sha256 `140b17eb...`, mode 100755) and
`tests/fixtures/hook-installer-reference/install-pre-commit-hook.ps1` (blob
`c46255f4`, sha256 `b8c8697a...`, mode 100644), LF through the existing
`.gitattributes` rules. `tests/skills/lib/hook-installer-reference.mjs`
exports `REFERENCE_SH`, `REFERENCE_PS1`, `REFERENCE_SH_SHA256`,
`REFERENCE_PS1_SHA256`, `REFERENCE_COMMIT` (`bf0148d6`),
`materializeHookInstallerReference(fromRoot, intoRoot)` (verifies both
hashes, a mismatch throws naming the file; writes the two files to
`<intoRoot>/.aai/scripts/` with modes 0755 and 0644 and the four current
templates from `<fromRoot>/.aai/templates/git-hooks/` to
`<intoRoot>/.aai/templates/git-hooks/`, because both twins read their
templates from their own location), and its own scratch helpers
`createOwnScratch`, `removeOwnScratch`, `removeOwnScratchAll` with `const
OWN_SCRATCH_PREFIX = 'aai-hk-';` and the marker `.aai-hk-owned`, with the
SPEC-0306 D-SAFETY refusal rules. Where git history holds `bf0148d6`,
TEST-3980 also requires each copy to equal `git show
bf0148d6:.aai/scripts/<name>`. The copies live outside `.aai/` (never
vendored) and outside the ratchets' scan directories.

### D-CORPUS. The differential corpora

In `tests/skills/lib/install-pre-commit-hook.test.mjs` (POSIX hosts; bash and
git; pwsh for the PowerShell side). Each case builds its fixture once per
side at the same absolute path under one own scratch root (the previous
side's tree renamed away first): a git repository (`git init -b main`, own
identity, one commit) whose `.aai/scripts/` holds either the frozen
reference (bash or PowerShell side) or the module and
`lib/guard-config.mjs` (module side), with the four templates and
`docs-audit.template.yaml` beside them. Both run with cwd the case's
directory and the environment: the caller's minus every `AAI_` variable,
plus `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL` an empty scratch file (so
a developer's global `core.hooksPath` can never redirect a write),
`LC_ALL=C`, `PWD` the cwd, `TMPDIR` a per-case scratch directory.

- Bash side (TEST-3989): `bash <case>/.aai/scripts/install-pre-commit-hook.sh
  <args>` against `node <case>/.aai/scripts/install-pre-commit-hook.mjs
  <args>`. Compared: exit code, stdout bytes, stderr bytes, and the case
  snapshot: every path under the case directory except `.git/` internals
  (the regular non-sample files of the resolved hooks directories and of a
  `core.hooksPath` directory are included) and `.aai/`, each with its type
  (file, link with its target text, directory), bytes and permission bits
  `mode & 0o777`; plus the `TMPDIR` listing. Rewrites before comparing, each
  registered per case on one side, a registered rewrite that changes nothing
  failing the case: DR-10 (the re-arm line), DR-14 (the NOTE line), DR-17
  (the WARNING and Removed lines), DR-18 (the two uninstall lines), the
  module's `install-pre-commit-hook: WARNING ref_guard value` line where the
  reference prints none.
- PowerShell side (TEST-3990): `pwsh -NoProfile -NonInteractive -File
  <case>/.aai/scripts/install-pre-commit-hook.ps1 <PowerShell-form args>`
  against the module with the same PowerShell-form arguments. Compared: exit
  code and the case snapshot only (every `.ps1` message is a DR-10 text);
  the asserted divergences below are compared to an expected value.
- Asserted divergences (not rewritten): K18 and P18 (help, DR-1), P19
  (DR-2), K20 and P20 (DR-4), K21 (DR-5), K22 and P11 (DR-6), P12 (DR-7),
  P17 (DR-8 message, both exit 1), P03 (DR-9: the module reports both
  refused slots), K23 and P14 (DR-11), K24 and P15 (DR-12), K25, K26 and P16
  (DR-15), K27 (DR-16 and DR-17).

Bash-side cases (K):

- K01 plain install in an empty repository; K02 the same twice (second run
  reports every hook already installed); K03 a foreign pre-commit (exit 1);
  K04 K03 with `--force`; K05 a pre-guard AAI pre-commit (the index template
  alone): upgraded by insertion; K06 a stale guard interior: refreshed;
  K07a to K07f the six `unprovable` pre-commit shapes (exit 1, file
  unchanged); K08 a symlinked pre-commit slot whose target is the K05 body.
- K09a `core.hooksPath=.githooks` (not yet existing), K09b an absolute
  `core.hooksPath` under the case, K09c a run from a subdirectory with K09a,
  K10 a linked worktree (`git worktree add` inside the case; the run there).
- K11a to K11d `--hooks index`, `ref-guard`, `close-gate`, `index,close-gate`;
  K12a to K12c `--hooks bogus`, `--hooks ''`, `--hooks` at the end.
- K13 `--uninstall` after K01, and `--uninstall --hooks ref-guard`.
- K14a `--decline-ref-guard` with no config (seeded from the template),
  K14b with an existing config, K14c with a foreign reference-transaction
  hook, K14d with that hook a symlink to a foreign file; K15 `--arm-ref-guard` after K14a; K16 a declined config and a plain
  run (skip); K16f the same with `--force`.
- K17 `--print` and each of the four kinds, run outside any repository;
  K18 `-h`; K19 `--bogus`; K20 `--uninstall --decline-ref-guard`; K21
  `--print --force`; K22 `--hooks index,`; K23 a declined config and a
  foreign reference-transaction hook, plain run; K24 a directory at the
  reference-transaction slot, plain run.
- K25 `--decline-ref-guard` on a symlinked config; K26 `--arm-ref-guard` on a
  CRLF config with mode 0644 and a `ref_guard: declined` line; K27a a doubled
  key (`armed` then `declined`) under `--arm-ref-guard`, K27b the same under
  `--decline-ref-guard`, K27c a plain run on it, K27d `ref_guard:\u00a0declined`
  plain run (the reader reads `declined`, the bash grep under `LC_ALL=C` read
  `armed`).
- K28 not a repository; K29a to K29d each of the four templates missing; K30
  a reference-transaction hook carrying the marker with other bytes; K31 the
  case directory path holding a space.

PowerShell-side cases (P), PowerShell-form arguments:

- P01 plain; P02 twice; P03 a foreign pre-commit and a foreign pre-push
  (both exit 1, trees unchanged; the module names both); P04 `-Force` on
  P03; P05 pre-guard upgrade; P06 stale refresh; P07 a BOM pre-commit
  (unprovable); P08 `core.hooksPath`; P09 `-Hooks index`; P10 `-Uninstall`
  after P01; P11 `-Hooks Index` (the `.ps1` installs, the module exits 2);
  P12 `-Hooks` at the end; P13 `-DeclineRefGuard` then a plain run (skip);
  P14 declined plus a foreign reference-transaction hook; P15 a directory at
  the pre-push slot; P16 `-ArmRefGuard` on a CRLF config with a doubled key;
  P17 not a repository; P18 `-h`; P19 `--bogus`; P20 `-Uninstall
  -DeclineRefGuard`.

After every case the case's scratch root holds no entry besides its
fixtures, the logs and the marker, and no run's resolved hooks path lies
outside the case directory (checked with `git rev-parse --git-path` before
the run).

### D-PARITY. The parity harness takes the module as a third twin on hooks

Changes to `tests/skills/lib/install-parity.mjs`:

- `ctx.hkref`: built once per run when a selected scenario has op `hooks`,
  by `materializeHookInstallerReference(REPO_ROOT, <root>/hkref)`; passed to
  every twin's argv ctx (like `bsref` and `upref`).
- sh twin, hooks: `bash <hkref>/.aai/scripts/install-pre-commit-hook.sh
  <sh flags>` with cwd the target (the frozen bash reference, forward-slash
  path). ps1 twin, hooks: `<ps> ...psHead <hkref>/.aai/scripts/install-pre-commit-hook.ps1
  <ps flags>` (the frozen PowerShell reference, so sh:ps1 keeps comparing
  the two old twins natively on Windows 5.1 and 7). node twin: `ops:
  ['bootstrap', 'update', 'hooks']`, `peers` unchanged (update only), hooks
  argv the exact line
  `      if (step.op === 'hooks') return { file: process.execPath, args: [path.join(ctx.target, '.aai', 'scripts', 'install-pre-commit-hook.mjs'), ...(step.flags || []).map((f) => SH_FLAG[f])], cwd: ctx.target };`
  (the module the target's sync vendored, so PROFILES core must list it).
  Hook scenarios compare all three pairs.
- Allowlist: no new row; `hk-uninstall-removes-hooks` widens its pairs to
  `sh:sh,ps1:ps1,node:node` with the reviewed reason appended "the module
  twin's uninstall step removes what its install step wrote, as the twins
  do". A divergence a hosted run shows gets a row and a follow-up in a
  remediation pass, never a normalization (SPEC-0284 D-ALLOW).
- No scenario, tier or normalization changes.

### D-LAUNCH. Launchers

- `.aai/scripts/install-pre-commit-hook.sh`: at most 20 lines, ASCII,
  `#!/bin/sh`, POSIX only (sh, dash, bash), mode 100755:

  ```sh
  #!/bin/sh
  # AAI git hook installer launcher; mode, policy, slot and write rules live in install-pre-commit-hook.mjs (RFC-0017 phase 5).
  # Usage: bash .aai/scripts/install-pre-commit-hook.sh [--force] [--uninstall] [--print [kind]] [--hooks <csv>] [--decline-ref-guard] [--arm-ref-guard] [-h]
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/install-pre-commit-hook.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    exec node "$MODULE" "$@"
  fi
  echo "install-pre-commit-hook: refused - node not found in PATH or install-pre-commit-hook.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
  exit 1
  ```

- `.aai/scripts/install-pre-commit-hook.ps1`: at most 20 lines, ASCII, no
  param block, 5.1 and 7 compatible; it sets `$ErrorActionPreference =
  'Continue'` and `$PSNativeCommandUseErrorActionPreference = $false` in its
  own scope, runs `node <PSScriptRoot>/install-pre-commit-hook.mjs` with the
  marshalled arguments and `exit $LASTEXITCODE`; without node or the module
  it writes `install-pre-commit-hook: refused - node not found in PATH or install-pre-commit-hook.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.`
  with `[Console]::Error.WriteLine` and exits 1. Argument marshalling, the
  only logic it holds (it names no flag): each element of `$args` in order;
  an array element becomes one argument joined with `,` (so an in-session
  `-Hooks index,ref-guard` stays one csv value); a token matching
  `^-[A-Za-z][A-Za-z0-9-]*:$` loses its colon; a `Boolean` element is not
  passed, and when it is `$false` the token before it is dropped too (so
  `-Force:$false` means no `-Force`, in session and under `-File`); every
  other element is passed as its string.
- Neither launcher names git, `rev-parse`, `ref_guard`, `AAI:`, `docs-audit`,
  a template, `exit 2`, or any flag outside its two comment lines.
- A consumer whose layer still has the twins gets the launchers and the
  module in the same sync (both PROFILES core); `/aai-update` runs the
  installer only after its update script exited 0, so the new launcher
  always finds the module (TEST-3996 proves the order).

### D-PESTER. `tests/skills/install-pre-commit-hook.Tests.ps1`

- `Copy-Installers` also copies `install-pre-commit-hook.mjs` and
  `lib/guard-config.mjs` (run 5, so the existing seven cases keep passing
  through both launchers).
- A new `Context 'launcher (pre-commit-installer-on-node)'`, Pester 5,
  5.1-compatible syntax, never skips, launching with the running engine
  through `ProcessStartInfo` with an explicit PATH, scratch only under
  `$TestDrive`, git with `GIT_CONFIG_NOSYSTEM=1` and an empty
  `GIT_CONFIG_GLOBAL`:
  1. Pass-through under `-File`: the launcher copied beside a stub module
     that writes its argv as JSON and exits 7; `-Hooks "index,ref-guard"
     --print pre-push -Force -Uninstall` arrive in that order unchanged,
     exit 7.
  2. In-session marshalling: one child engine runs `& <copied launcher>
     -Hooks index,ref-guard -Force:$false -Uninstall -Hooks:close-gate`; the
     stub records `-Hooks`, `index,ref-guard`, `-Uninstall`, `-Hooks`,
     `close-gate`.
  3. Refusal: PATH an empty `$TestDrive` directory; exit 1, stdout empty,
     stderr exactly the D-LAUNCH line, the repository unchanged.
  4. Module missing: the launcher copied alone; the same refusal.
  5. Real run: a `$TestDrive` repository with the vendored installers, the
     launcher with `-Hooks index,close-gate` (in session) exits 0 and writes
     pre-commit and pre-push only; `-Hooks bogus` exits 2.
- It runs in the existing jobs through directory discovery (Linux `gate`,
  `windows-5_1` with both engines, `windows-wsl1`); no job, step or
  exclusion is added; the TotalCount floor 111 and
  `AAI_EXPECTED_WIN_SKIP_COUNT` 4 stay. Budget: at most 30 s per engine on
  a hosted runner.

### D-INSTALL. A scratch aai-sync install runs both launchers, and the /aai-update order

TEST-3996:
1. `bash .aai/scripts/aai-sync.sh <scratch>/target --profile core` from this
   checkout into a fresh `git init` target; the module, both launchers,
   `lib/guard-config.mjs` and the four templates exist in the target.
2. On three fresh copies of the synced target (same absolute path, one after
   another), `bash .aai/scripts/install-pre-commit-hook.sh`, `sh` of the
   same, and `<pwsh> -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1`
   each exit 0, and the three hooks are byte-equal across the copies.
3. With PATH a scratch directory holding only `dirname`, `sh
   .aai/scripts/install-pre-commit-hook.sh` exits 1 with the D-LAUNCH line
   and no hook is written.
4. The /aai-update order: a scratch target whose `.aai/scripts/` holds the
   frozen bash reference installer and no module (an older layer); `bash
   .aai/scripts/aai-update.sh --repo <scratch source> --force` (the source a
   committed scratch copy of this checkout's tracked files, never this
   checkout) exits 0; then the SKILL_UPDATE step 4 command `bash
   .aai/scripts/install-pre-commit-hook.sh` exits 0 with the three hooks
   attested, proving the sync vendored the module before the new launcher
   ran.
pwsh through `need_tool`; every installer run with the D-SAFETY git
environment.

### D-SAFETY. Scratch only, no daemon, delete only what the run made

- Hooks are installed only into repositories the test created under its own
  scratch root. Every installer run in the new suite, the node:test file,
  the corpora and the Pester launcher context sets `GIT_CONFIG_NOSYSTEM=1`
  and `GIT_CONFIG_GLOBAL` to an empty scratch file, and the new suite and
  the node:test file assert before each run that `git rev-parse --git-path
  hooks/pre-commit` from the run's cwd resolves under the run's own scratch
  root; this checkout is never a target, a source or a cwd of an installer
  run.
- No container daemon: no test or mutation calls `docker`, `pkill`,
  `killall` or a kill by pattern; children are synchronous; the suites run
  under `aai-run-tests.sh`, whose isolation points `DOCKER_HOST` at a
  nonexistent socket.
- Deletion: the module deletes only its own temp files and, in uninstall
  and decline, a marker-owned hook (D-WRITE). Test scratch is removed through
  `removeOwnScratch` (prefix `aai-hk-`, marker `.aai-hk-owned`) or the new
  suite's `safe_rm_own` (prefix `aai-hook-installer-node.`), each refusing an
  empty path, a relative path, a foreign prefix, a path outside the temp
  directory, a symbolic link and an unmarked directory, re-reading the
  marker right before removing, and treating an empty list as a failure;
  the suite removes its scratch from an EXIT trap, so a failing case leaves
  nothing behind. Pester uses `$TestDrive`.

### D-REHOME. Existing tests that read the old twins, and their amendments

Each named change gets one unsigned amendment record (`node
.aai/scripts/spec-amend.mjs add --spec <spec> --ref
pre-commit-installer-on-node --class contract --signoff none --what
"<what>" --why "<one line>"`; the owner's merge direction signs them). The
property each removed text pin stood for keeps a behaviour test; nothing is
dropped without one. Re-homed functions keep their names and test ids (the
selectors of TEST-3992 and TEST-3994 name them).

- Run 5, with the `.sh` swap:
  - `tests/skills/lib/vendor-hook-installer.sh` and the Pester
    `Copy-Installers` also copy the module and `lib/guard-config.mjs` for
    every `<sh|ps1|both>` choice (`check-vendored-script-deps.mjs` exits 0).
    The helper holds, once each and outside its `case` blocks, the exact
    lines `  cp "$src/.aai/scripts/install-pre-commit-hook.mjs" "$root/.aai/scripts/"`
    and `  cp "$src/.aai/scripts/lib/guard-config.mjs" "$root/.aai/scripts/lib/"`
    (after a `mkdir -p` of `$root/.aai/scripts/lib`; TEST-3992's mutation
    relies on the first).
  - `test-aai-git-ref-guard.sh` TEST-314: the `grep -- '--print'` pin on the
    `.sh` is dropped; its behaviour half stays. Record for SPEC-0156, what
    begins `TEST-314 re-homed`.
  - `test-aai-hygiene-pack.sh` test_618 (SPEC-0184 TEST-618): the shell
    grep it extracted is gone; the eleven variants plus a BOM variant now go
    through `readRefGuardPolicy` and through a plain module install in a
    scratch repository, which skips the ref-guard exactly when the reader
    says `declined`; the module holds no `ref_guard` pattern of its own.
    Record for SPEC-0184, what begins `TEST-618 re-homed`.
  - `test-aai-docs-audit.sh` TEST-013 (SPEC-0011) and TEST-008 (SPEC-0013):
    "the installers read pre-commit-index.sh" reads the module instead of
    the two twins. Records for SPEC-0011 and SPEC-0013, what begins
    `TEST-013 re-homed` and `TEST-008 re-homed`.
- Run 6, with the `.ps1` swap (each removed `.ps1` text pin is replaced by a
  behaviour arm through the `.ps1` launcher under pwsh, or on the module
  under node when the property is engine-independent):
  - `test-aai-git-ref-guard.sh`: TEST-309 (the launcher under pwsh writes the
    reference-transaction hook into a `core.hooksPath` directory from a
    subdirectory cwd), TEST-608 (`-Hooks index` writes pre-commit only,
    `-Hooks bogus` exits 2 and writes nothing), TEST-631
    (`-DeclineRefGuard` and `-ArmRefGuard` exit 0, both together exit 2),
    TEST-632 (the module imports `readRefGuardPolicy` and holds no
    `ref_guard` regex; the reader's fail-closed cases), TEST-633 (the
    foreign reference-transaction sentence occurs once in the module),
    TEST-637 (a declined config and a plain launcher run skip the guard),
    TEST-641 (the stray-value correction on the module under node, plus the
    launcher when pwsh is present: closes `fu-test641-passes-without-pwsh`),
    TEST-642 (decline with an unwritable config directory exits 1 and keeps
    the hook, on the module, POSIX non-root), TEST-644 (decline on an absent
    config seeds from the template and prints SEED, or prints NOTE without
    it, on the module), TEST-646 and TEST-647 (their behaviour arms stay,
    their text pins go). Record for SPEC-0184, what begins `TEST-608 to
    TEST-647 re-homed`; record for SPEC-0156, what begins `TEST-309
    re-homed`.
  - `test-aai-hygiene-pack.sh` test_813 (`-Hooks close-gate` writes pre-push
    only; `-Hooks bogus` names the closed set with close-gate; the module
    names the four template files) and test_818 (its three text pins go, its
    behaviour arms stay). Record for SPEC-0201, what begins `TEST-813 and
    TEST-818 re-homed`.
  - `tests/skills/install-pre-commit-hook.Tests.ps1`: the D-PESTER context;
    the seven existing cases unchanged. Record for SPEC-0278, what begins
    `install-pre-commit-hook.Tests.ps1 vendors the module`.
  - `install-parity.mjs`, `install-parity.test.mjs` and the allowlist
    (SPEC-0284 D-SEAM): D-PARITY; the real-registry unit test's hook argv
    assertions follow (sh `[<hkref>/.aai/scripts/install-pre-commit-hook.sh,
    --force, --uninstall, --decline-ref-guard]`, ps1 `[..., -File,
    <hkref>/.aai/scripts/install-pre-commit-hook.ps1, -Force, -Uninstall,
    -DeclineRefGuard]`, node as D-PARITY). Record for SPEC-0284, what begins
    `D-SEAM hook twins run the frozen references`.
  - `tests/skills/lib/aai-bootstrap.test.mjs` TEST-3956 (SPEC-0306): the node
    twin's operations become `['bootstrap', 'update', 'hooks']`. Record for
    SPEC-0306, what begins `TEST-3956 node twin operations`.
- Unchanged and passing (checked in the sweep): `test-aai-git-ref-guard.sh`
  TEST-308 (its pre-commit sha256 baseline holds: the module writes the same
  bytes), TEST-316, TEST-621 (D-DOCS keeps its tokens), TEST-634 (a CRLF
  config still reads back with one key line), TEST-635 (a read-only config
  still refuses the decline and keeps the guard), and every other case;
  `test-aai-hygiene-pack.sh` TEST-814 (the help keeps its tokens, DR-1);
  `test-aai-git-hook-templates.sh` (TEST-3432, 3437, 3438, 3440, 3442, 3444);
  `test-aai-doctor.sh`; `test-aai-pre-commit-checks.sh`;
  `test-aai-tracked-ignored.sh`; `test-aai-release.sh`;
  `test-aai-install-parity.sh`; `install-parity.Tests.ps1`;
  `test-aai-win-fallback.sh`; `test-ps1-quality.sh`.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-hook-installer-node` with globs
  `.aai/scripts/install-pre-commit-hook.*`, `.aai/scripts/lib/guard-config.mjs`,
  `.aai/templates/git-hooks/**`, `.aai/templates/docs-audit.template.yaml`,
  `.aai/system/PROFILES.yaml`, `.aai/scripts/aai-sync.sh`,
  `.aai/scripts/aai-update.*`, `tests/fixtures/hook-installer-reference/**`,
  `tests/skills/test-aai-hook-installer-node.sh`,
  `tests/skills/lib/install-pre-commit-hook.test.mjs`,
  `tests/skills/lib/install-pre-commit-hook-fixtures.mjs`,
  `tests/skills/lib/hook-installer-reference.mjs`,
  `tests/skills/lib/install-parity.mjs`,
  `tests/skills/lib/install-parity-allowlist.tsv`,
  `tests/skills/lib/install-parity.test.mjs`,
  `tests/skills/lib/vendor-hook-installer.sh`,
  `tests/skills/install-pre-commit-hook.Tests.ps1`,
  `tests/skills/lib/pester-native-capture.ps1`, and every other
  `tests/skills/lib/*` file the suite sources or reads. New row
  `aai-hook-installer-docs` with `CHANGELOG.md`, `.aai/SKILL_UPDATE.prompt.md`,
  `docs/USER_GUIDE.md`, `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-hook-installer-docs.sh` and the suites it runs by
  selector. Every existing row that lists `.aai/scripts/install-pre-commit-hook.sh`
  or `.ps1` (`aai-docs-audit`, `aai-git-ref-guard`, `aai-hygiene-pack`,
  `aai-install-parity`) gains `.aai/scripts/install-pre-commit-hook.mjs`;
  `aai-install-parity` also gains `tests/fixtures/hook-installer-reference/**`
  and `tests/skills/lib/hook-installer-reference.mjs`; the rows of the
  suites that run the installer through `vendor-hook-installer.sh`
  (`aai-doctor`, `aai-pre-commit-checks`, `aai-tracked-ignored`) gain
  `.aai/scripts/install-pre-commit-hook.mjs`; hygiene TEST-815 keeps
  passing.
- Shared-lib note (run 7): `.aai/scripts/lib/guard-config.mjs` sits under the
  `.aai/scripts/lib/**` shared-lib glob, so a change to it is a FULL_RUN, which
  runs this suite; TEST-3997 checks that escalation for guard-config and the
  routing to `aai-hook-installer-node` for every other listed file.
- `tests/skills/suite-weights.tsv`: the fallback lines
  `# sample aai-hook-installer-node fallback unsampled (new suite of pre-commit-installer-on-node; no successful observation)`
  with `aai-hook-installer-node<TAB>196`, and the same for
  `aai-hook-installer-docs` (`split from aai-hook-installer-node by
  pre-commit-installer-on-node`).
- `test-aai-hygiene-pack.sh` test_090: the row-count pin moves 140 to 142
  (a parallel ride that adds a suite moves it again; the branch merging
  second rebases the pin); test_129 passes.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record`;
  `.aai/scripts/install-pre-commit-hook.sh` stays 1 (the launcher's one
  `$(CDPATH= cd ...)`), `tests/skills/lib/vendor-hook-installer.sh` stays 1,
  the new suites hold no `cd` inside a command substitution.
- Nested-suite lint: no new allowlist row (other suites only in selector
  form). `check-test-registration.mjs` and `check-vendored-script-deps.mjs`
  exit 0. Hygiene test_128's pipefail floor (at least 3) still holds (four
  shipping scripts keep pipefail).
- `.aai/system/PROFILES.yaml` core: `.aai/scripts/install-pre-commit-hook.mjs`
  beside the two launchers (run 5; companion obligation for a new `.aai/**`
  file).
- `.github/workflows/ps1-quality.yml`: both `push` and `pull_request` path
  lists (identical) gain `.aai/scripts/install-pre-commit-hook.mjs`,
  `.aai/scripts/lib/guard-config.mjs`,
  `tests/fixtures/hook-installer-reference/**` and
  `tests/skills/lib/hook-installer-reference.mjs`; win-fallback test_034
  and test_035 pass (a `ps1f_derive` hop only if the derivation misses the
  new helper, as ride 10 added one). No job or step changes; the Windows
  CAT-17 step keeps running `bash .aai/scripts/install-pre-commit-hook.sh
  --arm-ref-guard`, now through the launcher (hosted check H3).
- Prompt corpus companion: `SKILL_UPDATE.prompt.md` grows (D-DOCS), so
  `tests/skills/lib/prompt-diet-ledger.sh` gains one JUSTIFIED_ADDITIONS
  entry stating `SKILL_UPDATE.prompt.md <before> -> <after>` measured with
  `/usr/bin/wc -c` against `bf0148d6`, and the same number moves the
  TEST-012 `want_growth` pin in `test-aai-prompt-diet.sh` and the growth sums
  in `test-aai-pr-preflight.sh` and `test-aai-suite-reuse.sh` (as rides 9 and
  10 did). The file never shrinks below 3600 bytes (TEST-622's floor).
- Left as is, checked: `aai-doctor.mjs` (remedy text and the `.sh`
  existence check stay true), the hook templates (their prose and the
  uninstall lines name both launchers, which still exist),
  `validate-skills.mjs`, `docs/TECHNOLOGY.md`,
  `PSScriptAnalyzerSettings.psd1`.

### D-DOCS. Documentation and release note

- CHANGELOG.md: one new heading
  `## [unreleased] — feat: the git hook installer runs on Node behind sh and ps1 launchers`
  whose body says that installing the AAI git hooks (and so step 4 of
  `/aai-update`) now requires Node.js 22 or later (both launchers refuse
  without it, exit 1, change nothing), that the hooks written are byte for
  byte the same, and names DR-4, DR-6, DR-11, DR-12, DR-15, DR-16 and
  DR-17 in one sentence each; ends with "Re-run `/aai-update` to pick up
  the new launchers and module."
- `.aai/SKILL_UPDATE.prompt.md` step 4 (closing
  `fu-skill-update-step4-both-hooks`): the command block unchanged; the
  paragraph after it becomes exactly these lines (3 spaces of indent as
  today), the two report bullets after "Therefore:" keep their shape with
  the first bullet's hook list updated:

  ```
     Both launchers run .aai/scripts/install-pre-commit-hook.mjs and need Node.js 22 or later.
     It installs THREE hooks into the directory git resolves: the docs-index
     pre-commit hook (AAI:INDEX-AUTOGEN), a reference-transaction hook
     (AAI:REF-GUARD) that refuses any refs/heads/main update in this
     repository unless AAI_GIT_WRITE=1 is set on that command, and a pre-push
     hook (AAI:CLOSE-GATE). A recorded `ref_guard: declined` in
     docs/ai/docs-audit.yaml is honoured: the ref-guard is skipped, not
     re-armed. The installer is idempotent per hook, checks every slot before
     writing any, and WITHOUT `--force` refuses to overwrite a foreign hook
     in any slot, so a refusal installs nothing. Therefore:
     - installed / already present → report one line naming the hooks: "AAI
       git hooks installed (docs-index pre-commit, AAI:REF-GUARD reference-
       transaction, AAI:CLOSE-GATE pre-push). Decline the ref-guard:
       install-pre-commit-hook.sh --decline-ref-guard."
  ```
  Nothing else in the prompt changes; TEST-621's tokens all remain.
- `docs/USER_GUIDE.md`: the install block's Windows line and the "(or the
  `.ps1` twin)" sentence say both files are launchers of one Node module
  that needs Node.js 22 or later; one added sentence: `--uninstall` of the
  ref-guard is undone by the next plain install unless the guard is
  declined.
- RFC-0017 phase 5 row: one sentence after the fifteenth-slice sentence and
  before the remaining-scripts-plan sentence:
  `The sixteenth slice [moved the git hook installer to Node](../issues/CHANGE-DRAFT-pre-commit-installer-on-node.md): one module holds the mode, policy, slot and write rules behind thin install-pre-commit-hook.sh and install-pre-commit-hook.ps1 launchers, compared with frozen copies of both twins, and the ref_guard policy is read and written only through guard-config.`
  Status stays `in progress`; the allocator rewrites the link at merge
  (checks match only the suffix `pre-commit-installer-on-node.md`). The
  remaining-pairs inventory loses its `install-pre-commit-hook` row (the
  pair now has an `.mjs`; expert-fetch test_2624 counts only pairs without
  one).
- `docs/product/pre-commit-installer-on-node.md` is written by the close
  ceremony after the loop completes, not by Implementation.

### D-FU. Follow-ups

Closed by Implementation in run 7 with `node .aai/scripts/follow-ups.mjs
close --id <id> --resolved-by pre-commit-installer-on-node --source "<test
file> <TEST id> (<DR or D- id>)"`, each source naming a test id that exists
in the named file:

| Follow-up | Resolved by | Evidence |
|---|---|---|
| fu-installer-flag-lattice-no-mode | DR-4, DR-5, D-CLI | TEST-3982, K20, K21 |
| fu-three-readers-three-whitespaces | DR-16, D-POLICY | TEST-3983, K27 |
| fu-installer-want-refguard-overloaded | DR-11, D-CLI selected vs planned | TEST-3987, K23 |
| fu-ps1-writeerror-terminates-before-exit | DR-9 (no PowerShell logic left) | TEST-3987, P03 |
| fu-ps1-symlink-config-replaced | DR-15 | TEST-3983, K25 |
| fu-ps1-decline-not-disclosed | DR-10 | TEST-3984, P13 |
| fu-ps1-refusal-no-manual-merge | DR-10 | TEST-3984 |
| fu-ps1-decline-force-advice-wrong | DR-10 (rewritten re-arm line) | TEST-3984, K16 |
| fu-ps1-enable-refguard-no-rationale | D-WRITE arm (one path, rationale once) | TEST-3981 |
| fu-ps1-setcontent-rewrites-seed-eol | DR-15 | TEST-3983, K26 |
| fu-hook-tmpl-final-lf-parity | DR-19 | TEST-3985 |
| fu-hook-installer-not-a-repo-msg | DR-8 | TEST-3986, P17 |
| fu-uninstall-refguard-leaves-armed | DR-18 | TEST-3984, K13 |
| fu-doubled-key-has-no-repair | DR-17 | TEST-3983, K27 |
| fu-ac05-counts-a-valueless-key | DR-17 (a value-less key line is the key) | TEST-3983 |
| fu-test618-positional-pattern | D-REHOME test_618 | TEST-3992 |
| fu-test641-passes-without-pwsh | D-REHOME TEST-641 | TEST-3994 |
| fu-skill-update-step4-both-hooks | D-DOCS | TEST-3998 |

Suggested at planning, filed by Implementation with `follow-ups.mjs add
--ref pre-commit-installer-on-node --severity P3` (ids at most 40
characters): `fu-installer-not-in-l3-protected-paths` (the installer writes
the guards but is not a protected L3 surface; owner decision),
`fu-guard-dials-ignore-bom` (`readGuardConfig`'s dials still read a
BOM-prefixed first line as no key, with the shell mirror in the L3
`pre-commit-checks.sh`), `fu-update-ps1-colon-switch-args` (the
`aai-update.ps1` launcher passes `-DryRun:$false` and in-session arrays as
measured above: `False` and two arguments), `fu-hook-upgrade-resets-mode` (an
upgraded hook takes 0777 minus umask). Every further divergence a hosted run
shows gets one.

### D-SLICES. Runs and the fallback

- Run 1, Spec-AC-01 to 03: frozen references and their helper, the suite
  skeleton (`safe_rm_own`, `run_node_tests`, `need_tool`), the node:test
  file, module shape, arguments, help and mode resolution; the suite-map,
  weights and test_090 rows land with the suite.
- Run 2, Spec-AC-04 to 06: the guard-config writer and the reader's BOM rule,
  the policy flows (decline, arm, plain skip, uninstall disclosure),
  templates, `--print` and composition.
- Run 3, Spec-AC-07 to 09: path resolution, slot attestation and the
  whole-run refusal, writes, upgrade, landing and post-run attestation.
- Run 4, Spec-AC-10 and 11: both corpora. Fallback ship point: the module
  present but unreachable (launchers unchanged, the module not in PROFILES),
  the guard-config writer used by nothing but the module, the new suite
  running TEST-3980 to TEST-3990, no CHANGELOG entry (the PR body carries
  `no-notes: Node hook installer module added but not yet reachable from any
  launcher`), and Spec-AC-12 to 20 moved to the next ride's spec by a
  recorded amendment.
- Run 5, Spec-AC-12 and 13: the `.sh` launcher swap, PROFILES core, the
  vendoring helpers, the bash-side re-homes and their records, so no suite
  is red between runs.
- Run 6, Spec-AC-14 to 16: the `.ps1` launcher with the Pester context, the
  `.ps1`-side re-homes and records, the parity harness's third twin.
- Run 7, Spec-AC-17 to 20: scratch install and the update order, the rest
  of D-WIRE, D-DOCS with the prompt-diet ledger, D-FU; then the full sweep
  once.

## Acceptance Criteria Mapping

- Intake AC-001 (one resolved mode, contradictions refused) maps to
  Spec-AC-03 (and Spec-AC-10, 11 for the fixture-level equivalence).
- Intake AC-002 (the policy through guard-config) maps to Spec-AC-04 and
  Spec-AC-05. Refinement, disclosed: the intake says a doubled key "is
  refused with a repair hint"; this spec makes the explicit arm and decline
  commands the repair (DR-17, what `fu-doubled-key-has-no-repair` asks for)
  and a plain run warns with the repair command and writes nothing.
- Intake AC-003 (slot attestation and upgrade) maps to Spec-AC-07 to
  Spec-AC-09.
- Intake AC-004 (the parity third twin) maps to Spec-AC-16 and hosted check
  H2.
- Intake AC-005 (launchers, Pester, scratch install) maps to Spec-AC-12,
  Spec-AC-14, Spec-AC-17 and hosted checks H1 and H3.
- Intake AC-006 (pins migrated, suites pass, follow-ups, wiring, CHANGELOG)
  maps to Spec-AC-13, Spec-AC-15, Spec-AC-18, Spec-AC-19 and Spec-AC-20;
  the unchanged suites in D-REHOME pass in the Verification sweep.
- Owner safety rules (scratch repositories only, no daemon, delete only
  what the run made, cleanup on failure) map to Spec-AC-01 and D-SAFETY in
  every new test.

## Constitution deviations

None. Article 1: every rule is seen failing first and the corpora compare
real runs of both frozen twins. Article 2: one module, two launchers of at
most 20 lines, one shared writer beside the existing reader, no dependency.
Article 4: without Node both launchers refuse with one named line and change
nothing; every refusal names its slot and leaves the tree as it was.
Article 5: installing the git hooks now requires Node.js 22 or later; this
is the owner's recorded decision (plan section 4, decision 1), stated in the
CHANGELOG entry; both launchers keep their paths, the argument forms they
accepted (minus the PowerShell abbreviations and common parameters, DR-3),
the bytes of every hook they write and the exit codes 0 and 1, with every
usage error now exit 2.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a test of this ride removes a scratch path the system SHALL refuse (throw or fail the test) an empty path, a relative path, a basename without the own prefix, a path outside the temp directory, a symbolic link, a directory without the .aai-hk-owned marker and an empty removal list; both frozen copies under tests/fixtures/hook-installer-reference SHALL hash to the D-REF sha256 values and, where git history holds bf0148d6, equal the twins at that commit; the new test files SHALL hold no docker, pkill or killall call, and every installer invocation helper in them SHALL set GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL and assert that the resolved hooks path lies under the run's own scratch root. | done | TEST-3980 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3980.log; TEST-3980 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3980.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3980.txt | — | D-SAFETY, D-REF |
| Spec-AC-02 | .aai/scripts/install-pre-commit-hook.mjs SHALL import only node: specifiers and ./lib/guard-config.mjs and none of http, https, net, tls or dgram, create no file and print nothing when imported, export the D-MODULE names, hold each D-MODULE anchor line exactly once, call spawnSync exactly once (inside runChild), never reference process.stdout or process.stderr, contain no line of 40 or more characters of any hook template, hold the D4 arm rationale comment once, and be ASCII only. | done | TEST-3981 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3981.log; TEST-3981 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3981.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3981.txt | — | D-MODULE |
| Spec-AC-03 | WHEN the module is run with arguments the system SHALL follow D-CLI: the long flags and the five exact PowerShell names in any case in any order, the last --hooks and --print kind winning, help per DR-1 on stdout with exit 0, an unknown argument, an abbreviation or a common parameter per DR-2 and DR-3 with exit 2, a missing --hooks value per DR-7 with exit 2, two mode flags per DR-4, a modifier without effect per DR-5 and an empty, untrimmed-unknown or wrong-case --hooks token per DR-6 each with exit 2, one stderr line and no git child started; resolveBase SHALL use PWD only when it names the same device and inode as the working directory. | done | TEST-3982 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3982.log; TEST-3982 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3982.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3982.txt | — | D-CLI, DR-1 to DR-7, DR-20 |
| Spec-AC-04 | WHEN writeRefGuardPolicy runs the system SHALL seed an absent file from seedFrom or start it empty, write a symbolic link's target and keep the link, refuse a dangling link with nothing written, keep the file's permission bits, each untouched line's terminator, the replaced line's own terminator and a leading BOM, replace the first column-0 ref_guard: line (valued or not) and remove every later one reporting their line numbers, append with the file's terminator when no key line exists, write nothing when the result is unchanged, refuse a target it cannot write with nothing written, leave no temp file, and throw on a read-back mismatch; readRefGuardPolicy SHALL read a BOM-prefixed first-line declined as declined and keep every other existing verdict, and aai-doctor CAT-17 on that file SHALL report DECLINED. | done | TEST-3983 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3983.log; TEST-3983 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3983.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3983.txt | — | D-POLICY, DR-15, DR-16, DR-17 |
| Spec-AC-05 | WHEN the module runs the policy flows the system SHALL skip the ref-guard on a plain install exactly when readRefGuardPolicy says declined and --force is absent, printing the Skipped line and the DR-10 re-arm line; decline SHALL refuse a foreign hook unmodified, write the declaration before removing an AAI hook and exit 1 keeping the hook when the config cannot be written (a read-only file or directory); arm SHALL record armed after the attested hook; uninstall of the ref-guard SHALL print the two DR-18 lines when the policy reads armed; a plain run on a file with more than one key line SHALL print the DR-17 warning and write nothing; and every policy read SHALL go through readRefGuardPolicy with the module holding no ref_guard pattern. | done | TEST-3984 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3984.log; TEST-3984 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3984.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3984.txt | — | D-POLICY, D-WRITE, DR-10, DR-17, DR-18 |
| Spec-AC-06 | WHEN templates are loaded the system SHALL read them from the module's own ../templates/git-hooks with every CR removed, name every missing template the run needs with exit 1 before any write, refuse a malformed index or guard-checks template per D-TEMPLATE, print each --print kind's bytes with exit 0 outside a repository, and compose a fresh pre-commit hook as the index first line, the guard block and the index rest ending with an LF; the composed hooks SHALL be byte-equal to those the bash reference writes for the shipped templates. | done | TEST-3985 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3985.log; TEST-3985 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3985.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3985.txt | — | D-TEMPLATE, DR-19 |
| Spec-AC-07 | WHEN slot paths are resolved the system SHALL ask git rev-parse --git-path hooks/<name> for each slot and resolve a relative answer against the base directory, so that a relative, absolute and not yet existing core.hooksPath, a linked worktree and a subdirectory cwd each place the hooks where git runs them; outside a repository it SHALL print the bash not-a-repository line with exit 1, and with git unable to start the DR-8 line with exit 1. | done | TEST-3986 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3986.log; TEST-3986 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3986.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3986.txt | — | D-SLOT, DR-8, DR-20 |
| Spec-AC-08 | WHEN an install plans its slots the system SHALL classify every planned slot before any write into the D-SLOT states, leave a declined unforced reference-transaction slot unclassified and unwritten, decide ownership on bytes per DR-21, and on any refusal (foreign without --force, unprovable, a link whose target would need a write, a directory, a dangling link, a pipe or a socket in any of the three slots) print every refusal in slot order on stderr with exit 1 and leave the case tree byte-identical, with no hook, temp file, hooks directory or policy line created. | done | TEST-3987 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3987.log; TEST-3987 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3987.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3987.txt | — | D-SLOT, DR-9, DR-11, DR-12, DR-21 |
| Spec-AC-09 | WHEN a slot is written the system SHALL write a temp sibling, rename it through io.rename and fail with the bash landing line and exit 1, removing the temp and any stray, when the slot does not then hold exactly the composed bytes as a regular file; it SHALL upgrade an older AAI pre-commit hook by insertion or interior refresh keeping every other byte, leave a current one byte-identical, leave a marked-differs reference-transaction or pre-push hook unwritten with the DR-14 NOTE unless --force, create new hooks with mode 0777 minus umask, attest every planned slot after the run with the bash lines, and skip the executable checks when platform is win32. | done | TEST-3988 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3988.log; TEST-3988 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3988.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3988.txt | — | D-WRITE, DR-13, DR-14, DR-22 |
| Spec-AC-10 | WHEN the D-CORPUS bash-side cases run the system SHALL give exit code, stdout, stderr, the case snapshot and the TMPDIR listing byte-equal between the frozen bash reference and the module after only the registered rewrites, each registered rewrite changing at least one byte, and the asserted divergences SHALL hold. | done | TEST-3989 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3989.log; TEST-3989 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3989.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3989.txt | — | D-CORPUS bash side |
| Spec-AC-11 | WHEN the D-CORPUS PowerShell-side cases run with pwsh the system SHALL give exit code and the case snapshot equal between the frozen PowerShell reference and the module on the same PowerShell-form arguments, and the asserted divergences SHALL hold. | done | TEST-3990 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3990.log; TEST-3990 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3990.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3990.txt | — | D-CORPUS PowerShell side |
| Spec-AC-12 | .aai/scripts/install-pre-commit-hook.sh SHALL be the D-LAUNCH text (at most 20 lines, ASCII, mode 100755, no policy token), and WHEN run by bash, sh and dash beside a stub module it SHALL pass every argument and the exit code through; WHEN node is not on PATH or the module is missing it SHALL exit 1 with the D-LAUNCH line on stderr and leave the repository unchanged. | done | TEST-3991 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3991.log; TEST-3991 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3991.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3991.txt | — | D-LAUNCH |
| Spec-AC-13 | WHEN the bash-side re-homed selectors run after the .sh swap (test-aai-git-ref-guard.sh test_314, test-aai-hygiene-pack.sh test_618, test-aai-docs-audit.sh test_spec0011_hook_parity_grep and test_change0007_hook_body_lint, and one vendored run per suite that calls vendor_hook_installer) each SHALL exit 0, check-vendored-script-deps SHALL exit 0, PROFILES core SHALL list the module, and spec-amend list SHALL hold one contract record of ref pre-commit-installer-on-node for each of SPEC-0156, SPEC-0011 and SPEC-0013 and the first one for SPEC-0184 whose what begins with the D-REHOME text. | done | TEST-3992 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3992.log; TEST-3992 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3992.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3992.txt | — | D-REHOME run 5 |
| Spec-AC-14 | .aai/scripts/install-pre-commit-hook.ps1 SHALL be the D-LAUNCH text (at most 20 lines, ASCII, no param block, no policy token); the launcher context of tests/skills/install-pre-commit-hook.Tests.ps1 run with Invoke-Pester under pwsh 7 SHALL pass the five D-PESTER cases with 0 skipped, 0 failed and 0 failed containers. | done | TEST-3993 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3993.log; TEST-3993 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3993.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3993.txt | — | D-PESTER; H1 for 5.1 and 7 on Windows |
| Spec-AC-15 | WHEN the PowerShell-side re-homed selectors run after the .ps1 swap (test-aai-git-ref-guard.sh test_309, test_608, test_631 to test_633, test_637, test_641, test_642, test_644, test_646, test_647, test-aai-hygiene-pack.sh test_813 and test_818) each SHALL exit 0 with no assertion reading the .ps1's text, the whole tests/skills/install-pre-commit-hook.Tests.ps1 SHALL pass under pwsh 7 with 0 failed and 0 skipped, and spec-amend list SHALL hold the second SPEC-0184 record and one record each for SPEC-0201 and SPEC-0278 and the second for SPEC-0156. | done | TEST-3994 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3994.log; TEST-3994 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3994.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3994.txt | — | D-REHOME run 6 |
| Spec-AC-16 | WHEN the parity driver runs the ten HK scenarios with twins sh, ps1 and node against the committed allowlist the system SHALL exit 0 with verdict PASS, pairs sh:ps1, sh:node and ps1:node in each hook scenario, the sh and ps1 twins running the frozen references from hkref, no new allowlist row and hk-uninstall-removes-hooks paired sh:sh,ps1:ps1,node:node; a fake node twin that writes one more byte into a hook SHALL fail naming sh:node; the real-registry unit test and aai-bootstrap.test.mjs TEST-3956 SHALL pass and spec-amend list SHALL hold the SPEC-0284 and SPEC-0306 records. | done | TEST-3995 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3995.log; TEST-3995 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3995.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3995.txt | — | D-PARITY; H2 on Windows |
| Spec-AC-17 | WHEN this checkout is synced with aai-sync.sh --profile core into a scratch target the system SHALL vendor the module, both launchers, guard-config and the templates, and bash, sh and pwsh runs of the vendored launchers SHALL each exit 0 with byte-equal hooks, while sh without node on PATH SHALL exit 1 with the refusal line and write no hook; WHEN a scratch target holding the frozen bash installer is updated by aai-update.sh from a scratch copy of this checkout, the following plain launcher run SHALL exit 0 with the three hooks attested. | done | TEST-3996 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3996.log; TEST-3996 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3996.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3996.txt | — | D-INSTALL |
| Spec-AC-18 | Wiring per D-WIRE: select-suites SHALL route the module, both launchers, guard-config, both reference copies, the node:test file, the Pester file and vendor-hook-installer.sh to aai-hook-installer-node, and every row listing install-pre-commit-hook.sh SHALL list install-pre-commit-hook.mjs; both weights rows SHALL be 196 with their fallback lines; hygiene test_090 SHALL pin 142 and test_129 pass; the cd-subshell baseline SHALL hold 1 for install-pre-commit-hook.sh; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps SHALL exit 0; both ps1-quality path lists SHALL be identical and hold the D-WIRE entries with win-fallback test_034 and test_035 passing. | done | TEST-3997 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3997.log; TEST-3997 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3997.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3997.txt | — | D-WIRE |
| Spec-AC-19 | CHANGELOG.md SHALL hold the D-DOCS heading exactly once with a body naming Node.js 22, DR-4, DR-6, DR-11, DR-12, DR-15, DR-16 and DR-17; SKILL_UPDATE.prompt.md step 4 SHALL hold the D-DOCS lines once each with TEST-621's tokens present and the file at least 3600 bytes, and test-aai-prompt-diet.sh test_012 and test_622, the pr-preflight growth case and the suite-reuse growth case SHALL pass; docs/USER_GUIDE.md SHALL name the module and Node.js 22 in the installer section; the RFC-0017 phase 5 row SHALL keep status in progress and hold the D-DOCS sentence once with a link ending pre-commit-installer-on-node.md, the inventory SHALL hold no install-pre-commit-hook row, and expert-fetch test_2624 SHALL pass. | done | TEST-3998 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3998.log; TEST-3998 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3998.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3998.txt | — | D-DOCS |
| Spec-AC-20 | follow-ups list --status all SHALL show each of the eighteen D-FU follow-ups closed with resolved_by pre-commit-installer-on-node and a source naming a test file and a TEST id that occurs in that file followed by a colon, fu-seterr-suspended-left-of-or SHALL stay open, and the four suggested follow-ups SHALL be listed open with ref pre-commit-installer-on-node. | done | TEST-3999 red docs/ai/tdd/pre-commit-installer-on-node/red/TEST-3999.log; TEST-3999 green docs/ai/tdd/pre-commit-installer-on-node/green/TEST-3999.log, mutation docs/ai/tdd/spec-pre-commit-installer-on-node/mutation-TEST-3999.txt | — | D-FU |

## Implementation plan

TDD in seven runs (D-SLICES); each run stores RED under
`docs/ai/tdd/pre-commit-installer-on-node/red/` before its change and GREEN
under `green/`, and one mutation record per row (`node
.aai/scripts/mutation-run.mjs`, records under
`docs/ai/tdd/spec-pre-commit-installer-on-node/`) before the run's hand-off.
New files: the module, `tests/fixtures/hook-installer-reference/install-pre-commit-hook.sh`
and `.ps1`, `tests/skills/lib/hook-installer-reference.mjs`,
`tests/skills/lib/install-pre-commit-hook.test.mjs` (optionally
`tests/skills/lib/install-pre-commit-hook-fixtures.mjs`),
`tests/skills/test-aai-hook-installer-node.sh`,
`tests/skills/test-aai-hook-installer-docs.sh` (its own small suite, so the
installer suite is not a release dry-run CHANGELOG reader, as ride 10
learned).

Seams this change shares with features it does not own, each crossed by a
test that produces on one side and asserts on the other:

- The ref_guard policy file: written by the module through guard-config,
  seeded by aai-sync from the template, read by the module, by aai-doctor
  CAT-17 and by the hook templates' neighbours. TEST-3983 writes it and reads
  it with the reader and with the doctor; TEST-3984 runs the module's plain
  install on what decline and arm wrote.
- The hook bodies: owned by the templates (SPEC-0278), composed by the
  module, run by git. TEST-3985 and TEST-3989 compare the module's bytes
  with the bash reference's on the shipped templates; git-ref-guard TEST-308
  keeps its sha256 baseline of the installed pre-commit hook; the parity
  harness compares the three twins' hooks (TEST-3995).
- The hooks directory git resolves: TEST-3986 and K09, K10 run git itself in
  scratch repositories with `core.hooksPath` and a linked worktree.
- The launchers and the module, vendored by aai-sync through PROFILES and
  run by SKILL_UPDATE step 4 after aai-update: TEST-3996.
- The test vendoring helper and every suite that uses it:
  `check-vendored-script-deps.mjs` and one vendored run per suite in
  TEST-3992.
- The parity driver's twin registry and the frozen references on native
  Windows: TEST-3995 and hosted check H2.
- The ps1 launcher's argument marshalling between PowerShell's binder and
  the module's parser: TEST-3993 (in session and under `-File`) and H1.
- A residual seam no automated test crosses: a downstream consumer who
  hand-edits `docs/ai/docs-audit.yaml` with a BOM and expects the old
  `armed` reading (DR-16 changes it to `declined`; disclosed in the
  CHANGELOG).

Edge cases: a case path with a space (K31, Pester 5); a symlinked working
directory and a stale `PWD`; a subdirectory cwd; `core.hooksPath` pointing at
a missing directory, at an absolute path and at a file; a linked worktree; a
CRLF, BOM, value-less, doubled and non-breaking-space `ref_guard` line; a
symlinked and a dangling-symlink config; an unwritable config directory; a
directory, dangling link, pipe and socket in each slot; a marker only in a
comment (foreign); a marker followed by CR and more bytes; an index template
without a final LF; a guard template without END; git absent from PATH;
PowerShell callers in session with comma arrays and `-Switch:$false`;
Windows paths from git (H2).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3980 | Spec-AC-01 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3980_scratch_safety runs run_node_tests TEST-3980 (removeOwnScratch refuses each D-SAFETY case and removes a marked own directory; both reference copies hash to their pins and equal git show bf0148d6 of the twins when that object exists; materializeHookInstallerReference writes the two twins and the four templates), checks safe_rm_own refuses an empty, relative, foreign, symlinked and unmarked path and an empty list, scans the new test files for docker, pkill and killall calls, and checks every installer invocation helper sets GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL and asserts the resolved hooks path lies under the own scratch root | `sed:s/const OWN_SCRATCH_PREFIX = 'aai-hk-';/const OWN_SCRATCH_PREFIX = '';/` on tests/skills/lib/hook-installer-reference.mjs | green |
| TEST-3981 | Spec-AC-02 | inspection | tests/skills/test-aai-hook-installer-node.sh | test_3981_module_shape runs run_node_tests TEST-3981: import in a scratch cwd creates nothing and prints nothing; the export list; only node: imports plus ./lib/guard-config.mjs and none of the network modules; each anchor once; one spawnSync call; no process.stdout or process.stderr; no template line of 40 or more characters; the arm rationale comment once; ASCII only | `sed:s/const writeFd = \(fd\) => \(s\) => \{ fs.writeSync\(fd, s\); \};/const writeFd = (fd) => (s) => { process.stdout.write(s); };/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3982 | Spec-AC-03 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3982_cli_and_mode runs run_node_tests TEST-3982: every accepted form in mixed order and case, last --hooks and --print kind win, help equal to lines 4 to 78 of the reference after the sed transform plus the two DR-1 lines, unknown argument, -F, -Verbose and --hooks= with exit 2 and no spawn recorded, --hooks at the end, every pair of mode flags, --force with print, uninstall and decline, --hooks with print, decline and arm, the tokens index comma, space index, Index and an empty value, each with its exact line and exit 2 and no spawn; resolveBase with a matching PWD, a stale PWD and a symlinked cwd | `sed:s/const EXIT_USAGE = 2;/const EXIT_USAGE = 0;/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3983 | Spec-AC-04 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3983_policy_writer runs run_node_tests TEST-3983 on writeRefGuardPolicy and readRefGuardPolicy in scratch directories: seed from a template and from nothing, a symlinked file written through with the link kept, a dangling link refused with nothing written, mode 0644 and 0600 kept, CRLF and mixed endings kept per line, a BOM kept, a doubled and a value-less key collapsed with the removed line numbers, append with CRLF and with a missing final newline, no write (same mtime and inode) when unchanged, a 0444 file refused unchanged, no temp left after an injected failure, a read-back mismatch thrown; the reader on a BOM-prefixed declined and on the eleven existing variants; then runs aai-doctor.mjs on a scratch repository with the BOM-prefixed declined file and no hook and requires CAT-17 DECLINED | `sed:s/const REF_GUARD_KEY_LINE = \/\^ref_guard:\/;/const REF_GUARD_KEY_LINE = \/^ref_guardX:\/;/` on .aai/scripts/lib/guard-config.mjs | green |
| TEST-3984 | Spec-AC-05 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3984_policy_flows runs run_node_tests TEST-3984 in scratch repositories: plain install skips the ref-guard for each reader verdict of declined (including the BOM case) and installs it for armed, invalid and absent, with the Skipped and the DR-10 re-arm lines; --force past a decline installs it and leaves declined recorded; decline refuses a foreign hook unmodified, writes first and keeps the hook with exit 1 under a read-only config file and under an unwritable config directory, removes an AAI hook after the write; arm records armed after the attested hook; the foreign refusal names --print ref-guard and the install disclosure names the decline command; uninstall of the ref-guard prints the two DR-18 lines only when the policy reads armed; a doubled key gives the DR-17 warning on a plain run with no write and the Removed line on arm and decline; the module source holds no ref_guard regex | `sed:s/const SKIP_DECLINED = \(mode, policy\) => !mode.force && policy === 'declined';/const SKIP_DECLINED = (mode, policy) => !mode.force && policy === 'declinedX';/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3985 | Spec-AC-06 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3985_templates runs run_node_tests TEST-3985: templates read from an injected scriptDir with CRLF bytes yield LF output; each missing template named with exit 1 and no hook written; an index template with one line and a guard template without END, with END above BEGIN and without a final newline refused as malformed; --print and each kind outside a repository equal the CR-stripped template bytes; composePreCommit on the shipped templates equals the bytes the bash reference writes, and on an index template without a final LF ends with one LF | `sed:s/const ensureFinalLf = \(b\) => \(b.length && b\[b.length - 1\] !== 10/const ensureFinalLf = (b) => (b.length && b[b.length - 1] !== 11/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3986 | Spec-AC-07 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3986_paths needs git and runs run_node_tests TEST-3986 in scratch repositories with real git: the three slot paths equal git rev-parse --git-path for hooksPath unset, relative and missing, absolute, from a subdirectory and in a linked worktree, and the hooks land there; outside a repository the bash not-a-repository line with exit 1; with an injected spawn that cannot start git the DR-8 line with exit 1; message paths built from PWD when it names the cwd | `sed:s/const GIT_PATH_ARGS = \(name\) => \['rev-parse', '--git-path'/const GIT_PATH_ARGS = (name) => ['rev-parse', '--git-common-dir'/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3987 | Spec-AC-08 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3987_attestation runs run_node_tests TEST-3987: classifySlot gives every D-SLOT state for crafted slots (a marker only in a comment is foreign; a marker followed by CR then a space is not a marker line); a declined unforced reference-transaction slot holding a foreign file, a directory or a dangling link is neither classified nor written while the other slots install; for each refusal kind in each of the three slots, and for two refusals at once, every refusal is printed in slot order on stderr, the exit is 1, and the case snapshot is byte-identical with no hook, temp file, hooks directory or policy line created | `sed:s/  if \(refusals.length\) return refuseWholeRun\(refusals\);/  if (false) return refuseWholeRun(refusals);/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3988 | Spec-AC-09 | unit | tests/skills/test-aai-hook-installer-node.sh | test_3988_writes runs run_node_tests TEST-3988: an injected rename that lands the temp inside a directory or writes other bytes makes the run exit 1 with the landing line and no temp or stray left; upgrade by insertion after a shebang and at the top, interior refresh, and current, each keeping every byte outside the interior (compared with planUpgrade on fixed inputs and with the bash reference on the same files); marked-differs reference-transaction and pre-push hooks left unwritten with the NOTE line and replaced under --force; new hooks with mode 0777 minus umask under umask 022 and 077; a hook made non-executable after the write fails the post-run attestation on posix and passes with platform win32 | `sed:s/    if \(!landed\(slot, bytes\)\) return landingFailure\(slot\);/    if (false) return landingFailure(slot);/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3989 | Spec-AC-10 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3989_corpus_bash needs bash and git and runs run_node_tests TEST-3989: every bash-side D-CORPUS case, comparing exit, stdout, stderr, the case snapshot and the TMPDIR listing after the registered rewrites, with the asserted divergences and a failure for a registered rewrite that changes nothing | `sed:s/Uninstall with: bash .aai\/scripts\/install-pre-commit-hook.sh --uninstall/Uninstall with: bash .aai\/scripts\/install-pre-commit-hook.sh/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3990 | Spec-AC-11 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3990_corpus_powershell needs pwsh (need_tool) and runs run_node_tests TEST-3990: every PowerShell-side D-CORPUS case against the frozen PowerShell reference with the module on the same PowerShell-form arguments, comparing exit and the case snapshot, with the asserted divergences | `sed:s/ '-armrefguard': '--arm-ref-guard' / /` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3991 | Spec-AC-12 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3991_sh_launcher checks the launcher text (at most 20 lines, ASCII, mode 100755, no policy token outside the comment lines), runs a copy beside a stub module under bash, sh and dash (dash through need_tool) with both flag forms and -h and requires the argv and exit 7 through, then with PATH holding only dirname and with the module removed requires exit 1, the exact refusal line and an unchanged repository | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE"/` on .aai/scripts/install-pre-commit-hook.sh | green |
| TEST-3992 | Spec-AC-13 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3992_rehomed_bash_side runs the selectors test-aai-git-ref-guard.sh test_314_print_flag, test-aai-hygiene-pack.sh test_618_ref_guard_grep_conformance, test-aai-docs-audit.sh test_spec0011_hook_parity_grep and test_change0007_hook_body_lint, and one selector per suite that calls vendor_hook_installer, each exit 0; runs check-vendored-script-deps (exit 0); requires PROFILES core to list the module; reads spec-amend list --json for the SPEC-0156, SPEC-0011, SPEC-0013 and first SPEC-0184 records of ref pre-commit-installer-on-node | `sed:s/  cp "\$src\/.aai\/scripts\/install-pre-commit-hook.mjs" "\$root\/.aai\/scripts\/"/  : no module copied/` on tests/skills/lib/vendor-hook-installer.sh | green |
| TEST-3993 | Spec-AC-14 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3993_ps1_launcher checks the .ps1 text (at most 20 lines, ASCII, no param block, no policy token outside the comment lines), then needs pwsh and Pester 5 and runs Invoke-Pester on tests/skills/install-pre-commit-hook.Tests.ps1 filtered to the launcher context under env -u AAI_ROLE requiring 5 passed, 0 skipped, 0 failed and 0 failed containers | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/install-pre-commit-hook.ps1 | green |
| TEST-3994 | Spec-AC-15 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3994_rehomed_ps1_side needs pwsh and Pester 5, runs the selectors test-aai-git-ref-guard.sh test_309_ps1_twin_static, test_608_ps1_hooks_static, test_631_ps1_decline_arm_params_static, test_632_ps1_policy_reader_fails_closed_static, test_633_ps1_foreign_refusal_shared_helper, test_637_ps1_plain_reinstall_honours_decline_static, test_641_ps1_write_policy_corrects_stray_value, test_642_ps1_decline_orders_write_before_removal, test_644_ps1_decline_seeds_or_discloses_new_config, test_646_ps1_hooks_contradicts_decline_arm, test_647_arm_ref_guard_creates_missing_hooks_dir and test-aai-hygiene-pack.sh test_813_ps1_twin_parity and test_818_ps1_upgrade_is_byte_exact_and_order_checked, each exit 0, with no grep, awk or sed over the .ps1 left in those functions; runs Invoke-Pester on the whole Pester file requiring 0 failed, 0 skipped and 0 failed containers; reads spec-amend list --json for the second SPEC-0184, the second SPEC-0156 and the SPEC-0201 and SPEC-0278 records | `sed:s/const HOOK_TOKENS = \['index', 'ref-guard', 'close-gate'\];/const HOOK_TOKENS = ['index', 'ref-guard'];/` on .aai/scripts/install-pre-commit-hook.mjs | green |
| TEST-3995 | Spec-AC-16 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3995_parity_hooks needs pwsh, runs the driver with the ten HK scenarios and twins sh,ps1,node into a scratch report and requires exit 0, verdict PASS, pairs sh:ps1, sh:node and ps1:node per hook scenario, the sh and ps1 argv naming hkref, node present only on UP, BS and HK scenarios; runs run_node_tests TEST-3995 in install-parity.test.mjs (a fake node twin writing one more byte into a hook fails naming sh:node; the real-registry argv test; the widened row) and aai-bootstrap.test.mjs TEST-3956; requires the SPEC-0284 and SPEC-0306 records | `sed:s/ops: \['bootstrap', 'update', 'hooks'\]/ops: ['bootstrap', 'update']/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3996 | Spec-AC-17 | integration | tests/skills/test-aai-hook-installer-node.sh | test_3996_scratch_install syncs this checkout with --profile core into a scratch git target, requires the module, both launchers, guard-config and the four templates vendored, runs bash, sh and pwsh (need_tool) launchers on three fresh copies at one path with byte-equal hooks, then sh with PATH holding only dirname exits 1 with the refusal line and no hook; then updates a scratch target holding the frozen bash installer with aai-update.sh from a committed scratch copy of this checkout's tracked files and requires the following plain launcher run to exit 0 with the three hooks attested | `sed:s/  - .aai\/scripts\/install-pre-commit-hook.mjs\n//` on .aai/system/PROFILES.yaml | pending |
| TEST-3997 | Spec-AC-18 | inspection | tests/skills/test-aai-hook-installer-node.sh | test_3997_wiring pipes the module, both launchers, guard-config, both reference copies, the node:test file, the Pester file and vendor-hook-installer.sh to select-suites.mjs --files-from - and requires aai-hook-installer-node each time; requires every suite-map row naming install-pre-commit-hook.sh to name install-pre-commit-hook.mjs; requires both weights rows 196 with their fallback lines; runs hygiene-pack test_090_suite_map_pin and test_129_mutation_gate_suite_registration and win-fallback test_034 and test_035 selectors; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the baseline row 1 for install-pre-commit-hook.sh and identical ps1-quality path lists holding the D-WIRE entries | `sed:s/  aai-hook-installer-node:/  aai-hook-installer-node-gone:/` on tests/skills/suite-map.yaml | pending |
| TEST-3998 | Spec-AC-19 | inspection | tests/skills/test-aai-hook-installer-docs.sh | test_3998_docs requires the CHANGELOG heading once with Node.js 22, DR-4, DR-6, DR-11, DR-12, DR-15, DR-16 and DR-17 in its body, the SKILL_UPDATE step 4 lines once each with TEST-621's tokens and the file at least 3600 bytes, the USER_GUIDE installer section naming install-pre-commit-hook.mjs and Node.js 22, the RFC-0017 phase 5 row in progress holding the D-DOCS sentence once with a link ending pre-commit-installer-on-node.md and no install-pre-commit-hook inventory row, and runs test-aai-prompt-diet.sh test_012 and test_622, the pr-preflight and suite-reuse growth selectors, test-aai-git-ref-guard.sh test_621 and expert-fetch test_2624_inventory_matches_tree (exit 0) | `sed:s/The sixteenth slice \[moved the git hook installer to Node\]/The sixteenth slice [moved hooks]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |
| TEST-3999 | Spec-AC-20 | inspection | tests/skills/test-aai-hook-installer-docs.sh | test_3999_follow_ups reads follow-ups list --status all --json and requires each of the eighteen D-FU ids closed with resolved_by pre-commit-installer-on-node and a source whose test file exists and contains the cited TEST id followed by a colon, fu-seterr-suspended-left-of-or open, and the four suggested ids open with ref pre-commit-installer-on-node | `sed:s/TEST-3982:/TEST-3982X:/g` on tests/skills/lib/install-pre-commit-hook.test.mjs | pending |

Test counts by type: unit 7, integration 9, inspection 4 (20 rows). The
re-homed rows of other specs (D-REHOME) keep their own ids and mutations.

RED observations (stored under
`docs/ai/tdd/pre-commit-installer-on-node/red/`): TEST-3980 to TEST-3990 fail
on the baseline because the reference copies, their helper, the node:test
file, the module and the guard-config writer do not exist; TEST-3991 fails
because the `.sh` is still the bash twin (more than 20 lines); TEST-3992
fails on the re-homed selectors after the `.sh` swap and before their edits
(the run 5 order makes this the RED); TEST-3993 and TEST-3994 fail because
the `.ps1` is still the twin and the Pester context and re-homes are absent;
TEST-3995 to TEST-3999 fail because the hooks op of the node twin, the
vendoring, the suite rows, the docs and the follow-up closures are absent.

Hosted checks (CI, not Test Plan rows; recorded in the validation report
from the PR's ps1-quality run):

- H1: `windows-5_1` (Windows PowerShell 5.1 and pwsh 7) and `windows-wsl1`
  full-suite steps report `install-pre-commit-hook.Tests.ps1` passed
  including the five launcher cases, skipped count still 4, TotalCount at or
  above 111, no failed container.
- H2: the `windows-parity` job's two steps pass with the smoke hook
  scenarios (HK-01, 03, 05, 07, 10) compared on pairs sh:ps1, sh:node and
  ps1:node, the node twin present; `AAI-PARITY-ELAPSED` recorded per engine.
- H3: the Windows CAT-17 step (`bash .aai/scripts/install-pre-commit-hook.sh
  --arm-ref-guard` under Git Bash, then the doctor probe) passes, proving the
  `.sh` launcher and the module natively on Windows.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hook-installer-node.sh`
  exits 0 (18 rows) and the same for `tests/skills/test-aai-hook-installer-docs.sh`
  (2 rows), plus the touched and selected suites run the same way:
  test-aai-git-ref-guard.sh, test-aai-hygiene-pack.sh,
  test-aai-docs-audit.sh, test-aai-git-hook-templates.sh,
  test-aai-doctor.sh, test-aai-pre-commit-checks.sh,
  test-aai-tracked-ignored.sh, test-aai-install-parity.sh,
  test-aai-win-fallback.sh, test-aai-prompt-diet.sh,
  test-aai-pr-preflight.sh, test-aai-suite-reuse.sh,
  test-aai-expert-fetch.sh, test-aai-layer-profiles.sh, test-ps1-quality.sh,
  test-aai-update-node.sh; then the full sweep once before close with
  `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/install-pre-commit-hook.test.mjs`,
  `env -u AAI_ROLE node --test tests/skills/lib/install-parity.test.mjs` and
  `env -u AAI_ROLE node --test tests/skills/lib/aai-bootstrap.test.mjs` exit 0
  (also under Node 22; the PowerShell-side corpus fails on CI and names the
  tool when pwsh is missing, and skips with a named reason locally).
- Hosted checks H1, H2 and H3 from the PR's ps1-quality run; a divergence
  that appears only on Windows gets an allowlist row and a follow-up in a
  remediation pass, never a normalization.
- `node .aai/scripts/spec-lint.mjs --path <this spec>`,
  `node .aai/scripts/mutation-gate.mjs` for this spec and
  `node .aai/scripts/spec-amend.mjs list --strict` pass.

## Evidence contract

ref_id `pre-commit-installer-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/pre-commit-installer-on-node/` and
`docs/ai/tdd/spec-pre-commit-installer-on-node/` (gitignored); each AC row's
Evidence names its green log and mutation record; the validation report and
review verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- The `.ps1` launcher's marshalling under Windows PowerShell 5.1 (legacy
  native argument passing drops an empty string, so `-Hooks ""` reaches the
  module as a missing value; both exit 2) is proven only by H1.
- The `.sh` launcher under Git Bash hands node a POSIX module path that
  MSYS converts; proven only by H3.
- `fs.renameSync` over an existing hook on Windows fails when another
  process holds it open or it is read-only; the module then exits 1 with
  the landing line, as the twins failed; not reproduced at planning.
- DR-16 changes `aai-doctor` CAT-17's reading of a BOM-prefixed declined
  config from armed to declined; disclosed in the CHANGELOG.
- The corpora's runtime is not measured at planning (estimate: about 60 s
  for both sides); the suite weight 196 is the fallback. TEST-3569's parity
  bounds now include the node twin on the hook scenarios (estimate: under
  4 s added); a bound exceeded on the reference host moves a scenario's tier
  by a recorded edit, never the bound.
- A downstream project without Node can no longer install the hooks; it
  could not run `/aai-update` without Node since ride 10 either, and step 4
  runs only after a successful update. This is the owner's decision,
  disclosed in the CHANGELOG.
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope: fu-installer-flag-lattice-no-mode, fu-three-readers-three-whitespaces, fu-installer-want-refguard-overloaded, fu-ps1-writeerror-terminates-before-exit, fu-ps1-symlink-config-replaced, fu-ps1-decline-not-disclosed, fu-ps1-refusal-no-manual-merge, fu-ps1-decline-force-advice-wrong, fu-ps1-enable-refguard-no-rationale, fu-ps1-setcontent-rewrites-seed-eol, fu-hook-tmpl-final-lf-parity, fu-hook-installer-not-a-repo-msg, fu-uninstall-refguard-leaves-armed, fu-doubled-key-has-no-repair, fu-ac05-counts-a-valueless-key, fu-test618-positional-pattern, fu-test641-passes-without-pwsh, fu-skill-update-step4-both-hooks (each with the evidence named in D-FU).

Items this scope touches and leaves open, with reasons:
`fu-seterr-suspended-left-of-or` (P2; its subject is every `fn || exit 1`
in the shell corpus; the installer's own instances disappear with the twin,
the class remains in other scripts), `fu-docs-audit-yaml-misnamed-guard-config`
(out of scope by the intake), `fu-doctor-declined-vocab-undeclared` (a
doctor vocabulary item), `fu-bare-config-satisfies-lane-gate` (lane gate,
not the installer), `fu-hook-cp-guard-midline` and
`fu-ps1-derive-misses-backslash-joinpath` (test tooling the port does not
change), `fu-mutation-selector-vs-bare-dispatch`,
`fu-duplicate-message-collides-mutation`,
`fu-mutation-patch-consumes-own-source` and `fu-mutation-anchors-undisclosed`
(mutation tooling; this spec's anchors are named up front).
