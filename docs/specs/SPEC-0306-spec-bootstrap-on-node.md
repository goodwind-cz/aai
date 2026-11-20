---
id: spec-bootstrap-on-node
type: spec
number: 306
status: done
mutation_gate: v1
frozen_sha256: 17fef3e71ed4a9e7ec39985807a873e8e341e8d15528a1713bd58736d87df192
ceremony_level: 2
links:
  requirement: bootstrap-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Run the project bootstrap as one Node module behind thin launchers

SPEC-FROZEN: true

## Links

- Requirement: [Run the project bootstrap as one Node module behind thin launchers](../issues/CHANGE-0261-bootstrap-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 9 (owner sign-off: yes; merge by the owner). Plan section 4 decision 1
  applies: Node is a hard prerequisite on the install path; launchers refuse
  without Node and print an install hint.
- Pattern precedents: [SPEC-0267](SPEC-0267-spec-node-first-reap-tests.md)
  (one module, thin launchers, recorded re-homes of other specs' tests with
  amendment records), [SPEC-0284](SPEC-0284-spec-install-path-parity-harness.md)
  (the parity harness this ride plugs into as a third twin),
  [SPEC-0283](SPEC-0283-spec-hook-gate-on-node.md) (`run_node_tests`,
  `need_tool`, a differential corpus, wiring named up front) and
  [SPEC-0281](SPEC-0281-spec-release-on-node.md).
- Specs whose tests this ride re-homes (D-REHOME): SPEC-0029
  (hook-enforced gates), SPEC-0157 (gitignore drift reconcile), SPEC-0265
  (node-first small pairs), SPEC-0284 (install-path parity harness).
- Shared code read but not changed: `.aai/scripts/platform.mjs`,
  `.aai/scripts/lib/platform-adapter.mjs`,
  `.aai/scripts/lib/merge-hooks-json.mjs`, `.aai/scripts/lib/gitignore-block.sh`
  (still used by the sync twins), `.aai/system/RUNTIME_IGNORE.list` (data
  lines unchanged; header text changes, D-DOCS).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 compatible suites, Pester 5, Windows PowerShell 5.1 and pwsh 7).
- Baseline: main `34fad51b`.

## Implementation strategy

- Strategy: tdd
- Rationale: owner requirement for every Node-first ride: TDD in runs of
  about three Spec-ACs. The port must be byte-equivalent to a 920-line bash
  script whose behaviour was never unit-tested; a rule port that was never
  seen failing proves nothing, so every rule test is RED before the module
  exists, the differential corpus is RED until the last rendering byte
  matches, and every Test Plan row carries a mutation (mutation_gate v1).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: a new module, two launchers, a frozen reference copy,
  re-homed assertions in five existing suites, CI path filters and PROFILES;
  the main checkout is shared with other sessions and holds unrelated
  uncommitted files.
- User decision: worktree (owner-directed own worktree, recorded in STATE
  with rationale "owner-directed own worktree"; not an autopilot default)
- Base ref: main
- Worktree branch/path: feat/bootstrap-node at /Users/ales/Projects/aai-worktrees/bootstrap-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/aai-bootstrap.mjs .aai/scripts/aai-bootstrap.sh
  .aai/scripts/aai-bootstrap.ps1 .aai/scripts/validate-skills.mjs
  .aai/system/PROFILES.yaml .aai/system/RUNTIME_IGNORE.list
  .aai/system/DYNAMIC_SKILLS.md .aai/SKILL_BOOTSTRAP.prompt.md
  tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh
  tests/skills/lib/bootstrap-reference.mjs tests/skills/lib/aai-bootstrap.test.mjs
  tests/skills/test-aai-bootstrap-node.sh tests/skills/aai-bootstrap.Tests.ps1
  tests/skills/lib/install-parity.mjs tests/skills/lib/install-parity.test.mjs
  tests/skills/lib/install-parity-allowlist.tsv tests/skills/test-aai-install-parity.sh
  tests/skills/test-aai-bootstrap.sh tests/skills/test-aai-hooks-overlay.sh
  tests/skills/test-aai-sync-seed.sh tests/skills/test-aai-validate-skills.sh
  tests/skills/lib/validate-skills.test.mjs tests/skills/validate-skills.Tests.ps1
  tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
  tests/skills/suite-map.yaml tests/skills/suite-weights.tsv
  tests/skills/test-aai-hygiene-pack.sh tests/skills/lib/cd-subshell-leak-baseline.tsv
  .github/workflows/ps1-quality.yml CHANGELOG.md
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl docs/issues/CHANGE-0261-bootstrap-on-node.md
  docs/specs/SPEC-0306-spec-bootstrap-on-node.md docs/INDEX.md
  tests/skills/lib/aai-bootstrap-fixtures.mjs tests/skills/lib/aai-bootstrap-golden.json
  tests/skills/test-aai-pr-preflight.sh tests/skills/test-aai-suite-reuse.sh
  (decisions.jsonl only for the amendment and follow-up records; the
  allocator renames the two DRAFT files at merge).
- Code review required: true.

## Ceremony

- Level 2: production scripts, tests, one CI workflow path filter, one prompt
  and docs; no file in `protected_paths_l3` (docs/ai/docs-audit.yaml) is
  touched.
- Suite selection: the wiring files select many suites; Validation runs the
  selected suites between runs and the full sweep once before close
  (`AAI_TEST_TIMEOUT=3000`).

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 3.2.57, Node 22.23.1, pwsh
7.6.3) on 2026-11-20 at `34fad51b`, scratch fixtures under the session
scratchpad. One run each; they size the work, they are not thresholds.

- `.aai/scripts/aai-bootstrap.sh`: 1133 lines, 920 code lines
  (`grep -cvE '^[[:space:]]*(#|$)'`), mode 100755, git blob
  `b41a0c02d61711528c5b85680346f62ea23860c3`, sha256
  `19055401a8854ead8233d75a8b788851a5535d4d95fd7aff31fa14b56bf661c0`.
- Run time of the bash script: 0.16 s on an empty directory, 0.47 s on the
  `test-aai-bootstrap.sh` fixture (eight evidence files); `pwsh -NoProfile`
  start-up 0.26 s.
- Root resolution: from a symlinked directory the bash script records the
  logical path (`.../link2`), while `process.cwd()` in Node returns the
  physical one (`.../real2`) and the environment's `PWD` holds the logical
  one. `link2/../empty` resolves lexically to `.../empty`.
- Argument handling: a nonexistent target exits 1 (bash's `cd` error on
  stderr); `--bogus` is taken as the target and exits 1 (`cd: --: invalid
  option` under bash 3.2); a second positional argument prints
  `ERROR: unexpected argument: b` plus the usage and exits 2; `-h` prints the
  script's lines 2 to 16 with the comment marks removed, so its first line is
  `set -euo pipefail`, and exits 0.
- A directory named `My Proj--X` holding only a Dockerfile yields
  `docker build -t my-proj-x- .` (the newline that `basename` prints becomes
  the trailing dash, `tr -s` folds `--`).
- `--dry-run` on a target without `.gitignore` lists only
  `[dry-run] .gitignore` for it (no pattern lines); a fresh run seeds the
  three cache patterns, each after a blank line, then 30 runtime patterns
  under the marker line (`.aai/system/RUNTIME_IGNORE.list` holds 30
  non-comment lines).
- No `rg` on bash's PATH on the planning host, so the bash script took its
  `grep -R` branch for the auth search; the CI images were not checked.
- The platform record on a target without `origin` prints
  `RECORDED platform=none (new file)` and `AUTH none skipped` and starts no
  `gh` or `az`.
- Children: `merge-hooks-json.mjs` writes its summary to stdout on success
  and only to stderr on failure; `platform.mjs record` writes its two lines
  to stdout and errors only to stderr. Concatenating a child's stdout and
  then its stderr therefore equals the bash `2>&1` capture on every outcome.
- CI: `.github/workflows/ps1-quality.yml` checks out without `fetch-depth`
  (depth 1); `skill-suite.yml` uses `fetch-depth: 0`. Last green
  ps1-quality run (44757602683): full Pester discovery 403.5 s under Windows
  PowerShell 5.1 and 381.9 s under pwsh 7 against the 600 s ceiling, 211
  passed and 4 skipped each; the `windows-parity` job 248.9 s and 236.8 s
  against its 10-minute steps.
- Callers and pins of `aai-bootstrap.sh` outside docs history: the prompt
  `SKILL_BOOTSTRAP.prompt.md`, `DYNAMIC_SKILLS.md`, PROFILES core,
  `validate-skills.mjs` REQUIRED (mirrored in three tests),
  `RUNTIME_IGNORE.list` header, suite-map rows `aai-bootstrap` and
  `aai-hooks-overlay`, `cd-subshell-leak-baseline.tsv` (3),
  `suite-weights.tsv` (6 s), and behaviour runs in `test-aai-bootstrap.sh`,
  `test-aai-hooks-overlay.sh` (TEST-010, TEST-011), `test-aai-sync-seed.sh`
  (TEST-011, 013, 016, 019, 020, 787, 823) and `test-aai-run-tests.sh`.
- `tests/skills/suite-map.yaml` holds 137 rows (hygiene test_090 pins 137);
  the highest Test Plan id in docs/specs is TEST-3935.

## Decisions

### D-MODULE. `.aai/scripts/aai-bootstrap.mjs`

Dependency-free ESM, Node 22 compatible, imports only `node:` specifiers,
ASCII only, no side effect on import (the main guard compares
`realpathSync` of `process.argv[1]` and of the module, as aai-live.mjs does),
never reads standard input. It holds all bootstrap policy: argument parsing,
root resolution, detection, command choice, the auth search, the skill plan,
rendering, the managed-file preflight, writes, the `.gitignore` cache and
runtime-sidecar blocks, the hooks overlay, the platform record relay, the
summary and the exit code. It starts child processes only as
`spawnSync(process.execPath, [script, ...args], ...)` for
`lib/merge-hooks-json.mjs` and `platform.mjs` (both resolved next to the
module, both with `cwd` the root); it starts no shell, no `git`, no
`docker`, no `gh`, no `az`.

Exports at least: `parseArgs`, `resolveRoot`, `detect`, `chooseCommands`,
`dockerTag`, `detectAuth`, `planSkills`, `wrapTestCommand`, `renderSkill`,
`renderMarker`, `renderIndex`, `renderSummary`, `isManagedFile`,
`preflight`, `writeOutputs`, `ensureGitignore`, `seedRuntimeGitignore`,
`installClaudeHooks`, `recordGitPlatform`, `run`, `main`. Pure where the
rule allows; filesystem readers take the root as an argument; `run` takes
injectable `out`, `err`, `now`, `env`, `cwd` and `spawn`.

It contains these exact lines, each once, and no comment repeats one (the
Test Plan mutations rely on them):

