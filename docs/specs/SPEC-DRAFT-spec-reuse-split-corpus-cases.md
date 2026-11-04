---
id: spec-reuse-split-corpus-cases
type: spec
number: null
status: implementing
frozen_sha256: eddd9d13e8de67f75ef1d79fbcbb184e8cebd9bcc48b4450f652fa3d4f5c3d6e
mutation_gate: v1
ceremony_level: 2
links:
  requirement: reuse-split-corpus-cases
  rfc: RFC-0017
  pr: []
  commits: []
---

# Fixture cases of aai-hygiene-pack and aai-win-fallback get their own narrow identity: whole-checkout cases move to two corpus suites

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-DRAFT-reuse-split-corpus-cases.md
- Prior slices: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md,
  docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md (access-trace
  identity, admission gate), docs/specs/SPEC-0270-spec-reuse-local-ledger-append.md
  (an unchanged rerun reuses index-reading suites)
- Split precedent: docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md
  (one definition file, a declared case list, a second suite file that sources it)
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (stays open)
- Measurement note: docs/analysis/precise-suite-evidence-reuse.md
- Product doc: docs/product/precise-suite-evidence-reuse.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor;
  system Bash 3.2 and GNU Bash for suites)
- Baseline commit: `6db05ffa562ba582a8f4e597417a95042ed60801` (main at planning time)

## Implementation strategy

- Strategy: tdd
- Rationale: the split decides which cases run on a pull request and which
  suite a reuse record covers. The two hazards are a case that silently runs
  nowhere (lost coverage) and a whole-checkout case left in a half that is
  reported REUSED (a false hit). Every row that guards the partition, the
  selection, the manifest or the admission goes RED first and carries a
  mutation record. TDD in runs of about three Spec-ACs (see the Test Plan).
  Mutation gate v1 applies.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions; the
  measurement needs seed runs, edits and reruns that append to the tracked run
  ledger, and mutation runs rewrite suite files. No file is in
  `protected_paths_l3`, so not required.
- User decision: worktree (autopilot default;
  /Users/ales/Projects/aai-worktrees/reuse-split-corpus-cases, branch
  feat/reuse-split-corpus-cases)
- Base ref: main
- Inline review scope: the list in "Files Implementation touches".
- Code review required: true.

## What Planning measured

Host: Apple M4 Max, macOS 27.0.1 (Darwin 27.0.0 arm64), Node v22.23.1, GNU bash
3.2.57, Git 2.54.0. Baseline commit above. `AAI_ROLE` unset. Raw data and the
harness are in the ride worktree under
`docs/ai/tdd/reuse-split-corpus-cases/planning/` (gitignored, local).

### M1 Method

For each of the five suites, a fresh `git clone --local --no-hardlinks` of the
baseline, detached, origin defanged and refs fetched, the same shape as the
framework's disposable checkout. For every case of the suite's full-run list,
in list order: `git reset --hard` and `git clean -fd` of the clone, then
`armTrace` of `.aai/scripts/lib/checkout-trace.mjs` on the clone, then the case
alone through the suite's own single-case dispatch
(`bash tests/skills/test-<suite>.sh <case>`), then `collectTrace`. Per case:
exit code, wall seconds, files read, whether the git index was read.
aai-docs-content's cases share state (its list starts with `check_deps`,
`setup_fixture` and `setup_indexarm_snapshots`, and later cases assert on a
live audit cached by earlier ones), so it was traced in one bash process that
sources the definition file and arms and collects between cases. Whole-suite
wall time: one run of each suite file in a fresh clone.

Class of a case: **index** (the trace read the git index, so the suite's
identity is every tracked file), **wide** (no index read, but at least 100
checkout files read: a whole tree such as all of `docs/specs/`, all suite files
or all of `.aai/scripts/`), **ledger** (reads `docs/ai/decisions.jsonl`,
`docs/ai/METRICS.jsonl` or `docs/ai/EVENTS.jsonl`, which role actions append
to during a ride), **fixture** (everything else).

### M2 Results

| Suite | Whole run s | Cases | index+wide+ledger cases | their s | fixture cases | their s | fixture read union |
|---|---|---|---|---|---|---|---|
| aai-hygiene-pack | 117.3 | 95 | 29 (7 index, 19 wide, 3 ledger) | 76.7 | 66 | 36.9 | 160 files |
| aai-win-fallback | 43.6 | 32 | 5 (5 index) | 19.3 | 27 | 29.5 | 57 files |
| aai-spec-lint | 38.6 | 52 | 12 (1 index, 11 wide) | 30.7 | 40 | 4.5 | 15 files |
| aai-prompt-diet | 4.3 | 42 | 5 (3 index, 2 wide) | 3.8 | 37 | 2.6 | 79 files |
| aai-docs-content | 24.3 | 25 list entries | 13 index or wide | about 22 | 0 | 0 | none |

