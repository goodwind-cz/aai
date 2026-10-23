---
id: spec-node-first-second-slice
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: c32089f5ef0ba77ada8c160d442728b4c142353facd9d82f20d9eca78fd176cd
ceremony_level: 2
links:
  requirement: node-first-second-slice
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the L1 triage snapshot from paired Bash and PowerShell scripts to one Node module

SPEC-FROZEN: true

## Links

- Requirement: [Second Node-first slice of paired sync/hook scripts](../issues/CHANGE-DRAFT-node-first-second-slice.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  Proposal section 1 and owner decisions 1.5 (phases 3 to 5 in order), 2 (Node
  22 floor downstream, Node 24 CI) and 4 (no new runner).
- Pattern precedent: [SPEC-0247](SPEC-0247-spec-node-first-sync-hook-slice.md)
  (live-spool), including its D2 disclosure on the Windows PowerShell 5.1 BOM.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no dependencies).
- Baseline: main `8df911c5`; the ride branch adds only the intake and the #495
  sign-off records (`d27c8b61`).

## Implementation strategy

- Strategy: hybrid
- Rationale: the new module and the two launchers are new behavior with
  recorded drift decisions, so every row that gates them goes RED first on the
  baseline (the module does not exist; each old copy fails at least one drift
  case) and carries a mutation record (TDD). The wiring edits (PROFILES, suite
  map, the ps1-quality path filter, the RFC row) are mechanical and done in
  loop mode, but each one is pinned by a mutation-gated row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped core scripts, a CI workflow
  and the vendored profile manifest; the ride already runs in its own linked
  worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: change/node-first-second-slice at /private/tmp/aai-node-first-2
- Inline review scope: .aai/scripts/triage.mjs; .aai/scripts/triage.sh;
  .aai/scripts/triage.ps1; .aai/system/PROFILES.yaml;
  .github/workflows/ps1-quality.yml; tests/skills/suite-map.yaml;
  tests/skills/test-aai-triage.sh; tests/skills/lib/triage.test.mjs;
  tests/skills/triage.Tests.ps1; tests/skills/test-aai-layer-profiles.sh;
  tests/skills/suite-weights.tsv (only if the selector asks for a row);
  tests/skills/lib/cd-subshell-leak-baseline.tsv (only if the checker asks for a re-record);
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md; CHANGELOG.md;
  docs/issues/CHANGE-DRAFT-node-first-second-slice.md; this spec.
- Code review required: true.

## Pair selection (measured)

Measured on the planning tree (macOS arm64, bash with `/usr/bin/grep`, Node
22.23.1, pwsh 7.6.3) on 2026-10-23. Lines are `wc -l`. Commits are
`git log --oneline -- <file>`; "joint" counts commits touching both copies and
"one-sided" counts commits that changed one copy's content only. Callers are
tracked files outside docs/ai, specs, issues, RFCs, analysis and CHANGELOG that
name the `.sh` or `.ps1` file. Drift cases are the probes listed below each
verdict, run on both copies with the same fixtures.

| Pair | Lines sh/ps1 | Commits sh/ps1 (joint, one-sided) | Callers | When it runs | Node today | Existing executing tests | Drift cases (measured + inspected, exit-code) | Verdict |
|---|---|---|---|---|---|---|---|---|
| triage | 73/67 = 140 | 2/2 (1, 2: 94a983ec sh-only pipefail fix, ee492fbd ps1-only ASCII sweep) | 5, none executing (PROFILES x2, cd-subshell baseline, two hygiene comments) | manual or scheduled L1 snapshot, `--check` as a CI gate | optional: the docs-audit step, the only check that can raise the verdict, is skipped without Node | none | 5 measured + 2 inspected, 1 exit-code drift (D-4) | CHOSEN |
| validate-skills | 47/55 = 102 | 5/3 (3, 2 sh-only: 377e688b, afc688df mode bit) | 5 (self-hosting smoke sh and ps1) | every CI run: the self-hosting smoke calls the sh copy twice (Node 24 and Node 22 steps); the ps1 smoke is run by no workflow | no | sh copy through the self-hosting smoke | 3 measured, 0 exit-code drift (WARN on stdout against Write-Warning, error text, missing-target text) | runner-up, rejected: twelve file-existence checks, less logic than live-spool (133), and its drift is cosmetic only |
| pre-compact-save | 77/87 = 164 | 1/1 (1, 0) | 8 (doctor checks file presence only) | PreCompact hook, wired by no shipped template | no | none | 2 measured + 3 inspected (5.1 BOM, CRLF, native stderr under Stop) | rejected: no install wires it, so the slice would move code nobody runs and add a Node dependency to a hook that has none |
| migrate-yaml-to-jsonl | 126/151 = 277 | 2/2 (2, 0) | 6 (called by aai-canonicalize) | one-off migration | no; both copies need python3 and PyYAML | none | not probed | rejected: needs a general YAML parser, which Node's stdlib lacks; one-off |
| pre-commit-checks | 323/281 = 604 | 7/6 (6, 1) | 27 | every commit | optional: checks 1 to 7 run without Node | many | not probed | disqualified: L3 protected surface (`protected_paths_l3`) and a pre-Node degrade path |
| aai-update | 180/188 = 368 | 7/7 (5, 2) | 16 | every downstream update | optional: prints `DOCTOR-REPORT SKIP node missing - update unaffected` | bash suite and Pester | not probed | disqualified: a caller runs before Node is installed |

Why triage:

- It has more logic than live-spool (140 lines against 133): four report
  sections, two child processes (git and docs-audit), argument parsing and an
  exit-code gate. This is the property the intake wants the second slice to test.
