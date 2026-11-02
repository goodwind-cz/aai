---
id: spec-reuse-for-docs-reading-suites
type: spec
number: null
status: implementing
frozen_sha256: 3c00581d1b0144628ac7cd6ad26c2acb0c78acebba786ea942575b2fc1b22383
mutation_gate: v1
ceremony_level: 2
links:
  requirement: reuse-for-docs-reading-suites
  rfc: RFC-0017
  pr: []
  commits: []
---

# Suite reuse keyed on what the suite actually read: a run-time access trace of the disposable checkout replaces the source-text path reader

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-DRAFT-reuse-for-docs-reading-suites.md
- Prior slice: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md
  (decisions D1 to D13, residual R1, the minimal-tree admission gate)
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (section 3, phase 5; the umbrella stays open)
- Measurement note: docs/analysis/precise-suite-evidence-reuse.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 24
  baseline, Node 22 floor; system Bash 3.2 and GNU Bash for suites)
- Baseline commit: `5e9f1350` (branch tip at planning time; main `f5a4f49d`)

## Implementation strategy

- Strategy: tdd
- Rationale: the hazard is a false hit, a stale pass reported as fresh. Every
  rule that turns a hit into a miss must be observed failing first (each new
  row has a RED on the baseline: the trace, the new component, the admission
  mode and the manifest entries do not exist, and TEST-3272 shows the baseline
  reusing a suite after a change to a file it reads through a built path).
  Mutation gate v1 applies.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound; edits tests/skills/test-framework.sh (the
  funnel every local and CI run goes through), the reuse helper, the manifest,
  the suite map and one core prompt; mutation runs rewrite these files and the
  measurement applies scratch edits, which must not reach the shared main
  checkout. No file is in `protected_paths_l3`, so not required.
- User decision: worktree (recorded at intake;
  /Users/ales/Projects/aai-worktrees/reuse-for-docs-reading-suites, branch
  feat/reuse-for-docs-reading-suites)
- Base ref: main
- Inline review scope: the list in "Files Implementation touches".
- Code review required: true.

## What Planning measured

Evidence (local, gitignored):
docs/ai/tdd/reuse-for-docs-reading-suites/planning/ (the scratch harness
`measure.mjs`, its Node preload, per-suite read lists and summaries).
Host Apple M4 Max, macOS 27.0.1, APFS, Node v22.23.1, system Bash 3.2.57,
Git 2.54.0, tree of 1,948 tracked files (37.3 MB) at `5e9f1350`.

### M1 Access times record reads by every process on this host

A file's access time was set to 2000-01-01 and the file was then read. The
access time advanced for `cat`, `grep`, `source`, plain `cp`, `git
hash-object`, Node `readFileSync`, `copyFileSync` (with and without the
clone flag) and `cpSync`, and for a directory listed by `ls`; it did not
advance for `stat`/`existsSync` (no read), `ditto` and `cp -c` (APFS clone
copies, which copy without reading). In a 50-commit repository `git log`
advanced HEAD, config, packed-refs, the pack, its index and the commit graph;
`git rev-parse --show-toplevel` advanced only HEAD and config; `git status`
also read `.git/index` and `info/exclude`.

### M2 What the six named suites actually read

Each suite ran once, as the framework runs it, in a scratch disposable
checkout (`git clone --local --no-hardlinks`, detached HEAD, refs fetched,
working-tree diff, untracked files and seeds replayed), with every access time
in the checkout reset to 2000-01-01 just before the run; a file counts as read
when its access time advanced, or it was replaced (new inode) or deleted.

| Suite | Seconds | Files read | Reads the git index | EVENTS.jsonl | test-runs.jsonl | STATE.yaml | every .aai/scripts file |
|---|---|---|---|---|---|---|---|
| aai-docs-content | 22 | 1,094 | yes | yes | no | no | yes |
| aai-spec-lint | 33 | 1,976 | yes | yes | yes | yes | yes |
| aai-prompt-diet | 4 | 1,977 | yes | yes | yes | no | yes |
| aai-win-fallback | 43 | 1,948 | yes | yes | yes | no | yes |
| aai-hygiene-pack | 94 | 2,283 | yes | yes | yes | yes | yes |
| aai-ride-status | 15 | 27 | no | no | no | no | no |

All six exited 0. A Node fs preload ran alongside: across the six suites, 0
Node content reads of a checkout file were missing from the access-time
set, and no child process dropped `NODE_OPTIONS`. The five large suites read
the whole corpus for real: `cp -R "$PROJECT_ROOT/docs"`, `grep -r` over
`.aai`, docs-audit's own `git status --porcelain -- docs`
(`.aai/scripts/lib/docs-audit-core.mjs`), and git commands whose index refresh
re-reads files. aai-ride-status reads 22 `.aai` files, 4 test files and
`docs/ai/docs-audit.yaml`.

The SPEC-0266 source-text reader, on the same tree, gives aai-ride-status
3,188 input files, a history marker and 2,194 unresolvable forms (it can never
be reused). The access trace gives 27 files and no history.

### M3 Two traps in the trace itself

- Resetting an access time with `utimes` also changes the file's ctime, so a
  later `git status` in the checkout sees every entry as stat-dirty and reads
  the whole tree (first pass: docs-content 1,974 files; with
  `core.trustctime=false` 1,094). This matters only for suites that read the
  git index, and those get the whole checkout as input anyway (D3), so no
  config change is made.
