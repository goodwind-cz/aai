---
id: spec-slowest-suite-hot-spots
type: spec
number: null
status: implementing
frozen_sha256: f37134f50558bdd92d8d6065fb6b8920bc5ab4c1cac45f1887b34e2c53e79eaa
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/DEBT-DRAFT-slowest-suite-hot-spots.md
  pr: []
  commits: []
---

# Spec — The four hot spots of the slowest suites get cheap without proving less

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-DRAFT-slowest-suite-hot-spots.md (techdebt intake, id `slowest-suite-hot-spots`)
- Decision records: SPEC-0215 Spec-AC-12 (the CI leg bound moved here by owner amendment, 2026-10-09)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only for `.aai/scripts/*.mjs`; bash suites under `tests/skills/`)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, as re-measured by Planning (2026-10-09)

Planning did not take the intake's numbers on trust. The tree is `e80ecabc`
(this branch's base, which already contains SPEC-0215: no suite re-runs a
whole suite). It was measured on a disposable clone in scratch, on this host
(16 CPU), with `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000`, every output line
timestamped, and a test's duration taken as the gap between its PASS line
and the previous one.

### Baseline per hot spot

| Suite | Local wall | CI weight | Where the time goes |
|---|---|---|---|
| aai-hygiene-pack | 294 s (88 tests) | 311 | test_094 155.5 s, TEST-562 92.7 s, the other 86 tests about 46 s |
| aai-sync-seed | 244 s alone (257 s beside two other suites) | 168 | 21 `aai-sync.ps1` calls 116.9 s (3.8 to 8.1 s each), about 48 `aai-sync.sh` calls (2.2 s fresh, 3.1 s re-sync) |
| aai-run-tests | 133 s | 131 | TEST-018 37.7 s; about 57 s of age waits; about 22 one-second settle waits; about 9 s of deliberate timeouts; 19 wrapper calls |

The SPEC-0215 nested-suite lint tests cost almost nothing: test_132 0.0 s,
test_133 1.3 s, test_134 0.0 s.

### What each hot spot really spends its time on

1. **hygiene-pack test_094 is wrapper overhead, not suite work.** It probes
   79 suites (it was 67 at intake). Probing all 79 DIRECTLY takes 2.6 s in
   total (0.03 s each). Probing them through `.aai/scripts/aai-run-tests.sh`
   takes 137.6 s (1.74 s each). The wrapper's fixed cost, measured on
   `aai-run-tests.sh true`, is 1.11 s, and 1.0 s of it is the unconditional
   `sleep 1` grace in `aai_reap_group`, paid even when the process group is
   already empty. The rest of a suite probe (about 0.6 s) is the disposable
   isolated checkout the wrapper builds for every suite run. With an
   empty-group fast path in the wrapper, `true` takes 0.09 s; the 79 probes
   take 55 s with isolation and 11 s without.
2. **TEST-562 scans the live tree twice, one `node` and one `git check-attr`
   per tracked file.** 1,608 tracked files, two identical live-tree scans
   (one checks the exit code, the next the empty output), about 46 s each.
3. **sync-seed is real engine calls.** About 97% of its time is inside
   `aai-sync.sh` and `aai-sync.ps1`. A fresh sync from the real source takes
   2.2 s (bash) and 1.6 to 6 s (ps1); copying its result takes 0.15 s. Many
   tests start with exactly that fresh sync before the step they assert.
4. **run-tests sleeps.** TEST-018 runs six cases one after another, each with
   a 3 s age wait and two 1 s settle waits (30 s). Every wrapper call pays the
   1 s grace (about 15 s in total; the suite with the fast-path wrapper ran in
   118 s and stayed green). The age waits are derived from the reaper's GRACE
   and were widened after CI flakes; their comments say DO NOT NARROW.

### Corrections to the intake

1. **There is no shipped no-NUL check.** The guard is
   `tests/skills/lib/no-nul-guard.sh`; its only consumer is
   `tests/skills/test-aai-hygiene-pack.sh` (plus a row in
   `tests/skills/lib/cd-subshell-leak-baseline.tsv`). `aai-sync` ships no
   `tests/` path, and `.aai/scripts/pre-commit-checks.sh` and `.ps1` contain
   no NUL check. So this scope does not touch a protected L3 surface for that
   item, and downstream pre-commit is not slowed by it today.
2. **test_094 keeps probing every suite.** The intake proposed a static proof
   plus a sample. The frozen row it backs (SPEC-0181 TEST-473) says the
   mutation must redden "proving the guard enumerates rather than sampling".
   Sampling would change what the row proves (a contract amendment owed to
   the owner). The measurement shows sampling is also unnecessary: the cost
   is the wrapper, not the probes. D1 keeps full enumeration.
