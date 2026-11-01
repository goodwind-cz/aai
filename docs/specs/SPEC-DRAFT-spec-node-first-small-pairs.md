---
id: spec-node-first-small-pairs
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: f03745b487cea50aea788298bf903e4c2a1e34ac5c5d03fd891be5502ffc4984
ceremony_level: 2
links:
  requirement: node-first-small-pairs
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move validate-skills and aai-live to Node and retire pre-compact-save

SPEC-FROZEN: true

## Links

- Requirement: [Move three small paired scripts to Node](../issues/CHANGE-DRAFT-node-first-small-pairs.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  section "Remaining paired scripts after phase 3" (later candidates).
- Pattern precedents: [SPEC-0247](SPEC-0247-spec-node-first-sync-hook-slice.md),
  [SPEC-0248](SPEC-0248-spec-node-first-second-slice.md) and
  [SPEC-0249](SPEC-0249-spec-node-first-third-slice.md): one module, thin
  launchers, measured drift table, Windows parity proven only on the hosted
  Windows PowerShell 5.1 job, a hosted failure diagnosed with a probe first.
- Doctor contract touched: [SPEC-0100](SPEC-0100-spec-doctor-determinize.md) TEST-009 (CAT-09).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor
  downstream, Node 24 CI).
- Baseline: main `89a63814`; the ride branch adds only the intake (`d27e0b82`).

## Implementation strategy

- Strategy: hybrid
- Rationale: the two new modules, the four launchers and the new CAT-09 check
  are new behavior with recorded drift decisions, so every row that gates them
  goes RED first on the baseline (the modules do not exist; the old copies fail
  at least one drift case; CAT-09 still checks file presence) and carries a
  mutation record. The retirement, the wiring edits (PROFILES, suite map, the
  ps1-quality path filter), the RFC inventory and the fixture adjustments of
  existing tests are mechanical and done in loop mode, each pinned by a
  mutation-gated row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to shipped scripts, a CI workflow, the
  vendored profile manifest and an umbrella RFC, running beside the
  precise-suite-evidence-reuse ride; the ride already runs in its own linked
  worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: feat/node-first-small-pairs at /Users/ales/Projects/aai-worktrees/node-first-small-pairs
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/validate-skills.mjs .aai/scripts/validate-skills.sh
  .aai/scripts/validate-skills.ps1 .aai/scripts/aai-live.mjs
  .aai/scripts/aai-live.sh .aai/scripts/aai-live.ps1
  .aai/scripts/pre-compact-save.sh .aai/scripts/pre-compact-save.ps1
  .aai/scripts/aai-doctor.mjs .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/test-aai-validate-skills.sh
  tests/skills/lib/validate-skills.test.mjs tests/skills/validate-skills.Tests.ps1
  tests/skills/lib/aai-live.test.mjs tests/skills/aai-live.Tests.ps1
  tests/skills/test-aai-live-status.sh tests/skills/test-aai-doctor.sh
  tests/self-hosting/test-self-hosting-smoke.ps1
  tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/product/live-status-dashboard.md docs/ai/decisions.jsonl CHANGELOG.md
  docs/issues/CHANGE-DRAFT-node-first-small-pairs.md
  docs/specs/SPEC-DRAFT-spec-node-first-small-pairs.md
  (suite-weights.tsv only if the selector asks for a row; the cd-subshell
  baseline only if the checker asks for a re-record).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash with `/usr/bin/grep`, Node
22.23.1, pwsh 7.6.3) on 2026-11-01. Windows PowerShell 5.1 was not available
to Planning; rows marked "by inspection" were read from the code.

| Pair | Lines sh/ps1 | Executing tests today | Callers outside docs |
|---|---|---|---|
| validate-skills | 47/55 | sh copy through tests/self-hosting/test-self-hosting-smoke.sh (CI job self-hosting-smoke); ps1 copy through the ps1 smoke, which no CI job runs | the two smoke scripts, PROFILES (extended), cd-subshell baseline, USER_GUIDE line 2290 |
| pre-compact-save | 77/87 | none (aai-doctor CAT-09 and TEST-009 check file presence only) | PROFILES (core), aai-doctor CAT-09, test-aai-doctor.sh fixture lines and TEST-009 |
| aai-live | 125/90 | live-status TEST-027 (opener refusal), TEST-031 (watch warm-up), TEST-037 (one-shot --output), all on the sh copy | PROFILES (extended), suite map, cd-subshell baseline, docs/product/live-status-dashboard.md |

Total before: 481 lines.

### pre-compact-save: where STATE lives and who wires the hook

- STATE lives at `docs/ai/STATE.yaml` in every checkout and linked worktree:
  state.mjs defaults to it (`--state`, line 61 and 1654), docs/TECHNOLOGY.md
  names it (lines 57, 189), `.gitignore` line 79 ignores it, and this ride's
  own STATE is that file. Both copies of pre-compact-save already read that
  path. The intake's premise that the path is stale is false; no path fix is
  needed. (`.aai/STATE.yaml` appears only in a provenance string of
  validation-outcome-check.mjs line 407; that script reads the same file.)
- No shipped install wires the hook: `.aai/templates/hooks/settings-hooks.json`
  wires PreToolUse and Stop only, `live-status-hooks.json` wires no PreCompact,
  aai-bootstrap, aai-sync and install.sh write no PreCompact entry, this
  repository has no `.claude/settings*.json`, and the owner's user settings
  carry no PreCompact hook (grep count 0). The only wiring instruction is a
  comment inside the two scripts.
