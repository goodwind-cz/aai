---
id: spec-docs-audit-suite-speed
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: bed44380a76468844f24ef6e65aa6b8c56f41a5ba8cc5929bb95c1785d9dac35
ceremony_level: 2
links:
  requirement: docs-audit-suite-speed
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Make the always-on docs-audit suite measurably faster

SPEC-FROZEN: true

## Links

- Requirement: [Docs-audit suite speed](../issues/CHANGE-DRAFT-docs-audit-suite-speed.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md), phase 2, child 3.
- Prior child: [SPEC-0241](SPEC-0241-spec-docs-audit-node-test-pilot.md) and
  [its report](../analysis/docs-audit-node-test-pilot.md).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Bash 3.2 and GNU Bash).
- Baseline commit: `34f0cbcad78fc851ed60972b1c527dcbc4c47779` (main at planning time).

## Implementation strategy

- Strategy: hybrid
- Rationale: the shared live-corpus helpers, the restore-order defect fix, the
  Node closeout batch and the wiring lint change what the suite proves, so each
  of those rows goes RED first and carries a mutation record (TDD). The analysis
  note, the measurement and the weights row are evidence work done in loop mode,
  but their note-consistency rows are still mutation-gated. No production
  behavior changes: `.aai/scripts/lib/docs-audit-core.mjs` and
  `.aai/scripts/docs-audit.mjs` stay byte-identical to the baseline.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: PR-bound test refactor that regenerates the real
  `docs/INDEX.md` during runs, needs paired before/after timing from a
  disposable baseline checkout, and runs mutations in clones. The ride already
  runs in its own linked worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: change/docs-audit-suite-speed at /private/tmp/aai-docs-audit-speed
- Inline review scope: tests/skills/test-aai-docs-audit.sh;
  tests/skills/lib/docs-audit-live.sh; tests/skills/lib/docs-audit-closeout.test.mjs;
  tests/skills/suite-map.yaml; tests/skills/suite-weights.tsv;
  docs/analysis/docs-audit-suite-speed.md; docs/product/ci-test-impact-selection.md;
  CHANGELOG.md; docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md;
  docs/issues/CHANGE-DRAFT-docs-audit-suite-speed.md; this spec.
- Code review required: true.

## What the profile says (Planning measurement)

Planning profiled every one of the 195 functions `main()` runs, by sourcing the
suite in a scratch clone and calling them in `main()` order with a monotonic
timer (raw files: `docs/ai/tdd/docs-audit-suite-speed/planning/`). Two clean
passes totalled 115.6 s and 116.1 s; the ordinary wrapper run took 115.2 s and
114.6 s on the same host (macOS arm64, Node 22.23.1, Bash 3.2.57, Git 2.54.0).

The cost is NOT dominated by fixture logic groups. It is dominated by repeated
work over the real corpus:

| Cost class | Launches | Local seconds | Share |
|---|---|---|---|
| Full real-corpus `docs-audit.mjs` runs (14 launches, 3 distinct argument lists, byte-identical output within a run) | 14 | 22.7 | 20% |
| Real-corpus `generate-docs-index.mjs` runs (11 launches; 10 are five identical idempotence pairs plus one fresh snapshot) | 11 | 19.8 | 17% |
| `test_histmap_corpus_equivalence` per-file git oracle over 1005 tracked docs, serial | 1 | 10.2 | 9% |
| All fixture-repo CLI launches (docs-audit 222, generator 59, append-event 25) | 306 | 32.9 | 28% |
| Bash, git fixture creation and the rest | n/a | about 30 | 26% |

Shared `setup_fixture` costs 0.2 s, so fixture reuse is not a lever. The
nine captured `--check --strict --no-event` outputs and all eleven real index
snapshots of one run are byte-identical (`live-output-checksums.txt`).

Choice, in the intake's spirit (faster always-on suite, every assertion kept):

1. Lever A, shared live-corpus audit: run each distinct real-corpus audit
   argument list once per suite run and hand every consumer its own copy.
   Expected saving about 16.5 s.
2. Lever B, shared real index pair: generate the real index twice once per run,
   restore the real files before any assertion, and let the five idempotence
   consumers and the fresh snapshot read those two snapshots. Expected saving
   about 14 s. This also fixes a measured defect (see Spec-AC-03).
