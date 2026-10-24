---
id: spec-node-first-third-slice
type: spec
number: 249
status: done
mutation_gate: v1
frozen_sha256: 2664d54c7d6e9f43c4711c5bd276a6fed2a4a5c34af1f74e2068848baca2ac4c
ceremony_level: 2
links:
  requirement: node-first-third-slice
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the expert prompt fetcher to one Node module and close RFC-0017 phase 3

SPEC-FROZEN: true

## Links

- Requirement: [Third Node-first slice and phase 3 closeout](../issues/CHANGE-0224-node-first-third-slice.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  Proposal section 1 and owner decisions 1.5 (phases 3 to 5 in order), 2 (Node
  22 floor downstream, Node 24 CI), 3 (YAML stays where a human edits it) and 4
  (no new runner).
- Pattern precedents: [SPEC-0247](SPEC-0247-spec-node-first-sync-hook-slice.md)
  (live-spool) and [SPEC-0248](SPEC-0248-spec-node-first-second-slice.md)
  (triage), including the SPEC-0247 D2 disclosure on the Windows PowerShell 5.1
  stdin BOM.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no dependencies).
- Baseline: main `4d4566bc`; the ride branch adds only the intake and the #496
  sign-off records (`3c1f916a`).

## Implementation strategy

- Strategy: hybrid
- Rationale: the new module and the two launchers are new behavior with
  recorded drift decisions, so every row that gates them goes RED first on the
  baseline (the module does not exist; each old copy fails at least one drift
  case) and carries a mutation record (TDD). The wiring edits (PROFILES, suite
  map, the ps1-quality path filter), the RFC row, the remaining-pairs inventory
  and the two amended status checks are mechanical and done in loop mode, but
  each one is pinned by a mutation-gated row.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped scripts, a CI workflow,
  the vendored profile manifest, two existing suites and an umbrella RFC; the
  ride already runs in its own linked worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: change/node-first-third-slice at /private/tmp/aai-node-first-3
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/expert-fetch.mjs .aai/scripts/expert-fetch.sh
  .aai/scripts/expert-fetch.ps1 .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/test-aai-expert-fetch.sh
  tests/skills/lib/expert-fetch.test.mjs tests/skills/expert-fetch.Tests.ps1
  tests/skills/test-aai-layer-profiles.sh tests/skills/test-aai-live-status.sh
  tests/skills/test-aai-triage.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl CHANGELOG.md
  docs/issues/CHANGE-0224-node-first-third-slice.md
  docs/specs/SPEC-0249-spec-node-first-third-slice.md
  (suite-weights.tsv only if the selector asks for a row;
  tests/skills/lib/cd-subshell-leak-baseline.tsv is added only if the checker
  asks for a re-record).
- Code review required: true.

## Pair selection (measured)

Measured on the planning tree (macOS arm64, bash with `/usr/bin/grep`, BSD sed,
Node 22.23.1, pwsh 7.6.3) on 2026-10-24. Lines are `wc -l`. Commits are
`git log --oneline -- <file>`; "joint" counts commits touching both copies and
"one-sided" names commits that changed one copy only. Callers are tracked files
outside docs/ai, specs, issues, RFCs, analysis and CHANGELOG that name the `.sh`
or `.ps1` file, excluding the pair itself. L3 is `protected_paths_l3` in
docs/ai/docs-audit.yaml (`.aai/system` holds no such key; measured). Drift
probes ran both copies on the same scratch fixtures (a copy of the real registry
with three appended test experts, and a stub `gh` that prints base64 of a fixture
prompt and logs its arguments).

| Pair | Lines sh/ps1 | Commits sh/ps1 (joint, one-sided) | Callers | When it runs | Node before install | Network or token | Platform-specific content | L3 | Existing executing tests | Measured drift | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| expert-fetch | 232/212 = 444 | 3/3 (2; 94a983ec sh, ee492fbd ps1) | 7: four role prompts (IMPLEMENTATION step 6b, SKILL_TDD GREEN and REFACTOR, EXPERT_RESOLVE, AGENTS) tell every Implementation and TDD dispatch to run the sh copy; PROFILES; hygiene comment; cd-subshell baseline | on demand inside every Implementation and TDD GREEN step (optional); no cache exists in this repository or its main checkout, so observed runs are zero | no: only role prompts call it, inside an AAI project whose tooling is Node | yes: `gh api` with gh's own stored auth, read-only, pinned SHA | sh: BSD `sed -i` breaks every fetch on macOS, `base64 -d`, `mktemp`; ps1: Write-Error under Stop | no | none (hygiene comment only) | 13 measured, 3 by inspection, 5 exit-code drifts, 1 security check missing in sh | CHOSEN |
| aai-live | 125/90 = 215 | 1/1 (1, 0) | 6 | manual dashboard launch | already requires Node (refuses without it) | no | browser opener per OS (`open`, `xdg-open`, `Start-Process`) | no | live-status suite (opener refusal) | by inspection: `AAI_LIVE_OPENER` honoured by sh only; ps1 warm-up stderr not suppressed | rejected: already a thin wrapper around a Node generator; what is left is platform opener choice, so the slice would retire little logic |
| cloudflare-share | 78/69 = 147 | 5/4 (4; 94a983ec sh) | 6 | manual publish (aai-share skill) | already requires Node (share-convert.mjs) | yes: wrangler deploy with wrangler's login or token, write effect on Cloudflare Pages | wrangler resolution | no | none | measured: sh `grep -oP` is invalid on macOS BSD grep (`invalid option -- P`, rc 2), so a macOS deploy ends without a URL or record; by inspection: JSON record not escaped in sh, unordered keys and real-byte size in ps1 | rejected: an external write effect needs a staged-deploy test seam larger than the slice, and it runs rarely; the macOS bug is a suggested follow-up |
| migrate-state-to-local | 162/175 = 337 | 5/7 (4; 94a983ec sh, e810522a ps1, fe82e9fe ps1, ee492fbd ps1) | 9 (aai-sync prints it as the next step) | one-off legacy migration (RFC-0001) | yes, possible: aai-sync names it for a target that may not have Node yet | no | none | no | sync-seed reads the name only | not probed | rejected: one-off, git-only, would add a Node dependency to a migration that has none |
| aai-canonicalize | 276/281 = 557 | 5/3 (3; f2201aa5 sh, 85c040e8 sh) | 3 | one-off structure migration | no | no | none | no | none | not probed | rejected: one-off; its telemetry step depends on migrate-yaml-to-jsonl, which needs python3 and PyYAML |
| aai-release | 365/414 = 779 | 9/11 (7; 230921a8 sh, ffe3f320 sh, 789c5c03 ps1, 42d9e8af ps1, 8cc930b7 ps1, 5f17df4d ps1) | 20 | every release cut | finish step already needs Node (release-finish.mjs) | yes: git push, gh release and PR writes | protected-branch recovery, 5.1 native stderr | no | bash suite (2389 lines) and two Pester files | not probed | rejected: 779 lines with write effects and the most active history; too large for one slice, and its newest logic already lives in Node modules |
| validate-skills | 47/55 = 102 | 5/3 (3, 2 sh-only) | 5 | every CI run through the self-hosting smoke | no | no | none | no | sh copy through the self-hosting smoke | cosmetic only (SPEC-0248) | rejected again, for SPEC-0248's reason: twelve file-existence checks and cosmetic drift |

Already decided by SPEC-0248, not re-measured here: pre-compact-save (rejected:
no install wires it), migrate-yaml-to-jsonl (rejected: needs a YAML parser that
Node's stdlib lacks; one-off), pre-commit-checks (disqualified: L3 protected
surface and a pre-Node degrade path) and aai-update (disqualified: a caller runs
before Node is installed). Process supervision (aai-run-tests, aai-reap-tests,
autonomous-loop) and the two largest pairs (aai-sync, install-pre-commit-hook)
are out of bounds by the intake.

Why expert-fetch:

- It is the pair with the most logic within bounds (444 lines): a registry
  parser, a 40-entry detection table, phase eligibility, a cache keyed by the
  pinned SHA, a network fetch, a size limit, a prompt-injection filter and a
  dangerous-command filter.
- Its drift is a security drift, not a cosmetic one. The sh copy never applies
  the blocked-category check (it fetched `09-meta-orchestration` through the
  stub, D-1), and on macOS every sh fetch fails after the network call because
  BSD `sed -i` takes `-e` as a backup suffix (D-2). Five cases change the exit
  code.
- Its callers are the role prompts every Implementation and TDD dispatch reads,
  so it is the widest-reaching candidate, even though it is optional and no run
  is observed here.
- No caller runs before Node is installed: only agent role prompts call it.
- The network effect is read-only and goes through one binary (`gh`), so a
  stub binary named by the existing `AAI_GH_BIN` seam (aai-feedback-status.mjs,
  pr-platform.mjs, hitl-channel.mjs) tests it offline with no token.
- It is in the `extended` profile with its registry, so the downstream test is
  an extended install.

What it does not show: observed run frequency. aai-live runs more often by hand
but has little logic left, and validate-skills runs in every CI run with almost
none. The evidence is not evenly split, so no owner question is raised.

## Drift between the two copies (measured) and decisions

Both copies ran on the same fixture root (`.aai/scripts/` with both copies,
`.aai/system/EXPERT_REGISTRY.yaml` as a copy of the real registry plus three
appended experts: `zblocked` with path `09-meta-orchestration/orchestrator.md`,
`znouse` with a path and no `use_in`, `zafter` with `use_in: [tdd-green]`), the
stub `gh` first on PATH, under bash 3.2 with BSD tools and under pwsh 7.6.3.
Windows PowerShell 5.1 was not available to Planning; rows marked "by
inspection" were read from the code.

