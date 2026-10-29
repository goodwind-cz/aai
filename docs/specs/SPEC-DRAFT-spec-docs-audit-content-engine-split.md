---
id: spec-docs-audit-content-engine-split
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: ba1f7afe83402b5e7ce4bb64937df5f4345e77c03c6fe004acdb801f3323e08e
ceremony_level: 2
links:
  requirement: docs-audit-content-engine-split
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Split always-on document-content checks from docs-audit engine regression

SPEC-FROZEN: true

## Links

- Requirement: [Content/engine split intake](../issues/CHANGE-DRAFT-docs-audit-content-engine-split.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md), phase 2,
  owner order item 3 (2026-10-22).
- Prior children: [SPEC-0241](SPEC-0241-spec-docs-audit-node-test-pilot.md),
  [SPEC-0245](SPEC-0245-spec-docs-audit-suite-speed.md) and
  [its note](../analysis/docs-audit-suite-speed.md).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only; Bash 3.2 and GNU Bash).
- Baseline commit: `c3e706e71e16ef041269002b08634bdae8612d02` (main at planning time).

## Implementation strategy

- Strategy: hybrid
- Rationale: the selection change (core list, globs, companion) and the case
  split decide what a pull request is tested with, so every row that guards
  selection, inventory or the content gate goes RED first and carries a
  mutation record (TDD). The Node gate batch follows the closeout precedent
  (TDD). The measurement note, the RFC row and the product line are evidence
  work done in loop mode, but their consistency rows are still mutation-gated.
  No production behavior changes: `.aai/` stays byte-identical to the baseline.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the checkout is shared with other sessions; the suites
  regenerate the real `docs/INDEX.md` during runs (restore floor), the
  measurement needs two disposable checkouts and about 15 minutes of paired
  runs, and mutation runs need a quiet tree. Not protected L3 surfaces, so not
  required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the file list in "Files Implementation touches" below.
- Code review required: true.

## What Planning measured

All numbers below were measured on the baseline in a scratch clone
(macOS arm64, Node 22.23.1, Bash 3.2.57) and are planning inputs, not
attestations of the implementation.

- Per-function profile of every function `main()` runs (195 entries), one
  pass under a monotonic timer: total 117.8 s on a loaded host (the SPEC-0245
  ordinary-run median was 79.3 s on a quiet one).
- The 23 functions that read the live repository corpus as their subject
  (list in "Case classification") sum to 31.3 s, 27% of the total.
- Hosted CI weights (`tests/skills/suite-weights.tsv`): `aai-docs-audit` 212 s,
  the largest single always-on cost. A document-only pull request today runs it
  through the `core:` list in `tests/skills/suite-map.yaml`; `docs/rfc/**` maps
  to no other suite.
- The second content gate already exists and blocks: `.github/workflows/docs-numbering.yml`
  runs `docs-audit.mjs --check --strict --no-event` in the job
  "doc-numbering guards (report-only unless enforced)", `docs/ai/docs-audit.yaml`
  sets `doc_number_guard: enforce`, so the enforce step fails on `audit_rc != 0`,
  and that job is a required status check on `main` (`gh api .../required_status_checks`).
  It covers only the strict audit exit code; the corpus pins in the suite
  (committed index staleness, body lint 0, near-miss set, docs/ai canon,
  product lifecycle, named closed documents) are not covered there. That is
  why the content cases move to a new always-on suite instead of relying on
  the workflow alone.
- Node candidates, measured as fixture setup versus CLI versus in-process:
  the false-open cluster (14 functions, 4.9 s) spends about 165 ms per case on
  git fixture setup that a Node test would still pay, against about 70 ms
  saved per CLI launch, so it stays in Bash. The `--gate`-only cluster
  (5 functions, 0.97 s, 15 CLI launches, no commit needed) calls the exported
  `gateDoc` and is moved.

## Scope and design

### D1. Two suites, one definition file

- `tests/skills/test-aai-docs-audit.sh` keeps every function definition and
  helper. It gains one declared list, `DOCS_AUDIT_CONTENT_CASES`, naming the
  content cases one per line with a two-space indent, in baseline `main()`
  order. Its `main()` registers the engine cases only, one per line with a
  two-space indent (the format TEST-2211 reads). Single-function dispatch
  (`bash tests/skills/test-aai-docs-audit.sh <function>`) keeps working for
  every function, content cases included.
