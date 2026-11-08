---
id: spec-release-on-node
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: b13b55e5c35088118e201b90fb2c601ca039899e36554ecbd5e944db2ef1deb4
ceremony_level: 2
links:
  requirement: release-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the release CHANGELOG rollup and unlogged-PR check of aai-release to one Node module

SPEC-FROZEN: true

## Links

- Requirement: [Move the release CHANGELOG rollup and unlogged-PR check of aai-release to one Node module](../issues/CHANGE-DRAFT-release-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 6, slice (a) of two (the owner merges).
- Pattern precedents: the reaper port [CHANGE-0241](../issues/CHANGE-0241-node-first-reap-tests.md)
  and ride 3 [SPEC-0276](SPEC-0276-spec-cloudflare-share-on-node.md)
  (one Node module, `run(opts, deps)` seam, one `node:test` case per drift,
  Pester under Windows PowerShell 5.1 and pwsh 7, a scratch `aai-sync`
  install, the suite helpers `run_node_tests` and `need_tool`).
- Shared transform reused unchanged: `.aai/scripts/lib/release-rollup.mjs`
  (already used by `release-finish.mjs` and `release-dry-run.mjs`).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, `node:test`,
  bash suites, Pester 5).
- Baseline: main `ed97f6a8`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (rides 1
  to 5). The module replaces behaviour on a shipped, consumer-visible core
  path whose confirm arm writes branches; every drift decision is a
  behaviour that must be seen failing first on the baseline. Inspection rows
  (wiring, RFC, preamble, budget) are RED on the baseline too. Every row
  carries a mutation record.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped core scripts, a new core
  module, PROFILES, a CI workflow path list, an umbrella RFC, CHANGELOG and
  several suites' pins; the main checkout is shared and holds unrelated
  uncommitted files (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/dashboard*,
  docs/ai/tests/test-runs.jsonl).
- User decision: worktree (autopilot default 2, rationale "autopilot
  default"; aai-release is not an L3 protected surface and the
  recommendation is not `required`)
- Base ref: main
- Worktree branch/path: refactor/release-on-node at /Users/ales/Projects/aai-worktrees/release-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/release-cut.mjs .aai/scripts/aai-release.sh
  .aai/scripts/aai-release.ps1 .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml CHANGELOG.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  tests/skills/test-aai-release-cut.sh tests/skills/lib/release-cut.test.mjs
  tests/skills/release-cut.Tests.ps1 tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/test-aai-hygiene-pack.sh
  tests/skills/test-aai-cloudflare-share.sh
  tests/skills/test-aai-pre-commit-checks.sh tests/skills/test-aai-release.sh
  tests/skills/test-aai-learned-routing.sh
  tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/issues/CHANGE-DRAFT-release-on-node.md
  docs/specs/SPEC-DRAFT-spec-release-on-node.md docs/INDEX.md
  (cd-subshell-leak-baseline.tsv only if the ratchet asks for a row).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2 and 5, BSD
`/usr/bin/grep`, Node 22.23.1, pwsh 7.6.3, git) on 2026-11-08 at `ed97f6a8`,
by running both scripts against scratch git fixtures. Windows PowerShell 5.1
was not available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`).

| Script | Total lines | Code lines | Git mode |
|---|---|---|---|
| aai-release.sh | 368 | 290 | 100755 |
| aai-release.ps1 | 417 | 351 | 100644 |
| lib/release-rollup.mjs | 44 | 44 | 100644 |

Before: 785 total lines, 641 code lines over the two scripts.

### What each step does today, and who owns it after this slice

| Step | Today | After slice (a) |
|---|---|---|
| arguments, repository check (10), CHANGELOG check (11), version | each script | each script (slice b) |
| remote `--confirm` hand-off to `release-finish.mjs` | each script | each script, unchanged |
| gh probe (`would block (publish path)`), target branch | each script | each script (slice b), passed to the module |
| rollup of the root CHANGELOG, refusals 12 and 13 | awk program / `Invoke-ChangelogRollup` | module (`lib/release-rollup.mjs`) |
| tag-exists check (15) | each script | module |
| unlogged-PR audit call and `--online` decision | each script, spawning `release-finish.mjs --audit` | module, spawning the same command |
| plan rendering, preconditions, missing-notes refusal (20) | each script | module |
| release-branch handling, temporary worktree, commit, `AAI_VERSION.md`, cut report | each script | each script (slice b) |
| rollup inside the temporary worktree | awk / PowerShell copy | module `roll` |

Found while reading: in the local cut (`--confirm --no-remote`) the gh probe
never runs, because the remote `--confirm` hands off to `release-finish.mjs`
before it, so both scripts' cut-path exit 16 branch is unreachable. The
module's `check` therefore has no gh input (not a behaviour change).

### Observed on the baseline (fixture outputs)

Rollup, each fixture cut with `--confirm --no-remote --version v9` by both
scripts and compared with `rollup(text, 'v9')` of `lib/release-rollup.mjs`:

| Fixture | .sh | .ps1 | shared rollup |
|---|---|---|---|
| scaffold, two entries, older section | exit 0, equal to the shared rollup | exit 0, equal | ok |
| entry heading with an empty title | exit 0, rolled | exit 0, rolled | malformed-notes |
| entry with an empty body | exit 0, rolled | exit 0, rolled | malformed-notes |
| entry, older section, entry | exit 0, entries left in place | exit 0, in place | ok, entries moved up |
| CRLF file with a scaffold | exit 12, stderr starts `MALFORMED` | exit 0, every line ending rewritten to LF | ok, CR kept |
| UTF-8 BOM | exit 0, BOM kept | exit 0, BOM dropped | ok, BOM kept |
| one line `## [unreleased] — x`, no newline | exit 0, rolled, newline added | exit 13 | malformed-notes |
| `## [unreleased] foo` | exit 12, stderr starts `MALFORMED` | exit 12, ASCII ` - ` | malformed-notes |
| no `## [` heading | exit 13, stderr starts `ABSENT` | exit 13 | empty-notes |
| no final newline | plan keeps it; the cut adds one | kept | kept |

Plan, a fixture with three merged PRs since tag `v0`, one of them noted:
the `.sh` prints the precondition lines in the order tag, gh, NAMED with
`- NAMED (not blocking): 2 PR(s) merged since the previous tag have no
matching section in these notes:` and an advice line; the `.ps1` prints
`- NAMED (not blocking): missing notes` first, then tag and gh, and adds
`- confirm will refuse until missing release notes are resolved` even when a
precondition already blocks. The local cut's missing-notes refusal is
multi-line in the `.sh` and joined with `; ` in the `.ps1`. Every `.ps1`
refusal and header line uses an ASCII ` - ` where the `.sh` uses an em dash.