| Id | Case | Bash copy | PowerShell copy | Decision |
|---|---|---|---|---|
| D-1 | fetch of an expert in a blocked category | not blocked: the awk range `/^blocked_categories:/,/^[a-z]/` closes on its own first line; the stub was called for `zblocked` | blocked, exit 1, but by a regex that matches `- <category>` anywhere after the heading | parse the `blocked_categories:` list: the heading may carry trailing spaces or a `#` comment; blank lines and comment lines inside the list are skipped; a dash item at any indent deeper than the heading counts, and a stray indented line that is not a dash item is skipped without ending the list (the list ends at the first line that starts in column 0 and is not a comment, the old ps1 regex `blocked_categories:[\s\S]*?- <category>` under case-insensitive `-match` matched a category anywhere after the heading, so it blocked more than this parser in four classes, measured with pwsh 7: it is case-insensitive (`- ZBlocked` blocked `zblocked`), it matches a prefix (`- zblocked-extra`), it matches inside a comment (`# - zblocked`), and it has no list boundary (a dash item under a later top-level key, text after the list that contains `- zblocked`, an unindented dash after the list, and a duplicate second heading in compact column-0 style all blocked). The first three classes are old false positives, because the category is compared exactly here; in the fourth class the dash item under a later key and the text after the list are false positives, while the compact duplicate heading and the unindented dash can be a real intent that this parser does not read. This parser does not block any of these shapes, and that gap is accepted and recorded, not claimed as parity; in the other direction this parser also blocks quoted items and the flow form, which the old regex missed); each item loses a `#` comment and one pair of matching single or double quotes, and an item that is empty after that is dropped; a second `blocked_categories:` heading adds its items to the first (the union, as the old ps1 regex did); the flow form `[a, b]` is read and `[]` is an explicit empty list; compare the category exactly. A registry whose headings yield no item at all (and none is `[]`) fails closed: every fetch and every `--body` prints `ERROR: blocked_categories in the registry has no readable item; refusing to serve experts` on stderr and exits 1, never running gh. A blocked category prints `ERROR: Category '<c>' is blocked in registry` on stderr and exits 1; fetch never runs gh, and `--body` applies the same check before it prints a cached prompt (the sh copy printed any cached file) |
| D-2 | dangerous-line strip after a successful fetch on macOS | `sed: -e: No such file or directory`, exit 1 after the network call (BSD `sed -i` takes `-e` as its suffix); on GNU sed it works | works | Node string processing; no sed, base64 or mktemp |
| D-3 | strip of `GIT PUSH upstream` and `Rm -Rf /` | kept (sed patterns are case-sensitive; by inspection, as D-2 stops macOS first) | removed (`-notmatch` is case-insensitive; measured) | case-insensitive (the stricter one) |
| D-4 | prompt of 8195 UTF-8 bytes (8192 characters) against `max_prompt_bytes: 8192` | `REJECTED: Expert prompt too large (    8195 > 8192 bytes)` (BSD wc padding), exit 1 | accepted (counts UTF-16 characters) | UTF-8 bytes, as the registry key says; message `REJECTED: Expert prompt too large (8195 > 8192 bytes)` without padding |
| D-5 | `--check znouse tdd-green` (no `use_in` in the expert's block) | `eligible`, exit 0 (reads the next expert's `use_in`) | `not-found`, exit 2 | lookups stay inside the expert's block: `not-found`, exit 2; the same bound applies to `path:` in fetch mode |
| D-6 | `--detect zzzz` (no match) | no output, exit 1 (pipefail on an empty grep) | no output, exit 0 | exit 0 with no output (the prompts read "returns 0-2 keys") |
| D-7 | fetch of a key not in the registry | `ERROR: Expert 'nosuch' not found in registry`, exit 2 | exit 1 (Write-Error under `Stop` terminates before `exit 2`; the class of `fu-ps1-writeerror-terminates-before-exit`) | exit 2, the documented code |
| D-8 | `pwsh -File expert-fetch.ps1 -Detect ts py docker` | n/a (`--detect ts py docker` gives `docker`, `python`) | `typescript` only: under `-File` only the first token binds to `-Detect` | the ps1 launcher forwards every detect token; output `docker`, `python` |
| D-9 | `--body` of a cached prompt whose body holds a `---` line | every `---` line in the body is dropped | kept, and the whole body is trimmed | the lines after the second `---` line, verbatim, `---` lines kept, ending in one LF; a prompt without leading frontmatter prints whole |
| D-10 | registry with CRLF line ends (`.yaml` has no eol rule in .gitattributes) | `--list` prints 0 keys | `--list` prints 110 keys | remove one trailing CR from every registry line |
| D-11 | cache and SHA files written by Windows PowerShell 5.1 | by inspection: `cat` keeps the BOM, so the SHA never matches and every call refetches; `--body` misses the BOM'd first `---` | by inspection: 5.1 `Set-Content -Encoding UTF8` writes a BOM into both files; pwsh 7 does not (measured) | the module writes UTF-8 without BOM and removes one leading BOM when it reads the registry, the cache file and the SHA file |
| D-12 | key or phase holding regex characters (`--check type.cript impl`) | `eligible` (key interpolated into an awk regex) | `eligible` (key interpolated into a .NET regex) | the key is compared literally (`not-found`, exit 2); the phase stays a substring test, done literally (shared substring behavior kept: `tdd` still matches `tdd-green`) |
| D-13 | registry without `max_prompt_bytes` | by inspection: `[ N -gt "" ]` errors inside `if`, so no size check runs | 8192 | 8192 |
| D-14 | gh fails, is absent, hangs, or prints nothing usable | pipeline failure gives `ERROR: Failed to fetch <path> at SHA <sha>`, exit 1 | Write-Error record, exit 1 | the module runs `env.AAI_GH_BIN` or `gh` with `spawnSync` (no shell, stdin ignored, 60 s timeout, SIGKILL); a non-zero exit, a spawn error, a timeout, or output that does not decode to non-empty text prints `ERROR: Failed to fetch <base>/<path> at SHA <sha>`, exits 1, and leaves the cache untouched. The timeout is new: an optional step must not hang a dispatch |
| D-15 | cache write | temp file plus `mv` | direct `Set-Content` | temp file in the cache directory, then rename; the SHA file is written after the prompt |
| D-16 | error text | plain lines on stderr | decorated Write-Error records, and ps1-specific usage text | plain one-line messages from the sh copy's text, on stderr; the usage text names `expert-fetch.sh` |
| D-17 | position of the force flag | only as the second argument | any position (switch) | `--force` anywhere after the key |
| D-18 | Node absent or module missing | today: needs bash, awk, sed, base64 and gh; never Node | needs gh only | each launcher prints exactly `ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)` on stderr and exits 1 (the documented error code; expert resolution is optional in every caller) |
| D-19 | prompt-injection patterns | five patterns, case-insensitive, per line | same five, case-insensitive | unchanged |
| D-20 | `--list` | keys matching `^  [a-z][a-z0-9_-]*:$`, 110 on the real registry (113 in the test fixture, which adds three experts) | same, 110 | unchanged, after D-10 and D-11 normalisation |
| D-21 | repository root | the logical script path, two directories up | same | the real path of the module (`import.meta.url`), two directories up, as live-spool and triage do |
| D-22 | `--body` with an argument that is not a plain registry key (`../x`, an upper-case or dotted name) | reads `<cache>/<arg>.md` for any argument, so `--body ../x` can print a file outside the cache | same, by inspection | the argument must match `^[a-z][a-z0-9_-]*$`; otherwise the not-cached line on stderr and exit 1, and no file outside the cache directory is read |
| D-23 | a failed cache write (read-only directory, a directory where the cache file belongs) | the `mv` of a `mktemp` file in the system temp directory fails with mv's own message under `set -e` | `Set-Content` error record | the module prints `ERROR: Cannot write the cache under <dir>: <code>` on stderr, exits 1 and removes its own `.tmp_<key>_<pid>` file on a best-effort basis, so no temporary file stays in the cache directory; the line and exit 1 hold for every failure shape, including a regular file where `.aai/cache` or `.aai/cache/experts` belongs and a directory at the `.tmp_` path, and the cleanup itself never throws |
| D-24 | a directory or other non-regular file at `.aai/cache/experts/<key>.md` (with a valid SHA file) | `-f` is true for regular files only, so it is a cache miss and `--body` prints the not-cached line | `Test-Path` is true for a directory too (measured with pwsh 7: `True` for a directory), so it reports a hit and `Get-Content` then fails | regular files only, for the registry, the cache file and the SHA file: a non-file cache path is a miss, so fetch refetches (a rename that a directory blocks ends in the D-23 line) and `--body` prints the not-cached line and exits 1, never a stack trace |

The module never reads standard input. Its text inputs are the registry, the
cache and SHA files (D-10 and D-11 handle CR and BOM there) and gh's standard
output (base64 decoding ignores CR and LF).

## Scope and design

### D1. The module `.aai/scripts/expert-fetch.mjs`

Dependency-free ESM, Node 22 compatible (only `node:fs`, `node:path`,
`node:url`, `node:child_process`), at most 200 lines, ASCII only. Importing it
has no side effects. It never reads standard input. It writes only under
`<root>/.aai/cache/experts/`. It contains these exact lines (mutation anchors):