Per-case second sums run a little above or below the whole run (each case
pays its own bash start and `check_deps`); they are used only to compare the
two parts of one suite.

- aai-hygiene-pack: one case dominates the corpus part,
  `test_124_degenerate_pass_guards_uncovered_and_ratcheted` (36.0 s, index),
  then `test_094_mutation_selector_fails_closed_corpus_wide` (11.1 s, index).
  `test_120_userguide_catalog_covers_every_skill` fails when run alone
  (it writes `$TEST_DIR/t120-catalog-tokens.txt` and `TEST_DIR` is set only by
  an earlier case in the list); its partial trace read `docs/USER_GUIDE.md`
  and `.claude/skills/**`, no index, so it is a fixture case.
- aai-win-fallback: the five index cases run the real `aai-run-tests.sh`
  wrapper (MSYS reaper arms and the TEST-028 gate); every other case reads
  57 files at most.
- aai-spec-lint: the eleven wide cases each read all 274 files of
  `docs/specs/` (or, for `test_clarify_011_no_new_ceremony`, all of `.aai/`);
  the index case is `test_011_seam_survival` (strict docs-audit plus two index
  regenerations, 17.2 s).
- aai-docs-content is already the corpus half of SPEC-0260. Its list entries
  that did not read the index or a docs tree themselves assert on the cached
  live audit of an earlier entry, or read one named document (TEST-2310,
  0.03 s). There is no fixture part.

### M3 Representative edits against the fixture read unions

- E1, one production script: a comment line appended to
  `.aai/scripts/pr-preflight.mjs`. It is not in the fixture union of
  aai-hygiene-pack, aai-win-fallback, aai-spec-lint or aai-prompt-diet.
- E2, one product doc: a line appended to
  `docs/product/precise-suite-evidence-reuse.md`. Not in any fixture union.
- Ride ledgers: `docs/ai/decisions.jsonl` is read by hygiene-pack
  `test_134_nested_suite_disclosures` and `test_137_hot_spot_disclosures`,
  `docs/ai/METRICS.jsonl` by `test_116_metrics_correction_not_counted`; these
  three are the ledger class and move with the corpus cases. `CHANGELOG.md`
  stays in the fixture unions of aai-hygiene-pack (`test_814_disclosure_and_docs`)
  and aai-win-fallback (`test_023`, `test_026`): it changes once per ride, at
  close-out.

### M4 Cost of one more suite

A `git clone --local --no-hardlinks` of the repository takes 0.35 s; the
framework adds seeding and the trace arm (about 0.2 s per suite, SPEC-0268
measurement). In CI a split suite adds one disposable checkout and runs the
same cases as before, in one framework invocation (selected) or one shard
(full). Each new suite also needs a suite-map row, a weights row and a reuse
manifest entry, and its admission runs it about three times when its entry
changes.

## Assumptions (autopilot, recorded instead of asked)

- A split pays off when the fixture part is at least 10 s of measured case
  time and both representative edits E1 and E2 leave it unread. Below that, the
  saving is smaller than the run-to-run noise of a local framework run (SPEC-0266
  note: 90 to 106 s for one unchanged suite set) and does not pay for a second
  suite's rows, admission and CI checkout.
- "Corpus" in this spec means "makes the identity of its suite the whole
  checkout or a whole tree": index, wide and ledger cases. It is wider than
  "reads `docs/`".
- The fixture half keeps the original suite name; the moved cases go to a new
  suite named `<original>-corpus` (hygiene-pack becomes `aai-hygiene-corpus`
  for the short name, win-fallback becomes `aai-win-fallback-corpus`).

## Decisions

### D1 Which suites are split

- Split: **aai-hygiene-pack** (fixture part 66 cases, 36.9 s; corpus part 29
  cases, 76.7 s) and **aai-win-fallback** (fixture part 27 cases, 29.5 s;
  corpus part 5 cases, 19.3 s).
