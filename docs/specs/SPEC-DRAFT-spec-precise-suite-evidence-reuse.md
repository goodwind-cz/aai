---
id: spec-precise-suite-evidence-reuse
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: e5bcd66c82de515fd584d715fe492ff2c020e5936e2e8d03280479c43628da58
ceremony_level: 2
links:
  requirement: precise-suite-evidence-reuse
  rfc: RFC-0017
  pr: []
  commits: []
---

# Precise reuse of local suite results: a complete input identity per suite, reported as reused with provenance, never as a new execution

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-DRAFT-precise-suite-evidence-reuse.md
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (section 3, "Cache only deterministic checks with a complete input
  identity"; Rollout Status phase 5, first slice; the umbrella stays open)
- Prior art: SPEC-0213 (CHANGE-0205, CI carry-forward over a push delta,
  `inert_globs` and `carry_forward_globs` in the suite map), SPEC-0206 (the
  textual dependency-graph prototype measured as low leverage for selection),
  SPEC-0247 (Node-first slice with a Pester twin and post-PR native Windows
  evidence), SPEC-0264 (house example of a frozen spec)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 24
  baseline, Node 22 floor; Bash 3.2 and GNU Bash for suites)
- Baseline commit: `773557ee` (main at planning time)

## Implementation strategy

- Strategy: tdd
- Rationale: the new behavior is a correctness gate whose main hazard is a
  false hit, i.e. a silent pass. Every identity component must be observed
  turning a hit into a miss under a mutation before its green counts, so RED
  first per row and mutation gate v1 apply. Every row has an observable RED on
  the baseline (the helper, the manifest and the framework lines do not exist).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound; edits tests/skills/test-framework.sh (the
  funnel CI runs), select-suites.mjs (CI selection), two core prompts,
  PROFILES.yaml, the suite map, the prompt-diet ledger and a workflow path
  filter; mutation runs temporarily rewrite these files; the measurement in
  D11 applies a scratch edit and must not touch the shared main checkout,
  which other sessions use. No file is in `protected_paths_l3`
  (docs/ai/docs-audit.yaml), so not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the list in "Files Implementation touches" below.
- Code review required: true.

## Assumptions (autopilot, recorded instead of asked)

- A1 Reuse lives in the per-suite dispatch of `tests/skills/test-framework.sh`
  (selected mode), reached through the canonical runner on every platform
  (`aai-run-tests.ps1` delegates to `aai-run-tests.sh`, which runs the
  framework). A direct single-suite invocation
  (`aai-run-tests.sh bash tests/skills/test-aai-x.sh`) always executes. The
  owner may have pictured the hook inside `aai-run-tests.sh`; D1 says why not.
- A2 Ceremony level 2, not 3: no protected path is touched. The change
  weakens a freshness rule, so review may raise it (WORKFLOW.md allows an
  upward re-classification as a finding).
- A3 Reuse is on by default for local selected runs; `AAI_SUITE_REUSE=0`
  turns it off (the intake asks for an explicit opt-out, not an opt-in).
- A4 One line is added to both path lists of
  `.github/workflows/ps1-quality.yml` so a future edit of the helper alone
  still runs the native Windows Pester job. No job, step or other trigger
  changes. If the owner reads "CI unchanged" as "no workflow byte changes",
  drop the line and accept that helper-only edits skip Windows.
- A5 The measurement uses three samples per mode, not the five the RFC's
  success-criteria preamble proposes, because one sample of the
  representative round costs several minutes per mode (D11).
- A6 The initial manifest qualifies at least five suites chosen by the
  implementer with the help of `suite-reuse.mjs explain`; the owner did not
  name which.

## What Planning measured

### M1 Where suites run

- `aai-run-tests.ps1` resolves WSL or Git Bash and launches
  `.aai/scripts/aai-run-tests.sh <cmd>` (header lines 3 to 6 and 52 to 60);
  there is no second suite runner on Windows.