3. **"Roughly halved" is not reachable for sync-seed and run-tests without
   proving less.** Their remaining time is the behavior under test: real
   re-syncs (sync-seed) and GRACE-derived age waits plus deliberate timeouts
   (run-tests). Planning projects about 0.61 and 0.66 of baseline and sets
   the bound at 0.70 (HITL Q2: owner accepted 0.70, 2026-10-09, "Hranice 0,70").
4. **The delta-stage3 side finding is already closed.** The fixed
   `/tmp/aai-delta-stage3-*.log` paths lived in the nested runs that
   `e80ecabc` removed. A search of `tests`, `.aai` and `.github` finds no
   fixed `/tmp/aai-delta` path. Nothing to fold in.

## Implementation strategy
- Strategy: direct
- Rationale: The owner chose `direct` at intake. It is recorded in STATE with
  `source: intake` and in the intake `## Notes` line "Implementation mode
  (user choice): direct". Planning agrees: this is a performance rework of
  existing tests whose behavior is pinned by the tests that exist, plus
  targeted regressions. Because equivalence is the risk, every Test Plan row
  still carries a sed-token Mutation that mutation-run can observe RED.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope touches the shipped test wrapper, four suites
  and the shard weights, and it needs a pushed branch for two full-mode CI
  runs (weights re-seed, then the leg measurement). The main checkout is
  shared with other live sessions. The worktree already exists.
- User decision: worktree (already in use)
- Base ref: main
- Worktree branch/path: `debt/slowest-suite-hot-spots` at `/Users/ales/Projects/aai-debt-slowest-suite-hot-spots`
- Inline review scope: `.aai/scripts/aai-run-tests.sh`, `tests/skills/lib/no-nul-guard.sh`, `tests/skills/lib/selector-probe.sh`, `tests/skills/lib/cd-subshell-leak-baseline.tsv`, `tests/skills/test-aai-hygiene-pack.sh`, `tests/skills/test-aai-sync-seed.sh`, `tests/skills/test-aai-run-tests.sh`, `tests/skills/test-aai-suite-select.sh`, `tests/skills/suite-weights.tsv`, `docs/ai/decisions.jsonl` (appended spec_amendment records only)

## Design decisions

### D1. test_094: one isolated checkout, every suite probed

New file `tests/skills/lib/selector-probe.sh`, run as
`aai-run-tests.sh bash tests/skills/lib/selector-probe.sh <suite>...` with the
enumerated suites as arguments. Because its arguments are suite files under
`tests/`, the wrapper classifies the run as `suite` and builds ONE isolated,
seeded disposable checkout (uncommitted edits replayed, the same seeding a
mutation run relies on today). Inside it, the probe loop
(`for rel in "$@"; do`) runs `bash "$rel" no_such_test_xyz` directly for each
suite and prints exactly one line `PROBE-RC <rel> <rc>` per suite. It never
stops early.

test_094 keeps its two self-checks (the planted fail-open fixture and the
negative control), its enumeration (`hp_scan_selector_suites`, unchanged) and
its three real-selector arms. It adds:
- the probe run's output carries `AAI-ISOLATION: isolated` (the seam to the
  wrapper's classifier);
- the number of `PROBE-RC` lines equals the enumerated count, and each
  enumerated suite has exactly one (positive control: every suite was really
  probed);
- every suite whose `PROBE-RC` is 0 is named in the failure, as today.

The outer wrapper call keeps `AAI_TEST_TIMEOUT=600` as the bound for the
whole loop. Today each probe had a 60 s bound, and a fail-open suite that ran
its whole body for more than 60 s was killed with 124 and counted as a
refusal. Under D1 it runs to completion and is caught when it exits 0. This
is stronger. Its cost appears only in the failure case.

### D2. No-NUL scan: one process, byte-identical output

`tests/skills/lib/no-nul-guard.sh` keeps `nonul_file_has_nul` and
`nonul_is_declared_binary` unchanged (the test calls them directly).
The current per-file loop is renamed `nonul_scan_perfile` and kept as the
reference implementation. `nonul_scan` delegates to a new
`nonul_scan_batch "$_nn_root"`, which runs:
- `git ls-files -z` once;
- `git check-attr -z --stdin binary` once, fed that list; a path is exempt
  only when the attribute value is `set` (the node code reads it as
  `info === 'set'`), exactly as `nonul_is_declared_binary` does;