- New `tests/skills/test-aai-docs-content.sh` (suite `aai-docs-content`)
  sources the definition file, sets its own `TEST_NAME`, runs `check_deps`,
  arms the INDEX restore floor before any real-index generation, runs every
  name in `DOCS_AUDIT_CONTENT_CASES` in order, and supports single-function
  dispatch. It exits 0, 1 or 42 with the same meaning as every suite and
  prints `PASS: All aai-docs-content tests passed` on success.
- A full run executes each case exactly once (content cases in the content
  suite, engine cases in the engine suite). Nothing runs nested.

### D2. Case classification

A case is **content** when its assertion reads the live repository corpus
under `docs/` as its subject (it calls `live_audit` or `live_index_pair` on
the real root, depends on `setup_indexarm_snapshots`, or launches docs-audit or
reads a document under `$PROJECT_ROOT/docs/`), so a document-only change can
turn it red. Mixed functions (fixture arms plus a live arm) move whole; no
assertion is edited. The minimum content set is these 23 functions (setup
and dependency closure included):

check_deps, setup_fixture, test_deterministic_index_no_clock_line,
test_1351_live_corpus_near_miss_set_is_dispositioned,
test_1348_near_miss_headline_carries_the_count,
test_1349_verdict_names_the_unreadable_tables,
test_spec0006_no_regression_real_repo, test_change0166_closeout_is_clean_and_terminal,
test_534_two_stale_halves_are_closed, setup_indexarm_snapshots,
test_indexarm_earlier_day_generation_is_green, test_indexarm_index_is_not_stale,
test_indexarm_overdue_boundary_is_green, test_issue0001_no_regression_real_repo,
test_spec0011_regression, test_537_shape_check_live_yield,
test_change0007_regression, test_change0012_regression,
test_docsaicanon_real_repo_clean, test_change0028_real_repo_clean,
test_spec0057_real_repo_known_collisions, test_pdcm_product_family_repo_wide_clean,
test_acflip_real_repo_clean.

`check_deps` and `setup_fixture` run in both suites (setup, not cases). A
case outside that list joins the content set only when the rule above holds
and the note says why. Everything else is **engine**. Two named exceptions
stay engine although they read the real tree: `test_histmap_corpus_equivalence`
(compares two engine implementations of first-commit dates over the same
corpus; only an engine defect can make them disagree) and the helper
self-tests that run against a fixture root through `live_test_enter`
(TEST-2202 to TEST-2205).

### D3. Selection

- `tests/skills/suite-map.yaml` `core:` becomes exactly `aai-check-state`,
  `aai-docs-content`, `aai-spec-lint`, `aai-hygiene-pack` (comment explains
  the swap and points at this spec).
- New row `aai-docs-content` with the document globs moved from
  `aai-docs-audit`: `docs/decisions/**`, `docs/specs/**`, `docs/issues/**`,
  `docs/rfc/**`, `docs/canonical/**`, `docs/_archive/**`, `docs/releases/**`
  (core suites' globs keep these paths mapped, so they never fall to an
  unmapped FULL_RUN).
- `aai-docs-audit` keeps every engine glob and adds:
  `tests/skills/test-aai-docs-content.sh`, `tests/skills/lib/docs-audit-gate.test.mjs`,
  `docs/analysis/docs-audit-content-engine-split.md`, and every further
  real-tree path an engine case reads (input closure, TEST-2306), for example
  `docs/USER_GUIDE.md` and `.claude/skills/aai-docs-audit/SKILL.md` unless the
  case reading them is reclassified content.
- `aai-delta-stage3` declares `aai-docs-audit` as a companion (its
  TEST-007 relied on docs-audit being core).
- `tests/skills/suite-weights.tsv` gets one `aai-docs-content` row with the
  file's existing provenance convention (`fallback unsampled` at the documented
  maximum until hosted runs exist). No other weight changes.
- `.aai/scripts/lib/**` stays a shared-lib FULL_RUN trigger; protected L3 and
  unmapped triggers are unchanged (fail-open triad intact).

### D4. Node gate batch