3. Lever C, sharded histmap oracle: keep the per-file `firstCommitDate` oracle
   over the whole corpus, computed in parallel worker threads. Prototype:
   9.7 s serial, 3.1 s with 4 workers, 1.7 s with 8.
4. Node batch (intake lever, chosen by measured cost among groups reachable
   through existing exports): the eight closeout logic groups, which each
   re-launch the identical `--path docs/closeout` audit (about 2 s together),
   move to `node:test` over `runAudit(root, { quick: true, scopePath })`, plus the
   existing in-process `hasUnfinishedRolloutPhases` case. Expected saving about 2 s.

Rejected: running suite functions in parallel (shared cwd, shared `TEST_DIR`
and the real index make it unsafe), and a larger `node:test` migration this
ride (pilot rate is about 0.3 s per group; thirty groups would be needed to
match Lever A alone).

## Scope and design

### D1. Live-corpus helper library

New file `tests/skills/lib/docs-audit-live.sh`, sourced by the suite next to
`assert-payload.sh`. It owns every real-corpus full audit and every
real-corpus index generation the suite performs, except the pinned-clock
generation in `index_generate_at`. Root is `LIVE_ROOT`, default `PROJECT_ROOT`,
so its own tests drive it against a fixture repository.

- `live_audit <dest> <args...>` runs `node .aai/scripts/docs-audit.mjs <args>`
  in `LIVE_ROOT` at most once per cache key, stores combined stdout and stderr
  and the exit code, copies the output to `<dest>`, and returns the stored exit
  code. Key = the argument list plus `live_fingerprint`, which covers `LIVE_ROOT`,
  its HEAD commit and the content of `docs/INDEX.md` and
  `docs/INDEX.violations.md` (absent counts as a value).
- Every real launch appends one line to `$LIVE_CACHE_DIR/launches.log`.
- `AAI_DOCS_AUDIT_LIVE_VERIFY=1` makes every cache hit also run fresh and
  byte-compare output and exit code with the cached ones; a difference is a
  failure naming `LIVE-CACHE MISMATCH`.
- `live_index_pair` generates the index in `LIVE_ROOT` twice once per run,
  snapshots `INDEX.md`, `INDEX.audit.md` and `INDEX.violations.md` after each
  run, records both exit codes, then restores `INDEX.md` byte for byte, restores
  a pre-existing violations companion or removes one the runs created, all
  before it returns.
- The cache directory lives under `TEST_DIR`; when `TEST_DIR` is empty
  (single-function dispatch) the helper creates `TEST_DIR` with the suite's own
  `mktemp` template so `cleanup()` removes it.

### D2. Consumers

Every full real-corpus audit launch becomes `live_audit`: the strict runs in
`test_spec0006_no_regression_real_repo`, `test_issue0001_no_regression_real_repo`,
`test_spec0011_regression`, `test_537_shape_check_live_yield` (both runs),
`test_change0007_regression`, `test_change0012_regression`,
`test_change0028_real_repo_clean`, `test_spec0057_real_repo_known_collisions`
(both runs), `test_acflip_real_repo_clean`,
`test_1351_live_corpus_near_miss_set_is_dispositioned`, and `silence_live_audit`.
Scoped or cheap runs (`--path`, `--quick`, `--lint-body`, `--ac-flip-check`,
`--list`) stay direct. Every real-corpus generator pair becomes `live_index_pair`:
the three Generated-stripped idempotence checks, `test_acflip_real_repo_clean`
(`index_strip_dated` comparison), `test_deterministic_index_no_clock_line`
(no clock line in the three files and byte-equal runs), and the fresh snapshot of
`setup_indexarm_snapshots` (run 1). Each consumer keeps every assertion it has
today; only the launch line and the snapshot source change.

### D3. Sharded histmap oracle

`test_histmap_corpus_equivalence` computes the per-file map with
`worker_threads`, `min(8, os.availableParallelism())` shards, each shard
importing the shipped `firstCommitDate`. It keeps every existing check (whole
corpus, at least 100 documents and 100 dated, zero mismatches, the wrong-date
bite) and adds: per-file entries equal the document count, and the shard count is
at least 2 when the host has 2 or more CPUs.

### D4. Node closeout batch

