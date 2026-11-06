---
id: spec-cloudflare-share-on-node
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: b32b6063304563c045a0a43a366617eff0cdb010c2787c192794d2b00f59bb88
ceremony_level: 2
links:
  requirement: cloudflare-share-on-node
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Port the Cloudflare share script pair to one Node module

SPEC-FROZEN: true

## Links

- Requirement: [Port the Cloudflare share script pair to one Node module](../issues/CHANGE-DRAFT-cloudflare-share-on-node.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 3 (no owner sign-off required by the plan).
- Pattern precedents: the reaper port [CHANGE-0241](../issues/CHANGE-0241-node-first-reap-tests.md)
  (one Node module, thin launchers, `node:test`, Pester under Windows
  PowerShell 5.1 and pwsh 7, a scratch `aai-sync` install) and ride 1's
  migrate-state-to-local port ([SPEC-0273](SPEC-0273-spec-retire-legacy-migrations.md):
  launcher shape and refusal line, `run(opts, deps)` seam, the suite helpers
  `run_node_tests` and `need_tool`); ride 2 ([SPEC-0274](SPEC-0274-spec-retire-shell-loop-runner.md))
  for the wiring it had to add at implementation.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, `node:test`,
  bash suites, Pester 5).
- Baseline: main `bd519bb3`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (rides 1
  and 2). The module is behaviour on a shipped, consumer-visible path with an
  external write effect; every drift decision is a behaviour that must be seen
  failing first. Inspection rows (wiring, RFC, budget) are RED on the baseline
  too. Every row carries a mutation record.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped scripts, a new shipped
  module, PROFILES, a CI workflow path list, an umbrella RFC and several
  suites' pins; the main checkout is shared and holds unrelated uncommitted
  files (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/dashboard*).
- User decision: pending (autopilot default 2 records `worktree` with
  rationale "autopilot default")
- Base ref: main
- Worktree branch/path: refactor/cloudflare-share-on-node at /Users/ales/Projects/aai-worktrees/cloudflare-share-on-node
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/cloudflare-share.mjs .aai/scripts/cloudflare-share.sh
  .aai/scripts/cloudflare-share.ps1 .aai/system/PROFILES.yaml
  .github/workflows/ps1-quality.yml docs/TECHNOLOGY.md
  tests/skills/test-aai-cloudflare-share.sh tests/skills/lib/cloudflare-share.test.mjs
  tests/skills/cloudflare-share.Tests.ps1 tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv
  tests/skills/test-aai-hygiene-pack.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/issues/CHANGE-DRAFT-cloudflare-share-on-node.md
  docs/specs/SPEC-DRAFT-cloudflare-share-on-node.md docs/INDEX.md
  (cd-subshell-leak-baseline.tsv only if the ratchet asks for a row).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 5, BSD `/usr/bin/grep`,
Node 22.23.1, pwsh 7, git) on 2026-11-06 at `bd519bb3`, with a stub `wrangler`
on PATH that prints one `https://abc123.my-repo.aai-reports.pages.dev` line.
Windows PowerShell 5.1 was not available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`).

| Script | Total lines | Code lines | Git mode |
|---|---|---|---|
| cloudflare-share.sh | 78 | 51 | 100644 |
| cloudflare-share.ps1 | 69 | 47 | 100644 |

Before: 147 total lines, 98 code lines over the two files; twin duplication
47 code lines (the smaller side).

### Observed on the baseline

- `.sh` in a git repo named `My Repo`: conversion and deploy run, then
  `grep: invalid option -- P`, exit 2, `.cloudflare-publish/` left in place,
  no history record. This is the macOS failure.
- `.sh` outside a git repo: the deploy line reads `(branch: )`; the
  `basename ... || basename "$PWD"` fallback never fires because `basename ""`
  succeeds.
- `.ps1` under pwsh 7 in the same repo: exit 0, the success lines, record
  `{"timestamp":...,"document":"doc.md","size_kb":2.28,"url":...}` (hashtable
  key order, apparent size with two decimals).
- `.ps1` under pwsh 7 outside a git repo: `Cannot bind argument to parameter
  'Path' because it is null.`, exit 1, `.cloudflare-publish/` left in place.
- `.ps1` under pwsh 7 with no argument and `-NonInteractive`: `Cannot process
  command because of one or more missing mandatory parameters: DocumentPath.`,
  exit 1 (without `-NonInteractive` it prompts).
- `.ps1` with a missing document: a thrown error record on stderr, exit 1.

### Callers and references (tracked files; docs history, CHANGELOG history and test results excluded)

- `.aai/SKILL_SHARE.prompt.md` line 72 names both scripts "for non-agent use";
  its own agent flow (steps 2 to 5) runs `share-convert.mjs` and `wrangler`
  directly and writes `{timestamp, document, url}` to the same
  `docs/ai/published/history.jsonl`. Unchanged (D-CALLERS).
- Harness wrappers `.claude/skills/aai-share/SKILL.md`,
  `.agents/skills/aai-share/SKILL.md`, `.codex/skills/aai-share/SKILL.md`,
  `.gemini/skills/aai-share/SKILL.md`: point at the prompt, unchanged.
- `.aai/scripts/share-convert.mjs`: called by both twins, unchanged; the
  module runs it as a child process exactly as the twins do.
- `.aai/system/PROFILES.yaml` lines 329 and 330: both scripts under
  `extended:`; the module joins them there.
- `docs/TECHNOLOGY.md` line 37 names the `.sh`/`.ps1` pair; it gains the
  module name (no technology added).
- `tests/skills/suite-map.yaml` row `aai-share` lists both scripts; its suite
  `test-aai-share.sh` never runs them (it mocks every step). Unchanged.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv` line 25 holds
  `1 .aai/scripts/cloudflare-share.sh`; the launcher keeps exactly one `cd`
  inside a substitution, so the row stays.