Move these five `--gate`-only Bash functions to `node:test` cases in
`tests/skills/lib/docs-audit-gate.test.mjs` over the exported `gateDoc`
(fixture files written to a temp dir, no git commits), keeping every clause
each asserted (migration map G1 to G5 in the note):
`test_l1gate_missing_justification`, `test_l1gate_garbage_level_fail_closed`,
`test_l1gate_pipe_drop_reconciled`, `test_gateac_canonical_pipe_drop_reconciled`,
`test_gateac_lean_volunteering_full_table`. Retained CLI owners stay in Bash
unchanged: `test_l1gate_lean_gate_pass` (exit codes of `--gate` and
`--gate-file`, row named on failure) and `test_gateac_issue330_crosscheck`
(spec-lint and `--gate` agree). A new engine function `test_2308_gate_node`
runs the Node file once from PROJECT_ROOT and fails naming TEST-2308 when any
case fails. Mixed `--check` functions in that area stay in Bash.

### D5. Measurement note

`docs/analysis/docs-audit-content-engine-split.md` carries:

- `## Case inventory`: one row per baseline `main()` entry (195) with columns
  Function, Class (content, engine, node), Owner (suite file or Node case id).
- `## Paired measurement`: five alternating pairs, baseline clone (B) versus
  candidate clone (F), same host and wrapper. Per pair: before suite seconds,
  after engine suite seconds, after content suite seconds. Then the lines
  `Before median: <s>`, `Before worst: <s>`, `Engine median: <s>`,
  `Engine worst: <s>`, `Content median: <s>`, `Content worst: <s>`,
  `Content ratio: <x>` (content median divided by before median, 2 decimals).
- `## Gate batch measurement`: five paired matched runs of the five Bash
  functions (B) versus `node --test tests/skills/lib/docs-audit-gate.test.mjs`
  (F), then `Gate before median: <s>`, `Gate after median: <s>`,
  `Gate ratio: <x>`; and the migration map G1 to G5.
- `## Remaining Bash clusters`: the measured reason each remaining fixture
  cluster stays in Bash (git-fixture dominated or CLI boundary).
- `## Selection`: the selector output for one document-only fixture diff
  before and after, and the hosted weights used, reported, not gated.

### Out of scope

Phase 5, changes to what docs-audit checks, its exit codes or findings, any
file under `.aai/`, the release-notes gate and the `watch-ci` issues of
2026-10-29, reseeding hosted weights.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (inventory, classes, paired timing).
- Intake AC-002 maps to Spec-AC-02 (document-only diff selects no engine suite).
- Intake AC-003 maps to Spec-AC-03 (planted content violation still fails the
  always-on content suite).
- Intake AC-004 maps to Spec-AC-04 (engine inputs select the engine suite;
  input closure).
- Intake AC-005 maps to Spec-AC-05 (case inventory equal, production unchanged).
- Intake AC-006 maps to Spec-AC-06 (Node gate batch, matched timing).
- Intake AC-007 maps to Spec-AC-07 (RFC-0017 Rollout Status).
- Spec-AC-08 adds the wiring seams the split crosses (core list, companion,
  weights row, product doc line).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | The note docs/analysis/docs-audit-content-engine-split.md lists all 195 baseline main entries each with exactly one class, reports five alternating paired runs with before, engine and content medians and worst values, and its Content ratio line is at most 0.40 and equals content median over before median within 0.01. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-audit.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/measurement/results.json ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2301.txt | — | TEST-2301 |