- one `node` process that, in `git ls-files` order, skips a path that is not
  a regular file or a link to one (the `[ -f ]` rule), skips an exempt path,
  skips an unreadable file (as the reference does when `node` exits 2), and
  prints each path whose bytes contain 0 (`buf.includes(0)`), one per line.

Output and exit code of `--check` stay byte-identical. TEST-562 scans the
live tree once and asserts both the exit code and the empty output on that
one result. The guard adds no new `cd` subshell. If its count drops, the
baseline row is re-recorded with `check-cd-subshell-leak.mjs --record`, never
hand-edited.

### D3. sync-seed: a golden result per key, copied per test

A helper in the suite, `_sync_cached <engine> <source-root> <dst> [git]`:
- key = engine (`sh` or `ps1`) + source kind (`real` = `$PROJECT_ROOT`,
  `fixture` = a source built by `_778_build_fixture_source`) + target kind
  (empty, or `git init -q -b main`);
- the first request per key runs the real engine into
  `$TMP_ROOT/golden/<key>` and then runs `chmod -R a-w "$golden"`, so any
  later write into the golden fails loudly;
- every request then copies with `cp -Rp "$golden"` into `<dst>` and makes
  the copy writable (`chmod -R u+w`), so content and executable bits match.

The canonical fixture source is built once per run; each fixture test copies
it to its own path before editing it.

The helper may replace only a FIRST sync into a fresh target whose output the
test discards. It never replaces a sync that a test asserts on directly
(stdout captured, a pre-seeded target, a re-sync, an engine-parity
comparison, or the old-versus-new byte comparison of TEST-778). Every re-sync
stays a real engine call.

Why a fixture-source golden is equivalent (measured by Planning): a sync's
only path-dependent output is `.aai/system/AAI_PIN.md` (Source path,
Template commit, Canonical repo, Synced at) plus the advisory's timestamped
file name and its path in stdout. On a re-sync both engines read only the
`- Profile:` line of an existing pin (`aai-sync.sh` line 76,
`aai-sync.ps1` line 136). Planning ran v1 from one fixture source path and
from a second identical copy, then a v2 from the first. Stdout and trees were
identical apart from those fields. TEST-007 pins both facts, so a future
engine that reads more of the pin breaks the cache's premise loudly.

### D4. The wrapper: skip the grace when the group is already empty

In `.aai/scripts/aai-run-tests.sh` `aai_reap_group`, POSIX branch only:
after `kill -TERM -<pgid>`, the grace becomes
`kill -0 -"${PGID:-$CMD_PID}" 2>/dev/null && sleep 1`, followed by the
unchanged `kill -KILL`. If any member survives the TERM, the wait and the
KILL are exactly as today. If no member is left, the pointless second is
skipped. The MSYS branch and `aai-run-tests.ps1` are unchanged. This is a
shipped change: every downstream wrapped test run gets about 1 s faster
(HITL Q1: owner chose to include it, 2026-10-09, "Zahrnout").

### D5. run-tests: batch the ages, poll the deaths, keep every margin

- **Age waits keep their length.** Every wait that ages a process across a
  GRACE-derived or MIN_AGE boundary carries a tag
  `# AGE-WAIT min=<n>` on its line, where `<n>` is the documented minimum
  (6, 6, 8, 6, 4 and 3; the TEST-016 delay of 7 is tagged too). A new static
  test pins the tag count and that each `sleep` is at least its `min`.
- **TEST-018 ages its six cases at once.** It spawns the six reap-old
  fixtures (each with its own workspace and its own process) first, waits
  one `sleep 3   # AGE-WAIT min=3`, then runs the six reap-old reaps and the
  six spare-fresh attributions. No case shares a workspace or a process with
  another.
- **Settle waits before an expected death become polls.**
  `wait_gone <pid>... <deadline-seconds>` polls `kill -0` every 0.1 s and
  returns 1 when the deadline passes. The deadline is at least 5 s, so it is
  more tolerant of CI load than the 1 s it replaces. A failed `wait_gone`
  is a `log_fail` naming the survivor.
- **Settle waits before an expected survival stay fixed.** A test that only
  asserts survival keeps its `sleep 1`. Where a test asserts both, the
  survival check runs after `wait_gone` of the reaped pid, so the reaper's
  signals have already landed.
- No timeout value (`AAI_TEST_TIMEOUT=1` or `2`) changes.

### D6. Weights, then the leg bound