- Its only verdict-raising check already needs Node (docs-audit is a Node
  script), so moving the logic removes no capability. Today a host without Node
  gets `### Triage verdict: CLEAN` after skipping the only real check; the slice
  replaces that with an explicit `UNKNOWN` (D-8).
- Its history shows the cost the RFC names: two of its three commits fixed one
  copy only, and the copies now disagree on five measured cases, one of which
  changes the `--check` exit code (D-4).
- No caller runs before Node is installed: nothing in the repository executes
  it, and the documented use is a manual or scheduled health check in an AAI
  project, whose tooling is Node (docs/TECHNOLOGY.md).
- It has no platform-specific content besides calling git.
- It is listed in the `core:` profile, so it is installed everywhere and the
  slice must also prove the core install carries the module (Spec-AC-07).

What it does not show: it runs rarely compared with validate-skills, which runs
in every CI run. validate-skills was rejected because it has almost no logic and
no exit-code drift. The evidence is not evenly split, so no owner question is
raised.

## Drift between the two copies (measured) and decisions

Both copies were run on the same fixture repositories (a git repository holding
copies of both scripts and, where named, a stub `.aai/scripts/docs-audit.mjs`
that prints fixed lines), under bash with Node 22.23.1 and under pwsh 7.6.3.
Windows PowerShell 5.1 was not available to Planning; rows marked "by
inspection" were read from the code.

| Id | Case | Bash copy | PowerShell copy | Decision |
|---|---|---|---|---|
| D-1 | header and state-absent separator | U+2014 em dash (`## AAI L1 Triage — <ts>`) | ASCII hyphen | ASCII hyphen. The ps1 copy was ASCII-swept for Windows PowerShell 5.1 (ee492fbd); the module's own text is ASCII only. |
| D-2 | `project_status:` with no value (or `project_status:active`) | `project_status=unknown` | `project_status=` | `unknown` |
| D-3 | STATE.yaml starting with a UTF-8 BOM | `State: not present yet` (grep `^` misses the BOM) | `State: present (project_status=active)` | strip one leading BOM from STATE.yaml and LOOP_TICKS.jsonl before reading them. A 5.1 `Set-Content -Encoding UTF8` writes exactly such a file. |
| D-4 | docs-audit output in another case (`### verdict: needs-triage`, `- mode: quick`) | lines not shown; CLEAN; `--check` exit 0 | lines shown; NEEDS-ATTENTION; `-Check` exit 1 (`Select-String` is case-insensitive) | case-sensitive, as docs-audit prints the exact upper-case marker |
| D-5 | LOOP_TICKS.jsonl with CRLF line ends | `Last tick:` line ends with CR | CR removed | remove one trailing CR from the last tick |
| D-6 | output encoding and line ends on Windows (by inspection) | UTF-8, LF | 5.1 re-encodes docs-audit's output through the console code page (its verdict line holds an em dash) and writes CRLF when redirected | Node writes the report as UTF-8 with LF; the ps1 launcher does not capture Node's output |
| D-7 | flag spelling | `--check` only | `-Check`; pwsh 7 also binds `--check` to `-Check` (measured); 5.1 by inspection unknown | the module accepts `--check`; the ps1 launcher passes `--check` to Node when it receives `-Check` or a literal `--check` |
| D-8 | Node absent | full report, `Docs audit: skipped`, CLEAN, exit 0 | same | each launcher prints exactly `### Triage verdict: UNKNOWN (node or triage.mjs unavailable)` and exits 0, also under `--check` (exit code unchanged, verdict now honest) |
| D-9 | Node present, docs-audit.mjs absent | `- Docs audit: skipped (node or docs-audit.mjs unavailable)`, CLEAN | same | unchanged |
| D-10 | `NEEDS-TRIAGE` anywhere in the audit output, also outside the verdict line | counts as an issue | same | unchanged (shared behavior; suggested follow-up) |
| D-11 | docs-audit exits non-zero without a verdict line | CLEAN, `--check` exit 0 | same | unchanged (shared behavior; suggested follow-up) |
| D-12 | root is not a git repository | `Working tree: clean` | same under pwsh 7; 5.1 by inspection may raise on git's stderr under `Stop` | `Working tree: clean` (shared output kept); git's stderr is discarded by the module, so no host can raise |
| D-13 | timestamp, tick tail, porcelain count, unknown arguments | `%Y-%m-%dT%H:%M:%SZ`; last line; one per porcelain line; ignored | same | unchanged |

The module reads no standard input. Its only external text inputs are the two
files above (D-3 handles a BOM there) and the child processes' standard output.

## Scope and design

### D1. The module `.aai/scripts/triage.mjs`

Dependency-free ESM, Node 22 compatible (only `node:fs`, `node:path`,
`node:url`, `node:child_process`), at most 110 lines, ASCII only. Importing it
has no side effects. It never reads standard input and never writes a file. It
contains these exact lines (mutation anchors):

```js
export const ATTENTION_MARKER = 'NEEDS-TRIAGE';
const BOM = String.fromCharCode(0xfeff);
const UNKNOWN_STATUS = 'unknown';
const check = argv.includes('--check');
const value = match.split(/\s+/)[1] ?? '';
const attention = output.includes(ATTENTION_MARKER);
const header = '## AAI L1 Triage - ' + stampUtc(now);
const tick = stripCr(last);
const lines = [header, '', stateLine(stateText), treeLine(porcelain), tickLine(ticksText), ''];
const exitCode = issues > 0 && check ? 1 : 0;
process.exitCode = runTriage({ argv: process.argv.slice(2) });
```