- Not split, with the evidence:
  - aai-spec-lint: the fixture part is 4.5 s of a 38.6 s suite (40 cases).
    Splitting off only the index case would leave a part whose identity
    includes all of `docs/specs/` and `.aai/`, which a spec edit or a script
    edit (E1) invalidates. Below the D1 threshold.
  - aai-prompt-diet: the whole suite is 4.3 s; the fixture part is 2.6 s.
  - aai-docs-content: no fixture part (M2).

### D2 One definition file, a declared corpus list, a thin corpus suite

Following SPEC-0260 D1:

- `tests/skills/test-aai-hygiene-pack.sh` keeps every function and helper.
  It gains `HYGIENE_CORPUS_CASES`, a double-quoted list with one name per line
  at a two-space indent, in baseline `main()` order, exactly these 29 names:
  test_030_auto_trigger_deprecation, test_043_review_taxonomy_alignment,
  test_060_work_item_brief, test_092_no_phantom_node_apis,
  test_093_test_registration, test_102_pgq_ratchet_gate_and_bite,
  test_103_pgq_baseline_is_measured_not_typed,
  test_104_pgq_shrink_never_lowers_the_bar, test_562_no_nul_in_tracked_text,
  test_122_pgq_corpus_drained_to_zero,
  test_124_degenerate_pass_guards_uncovered_and_ratcheted,
  test_126_learned_guard_lints_live_and_markers,
  test_832_sync_leaves_history_out_of_downstream,
  test_106_base_ref_pin_gate_and_bite, test_108_cd_subshell_leak_gate_and_bite,
  test_111_generator_check_clean_and_idempotent,
  test_113_bite_proofs_in_detached_worktree,
  test_116_metrics_correction_not_counted, test_117_source_skills_are_lf_pinned,
  test_127_withdrawn_phrases_drained,
  test_094_mutation_selector_fails_closed_corpus_wide,
  test_129_mutation_gate_suite_registration,
  test_130_node_bash_selector_scanner_whitespace_parity,
  test_131_vendored_script_deps_gate_and_bite,
  test_133_nested_suite_lint_live_and_base, test_134_nested_suite_disclosures,
  test_137_hot_spot_disclosures, test_138_ci_node_pins,
  test_815_suite_map_and_registration.
  Its `main()` registers the other 66 cases only, in baseline order. The
  single-case dispatch of the definition file keeps working for every defined
  case, moved ones included (mutation records of earlier specs select by
  `<file> <function>`).
- New `tests/skills/test-aai-hygiene-corpus.sh` (suite `aai-hygiene-corpus`)
  sources the definition file, sets `TEST_NAME`, runs `check_deps`, runs every
  name of the list with the loop line `for fn in $HYGIENE_CORPUS_CASES; do`,
  supports the same single-case dispatch, exits 0, 1 or 42 with the usual
  meaning and prints `PASS: All aai-hygiene-corpus tests passed`.
- `tests/skills/test-aai-win-fallback.sh` keeps `ALL_TESTS` as the full
  32-number list (TEST-027 and `check-test-registration.mjs` read it) and
  gains `WIN_FALLBACK_CORPUS_TESTS="007 029 030 031 042"`. Its `main()`
  without arguments runs `ALL_TESTS` minus those five; with arguments it runs
  exactly the named ones, as today.
- New `tests/skills/test-aai-win-fallback-corpus.sh` (suite
  `aai-win-fallback-corpus`) sources the definition file and runs the five,
  with single-case dispatch, and prints
  `PASS: All selected aai-win-fallback-corpus tests passed`.
- No assertion, TEST id or log text of a moved case changes. Setup a case
  needs (`TEST_DIR`, `check_deps`, the EXIT trap) is created by each suite
  entry before its first case, not inherited from a case that moved (this is
  what makes `test_120` independent of list order).

### D3 Selection

- `tests/skills/suite-map.yaml` `core:` becomes exactly `aai-check-state`,
  `aai-docs-content`, `aai-spec-lint`, `aai-hygiene-pack`,
  `aai-hygiene-corpus`, with a comment pointing at this spec: the
  pipe-into-grep-q ratchet that made hygiene-pack core (test_102 to test_104,
  test_122) moves to the corpus half, and the fixture half stays core because
  it was core before (no coverage moves out of the always-on set).
- New row `aai-hygiene-corpus` whose globs are its own suite file and
  `tests/skills/test-aai-hygiene-pack.sh` (a definition-file edit selects both
  halves even outside core, for delta and selected-plan tooling).
