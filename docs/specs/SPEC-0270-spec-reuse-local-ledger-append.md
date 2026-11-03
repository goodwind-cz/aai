---
id: spec-reuse-local-ledger-append
type: spec
number: 270
status: done
mutation_gate: v1
frozen_sha256: f96193ff4dce5e9c6c44f9ba381f1f7c4c75a07d280b085ee9faeeb8e54b00e2
ceremony_level: 2
links:
  requirement: reuse-local-ledger-append
  rfc: RFC-0017
  pr: []
  commits: []
---

# An unchanged rerun reuses index-reading suites: the run ledger is compared on the bytes the suite's checkout held, appended lines tolerated

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-0243-reuse-local-ledger-append.md
- Prior slices: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md,
  docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md (D3 identity,
  D5 admission gate, D7 which rejected a by-name ledger exclusion; this spec
  revisits D7 with new measurements, M3 and M4)
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (stays open)
- Measurement note: docs/analysis/precise-suite-evidence-reuse.md
- Product doc: docs/product/precise-suite-evidence-reuse.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor;
  system Bash 3.2 and GNU Bash for suites)
- Baseline commit: `9c487740cf606419046a3f5488508520507ff9e3` (main at
  planning time)

## Implementation strategy

- Strategy: tdd
- Rationale: the change narrows a reuse identity, and the hazard of every
  narrowing is a false hit (a stale pass reported as fresh). Each rule that
  keeps a real change a miss must be observed failing first, and the rule
  that turns today's miss into a hit (TEST-3300) has an observed RED on the
  baseline. Mutation gate v1 applies.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound; edits the reuse helper every local framework
  run consults; mutation runs rewrite it and the measurement needs seed runs
  and zero-delta reruns that append to the tracked run ledger, which must not
  reach the shared main checkout. No file is in `protected_paths_l3`.
- User decision: worktree (autopilot default;
  /Users/ales/Projects/aai-worktrees/reuse-local-ledger-append, branch
  feat/reuse-local-ledger-append)
- Base ref: main
- Inline review scope: the list in "Files Implementation touches".
- Code review required: true.

## What Planning measured

All on the baseline commit in the ride worktree (macOS 27.0.1, Apple M4 Max,
Node v22.23.1, GNU bash 3.2.57, Git 2.54.0), suites with `AAI_ROLE` unset and
`AAI_TEST_TIMEOUT=3000`; the run ledger was restored after every run.

### M1 The zero-delta miss and its only cause

One framework run of the eleven suites of `tests/skills/suite-reuse.json`
with reuse on (exit 0, 110 s, all eleven `RECORDED`), then
`suite-reuse.mjs check` for the same eleven with no edit in between:

- REUSE: aai-ride-status, aai-feedback-status, aai-pricing, aai-redact,
  aai-orchestration-mode, aai-runtime-file (6).
- RUN reason=inputs changed docs/ai/tests/test-runs.jsonl: aai-docs-content,
  aai-spec-lint, aai-hygiene-pack, aai-prompt-diet, aai-win-fallback (5).

Recomputing each identity with the helper's own exported functions against
its record: for each of the five, exactly one identity component differs
(`inputs`) and exactly one input differs (`docs/ai/tests/test-runs.jsonl`);
for the six, nothing differs. Their records: reads 1550, 1493, 1965, 1949
and 1949 files, `index_read` true for all five, false for the six.

### M2 Who consumes the tracked run ledger

`grep` over `.aai`, `.github`, `tests`, `.claude`, `.codex`, `.gemini`:

- No script parses the ledger's content to decide anything. The scripts that
  name it treat it as an append-only ledger by path: `check-committed-scope.mjs`
  (LEDGER_PATHS, prefix rule for committed blobs), `lib/pr-sweep.mjs`
  (STALE_HEAD_SAFE_LEDGERS), `lib/recheck.mjs` and `orchestration-dispatch.mjs`
  (excluded from the dispatch tree hash), `merge-cleanup.mjs` (ledger union),
  `tests/skills/suite-map.yaml` (`carry_forward_globs` and the
  aai-repo-tripwire row), `.aai/SUBAGENT_CONTRACT.md` (HAZ-LEDGER), the
  append lock and comments in `aai-run-tests.sh` and `mutation-run.mjs`.
- No workflow under `.github/` references it. `tests/skills/suite-weights.tsv`
  is a separate file and is not derived from the ledger.