### Callers and references (tracked files; docs history, CHANGELOG history and test results excluded)

- `.aai/SKILL_RELEASE.prompt.md` and the `aai-release` harness wrappers run
  the two scripts by name. Unchanged.
- `release-finish.mjs`: the scripts run its `--audit` mode (plan and local
  cut) and hand the remote `--confirm` to it. Unchanged; the module runs the
  same `--audit` command.
- `lib/release-rollup.mjs`, `release-dry-run.mjs`: unchanged (see the
  coordination note below).
- `.aai/system/PROFILES.yaml` lines 91 to 96: the scripts, `release-finish.mjs`,
  `release-notes-gate.mjs`, `release-dry-run.mjs` and `lib/release-rollup.mjs`
  are `core`; the module joins them there.
- Fixtures that copy the scripts into a scratch tree and must now also copy
  the module: `tests/skills/test-aai-release.sh` (the helper-closure case
  near line 2167) and `tests/skills/test-aai-learned-routing.sh` TEST-002
  (line 74).
- `tests/skills/aai-win-dispatch.Tests.ps1` (Describe `aai-release.ps1`) and
  `tests/skills/aai-release.Tests.ps1` dot-source the `.ps1` for
  `Invoke-NativeChecked` and `Select-CapturedValue` and pin the cut-path
  helper calls; both functions and those calls stay. Neither file is edited.
- `tests/skills/test-aai-release.sh` TEST-034 checks that every `exit N` of
  the `.sh` is documented in SKILL_RELEASE; it keeps passing (a subset).
- `CHANGELOG.md` preamble states that `aai-release` enforces only the
  `## [unreleased] — ` prefix and rolls the rest unexamined; the remote
  finish already refuses an empty title or body, and after this slice every
  path does.
- RFC-0017 inventory row `aai-release` stays a pair (no `aai-release.mjs` is
  created); its Notes cell gains the module name.

### Coordination (SPEC-0257 Spec-AC-05 session)

Read only, on 2026-11-08: `fix/release-corpus-hermetic`
(/private/tmp/aai-release-corpus-hermetic) and `chore/spec-0257-ac05`
(/Users/ales/Projects/aai-worktrees/spec-0257-ac05) have no commits ahead of
main. Their uncommitted work touches `tests/skills/aai-win-dispatch.Tests.ps1`,
`tests/skills/aai-update.Tests.ps1` and `docs/specs/SPEC-0257-*.md`, and its
Spec-AC-02 measures `release-dry-run.mjs --both` over the reader corpus.
This slice does not edit `release-dry-run.mjs`, `lib/release-rollup.mjs`,
`tests/skills/test-aai-release-first.sh`, `tests/skills/lib/release-first.test.mjs`,
`aai-win-dispatch.Tests.ps1` or `aai-update.Tests.ps1`. Overlap that remains:

- The three new test files name CHANGELOG, so `release-dry-run.mjs --list`
  will count them as readers after this merges (corpus 30 to 33 readers),
  and their run time adds to the CI `release-dry-run` budget. They must pass
  in the rolled arm and stay fast (D-SUITE).
- `test-aai-release.sh`, `test-aai-learned-routing.sh`,
  `test-aai-hygiene-pack.sh` and `test-aai-pre-commit-checks.sh` are corpus
  readers that this slice edits.
- Whichever branch merges second rebases; no file is edited by both.

## Decisions

### D-DRIFT. Every behaviour difference found

Each row is decided here and pinned by exactly one `node:test` case in
`tests/skills/lib/release-cut.test.mjs` whose name begins with the DR id.
"Shared" means `lib/release-rollup.mjs`, which the remote finish already
uses, so after this slice the plan, the local cut and the remote finish roll
the same bytes.

| DR | Behaviour | .sh at ed97f6a8 | .ps1 at ed97f6a8 | Decision |
|---|---|---|---|---|
| DR-01 | entry heading with an empty title | rolled, exit 0 | rolled, exit 0 | shared: exit 12 with the D-OUT malformed line |
| DR-02 | entry whose body is blank | rolled, exit 0 | rolled, exit 0 | shared: exit 12 with the malformed line |
| DR-03 | entries interleaved with an older section | rolled in place | rolled in place | shared: the rolled entries move, in order, under the fresh scaffold, followed by every other section in its original order; the plan lists them in that order |
| DR-04 | CRLF file | scaffold misread, exit 12 | exit 0, every line ending rewritten to LF | shared: exit 0, every byte outside the rolled headings kept, the fresh scaffold lines take the CR of the first heading |
| DR-05 | UTF-8 byte order mark | kept | dropped | shared: kept |
| DR-06 | file decoding | bytes as read by awk | Get-Content; under Windows PowerShell 5.1 the ANSI code page misreads the em dash of every entry heading, so a valid CHANGELOG refuses with exit 12 (source reading; proven on the hosted 5.1 job) | Node decodes UTF-8 with `fatal: true` on every engine; bytes that are not valid UTF-8 exit 12 with the D-OUT encoding line |
| DR-07 | one-line file holding only an entry heading | rolled, exit 0 | exit 13 (a single line is read as a string) | shared: exit 12 (an entry without a body, as DR-02) |
| DR-08 | file without a final newline, local cut | the plan keeps it, the cut adds one | kept | kept on the plan and the cut |
| DR-09 | stderr on a rollup refusal | a bare awk token (MALFORMED, ABSENT or EMPTY) before the REFUSED line | the REFUSED line only | the REFUSED line only |
| DR-10 | punctuation in refusal and header lines | em dash | ASCII ` - ` | em dash on both, UTF-8 (the notes preview and `release-finish.mjs` already print em dashes) |
| DR-11 | rollup refusal inside the temporary worktree | any failure exits 13 with `base branch has no rollable entries (rc=N)` | 12 or 13 with the specific line | 12 or 13 with the same D-OUT lines as the root check |
| DR-12 | plan unlogged block wording | count line and advice line | `missing notes` | the `.sh` wording (D-OUT) |
| DR-13 | precondition order | tag, gh, NAMED | NAMED, tag, gh | tag, gh, NAMED |
| DR-14 | `confirm will refuse` line when a precondition also blocks | omitted | printed | printed whenever the NAMED list is not empty, `.sh` wording |
| DR-15 | audit failure during the plan | part of the plan printed, then the audit's exit code | nothing printed, the audit's exit code | the audit runs before any plan line; on failure no stdout, its stderr relayed, its exit code |
| DR-16 | audit order in the local cut | tag refusal first | audit first (an audit failure hides exit 15) | rollup (12, 13), then tag (15), then the audit |
| DR-17 | missing-notes refusal | items on separate lines | joined with `; ` | joined with `; ` on one line, as the remote finish already does |
| DR-18 | rolled-heading listing in the plan | substring match anywhere in a line | anchored at the line start | anchored at the line start, printed without a CR |
| DR-19 | files written by a plan | `.aai-release-changelog.*` in the repository root and a notes file in TMPDIR | the same | no file in the repository; the audit notes file lives in the OS temp directory and is removed on every exit path |
| DR-20 | origin probe for `--online` | `git remote get-url origin` | `git config --get remote.origin.url` (written for the 5.1 stderr hazard) | `git config --get remote.origin.url` run by Node with stderr captured; `--online` only when gh is not blocked, the remote is not skipped and the value is not empty |
| DR-21 | Node missing on the plan or local cut | exit 127 after the plan header | CommandNotFoundException, exit 1 | each script prints the D-LAUNCH missing-node line on stderr, exit 20, nothing on stdout, no file written |
| DR-22 | `.ps1` plan output stream | n/a | Write-Host (information stream) | the module's stdout, relayed by the `.ps1` on its success stream (a caller that assigns the script's output now captures the plan) |