- `tests/skills/test-aai-hygiene-pack.sh` line 1797: a historical comment.
  Unchanged.
- `SKILLS.md`: names `share-convert.mjs` and Wrangler, not the scripts.
  Unchanged.
- No reader of `docs/ai/published/history.jsonl` exists in the tree.
- No shipped hook, routine, `aai-sync`, `aai-update`, `aai-bootstrap` or
  `aai-doctor` path invokes either script.

### Wiring found at planning (ride 2 found several only at implementation)

- `tests/skills/suite-map.yaml`: 127 top-level rows; the new row makes 128.
- `tests/skills/test-aai-hygiene-pack.sh` pins the row count in two places:
  `test_090_suite_map_pin` (line 1104) and
  `test_129_mutation_gate_suite_registration` (line 2133). Both move to 128.
- `tests/skills/lib/nested-suite-lint.mjs` (run by hygiene-pack
  `test_133`, allowlist pinned at 5 rows) refuses a suite that runs another
  whole suite; every cross-suite call in the new suite is selector form.
- `tests/skills/suite-weights.tsv`: new suites carry
  `<name><TAB>212` with a `# sample <name> fallback unsampled (...)` line.
- `.github/workflows/ps1-quality.yml`: both path lists name the Node modules
  that a Pester-tested launcher runs (`aai-reap-tests.mjs`,
  `migrate-state-to-local.mjs`); the new module joins both lists.
- `.aai/scripts/check-cd-subshell-leak.mjs` (hygiene-pack `test_108`,
  `test_109`) exits 0 at baseline; a `cd` inside a substitution in the new
  suite needs a recorded row.
- `.aai/scripts/check-test-registration.mjs`: every `test_*` function of the
  new suite must be called.
- RFC-0017 inventory (`test-aai-expert-fetch.sh test_2624_inventory_matches_tree`)
  lists a pair only while `<name>.mjs` is absent; adding the module makes the
  `cloudflare-share` row "not a pair in the tree", so the row is removed (ride
  1 removed the migrate-state-to-local row the same way).
- Prompt corpus: no `.aai/*.prompt.md` and no `.aai/AGENTS.md` change, so no
  prompt-diet ledger entry, no TEST-012 move, and no companion pin move in
  `test-aai-pr-preflight.sh`, `test-aai-legacy-migrations.sh` or
  `test-aai-retired-loop-runner.sh`.

## Decisions

### D-DRIFT. Every behaviour difference between the twins

Each row is decided here and pinned by exactly one `node:test` case in
`tests/skills/lib/cloudflare-share.test.mjs` whose name begins with the DR id.