- Every suite that reads a `test-runs.jsonl` reads a fixture ledger in its
  own temp repository (test-aai-suite-isolation, test-aai-sweep-parallel,
  test-aai-suite-reuse, test-aai-merge-cleanup, test-aai-repo-tripwire).

### M3 The ledger "read" of an index-reading suite is git's index refresh

On a two-file scratch repository: `armTrace`, then one `git status`, then
`collectTrace` lists both tracked files as read and sets `index_read`;
`armTrace`, `git ls-files`, `collectTrace` sets `index_read` and lists no
file. Arm resets access times with `lutimes`, which changes each file's
ctime, so git's stat check misses and git re-reads every tracked file. The
trace of an index-reading suite therefore lists the ledger (and every other
tracked file) whether or not the suite looks at it; SPEC-0268 M2's "the
suites that read the ledgers" measured this refresh, not the suites.

### M4 The five suites do not depend on the ledger's content

In a local clone of the baseline with `docs/ai/tests/test-runs.jsonl`
replaced by the single non-JSON line `AAI-REUSE-POISON not json` and
committed, the five index-reading suites ran through the framework with
`AAI_SUITE_REUSE=0`: all five PASS, exit 0, 104 s.

### M5 What follows for the candidates of the intake

- Moving the framework's write to an untracked local file and landing it in
  the tracked ledger later: the file would have to be gitignored as well
  (an untracked file is still in the path list an index-reading identity
  hashes), the nine path-list consumers of M2 and three suites asserting the
  tracked append would change, downstream projects would lose the tracked
  history, and a new landing mechanism would be needed. Rejected as wider
  than the defect.
- Deferring the write, or moving it outside the traced window: no effect.
  The miss is decided by the next run's `check`, which hashes the working
  tree's ledger after the append; where inside a run the append happens
  does not matter.
- Excluding the ledger path from the identity outright: would also ignore a
  rewrite or truncation of existing ledger lines. Rejected as wider than
  needed.
- Chosen (D1): compare the ledger of an index-reading suite on the bytes its
  checkout held at arm, tolerating only lines appended after them.

## Assumptions (autopilot, recorded instead of asked)

- The framework's append is the only ledger change a zero-delta rerun sees
  (M1); other append-only ledgers (EVENTS, decisions) move with role
  actions, which `fu-reuse-docs-closure-suites` owns.
- Owner metrics question skipped (human_time_minutes null).

## Decisions

### D1 Append-only tolerance for the run ledger, index-reading suites only

`.aai/scripts/suite-reuse.mjs` gains, as the first occurrence of each
literal:

- `const APPEND_ONLY_LEDGERS = ['docs/ai/tests/test-runs.jsonl'];`
- record side (`recordSuite`), in the store record:
  `append_prefix: traced.index_read ? appendPrefix(ctx, after.inputs_map) : undefined`
  where `appendPrefix` returns, for each path of `APPEND_ONLY_LEDGERS` that
  has a string hash other than `absent` in `inputs_map` and exists in the
  working tree, `{ bytes: <its size in the working tree now>, sha256: <its
  inputs_map value> }`. The `inputs_map` value is the hash the suite's
  checkout held at arm, so a size that does not reproduce it (another run
  appended during this one) only ever makes later checks miss.
- check side (`computeIdentity` with `recorded` false), after the
  `index_read` expansion, for each path of `APPEND_ONLY_LEDGERS`:
  `const tolerate = trace.index_read && trace.append_prefix && trace.append_prefix[p];`
  and when `tolerate` holds and `appendedOnly(ctx, p, tolerate)` is true,
  `inputsMap[p]` becomes `tolerate.sha256`. `appendedOnly` reads the working
  tree file and returns
  `buf.length >= prefix.bytes && contentHash(buf.subarray(0, prefix.bytes), fs.statSync(abs).mode) === prefix.sha256;`
  and false when the file is absent or unreadable.
- `traceOfRecord` passes `append_prefix` through when it is an object, and
  an empty object otherwise.

No other path, no suite without `index_read`, and no record without
`append_prefix` gets the tolerance. `REUSE_POLICY_VERSION` stays 2: a record
written before this change has no `append_prefix` and is compared exactly
as today, so it can only miss, never hit, on a ledger change.

### D2 What the identity compares afterwards