Removed without a behaviour change (no test row): the unused dirty-tree
probe in both scripts, the `.sh` copy of the worktree notes into a file
nothing reads, the notes file's final newline (read only by the audit), and
the unreachable cut-path exit 16 branch of both scripts.

Found and left for slice (b), outside this slice's steps (named in
`fu-release-slice-b-delete-twins`): unknown-argument handling (the `.sh`
prints the usage, the `.ps1` one line), `-h` and `--help` (the `.sh` only),
the cut report's Remote line (the `.sh` names the SHA), and both scripts
reusing exit 12 for an existing release branch with unmerged commits.

Kept identical: every exit code, flag, environment variable and Resume
command of both scripts; `--dry-run` wins over `--confirm`; the remote
`--confirm` hands off to `release-finish.mjs` before any module call.

### D-MOD. The module

`.aai/scripts/release-cut.mjs`, Node stdlib only, imports `rollup` from
`./lib/release-rollup.mjs`, no side effect on import (the CLI runs only when
the file is the entry point, the `release-finish.mjs` guard). It holds the
literal constants
`const AUDIT_SCRIPT = 'release-finish.mjs';`,
`const PLAN_HEADER = '## aai-release (plan) — no files changed';`,
`const EXIT = { MALFORMED: 12, EMPTY: 13, TAG: 15, REFUSED: 20 };`
and the origin probe argument list `['config', '--get', 'remote.origin.url']`,
and exports:

- `parseArgs(argv)`: `{ cmd, root, version, targetBranch, launcher,
  launcherPath, noRemote, ghBlock, file }` or `{ error }` (exit 1 with a
  usage line on stderr).
- `decode(bytes)`: the UTF-8 text, or a thrown error whose `causeName` is
  `encoding` (DR-06).
- `rollOrRefuse(text, version)`: `{ content, notes }` from `rollup`, or
  `{ code, line }` with code 12 for `malformed-notes` and `encoding`, 13 for
  `empty-notes`.
- `rolledHeadings(content, version)`: `[{ n, line }]` for every line that
  starts with `## [<version>] — `, CR removed (DR-18).
- `onlineAllowed({ ghBlock, noRemote, origin })`: DR-20.
- `planLines(input)`: the D-OUT plan as an array of lines.
- `resumeLine(launcher, launcherPath, version)`: the Resume line of D-OUT.
- `run(argv, deps)`: the whole command, returning the exit code. `deps`
  holds `readFile`, `writeFile`, `rename`, `rm`, `tmpdir`, `git(args, cwd)`
  and `audit(args)`, each returning `{ status, stdout, stderr }` for the two
  process seams, plus `out(line)` and `err(line)`. The CLI wires `git` and
  `audit` to `spawnSync` (`audit` runs `process.execPath` on
  `AUDIT_SCRIPT` next to the module with
  `--root <root> --audit <notes file> [--online]`). Tests pass fakes for the
  unit cases and the real wiring for the integration cases.

Commands (all paths absolute, passed by the scripts):

- `plan --root R --version V --target-branch B --launcher sh|ps1 [--no-remote] [--gh-block <reason>]`:
  read and roll `R/CHANGELOG.md` (12, 13), check the tag, write the notes to
  a temp file, run the audit (DR-15), remove the temp file, print D-OUT,
  exit 0.
- `check --root R --version V --launcher sh|ps1 --launcher-path P`: roll the
  root (12, 13), tag (15), audit offline (the local cut always runs with the
  remote skipped), missing-notes refusal (20) with the Resume line; exit 0
  when the cut may proceed. Prints nothing on success.
- `roll --file F --version V`: decode and roll F, write the content to a
  temp file in F's directory and rename it over F (12, 13 with the D-OUT
  lines and F unchanged on refusal).

### D-OUT. The output contract

Plan (stdout; `<C>` is `--confirm` for `sh` and `-Confirm` for `ps1`; `<NR>`
is `--no-remote` and `-NoRemote`; lines in brackets are conditional):

```
## aai-release (plan) — no files changed
- Resolved version: <V>
- Tag to create:    <V> (annotated)
- Commit message:   chore(release): <V>

## CHANGELOG rollup (would write)
  <n>:## [<V>] — <title>                     (one line per rolled heading)
  ## [unreleased]   <- fresh scaffold inserted above the rolled section

## Release notes preview (title=<V>)
  <each notes line, indented by two spaces>

## Preconditions
[- would block: tag <V> already exists]
[- would block (publish path): <gh reason>]
[- NAMED (not blocking): <N> PR(s) merged since the previous tag have no matching section in these notes:
    - <audit line>                            (one per audit line)
    Add a '## [unreleased] — <title>' section for each, or confirm they are covered under another title.]
[- confirm will refuse until the NAMED missing release notes are resolved]   (NAMED not empty)
[- none — ready to cut with <C>]              (no line above)

## Remote
- <NR> / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED
  (or, without the skip)
- push (branch chore/release-<V>) and 'gh pr create' (base <B>) WOULD run against this repo's remote; CI will tag and publish upon merge
```

Refusals (stderr, one line each, exit code in brackets):

- `REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) — never silently dropping entries.` (12)
- `REFUSED: CHANGELOG.md is not valid UTF-8 — never guessing its encoding.` (12)
- `REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) — nothing to release.` (13)
- `REFUSED: tag <V> already exists.` (15)
- `REFUSED: missing-notes — <audit lines joined with '; '>` then
  `Resume: bash "<P>" --version <V> --confirm --no-remote` (sh) or
  `Resume: pwsh -NoProfile -File "<P>" -Version <V> -Confirm -NoRemote` (ps1) (20)

### D-LAUNCH. The two scripts after this slice