No comment in the module may contain the text `AAI L1 Triage - ` (TEST-2502's
mutation edits the first occurrence).

Exports (pure functions take text, not paths, so `node:test` needs no fixture
repository):

- `parseArgs(argv)` returns `{ check }`.
- `stampUtc(now)` returns `now.toISOString()` with the milliseconds removed
  (`2026-10-23T21:58:07Z`).
- `stateLine(stateText)`: `stateText` is the file's text with one leading BOM
  removed, or `null`. The first line (split on LF, CR removed) matching
  `^project_status:` gives `value`; an empty value prints `UNKNOWN_STATUS`. No
  match or `null` prints
  `- State: not present yet (docs/ai/STATE.yaml) - orchestrator will init, or run /aai-check-state`.
- `treeLine(porcelain)`: the count of non-empty lines, or `- Working tree: clean`
  for `null` or an empty string.
- `tickLine(ticksText)`: `null` or empty prints `- Last tick: none recorded`;
  otherwise the last line (a final empty line from the trailing LF is dropped),
  through the `stripCr` helper.
- `auditSection(output)`: `null` gives the D-9 skipped line and no attention;
  otherwise the lines matching `^- (Mode`, `Scanned`, `Tracked):` or
  `^### Verdict:` (case-sensitive), or `- Docs audit: (no output)` when none
  match, and `attention` from the anchored line.
- `buildReport({ now, check, stateText, porcelain, ticksText, auditOutput })`
  returns `{ text, exitCode }`: `lines`, then the audit lines, a blank line and
  `### Triage verdict: CLEAN` or `### Triage verdict: NEEDS-ATTENTION (1 area(s))`;
  lines joined with LF plus a final LF.
- `runTriage({ argv, root, now, stdout })`: `root` defaults to two directories
  above the module's own directory (never the caller's cwd), as both copies do
  today. It reads the two files under `root/docs/ai/`, runs
  `git status --porcelain` and, when `root/.aai/scripts/docs-audit.mjs` exists,
  `process.execPath` on it with `--quick`, both with `spawnSync`, `cwd: root`,
  stdin and stderr ignored. git's output counts only when it exits 0
  (otherwise `null`); docs-audit's standard output counts whatever its exit
  code (as `|| true` does today, D-11). It writes `text` to `stdout` and
  returns `exitCode`.

CLI: when run as the main module (real path of `process.argv[1]` equals the real
path of `fileURLToPath(import.meta.url)`), the anchored `process.exitCode` line
runs. It sets the exit code instead of calling `process.exit`, so a piped
standard output is flushed before Node exits.

### D2. The launchers

Both keep their names and flags. Each is ASCII only and at most 14 lines, and
holds none of these tokens: `project_status`, `LOOP_TICKS`, `STATE.yaml`,
`porcelain`, `docs-audit`, `NEEDS-`, `CLEAN`, `Select-String`, `grep`, `tail`,
`awk`. The literal `### Triage verdict: UNKNOWN (node or triage.mjs unavailable)`
appears exactly once, in the fallback. The fallback runs when Node is absent or
the module file is absent; it never reads standard input.

`triage.sh`, shape (the anchored lines are exact):

```bash
#!/usr/bin/env bash
# AAI L1 Triage launcher; the logic lives in triage.mjs (RFC-0017 phase 3).
# Usage: ./.aai/scripts/triage.sh [--check]
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/triage.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "### Triage verdict: UNKNOWN (node or triage.mjs unavailable)"
exit 0
```

`triage.ps1`, shape (the anchored lines are exact):

```powershell
#!/usr/bin/env pwsh
# AAI L1 Triage launcher; the logic lives in triage.mjs (RFC-0017 phase 3).
# Usage: ./.aai/scripts/triage.ps1 [-Check]
param([switch]$Check)
$Module = Join-Path $PSScriptRoot 'triage.mjs'
$NodeArgs = @()
if ($Check -or ($args -contains '--check')) { $NodeArgs += '--check' }
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @NodeArgs
  exit $LASTEXITCODE
}
Write-Output '### Triage verdict: UNKNOWN (node or triage.mjs unavailable)'
exit 0
```

The PowerShell launcher sets no `$ErrorActionPreference` and lets Node write to
the inherited standard output, so PowerShell neither raises on a native
command's stderr nor re-encodes the report. Node exceptions (a module that fails
to load) propagate as Node's non-zero exit, which `--check` callers see as a
failure: a broken gate must not read as clean.

Windows parity lesson from SPEC-0247 (binding here): any module of this program
that reads standard input must tolerate one leading UTF-8 BOM, because a .NET
Framework writer (the Windows PowerShell 5.1 Pester harness among them) prefixes
EF BB BF to a child's redirected standard input. This module reads none
(TEST-2508 pins that), and applies the same rule to the two files it reads
(D-3). A failure seen only on the hosted Windows job is diagnosed with a probe
before any code change (see H1).

### D3. Wiring

- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/triage.mjs` in the `core:` list
  next to the two launchers (they are core, so the module must be too, or a core
  install would print `UNKNOWN`). Companion obligation for a new `.aai/**` file.
- `tests/skills/suite-map.yaml`: a new suite row `aai-triage` with the globs
  `.aai/scripts/triage.sh`, `.aai/scripts/triage.ps1`, `.aai/scripts/triage.mjs`,
  `tests/skills/lib/triage.test.mjs` and `tests/skills/triage.Tests.ps1` (today
  `.aai/scripts/triage.sh` maps to `FULL_RUN reason=unmapped`). The hygiene pin
  requires the row for the new `test-aai-triage.sh`.
- `.github/workflows/ps1-quality.yml`: add `'.aai/scripts/triage.mjs'` to both
  the `push` and the `pull_request` path lists, which must stay identical. No
  job, runner or step is added (RFC-0017 decision 4). No comment naming the
  module may precede the `push` list. The new Pester file is discovered by the
  existing `Run.Path = 'tests/skills'` steps under Windows PowerShell 5.1 and
  pwsh 7 in `windows-5_1`, under 5.1 in `windows-wsl1`, and under pwsh 7 on
  Linux in `gate`.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-record with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record` only if the checker
  reports the `triage.sh` count changed.
- `tests/skills/suite-weights.tsv`: add a row only if `test-aai-suite-select.sh`
  requires one for every suite.

### D4. Tests

- `tests/skills/lib/triage.test.mjs` (`node:test`, direct imports, temp
  directories only). Every test name starts with its TEST id.
- `tests/skills/test-aai-triage.sh`, a new suite: one function per row, each
  registered once in `main()`, each failure message naming its TEST id, runnable
  alone (`bash tests/skills/test-aai-triage.sh <function>`). Fixtures are
  temporary git repositories built with `git init -b main` and their own
  `user.email`/`user.name`, holding copies of the launchers and the module under
  `.aai/scripts/` and, where named, a stub `docs-audit.mjs`. Functions that run
  `node --test` pass `--test-name-pattern '<TEST id>'` and also fail when the
  output reports zero passing tests. Functions that need `pwsh` fail when it is
  absent and `CI` is set, and otherwise print a `SKIP-CASE` line naming the
  missing tool and return 0. The Pester wrapper skips by name when Pester 5 is
  absent (the ps1-quality `gate` job is its authoritative runner).
- `tests/skills/triage.Tests.ps1` (Pester 5) with at least eight cases, none of
  which may skip on any host: the launcher parses with zero errors; a clean
  fixture prints the header matching `^## AAI L1 Triage - \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$`,
  the state, tree and tick lines and `### Triage verdict: CLEAN`, exit 0; a
  STATE.yaml written with a UTF-8 BOM gives `project_status=active`; a stub
  audit printing `### Verdict: NEEDS-TRIAGE` exits 1 under `-Check` and 0
  without it; the same stub exits 1 under a literal `--check`; a stub printing
  `### verdict: needs-triage` exits 0 under `-Check` with CLEAN; a launcher copy
  without `triage.mjs` beside it prints exactly the UNKNOWN line and exits 0; and
  one case prints `node --version` and asserts major 22 or higher. Each case runs
  the launcher with the engine running the test (`(Get-Process -Id $PID).Path`),
  so the 5.1 step tests 5.1. Assertions read ASCII lines only (D-6 is asserted on
  Linux and macOS, see the risks).
- One new function in `tests/skills/test-aai-layer-profiles.sh`.

### D5. RFC row and delivery documents

The RFC-0017 Rollout Status phase 3 row keeps status `in progress`, its
description cell and the whole first-slice text (TEST-2419 and TEST-2420 of
SPEC-0247 still read it). Its delivered-by cell gains, after the first slice, a
link whose target ends in `node-first-second-slice.md`, the text
`triage pair 140 to <N> lines`, where `<N>` is the `wc -l` sum of `triage.sh`,
`triage.ps1` and `triage.mjs` at delivery, and one sentence saying the slice
moved a behavior with an exit-code gate and two child processes.

After LOOP COMPLETE (ship convention, not gated by a TEST row, in the review
scope): `CHANGELOG.md` gains one
`## [unreleased] — refactor(triage): one Node module owns the L1 triage snapshot`
entry naming D-1, D-4 and D-8. No product doc describes triage (measured), so
none is edited.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 and Spec-AC-05.
- Intake AC-002 maps to Spec-AC-06 (local parity and Pester under pwsh 7) and
  hosted check H1 (native Windows, both engines). No pre-existing test executes
  either copy (measured), so there is nothing to keep passing beyond the suites
  that name `triage.sh` (hygiene pack, cd-subshell baseline) in Verification.
- Intake AC-003 maps to Spec-AC-01 to Spec-AC-04.
- Intake AC-004 maps to Spec-AC-07 and Spec-AC-08.
- Intake AC-005 maps to Spec-AC-09.
- Intake AC-006 maps to Spec-AC-10.
- Intake AC-007 maps to Spec-AC-11. The sign-off records were appended by the
  intake commit `d27c8b61`; the row pins them.

## Constitution deviations

None. Article 4 (degrade and report) was checked: the Node-absent fallback now
reports `UNKNOWN` instead of a CLEAN verdict over a skipped check (D-8). D-11 (a
crashed docs-audit reads as CLEAN) is a pre-existing article 4 gap shared by
both copies; it is kept unchanged because the intake excludes behavior changes
beyond the drift choices, and it is disclosed under Risks. Article 5 (additive
first): the visible output changes (D-1, D-8) are named in the CHANGELOG entry.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN buildReport from .aai/scripts/triage.mjs receives fixed inputs the system SHALL return the report lines in this order: header, blank, state line, tree line, tick line, blank, the audit lines, blank, verdict line, joined with LF and ending in one LF, with exit code 0. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2501.log | tdd | TEST-2501 |
| Spec-AC-02 | The module SHALL resolve the recorded drift: the report holds only ASCII bytes for ASCII inputs and the header uses an ASCII hyphen (D-1); an empty project_status prints unknown (D-2); one leading BOM in STATE.yaml or LOOP_TICKS.jsonl is ignored (D-3); a lower-case needs-triage in the audit output gives CLEAN and exit 0 under --check and its lower-case lines are not shown (D-4); a CRLF tick line is printed without CR (D-5). | done | docs/ai/tdd/node-first-second-slice/green/TEST-2502.log, docs/ai/tdd/node-first-second-slice/green/TEST-2503.log, docs/ai/tdd/node-first-second-slice/green/TEST-2504.log, docs/ai/tdd/node-first-second-slice/green/TEST-2505.log, docs/ai/tdd/node-first-second-slice/green/TEST-2506.log | tdd | TEST-2502, TEST-2503, TEST-2504, TEST-2505, TEST-2506 |
| Spec-AC-03 | WHEN the module CLI runs in a fixture repository it SHALL count real git porcelain lines, SHALL exit 1 only when the audit output holds NEEDS-TRIAGE and --check is given and 0 otherwise, SHALL print the skipped line when docs-audit.mjs is absent and the no-output line when the audit prints no matching line, and SHALL write nothing to stderr. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2507.log | tdd | TEST-2507 |
| Spec-AC-04 | The module source contains no readFileSync(0, process.stdin, writeFileSync, appendFileSync, mkdirSync or renameSync; WHEN the CLI runs in a fixture repository with STATE.yaml, ticks and a stub audit, git status --porcelain and the file list under the fixture SHALL be identical before and after. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2508.log | tdd | TEST-2508 |
| Spec-AC-05 | triage.sh and triage.ps1 are each ASCII only, at most 14 lines, call triage.mjs from their own directory, contain none of the D2 logic tokens and the UNKNOWN literal exactly once; WHEN node is not on PATH, or triage.mjs is absent beside the launcher, each launcher SHALL print exactly the UNKNOWN line, write nothing to stderr and exit 0, with and without the check flag; WHEN node and the module are present the ps1 launcher SHALL return the module exit code. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2509.log, docs/ai/tdd/node-first-second-slice/green/TEST-2510.log, docs/ai/tdd/node-first-second-slice/green/TEST-2511.log | tdd | TEST-2509, TEST-2510, TEST-2511 |
| Spec-AC-06 | WHEN the same seven fixtures (clean, state with ticks and changes, empty project_status, BOM STATE, lower-case audit, NEEDS-TRIAGE audit with the check flag, CRLF ticks) run through triage.sh and through triage.ps1 under pwsh, stdout after removing the timestamp and the exit code SHALL be identical; tests/skills/triage.Tests.ps1 SHALL pass at least 8 cases with 0 skipped and 0 failed under local pwsh 7. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2512.log, docs/ai/tdd/node-first-second-slice/green/TEST-2513.log | tdd | TEST-2512, TEST-2513 |
| Spec-AC-07 | WHEN aai-sync.sh installs the core profile into a scratch git target whose path contains a space, the target SHALL contain .aai/scripts/triage.mjs, and bash .aai/scripts/triage.sh run there SHALL exit 0 and print the header, a line starting with - Mode: from the real docs-audit, and a Triage verdict line, and SHALL not print the UNKNOWN or skipped line. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2514.log | tdd | TEST-2514 |
| Spec-AC-08 | PROFILES.yaml lists .aai/scripts/triage.mjs exactly once, in core; select-suites.mjs selects aai-triage for each of the five suite paths with no FULL_RUN line; both ps1-quality.yml path lists contain .aai/scripts/triage.mjs and stay identical. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2515.log, docs/ai/tdd/node-first-second-slice/green/TEST-2516.log, docs/ai/tdd/node-first-second-slice/green/TEST-2517.log | tdd | TEST-2515, TEST-2516, TEST-2517 |
| Spec-AC-09 | The RFC-0017 Rollout Status phase 3 row has status in progress, its description cell unchanged, the first-slice link and text unchanged, and a link whose target ends in node-first-second-slice.md followed by the word triage. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2518.log | tdd | TEST-2518 |
| Spec-AC-10 | The phase 3 row records triage pair 140 to N lines, where N equals the live wc -l sum of triage.sh, triage.ps1 and triage.mjs and N is below 140. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2519.log | tdd | TEST-2519 |
| Spec-AC-11 | spec-amend list over the repository ledger shows every spec_amendment record of ref node-first-sync-hook-slice as signed, and follow-ups list with status all shows fu-amend-spec-node-first-sync-hook-slice as done. | done | docs/ai/tdd/node-first-second-slice/green/TEST-2520.log | tdd | TEST-2520 |

## Implementation plan

1. RED: write `triage.test.mjs`, `triage.Tests.ps1`, `test-aai-triage.sh` and the
   layer-profiles function; run each row's function alone on the unchanged tree
   and store the output under `docs/ai/tdd/node-first-second-slice/red/`.
   Expected RED: TEST-2501 to TEST-2508 fail because the module does not exist;
   TEST-2509 fails on the current scripts (logic tokens, length, non-ASCII bytes
   in triage.sh); TEST-2510 and TEST-2511 fail because both copies print a full
   report without Node (D-8); TEST-2512 fails on D-1 to D-5 through the current
   copies; TEST-2513 fails on the UNKNOWN case and the lower-case case (D-4);
   TEST-2514 fails because the core target lacks `triage.mjs`; TEST-2515 to
   TEST-2519 fail because the entries and the row do not exist; TEST-2520 passes
   on the baseline, so its RED is the mutation record.
2. Write the module (D1); TEST-2501 to TEST-2508 go green.
3. Replace both scripts with the launchers (D2); TEST-2509 to TEST-2514 go green.
4. Wiring and the RFC row (D3, D5 first paragraph); the rest go green.
5. Run the triage, layer-profiles, suite-select, hygiene-pack and win-fallback
   suites through the wrapper, `test-ps1-quality.sh` locally, and record one
   mutation per row.

Seams crossed (each with a test that produces on one side and reads the real
result on the other):

- Launcher to module: TEST-2512 and TEST-2513 drive both real launchers into the
  real module; TEST-2510 and TEST-2511 cut Node or the module out from under them.
- Module to git: TEST-2507 counts real porcelain lines in a real repository.
- Module to docs-audit: TEST-2514 runs the real `docs-audit.mjs` of a real core
  install; the unit rows use a stub that prints fixed lines.
- Profile manifest to sync: TEST-2514 and TEST-2515, plus the existing
  layer-profiles conformance test (100% classification).
- Path filter to the Windows job, and suite map to the selector: TEST-2516 and
  TEST-2517 read the real files; the Windows job itself is crossed only on
  hosted CI (H1).
- Module to Node 22: the existing Node 22 compatibility step runs
  `node --test tests/skills/lib/*.test.mjs`, which picks up the new file (H2).

Residual risks, written down:

- Whether Windows PowerShell 5.1 passes Node's standard output through
  unchanged when the launcher's own output is redirected is not provable on a
  local host. The Pester cases assert ASCII lines only; byte-exact non-ASCII
  output (D-6) is asserted on Linux and macOS. If H1 shows a garbled ASCII line,
  diagnose with a probe first (see H1).
- How 5.1 binds a literal `--check` (D-7) was not measured; the launcher handles
  both binding outcomes and a Pester case runs it under 5.1 in H1.
- D-10 and D-11 are shared, pre-existing false results (a stray marker raises
  the verdict; a crashed docs-audit reads as CLEAN) and stay unchanged.
  Suggested follow-ups: `suggested: fu-triage-crashed-audit-reads-clean` and
  `suggested: fu-triage-marker-outside-verdict-line`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2501 | Spec-AC-01 | unit | tests/skills/test-aai-triage.sh | test_2501_module_report_order runs node --test --test-name-pattern TEST-2501 on tests/skills/lib/triage.test.mjs: buildReport with a fixed Date, state text, two porcelain lines, ticks and an audit text returns exactly the expected ten-plus-audit lines in D1 order with exit code 0 | `sed:s/treeLine\(porcelain\), tickLine\(ticksText\)/tickLine(ticksText), treeLine(porcelain)/` on .aai/scripts/triage.mjs | green |
| TEST-2502 | Spec-AC-02 | unit | tests/skills/test-aai-triage.sh | test_2502_module_ascii_header runs the TEST-2502 node cases: the header equals ## AAI L1 Triage - 2026-10-23T21:58:07Z for that Date, and no byte of the whole report for ASCII inputs is above 0x7E | `sed:s/const header = '## AAI L1 Triage - '/const header = '## AAI L1 Triage — '/` on .aai/scripts/triage.mjs | green |
| TEST-2503 | Spec-AC-02 | unit | tests/skills/test-aai-triage.sh | test_2503_module_unknown_status runs the TEST-2503 node cases: state texts project_status: with nothing after it, project_status:active and project_status: followed by spaces each print project_status=unknown; project_status: active # note prints active | `sed:s/const UNKNOWN_STATUS = 'unknown';/const UNKNOWN_STATUS = '';/` on .aai/scripts/triage.mjs | green |
| TEST-2504 | Spec-AC-02 | unit | tests/skills/test-aai-triage.sh | test_2504_module_bom_inputs runs the TEST-2504 node cases: runTriage over a temp root whose STATE.yaml and LOOP_TICKS.jsonl start with EF BB BF prints project_status=active and the last tick without U+FEFF; a file holding only a BOM prints none recorded for ticks | `sed:s/const BOM = String\.fromCharCode\(0xfeff\);/const BOM = String.fromCharCode(0x20);/` on .aai/scripts/triage.mjs | green |
| TEST-2505 | Spec-AC-02 | unit | tests/skills/test-aai-triage.sh | test_2505_module_case_sensitive runs the TEST-2505 node cases: audit text with - mode: quick and ### verdict: needs-triage gives the no-output line, CLEAN and exit 0 with check true; the upper-case text gives NEEDS-ATTENTION and exit 1 | `sed:s/const attention = output\.includes\(ATTENTION_MARKER\);/const attention = output.toUpperCase().includes(ATTENTION_MARKER);/` on .aai/scripts/triage.mjs | green |
| TEST-2506 | Spec-AC-02 | unit | tests/skills/test-aai-triage.sh | test_2506_module_crlf_tick runs the TEST-2506 node cases: ticks text with CRLF line ends prints the last record without a 0D byte; a text ending in an empty line prints an empty tick | `sed:s/const tick = stripCr\(last\);/const tick = last;/` on .aai/scripts/triage.mjs | green |
| TEST-2507 | Spec-AC-03 | integration | tests/skills/test-aai-triage.sh | test_2507_module_cli_gate builds a fixture git repository with two uncommitted files and runs node .aai/scripts/triage.mjs there: 2 uncommitted change(s) is printed; with a stub audit printing ### Verdict: NEEDS-TRIAGE the exit code is 1 with --check and 0 without; with the stub removed the skipped line is printed and the exit code is 0 with --check; a stub printing only foo gives the no-output line; stderr is empty in every run | `sed:s/const exitCode = issues > 0 && check \? 1 : 0;/const exitCode = 0;/` on .aai/scripts/triage.mjs | green |
| TEST-2508 | Spec-AC-04 | inspection | tests/skills/test-aai-triage.sh | test_2508_module_read_only checks the module source for the six forbidden tokens, then runs the CLI in a fixture repository and compares git status --porcelain and a sorted file list taken before and after | `sed:s/export const ATTENTION_MARKER = 'NEEDS-TRIAGE';/export const ATTENTION_MARKER = 'NEEDS-TRIAGE'; const STDIN_PROBE = () => fs.readFileSync(0);/` on .aai/scripts/triage.mjs | green |
| TEST-2509 | Spec-AC-05 | inspection | tests/skills/test-aai-triage.sh | test_2509_launchers_thin checks both launchers: no byte above 0x7E, at most 14 lines, a reference to triage.mjs, none of the D2 logic tokens, and the UNKNOWN literal exactly once | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" "$@" # project_status/` on .aai/scripts/triage.sh | green |
| TEST-2510 | Spec-AC-05 | integration | tests/skills/test-aai-triage.sh | test_2510_sh_launcher_without_node runs triage.sh with PATH set to a TEST_DIR bin holding only bash and dirname (positive control: command -v node fails under that PATH): stdout is exactly the UNKNOWN line, stderr empty, exit 0, with and without --check; then, with node on PATH, a launcher copy in a directory without triage.mjs gives the same | `sed:s/echo "### Triage verdict: UNKNOWN/echo "### Triage verdict: CLEAN/` on .aai/scripts/triage.sh | green |
| TEST-2511 | Spec-AC-05 | integration | tests/skills/test-aai-triage.sh | test_2511_ps1_launcher_fallback_and_exit runs triage.ps1 under pwsh with a PATH that resolves pwsh but not node (same positive control) and from a copy without triage.mjs: exactly the UNKNOWN line, empty stderr, exit 0 with and without -Check; then in a fixture with node, the module and a NEEDS-TRIAGE stub, -Check exits 1 and no flag exits 0 | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/triage.ps1 | green |
| TEST-2512 | Spec-AC-06 | integration | tests/skills/test-aai-triage.sh | test_2512_launcher_parity runs the seven fixtures through bash triage.sh and through pwsh -File triage.ps1 (check flag as --check and -Check) and compares stdout with the timestamp removed and the exit codes; positive control: the NEEDS-TRIAGE fixture exits 1 on both sides | `sed:s/\$NodeArgs \+= '--check'/$NodeArgs += '--no-check'/` on .aai/scripts/triage.ps1 | green |
| TEST-2513 | Spec-AC-06 | integration | tests/skills/test-aai-triage.sh | test_2513_pester_triage runs Invoke-Pester on tests/skills/triage.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 8 | `sed:s/param\(\[switch\]\$Check\)/param([switch]$Gate)/` on .aai/scripts/triage.ps1 | green |
| TEST-2514 | Spec-AC-07 | e2e | tests/skills/test-aai-triage.sh | test_2514_downstream_core_sync_runs_triage runs .aai/scripts/aai-sync.sh --profile core into a git-initialised TEST_DIR/target with space, asserts the target holds .aai/scripts/triage.mjs, runs bash .aai/scripts/triage.sh in the target and asserts exit 0, the header, a - Mode: line, a Triage verdict line and neither the UNKNOWN nor the skipped line | `sed:s/  - \.aai\/scripts\/triage\.mjs/  - .aai\/scripts\/triage-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-2515 | Spec-AC-08 | inspection | tests/skills/test-aai-layer-profiles.sh | test_2515_triage_module_classified asserts .aai/scripts/triage.mjs appears exactly once in PROFILES.yaml, inside the core list | `sed:s/triage\.mjs/triage-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-2516 | Spec-AC-08 | integration | tests/skills/test-aai-triage.sh | test_2516_suite_map_selects_triage feeds each of the five suite paths to node .aai/scripts/select-suites.mjs --files-from - and requires a SELECTED aai-triage line and no FULL_RUN line | `sed:s/\.aai\/scripts\/triage\.mjs/.aai\/scripts\/triage-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-2517 | Spec-AC-08 | inspection | tests/skills/test-aai-triage.sh | test_2517_ps1_quality_filter_has_module extracts the push and pull_request path lists of .github/workflows/ps1-quality.yml and requires both to contain .aai/scripts/triage.mjs and to be identical | `sed:s/triage\.mjs/triage-gone.mjs/` on .github/workflows/ps1-quality.yml | green |
| TEST-2518 | Spec-AC-09 | inspection | tests/skills/test-aai-triage.sh | test_2518_rfc_phase3_row finds the Rollout Status row whose first cell is 3 and checks the unchanged description cell, status in progress, the unchanged first-slice link and text, and a link target ending in node-first-second-slice.md followed by the word triage | `sed:s/node-first-second-slice\.md/node-first-2.md/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2519 | Spec-AC-10 | inspection | tests/skills/test-aai-triage.sh | test_2519_line_budget_recorded parses triage pair 140 to N lines from the phase 3 row and requires N to equal the live wc -l sum of the three files and to be below 140 | `sed:s/triage pair 140 to (\d+) lines/triage pair 140 to 1$1 lines/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2520 | Spec-AC-11 | inspection | tests/skills/test-aai-triage.sh | test_2520_495_amendments_signed runs node .aai/scripts/spec-amend.mjs list --json and requires at least seven records of ref node-first-sync-hook-slice, all signed; then node .aai/scripts/follow-ups.mjs list --status all --json and requires fu-amend-spec-node-first-sync-hook-slice with status done | `sed:s/"owner_signoff":true,"why":"Owner directed the merge of PR #495/"owner_signoff":false,"why":"Owner directed the merge of PR #495/` on docs/ai/decisions.jsonl | green |

Test-file note: every row's selector is one bash function that runs alone under
single-function dispatch, because `mutation-run.mjs` runs bash suites only
(`fu-mutation-gate-skips-pester` stays open; the Pester file is reached through
the TEST-2513 wrapper). Mutation patterns are JavaScript regular expressions with
`(`, `)`, `[`, `]`, `.`, `+`, `?`, `/` and `$` escaped as written; no row uses a
flag. `check-test-registration.mjs` must stay at exit 0. If a mutation anchor
proves ambiguous at RED time (first occurrence lands elsewhere), the fix is an
additive-with-disclosure amendment of that one cell, recorded before its run.

### RED observations and positive controls

- TEST-2501 to TEST-2508: RED on the baseline because the module does not exist
  (import or file read fails); the wrappers' zero-passing-tests guard makes a
  missing test name RED rather than vacuously green.
- TEST-2509: RED on the baseline (logic tokens and length in both scripts,
  non-ASCII bytes in triage.sh).
- TEST-2510 and TEST-2511: RED on the baseline (both copies print a full report
  without Node, D-8); the positive control (`command -v node` fails under the
  test PATH) is asserted first.
- TEST-2512: RED on the baseline through D-1 to D-5. TEST-2513: RED on the
  baseline (UNKNOWN case, lower-case case).
- TEST-2514: RED on the baseline, because the core target lacks `triage.mjs`.
- TEST-2515 to TEST-2519: RED on the baseline (entries and row absent).
- TEST-2520: passes on the baseline (signed by `d27c8b61`); its RED is the
  mutation record.

## Verification

- Triage suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-triage.sh` exits 0.
- Layer profiles: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` exits 0.
- Suite selection: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` exits 0.
- Hygiene pack (suite-map row pin, pipefail reader scan, cd-subshell baseline): `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` exits 0.
- Windows-fallback pins on the path filter: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` exits 0.
- Live-status suite, unchanged slice-1 rows that read the phase 3 row: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-live-status.sh` exits 0.
- Direct Node tests: `node --test tests/skills/lib/triage.test.mjs` exits 0, under local Node 22.
- PowerShell gate: `bash tests/skills/test-ps1-quality.sh` exits 0 locally (PSScriptAnalyzer and the full Pester discovery, SkippedCount 0).
- Line budget: `wc -l .aai/scripts/triage.sh .aai/scripts/triage.ps1 .aai/scripts/triage.mjs` total below 140 and equal to the RFC row.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.

### Hosted delivery checks (after normal PR creation, before merge-readiness)

These are not Spec-ACs and are not claimed by local Validation.

- H1 (native Windows parity, intake AC-002): on the PR head, the ps1-quality
  run concludes success for `gate`, `windows-5_1` and `windows-wsl1`. In both
  `Full Pester suite discovery` steps of `windows-5_1` (Windows PowerShell 5.1
  and pwsh 7) and in the one of `windows-wsl1`, every case of
  `triage.Tests.ps1` is listed as passed, the skipped count still equals
  `AAI_EXPECTED_WIN_SKIP_COUNT` (4), and the Node version case logs a major of
  22 or higher. Evidence: run id, head SHA and the matched log lines from
  `gh run view <id> --log`. A hosted-only failure is diagnosed with a probe
  before any code change: a temporary diagnostic step or case that prints the
  bytes the launcher and Node actually exchanged (stdout bytes in hex, the
  arguments Node received, `$LASTEXITCODE`), and the code change follows the
  probe's result, recorded as an amendment. SPEC-0247 spent two rounds on
  disproven hypotheses before such a probe found its BOM.
- H2 (Linux and Node 22 floor): the PR head's skill-suite run concludes success,
  with `aai-triage` selected or a full run, and the step
  `Node 22 compatibility (downstream floor)` passing; its `node --test` output
  lists the TEST-2501 to TEST-2506 cases.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/node-first-second-slice/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. H1 and H2 are recorded separately after PR creation. Planning's
measurements above are inputs, not attestations of the implementation.

## Risks and rollback

- The Windows output path (D-6, D-7) is the one behavior no local host can
  prove; H1 decides it.
- A scheduled `triage --check` on a host without Node now prints `UNKNOWN`
  instead of a full report and CLEAN; the exit code stays 0. The CHANGELOG entry
  names it.
- Changing two shipped core scripts is consumer-visible: merge needs the
  owner's menu (intake constraint).
- The phase 3 row edit on an open umbrella RFC can trip the docs-audit
  false-open check at close; handle it with a fresh `doc_lifecycle` event, as
  earlier phase children did.
- TEST-2520 pins a ledger fact; a later, legitimate re-classification of those
  records would redden it and must then amend or retire the row.
- Rollback is one revert of the scope's files; no template or hook command
  names triage, so installs need nothing.

## Registry disposition

Related open registry items, all left open:

- `fu-mutation-gate-skips-pester`: this scope reaches its Pester file through a
  bash wrapper (TEST-2513) instead of extending the gate.
- `fu-ps1-quality-outside-sweep-glob`: `test-ps1-quality.sh` is still outside the
  sweep glob; this scope runs it in Verification and through H1 only.
- `fu-three-readers-three-whitespaces`: a BOM finding in another reader
  (`update-installs-ref-guard`); this scope's BOM handling (D-3) does not touch
  that reader.

Registry items closed by this scope: none. (`fu-amend-spec-node-first-sync-hook-slice`
already projects as done after the intake commit; Spec-AC-11 pins it.)