| Spec-AC-02 | WHEN select-suites.mjs runs on the real map with a changed-path list of only docs/issues, docs/specs, docs/rfc and docs/decisions documents plus docs/INDEX.md, the system SHALL print CORE aai-docs-content, no line naming aai-docs-audit and no FULL_RUN line. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-suite-select.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-lightweight-lane.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/selector-rfc.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2302.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2303.txt | — | TEST-2302, TEST-2303 |
| Spec-AC-03 | WHEN the content suite runs in a disposable clone whose only change is a committed document under docs/issues without frontmatter together with a regenerated index, the system SHALL exit 1 with a FAIL line naming the orphan finding; the content suite on the unmodified tree exits 0. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-audit.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2304.txt | — | TEST-2304 |
| Spec-AC-04 | WHEN select-suites.mjs runs on each engine input (docs-audit.mjs, lib/docs-audit-core.mjs, docs/ai/docs-audit.yaml, generate-docs-index.mjs, SKILL_DOCS_AUDIT.prompt.md, both docs-audit suite files, docs-audit-live.sh, each docs-audit test.mjs file), the system SHALL print SELECTED aai-docs-audit or FULL_RUN; every literal real-tree path an engine case reads SHALL do the same, and no engine case outside the named exceptions reads the live docs corpus. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-suite-select.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-audit.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2305.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2306.txt | — | TEST-2305, TEST-2306 |
| Spec-AC-05 | The engine main registrations, DOCS_AUDIT_CONTENT_CASES and the five Node-moved names together equal the baseline main list with no name in two places; check-test-registration.mjs exits 0; both suites exit 0 through the wrapper; git diff against the baseline over .aai is empty. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-audit.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-content.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/registration.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2307.txt | — | TEST-2307 |
| Spec-AC-06 | WHEN the engine suite runs, the system SHALL run docs-audit-gate.test.mjs once and fail naming TEST-2308 when any case fails; the five moved functions are neither defined nor registered, both retained CLI owners are defined and registered once, and the note's Gate ratio is at most 0.50 and matches its two medians within 0.01. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/gate-node.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-audit.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/measurement/results-gate.json ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2308.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2309.txt | — | TEST-2308, TEST-2309 |
| Spec-AC-07 | The RFC-0017 Rollout Status phase 2 row reads done and links this change's intake and note, the phase 4 row links CHANGE-0228, and the RFC frontmatter still reads status implementing with umbrella true. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-docs-content.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2310.txt | — | TEST-2310 |
| Spec-AC-08 | The suite-map core list is exactly aai-check-state, aai-docs-content, aai-spec-lint, aai-hygiene-pack; suite-weights.tsv has exactly one aai-docs-content row; the product doc ci-test-impact-selection.md names the same core list; aai-delta-stage3 selects aai-docs-audit as a companion. | planned | docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-suite-select.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-delta-stage3.txt ; docs/ai/tdd/docs-audit-content-engine-split/green_final/test-aai-hygiene-pack.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2311.txt ; docs/ai/tdd/spec-docs-audit-content-engine-split/mutation-TEST-2312.txt | — | TEST-2311, TEST-2312 |

## Implementation plan

1. Before record: keep Planning's profile as input only; build a disposable
   baseline clone at the baseline commit (never the shipping tree) for paired
   timing; extract the baseline `main()` list (195 names).
2. TDD the selection rows first (TEST-2302, TEST-2303, TEST-2305, TEST-2311,
   TEST-2312): write them against the current map, observe RED, then change
   `suite-map.yaml` (D3) and the weights row.
3. TDD the split (TEST-2307, TEST-2306, TEST-2304): add
   `DOCS_AUDIT_CONTENT_CASES`, trim the engine `main()`, add the content suite
   file, then the e2e planted-violation test.
4. TDD the Node gate batch (TEST-2308): write the Node file, observe it run,
   remove the five functions and their registrations.
5. Measure (D5), write the note (TEST-2301, TEST-2309), update RFC-0017
   (TEST-2310), the product doc line, the workflow comment that names the core
   set in `.github/workflows/skill-suite.yml`, and a CHANGELOG entry headed
   `## [unreleased] — test(ci): ...`.
6. Run the touched suites, `check-test-registration.mjs`, the mutation rows,
   then one full sweep before close.

Seams crossed:

- suite-map.yaml (producer) and select-suites.mjs plus the CI selected plan
  (consumer): TEST-2302, TEST-2303 and TEST-2305 feed fixture path lists to the
  REAL selector over the REAL map and assert its printed lines.
- The definition file (producer of case functions and the content list) and
  the content suite (consumer that sources and runs it): TEST-2304 runs the
  real content suite entry in a clone and observes its exit code; TEST-2307
  checks that the two registrations partition the baseline list.
- Engine cases reading real-tree files (consumer) and suite-map globs
  (producer of selection): TEST-2306 derives the read paths from the suite
  text and runs them through the selector.
- The delta-stage3 suite relied on docs-audit being core: TEST-2312 is its
  existing `test_007_seam_survival`, which goes RED when the core swap lands
  without the companion.
- `gateDoc` (producer, exported) and the CLI renderer of `--gate` (consumer):
  the Node cases assert the structured reasons; the retained CLI owners keep
  the exit codes and rendered row names.