New file `tests/skills/lib/docs-audit-closeout.test.mjs` writes the complete
`setup_closeout_fixture` documents byte for byte into an `fs.mkdtempSync`
directory (no git, no child process) and calls the exported `runAudit` with
`quick: true` and `scopePath: 'docs/closeout'`, asserting on
`closeoutCandidates` (id, specs, `suggestedStep` prefix `advance <id> to`). It also
hosts the `hasUnfinishedRolloutPhases` four-input case. The suite runs it once
through a new `test_2208_closeout_node` registered right after
`test_change0007_lint_body_node`.

Migration map (binding names; the analysis note reconciles each clause):

| Map | Removed Bash function | Node owner | Retained CLI owner |
|---|---|---|---|
| C1 | test_closeout_candidate_flagged | candidates contain RFC-0010 with specs SPEC-0010 | test_closeout_report_only_gate adds the one-line RFC-0010 and SPEC-0010 rendering check |
| C2 | test_closeout_spec_not_all_done | RFC-0010 present, RFC-0020 absent | none needed |
| C3 | test_closeout_terminal_parent | RFC-0010 present; RFC-0030, RFC-0032, RFC-0034 absent | none needed |
| C4 | test_closeout_no_false_positive | RFC-0010 present; RFC-0050, CHANGE-0050, RFC-0052 absent | none needed |
| C5 | test_closeout_reverse_only | RFC-0060 present with SPEC-0060 | report_only_gate renders the section |
| C6 | test_closeout_forward_nonspec_not_flagged | RFC-0070 absent | none needed |
| C7 | test_closeout_display_id_match | RFC-0080 present | none needed |
| C8 | test_closeout_rollout_guard | RFC-0080 present, RFC-0090 absent | none needed |
| C9 | test_rollout_status_pipe_styles | four inputs give true, true, false, false | none needed |

`test_closeout_read_only` and `test_closeout_report_only_gate` stay and keep
their assertions. `test_closeout_report_only_gate` also becomes self-sufficient
under single-function dispatch (it runs `setup_fixture` and
`setup_closeout_fixture` itself when `TEST_DIR` is empty) and names TEST-2209 in
its failure messages.

### D5. Wiring, docs and weights

- suite-map: add `tests/skills/lib/docs-audit-live.sh` and
  `tests/skills/lib/docs-audit-closeout.test.mjs` under `aai-docs-audit`.
- New self-contained suite functions (each also works under single-function
  dispatch and prints its TEST id in every failure message):
  `test_2202_live_audit_memo`, `test_2203_live_audit_verify_mode`,
  `test_2204_live_index_pair_restores`, `test_2205_committed_index_staleness_survives`,
  `test_2206_no_direct_live_corpus_launch`, `test_2208_closeout_node`,
  `test_2211_migration_map_owners`, `test_2201_speed_note_profile`,
  `test_2210_speed_note_measurement`. Register each once in `main()`.
- Analysis note `docs/analysis/docs-audit-suite-speed.md` (format in the brief),
  product page section, CHANGELOG entry, RFC-0017 phase 2 row.
- `tests/skills/suite-weights.tsv`: re-measure the `aai-docs-audit` row from at
  least three successful hosted full-framework runs (workflow_dispatch on the
  final candidate head is acceptable) whose `test-aai-docs-audit.sh` blob equals
  the final one, with `# source run` lines; update the fallback rows and the
  header maximum that `auditWeights` ties to the maximum measured weight.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (profile and batch choice in the note).
- Intake AC-002 maps to Spec-AC-05 (Node closeout batch, migration map C1 to C9).
- Intake AC-003 maps to Spec-AC-05 and Spec-AC-07 (ordinary run executes and
  propagates the Node cases; registration and mapping).
- Intake AC-004 maps to Spec-AC-02, Spec-AC-03, Spec-AC-04 (the levers) and
  Spec-AC-06 (measurement). The target is tightened from 25% to 30%: the profile
  supports about 37% (16.5 + 14 + 8 + 2 s of 115 s), and 30% keeps margin for
  noise.
- Intake AC-005 maps to Spec-AC-03 and Spec-AC-07 (retained CLI, hooks,
  predicates and real-corpus checks still run, and the committed-index
  staleness check regains its bite).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | The analysis note lists the measured per-function cost of every function main runs, states a profiled total that equals the sum of its rows within 0.5 s, and names every lever's functions from that table. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_2201_speed_note_profile.log | TDD | TEST-2201 |