| DR | Behaviour | .sh at bd519bb3 | .ps1 at bd519bb3 | Decision |
|---|---|---|---|---|
| DR-01 | no document argument | usage on stdout, exit 1 | mandatory parameter: prompts, or a binding error and exit 1 under -NonInteractive | usage line on stderr, exit 1, nothing created, never a prompt; `-h` and `--help` print the usage line on stdout and exit 0 |
| DR-02 | document not found | `ERROR: Document not found: X` on stdout, exit 1 | thrown error record on stderr, exit 1 | `ERROR: Document not found: X` on stderr, exit 1 |
| DR-03 | directory or wildcard path | regular file only | Test-Path accepts a directory and reads `[` `]` as wildcards | literal path, regular file only, else DR-02 |
| DR-04 | document name in the report | strips a trailing `.md` only | strips any last extension | strip the last extension (`notes.markdown` reports `notes`, `doc.md` reports `doc`) |
| DR-05 | conversion fails | exits with share-convert's code, publish dir left | `Conversion failed` thrown, exit 1, publish dir left | `ERROR: conversion failed (share-convert.mjs exited N)` on stderr, exit 1, publish dir removed |
| DR-06 | wrangler not on PATH | three stdout lines after conversion, publish dir removed | one thrown line without the login hint, after conversion | checked before conversion: three stderr lines `ERROR: wrangler not found`, `Install: npm install -g wrangler`, `Then run: wrangler login`, exit 1, no publish dir created |
| DR-07 | wrangler resolution on Windows | n/a | Get-Command finds the npm `wrangler.cmd` shim | the module resolves `wrangler` itself over PATH (and PATHEXT on win32); a `.cmd` or `.bat` hit runs through the shell with only the fixed, sanitised arguments of D-MOD |
| DR-08 | branch name outside a git repository | empty branch (`basename ""`) | pwsh 7: null-path crash, exit 1, publish dir left; 5.1: falls back to the current directory | basename of the current directory; an empty result after sanitising refuses with exit 1 |
| DR-09 | non-ASCII repository name | ASCII `tr`, locale-dependent `sed` (one or more dashes per character) | Unicode ToLower, one dash per character | Unicode lower case, one dash per code point outside `[a-z0-9-]` |
| DR-10 | wrangler exit status | ignored (`or true`) | ignored; under 5.1 a wrangler stderr line ends the script | a non-zero status is a failure (exit 1) whatever the output holds; stderr output never ends the run |
| DR-11 | URL extraction | `grep -oP`, absent from BSD grep: exit 2 on macOS | .NET regex, first match | the regex `https://[^\s]+\.pages\.dev` in JavaScript, first match over stdout then stderr; no grep |
| DR-12 | deploy failure report | `Deployment failed or URL not found` and the output on stdout | thrown with the output appended | `ERROR: Deployment failed or URL not found` then the output on stderr, credentials redacted (DR-21), exit 1, publish dir removed |
| DR-13 | `size_kb` | `du -sk`: integer disk-usage blocks | apparent bytes / 1024, two decimals | apparent byte sum of every file under the publish dir / 1024, rounded to two decimals, a JSON number |
| DR-14 | record key order and escaping | fixed order timestamp, document, url, size_kb; no escaping (a quote or backslash in the path breaks the line) | hashtable order (measured: timestamp, document, size_kb, url); escaped | `JSON.stringify` of keys in the order timestamp, document, url, size_kb |
| DR-15 | record line ending and encoding | LF | Add-Content: CRLF on Windows, ANSI default on 5.1 | UTF-8, one line ending in LF, appended |
| DR-16 | timestamp | `date -u` ISO seconds and Z | .NET custom format whose `:` is the culture time separator | ISO 8601 UTC to the second with Z, culture-free |
| DR-17 | colour | plain | green and cyan Write-Host | plain text, no ANSI escapes, including the echoed output of a failed deploy, whose ANSI escape sequences are removed before the DR-21 redaction |
| DR-18 | unexpected deploy error (spawn fails) | set -e exit, publish dir left | thrown, publish dir left | `ERROR: wrangler could not be run: <message>` on stderr, exit 1, publish dir removed |
| DR-19 | extra arguments | ignored | binding error, exit 1 | usage line on stderr, exit 1, nothing created |
| DR-20 | Node missing | `node` not found under set -e, exit 127 | CommandNotFoundException, exit 1 | launchers print the D-LAUNCH refusal line on stderr, exit 1, create nothing |
| DR-21 | credentials in output | wrangler output echoed unfiltered | same | the environment is passed to wrangler unchanged and never printed; on failure every occurrence of the value of `CLOUDFLARE_API_TOKEN` or `CLOUDFLARE_API_KEY` (when set and at least 8 characters) in the echoed output becomes `[REDACTED]` |

Kept identical in both twins and in the port: the publish dir
`.cloudflare-publish` and the history file `docs/ai/published/history.jsonl`
are relative to the current directory; a pre-existing `.cloudflare-publish`
is removed before conversion; the project name is `aai-reports`; success
exits 0; every failure exits 1 except DR-01's help form.

### D-MOD. The module

`.aai/scripts/cloudflare-share.mjs`, Node stdlib only, no side effect on
import (the CLI runs only when the file is the entry point). It holds the
literal constants `const PUBLISH_DIR = '.cloudflare-publish';`,
`const PROJECT_NAME = 'aai-reports';`,
`const HISTORY_FILE = 'docs/ai/published/history.jsonl';` and
`const URL_RE = /https:\/\/[^\s]+\.pages\.dev/;`, and exports:

- `parseArgs(argv)`: `{ doc }`, `{ help: true }` or `{ error }` (DR-01, DR-19).
- `branchName(name)`: DR-09 sanitising; `''` when nothing is left.
- `extractUrl(text)`: the first `URL_RE` match or `null` (DR-11).
- `redact(text, env)`: DR-21.
- `historyLine({ timestamp, document, url, sizeKb })`: the DR-14 JSON line
  without its newline; the object literal is written
  `{ timestamp, document, url, size_kb: sizeKb }`.
- `findWrangler(env, platform, fs)`: DR-07 resolution, a path or `null`.
- `deployCommand(wranglerPath, branch, platform)`:
  `{ command, args, shell }` with args
  `['pages', 'deploy', PUBLISH_DIR, '--project-name=' + PROJECT_NAME, '--branch=' + branch]`;
  `shell: true` only for a `.cmd` or `.bat` path on win32, with the quoted
  path and the same arguments joined into one command string; a resolved
  path holding `"`, `%` or `!` returns `null`, which `run` reports as
  `ERROR: wrangler path cannot be run safely: <path>` on stderr with exit 1.
- `run(opts, deps)`: the whole flow, returning the exit code. `deps` holds
  `cwd`, `env`, `platform`, `fs`, `convert(doc, dir)`, `deploy(cmd, env)`,
  `gitToplevel(cwd)`, `now()`, `out(line)` and `err(line)`. `convert`,
  `deploy` and `gitToplevel` return `{ status, stdout, stderr }` or throw;
  the CLI wires them to `spawnSync` (`process.execPath` running
  `share-convert.mjs` next to the module; the `deployCommand` result with the
  inherited environment). Tests pass fakes; no test runs a real `wrangler`.