- `aai-win-fallback` gains `companions:` with `aai-win-fallback-corpus`, so
  every diff that selects aai-win-fallback also selects the corpus half (the
  same selection as today, no glob duplicated). New row
  `aai-win-fallback-corpus` whose globs are its own suite file and
  `tests/skills/test-aai-win-fallback.sh`.
- The `aai-suite-reuse` row gains both new suite files (manifest suites'
  files select the admission gate).
- `.aai/scripts/lib/**` stays a FULL_RUN trigger; protected L3 and unmapped
  triggers are unchanged.

### D4 Reuse manifest

- New entries `aai-hygiene-corpus` and `aai-win-fallback-corpus`, `live:
  false`, notes in the SPEC-0270 form: the suite reads the git index, so its
  identity is every tracked file, with lines appended to
  `docs/ai/tests/test-runs.jsonl` tolerated, plus the admission counts.
- The notes of `aai-hygiene-pack` and `aai-win-fallback` are rewritten from
  their new admission: files read, files poisoned, and no git index read.
- `lint --admit --changed-since main` must print `ADMIT-PASS` for all four,
  with `poisoned=` greater than 0 for the two fixture halves (the poisoned run
  overwrote every checkout file the trace did not see read and the suite still
  passed: the proof that the half is narrow), and an appended-ledger
  `ADMIT-PROBE ... PASS` line for each of the two corpus suites.

### D5 Weights, pins and other consumers

- `tests/skills/suite-weights.tsv`: one row per new suite with the file's
  unsampled convention (`# sample <suite> fallback unsampled (...)` and the
  documented maximum 212). Existing rows unchanged (reseeding is out of scope).
- Existing pins whose value follows the suite set (meaning unchanged, value
  updated, disclosed here): TEST-2311 in `tests/skills/test-aai-suite-select.sh`
  (exact core list and the product doc line in
  `docs/product/ci-test-impact-selection.md`), TEST-3275 in
  `tests/skills/test-aai-suite-reuse.sh` (the manifest suite list, now
  thirteen, and the suite files that select the gate), and
  `FIVE_INDEX_SUITES` used by TEST-3306 and TEST-3307 (now aai-docs-content,
  aai-spec-lint, aai-prompt-diet, aai-hygiene-corpus, aai-win-fallback-corpus).
- Windows and Pester: no `.Tests.ps1` mirrors these suites and the
  ps1-quality path filter names neither suite file (verified by grep at
  planning); nothing to update. `.github/workflows/skill-suite.yml` names no
  core suite by name except in a comment about the hygiene pin; it is not
  touched unless that comment becomes false.

### D6 Measurement protocol (analysis note, new section)

Heading `## Measurements (corpus split)` in
docs/analysis/precise-suite-evidence-reuse.md:

- Case inventory: one row per full-run case of the five suites at the
  implementation tip, columns Suite, Case, Class (index, wide, ledger,
  fixture), Files read, Index, Seconds, Half (fixture, corpus, or unsplit),
  measured with the M1 method.