- The lightweight-lane gate trusts that a docs-only close diff routes to core:
  TEST-2303 updates its pin to the new core suite.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2301 | Spec-AC-01 | inspection | tests/skills/test-aai-docs-audit.sh | test_2301_split_note_inventory parses the note: Case inventory rows equal the baseline main list from git show of the baseline commit (or fails naming TEST-2301 when the commit is absent), each row has one class, five pair rows exist, recomputed medians and worst values match the lines, Content ratio at most 0.40 | `sed:s/test_indexarm_index_is_not_stale/test_indexarm_index_is_not_staleX/` on docs/analysis/docs-audit-content-engine-split.md | pending |
| TEST-2302 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | test_2302_doc_only_selects_content_not_engine feeds four document paths plus docs/INDEX.md to the real selector and map; asserts CORE aai-docs-content, no aai-docs-audit line, no FULL_RUN | `sed:s/(?<=\n  - )aai-docs-content(?=\n)/aai-docs-audit/` on tests/skills/suite-map.yaml | pending |
| TEST-2303 | Spec-AC-02 | integration | tests/skills/test-aai-lightweight-lane.sh | test_017_docs_only_close_diff_never_full now asserts CORE aai-docs-content and no aai-docs-audit line for the close-commit diff, still never FULL_RUN | `sed:s/(?<=\n  - )aai-docs-content(?=\n)/aai-docs-audit/` on tests/skills/suite-map.yaml | pending |
| TEST-2304 | Spec-AC-03 | e2e | tests/skills/test-aai-docs-audit.sh | test_2304_content_suite_fails_on_planted_orphan clones PROJECT_ROOT into TEST_DIR, overlays the working tree's tests/skills and .aai, commits a frontmatter-less docs/issues document and the regenerated index, runs the clone's test-aai-docs-content.sh and asserts exit 1 and a FAIL line naming Orphans | `sed:s/const orphans = docs\.filter\(d => d\.cls === 'orphan'\);/const orphans = [];/` on .aai/scripts/lib/docs-audit-core.mjs | pending |
| TEST-2305 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | test_2305_engine_inputs_select_engine feeds each engine input path separately to the real selector; each output has SELECTED aai-docs-audit or FULL_RUN | `sed:s/(?<=\n      - )\.aai\/scripts\/docs-audit\.mjs(?=\n)/.aai\/scripts\/docs-audit.mjs.unused/` on tests/skills/suite-map.yaml | pending |
| TEST-2306 | Spec-AC-04 | inspection | tests/skills/test-aai-docs-audit.sh | test_2306_engine_input_closure extracts literal PROJECT_ROOT paths (plain, quoted, or relative inside a cd PROJECT_ROOT subshell) read by engine-registered functions, runs each through the real selector (SELECTED aai-docs-audit or FULL_RUN), and fails when an engine function outside the named exceptions calls live_audit, live_index_pair or reads PROJECT_ROOT docs | `sed:s/(?<=\n)      - \.aai\/scripts\/select-suites\.mjs\n//` on tests/skills/suite-map.yaml | pending |
| TEST-2307 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | test_2307_case_inventory_partition compares engine main registrations, DOCS_AUDIT_CONTENT_CASES and the five Node-moved names with the baseline main list (equal, disjoint), and runs check-test-registration.mjs over tests/skills | `sed:s/(?<=\n)  test_orphan_split\n//` on tests/skills/test-aai-docs-audit.sh | pending |
| TEST-2308 | Spec-AC-06 | unit | tests/skills/test-aai-docs-audit.sh | test_2308_gate_node runs node --test tests/skills/lib/docs-audit-gate.test.mjs from PROJECT_ROOT and fails naming TEST-2308 when any G1 to G5 case fails; also checks the five moved functions are gone and the two retained owners are defined and registered once | `sed:s/requires a "Ceremony justification: ..." body line/requires a justification line/` on .aai/scripts/lib/docs-audit-core.mjs | pending |
| TEST-2309 | Spec-AC-06 | performance | tests/skills/test-aai-docs-audit.sh | test_2309_gate_batch_measurement recomputes both gate medians from the five pair rows, checks the Gate ratio line matches within 0.01 and is at most 0.50, and that G1 to G5 each name a removed function and a Node case | `sed:s/Gate after median: /Gate after: /` on docs/analysis/docs-audit-content-engine-split.md | pending |
| TEST-2310 | Spec-AC-07 | inspection | tests/skills/test-aai-docs-audit.sh | test_2310_rfc0017_rollout_rows reads the RFC: phase 2 row status done with links to this intake and the note, phase 4 row links CHANGE-0228, frontmatter status implementing and umbrella true | `sed:s/CHANGE-0228-provider-adapter-registry-slice\.md/CHANGE-0228-missing.md/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |
| TEST-2311 | Spec-AC-08 | inspection | tests/skills/test-aai-suite-select.sh | test_2311_core_list_weights_product_doc reads the core list from the real map (exactly four names in order), counts one aai-docs-content weights row, and checks the product doc line names the same four core suites | `sed:s/aai-docs-content/aai-docs-audit/` on docs/product/ci-test-impact-selection.md | pending |
| TEST-2312 | Spec-AC-08 | integration | tests/skills/test-aai-delta-stage3.sh | existing test_007_seam_survival: assert_companions requires aai-docs-audit selected or core for the delta-stage3 test file; RED observed when the core swap lands before the companion entry | `sed:s/(?<=\n      - )aai-docs-audit(?=\n)/aai-docs-audit-gone/` on tests/skills/suite-map.yaml | pending |

Test-file note: every row's selector is a function in the named suite that
runs alone under single-function dispatch (`bash <suite> <function>`), because
`mutation-run.mjs` runs bash suites only and dispatches one function. Every
failure message names that row's TEST id. The Node file is reached through
`test_2308_gate_node`. TEST-2304 runs a whole content suite inside a clone, so
it adds about 30 s to the engine suite; that is accepted because the engine
suite now runs only on engine changes and full runs.

### RED observations and negative controls

- TEST-2302, TEST-2303, TEST-2305 (the engine prints as CORE, not SELECTED,
  and the docs/rfc control still reaches it), TEST-2311 and TEST-2312 are RED
  on the pre-change map; record each run under
  `docs/ai/tdd/docs-audit-content-engine-split/red/`.
- TEST-2304, TEST-2306, TEST-2307, TEST-2308 are RED because the content suite,
  the list or the Node file do not exist yet. TEST-2304 also has a negative
  control: the same clone without the plant exits 0 once (recorded, not
  repeated in the suite).
- TEST-2301, TEST-2309 and TEST-2310 are RED until the note and the RFC rows
  exist.
- Positive controls: TEST-2305 includes one non-engine path (for example
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`) that must NOT
  select aai-docs-audit, so a map that selects the engine for everything fails
  it.