- Nothing reads its output: `docs/ai/.session-context.md` and
  `docs/ai/.pre-compact-state-backup.yaml` are named only by ignore lists
  (`.gitignore`, RUNTIME_IGNORE.list, DOCS_AI_CANON.list,
  migrate-state-to-local.ps1) and archived analysis; no prompt or script reads
  them back.
- A retirement is non-destructive downstream: both aai-sync profile paths
  keep a target-only script (`PRESERVE target-only script`, aai-sync.sh lines
  357 and 404), so a target that hand-wired the hook keeps its copy.

## Decisions

- PC-1 (pre-compact-save): retire the pair, do not port it. Porting would
  move 164 lines that no shipped install runs and give a hook that has no Node
  dependency one; the path needs no fix (above). The two scripts and their
  core PROFILES entries go; the ignore-list entries for the two output files
  stay (a preserved downstream copy may still write them). aai-doctor CAT-09
  keeps its id and changes meaning (D3). CHANGELOG names the retirement
  (Constitution Article 5: an explicit, documented breaking change).
- LV-1 (aai-live placement): a new module `.aai/scripts/aai-live.mjs` beside
  the generator, not code folded into generate-live-status.mjs. Reasons,
  measured: the inventory rule (TEST-2624 of SPEC-0249) counts a pair as
  `<name>.sh` plus `<name>.ps1` with no `<name>.mjs`, so only `aai-live.mjs`
  takes the pair out of the inventory; the generator (680 lines) is also run
  by aai-live-serve.mjs with `--data-only` and its contract stays untouched;
  the launcher logic (opener choice, output resolution, warm-up, signal
  forwarding) is unrelated to page generation.
- VS-1 (validate-skills drift): the module keeps the bash copy's observable
  behavior, which is the copy CI runs (table V below).

### Drift between the validate-skills copies (measured)

Both copies ran on the same scratch fixtures (all twelve required files plus
marker plus a skill tick; required files only; one required file missing; a
directory where a required file belongs; a tick log without a skill entry; a
CRLF tick log with `"mode": "skill"`; a missing target).

| Id | Case | Bash copy | PowerShell copy | Decision |
|---|---|---|---|---|
| V-1 | a required file missing | `ERROR: Missing required file: <abs path>` on stderr, exit 1, first missing only | a thrown error record with source position, exit 1 | the bash line on stderr, exit 1, first missing only, in the REQUIRED order |
| V-2 | marker or tick log absent, or no skill tick | `WARN: <text>` on stdout | `WARNING: <text>` on the warning stream, coloured | `WARN: <text>` on stdout, the bash texts verbatim |
| V-3 | a directory at a required path | missing, exit 1 (`-f`) | accepted, exit 0 (`Test-Path`) | regular files only (missing, exit 1) |
| V-4 | target directory does not exist | `cd` error text from bash, exit 1 | Resolve-Path error record, exit 1 | `ERROR: Target not found: <arg>` on stderr, exit 1 |
| V-5 | skill tick detection | `grep -q '"mode":"skill"'` (no regex metacharacter, so literal) | `-SimpleMatch` literal | unchanged: literal substring `"mode":"skill"`; the CRLF fixture with a space after the colon gives the no-skill warning in both copies today and keeps doing so |
| V-6 | argument form | positional target, default the current directory | `-TargetRoot`, default the current location | sh launcher positional, ps1 launcher `-TargetRoot` and positional; both default to the current directory |
| V-7 | Node absent or module missing | never needed Node | never needed Node | each launcher prints exactly `ERROR: validate-skills needs node (validate-skills.mjs unavailable)` on stderr and exits 1 |

Observed and left alone (no new features): validate-skills requires three
extended-profile prompts (SKILL_VALIDATE_REPORT, SKILL_CANONICALIZE,
SKILL_SHARE), so it fails on a core-profile install; it is itself extended.

### Drift between the aai-live copies (measured or by inspection)

| Id | Case | Bash copy | PowerShell copy | Decision |
|---|---|---|---|---|
| L-1 | `AAI_LIVE_OPENER` | honoured (measured by TEST-027/031/037) | ignored (by inspection) | honoured on every platform; the value is one executable path |
| L-2 | opener without override | `open`, else `xdg-open` on PATH, else refuse | `Start-Process` | non-win32: first of `open`, `xdg-open` found on PATH, else refuse; win32: `explorer.exe` with the absolute target (its exit code ignored) |
| L-3 | no opener found | refuses before generating, also under `--data-only`, exit 1, message names the opener (TEST-027) | never refuses | bash behavior: `aai-live: refused - no browser opener found on PATH (expected 'open' on macOS or 'xdg-open' on Linux; set AAI_LIVE_OPENER to override)` on stderr, exit 1, before the generator runs |
| L-4 | warm-up output under `--watch` | stdout and stderr suppressed, failure ignored | stdout suppressed only | both suppressed, failure ignored |
| L-5 | open target | last `--output` value, relative to the repository root; default `docs/ai/live-status.html` | same | same; an absolute `--output` is used as given |
| L-6 | `.cmd` or `.bat` opener on win32 | n/a | n/a | run through the shell with opener and target each double-quoted, so a target path with a space arrives as one argument |
| L-7 | opener run | synchronous, failure ignored | `Start-Process`, failure ignored | synchronous with a 10 s timeout, stdio ignored, any failure ignored |
| L-8 | `--watch` lifetime | `exec` into the generator (one process) | generator as a child, exit code forwarded | generator as a child with inherited stdio; SIGINT and SIGTERM received by the launcher are forwarded to it; the launcher exits with the generator's exit code (1 when it ended without one) |
| L-9 | repository root | logical script path, two directories up | same | the real path of the module (`import.meta.url`), two directories up; the generator runs with that directory as its working directory |
| L-10 | missing generator | `aai-live: refused — generator not found: <path>`, exit 1 | same text with an ASCII hyphen | `aai-live: refused - generator not found: <path>`, exit 1, ASCII only |
| L-11 | Node absent or module missing | `aai-live: refused — node not found in PATH`, exit 1 | same with an ASCII hyphen | each launcher prints exactly `aai-live: refused - node not found in PATH or aai-live.mjs missing` on stderr and exits 1 |
| L-12 | one-shot generator failure | no open, generator exit code returned | same | same |