- Before/after: before = the baseline commit, after = the implementation tip,
  each in a disposable detached worktree. Suite set: the five original suites
  before, the same plus the two corpus suites after. For each edit E1 and E2:
  one seed run with reuse on, a copy of `tests/skills/results/reuse/`, the
  edit, then three rerun samples with reuse on, the store restored before each.
  Command: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
  with one `--skill` per suite, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE` unset.
  Per sample: wall seconds, the `Evidence reuse:` line, each suite REUSED or
  its RUN reason. Then lines `E1 before median: <s>`, `E1 after median: <s>`,
  `E2 before median: <s>`, `E2 after median: <s>`, the two 40-character
  shas, Node, Bash and Git versions. `docs/ai/tests/test-runs.jsonl` is
  restored after every run.

### D7 Rejected alternatives

- Narrowing what an index-reading case reads (for example making
  `test_124` scan a fixed list instead of the tree): changes assertions, out
  of scope by the intake.
- Taking the fixture half of aai-hygiene-pack out of `core:` with globs
  derived from its read set: saves CI time on unrelated PRs, but moves an
  always-on check onto a glob list that must keep up with 66 cases; not this
  ride.
- A companion edge from aai-hygiene-pack to aai-hygiene-corpus instead of a
  core entry: equivalent selection, but hides the always-on ratchet behind an
  indirection; the core list says it directly.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (per-case inventory in the note) and D1.
- Intake AC-002 maps to Spec-AC-02, Spec-AC-03 and Spec-AC-04.
- Intake AC-003 maps to Spec-AC-05, Spec-AC-06 and Spec-AC-07.
- Intake AC-004 maps to Spec-AC-08.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | docs/analysis/precise-suite-evidence-reuse.md has a heading Measurements (corpus split) with one case inventory row per full-run case of aai-hygiene-pack, aai-win-fallback, aai-spec-lint, aai-prompt-diet and aai-docs-content as listed at the baseline commit, each with one class out of index, wide, ledger, fixture and one half; the rows with half corpus are exactly HYGIENE_CORPUS_CASES and WIN_FALLBACK_CORPUS_TESTS and no row with half fixture has class index, wide or ledger | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3330.log (TEST-3330); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3330.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3330.txt | - | D1 D6 |
| Spec-AC-02 | HYGIENE_CORPUS_CASES equals the 29 names of D2 in that order; the names main of test-aai-hygiene-pack.sh registers plus that list equal the baseline main list of 95 with no name in both; check-test-registration.mjs over tests/skills exits 0 | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3331.log (TEST-3331); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3331.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3331.txt | - | D2 |
| Spec-AC-03 | WIN_FALLBACK_CORPUS_TESTS is 007 029 030 031 042; ALL_TESTS equals the baseline 32-number list; main of test-aai-win-fallback.sh run without arguments runs exactly ALL_TESTS minus those five and test-aai-win-fallback-corpus.sh runs exactly those five | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3332.log (TEST-3332); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3332.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3332.txt | - | D2 |
| Spec-AC-04 | WHEN a disposable clone of the branch commits a tracked text file containing a NUL byte THEN test-aai-hygiene-corpus.sh exits 1 with a FAIL line from test_562 while test-aai-hygiene-pack.sh exits 0 on the same clone; on the unmodified tree every one of the four suite files exits 0, and each moved case is still dispatched alone by its definition file | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3333.log (TEST-3333); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3333.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3333.txt; docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3334.log (TEST-3334); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3334.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3334.txt | - | D2 |
| Spec-AC-05 | WHEN select-suites.mjs runs on the real map THEN the core list is exactly aai-check-state aai-docs-content aai-spec-lint aai-hygiene-pack aai-hygiene-corpus, every changed-path list prints CORE aai-hygiene-corpus, and each glob path of the aai-win-fallback row prints a SELECTED line for aai-win-fallback and a SELECTED line for aai-win-fallback-corpus (reason companion or a glob) and no FULL_RUN | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3335.log (TEST-3335); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3335.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3335.txt | - | D3 |
| Spec-AC-06 | suite-reuse.mjs lint on the live repository exits 0; the manifest has thirteen entries including aai-hygiene-corpus and aai-win-fallback-corpus; the notes of the five index-reading suites name docs/ai/tests/test-runs.jsonl and the notes of aai-hygiene-pack and aai-win-fallback do not claim a git index read | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3336.log (TEST-3336); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3336.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3336.txt | - | D4 |
| Spec-AC-07 | lint --admit --changed-since main on the branch prints ADMIT-PASS for aai-hygiene-pack and aai-win-fallback each with poisoned greater than 0, ADMIT-PASS plus an appended docs/ai/tests/test-runs.jsonl ADMIT-PROBE PASS line for aai-hygiene-corpus and aai-win-fallback-corpus, and exits 0 (ADMIT-OFF ci under CI); suite-weights.tsv has exactly one row for each new suite and the weights audit covers every suite file | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3337.log (TEST-3337); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3337.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3337.txt; docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3338.log (TEST-3338); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3338.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3338.txt | - | D4 D5 |
| Spec-AC-08 | The note section of Spec-AC-01 reports the D6 before and after reruns for E1 and E2: before, none of the five original suites is REUSED in any sample; after, aai-hygiene-pack and aai-win-fallback are REUSED in every sample of both edits; each after median is at most 0.85 times the before median of the same edit and every median line equals the median of its three sample rows | done | docs/ai/tdd/reuse-split-corpus-cases/green/green-TEST-3339.log (TEST-3339); docs/ai/tdd/reuse-split-corpus-cases/red/red-TEST-3339.log; docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3339.txt; docs/ai/tdd/reuse-split-corpus-cases/admit-output.txt | - | D6 |

## Implementation plan

1. Run A (Spec-AC-02, Spec-AC-03, Spec-AC-04): write TEST-3331 to TEST-3334
   against the baseline, observe RED, then add the two lists, trim the two
   `main()` registrations, add the two corpus suite files, make each suite
   entry create its own setup (D2).
2. Run B (Spec-AC-05, Spec-AC-06, Spec-AC-07): write TEST-3335 to TEST-3338,
   observe RED, then the suite-map core list, rows and companion (D3), the
   manifest entries and notes from a live admission (D4), the weights rows and
   the pin updates (D5).
3. Run C (Spec-AC-01, Spec-AC-08): write TEST-3330 and TEST-3339, observe
   RED, re-run the M1 harness at the implementation tip for the inventory, run
   the D6 protocol, write the note section last.
4. Run the touched suites, `check-test-registration.mjs`, `spec-lint`, the
   mutation rows and `mutation-gate.mjs`.

### Seams crossed

| Seam | Producer | Consumer | Test |
|---|---|---|---|
| S1 definition file to corpus suite | HYGIENE_CORPUS_CASES and WIN_FALLBACK_CORPUS_TESTS | the corpus suite files that source them | TEST-3331, TEST-3332, TEST-3333, TEST-3334 |
| S2 suite map to CI selection | suite-map.yaml core, rows, companion | select-suites.mjs and the selected plan | TEST-3335, existing TEST-2311 |
| S3 manifest to admission | suite-reuse.json entries | lint --admit poisoned and appended runs of the real suites | TEST-3336, TEST-3337 |
| S4 suite files to weights audit | new test-aai-*.sh files | auditWeights of selected-scheduling-benchmark-check.mjs | TEST-3338, existing TEST-1804 |
| S5 framework reuse | the access trace of each half | check REUSED after E1 and E2 | TEST-3339 (measured) |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3330 | Spec-AC-01 | inspection | tests/skills/test-aai-suite-reuse.sh | test_3330_split_inventory parses the note section: inventory rows per suite equal the full-run list read with git show from the baseline commit (fails naming TEST-3330 when the commit is absent), one class and one half per row, the corpus-half rows equal the two declared lists, no fixture-half row of class index, wide or ledger | `sed:s/test_124_degenerate_pass_guards_uncovered_and_ratcheted/test_124_renamed/` on docs/analysis/precise-suite-evidence-reuse.md | green |
| TEST-3331 | Spec-AC-02 | integration | tests/skills/test-aai-suite-reuse.sh | test_3331_hygiene_partition reads HYGIENE_CORPUS_CASES and the main registrations of the definition file, compares the list with the 29 names in order and the union with the baseline main list (disjoint), and runs check-test-registration.mjs over tests/skills | `sed:s/(?<=\n)  test_562_no_nul_in_tracked_text\n//` on tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-3332 | Spec-AC-03 | integration | tests/skills/test-aai-suite-reuse.sh | test_3332_win_fallback_partition reads ALL_TESTS and WIN_FALLBACK_CORPUS_TESTS, compares them with the baseline list and the five numbers, and checks with a stubbed case runner that main without arguments runs ALL_TESTS minus the five and the corpus suite runs the five | `sed:s/WIN_FALLBACK_CORPUS_TESTS="007 /WIN_FALLBACK_CORPUS_TESTS="/` on tests/skills/test-aai-win-fallback.sh | green |
| TEST-3333 | Spec-AC-04 | e2e | tests/skills/test-aai-suite-reuse.sh | test_3333_corpus_suite_bites clones PROJECT_ROOT, overlays the working tree's tests/skills and .aai, commits a text file with a NUL byte, runs the clone's test-aai-hygiene-corpus.sh (exit 1, FAIL from test_562) and test-aai-hygiene-pack.sh (exit 0) | `sed:s/for fn in \$HYGIENE_CORPUS_CASES; do/for fn in ; do/` on tests/skills/test-aai-hygiene-corpus.sh | green |
| TEST-3334 | Spec-AC-04 | integration | tests/skills/test-aai-suite-reuse.sh | test_3334_dispatch_both_ways runs test_117_source_skills_are_lf_pinned through the definition file and through the corpus suite, test_029 through both win-fallback files, each exit 0, and checks that the hygiene main body names no corpus case | `patch:docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3334.patch` inserts the line `  test_117_source_skills_are_lf_pinned` after the `test_120_userguide_catalog_covers_every_skill` line of main in tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-3335 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | test_3335_split_selection reads the core list from the real map (exactly five, in order), feeds a docs-only path and a script path to the real selector (CORE aai-hygiene-corpus each), and feeds every glob path of the aai-win-fallback row (a concrete file for each wildcard) expecting lines for both win-fallback suites and no FULL_RUN | `sed:s/(?<=\n  - )aai-hygiene-corpus(?=\n)/aai-hygiene-corpus-gone/` on tests/skills/suite-map.yaml | green |
| TEST-3336 | Spec-AC-06 | contract | tests/skills/test-aai-suite-reuse.sh | test_3336_split_manifest runs lint on the live repository (exit 0), counts thirteen manifest entries including both corpus suites, checks the five index-reading notes name the run ledger and the two fixture-half notes do not say the git index is read | `sed:s/"aai-win-fallback-corpus": \{/"aai-win-fallback-korpus": {/` on tests/skills/suite-reuse.json | green |
| TEST-3337 | Spec-AC-07 | contract | tests/skills/test-aai-suite-reuse.sh | test_3337_split_admission judges the live admission output of TEST-3276 (or runs it when dispatched alone): ADMIT-PASS with poisoned greater than 0 for both fixture halves, ADMIT-PASS and the appended probe PASS for both corpus suites, ADMIT-OFF ci under CI | `patch:docs/ai/tdd/spec-reuse-split-corpus-cases/mutation-TEST-3337.patch` inserts the line `  test_562_no_nul_in_tracked_text` after the `test_120_userguide_catalog_covers_every_skill` line of main in tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-3338 | Spec-AC-07 | inspection | tests/skills/test-aai-suite-select.sh | test_3338_split_weights_rows counts exactly one weights row and one unsampled sample line per new suite, one suite-map row per new suite file, both new files in the aai-suite-reuse globs, and runs auditWeights over every test-aai-*.sh name | `sed:s/(?<=\n)aai-win-fallback-corpus\t212\n//` on tests/skills/suite-weights.tsv | green |
| TEST-3339 | Spec-AC-08 | performance | tests/skills/test-aai-suite-reuse.sh | test_3339_split_measurement parses the before and after sample rows for E1 and E2, recomputes the four medians, checks the REUSED and RUN outcomes per suite of Spec-AC-08, the 0.85 bound, the two 40-character shas and the version lines | `sed:s/## Measurements \(corpus split\)/## Measurementz (corpus split)/` on docs/analysis/precise-suite-evidence-reuse.md | green |