- Without a reset the trace is blind: in a fresh framework-like checkout
  1,933 of 1,948 files already had an access time newer than their mtime
  before any suite ran (git's racy-index re-reads during clone and checkout),
  and under relatime a later read would not advance it again. The reset is
  mandatory.

### M4 Cost

On the 1,948-file checkout: listing and hashing every file 60 ms, resetting
2,850 entries 57 ms, the post-run scan 15 ms.

### M5 What follows for the three mechanisms of the intake

- Framework ledger append and EVENTS/STATE churn: under a trace, a ledger is
  an input only of a suite that reads it. aai-ride-status reads none of them;
  the five large suites read EVENTS.jsonl, four of them read test-runs.jsonl
  and two read STATE.yaml, and all five read the git index. Those are real
  reads, so they stay inputs. A change to where the framework writes its
  ledger would not let any of the five be reused after a code edit, because
  each of them also reads every production script. No ledger-write change is
  made in this slice (D7).
- Shared-library prose literals: they exist only for the source-text reader.
  The trace never sees them; the reader is removed (D8).
- The history marker: replaced by observed reads under the checkout's
  `.git/` directory (D3): history enters only when the run read it.

Consequence, stated plainly: an exact identity, by any method, cannot reuse
aai-docs-content, aai-spec-lint, aai-prompt-diet, aai-win-fallback or
aai-hygiene-pack after a one-line change to any tracked file, because they
read every tracked file (directly or through the git index). They are
admitted and are reused exactly when nothing they read changed. Making them
cheap on a remediation round needs a different change, splitting their
corpus-wide cases into separate suites, which is not this slice (see Split).

## Split

The intake allows a split. This spec plans the first slice: the trace
identity, the admission gate and the manifest (all six named suites
admitted), plus the measurement. Not planned here, recorded as follow-ups at
close:

- `fu-reuse-split-corpus-cases`: split the corpus-wide cases of the five
  large suites (cases that read all of docs/ or .aai) from their fixture
  cases, so the fixture part gets a narrow read set; needs a per-case read
  measurement first.
- `fu-reuse-local-ledger-append`: the framework's append to the tracked
  `docs/ai/tests/test-runs.jsonl` is an input of every suite that reads it,
  so a zero-delta re-run of those suites misses; worth changing only together
  with the split above.

## Assumptions (autopilot, recorded instead of asked)

- A1 The measurement round uses an uncommitted one-line edit (as SPEC-0266
  did). A commit moves HEAD, which is an input of every suite that reads the
  checkout's git directory.
- A2 CI never reuses (unchanged), so the admission gate is off under CI
  (D5): it guards local reuse only, and CI's file system is not assumed to
  record access times.
- A3 The five suites already in the manifest stay and are re-admitted under
  the trace; aai-orchestration-mode and aai-runtime-file, unresolvable under
  the source-text reader, become reusable.

## Decisions

### D1 The identity method: a run-time access trace of the disposable checkout

Every suite already runs in its own disposable checkout. For a declared suite
the framework resets the access time of every entry in that checkout just
before the suite starts and collects, just after it ends, which pre-existing
files were read (access time advanced), replaced or deleted. The identity is
keyed on that set. It sees reads by every process (bash builtins, grep, cp,
git, node, python) without a per-language tracer, and it needs no root.
Rejected: fixing the three mechanisms inside the source-text reader (it stays a
hand-written parser in a gate, 14 validation rounds and still open gaps; and
even a perfect reader cannot be narrower than the true read set M2 measured);
a Node-only trace (blind to bash); OS tracers (`fs_usage`, `dtrace`,
`strace`: root or unavailable). SPEC-0266 D12 rejected access times for the
real checkout (atime off on Windows, unreliable on APFS); here the times are
set and read inside a throwaway checkout and a canary proves they work, and
where they do not, nothing is recorded.

### D2 Trace protocol

- New module `.aai/scripts/lib/checkout-trace.mjs` (Node stdlib, at most 200
  lines) exporting `armTrace` and `collectTrace`, and the helper subcommands
  `suite-reuse.mjs arm --dir <checkout> --run-dir D --suite S` and
  `suite-reuse.mjs collect --dir <checkout> --run-dir D --suite S`.
- `arm`, in this order: list the checkout's paths with `listTreeFiles` on
  the checkout plus each seed path that exists there (the path list); hash
  every regular file under the checkout outside `.git/` (sha256); record each
  entry's inode; reset the access time
  of every entry under the checkout, `.git` included, to `ATIME_FLOOR`
  (`export const ATIME_FLOOR = 946684800;`, 2000-01-01T00:00:00Z) keeping its
  mtime, children before their directory; then write a canary file next to the
  checkout, reset it, read it, and set `canary` true only when its access time
  advanced. Writes `$RUN_DIR/<suite>.reuse-arm.json`.
- `collect` walks the checkout. A file present at arm is an input when its
  access time is above the floor (`const wasRead = st.atimeMs / 1000 >
  ATIME_FLOOR;`), its inode changed (`st.ino !== armed.ino`) or it is gone.
  Files created during the run are not inputs. `git_read` is true when any
  input is under `.git/`; `index_read` when `.git/index` is one
  (`rel === '.git/index'`). It writes `$RUN_DIR/<suite>.reuse-trace.json`:
  `{suite, run_id, canary, git_read, index_read, inputs: {<path>: <arm
  sha256>}, paths: [<path list>], env_names: [...]}`, where inputs outside
  `.git/` carry their arm-time hash and `env_names` are the names
  `referencedNames(texts)` finds (the SPEC-0266 D4 env regex) in the texts of
  the input files.
- The framework calls `arm` after `suite_prepare` and immediately before
  `suite_execute`, and `collect` immediately after it and before
  `iso_destroy`, in both execution paths (serial `run_test`, wave
  `suite_child`), through one function `reuse_trace_arm` and one
  `reuse_trace_collect`, only for suites `check` lists on a `TRACE <suite>`
  line. `check` prints `TRACE <suite>` for every declared non-live suite
  unless reuse is off for `ci`, `opt-out` or `isolation-off` (a full sweep
  still records, SPEC-0266 D6, so it is traced). A failing `arm` or `collect`
  never changes the suite's verdict; it only leaves no trace.

### D3 What the identity compares

`const IDENTITY_COMPONENTS = ['inputs', 'paths', 'env', 'args', 'runtime', 'policy', 'history'];`
(first occurrence in `suite-reuse.mjs`); hash and miss diff run over exactly
these, in this order.

- `inputs`: path to sha256 for every traced input outside `.git/` (the hash
  the checkout had at arm on record; the working tree's bytes on check, a
  missing file being `absent`); when `index_read`, also every file of the path
  list; plus the harness, hashed from the working tree on both sides:
  `tests/skills/test-framework.sh`, `.aai/scripts/aai-run-tests.sh`,
  `.aai/scripts/suite-reuse.mjs`, `.aai/scripts/lib/checkout-trace.mjs`,
  `.aai/scripts/select-suites.mjs`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-reuse.json`, `.gitignore`, and the manifest entry's
  `inputs` globs. Suite-map globs and the `tests/skills/lib/*.sh` blanket of
  SPEC-0266 D4 (c) leave the identity: what the suite reads is traced.
- `paths`: the path list (on check: `listTreeFiles` of the working tree plus
  the seed paths that exist). A miss names the first added or removed path.
- `env`: as SPEC-0266 D4, except that the referenced names come from the
  record's `env_names` (texts of the files the run read), not from a static
  closure.
- `args`, `runtime`: unchanged (SPEC-0266 D4).
- `policy`: as SPEC-0266 D4 with `REUSE_POLICY_VERSION = 2` and
  `trace: 'atime'`, so every record written by the source-text reader misses
  once.
- `history`: empty unless `git_read`; then the HEAD sha and every ref with its
  object (`git for-each-ref`) of the working repository
  (`history = trace.git_read ? hist : ''`).

What the identity compares, in one sentence for the product doc and the
canon: the bytes of every file of the suite's disposable checkout that the
operating system recorded as read, replaced or deleted during the passing run
(every file, when that includes the git index), the list of file paths in the
checkout, HEAD and every ref when the run read the checkout's git directory,
the harness files, and the env, args, runtime and policy components.
Caveat: anything the suite depends on that is not a file inside its disposable
checkout, or that it reads without the operating system advancing the file's
access time, is not compared.

### D4 Record: fail closed

`record` writes a store entry only when everything SPEC-0266 D5 requires
holds and, in addition: the trace file exists, parses, names this suite and
this run (`no-trace` otherwise, decided before any context is loaded, never a
throw); its `canary` is true (`if (!trace.canary) return no('trace-unavailable');`);
and the env, args, runtime, policy and history values and the harness hashes
that `check` computed before the run equal the values computed after it
(`inputs-changed-during-run`).
Content needs no before and after comparison: the recorded hashes are the
bytes the suite's checkout held when it started. Store records keep the
SPEC-0266 D5 fields and add `paths` and `env_names` so a later miss can name
the path. A record never claims more than the trace saw; reads the trace cannot
see are what the admission gate (D5) and the caveat in D3 are for.

### D5 Admission gate: `lint --admit`

`node .aai/scripts/suite-reuse.mjs lint --admit [--suite S ...] [--changed-since REF]`
replaces `lint --minimal-tree`. It runs `lint`, then for each selected
manifest suite:

1. builds a scratch repository: `git clone --local --no-hardlinks` of the
   working repository, then every path-list file copied from the working tree
   over it, every tracked file deleted in the working tree removed, and the
   seed paths copied, so it holds the working tree with full history;
2. runs `bash tests/skills/test-framework.sh --skill S` there with reuse on,
   no `CI`, and `NODE_OPTIONS=--require <abs>/tests/skills/lib/read-trace.cjs`
   with `AAI_TRACE_OUT` set; requires a pass and a store record;
3. cross-check: every Node content read (`readFileSync`, `readFile`,
   `createReadStream`, `fs.promises.readFile`) of a file that existed in the
   framework's checkout at arm must be an input of the trace
   (`const missed = nodeReadsMissing(`); otherwise
   `ADMIT-FAIL <suite> trace-misses-node-read <path>`. read-trace.cjs logs the
   function name per line and logs nothing in a process whose entry script is
   suite-reuse.mjs;
4. probes, through `check` on the scratch repository: one byte appended to
   the first input in sort order that is not the suite file gives
   `RUN <suite> reason=inputs` (`expect: 'RUN'`); one byte appended to the
   first path-list file that is not an input, or when there is none to a new
   gitignored file `tests/skills/results/admit-probe.txt`, gives `REUSE`;
   each probe is reverted;
5. poisoned run: every path-list file that is not an input is overwritten by
   `poisonFile(abs, rel);` with the single line `AAI-REUSE-POISON <path>`, and
   the framework runs the suite fresh (`AAI_SUITE_REUSE=0`); it must pass
   (`const passed = r.status === 0` together with `Passed: 1 (100%)` and no
   failed or skipped line). With nothing to poison the step is reported as
   `poisoned=0` and not run.

Output per suite: `ADMIT-PASS <suite> <seconds>s reads=<n> poisoned=<n>` or
`ADMIT-FAIL <suite> <seconds>s <reason>`; exit 1 on any failure. With
`--changed-since REF` only manifest suites whose entry differs from the
manifest at REF, or whose suite file differs from REF, are admitted
(`function entryChanged(base, suite) {`); none gives one line `ADMIT-NONE`
and exit 0; a REF that does not resolve admits every suite. Under `CI` or
`GITHUB_ACTIONS=true` it prints `ADMIT-OFF ci` after the lint result and
exits with the lint result (A2). A suite whose admission fails must not be in
the manifest. What it proves: the suite passes from a clean scratch copy with
every file it did not read replaced, its trace saw every Node read, and one
read and one unread edit move it the right way; it cannot show the same for a
future version of the suite.

### D6 Manifest and selection

- `tests/skills/suite-reuse.json` lists the six named suites
  (aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-prompt-diet,
  aai-ride-status, aai-win-fallback) and keeps aai-feedback-status,
  aai-pricing, aai-redact, aai-orchestration-mode and aai-runtime-file, each
  with `live: false` and a `note` rewritten for the trace (what it reads, from
  the admission output; network and clock statements kept). aai-orchestration-mode's
  `inputs: ["CHANGELOG.md"]` may stay (an extra input only adds misses).
- The `aai-suite-reuse` suite-map row gains the six suite files, so editing
  one selects the suite that re-admits it (the existing convention of that
  row). Cost disclosed: a ride that edits test-aai-hygiene-pack.sh pays about
  95 s for its admission.
- Not changed: CI selection for every existing path (SPEC-0266 D13), modes
  and off reasons (D6 there), reporting (D7 there), store location, the roles
  that may consume reuse (D8 there).

### D7 Ledger mechanisms: no write change in this slice

Measured (M2, M5): a ledger is an input only of a suite that reads it, and
the suites that read the ledgers also read every production script. Excluding
a ledger by name from the identity would be a false hit for exactly those
suites and is rejected. Moving the framework's local append out of the
tracked `docs/ai/tests/test-runs.jsonl` touches nine consumers
(`pr-sweep`, `recheck`, `orchestration-dispatch`, `merge-cleanup` and
others) and buys nothing after a code edit; it is recorded as
`fu-reuse-local-ledger-append` (Split).

### D8 The source-text reader is removed

`computeClosure`, the after-literal rule, the `lib/` allowlist, the
own-directory and root-variable rules, `HISTORY_RE`, `MARKER_RE` and the
`MINIMAL_TREE_FRAMEWORK` array leave `suite-reuse.mjs`. `explain --suite S`
prints the suite's last record: input count by top directory, whether it read
the git directory and the index, the env names, and the run id; with no
record it says so. The helper stays at most 600 lines; its imports are `node:`
modules, `./select-suites.mjs`, `./lib/tree-hash.mjs`,
`./lib/runtime-file.mjs` and `./lib/checkout-trace.mjs`
(`import { armTrace, collectTrace } from './lib/checkout-trace.mjs';`).

### D9 Canon wording

`.aai/SKILL_VERIFY.prompt.md` Reuse exception: "had the same declared inputs,
env, args, runtime, policy and history" becomes "had the same files read, env,
args, runtime, policy and history". The prompt glob shrinks by 5 B, so no
diet-ledger entry and no TEST-012 move are owed; test-aai-prompt-diet.sh runs
in Verification. VALIDATION.prompt.md is unchanged.

### D10 Windows

On NTFS with last-access updates off, and on any file system that does not
advance access times, the canary is false and nothing is recorded: reuse is
off there, failing closed (Git Bash degraded mode already turns it off,
SPEC-0266 D5). `tests/skills/suite-reuse.Tests.ps1` keeps its four cases,
adapted to write a synthetic trace file before `record`; TEST-3184 still
requires at least 4 passed, 0 failed, 0 skipped.

### D11 Measurement protocol (analysis note, new section)

In a disposable detached worktree of the implementation tip, never the shared
main checkout, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE` unset, command per sample
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <each suite>`
over the suite list L = CORE (aai-check-state, aai-docs-content,
aai-spec-lint, aai-hygiene-pack) plus aai-pr-preflight (selected by the R1
delta) plus aai-prompt-diet, aai-ride-status and aai-win-fallback (8 suites):

- Seed: one run with reuse on; snapshot `tests/skills/results/reuse/`.
- R0, zero delta: no edit. R1, one production line: one comment line appended
  to `.aai/scripts/pr-preflight.mjs`.
- Per round six samples alternating off (`AAI_SUITE_REUSE=0`) and on,
  restoring the store snapshot before each on sample.
- The note's new heading is `## Measurements (trace identity)`: one row per
  sample (round, mode, wall seconds, executed, reused, check seconds), medians
  and worst per mode and round, per suite of L in each on sample REUSED or the
  RUN reason with its first path, the per-suite read counts from the
  records, the arm plus collect milliseconds per traced suite, the commit sha
  and host, OS, Node, Bash and Git versions. The SPEC-0266 section stays as
  history. No requirement that on beats off.

### D12 Rejected alternatives

- Fixing the three mechanisms in the source-text reader: still a parser in a
  gate, and M2 shows the true read sets of five of the six suites are the
  whole checkout, so a correct reader gains nothing for them.
- Excluding ledgers or EVENTS/STATE by name: a false hit for the suites that
  read them (all five large suites do).
- A poisoned verification run on every record: doubles the cost of every
  miss; it runs at admission instead.
- Hashing the whole checkout for every suite: exact but makes aai-ride-status
  miss on any edit; the trace keeps it at 27 files.
- `core.trustctime=false` in the checkout: not needed (M3) and would change
  the checkout's git config that suites can read.

## Acceptance Criteria Mapping

- Intake AC-001 (six suites in the manifest, admission passes) maps to
  Spec-AC-06.
- Intake AC-002 (a read file edit makes it RUN, an unread file edit, ledgers
  included, leaves it REUSED; tested) maps to Spec-AC-05 (probes per suite in
  the admission gate) and Spec-AC-04 (ledgers).
- Intake AC-003 (framework ledger writes no longer change the identity of a
  suite that does not read them) maps to Spec-AC-04.
- Intake AC-004 (fails closed on what it cannot account for, at least one
  unobserved-read case) maps to Spec-AC-03.
- Intake AC-005 (representative round off and on, three samples each,
  recorded) maps to Spec-AC-09.
- Intake scope "weigh a run-time read trace against the tokenizer, choose the
  exact approach" maps to D1, M1 to M5, Spec-AC-01, Spec-AC-02.
- Intake constraint "state exactly what the identity compares, one caveat"
  maps to D3 and Spec-AC-08 (canon wording).

## Constitution deviations

- Article 5 (additive first): `suite-reuse.mjs lint --minimal-tree` is
  replaced by `lint --admit`, the store record gains fields and a policy
  version bump invalidates every existing record once. Justified: the helper
  CLI is an internal test-harness interface with one caller pair (the suite
  and Verification), the store is gitignored local runtime data, and the
  change is documented in the product doc and the CHANGELOG entry.
- Article 1 (evidence produced in this session): no new deviation; the
  SPEC-0266 justification for reused evidence applies unchanged.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a declared fixture suite runs through the real framework with reuse on THEN $RUN_DIR holds a reuse-trace file for it whose inputs list exactly the checkout files the suite read with bash cat, grep, source and node readFileSync, a file it replaced with sed -i and a file it deleted, and not a checkout file it did not read nor a file it created; git_read and index_read are true only for a suite that ran git status in its checkout, and canary is true | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3260, TEST-3261); docs/ai/tdd/reuse-for-docs-reading-suites/red/node-326x-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runA.txt | — | D2 |
| Spec-AC-02 | WHEN only one of these changes between record and check THEN check prints RUN with that component: a traced input file (inputs, naming the path), an added or removed untracked file the suite never read (paths), any tracked file for a suite whose trace read the git index (inputs), HEAD for a suite whose trace read the git directory (history), a variable named only in a file the suite read (env); a change to a file the suite did not read, and HEAD for a suite that did not read the git directory, still give REUSE; IDENTITY_COMPONENTS equals the D3 literal and the helper holds no source-text reader | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3262 to TEST-3267); docs/ai/tdd/reuse-for-docs-reading-suites/red/node-326x-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runA.txt | — | D3 D8 |
| Spec-AC-03 | WHEN the trace file is missing, unparseable or names another suite, or its canary is false, or env, args, runtime, policy or history moved during the run THEN record prints NOT-RECORDED with no-trace, trace-unavailable or inputs-changed-during-run and writes nothing; WHEN a fixture suite reads a file and then restores its access time with bash, or reads it with node and restores it THEN lint --admit prints ADMIT-FAIL for it (poisoned run failed, or trace-misses-node-read) and exits 1 | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3268 to TEST-3271); docs/ai/tdd/reuse-for-docs-reading-suites/red/node-326x-baseline.log, docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3270_poisoned_run-baseline.log, docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3271_node_read_cross_check-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runB.txt, docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runC.txt | — | D4 D5 |
| Spec-AC-04 | WHEN a declared fixture suite that reads none of docs/ai/tests/test-runs.jsonl, docs/ai/EVENTS.jsonl and docs/ai/STATE.yaml passed THEN the next framework run reports it REUSED although the framework appended a line to test-runs.jsonl after the first run, and it stays REUSED after a line is appended to EVENTS.jsonl and STATE.yaml changes; a second fixture suite that reads EVENTS.jsonl through a path built at run time gives RUN reason=inputs changed docs/ai/EVENTS.jsonl after that append | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3272); docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3272_ledgers_not_inputs-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runB.txt | — | D3 D7 |
| Spec-AC-05 | WHEN lint --admit runs on a fixture manifest with an honest suite THEN it prints ADMIT-PASS with reads and poisoned counts after the read probe gave RUN and the unread probe gave REUSE, and exits 0; with --changed-since naming a ref whose manifest and suite files equal the working tree it prints ADMIT-NONE and runs no suite, and with one changed entry it admits only that suite; under CI it prints ADMIT-OFF ci | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3273, TEST-3274); docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3273_admission_pass-baseline.log, docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3274_changed_since_and_ci-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runC.txt | — | D5 |
| Spec-AC-06 | lint exits 0 on the live repository and the live manifest lists the six named suites and the five earlier ones, each live false with a non-empty note and a row selecting it in the aai-suite-reuse suite-map globs; lint --admit --changed-since main exits 0 on the branch tip locally with one ADMIT-PASS line for each of the eleven suites | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3275, TEST-3276); docs/ai/tdd/reuse-for-docs-reading-suites/admit-live-3.txt (eleven ADMIT-PASS); docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3275_live_manifest-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runC.txt | — | D5 D6 |
| Spec-AC-07 | WHEN the framework runs a declared suite with reuse on THEN reuse-arm and reuse-trace files exist for it in serial mode and with AAI_TEST_PARALLEL=2; WHEN the suite is not declared, or the run is opted out THEN no arm or trace file exists for it; a failing arm does not change the suite verdict | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3277); docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3277_framework_wiring-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runB.txt | — | D2 |
| Spec-AC-08 | SKILL_VERIFY's Reuse exception says files read where it said declared inputs, and cat .aai/*.prompt.md is not larger than on the baseline 5e9f1350; test-aai-prompt-diet.sh TEST-010 and TEST-012 pass | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3278); test-aai-prompt-diet.sh exit 0; docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3278-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runD.txt | — | D9 |
| Spec-AC-09 | docs/analysis/precise-suite-evidence-reuse.md has a heading Measurements (trace identity) with at least 3 samples per mode in each of rounds R0 and R1 over the 8 suites of D11, medians and worst per mode and round, per suite REUSED or its first RUN reason in each on sample, per-suite read counts, arm plus collect milliseconds, a 40-character commit sha and host, OS, Node, Bash and Git versions | done | docs/ai/tdd/reuse-for-docs-reading-suites/green/suite-reuse-final.log (TEST-3279); docs/analysis/precise-suite-evidence-reuse.md section Measurements (trace identity), commit 770210a1c5c2081339bcc9482b0a518c9db1f8f8; docs/ai/tdd/reuse-for-docs-reading-suites/red/test_3279-baseline.log; docs/ai/tdd/spec-reuse-for-docs-reading-suites/mutation-runD.txt | — | D11 |

## Implementation plan

- New `.aai/scripts/lib/checkout-trace.mjs` (D2) and its PROFILES.yaml core
  row beside suite-reuse.mjs.
- `.aai/scripts/suite-reuse.mjs`: `arm` and `collect` subcommands, `TRACE`
  lines from `check`, identity per D3, record per D4, `lint --admit` per D5,
  `explain` per D8; source-text reader removed.
- `tests/skills/test-framework.sh`: `reuse_trace_arm` and
  `reuse_trace_collect` around `suite_execute` in `run_test` and
  `suite_child`, for `TRACE` suites only.
- `tests/skills/lib/read-trace.cjs`: function name per line; silent in the
  helper's own process.
- Manifest, suite-map row, Pester adaptation, SKILL_VERIFY wording, analysis
  note section.
- Existing tests in `tests/skills/test-aai-suite-reuse.sh` and
  `tests/skills/lib/suite-reuse.test.mjs`: TEST-3167 (source-text reader),
  TEST-3172 (text history marker), TEST-3193 (Node read honesty) and TEST-3194
  (minimal tree) are retired, superseded by TEST-3260 to TEST-3279; TEST-3188
  keeps its PROFILES and selection checks, its import and IDENTITY literal
  checks move to TEST-3267; every other SPEC-0266 row keeps its assertion and
  is adapted only to supply a trace where it records (a fixture run through
  the real framework produces one; a direct `recordSuite` call gets a
  synthetic trace file).

### Seams crossed

| Seam | Producer | Consumer | Test |
|---|---|---|---|
| S1 disposable checkout | framework iso_create seeding | helper arm and collect | TEST-3260, TEST-3277 (real framework, serial and wave paths) |
| S2 trace to store | collect trace file | record, then the next check | TEST-3262, TEST-3268, TEST-3272 |
| S3 framework ledger append | framework summary writing test-runs.jsonl | next run's check of the same suite | TEST-3272 |
| S4 admission | helper lint --admit | real framework run in a scratch clone, and check | TEST-3270, TEST-3273, TEST-3276 |
| S5 Node preload | read-trace.cjs in suite processes | admission cross-check against the access trace | TEST-3271 |
| S6 git directory | suite git commands in the checkout | history component and index rule | TEST-3261, TEST-3264, TEST-3265 |
| S7 canon | SKILL_VERIFY | roles citing reused evidence | TEST-3278 (text only, residual R3) |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3260 | Spec-AC-01 | integration | tests/skills/test-aai-suite-reuse.sh | test_3260: fixture repository with the real framework and helper; declared suite fx reads a.txt with cat, b.txt with grep, sources c.sh, reads d.txt with node readFileSync, rewrites e.txt with sed -i, deletes f.txt and creates g.txt; after one run the reuse-trace file lists a.txt, b.txt, c.sh, d.txt, e.txt and f.txt as inputs, not u.txt (never read) nor g.txt, canary true, git_read false | `sed:s/const wasRead = st.atimeMs \/ 1000 > ATIME_FLOOR;/const wasRead = false;/` on .aai/scripts/lib/checkout-trace.mjs | green |
| TEST-3261 | Spec-AC-01 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3261: armTrace then collectTrace on a scratch git checkout; a file replaced by rename counts as an input, a directory listing alone does not make its files inputs, git rev-parse sets git_read and not index_read, git status sets both | `sed:s/st.ino !== armed.ino/false/` on .aai/scripts/lib/checkout-trace.mjs | green |
| TEST-3262 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3262: recordSuite with a synthetic trace naming docs/x.md; editing docs/x.md gives RUN reason=inputs changed docs/x.md; editing docs/y.md (in the path list, not traced) gives REUSE | `sed:s/'inputs', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3263 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3263: adding an untracked file no trace names gives RUN reason=paths added that path; deleting an untraced tracked file gives reason=paths removed | `sed:s/'paths', //` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3264 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3264: a commit that moves HEAD gives RUN reason=history for a record whose trace has git_read true and REUSE for one whose trace has git_read false | `sed:s/trace.git_read ?/true ?/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3265 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3265: with index_read true in the trace, editing a tracked file the trace does not name gives RUN reason=inputs changed that file; with index_read false the same edit gives REUSE | `sed:s/if (trace.index_read)/if (false)/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3266 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3266: a trace whose input module names process.env.FIXTURE_Q; changing FIXTURE_Q gives RUN reason=env; changing an unreferenced FIXTURE_Z gives REUSE | `sed:s/referencedNames(texts)/referencedNames([])/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3267 | Spec-AC-02 | contract | tests/skills/test-aai-suite-reuse.sh | test_3267: suite-reuse.mjs has the D3 IDENTITY_COMPONENTS line, at most 600 lines, imports only node: modules and the four D8 local modules, and contains none of computeClosure, TOKEN_RE, HISTORY_RE, MARKER_RE, MINIMAL_TREE_FRAMEWORK; checkout-trace.mjs has at most 200 lines and imports only node: modules and ./tree-hash.mjs | `sed:s/import { armTrace, collectTrace } from '.\/lib\/checkout-trace.mjs';/import { armTrace, collectTrace } from '.\/lib\/checkout-trace2.mjs';/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3268 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3268: recordSuite with no trace file, an unparseable one, one naming another suite, one with canary false, and one whose pre-run history differs from the post-run value gives recorded false with no-trace, no-trace, no-trace, trace-unavailable and inputs-changed-during-run, never throws, and writes no store file | `sed:s/if (!trace.canary)/if (false)/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3269 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3269: armTrace with an injected access-time probe that reports no advance returns canary false, and the CLI arm on a normal temp checkout returns canary true | `sed:s/const canary = atimeAdvances(/const canary = true; void (/` on .aai/scripts/lib/checkout-trace.mjs | green |
| TEST-3270 | Spec-AC-03 | integration | tests/skills/test-aai-suite-reuse.sh | test_3270: fixture manifest with suite hide that reads secret.txt with cat, asserts its first line and restores its access time with touch -a -t 200001010000; lint --admit prints ADMIT-FAIL hide (poisoned run failed) and exits 1 | `sed:s/poisonFile(abs, rel);/void 0;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3271 | Spec-AC-03 | integration | tests/skills/test-aai-suite-reuse.sh | test_3271: fixture manifest with suite nodehide whose node script reads n.txt with readFileSync and restores its access time with fs.utimesSync, and that never fails on content; lint --admit prints ADMIT-FAIL nodehide trace-misses-node-read n.txt and exits 1 | `sed:s/const missed = nodeReadsMissing(/const missed = [], unusedMissed = nodeReadsMissing(/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3272 | Spec-AC-04 | integration | tests/skills/test-aai-suite-reuse.sh | test_3272: fixture repository with tracked docs/ai/tests/test-runs.jsonl and docs/ai/EVENTS.jsonl and a seeded STATE.yaml; fx reads none of them, fy reads EVENTS through f=docs/ai/EVENTS then cat of the f variable with .jsonl appended; run 2 reports fx and fy REUSED and test-runs.jsonl grew by one line per run; after an EVENTS append and a STATE edit fx stays REUSED and fy prints RUN reason=inputs changed docs/ai/EVENTS.jsonl (baseline: fy REUSED, the false hit) | `sed:s/'.gitignore',/'.gitignore', 'docs\/ai\/tests\/test-runs.jsonl',/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3273 | Spec-AC-05 | integration | tests/skills/test-aai-suite-reuse.sh | test_3273: fixture manifest with honest suite ok that reads one of three data files; lint --admit prints ADMIT-PASS ok with reads and poisoned=2 and exits 0, and its log shows the read probe as RUN and the unread probe as REUSE | `sed:s/expect: 'RUN'/expect: 'REUSE'/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3274 | Spec-AC-05 | integration | tests/skills/test-aai-suite-reuse.sh | test_3274: fixture with a committed base; lint --admit --changed-since the base prints ADMIT-NONE and exit 0; after changing one manifest note only that suite gets an ADMIT line; with CI=true it prints ADMIT-OFF ci and runs no suite | `sed:s/function entryChanged(base, suite) {/function entryChanged(base, suite) { return true;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3275 | Spec-AC-06 | contract | tests/skills/test-aai-suite-reuse.sh | test_3275: lint on the live repository exits 0; the live manifest has the eleven suites of D6 each with live false and a non-empty note; the real select-suites.mjs selects aai-suite-reuse for each of the six named suite files | `sed:s/"aai-hygiene-pack"/"aai-hygiene-packx"/` on tests/skills/suite-reuse.json | green |
| TEST-3276 | Spec-AC-06 | contract | tests/skills/test-aai-suite-reuse.sh | test_3276: lint --admit --changed-since main on the live repository exits 0 and prints ADMIT-PASS for every suite that differs from main (on this branch all eleven), or ADMIT-OFF ci under CI | `sed:s/const passed = r.status === 0/const passed = r.status !== 0/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3277 | Spec-AC-07 | integration | tests/skills/test-aai-suite-reuse.sh | test_3277: two-suite fixture, one declared and one not; with reuse on, serial and with AAI_TEST_PARALLEL=2, the declared suite has reuse-arm and reuse-trace files and the undeclared has neither; with AAI_SUITE_REUSE=0 neither has; with the helper's arm made to exit 1 the declared suite still passes | `sed:s/reuse_trace_arm "\$skill_name"/: "$skill_name"/` on tests/skills/test-framework.sh | green |
| TEST-3278 | Spec-AC-08 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3278: the Reuse exception paragraph of SKILL_VERIFY contains files read and not declared inputs; the byte count of cat .aai/*.prompt.md is at most the count of the same glob at 5e9f1350 (git show per file) | `sed:s/had the same files read, env/had the same declared inputs and files read, env/` on .aai/SKILL_VERIFY.prompt.md | green |
| TEST-3279 | Spec-AC-09 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3279: the analysis note has a line equal to ## Measurements (trace identity), at least 3 rows per mode for R0 and R1, a per-suite outcome for each of the 8 D11 suites, medians, read counts, arm plus collect milliseconds, a 40-character sha and Node, Bash and Git versions | `sed:s/## Measurements (trace identity)/## Measurementz (trace identity)/` on docs/analysis/precise-suite-evidence-reuse.md | green |

RED plan, observed on the baseline `5e9f1350` before each fix and stored
under `docs/ai/tdd/reuse-for-docs-reading-suites/red/`:

- TEST-3260, TEST-3261, TEST-3269, TEST-3277: no `arm`/`collect`
  subcommand, no checkout-trace module, no trace files.
- TEST-3262 to TEST-3266, TEST-3268: no `paths` component, no trace input to
  `record`; the history and env rules read the static closure.
- TEST-3267: the source-text reader is present and the import is absent.
- TEST-3270, TEST-3271, TEST-3273, TEST-3274, TEST-3276: `lint --admit` does
  not exist (lint prints no ADMIT line).
- TEST-3272: on the baseline fy is REUSED after the EVENTS append, because its
  built path is invisible to the source-text reader (the false hit this scope
  removes).
- TEST-3275: the manifest lacks the six named suites.
- TEST-3278: SKILL_VERIFY says declared inputs. TEST-3279: no such section.

Mutation semantics: `mutation-run.mjs` replaces the FIRST occurrence of OLD in
the whole file, so each literal a mutation names (the D2, D3, D4 and D5
code literals quoted above, `reuse_trace_arm "$skill_name"`) must first occur
at its decisive site; if the implementation cannot place it so, the row's
mutation is amended additively with disclosure, never dropped.

TDD run split (about three ACs per run):

- Run A: Spec-AC-01, Spec-AC-02 (checkout-trace module, arm and collect,
  identity, reader removal; TEST-3260 to TEST-3267).
- Run B: Spec-AC-03, Spec-AC-04, Spec-AC-07 (record rules, framework wiring,
  ledger independence; TEST-3268, TEST-3269, TEST-3272, TEST-3277, and the
  adaptation of the kept SPEC-0266 rows).
- Run C: Spec-AC-05, Spec-AC-06 (admission gate, manifest, suite-map row;
  TEST-3270, TEST-3271, TEST-3273 to TEST-3276).
- Run D: Spec-AC-08, Spec-AC-09 (canon wording, Pester adaptation, then the
  measurement; TEST-3278, TEST-3279).

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-suite-reuse.sh` (includes the live admission, several minutes on
  this branch), `test-aai-suite-select.sh`, `test-aai-suite-isolation.sh`,
  `test-aai-sweep-parallel.sh`, `test-aai-repo-tripwire.sh` (fixture
  frameworks), `test-aai-release-first.sh`, `test-aai-win-fallback.sh`,
  `test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh`,
  `test-aai-layer-profiles.sh` (PROFILES row), `test-aai-hygiene-pack.sh`,
  plus `node .aai/scripts/select-suites.mjs --base-ref main` selected plus
  CORE. Intermediate rounds: selected plus CORE; one full sweep before close
  with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/suite-reuse.mjs lint --admit --changed-since main`
  exits 0 with eleven ADMIT-PASS lines; output stored under
  `docs/ai/tdd/reuse-for-docs-reading-suites/`.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exit 0 before
  close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Post-PR checks (not Spec-ACs, not claimed by local Validation)

- H1: on the PR head the ps1-quality run concludes success and every case of
  `suite-reuse.Tests.ps1` passes in both Windows jobs.
- H2: the PR head's skill-suite run concludes success; its framework jobs
  print `Evidence reuse: off (ci)` and the aai-suite-reuse job prints
  `ADMIT-OFF ci`.

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

Run by the orchestrator after flush, before the PR; then run
`set-code-review` again with this file list as scope.

1. Product doc `docs/product/precise-suite-evidence-reuse.md`: the D3
   sentence and caveat replace "complete input identity" wording; Limits say
   that five of the six named suites read the whole checkout and so reuse only
   when no tracked file changed, that reuse is off where access times are not
   recorded, and how to read `lint --admit`.
2. CHANGELOG.md: one `## [unreleased] — <title>` heading entry naming the
   `lint --minimal-tree` to `lint --admit` change.
3. Register `fu-reuse-split-corpus-cases` and `fu-reuse-local-ledger-append`
   (Split); close the follow-ups listed below.
4. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/reuse-for-docs-reading-suites/red/, a mutation record per Test
Plan row under docs/ai/tdd/spec-reuse-for-docs-reading-suites/, and green
suite outputs. A REUSED suite line is not evidence for any row of this spec:
its suites run with `AAI_SUITE_REUSE=0`.

## Files Implementation touches

- .aai/scripts/lib/checkout-trace.mjs (new)
- .aai/scripts/suite-reuse.mjs
- .aai/system/PROFILES.yaml (core row for the new module)
- tests/skills/test-framework.sh
- tests/skills/suite-reuse.json
- tests/skills/suite-map.yaml (aai-suite-reuse row globs only)
- tests/skills/lib/read-trace.cjs
- tests/skills/lib/suite-reuse.test.mjs
- tests/skills/test-aai-suite-reuse.sh
- tests/skills/suite-reuse.Tests.ps1
- .aai/SKILL_VERIFY.prompt.md
- docs/analysis/precise-suite-evidence-reuse.md
- docs/issues/CHANGE-DRAFT-reuse-for-docs-reading-suites.md
- docs/specs/SPEC-DRAFT-spec-reuse-for-docs-reading-suites.md
- docs/product/precise-suite-evidence-reuse.md (close-out)
- CHANGELOG.md (close-out)
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

One new `.aai/**` file (checkout-trace.mjs), classified in PROFILES.yaml core
beside suite-reuse.mjs (layer-profiles suite in Verification). The prompt
glob shrinks, so no diet-ledger entry is owed. Not touched: aai-run-tests.sh,
.ps1, every protected_paths_l3 file, AGENTS.md, WORKFLOW.md, VALIDATION.prompt.md,
existing suite-map rows other than aai-suite-reuse, every ledger writer.

## Risks and rollback

- R1 False hit through a read the trace does not see: a file outside the
  disposable checkout (home directory, temp files, absolute paths, the
  network, the clock), or a read that does not advance an access time (an
  APFS clone copy such as `ditto` or `cp -c`, a process that restores access
  times). The admission gate's poisoned run and Node cross-check catch such a
  read at admission; a later suite change that adds one is not caught until
  the next admission. Background readers of the checkout (indexers) only add
  inputs, never remove them. Every final-verdict context still executes fresh.
- R2 The five large suites read the whole checkout, so their saving on a
  remediation round is zero by construction (M2); D11 measures it and the
  note says so.
- R3 Role behavior when citing reused evidence is prompt text; TEST-3278
  checks the text only.
- R4 The live admission makes the aai-suite-reuse suite several minutes long
  on rides that change the manifest or a manifest suite file (D6).
- R5 A host whose file system does not record access times loses reuse
  entirely (canary false); this fails closed and is stated in the product
  doc.
- Rollback: `AAI_SUITE_REUSE=0` disables reuse; reverting the PR restores the
  source-text reader; deleting `tests/skills/results/reuse/` is always safe.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list --status open` (282 open) has ten
`precise-suite-evidence-reuse` items. This scope removes the source-text
reader and the text history marker they describe, so it closes six of them;
`fu-reuse-docs-closure-suites` stays open because the measured blockers of the
five large suites are real reads, not identity artifacts (Split); left open as
unrelated: `fu-reuse-record-max-age`, `fu-reuse-distro-exported-functions`,
`fu-test021c-fifo-open-eintr`.

## Registry items closed by this scope

fu-reuse-history-marker-scope, fu-reuse-comma-colon-literal,
fu-reuse-lib-dirname-base, fu-reuse-lib-after-expansion,
fu-reuse-trailing-dot-literal, fu-reuse-mutation-rows-3167