## Verification

- Engine suite: `env -u AAI_ROLE AAI_TEST_TIMEOUT=1200 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
  exits 0 and prints `PASS: All aai-docs-audit tests passed`.
- Content suite: `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-content.sh`
  exits 0 and prints `PASS: All aai-docs-content tests passed`.
- Selection and wiring suites: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh`,
  the same for `test-aai-lightweight-lane.sh`, `test-aai-delta-stage3.sh` and
  `test-aai-hygiene-pack.sh` (suite-map row pin, pipe-grep-q ratchet), each exit 0.
- Node file alone: `bash .aai/scripts/aai-run-tests.sh node --test tests/skills/lib/docs-audit-gate.test.mjs` exits 0.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Selector spot checks: `printf 'docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md\n' | node .aai/scripts/select-suites.mjs --files-from -`
  prints `CORE aai-docs-content reason=core` and no `aai-docs-audit`.
- Production unchanged: `git diff --quiet c3e706e71e16ef041269002b08634bdae8612d02 -- .aai/` exits 0.
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'`
  per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- One full sweep before close (`AAI_TEST_TIMEOUT=3600`).

### Measurement design (Spec-AC-01, Spec-AC-06)

Before (B) is the baseline commit in a disposable clone with its own git
directory; after (F) is the candidate in another. Same host, Node, Bash, Git,
wrapper and serial width. One untimed warm-up per side, then five pairs
alternating B then F and F then B, external monotonic wall seconds rounded to
0.1 s. B runs the ordinary docs-audit suite; F runs the engine suite and the
content suite back to back, each timed separately. Every attempt is disclosed;
a failed run voids its pair and the pair is rerun after diagnosis. Hosted CI
durations are reported only.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/docs-audit-content-engine-split/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. Planning's measurements are inputs, not attestations.

## Files Implementation touches