Test-file note: every row's selector is a function in the named suite that
runs alone under single-function dispatch, because `mutation-run.mjs` runs
bash suites only and dispatches one function. Every failure message names the
row's TEST id. TEST-3333 stops at the first failing corpus case (the list
reaches test_562 after about 8 s); the clean-tree runs of Spec-AC-04 are the
suites' own green runs, not repeated inside TEST-3333.

RED plan, observed on the baseline before each change and stored under
`docs/ai/tdd/reuse-split-corpus-cases/red/`:

- TEST-3331, TEST-3332, TEST-3334: the lists and corpus suite files do not
  exist.
- TEST-3333: the corpus suite file does not exist (exit 127, not 1).
- TEST-3335: the core list has four names; no aai-win-fallback-corpus row.
- TEST-3336, TEST-3337: eleven entries; hygiene-pack and win-fallback notes
  claim an index read; no corpus entries.
- TEST-3338: no weights rows for the new suites.
- TEST-3330, TEST-3339: no note section.

Mutation semantics: `mutation-run.mjs` applies the pattern as a JavaScript
RegExp to the first match in the whole file, so each literal a mutation names
must first occur at its decisive site (D2 fixes the list and loop literals);
if the implementation cannot place one so, the row's mutation is amended
additively with disclosure, never dropped.