`IDENTITY_COMPONENTS` and every component are as SPEC-0268 D3, except one
input value: for a suite whose recorded trace read the git index, the value
compared for `docs/ai/tests/test-runs.jsonl` is the sha256 plus executable
bit of its first N bytes in the working tree, where N is the ledger's size
recorded with the pass, against the hash the suite's checkout held at arm.

In one sentence for the product doc: the bytes and executable bit of every
file of the suite's disposable checkout that the operating system recorded
as read, replaced or deleted during the passing run (every file, when that
includes the git index, and then for the run ledger
`docs/ai/tests/test-runs.jsonl` only the bytes it held when the run started),
the list of file paths in the checkout, HEAD and every ref when the run read
the checkout's git directory, the harness files, and the env, args, runtime
and policy components.

Caveat: anything the suite depends on that this comparison does not cover
is not seen, including lines appended to the run ledger after the recorded
run when an index-reading suite genuinely reads them. The admission gate
(D3) runs each index-reading suite once when it is admitted locally, with one non-JSON
line appended to the ledger, and the suite must still pass. That catches a
suite that parses the ledger strictly; it does not catch a lenient reader
that skips lines it cannot parse, and it is not repeated on every run.

### D3 Admission: an appended-ledger run for index-reading suites

`admitSuite` in `lint --admit`, for a suite whose admission trace has
`index_read` true, makes one further scratch clone, appends the line
`AAI-REUSE-POISON appended` to its `docs/ai/tests/test-runs.jsonl`
(creating the file when absent), runs `bash tests/skills/test-<suite>.sh` there with
`AAI_SUITE_REUSE=0`, and evaluates `const tailOk = ra.status === 0;`
(first occurrence). When `tailOk` is false the suite fails admission with
the reason `appended-ledger run failed rc=<status>`; when true the gate prints
`ADMIT-PROBE <suite> appended docs/ai/tests/test-runs.jsonl PASS` among the
suite's probe lines. A suite without `index_read` gets no such run and no
such line. This turns M4 into a guard that every future index-reading
manifest suite passes.

### D4 Manifest notes

The notes of the five index-reading suites in `tests/skills/suite-reuse.json`
say that the identity is every tracked file, with lines appended to
`docs/ai/tests/test-runs.jsonl` after the recorded run tolerated, instead of
"reused only when no tracked or untracked file changed". Changing the five
entries makes `lint --admit --changed-since main` (TEST-3276) admit exactly
those five on this branch, which exercises D3 on the live suites.

### D5 Nothing else moves

`tests/skills/test-framework.sh`, `.aai/scripts/lib/checkout-trace.mjs`,
`.aai/scripts/aai-run-tests.sh`, every ledger writer and every consumer of
M2 are unchanged: the framework keeps appending to the tracked ledger at the
end of every run.

### D6 Measurement protocol (analysis note, new section)

