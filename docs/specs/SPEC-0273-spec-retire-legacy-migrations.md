---
id: spec-retire-legacy-migrations
type: spec
number: 273
status: done
mutation_gate: v1
frozen_sha256: de9aadce58fba6ff699e31582ff773b4ef67433fed66b16521c4923407632cdc
ceremony_level: 2
links:
  requirement: retire-legacy-migrations
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Retire aai-canonicalize and migrate-yaml-to-jsonl, move migrate-state-to-local to Node

SPEC-FROZEN: true

## Links

- Requirement: [Retire the legacy migration scripts and port migrate-state-to-local to Node](../issues/CHANGE-0245-retire-legacy-migrations.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 1 with its owner decisions of 2026-11-05 (section 4, items 1 and 2).
- Pattern precedents: [SPEC-0265](SPEC-0265-spec-node-first-small-pairs.md)
  (pre-compact-save retirement, small pairs) and
  [SPEC-0267](SPEC-0267-spec-node-first-reap-tests.md) (one module, thin
  launchers, measured drift table, `node:test` per behavior, Pester on the
  native Windows job, a scratch `aai-sync` install proving the launchers).
- Deprecated-skill precedent: SPEC-0014 (`/aai-auto-trigger`: notice prompt,
  wrappers kept, description leads with the marker, catalog relabelled).
- Retired-wrapper prune: the `sync-prune-retired-skill-wrappers` predicate
  `is_retired_skill_wrapper` in `.aai/scripts/aai-sync.sh` and its
  `aai-sync.ps1` twin (not edited here).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor
  downstream, Node 24 CI).
- Baseline: main `f324b66f`; the ride branch adds only the intake (`fa9c4169`).

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs. The new
  module, both migrate-state launchers, the four retirement launchers and the
  prunable wrapper shape are behavior on a consumer-visible path that writes a
  target's git index, so every row goes RED first on the baseline and carries
  a mutation record. The documentation, wiring and ledger rows are pinned by
  inspection tests that are RED on the baseline too.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to shipped core and extended scripts, a
  shipped skill in four harness trees, a CI workflow path filter, the vendored
  profile manifest, the prompt-diet ledger and an umbrella RFC.
- User decision: worktree (autopilot default, recorded via state.mjs
  set-worktree)
- Base ref: main
- Worktree branch/path: refactor/retire-legacy-migrations at /Users/ales/Projects/aai-worktrees/retire-legacy-migrations
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/migrate-state-to-local.mjs .aai/scripts/migrate-state-to-local.sh
  .aai/scripts/migrate-state-to-local.ps1 .aai/scripts/aai-canonicalize.sh
  .aai/scripts/aai-canonicalize.ps1 .aai/scripts/migrate-yaml-to-jsonl.sh
  .aai/scripts/migrate-yaml-to-jsonl.ps1 .aai/SKILL_CANONICALIZE.prompt.md
  .aai/AGENTS.md .claude/skills/aai-canonicalize/SKILL.md
  .agents/skills/aai-canonicalize/SKILL.md .codex/skills/aai-canonicalize/SKILL.md
  .gemini/skills/aai-canonicalize/SKILL.md .codex/skills/README.md
  .gemini/skills/README.md SKILLS.md docs/USER_GUIDE.md docs/SKILL_CATALOG.html
  docs/skill-catalog-data.json .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/test-aai-legacy-migrations.sh
  tests/skills/lib/migrate-state-to-local.test.mjs
  tests/skills/legacy-migrations.Tests.ps1 tests/skills/lib/prompt-diet-ledger.sh
  tests/skills/test-aai-prompt-diet.sh tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/issues/CHANGE-0245-retire-legacy-migrations.md
  docs/specs/SPEC-0273-spec-retire-legacy-migrations.md
  tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-harness-shims.sh
  (suite-weights.tsv only if the selector asks for a row).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 5 and `/bin/sh`, dash, Node
22.23.1, pwsh 7.6.3, git 2.54) on 2026-11-05. Windows PowerShell 5.1 was not
available to Planning; rows marked "by inspection" were read from the code.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`).

| Script | Total lines sh/ps1 | Code lines sh/ps1 |
|---|---|---|
| aai-canonicalize | 276/281 | 223/228 |
| migrate-yaml-to-jsonl | 126/151 | 78/99 |
| migrate-state-to-local | 162/175 | 122/143 |

Before: 1171 total lines, 893 code lines over the six files. For the `.mjs`
module the same method counts lines that are not blank and do not start with
`//` (measured with `grep -cvE '^[[:space:]]*(//|$)'`), so a comment in either
language is not logic.

### Callers and pins (tracked files, docs history excluded)

- `aai-canonicalize` (.sh/.ps1): called only by `.aai/SKILL_CANONICALIZE.prompt.md`
  step 3; listed in `.aai/system/PROFILES.yaml` (`extended:`); one row in
  `tests/skills/lib/cd-subshell-leak-baseline.tsv`; named in
  `CHANGELOG.md` history and one archived review.
- `migrate-yaml-to-jsonl` (.sh/.ps1): called only by the two aai-canonicalize
  copies; PROFILES (`extended:`); one cd-subshell baseline row. No prompt,
  test or workflow names it.
- `/aai-canonicalize` skill: prompt `.aai/SKILL_CANONICALIZE.prompt.md` (1950
  bytes, PROFILES `extended:`); wrappers `.claude/skills/aai-canonicalize/SKILL.md`,
  `.agents/skills/aai-canonicalize/SKILL.md`, `.codex/skills/aai-canonicalize/SKILL.md`
  and `.gemini/skills/aai-canonicalize/SKILL.md` (byte-identical; the last
  three are written by `node .aai/scripts/sync-harness-skills.mjs --write`
  from the `.claude` copy); index rows in `.codex/skills/README.md` and
  `.gemini/skills/README.md` (generated by the same script); `SKILLS.md`
  table row (line 24) and section `### aai-canonicalize` (lines 152-162);
  `.aai/AGENTS.md` lines 94, 148 and 216; `docs/USER_GUIDE.md` lines 301,
  1932-1945 and 2373; `docs/SKILL_CATALOG.html` and
  `docs/skill-catalog-data.json` (generated by
  `node .aai/scripts/generate-docs-hub.mjs`); the required-file list of
  `.aai/scripts/validate-skills.mjs` and its three tests
  (`tests/skills/lib/validate-skills.test.mjs`,
  `tests/skills/test-aai-validate-skills.sh`,
  `tests/skills/validate-skills.Tests.ps1`). The prompt still ships this
  release, so the validate-skills list stays as it is.
- `migrate-state-to-local` (.sh/.ps1): named by `.aai/scripts/aai-doctor.mjs`
  lines 341-342 (`run migrate-state-to-local.sh`), `.aai/scripts/aai-sync.sh`
  line 922 (`run bash .aai/scripts/migrate-state-to-local.sh`),
  `.aai/scripts/aai-sync.ps1` line 932 (`run pwsh .aai/scripts/migrate-state-to-local.ps1`)
  and `README.md` line 167; PROFILES `core:`; one cd-subshell baseline row;
  `tests/skills/test-aai-sync-seed.sh` TEST-016 (asserts the
  RUNTIME_IGNORE.list header does NOT claim the ps1 as a consumer; unchanged);
  a comment in `tests/skills/test-aai-hygiene-pack.sh` line 1798. No test
  runs either copy today.
- RFC-0017 "Remaining paired scripts after phase 3" lists all three pairs;
  `tests/skills/test-aai-expert-fetch.sh` TEST-2624 (`inventory_check`)
  requires the table to equal the set of `.sh`/`.ps1` pairs without a `.mjs`,
  with destinations from a closed list.

### Drift between the two migrate-state-to-local copies