`tests/skills/suite-weights.tsv` is re-seeded with the SPEC-0215 D9 method:
a full-mode CI run of this branch after Batches 1 to 3 are green
(`gh workflow run skill-suite.yml --ref debt/slowest-suite-hot-spots`), parsed
from the four legs' `[ n/NN] <suite> PASS (<s>s)` lines, with the run id,
job ids and head SHA in the header. A SECOND full-mode run on the re-seeded
weights measures the legs. Leg wall means the duration of each leg's
shard-run step, taken from `gh run view <run> --json jobs` (step start to
completion). The header gains one line,
`# Leg walls (run <id>): <w1> <w2> <w3> <w4>`, and a suite-select test
requires that the largest is at most 1.25 times their mean.

Projection: weights sum 2,485 now, about 2,140 after (hygiene-pack about 60,
sync-seed about 110, run-tests about 90). The heaviest remaining suites are
aai-docs-audit (139) and aai-close-work-item (133). Neither alone floors a
leg the way hygiene-pack (308 s alone in a 309 s leg) did. Planning expects
a ratio of about 1.1 to 1.2. If the second run measures above 1.25,
Spec-AC-11 goes `blocked` with the four walls and the heaviest suite of the
slowest leg, and the owner decides the bound (HITL). It is never relaxed
silently.

### D7. Frozen-spec impact

No frozen row changes meaning:
- SPEC-0181 TEST-473: every enumerated suite is still invoked with the
  literal and must exit non-zero. The mechanism is still enumeration, and the
  recorded mutation (feedback-triage's guard set to `true`) still reddens it.
  No record.
- SPEC-0182 TEST-562: the same assertions over the same tree. The recorded
  mutation `buf.includes(0)` to `buf.includes(1)` still reddens it, because
  the batch program contains the same token. No record.
- sync-seed rows whose first sync comes from the golden, and run-tests rows
  whose waits are batched or polled: the predicate is unchanged; only how the
  precondition is produced or how long the test waits for a death changes.
  This is the `measurement` class of `.aai/system/AUTONOMOUS_LOOP.md` section
  6a. To be honest about it, Implementation records one disclosure per
  affected spec:
  `node .aai/scripts/spec-amend.mjs add --spec <spec path> --ref slowest-suite-hot-spots --class measurement --signoff none --what "<rows>: first sync from a cached golden copy (or: settle sleep replaced by a bounded poll; ages batched)" --why "suite time; predicate unchanged"`.
  The final spec list is pinned in TEST-018.

The local mutation records for TEST-473 and TEST-562 live in the main
checkout's gitignored evidence tree. Implementation replays them
(`node .aai/scripts/mutation-run.mjs --replay --spec <spec path>`) from the
main checkout after the change and re-points nothing unless the replay says
otherwise.

## Implementation plan

Four batches of about three AC each, largest saving first. Each batch runs
its touched suites, `aai-hygiene-pack` and `aai-suite-select`, and records the
Mutation of each of its rows with `mutation-run.mjs`.

- **Batch 1 — hygiene-pack (Spec-AC-01..03).** `selector-probe.sh`, test_094
  rewrite, `no-nul-guard.sh` batch scan, TEST-562 single live scan, new
  test_135 and test_136. Projected suite time about 55 s.
- **Batch 2 — sync-seed (Spec-AC-04..06).** `_sync_cached`, the canonical
  fixture source, conversion of the eligible first syncs, new test_794 to
  test_796. Projected about 150 s.
- **Batch 3 — run-tests and the wrapper (Spec-AC-07..09).** D4, `wait_gone`,
  AGE-WAIT tags, TEST-018 batching, new test_028 to test_030. Projected
  about 88 s.
- **Batch 4 — weights, legs, disclosure (Spec-AC-10..12).** CI run 1 and the
  re-seed, CI run 2 and the leg line, new suite-select test_1757 to
  test_1761, hygiene-pack test_137, the spec-amend records, one full local
  sweep.

New test functions are registered in each suite's `main`
(check-test-registration stays clean). Rollback is per batch.

## Seams this change crosses

- SEAM-1. The probe run and the wrapper's suite-run classifier and seeding:
  the probe must be classified `suite` and see uncommitted edits. Crossed by
  TEST-001 (isolation line) and by the replay of the TEST-473 record, which
  mutates an uncommitted working-tree file.
- SEAM-2. The probe loop and the SPEC-0215 nested-suite lint: a selector-form
  call through a lib script must stay unreported. Crossed by hygiene-pack
  test_133 staying green.
- SEAM-3. `nonul_scan` and the cd-subshell-leak ratchet baseline row for
  `no-nul-guard.sh`. Crossed by the ratchet test in hygiene-pack.
- SEAM-4. The sync cache and both engines: the golden must equal what the
  engine writes, and the engine must read only the Profile line of an
  existing pin. Crossed by TEST-007.
- SEAM-5. The wrapper's reap and everyone who calls it (framework, CI, the
  loop, 23 suites). Crossed by the whole run-tests suite, TEST-010, TEST-011
  and the full local sweep.