The flow: parse; check the document (DR-02, DR-03); resolve wrangler (DR-06,
DR-07); derive the branch (DR-08, DR-09); remove and recreate the publish dir;
print `Converting Markdown to HTML...`; convert and forward share-convert's
stdout lines (DR-05); print `Deploying to Cloudflare Pages (branch: <b>)...`;
deploy (DR-10, DR-12, DR-18); extract the URL (DR-11); size (DR-13); remove
the publish dir; append the record (DR-14 to DR-16); print the report. The
publish dir is removed on every exit path after it was created.

### D-OUT. The success output contract (stdout, unchanged from both twins)

```
Converting Markdown to HTML...
<share-convert.mjs stdout lines, forwarded unchanged>
Deploying to Cloudflare Pages (branch: <branch>)...

Document published successfully!

Document: <name>
URL: <url>

Click to open: <url>

```

Nothing is written to stderr on success.

### D-LAUNCH. The launchers

Both keep their names, mode 100644, ASCII, at most 20 lines, no policy.

- `cloudflare-share.sh`: first line `#!/bin/sh`, one `# Launcher:` comment
  naming the module and RFC-0017 phase 5, one `# Usage:` comment, then
  `MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/cloudflare-share.mjs"`,
  `exec node "$MODULE" "$@"` when `node` is on PATH and the module exists,
  else the refusal line on stderr and `exit 1`.
- `cloudflare-share.ps1`: the two comments,
  `[CmdletBinding()] param([Parameter(Position = 0)][string]$DocumentPath)`
  (not mandatory, so no prompt), `& node @nodeArgs` with the document
  appended only when non-empty, `exit $LASTEXITCODE`; else the refusal line
  through `[Console]::Error.WriteLine` and `exit 1`.
- The refusal line (both):
  `cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run.`
- Neither launcher nor the module holds the word `grep`.

### D-CALLERS

`.aai/SKILL_SHARE.prompt.md`, the four harness wrappers and
`share-convert.mjs` stay byte for byte as at `bd519bb3`: the prompt's agent
flow works on macOS (it uses `tr` and `sed`, not `grep -oP`), and its line 72
stays true. The prompt's agent flow writes `{timestamp, document, url}`; the
module's record carries the same three keys first, in the same order, plus
`size_kb` (the multi-writer seam, TEST-3420).

### D-SECRET