TDD run split (about three ACs per run): Run A Spec-AC-02, Spec-AC-03,
Spec-AC-04 (TEST-3331 to TEST-3334); Run B Spec-AC-05, Spec-AC-06,
Spec-AC-07 (TEST-3335 to TEST-3338); Run C Spec-AC-01, Spec-AC-08
(TEST-3330, TEST-3339).

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-hygiene-pack.sh`, `test-aai-hygiene-corpus.sh`,
  `test-aai-win-fallback.sh`, `test-aai-win-fallback-corpus.sh`,
  `test-aai-suite-select.sh`, `test-aai-suite-reuse.sh` (includes the live
  admission of the changed manifest suites, several minutes),
  `test-aai-lightweight-lane.sh`, `test-aai-delta-stage3.sh`; plus
  `node .aai/scripts/select-suites.mjs --base-ref main` selected plus CORE.
  No full sweep in intermediate rounds. Restore
  `docs/ai/tests/test-runs.jsonl` after every run. Never git stash.
- `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- `node .aai/scripts/suite-reuse.mjs lint --admit --changed-since main`
  output stored under `docs/ai/tdd/reuse-split-corpus-cases/`.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exit 0 before close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Post-PR checks (not Spec-ACs, not claimed by local Validation)

- H1: the PR head's skill-suite run concludes success, with
  aai-hygiene-corpus in its core set and `ADMIT-OFF ci` in the aai-suite-reuse job.