```js
export const DEFAULT_MAX_BYTES = 8192;
const BOM = String.fromCharCode(0xfeff);
const CR = String.fromCharCode(13);
const STRIP_FLAGS = 'i';
const NOT_FOUND = 2;
const DETECT_EMPTY_CODE = 0;
const blockEnd = (line) => indentOf(line) <= 2;
const blocked = reg.blocked.includes(category);
const size = Buffer.byteLength(text, 'utf8');
const force = rest.includes('--force');
const bin = env.AAI_GH_BIN || 'gh';
const ghOk = r.status === 0 && !r.error;
const decoded = Buffer.from(out, 'base64').toString('utf8');
const body = lines.slice(close + 1);
renameSync(tmp, cacheFile);
process.exitCode = main({ argv: process.argv.slice(2) });
```

Each anchor line appears exactly once. No comment in the module may repeat an
anchor's text.

Exports (pure functions take text, not paths, so `node:test` needs no fixture
tree except where named):

- `parseRegistry(text)` returns `{ repo, pinnedSha, basePath, maxBytes, blocked, blockedBroken, keys, experts }`.
  One leading BOM is removed and every line loses one trailing CR. `keys` holds
  every line matching `^  [a-z][a-z0-9_-]*:\s*$` in file order (D-20).
  `experts` maps a key to `{ path, useIn }`, read only from the lines of that
  key's block (`blockEnd` ends it, D-5). `maxBytes` defaults to
  `DEFAULT_MAX_BYTES` (D-13). `blocked` is the D-1 list and `blockedBroken` is true when the heading yields no item and is not `[]`. `blockedRefusal(reg, key)` returns the refusal result or null and serves both fetch and `--body`.
- `detect(tokens, reg)` returns `{ code, out }`: each token is lower-cased and
  loses one leading dot; the 40-entry table of the old copies maps it (the
  table is identical in both copies, measured), otherwise a token equal to a
  registry key matches itself (literal, D-12); the result is sorted, unique and
  cut to two. No match gives `DETECT_EMPTY_CODE` (D-6).
- `checkPhase(reg, key, phase)` returns `{ code, out }`: `eligible` 0,
  `not-eligible` 1, `not-found` `NOT_FOUND`; missing arguments give the usage
  line on stderr and 1.
- `stripFrontmatter(text)` implements D-9 after removing one leading BOM.
- `sanitize(text, maxBytes)` returns `{ ok, text, error }`: the size check
  (D-4), then the five injection patterns (case-insensitive, any line, D-19),
  then removal of every line matching `git push`, `git reset --hard`, `rm -rf`,
  `force.push` or `--no-verify` with `STRIP_FLAGS` (D-3). Lines are split on LF;
  a CR stays with its line.
- `fetchExpert({ root, reg, key, force, runGh })` implements fetch mode: unknown
  key gives `NOT_FOUND` (D-7), blocked category gives 1 without calling `runGh`
  (D-1), a cache hit (prompt and SHA file present, SHA equal to the pinned SHA
  after BOM and whitespace removal) prints the cache path without calling
  `runGh`, otherwise `runGh(args)` with
  `['api', 'repos/<repo>/contents/<base>/<path>?ref=<sha>', '--jq', '.content']`,
  then D-14, `sanitize`, and the D-15 write. It returns `{ code, out, err }`.
- `main({ argv, root, env, stdout, stderr, runGh })`: `root` defaults to two
  directories above the module's real directory (D-21); `env` defaults to
  `process.env`; `runGh` defaults to the `spawnSync` call of D-14. Modes:
  `--list`, `--detect <tok>...`, `--check <key> <phase>`, `--body <key>`,
  otherwise `<key> [--force]`. No arguments print the five usage lines of the
  old sh copy on stderr and return 1. A missing registry prints
  `ERROR: Registry not found at <path>` and returns 1; a registry without
  `pinned_sha` or `repo` prints `ERROR: Invalid registry - missing pinned_sha or repo`
  and returns 1 in fetch mode. Standard output carries only results; every
  error goes to stderr as one line (D-16).

CLI: when run as the main module (real path of `process.argv[1]` equals the real
path of `fileURLToPath(import.meta.url)`), the anchored `process.exitCode` line
runs. It sets the exit code instead of calling `process.exit`, so piped output
is flushed.

### D2. The launchers

Both keep their names and their flags. Each is ASCII only and holds none of
these tokens: `awk`, `sed`, `base64`, `gh api`, `blocked_categories`,
`use_in`, `pinned_sha`, `REJECTED`, `previous`, `Select-String`,
`FromBase64String`, `Set-Content`. The literal
`ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)` appears exactly
once, in the fallback, which runs when Node is absent or the module file is
absent and never reads standard input.

`expert-fetch.sh`, at most 10 lines (the anchored lines are exact):

```bash
#!/usr/bin/env bash
# Expert fetch launcher; the logic lives in expert-fetch.mjs (RFC-0017 phase 3).
# Usage: bash .aai/scripts/expert-fetch.sh <key> [--force] | --detect <tok>... | --body <key> | --list | --check <key> <phase>
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/expert-fetch.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)" >&2
exit 1
```

`expert-fetch.ps1`, at most 20 lines (the anchored lines are exact; this shape
was run under pwsh 7.6.3 against a stub module and produced the argument lists
named in TEST-2615):

```powershell
#!/usr/bin/env pwsh
# Expert fetch launcher; the logic lives in expert-fetch.mjs (RFC-0017 phase 3).
# Usage: see expert-fetch.mjs (--list, --detect, --check, --body, <key> [--force]).
[CmdletBinding(PositionalBinding = $false)]
param([string]$ExpertKey, [switch]$Force, [string[]]$Detect, [string]$Body, [switch]$List, [string]$Check, [string]$Phase,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$Module = Join-Path $PSScriptRoot 'expert-fetch.mjs'
$Rest = @($Rest | Where-Object { $_ })
if ($List) { $NodeArgs = @('--list') }
elseif ($Detect) { $NodeArgs = @('--detect') + $Detect + $Rest }
elseif ($Check) { $NodeArgs = @('--check', $Check) + @($Phase | Where-Object { $_ }) + $Rest }
elseif ($Body) { $NodeArgs = @('--body', $Body) }
else { $NodeArgs = @($ExpertKey | Where-Object { $_ }) + $Rest; if ($Force) { $NodeArgs += '--force' } }
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @NodeArgs
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)')
exit 1
```

The PowerShell launcher sets no `$ErrorActionPreference`, writes its one error
line with `[Console]::Error` (no Write-Error record, so no 5.1 terminating
error), and lets Node write to the inherited standard output, so PowerShell
neither raises on a native command's stderr nor re-encodes the output.

Windows parity lessons from SPEC-0247 and SPEC-0248 (binding here):

- Any module of this program that reads standard input must tolerate one
  leading UTF-8 BOM, because a .NET Framework writer (the Windows PowerShell 5.1
  Pester harness among them) prefixes EF BB BF to a child's redirected standard
  input. This module reads none (TEST-2612 pins that) and applies the same rule
  to the files it reads (D-11).
- Hosted Windows PowerShell 5.1 Pester is the only proof of Windows parity; no
  local host provides it (H1).
- A failure seen only on the hosted job is diagnosed with a probe before any
  code change (H1).
- The hosted skipped count stays at `AAI_EXPECTED_WIN_SKIP_COUNT` (4); the new
  Pester file adds no skip, and this scope does not change that value.

### D3. Wiring

- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/expert-fetch.mjs` in the
  `extended:` list next to the two launchers (they and the registry are
  extended). Companion obligation for a new `.aai/**` file. No prompt changes:
  every caller keeps calling `bash .aai/scripts/expert-fetch.sh`, so the prompt
  corpus and its diet ledger are untouched.
- `tests/skills/suite-map.yaml`: a new suite row `aai-expert-fetch` with the
  globs `.aai/scripts/expert-fetch.sh`, `.aai/scripts/expert-fetch.ps1`,
  `.aai/scripts/expert-fetch.mjs`, `tests/skills/lib/expert-fetch.test.mjs` and
  `tests/skills/expert-fetch.Tests.ps1`. The hygiene pin requires the row for
  the new `test-aai-expert-fetch.sh`.
- `.github/workflows/ps1-quality.yml`: add `'.aai/scripts/expert-fetch.mjs'` to
  both the `push` and the `pull_request` path lists, which must stay identical,
  plus whatever the PowerShell-read derivation in
  `tests/skills/test-aai-win-fallback.sh` (test_034 to test_036) requires. No
  job, runner or step is added (RFC-0017 decision 4). The new Pester file is
  discovered by the existing `Run.Path = 'tests/skills'` steps under Windows
  PowerShell 5.1 and pwsh 7 in `windows-5_1`, under 5.1 in `windows-wsl1`, and
  under pwsh 7 on Linux in `gate`.
- First-occurrence rule for the mutation anchors: no comment or earlier line
  may name `expert-fetch.mjs` before the `extended:` entry in PROFILES.yaml or
  before the `push` path list in ps1-quality.yml, and the RFC may not contain
  the backticked text `` `validate-skills` `` before the inventory row.
- `tests/skills/suite-weights.tsv`: add a row only if
  `test-aai-suite-select.sh` requires one for every suite.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: the launcher keeps one
  `cd` in a substitution (count 2 to 1, a shrink, which needs no re-record);
  re-record only if the checker asks.

### D4. Tests

- `tests/skills/lib/expert-fetch.test.mjs` (`node:test`, direct imports,
  temporary directories only, `runGh` injected; no test runs a real gh). Every
  test name starts with its TEST id.
- `tests/skills/test-aai-expert-fetch.sh`, a new suite: one function per row,
  each registered once in `main()`, each failure message naming its TEST id,
  runnable alone (`bash tests/skills/test-aai-expert-fetch.sh <function>`).
  Fixture roots are temporary directories holding copies of the two launchers
  and the module under `.aai/scripts/` and the fixture registry (the real
  registry plus the three D-table experts) under `.aai/system/`. The stub gh
  is a bash script named by `AAI_GH_BIN` that logs its arguments to a file and
  prints base64 of a fixture prompt, wrapped at 60 columns with LF. Functions
  that run `node --test` pass `--test-name-pattern '<TEST id>'` and also fail
  when the output reports zero passing tests. Functions that need `pwsh` fail
  when it is absent and `CI` is set, and otherwise print a `SKIP-CASE` line
  naming the missing tool and return 0. The Pester wrapper skips by name when
  Pester 5 is absent (the ps1-quality `gate` job is its authoritative runner).
- `tests/skills/expert-fetch.Tests.ps1` (Pester 5), at least 11 cases, none of
  which may skip on any host. Each case runs the launcher with the engine
  running the test (`(Get-Process -Id $PID).Path -NoProfile -File`), so the 5.1
  step tests 5.1, in a TestDrive root holding the launcher, the module and the
  fixture registry. Cases: the launcher parses with zero errors; `-List` prints
  the same number of keys as the registry holds (counted in the test with its
  own regex); `-Detect .TSX py docker` prints `docker` and `python`; `-Check
  typescript -Phase implementation` prints `eligible`, exit 0; `-Check znouse
  -Phase tdd-green` prints `not-found`, exit 2; a fetch of `nosuch` exits 2;
  `-Body typescript` over a cache file written with a UTF-8 BOM
  (`[IO.File]::WriteAllText` with a BOM encoding) prints the body without the
  frontmatter; a cache hit (prompt and SHA files with BOM) prints the cache
  path while `AAI_GH_BIN` names a file that does not exist (so any gh call
  would fail); a fetch without cache under that `AAI_GH_BIN` exits 1 with
  `ERROR: Failed to fetch` on stderr and creates no cache file; a launcher copy
  without the module beside it prints exactly the D-18 line on stderr and exits
  1; and one case prints `node --version` and asserts major 22 or higher.
  Assertions read ASCII lines only.
- One new function in `tests/skills/test-aai-layer-profiles.sh`.
- Amended status checks in two existing suites (D5).

### D5. RFC-0017: phase 3 row, inventory, amended checks

Phase 3 row. The Rollout Status row whose first cell is `3` keeps its
description cell and the whole first- and second-slice text byte for byte
(TEST-2518 of SPEC-0248 pins the first-slice text exactly). Its status cell
becomes `done`. Its delivered-by cell gains, after the second slice, the text
`; the [third slice](../issues/CHANGE-0224-node-first-third-slice.md) moved the expert prompt fetcher (expert-fetch pair 444 to <N> lines), a behavior with a network fetch, a cache and two security filters, and closed phase 3 with the remaining-pairs inventory below`,
where `<N>` is the `wc -l` sum of `expert-fetch.sh`, `expert-fetch.ps1` and
`expert-fetch.mjs` at delivery. The allocator rewrites the `CHANGE-DRAFT-` link
at merge; every check matches only the suffix `node-first-third-slice.md`.
The RFC frontmatter keeps `status: implementing` and `umbrella: true`; rows 0
and 2 stay `in progress`, rows 4 and 5 stay `not started`.

Inventory. A new subsection `### Remaining paired scripts after phase 3`
directly after the Rollout Status table holds one sentence naming the rule (a
pair is `.aai/scripts/<name>.sh` plus `<name>.ps1` with no `<name>.mjs`; counts
measured at the delivery commit) and this table, one row per pair, in this
order and with these values (counts measured on `4d4566bc`; Implementation
re-measures at delivery and updates any count that changed):

| Pair | Lines sh/ps1 | Destination | Reason |
|---|---|---|---|
| `aai-canonicalize` | 276/281 | later candidate | one-off structure migration; its telemetry step depends on migrate-yaml-to-jsonl (python3 and PyYAML) |
| `aai-live` | 125/90 | later candidate | already requires Node; what remains is browser-opener choice around generate-live-status.mjs, which a later slice can fold into that generator |
| `aai-reap-tests` | 368/419 | phase 5 process adapter | reaps process groups and Windows process trees (process supervision migrates last) |
| `aai-release` | 365/414 | later candidate | 779 lines with git and gh write effects and the most active history; its finish step already lives in release-finish.mjs |
| `aai-run-tests` | 958/942 | phase 5 process adapter | supervises suite processes, timeouts and orphan cleanup |
| `aai-sync` | 1039/1087 | platform adapter kept on purpose | installs AAI into a target before Node is guaranteed there (bootstrap before Node is installed) |
| `aai-update` | 180/188 | platform adapter kept on purpose | a caller runs before Node is installed (SPEC-0248) |
| `autonomous-loop` | 488/464 | phase 5 process adapter | supervises agent child processes |
| `cloudflare-share` | 78/69 | later candidate | external deploy with a write effect; needs a staged-deploy test seam; the sh copy's grep -oP fails on macOS |
| `install-pre-commit-hook` | 1313/1097 | platform adapter kept on purpose | hook installation, file permissions and symlinked configuration |
| `migrate-state-to-local` | 162/175 | platform adapter kept on purpose | git-only legacy migration that aai-sync names for a target that may not have Node yet; retire with RFC-0001 legacy support instead of porting |
| `migrate-yaml-to-jsonl` | 126/151 | later candidate | needs a general YAML parser that Node's stdlib lacks; one-off (SPEC-0248) |
| `pre-commit-checks` | 323/281 | platform adapter kept on purpose | L3 protected surface whose checks 1 to 7 run without Node; a move needs its own L3 scope |
| `pre-compact-save` | 77/87 | later candidate | no shipped install wires the hook (SPEC-0248) |
| `validate-skills` | 47/55 | later candidate | twelve file-existence checks with cosmetic drift (SPEC-0248) |

Destination values are exactly `phase 5 process adapter`, `platform adapter
kept on purpose` or `later candidate`. No cell holds a pipe character.

Amended status checks. TEST-2419 (`tests/skills/test-aai-live-status.sh`,
SPEC-0247 Spec-AC-09) and TEST-2518 (`tests/skills/test-aai-triage.sh`,
SPEC-0248 Spec-AC-09) assert `| in progress |`, which the owner's decision to
close phase 3 makes false. Each status assertion changes to accept
`| in progress |` or `| done |`; every other assertion in both functions stays
as it is, and the frozen bodies of SPEC-0247 and SPEC-0248 are not edited.
The justification is recorded with
`node .aai/scripts/spec-amend.mjs add --class contract --signoff owner`, one
record per spec, with `--authority` naming the owner's menu answer of
2026-10-24 ("one more slice, then close phase 3", intake Notes):
`--ref node-first-sync-hook-slice --spec docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md`
with a `--what` that begins `TEST-2419 status check accepts done`, and
`--ref node-first-second-slice --spec docs/specs/SPEC-0248-spec-node-first-second-slice.md`
with a `--what` that begins `TEST-2518 status check accepts done`. Both records
must be signed: TEST-2520 of SPEC-0248 requires every
node-first-sync-hook-slice record to be signed, and TEST-2626 requires the same
for node-first-second-slice.

After LOOP COMPLETE (ship convention, not gated by a TEST row, in the review
scope): `CHANGELOG.md` gains one
`## [unreleased] — refactor(expert-fetch): one Node module owns the expert prompt fetcher`
entry naming D-1, D-2, D-4, D-7 and D-18 and the phase 3 closeout. No product
doc describes expert-fetch (measured), so none is edited.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-08 (launchers hold no copy) and Spec-AC-01 to
  Spec-AC-07 (the logic is in the module).
- Intake AC-002 maps to Spec-AC-09 (local parity and Pester under pwsh 7) and
  hosted check H1 (native Windows, both engines). No pre-existing test executes
  either copy (measured: a hygiene comment and the cd-subshell baseline name
  the sh file), so nothing else needs to keep passing beyond the suites in
  Verification.
- Intake AC-003 maps to Spec-AC-01 to Spec-AC-07; every D-row with a changed
  behavior has a named test (D-1 TEST-2604, TEST-2627, TEST-2628, TEST-2629, TEST-2630 and TEST-2633, D-2 and D-3 TEST-2606, D-4 and D-13
  TEST-2605, D-5 and D-12 TEST-2603, D-6 TEST-2602, D-7 and D-17 TEST-2609, D-8
  TEST-2615 and TEST-2616, D-9 TEST-2610, D-10 and D-11 TEST-2601, TEST-2607 and
  TEST-2610, D-14 and D-15 TEST-2607 and TEST-2608, D-16 TEST-2611, D-18
  TEST-2614 and TEST-2615, D-21 TEST-2611, D-22 TEST-2634, TEST-2635 and TEST-2630, D-23 TEST-2631 and TEST-2632, D-24 TEST-2636; D-1 residual list shapes TEST-2633).
- Intake AC-004 maps to Spec-AC-10 and Spec-AC-11.
- Intake AC-005 maps to Spec-AC-12.
- Intake AC-006 maps to Spec-AC-13, Spec-AC-14 and Spec-AC-15.
- Intake AC-007 maps to Spec-AC-16. The sign-off records were appended by the
  intake commit `3c1f916a`; the row pins them.

## Constitution deviations

None. Article 4 (degrade and report): without Node the launchers now print an
explicit error and exit 1 (D-18), and a hung gh can no longer hang a dispatch
(D-14). Article 5 (additive first): command names, flags and exit-code meanings
stay; the changed exit codes (D-5, D-6, D-7) and the newly enforced blocked
category (D-1) are named in the CHANGELOG entry. Article 2 (simplicity): no new
seam is invented; `AAI_GH_BIN` already exists in four scripts.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN parseRegistry from .aai/scripts/expert-fetch.mjs reads the real registry the system SHALL return the same keys in the same order as an independent count of lines matching two spaces, a lower-case key and a colon at line end; the same text with CRLF line ends and with a leading BOM SHALL give the identical result (D-10, D-11); a block without use_in SHALL not borrow the next block's value. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2601.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2601 |
| Spec-AC-02 | WHEN detect receives tokens the system SHALL map every entry of the old 40-entry table to its key, ignore case and one leading dot, match an exact registry key literally, return at most two keys sorted and unique, and return no output with code 0 when nothing matches (D-6). | done | docs/ai/tdd/node-first-third-slice/green/TEST-2602.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2602 |
| Spec-AC-03 | WHEN checkPhase runs the system SHALL return eligible with 0, not-eligible with 1 and not-found with 2, SHALL read use_in only inside the named expert's block (D-5) and SHALL compare the key literally (D-12). | done | docs/ai/tdd/node-first-third-slice/green/TEST-2603.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2603 |
| Spec-AC-04 | WHEN a fetch is requested the system SHALL refuse a blocked category with exit 1 before any gh call (D-1), SHALL reject a prompt above max_prompt_bytes counted in UTF-8 bytes with the unpadded message and default the limit to 8192 (D-4, D-13), SHALL reject the five injection patterns case-insensitively, and SHALL remove the dangerous lines case-insensitively (D-3); the blocked list SHALL be read with the D-1 spellings (commented heading, comment and blank lines, any deeper indent, quoted items, flow form) and SHALL fail closed with exit 1 and no gh call when the headings yield no item; a second heading SHALL add its items to the first, an empty item SHALL be dropped, and a stray indented line SHALL NOT truncate the list. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2604.log, docs/ai/tdd/node-first-third-slice/green/TEST-2605.log, docs/ai/tdd/node-first-third-slice/green/TEST-2606.log, docs/ai/tdd/node-first-third-slice/green/TEST-2627.log, docs/ai/tdd/node-first-third-slice/green/TEST-2628.log, docs/ai/tdd/node-first-third-slice/green/TEST-2630.log, docs/ai/tdd/node-first-third-slice/green/TEST-2633.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2604, TEST-2605, TEST-2606, TEST-2627, TEST-2628, TEST-2630, TEST-2633 |
| Spec-AC-05 | WHEN fetchExpert runs with an injected runGh the system SHALL pass the pinned contents arguments, decode wrapped base64 with LF or CRLF, write the prompt without BOM through a temp file and rename, write the SHA file, print the cache path, serve a cache hit (also with BOM'd files) without calling runGh, refetch on --force in any position (D-17), print the failed-fetch line and exit 1 with the cache untouched on a non-zero gh exit, a spawn error or undecodable output (D-14), exit 2 for an unknown key (D-7), and print exactly one Cannot-write line and exit 1 for any failed cache write (D-23). | done | docs/ai/tdd/node-first-third-slice/green/TEST-2607.log, docs/ai/tdd/node-first-third-slice/green/TEST-2608.log, docs/ai/tdd/node-first-third-slice/green/TEST-2609.log, docs/ai/tdd/node-first-third-slice/green/TEST-2631.log, docs/ai/tdd/node-first-third-slice/green/TEST-2632.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2607, TEST-2608, TEST-2609, TEST-2631, TEST-2632 |
| Spec-AC-06 | WHEN --body runs on a cached prompt the system SHALL print the lines after the second dash line verbatim, keeping dash lines in the body, ending in one LF, also when the cache file starts with a BOM (D-9, D-11), and exit 1 with the not-cached message when the file is absent; it SHALL apply the same blocked-category check as fetch (D-1) before printing, and SHALL refuse an argument that is not a plain registry key (D-22); a directory or other non-regular file at the cache path SHALL count as not cached for fetch and --body (D-24). | done | docs/ai/tdd/node-first-third-slice/green/TEST-2610.log, docs/ai/tdd/node-first-third-slice/green/TEST-2629.log, docs/ai/tdd/node-first-third-slice/green/TEST-2634.log, docs/ai/tdd/node-first-third-slice/green/TEST-2635.log, docs/ai/tdd/node-first-third-slice/green/TEST-2636.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2610, TEST-2629, TEST-2634, TEST-2635, TEST-2636 |
| Spec-AC-07 | WHEN the module CLI runs in a fixture root with AAI_GH_BIN naming a stub gh the system SHALL write the cache under that root, print only the cache path on stdout with empty stderr, and the stub SHALL receive exactly the pinned contents arguments; the module source SHALL contain no readFileSync(0 or process.stdin, and a fetch SHALL change only the two cache files under the fixture root. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2611.log, docs/ai/tdd/node-first-third-slice/green/TEST-2612.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2611, TEST-2612 |
| Spec-AC-08 | expert-fetch.sh (at most 10 lines) and expert-fetch.ps1 (at most 20 lines) are ASCII only, call expert-fetch.mjs from their own directory, hold none of the D2 logic tokens and the D-18 literal exactly once; WHEN node is not on PATH or the module is absent each launcher SHALL print exactly the D-18 line on stderr, nothing on stdout, and exit 1; WHEN node and the module are present the ps1 launcher SHALL forward the D2 argument mapping and return the module exit code. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2613.log, docs/ai/tdd/node-first-third-slice/green/TEST-2614.log, docs/ai/tdd/node-first-third-slice/green/TEST-2615.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2613, TEST-2614, TEST-2615 |
| Spec-AC-09 | WHEN the eleven parity fixtures run through expert-fetch.sh and through expert-fetch.ps1 under pwsh the system SHALL give identical stdout, stderr and exit code for each; tests/skills/expert-fetch.Tests.ps1 SHALL pass at least 11 cases with 0 skipped and 0 failed under local pwsh 7. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2616.log, docs/ai/tdd/node-first-third-slice/green/TEST-2617.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2616, TEST-2617 |
| Spec-AC-10 | WHEN aai-sync.sh installs the extended profile into a scratch git target whose path contains a space, the target SHALL contain .aai/scripts/expert-fetch.mjs, and bash .aai/scripts/expert-fetch.sh run there SHALL list as many keys as the target registry holds, report typescript eligible for implementation, and fetch typescript through a stub AAI_GH_BIN into the target's own cache; a core-profile target SHALL hold none of the three expert-fetch files. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2618.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2618 |
| Spec-AC-11 | PROFILES.yaml lists .aai/scripts/expert-fetch.mjs exactly once, in extended; select-suites.mjs selects aai-expert-fetch for each of the five suite paths with no FULL_RUN line; both ps1-quality.yml path lists contain .aai/scripts/expert-fetch.mjs and stay identical. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2619.log, docs/ai/tdd/node-first-third-slice/green/TEST-2620.log, docs/ai/tdd/node-first-third-slice/green/TEST-2621.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2619, TEST-2620, TEST-2621 |
| Spec-AC-12 | The phase 3 row records expert-fetch pair 444 to N lines, where N equals the live wc -l sum of expert-fetch.sh, expert-fetch.ps1 and expert-fetch.mjs and N is at most 230. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2622.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2622 |
| Spec-AC-13 | The RFC-0017 Rollout Status phase 3 row has status cell done, its description cell unchanged, the first- and second-slice text unchanged, and a link whose target ends in node-first-third-slice.md followed by the word expert-fetch; the RFC frontmatter keeps status implementing and umbrella true, rows 0 and 2 stay in progress and rows 4 and 5 stay not started. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2623.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2623 |
| Spec-AC-14 | The RFC-0017 subsection Remaining paired scripts after phase 3 lists exactly the set of names that have .aai/scripts/NAME.sh and NAME.ps1 and no NAME.mjs in the live tree, each row with two positive integer line counts, a destination from the three allowed values and a non-empty reason; aai-run-tests, aai-reap-tests and autonomous-loop are phase 5 process adapters and pre-commit-checks is a platform adapter kept on purpose. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2624.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2624 |
| Spec-AC-15 | test_2419_rfc_phase3_row and test_2518_rfc_phase3_row each exit 0 against the done row, and spec-amend list shows one signed contract record of ref node-first-sync-hook-slice whose what begins TEST-2419 and one of ref node-first-second-slice whose what begins TEST-2518. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2625.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2625 |
| Spec-AC-16 | spec-amend list over the repository ledger shows every spec_amendment record of ref node-first-second-slice as signed (at least three), and follow-ups list with status all shows fu-amend-spec-node-first-second-slice as done. | done | docs/ai/tdd/node-first-third-slice/green/TEST-2626.log, docs/ai/tdd/node-first-third-slice/green/suites.summary | tdd | TEST-2626 |

## Implementation plan

1. RED: write `expert-fetch.test.mjs`, `expert-fetch.Tests.ps1`,
   `test-aai-expert-fetch.sh` and the layer-profiles function; run each row's
   function alone on the unchanged tree and store the output under
   `docs/ai/tdd/node-first-third-slice/red/`. Expected RED: TEST-2601 to
   TEST-2612 fail because the module does not exist; TEST-2613 fails on the
   current scripts (logic tokens, length, non-ASCII bytes in expert-fetch.sh);
   TEST-2614 and TEST-2615 fail because both copies run without Node and the ps1
   copy has no `-Detect` forwarding or D-18 line; TEST-2616 fails on D-1, D-5,
   D-6, D-7 and D-8 through the current copies; TEST-2617 fails on the D-18,
   detect and not-found cases; TEST-2618 fails because the target lacks the
   module; TEST-2619 to TEST-2624 fail because the entries, row text and
   subsection do not exist; TEST-2625 fails on its ledger half (no TEST-2419
   record yet) and, after the RFC flip, on the old status assertions; TEST-2626
   passes on the baseline, so its RED is the mutation record.
2. Write the module (D1); TEST-2601 to TEST-2612 go green.
3. Replace both scripts with the launchers (D2); TEST-2613 to TEST-2618 go green.
4. Wiring (D3), the RFC row and inventory (D5), the two amended status checks
   and their two `spec-amend add` records; the rest go green.
5. Run the expert-fetch, layer-profiles, suite-select, hygiene-pack,
   win-fallback, live-status and triage suites through the wrapper,
   `test-ps1-quality.sh` locally, and record one mutation per row.

Seams crossed (each with a test that produces on one side and reads the real
result on the other):

- Launcher to module: TEST-2616 and TEST-2617 drive both real launchers into
  the real module; TEST-2614 and TEST-2615 cut Node or the module out from
  under them.
- Module to gh: TEST-2611 runs the real CLI against a stub binary through the
  real `AAI_GH_BIN` spawn and reads the arguments the stub received; TEST-2617
  crosses the Windows spawn with a missing binary (failure path) on the hosted
  job.
- Module to the registry humans edit: TEST-2601 parses the real registry and
  compares it with an independent count; TEST-2618 reads the registry a real
  extended install carries.
- Module to cache files another engine wrote: TEST-2617 writes BOM'd cache and
  SHA files from PowerShell and reads them through the module.
- Profile manifest to sync: TEST-2618 and TEST-2619, plus the existing
  layer-profiles conformance test (100% classification).
- Path filter to the Windows job, and suite map to the selector: TEST-2620 and
  TEST-2621 read the real files; the Windows job itself is crossed only on
  hosted CI (H1).
- RFC row to the earlier slices' checks: TEST-2625 runs the two amended
  functions of the other suites against the real RFC; TEST-2520 (unchanged)
  reads the new signed record.
- Inventory to the tree: TEST-2624 computes the pair set from the live
  `.aai/scripts/` directory.
- Module to Node 22: the existing Node 22 compatibility step runs
  `node --test tests/skills/lib/*.test.mjs`, which picks up the new file (H2).

Residual risks, written down:

- The fetch success path on native Windows (a real gh.exe writing base64 with
  CRLF) is not run by any test: no stub can be spawned there without a shell,
  and a real gh needs network and auth. The decoding is platform-neutral Node
  and is unit-tested with CRLF input; the Windows spawn itself is crossed by the
  failure-path Pester case.
- How Windows PowerShell 5.1 binds `-Detect ts py docker` and an in-session
  `--check` under `PositionalBinding = $false` was not measured; the Pester
  cases run under 5.1 in H1.
- The phase stays a substring test (D-12, shared): `--check typescript tdd`
  reads eligible. Suggested follow-up: `suggested: fu-expert-check-phase-substring`.
- The sh copy of cloudflare-share fails on macOS (`grep -oP`); not in this
  scope. Suggested follow-up: `suggested: fu-cloudflare-share-macos-grep-p`.
- The inventory TEST pins names, destinations and count shape, not live line
  counts, so later edits to those scripts do not redden it; Verification checks
  the counts once at delivery.
- Signing the two status-check amendments with the owner's 2026-10-24 decision
  as authority is the orchestrator's reading of that decision. If the owner or
  review rejects that reading, record them with `--signoff none` and a
  `fu-amend-` item; TEST-2520 and TEST-2625 then stay red until the owner signs,
  which is the intended stop.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2601 | Spec-AC-01 | unit | tests/skills/test-aai-expert-fetch.sh | test_2601_registry_parse runs node --test --test-name-pattern TEST-2601 on tests/skills/lib/expert-fetch.test.mjs: parseRegistry of the real registry gives keys equal to an independent regex count (110 on the real registry; the test fixture adds three experts, 113), repo, pinned SHA, base path, max bytes 8192 and the two blocked categories; the CRLF copy and the BOM copy give a deep-equal result; znouse has no useIn | `sed:s/const CR = String\.fromCharCode\(13\);/const CR = String.fromCharCode(1);/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2602 | Spec-AC-02 | unit | tests/skills/test-aai-expert-fetch.sh | test_2602_detect runs the TEST-2602 node cases: every token of the old table maps to its key (table written into the test from the baseline copy), .TSX py docker gives docker and python, a token equal to a registry key matches, type.cript matches nothing, zzzz gives code 0 and no output | `sed:s/const DETECT_EMPTY_CODE = 0;/const DETECT_EMPTY_CODE = 1;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2603 | Spec-AC-03 | unit | tests/skills/test-aai-expert-fetch.sh | test_2603_check_phase runs the TEST-2603 node cases: typescript implementation eligible 0, zafter implementation not-eligible 1, znouse tdd-green not-found 2, type.cript impl not-found 2, missing phase gives usage and 1 | `sed:s/const blockEnd = \(line\) => indentOf\(line\) <= 2;/const blockEnd = (line) => false;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2604 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2604_blocked_category runs the TEST-2604 node cases: fetch of zblocked returns 1 with the blocked line and the injected runGh is never called; a registry whose blocked list carries a trailing comment still blocks; an allowed category whose name appears later in the file as a list item is not blocked | `sed:s/const blocked = reg\.blocked\.includes\(category\);/const blocked = false;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2605 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2605_size_limit runs the TEST-2605 node cases: a prompt of 8195 bytes and 8192 characters is rejected with REJECTED: Expert prompt too large (8195 > 8192 bytes); 8192 bytes passes; a registry without max_prompt_bytes applies 8192 | `sed:s/const size = Buffer\.byteLength\(text, 'utf8'\);/const size = text.length;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2606 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2606_injection_and_strip runs the TEST-2606 node cases: each of the five injection patterns in mixed case is rejected; GIT PUSH upstream, Rm -Rf and a lower-case force push line are removed, an ordinary line and a CRLF line are kept byte for byte | `sed:s/const STRIP_FLAGS = 'i';/const STRIP_FLAGS = '';/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2607 | Spec-AC-05 | unit | tests/skills/test-aai-expert-fetch.sh | test_2607_fetch_and_cache runs the TEST-2607 node cases: an injected runGh returning base64 wrapped at 60 columns with CRLF gives a cache file equal to the sanitized prompt with no BOM, a SHA file equal to the pinned SHA, stdout the cache path and the exact contents arguments; a second call with BOM'd cache and SHA files makes no runGh call; --force before or after the key refetches | `sed:s/const decoded = Buffer\.from\(out, 'base64'\)\.toString\('utf8'\);/const decoded = out;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2608 | Spec-AC-05 | unit | tests/skills/test-aai-expert-fetch.sh | test_2608_fetch_failures runs the TEST-2608 node cases: runGh results with status 1 and valid base64 on stdout, a spawn error, empty stdout and non-base64 text each give the failed-fetch line, code 1, and leave an existing cache file byte-identical and create none where there was none | `sed:s/const ghOk = r\.status === 0 && !r\.error;/const ghOk = !r.error;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2609 | Spec-AC-05 | unit | tests/skills/test-aai-expert-fetch.sh | test_2609_exit_codes runs the TEST-2609 node cases: fetch of nosuch returns 2 with the not-found line, no arguments return 1 with the five usage lines naming expert-fetch.sh, a missing registry returns 1, a registry without pinned_sha returns 1 in fetch mode | `sed:s/const NOT_FOUND = 2;/const NOT_FOUND = 1;/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2610 | Spec-AC-06 | unit | tests/skills/test-aai-expert-fetch.sh | test_2610_body runs the TEST-2610 node cases: a cached prompt with frontmatter and a dash line in the body prints the body with the dash line and one final LF; the same file with a leading BOM prints the same; a prompt without frontmatter prints whole; an absent cache file gives the not-cached line and 1 | `sed:s/const body = lines\.slice\(close \+ 1\);/const body = lines.slice(close + 1).filter((l) => l !== '---');/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2611 | Spec-AC-07 | integration | tests/skills/test-aai-expert-fetch.sh | test_2611_cli_with_stub_gh runs node .aai/scripts/expert-fetch.mjs typescript in a fixture root with AAI_GH_BIN naming the stub and PATH holding node and the system directories but no gh (positive control: command -v gh fails under that PATH): exit 0, stdout exactly the fixture's cache path, stderr empty, the stub log holds exactly the pinned contents arguments, and the cache file holds the sanitized prompt | `sed:s/const bin = env\.AAI_GH_BIN /const bin = env.AAI_GH_BIN_GONE /` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2612 | Spec-AC-07 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2612_no_stdin_and_write_set checks the module source for readFileSync(0, process.stdin, /dev/stdin, /dev/fd/0, require( and a dynamic import with or without whitespace before the parenthesis (the pattern import, optional whitespace, open parenthesis), requires the exact import set, with bare specifiers such as net counted too (node:child_process, node:fs, node:path, node:url, and for node:fs exactly mkdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync), then runs a stub fetch in a fixture root and compares sorted file lists before and after: the only additions are .aai/cache/experts/typescript.md and .aai/cache/experts/.sha_typescript | `sed:s/const BOM = String\.fromCharCode\(0xfeff\);/import net from "net"; const BOM = String.fromCharCode(0xfeff);/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2613 | Spec-AC-08 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2613_launchers_thin checks both launchers: no byte above 0x7E, at most 10 and 20 lines, a reference to expert-fetch.mjs, none of the D2 logic tokens, and the D-18 literal exactly once | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE" "$@" # blocked_categories/` on .aai/scripts/expert-fetch.sh | green |
| TEST-2614 | Spec-AC-08 | integration | tests/skills/test-aai-expert-fetch.sh | test_2614_sh_launcher_without_node runs expert-fetch.sh --list with PATH set to a TEST_DIR bin holding only bash and dirname (positive control: command -v node fails under that PATH): stdout empty, stderr exactly the D-18 line, exit 1; then, with node on PATH, a launcher copy in a directory without expert-fetch.mjs gives the same | `sed:s/unavailable\)" >&2/unavailable)"/` on .aai/scripts/expert-fetch.sh | green |
| TEST-2615 | Spec-AC-08 | integration | tests/skills/test-aai-expert-fetch.sh | test_2615_ps1_launcher_mapping_and_exit runs expert-fetch.ps1 under pwsh -File: without node on PATH (same positive control) and from a copy without the module it prints exactly the D-18 line on stderr and exits 1; with the real module, -Detect ts py docker prints docker and python, -ExpertKey nosuch exits 2, positional nosuch exits 2, -Check znouse -Phase tdd-green and the GNU form --check znouse tdd-green both print not-found and exit 2, -List prints the registry's key count, and -Body over a cached prompt prints its body | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/expert-fetch.ps1 | green |
| TEST-2616 | Spec-AC-09 | integration | tests/skills/test-aai-expert-fetch.sh | test_2616_launcher_parity runs eleven fixtures through bash expert-fetch.sh and through pwsh -File expert-fetch.ps1 (PowerShell parameter spelling on the ps1 side) and compares stdout, stderr and exit code: list; detect .TSX py docker; detect zzzz; check typescript implementation; check znouse tdd-green; check typescript nosuchphase; fetch nosuch; fetch zblocked (stub log stays empty); fetch typescript with the stub; body typescript; fetch with a stub that exits 1; positive control: the znouse case exits 2 on both sides | `sed:s/@\('--detect'\) \+ \$Detect \+ \$Rest/@('--detect') + $Detect/` on .aai/scripts/expert-fetch.ps1 | green |
| TEST-2617 | Spec-AC-09 | integration | tests/skills/test-aai-expert-fetch.sh | test_2617_pester_expert_fetch runs Invoke-Pester on tests/skills/expert-fetch.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 11 | `sed:s/param\(\[string\]\$ExpertKey/param([string]$Key/` on .aai/scripts/expert-fetch.ps1 | green |
| TEST-2618 | Spec-AC-10 | e2e | tests/skills/test-aai-expert-fetch.sh | test_2618_downstream_extended_sync_runs_expert_fetch runs .aai/scripts/aai-sync.sh --profile extended into a git-initialised TEST_DIR/target with space, asserts the target holds .aai/scripts/expert-fetch.mjs, runs bash .aai/scripts/expert-fetch.sh there: --list prints the target registry's key count, --check typescript implementation prints eligible, and a fetch of typescript with AAI_GH_BIN naming the stub exits 0 and prints a path under the target's .aai/cache/experts; then a --profile core target holds none of expert-fetch.sh, expert-fetch.ps1 and expert-fetch.mjs | `sed:s/\/expert-fetch\.mjs"/\/expert-fetch-gone.mjs"/` on .aai/scripts/expert-fetch.sh | green |
| TEST-2619 | Spec-AC-11 | inspection | tests/skills/test-aai-layer-profiles.sh | test_2619_expert_fetch_module_classified asserts .aai/scripts/expert-fetch.mjs appears exactly once in PROFILES.yaml, inside the extended list | `sed:s/expert-fetch\.mjs/expert-fetch-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-2620 | Spec-AC-11 | integration | tests/skills/test-aai-expert-fetch.sh | test_2620_suite_map_selects_expert_fetch feeds each of the five suite paths to node .aai/scripts/select-suites.mjs --files-from - and requires a SELECTED aai-expert-fetch line and no FULL_RUN line | `sed:s/\.aai\/scripts\/expert-fetch\.mjs/.aai\/scripts\/expert-fetch-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-2621 | Spec-AC-11 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2621_ps1_quality_filter_has_module extracts the push and pull_request path lists of .github/workflows/ps1-quality.yml and requires both to contain .aai/scripts/expert-fetch.mjs and to be identical | `sed:s/expert-fetch\.mjs/expert-fetch-gone.mjs/` on .github/workflows/ps1-quality.yml | green |
| TEST-2622 | Spec-AC-12 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2622_line_budget_recorded parses expert-fetch pair 444 to N lines from the phase 3 row and requires N to equal the live wc -l sum of the three files and to be at most 230 | `sed:s/expert-fetch pair 444 to (\d+) lines/expert-fetch pair 444 to 1$1 lines/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2623 | Spec-AC-13 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2623_rfc_phase3_done finds the Rollout Status row whose first cell is 3, splits its cells and requires the description cell unchanged, the status cell exactly done, the SPEC-0248 first-slice string and the second-slice link and triage pair 140 to 129 lines text unchanged, and a link target ending in node-first-third-slice.md followed by expert-fetch; reads the RFC frontmatter (status implementing, umbrella true) and the status cells of rows 0 and 2 (in progress) and 4 and 5 (not started) | `sed:s/(retired counterparts \x7c )done/$1in progress/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2624 | Spec-AC-14 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2624_inventory_matches_tree computes the names with .aai/scripts/NAME.sh and NAME.ps1 and no NAME.mjs from the live tree, parses the table under the heading Remaining paired scripts after phase 3, and requires set equality (missing and extra names listed on failure), two positive integers per Lines cell, a destination from the three allowed values, a non-empty reason, the three supervision pairs as phase 5 process adapter and pre-commit-checks as platform adapter kept on purpose; positive control: a fixture tree with an added pair x.sh and x.ps1 makes the same comparison fail | ``sed:s/`validate-skills`/`validate-skill`/`` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-2625 | Spec-AC-15 | integration | tests/skills/test-aai-expert-fetch.sh | test_2625_amended_status_checks runs bash tests/skills/test-aai-live-status.sh test_2419_rfc_phase3_row and bash tests/skills/test-aai-triage.sh test_2518_rfc_phase3_row (each exit 0), then node .aai/scripts/spec-amend.mjs list --json and requires a signed contract record of ref node-first-sync-hook-slice whose what begins TEST-2419 and one of ref node-first-second-slice whose what begins TEST-2518 | `sed:s/"owner_signoff":true,"amendment_class":"contract","what":"TEST-2419/"owner_signoff":false,"amendment_class":"contract","what":"TEST-2419/` on docs/ai/decisions.jsonl | green |
| TEST-2626 | Spec-AC-16 | inspection | tests/skills/test-aai-expert-fetch.sh | test_2626_496_amendments_signed runs node .aai/scripts/spec-amend.mjs list --json and requires at least three records of ref node-first-second-slice, all signed; then node .aai/scripts/follow-ups.mjs list --status all --json and requires fu-amend-spec-node-first-second-slice with status done | `sed:s/"classifies_ref":"node-first-second-slice","owner_signoff":true/"classifies_ref":"node-first-second-slice","owner_signoff":false/` on docs/ai/decisions.jsonl | green |
| TEST-2627 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2627_blocked_list_spellings runs the TEST-2627 node cases: each of eight blocked-list spellings (trailing spaces or a comment on the heading, a comment line or a blank line first in the list, four-space indent, double-quoted items, single-quoted items with comments, the flow form) gives both categories, blockedBroken false, and a fetch of zblocked exits 1 with no runGh call; the real registry still gives exactly its two categories, blockedBroken false and 110 keys | `sed:s/\^\\s\+-\\s\+\(\.\*\)\$/^ {2}- (.*)$/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2628 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2628_blocked_list_fails_closed runs the TEST-2628 node cases: four headings with no readable item (bare, only a comment, an unindented dash, a bare word) set blockedBroken, and a fetch of typescript exits 1 with the no-readable-item line and no runGh call; the explicit empty flow list and a registry without the heading stay well-formed with no blocked category | `sed:s/blockedBroken: heads\.length > 0/blockedBroken: false/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2629 | Spec-AC-06 | unit | tests/skills/test-aai-expert-fetch.sh | test_2629_body_blocked_check runs the TEST-2629 node cases: --body of a cached zblocked prompt exits 1 with the blocked line and empty stdout, --body of a cached typescript prompt still prints its body, --body under a registry whose blocked heading has no item exits 1 with the no-readable-item line, with the key guard cases moved to TEST-2634 and TEST-2635 | `sed:s/blockedRefusal\(reg, key\) \?\? /null ?? /` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2630 | Spec-AC-04 | integration | tests/skills/test-aai-expert-fetch.sh | test_2630_launcher_blocked_list runs bash expert-fetch.sh in a fixture root with AAI_GH_BIN naming the stub: a commented heading, a comment line plus blank line plus four-space items, and quoted items each make zblocked exit 1 with exactly the blocked line, and a heading with only a comment makes typescript exit 1 with exactly the no-readable-item line; the stub log stays empty in all four; then a real file planted above the experts directory and cached files named Zblocked and type.script each make --body exit 1 with empty stdout, and --body ../x prints exactly the not-cached line | `sed:s/refusing to serve experts/refusing/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2631 | Spec-AC-05 | unit | tests/skills/test-aai-expert-fetch.sh | test_2631_cache_write_failure_cleans_up runs the TEST-2631 node case: a directory where the cache file belongs makes the rename fail, the fetch exits 1 with the Cannot-write line and the cache directory holds no .tmp_ file | `sed:s/rmSync\(tmp, \{ force: true \}\); //` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2632 | Spec-AC-05 | unit | tests/skills/test-aai-expert-fetch.sh | test_2632_cache_write_failure_shapes runs the TEST-2632 node case: a regular file where .aai/cache belongs, a regular file where .aai/cache/experts belongs, and a directory at the .tmp_ path each make the fetch exit 1 with empty stdout and exactly one Cannot-write line on stderr, with no stack trace | `sed:s/try \{ (rmSync\(tmp, \{ force: true \}\);) \} catch \{ \/\* best effort \*\/ \}/$1/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2633 | Spec-AC-04 | unit | tests/skills/test-aai-expert-fetch.sh | test_2633_blocked_list_residual_shapes runs the TEST-2633 node cases: a second heading adds its items to the first (an empty flow list then a real list blocks it), an item that is empty after comment and quote removal is dropped and a heading left with none sets blockedBroken, a stray indented line does not truncate the list so a later item still blocks zblocked with no runGh call, and the real registry still gives two categories | `sed:s/if \(item && unq\(item\[1\]\)\) //` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2634 | Spec-AC-06 | unit | tests/skills/test-aai-expert-fetch.sh | test_2634_body_key_guard_planted runs the TEST-2634 node case: a real file is planted at .aai/cache/x.md and cached files are planted for Typescript and type.script, so only the key guard can refuse them, then --body ../x, --body Typescript and --body type.script each exit 1 with empty stdout and exactly the not-cached line naming the argument, and the planted contents are never printed; test_2630 repeats the planted cases through the bash launcher | `sed:s/\/\^\[a-z\]\[a-z0-9_-\]\*\$\/\.test\(key\)/\/.*\/.test(key)/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2635 | Spec-AC-06 | unit | tests/skills/test-aai-expert-fetch.sh | test_2635_body_case_variant_blocked runs the TEST-2635 node case: cached files zblocked.md and Zblocked.md are planted, then --body Zblocked exits 1 with empty stdout and exactly the not-cached line naming Zblocked, and --body zblocked exits 1 with empty stdout and the blocked-category line; a guard loosened to accept upper-case letters serves the blocked body and goes red | `sed:s/\/\^\[a-z\]\[a-z0-9_-\]\*\$\/\.test\(key\)/\/^[a-zA-Z][a-zA-Z0-9_-]*$\/.test(key)/` on .aai/scripts/expert-fetch.mjs | green |
| TEST-2636 | Spec-AC-06 | unit | tests/skills/test-aai-expert-fetch.sh | test_2636_cache_path_not_a_file runs the TEST-2636 node case: a directory at the cache .md path with a valid SHA file makes fetch call runGh once instead of exiting 0 with the directory path, and --body exits 1 with empty stdout, exactly the not-cached line and no stack trace; it then repeats the --body case through the bash launcher | `sed:s/statSync\(p\)\.isFile\(\)/statSync(p)/` on .aai/scripts/expert-fetch.mjs | green |

Test-file note: every row's selector is one bash function that runs alone under
single-function dispatch, because `mutation-run.mjs` runs bash suites only
(`fu-mutation-gate-skips-pester` stays open; the Pester file is reached through
the TEST-2617 wrapper). Mutation patterns are JavaScript regular expressions
with `(`, `)`, `[`, `]`, `.`, `+`, `?`, `/` and `$` escaped as written; TEST-2623
writes the table pipe as `\x7c` because no Test Plan cell may hold a pipe; no
row uses a flag. `check-test-registration.mjs` must stay at exit 0. If a
mutation anchor proves ambiguous at RED time (first occurrence lands
elsewhere), the fix is an additive-with-disclosure amendment of that one cell,
recorded before its run.

### RED observations and positive controls

- TEST-2601 to TEST-2612: RED on the baseline because the module does not exist
  (import or file read fails); the wrappers' zero-passing-tests guard makes a
  missing test name RED rather than vacuously green.
- TEST-2613: RED on the baseline (logic tokens and length in both scripts,
  non-ASCII bytes in expert-fetch.sh).
- TEST-2614 and TEST-2615: RED on the baseline (both copies run without Node and
  print no D-18 line; the ps1 copy loses detect tokens and exits 1 for an
  unknown key); the positive control (`command -v node` fails under the test
  PATH) is asserted first.
- TEST-2616: RED on the baseline through D-1, D-5, D-6, D-7 and D-8.
  TEST-2617: RED on the baseline (D-18, detect and not-found cases).
- TEST-2618: RED on the baseline, because the target lacks the module.
- TEST-2619 to TEST-2624: RED on the baseline (entries, row text and subsection
  absent).
- TEST-2625: RED on the baseline (no TEST-2419 or TEST-2518 record), and RED
  again between the RFC flip and the two test edits, which is the observation
  that the old checks pin the status.
- TEST-2626: passes on the baseline (signed by `3c1f916a`); its RED is the
  mutation record.

## Verification

- Expert-fetch suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-expert-fetch.sh` exits 0.
- Layer profiles: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` exits 0.
- Suite selection: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` exits 0.
- Hygiene pack (suite-map row pin, pipefail reader scan with its count guard, cd-subshell baseline, test registration): `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` exits 0.
- Windows-fallback pins on the path filter: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` exits 0.
- Earlier slices, which read the phase 3 row and the ledger: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-live-status.sh` and `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-triage.sh` exit 0 (TEST-2419, TEST-2420, TEST-2518, TEST-2519 and TEST-2520 among them).
- Direct Node tests: `node --test tests/skills/lib/expert-fetch.test.mjs` exits 0, under local Node 22.
- PowerShell gate: `bash tests/skills/test-ps1-quality.sh` exits 0 locally (PSScriptAnalyzer and the full Pester discovery, SkippedCount 0).
- Line budget: `wc -l .aai/scripts/expert-fetch.sh .aai/scripts/expert-fetch.ps1 .aai/scripts/expert-fetch.mjs` total at most 230 and equal to the RFC row.
- Inventory counts, once at delivery: for every inventory row, `wc -l .aai/scripts/<name>.sh .aai/scripts/<name>.ps1` equals the row's Lines cell.
- Amendment ledger: `node .aai/scripts/spec-amend.mjs list --strict` exits 0 and shows the two new records as signed.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'` per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.
- Docs audit on the RFC and this spec: `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <file>` reports no finding that this scope introduced (the umbrella false-open note under Risks applies at close).

### Hosted delivery checks (after normal PR creation, before merge-readiness)

These are not Spec-ACs and are not claimed by local Validation. They are
planned, not optional: Windows parity (intake AC-002) is proven only here.

- H1 (native Windows parity): on the PR head, the ps1-quality run concludes
  success for `gate`, `windows-5_1` and `windows-wsl1`. In both
  `Full Pester suite discovery` steps of `windows-5_1` (Windows PowerShell 5.1
  and pwsh 7) and in the one of `windows-wsl1`, every case of
  `expert-fetch.Tests.ps1` is listed as passed, the skipped count still equals
  `AAI_EXPECTED_WIN_SKIP_COUNT` (4), and the Node version case logs a major of
  22 or higher. Evidence: run id, head SHA and the matched log lines from
  `gh run view <id> --log`. A hosted-only failure is diagnosed with a probe
  before any code change: a temporary diagnostic step or case that prints what
  the launcher and Node actually exchanged (the argument list Node received,
  stdout and stderr bytes in hex, `$LASTEXITCODE`, and for file cases the first
  bytes of the cache and SHA files), and the code change follows the probe's
  result, recorded as an amendment. SPEC-0247 spent two rounds on disproven
  hypotheses before such a probe found its stdin BOM.
- H2 (Linux and Node 22 floor): the PR head's skill-suite run concludes success,
  with `aai-expert-fetch` selected or a full run, and the step
  `Node 22 compatibility (downstream floor)` passing; its `node --test` output
  lists the TEST-2601 to TEST-2610 cases.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/node-first-third-slice/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. H1 and H2 are recorded separately after PR creation. Planning's
measurements above are inputs, not attestations of the implementation.

## Risks and rollback

- The Windows launcher binding (D-8 under 5.1) and the 5.1 BOM reading (D-11)
  are the behaviors no local host can prove; H1 decides them.
- An Implementation or TDD dispatch on a host without Node now gets an explicit
  error and exit 1 from the expert step instead of a bash-only fetch; the step
  is optional in every caller. The CHANGELOG entry names it.
- The sh copy started blocking `09-meta-orchestration` and
  `08-business-product` experts it used to fetch (D-1); a caller that relied on
  that gets exit 1. This is the registry's own stated policy.
- Changing two shipped scripts is consumer-visible: merge needs the owner's menu
  (intake constraint).
- Flipping phase 3 to done on an open umbrella RFC can trip the docs-audit
  false-open check at close; handle it with a fresh `doc_lifecycle` event, as
  earlier phase children did. The RFC itself stays `implementing`.
- TEST-2625 and TEST-2626 pin ledger facts; a later, legitimate
  re-classification of those records would redden them and must then amend or
  retire the rows.
- Rollback is one revert of the scope's files plus the two amendment records'
  disclosure; no template or hook command names expert-fetch, so installs need
  nothing.

## Registry disposition

Related open registry items, all left open:

- `fu-mutation-gate-skips-pester`: this scope reaches its Pester file through a
  bash wrapper (TEST-2617) instead of extending the gate.
- `fu-ps1-quality-outside-sweep-glob`: `test-ps1-quality.sh` is still outside
  the sweep glob; this scope runs it in Verification and through H1 only.
- `fu-ps1-writeerror-terminates-before-exit`: this scope removes one instance
  of the class (expert-fetch.ps1, D-7), but the item names
  install-pre-commit-hook.ps1, which this scope does not touch.

Registry items closed by this scope: none. (`fu-amend-spec-node-first-second-slice`
already projects as done after the intake commit; Spec-AC-16 pins it.)