A new section `## Measurements (ledger append)` in
`docs/analysis/precise-suite-evidence-reuse.md`. For each of two commits,
the baseline `9c487740` ("before") and the implementation tip ("after"),
each in a disposable detached worktree of that commit, never the shared main
checkout: one framework run of the eleven manifest suites with reuse on
(the seed), then one zero-delta rerun with reuse on and no edit in between.
Command:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
with one `--skill` per manifest suite, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE`
unset. Record per commit: the 40-character sha, seed and rerun exit codes
and wall seconds, the rerun's `Evidence reuse: on (<M> of <N> ...)` line, and
per suite REUSED or the first RUN reason that `suite-reuse.mjs check`
printed against the seed's store with the framework's environment. Host,
OS, Node, Bash and Git versions once.

### D7 Rejected alternatives

- Untracked local ledger, deferred write, outright path exclusion: M5.
- Tolerating EVENTS.jsonl and decisions.jsonl the same way: they change with
  role actions, not with the framework's own run, and genuinely carry state
  some suites read; out of scope (`fu-reuse-docs-closure-suites`).
- A policy version bump: buys no safety (D1), costs one forced miss for
  every record.

## Acceptance Criteria Mapping

- Intake AC-001 (zero-delta rerun reuses the five, before and after
  recorded) maps to Spec-AC-01 (fixture, through the real framework) and
  Spec-AC-07 (live measurement).
- Intake AC-002 (any other change still misses, an edit of an existing
  ledger line included) maps to Spec-AC-02 and Spec-AC-04.
- Intake AC-003 (suites that did not read the index unchanged) maps to
  Spec-AC-03.
- Intake AC-004 (the spec states what the identity compares, one caveat)
  maps to D2; the product doc sentence is a close-out step.
- Intake risk "a suite that genuinely reads the ledger must still see
  changes" maps to Spec-AC-03 (non-index readers) and Spec-AC-05,
  Spec-AC-06 (admission guard for index readers).

## Constitution deviations

None. The store record gains one optional field (Article 5: additive; the
store is gitignored local runtime data), and the admission gate gains one
probe line and one failure reason on an internal test-harness interface.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a declared fixture suite that runs git status in its checkout (index_read) passed and the framework appended its run line to the tracked docs/ai/tests/test-runs.jsonl THEN the next framework run with no other edit reports the suite REUSED, and a third run after the second append still reports it REUSED; the ledger grew by one line per run | done | docs/ai/tdd/reuse-local-ledger-append/green/test_3300.log (TEST-3300); docs/ai/tdd/reuse-local-ledger-append/red/test_3300-baseline.log; docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3300.txt | — | D1 |
| Spec-AC-02 | WHEN only one of these changes after an index-reading record THEN check prints RUN: an existing ledger line edited at equal length (inputs changed docs/ai/tests/test-runs.jsonl), the ledger truncated, the ledger's executable bit set, a line appended to docs/ai/EVENTS.jsonl (inputs changed docs/ai/EVENTS.jsonl), another tracked file edited after a ledger append (inputs changed that file); a ledger append alone gives REUSE | done | docs/ai/tdd/reuse-local-ledger-append/green/node-3301-3302.log (TEST-3301); docs/ai/tdd/reuse-local-ledger-append/red/node-3301-3302-baseline.log; docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3301.txt | — | D1 D2 |
| Spec-AC-03 | WHEN a record's trace did not read the git index THEN a ledger append after it gives RUN reason=inputs changed docs/ai/tests/test-runs.jsonl for a suite that read the ledger, even when the record carries append_prefix; WHEN an index-reading record has no append_prefix THEN a ledger append gives RUN with the same reason | done | docs/ai/tdd/reuse-local-ledger-append/green/node-3301-3302.log (TEST-3302); docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3302.txt (RED is the mutation, green on the baseline) | — | D1 |
| Spec-AC-04 | WHEN recordSuite records an index-reading pass THEN the store record has append_prefix for docs/ai/tests/test-runs.jsonl whose bytes equal the working-tree ledger size and whose sha256 equals the record's inputs_map value for that path; WHEN the trace did not read the index THEN the record has no append_prefix | done | docs/ai/tdd/reuse-local-ledger-append/green/node-3303.log (TEST-3303); docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3303.txt (field landed with run 1, RED is the mutation) | — | D1 |
| Spec-AC-05 | WHEN lint --admit admits a fixture index-reading suite that fails if the last ledger line contains AAI-REUSE-POISON THEN it prints ADMIT-FAIL for it with appended-ledger run failed and exits 1; WHEN the index-reading suite ignores the ledger THEN it prints ADMIT-PROBE with appended docs/ai/tests/test-runs.jsonl PASS and ADMIT-PASS and exits 0; a suite without index_read gets no appended probe line | done | docs/ai/tdd/reuse-local-ledger-append/green/test_3304_tail_read_refused.log, docs/ai/tdd/reuse-local-ledger-append/green/test_3305_tail_ignored_admitted.log; docs/ai/tdd/reuse-local-ledger-append/red/test_3304_tail_read_refused-baseline.log, docs/ai/tdd/reuse-local-ledger-append/red/test_3305_tail_ignored_admitted-baseline.log; docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3304.txt, docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3305.txt | — | D3 |
| Spec-AC-06 | The live manifest's notes for aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-prompt-diet and aai-win-fallback name docs/ai/tests/test-runs.jsonl and lint exits 0; lint --admit --changed-since main on the branch tip exits 0 locally with ADMIT-PASS and an appended ADMIT-PROBE PASS line for each of the five | done | docs/ai/tdd/reuse-local-ledger-append/green/suite-reuse-run3.log (TEST-3306, TEST-3307); docs/ai/tdd/reuse-local-ledger-append/admit-live.txt (five ADMIT-PASS, five appended ADMIT-PROBE PASS); docs/ai/tdd/reuse-local-ledger-append/red/test_3306-baseline.log, docs/ai/tdd/reuse-local-ledger-append/red/test_3307-baseline.log; docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3306.txt, docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3307.txt | — | D3 D4 |
| Spec-AC-07 | docs/analysis/precise-suite-evidence-reuse.md has a heading Measurements (ledger append) with a before and an after zero-delta rerun of the eleven manifest suites per D6 (40-character shas, exit codes, wall seconds, per-suite REUSED or first RUN reason, versions); after, the five index-reading suites are REUSED; before, each of them is RUN with reason inputs changed docs/ai/tests/test-runs.jsonl | done | docs/ai/tdd/reuse-local-ledger-append/green/suite-reuse-run3.log (TEST-3308); docs/analysis/precise-suite-evidence-reuse.md section Measurements (ledger append); docs/ai/tdd/reuse-local-ledger-append/red/test_3308-baseline.log; docs/ai/tdd/spec-reuse-local-ledger-append/mutation-TEST-3308.txt | — | D6 |

## Implementation plan

- `.aai/scripts/suite-reuse.mjs`: D1 (constant, `appendPrefix`,
  `appendedOnly`, the check-side substitution, `traceOfRecord` pass-through,
  the record field) and D3 (appended-ledger run in `admitSuite`). TEST-3267
  keeps the file at most 600 lines (546 at baseline).
- `tests/skills/lib/suite-reuse.test.mjs`: node cases TEST-3301 to TEST-3303.
- `tests/skills/test-aai-suite-reuse.sh`: TEST-3300, TEST-3304 to TEST-3308,
  wrappers for the node cases; TEST-3307 asserts on the output of the live
  admission TEST-3276 already runs (one live admission per suite run).
- `tests/skills/suite-reuse.json`: the five notes (D4).
- Analysis note section (D6), measured last.
- Edge cases: ledger absent at record (no `append_prefix` for it); ledger
  absent at check (`appendedOnly` false, RUN); ledger shrunk; a concurrent
  run appended during the recorded run (size does not reproduce the arm
  hash, every later check misses until the next record); a record from
  before this change (no `append_prefix`, today's behavior).

### Seams crossed

| Seam | Producer | Consumer | Test |
|---|---|---|---|
| S1 framework ledger append | framework summary writing test-runs.jsonl | next run's check of an index-reading suite | TEST-3300 (real framework, three runs) |
| S2 record to check | recordSuite append_prefix | computeIdentity check side | TEST-3301, TEST-3302, TEST-3303 |
| S3 git index refresh | git status in the disposable checkout | collectTrace index_read | TEST-3300 (the fixture suite reads the index only through git status) |
| S4 admission | lint --admit appended-ledger run | real suite in a scratch clone | TEST-3304, TEST-3305, TEST-3307 |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3300 | Spec-AC-01 | integration | tests/skills/test-aai-suite-reuse.sh | test_3300: fixture repository with the real framework and helper, docs/ai/tests/test-runs.jsonl tracked and not ignored; declared suite ix runs git status in its checkout and cats a.txt; run 1 PASS and recorded; run 2 reports ix REUSED; run 3 reports ix REUSED; the ledger has one more line after each run (baseline: run 2 prints RUN with reason inputs changed docs/ai/tests/test-runs.jsonl) | `sed:s/const APPEND_ONLY_LEDGERS = \['docs\/ai\/tests\/test-runs.jsonl'\];/const APPEND_ONLY_LEDGERS = [];/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3301 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3301: recordSuite with a synthetic index_read trace on a scratch repo with tracked ledger and EVENTS; from a copy of that state each of: equal-length edit of an existing ledger line, truncation, chmod +x of the ledger, an EVENTS append, a ledger append plus an edit of docs/x.md gives RUN naming the expected path; a ledger append alone gives REUSE | `sed:s/=== prefix.sha256;/!== null;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3302 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3302: a record whose trace has index_read false, names the ledger as an input and carries a hand-written append_prefix gives RUN reason=inputs changed docs/ai/tests/test-runs.jsonl after a ledger append; an index_read record with append_prefix removed gives the same RUN after a ledger append | `sed:s/const tolerate = trace.index_read && /const tolerate = /` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3303 | Spec-AC-04 | unit | tests/skills/test-aai-suite-reuse.sh | node case TEST-3303: recordSuite with an index_read trace writes append_prefix for the ledger with bytes equal to its size and sha256 equal to inputs_map of that path; with index_read false the record has no append_prefix key | `sed:s/append_prefix: traced.index_read \? /append_prefix: false ? /` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3304 | Spec-AC-05 | integration | tests/skills/test-aai-suite-reuse.sh | test_3304: fixture manifest with suite tailread that runs git status and exits 1 when the last line of docs/ai/tests/test-runs.jsonl contains AAI-REUSE-POISON; lint --admit prints ADMIT-FAIL tailread with appended-ledger run failed and exits 1 | `sed:s/const tailOk = ra.status === 0;/const tailOk = true;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3305 | Spec-AC-05 | integration | tests/skills/test-aai-suite-reuse.sh | test_3305: fixture manifest with index-reading suite tailok (git status only) and non-index suite plain; lint --admit prints ADMIT-PROBE tailok appended docs/ai/tests/test-runs.jsonl PASS, ADMIT-PASS tailok and ADMIT-PASS plain, no appended probe line for plain, and exits 0 | `sed:s/const tailOk = ra.status === 0;/const tailOk = false;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3306 | Spec-AC-06 | contract | tests/skills/test-aai-suite-reuse.sh | test_3306: lint on the live repository exits 0; the live manifest notes of the five index-reading suites each contain docs/ai/tests/test-runs.jsonl | `sed:s/test-runs.jsonl/test-runz.jsonl/` on tests/skills/suite-reuse.json | green |
| TEST-3307 | Spec-AC-06 | contract | tests/skills/test-aai-suite-reuse.sh | test_3307: the output of the live lint --admit --changed-since main of TEST-3276 has, for each of the five index-reading suites that it admitted, an ADMIT-PASS line and an ADMIT-PROBE appended docs/ai/tests/test-runs.jsonl PASS line, at least one such suite is admitted on this branch, or ADMIT-OFF ci under CI, or ADMIT-NONE when no suite changed against main (checked in a scratch clone whose main is HEAD) | `sed:s/const tailOk = ra.status === 0;/const tailOk = ra.status !== 0;/` on .aai/scripts/suite-reuse.mjs | green |
| TEST-3308 | Spec-AC-07 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3308: the analysis note has a line equal to ## Measurements (ledger append) with two 40-character shas, a before and an after row per manifest suite, the five index-reading suites REUSED after and RUN with inputs changed docs/ai/tests/test-runs.jsonl before, and Node, Bash and Git versions | `sed:s/## Measurements \(ledger append\)/## Measurementz (ledger append)/` on docs/analysis/precise-suite-evidence-reuse.md | green |