The module reads no credential and prints no environment value. Wrangler
reads `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (or its own login) from
the environment it inherits unchanged. DR-21 redacts on the one path that
echoes foreign output.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-cloudflare-share` with globs
  `.aai/scripts/cloudflare-share.*`, `.aai/scripts/share-convert.mjs`, every
  `.aai/scripts/lib/*` file the module imports, `.aai/system/PROFILES.yaml`,
  `.github/workflows/ps1-quality.yml`,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-cloudflare-share.sh`,
  `tests/skills/lib/cloudflare-share.test.mjs`,
  `tests/skills/cloudflare-share.Tests.ps1`, and every `tests/skills/lib/*`
  file the suite or the Pester file sources or reads (shared test libs).
- `tests/skills/suite-weights.tsv`: `# sample aai-cloudflare-share fallback unsampled (new suite of cloudflare-share-on-node; no successful observation)`
  and `aai-cloudflare-share<TAB>212`.
- `tests/skills/test-aai-hygiene-pack.sh`: the row-count pins in
  `test_090_suite_map_pin` and `test_129_mutation_gate_suite_registration`
  move from 127 to 128, with the message naming the cloudflare-share suite.
- Nested-suite lint: no new allowlist row; cross-suite calls are selector
  form (`test-aai-expert-fetch.sh test_2624_inventory_matches_tree`,
  `test-aai-layer-profiles.sh test_manifest_conformance`,
  `test-aai-win-fallback.sh test_034`).
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: a row for the new suite
  only if `check-cd-subshell-leak.mjs` asks, recorded with `--record`.
- `.github/workflows/ps1-quality.yml`: `- '.aai/scripts/cloudflare-share.mjs'`
  in both the push and the pull_request path lists, after
  `migrate-state-to-local.mjs`; the `tests/skills/*.Tests.ps1` glob already
  covers the Pester file.
- `.aai/system/PROFILES.yaml`: `  - .aai/scripts/cloudflare-share.mjs` under
  `extended:`, next to the two launchers.
- `docs/TECHNOLOGY.md` line 37: `(.aai/scripts/cloudflare-share.mjs with its
  .sh/.ps1 launchers, /aai-share)`, in the file's existing code-span style.

### D-RFC. RFC-0017

- Inventory: the `cloudflare-share` row is removed (no longer a pair: the
  module exists). Every other row stays byte for byte.
- Phase 5 row: one sentence after the sixth-slice sentence and before the
  remaining-scripts-plan sentence:
  `The seventh slice [moved cloudflare-share to Node](../issues/CHANGE-DRAFT-cloudflare-share-on-node.md): one module with an injectable deploy seam behind thin launchers, which ends the macOS grep -oP failure and the twins' drift.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  the link at merge; checks match only the suffix `cloudflare-share-on-node.md`.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(scripts): cloudflare-share runs on one Node module`
  naming the macOS fix, every DR decision that changes what a user sees
  (DR-01, DR-02, DR-05, DR-06, DR-08, DR-10, DR-12, DR-13, DR-14, DR-19,
  DR-20), and the before and after code lines.

### D-SUITE

One new suite `aai-cloudflare-share` (`tests/skills/test-aai-cloudflare-share.sh`)
holds every row, using ride 1's `run_node_tests` (a pattern that matches no
passing case fails) and `need_tool` (absent tool fails on CI, named
SKIP-CASE locally). Every fixture is a fresh temp directory; every CLI case
puts a stub `wrangler` first on PATH and no case can reach the network. The
Pester file launches the `.ps1` with the engine running the test
(`(Get-Process -Id $PID).Path`), so the hosted 5.1 step tests 5.1 and the
pwsh 7 step tests pwsh 7; on Windows its stub is a `wrangler.cmd`, which
exercises DR-07 for real.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02, Spec-AC-08 and Spec-AC-09.
- Intake AC-002 maps to Spec-AC-10.
- Intake AC-003 maps to Spec-AC-03, Spec-AC-04, Spec-AC-05, Spec-AC-06 and
  Spec-AC-07.
- Intake AC-004 maps to Spec-AC-08, Spec-AC-09, Spec-AC-11 and hosted check
  H1 (the native Windows Pester jobs under Windows PowerShell 5.1 and pwsh 7
  run `tests/skills/cloudflare-share.Tests.ps1`).
- Intake AC-005 maps to Spec-AC-12, Spec-AC-13, Spec-AC-14 and Spec-AC-15.

## Constitution deviations

None. Article 4 (degrade and report): every failure names its cause on
stderr and exits 1 instead of dying in grep or leaving the publish dir.
Article 5 (additive first): both command names, arguments, exit codes and
the success output stay; the changed failure behaviours are listed in D-DRIFT
and in the CHANGELOG. Article 2 (simplicity): no new flag, environment
variable or dependency; the deploy seam is a function argument, not a
runtime switch.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Importing .aai/scripts/cloudflare-share.mjs writes nothing and exports the D-MOD functions; run with fake convert, deploy and gitToplevel in a temp directory calls deploy exactly once with the deployCommand of the resolved stub path and args pages deploy .cloudflare-publish --project-name=aai-reports --branch=fixture, and spawns no process. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3416.txt | — | — |
| Spec-AC-02 | WHEN the module CLI runs in a committed temp git repo named My Repo with a stub wrangler first on PATH, the system SHALL exit 0, print exactly the D-OUT lines with branch my-repo and the stub URL on stdout, print nothing on stderr, append one history line and leave no .cloudflare-publish. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3417.txt | — | — |
| Spec-AC-03 | The node:test cases DR-01, DR-02, DR-03, DR-04, DR-05 and DR-19 pass and each asserts the D-DRIFT decision of its row: stream, exact line and exit code, and for every failure no .cloudflare-publish and no history file left behind. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3418.txt | — | — |
| Spec-AC-04 | The node:test cases DR-06, DR-07, DR-08, DR-09, DR-10, DR-11, DR-12 and DR-18 pass and each asserts the D-DRIFT decision of its row, including that a non-zero wrangler status whose output holds a pages.dev URL exits 1 and records nothing. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3419.txt | — | — |
| Spec-AC-05 | The node:test cases DR-13, DR-14, DR-15, DR-16 and DR-17 pass; the record of a path holding a double quote and a backslash parses as JSON with keys in the order timestamp, document, url, size_kb, and its first three keys equal the keys of the SKILL_SHARE step 4 record. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3420.txt | — | — |
| Spec-AC-06 | The node:test case DR-21 passes: with CLOUDFLARE_API_TOKEN and CLOUDFLARE_API_KEY set and a failing stub that prints both values, stderr holds REDACTED twice and neither value, stdout holds neither, and the stub received both values in its environment. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3421.txt | — | — |
| Spec-AC-07 | Every DR id in the D-DRIFT table names exactly one node:test case whose name begins with that id, and the test file names no DR id the table lacks. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3422.txt | — | — |
| Spec-AC-08 | cloudflare-share.sh is at most 20 lines, ASCII, mode 100644, first line #!/bin/sh, per D-LAUNCH; run by bash, sh and dash from the Spec-AC-02 fixture it meets the D-OUT contract with exit 0; with PATH holding no node it prints the D-LAUNCH refusal line on stderr only, exits 1 and creates nothing (DR-20). | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3423.txt | — | — |
| Spec-AC-09 | cloudflare-share.ps1 is at most 20 lines, ASCII, mode 100644, per D-LAUNCH; under pwsh it meets the D-OUT contract with a document path holding a space and exits 1 with the usage line and no prompt when given no argument under -NonInteractive; tests/skills/cloudflare-share.Tests.ps1 passes under Pester 5 with at least 5 cases and none failed or skipped. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3424.txt; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3425.txt | — | — |
| Spec-AC-10 | WHEN cloudflare-share.sh runs with a PATH whose grep rejects -P (exit 2), the system SHALL exit 0, report and record the stub URL and leave no .cloudflare-publish; neither launcher nor the module holds the word grep. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3426.txt | — | — |
| Spec-AC-11 | WHEN aai-sync.sh --profile extended installs into a scratch git target whose path holds a space, the target SHALL hold the module, both launchers and share-convert.mjs, and the target's own launchers (sh under bash; ps1 under pwsh when present) SHALL publish through the stub with exit 0 and one record each; a --profile core install SHALL hold none of the three cloudflare-share files. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3427.txt | — | — |
| Spec-AC-12 | Wiring per D-WIRE: select-suites selects aai-cloudflare-share for each of the module, both launchers, the node:test file and the Pester file; suite-weights holds the row; both hygiene-pack pins read 128 and their selectors pass; nested-suite lint with its allowlist and check-cd-subshell-leak exit 0; check-test-registration exits 0; PROFILES lists the module once under extended and layer-profiles test_manifest_conformance passes; both ps1-quality path lists name the module and win-fallback test_034 passes. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3428.txt | — | — |
| Spec-AC-13 | test-aai-expert-fetch.sh test_2624_inventory_matches_tree exits 0, the inventory holds no cloudflare-share row, the phase 5 row keeps status in progress and holds the D-RFC sentence once with a link ending cloudflare-share-on-node.md, and docs/TECHNOLOGY.md names cloudflare-share.mjs. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3429.txt | — | — |
| Spec-AC-14 | Measured with the plan's method on the delivered tree, cloudflare-share.sh has at most 6 code lines and cloudflare-share.ps1 at most 10, each at most 20 lines in total; the suite prints before 98 and the after launcher sum, and the module's code lines. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3430.txt | — | — |
| Spec-AC-15 | The callers keep working unchanged: .aai/SKILL_SHARE.prompt.md still names both launchers on its Scripts line, every .aai/scripts path that SKILL_SHARE or any of the four aai-share wrappers names exists in the tree, and share-convert.mjs is still the converter the module runs. | done | docs/ai/tdd/cloudflare-share-on-node/green/suite.log; docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3431.txt | — | — |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/cloudflare-share-on-node/red/` before its change, GREEN under
`green/`, and one mutation record per row (`node .aai/scripts/mutation-run.mjs`)
before the run's hand-off.

1. Run 1, Spec-AC-01, 02, 07: the suite skeleton, the node:test file with the
   seam and success cases and all 21 DR case names, then the module (D-MOD,
   D-OUT).
2. Run 2, Spec-AC-03, 04, 05, 06: the DR cases, module behaviour per D-DRIFT.
3. Run 3, Spec-AC-08, 09, 10: the two launchers (D-LAUNCH), the Pester file,
   the BSD-grep case.
4. Run 4, Spec-AC-11, 12: the scratch install, the D-WIRE edits.
5. Run 5, Spec-AC-13, 14, 15: RFC-0017 and TECHNOLOGY (D-RFC), the
   measurement, the caller freeze; then the CHANGELOG entry after LOOP
   COMPLETE.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3416 | Spec-AC-01 | unit | tests/skills/test-aai-cloudflare-share.sh | test_3416_seam runs run_node_tests TEST-3416 on tests/skills/lib/cloudflare-share.test.mjs: an import in a child node with a temp cwd writes nothing to stdout, stderr or the cwd and exposes parseArgs, branchName, extractUrl, redact, historyLine, findWrangler, deployCommand and run; run with recording fakes calls convert once with the document and .cloudflare-publish and deploy once with the D-MOD command for branch fixture | `sed:s/const PROJECT_NAME = 'aai-reports'/const PROJECT_NAME = 'aai-report'/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3417 | Spec-AC-02 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3417_cli_success runs run_node_tests TEST-3417: the module CLI in a committed temp repo named My Repo with a stub wrangler first on PATH (prints the URL line, records its argv) gives exit 0, stdout equal to the D-OUT lines for branch my-repo, empty stderr, one history line, no .cloudflare-publish, and the stub argv equal to the D-MOD args | `sed:s/Document published successfully!/Document published!/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3418 | Spec-AC-03 | unit | tests/skills/test-aai-cloudflare-share.sh | test_3418_args_drift runs run_node_tests TEST-3418: cases DR-01 (no argument; -h and --help), DR-02, DR-03 (a directory; a literal name holding brackets that exists), DR-04 (doc.md and notes.markdown), DR-05 (a convert fake exiting 3), DR-19 (two arguments), each asserting the decided stream, line and exit code and no publish dir or history left | `sed:s/ERROR: Document not found: /Document not found: /` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3419 | Spec-AC-04 | unit | tests/skills/test-aai-cloudflare-share.sh | test_3419_deploy_drift runs run_node_tests TEST-3419: DR-06 (empty PATH dir: three stderr lines, no convert call, no publish dir), DR-07 (findWrangler and deployCommand for win32 with PATHEXT and a wrangler.cmd; POSIX executable bit), DR-08 (a non-git temp dir named Share Dir gives share-dir; a cwd whose name sanitises to empty refuses), DR-09 (Cafe with an acute e gives caf-), DR-10, DR-11 (ANSI-coloured output, two URLs, none), DR-12, DR-18 (deploy fake throws) | `sed:s/Then run: wrangler login/Then run: wrangler auth/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3420 | Spec-AC-05 | unit | tests/skills/test-aai-cloudflare-share.sh | test_3420_record_drift runs run_node_tests TEST-3420: DR-13 (two files of 1000 and 1300 bytes give 2.25), DR-14 (a path holding a double quote and a backslash round-trips; key order), DR-15 (appended line ends in LF only, UTF-8 bytes of a non-ASCII path), DR-16 (a fixed now() gives 2026-01-02T03:04:05Z), DR-17 (no ESC byte on stdout); the first three keys equal the keys parsed from the SKILL_SHARE step 4 echo line | `sed:s/{ timestamp, document, url, size_kb: sizeKb }/{ timestamp, document, size_kb: sizeKb, url }/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3421 | Spec-AC-06 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3421_secrets runs run_node_tests TEST-3421: case DR-21 runs the CLI with two fixture credential values in the environment and a stub that writes its environment values to a file and prints both values then exits 1; stderr holds [REDACTED] twice and neither value, stdout neither, the stub file both; a 7-character value is not redacted | `sed:s/\[REDACTED\]/[HIDDEN]/` on .aai/scripts/cloudflare-share.mjs | green |
| TEST-3422 | Spec-AC-07 | inspection | tests/skills/test-aai-cloudflare-share.sh | test_3422_drift_coverage reads the DR ids of the D-DRIFT table of this spec (found by its id spec-cloudflare-share-on-node under docs/specs) and the test names of tests/skills/lib/cloudflare-share.test.mjs; each table id begins exactly one test name and no test name begins with an id the table lacks; positive control: a scratch copy with DR-13 renamed is reported | `sed:s/'TEST-3420 DR-13 /'TEST-3420 DR-31 /` on tests/skills/lib/cloudflare-share.test.mjs | green |
| TEST-3423 | Spec-AC-08 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3423_sh_launcher checks the D-LAUNCH shape (at most 20 lines, ASCII, git mode 100644, #!/bin/sh, the refusal line text), runs the launcher by absolute path under bash, sh and dash (SKIP-CASE per absent shell) from a My Repo fixture with the stub first on PATH: D-OUT on stdout, empty stderr, exit 0; then run_node_tests TEST-3423 runs case DR-20, which spawns /bin/sh on the launcher with PATH holding only a scratch bin with a dirname link and the stub (no node): stderr equals the refusal line, stdout empty, exit 1, no publish dir and no history | `sed:s/exec node /exec nodejs /` on .aai/scripts/cloudflare-share.sh | green |
| TEST-3424 | Spec-AC-09 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3424_ps1_launcher (need_tool pwsh) checks the D-LAUNCH shape of the ps1 (at most 20 lines, ASCII, mode 100644, the param line, no Mandatory), runs pwsh -NoProfile -NonInteractive -File on it from a fixture named My Repo with the document path my doc.md: D-OUT, exit 0, one record; with no argument: the usage line on stderr, exit 1, no prompt, no publish dir | `sed:s/exit \$LASTEXITCODE/exit 0/` on .aai/scripts/cloudflare-share.ps1 | green |
| TEST-3425 | Spec-AC-09 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3425_pester (need_tool pwsh; SKIP-CASE without Pester 5 locally, as SPEC-0273 TEST-3388) runs Invoke-Pester on tests/skills/cloudflare-share.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 5; the cases build TestDrive git fixtures with a local identity and a stub (wrangler.cmd on Windows, an executable wrangler script elsewhere) first on PATH and cover success with a spaced path, -DocumentPath by name, no argument, a missing document, a failing stub and a PATH without node (the D-LAUNCH refusal line, DR-20), each asserting stream, exit code and no publish dir | `sed:s/\[Parameter\(Position = 0\)\]/[Parameter(Position = 0, Mandatory = $true)]/` on .aai/scripts/cloudflare-share.ps1 | green |
| TEST-3426 | Spec-AC-10 | integration | tests/skills/test-aai-cloudflare-share.sh | test_3426_bsd_grep puts a grep shim that exits 2 on any -P argument and a stub wrangler first on PATH, runs the sh launcher under bash in the My Repo fixture: exit 0, the URL line, one record, no .cloudflare-publish; requires no word grep in the module or either launcher; RED on the baseline (exit 2) | `sed:s/# Launcher:/# Launcher (no grep):/` on .aai/scripts/cloudflare-share.sh | green |
| TEST-3427 | Spec-AC-11 | e2e | tests/skills/test-aai-cloudflare-share.sh | test_3427_downstream_install runs aai-sync.sh --profile extended into a scratch git target named with a space, requires the module, both launchers and share-convert.mjs there, runs the target's own launcher from inside the target under bash and (when pwsh is present) the target's ps1 under pwsh, each with the stub first on PATH: exit 0, the URL line, one record each; an aai-sync.sh --profile core target holds no cloudflare-share file | `sed:s/exec node /exec nodejs /` on .aai/scripts/cloudflare-share.sh | green |
| TEST-3428 | Spec-AC-12 | inspection | tests/skills/test-aai-cloudflare-share.sh | test_3428_wiring pipes each of the five files to node .aai/scripts/select-suites.mjs --files-from - and requires aai-cloudflare-share; requires the suite-weights row; runs test-aai-hygiene-pack.sh test_090_suite_map_pin and test_129_mutation_gate_suite_registration (exit 0); runs nested-suite-lint with its allowlist, check-cd-subshell-leak and check-test-registration (exit 0); requires the module once under extended in PROFILES and runs test-aai-layer-profiles.sh test_manifest_conformance (exit 0); requires the module in both ps1-quality path lists and runs test-aai-win-fallback.sh test_034 (exit 0) | `sed:s/      - \.aai\/scripts\/cloudflare-share\.\*/      - .aai\/scripts\/cloudflare-share-gone.*/` on tests/skills/suite-map.yaml | green |
| TEST-3429 | Spec-AC-13 | inspection | tests/skills/test-aai-cloudflare-share.sh | test_3429_rfc runs test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires no cloudflare-share row in the inventory table, the phase 5 row with status in progress and the D-RFC sentence exactly once with a link ending cloudflare-share-on-node.md, and cloudflare-share.mjs on the docs/TECHNOLOGY.md Cloudflare line | `sed:s/The seventh slice \[moved cloudflare-share to Node\]/The seventh slice [moved cloudflare-share]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3430 | Spec-AC-14 | inspection | tests/skills/test-aai-cloudflare-share.sh | test_3430_line_budget counts code lines with grep -cvE on the hash comment and blank pattern under bash with /usr/bin/grep when present: the sh launcher at most 6, the ps1 at most 10, each at most 20 in wc -l, and prints before 98, the after launcher sum and the module's code lines | `patch:docs/ai/tdd/spec-cloudflare-share-on-node/mutation-TEST-3430.patch` on .aai/scripts/cloudflare-share.sh | green |
| TEST-3431 | Spec-AC-15 | inspection | tests/skills/test-aai-cloudflare-share.sh | test_3431_callers requires the SKILL_SHARE Scripts line to name .aai/scripts/cloudflare-share.sh and .aai/scripts/cloudflare-share.ps1, every .aai/scripts/ path token in SKILL_SHARE and in .claude, .agents, .codex and .gemini skills/aai-share/SKILL.md to exist, and the module to name share-convert.mjs; positive control: a scratch copy of the prompt naming a missing script is reported | `sed:s/\.aai\/scripts\/cloudflare-share\.ps1/.aai\/scripts\/cloudflare-share-gone.ps1/` on .aai/SKILL_SHARE.prompt.md | green |