| Spec-AC-02 | WHEN the ordinary suite runs, the system SHALL launch a full real-corpus docs-audit once per distinct argument list and fingerprint (at most 3 launches, was 14), hand each former consumer a byte-identical copy, relaunch after docs/INDEX.md changes, and fail on any cache difference under AAI_DOCS_AUDIT_LIVE_VERIFY=1. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_2202_live_audit_memo.log | TDD | TEST-2202, TEST-2203, TEST-2206 |
| Spec-AC-03 | WHEN the ordinary suite runs, the system SHALL run the real index generator at most 3 times (was 11), restore the real INDEX.md and violations companion byte for byte before any assertion, and keep every consumer's idempotence and clock-line assertion; a stale committed INDEX.md SHALL still fail the committed-index staleness check in main order. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_2204_live_index_pair_restores.log | TDD | TEST-2204, TEST-2205 |
| Spec-AC-04 | WHEN test_histmap_corpus_equivalence runs, the system SHALL still compare the shipped per-file firstCommitDate for every tracked doc against the bulk map, using at least 2 worker shards on a host with 2 or more CPUs. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_histmap_corpus_equivalence.log | TDD | TEST-2207 |
| Spec-AC-05 | WHEN the ordinary suite runs, the system SHALL execute the closeout Node cases once and fail when any fails; the eight closeout functions and test_rollout_status_pipe_styles SHALL be absent, and each map row C1 to C9 SHALL have its named Node or CLI owner. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_2208_closeout_node.log | TDD | TEST-2208, TEST-2209 |
| Spec-AC-06 | Five alternating paired local runs of the ordinary suite show an after median at most 0.70 times the before median; the note reports at least 5 hosted before and 3 hosted after docs-audit durations, and the aai-docs-audit weight row is re-measured with valid provenance. | deferred | docs/ai/tdd/docs-audit-suite-speed/green/test_2210_speed_note_measurement.log | 2026-11-06 | TEST-2210; local paired runs done (31.9% reduction); hosted after rows and suite-weights re-measure pending push |
| Spec-AC-07 | The ordinary suite exits 0 through the wrapper; every retained owner is defined and registered once, the removed functions are gone, check-test-registration exits 0, and both new lib files select aai-docs-audit without a full-run fallback. | done | docs/ai/tdd/docs-audit-suite-speed/green/test_2211_migration_map_owners.log | TDD | TEST-2211 |

## Implementation plan

1. Store the Planning profile and the baseline wrapper timing as the before
   record; build a disposable baseline checkout at the baseline commit for paired
   timing (never the shipping tree).
2. TDD the helper library through TEST-2202 to TEST-2206 (RED first: the lib
   does not exist, and TEST-2205 is RED on the baseline ordering), then convert
   every consumer in D2.
3. TDD the histmap sharding (TEST-2207) and the closeout batch
   (TEST-2208, TEST-2209), then remove the nine mapped functions and their
   registrations.
4. Wiring, registration and suite-map (TEST-2211).
5. Measure (Spec-AC-06), write the note, product section, CHANGELOG and
   RFC-0017 row; after the PR CI and the dispatched full runs, re-measure the
   weight row and re-run test-aai-suite-select.sh.

Seams crossed:

- Producer `live_index_pair` writes and restores the real index; consumer
  `setup_indexarm_snapshots` reads it as the committed index. TEST-2205 produces
  on one side (a stale committed index in a fixture repo, then a pair) and
  asserts on the other (the staleness check still fires).
- Producer `runAudit` builds the doc records; consumer `closeoutCandidatesFor`
  reads them. TEST-2208 goes through `runAudit` over written files, never hand
  built doc objects.
- Producer `docs-audit.mjs` renders the closeout section; TEST-2209 keeps the
  CLI half of that seam.
- The cache crosses suite functions: TEST-2202 (key and invalidation),
  TEST-2203 (verify mode) and TEST-2206 (no consumer bypasses it).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2201 | Spec-AC-01 | inspection | tests/skills/test-aai-docs-audit.sh | test_2201_speed_note_profile parses the note's Cost profile table, checks the Profiled total line equals the sum of the Pass 1 column within 0.5 s and every lever function appears in that table | `sed:s/Profiled total \(pass 1\): /Profiled sum: /` on docs/analysis/docs-audit-suite-speed.md | green |