RED plan, observed on the baseline `9c487740` before each fix and stored
under `docs/ai/tdd/reuse-local-ledger-append/red/`:

- TEST-3300: run 2 prints RUN for ix with reason inputs changed
  docs/ai/tests/test-runs.jsonl (the defect).
- TEST-3301: the ledger-append-alone case gives RUN (no tolerance yet); the
  RUN cases already pass on the baseline and must stay so.
- TEST-3302: passes on the baseline (no tolerance exists); its RED is the
  mutation, recorded by mutation-run.
- TEST-3303: the record has no append_prefix.
- TEST-3304, TEST-3305, TEST-3307: no appended-ledger run, so tailread is
  admitted (ADMIT-PASS) and no appended probe line exists.
- TEST-3306: the notes do not name test-runs.jsonl.
- TEST-3308: no such section.

Mutation semantics: `mutation-run.mjs` applies the pattern as a JavaScript
RegExp to the first match in the whole file, so each D1 and D3 literal a
mutation names must first occur at its decisive site; if the implementation
cannot place it so, the row's mutation is amended additively with
disclosure, never dropped.

TDD run split (about three ACs per run):

- Run A: Spec-AC-01, Spec-AC-02, Spec-AC-03 (identity rule; TEST-3300 to
  TEST-3302).