## Scope and design

### D1. `.aai/scripts/validate-skills.mjs`

Dependency-free ESM, Node 22 compatible (`node:fs`, `node:path`, `node:url`
only), at most 60 lines, ASCII only, no side effects on import, never reads
standard input, writes nothing. Exports `REQUIRED` (the twelve repo-relative
paths of the current copies, same order) and `validate(target)` returning
`{ code, out, err }` (arrays of lines), plus `main(argv)`. It contains these
exact lines, each once, and no comment repeats an anchor:

```js
const isFile = (p) => { try { return statSync(p).isFile(); } catch { return false; } };
const TICK = '"mode":"skill"';
const WARN = 'WARN: ';
const MISSING = 'ERROR: Missing required file: ';
const NOT_FOUND = 'ERROR: Target not found: ';
```

Output lines and order are those of the bash copy: `Validating skills in:
<path.resolve(target)>`, then either the first missing file (V-1) or the two
OK/WARN lines and `Skill validation completed.`

### D2. `.aai/scripts/aai-live.mjs`

Dependency-free ESM, Node 22 compatible (`node:fs`, `node:path`, `node:url`,
`node:child_process`), at most 120 lines, ASCII only, no side effects on
import, never reads standard input. Exports `resolveOutputPath(args, root)`,
`warmupArgs(args)`, `resolveOpener({ env, platform, pathEnv })` (returns
`{ cmd, shell }` or null) and `main(argv)`. Behavior per L-1 to L-12. It
contains these exact lines, each once:

```js
const DEFAULT_OUTPUT = 'docs/ai/live-status.html';
const CANDIDATES = ['open', 'xdg-open'];
const WIN_OPENER = 'explorer.exe';
const OPENER_TIMEOUT_MS = 10000;
const warm = args.filter((a) => a !== '--watch');
const dataOnly = args.includes('--data-only');
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
```

generate-live-status.mjs is not edited.

### D3. Launchers, retirement and doctor

- `validate-skills.sh` and `aai-live.sh`: at most 10 lines each, ASCII, the
  expert-fetch.sh shape (`MODULE=` from `BASH_SOURCE`, `exec node "$MODULE"
  "$@"` when node and the module exist, else the V-7 or L-11 line and exit 1),
  executable bit kept (the sh smoke runs validate-skills.sh directly).
- `validate-skills.ps1`: at most 15 lines, `param([string]$TargetRoot =
  (Get-Location).Path)`, `& node $Module $TargetRoot; exit $LASTEXITCODE`,
  else the V-7 line through `[Console]::Error.WriteLine` and `exit 1`.
- `aai-live.ps1`: at most 15 lines, keeps the
  `ValueFromRemainingArguments` `$RestArgs` binding, `& node $Module @RestArgs;
  exit $LASTEXITCODE`, else the L-11 line and `exit 1`.
- No launcher holds the REQUIRED list, an opener name, `--output` parsing or
  the warm-up.
- `pre-compact-save.sh` and `pre-compact-save.ps1` are deleted.
- aai-doctor CAT-09 (`Pre-Compact Hook`) keeps its id and title and reads
  `.claude/settings.json` and `.claude/settings.local.json` under the root. It
  contains `const RETIRED_HOOK = 'pre-compact-save';` and
  `const HOOK_SETTINGS = ['.claude/settings.json', '.claude/settings.local.json'];`.
  When a settings file's text contains `pre-compact-save` and neither
  `.aai/scripts/pre-compact-save.sh` nor `.ps1` exists: WARN, message names
  that settings file and says the hook names a script AAI retired (RFC-0017),
  remove the entry. When the text names it and a copy exists: PASS, message
  says a local copy serves a hand-wired hook. Otherwise PASS, message says no
  hook names the retired pre-compact-save. An unreadable settings file counts
  as absent.

### D4. Wiring and existing tests

- `.aai/system/PROFILES.yaml`: `.aai/scripts/validate-skills.mjs` and
  `.aai/scripts/aai-live.mjs` once each in `extended:` (companion obligation for
  new `.aai/**` files); the two pre-compact-save `core:` entries removed.
- `tests/skills/suite-map.yaml`: new row `aai-validate-skills` with globs
  `.aai/scripts/validate-skills.*`, `tests/skills/lib/validate-skills.test.mjs`,
  `tests/skills/validate-skills.Tests.ps1`, `tests/self-hosting/**`; the
  `aai-live-status` row gains `.aai/scripts/aai-live.mjs`,
  `tests/skills/lib/aai-live.test.mjs`, `tests/skills/aai-live.Tests.ps1`.