Both copies ran on the same legacy fixture (a git repository whose `.gitignore`
holds one CRLF line and which tracks `docs/ai/STATE.yaml`,
`docs/ai/LOOP_TICKS.jsonl`, `docs/ai/tdd/.gitkeep`, `docs/ai/tdd/x/red.log`,
`docs/ai/loop/a.txt` and a file `docs/ai/tdd/x/<e-acute> $(touch PWNED).log`).

| Id | Case | sh copy | ps1 copy | Decision |
|---|---|---|---|---|
| M-1 | ignore entries added | 6: STATE, LOOP_TICKS, `docs/ai/tdd/**`, `!docs/ai/tdd/`, `!docs/ai/tdd/.gitkeep`, `docs/ai/loop/` (measured) | 16, the six plus validation, locks, hitl-channel, briefs, reports, friction, archive, two sidecars and `docs/INDEX.audit.md` (measured) | the ps1 set of 16, in the ps1 order (D1); POSIX users gain 10 entries |
| M-2 | file name under the evidence dirs that git quotes (non-ASCII) or that holds shell syntax | `eval` runs the name: the fixture's `$(touch PWNED)` created a file `PWNED`, then git refused the mangled pathspec and the script aborted with exit 128 after untracking four files and before writing `.gitignore` or `EVENTS.jsonl` (measured) | the quoted name reaches `git rm` as a pathspec that matches nothing; the error is printed, the file stays tracked, the count still says 5 (measured) | names are read with `ls-files -z` and passed to one `git rm` through standard input with literal pathspecs; no shell sees a name (D1) |
| M-3 | a `git rm` that fails | aborts mid-way, partial effects (measured) | continues and counts the failed file as untracked (measured) | one `git rm` call for all paths; on failure the module prints the error, exits 1 and writes neither `.gitignore` nor `EVENTS.jsonl` |
| M-4 | a name holding pathspec magic (`*`) | glob pathspec, can match `.gitkeep` (by inspection) | same (by inspection) | literal pathspecs (`GIT_LITERAL_PATHSPECS=1`), so `.gitkeep` stays tracked |
| M-5 | git's own `rm '...'` lines | printed (measured) | suppressed (measured) | suppressed (`--quiet`) |
| M-6 | final line when nothing changed | `Nothing to do — already migrated.` (em dash) | `Nothing to do - already migrated.` | ASCII hyphen |
| M-7 | dry-run line per untracked file | `  [dry-run] git -C "<target>" rm --cached "<file>"` | `  [dry-run] git rm --cached <file>` | the ps1 form |
| M-8 | dry-run closing line | `Re-run without --dry-run to apply.` | `Re-run without -DryRun to apply.` | `Dry-run only. Re-run without the dry-run flag to apply.` (true for both launchers) |
| M-9 | end of line of appended entries | LF (measured) | the platform newline (CRLF on Windows, by inspection) | CRLF when the existing `.gitignore` holds a CRLF, else LF; a missing final newline is written first |
| M-10 | target when none is given | logical `$PWD` | the PowerShell location | `process.cwd()` (physical path; only the `Target:` and next-step lines can differ under a symlinked directory) |
| M-11 | target that does not exist | bash `cd` error, exit 1 | `Resolve-Path` error, exit 1 | `ERROR: target directory not found: <raw>`, exit 1 |
| M-12 | second positional argument or unknown option | exit 2 for a second positional; an unknown `--x` becomes the target and fails in `cd` | parameter-binding error | `ERROR: unexpected argument: <a>` or `ERROR: unknown option: <a>`, exit 2 |
| M-13 | help | prints the header comments, exit 0 | Get-Help only | `--help` and `-h` print the usage text on stdout, exit 0 |
| M-14 | git not installed | `git` not found from the first call (by inspection) | same | `ERROR: git not found in PATH.`, exit 1 |

Unchanged in both and kept: the untrack set (STATE, LOOP_TICKS when tracked,
every tracked file under `docs/ai/tdd` and `docs/ai/loop` except names ending
`/.gitkeep`), the dirty-tree refusal on `git status --porcelain`, the CR-tolerant
exact-line check, the header line, the empty `EVENTS.jsonl`, the summary and
next-step text, never committing.

## Decisions

- D-RETIRE (owner decision 2026-11-05): `aai-canonicalize` and
  `migrate-yaml-to-jsonl` stay one release as deprecation launchers, then a
  later release deletes them, the prompt and the four wrappers. Unlike
  pre-compact-save (deleted outright in SPEC-0265), nothing is deleted here.
- D-EXIT: a retirement launcher exits 1, prints exactly one line on stderr and
  nothing on stdout, ignores every argument and needs neither Node nor Python.
- D-REPL: the replacement is `none` for both scripts and for the skill; they
  were one-off migrations from layouts and YAML telemetry no supported layer
  writes.
- D-PRUNE: the wrappers keep the two-line delegation shape that
  `is_retired_skill_wrapper` recognises (the inserted retirement clause holds
  no `.aai/` and the not-found line stays verbatim), so the later release's
  deletion of the prompt and the source wrappers removes downstream copies
  through the existing aai-sync prune. aai-sync is not edited.
- D-PATTERNS: the module adds the ps1 copy's 16 ignore entries (M-1). Reading
  `.aai/system/RUNTIME_IGNORE.list` instead was rejected: it adds 15 more
  entries, makes this script a consumer that the list's header and
  `test-aai-sync-seed.sh` TEST-016 say it is not, and aai-sync already
  reconciles that block on every update.
- D-NAMES: M-2 to M-4; one `git update-index --force-remove -z --stdin` with
  `GIT_LITERAL_PATHSPECS=1` (no pathspec parsing at all; it honours the cwd
  prefix, so a target below the git top level migrates as the old scripts did).
- D-NODE (owner decision 2026-11-05): Node is a hard prerequisite; without it
  (or without the module) each migrate-state launcher prints a refusal with an
  install hint and exits 1, and nothing is changed.
- D-CALLERS: aai-doctor.mjs, aai-sync.sh, aai-sync.ps1 and README.md are not
  edited; the commands they print keep working.
- D-INV: in the RFC-0017 inventory the two retired pairs keep their rows and
  the destination `later candidate` (TEST-2624's closed list is not widened, so
  no contract amendment), with the reason cell rewritten; the
  migrate-state-to-local row is removed because the pair now has a `.mjs`.
- D-DIET: the prompt shrink is reclaimed by one negative ledger entry equal to
  the measured byte delta, so TEST-010 headroom stays 0/2048 and the TEST-012
  pin moves down by the same number.
- D-VALIDATE: `.aai/scripts/validate-skills.mjs` keeps
  `.aai/SKILL_CANONICALIZE.prompt.md` in its required list this release (the
  file still ships); the deleting release removes it.

## Scope and design

### D1. `.aai/scripts/migrate-state-to-local.mjs`

Dependency-free ESM, Node 22 compatible (`node:child_process`, `node:fs`,
`node:path`, `node:url` only), at most 200 lines, ASCII only, no side effects
on import, never reads its own standard input. The main guard compares
`realpathSync` of `process.argv[1]` and of the module, as aai-live.mjs does.

Exports: `IGNORE_PATTERNS`, `parseArgs(argv)`, `missingPatterns(text,
patterns)`, `gitignoreAppend(text, patterns)` (the exact string to append),
`run(opts, deps)` (deps: `git(args, input)` returning `{ status, stdout,
stderr }`, `fs`, `out`, `err`) and `main()`.

It contains these exact lines, each once:

```js
const UNTRACK_FILES = ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl'];
const EVIDENCE_DIRS = ['docs/ai/tdd', 'docs/ai/loop'];
const EVENTS_FILE = 'docs/ai/EVENTS.jsonl';
const HEADER = '# AAI per-dev runtime state (RFC-0001: never committed)';
const DIRTY_LINE = 'ERROR: working tree has uncommitted changes.';
const CRLF = String.fromCharCode(13, 10);
const GIT_ENV = { ...process.env, GIT_LITERAL_PATHSPECS: '1' };
const RM_ARGS = ['update-index', '--force-remove', '-z', '--stdin'];
  const useCrlf = text.includes(CRLF);
  if (rm.status !== 0) {
```