- SEAM-6. The re-seeded weights and the shard planner. Crossed by TEST-1423
  and SPEC-0215's test_1756 (learned-append and delta-stage3 bounds) staying
  green, and by TEST-016.
- SEAM-7. `merge-policy.mjs` GUARD_PATHS lists `.aai/scripts/aai-run-tests.sh`,
  so this PR takes the heavy lane. Expected; no change.

## Acceptance Criteria Mapping
- Maps to: intake Target State bullet 2 (test_094) and Verification bullet 1
  (hygiene-pack under about 60 s). Spec-AC-01 and Spec-AC-03, verified by
  TEST-001, TEST-002 and TEST-005.
- Maps to: intake Target State bullet 1 (single-process no-NUL check) and
  Verification bullet 3 (identical output). Spec-AC-02, TEST-003 and TEST-004.
- Maps to: intake Target State bullet 3 (sync-seed cache) and Constraints
  (no state leakage). Spec-AC-04 to Spec-AC-06, TEST-006 to TEST-009.
- Maps to: intake Target State bullet 4 (run-tests sleeps) and Constraints
  (no new flake). Spec-AC-07 to Spec-AC-09, TEST-010 to TEST-015.
- Maps to: intake Verification bullet 2 (the 1.25 leg bound) and Plan step 5
  (re-seed). Spec-AC-10 and Spec-AC-11, TEST-016 and TEST-017.
- Maps to: intake Verification bullet 4 (every behavior still proved) and the
  frozen-spec constraint. Spec-AC-12, TEST-018, plus every row's Mutation.

## Constitution deviations

None.

Article 1 (evidence before claims): every number above was measured, and
every target is checked by a command or a pinned weight. Article 2
(simplicity): one lib script, one helper per suite, one changed line in the
wrapper; no new CLI. Article 4 (degrade and report): a probe loop that hangs
is bounded by the wrapper timeout and names the last suite it started.
Article 5 (additive first): the per-file reference scan stays, and the
wrapper only skips a wait that had nothing to wait for.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN test_094 runs, it SHALL probe every suite that hp_scan_selector_suites enumerates with the literal no_such_test_xyz inside one wrapper run classified as an isolated suite run, SHALL see exactly one PROBE-RC line per enumerated suite, SHALL fail naming every suite whose probe exits 0, and SHALL keep its two self-checks and its three real-selector arms. | planned | — | — | D1; SEAM-1, SEAM-2 |
| Spec-AC-02 | WHEN nonul_scan runs over any tree, it SHALL start exactly one node process and one git check-attr process, and its stdout and exit code SHALL be byte-identical to nonul_scan_perfile over a fixture holding a planted NUL, a clean file, a declared-binary asset, an undeclared NUL file, a path with spaces, a NUL past byte 8000, a tracked file missing from the worktree, a symlink to a NUL file and an unreadable file; and TEST-562 SHALL scan the live tree once. | planned | — | — | D2; SEAM-3 |
| Spec-AC-03 | On the measuring host aai-hygiene-pack SHALL finish in at most 60 s with test_094 at most 15 s and TEST-562 at most 5 s, and the re-seeded CI weight of aai-hygiene-pack SHALL be at most 65. | planned | — | — | baseline 294 s local, 311 CI |
| Spec-AC-04 | WHEN a sync-seed test requests a first sync through _sync_cached, the first request per key SHALL run the real engine into a golden that is then read-only, and every request SHALL receive a writable copy whose file contents and executable bits equal the golden's; a write into the golden SHALL fail. | planned | — | — | D3 |
| Spec-AC-05 | For each golden key, one real sync from a differently located identical source into a fresh target SHALL equal the golden apart from the AAI_PIN.md Source path, Template commit, Canonical repo and Synced at lines and the advisory file name; and aai-sync.sh and aai-sync.ps1 SHALL read no field of an existing AAI_PIN.md other than Profile. | planned | — | — | D3; SEAM-4 |
| Spec-AC-06 | At least 15 first syncs in test-aai-sync-seed.sh SHALL go through _sync_cached, every re-sync and every asserted first sync SHALL stay a real engine call, the suite SHALL finish in at most 170 s on the measuring host (0.70 of 244 s), and its re-seeded CI weight SHALL be at most 118. | planned | — | — | not halved, see HITL Q2 |
| Spec-AC-07 | WHEN no member of the wrapped command's process group is alive after the TERM, aai_reap_group in aai-run-tests.sh SHALL return without the 1 s grace; WHEN a member survives the TERM it SHALL still wait the grace before the KILL; the MSYS branch SHALL be unchanged. | planned | — | — | D4; SEAM-5; shipped |
| Spec-AC-08 | test-aai-run-tests.sh SHALL tag every age wait with AGE-WAIT min and keep each at or above its min, SHALL age TEST-018's six reap-old fixtures in one shared wait while keeping one workspace and one process per case, and SHALL replace each settle wait before an expected death with wait_gone whose deadline is at least 5 s. | planned | — | — | D5 |
| Spec-AC-09 | aai-run-tests SHALL finish in at most 93 s on the measuring host (0.70 of 133 s), three consecutive local runs under a bounded four-process CPU load SHALL all pass, and its re-seeded CI weight SHALL be at most 92. | planned | — | — | flake guard |
| Spec-AC-10 | tests/skills/suite-weights.tsv SHALL be re-seeded from a named full-mode CI run of this branch whose run id, job ids and head SHA its header names, and TEST-1423 and SPEC-0215 test_1756 SHALL stay green. | planned | — | — | D6; SEAM-6 |
| Spec-AC-11 | On a second full-mode CI run on the re-seeded weights the slowest leg's shard-run step SHALL take at most 1.25 times the mean of the four legs, recorded in the weights header as a Leg walls line. | planned | — | — | D6; bound moved from SPEC-0215 |
| Spec-AC-12 | Every frozen spec whose Test Plan row is backed by a sync-seed function that takes its first sync from the cache, or by a run-tests function whose waits were batched or polled, SHALL carry a spec_amendment record of class measurement with ref slowest-suite-hot-spots, and SPEC-0181 and SPEC-0182 SHALL carry none for this ref. | planned | — | — | D7 |