```js
const GENERATOR = '.aai/scripts/aai-bootstrap.sh';
const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:START';
const FILE_MARKER = 'AAI-DYNAMIC-FILE:START';
const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars';
const RUNTIME_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';
const CACHE_PATTERNS = ['.claude/skills/.cache', '.codex/skills.local/.cache', '.gemini/skills.local/.cache'];
const LOCKFILES = [['pnpm-lock.yaml', 'pnpm'], ['yarn.lock', 'yarn'], ['bun.lock', 'bun'], ['bun.lockb', 'bun']];
const AUTH_SKIP_DIRS = ['node_modules', '.git', 'dist', 'build'];
const HOOKS_UNCHANGED = '0 hook(s) added, 0 updated';
const PLATFORM_MISMATCH = 6;
const EXIT_HOOKS_REFUSED = 3;
const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;
const sameContent = (a, b) => stripTrailingNewlines(a) === stripTrailingNewlines(b);
  if (pm === 'npm' && script === 'test') return 'npm test';
const runChild = (script, args, cwd) => spawnSync(process.execPath, [script, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
```

`GENERATOR` keeps the `.sh` name on purpose: generated files name it and
`isManagedFile` matches it, so every existing install stays managed (D-WRITE).
`seedRuntimeGitignore` is exported so that ride 12 (sync on Node) can reuse
the one Node implementation of the runtime-sidecar reconcile instead of
writing a second one.

### D-CLI. Arguments, help, exit codes

- Arguments are read left to right, as the bash loop does: `--dry-run`,
  `--force` and `--with-claude-hooks` set their mode in any position; `-h` or
  `--help` prints the help text to stdout and exits 0 at that position; any
  other argument is the target when none is set yet, otherwise the module
  prints `ERROR: unexpected argument: <arg>` and then the help text to
  stderr and exits 2 at that position. An unknown flag such as `--bogus` is
  therefore a target (kept for parity).
- Help text (DR-1): the reference's help output without its first two lines
  (`set -euo pipefail` and the empty line), with one line added right after
  the `./.aai/scripts/aai-bootstrap.sh ...` usage line:
  `  powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]`.
- A target that names no directory (missing, a file, or an unknown flag)
  exits 1 with one stderr line `aai-bootstrap: target not found: <arg>` and
  writes nothing (DR-2: same exit as bash, different stderr text).
- Exit codes: 0 done; 1 conflict refusal (D-WRITE) or bad target; 2 usage;
  3 an explicitly requested hooks overlay that delivered nothing (D-HOOKS);
  an uncaught I/O error during writes ends the process with Node's exit 1
  after the writes before it, as `set -e` does in bash.

### D-ROOT. Root resolution (DR-6)

Base directory: the environment's `PWD` when it is absolute and `samePlace`
(device and inode) holds between it and the process working directory,
else `process.cwd()`. This is bash's own rule for trusting `PWD` at start-up,
so the module reports the logical path where bash does, including through
the `.sh` launcher (`exec node` keeps the validated `PWD`), and the physical
path where a parent left a stale `PWD`. With a target: `path.resolve(base,
target)` (lexical, as bash's logical `cd`). `CDPATH` is ignored (bash honours
it for a relative target and its echo corrupts `ROOT`). All target paths in
output use the resolved root; every child runs with `cwd` the root and the
same relative arguments bash passes (`.aai/templates/hooks/settings-hooks.json`,
`.claude/settings.json`).

### D-DETECT, D-CHOOSE, D-AUTH, D-PLAN. The rules (slice a)

Ported one to one from the reference; each rule has its own node:test case
with a positive and a negative fixture (TEST-3943 to TEST-3945):

- Package manager only when `package.json` is a file: `LOCKFILES` in order,
  else npm; label `<pm> (package.json)`. package.json queries (script, the
  four dependency buckets, top-level key) parse JSON in process; a parse
  failure or a non-object answers false (DR-3: the bash grep fallback for a
  missing node is unreachable and gone).
- Languages and managers: JavaScript/TypeScript (+ `package.json
  workspaces` build tool when the key exists); Python from any of
  pyproject.toml, requirements.txt, poetry.lock, uv.lock, setup.cfg,
  setup.py with poetry, then uv, then `pip/python (python manifest)`; Go,
  Rust, Java (maven), Java/Kotlin (gradle from build.gradle, build.gradle.kts
  or gradlew).
- Tools: Playwright, Cypress, Jest, Vite, Webpack by `<name>.config.*` in the
  root (any entry kind, case-sensitive name match); Vitest by config or
  dependency (also sets the Vitest guidance); pytest by pytest.ini or
  tox.ini; `test directory` by `tests/` or `test/`; TypeScript, Dockerfile,
  Docker Compose (docker-compose.yml or compose.yml), Makefile (Makefile or
  makefile), justfile (justfile or Justfile); ESLint config (`.eslintrc*` or
  eslint.config.js, .mjs, .cjs, listed once), Biome, Ruff, `Python lint
  config (pyproject.toml)` when pyproject.toml holds `[tool.ruff]`,
  `[tool.flake8]` or `[tool.black]`; CI `.github/workflows`; deploy
  Cloudflare Wrangler, Vercel, Netlify. Lists keep first-seen order without
  duplicates.
- Task runners: for each target name in order, justfile (regex
  `^[[:space:]]*<t>([[:space:]].*)?:` per line) before Makefile
  (`^[[:space:]]*<t>[[:space:]]*:`); `just <t>` or `make <t>`. Script
  commands: `npm test` for npm's test script, `npm run <s>`, `pnpm run`,
  `yarn run`, `bun run`; exec commands `npx`, `pnpm exec`, `yarn exec`,
  `bunx`.
- Command chains, each in the reference's order: unit (runner test-unit,
  unit, test; scripts test:unit, unit, test; vitest run; jest; pytest when
  pytest.ini exists or the substring `pytest` occurs in pyproject.toml,
  requirements.txt, setup.cfg or tox.ini; go test; cargo test; mvn test;
  ./gradlew test; gradle test), e2e (gated on a Playwright or Cypress config
  or a `test:e2e` or `e2e` script; runner test-e2e, e2e, test_e2e; scripts
  test:e2e, e2e, playwright, cypress:run, cy:run; playwright test; cypress
  run), build (runner build, compile; scripts build, compile; vite build;
  webpack; `tsc --noEmit` when tsconfig.json and the typescript dependency;
  go build; cargo build; mvn package; ./gradlew build; gradle build; docker
  build), lint (runner lint, check, lint-check; scripts lint, check,
  typecheck; `eslint .`; `biome check .`; `ruff check .` when ruff.toml or
  the substring `ruff` in pyproject.toml or requirements.txt; `flake8`;
  `go vet ./...`; `cargo clippy --all-targets --all-features`), monty (any
  Python manifest), deploy (runner deploy, publish, release; same scripts;
  wrangler, vercel, netlify deploy). A substring search over a path that is
  a directory searches the files below it, as `grep -R` does.
- `dockerTag(root)`: the root's basename, ASCII A to Z lowered, a newline
  appended, every character outside `a-z0-9_.-` replaced by `-`, runs of
  `-` folded to one (kept for parity: the trailing `-`).
- Auth (D-AUTH, DR-5): only when an e2e command exists; candidate paths app,
  src, pages, components, routes, tests, e2e, cypress, package.json, then
  middleware.ts, middleware.js and the Playwright and Cypress configs, each
  when it exists. Search: regular files read as latin1, directories walked
  recursively following symlinks (each real directory once), directories
  named in `AUTH_SKIP_DIRS` skipped at any depth, hidden files searched,
  `.gitignore` not consulted; case-insensitive match of the reference's
  alternation (login, sign-in, auth, session, jwt, passport, next-auth,
  clerk, requireAuth, withAuth, storageState, globalSetup). The bash script
  uses `rg` when it is installed (hidden files and gitignored paths skipped)
  and `grep -R` otherwise (no skipped directories); the module's rule equals
  both wherever no signal lies only in a skipped directory, a hidden file or
  a gitignored path. Credential reference: `docs/knowledge/FACTS.md` with a
  `## Test Credentials` line, else the first of .env.e2e, .env.test,
  .env.testing whose lines match
  `^(TEST|E2E|PLAYWRIGHT|CYPRESS|AUTH|LOGIN).*(_USER|_EMAIL|_PASSWORD|_PASS|_TOKEN)=`
  (names before the first `=`, joined by `, `). Session line by a
  globalSetup or storageState match over the same paths.
- Plan (D-PLAN): skills in the order aai-test-unit, aai-test-e2e, aai-build,
  aai-lint, aai-python-monty, aai-deploy with the reference's descriptions;
  unit and e2e commands wrapped by `wrapTestCommand` (the two-line
  Windows/POSIX form); the Vitest guidance block, the e2e Prerequisites
  block and the Monty block byte for byte; the five skipped messages
  (deploy has none).

### D-RENDER, D-WRITE, D-GITIGNORE. Rendering and writes (slice b)

- Rendering: the skill file, the marker file, the two index files and the
  summary are byte-identical to the reference for the same inputs, including
  the empty-line placement around an empty extra block, the `- None`, `- None
  generated`, `Not detected` and `No ... detected` fallbacks, the CI/CD
  section that joins CI and deploy, the fence rule (empty fence when the
  command holds a newline or `aai-run-tests.ps1`, else `bash`) and the
  one-line display form (newline replaced by ` / `). The run timestamp is
  read once per run, UTC, to the second.