Test counts by type: unit 4, integration 7, inspection 5, e2e 1 (16 rows;
the DR cases are 21 node:test cases inside TEST-3418 to TEST-3423).

Seams crossed (Principle 2): the module and the real `share-convert.mjs`
(TEST-3417, TEST-3423, TEST-3427, no convert fake); each launcher under every
engine that runs it (TEST-3423, TEST-3424, TEST-3425; Windows PowerShell 5.1
and pwsh 7 on native Windows with a real `.cmd` shim in H1); the history file
that SKILL_SHARE's agent flow also writes (TEST-3420 reads the prompt's key
list); aai-sync's profile copy to the target's own launchers (TEST-3427); the
RFC inventory read by SPEC-0249's check (TEST-3429); select-suites, the
hygiene pins, the nested-suite lint, the cd ratchet and the registration
check reading the new suite (TEST-3428); the ps1-quality path lists read by
win-fallback test_034 (TEST-3428).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-cloudflare-share.sh`
  exits 0 (16 rows), plus the touched and selected suites:
  test-aai-hygiene-pack.sh, test-aai-layer-profiles.sh,
  test-aai-expert-fetch.sh, test-aai-win-fallback.sh, test-aai-suite-select.sh,
  test-aai-share.sh, test-aai-sync.sh (if selected), test-aai-ps1-quality.sh
  (if selected). No full sweep is required by this spec; Validation decides
  its own.
- Callers unchanged (D-CALLERS), recorded in the validation report:
  `git diff --stat bd519bb3 -- .aai/SKILL_SHARE.prompt.md .aai/scripts/share-convert.mjs '.*/skills/aai-share/*' .aai/AGENTS.md`
  prints nothing, and no `.aai/*.prompt.md` differs from `bd519bb3`.
- `env -u AAI_ROLE node --test tests/skills/lib/cloudflare-share.test.mjs`
  exits 0 with at least 24 passing cases (21 DR cases plus TEST-3416, 3417).
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell 5.1
  and pwsh 7 with `cloudflare-share.Tests.ps1` discovered and not skipped.

## Evidence contract

ref_id `cloudflare-share-on-node`; RED, GREEN and mutation evidence under
`docs/ai/tdd/cloudflare-share-on-node/` (gitignored); each AC row's Evidence
names its green log and mutation record; the validation report and review
verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity and the `.cmd` shim path are proven only on
  the hosted job (H1); Planning had no Windows engine.
- No test talks to Cloudflare: the real Wrangler output format is assumed to
  keep a `https://...pages.dev` URL in its output (as both twins assumed).
- A `.cmd` resolved from a PATH entry holding `"`, `%` or `!` is not quoted
  safely by cmd.exe (`!` expands under delayed expansion); such PATH entries
  are not supported (the module refuses a resolved path holding any of them).
- The changed failure behaviours (D-DRIFT rows marked in D-RFC) are visible
  to a downstream wrapper that parsed stdout for error text; the CHANGELOG
  names them.
- The SKILL_SHARE agent flow keeps writing records without `size_kb`; no
  reader exists, so the two shapes are recorded, not unified.

Registry items closed by this scope: none.
