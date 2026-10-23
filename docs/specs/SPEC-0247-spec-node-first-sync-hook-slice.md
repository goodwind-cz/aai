---
id: spec-node-first-sync-hook-slice
type: spec
number: 247
status: done
mutation_gate: v1
frozen_sha256: f901c5787c33d6eb1d25c16064b3dd996824d7f687ced99793df529ed587a9f7
ceremony_level: 2
links:
  requirement: node-first-sync-hook-slice
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the live-status spool hook from paired Bash and PowerShell scripts to one Node module

SPEC-FROZEN: true

## Links

- Requirement: [First Node-first slice of paired sync/hook scripts](../issues/CHANGE-0222-node-first-sync-hook-slice.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  Proposal section 1 and owner decisions 1.5 (phases 3 to 5 in order), 2 (Node
  22 floor downstream, Node 24 CI) and 4 (no new runner).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no dependencies).
- Baseline: main `3b092c64`; the ride branch adds only the intake (`eaa830ca`).

## Implementation strategy

- Strategy: hybrid
- Rationale: the new module and the two launchers are new behavior with
  recorded drift decisions, so every row that gates them goes RED first on the
  baseline (the module does not exist; the PowerShell copy fails the drift
  cases) and carries a mutation record (TDD). The wiring edits (PROFILES,
  suite map, the ps1-quality path filter, the RFC row) are mechanical and done
  in loop mode, but each one is pinned by a mutation-gated row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped scripts, a CI workflow and
  the vendored profile manifest; the ride already runs in its own linked worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: change/node-first-sync-hook-slice at /private/tmp/aai-node-first-slice
- Inline review scope: .aai/scripts/live-spool.mjs; .aai/scripts/live-spool.sh;
  .aai/scripts/live-spool.ps1; .aai/system/PROFILES.yaml;
  .github/workflows/ps1-quality.yml; tests/skills/suite-map.yaml;
  tests/skills/lib/live-spool.test.mjs; tests/skills/live-spool.Tests.ps1;
  tests/skills/test-aai-live-status.sh; tests/skills/test-aai-layer-profiles.sh;
  tests/skills/lib/cd-subshell-leak-baseline.tsv (only if the checker asks for a re-record);
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md;
  docs/product/live-status-dashboard.md; CHANGELOG.md;
  docs/issues/CHANGE-0222-node-first-sync-hook-slice.md; this spec.
- Code review required: true.

## Pair selection (measured)

Measured on the planning tree (macOS arm64, Node 22.23.1, pwsh 7.6.3) on
2026-10-23. Lines are `wc -l`. Commits are `git log --oneline -- <file>` over
986 commits of history. "Callers" are tracked files outside docs/ai, specs,
issues, RFCs, analysis and CHANGELOG that name the `.sh` or `.ps1` file.

| Pair | Lines sh/ps1 | Commits sh/ps1 (joint) | Callers | When it runs | Node today | Platform-specific content | Existing executing tests | Verdict |
|---|---|---|---|---|---|---|---|---|
| validate-skills | 47/55 | 5/3 (3) | 5 | manual, self-hosting smoke | no | none | self-hosting smoke | not a sync/hook behavior |
| live-spool | 66/67 | 1/1 (1) | 10 | every statusline refresh plus every Stop and Notification hook, when the opt-in overlay is installed | sh copy spawns node on every call (line 31); its only reader is Node | none (stdin, JSON projection, file append, line cap) | 3 bash functions produce through the sh copy (test_011, test_014, test_015); 0 for the ps1 copy | CHOSEN |
| triage | 73/67 | 2/2 (1) | 5 | manual or scheduled | no | none | hygiene mention only | not a sync/hook behavior |
| pre-compact-save | 77/87 | 1/1 (1) | 8 | PreCompact hook, wired by no shipped template | no | git calls | 0 (doctor checks file presence only) | runner-up, rejected: no test of either copy, and it would introduce a Node dependency into a hook that has none |
| cloudflare-share | 78/69 | 5/4 (4) | 7 | manual publish | no | wrangler, network | hygiene mention only | external service |
| aai-live | 125/90 | 1/1 (1) | 8 | manual dashboard launch | yes | browser opener per OS | live-status suite | platform adapter content |
| migrate-yaml-to-jsonl | 126/151 | 2/2 (2) | 6 | one-off migration | no | none | none | not a sync/hook behavior |
| migrate-state-to-local | 162/175 | 5/7 (4) | 11 | one-off migration named by sync | no | none | sync-seed | one-off, no Node today |
| aai-update | 180/188 | 7/7 (5) | 16 | every downstream update | optional: prints `DOCTOR-REPORT SKIP node missing - update unaffected` | git clone, temp dirs | bash suite and Pester | disqualified: a caller runs before Node is installed |
| expert-fetch | 232/212 | 3/3 (2) | 9 | on demand | no | network | hygiene mention only | external service |
| aai-canonicalize | 276/281 | 5/3 (3) | 5 | one-off | no | none | none | one-off |
| pre-commit-checks | 323/281 | 7/6 (6) | 27 | every commit | optional: checks 1 to 7 run without Node, checks 8 and 9 are skipped by `command -v node` | pwsh parse gate | many | disqualified for a first slice: L3 protected surface (`protected_paths_l3`) and a pre-Node degrade path |