- Managed-file rule: a missing path is managed; an existing one is managed
  when it matches any of `AAI-DYNAMIC-SKILL:START`, `AAI-DYNAMIC-FILE:START`,
  `Generated by: .aai/scripts/aai-bootstrap.sh` (dots match any character,
  as in the reference's basic regex), `generated by aai-bootstrap`, `AAI
  Dynamic Skills`. Preflight checks every planned skill path, the marker and
  both index files; without `--force` an unmanaged regular file is a
  conflict. Conflicts print `ERROR: bootstrap would overwrite unmarked
  files.`, one `- <path> exists and is not marked as AAI-generated; rerun
  with --force to replace it` line each and `Rerun with --force only if
  replacing these files is intentional.` to stderr, exit 1, before any write.
- Writes: a file whose content equals the new content after both lose their
  trailing newlines is unchanged (listed under Unchanged files, even in
  dry-run); otherwise dry-run lists `[dry-run] <path>`, a real run creates
  the parent directories and writes the content plus one newline. Order:
  skills, marker, Codex index, Gemini index, `.gitignore`.
- `.gitignore`: a missing file is listed as `[dry-run] .gitignore` and
  nothing else in dry-run, or created empty; then each of `CACHE_PATTERNS`
  not present as an exact line (no carriage-return stripping, kept for
  parity) is appended after a blank line (`[dry-run] .gitignore add <p>` or
  `.gitignore add <p>`); then `seedRuntimeGitignore('.gitignore',
  <module dir>/../system/RUNTIME_IGNORE.list, RUNTIME_MARKER, dryRun)` ports
  `aai_gitignore_seed_runtime`: list lines split on LF with any carriage
  return kept (parity), blank and `#` lines skipped; a pattern is present
  when an exact line of the target with every carriage return removed equals
  it; nothing missing prints nothing; dry-run prints `[dry-run] .gitignore
  add <n> AAI runtime sidecar pattern(s)`; a real run appends a blank line,
  the marker only when no line starts with `RUNTIME_MARKER_PREFIX`, and the
  missing patterns, then lists `.gitignore add <n> AAI runtime sidecar
  pattern(s)`; a missing list prints `skipped runtime-sidecar gitignore
  seed: <list path> missing` and writes nothing. The module does not read or
  need `lib/gitignore-block.sh` (DR-4).

### D-HOOKS, D-PLATFORM. Overlay and platform record (slice c)

- Hooks overlay only with `--with-claude-hooks`, after the writes: template
  `.aai/templates/hooks/settings-hooks.json` missing in the root prints the
  reference's WARN line and continues with exit 0; merge library missing
  next to the module prints the reference's `ERROR: hooks merge library not
  found (<lib path>) ...` line to stderr and the run ends with exit 3 after
  the summary; dry-run lists `[dry-run] .claude/settings.json (merge AAI
  hooks overlay from <tpl>)`; otherwise create `.claude/`, run the library
  with the relative template and destination, print `  hooks overlay:
  <output>` on success (listed unchanged when the output holds
  `HOOKS_UNCHANGED`, else merged) and on failure the two reference ERROR
  lines to stderr and exit 3 after the summary. The reference's `WARN: node
  unavailable` branch is gone (DR-3).
- Platform record after the overlay: `platform.mjs record --repo-root <root>`
  (plus `--dry-run`); the relayed text is the child's stdout then stderr
  with trailing newlines removed; exit codes 0 and `PLATFORM_MISMATCH` relay
  the text as is, any other code relays `platform record failed (exit <n>):
  <text>`; the run never aborts on it. The reference's `node unavailable`
  line is gone (DR-3).

### D-DRIFT. Every difference from the reference, each with a node:test

| Id | Reference | Module | Why | Test |
|---|---|---|---|---|
| DR-1 | `-h` prints `set -euo pipefail`, an empty line, then the comment block | the comment block plus the PowerShell usage line | the reference prints its own source line by accident; a Node module has no such line | TEST-3942 |
| DR-2 | a bad target prints bash's `line 76: cd:` error | prints `aai-bootstrap: target not found: <arg>`; exit 1 in both | bash's message names a script line; DR-11 covers the three `cd`-option targets the reference accepts | TEST-3942 |
| DR-3 | three branches for a missing node (package.json grep fallback, hooks WARN, platform line) | absent | Node runs the module, so node exists | TEST-3941 |
| DR-4 | with `lib/gitignore-block.sh` missing it prints a skip note and seeds no runtime pattern | seeds from the list; the library is not a dependency | the Node reconcile is the module's own | TEST-3948 |
| DR-5 | auth search by `rg` (skips hidden and gitignored paths) or `grep -R` (skips nothing), host-dependent | one walk: skips node_modules, .git, dist, build; searches hidden files; ignores .gitignore | one deterministic rule on every host | TEST-3945 |
| DR-6 | `CDPATH` applies to a relative target | `CDPATH` ignored; logical root by the PWD rule | the bash behaviour corrupts the root | TEST-3942 |
| DR-7 | a NUL byte in an existing generated file is dropped by `$(cat)` before the unchanged check | compared as read; the file is rewritten | Node strings keep NUL | TEST-3947 |
| DR-8 | script-dir paths in messages are logical; a missing `../system` gives `/RUNTIME_IGNORE.list` | module dir as Node resolves it; the full expected list path | Node resolves the main module through symlinks | TEST-3948 |
| DR-9 | on Windows (Git Bash) the marker records `Target root: /c/...` | records the native path `C:\...` | the native path is what a Windows bootstrap should record; one allowlist row (D-PARITY) | TEST-3956 |
| DR-10 | an `.env.*` file without a matching credential name makes the `grep` into `cut` pipeline fail under pipefail: silent exit 1, empty stdout and stderr, nothing written (corpus K19) | the file is skipped as D-AUTH says and the run completes, exit 0 | the reference aborts by accident, not by policy; K19 stays in the corpus as an asserted divergence and K19b (K19 without that file) is byte-equal | TEST-3949 |
| DR-11 | a target of `--`, `-P` or `-L` is taken by `cd` as an option, so the reference changes to HOME and bootstraps HOME (exit 0) | the target is resolved as a path name; these three name no directory, so the module exits 1 with `aai-bootstrap: target not found: <target>` and writes nothing | the reference behaviour is an accident of `cd` option parsing that bootstraps an unintended directory; refusing is safer | TEST-3942 |

Kept for parity, pinned as rules and not drifts: the docker tag's trailing
dash, `GENERATOR` dots matching any character, cache patterns compared
without carriage-return stripping, list lines keeping a carriage return,
dry-run listing only `.gitignore` when it is missing, unknown flags read as
the target, generated files naming `aai-bootstrap.sh` on Windows too. Each
gets a suggested follow-up (D-FU), not a fix: the reference is frozen, so a
fix would be an allowlisted divergence.

### D-LAUNCH. Launchers

- `.aai/scripts/aai-bootstrap.sh`: at most 20 lines, ASCII, `#!/bin/sh`,
  POSIX only (runs under `sh`, `dash` and `bash`), mode 100755:

  ```sh
  #!/bin/sh
  # Project bootstrap launcher; detection, rendering and write policy live in aai-bootstrap.mjs (RFC-0017 phase 5).
  # Usage: ./.aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force] [--with-claude-hooks]
  MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-bootstrap.mjs"
  if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
    exec node "$MODULE" "$@"
  fi
  echo "aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
  exit 1
  ```

- `.aai/scripts/aai-bootstrap.ps1`: at most 20 lines, ASCII, no param block
  (so every argument, dashed or not, reaches `$args` as a string), 5.1 and 7
  compatible:

  ```powershell
  # Project bootstrap launcher; detection, rendering and write policy live in aai-bootstrap.mjs (RFC-0017 phase 5).
  # Usage: powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]
  $Module = Join-Path $PSScriptRoot 'aai-bootstrap.mjs'
  if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
    & node $Module @args
    exit $LASTEXITCODE
  }
  [Console]::Error.WriteLine('aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
  exit 1
  ```

- Neither launcher names a detection file, a skill name, a marker, a
  `.gitignore` pattern, the hooks template or the platform record. Exit 1
  for the refusal follows the five existing Node-first launchers; the stderr
  line, not the code, tells it from a conflict.

### D-REF. The bash reference stays runnable as a frozen copy

`tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh` is a byte copy of
blob `b41a0c02` (sha256 `19055401...`, mode 100755, LF by the existing
`*.sh text eol=lf` rule). `tests/skills/lib/bootstrap-reference.mjs` exports
`REFERENCE_PATH`, `REFERENCE_SHA256`, `REFERENCE_BLOB` and
`materializeBootstrapReference(fromRoot, intoRoot)`: it verifies the sha256
(a mismatch throws, naming the file), copies `<fromRoot>/.aai` to
`<intoRoot>/.aai`, then writes the reference over
`<intoRoot>/.aai/scripts/aai-bootstrap.sh` with mode 0755. In that tree the
reference finds the same siblings it found in place (`lib/`, `platform.mjs`,
`../system/RUNTIME_IGNORE.list`) and sits next to the module and the `.ps1`
launcher, so all three entry points run from one tree and print the same
script-dir paths.

Why a committed copy and not `git show <pinned sha>:...`: (1) ps1-quality
checks out at depth 1, so the `windows-parity` job, the one place the
reference runs under native Windows, has no history to show from; (2) the
harness's scratch source and any shallow or exported checkout have none
either; (3) a sha256 pin makes an edit to the copy fail loudly, which
`git show` gives only while the object exists. Where history is present
(skill-suite, `fetch-depth: 0`) TEST-3940 also requires the copy to equal
`git show 34fad51b:.aai/scripts/aai-bootstrap.sh`. The copy lives outside
`.aai/` (never vendored) and outside `tests/skills` and `.aai/scripts` (the
cd-subshell and pipe-grep ratchets' scan directories). Lifetime: a later
ride that changes bootstrap output on purpose retires the bootstrap
scenarios and the copy, or adds reviewed allowlist rows; this spec does not
freeze bootstrap behaviour forever.

### D-CORPUS. The differential corpus (stdout, stderr, exit and tree)

In `tests/skills/lib/aai-bootstrap.test.mjs` (POSIX hosts; it needs bash).
Each case builds its fixture twice at the same absolute path under one
`mkdtemp` scratch root (the first side's tree renamed away before the second
is laid down), materializes one reference tree from the checkout
(D-REF) and runs `bash <tree>/.aai/scripts/aai-bootstrap.sh <target> <args>`
and `node <tree>/.aai/scripts/aai-bootstrap.mjs <target> <args>` with cwd
the target, the caller's environment minus every `AAI_` variable,
`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL` an empty scratch file, and a
scratch stub directory first on PATH holding `docker`, `gh` and `az` stubs
that append their argv to a scratch log and exit 0. Two-step cases wait for
the next wall-clock second between steps on both sides. Compared: exit code,
stdout bytes, stderr bytes, and the trees through the harness's
`snapshotNormalized` and `compareSnapshots` (N5 included, `.git/` excluded).
After every case the stub log holds no `docker` line, and `gh` or `az` lines
only for K35 to K37.

Fixtures (at least these; each a `git init` repository with its own
identity unless it says otherwise):

- K01 the `test-aai-bootstrap.sh` fixture (npm scripts test, test:e2e,
  build, lint; jest, playwright, vite, eslint configs; pyproject.toml with
  ruff and pydantic-monty; app/login.ts with requireAuth; .env.e2e; e2e/);
  K02 the same with `--dry-run`.
- K03 an empty directory that is not a repository, run with no target from
  cwd; K04 an empty repository, two steps (the second lists Unchanged files).
- K05 yarn.lock, workspaces, jest dependency only, webpack.config.js,
  .eslintrc.json, netlify.toml, tests/; K06 pnpm-lock.yaml, vitest and
  typescript dependencies, tsconfig.json, biome.json, vercel.json, scripts
  test:unit and deploy; K07 bun.lockb, cypress.config.ts, script cy:run,
  @biomejs/biome, app/session.ts, cypress/support.ts with storageState; K08
  bun.lock with scripts e2e, check, compile and no config.
- K09 poetry.lock, pyproject.toml with `[tool.black]` and the word pytest,
  requirements.txt with flake8; K10 uv.lock, setup.cfg naming pytest,
  ruff.toml, tox.ini; K11 setup.py and requirements.txt naming ruff.
- K12 go.mod, Makefile with test, build and lint targets, justfile with a
  `deploy env:` recipe, .github/workflows/ci.yml; K13 Cargo.toml and a
  Justfile with test-unit and release recipes.
- K14 pom.xml, Dockerfile, docker-compose.yml, wrangler.toml in a directory
  named `My Proj--X`; K15 only a Dockerfile and compose.yml in `My Proj--X`.
- K16 gradlew, build.gradle.kts, tests/; K17 build.gradle, test/.
- K18 docs/knowledge/FACTS.md with `## Test Credentials`, playwright.config.ts
  with globalSetup, @playwright/test dependency, e2e/; K19 .env.test without
  matching names, .env.testing with TEST_USER, AUTH_TOKEN and OTHER,
  playwright config, app/ with login.
- K20 package.json that is not JSON plus a Makefile with a unit target.
- K21 K01 plus an unmarked .claude/skills/aai-test-unit/SKILL.md and an
  unmarked .codex/skills.local/README.md (exit 1, nothing written); K22 the
  same with `--force`; K23 an existing aai-build skill holding only
  `Generated by: Xaai/scripts/aai-bootstrapYsh` and a Gemini index holding
  `AAI Dynamic Skills` (managed, no conflict).
- K24 a CRLF .gitignore holding `.claude/skills/.cache`, `docs/ai/STATE.yaml`
  and a legacy `# AAI runtime sidecars (seeded from ...)` line; K25 a
  .gitignore `node_modules/` without a final newline; K26 `--dry-run` over a
  target with a .gitignore lacking every pattern and an unchanged generated
  skill; K27 generated files that carry extra trailing newlines.
- K28 to K34 (slice c, hooks): template copied into the root and no
  settings.json, two steps (merged, then unchanged); foreign permissions and
  a foreign SessionStart hook; `NOT JSON {` (exit 3); `{"hooks": []}` (exit
  3); template missing (WARN, exit 0); merge library removed from the tree
  copy (exit 3, the ERROR names merge-hooks-json.mjs); `--dry-run`.
- K35 to K37 (slice c, platform): an Azure origin (stub az) recorded; a
  pre-seeded `platform: azure` with a GitHub origin (stub gh) relayed as
  MISMATCH with exit 0 and the file unchanged; an Azure origin with
  `--dry-run` (WOULD-RECORD, no file).
- K38 vitest.config.ts with npm and no scripts (`npx vitest run` plus the
  guidance block).

Masked mode (Spec-AC-10, the slice b gate): the `Git platform:` block is
cut from both stdouts, `docs/ai/pr-config.yaml` from both trees, and K28 to
K37 are not run. Full mode (Spec-AC-13): nothing is cut and every case runs.

### D-PARITY. The parity harness takes bootstrap as an operation

Changes to `tests/skills/lib/install-parity.mjs` (SPEC-0284's driver):

- `TWINS.node = { name: 'node', ops: ['bootstrap'], argv }`; a twin with
  `ops` runs only on scenarios whose op it lists; `runScenario` filters with
  `!t.ops` or `t.ops.includes(scenario.op)`; a module twin without `ops`
  runs everywhere, as before; the default `--twins` stays every registered
  twin.
- Bootstrap argv, cwd the target, flags `force`, `dry-run`,
  `with-claude-hooks` mapped to `--force`, `--dry-run`,
  `--with-claude-hooks`: sh `bash <bsref>/.aai/scripts/aai-bootstrap.sh
  <target>` (the frozen reference, forward-slash paths), ps1 `<ps>
  -NoProfile -NonInteractive [-ExecutionPolicy Bypass] -File
  <bsref>/.aai/scripts/aai-bootstrap.ps1 <target>` (the PowerShell launcher,
  so the native Windows legs prove it against the reference), node
  `process.execPath <bsref>/.aai/scripts/aai-bootstrap.mjs <target>`, with
  the exact line `args: [path.join(ctx.bsref, '.aai', 'scripts', 'aai-bootstrap.mjs'), ctx.target, ...bsFlags(step)],`.
- `ctx.bsref`: built once per run, when a selected scenario has op
  bootstrap, by `materializeBootstrapReference(src, <root>/bsref)`; passed to
  every twin's argv (module twins too).
- Normalization N5 (added to `NORMALIZATIONS` with its reason "wall clock:
  the bootstrap run timestamp NOW_UTC"): in exactly the paths of
  `const BOOTSTRAP_STAMPED = ['.claude/skills/AAI_DYNAMIC_SKILLS.md', '.codex/skills.local/README.md', '.gemini/skills.local/README.md'];`
  the line `- Generated at (UTC): YYYY-MM-DDTHH:MM:SSZ` (marker) or
  `Generated at (UTC): YYYY-MM-DDTHH:MM:SSZ` (indexes), second precision
  only, becomes `<stamp>`. This is the one normalization the timestamp gets;
  the corpus uses it through the same functions.
- Setups `bs-polyglot` (K01's files), `bs-empty`, `bs-unmarked` (bs-polyglot
  plus an unmarked aai-test-unit skill), `bs-hooks` (template copied from
  the source plus a settings.json with a foreign permissions key),
  `bs-hooks-invalid` (settings.json `NOT JSON {`), `bs-multi` (go.mod,
  Cargo.toml, Makefile with test, build and lint, justfile with deploy,
  Dockerfile, wrangler.toml, .github/workflows/ci.yml, a CRLF .gitignore with
  `.claude/skills/.cache` and `docs/ai/STATE.yaml`), `bs-vitest`
  (pnpm-lock.yaml, vitest and typescript dependencies, tsconfig.json,
  biome.json). Every bootstrap target is a git repository without origin.

Bootstrap scenarios, appended after SPEC-0284's rows in `SCENARIOS`:

| ID | Tier | Op | Setup | Steps | Expect | Probes |
|---|---|---|---|---|---|---|
| BS-01 | smoke | bootstrap | bs-polyglot at `BS-01/target with space` | bootstrap | 0 | .claude/skills/AAI_DYNAMIC_SKILLS.md, .claude/skills/aai-test-e2e/SKILL.md, docs/ai/pr-config.yaml |
| BS-02 | smoke | bootstrap | bs-unmarked | bootstrap | nonzero | .claude/skills/aai-test-unit/SKILL.md |
| BS-03 | default | bootstrap | bs-empty | bootstrap; bootstrap | 0, 0 | .gitignore, .claude/skills/AAI_DYNAMIC_SKILLS.md |
| BS-04 | default | bootstrap | bs-unmarked | bootstrap with force | 0 | .claude/skills/aai-test-unit/SKILL.md |
| BS-05 | default | bootstrap | bs-polyglot | bootstrap with dry-run | 0 | package.json |
| BS-06 | default | bootstrap | bs-hooks | bootstrap with with-claude-hooks | 0 | .claude/settings.json |
| BS-07 | full | bootstrap | bs-hooks-invalid | bootstrap with with-claude-hooks | nonzero | .claude/settings.json |
| BS-08 | full | bootstrap | bs-multi | bootstrap | 0 | .gitignore |
| BS-09 | full | bootstrap | bs-vitest | bootstrap | 0 | .claude/skills/aai-test-unit/SKILL.md |

Tier sizes become smoke 9, default 21, full 29. Pairs on a bootstrap
scenario: sh:ps1, sh:node, ps1:node, plus self pairs on BS-03.

Allowlist: exactly one new row, reviewed:
`win-bootstrap-target-root`, pairs `sh:ps1,sh:node`, scenarios
`BS-01,BS-03,BS-04,BS-06,BS-07,BS-08,BS-09`, path
`.claude/skills/AAI_DYNAMIC_SKILLS.md`, kind `lines`, host `win32`, tracker
`accepted`, match `^- Target root: `, reason: Git Bash spells the target
root /c/...; the native module writes the Windows path, which a native
Windows bootstrap should record (DR-9). A further divergence a hosted run
shows gets a row and a follow-up in a remediation pass (D-FU), never a
normalization, as SPEC-0284 D-ALLOW requires.

### D-PESTER. `tests/skills/aai-bootstrap.Tests.ps1`

Pester 5, 5.1-compatible syntax, never skips (no `-Skip`, no host guard),
launches with the running engine (`(Get-Process -Id $PID).Path`) through
`ProcessStartInfo` with an explicit PATH, as cloudflare-share.Tests.ps1
does, scratch only under `$TestDrive`. Cases:

1. Pass-through: the launcher copied into `$TestDrive` beside a stub
   `aai-bootstrap.mjs` that writes its argv as JSON to a file and exits 7;
   arguments `"dir with space" --dry-run --force --with-claude-hooks -h`
   arrive in that order unchanged and the exit code is 7.
2. Refusal: PATH an empty `$TestDrive` directory; exit 1, stdout empty,
   stderr exactly the D-LAUNCH line, the target directory still empty.
3. Module missing: the launcher copied alone; the same refusal.
4. Real run: the repository's launcher on a `$TestDrive` target holding a
   package.json with a test script; exit 0, `.claude/skills/aai-test-unit/SKILL.md`
   exists and the marker's `- Target root: ` line names the target's
   native full path.

It runs in the existing jobs through their directory discovery: the Linux
`gate` job, `windows-5_1` (Windows PowerShell 5.1 and pwsh 7 steps) and
`windows-wsl1`. No job, step or exclusion is added; the TotalCount floor
111 and `AAI_EXPECTED_WIN_SKIP_COUNT` 4 stay; `test-ps1-quality.sh` keeps
failing a POSIX run that skips. Budget: at most 30 s per engine on a hosted
runner (the full-suite steps stand at 382 to 404 s of 600 s).

### D-INSTALL. A scratch aai-sync install runs both launchers

TEST-3957: `bash .aai/scripts/aai-sync.sh <scratch>/target --profile core`
from this checkout into a fresh `git init` target, then the vendored
`aai-bootstrap.mjs`, `.sh` and `.ps1` exist in the target; on three fresh
copies of the synced target (same absolute path, one after another) `bash
.aai/scripts/aai-bootstrap.sh .`, `sh .aai/scripts/aai-bootstrap.sh .` and
`<pwsh> -NoProfile -File .aai/scripts/aai-bootstrap.ps1 .` each exit 0 and
leave trees equal under `snapshotNormalized`; with PATH a scratch directory
holding only `dirname`, `sh .aai/scripts/aai-bootstrap.sh .` exits 1 with the
D-LAUNCH line and the target tree is unchanged. pwsh through `need_tool`
(fails on CI, a named SKIP-CASE locally).

### D-SAFETY. Tests delete and kill only what they provably created

- Every scratch root is `mkdtemp` under the run's temp directory with the
  prefix `const OWN_SCRATCH_PREFIX = 'aai-bs-';` (node) or
  `aai-bootstrap-node.` (bash), and holds a marker file `.aai-bs-owned`
  written at creation with the creating process id.
- Removal only through `removeOwnScratch(dir)` (bootstrap-reference.mjs) or
  `safe_rm_own` (the suite): it throws or fails the test (never skips
  silently) for an empty path, a relative path, a path whose basename lacks
  the prefix, a path outside the temp directory, and a directory without
  the marker; it re-reads the marker right before `rm`. An empty list of
  paths to remove is a hard failure, not a no-op. Pester uses `$TestDrive`
  only.
- No test calls `docker`, `pkill`, `killall` or a kill by pattern; child
  processes are synchronous with a timeout that kills only the child the
  test started. The suite runs under `aai-run-tests.sh`, whose container
  isolation already points `DOCKER_HOST` at a nonexistent socket.
- Bootstrap in tests writes only under scratch targets: each corpus and
  scenario target sits in its own scratch root, and the corpus checks that
  the scratch root holds no entry besides the targets, the reference tree,
  the stub directory, the stub log and the marker after every case.

### D-REHOME. Existing tests that read the old file, and their amendments

Behaviour assertions stay byte for byte; only these source-shape assertions
change, each with one unsigned amendment record
(`node .aai/scripts/spec-amend.mjs add --spec <spec> --ref bootstrap-on-node
--class contract --signoff none --what "<what>" --why "<one line>"`; the
owner's merge direction signs them):

- SPEC-0157 (`spec-aai-update-gitignore-drift-reconcile`), what begins
  `TEST-011, TEST-016, TEST-017, TEST-019 and TEST-020 re-homed`:
  test-aai-sync-seed.sh TEST-011 expects 2 `.sh` referencers of
  RUNTIME_IGNORE (sync and the library) and drops the bootstrap sourcing and
  read-loop assertions; TEST-016's named list holds
  `.aai/scripts/aai-bootstrap.mjs` instead of the `.sh`; TEST-019 asserts
  that bootstrap with the library removed exits 0 and seeds the 30 runtime
  patterns (DR-4) instead of printing the skip note; TEST-020 reads the
  bootstrap marker text from the module; test-aai-bootstrap.sh TEST-017
  replaces `assert_contains "$BOOTSTRAP_SCRIPT" "gitignore-block.sh"` by the
  module naming `RUNTIME_IGNORE.list` and not `gitignore-block.sh`.
- SPEC-0029 (`spec-hook-enforced-gates`), what begins `TEST-010 re-homed`:
  test-aai-hooks-overlay.sh TEST-010 reads the template path and the flag
  parsing from the module; the usage-header check still reads the launcher's
  first lines.
- SPEC-0265 (`spec-node-first-small-pairs`), what begins `TEST-3201 REQUIRED
  grows`: `validate-skills.mjs` REQUIRED gains
  `.aai/scripts/aai-bootstrap.mjs` and `.aai/scripts/aai-bootstrap.ps1` at
  the end; the mirrors in validate-skills.test.mjs, validate-skills.Tests.ps1
  and test-aai-validate-skills.sh follow.
- SPEC-0284 (`spec-install-path-parity-harness`), what begins `TEST-3560 and
  TEST-3562 widened`: TEST-3560 reads the tier rows of both specs' matrix
  tables (SPEC-0284's first, then this spec's) and the tier sizes become 9,
  21 and 29; TEST-3562 expects N1 to N5 and E1, E2; D-SEAM gains the twin
  `ops` field.

Unchanged and passing against the launcher: test-aai-bootstrap.sh (every
other case), test-aai-hooks-overlay.sh TEST-011, test-aai-sync-seed.sh
TEST-013, TEST-787 and TEST-823, test-aai-run-tests.sh,
test-aai-install-parity.sh TEST-3565 (now including the default bootstrap
scenarios) and TEST-3569 (its 150 s and 75 s bounds unchanged).

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-bootstrap-node` with globs
  `.aai/scripts/aai-bootstrap.*`, `.aai/scripts/platform.mjs`,
  `.aai/scripts/lib/platform-adapter.mjs`,
  `.aai/scripts/lib/merge-hooks-json.mjs`, `.aai/system/RUNTIME_IGNORE.list`,
  `.aai/system/PROFILES.yaml`, `.aai/templates/hooks/settings-hooks.json`,
  `.aai/scripts/aai-sync.sh`, `tests/fixtures/aai-bootstrap-reference/**`,
  `tests/skills/test-aai-bootstrap-node.sh`,
  `tests/skills/lib/aai-bootstrap.test.mjs`,
  `tests/skills/lib/bootstrap-reference.mjs`,
  `tests/skills/lib/install-parity.mjs`, `tests/skills/aai-bootstrap.Tests.ps1`,
  `tests/skills/lib/pester-native-capture.ps1`, and every other
  `tests/skills/lib/*` file the suite sources or reads. Rows
  `aai-bootstrap`, `aai-hooks-overlay`, `aai-sync-seed` and `aai-run-tests`
  gain `.aai/scripts/aai-bootstrap.mjs`; `aai-install-parity` gains
  `.aai/scripts/aai-bootstrap.*`, `tests/fixtures/aai-bootstrap-reference/**`
  and `tests/skills/lib/bootstrap-reference.mjs`; `aai-validate-skills`
  stays as is.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-bootstrap-node fallback unsampled (new suite of bootstrap-on-node; no successful observation)`
  and `aai-bootstrap-node<TAB>196`.
- `test-aai-hygiene-pack.sh` test_090: the row-count pin moves 137 to 138
  (a parallel ride that adds a suite moves it again; the branch merging
  second rebases the pin); test_129 passes.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded with
  `node .aai/scripts/check-cd-subshell-leak.mjs --record`;
  `.aai/scripts/aai-bootstrap.sh` falls 3 to 1 (the launcher's one
  `$(CDPATH= cd ...)`); the new suite holds no `cd` inside a command
  substitution, so no row is added.
- Nested-suite lint: no new allowlist row; the new suite calls other suites
  only in selector form.
- `check-test-registration.mjs` and `check-vendored-script-deps.mjs` exit 0.
- `.aai/system/PROFILES.yaml` core: `.aai/scripts/aai-bootstrap.mjs` and
  `.aai/scripts/aai-bootstrap.ps1` beside `aai-bootstrap.sh` (companion
  obligation for new `.aai/**` files).
- `.github/workflows/ps1-quality.yml`: both `push` and `pull_request` path
  lists (identical) gain `.aai/scripts/aai-bootstrap.mjs`,
  `.aai/scripts/aai-bootstrap.sh` and
  `tests/fixtures/aai-bootstrap-reference/**`; the `.ps1` and the Pester file
  are already covered by `.aai/scripts/**.ps1` and `tests/skills/*.Tests.ps1`;
  win-fallback test_034 passes. No job or step changes.
- Prompt corpus companion: SKILL_BOOTSTRAP.prompt.md grows (D-DOCS), so
  `tests/skills/lib/prompt-diet-ledger.sh` gains one JUSTIFIED_ADDITIONS entry
  with the measured byte growth (`/usr/bin/wc -c` against the base) and the
  TEST-012 pin in test-aai-prompt-diet.sh moves by the same number.

### D-DOCS. Documentation and release note

- CHANGELOG.md: one new heading
  `## [unreleased] — feat: project bootstrap runs on Node with a native Windows launcher`
  whose body says downstream bootstrap now requires Node.js 22 or later
  (both launchers refuse without it), names `aai-bootstrap.ps1`, and names
  the recorded drifts DR-1, DR-2, DR-4, DR-5 and DR-9.
- `.aai/SKILL_BOOTSTRAP.prompt.md` Default Path: each of the two commands
  gains a PowerShell line, `powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 . --dry-run`
  and `powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 .`, and one
  sentence says both need Node.js 22 or later; the POSIX lines and the
  platform section stay byte for byte.
- `.aai/system/DYNAMIC_SKILLS.md`: the default implementation is
  `.aai/scripts/aai-bootstrap.mjs`, run through `aai-bootstrap.sh` or
  `aai-bootstrap.ps1`.
- `.aai/system/RUNTIME_IGNORE.list` header: names `aai-bootstrap.mjs` as the
  bootstrap consumer (its own Node reconcile) instead of `aai-bootstrap.sh`
  via the shared library; no data line changes.
- RFC-0017 phase 5 row: one sentence after the thirteenth-slice sentence and
  before the remaining-scripts-plan sentence:
  `The fourteenth slice [moved the project bootstrap to Node](../issues/CHANGE-0261-bootstrap-on-node.md): one module holds the detection, rendering and write policy behind thin aai-bootstrap.sh and aai-bootstrap.ps1 launchers, byte-equivalent to the frozen bash reference in the parity harness, so Windows gets a native bootstrap.`
  Status stays `in progress`; frontmatter untouched; the allocator rewrites
  the link at merge (checks match only the suffix `bootstrap-on-node.md`).
  The inventory table is unchanged: a stem with a `.mjs` is not a pair
  (expert-fetch TEST-2624 passes).

### D-FU. Follow-ups

Filed by Implementation with `node .aai/scripts/follow-ups.mjs add --id <id>
--ref bootstrap-on-node --severity P3 --what ... --why ... --source ...` (ids
at most 40 characters), suggested at planning, not filed:
`fu-bootstrap-docker-tag-trailing-dash`, `fu-bootstrap-gitignore-crlf`
(cache patterns compared without CR stripping, list lines keep a CR),
`fu-bootstrap-generator-names-sh` (generated files name the `.sh` on
Windows). Every further divergence a hosted run shows gets one.

### D-SLICES. Slices and the fallback

- Slice (a) detection and planning: Spec-AC-01 to Spec-AC-06.
- Slice (b) rendering and writes: Spec-AC-07 to Spec-AC-10.
- Slice (c) hooks overlay, platform record, launchers and everything that
  makes the module the entry point: Spec-AC-11 to Spec-AC-20.
- Fallback: if (c) has to become the next ride, (a) and (b) ship alone
  with the module present but unreachable (`aai-bootstrap.sh` unchanged,
  the module not in PROFILES, no `.ps1`), the new suite running TEST-3940
  to TEST-3949, the masked corpus as the equivalence proof, the suite-map,
  weights and test_090 rows of D-WIRE, no CHANGELOG entry (the PR body
  carries `no-notes: Node bootstrap module added but not yet reachable from
  any launcher`), and Spec-AC-11 to Spec-AC-20 moved to the next ride's spec
  by a recorded amendment.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-02 to Spec-AC-06 (and Spec-AC-10 for the
  fixture-level equivalence).
- Intake AC-002 maps to Spec-AC-07 to Spec-AC-10.
- Intake AC-003 maps to Spec-AC-11 to Spec-AC-13.
- Intake AC-004 maps to Spec-AC-17 and hosted check H2.
- Intake AC-005 maps to Spec-AC-14, Spec-AC-16, Spec-AC-18 and hosted
  check H1.
- Intake AC-006 maps to Spec-AC-15, Spec-AC-16 (validate-skills),
  Spec-AC-19 and Spec-AC-20; the unchanged suites listed in D-REHOME pass in
  the Verification sweep.
- Owner requirement 10 (safety) maps to Spec-AC-01.

## Constitution deviations

None. Article 1: every rule is seen failing first and the corpus compares
real runs of the reference. Article 2: one module, two launchers of 9 lines,
no dependency. Article 4: without Node both launchers refuse with one named
line and write nothing; a missing template still degrades with a WARN, a
missing merge library still fails. Article 5: downstream bootstrap now
requires Node.js 22 or later; this is the owner's recorded decision (plan
section 4, decision 1), stated in the CHANGELOG entry, and the `.sh` keeps
its path, arguments and exit codes.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a test of this ride removes a scratch path the system SHALL refuse (throw or fail the test) for an empty path, a relative path, a basename without the own prefix, a path outside the temp directory, a directory without the .aai-bs-owned marker and an empty removal list, and the new test files SHALL hold no docker, pkill or killall call; tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh SHALL hash to the D-REF sha256 and, where git history holds 34fad51b, equal its aai-bootstrap.sh. | done | TEST-3940 red docs/ai/tdd/bootstrap-on-node/red/TEST-3940.log; TEST-3940 green docs/ai/tdd/bootstrap-on-node/green/TEST-3940-3942.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3940.txt | — | D-SAFETY, D-REF |
| Spec-AC-02 | .aai/scripts/aai-bootstrap.mjs SHALL import only node: specifiers, create no file and print nothing when imported, export the D-MODULE names, hold each D-MODULE anchor line exactly once, start children only through spawnSync(process.execPath, ...) and hold none of the strings rg, grep, bash, docker, gh auth or az account in a spawn call, nor the DR-3 messages. | done | TEST-3941 red docs/ai/tdd/bootstrap-on-node/red/TEST-3941.log; TEST-3941 green docs/ai/tdd/bootstrap-on-node/green/TEST-3940-3942.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3941.txt | — | D-MODULE, DR-3 |
| Spec-AC-03 | WHEN the module is run with arguments the system SHALL follow D-CLI: modes in any position, help text per DR-1 with exit 0, a second positional exit 2 with the ERROR line and help on stderr, a target that names no directory (an unknown flag included) exit 1 with the DR-2 line and nothing written; resolveRoot SHALL use PWD only when samePlace holds with the working directory, else the working directory, resolve a target lexically and ignore CDPATH. | done | TEST-3942 red docs/ai/tdd/bootstrap-on-node/red/TEST-3942.log; TEST-3942 green docs/ai/tdd/bootstrap-on-node/green/TEST-3940-3942.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3942.txt | — | D-CLI, D-ROOT, DR-1, DR-2, DR-6 |
| Spec-AC-04 | WHEN detect runs on a fixture the system SHALL return the D-DETECT lists in first-seen order without duplicates, with one node:test case per rule holding a positive and a negative fixture (package manager and lockfile order, languages, Python manager order, tools, build tools, lint tools, CI, deploy, Vitest flag, package.json queries on valid, invalid and non-object JSON). | done | TEST-3943 red docs/ai/tdd/bootstrap-on-node/red/TEST-3943.log; TEST-3943 green docs/ai/tdd/bootstrap-on-node/green/TEST-3943-3945.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3943.txt | — | D-DETECT |
| Spec-AC-05 | WHEN chooseCommands runs the system SHALL return the D-CHOOSE command of each chain for one fixture per chain step (task runner precedence justfile before Makefile per target, script names, the npm test special case, exec forms per manager, language fallbacks), and dockerTag SHALL give my-proj-x- for a root named My Proj--X. | done | TEST-3944 red docs/ai/tdd/bootstrap-on-node/red/TEST-3944.log; TEST-3944 green docs/ai/tdd/bootstrap-on-node/green/TEST-3943-3945.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3944.txt | — | D-CHOOSE |
| Spec-AC-06 | WHEN detectAuth and planSkills run the system SHALL apply D-AUTH (the e2e gate, candidate paths, the DR-5 walk with a signal only under node_modules not found and one in a hidden file found, the FACTS.md and env-file credential order, the session line) and D-PLAN (skill order, descriptions, wrapped unit and e2e commands, the Vitest, Prerequisites and Monty blocks, the five skipped messages). | done | TEST-3945 red docs/ai/tdd/bootstrap-on-node/red/TEST-3945.log; TEST-3945 green docs/ai/tdd/bootstrap-on-node/green/TEST-3943-3945.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3945.txt | — | D-AUTH, D-PLAN, DR-5 |
| Spec-AC-07 | WHEN renderSkill, renderMarker, renderIndex and renderSummary run on a fixed plan and a fixed timestamp the system SHALL return the reference's bytes for that plan, covering the fence rule (including a one-line command naming aai-run-tests.ps1), the empty extra block, every fallback line, the CI/CD join and the one-line display form. | done | TEST-3946 red docs/ai/tdd/bootstrap-on-node/red/TEST-3946.log; TEST-3946 green docs/ai/tdd/bootstrap-on-node/green/TEST-3946-3949.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3946.txt | — | D-RENDER |
| Spec-AC-08 | WHEN preflight and writeOutputs run the system SHALL treat a missing path and a file matching any managed mark as managed (the GENERATOR dots matching any character), refuse unmanaged files without force with the three stderr lines and exit 1 before any write, replace them with force, list a file unchanged when contents match after trailing newlines are removed, write content plus one newline otherwise, list dry-run paths without writing, and rewrite a file holding a NUL byte (DR-7). | done | TEST-3947 red docs/ai/tdd/bootstrap-on-node/red/TEST-3947.log; TEST-3947 green docs/ai/tdd/bootstrap-on-node/green/TEST-3946-3949.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3947.txt | — | D-WRITE, DR-7 |
| Spec-AC-09 | WHEN ensureGitignore runs the system SHALL follow D-GITIGNORE: a missing file is only listed in dry-run, cache patterns are appended after a blank line without CR stripping, runtime patterns are compared against a CR-stripped target, the marker is written once and never when any line starts with RUNTIME_MARKER_PREFIX, dry-run prints the count line, a missing list prints the named skip line, and with lib/gitignore-block.sh absent the 30 patterns are still seeded (DR-4, DR-8). | done | TEST-3948 red docs/ai/tdd/bootstrap-on-node/red/TEST-3948.log; TEST-3948 green docs/ai/tdd/bootstrap-on-node/green/TEST-3946-3949.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3948.txt | — | D-GITIGNORE, DR-4, DR-8 |
| Spec-AC-10 | WHEN the D-CORPUS cases K01 to K27 and K38 run in masked mode the system SHALL give exit code, stdout, stderr and normalized tree byte-equal between the bash reference and the module for every case, and no stub log SHALL hold a docker line. | done | TEST-3949 red docs/ai/tdd/bootstrap-on-node/red/TEST-3949.log; TEST-3949 green docs/ai/tdd/bootstrap-on-node/green/TEST-3946-3949.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3949.txt | — | D-CORPUS masked; slice b gate |
| Spec-AC-11 | WHEN the module runs with --with-claude-hooks the system SHALL follow D-HOOKS on every branch (template missing WARN exit 0, library missing ERROR exit 3, dry-run line, merged, unchanged on re-run, foreign keys kept, invalid JSON and a non-object hooks key refused with the file byte-identical and exit 3 after the summary), and a run without the flag SHALL not create .claude/settings.json. | done | TEST-3950 red docs/ai/tdd/bootstrap-on-node/red/TEST-3950.log; TEST-3950 green docs/ai/tdd/bootstrap-on-node/green/TEST-3950-3952.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3950.txt | — | D-HOOKS |
| Spec-AC-12 | WHEN recordGitPlatform runs with an injected child result the system SHALL relay exit 0 and exit 6 text as is, relay any other exit as platform record failed (exit n): text, pass --dry-run through, and never change the run's exit code. | done | TEST-3951 red docs/ai/tdd/bootstrap-on-node/red/TEST-3951.log; TEST-3951 green docs/ai/tdd/bootstrap-on-node/green/TEST-3950-3952.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3951.txt | — | D-PLATFORM |
| Spec-AC-13 | WHEN every D-CORPUS case K01 to K38 runs in full mode the system SHALL give exit code, stdout, stderr and normalized tree byte-equal between the reference and the module, with gh or az stub lines only for K35 to K37 and no docker line. | done | TEST-3952 red docs/ai/tdd/bootstrap-on-node/red/TEST-3952.log; TEST-3952 green docs/ai/tdd/bootstrap-on-node/green/TEST-3950-3952.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3952.txt | — | D-CORPUS full |
| Spec-AC-14 | .aai/scripts/aai-bootstrap.sh SHALL be the D-LAUNCH text (at most 20 lines, no policy token), and WHEN run by bash, sh and dash with a stub module it SHALL pass every argument and the exit code through; WHEN node is not on PATH or the module is missing it SHALL exit 1 with the D-LAUNCH line on stderr and leave the target unchanged; PROFILES core SHALL list aai-bootstrap.mjs. | done | TEST-3953 red docs/ai/tdd/bootstrap-on-node/red/TEST-3953.log; TEST-3953 green docs/ai/tdd/bootstrap-on-node/green/TEST-3953-3954.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3953.txt | — | D-LAUNCH |
| Spec-AC-15 | WHEN the D-REHOME selectors of test-aai-bootstrap.sh, test-aai-hooks-overlay.sh and test-aai-sync-seed.sh run against the launcher each SHALL exit 0 with only the D-REHOME edits made to those suites, and spec-amend list SHALL hold one contract record of ref bootstrap-on-node for SPEC-0157 and one for SPEC-0029 whose what begins with the D-REHOME text. | done | TEST-3954 red docs/ai/tdd/bootstrap-on-node/red/TEST-3954.log; TEST-3954 green docs/ai/tdd/bootstrap-on-node/green/TEST-3953-3954.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3954.txt | — | D-REHOME (SPEC-0157, SPEC-0029) |
| Spec-AC-16 | .aai/scripts/aai-bootstrap.ps1 SHALL be the D-LAUNCH text (at most 20 lines, no policy token, listed in PROFILES core); tests/skills/aai-bootstrap.Tests.ps1 run with Invoke-Pester under pwsh 7 SHALL pass at least 4 tests with 0 skipped, 0 failed and 0 failed containers, covering the four D-PESTER cases; validate-skills REQUIRED SHALL end with aai-bootstrap.mjs and aai-bootstrap.ps1 with its three mirrors passing, and spec-amend list SHALL hold the SPEC-0265 record of D-REHOME. | done | TEST-3955 red docs/ai/tdd/bootstrap-on-node/red/TEST-3955.log; TEST-3955 green docs/ai/tdd/bootstrap-on-node/green/TEST-3955-3957.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3955.txt | — | D-PESTER, D-REHOME (SPEC-0265); H1 for 5.1 and 7 on Windows |
| Spec-AC-17 | WHEN the parity driver runs --scenario BS-01 to BS-09 with twins sh, ps1 and node against the committed allowlist the system SHALL exit 0 with verdict PASS and pairs sh:ps1, sh:node and ps1:node in every bootstrap scenario, BS-03 self pairs, N5 in NORMALIZATIONS, node absent from every non-bootstrap scenario, and the one new allowlist row; a module twin that appends one byte to the marker SHALL fail naming its pairs on that path; the amended TEST-3560 and TEST-3562 selectors SHALL pass and spec-amend list SHALL hold the SPEC-0284 record of D-REHOME. | done | TEST-3956 red docs/ai/tdd/bootstrap-on-node/red/TEST-3956.log; TEST-3956 green docs/ai/tdd/bootstrap-on-node/green/TEST-3955-3957.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3956.txt | — | D-PARITY, D-REHOME (SPEC-0284); H2 on Windows |
| Spec-AC-18 | WHEN this checkout is synced with aai-sync.sh --profile core into a scratch target the system SHALL vendor the module and both launchers, and bash, sh and pwsh runs of the vendored launchers SHALL each exit 0 with normalized-equal trees, while sh without node on PATH SHALL exit 1 with the refusal line and leave the tree unchanged. | done | TEST-3957 red docs/ai/tdd/bootstrap-on-node/red/TEST-3957.log; TEST-3957 green docs/ai/tdd/bootstrap-on-node/green/TEST-3955-3957.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3957.txt | — | D-INSTALL |
| Spec-AC-19 | Wiring per D-WIRE: select-suites SHALL route the module, both launchers, the reference copy, the node:test file and the Pester file to aai-bootstrap-node; the weights row SHALL be 196 with its fallback line; hygiene test_090 SHALL pin 138 and test_129 pass; the cd-subshell baseline SHALL hold 1 for aai-bootstrap.sh; nested-suite lint, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps SHALL exit 0; both ps1-quality path lists SHALL be identical and hold the D-WIRE entries with win-fallback test_034 passing. | done | TEST-3958 red docs/ai/tdd/bootstrap-on-node/red/TEST-3958.log; TEST-3958 green docs/ai/tdd/bootstrap-on-node/green/TEST-3958-3959.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3958.txt | — | D-WIRE |
| Spec-AC-20 | CHANGELOG.md SHALL hold the D-DOCS heading exactly once with a body naming Node.js 22 and aai-bootstrap.ps1; SKILL_BOOTSTRAP.prompt.md SHALL hold both PowerShell lines once each with the POSIX lines unchanged, and test-aai-prompt-diet.sh SHALL pass; DYNAMIC_SKILLS.md and the RUNTIME_IGNORE.list header SHALL name aai-bootstrap.mjs; the RFC-0017 phase 5 row SHALL keep status in progress and hold the D-DOCS sentence once, and expert-fetch test_2624 SHALL pass. | done | TEST-3959 red docs/ai/tdd/bootstrap-on-node/red/TEST-3959.log; TEST-3959 green docs/ai/tdd/bootstrap-on-node/green/TEST-3958-3959.log, mutation docs/ai/tdd/spec-bootstrap-on-node/mutation-TEST-3959.txt | — | D-DOCS |

## Implementation plan

TDD in seven runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/bootstrap-on-node/red/` before its change and GREEN under
`green/`, and one mutation record per row
(`node .aai/scripts/mutation-run.mjs`, records under
`docs/ai/tdd/spec-bootstrap-on-node/`) before the run's hand-off.

1. Run 1, Spec-AC-01 to 03: the frozen reference and its helper module, the
   new suite skeleton with `safe_rm_own`, `run_node_tests` and `need_tool`,
   the node:test file, the module's shape, arguments and root; the suite-map,
   weights and test_090 rows land here with the suite.
2. Run 2, Spec-AC-04 to 06: detection, command choice, auth and the plan.
3. Run 3, Spec-AC-07 to 10: rendering, writes, `.gitignore`, the masked
   corpus. Fallback ship point (D-SLICES).
4. Run 4, Spec-AC-11 to 13: hooks overlay, platform relay, the full corpus.
5. Run 5, Spec-AC-14 and 15: the `.sh` launcher swap together with its
   PROFILES entry and the SPEC-0157 and SPEC-0029 re-homes and records, so
   no suite is red between runs.
6. Run 6, Spec-AC-16 to 18: the `.ps1` launcher, its PROFILES entry and
   Pester, the validate-skills REQUIRED growth with the SPEC-0265 record
   (both files exist from here on), the parity harness extension with the
   SPEC-0284 record, the scratch install.
7. Run 7, Spec-AC-19 and 20: the rest of D-WIRE (cd baseline re-record,
   ps1-quality lists), D-DOCS with the prompt diet ledger, D-FU; then the
   full sweep once.

Edge cases: a target path with a space (BS-01, Pester case 1); a symlinked
working directory; a stale `PWD`; a CRLF `.gitignore`; two runs inside one
second (the corpus and the harness wait for the next second); a merge
library or template missing from the tree; an Azure or GitHub origin
(stubs only, nothing reaches the network); Windows paths given to Git Bash
as `C:/...`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3940 | Spec-AC-01 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3940_scratch_safety runs run_node_tests TEST-3940 (removeOwnScratch refuses each D-SAFETY case and removes a marked own directory; the reference copy hashes to REFERENCE_SHA256 and equals git show 34fad51b:.aai/scripts/aai-bootstrap.sh when that object exists), checks safe_rm_own refuses an empty, relative, foreign and unmarked path, and scans the new test files for docker, pkill and killall calls | `sed:s/const OWN_SCRATCH_PREFIX = 'aai-bs-';/const OWN_SCRATCH_PREFIX = '';/` on tests/skills/lib/bootstrap-reference.mjs | green |
| TEST-3941 | Spec-AC-02 | inspection | tests/skills/test-aai-bootstrap-node.sh | test_3941_module_shape runs run_node_tests TEST-3941: import in a scratch cwd creates nothing and prints nothing; the export list; only node: imports; each anchor once; every spawn call starts with spawnSync(process.execPath; no DR-3 message strings | `sed:s/spawnSync\(process.execPath, \[script/spawnSync('node', [script/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3942 | Spec-AC-03 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3942_cli_and_root runs run_node_tests TEST-3942: modes in any position, help text equal to the reference help minus two lines plus the PowerShell line (DR-1), exit 2 on a second positional with stderr, exit 1 and nothing written for a missing target, a file and --bogus (DR-2), resolveRoot with a matching PWD (logical path kept), a stale PWD (cwd used), a relative target with dot-dot, and CDPATH set (ignored, DR-6) | `sed:s/a.dev === b.dev && a.ino === b.ino/true/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3943 | Spec-AC-04 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3943_detection runs run_node_tests TEST-3943: one positive and one negative fixture per D-DETECT rule, lockfile precedence pnpm before yarn before bun, first-seen order and no duplicate ESLint entry, package.json queries on valid, invalid and null JSON | `sed:s/\['pnpm-lock.yaml', 'pnpm'\], \['yarn.lock', 'yarn'\]/['yarn.lock', 'yarn'], ['pnpm-lock.yaml', 'pnpm']/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3944 | Spec-AC-05 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3944_commands runs run_node_tests TEST-3944: each chain step of unit, e2e, build, lint, monty and deploy on its own fixture, justfile before Makefile for one target, the justfile and Makefile target regexes, npm test against npm run, exec forms of npm, pnpm, yarn and bun, dockerTag on My Proj--X | `sed:s/script === 'test'\) return 'npm test'/script === 'nonesuch') return 'npm test'/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3945 | Spec-AC-06 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3945_auth_and_plan runs run_node_tests TEST-3945: no auth without an e2e command; a signal only under node_modules or dist not found; a signal in a hidden file found; FACTS.md before env files; .env.test without names skipped for .env.testing; session line both ways; plan order, descriptions, wrapped commands and the three extra blocks byte for byte; skipped messages | `sed:s/const AUTH_SKIP_DIRS = \['node_modules', '.git', 'dist', 'build'\];/const AUTH_SKIP_DIRS = [];/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3946 | Spec-AC-07 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3946_rendering runs run_node_tests TEST-3946: renderSkill with a wrapped, a plain and a one-line aai-run-tests.ps1 command and with and without an extra block; renderMarker with empty and full lists and CI plus deploy; renderIndex for Codex and Gemini with and without skills; renderSummary with and without auth, unchanged, skipped and platform sections; expected bytes captured once from the reference and committed in the test | `sed:s/- Ownership: project-owned dynamic skills/- Ownership: project owned dynamic skills/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3947 | Spec-AC-08 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3947_writes_and_conflicts runs run_node_tests TEST-3947: each managed mark, the Xaai dots case, conflict lines and exit 1 with nothing written, force replacing, unchanged after extra trailing newlines, dry-run listing without writing, write order, a NUL byte file rewritten (DR-7) | `sed:s/stripTrailingNewlines\(a\) === stripTrailingNewlines\(b\)/a === b/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3948 | Spec-AC-09 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3948_gitignore runs run_node_tests TEST-3948: missing file in dry-run and real run, cache patterns after blank lines, a CR-suffixed cache line not counted (parity), runtime patterns against a CRLF target, one marker with a legacy sync marker present, dry-run count line, missing list line naming the path (DR-8), and a tree copy without lib/gitignore-block.sh still seeding 30 patterns (DR-4) | `sed:s/const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars';/const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars (seeded by aai-bootstrap';/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3949 | Spec-AC-10 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3949_corpus_masked needs bash and git and runs run_node_tests TEST-3949: K01 to K27 and K38 in masked mode, each comparing exit, stdout, stderr and the normalized tree of the reference and the module, with no docker line in any stub log | `sed:s/const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:START';/const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:BEGIN';/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3950 | Spec-AC-11 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3950_hooks_overlay runs run_node_tests TEST-3950: every D-HOOKS branch on scratch roots with the real merge library or a tree copy without it, file bytes before and after a refusal, exit codes 0 and 3, no settings.json without the flag | `sed:s/const EXIT_HOOKS_REFUSED = 3;/const EXIT_HOOKS_REFUSED = 0;/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3951 | Spec-AC-12 | unit | tests/skills/test-aai-bootstrap-node.sh | test_3951_platform_record runs run_node_tests TEST-3951: an injected child result with exit 0, 6, 1 and 4 gives the relayed or failed text, the dry-run flag reaches the argv, the run's exit code is unchanged | `sed:s/const PLATFORM_MISMATCH = 6;/const PLATFORM_MISMATCH = 7;/` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3952 | Spec-AC-13 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3952_corpus_full needs bash and git and runs run_node_tests TEST-3952: every case K01 to K38 in full mode, gh or az stub lines only for K35 to K37, no docker line | `sed:s/  hooks overlay: /  hooks overlay:  /` on .aai/scripts/aai-bootstrap.mjs | green |
| TEST-3953 | Spec-AC-14 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3953_sh_launcher checks the launcher text (at most 20 lines, ASCII, mode 100755, no policy token), runs a copy beside a stub module under bash, sh and dash (dash through need_tool) with a spaced target and the three flags and -h and requires the argv and exit 7 through, then with PATH holding only dirname and with the module removed requires exit 1, the exact refusal line and an unchanged target; requires PROFILES core to list aai-bootstrap.mjs | `sed:s/\nexit 1\n/\nexit 0\n/` on .aai/scripts/aai-bootstrap.sh | green |
| TEST-3954 | Spec-AC-15 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3954_rehomed_suites runs the re-homed selectors (test-aai-bootstrap.sh test_gitignore_seed_uses_shared_library, test-aai-hooks-overlay.sh test_010_bootstrap_wiring and test_011_bootstrap_behavior, test-aai-sync-seed.sh test_single_bash_reader_and_sourcing, test_runtime_ignore_header_consumer_accuracy, test_bootstrap_survives_missing_library and test_marker_prefix_pinned_across_call_sites) each exit 0, and reads spec-amend list --json for the SPEC-0157 and SPEC-0029 contract records of ref bootstrap-on-node | `sed:s/aai-bootstrap.mjs/aai-bootstrap.sh/` on .aai/system/RUNTIME_IGNORE.list | green |
| TEST-3955 | Spec-AC-16 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3955_ps1_launcher checks the .ps1 text (at most 20 lines, ASCII, no param block, no policy token) and PROFILES core, runs the test-aai-validate-skills.sh test_3201_required_and_first_missing selector and requires the SPEC-0265 record, then needs pwsh and Pester 5 and runs Invoke-Pester on tests/skills/aai-bootstrap.Tests.ps1 under env -u AAI_ROLE requiring at least 4 passed, 0 skipped, 0 failed and 0 failed containers | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/aai-bootstrap.ps1 | green |
| TEST-3956 | Spec-AC-17 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3956_parity_bootstrap needs pwsh, runs the driver with --scenario BS-01 to BS-09 and twins sh,ps1,node into a scratch report and requires exit 0, verdict PASS, the three pairs per scenario, BS-03 self pairs and node only on BS scenarios; runs run_node_tests TEST-3956 for N5 on synthetic stamps and the DR-9 row parse; then a skew module twin appending one byte to the marker fails naming its pairs; runs the test-aai-install-parity.sh test_3560_matrix_tiers and test_3562_normalizations selectors and requires the SPEC-0284 record | `sed:s/'aai-bootstrap.mjs'\), ctx.target/'aai-bootstrap.mjs'), ctx.bsref/` on tests/skills/lib/install-parity.mjs | green |
| TEST-3957 | Spec-AC-18 | integration | tests/skills/test-aai-bootstrap-node.sh | test_3957_scratch_install syncs this checkout with --profile core into a scratch git target, requires the module and both launchers vendored, runs bash, sh and pwsh (need_tool) launchers on three fresh copies at one path with equal normalized trees, then sh with PATH holding only dirname exits 1 with the refusal line and an unchanged tree | `sed:s/  - .aai\/scripts\/aai-bootstrap.mjs\n//` on .aai/system/PROFILES.yaml | green |
| TEST-3958 | Spec-AC-19 | inspection | tests/skills/test-aai-bootstrap-node.sh | test_3958_wiring pipes the module, both launchers, the reference copy, the node:test file and the Pester file to select-suites.mjs --files-from - and requires aai-bootstrap-node each time; requires the weights row 196 with its fallback line; runs hygiene-pack test_090_suite_map_pin and test_129_mutation_gate_suite_registration and win-fallback test_034 selectors; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and check-vendored-script-deps (exit 0); requires the baseline row 1 for aai-bootstrap.sh and identical ps1-quality path lists holding the D-WIRE entries | `sed:s/  aai-bootstrap-node:/  aai-bootstrap-node-gone:/` on tests/skills/suite-map.yaml | green |
| TEST-3959 | Spec-AC-20 | inspection | tests/skills/test-aai-bootstrap-node.sh | test_3959_docs requires the CHANGELOG heading once with Node.js 22 and aai-bootstrap.ps1 in its body, both PowerShell lines once each in SKILL_BOOTSTRAP.prompt.md with the POSIX lines present, DYNAMIC_SKILLS.md and the RUNTIME_IGNORE.list header naming aai-bootstrap.mjs, the RFC-0017 phase 5 row in progress holding the D-DOCS sentence once with a link ending bootstrap-on-node.md, and runs test-aai-prompt-diet.sh test_012 and expert-fetch test_2624_inventory_matches_tree selectors (exit 0) | `sed:s/The fourteenth slice \[moved the project bootstrap to Node\]/The fourteenth slice [moved bootstrap]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |

Test counts by type: unit 10, integration 7, inspection 3 (20 rows). The
re-homed rows of other specs (D-REHOME) keep their own ids and mutations.

Seams crossed (Principle 2): the module against the frozen reference on
the same fixtures and the same `.aai` tree (TEST-3949, TEST-3952: stdout,
stderr, exit and tree); the module against the shared children it does not
own, `merge-hooks-json.mjs` and `platform.mjs`, through real runs (TEST-3950,
TEST-3952); the `.gitignore` the module seeds against the sync twins'
legacy marker and the shared list (TEST-3948, and sync-seed TEST-011, 016,
019, 020 in TEST-3954); the launchers against the module and against an
environment without Node (TEST-3953, TEST-3955, and natively on Windows in
H1); `aai-sync` vendoring the module through PROFILES into a target whose
launchers then run it (TEST-3957); the parity driver's twin registry, the
PowerShell launcher and the reference on native Windows (TEST-3956 and H2);
select-suites, the hygiene pins, the ratchets and the ps1 path-filter
derivation reading the new files (TEST-3958); the RFC inventory and the
prompt-diet ledger reading the docs (TEST-3959).

RED observations (stored under `docs/ai/tdd/bootstrap-on-node/red/`):
TEST-3940 to TEST-3952 fail on the baseline because the reference copy, its
helper and the module do not exist; TEST-3953 fails because the `.sh` is
still the bash script (more than 20 lines); TEST-3954 fails on the
re-homed selectors before their edits once the launcher is in place (the
run 5 order makes this the RED); TEST-3955 to TEST-3959 fail because the
`.ps1`, the BS scenarios, the vendoring, the suite row and the docs are
absent.

Hosted checks (CI, not Test Plan rows; recorded in the validation report
from the PR's ps1-quality run):

- H1: `windows-5_1` (Windows PowerShell 5.1 and pwsh 7) and `windows-wsl1`
  full-suite steps report `aai-bootstrap.Tests.ps1` passed, skipped count
  still 4, TotalCount at or above 111, no failed container, elapsed under
  600 s.
- H2: the `windows-parity` job's two steps pass with BS-01 and BS-02 in the
  smoke report, the sh, ps1 and node twins compared, and at most the
  `win-bootstrap-target-root` row covering a bootstrap divergence;
  `AAI-PARITY-ELAPSED` recorded for each engine.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-bootstrap-node.sh`
  exits 0 (20 rows), plus the touched and selected suites run the same way:
  test-aai-bootstrap.sh, test-aai-hooks-overlay.sh, test-aai-sync-seed.sh,
  test-aai-run-tests.sh, test-aai-validate-skills.sh,
  test-aai-install-parity.sh, test-aai-hygiene-pack.sh,
  test-aai-win-fallback.sh, test-aai-prompt-diet.sh, test-aai-expert-fetch.sh,
  test-aai-layer-profiles.sh, test-ps1-quality.sh; then the full sweep once
  before close with `AAI_TEST_TIMEOUT=3000`.
- `env -u AAI_ROLE node --test tests/skills/lib/aai-bootstrap.test.mjs` and
  `env -u AAI_ROLE node --test tests/skills/lib/install-parity.test.mjs`
  exit 0 (also under Node 22, as the skill-suite Node 22 step runs every
  `tests/skills/lib/*.test.mjs`).
- Hosted checks H1 and H2 from the PR's ps1-quality run; a divergence that
  appears only on Windows gets an allowlist row and a follow-up in a
  remediation pass, never a normalization.
- `node .aai/scripts/spec-lint.mjs --path <this spec>`,
  `node .aai/scripts/mutation-gate.mjs` for this spec and
  `node .aai/scripts/spec-amend.mjs list --strict` pass.

## Evidence contract

ref_id `bootstrap-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/bootstrap-on-node/` and `docs/ai/tdd/spec-bootstrap-on-node/`
(gitignored); each AC row's Evidence names its green log and mutation
record; the validation report and review verdict under `docs/ai/reports/`
and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- The `rg` branch of the reference is not exercised on the planning host
  (no `rg`); a CI image with `rg` takes it. Fixtures put no auth signal in a
  hidden, gitignored or skipped path, so both branches agree there; DR-5
  pins the module's own rule. A project whose only signal sits in such a
  path gets the module's answer, which may differ from what the old script
  gave on that host.
- Stdout and stderr are compared on POSIX only (the corpus needs bash);
  on Windows the harness compares trees and exit codes, and the summary's
  `Target:` line differs by design (DR-9).
- The Pester real-run case and the `windows-parity` bootstrap scenarios are
  the only native Windows evidence; they are not measured at planning
  (estimate: under 30 s per engine for the Pester file and about 20 s per
  engine added to `windows-parity`).
- TEST-3569's reference-host bounds (150 s default, 75 s smoke) now include
  six and two bootstrap scenarios (estimate: under 20 s and 8 s added); if a
  reference-host run exceeds a bound, the remediation moves BS-02 out of
  smoke (a recorded tier edit), never the bound.
- A downstream project without Node can no longer bootstrap; the launcher
  says so and names the install. This is the owner's decision, disclosed in
  the CHANGELOG.
- The frozen reference ties the bootstrap scenarios to today's behaviour; a
  later intended change must retire them or add reviewed rows (D-REF).
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope: none

Items this scope leaves open, with reasons: the `fu-parity-*` items of the
sync and update twins (not bootstrap; this ride adds one accepted row only)
and `fu-parity-node22-step-wire` (the Node 22 step will also run the new
node:test file; its time is reported in the validation report, the item
stays with the harness ride).