- Run B: Spec-AC-04, Spec-AC-05 (record field, admission run; TEST-3303 to
  TEST-3305).
- Run C: Spec-AC-06, Spec-AC-07 (notes, live admission, then the
  measurement; TEST-3306 to TEST-3308).

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-suite-reuse.sh` (includes the live admission of the five
  index-reading suites, several minutes), `test-aai-suite-isolation.sh`,
  `test-aai-sweep-parallel.sh`, `test-aai-repo-tripwire.sh`, plus
  `node .aai/scripts/select-suites.mjs --base-ref main` selected plus CORE.
  No full sweep in intermediate rounds; one before close only if the
  orchestrator's sweep policy asks for it. Restore
  `docs/ai/tests/test-runs.jsonl` after every run.
- `node .aai/scripts/suite-reuse.mjs lint --admit --changed-since main`
  exits 0 with five ADMIT-PASS lines and five appended ADMIT-PROBE PASS
  lines; output stored under `docs/ai/tdd/reuse-local-ledger-append/`.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exit 0 before
  close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Post-PR checks (not Spec-ACs, not claimed by local Validation)

- H1: the PR head's skill-suite run concludes success; its framework jobs
  print `Evidence reuse: off (ci)` and the aai-suite-reuse job prints
  `ADMIT-OFF ci`.
- H2: the PR head's ps1-quality run concludes success.

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

Run by the orchestrator after flush, before the PR; then run
`set-code-review` again with this file list as scope.

1. Product doc `docs/product/precise-suite-evidence-reuse.md`: the D2
   sentence and caveat replace the SPEC-0268 sentence; Limits say that the
   five index-reading suites are reused on an unchanged rerun and on a
   rerun whose only change is the framework's run-ledger append, and miss on
   any other tracked change.
2. CHANGELOG.md: one `## [unreleased] — <title>` heading entry.
3. Close `fu-reuse-local-ledger-append` (below); `fu-reuse-docs-closure-suites`
   stays open with a note that its first named cause is removed.
4. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/reuse-local-ledger-append/red/, a mutation record per Test Plan
row under docs/ai/tdd/spec-reuse-local-ledger-append/, and green suite
outputs. A REUSED suite line is not evidence for any row of this spec: its
suites run with `AAI_SUITE_REUSE=0`.

## Files Implementation touches

- .aai/scripts/suite-reuse.mjs
- tests/skills/lib/suite-reuse.test.mjs
- tests/skills/test-aai-suite-reuse.sh
- tests/skills/suite-reuse.json
- docs/analysis/precise-suite-evidence-reuse.md
- docs/issues/CHANGE-0243-reuse-local-ledger-append.md
- docs/specs/SPEC-0270-spec-reuse-local-ledger-append.md
- docs/product/precise-suite-evidence-reuse.md (close-out)
- CHANGELOG.md (close-out)
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

No new `.aai/**` file (no PROFILES.yaml entry owed) and no prompt-corpus
bytes (no diet-ledger entry owed). Not touched: tests/skills/test-framework.sh,
.aai/scripts/lib/checkout-trace.mjs, .aai/scripts/aai-run-tests.sh,
tests/skills/suite-map.yaml, every ledger writer and every consumer named in
M2, every protected_paths_l3 file.

## Risks and rollback

- R1 False hit through an appended ledger line: an index-reading suite that
  genuinely reads lines appended to `docs/ai/tests/test-runs.jsonl` after
  its record would be reported REUSED. D3 checks every index-reading
  manifest suite against an appended poison line at admission; a later
  suite change that starts reading the tail is caught only at its next
  admission (the suite file change itself triggers it under
  `--changed-since`). M4 shows the five current suites independent of the
  whole ledger's content.
- R2 The admission of an index-reading suite runs it once more (about the
  suite's own duration; aai-hygiene-pack about 100 s), on rides that change
  its manifest entry or suite file only.
- R3 A concurrent framework run that appends during a recorded run leaves a
  record whose prefix never matches; that suite misses until its next pass
  is recorded (fail closed).
- Rollback: `AAI_SUITE_REUSE=0` disables reuse; reverting the PR restores
  the full-hash comparison; deleting `tests/skills/results/reuse/` is always
  safe.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list --status open` (288 open) has these
reuse items: `fu-reuse-local-ledger-append` is this scope and is closed by
it at delivery. `fu-reuse-docs-closure-suites` names the framework-appended
ledger as one of three causes; this scope removes that cause for
index-reading suites but not EVENTS and STATE churn or the shared-library
prose literals, so it stays open. Out of scope and left open:
`fu-reuse-split-corpus-cases` (the next ride), `fu-reuse-record-max-age`,
`fu-reuse-distro-exported-functions`, `fu-reuse-overlaps-mutation`,
`fu-reuse-arm-dir-nonexist-case`.

## Registry items closed by this scope

fu-reuse-local-ledger-append