| TEST-2202 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | test_2202_live_audit_memo on a fixture repo as LIVE_ROOT: two calls with one argument list give one launch and identical output and exit code; a second argument list launches again; rewriting docs/INDEX.md launches again | `sed:s/\$\(live_fingerprint\)/static/` on tests/skills/lib/docs-audit-live.sh | green |
| TEST-2203 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | test_2203_live_audit_verify_mode corrupts a cached output file, calls again with AAI_DOCS_AUDIT_LIVE_VERIFY=1 in a subshell and asserts a nonzero exit naming LIVE-CACHE MISMATCH; an uncorrupted hit passes | `sed:s/cmp -s "\$fresh_out" "\$cache_out"/true/` on tests/skills/lib/docs-audit-live.sh | green |
| TEST-2204 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | test_2204_live_index_pair_restores on a fixture repo whose corpus yields a violations companion it did not have: after the pair INDEX.md is byte-identical, the companion is absent, both snapshots exist and a second consumer adds no launch | `sed:s/rm -f "\$live_viol"/: keep companion/` on tests/skills/lib/docs-audit-live.sh | green |
| TEST-2205 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | test_2205_committed_index_staleness_survives commits an INDEX.md missing a tracked doc in a fixture repo, runs live_index_pair, then index_stale_findings on the fixture INDEX.md must still report STALE | `sed:s/cp "\$live_idx_backup" "\$live_idx"/: skip restore/` on tests/skills/lib/docs-audit-live.sh | green |
| TEST-2206 | Spec-AC-02 | inspection | tests/skills/test-aai-docs-audit.sh | test_2206_no_direct_live_corpus_launch scans the suite text: no PROJECT_ROOT docs-audit launch without --path, --quick, --lint-body, --ac-flip-check or --list, and no PROJECT_ROOT generator launch outside the lib and index_generate_at; at least 14 live_audit call sites | `sed:s/live_audit "\$TEST_DIR\/c12-repo-audit.log" --check --strict --no-event/(cd "$PROJECT_ROOT" && node .aai\/scripts\/docs-audit.mjs --check --strict --no-event > "$TEST_DIR\/c12-repo-audit.log" 2>&1)/` on tests/skills/test-aai-docs-audit.sh | green |
| TEST-2207 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | test_histmap_corpus_equivalence keeps its whole-corpus checks and bite, asserts per-file entries equal the document count and at least 2 shards, and names TEST-2207 in its failure message | `sed:s/'--no-renames', //` on .aai/scripts/lib/docs-audit-core.mjs | green |
| TEST-2208 | Spec-AC-05 | unit | tests/skills/test-aai-docs-audit.sh | test_2208_closeout_node runs node --test tests/skills/lib/docs-audit-closeout.test.mjs from PROJECT_ROOT and fails naming TEST-2208 when any C1 to C9 case fails | `sed:s/if \(parent\.rolloutUnfinished\) continue;/void 0;/` on .aai/scripts/lib/docs-audit-core.mjs | green |
| TEST-2209 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | test_closeout_report_only_gate keeps strict exit 0, the Closeout candidates heading and the RFC-0010 line, adds the one-line RFC-0010 and SPEC-0010 check, and is self-sufficient under single dispatch | `sed:s/### Closeout candidates: /### Close-out candidates: /` on .aai/scripts/docs-audit.mjs | green |
| TEST-2210 | Spec-AC-06 | performance | tests/skills/test-aai-docs-audit.sh | test_2210_speed_note_measurement recomputes both medians from the note's five pair rows, checks the Median reduction line and that it is at least 30.0, and counts at least 5 hosted before and 3 hosted after rows | `sed:s/Median reduction: /Median change: /` on docs/analysis/docs-audit-suite-speed.md | green |
| TEST-2211 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | test_2211_migration_map_owners checks the nine removed functions are neither defined nor registered, each retained owner is defined and registered exactly once, and select-suites maps both new lib files to aai-docs-audit with no FULL_RUN | `sed:s/(\n  )test_closeout_read_only(\n)/$1: test_closeout_read_only$2/` on tests/skills/test-aai-docs-audit.sh | green |

Test-file note: every row's selector is a function in
`tests/skills/test-aai-docs-audit.sh` that runs alone under single-function
dispatch (`bash tests/skills/test-aai-docs-audit.sh <function>`), because
`mutation-run.mjs` runs bash suites only and dispatches one function. The Node
file is reached through `test_2208_closeout_node`. Every failure message of a
row's selector names that row's TEST id, so `mutation-run.mjs` can attribute
the RED.