Why live-spool:

- It is the only hook pair whose existing caller path already requires Node:
  the Bash copy's projection is an inline `node -e` program, and the spool's only
  reader is `.aai/scripts/generate-live-status.mjs`. Moving the logic into a
  module removes no capability from any host that can read the spool.
- It has zero lines of platform-specific behavior, so the whole behavior moves
  and nothing remains for an adapter except the "Node is absent" fallback.
- It runs more often than any other candidate where it is installed.
- It has real, measured drift between the copies (below) and the PowerShell copy
  has no test at all, so the slice removes untested duplicate logic.
- It is small (133 lines) and sets the pattern (module, launchers, `node:test`,
  Pester on the native Windows job, profile and path-filter wiring) at low risk.

What it does not show: its git history has one commit per copy (born together in
8e4f9ac9, never fixed), so it carries no drift-fix history; the twice-fixed cost
the RFC names is better illustrated by pre-commit-checks (6 joint commits) and
aai-update (5), both disqualified above. The saving is small by design. The
evidence is not evenly split, so no owner question is raised.

## Drift between the two copies (measured) and decisions

Both copies were run on the same payloads (macOS, Bash with Node 22.23.1, and
pwsh 7.6.3). The Node module takes the Bash copy's semantics in every case,
because that copy's logic already is Node and its output is the one the existing
tests and the reader were built against.

| Id | Case | Bash copy | PowerShell copy | Decision |
|---|---|---|---|---|
| D-1 | `ts` format | `2026-10-23T13:36:09.977Z` (3 fractional digits) | `2026-10-23T13:36:10.2774300Z` (7 digits) | 3 digits (`Date.prototype.toISOString`). The reader compares `ts` as strings (generate-live-status.mjs line 326), so mixed precision can order lines wrongly: `...10.400Z` sorts after `...10.4000001Z`. |
| D-2 | JSON array or scalar payload | no line | writes a bare `{"ts":...}` line | no line. A bare line becomes the last statusline record and hides the quotas, because the reader takes the last line (`readSpoolLastLine`). |
| D-3 | nesting deeper than 10 levels | kept | truncated to `"@{k=}"` and a `WARNING: Resulting JSON is truncated` line on the host stream | kept; nothing but the passthrough line is ever printed |
| D-4 | numbers | JSON.parse semantics (`1.0` becomes `1`; integers above 2^53 lose precision) | literal kept | JSON.parse semantics; no reader needs more |
| D-5 | encoding (Windows PowerShell 5.1 only, by inspection) | UTF-8 | `Add-Content` and `Set-Content` use the ANSI code page | UTF-8 without BOM |
| D-6 | line endings (Windows only, by inspection) | LF | CRLF | LF |
| D-7 | line cap rewrite | `tail -n 500` to a temp file, then `mv` | `Set-Content` rewrite in place | keep the last 500 lines, written to a temp file in the same directory, then renamed |
| D-8 | empty, whitespace-only or invalid JSON | no line | no line | unchanged (no line, spool file not created) |
| D-9 | Node absent | no line, passthrough still printed | writes the line (no Node needed) | no line, passthrough still printed, exit 0, on both launchers. Accepted behavior change on Windows hosts without Node: nothing can read the spool there, because the reader is Node. |
| D-10 | non-whitelisted `kind` (for example `foo`) | statusline fields, file `foo.jsonl` | same | unchanged |

## Scope and design

### D1. The module `.aai/scripts/live-spool.mjs`

Dependency-free ESM, Node 22 compatible (only `node:fs`, `node:path`, `node:url`).
Importing it has no side effects. It contains these exact lines (mutation anchors):

```js
export const MAX_LINES = 500;
export const PASSTHROUGH = '(aai-live tap active)';
const COMMON_FIELDS = ['session_id', 'cwd', 'model'];
const STATUSLINE_FIELDS = ['rate_limits', 'cost'];
const HOOK_FIELDS = ['hook_event_name'];
```

Exports:

- `projectPayload(raw, kind, now = new Date())` returns the JSON line (no
  newline) or `null`. It parses `raw` with `JSON.parse` inside try/catch and
  returns `null` on a parse error, on `null`, on a non-object and on an array,
  through three separate lines, one of which is exactly
  `if (Array.isArray(obj)) return null;`. The allow list is `COMMON_FIELDS`
  plus `HOOK_FIELDS` when `kind === 'hooks'`, otherwise plus
  `STATUSLINE_FIELDS`. The output object starts with `ts`, taken by the exact
  line `const ts = now.toISOString();`, followed by each allowed key present in
  the payload (`in` test, so `null`, `0` and `""` values are kept), copied by the
  exact line `out[key] = obj[key];`, in allow-list order.