`IGNORE_PATTERNS` is one entry per line, in this order: `docs/ai/STATE.yaml`,
`docs/ai/LOOP_TICKS.jsonl`, `docs/ai/tdd/**`, `docs/ai/validation/**`,
`!docs/ai/tdd/`, `!docs/ai/tdd/.gitkeep`, `docs/ai/loop/`, `docs/ai/locks/`,
`docs/ai/hitl-channel.json`, `docs/ai/briefs/**`, `docs/ai/reports/**`,
`docs/ai/friction/**`, `docs/ai/archive/**`, `docs/ai/.session-context.md`,
`docs/ai/.pre-compact-state-backup.yaml`, `docs/INDEX.audit.md`, each written
as `  '<pattern>',`.

Arguments: at most one positional target (default `process.cwd()`, resolved
with `path.resolve`), `--dry-run`, `-h` or `--help`. Checks in this order,
each refusal on stderr: M-12 (exit 2), M-13, M-11, `ERROR: <target>/docs/ai
not found. Is this an AAI project?` (exit 1), M-14, `ERROR: <target> is not
inside a git repository.` (exit 1, from `git -C <target> rev-parse
--git-dir`), and the dirty tree (`git -C <target> status --porcelain` not
empty): the two lines `DIRTY_LINE` and
`       Commit or stash them first, then re-run this script.`, exit 1.

Effects, in order, every git call as `git -C <target> ...` with `GIT_ENV`:
1. Tracked set: one `ls-files -z --` over `UNTRACK_FILES` and `EVIDENCE_DIRS`.
   For each of `UNTRACK_FILES`: `UNTRACK <f> (file remains on disk)` when
   tracked, else `SKIP    <f> (already untracked or absent)`. Then each
   tracked file under `EVIDENCE_DIRS` whose name does not end `/.gitkeep`, in
   ls-files order: `UNTRACK <f> (runtime evidence; file remains on disk)`. In
   a dry run each UNTRACK line is followed by `  [dry-run] git rm --cached <f>`.
2. Unless dry run and only when the set is not empty: one `git` call with
   `RM_ARGS`, the NUL-joined paths on its standard input. On a non-zero
   status: `ERROR: git rm --cached failed (exit <n>): <first non-empty stderr
   line>`, exit 1, and steps 3 and 4 do not run.
3. `.gitignore` at `<target>/.gitignore`: for each pattern, CR-tolerant exact
   line match; the first missing one prints `GITIGNORE add header + entries to
   <target>/.gitignore`, each missing one `GITIGNORE add: <p>`, each present
   one `SKIP    .gitignore already contains <p>`. Unless dry run, one append
   (the file is created when absent): when the existing text is not empty and
   does not end in a newline, one end-of-line first; then an empty line,
   `HEADER`, and each missing pattern, every line ended by CRLF when
   `useCrlf`, else LF.
4. `CREATE  docs/ai/EVENTS.jsonl (empty, append-only audit log)` and, unless
   dry run, an empty file; or `SKIP    docs/ai/EVENTS.jsonl already exists`.

Output frame on stdout: `AAI per-dev runtime state migration (RFC-0001)`,
`Target: <target>`, in a dry run `Mode:   dry-run (no changes will be
written)`, an empty line, the step lines, an empty line, `Summary:`,
`  Files untracked:        <n>`, `  .gitignore entries added: <n>`,
`  EVENTS.jsonl created:   <0 or 1>`. Then a dry run prints an empty line and
`Dry-run only. Re-run without the dry-run flag to apply.`; a run that changed
something prints an empty line, `Next steps (run manually):`,
`  git -C "<target>" add .gitignore docs/ai/EVENTS.jsonl`,
`  git -C "<target>" commit -m "Migrate AAI STATE to per-dev local runtime (RFC-0001)"`,
an empty line, `After commit, other developers will see STATE.yaml and LOOP_TICKS.jsonl`
and `vanish from the tree on next pull. Their local copies remain on disk.`;
otherwise an empty line and `Nothing to do - already migrated.`. Exit 0 on
these three paths. The module never commits.

### D2. migrate-state-to-local launchers

- `migrate-state-to-local.sh`: at most 20 lines, ASCII, `#!/bin/sh`, POSIX
  only (no `[[`, no `BASH_SOURCE`; it runs under `bash`, `sh` and `dash`),
  executable bit kept (100755):
  ```sh
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/migrate-state-to-local.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    exec node "$MODULE" "$@"
  fi
  echo "migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
  exit 1
  ```
  plus a comment line saying the logic lives in migrate-state-to-local.mjs
  (RFC-0017 phase 5) and the usage line
  `# Usage: sh .aai/scripts/migrate-state-to-local.sh [path-to-target-project] [--dry-run]`.
- `migrate-state-to-local.ps1`: at most 20 lines, ASCII, the same pointer
  comment, the usage comment
  `# Usage: powershell -NoProfile -File .aai/scripts/migrate-state-to-local.ps1 [-TargetRoot <path>] [-DryRun]`,
  `[CmdletBinding()]` (so a mistyped switch is a binding error, nothing runs),
  `param([string]$TargetRoot = (Get-Location).ProviderPath, [switch]$DryRun)`,
  `$Module = Join-Path $PSScriptRoot 'migrate-state-to-local.mjs'`, and when
  node and the module exist `$nodeArgs = @($Module, $TargetRoot)`,
  `if ($DryRun) { $nodeArgs += '--dry-run' }`, `& node @nodeArgs`,
  `exit $LASTEXITCODE`; else the same refusal line through
  `[Console]::Error.WriteLine` and `exit 1`.
- Neither launcher holds `rm --cached`, `ls-files`, `.gitignore`,
  `EVENTS.jsonl`, `UNTRACK` or an ignore pattern.

### D3. Retirement launchers

Each of the four files is at most 20 lines, ASCII, keeps its git file mode
(all four are 100644 today), holds one comment line beginning
`# RETIRED (RFC-0017 phase 5, retire-legacy-migrations)` that says it is a
deprecation launcher for one release and the next release deletes it, then
writes exactly one line to stderr and `exit 1`. The `.sh` files start with
`#!/bin/sh` and use `echo "<line>" >&2`; the `.ps1` files have no param
block and use `[Console]::Error.WriteLine('<line>')`. The lines:

- aai-canonicalize: `aai-canonicalize: retired - the aai-canonicalize script and the /aai-canonicalize skill are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed`
- migrate-yaml-to-jsonl: `migrate-yaml-to-jsonl: retired - the migrate-yaml-to-jsonl script is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed`

No retirement launcher names `python`, `node`, `git`, `mv`, `cp`, `rm` or
`mkdir`.

### D4. The /aai-canonicalize skill

- `.aai/SKILL_CANONICALIZE.prompt.md`: at most 900 bytes, first line
  `# Canonicalize Skill - RETIRED`, a line beginning `Status: RETIRED
  (retire-legacy-migrations, RFC-0017 phase 5, 2026-11-05)`, a sentence that
  the next release deletes the notice, the wrappers and both scripts, a line
  beginning `Replacement: none`, and the instruction to tell the user the
  skill is retired and change nothing. It names no `.sh` or `.ps1` file and no
  `-DryRun` or `--dry-run`.