Status values: planned | implementing | done | deferred | blocked | rejected

## Test Plan

Fixtures live in `mktemp -d` scratch directories. Every row runs as
`bash tests/skills/<file> <selector>` under `env -u AAI_ROLE`. The Mutation
cells target shapes this spec MANDATES (D1 to D6). If Implementation renames
a mandated shape, it restamps the cell mechanically and says so in its
hand-off. Under the `direct` strategy the mutation observation is a
targeted regression check; storing it is optional.

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Mutation | Status |
|----------|------------|-------------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-hygiene-pack.sh | test_094_mutation_selector_fails_closed_corpus_wide: one wrapper run of selector-probe.sh over the live enumeration prints AAI-ISOLATION isolated and exactly one PROBE-RC line per enumerated suite; none exits 0; the three real-selector arms still pass (target of the mutation: tests/skills/test-aai-feedback-triage.sh) | sed:s/declare -F "\$1" >\/dev\/null/true/ | pending |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh | test_135_selector_probe_counts: a fixture of three suites (one fail-open) through selector-probe.sh yields exactly three PROBE-RC lines and rc 0 only for the fail-open one | sed:s/for rel in "\$@"; do/for rel in "\$1"; do/ | pending |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh | test_562_no_nul_in_tracked_text: planted and undeclared NUL files named, declared asset exempt, live tree scanned once with exit 0 and empty output | sed:s/buf\.includes\(0\)/buf.includes(1)/g | pending |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh | test_136_nonul_batch_equivalence: over the nine-case fixture nonul_scan and nonul_scan_perfile give byte-identical stdout and equal exit codes; a PATH shim counts exactly one node and one git check-attr start for nonul_scan | sed:s/nonul_scan_batch "\$_nn_root"/nonul_scan_perfile "\$_nn_root"/ | pending |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-suite-select.sh | test_1757_hygiene_pack_weight: the committed weight of aai-hygiene-pack is at most 65 | sed:s/(aai-hygiene-pack\s+)[0-9]+/$1311/ | pending |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-sync-seed.sh | test_794_sync_cache_golden_isolation: two copies of one key equal the golden in contents and executable bits; a copy is writable; a write into the golden fails; two keys give two goldens | sed:s/chmod -R a-w "\$golden"/true/ | pending |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-sync-seed.sh | test_795_sync_cache_equivalence: per key a real sync from a second identical source equals the golden apart from the four pin lines and the advisory name (ps1 keys when pwsh is present); a static read of both engines finds Profile as the only pin field read (target of the mutation: .aai/scripts/aai-sync.sh) | sed:s/s\/\^- Profile: \/\/p/s\/^- Source path: \/\/p/ | pending |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-sync-seed.sh | test_796_sync_cache_adoption: the suite's own source has at least 15 _sync_cached call sites and no _sync_cached call on a line that captures output | sed:s/_sync_cached sh "\$PROJECT_ROOT"/_sync_real sh "\$PROJECT_ROOT"/g | pending |
| TEST-009 | Spec-AC-06 | unit        | tests/skills/test-aai-suite-select.sh | test_1758_sync_seed_weight: the committed weight of aai-sync-seed is at most 118 | sed:s/(aai-sync-seed\s+)[0-9]+/$1168/ | pending |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-run-tests.sh | test_028_reap_grace_skipped_on_empty_group: the fastest of three runs of aai-run-tests.sh true takes under 0.8 s (target of the mutation: .aai/scripts/aai-run-tests.sh) | sed:s/kill -0 -"\$\{PGID:-\$CMD_PID\}" 2>\/dev\/null && sleep 1/sleep 1/ | pending |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-run-tests.sh | test_029_grace_kept_for_term_trapping_member: a wrapped command leaves a member that traps TERM and writes a marker after 0.3 s; the marker exists after the wrapper returns and the member is gone (target of the mutation: .aai/scripts/aai-run-tests.sh) | sed:s/kill -0 -"\$\{PGID:-\$CMD_PID\}" 2>\/dev\/null && sleep 1/:/ | pending |
| TEST-012 | Spec-AC-08 | unit        | tests/skills/test-aai-run-tests.sh | test_030_age_waits_not_narrowed: the suite's own source carries the pinned number of AGE-WAIT tags and each tagged sleep is at least its min | sed:s/sleep 8   # AGE-WAIT min=8/sleep 4   # AGE-WAIT min=8/ | pending |
| TEST-013 | Spec-AC-08 | integration | tests/skills/test-aai-run-tests.sh | test_018: six cases, one shared age wait, one workspace and one process per case; every reap-old fixture reaped and every spare-fresh attribution clean | sed:s/sleep 3   # AGE-WAIT min=3/sleep 0   # AGE-WAIT min=3/ | pending |
| TEST-014 | Spec-AC-08 | integration | tests/skills/test-aai-run-tests.sh | test_005: the reaped match is awaited with wait_gone (deadline at least 5 s), the other-workspace sibling survives, and a wait_gone that times out fails naming the pid | sed:s/wait_gone "\$match_pid" 5/wait_gone "\$other_pid" 5/ | pending |
| TEST-015 | Spec-AC-09 | unit        | tests/skills/test-aai-suite-select.sh | test_1759_run_tests_weight: the committed weight of aai-run-tests is at most 92 | sed:s/(aai-run-tests\s+)[0-9]+/$1131/ | pending |
| TEST-016 | Spec-AC-10 | unit        | tests/skills/test-aai-suite-select.sh | test_1760_weights_provenance: the header names a run id other than 37930287459, four job ids and a head SHA; TEST-1423 stays green | sed:s/(# run )[0-9]+/$137930287459/ | pending |
| TEST-017 | Spec-AC-11 | unit        | tests/skills/test-aai-suite-select.sh | test_1761_leg_walls_bound: the header's Leg walls line has four positive integers and the largest is at most 1.25 times their mean | sed:s/(# Leg walls \(run [0-9]+\): )[0-9]+/$1999/ | pending |
| TEST-018 | Spec-AC-12 | integration | tests/skills/test-aai-hygiene-pack.sh | test_137_hot_spot_disclosures: spec-amend list --status measurement --json has at least one item with ref slowest-suite-hot-spots for every spec in the final pinned list and none for SPEC-0181 or SPEC-0182 (target of the mutation: docs/ai/decisions.jsonl) | sed:s/"ref_id":"slowest-suite-hot-spots"/"ref_id":"x"/g | pending |

Test status values: pending → red → green

Counts: 18 rows. Unit 10 (TEST-002, 004, 005, 006, 008, 009, 012, 015, 016,
017), integration 8. Seams crossed: SEAM-1 by TEST-001; SEAM-2 by
hygiene-pack test_133 (unchanged); SEAM-3 by the cd-subshell ratchet test
(unchanged); SEAM-4 by TEST-007; SEAM-5 by TEST-010, TEST-011 and the whole
run-tests suite; SEAM-6 by TEST-016 and TEST-1423.

## Verification

Commands, all run from the worktree root, suites under `env -u AAI_ROLE`:
- Per batch: `AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-<suite>.sh`
  for every touched suite, plus `aai-hygiene-pack` and `aai-suite-select`.
- Per row: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <file> --selector <fn> --target <path> --sed '<expr>'`.
- Equivalence on the live tree, once, as Validation evidence (too slow for
  the suite): `bash -c '. tests/skills/lib/no-nul-guard.sh; nonul_scan_perfile "$PWD"'`
  and `bash tests/skills/lib/no-nul-guard.sh --check "$PWD"` give the same
  stdout and exit code.
- Timing on the measuring host, each suite alone, wall from `date +%s`:
  hygiene-pack at most 60 s (test_094 at most 15 s and TEST-562 at most 5 s
  from the PASS-line gaps), sync-seed at most 170 s, run-tests at most 93 s.
- Flake guard: run-tests three consecutive times while four CPU-bound loops
  run, each loop wrapped as `AAI_TEST_TIMEOUT=400 bash .aai/scripts/aai-run-tests.sh sh -c 'while :; do :; done'`
  so it ends on its own (never `pkill`); all three runs pass.
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md`
  and the same for `SPEC-0182-spec-close-ceremony-sweep.md`, from the main
  checkout where the records live (D7).
- CI run 1 (re-seed) and CI run 2 (legs):
  `gh workflow run skill-suite.yml --ref debt/slowest-suite-hot-spots`, then
  `gh run view <run> --json jobs`. Wait about 40 s after a push before
  watching.
- One full local sweep before close:
  `AAI_TEST_TIMEOUT=3000 env -u AAI_ROLE bash tests/skills/test-framework.sh`.
- `node .aai/scripts/spec-amend.mjs list --status measurement --json`;
  `node .aai/scripts/spec-lint.mjs --path <this spec>`;
  `node .aai/scripts/docs-audit.mjs --strict`.

PASS criteria:
- All TEST-xxx green, each Mutation observed RED once, all Spec-AC terminal.
- The three timing bounds and the flake guard hold on the measuring host.
- CI run 2 green with the leg ratio at most 1.25, recorded in the header.
- The full local sweep green apart from failures named as pre-existing
  (aai-win-fallback python-path fixture) with their reason.
- `docs-audit --strict` CLEAN; `spec-amend list --strict` exit 0.

## Evidence contract
For each implementation, validation and code review artifact, record:
- ref_id: `slowest-suite-hot-spots`
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available (for CI: run id, job ids, headSha)

### Evidence by strategy

The recorded strategy is `direct`, so the demanded evidence is the `direct`
row: targeted regression tests green (exit codes), the scoped diff, the
timing measurements, the two CI runs and the observed mutations. No stored
RED artifact is demanded.

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope

Source: `node .aai/scripts/follow-ups.mjs list`, read on 2026-10-09 and
scanned for nul, selector, sync-seed, aai-sync, run-tests, reaper, grace,
wrapper, sleep, weight, shard, leg and hygiene subjects.

This scope closes none of the registry items.

NOT CLOSED, with reason:
- `fu-msys-reap-fallback-foreign-pid` (P3). Same function
  (`aai_reap_group`), different branch: D4 changes only the POSIX branch.
- `fu-watchdog-3000-exceeds-ci-timeout` (P3). Same wrapper, different
  subject (the default timeout); not touched.
- `fu-mutation-selector-vs-bare-dispatch` (P2). test_094 still probes with
  the full literal; `mutation-run.mjs` is unchanged.
- `fu-shard-check-twin-basename`, `fu-shard-check-regex-arm-unpinned` (P3).
  Same planner, different subject; the re-seed changes weights only.

## Residual risks

- RR-1. A fail-open suite whose body FAILS still counts as a refusal (today
  and under D1). Only an exit 0 is caught. Unchanged.
- RR-2. The probe loop shares one disposable checkout. A suite that writes
  during its pre-dispatch setup could affect a later probe. The probes run
  only up to dispatch; the 79 measured probes left the checkout clean.
- RR-3. The cache assumes an engine's first sync into an empty target is a
  function of the source content and the target kind. TEST-007 checks it per
  key on every run, but only for the keys in use.
- RR-4. D4 ships to every downstream project. A command whose group is empty
  at TERM time and whose descendant has left the group (setsid) was never
  reaped by the group kill anyway, so the skipped second protects nothing
  the old code protected.
- RR-5. Shorter settle waits rely on `wait_gone` deadlines; CI load could
  still exceed 5 s. The deadline is five times the wait it replaces, and the
  flake guard runs under load. Known history: reaper cases flake on CI load
  only (docs/knowledge/LEARNED.md and the run-tests comments).
- RR-6. The leg bound depends on CI runner variance; one run decides it.
  If it fails narrowly, a re-run is evidence, not a fix; the owner decides
  (D6).
- RR-7. TEST-010 is a timing assertion (fastest of three under 0.8 s,
  against a grace of 1.0 s). A heavily loaded runner could exceed it; taking
  the fastest of three is the mitigation.