- `.github/workflows/ps1-quality.yml`: both modules added to the `push` and
  `pull_request` path lists, which stay identical (plus whatever
  test-aai-win-fallback.sh's derivation needs). No job, runner or step added.
- Existing tests, recorded adjustments:
  - live-status TEST-031 and TEST-037 copy `aai-live.mjs` into their scratch
    roots next to the launcher (fixture setup only; assertions unchanged).
    TEST-027 is unchanged: it symlinks node and dirname only, which the new sh
    launcher needs.
  - doctor TEST-009 changes to the D3 semantics (no settings: PASS; settings
    naming the hook without a copy: WARN; with a copy: PASS), and the all-PASS
    fixture drops its two pre-compact-save lines. This changes the SPEC-0100
    contract: one unsigned (`--signoff none`, the autopilot default; the owner's merge direction signs it) `node .aai/scripts/spec-amend.mjs add --spec
    docs/specs/SPEC-0100-spec-doctor-determinize.md --ref doctor-determinize
    --class contract --signoff none --authority "intake node-first-small-pairs
    (owner menu answer 2026-11-01 '1 2'): aai-doctor's check follows the
    pre-compact-save decision" --what "TEST-009 CAT-09 checks hook wiring
    against the retired pre-compact-save" --why "<one line>"` record.
  - `tests/self-hosting/test-self-hosting-smoke.ps1` checks `$LASTEXITCODE`
    after its validate-skills call and throws when it is non-zero: the old ps1
    copy threw on failure, an `exit 1` from the launcher does not, so without
    this the ps1 smoke would pass over a failed validation.
- `docs/product/live-status-dashboard.md`: the launcher sentence says the logic
  lives in aai-live.mjs and that `AAI_LIVE_OPENER` now works on Windows too.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(scripts): validate-skills and aai-live move to Node, pre-compact-save retired`
  naming V-3, V-4, L-1, L-2, L-8 and the retirement with the CAT-09 meaning.

### D5. RFC-0017

- The inventory table under `### Remaining paired scripts after phase 3` drops
  the rows `aai-live`, `pre-compact-save` and `validate-skills`; every other
  row stays byte for byte.
- Directly after the table, one paragraph:
  `The [small-pairs slice](../issues/CHANGE-DRAFT-node-first-small-pairs.md) moved validate-skills and aai-live to Node modules and retired pre-compact-save (three pairs 481 to <N> lines).`
  where `<N>` is the `wc -l` sum of the four launchers and two modules at
  delivery. The allocator rewrites the link at merge; checks match only the
  suffix `node-first-small-pairs.md`.
- The Rollout Status rows, the frontmatter (`status: implementing`,
  `umbrella: true`) and the phase 3 row (`done`) are not edited.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-03 (logic in one module each),
  Spec-AC-02 and Spec-AC-04 (launchers hold no copy) and Spec-AC-06 (the third
  pair removed with no remaining caller).
- Intake AC-002 maps to Spec-AC-05 locally and to hosted check H1 (native
  Windows, both engines).
- Intake AC-003 maps to Spec-AC-01 and Spec-AC-03; every changed drift row has
  a named test: V-1, V-3 TEST-3201; V-2, V-4, V-5 TEST-3202; V-6, V-7 TEST-3204
  and TEST-3205; L-1, L-2, L-5, L-6 TEST-3206; L-3, L-4, L-7, L-10, L-12
  TEST-3207; L-8, L-9 TEST-3208; L-11 TEST-3209 and TEST-3210.
- Intake AC-004 maps to Spec-AC-06 and Spec-AC-07 (measured: the path is
  already right, so the pair is retired).
- Intake AC-005 maps to Spec-AC-08.
- Intake AC-006 maps to Spec-AC-10.
- Intake AC-007 maps to Spec-AC-11; the wiring that keeps installs and CI
  selection right is Spec-AC-09.

## Constitution deviations

None. Article 5 (additive first): the retirement of pre-compact-save is a
breaking change made explicit (CHANGELOG entry, CAT-09 WARN naming a dangling
hook) and documented here; downstream copies are preserved by aai-sync.
Article 4 (degrade and report): without Node every launcher prints a named
error and exits 1. Article 2 (simplicity): no new seam; `AAI_LIVE_OPENER`
already exists.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN validate from .aai/scripts/validate-skills.mjs runs on a fixture root the system SHALL print the bash copy's lines (V-1, V-2), stop at the first missing REQUIRED path in REQUIRED order with exit 1, treat a directory at a required path as missing (V-3), print ERROR: Target not found and exit 1 for a missing target (V-4), and detect the skill tick as the literal substring only (V-5). | planned | - | - | TEST-3201, TEST-3202 |
| Spec-AC-02 | The validate-skills launchers are thin: each at most its D3 line cap, ASCII only, naming validate-skills.mjs, holding none of the REQUIRED names; through bash and pwsh -File on the same fixtures they give equal stdout, stderr and exit code, and without node or without the module each prints exactly the V-7 line on stderr and exits 1. | planned | - | - | TEST-3203, TEST-3204, TEST-3205 |
| Spec-AC-03 | WHEN aai-live.mjs runs the system SHALL resolve the opener and the open target per L-1, L-2, L-5 and L-6, refuse before generating when no opener resolves (L-3), suppress warm-up output (L-4), open the target only after a zero generator exit and never under --data-only (L-12), forward SIGINT and SIGTERM to the watch child and exit with its code (L-8), and run the generator from the module's real repository root (L-9). | planned | - | - | TEST-3206, TEST-3207, TEST-3208 |
| Spec-AC-04 | The aai-live launchers are thin: each at most its D3 line cap, ASCII only, naming aai-live.mjs, holding none of open, xdg-open, Start-Process, --output parsing or the warm-up; without node or without the module each prints exactly the L-11 line and exits 1; under pwsh a .cmd opener in a path with a space receives the output path as one argument. | planned | - | - | TEST-3209, TEST-3210 |
| Spec-AC-05 | The pre-existing tests of the three pairs pass on the changed tree: live-status TEST-027, TEST-031 and TEST-037, the sh self-hosting smoke, and the ps1 smoke's validate-skills call now fails the smoke on a non-zero exit. | planned | - | - | TEST-3211, TEST-3212 |
| Spec-AC-06 | pre-compact-save.sh and pre-compact-save.ps1 are absent; PROFILES.yaml has no pre-compact-save entry; outside docs, CHANGELOG and docs/ai no tracked file names pre-compact-save except aai-doctor.mjs and test-aai-doctor.sh. | planned | - | - | TEST-3213 |
| Spec-AC-07 | WHEN aai-doctor runs on a fixture root the system SHALL report CAT-09 PASS with no settings file, WARN naming the file when .claude/settings.json or .claude/settings.local.json names pre-compact-save and no copy exists, and PASS when a copy exists; SPEC-0100 TEST-009 is adjusted to this and its amendment record is recorded (unsigned, signed by the owner's merge). | planned | - | - | TEST-3214, TEST-3215 |
| Spec-AC-08 | WHEN aai-sync --profile extended installs into a target with a space in its path the system SHALL let the target's own validate-skills.sh and aai-live.sh run from that target (exit 0, opener stub sees the written page), preserve a pre-existing target copy of pre-compact-save.sh, and a core-profile target SHALL hold neither module. | planned | - | - | TEST-3216 |
| Spec-AC-09 | Both modules are classified once in the extended PROFILES list, select-suites maps every new or moved path to its suite without a full run, and the two ps1-quality path lists name both modules and stay identical. | planned | - | - | TEST-3217, TEST-3218, TEST-3219 |
| Spec-AC-10 | The wc -l sum of the four launchers and two modules is at most 230 (481 before) and equals the number recorded in the RFC-0017 slice paragraph. | planned | - | - | TEST-3220 |
| Spec-AC-11 | The RFC-0017 inventory equals the pair set of the tree (SPEC-0249 TEST-2624 exits 0), lists none of aai-live, pre-compact-save and validate-skills, carries the slice paragraph with a link ending node-first-small-pairs.md, and SPEC-0249 TEST-2623 (phase 3 done, umbrella implementing) still exits 0. | planned | - | - | TEST-3221 |

## Implementation plan

1. RED: write `tests/skills/lib/validate-skills.test.mjs`,
   `tests/skills/lib/aai-live.test.mjs`, `tests/skills/validate-skills.Tests.ps1`,
   `tests/skills/aai-live.Tests.ps1`, the new suite
   `tests/skills/test-aai-validate-skills.sh` and the new functions in
   test-aai-live-status.sh and test-aai-doctor.sh; run each row's function
   alone on the unchanged tree and store the output under
   `docs/ai/tdd/node-first-small-pairs/red/`.
2. Write the two modules (D1, D2): TEST-3201, TEST-3202, TEST-3206 to TEST-3208
   go green.
3. Replace the four scripts with launchers and adjust the three fixtures (D3,
   D4): TEST-3203 to TEST-3205, TEST-3209 to TEST-3212 go green.
4. Retire pre-compact-save, rewrite CAT-09, adjust doctor TEST-009 and append
   the SPEC-0100 amendment record: TEST-3213 to TEST-3215.
5. Wiring and RFC (D4, D5): TEST-3216 to TEST-3221.
6. Mutation records per row, then the Verification list.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3201 | Spec-AC-01 | unit | tests/skills/test-aai-validate-skills.sh | test_3201_required_and_first_missing runs node --test --test-name-pattern TEST-3201 on tests/skills/lib/validate-skills.test.mjs: REQUIRED equals the twelve paths of the baseline copy in order; a full fixture gives exit 0 and the four bash lines; a fixture missing SKILL_TDD and SKILL_SHARE gives exit 1, one stderr line naming SKILL_TDD only; a directory at SKILL_TDD gives the same exit 1 line; the wrapper fails on zero passing tests | `sed:s/return statSync\(p\)\.isFile\(\);/return true;/` on .aai/scripts/validate-skills.mjs | pending |
| TEST-3202 | Spec-AC-01 | unit | tests/skills/test-aai-validate-skills.sh | test_3202_warnings_and_target runs the TEST-3202 node cases: a required-only fixture gives the two WARN lines with the bash texts on out and nothing on err; a tick log without a skill entry gives the no-skill-mode WARN; the CRLF tick log with a space after the colon also gives it; a missing target gives exit 1 and exactly ERROR: Target not found: plus the argument | `sed:s/const WARN = 'WARN: ';/const WARN = 'WARNING: ';/` on .aai/scripts/validate-skills.mjs | pending |
| TEST-3203 | Spec-AC-02 | inspection | tests/skills/test-aai-validate-skills.sh | test_3203_vs_launchers_thin checks both validate-skills launchers: no byte above 0x7E, at most 10 and 15 lines, a reference to validate-skills.mjs, no SKILL_ token, the V-7 line exactly once, the sh file executable | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" "$@" # SKILL_TDD/` on .aai/scripts/validate-skills.sh | pending |
| TEST-3204 | Spec-AC-02 | integration | tests/skills/test-aai-validate-skills.sh | test_3204_vs_launcher_parity runs five fixtures (full, required-only, one missing, directory at a required path, missing target) through bash validate-skills.sh TARGET and pwsh -File validate-skills.ps1 -TargetRoot TARGET and compares stdout, stderr and exit code (pwsh is on the hosted Linux runner, as SPEC-0249 TEST-2616 relies on); then both launchers with PATH holding bash and dirname only (positive control: command -v node fails) and a copy without the module print exactly the V-7 line and exit 1 | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/validate-skills.ps1 | pending |
| TEST-3205 | Spec-AC-02 | integration | tests/skills/test-aai-validate-skills.sh | test_3205_pester_validate_skills runs Invoke-Pester on tests/skills/validate-skills.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 4 (cases: full fixture exit 0, missing file line and exit 1, positional target, launcher copy without the module gives the V-7 line), each case launching the launcher with the engine running the test | `sed:s/param\(\[string\]\$TargetRoot/param([string]$Target/` on .aai/scripts/validate-skills.ps1 | pending |
| TEST-3206 | Spec-AC-03 | unit | tests/skills/test-aai-live-status.sh | test_3206_live_resolvers runs node --test --test-name-pattern TEST-3206 on tests/skills/lib/aai-live.test.mjs: resolveOutputPath gives the default under root, the last --output value, a relative value under root and an absolute value unchanged; warmupArgs drops every --watch and keeps order; resolveOpener honours AAI_LIVE_OPENER on linux and win32, finds open before xdg-open on a fixture PATH, returns null on an empty PATH, gives explorer.exe on win32, and marks a .CMD or .bat override on win32 as shell with both parts double-quoted | `sed:s/const CANDIDATES = \['open', 'xdg-open'\];/const CANDIDATES = ['xdg-open', 'open'];/` on .aai/scripts/aai-live.mjs | pending |
| TEST-3207 | Spec-AC-03 | integration | tests/skills/test-aai-live-status.sh | test_3207_live_oneshot_paths runs node aai-live.mjs from a scratch root (launcher, module, generator, parsers, libs copied; HOME and harness overrides at an empty fixture) with an opener stub that logs EXISTS or MISSING and its argument: --output custom/page.html logs EXISTS for the absolute path; --data-only logs nothing; an empty PATH without override refuses with the L-3 line, exit 1, and no live-status.json written; a generator stub that exits 3 gives exit 3 and no open; a missing generator gives the L-10 line and exit 1; a --watch warm-up whose generator stub writes to stderr leaks nothing to the launcher's stderr before the watch child starts | `sed:s/const dataOnly = args\.includes\('--data-only'\);/const dataOnly = false;/` on .aai/scripts/aai-live.mjs | pending |
| TEST-3208 | Spec-AC-03 | integration | tests/skills/test-aai-live-status.sh | test_3208_watch_signal_forwarding starts bash aai-live.sh --watch --interval 1 in the background from a scratch root reached through a symlinked directory, waits for the opener log (EXISTS), sends SIGTERM to the launcher pid only, and requires the launcher to exit 0 within 5 s, no generate-live-status.mjs process of that scratch root left (pgrep -f on the scratch path), and the written page under the real root; positive control: the generator child is observed running before the signal | `sed:s/process\.on\(sig, \(\) => child\.kill\(sig\)\)/process.on(sig, () => {})/` on .aai/scripts/aai-live.mjs | pending |
| TEST-3209 | Spec-AC-04 | inspection | tests/skills/test-aai-live-status.sh | test_3209_live_launchers_thin checks both aai-live launchers: no byte above 0x7E, at most 10 and 15 lines, a reference to aai-live.mjs, none of the tokens xdg-open, Start-Process, --output, WARMUP, the L-11 line exactly once; then bash aai-live.sh with PATH holding bash and dirname only (positive control first) and a copy without the module print exactly the L-11 line and exit 1 | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" "$@" # xdg-open/` on .aai/scripts/aai-live.sh | pending |
| TEST-3210 | Spec-AC-04 | integration | tests/skills/test-aai-live-status.sh | test_3210_pester_aai_live runs Invoke-Pester on tests/skills/aai-live.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 4 (cases: one-shot --output with AAI_LIVE_OPENER naming a stub in a directory whose name holds a space gets exactly one argument equal to the absolute page path, on Windows a .cmd stub and elsewhere a shell stub; --data-only opens nothing; a launcher copy without the module gives the L-11 line and exit 1; the generator's exit code is forwarded) | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/aai-live.ps1 | pending |
| TEST-3211 | Spec-AC-05 | integration | tests/skills/test-aai-validate-skills.sh | test_3211_existing_tests_pass runs bash tests/skills/test-aai-live-status.sh with test_027_opener_refusal, test_031_watch_warmup_opens_existing_html and the TEST-037 function (each exit 0) and bash tests/self-hosting/test-self-hosting-smoke.sh (exit 0, PASS line) | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" --no-such-flag "$@"/` on .aai/scripts/validate-skills.sh | pending |
| TEST-3212 | Spec-AC-05 | integration | tests/skills/test-aai-validate-skills.sh | test_3212_ps1_smoke_checks_exit extracts the Assert-AaiInstalled validate-skills call block from tests/self-hosting/test-self-hosting-smoke.ps1, runs it under pwsh against a fixture missing SKILL_TDD with a launcher copy, and requires a thrown error (non-zero pwsh exit); positive control: the same block against the full fixture exits 0 | `sed:s/if \(\$LASTEXITCODE -ne 0\)/if ($false)/` on tests/self-hosting/test-self-hosting-smoke.ps1 | pending |
| TEST-3213 | Spec-AC-06 | inspection | tests/skills/test-aai-validate-skills.sh | test_3213_pre_compact_retired requires both pre-compact-save files absent, no pre-compact-save line in PROFILES.yaml, and git ls-files outside docs/, CHANGELOG.md naming pre-compact-save only in .aai/scripts/aai-doctor.mjs and tests/skills/test-aai-doctor.sh; positive control: a fixture list with an extra naming file is reported | `sed:s/^# \.aai\/system\/PROFILES\.yaml /# pre-compact-save .aai\/system\/PROFILES.yaml /` on .aai/system/PROFILES.yaml | pending |
| TEST-3214 | Spec-AC-07 | integration | tests/skills/test-aai-doctor.sh | test_3214_cat09_retired_hook runs node aai-doctor.mjs --root on four fixtures: no settings gives CAT-09 PASS; .claude/settings.local.json with a PreCompact command naming bash .aai/scripts/pre-compact-save.sh and no copy gives WARN naming settings.local.json; the same in .claude/settings.json gives WARN naming settings.json; with a copy of pre-compact-save.sh present gives PASS | `sed:s/const RETIRED_HOOK = 'pre-compact-save';/const RETIRED_HOOK = 'pre-compact-gone';/` on .aai/scripts/aai-doctor.mjs | pending |
| TEST-3215 | Spec-AC-07 | integration | tests/skills/test-aai-doctor.sh | test_3215_test009_amended runs bash tests/skills/test-aai-doctor.sh test_009_cat09_precompact (exit 0) and node .aai/scripts/spec-amend.mjs list --json and requires a contract record of ref doctor-determinize whose what begins TEST-009, regardless of owner_signoff | `sed:s/"what":"TEST-009/"what":"TEST-gone/` on docs/ai/decisions.jsonl | pending |
| TEST-3216 | Spec-AC-08 | e2e | tests/skills/test-aai-validate-skills.sh | test_3216_downstream_extended_sync seeds TEST_DIR/target with space with an old .aai/scripts/pre-compact-save.sh, runs .aai/scripts/aai-sync.sh --profile extended into it, requires validate-skills.mjs and aai-live.mjs there and the PRESERVE line plus the old pre-compact-save.sh kept; runs the target's bash .aai/scripts/validate-skills.sh on the target (exit 0, Skill validation completed.) and the target's aai-live.sh --output x.html with the opener stub and an empty --home (exit 0, stub logs EXISTS for the target's x.html); then a --profile core target holds neither module | `sed:s/\/validate-skills\.mjs"/\/validate-skills-gone.mjs"/` on .aai/scripts/validate-skills.sh | pending |
| TEST-3217 | Spec-AC-09 | inspection | tests/skills/test-aai-validate-skills.sh | test_3217_profiles_classified requires .aai/scripts/validate-skills.mjs and .aai/scripts/aai-live.mjs exactly once each in PROFILES.yaml, inside the extended list (the whole-tree classification check stays with test-aai-layer-profiles.sh in Verification) | `sed:s/aai-live\.mjs/aai-live-gone.mjs/` on .aai/system/PROFILES.yaml | pending |
| TEST-3218 | Spec-AC-09 | integration | tests/skills/test-aai-validate-skills.sh | test_3218_suite_map_selects feeds each new path to node .aai/scripts/select-suites.mjs --files-from - : the three validate-skills paths and the two test files select aai-validate-skills, aai-live.mjs and its two test files select aai-live-status, and no output holds a FULL_RUN line | `sed:s/\.aai\/scripts\/aai-live\.mjs/.aai\/scripts\/aai-live-gone.mjs/` on tests/skills/suite-map.yaml | pending |
| TEST-3219 | Spec-AC-09 | inspection | tests/skills/test-aai-validate-skills.sh | test_3219_ps1_quality_paths extracts the push and pull_request path lists of .github/workflows/ps1-quality.yml and requires both to name .aai/scripts/validate-skills.mjs and .aai/scripts/aai-live.mjs and to be identical | `sed:s/validate-skills\.mjs/validate-skills-gone.mjs/` on .github/workflows/ps1-quality.yml | pending |
| TEST-3220 | Spec-AC-10 | inspection | tests/skills/test-aai-validate-skills.sh | test_3220_line_budget parses three pairs 481 to N lines from the RFC-0017 slice paragraph and requires N to equal the live wc -l sum of the four launchers and two modules and to be at most 230 | `sed:s/three pairs 481 to (\d+) lines/three pairs 481 to 1$1 lines/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |
| TEST-3221 | Spec-AC-11 | inspection | tests/skills/test-aai-validate-skills.sh | test_3221_rfc_inventory runs bash tests/skills/test-aai-expert-fetch.sh test_2624_inventory_matches_tree and test_2623_rfc_phase3_done (each exit 0), then requires no inventory row for aai-live, pre-compact-save or validate-skills and a paragraph after the table whose link ends node-first-small-pairs.md | `sed:s/\(\.\.\/issues\/CHANGE-DRAFT-node-first-small-pairs\.md\)/(..\/issues\/CHANGE-DRAFT-node-first-gone.md)/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |

Test counts by type: unit 3, integration 11, inspection 6, e2e 1 (21).

Seams crossed (Principle 2): sh launcher to module to generator process
(TEST-3207, TEST-3208, TEST-3211); ps1 launcher under the engine running the
test to module (TEST-3204, TEST-3205, TEST-3210); aai-sync install to the
target's own launchers and the preserved retired script (TEST-3216); doctor
reading a settings file a user or harness wrote (TEST-3214); the RFC
inventory read by SPEC-0249's checks (TEST-3221); the ps1 smoke reading the
launcher's exit code (TEST-3212); select-suites reading the suite map
(TEST-3218).

### RED observations and positive controls

- TEST-3201, TEST-3202, TEST-3206: RED on the baseline, the module does not
  exist; the wrapper's zero-passing-tests guard makes a missing name RED.
- TEST-3203, TEST-3209: RED on the baseline (logic tokens and length in the
  current scripts; aai-live.sh holds non-ASCII bytes).
- TEST-3204: RED on the baseline through V-1, V-2, V-3 and V-4 (stderr and
  stdout differ, the directory case exits 0 under ps1). TEST-3205 and
  TEST-3210: RED on the baseline (no needs-node line; ps1 aai-live ignores the
  opener override).
- TEST-3207, TEST-3208: RED on the baseline (no module to run).
- TEST-3211: passes on the baseline; its RED is the mutation record.
- TEST-3212: passes on the baseline, because the old ps1 copy throws; its RED
  is observed after the launcher swap and before the smoke edit (the block
  exits 0 over a missing file), stored under red/, then the mutation record.
- TEST-3213 to TEST-3215: RED on the baseline (files present; CAT-09 checks
  presence; no amendment record).
- TEST-3216: RED on the baseline (no modules in the target).
- TEST-3217 to TEST-3221: RED on the baseline (entries, rows, paragraph
  absent; the inventory still lists the three pairs only after the modules
  land, which TEST-2624 then reports as extra names).

## Verification

- New suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-validate-skills.sh` exits 0.
- Live status: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-live-status.sh` exits 0.
- Doctor: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh` exits 0.
- Expert-fetch (inventory and phase 3 checks): `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-expert-fetch.sh` exits 0.
- Layer profiles, suite selection, hygiene pack, Windows-fallback pins:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`
  for test-aai-layer-profiles, test-aai-suite-select, test-aai-hygiene-pack and
  test-aai-win-fallback, each exit 0.
- Self-hosting smoke: `bash tests/self-hosting/test-self-hosting-smoke.sh` exits 0.
- Direct Node tests: `node --test tests/skills/lib/validate-skills.test.mjs tests/skills/lib/aai-live.test.mjs` exits 0 under local Node 22.
- PowerShell gate: `bash tests/skills/test-ps1-quality.sh` exits 0 locally (PSScriptAnalyzer and full Pester discovery, SkippedCount 0).
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records per row with `node .aai/scripts/mutation-run.mjs`, then `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- No full sweep while the precise-suite-evidence-reuse ride runs one (intake constraint).

### Hosted delivery checks (after PR creation, before merge-readiness)

Not Spec-ACs and not claimed by local Validation; Windows parity (intake
AC-002) is proven only here.

- H1: on the PR head the ps1-quality run concludes success for `gate`,
  `windows-5_1` and `windows-wsl1`; in both Pester discovery steps of
  `windows-5_1` (5.1 and pwsh 7) every case of validate-skills.Tests.ps1 and
  aai-live.Tests.ps1 is listed passed and the skipped count still equals
  `AAI_EXPECTED_WIN_SKIP_COUNT`. A hosted-only failure is diagnosed with a
  probe (arguments Node received, stdout and stderr bytes in hex,
  `$LASTEXITCODE`) before any code change, and the change is recorded as an
  amendment.
- H2: the skill-suite run concludes success with `aai-validate-skills` and
  `aai-live-status` selected or a full run, the `self-hosting-smoke` job green
  and the Node 22 compatibility step passing.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/node-first-small-pairs/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the
Verification list. H1 and H2 are recorded separately after PR creation.
Planning's measurements above are inputs, not attestations.

## Risks and rollback

- Windows behavior of the opener (L-2 explorer.exe, L-6 .cmd quoting) and of
  Ctrl+C forwarding under the watch child cannot be proven on a local host;
  H1 covers the Pester cases, and Ctrl+C on a Windows console (which signals
  every attached process) is a residual risk checked by inspection only.
- A user who hand-wired the PreCompact hook in a fresh install made after this
  change gets a missing-script hook error from the harness; doctor CAT-09
  names the entry to remove, and existing installs keep their preserved copy.
- SPEC-0249 TEST-2624's recorded mutation renames the `validate-skills` row,
  which no longer exists; its stored mutation record stays valid evidence for
  that closed spec, but a future replay of that one row would not apply. This
  is disclosed, not amended (the row itself still passes).
- The SPEC-0100 amendment is recorded unsigned (`--signoff none`, the autopilot
  default) citing the owner's intake answer as authority; the canon assigns the
  sign-off to the owner, whose merge direction signs it (SKILL_SHIP default 5).
- Changing shipped scripts is consumer-visible: merge stays with the owner.
- Rollback is one revert of the scope's files plus the amendment record's
  disclosure.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list` (270 open) holds no item on
validate-skills, aai-live, pre-compact-save, CAT-09 or the remaining-pairs
inventory. Related but left open: `fu-ps1-quality-outside-sweep-glob`
(test-ps1-quality.sh still runs only in Verification and H1) and
`fu-ps1-writeerror-terminates-before-exit` (this scope removes no instance of
that class in its named file).

Registry items closed by this scope: none.