- tests/skills/test-aai-docs-audit.sh
- tests/skills/test-aai-docs-content.sh (new)
- tests/skills/lib/docs-audit-gate.test.mjs (new)
- tests/skills/suite-map.yaml
- tests/skills/suite-weights.tsv
- tests/skills/test-aai-suite-select.sh
- tests/skills/test-aai-lightweight-lane.sh
- docs/analysis/docs-audit-content-engine-split.md (new)
- docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
- docs/product/ci-test-impact-selection.md
- .github/workflows/skill-suite.yml (comment naming the core set only)
- CHANGELOG.md
- docs/issues/CHANGE-DRAFT-docs-audit-content-engine-split.md
- this spec; docs/INDEX.md (regenerated)

Not touched: anything under `.aai/`; `tests/skills/test-aai-delta-stage3.sh` is
touched only in one failure message (A1-l; its pin already holds once the companion exists).

## Assumptions (autopilot, no owner question)

- A1. A content case moves whole even when it also has fixture arms; no
  assertion is split or rewritten in this slice.
- A2. The docs-numbering job stays as it is; it is a second, narrower gate,
  not the always-on content suite.
- A3. Phase 2 of RFC-0017 is marked done by this delivery: the split lands,
  the last measured-beneficial Node cluster moves, and the note records why the
  remaining clusters stay in Bash. If Validation finds a remaining cluster with
  a measured benefit above 1 s per ordinary run, phase 2 stays in progress and
  the note says so (TEST-2310 then asserts that wording instead, via a recorded
  amendment).
- A4. Phase 4 keeps its current status; only the CHANGE-0228 link is added.
- A5. The new suite's weights row uses the fallback convention; a hosted
  reseed is a later chore.

## Risks and rollback

- Under-selection: an engine case that reads a real-tree file outside its
  globs would stop running on pull requests that change only that file.
  TEST-2306 guards the literal paths; non-literal reads (globs computed at run
  time) are a residual risk, covered by main and nightly full runs.
- `test_histmap_corpus_equivalence` no longer runs on document-only pull
  requests; an engine defect revealed only by a new document is caught at
  merge to main or nightly, not on the pull request. Disclosed.
- Scheduling: the content suite carries the fallback weight 212 until a
  hosted reseed, so an engine-change pull request may plan two runners where
  it planned one; documented in the note.
- The content suite regenerates the real index like the old suite did; the
  restore floor and cleanup trap apply unchanged.
- Rollback is one revert of the listed files; production code is untouched.

## Registry disposition

Related open registry items, all left open:

- `fu-docs-audit-suite-has-no-selector`: the suite already dispatches one
  function and both suites keep that; retiring the item is registry triage,
  outside this scope.
- `fu-prompt-diet-fixture-real-root-race`: the real-corpus walk now lives in
  the content suite; the race class is unchanged and stays disclosed.

Registry items closed by this scope: none

## Amendment 1 (post-freeze, additive-with-disclosure, no owner sign-off obtained)

Implementation outgrew the literal text of this frozen spec in thirteen places (A1-a to A1-m). The
original text above is kept; where it differs, this section governs. The owner
may accept or reverse it at merge.

- A1-a. The content list holds 24 names, not 23: `test_issue0001_posix_paths_noop`
  reads the `setup_indexarm_snapshots` real-index snapshots, so by the D2 rule it
  is a content case and it moved whole. TEST-2307 asserts 24. TEST-2310 joins the
  list as a new row (it is not a baseline entry, so the partition ignores
  `test_23xx` rows in both suites).
- A1-b. `check_deps` and `setup_fixture` are registered in both suites (setup, not
  cases). TEST-2307 allows exactly these two names to overlap; the inventory
  classes them content with owner "both suites (setup)". After the Node batch the
  five Node-moved names are disjoint from both registrations (TEST-2307 tightened).
- A1-c. TEST-2304 asserts a `FAIL:` line plus `Orphans: [1-9]` in the output rather
  than one FAIL line naming Orphans, because the strict audit prints its headline
  on continuation lines after the FAIL line.
- A1-d. TEST-2306 also excludes `test_2206_no_direct_live_corpus_launch` (it
  inspects the suite text for the live-corpus launch rule, not the corpus) and
  itself, beside the named exceptions of D2.