- `.claude/skills/aai-canonicalize/SKILL.md`: frontmatter `name:
  aai-canonicalize`, `description:` beginning `RETIRED - ` and saying the skill
  and both scripts are retired (RFC-0017 phase 5), are deleted in the next
  release, have no replacement, and that invoking it explains the retirement
  and runs nothing. Body, two non-empty lines exactly:
  `` Read the file `.aai/SKILL_CANONICALIZE.prompt.md` from the current project root and follow its instructions exactly - it is a retirement notice: explain it to the user and run no script. Invoke this as `/aai-canonicalize`. ``
  and the unchanged not-found line. The other three trees are regenerated with
  `node .aai/scripts/sync-harness-skills.mjs --write`, which also rewrites the
  `.codex/skills/README.md` and `.gemini/skills/README.md` rows.
- `docs/SKILL_CATALOG.html` and `docs/skill-catalog-data.json` regenerated
  with `node .aai/scripts/generate-docs-hub.mjs`.
- `.aai/AGENTS.md`: line 94 becomes
  `Follow .aai/SKILL_CANONICALIZE.prompt.md # RETIRED: deprecation notice only, deleted in the next release`;
  the line `- Use SKILL_CANONICALIZE when migrating legacy AAI structure or cleaning up scattered artifacts.`
  and the line `  - \`codex --prompt-file .aai/SKILL_CANONICALIZE.prompt.md\`` are deleted.
- `SKILLS.md`: the table row keeps its four cells, the second reading
  `Retired: deprecation notice only, deleted in the next release; no replacement`;
  the `### aai-canonicalize` section body becomes one paragraph saying the
  skill is retired (RFC-0017 phase 5), runs nothing and is deleted in the
  next release, with no code block.
- Added in run 4 (additive): the `### aai-canonicalize` and `#### `/aai-canonicalize``
  headings gain the suffix ` (retired)` so that every line naming the skill says
  retired (Spec-AC-10); the bodies are as stated here.
- `docs/USER_GUIDE.md`: the table row's second and third cells become
  `Retired` and `Deprecation notice only; deleted in the next release`; the
  `#### \`/aai-canonicalize\`` section becomes one paragraph beginning
  `**What:** Retired`; the monthly list line becomes
  `- \`/aai-canonicalize\` - Retired (deleted in the next release)`.

### D5. Wiring

- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/migrate-state-to-local.mjs`
  once in `core:` beside the two launchers. The retired files keep their
  `extended:` entries.
- `tests/skills/suite-map.yaml`: new row `aai-legacy-migrations` with globs
  `.aai/scripts/migrate-state-to-local.*`, `.aai/scripts/aai-canonicalize.*`,
  `.aai/scripts/migrate-yaml-to-jsonl.*`, `.aai/SKILL_CANONICALIZE.prompt.md`,
  the four `*/skills/aai-canonicalize/**` trees,
  `tests/skills/test-aai-legacy-migrations.sh`,
  `tests/skills/lib/migrate-state-to-local.test.mjs`,
  `tests/skills/legacy-migrations.Tests.ps1`.
- `.github/workflows/ps1-quality.yml`: `.aai/scripts/migrate-state-to-local.mjs`
  added to the `push` and `pull_request` path lists, which stay identical (the
  derivation pin in `test-aai-win-fallback.sh` test_034 to test_036 decides
  anything else). No job, runner or step added; the native Windows Pester jobs
  pick up the new `*.Tests.ps1` by directory.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv` re-recorded with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record`.
- `tests/skills/lib/prompt-diet-ledger.sh`: one entry
  `JUSTIFIED_ADDITIONS+=( "-<N> retire-legacy-migrations RECLAIMED credit (NEGATIVE entry, ...)" )`
  where N is the measured shrink of `.aai/SKILL_CANONICALIZE.prompt.md`;
  `tests/skills/test-aai-prompt-diet.sh` TEST-012 pin and its comment move
  from 65792 to 65792 minus N.

### D6. RFC-0017

- The phase 5 row gains one sentence before the remaining-scripts-plan
  sentence: `The fifth slice [retired the legacy migrations](../issues/CHANGE-0245-retire-legacy-migrations.md): aai-canonicalize with its skill and migrate-yaml-to-jsonl became deprecation launchers for one release, and migrate-state-to-local moved to one Node module with thin launchers.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  the link at merge; checks match only the suffix `retire-legacy-migrations.md`.
- Inventory (D-INV): the `migrate-state-to-local` row is removed; the
  `aai-canonicalize` and `migrate-yaml-to-jsonl` rows keep their Pair, Lines
  and Destination cells, and their Reason cell becomes
  `retired by the [legacy-migrations slice](../issues/CHANGE-0245-retire-legacy-migrations.md); a deprecation launcher for one release, deleted in the next`.
  Every other row stays byte for byte.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(scripts): legacy migrations retired, migrate-state-to-local moves to Node`
  naming the retirement and its one-release window, M-1, M-2, M-3, M-6 to
  M-9, D-NODE and the before/after code lines.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-08.
- Intake AC-002 maps to Spec-AC-09, Spec-AC-10 and Spec-AC-11.
- Intake AC-003 maps to Spec-AC-01 and Spec-AC-05.
- Intake AC-004 maps to Spec-AC-02, Spec-AC-03 and Spec-AC-04; every drift
  row has a named test: M-1, M-5, M-6, M-9 TEST-3380 and TEST-3381; M-7, M-8,
  M-11 to M-14 TEST-3382; M-2 to M-4 TEST-3383 and TEST-3384; M-10 TEST-3387.
- Intake AC-005 maps to Spec-AC-06, Spec-AC-07 and Spec-AC-12, and to hosted
  check H1 (the native Windows Pester jobs under Windows PowerShell 5.1 and
  pwsh 7 run `tests/skills/legacy-migrations.Tests.ps1`).
- Intake AC-006 maps to Spec-AC-13, Spec-AC-14, Spec-AC-15 and Spec-AC-16.
- Intake AC-007 maps to Spec-AC-17.

## Constitution deviations

None. Article 4 (degrade and report): without Node the migrate-state
launchers print a named refusal with an install hint and exit 1; a failed
`git rm` is reported and stops before any other write. Article 5 (additive
first): the retirement keeps every command name for one release and says so
on use; the 10 extra ignore entries on POSIX are additive and named in the
CHANGELOG. Article 2 (simplicity): no new flag, variable or seam; aai-sync is
not edited.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the module's pure functions run on fixtures the system SHALL export IGNORE_PATTERNS as exactly the 16 D1 entries in order, parse the D1 arguments with exit codes 2 for M-12, match lines CR-tolerantly, and return from gitignoreAppend the exact D1 block with LF for an LF or absent file, CRLF for a file holding a CRLF, and one leading end-of-line when the text lacks a final newline. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3380.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3380.txt | - | TEST-3380 |
| Spec-AC-02 | WHEN the module runs on a clean legacy git fixture the system SHALL untrack STATE, LOOP_TICKS and every non-.gitkeep file under docs/ai/tdd and docs/ai/loop (files kept on disk), append the header and the 16 entries once, create an empty EVENTS.jsonl, print the D1 frame with counts and next steps and exit 0, and a second run after committing SHALL print Nothing to do - already migrated. with zero counts and leave the tree byte-identical. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3381.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3381.txt | - | TEST-3381 |
| Spec-AC-03 | WHEN the module is refused or runs in dry-run mode the system SHALL print each D1 refusal text with its exit code (unknown option 2, missing target, no docs/ai, not a git repository, git missing, dirty tree 1) and help with exit 0, and a dry run SHALL print the M-7 lines and the M-8 line, exit 0 and leave the index, .gitignore and docs/ai byte-identical. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3382.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3382.txt | - | TEST-3382 |
| Spec-AC-04 | WHEN tracked evidence names hold shell syntax, double quotes, backticks, non-ASCII letters or a literal star the system SHALL untrack each of them, run no command from a name, keep docs/ai/tdd/.gitkeep tracked, and WHEN the index removal fails (an existing index.lock) or git skips a listed name without failing (git~1, a non-UTF-8 name) SHALL print the D1 error line, exit 1 and leave .gitignore, EVENTS.jsonl and the index unchanged, and WHEN the target is a subdirectory of its git repository SHALL migrate it with rc 0 and leave the rest of the repository tracked. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3383.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3384.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3401.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3383.txt; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3384.txt; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3401.txt; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3402.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3402-r4.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3402.txt | - | TEST-3383, TEST-3384, TEST-3401, TEST-3402 |
| Spec-AC-05 | The migrate-state launchers are thin per D2 (at most 20 lines each, ASCII, the sh shebang and no double-bracket test, the sh file mode 100755, the module named, none of the D2 forbidden strings), and without node on PATH or without the module each prints exactly the D2 refusal line on stderr, nothing on stdout, exits 1 and leaves the fixture unchanged (sh launcher under bash, sh and dash; ps1 launcher under pwsh). | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3385.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3386.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3385.txt; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3386.txt | - | TEST-3385, TEST-3386 |
| Spec-AC-06 | WHEN the sh launcher runs on a legacy fixture whose path holds a space, once with the target as argument from another directory and once with no argument from inside the target, under bash, sh and dash, the system SHALL produce the Spec-AC-02 effects and exit 0, forward --dry-run, and print Target: with the target directory. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3387.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3387.txt | - | TEST-3387 |
| Spec-AC-07 | WHEN tests/skills/legacy-migrations.Tests.ps1 runs under Pester 5 the system SHALL pass with no failed or skipped case and at least 7 cases: the ps1 launcher with -TargetRoot produces the Spec-AC-02 effects, with -DryRun changes nothing, with a mistyped switch (-DyRun) is refused and changes nothing, from Push-Location with no -TargetRoot migrates the location, from a copy without the module refuses with exit 1, and each retired ps1 launcher prints its D3 line, exits 1 and changes nothing. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3388.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3388.txt | - | TEST-3388 |
| Spec-AC-08 | WHEN any of the four retirement launchers runs (sh files under bash, sh and dash with arguments . --dry-run, ps1 files under pwsh with -TargetRoot . -DryRun, and with PATH holding no node and no python3) the system SHALL print exactly its D3 line on stderr, nothing on stdout, exit 1 and leave a fixture tree byte-identical; each file is at most 20 lines, ASCII, keeps mode 100644, holds the RETIRED comment and none of the D3 forbidden names. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3389.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3390.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3389.txt; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3390.txt | - | TEST-3389, TEST-3390 |
| Spec-AC-09 | The skill is a retirement notice per D4: the prompt is at most 900 bytes with the D4 lines and no .sh, .ps1 or dry-run token; the four wrappers are byte-identical with a description beginning RETIRED and the D4 body; sync-harness-skills --check exits 0; the generated Codex and Gemini index rows and the catalog card for aai-canonicalize contain RETIRED; generate-docs-hub leaves both catalog files unchanged. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3391.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3391.txt | - | TEST-3391 |
| Spec-AC-10 | Outside docs/ history, CHANGELOG.md and tests/, no tracked file names aai-canonicalize.sh, aai-canonicalize.ps1, migrate-yaml-to-jsonl.sh or migrate-yaml-to-jsonl.ps1 except the four launchers and PROFILES.yaml (docs/USER_GUIDE.md and the two catalog files included in the scan); every line of SKILLS.md, .aai/AGENTS.md and docs/USER_GUIDE.md naming aai-canonicalize or SKILL_CANONICALIZE contains retired (any case); AGENTS.md holds no codex prompt-file line and no Use SKILL_CANONICALIZE line for it. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3392.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3392.txt | - | TEST-3392 |
| Spec-AC-11 | WHEN a target holds the shipped aai-canonicalize wrapper in .claude/skills and .agents/skills and aai-sync syncs it from a source copy without SKILL_CANONICALIZE.prompt.md and without the aai-canonicalize wrapper directories, the system SHALL remove both copies with exactly one CLEAN removed retired skill wrapper line each, under aai-sync.sh and under aai-sync.ps1 (pwsh); a sync from the unchanged source SHALL keep the wrapper. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3393.log; docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3394.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3393.txt; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3394.txt | - | TEST-3393, TEST-3394 |
| Spec-AC-12 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space the system SHALL carry migrate-state-to-local.sh, .ps1 and .mjs, and the target's own sh launcher SHALL migrate the target's legacy docs/ai with the Spec-AC-02 effects; WHEN --profile extended installs, each of the target's four retirement launchers SHALL print its D3 line and exit 1. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3395.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3395.txt | - | TEST-3395 |
| Spec-AC-13 | WHEN aai-doctor runs on a legacy fixture whose STATE.yaml is gitignored and still tracked the system SHALL report the INCONSISTENT line naming migrate-state-to-local.sh, and after the named launcher runs and its next-step commit is made the doctor output SHALL no longer name migrate-state-to-local; the migrate-state-to-local lines of aai-doctor.mjs, aai-sync.sh, aai-sync.ps1 and README.md equal those at f324b66f. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3396.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3396.txt | - | TEST-3396 |
| Spec-AC-14 | Wiring per D5: PROFILES core lists the module once and test-aai-layer-profiles.sh exits 0; select-suites maps the module and the prompt to aai-legacy-migrations; both ps1-quality path lists hold the module and stay identical and test-aai-win-fallback.sh test_034 to test_036 exit 0; check-cd-subshell-leak passes and its baseline has no row for aai-canonicalize.sh or migrate-yaml-to-jsonl.sh. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3397.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3397.txt | - | TEST-3397 |
| Spec-AC-15 | The prompt-diet ledger holds exactly one retire-legacy-migrations entry, negative, equal to 1950 minus the delivered prompt size in bytes; test-aai-prompt-diet.sh exits 0 with TEST-010 headroom 0 of 2048 and the TEST-012 pin equal to 65792 minus that shrink. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3398.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3398.txt | - | TEST-3398 |
| Spec-AC-16 | The RFC-0017 inventory equals the pair set of the tree (TEST-2624 exits 0), has no migrate-state-to-local row, the aai-canonicalize and migrate-yaml-to-jsonl rows carry the D6 reason with a link ending retire-legacy-migrations.md, and the phase 5 row keeps status in progress and holds the D6 sentence once. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3399.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3399.txt | - | TEST-3399 |
| Spec-AC-17 | Measured with the plan's method on the delivered tree, the four retirement launchers have at most 2 code lines each, the two migrate-state launchers at most 10 each and the module at most 160, so the seven files hold at most 188 code lines against 893 before; the module is at most 200 lines in total. | done | docs/ai/tdd/retire-legacy-migrations/green/green-TEST-3400.log; docs/ai/tdd/spec-retire-legacy-migrations/mutation-TEST-3400.txt | - | TEST-3400 |

## Implementation plan

TDD in six runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/retire-legacy-migrations/red/` before its code, GREEN under
`green/`, and one mutation record per row
(`node .aai/scripts/mutation-run.mjs`) before the run's hand-off.

1. Run 1, Spec-AC-01 to 03: write `tests/skills/lib/migrate-state-to-local.test.mjs`
   and `tests/skills/test-aai-legacy-migrations.sh` (wrappers fail on zero
   passing tests), then the module (D1).
2. Run 2, Spec-AC-04 to 06: hostile names, the rm failure, both launchers (D2).
3. Run 3, Spec-AC-07, 08 and 13: the Pester file, the four retirement
   launchers (D3), the doctor seam.
4. Run 4, Spec-AC-09 to 11: the skill notice and wrappers, the regenerated
   indexes and catalog, AGENTS.md, SKILLS.md, USER_GUIDE.md (D4), the prune
   seam.
5. Run 5, Spec-AC-12, 14 and 15: the scratch install, wiring and the
   baseline re-record (D5), the ledger true-up.
6. Run 6, Spec-AC-16 and 17: RFC-0017 (D6), the measurement; then the
   CHANGELOG entry after LOOP COMPLETE.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3380 | Spec-AC-01 | unit | tests/skills/test-aai-legacy-migrations.sh | test_3380_pure runs node --test --test-name-pattern TEST-3380 on tests/skills/lib/migrate-state-to-local.test.mjs: IGNORE_PATTERNS deep-equals the 16 D1 entries; parseArgs gives dryRun for --dry-run, help for -h and --help, code 2 for a second positional and for --bogus; missingPatterns finds docs/ai/STATE.yaml in a CRLF text; gitignoreAppend on an empty text, an LF text, a CRLF text and a text without a final newline returns the exact expected strings; the wrapper fails on zero passing tests | `sed:s/const useCrlf = text.includes\(CRLF\);/const useCrlf = false;/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3381 | Spec-AC-02 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3381_effects runs the TEST-3381 node cases on a mkdtemp git fixture (local user.email and user.name, a one-line CRLF .gitignore, tracked STATE, LOOP_TICKS, tdd/.gitkeep, tdd/x/red.log, loop/a.txt): exit 0; ls-files shows only .gitignore and tdd/.gitkeep of those; every file still on disk; .gitignore ends with the header and 16 CRLF lines; EVENTS.jsonl has 0 bytes; stdout holds Files untracked: 4, .gitignore entries added: 16, EVENTS.jsonl created: 1 and the next-step lines; after git add and commit a second run exits 0, prints Nothing to do - already migrated. and the three zero counts, and git status is empty | `sed:s/const EVENTS_FILE = 'docs\/ai\/EVENTS.jsonl';/const EVENTS_FILE = 'docs\/ai\/EVENTS.json';/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3382 | Spec-AC-03 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3382_refusals_dry_run runs the TEST-3382 node cases through the module CLI: --bogus and a second positional exit 2 with the M-12 texts; a missing directory exits 1 with the M-11 text; a git repo without docs/ai and a docs/ai folder outside git each exit 1 with the D1 texts; PATH without git exits 1 with the M-14 text; an untracked extra file gives the two dirty lines and exit 1; --help exits 0 with the usage line; a dry run on the legacy fixture exits 0, prints [dry-run] git rm --cached docs/ai/STATE.yaml and the M-8 line, and the index hash, .gitignore bytes and the docs/ai listing are unchanged | `sed:s/const DIRTY_LINE = 'ERROR: working tree has uncommitted changes.';/const DIRTY_LINE = 'ERROR: dirty.';/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3383 | Spec-AC-04 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3383_hostile_names runs the TEST-3383 node cases: tracked files under docs/ai/tdd/x named with $(touch PWNED), a double quote, a backtick, an e-acute letter, a literal star and a newline; after the run each is untracked and on disk, no file PWNED exists anywhere in the fixture, docs/ai/tdd/.gitkeep is still tracked, Files untracked: equals the number of those names plus STATE | `sed:s/toRemove\.join\('\\0'\)/toRemove.join(' ')/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3384 | Spec-AC-04 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3384_rm_failure runs the TEST-3384 node case: the legacy fixture with an existing .git/index.lock; exit 1, stderr begins ERROR: git rm --cached failed (exit, .gitignore bytes unchanged, no EVENTS.jsonl, ls-files unchanged after the lock is removed | `sed:s/if \(rm.status !== 0\) \{/if (false) {/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3385 | Spec-AC-05 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3385_launchers_thin requires both migrate-state launchers at most 20 lines and ASCII only, the sh first line #!/bin/sh, no [[ and no BASH_SOURCE in it, git ls-files -s mode 100755 for the sh, the string migrate-state-to-local.mjs in both, and none of rm --cached, ls-files, .gitignore, EVENTS.jsonl, UNTRACK, docs/ai/ in either; positive control: a scratch copy with one forbidden string is reported | `sed:s/exit 1/git rm --cached x; exit 1/` on .aai/scripts/migrate-state-to-local.sh | green |
| TEST-3386 | Spec-AC-05 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3386_refusal_no_node runs the sh launcher under bash, sh and dash with PATH set to a scratch bin holding only git and coreutils links (no node), and a launcher copy in a scratch dir without the module under the normal PATH, and the ps1 launcher copy without the module under pwsh: each stderr equals the D2 refusal line, stdout is empty, exit 1, and the fixture's git status and .gitignore bytes are unchanged | `sed:s/command -v node >\/dev\/null 2>&1 && \[ -f "\$MODULE" \]/command -v true >\/dev\/null 2>&1/` on .aai/scripts/migrate-state-to-local.sh | green |
| TEST-3387 | Spec-AC-06 | e2e | tests/skills/test-aai-legacy-migrations.sh | test_3387_sh_launcher_e2e copies the legacy fixture to a directory named with a space, runs bash, sh and dash on the repository's sh launcher with the fixture as argument from TEST_DIR and, on a fresh copy each, with no argument from inside the fixture: each exits 0, prints Target: followed by the fixture directory, and leaves the Spec-AC-02 ls-files result and the 16 entries; a further copy run with --dry-run is unchanged afterwards | `sed:s/exec node "\$MODULE" "\$@"/exec node "$MODULE"/` on .aai/scripts/migrate-state-to-local.sh | green |
| TEST-3388 | Spec-AC-07 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3388_pester runs Invoke-Pester on tests/skills/legacy-migrations.Tests.ps1 with PassThru under pwsh and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 7 (SKIP-CASE without Pester 5, as SPEC-0267 TEST-3239 does); the cases build git fixtures in TestDrive with local identity and run the ps1 launchers with the engine running the test | `sed:s/\$nodeArgs \+= '--dry-run'/$null = 1/` on .aai/scripts/migrate-state-to-local.ps1 | green |
| TEST-3389 | Spec-AC-08 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3389_retired_run runs aai-canonicalize.sh and migrate-yaml-to-jsonl.sh under bash, sh and dash with arguments . --dry-run from inside a committed fixture, and the two ps1 files under pwsh with -TargetRoot . -DryRun, all with PATH limited to a scratch bin holding no node and no python3 (the shells by absolute path): each stderr equals its D3 line, stdout empty, exit 1, git status empty and the fixture file listing unchanged | `sed:s/exit 1/exit 0/` on .aai/scripts/aai-canonicalize.sh | green |
| TEST-3390 | Spec-AC-08 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3390_retired_thin requires each of the four files at most 20 lines, ASCII only, git mode 100644, one line beginning # RETIRED (RFC-0017 phase 5, retire-legacy-migrations), the D3 line text, and none of python, node, git, mv, cp, rm, mkdir as a word; positive control: a scratch copy holding python3 is reported | `sed:s/exit 1/python3 -c pass; exit 1/` on .aai/scripts/migrate-yaml-to-jsonl.sh | green |
| TEST-3391 | Spec-AC-09 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3391_skill_notice requires the prompt at most 900 bytes, its first line # Canonicalize Skill - RETIRED, the Status and Replacement: none lines, no .sh, .ps1, -DryRun or --dry-run; the four wrappers byte-identical, description beginning RETIRED, the D4 body line verbatim; node .aai/scripts/sync-harness-skills.mjs --check exits 0; the aai-canonicalize rows of .codex/skills/README.md and .gemini/skills/README.md and the catalog card contain RETIRED; generate-docs-hub run into a scratch output equals docs/SKILL_CATALOG.html and docs/skill-catalog-data.json | `sed:s/Replacement: none/Replacement: run the migration scripts/` on .aai/SKILL_CANONICALIZE.prompt.md | green |
| TEST-3392 | Spec-AC-10 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3392_no_stale_instruction lists tracked files outside docs/ (plus docs/USER_GUIDE.md, docs/SKILL_CATALOG.html, docs/skill-catalog-data.json), outside tests/ and except CHANGELOG.md, and requires the four retired file names only in the four launchers and .aai/system/PROFILES.yaml; requires retired in every line of SKILLS.md, .aai/AGENTS.md and docs/USER_GUIDE.md naming aai-canonicalize or SKILL_CANONICALIZE; no codex prompt-file line and no Use SKILL_CANONICALIZE line in AGENTS.md; positive control: a fixture list with one extra naming file is reported | `sed:s/# RETIRED: deprecation notice only, deleted in the next release/# Canonicalize repository structure (migration, cleanup)/` on .aai/AGENTS.md | green |
| TEST-3393 | Spec-AC-11 | e2e | tests/skills/test-aai-legacy-migrations.sh | test_3393_prune_sh first requires the repository wrapper to carry the D4 retirement clause, then copies the repository's tracked tree into a scratch source, deletes .aai/SKILL_CANONICALIZE.prompt.md and the four aai-canonicalize wrapper directories there, places the repository's .claude/skills/aai-canonicalize/SKILL.md into a scratch target's .claude/skills and .agents/skills, runs aai-sync.sh from the scratch source: both directories are gone and each CLEAN removed retired skill wrapper line appears exactly once; a second target synced from the repository itself keeps both copies | `sed:s/ Invoke this as/ Read .aai\/SKILL_CANONICALIZE.prompt.md first. Invoke this as/` on .claude/skills/aai-canonicalize/SKILL.md | green |
| TEST-3394 | Spec-AC-11 | e2e | tests/skills/test-aai-legacy-migrations.sh | test_3394_prune_ps1 requires the D4 retirement clause as TEST-3393 does and repeats its removal arm with aai-sync.ps1 under pwsh (need_tool pwsh, SKIP-CASE when absent): both directories gone, one CLEAN line each | `sed:s/name: aai-canonicalize/name: aai-canonicalize-old/` on .claude/skills/aai-canonicalize/SKILL.md | green |
| TEST-3395 | Spec-AC-12 | e2e | tests/skills/test-aai-legacy-migrations.sh | test_3395_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space holding a committed legacy docs/ai, requires the three migrate-state files there, runs the target's own bash .aai/scripts/migrate-state-to-local.sh from inside it and requires the Spec-AC-02 effects; then a --profile extended target, where each of the four retirement launchers (sh under bash, ps1 under pwsh when present) prints its D3 line and exits 1 | `sed:s/  - \.aai\/scripts\/migrate-state-to-local\.mjs/  - .aai\/scripts\/migrate-state-to-local-gone.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3396 | Spec-AC-13 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3396_doctor_seam builds a fixture with .aai/scripts copied from the repository, STATE.yaml tracked and listed in .gitignore; node .aai/scripts/aai-doctor.mjs --root on it prints INCONSISTENT and migrate-state-to-local.sh; bash .aai/scripts/migrate-state-to-local.sh in it, git add .gitignore docs/ai/EVENTS.jsonl and commit; doctor output then holds no migrate-state-to-local; and git show f324b66f lines naming migrate-state-to-local in aai-doctor.mjs, aai-sync.sh, aai-sync.ps1 and README.md equal the working tree's | `sed:s/const UNTRACK_FILES = \['docs\/ai\/STATE.yaml', 'docs\/ai\/LOOP_TICKS.jsonl'\];/const UNTRACK_FILES = ['docs\/ai\/LOOP_TICKS.jsonl'];/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3397 | Spec-AC-14 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3397_wiring requires the module line once under core: in PROFILES.yaml and runs test-aai-layer-profiles.sh (exit 0); node .aai/scripts/select-suites.mjs on the module path and on .aai/SKILL_CANONICALIZE.prompt.md each selects aai-legacy-migrations; both ps1-quality path lists hold the module and are equal; runs test-aai-win-fallback.sh test_034, test_035 and test_036 (each exit 0) and node .aai/scripts/check-cd-subshell-leak.mjs (exit 0); the baseline has no row ending aai-canonicalize.sh or migrate-yaml-to-jsonl.sh | `sed:s/      - '\.aai\/scripts\/migrate-state-to-local\.mjs'/      - '.aai\/scripts\/migrate-state-gone.mjs'/` on .github/workflows/ps1-quality.yml | green |
| TEST-3398 | Spec-AC-15 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3398_diet requires exactly one ledger line naming retire-legacy-migrations whose amount is negative and equals the current byte size of .aai/SKILL_CANONICALIZE.prompt.md minus 1950, runs test-aai-prompt-diet.sh (exit 0) and requires its output to hold headroom 0/2048 and the TEST-012 pin equal to 65792 plus that amount | `sed:s/"-([0-9]+) retire-legacy-migrations/"-1$1 retire-legacy-migrations/` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-3399 | Spec-AC-16 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3399_rfc runs bash tests/skills/test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires no inventory row for migrate-state-to-local, the D6 reason with a link ending retire-legacy-migrations.md in the aai-canonicalize and migrate-yaml-to-jsonl rows, and the phase 5 row with status in progress and the D6 sentence exactly once | `sed:s/retire-legacy-migrations\.md\)/retire-legacy-gone.md)/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3401 | Spec-AC-04 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3401_subdir_target runs the TEST-3401 node case: a git repository whose target is apps/web, holding docs/ai with STATE, LOOP_TICKS, tdd/.gitkeep, tdd/x/red.log and loop/a.txt plus an unrelated tracked docs/ai/tdd/outside.log at the repository top: the module exits 0, ls-files then shows only apps/web/.gitignore, apps/web/docs/ai/tdd/.gitkeep and the outside file, the files stay on disk, EVENTS.jsonl is created empty and Files untracked is 4 | `sed:s/'-z', '--stdin'/'--stdin'/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3402 | Spec-AC-04 | integration | tests/skills/test-aai-legacy-migrations.sh | test_3402_refused_name runs the TEST-3402 node cases: a tracked docs/ai/tdd/git~1/a.log (added with core.protectNTFS off) and a tracked non-UTF-8 name (SKIP-CASE line when the filesystem refuses it); the module exits 1, stderr begins ERROR: git could not untrack 1 path, stdout holds no Files untracked line, .gitignore bytes unchanged, no EVENTS.jsonl, ls-files -s unchanged, and the index file byte for byte as before; a further case sets skip-worktree on docs/ai/STATE.yaml and assume-unchanged on a planned evidence file beside git~1 and ls-files -v and git status stay as before | `sed:s/if \(left.length > 0\) \{/if (false) {/` on .aai/scripts/migrate-state-to-local.mjs | green |
| TEST-3400 | Spec-AC-17 | inspection | tests/skills/test-aai-legacy-migrations.sh | test_3400_line_budget counts code lines with grep -cvE on the comment and blank pattern of each language (hash for sh and ps1, double slash for mjs) under bash with /usr/bin/grep when present: each retirement launcher at most 2, each migrate-state launcher at most 10, the module at most 160 and at most 200 lines in wc -l, the seven-file sum at most 188, and prints before 893 and the after sum | `sed:s/# RETIRED \(RFC-0017 phase 5, retire-legacy-migrations\)/echo a; echo b # RETIRED (RFC-0017 phase 5, retire-legacy-migrations)/` on .aai/scripts/aai-canonicalize.ps1 | green |

Test counts by type: unit 1, integration 11, inspection 7, e2e 4 (23).

Seams crossed (Principle 2): the module to real git in a scratch repository
(TEST-3381 to TEST-3384); each launcher to the module under every shell that
runs it (TEST-3386, TEST-3387, TEST-3388; Windows PowerShell 5.1 and pwsh 7 on
native Windows in H1); aai-doctor's printed command to the script it names
(TEST-3396); aai-sync's profile copy to the target's own launchers (TEST-3395);
the shipped wrapper to the aai-sync retired-wrapper prune of the deleting
release, both engines (TEST-3393, TEST-3394); sync-harness-skills and
generate-docs-hub to the committed mirrors and catalog (TEST-3391); the RFC
inventory read by SPEC-0249's check (TEST-3399); the ledger read by
test-aai-prompt-diet (TEST-3398); select-suites reading the suite map and the
win-fallback derivation reading the workflow (TEST-3397).

### RED observations

- TEST-3380 to TEST-3384, TEST-3396: RED on the baseline, the module does not
  exist (the node wrapper fails on zero passing tests).
  Added in run 2 (additive): the module's whole D1 flow landed in run 1, so
  TEST-3383 and TEST-3384 were green on their first run; their RED is a scratch
  copy of the module with GIT_LITERAL_PATHSPECS set to 0 and with the
  rm.status branch removed (red-TEST-3383.log, red-TEST-3384.log), and the
  mutation records remain the standing proof.
  Added in run 3 (additive): TEST-3396 was green on its first run because the
  old sh copy honours the same doctor contract; its RED is the suite run with
  the fixture's scripts taken from a scratch copy whose module no longer
  untracks STATE.yaml (red-TEST-3396.log; the suite reads the optional
  AAI_LM_SCRIPTS directory for that, unset in every normal run). TEST-3388 went
  RED on the two retirement cases of the Pester file, the four migrate-state
  cases already passing from run 2 (red-TEST-3388.log).
  Added in run 5 (additive): TEST-3395 and TEST-3398 were green on first run
  (the install pieces and the ledger entry landed in runs 1 to 4); their RED is
  the suite run with an optional scratch sync source (AAI_LM_SYNC_SRC, a copy of
  the tracked tree whose PROFILES core list lacks the module) and an optional
  scratch ledger (AAI_LM_LEDGER, amount -11504), both unset in every normal run
  (red-TEST-3395.log, red-TEST-3398.log). TEST-3397 was RED on the missing
  ps1-quality path entries (red-TEST-3397.log). TEST-3395 checks the Spec-AC-02
  effects that survive an install: the four runtime files untracked and on
  disk, .gitkeep tracked, all 16 patterns present, EVENTS.jsonl present; the
  header-and-16-entries append cannot be observed there because aai-sync
  already reconciles the runtime ignore block into the target .gitignore.
  TEST-3397 and TEST-3398 call single functions of test-aai-layer-profiles.sh
  (test_manifest_conformance) and test-aai-prompt-diet.sh (test_010 and test_012)
  instead of the whole suites, because the nested-suite lint of the hygiene
  corpus (test_133, exactly 5 allowlisted rows) refuses a whole-suite run inside
  a suite; the whole suites stay in the Verification list.
  Added in run 6 (additive): TEST-3399 and TEST-3400 were written after their
  edits (the RFC inventory row removal in run 4, the launchers in runs 2 and 3),
  so their RED is the suite run with an optional scratch RFC copy (AAI_LM_RFC,
  the baseline blob) and an optional scratch scripts directory
  (AAI_LM_BUDGET_DIR, the baseline blobs plus the new module), both unset in
  every normal run (red-TEST-3399.log, red-TEST-3400.log).
- TEST-3385: RED (the scripts are 162 and 175 lines and hold the logic).
  TEST-3386: RED (no refusal line; the old sh needs no node). TEST-3387: RED
  (the old sh copy adds 6 ignore entries, not 16).
- TEST-3388: RED (no Pester file). TEST-3389, TEST-3390: RED (the old scripts
  run, need python3 or print no retirement line).
- TEST-3391, TEST-3392: RED (prompt 1950 bytes, wrappers and docs advertise
  the skill). TEST-3393, TEST-3394: RED (the baseline wrapper carries no
  retirement clause; the prune arm alone passes on the baseline wrapper, so
  the mutation record is what proves that arm).
- TEST-3395, TEST-3397 to TEST-3400: RED (no module, entry, row, ledger line,
  RFC sentence; the line budget fails at 893).
  Added in remediation r1 (additive, contract amendment): TEST-3401 was RED on
  the unfixed module (`fatal: '--pathspec-from-file' and pathspec arguments
  cannot be used together`, red-TEST-3401.log); the Pester case for a mistyped
  switch (-DyRun) was RED without `[CmdletBinding()]` (Failed 1 of 7,
  red-TEST-3388-dyrun.log).
  Added in remediation r2 (additive, contract amendment): TEST-3402 was RED on
  the r2 module (git update-index exits 0 and skips git~1; the run printed
  Files untracked and exited 0, red-TEST-3402.log); the non-UTF-8 case is
  skipped with a SKIP-CASE line where the filesystem refuses such names.
  Added in remediation r4 (additive, contract amendment): validation r3 found
  the git reset -q rollback cleared skip-worktree and assume-unchanged bits on
  the planned paths while claiming the index unchanged; TEST-3402 gained a
  flags case and a byte-compare of the index file, RED on f71b52cf
  (red-TEST-3402-r4.log, product_red). The module snapshots the index file
  before the removal and writes it back byte for byte on a surviving path.

## Verification

- `env -u AAI_ROLE bash tests/skills/test-aai-legacy-migrations.sh` exits 0
  (23 rows), plus the touched suites: test-aai-prompt-diet.sh,
  test-aai-layer-profiles.sh, test-aai-expert-fetch.sh, test-aai-hygiene-pack.sh,
  test-aai-validate-skills.sh, test-aai-sync-seed.sh, test-aai-docs-hub.sh,
  test-aai-harness-shims.sh, test-aai-win-fallback.sh. No full sweep is
  required by this spec; Validation decides its own.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell 5.1
  and pwsh 7 with `legacy-migrations.Tests.ps1` discovered and not skipped.

## Evidence contract

ref_id `retire-legacy-migrations`; RED, GREEN and mutation evidence under
`docs/ai/tdd/retire-legacy-migrations/` (gitignored); each AC row's Evidence
names its green log and mutation record; the validation report and review
verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity is proven only on the hosted job (H1);
  Planning had no 5.1 engine.
- A PowerShell 5.1 `-TargetRoot` ending in a backslash and holding a space
  can be mis-quoted by 5.1's native argument passing; `Get-Location` never
  returns such a path except a drive root, which holds no `docs/ai` in
  practice. Not tested.
- `git update-index --force-remove -z --stdin` is old git; the step fails with
  the D1 error and changes nothing when git refuses it. The error line keeps the
  words `git rm --cached` (the effect is the same index removal).
- The retirement relies on the later release deleting the prompt, the
  wrappers and the four launchers; nothing here enforces that. A follow-up is
  filed at delivery under the deletion release.
- Downstream `.codex/skills` and `.gemini/skills` are replaced wholesale by
  aai-sync, so their wrapper copies leave with the source; only the
  `.claude` and `.agents` trees rely on the prune (TEST-3393, TEST-3394).
- The open item `fu-sync-core-profile-dangling-wrappers` (a core-profile sync
  copies wrappers whose extended prompt it does not ship) also applies to the
  aai-canonicalize wrapper; not closed here.
- Accepted at the r4 code review (all P3, none changes an acceptance row):
  - The index restore after a git-skipped path is a non-atomic write that
    ignores `index.lock`; a failed write crashes loudly or truncates the index
    without claiming it unchanged. The concurrent-writer race equals the r3
    reset. NB-r4-2.
  - Sparse-index users untrack evidence that is not on disk. NB-2.
  - `-h` after a second positional argument exits 2 (cosmetic). NB-4.
  - A dry run on a `git~1` or non-UTF-8 evidence name exits 0; the real run
    refuses with rc 1 and changes nothing.
  - With `core.splitIndex`, `splitIndex.maxPercentChange=0` and
    `splitIndex.sharedIndexExpire=now` all set, the index restore can point at an
    expired shared index and still print that the index is unchanged. Tracked as
    `fu-migrate-state-split-index-expire`.

Registry items closed by this scope: none.