- Intermediate validation rounds run
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh
  --skill <a> --skill <b> ...` (VALIDATION.prompt.md step 5 c2); the full
  sweep before close is the same command without `--skill`. CI selected jobs
  run the framework with `--skill`, full jobs without
  (.github/workflows/skill-suite.yml lines 241 to 333).
- The wrapper never isolates a framework invocation
  (`aai_iso_is_suite_run` opts the framework out); the framework isolates
  each suite itself in `suite_prepare` (a `git clone --local` seeded with
  tracked edits, untracked-not-ignored files and the gitignored seed list
  `docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json`,
  overridable by `AAI_TEST_ISOLATION_SEED`). Under isolation a suite can see
  only those repository files, which bounds the repository side of any
  identity.
- `suite_report` writes one line per suite to `$RUN_DIR/metrics.jsonl`
  with `status`, `exit_code`, `tripwire_attested` and
  `tripwire_hasher_degraded`; `.result` is PASS, SKIP (exit 42) or FAIL. The
  run ledger line in `docs/ai/tests/test-runs.jsonl` carries `total`,
  `passed`, `failed`, `skipped` and the isolation and seeding counts; no
  script parses its pass counts (`lib/pr-sweep.mjs`, `recheck.mjs`,
  `orchestration-dispatch.mjs` only list the path).
- Other `--skill` callers: `release-dry-run.mjs` `invocation()` runs
  `tests/skills/test-framework.sh --skill <name>` for a changed suite.
  `mutation-run.mjs` runs `bash <wrapper> bash <suite> <selector>` directly,
  never the framework, so it is not affected.

### M2 What the suite map can and cannot declare

- `tests/skills/suite-map.yaml` globs were written for selection and are
  generous on purpose; they omit shared code because
  `full_run_triggers.shared_lib_globs` (`.aai/scripts/lib/**`) escalates
  CI to a full run instead. Globs alone are therefore not a complete input
  set.
- `select-suites.mjs` has no exports and runs `runMain` at module load, so
  its parser cannot be imported today. 24 other `.aai/scripts/*.mjs` use the
  `isMain` realpath guard (`aai-issues.mjs:375`, `branch-guard.mjs:753`).
- `lib/tree-hash.mjs` `listTreeFiles` already lists tracked plus
  untracked-not-ignored files with `git ls-files -z`, the same set the
  isolated checkout is seeded with.

### M3 Closure prototype (scratch, not shipped)

A scratch prototype over all 120 `tests/skills/test-aai-*.sh` files:

- Following every path literal transitively, including literals inside
  production scripts, reached 409 to 421 files and the whole `docs/` tree for
  most suites (`aai-docs-content`, `aai-spec-lint`, `aai-hygiene-pack`,
  `aai-check-state`, `aai-ride-status`). Production scripts name default
  corpus paths that a fixture-driven suite never reads from the real tree, so
  that rule turns nearly every edit into a miss. Rejected (D12).
- Following only test-side literals plus ESM relative imports gave closures
  of 2 to 27 files for the 52 suites whose test-side text has no network or
  remote marker.
- A text scan for live markers (`gh api`, `gh pr`, `curl`, `ls-remote`,
  `git push`, `git fetch`, URLs) fires on assertion strings (for example
  `test-aai-hygiene-pack.sh:83` greps prompts for `gh pr create`), so a
  marker hit cannot be a mechanical refusal without disqualifying the suites
  worth reusing. Live effects are therefore a reviewed declaration (D3) and
  the scan is advisory (`explain`).

### M4 Prompt bytes and ids

- `cat .aai/*.prompt.md | /usr/bin/wc -c` = 373456; TEST-012 pin
  (`want_growth` in tests/skills/test-aai-prompt-diet.sh line 1027) = 65249.
- `.aai/SKILL_VERIFY.prompt.md` 3726 B, `.aai/VALIDATION.prompt.md` 24944 B.
- Highest TEST-3xxx in docs/specs: TEST-3164. This spec uses TEST-3165 to
  TEST-3190.

### M5 Representative round

For a remediation delta of `.aai/scripts/ride-status.mjs` plus
`tests/skills/lib/ride-status.test.mjs` (the PR #520 shape),
`select-suites.mjs --files-from` gives CORE `aai-check-state`,
`aai-docs-content`, `aai-spec-lint`, `aai-hygiene-pack` and SELECTED
`aai-ride-status`, `aai-win-fallback`, `aai-prompt-diet` (7 suites;
measured CI weights 3, 212, 38, 97, 212, unlisted, 8 seconds in
tests/skills/suite-weights.tsv).

## Decisions

### D1 Hook point: the framework's per-suite dispatch, one Node helper

The reuse decision is made in `tests/skills/test-framework.sh` after
discovery and before execution, and the record is written after
`suite_report`. Reasons: the framework is the unit that already owns the
per-suite isolation, the per-suite verdict (tripwire, seeding) and the run
ledger; the Windows launcher reaches it through the POSIX wrapper, so one code
path serves every platform; and `aai-run-tests.sh` and `.ps1` stay untouched,
which keeps the later phase-5 runner migration separate. All identity and
store logic lives in one Node module, `.aai/scripts/suite-reuse.mjs` (Node
stdlib only, at most 600 lines), with four subcommands: `check`, `record`,
`forget`, `lint`, plus a read-only `explain` that prints a suite's identity
inputs and advisory marker hits. The framework calls it with argument arrays
and degrades to "reuse off" when `node` or the helper is absent (a fixture
framework copied without the helper keeps working).

### D2 Code reuse

- `select-suites.mjs` gains the `isMain` realpath guard (the house pattern
  `const isMain = process.argv[1] && realOrResolve(process.argv[1]) ===
  realOrResolve(fileURLToPath(import.meta.url));`) and calls
  `if (isMain) runMain(` instead of the bare call, plus one line
  `export { parseSuiteMap, matchesGlob };`. CLI behavior is
  unchanged (the existing `aai-suite-select` suite stays green).
- The helper imports `parseSuiteMap` and `matchesGlob` from it, and
  `listTreeFiles` from `lib/tree-hash.mjs` for every file enumeration. No
  second glob matcher, map parser or tree lister is written.

### D3 What "declared" means (qualification)

- A suite is reusable only when it has an entry in the new manifest
  `tests/skills/suite-reuse.json` (JSON per RFC-0017 owner decision 3:
  machine-only manifest). Shape:
  `{"version": 1, "suites": {"<suite>": {"inputs": ["<glob>"], "live": false, "note": "<why the inputs are complete>"}}}`.
  `inputs` are extra globs for data the suite reads by a constructed path
  (may be empty); `live` must be the literal `false` for the suite to be
  reusable (`true` documents a suite that must never be reused); `note` is a
  non-empty review statement.
- An unlisted suite gives `RUN <suite> reason=not-declared`; a listed suite
  with `live: true` gives `reason=live`. A manifest that fails to parse, has
  an unknown key, a wrong `version`, a non-boolean `live` or an empty `note`
  disables reuse for the whole run (`reason=manifest-invalid` for every
  suite).
- `lint` exits 0 only when the manifest is valid and every listed suite has a
  suite-map row and a `tests/skills/test-<suite>.sh` file; otherwise exit 1
  with one line per offending suite naming `not-in-suite-map` or
  `no-suite-file`.

### D4 The identity (closed component list)

The helper declares exactly
`const IDENTITY_COMPONENTS = ['inputs', 'env', 'args', 'runtime', 'policy', 'history'];`
as the first occurrence of each of those six quoted names in the file, and
both the identity hash and the miss diff are computed over exactly the
components in that array, in that order. Each component is a sha256 over a
canonical JSON value:

- `inputs`: a map path to sha256 of file bytes, paths repo-relative with `/`
  separators, sorted, over the union of
  (a) every `listTreeFiles` path matching one of the suite's suite-map
  globs or manifest `inputs` globs;
  (b) the suite file;
  (c) the harness: `tests/skills/test-framework.sh`,
  `.aai/scripts/aai-run-tests.sh`, `.aai/scripts/suite-reuse.mjs`,
  `.aai/scripts/select-suites.mjs`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-reuse.json`, `.gitignore`, every file under
  `tests/skills/lib/` ending in `.sh`, and every path matching the suite
  map's `full_run_triggers.shared_lib_globs` (read from the map, not
  duplicated);
  (d) the static closure: starting from the suite file, every file named by
  a path literal in a closure file under `tests/` (a token starting
  `.aai`, `tests` or `docs` made of path characters, or a `lib/<name>`
  token in a `tests/skills/` file resolved against `tests/skills/`), and
  every file reached by an ESM relative `import` or `import()` from a
  closure `.mjs` or `.js` file, transitively. A literal that names a
  directory adds every `listTreeFiles` path under it, except that a literal
  of the form `dir/*.ext` (one simple single-star glob in the last segment,
  with no brace, extglob or `**` syntax) is matched as that glob and adds only
  the `listTreeFiles` paths it matches; any literal with brace or extglob
  syntax keeps the directory fallback (amendment O1). Literals inside files
  under `.aai/` are not followed (M3);
  (e) each seed path (the framework's effective seed list) that exists, when
  its basename occurs in the text of any closure file.
  A path in the union that does not exist is recorded with the value
  `absent`, so its later creation is a change.
- `env`: name to value for every variable in the helper's environment whose
  name starts with `AAI_`, `GIT_`, `NODE_` or `npm_config_`, plus `PATH`,
  `HOME`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TZ`, `TMPDIR`, `SHELL`, plus any
  other variable whose name occurs in a closure file as `$NAME`, `${NAME`,
  `process.env.NAME` or `$env:NAME`; minus the closed exclusion list
  `AAI_SUITE_REUSE` (the switch itself), `AAI_TEST_REF_ID` (heartbeat label
  only) and `AAI_REAP_STEP_START_EPOCH` (per-step timestamp read by the
  reaper), except that an excluded name that occurs in a closure file is
  included.
- `args`: the argument vector the framework runs the suite with
  (`["bash", "tests/skills/test-<suite>.sh"]` today), passed by the caller.
- `runtime`: `process.version`, `process.platform`, `process.arch`, the
  first line of `git --version` and of `bash --version`. The library entry
  point accepts a `runtime` override so tests can inject a Node version and a
  platform; the CLI has no override.
- `policy`: `{policy_version: REUSE_POLICY_VERSION, timeout_seconds,
  isolation: "isolated", seed_paths}` where `REUSE_POLICY_VERSION = 1`,
  `timeout_seconds` is `AAI_TEST_TIMEOUT` resolved by the wrapper's rule
  (non-integer or not positive gives 3000) and `seed_paths` is the effective
  seed list.
- `history`: the empty value, unless a closure file under `tests/` contains
  `git log`, `rev-parse`, `merge-base`, `git diff`, `git show` or
  `git describe`; then the HEAD commit sha and the shas of `refs/heads/main`
  and `refs/remotes/origin/main` when they exist.

Every rule above errs toward a miss: over-inclusion costs a re-run, never a
false pass. The one hole no static rule closes, a read through a path built
at run time, is what the manifest `note` asserts against (residual risk R1).

### D5 Store and record

- Store: `tests/skills/results/reuse/<suite>.json` (already gitignored by
  `tests/skills/results/`), one file per suite, written by temp file plus
  rename. Fields: `schema` 1, `suite`, `identity` (sha256), `components`
  (the per-component sha256 plus the `inputs` path map, so a miss can name
  what changed), `run_id`, `finished_at` (UTC ISO), `duration_seconds`,
  `exit_code` 0, `log` (repo-relative path of
  `tests/skills/results/<run_id>/<suite>.log`), `log_sha256`.
- `check` computes each suite's identity once, writes it to
  `$RUN_DIR/<suite>.reuse-identity.json`, and prints one line per suite:
  `REUSE <suite> run=<run_id> at=<finished_at> log=<log>` or
  `RUN <suite> reason=<reason>[ <detail>]`. Reasons: `no-record`,
  `not-declared`, `live`, `manifest-invalid`, `log-missing` (the cited log
  is absent or its sha256 differs), or the first differing component name
  from IDENTITY_COMPONENTS; for `inputs` the detail is
  `changed <path>`, `added <path>` or `removed <path>` for the first
  differing path in sort order.
- `record` writes the store entry only when all hold, else prints
  `NOT-RECORDED <suite> reason=<reason>`: the suite's `metrics.jsonl` line
  has `status` PASS, `exit_code` 0, `tripwire_attested` true and
  `tripwire_hasher_degraded` false (`not-pass`, `not-attested`); the
  framework passed `isolation=isolated` and `seeding=seeded` for it
  (`not-isolated`); a recomputed identity equals the pre-run one in
  `$RUN_DIR/<suite>.reuse-identity.json` (`inputs-changed-during-run`).
- `forget` deletes the suite's store entry. The framework calls it for
  every suite whose result is FAIL or SKIP in any local run, including an
  opted-out one.
- Only passing results are ever stored, and a record from another machine
  can never match because `runtime` and `env` differ (no cross-machine
  reuse is attempted).

### D6 Modes: when reuse may happen and when fresh execution is mandatory

The framework sets `REUSE_MODE=selected` when at least one `--skill` was
given and `REUSE_MODE=full` otherwise, and passes `--mode` and
`--isolation on|off` to the helper. `check` prints one `OFF <reason>` line
instead of per-suite lines, and the framework prints
`Evidence reuse: off (<reason>)` once, when any holds, first match:
`ci` (`CI` set and not `false`, or `GITHUB_ACTIONS` equal to `true`),
`opt-out` (`AAI_SUITE_REUSE=0`), `full-sweep` (`--mode full`),
`isolation-off` (`--isolation off`). The framework itself prints
`Evidence reuse: off (helper-missing)` when node or the helper is absent.
Otherwise it prints `Evidence reuse: on (<M> of <N> suites reused, check
<s>s)`.

- `record` runs after every local run, full sweep included, unless `ci` or
  `opt-out` holds (then nothing in the store is written; `forget` still
  runs locally on FAIL or SKIP).
- The framework runs every suite with `AAI_SUITE_REUSE=0` in that suite's
  own environment, so a nested framework a suite starts never reuses (the
  framework's own identity calculation excludes the variable, D4).
- `release-dry-run.mjs` passes `AAI_SUITE_REUSE: '0'` in the environment of
  the framework it starts.
- Fresh execution therefore stays mandatory for: the one full sweep before
  close (full mode), CI on pull requests, main and nightly (the `ci` rule),
  release (release-dry-run), TDD RED observations (a failure is never
  stored, and the changed test file is an input) and mutation runs (they
  never go through the framework, M1).

### D7 Reporting: reused is never a new execution

- A reused suite prints `[ n/ m] <suite> REUSED (run <run_id>, <finished_at>,
  log <log>)` and is not executed: no checkout, no tripwire window, no
  `.result` of PASS.
- `$RUN_DIR/metrics.jsonl` gets
  `{"skill":"<suite>","status":"REUSED","reused_from_run":"<run_id>","reused_log":"<log>","identity":"<sha256>"}`.
- The summary prints a line `Reused:  <M>` after `Skipped:`. `Passed`,
  `Failed`, `Skipped`, `TOTAL_TESTS`, the isolation and the seeding counts
  cover executed suites only, so the invariants
  `suites_isolated + suites_degraded == total` and its seeding twin still
  hold. The run ledger line in `docs/ai/tests/test-runs.jsonl` gains one
  field `"reused":<M>`; `total` stays the executed count.
- A run whose every selected suite is reused exits 0 and says so; it is
  still not a full sweep.

### D8 Roles that may consume reused evidence

- May consume: Implementation and TDD GREEN re-checks, Remediation
  re-checks, Validation and Code Review intermediate rounds (all run the
  framework in selected mode). The claim cites the suite as reused, with the
  original run id and log, and the consumer reads that log (SKILL_VERIFY
  READ step).
- Never: the full sweep before close that the TEST rows cite, CI, main,
  nightly, release, mutation runs, TDD RED observations (D6).

### D9 Freshness reconciliation in the canon (byte cap 600 B)

- `.aai/SKILL_VERIFY.prompt.md`, directly after the Iron Law paragraph, one
  paragraph starting `Reuse exception:` stating: a suite that
  `tests/skills/test-framework.sh` prints as REUSED matched the complete
  input identity of an earlier passing run
  (docs/product/precise-suite-evidence-reuse.md); it counts as fresh for that
  suite; cite it as reused with the original run id and log, and read that
  log; the full sweep before close, CI, main, nightly and release always
  execute.
- `.aai/VALIDATION.prompt.md` step 5 c2, one sentence: a REUSED suite counts
  in an intermediate round and is cited as reused (SKILL_VERIFY reuse
  exception).
- Growth of `cat .aai/*.prompt.md` is at most 600 B, credited by exactly one
  JUSTIFIED_ADDITIONS entry naming `precise-suite-evidence-reuse` in
  tests/skills/lib/prompt-diet-ledger.sh, with the TEST-012 `want_growth`
  pin bumped by the same amount. No other prompt, AGENTS.md or WORKFLOW.md
  changes.

### D10 Windows parity

- The logic is one Node module on every platform (D1). A Pester file
  `tests/skills/suite-reuse.Tests.ps1` runs the helper CLI against a
  `$TestDrive` fixture repository with at least four cases: a recorded pass
  gives `REUSE`; an edited declared input gives `RUN` with `reason=inputs`;
  an added untracked file matching a declared glob gives `reason=inputs` with
  `added`; the store entry's `inputs` paths use `/` separators. The full
  Pester discovery of both Windows jobs picks the file up by directory.
- `.github/workflows/ps1-quality.yml` gains `.aai/scripts/suite-reuse.mjs`
  in both the push and pull_request path lists (A4). Native Windows evidence
  is a post-PR check (H1), not a local Spec-AC.

### D11 Measurement protocol (analysis note)

`docs/analysis/precise-suite-evidence-reuse.md`, written by Implementation
after the helper is green, in a disposable worktree of the implementation
branch tip (never the shared main checkout):

1. Round: the M5 suite set, run as
   `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh
   --skill <each of the 7>`.
2. Seed: one run with reuse on, then copy `tests/skills/results/reuse/` to a
   scratch snapshot.
3. Remediation-shaped edit: append one comment line to
   `.aai/scripts/ride-status.mjs`.
   A second round (amendment M1) repeats steps 2 to 4 with a delta of one
   production-script edit that changes no docs/ file.
4. Six samples, alternating off and on: off is the round with
   `AAI_SUITE_REUSE=0`; before each on sample, restore the store from the
   snapshot so every on sample starts from the same state.
5. The note has a heading `## Measurements` and a table with one row per
   sample (mode, wall seconds, suites executed, suites reused, the check
   seconds from the framework line), then the median and worst wall time per
   mode, the commit sha, host, OS, Node, Bash and Git versions, and the list
   of manifest suites with the reason any M5 suite was not reused.

### D12 Rejected alternatives

- Tracing actual reads (strace, fs_usage, atime): needs root on macOS,
  atime is disabled by default on Windows and unreliable on APFS; not
  portable.
- Transitive path-literal closure through production scripts: measured in
  M3 to cover the whole corpus for most suites.
- Whole-tree hash per suite: complete but turns every edit into a miss.
- A general dependency graph: SPEC-0206 measured its leverage and soundness
  premise as weak; not started here.
- A reuse key inside `aai-run-tests.sh` and `.ps1`: duplicated logic in
  two large scripts and no per-suite verdict to bind to (D1).
- Extending suite-map.yaml with reuse keys: the hand-rolled parser and the
  hygiene pins would change and every edit there touches CI selection; a
  separate JSON manifest keeps CI selection byte-identical (D13).
- Mechanical refusal on live-marker text: fires on assertion strings (M3).

### D13 CI selection unchanged

Existing suite-map rows are not edited. The only map change is the new row
`aai-suite-reuse`. The manifest's `inputs` globs affect only identity, never
selection. CI jobs, steps and the selection output for every existing path
stay as they are; CI never reuses (D6).

## Acceptance Criteria Mapping

- Intake AC "reported reused with provenance, not executed" maps to
  Spec-AC-01 and Spec-AC-07.
- Intake AC "each identity component invalidates" maps to Spec-AC-02
  (tracked bytes, untracked file, closure, seed file) and Spec-AC-03 (env,
  args, Node version and platform, runner policy, history).
- Intake AC "undeclared, live, failing earlier run, opt-out run normally"
  maps to Spec-AC-04, Spec-AC-05 and Spec-AC-06.
- Intake AC "never claims a new execution" maps to Spec-AC-07.
- Intake AC "Windows and POSIX behave the same" maps to Spec-AC-10 (local)
  and post-PR check H1 (native Windows job).
- Intake AC "analysis note with measured wall time" maps to Spec-AC-13.
- Intake scope "Planning names how declared is decided and which suites
  qualify" maps to Spec-AC-08 (manifest and lint).
- Intake scope "roles that may consume, fresh mandatory contexts,
  SKILL_VERIFY and dispatch-sweep reconciled" maps to Spec-AC-06 and
  Spec-AC-11.
- Owner constraint "reuse, do not build a second engine" maps to
  Spec-AC-09 and Spec-AC-12.
- Intake scope "product doc, CHANGELOG, RFC-0017 phase 5 row in progress"
  is close-out, not an implementation AC (Close-out steps).

## Constitution deviations

- Article 1 (evidence before claims, "produced and read in this session"):
  a REUSED suite's evidence was produced by an earlier execution, possibly in
  an earlier session. Justified: the reuse is bound to a complete input
  identity (D4) that errs toward a miss, the claim cites the original run and
  its log, which the consumer reads in this session (D8), and every context
  that grants a final verdict (the full sweep before close, CI, main,
  nightly, release) always executes fresh (D6). RFC-0017 section 3, approved
  by the owner on 2026-10-22, asks for exactly this reconciliation.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a declared fixture suite passed in a framework run with --skill and a second run with an unchanged identity starts THEN the second run prints the suite as REUSED naming the first run id, its finished time and its log, does not execute it (the suite's run marker count stays 1) and exits 0 | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3165.log | — | D1 D7 |
| Spec-AC-02 | WHEN between two runs a byte of a tracked declared input changes, an untracked file matching a declared glob appears, a closure-only imported module changes, a file appears under a directory named by a test-side literal, or a seed file named in the closure changes THEN check prints RUN with reason=inputs and the changed, added or removed path and the suite executes; a seed file change for a suite whose closure does not name it still gives REUSE | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3166.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3167.log | — | D4 |
| Spec-AC-03 | WHEN only one of these changes between record and check THEN check prints RUN with that component as reason: an AAI_ variable (env), an excluded variable referenced in the closure (env), the suite argument vector (args), the injected Node version or platform (runtime), the seed list or policy version (policy), HEAD for a suite with a history marker (history); an excluded variable not referenced and HEAD for a suite without a history marker still give REUSE | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3168.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3169.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3170.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3171.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3172.log | — | D4 |
| Spec-AC-04 | WHEN a suite is not in the manifest, is listed with live true, or the manifest has an unknown key THEN check prints RUN with reason not-declared, live or manifest-invalid and the framework executes the suite | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3173.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3174.log | — | D3 |
| Spec-AC-05 | WHEN a recorded suite then fails or skips (exit 42) in a local run THEN its store entry is deleted and the next run executes it with reason=no-record; record refuses to store with reason not-pass, not-attested, not-isolated or inputs-changed-during-run for the matching metrics or identity condition | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3175.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3176.log | — | D5 |
| Spec-AC-06 | WHEN the framework runs without --skill, or with CI set, GITHUB_ACTIONS true, AAI_SUITE_REUSE=0 or isolation off THEN it prints Evidence reuse off with full-sweep, ci, opt-out or isolation-off and executes every suite despite a valid record; a full sweep records passes, a ci or opt-out run writes no store entry; every suite runs with AAI_SUITE_REUSE=0 in its own environment; release-dry-run.mjs passes AAI_SUITE_REUSE 0 to the framework it starts | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3177.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3178.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3179.log | — | D6 |
| Spec-AC-07 | WHEN a suite is reused THEN metrics.jsonl holds status REUSED with reused_from_run and reused_log, the summary prints Reused with the count, Passed counts executed suites only, the test-runs.jsonl line carries reused while total stays the executed count and the isolation invariant holds; WHEN the cited log is missing or its sha256 differs THEN check prints RUN reason=log-missing | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3180.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3181.log | — | D7 D5 |
| Spec-AC-08 | lint exits 0 on the live repository; the live manifest lists at least 5 suites, at least 1 of them in the M5 round, each with live false, a non-empty note, a suite-map row and a suite file; on a fixture manifest naming a suite without a suite-map row lint exits 1 and names the suite and not-in-suite-map | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3182.log | — | D3 |
| Spec-AC-09 | importing select-suites.mjs from another module prints nothing, does not set an exit code and exposes parseSuiteMap and matchesGlob; the helper's declared globs for a suite equal parseSuiteMap's globs for that suite; tests/skills/test-aai-suite-select.sh passes unchanged | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3183.log, docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3190.log | — | D2 |
| Spec-AC-10 | tests/skills/suite-reuse.Tests.ps1 passes at least 4 cases with 0 failed and 0 skipped under local pwsh 7 (hit, edited input, untracked added, slash-separated store paths); both path lists of ps1-quality.yml list .aai/scripts/suite-reuse.mjs and test-aai-win-fallback.sh test_034 passes | planned | — | — | D10 |
| Spec-AC-11 | SKILL_VERIFY carries a paragraph starting Reuse exception: after the Iron Law naming REUSED, the original run, reading its log, and the full sweep before close, CI, main, nightly and release as always executed; VALIDATION step 5 c2 names a REUSED suite as counting in an intermediate round; the prompt glob grows at most 600 B, credited by one ledger entry naming precise-suite-evidence-reuse, and test-aai-prompt-diet.sh TEST-010 and TEST-012 pass | planned | — | — | D9 |
| Spec-AC-12 | PROFILES.yaml core lists .aai/scripts/suite-reuse.mjs; select-suites.mjs selects aai-suite-reuse for suite-reuse.mjs, suite-reuse.json, test-framework.sh and release-dry-run.mjs; the helper is at most 600 lines, imports only node: modules plus select-suites.mjs and lib/tree-hash.mjs, and passes no shell option to a child process; IDENTITY_COMPONENTS holds exactly the six D4 names in order | done | docs/ai/tdd/precise-suite-evidence-reuse/green/green-TEST-3188.log | — | D1 D2 D4 |
| Spec-AC-13 | docs/analysis/precise-suite-evidence-reuse.md has a Measurements heading and at least 3 samples per mode for each of two rounds (the M5 round, and a second round whose delta is one production-script edit that changes no docs/ file); every on sample reuses at least 1 suite where the note says it should; the note gives the reused-suite count and both medians per round, every check time is at most 5 s, it names commit, host, Node, Bash and Git versions, and it states where reuse helps and why the docs-closure suites miss (no requirement that the on median beats the off median) | planned | — | — | D11 |

## Implementation plan

- New `.aai/scripts/suite-reuse.mjs` (D1 to D6): library exports
  `computeIdentity`, `diffIdentity`, `checkSuites`, `recordSuite`,
  `forgetSuite`, `lintManifest`, and the CLI.
- New `tests/skills/suite-reuse.json` (D3), initial qualified suites chosen
  by the implementer: run `explain` on candidates (the M5 suites first), and
  list a suite only when its closure and globs cover what it reads and its
  advisory marker hits are explained in `note`.
- `tests/skills/test-framework.sh`: after discovery, call `check` with
  `--mode`, `--isolation`, `--run-dir`, `--root` and one `--suite` per
  discovered suite; remove REUSE suites from the execution list and report
  them (D7); export `AAI_SUITE_REUSE=0` into each suite's execution
  environment only (D6); add `isolation` and `seeding` to the per-suite
  metrics line; after reporting, call `record` for executed suites and
  ` forget ` for FAIL or SKIP; add `REUSED_TESTS`, the summary line and the
  ledger field.
- `select-suites.mjs`: `isMain` guard and the export line (D2).
- `release-dry-run.mjs`: `AAI_SUITE_REUSE: '0'` in the framework child env.
- Prompts, ledger, pin, PROFILES row, suite-map row, Pester file, path
  filter lines, analysis note.

### Seams crossed

| Seam | Producer | Consumer | Test |
|---|---|---|---|
| S1 per-suite verdict | framework metrics.jsonl line | helper record | TEST-3175, TEST-3176 (real framework run, then the store) |
| S2 pre-run identity | helper check | helper record after the run | TEST-3176 (inputs-changed-during-run) |
| S3 reuse decision | helper check stdout | framework execution list and counters | TEST-3165, TEST-3180 |
| S4 run ledger | framework | test-runs.jsonl readers and the isolation invariant | TEST-3180 |
| S5 suite map | select-suites.mjs parser | helper declared globs | TEST-3183 |
| S6 fresh-mandatory callers | release-dry-run.mjs, nested frameworks | framework reuse switch | TEST-3179 |
| S7 canon | SKILL_VERIFY, VALIDATION | roles citing evidence | TEST-3186 (inspection; behavior of a role is not automatable, R3) |
| S8 Windows | PowerShell host paths | helper | TEST-3184 and TEST-3185 locally, H1 natively |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3165 | Spec-AC-01 | integration | tests/skills/test-aai-suite-reuse.sh | test_3165: fixture repo with the real framework, helper, select-suites and lib copied in, a manifest declaring fx and a suite fx that appends one line to a marker file outside the repo; run 1 with --skill fx passes; run 2 prints fx REUSED naming run 1 id, time and log, the marker has 1 line, exit 0 | `sed:s/REUSED (run/PASS (run/` on tests/skills/test-framework.sh | green |
| TEST-3166 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3166: recordSuite then checkSuites on a fixture git repo; editing a tracked declared input gives RUN reason=inputs changed path; adding an untracked file matching a declared glob gives reason=inputs added path | `sed:s/'--others', '--exclude-standard'/'--cached'/` on .aai/scripts/lib/tree-hash.mjs | green |
| TEST-3167 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3167: a module imported by the suite's test lib but matched by no glob changes, a file appears under a directory the suite names as a literal, and docs/ai/STATE.yaml changes; each gives reason=inputs for a suite whose closure covers it, and the STATE change gives REUSE for a suite whose closure does not name STATE.yaml | `sed:s/'inputs', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3168 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3168: changing AAI_FIXTURE_X gives reason=env; changing AAI_TEST_REF_ID gives REUSE; changing AAI_TEST_REF_ID for a suite whose closure references it gives reason=env | `sed:s/'env', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3169 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3169: computeIdentity with the argument vector extended by one argument gives reason=args against the record | `sed:s/'args', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3170 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3170: an injected runtime with another Node version gives reason=runtime, and one with another platform gives reason=runtime | `sed:s/'runtime', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3171 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3171: another seed list and another policy version each give reason=policy | `sed:s/'policy', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3172 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3172: a commit that moves HEAD gives reason=history for a suite whose test file runs git rev-parse and REUSE for a suite without a history marker | `sed:s/, 'history'//` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3173 | Spec-AC-04 | integration | tests/skills/test-aai-suite-reuse.sh | test_3173: framework fixture with a recorded pass; removing fx from the manifest gives RUN reason=not-declared and the marker grows; setting live true gives reason=live; adding an unknown key gives reason=manifest-invalid; each run executes fx | `sed:s/'not-declared'/'no-record'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3174 | Spec-AC-04 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3174: manifests with version 2, live as a string and an empty note each give manifest-invalid for every suite | `sed:s/'manifest-invalid'/'not-declared'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3175 | Spec-AC-05 | integration | tests/skills/test-aai-suite-reuse.sh | test_3175: framework fixture; fx passes and is recorded; fx is switched to exit 1, the run fails and the store entry is gone; fx is switched back and the next run executes it with reason=no-record; a suite exiting 42 is not recorded | `sed:s/ forget / forgot /` on tests/skills/test-framework.sh | green |
| TEST-3176 | Spec-AC-05 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3176: recordSuite with metrics lines for status FAIL, tripwire_attested false and isolation degraded gives NOT-RECORDED not-pass, not-attested and not-isolated; editing an input between check and record gives inputs-changed-during-run; no store file is written in any case | `sed:s/'not-attested'/'not-isolated'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3177 | Spec-AC-06 | integration | tests/skills/test-aai-suite-reuse.sh | test_3177: framework fixture with a valid record; a run without --skill prints Evidence reuse off (full-sweep), executes fx and refreshes the record; a run with AAI_SUITE_REUSE=0 prints off (opt-out), executes fx and leaves the store file byte-identical | `sed:s/REUSE_MODE=full/REUSE_MODE=selected/` on tests/skills/test-framework.sh | green |
| TEST-3178 | Spec-AC-06 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3178: checkSuites with GITHUB_ACTIONS=true prints OFF ci; with CI=true prints OFF ci; with CI=false and no GITHUB_ACTIONS does not; recordSuite under GITHUB_ACTIONS=true writes nothing; --isolation off prints OFF isolation-off | `sed:s/'GITHUB_ACTIONS'/'GITHUB_ACTIONZ'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3179 | Spec-AC-06 | integration | tests/skills/test-aai-suite-reuse.sh | test_3179: a fixture suite prints its AAI_SUITE_REUSE value into its log and the framework run with reuse on shows 0; release-dry-run.mjs sets AAI_SUITE_REUSE to '0' in the environment it passes to the test-framework.sh invocation | `sed:s/AAI_SUITE_REUSE: '0'/AAI_SUITE_REUSE: '1'/` on .aai/scripts/release-dry-run.mjs | green |
| TEST-3180 | Spec-AC-07 | integration | tests/skills/test-aai-suite-reuse.sh | test_3180: two-suite fixture, one reused and one executed; metrics.jsonl holds status REUSED with reused_from_run and reused_log for the reused one; the summary has Reused with 1 and Passed with 1; the new test-runs.jsonl line has reused 1, total 1 and suites_isolated plus suites_degraded equal to total | `sed:s/Reused:  /Reusex:  /` on tests/skills/test-framework.sh | green |
| TEST-3181 | Spec-AC-07 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3181: with a valid record, deleting the cited log gives RUN reason=log-missing and so does appending one byte to it | `sed:s/'log-missing'/'no-record'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3182 | Spec-AC-08 | contract | tests/skills/test-aai-suite-reuse.sh | test_3182: lint on the live repository exits 0; the live manifest has at least 5 suites, at least 1 of the 7 M5 suites, each with live false, a non-empty note, a suite-map row and a suite file; a fixture manifest naming ghost-suite makes lint exit 1 with ghost-suite and not-in-suite-map | `sed:s/'not-in-suite-map'/'ok'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3183 | Spec-AC-09 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3183: a child node process that imports select-suites.mjs prints nothing and exits 0; parseSuiteMap and matchesGlob are functions; the helper's declared globs for aai-ride-status equal parseSuiteMap(live map).suites aai-ride-status globs | `sed:s/export { parseSuiteMap, matchesGlob };/const unusedExports = 0;/` on .aai/scripts/select-suites.mjs | green |
| TEST-3184 | Spec-AC-10 | integration | tests/skills/test-aai-suite-reuse.sh | test_3184: runs Invoke-Pester with PassThru on tests/skills/suite-reuse.Tests.ps1 under pwsh 7 and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 4 | `sed:s/'inputs', //` on .aai/scripts/suite-reuse.mjs | pending |
| TEST-3185 | Spec-AC-10 | contract | tests/skills/test-aai-suite-reuse.sh | test_3185: the push list and the pull_request list of ps1-quality.yml each contain the exact entry .aai/scripts/suite-reuse.mjs (test-aai-win-fallback.sh test_034 runs in Verification for list parity) | `sed:s/      - '.aai\/scripts\/suite-reuse.mjs'/      - '.aai\/scripts\/suite-reusx.mjs'/` on .github/workflows/ps1-quality.yml | pending |
| TEST-3186 | Spec-AC-11 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3186: SKILL_VERIFY has a paragraph starting Reuse exception: after the Iron Law paragraph containing REUSED, original run, log, full sweep before close, CI, main, nightly and release; VALIDATION step 5 c2 contains REUSED and intermediate round | `sed:s/REUSED/RE-USED/` on .aai/SKILL_VERIFY.prompt.md | pending |
| TEST-3187 | Spec-AC-11 | contract | tests/skills/test-aai-suite-reuse.sh | test_3187: prompt-diet-ledger.sh has exactly one JUSTIFIED_ADDITIONS entry naming precise-suite-evidence-reuse with a leading byte count from 1 to 600; the Verification run of test-aai-prompt-diet.sh proves TEST-010 and TEST-012 | `sed:s/ precise-suite-evidence-reuse / precise-suite-evidence-reusx /` on tests/skills/lib/prompt-diet-ledger.sh | pending |
| TEST-3188 | Spec-AC-12 | contract | tests/skills/test-aai-suite-reuse.sh | test_3188: PROFILES.yaml core has the suite-reuse.mjs row; the real select-suites.mjs selects aai-suite-reuse for the helper, the manifest, test-framework.sh and release-dry-run.mjs; the helper is at most 600 lines, its imports are node: modules, ./select-suites.mjs and ./lib/tree-hash.mjs, it has no shell true, and its IDENTITY_COMPONENTS line equals the D4 literal | `sed:s/  - \.aai\/scripts\/suite-reuse\.mjs/  - .aai\/scripts\/suite-reusx.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3189 | Spec-AC-13 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3189: the note has a line equal to ## Measurements, at least 3 table rows per mode in each of two rounds, a reused count and both medians per round, every check value at most 5, a statement of where reuse helps and why docs-closure suites miss, and names a 40-character commit sha, Node, Bash and Git versions (no comparison of the on and off medians) | `sed:s/## Measurements/## Measurementz/` on docs/analysis/precise-suite-evidence-reuse.md | pending |
| TEST-3191 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3191: a suite whose test file names `dir/*.txt` stays REUSE when a non-matching file in that directory changes or appears and gives reason=inputs for a matching file changed or added; a suite naming a brace literal `dir/{a,b}.txt` gives reason=inputs for a non-matching file in the directory | `sed:s/SIMPLE_GLOB_RE.test(p)/false/` on .aai/scripts/suite-reuse.mjs | pending |
| TEST-3190 | Spec-AC-09 | integration | tests/skills/test-aai-suite-select.sh | the existing suite runs unchanged against the guarded select-suites.mjs (CLI output contract) | `sed:s/if (isMain) runMain(/if (false) runMain(/` on .aai/scripts/select-suites.mjs | green |

RED plan, observed on the baseline `773557ee` before each fix and stored
under `docs/ai/tdd/precise-suite-evidence-reuse/red/`:

- TEST-3165 to TEST-3181: `.aai/scripts/suite-reuse.mjs` and the manifest
  do not exist and the framework has no reuse lines; each case fails on the
  missing module, the missing REUSED line or an executed marker.
- TEST-3182: lint does not exist. TEST-3183: importing select-suites.mjs runs
  its main and prints a selection.
- TEST-3184: the Pester file does not exist. TEST-3185: the path lists lack
  the helper entry.
- TEST-3186 and TEST-3187: the prompt paragraph and the ledger entry are
  absent. TEST-3188: no PROFILES or suite-map row. TEST-3189: no note.
- TEST-3190: green on the baseline by design (a regression pin for the
  guarded CLI); its RED is the mutation record (the guard never calls main),
  which mutation-gate accepts.

Mutation semantics: `mutation-run.mjs` applies a `sed:s/OLD/NEW/` to the whole
file and replaces the FIRST occurrence (fu-mutation-sed-drops-multiline-flag),
so no expression above is anchored. Each quoted literal a mutation names
(IDENTITY_COMPONENTS, the reason strings, `REUSED (run`, `REUSE_MODE=full`,
` forget `, `Reused:  `, `AAI_SUITE_REUSE: '0'`, `if (isMain) runMain(`,
`export { parseSuiteMap, matchesGlob };`) must first occur at its decisive
site; if the implementation cannot place it so, the row's mutation is amended
additively with disclosure, never dropped.

TDD run split (about three ACs per run, sweep-ride operating note):

- Run A: Spec-AC-09, Spec-AC-12, Spec-AC-02 (select-suites export, helper
  skeleton with identity inputs; TEST-3166, TEST-3167, TEST-3183, TEST-3188,
  TEST-3190).
- Run B: Spec-AC-03, Spec-AC-04, Spec-AC-08 (remaining components,
  qualification, lint and the live manifest; TEST-3168 to TEST-3174,
  TEST-3182).
- Run C: Spec-AC-01, Spec-AC-05, Spec-AC-06, Spec-AC-07 (framework wiring
  and release-dry-run; TEST-3165, TEST-3175 to TEST-3181).
- Run D: Spec-AC-10, Spec-AC-11, Spec-AC-13 (Pester, path filter, prompts and
  ledger last, then the measurement; TEST-3184 to TEST-3187, TEST-3189).

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-suite-reuse.sh`, `test-aai-suite-select.sh`,
  `test-aai-suite-isolation.sh`, `test-aai-sweep-parallel.sh`,
  `test-aai-repo-tripwire.sh` (fixture frameworks), `test-aai-release-first.sh`
  (release-dry-run), `test-aai-win-fallback.sh` (path filter),
  `test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh` (shares the diet
  ledger), `test-aai-layer-profiles.sh`, `test-aai-hygiene-pack.sh` (one
  suite-map row per suite), plus whatever
  `node .aai/scripts/select-suites.mjs --base-ref main` selects plus CORE.
  Intermediate rounds run selected plus CORE; one full sweep before close
  with `AAI_TEST_TIMEOUT=3600`, which by D6 always executes every suite.
- `node .aai/scripts/suite-reuse.mjs lint` exits 0 on the branch tip.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` exits 0.
- `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0 before
  close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Post-PR checks (not Spec-ACs, not claimed by local Validation)

- H1 (native Windows parity, intake AC "Windows and POSIX behave the same"):
  on the PR head the ps1-quality run concludes success for `gate`,
  `windows-5_1` and `windows-wsl1`, every case of `suite-reuse.Tests.ps1` is
  listed as passed in each Pester discovery step, and the skipped count still
  equals `AAI_EXPECTED_WIN_SKIP_COUNT`. Evidence: run id, head SHA, matched
  log lines from `gh run view <id> --log`.
- H2: the PR head's skill-suite run concludes success; its log shows
  `Evidence reuse: off (ci)` in every framework job.

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

Run by the orchestrator after flush, before the PR. After them, run
`set-code-review` again with this file list as scope.

1. Product doc `docs/product/precise-suite-evidence-reuse.md` from
   .aai/templates/PRODUCT_TEMPLATE.md (the intake's `capability:`): what is
   reused, the opt-out, where fresh execution stays mandatory, how to read a
   REUSED line.
2. RFC-0017 Rollout Status phase 5 row: status `in progress`, delivered by
   this slice (precise local suite reuse with a complete input identity);
   the process-adapter migration stays open. Frontmatter
   `status: implementing` and `umbrella: true` stay.
3. CHANGELOG.md: one `## [unreleased] — <title>` heading entry; the prompts
   are shipped surfaces, so `release-notes-gate.mjs --staged` must pass.
4. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/precise-suite-evidence-reuse/red/, a mutation record per Test
Plan row under docs/ai/tdd/spec-precise-suite-evidence-reuse/, and green
suite outputs. A REUSED suite line is not evidence for any row of this spec:
its suites run with `AAI_SUITE_REUSE=0` (the feature under test must not
certify itself).

## Files Implementation touches

- .aai/scripts/suite-reuse.mjs (new)
- tests/skills/suite-reuse.json (new)
- tests/skills/lib/suite-reuse.test.mjs (new)
- tests/skills/test-aai-suite-reuse.sh (new)
- tests/skills/suite-reuse.Tests.ps1 (new)
- tests/skills/test-framework.sh
- .aai/scripts/select-suites.mjs
- .aai/scripts/release-dry-run.mjs
- tests/skills/suite-map.yaml (new row aai-suite-reuse only)
- .aai/system/PROFILES.yaml (core row for the helper)
- .github/workflows/ps1-quality.yml (one path line in each of two lists)
- .aai/SKILL_VERIFY.prompt.md
- .aai/VALIDATION.prompt.md
- tests/skills/lib/prompt-diet-ledger.sh
- tests/skills/test-aai-prompt-diet.sh (TEST-012 pin)
- docs/analysis/precise-suite-evidence-reuse.md (new)
- docs/issues/CHANGE-DRAFT-precise-suite-evidence-reuse.md
- docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md
- docs/product/precise-suite-evidence-reuse.md (close-out)
- docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (close-out)
- CHANGELOG.md (close-out)
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

One new `.aai/**` file (suite-reuse.mjs) is classified in PROFILES.yaml core,
beside select-suites.mjs which it imports (TEST-3188). Two prompt-corpus files
grow, so one diet-ledger entry and the TEST-012 pin are owed (TEST-3187). Not
touched: aai-run-tests.sh, aai-run-tests.ps1, aai-reap-tests.*,
autonomous-loop.*, skill-suite.yml, every protected_paths_l3 file, AGENTS.md,
WORKFLOW.md, existing suite-map rows.

## Risks and rollback

- R1 False hit through a read the static rules cannot see (a path built at
  run time, a corpus walk from a production default). Mitigations: the
  manifest is opt-in per suite with a reviewed `note`; directory literals
  hash whole directories; the shared lib tree is in every identity; every
  final-verdict context executes fresh (D6). Residual: a wrong `note` can
  produce a false hit in an intermediate round; the full sweep before close
  still executes that suite.
- R2 Concurrent edits during a run: the pre and post identity comparison
  refuses the record (D5); an edit made and reverted inside one run is not
  detected.
- R3 Role behavior (citing reused evidence correctly, reading the original
  log) is prompt text; TEST-3186 checks the text, not a role's conduct.
- R4 Value may be small when most selected suites hash broad inputs; D11
  measures it honestly in two rounds and Spec-AC-13 requires the note to say where reuse helps and why it misses, not that the on median is lower (amendment M1).
- R5 Fixture frameworks that assert exact output gain one `Evidence reuse`
  line; the Verification list runs the three suites that copy the framework.
- Rollback: `AAI_SUITE_REUSE=0` disables reuse at once; reverting the PR
  removes it. The store is gitignored runtime data; deleting
  `tests/skills/results/reuse/` is always safe.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list` (272 lines) has no item on local suite
reuse, an input identity, a reuse store or the freshness rule. Related, left
open: `fu-suite-select-pin-product-docs`,
`fu-tracked-ignored-rev-cat-file-batch`, `fu-rescue-dir-and-member-double-copy`
(CI carry-forward, CHANGE-0205), `fu-tripwire-attributes-concurrent-writes`
(framework tripwire attribution, unchanged here), `fu-mutation-gate-skips-pester`
(this spec's Pester row is covered through a bash wrapper row, as SPEC-0247
did).

## Registry items closed by this scope

none