- A1-e. Selection wiring beyond D3: `docs/INDEX.md` and `docs/ai/EVENTS.jsonl` map
  to the `aai-docs-content` row (the generated index and event ledger are content
  inputs); the `aai-hygiene-pack` row pin moved 118 to 119; every failure message
  names its TEST id; and the `aai-docs-audit` row gained five engine-input globs
  that TEST-2306 found engine cases reading: `.aai/ROLE_COMMON.md`,
  `.aai/scripts/spec-lint.mjs`, `.claude/skills/aai-docs-audit/SKILL.md`,
  `docs/USER_GUIDE.md`, `tests/skills/suite-map.yaml`. TEST-2201 accepts the five
  Node-moved function names in the cost profile of the earlier speed note.
- A1-f. Mutation cells. `mutation-run.mjs` has no `m` regex flag and no delete
  form, so the Mutation cells of TEST-2301 to TEST-2312 are rewritten to the
  substitution or lookbehind forms that were actually run and recorded. Before
  this rewrite `mutation-gate.mjs` read TEST-2301, TEST-2307 and TEST-2312 as
  uncomparable (`mutation_uncomparable actual=3 > baseline=0`) and the other
  rows as declared-versus-recorded mismatches; the cell text is the only thing
  that changed, not the claim each row makes. Records live under
  `docs/ai/tdd/spec-docs-audit-content-engine-split/`.
- A1-g. TEST-2310's selector is defined in the definition file with every other
  function and is listed in `DOCS_AUDIT_CONTENT_CASES`, so the content suite runs it
  and `mutation-run.mjs` (which only accepts a selector defined in the named suite
  file) is pointed at `tests/skills/test-aai-docs-audit.sh` for it; the Test Plan
  File path cell for TEST-2310 now names that definition file too (the mutation
  gate requires the record's suite to equal the cell); the content suite is what
  runs it in a full run.
- A1-h. Measured result (see the note): Content ratio 0.28, Gate ratio 0.07. The
  engine suite median (131.7 s) is not below the old suite median (144.8 s)
  because TEST-2304 runs the content suite in a clone; an engine-input pull request
  now pays both suites, a document-only one pays only the content suite.
- A1-i. TEST-2304 runs a whole suite inside a clone, which the nested-suite lint
  refuses unless the run is allowlisted. `tests/skills/lib/nested-suite-allowlist.tsv`
  gains one row for it (4 rows, was 3) with its reason, and the pin in
  `tests/skills/test-aai-hygiene-pack.sh` (test_133) moves from 3 to 4. This is a
  change to a ratchet that "only shrinks"; the proof the row defends (the suite's
  own list fails on a planted violation) cannot be shown by a selected single case
  or a companion declaration, but the owner may prefer to narrow TEST-2304 instead.
- A1-j. TEST-2306 found `.aai/scripts/check-test-registration.mjs` as one more
  real-tree path an engine case reads (TEST-2307 now calls it by absolute path, since
  the relative `cd` form tripped the cd-in-substitution ratchet); the `aai-docs-audit`
  row of `tests/skills/suite-map.yaml` gained that glob.
- A1-k. Review r1 finding F-B1: TEST-2306 recognised only `$PROJECT_ROOT/<path>` reads and
  missed `(cd "$PROJECT_ROOT" && node .aai/scripts/<x>)` and quoted `"$PROJECT_ROOT"/<path>`
  forms. It now extracts both, and fails when it scanned zero engine functions or zero
  paths (non-vacuous floor). The widened scan was RED on the previous map for
  `.aai/scripts/check-state.mjs` and `.aai/scripts/select-suites.mjs`; the `aai-docs-audit`
  row gained both globs and no further hole was found. The TEST-2306 Mutation cell now
  names removal of the `select-suites.mjs` glob (recorded RED).
- A1-l. Disclosure: `tests/skills/test-aai-delta-stage3.sh` was edited, message text only
  (the TEST-007 failure message cites plan row TEST-2312); no logic changed. The "Not
  touched" list above is read with this exception. The note's 172.4 s for an engine-input pull request
  (engine plus content suite) is a sum of medians; the median of the per-pair sums is 173.0 s.
- A1-m. Disclosure: two earlier-ride pins were updated because this spec delivers RFC-0017
  Rollout Status phase 2 as `done` (Spec-AC-07): `tests/skills/test-aai-expert-fetch.sh`
  (TEST-2623) and `tests/skills/lib/recheck.test.mjs` (TEST-2716 and TEST-2825) pinned
  that row as `in progress`; each now pins `done`, nothing else in them changed. Read the
  "Not touched" list with this exception too. Validation r2 finding F-R2-B1.