- `appendCapped(file, line, maxLines = MAX_LINES)` creates the directory,
  appends with the exact line `fs.appendFileSync(file, line + EOL, 'utf8');`
  where `const EOL = '\n';`, then, when the file holds more than `maxLines`
  lines, writes the last `maxLines` lines to `<file>.tmp` and renames it over
  the file.
- `runLiveSpool({ argv, env, stdinText, stdout })` is the whole behavior: kind
  is `argv[0]` or `statusline`; the spool directory is `env.AAI_LIVE_SPOOL_DIR`
  or `<repo>/docs/ai/live`, where `<repo>` is two levels above the module's own
  directory (never the caller's cwd); a non-empty projected line is appended;
  every error is caught; for kind `statusline` it writes `PASSTHROUGH` plus a
  newline to `stdout` whether or not anything was written.

CLI: when run as the main module (main-module check by comparing the real path
of `process.argv[1]` with the real path of `fileURLToPath(import.meta.url)`, so a
script path containing a space still works), it reads all of stdin as UTF-8,
calls `runLiveSpool`, and ends with the exact line `process.exit(0);`. Nothing
is written to stderr.

### D2. The launchers

Both keep their names, their position-zero `kind` argument and the
`AAI_LIVE_SPOOL_DIR` override. Each is ASCII only and at most 20 lines, and holds
none of these tokens: `session_id`, `rate_limits`, `hook_event_name`, `cost`,
`500`, `JSON`, `ConvertFrom-Json`, `ConvertTo-Json`, `Add-Content`,
`Set-Content`, `tail`. The literal `(aai-live tap active)` is allowed once, in
the fallback branch only (D-9). The fallback runs when Node is absent OR when
Node could not run the module (a non-zero exit, which the module itself never
returns, so it means the module was missing or failed to load); it drains a
redirected standard input and prints the passthrough for statusline only.
Amended after code review NB-1/NB-2 (2026-10-23): the frozen shape printed
nothing when Node was present but the module could not run, and left standing
input unread in the Node-absent hooks branch.

`live-spool.sh`, shape (the anchored lines are exact):

```bash
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/live-spool.mjs"
rc=1
if command -v node >/dev/null 2>&1; then
  node "$MODULE" "$@" 2>/dev/null && rc=0
fi
if [[ $rc -ne 0 ]]; then
  [[ -t 0 ]] || cat >/dev/null 2>&1
  [[ "${1:-statusline}" == "statusline" ]] && echo "(aai-live tap active)"
fi
exit 0
```

`live-spool.ps1`, shape (the anchored lines are exact):

```powershell
param([Parameter(Position = 0)][string]$Kind = 'statusline')
$Module = Join-Path $PSScriptRoot 'live-spool.mjs'
$Ran = $false
if (Get-Command node -ErrorAction SilentlyContinue) {
  & node $Module $Kind 2>$null
  $Ran = ($LASTEXITCODE -eq 0)
}
if (-not $Ran) {
  if ([Console]::IsInputRedirected) { $null = [Console]::In.ReadToEnd() }
  if ($Kind -eq 'statusline') { Write-Output '(aai-live tap active)' }
}
exit 0
```

The PowerShell launcher lets Node inherit the process's standard input, so
PowerShell never decodes or re-encodes the payload (removes D-5 at the source).
If the hosted Windows check H1 shows that Windows PowerShell 5.1 does not pass
its standard input to the child, Implementation may switch to piping the payload
with `$OutputEncoding` and `[Console]::InputEncoding` set to UTF-8 without BOM;
that is a recorded amendment, and the non-ASCII Pester case decides it.

Disclosure (amendment): hosted check H1 on PR #495 failed every Pester case that
expects a spool line. The cause was a UTF-8 byte-order mark: the Windows PowerShell
5.1 Pester harness (and any .NET Framework writer to a child's redirected stdin)
writes EF BB BF before the payload (33 bytes on Windows against 30 on Linux for
the same payload), and the module's JSON parse rejected the leading U+FEFF. The
module now strips one leading BOM before parsing (`projectPayload`; a BOM anywhere
else still gives no line). Two earlier hypotheses, that 5.1 does not forward stdin
(rewrite b168d458) and that `fs.readFileSync(0)` throws EOF on Windows pipes
(`readStdin`, eb109b01), were disproven by a hosted diagnostic (CI run 40011517525,
`readFileSync(0)` read all 33 bytes) and both were reverted. The launchers and
their 20-line cap are as first frozen; the live-spool line total is 116.

`.aai/templates/hooks/live-status-hooks.json` is not changed (byte-identical),
so installed overlays and approval prefixes keep working.

### D3. Wiring

- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/live-spool.mjs` in the
  `extended:` list next to the two launchers (companion obligation for a new
  `.aai/**` file). Not in `core:`.
- `tests/skills/suite-map.yaml`, suite `aai-live-status`: add
  `.aai/scripts/live-spool.mjs`, `tests/skills/lib/live-spool.test.mjs` and
  `tests/skills/live-spool.Tests.ps1` (today each of the first two maps to
  `FULL_RUN reason=unmapped`).
- `.github/workflows/ps1-quality.yml`: add `'.aai/scripts/live-spool.mjs'` to both
  the `push` and the `pull_request` path lists, which must stay identical, so a
  change to the module alone still runs the native Windows job. No job, runner
  or step is added (RFC-0017 decision 4). No comment naming the module may
  precede the `push` list (TEST-2418's mutation edits the first occurrence). The new Pester file is discovered by
  the existing `Run.Path = 'tests/skills'` steps under Windows PowerShell 5.1 and
  pwsh 7 in `windows-5_1`, under 5.1 in `windows-wsl1`, and under pwsh 7 on
  Linux in `gate`.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-record with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record` only if the checker
  reports the `live-spool.sh` count changed.

### D4. Tests

- `tests/skills/lib/live-spool.test.mjs` (`node:test`, direct imports, temp
  directories only, no repository clone). Every test name starts with its TEST id.
- `tests/skills/live-spool.Tests.ps1` (Pester 5) with at least six cases, none
  of which may skip on any host: the launcher parses with zero errors; an object
  payload gives one whitelisted line with a 3-digit `ts`; a non-ASCII payload
  (`Opus ✓ čř`) round-trips byte-exact as UTF-8 without BOM and with LF only; an
  array payload creates no spool file; `hooks` prints nothing and exits 0; no
  argument prints exactly `(aai-live tap active)`; and one case prints
  `node --version` and asserts major 22 or higher. Each case launches the
  launcher with the engine running the test (`(Get-Process -Id $PID).Path`), so
  the 5.1 step tests 5.1. Stdin bytes are written by the test as UTF-8.
- New functions in `tests/skills/test-aai-live-status.sh`, each registered once
  in `main()`, each failure message naming its TEST id. Functions that run
  `node --test` pass `--test-name-pattern '<TEST id>'` and also fail when the
  output reports zero passing tests (a pattern that matches nothing is not a
  pass). Functions that need `pwsh` fail when it is absent and `CI` is set, and
  otherwise print a `SKIP-CASE` line naming the missing tool and return 0. The
  Pester wrapper skips by name when Pester 5 is absent (the ps1-quality `gate`
  job is its authoritative runner).
- One new function in `tests/skills/test-aai-layer-profiles.sh`.

### D5. RFC row and delivery documents

The RFC-0017 Rollout Status phase 3 row: status cell `in progress`; delivered-by
cell gains a link whose target ends in `node-first-sync-hook-slice.md`, the text
`live-spool pair 133 to <N> lines`, where `<N>` is the `wc -l` sum of
`live-spool.sh`, `live-spool.ps1` and `live-spool.mjs` at delivery, and one
sentence naming the pattern (one Node module, two launchers, `node:test` plus
Pester on the native Windows job). The phase 3 description cell is unchanged.

After LOOP COMPLETE (ship convention, not gated by a TEST row, in the review
scope): `docs/product/live-status-dashboard.md` lines that call the PowerShell
file a twin now say the logic is in `live-spool.mjs` and both scripts are
launchers, and name D-1, D-2 and D-9; `CHANGELOG.md` gains one
`## [unreleased] — refactor(live): one Node module owns the live-status spool` entry.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 and Spec-AC-04.
- Intake AC-002 maps to Spec-AC-05 (local parity, existing suite unchanged) and
  hosted check H1 (native Windows).
- Intake AC-003 maps to Spec-AC-01, Spec-AC-02 and Spec-AC-03.
- Intake AC-004 maps to Spec-AC-07 and Spec-AC-08.
- Intake AC-005 maps to Spec-AC-09.
- Intake AC-006 maps to Spec-AC-10.
- The reader seam maps to Spec-AC-06.

## Constitution deviations

None. Article 4 (degrade and report) was checked: the spool writer stays silent
on its own errors because a statusline or hook writer must never disturb the
harness; that contract predates this scope and is unchanged.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN runLiveSpool from .aai/scripts/live-spool.mjs receives an object payload the system SHALL append one line holding ts and exactly the whitelisted keys present (statusline and any non-hooks kind: session_id, cwd, model, rate_limits, cost; hooks: session_id, cwd, model, hook_event_name) and SHALL drop every other key such as transcript_path and message. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2401.log | tdd | TEST-2401 |
| Spec-AC-02 | The module SHALL resolve the recorded drift: ts has exactly 3 fractional digits (D-1); an array or scalar payload writes no line (D-2); a 12-level nested value is written byte-identical to JSON.stringify of the input (D-3); a non-ASCII payload is written as UTF-8 without BOM and without CR (D-5, D-6); a file of 505 lines plus one append holds 500 lines ending with the new one (D-7). | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2402.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2403.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2404.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2405.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2406.log | tdd | TEST-2402, TEST-2403, TEST-2404, TEST-2405, TEST-2406 |
| Spec-AC-03 | WHEN the module CLI runs with kind statusline or no kind it SHALL print exactly one line (aai-live tap active) and exit 0; with kind hooks it SHALL print nothing and exit 0; WHEN AAI_LIVE_SPOOL_DIR names an existing regular file it SHALL still exit 0 with empty stderr and print the passthrough for statusline. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2407.log | tdd | TEST-2407 |
| Spec-AC-04 | live-spool.sh and live-spool.ps1 are each ASCII only, at most 20 lines, call live-spool.mjs from their own directory and contain none of the D2 logic tokens; WHEN node is not on PATH, or node cannot run live-spool.mjs (module absent next to the launcher), each launcher SHALL exit 0, create no spool file, write nothing to stderr and print the passthrough line for statusline only. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2408.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2409.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2410.log | tdd | TEST-2408, TEST-2409, TEST-2410 |
| Spec-AC-05 | WHEN the same six payloads (object statusline, object hooks, array, invalid, non-ASCII, deep) are piped through live-spool.sh and through live-spool.ps1 under pwsh the spool files SHALL be identical after removing ts values and stdout SHALL be identical; tests/skills/live-spool.Tests.ps1 SHALL pass at least 6 cases with 0 skipped and 0 failed under local pwsh 7; the existing test-aai-live-status.sh functions test_001 to test_039 pass with their bodies unchanged. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2411.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2412.log | tdd | TEST-2411, TEST-2412 |
| Spec-AC-06 | WHEN a statusline payload with five_hour and seven_day rate limits is written through live-spool.ps1 under pwsh, generate-live-status.mjs over that spool SHALL report quotas source tap with both used_percent values and render both percentages in the HTML. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2413.log | tdd | TEST-2413 |
| Spec-AC-07 | WHEN aai-sync.sh installs the layer into a scratch target whose path contains a space, the target SHALL contain .aai/scripts/live-spool.mjs, and running the statusLine command and the Stop hook command taken from the real live-status-hooks.json with CLAUDE_PROJECT_DIR set to the target SHALL append one line each to the target's docs/ai/live/statusline.jsonl and hooks.jsonl, with the statusLine run printing the passthrough. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2414.log | tdd | TEST-2414 |
| Spec-AC-08 | live-status-hooks.json still invokes bash on .aai/scripts/live-spool.sh for statusLine, Stop and Notification; PROFILES.yaml lists .aai/scripts/live-spool.mjs exactly once, in extended; select-suites.mjs selects aai-live-status for each of the three new paths; both ps1-quality.yml path lists contain .aai/scripts/live-spool.mjs and stay identical. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2415.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2416.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2417.log, docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2418.log | tdd | TEST-2415, TEST-2416, TEST-2417, TEST-2418 |
| Spec-AC-09 | The RFC-0017 Rollout Status phase 3 row has status in progress, a link whose target ends in node-first-sync-hook-slice.md and the word live-spool, and its description cell is unchanged. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2419.log | tdd | TEST-2419 |
| Spec-AC-10 | The phase 3 row records live-spool pair 133 to N lines, where N equals the live wc -l sum of live-spool.sh, live-spool.ps1 and live-spool.mjs and N is below 133. | done | docs/ai/tdd/node-first-sync-hook-slice/green/TEST-2420.log | tdd | TEST-2420 |

## Implementation plan

1. RED: write `live-spool.test.mjs`, `live-spool.Tests.ps1` and the bash wrapper
   functions; run each row's function alone on the unchanged tree and store the
   output under `docs/ai/tdd/node-first-sync-hook-slice/red/`. Expected RED: the
   module rows fail because the module does not exist; TEST-2408 fails on the
   current launchers (logic tokens, length, non-ASCII bytes in live-spool.sh);
   TEST-2409 and TEST-2410 fail because the PowerShell copy writes without Node
   (D-9) and TEST-2410 also has a positive control (see below); TEST-2411 and
   TEST-2412 fail on D-1 and D-2 through the current PowerShell copy; TEST-2414
   fails because the target lacks `live-spool.mjs`; TEST-2416 to TEST-2420 fail
   because the entries and the row do not exist.
2. Write the module (D1); TEST-2401 to TEST-2407 go green.
3. Replace both scripts with the launchers (D2); TEST-2408 to TEST-2414 go green.
4. Wiring and the RFC row (D3, D5 first paragraph); the rest go green.
5. Run the full live-status, layer-profiles and suite-select suites through the
   wrapper, `test-ps1-quality.sh` locally, and record one mutation per row.

Seams crossed (each with a test that produces on one side and reads the real
result on the other):

- Launcher to module: TEST-2411 and TEST-2412 drive both real launchers into the
  real module; TEST-2409 and TEST-2410 cut Node out from under them.
- Spool to reader: TEST-2413 writes through the PowerShell launcher and reads
  with the real `generate-live-status.mjs`; existing test_011, test_014 and
  test_015 do the same through the Bash launcher.
- Template to launcher to downstream install: TEST-2414 runs the commands from
  the real template inside a real `aai-sync.sh` install.
- Profile manifest to sync: TEST-2416 and the existing layer-profiles
  conformance test (100% classification).
- Path filter to the Windows job, and suite map to the selector: TEST-2417 and
  TEST-2418 read the real files; the Windows job itself is crossed only on
  hosted CI (H1).
- Module to Node 22: the existing Node 22 compatibility step runs
  `node --test tests/skills/lib/*.test.mjs`, which picks up the new file (H2).

Residual risks, written down:

- Whether Windows PowerShell 5.1 hands its standard input to a native child was
  proved by H1; a leading UTF-8 BOM, which the 5.1 harness adds, is now ignored by
  the module (resolved, see the D2 disclosure).
- The Windows job uses the runner image's preinstalled Node (ps1-quality.yml
  has no setup-node step); the Pester version case makes its major visible and
  fails below 22.
- The PowerShell copy's ANSI and CRLF behavior (D-5, D-6) was read from the code,
  not run, because no Windows host was available to Planning.
- Two sessions appending to the same spool at the moment of a cap rewrite can
  lose a line; that race exists in both copies today and is unchanged.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2401 | Spec-AC-01 | unit | tests/skills/test-aai-live-status.sh | test_2401_module_whitelist runs node --test --test-name-pattern TEST-2401 on tests/skills/lib/live-spool.test.mjs: statusline, hooks and kind foo payloads carrying every whitelisted key plus transcript_path and message give lines with exactly ts plus the kind's keys in allow-list order; null, 0 and empty-string values are kept | `sed:s/const HOOK_FIELDS = \['hook_event_name'\];/const HOOK_FIELDS = [];/` on .aai/scripts/live-spool.mjs | green |
| TEST-2402 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | test_2402_module_ts_precision runs the TEST-2402 node cases: with a fixed Date the ts equals its toISOString and matches 3 fractional digits then Z | `sed:s/const ts = now\.toISOString\(\);/const ts = now.toISOString().replace('Z', '0000Z');/` on .aai/scripts/live-spool.mjs | green |
| TEST-2403 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | test_2403_module_non_object runs the TEST-2403 node cases: an array, a number, a string and null payload each return null and create no spool file; a payload with one leading U+FEFF projects to the same line as without it, while two leading, a middle and a trailing U+FEFF give null | `sed:s/if \(Array\.isArray\(obj\)\) return null;//` on .aai/scripts/live-spool.mjs | green |
| TEST-2404 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | test_2404_module_deep_nesting runs the TEST-2404 node cases: a cost value nested 12 levels deep is written equal to JSON.stringify of the input value | `sed:s/out\[key\] = obj\[key\];/out[key] = typeof obj[key] === 'object' ? {} : obj[key];/` on .aai/scripts/live-spool.mjs | green |
| TEST-2405 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | test_2405_module_utf8_lf runs the TEST-2405 node cases: a payload with model display_name Opus ✓ čř is written so the file bytes decode as UTF-8 to that text, start without EF BB BF and contain no 0D byte | `sed:s/line \+ EOL, 'utf8'/line + EOL, 'latin1'/` on .aai/scripts/live-spool.mjs | green |
| TEST-2406 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | test_2406_module_line_cap runs the TEST-2406 node cases: a spool of 505 valid lines plus one append holds exactly 500 lines whose last is the new line and no .tmp file remains | `sed:s/export const MAX_LINES = 500;/export const MAX_LINES = 5000;/` on .aai/scripts/live-spool.mjs | green |
| TEST-2407 | Spec-AC-03 | integration | tests/skills/test-aai-live-status.sh | test_2407_module_cli_exit_and_passthrough runs node .aai/scripts/live-spool.mjs as a CLI: statusline and no-kind print exactly the passthrough line, hooks prints nothing, and with AAI_LIVE_SPOOL_DIR pointing at a regular file the exit code is 0, stderr is empty and statusline still prints the passthrough | `sed:s/process\.exit\(0\);/process.exit(1);/` on .aai/scripts/live-spool.mjs | green |
| TEST-2408 | Spec-AC-04 | inspection | tests/skills/test-aai-live-status.sh | test_2408_launchers_thin checks both launchers: no byte above 0x7E, at most 20 lines, a reference to live-spool.mjs, none of the D2 logic tokens, and the passthrough literal at most once | `sed:s/pwd\)\/live-spool\.mjs"/pwd)\/live-spool.mjs" session_id/` on .aai/scripts/live-spool.sh | green |
| TEST-2409 | Spec-AC-04 | integration | tests/skills/test-aai-live-status.sh | test_2409_sh_launcher_without_node runs live-spool.sh with PATH set to a TEST_DIR bin holding only bash, cat, dirname and the shell builtins it needs (positive control: command -v node fails under that PATH): exit 0, statusline prints the passthrough, hooks prints nothing, no spool file; then, with node on PATH, runs a copy of the launcher in a TEST_DIR directory without live-spool.mjs: exit 0, empty stderr, statusline prints the passthrough, a redirected 1 MB hooks payload is drained without a broken pipe | `sed:s/if \[\[ \$rc -ne 0 \]\]; then/if false; then/` on .aai/scripts/live-spool.sh | green |
| TEST-2410 | Spec-AC-04 | integration | tests/skills/test-aai-live-status.sh | test_2410_ps1_launcher_without_node runs live-spool.ps1 under pwsh with a PATH that resolves pwsh but not node (same positive control): exit 0, statusline prints the passthrough, no spool file; then, with node on PATH, runs a copy of the launcher in a TEST_DIR directory without live-spool.mjs: exit 0, empty stderr, statusline prints the passthrough, a redirected 1 MB hooks payload is drained; finally the real launcher with node and the module present exits 0, keeps stderr empty and writes exactly one line | `sed:s/if \(-not \$Ran\)/if ($false)/` on .aai/scripts/live-spool.ps1 | green |
| TEST-2411 | Spec-AC-05 | integration | tests/skills/test-aai-live-status.sh | test_2411_launcher_parity pipes the six payloads through live-spool.sh and through pwsh -File live-spool.ps1 into separate spool dirs and compares stdout and the spool files after replacing ts values; positive control: the object payload produced one line on each side | `sed:s/& node \$Module \$Kind/& node $Module 'hooks'/` on .aai/scripts/live-spool.ps1 | green |
| TEST-2412 | Spec-AC-05 | integration | tests/skills/test-aai-live-status.sh | test_2412_pester_live_spool runs Invoke-Pester on tests/skills/live-spool.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 6 | `sed:s/\[string\]\$Kind = 'statusline'/[string]$Kind = 'hooks'/` on .aai/scripts/live-spool.ps1 | green |
| TEST-2413 | Spec-AC-06 | integration | tests/skills/test-aai-live-status.sh | test_2413_seam_ps1_tap_quotas_render writes the test_011 payload through live-spool.ps1 under pwsh, runs the real generator on that spool and asserts quotas source tap, five_hour 33 and seven_day 12, and both percentages in the HTML | `sed:s/const STATUSLINE_FIELDS = \['rate_limits', 'cost'\];/const STATUSLINE_FIELDS = ['cost'];/` on .aai/scripts/live-spool.mjs | green |
| TEST-2414 | Spec-AC-07 | e2e | tests/skills/test-aai-live-status.sh | test_2414_downstream_sync_runs_tap runs .aai/scripts/aai-sync.sh into TEST_DIR/target with space, reads the statusLine and Stop commands from the real live-status-hooks.json, runs each with bash -c and CLAUDE_PROJECT_DIR set to the target and a payload on stdin, and asserts one line in each target spool file and the passthrough on the statusLine run | `sed:s/pwd\)\/live-spool\.mjs"/pwd)\/live-spool-moved.mjs"/` on .aai/scripts/live-spool.sh | green |
| TEST-2415 | Spec-AC-08 | inspection | tests/skills/test-aai-live-status.sh | test_2415_template_still_calls_sh_launcher parses the real live-status-hooks.json and asserts the statusLine, Stop and Notification commands each invoke bash on .aai/scripts/live-spool.sh with the documented kind | `sed:s/live-spool\.sh(\\" statusline)/live-spool.mjs$1/` on .aai/templates/hooks/live-status-hooks.json | green |
| TEST-2416 | Spec-AC-08 | inspection | tests/skills/test-aai-layer-profiles.sh | test_2416_live_spool_module_classified asserts .aai/scripts/live-spool.mjs appears exactly once in PROFILES.yaml, inside the extended list | `sed:s/live-spool\.mjs/live-spool-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-2417 | Spec-AC-08 | integration | tests/skills/test-aai-live-status.sh | test_2417_suite_map_selects_live_status feeds each of the three new paths to node .aai/scripts/select-suites.mjs --files-from - and requires a SELECTED aai-live-status line and no FULL_RUN line | `sed:s/live-spool\.mjs/live-spool-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-2418 | Spec-AC-08 | inspection | tests/skills/test-aai-live-status.sh | test_2418_ps1_quality_filter_has_module extracts the push and pull_request path lists of .github/workflows/ps1-quality.yml and requires both to contain .aai/scripts/live-spool.mjs and to be identical | `sed:s/live-spool\.mjs/live-spool-gone.mjs/` on .github/workflows/ps1-quality.yml | green |
| TEST-2419 | Spec-AC-09 | inspection | tests/skills/test-aai-live-status.sh | test_2419_rfc_phase3_row finds the Rollout Status row whose first cell is 3 and checks the unchanged description cell, status in progress, a link target ending in node-first-sync-hook-slice.md and the word live-spool | `sed:s/node-first-sync-hook-slice\.md/node-first-slice.md/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2420 | Spec-AC-10 | inspection | tests/skills/test-aai-live-status.sh | test_2420_line_budget_recorded parses live-spool pair 133 to N lines from the phase 3 row and requires N to equal the live wc -l sum of the three files and to be below 133 | `sed:s/live-spool pair 133 to (\d+) lines/live-spool pair 133 to 1$1 lines/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |

Test-file note: every row's selector is one bash function that runs alone under
single-function dispatch (`bash tests/skills/test-aai-live-status.sh <function>`,
`bash tests/skills/test-aai-layer-profiles.sh <function>`), because
`mutation-run.mjs` runs bash suites only (`fu-mutation-gate-skips-pester` stays
open; the Pester file is reached through the TEST-2412 wrapper). Mutation
patterns are JavaScript regular expressions with `(`, `)`, `[`, `]`, `.`, `+` and
`$` escaped as written; no row uses a flag. `check-test-registration.mjs` must
stay at exit 0.

### RED observations and positive controls

- TEST-2401 to TEST-2407: RED on the baseline because the module does not exist
  (import fails); the wrappers' zero-passing-tests guard makes a missing test
  name RED rather than vacuously green.
- TEST-2408: RED on the baseline (logic tokens and length in both scripts,
  non-ASCII bytes in live-spool.sh).
- TEST-2409: passes on the baseline (the Bash copy already degrades), so its RED
  is the mutation record, and its positive control (`command -v node` fails under
  the test PATH) is asserted first. TEST-2410 is RED on the baseline (the
  PowerShell copy writes a line without Node, D-9).
- TEST-2411 and TEST-2412: RED on the baseline through D-1 and D-2.
- TEST-2413: passes on the baseline (the old PowerShell copy also writes quotas);
  its RED is the mutation record. TEST-2414: RED on the baseline, because its
  first assertion (the synced target contains `.aai/scripts/live-spool.mjs`)
  fails; its mutation record moves the module path inside the launcher.
- TEST-2415: passes on the baseline (the template is unchanged by design); its RED
  is the mutation record.
- TEST-2416 to TEST-2420: RED on the baseline (entries and row absent).

## Verification

- Live-status suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-live-status.sh` exits 0, including test_001 to test_039 unchanged (`git diff main -- tests/skills/test-aai-live-status.sh` shows only added lines outside `main()` plus the added calls).
- Layer profiles: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` exits 0.
- Suite selection: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` exits 0.
- Windows-fallback pins on the path filter: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` exits 0.
- Direct Node tests: `node --test tests/skills/lib/live-spool.test.mjs` exits 0, under local Node 22.
- PowerShell gate: `bash tests/skills/test-ps1-quality.sh` exits 0 locally (PSScriptAnalyzer and the full Pester discovery, SkippedCount 0).
- Line budget: `wc -l .aai/scripts/live-spool.sh .aai/scripts/live-spool.ps1 .aai/scripts/live-spool.mjs` total below 133 and equal to the RFC row.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.

### Hosted delivery checks (after normal PR creation, before merge-readiness)

These are not Spec-ACs and are not claimed by local Validation.

- H1 (native Windows parity, intake AC-002): on the PR head, the ps1-quality
  run concludes success for `gate`, `windows-5_1` and `windows-wsl1`. In both
  `Full Pester suite discovery` steps of `windows-5_1` and in the one of
  `windows-wsl1`, every case of `live-spool.Tests.ps1` is listed as passed, the
  skipped count still equals `AAI_EXPECTED_WIN_SKIP_COUNT` (4), and the Node
  version case logs a major of 22 or higher. Evidence: run id, head SHA and the
  matched log lines from `gh run view <id> --log`. A failure of the non-ASCII
  case under 5.1 triggers the D2 fallback as a recorded amendment, not a waiver.
- H2 (Linux and Node 22 floor): the PR head's skill-suite run concludes success,
  with `aai-live-status` selected or a full run, and the step
  `Node 22 compatibility (downstream floor)` passing; its `node --test` output
  lists the TEST-2401 to TEST-2407 cases.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/node-first-sync-hook-slice/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. H1 and H2 are recorded separately after PR creation. Planning's
measurements above are inputs, not attestations of the implementation.

## Risks and rollback

- The Windows standard-input path (D2) is the one behavior no local host can
  prove; H1 decides it.
- A downstream user who wired `live-spool.ps1` by hand on a Windows host without
  Node loses spool lines (D-9). The live-status reader needs Node, so that host
  could not show them anyway; the product doc names it.
- The phase 3 row edit on an open umbrella RFC can trip the docs-audit
  false-open check at close; handle it with a fresh `doc_lifecycle` event, as
  earlier phase children did.
- Rollback is one revert of the scope's files; the template and the hook
  commands never change, so installed overlays need nothing.

## Registry disposition

Related open registry items, all left open:

- `fu-mutation-gate-skips-pester`: this scope reaches its Pester file through a
  bash wrapper (TEST-2412) instead of extending the gate; the item's subject (no
  Pester mutation evidence in general) is unchanged.
- `fu-ps1-quality-outside-sweep-glob`: `test-ps1-quality.sh` is still outside the
  sweep glob; this scope runs it in Verification and through H1 only.

Registry items closed by this scope: none.