Both keep their names, modes (100755 and 100644), flags, environment
variables, usage comments and exit codes. They hold no rollup of their own
and no plan rendering. The argument handling, including the block in which
`--dry-run` resets `CONFIRM`/`$Confirm`, and the remote `--confirm` hand-off
stay as they are at `ed97f6a8` (TEST-3469's mutation targets that block).

- Before the first module call (after the CHANGELOG check and the remote
  `--confirm` hand-off, which keeps its own missing-node line), each prints
  `REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.`
  on stderr and exits 20 when `node` is not found (DR-21).
- `aai-release.sh` runs `node "$(dirname "$0")/release-cut.mjs" ...`: the
  plan with `exec`, `check` before the release-branch step, `roll` on the
  temporary worktree's CHANGELOG.md (its non-zero code is the script's exit
  code, after the worktree is removed).
- `aai-release.ps1` runs the same commands with
  `& node (Join-Path $PSScriptRoot 'release-cut.mjs') ... '--launcher', 'ps1'`
  and `exit $LASTEXITCODE` on non-zero. `Invoke-NativeChecked`,
  `Select-CapturedValue` and the dot-source guard stay as they are, and the
  cut-path git calls keep going through `Invoke-NativeChecked`.
- Budget (the plan's method): `aai-release.sh` at most 160 code lines,
  `aai-release.ps1` at most 220 (upper bounds, not exact pins).

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-release-cut` with globs
  `.aai/scripts/release-cut.mjs`, `.aai/scripts/aai-release.sh`,
  `.aai/scripts/aai-release.ps1`, `.aai/scripts/lib/release-rollup.mjs`,
  `.aai/scripts/release-finish.mjs`, `.aai/scripts/release-notes-gate.mjs`,
  `.aai/SKILL_RELEASE.prompt.md`, `.aai/system/PROFILES.yaml`,
  `.github/workflows/ps1-quality.yml`,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-release-cut.sh`,
  `tests/skills/lib/release-cut.test.mjs`, `tests/skills/release-cut.Tests.ps1`,
  `tests/skills/lib/nested-suite-lint.mjs`,
  `tests/skills/lib/nested-suite-allowlist.tsv`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-weights.tsv`, and every `tests/skills/lib/*` file the
  suite or the Pester file sources or reads. Not `CHANGELOG.md` (the
  preamble arm lives in `aai-release`, which already maps it, so this suite
  is not selected by every PR). The `aai-release` row gains
  `.aai/scripts/release-cut.mjs`.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-release-cut fallback unsampled (new suite of release-on-node; no successful observation)`
  and `aai-release-cut<TAB>196` (the documented maximum).
- Suite-map row-count pins (closes `fu-suite-map-row-count-pin-sprawl`):
  130 rows today, 131 after. `test-aai-hygiene-pack.sh` `test_090_suite_map_pin`
  stays the one literal pin and moves to 131. `test_129_mutation_gate_suite_registration`
  compares the live count with the number in test_090's `-eq` line read from
  the same file, not with a literal of its own.
  `test-aai-cloudflare-share.sh` TEST-3428 and `test-aai-pre-commit-checks.sh`
  TEST-3458 drop their literal row-count lines (both already run the
  hygiene-pack selectors); TEST-3458's "both hygiene pins read 130" line
  becomes "exactly one `-eq <n> ]]` row-count line in the hygiene pack".
  After this slice a new suite moves one number in one file.
- Nested-suite lint: no new allowlist row; cross-suite calls in the new
  suite are selector form (`test-aai-hygiene-pack.sh test_090_suite_map_pin`,
  `test_129_mutation_gate_suite_registration`,
  `test-aai-layer-profiles.sh test_manifest_conformance`,
  `test-aai-win-fallback.sh test_034`,
  `test-aai-expert-fetch.sh test_2624_inventory_matches_tree`,
  `test-aai-release.sh test_570_changelog_shape_is_documented`).
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: a row only if
  `check-cd-subshell-leak.mjs` asks, recorded with `--record`.
- `check-test-registration.mjs`: every `test_*` function is called.
- `.github/workflows/ps1-quality.yml`: `- '.aai/scripts/release-cut.mjs'` in
  both the push and the pull_request path lists, after `cloudflare-share.mjs`.
- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/release-cut.mjs` under
  `core:`, after `.aai/scripts/lib/release-rollup.mjs`.
- Fixtures that copy the scripts copy the module too:
  `test-aai-release.sh` (the helper-closure case) and
  `test-aai-learned-routing.sh` TEST-002; `check-vendored-script-deps.mjs`
  exits 0.
- Prompt corpus: no `.aai/*.prompt.md` and no `.aai/AGENTS.md` change, so no
  prompt-diet ledger entry, no TEST-012 move, and no companion pin move in
  `test-aai-pr-preflight.sh`, `test-aai-legacy-migrations.sh` or
  `test-aai-retired-loop-runner.sh`. A Validation diff that shows a prompt
  change is a scope breach.
- Release-notes gate: the CHANGELOG entry below is the shipped-surface note
  for `.aai/scripts/**`.

### D-RFC. RFC-0017 and CHANGELOG

- RFC-0017 inventory row `aai-release`: the Notes cell gains
  `; its rollup and unlogged-PR check run in release-cut.mjs since the [release slice](../issues/CHANGE-DRAFT-release-on-node.md)`
  at its end. Every other row stays byte for byte.
- Phase 5 row: one sentence after the ninth-slice sentence and before the
  remaining-scripts-plan sentence:
  `The tenth slice [moved the release rollup to Node](../issues/CHANGE-DRAFT-release-on-node.md): the plan, the local cut and the remote finish roll CHANGELOG.md through one transform, and the unlogged-PR check renders once; a later slice moves the tag, publish and PR steps to the platform adapter and deletes the twins.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  both links at merge; checks match only the suffix `release-on-node.md`.
- CHANGELOG preamble (closes `fu-changelog-exit12-second-arm`): the sentence
  that says the parser enforces only the prefix becomes a statement of what
  the plan, `--dry-run` and the local cut refuse with exit 12 (the remote
  finish refuses the same headings and empty entries with exit 20 and does
  not check the encoding): a bare `## [unreleased]` scaffold
  with body text, a `## [unreleased]` heading with other trailing text than
  the `— ` form, an entry whose title or body is empty, and a file that is
  not valid UTF-8. The literal `## [unreleased] — <type>: <title>` stays
  stated exactly once (TEST-570).
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST
  row): CHANGELOG `## [unreleased] — refactor(release): the CHANGELOG rollup and unlogged-PR check of aai-release run in one Node module`
  naming every DR decision a user can see (DR-01 to DR-08, DR-10, DR-11,
  DR-12 to DR-17, DR-21, DR-22) and the before and after code lines.

### D-SUITE

One new suite `aai-release-cut` (`tests/skills/test-aai-release-cut.sh`)
holds every row, using `run_node_tests` (a pattern that matches no passing
case fails) and `need_tool` (an absent tool fails on CI, a named SKIP-CASE
locally). Every fixture is a fresh temp git repository with a local
identity; no case reads or writes the repository's own `CHANGELOG.md`,
except the preamble arm, which runs through the `test-aai-release.sh`
selector. Every case that runs a script puts a stub `gh` first on PATH that
logs its argv, answers `auth status` with exit 0 and exits 1 on any other
call; origins are local bare repositories. No case pushes to a network
remote, opens a PR, tags or publishes. The Pester file launches the `.ps1`
with the engine running the test (`(Get-Process -Id $PID).Path`), so the
hosted 5.1 step tests 5.1, and writes fixtures with
`[System.IO.File]::WriteAllBytes` so the bytes do not depend on the engine.
The suite and the `node:test` file each finish in under 60 seconds locally
(they join the release-dry-run reader corpus).

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02, Spec-AC-09 and Spec-AC-10.
- Intake AC-002 maps to Spec-AC-03, Spec-AC-04, Spec-AC-05 and Spec-AC-06.
- Intake AC-003 maps to Spec-AC-07.
- Intake AC-004 maps to Spec-AC-08.
- Intake AC-005 maps to Spec-AC-10, Spec-AC-11 and hosted check H1.
- Intake AC-006 maps to Spec-AC-12, Spec-AC-13, Spec-AC-14 and Spec-AC-15.

## Constitution deviations

None. Article 4 (degrade and report): every refusal names its cause on
stderr with its documented exit code; a missing Node is named instead of a
crash. Article 5 (additive first): both command names, flags, environment
variables, exit codes and Resume commands stay; the changed behaviours are
listed in D-DRIFT and in the CHANGELOG. Article 2 (simplicity): no new flag
or dependency; the module reuses the shared rollup and the existing audit
command instead of a third copy.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Importing .aai/scripts/release-cut.mjs writes nothing and exports the D-MOD functions; run plan with fake git and audit on a fixture text calls audit exactly once with release-finish.mjs, --root, the root, --audit and a temp notes file outside the root, adds --online only per DR-20, and the temp file no longer exists after run returns. | done | docs/ai/tdd/release-on-node/green/run1-test_3462_seam.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3462.txt | — | — |
| Spec-AC-02 | WHEN the module CLI runs plan in a committed temp git repository with the real release-finish.mjs audit, the system SHALL exit 0, print exactly the D-OUT plan lines for launcher sh and, with only the flag spellings changed, for launcher ps1, print nothing on stderr, and leave the working tree bytes, the index, every ref and the file list unchanged. | done | docs/ai/tdd/release-on-node/green/run1-test_3463_plan_contract.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3463.txt | — | — |
| Spec-AC-03 | The node:test cases DR-01 to DR-09 pass and each asserts the D-DRIFT decision of its row: exit code, the exact stderr line, and for a cut the exact bytes written. | done | docs/ai/tdd/release-on-node/green/run2-test_3464_rollup_drift.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3464.txt | — | — |
| Spec-AC-04 | The node:test cases DR-10 and DR-12 to DR-18 pass and each asserts the D-DRIFT decision of its row: the exact plan lines or refusal line, their order, the exit code and the order of the checks. | done | docs/ai/tdd/release-on-node/green/run2-test_3465_plan_drift.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3465.txt | — | — |
| Spec-AC-05 | The node:test cases DR-11 and DR-19 to DR-22 pass: the worktree roll refuses with 12 or 13 and leaves the file unchanged, a plan leaves no new file anywhere under the root, the origin probe uses config --get with stderr captured, a script run with no node on PATH prints the D-LAUNCH line with exit 20 and empty stdout, and a ps1 plan reaches the success stream. | done | docs/ai/tdd/release-on-node/green/final-test_3466_files_and_launch.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3466.txt | — | — |
| Spec-AC-06 | Every DR id in the D-DRIFT table begins exactly one node:test case name in tests/skills/lib/release-cut.test.mjs, and the test file names no DR id the table lacks. | done | docs/ai/tdd/release-on-node/green/final-test_3467_drift_coverage.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3467.txt | — | — |
| Spec-AC-07 | WHEN aai-release.sh and aai-release.ps1 each run --confirm --no-remote on the same committed fixture (CRLF, a BOM, interleaved entries, no final newline), the CHANGELOG.md of each chore/release branch SHALL equal byte for byte the rollup of lib/release-rollup.mjs over the base blob, and each plan SHALL list exactly that content's rolled headings with their line numbers. | done | docs/ai/tdd/release-on-node/green/run4-test_3468_one_transform.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3468.txt | — | — |
| Spec-AC-08 | WHEN either script runs bare, with --dry-run, and with --dry-run --confirm in a fixture with a bare local origin and the D-SUITE gh stub, the system SHALL exit 0 and leave the working tree bytes, index, local refs, origin refs and file list unchanged with no gh call other than auth status; a --confirm --no-remote cut SHALL leave the origin refs unchanged and call no gh; a remote --confirm SHALL end in the release-finish.mjs refusal with its Resume line and no ref change. | done | docs/ai/tdd/release-on-node/green/run4-test_3469_no_publish.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3469.txt | — | — |
| Spec-AC-09 | aai-release.sh has at most 160 code lines by the plan's method, holds no awk program and no plan rendering, and calls release-cut.mjs for plan, check and roll; run by bash in the Spec-AC-02 fixture it prints the D-OUT sh plan with exit 0, and with no node on PATH it prints the D-LAUNCH missing-node line on stderr only with exit 20 (DR-21). | done | docs/ai/tdd/release-on-node/green/run3-test_3470_sh_script.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3470.txt | — | — |
| Spec-AC-10 | aai-release.ps1 has at most 220 code lines, holds no Invoke-ChangelogRollup and no Write-Host plan line, keeps Invoke-NativeChecked and Select-CapturedValue above the dot-source guard; under pwsh it prints the D-OUT ps1 plan with exit 0; tests/skills/release-cut.Tests.ps1 passes under Pester 5 with at least 5 cases and none failed or skipped; the aai-release.ps1 Describe of aai-win-dispatch.Tests.ps1 and aai-release.Tests.ps1 pass unchanged. | done | docs/ai/tdd/release-on-node/green/final-test_3471_ps1_script.log; docs/ai/tdd/release-on-node/green/run4-test_3472_pester.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3471.txt; docs/ai/tdd/spec-release-on-node/mutation-TEST-3472.txt | — | — |
| Spec-AC-11 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space, the target SHALL hold release-cut.mjs, both scripts, lib/release-rollup.mjs, release-finish.mjs and release-notes-gate.mjs, and the target's own scripts (sh under bash; ps1 under pwsh when present) SHALL print the plan with the rolled heading line and exit 0. | done | docs/ai/tdd/release-on-node/green/run4-test_3473_downstream_install.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3473.txt | — | — |
| Spec-AC-12 | The existing callers keep working: test-aai-release.sh, test-aai-learned-routing.sh and test-aai-release-notes.sh exit 0; every tests file that copies aai-release.sh into a scratch tree also copies release-cut.mjs; check-vendored-script-deps.mjs exits 0. | done | docs/ai/tdd/release-on-node/green/run4-test_3474_callers.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3474.txt | — | — |
| Spec-AC-13 | Wiring per D-WIRE: select-suites selects aai-release-cut for the module, both scripts and the three test files, and aai-release for the module; suite-weights holds the row; hygiene-pack test_090 pins 131 and is the only literal row-count pin left in test_129, TEST-3428 and TEST-3458, and all four selectors pass; nested-suite lint, check-cd-subshell-leak and check-test-registration exit 0; PROFILES lists the module once under core and layer-profiles test_manifest_conformance passes; both ps1-quality path lists name the module and win-fallback test_034 passes. | done | docs/ai/tdd/release-on-node/green/final-test_3475_wiring.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3475.txt | — | — |
| Spec-AC-14 | test-aai-expert-fetch.sh test_2624_inventory_matches_tree exits 0, the aai-release inventory row names release-cut.mjs, the phase 5 row keeps status in progress and holds the D-RFC sentence once with a link ending release-on-node.md; the CHANGELOG preamble names the four exit-12 arms of D-RFC and test-aai-release.sh test_570_changelog_shape_is_documented exits 0. | done | docs/ai/tdd/release-on-node/green/run5-test_3476_rfc_and_preamble.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3476.txt | — | — |
| Spec-AC-15 | Measured with the plan's method on the delivered tree, the suite prints before 641, the after sum of both scripts, the removed code lines and the module's code lines, and fails when either script exceeds its D-LAUNCH budget; every value of the module's EXIT constant and the exit 1 usage code is documented as exit N = in .aai/SKILL_RELEASE.prompt.md. | done | docs/ai/tdd/release-on-node/green/run5-test_3477_line_budget.log; docs/ai/tdd/spec-release-on-node/mutation-TEST-3477.txt | — | — |
| Spec-AC-16 | A plan piped into head -1 prints nothing on stderr and exits 141 (SIGPIPE), not a Node EPIPE stack trace. | done | docs/ai/tdd/spec-release-on-node/mutation-TEST-3478.txt | — | — |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/release-on-node/red/` before its change, GREEN under `green/`,
and one mutation record per row (`node .aai/scripts/mutation-run.mjs`)
before the run's hand-off.

1. Run 1, Spec-AC-01, 02, 06: the suite skeleton, the `node:test` file with
   the seam and plan cases and all 22 DR case names, then the module
   (D-MOD, D-OUT).
2. Run 2, Spec-AC-03, 04, 05: the DR cases, module behaviour per D-DRIFT.
3. Run 3, Spec-AC-07, 08, 09: the `.sh` delegates (D-LAUNCH), the
   one-transform seam and the safety case.
4. Run 4, Spec-AC-10, 11, 12: the `.ps1` delegates, the Pester file, the
   scratch install, the two fixtures that copy the scripts.
5. Run 5, Spec-AC-13, 14, 15: D-WIRE, D-RFC (RFC-0017 and the preamble),
   the measurement; then the CHANGELOG entry after LOOP COMPLETE.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3462 | Spec-AC-01 | unit | tests/skills/test-aai-release-cut.sh | test_3462_seam runs run_node_tests TEST-3462 on tests/skills/lib/release-cut.test.mjs: an import in a child node with a temp cwd writes nothing to stdout, stderr or the cwd and exposes parseArgs, decode, rollOrRefuse, rolledHeadings, onlineAllowed, planLines, resumeLine and run; run plan with recording fakes calls audit once with the AUDIT_SCRIPT path, --root, --audit and a temp file under the fake tmpdir, adds --online only with an origin, gh not blocked and the remote not skipped, and the temp file is removed | `sed:s/const AUDIT_SCRIPT = 'release-finish.mjs'/const AUDIT_SCRIPT = 'release-finish-gone.mjs'/` on .aai/scripts/release-cut.mjs | green |
| TEST-3463 | Spec-AC-02 | integration | tests/skills/test-aai-release-cut.sh | test_3463_plan_contract runs run_node_tests TEST-3463: the module CLI plan in a committed temp repo with one noted and two unnoted merged PRs since a tag, the real audit, launcher sh and launcher ps1: stdout equals the D-OUT lines, stderr empty, exit 0; git status, the index digest, show-ref and a recursive file list are unchanged | `sed:s/## aai-release \(plan\) — no files changed/## aai-release \(plan\)/` on .aai/scripts/release-cut.mjs | green |
| TEST-3464 | Spec-AC-03 | unit | tests/skills/test-aai-release-cut.sh | test_3464_rollup_drift runs run_node_tests TEST-3464: cases DR-01 to DR-09 with the fixtures of the baseline table (empty title, blank body, interleaved, CRLF, BOM, invalid UTF-8, one line, no final newline, refusal stderr), each asserting exit code, the exact stderr line and the rolled bytes | `sed:s/fatal: true/fatal: false/` on .aai/scripts/release-cut.mjs | green |
| TEST-3465 | Spec-AC-04 | unit | tests/skills/test-aai-release-cut.sh | test_3465_plan_drift runs run_node_tests TEST-3465: cases DR-10 and DR-12 to DR-18 (em dash lines, the NAMED wording, tag-gh-NAMED order, the confirm-will-refuse line under a block, an audit fake that fails before any stdout, check order 12-13-15-audit with a fake audit that records whether it ran, the one-line missing-notes refusal and Resume per launcher, a heading text quoted inside an older section not listed) | `sed:s/confirm will refuse until the NAMED missing release notes are resolved/confirm will refuse/` on .aai/scripts/release-cut.mjs | green |
| TEST-3466 | Spec-AC-05 | integration | tests/skills/test-aai-release-cut.sh | test_3466_files_and_launch runs run_node_tests TEST-3466: DR-11 (roll on a malformed and an empty file: 12 and 13, file bytes unchanged), DR-19 (a plan leaves the recursive file list of the root unchanged and the fake tmpdir empty), DR-20 (the git fake sees config --get remote.origin.url and a failing probe with stderr gives no --online), DR-21 (each script spawned with PATH holding only git and its helpers: the D-LAUNCH line on stderr, empty stdout, exit 20, no file written; the ps1 arm under pwsh when present), DR-22 (pwsh -File plan output arrives on the child's stdout) | `sed:s/'config', '--get', 'remote.origin.url'/'remote', 'get-url', 'origin'/` on .aai/scripts/release-cut.mjs | green |
| TEST-3467 | Spec-AC-06 | inspection | tests/skills/test-aai-release-cut.sh | test_3467_drift_coverage reads the DR ids of the D-DRIFT table of this spec (found by its id spec-release-on-node under docs/specs) and the test names of tests/skills/lib/release-cut.test.mjs; each table id begins exactly one test name and no test name begins with an id the table lacks; positive control: a scratch copy with DR-13 renamed is reported | `sed:s/'TEST-3465 DR-13 /'TEST-3465 DR-31 /` on tests/skills/lib/release-cut.test.mjs | green |
| TEST-3468 | Spec-AC-07 | integration | tests/skills/test-aai-release-cut.sh | test_3468_one_transform builds a committed fixture with CRLF, a BOM, interleaved entries and no final newline, runs aai-release.sh --confirm --no-remote --version v9 and, in a copy, aai-release.ps1 -Confirm -NoRemote -Version v9 (need_tool pwsh), and compares each git show chore/release-v9:CHANGELOG.md byte for byte with a node rollup of the base blob through lib/release-rollup.mjs; the plan of each script lists exactly the rolled headings of that content with their line numbers | `patch:docs/ai/tdd/spec-release-on-node/mutation-TEST-3468.patch` on .aai/scripts/release-cut.mjs | green |
| TEST-3469 | Spec-AC-08 | integration | tests/skills/test-aai-release-cut.sh | test_3469_no_publish puts the D-SUITE gh stub first on PATH and a bare local origin behind the fixture; for each script runs bare, --dry-run and --dry-run --confirm (exit 0, working tree, index, local and origin refs and file list unchanged, gh log at most auth status), --confirm --no-remote (origin refs unchanged, no gh call) and remote --confirm (the release-finish.mjs REFUSED and Resume lines, refs unchanged) | `sed:s/  CONFIRM=0/  CONFIRM=1/` on .aai/scripts/aai-release.sh | green |
| TEST-3470 | Spec-AC-09 | integration | tests/skills/test-aai-release-cut.sh | test_3470_sh_script counts aai-release.sh code lines (at most 160), requires no awk program, no perform_rollup and no plan header text in it and three release-cut.mjs calls (plan, check, roll); runs it by bash in the Spec-AC-02 fixture (D-OUT sh plan, exit 0); runs it with PATH holding only a scratch bin with git, dirname and the gh stub (no node): stderr equals the D-LAUNCH missing-node line, stdout empty, exit 20 | `sed:s/REFUSED: missing-node — Node.js 22 or later is required for \/aai-release/REFUSED: missing-node — Node.js is required for \/aai-release/` on .aai/scripts/aai-release.sh | green |
| TEST-3471 | Spec-AC-10 | integration | tests/skills/test-aai-release-cut.sh | test_3471_ps1_script (need_tool pwsh) counts aai-release.ps1 code lines (at most 220), requires no Invoke-ChangelogRollup and no Write-Host line of the plan, and both helper functions defined before the dot-source guard line; runs pwsh -NoProfile -NonInteractive -File on it in the Spec-AC-02 fixture: the D-OUT ps1 plan, exit 0 | `sed:s/'--launcher', 'ps1'/'--launcher', 'sh'/` on .aai/scripts/aai-release.ps1 | green |
| TEST-3472 | Spec-AC-10 | integration | tests/skills/test-aai-release-cut.sh | test_3472_pester (need_tool pwsh; SKIP-CASE without Pester 5 locally) runs Invoke-Pester on tests/skills/release-cut.Tests.ps1, then on the aai-release.ps1 Describe of tests/skills/aai-win-dispatch.Tests.ps1 and on tests/skills/aai-release.Tests.ps1, each with PassThru, failing on FailedCount above 0, and for release-cut.Tests.ps1 on SkippedCount above 0 or TotalCount below 5; the release-cut cases cover a -DryRun plan of a UTF-8 em dash CHANGELOG written as bytes, a malformed file (exit 12), a -Confirm -NoRemote cut whose branch CHANGELOG equals the expected bytes, a missing-notes refusal on one line, and a PATH without node (exit 20) | `sed:s/Node.js 22 or later is required/Node.js is required/` on .aai/scripts/aai-release.ps1 | green |
| TEST-3473 | Spec-AC-11 | e2e | tests/skills/test-aai-release-cut.sh | test_3473_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, requires the six files there, commits a fixture CHANGELOG in the target, runs the target's own aai-release.sh under bash and, when pwsh is present, its aai-release.ps1 under pwsh, each with the gh stub first on PATH and --no-remote: exit 0 and the rolled heading line | `sed:s/  - \.aai\/scripts\/release-cut\.mjs/  - .aai\/scripts\/release-cut-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3474 | Spec-AC-12 | integration | tests/skills/test-aai-release-cut.sh | test_3474_callers runs test-aai-learned-routing.sh test_002_release_names_unlogged_pr and test-aai-release.sh test_031_unprotected_path_byte_identical selectors (exit 0); scans tests/ for files that copy aai-release.sh into a scratch tree and requires each to name release-cut.mjs; runs check-vendored-script-deps.mjs (exit 0). The full test-aai-release.sh, test-aai-learned-routing.sh and test-aai-release-notes.sh runs are Verification steps | `patch:docs/ai/tdd/spec-release-on-node/mutation-TEST-3474.patch` on tests/skills/test-aai-learned-routing.sh | green |
| TEST-3475 | Spec-AC-13 | inspection | tests/skills/test-aai-release-cut.sh | test_3475_wiring pipes each of the module, both scripts and the three test files to node .aai/scripts/select-suites.mjs --files-from - and requires aai-release-cut, and the module also aai-release; requires one suite-weights row at 196 with its fallback line; requires exactly one -eq row-count literal in the hygiene pack and none in TEST-3428 and TEST-3458; runs hygiene-pack test_090 and test_129, cloudflare-share test_3428_wiring and pre-commit-checks test_3458_wiring selectors (exit 0); runs nested-suite-lint with its allowlist, check-cd-subshell-leak and check-test-registration (exit 0); requires the module once under core in PROFILES and runs layer-profiles test_manifest_conformance; requires the module in both ps1-quality path lists and runs win-fallback test_034 | `sed:s/      - \.aai\/scripts\/release-cut\.mjs/      - .aai\/scripts\/release-cut-gone.mjs/` on tests/skills/suite-map.yaml | green |
| TEST-3476 | Spec-AC-14 | inspection | tests/skills/test-aai-release-cut.sh | test_3476_rfc_and_preamble runs test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires release-cut.mjs in the aai-release inventory row, the phase 5 row with status in progress and the D-RFC sentence exactly once with a link ending release-on-node.md, reads the CHANGELOG preamble (lines before the first unreleased heading) for the four exit-12 arms, and runs test-aai-release.sh test_570_changelog_shape_is_documented (exit 0) | `sed:s/The tenth slice \[moved the release rollup to Node\]/The tenth slice [moved the release rollup]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3477 | Spec-AC-15 | inspection | tests/skills/test-aai-release-cut.sh | test_3477_line_budget counts code lines with grep -cvE on the hash comment and blank pattern under bash with /usr/bin/grep when present: aai-release.sh at most 160, aai-release.ps1 at most 220; prints before 641, the after sum, the removed lines and the module's code lines (the module is JavaScript, so its lines are counted with the double-slash comment pattern instead of the hash pattern); reads the EXIT constant of the module and requires each value and 1 as exit N = in SKILL_RELEASE | `patch:docs/ai/tdd/spec-release-on-node/mutation-TEST-3477.patch` on .aai/scripts/aai-release.sh | green |
| TEST-3478 | Spec-AC-16 | integration | tests/skills/test-aai-release-cut.sh | test_3478_early_close runs run_node_tests TEST-3478: the module plan on the Spec-AC-02 fixture piped into head -1 under bash, asserting empty stderr and exit 141 from PIPESTATUS | `sed:s/e.code === 'EPIPE'/e.code === 'EXXXX'/` on .aai/scripts/release-cut.mjs | green |

Test counts by type: unit 3, integration 9, inspection 4, e2e 1 (17 rows;
the 22 DR cases are node:test cases inside TEST-3464 to TEST-3466).

Seams crossed (Principle 2): the module and the real `lib/release-rollup.mjs`
that the remote finish also uses (TEST-3468 compares the scripts' cut with a
direct rollup of the base blob); the module and the real
`release-finish.mjs --audit` (TEST-3463, TEST-3474); each script under every
engine that runs it (TEST-3470, TEST-3471, TEST-3472; Windows PowerShell 5.1
and pwsh 7 on native Windows in H1); the existing Pester files that
dot-source the `.ps1` (TEST-3472); aai-sync's core profile copy to the
target's own scripts (TEST-3473); fixtures in other suites that copy the
scripts (TEST-3474); the RFC inventory read by SPEC-0249's check and the
CHANGELOG preamble read by TEST-570 (TEST-3476); select-suites, the
hygiene pins, the nested-suite lint, the cd ratchet and the registration
check reading the new suite (TEST-3475); the ps1-quality path lists read by
win-fallback test_034 (TEST-3475); SKILL_RELEASE's exit-code list
(TEST-3477).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-cut.sh`
  exits 0 (17 rows), plus the touched and selected suites, each run the same
  way: test-aai-release.sh, test-aai-release-notes.sh,
  test-aai-learned-routing.sh, test-aai-hygiene-pack.sh,
  test-aai-cloudflare-share.sh, test-aai-pre-commit-checks.sh,
  test-aai-layer-profiles.sh, test-aai-expert-fetch.sh,
  test-aai-win-fallback.sh, test-aai-suite-select.sh, test-ps1-quality.sh.
  No full sweep is required by this spec; Validation decides its own.
- `env -u AAI_ROLE node --test tests/skills/lib/release-cut.test.mjs` exits 0
  with at least 24 passing cases (22 DR cases plus TEST-3462 and TEST-3463).
- No prompt change: `git diff --stat main -- '.aai/*.prompt.md' .aai/AGENTS.md`
  prints nothing (recorded in the validation report, not pinned by a test).
- Not edited (coordination): `git diff --stat main -- .aai/scripts/release-dry-run.mjs .aai/scripts/lib/release-rollup.mjs .aai/scripts/release-finish.mjs tests/skills/test-aai-release-first.sh tests/skills/lib/release-first.test.mjs tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/aai-update.Tests.ps1`
  prints nothing.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell
  5.1 and pwsh 7 with `release-cut.Tests.ps1` discovered and not skipped
  (the DR-06 5.1 arm is proven only there).
- H2 (hosted): the required `release-dry-run` CI job passes with the three
  new test files in its reader corpus.

## Evidence contract

ref_id `release-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/release-on-node/` and `docs/ai/tdd/spec-release-on-node/`
(gitignored); each AC row's Evidence names its green log and mutation
record; the validation report and review verdict under `docs/ai/reports/`
and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity (DR-06, DR-21, DR-22) is proven only on the
  hosted job (H1); Planning had no Windows engine.
- DR-01, DR-02, DR-03 and DR-07 make the plan and the local cut refuse or
  reorder input that both scripts used to accept as is. The remote finish
  already did so, so a downstream CHANGELOG that passed a plan but would
  have failed `--confirm` now fails at the plan instead. The CHANGELOG entry
  and the preamble name it.
- The plan's em dashes and the notes preview print as mojibake on a Windows
  PowerShell 5.1 console whose code page is not UTF-8; the notes preview
  already did. Not fixed here.
- The three new test files join the release-dry-run reader corpus and its CI
  budget (Coordination).
- The unlogged-PR audit's own classification is unchanged; the three
  situations it collapses stay open (`fu-release-unlogged-pr-three-classes`).

## Follow-ups

- `fu-release-slice-b-delete-twins` (P2, ref `release-on-node`, added with
  `follow-ups.mjs add` at the close of this ride): slice (b) of the plan's
  ride 6. The tag, publish and release-PR steps run on the platform adapter
  (with `fu-platform-adapter-release`), the remaining script steps move to
  Node, the out-of-scope drifts listed under D-DRIFT are decided, and both
  scripts are deleted. The roadmap item `release-on-node` stays the
  capability; `ship-append` added nothing (already on the roadmap).

Registry items closed by this scope: fu-suite-map-row-count-pin-sprawl (D-WIRE), fu-release-ps1-origin-check-ps51-test (DR-20: the PowerShell origin probe is deleted and the module's probe is pinned), fu-changelog-exit12-second-arm (D-RFC preamble).

Items this scope leaves open, with reasons: fu-release-unlogged-pr-three-classes (the audit classifier in release-finish.mjs is not changed; the module relays its lines), fu-changelog-shape-third-statement (the advice line moves into the module verbatim; widening TEST-570's statement count is a wording decision outside this port), fu-platform-adapter-release (slice b), fu-pcc-ride-scoped-pins (pins on pre-commit-checks.sh, which this slice does not touch).