### RED observations and negative controls

- TEST-2202 to TEST-2206, TEST-2208, TEST-2210, TEST-2211 and TEST-2201 are RED
  on the baseline because their functions, the lib, the Node file or the note do
  not exist. Record each RED run under `docs/ai/tdd/docs-audit-suite-speed/`.
- TEST-2205 also has a behavioral RED: on the baseline the main-order sequence
  `setup_fixture`, `test_deterministic_index_no_clock_line`,
  `setup_indexarm_snapshots`, `test_indexarm_index_is_not_stale` passes over a
  stale committed index (`planning/stale-index-masking-probe.txt`); after the
  change the same sequence must fail. Record both runs.
- TEST-2207 and TEST-2209 already exist in another form; their RED is the
  mutation record.
- Positive controls: TEST-2202 asserts the second argument list does launch, so a
  helper that never caches and a helper that never relaunches both fail. TEST-2203
  asserts the uncorrupted hit passes.

## Verification

- Ordinary suite: `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
  exits 0 and prints `PASS: All aai-docs-audit tests passed`.
- Equivalence on the real corpus: the same command with
  `AAI_DOCS_AUDIT_LIVE_VERIFY=1` exits 0 (every cache hit re-run and byte-equal).
- Launch budget: the same command with a node PATH shim (the Planning
  `node-shim.sh` pattern) shows at most 3 full real-corpus docs-audit launches
  and at most 3 real-corpus generator launches with cwd PROJECT_ROOT.
- Node file alone: `bash .aai/scripts/aai-run-tests.sh node --test tests/skills/lib/docs-audit-closeout.test.mjs` exits 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite tests/skills/test-aai-docs-audit.sh --selector <function> --target <file> --sed '<expr>'`
  per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Weights: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh` exits 0 after the row update.
- Production unchanged: `git diff --quiet 34f0cbcad78fc851ed60972b1c527dcbc4c47779 -- .aai/` exits 0.

### Measurement design (Spec-AC-06)

Before (B) is the baseline commit in a disposable checkout with its own git
directory; after (F) is the candidate in another disposable checkout. Both run
the ordinary wrapper command above on the same host, Node, Bash, Git, wrapper and
serial width. One untimed warm-up per side, then five pairs alternating B then F
and F then B. External monotonic wall time per run; every attempt is disclosed;
a failed run voids its pair and the pair is rerun after diagnosis. The note
embeds every raw row, both medians, the reduction and the environment. Hosted:
the before rows are existing successful skill-suite runs on main or PR heads
(at least 5, run id, head SHA, docs-audit seconds from the log line
`aai-docs-audit PASS (Ns)`); the after rows are at least 3 successful runs whose
docs-audit suite blob equals the final one. Hosted durations vary from 116 s to
207 s on unchanged code, so the hosted numbers are reported, never gated.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/docs-audit-suite-speed/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. Planning's own measurements are inputs, not attestations of the
implementation.

## Risks and rollback

- A stale cache could hide a real regression. Mitigations: the fingerprint
  covers the only real-tree files the suite writes, verify mode proves
  byte-equality on the real corpus, and TEST-2206 stops a consumer from
  bypassing the helper. Residual: an edit to another real-corpus document by a
  concurrent process during one run is not detected. The wrapper runs the suite
  in its own disposable checkout, so this needs a writer inside that checkout.
- Single-function dispatch skips `setup_fixture`; every new or changed selector
  sets up what it needs.
- The weights row cascades into the fallback rows; test-aai-suite-select.sh
  is the guard.
- Rollback is one revert of the scope's files; production code is untouched.

## Registry disposition

Related open registry items, all left open:

- `fu-docs-audit-suite-has-no-selector` is not closed. The suite already
  dispatches one function (TEST-012), and every row here relies on that, so the
  item may be stale. Retiring it is registry triage, outside this scope.
- `fu-prompt-diet-fixture-real-root-race` stays open. It concerns bare
  concurrent invocations writing the real tree; the cache's residual risk above
  is the same class and is disclosed, not fixed.
- `fu-runmain-runs-main-on-import` stays open. The Node batch imports only the
  library.

Registry items closed by this scope: none.