- H2: a later weights reseed replaces the two unsampled rows with measured
  ones (not this ride).

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

1. Product doc `docs/product/precise-suite-evidence-reuse.md`, Limits: the
   fixture halves of aai-hygiene-pack and aai-win-fallback are reused after an
   edit outside their read set; aai-spec-lint, aai-prompt-diet and
   aai-docs-content are not split and why; the
   `fu-reuse-split-corpus-cases` sentence is replaced.
2. `docs/product/ci-test-impact-selection.md` core line (pinned by TEST-2311).
3. CHANGELOG.md: one `## [unreleased] — <title>` heading entry.
4. Close `fu-reuse-split-corpus-cases`.
5. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/reuse-split-corpus-cases/red/, a mutation record per Test Plan
row under docs/ai/tdd/spec-reuse-split-corpus-cases/, and green suite outputs.
A REUSED suite line is not evidence for any row of this spec: its suites run
with `AAI_SUITE_REUSE=0`.

## Files Implementation touches

- tests/skills/test-aai-hygiene-pack.sh
- tests/skills/test-aai-hygiene-corpus.sh (new)
- tests/skills/test-aai-win-fallback.sh
- tests/skills/test-aai-win-fallback-corpus.sh (new)
- tests/skills/suite-map.yaml
- tests/skills/suite-reuse.json
- tests/skills/suite-weights.tsv
- tests/skills/test-aai-suite-reuse.sh
- tests/skills/test-aai-suite-select.sh
- docs/analysis/precise-suite-evidence-reuse.md
- docs/issues/CHANGE-DRAFT-reuse-split-corpus-cases.md
- docs/specs/SPEC-DRAFT-spec-reuse-split-corpus-cases.md
- docs/product/precise-suite-evidence-reuse.md (close-out)
- docs/product/ci-test-impact-selection.md (close-out, TEST-2311 line)
- CHANGELOG.md (close-out)
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (local evidence)

No `.aai/**` file changes (no PROFILES.yaml entry and no prompt-diet ledger
entry owed). Not touched: tests/skills/test-framework.sh,
.aai/scripts/suite-reuse.mjs, .aai/scripts/lib/checkout-trace.mjs,
.aai/scripts/select-suites.mjs, the three unsplit suites, every
protected_paths_l3 file.

## Risks and rollback

- R1 False hit: a fixture-half case that reads a file through a channel the
  access trace does not see (a stat-only check, an APFS clone, an environment
  variable; SPEC-0268 D3 caveat) would be reported REUSED. The admission
  poisoned run (Spec-AC-07) overwrites every unread checkout file and requires
  a pass; a stat-only read of a file that exists either way stays outside.
- R2 Lost coverage: a case dropped from both halves. Spec-AC-02 and
  Spec-AC-03 partition against the baseline lists.
- R3 Order dependence: a case that relied on setup done by an earlier case
  now in the other half (measured: test_120 on `TEST_DIR`). Both halves'
  green full runs and the single-case dispatch of TEST-3334 cover it.
- R4 Weights: the two unsampled rows use 212 s, which overstates the new
  suites until a reseed; shard balance in full CI runs may skew.
- R5 Admission cost: a change to either definition file re-admits two suites
  (aai-hygiene-pack and its corpus half run about three times each).
- Rollback: revert the PR; `AAI_SUITE_REUSE=0` disables reuse;
  deleting `tests/skills/results/reuse/` is always safe.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list --status open` (288 open) has these
reuse items: `fu-reuse-split-corpus-cases` is this scope and is closed by it
at delivery (aai-spec-lint, aai-prompt-diet and aai-docs-content are left
unsplit on measured evidence, D1). `fu-reuse-docs-closure-suites` stays open
(EVENTS and STATE churn and shared-library literals are untouched). Out of
scope and left open: `fu-reuse-record-max-age`,
`fu-reuse-distro-exported-functions`, `fu-reuse-overlaps-mutation`,
`fu-reuse-arm-dir-nonexist-case`, `fu-prompt-diet-fixture-real-root-race`.

## Registry items closed by this scope

fu-reuse-split-corpus-cases
